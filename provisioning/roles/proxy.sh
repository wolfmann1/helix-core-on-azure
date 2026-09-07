#!/usr/bin/env bash
# proxy.sh — configure P4P. Cache only, no metadata.
set -euo pipefail
: "${COMMIT_HOST:?--commit-host required for proxy}" "${P4PORT:=1666}"
mkdir -p /p4depots/cache
cat > /etc/systemd/system/p4p.service << UNIT
[Unit]
Description=Perforce Proxy
After=network-online.target
[Service]
Type=simple
User=perforce
ExecStart=/usr/local/bin/p4p -p 1666 -t ${COMMIT_HOST}:${P4PORT} -r /p4depots/cache -v proxy.monitor.level=3
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
echo "[proxy] unit written; enable once p4p binary is present"
