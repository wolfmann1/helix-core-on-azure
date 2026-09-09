#!/usr/bin/env bash
# setup-env.sh — install the pinned toolchain listed in dependencies.txt.
#
# Clone from GitHub or sync from Perforce, run this script, and the toolchain
# is in place. Installs into ./.tools/bin, which is excluded by .gitignore and
# .p4ignore, so nothing is installed system-wide and the directory can be
# deleted to reset.
#
#   ./scripts/setup-env.sh          # install
#   ./scripts/setup-env.sh --check  # report what is missing, install nothing
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.tools/bin"; mkdir -p "$TOOLS"
CHECK_ONLY="${1:-}"
export PATH="$TOOLS:$PATH"

# Asset filenames are tool-specific, so the recipes live here rather than in
# dependencies.txt.
download() {  # download <name> <version>
  local name="$1" ver="$2" url="" tmp
  case "$name" in
    terraform) url="https://releases.hashicorp.com/terraform/${ver}/terraform_${ver}_linux_amd64.zip" ;;
    tflint)    url="https://github.com/terraform-linters/tflint/releases/download/v${ver}/tflint_linux_amd64.zip" ;;
    gh)        url="https://github.com/cli/cli/releases/download/v${ver}/gh_${ver}_linux_amd64.tar.gz" ;;
    jq)        url="https://github.com/jqlang/jq/releases/download/jq-${ver}/jq-linux-amd64" ;;
    *)         echo "    no download recipe for $name" >&2; return 1 ;;
  esac

  tmp="$(mktemp -d)"
  if ! curl -fsSL "$url" -o "$tmp/asset"; then
    echo "    download failed: $url" >&2; rm -rf "$tmp"; return 1
  fi
  case "$url" in
    *.zip)    unzip -oq "$tmp/asset" -d "$tmp/x" && find "$tmp/x" -type f -perm -u+x -exec cp {} "$TOOLS/" \; ;;
    *.tar.gz) tar -xzf "$tmp/asset" -C "$tmp" && find "$tmp" -type f -name "$name" -exec cp {} "$TOOLS/" \; ;;
    *)        cp "$tmp/asset" "$TOOLS/$name" && chmod +x "$TOOLS/$name" ;;
  esac
  rm -rf "$tmp"
  command -v "$name" >/dev/null 2>&1
}

fail=0
while IFS='|' read -r name version winget_id gh_repo verify; do
  name="$(echo "$name" | xargs)";     [[ -z "$name" || "$name" == \#* ]] && continue
  version="$(echo "$version" | xargs)"
  gh_repo="$(echo "$gh_repo" | xargs)"
  verify="$(echo "$verify" | xargs)"

  if command -v "${verify%% *}" >/dev/null 2>&1; then
    printf "  ok       %-11s %s\n" "$name" "$($verify 2>&1 | head -1)"
    continue
  fi
  if [[ "$CHECK_ONLY" == "--check" ]]; then
    printf "  MISSING  %-11s (want %s)\n" "$name" "$version"; fail=1; continue
  fi

  printf "  install  %-11s %s\n" "$name" "$version"
  case "$name" in
    checkov)
      pip install --quiet "checkov==${version}" 2>/dev/null \
        || python3 -m pip install --quiet "checkov==${version}" 2>/dev/null \
        || { echo "    could not install checkov"; fail=1; }
      ;;
    azure-cli)
      # The vendor script is the supported path on Linux and handles the distro
      # differences; there is no single release binary to pin.
      curl -fsSL https://aka.ms/InstallAzureCLIDeb | sudo bash || { echo "    az install failed"; fail=1; }
      ;;
    *)
      if [[ "$gh_repo" == "-" ]] || ! download "$name" "$version"; then
        echo "    not installed"; fail=1
      fi
      ;;
  esac
done < <(grep -v '^\s*#' "$ROOT/dependencies.txt" | grep '|')

# TODO(chris): add --from git|p4 to fetch the repo itself before resolving
# dependencies, so a bare machine bootstraps in one command.
exit $fail
