#!/usr/bin/env bash
# scripts/sync-core.sh
# ──────────────────────────────────────────────────────────────────────────────
# THE MAINTAIN BUTTON.
#
# After you change Core (here, in dotfiles-core) and push, run this to vendor the
# update into every OS repo's core/. Replaces the old N-way
# manual reconciliation with one mechanical loop.
#
# Assumes:
#   - all OS repos are cloned as siblings under one parent dir (see REPOS_ROOT)
#   - each OS repo already did the one-time (from a RELEASED tag, never main — #588):
#       git subtree add --prefix=core <core-remote> refs/tags/v5 --squash
#
# Usage:
#   ./scripts/sync-core.sh                # vendor core into every repo found
#   ./scripts/sync-core.sh --dry-run      # show what would happen, touch nothing
#   ./scripts/sync-core.sh dotfiles-Fedora dotfiles-Arch   # only these
#
# Env overrides:
#   REPOS_ROOT        parent dir holding the repos   (default: parent of this repo)
#   CORE_REMOTE       remote name/URL for dotfiles-core in each OS repo (default: origin of core)
#   CORE_BRANCH       Core ref to vendor             (default: main)
#                     `main` is right for a maintainer's ad-hoc `make sync` — the fan-out
#                     always overrides it with the released commit (sync-fanout.yml passes
#                     CORE_BRANCH=<sha>). Vendoring a repo for the FIRST time is the other
#                     case: pass a released tag, or core.lock records a commit no release
#                     points at (#588).
#   SYNC_JOBS         parallel prefetch jobs; 1 disables the warm-up (default: 4)
#   SYNC_SKIP_AUDIT   set to 1 to skip the pre-fan-out audit gate (escape hatch; see below)
#   SYNC_SKIP_STALE   set to 1 to skip the pre-flight 'targets are current' check (#622)
#
# FAN-OUT GATE: this is the single point where Core is vendored into the OS-repo fleet, so a
# defect here amplifies N-way — exactly what audit-core.sh exists to prevent. The repo's
# thesis is "gate BEFORE vendoring", but nothing mechanically enforced that AT the step
# that vendors: it relied on the operator remembering `make audit`. So this script now
# runs the audit itself and REFUSES to fan out a red tree (--dry-run is exempt — it
# touches nothing; SYNC_SKIP_AUDIT=1 is the documented escape hatch for a tree you just
# audited). It also warns when local HEAD differs from the remote tip that actually fans
# out, so you never sync a commit you didn't audit locally.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_ROOT="${REPOS_ROOT:-$(dirname "$HERE")}"
CORE_BRANCH="${CORE_BRANCH:-main}"

# Default: read the core repo's own origin URL so each OS repo pulls from the
# same place. Override with CORE_REMOTE if your OS repos use a named remote.
CORE_REMOTE="${CORE_REMOTE:-$(git -C "$HERE" remote get-url origin 2>/dev/null || echo '')}"

# usage() is a real heredoc, NOT `sed -n '2,30p' "$0"`: the old form was coupled to
# this file's header line numbers, so editing the banner above silently drifted
# `--help` (the exact trap bootstrap.sh's usage() was rewritten to avoid). This stays
# correct no matter how the header moves.
usage() {
  cat <<'EOF'
sync-core.sh — THE maintain button: vendor Core into every OS repo's core/.

  ./scripts/sync-core.sh                       vendor core into every repo found
  ./scripts/sync-core.sh --dry-run, -n         show what would happen, touch nothing
  ./scripts/sync-core.sh dotfiles-Fedora …     only the named repos
  ./scripts/sync-core.sh -h, --help            show this help and exit

Env overrides:
  REPOS_ROOT        parent dir holding the repos   (default: parent of this repo)
  CORE_REMOTE       remote name/URL for dotfiles-core in each OS repo (default: core's origin)
  CORE_BRANCH       Core ref to vendor             (default: main; pass a released tag
                    such as refs/tags/v5 when vendoring a repo for the first time)
  SYNC_JOBS         parallel prefetch jobs; 1 disables the warm-up (default: 4)
  SYNC_SKIP_AUDIT   set to 1 to skip the pre-fan-out audit gate (documented escape hatch)
  SYNC_SKIP_STALE   set to 1 to skip the pre-flight check that each target is up to date

Refuses to fan out a red tree: runs scripts/audit-core.sh first (--dry-run exempt).
EOF
}

DRY=0
SELECT=()
for arg in "$@"; do
  case "$arg" in
  --dry-run | -n) DRY=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  dotfiles-*) SELECT+=("$arg") ;;
  *)
    echo "unknown arg: $arg" >&2
    exit 1
    ;;
  esac
done

# Shared palette + pass/skip/fail/have (one definition for every gate script).
# The lib's counters ARE read here: the summary footer prints them as the `checks:` row,
# and the per-repo bucket logic snapshots $FAIL to classify a repo (see the fan-out loop).
# `ok`/`err` are kept as thin aliases for pass/fail so the call sites below read naturally.
# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"
# The tree-vs-lock comparison, shared with core-integrity.sh so this script's own
# post-fan-out assertion means exactly what that gate will later report (#556).
# shellcheck source=scripts/lib/core-lock.sh
source "${BASH_SOURCE[0]%/*}/lib/core-lock.sh"

