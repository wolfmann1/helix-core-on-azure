#!/usr/bin/env bash
# swarm.sh — P4 Code Review (formerly Helix Swarm).
#
# Documented requirements (Perforce docs, 2026.3):
#   * Apache 2.4, prefork MPM only — worker and event are incompatible
#   * PHP 8.2-8.5, NON-THREADED — the P4 PHP API is not thread-safe
#   * Redis is required for cache management
#   * Linux only; no Windows support
#   * Needs a dedicated admin-level P4 user
set -euo pipefail
: "${COMMIT_HOST:?--commit-host required}" "${P4PORT:=1666}"

systemctl enable --now redis-server 2>/dev/null || systemctl enable --now redis 2>/dev/null || true

# TODO(chris): install the P4PHP extension matching the installed PHP minor,
# then run Swarm's configure-swarm.sh with the swarm service user's ticket
# pulled from Key Vault. Do NOT bake the ticket into the image.
echo "[swarm] base packages in place; configure-swarm pending credentials"
