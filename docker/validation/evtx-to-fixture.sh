#!/usr/bin/env bash
# docker/validation/evtx-to-fixture.sh — turn a CAPTURED Windows EVTX into the fixture JSONL
# the Sigma manifests consume.
#
# WHY. LAB-VALIDATION-PLAN.md Phase 3 ("fixtures from the real attacks") was specified and
# never built, so every host-plane fixture in this repo is hand-authored and every provenance
# row says `unverified`. That is the #149 shape: a rule keyed on a field the provider does not
# emit passes its true positive AND its true negative, then sits inert in production. The gate
# cannot catch it — check_near_miss in run-sigma-validation.sh requires a TN to carry the
# IDENTICAL EventData key set as its TP, so by construction no fixture in the manifest can ever
# exercise a missing-or-renamed-field case.
#
# This is the missing piece: the step that takes a real event and produces a fixture whose
# schema is the provider's rather than the author's. It is deliberately the SMALL half of
# Phase 3 — it does not run attacks or stand up hosts (see labruns/ for that runbook); it
# converts what a capture produced, which is the part worth having in the repo because it is
# the part that is reusable and testable.
#
# 2026-08-29 was its first use: labruns/2026-08-sysmon18-remote-pipe.md, which settled the
# Sysmon-18 remote-pipe premise and corrected the field set of six fixtures.
#
# Usage:
#   evtx-to-fixture.sh [--event-id N]... [--channel SUBSTR] <file.evtx> [file.evtx...]
#
#   --event-id N   keep only these EventIDs (repeatable; default: keep all)
#   --channel S    keep only records whose Channel contains S
#
# Writes JSONL to stdout, one event per line, in the shape the manifests expect:
#   {"Event": {"System": {"EventID": N, "Channel": "...", "Computer": "..."}, "EventData": {...}}}
#
# Requires `chainsaw` (the repo's HAVE_CHAINSAW tool) and python3. Both are hard requirements:
# a normalizer that silently skips when its parser is missing would emit an empty fixture, and
# an empty fixture is the exact vacuous-pass this harness already learned to reject.
#
# NOTE on chainsaw: use a stdout redirect, NOT `chainsaw dump -o FILE`. The -o path truncates
# output at a buffer boundary on the versions tested (2.16.4), producing JSON that fails to
# parse partway through — silently losing the tail of a capture.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PYTHON="${PYTHON:-python3}"
CHAINSAW="${CHAINSAW:-chainsaw}"

die() { echo "evtx-to-fixture: $*" >&2; exit 1; }

event_ids=()
channel=""
inputs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --event-id) [[ $# -ge 2 ]] || die "--event-id needs a value"; event_ids+=("$2"); shift 2 ;;
    --channel)  [[ $# -ge 2 ]] || die "--channel needs a value";  channel="$2";       shift 2 ;;
    -h|--help)  sed -n '1,40p' "$0" >&2; exit 0 ;;
    -*)         die "unknown option: $1" ;;
    *)          inputs+=("$1"); shift ;;
  esac
done

[[ ${#inputs[@]} -gt 0 ]] || die "no input files (see --help)"
command -v "$CHAINSAW" >/dev/null 2>&1 || die "chainsaw not on PATH — it is what parses the EVTX"
command -v "$PYTHON"   >/dev/null 2>&1 || die "$PYTHON not on PATH"

for f in "${inputs[@]}"; do
  [[ -f "$f" ]] || die "no such file: $f"
done

work="$(mktemp -d "${TMPDIR:-/tmp}/evtx2fixture.XXXXXX")"
trap 'rm -rf "$work"' EXIT

for f in "${inputs[@]}"; do
  # stdout redirect, not -o — see the NOTE in the header.
  if ! "$CHAINSAW" dump --json -q "$f" > "$work/dump.json" 2>"$work/dump.err"; then
    sed -n '1,5p' "$work/dump.err" >&2
    die "chainsaw could not parse $f"
  fi
  [[ -s "$work/dump.json" ]] || die "chainsaw produced no output for $f"

  IDS="$(IFS=,; echo "${event_ids[*]:-}")" CHANNEL="$channel" SRC="$f" \
    "$PYTHON" - "$work/dump.json" <<'PY'
import json, os, sys

want = {int(x) for x in os.environ.get("IDS", "").split(",") if x.strip()}
channel_filter = os.environ.get("CHANNEL", "")
src = os.environ.get("SRC", "")

try:
    records = json.load(open(sys.argv[1], encoding="utf-8"))
except ValueError as exc:
    sys.exit("evtx-to-fixture: %s produced unparseable JSON (%s)" % (src, exc))

kept = 0
for rec in records:
    ev = rec.get("Event", rec)
    system = ev.get("System", {})
    eid = system.get("EventID")
    if isinstance(eid, dict):                       # some renderers nest it
        eid = eid.get("#text", eid.get("Value"))
    try:
        eid = int(eid)
    except (TypeError, ValueError):
        continue
    if want and eid not in want:
        continue
    chan = system.get("Channel") or ""
    if channel_filter and channel_filter not in chan:
        continue
    data = ev.get("EventData")
    if not isinstance(data, dict) or not data:
        # An event with no EventData cannot exercise a rule's selection. Skipping it
        # silently would be the vacuous-pass trap, so say so on stderr.
        print("evtx-to-fixture: skipping EventID %s with no EventData" % eid, file=sys.stderr)
        continue
    out = {"Event": {"System": {"EventID": eid, "Channel": chan,
                                "Computer": system.get("Computer")},
                     "EventData": data}}
    print(json.dumps(out, ensure_ascii=False))
    kept += 1

if not kept:
    sys.exit("evtx-to-fixture: %s yielded 0 matching events — an empty fixture is a vacuous "
             "pass, not a true negative; widen --event-id/--channel or check the capture" % src)
PY
done
