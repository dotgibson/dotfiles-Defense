#!/usr/bin/env bash
# .github/workflows/verify-routine-report.sh
# ──────────────────────────────────────────────────────────────────────────────
# Fact-check a Claude routine's report against the repository BEFORE it is filed as an
# issue, and append a verification block recording what was checked.
#
# WHY. The routines produce judgment work, and judgment reports get filed verbatim with
# the authority of a green automated run. In practice they misstate checkable facts: a
# real /detection-review report cited `harbor/harbor_artifact_deleted.yml` (the rule lives
# in `registry/`, not `harbor/`) and opened with a corpus size that no longer matched the
# tree. Neither is a judgment error — both are mechanically checkable, and neither was
# caught, because nothing checked.
#
# WHAT IT CHECKS. Only things that can be decided deterministically:
#   • every backticked repo path the report cites, resolved against the git index
#   • ground-truth corpus counts, stamped into the issue so a stale claim is visible
#
# WHAT IT DELIBERATELY DOES NOT DO. It does not judge the findings — that is the routine's
# job and a human's. It also does not fail on ambiguity. A citation with no match anywhere
# is usually a PROPOSED new rule (these reports propose files by path, and last week's
# proposals are this week's files), so those are listed, not fatal. The gate fires only on
# a citation that is provably wrong: the file exists, at a different path than claimed.
# A gate that cried wolf on correct reports would be switched off within a month.
#
# Usage: verify-routine-report.sh <report-file> [repo-root]
# Exit:  0 = nothing provably wrong (report may still carry listed warnings)
#        1 = at least one citation is provably wrong; caller should mark the run failed
# ──────────────────────────────────────────────────────────────────────────────
# shellcheck disable=SC2016
# Single-quoted backticks are load-bearing here in two ways, and both must stay literal:
# the extraction regex matches markdown code spans, and the report block this script
# appends IS markdown. Every interpolated value is a double-quoted printf argument.
set -uo pipefail

report="${1:?usage: verify-routine-report.sh <report-file> [repo-root]}"
root="${2:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

[ -s "$report" ] || {
  echo "::warning::report is empty ($report) — nothing to verify"
  exit 0
}

cd "$root" || exit 1

tracked="$(mktemp)"
trap 'rm -f "$tracked"' EXIT
git ls-files >"$tracked" 2>/dev/null || : >"$tracked"

# ── extract cited paths ───────────────────────────────────────────────────────
# Backticked tokens that look like a repo path. Anchoring on backticks is what keeps this
# quiet: these reports write paths in code spans and prose in plain text, so free text
# mentioning "the sigma corpus" is not mistaken for a citation.
mapfile -t cites < <(
  grep -oE '`[A-Za-z0-9_][A-Za-z0-9_./*-]*\.(yml|yaml|md|conf|kql|lucene|json|sh|zsh|toml|tsv)`' "$report" |
    tr -d '`' | sort -u
)

verified=0
proposed=()
mislocated=()
unresolved=()

# A citation is "proposed" when its line reads as a proposal rather than a reference.
# Checked on the whole line, because these reports write "Author `path`" / "New `path`"
# / "Proposed change: … `path`".
_is_proposed() {
  grep -F -- "$1" "$report" |
    grep -qiE 'author|propose|proposed change|new rule|new file|create|would add|to be written'
}

