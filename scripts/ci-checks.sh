#!/usr/bin/env bash
# ci-checks.sh <env> — the checks the pipeline runs before a plan.
# Kept in a script rather than inline workflow YAML so the GitLab pipeline
# planned for a later iteration can reuse it unchanged.
set -euo pipefail
ENVIRONMENT="${1:?environment required}"
FIX="${2:-}"
cd "$(dirname "$0")/.."

# terraform fmt parses before it formats, so a syntax error surfaces here
# rather than at validate. Pass --fix as the second argument to rewrite files.
echo "::group::fmt"
if [[ "$FIX" == "--fix" ]]; then terraform fmt -recursive; else terraform fmt -check -recursive; fi
echo "::endgroup::"
echo "::group::init";     terraform -chdir="envs/$ENVIRONMENT" init -backend=false; echo "::endgroup::"
echo "::group::validate"; terraform -chdir="envs/$ENVIRONMENT" validate;  echo "::endgroup::"
echo "::group::tflint";   tflint --recursive --config="$PWD/.tflint.hcl"; echo "::endgroup::"
echo "::group::checkov";  checkov -d . --framework terraform --quiet --compact --soft-fail-on LOW; echo "::endgroup::"
