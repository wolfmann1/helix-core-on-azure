#!/usr/bin/env bash
# ci-checks.sh <env> — everything the pipeline runs before a plan.
# Deliberately a script rather than steps inline in workflow YAML, so the
# GitLab pipeline planned for a later iteration reuses it verbatim.
set -euo pipefail
ENVIRONMENT="${1:?environment required}"
cd "$(dirname "$0")/.."

echo "::group::fmt";      terraform fmt -check -recursive;                echo "::endgroup::"
echo "::group::init";     terraform -chdir="envs/$ENVIRONMENT" init -backend=false; echo "::endgroup::"
echo "::group::validate"; terraform -chdir="envs/$ENVIRONMENT" validate;  echo "::endgroup::"
echo "::group::tflint";   tflint --recursive --config="$PWD/.tflint.hcl"; echo "::endgroup::"
echo "::group::checkov";  checkov -d . --framework terraform --quiet --compact --soft-fail-on LOW; echo "::endgroup::"
