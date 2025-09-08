#!/usr/bin/env bash
# Cluster TLS using NiFi Toolkit (single CA, per-node bundles)
# Strategy: run toolkit LOCALLY (controller host), then scp node bundles.

ni::certs::ensure_cluster_tls() {
  local installer="$1"; shift
  local username="$1"; shift

  local nodes=("$@")
  local CERTS_DIR="./.private/nifi-certs"

  echo "generating certificates for the nifi cluster if they don't exist in ${CERTS_DIR}..."

  # --- prereqs on local host ---
  command -v openssl >/dev/null 2>&1 || { echo "ERROR: openssl not found on local host."; return 2; }
  mkdir -p "${CERTS_DIR}/_ca"

  # --- cluster CA (create once if absent) ---
  local CA_KEY="${CERTS_DIR}/_ca/ca.key"
  local CA_CRT="${CERTS_DIR}/_ca/ca.crt"
  if [ ! -f "${CA_KEY}" ] || [ ! -f "${CA_CRT}" ]; then
    echo "+ generating cluster CA at ${CERTS_DIR}/_ca"
    openssl genrsa -out "${CA_KEY}" 4096
    openssl req -x509 -new -key "$CA_KEY" -sha256 -days 3650 \
      -subj "/CN=nifi-ca/OU=NIFI" -out "$CA_CRT"
  fi

  # --- global SAN block ---
  declare -A seen=()
  declare -a SAN_ENTRIES=()
  i=1
  for n in "${nodes[@]}"; do
    if [[ -z "${seen[$n]:-}" ]]; then SAN_ENTRIES+=("DNS.$i = $n"); seen[$n]=1; ((i++)); fi
    short="${n%%.*}"
    if [[ "$short" != "$n" && -z "${seen[$short]:-}" ]]; then SAN_ENTRIES+=("DNS.$i = $short"); seen[$short]=1; ((i++)); fi
  done
  SAN_BLOCK="$(printf '%s\n' "${SAN_ENTRIES[@]}")"

  # --- per-node bundles ---
  for host in "${nodes[@]}"; do
    local OUT="${CERTS_DIR}/${host}"
    mkdir -p "${OUT}"

    # Idempotency: skip if both keystore & truststore already present
    if [ -f "${OUT}/keystore.p12" ] && [ -f "${OUT}/truststore.p12" ]; then
      echo "INFO: cert bundle for ${host} already exists; skipping."
      continue
    fi

    echo "+ generating key/cert for ${host}"
    openssl genrsa -out "${OUT}/${host}.key" 4096

    # One config file used for CSR and signing (keeps SANs consistent)
    cat > "${OUT}/${host}.cnf" <<EOF
[ req ]
distinguished_name = dn
req_extensions     = v3_req
prompt             = no
[ dn ]
CN = ${host}
OU = NIFI
[ v3_req ]
keyUsage = digitalSignature, keyEncipherment, keyAgreement
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names
[ alt_names ]
${SAN_BLOCK}
EOF

    openssl req -new -key "${OUT}/${host}.key" -out "${OUT}/${host}.csr" -config "${OUT}/${host}.cnf"

    # Sign with CA; pull extensions from the same cnf
    openssl x509 -req -in "${OUT}/${host}.csr" \
      -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
      -out "${OUT}/${host}.crt" -days 1825 -sha256 \
      -extfile "${OUT}/${host}.cnf" -extensions v3_req

    # PKCS12 keystore: private key + leaf cert (+ CA cert as chain)
    openssl pkcs12 -export \
      -name "${host}" \
      -inkey "${OUT}/${host}.key" \
      -in "${OUT}/${host}.crt" \
      -certfile "${CA_CRT}" \
      -out "${OUT}/keystore.p12" \
      -passout "pass:${KEYSTORE_PASSWD}"

    # PKCS12 truststore containing only CA certificate
    if command -v keytool >/dev/null 2>&1; then
      rm -f "${OUT}/truststore.p12"
      keytool -importcert -noprompt \
        -alias nifi-ca \
        -file "$CA_CRT" \
        -keystore "${OUT}/truststore.p12" \
        -storetype PKCS12 \
        -storepass "${TRUSTSTORE_PASSWD}"
    else
      echo "ERROR: keytool (JDK) not found; required to create truststore.p12 cleanly." >&2
      return 2
    fi
  done

  # --- admin/client certificate (for ${username}) ---
  CLIENT_DIR="${CERTS_DIR}/_clients/${username}"
  mkdir -p "$CLIENT_DIR"
  if [[ ! -f "${CLIENT_DIR}/${username}.p12" ]]; then
    echo "+ generating admin client cert for ${username}"
    openssl genrsa -out "${CLIENT_DIR}/${username}.key" 4096
    cat > "${CLIENT_DIR}/${username}.cnf" <<EOF
[ req ]
distinguished_name = dn
prompt             = no
[ dn ]
CN = ${username}
OU = NIFI
EOF
    openssl req -new -key "${CLIENT_DIR}/${username}.key" \
      -out "${CLIENT_DIR}/${username}.csr" -config "${CLIENT_DIR}/${username}.cnf"
    openssl x509 -req -in "${CLIENT_DIR}/${username}.csr" \
      -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
      -out "${CLIENT_DIR}/${username}.crt" -days 825 -sha256
    openssl pkcs12 -export \
      -name "${username}" \
      -inkey "${CLIENT_DIR}/${username}.key" \
      -in "${CLIENT_DIR}/${username}.crt" \
      -certfile "$CA_CRT" \
      -out "${CLIENT_DIR}/${username}.p12" \
      -passout "pass:${KEYSTORE_PASSWD}"
  fi

  # --- push to nodes ---
  for host in "${nodes[@]}"; do
    echo "+ ${host}: installing certs"
    ssh -o StrictHostKeyChecking=no "${installer}@${host}" 'sudo mkdir -p /opt/nifi/certs && mkdir -p /tmp/nifi-certs'
    scp -o StrictHostKeyChecking=no -r "${CERTS_DIR}/${host}/." "${installer}@${host}:/tmp/nifi-certs"
    ssh -o StrictHostKeyChecking=no "${installer}@${host}" \
      'sudo bash -lc "mv /tmp/nifi-certs/* /opt/nifi/certs/; rm -rf /tmp/nifi-certs; chown -R nifi:nifi /opt/nifi/certs"'
  done
}
