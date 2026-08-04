#!/usr/bin/env bash
# scripts/freshness-dashboard.sh
# ──────────────────────────────────────────────────────────────────────────────
# Compose the weekly FLEET FRESHNESS DASHBOARD — one glanceable health board
# (markdown → stdout) that consolidates the fleet's otherwise-scattered signals:
#   • vendoring drift         (scripts/fleet-drift.sh)      — every OS repo on the latest Core tag?
#   • vendored-core integrity (scripts/core-integrity.sh)   — any repo's core/ hand-edited?
#   • zsh + nvim plugin pins  (update-*-plugins.sh --check) — are the pinned SHAs behind upstream?
# plus three LIVE cross-repo signals it queries from the GitHub API (best-effort — see below):
#   • own-tag release drift   — how many commits each repo has merged since its last release
#                               tag (distinct from core.lock drift: this is the repo's OWN
#                               unreleased work, a nudge to cut its next vX.Y.Z).
#   • open dependency PRs      — the live count of open Renovate PRs per repo (the dashboards
#                               below are the backlog; this is how much is waiting right now).
#   • judgment-layer issues    — links to each repo's open issues filed by the .claude routines
#                               (doc-audit, os-package-availability, coverage-gap, shell-review,
#                               methodology-review, showcase-accuracy, corpus-review, …), so the
#                               board REFERENCES those judgment signals rather than recomputing them.
# plus links to each repo's Renovate dependency dashboard and a note on the fleet App auth.
#
# A live signal that can't be fetched renders `?` — never a partial or garbage value: `gh
# api` copies an HTTP error BODY to stdout, so the helpers below gate on its exit code (see
# _gh_api). The search-backed signals are paced and retry a 403 once per run.
#
# It is a REPORTER, not a mutator, and never fails the build: each sub-check's output is
# embedded and its exit code becomes a ✅/⚠️ row. The three live signals need `gh` + a token;
# the workflow provides both, so they fill in CI — a local run without gh shows an
# "unavailable" note instead of failing. .github/workflows/freshness-dashboard.yml clones the
# fleet first and files this via file-routine-issue.sh (deduped by title — a weekly board that
# updates in place). Run locally with `make freshness-dashboard`.
#
# Usage:  ./scripts/freshness-dashboard.sh [--root DIR]
#   --root DIR   where the sibling OS repos live (default: dotfiles-core's parent)
# Exit: always 0 (a dashboard reports; the sub-gates enforce). 2 = usage error.
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
cd "$HERE" || exit 1
ROOT="$(cd "$HERE/.." && pwd)" # siblings of dotfiles-core by default
OWNER="${GITHUB_REPOSITORY_OWNER:-dotgibson}"

while [ $# -gt 0 ]; do
  case "$1" in
  --root) ROOT="${2:?--root needs a directory}"; shift 2 ;;
  -h | --help)
    cat <<'EOF'
freshness-dashboard.sh — compose the weekly fleet freshness dashboard (markdown → stdout).

  ./scripts/freshness-dashboard.sh              build the dashboard for the whole fleet
  ./scripts/freshness-dashboard.sh --root DIR   use DIR as the parent holding the repos

Consolidates vendoring drift, vendored-core integrity, and zsh/nvim plugin-pin freshness
with live GitHub signals (own-tag release drift, open dependency PRs, judgment-layer issue
links). Reporter only — never mutates, never fails the build; live signals need `gh` + a token.
EOF
    exit 0 ;;
  *) echo "freshness-dashboard: unknown arg: $1" >&2; exit 2 ;;
  esac
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run <outfile> <cmd...> — capture combined output, preserve the command's exit code.
run() { local out="$1"; shift; "$@" >"$out" 2>&1; }
badge() { if [ "$1" -eq 0 ]; then printf '✅ ok'; else printf '⚠️ attention'; fi; }

# The three live signals below are best-effort: they need `gh` + a token (the workflow has
# both). Without them the board still composes — the sections just print an "unavailable"
# note. Probe once so a local run degrades cleanly instead of erroring per call.
GH_OK=0
# An env token (GH_TOKEN/GITHUB_TOKEN — what the workflow provides) is sufficient for
# `gh api` and more reliable than `gh auth status`, whose exit/output varies by gh
# version; only fall back to `gh auth status` for local runs authed via stored creds.
if command -v gh >/dev/null 2>&1 &&
  { [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ] || gh auth status >/dev/null 2>&1; }; then
  GH_OK=1
