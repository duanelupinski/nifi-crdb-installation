#!/usr/bin/env bash
# Install PostgreSQL JDBC driver on each node

ni::pg::install_jdbc() {
  local remote="$1" ver="${2:-42.7.7}" dest="${3:-/opt/drivers/postgres}" user="$4" curl_flags="${5:-}"
  local jar="postgresql-${ver}.jar"
  local url="https://jdbc.postgresql.org/download/${jar}"

  ni::ssh_sudo_stdin "$remote" "$dest" "$jar" "$url" "$user" "$curl_flags" <<'BASH'
set -o errexit -o nounset -o pipefail
DEST="$1"; JAR="$2"; URL="$3"; user="$4"; CURL_FLAGS="$5"

mkdir -p "$DEST"
chown root:root "$DEST"
chmod 0755 "$DEST"

command -v curl >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y curl

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
if [ ! -f "$DEST/$JAR" ]; then
  echo "downloading $JAR"
  # shellcheck disable=SC2086
  curl $CURL_FLAGS -fL -o "$TMP" "$URL"
  install -o root -g root -m 0644 "$TMP" "$DEST/$JAR"
fi
sudo chown -R $user:$user "$DEST/.."
ln -sfn "$JAR" "$DEST/postgresql-jdbc.jar"
BASH
}
