#!/usr/bin/env bash
# nifi-install.sh
# OP=new-cluster (default): SSH reachability, apt update/upgrade, UFW defaults, peer rules
# Hostnames-only. Default installer user: ubuntu. Idempotent. Supports --dry-run.
# Debian/Ubuntu only for now (uses apt-get and DEBIAN_FRONTEND=noninteractive).

set -o pipefail
OPTIND=1

# --- Locate script dir and source REQUIRED helpers -------------------------
NI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_LIBS=(
  helpers/ni_api.sh
  helpers/ni_auth.sh
  helpers/ni_certs.sh
  helpers/ni_common.sh
  helpers/ni_firewall.sh
  helpers/ni_git.sh
  helpers/ni_inventory.sh
  helpers/ni_java.sh
  helpers/ni_kafka.sh
  helpers/ni_nifi.sh
  helpers/ni_postgres.sh
  helpers/ni_registry.sh
  helpers/ni_ssh.sh
  helpers/ni_zk.sh
)
for f in "${REQUIRED_LIBS[@]}"; do
  if [ ! -f "${NI_DIR}/${f}" ]; then
    echo "ERROR: missing required library: ${f}" >&2
    exit 2
  fi
  # shellcheck source=/dev/null
  . "${NI_DIR}/${f}"
done

ni::tmpmap_init

# --- Defaults & CLI parsing ------------------------------------------------
help=false
installer="ubuntu"     # default installer account
secure=false           # if true: use TLS NiFi ports
registry_host=""       # optional registry hostname (excluded from peer rules)
DRY_RUN=false
SSH_TIMEOUT=8          # seconds for reachability probe
QUIET=false

INSECURE_DOWNLOADS=false
CURL_CACERT=""
DOWNLOAD_CURL_FLAGS=""

# version defaults (override via flags)
JAVA_VERSION=21
PGJDBC_VERSION=42.7.7
ZK_VERSION=3.9.4
KAFKA_VERSION=3.9.1
SCALA_VERSION=2.13

# NiFi versions (choose based on Java)
NIFI_VERSION=2.5.0
NIFI_TOOLKIT_VERSION=2.5.0   # usually same as NIFI_VERSION
NIFI_USER=nifi

# Repo base directories (not mounted here; TF handles mounts for content/prov)
FLOWFILE_DIR="/flowfile_repository"
DATABASE_DIR="/database_repository"

# Repo mount points (from nifi-setup/terraform). Repeatable flags.
CONTENT_DIRS=()
PROVENANCE_DIRS=()

# JVM heap & logging defaults
NIFI_HEAP="3g"                       # override with --nifi-heap
NIFI_LOG_DIR="/var/log/nifi"         # override with --nifi-log-dir
LOG_MAX_SIZE="256MB"                 # override with --log-max-size
LOG_MAX_HISTORY="14"                 # override with --log-max-history

# GitHub default values
GH_URL=""                            # override with --gh-url
GH_USERNAME=""                       # override with --gh-username
GH_USERTEXT=""                       # override with --gh-usertext
GH_EMAIL=""                          # override with --gh-email
GH_BRANCH="registry"                 # override with --gh-branch
GH_DIRECTORY="nifi-flows"            # override with --gh-directory
GH_REMOTE_NAME="origin"              # override with --gh-remote-name

usage(){
  cat <<EOF

usage: $0 [options] node-<id>:<hostname> [node-<id>:<hostname> ...]

Phase 1 (new-cluster, idempotent):
  1) Check SSH to each node (by hostname) and ensure our pubkey is present
  2) apt-get update && full-upgrade (Debian/Ubuntu only)
  3) Install & configure UFW: deny incoming, allow outgoing, allow SSH
  4) Allow intra-cluster traffic between nodes and enable UFW

