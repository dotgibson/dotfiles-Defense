#!/usr/bin/env bash
# detections/check-readme-tables.sh — assert that detections/README.md's rule tables and
# deploy-time tables still describe the corpus that actually ships.
# ──────────────────────────────────────────────────────────────────────────────
# WHY. Same argument as check-readme-gates.sh, applied to the other half of the README:
# "the README is load-bearing documentation, so it gets a gate like the rest of the
# load-bearing artifacts." Nothing tied these tables to detections/sigma/, so they drifted
# — by #314, twelve rules carried a DEPLOY-REQUIRED marker with no row in the deploy-time
# table, and three rules had no row in any per-directory table at all.
#
# The cost is specific in each direction.
#
#   A MISSING DEPLOY ROW is the expensive one. The marker is a YAML comment, and the
#   table's own preamble says so: "a comment isn't enforcement, so this is the
#   discoverable checklist instead." An operator reads the table before deploying and
#   fills each spot. A rule missing from it ships with an unfilled placeholder nobody was
#   told about — which is the failure half these rules' own comments describe at length
#   ("an unfilled list means every routine remediation alerts, someone mutes the rule, and
#   the mute takes the other arms with it").
#
#   A PHANTOM DEPLOY ROW is worse than a missing one. It tells an operator to go fill a
#   placeholder that is not there, which trains them to distrust the checklist.
#
#   A MISSING RULE ROW makes coverage read as smaller than it is. Before #314 the cloud
#   table listed one of three GCP rules, so GCP read as a third of what shipped — the same
#   class of error DEFENSE-METHODOLOGY.md's plane claim made, in a different artifact.
#
#   check-readme-tables.sh        # exit non-zero, naming each row, on a stale table
#
# Four assertions, two per table, both directions each:
#
#   1. every rule in detections/sigma/ is named in a per-directory rule table
#   2. every rule name in those tables is a real rule file
#   3. every rule carrying a DEPLOY-REQUIRED marker has a deploy-time row
#   4. every deploy-time row names a rule that carries the marker
#
# HOW THE REGIONS ARE FOUND. By heading text, and the script FAILS rather than passing if a
# heading moves or is renamed. That is deliberate: a silent pass on a region the script
# could not locate would report a clean bill for tables it never read, which is exactly the
# drift this exists to catch. Renaming a heading is meant to be a review conversation — the
# same reason splunk-precedence-allowlist.tsv is keyed on stanza title.
#
# ROW WIDTHS. The tables are wrapped to fixed pipe offsets and markdownlint's MD060 enforces
# the alignment, so a new row has hard per-column width limits. This script does not check
# that — `make markdown` does, and it is the gate that will fail if you paste a row in
# without padding it. Mentioned here because it is not obvious and it is what bites anyone
# adding rows in bulk.
#
# Usage: detections/check-readme-tables.sh [repo-root]
# Exit:  0 = both tables match the corpus;  1 = otherwise
set -uo pipefail

REPO="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$REPO" || exit 1

README="detections/README.md"
[ -r "$README" ] || {
  echo "::error::missing $README"
  exit 1
}

python3 - "$README" <<'PY'
import glob, os, re, sys

readme = sys.argv[1]
lines = open(readme).read().split("\n")

def find(pred, what):
    hits = [i for i, l in enumerate(lines) if pred(l)]
    if len(hits) != 1:
        print(f"::error::{readme}: expected exactly one {what} heading, found {len(hits)}.")
        print("  This script locates the tables by heading text and refuses to guess — a")
        print("  silent pass here would report a clean bill for a table it never read.")
        print("  Fix the heading, or update the matcher in detections/check-readme-tables.sh.")
        sys.exit(1)
    return hits[0]

RULES_START  = find(lambda l: l.startswith("### `sigma/`"), "`sigma/` rule-table section")
SUBS_START   = find(lambda l: l.startswith("#### Deploy-time substitutions"), "deploy-time substitutions")
BACKEND_START= find(lambda l: l.startswith("#### Deploy-time backend work"), "deploy-time backend work")
STATUS_START = find(lambda l: l.startswith("#### What `status:` means here"), "`status:` section")

def first_cell_names(lo, hi):
    """Backticked tokens in the first cell of every table row in [lo, hi)."""
    out = {}
    for i in range(lo, hi):
        if not lines[i].startswith("| `"):
            continue
        for tok in re.findall(r"`([^`]+)`", lines[i].split("|")[1]):
            out.setdefault(tok, i + 1)
    return out

files = sorted(glob.glob("detections/sigma/*/*.yml"))
stems = {os.path.basename(f)[:-4]: f for f in files}
marked = {f[len("detections/sigma/"):-4]: f
          for f in files if "DEPLOY-REQUIRED" in open(f).read()}

rc = 0
def fail(msg, rows, fix):
    global rc
    print(f"::error::{msg}")
    for r in rows:
        print(f"  {r}")
    print(f"  fix: {fix}")
    rc = 1

# 1 + 2 — per-directory rule tables
claimed = first_cell_names(RULES_START, SUBS_START)
missing = sorted(set(stems) - set(claimed))
if missing:
    fail(f"{len(missing)} rule(s) have no row in any per-directory rule table — the corpus "
         "is larger than the README says it is:",
         [f"{stems[s]}" for s in missing],
         f"add a row to the matching directory table in {readme}.")
phantom = sorted((t, ln) for t, ln in claimed.items() if t not in stems)
if phantom:
    fail(f"{len(phantom)} rule table row(s) name a rule that does not exist:",
         [f"{readme}:{ln}: `{t}`" for t, ln in phantom],
         "remove the row, or fix the name if the rule was renamed.")

# 3 + 4 — deploy-time tables (substitutions + backend work), keyed on dir/rule
deploy = first_cell_names(SUBS_START, STATUS_START)
missing = sorted(set(marked) - set(deploy))
if missing:
    fail(f"{len(missing)} rule(s) carry a DEPLOY-REQUIRED marker with no deploy-time row — "
         "they ship with a placeholder no operator was told to fill:",
         [marked[s] for s in missing],
         f"add a row under 'Deploy-time substitutions' in {readme}, or under "
         "'Deploy-time backend work' if the marker asks for work at the backend rather "
         "than a value to substitute.")
phantom = sorted((t, ln) for t, ln in deploy.items()
                 if t not in marked and "/" in t)
if phantom:
    fail(f"{len(phantom)} deploy-time row(s) name a rule with no DEPLOY-REQUIRED marker — "
         "each sends an operator to fill a placeholder that is not there:",
         [f"{readme}:{ln}: `{t}`" for t, ln in phantom],
         "remove the row, or restore the marker if it was dropped by accident.")

if rc == 0:
    print(f"check-readme-tables: README tables match the corpus "
          f"({len(stems)} rule(s) tabled, {len(marked)} DEPLOY-REQUIRED marker(s) listed)")
sys.exit(rc)
PY
