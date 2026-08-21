#!/usr/bin/env bash
# detections/check-readme-gates.sh — assert that detections/README.md's "CI gate" section
# still describes the gates .github/workflows/sigma.yml actually runs.
# ──────────────────────────────────────────────────────────────────────────────
# WHY. The gate list exists twice: once as the steps sigma.yml runs, and once as the
# numbered prose + copy-pasteable block contributors run locally before pushing. Nothing
# tied the two together, so they drifted: #145 and #150 added check-rule-coverage.sh and
# check-fixture-provenance.sh as hard gates, and the README kept saying "Six hard checks"
# and listing six commands for weeks.
#
# That drift has a specific cost, and it is the opposite of a cosmetic one. The local
# block's whole purpose is "run these and CI will agree." A contributor who runs a stale
# block goes green locally, pushes, and fails on a gate they were never told about — which
# is exactly the surprise the pinned block was written to prevent. The README is load-
# bearing documentation, so it gets a gate like the rest of the load-bearing artifacts.
#
#   check-readme-gates.sh       # exit non-zero, with a specific reason, on a stale section
#
# Three assertions:
#
#   1. COVERED — every hard gate in sigma.yml appears in the README's local block. This is
#      the direction that bit us: a gate added to CI and never documented.
#   2. NO PHANTOMS — every command in the block corresponds to a real step in sigma.yml.
#      Catches the inverse: a gate retired from CI while the README still tells people to
#      run it, which trains contributors to ignore a failure that no longer means anything.
#   3. COUNTS — the "N hard checks, one advisory" sentence and the numbered list both match
#      the number of steps actually classified. A count is the cheapest thing to leave
#      stale and the first thing a reader trusts.
#
# Steps are classified from sigma.yml itself, not from a list kept here — a hard-coded
# list would be a third copy to drift:
#   - ADVISORY  — the step sets `continue-on-error: true`
#   - SETUP     — the step's run is a `pip install` (a prerequisite, in the block but not
#                 a check; the README's count deliberately excludes it)
#   - HARD GATE — everything else
#
# Deliberately NOT checked: the prose describing each gate. What a gate is FOR is
# editorial, the same judgement call check-methodology.sh leaves alone in the methodology
# table — gating it would fight the writing instead of protecting it. This checks the
# machine-checkable skeleton: which commands, and how many.
#
# Matching is on the command KEY (the script path, or `sigma check`), not the full string:
# the workflow redirects and the README annotates, and neither difference is drift. The
# one flag that IS compared is `--check`, because gen-siem.sh and gen-siem.sh --check are
# opposite operations — one rewrites the artifact, the other proves it wasn't rewritten.
#
# Pure stdlib Python — no deps beyond the python3 the sigma job already installs.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd -- "$HERE/.." && pwd)"
DOC="$HERE/README.md"
WORKFLOW="$REPO_ROOT/.github/workflows/sigma.yml"

