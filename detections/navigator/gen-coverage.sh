#!/usr/bin/env bash
# detections/navigator/gen-coverage.sh — generate a human-readable ATT&CK coverage
# report (COVERAGE.md) from the Sigma rules, so the corpus's coverage is a versioned,
# reviewable artifact alongside the machine-readable Navigator layer.
# ──────────────────────────────────────────────────────────────────────────────
# Sigma is the source of truth (detections/sigma/). Every rule carries ATT&CK tactic
# tags (attack.<tactic>) and technique tags (attack.tXXXX[.YYY]) and a logsource. This
# rolls them up three ways — by tactic, by technique, and by logsource — into a
# Markdown coverage matrix. It is the prose companion to coverage-layer.json (the
# Navigator layer gen-navigator.sh emits); this one is for humans reading the repo.
#
#   gen-coverage.sh            # (re)write navigator/COVERAGE.md from sigma/
#   gen-coverage.sh --check    # exit 1 (with a diff) if the committed report is stale
#
# --check is the drift gate (CI runs it in .github/workflows/sigma.yml); the bare form
# is what you run after adding/retagging a rule. Pure stdlib Python — no extra deps
# beyond the python3 the sigma job already installs.
#
# "Rules" counts rule FILES (matching the README's 64-rules convention); "documents"
# counts YAML documents (title: lines) — the two correlation files hold two each.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SIGMA="$HERE/../sigma"
OUT="$HERE/COVERAGE.md"

CHECK=0
if [[ $# -gt 1 ]]; then
  echo "gen-coverage: too many arguments" >&2
  echo "usage: gen-coverage.sh [--check]" >&2
  exit 2
fi
case "${1:-}" in
"") CHECK=0 ;;
--check) CHECK=1 ;;
*)
  echo "gen-coverage: unknown argument '$1'" >&2
  echo "usage: gen-coverage.sh [--check]" >&2
  exit 2
  ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  echo "gen-coverage: python3 not found" >&2
  exit 1
fi

