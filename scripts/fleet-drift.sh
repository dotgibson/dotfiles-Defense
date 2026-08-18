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
# missing check: it reads every marker and flags any repo behind the reference Core commit,
# or ahead of it off Core's released lineage. Exception: dotfiles-Windows vendors only the
# nvim/ subtree and tracks Core's main tip (nvim-sync, not a release tag), so it's judged
# against nvim/'s last change reachable from the reference — not the reference itself.
# That treats both "ahead on main between releases" and "a release that changed no nvim/
# files" as current, and still flags a genuinely stale nvim/ tree (see _classify_subtree).
#
# It is a REPORTER, not a mutator — it never writes to a repo. Run it locally against
# your checked-out fleet, or in CI (.github/workflows/fleet-drift.yml) which shallow-
# clones the fleet first. Graceful degradation mirrors audit-core.sh: a repo that
# isn't checked out is SKIPPED with a notice (not a failure) unless --strict.
#
# Reference commit (what "current" means), first hit wins:
#   --ref <sha|ref>  →  $CORE_REF_SHA  →  the latest released Core tag  →  origin/main
#                    →  main  →  HEAD
# DEFAULT = the latest released Core tag (newest `vX.Y.Z`), NOT the working tip. Measuring
# against tip reported a false "BEHIND by N" for every unreleased commit on main
# (CHANGELOG/auto-tag churn between releases). An explicit --ref or $CORE_REF_SHA still wins
# for ad-hoc comparisons.
#
# AHEAD of that tag is NOT drift (issue #371). `make sync` vendors main's TIP, not a tag —
# sync-core.sh resolves the sha from `git ls-remote <remote> main` and stamps core.lock with
# it — so between releases every repo is legitimately ahead of the newest tag, and the whole
# fleet reported "AHEAD by N" every week a sync landed mid-cycle. Worse, the remediation that
# failure printed ("run make sync") re-vendored the same tip and changed nothing. A repo ahead
# of the tag but still on main's lineage carries UNRELEASED Core, not STALE Core, so it counts
# as current (see $_MAIN_REF and _classify). Ahead but OFF main — a feature branch fanned out
# by mistake — is still drift, as is an ahead-only marker we cannot check because no mainline
# ref resolved. This is the Unix-side counterpart of the same fix _classify_subtree already
# made for dotfiles-Windows.
#
# That row also reports how far BEHIND main's tip it still is, when that distance is non-zero:
# "on main" is true both AT the tip and many commits back from it, so without the number a
# fan-out that stalled mid-cycle renders identically to one that ran this morning. REPORT-ONLY
# — it changes no verdict, no tally and no exit code.
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
# Exit: 0 = every present repo is current (which INCLUDES ahead-of-tag on main — see above;
#       those rows print as `•` and are counted in the closing "carrying UNRELEASED Core"
#       tally); 1 = drift found; 2 = usage error (including a --ref that doesn't resolve).
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/scripts/lib/common.sh"

# A THIRD verdict, between pass and fail. The repo is not drifting — it carries Core NEWER
# than the reference — but it is not pinned to a release either, and flattening those two
# into one ✓ is exactly how "the fleet is running unreleased Core" would stop being visible.
# Tallied as a PASS so the counters still add up, and honoured by --quiet like pass(), so the
# flag keeps meaning "show me only what's wrong"; the footer tally is what survives --quiet.
# Local to this script on purpose: adding it to lib/common.sh would touch every gate script
# that sources it for the benefit of this one caller. skip() is the wrong fit — it tallies
# SKIP and callers render that as "green but partial", which this is not.
note() {
  PASS=$((PASS + 1))
  ((QUIET)) || printf '%s•%s %s\n' "$c_yel" "$c_rst" "$*"
}

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
# An EXPLICIT --ref / $CORE_REF_SHA that doesn't resolve is a usage error, not a cue to
# quietly measure against something else. The fallback ladder exists for the DEFAULT path
# (no tags yet, or a clone too shallow to reach one); letting a caller's dead ref slide into
# it answered a question nobody asked while the banner still named the dead ref — the same
# mislabel this change exists to remove. Checked before _resolve_ref so the message names
# the ref, not the ladder.
if [[ -n "$REF_ARG" ]] && ! git -C "$HERE" rev-parse --verify --quiet "${REF_ARG}^{commit}" >/dev/null 2>&1; then
  fail "--ref '$REF_ARG' does not resolve to a commit in this clone"
  exit 2
