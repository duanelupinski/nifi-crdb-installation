#!/usr/bin/env bash
set -Eeuo pipefail

# Requires DISKS to be defined (array of: "<device> <mountpoint> <label>"), i.e.
# DISKS=(
#   "/dev/nvme2n1 /mnt/flowfile-repo nifi_flowfile"
#   "/dev/nvme3n1 /mnt/cont-repo1   nifi_content1"
#   "/dev/nvme4n1 /mnt/cont-repo2   nifi_content2"
#   "/dev/nvme5n1 /mnt/cont-repo3   nifi_content3"
#   "/dev/nvme1n1 /mnt/prov-repo1   nifi_prov1"
#   "/dev/nvme6n1 /mnt/prov-repo2   nifi_prov2"
# )

log(){ echo "[$(date +%H:%M:%S)] $*"; }

wait_for_part() {
  local part="$1" tries=40
  for _ in $(seq 1 $tries); do
    [ -b "$part" ] && return 0
    sudo udevadm settle || true
    sleep 0.25
  done
  return 1
}

get_type() {
  sudo blkid -p -c /dev/null -s TYPE -o value "$1" 2>/dev/null || true
}

get_uuid() {
  local part="$1" tries=40
  local u=""
  for _ in $(seq 1 $tries); do
    u=$(sudo blkid -p -c /dev/null -s UUID -o value "$part" 2>/dev/null || true)
    [ -n "$u" ] && { echo "$u"; return 0; }
    sleep 0.25
  done
  echo ""
  return 1
}

fstab_upsert() {
  local uuid="$1" mnt="$2"
  local line="UUID=$uuid $mnt ext4 noatime,nodiratime,nofail,x-systemd.device-timeout=2min 0 2"
  # Remove any existing line for this mountpoint
  sudo sed -i -E "\|[[:space:]]$mnt[[:space:]]|d" /etc/fstab
  echo "$line" | sudo tee -a /etc/fstab >/dev/null
}

prep_disk() {
  local dev="$1" mnt="$2" label="$3"
  local part="${dev}p1"

  log "Preparing $dev -> $mnt (label: $label)"

  [ -b "$dev" ] || { echo "!! Block device not found: $dev"; return 1; }

  # Create GPT + single partition if missing
  if [ ! -b "$part" ]; then
    sudo parted -s "$dev" mklabel gpt
    sudo parted -s "$dev" mkpart primary ext4 0% 100%
    sudo partprobe "$dev" || true
    sudo udevadm settle || true
  fi

  # Ensure partition node visible
  if ! wait_for_part "$part"; then
    echo "!! Partition node not appearing: $part"
    return 1
  fi

  # Create filesystem if missing
  if [ -z "$(get_type "$part")" ]; then
    sudo mkfs.ext4 -F -L "$label" "$part"
    sync
    sudo udevadm settle || true
  fi

  # Mountpoint + UUID
  sudo mkdir -p "$mnt"
  local uuid=""
  uuid=$(get_uuid "$part")
  if [ -z "$uuid" ]; then
    echo "!! Could not read UUID for $part (skipping fstab/mount)"
    return 1
  fi

  # /etc/fstab upsert + mount
  fstab_upsert "$uuid" "$mnt"
  mountpoint -q "$mnt" || sudo mount -U "$uuid" "$mnt"

  findmnt -no TARGET,SOURCE,FSTYPE,OPTIONS "$mnt" || echo "!! Not mounted: $mnt"
}

main() {
  local ok=0 fail=0
  for entry in "${DISKS[@]}"; do
    # shellcheck disable=SC2086
    if prep_disk $entry; then ok=$((ok+1)); else fail=$((fail+1)); fi
  done

  echo
  echo "=== Summary: ok=$ok fail=$fail ==="
  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
  echo
  echo "fstab entries for /mnt repos:"
  grep -E '/mnt/(flowfile|cont-repo|prov-repo)' /etc/fstab || true

  [ "$fail" -eq 0 ]
}
main "$@"
