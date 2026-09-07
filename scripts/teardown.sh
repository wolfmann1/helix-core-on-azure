#!/usr/bin/env bash
# teardown.sh <env> — destroy an on-demand environment after evidence capture.
# Pairs with the on-demand strategy in local/hyperv/README.md.
set -euo pipefail
ENVIRONMENT="${1:?environment required}"
cd "$(dirname "$0")/.."
echo "About to DESTROY envs/$ENVIRONMENT. Capture your evidence first:"
echo "  - alert rules firing        - failover drill timings"
echo "  - plan/apply output          - restore verification result"
read -rp "Type the environment name to confirm: " confirm
[[ "$confirm" == "$ENVIRONMENT" ]] || { echo "aborted"; exit 1; }
terraform -chdir="envs/$ENVIRONMENT" destroy
