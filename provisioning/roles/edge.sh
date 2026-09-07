#!/usr/bin/env bash
# edge.sh — configure this node as an edge server.
# An edge holds its own metadata, which is why it gets its own p4db volume
# rather than sharing the commit server's.
set -euo pipefail
: "${SDP_INSTANCE:=1}" "${COMMIT_HOST:?--commit-host required for edge}"
echo "[edge] instance $SDP_INSTANCE targeting commit $COMMIT_HOST"
# TODO(chris): p4 server -i with Services: edge-server, then p4 configure set
# for the edge's serverid, then seed from a commit checkpoint.
