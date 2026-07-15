#!/usr/bin/env bash
# run-validation.sh — fire each network detection against a synthetic PCAP and assert it
# triggers. The executable half of every "Validate (purple)" line: attack-shaped traffic
# in → engine runs the shipped detection → expected notice/alert out.
# ──────────────────────────────────────────────────────────────────────────────
# Reads manifest.tsv (name / engine / generator / script / expected-signal), and for each
# row: runs the generator to synthesize a PCAP, replays it through the engine with the
# REAL shipped detection script, and greps the engine's output for the expected signal.
# PASS/FAIL per row; non-zero exit if any row fails. Deterministic — the generators are
# seeded, so a green run here means the detection fires on the traffic shape it claims to.
#
#   run-validation.sh                 # run the whole manifest
#   ZEEK_CMD=/opt/zeek/bin/zeek run-validation.sh   # point at a specific zeek
#   PYTHON=python3.11 run-validation.sh             # pick the python for the generators
#
# Requires `zeek` and a scapy-capable `python3` on PATH. CI runs this inside the
# zeek/zeek image (see .github/workflows/network-validation.yml); locally, install Zeek
# or wrap the zeek/zeek Docker image in a `zeek` shim on PATH. Suricata rows land here
# next (Phase 1) via the same manifest.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
MANIFEST="$HERE/manifest.tsv"
ZEEK_CMD="${ZEEK_CMD:-zeek}"
PYTHON="${PYTHON:-python3}"

fail_preflight() {
  echo "run-validation: $1" >&2
  exit 1
}
command -v "$PYTHON" >/dev/null 2>&1 || fail_preflight "python3 not found (needed for fixtures)"
"$PYTHON" -c 'import scapy' 2>/dev/null || fail_preflight "python 'scapy' module not found (pip install scapy)"
command -v "$ZEEK_CMD" >/dev/null 2>&1 || fail_preflight "zeek not found (set ZEEK_CMD, or run in the zeek/zeek image)"
[[ -f "$MANIFEST" ]] || fail_preflight "manifest not found: $MANIFEST"

work="$(mktemp -d "${TMPDIR:-/tmp}/netval.XXXXXX")"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0
total=0

while IFS=$'\t' read -r name engine gen script expect; do
  case "$name" in '' | \#*) continue ;; esac
  total=$((total + 1))
  pcap="$work/$name.pcap"

  if ! "$PYTHON" "$REPO_ROOT/$gen" "$pcap" >/dev/null 2>"$work/$name.gen.err"; then
    echo "FAIL $name — fixture generator errored:"; sed 's/^/    /' "$work/$name.gen.err"
    fail=$((fail + 1)); continue
  fi

  case "$engine" in
  zeek)
    rundir="$work/$name.run"
    mkdir -p "$rundir"
    # Run in a scratch dir so Zeek's logs (notice.log, conn.log, …) land there, isolated.
    (cd "$rundir" && "$ZEEK_CMD" -r "$pcap" "$REPO_ROOT/$script") >/dev/null 2>&1 || true
    out="$rundir/notice.log"
    ;;
  *)
    echo "FAIL $name — unknown engine '$engine'"
    fail=$((fail + 1)); continue
    ;;
  esac

  if [[ -f "$out" ]] && grep -q "$expect" "$out"; then
    echo "PASS $name — '$expect' fired ($engine $(basename "$script"))"
    pass=$((pass + 1))
  else
    echo "FAIL $name — expected '$expect' from $engine $(basename "$script"), not seen"
    fail=$((fail + 1))
  fi
done <"$MANIFEST"

echo "──────────────────────────────────────────"
echo "network validation: $pass/$total passed"
[[ "$fail" -eq 0 ]]
