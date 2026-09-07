#!/usr/bin/env bash
# standby.sh — cross-region standby replica running journalcopy.
# Its replication lag is collected by modules/observability, which is what
# makes the RPO a measured value rather than an estimate.
set -euo pipefail
: "${COMMIT_HOST:?--commit-host required}" "${SDP_INSTANCE:=1}"
echo "[standby] targeting $COMMIT_HOST"
# TODO(chris): p4 server -i with Services: standby, ServerID set, then
# seed from checkpoint, then start p4 journalcopy + p4 pull -L.
# The observability module alerts on the lag this produces.
