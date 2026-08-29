#!/usr/bin/env bash
# docker/validation/check-rule-coverage.sh — every Sigma rule must be validated, and every
# exclusion must be proven to still work.
#
# WHY. run-sigma-validation.sh and run-cloud-validation.sh iterate the MANIFESTS, not the
# corpus. A rule that is never listed is therefore never run against a fixture — it
# compiles, it ships, and nothing has ever demonstrated it fires. The corpus is currently
# 108/108 covered with 47/47 filtered rules carrying a true-negative fixture, which is an
# excellent position and one held entirely by hand. This turns that discipline into an
# invariant, at the moment it is green and so costs nothing to adopt.
#
# Two rules, both hard:
#   1. every detections/sigma/**.yml appears in a manifest
#   2. every rule carrying a `filter_*` block has a TRUE-NEGATIVE fixture
#
# (2) is the one that protects against silent noise. A true-positive row only proves a rule
# CAN fire; it cannot show that an exclusion still excludes. An exclusion that quietly
# stopped matching keeps every TP green while the rule floods the analyst — the failure
# run-sigma-validation.sh's own header describes, and the reason its sixth column exists.
#
# THE MANIFESTS HAVE DIFFERENT COLUMN LAYOUTS. This bit me while writing the check, and it
# will bite the next reader, so it is spelled out rather than inferred:
#   host  (sigma-manifest.tsv)       name  pipeline  tp-fixture  RULE  expected-id  tn-fixture
#   cloud (sigma-cloud-manifest.tsv) name  RULE      tp-fixture  tn-fixture  expected-id
# The rule path is column 4 in one and column 2 in the other; the TN is column 6 and 4.
#
# Exemptions live in no-fixture-allowlist.tsv (rule<TAB>reason) and must carry a reason.
# It is empty today — deliberately. A rule that genuinely cannot be fixtured is a real
# thing (see the cloud-plane notes in README.md), but it should be argued for in writing,
# not achieved by omission.
#
# Usage: docker/validation/check-rule-coverage.sh [repo-root]
# Exit:  0 = every rule validated, every filter proven;  1 = otherwise
set -uo pipefail

REPO="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$REPO" || exit 1

host_manifest="docker/validation/sigma-manifest.tsv"
cloud_manifest="docker/validation/sigma-cloud-manifest.tsv"
allowlist="docker/validation/no-fixture-allowlist.tsv"

for f in "$host_manifest" "$cloud_manifest"; do
  [ -r "$f" ] || {
    echo "::error::missing manifest: $f"
    exit 1
  }
done

covered="$(mktemp)"   # rule
with_tn="$(mktemp)"   # rule (has a true-negative fixture)
exempted="$(mktemp)"  # rule
trap 'rm -f "$covered" "$with_tn" "$exempted"' EXIT

# Every rule listed in either manifest. Column 4 for host, column 2 for cloud — see the
# layout note above; getting this backwards silently reports the whole corpus as uncovered.
{
  awk -F'\t' '!/^[[:space:]]*#/ && NF>=4 && $4!="" {print $4}' "$host_manifest"
  awk -F'\t' '!/^[[:space:]]*#/ && NF>=2 && $2!="" {print $2}' "$cloud_manifest"
} | sort -u >"$covered"

# Rules whose row names a TRUE-NEGATIVE fixture. '-' is the manifest's explicit "none".
{
  awk -F'\t' '!/^[[:space:]]*#/ && NF>=6 && $6!="-" && $6!="" {print $4}' "$host_manifest"
  awk -F'\t' '!/^[[:space:]]*#/ && NF>=4 && $4!="-" && $4!="" {print $2}' "$cloud_manifest"
} | sort -u >"$with_tn"

if [ -r "$allowlist" ]; then
  awk -F'\t' '!/^[[:space:]]*#/ && NF>=2 && $1!="" && $2!="" {print $1}' "$allowlist" >"$exempted"
fi



sort -u -o "$exempted" "$exempted" 2>/dev/null || :

missing_fixture=()
missing_tn=()
total=0

while IFS= read -r rule; do
  total=$((total + 1))
  grep -qxF "$rule" "$exempted" 2>/dev/null && continue

  grep -qxF "$rule" "$covered" || {
    missing_fixture+=("$rule")
    continue
  }

  # A filter_* block is an exclusion, and an exclusion needs a true negative to prove it.
  if grep -qE '^[[:space:]]*filter_' "$rule" && ! grep -qxF "$rule" "$with_tn"; then
    missing_tn+=("$rule")
  fi
done < <(find detections/sigma -name '*.yml' -type f | sort)

rc=0

if [ "${#missing_fixture[@]}" -gt 0 ]; then
  echo "::error::${#missing_fixture[@]} rule(s) are in the corpus but in no validation manifest — they have never been shown to fire:"
  for r in "${missing_fixture[@]}"; do echo "  $r"; done
  echo "  fix: add a row to $host_manifest (or $cloud_manifest for nested-field cloud rules),"
  echo "       or record it in $allowlist with a reason."
  rc=1
fi

if [ "${#missing_tn[@]}" -gt 0 ]; then
  echo "::error::${#missing_tn[@]} rule(s) carry a filter_* exclusion with no true-negative fixture — nothing proves the exclusion still excludes:"
  for r in "${missing_tn[@]}"; do echo "  $r"; done
  echo "  fix: add a TN fixture in the manifest's tn column (6th for host, 4th for cloud)."
  rc=1
fi

if [ "$rc" -eq 0 ]; then
  printf 'rule coverage: %s/%s rules validated' "$(wc -l <"$covered" | tr -d ' ')" "$total"
  [ -s "$exempted" ] && printf ', %s exempted' "$(wc -l <"$exempted" | tr -d ' ')"
  printf '; every filter_* rule has a true negative\n'
fi
exit "$rc"
