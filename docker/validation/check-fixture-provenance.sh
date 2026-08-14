#!/usr/bin/env bash
# docker/validation/check-fixture-provenance.sh — every validation fixture must say where
# its schema came from.
#
# WHY. The Sigma gates prove a rule fires against OUR fixture. Where that fixture was
# hand-written from the same belief that produced the rule, the test is circular: it proves
# the rule is consistent with itself and says nothing about the provider's schema. A rule
# keyed on a field the provider does not emit passes its true positive AND its true
# negative, then sits inert in production. #149 is exactly that shape — the npm rule's TN
# fixture asserts `actor.type: ci` because the rule does.
#
# No gate can tell a plausible invented field from a real one. What it CAN do is make the
# distinction visible and stop it being lost: every fixture a manifest references must
# carry a provenance row, so a new fixture cannot arrive without someone stating whether
# its field names came from a real event, a vendor document, or an assumption.
#
# Two checks, both hard:
#   1. every manifest-referenced fixture has a row in fixture-provenance.tsv
#   2. every row's provenance is one of the three known values
#
# Deliberately NOT a check: that anything is captured or vendor-documented. Today
# everything is `unverified`, which is the honest state — Phase 3 is not done. Failing on
# that would be failing on the truth rather than on a regression.
#
# Usage: docker/validation/check-fixture-provenance.sh [repo-root]
# Exit:  0 = every fixture accounted for;  1 = otherwise
set -uo pipefail

REPO="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$REPO" || exit 1

host_manifest="docker/validation/sigma-manifest.tsv"
cloud_manifest="docker/validation/sigma-cloud-manifest.tsv"
ledger="docker/validation/fixture-provenance.tsv"

for f in "$host_manifest" "$cloud_manifest" "$ledger"; do
  [ -r "$f" ] || {
    echo "::error::missing: $f"
    exit 1
  }
done

referenced="$(mktemp)"
recorded="$(mktemp)"
trap 'rm -f "$referenced" "$recorded"' EXIT

# Fixture columns differ per manifest, same trap as check-rule-coverage.sh:
#   host  … tp-fixture is column 3, tn-fixture column 6
#   cloud … tp-fixture is column 3, tn-fixture column 4
{
  awk -F'\t' '!/^[[:space:]]*#/ && NF>=3 && $3!="" {print $3; if (NF>=6 && $6!="-" && $6!="") print $6}' "$host_manifest"
  awk -F'\t' '!/^[[:space:]]*#/ && NF>=3 && $3!="" {print $3; if (NF>=4 && $4!="-" && $4!="") print $4}' "$cloud_manifest"
} | sort -u >"$referenced"

awk -F'\t' '!/^[[:space:]]*#/ && NF>=2 && $1!="" {print $1}' "$ledger" | sort -u >"$recorded"

missing=()
while IFS= read -r fx; do
  grep -qxF "$fx" "$recorded" || missing+=("$fx")
done <"$referenced"

# A row naming a fixture no manifest uses is stale bookkeeping, not a failure — say so.
stale=0
while IFS= read -r fx; do
  grep -qxF "$fx" "$referenced" || stale=$((stale + 1))
done <"$recorded"

bad_value=()
while IFS=$'\t' read -r fx prov _rest; do
  case "$fx" in '#'* | '') continue ;; esac
  [ -n "$prov" ] || continue
  case "$prov" in
  captured | vendor-documented | unverified) ;;
  *) bad_value+=("$fx -> '$prov'") ;;
  esac
done < <(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$ledger")

rc=0

if [ "${#missing[@]}" -gt 0 ]; then
  echo "::error::${#missing[@]} fixture(s) are used by a manifest but have no provenance row:"
  for m in "${missing[@]}"; do echo "  $m"; done
  echo "  fix: add '<fixture>\\t<captured|vendor-documented|unverified>\\t<note>' to $ledger"
  rc=1
fi

if [ "${#bad_value[@]}" -gt 0 ]; then
  echo "::error::${#bad_value[@]} row(s) have an unknown provenance value:"
  for b in "${bad_value[@]}"; do echo "  $b"; done
  echo "  allowed: captured | vendor-documented | unverified"
  rc=1
fi

if [ "$rc" -eq 0 ]; then
  total=$(wc -l <"$referenced" | tr -d ' ')
  cap=$(awk -F'\t' '!/^[[:space:]]*#/ && $2=="captured"' "$ledger" | wc -l | tr -d ' ')
  doc=$(awk -F'\t' '!/^[[:space:]]*#/ && $2=="vendor-documented"' "$ledger" | wc -l | tr -d ' ')
  unv=$(awk -F'\t' '!/^[[:space:]]*#/ && $2=="unverified"' "$ledger" | wc -l | tr -d ' ')
  printf 'fixture provenance: %s referenced — %s captured, %s vendor-documented, %s unverified' \
    "$total" "$cap" "$doc" "$unv"
  [ "$stale" -gt 0 ] && printf ' (%s stale row(s) in the ledger)' "$stale"
  printf '\n'
  if [ "$unv" -eq "$total" ]; then
    echo "note: nothing is verified against a provider schema yet — every green Sigma check"
    echo "      on a SaaS field currently rests on an assumption. See #149."
  fi
fi
exit "$rc"