fi
REF="$(_resolve_ref "$REF_ARG" "$_REL_TAG" origin/main main HEAD)" ||
  { fail "could not resolve a reference Core commit (tried: ${REF_ARG:-} ${_REL_TAG:-} origin/main main HEAD)"; exit 2; }

# Human-readable name for REF: the caller's --ref/$CORE_REF_SHA, else the release tag we
# defaulted to, else the short sha. Set here (before _classify, which reads it) so `set -u`
# can't trip. The banner used to print `rev-parse --abbrev-ref HEAD` next to REF's sha, which
# labelled the reference with the CURRENT BRANCH — reading "vs Core f95fc2b88218 (main)" while
# REF was actually tag v4.9.3, and "(my-branch)" from any topic branch. That misread the whole
# report as a comparison against main's tip; /drift-triage parses these rows, so name the
# thing we actually compared against.
REF_NAME="${REF_ARG:-${_REL_TAG:-${REF:0:12}}}"

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
  dotfiles-MacBook dotfiles-Alpine dotfiles-Arch dotfiles-Debian
  dotfiles-Defense dotfiles-Fedora dotfiles-Gentoo dotfiles-Offense
  dotfiles-openSUSE
)

# Read a `key=value` (core.lock) or `key = value` (.core-ref) value from a file.
_read_kv() { # _read_kv <file> <key>
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//p" "$1" 2>/dev/null | head -n1
}

# Core's RELEASED LINEAGE — the branch `make sync` actually fans out from. Being ahead of the
# release tag is the NORMAL state between releases, so this is what separates "carries
# unreleased Core" (fine) from "was fanned out from some other branch" (drift).
#
# Prefer the remote-tracking ref: CI checks out with fetch-depth 0, so origin/main is present
# and authoritative, while a local `main` can trail it. Deliberately NO fallback to HEAD — on a
# topic branch HEAD would bless that branch's commits as released lineage, which is exactly the
# divergence this check exists to catch. Resolved ONCE here rather than inside _classify, which
# runs in a per-repo subshell where the lookup would be repeated and thrown away.
_MAIN_REF="" _MAIN_NAME=""
for _m in origin/main main; do
  if _MAIN_REF="$(git -C "$HERE" rev-parse --verify --quiet "${_m}^{commit}" 2>/dev/null)" &&
    [[ -n "$_MAIN_REF" ]]; then
    _MAIN_NAME="$_m"
    break
  fi
  _MAIN_REF=""
done

