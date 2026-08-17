#!/usr/bin/env bash
# scripts/gen-release-notes.sh
# ──────────────────────────────────────────────────────────────────────────────
# Draft a GitHub Release body for an OS repo from its Conventional Commits — the
# grouped, curated alternative to `gh release create --generate-notes` (a raw PR list).
# It is the first-party twin of Core's `make release-notes` (cliff.toml): the SAME
# grouping and one-bullet-per-commit shape, but pure git + awk so it needs NO git-cliff
# binary — honouring the fleet's "no third-party CI tool we can't pin" discipline (the
# same reason zizmor stayed deferred). auto-tag.sh calls it in its --release path, with a
# graceful fall back to gh's auto-generated notes when a range has no conventional commits.
#
# Usage: gen-release-notes.sh <repo-path> <from-ref-or-empty> <to-ref>
#   from-ref empty → all history up to <to-ref> (a repo's first release)
# Prints the markdown body to stdout. Exit 0 WITH output on success; exit 0 with NO output
# when the range holds no conventional commits (the caller then falls back). 2 = usage.
#
# WHERE THE TWIN STOPS BEING A TWIN — one axis, and it is outside both callers' contract.
# Given a range that CROSSES AN INTERMEDIATE TAG, git-cliff segments its output per release:
# `v4.7.0..v4.9.0` renders three blocks (one each for v4.7.1, v4.8.0, v4.9.0), so headings
# repeat and "### Bug Fixes" can appear three times. This script has no notion of a release
# boundary and flattens the whole range into ONE set of groups. Neither caller ever asks for
# such a range — `make release-notes` passes the commits since the last `release vX` commit,
# and auto-tag.sh passes <last-tag>..<new-tag> — so on every range either tool is actually
# given, the two agree exactly (verified against git-cliff 2.13.1: identical structure,
# group order and bullets over v4.8.0..v4.9.0 and a synthetic all-groups repo). Documented
# rather than implemented: teaching awk to segment by tag would add real complexity for a
# shape no caller produces. If a multi-tag range is ever wanted, use git-cliff itself.
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO="${1:?usage: gen-release-notes.sh <repo-path> <from-ref-or-empty> <to-ref>}"
FROM="${2-}"
TO="${3:?usage: gen-release-notes.sh <repo-path> <from-ref-or-empty> <to-ref>}"

range="$TO"
[ -n "$FROM" ] && range="$FROM..$TO"

# Oldest-first (cliff sort_commits=oldest), no merges, "<full-sha> <subject>". %s is the
# subject only — a Conventional Commit's `type(scope): summary`. The FULL %H (not %h) so
# the display SHA is a deterministic truncate-to-7 like cliff's `commit.id | truncate(7)`,
# never git's auto-lengthened abbreviation. Split on whitespace in awk (sha = first token,
# subject = the rest) — portable, no exotic -F byte.
notes="$(
  git -C "$REPO" log "$range" --no-merges --reverse --format='%H %s' 2>/dev/null | awk '
    # Map a subject to a group, mirroring cliff.toml commit_parsers (first match wins,
    # in order). Each pattern requires the Conventional-Commit delimiter after the type
    # — an optional `(scope)`, optional breaking `!`, then `:` — so ordinary prose that
    # merely starts with a type word ("fixing a flaky test") is NOT grouped but DROPPED,
    # matching git-cliff conventional_commits + filter_unconventional. "" = drop.
    function group(m) {
      if (m ~ /^feat(\([^)]*\))?!?:/)       return "Features"
      if (m ~ /^fix(\([^)]*\))?!?:/)        return "Bug Fixes"
      if (m ~ /^perf(\([^)]*\))?!?:/)       return "Performance"
      if (m ~ /^refactor(\([^)]*\))?!?:/)   return "Refactoring"
      if (m ~ /^docs(\([^)]*\))?!?:/)       return "Documentation"
      if (m ~ /^test(\([^)]*\))?!?:/)       return "Tests"
      if (m ~ /^(ci|build)(\([^)]*\))?!?:/) return "CI / Build"
      if (m ~ /^chore\(release\)!?:/)       return ""              # skip release commits
      if (m ~ /^chore\(deps\)!?:/)          return "Dependencies"
      if (m ~ /^chore(\([^)]*\))?!?:/)      return "Chores"
      if (m ~ /^style(\([^)]*\))?!?:/)      return "Styling"
      return ""                                                    # filter_unconventional
    }
    BEGIN {
      n = split("Features|Bug Fixes|Performance|Refactoring|Documentation|Tests|CI / Build|Dependencies|Chores|Styling", ORDER, "|")
    }
    {
      msg = substr($0, length($1) + 2)                       # everything after "<sha> "
      g = group(msg)
      if (g == "") next
      sha = substr($1, 1, 7)                                 # cliff: commit.id | truncate(7) — always 7
      # Strip the Conventional-Commit prefix before rendering. cliff.toml sets
      # conventional_commits = true, which makes git-cliff parse each subject and expose
      # `commit.message` as the DESCRIPTION alone — type, scope and the breaking `!` are
      # parsed off into commit.scope/commit.breaking. So `{{ commit.message | upper_first }}`
      # renders "Point core-freshness at the released tag", never "Fix(ci): point …".
      # Keeping the prefix here both repeated the group heading ("Bug Fixes" → "Fix(ci):")
      # and upper-cased the type into a non-Conventional "Fix(ci):". group() has already
      # proven the subject starts with a known type + delimiter, so this strip cannot eat
      # ordinary prose. A subject that is nothing BUT a prefix ("refactor:") is DROPPED, not
      # rendered as an empty bullet: git-conventional requires a description, so git-cliff
      # fails to parse it and filter_unconventional discards it — verified against the real
      # binary (2.13.1), which emits no Refactoring group at all for that input.
      breaking = (msg ~ /^[a-z]+(\([^)]*\))?!:/)
      sub(/^[a-z]+(\([^)]*\))?!?:[ \t]*/, "", msg)
      if (msg == "") next
      msg = toupper(substr(msg, 1, 1)) substr(msg, 2)        # cliff: message | upper_first
      # DELIBERATE DIVERGENCE from cliff.toml, and the only one: git-cliff would render a
      # breaking commit identically to a normal one, because this template interpolates only
      # `commit.message` and never `commit.breaking`. Dropping the prefix is what would make
      # that invisible here too — `feat!: …` and `feat: …` collapse to the same bullet — and a
      # release-notes draft is the one document where a breaking change must not be silent
      # (it is what drives the SemVer major bump). Mark it instead of losing it.
      if (breaking) msg = "**BREAKING** " msg
      bucket[g] = bucket[g] "- " msg " (" sha ")\n"
      seen[g] = 1
    }
    END {
      first = 1
      for (i = 1; i <= n; i++) {
        g = ORDER[i]
        if (!seen[g]) continue
        if (!first) printf "\n"
        first = 0
        printf "### %s\n\n%s", g, bucket[g]
      }
    }
  '
)"

[ -n "$notes" ] || exit 0
printf '%s\n' "$notes"
