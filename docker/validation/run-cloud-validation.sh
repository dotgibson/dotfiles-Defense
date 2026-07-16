#!/usr/bin/env bash
# run-cloud-validation.sh — fire each nested-field cloud/SaaS Sigma rule against a
# committed JSON event and assert it triggers on the attack shape AND stays silent on a
# benign near-miss. The cloud-plane twin of run-sigma-validation.sh, for the rules whose
# field names zircolite's EVTX flattener can't preserve (dotted paths + underscored keys).
# ──────────────────────────────────────────────────────────────────────────────
# Reads sigma-cloud-manifest.tsv (name / rule / tp-fixture / tn-fixture / expected-id) and
# for each row runs the REAL shipped Sigma rule through sigma_eval.py — a matcher that
# walks pysigma's OWN parsed condition tree over natural cloud-event JSON, so the field
# logic (contains/startswith/all, AND/OR/NOT) comes from the authoritative parser, not a
# re-implementation. A row PASSES only if the TP fixture fires the expected id and the TN
# fixture does not fire. PASS/FAIL per row; non-zero exit if any fails.
#
#   run-cloud-validation.sh
#   PYTHON=python3.11 run-cloud-validation.sh
#
# Requires a python3 with pysigma importable (pip install pysigma). No engine download and
# no pipeline: the evaluator is pure Python. CI installs pysigma and runs this directly
# (see .github/workflows/sigma-validation.yml).
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
MANIFEST="$HERE/sigma-cloud-manifest.tsv"
EVAL="$HERE/sigma_eval.py"
PYTHON="${PYTHON:-python3}"

fail_preflight() {
  echo "run-cloud-validation: $1" >&2
  exit 1
}
[[ -f "$MANIFEST" ]] || fail_preflight "manifest not found: $MANIFEST"
[[ -f "$EVAL" ]] || fail_preflight "evaluator not found: $EVAL"
command -v "$PYTHON" >/dev/null 2>&1 || fail_preflight "python3 not found"
"$PYTHON" -c 'import sigma' 2>/dev/null || fail_preflight "pysigma not importable (pip install pysigma)"

pass=0
fail=0
total=0

# Runs the evaluator; echoes "fire" or "nofire". Any evaluator error (unsupported rule
# shape, bad fixture) surfaces on stderr and counts as neither — the row then FAILs below.
verdict() {
  if "$PYTHON" "$EVAL" "$REPO_ROOT/$1" "$REPO_ROOT/$2" >/dev/null 2>"$3"; then
    echo fire
  else
    echo nofire
  fi
}

while IFS=$'\t' read -r name rule tp tn expect; do
  case "$name" in '' | \#*) continue ;; esac
  total=$((total + 1))
  if [[ -z "$rule" || -z "$tp" || -z "$tn" || -z "$expect" ]]; then
    echo "FAIL $name — malformed manifest row (need rule/tp/tn/expected-id, tab-separated)"
    fail=$((fail + 1)); continue
  fi

  # TP must fire with the expected id; TN must not fire at all.
  tp_err="$(mktemp "${TMPDIR:-/tmp}/cloudval.XXXXXX")"
  tp_out="$("$PYTHON" "$EVAL" "$REPO_ROOT/$rule" "$REPO_ROOT/$tp" --expect "$expect" 2>"$tp_err")" && tp_rc=0 || tp_rc=$?
  tn_verdict="$(verdict "$rule" "$tn" "/dev/null")"

  if [[ "$tp_rc" -eq 0 && "$tp_out" == "FIRE $expect" && "$tn_verdict" == "nofire" ]]; then
    echo "PASS $name — TP fired $expect, TN silent ($(basename "$rule"))"
    pass=$((pass + 1))
  else
    echo "FAIL $name — TP=[$tp_out rc=$tp_rc] TN=[$tn_verdict] (expected TP FIRE $expect / TN nofire)"
    [[ -s "$tp_err" ]] && sed 's/^/    /' "$tp_err"
    fail=$((fail + 1))
  fi
  rm -f "$tp_err"
done <"$MANIFEST"

echo "──────────────────────────────────────────"
echo "cloud validation: $pass/$total passed"
[[ "$fail" -eq 0 ]]
