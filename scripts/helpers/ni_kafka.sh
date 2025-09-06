#!/usr/bin/env bash
# Kafka install/config/systemd (ZK mode)

ni::kafka::install() {
  local remote="$1" ver="${2:-3.9.1}" scala="${3:-2.13}" base="/opt/kafka" curl_flags="${4:-}"
  local tgz="kafka_${scala}-${ver}.tgz"
  local dir="kafka-${ver}"
  local url="https://downloads.apache.org/kafka/${ver}/${tgz}"
  local url1="https://dlcdn.apache.org/kafka/${ver}/${tgz}"
  local url2="https://archive.apache.org/dist/kafka/${ver}/${tgz}"
  ni::ssh_sudo "$remote" $'
set -e
id -u kafka >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin kafka
command -v curl >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y curl tar
mkdir -p /opt
cd /opt
if [ ! -d '"$dir"' ]; then
  echo downloading '"$tgz"'
  (curl '"$curl_flags"' -fL -o '"$tgz"' '"$url1"' || curl '"$curl_flags"' -fL -o '"$tgz"' '"$url2"')
  tar -xzf '"$tgz"'
  rm -f '"$tgz"'
  mv kafka_'"$scala"'-'"$ver"' '"$dir"'
fi
ln -sfn '"$dir"' kafka
# Ensure scripts are executable for the service user
chmod -R a+rx /opt/'"$dir"'/bin
mkdir -p /var/lib/kafka/logs
chown -R kafka:kafka /opt/'"$dir"' /opt/kafka /var/lib/kafka
'
}

ni::kafka::configure() {
  local remote="$1" broker_id="$2" zk_connect="$3" cluster_size="$4"
  # replication factors are min(3, cluster size)
  ni::ssh_sudo_stdin "$remote" "$broker_id" "$zk_connect" "$cluster_size" <<'RSH'
set -o errexit -o nounset -o pipefail
BID="$1"; ZK="$2"; SIZE="$3"
RF=3; [ "$SIZE" -lt 3 ] && RF="$SIZE"
HOST_FQDN="$(hostname -f || hostname)"
CFG=/opt/kafka/config/server.properties
cat > "$CFG" <<CFG
broker.id=${BID}
listeners=PLAINTEXT://0.0.0.0:9092
advertised.listeners=PLAINTEXT://${HOST_FQDN}:9092
listener.security.protocol.map=PLAINTEXT:PLAINTEXT
inter.broker.listener.name=PLAINTEXT
log.dirs=/var/lib/kafka/logs
log.retention.hours=168
log.retention.check.interval.ms=300000
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
num.partitions=3
num.recovery.threads.per.data.dir=3
default.replication.factor=${RF}
offsets.topic.replication.factor=${RF}
transaction.state.log.replication.factor=${RF}
transaction.state.log.min.isr=1
min.insync.replicas=1
delete.topic.enable=true
zookeeper.connect=${ZK}
zookeeper.connection.timeout.ms=18000
group.initial.rebalance.delay.ms=0
auto.create.topics.enable=true
CFG
chown kafka:kafka "$CFG" /var/lib/kafka -R
RSH
}

ni::kafka::systemd() {
  local remote="$1"
  ni::ssh_sudo "$remote" $'cat > /etc/systemd/system/kafka.service <<\'UNIT\'
[Unit]
Description=Apache Kafka Broker
Requires=network.target zookeeper.service
After=network.target zookeeper.service

[Service]
Type=simple
User=kafka
Group=kafka
WorkingDirectory=/opt/kafka
Environment=KAFKA_HEAP_OPTS=-Xms1g -Xmx1g
# Verify the script exists & is executable before start
ExecStartPre=/usr/bin/test -x /opt/kafka/bin/kafka-server-start.sh
# Use env to select bash explicitly
ExecStart=/usr/bin/env bash /opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
Restart=on-abnormal
RestartSec=2
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload'
}

ni::kafka::enable_start() {
  local remote="$1"
  ni::ssh_sudo "$remote" "systemctl enable --now kafka"
}