Options:
  -i <user>              installer account on nodes (default: ubuntu)
  -r registry=<hostname> optional registry host (excluded from peer rules)
  -S                     use secure NiFi ports (TLS) for cluster comms
  -x                     dry-run (print actions, no changes)
  --ssh-timeout <secs>   SSH reachability timeout (default: 8)
  -q                     quiet mode
  --trace                enable trace for detailed log reporting

  for all installations you'll need to provide a 16+ character key for sensitive properties
  $ export SENSITIVE_KEY='******'

  for secure installations you'll also need to provide passwords for the key and trust stores
  $ export KEYSTORE_PASSWD='******'
  $ export TRUSTSTORE_PASSWD='******'

  --insecure-downloads   defaults to $INSECURE_DOWNLOADS
  --curl-cacert          defaults to $CURL_CACERT

  --java-version         defaults to $JAVA_VERSION
  --pgjdbc-version       defaults to $PGJDBC_VERSION
  --zk-version           defaults to $ZK_VERSION
  --kafka-version        defaults to $KAFKA_VERSION
  --scala-version        defaults to $SCALA_VERSION
  
  --nifi-version         defaults to $NIFI_VERSION
  --nifi-toolkit-version defaults to $NIFI_TOOLKIT_VERSION
  --nifi-user            defaults to $NIFI_USER

  --flowfile-dir PATH    flowfile repo mount, e.g. /mnt/disk1 (single), defaults to $FLOWFILE_DIR
  --database-dir PATH    database repo mount, e.g. /mnt/disk2 (single), defaults to $DATABASE_DIR
  --content-dir PATH     repeatable; content repo mount(s), e.g. /mnt/disk3 /mnt/disk3
  --provenance-dir PATH  repeatable; provenance repo mount(s), e.g. /mnt/disk5 /mnt/disk6

  --nifi-heap             defaults to $NIFI_HEAP
  --nifi-log-dir          defaults to $NIFI_LOG_DIR
  --log-max-size          defaults to $LOG_MAX_SIZE
  --log-max-history       defaults to $LOG_MAX_HISTORY

  if using git with https://... you'll need to export GIT_TOKEN='******' with a fine-grained PAT with repo read/write
  if using git with ssh remote you'll need to unset GIT_TOKEN and allow ssh credentials to authenticate

  --gh-url                no default, if you have a repo then either https://… or git@github.com:…
  --gh-username           no default, use for HTTPS connection but leave blank for if SSH
  --gh-usertext           no default, git identity stored for the nifi user
  --gh-email              no default, git identity stored for the nifi user
  --gh-branch             defaults to $GH_BRANCH
  --gh-directory          defaults to $GH_DIRECTORY
  --gh-remote-name        defaults to $GH_REMOTE_NAME

Advanced:
  OP=<op> $0 ...         set operation via env (default: new-cluster)
                         planned ops: add-node, join-cluster, remove-node,
                         replace-node, rotate-certs, upgrade, migrate

Notes:
  • Arguments accept legacy form node-1:host=anything — value is ignored; only hostnames are used.
  • No IPs required as inputs; UFW resolves peers to IPs on each node during rule creation.
  • Debian/Ubuntu only (uses apt-get with DEBIAN_FRONTEND=noninteractive).
EOF
}

# --- Robust parsing: options can appear anywhere; collect node tokens separately
NODE_ARGS=()
TRACE=false

while (( "$#" )); do
  case "$1" in
    # node tokens: node-<id>:<host>[=ignored]
    node-[0-9]*:*)
      NODE_ARGS+=("$1"); shift ;;

    -h|-\?) help=true; shift ;;
    -i) installer="$2"; shift 2 ;;
    -r) registry_host="$(printf "%s" "$2" | cut -d= -f2)"; shift 2 ;;
    -S) secure=true; shift ;;
    -x) DRY_RUN=true; shift ;;
    --ssh-timeout) SSH_TIMEOUT="$2"; shift 2 ;;
    -q) QUIET=true; shift ;;
    --trace) TRACE=true; shift ;;

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

    --flowfile-dir)   FLOWFILE_DIR="$2"; shift 2 ;;
    --database-dir)   DATABASE_DIR="$2"; shift 2 ;;
    --content-dir)    CONTENT_DIRS+=("$2"); shift 2 ;;
    --provenance-dir) PROVENANCE_DIRS+=("$2"); shift 2 ;;

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
    -*)
      echo "WARN: unknown option: $1 (ignored)"; shift ;;
    *)
      echo "WARN: unexpected argument (ignored): $1"; shift ;;
  esac
