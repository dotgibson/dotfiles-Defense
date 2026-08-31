#!/usr/bin/env bash
# scripts/tag-release.sh — finish a release, in TWO phases: commit, then (after the PR
# merges) publish the tags.
# ──────────────────────────────────────────────────────────────────────────────
# `release.sh` deliberately stops short of git: it bumps core.version, promotes the
# CHANGELOG, runs the audit, and PRINTS the commit/tag/push recipe for the operator to
# run by hand. That hand-run recipe is the last drift-prone step — a fat-fingered tag
# name or a forgotten `git push --tags` is exactly the class of mistake the rest of the
# release path is mechanized to avoid. This is the other half.
#
# WHY TWO PHASES — the tag is created LAST, never before the merge:
#
# This script used to commit AND tag in one go, leaving a local `vX.Y.Z` sitting on a
# commit that was not yet on main. That window is not safe, and no amount of
# `--no-follow-tags` discipline closes it: the flag governs YOUR push, while the tag
# lives in SHARED .git state that any other process can push. It happened — a concurrent
# session pushed its own branch with `push.followTags` set, carried the release tag to
# origin, and fired release.yml + sync-fanout.yml against an unmerged commit, opening
# eight bad vendor PRs across the fleet. The version number had to be retired.
#
# So the invariant is now structural rather than procedural:
#
#     a vX.Y.Z tag only ever exists on a commit that is already on origin/main.
#
# Phase 1 (default) commits the release and creates NO tag — there is nothing for a
# stray push to carry. Phase 2 (--publish) runs after the PR merges: it proves
# origin/main actually carries this version, then tags origin/main and pushes.
#
# Usage:
#   ./scripts/tag-release.sh              # phase 1: commit core.version + CHANGELOG
#   ./scripts/tag-release.sh --publish    # phase 2: tag origin/main + push (AFTER merge)
#   make tag                              # phase 1, via the Makefile façade
#   make publish                          # phase 2
#
# Env:
#   TAG_SKIP_AUDIT=1   skip the green-tree gate (escape hatch for a tree you just audited)
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

usage() {
  cat <<'EOF'
usage: tag-release.sh [--publish]

Finish the release that release.sh staged, in two phases.

  (no flag)     PHASE 1 — prove the tree green and commit core.version + CHANGELOG.md.
                Creates NO tag: until the commit is on origin/main there must be no
                vX.Y.Z for a stray push to carry to the remote. Prints the land recipe.

  --publish     PHASE 2 — run AFTER the release PR merges. Proves origin/main really
                carries this core.version, then creates the annotated vX.Y.Z and moves
                the vN alias AT origin/main, and pushes both.

  -h, --help    show this help and exit

Env: TAG_SKIP_AUDIT=1 skips the audit gate (use only on a tree you just audited).
EOF
}

MODE=commit
case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
--publish)
  MODE=publish
  ;;
--push)
  # Removed deliberately. Its whole semantic was "push the tag we just made on the
  # PRE-merge commit", which is the failure this script now exists to prevent.
  fail "tag-release.sh: --push was removed — it pushed a tag for a commit that was not on main yet"
  fail "run this with no flag to commit, land the PR, then re-run with --publish"
  exit 2
  ;;
"") ;;
*)
  fail "tag-release.sh: unknown argument '$1'"
  usage >&2
  exit 2
  ;;
esac

have git || {
  fail "tag-release.sh: git not found"
  exit 1
}
git rev-parse --git-dir >/dev/null 2>&1 || {
  fail "tag-release.sh: not a git checkout"
  exit 1
}

CHANGELOG="CHANGELOG.md"
VERFILE="core.version"
[[ -r "$VERFILE" && -r "$CHANGELOG" ]] || {
  fail "tag-release.sh: $VERFILE or $CHANGELOG missing/unreadable"
  exit 1
}

VERSION="$(tr -d '[:space:]' <"$VERFILE")"
# A tag stamps a clean SemVer release — the same shape release.sh enforces. A
# prerelease/dirty core.version means no release was cut; refuse rather than tag junk.
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "tag-release.sh: core.version ('$VERSION') is not a clean release (X.Y.Z) — run 'make release VERSION=X.Y.Z' first"
  exit 2