# Classify a recorded sha against REF, echoing a human status. PURE: it only reads
# (no shared-state writes) because callers run it in a command substitution — a
# subshell, where any DRIFT=1 would be lost. The caller decides drift from the
# returned status string (a "current" PREFIX is the only non-drift verdict, so the
# ahead-of-tag case below must keep that prefix to pass).
DRIFT=0
# Did any drift row name something `make sync` can actually repair? Drives the closing
# advice; see _check_repo. Initialised here because `set -u` makes an unset read fatal.
STALE=0
# How many repos carry Core newer than the reference but still on main's lineage. This tally,
# NOT the exit code, is now where "the fleet isn't pinned to a release" lives — so it has to
# be reported even on a green run. Incremented in _check_repo, which (unlike _classify) runs
# in the current shell, so a plain increment survives.
UNRELEASED=0
# Did any row record a Core commit that isn't on main at all? Only that verdict earns the
# "check the recorded sha" advice — a NOT-CHECKED-OUT repo under --strict is also drift, but
# neither stale nor off-lineage, and must not inherit either recommendation.
OFFLINEAGE=0
_classify() { # _classify <recorded-sha>
  local rec="$1" ahead behind behind_main lag=""
  if [[ -z "$rec" ]]; then echo "no provenance recorded"; return; fi
  if [[ "$rec" == "$REF" ]]; then echo "current"; return; fi
  # Try to quantify; objects may be absent (shallow clone) → fall back to "differs".
  behind="$(git -C "$HERE" rev-list --count "${rec}..${REF}" 2>/dev/null)" || behind=""
  ahead="$(git -C "$HERE" rev-list --count "${REF}..${rec}" 2>/dev/null)" || ahead=""
  if [[ -n "$behind" && -n "$ahead" ]]; then
    if [[ "$behind" != 0 && "$ahead" == 0 ]]; then echo "BEHIND by $behind commit(s)"; return; fi
    # AHEAD-ONLY. The repo carries Core NEWER than the reference — the ordinary state of the
    # whole fleet between releases, because `make sync` vendors main's tip. Newer is not
    # stale, so this must not red the sweep (#371) — but only when the commit is genuinely on
    # the released lineage. With no mainline to check against, don't guess: fail CLOSED and
    # say which it is, rather than either green-lighting an unverifiable lineage or accusing
    # the repo of being off-branch when we simply couldn't look.
    if [[ "$ahead" != 0 && "$behind" == 0 ]]; then
      if [[ -z "$_MAIN_REF" ]]; then
        echo "AHEAD by $ahead commit(s) (no mainline ref — lineage unverifiable)"
      elif git -C "$HERE" merge-base --is-ancestor "$rec" "$_MAIN_REF" 2>/dev/null; then
        # --is-ancestor is reflexive, so a repo synced exactly at the tip counts. But it is
        # reflexive at BOTH ends: "on $_MAIN_NAME" is equally true of a repo sitting exactly
        # at the tip and one dozens of commits back from it, and printing the identical string
        # for both is how a STALLED FAN-OUT stays silent — every row reads `current (…)`, the
        # sweep exits 0, and nothing says the last sync landed weeks ago. So measure the
        # remaining gap and name it. REPORT-ONLY: the `current` prefix, the UNRELEASED tally,
        # DRIFT/STALE/OFFLINEAGE and the exit code are all unchanged — this adds a number to
        # a row that was already green, and a green run stays green.
        #
        # Degrades like behind/ahead above: rev-list exits 128 with empty stdout on an object
        # this clone lacks. An empty OR zero count drops the clause rather than printing
        # "0 behind its tip" — noise on the one ahead-on-main state that is actually finished,
        # and the omission is what keeps the at-tip string byte-identical to the old one.
        behind_main="$(git -C "$HERE" rev-list --count "${rec}..${_MAIN_REF}" 2>/dev/null)" || behind_main=""
        [[ -n "$behind_main" && "$behind_main" != 0 ]] && lag=", $behind_main behind its tip"
        # Inside the parens on purpose: it keeps the verdict one clause, and it makes the
        # suite's `…, on main\)` regex a live oracle for the zero case above.
        echo "current (ahead of $REF_NAME by $ahead commit(s), on $_MAIN_NAME$lag)"
      else
        echo "AHEAD by $ahead commit(s) OFF-LINEAGE (not on $_MAIN_NAME)"
      fi
      return
    fi
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

hdr "Fleet drift vs Core $REF_NAME (${REF:0:12})"
# RECORDED is %-20s, not %-14s: core.lock's core_tag is `git describe` output, so a fleet
# synced between releases carries values like `v4.9.3-56-g44a44fc` (18 chars) that overran the
# old width and broke the column alignment in every CI log.
printf '%-22s %-20s %s\n' "REPO" "RECORDED" "STATUS"
printf '%-22s %-20s %s\n' "----" "--------" "------"

_check_repo() { # _check_repo <repo-dir-name> <marker-relative-path> <sha-key> [tag-key] [subtree-path]
  local name="$1" marker="$2" key="$3" tagkey="${4:-core_tag}" track_path="${5:-}" dir="$ROOT/$1" file rec status tag shown
  if [[ ! -d "$dir" ]]; then
    # --strict documents (header, "Exit:") that a not-checked-out repo FAILS. It called fail
    # — bumping the counter and printing red — but never set DRIFT, so the script still
    # exited 0 and every caller read the run as clean. NOT stale: `make sync` can't repair a
    # repo that was never cloned, so the closing advice must not offer it.
    if ((STRICT)); then fail "$(printf '%-22s %-20s %s' "$name" "-" "NOT CHECKED OUT")"; DRIFT=1
    else skip "$(printf '%-22s %-20s %s' "$name" "-" "not checked out")"; fi
    return
  fi
  file="$dir/$marker"
  if [[ ! -r "$file" ]]; then
    # STALE too: an unstamped repo is exactly what a re-sync fixes. Set here because this
    # branch returns before reaching the bucketing in the verdict arm below.
    fail "$(printf '%-22s %-20s %s' "$name" "-" "missing $marker")"; DRIFT=1; STALE=1; return
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
  # Three-way, not two. The ahead-on-main verdict keeps the `current` PREFIX — that is
  # _classify's non-drift contract — but gets its own glyph and its own tally, because
  # "pinned to a release" and "current, but running unreleased Core" are different operator
  # facts and only one of them is a finished state.
  if [[ "$status" == "current (ahead of "* ]]; then
    UNRELEASED=$((UNRELEASED + 1))
    note "$(printf '%-22s %-20s %s' "$name" "$shown" "$status")"
  elif [[ "$status" == current* ]]; then
    pass "$(printf '%-22s %-20s %s' "$name" "$shown" "$status")"
  else
    fail "$(printf '%-22s %-20s %s' "$name" "$shown" "$status")"
    DRIFT=1
    # Does `make sync` actually FIX this row? It re-vendors main's tip, which repairs a repo
    # that is behind or unstamped — but not one sitting on a foreign lineage, where re-syncing
    # would paper over how it got there. Recorded in the caller (not _classify, which is pure)
    # so the closing advice matches what was really found. No `missing*` arm: that branch
    # returns above, before it could ever reach this case.
    case "$status" in
    BEHIND* | DIFFERS* | "no provenance recorded") STALE=1 ;;
    *OFF-LINEAGE*) OFFLINEAGE=1 ;;
    esac
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

