#!/usr/bin/env bash
# volumes.sh <role> — mount and label the three-volume split.
#
# Why the volumes are split:
#   p4logs full -> the journal cannot be written -> p4d stops.
#   p4db full   -> recovery may require a checkpoint restore.
# Sharing them means depot or log growth can cause an outage on metadata.
#
# Stock SDP expects /hxmetadata, /hxlogs, /hxdepots. We mount our names and
# symlink the SDP paths onto them, so SDP tooling keeps working unmodified.
set -euo pipefail
ROLE="${1:?role required}"

mount_one() {  # mount_one <label> <mountpoint>
  local label="$1" mp="$2" dev
  dev="$(blkid -L "$label" 2>/dev/null || true)"
  if [[ -z "$dev" ]]; then
    echo "[volumes] no device labelled $label — skipping (expected on $ROLE?)"
    return 0
  fi
  mkdir -p "$mp"
  grep -q "LABEL=$label" /etc/fstab || \
    echo "LABEL=$label $mp xfs defaults,noatime,nofail 0 2" >> /etc/fstab
  mountpoint -q "$mp" || mount "$mp"
  echo "[volumes] $label -> $mp"
}

case "$ROLE" in
  commit|edge|standby)
    mount_one p4db     /p4db
    mount_one p4logs   /p4logs
    mount_one p4depots /p4depots
    ln -sfn /p4db     /hxmetadata
    ln -sfn /p4logs   /hxlogs
    ln -sfn /p4depots /hxdepots
    ;;
  proxy)
    # A proxy caches file content only and holds no metadata, so it gets a
    # single cache volume.
    mount_one p4depots /p4depots
    ln -sfn /p4depots /hxdepots
    ;;
  broker|swarm|p4search)
    echo "[volumes] role=$ROLE needs no Perforce data volumes"
    ;;
esac
