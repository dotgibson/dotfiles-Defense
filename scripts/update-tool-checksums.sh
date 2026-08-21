#!/usr/bin/env bash
# scripts/update-tool-checksums.sh
# ──────────────────────────────────────────────────────────────────────────────
# Recompute the pinned SHA-256 of every release ASSET the setup-core-tools composite
# action downloads, and write it back into scripts/tool-versions.env. Run this AFTER
# bumping a *_VERSION there: the action verifies each download against its *_SHA256
# before installing, and scripts/audit-core.sh fails any pinned version whose hash is
# missing or not 64-hex — so a bump is only complete once its checksum is refreshed.
#
# It downloads the exact asset URL the action uses (Linux x86_64), hashes it, and
# rewrites the matching KEY=... line in place (appending it if absent). Review the
# resulting diff and cross-check against upstream's published checksums before
# committing — this is the trust anchor for the gate toolchain.
#
# Usage:  scripts/update-tool-checksums.sh
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="$here/tool-versions.env"
[[ -r "$env_file" ]] || {
  echo "error: $env_file not found" >&2
  exit 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Read a KEY=value from the env file (first match), so we don't have to `source` it.
ver() { sed -n "s/^$1=//p" "$env_file" | head -n1; }

# Replace KEY=... in place (portable across GNU and BSD sed via the .bak suffix), or
# append the line if the key isn't present yet.
set_key() {
  local key="$1" val="$2"
  if grep -qE "^${key}=" "$env_file"; then
    sed -i.bak "s|^${key}=.*|${key}=${val}|" "$env_file"
    rm -f "$env_file.bak"
  else
    printf '%s=%s\n' "$key" "$val" >>"$env_file"
  fi
}

# Download an asset and print its SHA-256.
sha_of() {
  local url="$1" out="$tmp/asset"
  curl -fsSL -o "$out" "$url"
  # sha256sum is GNU coreutils; macOS/BSD ships `shasum -a 256` instead.
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$out" | cut -d' ' -f1
  else
    shasum -a 256 "$out" | cut -d' ' -f1
  fi
}

# <env-prefix>|<asset URL built from that tool's pinned version>
# Keep this list in lockstep with the install steps in
# .github/actions/setup-core-tools/action.yml.
assets=(
  "SHELLCHECK|https://github.com/koalaman/shellcheck/releases/download/v$(ver SHELLCHECK_VERSION)/shellcheck-v$(ver SHELLCHECK_VERSION).linux.x86_64.tar.xz"
  "ACTIONLINT|https://github.com/rhysd/actionlint/releases/download/v$(ver ACTIONLINT_VERSION)/actionlint_$(ver ACTIONLINT_VERSION)_linux_amd64.tar.gz"
  "GITLEAKS|https://github.com/gitleaks/gitleaks/releases/download/v$(ver GITLEAKS_VERSION)/gitleaks_$(ver GITLEAKS_VERSION)_linux_x64.tar.gz"
  "NVIM|https://github.com/neovim/neovim/releases/download/v$(ver NVIM_VERSION)/nvim-linux-x86_64.tar.gz"
  "SHFMT|https://github.com/mvdan/sh/releases/download/v$(ver SHFMT_VERSION)/shfmt_v$(ver SHFMT_VERSION)_linux_amd64"
)

for entry in "${assets[@]}"; do
  prefix="${entry%%|*}"
  url="${entry#*|}"
  if [[ -z "$(ver "${prefix}_VERSION")" ]]; then
    echo "skip ${prefix}: no ${prefix}_VERSION pinned" >&2
    continue
  fi
  printf 'fetching %-11s' "$prefix"
  sha="$(sha_of "$url")"
  set_key "${prefix}_SHA256" "$sha"
  printf ' %s\n' "$sha"
done

echo "done — review: git diff -- $env_file"
