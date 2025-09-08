#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# Read JSON from stdin: {"name":"vm-name"}
read -r input
name="$(printf '%s' "$input" | /opt/homebrew/bin/jq -r '.name')"

# Query Multipass and emit {"ip":"<addr>"} (blank if none yet)
ip="$(multipass info "$name" --format json | /opt/homebrew/bin/jq -r --arg n "$name" '.info[$n].ipv4[0] // ""')"
/opt/homebrew/bin/jq -n --arg ip "$ip" '{"ip":$ip}'
