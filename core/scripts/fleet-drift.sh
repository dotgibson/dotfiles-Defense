#!/usr/bin/env bash
# scripts/fleet-drift.sh
# ──────────────────────────────────────────────────────────────────────────────
# FLEET DRIFT CHECK — is every OS repo carrying the latest Core?
#
# sync-core.sh fans Core out and stamps each OS repo with its provenance:
#   • Unix repos: a root-level `core.lock` with `core_sha=<full sha>` (+ `core_tag`) (B1)
#   • dotfiles-Windows: `nvim/.core-ref` with `commit = <sha>` (+ `tag = <release>`)
#     (it vendors only nvim/ via robocopy, not the whole core/ subtree)
# Those markers answer "which Core do I carry?" offline — but NOTHING compared them
# against each other or against Core's tip, so a repo could silently sit on a stale
# Core for weeks (exactly how dotfiles-MacBook's nvim lockfile drifted). This is that
# missing check: it reads every marker and flags any repo behind (or ahead of) the
# reference Core commit. Exception: dotfiles-Windows vendors only the nvim/ subtree and
# tracks Core's main tip (nvim-sync, not a release tag), so it's judged against nvim/'s
# last change reachable from the reference — not the reference itself. That treats both
# "ahead on main between releases" and "a release that changed no nvim/ files" as current,
# and still flags a genuinely stale nvim/ tree (see _classify_subtree).
#
# It is a REPORTER, not a mutator — it never writes to a repo. Run it locally against
# your checked-out fleet, or in CI (.github/workflows/fleet-drift.yml) which shallow-
# clones the fleet first. Graceful degradation mirrors audit-core.sh: a repo that
# isn't checked out is SKIPPED with a notice (not a failure) unless --strict.
#
# Reference commit (what "current" means), first hit wins:
#   --ref <sha|ref>  →  $CORE_REF_SHA  →  the latest released Core tag  →  origin/main
#                    →  main  →  HEAD
# DEFAULT = the latest released Core tag (newest `vX.Y.Z`), NOT the working tip. Fan-out
# stamps each OS repo with the Core tag it carries (sync-core.sh), so measuring against
# the tag is the apples-to-apples comparison; measuring against tip reported a false
# "BEHIND by N" for every unreleased commit on main (CHANGELOG/auto-tag churn between
# releases). An explicit --ref or $CORE_REF_SHA still wins for ad-hoc comparisons.
#
# Usage:
#   ./scripts/fleet-drift.sh                 # check siblings against the latest Core tag
#   ./scripts/fleet-drift.sh --root ~/src    # fleet lives elsewhere
#   ./scripts/fleet-drift.sh --ref v1.2.0    # compare against a specific tag/commit
#   ./scripts/fleet-drift.sh --strict        # a not-checked-out repo FAILS, not skips
#   ./scripts/fleet-drift.sh --quiet         # suppress the ✓ rows; show only drift + summary
#
# Flags: [--root DIR] [--ref COMMIT-ISH] [--strict] [--quiet] [--color auto|always|never]
#   (--color defaults to auto and honours NO_COLOR, like the sibling gate scripts.)
#
# Exit: 0 = every present repo is current; 1 = drift found; 2 = usage error.
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/scripts/lib/common.sh"

ROOT="$(cd "$HERE/.." && pwd)" # siblings of dotfiles-core by default
REF_ARG="${CORE_REF_SHA:-}"
STRICT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --root)
    ROOT="${2:-}"
    shift 2 || { fail "--root needs a directory"; exit 2; }
    ;;
  --ref)
    REF_ARG="${2:-}"
    shift 2 || { fail "--ref needs a commit-ish"; exit 2; }
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

[[ -d "$ROOT" ]] || { fail "fleet root not found: $ROOT"; exit 2; }

# Resolve the reference Core commit to a full sha (first that exists wins).
_resolve_ref() {
  local r s
  for r in "$@"; do
    [[ -n "$r" ]] || continue
    if s="$(git -C "$HERE" rev-parse --verify --quiet "${r}^{commit}" 2>/dev/null)"; then
      printf '%s\n' "$s"
      return 0
    fi
  done
  return 1
}

