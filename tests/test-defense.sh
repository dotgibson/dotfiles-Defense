#!/usr/bin/env bash
# tests/test-defense.sh — functional tests for the two files this repo actually ships:
# defense/defense.zsh (the band-85 role layer) and bootstrap.sh (the installer).
#
# WHY THIS EXISTS. The shared lint gate gives shellcheck + `bash -n` + `zsh -n`, which is
# syntax only. Nothing asserted that mkcase builds the case tree, that note refuses an
# empty entry, that case data lands OUTSIDE the repo, or that the host-tool probe tells
# "installed but off $PATH" apart from "missing". Those are behaviours, and behaviours
# regress silently. dotfiles-core carries scripts/test-core.sh for exactly this reason;
# this is the Defense equivalent.
#
# The cardinal rule of this repo — case/evidence data NEVER lives in the repo — is a
# CORRECTNESS property of mkcase, so it gets an explicit test (case_root_is_outside_repo)
# rather than relying on .gitignore as a backstop.
#
# Design notes:
#   • Runs under bash but drives defense.zsh through `zsh -c`, because that file is zsh
#     (it uses ${(%):-%x}, brace expansion in mkdir, and zsh parameter flags).
#   • Every test gets a throwaway CASES_DIR and HOME under one temp root, removed on exit.
#   • EDITOR=true — mkcase opens $EDITOR on the new case.md as its last act, which would
#     otherwise hang CI forever.
#   • No network, no docker, no sudo. Safe to run on a dev box: nothing outside the temp
#     root is written, and bootstrap.sh is only ever invoked with --dry-run.
# shellcheck disable=SC2016
# SC2016 ("expressions don't expand in single quotes") is the POINT throughout this file:
# the single-quoted strings are zsh source passed to a child shell, so `$CASE`,
# `$+functions[...]` and friends must survive bash untouched and be expanded by zsh. Every
# value this suite wants interpolated in bash is passed as a separate argument instead.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0

ok() {
  printf '  \033[32m✓\033[0m %s\n' "$1"
  PASS=$((PASS + 1))
}
no() {
  printf '  \033[31m✗\033[0m %s\n' "$1" >&2
  [ $# -gt 1 ] && printf '      %s\n' "$2" >&2
  FAIL=$((FAIL + 1))
}
group() { printf '\n\033[36m%s\033[0m\n' "$1"; }

# is <description> <expected> <actual>
is() {
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "expected [$2], got [$3]"; fi
}
# contains <description> <haystack> <needle>
contains() {
  case "$2" in
  *"$3"*) ok "$1" ;;
  *) no "$1" "expected to find [$3]" ;;
  esac
}
# isnt_empty <description> <value>
isnt_empty() {
  if [ -n "$2" ]; then ok "$1"; else no "$1" "value was empty"; fi
}

# zdef <sandbox> <shell-code> — run code with defense.zsh sourced against a scratch
# CASES_DIR. Each call is an independent zsh, so no test can leak $CASE or $PWD forward.
#
# `zsh -f -i` matters and is not incidental:
#   -i  defense.zsh opens with `[[ $- == *i* ]] || return 0` (interactive shells only,
#       mirroring Core's 00-tools.zsh). A plain `zsh -c` returns before defining a single
#       function, and every assertion below would vacuously "pass nothing".
#   -f  skip the user's rc files, so the suite tests THIS repo's file rather than whatever
#       the developer happens to have wired into their own shell.
zdef() {
  local sandbox="$1"
  shift
  CASES_DIR="$sandbox" DEFENSE_DIR="$REPO" EDITOR=true HOME="$sandbox/home" \
    zsh -f -i -c "source '$REPO/defense/defense.zsh' >/dev/null 2>&1; $*" 2>&1
}

sandbox() { # fresh CASES_DIR, echoed
  local d
  d="$(mktemp -d "$TMPROOT/case.XXXXXX")"
  mkdir -p "$d/home"
  printf '%s\n' "$d"
}

# ─────────────────────────────────────────────────────────────────────────────
group "defense.zsh — loads"

if ! command -v zsh >/dev/null 2>&1; then
  echo "zsh not installed — cannot test the role layer" >&2
  exit 1
fi

S="$(sandbox)"
out="$(zdef "$S" 'echo LOADED')"
contains "sources cleanly under zsh" "$out" "LOADED"

out="$(zdef "$S" 'for f in mkcase gocase note siemup siemdown siemlogs; do (( $+functions[$f] )) || echo "MISSING:$f"; done; echo DONE')"
is "defines every public verb" "DONE" "$(printf '%s' "$out" | tr -d '\n')"

