#!/usr/bin/env bash
# run-sigma-validation.sh — fire each Sigma rule against a synthetic event log and assert
# it triggers. The host-plane twin of run-validation.sh: where sigma.yml proves the rules
# parse + compile, this proves they FIRE on the telemetry they claim to catch.
# ──────────────────────────────────────────────────────────────────────────────
# Reads sigma-manifest.tsv (name / pipeline / fixture / rule / expected-id), and for each
# row runs the JSON-lines event fixture through the REAL shipped Sigma rule with zircolite
# (native Sigma via the pysigma pipeline), then asserts the rule's id appears in the
# detections. PASS/FAIL per row; non-zero exit if any fails. Deterministic — committed
# fixtures, so a green run means the rule fires on the attack shape it claims.
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

while IFS=$'\t' read -r name pipeline fixture rule expect; do
  case "$name" in '' | \#*) continue ;; esac
  total=$((total + 1))
  rundir="$work/$name"
  mkdir -p "$rundir"
  out="$rundir/detections.json"

  # zircolite drops a db/log in its cwd — run it in the isolated rundir.
  (cd "$rundir" && "$PYTHON" "$ZIRCOLITE" -j \
    -e "$REPO_ROOT/$fixture" \
    -r "$REPO_ROOT/$rule" \
    --pipeline "$pipeline" \
    -c "$CONFIG" \
    -o "$out") >"$rundir/engine.out" 2>&1 || true

  if [[ -f "$out" ]] && grep -qF "$expect" "$out"; then
    echo "PASS $name — rule fired ($pipeline · $(basename "$rule"))"
    pass=$((pass + 1))
  else
    echo "FAIL $name — rule id $expect not detected ($pipeline · $(basename "$rule"))"
    if [[ -s "$rundir/engine.out" ]]; then
      echo "    ── zircolite output (last lines) ──"
      tail -12 "$rundir/engine.out" | sed 's/^/    /'
    fi
    fail=$((fail + 1))
  fi
done <"$MANIFEST"

echo "──────────────────────────────────────────"
echo "sigma validation: $pass/$total passed"
[[ "$fail" -eq 0 ]]