done

[ "$help" = true ] && { usage; exit 0; }

# NiFi 2.x requires Java 21+
if [[ "${NIFI_VERSION}" =~ ^2\. ]] && [ "${JAVA_VERSION}" -lt 21 ]; then
  ni::die "NiFi ${NIFI_VERSION} requires Java 21+. Re-run with --java-version 21"
fi

# Build curl flags once and export for helpers
[ "$INSECURE_DOWNLOADS" = true ] && DOWNLOAD_CURL_FLAGS+=" --insecure"
[ -n "$CURL_CACERT" ] && DOWNLOAD_CURL_FLAGS+=" --cacert ${CURL_CACERT}"
export DOWNLOAD_CURL_FLAGS

# Optional detailed trace
if [ "$TRACE" = true ]; then
  set -o xtrace
  PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
fi

# --- Sanity: must have node args
if [ "${#NODE_ARGS[@]}" -lt 1 ]; then
  echo "ERROR: no node arguments provided (expected node-<id>:<hostname>)" >&2
  usage; exit 1
fi

# --- More Helpers ----------------------------------------------------------
ensure_debian_like(){
  local remote="$1"
  ni::ssh "$remote" 'command -v apt-get >/dev/null 2>&1 || { echo "This op currently supports Debian/Ubuntu only (apt-get not found)"; exit 2; }'
}

ensure_local_pubkey(){
  # prefer ed25519, fallback rsa
  if [ -f "${HOME}/.ssh/id_ed25519.pub" ]; then
    cat "${HOME}/.ssh/id_ed25519.pub"
  elif [ -f "${HOME}/.ssh/id_rsa.pub" ]; then
    cat "${HOME}/.ssh/id_rsa.pub"
  else
    ni::die "No local public key found (~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub)"
  fi
}

