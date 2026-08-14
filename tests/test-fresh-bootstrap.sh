#!/usr/bin/env bash
# tests/test-fresh-bootstrap.sh — does this repo bootstrap on a machine that has nothing?
#
# WHY. Every other test runs on a box that is already provisioned, so it cannot see the
# failures that only happen the FIRST time. Those are the expensive ones, and this repo has
# had two:
#   • siemup died on a fresh clone because Docker created the OpenSearch bind-mount
#     root-owned and the container runs as uid 1000. Invisible on any box where the lab had
#     run once, which is every box anyone had tested on.
#   • the k8s rule's dead array paths, and the npm rule's unconfirmed field, both survive
#     precisely because nothing exercises them from cold.
# Running bootstrap in a container with only zsh + git installed is the cheapest way to
# make "fresh machine" a thing CI checks rather than a thing someone remembers to try.
#
# It asserts two DIFFERENT kinds of thing, and the second matters as much as the first:
#   1. the config bootstrap COMPLETES — links land, the loader is written, an interactive
#      zsh loads Core and defines every band-85 verb
#   2. the host-tool probe honestly reports the forensics tools as MISSING. This repo does
#      not install them (the OS-native layer owns that), so a fresh box must say so. A
#      probe that claimed they were present would be the more dangerous bug — it is exactly
#      the class #130 fixed, and a regression there is silent everywhere else.
#
# Ubuntu 24.04 because that is what the fleet's apt column targets. zsh and git are
# installed because bootstrap.sh's contract requires them and cannot supply them; nothing
# else is, on purpose — the point is the empty box.
#
# Needs docker and network (apt, and the plugin clones Core does on first shell launch).
# Skips cleanly without docker so it never breaks the fast suite.
#
# Usage: tests/test-fresh-bootstrap.sh [--keep]
#          --keep   leave the container around for poking at
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="ubuntu:24.04"
NAME="dotfiles-defense-freshboot-$$"
keep=0
[ "${1:-}" = "--keep" ] && keep=1

PASS=0
FAIL=0
ok() {
  printf '  \033[32m✓\033[0m %s\n' "$1"
  PASS=$((PASS + 1))
}
no() {
  printf '  \033[31m✗\033[0m %s\n' "$1" >&2
  [ $# -gt 1 ] && printf '      %s\n' "$2" >&2
  FAIL=$((FAIL + 1))
}

command -v docker >/dev/null 2>&1 || {
  echo "docker not available — skipping the fresh-machine test"
  exit 0
}

cleanup() {
  [ "$keep" -eq 1 ] && {
    echo ":: leaving container $NAME (--keep)"
    return
  }
  docker rm -f "$NAME" >/dev/null 2>&1 || :
}
trap cleanup EXIT

echo ":: booting a bare $IMAGE with only zsh + git"

# The repo is COPIED in, not bind-mounted: bootstrap installs a git pre-commit hook into
# the working tree, and a fresh clone is the honest starting point anyway. .git comes along
# because the core-guard resolves its hooks dir through git.
out="$(
  docker run --name "$NAME" -v "$REPO:/src:ro" "$IMAGE" bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq --no-install-recommends zsh git ca-certificates >/dev/null 2>&1
    cp -a /src /work
    cd /work
    git config --global --add safe.directory /work
    echo "=== BOOTSTRAP ==="
    ./bootstrap.sh; echo "BOOTSTRAP_RC=$?"
    echo "=== SHELL ==="
    zsh -i -c "
      print -r -- \"CORE_LOADED=\$(( \$+functions[core-doctor] ))\"
      print -r -- \"CASES_DIR=\$CASES_DIR\"
      for f in mkcase gocase note siemup siemdown siemlogs; do
        (( \$+functions[\$f] )) || print -r -- \"MISSING_FN=\$f\"
      done
      print -r -- \"VERBS_OK=1\"
    " 2>&1 | tail -12
    echo "=== LINKS ==="
    [ -L "$HOME/.config/zsh/85-defense.zsh" ] && echo "BAND85=linked"
    [ -r "$HOME/.zshrc" ] && grep -q "loader.zsh" "$HOME/.zshrc" && echo "ZSHRC=wired"
  ' 2>&1
)"
rc=$?

printf '%s\n' "$out" | sed 's/^/    | /' | tail -32

echo
echo "assertions:"

case "$out" in *"BOOTSTRAP_RC=0"*) ok "bootstrap exits 0 on a bare machine" ;;
*) no "bootstrap exits 0 on a bare machine" "rc line absent or non-zero (docker rc=$rc)" ;; esac

case "$out" in *"ZSHRC=wired"*) ok "the managed ~/.zshrc loader is written" ;;
*) no "the managed ~/.zshrc loader is written" ;; esac

case "$out" in *"BAND85=linked"*) ok "the band-85 defense stage is symlinked" ;;
*) no "the band-85 defense stage is symlinked" ;; esac

case "$out" in *"CORE_LOADED=1"*) ok "an interactive zsh loads Core (core-doctor defined)" ;;
*) no "an interactive zsh loads Core (core-doctor defined)" ;; esac

case "$out" in *"MISSING_FN="*)
  no "every band-85 verb is defined" "$(printf '%s\n' "$out" | grep -o 'MISSING_FN=[a-z]*' | tr '\n' ' ')" ;;
*) case "$out" in *"VERBS_OK=1"*) ok "every band-85 verb is defined" ;;
  *) no "every band-85 verb is defined" "the shell did not reach the check" ;; esac ;;
esac

case "$out" in *"CASES_DIR=/root/cases"*) ok "CASES_DIR resolves outside the repo" ;;
*) no "CASES_DIR resolves outside the repo" "$(printf '%s\n' "$out" | grep -o 'CASES_DIR=[^ ]*' | head -1)" ;; esac

# The other half: the probe must be HONEST about a box with no forensics tooling. This repo
# installs none of it, so claiming otherwise would be the worse failure.
for t in chainsaw hayabusa velociraptor; do
  case "$out" in *"missing: $t"*) ok "probe honestly reports $t missing" ;;
  *) no "probe honestly reports $t missing" "a bare box must not claim $t is present" ;; esac
done

case "$out" in *"tool(s) missing"*) ok "the probe summarises the missing count" ;;
*) no "the probe summarises the missing count" ;; esac

printf '\nsummary\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