fi

# Seconds between SEARCH-API calls, and the backoff unit for a rate-limited retry. The
# board fires ~24 search requests and GitHub's authenticated search ceiling is 30/minute,
# so a 3s pace lands ~20/min — under the primary limit with room for the secondary (burst)
# limiter that produced the 403 in the 2026-08-03 board. The plain REST calls in the
# release-drift table are NOT paced: core REST's budget is orders of magnitude larger and
# 36 sequential GETs never approach it. Both are overridable so the hermetic test in
# scripts/test-core.sh can drive the retry ladder without sleeping through it.
#
# DASH_RETRY_BUDGET is the ceiling on TOTAL backoff sleep for the whole run (see _gh_api):
# 60s leaves room for two full ladders — enough to ride out a normal ~60s secondary limit —
# while keeping the worst case nowhere near the workflow's 15-minute timeout.
: "${DASH_SEARCH_PACE:=3}"
: "${DASH_RETRY_BASE:=5}"
: "${DASH_RETRY_BUDGET:=60}"

# _gh_api <gh-api-args...> — gh's stdout ONLY when the call actually SUCCEEDED; empty
# output and a non-zero status otherwise.
#
# WHY this dance instead of `gh api … 2>/dev/null || true`: on an HTTP error gh SKIPS the
# --jq filter entirely and copies the raw response body to STDOUT ({"message":"Not
# Found",…,"status":"404"}), writing only its one-line summary (`gh: Not Found (HTTP 404)`)
# to stderr. So `2>/dev/null` silences the wrong stream and `|| true` discards the one
# reliable signal — the exit code — leaving the error JSON to masquerade as the value and
# defeating every `// empty` and every downstream emptiness guard. gh's status IS
# trustworthy (non-zero on any HTTP >= 400), so gate on it and drop stdout when it fails.
#
# 403/429 (the secondary rate limit) is the one answer worth waiting on — a 404 or 422 will
# never change — so it gets a widening backoff. TWO separate brakes stop that from eating
# the workflow's 15-minute budget, because they catch different failures:
#
#   • An EXHAUSTED ladder latches. Waiting demonstrably didn't help, and a secondary limit
#     is a property of the token rather than of this endpoint, so the remaining ~50 calls
#     give up immediately instead of re-laddering.
#   • Cumulative sleep is CAPPED (DASH_RETRY_BUDGET). A ladder that RECOVERS must not latch
#     — waiting worked, and a later limit deserves the same courtesy — but that alone is
#     unbounded: 24 search calls each hitting a fresh transient limit and recovering on the
#     last retry is 24 × (5+10+15) = 12 minutes of sleeping, with no ladder ever exhausted
#     to trip the first brake. The budget bounds the whole run instead of each ladder.
#
# Latching on ladder START would collapse both into one and is wrong: it turns the first
# recoverable blip into a permanent `?` for every later call.
#
# Both brakes are FILES, not variables: callers invoke this inside `$( )`, and a variable
# set in that subshell never reaches the parent, so every later call would re-ladder.
_gh_api() {
  local out rc try=0 spent
  while :; do
    out="$(gh api "$@" 2>"$TMP/gh.err")"
    rc=$?
    if [ "$rc" -eq 0 ]; then printf '%s\n' "$out"; return 0; fi
    grep -qE 'HTTP (403|429)' "$TMP/gh.err" || return 1
    [ -e "$TMP/rate-limited" ] && return 1
    try=$((try + 1))
    if [ "$try" -gt 3 ]; then : >"$TMP/rate-limited"; return 1; fi
    spent=0
    [ -f "$TMP/backoff-spent" ] && spent="$(cat "$TMP/backoff-spent")"
    spent=$((spent + try * DASH_RETRY_BASE))
    if [ "$spent" -gt "$DASH_RETRY_BUDGET" ]; then : >"$TMP/rate-limited"; return 1; fi
    printf '%s\n' "$spent" >"$TMP/backoff-spent"
    sleep $((try * DASH_RETRY_BASE))
  done
}

