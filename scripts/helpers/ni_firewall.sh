#!/usr/bin/env bash
# UFW defaults + peer rules (hostname->IP resolve done on the node).

ni::ufw_defaults(){
  local remote="$1"
  ni::ssh_sudo "$remote" $'command -v ufw >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp'
}

ni::resolve_and_allow_peers(){
  local remote="$1" secure="$2"; shift 2
  ni::ssh_sudo_stdin "$remote" "$secure" "$@" <<'RSH'
set -o errexit -o nounset -o pipefail
SECURE="$1"; shift
resolve_ip(){
  local n="$1" ip=""
  ip="$(getent ahostsv4 "$n" | awk 'NR==1{print $1}')" || true
  [ -n "$ip" ] || ip="$(getent ahosts "$n" | awk 'NR==1{print $1}')" || true
  printf '%s' "$ip"
}
for peer in "$@"; do
  ip="$(resolve_ip "$peer")"; [ -z "$ip" ] && { echo "WARN: cannot resolve $peer"; continue; }
  ufw allow from "$ip" to any port 9092
  ufw allow from "$ip" to any port 2181
  ufw allow from "$ip" to any port 2888
  ufw allow from "$ip" to any port 3888
  if [ "$SECURE" = "true" ]; then
    ufw allow from "$ip" to any port 10443   # NiFi S2S TLS
    ufw allow from "$ip" to any port 11443   # NiFi cluster TLS
  else
    ufw allow from "$ip" to any port 9998    # NiFi S2S HTTP
    ufw allow from "$ip" to any port 9997    # NiFi cluster HTTP
  fi
  ufw allow from "$ip" to any port 6342      # load-balance
  ufw allow from "$ip" to any port 4557      # legacy comms
done
ufw --force enable
ufw reload
ufw status verbose || true
RSH
}
