#!/usr/bin/env bash
# scripts/sync-core.sh
# ──────────────────────────────────────────────────────────────────────────────
# THE MAINTAIN BUTTON.
#
# After you change Core (here, in dotfiles-core) and push, run this to pull the
# update into every OS repo's vendored core/ subtree. Replaces the old N-way
# manual reconciliation with one mechanical loop.
#
# Assumes:
#   - all OS repos are cloned as siblings under one parent dir (see REPOS_ROOT)
#   - each OS repo already did the one-time:
#       git subtree add --prefix=core <core-remote> main --squash
#
# Usage:
#   ./scripts/sync-core.sh                # pull core into every repo found
#   ./scripts/sync-core.sh --dry-run      # show what would happen, touch nothing
#   ./scripts/sync-core.sh dotfiles-Fedora dotfiles-Arch   # only these
#
# Env overrides:
#   REPOS_ROOT        parent dir holding the repos   (default: parent of this repo)
#   CORE_REMOTE       remote name/URL for dotfiles-core in each OS repo (default: origin of core)
#   CORE_BRANCH       Core branch to vendor          (default: main)
#   SYNC_JOBS         parallel prefetch jobs; 1 disables the warm-up (default: 4)
#   SYNC_SKIP_AUDIT   set to 1 to skip the pre-fan-out audit gate (escape hatch; see below)
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