# gh_q <jq> <api-path> — the jq result on success; EMPTY output AND a non-zero status on
# any failure (never aborts, so a single unreachable/renamed/rate-limited repo can't sink
# the board). `// empty` still normalizes a missing/null field on a SUCCESSFUL response
# (e.g. `.[0].name` on a tagless repo) to empty output. The status is the other half of the
# contract: it lets a caller tell "the API answered: none" (rc 0, empty) apart from "we
# never got an answer" (rc non-zero, empty) — see the release-drift table below, whose
# "— (no tags)" verdict was previously asserted on evidence it did not have.
# GH_OK=0 keeps its degradation path: success, empty stdout, no call made.
gh_q() { [ "$GH_OK" -eq 1 ] || return 0; _gh_api "$2" --jq "$1 // empty"; }

run "$TMP/drift" ./scripts/fleet-drift.sh --root "$ROOT" --color never;    drift_st=$?
run "$TMP/integ" ./scripts/core-integrity.sh --root "$ROOT" --color never; integ_st=$?
run "$TMP/zsh"   ./scripts/update-plugins.sh --check;                      zsh_st=$?
run "$TMP/nvim"  ./scripts/update-nvim-plugins.sh --check;                 nvim_st=$?

# ── summary table ─────────────────────────────────────────────────────────────
printf '**Fleet health at a glance** — the weekly freshness signals in one board.\n\n'
printf '| Signal | Status |\n| --- | --- |\n'
printf '| Vendoring drift — every OS repo on the latest Core tag | %s |\n' "$(badge "$drift_st")"
printf "| Vendored \`core/\` integrity — no hand-edits | %s |\n" "$(badge "$integ_st")"
printf "| zsh plugin pins (\`zsh/45-plugins.zsh\`) | %s |\n" "$(badge "$zsh_st")"
printf "| nvim plugin pins (\`nvim/lazy-lock.json\`) | %s |\n" "$(badge "$nvim_st")"

detail() { # <summary-text> <output-file>
  printf '\n<details><summary>%s</summary>\n\n```text\n' "$1"
  if [ -s "$2" ]; then cat "$2"; else printf '(no output)\n'; fi
  printf '```\n\n</details>\n'
}
detail 'Vendoring drift — fleet-drift.sh' "$TMP/drift"
detail 'Core integrity — core-integrity.sh' "$TMP/integ"
detail 'zsh plugin pins — update-plugins.sh --check' "$TMP/zsh"
detail 'nvim plugin pins — update-nvim-plugins.sh --check' "$TMP/nvim"

# ── Renovate dependency dashboards (per repo) ─────────────────────────────────
# The wired fleet: the two standalone repos + web, the Core-vendoring OS repos
# (scripts/os-repos.txt), and htpx. dotfiles-Windows carries no core/ but is wired.
REPOS=(dotfiles-core dotfiles-Windows dotfiles-web)
while IFS= read -r r; do [ -n "$r" ] && REPOS+=("$r"); done \
  < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' scripts/os-repos.txt)
REPOS+=(htpx)

# search_count <query...> — total_count for a repo search; EMPTY output + a non-zero status
# on failure, so a caller prints `?` rather than a number it never received. Search is the
# most rate-limited API GitHub has and this board fires ~24 of these, so every call is paced
# (DASH_SEARCH_PACE) and _gh_api's ladder absorbs a burst 403. The pace lives HERE rather
# than in the two loops so there is one rule, instead of reasoning about which loop happens
# to hold the 13th call. Callers still gate on GH_OK and fall back to a plain link.
search_count() {
  [ "$GH_OK" -eq 1 ] || return 0
  sleep "$DASH_SEARCH_PACE"
  _gh_api -X GET search/issues -f "q=$*" --jq '.total_count // empty'
}

