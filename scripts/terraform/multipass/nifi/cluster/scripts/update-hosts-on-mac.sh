#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# Edit this list as you add nodes (missing ones are skipped gracefully)
NODES=("nifi-node-01" "nifi-node-02" "nifi-node-03" "nifi-registry")

fqdn() {
  case "$1" in
    nifi-node-01) echo "nifi-node-01.nifi.demo" ;;
    nifi-node-02) echo "nifi-node-02.nifi.demo" ;;
    nifi-node-03) echo "nifi-node-03.nifi.demo" ;;
    nifi-registry) echo "nifi-registry.nifi.demo" ;;
  esac
}

BLOCK=""
PRESENT=()

for NAME in "${NODES[@]}"; do
  if multipass info "$NAME" >/dev/null 2>&1; then
    # Grab first IPv4 from human output (no jq)
    IP="$(multipass info "$NAME" | awk -F': *' '/^IPv4/ {print $2; exit}' | awk '{print $1}')"
    if [[ -n "$IP" ]]; then
      FQDN="$(fqdn "$NAME")"
      BLOCK+=$'\n'"$IP $FQDN $NAME"
      PRESENT+=("$NAME")
    fi
  fi
done

BEGIN='# BEGIN multipass-nifi'
END='# END multipass-nifi'
TMP="$(mktemp)"
trap 'rm -f "$TMP" || true' EXIT

# Remove any previous block, then append fresh lines (if any)
awk -v b="$BEGIN" -v e="$END" '
  $0==b {inblk=1; next}
  $0==e {inblk=0; next}
  !inblk {print}
' /etc/hosts >"$TMP"

if [[ -n "${BLOCK// /}" ]]; then
  {
    echo "$BEGIN"
    printf "%s\n" "$BLOCK" | sed '/^$/d'
    echo "$END"
  } >>"$TMP"
fi

# --- Privileged replace of /etc/hosts without hanging ---
if sudo -n true 2>/dev/null; then
  sudo /bin/cp "$TMP" /etc/hosts
  sudo /bin/chmod 644 /etc/hosts
  sudo /usr/sbin/chown root:wheel /etc/hosts
else
  # GUI prompt on macOS; runs as root
  /usr/bin/osascript -e \
    'do shell script "/bin/cp '"$TMP"' /etc/hosts && /bin/chmod 644 /etc/hosts && /usr/sbin/chown root:wheel /etc/hosts" with administrator privileges'
fi

echo "Updated /etc/hosts for: ${PRESENT[*]:-none}"
