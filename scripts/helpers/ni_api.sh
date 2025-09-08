#!/usr/bin/env bash
# Helpers for accessing NiFi API endpoints

NIFI_SCHEME="${NIFI_SCHEME:-https}"
NIFI_PORT="${NIFI_PORT:-9443}"
REG_PORT="${REG_PORT:-19443}"

ni::api::curl_nifi() {
  local CERTS_DIR="./.private/nifi-certs"
  local CERT="${CERTS_DIR}/_clients/${NIFI_USER}/${NIFI_USER}.crt"
  local KEY="${CERTS_DIR}/_clients/${NIFI_USER}/${NIFI_USER}.key"
  local CA="${CERTS_DIR}/_ca/ca.crt"
  if [[ "${NI_VERBOSE:-0}" == "1" ]]; then
    echo ">> curl $*" 1>&2
    curl --path-as-is -v -sS --fail \
      -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'X-Requested-By: nifi-cli' \
      --cert "$CERT" --key "$KEY" --cacert "$CA" "$@"
  else
    curl --path-as-is -sS --fail \
      -H 'Accept: application/json' -H 'Content-Type: application/json' -H 'X-Requested-By: nifi-cli' \
      --cert "$CERT" --key "$KEY" --cacert "$CA" "$@"
  fi
}

ni::api::api_base_for() {  # build https://host:9443/nifi-api
  local host="$1"
  printf '%s://%s:%s/nifi-api' "$NIFI_SCHEME" "$host" "$NIFI_PORT"
}

reg::api::api_base_for() {  # build https://host:19443/nifi-registry-api
  local host="$1"
  printf '%s://%s:%s/nifi-registry-api' "$NIFI_SCHEME" "$host" "$REG_PORT"
}

# URL-encode helper for resource paths like /flow, /data/process-groups/{id}
ni::api::urlenc() { printf '%s' "$1" | jq -sRr @uri; }
