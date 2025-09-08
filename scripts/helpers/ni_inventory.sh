#!/usr/bin/env bash
# Build and read the node inventory for the installer.
# Accepts only node tokens: node-<id>:<hostname> (any "=ignored" tail is stripped)

ni::inventory_from_args() {
  local registry_host="$1"; shift

  local nodes=()
  for a in "$@"; do
    # Expect node-<digits>:<host>[=ignored]
    if [[ "$a" =~ ^node-([0-9]+):(.*)$ ]]; then
      local id="${BASH_REMATCH[1]}"
      local host="${BASH_REMATCH[2]}"
      host="${host%%=*}"            # strip any =ignored tail

      nodes+=("$host")

      # --- store mappings for later lookups ---
      ni::put node    "$host" "$host"  # identity (host -> host)
      ni::put node-id "$host" "$id"    # host -> numeric id
    fi
  done

  if [ ${#nodes[@]} -eq 0 ]; then
    ni::die "No nodes provided"
  fi

  # first three are the NiFi/ZK ensemble (preserve given order)
  local first3=()
  for i in 0 1 2; do
    [ -n "${nodes[$i]:-}" ] && first3+=("${nodes[$i]}")
  done

  # all hosts = all nodes + registry (no dup)
  local hosts=( "${nodes[@]}" )
  if [ -n "${registry_host:-}" ]; then
    local seen=false
    for h in "${hosts[@]}"; do [ "$h" = "$registry_host" ] && { seen=true; break; }; done
    $seen || hosts+=("$registry_host")
    # keep identity mapping for registry as well
    ni::put node "$registry_host" "$registry_host"
  fi

  # persist lists
  ni::put nodelist nodes      "${nodes[@]}"
  ni::put nodelist nifi_nodes "${first3[@]}"
  ni::put nodelist zk_nodes   "${first3[@]}"
  ni::put nodelist hosts      "${hosts[@]}"
}


# ----------------- Getters (arrays by name) -----------------

# Usage: ni::nodes myarr
ni::nodes() {
  local -n out="$1"
  local s; s="$(ni::get nodelist nodes)"
  # split by IFS into array (handles multi-host lists written by ni::put)
  read -r -a out <<<"$s"
}

ni::nifi_nodes() {
  local -n out="$1"
  local s; s="$(ni::get nodelist nifi_nodes)"
  read -r -a out <<<"$s"
}

ni::zk_nodes() {
  local -n out="$1"
  local s; s="$(ni::get nodelist zk_nodes)"
  read -r -a out <<<"$s"
}

ni::hosts() {
  local -n out="$1"
  local s; s="$(ni::get nodelist hosts)"
  read -r -a out <<<"$s"
}