for p in "${cites[@]}"; do
  # 1. exists exactly as written
  if [ -e "$p" ]; then
    verified=$((verified + 1))
    continue
  fi

  # 2. a glob that matches something (reports cite e.g. siem/sentinel/*.yaml)
  case "$p" in
  *'*'*)
    if compgen -G "$p" >/dev/null 2>&1; then
      verified=$((verified + 1))
      continue
    fi
    ;;
  esac

  # 3. cited relative to a subtree — a tracked path ENDS with the citation. This is the
  #    common, correct case: the reports write `credential_access/foo.yml` for a rule that
  #    lives at `detections/sigma/credential_access/foo.yml`.
  esc="$(printf '%s' "$p" | sed 's/[][\.*^$/]/\\&/g')"
  if grep -qE "(^|/)${esc}$" "$tracked"; then
    verified=$((verified + 1))
    continue
  fi

  # 4. proposals are not facts about the tree — do not hold them to one
  if _is_proposed "$p"; then
    proposed+=("$p")
    continue
  fi

  # 5. the basename exists, but not where the report says. THIS is the provably-wrong
  #    case, and the only one that fails the gate.
  base="${p##*/}"
  escb="$(printf '%s' "$base" | sed 's/[][\.*^$/]/\\&/g')"
  actual="$(grep -E "(^|/)${escb}$" "$tracked" | head -n3 | tr '\n' ' ')"
  if [ -n "$actual" ]; then
    mislocated+=("$p → actually at: ${actual% }")
    continue
  fi

  # 6. nothing by that name anywhere — probably an unlabelled proposal, possibly invented
  unresolved+=("$p")
done

# ── ground truth ──────────────────────────────────────────────────────────────
# Stamped into every issue. A report that opens "all 89 rules" against a 94-rule tree is
# not obviously wrong to a reader; next to a measured count, it is.
sigma_rules=$(find detections/sigma -name '*.yml' -type f 2>/dev/null | wc -l | tr -d ' ')
detect_docs=$(find detections \( -name '*.yml' -o -name '*.yaml' \) -type f 2>/dev/null | wc -l | tr -d ' ')
attack_ids=$(grep -rhoE 'T[0-9]{4}(\.[0-9]{3})?' detections/ 2>/dev/null | sort -u | wc -l | tr -d ' ')

# ── verification block ────────────────────────────────────────────────────────
{
  printf '\n---\n\n### Automated verification\n\n'
  printf 'Checked before filing by `.github/workflows/verify-routine-report.sh`. '
  printf 'Citations are resolved against the git index; the counts are measured from the tree '
  printf 'at filing time, so a stale figure in the report above is visible rather than implied.\n\n'

  printf '| measured now | |\n| --- | --- |\n'
  printf '| Sigma rules (`detections/sigma/**.yml`) | **%s** |\n' "$sigma_rules"
  printf '| Detection docs (`detections/**.y*ml`) | **%s** |\n' "$detect_docs"
  printf '| Distinct ATT&CK technique IDs referenced | **%s** |\n\n' "$attack_ids"

  printf '| citations | count |\n| --- | --- |\n'
  printf '| resolved | %s |\n' "$verified"
  printf '| proposed (new files, not expected to exist) | %s |\n' "${#proposed[@]}"
  printf '| **wrong path** | **%s** |\n' "${#mislocated[@]}"
  printf '| unmatched | %s |\n\n' "${#unresolved[@]}"

  if [ "${#mislocated[@]}" -gt 0 ]; then
    printf '> [!WARNING]\n'
    printf '> **%s citation(s) point at a path that does not exist, for a file that does.**\n' "${#mislocated[@]}"
    printf '> Treat the surrounding findings as unverified until the paths are corrected.\n\n'
    for m in "${mislocated[@]}"; do printf -- '- `%s`\n' "$m"; done
    printf '\n'
  fi

  if [ "${#unresolved[@]}" -gt 0 ]; then
    printf 'Cited but not found anywhere in the tree — expected for a proposed rule, worth a look otherwise:\n\n'
    for u in "${unresolved[@]}"; do printf -- '- `%s`\n' "$u"; done
    printf '\n'
  fi

  if [ "${#mislocated[@]}" -eq 0 ] && [ "${#unresolved[@]}" -eq 0 ]; then
    printf 'Every cited path resolved.\n\n'
  fi
} >>"$report"

# ── verdict ───────────────────────────────────────────────────────────────────
if [ "${#mislocated[@]}" -gt 0 ]; then
  echo "::error::${#mislocated[@]} citation(s) point at the wrong path — report filed, run marked failed"
  for m in "${mislocated[@]}"; do echo "  $m"; done
  exit 1
fi

echo "verification passed: $verified resolved, ${#proposed[@]} proposed, ${#unresolved[@]} unmatched"
exit 0
