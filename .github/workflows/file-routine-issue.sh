#!/usr/bin/env bash
# .github/workflows/file-routine-issue.sh
# ──────────────────────────────────────────────────────────────────────────────
# File a Claude routine's report as a DEDUPLICATED GitHub issue: if an open issue
# with the given title already exists, append the report as a comment; otherwise
# open a new one. Keeps a weekly bot from stacking duplicate issues. Invoked by
# .github/workflows/claude-routines.yml via `bash …` (so it needs no exec bit).
#
# Usage: file-routine-issue.sh <issue-title> <report-file>
# Requires: gh (preinstalled on GitHub runners) + GH_TOKEN in the environment.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

title="${1:?usage: file-routine-issue.sh <title> <report-file>}"
report="${2:?usage: file-routine-issue.sh <title> <report-file>}"

if [ ! -s "$report" ]; then
  echo "::warning::routine produced an empty report ($report) — nothing to file"
  exit 0
fi

# Compose the issue body: a dated heading, the report, and a report-first footer.
body="${RUNNER_TEMP:-/tmp}/routine-issue-body.md"
{
  printf '## %s — %s\n\n' "$title" "$(date -u +%Y-%m-%d)"
  cat "$report"
  printf '\n_Filed by the claude-routines workflow. Report-first: review and act — nothing was changed._\n'
} >"$body"

# gh search is fuzzy, so re-check the title exactly before deciding to dedup.
existing="$(gh issue list --state open --limit 200 --search "$title in:title" --json number,title \
  --jq '.[] | [.number, .title] | @tsv' | awk -F'\t' -v t="$title" '$2 == t {print $1; exit}')"

if [ -n "$existing" ]; then
  gh issue comment "$existing" --body-file "$body"
  echo "appended report to existing issue #$existing"
else
  gh issue create --title "$title" --body-file "$body"
fi
