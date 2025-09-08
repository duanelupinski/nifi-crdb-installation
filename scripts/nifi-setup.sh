#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# -------------------------------------------
# nifi-setup.sh (INIT_ENV only, provider-agnostic)
# -------------------------------------------

INIT_ENV=1
INSTALL=2
MAX_STEPS=2

# Defaults (your updated paths)
OPTIND=1
SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
PRIVATE_DIR="${SCRIPT_DIR}/../.private"
TF_DIR="${SCRIPT_DIR}/terraform/multipass/nifi"  # where your TF lives
SSH_KEY="${HOME}/.ssh/id_rsa"                    # will generate if not present
START=$INIT_ENV
END=$INIT_ENV
HELP=false
CLUSTER_PREFIX=""
QUIET=false
DRY_RUN=false
NO_APPLY=false         # if true, skip TF init/plan/apply; just read outputs if present
TRACE=false

# --- INSTALL defaults ---
NIFI_INSTALL_SCRIPT="${SCRIPT_DIR}/nifi-install.sh"   # path to the separate installer
INCLUDE_REGISTRY=false                                # -R/--include-registry
SECURE=false                                          # -S (TLS NiFi ports)
SSH_TIMEOUT=8                                         # forwarded to nifi-install.sh

INSECURE_DOWNLOADS=false
CURL_CACERT=""
DOWNLOAD_CURL_FLAGS=""

JAVA_VERSION="${JAVA_VERSION:-21}"
PGJDBC_VERSION="${PGJDBC_VERSION:-42.7.7}"
ZK_VERSION="${ZK_VERSION:-3.9.4}"
KAFKA_VERSION="${KAFKA_VERSION:-3.9.1}"
SCALA_VERSION="${SCALA_VERSION:-2.13}"

NIFI_VERSION="${NIFI_VERSION:-2.5.0}"
NIFI_TOOLKIT_VERSION="${NIFI_TOOLKIT_VERSION:-2.5.0}"
NIFI_USER="${NIFI_USER:-nifi}"

NIFI_HEAP="${NIFI_HEAP:-3g}"
NIFI_LOG_DIR="${NIFI_LOG_DIR:-/var/log/nifi}"
LOG_MAX_SIZE="${LOG_MAX_SIZE:-256MB}"
LOG_MAX_HISTORY="${LOG_MAX_HISTORY:-14}"

GH_URL="${GH_URL:-}"
GH_USERNAME="${GH_USERNAME:-}"
GH_USERTEXT="${GH_USERTEXT:-}"
GH_EMAIL="${GH_EMAIL:-}"
GH_BRANCH="${GH_BRANCH:-registry}"
GH_DIRECTORY="${GH_DIRECTORY:-nifi-flows}"
GH_REMOTE_NAME="${GH_REMOTE_NAME:-origin}"

# --- helpers ---------------------------------------------------------------

die(){ echo "ERROR: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Missing required tool: $1"; }
log(){ [ "$QUIET" = false ] && echo "$@"; }

mkpath(){ if [ "$DRY_RUN" = true ]; then log "[dry-run] mkdir -p $1"; else mkdir -p "$1"; fi; }
chmod_guard(){ if [ "$DRY_RUN" = true ]; then log "[dry-run] chmod $1 $2"; else chmod "$1" "$2"; fi; }
touch_guard(){ if [ "$DRY_RUN" = true ]; then log "[dry-run] touch $1"; else touch "$1"; fi; }

writefile(){
  local path="$1"; shift
  if [ "$DRY_RUN" = true ]; then log "[dry-run] write $path"; printf "%s\n" "$*"; return 0; fi
  local tmp="${path}.tmp.$$"; printf "%s\n" "$*" > "$tmp"; mv "$tmp" "$path"
}

appendfile(){
  local path="$1"; shift
  if [ "$DRY_RUN" = true ]; then log "[dry-run] append $path"; printf "%s\n" "$*"; return 0; fi
  printf "%s\n" "$*" >> "$path"
}

tf(){
  # wrapper so we always show the exact command in dry-run
  if [ "$DRY_RUN" = true ]; then
    log "[dry-run] terraform -chdir='${TF_DIR}' $*"
    return 0
  fi
  terraform -chdir="$TF_DIR" "$@"
}

