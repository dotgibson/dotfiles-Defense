#!/usr/bin/env bash
# scripts/freshness-dashboard.sh
# ──────────────────────────────────────────────────────────────────────────────
# Compose the weekly FLEET FRESHNESS DASHBOARD — one glanceable health board
# (markdown → stdout) that consolidates the fleet's otherwise-scattered signals:
#   • vendoring drift         (scripts/fleet-drift.sh)      — every OS repo on the latest Core tag?
#   • vendored-core integrity (scripts/core-integrity.sh)   — any repo's core/ hand-edited?
#   • zsh + nvim plugin pins  (update-*-plugins.sh --check) — are the pinned SHAs behind upstream?
# plus links to each repo's Renovate dependency dashboard and a note on the fleet App auth.
#
# It is a REPORTER, not a mutator, and never fails the build: each sub-check's output is
# embedded and its exit code becomes a ✅/⚠️ row. .github/workflows/freshness-dashboard.yml
# clones the fleet first and files this via file-routine-issue.sh (deduped by title — a
# weekly board that updates in place). Run locally with `make freshness-dashboard`.
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
  -h | --help) sed -n '2,19p' "$0"; exit 0 ;;
  *) echo "freshness-dashboard: unknown arg: $1" >&2; exit 2 ;;
  esac
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run <outfile> <cmd...> — capture combined output, preserve the command's exit code.
run() { local out="$1"; shift; "$@" >"$out" 2>&1; }
badge() { if [ "$1" -eq 0 ]; then printf '✅ ok'; else printf '⚠️ attention'; fi; }

run "$TMP/drift" ./scripts/fleet-drift.sh --root "$ROOT" --color never;    drift_st=$?
run "$TMP/integ" ./scripts/core-integrity.sh --root "$ROOT" --color never; integ_st=$?
run "$TMP/zsh"   ./scripts/update-plugins.sh --check;                      zsh_st=$?
run "$TMP/nvim"  ./scripts/update-nvim-plugins.sh --check;                 nvim_st=$?

# ── summary table ─────────────────────────────────────────────────────────────
printf '**Fleet health at a glance** — the weekly freshness signals in one board.\n\n'
printf '| Signal | Status |\n| --- | --- |\n'
printf '| Vendoring drift — every OS repo on the latest Core tag | %s |\n' "$(badge "$drift_st")"
printf "| Vendored \`core/\` integrity — no hand-edits | %s |\n" "$(badge "$integ_st")"
printf "| zsh plugin pins (\`zsh/plugins.zsh\`) | %s |\n" "$(badge "$zsh_st")"
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

printf '\n## Dependency dashboards (Renovate)\n\n'
printf "Renovate keeps a per-repo dashboard issue; action/container pins land as grouped \`ci(deps):\` PRs.\n\n"
q='is%3Aissue+is%3Aopen+in%3Atitle+Dependency+Dashboard'
for r in "${REPOS[@]}"; do
  printf -- '- [%s](https://github.com/%s/%s/issues?q=%s)\n' "$r" "$OWNER" "$r" "$q"
done

# ── Fleet auth (GitHub App — nothing to expire) ───────────────────────────────
printf '\n## Fleet auth\n\n'
printf "Cross-repo automation authenticates via a GitHub App that mints short-lived, scoped "
printf 'installation tokens at run time (GITHUB-APP-AUTH.md) — there are no long-lived PATs to '
printf 'expire, so nothing to probe here.\n'

exit 0
