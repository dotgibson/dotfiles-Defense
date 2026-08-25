#!/usr/bin/env bash
# detections/check-htpx-pairing.sh — assert that every htpx entry this repo NAMES still
# exists upstream, and still pairs back the way the naming rule claims it does.
# ──────────────────────────────────────────────────────────────────────────────
# WHY. detections/README.md's opening promise is that each rule "names the exact
# dotfiles-Offense hacktheplanet fold and htpx pair that reproduces it — so the purple
# loop is closed in the file itself." Rules keep that promise two ways: ~80 references:
# URLs pointing at entries/blue/<id>.md, and `htpx pair <id>` in the validation note.
#
# Nothing verified either one. htpx is a separate repo with its own release cycle, so an
# entry renamed there left a rule here pointing at a 404 — and the only way to find out was
# for a human to click the link. Adopting this gate found four: bloodhound-sharphound was
# renamed bloodhound-collect upstream (two references), and archive-staging-rar /
# local-data-collection name entries htpx has never had. dotgibson/dotfiles-Defense#196.
#
# WHAT IT ASSERTS, AND WHAT IT DELIBERATELY DOES NOT. This gates CLAIMS, not COVERAGE.
# Naming an entry is a factual assertion about another repo and is either true or false, so
# a false one fails the build. Whether some blue entry lacks a Sigma rule, or some technique
# here has no htpx entry, is a judgement about scope — the two corpora legitimately have
# different granularity, htpx spanning SaaS and CI/CD platforms this repo has no rules for.
# That belongs in navigator/gen-htpx-coverage.sh's report, which drift-gates but never fails
# on a gap. #196 asked for exactly this split; a strict bidirectional foreign key would fight
# the corpora instead of protecting them.
#
# Three assertions:
#
#   1. URL CLAIMS   — every https://github.com/dotgibson/htpx/blob/<ref>/entries/<colour>/
#                     <id>.md resolves to a file in the pinned corpus whose own id: matches.
#                     The id inside the file is checked too: a path can survive a rename that
#                     the frontmatter did not.
#   2. PROSE CLAIMS — every `htpx pair <id>` names a real entry, either colour.
#   3. TABLE CLAIMS — the "Validate with (Offense fold · htpx pair)" column in
#                     detections/README.md names an entry per rule, 82 of them. It is the
#                     same promise in table form, and it rotted the same way: four of the
#                     eight defects this gate found on adoption were in that column alone.
#                     A cell whose last `·` segment is not id-shaped is prose ("PURPLE-TEAM
#                     4648 row", "the same sweep from an interactive PowerShell session") and
#                     is skipped — 17 of 99 cells, none of them a claim.
#   4. BACK-REFS    — a blue entry this repo names must point at a red entry that exists and
#                     points back. htpx's own ci.yml enforces this inside the corpus; the
#                     value of repeating it here is that a rule can name a blue entry that is
#                     itself half of a broken pair, which upstream CI catches only after the
#                     fact.
#
# There is NO allowlist, unlike the splunk-precedence and no-fixture gates. Those exist
# because a violation there can be a signed-off judgement call. Here the only way to fail is
# to name an entry that is not there, and the fix is to correct the name — an allowlist would
# just be a place to write down a link you know is dead.
#
# GENERATED FILES ARE SKIPPED (*.generated.*). savedsearches.generated.conf carries every
# rule description verbatim, so scanning it reports each defect twice and points the reader
# at a file they must not edit. Fix the rule, regenerate, and the copy follows.
#
# The corpus comes from detections/htpx-corpus.sh at the commit in detections/htpx.pin — so
# this gate's verdict is a function of this repo's tree, not of whatever htpx main did today.
# Same reasoning as attack-data.pin; read that file's header for the long version.
#
#   check-htpx-pairing.sh                # exit non-zero, naming the file and the dead id
#   check-htpx-pairing.sh --list-claims  # print every entry this repo names, one per line
#
# --list-claims is a DATA QUERY, not a check: it prints `<colour>\t<stem>` for every entry
# named anywhere above and exits 0 even when a claim is dead. htpx-drift.yml uses it to ask
# "did upstream delete something we point at", and the point of routing that through this
# script is that there is then only ONE implementation of what counts as a claim. There are
# already two readers of that definition (this and gen-htpx-coverage.sh, which documents
# that it matches); a third, hand-rolled inside a workflow, is how they start disagreeing.
#
# Exit: 0 = every claim resolves (or --list-claims);  1 = a claim is dead, or the corpus is
#       unavailable;  2 = bad invocation
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

LIST=0
if [[ $# -gt 1 ]]; then
  echo "check-htpx-pairing: too many arguments" >&2
  echo "usage: check-htpx-pairing.sh [--list-claims]" >&2
  exit 2
fi
case "${1:-}" in
"") LIST=0 ;;
--list-claims) LIST=1 ;;
*)
  echo "check-htpx-pairing: unknown argument '$1'" >&2
  echo "usage: check-htpx-pairing.sh [--list-claims]" >&2
  exit 2
  ;;
