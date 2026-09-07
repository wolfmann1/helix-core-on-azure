#!/usr/bin/env bash
# install-sdp.sh — install the Perforce Server Deployment Package.
#
# SDP is optional via --install-sdp false, so a plain p4d can be deployed for
# comparison. Maintaining both paths costs little and makes the differences
# between them explicit.
set -euo pipefail

SDP_URL="${SDP_URL:-https://swarm.workshop.perforce.com/downloads/guest/perforce_software/sdp/sdp.Unix.tgz}"
SDP_INSTANCE="${SDP_INSTANCE:-1}"
STAGE="/hxdepots/sdp"

echo "[sdp] installing instance $SDP_INSTANCE"

id -u perforce >/dev/null 2>&1 || useradd -r -m -s /bin/bash perforce

mkdir -p "$STAGE"
curl -fsSL "$SDP_URL" -o /tmp/sdp.tgz
tar -xzf /tmp/sdp.tgz -C "$STAGE" --strip-components=1

# mkdirs.sh builds the /p4/<instance> tree against the hx* mount points,
# which volumes.sh has already symlinked onto /p4db, /p4logs and /p4depots.
cd "$STAGE/Server/Unix/p4/common/etc/init.d" 2>/dev/null || cd "$STAGE/Server/Unix/setup"
cd "$STAGE/Server/Unix/setup"

# NOTE: mkdirs.cfg wants review before a real run — it carries the P4PORT,
# instance name, and mail settings. TODO(chris): template this from Terraform
# rather than editing in place, so the environment is reproducible.
[[ -f mkdirs.cfg ]] && cp mkdirs.cfg "mkdirs.${SDP_INSTANCE}.cfg"

./mkdirs.sh "$SDP_INSTANCE"

chown -R perforce:perforce /p4 /p4db /p4logs /p4depots 2>/dev/null || true
echo "[sdp] instance $SDP_INSTANCE created under /p4/$SDP_INSTANCE"
