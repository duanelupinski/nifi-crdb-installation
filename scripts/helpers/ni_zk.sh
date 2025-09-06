#!/usr/bin/env bash
# ZooKeeper install/config/systemd

ni::zk::install() {
  local remote="$1" ver="${2:-3.9.4}" base="/opt/zookeeper" curl_flags="${3:-}"
  local tgz="apache-zookeeper-${ver}-bin.tar.gz"
  local dir="apache-zookeeper-${ver}-bin"
  local url1="https://dlcdn.apache.org/zookeeper/zookeeper-${ver}/${tgz}"
  local url2="https://archive.apache.org/dist/zookeeper/zookeeper-${ver}/${tgz}"
  ni::ssh_sudo "$remote" $'
set -e
id -u zookeeper >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin zookeeper
command -v curl >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y curl tar
mkdir -p /opt
cd /opt
if [ ! -d '"$dir"' ]; then
  echo downloading '"$tgz"'
  (curl '"$curl_flags"' -fL -o '"$tgz"' '"$url1"' || curl '"$curl_flags"' -fL -o '"$tgz"' '"$url2"')
  tar -xzf '"$tgz"'
  rm -f '"$tgz"'
fi
ln -sfn '"$dir"' zookeeper
mkdir -p /var/lib/zookeeper/data /var/lib/zookeeper/datalog
chown -R zookeeper:zookeeper /opt/'"$dir"' /opt/zookeeper /var/lib/zookeeper
'
}

# Write zoo.cfg with server list; set myid per node
ni::zk::configure() {
  local remote="$1" myid="$2"; shift 2
  # remaining args are peer hostnames (including this host)
  ni::ssh_sudo_stdin "$remote" "$myid" "$@" <<'RSH'
set -o errexit -o nounset -o pipefail
MYID="$1"; shift
PEERS=("$@")
CONFIG=/opt/zookeeper/conf/zoo.cfg
cat > "$CONFIG" <<CFG
tickTime=2000
initLimit=10
syncLimit=5
dataDir=/var/lib/zookeeper/data
dataLogDir=/var/lib/zookeeper/datalog
clientPort=2181
autopurge.snapRetainCount=5
autopurge.purgeInterval=24
4lw.commands.whitelist=stat,mntr,srvr,ruok
CFG
i=1
for h in "${PEERS[@]}"; do
  echo "server.${i}=${h}:2888:3888" >> "$CONFIG"
  i=$((i+1))
done
echo "$MYID" > /var/lib/zookeeper/data/myid
chown -R zookeeper:zookeeper /var/lib/zookeeper /opt/zookeeper
RSH
}

ni::zk::systemd() {
  local remote="$1"
  ni::ssh_sudo "$remote" $'cat > /etc/systemd/system/zookeeper.service <<UNIT
[Unit]
Description=Apache ZooKeeper
Requires=network.target remote-fs.target
After=network.target remote-fs.target
Wants=network-online.target

[Service]
Type=simple
User=zookeeper
Group=zookeeper
ExecStart=/opt/zookeeper/bin/zkServer.sh start-foreground /opt/zookeeper/conf/zoo.cfg
ExecStop=/opt/zookeeper/bin/zkServer.sh stop
Restart=on-abnormal
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload'
}

ni::zk::enable_start() {
  local remote="$1"
  ni::ssh_sudo "$remote" "systemctl enable --now zookeeper"
}
