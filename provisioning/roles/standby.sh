#!/usr/bin/env bash
# standby.sh — cross-region standby replica running journalcopy.
# This role is the technical spine of the DR audit: it is what turns a
# claimed RPO into a measured one.
set -euo pipefail
: "${COMMIT_HOST:?--commit-host required}" "${SDP_INSTANCE:=1}"
echo "[standby] targeting $COMMIT_HOST"
# TODO(chris): p4 server -i with Services: standby, ServerID set, then
# seed from checkpoint, then start p4 journalcopy + p4 pull -L.
# The observability module alerts on the lag this produces.
