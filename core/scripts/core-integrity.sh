#!/usr/bin/env bash
# scripts/core-integrity.sh
# ──────────────────────────────────────────────────────────────────────────────
# CORE INTEGRITY CHECK — is every OS repo's vendored core/ PRISTINE, or was it
# hand-edited?
#
# The rule that bites: core/ is a vendored copy of dotfiles-core and is
# overwritten on the next `make sync`, so a hand-edit there is silent — it works
# until a sync clobbers it, and never reaches the source of truth. The only guard
# was blib_install_core_guard, a LOCAL .git/hooks/pre-commit. But .git/hooks is not
# version-controlled: it does not exist on a fresh clone or in CI, so it protects
# exactly one machine and nothing on the surfaces that matter. This is the durable,
# CI-runnable replacement.
#
# How: a vendored core/ is a content-addressed copy of dotfiles-core's WHOLE tree at
# the commit core.lock pins, so the git tree object of `HEAD:core` in an OS repo must
# byte-equal `<core_sha>^{tree}` in dotfiles-core. Edit any vendored file and that
# tree hash diverges. One rev-parse each side, O(1), no file walk.
#
# This is the INTEGRITY companion to fleet-drift.sh (which checks STALENESS — recorded
# sha vs the latest RELEASED Core tag). They are orthogonal: a repo can be perfectly current AND tampered,
# or pristine BUT behind. Run both.
#
# REPORTER, not mutator — never writes to a repo. Run locally against your checked-out
# fleet, or in CI (.github/workflows/core-integrity.yml) which clones the fleet first.
# Graceful degradation mirrors audit-core.sh / fleet-drift.sh: a repo that isn't
# checked out is SKIPPED with a notice (not a failure) unless --strict.
#
# Usage:
#   ./scripts/core-integrity.sh                 # check siblings of this repo
#   ./scripts/core-integrity.sh --root ~/src    # fleet lives elsewhere
#   ./scripts/core-integrity.sh --self ../dotfiles-Offense   # check just ONE repo (per-repo CI guard)
#   ./scripts/core-integrity.sh --strict        # a not-checked-out repo FAILS, not skips
#   ./scripts/core-integrity.sh --quiet         # suppress the ✓ rows; show only problems + summary
#
# Flags: [--root DIR] [--self REPO-DIR] [--strict] [--quiet] [--color auto|always|never]
#   (--color defaults to auto and honours NO_COLOR, like the sibling gate scripts.)
#
# Exit: 0 = every present repo is pristine; 1 = tamper/unverifiable found; 2 = usage error.
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/scripts/lib/common.sh"
# shellcheck source=scripts/lib/core-lock.sh
source "$HERE/scripts/lib/core-lock.sh"

ROOT="$(cd "$HERE/.." && pwd)" # siblings of dotfiles-core by default
STRICT=0
SELF_DIR="" # --self: check exactly ONE repo (the per-repo PR-time guard)

while [[ $# -gt 0 ]]; do
  case "$1" in
  --root)
    ROOT="${2:-}"
    shift 2 || { fail "--root needs a directory"; exit 2; }
    ;;
  --self)
    SELF_DIR="${2:-}"
    shift 2 || { fail "--self needs a repo directory"; exit 2; }
    ;;
  --strict) STRICT=1; shift ;;
  --quiet) QUIET=1; shift ;;
  --color)
    _core_set_color "${2:-}" || { fail "--color wants auto|always|never"; exit 2; }
    shift 2
    ;;
  -h | --help)
    sed -n '2,/^set -u/p' "${BASH_SOURCE[0]}" | sed '$d;s/^# \{0,1\}//'
    exit 0
    ;;
  *) fail "unknown argument: $1"; exit 2 ;;
  esac
done

# --self <dir> checks exactly ONE repo against its own core.lock (the per-repo
# PR-time guard); otherwise we sweep the whole fleet. Either way the SAME _check_repo
# path runs — --self just narrows ROOT + the target list to that one repo, so the
# comparison logic has a single definition.
if [[ -n "$SELF_DIR" ]]; then
  [[ -d "$SELF_DIR" ]] || { fail "--self repo dir not found: $SELF_DIR"; exit 2; }
  ROOT="$(cd "$SELF_DIR/.." && pwd)"
  OS_REPOS=("$(basename "$SELF_DIR")")
