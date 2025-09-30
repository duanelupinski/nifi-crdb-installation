#!/usr/bin/env bash
set -euo pipefail

############################################
# Defaults (CLI can override)
############################################
MONGO_INSTANCE_NAME="mongo-dev"         # Multipass VM name
MONGO_TLS_DIR="/etc/ssl/mongo"          # where certs go inside the VM

SSH_USER="ubuntu"                       # remote user for NiFi nodes
SSH_KEY="${HOME}/.ssh/id_rsa"           # path to SSH key (or rely on ssh-agent)

# If your NiFi nodes use a non-default JVM, set the exact cacerts path here:
# JAVA_CACERTS_PATH="/usr/lib/jvm/java-17-openjdk-amd64/lib/security/cacerts"
JAVA_CACERTS_PATH=""

# Mongo CA identity (separate from any NiFi CA)
NIFI_CA_ALIAS="mongo_server_ca"
DEST_DIR="$(pwd)/.private/mongo-certs"

usage() {
  cat <<EOF
usage: $0 [options] <hostname> [<hostname> ...]

you'll also need to provide the password for the trust store
  $ export TRUSTSTORE_PASSWD='******'

Options:
  --mongo-name    Multipass VM name, defaults to $MONGO_INSTANCE_NAME
  --mongo-tls     where certs go inside the VM, defaults to $MONGO_TLS_DIR
  --ssh-user      remote user for NiFi nodes, defaults to $SSH_USER
  --ssh-key       path to SSH key (or rely on ssh-agent), defaults to $SSH_KEY
  --java-ca-path  path where cacerts live on host, defaults to $JAVA_CACERTS_PATH
  --ca-alias      defaults to $NIFI_CA_ALIAS
  --dest-dir      local destination folder for mongo certs, defaults to $DEST_DIR
  -h, --help
EOF
}

# ---- parse args ----
while (( "$#" )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --mongo-name)    MONGO_INSTANCE_NAME="$2"; shift 2 ;;
    --mongo-tls)     MONGO_TLS_DIR="$2"; shift 2 ;;
    --ssh-user)      SSH_USER="$2"; shift 2 ;;
    --ssh-key)       SSH_KEY="$2"; shift 2 ;;
    --java-ca-path)  JAVA_CACERTS_PATH="$2"; shift 2 ;;
    --ca-alias)      NIFI_CA_ALIAS="$2"; shift 2 ;;
    --dest-dir)      DEST_DIR="$2"; shift 2 ;;
    --) shift; break ;;
    -*) echo "WARN: unknown option: $1" >&2; shift ;;
    *) break ;;
  esac
done

if (( "$#" == 0 )); then
  echo "ERROR: provide at least one hostname"; usage; exit 1
fi
NIFI_NODES=("$@")