fakehome="$TMPROOT/defaulthome"
mkdir -p "$fakehome"
out="$(HOME="$fakehome" DEFENSE_DIR="$REPO" zsh -f -i -c \
  "unset CASES_DIR; source '$REPO/defense/defense.zsh' >/dev/null 2>&1; echo \$CASES_DIR" 2>/dev/null)"
is "CASES_DIR defaults to \$HOME/cases" "$fakehome/cases" "$out"

out="$(zdef "$S" 'echo $DEFENSE_STACK')"
is "DEFENSE_STACK defaults to detection-lab" "detection-lab" "$out"

# The helper is deliberately unfunction'd at the end of the file so it does not leak
# into the interactive shell; if that ever stops working it silently shadows Core's.
out="$(zdef "$S" 'echo $+functions[_have]')"
is "_have does not leak into the shell" "0" "$out"

# ─────────────────────────────────────────────────────────────────────────────
group "mkcase — scaffolding"

S="$(sandbox)"
zdef "$S" 'mkcase test-incident' >/dev/null
root="$(find "$S" -mindepth 1 -maxdepth 1 -type d -not -name home)"
isnt_empty "creates a case directory" "$root"

for sub in evidence network timeline iocs report notes; do
  if [ -d "$root/$sub" ]; then ok "creates $sub/"; else no "creates $sub/"; fi
done

[ -f "$root/case.md" ] && ok "writes case.md" || no "writes case.md"
[ -f "$root/hunt.md" ] && ok "copies hunt.md template" || no "copies hunt.md template"
[ -f "$root/notes/notes.md" ] && ok "seeds notes/notes.md" || no "seeds notes/notes.md"

contains "case.md gets the case name substituted in" "$(cat "$root/case.md")" "$(basename "$root")"
if grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' "$root/case.md"; then
  ok "case.md gets a real creation timestamp"
else
  no "case.md gets a real creation timestamp" "no ISO-8601 stamp in case.md"
fi

# Checks BOTH placeholder conventions on purpose. The original template shipped
# `**CASE**` / `**CREATED**` while mkcase substituted `__CASE__` / `__CREATED__`, so the
# sed never matched and every case.md kept a literal placeholder where the case name and
# creation time belong — on the file the workflow tells you to fill in BEFORE touching
# evidence. Grepping for only one convention is exactly how that survived from the initial
# scaffold, so this asserts neither form survives.
if grep -qE '__CASE__|__CREATED__|\*\*CASE\*\*|\*\*CREATED\*\*' "$root/case.md"; then
  no "no template placeholder survives, in either convention" \
    "found: $(grep -oE '__CASE__|__CREATED__|\*\*CASE\*\*|\*\*CREATED\*\*' "$root/case.md" | tr '\n' ' ')"
else
  ok "no template placeholder survives, in either convention"
fi

# Hyphens are preserved by the slug (only spaces become underscores); asserting the exact
# name keeps that contract pinned.
is "case name is date-prefixed and slugged" "$(date +%Y%m%d)-test-incident" "$(basename "$root")"

# ─────────────────────────────────────────────────────────────────────────────
group "mkcase — slugging, exit codes, idempotency"

S="$(sandbox)"
zdef "$S" "mkcase 'Operation LOUD Noise!!'" >/dev/null
root="$(find "$S" -mindepth 1 -maxdepth 1 -type d -not -name home)"
is "lowercases, underscores spaces, strips punctuation" \
  "$(date +%Y%m%d)-operation_loud_noise" "$(basename "$root")"

S="$(sandbox)"
out="$(zdef "$S" 'mkcase; echo "rc=$?"')"
contains "no argument prints usage" "$out" "Usage: mkcase"
contains "no argument exits non-zero" "$out" "rc=1"

S="$(sandbox)"
zdef "$S" 'mkcase dup' >/dev/null
echo "sentinel content" >"$(find "$S" -mindepth 1 -maxdepth 1 -type d -not -name home)/case.md"
out="$(zdef "$S" 'mkcase dup; echo "rc=$?"')"
contains "re-running on an existing case is a no-op, not a clobber" "$out" "Case already exists"
contains "re-running still succeeds" "$out" "rc=0"
is "existing case.md is preserved" "sentinel content" \
  "$(cat "$(find "$S" -mindepth 1 -maxdepth 1 -type d -not -name home)/case.md")"