check_ssh_reachable(){
  local remote="$1"
  if [ "${DRY_RUN:-false}" = true ]; then
    echo "[dry-run] ssh -o ConnectTimeout=${SSH_TIMEOUT} ${remote} 'echo ok'"
    return 0
  fi
  if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout="${SSH_TIMEOUT}" "${remote}" "echo ok" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

ensure_pubkey_on_remote(){
  local remote="$1" pubkey="$2"
  ni::ssh "$remote" $'mkdir -p ~/.ssh && chmod 700 ~/.ssh'
  ni::ssh "$remote" "grep -Fq \"${pubkey}\" ~/.ssh/authorized_keys || echo '${pubkey}' >> ~/.ssh/authorized_keys"
  ni::ssh "$remote" $'chmod 600 ~/.ssh/authorized_keys || true'
}

apt_update_upgrade(){
  local remote="$1"
  ni::ssh_sudo "$remote" $'DEBIAN_FRONTEND=noninteractive apt-get update -y && \
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y && \
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y && \
DEBIAN_FRONTEND=noninteractive apt-get clean'
}

# --- Operation: new-cluster ------------------------------------------------
ni::op::new_cluster(){
  # Build inventory once
  ni::inventory_from_args "${registry_host}" "$@"
  # Inspect parsed lists
  if [ "$TRACE" = true ]; then
    local _nodes _nifi _zk _hosts
    ni::nodes _nodes; ni::nifi_nodes _nifi; ni::zk_nodes _zk; ni::hosts _hosts
    echo "TRACE inventory: nodes=(${_nodes[*]}) nifi=(${_nifi[*]}) zk=(${_zk[*]}) hosts=(${_hosts[*]})"
  fi

  local nodes; ni::nodes nodes
  [ "${#nodes[@]}" -ge 1 ] || ni::die "No nodes provided"

  # Partition: NiFi nodes (exclude registry), then the first 3 for ZK/Kafka
  declare -a NIFI_NODES=() NIFI_HOSTS=() sorted_nifi_nodes=()
  for arg in "${nodes[@]}"; do
    host="$(ni::resolve_host "${arg}")"
    if [ -n "${registry_host}" ] && [ "${host}" = "${registry_host}" ]; then
      continue
    fi
    NIFI_NODES+=("${arg}")
    NIFI_HOSTS+=("${host}")
  done
  # for h in "${NIFI_NODES[@]}"; do
  #   echo "HOST $(ni::resolve_node_id ${h}): $(ni::resolve_host ${h})"
  # done
  # exit 0
  [ "${#NIFI_NODES[@]}" -ge 3 ] || ni::die "At least 3 NiFi nodes are required (registry excluded)"

  # Sort NiFi nodes by node-id (node-<id>:host) and pick first three for ZK/Kafka
  IFS=$'\n' read -r -d '' -a sorted_nifi_nodes < <(printf '%s\n' "${NIFI_NODES[@]}" | sort -t: -k1.6n && printf '\0')
  ZK_NODES=("${sorted_nifi_nodes[@]:0:3}")
  ZK_HOSTS=(); for n in "${ZK_NODES[@]}"; do ZK_HOSTS+=("$(ni::resolve_host "$n")"); done

  # Build ZK connect string ONLY from the first three NiFi nodes
  ZK_CONNECT=""
  for h in "${ZK_HOSTS[@]}"; do
    if [ -n "$ZK_CONNECT" ]; then ZK_CONNECT+=",${h}:2181"; else ZK_CONNECT="${h}:2181"; fi
  done
  echo "ZK connect string: ${ZK_CONNECT}"

  ni::need ssh
  local pubkey; pubkey="$(ensure_local_pubkey)"

  echo "checking status of SSH to execute the script on the other nodes in the cluster"
  for n in "${NIFI_NODES[@]}"; do
    local remote="${installer}@$(ni::resolve_host "${n}")"
    if ! check_ssh_reachable "${remote}"; then
      ni::die "ssh not reachable for ${remote}"
    fi
    ensure_pubkey_on_remote "${remote}" "${pubkey}"
    echo "INFO: ssh enabled for ${remote} and script will be executed remotely"
  done
  # Optionally ensure SSH for registry host (peer rules skip it; you may still want key access)
  if [ -n "${registry_host}" ]; then
    remote="${installer}@${registry_host}"
    if check_ssh_reachable "${remote}"; then
      ensure_pubkey_on_remote "${remote}" "${pubkey}"
    fi
  fi

  echo "updating package installer and upgrading versions..."
  for n in "${NIFI_NODES[@]}"; do
    local remote="${installer}@$(ni::resolve_host "${n}")"
    ensure_debian_like "${remote}"
    apt_update_upgrade "${remote}"
  done
  if [ -n "${registry_host}" ]; then
    remote="${installer}@${registry_host}"
    ensure_debian_like "${remote}"
    apt_update_upgrade "${remote}"
  fi

  echo "installing the firewall and configuring default policies..."
  # Base UFW defaults on all hosts
  for h in "${NIFI_HOSTS[@]}"; do
    remote="${installer}@${h}"
    ni::ufw_defaults "${remote}"
    # NiFi nodes: open NiFi UI port (secure => 9443, else 8080)
    if [ "${secure}" = true ]; then
      ni::ssh_sudo "${remote}" $'ufw allow 9443'
    else
      ni::ssh_sudo "${remote}" $'ufw allow 8080'
    fi
  done

  # Registry: defaults only (do NOT open NiFi node UI ports here)
  if [ -n "${registry_host}" ]; then
    remote="${installer}@${registry_host}"
    ni::ufw_defaults "${remote}"
    # (Registry UI ports, e.g., 18443/18080, will be handled in the registry install step.)
  fi

  echo "updating firewall rules to enable communication between nodes..."
  # Peer rules ONLY among NiFi nodes (exclude registry)
  for n in "${NIFI_NODES[@]}"; do
    local host="$(ni::resolve_host "${n}")"
    local remote="${installer}@${host}"
    local peers=()
    for m in "${NIFI_NODES[@]}"; do
      [ "$m" != "$n" ] && peers+=("$(ni::resolve_host "$m")")
    done
    local secure_flag=$([ "${secure}" = true ] && echo true || echo false)
    ni::resolve_and_allow_peers "${remote}" "${secure_flag}" "${peers[@]}"
  done

  # --- Java & JDBC driver on NiFi nodes (and registry if you want JDBC there too) ---
  echo "installing java version ${JAVA_VERSION}..."
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::java::ensure "${remote}" "${JAVA_VERSION}"
  done
  if [ -n "${registry_host}" ]; then
    remote="${installer}@${registry_host}"
    ni::java::ensure "${remote}" "${JAVA_VERSION}"
  fi

  # --- NiFi user + installs ONLY on NiFi nodes ---
  echo "creating user for nifi installation..."
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::nifi::user "${remote}" "${NIFI_USER}"
  done
  # Registry (needs `nifi` owner for toolkit/registry)
  if [ -n "${registry_host}" ]; then
    remote="${installer}@${registry_host}"
    ni::nifi::user "${remote}" "${NIFI_USER}"
  fi

  echo "installing postgres drivers for version ${PGJDBC_VERSION}..."
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::pg::install_jdbc "${remote}" "${PGJDBC_VERSION}" "/opt/drivers/postgres" "${NIFI_USER}" "${DOWNLOAD_CURL_FLAGS}"
  done
  # Intentionally NOT installing JDBC driver on the registry

  # --- ZooKeeper ensemble ONLY on first three NiFi nodes ---
  echo "installing zookeeper ${ZK_VERSION}..."
  for n in "${ZK_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::zk::install "${remote}" "${ZK_VERSION}" "${DOWNLOAD_CURL_FLAGS}"
  done

  echo "updating zookeeper configuration with node details..."
  for n in "${ZK_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    myid="$(ni::resolve_node_id "${n}")"
    ni::zk::configure "${remote}" "${myid}" "${ZK_HOSTS[@]}"
    ni::zk::systemd "${remote}"
  done

  # --- Kafka brokers ONLY on first three NiFi nodes (ZK mode) ---
  echo "installing kafka ${KAFKA_VERSION} (scala ${SCALA_VERSION})..."
  for n in "${ZK_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::kafka::install "${remote}" "${KAFKA_VERSION}" "${SCALA_VERSION}" "${DOWNLOAD_CURL_FLAGS}"
  done

  echo "configuring zookeeper properties for kafka..."
  cluster_size="${#ZK_HOSTS[@]}"
  for n in "${ZK_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    broker_id="$(ni::resolve_node_id "${n}")"
    ni::kafka::configure "${remote}" "${broker_id}" "${ZK_CONNECT}" "${cluster_size}"
    ni::kafka::systemd "${remote}"
  done

  echo "starting kafka/zookeeper and enabling the managed services..."
  for n in "${ZK_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::zk::enable_start "${remote}"
    ni::kafka::enable_start "${remote}"
  done

  echo "installing nifi components (v ${NIFI_VERSION})..."
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::nifi::install "${remote}" "${NIFI_VERSION}" "${NIFI_USER}" "${DOWNLOAD_CURL_FLAGS}"
  done

  echo "installing nifi toolkit (v ${NIFI_TOOLKIT_VERSION})..."
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::nifi::install_toolkit "${remote}" "${NIFI_TOOLKIT_VERSION}" "${NIFI_USER}" "${DOWNLOAD_CURL_FLAGS}"
  done
  # Toolkit on registry as well
  if [ -n "${registry_host}" ]; then
    remote="${installer}@${registry_host}"
    ni::nifi::install_toolkit "${remote}" "${NIFI_TOOLKIT_VERSION}" "${NIFI_USER}" "${DOWNLOAD_CURL_FLAGS}"
  fi

  echo "installing nifi registry components (v ${NIFI_VERSION})..."
  if [ -n "${registry_host}" ]; then
    remote="${installer}@${registry_host}"
    ni::registry::install "${remote}" "${NIFI_VERSION}" "${NIFI_USER}" "${DOWNLOAD_CURL_FLAGS}"
  fi

  # --- TLS (cluster CA, per-node bundles) if secure ---
  export KEYSTORE_PASSWD=${KEYSTORE_PASSWD}
  export TRUSTSTORE_PASSWD=${TRUSTSTORE_PASSWD}
  if [ "${secure}" = true ]; then
    peers_for_certs=("${NIFI_HOSTS[@]}")
    [ -n "${registry_host}" ] && peers_for_certs+=("${registry_host}")
    ni::certs::ensure_cluster_tls "${installer}" "${NIFI_USER}" "${peers_for_certs[@]}"
  fi

  # --- nifi.properties (common: ZK_CONNECT from first three; then per-node) ---
  echo "updating nifi configuration (common properties and security certificates)..."
  export SENSITIVE_KEY=${SENSITIVE_KEY}
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::nifi::configure "${remote}" "${secure}" "${ZK_CONNECT}" "${NIFI_USER}"
  done
  if [ -n "${registry_host}" ]; then
    remote="${installer}@${registry_host}"
    ni::registry::configure "${remote}" "${secure}" "${registry_host}"
  fi

  echo "configuring NiFi flowfile + database repositories (NiFi nodes only)..."
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    # make sure dirs exist and are owned by NIFI_USER
    ni::nifi::ensure_flow_and_db_dirs "${remote}" "${NIFI_USER}" \
    "${FLOWFILE_DIR}" "${DATABASE_DIR}"
    [ "${TRACE:-false}" = true ] && {
      echo "TRACE repos (local): flowfile=${FLOWFILE_DIR}"
      echo "TRACE repos (local): database=${DATABASE_DIR}"
    }
    # write nifi.properties keys
    ni::nifi::configure_flow_and_db "${remote}" \
      "${FLOWFILE_DIR}" "${DATABASE_DIR}"
  done

  echo "updating NiFi repository directories from Terraform-provided mounts (NiFi nodes only)..."
  if ((${#CONTENT_DIRS[@]} == 0 && ${#PROVENANCE_DIRS[@]} == 0)); then
    echo "WARN: no --content-dir/--provenance-dir provided; leaving defaults"
  else
    for n in "${NIFI_NODES[@]}"; do
      remote="${installer}@$(ni::resolve_host "${n}")"
      # ensure dirs exist & ownership (idempotent). We do NOT mount here.
      ni::nifi::ensure_repo_dirs "${remote}" "${NIFI_USER}" \
        --content "${CONTENT_DIRS[@]}" \
        --provenance "${PROVENANCE_DIRS[@]}"
      [ "${TRACE:-false}" = true ] && {
        echo "TRACE repos (local): content=(${CONTENT_DIRS[*]})"
        echo "TRACE repos (local): provenance=(${PROVENANCE_DIRS[*]})"
      }
      # write nifi.properties keys
      ni::nifi::configure_repos "${remote}" \
        --content "${CONTENT_DIRS[@]}" \
        --provenance "${PROVENANCE_DIRS[@]}"
    done
  fi

  # --- authorizers.xml: add node identities (CN=<host>) ---
  peers_for_auth=("${NIFI_HOSTS[@]}")
  [ -n "${registry_host}" ] && peers_for_auth+=("${registry_host}")
  # 1) NiFi nodes: add Node Identity entries
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::nifi::authorizers_add_nodes "${remote}" "${NIFI_USER}" "${peers_for_auth[@]}"
  done
  # 2) Registry: seed identities of nodes
  if [ -n "${registry_host:-}" ]; then
    remote="${installer}@$(ni::resolve_host "${registry_host}")"
    ni::registry::authorizers_add_nodes "${remote}" "${NIFI_USER}" "${peers_for_auth[@]}"
  fi

  echo "updating nifi memory configurations for this installation..."
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::nifi::set_heap "${remote}" "${NIFI_HEAP}"
  done

  echo "updating the configuration to change the log file location and rollover policies for nifi..."
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::nifi::configure_logging "${remote}" "${NIFI_USER}" "${NIFI_LOG_DIR}" "${LOG_MAX_SIZE}" "${LOG_MAX_HISTORY}"
  done
  if [ -n "${registry_host}" ]; then
    remote="${installer}@$(ni::resolve_host "${registry_host}")"
    ni::registry::configure_logging "${remote}" "${NIFI_USER}" "${LOG_MAX_SIZE}" "${LOG_MAX_HISTORY}"
  fi

  echo "updating configurations for IO intensive operations on Linux..."
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::nifi::tune_linux_io "${remote}" "${NIFI_USER}"
  done

  echo "updating nifi configuration files to point from the current working directory to NIFI_HOME / NIFI_REGISTRY_HOME..."
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    # If you want to pass single-user creds, set these vars/flags and forward them:
    # ni::nifi::ensure_env_vars "$remote" "$NIFI_USER" "$SINGLE_USER_NAME" "$SINGLE_USER_PASSWORD"
    ni::nifi::ensure_env_vars "$remote" "$NIFI_USER"
  done
  if [ -n "${registry_host:-}" ]; then
    remote="${installer}@$(ni::resolve_host "${registry_host}")"
    ni::registry::ensure_env_vars "$remote"
  fi

  echo "creating a system unit files for nifi..."
  # NiFi services
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    # is this host part of the ZK quorum?
    is_zk=false
    for z in "${ZK_NODES[@]}"; do [ "$z" = "$n" ] && is_zk=true; done
    ni::nifi::systemd "${remote}" "${is_zk}"
  done
  # Registry service
  if [ -n "${registry_host}" ]; then
    remote="${installer}@$(ni::resolve_host "${registry_host}")"
    ni::registry::systemd "${remote}"
  fi

  echo "installing avro and postgres components for python3..."
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::nifi::python_components "${remote}"
  done

  echo "starting nifi and enabling the managed services..."
  for n in "${NIFI_NODES[@]}"; do
    remote="${installer}@$(ni::resolve_host "${n}")"
    ni::nifi::enable_start "${remote}"
  done
  if [ -n "${registry_host}" ]; then
    remote="${installer}@$(ni::resolve_host "${registry_host}")"
    ni::registry::enable_start "${remote}"
  fi

  if [ "${secure}" = true ]; then
    export NIFI_USER=${NIFI_USER}
    export NIFI_NODES=${NIFI_NODES}
    if ni::nifi::wait_nifi_cluster_ready; then
      echo "NiFi cluster healthy. Proceeding with auth/policy setup…"
      ni::auth::grant_nodes
    else
      echo "NiFi cluster did not become healthy. Aborting auth setup."
      exit 1
    fi
  fi

  if [ -n "${registry_host}" ]; then
    export NIFI_USER=${NIFI_USER}
    export NIFI_NODES=${NIFI_NODES}
    export REGISTRY_HOST=${registry_host}
    ni::nifi::ensure_registry_client
    # reg::auth::bootstrap "NiFi Flows"
  fi

  if [ -n "${registry_host}" ] && [ -n "${GH_URL}" ]; then
    export GIT_TOKEN=${GIT_TOKEN}
    remote="${installer}@$(ni::resolve_host "${registry_host}")"
    ni::git::configure ${remote} "${GH_URL}" "${GH_USERNAME}" "${GH_USERTEXT}" "${GH_EMAIL}" \
      "${GH_BRANCH}" "${GH_DIRECTORY}" "${GH_REMOTE_NAME}" "${NIFI_USER}" "${NIFI_USER}"
    ni::git::verify_git_provider ${remote}
  fi

  echo "New-cluster install complete."
}

# --- Main dispatcher --------------------------------------------------------
OP="${OP:-new-cluster}"
case "${OP}" in
  new-cluster)
    echo ">> nifi-install: OP=${OP}, nodes=(${NODE_ARGS[*]}), registry_host=${registry_host}, secure=${secure}"
    ni::op::new_cluster "${NODE_ARGS[@]}"
    ;;
  *)
    ni::die "Unknown OP='${OP}'"
    ;;
esac
