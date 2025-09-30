#!/usr/bin/env bash
set -Eeuo pipefail

SSH_USER="ubuntu"
NIFI_USER="nifi"
MONGO_VER="${MONGO_VER:-}"   # optional override via env

usage() {
  cat <<EOF
usage: $0 [options] <hostname> [<hostname> ...]
Options:
  --ssh-user   defaults to $SSH_USER
  --nifi-user  defaults to $NIFI_USER
  -h, --help
EOF
}

# ---- parse args ----
while (( "$#" )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --ssh-user)  SSH_USER="$2"; shift 2 ;;
    --nifi-user) NIFI_USER="$2"; shift 2 ;;
    --) shift; break ;;
    -*) echo "WARN: unknown option: $1" >&2; shift ;;
    *) break ;;
  esac
done

if (( "$#" == 0 )); then
  echo "ERROR: provide at least one hostname"; usage; exit 1
fi
HOSTS=("$@")

for H in "${HOSTS[@]}"; do
  echo ">>> provisioning $H"
  ssh -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      -o ConnectTimeout=10 \
      -o ServerAliveInterval=15 \
      -o ServerAliveCountMax=4 \
      -v \
      "${SSH_USER}@${H}" \
      NIFI_USER="$NIFI_USER" MONGO_VER="$MONGO_VER" 'bash -s' <<'REMOTE'
set -Eeuo pipefail

# sudo helper (works as root or with passwordless sudo)
SUDO=""
if [[ "$EUID" -ne 0 ]]; then SUDO="sudo -n"; fi

# --- detect package manager & ensure maven ---
if command -v apt-get >/dev/null 2>&1; then
  INSTALL_MAVEN="$SUDO DEBIAN_FRONTEND=noninteractive apt-get update -y && $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq maven"
elif command -v dnf >/dev/null 2>&1; then
  INSTALL_MAVEN="$SUDO dnf install -y -q maven"
elif command -v yum >/dev/null 2>&1; then
  INSTALL_MAVEN="$SUDO yum install -y -q maven"
else
  echo "FATAL: unsupported Linux (need apt-get/dnf/yum)"; exit 1
fi

if ! command -v mvn >/dev/null 2>&1; then
  echo "Installing Maven..."
  eval "$INSTALL_MAVEN"
fi

# --- ensure Java present (install 17 if missing) ---
if ! command -v java >/dev/null 2>&1; then
  echo "Java not found, installing OpenJDK 17..."
  if command -v apt-get >/dev/null 2>&1; then
    eval "$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-17-jre-headless"
  elif command -v dnf >/dev/null 2>&1; then
    eval "$SUDO dnf install -y -q java-17-openjdk-headless"
  else
    eval "$SUDO yum install -y -q java-17-openjdk-headless"
  fi
fi

JAVA_MAJ=$(java -XshowSettings:properties -version 2>&1 | awk -F= '/java.specification.version/ {gsub(/ /,"",$2); print $2; exit}')
if [[ -z "$JAVA_MAJ" ]]; then
  JAVA_MAJ=$(java -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p')
fi

# choose driver version: 5.x for Java>=17, 4.11.x otherwise (or override via MONGO_VER)
if [[ -n "${MONGO_VER:-}" ]]; then
  VER="$MONGO_VER"
elif [[ "${JAVA_MAJ:-17}" -ge 17 ]]; then
  VER="5.1.2"
else
  VER="4.11.1"
fi
echo "Java ${JAVA_MAJ}, using MongoDB driver ${VER}"

DRIVER_DIR="/opt/drivers/mongodb"
$SUDO mkdir -p "$DRIVER_DIR"

# choose group for files: match NIFI_USER group if present, else root
if getent group "$NIFI_USER" >/dev/null 2>&1; then
  GRP="$NIFI_USER"
else
  GRP="$(id -gn "$NIFI_USER" 2>/dev/null || echo root)"
fi
$SUDO chown "$NIFI_USER":"$GRP" "$DRIVER_DIR"
$SUDO chmod 0755 "$DRIVER_DIR"

# --- fetch jars with maven ---
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

cat > "$WORKDIR/pom.xml" <<POM
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>local.nifi</groupId><artifactId>mongodb-driver-fetch</artifactId><version>1.0.0</version>
  <properties><mongodb.driver.version>${VER}</mongodb.driver.version></properties>
  <dependencies>
    <dependency>
      <groupId>org.mongodb</groupId>
      <artifactId>mongodb-driver-sync</artifactId>
      <version>\${mongodb.driver.version}</version>
    </dependency>
  </dependencies>
</project>
POM

mvn -q -f "$WORKDIR/pom.xml" -DoutputDirectory="$WORKDIR/jars" -DincludeScope=runtime dependency:copy-dependencies

$SUDO rm -f "$DRIVER_DIR"/*.jar
$SUDO cp -f "$WORKDIR/jars"/{mongodb-driver-sync-*.jar,mongodb-driver-core-*.jar,bson-*.jar} "$DRIVER_DIR"/

$SUDO chown "$NIFI_USER":"$GRP" "$DRIVER_DIR"/*.jar
$SUDO chmod 0644 "$DRIVER_DIR"/*.jar

echo "Installed jars in $DRIVER_DIR:"
ls -l "$DRIVER_DIR"
REMOTE
done
