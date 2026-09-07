#!/usr/bin/env bash
# edge.sh — configure this node as an edge server.
# An edge holds its OWN metadata; that is the entire point of an edge and the
# reason it gets a p4db volume of its own rather than sharing commit's.
set -euo pipefail
: "${SDP_INSTANCE:=1}" "${COMMIT_HOST:?--commit-host required for edge}"
echo "[edge] instance $SDP_INSTANCE targeting commit $COMMIT_HOST"
# TODO(chris): p4 server -i with Services: edge-server, then p4 configure set
# for the edge's serverid, then seed from a commit checkpoint.
