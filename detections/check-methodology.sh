#!/usr/bin/env bash
# detections/check-methodology.sh — assert that DEFENSE-METHODOLOGY.md's claims about
# the corpus are still true, so the one hand-written map of the detection layer can't
# quietly rot the way the generated artifacts can't.
# ──────────────────────────────────────────────────────────────────────────────
# The navigator/ and siem/ artifacts are GENERATED and drift-gated by regenerating and
# diffing. DEFENSE-METHODOLOGY.md can't work that way: two of its table's four columns
# (the prose data-source summary and the Kali fold names) are editorial judgement that no
# generator can emit. So this is a CHECKER, not a generator — it asserts the subset of
# the document's claims that ARE machine-checkable and leaves the prose alone.
#
#   check-methodology.sh        # exit non-zero, with a specific reason, on a stale claim
#
# Two assertions:
#
#   1. PATHS — every backticked repo-relative path in the doc exists. Catches a rule
#      directory being renamed out from under a paragraph that points at it.
#   2. TECHNIQUES — every ATT&CK technique id cited in the doc is either covered by a
#      rule in detections/sigma/, or declared absent in the doc's own known-absent
#      marker. Catches BOTH directions:
#        - citing a technique as covered when nothing covers it, and
#        - a technique the doc calls a gap quietly becoming covered — which is the
#          moment the surrounding prose ("add network to this row when it lands") stops
#          being true and needs a human.
#
# The marker lives in the document it constrains:
#
#   <!-- methodology-check: known-absent = T1496.001 -->
#
# Deliberately NOT checked: the "Primary data sources" and "Validate with (Kali)"
# columns. The first is a generalised prose summary on purpose — enumerating every
# command primitive there is what made it go stale in the first place — and the second
# names folds in a repo this gate can't see. Gating either would produce a brittle check
# that fights the writing rather than protecting it.
#
# Pure stdlib Python — no deps beyond the python3 the sigma job already installs.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd -- "$HERE/.." && pwd)"
DOC="$REPO_ROOT/DEFENSE-METHODOLOGY.md"
SIGMA="$HERE/sigma"

if [[ $# -gt 0 ]]; then
  echo "check-methodology: unexpected argument '$1'" >&2
  echo "usage: check-methodology.sh" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "check-methodology: python3 not found" >&2
  exit 1
fi

[[ -f "$DOC" ]] || {
  echo "check-methodology: $DOC not found" >&2
  exit 1
}

DOC="$DOC" SIGMA_DIR="$SIGMA" REPO_ROOT="$REPO_ROOT" python3 - <<'PY'
import glob, os, re, sys

doc_path = os.environ["DOC"]
sigma = os.environ["SIGMA_DIR"]
root = os.environ["REPO_ROOT"]
text = open(doc_path, encoding="utf-8").read()
failures = []

# ── 1. paths ──────────────────────────────────────────────────────────────────
# Only backticked tokens that look like repo-relative paths: they contain a "/" and
# don't start with ~ (home), / (absolute) or a scheme. Bare filenames are skipped on
# purpose — PURPLE-TEAM.md and OFFENSIVE-METHODOLOGY.md live in the Kali repo, which
# this gate cannot see, and guessing at them would fail on a correct document.
for tok in sorted(set(re.findall(r'`([^`\s]+)`', text))):
    if "/" not in tok or tok.startswith(("~", "/", "http://", "https://")):
        continue
    if not os.path.exists(os.path.join(root, tok.rstrip("/"))):
        failures.append(
            "path does not exist: `{}` is referenced by DEFENSE-METHODOLOGY.md".format(tok)
        )

# ── 2. techniques ─────────────────────────────────────────────────────────────
# The marker is stripped BEFORE counting citations, or it satisfies itself: an id
# written only inside the marker would count as "cited by the document", so padding the
# marker with ids the prose never mentions would pass silently and the stale-entry check
# below could never fire.
marker_re = r'<!--\s*methodology-check:\s*known-absent\s*=\s*([^>]*?)\s*-->'
prose = re.sub(marker_re, '', text, flags=re.S)

# \bT#### with an optional .### sub-technique. TA0043-style tactic ids don't match
# (no digit directly after the T), which is what we want — this checks techniques.
cited = set(re.findall(r'\bT\d{4}(?:\.\d{3})?\b', prose))

covered = set()
for path in glob.glob(os.path.join(sigma, "*", "*.yml")):
    body = open(path, encoding="utf-8").read()
    for m in re.finditer(r'attack\.(t\d+(?:\.\d+)?)', body, re.IGNORECASE):
        covered.add("T" + m.group(1)[1:].upper())

marker = re.search(marker_re, text)
declared = set()
if marker:
    # Upper-cased so a marker written `t1496.001` compares equal to the `T1496.001` the
    # citation regex finds, instead of reading as an unrelated (and therefore stale) id.
    declared = {t.upper() for t in re.split(r'[,\s]+', marker.group(1)) if t}
elif cited - covered:
    failures.append(
        "DEFENSE-METHODOLOGY.md cites technique(s) no Sigma rule covers ({}) and has no "
        "known-absent marker. Add one, e.g.\n"
        "    <!-- methodology-check: known-absent = {} -->".format(
            ", ".join(sorted(cited - covered)), " ".join(sorted(cited - covered))
        )
    )

actually_absent = cited - covered
if marker:
    undeclared = actually_absent - declared
    if undeclared:
        failures.append(
            "DEFENSE-METHODOLOGY.md cites {} as though covered, but no rule in "
            "detections/sigma/ tags it. Either write the detection, or add it to the "
            "known-absent marker.".format(", ".join(sorted(undeclared)))
        )
    # The inverse, and the more interesting one: a declared gap that got filled. The
    # prose around it ("add network to this row when it lands") is now stale.
    stale = declared - actually_absent
    for tid in sorted(stale):
        if tid in covered:
            failures.append(
                "{} is declared known-absent in DEFENSE-METHODOLOGY.md, but a rule in "
                "detections/sigma/ now covers it. The gap closed — update the table row "
                "and the prose describing the gap, then drop it from the marker.".format(tid)
            )
        else:
            failures.append(
                "{} is in the known-absent marker but isn't cited anywhere in "
                "DEFENSE-METHODOLOGY.md. Drop it from the marker.".format(tid)
            )

if failures:
    print("check-methodology: DEFENSE-METHODOLOGY.md is out of step with the corpus\n",
          file=sys.stderr)
    for f in failures:
        print("  - " + f, file=sys.stderr)
    print("", file=sys.stderr)
    sys.exit(1)

print("check-methodology: DEFENSE-METHODOLOGY.md claims check out "
      "({} technique(s) cited, {} declared absent)".format(len(cited), len(declared)))
PY
