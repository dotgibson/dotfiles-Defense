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
#   check-attack-tags.sh              # gate the corpus
#   ATTACK_DATA_DIR=... check-...     # override where the bundle is cached
#
# Exit: 0 = every tag valid;  1 = invalid tags, bad digest, or the bundle is unavailable;
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
"$PYTHON" - "$BUNDLE" "$REPO/detections/sigma/" "$VERSION" <<'PY'
import sys, tempfile

bundle, rules, want_version = sys.argv[1], sys.argv[2], sys.argv[3]

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

sys.argv = ["sigma", "check", "--fail-on-issues", rules]
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
sys.exit(code)
PY
