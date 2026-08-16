#!/usr/bin/env bash
# scripts/release.sh — cut a Core release in one command (B9).
# ──────────────────────────────────────────────────────────────────────────────
# Releasing was a manual, drift-prone TWO-file edit (bump core.version, then move
# CHANGELOG's [Unreleased] under a dated heading), caught only REACTIVELY by the audit's
# version/CHANGELOG coherence gate. This does both mechanically, then runs the audit so a
# release is proven green BEFORE it's tagged and fanned out to the eight OS repos.
#
# It deliberately does NOT commit, tag, or push — those are the operator's call. It edits
# the two files, runs the gate, and prints the exact git commands to finish. Safe to
# inspect with `git diff` and revert if anything looks off.
#
# Usage:
#   ./scripts/release.sh X.Y.Z          # bump to a clean SemVer release
#   make release VERSION=X.Y.Z
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

usage() {
  cat <<'EOF'
usage: release.sh X.Y.Z

Cut a Core release: bump core.version, move CHANGELOG's [Unreleased] under a dated
## [vX.Y.Z] heading (opening a fresh [Unreleased]), then run the audit. Does NOT
commit/tag/push — it prints the git commands to finish.
EOF
}

VERSION="${1:-}"
case "$VERSION" in
-h | --help)
  usage
  exit 0
  ;;
"")
  fail "release.sh: a version is required (X.Y.Z)"
  usage >&2
  exit 2
  ;;
esac
# A RELEASE stamp is a clean SemVer (no -prerelease) — the coherence gate requires a
# matching dated heading for exactly that shape. Reject anything else up front.
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "release.sh: '$VERSION' is not a clean SemVer release (expected X.Y.Z, no -suffix)"
  exit 2
fi

CHANGELOG="CHANGELOG.md"
VERFILE="core.version"
[[ -w "$VERFILE" && -w "$CHANGELOG" ]] || {
  fail "release.sh: $VERFILE or $CHANGELOG missing/unwritable"
  exit 1
}

# Idempotency / double-release guard: refuse if this version already has a heading.
if grep -qE "^## +\[v?${VERSION//./\\.}\]" "$CHANGELOG"; then
  fail "release.sh: CHANGELOG already has a heading for $VERSION — already released?"
  exit 1
fi
grep -qE '^## +\[[Uu]nreleased\]' "$CHANGELOG" || {
  fail "release.sh: no '## [Unreleased]' section in $CHANGELOG to promote"
  exit 1
}

DATE="$(date +%Y-%m-%d)"
OLD="$(tr -d '[:space:]' <"$VERFILE")"
hdr "release $OLD → $VERSION ($DATE)"

# 1. core.version stamp.
printf '%s\n' "$VERSION" >"$VERFILE"
pass "core.version → $VERSION"

# 2. CHANGELOG: rename the FIRST [Unreleased] to the dated release heading, and open a
#    fresh empty [Unreleased] above it. awk on the first match only (later text untouched).
tmp="$(mktemp "${CHANGELOG}.XXXXXX")" || {
  fail "release.sh: mktemp failed"
  exit 1
}
awk -v ver="$VERSION" -v date="$DATE" '
  !done && /^## +\[[Uu]nreleased\]/ {
    print "## [Unreleased]"
    print ""
    print "## [v" ver "] - " date
    done = 1
    next
  }
  { print }
' "$CHANGELOG" >"$tmp" && mv "$tmp" "$CHANGELOG"
pass "CHANGELOG.md: [Unreleased] → ## [v$VERSION] - $DATE (fresh [Unreleased] opened)"

# 3. prove it green before anyone tags it.
hdr "audit (release must be green before it fans out)"
if ./scripts/audit-core.sh --quiet; then
  pass "audit green"
else
  fail "audit FAILED — fix, or 'git checkout -- $VERFILE $CHANGELOG' to abort the release"
  exit 1
fi

printf '\n%s──────── release %s staged ────────%s\n' "$c_blu" "$VERSION" "$c_rst"
cat <<EOF
  review:  git diff

  NOTE: do NOT tag yet. A vX.Y.Z tag must only ever exist on a commit that is already on
  origin/main — a local tag on an unmerged commit can be carried to the remote by any
  push from this checkout (yours or a concurrent session's), firing release.yml and
  sync-fanout.yml against a commit main does not have. See RELEASE-RUNBOOK.md
  §"Why the tag comes last".

  1. commit:   make tag                  # commits $VERFILE + $CHANGELOG, creates NO tag
  2. land it:  git push origin HEAD:release/v$VERSION
               gh pr create --base main --head release/v$VERSION --title "release v$VERSION"
               # ...then merge it
  3. publish:  make publish              # tags the release commit on origin/main + pushes
  4. fan out:  sync-fanout.yml opens the vendor PRs on release
               (or ./scripts/sync-core.sh to do it by hand)
EOF