# The fleet that vendors Core. SINGLE SOURCE: scripts/os-repos.txt (B9) — one edit
# adds an OS target, instead of this array drifting from the README/PORTING-MATRIX.
# The inline list stays as a hard fallback so a missing/corrupt data file can't strand
# the maintain button (it degrades to the last-known fleet rather than fanning out to
# nothing). Lines are trimmed; blanks and `#` comments are dropped.
# NB: dotfiles-Windows is intentionally NOT here — it's the native host layer (no
# vendored core/ subtree). See the note in scripts/os-repos.txt.
ALL_OS_REPOS=(
  dotfiles-MacBook dotfiles-Alpine dotfiles-Arch dotfiles-Defense
  dotfiles-Fedora dotfiles-Gentoo dotfiles-Kali dotfiles-openSUSE
)
_OS_REPOS_FILE="$HERE/scripts/os-repos.txt"
if [[ -r "$_OS_REPOS_FILE" ]]; then
  _from_file=()
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    _line="${_line%%#*}"                       # strip trailing comments
    _line="${_line#"${_line%%[![:space:]]*}"}" # ltrim
    _line="${_line%"${_line##*[![:space:]]}"}" # rtrim
    [[ -n "$_line" ]] && _from_file+=("$_line")
  done <"$_OS_REPOS_FILE"
  ((${#_from_file[@]})) && ALL_OS_REPOS=("${_from_file[@]}")
fi

# usage() is a real heredoc, NOT `sed -n '2,30p' "$0"`: the old form was coupled to
# this file's header line numbers, so editing the banner above silently drifted
# `--help` (the exact trap bootstrap.sh's usage() was rewritten to avoid). This stays
# correct no matter how the header moves.
usage() {
  cat <<'EOF'
sync-core.sh — THE maintain button: subtree-pull Core into every OS repo's core/.

  ./scripts/sync-core.sh                       pull core into every repo found
  ./scripts/sync-core.sh --dry-run, -n         show what would happen, touch nothing
  ./scripts/sync-core.sh dotfiles-Fedora …     only the named repos
  ./scripts/sync-core.sh -h, --help            show this help and exit

Env overrides:
  REPOS_ROOT        parent dir holding the repos   (default: parent of this repo)
  CORE_REMOTE       remote name/URL for dotfiles-core in each OS repo (default: core's origin)
  CORE_BRANCH       Core branch to vendor          (default: main)
  SYNC_JOBS         parallel prefetch jobs; 1 disables the warm-up (default: 4)
  SYNC_SKIP_AUDIT   set to 1 to skip the pre-fan-out audit gate (documented escape hatch)

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
[[ ${#SELECT[@]} -gt 0 ]] && TARGETS=("${SELECT[@]}") || TARGETS=("${ALL_OS_REPOS[@]}")

# Shared palette + pass/skip/fail/have (one definition for every gate script).
# The lib's counters ARE read here: the summary footer prints them as the `checks:` row,
# and the per-repo bucket logic snapshots $FAIL to classify a repo (see the fan-out loop).
# `ok`/`err` are kept as thin aliases for pass/fail so the call sites below read naturally.
# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"
ok() { pass "$@"; }
err() { fail "$@"; }

# core-guard: reuse the bootstrap lib's installer so each repo we sync gets the local
# pre-commit hook that blocks hand-edits to its vendored core/ (see blib_install_core_guard).
# And exempt the commits THIS script makes (subtree pull + core.lock) from that hook —
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
# is the source of truth: it's the tip `subtree pull` fetches, even if the local
# checkout is behind. Falls back to the local branch SHA when offline. (The empty
# assignment from a failed $() does NOT trip `set -e`, so the fallback runs.)
# Resolve the revision with ONE network call: take the FULL SHA from ls-remote, then derive
# the short form as its 12-char prefix (core.lock (B1) records the full hash so an OS repo's
# verify/freshness can compare it exactly against the subtree-split marker, which is full).
CORE_SHA_FULL="$(git ls-remote "$CORE_REMOTE" "$CORE_BRANCH" 2>/dev/null | awk 'NR==1{print $1}')"
[[ -n "$CORE_SHA_FULL" ]] || CORE_SHA_FULL="$(git -C "$HERE" rev-parse "$CORE_BRANCH" 2>/dev/null || echo unknown)"
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
CORE_TAG="$(git -C "$HERE" describe --tags "$CORE_SHA_FULL" 2>/dev/null \
  || git -C "$HERE" describe --tags "$CORE_BRANCH" 2>/dev/null || echo '')"

echo ":: core version = $CORE_VERSION${CORE_TAG:+  (tag $CORE_TAG)}"
echo ":: core remote  = $CORE_REMOTE  (branch $CORE_BRANCH @ $CORE_SHA)"
echo ":: repos root   = $REPOS_ROOT"
echo

# ── Pre-fan-out gate: Core must be audit-green, and what you audited must be what
# fans out. Skipped for --dry-run (nothing is written) and via SYNC_SKIP_AUDIT=1. ──
if ((!DRY)) && [[ "${SYNC_SKIP_AUDIT:-0}" != 1 ]]; then
  # 1. The code must pass its own gate before it lands in 8 repos. We run the same
  #    audit CI and pre-commit run — one definition of "Core is healthy".
  echo ":: pre-fan-out audit (scripts/audit-core.sh --quiet)"
  # Clear DOTFILES_ALLOW_CORE_EDIT (exported above for THIS script's own subtree
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
  # 2. subtree pull fetches the REMOTE tip, not this working tree — so warn if local
  #    HEAD differs from the $CORE_SHA that will actually be vendored. (Best-effort:
  #    only when origin is resolvable; a detached/odd checkout just skips the check.)
  local_head="$(git -C "$HERE" rev-parse --short=12 HEAD 2>/dev/null || echo '')"
  if [[ -n "$local_head" && "$CORE_SHA" != unknown && "$local_head" != "$CORE_SHA" ]]; then
    err "local HEAD ($local_head) != remote tip being fanned out ($CORE_SHA)"
    fail "the audit above validated your LOCAL tree, not what will vendor — push/pull to align, or set SYNC_SKIP_AUDIT=1"
    exit 1
  fi
  echo
fi

# ── B6: parallel prefetch — warm each repo's object store with the Core commit in the
# background so the (sequential, reviewable) subtree pulls below are mostly local. The
# MERGE deliberately stays SERIAL: fanning a squash-merge into 8 working trees is the
# high-stakes step an operator should watch one repo at a time — but the network
# round-trips, the slow part, overlap here. Best-effort: a prefetch failure just means
# that repo's pull fetches normally. Bounded by SYNC_JOBS (default 4; set 1 to disable),
# using BATCHED waits (no `wait -n`) so it stays bash-3.2-safe on macOS. ──
SYNC_JOBS="${SYNC_JOBS:-4}"
if ((!DRY)) && ((SYNC_JOBS > 1)) && [[ "$CORE_SHA" != unknown ]]; then
  echo ":: prefetching Core into up to $SYNC_JOBS repos in parallel (merge stays sequential)"
  _pf=0
  for repo in "${TARGETS[@]}"; do
    path="$REPOS_ROOT/$repo"
    [[ -d "$path/.git" && -d "$path/core" ]] || continue
    git -C "$path" fetch -q "$CORE_REMOTE" "$CORE_BRANCH" >/dev/null 2>&1 &
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

# Per-REPO tally for the summary footer. The line-level PASS/SKIP/FAIL counters from
# common.sh count function calls, not repos: the pre-flight audit ✓ plus two ok() per
# healthy repo (subtree pull + core.lock) — so reporting $PASS as "updated" once claimed
# "updated 17" for an 8-repo fleet (1 + 2×8; the guard-install ✓ came from blib_ok and
# wasn't even counted until the override above). These count REPOS, each landing in
# exactly one bucket: failed if the repo printed any ✗ (dirty tree, pull or lock-commit
# failure), else updated if its subtree pull ran, else skipped.
repos_updated=0 repos_skipped=0 repos_failed=0
for repo in "${TARGETS[@]}"; do
  path="$REPOS_ROOT/$repo"
  if [[ ! -d "$path/.git" ]]; then
    skip "$repo (not cloned at $path)"
    repos_skipped=$((repos_skipped + 1))
    continue
  fi
  if [[ ! -d "$path/core" ]]; then
    skip "$repo (no core/ subtree yet — run the one-time 'git subtree add' first)"
    repos_skipped=$((repos_skipped + 1))
    continue
  fi
  if ((DRY)); then
    echo "would: git -C $path subtree pull --prefix=core $CORE_REMOTE $CORE_BRANCH --squash   (→ $CORE_SHA)"
    continue
  fi
  # bail if the OS repo has a dirty tree — subtree merges into a clean state only
  if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
    err "$repo has uncommitted changes — commit/stash first, skipping"
    repos_failed=$((repos_failed + 1))
    continue
  fi
  echo ":: $repo"
  # Snapshot the line-level FAIL counter: any err() emitted inside this repo's body
  # (pull failure, core.lock commit failure) flips the whole repo into the failed bucket.
  _repo_fail0=$FAIL
  if git -C "$path" subtree pull --prefix=core "$CORE_REMOTE" "$CORE_BRANCH" --squash; then
    ok "$repo core/ updated → $CORE_SHA"
    # B1: stamp provenance so the OS repo can answer "which Core do I carry?" in O(1),
    # OFFLINE, without parsing `git log --grep` for the subtree-split marker (which needs
    # full history and breaks if the squash-commit format ever changes). Lives at the OS
    # repo ROOT — outside core/, so a subtree pull never clobbers it. verify-core asserts
    # this equals the actual split; check-core-freshness reads it as the local baseline.
    if [[ "$CORE_SHA_FULL" != unknown ]]; then
      {
        echo "# GENERATED by dotfiles-core sync-core.sh — vendored Core provenance (B1)."
        echo "# Regenerate after a manual 'git subtree pull' with: make core-lock"
        echo "core_version=$CORE_VERSION"
        echo "core_sha=$CORE_SHA_FULL"
        echo "core_branch=$CORE_BRANCH"
        # Only emit core_tag once Core actually carries a tag — keeps core.lock
        # byte-identical to the pre-tagging format until the first release, so the
        # idempotency check below still skips a no-op re-sync (no spurious commit).
        [[ -n "$CORE_TAG" ]] && echo "core_tag=$CORE_TAG"
      } >"$path/core.lock"
      # COMMIT it (as a follow-up to the subtree-pull commit) so the tree is clean for the
      # NEXT run — otherwise the dirty-tree guard above would see the uncommitted core.lock
      # and refuse to update this repo. Idempotent: a re-sync of the same SHA leaves
      # core.lock byte-identical, so there's nothing staged and we skip the commit.
      git -C "$path" add core.lock
      if git -C "$path" diff --cached --quiet -- core.lock; then
        ok "$repo core.lock current → ${CORE_SHA_FULL:0:12} (v$CORE_VERSION)"
      elif git -C "$path" commit -q -m "chore(core): core.lock → ${CORE_SHA} (v$CORE_VERSION)"; then
        ok "$repo core.lock committed → ${CORE_SHA_FULL:0:12} (v$CORE_VERSION)"
      else
        err "$repo core.lock commit failed — commit it manually before re-running"
      fi
    fi
    # (re)install the local core/ pre-commit guard so a later hand-edit of the vendored
    # subtree in this repo is rejected (this sync run itself is exempt via the env var above).
    blib_install_core_guard "$path" || true
  else
    err "$repo subtree pull failed — resolve, then re-run"
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
