#!/usr/bin/env bash
# helpers/ni_registry.sh
# Install NiFi Registry under /opt/nifi-registry-<ver>, set NIFI_REGISTRY_HOME,
# and symlink /usr/bin/nifi-registry -> <dest>/bin/nifi-registry.sh.
# Idempotent, Debian/Ubuntu only.

# --- Install NiFi Registry and set NIFI_REGISTRY_HOME ---
ni::registry::install() {
  local remote="$1" ver="$2" user="$3" curl_flags="${4:-}"
  ni::ssh_sudo "$remote" bash -s -- "$ver" "$user" "$curl_flags" <<'REMOTE'
set -o errexit -o nounset -o pipefail
ver="$1"; user="$2"; curl_flags="$3"

dir="nifi-registry-${ver}"
zip="nifi-registry-${ver}-bin.zip"
url1="https://dlcdn.apache.org/nifi/${ver}/${zip}"
url2="https://archive.apache.org/dist/nifi/${ver}/${zip}"

# ensure deps
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip

mkdir -p /opt
cd /opt

if [ ! -d "$dir" ]; then
  echo "downloading NiFi Registry $ver"
  (curl $curl_flags -fL -o "$zip" "$url1" || curl $curl_flags -fL -o "$zip" "$url2")
  unzip -q -o "$zip"
  rm -f "$zip"
fi

sudo chown -R $user:$user "$dir"
ln -sfn "$dir" nifi-registry
chown -R $user:$user /opt/nifi-registry
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
set_kv "NIFI_REGISTRY_HOME" "/opt/nifi-registry" /etc/environment
printf 'export NIFI_REGISTRY_HOME=%s\n' "/opt/nifi-registry" > /etc/profile.d/nifi_registry_home.sh
chmod 0644 /etc/profile.d/nifi_registry_home.sh
REMOTE
}

# Configure NiFi Registry web listeners (secure or http), hostnames only.
# Usage: ni::registry::configure_web <ssh-remote> <secure:true|false> <registry_hostname> [nifi_user]
ni::registry::configure() {
  local remote="$1" secure="$2" reg_host="$3" user="${4:-nifi}"
  ni::ssh_sudo_stdin "$remote" env KS_PWD="${KEYSTORE_PASSWD:-}" \
    TS_PWD="${TRUSTSTORE_PASSWD:-}" bash -s -- "$secure" "$reg_host" "$user" <<'RSH'
set -o errexit -o nounset -o pipefail
SECURE="$1"; HOST="$2"; NIFI_USER="$3";
NIFI_HOME="${NIFI_HOME:-/opt/nifi}"
NIFI_REGISTRY_HOME="${NIFI_REGISTRY_HOME:-/opt/nifi-registry}"
CONF="$NIFI_REGISTRY_HOME/conf/nifi-registry.properties"
HOST="${HOST%%.*}"
CERTS="$NIFI_HOME/certs"

[ -f "$CONF" ] || { echo "ERROR: $CONF not found"; exit 2; }

# idempotent setter
setprop() {
  local k="$1" v="${2-}"
  if grep -qE "^${k}=" "$CONF"; then
    sed -i -e "s|^${k}=.*|${k}=${v}|" "$CONF"
  else
    printf '%s=%s\n' "$k" "$v" >> "$CONF"
  fi
}

# HTTP(S) ports — exactly one
if [ "$SECURE" = "true" ]; then
  setprop nifi.registry.web.http.host ""
  setprop nifi.registry.web.http.port ""
  setprop nifi.registry.web.https.host "$HOST"
  setprop nifi.registry.web.https.port 19443
else
  setprop nifi.registry.web.http.host "$HOST"
  setprop nifi.registry.web.http.port 18080
  setprop nifi.registry.web.https.host ""
  setprop nifi.registry.web.https.port ""
fi

# security
if [ "$SECURE" = "true" ] && [ -f "${CERTS}/keystore.p12" ] && [ -f "${CERTS}/truststore.p12" ]; then
  setprop nifi.registry.security.keystore "${CERTS}/keystore.p12"
  setprop nifi.registry.security.keystoreType "PKCS12"
  setprop nifi.registry.security.keystorePasswd "${KS_PWD}"
  setprop nifi.registry.security.keyPasswd "${KS_PWD}"
  setprop nifi.registry.security.truststore "${CERTS}/truststore.p12"
  setprop nifi.registry.security.truststoreType "PKCS12"
  setprop nifi.registry.security.truststorePasswd "${TS_PWD}"
  setprop nifi.registry.security.identity.mapping.pattern.1 "^OU=([^,]+), CN=([^,]+)$"
  setprop nifi.registry.security.identity.mapping.value.1 "CN=\$2, OU=\$1"
  setprop nifi.registry.security.identity.mapping.transform.1 "NONE"
fi

# Make sure the nifi user owns dirs it needs to write to (not the whole distro)
chown -R "$NIFI_USER:$NIFI_USER" "$NIFI_REGISTRY_HOME" 2>/dev/null || true
RSH
}

