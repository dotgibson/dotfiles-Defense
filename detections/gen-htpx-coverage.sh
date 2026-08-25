#!/usr/bin/env bash
# detections/gen-htpx-coverage.sh — generate HTPX-COVERAGE.md, the report half of the
# Defense<->htpx boundary: where the two corpora meet, and where they do not.
# ──────────────────────────────────────────────────────────────────────────────
# WHY A REPORT AND NOT A GATE. check-htpx-pairing.sh fails the build on a dead CLAIM,
# because naming an entry that is not there is simply wrong. A GAP is not wrong. htpx spans
# Okta, Google Workspace, GitHub Actions, GitLab, Jenkins, Harbor, Vault, Terraform Cloud,
# Snowflake, Cloudflare, npm and PyPI; this repo has Sigma rules for a fraction of that, on
# purpose. A gate that failed on every uncovered blue entry would be red forever and would
# be silenced within a week. dotgibson/dotfiles-Defense#196 asked for the split explicitly
# and warned that a strict bidirectional foreign key would fight the two corpora's
# different granularity.
#
# So this renders the gaps into a versioned artifact and DRIFT-GATES it instead. The report
# never fails on its own content; it fails when the committed file stops matching what the
# rules and the pinned corpus actually say. That turns "coverage changed" into a diff in a
# PR someone reads — the same trade navigator/COVERAGE.md already makes for ATT&CK coverage,
# and the reason that gate is worth having.
#
#   gen-htpx-coverage.sh            # (re)write HTPX-COVERAGE.md
#   gen-htpx-coverage.sh --check    # exit 1 (with a diff) if the committed report is stale
#
# DETERMINISM. The output is a function of detections/sigma/ plus the corpus at the commit
# in detections/htpx.pin — both fixed by this repo's tree — so --check is meaningful. It
# would not be if this read htpx main, which is the whole argument for the pin.
#
# DECLARED HOLES ARE READ, NOT LISTED HERE. htpx requires pair_note: on any entry carrying
# pair: null (dotgibson/htpx#98), so an upstream entry that is unpaired ON PURPOSE says why
# in its own frontmatter. This report renders that reason verbatim rather than keeping a
# local allowlist of "known unpaired" ids — a second copy of someone else's decision is the
# thing that goes stale.
#
# Pure stdlib Python, like the other generators here — no deps beyond python3.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd -- "$HERE/.." && pwd)"
OUT="$HERE/HTPX-COVERAGE.md"

CHECK=0
if [[ $# -gt 1 ]]; then
  echo "gen-htpx-coverage: too many arguments" >&2
  echo "usage: gen-htpx-coverage.sh [--check]" >&2
  exit 2
fi
case "${1:-}" in
"") CHECK=0 ;;
--check) CHECK=1 ;;
*)
  echo "gen-htpx-coverage: unknown argument '$1'" >&2
  echo "usage: gen-htpx-coverage.sh [--check]" >&2
  exit 2
  ;;
esac

CORPUS="$("$HERE/htpx-corpus.sh")"

