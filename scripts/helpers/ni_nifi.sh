#!/usr/bin/env bash
# NiFi install, user hardening, and config

ni::nifi::user() {
  local remote="$1" user="${2:-nifi}"
  ni::ssh_sudo "$remote" $'id -u '"$user"' >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin '"$user"
}

# --- Install Apache NiFi and set env vars (JAVA_HOME, NIFI_HOME) ---
ni::nifi::install() {
  local remote="$1" ver="$2" user="$3" curl_flags="${4:-}"
  ni::ssh_sudo "$remote" bash -s -- "$ver" "$user" "$curl_flags" <<'REMOTE'
set -o errexit -o nounset -o pipefail
ver="$1"; user="$2"; curl_flags="$3"

dir="nifi-${ver}"
zip="nifi-${ver}-bin.zip"
url1="https://dlcdn.apache.org/nifi/${ver}/${zip}"
url2="https://archive.apache.org/dist/nifi/${ver}/${zip}"

# ensure deps
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip

mkdir -p /opt
cd /opt

if [ ! -d "$dir" ]; then
  echo "downloading NiFi $ver"
  (curl $curl_flags -fL -o "$zip" "$url1" || curl $curl_flags -fL -o "$zip" "$url2")
  unzip -q -o "$zip"
  rm -f "$zip"
fi

sudo chown -R $user:$user "$dir"
ln -sfn "$dir" nifi
chown -R $user:$user /opt/nifi
chmod -R a+rx "/opt/$dir/bin"

# derive JAVA_HOME from java in PATH (fallback to OpenJDK 21 location)
JAVA_BIN="$(command -v java || true)"
if [ -n "$JAVA_BIN" ]; then
  JAVA_HOME="$(readlink -f "$JAVA_BIN" | sed 's:/bin/java$::')"
fi

# helper to upsert KEY=VALUE in a file (idempotent)
set_kv() {
  local key="$1" val="$2" file="$3"
  [ -n "${val}" ] || return 0
  local esc; esc="$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')"
  if grep -qE "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${esc}|" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >>"$file"
  fi
}

# persist env for services and logins
set_kv "JAVA_HOME" "${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-arm64}" /etc/environment
set_kv "NIFI_HOME" "/opt/nifi" /etc/environment

printf 'export JAVA_HOME=%s\n' "${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-arm64}" > /etc/profile.d/java_home.sh
printf 'export NIFI_HOME=%s\n' "/opt/nifi" > /etc/profile.d/nifi_home.sh
chmod 0644 /etc/profile.d/java_home.sh /etc/profile.d/nifi_home.sh
REMOTE
}

# --- Install NiFi Toolkit and set NIFI_TOOLKIT_HOME ---
ni::nifi::install_toolkit() {
  local remote="$1" ver="$2" user="$3" curl_flags="${4:-}"
  ni::ssh_sudo "$remote" bash -s -- "$ver" "$user" "$curl_flags" <<'REMOTE'
set -o errexit -o nounset -o pipefail
ver="$1"; user="$2"; curl_flags="$3"

# xmlstarlet used for configuration file edits
which xmlstarlet &> /dev/null || sudo apt-get install -y xmlstarlet

dir="nifi-toolkit-${ver}"
zip="nifi-toolkit-${ver}-bin.zip"
url1="https://dlcdn.apache.org/nifi/${ver}/${zip}"
url2="https://archive.apache.org/dist/nifi/${ver}/${zip}"

# ensure deps
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip

mkdir -p /opt
cd /opt

if [ ! -d "$dir" ]; then
  echo "downloading NiFi Toolkit $ver"
  (curl $curl_flags -fL -o "$zip" "$url1" || curl $curl_flags -fL -o "$zip" "$url2")
  unzip -q -o "$zip"
  rm -f "$zip"
fi

sudo chown -R $user:$user "$dir"
ln -sfn "$dir" nifi-toolkit
chown -R $user:$user /opt/nifi-toolkit
chmod -R a+rx "/opt/$dir/bin"

# helper to upsert KEY=VALUE in a file (idempotent)
set_kv() {
  local key="$1" val="$2" file="$3"
  [ -n "${val}" ] || return 0
  local esc; esc="$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')"
  if grep -qE "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${esc}|" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >>"$file"
  fi
}

# persist env for services and logins
set_kv "NIFI_TOOLKIT_HOME" "/opt/nifi-toolkit" /etc/environment
printf 'export NIFI_TOOLKIT_HOME=%s\n' "/opt/nifi-toolkit" > /etc/profile.d/nifi_toolkit_home.sh
chmod 0644 /etc/profile.d/nifi_toolkit_home.sh
REMOTE
}

