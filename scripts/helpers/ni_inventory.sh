#!/usr/bin/env bash
# Build and read the node inventory for the installer.
# Accepts only node tokens: node-<id>:<hostname> (any "=ignored" tail is stripped)

ni::inventory_from_args() {
  # require bash
  if [ -z "${BASH_VERSION:-}" ]; then
    echo "ni::inventory_from_args requires bash" >&2
    return 127
  fi

  local registry_host=""
  case "${1:-}" in
    --registry)
      [ -n "${2:-}" ] || ni::die "--registry requires a host"
      registry_host="$2"
      shift 2
      ;;
    --no-registry)
      registry_host=""
      shift 1
      ;;
    *)
      ni::die "first arg must be --registry <host> or --no-registry"
      ;;
  esac

  # -------- parse node specs --------
  local nodes=()
  while (($#)); do
    local a="$1"; shift
    if [[ "$a" =~ ^node-([0-9]+):(.*)$ ]]; then
      local id="${BASH_REMATCH[1]}"
      local host="${BASH_REMATCH[2]}"
      host="${host%%=*}"                     # strip any =ignored tail
      nodes+=("$host")
      ni::put node    "$host" "$host"        # identity (host -> host)
      ni::put node-id "$host" "$id"          # host -> numeric id
    else
      ni::die "Invalid node spec: '$a' (expected node-<id>:<host>[=ignored])"
    fi
  done

  [ ${#nodes[@]} -gt 0 ] || ni::die "No nodes provided"

  # first three are the NiFi/ZK ensemble (preserve given order)
  local first3=()
  for i in 0 1 2; do
    [ -n "${nodes[$i]:-}" ] && first3+=("${nodes[$i]}")
  done

  # all hosts = nodes + optional registry (dedup)
  local hosts=( "${nodes[@]}" )
  if [ -n "$registry_host" ]; then
    local seen=""
    for h in "${hosts[@]}"; do
      if [ "$h" = "$registry_host" ]; then seen="yes"; break; fi
    done
    [ -n "$seen" ] || hosts+=("$registry_host")
    ni::put node "$registry_host" "$registry_host"
    ni::put scalar has_registry "true"
    ni::put scalar registry_host "$registry_host"
  else
    ni::put scalar has_registry "false"
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
