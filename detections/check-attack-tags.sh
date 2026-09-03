#!/usr/bin/env bash
# detections/check-attack-tags.sh — validate every ATT&CK tag against a PINNED ATT&CK
# release, not against whatever MITRE published this morning.
# ──────────────────────────────────────────────────────────────────────────────
# WHY. This check used to be advisory, and for good reason: pySigma >= 1.5.0 resolves tags
# against a STIX bundle it downloads at check time from the HEAD of the attack-stix-data
# repo, dropping revoked and deprecated objects. That made its verdict a function of the
# outside world — the same commit reported 0 issues one run and 52 the next, with nothing
# in the repo changed (#172) — and continue-on-error then hid the flip entirely. It was the
# only check in sigma.yml that could change its answer on its own, and the only one whose
# failures were invisible by design.
#
# Pinning the bundle removes both halves of that. detections/attack-data.pin names an
# immutable per-version file and its SHA-256; this verifies the digest on every run and
# injects the file via pySigma's own set_url(), which exists for exactly this purpose. The
# result is reproducible, so the check earns the right to be a hard gate: an ATT&CK release
# now fails the build at bump time, in a PR someone reads, instead of silently.
#
# It downloads on a cache miss, which is a network dependency — the same trade the shell
# lint gate already makes for its SHA-256-verified pinned tools. A digest mismatch is a
# hard failure, never a warning: it means the pin and the file disagree, and continuing
# would validate against an unknown vocabulary.
#
# TWO representations are checked, because gating one moves the risk to the other rather
# than removing it. #171 retagged the corpus for v19 and #179 then found 27 revoked ids
# still sitting in prose and in references: URLs — untouched, because this gate read tags:
# and nothing else. The references were the sharp end: attack.mitre.org serves a revoked
# technique page with a banner rather than a 404 (T1562/001/ still returns HTTP 200), so a
# stale link does not announce itself, it quietly shows the wrong technique to whoever is
# working the alert.
#
#   1. TAGS    — pySigma's own validator over detections/sigma/, against the pinned bundle.
#   2. CITED   — every ATT&CK id written anywhere else under detections/ or in
#                DEFENSE-METHODOLOGY.md: prose ids, and the technique/tactic pages that
#                references: entries link to.
#   3. PAIRING — every attack.<tactic> tag on a rule is one that ATT&CK actually places at
#                least one of that rule's attack.tNNNN techniques in.
#
# PAIRING exists because 1 and 2 both pass on a tag that is real but MISFILED, and that is
# not a hypothetical: #209 found npm_malicious_package_publish and pypi_token_release_upload
# tagging attack.execution beside attack.t1195.002. T1195.002 is Initial-Access-only, so
# COVERAGE.md's TA0001 column read zero while Execution over-counted — a whole tactic
# missing from the roll-up, with every existing gate green. Validating that an id EXISTS
# says nothing about whether it belongs where it was written.
#
# Direction matters: this asserts that each TACTIC tag is earned, NOT that every tactic of
# every technique is tagged. The reverse would fight unconstrained_delegation_4624.yml,
# which deliberately tags a subset of three techniques' tactics and says why inline.
#
# TWO escapes, both same-line so they name what they excuse:
#   - `attack-id-historical`       a deliberate mention of a revoked id (assertions 1-2)
#   - `attack-tactic-deliberate`   a tactic tag that is real tradecraft but not an ATT&CK
#                                  placement — PsExec service creation IS lateral movement
#                                  though ATT&CK files T1569.002 under Execution alone.
#                                  Put it on the tag's own line, with the reason in a
#                                  comment above. If these ever outgrow inline comments, an
#                                  allowlist beside splunk-precedence-allowlist.tsv is the
#                                  upgrade.
#
#   check-attack-tags.sh              # gate the corpus
#   ATTACK_DATA_DIR=... check-...     # override where the bundle is cached
#
# Exit: 0 = every id valid;  1 = invalid ids, bad digest, or the bundle is unavailable;
#       2 = bad invocation
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