# Common nifi.properties updates shared by all nodes
# Usage: ni::nifi::configure_common <ssh-remote> <secure:true|false> <zk_connect> [nifi_user]
ni::nifi::configure() {
  local remote="$1" secure="$2" zk_connect="$3" user="${4:-nifi}"
  ni::ssh_sudo_stdin "$remote" env KEY="${SENSITIVE_KEY:-}" KS_PWD="${KEYSTORE_PASSWD:-}" \
    TS_PWD="${TRUSTSTORE_PASSWD:-}" bash -s -- "$secure" "$zk_connect" "$user" <<'RSH'
set -o errexit -o nounset -o pipefail
SECURE="$1"; ZK="$2"; NIFI_USER="$3";
NIFI_HOME="${NIFI_HOME:-/opt/nifi}"
CONF="$NIFI_HOME/conf/nifi.properties"
HOST="$(hostname)"
CERTS="$NIFI_HOME/certs"

[ -f "$CONF" ] || { echo "ERROR: $CONF not found"; exit 2; }

if [ -z "${KEY}" ]; then
  echo "ERROR: nifi.sensitive.props.key is empty" >&2
  exit 3
fi

# idempotent setter
setprop() {
  local k="$1" v="${2-}"
  if grep -qE "^${k}=" "$CONF"; then
    sed -i -e "s|^${k}=.*|${k}=${v}|" "$CONF"
  else
    printf '%s=%s\n' "$k" "$v" >> "$CONF"
  fi
}

# zookeeper
setprop nifi.state.management.embedded.zookeeper.start false
setprop nifi.zookeeper.connect.string "$ZK"

# cluster
setprop nifi.cluster.protocol.is.secure "$SECURE"
setprop nifi.cluster.is.node true
setprop nifi.cluster.node.address "$HOST"
if [ "$SECURE" = "true" ]; then
  setprop nifi.cluster.node.protocol.port 11443
else
  setprop nifi.cluster.node.protocol.port 9997
fi
setprop nifi.cluster.node.protocol.threads 50
setprop nifi.cluster.node.protocol.max.threads 50
setprop nifi.cluster.node.event.history.size 25
setprop nifi.cluster.node.connection.timeout "30 sec"
setprop nifi.cluster.node.read.timeout "30 sec"
setprop nifi.cluster.node.max.concurrent.requests 100
setprop nifi.cluster.firewall.file ""
setprop nifi.cluster.load.balance.host "$HOST"
setprop nifi.cluster.load.balance.connections.per.node 4
setprop nifi.cluster.load.balance.max.thread.count 12

# remote
setprop nifi.remote.input.host "$HOST"
setprop nifi.remote.input.secure "$SECURE"
if [ "$SECURE" = "true" ]; then
  setprop nifi.remote.input.socket.port 10443
else
  setprop nifi.remote.input.socket.port 9998
fi
setprop nifi.remote.input.http.enabled true
setprop nifi.remote.input.http.transaction.ttl "30 sec"

# HTTP(S) ports — exactly one
if [ "$SECURE" = "true" ]; then
  setprop nifi.web.http.host ""
  setprop nifi.web.http.port ""
  setprop nifi.web.https.host "$HOST"
  setprop nifi.web.https.port 9443
else
  setprop nifi.web.http.host "$HOST"
  setprop nifi.web.http.port 8080
  setprop nifi.web.https.host ""
  setprop nifi.web.https.port ""
fi

# sensitive props key (required in NiFi 2.x)
setprop nifi.sensitive.props.key "$KEY"

# Performance
setprop nifi.bored.yield.duration "100 millis"
setprop nifi.cluster.flow.election.max.wait.time "1 min"
setprop nifi.cluster.flow.election.max.candidates 3
setprop nifi.queue.swap.threshold 50000

# security
if [ "$SECURE" = "true" ] && [ -f "${CERTS}/keystore.p12" ] && [ -f "${CERTS}/truststore.p12" ]; then
  setprop nifi.security.keystore "${CERTS}/keystore.p12"
  setprop nifi.security.keystoreType "PKCS12"
  setprop nifi.security.keystorePasswd "${KS_PWD}"
  setprop nifi.security.keyPasswd "${KS_PWD}"
  setprop nifi.security.truststore "${CERTS}/truststore.p12"
  setprop nifi.security.truststoreType "PKCS12"
  setprop nifi.security.truststorePasswd "${TS_PWD}"
  setprop nifi.security.identity.mapping.pattern.1 "^OU=([^,]+), CN=([^,]+)$"
  setprop nifi.security.identity.mapping.value.1 "CN=\$2, OU=\$1"
  setprop nifi.security.identity.mapping.transform.1 "NONE"
fi

# Make sure the nifi user owns dirs it needs to write to (not the whole distro)
chown -R "$NIFI_USER:$NIFI_USER" "$NIFI_HOME" 2>/dev/null || true

# finally, update zk connection string in state management config
xmlstarlet ed -P -L -u /stateManagement/cluster-provider/property[@name='"Connect String"'] -v "${ZK}" $NIFI_HOME/conf/state-management.xml
RSH
}

# Ensure flowfile + database repo dirs exist and are owned by nifi
# Usage: ni::nifi::ensure_flow_and_db_dirs <ssh-remote> <nifi_user> <flow_dir> <db_dir>
ni::nifi::ensure_flow_and_db_dirs() {
  local remote="$1" user="$2" flow="$3" db="$4"
  ni::ssh_sudo "$remote" bash -s -- "$user" "$flow" "$db" <<'BASH'
set -o errexit -o nounset -o pipefail
user="$1"; flow="$2"; db="$3"

ensure_dir() {
  local d="$1"
  [ -n "${d:-}" ] || return 0
  mkdir -p "$d"
  chown -R "$user:$user" "$d"
}
ensure_dir "$flow"
ensure_dir "$db"
BASH
}

# Write flowfile + database repo paths into /opt/nifi/conf/nifi.properties
# Usage: ni::nifi::configure_flow_and_db <ssh-remote> <flow_dir> <db_dir>
ni::nifi::configure_flow_and_db() {
  local remote="$1" flow="$2" db="$3"
  ni::ssh_sudo "$remote" bash -s -- "$flow" "$db" <<'BASH'
set -o errexit -o nounset -o pipefail
flow="$1"; db="$2"
CONF="$NIFI_HOME/conf/nifi.properties"

[ -f "$CONF" ] || { echo "ERROR: $CONF not found"; exit 2; }

setprop() {
  local k="$1" v="${2-}"
  if grep -qE "^${k}=" "$CONF"; then
    sed -i -e "s|^${k}=.*|${k}=${v}|" "$CONF"
  else
    printf '%s=%s\n' "$k" "$v" >> "$CONF"
  fi
}

[ -n "${flow:-}" ] && setprop "nifi.flowfile.repository.directory" "$flow"
[ -n "${db:-}"   ] && setprop "nifi.database.directory" "$db"
BASH
}