esac

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd -- "$HERE/.." && pwd)"

CORPUS="$("$HERE/htpx-corpus.sh")" || exit 1

REPO_ROOT="$REPO_ROOT" CORPUS="$CORPUS" LIST="$LIST" python3 - <<'PY'
import os, re, sys, glob

repo = os.environ["REPO_ROOT"]
corpus = os.environ["CORPUS"]
failures = []

# ── the pinned corpus ─────────────────────────────────────────────────────────
def frontmatter(path):
    text = open(path, encoding="utf-8").read()
    m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
    return m.group(1) if m else ""

def field(fm, key):
    m = re.search(r'^%s:\s*(.*)$' % key, fm, re.M)
    return m.group(1).strip() if m else None

entries = {"red": {}, "blue": {}}   # colour -> stem -> {"id":…, "pair":…}
for colour in entries:
    for path in glob.glob(os.path.join(corpus, "entries", colour, "*.md")):
        fm = frontmatter(path)
        entries[colour][os.path.basename(path)[:-3]] = {
            "id": field(fm, "id"), "pair": field(fm, "pair")}
if not entries["red"] or not entries["blue"]:
    print("::error::the pinned corpus at %s has no entries — refusing to pass vacuously"
          % corpus, file=sys.stderr)
    sys.exit(1)

by_id = {}
for colour, stems in entries.items():
    for stem, e in stems.items():
        if e["id"]:
            by_id[e["id"]] = (colour, stem, e)

# ── the files that make claims ────────────────────────────────────────────────
# Everything this repo owns that could name an entry. core/ is excluded (vendored, gated
# upstream) and so is this gate's own documentation, which quotes dead ids on purpose.
SCANNABLE = {".md", ".yml", ".yaml", ".sh", ".conf", ".zeek", ".rules", ".tsv", ".pin",
             ".lucene", ".kql"}
targets = []
for root, dirs, files in os.walk(os.path.join(repo, "detections")):
    dirs[:] = [d for d in dirs if d not in (".git", "__pycache__")]
    for f in files:
        if os.path.splitext(f)[1] not in SCANNABLE:
            continue
        if ".generated." in f:          # derived from the rules; fix the source
            continue
        if f.startswith("htpx") or f == "check-htpx-pairing.sh":
            continue
        targets.append(os.path.join(root, f))
for extra in ("DEFENSE-METHODOLOGY.md", "README.md"):
    p = os.path.join(repo, extra)
    if os.path.isfile(p):
        targets.append(p)

# ── 1. URL claims ─────────────────────────────────────────────────────────────
URL = re.compile(
    r'https://github\.com/dotgibson/htpx/blob/[^/\s]+/entries/(red|blue)/([a-z0-9][a-z0-9-]*)\.md')

named_blue = set()
# Every entry named, both colours. named_blue drives the back-reference check; this drives
# --list-claims, which has to report a deleted RED entry too — prose names those.
named = set()
listing = os.environ.get("LIST") == "1"
for path in targets:
    rel = os.path.relpath(path, repo)
    try:
        text = open(path, encoding="utf-8").read()
    except (UnicodeDecodeError, OSError):
        continue
    for colour, stem in URL.findall(text):
        if stem not in entries[colour]:
            failures.append(
                "{}: references entries/{}/{}.md, which is not in the pinned htpx corpus. "
                "The entry was renamed or retired upstream — find its new id and update the "
                "reference (do NOT bump detections/htpx.pin to make this go away).".format(
                    rel, colour, stem))
            continue
        got = entries[colour][stem]["id"]
        if got != stem:
            failures.append(
                "{}: references entries/{}/{}.md, but that file's own id: is '{}'. The path "
                "survived a rename the frontmatter did not — cite '{}'.".format(
                    rel, colour, stem, got, got))
        named.add((colour, stem))
        if colour == "blue":
            named_blue.add(stem)

# ── 2. prose claims ───────────────────────────────────────────────────────────
# `htpx pair <id>`, `htpx pair: <a> / <b>`, `htpx pair <a> <-> <b>`, `htpx pairs <a>,`.
# The claim ends at the first token that is not an id — which is what keeps English out of
# the check. Three token rules, each earned from a real line in this repo:
#   - a LEADING '(' ends the claim    ("… <-> icmp-c2-volume (T1095, …")
#   - a comment leader is SKIPPED     (a claim wrapped onto a Zeek '##!' continuation line)
#   - trailing ).,;: is stripped, and CLOSES the list ("htpx pair consent-grant; companion-
#     only, M365/Entra section" — consent-grant is the claim, the rest is prose that happens
#     to be hyphenated, and reading on turns it into a phantom id)
PROSE = re.compile(r'htpx pairs?:?[ \t\n]+(.{0,160})', re.I | re.S)
IDLIKE = re.compile(r'^[a-z0-9]+(?:-[a-z0-9]+)+$')
CONNECTOR = {"<->", "/", "&", "and", "<-", "->"}
COMMENT_LEAD = {"#", "##", "###", "##!", "//", "--", "*", "-", "|"}

