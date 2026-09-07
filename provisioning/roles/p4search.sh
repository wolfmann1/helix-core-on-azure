#!/usr/bin/env bash
# p4search.sh — P4 Search, which fronts Elasticsearch.
#
# Sizing note: Perforce's own floor for a small site is 4 vCPU and 8 GB RAM
# PER COMPONENT. That fights the minimum-footprint goal, which is why this
# role is disabled in dev and stage and opt-in everywhere.
set -euo pipefail
: "${COMMIT_HOST:?--commit-host required}"
echo "[p4search] java present: $(java -version 2>&1 | head -1)"
# TODO(chris): install Elasticsearch, then the P4 Search service, then
# register the search user in the protections table.