# ── Own-tag release drift (live) ──────────────────────────────────────────────
# Each repo's OWN unreleased work: commits merged since its last release tag. Distinct
# from vendoring drift (which tracks the Core tag) — this nudges each repo toward its next
# release. Compared against the default branch `main` (the whole fleet's default).
printf '\n## Own-tag release drift\n\n'
printf 'Commits each repo has merged since its last release tag — the repo'\''s own unreleased '
printf 'work (distinct from the vendoring drift above, which tracks the Core tag). A high count '
printf 'is a nudge to cut that repo'\''s next release.\n\n'
printf "In the live tables below, \`?\` means the API call itself failed (a rate limit or a "
printf 'transient error) — it is not a zero.\n\n'
if [ "$GH_OK" -eq 1 ]; then
  printf '| Repo | Latest release | Unreleased commits (main) |\n| --- | --- | --- |\n'
  for r in "${REPOS[@]}"; do
    # `releases/latest` 404s for a repo that has never published a release — that is the
    # NORMAL answer, not an error — so fall back to the plain tag list before concluding
    # anything. It is the FALLBACK's status that separates "this repo has no tags" from "we
    # couldn't ask": before the gh_q fix both looked identical (empty), a 404 body leaked
    # into `tag`, and the "— (no tags)" branch was unreachable for dotfiles-web.
    tag="$(gh_q '.tag_name' "repos/$OWNER/$r/releases/latest")"
    probe=$?
    if [ -z "$tag" ]; then
      tag="$(gh_q '.[0].name' "repos/$OWNER/$r/tags")"
      probe=$?
    fi
    if [ -n "$tag" ]; then
      ahead="$(gh_q '.ahead_by' "repos/$OWNER/$r/compare/$tag...main")"
      printf "| %s | \`%s\` | %s |\n" "$r" "$tag" "${ahead:-?}"
    elif [ "$probe" -eq 0 ]; then
      printf '| %s | — (no tags) | — |\n' "$r"
    else
      printf '| %s | ? | ? |\n' "$r"
    fi
  done
else
  printf "_Unavailable in this run (no \`gh\`/token) — populated by the workflow in CI._\n"
fi

# ── Dependency dashboards + live open-PR tally (Renovate) ──────────────────────
printf '\n## Dependency dashboards (Renovate)\n\n'
printf "Renovate keeps a per-repo dashboard issue; action/container pins land as grouped "
printf "\`ci(deps):\` PRs. **Open dep PRs** is how many are waiting right now.\n\n"
q='is%3Aissue+is%3Aopen+in%3Atitle+Dependency+Dashboard'
printf '| Repo | Open dep PRs | Dashboard |\n| --- | --- | --- |\n'
for r in "${REPOS[@]}"; do
  n='—'
  if [ "$GH_OK" -eq 1 ]; then
    # Empty now means the call FAILED — a real zero comes back as the string "0" — so `?`
    # is an honest cell rather than a guard a 403 body walks straight through.
    n="$(search_count "repo:$OWNER/$r is:pr is:open author:app/renovate")"
    n="${n:-?}"
  fi
  printf '| %s | %s | [dashboard](https://github.com/%s/%s/issues?q=%s) |\n' "$r" "$n" "$OWNER" "$r" "$q"
done

# ── Judgment-layer routine issues (live links) ────────────────────────────────
# The board REFERENCES the judgment signals (stale docs, coverage holes, package drift, …)
# rather than recomputing them: each is filed as an issue by its `.claude` routine. Author
# filter app/github-actions catches the routine reports (Renovate — app/renovate — is separate).
printf '\n## Judgment-layer routine issues\n\n'
printf "Open issues filed by the scheduled \`.claude\` routines (doc-audit, os-package-availability, "
printf 'coverage-gap, shell-review, methodology-review, showcase-accuracy, corpus-review, …) plus the '
printf 'automated health notices. This is where the stale-docs and coverage-hole signals live — the '
printf 'board links them rather than recomputing them.\n\n'
ri='is%3Aissue+is%3Aopen+author%3Aapp%2Fgithub-actions'
printf '| Repo | Open routine/automation issues |\n| --- | --- |\n'
for r in "${REPOS[@]}"; do
  link="https://github.com/$OWNER/$r/issues?q=$ri"
  cell="[open]($link)"
  if [ "$GH_OK" -eq 1 ]; then
    # This is the exact cell that rendered htpx's 403 body as markdown link text in the
    # 2026-08-03 board. `${n:-?}` also replaces a `[ -n "$n" ] && …` whose status leaked as
    # the if-block's status.
    n="$(search_count "repo:$OWNER/$r is:issue is:open author:app/github-actions")"
    cell="[${n:-?}]($link)"
  fi
  printf '| %s | %s |\n' "$r" "$cell"
done

# ── Fleet auth (GitHub App — nothing to expire) ───────────────────────────────
printf '\n## Fleet auth\n\n'
printf "Cross-repo automation authenticates via a GitHub App that mints short-lived, scoped "
printf 'installation tokens at run time (GITHUB-APP-AUTH.md) — there are no long-lived PATs to '
printf 'expire, so nothing to probe here.\n'

exit 0