# Say the unpinned count out loud, on a green run AND on a red one — a fleet can be stale in
# one repo and unpinned in seven, and the red row would otherwise bury the second fact. This
# is the signal the old red exit code was carrying badly: the state is fine to RUN and wrong
# to leave indefinitely, and the fix is a release, not a sync.
_unreleased_note() {
  ((UNRELEASED)) || return 0
  note "$UNRELEASED repo(s) carrying UNRELEASED Core — ahead of $REF_NAME on ${_MAIN_NAME:-main}," \
    "not stale but not pinned to a release; cut a release and sync-fanout re-pins the fleet"
}

echo
if ((DRIFT)); then
  if ((STALE)); then
    fail "fleet drift detected — run 'make sync' (and nvim-sync.ps1 for Windows) to bring repos to $REF_NAME"
  elif ((OFFLINEAGE)); then
    # Nothing here is stale, so `make sync` is the wrong advice: these repos carry a Core
    # commit that isn't on main's lineage at all. Say what was actually found instead.
    fail "fleet drift detected — repo(s) record a Core commit off main's lineage; check the recorded sha in their core.lock before re-syncing"
  else
    # Neither stale nor off-lineage — today that means --strict on a repo that isn't cloned.
    # Offer no recipe rather than a wrong one; the rows above already name what's missing.
    fail "fleet drift detected — see the rows above"
  fi
  _unreleased_note
  exit 1
fi
if ((UNRELEASED)); then
  pass "no checked-out repo lags Core $REF_NAME"
  _unreleased_note
else
  # Only claim the strong form when it's actually true: every repo sits exactly on the tag.
  pass "every checked-out repo is pinned to Core $REF_NAME"
fi
exit 0
