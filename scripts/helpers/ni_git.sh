#!/usr/bin/env bash
# Automate the configuration of a Git repository for the NiFi registry
# -------------------------------------------------------------------
# Idempotent Git provider configuration for NiFi Registry
# Depends on: xmlstarlet, git, systemd, and existing ni::ssh_sudo helper
# Usage (HTTPS + PAT):
#   export GIT_TOKEN='******'     # fine-grained PAT with repo read/write
#   ni::git::configure nifi-registry \
#     https://github.com/owner/repo.git gh-username "Your Name" you@domain.com \
#     registry /home/nifi/repo origin nifi nifi
#
# Usage (SSH remote; no token required):
#   unset GIT_TOKEN
#   ni::git::configure nifi-registry \
#     git@github.com:owner/repo.git "" "Your Name" you@domain.com \
#     registry /home/nifi/repo origin nifi nifi
# -------------------------------------------------------------------

# Configure NiFi Registry to use GitFlowPersistenceProvider and point at a repo.
# Args:
#   $1  remote                     (ssh target your ni::ssh_sudo understands)
#   $2  repo_url                   (https://… or git@github.com:…)
#   $3  gh_username                (for HTTPS; "" if SSH)
#   $4  git_user_name              (git identity stored for the nifi user)
#   $5  git_user_email             (git identity stored for the nifi user)
#   $6  branch           [registry]
#   $7  repo_dir         [/home/nifi/nifi-flows]
#   $8  remote_name      [origin]
#   $9  nifi_user        [nifi]
#   $10 nifi_group       [nifi]
ni::git::configure() {
  local remote="$1"; shift
  local repo_url="${1:?repo_url required}"; shift
  local gh_user="${1:-}"; shift
  local git_user_name="${1:?git_user_name required}"; shift
  local git_user_name_enc=${git_user_name// /%20}
  local git_user_email="${1:?git_user_email required}"; shift
  local branch="${1:-registry}"; shift || true
  local repo_dir="${1:-nifi-flows}"; shift || true
  local remote_name="${1:-origin}"; shift || true
  local nifi_user="${1:-nifi}"; shift || true
  local nifi_group="${1:-nifi}"; shift || true

  # Pass token as an env var into the remote session (keeps it out of arg list)
  ni::ssh_sudo "$remote" env GIT_TOKEN="${GIT_TOKEN:-}" bash -s -- \
    "$repo_url" "$gh_user" "$git_user_name_enc" "$git_user_email" "$branch" \
    "$repo_dir" "$remote_name" "$nifi_user" "$nifi_group" <<'BASH'
set -o errexit -o nounset -o pipefail
REPO_URL="$1"; GH_USER="$2"; GIT_USER_NAME="$3"; GIT_USER_EMAIL="$4"; BRANCH="$5"
REPO_DIR="$6"; REMOTE_NAME="$7"; NIFI_USER="$8"; NIFI_GROUP="${9}"
GIT_USER_NAME="${GIT_USER_NAME//%20/ }"
NIFI_REG_HOME="${NIFI_REGISTRY_HOME:-/opt/nifi-registry}"
PROVIDERS_XML="${NIFI_REG_HOME}/conf/providers.xml"
LOG="${NIFI_REG_HOME}/logs/nifi-registry-app.log"
REPO_DIR="/home/${NIFI_USER}/${REPO_DIR}"
BACKUP_SUFFIX="$(date +%Y%m%d%H%M%S)"
HTTPS_REMOTE=0
[[ "$REPO_URL" =~ ^https:// ]] && HTTPS_REMOTE=1

need() { command -v "$1" >/dev/null || { echo "ERR: missing $1"; exit 1; }; }
need git
need xmlstarlet
test -f "$PROVIDERS_XML" || { echo "ERR: $PROVIDERS_XML not found"; exit 1; }

# Guard: if HTTPS remote, require a token
if (( HTTPS_REMOTE == 1 )); then
  : "${GIT_TOKEN:?ERR: GIT_TOKEN environment variable is required for HTTPS remotes}"
fi

# Ensure repo parent and ownership
install -d -m 0755 -o "$NIFI_USER" -g "$NIFI_GROUP" "$(dirname "$REPO_DIR")"

# Git identity for the NiFi service user
sudo -u "$NIFI_USER" git config --global --replace-all user.name  "$GIT_USER_NAME"  || true
sudo -u "$NIFI_USER" git config --global --replace-all user.email "$GIT_USER_EMAIL" || true
sudo -u "$NIFI_USER" git config --global --unset-all safe.directory || true
sudo -u "$NIFI_USER" git config --global --add safe.directory "$REPO_DIR" || true

# If HTTPS, create a strict .netrc for non-interactive auth (useful for manual ops too)
if (( HTTPS_REMOTE == 1 )); then
  sudo -u "$NIFI_USER" bash -c "umask 077; cat > /home/${NIFI_USER}/.netrc <<NETRC
machine github.com
  login ${GH_USER}
  password ${GIT_TOKEN}
NETRC"
fi

# Clone or reconcile repo
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "Cloning $REPO_URL -> $REPO_DIR"
  sudo -u "$NIFI_USER" git clone "$REPO_URL" "$REPO_DIR"
  sudo -u "$NIFI_USER" git -C "$REPO_DIR" checkout "$BRANCH" || true
else
  echo "Repo exists; syncing remote/branch"
  sudo -u "$NIFI_USER" git -C "$REPO_DIR" remote set-url "$REMOTE_NAME" "$REPO_URL" || true
  sudo -u "$NIFI_USER" git -C "$REPO_DIR" fetch "$REMOTE_NAME" || true
  sudo -u "$NIFI_USER" git -C "$REPO_DIR" checkout "$BRANCH" || true
  sudo -u "$NIFI_USER" git -C "$REPO_DIR" pull --ff-only || true
fi
chown -R "$NIFI_USER:$NIFI_GROUP" "$REPO_DIR"

# Prepare property values for providers.xml
if (( HTTPS_REMOTE == 1 )); then
  REMOTE_ACCESS_USER="$GH_USER"
  REMOTE_ACCESS_PASSWORD="${GIT_TOKEN}"
else
  REMOTE_ACCESS_USER=""
  REMOTE_ACCESS_PASSWORD=""
fi
# Clone URL only for first-time bootstrap (no .git dir)
REMOTE_CLONE_REPO=""
[ ! -d "$REPO_DIR/.git" ] && REMOTE_CLONE_REPO="$REPO_URL"

# Backup and rewrite the flowPersistenceProvider cleanly
cp -a "$PROVIDERS_XML" "${PROVIDERS_XML}.${BACKUP_SUFFIX}.bak"

# Remove any existing flowPersistenceProvider blocks to avoid duplicates
xmlstarlet ed -P -L -d "/providers/flowPersistenceProvider" "$PROVIDERS_XML"

# Insert a new empty flowPersistenceProvider BEFORE the first child.
# If no children exist, append it as the first under /providers.
if xmlstarlet sel -t -c "/providers/*[1]" "$PROVIDERS_XML" | grep -q .; then
  xmlstarlet ed -P -L -i "/providers/*[1]" -t elem -n "flowPersistenceProvider" -v "" "$PROVIDERS_XML"
else
  xmlstarlet ed -P -L -s "/providers" -t elem -n "flowPersistenceProvider" -v "" "$PROVIDERS_XML"
fi

# Populate it with the Git provider class and properties
xmlstarlet ed -P -L \
  -s "/providers/flowPersistenceProvider[1]" -t elem -n class -v "org.apache.nifi.registry.provider.flow.git.GitFlowPersistenceProvider" \
  -s "/providers/flowPersistenceProvider[1]" -t elem -n property -v "$REPO_DIR" \
  -i "/providers/flowPersistenceProvider[1]/property[1]" -t attr -n name -v "Flow Storage Directory" \
  -s "/providers/flowPersistenceProvider[1]" -t elem -n property -v "$REMOTE_NAME" \
  -i "/providers/flowPersistenceProvider[1]/property[2]" -t attr -n name -v "Remote To Push" \
  -s "/providers/flowPersistenceProvider[1]" -t elem -n property -v "${REMOTE_ACCESS_USER}" \
  -i "/providers/flowPersistenceProvider[1]/property[3]" -t attr -n name -v "Remote Access User" \
  -s "/providers/flowPersistenceProvider[1]" -t elem -n property -v "${REMOTE_ACCESS_PASSWORD}" \
  -i "/providers/flowPersistenceProvider[1]/property[4]" -t attr -n name -v "Remote Access Password" \
  -s "/providers/flowPersistenceProvider[1]" -t elem -n property -v "$REMOTE_CLONE_REPO" \
  -i "/providers/flowPersistenceProvider[1]/property[5]" -t attr -n name -v "Remote Clone Repository" \
  "$PROVIDERS_XML"

# Restart registry and show a brief status + last 100 lines
systemctl restart nifi-registry
sleep 10
systemctl --no-pager --full status nifi-registry || true

# Quick check for provider load
if grep -q "GitFlowPersistenceProvider" "$LOG"; then
  echo "OK: GitFlowPersistenceProvider appears in logs."
else
  echo "WARN: did not find GitFlowPersistenceProvider string in logs yet."
fi
BASH
}

# Convenience: verify current provider & properties
ni::git::verify_git_provider() {
  local remote="$1"; shift
  ni::ssh_sudo "$remote" bash -s -- <<'BASH'
set -o errexit -o nounset -o pipefail
NIFI_REG_HOME="${NIFI_REGISTRY_HOME:-/opt/nifi-registry}"
PROVIDERS_XML="${NIFI_REG_HOME}/conf/providers.xml"
test -f "$PROVIDERS_XML" || { echo "ERR: $PROVIDERS_XML not found"; exit 1; }
command -v xmlstarlet >/dev/null || { echo "ERR: xmlstarlet missing"; exit 1; }
echo "class: $(xmlstarlet sel -t -v '/providers/flowPersistenceProvider/class' "$PROVIDERS_XML")"
echo "Flow Storage Directory: $(xmlstarlet sel -t -v '/providers/flowPersistenceProvider/property[@name="Flow Storage Directory"]' "$PROVIDERS_XML")"
echo "Remote To Push: $(xmlstarlet sel -t -v '/providers/flowPersistenceProvider/property[@name="Remote To Push"]' "$PROVIDERS_XML")"
echo "Remote Access User: $(xmlstarlet sel -t -v '/providers/flowPersistenceProvider/property[@name="Remote Access User"]' "$PROVIDERS_XML")"
# don't echo password
echo "Remote Clone Repository: $(xmlstarlet sel -t -v '/providers/flowPersistenceProvider/property[@name="Remote Clone Repository"]' "$PROVIDERS_XML")"
BASH
}
