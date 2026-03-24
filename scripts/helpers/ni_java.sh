#!/usr/bin/env bash
# Ensure OpenJDK on Debian/Ubuntu

# Install OpenJDK (default 21) and persist JAVA_HOME in /etc/environment.
ni::java::ensure() {
  local remote="$1" ver="${2:-21}"
  ni::ssh_sudo "$remote" bash -s -- "$ver" <<'BASH'
set -o errexit -o nounset -o pipefail
ver="$1"

command -v apt-get >/dev/null 2>&1 || { echo "Debian/Ubuntu required"; exit 2; }
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y "openjdk-${ver}-jdk"

# Force alternatives to use the requested version
update-alternatives --set java "$(update-alternatives --list java | grep "java-${ver}-openjdk" | head -n1)"

JAVA_BIN="$(readlink -f "$(command -v java)")"
JAVA_HOME="${JAVA_BIN%/bin/java}"

# Persist system-wide
if grep -q '^JAVA_HOME=' /etc/environment; then
  sed -i "s|^JAVA_HOME=.*|JAVA_HOME=${JAVA_HOME}|" /etc/environment
else
  printf '\nJAVA_HOME=%s\n' "$JAVA_HOME" | tee -a /etc/environment >/dev/null
fi

# Also set in NiFi env scripts if already present (idempotent)
[ -f /opt/nifi/bin/nifi-env.sh ] && \
  sed -i "s|^#\?JAVA_HOME=.*|JAVA_HOME=${JAVA_HOME}|" /opt/nifi/bin/nifi-env.sh || true
[ -f /opt/nifi-registry/bin/nifi-registry-env.sh ] && \
  sed -i "s|^#\?JAVA_HOME=.*|JAVA_HOME=${JAVA_HOME}|" /opt/nifi-registry/bin/nifi-registry-env.sh || true

java -version || true
BASH
}
