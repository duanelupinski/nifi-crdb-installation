#!/usr/bin/env bash
# Common utilities: logging, errors, local run, simple map helpers.

ni::log(){ [ "${QUIET:-false}" = true ] || echo "$@"; }
ni::die(){ echo "ERROR: $*" >&2; exit 1; }
ni::need(){ command -v "$1" >/dev/null 2>&1 || ni::die "Missing tool: $1"; }

ni::run(){
  if [ "${DRY_RUN:-false}" = true ]; then
    echo "[dry-run][local] $*"
  else
    eval "$@"
  fi
}

# --- tmp-backed KV (supports multi-word values) ----------------------------
# Create one temp dir per top-level process and only clean it up from that process.
ni::tmpmap_init(){
  # Reuse if already defined & exists
  if [ -n "${NI_TMP_ROOT:-}" ] && [ -d "${NI_TMP_ROOT}" ]; then
    return
  fi
  NI_TMP_ROOT="$(mktemp -d)"
  export NI_TMP_ROOT
  # Record the owner PID (top-level shell when this first runs)
  NI_TMP_OWNER="$$"
  export NI_TMP_OWNER
  # Only the owner cleans up on exit; subshells won't remove the dir
  trap '
    if [ "$$" = "${NI_TMP_OWNER}" ] && [ -n "${NI_TMP_ROOT}" ] && [ -d "${NI_TMP_ROOT}" ]; then
      rm -rf "${NI_TMP_ROOT}"
    fi
  ' EXIT
}

# Store: ni::put <namespace> <key> <value...>
# Accepts ANY number of args >= 3; joins value with spaces.
ni::put(){  # ni::put <ns> <key> <value...>
  [ "$#" -ge 3 ] || ni::die "ni::put expects >=3 args (ns key value...)"
  ni::tmpmap_init
  local ns="$1" key="$2"; shift 2
  mkdir -p "${NI_TMP_ROOT}/${ns}"
  printf '%s' "$*" > "${NI_TMP_ROOT}/${ns}/${key}"
}

# Get: prints empty string if not set
ni::get(){  # ni::get <ns> <key>
  [ "$#" -eq 2 ] || ni::die "ni::get expects 2 args (ns key)"
  ni::tmpmap_init
  [ -f "${NI_TMP_ROOT}/${1}/${2}" ] && cat "${NI_TMP_ROOT}/${1}/${2}" || true
}

# List keys into a named array: ni::keys <namespace> <arrname>
ni::keys(){ # ni::keys <ns> <arrname>
  [ "$#" -eq 2 ] || ni::die "ni::keys expects 2 args (ns arrname)"
  ni::tmpmap_init
  local -n _arr="$2"; _arr=()
  [ -d "${NI_TMP_ROOT}/${1}" ] && for f in "${NI_TMP_ROOT}/${1}"/*; do
    [ -e "$f" ] && _arr+=("$(basename "$f")")
  done
}

# Back-compat for any callers expecting ni::set
ni::set(){ ni::put "$@"; }

# Resolve a host via the node map; fallback to the key itself if unset
ni::resolve_host(){
  local key="$1" mapped
  mapped="$(ni::get node "$key")"
  printf '%s' "${mapped:-$key}"
}

ni::resolve_node_id(){
  local id; id="$(ni::get node-id "$1")"
  if [ -n "$id" ]; then printf '%s' "$id"; return 0; fi
  local list i=1; list="$(ni::get nodelist nifi_nodes)"
  for h in $list; do [ "$h" = "$1" ] && { printf '%s' "$i"; return 0; }; i=$((i+1)); done
}