if [[ $# -gt 0 ]]; then
  echo "check-attack-tags: unexpected argument '$1'" >&2
  echo "usage: check-attack-tags.sh" >&2
  exit 2
fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
PIN="$HERE/attack-data.pin"
PYTHON="${PYTHON:-python3}"

[[ -r "$PIN" ]] || {
  echo "::error::missing: $PIN"
  exit 1
}

pin_field() { awk -F'\t' -v k="$1" '!/^[[:space:]]*#/ && $1==k {print $2; exit}' "$PIN"; }
VERSION="$(pin_field version)"
URL="$(pin_field url)"
WANT_SHA="$(pin_field sha256)"

# Name the PIN FIELD in the error, not the shell variable holding it — the reader has to
# go edit the file, and "missing the 'want_sha' field" sends them looking for a key that
# does not exist.
missing=()
[[ -n "$VERSION" ]] || missing+=("version")
[[ -n "$URL" ]] || missing+=("url")
[[ -n "$WANT_SHA" ]] || missing+=("sha256")
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "::error::$PIN is missing required field(s): ${missing[*]}"
  echo "  expected tab-separated rows: version / url / sha256"
  exit 1
fi

CACHE_DIR="${ATTACK_DATA_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles-Defense/attack}"
BUNDLE="$CACHE_DIR/enterprise-attack-$VERSION.json"
mkdir -p "$CACHE_DIR" || exit 1

digest_ok() {
  [[ -f "$BUNDLE" ]] || return 1
  local got
  got="$(
    "$PYTHON" - "$BUNDLE" <<'PY'
import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], "rb") as fh:
    for chunk in iter(lambda: fh.read(1 << 20), b""):
        h.update(chunk)
print(h.hexdigest())
PY
  )"
  [[ "$got" == "$WANT_SHA" ]]
}

if ! digest_ok; then
  if [[ -f "$BUNDLE" ]]; then
    echo "attack tags: cached bundle failed its digest — refetching"
    rm -f "$BUNDLE"
  fi
  echo "attack tags: fetching ATT&CK v$VERSION (~51 MiB, cached at $CACHE_DIR)"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$BUNDLE" "$URL"; then
    echo "::error::could not download the pinned ATT&CK bundle from $URL"
    echo "  This gate needs it. Pre-seed the cache to run offline:"
    echo "    ATTACK_DATA_DIR=<dir> with enterprise-attack-$VERSION.json already present"
    rm -f "$BUNDLE"
    exit 1
  fi
  if ! digest_ok; then
    echo "::error::SHA-256 mismatch for the pinned ATT&CK bundle."
    echo "  expected $WANT_SHA"
    echo "  The pin and the published file disagree — do NOT edit the digest to match."
    echo "  MITRE's per-version files are immutable, so this means the URL moved or the"
    echo "  download is corrupt. Investigate before trusting any tag verdict."
    rm -f "$BUNDLE"
    exit 1
  fi
fi

# Inject the pinned bundle through pySigma's own set_url(), then run the real CLI check in
# the same process so the injection is in effect. set_cache_dir first: set_url clears the
# cache it is pointed at, and clobbering the user's shared ~/.cache/pysigma as a side
# effect of running a gate would be rude.
"$PYTHON" - "$BUNDLE" "$REPO/detections/sigma/" "$VERSION" "$REPO" <<'PY'
import os, sys, tempfile

bundle, rules, want_version, repo = sys.argv[1:5]

from sigma.data import mitre_attack

mitre_attack.set_cache_dir(tempfile.mkdtemp(prefix="attack-pin-"))
mitre_attack.set_url(bundle)

got = str(mitre_attack.mitre_attack_version)
if got != want_version:
    print("::error::pinned bundle reports ATT&CK v%s but attack-data.pin says v%s"
          % (got, want_version))
    sys.exit(1)
print("attack tags: validating against pinned ATT&CK v%s (%d tactics, %d techniques)"
      % (got, len(mitre_attack.mitre_attack_tactics),
         len(mitre_attack.mitre_attack_techniques)))