# Latest RELEASE tag — the default reference. `git describe` walks back from a starting
# point to the nearest reachable strict-SemVer tag (vX.Y.Z, no prerelease/suffix), which
# is exactly "the Core release the fleet should be carrying". The --match glob is a glob,
# not a regex, so its trailing `*` would also match a prerelease like v1.2.3-rc1; --exclude
# '*-*' drops anything with a suffix (same gotcha auto-tag.sh:177-179 documents). Try
# origin/main's history first (CI shallow-clones it), then HEAD's. Empty (no tags yet, or a
# clone too shallow to reach one) → the caller falls back to origin/main/main/HEAD,
# preserving old behaviour.
_latest_release_tag() {
  local start t
  for start in origin/main HEAD; do
    t="$(git -C "$HERE" describe --tags --abbrev=0 \
      --match 'v[0-9]*.[0-9]*.[0-9]*' --exclude '*-*' "$start" 2>/dev/null)" || t=""
    [[ -n "$t" ]] && { printf '%s\n' "$t"; return 0; }
  done
  return 1
}

# DEFAULT reference = the latest released Core tag (when no --ref / $CORE_REF_SHA given),
# then origin/main → main → HEAD. An explicit ref still wins because it is tried first.
_REL_TAG="$([[ -n "$REF_ARG" ]] || _latest_release_tag)"
REF="$(_resolve_ref "$REF_ARG" "$_REL_TAG" origin/main main HEAD)" ||
  { fail "could not resolve a reference Core commit (tried: ${REF_ARG:-} ${_REL_TAG:-} origin/main main HEAD)"; exit 2; }

