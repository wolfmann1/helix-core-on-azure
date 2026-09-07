#!/usr/bin/env bash
# broker.sh — P4Broker. Provides controlled failover and read-only
# maintenance windows. Included even though a lab would run without it.
set -euo pipefail
: "${COMMIT_HOST:?--commit-host required}" "${P4PORT:=1666}"
mkdir -p /etc/perforce
cat > /etc/perforce/p4broker.conf << CONF
target = ${COMMIT_HOST}:${P4PORT};
listen = 1666;
directory = /p4logs;
logfile = /p4logs/p4broker.log;
debug-level = server=1;
admin {
  name = "Perforce Admin";
  message = "Server is in a scheduled maintenance window. Read-only commands are permitted.";
}
CONF
echo "[broker] config written"