tfout(){
  local key="$1"
  jq -r --arg k "$key" '.[$k].value // empty' "${PRIVATE_DIR}/tf-outputs.json" 2>/dev/null || true
}

tfout_array(){
  local key="$1"
  jq -r --arg k "$key" '
    if .[$k].value == null then empty
    elif (.[$k].value | type) == "array" then .[$k].value[] | tostring
    else empty
    end
  ' "${PRIVATE_DIR}/tf-outputs.json" 2>/dev/null || true
}

infer_user_from_ssh_commands(){
  local cmds_json user uniq
  cmds_json="$(jq -r '.ssh_commands.value // empty' "${PRIVATE_DIR}/tf-outputs.json" 2>/dev/null || true)"
  [ -z "$cmds_json" ] && { echo ""; return 0; }
  uniq="$(echo "$cmds_json" \
    | jq -r '.[]? // empty' \
    | sed -nE 's/.*[[:space:]]+([a-zA-Z0-9._-]+)@([a-zA-Z0-9._-]+).*$/\1/p' \
    | sort -u)"
  if [ -n "$uniq" ] && [ "$(echo "$uniq" | wc -l | tr -d ' ')" = "1" ]; then echo "$uniq"; else echo ""; fi
}

hosts_from_instance_names(){
  jq -r '.instance_names.value[]? // empty' "${PRIVATE_DIR}/tf-outputs.json" 2>/dev/null | sed '/^\s*$/d'
}

discover_registry_hostname() {
  # explicit output wins
  local r
  r="$(tfout registry_hostname)"; [ -n "$r" ] && { echo "$r"; return; }
  r="$(tfout registry_host)";     [ -n "$r" ] && { echo "$r"; return; }
  # else scan instance_names
  mapfile -t names < <(jq -r '.instance_names.value[]? // empty' "${PRIVATE_DIR}/tf-outputs.json" 2>/dev/null | sed '/^\s*$/d')
  if [ "${#names[@]}" -gt 0 ]; then
    for n in "${names[@]}"; do
      if echo "$n" | grep -qi 'registry'; then echo "$n"; return; fi
    done
  fi
  echo ""
}

discover_node_hostnames() {
  # prefer explicit nifi_hosts; else fall back to instance_names excluding registry unless requested
  mapfile -t hosts < <(tfout_array nifi_hosts || true)
  if [ "${#hosts[@]}" -eq 0 ]; then
    mapfile -t names < <(jq -r '.instance_names.value[]? // empty' "${PRIVATE_DIR}/tf-outputs.json" 2>/dev/null | sed '/^\s*$/d')
    if [ "${#names[@]}" -gt 0 ]; then
      local reg_match
      reg_match="$(discover_registry_hostname)"
      hosts=()
      for n in "${names[@]}"; do
        if [ "$INCLUDE_REGISTRY" = false ] && [ -n "$reg_match" ] && [ "$n" = "$reg_match" ]; then
          continue
        fi
        # also exclude any item that contains 'registry' if we're not including registry
        if [ "$INCLUDE_REGISTRY" = false ] && echo "$n" | grep -qi 'registry'; then
          continue
        fi
        hosts+=("$n")
      done
    fi
  fi
  printf "%s\n" "${hosts[@]}"
}

# --- cli -------------------------------------------------------------------

usage(){
  cat <<EOF

usage: $0 [INIT_ENV only] [options]

OPTIONS (GENERAL):
  -h                   Show help
  -s <start>           Start step (default: ${INIT_ENV})
  -e <end>             End step (default: ${INIT_ENV})
  -q                   Quiet output
  -x                   DRY-RUN: print intended actions, do not change anything

INIT_ENV does the following:
  1) Validates local tools (no network installs)
  2) Ensures an SSH key exists (or generates it)
  3) Runs Terraform (init -> plan -> apply) in -t <dir>   [unless --no-apply]
  4) Captures 'terraform output -json' to .private/tf-outputs.json
  5) Writes .private/cluster.env with useful exports
  6) Appends a managed SSH config block (~/.ssh/config), bastion-aware

OPTIONS (INIT_ENV):
  -t <terraform_dir>   Terraform working directory (default: ${TF_DIR})
  -k <ssh_key>         SSH private key path (default: ${SSH_KEY})
  -p <prefix>          Logical cluster prefix for SSH aliases (optional)
  -N, --no-apply       Skip Terraform init/plan/apply; just read outputs if present

