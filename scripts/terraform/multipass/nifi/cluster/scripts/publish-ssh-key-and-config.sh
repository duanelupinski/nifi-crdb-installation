#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

# usage: ./seed-ssh-and-config.sh </path/to/id_ed25519.pub|id_rsa.pub>
PUBKEY_PATH="${1:?usage: $0 </path/to/id_ed25519.pub|id_rsa.pub>}"

# Expand ~ if present
eval PUBKEY_PATH="$PUBKEY_PATH"
PUBKEY="$(cat "$PUBKEY_PATH")"

# ---- VMs we manage via multipass ----
NODES=("nifi-node-01" "nifi-node-02" "nifi-node-03" "nifi-registry")

# ---- Seed authorized_keys + ensure SSH on each VM ----
for NAME in "${NODES[@]}"; do
  if ! multipass info "$NAME" >/dev/null 2>&1; then
    continue
  fi
  echo "Seeding authorized_keys and enabling ssh on ${NAME}…"

  multipass exec "$NAME" -- sudo bash -lc "
    set -o errexit -o nounset -o pipefail
    # Ensure ubuntu user home + .ssh
    id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu || true
    install -d -m 700 -o ubuntu -g ubuntu ~ubuntu/.ssh
    touch ~ubuntu/.ssh/authorized_keys
    chown ubuntu:ubuntu ~ubuntu/.ssh/authorized_keys
    chmod 600 ~ubuntu/.ssh/authorized_keys

    # Append key if not present
    grep -qxF '$PUBKEY' ~ubuntu/.ssh/authorized_keys || echo '$PUBKEY' >> ~ubuntu/.ssh/authorized_keys

    # Make sure ssh is installed and enabled
    apt-get update -y >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server >/dev/null 2>&1 || true
    systemctl enable --now ssh || systemctl enable --now sshd || true
  "
done

# ---- Update ~/.ssh/config with current IPs (idempotent, cleans stale blocks) ----
CONFIG="$HOME/.ssh/config"
mkdir -p "$HOME/.ssh"
touch "$CONFIG"
chmod 600 "$CONFIG"

# Derive private key path from the pubkey (for IdentityFile), expanding ~ if present
KEYPATH="${PUBKEY_PATH%.pub}"
eval KEYPATH="$KEYPATH"

# --- Robust removal of nifi-install managed blocks from ~/.ssh/config ---
purge_nifi_install_blocks() {
  local file="$1"
  local tmp="$(mktemp)"

  # 1) Remove every well-formed block from BEGIN..END (flexible whitespace)
  awk '
    BEGIN { inblk=0 }
    $0 ~ /^# BEGIN[[:space:]]+nifi-install[[:space:]]+\(managed\)[[:space:]]*$/ { inblk=1; next }
    $0 ~ /^# END[[:space:]]+nifi-install[[:space:]]+\(managed\)[[:space:]]*$/   { inblk=0; next }
    inblk { next }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"

  # 2) Remove any stray BEGIN lines left behind (e.g., prior malformed runs)
  awk '
    $0 ~ /^# BEGIN[[:space:]]+nifi-install[[:space:]]+\(managed\)[[:space:]]*$/ { next }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"

  # 3) Remove any stray END lines (just in case)
  awk '
    $0 ~ /^# END[[:space:]]+nifi-install[[:space:]]+\(managed\)[[:space:]]*$/ { next }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# Helpers to surgically edit ~/.ssh/config
remove_between_markers() {
  local file="$1" begin_re="$2" end_re="$3"
  awk -v B="$begin_re" -v E="$end_re" '
    $0 ~ B {drop=1; next}
    $0 ~ E {drop=0; next}
    !drop {print}
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

remove_host_block() {
  # Remove a full "Host <name>" block up to the next "Host " or EOF
  local file="$1" host="$2"
  awk -v H="$host" '
    BEGIN{drop=0}
    /^Host[[:space:]]+/ { drop=0 }                 # new block ends any drop
    $0 ~ "^Host[[:space:]]+" H "$" { drop=1; next }# start dropping this block
    drop && /^Host[[:space:]]+/ { drop=0 }         # safety
    drop { next }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# 1) Remove stale managed sections first (all occurrences)
remove_between_markers "$CONFIG" '^# BEGIN nifi-multipass' '^# END nifi-multipass'
remove_between_markers "$CONFIG" '^# BEGIN nifi-install \(managed\)$' '^# END nifi-install \(managed\)$'

# 2) Also remove any existing per-host blocks we manage (exact names and old numeric aliases)
for NAME in "${NODES[@]}"; do
  remove_host_block "$CONFIG" "$NAME"
done
remove_host_block "$CONFIG" "nifi-node-1"
remove_host_block "$CONFIG" "nifi-node-2"
remove_host_block "$CONFIG" "nifi-node-3"

# Remove any prior managed blocks/headers first
purge_nifi_install_blocks "$CONFIG"

# 3) Build a fresh managed block ONLY if we have at least one IP
TMPBLOCK="$(mktemp)"
{
  echo "# BEGIN nifi-install (managed)"
  echo "# This section is rewritten by the NiFi install tooling. Do not edit by hand."
} > "$TMPBLOCK"

added=0
for NAME in "${NODES[@]}"; do
  if multipass info "$NAME" >/dev/null 2>&1; then
    # First IPv4 from multipass info
    IP="$(multipass info "$NAME" \
         | awk -F': *' '/^[[:space:]]*IPv4/ {print $2; exit}' \
         | awk '{print $1}')"
    if [ -n "$IP" ]; then
      {
        echo "Host ${NAME}"
        echo "  CanonicalizeHostname no"
        echo "  HostName ${IP}"
        echo "  User ubuntu"
        echo "  IdentityFile ${KEYPATH}"
        echo "  IdentitiesOnly yes"
        echo
      } >> "$TMPBLOCK"
      added=$((added+1))
    else
      echo "WARN: could not determine IPv4 for ${NAME}; skipping" >&2
    fi
  fi
done

echo "# END nifi-install (managed)" >> "$TMPBLOCK"

if [ "$added" -gt 0 ]; then
  cat "$TMPBLOCK" >> "$CONFIG"
else
  echo "WARN: no nodes had IPs; not writing nifi-install block" >&2
fi
rm -f "$TMPBLOCK"

echo "SSH keys published and ~/.ssh/config updated."
