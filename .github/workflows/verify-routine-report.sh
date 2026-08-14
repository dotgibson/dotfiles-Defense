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
# WHAT IT DOES ABOUT A WRONG PATH. It fixes it. A citation naming a real file at the wrong
# path is rewritten in place to the path that file actually occupies, and the substitution
# is recorded in the appended block so the edit is visible rather than silent. Correcting
# beats blocking here: the finding was usually right and only its address was wrong, so
# suppressing the whole week's report over a typo throws away the expensive part.
#
# The rewrite is only safe when the basename is UNIQUE in the tree. 17 basenames are
# duplicated in this repo (CLAUDE.md, config.toml, …), and picking one of several
# candidates would replace a visibly wrong path with a confidently wrong one. Those are
# left exactly as written, and they are the one thing that still blocks.
#
# WHAT IT DELIBERATELY DOES NOT DO. It does not judge the findings — that is the routine's
# job and a human's. It does not fail on ambiguity of INTENT either: a citation with no
# match anywhere is usually a PROPOSED new rule (these reports propose files by path, and
# last week's proposals are this week's files), so those are listed, not fatal. A gate that
# cried wolf on correct reports would be switched off within a month.
#
# Usage: verify-routine-report.sh <report-file> [repo-root]
# Exit:  0 = filing may proceed. The report may have been REWRITTEN — corrections are
#            listed in the appended block.
#        1 = a citation names a file that exists in more than one place, so it cannot be
#            corrected automatically. The caller treats this as a hard gate: the report is
#            not filed, and goes to the run summary instead so the work survives.
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
corrected=()
ambiguous=()
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

  # 5. the basename exists, but not where the report says — a wrong path for a real file.
  #    Correctable when the basename is UNIQUE in the tree, because then there is exactly
  #    one thing it can have meant. This is the common shape: a report writes
  #    `harbor/harbor_artifact_deleted.yml` for a rule that lives under `registry/`.
  base="${p##*/}"
  escb="$(printf '%s' "$base" | sed 's/[][\.*^$/]/\\&/g')"
  mapfile -t candidates < <(grep -E "(^|/)${escb}$" "$tracked")

  if [ "${#candidates[@]}" -eq 1 ]; then
    corrected+=("$p → ${candidates[0]}")
    continue
  fi

  # 6. several files share the basename, so there is no single right answer and guessing
  #    would file a citation that is confidently wrong. 17 basenames are duplicated in
  #    this tree (CLAUDE.md, config.toml, …), so this is a real case, not a theoretical
  #    one. Left for a human — and it is the ONLY thing that still blocks.
  if [ "${#candidates[@]}" -gt 1 ]; then
    ambiguous+=("$p → ${#candidates[@]} candidates: $(printf '%s ' "${candidates[@]:0:3}")")
    continue
  fi

  # 7. nothing by that name anywhere — probably an unlabelled proposal, possibly invented
  unresolved+=("$p")
done

# ── apply the corrections ─────────────────────────────────────────────────────
# Rewrite each wrong citation to the path it must have meant, in place, BEFORE the
# verification block is appended — so the block's own record of "old → new" survives
# untouched and the reader can see exactly what was changed.
#
# bash literal replacement, not sed: the pattern is QUOTED inside the expansion, so a
# path containing regex or glob metacharacters cannot misfire. Anchored on the backticks
# so only code spans are rewritten and prose that happens to repeat the string is not.
if [ "${#corrected[@]}" -gt 0 ]; then
  bt='`'
  body="$(cat "$report")"
  for c in "${corrected[@]}"; do
    old="${c%% → *}"
    new="${c##* → }"
    body="${body//"${bt}${old}${bt}"/"${bt}${new}${bt}"}"
  done
  printf '%s\n' "$body" >"$report"
fi

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
  printf '| resolved as written | %s |\n' "$verified"
  printf '| **auto-corrected** | **%s** |\n' "${#corrected[@]}"
  printf '| proposed (new files, not expected to exist) | %s |\n' "${#proposed[@]}"
  printf '| **ambiguous — left alone** | **%s** |\n' "${#ambiguous[@]}"
  printf '| unmatched | %s |\n\n' "${#unresolved[@]}"

  if [ "${#corrected[@]}" -gt 0 ]; then
    printf '> [!NOTE]\n'
    printf '> **%s citation(s) were rewritten above.** Each named a real file at the wrong\n' "${#corrected[@]}"
    printf '> path, and the basename was unique in the tree, so there was exactly one thing\n'
    printf '> it could have meant. The findings themselves are unreviewed.\n\n'
    for c in "${corrected[@]}"; do printf -- '- `%s`\n' "$c"; done
    printf '\n'
  fi

  if [ "${#ambiguous[@]}" -gt 0 ]; then
    printf '> [!WARNING]\n'
    printf '> **%s citation(s) name a file that exists in more than one place.**\n' "${#ambiguous[@]}"
    printf '> There is no single correct rewrite, so they were left as written and this\n'
    printf '> report was blocked from filing. Disambiguate and re-run, or file by hand.\n\n'
    for a in "${ambiguous[@]}"; do printf -- '- `%s`\n' "$a"; done
    printf '\n'
  fi

  if [ "${#unresolved[@]}" -gt 0 ]; then
    printf 'Cited but not found anywhere in the tree — expected for a proposed rule, worth a look otherwise:\n\n'
    for u in "${unresolved[@]}"; do printf -- '- `%s`\n' "$u"; done
    printf '\n'
  fi

  if [ "${#corrected[@]}" -eq 0 ] && [ "${#ambiguous[@]}" -eq 0 ] && [ "${#unresolved[@]}" -eq 0 ]; then
    printf 'Every cited path resolved as written.\n\n'
  fi
} >>"$report"

# ── verdict ───────────────────────────────────────────────────────────────────
if [ "${#corrected[@]}" -gt 0 ]; then
  echo "::notice::auto-corrected ${#corrected[@]} citation(s) to the path each named file actually occupies"
  for c in "${corrected[@]}"; do echo "  $c"; done
fi

if [ "${#ambiguous[@]}" -gt 0 ]; then
  echo "::error::${#ambiguous[@]} citation(s) are ambiguous — BLOCKING: the report will not be filed"
  for a in "${ambiguous[@]}"; do echo "  $a"; done
  exit 1
fi

echo "verification passed: $verified resolved, ${#corrected[@]} auto-corrected, ${#proposed[@]} proposed, ${#unresolved[@]} unmatched"
exit 0
