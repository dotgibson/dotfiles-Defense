#!/usr/bin/env bash
# run-validation.sh — fire each network detection against a synthetic PCAP and assert it
# triggers. The executable half of every "Validate (purple)" line: attack-shaped traffic
# in → engine runs the shipped detection → expected notice/alert out.
# ──────────────────────────────────────────────────────────────────────────────
# Reads manifest.tsv (name / engine / generator / script / expected-signal), and for each
# row: runs the generator to synthesize a PCAP, replays it through the engine (zeek or
# suricata) with the REAL shipped detection, and greps the engine's output for the
# expected signal. PASS/FAIL per row; non-zero exit if any row fails. Deterministic — the
# generators are seeded, so a green run means the detection fires on the shape it claims.
#
#   run-validation.sh              # run every row
#   run-validation.sh zeek         # only zeek rows   (CI runs one engine per job/image)
#   run-validation.sh suricata     # only suricata rows
#   ZEEK_CMD=… SURICATA_CMD=… PYTHON=…   # override the binaries
#
# Requires a scapy-capable python3, plus the engine(s) the (filtered) manifest needs on
# PATH. CI runs one job per engine in that engine's image (network-validation.yml);
# locally, install the engine or wrap its Docker image in a shim on PATH.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
MANIFEST="$HERE/manifest.tsv"
ZEEK_CMD="${ZEEK_CMD:-zeek}"
SURICATA_CMD="${SURICATA_CMD:-suricata}"
PYTHON="${PYTHON:-python3}"
ENGINE_FILTER="${1:-}"

fail_preflight() {
  echo "run-validation: $1" >&2
  exit 1
}
[[ -f "$MANIFEST" ]] || fail_preflight "manifest not found: $MANIFEST"
command -v "$PYTHON" >/dev/null 2>&1 || fail_preflight "python3 not found (needed for fixtures)"
"$PYTHON" -c 'import scapy' 2>/dev/null || fail_preflight "python 'scapy' module not found (pip install scapy)"

# Only require the engines the in-scope rows actually use, so `run-validation.sh zeek` in
# the zeek image doesn't demand suricata (and vice versa).
need=""
while IFS=$'\t' read -r name engine _; do
  case "$name" in '' | \#*) continue ;; esac
  [[ -n "$ENGINE_FILTER" && "$engine" != "$ENGINE_FILTER" ]] && continue
  case " $need " in *" $engine "*) ;; *) need="$need $engine" ;; esac
done <"$MANIFEST"
case " $need " in *" zeek "*) command -v "$ZEEK_CMD" >/dev/null 2>&1 || fail_preflight "zeek not found (set ZEEK_CMD, or run in the zeek/zeek image)" ;; esac
case " $need " in *" suricata "*) command -v "$SURICATA_CMD" >/dev/null 2>&1 || fail_preflight "suricata not found (set SURICATA_CMD, or run in a suricata image)" ;; esac

work="$(mktemp -d "${TMPDIR:-/tmp}/netval.XXXXXX")"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0
total=0

while IFS=$'\t' read -r name engine gen script expect; do
  case "$name" in '' | \#*) continue ;; esac
  [[ -n "$ENGINE_FILTER" && "$engine" != "$ENGINE_FILTER" ]] && continue
  total=$((total + 1))
  pcap="$work/$name.pcap"
  engine_log="$work/$name.engine.out" # kept OUTSIDE the run dir so the assertion never greps it

  if ! "$PYTHON" "$REPO_ROOT/$gen" "$pcap" >/dev/null 2>"$work/$name.gen.err"; then
    echo "FAIL $name — fixture generator errored:"; sed 's/^/    /' "$work/$name.gen.err"
    fail=$((fail + 1)); continue
  fi

  rundir="$work/$name.run"
  mkdir -p "$rundir"
  case "$engine" in
  zeek)
    # Run in the scratch dir so Zeek's logs (notice.log, …) land there, isolated.
    (cd "$rundir" && "$ZEEK_CMD" -r "$pcap" "$REPO_ROOT/$script") >"$engine_log" 2>&1 || true
    ;;
  suricata)
    # -S: run ONLY this rule file; -k none: don't drop scapy packets on checksum mismatch;
    # -l: write fast.log/eve.json into the isolated run dir.
    "$SURICATA_CMD" -r "$pcap" -S "$REPO_ROOT/$script" -l "$rundir" -k none >"$engine_log" 2>&1 || true
    ;;
  *)
    echo "FAIL $name — unknown engine '$engine'"
    fail=$((fail + 1)); continue
    ;;
  esac

  # grep -rF: the expected signal is a literal (a Zeek Notice::Type or a Suricata msg),
  # searched across the engine's output files in the run dir.
  if grep -rqF "$expect" "$rundir"; then
    echo "PASS $name — '$expect' fired ($engine $(basename "$script"))"
    pass=$((pass + 1))
  else
    echo "FAIL $name — expected '$expect' from $engine $(basename "$script"), not seen"
    if [[ -s "$engine_log" ]]; then
      echo "    ── engine output (a load/parse error here means the script broke, not the detection) ──"
      sed 's/^/    /' "$engine_log"
    fi
    fail=$((fail + 1))
  fi
done <"$MANIFEST"

echo "──────────────────────────────────────────"
echo "network validation${ENGINE_FILTER:+ ($ENGINE_FILTER)}: $pass/$total passed"
[[ "$fail" -eq 0 ]]
