#!/usr/bin/env bash
# scripts/fleet-coverage.sh — the gate x repo coverage register (#607)
# ──────────────────────────────────────────────────────────────────────────────
# WHICH REPO SATISFIES WHICH GATE, AND HOW. Coverage used to be inferred by reading the
# `uses:` lines in each repo's workflows — and that inference is WRONG for any repo that
# satisfies a gate its own way. It has misfired twice, identically, both times in good faith:
#
#   * dotgibson/dotfiles-MacBook#154 — the RETURN-trap gate arrived in lint-call.yml; MacBook
#     does not call it; the rule had in fact been ported by hand.
#   * dotgibson/dotfiles-MacBook#178 — the provision-stub job arrived in bootstrap-test.yml;
#     MacBook is not a caller. But provision() WAS already gated there, on its macOS leg via a
#     BOOTSTRAP_BREW seam. The issue's central premise was false and nothing discoverable
#     contradicted it.
#
# Same failure mode, two gates apart, because a rollout audit had no way to tell
# "not covered" from "covered elsewhere".
#
# DERIVED, NOT HAND-MAINTAINED, and that is the load-bearing decision. This repo has been
# burned by frozen counts before — one commit fixed ELEVEN stale ones (#519) — and
# RELEASE-RUNBOOK.md sets the precedent in as many words: "count them rather than trusting a
# number frozen into this doc". So the `reusable` cells are read from each repo's actual
# `uses:` lines at run time, and only the cells that CANNOT be derived are declared.
#
# THE DECLARATION FILE. A repo that does not call a reusable workflow states why, in
# .github/core-gates.txt, one line per gate:
#
#     <gate> own <how it is satisfied here>
#     <gate> none <why this repo does not need it>
#
# Only the exceptions need a line; anything calling the reusable is derived. That keeps the
# file short enough to stay true, and it is the whole value of the register: a rollout then
# reads as "who is not yet covered AND has not said why", which is the question an audit is
# actually asking.
#
# Usage:
#   ./scripts/fleet-coverage.sh              # markdown table on stdout
#   ./scripts/fleet-coverage.sh --check      # exit 1 if any cell is undeclared
# Env: REPOS_ROOT (default: parent of this repo)
set -uo pipefail
HERE="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/scripts/lib/common.sh"

REPOS_ROOT="${REPOS_ROOT:-$(cd "$HERE/.." && pwd)}"
CHECK=0
for a in "$@"; do
  case "$a" in
  --check) CHECK=1 ;;
  -h | --help)
    sed -n '2,40p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *)
    echo "unknown arg: $a" >&2
    exit 2
    ;;
  esac
done

# The gates: every reusable workflow Core publishes. Derived from the tree, not a list, so a
# new reusable workflow joins the register the moment it exists — which is the property that
# makes "a new gate cannot ship without each repo declaring a position" true.
GATES=()
for f in "$HERE"/.github/workflows/*.yml; do
  grep -q '^on:' "$f" 2>/dev/null || true
  grep -qE '^[[:space:]]*workflow_call:' "$f" 2>/dev/null && GATES+=("$(basename "$f" .yml)")
done
# notify-failure-call is infrastructure the sweeps call internally, not a per-repo gate.
_g=()
for g in "${GATES[@]}"; do [[ "$g" == notify-failure-call ]] || _g+=("$g"); done
GATES=("${_g[@]}")

REPOS=()
while IFS= read -r r; do [[ -n "$r" ]] && REPOS+=("$r"); done < <(
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$HERE/scripts/os-repos.txt" 2>/dev/null
)

_cell() { # _cell <repo-dir> <gate> → "reusable" | "own:<why>" | "none:<why>" | ""
  local d="$1" g="$2" decl
  if [[ -d "$d/.github/workflows" ]] &&
    grep -rqE "dotgibson/dotfiles-core/\.github/workflows/${g}\.ya?ml@" "$d/.github/workflows" 2>/dev/null; then
    printf 'reusable'
    return 0
  fi
  decl="$(sed -e 's/#.*//' "$d/.github/core-gates.txt" 2>/dev/null |
    awk -v g="$g" '$1==g { $1=""; sub(/^[[:space:]]+/,""); print; exit }')"
  [[ -n "$decl" ]] && printf '%s' "$decl"
}

rows=""
notes=""
missing=0
present=0
n=0
for repo in "${REPOS[@]}"; do
  dir="$(resolve_repo_dir "$REPOS_ROOT" "$repo")" || dir="$REPOS_ROOT/$repo"
  [[ -d "$dir/.git" ]] || continue
  present=$((present + 1))
  line="| \`${repo#dotfiles-}\` |"
  for g in "${GATES[@]}"; do
    c="$(_cell "$dir" "$g")"
    case "$c" in
    reusable) line="$line reusable |" ;;
    "")
      line="$line **undeclared** |"
      missing=$((missing + 1))
      ;;
    *)
      # A declared exception. The cell carries the VERDICT and a footnote marker; the
      # reasoning goes below the table, or a nine-row table becomes unreadable and stops
      # being consulted — which is the failure this register exists to prevent.
      n=$((n + 1))
      line="$line ${c%% *}[^$n] |"
      notes="${notes}[^$n]: \`${repo#dotfiles-}\` / \`$g\` — ${c#* }
"
      ;;
    esac
  done
  rows="$rows$line
"
done

if ((CHECK)); then
  if ((present == 0)); then
    echo "fleet-coverage: no sibling repo checked out — nothing to check" >&2
    exit 0
  fi
  if ((missing)); then
    echo "fleet-coverage: $missing gate x repo cell(s) undeclared" >&2
    printf '%s' "$rows" | grep -F '**undeclared**' >&2
    exit 1
  fi
  echo "fleet-coverage: every gate x repo cell is declared ($present repo(s) x ${#GATES[@]} gate(s))"
  exit 0
fi

hdr_row="| repo |"
sep_row="| --- |"
for g in "${GATES[@]}"; do
  hdr_row="$hdr_row \`${g}\` |"
  sep_row="$sep_row --- |"
done
printf '%s\n%s\n%s' "$hdr_row" "$sep_row" "$rows"
[[ -n "$notes" ]] && printf '\n%s' "$notes"
