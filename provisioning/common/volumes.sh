#!/usr/bin/env bash
# volumes.sh <role> — mount the Perforce volumes and create the SDP symlinks.
#
# Volume layout (see ARCHITECTURE.md for the reasoning):
#   p4db          metadata, db.* files
#   p4db2         second metadata volume, when split_metadata is true
#   p4logs        journal and structured logs
#   p4depots      versioned archive files
#   p4            SDP root, when separate_sdp_volumes is true
#   p4ckps        checkpoints, when separate_sdp_volumes is true
#   p4serverlocks tmpfs in RAM, not a disk
#
# Why the volumes are split:
#   p4logs full -> the journal cannot be written -> p4d stops.
#   p4db full   -> recovery may require a checkpoint restore.
# Sharing them means depot or log growth can cause an outage on metadata.
#
# SDP expects the hx* names. This script mounts the p4* names and symlinks the
# hx* paths onto them, so SDP tooling runs unmodified.
set -euo pipefail
ROLE="${1:?role required}"
SERVERLOCKS_MB="${SERVERLOCKS_MB:-1024}"

mount_one() {  # mount_one <label> <mountpoint>
  local label="$1" mp="$2" dev
  dev="$(blkid -L "$label" 2>/dev/null || true)"
  if [[ -z "$dev" ]]; then
    echo "[volumes] no device labelled $label — not attached for this role"
    return 0
  fi
  mkdir -p "$mp"
  grep -q "LABEL=$label " /etc/fstab || \
    echo "LABEL=$label $mp xfs defaults,noatime,nofail 0 2" >> /etc/fstab
  mountpoint -q "$mp" || mount "$mp"
  echo "[volumes] $label -> $mp"
}

link() {  # link <target> <linkname>; skips if target is missing
  [[ -d "$1" ]] || return 0
  ln -sfn "$1" "$2"
  echo "[volumes] symlink $2 -> $1"
}

case "$ROLE" in
  commit|edge|standby)
    mount_one p4db     /p4db
    mount_one p4db2    /p4db2
    mount_one p4logs   /p4logs
    mount_one p4depots /p4depots
    mount_one p4       /p4
    mount_one p4ckps   /p4ckps

    # When /p4 and /p4ckps have no volume of their own they live on p4depots,
    # which is where SDP places them by default.
    [[ -d /p4     ]] || mkdir -p /p4depots/p4     && link /p4depots/p4     /p4
    [[ -d /p4ckps ]] || mkdir -p /p4depots/p4ckps && link /p4depots/p4ckps /p4ckps

    # server.locks in RAM. SDP recommends this; it is a tmpfs, not a disk.
    if [[ "$SERVERLOCKS_MB" -gt 0 ]]; then
      mkdir -p /p4serverlocks
      grep -q " /p4serverlocks " /etc/fstab || \
        echo "tmpfs /p4serverlocks tmpfs defaults,size=${SERVERLOCKS_MB}m,mode=0700 0 0" >> /etc/fstab
      mountpoint -q /p4serverlocks || mount /p4serverlocks
      echo "[volumes] tmpfs ${SERVERLOCKS_MB}M -> /p4serverlocks"
    fi

    # SDP names. /hxmetadata is the single-volume convention; /hxmetadata1 and
    # /hxmetadata2 are used when metadata is split across two volumes.
    link /p4db          /hxmetadata
    link /p4db          /hxmetadata1
    link /p4db2         /hxmetadata2
    link /p4logs        /hxlogs
    link /p4depots      /hxdepots
    link /p4ckps        /hxcheckpoints
    link /p4serverlocks /hxserverlocks
    ;;

  proxy)
    # A proxy caches file content only and holds no metadata, so it gets a
    # single cache volume.
    mount_one p4depots /p4depots
    link /p4depots /hxdepots
    ;;

  broker|swarm|p4search)
    echo "[volumes] role=$ROLE holds no Perforce data volumes"
    ;;
esac
