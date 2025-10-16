#!/usr/bin/env bash
# helpers/ni_tunnel.sh
# Prepare a tunnel for private networks into the NiFi cluster

ni::tunnel::log() { printf '[ni] %s\n' "$*"; }
ni::tunnel::warn() { printf '[ni][WARN] %s\n' "$*" >&2; }
ni::tunnel::err() { printf '[ni][ERR] %s\n' "$*" >&2; }

# Return 0 (true) if we need a tunnel to reach https://<host>:<port>
ni::tunnel::needs_tunnel() {
  local scheme="${1:-http}"; local host="${2:-nifi-node-01}"; local port="${3:-8080}"
  curl -skI --connect-timeout 2 "${scheme}://${host}:${port}/" >/dev/null 2>&1 || return 0
  return 1
}

# Determine if a local TCP port is already listening (e.g., an existing tunnel)
ni::tunnel::port_listening() {
  local port="$1"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
}

# Start a background SSH tunnel if not already active.
# Usage: ni::tunnel::ensure <ssh_user> <admin_host> <admin_port> [registry_host] [registry_port]
# - Binds local <admin_port> -> admin_host:<admin_port>
# - Binds local <registry_port> -> registry_host:<registry_port> (if provided)
# Uses ControlMaster so multiple forwards share one connection.
ni::tunnel::ensure() {
  local ssh_user="$1"; local admin_host="$2"; local local_admin="$3";
  local registry_host="${4:-}"; local local_reg="${5:-}"
  local forwards=(-L "${local_admin}:${admin_host}:${local_admin}")
  [ -n "$registry_host" ] && forwards+=(-L "${local_reg}:${registry_host}:${local_reg}")

  # If both local ports are already listening, assume we’re good.
  if ni::tunnel::port_listening "$local_admin" && { [ -z "$registry_host" ] || ni::tunnel::port_listening "$local_reg"; }; then
    ni::tunnel::log "SSH tunnel already active on localhost:${local_admin}${registry_host:+ and :${local_reg}}."
    return 0
  fi

  # macOS option: open a new Terminal window if NIFI_OPEN_TERMINAL=1
  if [ "${NIFI_OPEN_TERMINAL:-0}" = "1" ] && command -v osascript >/dev/null 2>&1; then
    local cmd="ssh -N ${forwards[*]} ${ssh_user}@${admin_host}"
    ni::tunnel::log "Opening new Terminal window for tunnel: $cmd"
    osascript <<OSA
tell application "Terminal"
  activate
  do script "$cmd"
end tell
OSA
    # Give it a moment, then verify ports
    sleep 1
  else
    # Background, resilient control socket
    local ctl_dir="${HOME}/.ssh/nifi-ctl"
    mkdir -p "$ctl_dir"
    local ctl="${ctl_dir}/admin-${admin_host}"
    # Try to reuse an existing control session if present
    ssh -O check -S "$ctl" "${ssh_user}@${admin_host}" >/dev/null 2>&1 && {
      ni::tunnel::log "Reusing existing SSH control session for ${admin_host}."
    } || {
      ni::tunnel::log "Starting SSH control session for ${admin_host}."
      ssh -fN -M -S "$ctl" -o ControlPersist=10m "${ssh_user}@${admin_host}" true || {
        ni::tunnel::err "Failed to start SSH control session to ${admin_host}"
        return 1
      }
    }
    # Add port forwards via the control master (keeps one connection)
    ni::tunnel::log "Adding port forwards: ${forwards[*]}"
    ssh -S "$ctl" -O forward "${ssh_user}@${admin_host}" "${forwards[@]}" || {
      # Some ssh implementations don't support -O forward; fall back to single background ssh
      ni::tunnel::warn "ControlForward not supported; starting standalone tunnel process."
      ssh -fN "${forwards[@]}" "${ssh_user}@${admin_host}" || {
        ni::tunnel::err "Failed to start SSH tunnel."
        return 1
      }
    }
    # Small grace period for sockets to bind
    sleep 1
  fi

  attempts=5
  delay=1
  for ((i=1; i<=attempts; i++)); do
    if ni::tunnel::port_listening "$local_admin" && { [ -z "$registry_host" ] || ni::tunnel::port_listening "$local_reg"; }; then
      ni::tunnel::log "SSH tunnel ready: https://localhost:${local_admin}/ ${registry_host:+and https://localhost:${local_reg}/}"
      return 0
    fi
    if [ "$i" -lt "$attempts" ]; then
      ni::tunnel::log "Tunnel not ready yet (attempt ${i}/${attempts}); retrying in ${delay}s…"
      sleep "$delay"
      delay=$(( delay < 8 ? delay * 2 : 8 ))
    fi
  done
  ni::tunnel::err "Tunnel ports not listening after ${attempts} attempts."
  return 1
}

