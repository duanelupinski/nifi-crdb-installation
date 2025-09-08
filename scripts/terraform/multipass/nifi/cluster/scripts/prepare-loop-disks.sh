#!/usr/bin/env bash
# prepare-loop-disks.sh
# Create/format/mount loop-backed ext4 images as /mnt/disk1..N on a Multipass VM.
# Idempotent: cleans old fstab lines, ensures ext4, detaches stale loops, mounts,
# and finally runs `mount -a -v` to guarantee all fstab entries are active.

set -o errexit -o nounset -o pipefail

VM_NAME="${1:?usage: $0 <vm-name> [count] [size] }"
COUNT="${2:-5}"        # number of loop disks
SIZE="${3:-50G}"       # size of each image file
IMG_DIR="/var/lib/nifi-disks"

multipass exec "$VM_NAME" -- sudo bash -s -- "$COUNT" "$SIZE" "$IMG_DIR" <<'REMOTE'
COUNT="$1"; SIZE="$2"; IMG_DIR="$3"
set -o errexit -o nounset -o pipefail

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing $1" >&2; exit 2; }; }
need losetup; need mount; need blkid; need mkfs.ext4; need findmnt; need awk; need sed

modprobe loop || true
mkdir -p "$IMG_DIR" /mnt

for i in $(seq 1 "$COUNT"); do
  img="$IMG_DIR/disk$i.img"
  mnt="/mnt/disk$i"

  install -d -m 0755 "$mnt"

  # De-dup any existing /etc/fstab lines for this img or mountpoint
  if [ -f /etc/fstab ]; then
    awk -v img="$img" -v mnt="$mnt" '$1==img || $2==mnt {next} {print}' /etc/fstab > /tmp/fstab.new || true
    cat /tmp/fstab.new > /etc/fstab || true
  fi

  # Create sparse image if missing
  if [ ! -f "$img" ]; then
    truncate -s "$SIZE" "$img"
  fi

  # Ensure ext4 filesystem
  type=$(blkid -s TYPE -o value "$img" 2>/dev/null || true)
  if [ "$type" != "ext4" ]; then
    mkfs.ext4 -F "$img"
    e2label "$img" "nifi-disk$i" || true
  fi

  # Stable fstab entry for persistence
  if ! grep -qE "^[[:space:]]*$(printf '%q' "$img")[[:space:]]+$(printf '%q' "$mnt")[[:space:]]+ext4" /etc/fstab; then
    echo "$img $mnt ext4 loop,defaults,nofail,x-systemd.requires-mounts-for=$IMG_DIR 0 2" >> /etc/fstab
  fi

  # If not mounted, detach stale loop devices for this image and mount via loop
  if ! findmnt -rn --target "$mnt" >/dev/null 2>&1; then
    while read -r dev _; do
      [ -n "${dev:-}" ] || continue
      losetup -d "$dev" || true
    done < <(losetup -j "$img" | awk -F: '{print $1}')
    mount -t ext4 -o loop "$img" "$mnt" || true
  else
    echo "INFO: $mnt already mounted; leaving as-is"
  fi
done

# Ensure all fstab entries are mounted (covers any race/ordering side-effects)
mount -a -v || true

echo
echo "Mounted:"
for i in $(seq 1 "$COUNT"); do
  findmnt -rno TARGET,SOURCE,FSTYPE --target "/mnt/disk$i" || true
done
echo
echo "Loop devices:"
losetup -a | grep "$IMG_DIR" || true
REMOTE
