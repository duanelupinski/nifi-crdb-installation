#!/usr/bin/env bash
# SSH helpers with dry-run support.


ni::ssh() {
  local r="$1"; shift
  if [ "${DRY_RUN:-false}" = true ]; then
    printf '[dry-run][%s]' "$r"; printf ' %q' "$@"; printf '\n'
    cat >/dev/null
    return 0
  fi
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -T "$r" "$@"
}

ni::ssh_sudo() {
  local r="$1"; shift
  if [ $# -eq 0 ]; then
    ni::ssh "$r" sudo -H bash -l
    return
  fi

  # If the argv contains a shell (e.g., `env ... -- bash -s`, or direct `bash -s`), pass through.
  case " $* " in
    *" bash "*|*" /bin/bash "*|*" sh "*|*" /bin/sh "*) 
      ni::ssh "$r" sudo -H "$@"
      ;;
    *)
      # Otherwise run a root login shell and execute the whole line.
      # (Joins args; good for simple commands/&& chains, but not for heredocs.)
      local cmd; printf -v cmd '%s ' "$@"
      ni::ssh "$r" sudo -n -H bash -lc "$cmd"
      ;;
  esac
}

# Heredoc over SSH (no PTY) — preserves newlines & "$@" correctly; fixes PTY warning
ni::ssh_sudo_stdin(){
  local r="$1"; shift
  local script; script="$(cat)"
  if [ "${DRY_RUN:-false}" = true ]; then
    echo "[dry-run][${r}] sudo -H bash -s -- $* <<'BASH'"
    printf '%s\n' "$script"
    echo "BASH"
    return 0
  fi
  local q=(); for a in "$@"; do q+=("$(printf "%q" "$a")"); done
  printf '%s' "$script" | ssh -T -o BatchMode=yes -o StrictHostKeyChecking=no "$r" "sudo -H bash -s -- ${q[*]}"
}

# Wait for SSH on a given remote like "ubuntu@nifi-node-01"
ni::wait_ssh_or_die() {
  local remote="$1"
  local user="${remote%@*}"
  local host="${remote#*@}"
  local timeout="${SSH_TIMEOUT:-600}"

  # Try a few spots, or use WAIT_SSH_SCRIPT if exported
  local -a candidates=()
  [ -n "${WAIT_SSH_SCRIPT:-}" ] && candidates+=("$WAIT_SSH_SCRIPT")
  [ -n "${NI_DIR:-}" ] && candidates+=("${NI_DIR}/scripts/wait-ssh.sh" "${NI_DIR}/wait-ssh.sh")
  candidates+=("./scripts/wait-ssh.sh" "./wait-ssh.sh")

  local found=""
  for p in "${candidates[@]}"; do
    [ -x "$p" ] && { found="$p"; break; }
  done

  if [ -n "$found" ]; then
    "$found" -u "$user" -t "$timeout" -c "$host"
    return
  fi

  echo "INFO: wait-ssh.sh not found; using inline wait..."
  for _ in $(seq 1 $((timeout/5+1))); do
    if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$remote" true 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  echo "ERROR: SSH not reachable for $remote after ${timeout}s" >&2
  return 1
}