else
  [[ -d "$ROOT" ]] || { fail "fleet root not found: $ROOT"; exit 2; }

  # The fleet that vendors the full core/ subtree. SINGLE SOURCE: scripts/os-repos.txt, read
  # through the ONE parser in lib/common.sh (#669). No inline fallback: an integrity gate
  # that quietly falls back to a hardcoded fleet when the data file is unreadable reports
  # "every repo pristine" about a list nobody chose. Unreadable now stops the run.
  # (dotfiles-Windows's absence is explained once, in scripts/os-repos.txt — it vendors only
  # nvim/, no core/ subtree, so there is no tree to integrity-check here.)
  load_os_repos || {
    fail "$CORE_OS_REPOS_ERR — cannot enumerate the fleet to check"
    exit 2
  }
  OS_REPOS=("${CORE_OS_REPOS[@]}")
fi

# Both helpers now live in scripts/lib/core-lock.sh, sourced above. They moved because
# sync-core.sh needs the SAME comparison to check its own work before it reports success
# (#556) — and a producer whose self-check is a second implementation of the reporter's
# verdict can pass its own assertion and still be reported dirty here.
_read_kv() { # _read_kv <file> <key>
  core_lock_read_kv "$1" "$2"
}

# Classify a repo's vendored core/ against the commit its core.lock pins. PURE: only
# reads (callers run it in a command substitution — a subshell — so any shared-state
# write would be lost). The caller decides the verdict from the returned status string
# ("pristine" is the only clean one). $HERE is Core: the expected tree is resolved in
# Core's object store, which is this gate's vantage point.
_classify() { # _classify <repo-dir> <recorded-sha>
  core_lock_classify "$1" "$2" "$HERE"
}

hdr "Core integrity — vendored core/ vs the commit each core.lock pins"
printf '%-22s %-14s %s\n' "REPO" "LOCKED" "STATUS"
printf '%-22s %-14s %s\n' "----" "------" "------"

PROBLEM=0
_check_repo() { # _check_repo <repo-dir-name>
  local name="$1" dir file rec status tag shown
  # Same resolution as fleet-drift.sh / sync-core.sh: directory name first, then origin's
  # URL, so a pre-rename clone directory can't hide a TAMPERED core/ behind "not checked out".
  dir="$(resolve_repo_dir "$ROOT" "$name")" || dir="$ROOT/$name"
  if [[ ! -d "$dir" ]]; then
    if ((STRICT)); then fail "$(printf '%-22s %-14s %s' "$name" "-" "NOT CHECKED OUT")"; PROBLEM=1
    else skip "$(printf '%-22s %-14s %s' "$name" "-" "not checked out")"; fi
    return
  fi
  file="$dir/core.lock"
  if [[ ! -r "$file" ]]; then
    fail "$(printf '%-22s %-14s %s' "$name" "-" "missing core.lock")"; PROBLEM=1; return
  fi
  rec="$(_read_kv "$file" core_sha)"
  # Display the human-readable tag when core.lock carries one, else the short sha
  # (the verdict itself is tree-based, not sha-based — this column is display only).
  tag="$(_read_kv "$file" core_tag)"
  shown="${tag:-${rec:0:12}}"
  status="$(_classify "$dir" "$rec")"
  if [[ "$status" == "pristine" ]]; then
    pass "$(printf '%-22s %-14s %s' "$name" "$shown" "$status")"
  else
    fail "$(printf '%-22s %-14s %s' "$name" "$shown" "$status")"
    PROBLEM=1
  fi
}

for _r in "${OS_REPOS[@]}"; do
  _check_repo "$_r"
done

echo
if ((PROBLEM)); then
  fail "core integrity FAILED — a vendored core/ no longer matches its core.lock. Fix upstream in dotfiles-core, then 'make sync' (never hand-edit core/)."
  exit 1
fi
pass "every checked-out repo's core/ is pristine"
exit 0
