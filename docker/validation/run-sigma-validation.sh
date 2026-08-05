#!/usr/bin/env bash
# run-sigma-validation.sh — fire each Sigma rule against a synthetic event log and assert
# it triggers on the attack shape AND stays silent on a benign near-miss. The host-plane
# twin of run-validation.sh: where sigma.yml proves the rules parse + compile, this proves
# they WORK on the telemetry they claim to catch.
# ──────────────────────────────────────────────────────────────────────────────
# Reads sigma-manifest.tsv (name / pipeline / tp-fixture / rule / expected-id / tn-fixture),
# and for each row runs the JSON-lines event fixture through the REAL shipped Sigma rule
# with zircolite (native Sigma via the pysigma pipeline), then asserts the rule's id appears
# in the detections. PASS/FAIL per row; non-zero exit if any fails. Deterministic — committed
# fixtures, so a green run means the rule fires on the attack shape it claims.
#
# The SIXTH column is the true-negative fixture, and it is what makes a filter provable.
# A TP row can only ever show that a rule fires; it cannot show that a rule's filter/
# exclusion still works, so an exclusion that silently stopped matching would keep this
# gate green while the rule quietly went noisy. Where a row names a TN fixture, the rule
# must ALSO stay silent on it. Use '-' for none.
#
# The TN check must not confuse "silent" with "broken". A zircolite that failed to run
# produces no detections either, which would read as a passing true-negative and hide a
# dead gate — the same trap run-cloud-validation.sh documents for its evaluator's exit
# codes. So a TN passes only on the three-way contract: the engine exited 0, it WROTE its
# output file, and the expected id is absent from it. Engine error => the row FAILS.
#
# Rules that carry a filter_* block but no TN fixture are reported at the end as an
# advisory (the run still passes) — the same discoverable-checklist idea as
# detections/sigma/deploy-required.sh, so the gap is visible instead of invisible.
#
#   ZIRCOLITE=/path/to/zircolite.py run-sigma-validation.sh
#   PYTHON=python3.11 ZIRCOLITE=... run-sigma-validation.sh
#
# Requires a python3 with zircolite's deps (pysigma + pipelines; see its requirements),
# and ZIRCOLITE pointing at zircolite.py. CI clones a pinned zircolite and sets both (see
# .github/workflows/sigma-validation.yml).
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
MANIFEST="$HERE/sigma-manifest.tsv"
PYTHON="${PYTHON:-python3}"
ZIRCOLITE="${ZIRCOLITE:-}"

fail_preflight() {
  echo "run-sigma-validation: $1" >&2
  exit 1
}
[[ -f "$MANIFEST" ]] || fail_preflight "manifest not found: $MANIFEST"
command -v "$PYTHON" >/dev/null 2>&1 || fail_preflight "python3 not found"
[[ -n "$ZIRCOLITE" && -f "$ZIRCOLITE" ]] || fail_preflight "set ZIRCOLITE to the path of zircolite.py"
"$PYTHON" -c 'import sigma' 2>/dev/null || fail_preflight "pysigma not importable (pip install -r <zircolite>/requirements.txt)"

# zircolite resolves its field-mapping config relative to its own dir; pass it explicitly
# so the tool works from the isolated per-row run dirs below.
ZDIR="$(cd "$(dirname "$ZIRCOLITE")" && pwd)"
CONFIG="$ZDIR/config/config.yaml"
[[ -f "$CONFIG" ]] || fail_preflight "zircolite config not found at $CONFIG"

work="$(mktemp -d "${TMPDIR:-/tmp}/sigmaval.XXXXXX")"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0
total=0
tn_checked=0
missing_tn=""

# Run one fixture through the real rule. Writes $4; returns zircolite's exit code, which
# callers MUST distinguish from "no detections" (see the TN contract in the header).
run_engine() {
  local rundir="$1" fixture="$2" rule="$3" out="$4"
  shift 4
  # zircolite drops a db/log in its cwd — run it in the isolated rundir.
  (cd "$rundir" && "$PYTHON" "$ZIRCOLITE" -j \
    -e "$REPO_ROOT/$fixture" \
    -r "$REPO_ROOT/$rule" \
    "$@" \
    -c "$CONFIG" \
    -o "$out") >"$rundir/engine.out" 2>&1
}

# Structural TN check: prove the TN fixture is a NEAR-MISS of its TP, not merely something
# the engine ignores. Prints the reason and returns 1 on failure. Three assertions, all
# version-independent (pure stdlib — no zircolite involvement):
#   1. every line parses as JSON, and there is at least one — catches a garbage or empty
#      fixture, which would otherwise ingest 0 events and read as a passing true negative;
#   2. the EventID set matches the TP's — a TN with the wrong (or no) event id is silent
#      for a reason that has nothing to do with the filter under test;
#   3. the EventData key set matches the TP's — this is what catches the subtle one, a
#      typo'd or dropped field name that makes the base selection miss. Such a TN is silent
#      no matter what the filter does, so it would lock in a false sense of coverage.
# Together they mechanically enforce the discipline the manifest header states in prose:
# same shape as the TP, ONE value changed so exactly one filter_* block catches it.
check_near_miss() {
  "$PYTHON" - "$1" "$2" <<'PY'
import json, sys

def shape(path):
    keys, eids, n = set(), set(), 0
    try:
        fh = open(path, encoding="utf-8")
    except OSError as exc:
        sys.exit("cannot read %s (%s)" % (path, exc.strerror))
    with fh:
        for i, line in enumerate(fh, 1):
            if not line.strip():
                continue
            try:
                ev = json.loads(line).get("Event", {})
            except ValueError as exc:
                sys.exit("%s line %d is not valid JSON (%s)" % (path, i, exc))
            keys |= set(ev.get("EventData", {}))
            eid = ev.get("System", {}).get("EventID")
            if eid is not None:
                eids.add(eid)
            n += 1
    if not n:
        sys.exit("%s has no events" % path)
    return keys, eids

tp_keys, tp_eids = shape(sys.argv[1])
tn_keys, tn_eids = shape(sys.argv[2])
if tp_eids != tn_eids:
    sys.exit("EventID set %s does not match the TP's %s" % (sorted(tn_eids), sorted(tp_eids)))
if tp_keys != tn_keys:
    sys.exit("EventData keys differ from the TP's (missing %s, extra %s) — a TN must change a "
             "VALUE, not the event shape, or it goes silent for the wrong reason"
             % (sorted(tp_keys - tn_keys), sorted(tn_keys - tp_keys)))
PY
}