generate() {
  SIGMA_DIR="$SIGMA" python3 - <<'PY'
import glob, os, re

sigma = os.environ["SIGMA_DIR"]

# ATT&CK enterprise tactics: tag slug -> (display name, TA id). Slugs are the Sigma
# tag spelling — multi-word tactics hyphenate, which is what the ATT&CK tag validator
# accepts. ATT&CK v19 (Apr 2026) split Defense Evasion into Stealth (TA0005, the same
# id renamed) and Defense Impairment (TA0112); a slug missing from this table is
# silently dropped from the tactic roll-up, so it has to track the corpus's tags.
# Matching against this
# fixed set (not any attack.\w+) keeps reference URLs (attack.mitre.org) and technique
# tags (attack.tNNNN) out of the tactic tally. Ordered by the kill chain.
TACTICS = [
    ("reconnaissance", "Reconnaissance", "TA0043"),
    ("resource-development", "Resource Development", "TA0042"),
    ("initial-access", "Initial Access", "TA0001"),
    ("execution", "Execution", "TA0002"),
    ("persistence", "Persistence", "TA0003"),
    ("privilege-escalation", "Privilege Escalation", "TA0004"),
    ("stealth", "Stealth", "TA0005"),
    ("defense-impairment", "Defense Impairment", "TA0112"),
    ("credential-access", "Credential Access", "TA0006"),
    ("discovery", "Discovery", "TA0007"),
    ("lateral-movement", "Lateral Movement", "TA0008"),
    ("collection", "Collection", "TA0009"),
    ("command-and-control", "Command and Control", "TA0011"),
    ("exfiltration", "Exfiltration", "TA0010"),
    ("impact", "Impact", "TA0040"),
]
TAC_ORDER = {slug: i for i, (slug, _, _) in enumerate(TACTICS)}
TAC_NAME = {slug: (name, tid) for slug, name, tid in TACTICS}

tech_re = re.compile(r'attack\.(t\d+(?:\.\d+)?)', re.IGNORECASE)
prod_re = re.compile(r'^\s*product:\s*(\S+)\s*$', re.MULTILINE)
title_re = re.compile(r'^title:\s*.+$', re.MULTILINE)

files = sorted(glob.glob(os.path.join(sigma, "*", "*.yml")))
n_files = len(files)
n_docs = 0

tac_tech = {}   # tactic slug -> set(technique ids)
tac_rules = {}  # tactic slug -> set(rule stems)
tech_rules = {} # technique id -> set(rule stems)
dir_rules = {}  # dir -> set(rule stems)
dir_prod = {}   # dir -> set(product)

for path in files:
    text = open(path, encoding="utf-8").read()
    stem = os.path.splitext(os.path.basename(path))[0]
    d = os.path.basename(os.path.dirname(path))
    n_docs += len(title_re.findall(text))

    techs = {"T" + m.group(1)[1:].upper() for m in tech_re.finditer(text)}
    tactics = [slug for slug in TAC_ORDER if re.search(r'attack\.' + slug + r'\b', text)]

    for t in techs:
        tech_rules.setdefault(t, set()).add(stem)
    for slug in tactics:
        tac_tech.setdefault(slug, set()).update(techs)
        tac_rules.setdefault(slug, set()).add(stem)
    dir_rules.setdefault(d, set()).add(stem)
    for m in prod_re.finditer(text):
        dir_prod.setdefault(d, set()).add(m.group(1))

n_tech = len(tech_rules)
n_tac = len(tac_rules)
n_dirs = len(dir_rules)

def tech_sort(t):
    # T1098 / T1098.001 -> numeric sort on the base then the sub
    base, _, sub = t[1:].partition(".")
    return (int(base), int(sub) if sub else -1)

L = []
L.append("# Detection coverage — GENERATED by detections/navigator/gen-coverage.sh. DO NOT EDIT")
L.append("")
L.append("Rolls up every Sigma rule in `detections/sigma/` by ATT&CK **tactic**, "
         "**technique**, and **logsource**. Regenerate with "
         "`detections/navigator/gen-coverage.sh`; CI drift-gates it with "
         "`gen-coverage.sh --check`. Prose companion to `coverage-layer.json` "
         "(the machine-readable Navigator layer).")
L.append("")
L.append("**{} rules · {} detection documents · {} techniques · {} tactics · {} logsources.**"
         .format(n_files, n_docs, n_tech, n_tac, n_dirs))
L.append("")
L.append("## By ATT&CK tactic")
L.append("")
L.append("| Tactic | ID | Techniques | Rules |")
L.append("| ------ | -- | ---------: | ----: |")
for slug in sorted(tac_rules, key=lambda s: TAC_ORDER[s]):
    name, tid = TAC_NAME[slug]
    L.append("| {} | {} | {} | {} |".format(name, tid, len(tac_tech[slug]), len(tac_rules[slug])))
L.append("")
L.append("## By technique")
L.append("")
L.append("| Technique | Rules | Detections |")
L.append("| --------- | ----: | ---------- |")
for t in sorted(tech_rules, key=tech_sort):
    rules = ", ".join("`{}`".format(r) for r in sorted(tech_rules[t]))
    L.append("| {} | {} | {} |".format(t, len(tech_rules[t]), rules))
L.append("")
L.append("## By logsource")
L.append("")
L.append("| Directory | product | Rules |")
L.append("| --------- | ------- | ----: |")
for d in sorted(dir_rules):
    prods = ", ".join("`{}`".format(p) for p in sorted(dir_prod.get(d, set()))) or "—"
    L.append("| `{}` | {} | {} |".format(d, prods, len(dir_rules[d])))
L.append("")
print("\n".join(L))
PY
}

if [[ "$CHECK" -eq 1 ]]; then
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  generate >"$tmp"
  if ! diff -u "$OUT" "$tmp" >/dev/null 2>&1; then
    echo "gen-coverage: $OUT is out of date — run detections/navigator/gen-coverage.sh" >&2
    diff -u "$OUT" "$tmp" >&2 || true
    exit 1
  fi
  echo "gen-coverage: COVERAGE.md up to date"
else
  generate >"$OUT"
  echo "gen-coverage: wrote $OUT"
fi