fi
TAG="v$VERSION"

MAJOR="v${VERSION%%.*}"

# ── PHASE 2 — publish the tags for a release that has ALREADY landed on main ──
if [[ "$MODE" == publish ]]; then
  hdr "publish $TAG (tag origin/main)"
  # --force, and the stderr is NOT swallowed. The vN major alias is force-moved to every
  # release (see the push below), so any clone that missed a release has a stale local vN
  # — and a plain `git fetch --tags` REFUSES to move it ("would clobber existing tag"),
  # exits 1, and takes publish down with it. That is not a fetch failure, but with the
  # error redirected to /dev/null it reported as one: "could not fetch origin" sent the
  # operator to look at the network while a one-line tag update was all that was needed.
  # Observed cutting v5.4.3, on a clone whose v4 and v5 were both behind.
  #
  # Forcing is correct rather than merely convenient: vN is a MOVING alias whose remote
  # value is authoritative by definition, so a local ref that disagrees is stale, never
  # a competing truth. Immutable vX.Y.Z release tags are unaffected — they never move,
  # so --force never has anything to overwrite there, and the ruleset forbids it anyway.
  if ! fetch_err="$(git fetch -q --force --tags origin 2>&1)"; then
    fail "tag-release.sh: could not fetch origin — publishing needs the remote's view of main"
    [[ -n "$fetch_err" ]] && printf '%s\n' "$fetch_err" >&2
    exit 1
  fi
  git rev-parse -q --verify origin/main >/dev/null || {
    fail "tag-release.sh: no origin/main to tag"
    exit 1
  }

  # THE guard, and it must identify the RELEASE COMMIT — not merely today's tip.
  # core.version does not change again until the NEXT release, so "origin/main carries
  # $VERSION" stays true for every commit that lands afterwards. Tagging the tip would
  # therefore tag whatever merged most recently, sweeping changes still sitting under
  # [Unreleased] into the release — and release.yml builds the Release body from the
  # [vX.Y.Z] section, so those changes would ship undescribed.
  #
  # So resolve the commit that SET core.version to this value: walk origin/main's history
  # for commits touching core.version, newest first, and take the first whose blob is
  # $VERSION. Under a squash merge that is exactly the release commit.
  RELEASE_SHA=''
  while IFS= read -r _sha; do
    [[ -n "$_sha" ]] || continue
    if [[ "$(git show "$_sha:$VERFILE" 2>/dev/null | tr -d '[:space:]')" == "$VERSION" ]]; then
      RELEASE_SHA="$_sha"
    else
      # First commit going back that does NOT carry $VERSION — everything older predates
      # the bump, so the last match we saw is the commit that introduced it.
      break
    fi
  done < <(git rev-list origin/main -- "$VERFILE")

  if [[ -z "$RELEASE_SHA" ]]; then
    fail "tag-release.sh: no commit on origin/main sets $VERFILE to '$VERSION' as its newest change"
    fail "either the release PR has not merged, or main has already moved on to a newer release"
    fail "land it first: the recipe is printed by a no-flag run"
    exit 1
  fi
  pass "release commit on origin/main: $(git rev-parse --short "$RELEASE_SHA") (sets $VERFILE to $VERSION)"

  # Say so when the tag will not land on the tip — that is legitimate (main moved on
  # after the release merged) but the operator should know `git describe` on main will
  # now report commits-since, not a clean tag.
  if [[ "$RELEASE_SHA" != "$(git rev-parse origin/main)" ]]; then
    # `skip`, not `note` — there is no note() in scripts/lib/common.sh (it defines
    # pass/skip/fail/hdr/have), so this line printed "note: command not found" and the
    # operator never saw the notice. It survived because this branch only runs when main
    # has ADVANCED past the release commit — an uncommon path — and because a bare word
    # that might be some command on PATH is not something the linter can flag. It fired
    # for real publishing v4.12.2, swallowing the very message it exists to give.
    # scripts/test-core.sh now drives this branch and asserts BOTH that the notice appears
    # and that no "command not found" does, so the gap that hid this is closed.
    skip "origin/main has advanced $(git rev-list --count "$RELEASE_SHA..origin/main") commit(s) since the release — tagging the release commit, not the tip"
  fi

  # The Release BODY comes from this commit's [vX.Y.Z] section (release.yml extracts it),
  # so a commit with the right core.version but no heading yields a tag that release.yml
  # then fails on — and by then the tag is published and immutable, i.e. the version is
  # burned. Validate before creating any tag.
  #
  # Captured, NOT piped into `grep -q`: under `set -o pipefail` that pipeline reports
  # failure on a successful match, because grep -q exits on the first hit and git show
  # then dies of SIGPIPE part-way through a 4000-line file.
  RELEASE_CHANGELOG="$(git show "$RELEASE_SHA:$CHANGELOG" 2>/dev/null)"
  if ! grep -qE "^## +\[v?${VERSION//./\\.}\]" <<<"$RELEASE_CHANGELOG"; then
    fail "tag-release.sh: the release commit's $CHANGELOG has no '## [v$VERSION]' heading"
    fail "release.yml builds the Release body from that section — refusing to publish a tag it would fail on"
    exit 1
  fi

  # A heading is not enough: release.yml ALSO rejects an empty section, and release.sh
  # will happily promote an empty [Unreleased]. Without this, publish would push the
  # immutable tag and release.yml would then fail on the empty body — burning the version
  # for a reason that was knowable up front. Extract the body with the SAME awk release.yml
  # uses, so the two cannot disagree about what "empty" means.
  RELEASE_BODY="$(awk -v tag="v$VERSION" '
    $0 ~ "^## +\\[" tag "\\]" { f = 1; next }
    f && /^## +\[/ { exit }
    f && NF { p = 1 }
    f && p { buf[++n] = $0 }
    END { while (n > 0 && buf[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print buf[i] }
  ' <<<"$RELEASE_CHANGELOG")"
  if [[ -z "${RELEASE_BODY//[[:space:]]/}" ]]; then
    fail "tag-release.sh: the [v$VERSION] section in $CHANGELOG is EMPTY"
    fail "release.yml refuses an empty Release body — publishing would burn the version; write the notes first"
    exit 1
  fi
  pass "the release commit's $CHANGELOG carries a non-empty [v$VERSION] section"

  # Never clobber a published release. vX.Y.Z is immutable by ruleset, so a re-push
  # would be rejected anyway — fail here with a reason instead of a git error.
  if git ls-remote --tags --exit-code origin "refs/tags/$TAG" >/dev/null 2>&1; then
    fail "tag-release.sh: $TAG already exists on origin — a published release tag is immutable"
    exit 1
  fi

  # Capture the remote alias NOW, well before the push: it is the lease for the force
  # below. A concurrent publisher that moves $MAJOR between this read and that push
  # invalidates the lease and our push is rejected — which is the point. Reading it here
  # rather than immediately before the push widens the window the lease protects.
  #
  # Rolling $MAJOR BACKWARD needs no separate guard: the resolution above only accepts the
  # NEWEST core.version change on origin/main, so an older release cannot resolve at all
  # and is refused before any tag is created (pinned by a test).
  REMOTE_MAJOR="$(git ls-remote origin "refs/tags/$MAJOR" 2>/dev/null | awk 'NR==1{print $1}')"

  # The lease alone is not enough. It only covers changes AFTER this read — but a newer
  # publisher that completes BEFORE it makes us read THEIR alias as our expected value,
  # and the leased push then moves $MAJOR backward with the lease perfectly satisfied.
  # So require the move to be FORWARD: whatever $MAJOR points at must be an ancestor of
  # the commit we are about to move it to. (An earlier revision dropped this guard as
  # unreachable, reasoning that resolution only accepts origin/main's newest core.version
  # change — true, but that reasoning holds only at resolution time, and this read happens
  # later. The two together are what make it safe: ancestry closes the gap before the
  # read, the lease closes the gap after it.)
  if [[ -n "$REMOTE_MAJOR" ]]; then
    REMOTE_MAJOR_COMMIT="$(git rev-parse -q --verify "$REMOTE_MAJOR^{commit}" 2>/dev/null || echo '')"
    if [[ -z "$REMOTE_MAJOR_COMMIT" ]]; then
      fail "tag-release.sh: cannot resolve origin's $MAJOR ($REMOTE_MAJOR) locally — refusing to move an alias blind"
      exit 1
    fi
    if [[ "$REMOTE_MAJOR_COMMIT" != "$RELEASE_SHA" ]] &&
      ! git merge-base --is-ancestor "$REMOTE_MAJOR_COMMIT" "$RELEASE_SHA" 2>/dev/null; then
      fail "tag-release.sh: origin's $MAJOR points at $(git rev-parse --short "$REMOTE_MAJOR_COMMIT"), which is not an ancestor of this release"
      fail "moving it would roll $MAJOR backward for every caller pinned to it — refusing (another publisher may have raced ahead; re-fetch and re-check)"
      exit 1
    fi
  fi

  if ! git tag -fa "$TAG" "$RELEASE_SHA" -m "$TAG"; then
    fail "tag-release.sh: could not create $TAG at origin/main"
    exit 1
  fi
  pass "tagged $TAG at $(git rev-parse --short "$RELEASE_SHA")"

  # The moving MAJOR alias reusable-workflow callers pin to (RELEASE-STRATEGY.md
  # §"Pinning reusable workflows"). Force-moved to each new vN.x so callers pick up
  # patch/minor guard fixes without a manual bump.
  #
  # ANNOTATED with a message (-fa … -m), exactly like the immutable tag above, and not a
  # bare `git tag -f`. Under `tag.gpgsign = true` git makes any tag SIGNED — therefore
  # annotated — so the message-less form aborts with "fatal: no tag message?" and the
  # publish dies here. That is invisible on a box with signing off, which is why it
  # survived: it broke the first time an operator with signing enabled cut a release
  # (v4.12.2, #506). Annotating is also the better artefact for a force-moved pointer:
  # it records who moved the alias and when, which a lightweight ref cannot.
  if ! git tag -fa "$MAJOR" "$RELEASE_SHA" -m "$MAJOR" >/dev/null; then
    fail "tag-release.sh: could not move major tag $MAJOR"
    exit 1
  fi
  pass "moved major tag $MAJOR → $(git rev-parse --short "$RELEASE_SHA")"

  # ONE atomic push, not two. Pushed separately these can half-land: if vX.Y.Z lands and
  # vN does not, release.yml and sync-fanout.yml fire while the alias every reusable-
  # workflow caller pins to is still stale — and re-running --publish then refuses,
  # because the immutable tag now exists. A concurrent publisher makes it worse: this
  # invocation could lose the vX.Y.Z race and still force vN back to its stale value.
  # --atomic makes it all-or-nothing; the leading + forces ONLY the alias, so a
  # non-fast-forward on the immutable tag is still rejected rather than overwritten.
  # The lease turns the alias force into a compare-and-swap: reject rather than overwrite
  # if $MAJOR moved since REMOTE_MAJOR was read. With no remote alias yet (a new major)
  # there is nothing to lease against and the ref is simply created.
  push_args=(--atomic origin "refs/tags/$TAG")
  if [[ -n "$REMOTE_MAJOR" ]]; then
    push_args+=(--force-with-lease="refs/tags/$MAJOR:$REMOTE_MAJOR" "+refs/tags/$MAJOR")
  else
    push_args+=("refs/tags/$MAJOR")
  fi
  if ! git push "${push_args[@]}"; then
    fail "tag-release.sh: atomic tag push failed — nothing was published"
    fail "if $MAJOR moved under you, another publisher won the race: re-fetch and re-run 'make publish'"
    exit 1
  fi
  pass "pushed $TAG and $MAJOR atomically"

  printf '\n%s──────── %s published ────────%s\n' "$c_blu" "$TAG" "$c_rst"
  cat <<EOF
  release.yml publishes the GitHub Release from the CHANGELOG section, then
  sync-fanout.yml opens a vendor PR in every repo in scripts/os-repos.txt.
  It opens PRs and never merges them — review canary-first (RELEASE-STRATEGY.md).

  verify:  gh run list --workflow release --limit 1
           gh run list --workflow sync-fanout --limit 1
EOF
  exit 0
fi

# ── PHASE 1 — commit the release. NO TAG IS CREATED HERE. ────────────────────
hdr "commit $TAG (from core.version)"

# Guard 1: never clobber an existing tag — a re-run after a successful tag must be a
# clear no-op error, not a silent second tag or a moved ref.
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  fail "tag-release.sh: tag $TAG already exists — bump core.version or delete the tag to re-cut"
  exit 1
fi

# Guard 2: the CHANGELOG must already carry this version's dated heading — i.e.
# release.sh ran. Tagging a version with no changelog section is exactly the
# incoherence the audit's version/CHANGELOG gate exists to catch; refuse up front.
if ! grep -qE "^## +\[v?${VERSION//./\\.}\]" "$CHANGELOG"; then
  fail "tag-release.sh: no '## [v$VERSION]' heading in $CHANGELOG — run 'make release VERSION=$VERSION' first"
  exit 1
fi

# Guard 3: prove the tree green before it's tagged (the same gate release.sh and
# sync-core.sh enforce). Skippable for a tree you JUST audited, mirroring SYNC_SKIP_AUDIT.
if [[ "${TAG_SKIP_AUDIT:-0}" == 1 ]]; then
  skip "audit (TAG_SKIP_AUDIT=1)"
else
  hdr "audit (tag must be green)"
  if ./scripts/audit-core.sh --quiet; then
    pass "audit green"
  else
    fail "audit FAILED — fix before tagging (or TAG_SKIP_AUDIT=1 to override a just-audited tree)"
    exit 1
  fi
fi

# Commit the two release files iff they actually differ from HEAD (release.sh left them
# modified). Re-running after the commit already landed is a no-op, not an error. The
# explicit pathspec commits ONLY these two files, so unrelated staged work is never
# swept into the release commit.
if git diff --quiet HEAD -- "$VERFILE" "$CHANGELOG"; then
  pass "release commit already present ($VERFILE/$CHANGELOG match HEAD)"
else
  if git commit -q -m "release $TAG" -- "$VERFILE" "$CHANGELOG"; then
    pass "committed release $TAG"
  else
    fail "tag-release.sh: commit failed"
    exit 1
  fi
fi

printf '\n%s──────── %s committed (no tag yet, by design) ────────%s\n' "$c_blu" "$TAG" "$c_rst"
cat <<EOF
  review:  git show HEAD

  NO TAG EXISTS YET, and that is the point. A vX.Y.Z tag is only created once the commit
  is on origin/main, so there is no window in which a stray push — yours or a concurrent
  session sharing this checkout — can carry $TAG to the remote and fire release.yml +
  sync-fanout.yml against an unmerged commit.

  You should be ON release/$TAG right now — this script commits to whatever branch you are
  standing on, and RELEASE-RUNBOOK.md §1.1 step 1 branches before staging for that reason.
  If you staged from main instead, the release commit is sitting on your local main, one
  ahead of origin, where it must NEVER be pushed (main is protected and takes the commit
  through the PR below). Push it to the branch as step 1 shows, then 'git reset --hard
  origin/main' to put your local main back.

  1. land the commit:
       git push origin HEAD:release/$TAG
       gh pr create --base main --head release/$TAG --title "release $TAG"
       # merge it — GitHub only offers the methods this repo enables, and any of them is
       # fine: phase 2 tags origin/main, so the merge method cannot affect the tag.
       # (Why the method cannot matter: RELEASE-RUNBOOK.md §"Why the tag comes last".)
  2. publish the tags AFTER the PR merges:
       make publish          # or: ./scripts/tag-release.sh --publish
       # refuses unless origin/main actually carries core.version $VERSION
  3. fan out: sync-fanout.yml opens the vendor PRs on release; or ./scripts/sync-core.sh

  Abandoning instead? Nothing to undo but the commit and the branch — no tags were
  created, so there is no 'git tag -d' step and no vN alias pointing at a dropped commit.
  Full recipe: RELEASE-RUNBOOK.md §"Abandoning a cut".
EOF
