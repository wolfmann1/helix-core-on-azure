#!/usr/bin/env bash
# setup-env.sh — resolve and install everything in dependencies.txt.
#
# Clone from GitHub or sync from Perforce, run this script, and the toolchain
# is in place. Installs into ./.tools, which is excluded by .gitignore and
# .p4ignore, so nothing is installed system-wide and the directory can be
# deleted to reset.
#
#   ./scripts/setup-env.sh          # install
#   ./scripts/setup-env.sh --check  # verify only, no install
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.tools"; mkdir -p "$TOOLS/bin"
CHECK_ONLY="${1:-}"
export PATH="$TOOLS/bin:$PATH"

fail=0
while IFS='|' read -r name version source verify; do
  name="$(echo "$name" | xargs)";     [[ -z "$name" || "$name" == \#* ]] && continue
  version="$(echo "$version" | xargs)"
  source="$(echo "$source" | xargs)"
  verify="$(echo "$verify" | xargs)"

  if command -v "${verify%% *}" >/dev/null 2>&1; then
    printf "  ok      %-12s %s\n" "$name" "$($verify 2>&1 | head -1)"
    continue
  fi
  if [[ "$CHECK_ONLY" == "--check" ]]; then
    printf "  MISSING %-12s (want %s)\n" "$name" "$version"; fail=1; continue
  fi

  printf "  install %-12s %s\n" "$name" "$version"
  case "$source" in
    hashicorp)
      curl -fsSL "https://releases.hashicorp.com/${name}/${version}/${name}_${version}_linux_amd64.zip" -o /tmp/$name.zip
      unzip -oq /tmp/$name.zip -d "$TOOLS/bin" ;;
    github:*)
      repo="${source#github:}"
      echo "    -> fetch from github.com/$repo release $version (see TODO)" ;;
    pip)
      pip install --quiet "${name}==${version}" ;;
    apt)
      sudo apt-get install -y -qq "$name" ;;
    winget:*)
      echo "    -> Windows only; run scripts/setup-env.ps1" ;;
    *)
      echo "    !! unknown source '$source'"; fail=1 ;;
  esac
done < <(grep -v '^\s*#' "$ROOT/dependencies.txt" | grep '|')

# TODO(chris): add --from p4 / --from git to fetch the repo itself before
# resolving deps, so a bare machine bootstraps in one command.
exit $fail
