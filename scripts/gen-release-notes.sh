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
      msg = toupper(substr(msg, 1, 1)) substr(msg, 2)        # cliff: message | upper_first
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
