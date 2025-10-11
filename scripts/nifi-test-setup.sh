#!/usr/bin/env bash

set -o pipefail
NI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRED_LIBS=(
  helpers/ni_api.sh
  helpers/ni_auth.sh
)
for f in "${REQUIRED_LIBS[@]}"; do
  if [ ! -f "${NI_DIR}/${f}" ]; then
    echo "ERROR: missing required library: ${f}" >&2
    exit 2
  fi
  # shellcheck source=/dev/null
  . "${NI_DIR}/${f}"
done


export NIFI_USER=nifi
export NIFI_NODES=( "nifi-node-01" "nifi-node-02" "nifi-node-03" )
ni::auth::grant_nodes
