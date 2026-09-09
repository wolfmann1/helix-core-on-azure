#!/usr/bin/env bash
# provision.sh — provider-agnostic node provisioning entry point.
#
# Called identically by:
#   - Azure   : via cloud-init runcmd (see provisioning/cloud-init/)
#   - Hyper-V : via local/hyperv/New-P4Lab.ps1 over SSH after first boot
#   - bare VM : by hand, for testing
#
# Terraform creates infrastructure; these scripts configure it. Nothing here
# should reference Azure concepts, which is what allows the Hyper-V path to
# reuse these scripts unchanged.
#
# Usage:
#   provision.sh --role commit --install-sdp true --p4port 1666 --sdp-instance 1 \
#                --disk-map "p4db=0,p4db2=1,p4logs=2,p4depots=3"
#
# --disk-map names which LUN carries which volume. Terraform passes the same
# map it used when attaching the disks, so the two cannot drift.
#
set -euo pipefail
trap 'echo "[provision] FAILED at line $LINENO: $BASH_COMMAND" >&2' ERR

ROLE=""
INSTALL_SDP="true"
P4PORT="1666"
SDP_INSTANCE="1"
COMMIT_HOST=""
P4_VERSION="latest"
SERVERLOCKS_MB="1024"
DISK_MAP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)         ROLE="$2"; shift 2 ;;
    --install-sdp)  INSTALL_SDP="$2"; shift 2 ;;
    --p4port)       P4PORT="$2"; shift 2 ;;
    --sdp-instance) SDP_INSTANCE="$2"; shift 2 ;;
    --commit-host)  COMMIT_HOST="$2"; shift 2 ;;
    --p4-version)   P4_VERSION="$2"; shift 2 ;;
    --serverlocks-mb) SERVERLOCKS_MB="$2"; shift 2 ;;
    --disk-map)     DISK_MAP="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$ROLE" ]] && { echo "--role is required" >&2; exit 2; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SDP_INSTANCE P4PORT COMMIT_HOST P4_VERSION SERVERLOCKS_MB DISK_MAP

# ---- 1. OS detection -------------------------------------------------------
. /etc/os-release
case "$ID" in
  ubuntu) OS_FAMILY="debian" ;;
  rhel|rocky|almalinux) OS_FAMILY="rhel" ;;
  *) echo "unsupported OS: $ID $VERSION_ID" >&2; exit 1 ;;
esac
export OS_FAMILY OS_ID="$ID" OS_VERSION="$VERSION_ID"

echo "[provision] role=$ROLE os=$ID $VERSION_ID family=$OS_FAMILY sdp=$INSTALL_SDP"

# ---- 2. Base packages ------------------------------------------------------
"$HERE/common/packages.sh" "$ROLE"

# ---- 3. Volume layout ------------------------------------------------------
# p4db / p4db2 -> database (db.*)          : fastest disks
# p4logs       -> journal + structured logs: separate disk, never shared with p4db
# p4depots     -> versioned archive files  : large disk
# p4 / p4ckps  -> SDP root and checkpoints : optional separate volumes
# p4serverlocks-> server.locks              : tmpfs in RAM
"$HERE/common/volumes.sh" "$ROLE"

# ---- 4. SDP (optional, parameterised) --------------------------------------
if [[ "$INSTALL_SDP" == "true" ]]; then
  "$HERE/sdp/install-sdp.sh"
else
  echo "[provision] SDP install skipped by parameter"
fi

# ---- 5. Role configuration -------------------------------------------------
"$HERE/roles/${ROLE}.sh"

echo "[provision] complete: $ROLE"
