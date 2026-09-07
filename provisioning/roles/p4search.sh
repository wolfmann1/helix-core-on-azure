#!/usr/bin/env bash
# p4search.sh — P4 Search, which fronts Elasticsearch.
#
# Sizing: Perforce states 4 vCPU and 8 GB RAM per component for a small site.
# That exceeds dev and stage, so this role is disabled by default.
set -euo pipefail
: "${COMMIT_HOST:?--commit-host required}"
echo "[p4search] java present: $(java -version 2>&1 | head -1)"
# TODO(chris): install Elasticsearch, then the P4 Search service, then
# register the search user in the protections table.