for path in targets:
    rel = os.path.relpath(path, repo)
    try:
        text = open(path, encoding="utf-8").read()
    except (UnicodeDecodeError, OSError):
        continue
    for tail in PROSE.findall(text):
        for raw in tail.split():
            tok = raw.strip('`*"\'')
            if tok in COMMENT_LEAD:
                continue
            if tok in CONNECTOR:
                continue
            if tok.startswith("("):
                break
            trimmed = tok.rstrip(').,;:')
            closes = trimmed != tok   # punctuation after an id ends the list
            tok = trimmed
            if not IDLIKE.match(tok):
                break
            if tok not in by_id:
                failures.append(
                    "{}: names htpx pair '{}', which is not an entry in the pinned corpus. "
                    "Either it was renamed upstream, or this rule promises a pair that has "
                    "never existed — say so in the validation note rather than naming a "
                    "phantom.".format(rel, tok))
            else:
                named.add(by_id[tok][:2])
                if by_id[tok][0] == "blue":
                    named_blue.add(by_id[tok][1])
            if closes:
                break

# ── 3. table claims ───────────────────────────────────────────────────────────
# detections/README.md's per-rule tables end in a "Validate with (…· htpx pair)" column.
# Only the last `·` segment is a claim; everything before it names the Offense fold. A
# segment that is not id-shaped is prose and is skipped — the alternative, demanding that
# every cell name an entry, would fight rows whose validation genuinely is a hand-run
# command. NOT counted as a claim by gen-htpx-coverage.sh: these rows restate the claim
# their own rule already makes, so counting both would double-report one relationship.
readme = os.path.join(repo, "detections", "README.md")
if os.path.isfile(readme):
    col = None
    for lineno, line in enumerate(open(readme, encoding="utf-8"), 1):
        if not line.lstrip().startswith("|"):
            col = None
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        header = [i for i, c in enumerate(cells) if "Validate with" in c]
        if header:
            col = header[0]
            continue
        if col is None or len(cells) <= col:
            continue
        if set(line.strip()) <= set("|- :"):        # the header underline
            continue
        tok = cells[col].split("·")[-1].strip().strip('`*')
        if not IDLIKE.match(tok):
            continue
        if tok not in by_id:
            failures.append(
                "detections/README.md:{}: the Validate-with column names htpx pair '{}', "
                "which is not an entry in the pinned corpus. If the rule has no htpx "
                "counterpart, say so in prose — a phantom id reads as a working "
                "cross-reference.".format(lineno, tok))
        else:
            named.add(by_id[tok][:2])
            if by_id[tok][0] == "blue":
                named_blue.add(by_id[tok][1])

# ── --list-claims: print and stop ─────────────────────────────────────────────
# Before the back-reference pass, which asserts rather than collects.
if listing:
    for colour, stem in sorted(named):
        print("{}\t{}".format(colour, stem))
    sys.exit(0)

# ── 4. back-references ────────────────────────────────────────────────────────
for stem in sorted(named_blue):
    blue = entries["blue"][stem]
    mate = blue["pair"]
    if mate in (None, "", "null"):
        failures.append(
            "htpx entries/blue/{}.md is named by this repo but carries pair: {} — this repo "
            "is relying on a detection the corpus does not consider paired.".format(
                stem, mate or "(absent)"))
        continue
    if mate not in by_id or by_id[mate][0] != "red":
        failures.append(
            "htpx entries/blue/{}.md pairs to '{}', which is not a red entry in the pinned "
            "corpus — the pair this repo cites is broken upstream.".format(stem, mate))
        continue
    back = by_id[mate][2]["pair"]
    if back != blue["id"]:
        failures.append(
            "htpx pair is one-directional: blue '{}' -> red '{}', but that red entry points "
            "back at '{}'. This repo cites the blue half, so the break matters here."
            .format(blue["id"], mate, back))

# ── report ────────────────────────────────────────────────────────────────────
if failures:
    print("::error::check-htpx-pairing: this repo names htpx entries that the pinned "
          "corpus does not have\n", file=sys.stderr)
    for f in failures:
        print("  - " + f, file=sys.stderr)
    print("\n  corpus: %s" % corpus, file=sys.stderr)
    print("  pin:    detections/htpx.pin\n", file=sys.stderr)
    sys.exit(1)

n_urls = sum(len(URL.findall(open(p, encoding="utf-8", errors="ignore").read()))
             for p in targets)
print("check-htpx-pairing: every htpx claim resolves "
      "({} reference URL(s), {} blue entr(ies) named, back-refs intact)"
      .format(n_urls, len(named_blue)))
PY
