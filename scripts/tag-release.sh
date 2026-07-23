#!/usr/bin/env bash
# scripts/tag-release.sh — finish a release: commit, annotated-tag, (optionally) push.
# ──────────────────────────────────────────────────────────────────────────────
# `release.sh` deliberately stops short of git: it bumps core.version, promotes the
# CHANGELOG, runs the audit, and PRINTS the commit/tag/push recipe for the operator to
# run by hand. That hand-run recipe is the last drift-prone step — a fat-fingered tag
# name or a forgotten `git push --tags` is exactly the class of mistake the rest of the
# release path is mechanized to avoid. This is the other half: it reads the version
# `release.sh` already stamped, re-proves the tree green, commits core.version+CHANGELOG,
# and creates the annotated `vX.Y.Z` tag — so `make release … && make tag` is the whole
# cut, end to end (RELEASE-STRATEGY.md gap 3).
#
# Push stays OPT-IN. Tagging is local and cheap to undo (`git tag -d`); pushing a tag to
# origin is the outward, hard-to-walk-back step, so it happens only with --push (or
# `make tag PUSH=1`). Without it, the script prints the exact push commands, mirroring
# release.sh's hands-off-the-remote stance.
#
# Usage:
#   ./scripts/tag-release.sh            # commit + annotated tag for core.version's value
#   ./scripts/tag-release.sh --push     # …then push the tags (vX.Y.Z + vN) to origin
#   make tag                            # same, via the Makefile façade (PUSH=1 to push)
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
usage: tag-release.sh [--push]

Finish the release that release.sh staged: commit core.version + CHANGELOG.md,
create the annotated tag vX.Y.Z (X.Y.Z = the current core.version), after proving
the tree green. Pushing is opt-in:

  --push        push the release tags (vX.Y.Z + the moved vN alias) to origin;
                main is protected, so the release commit lands via a PR (the script
                prints the recipe) — --push never touches the branch
  -h, --help    show this help and exit

Env: TAG_SKIP_AUDIT=1 skips the audit gate (use only on a tree you just audited).
EOF
}

PUSH=0
case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
--push)
  PUSH=1
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

hdr "tag $TAG (from core.version)"

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

# Annotated (not lightweight) tag: release.sh's printed recipe uses -a, git-cliff and
# `git describe` expect the annotation, and it carries the tagger/date.
if git tag -a "$TAG" -m "$TAG"; then
  pass "tagged $TAG"
else
  fail "tag-release.sh: 'git tag -a $TAG' failed"
  exit 1
fi

# Moving MAJOR tag (vN) — the ref reusable-workflow callers pin to (RELEASE-STRATEGY.md
# §"Pinning reusable workflows"). Lightweight and FORCE-moved to each new vN.x so callers
# get patch/minor guard improvements without a manual bump, while staying deterministic
# between releases (unlike @main). Advancing it here, in the one release step, is what
# keeps it from ever drifting from the release it should point at.
MAJOR="v${VERSION%%.*}"
if git tag -f "$MAJOR" "$TAG^{commit}" >/dev/null; then
  pass "moved major tag $MAJOR → $TAG"
else
  fail "tag-release.sh: could not move major tag $MAJOR"
  exit 1
fi

if ((PUSH)); then
  hdr "push tags $TAG + $MAJOR → origin"
  # TAGS ONLY — never `git push origin main`. main is a PROTECTED branch (required
  # status checks), so a direct branch push is rejected and the release COMMIT must
  # land via a PR (as v2.0.0 did, #95). Tags are not branch-protected, so we push the
  # immutable vX.Y.Z and force-move the vN alias here; the commit goes up with the PR.
  if git push origin "$TAG" && git push -f origin "$MAJOR"; then
    pass "pushed $TAG and moved $MAJOR → $TAG"
  else
    fail "tag-release.sh: tag push failed — re-push manually: git push origin $TAG && git push -f origin $MAJOR"
    exit 1
  fi
  printf '\n%s──────── %s released (tags pushed) ────────%s\n' "$c_blu" "$TAG" "$c_rst"
  cat <<EOF
  NOTE: --push tagged the PRE-merge commit. main is protected, so the commit lands via a
  PR — which adds a merge commit, leaving these tags one behind main's HEAD ('git describe'
  shows $TAG-1-g…). After the PR merges, RE-POINT both at the merged tip for a clean tag:

  1. land the commit:  git push --no-follow-tags origin HEAD:release/$TAG
       gh pr create --base main --head release/$TAG --title "release $TAG"
       # merge with a MERGE commit (not squash)
  2. re-point AFTER it merges:
       git fetch origin
       git tag -fa $TAG origin/main -m $TAG && git tag -f $MAJOR origin/main
       git push -f origin $TAG ; git push -f origin $MAJOR   # ';' not '&&' — independent
  3. fan out: ./scripts/sync-core.sh     # or let sync-fanout.yml open the PRs on release

  (Tip: skip PUSH=1 and follow the 'make tag' recipe below — it tags the merged tip from
  the start, so there's nothing to re-point.)
EOF
else
  printf '\n%s──────── %s tagged locally ────────%s\n' "$c_blu" "$TAG" "$c_rst"
  cat <<EOF
  review:  git show $TAG

  Ship IN THIS ORDER — land the commit FIRST, then tag the MERGED tip. main is protected,
  so the commit lands via a PR (a merge commit); tagging only AFTER that, at origin/main,
  keeps the tag on main's HEAD and 'git describe' clean. (Tagging before the merge leaves
  the tag one commit behind and needs a re-point — the trap PUSH=1 falls into.)

  --no-follow-tags below is LOAD-BEARING: $TAG already exists locally, and with
  \`push.followTags = true\` set a plain push carries it to origin — putting the tag on the
  PRE-merge commit and firing release.yml + sync-fanout.yml right then, which lands you in
  the very PUSH=1 state this ordering avoids.

  1. land the commit:
       git push --no-follow-tags origin HEAD:release/$TAG
       gh pr create --base main --head release/$TAG --title "release $TAG"
       # merge with a MERGE commit (not squash)
  2. tag the merged tip AFTER the PR merges:
       git fetch origin
       git tag -fa $TAG origin/main -m $TAG
       git tag -f  $MAJOR origin/main
       git push origin $TAG ; git push -f origin $MAJOR   # ';' not '&&' — independent pushes
  3. fan out: ./scripts/sync-core.sh     # or let sync-fanout.yml open the PRs on release
EOF
fi