PARAMETERS USED BY INIT_ENV:
  REQUIRED:   terraform directory (-t) must exist (and be a valid TF project)
  OPTIONAL:   ssh_user (TF output) or inferred from ssh_commands
              bastion_host, bastion_user, bastion_private_key (TF outputs)
              nifi_hosts OR nifi_public_ips OR nifi_private_ips OR instance_names
  DEFAULTS:   PRIVATE_DIR=${PRIVATE_DIR}
              TF_DIR=${TF_DIR}
              SSH_KEY=${SSH_KEY}
              START=END=${INIT_ENV}
              QUIET=false, DRY_RUN=false, NO_APPLY=false

SUPPORTED TERRAFORM OUTPUTS (any subset is fine):
  instance_names          list(string)  # e.g., ["nifi-node-01","nifi-node-02","nifi-registry"]
  ssh_commands            list(string)  # e.g., ["ssh ... ubuntu@nifi-node-01", ...] (for user inference)
  nifi_hosts              list(string)  # preferred, resolvable hostnames
  nifi_public_ips         list(string)
  nifi_private_ips        list(string)
  ssh_user                string
  bastion_host            string
  bastion_user            string
  bastion_private_key     string (path)

INSTALL (step ${INSTALL}) runs the separate nifi-install.sh on your cluster:
  - Uses hostnames from Terraform outputs (nifi_hosts or instance_names)
  - Calls: \$ ${NIFI_INSTALL_SCRIPT} [flags] node-<i>:<hostname> ...
  - Hostnames only (no IPs)

OPTIONS (INSTALL):
  --install-script <path>   Override path to nifi-install.sh (default: ${NIFI_INSTALL_SCRIPT})
  -R, --include-registry    Include the registry host in this step (default: ${INCLUDE_REGISTRY})
  -S, --secure              Use secure NiFi ports (TLS) (default: ${SECURE})
  --ssh-timeout <secs>      SSH reachability timeout for nifi-install.sh (default: ${SSH_TIMEOUT})
  --trace                   enable trace for detailed log reporting in the nifi installer script
  # Installer user:
  #   If NIFI_SSH_USER is set in .private/cluster.env we will pass -i <user>.
  #   Otherwise we do NOT pass -i so nifi-install.sh defaults to 'ubuntu'.

  for all installations you'll need to provide a 16+ character key for sensitive properties
  $ export SENSITIVE_KEY='******'

  for secure installations you'll also need to provide passwords for the key and trust stores
  $ export KEYSTORE_PASSWD='******'
  $ export TRUSTSTORE_PASSWD='******'

  --insecure-downloads      defaults to $INSECURE_DOWNLOADS
  --curl-cacert             defaults to $CURL_CACERT

  --java-version            defaults to $JAVA_VERSION
  --pgjdbc-version          defaults to $PGJDBC_VERSION
  --zk-version              defaults to $ZK_VERSION
  --kafka-version           defaults to $KAFKA_VERSION
  --scala-version           defaults to $SCALA_VERSION
  
  --nifi-version            defaults to $NIFI_VERSION
  --nifi-toolkit-version    defaults to $NIFI_TOOLKIT_VERSION
  --nifi-user               defaults to $NIFI_USER

  --nifi-heap)              defaults to $NIFI_HEAP
  --nifi-log-dir)           defaults to $NIFI_LOG_DIR
  --log-max-size)           defaults to $LOG_MAX_SIZE
  --log-max-history)        defaults to $LOG_MAX_HISTORY
  
  if using git with https://... you'll need to export GIT_TOKEN='******' with a fine-grained PAT with repo read/write
  if using git with ssh remote you'll need to unset GIT_TOKEN and allow ssh credentials to authenticate

  --gh-url                no default, if you have a repo then either https://… or git@github.com:…
  --gh-username           no default, use for HTTPS connection but leave blank for if SSH
  --gh-usertext           no default, git identity stored for the nifi user
  --gh-email              no default, git identity stored for the nifi user
  --gh-branch             defaults to $GH_BRANCH
  --gh-directory          defaults to $GH_DIRECTORY
  --gh-remote-name        defaults to $GH_REMOTE_NAME

EOF
}