# NiFi: replace Node Identity list with the provided hosts (idempotent)
# Usage: ni::registry::authorizers_add_nodes <ssh-remote> <username> <host1> [host2...]
ni::registry::authorizers_add_nodes() {
  local remote="$1"; shift
  local username="$1"; shift
  local nodes=("$@")

  # Run everything on the remote host with sudo
  ni::ssh_sudo "$remote" bash -s -- "${username}" "${nodes[@]}" <<'BASH'
set -o errexit -o nounset -o pipefail

username="$1"; shift  # remaining "$@" are node hosts

NIFI_REGISTRY_HOME="${NIFI_REGISTRY_HOME:-/opt/nifi-registry}"
AUTH="$NIFI_REGISTRY_HOME/conf/authorizers.xml"
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

# Recreate NiFi Identity <nodeid> with node-id = (index+1)
i=0
for host in "$@"; do
  i=$((i+1))

  xmlcmd+=" -d /authorizers/accessPolicyProvider/property[@name='\"NiFi Identity ${i}\"']"
  xmlcmd+=" -s /authorizers/accessPolicyProvider -t elem -n propertyTMP -v \"CN=${host}, OU=NIFI\""
  xmlcmd+=" -i //propertyTMP -t attr -n name -v \"NiFi Identity ${i}\""
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

# Registry variant
# Tweak Registry logback.xml safely (dir/size/history); auto-repair if invalid
ni::registry::configure_logging() {
  local remote="$1" username="$2" maxsize="${3:-100MB}" maxhist="${4:-30}"
  ni::ssh_sudo "$remote" bash -s -- "$username" "$maxsize" "$maxhist" <<'BASH'
set -o errexit -o nounset -o pipefail
username="$1"; maxsize="$2"; maxhist="$3"
REG_HOME="${NIFI_REGISTRY_HOME:-/opt/nifi-registry}"
LB="$REG_HOME/conf/logback.xml"

[ -f "$LB" ] || { echo "WARN: $LB not found; skipping"; exit 0; }

# Ensure xmlstarlet is available
if ! command -v xmlstarlet >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -y >/dev/null 2>&1 || true
  sudo apt-get install -y xmlstarlet
fi

xmlstarlet ed -P -L -u /configuration/appender[@name='"APP_FILE"']/rollingPolicy/maxHistory -v ${maxhist} "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"APP_FILE"']/rollingPolicy/totalSizeCap -v "${maxsize}" "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"BOOTSTRAP_FILE"']/rollingPolicy/maxHistory -v ${maxhist} "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"BOOTSTRAP_FILE"']/rollingPolicy/totalSizeCap -v "${maxsize}" "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"EVENTS_FILE"']/rollingPolicy/maxHistory -v ${maxhist} "${LB}"
xmlstarlet ed -P -L -u /configuration/appender[@name='"EVENTS_FILE"']/rollingPolicy/totalSizeCap -v "${maxsize}" "${LB}"

chown $username:$username "$LB"
BASH
}

# Ensure NiFi Registry configs reference ${NIFI_REGISTRY_HOME} instead of "./"
# Usage: ni::registry::ensure_env_vars <ssh-remote>
ni::registry::ensure_env_vars() {
  local remote="$1"

  ni::ssh "$remote" bash -s <<'BASH'
set -o errexit -o nounset -o pipefail
NIFI_REGISTRY_HOME="${NIFI_REGISTRY_HOME:-/opt/nifi-registry}"
H_ESC="$(printf '%s' "$NIFI_REGISTRY_HOME" | sed 's/[\/&]/\\&/g')"

prop_files=(
  "$NIFI_REGISTRY_HOME/conf/nifi-registry.properties"
  "$NIFI_REGISTRY_HOME/conf/bootstrap.conf"
)
xml_files=(
  "$NIFI_REGISTRY_HOME/conf/authorizers.xml"
  "$NIFI_REGISTRY_HOME/conf/providers.xml"
)

for f in "${prop_files[@]}"; do
  [ -f "$f" ] || continue
  sudo sed -i "s|=\./|=${H_ESC}/|g" "$f"
done
for f in "${xml_files[@]}"; do
  [ -f "$f" ] || continue
  sudo sed -i "s|\./|${H_ESC}/|g" "$f"
done

echo "NiFi Registry env/paths normalized under \$NIFI_REGISTRY_HOME=$NIFI_REGISTRY_HOME"
BASH
}

# Registry service
ni::registry::systemd() {
  local remote="$1"
  ni::ssh_sudo "$remote" bash -s <<'BASH'
set -o errexit -o nounset -o pipefail
REG="${NIFI_REGISTRY_HOME:-/opt/nifi-registry}"

JAVA_BIN="$(readlink -f "$(command -v java)")"
JAVA_HOME="${JAVA_BIN%/bin/java}"

cat >/etc/systemd/system/nifi-registry.service <<UNIT
[Unit]
Description=Apache NiFi Registry
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=nifi
Group=nifi
EnvironmentFile=-/etc/environment
Environment=JAVA_HOME=/usr/bin/java
Environment=NIFI_REGISTRY_HOME=/opt/nifi-registry
WorkingDirectory=/opt/nifi-registry
ExecStart=/opt/nifi-registry/bin/nifi-registry.sh run
ExecStop=/opt/nifi-registry/bin/nifi-registry.sh stop
Restart=on-failure
RestartSec=10s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
BASH
}

ni::registry::enable_start() {
  local remote="$1"
  ni::wait_ssh_or_die "$remote" || ni::die "ssh not reachable for $remote"
  ni::ssh "$remote" "sudo -n bash -s" <<'BASH'
set -o errexit -o nounset -o pipefail
systemctl daemon-reload
systemctl enable nifi-registry
systemctl restart nifi-registry || { echo "---- nifi-registry journal (last 200) ----"; journalctl -u nifi-registry -n 200 --no-pager || true; exit 1; }
systemctl --no-pager --full status nifi-registry || true
BASH
}
