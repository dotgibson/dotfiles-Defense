#!/usr/bin/env bash
# tests/lint-shell.sh — run the shell lint the way CI runs it, and refuse to be quietly
# different from it.
#
# WHY THIS EXISTS. CI installs a PINNED shellcheck; a developer box has whatever the
# distro ships. Those disagree about which checks exist, so a file can be clean locally
# and red in CI with no visible reason. That is not hypothetical — it cost two red builds
# in one afternoon:
#
#   • SC2329 ("function is never invoked") does not exist in 0.9.0 at all, so a stub the
#     local run considered fine failed the gate.
#   • The fix then had to be verified twice, because "clean here" said nothing about there.
#
# The version and the flags are both READ FROM THE VENDORED CORE rather than restated, so
# this script cannot drift from the gate it is imitating:
#   • core/scripts/tool-versions.env         → SHELLCHECK_VERSION
#   • core/.github/workflows/lint-call.yml   → SHELLCHECK_OPTS
#
# Engine selection, in order:
#   1. a local shellcheck whose version MATCHES the pin — use it, it is identical
#   2. docker — run the pinned image, which is genuinely what CI runs
#   3. a mismatched local shellcheck — run it, but say loudly that the result is advisory
#
# Usage: tests/lint-shell.sh [--plan] [file ...]
#          default   every repo-owned *.sh, exactly the set CI lints
#          --plan    resolve and print the pin, flags and engine, then stop WITHOUT
#                    linting. The test suite uses this: it can assert the resolution is
#                    correct without pulling a docker image, which would put a network
#                    dependency inside a required check.
set -uo pipefail

plan_only=0
if [ "${1:-}" = "--plan" ]; then
  plan_only=1
  shift
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

versions_env="core/scripts/tool-versions.env"
lint_wf="core/.github/workflows/lint-call.yml"

pinned=""
[ -r "$versions_env" ] && pinned="$(sed -n 's/^SHELLCHECK_VERSION=//p' "$versions_env" | tr -d '"' | head -n1)"
if [ -z "$pinned" ]; then
  echo "warn: could not read SHELLCHECK_VERSION from $versions_env — is the core/ subtree present?" >&2
fi

# The gate's exclusions. Read, not restated: if Core changes them, this follows.
opts=""
[ -r "$lint_wf" ] && opts="$(grep -m1 'SHELLCHECK_OPTS:' "$lint_wf" | sed 's/.*SHELLCHECK_OPTS: *//; s/^"//; s/"$//')"
[ -n "$opts" ] || opts="-e SC1090 -e SC1091 -e SC2015 -e SC2088"

# Same file set as the gate: repo-owned shell only, never the vendored subtree.
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  mapfile -t files < <(git ls-files '*.sh' ':!:core/**')
fi
if [ "${#files[@]}" -eq 0 ]; then
  echo "no repo-owned .sh files"
  exit 0
fi

local_ver=""
command -v shellcheck >/dev/null 2>&1 &&
  local_ver="$(shellcheck --version 2>/dev/null | sed -n 's/^version: //p')"

printf 'pinned by CI : %s\n' "${pinned:-unknown}"
printf 'local        : %s\n' "${local_ver:-not installed}"
printf 'flags        : %s\n' "$opts"
printf 'files        : %s\n\n' "${#files[@]}"

# Resolve the engine first, so --plan can report it without running anything.
if [ -n "$local_ver" ] && [ "$local_ver" = "$pinned" ]; then
  engine="local shellcheck (matches the pin)"
elif command -v docker >/dev/null 2>&1 && [ -n "$pinned" ]; then
  engine="docker koalaman/shellcheck:v${pinned} (what CI actually runs)"
elif [ -n "$local_ver" ]; then
  engine="local shellcheck ${local_ver} — DIFFERS from the pin, result is advisory"
else
  engine="none available"
fi
echo "engine: $engine"

if [ "$plan_only" -eq 1 ]; then
  echo
  echo "(--plan: resolved only, nothing linted)"
  exit 0
fi

# shellcheck disable=SC2086  # $opts is a deliberate, curated flag list — must word-split
if [ -n "$local_ver" ] && [ "$local_ver" = "$pinned" ]; then
  shellcheck $opts "${files[@]}"
  rc=$?
elif command -v docker >/dev/null 2>&1 && [ -n "$pinned" ]; then
  docker run --rm -v "$REPO:/mnt" -w /mnt "koalaman/shellcheck:v${pinned}" $opts "${files[@]}"
  rc=$?
elif [ -n "$local_ver" ]; then
  cat >&2 <<EOF
warn: local shellcheck is ${local_ver}, CI pins ${pinned:-unknown}, and docker is unavailable.
warn: running the local one — a CLEAN result here does NOT mean CI will be green.
warn: newer versions add checks older ones cannot report (SC2329 is one that has bitten
warn: this repo). To match CI exactly, install ${pinned:-the pinned version} or run docker.
EOF
  echo
  shellcheck $opts "${files[@]}"
  rc=$?
else
  echo "error: no shellcheck and no docker — cannot lint" >&2
  exit 2
fi

if [ "$rc" -eq 0 ]; then
  echo
  echo "clean"
fi
exit "$rc"
