#!/usr/bin/env bash
# commit.sh — configure this node as the commit (master) server.
set -euo pipefail
: "${SDP_INSTANCE:=1}" "${P4PORT:=1666}"

echo "[commit] configuring instance $SDP_INSTANCE on port $P4PORT"

# Structured logs from first boot. modules/observability reads these; without
# them there is little to review after an incident.
CFG=(
  "serverlog.file.3=/p4logs/commands.csv"
  "serverlog.retain.3=7"
  "serverlog.file.7=/p4logs/errors.csv"
  "serverlog.retain.7=30"
  "serverlog.file.8=/p4logs/audit.csv"
  "serverlog.retain.8=30"
  "monitor=2"
  "server.depot.root=/p4depots"
  "journalPrefix=/p4logs/checkpoints/p4_${SDP_INSTANCE}"
  "db.reorg.disable=1"
)
mkdir -p /p4logs/checkpoints

# TODO(chris): apply with `p4 configure set` once p4d is running and a super
# user ticket is available from Key Vault. Written as data rather than
# executed so the settings are reviewable in a pull request.
printf '%s\n' "${CFG[@]}" > /p4logs/desired-configurables.txt

systemctl enable --now "p4d_${SDP_INSTANCE}" 2>/dev/null || \
  echo "[commit] service unit not present yet (SDP not installed?)"
