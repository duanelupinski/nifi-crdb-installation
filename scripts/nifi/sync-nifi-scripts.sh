#!/usr/bin/env bash
set -Eeuo pipefail

# Defaults
SSH_USER="${SSH_USER:-ubuntu}"
NIFI_USER="${NIFI_USER:-nifi}"
SRC_DIR="${SRC_DIR:-./scripts/nifi/mongodb}"
DEST_DIR="${DEST_DIR:-/opt/nifi/scripts}"
SSH_KEY="${SSH_KEY:-}"          # e.g., /path/to/key.pem
DELETE="${DELETE:-0}"           # 1 to --delete extra files on remote
DRY_RUN="${DRY_RUN:-0}"         # 1 to show actions without changing
SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4)

usage() {
  cat <<EOF
Usage: $0 [options] <host1> [host2 ...]
Options:
  --ssh-user <user>       (default: $SSH_USER)
  --nifi-user <user>      (default: $NIFI_USER)
  --src <dir>             (default: $SRC_DIR)
  --dest <dir>            (default: $DEST_DIR)
  --ssh-key <file>        (optional, ssh private key)
  --delete                remove remote files not present locally
  --dry-run               show what would happen, do nothing
  -h, --help
Env overrides also supported: SSH_USER, NIFI_USER, SRC_DIR, DEST_DIR, SSH_KEY, DELETE, DRY_RUN
EOF
}

# --- arg parse ---
while (( "$#" )); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --ssh-user)  SSH_USER="$2"; shift 2 ;;
    --nifi-user) NIFI_USER="$2"; shift 2 ;;
    --src)       SRC_DIR="$2";  shift 2 ;;
    --dest)      DEST_DIR="$2"; shift 2 ;;
    --ssh-key)   SSH_KEY="$2";  shift 2 ;;
    --delete)    DELETE=1; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    --) shift; break ;;
    -*) echo "WARN: unknown option $1" >&2; shift ;;
    *) break ;;
  esac
done

if (( "$#" == 0 )); then
  echo "ERROR: provide at least one hostname"; usage; exit 1
fi
HOSTS=("$@")

# --- sanity checks ---
if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERROR: source directory not found: $SRC_DIR" >&2
  exit 2
fi

# ssh key option
if [[ -n "$SSH_KEY" ]]; then
  SSH_OPTS+=(-i "$SSH_KEY")
fi

# trailing-slash rsync semantics: copy CONTENTS of SRC_DIR into remote DEST_SUBDIR
SRC_DIR_ABS="$(cd "$SRC_DIR" && pwd)"
SRC_BASENAME="$(basename "$SRC_DIR_ABS")"
REMOTE_SUBDIR="$DEST_DIR/$SRC_BASENAME"

# rsync flags
RSYNC_FLAGS=(-avz --progress --omit-dir-times --no-perms --no-group)
(( DELETE == 1 )) && RSYNC_FLAGS+=(--delete)
(( DRY_RUN == 1 )) && RSYNC_FLAGS+=(--dry-run)
SSH_CMD="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"


# function to run an ssh command (with optional DRY RUN echo)
ssh_run() {
  local host="$1"; shift
  if (( DRY_RUN == 1 )); then
    echo "[dry-run] ssh ${SSH_OPTS[*]} ${SSH_USER}@${host} $*"
  else
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "$@"
  fi
}

for H in "${HOSTS[@]}"; do
  echo ">>> syncing to $H"

  # 1) prepare destination on remote (mkdir + perms)
  ssh_run "$H" bash -s <<'REMOTE'
set -Eeuo pipefail
SUDO=""; [[ "$EUID" -ne 0 ]] && SUDO="sudo -n" || true
REMOTE
  # pass variables and do the real work with a second heredoc so we can interpolate
  ssh_run "$H" NIFI_USER="$NIFI_USER" DEST_DIR="$DEST_DIR" REMOTE_SUBDIR="$REMOTE_SUBDIR" bash -s <<'REMOTE'