generate() {
  REPO_ROOT="$REPO_ROOT" CORPUS="$CORPUS" python3 - <<'PY'
import os, re, glob

repo = os.environ["REPO_ROOT"]
corpus = os.environ["CORPUS"]

# ── the pinned htpx corpus ────────────────────────────────────────────────────
def frontmatter(path):
    t = open(path, encoding="utf-8").read()
    m = re.match(r'^---\n(.*?)\n---\n', t, re.S)
    return m.group(1) if m else ""

def scalar(fm, key):
    m = re.search(r'^%s:\s*(.*)$' % key, fm, re.M)
    return m.group(1).strip() if m else None

def block(fm, key):
    """A YAML block scalar (`key: >-` + indented lines) or a plain one-line value."""
    m = re.search(r'^%s:\s*(?:[>|][-+]?)?\s*\n((?:[ \t]+.*\n?)+)' % key, fm, re.M)
    if m:
        return " ".join(l.strip() for l in m.group(1).splitlines() if l.strip())
    return scalar(fm, key)

TECHS = re.compile(r'T\d{4}(?:\.\d{3})?')

entries = {"red": {}, "blue": {}}
for colour in entries:
    for path in sorted(glob.glob(os.path.join(corpus, "entries", colour, "*.md"))):
        fm = frontmatter(path)
        am = re.search(r'^attack:\s*\n((?:[ \t]+.*\n)+)', fm, re.M)
        entries[colour][os.path.basename(path)[:-3]] = {
            "id": scalar(fm, "id"),
            "title": scalar(fm, "title") or "",
            "pair": scalar(fm, "pair"),
            "pair_note": block(fm, "pair_note"),
            "techs": sorted(set(TECHS.findall(am.group(1)))) if am else [],
        }

htpx_techs = set()
for colour in entries:
    for e in entries[colour].values():
        htpx_techs.update(e["techs"])

# ── this repo's Sigma rules, and the htpx entries each one claims ─────────────
URL = re.compile(
    r'https://github\.com/dotgibson/htpx/blob/[^/\s]+/entries/(red|blue)/([a-z0-9][a-z0-9-]*)\.md')
PROSE = re.compile(r'htpx pairs?:?[ \t\n]+(.{0,160})', re.I | re.S)
IDLIKE = re.compile(r'^[a-z0-9]+(?:-[a-z0-9]+)+$')
CONNECTOR = {"<->", "/", "&", "and", "<-", "->"}
COMMENT_LEAD = {"#", "##", "###", "##!", "//", "--", "*", "-", "|"}

by_id = {}
for colour, stems in entries.items():
    for stem, e in stems.items():
        if e["id"]:
            by_id[e["id"]] = (colour, stem)

# Claim extraction matches check-htpx-pairing.sh exactly; that gate has already proved
# every id below resolves, so this one never has to report a miss.
def claims(text):
    out = set()
    for colour, stem in URL.findall(text):
        out.add((colour, stem))
    for tail in PROSE.findall(text):
        for raw in tail.split():
            tok = raw.strip('`*"\'')
            if tok in COMMENT_LEAD or tok in CONNECTOR:
                continue
            if tok.startswith("("):
                break
            trimmed = tok.rstrip(').,;:')
            closes = trimmed != tok
            tok = trimmed
            if not IDLIKE.match(tok):
                break
            if tok in by_id:
                out.add(by_id[tok])
            if closes:
                break
    return out

# Scan every artifact that can name an entry, not just sigma/. Eight blue entries are
# claimed only by a Sentinel analytics rule, a Zeek script or a Splunk correlation search —
# real detection content that is not a Sigma rule — and listing those as "nothing here
# covers it" would be false. Same file set as check-htpx-pairing.sh, so the two agree on
# what a claim is; a Sigma rule is shown by its stem, anything else by its path.
SCANNABLE = {".md", ".yml", ".yaml", ".sh", ".conf", ".zeek", ".rules", ".tsv", ".pin",
             ".lucene", ".kql"}
targets = []
for root, dirs, files in os.walk(os.path.join(repo, "detections")):
    dirs[:] = [d for d in dirs if d not in (".git", "__pycache__")]
    for f in files:
        if os.path.splitext(f)[1] not in SCANNABLE:
            continue
        if ".generated." in f or f.startswith("htpx") or f in (
                "check-htpx-pairing.sh", "HTPX-COVERAGE.md"):
            continue
        targets.append(os.path.join(root, f))
for extra in ("DEFENSE-METHODOLOGY.md", "README.md"):
    q = os.path.join(repo, extra)
    if os.path.isfile(q):
        targets.append(q)

sigma_dir = os.path.join(repo, "detections", "sigma") + os.sep
blue_to_rules = {}
rule_techs = {}
for path in sorted(targets):
    try:
        text = open(path, encoding="utf-8").read()
    except (UnicodeDecodeError, OSError):
        continue
    is_sigma = path.startswith(sigma_dir) and path.endswith(".yml")
    label = os.path.basename(path)[:-4] if is_sigma else os.path.relpath(path, repo)
    if is_sigma:
        rule_techs[label] = sorted({"T" + m.group(1)[1:].upper()
                                    for m in re.finditer(r'attack\.(t\d{4}(?:\.\d{3})?)', text)})
    for colour, entry_stem in claims(text):
        if colour == "blue":
            blue_to_rules.setdefault(entry_stem, set()).add((is_sigma, label))

defense_techs = {}
for stem, techs in rule_techs.items():
    for t in techs:
        defense_techs.setdefault(t, set()).add(stem)

# ── render ────────────────────────────────────────────────────────────────────
blue = entries["blue"]
claimed = sorted(s for s in blue if s in blue_to_rules)
unclaimed = sorted(s for s in blue if s not in blue_to_rules)
uncovered = sorted((t for t in defense_techs if t not in htpx_techs),
                   key=lambda t: (int(t[1:].partition(".")[0]),
                                  int(t.partition(".")[2] or -1)))
holes = sorted(s for s, e in entries["red"].items() if e["pair"] in (None, "", "null"))

pin = {}
for line in open(os.path.join(repo, "detections", "htpx.pin"), encoding="utf-8"):
    if line.startswith("#") or "\t" not in line:
        continue
    k, _, v = line.partition("\t")
    pin[k.strip()] = v.strip()

L = []
L.append("# Defense ↔ htpx pairing coverage — GENERATED by detections/gen-htpx-coverage.sh. DO NOT EDIT")
L.append("")
L.append("Where this repo's Sigma rules meet the [htpx](https://github.com/dotgibson/htpx) "
         "red↔blue corpus, and where they do not. Regenerate with "
         "`detections/gen-htpx-coverage.sh`; CI drift-gates it with "
         "`gen-htpx-coverage.sh --check`.")
L.append("")
L.append("A **gap here is not a defect.** htpx spans SaaS and CI/CD platforms this repo has "
         "no rules for, by design — this report exists so the shape of that boundary is "
         "reviewable instead of assumed. A dead *claim* is a different matter and fails the "
         "build in `detections/check-htpx-pairing.sh`.")
L.append("")
L.append("Corpus: `{}` at `{}` ({}), pinned in `detections/htpx.pin`."
         .format(pin.get("repo", "?"), pin.get("sha", "?")[:12], pin.get("tag", "?")))
L.append("")
def plural(n, one, many):
    return "{} {}".format(n, one if n == 1 else many)

L.append("**{} · {} claimed here · {} no htpx entry covers · {} upstream.**".format(
    plural(len(blue), "blue entry", "blue entries"),
    len(claimed),
    plural(len(uncovered), "Sigma technique", "Sigma techniques"),
    plural(len(holes), "declared hole", "declared holes")))
L.append("")

L.append("## htpx blue entries claimed by detection content here")
L.append("")
L.append("| htpx blue entry | ATT&CK | Claimed by |")
L.append("| --------------- | ------ | ------------- |")
for stem in claimed:
    e = blue[stem]
    rules = ", ".join("`{}`".format(label)
                      for _, label in sorted(blue_to_rules[stem], key=lambda x: (not x[0], x[1])))
    L.append("| `{}` | {} | {} |".format(stem, ", ".join(e["techs"]) or "—", rules))
L.append("")

L.append("## htpx blue entries nothing here claims")
L.append("")
L.append("The other side of the boundary. Each is a detection the corpus documents and this "
         "repo does not implement — a candidate, not a defect.")
L.append("")
L.append("| htpx blue entry | ATT&CK | Title |")
L.append("| --------------- | ------ | ----- |")
for stem in unclaimed:
    e = blue[stem]
    L.append("| `{}` | {} | {} |".format(stem, ", ".join(e["techs"]) or "—", e["title"]))
L.append("")

L.append("## Sigma techniques no htpx entry covers")
L.append("")
L.append("Techniques this repo detects that the corpus has no attack for — so there is "
         "nothing to run from `dotfiles-Offense` to prove the rule fires.")
L.append("")
L.append("| Technique | Rules |")
L.append("| --------- | ----- |")
for t in uncovered:
    L.append("| {} | {} |".format(
        t, ", ".join("`{}`".format(r) for r in sorted(defense_techs[t]))))
L.append("")

L.append("## Declared holes upstream (`pair: null`)")
L.append("")
L.append("Red entries htpx ships deliberately unpaired. The reason is read from each entry's "
         "`pair_note:`, which htpx's CI requires whenever `pair:` is null "
         "([htpx#98](https://github.com/dotgibson/htpx/pull/98)) — so these are excluded by "
         "field, not by an allowlist kept here.")
L.append("")
L.append("| htpx red entry | Reason (`pair_note:`) |")
L.append("| -------------- | --------------------- |")
for stem in holes:
    note = entries["red"][stem]["pair_note"] or "**no `pair_note:` — upstream CI should have caught this**"
    L.append("| `{}` | {} |".format(stem, note))

# No trailing blank element: print() terminates the last line already, and a final
# L.append("") would end the file "|\n\n" — the MD012 trailing-blank-line defect
# navigator/gen-coverage.sh documents. A generated file has to be fixed in its generator.
print("\n".join(L).rstrip("\n"))
PY
}

if [[ "$CHECK" -eq 1 ]]; then
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  generate >"$tmp"
  if ! diff -u "$OUT" "$tmp" >/dev/null 2>&1; then
    echo "gen-htpx-coverage: $OUT is out of date — run detections/gen-htpx-coverage.sh" >&2
    diff -u "$OUT" "$tmp" >&2 || true
    exit 1
  fi
  echo "gen-htpx-coverage: HTPX-COVERAGE.md up to date"
else
  generate >"$OUT"
  echo "gen-htpx-coverage: wrote $OUT"
fi
