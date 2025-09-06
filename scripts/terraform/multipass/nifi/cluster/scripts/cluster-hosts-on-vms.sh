#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# Usage: cluster-hosts-on-vms.sh apply
ACTION="${1:-apply}"

NODES=(nifi-node-01 nifi-node-02 nifi-node-03 nifi-registry)

fqdn() {
  case "$1" in
    nifi-node-01) echo "nifi-node-01.nifi.demo" ;;
    nifi-node-02) echo "nifi-node-02.nifi.demo" ;;
    nifi-node-03) echo "nifi-node-03.nifi.demo" ;;
    nifi-registry) echo "nifi-registry.nifi.demo" ;;
  esac
}

# 1) Discover present VMs + build lines
present=()
lines=""
for name in "${NODES[@]}"; do
  if multipass info "$name" >/dev/null 2>&1; then
    ip="$(multipass info "$name" | awk -F': *' '/^IPv4/ {print $2; exit}' | awk '{print $1}')"
    [ -n "${ip:-}" ] || continue
    present+=("$name")
    lines+="${ip} $(fqdn "$name") ${name}\n"
  fi
done

if [ "${#present[@]}" -eq 0 ]; then
  echo "No VMs present to update."
  exit 0
fi

# 2) Write lines to a temp file on the host
LINES_FILE="$(mktemp)"
# shellcheck disable=SC2059
printf "%b" "$lines" | sed '/^$/d' > "$LINES_FILE"

# Patterns for pruning old entries inside guests
SHORTS='nifi-node-01|nifi-node-02|nifi-node-03|nifi-registry'
FQDNS='nifi-node-01\.nifi\.demo|nifi-node-02\.nifi\.demo|nifi-node-03\.nifi\.demo|nifi-registry\.nifi\.demo'

# 3) Push and apply on each VM
for target in "${present[@]}"; do
  echo "Updating /etc/hosts inside ${target}"
  multipass transfer "$LINES_FILE" "${target}:/tmp/cluster-hosts.txt"

  multipass exec "$target" -- sudo /bin/bash -lc "
    set -o errexit -o nounset -o pipefail
    TMP=\$(mktemp)

    # Start from existing /etc/hosts with old cluster lines removed
    if [ -f /etc/hosts ]; then
      grep -Ev \"[[:space:]]($SHORTS|$FQDNS)(\\s|\$)\" /etc/hosts > \"\$TMP\" || true
    else
      : > \"\$TMP\"
    fi

    # Append fresh lines
    cat /tmp/cluster-hosts.txt >> \"\$TMP\"

    # Replace atomically
    mv \"\$TMP\" /etc/hosts
    chmod 644 /etc/hosts
  "

  echo "Updated /etc/hosts inside ${target}"
done

rm -f "$LINES_FILE"
echo "Done. Updated: ${present[*]}"
