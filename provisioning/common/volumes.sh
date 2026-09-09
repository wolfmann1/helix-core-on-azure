#!/usr/bin/env bash
# volumes.sh <role> -- format, label, mount the Perforce volumes and create the
# SDP symlinks.
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
# Disks arrive raw. DISK_MAP tells this script which LUN carries which volume,
# for example "p4db=0,p4db2=1,p4logs=2,p4depots=3". Terraform passes the map it
# used when attaching the disks, so the two cannot drift.
#
# Device names such as /dev/sdb are not stable across reboots, so the LUN is
# resolved through a by-path symlink instead. Azure's agent publishes
# /dev/disk/azure/scsi1/lunN; the generic SCSI by-path form is the fallback and
# is what the Hyper-V path uses.
#
# SDP expects the hx* names. This script mounts the p4* names and symlinks the
# hx* paths onto them, so SDP tooling runs unmodified.
set -euo pipefail
ROLE="${1:?role required}"

# Report where a failure happened. set -e otherwise exits silently, which is
# what made the first run look like it simply stopped.
trap 'echo "[volumes] FAILED at line $LINENO: $BASH_COMMAND" >&2' ERR
SERVERLOCKS_MB="${SERVERLOCKS_MB:-1024}"
DISK_MAP="${DISK_MAP:-}"
FSTYPE="${FSTYPE:-xfs}"

resolve_lun() {  # resolve_lun <lun> -> device path on stdout, empty if absent
  local lun="$1" dev=""
  if [[ -e "/dev/disk/azure/scsi1/lun${lun}" ]]; then
    dev="$(readlink -f "/dev/disk/azure/scsi1/lun${lun}")"
  else
    # Generic SCSI: host:bus:target:lun. Data disks sit on target 0.
    dev="$(readlink -f /dev/disk/by-path/*scsi-0:0:0:"${lun}" 2>/dev/null | head -1 || true)"
  fi
  # Always succeed. Returning non-zero here aborts the caller under set -e,
  # because the exit status of dev="$(resolve_lun ...)" is the substitution's.
  # An absent disk is a normal condition, not an error.
  [[ -b "$dev" ]] && echo "$dev"
  return 0
}

prepare_disk() {  # prepare_disk <label> <lun>
  local label="$1" lun="$2" dev existing
  dev="$(resolve_lun "$lun")"
  if [[ -z "$dev" ]]; then
    echo "[volumes] no disk at LUN $lun for $label -- not attached for this role"
    return 0
  fi

  existing="$(blkid -o value -s LABEL "$dev" 2>/dev/null || true)"
  if [[ -z "$existing" ]]; then
    # Whole-disk filesystem, no partition table. Simpler to grow later, and
    # there is no reason to partition a disk dedicated to one volume.
    echo "[volumes] formatting $dev as $FSTYPE, label $label"
    mkfs."$FSTYPE" -f -L "$label" "$dev" >/dev/null
  elif [[ "$existing" != "$label" ]]; then
    # Refuse rather than reformat. A disk carrying someone else's label is more
    # likely a mistake than something to overwrite.
    echo "[volumes] REFUSING $dev: labelled '$existing', expected '$label'" >&2
    return 1
  else
    echo "[volumes] $dev already labelled $label"
  fi
}

mount_one() {  # mount_one <label> <mountpoint>
  local label="$1" mp="$2"
  blkid -L "$label" >/dev/null 2>&1 || { echo "[volumes] no filesystem labelled $label"; return 0; }
  mkdir -p "$mp"
  grep -q "LABEL=$label " /etc/fstab || \
    echo "LABEL=$label $mp $FSTYPE defaults,noatime,nofail 0 2" >> /etc/fstab
  mountpoint -q "$mp" || mount "$mp"
  echo "[volumes] $label -> $mp"
}

link() {  # link <target> <linkname>; skips if target is missing
  [[ -d "$1" ]] || return 0
  ln -sfn "$1" "$2"
  echo "[volumes] symlink $2 -> $1"
}

# Format and label everything named in DISK_MAP before mounting anything.
if [[ -n "$DISK_MAP" ]]; then
  IFS=',' read -ra pairs <<< "$DISK_MAP"
  for pair in "${pairs[@]}"; do
    prepare_disk "${pair%%=*}" "${pair##*=}"
  done
fi

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
    mountpoint -q /p4     || { mkdir -p /p4depots/p4     && link /p4depots/p4     /p4; }
    mountpoint -q /p4ckps || { mkdir -p /p4depots/p4ckps && link /p4depots/p4ckps /p4ckps; }

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

echo "[volumes] final layout:"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS | sed 's/^/  /'