# Ensure content/provenance repo dirs exist and ownership is set.
# Call-site supported (your current usage):
#   ni::nifi::ensure_repo_dirs "<remote>" "<NIFI_USER>" --content ... --provenance ...
ni::nifi::ensure_repo_dirs() {
  local remote="${1:?remote required}"; shift
  # Support legacy: optional explicit user as 2nd arg
  local nifi_user="${NIFI_USER:-nifi}"
  if (($#)) && [[ "$1" != --* ]]; then nifi_user="$1"; shift; fi

  local content_dirs=() prov_dirs=() mode=""
  while (($#)); do
    case "$1" in
      --content)    mode="content"; shift ;;
      --provenance) mode="prov";    shift ;;
      *)
        if   [[ "$mode" == "content" ]]; then content_dirs+=("$1")
        elif [[ "$mode" == "prov"    ]]; then prov_dirs+=("$1")
        else echo "WARN: ensure_repo_dirs: ignoring arg '$1'" >&2
        fi
        shift
      ;;
    esac
  done

  # Convert lists to CSV so we can pass as simple args to the remote script
  local content_csv prov_csv
  content_csv="$(IFS=,; echo "${content_dirs[*]-}")"
  prov_csv="$(IFS=,; echo "${prov_dirs[*]-}")"

  # Run the remote script with sudo context; no naked `set` (which prints env)
  local rs
  rs=$(cat <<'EOS'
set -o errexit -o nounset -o pipefail
nifi_user="$1"; content_csv="$2"; prov_csv="$3"

# Expand CSVs
IFS=',' read -r -a content_dirs <<< "${content_csv:-}"
IFS=',' read -r -a prov_dirs    <<< "${prov_csv:-}"

ensure_dir() {
  local d="$1"
  [ -n "${d:-}" ] || return 0
  install -d -o "$nifi_user" -g "$nifi_user" -m 0755 "$d"
}

for d in "${content_dirs[@]}"; do ensure_dir "$d"; done
for d in "${prov_dirs[@]}";   do ensure_dir "$d"; done

# Soft warn if not mounted yet (use findmnt; don’t fail)
is_mnt(){ /usr/bin/findmnt -rn --target "$1" >/dev/null 2>&1; }
for d in "${content_dirs[@]}"; do [ -z "${d:-}" ] || is_mnt "$d" || echo "WARN: $d is not a mountpoint" >&2; done
for d in "${prov_dirs[@]}";   do [ -z "${d:-}" ] || is_mnt "$d" || echo "WARN: $d is not a mountpoint" >&2; done
EOS
)
  ni::ssh_sudo "$remote" bash -s -- "$nifi_user" "$content_csv" "$prov_csv" <<< "$rs"
}

# Write content/provenance directories to /opt/nifi/conf/nifi.properties.
# Call-site supported (your current usage):
#   ni::nifi::configure_repos "<remote>" --content ... --provenance ...
ni::nifi::configure_repos() {
  local remote="${1:?remote required}"; shift
  local content_dirs=() prov_dirs=() mode=""

  while (($#)); do
    case "$1" in
      --content)      mode="content"; shift ;;
      --provenance)   mode="prov";    shift ;;
      *)
        if   [[ "$mode" == "content" ]]; then content_dirs+=("$1")
        elif [[ "$mode" == "prov"    ]]; then prov_dirs+=("$1")
        else echo "WARN: configure_repos: ignoring arg '$1'" >&2
        fi
        shift
      ;;
    esac
  done

  local content_csv prov_csv
  content_csv="$(IFS=,; echo "${content_dirs[*]-}")"
  prov_csv="$(IFS=,; echo "${prov_dirs[*]-}")"

  local rs
  rs=$(cat <<'EOS'
set -o errexit -o nounset -o pipefail
content_csv="$1"; prov_csv="$2"

NIFI_HOME="${NIFI_HOME:-/opt/nifi}"
PROP="$NIFI_HOME/conf/nifi.properties"
[ -f "$PROP" ] || { echo "ERROR: $PROP not found" >&2; exit 1; }

setprop() {
  local key="$1" val="$2" file="$3"
  local esc; esc="$(printf '%s' "$val" | sed -e 's/[\/&]/\\&/g')"
  if grep -qE "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${esc}|" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >> "$file"
  fi
}

unsetprop() {
  local key="$1" file="$2"
  if grep -qE "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|#${key}=|g" "$file"
  fi
}

# comment out the default repository values to effectively hide them
unsetprop nifi.content.repository.directory.default "$PROP"
unsetprop nifi.provenance.repository.directory.default "$PROP"

# Expand CSVs
IFS=',' read -r -a content_dirs <<< "${content_csv:-}"
IFS=',' read -r -a prov_dirs    <<< "${prov_csv:-}"

# Clear any old numbered keys first (avoid leftovers on re-runs)
sed -i '/^nifi\.content\.repository\.directory\.content[0-9]\+=/d' "$PROP"
sed -i '/^nifi\.provenance\.repository\.directory\.provenance[0-9]\+=/d' "$PROP"

# Content repo mapping: content1..N
if [ "${#content_dirs[@]}" -ge 1 ] && [ -n "${content_dirs[0]:-}" ]; then
  idx=1
  for ((i=0;i<${#content_dirs[@]};i++)); do
    d="${content_dirs[$i]}"; [ -z "${d:-}" ] && continue
    setprop "nifi.content.repository.directory.content${idx}" "$d" "$PROP"
    idx=$((idx+1))
  done
fi

# Provenance repo mapping: provenance1..N
if [ "${#prov_dirs[@]}" -ge 1 ] && [ -n "${prov_dirs[0]:-}" ]; then
  idx=1
  for ((i=0;i<${#prov_dirs[@]};i++)); do
    d="${prov_dirs[$i]}"; [ -z "${d:-}" ] && continue
    setprop "nifi.provenance.repository.directory.provenance${idx}" "$d" "$PROP"
    idx=$((idx+1))
  done
fi

echo "Updated repository directories in $PROP"
EOS
)
  ni::ssh_sudo "$remote" bash -s -- "$content_csv" "$prov_csv" <<< "$rs"
}

# NiFi: replace Node Identity list with the provided hosts (idempotent)
# Usage: ni::nifi::authorizers_add_nodes <ssh-remote> <username> <host1> [host2...]
ni::nifi::authorizers_add_nodes() {
  local remote="$1"; shift
  local username="$1"; shift
  local nodes=("$@")

  # Run the script remotely under *bash* with sudo
  ni::ssh_sudo "$remote" /bin/bash -s -- "${username}" "${nodes[@]}" <<'BASH'
set -o errexit -o nounset -o pipefail

username="$1"; shift  # remaining "$@" are node hosts

NIFI_HOME="${NIFI_HOME:-/opt/nifi}"
AUTH="$NIFI_HOME/conf/authorizers.xml"
[ -f "$AUTH" ] || { echo "WARN: $AUTH not found; skipping"; exit 0; }

# Ensure xmlstarlet is available
if ! command -v xmlstarlet >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -y >/dev/null 2>&1 || true
  sudo apt-get install -y xmlstarlet
fi

# ---------------------------
# userGroupProvider edits
# ---------------------------
# Initial User Identity 1 -> admin DN (keep original XPath quoting)
xmlcmd="xmlstarlet ed -P -L \
  -u /authorizers/userGroupProvider/property[@name='\"Initial User Identity 1\"'] \
  -v \"CN=${username}, OU=NIFI\""

# For each node: node-id = (index+1), then +2 for 'Initial User Identity N'
i=1
for host in "$@"; do
  i=$((i+1))

  xmlcmd+=" -d /authorizers/userGroupProvider/property[@name='\"Initial User Identity ${i}\"']"
  xmlcmd+=" -s /authorizers/userGroupProvider -t elem -n propertyTMP -v \"CN=${host}, OU=NIFI\""
  xmlcmd+=" -i //propertyTMP -t attr -n name -v \"Initial User Identity ${i}\""
  xmlcmd+=" -r //propertyTMP -v property"
done
xmlcmd+=" \"${AUTH}\""

# Execute the composed command
sudo bash -lc "$xmlcmd"

# ---------------------------
# accessPolicyProvider edits
# ---------------------------
# Initial Admin Identity -> admin DN
xmlcmd="xmlstarlet ed -P -L \
  -u /authorizers/accessPolicyProvider/property[@name='\"Initial Admin Identity\"'] \
  -v \"CN=${username}, OU=NIFI\""

# Recreate Node Identity <nodeid> with node-id = (index+1)
i=0
for host in "$@"; do
  i=$((i+1))

  xmlcmd+=" -d /authorizers/accessPolicyProvider/property[@name='\"Node Identity ${i}\"']"
  xmlcmd+=" -s /authorizers/accessPolicyProvider -t elem -n propertyTMP -v \"CN=${host}, OU=NIFI\""
  xmlcmd+=" -i //propertyTMP -t attr -n name -v \"Node Identity ${i}\""
  xmlcmd+=" -r //propertyTMP -v property"
done
xmlcmd+=" \"${AUTH}\""

sudo bash -lc "$xmlcmd"

# Pretty-print the final XML
tmpfile="$(mktemp)"
xmlstarlet fo -s 4 "$AUTH" > "$tmpfile" && sudo mv "$tmpfile" "$AUTH"
sudo chown ${username}:${username} "$AUTH" || true
sudo chmod 644 "$AUTH" || true
BASH
}

# Set -Xms/-Xmx heap in NiFi bootstrap.conf
# Usage: ni::nifi::set_heap <ssh-remote> <heap>   (e.g., "8g" or "8192m")
ni::nifi::set_heap() {
  local remote="$1" heap="$2"
  ni::ssh_sudo "$remote" bash -s -- "$heap" <<'BASH'
set -o errexit -o nounset -o pipefail
heap="$1"
BOOT="${NIFI_HOME:-/opt/nifi}/conf/bootstrap.conf"
[ -f "$BOOT" ] || { echo "ERROR: $BOOT not found"; exit 2; }

# Replace any existing -Xms/-Xmx in java.args.* lines
sed -i "s/^java.arg.2=.*/java.arg.2=-Xms${heap}/g" "$BOOT"
sed -i "s/^java.arg.3=.*/java.arg.3=-Xmx${heap}/g" "$BOOT"
			
# Make sure the UseG1GC java option is commented out due to a known bug in its implementation
if grep -qE "^java.arg.13=" "$BOOT"; then
  sed -i "s|^java.arg.13=.*|#java.arg.13=-XX:+UseG1GC|" "$BOOT"
fi
BASH
}

# Configure NiFi logback.xml safely. If invalid, rewrite minimal valid XML, then set dir/rollover.
# Usage: ni::nifi::configure_logging <ssh-remote> <log_dir> <max_size> <max_history>
ni::nifi::configure_logging() {
  local remote="$1" username="$2" logdir="$3" maxsize="${4:-100MB}" maxhist="${5:-30}"
  ni::ssh_sudo "$remote" bash -s -- "$username" "$logdir" "$maxsize" "$maxhist" <<'BASH'
set -o errexit -o nounset -o pipefail
username="$1"; logdir="$2"; maxsize="$3"; maxhist="$4"
NIFI_HOME="${NIFI_HOME:-/opt/nifi}"
LB="$NIFI_HOME/conf/logback.xml"

[ -f "$LB" ] || { echo "WARN: $LB not found; skipping"; exit 0; }
install -d -m 0755 -o $username -g $username "$logdir" || true

# Ensure xmlstarlet is available
if ! command -v xmlstarlet >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -y >/dev/null 2>&1 || true
  sudo apt-get install -y xmlstarlet
fi

sed -i "s|^NIFI_LOG_DIR=.*|NIFI_LOG_DIR=\"\$(setOrDefault \"\$NIFI_LOG_DIR\" \"${logdir}\")\"|g" "${NIFI_HOME}/bin/nifi-env.sh"
xmlstarlet ed -P -L -u /configuration/appender[@name='"APP_FILE"']/rollingPolicy/maxHistory -v ${maxhist} "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"APP_FILE"']/rollingPolicy/totalSizeCap -v "${maxsize}" "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"USER_FILE"']/rollingPolicy/maxHistory -v ${maxhist} "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"USER_FILE"']/rollingPolicy/totalSizeCap -v "${maxsize}" "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"REQUEST_FILE"']/rollingPolicy/maxHistory -v ${maxhist} "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"REQUEST_FILE"']/rollingPolicy/totalSizeCap -v "${maxsize}" "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"BOOTSTRAP_FILE"']/rollingPolicy/maxHistory -v ${maxhist} "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"BOOTSTRAP_FILE"']/rollingPolicy/totalSizeCap -v "${maxsize}" "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"DEPRECATION_FILE"']/rollingPolicy/maxHistory -v ${maxhist} "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"DEPRECATION_FILE"']/rollingPolicy/totalSizeCap -v "${maxsize}" "${LB}"

chown $username:$username "$LB"
BASH
}

# Safe, common IO/network tunings and file limits for NiFi
# Usage: ni::nifi::tune_linux_io <ssh-remote> <nifi_user>
ni::nifi::tune_linux_io() {
  local remote="$1" user="$2"

  ni::ssh_sudo "$remote" /bin/bash -s -- "$user" <<'BASH'
set -o errexit -o nounset -o pipefail
user="$1"

# Ensure tools and dirs exist
export DEBIAN_FRONTEND=noninteractive
if ! command -v tee >/dev/null 2>&1; then sudo apt-get update -y && sudo apt-get install -y coreutils >/dev/null 2>&1 || true; fi
sudo install -d -m 0755 /etc/sysctl.d
sudo install -d -m 0755 /etc/security/limits.d

# ---- sysctl: ----
sudo tee /etc/sysctl.d/99-nifi.conf >/dev/null <<'SYS'
vm.swappiness=1
vm.dirty_ratio=20
vm.dirty_background_ratio=10
net.core.somaxconn=4096
fs.file-max=2097152
SYS

# Also set ip_local_port_range immediately (not usually persisted by distro defaults)
sudo sysctl -w net.ipv4.ip_local_port_range="10000 65535"

# Load everything
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet systemd-sysctl; then
  # Preferred on systemd systems
  sudo sysctl --system
else
  # Fallback to loading our file only
  sudo sysctl -p /etc/sysctl.d/99-nifi.conf || true
fi

# Show what actually applied
sysctl -n vm.swappiness vm.dirty_ratio vm.dirty_background_ratio net.core.somaxconn fs.file-max net.ipv4.ip_local_port_range || true

# ---- PAM limits (note: won’t affect systemd services) ----
sudo tee /etc/security/limits.d/99-nifi.conf >/dev/null <<LIM
${user}    soft    nofile  65535
${user}    hard    nofile  65535
${user}    soft    nproc   10000
${user}    hard    nproc   10000
LIM

# Print the files for verification
echo "--- /etc/sysctl.d/99-nifi.conf ---"
sudo sed -n '1,200p' /etc/sysctl.d/99-nifi.conf || true
echo "--- /etc/security/limits.d/99-nifi.conf ---"
sudo sed -n '1,200p' /etc/security/limits.d/99-nifi.conf || true
BASH
}

# Ensure NiFi configs reference ${NIFI_HOME} instead of "./", and clean up auth config.
# Usage:
#   ni::nifi::ensure_env_vars <ssh-remote> <nifi_user> [admin_user] [admin_pass]
ni::nifi::ensure_env_vars() {
  local remote="$1" nifi_user="$2" admin_user="${3:-}" admin_pass="${4:-}"

  # NOTE: pass args *before* the heredoc via "bash -s -- …"
  ni::ssh "$remote" bash -s -- "$nifi_user" "$admin_user" "$admin_pass" <<'BASH'
set -o errexit -o nounset -o pipefail
nifi_user="$1"; admin_user="${2-}"; admin_pass="${3-}"

NIFI_HOME="${NIFI_HOME:-/opt/nifi}"
H_ESC="$(printf '%s' "$NIFI_HOME" | sed 's/[\/&]/\\&/g')"

# Best-effort install xmlstarlet (quiet)
if ! command -v xmlstarlet >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive sudo apt-get update -y >/dev/null 2>&1 || true
  DEBIAN_FRONTEND=noninteractive sudo apt-get install -y xmlstarlet >/dev/null 2>&1 || true
fi

prop_files=(
  "$NIFI_HOME/conf/zookeeper.properties"
  "$NIFI_HOME/conf/nifi.properties"
  "$NIFI_HOME/conf/bootstrap.conf"
)
xml_files=(
  "$NIFI_HOME/conf/state-management.xml"
  "$NIFI_HOME/conf/authorizers.xml"
)

# 1) Rewrite relative paths to ${NIFI_HOME}
for f in "${prop_files[@]}"; do
  [ -f "$f" ] || continue
  sudo sed -i "s|=\./|=${H_ESC}/|g" "$f"
done
for f in "${xml_files[@]}"; do
  [ -f "$f" ] || continue
  sudo sed -i "s|\./|${H_ESC}/|g" "$f"
done

# 2) Force managed authorizer and disable single-user provider reference
PROP="$NIFI_HOME/conf/nifi.properties"
if [ -f "$PROP" ]; then
  sudo sed -i -E \
    -e 's|^nifi\.security\.user\.authorizer=.*|nifi.security.user.authorizer=managed-authorizer|' \
    -e 's|^nifi\.security\.user\.login\.identity\.provider=.*|#nifi.security.user.login.identity.provider=|' \
    "$PROP" || true
fi

# 3) Remove the single-user-provider block from login-identity-providers.xml (if present)
LIP="$NIFI_HOME/conf/login-identity-providers.xml"
if [ -f "$LIP" ]; then
  sudo xmlstarlet ed -P -L -d "/loginIdentityProviders/provider[identifier='single-user-provider']" "$LIP" || true
fi

# 4) Optionally set single-user credentials if provided (runs as NiFi user)
if [ -n "${admin_user-}" ] && [ -n "${admin_pass-}" ] && command -v nifi >/dev/null 2>&1; then
  sudo -u "$nifi_user" -H bash -lc "nifi set-single-user-credentials '$admin_user' '$admin_pass'" || true
fi

echo "NiFi env/paths/auth config normalized under \$NIFI_HOME=$NIFI_HOME"
BASH
}

# Usage: ni::nifi::systemd <ssh-remote> <is_zk:true|false>
# NiFi service (optionally depend on zookeeper.service when is_zk=true)
ni::nifi::systemd() {
  local remote="$1" is_zk="${2:-false}"
  ni::ssh_sudo "$remote" bash -s -- "$is_zk" <<'BASH'
set -o errexit -o nounset -o pipefail
is_zk="$1"
NIFI_HOME="${NIFI_HOME:-/opt/nifi}"

JAVA_BIN="$(readlink -f "$(command -v java)")"
JAVA_HOME="${JAVA_BIN%/bin/java}"

cat >/etc/systemd/system/nifi.service <<UNIT
[Unit]
Description=Apache NiFi
Wants=network-online.target
After=network-online.target$( [ "$is_zk" = "true" ] && printf " zookeeper.service")
$( [ "$is_zk" = "true" ] && printf "Requires=zookeeper.service\n")

[Service]
Type=simple
User=nifi
Group=nifi
EnvironmentFile=-/etc/environment
Environment=JAVA_HOME=/usr/bin/java
Environment=NIFI_HOME=/opt/nifi
WorkingDirectory=/opt/nifi
ExecStart=/opt/nifi/bin/nifi.sh run
ExecStop=/opt/nifi/bin/nifi.sh stop
TimeoutStartSec=10min
TimeoutStopSec=5min
Restart=on-failure
RestartSec=10s
LimitNOFILE=65535
LimitNPROC=10000

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
BASH
}

# Install avro/fastavro and psycopg (system-wide), then schedule a reboot if required.
ni::nifi::python_components() {
  local remote="$1"
  local rs
  rs=$(cat <<'EOS'
set -o errexit -o nounset -o pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3 python3-pip python3-dev build-essential ca-certificates

# Upgrade pip tooling (ignore apt-managed uninstall warnings)
env PIP_BREAK_SYSTEM_PACKAGES=1 PIP_ROOT_USER_ACTION=ignore \
  python3 -m pip install -U pip setuptools wheel --no-cache-dir --break-system-packages || true

# Install packages *system-wide*
env PIP_BREAK_SYSTEM_PACKAGES=1 PIP_ROOT_USER_ACTION=ignore \
  python3 -m pip install -U "psycopg[binary]" avro fastavro \
  --no-cache-dir --break-system-packages

# Verify (non-fatal here)
python3 - <<'PY' || true
import importlib
mods = ["psycopg","avro","fastavro"]
missing = [m for m in mods if not importlib.util.find_spec(m)]
print("Verify:", "OK" if not missing else ("missing: " + ",".join(missing)))
PY

# Reboot if OS requests it (asynchronously so SSH can exit cleanly)
if [ -f /run/reboot-required ] || [ -f /var/run/reboot-required ]; then
  echo "INFO: reboot required; scheduling in 5s…"
  nohup bash -c "sleep 5; systemctl reboot" >/dev/null 2>&1 &
fi
EOS
)
  ni::ssh_sudo "$remote" bash -s -- <<< "$rs"
}

ni::nifi::enable_start() {
  local remote="$1"
  ni::wait_ssh_or_die "$remote" || ni::die "ssh not reachable for $remote"
  ni::ssh "$remote" "sudo -n bash -s" <<'BASH'
set -o errexit -o nounset -o pipefail
systemctl daemon-reload
systemctl enable nifi
systemctl restart nifi || { echo "---- nifi journal (last 200) ----"; journalctl -u nifi -n 200 --no-pager || true; exit 1; }
systemctl --no-pager --full status nifi || true
BASH
}

# ---------- 1) Wait for each node's API to come up ----------
ni::nifi::wait_nodes_api() {
  local deadline=$(( $(date +%s) + ${1:-600} )) # default 10m
  local node up api
  printf 'Waiting for NiFi REST API on %d nodes…\n' "${#NIFI_NODES[@]}"
  while :; do
    up=0
    for node in "${NIFI_NODES[@]}"; do
      api="$(ni::api::api_base_for "$node")"
      if ni::api::curl_nifi "${api}/flow/about" >/dev/null 2>&1; then
        printf '  - %s: API up\n' "$node"
        : $((up+=1))
      else
        printf '  - %s: not up yet\n' "$node"
      fi
    done
    if (( up == ${#NIFI_NODES[@]} )); then
      echo "All node APIs are responsive."
      return 0
    fi
    if (( $(date +%s) >= deadline )); then
      echo "Timed out waiting for node APIs."
      return 1
    fi
    sleep 5
  done
}

# ---------- 2) Wait for cluster health (all CONNECTED) ----------
ni::nifi::wait_cluster_connected() {
  local controller="${NIFI_NODES[0]}"               # query any node
  local api="$(ni::api::api_base_for "$controller")"
  local deadline=$(( $(date +%s) + ${1:-600} ))     # default 10m
  local want=${#NIFI_NODES[@]}

  echo "Waiting for cluster connectivity (${want} nodes CONNECTED)…"
  while :; do
    # /controller/cluster returns nodes with statuses
    if ! out="$(ni::api::curl_nifi "${api}/controller/cluster" 2>/dev/null)"; then
      echo "  - controller not ready yet"
      sleep 3; continue
    fi

    # Count how many of our expected hosts are present and CONNECTED
    connected=$(jq -r --argjson hosts "$(printf '%s\n' "${NIFI_NODES[@]}" | jq -R . | jq -s .)" '
      .cluster.nodes
      | map({addr: (.address // .nodeAddress // ""), status})
      | map(select(.addr as $a | ($hosts | index($a)) != null and .status=="CONNECTED"))
      | length
    ' <<<"$out")

    total=$(jq -r '.cluster.nodes | length' <<<"$out" 2>/dev/null)

    printf '  - %s/%s of expected nodes CONNECTED (controller sees %s total)\n' "${connected:-0}" "$want" "${total:-?}"

    if [[ -n "$connected" ]] && (( connected == want )); then
      echo "Cluster is healthy: all expected nodes are CONNECTED."
      return 0
    fi

    if (( $(date +%s) >= deadline )); then
      echo "Timed out waiting for full cluster connectivity."
      echo "$out" | jq '.cluster.nodes | map({address,status,roles})' 2>/dev/null || true
      return 1
    fi

    sleep 5
  done
}

# ---------- 3) One-shot convenience gate ----------
ni::nifi::wait_nifi_cluster_ready() {
  ni::nifi::wait_nodes_api 600 && ni::nifi::wait_cluster_connected 600
}

# --- Internal helper: ensure controller-level StandardRestrictedSSLContextService
# Echos the Controller Service ID
ni::nifi::ensure_controller_ssl_service() {
  local api="$1"
  NIFI_HOME="${NIFI_HOME:-/opt/nifi}"
  NIFI_KEYSTORE_FILE="${NIFI_KEYSTORE_FILE:-${NIFI_HOME}/certs/keystore.p12}"
  NIFI_TRUSTSTORE_FILE="${NIFI_TRUSTSTORE_FILE:-${NIFI_HOME}/certs/truststore.p12}"
  NIFI_KEYSTORE_TYPE="${NIFI_KEYSTORE_TYPE:-PKCS12}"
  NIFI_TRUSTSTORE_TYPE="${NIFI_TRUSTSTORE_TYPE:-PKCS12}"
  NIFI_CONTROLLER_SSL_NAME="${NIFI_CONTROLLER_SSL_NAME:-Controller SSL (Restricted)}"

  # List controller-level services once
  local list; list="$(ni::api::curl_nifi "${api}/flow/controller/controller-services")"

  # Prefer an existing *restricted* SSL CS, otherwise any standard SSL CS
  local cs_id; cs_id="$(
    jq -r --arg name "$NIFI_CONTROLLER_SSL_NAME" '
      # exact name match first
      (.controllerServices[]?.component | select(.name==$name)
         | select(.type=="org.apache.nifi.ssl.StandardRestrictedSSLContextService")
         | .id) // empty
    ' <<<"$list" | head -n1
  )"

  # Otherwise, reuse ANY existing StandardRestrictedSSLContextService (avoid duplicates)
  if [[ -z "$cs_id" ]]; then
    cs_id="$(
      jq -r '
        .controllerServices[]?.component
        | select(.type=="org.apache.nifi.ssl.StandardRestrictedSSLContextService")
        | .id // empty
      ' <<<"$list" | head -n1
    )"
  fi
  if [[ -z "$cs_id" ]]; then
    cs_id="$(
      jq -r '
        .controllerServices[]?.component
        | select(.type=="org.apache.nifi.ssl.StandardSSLContextService")
        | .id // empty
      ' <<<"$list" | head -n1
    )"
  fi

  # Create only if none exist yet
  if [[ -z "$cs_id" ]]; then
    local payload; payload="$(jq -n --arg name "$NIFI_CONTROLLER_SSL_NAME" '
      {
        revision:{version:0},
        component:{
          name:$name,
          type:"org.apache.nifi.ssl.StandardRestrictedSSLContextService",
          properties:{}
        }
      }')"
    local created; created="$(ni::api::curl_nifi "${api}/controller/controller-services" -X POST -d "$payload")" || return 1
    cs_id="$(jq -r '.id' <<<"$created")"
    [[ -n "$cs_id" ]] || { echo "ERR: failed to create controller SSL CS" >&2; return 1; }
  fi

  # Fetch current entity for revision
  local ent; ent="$(ni::api::curl_nifi "${api}/controller-services/${cs_id}")" || return 1
  local rev; rev="$(jq '.revision.version' <<<"$ent")"
  local state; state="$(jq -r '.component.state' <<<"$ent")"

  # If ENABLED, DISABLE so we can update properties safely
  if [[ "$state" == "ENABLED" ]]; then
    local dis_payload; dis_payload="$(jq -n --argjson v "$rev" '{revision:{version:$v}, state:"DISABLED"}')"
    ni::api::curl_nifi "${api}/controller-services/${cs_id}/run-status" -X PUT -d "$dis_payload" >/dev/null || return 1
    # refresh entity/rev after state change
    ent="$(ni::api::curl_nifi "${api}/controller-services/${cs_id}")" || return 1
    rev="$(jq '.revision.version' <<<"$ent")"
  fi

  # Build properties:
  local props; props="$(jq -n \
    --arg ks "$NIFI_KEYSTORE_FILE" \
    --arg ksp "$KEYSTORE_PASSWD" \
    --arg kp  "$KEYSTORE_PASSWD" \
    --arg kst "$NIFI_KEYSTORE_TYPE" \
    --arg ts "$NIFI_TRUSTSTORE_FILE" \
    --arg tsp "$TRUSTSTORE_PASSWD" \
    --arg tst "$NIFI_TRUSTSTORE_TYPE" '
    {
      "Keystore Filename":   $ks,
      "Keystore Password":   $ksp,
      "key-password":        $kp,
      "Keystore Type":       $kst,
      "Truststore Filename": $ts,
      "Truststore Password": $tsp,
      "Truststore Type":     $tst
    }')"

  # Update properties
  local upd; upd="$(jq --argjson props "$props" '.component.properties=$props' <<<"$ent")"
  ni::api::curl_nifi -X PUT "${api}/controller-services/${cs_id}" -d "$upd" >/dev/null || return 1

  # Enable (idempotent)
  ent="$(ni::api::curl_nifi "${api}/controller-services/${cs_id}")" || return 1
  rev="$(jq '.revision.version' <<<"$ent")"
  local en_payload; en_payload="$(jq -n --argjson v "$rev" '{revision:{version:$v}, state:"ENABLED"}')"
  ni::api::curl_nifi -X PUT "${api}/controller-services/${cs_id}/run-status" -d "$en_payload" >/dev/null || return 1

  # Optional: poll until validation completes or timeout
  local tries=30
  while (( tries-- > 0 )); do
    local st; st="$(ni::api::curl_nifi "${api}/controller-services/${cs_id}")"
    local state; state="$(jq -r '.component.state' <<<"$st")"
    local valid; valid="$(jq -r '.component.validationStatus' <<<"$st")"
    if [[ "$state" == "ENABLED" && "$valid" != "INVALID" ]]; then
      break
    fi
    sleep 1
  done

  echo "$cs_id"
}

# NiFi: ensure a Registry Client (NifiRegistryFlowRegistryClient) exists with correct URL and SSL Context Service
# Usage:
#   export NIFI_USER=admin
#   NIFI_NODES=(nifi-node-01 nifi-node-02)
#   REGISTRY_HOST=nifi-registry
#   ni::nifi::ensure_registry_client
ni::nifi::ensure_registry_client() {
  local registry_url; registry_url="$(printf '%s://%s:%s/' "https" "${REGISTRY_HOST}" "19443")"
  local api; api="$(ni::api::api_base_for "${NIFI_NODES[0]}")"

  # Ensure controller-scoped SSL CS exists/enabled; get its ID
  local ssl_cs_id; ssl_cs_id="$(ni::nifi::ensure_controller_ssl_service "$api")" || return 1

  List registry clients
  local list; list="$(ni::api::curl_nifi "${api}/controller/registry-clients")" || return 1

  # Prefer a client that already targets our URL; else reuse the first client; else create one
  local rc_id; rc_id="$(
    jq -r --arg url "$registry_url" '
      .registries[]?.component
      | select((.properties.url // "") == $url)
      | .id // empty
    ' <<<"$list" | head -n1
  )"

  if [[ -z "$rc_id" ]]; then
    rc_id="$(jq -r '.registries[]?.id // empty' <<<"$list" | head -n1)"
    if [[ -z "$rc_id" ]]; then
      local payload; payload="$(jq -n --arg url "$registry_url" '
        {
          revision:{version:0},
          component:{
            name:"NiFi Registry",
            type:"org.apache.nifi.registry.flow.NifiRegistryFlowRegistryClient",
            properties:{ url:$url }
          }
        }')"
      local created; created="$(ni::api::curl_nifi "${api}/controller/registry-clients" -X POST -d "$payload")" || return 1
      rc_id="$(jq -r '.id' <<<"$created")"
      [[ -n "$rc_id" ]] || { echo "ERR: failed to create Registry Client" >&2; return 1; }
      echo "Created Registry Client: $rc_id"
    else
      echo "Reusing existing Registry Client: $rc_id (will set URL and SSL link)."
    fi
  else
    echo "Found Registry Client already at target URL: $rc_id"
  fi

  # Fetch entity to get current revision
  local ent; ent="$(ni::api::curl_nifi "${api}/controller/registry-clients/${rc_id}")" || return 1

  # Patch URL and SSL link using the confirmed property key: ssl-context-service
  local patched; patched="$(
    jq --arg url "$registry_url" --arg ssl "$ssl_cs_id" '
      .component.properties.url = $url
      | .component.properties["ssl-context-service"] = $ssl
    ' <<<"$ent"
  )"

  # PUT update
  ni::api::curl_nifi -X PUT "${api}/controller/registry-clients/${rc_id}" -d "$patched" >/dev/null \
    || { echo "ERR: failed to update Registry Client" >&2; return 1; }

  echo "Registry Client updated: URL=${registry_url}; ssl-context-service=${ssl_cs_id}"
}
