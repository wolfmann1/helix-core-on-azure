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
#   provision.sh --role commit --install-sdp true --p4port 1666 --sdp-instance 1
#
set -euo pipefail

ROLE=""
INSTALL_SDP="true"
P4PORT="1666"
SDP_INSTANCE="1"
COMMIT_HOST=""
P4_VERSION="latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)         ROLE="$2"; shift 2 ;;
    --install-sdp)  INSTALL_SDP="$2"; shift 2 ;;
    --p4port)       P4PORT="$2"; shift 2 ;;
    --sdp-instance) SDP_INSTANCE="$2"; shift 2 ;;
    --commit-host)  COMMIT_HOST="$2"; shift 2 ;;
    --p4-version)   P4_VERSION="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$ROLE" ]] && { echo "--role is required" >&2; exit 2; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SDP_INSTANCE P4PORT COMMIT_HOST P4_VERSION

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
# p4db     -> database (db.*)          : fastest disk
# p4logs   -> journal + structured logs: separate disk, must never share with p4db
# p4depots -> versioned archive files  : large disk
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