# parse args
while (( "$#" )); do
  case "$1" in
    # general
    -h) HELP=true; shift ;;
    -s) START="$2"; END="$2"; shift 2 ;;
    -e) END="$2"; shift 2 ;;
    -q) QUIET=true; shift ;;
    -x) DRY_RUN=true; shift ;;

    # init_env
    -t) TF_DIR="$2"; shift 2 ;;
    -k) SSH_KEY="$2"; shift 2 ;;
    -p) CLUSTER_PREFIX="$2"; shift 2 ;;
    -N|--no-apply) NO_APPLY=true; shift ;;

    # install
    --install-script)      NIFI_INSTALL_SCRIPT="$2"; shift 2 ;;
    -R|--include-registry) INCLUDE_REGISTRY=true; shift ;;
    -S|--secure)           SECURE=true; shift ;;
    --ssh-timeout)         SSH_TIMEOUT="$2"; shift 2 ;;
    --trace)               TRACE=true; shift ;;

    --insecure-downloads) INSECURE_DOWNLOADS=true; shift ;;
    --curl-cacert)        CURL_CACERT="$2"; shift 2 ;;

    --java-version)   JAVA_VERSION="$2"; shift 2 ;;
    --pgjdbc-version) PGJDBC_VERSION="$2"; shift 2 ;;
    --zk-version)     ZK_VERSION="$2"; shift 2 ;;
    --kafka-version)  KAFKA_VERSION="$2"; shift 2 ;;
    --scala-version)  SCALA_VERSION="$2"; shift 2 ;;

    --nifi-version)         NIFI_VERSION="$2"; shift 2 ;;
    --nifi-toolkit-version) NIFI_TOOLKIT_VERSION="$2"; shift 2 ;;
    --nifi-user)            NIFI_USER="$2"; shift 2 ;;

    --nifi-heap)           NIFI_HEAP="$2"; shift 2 ;;
    --nifi-log-dir)        NIFI_LOG_DIR="$2"; shift 2 ;;
    --log-max-size)        LOG_MAX_SIZE="$2"; shift 2 ;;
    --log-max-history)     LOG_MAX_HISTORY="$2"; shift 2 ;;

    --gh-url)         GH_URL="$2"; shift 2 ;;
    --gh-username)    GH_USERNAME="$2"; shift 2 ;;
    --gh-usertext)    GH_USERTEXT="$2"; shift 2 ;;
    --gh-email)       GH_EMAIL="$2"; shift 2 ;;
    --gh-branch)      GH_BRANCH="$2"; shift 2 ;;
    --gh-directory)   GH_DIRECTORY="$2"; shift 2 ;;
    --gh-remote-name) GH_REMOTE_NAME="$2"; shift 2 ;;
    
    --) shift; break ;;
    -*) echo "Unknown option: $1"; HELP=true; break ;;
    *) break ;;
  esac
done

if [ "$HELP" = true ]; then usage; exit 0; fi
if [ "$START" -lt "$INIT_ENV" ] || [ "$END" -gt "$MAX_STEPS" ] || [ "$END" -lt "$START" ]; then
  die "Invalid step range: start=${START} end=${END} (supported: ${INIT_ENV}..${MAX_STEPS})"
fi

mkpath "$PRIVATE_DIR"

# --- step: INIT_ENV --------------------------------------------------------