# Ensure aliases exist on the 127.0.0.1 line in /etc/hosts (idempotent).
# Usage: ni::tunnel::ensure_local_aliases nifi-node-01 nifi-node-02 nifi-registry ...
ni::tunnel::ensure_local_aliases() {
  local aliases=("$@")
  [ "${#aliases[@]}" -gt 0 ] || { ni::tunnel::warn "No aliases supplied to ni::tunnel::ensure_local_aliases"; return 0; }

  local hosts="/etc/hosts"
  [ -w "$hosts" ] || ni::tunnel::log "Updating $hosts requires sudo."

  # Read current 127.0.0.1 line and build the desired union
  local current desired tmp
  current="$(grep -E '^[[:space:]]*127\.0\.0\.1[[:space:]]' "$hosts" || true)"
  if [ -z "$current" ]; then
    # No localhost line present; add a sane default
    desired="127.0.0.1\tlocalhost ${aliases[*]}"
    tmp="$(mktemp)"
    { echo -e "$desired"; cat "$hosts"; } >"$tmp"
    sudo cp "$tmp" "$hosts"; rm -f "$tmp"
    ni::tunnel::log "Added localhost line with aliases to $hosts"
    return 0
  fi

  # Tokenize current aliases while preserving 'localhost'
  # shellcheck disable=SC2206
  local words=($current)
  # words[0] = 127.0.0.1
  # subsequent = names
  declare -A seen
  local newlist=()
  for i in "${!words[@]}"; do
    if [ "$i" -eq 0 ]; then
      continue
    fi
    # Dedup existing
    if [ -z "${seen[${words[$i]}]+x}" ]; then
      newlist+=("${words[$i]}")
      seen["${words[$i]}"]=1
    fi
  done
  # Ensure 'localhost' present first
  if [ -z "${seen[localhost]+x}" ]; then
    newlist=("localhost" "${newlist[@]}")
    seen[localhost]=1
  fi
  # Add requested aliases if missing
  for a in "${aliases[@]}"; do
    if [ -z "${seen[$a]+x}" ]; then
      newlist+=("$a")
      seen["$a"]=1
    fi
  done

  desired="127.0.0.1\t$(printf '%s ' "${newlist[@]}")"
  desired="${desired%" "}"

  # If identical, do nothing
  if [ "$current" = "$desired" ]; then
    ni::tunnel::log "$hosts already contains aliases on 127.0.0.1: ${aliases[*]}"
    return 0
  fi

  # Replace the line atomically
  tmp="$(mktemp)"
  awk -v repl="$desired" '
    BEGIN { done=0 }
    /^[[:space:]]*127\.0\.0\.1[[:space:]]/ { if (!done) { print repl; done=1; next } }
    { print }
    END { if (!done) print repl }
  ' "$hosts" >"$tmp"
  sudo cp "$tmp" "$hosts"; rm -f "$tmp"
  ni::tunnel::log "Updated $hosts 127.0.0.1 aliases: ${aliases[*]}"
}

# Call this right after starting cluster services and before authorizing nodes.
# Usage: ni::tunnel::prepare_local_access <secure> <ssh_user> [registry_host]
ni::tunnel::prepare_local_access() {
  local secure="${1:-false}"
  local ssh_user="${2:-ubuntu}"
  local registry_host="${3:-}"   # optional
  if [ "${#NIFI_NODES[@]}" -eq 0 ]; then
    ni::tunnel::err "NIFI_NODES is empty; cannot infer admin and node aliases."
    return 1
  fi
  local admin_host="${NIFI_NODES[0]}"

  local nifi_scheme="http"
  local nifi_port="8080"
  local reg_port="18080"
  if [ "${secure}" = true ]; then
    nifi_scheme="https"
    nifi_port="9443"
    reg_port="19443"
  fi

  if ni::tunnel::needs_tunnel "$nifi_scheme" "$admin_host" "$nifi_port"; then
    # 1) If admin UI not reachable, create/ensure tunnel
    ni::tunnel::log "Admin UI not reachable directly; creating SSH tunnel via ${admin_host}."
    NIFI_OPEN_TERMINAL=1 ni::tunnel::ensure "$ssh_user" "$admin_host" "$nifi_port" "$registry_host" "$reg_port" || return 1

    # Ensure /etc/hosts has ALL aliases pointing to localhost:
    # - admin host
    # - registry host (if any)
    # - any remaining cluster nodes (passed as extra args)
    local aliases=("$admin_host")
    [ -n "$registry_host" ] && aliases+=("$registry_host")
    if [ "${#NIFI_NODES[@]}" -gt 1 ]; then
      aliases+=("${NIFI_NODES[@]:1}")
    fi
    ni::tunnel::ensure_local_aliases "${aliases[@]}"
  else
    ni::tunnel::log "Admin UI reachable directly at ${nifi_scheme}://${admin_host}:${nifi_port} — tunnel not required."
  fi
}
