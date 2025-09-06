#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

USER=ubuntu
HOST=""
TIMEOUT=600

usage(){ echo "usage: $0 -c <host> [-u <user>] [-t <seconds>]"; }

while getopts "c:u:t:h" opt; do
  case "$opt" in
    c) HOST="$OPTARG" ;;
    u) USER="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[ -n "$HOST" ] || { usage; exit 2; }

end=$((SECONDS + TIMEOUT))
while (( SECONDS < end )); do
  if ssh -o BatchMode=yes -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR \
        "${USER}@${HOST}" true 2>/dev/null; then
    exit 0
  fi
  sleep 5
done

echo "ERROR: SSH not ready for ${USER}@${HOST} after ${TIMEOUT}s" >&2
exit 1