set -Eeuo pipefail
SUDO=""; [[ "$EUID" -ne 0 ]] && SUDO="sudo -n" || true

# create base and subdir
$SUDO mkdir -p "$DEST_DIR"
$SUDO mkdir -p "$REMOTE_SUBDIR"
# own by NIFI_USER (user:group)
if getent passwd "$NIFI_USER" >/dev/null 2>&1; then
  GRP="$(id -gn "$NIFI_USER")"
else
  GRP="$NIFI_USER"
fi
$SUDO chown -R "$NIFI_USER":"$GRP" "$REMOTE_SUBDIR"
$SUDO chmod 0755 "$DEST_DIR" "$REMOTE_SUBDIR"
REMOTE

  # 2) try rsync (preferred)
  RSYNC_AVAILABLE=0
  if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${H}" 'command -v rsync >/dev/null 2>&1'; then
    RSYNC_AVAILABLE=1
  fi

  ssh ${SSH_USER}@${H} 'sudo -n mkdir -p /opt/nifi/scripts/mongodb && sudo -n chmod 0755 /opt/nifi/scripts/mongodb'
  if (( RSYNC_AVAILABLE == 1 )); then
    echo " - using rsync"
    # Note the trailing slash on SRC to copy contents into REMOTE_SUBDIR
    if (( DRY_RUN == 1 )); then
      echo "[dry-run] rsync ${RSYNC_FLAGS[*]} -e \"$SSH_CMD\" --rsync-path=\"sudo -n rsync\" \"$SRC_DIR_ABS/\" \"${SSH_USER}@${H}:$REMOTE_SUBDIR/\""
    else
      rsync "${RSYNC_FLAGS[@]}" \
        -e "$SSH_CMD" \
        --rsync-path="sudo -n rsync" \
        "$SRC_DIR_ABS/" "${SSH_USER}@${H}:$REMOTE_SUBDIR/"
    fi
  else
    echo " - rsync not found on $H, falling back to scp -r"
    if (( DRY_RUN == 1 )); then
      echo "[dry-run] scp ${SSH_KEY:+-i $SSH_KEY} -r \"$SRC_DIR_ABS/*\" \"${SSH_USER}@${H}:$REMOTE_SUBDIR/\""
    else
      # shellcheck disable=SC2086
      scp ${SSH_KEY:+-i "$SSH_KEY"} -r "$SRC_DIR_ABS"/* "${SSH_USER}@${H}:$REMOTE_SUBDIR/"
    fi
    if (( DELETE == 1 )); then
      echo "   (delete requested, but scp fallback does not support remote prune)"
    fi
  fi

  # 3) fix ownership/permissions after copy
  ssh_run "$H" NIFI_USER="$NIFI_USER" REMOTE_SUBDIR="$REMOTE_SUBDIR" bash -s <<'REMOTE'
set -Eeuo pipefail
SUDO=""; [[ "$EUID" -ne 0 ]] && SUDO="sudo -n" || true
if getent passwd "$NIFI_USER" >/dev/null 2>&1; then
  GRP="$(id -gn "$NIFI_USER")"
else
  GRP="$NIFI_USER"
fi

# directories 0755, files 0644, and make scripts executable
$SUDO find "$REMOTE_SUBDIR" -type d -exec chmod 0755 {} +
$SUDO find "$REMOTE_SUBDIR" -type f -exec chmod 0644 {} +
$SUDO find "$REMOTE_SUBDIR" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.groovy" \) -exec chmod +x {} +
$SUDO chown -R "$NIFI_USER":"$GRP" "$REMOTE_SUBDIR"

echo " - synced to $REMOTE_SUBDIR:"
ls -l "$REMOTE_SUBDIR" | sed "s/^/   /"
REMOTE

  echo ">>> done $H"
done

echo "All hosts completed."