init_env(){
  log "==> INIT_ENV: validating local environment…"
  need ssh; need ssh-keygen; need jq; need terraform

  # SSH key
  if [ ! -f "$SSH_KEY" ]; then
    if [ "$DRY_RUN" = true ]; then
      log "[dry-run] would generate SSH key at ${SSH_KEY}"
    else
      log "-> Generating SSH key at ${SSH_KEY}"
      mkpath "$(dirname "$SSH_KEY")"
      ssh-keygen -q -t rsa -b 4096 -N '' -f "$SSH_KEY" <<< n >/dev/null
    fi
  else
    log "-> Using existing SSH key at ${SSH_KEY}"
  fi

  # Terraform init/plan/apply (unless skipped)
  if [ "$NO_APPLY" = false ]; then
    log "-> Terraform init/plan/apply in ${TF_DIR}"
    [ "$DRY_RUN" = true ] || [ -d "$TF_DIR" ] || die "Terraform dir not found: ${TF_DIR}"
    tf init -input=false -upgrade
    tf plan -input=false -out=tfplan.out
    tf apply -input=false -auto-approve tfplan.out
  else
    log "-> Skipping Terraform apply (NO_APPLY=true)."
  fi

  # Capture outputs JSON
  log "-> Reading Terraform outputs"
  if [ "$DRY_RUN" = true ]; then
    log "[dry-run] terraform -chdir='${TF_DIR}' output -json > ${PRIVATE_DIR}/tf-outputs.json"
  else
    tf output -json > "${PRIVATE_DIR}/tf-outputs.json"
  fi

  # Determine SSH user (explicit > inferred > blank)
  local ssh_user inferred
  ssh_user="$(tfout ssh_user)"
  if [ -z "$ssh_user" ]; then
    inferred="$(infer_user_from_ssh_commands || true)"
    [ -n "$inferred" ] && ssh_user="$inferred"
  fi

  # Emit cluster.env
  log "-> Emitting environment: ${PRIVATE_DIR}/cluster.env"
  {
    echo "# Generated by nifi-setup.sh INIT_ENV"
    echo "export TF_DIR='${TF_DIR}'"
    echo "export SSH_PRIVATE_KEY='${SSH_KEY}'"
    [ -n "$ssh_user" ] && echo "export NIFI_SSH_USER='${ssh_user}'"
    [ -n "$CLUSTER_PREFIX" ] && echo "export NIFI_CLUSTER_PREFIX='${CLUSTER_PREFIX}'"
  } | writefile "${PRIVATE_DIR}/cluster.env"

  # SSH config
  local ssh_cfg="${HOME}/.ssh/config"
  mkpath "${HOME}/.ssh"
  touch_guard "$ssh_cfg"
  chmod_guard 600 "$ssh_cfg"

  local bastion_host bastion_user bastion_key
  bastion_host="$(tfout bastion_host)"
  bastion_user="$(tfout bastion_user)"
  bastion_key="$(tfout bastion_private_key)"; [ -n "$bastion_key" ] || bastion_key="$SSH_KEY"

  mapfile -t nifi_hosts < <(tfout_array nifi_hosts || true)
  mapfile -t nifi_pubs  < <(tfout_array nifi_public_ips || true)
  mapfile -t nifi_privs < <(tfout_array nifi_private_ips || true)
  mapfile -t instance_names < <(hosts_from_instance_names || true)

  # choose a node list (registry excluded from the node list; added separately below)
  declare -a nodes=()
  if [ "${#nifi_hosts[@]}" -gt 0 ]; then
    nodes=("${nifi_hosts[@]}")
  elif [ "${#nifi_pubs[@]}" -gt 0 ]; then
    nodes=("${nifi_pubs[@]}")
  elif [ "${#nifi_privs[@]}" -gt 0 ]; then
    nodes=("${nifi_privs[@]}")
  elif [ "${#instance_names[@]}" -gt 0 ]; then
    for n in "${instance_names[@]}"; do
      if echo "$n" | grep -qiE 'registry'; then continue; fi
      nodes+=("$n")
    done
  fi

  local start_marker="# >>> NI-FI INIT (managed)"
  local end_marker="# <<< NI-FI INIT (managed)"

  # remove old managed block
  if [ "$DRY_RUN" = true ]; then
    log "[dry-run] would remove previous managed block in ${ssh_cfg}"
  else
    awk -v s="$start_marker" -v e="$end_marker" '
      $0==s {skip=1}
      skip!=1 {print}
      $0==e {skip=0}
    ' "$ssh_cfg" > "${ssh_cfg}.tmp" && mv "${ssh_cfg}.tmp" "$ssh_cfg"
  fi

  # build new managed block
  {
    echo "$start_marker"
    if [ -n "$bastion_host" ]; then
      echo "Host nifi-bastion"
      echo "  HostName ${bastion_host}"
      [ -n "$bastion_user" ] && echo "  User ${bastion_user}"
      echo "  IdentityFile ${bastion_key}"
      echo "  IdentitiesOnly yes"
      echo
    fi

    if [ "${#nodes[@]}" -gt 0 ]; then
      idx=1
      for h in "${nodes[@]}"; do
        alias="${CLUSTER_PREFIX}nifi-node-${idx}"
        echo "Host ${alias}"
        echo "  HostName ${h}"
        [ -n "$ssh_user" ] && echo "  User ${ssh_user}"
        echo "  IdentityFile ${SSH_KEY}"
        echo "  IdentitiesOnly yes"
        [ -n "$bastion_host" ] && echo "  ProxyJump nifi-bastion"
        echo
        idx=$((idx+1))
      done
    else
      echo "# (No NiFi node addresses found in Terraform outputs.)"
      echo
    fi

    if [ "${#instance_names[@]}" -gt 0 ]; then
      reg="$(printf "%s\n" "${instance_names[@]}" | grep -iE 'registry' || true)"
      if [ -n "$reg" ]; then
        echo "Host ${CLUSTER_PREFIX}nifi-registry"
        echo "  HostName ${reg}"
        [ -n "$ssh_user" ] && echo "  User ${ssh_user}"
        echo "  IdentityFile ${SSH_KEY}"
        echo "  IdentitiesOnly yes"
        [ -n "$bastion_host" ] && echo "  ProxyJump nifi-bastion"
        echo
      fi
    fi
    echo "$end_marker"
  } | {
      if [ "$DRY_RUN" = true ]; then
        log "[dry-run] would append managed SSH config block to ${ssh_cfg}:"
        cat
      else
        appendfile "$ssh_cfg" "$(cat)"
      fi
    }

  chmod_guard 600 "$ssh_cfg"

  log "==> INIT_ENV complete."
  log "    Outputs:  ${PRIVATE_DIR}/tf-outputs.json   $( [ "$DRY_RUN" = true ] && echo '(planned)' )"
  log "    Exports:  ${PRIVATE_DIR}/cluster.env       $( [ "$DRY_RUN" = true ] && echo '(planned)' )"
  log "    SSH cfg:  ${HOME}/.ssh/config              $( [ "$DRY_RUN" = true ] && echo '(planned block append)' )"
}