from sigma.cli.main import main

# Run with the repo's OWN validation config, minus the `-attacktag` line it carries.
# That line exists so the hermetic lint in sigma.yml never touches the network; here the
# pinned bundle is already injected above, so attacktag can and must run.
#
# Reusing the file rather than passing no config at all is the point: `sigma check` with
# no `-c` enables every validator and honours NO exclusions, so this gate silently
# disagreed with the hermetic one about which rules are exempt from what. A per-rule
# exclusion added in sigma-validation-config.yml passed there and failed here, which reads
# as an ATT&CK-tag failure and is nothing of the sort (dotgibson/dotfiles-Defense#268).
cfg_src = os.path.join(repo, "detections", "sigma-validation-config.yml")
with open(cfg_src, encoding="utf-8") as fh:
    cfg = [ln for ln in fh if ln.strip() != "- -attacktag"]
cfg_path = os.path.join(tempfile.mkdtemp(prefix="attack-cfg-"), "validation.yml")
with open(cfg_path, "w", encoding="utf-8") as fh:
    fh.writelines(cfg)

sys.argv = ["sigma", "check", "--fail-on-issues", "-c", cfg_path, rules]
try:
    main()
    code = 0
except SystemExit as exc:
    code = exc.code or 0
if code:
    print("::error::invalid ATT&CK tag(s) against pinned v%s — see the issues above." % got)
    print("  A tag can go invalid without the repo changing: ATT&CK revokes ids between")
    print("  releases. If this appeared after bumping attack-data.pin, retag the rules;")
    print("  the old ids are gone, not merely unfashionable.")

# ── 2. ids CITED outside tags: prose, and the pages references: link to ────────────────
import os, re

TECH = set(mitre_attack.mitre_attack_techniques)
TACS = {t.upper() for t in mitre_attack.mitre_attack_tactics}
TAC_IDS = set(mitre_attack.mitre_attack_tactics)

ID_RE  = re.compile(r"\bT\d{4}(?:\.\d{3})?\b")
TA_RE  = re.compile(r"\bTA\d{4}\b")
URL_RE = re.compile(r"https?://attack\.mitre\.org/(techniques|tactics)/(T[\dA-Z.]+|TA\d+)"
                    r"(?:/(\d{3}))?/?")

SCAN_DIRS = [os.path.join(repo, "detections")]
SCAN_FILES = [os.path.join(repo, "DEFENSE-METHODOLOGY.md")]
EXT = (".yml", ".yaml", ".md", ".conf", ".kql", ".lucene", ".zeek", ".rules")

def files():
    for f in SCAN_FILES:
        if os.path.isfile(f):
            yield f
    for root in SCAN_DIRS:
        for dirpath, _dirs, names in os.walk(root):
            for n in sorted(names):
                if n.endswith(EXT):
                    yield os.path.join(dirpath, n)