S="$(sandbox)"
out="$(zdef "$S" 'mkcase exported >/dev/null; echo "$CASE"')"
contains "exports \$CASE" "$out" "$(date +%Y%m%d)-exported"

# THE CARDINAL RULE: case data never lands inside the repository.
S="$(sandbox)"
out="$(zdef "$S" 'mkcase outside >/dev/null; echo "$CASE"')"
case "$out" in
"$REPO"/*) no "case root is outside the repo" "case landed INSIDE the repo: $out" ;;
*) ok "case root is outside the repo" ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
group "note — audit trail"

S="$(sandbox)"
out="$(zdef "$S" 'mkcase noted >/dev/null; note "first entry"; cat "$CASE/notes/notes.md"')"
contains "appends the note text" "$out" "first entry"
if printf '%s' "$out" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}'; then
  ok "prefixes an ISO-8601 timestamp"
else
  no "prefixes an ISO-8601 timestamp" "got: $out"
fi

out="$(zdef "$S" 'mkcase appended >/dev/null; note one; note two; wc -l < "$CASE/notes/notes.md"')"
is "appends rather than truncates" "2" "$(printf '%s' "$out" | tr -d ' \n')"

out="$(zdef "$S" 'note; echo "rc=$?"')"
contains "empty note is rejected" "$out" "Usage: note"
contains "empty note exits non-zero" "$out" "rc=1"

out="$(zdef "$S" 'note "   "; echo "rc=$?"')"
contains "whitespace-only note is rejected" "$out" "rc=1"

# ─────────────────────────────────────────────────────────────────────────────
group "gocase — guards"

S="$(sandbox)"
out="$(CASES_DIR="$S/nonexistent" DEFENSE_DIR="$REPO" EDITOR=true \
  zsh -f -i -c "source '$REPO/defense/defense.zsh' >/dev/null 2>&1; gocase; echo rc=\$?" 2>&1)"
contains "missing CASES_DIR is reported, not crashed" "$out" "run mkcase"
contains "missing CASES_DIR exits non-zero" "$out" "rc=1"

# ─────────────────────────────────────────────────────────────────────────────
group "siemup/siemdown — guards"

S="$(sandbox)"
out="$(zdef "$S" 'DEFENSE_STACK=no-such-stack; HAVE_DOCKER=1; siemup; echo "rc=$?"')"
contains "a missing compose file is reported" "$out" "no compose file"
contains "a missing compose file exits non-zero" "$out" "rc=1"

out="$(zdef "$S" 'unset HAVE_DOCKER; siemup; echo "rc=$?"')"
contains "siemup without docker is reported" "$out" "docker not installed"
contains "siemup without docker exits non-zero" "$out" "rc=1"

out="$(zdef "$S" 'unset HAVE_DOCKER; siemdown; echo "rc=$?"')"
contains "siemdown without docker exits non-zero" "$out" "rc=1"

# ─────────────────────────────────────────────────────────────────────────────
group "bootstrap.sh — host-tool probe classification"

# Drive check_tools in isolation with stubbed blib_* and a synthetic PATH, so the three
# states are asserted without installing or removing anything on the host.
harness() { # harness <extra-shell-setup>
  local h="$TMPROOT/probe.sh"
  {
    echo '#!/usr/bin/env bash'
    echo 'blib_say(){ echo ":: $*"; }; blib_ok(){ echo "+ $*"; }; blib_warn(){ echo "! $*"; }'
    sed -n '/^_probe_offpath()/,/^}/p' "$REPO/bootstrap.sh"
    sed -n '/^_probe_altname()/,/^}/p' "$REPO/bootstrap.sh"
    sed -n '/^check_tools()/,/^}/p' "$REPO/bootstrap.sh"
    echo "$1"
    echo 'check_tools'
  } >"$h"
  bash "$h" 2>&1
}

# HERMETIC BY CONSTRUCTION. The probe searches real locations (/opt/<t>/bin, /snap/bin,
# ~/.local/share/<t>), so a suite that only narrowed $PATH would still find the host's own
# tools — this very box has a real /opt/zeek, which made an early draft of the "missing"
# assertion pass or fail depending on who ran it. So every case below narrows $PATH AND
# stubs _probe_offpath, leaving the planted fixtures as the only things discoverable.
PROBED="zsh docker jq tshark zeek suricata chainsaw hayabusa sigma yara velociraptor vol log2timeline.py"
NOWHERE='_probe_offpath(){ return 1; }'

plant() { # plant <dir> <name>...
  local d="$1"
  shift
  mkdir -p "$d"
  local t
  for t in "$@"; do
    printf '#!/bin/sh\nexit 0\n' >"$d/$t"
    chmod +x "$d/$t"
  done
}

# Case 1 — some on PATH, nothing anywhere else.
STUB="$TMPROOT/stub"
# shellcheck disable=SC2086  # deliberate word split: PROBED is a space-separated list
plant "$STUB" zsh docker jq tshark suricata sigma yara log2timeline.py
out="$(harness "PATH=$STUB; $NOWHERE")"
contains "a tool on PATH reports found" "$out" "+ found: jq"
contains "a tool absent everywhere reports missing" "$out" "! missing: zeek"
contains "the missing count is summarised" "$out" "tool(s) missing"

# Case 2 — zeek planted at a tool-owned prefix, off PATH. The /opt/zeek/bin case that
# motivated the three-state probe in the first place.
FAKEOPT="$TMPROOT/opt/zeek/bin"
plant "$FAKEOPT" zeek
out="$(harness "PATH=$STUB; _probe_offpath(){ [ \"\$1\" = zeek ] && { echo '$FAKEOPT/zeek'; return 0; }; return 1; }")"
contains "an off-PATH tool reports unreachable, not missing" "$out" "! unreachable: zeek"
contains "unreachable names the path it found" "$out" "$FAKEOPT/zeek"
contains "unreachable prints the fixing symlink" "$out" "ln -s"
contains "the unreachable count is summarised separately" "$out" "off \$PATH"
if printf '%s' "$out" | grep -q "missing: zeek"; then
  no "an off-PATH tool is not also counted missing" "zeek reported BOTH unreachable and missing"
else
  ok "an off-PATH tool is not also counted missing"
fi

# Case 3 — alternate name: vol shipped as vol.py, the volatility3 packaging case.
ALT="$TMPROOT/alt"
# shellcheck disable=SC2086
plant "$ALT" $PROBED
rm -f "$ALT/vol"
plant "$ALT" vol.py
out="$(harness "PATH=$ALT; $NOWHERE")"
contains "an alternate name reports found, naming the alias" "$out" "found: vol (as \`vol.py\`)"
if printf '%s' "$out" | grep -q "missing: vol$"; then
  no "an alternate name is not also counted missing" "vol reported found AND missing"
else
  ok "an alternate name is not also counted missing"
fi

# Case 4 — everything on PATH under its own name → the all-clear, nothing counted.
ALL="$TMPROOT/all"
# shellcheck disable=SC2086
plant "$ALL" $PROBED
out="$(harness "PATH=$ALL; $NOWHERE")"
contains "all-clear line appears when nothing is missing or unreachable" "$out" "all probed tools present"
if printf '%s' "$out" | grep -qE "missing:|unreachable:"; then
  no "all-clear run reports no warnings" "got: $(printf '%s' "$out" | grep -E 'missing:|unreachable:' | head -2)"
else
  ok "all-clear run reports no warnings"
fi

# ─────────────────────────────────────────────────────────────────────────────
group "bootstrap.sh — dry run is inert"

DRYHOME="$TMPROOT/dryhome"
mkdir -p "$DRYHOME"
dry_out="$(HOME="$DRYHOME" "$REPO/bootstrap.sh" --dry-run --no-check 2>&1)"
is "dry run exits 0" "0" "$?"
contains "dry run plans the Core surface" "$dry_out" "would link"
contains "dry run plans the band-85 role stage" "$dry_out" "85-defense.zsh"

# The whole point of --dry-run: it must not write. A single file here is a real bug.
written="$(find "$DRYHOME" -mindepth 1 2>/dev/null | head -5)"
if [ -z "$written" ]; then
  ok "dry run writes nothing into HOME"
else
  no "dry run writes nothing into HOME" "created: $(printf '%s' "$written" | tr '\n' ' ')"
fi

# ─────────────────────────────────────────────────────────────────────────────
group "bootstrap.sh — argument handling"

out="$("$REPO/bootstrap.sh" --help 2>&1)"
rc=$?
is "--help exits 0" "0" "$rc"
contains "--help describes the script" "$out" "role layer"

out="$("$REPO/bootstrap.sh" --nonsense 2>&1)"
rc=$?
is "an unknown argument exits non-zero" "1" "$rc"
contains "an unknown argument is named" "$out" "unknown arg"

# ─────────────────────────────────────────────────────────────────────────────
printf '\n\033[36msummary\033[0m\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