# --- step: INSTALL --------------------------------------------------------

install_step() {
  echo "==> INSTALL: preparing to call ${NIFI_INSTALL_SCRIPT}"

  # Ensure outputs exist (i.e., INIT_ENV ran)
  if [ ! -f "${PRIVATE_DIR}/tf-outputs.json" ]; then
    echo "ERROR: ${PRIVATE_DIR}/tf-outputs.json not found. Run INIT_ENV (step ${INIT_ENV}) first."
    exit 1
  fi

  # Discover hostnames
  mapfile -t nodes < <(discover_node_hostnames)
  if [ "${#nodes[@]}" -eq 0 ]; then
    echo "ERROR: no node hostnames discovered (expected nifi_hosts or instance_names in Terraform outputs)."
    exit 1
  fi

  # Optional registry hostname
  local reg_host=""
  if [ "$INCLUDE_REGISTRY" = true ]; then
    reg_host="$(discover_registry_hostname)"
  fi

  # Build argv for nifi-install.sh (hostnames only)
  # node-<i>:<hostname> (no '=ip')

  # 1) Build the argument array
  declare -a argv
  REPO_JSON="$(terraform -chdir="${TF_DIR}" output -json repo_mounts)"
  FLOWFILE_DIR="$(jq -r '.flowfile_dir  // empty' <<<"$REPO_JSON")"
  DATABASE_DIR="$(jq -r '.database_dir  // empty' <<<"$REPO_JSON")"
  mapfile -t CONTENT_DIRS    < <(printf '%s' "$REPO_JSON" | jq -r '.content_dirs[]')
  mapfile -t PROVENANCE_DIRS < <(printf '%s' "$REPO_JSON" | jq -r '.provenance_dirs[]')

  # forward DRY RUN from this script if you have one; here we detect -x via your own DRY_RUN variable if present
  if [ "${DRY_RUN:-false}" = true ]; then argv+=("-x"); fi
  if [ "$TRACE" = true ]; then argv+=("--trace"); fi
  if [ "$SECURE" = true ]; then argv+=("-S"); fi
  if [ -n "$reg_host" ]; then argv+=("-r" "registry=${reg_host}"); fi
  argv+=("--ssh-timeout" "${SSH_TIMEOUT}")

  # pass -i only if user was set during INIT_ENV (cluster.env)
  # shellcheck disable=SC1090
  [ -f "${PRIVATE_DIR}/cluster.env" ] && source "${PRIVATE_DIR}/cluster.env"
  if [ -n "${NIFI_SSH_USER:-}" ]; then
    argv+=("-i" "${NIFI_SSH_USER}")
  fi

  # --insecure-downloads is a switch: add it ONLY when true, with NO value
  if [ "${INSECURE_DOWNLOADS:-false}" = true ]; then
    argv+=("--insecure-downloads")
  fi

  # --curl-cacert takes a path: add it ONLY when non-empty
  if [ -n "${CURL_CACERT:-}" ]; then
    argv+=("--curl-cacert" "${CURL_CACERT}")
  fi

  # pass the version flags
  argv+=("--java-version"   "${JAVA_VERSION}")
  argv+=("--pgjdbc-version" "${PGJDBC_VERSION}")
  argv+=("--zk-version"     "${ZK_VERSION}")
  argv+=("--kafka-version"  "${KAFKA_VERSION}")
  argv+=("--scala-version"  "${SCALA_VERSION}")
  
  argv+=("--nifi-version" "${NIFI_VERSION}")
  argv+=("--nifi-toolkit-version" "${NIFI_TOOLKIT_VERSION}")
  argv+=("--nifi-user" "${NIFI_USER}")

  argv+=("--nifi-heap" "${NIFI_HEAP}")
  argv+=("--nifi-log-dir" "${NIFI_LOG_DIR}")
  argv+=("--log-max-size" "${LOG_MAX_SIZE}")
  argv+=("--log-max-history" "${LOG_MAX_HISTORY}")

  [[ -n "$GH_URL" ]] && argv+=( --gh-url  "$GH_URL" )
  [[ -n "$GH_USERNAME" ]] && argv+=( --gh-username  "$GH_USERNAME" )
  [[ -n "$GH_USERTEXT" ]] && argv+=( --gh-usertext  "$GH_USERTEXT" )
  [[ -n "$GH_EMAIL" ]] && argv+=( --gh-email  "$GH_EMAIL" )
  argv+=("--gh-branch" "${GH_BRANCH}")
  argv+=("--gh-directory" "${GH_DIRECTORY}")
  argv+=("--gh-remote-name" "${GH_REMOTE_NAME}")

  # and the mount points for the content and provenance repositories
  [[ -n "$FLOWFILE_DIR" ]] && argv+=( --flowfile-dir  "$FLOWFILE_DIR" )
  [[ -n "$DATABASE_DIR" ]] && argv+=( --database-dir  "$DATABASE_DIR" )
  for d in "${CONTENT_DIRS[@]}";    do argv+=( --content-dir "$d" ); done
  for d in "${PROVENANCE_DIRS[@]}"; do argv+=( --provenance-dir "$d" ); done

  # 2) Append the node arguments in the shape your installer expects: node-<i>:<hostname>
  local i=1
  for h in "${nodes[@]}"; do
    # assuming REGISTRY_HOST is set when --include-registry
    if [ -n "${REGISTRY_HOST:-}" ] && [ "$h" = "$REGISTRY_HOST" ]; then
      continue  # registry is NOT a NiFi node
    fi
    argv+=("node-${i}:${h}")
    i=$((i+1))
  done
  
  # Validate installer script
  if [ ! -x "${NIFI_INSTALL_SCRIPT}" ]; then
    echo "ERROR: ${NIFI_INSTALL_SCRIPT} not found or not executable."
    echo "Hint: set with --install-script <path> or place nifi-install.sh next to nifi-setup.sh"
    exit 1
  fi

  # 3) Call the installer with the array (this preserves spaces/quoting correctly)
  echo "==> INSTALL: calling ${NIFI_INSTALL_SCRIPT} with:"
  printf '   %q ' "${NIFI_INSTALL_SCRIPT}" "${argv[@]}"; echo
  OP=new-cluster "${NIFI_INSTALL_SCRIPT}" "${argv[@]}"
}

# --- main ------------------------------------------------------------------

[ "$START" -eq "$END" ] && log "Executing step ${START}…" || log "Executing steps ${START}..${END}…"

for (( step = START; step <= END; step++ )); do
  case "$step" in
    ${INIT_ENV}) init_env ;;
    ${INSTALL})  install_step ;;
    *) die "Step ${step} not implemented in this refactor." ;;
  esac
done