dump_engine_out() {
  if [[ -s "$1/engine.out" ]]; then
    echo "    ── zircolite output (last lines) ──"
    tail -12 "$1/engine.out" | sed 's/^/    /'
  fi
}

while IFS=$'\t' read -r name pipeline fixture rule expect tn; do
  case "$name" in '' | \#*) continue ;; esac
  total=$((total + 1))
  # Guard malformed rows: an empty expected-id would make `grep -qF ""` match any
  # non-empty output — a false PASS that silently hides a coverage gap. The tn column is
  # required too (as a path or the literal '-'): defaulting a missing field to "no TN"
  # would let a row silently opt out of the very check this column exists to enforce.
  if [[ -z "$pipeline" || -z "$fixture" || -z "$rule" || -z "$expect" || -z "$tn" ]]; then
    echo "FAIL $name — malformed manifest row (need pipeline/tp-fixture/rule/expected-id/tn-fixture, tab-separated; tn may be '-')"
    fail=$((fail + 1)); continue
  fi
  rundir="$work/$name"
  mkdir -p "$rundir/tp" "$rundir/tn"
  out="$rundir/tp/detections.json"

  # pipeline "none" = no pysigma pipeline: cloud/SaaS rules have no EventID and match on
  # raw field names, so they convert and match without a product pipeline (none is
  # installed for them anyway). Windows/Sysmon rows name a real pipeline.
  pipe_args=(--pipeline "$pipeline")
  [[ "$pipeline" == "none" ]] && pipe_args=()

  run_engine "$rundir/tp" "$fixture" "$rule" "$out" "${pipe_args[@]}" || true

  if ! { [[ -f "$out" ]] && grep -qF "$expect" "$out"; }; then
    echo "FAIL $name — TP: rule id $expect not detected ($pipeline · $(basename "$rule"))"
    dump_engine_out "$rundir/tp"
    fail=$((fail + 1)); continue
  fi

  # No TN declared — the TP verdict stands, and the advisory below records the gap.
  if [[ "$tn" == "-" ]]; then
    if grep -q '^  filter' "$REPO_ROOT/$rule" 2>/dev/null; then
      missing_tn="$missing_tn  $name ($(basename "$rule"))"$'\n'
    fi
    echo "PASS $name — rule fired ($pipeline · $(basename "$rule"))"
    pass=$((pass + 1)); continue
  fi

  # A TN that the engine never really evaluates passes vacuously — silence proves nothing
  # if nothing was tested. Found the hard way: a TN fixture of unparseable garbage sailed
  # through, because zircolite ingests 0 events, exits 0, and writes an empty result that
  # is indistinguishable from a filter doing its job. So the TN is checked STRUCTURALLY
  # against its own TP before the engine ever runs.
  # 2>&1: the helper reports its reason on stderr (python's sys.exit(str)), so the capture
  # must fold stderr in or the failure prints with an empty explanation.
  if ! tn_err="$(check_near_miss "$REPO_ROOT/$fixture" "$REPO_ROOT/$tn" 2>&1)"; then
    echo "FAIL $name — TN fixture is not a usable near-miss: $tn_err"
    fail=$((fail + 1)); continue
  fi

  tn_out="$rundir/tn/detections.json"
  run_engine "$rundir/tn" "$tn" "$rule" "$tn_out" "${pipe_args[@]}" && tn_rc=0 || tn_rc=$?

  # The three-way contract: engine exited 0 AND wrote its output AND the id is absent.
  # Anything else is an engine ERROR, which must not be read as a passing true-negative.
  if [[ "$tn_rc" -ne 0 || ! -f "$tn_out" ]]; then
    echo "FAIL $name — TN: zircolite error (rc=$tn_rc, output $([[ -f "$tn_out" ]] && echo written || echo absent)) — not a true negative"
    dump_engine_out "$rundir/tn"
    fail=$((fail + 1)); continue
  fi
  if grep -qF "$expect" "$tn_out"; then
    echo "FAIL $name — TN: rule fired on the benign near-miss ($(basename "$tn"))"
    fail=$((fail + 1)); continue
  fi

  echo "PASS $name — TP fired $expect, TN silent ($pipeline · $(basename "$rule"))"
  pass=$((pass + 1))
  tn_checked=$((tn_checked + 1))
done <"$MANIFEST"

echo "──────────────────────────────────────────"
echo "sigma validation: $pass/$total passed ($tn_checked with a true-negative)"
if [[ -n "$missing_tn" ]]; then
  # Advisory, not a gate: adoption is incremental by design, but the gap stays visible.
  printf '\nadvisory — rules with a filter_* block and no TN fixture (a TP row cannot prove\nthe filter still works; add a near-miss fixture and replace the row'"'"'s trailing -):\n%s' "$missing_tn"
fi
[[ "$fail" -eq 0 ]]