if [[ $# -gt 0 ]]; then
  echo "check-readme-gates: unexpected argument '$1'" >&2
  echo "usage: check-readme-gates.sh" >&2
  exit 2
fi

[[ -f "$DOC" ]] || {
  echo "check-readme-gates: $DOC not found" >&2
  exit 1
}
[[ -f "$WORKFLOW" ]] || {
  echo "check-readme-gates: $WORKFLOW not found" >&2
  exit 1
}

DOC="$DOC" WORKFLOW="$WORKFLOW" python3 - <<'PY'
import os, re, sys

doc = open(os.environ["DOC"], encoding="utf-8").read()
wf_lines = open(os.environ["WORKFLOW"], encoding="utf-8").read().splitlines()
failures = []

# ── parse sigma.yml steps ─────────────────────────────────────────────────────
# All run: values in this workflow are single-line; a block scalar would need handling,
# so it is detected and reported rather than silently mis-parsed.
steps, cur = [], None
for i, line in enumerate(wf_lines, 1):
    m = re.match(r'^\s*- name:\s*(.+?)\s*$', line)
    if m:
        if cur:
            steps.append(cur)
        cur = {"name": m.group(1), "run": None, "advisory": False, "line": i}
        continue
    if cur is None:
        continue
    if re.match(r'^\s*continue-on-error:\s*true\s*$', line):
        cur["advisory"] = True
    m = re.match(r'^\s*run:\s*(.+?)\s*$', line)
    if m:
        if m.group(1) in ("|", ">", "|-", ">-"):
            failures.append(
                "sigma.yml:{} uses a block-scalar `run:`, which this checker cannot read. "
                "Either keep run: single-line, or teach check-readme-gates.sh to fold "
                "block scalars.".format(i))
        cur["run"] = m.group(1)
if cur:
    steps.append(cur)

def key_of(cmd):
    """Command identity: the script path, or the tool's first two words."""
    first = cmd.split()[0].lstrip("./")
    if first.endswith(".sh"):
        return first
    return " ".join(cmd.split()[:2])

def has_check_flag(cmd):
    return "--check" in cmd.split()

runs = [s for s in steps if s["run"]]
advisory = [s for s in runs if s["advisory"]]
setup    = [s for s in runs if not s["advisory"] and s["run"].startswith("pip install")]
hard     = [s for s in runs if not s["advisory"] and s not in setup]

if not hard:
    failures.append("no hard gates parsed out of sigma.yml — the checker's step parsing "
                    "has broken, which would let real drift through silently.")

# ── parse the README's local command block ────────────────────────────────────
block = None
for m in re.finditer(r'```sh\n(.*?)```', doc, re.S):
    if "matching CI" in m.group(1):
        block = m.group(1)
        break
if block is None:
    failures.append("could not find the fenced ```sh block containing 'matching CI' in "
                    "detections/README.md — the local pre-push command block. If it moved "
                    "or was retitled, update this checker with it.")
    block = ""

# Join backslash continuations (the pip install line wraps), then strip trailing comments.
block = block.replace("\\\n", " ")
block_cmds = []
for raw in block.splitlines():
    line = raw.split("#", 1)[0].strip() if not raw.lstrip().startswith("#") else ""
    if line:
        block_cmds.append(line)
block_keys = {key_of(c): c for c in block_cmds}

# ── 1. COVERED ────────────────────────────────────────────────────────────────
for s in hard:
    k = key_of(s["run"])
    if k not in block_keys:
        failures.append(
            "sigma.yml runs '{}' as a hard gate (line {}, \"{}\") but detections/README.md's "
            "local block never tells anyone to run it. A contributor following the README "
            "goes green locally and fails in CI. Add it to the block and to the numbered "
            "list.".format(k, s["line"], s["name"]))
    elif has_check_flag(s["run"]) and not has_check_flag(block_keys[k]):
        failures.append(
            "sigma.yml runs '{}' with --check but the README's block runs it without. Those "
            "are opposite operations — one rewrites the generated artifact, the other proves "
            "it wasn't rewritten — so the documented command cannot reproduce the gate."
            .format(k))

# ── 2. NO PHANTOMS ────────────────────────────────────────────────────────────
all_run_keys = {key_of(s["run"]) for s in runs}
for k, cmd in sorted(block_keys.items()):
    if k not in all_run_keys:
        failures.append(
            "detections/README.md's local block runs '{}', which is not a step in "
            "sigma.yml. Either it was retired from CI and should come out of the block, or "
            "it should be a gate and isn't.".format(k))

# ── 3. COUNTS ─────────────────────────────────────────────────────────────────
WORDS = {"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,
         "nine":9,"ten":10,"eleven":11,"twelve":12}
m = re.search(r'\b([A-Za-z]+) hard checks?, (\w+) advisory\b', doc)
if not m:
    failures.append("could not find the 'N hard checks, one advisory' sentence in "
                    "detections/README.md; this checker asserts that count, so keep the "
                    "phrasing or update the checker.")
else:
    stated = WORDS.get(m.group(1).lower())
    stated_adv = WORDS.get(m.group(2).lower())
    if stated != len(hard):
        failures.append(
            "detections/README.md says '{} hard checks' but sigma.yml runs {}: {}."
            .format(m.group(1), len(hard), ", ".join(key_of(s["run"]) for s in hard)))
    if stated_adv != len(advisory):
        failures.append(
            "detections/README.md says '{} advisory' but sigma.yml has {} continue-on-error "
            "step(s).".format(m.group(2), len(advisory)))

numbered = re.findall(r'^(\d+)\. \*\*', doc, re.M)
expected = len(hard) + len(advisory)
if numbered and len(numbered) != expected:
    failures.append(
        "detections/README.md's numbered gate list has {} item(s); sigma.yml has {} "
        "({} hard + {} advisory). The list and the workflow disagree."
        .format(len(numbered), expected, len(hard), len(advisory)))
elif numbered and [int(n) for n in numbered] != list(range(1, len(numbered) + 1)):
    failures.append(
        "detections/README.md's numbered gate list is not 1..{} in order (got {}). "
        "Renumber after inserting a gate.".format(len(numbered), ", ".join(numbered)))

if failures:
    print("check-readme-gates: detections/README.md is out of step with "
          ".github/workflows/sigma.yml\n", file=sys.stderr)
    for f in failures:
        print("  - " + f, file=sys.stderr)
    print("", file=sys.stderr)
    sys.exit(1)

print("check-readme-gates: README matches sigma.yml "
      "({} hard gate(s), {} advisory, {} documented locally)"
      .format(len(hard), len(advisory), len(block_cmds)))
PY