# The fleet that vendors the full core/ subtree. SINGLE SOURCE: scripts/os-repos.txt
# (same data file sync-core.sh reads), with the inline list as a hard fallback so a
# missing/corrupt file degrades to the last-known fleet instead of checking nothing.
OS_REPOS=()
_OS_REPOS_FILE="$HERE/scripts/os-repos.txt"
if [[ -r "$_OS_REPOS_FILE" ]]; then
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    _line="${_line%%#*}"                       # strip trailing comments
    _line="${_line#"${_line%%[![:space:]]*}"}" # ltrim
    _line="${_line%"${_line##*[![:space:]]}"}" # rtrim
    [[ -n "$_line" ]] && OS_REPOS+=("$_line")
  done <"$_OS_REPOS_FILE"
fi
((${#OS_REPOS[@]})) || OS_REPOS=(
  dotfiles-MacBook dotfiles-Alpine dotfiles-Arch dotfiles-Defense
  dotfiles-Fedora dotfiles-Gentoo dotfiles-Kali dotfiles-openSUSE
)

# Read a `key=value` (core.lock) or `key = value` (.core-ref) value from a file.
_read_kv() { # _read_kv <file> <key>
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//p" "$1" 2>/dev/null | head -n1
}

# Classify a recorded sha against REF, echoing a human status. PURE: it only reads
# (no shared-state writes) because callers run it in a command substitution — a
# subshell, where any DRIFT=1 would be lost. The caller decides drift from the
# returned status string (status == "current" is the only non-drift verdict).
DRIFT=0
_classify() { # _classify <recorded-sha>
  local rec="$1" ahead behind
  if [[ -z "$rec" ]]; then echo "no provenance recorded"; return; fi
  if [[ "$rec" == "$REF" ]]; then echo "current"; return; fi
  # Try to quantify; objects may be absent (shallow clone) → fall back to "differs".
  behind="$(git -C "$HERE" rev-list --count "${rec}..${REF}" 2>/dev/null)" || behind=""
  ahead="$(git -C "$HERE" rev-list --count "${REF}..${rec}" 2>/dev/null)" || ahead=""
  if [[ -n "$behind" && -n "$ahead" ]]; then
    if [[ "$behind" != 0 && "$ahead" == 0 ]]; then echo "BEHIND by $behind commit(s)"; return; fi
    if [[ "$ahead" != 0 && "$behind" == 0 ]]; then echo "AHEAD by $ahead commit(s)"; return; fi
    echo "DIVERGED (behind $behind, ahead $ahead)"; return
  fi
  echo "DIFFERS (sha not in local history)"
}

# Classify a repo that vendors only a SUBTREE of Core (dotfiles-Windows: nvim/) and tracks
# main's TIP, not a release tag. Its nvim-sync bot re-stamps the marker ONLY when the subtree
# actually changes — it reverts the marker's timestamp-only churn otherwise (nvim-sync.yml) —
# so the recorded commit is the last Core commit to touch that subtree. That can be an
# ANCESTOR of REF (a release that changed nothing under the subtree leaves the marker behind
# while the vendored tree is byte-identical) or a DESCENDANT (an unreleased subtree commit
# pulled from main between releases). In BOTH cases the vendored tree is current iff the
# recorded commit already contains REF's latest change to that subtree — so compare against
# that commit (`git rev-list -1 REF -- <path>`), not REF itself. Measuring against raw REF
# reported a false BEHIND/AHEAD for exactly these two legitimate states.
_classify_subtree() { # _classify_subtree <recorded-sha> <subtree-path>
  local rec="$1" path="$2" subref
  [[ -z "$rec" ]] && { echo "no provenance recorded"; return; }
  subref="$(git -C "$HERE" rev-list -1 "$REF" -- "$path" 2>/dev/null)" || subref=""
  # Can't resolve the subtree's history (shallow clone, or path absent) → don't guess; fall
  # back to the commit-level verdict.
  [[ -n "$subref" ]] || { _classify "$rec"; return; }
  # rec carries REF's latest <path> change (or a newer one) ⇒ the vendored tree is current.
  # --is-ancestor is reflexive (rec == subref counts). A non-zero exit — not an ancestor, or
  # rec absent from local history — means the vendored subtree genuinely lags; report the
  # real commit-level distance via _classify.
  if git -C "$HERE" merge-base --is-ancestor "$subref" "$rec" 2>/dev/null; then
    echo "current ($path up to date)"
  else
    _classify "$rec"
  fi
}

hdr "Fleet drift vs Core ${REF:0:12} ($(git -C "$HERE" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?'))"
printf '%-22s %-14s %s\n' "REPO" "RECORDED" "STATUS"
printf '%-22s %-14s %s\n' "----" "--------" "------"

_check_repo() { # _check_repo <repo-dir-name> <marker-relative-path> <sha-key> [tag-key] [subtree-path]
  local name="$1" marker="$2" key="$3" tagkey="${4:-core_tag}" track_path="${5:-}" dir="$ROOT/$1" file rec status tag shown
  if [[ ! -d "$dir" ]]; then
    if ((STRICT)); then fail "$(printf '%-22s %-14s %s' "$name" "-" "NOT CHECKED OUT")"
    else skip "$(printf '%-22s %-14s %s' "$name" "-" "not checked out")"; fi
    return
  fi
  file="$dir/$marker"
  if [[ ! -r "$file" ]]; then
    fail "$(printf '%-22s %-14s %s' "$name" "-" "missing $marker")"; DRIFT=1; return
  fi
  rec="$(_read_kv "$file" "$key")"
  # Prefer the human-readable release tag in the RECORDED column when the marker
  # carries one — core.lock's `core_tag` for the Unix repos, nvim/.core-ref's `tag`
  # for Windows (the tag-key arg differs per marker). Fall back to the short sha when
  # there's no tag (e.g. Core carries none yet). The drift VERDICT stays sha-based via
  # _classify — the tag is display only.
  tag="$(_read_kv "$file" "$tagkey")"
  shown="${tag:-${rec:0:12}}"
  # A subtree-tracking repo (track_path set: dotfiles-Windows vendors only nvim/) is judged
  # against that subtree's last change reachable from REF, not REF itself — see
  # _classify_subtree. Everything else is pinned to the release tag by `make sync`.
  if [[ -n "$track_path" ]]; then
    status="$(_classify_subtree "$rec" "$track_path")"
  else
    status="$(_classify "$rec")"
  fi
  if [[ "$status" == current* ]]; then
    pass "$(printf '%-22s %-14s %s' "$name" "$shown" "$status")"
  else
    fail "$(printf '%-22s %-14s %s' "$name" "$shown" "$status")"
    DRIFT=1
  fi
}

for _r in "${OS_REPOS[@]}"; do
  _check_repo "$_r" "core.lock" "core_sha"
done
# Windows is the outlier: no core/ subtree, only nvim/ mirrored — its provenance
# lives in nvim/.core-ref (sha under `commit`, release name under `tag`). Include it
# so the dashboard covers the whole fleet, labelled by tag like the Unix repos. Unlike the
# Unix repos (pinned to a release tag by `make sync`), it vendors only the nvim/ subtree and
# tracks main's tip via the nvim-sync bot, so pass the subtree path `nvim`: it's judged
# against nvim/'s last change reachable from REF (see _classify_subtree), which treats both
# "ahead on main" and "release didn't touch nvim/" as current, and still fails a genuinely
# stale nvim/ tree.
_check_repo "dotfiles-Windows" "nvim/.core-ref" "commit" "tag" "nvim"

echo
if ((DRIFT)); then
  fail "fleet drift detected — run 'make sync' (and nvim-sync.ps1 for Windows) to bring repos to ${REF:0:12}"
  exit 1
fi
pass "every checked-out repo is on Core ${REF:0:12}"
exit 0