bad = []
for f in sorted(set(files())):
    try:
        text = open(f, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        continue
    rel = os.path.relpath(f, repo)
    for lineno, line in enumerate(text.split("\n"), 1):
        if "attack-id-historical" in line:
            continue
        seen = set()
        # references: URLs — a sub-technique is .../T1685/002/, so rejoin the parts
        for kind, head, sub in URL_RE.findall(line):
            seen.add((head + "." + sub if sub else head, "reference URL"))
        for m in ID_RE.findall(line):
            seen.add((m, "cited id"))
        for m in TA_RE.findall(line):
            seen.add((m, "cited tactic"))
        for ident, how in sorted(seen):
            ok = ident in TAC_IDS if ident.startswith("TA") else ident in TECH
            if not ok:
                bad.append((rel, lineno, ident, how))

if bad:
    print("::error::%d ATT&CK id(s) cited outside tags: are not in pinned v%s:"
          % (len(bad), got))
    for rel, lineno, ident, how in bad:
        print("  %s:%s  %s  (%s)" % (rel, lineno, ident, how))
    print("  These are revoked, deprecated, or misspelled. Tags are checked separately and")
    print("  may already be correct — that is exactly how #179 happened: the retag fixed")
    print("  tags: and left prose and references: pointing at revoked techniques, which")
    print("  attack.mitre.org still serves with a banner instead of a 404.")
    print("  For a DELIBERATE historical mention, put `attack-id-historical` on that line.")
    code = code or 1
else:
    print("attack ids: %d file(s) scanned, every cited id and reference URL current"
          % len(sorted(set(files()))))

# ── 3. tactic <-> technique PAIRING ───────────────────────────────────────────────────
# Read kill_chain_phases straight out of the pinned bundle rather than through pySigma:
# the digest is already verified above, the mapping is plain STIX, and it keeps this
# assertion independent of which lookup tables a pySigma version happens to expose.
import glob, json

phases_of = {}
with open(bundle, encoding="utf-8") as fh:
    for obj in json.load(fh)["objects"]:
        if obj.get("type") != "attack-pattern":
            continue
        if obj.get("revoked") or obj.get("x_mitre_deprecated"):
            continue
        tid = next((r.get("external_id") for r in obj.get("external_references", [])
                    if r.get("source_name") == "mitre-attack"), None)
        if tid:
            phases_of[tid] = {k["phase_name"] for k in obj.get("kill_chain_phases", [])
                              if k.get("kill_chain_name") == "mitre-attack"}

ALL_TACTICS = set().union(*phases_of.values()) if phases_of else set()
TAG_RE = re.compile(r"-\s+attack\.(\S+)")
TECH_TAG_RE = re.compile(r"t\d{4}(?:\.\d{3})?\Z")

def tags_block(text):
    """Yield (tag, line_no, line) for each attack.* entry in the rule's tags: block."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if line.rstrip() != "tags:":
            continue
        for j in range(i + 1, len(lines)):
            nxt = lines[j]
            if not nxt.strip():
                continue
            if not nxt[:1].isspace():          # dedent ends the block
                return
            m = TAG_RE.search(nxt)
            if m:
                yield m.group(1), j + 1, nxt
        return

mispaired = []
for path in sorted(glob.glob(os.path.join(repo, "detections", "sigma", "*", "*.yml"))):
    text = open(path, encoding="utf-8").read()
    entries = list(tags_block(text))
    techs = ["T" + tag[1:].upper() for tag, _, _ in entries if TECH_TAG_RE.fullmatch(tag)]
    earned = set().union(*(phases_of.get(t, set()) for t in techs)) if techs else set()
    for tag, lineno, line in entries:
        if tag not in ALL_TACTICS:             # technique tags and typos: not our job
            continue
        if tag in earned or "attack-tactic-deliberate" in line:
            continue
        mispaired.append((os.path.relpath(path, repo), lineno, tag, techs, sorted(earned)))

if mispaired:
    print("::error::%d tactic tag(s) that ATT&CK v%s does not place the rule's technique(s) in:"
          % (len(mispaired), got))
    for rel, lineno, tag, techs, earned in mispaired:
        print("  %s:%s  attack.%s" % (rel, lineno, tag))
        print("      techniques tagged here: %s" % (", ".join(techs) or "(none)"))
        print("      ATT&CK puts those in:   %s" % (", ".join(earned) or "(nothing)"))
    print("  Either the tactic tag is wrong, or the rule is missing the technique that")
    print("  would earn it. If the tag is deliberate tradecraft ATT&CK does not model —")
    print("  PsExec service creation IS lateral movement though T1569.002 is filed under")
    print("  Execution alone — put `attack-tactic-deliberate` on that tag's line and the")
    print("  reason in a comment above it.")
    code = code or 1
else:
    print("attack pairing: %d rule(s), every tactic tag earned by a technique tagged beside it"
          % len(glob.glob(os.path.join(repo, "detections", "sigma", "*", "*.yml"))))

sys.exit(code)
PY