############################################
# Helper Functions
############################################
log()  { echo -e "\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
err()  { echo -e "\033[1;31m[x] $*\033[0m"; }

ssh_cmd() {
  local host="$1"; shift
  if [[ -n "${SSH_KEY:-}" && -f "$SSH_KEY" ]]; then
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${host}" "$@"
  else
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${host}" "$@"
  fi
}

scp_put() {
  local src="$1" host="$2" dest="$3"
  if [[ -n "${SSH_KEY:-}" && -f "$SSH_KEY" ]]; then
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$src" "${SSH_USER}@${host}:$dest"
  else
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$src" "${SSH_USER}@${host}:$dest"
  fi
}

detect_remote_cacerts() {
  local host="$1"
  if [[ -n "$JAVA_CACERTS_PATH" ]]; then echo "$JAVA_CACERTS_PATH"; return; fi
  ssh_cmd "$host" 'set -e
  JAVA_BIN=$(command -v java || true)
    if [[ -z "$JAVA_BIN" ]]; then echo ""; exit 0; fi
    REAL_JAVA=$(readlink -f "$JAVA_BIN")
    CAND=$(dirname "$REAL_JAVA")/../lib/security/cacerts
    if [[ -f "$CAND" ]]; then echo "$CAND"; exit 0; fi
    for p in /usr/lib/jvm/*/lib/security/cacerts /Library/Java/JavaVirtualMachines/*/Contents/Home/lib/security/cacerts; do
      [[ -f "$p" ]] && { echo "$p"; exit 0; }
    done
    echo ""'
}

############################################
# Ensure multipass present and get Mongo VM IP
############################################
need() { command -v "$1" >/dev/null || { err "missing: $1"; exit 1; }; }
need multipass; need ssh; need scp; need keytool || true

[[ -n "${TRUSTSTORE_PASSWD:-}" ]] || { err "TRUSTSTORE_PASSWD not set"; exit 1; }

mkdir -p "$DEST_DIR/_ca" "$DEST_DIR/${MONGO_INSTANCE_NAME}"

log "Fetching IP for '${MONGO_INSTANCE_NAME}'..."
if command -v jq >/dev/null 2>&1; then
  MONGO_IP="$(multipass info "$MONGO_INSTANCE_NAME" --format json | jq -r '.info["'"$MONGO_INSTANCE_NAME"'"].ipv4[0]')"
else
  MONGO_IP="$(multipass info "$MONGO_INSTANCE_NAME" | awk '/IPv4/ {print $2; exit}')"
  [[ -n "${MONGO_IP:-}" ]] || MONGO_IP="$(multipass info "$MONGO_INSTANCE_NAME" --format json | tr -d '\n' | sed -nE 's/.*"ipv4"[[:space:]]*:[[:space:]]*\[[[:space:]]*"([^"]+)".*/\1/p')"
fi
[[ -n "${MONGO_IP:-}" ]] || { err "Could not determine VM IP. Is the instance running?"; exit 1; }
log "Mongo VM IP: ${MONGO_IP}"

############################################
# Copy certs from Mongo VM to local destination folder
############################################
CA_KEY="${DEST_DIR}/_ca/ca.key"
CA_CRT="${DEST_DIR}/_ca/ca.crt"
SRV_KEY="${DEST_DIR}/${MONGO_INSTANCE_NAME}/mongo.key"
SRV_CRT="${DEST_DIR}/${MONGO_INSTANCE_NAME}/mongo.crt"
SRV_PEM="${DEST_DIR}/${MONGO_INSTANCE_NAME}/mongo.pem"

log "Pulling certs from VM..."
PUBKEY="$(cat ${SSH_KEY}.pub)"
multipass exec $MONGO_INSTANCE_NAME -- bash -lc "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$PUBKEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh_cmd "$MONGO_IP" "sudo cat ${MONGO_TLS_DIR}/ca.key" > "$CA_KEY"
ssh_cmd "$MONGO_IP" "sudo cat ${MONGO_TLS_DIR}/ca.crt" > "$CA_CRT"
ssh_cmd "$MONGO_IP" "sudo cat ${MONGO_TLS_DIR}/server.key" > "$SRV_KEY" || true
ssh_cmd "$MONGO_IP" "sudo cat ${MONGO_TLS_DIR}/server.crt" > "$SRV_CRT" || true
ssh_cmd "$MONGO_IP" "sudo cat ${MONGO_TLS_DIR}/server.pem" > "$SRV_PEM" || true

############################################
# Import CA into NiFi JVM truststores
############################################
for host in "${NIFI_NODES[@]}"; do
  log "Processing NiFi node: ${host}"
  if ! ssh_cmd "$host" "echo ok" >/dev/null 2>&1; then
    warn "Cannot SSH to ${host}; skipping CA import."
    continue
  fi

  scp_put "$CA_CRT" "$host" "/tmp/ca.crt"
  CACERTS_PATH="$(detect_remote_cacerts "$host")"
  if [[ -z "$CACERTS_PATH" ]]; then
    warn "Could not detect JVM cacerts on ${host}; skipping."
    continue
  fi
  log "Remote cacerts on ${host}: ${CACERTS_PATH}"

  ssh_cmd "$host" "
    sudo keytool -delete -alias ${NIFI_CA_ALIAS} -keystore '${CACERTS_PATH}' -storepass '${TRUSTSTORE_PASSWD}' >/dev/null 2>&1 || true
    sudo keytool -importcert -alias ${NIFI_CA_ALIAS} -file /tmp/ca.crt -keystore '${CACERTS_PATH}' -storepass '${TRUSTSTORE_PASSWD}' -noprompt
    sudo systemctl restart nifi || true
    sleep 1; sudo systemctl is-active nifi || true
  "
done

log "Done."
