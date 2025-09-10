#!/usr/bin/env bash
# Create/format/mount loop-backed ext4 images with explicit repo-style names.
# Examples:
#   prepare-loop-disks.sh vm-1 \
#     --default-size 50G \
#     --flowfile /mnt/flowfile-repo \
#     --database /mnt/database-repo \
#     --content /mnt/cont-repo1,/mnt/cont-repo2,/mnt/cont-repo3 \
#     --provenance /mnt/prov-repo1,/mnt/prov-repo2
#
# Per-disk sizes:
#   --content /mnt/cont-repo1:100G,/mnt/cont-repo2:150G

set -o errexit -o nounset -o pipefail

usage() {
  cat >&2 <<'USAGE'
usage: prepare-loop-disks.sh <vm-name>
  [--img-dir DIR]               (default: /var/lib/nifi-disks)
  [--default-size SIZE]         (default: 50G)
  [--flowfile NAME[:SIZE]]      (e.g., /mnt/flowfile-repo[:60G])
  [--database NAME[:SIZE]]      (e.g., /mnt/database-repo[:60G])
  [--content list]              comma list of NAME[:SIZE]
  [--provenance list]           comma list of NAME[:SIZE]
USAGE
}

VM_NAME="${1:-}"; shift || true
[ -n "${VM_NAME:-}" ] || { usage; exit 2; }

IMG_DIR="/var/lib/nifi-disks"
DEFAULT_SIZE="50G"
FLOWFILE_SPEC=""
DATABASE_SPEC=""
CONTENT_SPECS=""
PROVENANCE_SPECS=""

while (($#)); do
  case "$1" in
    --img-dir)        IMG_DIR="$2"; shift 2;;
    --default-size)   DEFAULT_SIZE="$2"; shift 2;;
    --flowfile)       FLOWFILE_SPEC="$2"; shift 2;;
    --database)       DATABASE_SPEC="$2"; shift 2;;
    --content)        CONTENT_SPECS="$2"; shift 2;;
    --provenance)     PROVENANCE_SPECS="$2"; shift 2;;
    -h|--help)        usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

multipass exec "$VM_NAME" -- sudo bash -s -- \
  "$IMG_DIR" "$DEFAULT_SIZE" "$FLOWFILE_SPEC" "$DATABASE_SPEC" "$CONTENT_SPECS" "$PROVENANCE_SPECS" <<'BASH'
set -o errexit -o nounset -o pipefail
IMG_DIR="$1"; DEFAULT_SIZE="$2"; FLOWFILE_SPEC="$3"; DATABASE_SPEC="$4"; CONTENT_SPECS="$5"; PROVENANCE_SPECS="$6"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing $1" >&2; exit 2; }; }
need losetup; need mount; need blkid; need mkfs.ext4; need findmnt; need awk; need sed; need tr; need e2label

modprobe loop || true
mkdir -p "$IMG_DIR" /mnt

entries=() # items are "MNT|IMG|SIZE"

add_entry() {
  local name="$1" size="${2:-}"
  [ -n "$name" ] || return 0
  local mnt base
  if [[ "$name" = /* ]]; then
    mnt="$name"
    base="${name#/mnt/}"; base="${base#/}"
  else
    mnt="/mnt/$name"
    base="$name"
  fi
  size="${size:-$DEFAULT_SIZE}"
  entries+=("$mnt|$IMG_DIR/${base//\//_}.img|$size")
}

split_list() {
  local list="$1"
  [[ -z "$list" ]] && return 0
  local item nm sz
  IFS=',' read -r -a arr <<< "$list"
  for item in "${arr[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"; item="${item%"${item##*[![:space:]]}"}"
    if [[ "$item" == *:* ]]; then nm="${item%%:*}"; sz="${item#*:}"; else nm="$item"; sz=""; fi
    add_entry "$nm" "$sz"
  done
}

parse_single() {
  local spec="$1" nm sz
  [[ -z "$spec" ]] && return 0
  if [[ "$spec" == *:* ]]; then nm="${spec%%:*}"; sz="${spec#*:}"; else nm="$spec"; sz=""; fi
  add_entry "$nm" "$sz"
}

parse_single "$FLOWFILE_SPEC"
parse_single "$DATABASE_SPEC"
split_list "$CONTENT_SPECS"
split_list "$PROVENANCE_SPECS"

# Clean old fstab lines we manage + legacy /mnt/diskN from this IMG_DIR
if [ -f /etc/fstab ]; then
  awk -v imgdir="$IMG_DIR" '
    { if (index($1, imgdir) == 1) next; if ($2 ~ /^\/mnt\/disk[0-9]+$/) next; print }' \
    /etc/fstab > /tmp/fstab.new || true
  cat /tmp/fstab.new > /etc/fstab || true
fi

prepare_mount() {
  local mnt="$1" img="$2" size="$3"
  install -d -m 0755 "$mnt"

  # De-dup specific img/mount entries
  if [ -f /etc/fstab ]; then
    awk -v img="$img" -v mnt="$mnt" '$1==img || $2==mnt {next} {print}' /etc/fstab > /tmp/fstab.new || true
    cat /tmp/fstab.new > /etc/fstab || true
  fi

  # Create image if missing
  [ -f "$img" ] || truncate -s "$size" "$img"

  # Ensure ext4
  local type; type=$(blkid -s TYPE -o value "$img" 2>/dev/null || true)
  if [ "$type" != "ext4" ]; then
    mkfs.ext4 -F "$img"
    e2label "$img" "nifi-$(basename "$mnt")" || true
  fi

  # Stable fstab line
  if ! grep -qE "^[[:space:]]*$(printf '%q' "$img")[[:space:]]+$(printf '%q' "$mnt")[[:space:]]+ext4" /etc/fstab; then
    echo "$img $mnt ext4 loop,defaults,nofail,x-systemd.requires-mounts-for=$IMG_DIR 0 2" >> /etc/fstab
  fi

  # Detach stale loops and mount
  while read -r dev _; do [ -n "${dev:-}" ] && losetup -d "$dev" || true; done < <(losetup -j "$img" | awk -F: '{print $1}')
  findmnt -rn --target "$mnt" >/dev/null 2>&1 || mount -t ext4 -o loop "$img" "$mnt" || true
}

for e in "${entries[@]}"; do
  IFS='|' read -r mnt img size <<< "$e"
  prepare_mount "$mnt" "$img" "$size"
done

mount -a -v || true

echo
echo "Mounted:"
for e in "${entries[@]}"; do
  IFS='|' read -r mnt img size <<< "$e"
  findmnt -rno TARGET,SOURCE,FSTYPE --target "$mnt" || true
done
echo
echo "Loop devices:"
losetup -a | grep "$IMG_DIR" || true
BASH
