#!/usr/bin/env bash
# detections/htpx-corpus.sh — materialise the PINNED dotgibson/htpx corpus and print the
# path to it. The fetch half of the two Defense<->htpx gates; it asserts nothing itself.
# ──────────────────────────────────────────────────────────────────────────────
# WHY IT IS A SCRIPT AND NOT TWO COPIES OF THE SAME curl. check-htpx-pairing.sh and
# navigator/gen-htpx-coverage.sh both need the corpus at the pinned sha, and a fetch
# duplicated across two gates is a third thing to drift. This is the one place that knows
# how to get it, so both gates provably read the SAME tree.
#
# WHY git AND NOT A TARBALL. detections/htpx.pin names a commit. Fetching it with git means
# git verifies every object hash on the way in and `rev-parse HEAD` proves what landed —
# so the integrity check the ATT&CK pin needs an explicit sha256 for is already done here,
# by construction. A codeload tarball would have to be trusted or separately digested, and
# GitHub does not promise its compression is byte-stable across time.
#
#   htpx-corpus.sh            # print the corpus path, fetching into the cache if needed
#
# Informational output goes to STDERR; STDOUT is the path and nothing else, so callers can
# write `corpus="$(htpx-corpus.sh)"`.
#
# OFFLINE / AIR-GAPPED. Same contract as check-attack-tags.sh's ATTACK_DATA_DIR: point
# HTPX_CORPUS_DIR at a cache directory that already contains a <sha>/ checkout and nothing
# is fetched. That is also how you test this repo against an htpx branch that has not
# merged yet.
#
# Exit: 0 = corpus ready, path on stdout;  1 = bad pin, fetch failed, or sha mismatch;
#       2 = bad invocation
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

if [[ $# -gt 0 ]]; then
  echo "htpx-corpus: unexpected argument '$1'" >&2
  echo "usage: htpx-corpus.sh" >&2
  exit 2
fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
PIN="$HERE/htpx.pin"

[[ -r "$PIN" ]] || {
  echo "::error::missing: $PIN" >&2
  exit 1
}

pin_field() { awk -F'\t' -v k="$1" '!/^[[:space:]]*#/ && $1==k {print $2; exit}' "$PIN"; }
REPO_SLUG="$(pin_field repo)"
SHA="$(pin_field sha)"

# Name the PIN FIELD in the error, not the shell variable — the reader has to go edit the
# file, and "missing repo_slug" sends them looking for a key that does not exist.
missing=()
[[ -n "$REPO_SLUG" ]] || missing+=("repo")
[[ -n "$SHA" ]] || missing+=("sha")
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "::error::$PIN is missing required field(s): ${missing[*]}" >&2
  echo "  expected tab-separated rows: repo / branch / sha / version / tag" >&2
  exit 1
fi

# A full 40-char sha, checked before use. An abbreviated sha would still fetch, but
# `rev-parse HEAD` returns the full form and the equality check below would fail with a
# confusing "mismatch" on a pin that is merely short. Say the real reason instead.
if [[ ! "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::$PIN: sha must be a full 40-character commit sha, got '$SHA'" >&2
  exit 1
fi

CACHE_DIR="${HTPX_CORPUS_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-Defense/htpx}"
DEST="$CACHE_DIR/$SHA"

# The corpus is usable if the entry directories are there. Deliberately NOT "if the
# directory exists": an interrupted fetch leaves a directory behind, and treating that as
# a cache hit would run both gates against a half-tree and report phantom breakage.
corpus_ok() { [[ -d "$DEST/entries/red" && -d "$DEST/entries/blue" ]]; }

if ! corpus_ok; then
  if [[ -e "$DEST" ]]; then
    echo "htpx-corpus: cached checkout at $DEST is incomplete — refetching" >&2
    rm -rf "$DEST"
  fi
  command -v git >/dev/null 2>&1 || {
    echo "::error::git not found — htpx-corpus.sh needs it to fetch the pinned corpus" >&2
    exit 1
  }
  echo "htpx-corpus: fetching $REPO_SLUG at ${SHA:0:12} (cached at $CACHE_DIR)" >&2
  mkdir -p "$DEST" || exit 1
  # Fetch the exact commit rather than cloning a branch: a branch tip moves, and this must
  # land on the pinned commit or fail. --depth 1 because no gate reads history.
  if ! git -C "$DEST" init -q 2>/dev/null ||
    ! git -C "$DEST" fetch -q --depth 1 "https://github.com/$REPO_SLUG" "$SHA" 2>/dev/null ||
    ! git -C "$DEST" checkout -q FETCH_HEAD 2>/dev/null; then
    echo "::error::could not fetch $REPO_SLUG at $SHA" >&2
    echo "  Either the commit is not reachable (force-push? wrong sha in $PIN?) or the" >&2
    echo "  network is unavailable. To run offline, pre-seed the cache:" >&2
    echo "    HTPX_CORPUS_DIR=<dir>, with <dir>/$SHA/ already checked out" >&2
    rm -rf "$DEST"
    exit 1
  fi
fi

# The integrity check. A pre-seeded HTPX_CORPUS_DIR is checked by exactly the same rule as
# a fresh fetch — an offline escape hatch that skipped verification would be a hole in
# both gates, not a convenience.
if [[ -d "$DEST/.git" ]]; then
  got="$(git -C "$DEST" rev-parse HEAD 2>/dev/null)"
  if [[ "$got" != "$SHA" ]]; then
    echo "::error::$DEST is checked out at $got, but $PIN says $SHA" >&2
    echo "  Do NOT edit the pin to match — that trusts whatever happens to be cached." >&2
    echo "  Remove the directory and let it refetch." >&2
    exit 1
  fi
elif [[ -z "${HTPX_CORPUS_DIR:-}" ]]; then
  # Only reachable if a fetch reported success but left no repository behind.
  echo "::error::$DEST has no .git — cannot verify it is the pinned commit" >&2
  exit 1
else
  # A pre-seeded plain directory (an export, a copy) cannot be verified against the pin.
  # Allowed, because the air-gapped case is real, but never silently: the path name is the
  # only thing tying it to the sha, and the operator has to own that.
  echo "htpx-corpus: WARNING — $DEST is not a git checkout, so it cannot be verified" >&2
  echo "  against $PIN. Trusting HTPX_CORPUS_DIR's layout. Unset it to fetch and verify." >&2
fi

corpus_ok || {
  echo "::error::$DEST has no entries/red + entries/blue — is this really the htpx corpus?" >&2
  exit 1
}

printf '%s\n' "$DEST"