# The fleet that vendors Core, from scripts/os-repos.txt via the ONE reader in common.sh
# (#669). There is deliberately no inline fallback list any more: the old one ran only when
# the data file was already unreadable, which is precisely when nobody would notice the
# maintain button fanning out into a stale fleet. An unreadable list now stops the run.
#
# Loaded HERE rather than at the top of the file for two reasons: fail() only exists once
# common.sh is sourced (just above), and naming targets on the CLI does not need the fleet
# list at all — `sync-core.sh dotfiles-Fedora` and `--help` must not depend on it.
if [[ ${#SELECT[@]} -gt 0 ]]; then
  TARGETS=("${SELECT[@]}")
else
  load_os_repos || {
    fail "$CORE_OS_REPOS_ERR — the maintain button has no fleet to fan out into"
    exit 2
  }
  TARGETS=("${CORE_OS_REPOS[@]}")
fi

ok() { pass "$@"; }
err() { fail "$@"; }

# core-guard: reuse the bootstrap lib's installer so each repo we sync gets the local
# pre-commit hook that blocks hand-edits to its vendored core/ (see blib_install_core_guard).
# And exempt the commits THIS script makes (core/ + core.lock) from that hook —
# this IS the legitimate path that rewrites core/.
# shellcheck source=lib/bootstrap-lib.sh
source "$HERE/lib/bootstrap-lib.sh"
export DOTFILES_ALLOW_CORE_EDIT=1
# Route the bootstrap lib's ✓ through the shared tally: blib_ok prints the same green
# check as pass() but does NOT increment $PASS, so the guard-install line was a visible ✓
# the `checks:` summary row couldn't account for. Overriding it (after the source above)
# makes every ✓ this script prints a counted one. blib_warn is left alone deliberately:
# it is a stderr warning, not a ✗ — mapping it to err() would flip a repo with a benign
# "custom pre-commit left as-is" notice into the failed bucket via the $FAIL snapshot.
blib_ok() { ok "$@"; }

[[ -n "$CORE_REMOTE" ]] || {
  err "CORE_REMOTE empty (set origin on dotfiles-core, or export CORE_REMOTE)"
  exit 1
}

# The exact dotfiles-core revision each OS repo will receive — surfaced so a sync
# is traceable (which Core commit landed where; pairs with CHANGELOG.md). ls-remote
# is the source of truth: it's the tip a sync would vendor, even if the local
# checkout is behind. Falls back to the local branch SHA when offline. (The empty
# assignment from a failed $() does NOT trip `set -e`, so the fallback runs.)
# Resolve the revision with ONE network call: take the FULL SHA from ls-remote, then derive
# the short form as its 12-char prefix (core.lock (B1) records the FULL hash because
# core-integrity.sh resolves it to a tree object, and the subtree-split marker it can be
# compared against is full too — a 12-char prefix would make both a string-prefix guess).
# `|| CORE_SHA_FULL=""` is load-bearing under `set -euo pipefail`. With pipefail on, an
# unreachable remote makes the PIPELINE fail (awk succeeds, ls-remote does not), the
# assignment inherits that status, and set -e killed the script right here — exit 128 with
# NO output at all, because ls-remote's stderr is deliberately suppressed. Swallowing it
# lets the local rev-parse fallback run and, failing that, delivers the explicit
# unresolvable-Core refusal below instead of a bare, silent 128.
CORE_SHA_FULL="$(git ls-remote "$CORE_REMOTE" "$CORE_BRANCH" 2>/dev/null | awk 'NR==1{print $1}')" || CORE_SHA_FULL=""
# --verify --quiet, not a bare rev-parse: on an unresolvable ref `git rev-parse foo` prints
# "foo" TO STDOUT and exits 128, so the `|| echo unknown` appended to it produced the
# literal "foo\nunknown" — and CORE_SHA then took a 12-char slice of that. The `unknown`
# sentinel the next line tests for could never actually be reached by this path.
[[ -n "$CORE_SHA_FULL" ]] || CORE_SHA_FULL="$(git -C "$HERE" rev-parse --verify --quiet "$CORE_BRANCH" 2>/dev/null || echo unknown)"
if [[ "$CORE_SHA_FULL" == unknown ]]; then CORE_SHA=unknown; else CORE_SHA="${CORE_SHA_FULL:0:12}"; fi

# Human-readable version stamp (core.version) — vendored into each OS repo so its
# `core-version` verb can report which Core it carries. Surfaced here too so the
# fan-out log records BOTH the SemVer and the commit that landed.
CORE_VERSION="$(tr -d '[:space:]' <"$HERE/core.version" 2>/dev/null || echo unknown)"
[[ -n "$CORE_VERSION" ]] || CORE_VERSION=unknown

# Nearest release tag describing the vendored commit — e.g. "v1.2.0" when synced
# exactly at a tag, or "v1.2.0-5-gabc1234" when Core is 5 commits past it. Best-effort
# and annotated-tag-aware: empty when Core carries no tags yet, or when the resolved
# commit/tags aren't in the local object store (a failed $() leaves it empty, which does
# NOT trip `set -e`). Stamped into core.lock so fleet-drift can speak in NAMED releases,
# not just SHAs (RELEASE-STRATEGY.md gap 1). Describe the resolved SHA first, falling
# back to the branch tip when that object is local.
#
# --match 'v[0-9]*.[0-9]*.[0-9]*' IS LOAD-BEARING, not tidiness (#515). Every release also
# carries a MOVING major alias (`v4`), deliberately re-pointed on each cut so an OS repo can
# track `@v4`. A bare `git describe --tags` picks whichever tag it likes among the several
# pointing at one commit, and on v4.15.1 it picked `v4` — so all nine repos stamped
# `core_tag=v4`: a provenance field naming a target that moves out from under it. The field
# is not decoration. It is read twice: fleet-drift renders it as RECORDED, and it becomes the
# trailing `# vX.Y.Z` comment on every rewritten workflow pin (_sync_pin_workflows below),
# which is what Renovate reads to pick the next bump. `# v4` gives Renovate a target that
# never changes. The two-dot shape excludes the alias by construction; when only the alias
# exists, describe fails and CORE_TAG is empty — and an ABSENT core_tag is strictly better
# than a wrong one, since the field is already documented as conditional. Same idiom as
# scripts/fleet-drift.sh's reference-tag resolution.
#
# The `|| describe "$CORE_BRANCH"` fallback this line used to carry was #556 wearing a
# different hat. $CORE_BRANCH is re-resolved at describe time, so when the branch moved
# after $CORE_SHA_FULL was taken, the fallback stamped a tag belonging to a DIFFERENT
# commit — into core.lock, and onto every rewritten workflow pin comment in all nine
# repos, which is the field Renovate reads. The rule stated just above settles it: an
# ABSENT core_tag is strictly better than a wrong one. Now that the sync vendors
# $CORE_SHA_FULL, describing anything else could only ever be describing the wrong thing.
CORE_TAG="$(git -C "$HERE" describe --tags --match 'v[0-9]*.[0-9]*.[0-9]*' "$CORE_SHA_FULL" 2>/dev/null || echo '')"

# A sync must vendor a NAMED commit. `unknown` means BOTH ls-remote and the local
# rev-parse failed — offline, with a local clone that cannot resolve $CORE_BRANCH — and
# what the script used to do there was materialize core/ from the branch and then skip
# writing core.lock entirely. That is not a tolerated corner case; it is a second,
# race-free producer of exactly the state this file now exists to prevent: core/ moves,
# core.lock stays put, and the next `make core-integrity` calls the repo TAMPERED.
#
# Placed before the audit gate so it costs no time and mutates nothing, and applied to
# --dry-run too: a rehearsal that would refuse should say so.
if [[ "$CORE_SHA_FULL" == unknown ]]; then
  err "could not resolve '$CORE_BRANCH' in $CORE_REMOTE, and $HERE cannot resolve it locally either"
  fail "a sync must vendor a named commit: without one, core/ moves while core.lock does not — the state core-integrity reports as TAMPERED (#556)"
  fail "fix: restore access to $CORE_REMOTE, or 'git fetch' so $HERE can resolve $CORE_BRANCH"
  exit 1
fi

echo ":: core version = $CORE_VERSION${CORE_TAG:+  (tag $CORE_TAG)}"
echo ":: core remote  = $CORE_REMOTE  (branch $CORE_BRANCH @ $CORE_SHA)"
echo ":: repos root   = $REPOS_ROOT"
echo

# ── Pre-flight: refuse to vendor onto a STALE clone ───────────────────────────────────
# The dirty-tree guard below asks "has this repo got uncommitted work?" and nothing asked
# "is this repo current with its remote?". So a sync materialized core/ onto whatever the
# local clone happened to be, reported `updated 9 / failed 0`, and the operator found out at
# `git push` — nine repos already committed to, every push rejected as non-fast-forward
# (#622, observed on the 2026-08-23 sync with all nine between 1 and 5 commits behind).
#
# WHY THIS IS PRE-FLIGHT AND NOT PER-REPO: the whole complaint is learning about it after the
# fan-out has written to nine repos. Checked here, nothing has been mutated yet.
#
# WHY THE OBVIOUS RECOVERY IS WRONG, and this is the part worth stating in the error. Rebasing
# the sync commit onto the updated remote is NOT always correct. Materializing core/ is safe to
# replay — _sync_materialize_core is fully determined by the Core SHA — but _sync_pin_workflows
# is a `sed` over the target's OWN existing workflow files, so its result is a function of a
# tree that no longer exists. It can apply cleanly and still be wrong. The correct recovery is
# to bring each repo up to date and RE-RUN the sync, which is idempotent by design.
#
# Applied to --dry-run too, and placed before the audit gate, for the same reason as the
# `unknown`-commit refusal above: a rehearsal that would refuse should say so, and it should
# not cost the operator a 400-second audit first. Escape hatch: SYNC_SKIP_STALE=1.
if [[ "${SYNC_SKIP_STALE:-0}" != 1 ]]; then
  echo ":: pre-flight: is each target current with its remote?"
  _stale_n=0 _stale_list="" _stale_unreach=0
  for repo in "${TARGETS[@]}"; do
    path="$(resolve_repo_dir "$REPOS_ROOT" "$repo")" || path="$REPOS_ROOT/$repo"
    # Not cloned / no subtree yet: the fan-out loop already reports those as skips. Saying
    # it twice, before it has even been attempted, is noise.
    [[ -d "$path/.git" ]] || continue
    # No upstream (detached HEAD, or a branch that tracks nothing) means there is no remote
    # counterpart to be behind — nothing to assert, so stay quiet rather than guess.
    _ups="$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    [[ -n "$_ups" ]] || continue
    if ! git -C "$path" fetch -q --no-tags "${_ups%%/*}" 2>/dev/null; then
      # Unreachable remote is NOT a refusal: this guard exists to catch a stale clone, and a
      # network blip is a different failure. Say so and let the sync proceed.
      _stale_unreach=$((_stale_unreach + 1))
      skip "$repo (could not reach ${_ups%%/*} — staleness unverified)"
      continue
    fi
    # left-right of HEAD...@{upstream} → "<ahead>\t<behind>". Ahead is fine and expected
    # (unpushed local work); only BEHIND makes the sync commit land on a stale base.
    _lr="$(git -C "$path" rev-list --left-right --count "HEAD...$_ups" 2>/dev/null || true)"
    _behind="${_lr##*[!0-9]}"
    [[ -n "$_behind" ]] || continue
    if ((_behind > 0)); then
      _stale_n=$((_stale_n + 1))
      _stale_list="$_stale_list
    $repo — $_behind behind $_ups"
    fi
  done
  if ((_stale_n > 0)); then
    err "$_stale_n of ${#TARGETS[@]} target repo(s) are BEHIND their remote:$_stale_list"
    fail "vendoring onto a stale base produces commits whose push is rejected as non-fast-forward"
    fail "fix: bring each repo up to date (git pull --ff-only), then RE-RUN this sync — it is idempotent"
    fail "do NOT rebase the sync commit instead: materializing core/ replays safely, but the workflow"
    fail "     pin rewrite is a sed over the target's own files and may apply cleanly while being wrong"
    fail "override (you had better be sure): SYNC_SKIP_STALE=1"
    exit 1
  fi
  ((_stale_unreach)) || ok "every cloned target is current with its remote"
  echo
fi

# ── Pre-fan-out gate: Core must be audit-green, and what you audited must be what
# fans out. Skipped for --dry-run (nothing is written) and via SYNC_SKIP_AUDIT=1. ──
if ((!DRY)) && [[ "${SYNC_SKIP_AUDIT:-0}" != 1 ]]; then
  # 1. The code must pass its own gate before it lands in 8 repos. We run the same
  #    audit CI and pre-commit run — one definition of "Core is healthy".
  echo ":: pre-fan-out audit (scripts/audit-core.sh --quiet)"
  # Clear DOTFILES_ALLOW_CORE_EDIT (exported above for THIS script's own core/
  # commits) for the audit only: the behavioral suite's core-guard test commits to a
  # throwaway core/ and asserts the hook BLOCKS it, so an inherited exemption would
  # make that assertion fail — a false negative that wrongly reds an otherwise-green
  # tree. The audit never writes to core/, so it has no need of the exemption.
  if ! env -u DOTFILES_ALLOW_CORE_EDIT "$HERE/scripts/audit-core.sh" --quiet; then
    err "Core audit FAILED — refusing to fan out a red tree to $((${#TARGETS[@]})) repos"
    fail "fix the audit (or, if you must, re-run with SYNC_SKIP_AUDIT=1)"
    exit 1
  fi
  ok "Core audit green — safe to fan out"
  # 2. The fan-out vendors $CORE_SHA_FULL, not this working tree — so refuse when local
  #    HEAD is a different commit, because then the audit above validated something other
  #    than what ships. Now that the vendored commit is pinned, this equality is exactly
  #    the statement "the tree I audited is the tree that fans out".
  #
  #    FULL sha, not `rev-parse --short=12`: `--short` returns AT LEAST 12 characters and
  #    more when 12 would be ambiguous in this repo, so comparing it against a hard 12-char
  #    prefix is a latent spurious refusal that grows more likely as history does.
  local_head="$(git -C "$HERE" rev-parse HEAD 2>/dev/null || echo '')"
  if [[ -n "$local_head" && "$local_head" != "$CORE_SHA_FULL" ]]; then
    err "local HEAD (${local_head:0:12}) != the pinned commit being vendored ($CORE_SHA)"
    fail "the audit above validated your LOCAL tree, not what will vendor — push/pull to align, or set SYNC_SKIP_AUDIT=1"
    exit 1
  fi
  echo
fi

# ── B6: parallel prefetch — warm each repo's object store with the Core commit in the
# background so the (sequential, reviewable) vendoring below is mostly local. The WRITE
# deliberately stays SERIAL: replacing core/ in 8 working trees is the
# high-stakes step an operator should watch one repo at a time — but the network
# round-trips, the slow part, overlap here. Best-effort: a prefetch failure just means
# that repo fetches normally when its turn comes. Bounded by SYNC_JOBS (default 4; set 1 to disable),
# using BATCHED waits (no `wait -n`) so it stays bash-3.2-safe on macOS. ──
SYNC_JOBS="${SYNC_JOBS:-4}"
if ((!DRY)) && ((SYNC_JOBS > 1)); then
  echo ":: prefetching Core into up to $SYNC_JOBS repos in parallel (merge stays sequential)"
  _pf=0
  for repo in "${TARGETS[@]}"; do
    # Resolved, not string-joined: a repo renamed upstream may still be cloned under its
    # old directory name (scripts/lib/common.sh :: resolve_repo_dir). Falling back to the
    # conventional path keeps the "nothing there" case looking exactly as it did.
    path="$(resolve_repo_dir "$REPOS_ROOT" "$repo")" || path="$REPOS_ROOT/$repo"
    [[ -d "$path/.git" && -d "$path/core" ]] || continue
    # Pinned, and through the same helper the serial loop uses — so a repo whose prefetch
    # succeeded needs NO network below at all (_sync_fetch_pinned short-circuits on
    # cat-file), which makes a re-run of the same sync fully offline. It also picks up
    # --no-tags, which this loop was missing: without it every prefetch dragged Core's
    # whole tag namespace into every OS repo, including the moving `v4` alias that the
    # materialize helper's own comment blames for blocking later fetches.
    _sync_fetch_pinned "$path" "$CORE_REMOTE" "$CORE_SHA_FULL" "$CORE_BRANCH" >/dev/null 2>&1 &
    _pf=$((_pf + 1))
    # `|| true` keeps the prefetch best-effort under `set -e`: a flaky background fetch
    # must never abort the script before the (real) serial merge loop below. A no-arg
    # `wait` returns 0 even when a child failed in modern bash, but the guard makes the
    # best-effort intent explicit AND holds on the bash-3.2 macOS target we can't assume.
    ((_pf % SYNC_JOBS == 0)) && { wait || true; }
  done
  wait || true
  echo
fi

# ── the THIRD reference to a Core commit: the reusable-workflow SHA pins ──────────────
# An OS repo names the vendored Core in three places — the core/ subtree, core.lock's
# core_sha, and (in any repo that SHA-pins its reusable callers) the `uses:` pins. This
# script wrote the first two and left the third, so a fan-out into a pinned repo produced
# a tree that VENDORED one Core and RAN another. Not cosmetic: auto-tag-call holds
# `contents: write` and notify-web-call is handed two secrets, so the pins decide whose
# privileged code executes. The existing gate stays green through it — core-integrity
# compares a tree object and never looks at a workflow — so the drift was silent until
# dotfiles-MacBook's test/check-pins.sh caught it on the v4.12.0 fan-out (#482). (This
# comment used to credit a second gate, `verify-core`, which has never existed here; #454.)
#
# Only an EXISTING 40-hex pin is moved. A caller on the mutable `@vN` alias is left alone:
# tracking the alias is a deliberate per-repo policy (7 of the 9 repos choose it, and the
# alias is what makes a guard fix reach them without an edit), so silently converting one
# into a SHA pin would change that repo's update model behind its back. Converting the
# other way is equally out of scope.
#
# The trailing `# vX.Y.Z` moves with the SHA. Renovate reads that comment to choose the
# next bump, and check-pins.sh compares it against core.lock's core_tag INDEPENDENTLY of
# the SHA — so rewriting one without the other just trades a red gate for a different red
# gate. It is written as core_tag verbatim (`git describe` output, which may be
# v4.12.0-5-gabc1234 off a tag) precisely so the two agree by construction — which is also
# why core_tag's derivation filters out the moving `v4` alias (#515): a `# v4` comment here
# would hand Renovate a bump target that never moves.
#
# Portable-sed shape: write to a temp and mv, never `sed -i` (BSD wants an arg, GNU does
# not). Idempotent by construction — an unchanged file hashes identically and is left
# alone, so a re-sync of the same Core stages nothing. That check is core_files_identical
# rather than `cmp -s`: cmp needs diffutils, and a missing cmp read as "differs" and
# counted every file as changed (#572).
_sync_pin_workflows() { # <repo-path> <full-sha> <tag> → prints how many files it changed
  local path="$1" sha="$2" tag="$3" f tmp changed=0 rc=0
  [[ -d "$path/.github/workflows" ]] || { printf 0; return 0; }
  for f in "$path"/.github/workflows/*.yml "$path"/.github/workflows/*.yaml; do
    [[ -f "$f" ]] || continue # unmatched glob stays literal (nullglob is off)
    tmp="$f.sync.tmp"
    # EVERY failure below is reported and fails the repo, never swallowed. Treating an
    # unreadable or unwritable workflow as "no pins here" would let the caller commit the
    # new core.lock and report the repo synced while a caller still pointed at the previous
    # Core — the exact silent drift this function exists to end, reintroduced through its
    # own error path. The file is named on stderr; the caller turns the non-zero return
    # into an err() (this runs in a command substitution, so an err() in here would have
    # its FAIL increment discarded with the subshell).
    if ! sed -E "s|(dotgibson/dotfiles-core/\.github/workflows/[^@[:space:]]+@)[0-9a-f]{40}|\1${sha}|g" \
      "$f" >"$tmp" 2>/dev/null; then
      rm -f "$tmp"
      printf 'pin rewrite failed (could not read or write): %s\n' "$f" >&2
      rc=1
      continue
    fi
    # Refresh the version comment only on the lines that now carry OUR sha, so a line
    # left on `@vN` above keeps whatever comment it had. A failure here is NOT recoverable
    # by keeping the sha-only rewrite: that lands a pin whose comment still names the old
    # release, which a pin check reds independently of the sha. Discard and report.
    #
    # The address carries the SAME dotgibson/dotfiles-core prefix as the sha pass above,
    # not a bare /@${sha}/. Matching on the sha alone reached any line that happened to
    # contain it — a third-party action pinned at the same commit, or a FORK of this repo
    # — and rewrote its `# vX.Y.Z` to our tag, silently falsifying a version claim on
    # somebody else's action while the sha (correctly prefix-scoped) stayed put. The
    # `\%…%` form picks % as the address delimiter so the slashes in the path need no
    # escaping; it is POSIX and works on both BSD and GNU sed.
    if [[ -n "$tag" ]]; then
      if sed -E "\%dotgibson/dotfiles-core/\.github/workflows/[^@[:space:]]+@${sha}% s|(#[[:space:]]*)v[0-9][^[:space:]]*|\1${tag}|" \
        "$tmp" >"$tmp.2" 2>/dev/null && mv "$tmp.2" "$tmp"; then
        : # comment pass landed
      else
        rm -f "$tmp.2" "$tmp"
        printf 'pin comment rewrite failed: %s\n' "$f" >&2
        rc=1
        continue
      fi
    fi
    if core_files_identical "$f" "$tmp"; then
      rm -f "$tmp"
    elif mv "$tmp" "$f"; then
      changed=$((changed + 1))
    else
      rm -f "$tmp"
      printf 'pin rewrite could not replace: %s\n' "$f" >&2
      rc=1
    fi
  done
  printf '%s' "$changed"
  return "$rc"
}

# Per-REPO tally for the summary footer. The line-level PASS/SKIP/FAIL counters from
# common.sh count function calls, not repos: the pre-flight audit ✓ plus two ok() per
# healthy repo (core/ materialized + core.lock) — so reporting $PASS as "updated" once claimed
# "updated 17" for an 8-repo fleet (1 + 2×8; the guard-install ✓ came from blib_ok and
# wasn't even counted until the override above). These count REPOS, each landing in
# exactly one bucket: failed if the repo printed any ✗ (dirty tree, materialize or
# lock-commit failure), else updated if its core/ was materialized, else skipped.
# ── materialize core/ at a Core commit (replaces `git subtree pull --squash`) ──
# WHY THIS IS NOT A MERGE ANY MORE (#587).
#
# `git subtree pull --squash` locates its base by grepping history for the
# `git-subtree-split:` trailer of the previous sync commit. Every fleet repo squash-merges
# its fan-out PR (RELEASE-STRATEGY.md), and a squash commit keeps the original body only
# if GitHub happens to carry it over — so the trailer is destroyed intermittently. After
# the v4.14.3 round SEVEN of nine repos had lost it.
#
# The consequence is not a missing marker, it is a WRONG BASE: subtree falls back to the
# newest surviving trailer (v4.14.2's) and replays every change since onto a tree that
# already contains v4.14.3, so core/CHANGELOG.md and core/core.version conflict in every
# repo at once. That is exactly how the v4.15.0 fan-out failed 9 of 9.
#
# Merging was never the right operation. core/ is a pure vendored COPY — never edited
# downstream (blib_install_core_guard rejects it, core-integrity.sh proves it byte-for-byte
# against core.lock). The question a sync answers is "make core/ identical to Core@<sha>",
# which has exactly one correct answer and no merge base. Materializing the tree cannot
# conflict, needs no trailer, and is immune to whatever the merge policy does to commit
# bodies. It also makes the sync self-healing: a repo whose core/ drifted for ANY reason
# is corrected by the next run rather than conflicting against its own drift.
#
# `read-tree --prefix` is the same plumbing `git subtree add` uses to place a tree at a
# path, so file modes (the exec bits audit-core.sh asserts) come straight from the tree
# object rather than being reconstructed.
# Is the pinned commit's tree already in this repo's object store?
#
# `cat-file -e <sha>^{tree}` and not `rev-parse`: rev-parse resolves the tree ID by reading
# the COMMIT header, and succeeds while the tree object itself is missing — which is
# precisely the state a partial fetch leaves behind, and precisely what read-tree needs.
_sync_have_core_object() { # <repo-path> <sha>
  git -C "$1" cat-file -e "${2}^{tree}" 2>/dev/null
}

# Get the pinned commit into <repo-path>'s object store, however we can.
#
# Try the bare SHA first: GitHub sets uploadpack.allowReachableSHA1InWant, and the release
# fan-out already proves this path works over HTTPS (sync-fanout.yml pins CORE_BRANCH to a
# raw sha, which flows straight through here). When CORE_BRANCH is itself that sha the two
# arms collapse, and a force-push that removed the pinned commit is then correctly a
# FAILURE rather than a silent vendoring of whatever the ref points at now.
#
# The ref fetch is a fallback for remotes that do not allow unadvertised wants — and it is
# strictly an OBJECT-DELIVERY mechanism. Nothing downstream reads FETCH_HEAD: the caller
# read-trees the pinned sha. A fallback that fetched the ref and then read FETCH_HEAD would
# re-create #556 inside the fix, since FETCH_HEAD is the new tip by definition.
_sync_fetch_pinned() { # <repo-path> <remote> <sha> <ref>
  local path="$1" remote="$2" sha="$3" ref="$4"
  _sync_have_core_object "$path" "$sha" && return 0        # already warm → no network
  if git -C "$path" fetch -q --no-tags "$remote" "$sha" >/dev/null 2>&1 &&
    _sync_have_core_object "$path" "$sha"; then
    return 0
  fi
  [[ "$ref" != "$sha" ]] || return 1                       # nothing else left to try
  git -C "$path" fetch -q --no-tags "$remote" "$ref" >/dev/null 2>&1 || return 1
  _sync_have_core_object "$path" "$sha"                    # the pin must be in what arrived
}

_sync_materialize_core() { # <repo-path> <remote> <sha> <ref> → stages core/ at that commit
  local path="$1" remote="$2" sha="$3" ref="$4"
  _sync_fetch_pinned "$path" "$remote" "$sha" "$ref" || return 1
  # Clear the prefix from index AND worktree: read-tree --prefix refuses to write over
  # existing index entries. --ignore-unmatch so a half-repaired repo (entries already
  # gone, directory still present) is recoverable rather than fatal.
  git -C "$path" rm -rq --ignore-unmatch -- core || return 1
  # The rm above removes TRACKED files only. An untracked leftover under core/ would
  # survive into the new tree and then read as drift to core-integrity, so clear the
  # directory outright. `${path:?}` guards an empty path expanding this to `rm -rf /core`.
  rm -rf -- "${path:?}/core"
  # The pinned tree BY SHA, never FETCH_HEAD (#556). FETCH_HEAD is whatever the ref
  # resolved to during THIS fetch — a second, later resolution of the same moving branch
  # that $CORE_SHA_FULL was taken from up top. When Core was pushed to during the ~250s
  # pre-fan-out audit, the two disagreed: core/ got the new tip, core.lock recorded the
  # old sha, and core-integrity later called the repo TAMPERED — pointing the operator at
  # a hand-edit that never happened. Addressing the tree by sha closes the window instead
  # of narrowing it, and makes the serial fan-out consistent by construction: every repo
  # materializes the same commit no matter how long the loop takes.
  git -C "$path" read-tree --prefix=core/ -u "${sha}^{tree}" || return 1
}

repos_updated=0 repos_skipped=0 repos_failed=0
for repo in "${TARGETS[@]}"; do
  path="$(resolve_repo_dir "$REPOS_ROOT" "$repo")" || path="$REPOS_ROOT/$repo"
  if [[ ! -d "$path/.git" ]]; then
    skip "$repo (not cloned at $path)"
    repos_skipped=$((repos_skipped + 1))
    continue
  fi
  if [[ ! -d "$path/core" ]]; then
    skip "$repo (no core/ yet — run the one-time 'git subtree add' first; see VENDORING.md)"
    repos_skipped=$((repos_skipped + 1))
    continue
  fi
  if ((DRY)); then
    echo "would: materialize $path/core at $CORE_REMOTE ${CORE_SHA_FULL:0:12}   (ref $CORE_BRANCH)"
    continue
  fi
  # bail if the OS repo has a dirty tree — an uncommitted edit here would be destroyed
  if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
    err "$repo has uncommitted changes — commit/stash first, skipping"
    repos_failed=$((repos_failed + 1))
    continue
  fi
  # Name the path whenever it ISN'T the conventional one, so a fan-out into a clone
  # sitting under a pre-rename directory name is visible in the log rather than a
  # surprise the next time someone reads the git output underneath it.
  if [[ "$path" == "$REPOS_ROOT/$repo" ]]; then echo ":: $repo"; else echo ":: $repo (at $path)"; fi
  # Snapshot the line-level FAIL counter: any err() emitted inside this repo's body
  # (pull failure, core.lock commit failure) flips the whole repo into the failed bucket.
  _repo_fail0=$FAIL
  # HEAD before this repo is touched — named in the recovery hint if the post-materialize
  # assertion below fails, so the operator is not left to work out what to reset to.
  _repo_head0="$(git -C "$path" rev-parse HEAD 2>/dev/null || echo '')"
  # Unlike the subtree pull this replaces, materializing COMMITS NOTHING — it leaves the
  # new tree staged so core.lock and the workflow pins land in the SAME commit below.
  # One atomic commit per repo instead of two, and no window where core/ has moved but
  # core.lock has not (the state core-integrity.sh reports as TAMPERED).
  if _sync_materialize_core "$path" "$CORE_REMOTE" "$CORE_SHA_FULL" "$CORE_BRANCH"; then
    ok "$repo core/ materialized → $CORE_SHA"
    # B1: stamp provenance so the OS repo can answer "which Core do I carry?" in O(1),
    # OFFLINE, without parsing `git log --grep` for the subtree-split marker (which needs
    # full history and breaks if the squash-commit format ever changes). Lives at the OS
    # repo ROOT — outside core/, so a subtree pull never clobbers it. core-integrity.sh
    # resolves core_sha to a tree and compares it with the vendored core/; fleet-drift.sh
    # reads it as each repo's recorded Core.
    # No `CORE_SHA_FULL != unknown` guard here any more. The up-front gate makes
    # `unknown` unreachable by this point, and what that guard used to do — materialize
    # core/ and then skip core.lock entirely — was itself a producer of the TAMPERED
    # state this file now exists to prevent (#556).
    {
      echo "# GENERATED by dotfiles-core sync-core.sh — vendored Core provenance (B1)."
      echo "# Regenerated ONLY by Core's fan-out ('make sync' in dotfiles-core) — never"
      echo "# hand-edit, and never 'git subtree pull' by hand: that moves core/ but not"
      echo "# this file, and core-integrity.sh then reports TAMPERED. See VENDORING.md."
      echo "core_version=$CORE_VERSION"
      echo "core_sha=$CORE_SHA_FULL"
      # core_ref, NOT core_branch (#453). The field is written from $CORE_BRANCH, which
      # is a branch name for a hand-run `make sync` but a PINNED COMMIT for a release
      # fan-out — sync-fanout.yml sets CORE_BRANCH="$target_sha" deliberately, so each
      # release PR vendors the exact released commit rather than a moving main. That
      # pinning is correct and stays. What was wrong was persisting it into a field
      # named, and documented in VENDORING.md, as a *branch*: the lock file disagreed
      # with its own contract, and the value duplicated core_sha with nothing added.
      #
      # Named for what it actually holds, it earns its place: core_ref is the one field
      # that says whether this repo was vendored by a release fan-out (a SHA) or by an
      # ad-hoc sync off a branch (a name) — which core_sha alone cannot answer.
      echo "core_ref=$CORE_BRANCH"
      # Only emit core_tag once Core actually carries a tag — keeps core.lock
      # byte-identical to the pre-tagging format until the first release, so the
      # idempotency check below still skips a no-op re-sync (no spurious commit).
      [[ -n "$CORE_TAG" ]] && echo "core_tag=$CORE_TAG"
    } >"$path/core.lock"
    # COMMIT it, alongside the already-staged core/ tree, so the tree is clean for the
    # NEXT run — otherwise the dirty-tree guard above would see the uncommitted core.lock
    # and refuse to update this repo. Idempotent: a re-sync of the same SHA leaves
    # core.lock byte-identical, so there's nothing staged and we skip the commit.
    # Move the workflow pins in the SAME commit that stamps core.lock: the two name the
    # same Core, so landing them apart leaves a window where the repo's own pin gate is
    # red on main. See the _sync_pin_workflows block above for why (#482).
    # `|| _pinfail=1` rather than a bare assignment: `set -e` is on, so a non-zero from
    # the command substitution would abort the whole fan-out mid-fleet. We want THIS repo
    # marked failed and the remaining repos still attempted — the same shape the dirty-tree
    # guard uses.
    _pinfail=0
    _pins="$(_sync_pin_workflows "$path" "$CORE_SHA_FULL" "$CORE_TAG")" || _pinfail=1
    # core.lock is still committed below even on a pin failure: core/ is already staged,
    # so leaving it uncommitted would only add a dirty tree that self-blocks
    # the next run on top of the drift. The err() is what makes it non-silent — it flips
    # this repo into the failed bucket, so the run cannot end "updated 8" with a repo whose
    # pins never moved.
    ((_pinfail)) && err "$repo: a workflow pin could not be rewritten (named above) — core.lock will be ahead of its pins; re-run after fixing the file"
    git -C "$path" add core.lock
    ((_pins)) && git -C "$path" add .github/workflows
    # Staged-wide, not `-- core.lock`: a repo whose core.lock is already current but
    # whose pins are stale (the state a fan-out predating this left behind) must still
    # commit. Scoping the check to core.lock reported "current" and dropped the pin fix.
    if git -C "$path" diff --cached --quiet; then
      ok "$repo core.lock current → ${CORE_SHA_FULL:0:12} (v$CORE_VERSION)"
    else
      # Name what actually moved. Since materializing stages core/ alongside core.lock,
      # "core.lock → sha" would understate a run that replaced the whole vendored tree —
      # and `git log -- core/` is how a maintainer finds the sync that brought a file in.
      if git -C "$path" diff --cached --quiet -- core; then
        _lockmsg="chore(core): core.lock → ${CORE_SHA} (v$CORE_VERSION)"
        ((_pins)) && _lockmsg="chore(core): core.lock + ${_pins} workflow file(s) → ${CORE_SHA} (v$CORE_VERSION)"
      else
        _lockmsg="chore(core): sync Core → v$CORE_VERSION (${CORE_SHA})"
        ((_pins)) && _lockmsg="chore(core): sync Core → v$CORE_VERSION (${CORE_SHA}) + ${_pins} workflow file(s)"
      fi
      # Emit the subtree trailer even though NOTHING here depends on it any more.
      # core.lock is the authoritative provenance (#587), and this sync no longer reads
      # the trailer to find a base — but consumer tooling still uses it as a fallback
      # (dotfiles-MacBook's verify-core warns when it disagrees with the lock), so an
      # ACCURATE marker where one survives is strictly better than none. Informational,
      # not load-bearing: a squash-merge may still eat it, and that is now harmless
      # rather than the thing that breaks the next release.
      _lockmsg="$_lockmsg
git-subtree-dir: core
git-subtree-split: ${CORE_SHA_FULL}"
      if git -C "$path" commit -q -m "$_lockmsg"; then
        ok "$repo core.lock committed → ${CORE_SHA_FULL:0:12} (v$CORE_VERSION)"
        ((_pins)) && ok "$repo repointed ${_pins} workflow file(s) at ${CORE_SHA_FULL:0:12}${CORE_TAG:+ ($CORE_TAG)}"
      else
        err "$repo core.lock commit failed — commit it manually before re-running"
      fi
    fi
    # ── POST-FAN-OUT ASSERTION: prove core/ and core.lock name the same commit ────
    # The sync PRODUCES this pair, so it is the run that should catch them disagreeing.
    # Before #556 it could not: a mismatch surfaced later, out of context, as a
    # `TAMPERED (core/ edited since sync)` verdict from an unrelated `make core-integrity`
    # — a diagnosis pointing at a hand-edit that never happened, which is the part that
    # cost the most time to unpick.
    #
    # Same comparison core-integrity.sh makes, via the shared lib, so the two cannot drift.
    # Resolved in "$path" and not "$HERE": after _sync_fetch_pinned the CONSUMER is
    # guaranteed to hold the object, whereas $HERE may not under SYNC_SKIP_AUDIT=1.
    #
    # Asserted on HEAD:core after the commit — that is the artefact core-integrity will
    # read. The idempotent "core.lock current" path is covered too: nothing was staged
    # precisely because HEAD:core already carries the right tree.
    _sync_vend="$(core_lock_vendored_tree "$path" || echo '')"
    _sync_exp="$(core_lock_expected_tree "$path" "$CORE_SHA_FULL" || echo '')"
    if [[ -n "$_sync_vend" && "$_sync_vend" == "$_sync_exp" ]]; then
      ok "$repo core/ verified == Core@$CORE_SHA (tree ${_sync_vend:0:12})"
    else
      # err(), not exit: sync-fanout.yml runs this script under `bash -e`, so aborting
      # here would deny PRs to every repo that synced correctly. Report, bucket this repo
      # as failed, and keep going — the same shape the dirty-tree and pin guards use.
      #
      # And no auto-revert: on the idempotent path no commit was made, so a blind
      # `reset --hard HEAD~1` would destroy a good prior commit. Name the target instead.
      err "$repo: vendored core/ tree ${_sync_vend:0:12} != Core@$CORE_SHA tree ${_sync_exp:0:12} — core/ and core.lock disagree (#556)"
      [[ -n "$_repo_head0" ]] && fail "recover with: git -C $path reset --hard ${_repo_head0:0:12}"
    fi

    # (re)install the local core/ pre-commit guard so a later hand-edit of the vendored
    # subtree in this repo is rejected (this sync run itself is exempt via the env var above).
    blib_install_core_guard "$path" || true
  else
    err "$repo: could not materialize core/ at $CORE_SHA — resolve, then re-run"
  fi
  if ((FAIL > _repo_fail0)); then
    repos_failed=$((repos_failed + 1))
  else
    repos_updated=$((repos_updated + 1))
  fi
  echo
done

# Scannable tally of the fan-out — sync sources common.sh (which counts every
# ok/skip/err via PASS/SKIP/FAIL) but used to end on a bare "done", forcing you to
# scroll an 8-repo run to learn what actually landed.
#
# The headline counts REPOS (each in exactly one bucket — see the loop above); it used
# to print the line-level $PASS as "updated", which claimed "updated 17" for an 8-repo
# fleet. The line-level counters stay on a second `checks:` row and — with blib_ok routed
# through the tally near the top of this script — match the individual ✓/–/✗ lines above
# one-for-one, which is what you scroll back for on a red run.
printf '\n%s──────── sync summary ────────%s\n' "$c_blu" "$c_rst"
printf '  repos:  %supdated %d%s   %sskipped %d%s   %sfailed %d%s   (of %d targeted)\n' \
  "$c_grn" "$repos_updated" "$c_rst" "$c_yel" "$repos_skipped" "$c_rst" "$c_red" "$repos_failed" "$c_rst" \
  "${#TARGETS[@]}"
printf '  checks: %sok %d%s   %sskip %d%s   %serr %d%s\n' \
  "$c_grn" "$PASS" "$c_rst" "$c_yel" "$SKIP" "$c_rst" "$c_red" "$FAIL" "$c_rst"
if ((DRY)); then
  echo "dry-run — nothing was written."
elif ((FAIL > 0)); then
  echo "done with failures — see the ✗ lines above, then re-run the affected repos." >&2
else
  echo "done. push each updated repo when you're satisfied."
fi
