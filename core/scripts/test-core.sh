#!/usr/bin/env bash
# scripts/test-core.sh
# ──────────────────────────────────────────────────────────────────────────────
# BEHAVIORAL tests for Core — the layer scripts/audit-core.sh's static analysis can't
# reach. audit-core.sh proves the modules PARSE (zsh -n) and that the manifest and
# exec-bits are consistent; this proves the modules actually LOAD TOGETHER in the
# canonical order and that the pure shell functions DO what they claim. A defect
# here passes every per-file `zsh -n` cleanly and still fans out to nine OS repos —
# which is exactly the gap this file closes.
#
# Two sections, both zsh-gated and degrading gracefully (mirrors audit-core.sh):
#   A. load-order smoke test  — source every zsh module in the README's canonical
#                               order inside ONE hermetic interactive zsh and
#                               assert the whole chain loads (catches cross-module
#                               contract breakage: a module that needs a var/fn an
#                               EARLIER module must define first).
#   B. function unit tests    — exercise the pure functions in functions.zsh
#                               (mkcd / cdup / mkbak / extract) and assert behavior.
#
# Hermetic: a throwaway $HOME/$ZDOTDIR/$XDG_CACHE_HOME is used, and the plugin dirs
# are pre-seeded EMPTY so plugins.zsh's first-run `git clone` is skipped — the test
# needs no network and writes nothing outside its tempdir.
#
# Graceful degradation: with no zsh installed (a bare box), both sections SKIP and
# the script exits 0 — identical philosophy to audit-core.sh, so this is safe to
# call from CI, pre-commit, and a developer's laptop alike.
#
# Usage:
#   ./scripts/test-core.sh            # run every section
#   ./scripts/test-core.sh --quiet    # only print SKIP/FAIL + the summary
# ──────────────────────────────────────────────────────────────────────────────

# This harness embeds zsh code as single-quoted literals on purpose: the `$…`
# inside them must be expanded by the zsh CHILD, not by this bash parent. SC2016
# (un-expanded `$` in single quotes) is therefore a false positive file-wide.
# shellcheck disable=SC2016
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

QUIET=0
JSON=0 # --json: machine-readable summary on stdout (implies quiet); mirrors audit-core.sh
# Scope mirrors audit-core.sh: gate the slow AREA-specific sections so a per-area run
# does less. FAIL-CLOSED default (no --scope → every area runs). The cross-cutting,
# pure-bash sections (clipboard ladder, CI-classifier) ALWAYS run — they are fast and
# guard runtime artifacts shared by every area. audit-core.sh passes the classifier's
# verdict here; a bare `./scripts/test-core.sh` runs everything.
SCOPE_SHELL=1
SCOPE_NVIM=1
SCOPE_ATUIN=1
# Shared palette + pass/skip/fail/hdr/have + _set_scope + _seed_plugin_dirs (one
# definition for every gate script). Sourced HERE — before the arg loop calls _set_scope
# — and after QUIET is set so the lib's `: "${QUIET:=0}"` preserves it.
# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

# Same flag contract as audit-core.sh: parse EVERY arg and reject an unknown option or
# a stray extra operand instead of ignoring it; -h/--help prints usage. (audit-core.sh
# invokes this with --quiet/--scope or nothing.)
while (($#)); do
  case "$1" in
  -q | --quiet) QUIET=1 ;;
  --scope)
    # Require an explicit value (mirrors audit-core.sh): `--scope --quiet` must not
    # eat the next flag as the scope list.
    if (($# < 2)) || [[ "$2" == -* ]]; then
      printf 'test-core.sh: --scope requires a value (shell,nvim,atuin|all|none)\n' >&2
      printf 'try: test-core.sh --help\n' >&2
      exit 2
    fi
    shift
    _set_scope "$1"
    ;;
  --scope=*) _set_scope "${1#*=}" ;;
  --json) JSON=1 QUIET=1 CORE_JSON=1 && export CORE_JSON ;; # only JSON on stdout
  --color)
    if (($# < 2)) || ! _core_set_color "$2"; then
      printf 'test-core.sh: --color requires a value (auto|always|never)\n' >&2
      printf 'try: test-core.sh --help\n' >&2
      exit 2
    fi
    shift
    ;;
  --color=*)
    _core_set_color "${1#*=}" || {
      printf 'test-core.sh: --color requires auto|always|never\n' >&2
      exit 2
    }
    ;;
  -h | --help)
    cat <<'EOF'
usage: test-core.sh [-q|--quiet] [--scope LIST] [--color WHEN] [--json] [-h|--help]

Behavioral suite: clipboard ladder + nvim headless load + nvim event callbacks
+ zsh load-order smoke + function/unit + detection tests. Degrades gracefully
when zsh/nvim are absent.

  -q, --quiet     only print SKIP/FAIL lines and the final summary
  --scope LIST    limit the slow area sections: shell, nvim, atuin, all (default),
                  none. The clipboard + CI-classifier sections always run.
                  `atuin` drives the premise detector's hermetic self-test
                  (scripts/verify-atuin-guard.sh) — the slowest thing here by far.
  --color WHEN    auto (default) | always | never; NO_COLOR still wins. (CORE_COLOR env.)
  --json          machine-readable summary on stdout (implies --quiet):
                  {pass,skip,fail,seconds,skipped[],result}
  -h, --help      show this help and exit
EOF
    exit 0
    ;;
  *)
    printf 'test-core.sh: unexpected argument: %s\n' "$1" >&2
    printf 'try: test-core.sh --help\n' >&2
    exit 2
    ;;
  esac
  shift
done

# ── STOP CORE_JSON AT THIS PROCESS BOUNDARY (#511/#524/#508) ──────────────────
# CORE_JSON=1 means "stdout carries only the JSON object", and common.sh's skip() honours
# it by printing nothing. That is right for THIS script and wrong for every child it runs.
#
# The fixtures below execute real gate scripts — fleet-drift.sh, sync-core.sh, auto-tag.sh,
# tag-release.sh — and assert on their human-readable output, skip() lines included. An
# INHERITED CORE_JSON silences exactly those lines, so an assertion fails for a reason that
# has nothing to do with the code under test: `test-core.sh --scope none --json` reported a
# failing result on a tree the identical non-JSON run passed clean, three separate times
# (#508 tag-release, #524 sync-core, #511 fleet-drift). Each was fixed where it hurt, and
# the next fixture inherited the trap again — because the default was wrong.
#
# `export -n` fixes the DEFAULT rather than the symptom: the value stays readable in this
# shell, so our own skip() is still quiet and the JSON object is still clean, but no child
# inherits it. It handles both routes in: our own --json above, and audit-core.sh --json,
# which puts CORE_JSON in our environment before we start.
#
# The explicit `env -u CORE_JSON` at each fixture invocation is kept as well. It is not
# redundant: it documents the hazard at the call site, and it keeps each fixture correct if
# it is ever lifted out of this file. The two insulation gates (sync-core, fleet-drift)
# export CORE_JSON inside a subshell precisely to prove those pins still work.
export -n CORE_JSON 2>/dev/null || true

# Wall-clock for the standalone summary (mirrors audit-core.sh) — the headless nvim
# leg can take a few seconds, so showing elapsed reads as progress, not a hang.
SECONDS=0

# When invoked from audit-core.sh (CORE_TEST_NESTED=1) the audit owns the summary,
# so we suppress ours and only signal pass/fail via the exit code.
NESTED="${CORE_TEST_NESTED:-0}"
summary() {
  [[ "$NESTED" == 1 ]] && return 0
  if ((JSON)); then
    local _result _first=1 _s
    ((FAIL == 0)) && _result=ok || _result=failed
    printf '{"pass":%d,"skip":%d,"fail":%d,"seconds":%d,"skipped":[' \
      "$PASS" "$SKIP" "$FAIL" "$SECONDS"
    for _s in ${_CORE_SKIPS[@]+"${_CORE_SKIPS[@]}"}; do
      _s="${_s//\\/\\\\}"
      _s="${_s//\"/\\\"}"
      ((_first)) || printf ','
      printf '"%s"' "$_s"
      _first=0
    done
    printf '],"result":"%s"}\n' "$_result"
    return 0
  fi
  printf '\n%s──────── test summary ────────%s\n' "$c_blu" "$c_rst"
  printf '  %spass %d%s   %sskip %d%s   %sfail %d%s   %s(%ds)%s\n' \
    "$c_grn" "$PASS" "$c_rst" "$c_yel" "$SKIP" "$c_rst" "$c_red" "$FAIL" "$c_rst" \
    "$c_blu" "$SECONDS" "$c_rst"
}

# One throwaway sandbox for the whole run; clean it up no matter how we exit. It is
# created BEFORE the zsh gate because Section C (clipboard) is pure bash and must run
# even where zsh is absent — bin/clip's whole reason to exist is bare-box portability.
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/core-test.XXXXXX")"
# ONE handler, because `trap … EXIT` REPLACES rather than appends — a second one installed
# further down this file would silently take the sandbox cleanup with it, leaving a
# core-test.XXXXXX per run under /tmp for nobody to notice. Anything else needing to run at
# exit hangs off this function. The `declare -F` guard is for the early exits above (--help,
# a bad argument): those leave before the later definitions exist, and an EXIT handler that
# calls a not-yet-defined function turns a clean `exit 0` into a command-not-found on stderr.
_core_test_cleanup() {
  rm -rf "$SANDBOX"
  declare -F _d_drop_lock >/dev/null && _d_drop_lock
  return 0
}
trap '_core_test_cleanup' EXIT

# ── C. clipboard detection ladder (bin/clip / bin/clip-paste) ─────────────────
# bin/clip is the single highest-fan-out runtime artifact in Core — used by zsh
# (pbcopy alias), tmux (copy-pipe), AND nvim (clipboard provider), across all nine OS
# repos — yet its WSL→macOS→Wayland→X11→OSC 52 ladder had no test, only `bash -n`. We drive
# the ladder HERMETICALLY: PATH is pointed at a fake bin holding a stub `uname` that
# reports the OS we want, a stub `grep` that answers the /proc/version probe, and
# stub backends that print a marker instead of touching a real clipboard — then we
# assert the RIGHT backend was exec'd. PATH is the fake dir ONLY (a real `bash`
# symlink keeps the `#!/usr/bin/env bash` shebang resolvable), so backend probing is
# fully deterministic regardless of what the host happens to have installed. Pure
# bash — runs with no zsh, exactly where bin/clip most needs to work.
hdr "clipboard detection ladder (bin/clip, bin/clip-paste)"
CLIP="$HERE/bin/clip"
CLIPPASTE="$HERE/bin/clip-paste"
CBIN="$SANDBOX/clipbin"
_real_bash="$(command -v bash)"
_real_tr="$(command -v tr)"

_stub() {
  printf '#!/bin/sh\n%s\n' "$2" >"$CBIN/$1"
  chmod +x "$CBIN/$1"
}
# Fresh fake bin + cleared env before each scenario. `bash` is symlinked so the
# shebang resolves under the stripped PATH; `uname` defaults to "Linux" and Darwin
# cases override it. The WSL probe now reads /proc/version via a bash builtin (no
# grep fork — see bin/clip), so we point CLIP_PROC_VERSION at a NON-WSL fixture; the
# WSL cases either set WSL_DISTRO_NAME or overwrite that fixture with a microsoft one.
_clip_reset() {
  rm -rf "$CBIN"
  mkdir -p "$CBIN"
  unset WSL_DISTRO_NAME WAYLAND_DISPLAY DISPLAY
  ln -s "$_real_bash" "$CBIN/bash"
  _stub uname 'echo Linux'
  printf 'Linux version 6.1.0-0 (gcc) #1 SMP\n' >"$CBIN/procversion"
  export CLIP_PROC_VERSION="$CBIN/procversion"
  # Point the OSC 52 fallback at a path that cannot be opened, so a scenario which
  # reaches it fails LOUDLY instead of quietly writing to the runner's real terminal
  # (or accidentally passing because CI happens to have no tty). The OSC 52 cases
  # below override this with a real file.
  export CLIP_TTY="$CBIN/no-such-dir/tty"
}
# Assert prog's stdout is exactly the marker the chosen backend prints.
_clip_is() { # _clip_is <label> <prog> <expected>
  local out
  out="$(printf 'payload' | PATH="$CBIN" "$2" 2>/dev/null)"
  if [[ "$out" == "$3" ]]; then pass "$1"; else fail "$1 (got '${out}', want '${3}')"; fi
}
# Assert prog exits non-zero — the no-backend-found path.
_clip_fails() { # _clip_fails <label> <prog>
  if printf 'payload' | PATH="$CBIN" "$2" >/dev/null 2>&1; then
    fail "$1 (expected non-zero exit)"
  else pass "$1"; fi
}

# clip (copy) — each scenario leaves ONLY the intended backend reachable.
_clip_reset
export WSL_DISTRO_NAME=Ubuntu
_stub clip.exe 'echo WSL'
_clip_is "clip → clip.exe when WSL_DISTRO_NAME set" "$CLIP" WSL
unset WSL_DISTRO_NAME
_clip_reset
# WSL with NO WSL_DISTRO_NAME — detection must come from /proc/version content.
printf 'Linux version 5.15.0-microsoft-standard-WSL2\n' >"$CBIN/procversion"
_stub clip.exe 'echo WSL'
_clip_is "clip → clip.exe via /proc/version (no WSL_DISTRO_NAME)" "$CLIP" WSL
_clip_reset
_stub uname 'echo Darwin'
_stub pbcopy 'echo MAC'
_clip_is "clip → pbcopy on Darwin" "$CLIP" MAC
_clip_reset
export WAYLAND_DISPLAY=wayland-0
_stub wl-copy 'echo WL'
_clip_is "clip → wl-copy under Wayland" "$CLIP" WL
unset WAYLAND_DISPLAY
_clip_reset
# DISPLAY is required, not incidental: xclip/xsel cannot talk to an X server without
# one, and the guard is what lets a box that merely HAS xclip installed (a common
# desktop dependency) fall through to OSC 52 over ssh instead of exec'ing a doomed
# binary. See the ladder's own comment in bin/clip.
export DISPLAY=:0
_stub xclip 'echo XCLIP'
_clip_is "clip → xclip on X11" "$CLIP" XCLIP
_clip_reset
export DISPLAY=:0
_stub xsel 'echo XSEL'
_clip_is "clip → xsel when xclip absent" "$CLIP" XSEL
_clip_reset
# The regression that motivated the guard: xclip present, no DISPLAY. This MUST NOT
# exec xclip — it must fall past it. The stub writes a marker file so we can prove the
# backend never ran, rather than inferring it from stdout.
_stub xclip "echo RAN >'$CBIN/xclip-ran'"
ln -s "$_real_tr" "$CBIN/tr"
ln -s "$(command -v base64)" "$CBIN/base64"
export CLIP_TTY="$CBIN/tty-x11"
if printf 'payload' | PATH="$CBIN" "$CLIP" 2>/dev/null && [[ ! -e "$CBIN/xclip-ran" ]]; then
  pass "clip: xclip installed but no DISPLAY falls through to OSC 52 (does not exec a doomed xclip)"
else
  fail "clip: xclip was exec'd with no DISPLAY, or the OSC 52 fallback did not run"
fi
_clip_reset
# base64/tr must be present, or `clip` dies during ENCODING and never reaches the tty
# write — leaving this assertion green even if the write-error handling is broken. It
# would then be testing "the fallback failed", not "the fallback failed FOR THE REASON
# THIS TEST NAMES". CLIP_TTY still points at _clip_reset's unopenable path.
ln -s "$_real_tr" "$CBIN/tr"
ln -s "$(command -v base64)" "$CBIN/base64"
_clip_fails "clip exits non-zero with no backend and no terminal" "$CLIP"

# OSC 52 fallback — the branch that makes `clip` work at all on a headless ssh box.
# Asserted on the WIRE FORMAT, not just "did something happen": a terminal ignores a
# malformed sequence silently, so a test that only checked for output would pass while
# the user's copy vanished. base64/tr are symlinked in because the fallback shells out
# to them under the stripped PATH.
_clip_reset
ln -s "$_real_tr" "$CBIN/tr"
ln -s "$(command -v base64)" "$CBIN/base64"
export CLIP_TTY="$CBIN/tty-osc52"
_osc_payload='hello osc52'
if printf '%s' "$_osc_payload" | PATH="$CBIN" "$CLIP" 2>/dev/null; then
  # \033]52;c;<base64>\a  — selection `c`, BEL-terminated.
  # `$(cat …)` strips ALL trailing newlines, which would normalise a stray LF after the
  # BEL right out of the comparison — so a regression that emitted
  # `ESC ]52;c;<b64> BEL LF` would sail through a test whose whole job is the exact wire
  # format. The X sentinel preserves the file's trailing bytes; strip it after.
  _osc_raw="$(cat "$CBIN/tty-osc52"; printf X)"
  _osc_raw="${_osc_raw%X}"
  _osc_b64="${_osc_raw#$'\033']52;c;}"
  _osc_b64="${_osc_b64%$'\a'}"
  if [[ "$_osc_raw" == $'\033']52\;c\;*$'\a' ]]; then
    pass "clip: OSC 52 fallback emits a BEL-terminated \\033]52;c; sequence"
  else
    fail "clip: OSC 52 framing wrong (got: $(printf '%q' "$_osc_raw"))"
  fi
  if [[ "$(printf '%s' "$_osc_b64" | base64 -d 2>/dev/null)" == "$_osc_payload" ]]; then
    pass "clip: OSC 52 payload base64-decodes back to exactly what was piped in"
  else
    fail "clip: OSC 52 payload did not round-trip"
  fi
  # A newline anywhere in the base64 terminates the escape early and the terminal
  # copies a truncated value — which is why the encoder pipes through `tr -d`, and
  # why `base64 -w0` (GNU-only) is not used.
  #
  # The payload has to be LONG to test this. GNU base64 wraps at 76 columns, so it
  # only emits a newline once the encoding exceeds that — i.e. past ~57 bytes of
  # input. A short multi-line string encodes to one line either way, and an assertion
  # built on one passes just as happily with the `tr` removed. (Confirmed by deleting
  # it: the short-input version of this test did not notice.) 300 bytes forces
  # several wraps on any implementation that wraps at all.
  _osc_long="$(printf 'the quick brown fox jumps over the lazy dog %.0s' 1 2 3 4 5 6 7)"
  printf '%s\n%s\n' "$_osc_long" "$_osc_long" | PATH="$CBIN" "$CLIP" 2>/dev/null
  _osc_multi="$(cat "$CBIN/tty-osc52"; printf X)"
  if [[ "${_osc_multi%X}" != *$'\n'* ]]; then
    pass "clip: OSC 52 payload stays one unbroken line for multi-line input"
  else
    fail "clip: OSC 52 payload contains a newline — the sequence would be truncated"
  fi
else
  fail "clip: OSC 52 fallback did not run with no backend and a writable CLIP_TTY"
fi
# The escape must go to the terminal, never stdout: `clip` is used in pipelines and as
# nvim's provider, so anything on stdout corrupts the caller's data.
_clip_reset
ln -s "$_real_tr" "$CBIN/tr"
ln -s "$(command -v base64)" "$CBIN/base64"
export CLIP_TTY="$CBIN/tty-stdout"
_osc_stdout="$(printf 'payload' | PATH="$CBIN" "$CLIP" 2>/dev/null)"
if [[ -z "$_osc_stdout" && -s "$CBIN/tty-stdout" ]]; then
  pass "clip: OSC 52 writes to the tty and leaves stdout empty"
else
  fail "clip: OSC 52 leaked to stdout (got '$_osc_stdout')"
fi
unset _osc_payload _osc_raw _osc_b64 _osc_stdout _osc_long _osc_multi

# ── the tmux copy-pipe case (#525) ───────────────────────────────────────────
# Every OSC 52 case above points CLIP_TTY at a writable FILE, so all of them exercise a
# clip that has somewhere to write. The one binding that actually names `clip` does not:
#
#   tmux.reset.conf:  bind -T copy-mode-vi y  send -X copy-pipe-and-cancel "clip"
#
# `copy-pipe` runs its command through tmux's job_run(), a child of the daemonized server
# — setsid'd, no controlling terminal, stderr to /dev/null. So /dev/tty fails to OPEN
# (ENXIO; it still exists and still passes a -w permission test, which is why clip attempts
# the write rather than probing), the error goes nowhere, and clip exits 1 in silence.
#
# `setsid` is the faithful reproduction of that shape, and the only one — a redirected or
# closed stdin does not detach the controlling terminal. Absent on macOS, so this skips
# there rather than pretending to cover it.
if ! have setsid; then
  skip "clip: tmux copy-pipe fallback (setsid not available — Linux-only reproduction)"
else
  _clip_reset
  ln -s "$_real_tr" "$CBIN/tr"
  ln -s "$(command -v base64)" "$CBIN/base64"
  # A tmux stub that records the call and captures what was piped to it, so the assertion
  # is "the payload arrived intact", not merely "something invoked tmux".
  _tmux_log="$CBIN/tmux.calls"
  # The stub touches a .done marker AFTER the payload is fully written. Waiting on the
  # payload file itself would race: `cat >file` CREATES it empty and fills it after, so a
  # reader that waits for existence can read nothing and call it corruption.
  # `cat` by ABSOLUTE path: the stub inherits the stripped PATH="$CBIN", where cat does
  # not exist. A bare `cat` there fails AFTER the shell has already created the redirect
  # target, leaving a 0-byte payload that reads exactly like a corrupted copy.
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\nif [ "$1" = load-buffer ]; then %s >"%s.payload"; : >"%s.done"; exit 0; fi\nexit 1\n' \
    "$_tmux_log" "$(command -v cat)" "$_tmux_log" "$_tmux_log" >"$CBIN/tmux"
  chmod +x "$CBIN/tmux"

  _clip_pipe_out="$(printf 'yanked\ttext\n' \
    | setsid env PATH="$CBIN" TMUX=/tmp/fake,1,0 CLIP_PROC_VERSION="$CBIN/procversion" \
        "$_real_bash" "$CLIP" </dev/stdin 2>&1)"
  _clip_pipe_rc=$?
  # setsid detaches, so the write to the log races our read by a few ms.
  _cp_i=0
  while [ ! -f "$_tmux_log.done" ] && [ "$_cp_i" -lt 50 ]; do sleep 0.1; _cp_i=$((_cp_i + 1)); done

  if [ "$_clip_pipe_rc" -eq 0 ] && grep -q 'load-buffer -w -' "$_tmux_log" 2>/dev/null; then
    pass "clip: with no controlling terminal inside tmux, falls back to tmux load-buffer -w"
  else
    fail "clip: the tmux copy-pipe path did not reach load-buffer (rc=$_clip_pipe_rc)"
    [ -n "$_clip_pipe_out" ] && printf '%s\n' "$_clip_pipe_out" | sed 's/^/    /' >&2
  fi

  # The payload must survive the base64 round-trip EXACTLY — clip reconstructs the raw
  # bytes by decoding, so a decode that mangled tabs or ate the trailing newline would be
  # a silent corruption of every yank taken this way.
  if [ -f "$_tmux_log.payload" ] \
    && [ "$(od -An -c <"$_tmux_log.payload" | tr -s ' ')" = "$(printf 'yanked\ttext\n' | od -An -c | tr -s ' ')" ]; then
    pass "clip: the tmux fallback payload round-trips byte-for-byte (tabs and trailing newline)"
  else
    fail "clip: the tmux fallback corrupted the payload"
    [ -f "$_tmux_log.payload" ] && od -c "$_tmux_log.payload" | sed 's/^/    /' >&2
  fi

  # Outside tmux the same detached shape must still fail LOUDLY. A fallback that swallowed
  # this would hide a genuinely missing backend, which is the failure the OSC 52 work in
  # v4.13.0 set out to make visible.
  _clip_reset
  ln -s "$_real_tr" "$CBIN/tr"
  ln -s "$(command -v base64)" "$CBIN/base64"
  if printf 'x' | setsid env PATH="$CBIN" CLIP_PROC_VERSION="$CBIN/procversion" \
      "$_real_bash" "$CLIP" </dev/stdin >/dev/null 2>&1; then
    fail "clip: detached with no tmux and no backend should exit non-zero"
  else
    pass "clip: detached with no tmux and no backend still fails loudly (no silent success)"
  fi
  unset _clip_pipe_out _clip_pipe_rc _tmux_log _cp_i
fi

# clip-paste (paste) — mirror ladder; the WSL leg also strips the CR powershell adds.
_clip_reset
export WSL_DISTRO_NAME=Ubuntu
ln -s "$_real_tr" "$CBIN/tr"
_stub powershell.exe 'printf "WSLPASTE\r"'
_clip_is "clip-paste → powershell + CR-strip on WSL" "$CLIPPASTE" WSLPASTE
unset WSL_DISTRO_NAME
_clip_reset
# WSL detected from /proc/version alone (no WSL_DISTRO_NAME).
printf 'Linux version 5.15.0-microsoft-standard-WSL2\n' >"$CBIN/procversion"
ln -s "$_real_tr" "$CBIN/tr"
_stub powershell.exe 'printf "WSLPASTE\r"'
_clip_is "clip-paste → powershell via /proc/version (no WSL_DISTRO_NAME)" "$CLIPPASTE" WSLPASTE
_clip_reset
_stub uname 'echo Darwin'
_stub pbpaste 'echo MAC'
_clip_is "clip-paste → pbpaste on Darwin" "$CLIPPASTE" MAC
_clip_reset
export WAYLAND_DISPLAY=wayland-0
_stub wl-paste 'echo WL'
_clip_is "clip-paste → wl-paste under Wayland" "$CLIPPASTE" WL
unset WAYLAND_DISPLAY
_clip_reset
export DISPLAY=:0
_stub xclip 'echo XCLIP'
_clip_is "clip-paste → xclip -o on X11" "$CLIPPASTE" XCLIP
_clip_reset
# No OSC 52 mirror here, deliberately: reading the clipboard over OSC 52 means querying
# the terminal and waiting for a reply that most terminals refuse to send, so clip-paste
# still fails — loudly — where clip now succeeds. bin/clip-paste's header explains why,
# and the asymmetry is intentional rather than an oversight.
_clip_fails "clip-paste exits non-zero with no backend (no OSC 52 read path)" "$CLIPPASTE"

# ── D. Neovim config load (nvim/, headless) ───────────────────────────────────
# nvim/ is the largest body of code in Core yet was validated only by luacheck
# (static). Lua that is luacheck-clean can still be a BROKEN config — a bad vim API
# call, a malformed lazy spec — that surfaces only when nvim actually starts, and it
# fans out to nine repos. This loads the AUTHORED Lua headlessly: the pure config layer
# (globals/options/keymaps/autocmds/clipboard/providers) AND every plugin SPEC file
# (require evaluates the spec TABLE; lazy's deferred config/keys callbacks do NOT run,
# so no plugin needs to be installed — every plugin `require` in this tree is inside
# such a callback). Hermetic + offline, mirroring how the zsh tests pre-seed empty
# plugin dirs; graceful skip when nvim is absent, exactly like the linters. Real
# plugin RUNTIME (the deferred callbacks) is out of scope — luacheck covers its syntax.
hdr "neovim config load (nvim/ headless)"
if ! ((SCOPE_NVIM)); then
  skip "nvim config load (out of scope)"
elif have nvim; then
  probe="$SANDBOX/nvim-probe.lua"
  cat >"$probe" <<'LUA'
vim.opt.runtimepath:prepend(vim.env.CORE_NVIM_DIR)
local errs = {}
local function try(mod)
  local ok, err = pcall(require, mod)
  if not ok then errs[#errs + 1] = mod .. " → " .. tostring(err) end
end
for _, m in ipairs({
  "gerrrt.config.globals", "gerrrt.config.options", "gerrrt.config.keymaps",
  "gerrrt.config.autocmds", "gerrrt.config.clipboard", "gerrrt.config.providers",
}) do try(m) end
-- :checkhealth gerrrt module — loaded only by checkhealth at runtime, so this is its
-- only load gate. Require it AND assert it exposes a check() function.
do
  local ok, m = pcall(require, "gerrrt.health")
  if not ok then
    errs[#errs + 1] = "gerrrt.health → " .. tostring(m)
  elseif type(m) ~= "table" or type(m.check) ~= "function" then
    errs[#errs + 1] = "gerrrt.health → did not return a table with a check() function"
  end
end
-- buf-config filetype detection (config/autocmds.lua, required above). Every buf config basename
-- must resolve to the `buf-config` filetype (so buf_ls attaches and `:checkhealth vim.lsp` stops
-- flagging an unknown filetype), and `buf-config` must alias the yaml treesitter parser (so
-- plugins/nvim-treesitter's get_lang-driven start lights these buffers). A dropped basename or a
-- lost parser alias is luacheck-clean but silently regresses attach/highlighting — and fans out 9×.
do
  for _, fname in ipairs({ "buf.yaml", "buf.gen.yaml", "buf.work.yaml", "buf.policy.yaml", "buf.lock" }) do
    local got = vim.filetype.match({ filename = fname })
    if got ~= "buf-config" then
      errs[#errs + 1] = ("buf-config ft: %s → %s (want buf-config)"):format(fname, tostring(got))
    end
  end
  local alias = vim.treesitter.language.get_lang("buf-config")
  if alias ~= "yaml" then
    errs[#errs + 1] = "buf-config ft: treesitter lang alias → " .. tostring(alias) .. " (want yaml)"
  end
end
-- every plugin spec must require cleanly and return a lazy spec table
local pdir = vim.env.CORE_NVIM_DIR .. "/lua/gerrrt/plugins"
for _, f in ipairs(vim.fn.readdir(pdir) or {}) do
  local name = f:match("^(.+)%.lua$")
  if name then
    local mod = "gerrrt.plugins." .. name
    local ok, res = pcall(require, mod)
    if not ok then
      errs[#errs + 1] = mod .. " → " .. tostring(res)
    elseif type(res) ~= "table" then
      errs[#errs + 1] = mod .. " → did not return a spec table"
    end
  end
end
-- #652 REGRESSION NET — nvim-lint must DECLARE mason.nvim as a dependency.
-- plugins/nvim-lint.lua loads on `User FilePost` and replays the triggering buffer at the end of
-- its config(), spawning Mason-installed linters (rubocop, markdownlint-cli2, eslint_d, ...). Those
-- resolve only once mason.setup() has prepended <data>/mason/bin to vim.env.PATH. nvim-lspconfig
-- loads on the SAME event and pulls mason in, but lazy.nvim orders a plugin against its DECLARED
-- dependencies only -- never against another plugin on the same event -- so without this edge the
-- replay raced mason's PATH prepend and lost about half the time: rubocop linted on open 4/6 on
-- macOS (dotgibson/dotfiles-MacBook#191) and 3/6 on Windows, while shellcheck, which lives on the
-- inherited PATH, was 6/6. vim.uv.spawn got ENOENT -- silently on Windows, where it read as "this
-- file is clean" rather than as an error.
-- ASSERTED AT SPEC LEVEL, deliberately: the ordering this guards is a lazy.nvim guarantee, so
-- re-deriving it at runtime would test lazy rather than this config -- and it cannot be tested
-- hermetically anyway (it needs lazy.nvim, nvim-lint AND mason really installed, i.e. the network).
-- Dropping the dependency is luacheck-clean, load-clean and regresses only intermittently on a real
-- machine, which is exactly the profile that needs a static gate.
-- #703 EXTENDS THE SAME NET TO conform.nvim, which had the identical undeclared dependency
-- with a WORSE failure shape. plugins/conform.lua loads on `BufWritePre` and spawns Mason-installed
-- formatters (prettierd, gofumpt, clang-format, php-cs-fixer, sql-formatter, ktlint,
-- google-java-format, taplo, ...); it declared no dependencies at all, and mason arrived only
-- incidentally via nvim-lspconfig / mason-tool-installer. Unlike #652 that is NOT a race: `-c`
-- commands run BEFORE VimEnter, so in the one-shot/scripted shape neither VeryLazy nor the
-- vim.schedule'd `User FilePost` emit has fired and mason has NEVER loaded by BufWritePre.
-- MEASURED on macOS with a `{"a":1,   "b":[1,2,3]}` fixture and prettierd (Mason-only; stylua and
-- shfmt also live on the base PATH and MASK this):
--   one-shot `nvim --headless f.json -c write -c qa!` -> 0/4 formatted (mason loaded=false,
--     executable("prettierd")=0 at BufWritePre); the same write deferred past startup (the
--     interactive shape) -> 4/4 (mason loaded=true, =1).
-- And it fails SILENTLY -- conform auto-skips a formatter that is not on PATH, so there is no
-- error and no notification, the file is just written unformatted.
-- ONE table-driven check rather than two copies: the assertion is identical, the per-entry `why`
-- keeps the failure message specific, and the next Mason-spawning spec is one more line.
for _, case in ipairs({
  {
    mod = "gerrrt.plugins.nvim-lint",
    file = "plugins/nvim-lint.lua",
    why = "its on-open replay will race mason's PATH prepend again (#652)",
  },
  {
    mod = "gerrrt.plugins.conform",
    file = "plugins/conform.lua",
    why = "format-on-save will silently skip every Mason-installed formatter in the "
      .. "one-shot/scripted shape again (#703)",
  },
}) do
  local ok, spec = pcall(require, case.mod)
  if not ok or type(spec) ~= "table" then
    errs[#errs + 1] = "mason dep: " .. case.file .. " did not load as a spec table"
  else
    local found = false
    for _, d in ipairs(spec.dependencies or {}) do
      -- lazy accepts a bare "owner/name" or a { "owner/name", opts = ... } fragment
      local dep = type(d) == "table" and d[1] or d
      if dep == "mason-org/mason.nvim" then
        found = true
      end
    end
    if not found then
      errs[#errs + 1] = "mason dep: " .. case.file .. " no longer declares "
        .. "mason-org/mason.nvim in `dependencies` -- " .. case.why
    end
  end
end
-- LSP layer: servers/init.lua wires 19 server configs + the on_attach/diagnostics
-- helpers, but ALL of it runs inside a deferred plugin callback (plugins/nvim-lspconfig)
-- — so the loop above never touches it, and luacheck (static) was its only gate. A bad
-- vim.lsp.config{} call or a typo'd capability there is luacheck-clean and breaks only on
-- first file-open, then fans out 9×. Close that: require utils.lsp/diagnostics, and every
-- servers/* LEAF. Each leaf returns a PLAIN CONFIG TABLE (it used to return a
-- `function(capabilities)` factory; capabilities now come from the "*" wildcard set once in
-- servers/init.lua, so the leaves are pure data). Requiring one evaluates the file without
-- registering anything, so no blink.cmp/lspconfig need be installed. servers/init.lua itself
-- is skipped — it require()s blink.cmp, a plugin absent from this hermetic probe.
-- utils.ui-highlights has the SAME gap: it's only require()d inside tokyonight's deferred
-- on_highlights callback (plugins/theme.lua), which the plugins/* loop above never runs — so
-- add it here too. It returns `M` with an `apply(hl, c)` function; requiring evaluates the
-- file without calling apply, so no tokyonight/colorscheme need be present.
for _, m in ipairs({ "gerrrt.utils.lsp", "gerrrt.utils.diagnostics", "gerrrt.utils.ui-highlights" }) do
  try(m)
end
local sdir = vim.env.CORE_NVIM_DIR .. "/lua/gerrrt/servers"
for _, f in ipairs(vim.fn.readdir(sdir) or {}) do
  local name = f:match("^(.+)%.lua$")
  if name and name ~= "init" then
    local mod = "gerrrt.servers." .. name
    local ok, res = pcall(require, mod)
    if not ok then
      errs[#errs + 1] = mod .. " → " .. tostring(res)
    elseif type(res) ~= "table" then
      errs[#errs + 1] = mod .. " → did not return a config table (got " .. type(res) .. ")"
    elseif next(res) == nil then
      -- An empty table means the file evaluated but configures nothing — almost certainly a
      -- botched edit rather than intent, and it would silently leave that server on defaults.
      errs[#errs + 1] = mod .. " → returned an EMPTY config table"
    end
  end
end
if #errs > 0 then
  io.stderr:write(table.concat(errs, "\n") .. "\n")
  vim.cmd("cquit 1")
end
vim.cmd("quitall!")
LUA
  # -u the probe AS init (so the repo's real bootstrap never runs → no lazy clone, no
  # network), headless, no shada/swap. A clean exit means every authored module and
  # spec loaded; the probe `:cquit 1`s with the offending modules on stderr otherwise.
  nvim_err="$SANDBOX/nvim.err"
  if CORE_NVIM_DIR="$HERE/nvim" nvim --headless -u "$probe" -i NONE -n +qa >/dev/null 2>"$nvim_err"; then
    pass "nvim loaded all config + plugin specs + LSP server configs (no lua errors)"
  else
    fail "nvim config/plugin-spec/lsp load error:"
    [[ -s "$nvim_err" ]] && sed 's/^/    /' "$nvim_err" >&2
  fi

  # Actually RUN :checkhealth gerrrt. The probe above only proves gerrrt.health LOADS and
  # exposes check(); this FIRES check() in the real checkhealth context, so a runtime error
  # in its vim.health calls (a typo'd h.warn, a bad API) is caught — nothing else exercises
  # it. -u NONE keeps it hermetic; --cmd puts nvim/ on the runtimepath so checkhealth
  # discovers lua/gerrrt/health.lua; we write the report buffer out and assert OUR section
  # rendered (h.start("dotfiles-core: …") is check()'s first call, so its absence means
  # check() never ran or threw immediately). checkhealth never prompts, so headless can't hang.
  ckrep="$SANDBOX/checkhealth.txt"
  ckerr="$SANDBOX/checkhealth.err"
  : >"$ckrep"
  # Pass the paths via ENV and fnameescape() them INSIDE vim (the idiom the event probe
  # below uses), so a space in $SANDBOX/$HERE can't break the Ex `set rtp`/`write` parsing.
  # `-c` runs post-startup in order: rtp is set before checkhealth scans it, before write.
  # Capture stderr (not /dev/null) so a failure with an empty report is still diagnosable.
  CORE_NVIM_DIR="$HERE/nvim" CORE_CK_REP="$ckrep" \
    nvim --headless -u NONE -i NONE -n \
    -c 'execute "set rtp^=" .. fnameescape($CORE_NVIM_DIR)' \
    -c 'checkhealth gerrrt' \
    -c 'execute "write!" fnameescape($CORE_CK_REP)' \
    -c 'qa!' >/dev/null 2>"$ckerr"
  # Assert ALL FIVE sections rendered — each helper's h.start() runs before any early return, so a
  # header proves that helper ran without throwing (a bad vim.health call in any of them would drop
  # its header). The LSP/formatters/linters sections show their "not loaded — open a file" info here
  # (hermetic: no plugins, no file opened), which is the correct side-effect-free behavior.
  if grep -q "dotfiles-core: clipboard" "$ckrep" 2>/dev/null \
     && grep -q "dotfiles-core: LSP servers" "$ckrep" 2>/dev/null \
     && grep -q "dotfiles-core: formatters" "$ckrep" 2>/dev/null \
     && grep -q "dotfiles-core: linters" "$ckrep" 2>/dev/null \
     && grep -q "dotfiles-core: Claude Code" "$ckrep" 2>/dev/null; then
    pass "checkhealth gerrrt ran (clipboard + LSP + formatters + linters + Claude sections rendered)"
  else
    fail "checkhealth gerrrt did not render all sections (a check() helper missing or threw):"
    [[ -s "$ckrep" ]] && sed 's/^/    /' "$ckrep" >&2
    [[ -s "$ckerr" ]] && sed 's/^/    /' "$ckerr" >&2
  fi

  # Native-Windows clipboard branch (headless, has("win32") stubbed). The Neovim CI matrix is
  # Ubuntu/macOS, so check_clipboard's has("win32") early return never runs under the gate — a
  # regression in it (running the Unix clip/clip-paste probe on the host, or a bad vim.health
  # call) would otherwise pass the full audit. This stubs vim.fn.has→win32 and CAPTURES the
  # vim.health calls (rather than rendering a report), asserting the clipboard section reports OK
  # (never warn/error) AND that the branch skips the executable()/system() probe entirely. The
  # whole body is pcall-guarded so even a bad stub cquits (fails) instead of hanging on a prompt.
  winprobe="$SANDBOX/nvim-health-win32.lua"
  cat >"$winprobe" <<'LUA'
local function run()
  local calls = {}
  vim.health = {
    start = function(s) calls[#calls + 1] = { "start", s } end,
    ok    = function(s) calls[#calls + 1] = { "ok", s } end,
    warn  = function(s) calls[#calls + 1] = { "warn", s } end,
    info  = function(s) calls[#calls + 1] = { "info", s } end,
    error = function(s) calls[#calls + 1] = { "error", s } end,
  }
  -- Force the native-Windows branch; trip a flag if the Unix probe is ever run.
  -- SCOPED TO THE CLIPBOARD SECTION. A run-wide flag would also fire on helpers that probe
  -- legitimately on Windows — check_claude gates on the `claude` binary there exactly as it does
  -- everywhere else — turning this into a "no helper may call executable()" rule, which is not the
  -- invariant being guarded. The one being guarded is: check_clipboard's win32 early return must
  -- fire BEFORE its clip/clip-paste ladder.
  local probed = false
  local function in_clipboard()
    for i = #calls, 1, -1 do
      if calls[i][1] == "start" then
        return (calls[i][2] or ""):find("dotfiles%-core: clipboard", 1) ~= nil
      end
    end
    return false
  end
  vim.fn.has = function(f) return (f == "win32") and 1 or 0 end
  vim.fn.executable = function(_) probed = probed or in_clipboard(); return 0 end
  vim.fn.system = function(_) probed = probed or in_clipboard(); return "" end
  assert(vim.fn.has("win32") == 1, "stub failed: vim.fn.has('win32') did not return 1")

  local M = dofile(vim.env.CORE_HEALTH_LUA)
  assert(type(M) == "table" and type(M.check) == "function", "health.lua did not return a module with check()")
  M.check()

  -- The clipboard section's calls run from its start() up to the next start().
  local in_clip, saw_start, saw_ok = false, false, false
  for _, c in ipairs(calls) do
    local kind, text = c[1], c[2] or ""
    if kind == "start" then
      in_clip = text:find("dotfiles%-core: clipboard", 1) ~= nil
      if in_clip then saw_start = true end
    elseif in_clip then
      assert(kind ~= "warn" and kind ~= "error", "clipboard section emitted a " .. kind .. " on native Windows: " .. text)
      if kind == "ok" then saw_ok = true end
    end
  end
  assert(saw_start, "clipboard section did not run (no start)")
  assert(saw_ok, "clipboard section did not report OK on native Windows")
  assert(not probed, "native-Windows branch called executable()/system() — it must skip the Unix probe")
end

local ok, err = pcall(run)
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
vim.cmd("quitall!")
LUA
  win_err="$SANDBOX/nvim-health-win32.err"
  if CORE_HEALTH_LUA="$HERE/nvim/lua/gerrrt/health.lua" \
     nvim --headless -u "$winprobe" -i NONE -n +qa >/dev/null 2>"$win_err"; then
    pass "checkhealth gerrrt: native-Windows clipboard branch skips the Unix probe (has('win32') stubbed)"
  else
    fail "checkhealth gerrrt native-Windows clipboard branch probe failed:"
    [[ -s "$win_err" ]] && sed 's/^/    /' "$win_err" >&2
  fi
else
  skip "nvim config load (nvim not installed — runs in CI)"
fi

# ── D1b. lazy.nvim's lockfile lives in STATE, not the vendored tree ───────────
# THE regression net for #465. nvim/lazy-lock.json is tracked inside core/, the one tree a
# consumer must keep byte-for-byte upstream — and lazy.nvim REWRITES its lockfile in place
# whenever plugins are installed or updated, while an OS repo bootstrap-symlinks
# ~/.config/nvim into that very tree. Opening the editor ONCE was enough to dirty it: a
# fresh openSUSE box repinned 10 plugins, a fresh Gentoo box 2, with nobody running
# :Lazy update. Consumers' vendoring gates (`make check-core`, a no-core-edits pre-commit
# hook, core-integrity at PR time) then failed closed on it — correctly, but against the
# operator, since the writer was lazy.nvim rather than a person. A pre-push gate that a
# routine editor session turns red is a gate people learn to ignore.
#
# So the contract is now: lazy writes $XDG_STATE_HOME/nvim/lazy-lock.json, and
# nvim/lazy-lock.json is a read-only fleet SEED copied in on first run. Both halves need
# pinning — the seed alone would not stop the drift, and the relocation alone would lose
# reproducibility on a fresh machine.
#
# HERMETIC, because the real thing needs the network: a STUB lazy.nvim is planted where
# lazy would be cloned (so config/lazy.lua's bootstrap finds it and skips the git clone),
# and its setup() records the opts instead of installing anything. That lets the actual
# nvim/lua/gerrrt/config/lazy.lua run start to finish — seeding included — with no plugin
# ever fetched. Asserting the recorded `lockfile` opt is what makes this a real gate rather
# than a grep: it is the value lazy would actually use.
hdr "lazy.nvim lockfile is state, not the vendored config tree (#465)"
if have nvim; then
  _lz="$(mktemp -d "$SANDBOX/lazylock.XXXXXX")"
  mkdir -p "$_lz/config" "$_lz/state" "$_lz/data" "$_lz/cache"
  # NORMALISE BOTH SIDES before comparing paths, because the two platforms disagree about
  # which form nvim reports. On macOS $TMPDIR is /var/folders/…, and /var is a symlink to
  # /private/var, and stdpath() came back RESOLVED — so comparing against the literal $_lz
  # false-reds there. Resolving only the expected side then false-reds on Linux, where the
  # same call came back LITERAL. Neither form is "the" answer, so resolve both and compare
  # resolved-to-resolved; the assertion is about WHICH DIRECTORY the lockfile is in, not
  # about which spelling of that directory nvim happened to hand back.
  _lz_real="$(cd "$_lz" && pwd -P)"
  _core_nvim_real="$(cd "$HERE/nvim" && pwd -P)"
  _lz_resolve() { # <path> — absolute, symlink-resolved; EMPTY unless the input is itself
    # an absolute path with an existing parent. The absolute-input guard is load-bearing:
    # without it, an UNSET opt arrives here as the literal "nil", `dirname nil` is ".", and
    # the result is a perfectly plausible $PWD/nil — so the "is an absolute path outside the
    # tree" assertion passes vacuously on exactly the pre-fix code it exists to catch.
    local d b
    [[ "$1" == /* ]] || return 0
    d="$(dirname "$1")" b="$(basename "$1")"
    [[ -d "$d" ]] || return 0
    printf '%s/%s' "$(cd "$d" && pwd -P)" "$b"
  }
  ln -s "$HERE/nvim" "$_lz/config/nvim"
  # The stub, at the exact path config/lazy.lua bootstraps into — so `fs_stat(lazypath)`
  # is true, no clone is attempted, and `require("lazy")` resolves here.
  mkdir -p "$_lz/data/nvim/lazy/lazy.nvim/lua/lazy"
  cat >"$_lz/data/nvim/lazy/lazy.nvim/lua/lazy/init.lua" <<'LZSTUB'
-- test stub: record what the real config asked for, install nothing.
local M = {}
function M.setup(opts)
  local f = assert(io.open(vim.env.CORE_LZ_OUT, "w"))
  f:write(tostring(opts.lockfile) .. "\n")
  f:close()
end
return M
LZSTUB
  _lz_out="$_lz/opts.txt"
  _lz_err="$_lz/nvim.err"
  # SNAPSHOT the vendored seed before the run, so assertion 3 below can ask the question it
  # actually means — "did THIS RUN write through into the vendored tree?" — against content
  # rather than against git's view of the maintainer's worktree. See the note there.
  _lz_seed_before="$_lz/seed-before.json"
  cp "$HERE/nvim/lazy-lock.json" "$_lz_seed_before"
  # -u the repo's REAL init.lua (via the symlinked config dir), not a probe: the seeding
  # runs at config load, so a probe that skipped it would test nothing.
  if HOME="$_lz" XDG_CONFIG_HOME="$_lz/config" XDG_STATE_HOME="$_lz/state" \
    XDG_DATA_HOME="$_lz/data" XDG_CACHE_HOME="$_lz/cache" \
    DOTFILES_OFFLINE=1 CORE_LZ_OUT="$_lz_out" \
    nvim --headless -i NONE -n +qa </dev/null >/dev/null 2>"$_lz_err"; then
    _lz_lock="$(head -n1 "$_lz_out" 2>/dev/null || true)"
    _lz_lock_real="$(_lz_resolve "$_lz_lock")"

    # 1) THE FIX. The path lazy was handed must be under XDG_STATE_HOME and must NOT be
    #    inside the config tree — that tree is the vendored one, and anything lazy writes
    #    there is drift a consumer's integrity gate will reject.
    if [[ "$_lz_lock_real" == "$_lz_real/state/nvim/lazy-lock.json" ]]; then
      pass "lazy lockfile resolves to \$XDG_STATE_HOME/nvim/lazy-lock.json"
    else
      fail "lazy lockfile is '$_lz_lock' — it must not live in the vendored config tree"
    fi
    # Stated as a POSITIVE requirement, not just "not inside the tree": an unset opt is
    # also not inside the tree, so the negative form alone passes vacuously on exactly the
    # pre-fix code this exists to catch. Require a real absolute path that is neither the
    # seed nor anywhere under the symlinked config dir.
    # The config dir is a SYMLINK into the repo, so "inside the config tree" resolves to
    # the repo nvim/ dir — check against that, which catches both spellings at once.
    if [[ "$_lz_lock_real" == /* && "$_lz_lock_real" != "$_core_nvim_real/"* ]]; then
      pass "lazy lockfile is an absolute path outside the symlinked config tree and is not the seed"
    else
      fail "lazy lockfile '$_lz_lock' is unset, is the seed, or is inside the vendored tree"
    fi

    # 2) REPRODUCIBILITY. A first run must start from the fleet's committed pins rather
    #    than resolving every plugin's default branch afresh — that is the entire reason
    #    Core ships a lockfile at all, and the half a bare relocation would have lost.
    # core_files_identical, not `cmp` — diffutils is not guaranteed present and this
    # repo has been bitten by assuming it (#572); the helper hashes with git instead.
    if [[ -f "$_lz/state/nvim/lazy-lock.json" ]] &&
      core_files_identical "$_lz/state/nvim/lazy-lock.json" "$HERE/nvim/lazy-lock.json"; then
      pass "first run seeds the state lockfile from Core's vendored pins (reproducible)"
    else
      fail "first run did not seed \$XDG_STATE_HOME/nvim/lazy-lock.json from the Core seed"
    fi

    # 3) The seed and the working copy must be DIFFERENT FILES, not the same inode reached
    #    two ways. Copying rather than symlinking is the whole mechanism: a symlink from
    #    state back into the config tree would satisfy every path assertion above and still
    #    let lazy write straight through into the vendored tree — the original bug wearing
    #    a state-directory costume.
    if [[ ! -L "$_lz/state/nvim/lazy-lock.json" ]]; then
      pass "the state lockfile is an independent copy, not a link back into the vendored tree"
    else
      fail "the state lockfile links back into the vendored tree"
    fi

    # 3b) The run must leave the vendored seed BYTE-IDENTICAL.
    #
    #    WHAT THIS DOES NOT CATCH, stated first so nobody reads it as more than it is: the
    #    #465 bug itself. lazy is stubbed here, so nothing plays the part of lazy REWRITING
    #    its lockfile, and "the vendored file is untouched" would pass on the pre-fix code
    #    too. Assertions 1 and 2 are what pin #465, by testing the CONFIGURED destination.
    #
    #    WHAT IT DOES CATCH: config/lazy.lua's own SEEDING, which — unlike lazy — really does
    #    run here, against a config dir symlinked at the vendored tree. `seed` there resolves
    #    to $HERE/nvim/lazy-lock.json, so an inverted fs_copyfile(lockfile, seed), an
    #    fs_symlink, or anything else that writes the seed instead of reading it would
    #    corrupt the fleet's pins from a plain editor start. That is a live path, and it is
    #    worth a gate.
    #
    #    WHY CONTENT AND NOT `git status --porcelain nvim/lazy-lock.json`, which this
    #    replaces: that asked git whether the WORKTREE was dirty, which is a different
    #    question and answers this one wrongly in both directions.
    #      · False RED, the one that bit: a maintainer running ./scripts/update-nvim-plugins.sh
    #        — the sanctioned way to move these pins — has an uncommitted seed by design, so
    #        `make audit` failed before they could commit. A gate that fires on the workflow
    #        it is meant to protect is one people learn to route around, which is the same
    #        lesson the #465 comment above already records about consumer vendoring gates.
    #      · False GREEN: outside a git checkout (a release tarball, a vendored copy) the
    #        `git rev-parse --show-toplevel` guard short-circuited the whole clause to true,
    #        so the assertion silently stopped asserting.
    #    Comparing a pre-run snapshot to the post-run file has neither failure mode and needs
    #    no repo. core_files_identical, not `cmp` — diffutils is not guaranteed present (#572).
    if core_files_identical "$_lz_seed_before" "$HERE/nvim/lazy-lock.json"; then
      pass "the run left the vendored seed byte-identical (no write-through)"
    else
      fail "the run MODIFIED $HERE/nvim/lazy-lock.json — config/lazy.lua wrote through into the vendored tree"
    fi
  else
    fail "nvim failed to load the real config with a stubbed lazy.nvim:"
    [[ -s "$_lz_err" ]] && sed 's/^/    /' "$_lz_err" >&2
  fi
else
  skip "lazy lockfile location (nvim not installed — runs in CI)"
fi

# ── D2. Neovim event-driven autocmd callbacks (nvim/, headless) ───────────────
# Section D proves the modules LOAD; it does not prove their EVENT CALLBACKS run.
# An autocmd registers fine and only its callback fires later — on a yank, a save,
# an LSP attach — so a bad vim API call inside one is luacheck-clean, load-clean, and
# breaks only when you actually edit. That blind spot shipped a real bug: the
# TextYankPost highlight called a non-existent `vim.hl.hl_op`, throwing on every yank
# AND delete (TextYankPost fires on both) while the edit still ran — a red error with
# no failing gate, fanned out to nine repos. This closes it: load the autocmds, then
# FIRE the events and assert the callbacks ran clean.
#
# Events are triggered via post-startup `-c` commands (NOT inside the `-u` init): an
# autocmd error during init makes headless nvim block on a "Press ENTER" prompt,
# whereas a `-c` error is reported and nvim proceeds to the next command — so the
# gate can never hang in CI. The require itself stays in `-u` and `cquit`s on failure
# (no prompt). Detection is STDERR-NON-EMPTY, not exit code: a fired-callback error
# does not change nvim's exit status (both clean and broken runs exit 0), it only
# prints — exactly the signature the bug has. BufWritePre (format-on-save) and
# LspAttach are deliberately NOT fired here: their callbacks require plugins
# (mini.trailspace/conform) or a live LSP attach, neither present in this hermetic
# probe — luacheck covers their syntax; runtime is out of scope.
hdr "neovim event callbacks (nvim/ headless)"
if ! ((SCOPE_NVIM)); then
  skip "nvim event callbacks (out of scope)"
elif have nvim; then
  evt_probe="$SANDBOX/nvim-events.lua"
  cat >"$evt_probe" <<'LUA'
vim.opt.runtimepath:prepend(vim.env.CORE_NVIM_DIR)
-- Register the autocmds. A require failure cquit's immediately (no ENTER prompt);
-- the EVENTS themselves are fired by the caller's -c flags, after startup.
local ok, err = pcall(require, "gerrrt.config.autocmds")
if not ok then
  io.stderr:write("require gerrrt.config.autocmds → " .. tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
LUA
  evt_file="$SANDBOX/probe.txt"
  printf 'one\ntwo\nthree\n' >"$evt_file"
  evt_err="$SANDBOX/nvim-events.err"
  # Stub `uv` on PATH so the Python FileType callback (config/autocmds.lua) is not gated out — it
  # registers its buffer-local pytest maps only when `executable("uv")`. The stub is never invoked
  # here (we assert the maps REGISTER, not that pytest runs), so its body only needs to exist +x.
  mkdir -p "$SANDBOX/bin"
  printf '#!/bin/sh\nexit 0\n' >"$SANDBOX/bin/uv"
  chmod +x "$SANDBOX/bin/uv"
  # Fire each registered event once: yank + delete (TextYankPost — the regression above), a
  # markdown FileType (per-filetype view options) and a python FileType (the pytest runner maps),
  # and a real file open (BufReadPost — cursor restore). Any callback that throws prints to stderr.
  # The python step also ASSERTS the buffer-local <leader>t{t,f} maps registered — matched by their
  # "pytest" desc, so the check is independent of whatever <leader> resolves to. The file path is
  # passed via $CORE_EVT_FILE and opened through fnameescape() rather than interpolated into the Ex
  # command, so a $SANDBOX/$TMPDIR containing spaces is safe.
  PATH="$SANDBOX/bin:$PATH" CORE_NVIM_DIR="$HERE/nvim" CORE_EVT_FILE="$evt_file" nvim --headless -u "$evt_probe" -i NONE -n \
    -c 'call setline(1, ["alpha","bravo","charlie"])' \
    -c 'normal! yy' -c 'normal! dd' \
    -c 'setfiletype markdown' \
    -c 'enew | setlocal filetype=python' \
    -c 'lua local ok=false; for _,k in ipairs(vim.api.nvim_buf_get_keymap(0,"n")) do if k.desc and k.desc:match("pytest") then ok=true end end; if not ok then io.stderr:write("FileType python did not register buffer-local pytest maps\n") end' \
    -c 'execute "edit" fnameescape($CORE_EVT_FILE)' \
    -c 'qa!' </dev/null >/dev/null 2>"$evt_err"
  if [[ -s "$evt_err" ]]; then
    fail "nvim autocmd callback errored when fired (e.g. the yank/delete highlight):"
    sed 's/^/    /' "$evt_err" >&2
  else
    pass "nvim event callbacks fired clean (TextYankPost yank+delete, FileType markdown+python w/ pytest maps, BufReadPost)"
  fi
else
  skip "nvim event callbacks (nvim not installed — runs in CI)"
fi

# ── D3. Neovim `User FilePost` contract (nvim/, headless) ─────────────────────
# config/autocmds.lua defers nvim-lspconfig, gitsigns, nvim-lint and todo-comments onto
# a custom `User FilePost` event so they load AFTER startup instead of in front of the
# first paint. Four plugins now depend on that event, but D2 above only proves the
# autocmds load and don't throw — it would still pass if FilePost never fired at all
# (every deferred plugin silently dead: no LSP, no linting, no git signs) or fired
# repeatedly (every later buffer re-emitting it). Neither shows up as an error, which
# is exactly the kind of silent breakage that fans out to nine repos.
#
# So assert the CONTRACT, not just the absence of errors — fires EXACTLY ONCE, in both
# startup shapes:
#   A. started WITH a file  — the readiness event arrives after the buffer is already named
#   B. bare start, then :edit two files — readiness arrives first, the first real file
#      triggers it, and the second must NOT re-fire (the augroup self-deletes)
# Counting (not just "did it fire") is what catches the fires-more-than-once regression.
# Headless is the only mode available in CI, and it is also the mode where UIEnter never
# fires — so this doubles as the guard on the VimEnter fallback that makes headless work.
#
# THE FIRST FILE MUST ALSO END UP WITH A FILETYPE. Firing FilePost synchronously inside
# the first buffer's BufReadPost chain once shipped a real bug: vim.lsp.enable() (loaded
# by FilePost) replays `doautoall <group> FileType`, and that nested trigger sets Vim's
# global did_filetype flag for the still-running chain — so the runtime filetypedetect
# handler's later `:setf` was a documented no-op and the FIRST file of every bare session
# opened with NO filetype (no highlighting, no LSP, no linter; later files fine). The
# probe can't see that through plugins — it is hermetic, FilePost loads nothing — so it
# SIMULATES the one relevant side effect: a `User FilePost` listener that replays a
# group-scoped FileType exactly like vim.lsp.enable does. If FilePost ever goes back to
# firing inside the read chain, that replay re-poisons did_filetype and the asserted
# `ft=lua` collapses to `ft=` on scenario B. (Fixtures are .lua for a filetype that is
# detected by name alone, no content sniffing.)
hdr "neovim User FilePost contract (nvim/ headless)"
if ! ((SCOPE_NVIM)); then
  skip "nvim FilePost contract (out of scope)"
elif have nvim; then
  fp_probe="$SANDBOX/nvim-filepost.lua"
  # The probe drives itself off the event loop rather than via `-c`: `-c` commands run
  # BEFORE VimEnter (:h VimEnter — it fires "after ... executing the -c cmd arguments"),
  # so reporting from a `-c` would sample the counter before readiness ever arrives and
  # report 0 on perfectly good code. vim.defer_fn lands strictly after startup, which is
  # also the ordering a real session has. Any :edit is deferred for the same reason —
  # done from `-c` it would run before readiness and test the wrong sequence.
  cat >"$fp_probe" <<'LUA'
vim.opt.runtimepath:prepend(vim.env.CORE_NVIM_DIR)
-- Count BEFORE requiring the module, so a FilePost emitted during startup is caught.
_G.filepost_count = 0
vim.api.nvim_create_autocmd("User", {
  pattern = "FilePost",
  callback = function()
    _G.filepost_count = _G.filepost_count + 1
  end,
})
-- Simulate the FileType-firing side effect of a real FilePost consumer: vim.lsp.enable()
-- replays `doautoall nvim.lsp.enable FileType` when called post-startup. The hermetic probe
-- loads no plugins, so without this replay the did_filetype poisoning path (see the header)
-- is invisible here and the ft assertion below would pass on broken code.
vim.api.nvim_create_augroup("ProbeFtReplay", { clear = true })
vim.api.nvim_create_autocmd("FileType", { group = "ProbeFtReplay", callback = function() end })
vim.api.nvim_create_autocmd("User", {
  pattern = "FilePost",
  callback = function()
    vim.cmd("doautoall ProbeFtReplay FileType")
  end,
})
local ok, err = pcall(require, "gerrrt.config.autocmds")
if not ok then
  io.stderr:write("require gerrrt.config.autocmds → " .. tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
vim.defer_fn(function()
  -- Scenario B only: open two real files AFTER startup. The second must not re-fire.
  local a, b = vim.env.CORE_FP_A, vim.env.CORE_FP_B
  local first_buf -- the FIRST real file's buffer: startup file (A) or first :edit (B)
  if a and a ~= "" then
    pcall(vim.cmd, "edit " .. vim.fn.fnameescape(a))
    first_buf = vim.api.nvim_get_current_buf()
    pcall(vim.cmd, "edit " .. vim.fn.fnameescape(b))
  else
    first_buf = vim.api.nvim_get_current_buf()
  end
  vim.defer_fn(function()
    -- Sampled AFTER the deferred FilePost tick, so this is the filetype the buffer is left
    -- with — `ft=` here means the first file of the session came up dead (see header).
    io.stdout:write(("filepost=%d ready=%s ft=%s\n"):format(
      _G.filepost_count, tostring(vim.g.startup_done), vim.bo[first_buf].filetype))
    vim.cmd("qa!")
  end, 200)
end, 200)
LUA
  fp_a="$SANDBOX/fp_a.lua"; printf 'return "alpha"\n' >"$fp_a"
  fp_b="$SANDBOX/fp_b.lua"; printf 'return "bravo"\n' >"$fp_b"
  fp_want='filepost=1 ready=true ft=lua'

  # A. nvim <file> — buffer is named before the readiness event arrives.
  fp_got_a=$(CORE_NVIM_DIR="$HERE/nvim" nvim --headless -u "$fp_probe" -i NONE -n "$fp_a" \
    </dev/null 2>/dev/null | tr -d '\r')
  # B. bare nvim, then open TWO files — readiness first; only the first file may fire.
  fp_got_b=$(CORE_NVIM_DIR="$HERE/nvim" CORE_FP_A="$fp_a" CORE_FP_B="$fp_b" \
    nvim --headless -u "$fp_probe" -i NONE -n \
    </dev/null 2>/dev/null | tr -d '\r')

  if [[ "$fp_got_a" == "$fp_want" ]]; then
    pass "FilePost fires exactly once when nvim starts with a file (filetype intact)"
  else
    fail "FilePost contract broken on 'nvim <file>' — want '$fp_want', got '$fp_got_a'"
  fi
  if [[ "$fp_got_b" == "$fp_want" ]]; then
    pass "FilePost fires exactly once on bare start + two :edits (no re-fire, filetype intact)"
  else
    fail "FilePost contract broken on bare-then-edit — want '$fp_want', got '$fp_got_b'"
  fi
else
  skip "nvim FilePost contract (nvim not installed — runs in CI)"
fi

# ── D4. Neovim LSP server registry (servers/init.lua, headless) ───────────────
# Section D requires every servers/* LEAF but deliberately SKIPS servers/init.lua, because it
# require()s blink.cmp — absent from that hermetic probe. That left the registry itself
# untested: the "*" wildcard capability registration, the per-server vim.lsp.config calls,
# the failed-module isolation, and which names actually get enabled could all regress while
# the leaf probe stayed green. It is the file that decides whether you have LSP at all, and
# it fans out to nine repos.
#
# Close it by stubbing the two things that made it untestable — blink.cmp (via package.preload)
# and the vim.lsp surface — then require the real module and assert what it registered. No
# plugins, no servers, no network. Also injects a deliberately broken module to prove one bad
# server file degrades to "that server is unconfigured" instead of taking the editor down.
hdr "neovim LSP server registry (servers/init.lua, headless)"
if ! ((SCOPE_NVIM)); then
  skip "nvim LSP registry (out of scope)"
elif have nvim; then
  reg_probe="$SANDBOX/nvim-registry.lua"
  cat >"$reg_probe" <<'LUA'
vim.opt.runtimepath:prepend(vim.env.CORE_NVIM_DIR)

-- Stub blink.cmp so the registry's capabilities call resolves without the plugin.
package.preload["blink.cmp"] = function()
  return { get_lsp_capabilities = function() return { STUB_CAPS = true } end }
end
-- Break ONE server module to prove failures are isolated, not fatal.
package.preload["gerrrt.servers.gopls"] = function()
  error("deliberate probe failure")
end

-- Pin the binary gate. binary_available() calls vim.fn.executable(), so without this the
-- enabled count would depend on which language servers happen to be installed on the host —
-- different locally vs each CI runner. CORE_REG_EXE drives both directions of the gate.
local exe_result = tonumber(vim.env.CORE_REG_EXE) or 1
local real_executable = vim.fn.executable
vim.fn.executable = function() return exe_result end

local registered, enabled = {}, {}
local real_config, real_enable = vim.lsp.config, vim.lsp.enable
vim.lsp.config = setmetatable({}, {
  __call = function(_, name, cfg) registered[name] = cfg end,
  -- binary_available() reads vim.lsp.config[name]; hand back what was registered.
  __index = function(_, name) return registered[name] end,
})
vim.lsp.enable = function(names)
  for _, n in ipairs(type(names) == "table" and names or { names }) do enabled[#enabled + 1] = n end
end

local ok, mod = pcall(require, "gerrrt.servers")

-- Exercise the read-only status() export (feeds :checkhealth gerrrt) WHILE the stubs are still
-- active, so the binary gate stays pinned and get_clients() is the real (empty, headless) surface.
-- Asserts the states health.lua renders: a broken override reports registered=false (NOT masked by
-- an upstream default); a good server reports registered+enabled+available; clients is a count.
local st_ok, st_gopls_reg, st_luals_reg, st_luals_en, st_luals_av, st_luals_cl = false
if ok and type(mod) == "table" and type(mod.status) == "function" then
  local oks, rows = pcall(mod.status)
  if oks and type(rows) == "table" then
    st_ok = true
    for _, s in ipairs(rows) do
      if s.name == "gopls" then st_gopls_reg = s.registered end
      if s.name == "lua_ls" then
        st_luals_reg, st_luals_en, st_luals_av, st_luals_cl = s.registered, s.enabled, s.available, s.clients
      end
    end
  end
end

vim.lsp.config, vim.lsp.enable = real_config, real_enable
vim.fn.executable = real_executable
if not ok then
  io.stderr:write("require gerrrt.servers → " .. tostring(mod) .. "\n")
  vim.cmd("cquit 1")
end

local n_servers, n_nocmd = 0, 0
for name, cfg in pairs(registered) do
  if name ~= "*" then
    n_servers = n_servers + 1
    -- binary_available() deliberately does NOT second-guess a config without a literal cmd list
    -- (nil, or a function launcher) — those bypass the executable check entirely.
    if type(cfg) ~= "table" or type(cfg.cmd) ~= "table" then n_nocmd = n_nocmd + 1 end
  end
end
-- The broken module registered nothing, so its cmd resolves to nil and it bypasses the gate too.
if registered["gopls"] == nil then n_nocmd = n_nocmd + 1 end
io.stdout:write(("wildcard=%s caps=%s servers=%d broken_registered=%s enabled=%d nocmd=%d"):format(
  tostring(registered["*"] ~= nil),
  tostring(registered["*"] and registered["*"].capabilities and registered["*"].capabilities.STUB_CAPS or false),
  n_servers,
  tostring(registered["gopls"] ~= nil),
  #enabled,
  n_nocmd))
io.stdout:write((" status_ok=%s st_gopls_reg=%s st_luals_reg=%s st_luals_en=%s st_luals_av=%s st_luals_cl=%s\n"):format(
  tostring(st_ok),
  tostring(st_gopls_reg),
  tostring(st_luals_reg),
  tostring(st_luals_en),
  tostring(st_luals_av),
  tostring(st_luals_cl)))
vim.cmd("qa!")
LUA
  reg_err="$SANDBOX/nvim-registry.err"
  _reg_field() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }

  # A. every binary present. The wildcard must carry the stubbed capabilities; the deliberately
  #    broken module must NOT be registered (isolated) while the module still completes; and every
  #    configured server must end up enabled — registered ones plus the broken one, which falls
  #    back to nvim-lspconfig's own defaults rather than disappearing.
  reg_a=$(CORE_NVIM_DIR="$HERE/nvim" CORE_REG_EXE=1 nvim --headless -u "$reg_probe" -i NONE -n \
    </dev/null 2>"$reg_err" | tr -d '\r')
  a_servers=$(_reg_field "$reg_a" servers); a_enabled=$(_reg_field "$reg_a" enabled)
  if [[ "$(_reg_field "$reg_a" wildcard)" == "true" && "$(_reg_field "$reg_a" caps)" == "true" \
        && "$(_reg_field "$reg_a" broken_registered)" == "false" \
        && -n "$a_servers" && "$a_enabled" -eq $((a_servers + 1)) ]]; then
    pass "LSP registry: wildcard caps set, broken module isolated, all $a_enabled servers enabled"
  else
    fail "LSP registry contract broken — got '$reg_a' (expected caps+wildcard true, broken_registered false, enabled = servers+1)"
    [[ -s "$reg_err" ]] && sed 's/^/    /' "$reg_err" >&2
  fi

  # status() export (feeds :checkhealth gerrrt). The broken gopls override must report
  # registered=false — the whole point of tracking it separately from vim.lsp.config[name], which
  # would resolve an upstream default and hide the failure. A good server (lua_ls) must report
  # registered + enabled + available, and clients must be a number (0 in this headless probe).
  if [[ "$(_reg_field "$reg_a" status_ok)" == "true" \
        && "$(_reg_field "$reg_a" st_gopls_reg)" == "false" \
        && "$(_reg_field "$reg_a" st_luals_reg)" == "true" \
        && "$(_reg_field "$reg_a" st_luals_en)" == "true" \
        && "$(_reg_field "$reg_a" st_luals_av)" == "true" \
        && "$(_reg_field "$reg_a" st_luals_cl)" == "0" ]]; then
    pass "LSP registry: status() separates registered/enabled/available (broken override → registered=false)"
  else
    fail "LSP registry status() contract broken — got '$reg_a' (expected status_ok, gopls reg=false, lua_ls reg/en/av=true, clients=0)"
  fi

  # B. no binary present. Only configs that bypass the gate by design may remain — those with no
  #    literal `cmd` list, which binary_available() deliberately does not second-guess. Asserted
  #    against the probe's own count rather than a magic number, so adding a server can't silently
  #    invalidate it. Anything more would mean a missing binary gets enabled and then respawn-errors
  #    on every matching buffer, which is exactly what that guard exists to prevent.
  reg_b=$(CORE_NVIM_DIR="$HERE/nvim" CORE_REG_EXE=0 nvim --headless -u "$reg_probe" -i NONE -n \
    </dev/null 2>/dev/null | tr -d '\r')
  b_enabled=$(_reg_field "$reg_b" enabled); b_nocmd=$(_reg_field "$reg_b" nocmd)
  if [[ -n "$b_enabled" && "$b_enabled" == "$b_nocmd" ]]; then
    pass "LSP registry: binary gate enables only the $b_nocmd cmd-less configs when no binary exists"
  else
    fail "LSP registry binary gate broken — got '$reg_b' (expected enabled == nocmd)"
  fi
else
  skip "nvim LSP registry (nvim not installed — runs in CI)"
fi

# ── E. CI path classifier (scripts/ci-classify.sh) ────────────────────────────
# ci.yml's change-detection picks which gates run per push. That logic now lives in
# scripts/ci-classify.sh (pulled out of the workflow YAML so it can be linted + tested);
# this asserts the contract the workflow depends on: known paths map to the right gates,
# the __ALL__ sentinel runs everything, and — the regression that matters — an
# UNRECOGNISED top-level path FAILS CLOSED to the full run instead of silently skipping
# a gate on the nine-repo fan-out. Pure bash, so it runs even where zsh/nvim are absent.
# ── failing-gate detail (scripts/lib/common.sh :: fail_detail) ────────────────
# WHY THIS IS TESTED. The audit used to discard every linter's own report, so a red CI run
# named a gate and nothing else — "✗ markdownlint reported issues", no rule, no file, no
# line — and CI is exactly where you cannot re-run the tool by hand (#456). fail_detail is
# what closes that, which makes its two easy-to-break properties worth pinning: it must go
# to STDERR (stdout carries the --json summary object, and polluting it would trade one
# broken output for another), and it must CAP, or a pathological run buries the summary it
# is meant to explain. The herestrings inside it are the #459 SIGPIPE trap; a "tidy-up"
# back to `printf | head` reintroduces it, so the cap assertion doubles as that guard.
hdr "failing-gate detail (fail_detail)"
_fdt_out="$(fail_detail "one
two" 2>/dev/null)"
if [[ -z "$_fdt_out" ]]; then pass "fail_detail: writes nothing to stdout (--json stays parseable)"; else fail "fail_detail: leaked to stdout: $_fdt_out"; fi

_fdt_err="$(fail_detail "alpha
beta" 2>&1 >/dev/null)"
if grep -q '^    alpha$' <<<"$_fdt_err" && grep -q '^    beta$' <<<"$_fdt_err"; then
  pass "fail_detail: writes the tool's report to stderr, indented"
else fail "fail_detail: stderr was [$_fdt_err]"; fi

_fdt_err="$(fail_detail "" 2>&1 >/dev/null)"
if [[ -z "$_fdt_err" ]]; then pass "fail_detail: empty output is a no-op"; else fail "fail_detail: emitted [$_fdt_err] for empty input"; fi

# cap: 60 lines with a limit of 5 → 5 shown plus one "… N more" line, and the count right
_fdt_many="$(seq 1 60)"
_fdt_err="$(CORE_FAIL_DETAIL_LINES=5 fail_detail "$_fdt_many" 2>&1 >/dev/null)"
_fdt_n="$(wc -l <<<"$_fdt_err" | tr -d ' ')"
if [[ "$_fdt_n" == 6 ]] && grep -q '… 55 more line' <<<"$_fdt_err"; then
  pass "fail_detail: caps at CORE_FAIL_DETAIL_LINES and reports the remainder"
else fail "fail_detail: cap produced $_fdt_n line(s): $(head -3 <<<"$_fdt_err")"; fi

# ── pipefail SIGPIPE scanner (scripts/lib/common.sh :: _core_pipefail_hits) ───
# WHY THIS IS TESTED. audit-core.sh §5d exists because this repo has hit the pipefail +
# SIGPIPE trap three times — a 4000-line `git show` into `grep -q`, `ldd --version |
# grep -qi musl`, and nvim-reachability.sh inventing orphans on main (#458, #459). A gate
# for a bug that has recurred that often is only worth having if it actually fires, and
# probe-testing this one already caught a real defect: it used to scan any file that merely
# MENTIONED pipefail in a comment, which is the false-positive class that gets a gate
# switched off. Both halves are pinned below — what it catches AND what it must ignore.
if have git; then
  hdr "pipefail SIGPIPE scanner (_core_pipefail_hits)"
  _pfd="$SANDBOX/pipefail"
  mkdir -p "$_pfd"
  _pf_write() { printf '%s\n' "$2" >"$_pfd/$1"; }   # _pf_write <name> <body>
  # THE PIPE IS ASSEMBLED, NOT WRITTEN LITERALLY. This file sets `pipefail`, so §5d scans
  # it — and a file whose job is to TEST the banned shape necessarily contains it, which
  # made the gate flag its own fixtures on the first run. Keeping the literal out of this
  # source is the honest fix: the fixture written to disk is byte-identical to the real
  # hazard, so the assertions still exercise the true pattern. The alternative — an
  # inline "allow" marker in the scanner — was rejected as an escape hatch that invites
  # silencing a real finding, on a gate that exists because this bug keeps coming back.
  _pf_p='|'

  _pf_write grepq.sh "set -euo pipefail
printf '%s' \"\$big\" $_pf_p grep -q needle"
  if [[ "$(_core_pipefail_hits "$_pfd/grepq.sh")" == 2 ]]; then pass "pipefail scan: catches a printf piped into grep -q"; else fail "pipefail scan: missed a printf piped into grep -q"; fi

  # FLAG ORDER must not matter. The regex used to require `q` to be the LAST letter of the
  # cluster, so `-q` and `-xq` were caught while `-qx` and `-Eqi` walked past — identical
  # hazard, different spelling. That blind spot was hiding a live one in ci-pr-link.sh's
  # No-Issue probe (`-Eqi`), where a body over the pipe buffer would have failed a
  # correctly-exempt PR. Pin every spelling so the gate cannot go half-blind again (#501).
  _pf_write grepqx.sh "set -euo pipefail
printf '%s' \"\$big\" $_pf_p grep -qx needle"
  if [[ "$(_core_pipefail_hits "$_pfd/grepqx.sh")" == 2 ]]; then pass "pipefail scan: catches grep -qx (q not last in the cluster)"; else fail "pipefail scan: missed grep -qx — the regex still requires q to be last"; fi

  _pf_write grepeqi.sh "set -euo pipefail
printf '%s' \"\$big\" $_pf_p grep -Eqi needle"
  if [[ "$(_core_pipefail_hits "$_pfd/grepeqi.sh")" == 2 ]]; then pass "pipefail scan: catches grep -Eqi (the real ci-pr-link.sh shape)"; else fail "pipefail scan: missed grep -Eqi"; fi

  _pf_write grepxq.sh "set -euo pipefail
printf '%s' \"\$big\" $_pf_p grep -xq needle"
  if [[ "$(_core_pipefail_hits "$_pfd/grepxq.sh")" == 2 ]]; then pass "pipefail scan: still catches grep -xq (q last, the original form)"; else fail "pipefail scan: regressed on grep -xq"; fi

  # The widened cluster must not swallow a grep with NO q at all — that has no early exit.
  _pf_write grepnoq.sh "set -euo pipefail
printf '%s' \"\$big\" $_pf_p grep -Ei needle"
  if [[ -z "$(_core_pipefail_hits "$_pfd/grepnoq.sh")" ]]; then pass "pipefail scan: a grep with no quiet flag is not a finding"; else fail "pipefail scan: widened regex now flags a non-quiet grep"; fi

  _pf_write head.sh "set -euo pipefail
echo \"\$v\" $_pf_p head -n1"
  if [[ "$(_core_pipefail_hits "$_pfd/head.sh")" == 2 ]]; then pass "pipefail scan: catches an echo piped into head"; else fail "pipefail scan: missed an echo piped into head"; fi

  _pf_write awkexit.sh "set -euo pipefail
printf '%s' \"\$v\" $_pf_p awk '/x/ { print; exit }'"
  if [[ "$(_core_pipefail_hits "$_pfd/awkexit.sh")" == 2 ]]; then pass "pipefail scan: catches a printf piped into awk with exit"; else fail "pipefail scan: missed a printf piped into awk with exit"; fi

  # the herestring form is the FIX — it must never be flagged, or the gate punishes the cure
  _pf_write safe.sh 'set -euo pipefail
grep -q needle <<<"$big"'
  if [[ -z "$(_core_pipefail_hits "$_pfd/safe.sh")" ]]; then pass "pipefail scan: a herestring is not a finding"; else fail "pipefail scan: flagged the herestring fix"; fi

  # writing ABOUT the hazard must not trip it — this very repo documents it in comments
  _pf_write comment.sh "set -euo pipefail
# printf '%s' \"\$x\" $_pf_p grep -q foo is the trap this gate exists to catch
grep -q foo <<<\"\$x\""
  if [[ -z "$(_core_pipefail_hits "$_pfd/comment.sh")" ]]; then pass "pipefail scan: a comment describing the hazard is not a finding"; else fail "pipefail scan: flagged a comment"; fi

  # no pipefail set → the shape is harmless, and flagging it is the false positive that
  # gets a gate disabled. (The word appearing in prose must not count as enabling it.)
  _pf_write nopipefail.sh "set -eu
# this file only mentions pipefail in a comment
printf '%s' \"\$v\" $_pf_p grep -q needle"
  if [[ -z "$(_core_pipefail_hits "$_pfd/nopipefail.sh")" ]]; then pass "pipefail scan: a file that never enables pipefail is not a finding"; else fail "pipefail scan: flagged a file that never enables pipefail"; fi

  # pipefail enabled in a SPLIT form — an earlier version anchored on the first option
  # token and skipped these entirely, so the gate silently permitted the hazard
  _pf_write splitset.sh "set -e -o pipefail
printf '%s' \"\$v\" $_pf_p grep -q needle"
  if [[ "$(_core_pipefail_hits "$_pfd/splitset.sh")" == 2 ]]; then pass "pipefail scan: sees set -e -o pipefail"; else fail "pipefail scan: missed the split set form"; fi

  _pf_write longset.sh "set -o errexit -o pipefail
printf '%s' \"\$v\" $_pf_p grep -q needle"
  if [[ "$(_core_pipefail_hits "$_pfd/longset.sh")" == 2 ]]; then pass "pipefail scan: sees set -o errexit -o pipefail"; else fail "pipefail scan: missed the long-option set form"; fi

  # quiet grep has more spellings than -q
  _pf_write grepeq.sh "set -euo pipefail
printf '%s' \"\$v\" $_pf_p grep -E -q needle"
  if [[ "$(_core_pipefail_hits "$_pfd/grepeq.sh")" == 2 ]]; then pass "pipefail scan: catches a separated quiet flag"; else fail "pipefail scan: missed grep -E -q"; fi

  _pf_write grepquiet.sh "set -euo pipefail
printf '%s' \"\$v\" $_pf_p grep --quiet needle"
  if [[ "$(_core_pipefail_hits "$_pfd/grepquiet.sh")" == 2 ]]; then pass "pipefail scan: catches --quiet"; else fail "pipefail scan: missed grep --quiet"; fi

  # awk that merely PRINTS the word exit does not exit early — flagging it would be an
  # invented finding, the other way this gate loses trust
  _pf_write awkstring.sh "set -euo pipefail
printf '%s' \"\$v\" $_pf_p awk '{ print \"exit\" }'"
  if [[ -z "$(_core_pipefail_hits "$_pfd/awkstring.sh")" ]]; then pass "pipefail scan: awk printing the word exit is not a finding"; else fail "pipefail scan: flagged awk that never exits"; fi

  # a file producer is deliberately out of scope (~15 legitimate instances in-tree)
  _pf_write fileproducer.sh 'set -euo pipefail
sed -n "s/^x=//p" "$f" | head -n1'
  if [[ -z "$(_core_pipefail_hits "$_pfd/fileproducer.sh")" ]]; then pass "pipefail scan: a file producer stays out of scope"; else fail "pipefail scan: flagged sed <file> | head"; fi

  # and the gate must not flag the library that defines it
  if [[ -z "$(_core_pipefail_hits "$HERE/scripts/lib/common.sh")" ]]; then pass "pipefail scan: does not flag its own definition"; else fail "pipefail scan: flagged common.sh itself"; fi
fi

# ── leaked-RETURN-trap scanner (scripts/lib/common.sh :: _core_return_trap_hits) ───
# WHY THIS IS TESTED. audit-core.sh §5e is the ONLY gate anywhere that can see this bug.
# The broken line is valid bash, so the lint and syntax sections both pass it; and
# bootstrap-test.yml only ever runs --links-only, so the code where it detonates is executed
# by nothing (#512, #461). A gate that is the sole line of defence, for a bug that has
# already shipped green in two repos, is worth proving fires. Probe-testing it while it was
# written is what found the line-start anchor: the version this repo nearly shipped catches
# ONE of the four broken shapes below, and the one it misses is the likeliest of them.
#
# Both halves are pinned — what it catches AND what it must ignore. The second half is not
# padding. The false-positive class is what gets a gate switched off, and dotfiles-Debian's
# own fix carries three comment lines naming the signal directly above its corrected traps:
# a scanner without the comment filter would red the repo that FIXED the bug.
#
# THE SIGNAL NAME IS ASSEMBLED, NOT WRITTEN LITERALLY — the same move, for the same reason,
# as _pf_p in the pipefail block above. §5e scans this file, and a file whose job is to test
# the banned shape necessarily contains it; the first run flagged eight of its own lines.
# Keeping the literal out of this source is the honest fix: the fixture written to disk is
# byte-identical to the real hazard, so the assertions still exercise the true pattern. An
# inline "allow" marker in the scanner was rejected for the same reason it was there — an
# escape hatch invites silencing a real finding. The assertion MESSAGES are worded around
# it too, which is why none of them says the shape out loud.
if have git; then
  hdr "leaked-RETURN-trap scanner (_core_return_trap_hits)"
  _rtd="$SANDBOX/returntrap"
  mkdir -p "$_rtd"
  _rt_write() { printf '%s\n' "$2" >"$_rtd/$1"; }   # _rt_write <name> <body>
  _rt_s='RETURN'
  # The handler body is a placeholder, not a real cleanup: what is under test is the signal
  # operand and the disarm, so a literal `rm -rf` in a fixture would be risk for no gain.

  # ── the four broken shapes ──
  # The ONE-LINE BODY is first because it is the shape a line-start anchor misses, and it is
  # how this is most often written: the whole helper fits on one line, so the handler does too.
  _rt_write oneline.sh "#!/usr/bin/env bash
f() { trap CLEAN $_rt_s; }"
  if [[ "$(_core_return_trap_hits "$_rtd/oneline.sh")" == 2 ]]; then pass "RETURN scan: catches a one-line function body"; else fail "RETURN scan: missed the one-line function body — is the pattern anchored to line-start again?"; fi

  _rt_write ownline.sh "#!/usr/bin/env bash
f() {
  trap CLEAN $_rt_s
}"
  if [[ "$(_core_return_trap_hits "$_rtd/ownline.sh")" == 3 ]]; then pass "RETURN scan: catches the dotfiles-Debian#2 shape (handler on its own line)"; else fail "RETURN scan: missed the own-line shape"; fi

  # A TRAILING COMMENT must not hide it. This is why the signal is matched as a TOKEN rather
  # than as the last word on the line — anchoring to end-of-line waves this straight through.
  _rt_write trailing.sh "#!/usr/bin/env bash
f() { trap CLEAN $_rt_s  # cleanup
}"
  if [[ "$(_core_return_trap_hits "$_rtd/trailing.sh")" == 2 ]]; then pass "RETURN scan: catches a handler with a trailing comment"; else fail "RETURN scan: missed a trailing comment — is the signal anchored to end-of-line again?"; fi

  # TWO SIGNALS leak in exactly the same way, and here the signal is not the last operand.
  _rt_write multisig.sh "#!/usr/bin/env bash
f() { trap CLEAN $_rt_s EXIT; }"
  if [[ "$(_core_return_trap_hits "$_rtd/multisig.sh")" == 2 ]]; then pass "RETURN scan: catches a second signal after the first"; else fail "RETURN scan: missed the two-signal form"; fi

  # ── what it must NOT flag ──
  # The disarming form is the FIX. Flagging it would punish the cure and leave no way to
  # write a correct one at all.
  _rt_write fixed.sh "#!/usr/bin/env bash
f() { trap \"trap - $_rt_s; CLEAN\" $_rt_s; }"
  if [[ -z "$(_core_return_trap_hits "$_rtd/fixed.sh")" ]]; then pass "RETURN scan: a self-disarming body is not a finding"; else fail "RETURN scan: flagged the disarming fix"; fi

  # Writing ABOUT the hazard must not trip it — this repo now documents it in three places,
  # and so does the fix in dotfiles-Debian.
  _rt_write comment.sh "#!/usr/bin/env bash
# trap CLEAN $_rt_s is the shape this gate exists to catch
f() { trap \"trap - $_rt_s; CLEAN\" $_rt_s; }"
  if [[ -z "$(_core_return_trap_hits "$_rtd/comment.sh")" ]]; then pass "RETURN scan: a comment describing the hazard is not a finding"; else fail "RETURN scan: flagged a comment"; fi

  # Every OTHER signal is fine — only this one has the leaking-slot semantics. An EXIT
  # handler inside a function is ordinary, and this repo uses several.
  _rt_write exitonly.sh '#!/usr/bin/env bash
f() { trap CLEAN EXIT; }'
  if [[ -z "$(_core_return_trap_hits "$_rtd/exitonly.sh")" ]]; then pass "RETURN scan: an EXIT handler is not a finding"; else fail "RETURN scan: flagged an EXIT handler"; fi

  # The word in prose, or as part of a longer identifier, is not a signal operand.
  _rt_write prose.sh "#!/usr/bin/env bash
f() { echo \"check the $_rt_s value\"; }"
  if [[ -z "$(_core_return_trap_hits "$_rtd/prose.sh")" ]]; then pass "RETURN scan: the bare word in prose is not a finding"; else fail "RETURN scan: flagged the word where no handler is armed"; fi

  # and the gate must not flag the library that defines it
  if [[ -z "$(_core_return_trap_hits "$HERE/scripts/lib/common.sh")" ]]; then pass "RETURN scan: does not flag its own definition"; else fail "RETURN scan: flagged common.sh itself"; fi

  # nor this file, whose fixtures are the banned shape by construction — the assembly above
  # is what makes that true, and a regression in it must fail HERE rather than in §5e
  if [[ -z "$(_core_return_trap_hits "$HERE/scripts/test-core.sh")" ]]; then pass "RETURN scan: does not flag its own fixtures (the signal name stays assembled)"; else fail "RETURN scan: this file now spells the banned shape literally — keep the name in \$_rt_s"; fi

  # ── SHELLCHECK_OPTS parity across the two workflows that lint the same file ──
  # lint-call.yml and bootstrap-test.yml BOTH run shellcheck over an OS repo's bootstrap.sh.
  # For a long time only the first set the fleet's curated exclusions, so the same commit
  # could be green in `lint` and red in `bootstrap` — with an error naming a rule the fleet
  # had documented as excluded (#517). SC2088 is the one that fires, because a bootstrap's
  # user-facing strings are full of ~/.zshrc and ~/.config.
  #
  # It is not shareable state: GitHub has no way to import an env value from one workflow
  # into another, so the value is authored twice by necessity. This is the assertion that
  # keeps the two copies equal — the same shape as the os-repos.txt fallback-array check
  # above, and for the same reason: a literal duplicated across files with nothing comparing
  # them is exactly the N-way drift the reusable workflows exist to end.
  # The multi-value test below is `== *$'\n'*`, NOT `$(wc -l) != 1`: BSD wc pads its count
  # with leading spaces ("       1"), so the string compare is true on macOS and false on
  # Linux — this assertion shipped with exactly that bug and the macOS leg caught it. A
  # bash-native newline test has no such divergence, and needs no external tool.
  _sco_of() { # _sco_of <workflow> → the SHELLCHECK_OPTS value, or empty
    sed -n 's/^[[:space:]]*SHELLCHECK_OPTS:[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$1" 2>/dev/null | sort -u
  }
  _sco_lc="$(_sco_of "$HERE/.github/workflows/lint-call.yml")"
  _sco_bt="$(_sco_of "$HERE/.github/workflows/bootstrap-test.yml")"
  if [[ -z "$_sco_lc" || -z "$_sco_bt" ]]; then
    fail "SHELLCHECK_OPTS parity: could not read the value from both workflows (lint-call='$_sco_lc' bootstrap-test='$_sco_bt')"
  elif [[ "$_sco_lc" == *$'\n'* ]]; then
    fail "SHELLCHECK_OPTS parity: lint-call.yml carries more than one distinct value — the steps disagree with each other"
  elif [[ "$_sco_lc" != "$_sco_bt" ]]; then
    fail "SHELLCHECK_OPTS parity: lint-call.yml has '$_sco_lc' but bootstrap-test.yml has '$_sco_bt' — the same bootstrap.sh would be green in one gate and red in the other (#517)"
  else
    pass "SHELLCHECK_OPTS parity: both gates that lint bootstrap.sh use the same exclusions"
  fi

  # ── ONE definition, and it must stay one ──
  # The fleet-facing leg in .github/workflows/lint-call.yml gates the nine caller repos with
  # the SAME rule §5e applies here. It first shipped with the pattern inlined (#552) while
  # the helper landed separately (#555), so for one release the rule existed twice and only
  # the copy below was tested — the fleet-facing half was the one that could drift unseen.
  # These two assertions are what stop that from recurring: the workflow must CALL the
  # helper, and must not carry a second copy of the expression. Cheap, and it fails in the
  # suite rather than the next time someone corrects one copy and not the other.
  _rt_wf="$HERE/.github/workflows/lint-call.yml"
  if [[ ! -r "$_rt_wf" ]]; then
    skip "RETURN scan: lint-call.yml not readable (partial checkout?)"
  elif ! grep -q '_core_return_trap_hits' "$_rt_wf"; then
    fail "RETURN scan: lint-call.yml no longer calls _core_return_trap_hits — the fleet gate has drifted off the shared definition"
  elif grep -qE 'trap\[\[:space:\]\]' "$_rt_wf"; then
    fail "RETURN scan: lint-call.yml carries its own copy of the pattern — call the helper instead, so the rule has one definition"
  else
    pass "RETURN scan: the fleet gate (lint-call.yml) calls the helper rather than copying the pattern"
  fi
fi
# ── Core-owned block scanner (scripts/lib/common.sh :: _core_owned_block_hits) ─────
# WHY THIS IS TESTED. This scanner is the ONLY thing standing between the fleet and the
# defect it was written for coming straight back. Seven OS repos each hand-maintained the
# direnv/gh/uv/ty init block and six the WSL probe; by the time anyone counted, the copies
# had drifted into THREE variants of one block, and two repos silently lacked half the
# tools. Nothing could see it: the duplicate is valid zsh, `zsh -n` passes it, the shell
# keeps working, and audit-core.sh §5c looks the other way down the boundary (OS-specifics
# leaking INTO Core, not portable logic stranded outside it). It was found by reading two
# layers side by side, which is not a gate (#449).
#
# Both halves are pinned, as in the RETURN block above, and for the same reason: the
# false-positive class is what gets a gate switched off. Here that risk is sharper than
# usual, because an OS layer's legitimate business — hooking a tool that exists on ONE OS —
# looks superficially identical to the thing being banned. Every ignore case below is a
# shape a real OS layer either has today or will write tomorrow.
#
# NOTE the inverted self-reference rule vs the two scanners above: those must not flag their
# own definition or this file. THIS one must not flag common.sh (the pattern table spells the
# kernel version file as a character class precisely so it doesn't) but MUST flag Core's two
# owning modules — that is the inverse assertion at the end of this block, and it is the
# only direction that catches Core quietly losing a block the fleet has been made to delete.
hdr "Core-owned block scanner (_core_owned_block_hits)"
_obd="$SANDBOX/ownedblock"
mkdir -p "$_obd"
_ob_write() { printf '%s\n' "$2" >"$_obd/$1"; }   # _ob_write <name> <body>
# _ob_is <file> <expected>  — the scanner's full output must equal <expected> exactly.
# Exact, not "contains": a rule that fires on the right line for the wrong reason, or fires
# twice, is a finding the operator has to triage, and this gate's whole value is that its
# output is a delete-list.
_ob_is() { # _ob_is <label> <file> <expected>
  local got
  got="$(_core_owned_block_hits "$_obd/$2")"
  if [[ "$got" == "$3" ]]; then
    pass "owned-block scan: $1"
  else
    fail "owned-block scan: $1 (got '${got//$'\n'/, }', want '${3//$'\n'/, }')"
  fi
}

# ── what it must catch: the cached arm, one fixture per rule ──
_ob_write direnv.zsh "# os layer
_cache_eval direnv direnv hook zsh"
_ob_is "the direnv hook is a finding" direnv.zsh "2:direnv-hook"

_ob_write gh.zsh "# os layer
_cache_eval gh gh completion -s zsh"
_ob_is "the gh completion is a finding" gh.zsh "2:gh-completion"

_ob_write uv.zsh "# os layer
_cache_eval uv uv generate-shell-completion zsh"
_ob_is "the uv completion is a finding" uv.zsh "2:uv-completion"

_ob_write ty.zsh "# os layer
_cache_eval ty ty generate-shell-completion zsh"
_ob_is "the ty completion is a finding" ty.zsh "2:ty-completion"

# THE EAGER FALLBACK ARM, which is half of every real copy. All seven os/*.zsh wrapped the
# block in `if (( \$+functions[_cache_eval] )); then … else <bare eval> fi`, so a scanner
# that only knew the _cache_eval shape would wave through the else-branch of every one of
# them and report the repo clean after a half-deletion.
_ob_write fallback.zsh "# os layer
command -v gh >/dev/null 2>&1 && eval \"\$(gh completion -s zsh 2>/dev/null)\""
_ob_is "the bare-eval fallback arm is a finding too" fallback.zsh "2:gh-completion"

# ── what it must catch: the WSL probe, both halves ──
_ob_write wslproc.zsh "# os layer
elif [[ -r /proc/version ]]; then"
_ob_is "reading the kernel version file is a finding" wslproc.zsh "2:wsl-detect"

_ob_write wslvar.zsh "# os layer
_IS_WSL=0"
_ob_is "the hand-rolled _IS_WSL flag is a finding" wslvar.zsh "2:wsl-detect"

# ── the whole block, as an OS layer actually writes it ──
# Sorted numerically, deduped, one entry per offending line: this output IS the delete-list
# the fan-out PRs work from, so its shape is part of the contract.
_ob_write full.zsh "# ── Detect WSL once ──
_IS_WSL=0
if [[ -n \"\${WSL_DISTRO_NAME:-}\" ]]; then
  _IS_WSL=1
elif [[ -r /proc/version ]]; then
  _pv=\"\$(</proc/version)\"; _pv=\${_pv:l}
  [[ \"\$_pv\" == *microsoft* || \"\$_pv\" == *wsl* ]] && _IS_WSL=1
fi
if (( \$+functions[_cache_eval] )); then
  _cache_eval direnv direnv hook zsh
  _cache_eval gh gh completion -s zsh
else
  command -v direnv >/dev/null 2>&1 && eval \"\$(direnv hook zsh)\"
fi"
_ob_is "a real os-layer block reports every line, sorted and deduped" full.zsh \
  "2:wsl-detect
4:wsl-detect
5:wsl-detect
6:wsl-detect
7:wsl-detect
10:direnv-hook
11:gh-completion
13:direnv-hook"

# ── what it must NOT catch ──
# The pointer comment the fan-out PRs replace the deleted block with. If this fires, the
# gate reds the repo that made the fix — the failure mode that switches a gate off.
_ob_write comment.zsh "# Deleted: direnv hook zsh is Core's now (core/zsh/00-tools.zsh), as is the
# WSL probe (_core_is_wsl); this file read /proc/version itself until #449."
_ob_is "the pointer comment replacing a deleted block is not a finding" comment.zsh ""

# AN OS-ONLY TOOL'S HOOK IS THE OS LAYER'S BUSINESS — the entire point of the band. This is
# the ignore case that matters most: it is the shape the fix's own comment tells authors to
# keep writing, and the one a tool-name-based pattern would have destroyed.
_ob_write osonly.zsh "# os layer
_cache_eval brew brew shellenv
_cache_eval pyenv pyenv init -"
_ob_is "an OS-only tool's own hook is not a finding" osonly.zsh ""

# Using a tool is not registering its completion.
_ob_write verbs.zsh "alias dv=direnv
direnv allow
gh pr create --fill
uv sync"
_ob_is "calling the tools is not a finding" verbs.zsh ""

# Reading the distro NAME is a different use from re-implementing the DETECTION — a prompt
# segment, a window title, a hostname. Only the latter is Core's, which is why the rule keys
# on the version file and the flag rather than on the env var.
_ob_write distroname.zsh "[[ -n \${WSL_DISTRO_NAME:-} ]] && print -r -- \"\$WSL_DISTRO_NAME\""
_ob_is "reading the distro name is not a finding" distroname.zsh ""

# THE FIX ITSELF MUST NEVER BE A FINDING.
_ob_write fixed.zsh "if _core_is_wsl; then
  alias open='explorer.exe'
fi"
_ob_is "calling Core's _core_is_wsl is not a finding" fixed.zsh ""

# and the gate must not flag the library that defines it (see the character-class note there)
if [[ -z "$(_core_owned_block_hits "$HERE/scripts/lib/common.sh")" ]]; then
  pass "owned-block scan: does not flag its own definition"
else
  fail "owned-block scan: flagged common.sh itself — the rule table now spells a pattern it defines"
fi

# ── the INVERSE assertion: Core must still carry what it makes the fleet delete ──
# This is this gate's counterpart to §5e, and the reason there is deliberately no
# audit-core.sh section calling the scanner: Core's own tree matches every pattern, which is
# the point. A gate that forces nine repos to delete a block Core has quietly lost is worse
# than no gate — the niceties simply go silent everywhere at once, with every repo green.
# Keyed on the RULE IDS, not on a list of files: #579 moved the three completion generators
# from 45-plugins.zsh to 00-tools.zsh, and a per-file assertion reported that as Core having
# LOST a block it still carries. What matters is that every rule the fleet is gated on is
# provided somewhere in Core, so ask exactly that.
_ob_core_ok=1
_ob_hits="$(for _obf in "$HERE"/zsh/*.zsh; do _core_owned_block_hits "$_obf"; done | sed 's/^[0-9]*://' | sort -u)"
for _obr in direnv-hook gh-completion uv-completion ty-completion wsl-detect; do
  grep -qx "$_obr" <<<"$_ob_hits" || { _ob_core_ok=0; printf '    missing Core-side block: %s\n' "$_obr" >&2; }
done
unset _ob_hits _obr
if (( _ob_core_ok )); then
  pass "owned-block scan: Core still carries the blocks it makes the fleet drop"
else
  fail "owned-block scan: Core no longer carries a block the fleet is gated on — the fleet gate is now making nine repos delete a feature nobody provides"
fi
unset _ob_core_ok _obf

# ── the fleet itself, when it is checked out ──
# The direct regression signal, and the only assertion here that watches the real defect
# rather than a fixture. SKIPs when a sibling clone is absent (CI, a partial checkout), the
# same graceful degradation scripts/fleet-drift.sh uses — a missing repo is not a failure.
# EXPECTED TO SKIP OR FAIL until the fan-out lands: the copies are still there on the day
# Core takes the blocks over, which is exactly why the lint leg ships advisory (#449).
_ob_fleet_seen=0 _ob_fleet_dirty=""
# Siblings of this repo, the layout every fleet script assumes (see scripts/sync-core.sh).
_ob_root="$(cd "$HERE/.." && pwd)"
# The fleet comes from scripts/os-repos.txt via load_os_repos (#669). It used to be a
# hand-typed list of SEVEN of the nine names right here — dotfiles-Defense and
# dotfiles-Offense were silently never scanned, in the very file that asserted the other
# three copies of this list agreed. A fourth copy nobody was policing is the argument for
# having no copies.
_ob_fleet=1
load_os_repos || _ob_fleet=0
# Guarded rather than looped-over-empty: "${CORE_OS_REPOS[@]}" on an empty array trips
# `set -u` on bash <= 4.3, and this file runs on macOS's bash 3.2.
if ((_ob_fleet)); then
  for _obr in "${CORE_OS_REPOS[@]}"; do
    _obp="$(resolve_repo_dir "$_ob_root" "$_obr" 2>/dev/null)" || continue
    [[ -n "$_obp" && -d "$_obp" ]] || continue
    for _obf in "$_obp"/os/*.zsh; do
      [[ -f "$_obf" ]] || continue
      _ob_fleet_seen=$((_ob_fleet_seen + 1))
      [[ -z "$(_core_owned_block_hits "$_obf")" ]] || _ob_fleet_dirty="$_ob_fleet_dirty ${_obr}"
    done
  done
fi
if (( ! _ob_fleet )); then
  skip "owned-block scan: $CORE_OS_REPOS_ERR (fleet regression check)"
elif (( _ob_fleet_seen == 0 )); then
  skip "owned-block scan: no sibling OS repo checked out (fleet regression check)"
elif [[ -n "$_ob_fleet_dirty" ]]; then
  skip "owned-block scan: fan-out pending —$_ob_fleet_dirty still carry a Core-owned block (#449 step 7)"
else
  pass "owned-block scan: all $_ob_fleet_seen checked-out os layers are free of Core-owned blocks"
fi
unset _ob_fleet_seen _ob_fleet_dirty _ob_fleet _ob_root _obr _obp _obf

# ── ONE definition, and it must stay one (same contract as the RETURN leg above) ──
_ob_wf="$HERE/.github/workflows/lint-call.yml"
if [[ ! -r "$_ob_wf" ]]; then
  skip "owned-block scan: lint-call.yml not readable (partial checkout?)"
elif ! grep -q '_core_owned_block_hits' "$_ob_wf"; then
  fail "owned-block scan: lint-call.yml no longer calls _core_owned_block_hits — the fleet gate has drifted off the shared definition"
elif grep -qE 'generate-shell-completion|hook\[\[:space:\]\]' "$_ob_wf"; then
  fail "owned-block scan: lint-call.yml carries its own copy of the patterns — call the helper instead, so the rule has one definition"
else
  pass "owned-block scan: the fleet gate (lint-call.yml) calls the helper rather than copying the patterns"
fi
unset _ob_wf


# ── leftover conflict markers (scripts/lib/common.sh :: _core_conflict_marker_hits) ──
# Drives audit-core.sh §5h. Two properties have to hold at once and they pull against each
# other, which is why both directions are pinned rather than just the firing one:
#   • it FIRES on every marker that names a ref, including a lone base marker with no
#     partners — the exact shape bcdd7dd (#650) committed and that nothing noticed
#   • it stays SILENT on a bare row of seven `=`, which is also a setext H1 underline that
#     .markdownlint.jsonc permits (MD003 defaults to `consistent`, not `atx`)
#
# THE FIRST VERSION OF THIS MATCHER FAILED OPEN and these fixtures are what caught it. `|` is
# ERE's alternation operator, so a literal row of seven pipes in the pattern read as eight
# EMPTY alternatives and the scanner reported NOTHING, on any input — a green gate that
# checked nothing. A firing-only test would have gone green on the broken version too,
# because the broken version was silent on the clean fixtures as well.
#
# Fixtures are BUILT, never typed: every marker below is assembled with printf, so this file
# does not itself contain the thing it tests. It is tracked, §5h scans every tracked file, and
# a literal fixture here would make the gate report its own test suite. They are written into
# $SANDBOX, which is untracked, so the scanner never sees them at all — that is also why §5h
# needs no allowlist.
hdr "conflict-marker scanner (_core_conflict_marker_hits)"
_cmd_="$SANDBOX/conflictmarker"
mkdir -p "$_cmd_"
_cm_open="$(printf '<%.0s' 1 2 3 4 5 6 7)"
_cm_base="$(printf '|%.0s' 1 2 3 4 5 6 7)"
_cm_close="$(printf '>%.0s' 1 2 3 4 5 6 7)"
_cm_sep="$(printf '=%.0s' 1 2 3 4 5 6 7)"
_cm_write() { printf '%s\n' "$2" >"$_cmd_/$1"; }   # _cm_write <name> <body>
# _cm_is <label> <file> <expected> — the scanner's full output must equal <expected> exactly.
# Exact, not "contains": the line numbers ARE the report an operator acts on.
_cm_is() { # _cm_is <label> <file> <expected>
  local got
  got="$(_core_conflict_marker_hits "$_cmd_/$2")"
  if [[ "$got" == "$3" ]]; then
    pass "conflict-marker scan: $1"
  else
    fail "conflict-marker scan: $1 (got '${got//$'\n'/, }', want '${3//$'\n'/, }')"
  fi
}

# ── what it must catch ──
_cm_write lonebase.md "## [Unreleased]
$_cm_base parent of fcb0308 (feat(audit): extend the adoption audit (#623))"
_cm_is "a lone base marker is a finding (the #650 shape)" lonebase.md "2"

_cm_write open.txt "a
$_cm_open HEAD"
_cm_is "an open marker is a finding" open.txt "2"

_cm_write close.txt "a
$_cm_close 6fe44bd (some commit subject)"
_cm_is "a close marker is a finding" close.txt "2"

# The separator counts ONLY alongside an unambiguous marker — here it has one, so all four
# lines report. This is the whole conflict as git would leave it under zdiff3.
_cm_write full.txt "a
$_cm_open HEAD
ours
$_cm_base parent of abc1234 (subject)
base
$_cm_sep
theirs
$_cm_close abc1234 (subject)"
_cm_is "a whole zdiff3 conflict reports all four marker lines" full.txt "2
4
6
8"

# ── what it must NOT catch ──
# A setext H1 underline of exactly seven `=`. MD003 defaults to `consistent`, so a document
# that uses setext throughout is valid house style — reddening it would be a false alarm on
# correct markdown, and the gate would get switched off.
_cm_write setext.md "Some Heading
$_cm_sep

body text"
_cm_is "a bare separator alone is NOT a finding (setext underline)" setext.md ""

_cm_write clean.md "## [Unreleased]

### Fixed

- something"
_cm_is "a clean file is silent" clean.md ""

# Column 0 is what git keys on, so it is what the scanner keys on — and indenting is the
# documented escape for a doc that must SHOW a marker.
_cm_write indented.md "Example of a conflict:

    $_cm_open HEAD"
_cm_is "an indented marker is NOT a finding (the documented escape)" indented.md ""

# The self-reference guard, asserted rather than assumed: the matcher lives in a tracked file
# that §5h scans, so if it ever stops assembling its patterns from fragments it reports itself
# and the audit goes permanently red. Same class as the obfuscated `/proc/versio[n]` in
# _core_owned_block_hits, and cheaper to assert than to rediscover.
if [[ -z "$(_core_conflict_marker_hits "$HERE/scripts/lib/common.sh")" ]]; then
  pass "conflict-marker scan: the matcher does not report itself"
else fail "conflict-marker scan: common.sh reports itself — the patterns stopped being assembled from fragments"; fi
if [[ -z "$(_core_conflict_marker_hits "$HERE/scripts/test-core.sh")" ]]; then
  pass "conflict-marker scan: this test file does not report itself"
else fail "conflict-marker scan: test-core.sh reports itself — a fixture was typed literally instead of built with printf"; fi

# ── routine reference scanner (scripts/lib/common.sh :: _core_claude_ref_hits) ─
# WHY THIS IS TESTED. audit-core.sh §1b is the backstop for a defect that shipped and was
# then reported wrong twice: #661 wired /tool-scout to read .claude/tool-decisions.md and
# never tracked the file, because .gitignore's `.claude/*` negations are per-DIRECTORY. The
# gate's value is entirely in what it EXTRACTS — §1b decides existence and trackedness from
# git, which no fixture can stand in for, so the scanner is the half that can be pinned
# here. Driven on fixtures for the same reason the digest below is: making the real gate
# fail means un-tracking a file mid-audit, and CI cannot repeat that.
#
# The line numbers are load-bearing, not decoration: §1b prints `<src>:<line> names <path>`
# and that citation is the whole repair instruction. So these assert exact output.
hdr "routine reference scanner (_core_claude_ref_hits)"
_crd="$SANDBOX/clauderef"
mkdir -p "$_crd"
_cr_bt="$(printf '\140')"
_cr_write() { printf '%s\n' "$2" >"$_crd/$1"; } # _cr_write <name> <body>
_cr_is() {                                      # _cr_is <label> <file> <expected>
  local got
  got="$(_core_claude_ref_hits "$_crd/$2")"
  if [[ "$got" == "$3" ]]; then
    pass "routine reference scan: $1"
  else
    fail "routine reference scan: $1 (got '${got//$'\n'/, }', want '${3//$'\n'/, }')"
  fi
}

# ── what it must catch ──
# The real shape, verbatim from .claude/commands/tool-scout.md — a code span in a bullet.
_cr_write bullet.md "Those five describe what Core has. One more describes what it turned down:

- ${_cr_bt}.claude/tool-decisions.md${_cr_bt} — tools considered and declined."
_cr_is "a backticked path in a bullet is reported with its line" bullet.md "3:.claude/tool-decisions.md"

_cr_write two.md "read ${_cr_bt}.claude/tool-decisions.md${_cr_bt} first
then ${_cr_bt}.claude/agents/tool-scout.md${_cr_bt} too"
_cr_is "every reference reports, one per line" two.md "1:.claude/tool-decisions.md
2:.claude/agents/tool-scout.md"

# Two on ONE line. grep -o emits both with the same line number, which is what the operator
# needs — the citation points at the line, and a line can make two claims.
_cr_write same.md "both ${_cr_bt}.claude/a.md${_cr_bt} and ${_cr_bt}.claude/b.md${_cr_bt} are read"
_cr_is "two references on one line both report" same.md "1:.claude/a.md
1:.claude/b.md"

# A citation carries a line number; the FILE is still the claim being made.
_cr_write cite.md "see ${_cr_bt}.claude/commands/tool-scout.md:164${_cr_bt} for the wording"
_cr_is "a trailing :NN is stripped — a citation names a file, not a line" cite.md "1:.claude/commands/tool-scout.md"

# ── what it must NOT catch ──
# A pattern describes a SET. Resolving it would mean inventing a semantics the prose does
# not have, and the first false positive is what gets a gate switched off (the §5f argument).
_cr_write glob.md "the routines live in ${_cr_bt}.claude/commands/*.md${_cr_bt}"
_cr_is "a glob is NOT a file claim" glob.md ""

_cr_write dir.md "everything under ${_cr_bt}.claude/agents/${_cr_bt} is shared"
_cr_is "a directory is NOT a file claim" dir.md ""

# Prose that merely says the word is not asserting a path exists. Requiring the code span
# is what keeps this gate keyed on "this exact file" rather than on any mention of .claude.
_cr_write prose.md "The .claude/tool-decisions.md ledger is worth reading."
_cr_is "an unbackticked mention is NOT a finding" prose.md ""

_cr_write other.md "read ${_cr_bt}PORTING-MATRIX.md${_cr_bt} and ${_cr_bt}zsh/00-tools.zsh${_cr_bt}"
_cr_is "paths outside .claude/ are out of scope" other.md ""

_cr_is "a missing file is silent, not an error" nosuchfile.md ""

# NO SELF-REFERENCE GUARD HERE, unlike the conflict-marker matcher above, and the
# difference is real rather than an omission. That scanner reads EVERY tracked file, so
# common.sh is inside its own scan set and a literally-typed pattern would redden the audit
# permanently. This one only ever opens .claude/{commands,agents}/*.md — common.sh is not in
# the set, and the backticked `.claude/…` examples in its own comments are documentation of
# the contract, not claims about files. Asserting silence here would forbid the scanner from
# being explained in prose, which is a worse trade than it looks.
#
# What IS worth pinning is the scanner against the real routine docs rather than fixtures.
# Every assertion above is synthetic; this one fails if the house form ever moves away from
# a code span (an autolink, a markdown link, a bare path), which would leave §1b silently
# scanning for a shape nobody writes any more — a gate that passes because it found nothing
# to check, which is the exact failure #700 was.
_cr_live="$(_core_claude_ref_hits "$HERE/.claude/commands/tool-scout.md")"
if [[ "$_cr_live" == *":.claude/tool-decisions.md" ]]; then
  pass "routine reference scan: the live routine doc still parses (tool-scout.md names the ledger)"
else fail "routine reference scan: .claude/commands/tool-scout.md yielded '${_cr_live//$'\n'/, }' — the routines stopped writing paths as code spans, so §1b is scanning for a shape that no longer exists"; fi

# ── .gitignore: crash dumps vs the core.* files this repo actually tracks ─────
# The rule is `core.[0-9]*`, and the whole point is what it does NOT match. `core.*` is the
# obvious spelling and is wrong twice: this repo tracks core.manifest and core.version, every
# OS repo also tracks core.lock, and in those repos bare `core` is the vendored Core
# DIRECTORY. Gitignore does not untrack a file that is already tracked, so the damage from
# "simplifying" this would not show up here — it would show up the next time someone adds a
# core.<something> and git silently declines to see it. That is #700's failure mode exactly,
# which is why this is pinned rather than left to a comment.
#
# Asserted against the REAL .gitignore via git check-ignore, not a fixture: the question is
# what this repo's own rules do, and a fixture would only test a copy of them.
#
# --no-index is load-bearing. Without it check-ignore consults the INDEX first and never calls
# an already-tracked path ignored — so the core.manifest and core.version cases would pass
# under `core.*` as readily as under the correct rule, and this block would be three tautologies
# guarding nothing. Verified: with the rule mutated to `core.*`, all three go red only with
# --no-index; without it, only core.lock (untracked HERE) catches the mistake.
if have git && git -C "$HERE" rev-parse --git-dir >/dev/null 2>&1; then
  hdr ".gitignore: crash dumps, without swallowing core.* files"
  _gi_is() { # _gi_is <path> <ignored|tracked-able> <why>
    local want="$2" got
    if git -C "$HERE" check-ignore -q --no-index "$1" 2>/dev/null; then got="ignored"; else got="tracked-able"; fi
    if [[ "$got" == "$want" ]]; then
      pass "gitignore: $1 is $want ($3)"
    else
      fail "gitignore: $1 is $got, want $want ($3)"
    fi
  }
  _gi_is "core.1234"      ignored      "a crash dump is noise"
  _gi_is "core.99999"     ignored      "any pid width"
  _gi_is "core.manifest"  tracked-able "TRACKED here — core.* would have hidden it"
  _gi_is "core.version"   tracked-able "TRACKED here — core.* would have hidden it"
  _gi_is "core.lock"      tracked-able "TRACKED in every OS repo; keep the rule fleet-safe"
  # A bare `mise.lock` line would have no slash, so it would match at EVERY depth. mise's
  # lockfile is meant to be COMMITTED (mise/config.toml sets lockfile = true and its comment
  # says so), and the file lands next to that config — so this is the path that matters.
  _gi_is "mise/mise.lock" tracked-able "lockfile = true wants this COMMITTED, not ignored"
  unset -f _gi_is
else
  skip "gitignore crash-dump rule (not a git checkout)"
fi

# ── luacheck verdict (common.sh :: _core_luacheck_verdict) ───────────────────
# WHY THIS IS TESTED. audit-core.sh §4 used to treat EVERY non-zero luacheck exit as
# "luacheck reported issues", so a toolchain that never ran was announced as a lint failure in
# nvim/ — and the repair it printed ("re-run luacheck") only reproduced the error (#726). The
# fix is a three-way decision, and the whole value is that the three stay distinguishable.
#
# THE CASE THAT MAKES THE PROBE NECESSARY is `a load failure also exits 1`. luacheck's own
# codes are 0/1/2/3, and luacheck 1.2.0 failing to load under Lua 5.5 — the documented
# mise/config.toml trap, and the likeliest toolchain break going forward — exits 1 too. So the
# lint rc ALONE cannot separate "warnings" from "did not run", at any threshold. If someone
# later "simplifies" this to a status check on the lint rc, these cases fail.
hdr "luacheck verdict (_core_luacheck_verdict)"
_lv_is() { # _lv_is <label> <probe-rc> <lint-rc> <expected>
  local got
  got="$(_core_luacheck_verdict "$2" "$3")"
  if [[ "$got" == "$4" ]]; then
    pass "luacheck verdict: $1"
  else
    fail "luacheck verdict: $1 (probe=$2 lint=$3 → '$got', want '$4')"
  fi
}
# ── the tool ran ──
_lv_is "a clean run is ok" 0 0 ok
_lv_is "exit 1 after a passing probe is warnings, not a broken tool" 0 1 issues
_lv_is "exit 2 (syntax errors in a checked file) is still a lint result" 0 2 issues
_lv_is "exit 3 (luacheck's I/O error) is still a lint result" 0 3 issues
# ── the tool did not run ──
# The #726 shape: the luarocks wrapper execs an absolute interpreter path that is gone.
_lv_is "a failing probe is a broken tool even when the lint rc looks clean" 127 0 broken
# THE UNDECIDABLE-WITHOUT-A-PROBE CASE: luacheck 1.2.0 under Lua 5.5 fails to LOAD and exits
# 1 — byte-identical in status to honest warnings. Only the probe separates them.
_lv_is "a load failure that exits 1 is broken, not warnings" 1 1 broken
_lv_is "a failing probe wins over any lint rc" 1 2 broken
# 126/127 are the shell's "could not exec", never one of luacheck's codes, so after a passing
# probe they can only mean it stopped being runnable mid-audit — its own sentence.
_lv_is "exit 127 after a passing probe is a mid-run break" 0 127 broken-midrun
_lv_is "exit 126 (found but not executable) is a mid-run break" 0 126 broken-midrun
# The boundary itself, both sides — 3 is luacheck's highest own code.
_lv_is "exit 125 stays a lint result (below the shell's exec-failure range)" 0 125 issues
# Defaults: called with nothing, claim nothing is wrong rather than inventing a failure.
_lv_is "no arguments is ok (no inputs, no claim)" "" "" ok

# LIVE CANARY, the _core_claude_ref_hits lesson: every case above is synthetic, so all of them
# would still pass if §4 stopped consulting this function. Assert the real gate still routes
# through it — otherwise these tests pin a helper nothing calls, which is the shape of a gate
# that is green because it checks nothing.
if grep -q '_core_luacheck_verdict' "$HERE/scripts/audit-core.sh"; then
  pass "luacheck verdict: audit-core.sh §4 still routes its verdict through this function"
else
  fail "luacheck verdict: audit-core.sh no longer calls _core_luacheck_verdict — §4 decides on its own again, so every case above pins a helper nothing uses (#726)"
fi
unset -f _lv_is

# ── workflow ref-major guard (common.sh :: _core_workflow_ref_hits) ──────────
# WHY THIS IS TESTED AGAINST REAL HISTORY, not only synthetic fixtures. This guard exists
# because two real regressions shipped and stayed green (v3->v4 for ten minors, v4->v5
# until #744). A guard for a historical defect that is never RUN against that defect is
# the same category error it exists to fix, so the last two cases below rebuild the exact
# trees from the tags and require the guard to red on them.
#
# It drives _core_workflow_ref_hits DIRECTLY — never a reimplementation of its loop. The
# note on _core_tool_skip_count records what happens otherwise: the test and the shipped
# logic drift apart, both stay green, and the defect walks back in.
hdr "workflow ref-major guard (_core_workflow_ref_hits)"
_wfr_="$SANDBOX/wfref"
mkdir -p "$_wfr_/.github/workflows"
# _wfr_reset — every case starts from an EMPTY workflows dir. Without this a fixture from
# an earlier case leaks its finding into the next one's count, which is exactly what the
# first draft of these tests did: three "failures" that were stale files, not defects.
_wfr_reset() { rm -f "$_wfr_"/.github/workflows/*.yml "$_wfr_"/.github/workflows/*.yaml 2>/dev/null || :; }
# _wfr_write <name> <body> — resets first, so each fixture stands alone.
_wfr_write() { _wfr_reset; printf '%s\n' "$2" >"$_wfr_/.github/workflows/$1"; }
# _wfr_count <label> <major> <expected-line-count> — how many findings the guard reports.
_wfr_count() {
  local got n
  got="$(_core_workflow_ref_hits "$_wfr_" "$2")"
  n=0
  [[ -n "$got" ]] && n="$(printf '%s\n' "$got" | wc -l | tr -d ' ')"
  if [[ "$n" == "$3" ]]; then
    pass "workflow ref-major: $1"
  else
    fail "workflow ref-major: $1 (got $n finding(s), want $3)"
  fi
}

_wfr_write a.yml '      - uses: actions/checkout@v5
        with:
          repository: ${{ github.repository_owner }}/dotfiles-core
          ref: v4'
_wfr_count "a foreign major on a dotfiles-core checkout is a finding" 5 1
_wfr_count "the SAME file is clean when core.version agrees" 4 0

# Order within the step must not matter — YAML does not promise key order, and a guard
# that only works one way round is a coin flip on the next author's formatting.
_wfr_write b.yml '      - uses: actions/checkout@v5
        with:
          ref: v4
          repository: ${{ github.repository_owner }}/dotfiles-core'
_wfr_count "ref: before repository: is judged the same" 5 1

# The association is per STEP. A ref belonging to somebody else s checkout is not ours to
# judge, and attributing it here would make the gate cry wolf on any workflow that pulls a
# second repository at a tag.
_wfr_write c.yml '      - uses: actions/checkout@v5
        with:
          repository: ${{ github.repository_owner }}/dotfiles-core
          ref: v5
      - uses: actions/checkout@v5
        with:
          repository: someone/other-repo
          ref: v1'
_wfr_count "another repository at v1 is NOT attributed to dotfiles-core" 5 0

# A non-vN ref is deliberately out of scope: this gate answers "which major", and a SHA or
# an expression is a pinning-style question with a different right answer.
_wfr_write d.yml '      - uses: actions/checkout@v5
        with:
          repository: ${{ github.repository_owner }}/dotfiles-core
          ref: 0123456789012345678901234567890123456789'
_wfr_count "a SHA ref is not judged as a major" 5 0

# A tree with no workflows at all must be silent, not an error — role repos vendoring Core
# run this same lib.
_wfr_reset
_wfr_count "an empty workflows dir is clean" 5 0

# ── the two real regressions ──
# Rebuild each tag s .github/workflows and require the guard to red on it. If either of
# these ever goes quiet, the guard has stopped covering the thing it was written for.
if have git && git -C "$HERE" rev-parse --git-dir >/dev/null 2>&1; then
  _wfr_hist() { # _wfr_hist <tag> <expected-major> <min-findings>
    local tag="$1" major="$2" want="$3" dir="$SANDBOX/wfhist-$1" f got n
    git -C "$HERE" rev-parse -q --verify "$tag^{commit}" >/dev/null 2>&1 || {
      skip "workflow ref-major: $tag not present in this clone (shallow?)"
      return 0
    }
    mkdir -p "$dir/.github/workflows"
    while IFS= read -r f; do
      [[ "$f" == *.yml || "$f" == *.yaml ]] || continue
      git -C "$HERE" show "$tag:$f" >"$dir/$f" 2>/dev/null || :
    done < <(git -C "$HERE" ls-tree --name-only "$tag" .github/workflows/ 2>/dev/null)
    got="$(_core_workflow_ref_hits "$dir" "$major")"
    n=0
    [[ -n "$got" ]] && n="$(printf '%s\n' "$got" | wc -l | tr -d ' ')"
    if [[ "$n" -ge "$want" ]]; then
      pass "workflow ref-major: catches the real $tag regression ($n site(s))"
    else
      fail "workflow ref-major: $tag regression NOT caught (got $n finding(s), want >= $want)"
    fi
  }
  # v4.0.0 shipped four sites still on ref: v3; not corrected until v4.10.0.
  _wfr_hist v4.0.0 4 4
  # v5.0.2 shipped six sites still on ref: v4; corrected in #744.
  _wfr_hist v5.0.2 5 6
else
  skip "workflow ref-major: historical regression cases (git/repo unavailable)"
fi

# And the tree as it stands must be clean against its own core.version — the gate running
# on itself, which is what CI will do on every push.
if [[ -r "$HERE/core.version" ]]; then
  _wfr_now="$(tr -d '[:space:]' <"$HERE/core.version" | cut -d. -f1)"
  if [[ -z "$(_core_workflow_ref_hits "$HERE" "$_wfr_now")" ]]; then
    pass "workflow ref-major: this tree pins ref: v$_wfr_now everywhere (matches core.version)"
  else
    fail "workflow ref-major: this tree has a workflow on a foreign major"
  fi
  unset _wfr_now
fi

# ── unreferenced .claude/ scanner (common.sh :: _core_claude_untracked_hits) ──
# WHY THIS IS TESTED ON A REAL REPO. Unlike _core_claude_ref_hits, which is pure text
# extraction, every verdict here comes from git: is the path tracked, and which .gitignore
# rule wins. No text fixture can stand in for that, so each case builds a throwaway repo with
# its own index and .gitignore — the same approach the nvim-reachability tests take, and for
# the same reason.
#
# The discriminator under test is the one that makes the gate self-maintaining: a file hidden
# by the BLANKET `.claude/*` is a finding, one named by a MORE SPECIFIC rule is a decision.
# Get that backwards in either direction and the gate either cries wolf on every per-machine
# file or goes silent on the defect it exists for (#700).
if have git; then
  hdr "unreferenced .claude/ scanner (_core_claude_untracked_hits)"
  _cud="$SANDBOX/claudeuntracked"
  _cu_fresh() { # a repo whose .gitignore mirrors Core's: blanket + per-path negations
    rm -rf "$_cud"
    mkdir -p "$_cud/.claude/commands" "$_cud/.claude/agents"
    git -C "$_cud" init -q
    git -C "$_cud" config user.email t@example.com
    git -C "$_cud" config user.name tester
    cat >"$_cud/.gitignore" <<'GI'
.claude/*
!.claude/commands/
!.claude/agents/
!.claude/tool-decisions.md
.claude/settings.local.json
GI
    printf 'cmd\n' >"$_cud/.claude/commands/a.md"
    git -C "$_cud" add -A >/dev/null 2>&1
    git -C "$_cud" commit -qm init >/dev/null 2>&1
  }
  _cu_is() { # _cu_is <label> <expected>
    local got
    got="$(_core_claude_untracked_hits "$_cud")"
    if [[ "$got" == "$2" ]]; then
      pass "unreferenced .claude/ scan: $1"
    else
      fail "unreferenced .claude/ scan: $1 (got '${got//$'\n'/, }', want '${2//$'\n'/, }')"
    fi
  }

  # ── what it must catch ──
  # THE #700 SHAPE, with no reference to betray it: a top-level file under the blanket rule.
  _cu_fresh
  printf 'ledger\n' >"$_cud/.claude/tool-decisions-v2.md"
  _cu_is "a top-level file hidden by the blanket rule is a finding" ".claude/tool-decisions-v2.md"
  # …and #700 itself, exactly: the negations are per-path, so a name one character off the
  # negated one is invisible.
  _cu_fresh
  printf 'x\n' >"$_cud/.claude/tool-decisions.md.bak"
  _cu_is "a near-miss on a negated filename is a finding" ".claude/tool-decisions.md.bak"

  # ── what it must NOT catch ──
  _cu_fresh
  _cu_is "a clean tree yields nothing" ""
  # The negated file, actually tracked — the state the gate wants the tree in.
  _cu_fresh
  printf 'ledger\n' >"$_cud/.claude/tool-decisions.md"
  git -C "$_cud" add -A >/dev/null 2>&1
  git -C "$_cud" commit -qm ledger >/dev/null 2>&1
  _cu_is "a tracked file is not a finding" ""
  # THE EXEMPTION THAT MUST HOLD: its own .gitignore line is a decision, not an oversight.
  # If this regresses, every developer's per-machine settings turn the audit red.
  _cu_fresh
  printf '{}\n' >"$_cud/.claude/settings.local.json"
  _cu_is "a file with its own specific ignore rule is exempt" ""
  # UNTRACKED BUT VISIBLE is deliberately out of scope — inside a negated directory git shows
  # the file in `git status`, so this gate flagging it would red the audit on every
  # work-in-progress file. The scope is invisibility, not un-added-ness.
  _cu_fresh
  printf 'new\n' >"$_cud/.claude/commands/b.md"
  _cu_is "an untracked file git can still SEE is not a finding" ""
  # Degenerate inputs: silence, never a crash or a false claim.
  rm -rf "$_cud"; mkdir -p "$_cud"
  _cu_is "a directory with no .claude/ yields nothing" ""
  rm -rf "$_cud"; mkdir -p "$_cud/.claude"; printf 'x\n' >"$_cud/.claude/f.md"
  _cu_is "a non-git directory yields nothing (no repo, no claim)" ""

  # LIVE CANARY, the _core_claude_ref_hits lesson: every case above is synthetic, so all of
  # them would still pass if .gitignore stopped using the blanket spelling the scanner
  # matches — leaving a gate that is green because it recognises nothing. Assert the real
  # rule still exists in the form the case arm keys on.
  if grep -qxE '\.claude/\*\*?' "$HERE/.gitignore"; then
    pass "unreferenced .claude/ scan: .gitignore still uses the blanket rule the scanner keys on"
  else
    fail "unreferenced .claude/ scan: .gitignore no longer carries a bare '.claude/*' line — _core_claude_untracked_hits keys its finding on that exact pattern, so it now recognises nothing and passes vacuously"
  fi
  rm -rf "$_cud"
  unset -f _cu_fresh _cu_is
  unset _cud
else
  skip "unreferenced .claude/ scanner (git not installed)"
fi

# ── nested-gate failure digest (scripts/lib/common.sh :: _core_fail_digest) ───
# WHY THIS IS TESTED AT ALL. audit-core.sh reports the behavioural suite through this, and its
# whole reason for existing is that an INTERMITTENT failure is unreproducible by the time the
# operator is told to re-run — so the one line that names it has to be right on the FIRST
# occurrence. Every branch below is a QUIET failure: it renders a plausible line and loses the
# name, which is indistinguishable from the flake simply not being nameable. Driven straight on
# fixtures because the alternative — making a real gate fail — means recursively invoking the
# audit or hand-injecting a fault, and CI repeats neither.
hdr "nested-gate failure digest (_core_fail_digest)"
_fdg="$SANDBOX/faildigest"
mkdir -p "$_fdg"
_fdesc="$(printf '\033')"

# 1. COLOUR IS THE ONE THAT WOULD GO QUIET UNNOTICED. fail() prefixes ✗ with $c_red, so an
#    anchored ^✗ finds nothing whenever colour is forced — and the runs where a human forces
#    colour are exactly the runs a human is watching. Fixture carries the real SGR bytes.
{
  printf 'preamble noise\n'
  printf '%s✗%s atuin autostart: the sandbox leaked\n' "${_fdesc}[31m" "${_fdesc}[0m"
  printf '%s✓%s something fine\n' "${_fdesc}[32m" "${_fdesc}[0m"
} >"$_fdg/coloured.txt"
_fdout="$(_core_fail_digest "$_fdg/coloured.txt")"
if [[ "$_fdout" == "1: atuin autostart: the sandbox leaked" ]]; then
  pass "fail digest: a COLOURED ✗ is still extracted (an anchored match would report nothing here)"
else
  fail "fail digest: colour hid the failure — got '$_fdout', want '1: atuin autostart: the sandbox leaked'"
fi

# 2. The count is the TRUE total while only three are named; "+N more" is what keeps that from
#    being a silent truncation. This is the line that tells one flaky assertion apart from a
#    section that is wholly down, which is what decides re-run versus investigate.
: >"$_fdg/many.txt"
for _fdi in alpha beta gamma delta epsilon; do printf '✗ case %s failed\n' "$_fdi" >>"$_fdg/many.txt"; done
_fdout="$(_core_fail_digest "$_fdg/many.txt")"
if [[ "$_fdout" == "5: case alpha failed | case beta failed | case gamma failed (+2 more)" ]]; then
  pass "fail digest: five failures render as three names + a true total (+2 more), not a silent cut"
else
  fail "fail digest: overflow rendering wrong — got '$_fdout'"
fi

# 3. EXACTLY three must not grow a "(+0 more)" tail — an off-by-one here is the kind of wart
#    that gets copied into the next renderer because it looks deliberate.
: >"$_fdg/three.txt"
for _fdi in one two three; do printf '✗ %s\n' "$_fdi" >>"$_fdg/three.txt"; done
_fdout="$(_core_fail_digest "$_fdg/three.txt")"
if [[ "$_fdout" == "3: one | two | three" ]]; then
  pass "fail digest: exactly three names render with no '(+0 more)' tail"
else
  fail "fail digest: boundary at three is wrong — got '$_fdout'"
fi

# 3b. A RECORD IS NOT REWRITTEN TO FIT THE SEPARATOR. The first implementation joined with
#     `tr '\n' '|' | sed 's/|/ | /g'`, which also spaced out every literal `|` INSIDE a
#     message — and nine assertions in this very file contain one, `'exec … || exec …' cannot
#     fall back` among them. Two failures then rendered with four apparent boundaries while
#     the count said 2, inventing structure in the one line someone has when they cannot
#     reproduce the failure. Fixtures use the real offending text rather than a stand-in.
{
  printf "✗ atuin unit: 'exec … || exec …' cannot fall back — exec replaces the process\n"
  printf '✗ serve: plain second failure\n'
} >"$_fdg/pipes.txt"
_fdout="$(_core_fail_digest "$_fdg/pipes.txt")"
if [[ "$_fdout" == "2: atuin unit: 'exec … || exec …' cannot fall back — exec replaces the process | serve: plain second failure" ]]; then
  pass "fail digest: a literal '||' inside a message survives verbatim — the count and the visible boundaries agree"
else
  fail "fail digest: a message's own pipes were rewritten as separators — got '$_fdout'"
fi

# 4. NO MARKER MUST YIELD NOTHING, so the caller can tell "these assertions failed" from "it
#    died before it could report". Rendering an empty list beside a red line would read as zero
#    failures and send the reader hunting a contradiction that is not there; audit-core.sh
#    branches on this emptiness to say "exited N without printing a ✗" instead.
printf 'ran fine\nno markers here\n' >"$_fdg/nomark.txt"
_fdout="$(_core_fail_digest "$_fdg/nomark.txt")"
_fdout2="$(_core_fail_digest "$_fdg/does-not-exist.txt")"
if [[ -z "$_fdout" && -z "$_fdout2" ]]; then
  pass "fail digest: output with no ✗, and an unreadable file, both yield EMPTY so a crash is not misreported as assertions"
else
  fail "fail digest: expected empty for both no-marker ('$_fdout') and missing file ('$_fdout2')"
fi

# ── E0. content-gate file set (_audit_ls, scripts/lib/common.sh) ──────────────
# The audit's content gates (bash -n, zsh -n, shellcheck, the pipefail scanner, toml/
# yaml/json) used to enumerate with a bare `git ls-files`, which lists ONLY tracked
# files. A brand-new script was therefore invisible until `git add`, and the gate still
# reported "all clean" — a green audit that had not read the file. That shipped: #496's
# scripts/ci-pr-link.sh passed a local 261/0 audit, then failed all four CI legs on two
# SC2016 violations. Pin the enumeration so the blind spot cannot come back.
#
# Driven in a THROWAWAY repo, not this one: asserting against the real checkout would
# depend on whatever happens to be untracked in the developer's tree, which is exactly
# the kind of ambient state that makes a test lie.
if have git; then
  hdr "content-gate file set (_audit_ls)"
  ALSREPO="$SANDBOX/audit-ls-repo"
  rm -rf "$ALSREPO"
  mkdir -p "$ALSREPO"
  git -C "$ALSREPO" init -q
  git -C "$ALSREPO" config user.email t@example.com
  git -C "$ALSREPO" config user.name tester
  printf 'ignored/\n' >"$ALSREPO/.gitignore"
  printf '#!/usr/bin/env bash\n:\n' >"$ALSREPO/tracked.sh"
  git -C "$ALSREPO" add -A
  git -C "$ALSREPO" commit -qm init
  # Created AFTER the commit: the exact state the bug was blind to.
  printf '#!/usr/bin/env bash\n:\n' >"$ALSREPO/untracked.sh"
  mkdir -p "$ALSREPO/ignored"
  printf '#!/usr/bin/env bash\n:\n' >"$ALSREPO/ignored/skipped.sh"
  _als_out="$(cd "$ALSREPO" && _audit_ls '*.sh')"
  _als_has() { # _als_has <label> <needle> <want:0|1>
    local n=0
    # Herestring, NOT `printf … | grep -qx`: that is the SIGPIPE shape §5d exists to
    # catch — grep exits on its first match, printf takes EPIPE, and pipefail reports
    # the pipeline as failed, which here would silently flip an assertion to false.
    # The list is small enough to fit the pipe buffer today, so it happens to work;
    # "happens to work" is exactly what this file should not rely on.
    grep -qx "$2" <<<"$_als_out" && n=1
    if ((n == $3)); then pass "$1"; else fail "$1 (got list: ${_als_out//$'\n'/ })"; fi
  }
  _als_has "_audit_ls includes a tracked script" 'tracked.sh' 1
  # THE REGRESSION GUARD: this is the assertion that would have failed before the fix.
  _als_has "_audit_ls includes an UNTRACKED script (the #496 blind spot)" 'untracked.sh' 1
  # --exclude-standard: a gitignored scratch script must not start failing anyone's audit.
  _als_has "_audit_ls excludes a gitignored script" 'ignored/skipped.sh' 0
  # Deduped: a tracked file must not be listed twice just because both probes ran.
  _als_n="$(printf '%s\n' "$_als_out" | grep -cx 'tracked.sh')"
  if [[ "$_als_n" == 1 ]]; then
    pass "_audit_ls does not double-list a tracked file"
  else
    fail "_audit_ls double-listed a tracked file ($_als_n times)"
  fi
  # The audit's CONTENT gates must all use _audit_ls; the GIT-STATE gates — the --changed
  # scope probe, manifest reverse-drift, and the index exec-bit check — must NOT.
  #
  # Manifest EXPANSION is deliberately absent from that list: it feeds §5c, which cat|greps
  # every file it names, so it is a content gate wearing manifest clothing and routes
  # through _audit_ls like the rest. It sat in this list while the implementation said
  # otherwise, which is how it got misfiled in the first place.
  #
  # Assert the split EXACTLY, in both directions. A floor (">= N helper calls") looks like
  # it guards this and does not: once seven calls exist, a NEW content gate can enumerate
  # with a bare `git ls-files` and the floor is still satisfied — the guard would sit green
  # through the reintroduction of the very bug it exists to prevent. Worse, a later helper
  # call could mask a regression elsewhere by keeping the total up.
  #
  # Exact counts are deliberately a tripwire: adding EITHER kind of enumeration fails here
  # until someone bumps the number, which is the moment to decide which side of the rule
  # the new gate belongs on. That decision is the whole point; a test that lets it be made
  # implicitly is not guarding anything.
  #
  # EVERY gate script that `make audit` consults, not just audit-core.sh. The first
  # version guarded one file, and the rule was quietly broken in three places outside it:
  # audit-core.sh's own manifest expansion (which feeds the §5c OS-path CONTENT scan and
  # merely looks like a manifest question), check-modern.sh's workflow inventory, and
  # nvim-reachability.sh's module inventory. A rule documented as universal but enforced
  # on one file is worse than no rule — it reads as covered.
  #
  # Count CALLS robustly: `_audit_ls '<glob>'`, `_audit_ls "$m"`, and `_audit_ls \` with
  # the pathspecs on the next line all count. Two earlier patterns here were too narrow
  # and undercounted exactly those forms. The definition line `_audit_ls() {` and comment
  # lines are excluded from both counts, so prose ABOUT either mechanism never trips it.
  _als_calls() { # _als_calls <file> → number of _audit_ls call sites
    grep -nE '(^|[^[:alnum:]_])_audit_ls([[:space:]]|$)' "$1" 2>/dev/null |
      grep -vE '^[0-9]+:[[:space:]]*#' | grep -vcE '_audit_ls\(\)'
  }
  _als_direct() { # _als_direct <file> → number of bare `git ls-files` sites
    grep -nE 'git ls-files' "$1" 2>/dev/null | grep -vcE '^[0-9]+:[[:space:]]*#'
  }
  # file:want_content:want_direct — exact on BOTH sides. A floor would stop guarding the
  # moment the count was met: a NEW content gate could use bare `git ls-files` and still
  # satisfy it. Exactness makes adding either kind of enumeration fail here until someone
  # picks a side, which is the decision this rule exists to force.
  # audit-core.sh 8→9 content calls: §5e (leaked RETURN trap) enumerates via _audit_ls.
  # It is a CONTENT gate — "is this file's text valid?" — so an untracked-but-not-ignored
  # script is in scope: a brand-new helper arming a leaked trap must be caught BEFORE it is
  # `git add`ed, not one round-trip later. That is the side of the rule this tripwire made
  # explicit, which is what it is for.
  #
  # 9→10: §5h (leftover conflict markers), same side and for the same reason. A marker is a
  # property of a file's TEXT, and the moment it most needs catching is before the commit
  # that would carry it onto main — which is precisely the untracked-but-not-ignored window
  # `_audit_ls` covers and bare `git ls-files` does not. Its pathspec is `*` rather than a
  # glob list because the defect that motivated it (#650) was in markdown, not in shell.
  #
  # DIRECT 3→5: §1b (routine reference integrity) takes bare `git ls-files` twice, and this
  # is the one gate where the choice is not a preference. It asks whether a file the
  # routines claim to read is SHIPPED — a pure "what does git record?" question — and the
  # defect it exists for (#700) was a file present on the author's disk and ignored by git.
  # `_audit_ls` includes untracked-but-not-ignored files, so using it here would wave that
  # exact file through while every clone stayed broken: the gate would be green precisely
  # on the machine where the bug is invisible. Both call sites are the same question — one
  # builds the tracked set to test membership against, the other picks the routine docs to
  # scan — so both take the git-state side.
  _als_expect="audit-core.sh:10:5 check-modern.sh:2:0 nvim-reachability.sh:2:0"
  _als_bad=""
  for _als_spec in $_als_expect; do
    _als_f="${_als_spec%%:*}"
    _als_rest="${_als_spec#*:}"
    _als_wc="${_als_rest%%:*}"
    _als_wd="${_als_rest##*:}"
    _als_gc="$(_als_calls "$HERE/scripts/$_als_f")"
    _als_gd="$(_als_direct "$HERE/scripts/$_als_f")"
    [[ "$_als_gc" == "$_als_wc" && "$_als_gd" == "$_als_wd" ]] ||
      _als_bad="${_als_bad}${_als_f} (got ${_als_gc}/${_als_gd}, want ${_als_wc}/${_als_wd}) "
  done
  if [[ -z "$_als_bad" ]]; then
    pass "enumeration split is exact across all three gate scripts (content via _audit_ls / git-state direct)"
  else
    fail "enumeration split changed: ${_als_bad}— a new enumeration must pick a side (content → _audit_ls, git-state → git ls-files), then update these counts"
  fi
fi

hdr "CI path classifier (scripts/ci-classify.sh)"
CLASSIFY="$HERE/scripts/ci-classify.sh"
_classify_is() { # _classify_is <label> <newline-input> <want-shell> <want-nvim> <want-atuin>
  local got
  got="$(printf '%s\n' "$2" | "$CLASSIFY" 2>/dev/null)"
  if [[ "$got" == "shell=$3"$'\n'"nvim=$4"$'\n'"atuin=$5" ]]; then
    pass "$1"
  else
    fail "$1 (got: ${got//$'\n'/ }; want shell=$3 nvim=$4 atuin=$5)"
  fi
}
_classify_is "zsh/ change → shell gate only" 'zsh/05-ui.zsh' true false false
_classify_is "nvim/ change → nvim gate only" 'nvim/init.lua' false true false
_classify_is "docs (*.md) change → no gate" 'README.md' false false false
_classify_is "infra (scripts/) change → full run" 'scripts/audit-core.sh' true true true
_classify_is "infra (.shellcheckrc) change → full run" '.shellcheckrc' true true true
_classify_is "__ALL__ sentinel → full run" '__ALL__' true true true
_classify_is "unrecognised path → FAIL CLOSED to full run" 'newdir/thing.xyz' true true true
_classify_is "mixed shell+nvim set → union of both" $'zsh/05-ui.zsh\nnvim/init.lua' true true false
_classify_is "examples/ change → no gate (repo-meta, nothing links it)" 'examples/atuin-daemon.service' false false false
# The atuin axis. zsh/00-tools.zsh carries _core_atuin_daemon_guard — the thing the premise
# detector exists to protect — and atuin/ is its config, so both must reach the atuin gate
# AND the shell gate. The first of these is the ORDERING assertion: 00-tools.zsh also matches
# the general `zsh/*` arm, and since first match wins, an arm added in the wrong order would
# classify it as plain shell and silently stop running the detector's self-test on the one
# module that can break it.
_classify_is "zsh/00-tools.zsh change → shell AND atuin (guard's own module)" 'zsh/00-tools.zsh' true false true
_classify_is "atuin/ config change → shell AND atuin" 'atuin/config.toml' true false true
# tealdeer is a plain tools-group config: shell gate only. NOT the atuin axis — that one
# gates the premise detector's hermetic self-test and is kept narrow on purpose.
_classify_is "tealdeer/ config change → shell gate only" 'tealdeer/config.toml' true false false
_classify_is "a plain zsh/ change does NOT pay the atuin gate" 'zsh/45-plugins.zsh' true false false
_classify_is "mixed atuin+nvim set → union across all three axes" $'atuin/config.toml\nnvim/init.lua' true true true

# ── E2. PR link gate (scripts/ci-pr-link.sh) ──────────────────────────────────
# #446 fixed #420 and #423 and merged green with NO closing keyword, so GitHub linked
# nothing and both issues sat open looking like live bugs. pr-link-check.yml now gates
# that, and the verdict logic lives in a script (like ci-classify.sh) precisely so it
# can be pinned here instead of rotting untested inside workflow YAML.
hdr "PR link gate (scripts/ci-pr-link.sh)"
PRLINK="$HERE/scripts/ci-pr-link.sh"
_prlink_is() { # _prlink_is <label> <title> <linked-count> <body> <want-verdict>
  local got rc want_rc
  got="$(printf '%s' "$4" | "$PRLINK" "$2" "$3" 2>/dev/null)"
  rc=$?
  # Assert the EXIT STATUS as well as the verdict line. The workflow enforces the policy
  # through the status, not the text — so a regression to `exit 0` on missing-link would
  # silently stop failing PRs while a stdout-only assertion stayed green. Checking both
  # pins the two together: missing-link is the only verdict that may exit non-zero.
  # Both blocking verdicts exit 1. They are NOT interchangeable: missing-link asserts
  # something about the PR, probe-failed asserts only that the API could not be reached
  # (#500). Same policy, different claim — so the tests pin the verdict token too, and a
  # regression that swapped one for the other would fail on the stdout comparison above.
  case "$5" in
  missing-link | probe-failed) want_rc=1 ;;
  *) want_rc=0 ;;
  esac
  if [[ "$got" == "verdict=$5" ]] && ((rc == want_rc)); then
    pass "$1"
  else
    fail "$1 (got: ${got:-<empty>} rc=$rc; want verdict=$5 rc=$want_rc)"
  fi
}
# The gated set: the delimiter-aware Conventional-Commit shape from
# scripts/gen-release-notes.sh:50 — optional (scope), optional breaking `!`, then the `:`.
# NOT cliff.toml:56, which groups on a broader bare `^fix` and would sweep in `fixup:`;
# the gate deliberately takes the stricter of the two.
_prlink_is "fix( PR with a linked issue → ok" 'fix(doctor): probe both names' 1 '' ok
_prlink_is "fix( PR with no link and no reason → missing-link" 'fix(doctor): probe both names' 0 '' missing-link
_prlink_is "unscoped fix: is gated too" 'fix: probe both names' 0 '' missing-link
_prlink_is "breaking fix!: is gated too" 'fix!: probe both names' 0 '' missing-link
_prlink_is "breaking scoped fix(x)!: is gated too" 'fix(doctor)!: probe both names' 0 '' missing-link
_prlink_is "feat( is not gated (fix-only rule)" 'feat(doctor): new panel' 0 '' not-gated
_prlink_is "chore( is not gated" 'chore(deps): bump actions' 0 '' not-gated
# The delimiter is what separates a type from prose — without it, `fixup:` and an
# ordinary sentence would both be swept in, and authors would learn to distrust the gate.
_prlink_is "fixup: is not the fix type (delimiter, not prefix)" 'fixup: squash me' 0 '' not-gated
_prlink_is "prose starting with the word is not gated" 'fixing a flaky test' 0 '' not-gated
# The escape hatch, and its two failure modes.
_prlink_is "No-Issue: with a reason exempts" 'fix(x): y' 0 'No-Issue: found in one pass, never filed' exempt
_prlink_is "No-Issue: is case-insensitive and may be indented" 'fix(x): y' 0 '   no-issue: trivial typo' exempt
_prlink_is "bare No-Issue: with no reason does NOT exempt" 'fix(x): y' 0 'No-Issue:' missing-link
_prlink_is "no-issue: mid-prose does NOT exempt (line-anchored)" 'fix(x): y' 0 'there is no-issue: here' missing-link
# THE ONE THAT MATTERS. pull_request_template.md documents the marker inside an HTML
# comment; if the scan read the raw body, every unedited-template PR would exempt itself
# and the gate would ship dead — green and green look identical, so nothing would catch it.
_prlink_is "commented-out No-Issue: does NOT exempt (inline)" \
  'fix(x): y' 0 '<!-- No-Issue: <reason> if there is no issue -->' missing-link
_prlink_is "commented-out No-Issue: does NOT exempt (multi-line)" \
  'fix(x): y' 0 $'<!--\nNo-Issue: <reason>\n-->' missing-link
_prlink_is "a real marker after a comment still exempts" \
  'fix(x): y' 0 $'<!-- guidance -->\nNo-Issue: genuinely no issue' exempt
# ── An undeterminable count is NOT zero links (#500) ─────────────────────────────────
# The first version coerced a non-numeric count to 0, so a GitHub API blip produced
# `missing-link` and told the author their linked PR had no link. That happened for real:
# #499 links #498, and during a run of 503s the check failed it with "closes no issue and
# gives no reason" — false, and the kind of thing that teaches people to distrust a gate.
# It still BLOCKS (a broken probe must never silently open the gate), but the claim it
# makes is now true.
_prlink_is "an undeterminable count is probe-failed, NOT missing-link" \
  'fix(x): y' 'unknown' '' probe-failed
_prlink_is "an empty count (partial API response) is probe-failed too" \
  'fix(x): y' '' '' probe-failed
# The escape hatch is read from the body and needs no API call, so it must still work
# while the probe is down — blocking a PR that already carries its reason would be
# gratuitous, and the check has everything it needs to say yes.
_prlink_is "No-Issue: still exempts while the probe is down" \
  'fix(x): y' 'unknown' 'No-Issue: found in one pass' exempt
# A non-fix PR is out of scope whatever the probe did.
_prlink_is "a non-fix PR stays not-gated while the probe is down" \
  'feat(x): y' 'unknown' '' not-gated
# Usage error is its own exit code (2), distinct from a policy violation (1), so a
# workflow that miscalls the script reads as broken rather than as a failing PR.
# Asserted inline rather than via check(), which is zsh-only and defined further down.
"$PRLINK" 'only-one-arg' </dev/null >/dev/null 2>&1
if [[ $? -eq 2 ]]; then
  pass "ci-pr-link.sh exits 2 on usage error"
else
  fail "ci-pr-link.sh exits 2 on usage error"
fi

# ── F. core/ pre-commit guard (lib/bootstrap-lib.sh blib_install_core_guard) ───
# The guard hook (installed by sync-core.sh on every fan-out, and by a bootstrap on a
# fresh clone) is the mechanical backstop for "never hand-edit vendored core/". Drive it
# hermetically in throwaway git repos: assert it BLOCKS a core/ commit, ALLOWS a non-core
# commit, ALLOWS a core/ commit under the sync escape hatch, and never clobbers a foreign
# pre-commit hook. Pure bash + git (skipped where git is absent, like the nvim sections).
if have git; then
  hdr "core/ pre-commit guard (blib_install_core_guard)"
  # shellcheck source=lib/bootstrap-lib.sh
  source "$HERE/lib/bootstrap-lib.sh"
  # Pin git config to /dev/null (like the gcheck helper) so a host/CI global
  # core.hooksPath would not make git ignore our per-repo hook, and a global
  # commit.gpgsign can't break the non-core commit — keeps these assertions hermetic.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  GREPO="$SANDBOX/guardrepo"
  _guard_fresh() { # fresh repo with the guard installed
    rm -rf "$GREPO"
    mkdir -p "$GREPO/core"
    git -C "$GREPO" init -q
    git -C "$GREPO" config user.email t@example.com
    git -C "$GREPO" config user.name tester
    blib_install_core_guard "$GREPO" >/dev/null 2>&1
  }
  _guard_commit() { # _guard_commit <relpath> <allow:0|1> → echoes ok|blocked
    printf 'edit' >"$GREPO/$1"
    git -C "$GREPO" add -A
    local rc
    if [[ "${2:-0}" == 1 ]]; then
      DOTFILES_ALLOW_CORE_EDIT=1 git -C "$GREPO" commit -q -m x >/dev/null 2>&1
      rc=$?
    else
      git -C "$GREPO" commit -q -m x >/dev/null 2>&1
      rc=$?
    fi
    [[ $rc -eq 0 ]] && echo ok || echo blocked
  }

  _guard_fresh
  if [[ -x "$GREPO/.git/hooks/pre-commit" ]]; then pass "guard: pre-commit hook installed (+x)"; else fail "guard: hook missing or not executable"; fi

  _guard_fresh
  if [[ "$(_guard_commit core/x.txt 0)" == blocked ]]; then pass "guard: blocks a commit touching core/"; else fail "guard: did NOT block a core/ edit"; fi

  _guard_fresh
  if [[ "$(_guard_commit README.md 0)" == ok ]]; then pass "guard: allows a non-core commit"; else fail "guard: wrongly blocked a non-core commit"; fi

  _guard_fresh
  if [[ "$(_guard_commit core/y.txt 1)" == ok ]]; then pass "guard: DOTFILES_ALLOW_CORE_EDIT exempts a sync write"; else fail "guard: escape hatch did not allow a core/ commit"; fi

  # a pure DELETION of a vendored file (git rm core/…) drifts from Core too — must be blocked
  _guard_fresh
  printf 'seed' >"$GREPO/core/seed.txt"; git -C "$GREPO" add -A
  DOTFILES_ALLOW_CORE_EDIT=1 git -C "$GREPO" commit -q -m seed >/dev/null 2>&1
  git -C "$GREPO" rm -q core/seed.txt >/dev/null 2>&1
  if git -C "$GREPO" commit -q -m del >/dev/null 2>&1; then fail "guard: did NOT block a core/ deletion"; else pass "guard: blocks a core/ deletion (git rm)"; fi

  # a pre-existing, unrelated pre-commit hook must be preserved (not clobbered)
  rm -rf "$GREPO"; mkdir -p "$GREPO/core"; git -C "$GREPO" init -q
  printf '#!/bin/sh\nexit 0\n' >"$GREPO/.git/hooks/pre-commit"; chmod +x "$GREPO/.git/hooks/pre-commit"
  blib_install_core_guard "$GREPO" >/dev/null 2>&1
  if grep -q 'dotfiles-core-guard' "$GREPO/.git/hooks/pre-commit"; then fail "guard: clobbered a pre-existing custom hook"; else pass "guard: preserves a pre-existing custom pre-commit hook"; fi

  # core.hooksPath set → git ignores .git/hooks, so installing there is false
  # protection. The installer must skip rather than write an ignored hook.
  rm -rf "$GREPO"; mkdir -p "$GREPO/core"; git -C "$GREPO" init -q
  git -C "$GREPO" config core.hooksPath .githooks
  blib_install_core_guard "$GREPO" >/dev/null 2>&1
  if [[ -e "$GREPO/.git/hooks/pre-commit" ]] && grep -q 'dotfiles-core-guard' "$GREPO/.git/hooks/pre-commit" 2>/dev/null; then
    fail "guard: wrote into the ignored .git/hooks despite core.hooksPath"
  else
    pass "guard: skips when core.hooksPath is set (no false protection)"
  fi

  # worktree support (the reason the installer asks git instead of testing for a `.git`
  # DIR): in a linked worktree `.git` is a FILE, and hooks live in the shared common dir.
  # Install into the worktree and assert the guard actually blocks a core/ commit there.
  rm -rf "$GREPO"; mkdir -p "$GREPO/core"; git -C "$GREPO" init -q
  git -C "$GREPO" config user.email t@example.com; git -C "$GREPO" config user.name tester
  printf 'seed' >"$GREPO/seed.txt"; git -C "$GREPO" add -A
  git -C "$GREPO" commit -q -m seed >/dev/null 2>&1   # a worktree needs a commit to branch from
  GWT="$SANDBOX/guardwt"; rm -rf "$GWT"
  if git -C "$GREPO" worktree add -q "$GWT" -b wt >/dev/null 2>&1; then
    mkdir -p "$GWT/core"
    blib_install_core_guard "$GWT" >/dev/null 2>&1
    printf 'edit' >"$GWT/core/wt.txt"; git -C "$GWT" add -A
    if git -C "$GWT" commit -q -m x >/dev/null 2>&1; then
      fail "guard: did NOT block a core/ edit in a worktree (.git is a file)"
    else
      pass "guard: blocks a core/ edit in a linked worktree"
    fi
  else
    skip "guard: worktree case (git worktree unavailable)"
  fi
fi

# ── F2. auto-tag version math + exit-code contract (scripts/auto-tag.sh) ──────
# auto-tag.sh cuts an OS repo's next vX.Y.Z when a Core fan-out lands. Drive its
# (dry-run) computation hermetically: it must patch-bump the latest STRICT SemVer tag
# while IGNORING a prerelease/suffixed tag (v1.2.0-rc1) and the moving major alias (v1),
# stay octal-safe on a zero-padded component (v1.08.0), seed an untagged repo, no-op when
# HEAD is already a release, and usage-error a bad --bump — the exact glob/parse
# regressions a loose `git tag --list` glob would let through. THEN the exit-code contract
# the script's fix(release) history is all about: success → 0, no-op → 0, validation error
# → 2, and a REAL push failure → non-zero (never a silent green). The first three legs are
# hermetic (no network, no gh); the push-failure leg deliberately drives the real `git push`
# error branch — there is no `origin` in the sandbox, so the push fails and the script goes
# non-zero, which is exactly the contract under test. Pure bash + git.
if have git; then
  hdr "auto-tag version math + exit-code contract (scripts/auto-tag.sh)"
  AT="$HERE/scripts/auto-tag.sh"
  ATR="$SANDBOX/atrepo"
  _at_fresh() {
    rm -rf "$ATR"
    mkdir -p "$ATR"
    git -C "$ATR" init -q
    git -C "$ATR" config user.email t@example.com
    git -C "$ATR" config user.name tester
    git -C "$ATR" commit -q --allow-empty -m c1
  }
  _at_would() { # [bump] → echoes the tag it WOULD cut (dry-run), or noop / err
    local out
    out="$(env -u CORE_JSON "$AT" "$ATR" ${1:+--bump "$1"} --color never 2>&1)" || {
      echo err
      return 0
    }
    if grep -q 'already tagged' <<<"$out"; then
      echo noop
    else
      sed -n 's/.*would tag \(v[0-9][0-9.]*\).*/\1/p' <<<"$out"
    fi
  }

  _at_assert() { # _at_assert <label> <want> [bump]
    local got
    got="$(_at_would "${3:-}")"
    if [[ "$got" == "$2" ]]; then pass "$1"; else fail "$1 (got $got, want $2)"; fi
  }

  _at_fresh
  git -C "$ATR" tag -a v1.2.0 -m v1.2.0
  git -C "$ATR" tag -a v1.2.0-rc1 -m rc      # prerelease — must be ignored
  git -C "$ATR" tag v1                       # moving major alias — must be ignored
  git -C "$ATR" commit -q --allow-empty -m c2 # HEAD now past the tags
  _at_assert "auto-tag: patch-bumps latest strict tag, ignoring rc + vN alias" v1.2.1
  _at_assert "auto-tag: minor bump" v1.3.0 minor

  _at_fresh
  git -C "$ATR" tag -a v1.08.0 -m x          # zero-padded component — must not octal-error
  git -C "$ATR" commit -q --allow-empty -m c2
  _at_assert "auto-tag: octal-safe on a zero-padded component" v1.9.0 minor

  _at_fresh # no tags at all → seed the initial
  _at_assert "auto-tag: seeds v0.1.0 when the repo has no tag" v0.1.0

  _at_fresh
  git -C "$ATR" tag -a v2.0.0 -m x           # HEAD itself tagged → idempotent no-op
  _at_assert "auto-tag: no-op when HEAD already carries a release" noop

  _at_assert "auto-tag: rejects an invalid --bump" err bogus

  _at_fresh # --release is meaningless without --push (can't release an unpushed tag)
  if "$AT" "$ATR" --release --color never >/dev/null 2>&1; then
    fail "auto-tag: --release without --push should error"
  else
    pass "auto-tag: --release requires --push"
  fi

  # ── exit-code contract (the band-aids' history is exactly about exit codes) ──
  # auto-tag.sh has had repeated fix(release) commits over its exit codes: a no-op must
  # be 0, a usage/validation error 2, and a REAL create failure non-zero (not a silent
  # green). Assert all three legs HERMETICALLY — no network, no gh. Helper: run + echo rc.
  _at_rc() { "$AT" "$ATR" "$@" --color never >/dev/null 2>&1; echo $?; }

  # 1) SUCCESS leg — a plain dry-run on a tagged repo computes a bump and exits 0.
  _at_fresh
  git -C "$ATR" tag -a v1.0.0 -m v1.0.0
  git -C "$ATR" commit -q --allow-empty -m c2
  if [[ "$(_at_rc)" == 0 ]]; then pass "auto-tag: success (dry-run computes a bump) exits 0"; else fail "auto-tag: dry-run should exit 0"; fi

  # 2) NO-OP leg — HEAD already carries a release → idempotent, exits 0 (not an error).
  _at_fresh
  git -C "$ATR" tag -a v1.0.0 -m v1.0.0   # tags HEAD
  if [[ "$(_at_rc)" == 0 ]]; then pass "auto-tag: no-op (HEAD already tagged) exits 0"; else fail "auto-tag: no-op should exit 0"; fi

  # 3) USAGE/VALIDATION error — a malformed --initial is rejected with exit 2 (not 1).
  _at_fresh   # untagged repo, so --initial is the seed path that validates it
  if [[ "$(_at_rc --initial 1.2)" == 2 ]]; then pass "auto-tag: malformed --initial exits 2"; else fail "auto-tag: bad --initial should exit 2"; fi

  # 4) REAL PUSH-FAILURE leg — exercise auto-tag.sh's push error branch (the one that
  #    `fail`s + exits 1 when `git push origin <tag>` fails). On a freshly-tagged repo the
  #    bump is computable and unique, so the script creates the tag and then tries to push
  #    it; the sandbox has NO `origin` remote, so the push genuinely fails and the script
  #    goes non-zero. This is the "a real push failure must go red, not green" contract the
  #    fix(release) history is about. (Not hermetic — it intentionally hits the push path;
  #    if an `origin` were ever added to the sandbox this leg would need a guaranteed-to-fail
  #    remote instead.)
  _at_fresh
  git -C "$ATR" tag -a v1.0.0 -m v1.0.0         # latest release on c1
  git -C "$ATR" commit -q --allow-empty -m c2   # HEAD past the tag → a real bump (v1.0.1) to push
  _rc_push="$(_at_rc --push)"
  if [[ "$_rc_push" != 0 ]]; then pass "auto-tag: --push with no reachable origin fails non-zero (rc=$_rc_push)"; else fail "auto-tag: failed push should exit non-zero, got 0"; fi
else
  skip "auto-tag version math + exit-code contract (git unavailable)"
fi

# ── F3. release-notes drafting (scripts/gen-release-notes.sh) ─────────────────
# gen-release-notes.sh turns an OS repo's Conventional Commits in a range into the grouped
# markdown body auto-tag.sh feeds `gh release create --notes-file` (G5 — a real changelog,
# not a bare tag). Assert hermetically: the right groups appear in cliff.toml order, the
# subject is rendered as cliff renders it, a chore(release) commit is skipped and an
# unconventional subject is dropped, and a range with no conventional commits prints
# NOTHING (exit 0 → the caller falls back to gh --generate-notes). Pure bash + git.
#
# "as cliff renders it" is load-bearing and was the one thing this block got wrong: it used
# to assert `Feat(x): add a thing`, pinning the prefix-retaining bug rather than the twin's
# contract. cliff.toml sets conventional_commits = true, so git-cliff's `commit.message` is
# the DESCRIPTION alone — the type/scope/`!` are parsed off — and the bullet reads
# "Add a thing" under a heading that already says Features. Both directions are asserted now
# (description present AND prefix absent), so the bug cannot come back green.
if have git; then
  hdr "release-notes drafting (scripts/gen-release-notes.sh)"
  GRN="$HERE/scripts/gen-release-notes.sh"
  GRNR="$SANDBOX/grnrepo"
  rm -rf "$GRNR"; mkdir -p "$GRNR"
  git -C "$GRNR" init -q
  git -C "$GRNR" config user.email t@example.com
  git -C "$GRNR" config user.name tester
  git -C "$GRNR" commit -q --allow-empty -m "chore: seed"
  git -C "$GRNR" tag v1.0.0
  git -C "$GRNR" commit -q --allow-empty -m "fix: correct a bug"          # Bug Fixes
  git -C "$GRNR" commit -q --allow-empty -m "feat(x): add a thing"        # Features (later, but must sort first)
  git -C "$GRNR" commit -q --allow-empty -m "feat(y)!: upend a contract"  # breaking → must stay visible
  git -C "$GRNR" commit -q --allow-empty -m "chore(release): v1.1.0"      # must be skipped
  git -C "$GRNR" commit -q --allow-empty -m "totally unconventional line" # must be dropped
  git -C "$GRNR" commit -q --allow-empty -m "fixing a flaky test"         # prose, no delimiter → dropped
  git -C "$GRNR" commit -q --allow-empty -m "refactor:"                   # no description → dropped
  _grn_out="$(env -u CORE_JSON "$GRN" "$GRNR" v1.0.0 HEAD 2>/dev/null)"

  if grep -q '^### Features$' <<<"$_grn_out" && grep -q '^### Bug Fixes$' <<<"$_grn_out"; then
    pass "gen-notes: groups feat + fix under cliff.toml headings"
  else fail "gen-notes: expected Features + Bug Fixes headings"; fi

  if grep -q 'Add a thing' <<<"$_grn_out" && grep -qE '\([0-9a-f]{7}\)' <<<"$_grn_out"; then
    pass "gen-notes: upper-firsts the description and appends a 7-char SHA"
  else fail "gen-notes: subject/sha format wrong"; fi

  # The regression this block used to enshrine: cliff strips type/scope, so no bullet may
  # carry a Conventional prefix. Asserted over the whole body, not just the one subject.
  if ! grep -qiE '^- (\*\*BREAKING\*\* )?(feat|fix|docs|chore|perf|refactor|test|ci|build|style)(\([^)]*\))?!?:' <<<"$_grn_out"; then
    pass "gen-notes: strips the Conventional prefix (cliff conventional_commits=true)"
  else fail "gen-notes: a bullet kept its type(scope): prefix"; fi

  # Deliberate divergence from cliff (which renders breaking commits indistinguishably,
  # since the template interpolates commit.message and never commit.breaking): a `!` must
  # survive into the draft, because it is what drives the SemVer major bump.
  if grep -q '^- \*\*BREAKING\*\* Upend a contract' <<<"$_grn_out"; then
    pass "gen-notes: marks a breaking (!) commit instead of flattening it"
  else fail "gen-notes: breaking marker lost"; fi

  # A type with no description ("refactor:") is unparseable to git-conventional, so cliff's
  # filter_unconventional drops it — verified against git-cliff 2.13.1, which emits no
  # Refactoring group for that input. It must not surface as a bare or empty bullet.
  if ! grep -q '^### Refactoring$' <<<"$_grn_out" && ! grep -qE '^- (Refactor:)?$' <<<"$_grn_out"; then
    pass "gen-notes: a prefix-only subject (no description) is dropped, not an empty bullet"
  else fail "gen-notes: a description-less commit leaked into the notes"; fi

  if ! grep -qi 'release' <<<"$_grn_out" && ! grep -qi 'unconventional' <<<"$_grn_out"; then
    pass "gen-notes: skips chore(release) and drops unconventional commits"
  else fail "gen-notes: a skipped/dropped commit leaked into the notes"; fi

  # "fixing a flaky test" starts with 'fix' but has no `:` delimiter → must be filtered,
  # not grouped under Bug Fixes (the conventional-delimiter anchor; mirrors filter_unconventional).
  if ! grep -qi 'flaky' <<<"$_grn_out"; then
    pass "gen-notes: prose starting with a type word (no delimiter) is dropped"
  else fail "gen-notes: unconventional prose leaked into a group"; fi

  # commit_parsers order, not commit order: Features (committed later) must lead Bug Fixes.
  if [[ "$_grn_out" == "### Features"* ]]; then
    pass "gen-notes: emits groups in cliff.toml order (Features first)"
  else fail "gen-notes: group order is not the cliff.toml order"; fi

  git -C "$GRNR" tag v1.1.0
  git -C "$GRNR" commit -q --allow-empty -m "just some words"
  if _grn_empty="$(env -u CORE_JSON "$GRN" "$GRNR" v1.1.0 HEAD)"; [[ -z "$_grn_empty" ]]; then
    pass "gen-notes: a no-conventional-commit range prints nothing (caller falls back)"
  else fail "gen-notes: expected empty output for a non-conventional range"; fi

  # The section order now lives in TWO places: cliff.toml's `<N>` sort keys (which the
  # template strips back out) and this script's ORDER array. They must not drift — that is
  # the whole point of the `<N>` keys, which exist only to make git-cliff emit the twin's
  # order instead of Tera's alphabetical group_by.
  #
  # SORT, don't read in file order. What git-cliff renders is the LEXICAL order of the full
  # group strings — Tera's group_by sorts by the attribute value — so the position of a line
  # in commit_parsers is not what decides anything. Reading the file top-to-bottom would pass
  # happily while `<0>` and `<1>` were swapped in place, i.e. while cliff emitted Bug Fixes
  # ahead of Features again. So: extract each group WITH its key, sort exactly as Tera does
  # (LC_ALL=C for a byte-order sort that does not drift with the runner's locale), and only
  # then strip the keys. The result is the effective output order, which is the thing that
  # has to match ORDER. (chore(release) is skip=true and contributes no group.)
  #
  # `sed -E`, not BRE `\+`: BSD sed has no `\+`, so the BRE form silently matched nothing on
  # macOS and this guard reported a phantom drift against an empty string. -E is understood
  # by both GNU and BSD sed.
  if [[ -f "$HERE/cliff.toml" ]]; then
    _cliff_order="$(sed -n -E 's/.*group = "(<[0-9]+> [^"]*)".*/\1/p' "$HERE/cliff.toml" |
      LC_ALL=C sort | sed -E 's/^<[0-9]+> //' | paste -sd'|' -)"
    _twin_order="$(sed -n -E 's/.*split\("([^"]*)", ORDER.*/\1/p' "$GRN")"
    if [[ -n "$_cliff_order" && "$_cliff_order" == "$_twin_order" ]]; then
      pass "gen-notes: group order matches cliff.toml's <N> sort keys"
    else
      fail "gen-notes: group order drifted — cliff.toml '$_cliff_order' vs twin '$_twin_order'"
    fi

    # The `<N>` keys are single-digit, so they sort correctly only up to ten groups:
    # "<10>" would land between "<1>" and "<2>" and silently reorder the notes.
    _cliff_groups="$(grep -cE 'group = "<[0-9]+>' "$HERE/cliff.toml")"
    if ((_cliff_groups <= 10)) && ! grep -q 'group = "<[0-9][0-9]' "$HERE/cliff.toml"; then
      pass "gen-notes: cliff.toml stays within the single-digit <N> sort ceiling ($_cliff_groups/10)"
    else
      fail "gen-notes: cliff.toml has >10 groups or a two-digit <N> — the sort key needs widening"
    fi
  else
    skip "gen-notes: cliff.toml order cross-check (no cliff.toml)"
  fi
else
  skip "release-notes drafting (git unavailable)"
fi

# ── F4. dashboard live-signal error handling (scripts/freshness-dashboard.sh) ─
# The weekly board embeds LIVE GitHub API answers, and `gh api` does something surprising
# on an HTTP error: it SKIPS --jq and copies the raw error BODY to STDOUT, summarising only
# to stderr. So the old `2>/dev/null || true` silenced the wrong stream, threw away the one
# reliable signal (the exit code), and let {"message":"Not Found",…} through as if it were
# a value — every `// empty` and `[ -n "$n" ]` guard downstream waved it past (issue #324:
# a 404 body rendered as dotfiles-web's release tag, a 403 body as htpx's issue count).
# Shellcheck cannot see any of that, so drive it hermetically: a programmable `gh` stub
# reproducing gh's real error shape (body on stdout, `(HTTP NNN)` on stderr, non-zero rc),
# in a throwaway repo root whose four sub-check scripts are stubs — the real
# update-nvim-plugins.sh --check drives a full `:Lazy! sync` (minutes, network).
hdr "dashboard live-signal error handling (scripts/freshness-dashboard.sh)"
FDR="$SANDBOX/fdrepo"
FDBIN="$SANDBOX/fdbin"
rm -rf "$FDR" "$FDBIN"
mkdir -p "$FDR/scripts/lib" "$FDR/lib" "$FDBIN" "$SANDBOX/fdfleet"
cp "$HERE/scripts/freshness-dashboard.sh" "$FDR/scripts/"
# The board sources lib/common.sh for load_os_repos (#669), and common.sh sources
# ../../lib/ux.sh — same two libs the fleet-drift fixture below carries, for the same reason.
cp "$HERE/scripts/lib/common.sh" "$FDR/scripts/lib/"
cp "$HERE/lib/ux.sh" "$FDR/lib/"
for _fd_s in fleet-drift core-integrity update-plugins update-nvim-plugins; do
  printf '#!/bin/sh\nexit 0\n' >"$FDR/scripts/$_fd_s.sh"
  chmod +x "$FDR/scripts/$_fd_s.sh"
done
# One OS repo → REPOS is 5 (core, Windows, web, MacBook, htpx) → 10 search calls, which is
# what the ladder-latch count below is derived from.
printf 'dotfiles-MacBook\n' >"$FDR/scripts/os-repos.txt"

cat >"$FDBIN/gh" <<'GHSTUB'
#!/bin/sh
printf '%s\n' "$*" >>"$GH_CALLS"
case "$*" in
"auth status"*)     exit 1 ;;   # so the GH_OK=0 degradation case is reachable
*releases/latest*)  # never-released repo: gh prints the 404 BODY to stdout, rc 1
  printf '{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}\n'
  echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
*/tags*)
  case "${GH_TAGS:-ok}" in
  none) exit 0 ;;               # genuinely tagless: rc 0, --jq yields empty
  fail) printf '{"message":"Bad credentials","status":"401"}\n'
        echo 'gh: Bad credentials (HTTP 401)' >&2; exit 1 ;;
  *)    printf 'v1.2.3\n' ;;
  esac ;;
*compare*)          printf '7\n' ;;
*search/issues*)
  # GH_SEARCH=flaky — limited on attempts 1-2, healthy on 3-6, limited again from 7. Two
  # DISTINCT episodes: the first clears mid-ladder (must recover), the second never does
  # (must exhaust and latch). One episode alone cannot tell latch-on-exhaustion from
  # latch-on-ladder-start; the second episode is what separates them. The attempt counter
  # is GH_CALLS itself (appended above), so it survives the separate stub processes a
  # single ladder spawns.
  if [ "${GH_SEARCH:-limited}" = flaky ]; then
    _n="$(grep -c 'search/issues' "$GH_CALLS")"
    [ "$_n" -ge 3 ] && [ "$_n" -le 6 ] && { printf '4\n'; exit 0; }
  fi
  printf '{"message":"You have exceeded a secondary rate limit.","status":"403"}\n'
  echo 'gh: You have exceeded a secondary rate limit (HTTP 403)' >&2; exit 1 ;;
esac
exit 0
GHSTUB
chmod +x "$FDBIN/gh"

# _fd_run — board on stdout, script's rc in $?. Pace/backoff zeroed so the ladder is
# exercised without sleeping through it. GITHUB_REPOSITORY_OWNER is PINNED, not inherited:
# the script defaults OWNER from it, GitHub Actions always sets it, and on a fork it is the
# fork owner — so an inherited value would fail the URL assertions below in a fork's CI
# even with the dashboard behaving correctly. A fixture owner (not the real `dotgibson`)
# keeps that pin honest: drop it and the assertions fail immediately, anywhere.
_fd_run() {
  PATH="$FDBIN:$PATH" GH_TOKEN=stub GH_CALLS="$SANDBOX/gh.calls" GH_TAGS="${GH_TAGS:-ok}" \
    GH_SEARCH="${GH_SEARCH:-limited}" GITHUB_REPOSITORY_OWNER=fixtureowner \
    DASH_SEARCH_PACE=0 DASH_RETRY_BASE="${DASH_RETRY_BASE:-0}" \
    DASH_RETRY_BUDGET="${DASH_RETRY_BUDGET:-60}" \
    env -u CORE_JSON bash "$FDR/scripts/freshness-dashboard.sh" --root "$SANDBOX/fdfleet" 2>/dev/null
}

: >"$SANDBOX/gh.calls"
_fd_board="$(GH_TAGS=none _fd_run)"
_fd_rc=$?

# The #324 regression itself: not one byte of an API error body may reach the board.
if ! grep -qE '"message"|documentation_url|"status":"40' <<<"$_fd_board"; then
  pass "dashboard: no GitHub API error body reaches the board"
else fail "dashboard: an API error body leaked into the rendered board"; fi

# `— (no tags)` was UNREACHABLE before the fix for any repo whose 404 body carries a
# `message` key, because the blob made `tag` non-empty and skipped the /tags fallback.
if grep -q -- '— (no tags)' <<<"$_fd_board"; then
  pass "dashboard: a genuinely tagless repo renders '— (no tags)'"
else fail "dashboard: '— (no tags)' branch still unreachable"; fi

# A rate-limited search must degrade to `?` in BOTH live tallies — the Renovate cell and
# the judgment-layer link text (the latter is the exact cell that rendered htpx's 403).
if grep -q '| dotfiles-core | ? |' <<<"$_fd_board" &&
  grep -qF '[?](https://github.com/fixtureowner/dotfiles-core/issues' <<<"$_fd_board"; then
  pass "dashboard: a rate-limited search renders '?' in both tallies"
else fail "dashboard: a failed search did not degrade to '?'"; fi

# A reporter never fails the build, even with every live call erroring.
if [ "$_fd_rc" -eq 0 ]; then
  pass "dashboard: still exits 0 with every live call failing"
else fail "dashboard: exited $_fd_rc with failing live calls (must always be 0)"; fi

# The ladder must run ONCE and then latch. 10 search calls → 4 invocations for the first
# (initial + 3 retries) + 1 each for the other 9 = 13. A variable latch would re-ladder
# every call (40) because the helpers run inside `$( )`; no latch at all, also 40.
_fd_calls="$(grep -c 'search/issues' "$SANDBOX/gh.calls")"
if [ "$_fd_calls" -eq 13 ]; then
  pass "dashboard: 403 backoff ladder runs once per run, then latches (13 search calls)"
else fail "dashboard: expected 13 search calls (one ladder + 9 latched), got $_fd_calls"; fi

# A FAILED tag probe must not masquerade as a confident "this repo has no tags" — that is
# the distinction the propagated exit status buys, and the board asserted it without
# evidence before.
_fd_board_fail="$(GH_TAGS=fail _fd_run)"
if grep -q '| dotfiles-web | ? | ? |' <<<"$_fd_board_fail" &&
  ! grep -q -- '(no tags)' <<<"$_fd_board_fail"; then
  pass "dashboard: a failed tag probe renders '?', not '— (no tags)'"
else fail "dashboard: a failed tag probe was reported as 'no tags'"; fi

# A TRANSIENT limit that clears must RECOVER, not latch — the ladder exists precisely so a
# blip still yields the real number — while a limit that never clears must still exhaust
# and latch. Two episodes (see the stub): the Renovate tally's first 4 repos ride out
# episode 1 and report real counts, htpx opens episode 2 and exhausts, and the judgment
# tally is latched from there on.
#
# The call count is what pins the DESIGN. 15 = 3 (episode-1 ladder recovers) + 3 (healthy)
# + 4 (episode-2 ladder exhausts) + 6 (latched). Latching when a ladder STARTS instead of
# when it is exhausted gives 12, because episode 2 would be refused without ever retrying —
# i.e. one recoverable blip would permanently downgrade the rest of the run.
: >"$SANDBOX/gh.calls"
_fd_flaky="$(GH_SEARCH=flaky GH_TAGS=none _fd_run)"
_fd_flaky_calls="$(grep -c 'search/issues' "$SANDBOX/gh.calls")"
if [ "$_fd_flaky_calls" -eq 15 ] &&
  grep -q '| dotfiles-core | 4 |' <<<"$_fd_flaky" && grep -q '| htpx | ? |' <<<"$_fd_flaky"; then
  pass "dashboard: a transient 403 recovers; only an exhausted ladder latches"
else fail "dashboard: recover-vs-latch wrong (calls=$_fd_flaky_calls, expected 15)"; fi

# Cumulative-sleep ceiling. The exhausted-ladder latch cannot bound a run where every
# ladder RECOVERS, so DASH_RETRY_BUDGET caps total backoff instead. Budget 0 proves the
# gate: the very first 403 exceeds it, so no call ever sleeps and each of the 10 makes
# exactly one invocation (vs 13 when the budget allows one full ladder).
: >"$SANDBOX/gh.calls"
_fd_budget="$(DASH_RETRY_BASE=1 DASH_RETRY_BUDGET=0 _fd_run)"
_fd_budget_rc=$?
_fd_budget_calls="$(grep -c 'search/issues' "$SANDBOX/gh.calls")"
if [ "$_fd_budget_calls" -eq 10 ] && [ "$_fd_budget_rc" -eq 0 ]; then
  pass "dashboard: the cumulative backoff budget caps total sleep across ladders"
else fail "dashboard: backoff budget not enforced (calls=$_fd_budget_calls, expected 10)"; fi

# Without gh/token the board must still compose, with the unavailable note.
_fd_degraded="$(env -u GH_TOKEN -u GITHUB_TOKEN PATH="$FDBIN:$PATH" \
  GH_CALLS="$SANDBOX/gh.calls" \
  env -u CORE_JSON bash "$FDR/scripts/freshness-dashboard.sh" --root "$SANDBOX/fdfleet" 2>/dev/null)"
_fd_deg_rc=$?
if [ "$_fd_deg_rc" -eq 0 ] && grep -q 'Unavailable in this run' <<<"$_fd_degraded"; then
  pass "dashboard: degrades to the 'unavailable' note without gh/token"
else fail "dashboard: GH_OK=0 degradation path broken (rc=$_fd_deg_rc)"; fi

# ── F4b. fleet-member resolution (scripts/lib/common.sh :: resolve_repo_dir) ──
# sync-core.sh, fleet-drift.sh and core-integrity.sh all turn a repo NAME from
# scripts/os-repos.txt into a path. They used to do it by string-joining onto the fleet
# root, which is right until a repo is RENAMED upstream: git follows the rename, the
# directory name does not, and all three scripts then reported "not cloned"/"not checked
# out" for a repo that was present, vendored and pristine. The fan-out SKIPPED it.
#
# Driven here rather than only through the fixtures because the failure is entirely in
# this one function, and the sharp edges (URL shapes, case-folding, precedence, a clone
# with no origin) are cheap to enumerate directly and expensive to stage end-to-end.
if have git; then
  hdr "fleet-member resolution (resolve_repo_dir)"
  RRD="$SANDBOX/repodir"
  rm -rf "$RRD"
  mkdir -p "$RRD/root"
  _rrd_repo() { # _rrd_repo <dir-name> [origin-url] — a clone, optionally with an origin
    local d="$RRD/root/$1"
    mkdir -p "$d"
    git -C "$d" init -q >/dev/null 2>&1
    [[ -n "${2:-}" ]] && git -C "$d" remote add origin "$2"
    return 0
  }
  _rrd_is() { # _rrd_is <label> <asked-name> <want-dir-or-empty>
    local got rc
    got="$(resolve_repo_dir "$RRD/root" "$2")" || rc=1
    rc="${rc:-0}"
    if [[ "$got" == "${3:+$RRD/root/$3}" ]] && [[ "$rc" == "$([[ -n "$3" ]] && echo 0 || echo 1)" ]]; then
      pass "$1"
    else
      fail "$1 (got='$got' rc=$rc, want='${3:-<unresolved>}')"
    fi
  }

  # 1) The fast path: a directory of the right name resolves with no remote at all — the
  #    conventional layout must not acquire a dependency on having an origin configured.
  mkdir -p "$RRD/root/dotfiles-Plain"
  _rrd_is "resolve: a directory matching the name wins outright (no git needed)" dotfiles-Plain dotfiles-Plain

  # 2) THE regression: no directory of that name, but a clone whose origin says it IS
  #    that repo. This is the dotfiles-Kali → dotfiles-Offense shape.
  _rrd_repo old-name https://github.com/dotgibson/dotfiles-Renamed.git
  _rrd_is "resolve: a renamed repo is found by its origin URL" dotfiles-Renamed old-name

  # 3) Both URL shapes. An scp-style remote (git@host:owner/repo) has no slash before the
  #    owner, so a naive ${url##*/} works on one form and silently fails on the other.
  _rrd_repo scp-clone git@github.com:dotgibson/dotfiles-Scp.git
  _rrd_is "resolve: an scp-style git@host:owner/repo remote parses" dotfiles-Scp scp-clone
  _rrd_repo bare-clone https://github.com/dotgibson/dotfiles-NoSuffix
  _rrd_is "resolve: an https remote with no .git suffix parses" dotfiles-NoSuffix bare-clone

  # 4) GitHub repo names are case-insensitive, so a clone of dotfiles-offense IS
  #    dotfiles-Offense. Matching case-sensitively would reintroduce the same false miss.
  _rrd_repo lower-clone https://github.com/dotgibson/dotfiles-mixedcase.git
  _rrd_is "resolve: matching is case-insensitive, like GitHub itself" dotfiles-MixedCase lower-clone

  # 5) Precedence. With BOTH a correctly-named directory and some other clone claiming the
  #    name via its origin, the directory must win — otherwise adding the fallback could
  #    silently move an existing, working fan-out onto a different tree.
  mkdir -p "$RRD/root/dotfiles-Both"
  _rrd_repo decoy-clone https://github.com/dotgibson/dotfiles-Both.git
  _rrd_is "resolve: the directory-name match takes precedence over a URL match" dotfiles-Both dotfiles-Both

  # 6) Nothing matches → return 1 and print nothing, so a caller's `|| path=<conventional>`
  #    fallback fires and the "not cloned at <path>" advice still names the expected path.
  _rrd_is "resolve: an absent repo is unresolved (rc 1, no output)" dotfiles-Absent ""

  # 7) A clone with NO origin must be stepped over, not crash the sweep. The scripts run
  #    under `set -euo pipefail`, so a bare `git remote get-url` failure inside the loop is
  #    a live abort risk, not a cosmetic one — and a fleet root routinely holds unrelated
  #    checkouts (dotfiles-web, a scratch clone) that have nothing to say about the fleet.
  _rrd_repo orphan-clone
  # rc captured off the `||`, not read back from `$?`: the distinction that matters is
  # 1 (searched, found nothing) vs anything else (aborted mid-scan), and only an explicit
  # capture keeps those apart.
  _rrd_orphan_rc=0
  (
    set -euo pipefail
    resolve_repo_dir "$RRD/root" dotfiles-Absent
  ) >/dev/null 2>&1 || _rrd_orphan_rc=$?
  if [[ "$_rrd_orphan_rc" -eq 1 ]]; then
    pass "resolve: a remote-less clone is skipped, not fatal under set -e"
  else
    fail "resolve: scanning a clone with no origin exited $_rrd_orphan_rc (want 1)"
  fi
fi

# ── F5. fleet drift classifier (scripts/fleet-drift.sh) ───────────────────────
# The sweep's verdict function had never been driven by a test. It flagged ANY recorded
# commit that wasn't byte-identical to the reference — but the reference DEFAULTS to the
# latest release tag while `make sync` fans out main's TIP, so every repo synced between
# releases was reported "AHEAD by N" and the sweep advised `make sync`, the one action that
# would push it further ahead (#371). The fix — ahead-of-tag but on main's lineage is
# CURRENT, ahead but off it is still drift — is pure git-reachability logic that shellcheck
# cannot see and that the real checkout cannot exercise (it needs a tag, commits past it, and
# an off-main commit, none of which may be created here). So build a throwaway Core: copy the
# script plus the two libs it sources into a sandbox repo root, git init a small history, and
# drive one fixture OS repo through every verdict by rewriting its core.lock.
if have git; then
  hdr "fleet drift classifier (scripts/fleet-drift.sh)"
  FDC="$SANDBOX/fdcore"    # the throwaway "Core" ($HERE, as fleet-drift.sh computes it)
  FDF="$SANDBOX/fdriftfleet"   # its fleet root (--root)
  rm -rf "$FDC" "$FDF"
  mkdir -p "$FDC/scripts/lib" "$FDC/lib" "$FDF/dotfiles-Test"
  cp "$HERE/scripts/fleet-drift.sh" "$FDC/scripts/"
  cp "$HERE/scripts/lib/common.sh" "$FDC/scripts/lib/"
  cp "$HERE/lib/ux.sh" "$FDC/lib/" # common.sh sources ../../lib/ux.sh
  printf 'dotfiles-Test\n' >"$FDC/scripts/os-repos.txt" # a one-repo fleet
  # Neutralise host git config: a global commit.gpgsign or init.defaultBranch must not reach
  # into the fixture (signing would block the commits; the branch name is load-bearing here).
  _fdg() { git -C "$FDC" -c commit.gpgsign=false -c user.email=t@example.com -c user.name=t "$@"; }
  _fdc() { _fdg commit -q --allow-empty -m "$1"; }
  _fdg init -q >/dev/null 2>&1
  _fdg symbolic-ref HEAD refs/heads/main # not `init -b main` (needs git >= 2.28)
  _fdc c0; FD_OLD="$(_fdg rev-parse HEAD)"  # before the tag → genuinely stale
  _fdc c1; _fdg tag -a v1.0.0 -m v1.0.0     # ← becomes the default reference
  FD_REL="$(_fdg rev-parse 'v1.0.0^{commit}')"
  # FD_MID: on main and ahead of the tag, but NOT at main's tip — the stalled-fan-out shape,
  # which _classify rendered identically to FD_TIP before the behind-main clause existed.
  # Only the sha differs between the two rows, so together they isolate that clause alone.
  _fdc c2; FD_MID="$(_fdg rev-parse HEAD)"          # main, 1 past the tag, 1 behind the tip
  _fdc c3; FD_TIP="$(_fdg rev-parse HEAD)"          # main, 2 past the tag
  _fdg checkout -q -b feat v1.0.0
  _fdc f1; FD_OFF="$(_fdg rev-parse HEAD)"  # ahead of the tag but NOT on main
  _fdg checkout -q -b side "$FD_OLD"
  _fdc g1; FD_DIV="$(_fdg rev-parse HEAD)"  # behind AND ahead → diverged
  _fdg checkout -q main

  _fdd_lock() { printf '%s\n' "$@" >"$FDF/dotfiles-Test/core.lock"; }
  # -u CORE_JSON, for the same reason _sc_run and _tr_run strip it (#524/#508/#511): the
  # parent's --json EXPORTS CORE_JSON=1 so nested gates keep stdout clean for the JSON object,
  # common.sh's skip() then prints nothing, and fleet-drift.sh reports a not-checked-out repo
  # via exactly that skip() (fleet-drift.sh, the `else skip` arm of the NOT CHECKED OUT
  # branch). The assertions below grep for that line, so `test-core.sh --scope none --json`
  # reported fail:1 on a tree the identical non-JSON run passed clean. Third fixture bitten by
  # this, which is why the scan below now enforces the rule rather than trusting review.
  _fdd_run() { env -u CORE_JSON bash "$FDC/scripts/fleet-drift.sh" --root "$FDF" --color never 2>&1; }
  _fdd_is() { # _fdd_is <label> <want-rc> <status-regex>
    local out rc row
    out="$(_fdd_run)"; rc=$?
    row="$(grep 'dotfiles-Test' <<<"$out" | head -n1)"
    if [[ "$rc" == "$2" ]] && grep -qE "$3" <<<"$row"; then pass "$1"
    else fail "$1 (rc=$rc want=$2; row='$row')"; fi
  }

  _fdd_lock "core_sha=$FD_REL"
  _fdd_is "drift: sha identical to the reference tag is current" 0 'current *$'
  _fdd_lock "core_sha=$FD_OLD"
  # THE guard on the fix: tolerating AHEAD must not have tolerated real staleness.
  _fdd_is "drift: a sha behind the reference still FAILS" 1 'BEHIND by 1 commit'
  _fdd_lock "core_sha=$FD_TIP"
  # #371 itself — the fleet's ordinary between-releases state must be green.
  _fdd_is "drift: ahead of the tag but on main is current (#371)" 0 'current \(ahead of v1.0.0 by 2 commit\(s\), on main\)'
  # ...and the row must say how far it still is from main's TIP. `--is-ancestor` is reflexive
  # at both ends, so "on main" alone read identically for a repo synced this morning and one
  # synced five weeks ago — a stalled fan-out hid inside a green sweep (#381). REPORT-ONLY, so
  # the rc stays 0: this must add a number, never a verdict.
  _fdd_lock "core_sha=$FD_MID"
  _fdd_is "drift: ahead-of-tag but behind main's tip reports the lag and stays green" 0 \
    'current \(ahead of v1\.0\.0 by 1 commit\(s\), on main, 1 behind its tip\)'
  # At the tip the clause must VANISH, not read "0 behind its tip". The assertion above for
  # FD_TIP already enforces it (its regex ends `on main\)`), but only incidentally — name the
  # invariant, because it is the sole reason a finished row keeps its pre-#381 wording.
  _fdd_lock "core_sha=$FD_TIP"
  if ! grep -q 'behind its tip' <<<"$(_fdd_run)"; then
    pass "drift: a repo AT main's tip omits the behind-main clause"
  else fail "drift: behind-main clause printed for a repo already at main's tip"; fi
  _fdd_lock "core_sha=$FD_OFF"
  # ...and the tolerance must stay narrow: ahead off the released lineage is still drift.
  _fdd_is "drift: ahead of the tag but OFF main still FAILS" 1 'OFF-LINEAGE'
  _fdd_lock "core_sha=$FD_DIV"
  _fdd_is "drift: a diverged sha still FAILS" 1 'DIVERGED \(behind 1, ahead 1\)'
  _fdd_lock "core_tag=v1.0.0" # marker present, but no core_sha key
  _fdd_is "drift: a marker with no recorded sha FAILS" 1 'no provenance recorded'
  _fdd_lock "core_sha=$(printf '0%.0s' {1..40})" # a sha this clone has never seen
  _fdd_is "drift: an unknown sha degrades to DIFFERS, not a crash" 1 'DIFFERS'
  rm -f "$FDF/dotfiles-Test/core.lock"
  _fdd_is "drift: a missing core.lock FAILS" 1 'missing core.lock'

  # The header must name the RESOLVED REFERENCE (a tag), not the checkout's branch: the old
  # form printed "(main)" beside the tag's sha, which read as a comparison against main's tip.
  _fdd_lock "core_sha=$FD_REL"
  _fdd_hdr="$(_fdd_run | grep 'Fleet drift vs Core')"
  if [[ "$_fdd_hdr" == *"v1.0.0 (${FD_REL:0:12})"* ]]; then
    pass "drift: header names the resolved reference tag, not the current branch"
  else fail "drift: header is '$_fdd_hdr'"; fi

  # The closing advice must fit the verdict. `make sync` brings a LAGGING repo forward; it
  # would overwrite an off-lineage marker rather than reconcile it, so it must not be offered.
  _fdd_lock "core_sha=$FD_OLD"; _fdd_behind="$(_fdd_run)"
  _fdd_lock "core_sha=$FD_OFF"; _fdd_off="$(_fdd_run)"
  if grep -q "make sync" <<<"$_fdd_behind" && ! grep -q "make sync" <<<"$_fdd_off"; then
    pass "drift: 'make sync' is advised only for repos that actually lag"
  else fail "drift: remediation text does not match the verdict"; fi
  # An unstamped repo IS sync-fixable — but its branch returns before the verdict arm that
  # buckets the rest, so it needs its own assertion or the advice silently regresses.
  rm -f "$FDF/dotfiles-Test/core.lock"
  if grep -q "make sync" <<<"$(_fdd_run)"; then
    pass "drift: a missing marker is advised to re-sync"
  else fail "drift: a missing core.lock did not advise 'make sync'"; fi

  # The ahead-on-main state is GREEN but not FINISHED, so it must not render as a plain ✓ —
  # the whole reason it stopped being a failure is that the tally now carries the signal.
  _fdd_lock "core_sha=$FD_TIP"; _fdd_ahead="$(_fdd_run)"
  if grep -qE '^•.*current \(ahead of v1\.0\.0' <<<"$_fdd_ahead" &&
    grep -q '1 repo(s) carrying UNRELEASED Core' <<<"$_fdd_ahead"; then
    pass "drift: unreleased-Core rows render as a third state and are tallied"
  else fail "drift: third state not distinguished from a plain pass"; fi
  # ...and the tally must stay silent when the fleet really is pinned, or it becomes noise.
  _fdd_lock "core_sha=$FD_REL"
  if ! grep -q 'UNRELEASED Core' <<<"$(_fdd_run)"; then
    pass "drift: a fleet pinned to the tag reports no unreleased Core"
  else fail "drift: unreleased tally fired on a pinned fleet"; fi

  # An explicit --ref that doesn't resolve must be a usage error, not a silent fallback to
  # origin/main — the banner would otherwise name a ref that was never compared against.
  env -u CORE_JSON bash "$FDC/scripts/fleet-drift.sh" --root "$FDF" --ref nosuchref --color never >/dev/null 2>&1
  if [[ $? -eq 2 ]]; then pass "drift: an unresolvable --ref exits 2 instead of falling back"
  else fail "drift: unresolvable --ref did not exit 2"; fi

  # An unusable fleet list must STOP the sweep, not degrade to a hardcoded fleet (#669).
  # fleet-drift.sh used to carry an inline nine-name array for exactly this case, so an
  # unreadable os-repos.txt produced a full green sweep of a list nobody chose — a report
  # that looks like coverage and is not. Same exit 2 as any other usage error here.
  _fdd_fleet="$FDC/scripts/os-repos.txt"
  _fdd_body="$(cat "$_fdd_fleet")"
  _fdd_lock "core_sha=$FD_REL" # a state that WOULD sweep green, so only the load can red it
  for _fdd_case in absent empty; do
    case "$_fdd_case" in
    absent) rm -f "$_fdd_fleet" ;;
    empty) printf '# nothing but comments\n\n' >"$_fdd_fleet" ;;
    esac
    _fdd_out="$(_fdd_run)"
    _fdd_rc=$?
    if [[ $_fdd_rc -eq 2 ]] && grep -qE 'fleet list (unreadable|is empty)' <<<"$_fdd_out"; then
      pass "drift: an $_fdd_case fleet list exits 2 instead of sweeping a fallback fleet"
    else
      fail "drift: an $_fdd_case fleet list did not stop the sweep (rc=$_fdd_rc want=2)"
    fi
  done
  printf '%s\n' "$_fdd_body" >"$_fdd_fleet"
  unset _fdd_fleet _fdd_body _fdd_case _fdd_out _fdd_rc

  # --strict is documented to FAIL on a repo that isn't checked out. It printed red but
  # returned 0, so every caller read the run as clean. The root must EXIST and merely be
  # empty — a missing root is a separate usage error (exit 2) and would mask the regression.
  mkdir -p "$SANDBOX/fdempty"
  env -u CORE_JSON bash "$FDC/scripts/fleet-drift.sh" --root "$SANDBOX/fdempty" --strict --color never >/dev/null 2>&1
  _fdd_strict=$?
  env -u CORE_JSON bash "$FDC/scripts/fleet-drift.sh" --root "$SANDBOX/fdempty" --color never >/dev/null 2>&1
  _fdd_plain=$?
  if [[ $_fdd_strict -eq 1 && $_fdd_plain -eq 0 ]]; then
    pass "drift: --strict fails on a not-checked-out repo, plain mode still skips"
  else fail "drift: --strict exit code wrong (strict=$_fdd_strict plain=$_fdd_plain)"; fi

  # --- a repo RENAMED upstream, still cloned under its old directory name -------
  # The fleet is named by repo NAME (scripts/os-repos.txt) and every fleet script used to
  # turn that name into a path by string-joining it onto the root. So a box that cloned
  # dotfiles-Kali and never renamed the directory after it became dotfiles-Offense reported
  # "not checked out" for a repo sitting right there, fully vendored — a false CLEAN row on
  # the one sweep whose job is to notice staleness, and one `make sync` cannot repair.
  # resolve_repo_dir (scripts/lib/common.sh) falls back to origin's URL, which follows a
  # GitHub rename on its own. Assert the real verdict comes back, not the skip.
  mv "$FDF/dotfiles-Test" "$FDF/dotfiles-OldName"
  git -C "$FDF/dotfiles-OldName" init -q >/dev/null 2>&1
  git -C "$FDF/dotfiles-OldName" remote add origin https://github.com/dotgibson/dotfiles-Test.git
  _fdd_lock2() { printf '%s\n' "$@" >"$FDF/dotfiles-OldName/core.lock"; }
  _fdd_lock2 "core_sha=$FD_REL"
  _fdd_renamed="$(_fdd_run)"; _fdd_ren_rc=$?
  # Two halves, and both matter: the row must classify (proving the clone was FOUND) and it
  # must not still be reported as absent (proving the fallback replaced the skip rather than
  # printing alongside it).
  if ((_fdd_ren_rc == 0)) && grep -qE 'dotfiles-Test.*current' <<<"$_fdd_renamed" &&
    ! grep -qE 'dotfiles-Test.*not checked out' <<<"$_fdd_renamed"; then
    pass "drift: a repo cloned under its PRE-RENAME directory name is found via origin's URL"
  else
    fail "drift: renamed-clone lookup failed (rc=$_fdd_ren_rc; row='$(grep 'dotfiles-Test' <<<"$_fdd_renamed" | head -n1)')"
  fi
  # ...and --strict must not red it either: "NOT CHECKED OUT" is the one drift verdict that
  # sets DRIFT while `make sync` cannot clear it, so a false positive there is an
  # unactionable red build. Asserted on the ROW, not the exit code: fleet-drift.sh also
  # checks dotfiles-Windows unconditionally (line ~383, outside the os-repos loop) and this
  # one-repo fixture root has no such clone, so --strict exits 1 here no matter what the
  # dotfiles-Test row says. An rc assertion would pass for entirely the wrong reason.
  _fdd_strict_ren="$(env -u CORE_JSON bash "$FDC/scripts/fleet-drift.sh" --root "$FDF" --strict --color never 2>&1)"
  if grep -qE 'dotfiles-Test.*current' <<<"$_fdd_strict_ren" &&
    ! grep -qE 'dotfiles-Test.*NOT CHECKED OUT' <<<"$_fdd_strict_ren"; then
    pass "drift: --strict does not red a found-by-URL renamed clone"
  else
    fail "drift: --strict still reported the renamed clone as NOT CHECKED OUT"
  fi
  # An origin that points somewhere ELSE must NOT be adopted — the fallback has to identify
  # the repo, not merely find any clone lying around, or it would silently sync the wrong one.
  git -C "$FDF/dotfiles-OldName" remote set-url origin https://github.com/dotgibson/dotfiles-Unrelated.git
  if grep -qE 'dotfiles-Test.*not checked out' <<<"$(_fdd_run)"; then
    pass "drift: a clone whose origin names a DIFFERENT repo is not adopted"
  else fail "drift: the URL fallback adopted an unrelated repo"; fi
  # THE REGRESSION GATE for #511, same shape and same reason as the sync-core one above.
  # The assertion immediately above is the one that actually broke: it greps for the
  # not-checked-out line, fleet-drift.sh emits that line through skip(), and skip() is silent
  # when CORE_JSON is exported — so `test-core.sh --scope none --json` reported fail:1 on a
  # tree the identical non-JSON run passed clean. Reproduced on an unmodified checkout before
  # the fix. Drive the same fixture with CORE_JSON exported and require the identical verdict:
  # this fails loudly if anyone drops the `-u CORE_JSON` from _fdd_run.
  #
  # An explicit `export` in a subshell, not a `CORE_JSON=1 _fdd_run` prefix — the value must
  # genuinely be EXPORTED or `env -u` has nothing to strip and the gate passes vacuously.
  # shellcheck disable=SC2030,SC2031  # subshell-local by design — the export must NOT
  # outlive this command substitution, or it would silence every later section's skip()
  _fdd_json="$(
    export CORE_JSON=1
    _fdd_run
  )"
  if grep -qE 'dotfiles-Test.*not checked out' <<<"$_fdd_json"; then
    pass "drift: the fixture is insulated from an exported CORE_JSON (--json cannot change the verdict)"
  else
    fail "drift: an exported CORE_JSON silenced fleet-drift's skip() line — --json would red a green tree (#511)"
  fi
  # Restore the fixture: later legs assert on the plain directory, with no remote to find.
  rm -rf "$FDF/dotfiles-OldName/.git"
  mv "$FDF/dotfiles-OldName" "$FDF/dotfiles-Test"

  # Fail-CLOSED leg: with no mainline ref at all, an ahead-only marker is unverifiable and
  # must NOT be waved through as current. Last — it deletes the branch the fixture rides on.
  _fdg checkout -q --detach main
  _fdg branch -D main >/dev/null 2>&1
  _fdd_lock "core_sha=$FD_TIP"
  _fdd_is "drift: ahead with no mainline ref fails closed" 1 'no mainline ref'
else
  skip "fleet drift classifier (git unavailable)"
fi

# ── F6. sync-core.sh — THE fan-out, on hermetic fixtures ─────────────────────
# scripts/sync-core.sh is the highest-blast-radius script here: it gates on the audit,
# runs `git subtree pull` into nine working trees, and stamps core.lock. Until now it
# had NO coverage at all — its only proof was sync-fanout.yml running it for real
# against the live fleet, i.e. the fleet WAS the test.
#
# Everything below is a REFUSAL or an idempotency property. That matters for what these
# tests are worth: a broken guard does not throw, it fans a bad tree out to nine repos
# and reports success. So each case asserts the script DECLINED, and (where the guard is
# per-repo) that it declined without abandoning the repos after it.
#
# The fixture is a miniature of the real topology: `coreremote` is the origin every OS
# repo vendors from, `core` is the local checkout sync-core.sh runs out of ($HERE, as it
# computes from BASH_SOURCE), and `repos/` is REPOS_ROOT. audit-core.sh is STUBBED in the
# fixture so the audit gate can be driven both ways in-process — the real one cannot fail
# on demand.
# `git subtree` is a CONTRIB command, not part of core git: the Alpine/busybox image
# ships git without it, and Debian splits it into a separate git-subtree package. Every
# assertion below needs a real subtree add + pull, so probe for the command itself rather
# than assuming `have git` implies it — otherwise the fixture silently builds an OS repo
# with no core/ and half these tests fail for a reason that has nothing to do with
# sync-core.sh. Probing the exec-path is deterministic; `git subtree --help` can page.
_sc_subtree=0
if have git; then
  if [[ -x "$(git --exec-path 2>/dev/null)/git-subtree" ]] || have git-subtree; then _sc_subtree=1; fi
fi
if ((_sc_subtree)); then
  hdr "sync-core.sh fan-out guards (hermetic fixtures)"
  SCF="$SANDBOX/synccore"
  rm -rf "$SCF"
  mkdir -p "$SCF"
  # Host git config must not reach in: a global commit.gpgsign blocks every fixture
  # commit, and init.defaultBranch decides whether `main` even exists (load-bearing —
  # CORE_BRANCH defaults to main). Same neutralisation the fleet-drift fixture uses.
  _scg() { git -C "$1" -c commit.gpgsign=false -c user.email=t@example.com -c user.name=t "${@:2}"; }
  # sync-core.sh runs `git subtree pull` and `git commit` INSIDE these fixtures with its
  # own argv — it never inherits the -c flags above. A CI runner has no global git
  # identity, so those commits abort with "Please tell me who you are" and the whole
  # fan-out silently produces no core.lock. (A developer machine hides this: the global
  # identity is already set, so it passes locally and fails only on CI.) Stamp the
  # identity into each fixture's LOCAL config so any git invocation inside it can commit.
  _sc_ident() {
    git -C "$1" config user.email t@example.com
    git -C "$1" config user.name t
    git -C "$1" config commit.gpgsign false
  }

  # 1) coreremote — the vendored origin. Carries the REAL sync-core.sh + the libs it
  #    sources, so the code under test is the shipped code, not a copy of its logic.
  mkdir -p "$SCF/coreremote/scripts/lib" "$SCF/coreremote/lib"
  cp "$HERE/scripts/sync-core.sh" "$SCF/coreremote/scripts/"
  # core-lock.sh too: sync-core.sh sources it for its post-fan-out assertion (#556), so
  # without this the whole F6 block dies at `source` rather than failing an assertion.
  cp "$HERE/scripts/lib/common.sh" "$HERE/scripts/lib/core-lock.sh" "$SCF/coreremote/scripts/lib/"
  cp "$HERE/lib/ux.sh" "$HERE/lib/bootstrap-lib.sh" "$SCF/coreremote/lib/"
  printf '9.9.9\n' >"$SCF/coreremote/core.version"
  printf 'dotfiles-Test\ndotfiles-Other\ndotfiles-NotCloned\n' >"$SCF/coreremote/scripts/os-repos.txt"
  printf 'core payload v1\n' >"$SCF/coreremote/payload.txt"
  # The stub audit: exits with whatever $SCF/auditrc says, so a single file flips the
  # pre-fan-out gate between green and red without touching the script under test.
  # The stub also PUSHES TO CORE when $SCF/pushduring exists — which reproduces #556
  # exactly and deterministically: the tip moves strictly between sync-core.sh's up-front
  # `ls-remote` and its per-repo fetch, with no sleeps and no timing dependence. That is
  # the real-world shape (a PR merging while the ~250s pre-fan-out audit runs), and the
  # audit gate is the one place in the run guaranteed to sit inside that window.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'if [ -s "%s/pushduring" ]; then\n' "$SCF"
    printf '  cat "%s/pushduring" > "%s/coreremote/payload.txt"\n' "$SCF" "$SCF"
    printf '  rm -f "%s/pushduring"\n' "$SCF"
    printf '  git -C "%s/coreremote" add -A\n' "$SCF"
    printf '  git -C "%s/coreremote" -c commit.gpgsign=false commit -q -m "core raced" >/dev/null 2>&1\n' "$SCF"
    printf 'fi\n'
    printf 'exit "$(cat "%s/auditrc" 2>/dev/null || echo 0)"\n' "$SCF"
  } >"$SCF/coreremote/scripts/audit-core.sh"
  chmod +x "$SCF/coreremote/scripts/audit-core.sh" "$SCF/coreremote/scripts/sync-core.sh"
  printf '0\n' >"$SCF/auditrc"
  _scg "$SCF/coreremote" init -q >/dev/null 2>&1
  _sc_ident "$SCF/coreremote"
  _scg "$SCF/coreremote" symbolic-ref HEAD refs/heads/main
  _scg "$SCF/coreremote" add -A
  _scg "$SCF/coreremote" commit -q -m "core c0"

  # 2) core — the local checkout sync-core.sh runs from. A clone, so HEAD == remote tip
  #    (the state the local-vs-remote guard demands).
  git -c commit.gpgsign=false clone -q "$SCF/coreremote" "$SCF/core" >/dev/null 2>&1
  _sc_ident "$SCF/core"
  _SCS="$SCF/core/scripts/sync-core.sh"

  # 3) the fleet. dotfiles-Test gets a real core/ subtree; the other two are the
  #    "not cloned" and "no core/ yet" shapes the loop must SKIP rather than fail.
  mkdir -p "$SCF/repos/dotfiles-Other" "$SCF/repos/dotfiles-NotCloned"
  _sc_new_osrepo() { # <name>  — a repo with a real core/ subtree sharing history
    local d="$SCF/repos/$1"
    mkdir -p "$d"
    _scg "$d" init -q >/dev/null 2>&1
    _sc_ident "$d"
    _scg "$d" symbolic-ref HEAD refs/heads/main
    printf 'os layer\n' >"$d/os.txt"
    _scg "$d" add -A
    _scg "$d" commit -q -m "os c0"
    _scg "$d" subtree add -q --prefix=core "$SCF/coreremote" main --squash >/dev/null 2>&1
  }
  _sc_new_osrepo dotfiles-Test
  _scg "$SCF/repos/dotfiles-Other" init -q >/dev/null 2>&1   # a git repo with NO core/
  _sc_ident "$SCF/repos/dotfiles-Other"
  _scg "$SCF/repos/dotfiles-Other" symbolic-ref HEAD refs/heads/main
  rm -rf "$SCF/repos/dotfiles-NotCloned/.git"                 # a dir that is not a repo

  _sc_run() { # run the fixture's sync-core.sh against the fixture fleet
    # -u CORE_JSON: --json EXPORTS CORE_JSON=1 so nested gates keep stdout clean for the
    # JSON object, and common.sh's skip() then prints nothing. The fixture inherits that
    # export, sync-core.sh reports absent / core/-less repos via skip(), and the assertions
    # below grep for exactly those lines — so `audit-core.sh --json` went red on a tree the
    # identical non-JSON run passed (#524). Same guard, same reason, as _tr_run below.
    env -u DOTFILES_ALLOW_CORE_EDIT -u CORE_JSON CORE_COLOR=never \
      REPOS_ROOT="$SCF/repos" CORE_REMOTE="$SCF/coreremote" CORE_BRANCH=main \
      SYNC_JOBS=1 "$@" bash "$_SCS" 2>&1
  }

  # --- the audit gate: the property that a RED tree must never fan out ---------
  # This is the single most important assertion in the file: every other guard protects
  # one repo, this one protects all nine. It must also refuse BEFORE mutating anything.
  printf '1\n' >"$SCF/auditrc"
  _sc_head_before="$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)"
  _sc_out="$(_sc_run)"; _sc_rc=$?
  if ((_sc_rc != 0)) && grep -q 'refusing to fan out a red tree' <<<"$_sc_out"; then
    pass "sync-core: a RED audit refuses the fan-out (rc=$_sc_rc)"
  else
    fail "sync-core: a red audit did NOT stop the fan-out (rc=$_sc_rc)"
  fi
  # ...and it refused BEFORE touching anything. HEAD alone is too weak a claim: a
  # regression that WROTE core.lock or staged a file before returning would leave HEAD
  # unchanged and still pass. Require the working tree to be clean as well.
  if [[ "$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)" == "$_sc_head_before" ]] &&
    [[ -z "$(_scg "$SCF/repos/dotfiles-Test" status --porcelain)" ]]; then
    pass "sync-core: the red-audit refusal happens before any repo is mutated"
  else
    fail "sync-core: a repo was written to or moved despite the red-audit refusal"
  fi
  printf '0\n' >"$SCF/auditrc"

  # --- the local-vs-remote guard ----------------------------------------------
  # subtree pull fetches the REMOTE tip, but the audit above validated the LOCAL tree.
  # Advance the remote so the two disagree; the run must refuse rather than vendor a
  # commit nobody audited.
  printf 'core payload v2\n' >"$SCF/coreremote/payload.txt"
  _scg "$SCF/coreremote" commit -q -am "core c1"
  _sc_out="$(_sc_run)"; _sc_rc=$?
  if ((_sc_rc != 0)) && grep -q 'local HEAD' <<<"$_sc_out"; then
    pass "sync-core: local HEAD != remote tip refuses (audited tree != vendored tree)"
  else
    fail "sync-core: local/remote mismatch was not caught (rc=$_sc_rc)"
  fi
  _scg "$SCF/core" pull -q --ff-only >/dev/null 2>&1   # realign for the runs below

  # --- skip vs fail: an absent repo is not a failure ---------------------------
  _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1)"
  # Both names appearing is not the property — they would still appear if either branch
  # were changed from skip() to err(). Assert the SUMMARY BUCKETS: two skipped, none
  # failed. That is the distinction that decides whether a missing clone reds a fan-out.
  if grep -q 'dotfiles-NotCloned' <<<"$_sc_out" && grep -qE 'dotfiles-Other.*no core/' <<<"$_sc_out" &&
    grep -qE 'skipped 2' <<<"$_sc_out" && grep -qE 'failed 0' <<<"$_sc_out"; then
    pass "sync-core: uncloned repo and core/-less repo land in the SKIPPED bucket, not failed"
  else
    fail "sync-core: absent/core-less repos not counted as skips (want skipped 2 / failed 0)"
  fi
  # THE REGRESSION GATE for #524, and the reason it is here rather than in a --json test:
  # the bug was invisible from inside a normal run. Both assertions above pass under a bare
  # `test-core.sh` and fail only when the parent was invoked with --json, so the suite
  # certified sync-core's bucketing while `audit-core.sh --json` reported the tree red.
  #
  # Drive the SAME fixture with CORE_JSON=1 exported — exactly what --json does — and require
  # the identical verdict. This fails loudly if anyone drops the `-u CORE_JSON` above, and it
  # costs one extra fixture run rather than a recursive audit.
  #
  # Asserted on the skip LINES, not just the summary counts: the counts are printed by
  # sync-core.sh's own printf and would survive a silenced skip(), so a count-only assertion
  # would go on passing through precisely this bug.
  # An explicit `export` inside a subshell, not a `CORE_JSON=1 _sc_run` prefix. The value must
  # genuinely be EXPORTED or `env -u` has nothing to strip and the gate passes vacuously; and a
  # prefix assignment on a FUNCTION call is the one form whose persistence bash and POSIX mode
  # disagree about, so it could leak CORE_JSON into every later section and silence their skips.
  # shellcheck disable=SC2030,SC2031  # subshell-local by design, as above
  _sc_out="$(
    export CORE_JSON=1
    _sc_run SYNC_SKIP_AUDIT=1
  )"
  if grep -q 'dotfiles-NotCloned' <<<"$_sc_out" && grep -qE 'dotfiles-Other.*no core/' <<<"$_sc_out" &&
    grep -qE 'skipped 2' <<<"$_sc_out" && grep -qE 'failed 0' <<<"$_sc_out"; then
    pass "sync-core: the fixture is insulated from an exported CORE_JSON (--json cannot change the verdict)"
  else
    fail "sync-core: an exported CORE_JSON silenced the fixture's skip() lines — --json would red a green tree (#524)"
  fi

  # --- dotfiles-Windows is never a target -------------------------------------
  # It vendors no core/ (its host layer is native PowerShell), so fanning into it would
  # be wrong, not merely useless. Since #669 the data file is the ONLY place it could be
  # wrongly added — the second clause here used to grep sync-core.sh's ALL_OS_REPOS array,
  # which no longer exists and would now pass vacuously. Assert the SHIPPED data file, not
  # the fixture's.
  if ! grep -qE '^[[:space:]]*dotfiles-Windows[[:space:]]*$' "$HERE/scripts/os-repos.txt"; then
    pass "sync-core: dotfiles-Windows is not in the fleet file"
  else
    fail "sync-core: dotfiles-Windows would be fanned into (it carries no core/ subtree)"
  fi

  # --- an unusable fleet list STOPS the fan-out, it does not degrade -----------
  # The whole point of #669. sync-core.sh used to fall back to a hardcoded nine-name array
  # when scripts/os-repos.txt was missing — the one moment nobody could see it — so a repo
  # registered in the file alone silently vanished from the fan-out. Now it exits 2 and
  # touches nothing. Driven for real rather than asserted by grep: a comment claiming the
  # script fails closed is exactly what the old fallback's comment also claimed.
  _sc_fleet_file="$SCF/core/scripts/os-repos.txt"
  _sc_fleet_body="$(cat "$_sc_fleet_file")"
  _sc_head_pre="$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)"
  for _sc_case in absent empty; do
    case "$_sc_case" in
    absent) rm -f "$_sc_fleet_file" ;;
    # Comments-only is the same hazard as absent and a far likelier edit slip: the reader
    # would yield zero names and the sweep would report a clean fleet of nobody.
    empty) printf '# every entry commented out\n\n' >"$_sc_fleet_file" ;;
    esac
    _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1)"
    _sc_rc=$?
    if [[ "$_sc_rc" == 2 ]] && grep -qE 'fleet list (unreadable|is empty)' <<<"$_sc_out" &&
      [[ "$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)" == "$_sc_head_pre" ]]; then
      pass "sync-core: an $_sc_case fleet list exits 2 and fans out into nothing"
    else
      fail "sync-core: an $_sc_case fleet list did not stop the fan-out (rc=$_sc_rc, want 2) — the maintain button degraded silently"
    fi
  done
  printf '%s\n' "$_sc_fleet_body" >"$_sc_fleet_file"

  # Naming targets on the CLI must NOT need the fleet list — the file describes the default
  # fan-out, not the argument parser, and coupling the two would make a broken data file
  # block the one-repo recovery sync you reach for to fix it.
  # Called directly, not through _sc_run: that helper appends its "$@" as env-var prefixes
  # BEFORE `bash`, so it cannot carry script arguments. --dry-run keeps this hermetic — the
  # fleet load happens during target selection either way, which is the thing under test.
  rm -f "$_sc_fleet_file"
  _sc_out="$(env -u DOTFILES_ALLOW_CORE_EDIT -u CORE_JSON CORE_COLOR=never \
    REPOS_ROOT="$SCF/repos" CORE_REMOTE="$SCF/coreremote" CORE_BRANCH=main SYNC_JOBS=1 \
    bash "$_SCS" --dry-run dotfiles-Test 2>&1)" || true
  if grep -q 'dotfiles-Test' <<<"$_sc_out" && ! grep -qE 'fleet list (unreadable|is empty)' <<<"$_sc_out"; then
    pass "sync-core: an explicitly named target still syncs with no fleet list present"
  else
    fail "sync-core: a named target was blocked by the missing fleet list it does not need"
  fi
  printf '%s\n' "$_sc_fleet_body" >"$_sc_fleet_file"
  unset _sc_fleet_file _sc_fleet_body _sc_head_pre _sc_case _sc_rc

  # --- the fleet list is the single source, and no copy has grown back ---------
  # This REPLACES the old four-way agreement assertion (#669). sync-core.sh, fleet-drift.sh
  # and core-integrity.sh each used to carry a hardcoded fallback array, and this suite
  # asserted the four agreed — a backstop for a design flaw rather than a fix. The arrays
  # are gone; what is worth policing now is that they stay gone, and that the one remaining
  # source is actually loadable. Three assertions, in that order.
  if load_os_repos; then
    pass "fleet list: scripts/os-repos.txt is readable and names ${#CORE_OS_REPOS[@]} repo(s)"
  else
    fail "fleet list: $CORE_OS_REPOS_ERR — every fleet script now hard-fails on this"
  fi

  for _fb_file in sync-core.sh fleet-drift.sh core-integrity.sh; do
    if grep -q 'load_os_repos' "$HERE/scripts/$_fb_file"; then
      pass "$_fb_file: reads the fleet through load_os_repos (lib/common.sh)"
    else
      fail "$_fb_file: no longer calls load_os_repos — it has its own fleet reader again"
    fi
    # Two fleet names on one line, comments stripped: the signature of a pasted-back array,
    # and it catches the `for r in a b c` shape as well as a `VAR=(…)` literal.
    # Deliberately not a bare `dotfiles-[A-Za-z]+` scan — sync-core.sh legitimately carries
    # the `dotfiles-*)` arg glob and a `dotfiles-Fedora` example, and a check that cannot
    # tell those from an array is a check nobody will keep. Usage lines are dropped too: an
    # example INVOKING the script ("sync-core.sh dotfiles-Fedora dotfiles-Arch") is prose
    # that happens to name two repos, and reporting it as a re-grown array would be a false
    # positive whose message actively misleads. Names may contain digits and further hyphens;
    # the old assertion's `^dotfiles-[A-Za-z]+$` would have silently dropped such a repo and
    # reported false DRIFT, so do not narrow this back.
    if sed -e 's/#.*//' -e "/$_fb_file/d" "$HERE/scripts/$_fb_file" |
      grep -qE 'dotfiles-[A-Za-z0-9-]+[[:space:]]+dotfiles-[A-Za-z0-9-]+'; then
      fail "$_fb_file: a hardcoded fleet list has grown back — scripts/os-repos.txt is the only source"
    else
      pass "$_fb_file: carries no hardcoded fleet list of its own"
    fi
  done
  unset _fb_file

  # --- --dry-run mutates nothing ----------------------------------------------
  _sc_head_before="$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)"
  # -u CORE_JSON for the same reason as _sc_run (#524). This call site does not currently
  # assert on skip() output, so it was not failing — but it is the identical trap one
  # assertion away, and a guard applied only where it already hurts is how this one got in.
  _sc_out="$(env -u DOTFILES_ALLOW_CORE_EDIT -u CORE_JSON CORE_COLOR=never REPOS_ROOT="$SCF/repos" \
    CORE_REMOTE="$SCF/coreremote" CORE_BRANCH=main SYNC_JOBS=1 bash "$_SCS" --dry-run 2>&1)"
  # 'would: materialize' since #587 — the plan line stopped naming `git subtree pull`
  # when the sync stopped BEING one. Matched on the verb rather than the whole line so
  # this pins "a plan was printed", not the sentence's punctuation.
  if grep -q 'would: materialize' <<<"$_sc_out" &&
    [[ "$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)" == "$_sc_head_before" ]] &&
    [[ -z "$(_scg "$SCF/repos/dotfiles-Test" status --porcelain)" ]]; then
    pass "sync-core: --dry-run prints the plan and writes nothing"
  else
    fail "sync-core: --dry-run mutated the target or printed no plan"
  fi

  # --- the real pull: core.lock lands at the ROOT and records the full sha -----
  _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1)"
  _sc_lock="$SCF/repos/dotfiles-Test/core.lock"
  _sc_remote_sha="$(_scg "$SCF/coreremote" rev-parse main)"
  if [[ -f "$_sc_lock" ]] && ! [[ -e "$SCF/repos/dotfiles-Test/core/core.lock" ]]; then
    pass "sync-core: core.lock is written at the repo ROOT (a subtree pull cannot clobber it)"
  else
    fail "sync-core: core.lock is missing or landed inside core/"
  fi
  if grep -q "^core_sha=$_sc_remote_sha\$" "$_sc_lock" &&
    grep -q '^core_version=9.9.9$' "$_sc_lock" && grep -q '^core_ref=main$' "$_sc_lock"; then
    pass "sync-core: core.lock records the FULL vendored sha, version and ref"
  else
    fail "sync-core: core.lock contents wrong ($(tr '\n' ' ' <"$_sc_lock"))"
  fi
  # The field must NOT be called core_branch any more (#453) — it was written from
  # $CORE_BRANCH, which sync-fanout.yml deliberately sets to a pinned SHA, so a field
  # documented as a branch held a commit and duplicated core_sha. Assert the old name is
  # gone rather than only that the new one is present: emitting BOTH would satisfy the
  # check above while leaving the contradicting field in every OS repo's lock file.
  if ! grep -q '^core_branch=' "$_sc_lock"; then
    pass "sync-core: core.lock no longer emits the mislabelled core_branch field"
  else
    fail "sync-core: core.lock still emits core_branch"
  fi
  # The tree must be CLEAN afterwards, or the dirty-tree guard blocks the next run —
  # the self-inflicted deadlock the core.lock commit exists to prevent.
  if [[ -z "$(_scg "$SCF/repos/dotfiles-Test" status --porcelain)" ]]; then
    pass "sync-core: the target tree is clean after a sync (next run is not self-blocked)"
  else
    fail "sync-core: sync left the target dirty — the next run would refuse it"
  fi

  # --- idempotency: re-syncing the same sha must not manufacture a commit ------
  _sc_head_before="$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)"
  _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1)"
  if grep -q 'core.lock current' <<<"$_sc_out" &&
    [[ "$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)" == "$_sc_head_before" ]]; then
    pass "sync-core: re-syncing an unchanged sha is a no-op (no empty core.lock commit)"
  else
    fail "sync-core: a no-change re-sync still moved HEAD"
  fi

  # --- a sync must NOT depend on the subtree trailer surviving (#587) ------------
  # THE REGRESSION THIS EXISTS FOR, and it is not hypothetical: it took the v4.15.0
  # fan-out down in 9 repos out of 9, simultaneously.
  #
  # `git subtree pull --squash` finds its base by grepping history for the previous sync
  # commit's `git-subtree-split:` trailer. Every fleet repo SQUASH-merges its fan-out PR
  # (RELEASE-STRATEGY.md), and a squash keeps the original body only if it happens to be
  # carried over — so the trailer dies intermittently. Seven of nine repos had lost it
  # after the v4.14.3 round.
  #
  # The damage is not a missing marker, it is a WRONG BASE. Reproducing that needs TWO
  # prior syncs, not one: destroy the NEWEST trailer and subtree falls back to the one
  # before it, then replays both rounds of changes onto a tree that already contains the
  # first — so any file touched by BOTH rounds conflicts. That is why CHANGELOG.md and
  # core.version (which every release rewrites) were the two casualties in the real
  # failure, and why payload.txt is rewritten in both rounds here.
  #
  # Materializing the tree has no base and no trailer to lose.
  # 'v2-round2', NOT 'v2': the local-vs-remote guard section above already wrote the exact
  # bytes 'core payload v2' to this file and committed them, so re-writing them here staged
  # nothing and `commit -q` was a NO-OP. That cost two things. It printed git's "nothing to
  # commit, working tree clean" to STDOUT — where --json promises the JSON object and nothing
  # else, so the machine-readable mode this section's own sibling fixtures exist to protect
  # was itself unparseable. And it quietly hollowed out this fixture: with no round-2 commit
  # the remote never moved, so round 2's sync was a no-op too and the "TWO prior syncs" the
  # comment above insists on were only ever one. The content must differ from BOTH the value
  # already vendored and the v3 written below.
  printf 'core payload v2-round2\n' >"$SCF/coreremote/payload.txt"
  _scg "$SCF/coreremote" add -A >/dev/null 2>&1
  _scg "$SCF/coreremote" commit -q -m 'core: payload v2-round2'
  _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1)"   # round 2 — this is the sync whose trailer dies
  # Destroy the trailer the way a squash-merge does — from EVERY commit, not just HEAD.
  # Amending HEAD alone is not enough and quietly proves nothing: under the old
  # `subtree pull` a sync round produced TWO commits (the squash, then core.lock), so
  # amending HEAD rewrote the lock commit and left the subtree marker untouched. Stripping
  # the trailer repo-wide is both the honest reproduction (a fleet repo can lose it on any
  # round) and what makes the assertion below able to fail.
  FILTER_BRANCH_SQUELCH_WARNING=1 _scg "$SCF/repos/dotfiles-Test" \
    filter-branch -f --msg-filter 'sed "/^git-subtree-/d"' -- --all >/dev/null 2>&1
  if _scg "$SCF/repos/dotfiles-Test" log --format=%B | grep -q 'git-subtree-split'; then
    fail "sync-core (#587 fixture): could not destroy the trailer — the test below would prove nothing"
  else
    printf 'core payload v3\n' >"$SCF/coreremote/payload.txt"   # SAME file round 2 touched
    _scg "$SCF/coreremote" add -A >/dev/null 2>&1
    _scg "$SCF/coreremote" commit -q -m 'core: payload v3'
    _sc_v3_sha="$(_scg "$SCF/coreremote" rev-parse main)"
    _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1)"                        # round 3 — the one that broke
    _sc_587=""
    grep -qi 'conflict' <<<"$_sc_out" && _sc_587="$_sc_587 conflicted"
    grep -q 'failed 0' <<<"$_sc_out" || _sc_587="$_sc_587 repo-failed"
    # The payload must actually have moved — a sync that "succeeded" without updating the
    # tree would satisfy the two checks above and be exactly as broken.
    [[ "$(cat "$SCF/repos/dotfiles-Test/core/payload.txt" 2>/dev/null)" == 'core payload v3' ]] ||
      _sc_587="$_sc_587 payload-stale"
    grep -q "^core_sha=$_sc_v3_sha\$" "$_sc_lock" || _sc_587="$_sc_587 lock-stale"
    if [[ -z "$_sc_587" ]]; then
      pass "sync-core: a sync succeeds with the subtree trailer DESTROYED (#587 — the v4.15.0 fan-out failure)"
    else
      fail "sync-core: trailer-less sync regressed —$_sc_587"
    fi
    # And the tree must be clean afterwards, or the next run self-blocks on the dirty guard.
    if [[ -z "$(_scg "$SCF/repos/dotfiles-Test" status --porcelain)" ]]; then
      pass "sync-core: the trailer-less sync leaves a clean tree (one atomic commit)"
    else
      fail "sync-core: the trailer-less sync left the target dirty"
    fi
  fi

  # --- core_ref records the ref that was FOLLOWED, branch or pinned commit (#453) --
  # The bug this pins: sync-fanout.yml sets CORE_BRANCH="$target_sha" on purpose, so each
  # release PR vendors the exact released commit rather than a moving main — and the value
  # was then persisted into a field named, and documented, as a *branch*. Every OS repo's
  # lock file ended up with core_branch == core_sha: a contract violation, and a field
  # carrying no information core_sha did not already have.
  #
  # The run above covers the branch half (core_ref=main). This covers the half that was
  # actually wrong, by driving the script the way the fan-out drives it.
  _sc_pin_sha="$(_scg "$SCF/coreremote" rev-parse main)"
  _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1 CORE_BRANCH="$_sc_pin_sha")"
  if grep -q "^core_ref=$_sc_pin_sha\$" "$_sc_lock"; then
    pass "sync-core: a pinned-SHA sync records that commit as core_ref (the fan-out shape)"
  else
    fail "sync-core: core_ref did not record the pinned sha ($(grep '^core_ref=' "$_sc_lock" || echo absent))"
  fi

  # --- the dirty-tree guard, and that it does not abandon the rest of the fleet -
  # Ordering matters here: dotfiles-Test sorts BEFORE dotfiles-Other in the fixture fleet
  # file, so if a dirty first repo aborted the loop the second would never be reached.
  printf 'uncommitted\n' >"$SCF/repos/dotfiles-Test/dirty.txt"
  _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1)"
  # Asserted on the ✗ line and the SUMMARY, deliberately NOT on $?. sync-core.sh exits
  # ZERO here: the failure branch prints "done with failures" to stderr but never sets a
  # status. That is load-bearing rather than an oversight to "fix" in passing —
  # sync-fanout.yml runs this under `bash -e` and then does its OWN per-repo
  # post-condition check, so a non-zero exit would abort that step and stop it opening PRs
  # for the repos that DID sync. Pinning the observable contract here keeps the test honest
  # about what the script actually promises; whether $? should also be non-zero is a design
  # call. That post-condition is now THREE assertions, not two — core.lock pins the released
  # sha, the branch is ≥1 commit ahead, and every dotgibson/dotfiles-core 40-hex pin in
  # .github/workflows/* equals the target (#484). The third was added because the first two
  # are both satisfied by a repo whose pin rewrite FAILED: err() flips it into the failed
  # bucket here, but that verdict cannot cross the exit-0 boundary, and core.lock is
  # deliberately committed anyway. The fan-out now checks the artefact rather than trusting
  # this script's report — which is what makes keeping exit 0 safe.
  if grep -q 'has uncommitted changes' <<<"$_sc_out" &&
    grep -qE 'failed 1' <<<"$_sc_out"; then
    pass "sync-core: a dirty target is refused and counted failed (not stashed, not force-merged)"
  else
    fail "sync-core: a dirty target was not refused/counted"
  fi
  if grep -q 'dotfiles-Other' <<<"$_sc_out"; then
    pass "sync-core: a dirty repo does not abandon the repos after it"
  else
    fail "sync-core: the fan-out stopped at the first dirty repo"
  fi
  rm -f "$SCF/repos/dotfiles-Test/dirty.txt"

  # --- the THIRD Core reference: reusable-workflow SHA pins (#482) -------------
  # A repo names the vendored Core in three places — the core/ subtree, core.lock, and the
  # `uses:` pins of any SHA-pinned reusable caller. The sync wrote two and left the third,
  # so a fan-out produced a tree that VENDORED one Core and RAN another, with both existing
  # the gate green (core-integrity compares a tree object and never reads a workflow). It reached production on the v4.12.0 fan-out and only surfaced because
  # dotfiles-MacBook had built its own pin gate.
  #
  # Tag the fixture Core first: the comment rewrite is driven by core.lock's core_tag, so
  # without a tag that half of the contract would go untested (and core_tag untested too).
  #
  # TWO tags on ONE commit, in release order, because that is the shape that broke (#515).
  # Every real cut writes the specific vX.Y.Z and then re-points the moving major alias, so
  # the alias is the NEWER tag — and a bare `git describe --tags` picks it. On v4.15.1 it did,
  # and all nine repos stamped `core_tag=v4`: a provenance field naming a target that moves on
  # the next release, which then became the `# v4` comment on every rewritten pin, i.e. a
  # Renovate bump target that never changes. Reproduced here: without the vX.Y.Z shape filter
  # in sync-core.sh, describe returns `v9` and both assertions below go red.
  _scg "$SCF/coreremote" tag -f v9.9.9 >/dev/null 2>&1
  _scg "$SCF/coreremote" tag -f v9 >/dev/null 2>&1
  _scg "$SCF/core" fetch -q --tags origin >/dev/null 2>&1
  _sc_remote_sha="$(_scg "$SCF/coreremote" rev-parse main)"
  _sc_oldsha=0123456789abcdef0123456789abcdef01234567
  _sc_wf="$SCF/repos/dotfiles-Test/.github/workflows"
  mkdir -p "$_sc_wf"
  # Four shapes: the first two must move, the last two must NOT.
  printf 'jobs:\n  t:\n    uses: dotgibson/dotfiles-core/.github/workflows/auto-tag-call.yml@%s # v9.0.0\n' \
    "$_sc_oldsha" >"$_sc_wf/pinned-with-comment.yml"
  printf 'jobs:\n  n:\n    uses: dotgibson/dotfiles-core/.github/workflows/notify-web-call.yml@%s\n' \
    "$_sc_oldsha" >"$_sc_wf/pinned-no-comment.yml"
  printf 'jobs:\n  l:\n    uses: dotgibson/dotfiles-core/.github/workflows/lint-call.yml@v4\n' \
    >"$_sc_wf/mutable-alias.yml"
  printf 'jobs:\n  c:\n    uses: actions/checkout@%s # v4.2.2\n' \
    "$_sc_oldsha" >"$_sc_wf/third-party.yml"
  # ...and the nastier variant: a NON-Core reference already sitting at the exact sha we
  # are syncing to. A third-party action can be pinned there by coincidence and a FORK of
  # this repo by construction. The sha pass is scoped to the dotgibson/dotfiles-core
  # prefix, so it never moved these — but the comment pass was addressed on the bare sha
  # and rewrote their `# vX.Y.Z` to our tag, falsifying a version claim on someone else's
  # action. Two files: neither prefix matches, and their comments must survive verbatim.
  printf 'jobs:\n  s:\n    uses: someorg/someaction@%s # v1.2.3\n' \
    "$_sc_remote_sha" >"$_sc_wf/third-party-same-sha.yml"
  printf 'jobs:\n  k:\n    uses: someonelse/dotfiles-core/.github/workflows/lint-call.yml@%s # v9.0.0\n' \
    "$_sc_remote_sha" >"$_sc_wf/forked-core.yml"
  _scg "$SCF/repos/dotfiles-Test" add -A
  _scg "$SCF/repos/dotfiles-Test" commit -q -m "ci: pinned callers"
  _sc_head_before="$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)"
  _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1)"

  if grep -q "@${_sc_remote_sha} # v9.9.9\$" "$_sc_wf/pinned-with-comment.yml"; then
    pass "sync-core: a SHA-pinned caller is repointed at the vendored Core, comment and all"
  else
    fail "sync-core: pinned caller not repointed ($(grep -o '@[^ ]*.*' "$_sc_wf/pinned-with-comment.yml"))"
  fi
  # The lock side of the same property. Asserted separately from the pin comment above
  # because the two can diverge: core_tag is written even by a repo that SHA-pins nothing,
  # and fleet-drift renders it as the RECORDED column, so `v9` here would make the fleet
  # dashboard answer "which Core?" with "9.x" for every repo (#515).
  if grep -q '^core_tag=v9\.9\.9$' "$_sc_lock"; then
    pass "sync-core: core.lock stamps the SPECIFIC release tag, not the moving major alias"
  else
    fail "sync-core: core.lock core_tag is '$(grep '^core_tag=' "$_sc_lock" || echo '(absent)')', want v9.9.9"
  fi
  # No comment in, no comment out: inventing one would hand Renovate a version claim the
  # repo never made.
  if grep -q "@${_sc_remote_sha}\$" "$_sc_wf/pinned-no-comment.yml"; then
    pass "sync-core: a pin with no version comment gets the sha moved and no comment invented"
  else
    fail "sync-core: comment-less pin mishandled ($(cat "$_sc_wf/pinned-no-comment.yml"))"
  fi
  # The two must-not-touch cases. `@v4` is a deliberate per-repo policy (8 of the 9 repos take
  # the moving alias); converting it to a SHA pin would change that repo's update model
  # behind its back. And a third-party action pinned to a sha with a `# vX.Y.Z` comment has
  # exactly the shape of our own pins — rewriting it would point actions/checkout at a
  # dotfiles-core commit, which is the worst outcome in this whole block.
  if grep -q '@v4$' "$_sc_wf/mutable-alias.yml"; then
    pass "sync-core: a caller on the mutable @v4 alias is left alone (policy is the repo's)"
  else
    fail "sync-core: the @v4 alias was rewritten into a SHA pin"
  fi
  if grep -q "actions/checkout@${_sc_oldsha} # v4.2.2\$" "$_sc_wf/third-party.yml"; then
    pass "sync-core: a third-party action pinned in the same shape is untouched"
  else
    fail "sync-core: a non-dotfiles-core action was rewritten ($(cat "$_sc_wf/third-party.yml"))"
  fi
  # The case the first version of this fixture missed: pinning the OLD sha made every
  # non-Core file trivially out of scope, so a comment pass addressed on the bare sha
  # looked correct. These two sit at the sha being synced TO.
  if grep -q "someorg/someaction@${_sc_remote_sha} # v1.2.3\$" "$_sc_wf/third-party-same-sha.yml" &&
    grep -q "someonelse/dotfiles-core/.github/workflows/lint-call.yml@${_sc_remote_sha} # v9.0.0\$" "$_sc_wf/forked-core.yml"; then
    pass "sync-core: a third-party action and a FORK already at the synced sha keep their own version comments"
  else
    fail "sync-core: a non-Core reference at the synced sha had its version comment rewritten"
  fi
  # The pins must land in the SAME commit as core.lock: landing them apart leaves a window
  # where the repo's own pin gate is red on main.
  if [[ "$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)" != "$_sc_head_before" ]] &&
    [[ -z "$(_scg "$SCF/repos/dotfiles-Test" status --porcelain)" ]] &&
    _scg "$SCF/repos/dotfiles-Test" show --stat --oneline HEAD | grep -q 'core.lock' &&
    _scg "$SCF/repos/dotfiles-Test" show --stat --oneline HEAD | grep -q 'pinned-with-comment.yml'; then
    pass "sync-core: pins and core.lock land in ONE commit, leaving the tree clean"
  else
    fail "sync-core: pins/core.lock were not committed together (or left the tree dirty)"
  fi
  # The regression the staged-wide check exists for: core.lock is now current, so a
  # core.lock-scoped idempotency test would report "current" and silently skip a stale pin.
  sed -i.bak "s|@${_sc_remote_sha}|@${_sc_oldsha}|" "$_sc_wf/pinned-with-comment.yml"
  rm -f "$_sc_wf/pinned-with-comment.yml.bak"
  _scg "$SCF/repos/dotfiles-Test" commit -q -a -m "ci: regress the pin"
  _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1)"
  if grep -q "@${_sc_remote_sha} # v9.9.9\$" "$_sc_wf/pinned-with-comment.yml"; then
    pass "sync-core: a stale pin is fixed even when core.lock is already current"
  else
    fail "sync-core: stale pin left behind because core.lock needed no change"
  fi
  # ...and re-syncing an already-correct repo still manufactures nothing.
  _sc_head_before="$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)"
  _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1)"
  if [[ "$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)" == "$_sc_head_before" ]]; then
    pass "sync-core: a repo whose pins and core.lock are both current gets no empty commit"
  else
    fail "sync-core: an already-correct repo still produced a commit"
  fi
  # A rewrite that CANNOT run must fail the repo, not read as "no pins here". Swallowed,
  # it would let the run commit core.lock and report the repo synced while a caller still
  # pointed at the previous Core — this fix's own error path recreating the drift it
  # exists to end. Root ignores the mode bits, so the CI legs that run as root skip it
  # rather than assert a property they cannot create.
  if [[ "$(id -u)" -ne 0 ]]; then
    chmod a-w "$_sc_wf"
    _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1)"
    chmod u+w "$_sc_wf"
    if grep -q 'pin rewrite failed' <<<"$_sc_out" && grep -qE 'failed 1' <<<"$_sc_out"; then
      pass "sync-core: an unwritable workflow fails the repo instead of reading as 'no pins'"
    else
      fail "sync-core: a pin-rewrite failure was swallowed (want the named file and failed 1)"
    fi
  else
    skip "sync-core: unwritable-workflow case (suite is running as root)"
  fi

  # ── #556: a push to Core DURING the run must not desync core/ from core.lock ──
  # sync-core.sh resolves the tip once up front, then audits (~250s on a real fleet), then
  # vendors. It used to re-resolve the BRANCH at vendor time, so a push inside that window
  # gave core/ the new tree while core.lock recorded the old sha. `make core-integrity`
  # then reported TAMPERED (core/ edited since sync) — for a tree nobody hand-edited,
  # which is the part that cost the most time to diagnose. Observed three times in one
  # afternoon on a normally-active day.
  #
  # Note the local-HEAD guard cannot see this: $SCF/core is still at the pre-push tip, so
  # it agrees with the up-front resolution. That is exactly why the bug shipped.
  _sc_race_n=0
  _sc_race_check() { # _sc_race_check <label-suffix> [ENV=VAL ...]  — extra env goes to _sc_run
    local want_sha want_tree got_tree locked payload trailer pre token
    _scg "$SCF/core" pull -q --ff-only >/dev/null 2>&1 || true
    want_sha="$(_scg "$SCF/coreremote" rev-parse HEAD)"
    want_tree="$(_scg "$SCF/coreremote" rev-parse "${want_sha}^{tree}")"
    # The payload as it stands BEFORE this race — that is what must end up vendored. A
    # fixed marker string will not do: the previous case's race commit becomes this one's
    # baseline, so the second run would compare a value against itself and pass vacuously
    # while no race had actually occurred.
    pre="$(cat "$SCF/coreremote/payload.txt")"
    _sc_race_n=$((_sc_race_n + 1))
    token="core payload RACED-$_sc_race_n"
    printf '0\n' >"$SCF/auditrc"   # ensure the gate is green for this run
    printf '%s\n' "$token" >"$SCF/pushduring"
    _sc_out="$(_sc_run "${@:2}")"; _sc_rc=$?
    payload="$(cat "$SCF/repos/dotfiles-Test/core/payload.txt" 2>/dev/null || echo MISSING)"
    locked="$(sed -n 's/^core_sha=//p' "$SCF/repos/dotfiles-Test/core.lock" 2>/dev/null)"
    got_tree="$(_scg "$SCF/repos/dotfiles-Test" rev-parse 'HEAD:core')"
    trailer="$(_scg "$SCF/repos/dotfiles-Test" log -1 --format=%B | sed -n 's/^git-subtree-split: //p')"

    if [[ "$payload" == "$pre" ]] && [[ "$payload" != *"$token"* ]] \
      && [[ "$locked" == "$want_sha" ]] \
      && [[ "$got_tree" == "$want_tree" ]] && grep -qE 'failed 0' <<<"$_sc_out"; then
      pass "sync-core: a push to Core during the audit does not desync core/ from core.lock ($1)"
    else
      fail "sync-core: #556 race — core/ and core.lock disagree ($1)"
      printf '    payload=%s\n    expected=%s\n    raced-in=%s\n    locked=%s want=%s\n    tree=%s want=%s\n' \
        "$payload" "$pre" "$token" "${locked:0:12}" "${want_sha:0:12}" \
        "${got_tree:0:12}" "${want_tree:0:12}" >&2
    fi
    # The subtree trailer is a THIRD artefact stamped from the same snapshot; consumer
    # tooling (dotfiles-MacBook's verify-core) warns when it disagrees with the lock.
    if [[ "$trailer" == "$want_sha" || -z "$trailer" ]]; then
      pass "sync-core: the git-subtree-split trailer names the vendored commit ($1)"
    else
      fail "sync-core: trailer ${trailer:0:12} != vendored ${want_sha:0:12} ($1)"
    fi
    # The assertion must have RUN and been GREEN — otherwise everything above could hold
    # while the guard itself is dead code that would never catch a future regression.
    if grep -q 'core/ verified ==' <<<"$_sc_out"; then
      pass "sync-core: the post-fan-out tree-vs-lock assertion runs and passes ($1)"
    else
      fail "sync-core: the post-fan-out assertion did not run, or ran and failed ($1)"
    fi
    rm -f "$SCF/pushduring"
  }

  # A: the direct-SHA fetch path. GitHub sets uploadpack.allowReachableSHA1InWant, and the
  #    release fan-out already relies on it (sync-fanout.yml pins CORE_BRANCH to a raw sha).
  _scg "$SCF/coreremote" config uploadpack.allowReachableSHA1InWant true
  _sc_race_check "direct-sha fetch"

  # B: the SAME assertions with that config OFF, so the ref-fetch fallback is exercised.
  #    This is the case that catches a fallback written against FETCH_HEAD — which would
  #    re-create #556 inside the fix, since FETCH_HEAD is the new tip by definition.
  _scg "$SCF/coreremote" config --unset uploadpack.allowReachableSHA1InWant || true
  _sc_race_check "ref-fetch fallback"

  # C: with the parallel prefetch on. A warm-up that fetched the moving BRANCH could
  #    smuggle the newer tip into the object store and have read-tree pick it up. SYNC_JOBS
  #    is passed through _sc_run's env-prefix parameter, which the outer runner already
  #    supports — overriding it wins over the SYNC_JOBS=1 baked into the runner.
  _scg "$SCF/coreremote" config uploadpack.allowReachableSHA1InWant true
  _sc_race_check "SYNC_JOBS=4 prefetch" SYNC_JOBS=4

  # ── #556: an unresolvable Core must hard-fail BEFORE anything is written ──────
  # Previously `unknown` was tolerated: the run materialized core/ from the branch and
  # skipped core.lock entirely — a second, race-free producer of the same TAMPERED state.
  _sc_head_before="$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)"
  _sc_out="$(_sc_run CORE_REMOTE="$SCF/nope" CORE_BRANCH=nosuchref)"; _sc_rc=$?
  if ((_sc_rc != 0)) && grep -q 'must vendor a named commit' <<<"$_sc_out" \
    && [[ "$(_scg "$SCF/repos/dotfiles-Test" rev-parse HEAD)" == "$_sc_head_before" ]] \
    && [[ -z "$(_scg "$SCF/repos/dotfiles-Test" status --porcelain)" ]]; then
    pass "sync-core: an unresolvable Core hard-fails before any repo is written"
  else
    fail "sync-core: unresolvable Core did not refuse cleanly (rc=$_sc_rc)"
    printf '%s\n' "$_sc_out" | sed 's/^/    /' >&2
  fi

  # ── #556: core_tag must never describe a commit other than the vendored one ───
  # The `|| describe "$CORE_BRANCH"` fallback re-resolved the branch at describe time, so a
  # moved branch stamped a tag belonging to a DIFFERENT commit — into core.lock and onto
  # every rewritten workflow pin comment, which is the field Renovate reads.
  _sc_old_sha="$(_scg "$SCF/coreremote" rev-parse HEAD)"
  _scg "$SCF/coreremote" tag -f v9.9.9 "$_sc_old_sha" >/dev/null 2>&1
  printf 'core payload newer\n' >"$SCF/coreremote/payload.txt"
  _scg "$SCF/coreremote" add -A
  _scg "$SCF/coreremote" commit -q -m "core c-newer"
  _scg "$SCF/coreremote" tag -f v9.9.10 >/dev/null 2>&1
  _scg "$SCF/core" fetch -q --tags origin >/dev/null 2>&1 || true
  _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1 CORE_BRANCH="$_sc_old_sha")"
  _sc_tag="$(sed -n 's/^core_tag=//p' "$SCF/repos/dotfiles-Test/core.lock" 2>/dev/null)"
  if [[ "$_sc_tag" != v9.9.10 ]] \
    && ! grep -rq '# v9.9.10' "$SCF/repos/dotfiles-Test/.github/workflows" 2>/dev/null; then
    pass "sync-core: core_tag never names a tag belonging to a different commit"
  else
    fail "sync-core: core_tag stamped v9.9.10 for a run that vendored ${_sc_old_sha:0:12}"
  fi
  _scg "$SCF/core" pull -q --ff-only >/dev/null 2>&1 || true
  unset _sc_old_sha _sc_tag
  unset _sc_race_n
  unset -f _sc_race_check

  # ── core_lock_classify: the shared comparison, both verdicts ──────────────────
  # core-integrity.sh had NO behavioural coverage, so extracting its classifier into a
  # shared lib could have changed the verdict silently. Drive the lib directly.
  # shellcheck source=scripts/lib/core-lock.sh
  source "$HERE/scripts/lib/core-lock.sh"
  _sc_run SYNC_SKIP_AUDIT=1 >/dev/null 2>&1
  _sc_rec="$(sed -n 's/^core_sha=//p' "$SCF/repos/dotfiles-Test/core.lock")"
  if [[ "$(core_lock_classify "$SCF/repos/dotfiles-Test" "$_sc_rec" "$SCF/coreremote")" == pristine ]]; then
    pass "core_lock_classify: a freshly synced repo is pristine"
  else
    fail "core_lock_classify: a freshly synced repo was not reported pristine"
  fi
  printf 'hand edit\n' >>"$SCF/repos/dotfiles-Test/core/payload.txt"
  _scg "$SCF/repos/dotfiles-Test" add -A
  DOTFILES_ALLOW_CORE_EDIT=1 _scg "$SCF/repos/dotfiles-Test" commit -q -m "hand edit core/"
  if [[ "$(core_lock_classify "$SCF/repos/dotfiles-Test" "$_sc_rec" "$SCF/coreremote")" == TAMPERED* ]]; then
    pass "core_lock_classify: a hand-edited core/ is reported TAMPERED"
  else
    fail "core_lock_classify: a hand-edited core/ was NOT caught"
  fi
  if [[ "$(core_lock_classify "$SCF/repos/dotfiles-Test" "$(printf '0%.0s' {1..40})" "$SCF/coreremote")" == UNVERIFIABLE* ]]; then
    pass "core_lock_classify: a sha absent from Core history is UNVERIFIABLE, not TAMPERED"
  else
    fail "core_lock_classify: an absent sha was misclassified"
  fi
  unset _sc_rec

  # ── the staleness guard: a target BEHIND its remote must refuse pre-flight (#622) ──
  # The dirty-tree guard asks "uncommitted work?" and nothing asked "current with the
  # remote?", so a sync landed on a stale base in all nine repos and reported
  # `updated 9 / failed 0`; every push was then rejected as non-fast-forward. The property
  # that matters is not the message, it is that the refusal happens BEFORE anything is
  # written — the whole cost of the bug was nine repos already committed to.
  #
  # A dedicated fixture, because the fleet above deliberately has no upstream: a repo with
  # no @{upstream} has no remote counterpart to be behind, which is a case this guard must
  # stay quiet about and which the other assertions rely on.
  _sc_st="$SCF/stale"
  mkdir -p "$_sc_st"
  git init -q --bare "$_sc_st/origin.git" >/dev/null 2>&1 || true
  # Point the bare HEAD at main BEFORE anything clones it. Without this the clone below
  # inherits the host's init.defaultBranch (often master), lands on an unborn branch that
  # the origin does not have, and a later commit there becomes a ROOT commit rather than a
  # descendant — so the "advance the remote" step produces a divergence, not a fast-forward,
  # and the target is never actually BEHIND. Silent, and it makes the guard look broken.
  git -C "$_sc_st/origin.git" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1 || true
  if git clone -q "$_sc_st/origin.git" "$SCF/repos/dotfiles-Stale" >/dev/null 2>&1; then
    _sc_ident "$SCF/repos/dotfiles-Stale"
    mkdir -p "$SCF/repos/dotfiles-Stale/core"
    printf 'seed\n' >"$SCF/repos/dotfiles-Stale/core/payload.txt"
    _scg "$SCF/repos/dotfiles-Stale" add -A
    _scg "$SCF/repos/dotfiles-Stale" commit -q -m "seed"
    _scg "$SCF/repos/dotfiles-Stale" push -q -u origin HEAD:main >/dev/null 2>&1
    # Advance the shared origin from a second clone, then fetch — leaving the target
    # exactly one commit behind its upstream, with a clean tree.
    if git clone -q "$_sc_st/origin.git" "$_sc_st/other" >/dev/null 2>&1; then
      _sc_ident "$_sc_st/other"
      printf 'upstream moved\n' >"$_sc_st/other/n.txt"
      _scg "$_sc_st/other" add -A
      _scg "$_sc_st/other" commit -q -m "remote advance"
      _scg "$_sc_st/other" push -q origin HEAD:main >/dev/null 2>&1
    fi
    _scg "$SCF/repos/dotfiles-Stale" fetch -q origin >/dev/null 2>&1
    _sc_st_head="$(_scg "$SCF/repos/dotfiles-Stale" rev-parse HEAD)"
    _sc_st_run() { # the fixture sync, aimed at the stale repo only
      env -u DOTFILES_ALLOW_CORE_EDIT -u CORE_JSON CORE_COLOR=never \
        REPOS_ROOT="$SCF/repos" CORE_REMOTE="$SCF/coreremote" CORE_BRANCH=main \
        SYNC_JOBS=1 "$@" bash "$_SCS" dotfiles-Stale 2>&1
    }
    _sc_out="$(_sc_st_run SYNC_SKIP_AUDIT=1)"; _sc_rc=$?
    if ((_sc_rc != 0)) && grep -qi 'behind their remote' <<<"$_sc_out"; then
      pass "sync-core: a target BEHIND its remote refuses the fan-out (rc=$_sc_rc)"
    else
      fail "sync-core: a stale target did NOT stop the fan-out (rc=$_sc_rc)"
    fi
    # The refusal must be pre-flight. HEAD alone is too weak — a regression that wrote
    # core.lock before returning would leave HEAD unchanged and still pass.
    if [[ "$(_scg "$SCF/repos/dotfiles-Stale" rev-parse HEAD)" == "$_sc_st_head" ]] &&
      [[ -z "$(_scg "$SCF/repos/dotfiles-Stale" status --porcelain)" ]] &&
      [[ ! -f "$SCF/repos/dotfiles-Stale/core.lock" ]]; then
      pass "sync-core: the staleness refusal happens before any repo is mutated"
    else
      fail "sync-core: a repo was written to despite the staleness refusal"
    fi
    # It names the correct recovery. Rebasing the sync commit is NOT it: the workflow pin
    # rewrite is a sed over the target's own files, so it can replay cleanly and be wrong.
    if grep -q 'RE-RUN this sync' <<<"$_sc_out" && grep -qi 'do NOT rebase' <<<"$_sc_out"; then
      pass "sync-core: the staleness refusal names re-running, not rebasing, as the fix"
    else
      fail "sync-core: the staleness refusal does not point at the correct recovery"
    fi
    # The documented escape hatch must actually bypass it.
    _sc_out="$(_sc_st_run SYNC_SKIP_AUDIT=1 SYNC_SKIP_STALE=1)"
    if ! grep -qi 'behind their remote' <<<"$_sc_out"; then
      pass "sync-core: SYNC_SKIP_STALE=1 bypasses the staleness guard"
    else
      fail "sync-core: SYNC_SKIP_STALE=1 did not bypass the staleness guard"
    fi
    # ...and a repo with NO upstream is silently fine, which is what keeps every other
    # assertion in this section working.
    _sc_out="$(_sc_run SYNC_SKIP_AUDIT=1)"
    if ! grep -qi 'behind their remote' <<<"$_sc_out"; then
      pass "sync-core: a target with no @{upstream} is not reported stale"
    else
      fail "sync-core: a target with no upstream was wrongly reported stale"
    fi
    rm -rf "$SCF/repos/dotfiles-Stale"
    unset -f _sc_st_run
    unset _sc_st_head
  else
    skip "sync-core staleness guard (could not build the clone fixture — out of scope)"
  fi
  unset _sc_st
else
  skip "sync-core.sh fan-out guards (git subtree unavailable — it is a contrib command)"
fi

# ── F6b. the real-bootstrap matrix (scripts/fleet-bootstrap-matrix.py) ───────
# THE FIRST TESTS THIS SCRIPT HAS EVER HAD, and the reason is #750. It is the static
# reader that turns each OS repo's own bootstrap-test.yml caller into the weekly sweep's
# matrix, so a defect here does not fail loudly — it silently drops a per-leg knob and the
# sweep runs on defaults that look exactly like a healthy run.
#
# The `postcheck` key is the sharp case. real-bootstrap.yml interpolates
# ${{ matrix.leg.postcheck }} into an env var and skips the assertion when it is empty, so
# a key this script never emits — a rename, a typo, a merge that drops the line — produces
# a hook that is a PERMANENT SILENT NO-OP. Every leg would report "NO postcheck declared",
# which is a sentence the workflow legitimately prints, and nothing anywhere would be red.
# That is the "advisory gate that never runs reads as coverage" failure both files warn
# about, and it is why the parity assertion below is worth more than the extraction ones.
_fbm="$HERE/scripts/fleet-bootstrap-matrix.py"
_fbm_wf="$HERE/.github/workflows/real-bootstrap.yml"
if [[ ! -r "$_fbm" || ! -r "$_fbm_wf" ]]; then
  skip "real-bootstrap matrix: script or workflow not readable (partial checkout?)"
elif ! have python3; then
  skip "real-bootstrap matrix (python3 not installed)"
elif ! python3 -c 'import yaml' 2>/dev/null; then
  # Same gate audit-core.sh section 6 uses, and CI installs PyYAML on every leg for it.
  skip "real-bootstrap matrix (python3 has no yaml module — pip install pyyaml)"
else
  hdr "real-bootstrap matrix (fleet-bootstrap-matrix.py)"

  # A scratch FLEET, not the real siblings: the assertions below are about what the parser
  # does with a given caller, and pinning them to whatever eight repos happen to be cloned
  # next to this one would make them fail for reasons that are not defects.
  _fbm_root="$SANDBOX/fleetmatrix"
  rm -rf "$_fbm_root"
  mkdir -p "$_fbm_root/dotfiles-core/scripts" "$_fbm_root/dotfiles-Probe/.github/workflows"
  printf '# scratch fleet\ndotfiles-Probe\n' >"$_fbm_root/dotfiles-core/scripts/os-repos.txt"

  # _fbm_caller <with-block-lines...> — write a synthetic caller and emit its one leg as JSON
  _fbm_caller() {
    {
      printf 'name: bootstrap\non: [pull_request]\njobs:\n  test:\n'
      printf '    uses: dotgibson/dotfiles-core/.github/workflows/bootstrap-test.yml@v5\n'
      printf '    with:\n      image: alpine:3.20\n      prep: apk add --no-cache bash zsh\n'
      local _l
      for _l in "$@"; do printf '      %s\n' "$_l"; done
    } >"$_fbm_root/dotfiles-Probe/.github/workflows/bootstrap.yml"
    python3 "$_fbm" "$_fbm_root" 2>"$_fbm_root/stderr"
  }
  # _fbm_key <json> <key> — the value of <key> on the first (only) leg
  _fbm_key() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0][sys.argv[1]])' "$2" 2>/dev/null; }

  # --- a declared postcheck arrives verbatim ----------------------------------
  _fbm_json="$(_fbm_caller 'bootstrap_postcheck: ./scripts/assert-provisioned.sh')"
  if [[ "$(_fbm_key "$_fbm_json" postcheck)" == "./scripts/assert-provisioned.sh" ]]; then
    pass "matrix: a declared bootstrap_postcheck reaches the leg verbatim"
  else
    fail "matrix: bootstrap_postcheck was not extracted from the caller — got '$(_fbm_key "$_fbm_json" postcheck)'"
  fi

  # --- absent is empty, and that is the whole opt-in property -----------------
  # If this ever yields anything but the empty string, every repo in the fleet starts
  # running something it never asked for on the far side of a real provision.
  _fbm_json="$(_fbm_caller 'bootstrap_timeout: 240')"
  if [[ -z "$(_fbm_key "$_fbm_json" postcheck)" ]]; then
    pass "matrix: a caller declaring no postcheck gets an empty one (the hook stays opt-in)"
  else
    fail "matrix: a caller with no bootstrap_postcheck produced '$(_fbm_key "$_fbm_json" postcheck)' — the hook is not opt-in"
  fi
  # The same fixture proves the timeout still rides through; these two share one reader.
  if [[ "$(_fbm_key "$_fbm_json" timeout)" == "240" ]]; then
    pass "matrix: bootstrap_timeout still rides through beside it"
  else
    fail "matrix: bootstrap_timeout regressed — got '$(_fbm_key "$_fbm_json" timeout)', want 240"
  fi

  # --- a non-string is a caller typo: warn, and run with NO assertion ---------
  # `bootstrap_postcheck: true` parses as a bool. Running `True` as a command would red the
  # leg for a reason that has nothing to do with provisioning, which is the false-accusation
  # this advisory lane must not make. Degrade like bootstrap_timeout does, but say so.
  _fbm_json="$(_fbm_caller 'bootstrap_postcheck: true')"
  if [[ -n "$(_fbm_key "$_fbm_json" postcheck)" ]]; then
    fail "matrix: a non-string bootstrap_postcheck was passed through as '$(_fbm_key "$_fbm_json" postcheck)' — that would run as a command"
  elif ! grep -q '::warning::.*bootstrap_postcheck is not a string' "$_fbm_root/stderr"; then
    fail "matrix: a non-string bootstrap_postcheck was dropped SILENTLY — the coverage loss must be announced"
  else
    pass "matrix: a non-string bootstrap_postcheck warns and yields no assertion"
  fi

  # --- every key the workflow reads is a key the script emits -----------------
  # The parity assertion. One-directional on purpose: an emitted key nothing consumes is
  # harmless, a CONSUMED key nothing emits expands to the empty string and fails open.
  # This retro-covers image/prep/name/repo/timeout/offensive as well as postcheck.
  _fbm_json="$(_fbm_caller 'bootstrap_postcheck: ./x.sh')"
  _fbm_emits="$(printf '%s' "$_fbm_json" | python3 -c 'import json,sys; print(" ".join(sorted(json.load(sys.stdin)[0])))' 2>/dev/null)"
  _fbm_missing=""
  # Herestring rather than a pipe: the accumulator below must survive the loop, and a
  # `... | while read` runs the body in a subshell where every append is discarded — the
  # assertion would then pass unconditionally, which is the one outcome it must not have.
  while read -r _fbm_k; do
    [[ -n "$_fbm_k" ]] || continue
    [[ " $_fbm_emits " == *" $_fbm_k "* ]] || _fbm_missing="$_fbm_missing $_fbm_k"
  done <<<"$(grep -oE 'matrix\.leg\.[A-Za-z_][A-Za-z0-9_]*' "$_fbm_wf" | sed 's/.*\.//' | sort -u)"
  if [[ -z "$_fbm_emits" ]]; then
    fail "matrix: could not read the emitted keys — the script did not produce a usable leg"
  elif [[ -n "$_fbm_missing" ]]; then
    fail "matrix: real-bootstrap.yml reads matrix.leg key(s)$_fbm_missing that fleet-bootstrap-matrix.py never emits — they expand to empty and the check they gate silently never runs"
  else
    pass "matrix: every matrix.leg.<key> the sweep reads is emitted by the script ($_fbm_emits)"
  fi

  # --- the postcheck must run INSIDE the docker run ---------------------------
  # #742 IN ONE ASSERTION. The wiring check used to sit in a step of its own, one level out,
  # where `docker run --rm` had already destroyed the filesystem it claimed to inspect — a
  # step NAMED for an assertion it could not perform. A postcheck placed there would be the
  # identical bug wearing a new name, and it would still look green. So: the reference has
  # to sit between the `sh -euc ...` opener and the line that closes it.
  if ! grep -q 'docker run .*-e POSTCHECK' "$_fbm_wf"; then
    fail "real-bootstrap: the docker run does not pass -e POSTCHECK — the value never reaches the container"
  elif ! awk "/sh -euc '\$/{f=1;next} f&&/^ *'\$/{f=0} f" "$_fbm_wf" | grep -q 'POSTCHECK'; then
    fail "real-bootstrap: \$POSTCHECK is referenced OUTSIDE the sh -euc block — docker run --rm has destroyed that filesystem by then (#742)"
  else
    pass "real-bootstrap: the postcheck runs inside the container, where the box it asserts still exists"
  fi

  # --- and that block still contains no apostrophe ----------------------------
  # The whole script is one single-quoted `sh -euc '...'` argument; a single apostrophe
  # closes it early and the rest is reinterpreted by the outer shell. The existing block
  # says so twice in comments, which is not a gate.
  if awk "/sh -euc '\$/{f=1;next} f&&/^ *'\$/{f=0} f" "$_fbm_wf" | grep -q "'"; then
    fail "real-bootstrap: an apostrophe has appeared inside the single-quoted sh -euc block — it closes the quote early"
  else
    pass "real-bootstrap: the sh -euc block is still apostrophe-free"
  fi

  unset -f _fbm_caller _fbm_key
  unset _fbm_root _fbm_json _fbm_emits _fbm_missing _fbm_k
fi
unset _fbm _fbm_wf

# ── F7. the REAL link run (blib_link_core against a throwaway $HOME) ─────────
# bootstrap-test.yml asserts the symlink graph, but it is workflow_call-only and
# dotfiles-core ships no bootstrap.sh — so it only ever runs from the nine OS repos.
# Core's own CI unit-tests the blib_* helpers and never performs a real link run, which
# means a bootstrap-lib regression is caught downstream, in nine repos, instead of here.
#
# This closes that: link the ACTUAL Core tree into a sandbox $HOME/$config and assert the
# graph a consumer depends on. Hermetic — the tpm directory is pre-seeded so the one-time
# clone is skipped, which is the only network call in the whole function.
if have git; then
  hdr "bootstrap link run (blib_link_core against a sandbox HOME)"
  LR="$SANDBOX/linkrun"
  rm -rf "$LR"
  mkdir -p "$LR/home" "$LR/config" "$LR/dotfiles"
  # A consumer's layout is <repo>/core -> the vendored Core tree. COPY it rather than
  # symlinking: blib_link_core runs `chmod +x` on core/tmux/scripts/*.sh and core/bin/clip*,
  # and audit-core.sh launches this suite CONCURRENTLY with its own exec-bit gate — a
  # symlink here would let the test mutate the very checkout that gate is reading, which is
  # both a race and a violation of the read-only assumption the whole suite is built on.
  # Copying per top-level directory keeps .git out without needing a non-portable tar flag.
  mkdir -p "$LR/dotfiles/core"
  for _lr_d in zsh nvim tmux vim git starship lazygit mise jujutsu atuin tealdeer sesh ssh bin lib; do
    [[ -e "$HERE/$_lr_d" ]] && cp -R "$HERE/$_lr_d" "$LR/dotfiles/core/$_lr_d"
  done
  mkdir -p "$LR/config/tmux/plugins/tpm"   # pre-seed: skips the tpm clone (offline)
  (
    # shellcheck source=lib/bootstrap-lib.sh
    HOME="$LR/home" XDG_CONFIG_HOME="$LR/config" \
      BLIB_ONLY="" BLIB_SKIP="" \
      bash -c '
        set -u
        . "'"$HERE/lib/bootstrap-lib.sh"'"
        blib_link_core "'"$LR/dotfiles"'" "'"$LR/config"'" >/dev/null 2>&1
      '
  ) || true

  _lr_is_link_to() { # <link> <target>  — a symlink resolving to the expected file
    [[ -L "$1" ]] && [[ "$(readlink "$1")" == "$2" ]]
  }
  _lr_mode() { # <path> — octal permission bits, GNU or BSD stat (the macOS CI leg)
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
  }
  # The zsh chain is the load-order contract: every numbered Core fragment must land FLAT
  # in $config/zsh under its own basename, because loader.zsh globs NN-*.zsh there. A
  # rename or a missed file here is precisely what silently drops a stage on nine boxes.
  _lr_missing=""
  for f in "$HERE"/zsh/[0-9][0-9]-*.zsh; do
    b="$(basename "$f")"
    _lr_is_link_to "$LR/config/zsh/$b" "$LR/dotfiles/core/zsh/$b" || _lr_missing="$_lr_missing $b"
  done
  if [[ -z "$_lr_missing" ]]; then
    pass "link run: every numbered Core zsh fragment is linked flat into \$ZSH_CFG"
  else
    fail "link run: zsh fragments missing or mislinked —$_lr_missing"
  fi
  # loader.zsh is not a numbered fragment but IS what sources them; a graph without it
  # produces a shell that starts and loads nothing.
  if _lr_is_link_to "$LR/config/zsh/loader.zsh" "$LR/dotfiles/core/zsh/loader.zsh"; then
    pass "link run: loader.zsh is linked (the chain has an entry point)"
  else
    fail "link run: loader.zsh was not linked"
  fi
  # nvim is linked as a DIRECTORY symlink — the one manifest entry that is a whole tree.
  if [[ -L "$LR/config/nvim" && -d "$LR/config/nvim" && -f "$LR/config/nvim/init.lua" ]]; then
    pass "link run: nvim/ is a directory symlink resolving to a real init.lua"
  else
    fail "link run: nvim/ is not a resolvable directory symlink"
  fi
  # The rest of the symlinked surface, at the exact destinations bootstrap promises.
  _lr_bad=""
  _lr_is_link_to "$LR/config/tmux/tmux.conf" "$LR/dotfiles/core/tmux/tmux.conf" || _lr_bad="$_lr_bad tmux.conf"
  _lr_is_link_to "$LR/config/starship.toml" "$LR/dotfiles/core/starship/starship.toml" || _lr_bad="$_lr_bad starship.toml"
  _lr_is_link_to "$LR/config/lazygit/config.yml" "$LR/dotfiles/core/lazygit/config.yml" || _lr_bad="$_lr_bad lazygit"
  _lr_is_link_to "$LR/config/jj/config.toml" "$LR/dotfiles/core/jujutsu/config.toml" || _lr_bad="$_lr_bad jj"
  _lr_is_link_to "$LR/config/tealdeer/config.toml" "$LR/dotfiles/core/tealdeer/config.toml" || _lr_bad="$_lr_bad tealdeer"
  # mise and atuin were absent from this group for as long as it has existed (#718) — the
  # gap the checklist rewrite predicts, found by reading the list it now tells you to edit.
  # Both are in the `tools` group beside lazygit/jj/tealdeer and were only ever covered by
  # the fixture-directory list above, which proves the SOURCE was copied, not that the LINK
  # lands where bootstrap promises.
  # mise is deliberately NOT in this group — it is ADOPTED (a real file), not linked,
  # because `mise use -g` rewrites it and a symlink pointed that write into vendored
  # core/. Asserted separately below.
  _lr_is_link_to "$LR/config/atuin/config.toml" "$LR/dotfiles/core/atuin/config.toml" || _lr_bad="$_lr_bad atuin"
  _lr_is_link_to "$LR/home/.gitconfig" "$LR/dotfiles/core/git/gitconfig" || _lr_bad="$_lr_bad .gitconfig"
  _lr_is_link_to "$LR/home/.vimrc" "$LR/dotfiles/core/vim/vimrc" || _lr_bad="$_lr_bad .vimrc"
  # Resolve the target, don't just prove it is *a* symlink — a dangling link, or one
  # pointing at the wrong directory, would otherwise pass this grouped assertion.
  _lr_is_link_to "$LR/config/tmux/scripts" "$LR/dotfiles/core/tmux/scripts" || _lr_bad="$_lr_bad tmux/scripts"
  [[ -d "$LR/config/tmux/scripts" ]] || _lr_bad="$_lr_bad tmux/scripts(dangling)"
  if [[ -z "$_lr_bad" ]]; then
    pass "link run: tmux, starship, lazygit, jj, tealdeer, atuin, gitconfig and vimrc land where bootstrap promises"
  else
    fail "link run: wrong or missing links —$_lr_bad"
  fi

  # ── mise is ADOPTED, not linked ─────────────────────────────────────────────
  # The regression this pins: a symlink here is a write path back into the vendored
  # core/ tree. `mise use -g ruby@4.0` followed it, tampered the tree, and took the
  # repo out of the next fleet sync. Asserting "not a symlink" IS the contract.
  if [[ -f "$LR/config/mise/config.toml" && ! -L "$LR/config/mise/config.toml" ]]; then
    pass "adopt run: mise config is a real file, not a symlink into core/"
  else
    fail "adopt run: mise config is missing or is a symlink (the write-through regression)"
  fi
  if [[ "$(git hash-object -- "$LR/config/mise/config.toml" 2>/dev/null)" == \
        "$(git hash-object -- "$LR/dotfiles/core/mise/config.toml" 2>/dev/null)" ]]; then
    pass "adopt run: a freshly adopted mise config matches Core byte-for-byte"
  else
    fail "adopt run: adopted mise config does not match Core's source"
  fi
  # And the write that started all this must now stay local: simulate the rewrite and
  # prove the vendored tree is untouched.
  _lr_core_before="$(git hash-object -- "$LR/dotfiles/core/mise/config.toml")"
  cp "$LR/config/mise/config.toml" "$SANDBOX/mise-adopted.orig"
  printf '\n[tools]\nruby = "4.0"\n' >>"$LR/config/mise/config.toml"
  if [[ "$(git hash-object -- "$LR/dotfiles/core/mise/config.toml")" == "$_lr_core_before" ]]; then
    pass "adopt run: a local mise rewrite does NOT reach vendored core/"
  else
    fail "adopt run: a local mise rewrite wrote through into vendored core/"
  fi
  # Restore: the later "second pass is a true no-op" assertion shares this fixture, and a
  # drifted file there would make THIS test the cause of an unrelated failure.
  cp "$SANDBOX/mise-adopted.orig" "$LR/config/mise/config.toml"
  # clip is SYMLINKED onto PATH — bootstrap-lib chmod +x's the SOURCE, not the link — so
  # assert the target as well as the mode. nvim's clipboard provider, tmux copy-pipe and
  # the zsh helpers all shell out to it by name, so a dangling link breaks copy on every
  # surface at once while `-x` alone would still look fine on a wrong-but-executable file.
  if _lr_is_link_to "$LR/home/.local/bin/clip" "$LR/dotfiles/core/bin/clip" &&
    _lr_is_link_to "$LR/home/.local/bin/clip-paste" "$LR/dotfiles/core/bin/clip-paste" &&
    [[ -x "$LR/home/.local/bin/clip" && -x "$LR/home/.local/bin/clip-paste" ]]; then
    pass "link run: clip + clip-paste link onto ~/.local/bin and resolve executable"
  else
    fail "link run: clip/clip-paste missing, mislinked, or not executable"
  fi
  # ssh (#450). Core OWNS the client config now — it used to be read from the OS repo's
  # ROOT ($dotfiles/ssh/config), a path Core neither shipped nor listed in core.manifest,
  # so a repo that simply lacked one silently got no ssh config at all. Assert the link
  # resolves INTO core/, not just that ~/.ssh/config exists: a leftover file from the
  # pre-#450 layout would satisfy the weaker check while the vendored config went unused.
  _lr_ssh_bad=""
  _lr_is_link_to "$LR/home/.ssh/config" "$LR/dotfiles/core/ssh/config" || _lr_ssh_bad="$_lr_ssh_bad config"
  # ssh REFUSES to use ~/.ssh when the perms are loose, and ControlMaster fails outright
  # on a missing sockets dir — both are silent-at-link-time, loud-at-first-connect.
  # config.d is the override chain Core's Include depends on; without it, the drop-in
  # mechanism that replaces each repo's forked config has nowhere to put a file.
  for _lr_sd in .ssh .ssh/sockets .ssh/config.d; do
    [[ -d "$LR/home/$_lr_sd" ]] || { _lr_ssh_bad="$_lr_ssh_bad $_lr_sd(missing)"; continue; }
    # 700 exactly — ssh rejects group/other access on ~/.ssh, and a 755 here is the
    # failure mode that only shows up on a box with a real key in it.
    [[ "$(_lr_mode "$LR/home/$_lr_sd")" == 700 ]] || _lr_ssh_bad="$_lr_ssh_bad $_lr_sd($(_lr_mode "$LR/home/$_lr_sd"))"
  done
  if [[ -z "$_lr_ssh_bad" ]]; then
    pass "link run: ssh/config links out of core/, with ~/.ssh, sockets and config.d at 0700"
  else
    fail "link run: ssh wiring wrong —$_lr_ssh_bad"
  fi
  # The dropped chmod, pinned so it cannot creep back. blib_link_core used to run
  # `chmod 600` on the SOURCE — reaching into the consumer repo's working tree to change
  # a tracked file's mode, which post-#450 means Core chmod'ing its own vendored tree in
  # nine repos. It was never needed: ssh only refuses a config that is group/world
  # WRITABLE, and git checks out 0644. Assert the source keeps the mode git gave it.
  if [[ "$(_lr_mode "$LR/dotfiles/core/ssh/config")" != 600 ]]; then
    pass "link run: core/ssh/config keeps its checked-out mode (no chmod into the vendored tree)"
  else
    fail "link run: something chmod 600'd core/ssh/config — Core must not mutate the vendored tree"
  fi
  # The SEEDED files are the inverse contract: real copies, never symlinks, so a user's
  # identity/local edits are never tracked back into Core. A symlink here would publish
  # someone's git identity into the repo on their next commit.
  if [[ -f "$LR/config/git/local.gitconfig" && ! -L "$LR/config/git/local.gitconfig" ]] &&
    [[ -f "$LR/config/sesh/sesh.toml" && ! -L "$LR/config/sesh/sesh.toml" ]]; then
    pass "link run: seeded local.gitconfig and sesh.toml are COPIES, not symlinks"
  else
    fail "link run: a seeded file is missing or was symlinked (user edits would track back)"
  fi
  # Idempotency: bootstrap is re-run after every sync, so a second pass must be a no-op.
  # Comparing sorted PATH NAMES is not enough — blib_link removing and recreating every
  # symlink leaves the exact same names behind, which is precisely the churn this is
  # supposed to catch. Compare INODES: a torn-down-and-remade link gets a new one.
  # The second run's exit status is captured rather than discarded, so a rerun that fails
  # outright cannot pass this as "nothing changed".
  _lr_inodes() { find "$LR/config" "$LR/home" -maxdepth 4 -type l -exec ls -di {} + 2>/dev/null | sort -k2; }
  _lr_before="$(find "$LR/config" "$LR/home" -maxdepth 4 2>/dev/null | sort)"
  _lr_ino_before="$(_lr_inodes)"
  HOME="$LR/home" XDG_CONFIG_HOME="$LR/config" bash -c '
    set -u
    . "'"$HERE/lib/bootstrap-lib.sh"'"
    blib_link_core "'"$LR/dotfiles"'" "'"$LR/config"'" >/dev/null 2>&1
  '
  _lr_rc=$?
  _lr_after="$(find "$LR/config" "$LR/home" -maxdepth 4 2>/dev/null | sort)"
  _lr_ino_after="$(_lr_inodes)"
  if ((_lr_rc == 0)) && [[ "$_lr_before" == "$_lr_after" ]] &&
    [[ -n "$_lr_ino_before" && "$_lr_ino_before" == "$_lr_ino_after" ]] &&
    [[ -z "$(find "$LR/config" "$LR/home" -name '*.pre-dotfiles.*')" ]]; then
    pass "link run: a second pass is a true no-op (same inodes, no backups, rc=0)"
  else
    fail "link run: re-running bootstrap churned links, backed a file up, or failed (rc=$_lr_rc)"
  fi

  # A FAILED tpm clone must read as a failure. It used to be announced with blib_say —
  # blue `::` on STDOUT, the identical shape to the "cloning tpm" progress line above —
  # with git's error discarded by `>/dev/null 2>&1`. Behind a proxy that left tmux with no
  # plugin manager, nothing in the log to notice, and an empty tally, so an adopting
  # bootstrap could not tell a degraded box from a good one.
  #
  # Hermetic and OFFLINE: GIT_ALLOW_PROTOCOL=file makes git refuse the https transport, so
  # the clone fails deterministically without depending on the remote being unreachable
  # (or reachable). $config is fresh, so the clone is genuinely attempted.
  TF="$SANDBOX/tpmfail"
  rm -rf "$TF"
  mkdir -p "$TF/home" "$TF/config"
  HOME="$TF/home" XDG_CONFIG_HOME="$TF/config" GIT_ALLOW_PROTOCOL=file \
    BLIB_ONLY="tmux" BLIB_SKIP="" bash -c '
      set -u
      . "'"$HERE/lib/bootstrap-lib.sh"'"
      blib_link_core "'"$LR/dotfiles"'" "'"$TF/config"'"
      printf "TALLY=%s\n" "$(blib_failed_count)"
    ' >"$TF/out" 2>"$TF/err"
  if grep -q "tpm clone failed" "$TF/err"; then
    pass "tpm clone failure warns on STDERR"
  else
    fail "tpm clone failure did not reach stderr"
  fi
  # The regression itself: the message must not be on stdout, where blib_say put it.
  if grep -q "tpm clone failed" "$TF/out"; then
    fail "tpm clone failure is on STDOUT (blib_say regression — it must use blib_note_fail)"
  else
    pass "tpm clone failure is NOT on stdout (no longer a blib_say status line)"
  fi
  # Recorded, so blib_failures_report / a caller's --strict can act on it downstream.
  if grep -q "^TALLY=[1-9]" "$TF/out"; then
    pass "tpm clone failure lands in the blib_note_fail tally"
  else
    fail "tpm clone failure was not recorded in the tally"
  fi
  # git's own error is the whole diagnosis (DNS, proxy, TLS, rate limit) and used to be
  # thrown away. Assert the indented passthrough, not git's wording, which varies.
  #
  # `[^[:space:]]` is load-bearing, not decoration: an EMPTY capture still produces an
  # indented line, because `printf '%s\n' ""` emits one empty line and sed indents it to
  # four spaces. A bare `^    ` therefore passed whether or not anything was captured —
  # exactly the regression this is here to catch. Require real content after the indent.
  if grep -q '^    [^[:space:]]' "$TF/err"; then
    pass "tpm clone failure surfaces git's own error, indented under it"
  else
    fail "tpm clone failure discarded git's error output"
  fi
else
  skip "bootstrap link run (git unavailable)"
fi

# ── F7b. new-os-repo.sh emits LINTABLE entry files (scripts/new-os-repo.sh) ──
# Every OS repo this generator stamps inherits whatever it writes, so a defect here
# ships to each new layer from birth and is only ever noticed downstream.
#
# #451: it emitted the three ZDOTDIR entry files EXTENSIONLESS — zsh/zshenv,
# zsh/zprofile, zsh/zshrc — because their symlink destinations (~/.zshenv,
# $ZDOTDIR/.zshrc, $ZDOTDIR/.zprofile) have no extension either. Core's reusable lint
# gate selects repo-owned zsh with `git ls-files '*.zsh'`, so none of the three matched
# and none was ever syntax-checked, in any repo, from the day the generator was added.
#
# ~/.zshenv is the file that makes this worth a fixture rather than a one-line fix: it
# is sourced on EVERY zsh invocation including non-interactive ones, and it carries the
# ZDOTDIR indirection, so a syntax error there breaks login shells outright rather than
# degrading them. It was simultaneously the highest-blast-radius file in an OS repo and
# the only one the gate could not see.
#
# Asserted here rather than trusted, because the pull toward renaming these back to
# match their destinations is permanent — the filenames LOOK wrong until you know why.
if have git && have zsh; then
  hdr "new-os-repo.sh entry files (lintable by construction)"
  NOR="$SANDBOX/newosrepo"
  rm -rf "$NOR"
  # --no-vendor: skip the `git subtree add`, which is the only network call in the
  # script. Everything this asserts is written before/independently of it.
  if env -u CORE_JSON bash "$HERE/scripts/new-os-repo.sh" --no-vendor Fixture "$NOR" >/dev/null 2>&1; then
    _nor_bad=""
    for _nor_f in zshenv zprofile zshrc; do
      [[ -f "$NOR/zsh/$_nor_f.zsh" ]] || _nor_bad="$_nor_bad zsh/$_nor_f.zsh(missing)"
      # The extensionless name must NOT come back alongside it: a generator writing both
      # would satisfy the check above while still shipping an unlinted file.
      [[ -e "$NOR/zsh/$_nor_f" ]] && _nor_bad="$_nor_bad zsh/$_nor_f(extensionless)"
    done
    if [[ -z "$_nor_bad" ]]; then
      pass "new-os-repo: the three ZDOTDIR entry files are written as *.zsh (lint-gate visible)"
    else
      fail "new-os-repo: entry-file naming wrong —$_nor_bad"
    fi
    # The rename is only behaviour-neutral if the generated bootstrap follows it. A repo
    # with zshenv.zsh on disk and `link .../zsh/zshenv` in bootstrap.sh has no ~/.zshenv
    # at all — no ZDOTDIR, so the loader is never reached and the shell starts bare.
    if grep -q 'link "\$REPO/zsh/zshenv\.zsh" *"\$HOME/\.zshenv"' "$NOR/bootstrap.sh" &&
      grep -q 'link "\$REPO/zsh/zprofile\.zsh" *"\$CFG/zsh/\.zprofile"' "$NOR/bootstrap.sh" &&
      grep -q 'link "\$REPO/zsh/zshrc\.zsh" *"\$CFG/zsh/\.zshrc"' "$NOR/bootstrap.sh"; then
      pass "new-os-repo: bootstrap.sh links the .zsh sources to the extensionless destinations"
    else
      fail "new-os-repo: bootstrap.sh link lines disagree with the scaffolded filenames"
    fi
    # And the gate can only help if what it reads actually parses. This is the check that
    # never ran on these three files in any repo until #451.
    _nor_syn=""
    for _nor_f in "$NOR"/zsh/*.zsh; do
      zsh -n "$_nor_f" 2>/dev/null || _nor_syn="$_nor_syn $(basename "$_nor_f")"
    done
    if [[ -z "$_nor_syn" ]]; then
      pass "new-os-repo: every scaffolded entry file passes zsh -n"
    else
      fail "new-os-repo: scaffolded entry file(s) fail zsh -n —$_nor_syn"
    fi
  else
    fail "new-os-repo: --no-vendor scaffold run failed outright"
  fi
else
  skip "new-os-repo entry files (git or zsh unavailable)"
fi

# ── F8. blib_link displacement accounting (lib/bootstrap-lib.sh) ─────────────
# blib_link is reached above only THROUGH blib_link_core, and no test asserted a BLIB_*
# value at all — which is how #430 survived: a real file at $dst was moved to
# .pre-dotfiles.<epoch> and counted, while a symlink pointing SOMEWHERE ELSE was rm -f'd
# with no record of its target, no counter, and nothing in the run summary. The repos
# being wired are symlink farms, so that was the common case, not the rare one.
#
# These pin the contract both directions: a displaced link is logged + counted as
# RELINKED (never as backed up — that word promises a restorable file on disk), a
# displaced file still backs up, and an already-correct link stays silent so a plain
# re-run of bootstrap.sh prints no relink noise.
hdr "blib_link displacement accounting (relink is recorded, not silent)"
_bl="$(mktemp -d "$SANDBOX/blink.XXXXXX")"
printf 'REAL\n' >"$_bl/src"
printf 'OTHER\n' >"$_bl/other"

# The lib's `_CORE_BOOTSTRAP_LIB_SH` re-entry guard makes a re-`source` a no-op, so the
# counters cannot be observed from a subshell here — sections F/G already sourced it at
# file scope. Drive a fresh `bash -c` instead, exactly as the link run above does, so the
# tallies are genuinely read from 0. Prints the run's output, then `--`, then the four.
_bl_run() { # <dry> <src> <dst>
  BLIB_DRY="$1" bash -c '
    set -u
    . "'"$HERE/lib/bootstrap-lib.sh"'"
    blib_link "$1" "$2"
    printf -- "--\n%s %s %s %s\n" "$BLIB_LINKED" "$BLIB_BACKED" "$BLIB_RELINKED" "$BLIB_SKIPPED"
  ' _ "$2" "$3" 2>&1
}
_bl_tally() { printf '%s' "${1##*$'--\n'}" | tr -d '\n'; } # the line after the -- marker

# 1) a symlink pointing ELSEWHERE: repointed, its old target NAMED, counted as relinked
#    and NOT as backed up, and no stray .pre-dotfiles.* left behind.
ln -sfn "$_bl/other" "$_bl/dst1"
_bl_out="$(_bl_run 0 "$_bl/src" "$_bl/dst1")"
if [[ "$_bl_out" == *"relinking"*"$_bl/other"* ]] && [[ "$(_bl_tally "$_bl_out")" == "1 0 1 0" ]] &&
  [[ "$(readlink "$_bl/dst1")" == "$_bl/src" ]] &&
  [[ -z "$(find "$_bl" -name 'dst1.pre-dotfiles.*')" ]]; then
  pass "blib_link: a displaced symlink is repointed, its old target named, counted relinked"
else
  fail "blib_link: displaced symlink lost its target or was miscounted (got: $_bl_out)"
fi

# 2) a real file still takes the OTHER path — moved aside with its content intact, counted
#    as backed up and NOT as relinked. The two tallies must not bleed into each other.
printf 'MINE\n' >"$_bl/dst2"
_bl_out="$(_bl_run 0 "$_bl/src" "$_bl/dst2")"
_bl_bak="$(find "$_bl" -name 'dst2.pre-dotfiles.*' | head -1)"
if [[ "$(_bl_tally "$_bl_out")" == "1 1 0 0" ]] && [[ -n "$_bl_bak" ]] &&
  [[ "$(cat "$_bl_bak")" == "MINE" ]] && [[ "$(readlink "$_bl/dst2")" == "$_bl/src" ]]; then
  pass "blib_link: a displaced real file still backs up (content intact), counted backed up"
else
  fail "blib_link: real-file backup regressed or leaked into the relink tally (got: $_bl_out)"
fi

# 2b) …and it SAYS SO. The backup was correct but MUTE, and blib_link wires ~34 of ~40
#     destinations in an OS-repo bootstrap, so silent clobbering was the common case, not
#     the rare one (#463). The aggregate "N backed up" footer says THAT something moved,
#     never WHAT — which is the one thing the person migrating an existing machine needs.
#     Assert the destination AND the backup path are both named, so a future refactor
#     cannot quietly degrade this to "backed up a file".
if [[ "$_bl_out" == *"backed up existing $_bl/dst2 -> $_bl_bak"* ]]; then
  pass "blib_link: the backup is announced, naming both the destination and where it went"
else
  fail "blib_link: a real file was displaced silently or without naming the backup (got: $_bl_out)"
fi

# 2c) The backup SUFFIX is the one sortable format (#464). Core wrote `date +%s` here and
#     the `link()` helper new-os-repo.sh generates wrote `date +%Y%m%d-%H%M%S`, and an
#     OS repo's unlink_dest DOCUMENTS a lexical-sort-is-chronological invariant over the
#     glob. A 10-digit epoch always sorts before a `20…` datestamp, so across the pair the
#     invariant was false and --uninstall could restore the OLDER file. Pin the format so
#     the assertion in that comment is true rather than merely asserted. The `.<pid>` tail
#     is the same-second collision guard; it only ever tiebreaks WITHIN a second.
if [[ "${_bl_bak##*/}" =~ ^dst2\.pre-dotfiles\.[0-9]{8}-[0-9]{6}\.[0-9]+$ ]]; then
  pass "blib_link: backup suffix is the sortable pre-dotfiles.<YYYYmmdd-HHMMSS>.<pid> format"
else
  fail "blib_link: backup suffix drifted from the one fleet format (got: ${_bl_bak##*/})"
fi

# 2d) The invariant itself, end to end: two backups of the SAME destination, one second
#     apart, must sort chronologically under a plain lexical sort — the operation
#     --uninstall performs to choose the newest. This is the assertion that would have
#     caught the two-format split, because it fails on a mixed pair regardless of which
#     formats are in play.
printf 'OLDER\n' >"$_bl/dst4"
_bl_run 0 "$_bl/src" "$_bl/dst4" >/dev/null
rm -f "$_bl/dst4"
sleep 1
printf 'NEWER\n' >"$_bl/dst4"
_bl_run 0 "$_bl/src" "$_bl/dst4" >/dev/null
_bl_sorted=()
while IFS= read -r _bl_l; do _bl_sorted[${#_bl_sorted[@]}]="$_bl_l"; done < <(
  find "$_bl" -name 'dst4.pre-dotfiles.*' | sort
)
if ((${#_bl_sorted[@]} == 2)) &&
  [[ "$(cat "${_bl_sorted[0]}")" == "OLDER" && "$(cat "${_bl_sorted[1]}")" == "NEWER" ]]; then
  pass "blib_link: a lexical sort of the backups IS chronological (the --uninstall invariant)"
else
  fail "blib_link: lexical sort of backups is not chronological — --uninstall would restore the wrong file"
fi

# 3) BLIB_DRY previews the displacement instead of hiding it. "would relink: $dst" alone
#    reads as *repoint*; a reader has to be told what is about to go, and the fixture must
#    come through untouched.
ln -sfn "$_bl/other" "$_bl/dst3"
_bl_out="$(_bl_run 1 "$_bl/src" "$_bl/dst3")"
if [[ "$_bl_out" == *"would relink"* ]] && [[ "$_bl_out" == *"currently -> $_bl/other"* ]] &&
  [[ "$(readlink "$_bl/dst3")" == "$_bl/other" ]] && [[ "$(_bl_tally "$_bl_out")" == "1 0 1 0" ]]; then
  pass "blib_link: BLIB_DRY=1 names what it would displace and mutates nothing"
else
  fail "blib_link: dry-run plan hides the displaced target or mutated the fixture (got: $_bl_out)"
fi

# 4) the already-correct link is still a silent no-op. bootstrap.sh is re-run after every
#    sync, so a relink notice here would fire on every path on every run and mean nothing.
ln -sfn "$_bl/src" "$_bl/dst4"
_bl_out="$(_bl_run 0 "$_bl/src" "$_bl/dst4")"
if [[ "$(_bl_tally "$_bl_out")" == "1 0 0 0" ]] && [[ "$_bl_out" != *"relink"* ]]; then
  pass "blib_link: an already-correct link stays a silent no-op (no relink noise on re-run)"
else
  fail "blib_link: a correct link was counted or announced as a relink (got: $_bl_out)"
fi

# 5) the summary carries it. The counter only matters if the run's footer reports it —
#    that footer is what an OS repo's bootstrap prints, and it is the only place a user
#    who scrolled past the per-link lines can still see that something was displaced.
_bl_sum="$(bash -c '
  set -u
  . "'"$HERE/lib/bootstrap-lib.sh"'"
  ln -sfn "$2" "$3"; ln -sfn "$2" "$4"
  blib_link "$1" "$3" >/dev/null 2>&1
  blib_link "$1" "$4" >/dev/null 2>&1
  blib_wire_summary
' _ "$_bl/src" "$_bl/other" "$_bl/dst5" "$_bl/dst6" 2>&1)"
if [[ "$_bl_sum" == *"2 relinked"* ]]; then
  pass "blib_wire_summary: displaced links are reported in the run footer"
else
  fail "blib_wire_summary: the footer omits the relink tally (got: $_bl_sum)"
fi

# ── F8a. blib_link_os_layer's ssh overlay (lib/bootstrap-lib.sh) ─────────────
# The escape hatch #450 depends on, and the one overlay NO repo ships yet — so without a
# fixture it is code that has never run anywhere. It is also what makes moving ssh/config
# into Core safe to argue for: a layer with a genuinely OS-specific ssh need has somewhere
# to put it other than a forked copy of the whole client config, which is how seven repos
# ended up hand-maintaining byte-identical files.
#
# Two properties, and the second is the one that bites. blib_link honours BLIB_DRY on its
# own, but the mkdir/chmod this overlay needs do NOT — they are plain commands, so a
# --dry-run would create and chmod ~/.ssh/config.d on a box the operator was only
# inspecting. That is the exact asymmetry F8b pins for the role layer (one repo's dry-run
# mutated the box, the other's did not), caught here before it can happen again.
#
# No `have` guard: this needs only bash and the library, unlike F7 (git), so it runs
# everywhere — including the minimal containers where the heavier fixtures skip.
hdr "helper-adoption section is --strict-safe (audit-core.sh §5f)"
# The adoption section reads SIBLING repos off disk, and CI checks out only Core — so every
# run there takes a skip branch. --strict (which ci.yml passes) reds on TOOL-absent skips, so
# a sibling-absence skip landing in that class would turn the whole fleet's CI red the moment
# it landed, on every repo, for a purely advisory check.
#
# THIS CONTRACT CHANGED SHAPE. It used to be a WORDING rule: the skip text had to contain the
# literal "out of scope", because a substring test was what classified skips. That made the
# message the gate — you could not make the wording honest without moving a gate — and it
# filed "this box has no sibling to read" under the same heading as "you asked me to narrow
# this run". The class is recorded structurally now, by skip_env(), so what must be pinned is
# the CALL, not the prose. Wording is free to change; the classifier is not.
#
# Asserted statically on the source rather than by running the audit: reproducing "no sibling
# checked out" means a fake fleet root, and the property worth pinning is which function the
# section calls, which is exactly what a static read can see.
_ha_bad=0
while IFS= read -r _ha_line; do
  [ -n "$_ha_line" ] || continue
  case "$_ha_line" in
  *skip_env*) ;;
  *)
    fail "helper adoption: a plain skip() here lands in the TOOL-absent class and reds --strict in CI — $_ha_line"
    _ha_bad=1
    ;;
  esac
done <<EOF
$(grep -n 'skip[_a-z]* "helper adoption' "$HERE/scripts/audit-core.sh" 2>/dev/null || true)
EOF
if ((_ha_bad == 0)) && grep -q 'skip_env "helper adoption' "$HERE/scripts/audit-core.sh" 2>/dev/null; then
  pass "helper adoption: every sibling skip goes through skip_env, so --strict stays green in CI"
elif ((_ha_bad == 0)); then
  fail "helper adoption: audit-core.sh has no helper-adoption skip at all — the section is gone or renamed"
fi
# skip_env must actually EXIST and be the thing that records the class — otherwise the
# assertion above passes against a typo'd call that silently becomes an unbound command.
if grep -q '^skip_env()' "$HERE/scripts/lib/common.sh" && grep -q '_CORE_ENV_SKIPS' "$HERE/scripts/lib/common.sh"; then
  pass "helper adoption: skip_env is defined in common.sh and records the environment class"
else
  fail "helper adoption: skip_env is missing from common.sh — the sibling skips call nothing"
fi

# ── skip_env / _core_tool_skip_count: the classifier, as a unit ──────────────
# These drive _core_tool_skip_count ITSELF — the same function audit-core.sh calls. The
# previous version of this block re-implemented the classification loop inline, which meant it
# exercised its own copy and could never fail when audit-core.sh changed. It was demonstrated
# green while the defect it guarded was fully reintroduced in audit-core.sh. That is the whole
# reason the logic moved into common.sh: so a test can bind to the code that actually runs.
_tsc() { # <setup...> — run a scenario against the REAL helper, print its verdict
  CORE_JSON=1 bash -c '
    . "'"$HERE"'/scripts/lib/common.sh" 2>/dev/null || exit 9
    '"$1"'
    printf "%d %d %d" "$SKIP" "$(_core_tool_skip_count)" "${#_CORE_ENV_SKIPS[@]}"
  ' 2>/dev/null
}

# The happy partition: 1 tool, 1 scope, 2 environment.
_se_out="$(_tsc '
  skip     "luacheck (not installed)"
  skip     "nvim config load (out of scope)"
  skip_env "helper adoption (no sibling OS repo checked out — nothing to read here)"
  skip_env "coverage register (no sibling OS repo checked out — nothing to read here)"
')"
case "$_se_out" in
"4 1 2") pass "_core_tool_skip_count: 4 skips partition as 1 tool / 1 scope / 2 environment" ;;
"")      fail "_core_tool_skip_count: could not source scripts/lib/common.sh — the helper is unreachable" ;;
*)       fail "_core_tool_skip_count: partition is '$_se_out', want '4 1 2' (SKIP, tool, env) — --strict's meaning moved" ;;
esac

# THE POISONED-WORDING CASE — the one that was actually broken. An environment skip whose text
# contains "out of scope" must NOT cancel a genuine tool gap. Every call site in-tree is worded
# innocently, so only a test that supplies the poisoned wording can see this.
_pw_out="$(_tsc '
  skip     "luacheck (not installed)"
  skip_env "gitleaks policy (no sibling checked out — out of scope)"
')"
case "$_pw_out" in
"2 1 1") pass "_core_tool_skip_count: an env skip worded 'out of scope' does not cancel a real tool gap" ;;
*)       fail "_core_tool_skip_count: got '$_pw_out', want '2 1 1' — a poisoned env message masked an absent tool, so --strict goes green on a real gap" ;;
esac

# BINDING. The two assertions above are only worth anything if audit-core.sh actually uses the
# helper AND does not adjust the number afterwards. The demonstrated regression was precisely
# that shape: leave the classification correct, then re-add a subtracting statement after it.
_tb=0
_tb_asg="$(grep -c '^_tool_skips=' "$HERE/scripts/audit-core.sh" || true)"
[[ "$_tb_asg" == 1 ]] || {
  fail "binding: _tool_skips is assigned $_tb_asg times in audit-core.sh, want exactly 1 — a second assignment can undo a correct classification"
  _tb=1
}
grep -q '^_tool_skips="\$(_core_tool_skip_count)"' "$HERE/scripts/audit-core.sh" || {
  fail "binding: audit-core.sh does not take _tool_skips straight from _core_tool_skip_count — the tested helper is not the code that runs"
  _tb=1
}
grep -q '_tool_skips=\$((_tool_skips' "$HERE/scripts/audit-core.sh" && {
  fail "binding: audit-core.sh post-processes _tool_skips — this is the exact partial revert the helper was extracted to prevent"
  _tb=1
}
((_tb)) || pass "binding: audit-core.sh takes _tool_skips solely from _core_tool_skip_count, with no post-processing"

# --json must stay JSON-ONLY, and the FLEET sections are where that broke. Their advisory
# reports printed to stdout unguarded, so `audit-core.sh --json` emitted invalid JSON —
# but ONLY on a box with sibling repos checked out, because otherwise the sections skip
# before reaching the report. CI checks out just this repo, so CI never saw it. That is the
# same blind spot --require-siblings exists for, which is why this assertion lives here.
# ANCHORED to statement position (^[[:space:]]*printf) on purpose: a bare /printf/ also
# matches a printf inside a $( ) that BUILDS A STRING — §5g composes its report that way —
# and flagging those would be a false fire that teaches the next reader to widen the guard
# where no guard belongs. Only a printf that is the statement can reach stdout.
_jg_bad=0
while IFS= read -r _jg_line; do
  [ -n "$_jg_line" ] || continue
  case "$_jg_line" in
  *CORE_JSON*) ;;
  *)
    fail "--json: an unguarded fleet-section printf breaks JSON-only stdout — $_jg_line"
    _jg_bad=1
    ;;
  esac
done <<EOF
$(awk 'NR>=860 && NR<=1045 && /^[[:space:]]*printf/ && !/>&2/ {printf "%d: %s\n", NR, $0}' "$HERE/scripts/audit-core.sh" 2>/dev/null || true)
EOF
((_jg_bad)) || pass "--json: every fleet-section report line is CORE_JSON-guarded (stdout stays parseable)"
# The other half of "advisory": the section must not be able to FAIL. A future edit that
# swaps the report for a fail() would red every repo's CI on arrival, since 8 of 9 are short.
if ! grep -q 'fail "helper adoption' "$HERE/scripts/audit-core.sh" 2>/dev/null; then
  pass "helper adoption: the section reports and never fails (advisory by construction)"
else
  fail "helper adoption: the section can now fail — 8 of 9 repos are short, so this reds the fleet"
fi
unset _ha_bad _ha_line

hdr "git identity refuses to guess (useConfigOnly + a commented-out seed)"
# What a FRESHLY BOOTSTRAPPED box does when the user has not set an identity yet.
#
# The seeded ~/.config/git/local.gitconfig used to ship a live `Your Name
# <you@example.com>`, and gitconfig [include]s it — so the box had a VALID identity, commits
# succeeded, and they were authored as Your Name. Before bootstrap the same box had no
# identity and the commit would have failed loudly, so bootstrapping made the failure mode
# strictly worse; the result lands in public repo history, where authorship is not fixable
# retroactively (#476).
#
# Both halves are asserted because either alone is insufficient: with a live placeholder,
# useConfigOnly is satisfied and git commits; with it commented out but useConfigOnly unset,
# git invents $USER@$(hostname) and commits. Only the pair produces the error.
if have git; then
  _gi="$(mktemp -d "$SANDBOX/gitid.XXXXXX")"
  mkdir -p "$_gi/home/.config/git" "$_gi/repo"
  cp "$HERE/git/gitconfig" "$_gi/home/.gitconfig"
  # exactly what blib_seed does on a first bootstrap
  cp "$HERE/git/local.gitconfig.example" "$_gi/home/.config/git/local.gitconfig"
  # GIT_CONFIG_GLOBAL must be POINTED at the fixture's copy, not left to $HOME. This suite
  # exports GIT_CONFIG_GLOBAL=/dev/null suite-wide (so a developer's real signing config
  # cannot reach the tag-release fixtures), and that override wins over $HOME/.gitconfig
  # outright — git would read no global config at all here. The first draft of this block set
  # only HOME and passed two of its four assertions VACUOUSLY: with no config whatsoever there
  # is no identity, so "resolves no user.email" and "the commit fails" were both true for
  # entirely the wrong reason. HOME is still set because gitconfig's [include] path is written
  # as ~/.config/git/local.gitconfig and `~` is $HOME.
  _gi_git() {
    HOME="$_gi/home" XDG_CONFIG_HOME="$_gi/home/.config" \
      GIT_CONFIG_GLOBAL="$_gi/home/.gitconfig" git -C "$_gi/repo" "$@"
  }
  _gi_git init -q >/dev/null 2>&1
  printf 'x\n' >"$_gi/repo/a"
  _gi_git add a >/dev/null 2>&1

  # 1) the seed must not supply an identity. Asserted on the RESOLVED value rather than by
  #    grepping the example file: the whole defect was that the include made a commented-out
  #    line and a live one indistinguishable from where git stands.
  if [[ -z "$(_gi_git config --get user.email || true)" ]] &&
    [[ -z "$(_gi_git config --get user.name || true)" ]]; then
    pass "git identity: a freshly seeded box resolves NO user.name/user.email"
  else
    fail "git identity: the seed supplied an identity ($(_gi_git config --get user.name || true) <$(_gi_git config --get user.email || true)>)"
  fi
  # 2) useConfigOnly must be on, or git fills the gap with a guess instead of erroring.
  if [[ "$(_gi_git config --get user.useConfigOnly || true)" == "true" ]]; then
    pass "git identity: user.useConfigOnly is set, so git will not invent an author"
  else
    fail "git identity: useConfigOnly is not set — git would author as \$USER@\$(hostname)"
  fi
  # 3) THE property, end to end: the commit must FAIL, and its message must tell the user what
  #    to do. This is the assertion that catches the live-placeholder half — restoring the
  #    example's `name`/`email` makes it report `rc=0 — authored as Your Name
  #    <you@example.com>`, i.e. #476 verbatim. It does NOT discriminate on the useConfigOnly
  #    half on every box: where the hostname is not a FQDN git declines to guess an email and
  #    refuses anyway. That is exactly why assertion 2 checks the setting directly rather than
  #    relying on this one to cover both.
  _gi_out="$(_gi_git -c commit.gpgsign=false commit -m probe 2>&1)"
  _gi_rc=$?
  if ((_gi_rc != 0)) && grep -qi 'please tell me who you are' <<<"$_gi_out"; then
    pass "git identity: committing on an unconfigured box FAILS loudly, naming the fix"
  else
    fail "git identity: commit succeeded on an unconfigured box (rc=$_gi_rc) — authored as $(_gi_git log -1 --format='%an <%ae>' 2>/dev/null)"
  fi
  # 4) ...and filling the seed in must still work. useConfigOnly only refuses to GUESS; a
  #    configured identity has to keep working, or the fix would have traded one bug for a
  #    worse one.
  _gi_git config -f "$_gi/home/.config/git/local.gitconfig" user.name "Real Person" >/dev/null 2>&1
  _gi_git config -f "$_gi/home/.config/git/local.gitconfig" user.email "real@example.org" >/dev/null 2>&1
  if _gi_git -c commit.gpgsign=false commit -qm probe >/dev/null 2>&1 &&
    [[ "$(_gi_git log -1 --format='%an <%ae>' 2>/dev/null)" == "Real Person <real@example.org>" ]]; then
    pass "git identity: filling the seed in restores committing, with the real author"
  else
    fail "git identity: a filled-in local.gitconfig still could not commit"
  fi
  unset _gi _gi_out _gi_rc
else
  skip "git identity (git not installed)"
fi

hdr "blib_install_system_file (root-owned /etc write, non-destructive)"
# The system-file counterpart to the blib_link accounting above, and the same property:
# nothing that was already on the machine is destroyed unannounced. blib_link has had this
# since the beginning; `_blib_priv tee` into /etc never did, so each OS repo hand-rolled it
# and dotfiles-Arch did not — it re-rendered /etc/wsl.conf on every run of a script its docs
# call idempotent, and on a real box destroyed a pre-existing `[boot] systemd=true` (#475).
#
# BLIB_SU= throughout: the helper escalates through _blib_priv, and an empty BLIB_SU means
# "run directly". That is what makes this hermetic — it writes only under $SANDBOX and needs
# no sudo, so it runs identically in CI, in a container and on a developer box.
_sf="$(mktemp -d "$SANDBOX/sysfile.XXXXXX")"
# Same `bash -c` shape as _bl_run above, and for the same reason: the lib's re-entry guard
# makes a re-source a no-op, so the counters can only be read from a fresh interpreter.
_sf_run() { # <dry> <content> <dst>  → run output, then "--", then LINKED BACKED SKIPPED
  BLIB_DRY="$1" BLIB_SU='' bash -c '
    set -u
    . "'"$HERE/lib/bootstrap-lib.sh"'"
    blib_install_system_file "$1" "$2"
    printf -- "--\n%s %s %s\n" "$BLIB_LINKED" "$BLIB_BACKED" "$BLIB_SKIPPED"
  ' _ "$2" "$3" 2>&1
}
_sf_tally() { printf '%s' "${1##*$'--\n'}" | tr -d '\n'; }

# 1) THE #475 CASE, verbatim: a real pre-existing /etc/wsl.conf carrying systemd=true, and a
#    bootstrap that renders something else. The old content must survive on disk.
mkdir -p "$_sf/etc"
printf '[boot]\nsystemd=true\n' >"$_sf/etc/wsl.conf"
_sf_out="$(_sf_run 0 "$(printf '[interop]\nappendWindowsPath=false')" "$_sf/etc/wsl.conf")"
_sf_bak="$(find "$_sf/etc" -name 'wsl.conf.pre-dotfiles.*' 2>/dev/null | head -n1)"
if [[ -n "$_sf_bak" ]] && grep -q 'systemd=true' "$_sf_bak" &&
  grep -q 'appendWindowsPath=false' "$_sf/etc/wsl.conf" && [[ "$_sf_out" == *"backed up existing"* ]]; then
  pass "blib_install_system_file: an existing /etc file is preserved, announced, and replaced"
else
  fail "blib_install_system_file: the pre-existing file was not backed up (got: $_sf_out)"
fi
# The backup must be findable by the SAME convention as a dotfile backup — one naming rule
# for the whole system, which is the whole point of routing it through _blib_backup_suffix.
if [[ "${_sf_bak##*/}" =~ ^wsl\.conf\.pre-dotfiles\.[0-9]{8}-[0-9]{6}\.[0-9]+$ ]]; then
  pass "blib_install_system_file: the backup uses the shared .pre-dotfiles.<stamp>.<pid> name"
else
  fail "blib_install_system_file: backup name '${_sf_bak##*/}' is not the shared convention (#464)"
fi
# ...and it must be counted, or the closing summary would report a clean run over a displaced
# system file — the aggregate half of the same silence.
if [[ "$(_sf_tally "$_sf_out")" == "0 1 0" ]]; then
  pass "blib_install_system_file: a displaced system file counts into BLIB_BACKED"
else
  fail "blib_install_system_file: wrong tally '$(_sf_tally "$_sf_out")' (want LINKED=0 BACKED=1 SKIPPED=0)"
fi

# 2) IDEMPOTENCE, which is the property the helper is really for. A second run with the same
#    rendering must write nothing and back up nothing — otherwise a weekly re-bootstrap
#    accumulates a directory of identical .pre-dotfiles copies, which is its own damage.
_sf_n1="$(find "$_sf/etc" -name 'wsl.conf.pre-dotfiles.*' | wc -l | tr -d ' ')"
_sf_out="$(_sf_run 0 "$(printf '[interop]\nappendWindowsPath=false')" "$_sf/etc/wsl.conf")"
_sf_n2="$(find "$_sf/etc" -name 'wsl.conf.pre-dotfiles.*' | wc -l | tr -d ' ')"
if [[ "$_sf_n1" == "$_sf_n2" ]] && [[ "$(_sf_tally "$_sf_out")" == "0 0 1" ]] &&
  [[ "$_sf_out" != *"backed up"* ]]; then
  pass "blib_install_system_file: an identical re-run is a silent no-op (no second backup)"
else
  fail "blib_install_system_file: re-run was not a no-op (backups $_sf_n1 -> $_sf_n2, tally '$(_sf_tally "$_sf_out")')"
fi
# The same content rendered the way a bootstrap actually renders it — a heredoc, i.e. WITH a
# trailing newline. $(...) strips trailing newlines from what is read off disk but nothing
# strips them from the argument, so without the normalisation inside the helper this compares
# unequal to the file the helper itself just wrote and rewrites on EVERY run: the exact
# non-idempotence the helper exists to remove, reintroduced one layer up.
_sf_out="$(_sf_run 0 "$(printf '[interop]\nappendWindowsPath=false\n\n')" "$_sf/etc/wsl.conf")"
_sf_n3="$(find "$_sf/etc" -name 'wsl.conf.pre-dotfiles.*' | wc -l | tr -d ' ')"
if [[ "$_sf_n2" == "$_sf_n3" ]] && [[ "$(_sf_tally "$_sf_out")" == "0 0 1" ]]; then
  pass "blib_install_system_file: trailing newlines do not make a heredoc rendering look changed"
else
  fail "blib_install_system_file: trailing-newline difference triggered a rewrite (backups $_sf_n2 -> $_sf_n3)"
fi

# 3) an ABSENT destination is written, with no backup and nothing counted as displaced.
_sf_out="$(_sf_run 0 'key=value' "$_sf/etc/fresh.conf")"
if [[ "$(cat "$_sf/etc/fresh.conf" 2>/dev/null)" == "key=value" ]] &&
  [[ "$(_sf_tally "$_sf_out")" == "0 0 0" ]]; then
  pass "blib_install_system_file: an absent destination is created and nothing is counted"
else
  fail "blib_install_system_file: absent-destination write wrong (tally '$(_sf_tally "$_sf_out")')"
fi

# 4) BLIB_DRY must PLAN and touch nothing. Asserted on the file's bytes, not just the message:
#    a dry run that announced correctly and wrote anyway would satisfy a message-only check,
#    and this helper's whole audience is people who run --dry-run before letting it near /etc.
_sf_before="$(cat "$_sf/etc/wsl.conf")"
_sf_out="$(_sf_run 1 'totally different' "$_sf/etc/wsl.conf")"
_sf_n4="$(find "$_sf/etc" -name 'wsl.conf.pre-dotfiles.*' | wc -l | tr -d ' ')"
if [[ "$(cat "$_sf/etc/wsl.conf")" == "$_sf_before" ]] && [[ "$_sf_n3" == "$_sf_n4" ]] &&
  [[ "$_sf_out" == *"would back up + write"* ]] && [[ "$(_sf_tally "$_sf_out")" == "0 1 0" ]]; then
  pass "blib_install_system_file: BLIB_DRY plans the write and backup, and changes nothing"
else
  fail "blib_install_system_file: dry run mutated the box or did not announce (got: $_sf_out)"
fi

# 5) a missing destination argument must warn, not write somewhere surprising, and must not
#    take down a bootstrap running under `set -e`.
_sf_out="$(_sf_run 0 'content' '')"
if [[ "$_sf_out" == *"no destination given"* ]] && [[ "$(_sf_tally "$_sf_out")" == "0 0 0" ]]; then
  pass "blib_install_system_file: a missing destination warns and returns cleanly"
else
  fail "blib_install_system_file: missing destination mishandled (got: $_sf_out)"
fi

hdr "blib_link_os_layer ssh overlay (config.d drop-in, dry-run safe)"
# Local rather than F7's _lr_mode: that one is defined inside `if have git`, so it does
# not exist on a box without git, where this fixture still runs.
_ol_mode() { # <path> — octal permission bits, GNU or BSD stat (the macOS CI leg)
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}
_ol_wire() { # run blib_link_os_layer against the fixture, honouring the caller's BLIB_DRY
  HOME="$_ol/home" XDG_CONFIG_HOME="$_ol/config" bash -c '
    set -u
    . "'"$HERE/lib/bootstrap-lib.sh"'"
    blib_link_os_layer "'"$_ol"'/repo" "'"$_ol"'/config" testos
  ' >/dev/null 2>&1
}
_ol="$(mktemp -d "$SANDBOX/oslayer.XXXXXX")"
mkdir -p "$_ol/home" "$_ol/config" "$_ol/repo/ssh"
printf 'Host *\n  IdentityAgent ~/.1password/agent.sock\n' >"$_ol/repo/ssh/os.conf"

# 1) --dry-run must touch NOTHING, not even the directory.
BLIB_DRY=1 _ol_wire
if [[ ! -e "$_ol/home/.ssh/config.d" ]]; then
  pass "os layer: --dry-run creates no ~/.ssh/config.d and links nothing"
else
  fail "os layer: --dry-run created ~/.ssh/config.d — the mkdir/chmod escaped the BLIB_DRY guard"
fi

# 2) the real run links it at the numbered drop-in path, with ssh's required 0700.
_ol_wire
_ol_bad=""
[[ -L "$_ol/home/.ssh/config.d/50-os.conf" ]] || _ol_bad="$_ol_bad link(missing)"
[[ "$(readlink "$_ol/home/.ssh/config.d/50-os.conf" 2>/dev/null)" == "$_ol/repo/ssh/os.conf" ]] ||
  _ol_bad="$_ol_bad link(wrong-target)"
[[ "$(_ol_mode "$_ol/home/.ssh/config.d")" == 700 ]] || _ol_bad="$_ol_bad config.d(perms)"
if [[ -z "$_ol_bad" ]]; then
  pass "os layer: ssh/os.conf links to ~/.ssh/config.d/50-os.conf with the dir at 0700"
else
  fail "os layer: ssh overlay wiring wrong —$_ol_bad"
fi

# 3) a repo WITHOUT one is the normal case, not a gap — no repo ships ssh/os.conf today,
#    so a version of this that linked unconditionally would break every one of them.
rm -f "$_ol/repo/ssh/os.conf"
rm -rf "$_ol/home/.ssh"
_ol_wire
if [[ ! -e "$_ol/home/.ssh/config.d/50-os.conf" ]]; then
  pass "os layer: no ssh/os.conf is a silent no-op (the case every repo is in today)"
else
  fail "os layer: linked a 50-os.conf with no source file"
fi


# ── F8b. blib_link_role_layer (lib/bootstrap-lib.sh) ─────────────────────────
# The Role band (85-94) had no Core wiring for years, so BOTH role repos hand-rolled it
# and drifted: dotfiles-Defense honoured BLIB_DRY when dropping the stale pre-v4
# unnumbered link, dotfiles-Offense did not — so the same `--dry-run` mutated one box and
# not the other. That asymmetry is exactly what case 3 below pins.
#
# The other invariant worth a test is a NEGATIVE one: a role repo must never write band
# 80. That band belongs to the OS repo underneath it, and a role layer that claimed it
# would silently displace the OS layer's fragment on every bootstrap — a failure that
# looks like "my aliases vanished", three layers from its cause.
hdr "blib_link_role_layer (band 85 + tmux/role.conf, and never band 80)"
_rl="$(mktemp -d "$SANDBOX/rolelayer.XXXXXX")"
mkdir -p "$_rl/repo/offensive/templates"
printf 'ROLEZSH\n'  >"$_rl/repo/offensive/offensive.zsh"
printf 'ROLECONF\n' >"$_rl/repo/offensive/offensive.conf"
printf 'TPL\n'      >"$_rl/repo/offensive/templates/engagement.md"

# Fresh `bash -c` per case: the lib's re-entry guard makes a re-source a no-op, and these
# need BLIB_DRY / BLIB_SKIP read from a clean start. <dry> <skip-csv> <config-dir>.
_rl_run() {
  BLIB_DRY="$1" bash -c '
    set -u
    . "'"$HERE/lib/bootstrap-lib.sh"'"
    [ -n "$2" ] && blib_select --skip "$2"
    blib_link_role_layer "$1/repo" "$3" offensive
  ' _ "$_rl" "$2" "$3" 2>&1
}

# 1) the full wire: band 85, tmux/role.conf, and templates under <config>/<role>/.
_rl_c1="$_rl/cfg1"
_rl_out="$(_rl_run 0 "" "$_rl_c1")"
if [[ "$(readlink "$_rl_c1/zsh/85-offensive.zsh")" == "$_rl/repo/offensive/offensive.zsh" ]] &&
  [[ "$(readlink "$_rl_c1/tmux/role.conf")" == "$_rl/repo/offensive/offensive.conf" ]] &&
  [[ "$(readlink "$_rl_c1/offensive/templates")" == "$_rl/repo/offensive/templates" ]]; then
  pass "blib_link_role_layer: wires 85-<role>.zsh, tmux/role.conf and <role>/templates"
else
  fail "blib_link_role_layer: the role surface is not fully wired (got: $_rl_out)"
fi

# 2) it must NOT touch band 80 — that is the OS repo's, and this helper has no business
#    there even though the role fragment rides the same `zsh` group.
if [[ ! -e "$_rl_c1/zsh/80-os.zsh" ]]; then
  pass "blib_link_role_layer: leaves band 80 alone (the OS repo owns it)"
else
  fail "blib_link_role_layer: wrote band 80 — a role layer would displace the OS fragment"
fi

# 3) the stale pre-v4 unnumbered link. The v4 loader globs NN-*.zsh, so an unnumbered
#    <role>.zsh is INERT while still looking wired — it must be dropped on a real run and
#    SURVIVE a dry run. The second half is the drift this helper was written to end.
_rl_c3="$_rl/cfg3"
mkdir -p "$_rl_c3/zsh"
ln -sfn "$_rl/repo/offensive/offensive.zsh" "$_rl_c3/zsh/offensive.zsh"
_rl_out="$(_rl_run 1 "" "$_rl_c3")"
if [[ -L "$_rl_c3/zsh/offensive.zsh" ]] && [[ ! -e "$_rl_c3/zsh/85-offensive.zsh" ]] &&
  [[ "$_rl_out" == *"would drop stale pre-v4 link"* ]]; then
  pass "blib_link_role_layer: BLIB_DRY names the stale pre-v4 link and removes nothing"
else
  fail "blib_link_role_layer: dry-run mutated the box or hid the stale link (got: $_rl_out)"
fi
_rl_out="$(_rl_run 0 "" "$_rl_c3")"
if [[ ! -e "$_rl_c3/zsh/offensive.zsh" ]] &&
  [[ "$(readlink "$_rl_c3/zsh/85-offensive.zsh")" == "$_rl/repo/offensive/offensive.zsh" ]]; then
  pass "blib_link_role_layer: a real run drops the inert pre-v4 link and numbers the fragment"
else
  fail "blib_link_role_layer: the stale unnumbered link survived a real run (got: $_rl_out)"
fi

# 4) group gating, both directions in one pass: --skip tmux must drop role.conf WITHOUT
#    dropping the zsh fragment. A helper that ignored blib_want would wire both; one that
#    gated the whole function on a single group would wire neither.
_rl_c4="$_rl/cfg4"
_rl_out="$(_rl_run 0 tmux "$_rl_c4")"
if [[ ! -e "$_rl_c4/tmux/role.conf" ]] &&
  [[ "$(readlink "$_rl_c4/zsh/85-offensive.zsh")" == "$_rl/repo/offensive/offensive.zsh" ]]; then
  pass "blib_link_role_layer: --skip tmux drops role.conf and keeps the band-85 fragment"
else
  fail "blib_link_role_layer: --skip tmux gated the wrong half (got: $_rl_out)"
fi

# 5) <role> names the directory AND the stem, so a role with no .conf (dotfiles-Defense
#    ships none today) wires cleanly instead of leaving a dangling tmux/role.conf.
mkdir -p "$_rl/repo2/defense"
printf 'BLUE\n' >"$_rl/repo2/defense/defense.zsh"
_rl_c5="$_rl/cfg5"
_rl_out="$(BLIB_DRY=0 bash -c '
  set -u
  . "'"$HERE/lib/bootstrap-lib.sh"'"
  blib_link_role_layer "$1/repo2" "$2" defense
' _ "$_rl" "$_rl_c5" 2>&1)"
# -e AND -L, not -e alone: bash's -e follows the link, so it is FALSE for a dangling
# symlink — an -e-only assertion would pass on exactly the regression this test is named
# after. -L catches the dangling case, -e catches a real file or directory.
if [[ "$(readlink "$_rl_c5/zsh/85-defense.zsh")" == "$_rl/repo2/defense/defense.zsh" ]] &&
  [[ ! -e "$_rl_c5/tmux/role.conf" && ! -L "$_rl_c5/tmux/role.conf" ]]; then
  pass "blib_link_role_layer: a role with no .conf and no templates leaves no dangling role.conf"
else
  fail "blib_link_role_layer: the no-.conf role wired wrongly (got: $_rl_out)"
fi

# ── F8c. package-list reading (lib/bootstrap-lib.sh) ─────────────────────────
# blib_read_pkgs had NO coverage, which is how #460 survived: it read its file with a bare
# redirect and no existence check, and every caller reaches it through a process
# substitution, where `mapfile` reports its OWN status rather than the reader's. A missing
# packages.txt therefore produced a zero-length array WITH A SUCCESS STATUS, and a broken
# clone provisioned nothing while reporting that as intended.
#
# blib_read_pkgs_into is the shape that actually fixes it — it assigns in the CALLER'S
# frame, so `|| exit 1` works. These pin both halves: the guard on the old function (loud
# even where the status is discarded) and the new function's status/assignment contract.
hdr "package-list reading (a missing list is a failure, not an empty array)"
_rp="$(mktemp -d "$SANDBOX/readpkgs.XXXXXX")"
printf 'foo # inline comment\n\n# whole-line comment\n  bar  \nbaz\n' >"$_rp/list.txt"
# A list whose LAST line is a comment — the common real shape, and the one that made the
# old `[[ -n "$line" ]] && printf …` tail return 1 from the loop.
printf 'pkg\n# trailing comment\n' >"$_rp/comment-final.txt"

# Fresh `bash -c` per case (the lib's re-entry guard makes a re-source a no-op at file
# scope). Prints the case's own verdict lines; the assertions match on those.
_rp_run() { bash -c '
  set -uo pipefail
  . "'"$HERE/scripts/lib/common.sh"'"
  . "'"$HERE/lib/bootstrap-lib.sh"'"
  '"$1"'
' 2>&1; }

# 1) THE BUG. An unreadable list must fail, loudly, and must not hand back a plausible
#    empty array. Both halves matter: the status is what a caller tests, the warning is
#    what an operator reads when the caller is the process-substitution form that cannot.
_rp_out="$(_rp_run '
  blib_read_pkgs_into pkgs /nonexistent/packages.txt && echo "STATUS=0" || echo "STATUS=$?"
  echo "SIZE=${#pkgs[@]}"
')"
if [[ "$_rp_out" == *"STATUS=1"* && "$_rp_out" == *"SIZE=0"* &&
  "$_rp_out" == *"not readable"* ]]; then
  pass "blib_read_pkgs_into: an unreadable list returns 1, warns, and yields no packages"
else
  fail "blib_read_pkgs_into: a missing list did not fail loudly (got: $_rp_out)"
fi

# 2) The happy path still parses exactly as before: inline comments, whole-line comments,
#    blank lines and surrounding whitespace all stripped.
_rp_out="$(_rp_run '
  blib_read_pkgs_into pkgs "'"$_rp"'/list.txt" || echo "STATUS=$?"
  echo "GOT=${#pkgs[@]}:${pkgs[*]}"
')"
if [[ "$_rp_out" == *"GOT=3:foo bar baz"* ]]; then
  pass "blib_read_pkgs_into: comments, blanks and whitespace are stripped into the array"
else
  fail "blib_read_pkgs_into: parsing drifted from blib_read_pkgs (got: $_rp_out)"
fi

# 3) The two readers must not disagree. CI and bootstrap both read the same file, and a
#    gate that parses it differently from the thing it gates is worse than no gate.
# core_files_identical, NOT diff — diffutils is not guaranteed present, and the Arch CI
# container is a box that genuinely lacks it. That is the same rule #572 records for `cmp`
# (they ship in the same package); the gate below now bans both.
_rp_out="$(_rp_run '
  blib_read_pkgs_into pkgs "'"$_rp"'/list.txt"
  blib_read_pkgs "'"$_rp"'/list.txt" >"'"$_rp"'/via-print.txt"
  printf "%s\n" "${pkgs[@]}" >"'"$_rp"'/via-array.txt"
  if core_files_identical "'"$_rp"'/via-print.txt" "'"$_rp"'/via-array.txt"; then
    echo AGREE
  else echo DIFFER; fi
')"
if [[ "$_rp_out" == *AGREE* ]]; then
  pass "blib_read_pkgs and blib_read_pkgs_into parse a list identically"
else
  fail "the two package-list readers disagree (got: $_rp_out)"
fi

# 4) A PROCESS SUBSTITUTION argument still works. dotfiles-Debian calls
#    `blib_read_pkgs <(pkg_filter_lines "$base_list" "$OS_ID")` to drop the lines annotated
#    for other distros, and that argument is a /dev/fd/N PIPE. This is why the guard is
#    `-r` and not `-f`: the obvious existence check would reject it and break a working
#    caller, turning a bug fix into an outage on one repo.
_rp_out="$(_rp_run '
  blib_read_pkgs_into pkgs <(printf "foo # c\n\nbar\n") || echo "STATUS=$?"
  echo "GOT=${#pkgs[@]}:${pkgs[*]}"
')"
if [[ "$_rp_out" == *"GOT=2:foo bar"* ]]; then
  pass "blib_read_pkgs_into: a /dev/fd process substitution is readable (the Debian shape)"
else
  fail "blib_read_pkgs_into: rejected a process substitution — -f crept back in (got: $_rp_out)"
fi

# 5) A failed read CLEARS the array rather than leaving the previous run's contents, so a
#    caller that ignores the status cannot silently install a stale list.
_rp_out="$(_rp_run '
  blib_read_pkgs_into pkgs "'"$_rp"'/list.txt"
  blib_read_pkgs_into pkgs /nonexistent 2>/dev/null
  echo "SIZE=${#pkgs[@]}"
')"
if [[ "$_rp_out" == *"SIZE=0"* ]]; then
  pass "blib_read_pkgs_into: a failed read empties the array (no stale package list)"
else
  fail "blib_read_pkgs_into: stale contents survived a failed read (got: $_rp_out)"
fi

# 6) The array NAME is spliced into an eval, so anything but a plain identifier must be
#    rejected before it gets there — this is a code-injection surface, not a typo check.
_rp_out="$(_rp_run '
  blib_read_pkgs_into "x;touch '"$_rp"'/PWNED" "'"$_rp"'/list.txt" && echo "STATUS=0" || echo "STATUS=$?"
  blib_read_pkgs_into "9lead" "'"$_rp"'/list.txt" 2>/dev/null && echo "D=0" || echo "D=$?"
')"
if [[ "$_rp_out" == *"STATUS=2"* && "$_rp_out" == *"D=2"* && ! -e "$_rp/PWNED" ]]; then
  pass "blib_read_pkgs_into: a malformed array name returns 2 and never reaches the eval"
else
  fail "blib_read_pkgs_into: a bad array name was not rejected (got: $_rp_out)"
fi

# 7) blib_read_pkgs' own status is now MEANINGFUL, so it has to be right in both
#    directions. The failure case is the point of #460; the success case is the
#    regression it could have introduced — the function used to end on
#    `[[ -n "$line" ]] && printf …`, so a list whose final line is a comment returned 1.
#    Harmless while every caller discarded the status, a landmine the moment one stops.
_rp_out="$(_rp_run '
  blib_read_pkgs "'"$_rp"'/comment-final.txt" >/dev/null && echo "OK=0" || echo "OK=$?"
  blib_read_pkgs /nonexistent >/dev/null 2>&1 && echo "MISS=0" || echo "MISS=$?"
')"
if [[ "$_rp_out" == *"OK=0"* && "$_rp_out" == *"MISS=1"* ]]; then
  pass "blib_read_pkgs: exits 0 on a comment-final list and 1 on a missing one"
else
  fail "blib_read_pkgs: status contract is wrong in one direction (got: $_rp_out)"
fi

# ── F9. tag-release.sh — the tag may only exist on a commit that is on main ──
# This script had NO coverage, which is how its ordering bug survived: it used to commit
# AND tag in one step, leaving a local vX.Y.Z on a commit that was not yet on main. A
# concurrent session pushing with push.followTags carried exactly such a tag to origin and
# fired release.yml + sync-fanout.yml against an unmerged commit — eight bad vendor PRs,
# and a retired version number, because release tags are immutable by ruleset.
#
# The invariant these pin: a vX.Y.Z tag only ever exists on a commit already on
# origin/main. Phase 1 must create NO tag; phase 2 must refuse unless origin/main really
# carries the version.
if have git; then
  hdr "tag-release.sh two-phase ordering (hermetic fixtures)"
  TR="$SANDBOX/tagrelease"
  rm -rf "$TR"; mkdir -p "$TR"
  _trg() { git -C "$1" -c commit.gpgsign=false -c user.email=t@example.com -c user.name=t "${@:2}"; }
  _tr_ident() {
    git -C "$1" config user.email t@example.com
    git -C "$1" config user.name t
    git -C "$1" config commit.gpgsign false
  }
  # A miniature release repo: the REAL tag-release.sh plus the two files it reads, and an
  # "origin" it can fetch. audit is stubbed so the gate can be driven without running the
  # real one inside a test.
  mkdir -p "$TR/origin/scripts/lib" "$TR/origin/lib"
  cp "$HERE/scripts/tag-release.sh" "$TR/origin/scripts/"
  cp "$HERE/scripts/lib/common.sh" "$TR/origin/scripts/lib/"
  cp "$HERE/lib/ux.sh" "$TR/origin/lib/"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$TR/origin/scripts/audit-core.sh"
  chmod +x "$TR/origin/scripts/audit-core.sh" "$TR/origin/scripts/tag-release.sh"
  printf '1.0.0\n' >"$TR/origin/core.version"
  printf '# Changelog\n\n## [Unreleased]\n\n## [v1.0.0] - 2026-01-01\n\n- released\n' >"$TR/origin/CHANGELOG.md"
  _trg "$TR/origin" init -q >/dev/null 2>&1
  _tr_ident "$TR/origin"
  _trg "$TR/origin" symbolic-ref HEAD refs/heads/main
  _trg "$TR/origin" add -A; _trg "$TR/origin" commit -q -m "v1.0.0"
  # The fixture "origin" is a normal repo with main checked out, so a push to that branch
  # is refused by default. Allow it: the test needs to LAND the release on origin's main
  # to exercise the guard, and nothing here reads origin's worktree.
  git -C "$TR/origin" config receive.denyCurrentBranch ignore
  git -c commit.gpgsign=false clone -q "$TR/origin" "$TR/work" >/dev/null 2>&1
  _tr_ident "$TR/work"
  _TRS="$TR/work/scripts/tag-release.sh"

  # Stage a 1.1.0 release in the clone, exactly as release.sh would leave it.
  printf '1.1.0\n' >"$TR/work/core.version"
  printf '# Changelog\n\n## [Unreleased]\n\n## [v1.1.0] - 2026-02-02\n\n- new\n\n## [v1.0.0] - 2026-01-01\n\n- released\n' >"$TR/work/CHANGELOG.md"

  # LC_ALL=C so assertions on this output mean the same thing on every box: the script's
  # own strings are ours and stable, but anything bash or git emits — notably a shell's
  # "command not found" — is localized, and an assertion that greps a translated
  # diagnostic silently stops matching rather than failing.
  # -u CORE_JSON alongside the pins: under --json, common.sh's skip() prints NOTHING (stdout
  # must carry only the JSON object), and both test-core.sh and audit-core.sh EXPORT
  # CORE_JSON=1 for that mode. The fixture inherits it, the advanced-tip notice vanishes,
  # and the assertion below fails for a reason that has nothing to do with tag-release.sh.
  # Verified: before this, `test-core.sh --json` reported the notice missing. The rule this
  # follows — a fixture asserting on OUTPUT must pin every variable that governs how output
  # is produced — is the same one behind LC_ALL and CORE_COLOR here, and $EDITOR below.
  _tr_run() { (cd "$TR/work" && env -u CORE_JSON LC_ALL=C CORE_COLOR=never TAG_SKIP_AUDIT=1 bash "$_TRS" "$@" 2>&1); }

  # THE property. Phase 1 commits and must leave NO tag behind — there must be nothing
  # for a stray push to carry while the commit is still off main.
  _tr_out="$(_tr_run)"; _tr_rc=$?
  _tr_tags="$(_trg "$TR/work" tag -l | tr '\n' ' ')"
  if ((_tr_rc == 0)) && [[ -z "$_tr_tags" ]] &&
    [[ -n "$(_trg "$TR/work" log --oneline -1 --grep='release v1.1.0')" ]]; then
    pass "tag-release: phase 1 commits the release and creates NO tag"
  else
    fail "tag-release: phase 1 left tags '$_tr_tags' (rc=$_tr_rc) — a pre-merge tag is the hazard"
  fi

  # Phase 2 must REFUSE while the commit is only local: origin/main still carries 1.0.0.
  _tr_out="$(_tr_run --publish)"; _tr_rc=$?
  if ((_tr_rc != 0)) && grep -q 'has not merged' <<<"$_tr_out" &&
    [[ -z "$(_trg "$TR/work" tag -l 'v1.1.0')" ]]; then
    pass "tag-release: --publish refuses while origin/main lacks the version (no tag created)"
  else
    fail "tag-release: --publish tagged a release that had not landed (rc=$_tr_rc)"
  fi

  # The withdrawn flag must fail loudly rather than silently doing the old thing.
  _tr_out="$(_tr_run --push)"; _tr_rc=$?
  if ((_tr_rc == 2)) && grep -q 'was removed' <<<"$_tr_out"; then
    pass "tag-release: the withdrawn --push flag fails with a pointer to --publish"
  else
    fail "tag-release: --push did not fail cleanly (rc=$_tr_rc)"
  fi

  # Land the release on origin's main — and then let main ADVANCE, which is the case
  # that matters. core.version does not change again until the next release, so "the tip
  # carries $VERSION" stays true for every later commit; tagging the tip would sweep work
  # still under [Unreleased] into the release, and release.yml builds the body from the
  # [vX.Y.Z] section, so it would ship undescribed.
  _trg "$TR/work" push -q origin HEAD:main 2>/dev/null
  _tr_release_sha="$(_trg "$TR/work" rev-parse HEAD)"
  # a later, unrelated commit on origin/main
  printf 'later\n' >"$TR/work/later.txt"
  _trg "$TR/work" add later.txt; _trg "$TR/work" commit -q -m "unrelated work after the release"
  _trg "$TR/work" push -q origin HEAD:main 2>/dev/null
  _trg "$TR/work" fetch -q origin

  _tr_out="$(_tr_run --publish)"; _tr_rc=$?
  _tr_at="$(_trg "$TR/work" rev-parse -q --verify 'v1.1.0^{commit}' 2>/dev/null)"
  _tr_tip="$(_trg "$TR/work" rev-parse -q --verify origin/main 2>/dev/null)"
  if ((_tr_rc == 0)) && [[ "$_tr_at" == "$_tr_release_sha" ]]; then
    pass "tag-release: --publish tags the RELEASE commit, not origin/main's tip"
  else
    fail "tag-release: tagged $_tr_at, wanted the release commit $_tr_release_sha (tip=$_tr_tip, rc=$_tr_rc)"
  fi
  if [[ "$_tr_at" != "$_tr_tip" ]]; then
    pass "tag-release: the tip had advanced, and the tag did not follow it"
  else
    fail "tag-release: fixture did not actually advance the tip — the assertion above proves nothing"
  fi
  # No undefined helper on the publish path. This run just exercised the advanced-tip
  # branch, which called a `note` that scripts/lib/common.sh has never defined (it defines
  # pass/skip/fail/hdr/have) — so it printed "note: command not found" and SWALLOWED the
  # very notice it exists to give. It survived because this branch only runs when main has
  # moved past the release commit, and because shellcheck cannot flag a bare word that
  # might be some command on PATH; the assertions above only ever inspected tags, never the
  # output. It fired for real while publishing v4.12.2.
  #
  # BOTH halves, because either alone is satisfiable by the wrong thing:
  #   * absence of the shell diagnostic alone passes if the notice is DELETED — the
  #     user-visible regression (no notice at all) would sail through;
  #   * presence of the notice alone would pass while a second, later helper was undefined.
  # And the diagnostic is matched only as a NEGATIVE, because bash localizes "command not
  # found" — a translated shell would silently satisfy a positive match. The notice text
  # is ours and stable, so that is the half worth asserting positively. _tr_run pins
  # LC_ALL=C so the negative match stays meaningful wherever this runs.
  # Order matters for the DIAGNOSIS, not the verdict. An undefined helper fails both halves
  # at once — bash prints "…: command not found" and the message text never appears, since
  # the words were arguments to a command that does not exist — so testing the missing
  # notice first would report "deleted? suppressed?" for a helper that is merely misspelled.
  # Check the specific cause first and let the general one catch the rest.
  if grep -qi 'command not found' <<<"$_tr_out"; then
    fail "tag-release: --publish invoked an undefined helper: $(grep -i 'command not found' <<<"$_tr_out" | head -1)"
  elif ! grep -q 'origin/main has advanced' <<<"$_tr_out"; then
    fail "tag-release: --publish printed NO advanced-tip notice — the fixture advanced the tip, so it was due (deleted? suppressed?)"
  else
    pass "tag-release: --publish emits the advanced-tip notice, via a helper that exists"
  fi
  # ...and the moving major alias rides along to the same commit.
  if [[ "$(_trg "$TR/work" rev-parse -q --verify 'v1^{commit}' 2>/dev/null)" == "$_tr_release_sha" ]]; then
    pass "tag-release: --publish moves the vN alias to the release commit too"
  else
    fail "tag-release: the vN alias did not follow the release"
  fi

  # ── the alias must be ANNOTATED, or signing operators cannot publish (#506) ──────────
  # The assertion above passes on any box with `tag.gpgsign` OFF, which is why this shipped
  # broken: under `tag.gpgsign = true` git makes every tag SIGNED — therefore annotated —
  # so a message-less `git tag -f "$MAJOR"` aborts with "fatal: no tag message?" and the
  # publish dies AFTER creating the immutable tag locally. It broke the first real release
  # cut by an operator with signing enabled (v4.12.2).
  #
  # This cannot be driven by simply flipping gpgsign on in the fixture: git would then try
  # to actually sign, and CI has no key, so the test would fail for an unrelated reason and
  # prove nothing. Note also WHY the fixture never caught this on the maintainer's own box,
  # where signing IS on — this suite exports GIT_CONFIG_GLOBAL=/dev/null (above), so the
  # fixture is hermetic from exactly the config that triggers the bug. Hermeticity is right,
  # and it is also what hid this. Pin it from both ends instead, neither needing a key:
  #   1. the hazard is REAL — the message-less form still fails under gpgsign, and it fails
  #      BEFORE any signing is attempted, so no key is required to observe it;
  #   2. the alias the script ACTUALLY produced is annotated and carries a message.
  _tr_gpgd="$SANDBOX/tagsign"; rm -rf "$_tr_gpgd"; mkdir -p "$_tr_gpgd"
  git init -q "$_tr_gpgd"; _tr_ident "$_tr_gpgd"
  git -C "$_tr_gpgd" commit -q --allow-empty -m x
  # Assert the STATUS and ONLY the status. The wording is environment-dependent, not a
  # stable contract: with no message and no -m, git needs one, and how it complains
  # depends on whether it can open an editor —
  #     macOS, interactive:  fatal: no tag message?
  #     CI, no TTY/EDITOR:   error: Terminal is dumb, but EDITOR unset
  # Both are the same hazard. An earlier version of this assertion demanded the first
  # wording and went red across all four CI legs for a difference that says nothing about
  # the bug. The message is kept for the failure text, where it aids diagnosis, and is
  # never gated on.
  # GIT_EDITOR=true, and the inherited editor vars cleared. Without this the probe is only
  # deterministic where there is no editor to launch — i.e. CI. On a developer's
  # interactive `make audit`, git would open $EDITOR here to collect the tag message and
  # BLOCK the suite on a modal vim; saving a message would then let it proceed to a real
  # signing attempt, which is neither what this asserts nor guaranteed to be possible.
  # `true` is a no-op editor: it exits 0 having written nothing, so the message stays
  # empty and git aborts exactly as it does in CI — deterministic, key-free, everywhere.
  _tr_sign_err="$(LC_ALL=C GIT_EDITOR=true EDITOR=true VISUAL=true \
    git -C "$_tr_gpgd" -c tag.gpgsign=true tag -f vSIG 2>&1)"
  _tr_sign_rc=$?
  if ((_tr_sign_rc != 0)); then
    pass "tag-release: a message-less 'git tag -f' really does abort under tag.gpgsign (the #506 hazard)"
  else
    # Not a failure of ours — git changed behaviour, so the check below is guarding a
    # hazard that may no longer exist. Say so rather than reporting a silent pass.
    fail "tag-release: message-less 'git tag -f' no longer aborts under gpgsign — re-check whether #506's fix is still needed (git said: ${_tr_sign_err:-<nothing>})"
  fi
  # BEHAVIOUR, not source spelling. Grepping tag-release.sh for a command form would match
  # a comment or dead code, and would reject equivalent correct spellings like
  # `--annotate --force`. The publish above already created v1 with the real script, so ask
  # git what that ref actually IS: an annotated tag is its own object (`cat-file -t` → tag)
  # and carries a message; a lightweight tag resolves straight to the commit.
  _tr_v1_type="$(_trg "$TR/work" cat-file -t "$(_trg "$TR/work" rev-parse -q --verify v1 2>/dev/null)" 2>/dev/null)"
  _tr_v1_msg="$(_trg "$TR/work" tag -l --format='%(contents)' v1 2>/dev/null)"
  if [[ "$_tr_v1_type" == tag && -n "${_tr_v1_msg//[[:space:]]/}" ]]; then
    pass "tag-release: the vN alias is an ANNOTATED tag with a message (publishable under gpgsign)"
  else
    fail "tag-release: the vN alias is '${_tr_v1_type:-missing}' with message '${_tr_v1_msg:-<empty>}' — a lightweight alias makes publish abort for a signing operator (#506)"
  fi
  # Re-publishing an already-published tag must refuse — release tags are immutable.
  # Runs here, while 1.1.0 is still origin/main's newest core.version change.
  _tr_out="$(_tr_run --publish)"; _tr_rc=$?
  if ((_tr_rc != 0)) && grep -q 'already exists on origin' <<<"$_tr_out"; then
    pass "tag-release: --publish refuses to re-tag a published release (immutable)"
  else
    fail "tag-release: --publish would clobber a published tag (rc=$_tr_rc)"
  fi

  # The alias may only move FORWARD. The lease covers changes after REMOTE_MAJOR is read,
  # but a publisher that finishes BEFORE that read is seen as our own expected value, and
  # the leased push would satisfy the lease while rolling vN backward. Reaching that state
  # naturally needs a real race, so drive it directly: stage an UNPUBLISHED release (so the
  # immutability guard does not fire first), point origin's alias at a commit that is NOT
  # an ancestor of it, and require the refusal.
  printf '1.3.0\n' >"$TR/work/core.version"
  printf '# Changelog\n\n## [Unreleased]\n\n## [v1.3.0] - 2026-05-05\n\n- three\n' >"$TR/work/CHANGELOG.md"
  _trg "$TR/work" add -A; _trg "$TR/work" commit -q -m "release v1.3.0"
  _trg "$TR/work" push -q origin HEAD:main 2>/dev/null
  _tr_rel13="$(_trg "$TR/work" rev-parse HEAD)"
  # a commit off that line, published to origin so a ref there can point at it
  _trg "$TR/work" checkout -q -b divergent "$_tr_rel13~1" 2>/dev/null
  printf 'divergent\n' >"$TR/work/side.txt"
  _trg "$TR/work" add side.txt; _trg "$TR/work" commit -q -m "a commit off the release line"
  _tr_div="$(_trg "$TR/work" rev-parse HEAD)"
  _trg "$TR/work" push -q origin HEAD:refs/heads/divergent 2>/dev/null
  git -C "$TR/origin" update-ref refs/tags/v1 "$_tr_div"
  _trg "$TR/work" checkout -q main 2>/dev/null
  _trg "$TR/work" fetch -q --tags --force origin
  printf '1.3.0\n' >"$TR/work/core.version"

  _tr_out="$(_tr_run --publish)"; _tr_rc=$?
  _tr_v1_now="$(git -C "$TR/origin" rev-parse -q --verify 'v1^{commit}' 2>/dev/null)"
  if ((_tr_rc != 0)) && grep -q 'not an ancestor' <<<"$_tr_out" &&
    [[ "$_tr_v1_now" == "$_tr_div" ]] && [[ -z "$(_trg "$TR/work" tag -l 'v1.3.0')" ]]; then
    pass "tag-release: --publish refuses to move vN off its line (ancestry, not just the lease)"
  else
    fail "tag-release: alias moved off its line (rc=$_tr_rc, v1=$_tr_v1_now want=$_tr_div)"
  fi
  # restore a sane alias for the cases below
  git -C "$TR/origin" update-ref refs/tags/v1 "$_tr_rel13"
  _trg "$TR/work" fetch -q --tags --force origin

  # Publishing an OLDER release must be refused and must not move the alias. The property
  # matters more than which guard enforces it: resolution only accepts origin/main's
  # NEWEST core.version change, so an older version never resolves — and vN, which every
  # reusable-workflow caller pins to, cannot be pointed at an older Core.
  printf '1.0.0\n' >"$TR/work/core.version"
  _tr_v1_before="$(git -C "$TR/origin" rev-parse -q --verify 'v1^{commit}' 2>/dev/null)"
  _tr_out="$(_tr_run --publish)"; _tr_rc=$?
  _tr_v1_after="$(git -C "$TR/origin" rev-parse -q --verify 'v1^{commit}' 2>/dev/null)"
  if ((_tr_rc != 0)) && [[ -z "$(_trg "$TR/work" tag -l 'v1.0.0')" ]] &&
    [[ -n "$_tr_v1_before" && "$_tr_v1_before" == "$_tr_v1_after" ]]; then
    pass "tag-release: publishing an older release is refused and vN does not move backward"
  else
    fail "tag-release: older publish not refused (rc=$_tr_rc, v1 $_tr_v1_before -> $_tr_v1_after)"
  fi

  # A heading with an EMPTY body must be refused too. release.yml rejects an empty Release
  # body, and release.sh will promote an empty [Unreleased] without complaint — so without
  # this the immutable tag is pushed and the workflow fails afterwards, burning the version
  # for a reason knowable up front. Uses release.yml's own extraction, so the two agree.
  printf '2.5.0\n' >"$TR/work/core.version"
  printf '# Changelog\n\n## [Unreleased]\n\n## [v2.5.0] - 2026-04-04\n\n## [v1.1.0] - 2026-02-02\n\n- new\n' >"$TR/work/CHANGELOG.md"
  _trg "$TR/work" add -A; _trg "$TR/work" commit -q -m "release v2.5.0 (empty section)"
  _trg "$TR/work" push -q origin HEAD:main 2>/dev/null; _trg "$TR/work" fetch -q origin
  _tr_out="$(_tr_run --publish)"; _tr_rc=$?
  if ((_tr_rc != 0)) && grep -q 'is EMPTY' <<<"$_tr_out" &&
    [[ -z "$(_trg "$TR/work" tag -l 'v2.5.0')" ]]; then
    pass "tag-release: --publish refuses an empty [vX.Y.Z] section (no tag created)"
  else
    fail "tag-release: published a version release.yml would reject as an empty body (rc=$_tr_rc)"
  fi

  # A release commit with the right core.version but NO [vX.Y.Z] heading must be refused
  # BEFORE any tag exists: release.yml builds the Release body from that section, so
  # publishing first and finding out later leaves an immutable tag on a release that
  # cannot be published — the version is burned. (This guard was silently lost in an
  # earlier revision of this script, which is why it is pinned.) Both files move in ONE
  # commit, as release.sh + make tag produce. Runs LAST: it advances origin/main.
  printf '3.0.0\n' >"$TR/work/core.version"
  printf '# Changelog\n\n## [Unreleased]\n\n- deliberately no 3.0.0 heading\n' >"$TR/work/CHANGELOG.md"
  _trg "$TR/work" add -A; _trg "$TR/work" commit -q -m "release v3.0.0 (no heading)"
  _trg "$TR/work" push -q origin HEAD:main 2>/dev/null; _trg "$TR/work" fetch -q origin
  _tr_out="$(_tr_run --publish)"; _tr_rc=$?
  if ((_tr_rc != 0)) && grep -q 'has no' <<<"$_tr_out" &&
    [[ -z "$(_trg "$TR/work" tag -l 'v3.0.0')" ]]; then
    pass "tag-release: --publish refuses a release commit with no CHANGELOG heading (no tag created)"
  else
    fail "tag-release: published a version release.yml would fail on (rc=$_tr_rc)"
  fi
else
  skip "tag-release.sh two-phase ordering (git unavailable)"
fi

# ── G. module selection (lib/bootstrap-lib.sh blib_select / blib_want) ─────────
# Track B's --only/--skip gate. blib_select VALIDATES a comma-separated selector and
# records BLIB_ONLY/BLIB_SKIP; blib_want is the allowlist/skiplist predicate the link
# helpers consult; blib_selected_note is the summary suffix. Pure bash (no git/zsh),
# so it runs everywhere: assert the regex rejects empty/leading/trailing/doubled
# commas + non-letters + spaces + unknown groups, accepts + normalises a clean
# selector, and that blib_want honours only-wins-over-skip precedence.
hdr "module selection (blib_select / blib_want)"
# shellcheck source=lib/bootstrap-lib.sh
source "$HERE/lib/bootstrap-lib.sh"

# Drift guard: the cases below hardcode the six groups as an independent oracle (so a
# corrupted BLIB_MODULES can't make them pass vacuously). Pin the production list to that
# oracle HERE so adding/renaming a group trips one obvious assertion instead of silently
# skewing every _want_set expectation.
if [[ "$BLIB_MODULES" == "zsh nvim tmux git prompt tools" ]]; then pass "BLIB_MODULES matches the tested group set"; else fail "BLIB_MODULES drifted from the tested oracle (got '$BLIB_MODULES') — update Section G"; fi

# blib_select aborts (exit 1) on bad input — drive it in a subshell and read the rc.
_sel_rc() { ( blib_select "$1" "$2" ) >/dev/null 2>&1; }
for _bad in 'zsh,,nvim' 'zsh,' ',zsh' '' '*' 'a b' 'bogus' 'zsh nvim'; do
  if _sel_rc --only "$_bad"; then fail "blib_select accepted a bad selector: '$_bad'"; else pass "blib_select rejects '$_bad'"; fi
done

# an unknown flag (not --only/--skip) must fail fast, not silently no-op the selection.
if _sel_rc --bogus 'zsh'; then fail "blib_select accepted an unknown flag"; else pass "blib_select rejects an unknown flag"; fi

# a clean selector is accepted and normalised to space-separated (subshell: blib_select
# would mutate the suite's own BLIB_ONLY otherwise).
_only_norm="$( blib_select --only 'zsh,nvim'; printf '%s' "$BLIB_ONLY" )"
if [[ "$_only_norm" == "zsh nvim" ]]; then pass "blib_select accepts zsh,nvim → 'zsh nvim'"; else fail "blib_select did not normalise zsh,nvim (got '$_only_norm')"; fi

# blib_want over the six groups under each mode. Dynamic scope: the `local` BLIB_ONLY/
# BLIB_SKIP here is exactly what blib_want reads.
_want_set() {
  local BLIB_ONLY="$1" BLIB_SKIP="$2" g w=""
  for g in zsh nvim tmux git prompt tools; do
    if blib_want "$g"; then w+="$g "; fi
  done
  printf '%s' "${w% }"
}
if [[ "$(_want_set '' '')" == "zsh nvim tmux git prompt tools" ]]; then pass "blib_want: default wires every group"; else fail "blib_want: default did not wire all groups"; fi
if [[ "$(_want_set 'zsh nvim' '')" == "zsh nvim" ]]; then pass "blib_want: --only is an allowlist"; else fail "blib_want: --only allowlist wrong"; fi
if [[ "$(_want_set '' 'tmux')" == "zsh nvim git prompt tools" ]]; then pass "blib_want: --skip drops the named group"; else fail "blib_want: --skip wrong"; fi
if [[ "$(_want_set 'zsh' 'zsh')" == "zsh" ]]; then pass "blib_want: --only wins over --skip"; else fail "blib_want: precedence wrong (only should win)"; fi

# blib_selected_note — empty when unfiltered, reflects the active selection otherwise.
if [[ -z "$( blib_selected_note )" ]]; then pass "blib_selected_note: empty when nothing is filtered"; else fail "blib_selected_note: not empty by default"; fi
if [[ "$( blib_select --only zsh,nvim; blib_selected_note )" == " (only: zsh nvim)" ]]; then pass "blib_selected_note: shows the --only suffix"; else fail "blib_selected_note: --only suffix wrong"; fi
if [[ "$( blib_select --skip tmux; blib_selected_note )" == " (skipped: tmux)" ]]; then pass "blib_selected_note: shows the --skip suffix"; else fail "blib_selected_note: --skip suffix wrong"; fi
# precedence: when both are set --only wins in blib_want, so the note must report ONLY the
# only-mode (showing a skipped suffix that's actually ignored would be misleading).
if [[ "$( blib_select --only zsh; blib_select --skip nvim; blib_selected_note )" == " (only: zsh)" ]]; then pass "blib_selected_note: --only wins, --skip not shown"; else fail "blib_selected_note: should report only-mode when both set"; fi

# ── H. v4 layout migration (lib/bootstrap-lib.sh blib_migrate_v4) ─────────────
# The destructive pre-v4 → v4 migration: relocate history to $XDG_STATE_HOME, rename a
# host local.zsh → 99-local.zsh, and drop the stale unnumbered Core symlinks + compdump.
# Hermetic (temp dirs, no network). Covers relocation, cleanup, second-run idempotence,
# and dry-run (must change NOTHING) — so a re-bootstrap cannot silently lose host state.
hdr "v4 layout migration (blib_migrate_v4)"
# fixture: a realistic pre-v4 ~/.config/zsh under a throwaway root. Prints the root.
_mkv4_fixture() {
  local root zdir
  root="$(mktemp -d "$SANDBOX/v4mig.XXXXXX")"
  zdir="$root/.config/zsh"
  mkdir -p "$zdir"
  printf 'old history\n' >"$zdir/.zsh_history"
  printf 'export FOO=bar\n' >"$zdir/local.zsh"
  ln -s /nonexistent/core/zsh/tools.zsh "$zdir/tools.zsh" # stale unnumbered Core symlink
  : >"$zdir/tools.zsh.zwc"
  : >"$zdir/.zcompdump"
  mkdir -p "$zdir/plugins/zsh-defer"                      # pre-v4 plugin checkout
  : >"$zdir/plugins/zsh-defer/zsh-defer.plugin.zsh"
  printf '%s' "$root"
}
# run migrate in a SUBSHELL so BLIB_DRY / XDG_* don't leak into the suite shell (a
# var-prefixed function call would persist in bash). XDG_DATA_HOME is derived from the
# state path's sibling so the plugins move stays inside the throwaway root (never the real
# HOME). Filesystem effects still persist.
_run_migrate() { ( export XDG_STATE_HOME="$2" XDG_DATA_HOME="${2%/state}/share"; BLIB_DRY="$1"; blib_migrate_v4 "$3" ) >/dev/null 2>&1; }

# 1) real run relocates + cleans up.
_v4root="$(_mkv4_fixture)"; _zd="$_v4root/.config/zsh"
_run_migrate 0 "$_v4root/.local/state" "$_v4root/.config"
if [[ -f "$_v4root/.local/state/zsh/history" ]] && grep -q 'old history' "$_v4root/.local/state/zsh/history" && [[ ! -e "$_zd/.zsh_history" ]]; then
  pass "migrate: history relocated to \$XDG_STATE_HOME"; else fail "migrate: history not relocated"; fi
if [[ -f "$_zd/99-local.zsh" ]] && grep -q 'FOO=bar' "$_zd/99-local.zsh" && [[ ! -e "$_zd/local.zsh" ]]; then
  pass "migrate: local.zsh → 99-local.zsh (contents preserved)"; else fail "migrate: local.zsh not renamed"; fi
if [[ ! -e "$_zd/tools.zsh" && ! -e "$_zd/tools.zsh.zwc" ]]; then
  pass "migrate: stale unnumbered symlink + .zwc removed"; else fail "migrate: stale symlink/.zwc lingered"; fi
if [[ ! -e "$_zd/.zcompdump" ]]; then pass "migrate: stale pre-v4 compdump removed"; else fail "migrate: compdump lingered"; fi
if [[ -f "$_v4root/.local/share/zsh/plugins/zsh-defer/zsh-defer.plugin.zsh" && ! -e "$_zd/plugins" ]]; then
  pass "migrate: plugins dir relocated to \$XDG_DATA_HOME"; else fail "migrate: plugins not relocated"; fi

# 2) idempotence: a second run changes nothing and returns 0.
_run_migrate 0 "$_v4root/.local/state" "$_v4root/.config"; _mig_rc=$?
if [[ $_mig_rc -eq 0 && -f "$_zd/99-local.zsh" && ! -e "$_zd/.zsh_history" ]]; then
  pass "migrate: second run is an idempotent no-op"; else fail "migrate: not idempotent (rc=$_mig_rc)"; fi

# 3) dry-run (BLIB_DRY=1) mutates NOTHING — fresh fixture, every pre-v4 file untouched.
_v4dry="$(_mkv4_fixture)"; _dzd="$_v4dry/.config/zsh"
_run_migrate 1 "$_v4dry/.local/state" "$_v4dry/.config"
if [[ -f "$_dzd/.zsh_history" && -e "$_dzd/local.zsh" && ! -e "$_dzd/99-local.zsh" && -L "$_dzd/tools.zsh" && -d "$_dzd/plugins" && ! -e "$_v4dry/.local/state/zsh/history" && ! -e "$_v4dry/.local/share/zsh/plugins" ]]; then
  pass "migrate: dry-run (BLIB_DRY=1) changes nothing"; else fail "migrate: dry-run mutated the fixture"; fi

# 4) partial-migration CONFLICT: when the v4 destinations already exist, migrate must WARN
# and leave the pre-v4 files in place — never clobber the new file, never silently drop the
# old one (a re-bootstrap must not lose host state). rc stays 0 (a warning is not a failure).
_v4cf="$(mktemp -d "$SANDBOX/v4cf.XXXXXX")"
_cfzd="$_v4cf/.config/zsh"
mkdir -p "$_cfzd" "$_v4cf/.local/state/zsh"
printf 'old\n' >"$_cfzd/.zsh_history"
printf 'new\n' >"$_v4cf/.local/state/zsh/history"
printf 'old\n' >"$_cfzd/local.zsh"
printf 'new\n' >"$_cfzd/99-local.zsh"
mkdir -p "$_cfzd/plugins/old-plugin" "$_v4cf/.local/share/zsh/plugins/new-plugin"
_run_migrate 0 "$_v4cf/.local/state" "$_v4cf/.config"
_cf_rc=$?
if [[ $_cf_rc -eq 0 && -f "$_cfzd/.zsh_history" && "$(cat "$_v4cf/.local/state/zsh/history")" == new && -e "$_cfzd/local.zsh" && "$(cat "$_cfzd/99-local.zsh")" == new && -d "$_cfzd/plugins/old-plugin" && -d "$_v4cf/.local/share/zsh/plugins/new-plugin" ]]; then
  pass "migrate: conflicting destinations preserved (no clobber, no silent drop)"; else fail "migrate: conflict handling wrong (rc=$_cf_rc)"; fi

# ── I. managed .zshrc entry (lib/bootstrap-lib.sh blib_write_zshrc_loader) ────
# The written ~/.zshrc EXPORTS ZDOTDIR, so the entry file must ALSO exist at
# $ZDOTDIR/.zshrc — otherwise every zsh started from inside the first one inherits the
# export, finds no startup file there, and runs zsh-newuser-install with no Core loaded.
# `exec zsh` is the documented first step after a bootstrap, so this is the fresh-box
# path, not an edge case. Pure bash (no zsh needed) so it runs everywhere, like G and H.
hdr "managed .zshrc entry (blib_write_zshrc_loader)"

# Drive the writer against a throwaway HOME in a SUBSHELL so HOME/XDG_*/BLIB_* never leak
# into the suite shell. BLIB_ONLY/BLIB_SKIP are reset because Section G leaves them set,
# and blib_want gates this function on the zsh group.
#
# ZDOTDIR MUST be unset: the managed shell EXPORTS it, so running this suite from a
# configured machine would otherwise make the writer resolve $ZDOTDIR to the developer's
# REAL ~/.config/zsh and replace their .zshrc with a link into a sandbox that is deleted
# on exit. Unsetting it is what keeps the fixture hermetic — and honest, since the fresh
# box this models has no ZDOTDIR in the environment either.
#
# SC2030/SC2031: the subshell-local HOME/XDG_CONFIG_HOME is the POINT — the writer targets
# $HOME, and leaking a throwaway HOME into the suite shell would send later sections at the
# real one. Confining it to the subshell is the isolation, not a lost assignment.
# shellcheck disable=SC2030,SC2031
_run_zrc() { ( unset ZDOTDIR; export HOME="$1" XDG_CONFIG_HOME="$1/.config"; BLIB_DRY="${2:-0}"; BLIB_ONLY=""; BLIB_SKIP=""; blib_write_zshrc_loader ) >/dev/null 2>&1; }
# Same, but capturing stdout so the dry-run PLAN can be asserted.
# shellcheck disable=SC2030,SC2031
_run_zrc_out() { ( unset ZDOTDIR; export HOME="$1" XDG_CONFIG_HOME="$1/.config"; BLIB_DRY="${2:-0}"; BLIB_ONLY=""; BLIB_SKIP=""; blib_write_zshrc_loader ) 2>&1; }

# 1) fresh box: both entry points exist, and the ZDOTDIR one resolves to ~/.zshrc.
_zr="$(mktemp -d "$SANDBOX/zrc.XXXXXX")"
_run_zrc "$_zr"
if [[ -f "$_zr/.zshrc" ]] && grep -q 'dotfiles-managed v4' "$_zr/.zshrc"; then
  pass "zshrc: managed ~/.zshrc written"; else fail "zshrc: managed ~/.zshrc not written"; fi
if [[ -L "$_zr/.config/zsh/.zshrc" && "$(readlink "$_zr/.config/zsh/.zshrc")" == "$_zr/.zshrc" ]]; then
  pass "zshrc: \$ZDOTDIR/.zshrc seeded → ~/.zshrc"; else fail "zshrc: \$ZDOTDIR/.zshrc missing — a re-exec'd zsh would hit zsh-newuser-install"; fi

# 2) the file zsh actually looks for is present, so the newuser wizard cannot trigger.
#    (zsh runs it only when NONE of these exist in $ZDOTDIR.)
_zr_found=0
for _f in .zshenv .zprofile .zshrc .zlogin; do [[ -e "$_zr/.config/zsh/$_f" ]] && _zr_found=1; done
if ((_zr_found)); then pass "zshrc: \$ZDOTDIR has a startup file (no newuser wizard)"; else fail "zshrc: \$ZDOTDIR has none of .zshenv/.zprofile/.zshrc/.zlogin"; fi

# 3) REGRESSION: a box bootstrapped BEFORE the seeding existed already has a managed
#    ~/.zshrc, so the writer takes its idempotent early return. It must still reconcile
#    the missing $ZDOTDIR entry rather than skipping straight past it.
_zold="$(mktemp -d "$SANDBOX/zold.XXXXXX")"
mkdir -p "$_zold/.config/zsh"
printf '# dotfiles-managed v4 — pre-existing\n' >"$_zold/.zshrc"
_run_zrc "$_zold"
if [[ -L "$_zold/.config/zsh/.zshrc" ]]; then
  pass "zshrc: pre-existing v4 rc still gets \$ZDOTDIR seeded"; else fail "zshrc: early return skipped \$ZDOTDIR seeding on an already-managed box"; fi
if grep -q 'pre-existing' "$_zold/.zshrc"; then
  pass "zshrc: pre-existing v4 rc left untouched"; else fail "zshrc: clobbered an already-managed ~/.zshrc"; fi

# 4) idempotence: a second run changes nothing and leaves the link correct.
_run_zrc "$_zr"
if [[ -L "$_zr/.config/zsh/.zshrc" && "$(readlink "$_zr/.config/zsh/.zshrc")" == "$_zr/.zshrc" ]] && ! compgen -G "$_zr/.config/zsh/.zshrc.pre-dotfiles.*" >/dev/null; then
  pass "zshrc: second run is an idempotent no-op (no backup churn)"; else fail "zshrc: not idempotent"; fi

# 5) dry-run mutates NOTHING…
_zdry="$(mktemp -d "$SANDBOX/zdry.XXXXXX")"
_zdry_out="$(_run_zrc_out "$_zdry" 1)"
if [[ ! -e "$_zdry/.zshrc" && ! -e "$_zdry/.config/zsh/.zshrc" ]]; then
  pass "zshrc: BLIB_DRY=1 writes nothing"; else fail "zshrc: dry run mutated the tree"; fi
# …and PREVIEWS the whole plan. BLIB_DRY's contract is the full set of actions, so the
# seeded $ZDOTDIR entry — a second file the real run creates — has to appear too, or a
# --dry-run reader is told less than will happen.
if [[ "$_zdry_out" == *".zshrc"* && "$_zdry_out" == *"$_zdry/.config/zsh"* ]]; then
  pass "zshrc: BLIB_DRY=1 previews the \$ZDOTDIR seeding too"; else fail "zshrc: dry-run plan omits the \$ZDOTDIR seeding (got: $_zdry_out)"; fi

# 6) INVERTED LAYOUT: ~/.zshrc is itself a symlink TO $ZDOTDIR/.zshrc. The two path
#    strings differ but resolve to one file — linking would move the real file aside and
#    leave the symlinks pointing at each other (ELOOP, every shell broken). Must no-op.
_zinv="$(mktemp -d "$SANDBOX/zinv.XXXXXX")"
mkdir -p "$_zinv/.config/zsh"
printf '# dotfiles-managed v4 — real file lives in ZDOTDIR\n' >"$_zinv/.config/zsh/.zshrc"
ln -s "$_zinv/.config/zsh/.zshrc" "$_zinv/.zshrc"
_run_zrc "$_zinv"
if [[ -f "$_zinv/.config/zsh/.zshrc" ]] && grep -q 'real file lives in ZDOTDIR' "$_zinv/.config/zsh/.zshrc" \
   && [[ "$(readlink "$_zinv/.zshrc")" == "$_zinv/.config/zsh/.zshrc" ]] \
   && ! compgen -G "$_zinv/.config/zsh/.zshrc.pre-dotfiles.*" >/dev/null; then
  pass "zshrc: inverted layout (~/.zshrc → \$ZDOTDIR/.zshrc) left intact — no symlink cycle"; else fail "zshrc: inverted layout clobbered or cycled"; fi
# and prove it: a real zsh must still start from it rather than dying on ELOOP.
if have zsh && zsh -f -c "ZDOTDIR='$_zinv/.config/zsh'; source \"\$ZDOTDIR/.zshrc\"" 2>/dev/null; then
  pass "zshrc: inverted layout still sources (no ELOOP)"; else
  if have zsh; then fail "zshrc: inverted layout no longer sources"; else skip "zshrc: ELOOP check (zsh absent)"; fi
fi

# 7) ZDOTDIR already pointing at $HOME — ~/.zshrc IS the entry, so nothing to seed and
#    certainly no self-referential link.
_zh="$(mktemp -d "$SANDBOX/zh.XXXXXX")"
# shellcheck disable=SC2030,SC2031  # subshell-local by design — see _run_zrc above
( export HOME="$_zh" XDG_CONFIG_HOME="$_zh/.config" ZDOTDIR="$_zh"; BLIB_DRY=0; BLIB_ONLY=""; BLIB_SKIP=""; blib_write_zshrc_loader ) >/dev/null 2>&1
if [[ -f "$_zh/.zshrc" && ! -L "$_zh/.zshrc" ]]; then
  pass "zshrc: ZDOTDIR=\$HOME leaves ~/.zshrc a real file (no self-link)"; else fail "zshrc: ZDOTDIR=\$HOME produced a self-referential link"; fi

# ── J. shipped example systemd unit (examples/atuin-daemon.service) ───────────
# This file is classified repo-meta by ci-classify (nothing links it, so it cannot break a
# shell) and was consequently never validated at all. It still ships onto real machines by
# copy-paste, and its failure mode is quiet: with the daemon enabled and unreachable, atuin
# exits 0 and DISCARDS the entry, so a unit whose ExecStart the binary rejects becomes a
# 3s restart loop while shells silently record nothing. Cheap assertions, pure bash.
hdr "example systemd unit (examples/atuin-daemon.service)"
_UNIT="$HERE/examples/atuin-daemon.service"
if [[ ! -f "$_UNIT" ]]; then
  skip "atuin unit (examples/atuin-daemon.service absent)"
else
  _ux="$(grep -E '^ExecStart=' "$_UNIT" || true)"
  # RUN the ExecStart payload against stub atuins rather than pattern-matching it. String
  # assertions are too weak here: "contains daemon start" is satisfied by the PROBE alone,
  # so a unit that probes correctly and then execs the bare form in BOTH branches would
  # pass while being exactly the bug this fixes. Executing it pins the actual choice.
  _uxcmd="$(sed -n "s|^ExecStart=/bin/sh -c '\(.*\)'\$|\1|p" "$_UNIT")"
  if [[ -z "$_uxcmd" ]]; then
    fail "atuin unit: could not extract the sh -c payload from ExecStart (format changed?)"
  else
    _ustub="$(mktemp -d "$SANDBOX/unitstub.XXXXXX")"
    mkdir -p "$_ustub/new" "$_ustub/old"
    # NEW atuin: `daemon start` exists, so the probe succeeds and start must be chosen.
    printf '%s\n' '#!/bin/sh' \
      '[ "$1" = daemon ] && [ "$2" = start ] && [ "$3" = --help ] && exit 0' \
      '[ "$1" = daemon ] && [ "$2" = start ] && { echo START >"$UNIT_MARK"; exit 0; }' \
      '[ "$1" = daemon ] && [ -z "$2" ] && { echo BARE >"$UNIT_MARK"; exit 0; }' \
      'exit 2' >"$_ustub/new/atuin"
    # OLD atuin: no `start` subcommand — the probe must fail and the bare form be chosen.
    printf '%s\n' '#!/bin/sh' \
      '[ "$1" = daemon ] && [ "$2" = start ] && exit 2' \
      '[ "$1" = daemon ] && { echo BARE >"$UNIT_MARK"; exit 0; }' \
      'exit 2' >"$_ustub/old/atuin"
    chmod +x "$_ustub/new/atuin" "$_ustub/old/atuin"

    UNIT_MARK="$_ustub/mark.new" PATH="$_ustub/new:$PATH" sh -c "$_uxcmd" >/dev/null 2>&1
    if [[ "$(cat "$_ustub/mark.new" 2>/dev/null)" == START ]]; then
      pass "atuin unit: on an atuin WITH 'daemon start', ExecStart runs the non-deprecated form"; else fail "atuin unit: modern atuin did not get 'daemon start' (got: $(cat "$_ustub/mark.new" 2>/dev/null || echo nothing))"; fi

    UNIT_MARK="$_ustub/mark.old" PATH="$_ustub/old:$PATH" sh -c "$_uxcmd" >/dev/null 2>&1
    if [[ "$(cat "$_ustub/mark.old" 2>/dev/null)" == BARE ]]; then
      pass "atuin unit: on an atuin WITHOUT it, ExecStart falls back to the bare form"; else fail "atuin unit: old atuin got no working fallback (got: $(cat "$_ustub/mark.old" 2>/dev/null || echo nothing))"; fi
  fi
  # `exec A || exec B` LOOKS like a fallback but is not: once exec succeeds the process is
  # replaced, so atuin exiting non-zero can never reach the `||`. Pin that it is not used.
  if [[ "$_ux" != *"|| exec"* ]]; then
    pass "atuin unit: no 'exec … || exec …' pseudo-fallback"; else fail "atuin unit: 'exec … || exec …' cannot fall back — exec replaces the process"; fi
  # Syntax, when the tool is around (Linux CI; absent on macOS runners).
  if have systemd-analyze; then
    if systemd-analyze verify "$_UNIT" >/dev/null 2>&1; then
      pass "atuin unit: systemd-analyze verify clean"; else fail "atuin unit: systemd-analyze verify reported problems"; fi
  else
    skip "atuin unit: systemd-analyze verify (not installed)"
  fi
fi

# ── J2. the atuin daemon bench harness (scripts/bench-atuin-daemon.sh) ────────
# The bench itself needs a real atuin, a real zsh and a background daemon, so `make audit`
# can never run it — which is exactly why its FAIL-CLOSED surface is worth pinning here.
# Everything below is pure bash + python3: no atuin, no zsh, no systemd bus.
#
# What is deliberately NOT covered: the row-count rule end to end. Driving it would need a
# stub atuin AND a stub zsh emulating zsh/datetime's $EPOCHREALTIME — a large, brittle fake
# of the very thing under measurement. (run_writers' short-arm refusal has the same status:
# validated by running the bench on a box that has atuin, not by this suite.) Test 6 pins the
# piece that IS cheaply hermetic — the SQL the whole rule rests on.
hdr "atuin daemon bench harness (scripts/bench-atuin-daemon.sh)"
_BENCH="$HERE/scripts/bench-atuin-daemon.sh"
if [[ ! -x "$_BENCH" ]]; then
  skip "atuin bench harness (scripts/bench-atuin-daemon.sh absent or not executable)"
else
  _bout=""
  _brc=0
  _b_run() { # _b_run [env=val ...] -- [args ...]
    local envs=()
    while (($#)) && [[ "$1" != -- ]]; do
      envs+=("$1")
      shift
    done
    shift || true
    # ${envs[@]+"${envs[@]}"}, not "${envs[@]}" — macOS ships bash 3.2, where expanding an
    # EMPTY array under `set -u` is an "unbound variable" error rather than zero words. The
    # calls that pass no env vars are exactly the ones that tripped it, so the bug only ever
    # showed on macOS. scripts/lib/common.sh pins the same 3.2 constraint for the same reason.
    _bout="$(env -u CORE_JSON CORE_COLOR=never ${envs[@]+"${envs[@]}"} "$_BENCH" "$@" 2>&1)"
    _brc=$?
  }

  # 1. --help documents the new surface. This is what stops a flag landing undocumented, and
  #    — more to the point — stops the SCOPE CAVEAT being dropped from the USER-VISIBLE surface
  #    while surviving only in a source comment. It pinned the UNVALIDATED marker until the
  #    seven runs that retired it; "not real hardware" is the caveat that outlives those runs,
  #    since a synthetic container/WSL2 figure is still not a real multi-pane box.
  _b_run -- --help
  if ((_brc == 0)) && [[ "$_bout" == *"--systemd"* && "$_bout" == *"CORE_ATBENCH_BASE"* &&
    "$_bout" == *"not real hardware"* ]]; then
    pass "atuin bench: --help documents --systemd, CORE_ATBENCH_BASE and the scope caveat"
  else
    fail "atuin bench: --help is missing one of --systemd / CORE_ATBENCH_BASE / 'not real hardware' (rc=$_brc)"
  fi

  # 2. The fail-closed arg contract still holds now that a flag exists which does not exit.
  _b_run -- --definitely-not-a-flag
  if ((_brc == 2)) && [[ "$_bout" == *"unexpected argument"* ]]; then
    pass "atuin bench: an unknown argument still exits 2"
  else
    fail "atuin bench: unknown argument should exit 2 (got rc=$_brc)"
  fi

  # 3. --systemd fails CLOSED and does not degrade. Stub systemd-run/systemctl that behave
  #    like a box with no bus, prepended to PATH so this is identical on a laptop with a real
  #    user manager and in CI without one. The load-bearing assertion is the last one: a skip
  #    that still printed a results table would be the silent degradation the flag exists to
  #    prevent, and "rc==0" alone would not catch it.
  _sdstub="$(mktemp -d "$SANDBOX/sdstub.XXXXXX")"
  for _t in systemd-run systemctl; do
    printf '%s\n' '#!/bin/sh' \
      'echo "Failed to connect to bus: No medium found" >&2' 'exit 1' >"$_sdstub/$_t"
    chmod +x "$_sdstub/$_t"
  done
  _bout="$(env CORE_COLOR=never PATH="$_sdstub:$PATH" "$_BENCH" --systemd 2>&1)"
  _brc=$?
  if ((_brc == 0)) && [[ "$_bout" == *"systemd"* && "$_bout" != *"results (ms per command"* &&
    "$_bout" != *"daemon off"* ]]; then
    pass "atuin bench: --systemd with no user bus SKIPs (rc 0) and reports no numbers"
  else
    fail "atuin bench: --systemd must skip without degrading to the no-systemd path (rc=$_brc)"
  fi

  # 4. CORE_ATBENCH_BASE validation — a caller error, so exit 2, never a silent skip.
  #    The non-writable leg is meaningless as root (-w is always true), hence the guard.
  _b_run "CORE_ATBENCH_BASE=relative/path" --
  _rc_rel=$_brc
  _b_run "CORE_ATBENCH_BASE=$SANDBOX/definitely-absent" --
  _rc_abs=$_brc
  if ((_rc_rel == 2)) && ((_rc_abs == 2)); then
    pass "atuin bench: CORE_ATBENCH_BASE rejects a relative and a nonexistent path (exit 2)"
  else
    fail "atuin bench: CORE_ATBENCH_BASE validation should exit 2 (relative=$_rc_rel absent=$_rc_abs)"
  fi

  # 5. Knob validation. WRITERS=0 is the one that matters: it makes every arm vacuously
  #    complete AND vacuously row-correct (0 samples, 0 rows) — a green run that measured
  #    nothing, which is precisely the outcome the row rule exists to make impossible.
  #    `08` is the third leg and the subtle one: it passes a `^[0-9]+$` digit class, and bash
  #    then reads it as OCTAL, so an arithmetic range check dies with "value too great for
  #    base" rather than producing the promised exit 2 — and the bad value goes on to break
  #    the writer loops. Assert the exit code AND that no arithmetic error leaked to stderr.
  _b_run "CORE_ATBENCH_WRITERS=abc" --
  _rc_nan=$_brc
  _b_run "CORE_ATBENCH_WRITERS=0" --
  _rc_zero=$_brc
  _b_run "CORE_ATBENCH_WRITERS=08" --
  _rc_oct=$_brc
  _oct_out="$_bout"
  if ((_rc_nan == 2)) && ((_rc_zero == 2)) && ((_rc_oct == 2)) &&
    [[ "$_oct_out" != *"value too great for base"* ]]; then
    pass "atuin bench: non-numeric, zero and octal-looking (08) CORE_ATBENCH_WRITERS exit 2"
  else
    fail "atuin bench: knob validation should exit 2 (abc=$_rc_nan zero=$_rc_zero 08=$_rc_oct)"
  fi

  # 6. EXECUTE the row-count SQL rather than pattern-match it — Section J's philosophy applied
  #    to the standing rule. Extract ROWCOUNT_PY (failing loudly if the extraction comes back
  #    empty, exactly as Section J does for ExecStart) and run it against a synthetic history
  #    table. This pins both predicates the rule rests on: the total, and the `duration >= 0`
  #    FINISHED count that catches a silently-discarded `history end`.
  #    The SQL now lives in scripts/lib/atuin-db.sh, shared with scripts/verify-atuin-guard.sh
  #    — so this one assertion covers BOTH atuin gates, which is the point of the extraction.
  _rcpy="$(sed -n "/^ROWCOUNT_PY='/,/^'$/p" "$HERE/scripts/lib/atuin-db.sh" | sed -e "1s/^ROWCOUNT_PY='//" -e '$d')"
  if [[ -z "$_rcpy" ]]; then
    fail "atuin bench: could not extract ROWCOUNT_PY from the script (format changed?)"
  elif ! have python3; then
    skip "atuin bench: row-count SQL (python3 not installed)"
  else
    _rcdb="$SANDBOX/rowcount.db"
    rm -f "$_rcdb"
    python3 -c 'import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("create table history (duration integer)")
con.executemany("insert into history values (?)", [(-1,), (-1,), (5,), (7,), (0,)])
con.commit(); con.close()' "$_rcdb"
    _tot="$(python3 -c "$_rcpy" "$_rcdb" '1=1')"
    _fin="$(python3 -c "$_rcpy" "$_rcdb" 'duration >= 0')"
    if [[ "$_tot" == 5 && "$_fin" == 3 ]]; then
      pass "atuin bench: the row-count SQL counts all rows (5) and finished rows (3)"
    else
      fail "atuin bench: row-count SQL wrong (total=$_tot want 5; finished=$_fin want 3)"
    fi
    # And it must FAIL CLOSED — a -1 can only ever break an equality check, never satisfy one.
    if [[ "$(python3 -c "$_rcpy" "$SANDBOX/no-such.db" '1=1')" == -1 ]]; then
      pass "atuin bench: the row-count SQL returns -1 on an unreadable DB (fails closed)"
    else
      fail "atuin bench: row-count SQL must return -1 when it cannot read the DB"
    fi
  fi

  # 7. The two-metric split, EXECUTED rather than grepped. The writer emits `start_ms
  #    pair_ms` per line; the stats block must read one column per table. This needs a real
  #    test because the failure is invisible: the previous parser split the whole file on
  #    whitespace, so two-column input would flatten into a single distribution of double
  #    the length — a table that looks entirely normal and is entirely wrong. Feed it
  #    samples whose two columns differ and pin that each table reports its own.
  # Anchored on the stats INVOCATION, not on `<<'PY'`: the seeder above it uses the same
  # heredoc tag, so the generic pattern silently extracted the wrong block. Avoids `$` in
  # the pattern so BSD and GNU sed agree on it.
  _stats="$(sed -n '/^python3 - .*OFF_OK/,/^PY$/p' "$_BENCH" | sed -e '1d' -e '$d')"
  if [[ -z "$_stats" ]]; then
    fail "atuin bench: could not extract the stats block from the script (format changed?)"
  elif ! have python3; then
    skip "atuin bench: two-metric split (python3 not installed)"
  else
    _sdir="$(mktemp -d "$SANDBOX/stats.XXXXXX")"
    mkdir -p "$_sdir/off" "$_sdir/on"
    # start: off 10 ms, on 5 ms  (p50 ratio 2.00x).  pair: off 30 ms, on 25 ms  (1.20x).
    # The ratios are the assertion, and 1.20x is the load-bearing one: a flattened parse
    # yields the SAME distribution for both tables, so it can still produce 2.00x — but it
    # can never produce a second, different ratio.
    for _i in 1 2 3 4 5 6 7 8 9 10; do
      printf '10.000000 30.000000\n' >>"$_sdir/off/1.txt"
      printf '5.000000 25.000000\n' >>"$_sdir/on/1.txt"
    done
    _sout="$(python3 -c "$_stats" "$_sdir" 1 1 'daemon on' 2>&1)"
    if [[ "$_sout" == *"PROMPT LATENCY"* && "$_sout" == *"TOTAL WRITE WORK"* &&
      "$_sout" == *"2.00x faster"* && "$_sout" == *"1.20x faster"* ]]; then
      pass "atuin bench: prompt-latency and total-write-work tables read separate columns"
    else
      fail "atuin bench: the two-metric split did not report both columns independently"
    fi

    # 8. A malformed sample line must REFUSE the arm, not coerce it. Same standing rule as
    #    the row count: a half-parsed latency table is indistinguishable from a real one.
    printf 'only-one-column\n' >"$_sdir/off/1.txt"
    _sout="$(python3 -c "$_stats" "$_sdir" 1 1 'daemon on' 2>&1)"
    if [[ "$_sout" == *"arm refused"* ]]; then
      pass "atuin bench: a malformed sample line refuses the arm"
    else
      fail "atuin bench: a malformed sample line must refuse the arm, not be coerced"
    fi
  fi
fi

# ── J3. the atuin-guard premise detector (scripts/verify-atuin-guard.sh) ──────
# The detector answers ONE question — does the upstream fact _core_atuin_daemon_guard is
# premised on still hold? — and the whole reason it exists in this shape is that the
# previous answer to that question could LIE. The copy-paste recipe it replaces seeded its
# DB through the unreachable-daemon path, so on a build that discards, the DB was never
# created, every row count fell back to 0, and it printed the premise-holds signature from
# an apparatus that had never written a row. Right by luck.
#
# So the assertions below are mostly about the THIRD verdict. `holds` and `moved` are the
# easy half; `unmeasurable` is the one that keeps a broken detector from reading as good
# news, and it is the one a well-meant future simplification would delete.
#
# Hermetic: a stub `atuin` supplies every shape, so this needs no atuin, no daemon and no
# network — the same stubbing idiom Section J uses on the example unit's ExecStart.
_VERIFY="$HERE/scripts/verify-atuin-guard.sh"
# SCOPE_ATUIN, not SCOPE_SHELL. This section and J4 below are 197s of a 286s suite — 68% of
# it, and the largest single cost on the CI critical path across all nine repos. What they
# exercise is the premise DETECTOR against stub binaries; the detector's real job, measuring
# live upstream atuin, runs weekly in .github/workflows/atuin-guard-verify.yml and never on a
# push. So the only changes that can move the result here are the detector itself (scripts/,
# which ci-classify.sh already treats as infra → full run), the guard it protects in
# zsh/00-tools.zsh, and atuin/. Every other shell change was paying 197s for a harness it
# cannot reach. Skipping is FAIL-CLOSED at the classifier, not here: an unrecognised or
# unparseable path forces the full scope, so an unclassified change still runs this.
if ! ((SCOPE_ATUIN)); then
  skip "atuin guard detector (out of scope)"
elif [[ ! -x "$_VERIFY" ]]; then
  skip "atuin guard detector (scripts/verify-atuin-guard.sh absent or not executable)"
elif ! have python3; then
  skip "atuin guard detector (python3 not installed)"
else
  hdr "atuin guard premise detector (scripts/verify-atuin-guard.sh, hermetic)"
  _vstub="$(mktemp -d "$SANDBOX/vstub.XXXXXX")"

  # _mkstub <name> <writes?> [version] — a fake atuin. `writes=yes` inserts a row on EVERY
  # invocation (an upstream that no longer discards); `writes=off-only` inserts one only
  # when the daemon is off (today's real 18.19.0 behaviour); `writes=no` never writes at
  # all (a broken apparatus — the case that used to read as "holds"); `writes=stops` writes
  # on the daemon-off path only until the DB exists and the opening control has run, then
  # stops for good (an apparatus that dies MID-run); `writes=replay` discards nothing — it
  # SPOOLS the daemon-on entries and flushes them on the next daemon-off write, the upstream
  # shape that would invert the guard's one-way degrade.
  #
  # _w is a COUNT, not a flag: `replay` has to land more than one row in a single call, and
  # every other mode simply leaves it at 1.
  _mkstub() {
    local name="$1" mode="$2" ver="${3:-18.19.0}"
    cat >"$_vstub/$name" <<STUB
#!/usr/bin/env bash
case "\$1" in --version) echo "atuin $ver"; exit 0 ;; esac
_w=0
_spool="\${XDG_DATA_HOME}/stub-spool"
case "$mode" in
  yes) _w=1 ;;
  off-only|badid|corrupt) [[ "\${ATUIN_DAEMON__ENABLED:-false}" == true ]] || _w=1 ;;
  stops)
    # Two daemon-off writes are allowed: the seed (which creates the DB) and the opening
    # control arm. After that this apparatus is dead — but it still READS fine, which is
    # exactly why the closing control arm has to exist.
    _n=\$(cat "\${XDG_DATA_HOME}/stub-writes" 2>/dev/null || echo 0)
    if [[ "\${ATUIN_DAEMON__ENABLED:-false}" != true ]] && ((_n < 2)); then
      _w=1
      mkdir -p "\${XDG_DATA_HOME}"; echo \$((_n + 1)) >"\${XDG_DATA_HOME}/stub-writes"
    fi
    ;;
  replay)
    if [[ "\${ATUIN_DAEMON__ENABLED:-false}" == true ]]; then
      mkdir -p "\${XDG_DATA_HOME}"; echo q >>"\$_spool"   # buffered, not discarded
    else
      _w=\$((1 + \$(wc -l <"\$_spool" 2>/dev/null || echo 0)))
      : >"\$_spool"
    fi
    ;;
esac
if (( _w )); then
  db="\${XDG_DATA_HOME}/atuin/history.db"; mkdir -p "\$(dirname "\$db")"
  python3 - "\$db" "\$_w" <<'PY'
import sqlite3,sys
c=sqlite3.connect(sys.argv[1])
c.execute("create table if not exists history (id text, duration integer)")
for _ in range(int(sys.argv[2])):
    c.execute("insert into history values ('x', -1)")
c.commit(); c.close()
PY
fi
# corrupt: after the daemon-on call, leave the DB unreadable — the shape that made an
# apparatus failure read as a MOVED verdict (a negative delta) before the readok sentinel.
# NOTE: no backticks anywhere in this heredoc body. The delimiter is unquoted (so \$mode and
# \$ver interpolate), which means a backtick here is COMMAND SUBSTITUTION at stub-generation
# time, not decoration.
if [ "$mode" = corrupt ] && [ "\${ATUIN_DAEMON__ENABLED:-false}" = true ]; then
  printf 'this is not a sqlite database' >"\${XDG_DATA_HOME}/atuin/history.db"
fi
# badid: exit 0, write nothing, and print something that is NOT a 32-hex history id —
# a deprecation notice on stdout is the realistic shape.
if [ "$mode" = badid ]; then
  echo "warning: atuin history start is deprecated"
else
  echo "0192deadbeefcafe0000000000000000"
fi
STUB
    chmod +x "$_vstub/$name"
  }

  _v_run() { # _v_run <stub> [extra args...] → sets _vout/_vrc
    local stub="$1"
    shift
    _vout="$(env -u CORE_JSON CORE_COLOR=never "$_VERIFY" --atuin "$_vstub/$stub" "$@" 2>&1)"
    _vrc=$?
  }
  _v_verdict() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["verdict"])' 2>/dev/null; }

  # ── apparatus-FREE assertions. These hold on any box, because none of them needs the
  #    stub to be able to write a row — so a platform where the apparatus cannot run still
  #    pins the script's contract surface.
  #
  # A. A bare box must not be able to produce a green "holds". This is the one place the
  #    repo's skip-and-exit-0 idiom is deliberately broken, so it is pinned.
  _vout="$(env -u CORE_JSON CORE_COLOR=never "$_VERIFY" --atuin /nonexistent/atuin --json 2>&1)"
  _vrc=$?
  if ((_vrc == 3)) && [[ "$(_v_verdict "$_vout")" == unmeasurable ]]; then
    pass "atuin verify: a missing atuin exits 3 (unmeasurable), NOT 0 — exit 0 asserts something about upstream"
  else
    fail "atuin verify: a missing atuin must exit 3, got rc$_vrc"
  fi

  # B. Usage errors stay distinct from verdicts: 2 is the caller's fault, 1 and 3 are
  #    findings. A workflow that conflated them would file an issue about a typo.
  CORE_COLOR=never "$_VERIFY" --definitely-not-a-flag >/dev/null 2>&1
  _vrc=$?
  CORE_COLOR=never "$_VERIFY" --atuin >/dev/null 2>&1
  _vrc2=$?
  if ((_vrc == 2)) && ((_vrc2 == 2)); then
    pass "atuin verify: an unknown flag and a flag missing its value both exit 2 (usage, not a finding)"
  else
    fail "atuin verify: usage errors must exit 2 (unknown=$_vrc missing-value=$_vrc2)"
  fi

  # C. --unmeasurable renders through the SAME one path as a real run, so the workflow
  #    never hand-rolls prose at the call site and the two cannot drift.
  _vout="$(CORE_COLOR=never "$_VERIFY" --unmeasurable "download failed" --json 2>&1)"
  _vrc=$?
  if ((_vrc == 3)) && [[ "$(_v_verdict "$_vout")" == unmeasurable ]] && [[ "$_vout" == *"download failed"* ]]; then
    pass "atuin verify: --unmeasurable emits a well-formed verdict without measuring (rc 3)"
  else
    fail "atuin verify: --unmeasurable must render a real unmeasurable verdict, got rc$_vrc"
  fi

  # D. The --json object carries every field a consumer reads (the workflow parses
  #    `verdict`; a human reads the rest). Asserted by SHAPE, not by grep, and on the
  #    apparatus-free path so it holds everywhere.
  if printf '%s' "$_vout" | python3 -c '
import json,sys
d = json.load(sys.stdin)
need = {"premise","verdict","reason","atuin_version","host","anchor","anchor_relation","control_delta","drain_delta","bounded","arms"}
assert need <= set(d), sorted(need - set(d))
assert isinstance(d["arms"], dict), type(d["arms"])
# `premise` defaults to discard and the workflow ASSERTS it per leg: the two legs differ by
# one flag, and a copy-paste that dropped it would file a silent-discard measurement under
# the autostart title. A default that silently changed would defeat that check.
assert d["premise"] == "discard", d["premise"]
' 2>/dev/null; then
    pass "atuin verify: --json carries premise/verdict/reason/versions/host/deltas/bounded/arms"
  else
    fail "atuin verify: --json shape is missing fields consumers depend on"
  fi

  # ── APPARATUS SELF-CHECK. Everything below drives a stub that must actually write a row
  #    into a real SQLite file and be measured through it. A box where that cannot work —
  #    a python3 built without the sqlite3 module, a coreutils that cannot bound a call,
  #    a busybox whose tools differ — would fail every assertion below for a reason that
  #    has nothing to do with the code under test. So prove the apparatus FIRST and SKIP
  #    if it cannot be built, which is the same contract check_dep applies to a missing
  #    binary. The skip carries the verdict AND the reason, because a skip that does not
  #    say why is how a platform-specific breakage stays invisible.
  _mkstub atuin-discards off-only
  _v_run atuin-discards --json
  _vapp="$(_v_verdict "$_vout")"
  if [[ "$_vapp" != holds ]]; then
    _vwhy="$(printf '%s' "$_vout" | python3 -c 'import json,sys; print(json.load(sys.stdin)["reason"][:160])' 2>/dev/null)"
    skip "atuin guard detector: measurement assertions (apparatus unusable here — verdict=${_vapp:-<unparseable>}: ${_vwhy:-no reason parsed})"
  else
    # 1. HOLDS — the control arm writes, both unreachable shapes discard. rc 0.
    _v_run atuin-discards --json
    if [[ "$(_v_verdict "$_vout")" == holds ]] && ((_vrc == 0)); then
      pass "atuin verify: an atuin that still discards on an unreachable socket → holds (rc 0)"
    else
      fail "atuin verify: expected holds/rc0, got $(_v_verdict "$_vout")/rc$_vrc"
    fi

    # 2. The control arm is REPORTED, not merely run. `holds` without a proven-working
    #    apparatus is exactly the old recipe's failure, so the number is in the output.
    if [[ "$_vout" == *'"control_delta":1'* ]]; then
      pass "atuin verify: holds is reported alongside a control arm that actually wrote"
    else
      fail "atuin verify: a holds verdict must carry control_delta 1 (got: $_vout)"
    fi

    # 3. MOVED — an atuin that writes on the unreachable path. rc 1, and the reason names
    #    WHICH property changed (a bare "it changed" is not actionable).
    _mkstub atuin-fixed yes 19.0.0
    _v_run atuin-fixed --json
    if [[ "$(_v_verdict "$_vout")" == moved ]] && ((_vrc == 1)) && [[ "$_vout" == *"no longer discards"* ]]; then
      pass "atuin verify: an atuin that writes on an unreachable socket → moved (rc 1), naming the change"
    else
      fail "atuin verify: expected moved/rc1 naming the change, got $(_v_verdict "$_vout")/rc$_vrc"
    fi

    # 4. A newer atuin than the anchor is REPORTED as such — the signal /tool-scout cannot
    #    compute for itself and the issue body leads with.
    if [[ "$_vout" == *'"anchor_relation":"newer"'* ]]; then
      pass "atuin verify: an atuin newer than the anchor reports anchor_relation=newer"
    else
      fail "atuin verify: anchor_relation must say 'newer' when the measured atuin outranks the anchor"
    fi

    # 5. THE LOAD-BEARING ONE. An apparatus that cannot write at all must be UNMEASURABLE,
    #    never holds. Both produce "the row count did not go up"; only one of them means the
    #    premise held. Deleting this assertion is how the fail-open bug comes back.
    _mkstub atuin-dead no
    _v_run atuin-dead --json
    if [[ "$(_v_verdict "$_vout")" == unmeasurable ]] && ((_vrc == 3)); then
      pass "atuin verify: an atuin that never writes is UNMEASURABLE (rc 3), never holds"
    else
      fail "atuin verify: a non-writing apparatus must be unmeasurable/rc3, got $(_v_verdict "$_vout")/rc$_vrc"
    fi

    # 6. The anchor is read from ONE machine-readable line, and a file that disagrees with
    #    itself (or has lost the line) is unmeasurable rather than defaulted. Driven from a
    #    sandbox repo whose zsh/00-tools.zsh is doctored.
    _vrepo="$(mktemp -d "$SANDBOX/vrepo.XXXXXX")"
    # lib/ux.sh too: scripts/lib/common.sh sources it as ../../lib/ux.sh, and without it the
    # script dies under `set -u` before it ever reads the anchor — which would make this
    # assertion pass for the wrong reason (a crash, not a refusal).
    mkdir -p "$_vrepo/scripts/lib" "$_vrepo/lib" "$_vrepo/zsh" "$_vrepo/atuin"
    cp "$_VERIFY" "$_vrepo/scripts/"
    cp "$HERE/scripts/lib/common.sh" "$HERE/scripts/lib/atuin-db.sh" "$_vrepo/scripts/lib/"
    cp "$HERE/lib/ux.sh" "$_vrepo/lib/"
    cp "$HERE/atuin/config.toml" "$_vrepo/atuin/"
    for _case in none dupe; do
      if [[ "$_case" == none ]]; then
        printf '# no anchor here\n' >"$_vrepo/zsh/00-tools.zsh"
      else
        printf '# CORE_ATUIN_GUARD_VERIFIED_AGAINST=18.19.0\n# CORE_ATUIN_GUARD_VERIFIED_AGAINST=19.0.0\n' \
          >"$_vrepo/zsh/00-tools.zsh"
      fi
      _vout="$(CORE_COLOR=never "$_vrepo/scripts/verify-atuin-guard.sh" --atuin "$_vstub/atuin-discards" --json 2>&1)"
      _vrc=$?
      if ((_vrc == 3)) && [[ "$_vout" == *"anchor"* ]]; then
        pass "atuin verify: a $_case anchor in zsh/00-tools.zsh is unmeasurable, not a default"
      else
        fail "atuin verify: a $_case anchor must be unmeasurable (rc3), got rc$_vrc"
      fi
    done

    # 7. The report is issue-ready: no title heading (file-routine-issue.sh supplies one),
    #    and its prose AGREES WITH THE MATRIX THAT RAN. The blind spots it must still name —
    #    musl, autostart, #3382 — are pinned as before, but the coverage half is checked for
    #    COHERENCE rather than for keywords, because keywords are what let the last bug
    #    through: the scope paragraph went on saying "`--hook` is not exercised" after the
    #    matrix was widened to four arms, and the assertion that should have caught it grepped
    #    for two nouns the false sentence also contained.
    #
    #    Both renderers run from ONE invocation — emit_report runs before emit_json — so the
    #    two can never be compared across different runs. The comparison targets the DERIVED
    #    coverage sentence SPECIFICALLY, and that precision is the whole assertion: the
    #    per-arm table already lists every arm, so a check that merely looks for arm names
    #    somewhere in the report is satisfied by the table alone and never reads the claim.
    _vrep="$SANDBOX/atverify-report.md"
    _vrepjson="$SANDBOX/atverify-report.json"
    CORE_COLOR=never "$_VERIFY" --atuin "$_vstub/atuin-discards" --report "$_vrep" --json \
      >"$_vrepjson" 2>/dev/null
    if [[ -s "$_vrep" ]] && [[ "$(head -c 1 "$_vrep")" != "#" ]] &&
      grep -qi 'musl' "$_vrep" && grep -qi 'autostart' "$_vrep" && grep -q '3382' "$_vrep" &&
      python3 - "$_vrep" "$_vrepjson" <<'PY' 2>/dev/null; then
import json, re, sys
rep = open(sys.argv[1]).read()
arms = set(json.load(open(sys.argv[2]))["arms"])

# The coverage claim, parsed and compared as a SET. emit_report renders "absent_hook" as
# "absent / hook", so the claim is mapped back rather than the arms mapped forward.
m = re.search(r"^\*\*Measured here:\*\* (.+)\.$", rep, re.M)
assert m, "the report states no coverage claim at all"
if arms:
    claimed = {a.strip().replace(" / ", "_") for a in m.group(1).split(",")}
    assert claimed == arms, sorted(claimed ^ arms)
else:
    assert m.group(1).startswith("nothing"), m.group(1)

# The scope section is BY CONSTRUCTION about what was not measured, so it may name neither an
# arm nor either hook mode — every arm is measured in both. That is the general form of the
# bug that shipped, where "`--hook` is not exercised" sat here while four hook arms ran; the
# previous exact-wording ban would have missed any reworded version of the same claim.
scope = rep.rsplit("\n---\n", 1)[-1]
named = [a for a in arms if a.replace("_", " / ") in scope]
assert not named, "the scope section names measured arms: %s" % named
assert "hook" not in scope.lower(), "the scope section disclaims hook coverage the matrix has"
PY
      pass "atuin verify: --report is issue-ready, names its musl/autostart/#3382 blind spots, and its prose matches the arms that ran"
    else
      fail "atuin verify: --report must omit a title heading, name the coverage it lacks, and not disclaim an arm it measured"
    fi

    # 8. FOUR arms, and the hook ones by name. atuin's own `init zsh` emits
    #    `atuin history start --hook -- "$1"`, so the plain form is a path no shell in the
    #    fleet actually runs; a detector that measured only it could report `holds` while an
    #    upstream change scoped to hook mode broke every prompt.
    _v_run atuin-discards --json
    if printf '%s' "$_vout" | python3 -c '
import json,sys
a = json.load(sys.stdin)["arms"]
want = {"absent_hook","absent_plain","stale_hook","stale_plain"}
assert want == set(a), sorted(set(a) ^ want)
for name, arm in a.items():
    assert {"rc","delta","stderr_empty","id_wellformed"} <= set(arm), name
' 2>/dev/null; then
      pass "atuin verify: all four arms are measured — absent/stale x hook/plain"
    else
      fail "atuin verify: --json must carry absent/stale x hook/plain arms (got: $_vout)"
    fi

    # 9. A malformed id is a FINDING, not a pass. "stdout was non-empty" is not the premise —
    #    the shell hands that id to `history end`, and 18.16.1's empty id is what crashed it.
    _mkstub atuin-badid badid
    _v_run atuin-badid --json
    if [[ "$(_v_verdict "$_vout")" == moved ]] && [[ "$_vout" == *"well-formed history id"* ]]; then
      pass "atuin verify: stdout that is not a 32-hex id is moved, not holds"
    else
      fail "atuin verify: a malformed history id must be a finding, got $(_v_verdict "$_vout")"
    fi

    # 10. THE OTHER HALF OF THE CENTRAL RULE. An unreadable DB must be `unmeasurable`, never
    #     `moved`. atuin_db_rows returns -1 on a failed read, and `after - before` then goes
    #     NEGATIVE — which the verdict block reads as "the row count changed". That renders an
    #     apparatus failure as a finding about upstream: the same conflation the control arm
    #     exists to prevent, pointing the other way.
    _mkstub atuin-corrupt corrupt
    _v_run atuin-corrupt --json
    if [[ "$(_v_verdict "$_vout")" == unmeasurable ]] && ((_vrc == 3)); then
      pass "atuin verify: an unreadable DB mid-run is unmeasurable (rc 3), never moved"
    else
      fail "atuin verify: an unreadable DB must be unmeasurable, got $(_v_verdict "$_vout")/rc$_vrc"
    fi

    # 11. THE SAME RULE, ONE STEP LATER IN THE RUN. #10 covers a DB that stops being
    #     READABLE; this covers one that stops being WRITABLE, which the -1 sentinel cannot
    #     see at all — the reads keep succeeding, so all four arms report an honest-looking
    #     delta of 0 and the run would report `holds` from an apparatus that died after the
    #     opening control. Only the CLOSING control arm can tell those apart. Deleting this
    #     assertion is how that fail-open comes back, the same way #5 guards the first one.
    _mkstub atuin-stops stops
    _v_run atuin-stops --json
    if [[ "$(_v_verdict "$_vout")" == unmeasurable ]] && ((_vrc == 3)) && [[ "$_vout" == *CLOSING* ]]; then
      pass "atuin verify: an apparatus that stops writing mid-run is unmeasurable (rc 3), never holds"
    else
      fail "atuin verify: a mid-run write failure must be unmeasurable naming the closing arm, got $(_v_verdict "$_vout")/rc$_vrc"
    fi

    # 12. BUFFER-AND-REPLAY IS A FINDING, and it is invisible to the four arms: a spooled
    #     entry and a discarded one both leave the row count at 0 while the socket is
    #     unreachable. It matters because the guard degrades a shell PERMANENTLY on the first
    #     failed connect, and that is only correct while atuin is discarding — an atuin that
    #     replays inverts the reasoning (dotgibson/dotfiles-core#383). The stub spools its
    #     four daemon-on entries and flushes them with the next daemon-off write, so the
    #     closing arm lands 5 rows instead of 1.
    _mkstub atuin-replay replay
    _v_run atuin-replay --json
    if [[ "$(_v_verdict "$_vout")" == moved ]] && ((_vrc == 1)) &&
      [[ "$_vout" == *'"drain_delta":5'* ]] && [[ "$_vout" == *BUFFERS* ]]; then
      pass "atuin verify: an atuin that spools and replays is moved (rc 1), naming the inverted premise"
    else
      fail "atuin verify: buffer-and-replay must be moved/rc1 with drain_delta 5, got $(_v_verdict "$_vout")/rc$_vrc"
    fi
  fi
fi

# ── J4. the AUTOSTART premise of the same detector (--premise autostart) ──────
# The other premise _core_atuin_daemon_guard rests on: under ATUIN_DAEMON__AUTOSTART the guard
# stands DOWN entirely — unhooks itself, never probes — because atuin is supposed to supervise
# its own daemon. That covers Alpine and macOS, and on those two it is the ONLY mitigation
# (dotgibson/dotfiles-core#402).
#
# WHAT THIS SECTION IS REALLY FOR. §J3's assertions are mostly about the third verdict, and so
# are these — but the conflation is sharper here, because this premise cannot be measured by
# observing: something has to be SPAWNED. "autostart did not start a daemon" and "this box
# cannot host a daemon" are the same observation, and only one of them is a fact about
# upstream. The manual-spawn control is what separates them, and case 9 below is the assertion
# that it actually does. A future simplification that deletes it would turn every CI sandbox
# problem into an issue titled "the autostart self-healing premise has MOVED".
#
# Hermetic, and genuinely so: the stub runs a REAL bindable AF_UNIX daemon (python3, exec'd so
# the process is signal-addressable), but no atuin, no systemd and no network are involved.
# ── the premise block's exclusivity lock ─────────────────────────────────────────────
# `mkdir` and not flock/pgrep, deliberately:
#   • mkdir is atomic on every POSIX filesystem and needs no util-linux — flock is absent on
#     macOS, and this suite runs on the MacBook too;
#   • a pgrep for "another test-core.sh" cannot work here at all. audit-core.sh runs
#     test-core.sh in the BACKGROUND of the same audit, concurrent with its static gates, so
#     a process-name probe would find its own sibling — or itself — and skip every audit.
# The lock is content-addressed to nothing but the machine: one holder at a time, fleet-wide.
#
# STALENESS MATTERS MORE THAN THE LOCK. A run killed with SIGKILL (or a machine that lost
# power mid-audit) leaves the directory behind, and a lock nothing can clear turns one crash
# into a permanently skipped block — which is worse than the flakiness it replaces, because
# it is silent and forever. So the holder's pid is recorded and a lock whose holder is gone
# is taken over.
_D_LOCK="${TMPDIR:-/tmp}/core-atuin-premise.lock"
_D_LOCK_HELD=0
_d_take_lock() {
  if mkdir "$_D_LOCK" 2>/dev/null; then
    printf '%s\n' "$$" >"$_D_LOCK/pid" 2>/dev/null || true
    _D_LOCK_HELD=1
    return 0
  fi
  local _holder
  _holder="$(cat "$_D_LOCK/pid" 2>/dev/null || true)"
  # No pid file, or a pid nobody answers for → the holder died. Take it over. `kill -0`
  # answers "is there a process" without signalling it, and a pid we do not own still
  # reports EPERM rather than ESRCH, so a live foreign holder is correctly left alone.
  if [[ -z "$_holder" ]] || ! kill -0 "$_holder" 2>/dev/null; then
    rm -rf "$_D_LOCK" 2>/dev/null || true
    if mkdir "$_D_LOCK" 2>/dev/null; then
      printf '%s\n' "$$" >"$_D_LOCK/pid" 2>/dev/null || true
      _D_LOCK_HELD=1
      return 0
    fi
  fi
  return 1
}
# Released on EXIT rather than at the end of the block: the block can leave by a `fail` path,
# and a lock held by a finished process would be reclaimed only by the staleness check above
# — correct, but it would make the very next run skip for no reason.
# Called from _core_test_cleanup, NOT from a trap of its own: a second `trap … EXIT` replaces
# the first, and the first is what removes this run's $SANDBOX.
_d_drop_lock() { ((_D_LOCK_HELD)) && rm -rf "$_D_LOCK" 2>/dev/null; return 0; }

_DVERIFY="$HERE/scripts/verify-atuin-guard.sh"
if [[ ! -x "$_DVERIFY" ]]; then
  skip "atuin autostart premise (scripts/verify-atuin-guard.sh absent or not executable)"
elif ! ((SCOPE_ATUIN)); then
  skip "atuin autostart premise (out of scope)"
elif ! have python3; then
  skip "atuin autostart premise (python3 not installed)"
elif ! _d_take_lock; then
  # EXCLUSIVITY, and a skip rather than a fail (#495). This block is hermetic with respect to
  # atuin, systemd and the network — but not with respect to another copy of ITSELF. Its
  # leak assertion reasons about what appeared under shared /tmp during a window, and its
  # fork/reap assertions about processes; neither can tell this run's residue from a
  # concurrent run's. That is not hypothetical here: the release path audits TWICE (`make
  # release` then `make tag`), this repo has carried six worktrees on one .git driven by
  # separate sessions, and a cut therefore needed two consecutive lucky greens to get out.
  # The observed shape was the tell — the same unmodified tree went `pass 261 fail 0` and
  # then `pass 260 fail 1` nine minutes later, and across three attempts the failure COUNT
  # varied (6, then 4, then 0), which a real defect does not do.
  #
  # A skip is honest; a flaky fail is not, and it teaches the operator to reach for
  # TAG_SKIP_AUDIT=1 — eroding the gate the runbook depends on, which is a far worse outcome
  # than one uncovered block.
  skip "atuin autostart premise (another test-core.sh holds the premise lock — not safely parallel)"
else
  hdr "atuin autostart self-healing premise (--premise autostart, hermetic)"
  # THIS RUN'S NAME IN SHARED /tmp. Case 17 asserts that a completed verifier run leaves no
  # sandbox behind, and the only evidence it has is what appeared under /tmp during a window.
  # /tmp has other writers — a second worktree, another agent, `make audit` in one terminal
  # while `make tag` audits in another — and an untagged glob cannot tell their sandbox from a
  # leak of ours. That is not hypothetical: it failed a `make tag` for exactly this reason.
  # Exported once, so every invocation below (case 18 runs the script from a copied repo, not
  # through _d_run) tags its trees identically and case 17's glob is exhaustive for OUR runs
  # and blind to everyone else's. The pid is the token because two LIVE processes cannot share
  # one, which is precisely the collision being defended against.
  _DTAG="t$$"
  export CORE_ATVERIFY_TAG="$_DTAG"
  _dstub="$(mktemp -d "$SANDBOX/dstub.XXXXXX")"
  # Section-local reaping. Every stub daemon writes its pid where the stub can find it, but a
  # test that fails midway can leave one behind — and unlike the script under test, this
  # harness has no EXIT trap of its own for them. The SANDBOX trap removes the files; this
  # removes the processes, which the files cannot do.
  _dreap() {
    local pf
    for pf in "$_dstub"/*.pid; do
      [[ -f "$pf" ]] || continue
      kill -9 "$(cat "$pf" 2>/dev/null)" 2>/dev/null
      rm -f "$pf"
    done
    for pf in "$_dstub"/*.forked; do
      [[ -f "$pf" ]] || continue
      while read -r _dp; do
        [[ -n "$_dp" ]] && kill -9 "$_dp" 2>/dev/null
      done <"$pf"
      rm -f "$pf"
    done
    rm -f "$_dstub"/*.spawned "$_dstub"/*.calls
    return 0
  }

  # _mkdstub <name> <mode> [version] — a fake atuin whose daemon really binds and really
  # answers, so prove_reachable's connect(2) has something to succeed against. Modes:
  #   heals                    everything works. Mirrors real 18.19.0 exactly, INCLUDING that
  #                            `daemon start` refuses over a stale inode while the autostart
  #                            CLIENT unlinks it first — measured, not assumed.
  #   never-spawns             manual works, autostart never spawns.            → moved
  #   heals-absent-not-stale   spawns on a clear path, not over a crashed daemon's leftover
  #                            inode. THE headline regression this premise exists to catch.
  #   spawns-but-discards      daemon comes up, entry never lands.              → moved
  #   manual-spawn-impossible  nothing can host a daemon here.                  → unmeasurable
  #   end-hangs                `history end` wedges on the autostart path only, so the manual
  #                            control still passes and the arms are reached — the bound then
  #                            expires on the half that carries the row.
  #   stop-unlinks-only        `daemon stop` removes the SOCKET and leaves the process alive
  #                            and holding the DB — atuin unlinks early in shutdown, so
  #                            "nothing answers" is not "the daemon exited".
  #   stop-noop                `daemon stop` accepts and does nothing — the teardown
  #                            escalation must still leave nothing running.
  #   no-daemon-subcommand     no `daemon start`.                               → unmeasurable
  #   no-stop-subcommand       no `daemon stop`.                                → unmeasurable
  #   fork-hang                autostart forks a child that NEVER binds and never exits —
  #                            invisible to every socket-based teardown path there is.
  #   manual-fork-nobind       `daemon start` forks a child that never binds and then EXITS,
  #                            so MANUAL_DAEMON_PID names a corpse and the socket never
  #                            answers — the manual control's version of fork-hang.
  #   fork-hang-end            the same, but the fork happens on `history end` rather than on
  #                            `history start`. atuin reaches its daemon through the same
  #                            autostarting path from both, so tracking only the opening half
  #                            of the pair would leave this one untracked.
  #
  # Every invocation is appended to stub-calls, which is how the "discard never spawns" and
  # "refused builds are never spawned on" assertions are made by CONSTRUCTION rather than by
  # trusting a comment.
  #
  # NOTE, as in §J3: the delimiter is unquoted so $mode and $ver interpolate, which means no
  # backticks may appear in this body and every runtime $ must be escaped.
  _mkdstub() {
    local name="$1" mode="$2" ver="${3:-18.19.0}"
    cat >"$_dstub/$name" <<STUB
#!/usr/bin/env bash
MODE="$mode"
DH="\${XDG_DATA_HOME:-/nonexistent}"
# LOG and PIDF live in the STUB dir, not the sandbox: verify-atuin-guard.sh removes its
# sandbox on the way out, so a log kept in there is gone by the time an assertion reads it —
# and "grep found no spawn" would pass for a deleted file exactly as it does for a real
# absence. Interpolated at generation time; only SOCK and DB belong to the measured tree.
LOG="$_dstub/$name.calls"
SPAWNMARK="$_dstub/$name.spawned"
FORKMARK="$_dstub/$name.forked"
SOCK="\$DH/atuin/atuin.sock"
PIDF="$_dstub/$name.pid"
DB="\$DH/atuin/history.db"
mkdir -p "\$DH/atuin" 2>/dev/null
printf '%s\n' "\$*" >>"\$LOG" 2>/dev/null

row() {
  python3 - "\$DB" <<'PY'
import sqlite3,sys
c=sqlite3.connect(sys.argv[1])
c.execute("create table if not exists history (id text, duration integer)")
c.execute("insert into history values ('x',-1)")
c.commit(); c.close()
PY
}

# EXEC, not a child: MANUAL_DAEMON_PID and socket_owner_pid both have to be able to signal
# this process, and a bash wrapper holding a python child would swallow the SIGKILL the
# teardown escalation depends on. The daemon then setsid()s below, so it leaves our process
# group the way a real one does. Binds in the FOREGROUND so a failure is immediate — and
# refuses over an existing inode, which is what 18.19.0 really does:
#   Error: Address already in use (os error 48)  crates/atuin-daemon/src/server.rs:72
serve_fg() {
  exec python3 - "\$SOCK" "\$PIDF" "\$MODE" "\$DB" <<'PY'
import socket, sys, os, sqlite3
sock, pidf, mode, db = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    s.bind(sock)
except OSError:
    sys.stderr.write("Error: Address already in use (os error 48)\n")
    sys.exit(98)
s.listen(8)
# DETACH, exactly as a real atuin daemon does. Measured on 18.19.0: the arm ran in process
# group 88291 and the daemon it spawned landed in 88299. A stub that stayed in the group
# would be reachable by the group reap and every teardown assertion here would pass for a
# reason that does not apply to atuin -- the stub has to be at least as hard to kill as the
# thing it stands in for.
try:
    os.setsid()
except OSError:
    pass
open(pidf, "w").write(str(os.getpid()))
s.settimeout(0.3)
while True:
    try:
        c, _ = s.accept()
        c.close()
    except socket.timeout:
        # stop-unlinks-only: once the socket is gone this daemon KEEPS COMMITTING. That is
        # what makes "nothing answers" different from "the daemon exited" — and it is only
        # observable because the extra rows land in arms that come after the fake stop.
        if mode == "stop-unlinks-only" and not os.path.exists(sock):
            try:
                con = sqlite3.connect(db, timeout=5)
                con.execute("insert into history values ('zombie',-1)")
                con.commit()
                con.close()
            except Exception:
                pass
    except Exception:
        pass
PY
}

daemon_up() {
  [[ -S "\$SOCK" ]] || return 1
  python3 -c "
import socket,sys
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(2)
try: s.connect('\$SOCK')
except OSError: sys.exit(1)
s.close()" 2>/dev/null
}

# What the autostart CLIENT does. stderr is silenced but STDOUT IS DELIBERATELY INHERITED:
# a spawned daemon holding the caller's fd 1 open is exactly the shape that used to hang
# run_one's \$( ) capture forever, so every autostart arm here regression-tests that fix
# instead of merely trusting it.
spawn_bg() {
  # The marker is the assertion's real subject. A call-log check only ever proved the CLI
  # spelling "daemon start" was not used -- and in this stub, as in atuin, the autostart
  # spawn happens INSIDE "history start", so a regression that turned autostart on in the
  # default premise would fork a daemon, log no "daemon start", and pass. Recorded outside
  # the sandbox, which the script deletes before any assertion runs. (No backticks here: the
  # heredoc delimiter is unquoted, so one would be command substitution at generation time.)
  printf 'spawn\n' >>"\$SPAWNMARK" 2>/dev/null
  ( serve_fg 2>/dev/null ) &
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    daemon_up && return 0
    sleep 0.05
  done
  return 1
}

case "\$1" in
--version) echo "atuin $ver"; exit 0 ;;
daemon)
  case "\$2" in
  start)
    if [[ "\$3" == --help ]]; then
      [[ "\$MODE" == no-daemon-subcommand ]] && exit 1
      echo "usage: atuin daemon start"; exit 0
    fi
    [[ "\$MODE" == manual-spawn-impossible ]] && { echo "Error: no" >&2; exit 1; }
    if [[ "\$MODE" == manual-fork-nobind ]]; then
      # Forks a child that never binds, then EXITS 0. The pid the caller recorded is dead a
      # moment later, nothing ever answers the socket, and no inode exists to resolve an
      # owner from -- only the process group knows about the survivor.
      sleep 300 &
      printf '%s\n' "\$!" >>"\$FORKMARK" 2>/dev/null
      exit 0
    fi
    serve_fg
    ;;
  stop)
    if [[ "\$3" == --help ]]; then
      [[ "\$MODE" == no-stop-subcommand ]] && exit 1
      echo "usage: atuin daemon stop"; exit 0
    fi
    # stop-noop ACCEPTS and does nothing, which is the realistic bad shape: a stop whose exit
    # status says yes while the process lives on. Proof-not-exit-status is why it is caught.
    [[ "\$MODE" == stop-noop ]] && exit 0
    # Unlink the socket and leave the daemon running -- it then starts committing rows. A
    # socket-only stop proof accepts this as stopped, after which every later arm measures
    # against a daemon it did not start and whose writes it will attribute to upstream.
    [[ "\$MODE" == stop-unlinks-only ]] && { rm -f "\$SOCK"; exit 0; }
    [[ -f "\$PIDF" ]] && kill "\$(cat "\$PIDF")" 2>/dev/null
    rm -f "\$SOCK" "\$PIDF"
    exit 0
    ;;
  esac
  exit 1
  ;;
history)
  case "\$2" in
  start)
    if [[ "\${ATUIN_DAEMON__ENABLED:-false}" != true ]]; then
      row   # daemon OFF: the row lands on start, and history end updates it in place
      echo "0192deadbeefcafe0000000000000000"; exit 0
    fi
    if [[ "\${ATUIN_DAEMON__AUTOSTART:-false}" == true ]] && ! daemon_up; then
      case "\$MODE" in
      never-spawns) : ;;
      fork-hang)
        # Forks a child that never binds and never exits. This is the shape the socket-based
        # teardown structurally cannot see: nothing ever answers, so the stop proof succeeds
        # instantly and socket_owner_pid has no inode to resolve a pid from. Only the arm's
        # process group knows about it. The pid is recorded so the test can check it died.
        sleep 300 &
        printf '%s\n' "\$!" >>"\$FORKMARK" 2>/dev/null
        ;;
      heals-absent-not-stale)
        # Spawns only onto a CLEAR path. A crashed daemon's leftover inode defeats it — the
        # silent net-loss on Alpine and macOS, and invisible to an absent-socket-only test.
        [[ -e "\$SOCK" ]] || spawn_bg
        ;;
      *)
        # heals and fork-hang-end both take this path: a real daemon must come up, or the arm
        # never gets a well-formed id and "history end" is never called.
        rm -f "\$SOCK"   # the real client clears a stale inode before spawning
        spawn_bg
        ;;
      esac
    fi
    echo "0192deadbeefcafe0000000000000000"; exit 0
    ;;
  end)
    # end-hangs: wedge the CLOSING half only, and only on the autostart path. Keyed that way
    # so the manual-spawn control (which does not set AUTOSTART) still passes and the run
    # actually reaches the arms, where the bound is supposed to fire.
    if [[ "\$MODE" == end-hangs && "\${ATUIN_DAEMON__AUTOSTART:-false}" == true ]]; then
      sleep 300
    fi
    # fork-hang-end: the closing half of the pair forks its own never-binding child. Recorded
    # in the same marker file, so one assertion covers however many halves forked.
    if [[ "\$MODE" == fork-hang-end && "\${ATUIN_DAEMON__AUTOSTART:-false}" == true ]]; then
      sleep 300 &
      printf '%s\n' "\$!" >>"\$FORKMARK" 2>/dev/null
    fi
    # With a daemon serving, the row lands on END, not on start. Measured on 18.19.0.
    if [[ "\${ATUIN_DAEMON__ENABLED:-false}" == true ]] && daemon_up; then
      # Keyed on AUTOSTART, not on the mode alone: the manual-spawn control writes through a
      # hand-started daemon, and if THAT is broken too the run is honestly unmeasurable rather
      # than a finding. This models the narrower, real shape — the daemon works, but entries
      # issued down the autostart path are dropped.
      if [[ "\$MODE" == spawns-but-discards && "\${ATUIN_DAEMON__AUTOSTART:-false}" == true ]]; then :; else row; fi
    fi
    exit 0
    ;;
  esac
  exit 1
  ;;
esac
exit 1
STUB
    chmod +x "$_dstub/$name"
  }

  # POLL very low on purpose, and only here. Every stub writes its row, binds its socket and
  # unlinks it SYNCHRONOUSLY before the call returns, so a positive case is satisfied on the
  # first tick and the bound is pure waiting for the cases that are SUPPOSED never to write —
  # of which there are several, four arms each. 3 ticks is therefore not a flakiness risk
  # here, and it is the difference between J4 costing seconds and costing minutes. Lowering it
  # against a REAL atuin manufactures findings; see the knob's own comment in
  # verify-atuin-guard.sh.
  # …AND THAT ARGUMENT DOES NOT COVER THE APPARATUS GATE, which is the one case here running a
  # stub that is supposed to SUCCEED at everything. For it the bound is not idle waiting, it is
  # a deadline: the manual-spawn control has 3 ticks — 300ms — for a spawned daemon to bind and
  # answer, and a loaded runner misses that. The verifier then declines, correctly and by
  # design, and the gate reads the decline as a defect in the detector. That reddened an audit
  # leg for an unrelated change.
  #
  # So the KNOWN-GOOD run gets a deadline with real headroom while every negative case keeps
  # the tight one. Measured on this repo's own fixture, all four arms holding: POLL=3 → 10.9s,
  # POLL=30 → 14.0s, POLL=100 → 23.4s. Three seconds of headroom for three seconds of wall
  # clock, once per suite, and 10x the margin on the only bound that has ever flaked here.
  # (Not free, because --premise autostart also spends the bound PROVING unreachability, which
  # is waiting that no amount of promptness shortens — hence 30 rather than 100.)
  _DPOLL=3
  _DPOLL_GATE=30
  # Set by the gate around its own calls; empty everywhere else. Declared here so `set -u`
  # holds and so the override is visible next to the constants it overrides.
  _dpoll=""
  _d_run() { # _d_run <stub> [extra args...] → sets _dout (stdout) / _dstderr / _drc
    local stub="$1"
    shift
    # STDOUT AND STDERR KEPT SEPARATE, unlike §J3's helper. Every case here passes --json and
    # the JSON is on stdout, so merging the two means any stray line — a busybox timeout
    # notice, a shell job-control message — lands inside the text being parsed and the
    # assertion fails for a reason that has nothing to do with the behaviour under test. That
    # is exactly how this first went red on Alpine: the exit code was a correct 3 and the
    # verdict came back empty, because something musl-side wrote to stderr and json.load then
    # choked on it. stderr is still captured, so a genuine crash still reaches the message.
    _dstderr=""
    _dout="$(CORE_COLOR=never CORE_ATVERIFY_POLL="${_dpoll:-$_DPOLL}" "$_DVERIFY" --atuin "$_dstub/$stub" "$@" 2>"$SANDBOX/derr.txt")"
    _drc=$?
    _dstderr="$(head -c 400 "$SANDBOX/derr.txt" 2>/dev/null | tr '\n' ' ')"
  }
  _d_get() { printf '%s' "$1" | python3 -c "import json,sys; print(json.load(sys.stdin)[\"$2\"])" 2>/dev/null; }
  # _d_calls <stub> — every invocation that stub received. Read from the stub dir, which
  # outlives the sandbox, so "no spawn was attempted" is a real absence rather than a
  # deleted file.
  _d_calls() { cat "$_dstub/$1.calls" 2>/dev/null; }
  # Did this stub ever FORK a daemon, by any route? Survives the sandbox, and unlike the call
  # log it is about the thing that matters rather than the command that usually causes it.
  _d_spawned() { [[ -s "$_dstub/$1.spawned" ]]; }
  # _d_forked_wait <stub> — wait, briefly and boundedly, for the stub's fork log to appear.
  #
  # The stub writes .forked from the CHILD it just forked, so "the file is not there yet" and
  # "the stub never forked" are the same observation at the wrong moment. Reading immediately
  # made that race decide the verdict, and the failure it produced named the wrong thing —
  # "the stub never forked, so the reaping assertion proved nothing" — which is how #495 came
  # to be filed as a flaky test rather than a race. ~2s at 50ms is far longer than a fork
  # needs and far shorter than the run it guards. Returns non-zero if it never appears, which
  # is then a real finding rather than a timing artefact.
  _d_forked_wait() {
    local _i
    for _i in $(seq 1 40); do
      [[ -s "$_dstub/$1.forked" ]] && return 0
      sleep 0.05
    done
    return 1
  }
  # _d_forks_alive <stub> — how many of the children that stub forked are STILL running.
  #
  # The `-s` guard is not defensive padding; without it this returned a SILENT ZERO. Bash
  # applies redirections left to right, so `<"$_dstub/$1.forked"` is opened BEFORE
  # `2>/dev/null` takes effect — a missing file therefore printed a raw
  # "No such file or directory" on the inherited stderr AND still ran the printf, handing the
  # caller a 0 indistinguishable from a genuinely clean reap. Its sibling _d_spawned just
  # above has always checked -s; this one was the outlier (#495).
  _d_forks_alive() {
    local n=0 pid
    [[ -s "$_dstub/$1.forked" ]] || { printf '0'; return 0; }
    while read -r pid; do
      [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && n=$((n + 1))
    done <"$_dstub/$1.forked" 2>/dev/null
    printf '%s' "$n"
  }

  # ── apparatus-free: the flag contract, assertable with no daemon anywhere ──
  # 1. An unknown premise is a USAGE error, not a measurement. The --color lesson applied to
  #    the one flag that selects which upstream fact is being asserted: a typo that fell
  #    through would measure the default premise and report it under the caller's title.
  CORE_COLOR=never "$_DVERIFY" --premise banana >/dev/null 2>&1
  _drc=$?
  CORE_COLOR=never "$_DVERIFY" --premise >/dev/null 2>&1
  _drc2=$?
  if ((_drc == 2 && _drc2 == 2)); then
    pass "atuin autostart: an unknown --premise and a --premise with no value both exit 2 (usage, not a finding)"
  else
    fail "atuin autostart: --premise must exit 2 on a bad value (got rc$_drc) and on a missing one (got rc$_drc2)"
  fi

  # 1b. THE TAG CONTRACT, asserted where it is cheapest — no daemon, no sandbox, no atuin.
  #     CORE_ATVERIFY_TAG is a PUBLIC knob (it is in --help), and case 17 only ever exports a
  #     generated valid one, so every way a caller can get it wrong was unasserted: the value
  #     becomes a path component under /tmp, and it is the only thing standing between the
  #     leak check and a glob that silently matches nothing.
  #
  #     THE EMPTY CASE IS THE IMPORTANT ONE, and it is why the script reads `${…-$$}` rather
  #     than the `${…:-…}` its two neighbouring knobs use. An empty tag is not a request for
  #     the default — it is a caller whose tag expression came out empty — and accepting it
  #     would put the sandbox under the pid while the caller globbed `/tmp/atverify..*`,
  #     matching nothing and greening the leak assertion forever. That is precisely the
  #     vacuous pass case 17's self-check exists to catch, arriving by a different door, so
  #     it is pinned here rather than left to the `-` vs `:-` being noticed in review.
  #
  #     Rejection must also happen BEFORE anything is measured, which is read off the stub's
  #     own call log rather than assumed: a tag validated late would already have spawned.
  _mkdstub atuin-tagck heals
  _dbad=0
  _dtagwhy=""
  # 17 chars, one past the cap — not 16, which is the accepted boundary asserted just below.
  #
  # THE TWO NON-ASCII CASES assert the ASCII half of the contract, and are the ones that would
  # notice if the script's LC_ALL=C pin were removed on a userland where it matters. A range
  # like [A-Z] is defined by COLLATION, not codepoint, so a locale may admit letters this
  # contract does not mean to allow; `ábcdefghij123456` is the same fault one step downstream —
  # sixteen CHARACTERS but seventeen BYTES, so a character-counting cap would pass a path
  # component longer than promised, against an AF_UNIX budget measured in bytes. Downstream,
  # not separate: every character in [A-Za-z0-9_-] is single-byte ASCII, so 16 chars can only
  # exceed 16 bytes once collation has already leaked a non-ASCII one in.
  #
  # THE PROBE ASKS THE ONLY QUESTION THAT MATTERS: is there a locale here under which the
  # UNPINNED pattern actually accepts the sample? An earlier version probed for multibyte
  # DECODING (`${#é}` is 1, not 2) and picked the first hit — which proved nothing, because a
  # locale can decode multibyte and still collate `á` outside [A-Za-z]. C.UTF-8 does exactly
  # that and was probed first, so the case passed identically with and without the pin: a
  # regression test that could not fail. Selecting on the real predicate means that where a
  # locale IS found the case genuinely fails if the pin is removed, and where none is found the
  # message SAYS the pin is unexercised here rather than implying coverage this box cannot give.
  # ENUMERATED, not guessed, wherever the box can answer. A hand-written candidate list is its
  # own way of reporting the wrong coverage: the locale that misbehaves here need not be among
  # seven names someone happened to think of — this machine offers 84 UTF-8 locales, not 7.
  # `locale -a` is the box's own answer; musl ships no such command, so the named candidates
  # survive as the fallback and the result line says which source it actually used.
  _dlocs="$(locale -a 2>/dev/null | grep -iE 'utf-?8' || true)"
  _dlocsrc=installed
  if [[ -z "$_dlocs" ]]; then
    _dlocsrc=candidate
    _dlocs="$(printf '%s\n' C.UTF-8 en_US.UTF-8 en_US.utf8 UTF-8 de_DE.UTF-8 cs_CZ.UTF-8 hu_HU.UTF-8)"
  fi
  _dutf8=""
  _dlocn=0
  while read -r _dl; do
    [[ -n "$_dl" ]] || continue
    _dlocn=$((_dlocn + 1))
    if LC_ALL="$_dl" "$BASH" -c '[[ "$1" =~ ^[A-Za-z0-9_-]{1,16}$ ]]' _ 'tág' 2>/dev/null; then
      _dutf8="$_dl"
      break
    fi
  done <<<"$_dlocs"
  # Said out loud in the result line, because "the pin is exercised here" and "no locale here
  # can exercise it" are different facts and a reader must not have to guess which one a green
  # tick meant. This is the same discipline as case 17's self-check, applied to coverage.
  if [[ -n "$_dutf8" ]]; then
    _dcov=" — LC_ALL=C pin EXERCISED under $_dutf8, which accepts the sample unpinned"
  else
    _dcov=" — none of $_dlocn $_dlocsrc UTF-8 locales accepts the sample unpinned, so the LC_ALL=C pin is unexercised on this box (contract only)"
  fi
  for _dcase in "bad/tag" "up..dir" "abcdefghij1234567" "" "tag with space" "tág" "ábcdefghij123456"; do
    # `:-C`, not a bare "$_dutf8". An EMPTY LC_ALL is not "no locale" — it falls through to the
    # caller's LC_COLLATE/LANG, which is an unprobed locale that could be the very one that
    # accepts the sample. The run would then exercise the pin while the line above reported it
    # unexercised: the report would be wrong in the one direction a coverage claim must not be.
    LC_ALL="${_dutf8:-C}" CORE_COLOR=never CORE_ATVERIFY_TAG="$_dcase" "$_DVERIFY" \
      --premise autostart --atuin "$_dstub/atuin-tagck" >/dev/null 2>&1
    _drc=$?
    if ((_drc != 2)); then
      _dbad=1
      _dtagwhy="$_dtagwhy '${_dcase:-<empty>}'→rc$_drc"
    fi
  done
  # Accepted, by contrast: the 16-char boundary and an ABSENT tag both get past validation and
  # fail later for the missing binary (rc 3), which is what tells acceptance from rejection
  # without measuring anything. The absent case is the standalone contract — it is what
  # `make verify-atuin-guard` and atuin-guard-verify.yml rely on, and the section exports a
  # tag, so it is unset in a SUBSHELL rather than for the rest of the run.
  CORE_COLOR=never CORE_ATVERIFY_TAG="sixteenchars0123" "$_DVERIFY" \
    --premise autostart --atuin "$_dstub/nonexistent" >/dev/null 2>&1
  _drc=$?
  if ((_drc != 3)); then
    _dbad=1
    _dtagwhy="$_dtagwhy 16-char→rc$_drc"
  fi
  (
    unset CORE_ATVERIFY_TAG
    CORE_COLOR=never "$_DVERIFY" --premise autostart \
      --atuin "$_dstub/nonexistent" >/dev/null 2>&1
  )
  _drc=$?
  if ((_drc != 3)); then
    _dbad=1
    _dtagwhy="$_dtagwhy unset→rc$_drc"
  fi
  [[ -z "$(_d_calls atuin-tagck)" ]] || {
    _dbad=1
    _dtagwhy="$_dtagwhy (a rejected tag still invoked atuin)"
  }
  _dreap
  if ((_dbad == 0)); then
    pass "atuin autostart: a tag that is empty, overlong, non-ASCII, or not [A-Za-z0-9_-] exits 2 before measuring, while the 16-char boundary and an ABSENT tag are accepted$_dcov"
  else
    fail "atuin autostart: the CORE_ATVERIFY_TAG contract is not enforced —$_dtagwhy; an accepted bad tag globs nothing and greens the leak check vacuously"
  fi

  # 2. The premise travels in the JSON. The workflow's two legs differ by ONE flag and both
  #    file issues under different titles, so it asserts this field rather than trusting the
  #    flag reached the script — this is the assertion that makes that check meaningful.
  _d_run nonexistent-stub --premise autostart --json
  if [[ "$(_d_get "$_dout" verdict)" == unmeasurable ]] && ((_drc == 3)) &&
    [[ "$(_d_get "$_dout" premise)" == autostart ]]; then
    pass "atuin autostart: --premise autostart is carried in --json, and a missing atuin is still rc 3"
  else
    fail "atuin autostart: expected unmeasurable/rc3/premise=autostart, got $(_d_get "$_dout" verdict)/rc$_drc/$(_d_get "$_dout" premise)"
  fi

  # 3. THE DEFAULT TARGET MUST STAY LAPTOP-SAFE. `make verify-atuin-guard` starts no
  #    background process today, and adding one silently would change what that target costs
  #    on a developer's machine. Asserted by CONSTRUCTION — the stub logs every invocation it
  #    receives, so this reads the log rather than believing a comment.
  _mkdstub atuin-heals heals
  _d_run atuin-heals --json >/dev/null 2>&1
  if _d_calls atuin-heals | grep -qE '^daemon start( |$)' || _d_spawned atuin-heals; then
    fail "atuin autostart: --premise discard started a daemon — the default target must spawn nothing, by any route"
  else
    pass "atuin autostart: --premise discard forks no daemon at all (not via 'daemon start', not via autostart inside 'history start')"
  fi
  _dreap

  # ── APPARATUS SELF-CHECK — and deliberately NOT through the subject under test.
  #    The obvious form of this gate ("run the known-good stub; skip everything if it does not
  #    say holds") uses the code under test as its own apparatus check, so ANY regression that
  #    made the healthy stub report `moved` or `unmeasurable` would skip every assertion below
  #    and leave the audit GREEN — the regression suite going blind to exactly the failures it
  #    exists to catch. So the box is proven FIRST, with python3 alone: bind an AF_UNIX socket
  #    under /tmp and connect to it, which is the only capability these cases need that an
  #    ordinary box might lack. Only if THAT fails is a skip honest.
  if ! python3 - "/tmp/j4probe.$$.sock" <<'J4PROBE' 2>/dev/null
import socket, sys, os
p = sys.argv[1]
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(p)
    s.listen(1)
    c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    c.settimeout(2)
    c.connect(p)
    c.close()
    s.close()
    os.unlink(p)
except Exception:
    sys.exit(1)
J4PROBE
  then
    rm -f "/tmp/j4probe.$$.sock"
    skip "atuin autostart: measurement assertions (this box cannot bind and connect an AF_UNIX socket under /tmp)"
  else
    rm -f "/tmp/j4probe.$$.sock"
    # The apparatus is established WITHOUT the subject's help, so a known-good stub that does
    # not report `holds` is a regression in the detector — a FAILURE, never a skip. This gate is
    # deliberately NOT §J3's blanket "skip unless holds": there, no independent probe exists, so
    # declining is all it can honestly do; here one does, and the stricter stance is the point.
    #
    # THE STRICTNESS IS KEPT AND THE DEADLINE IS FIXED INSTEAD, which is the whole correction.
    # This arm used to fail on ANY non-`holds`, including `unmeasurable` — the verifier's
    # fail-closed answer when the manual-spawn control's daemon did not answer inside 300ms. On
    # a loaded runner that is a property of the BOX, and reporting it as a defect in the
    # detector is a false finding of exactly the kind §J4 exists to prevent.
    #
    # The tempting repair — skip on `unmeasurable` — is wrong, and the reason is worth keeping:
    # that verdict covers a family of causes, and most are DETERMINISTIC AND ARE THE DETECTOR
    # (a renamed or duplicated anchor, control-arm row accounting that no longer matches, and
    # `internal: no verdict was reached (this is a bug in verify-atuin-guard.sh)`). Skipping on
    # it would silence the sixteen assertions below while the subject announces its own bug —
    # the blindness the block comment above refuses to allow, arriving by a quieter door. No
    # amount of retrying separates those from slowness either, since every one of them repeats.
    #
    # So nothing here skips. The deadline is simply made generous enough that missing it is not
    # ordinary: $_DPOLL_GATE ticks instead of $_DPOLL, and one retry, so a transient stall has
    # to land twice inside a 10x-wider window to be seen at all. What remains is a gate that
    # cannot go quiet — every verdict other than `holds` still reddens it — bought with about
    # three seconds of wall clock, once.
    #
    # The three failures are told apart because they mean different things to whoever reads the
    # line: `moved` is the verifier miscategorising correct behaviour, `unmeasurable` is it
    # declining where it should measure (and carries its own reason, which names the cause), and
    # no parseable verdict at all is the apparatus failing to report — the Alpine shape, where a
    # stray stderr line merged into the JSON, so that one carries stderr.
    _dpoll="$_DPOLL_GATE"
    _d_run atuin-heals --premise autostart --json
    _dapp="$(_d_get "$_dout" verdict)"
    _dappwhy="$(_d_get "$_dout" reason)"
    _dreap
    if [[ "$_dapp" == unmeasurable ]]; then
      _d_run atuin-heals --premise autostart --json
      _dapp="$(_d_get "$_dout" verdict)"
      _dappwhy="$(_d_get "$_dout" reason)"
      _dreap
    fi
    _dpoll=""
    if [[ "$_dapp" == unmeasurable ]]; then
      fail "atuin autostart: the known-good stub reported unmeasurable TWICE at a ${_DPOLL_GATE}-tick bound — this box can bind AF_UNIX sockets, so verify-atuin-guard.sh is declining where it should measure: ${_dappwhy:-no reason parsed}"
    elif [[ "$_dapp" == moved ]]; then
      fail "atuin autostart: this box can bind AF_UNIX sockets, yet the known-good stub reported moved rather than holds — that is a regression in verify-atuin-guard.sh, not an unusable apparatus: ${_dappwhy:-no reason parsed}"
    elif [[ "$_dapp" != holds ]]; then
      fail "atuin autostart: the known-good stub produced no parseable verdict (rc$_drc) — the apparatus failed to report rather than measuring${_dstderr:+ (stderr: $_dstderr)}"
    else

    # 4. The happy path, and the shape real 18.19.0 has: all four arms spawn and land a row.
    if ((_drc == 0)) && [[ "$_dout" == *'"spawned":"no"'* ]]; then
      fail "atuin autostart: a healing atuin reported an arm that did not spawn"
    elif ((_drc == 0)); then
      pass "atuin autostart: an atuin that self-heals its daemon → holds (rc 0), every arm spawned"
    else
      fail "atuin autostart: expected holds/rc0 for a healing atuin, got rc$_drc"
    fi

    # 5. Expected delta is 1 here and 0 under discard, on arms with IDENTICAL names. Without
    #    expected_delta in the JSON a reader has no way to tell a healthy autostart arm from a
    #    discard arm that just broke.
    if [[ "$_dout" == *'"expected_delta":1'* ]] && [[ "$_dout" != *'"expected_delta":0'* ]]; then
      pass "atuin autostart: every arm records expected_delta 1, so an identically-named discard arm cannot be misread"
    else
      fail "atuin autostart: arms must carry expected_delta 1 under this premise"
    fi

    # 6. An atuin that never spawns is a FINDING, and the reason must say so in the words the
    #    remedy depends on — "no daemon became reachable", not merely "the row count changed".
    _mkdstub atuin-nospawn never-spawns
    _d_run atuin-nospawn --premise autostart --json
    _dreap
    if [[ "$(_d_get "$_dout" verdict)" == moved ]] && ((_drc == 1)) &&
      [[ "$_dout" == *"no daemon became reachable"* ]]; then
      pass "atuin autostart: an atuin that never spawns a daemon → moved (rc 1), naming the absent spawn"
    else
      fail "atuin autostart: expected moved/rc1 naming the absent spawn, got $(_d_get "$_dout" verdict)/rc$_drc"
    fi

    # 7. THE HEADLINE SHAPE. Spawns onto a clear path, not over a crashed daemon's leftover
    #    inode. Every `atuin history start` is a fresh process, so this is what
    #    "fire-and-forget" can actually mean — and an absent-socket-only detector would call
    #    it healthy while Alpine and macOS quietly lost their net.
    _mkdstub atuin-halfheal heals-absent-not-stale
    _d_run atuin-halfheal --premise autostart --json
    _dreap
    if [[ "$(_d_get "$_dout" verdict)" == moved ]] && ((_drc == 1)) &&
      [[ "$_dout" == *'"stale_hook":{"rc":0,"delta":0'* ]] &&
      [[ "$_dout" == *'"absent_hook":{"rc":0,"delta":1'* ]]; then
      pass "atuin autostart: spawning on an absent socket but NOT over a stale one is moved — the stale arm is why it is measured"
    else
      fail "atuin autostart: half-healing must be moved with stale arms failing and absent arms passing, got $(_d_get "$_dout" verdict)/rc$_drc"
    fi

    # 8. A daemon that comes up and drops the entry is a DIFFERENT finding from one that never
    #    came up, and both leave delta 0 — which is exactly why `spawned` is recorded per arm
    #    rather than inferred from the row count.
    _mkdstub atuin-nowrite spawns-but-discards
    _d_run atuin-nowrite --premise autostart --json
    _dreap
    if [[ "$(_d_get "$_dout" verdict)" == moved ]] && ((_drc == 1)) &&
      [[ "$_dout" == *'"spawned":"yes"'* ]] && [[ "$_dout" == *"did not land"* ]]; then
      pass "atuin autostart: a daemon that spawns but drops the entry is moved, and is distinguished from one that never spawned"
    else
      fail "atuin autostart: spawn-but-discard must be moved naming the unlanded entry, got $(_d_get "$_dout" verdict)/rc$_drc"
    fi

    # 9. THE LOAD-BEARING ONE, and §J3 case 5's counterpart. A box that cannot host a daemon
    #    AT ALL must be `unmeasurable` — never a finding about upstream. This is the whole
    #    reason the manual-spawn control exists, and the assertion a future simplification
    #    that deletes it would trip.
    _mkdstub atuin-nodaemon manual-spawn-impossible
    _d_run atuin-nodaemon --premise autostart --json
    _dreap
    if [[ "$(_d_get "$_dout" verdict)" == unmeasurable ]] && ((_drc == 3)) &&
      [[ "$_dout" == *"cannot host a daemon"* ]]; then
      pass "atuin autostart: a box where NO daemon can start is unmeasurable (rc 3), never a finding about upstream"
    else
      fail "atuin autostart: a failed spawn CONTROL must be unmeasurable/rc3, got $(_d_get "$_dout" verdict)/rc$_drc — an apparatus limit was rendered as an upstream finding"
    fi

    # 10. A build this script cannot cleanly stop is one it must not start. atuin has moved
    #     the daemon subcommand spelling before (#380), and unlike the bench — which holds a
    #     PID to kill — an autostart daemon's PID is never handed to us. Refusing costs an
    #     unmeasurable run; spawning anyway costs a process writing into a deleted tree.
    for _dcase in no-daemon-subcommand no-stop-subcommand; do
      _mkdstub "atuin-$_dcase" "$_dcase"
      _d_run "atuin-$_dcase" --premise autostart --json
      # REAP AFTER THE ASSERTION, not before: _dreap deletes the .calls and .spawned markers,
      # and reading them afterwards is reading files that are already gone — both checks would
      # then pass for a build that DID spawn.
      if [[ "$(_d_get "$_dout" verdict)" == unmeasurable ]] && ((_drc == 3)) &&
        ! _d_calls "atuin-$_dcase" | grep -qE '^daemon start$' && ! _d_spawned "atuin-$_dcase"; then
        pass "atuin autostart: $_dcase is unmeasurable (rc 3) and nothing was spawned on it"
      else
        fail "atuin autostart: $_dcase must be unmeasurable/rc3 with no spawn attempted, got $(_d_get "$_dout" verdict)/rc$_drc"
      fi
      _dreap
    done

    # 11. TEARDOWN IS THE KNOWN-HARD PART. A `daemon stop` that returns 0 and does nothing is
    #     the realistic bad shape — which is why the stop is PROVEN by a connect rather than
    #     believed from an exit status. The escalation must still leave nothing running and
    #     nothing behind, or the next arm measures a daemon it did not start and the EXIT
    #     trap rm -rf's a tree a live process is writing into.
    #
    #     WHAT THIS DOES NOT COVER, stated so the gap is not mistaken for coverage: the branch
    #     where the stop can never be proven at all, which PRESERVES the sandbox and prints its
    #     path. No portable stub can reach it — a process that survives SIGKILL does not exist,
    #     and the escalation's PID lookup is what would have to fail instead (/proc on Linux,
    #     lsof on macOS), which is platform-specific rather than something a stub can arrange.
    #     It was verified by hand on macOS by running this same stub with lsof off PATH:
    #     verdict `unmeasurable`, sandbox kept, and the exact `rm -rf` printed to stderr.
    _mkdstub atuin-stopnoop stop-noop
    _d_run atuin-stopnoop --premise autostart --json
    _dleft=0
    _dpf="$_dstub/atuin-stopnoop.pid"
    if [[ -f "$_dpf" ]] && kill -0 "$(cat "$_dpf" 2>/dev/null)" 2>/dev/null; then
      _dleft=1
    fi
    _dreap
    if ((_dleft == 0)) && [[ -n "$(_d_get "$_dout" verdict)" ]]; then
      pass "atuin autostart: a 'daemon stop' that lies still leaves no daemon running — the stop is proven, not believed"
    else
      fail "atuin autostart: a no-op 'daemon stop' left a daemon alive; teardown escalation did not work"
    fi

    # 12. THE CHILD NO SOCKET CAN SEE. autostart may fork a daemon that hangs or dies before
    #     it ever binds: nothing answers, so the stop proof succeeds instantly and
    #     socket_owner_pid has no inode to resolve a pid from. The arm's PROCESS GROUP is the
    #     only handle on it, which is why the arms run under `set -m` — and why run_one returns
    #     its record in a global rather than on stdout, since a command substitution would run
    #     the whole function in a subshell and discard the group id before cleanup ever saw it.
    _mkdstub atuin-forkhang fork-hang
    _d_run atuin-forkhang --premise autostart --json
    _d_forked_wait atuin-forkhang || true
    _dalive="$(_d_forks_alive atuin-forkhang)"
    _dforked="$(grep -c . "$_dstub/atuin-forkhang.forked" 2>/dev/null || echo 0)"
    _dreap
    if ((_dforked > 0)) && ((_dalive == 0)); then
      pass "atuin autostart: a child that forks and never binds is still reaped ($_dforked forked, 0 alive) — the process group catches what the socket cannot"
    elif ((_dforked == 0)); then
      fail "atuin autostart: the fork-hang stub never forked, so the reaping assertion proved nothing"
    else
      fail "atuin autostart: $_dalive of $_dforked never-bound children survived the run — cleanup deleted the sandbox around a live process"
    fi

    # (There is no case here for a child that DETACHES and never binds. The handle that
    #  covered it — matching processes by the sandbox path in their environment — was removed
    #  deliberately: exact only on Linux, a different mechanism on macOS, and in two
    #  consecutive reviews the source of fail-open defects of its own. The residual is
    #  documented at daemon_stop_proven and in the report's scope note rather than half-tested
    #  here.)

    # 13. THE SAME HOLE IN THE CLOSING HALF OF THE PAIR. Tracking only `history start` would
    #     pass case 12 while leaving an `end`-spawned child untracked, and `end` runs with the
    #     same AUTOSTART env down the same autostarting path — so it is asserted separately
    #     rather than assumed to be covered by its sibling.
    _mkdstub atuin-forkhangend fork-hang-end
    _d_run atuin-forkhangend --premise autostart --json
    _d_forked_wait atuin-forkhangend || true
    _dalive="$(_d_forks_alive atuin-forkhangend)"
    _dforked="$(grep -c . "$_dstub/atuin-forkhangend.forked" 2>/dev/null || echo 0)"
    _dreap
    if ((_dforked > 0)) && ((_dalive == 0)); then
      pass "atuin autostart: a child forked by the CLOSING half of the pair is reaped too ($_dforked forked, 0 alive)"
    elif ((_dforked == 0)); then
      fail "atuin autostart: the fork-hang-end stub never forked on 'history end', so the assertion proved nothing"
    else
      fail "atuin autostart: $_dalive of $_dforked children forked by 'history end' survived — only the opening half of the pair is tracked"
    fi

    # 14. THE MANUAL CONTROL HAS THE SAME HOLE, and it was the last untracked spawn here. If
    #     `daemon start` forks a child that never binds and its parent exits, the recorded pid
    #     is a corpse, wait_reachable fails, cleanup sees an absent socket and calls it
    #     stopped, and reap_manual has nothing left to kill. The verdict must still be
    #     `unmeasurable` (this box could not host a daemon -- never a finding about upstream),
    #     AND the survivor must be reaped.
    _mkdstub atuin-manualfork manual-fork-nobind
    _d_run atuin-manualfork --premise autostart --json
    _d_forked_wait atuin-manualfork || true
    _dalive="$(_d_forks_alive atuin-manualfork)"
    _dforked="$(grep -c . "$_dstub/atuin-manualfork.forked" 2>/dev/null || echo 0)"
    _dv="$(_d_get "$_dout" verdict)"
    _dreap
    if [[ "$_dv" == unmeasurable ]] && ((_drc == 3)) && ((_dforked > 0)) && ((_dalive == 0)); then
      pass "atuin autostart: a manual spawn that forks without binding is unmeasurable AND its orphan is reaped ($_dforked forked, 0 alive)"
    elif ((_dforked == 0)); then
      fail "atuin autostart: the manual-fork-nobind stub never forked, so the assertion proved nothing"
    else
      fail "atuin autostart: manual-fork-nobind gave $_dv/rc$_drc with $_dalive of $_dforked orphans alive — the manual control is not process-group tracked"
    fi

    # 15. A BOUND THAT EXPIRES ON THE CLOSING HALF IS STILL AN APPARATUS LIMIT. The row lands
    #     on `history end` when a daemon is serving, so `end` is the verdict-bearing call —
    #     and its status used to be discarded, leaving a timed-out `end` looking like a
    #     successful `start` with a missing row, which the verdict block reported as
    #     "the entry did not land". A finding about upstream, manufactured by this run's own
    #     timeout. The wedge is on the autostart path only, so the manual control passes and
    #     the arms are actually reached.
    # GUARDED ON A TIMEOUT UTILITY, because this case's whole mechanism is the bound. Where
    # neither timeout(1) nor gtimeout(1) exists the verifier deliberately measures UNBOUNDED
    # and discloses it — which is right for a real run and fatal here: TIMEOUT_CMD is empty, so
    # nothing cuts the stub's four 300-second wedges and the suite runs to the job timeout
    # instead of failing. A stock macOS box has neither utility, and the macOS audit leg runs
    # this section.
    if ! have timeout && ! have gtimeout; then
      skip "atuin autostart: wedged 'history end' (no timeout(1)/gtimeout(1) here, so the verifier measures unbounded by design and the case's own wedge would never be cut)"
    else
    _mkdstub atuin-endhangs end-hangs
    CORE_ATVERIFY_TIMEOUT=2 _d_run atuin-endhangs --premise autostart --json
    _dv="$(_d_get "$_dout" verdict)"
    _dwhy="$(_d_get "$_dout" reason)"
    _dreap
    if [[ "$_dv" == unmeasurable ]] && ((_drc == 3)) && [[ "$_dwhy" == *"did not return within"* ]]; then
      pass "atuin autostart: a 'history end' that wedges is unmeasurable (rc 3), never a finding that the entry did not land"
    else
      fail "atuin autostart: a wedged 'history end' must be unmeasurable/rc3 naming the bound, got ${_dv:-<unparseable>}/rc$_drc${_dstderr:+ (stderr: $_dstderr)}"
    fi
    fi

    # 16. "NOTHING ANSWERS" IS NOT "THE DAEMON EXITED". atuin unlinks its socket early in
    #     shutdown and `daemon stop` can return while teardown is still running, so a
    #     socket-only proof accepts a daemon that is gone from the socket and still HOLDING
    #     THE DB. The harm is not a leak — cleanup's group reap would catch that — it is
    #     CONTAMINATION: every later arm then measures against a daemon it did not start, and
    #     attributes that daemon's writes to upstream. This stub's zombie keeps committing
    #     once its socket is unlinked, so a socket-only proof yields extra rows and a FALSE
    #     `moved`; the group half of the proof kills it at the inter-arm stop and the run
    #     stays clean. Asserted on the VERDICT, because that is where the damage would show.
    #
    #     THREE VERDICTS HERE TOO, and this is the one case in the section that had to learn
    #     it. Every other verdict-bearing arm drives its stub to a SPECIFIC negative
    #     (`moved`, or `unmeasurable` for a named apparatus limit), so anything else is a
    #     genuine miss. This one is the only arm that expects the POSITIVE verdict from an
    #     otherwise well-behaved stub — which means it inherits every environmental way a run
    #     can honestly decline, and `[[ $_dv == holds ]]` … `else fail` swept all of them into
    #     a message asserting an upstream finding. That is precisely the inversion the third
    #     verdict exists to prevent (see verify-atuin-guard.sh's header: `unmeasurable` is
    #     "the apparatus could not be trusted … never a finding about upstream"), so the check
    #     that polices it must not be the one committing it.
    #
    #     NOT HYPOTHETICAL, and not a rare corner. The section runs at CORE_ATVERIFY_POLL=3 —
    #     300ms for the manual-spawn control's daemon to bind and answer — which a loaded box
    #     misses, yielding "a daemon started by hand never answered … An apparatus limit, not
    #     a finding" with NOTHING having survived. Reproduced under CPU contention (the same
    #     stub flips holds/unmeasurable), and it reddened audit-alpine on an unrelated
    #     docs-only PR, where a rerun of the identical commit went green.
    #
    #     THE SKIP DOES NOT MAKE THIS GO QUIET, which is the only reason it is allowed. The
    #     two halves are separated: the SURVIVOR half is unconditional and stays a failure
    #     under any verdict — a live daemon is a leak whether or not the run could measure —
    #     and `moved` stays a failure because that is the false verdict the zombie's rows
    #     would manufacture. Nor can a contaminated control hide behind the skip: the opening
    #     control runs before any daemon exists, the spawn control runs while the socket is
    #     PRESENT (this stub only commits once it is gone), and the closing drain control runs
    #     only after daemon_stop_proven has confirmed the owner pid dead. Contamination has no
    #     route to `unmeasurable` here — it can only surface as `moved` or a survivor.
    _mkdstub atuin-stopunlink stop-unlinks-only
    _d_run atuin-stopunlink --premise autostart --json
    _dv="$(_d_get "$_dout" verdict)"
    _dwhy="$(_d_get "$_dout" reason)"
    _dleft=0
    _dpf="$_dstub/atuin-stopunlink.pid"
    if [[ -f "$_dpf" ]] && kill -0 "$(cat "$_dpf" 2>/dev/null)" 2>/dev/null; then
      _dleft=1
    fi
    _dreap
    if ((_dleft != 0)); then
      fail "atuin autostart: a socket-only stop left the zombie daemon alive (verdict=$_dv) — it keeps committing into later arms and its writes would be reported as an upstream finding"
    elif [[ "$_dv" == holds ]]; then
      pass "atuin autostart: a daemon that outlives its own socket is stopped before the next arm — it cannot write rows the run would blame on upstream"
    elif [[ "$_dv" == unmeasurable ]]; then
      skip "atuin autostart: a daemon that outlives its own socket — no zombie survived, but the verdict half could not be measured on this box (${_dwhy:-no reason reported})"
    elif [[ "$_dv" == moved ]]; then
      fail "atuin autostart: a socket-only stop let the zombie's rows land in a measured arm — the run reports a premise that MOVED on writes it made itself"
    else
      # NO VERDICT AT ALL is its own outcome, and routing it into the `moved` arm would name a
      # cause this run has no evidence for. It is also the one shape with a KNOWN history here:
      # a stray line on stderr merging into stdout leaves json.load with nothing to parse, which
      # is how §J4 first went red on Alpine (see _d_run's comment). So stderr is carried into the
      # message — it is the only thing that can say what actually happened.
      fail "atuin autostart: the socket-only-stop run produced no parseable verdict (rc$_drc) — this is the apparatus failing to report, not a measurement${_dstderr:+ (stderr: $_dstderr)}"
    fi

    # 17. The sandbox is REMOVED on a normal run — asserted on the DELTA, not on a global scan
    #     of /tmp. The verifier DELIBERATELY preserves a sandbox when a stop cannot be proven,
    #     so a tree left by an earlier run, a hand-run, or a concurrent one would otherwise
    #     fail this for a run that cleaned up perfectly. Only paths this run created count.
    #
    #     A DELTA IS NOT ENOUGH, because /tmp is a SHARED namespace and the window is not
    #     exclusive. This globbed every `atverify.*` and treated anything new as a leak, which
    #     silently assumed no second run existed — and a second run is ordinary here: another
    #     worktree, another agent, or simply `make audit` in one terminal while `make tag`
    #     audits in another. The second run's sandbox is born inside the first run's window and
    #     the first run reports a leak that does not exist. That is what happened: a `make tag`
    #     failed the audit with "leaked 1 new sandbox dir(s)" on the repo's most consequential
    #     command, where the operator's natural next move — re-run, or reach for
    #     TAG_SKIP_AUDIT=1 — is the exact habit a release gate must not teach. So the glob is
    #     narrowed to $_DTAG, the tag every sandbox of OURS carries (see CORE_ATVERIFY_TAG),
    #     and a foreign tree is now invisible to it by construction rather than by luck.
    #
    #     THE SELF-CHECK IS NOT OPTIONAL. A delta over a directory listing that silently
    #     returns nothing passes for every run, forever — and that is precisely what the first
    #     version of this did: on macOS /tmp is a symlink to private/tmp and `find /tmp`
    #     without -L does not descend it, so both snapshots were empty and the assertion was
    #     vacuous on a third of the fleet. Prove the snapshot can see a directory before
    #     trusting it to notice one. (The fault there was the unfollowed symlink, not a
    #     missing -maxdepth.) Narrowing the glob makes that guard MORE load-bearing, not less:
    #     a tag that never reached the script would empty both snapshots the same way.
    # The shell's own one-level glob, not find(1) and not ls(1). BSD find on macOS does
    # support -maxdepth (checked against /usr/bin/find, which is what the macOS CI leg runs),
    # so the earlier version was not broken for that reason — but a glob needs no portability
    # argument at all, and this check has already been silently blind once.
    _dsnap() {
      local d
      local -a out=()
      for d in "/tmp/atverify.$_DTAG."*; do [[ -d "$d" ]] && out+=("$d"); done
      ((${#out[@]})) && printf '%s\n' "${out[@]}" | sort
      return 0
    }
    # _dnewdirs <pre-snapshot> — the tagged dirs present now that were absent in <pre>.
    # comm needs sorted input on both sides; _dsnap sorts, so a snapshot may be fed back in.
    _dnewdirs() {
      comm -13 <(printf '%s\n' "$1" | grep -v '^$') <(_dsnap | grep -v '^$')
    }
    _dselfck="/tmp/atverify.$_DTAG.selfcheck$$"
    mkdir -p "$_dselfck"
    if ! _dsnap | grep -q "atverify.$_DTAG.selfcheck$$"; then
      rmdir "$_dselfck" 2>/dev/null
      fail "atuin autostart: the sandbox-leak check cannot enumerate /tmp — it would pass vacuously, so it is reported as broken rather than green"
    else
      rmdir "$_dselfck" 2>/dev/null
      _dpre="$(_dsnap)"
      _d_run atuin-heals --premise autostart --json
      _dreap
      # A CONCURRENT RUN'S SANDBOX, planted inside the window on purpose — this is the
      # regression half of the assertion, not scaffolding. Who created it is irrelevant: a
      # glob is all this check has to reason with, so a directory of the right SHAPE under a
      # tag that is not ours is exactly what a second test-core.sh on this box contributes.
      # If it is ever counted again, this arm goes red here rather than at a release cut.
      _dforeign="/tmp/atverify.foreign$$.regress"
      mkdir -p "$_dforeign"
      _dleaked="$(_dnewdirs "$_dpre")"
      rmdir "$_dforeign" 2>/dev/null
      _dnew="$(printf '%s\n' "$_dleaked" | grep -c . || true)"
      if ((_dnew == 0)); then
        pass "atuin autostart: a completed run leaves no NEW sandbox behind, daemon stopped first — and a concurrent run's sandbox in shared /tmp is not mistaken for one"
      else
        fail "atuin autostart: a completed run leaked $_dnew new sandbox dir(s) under /tmp: $(printf '%s' "$_dleaked" | tr '\n' ' ')"
      fi
    fi

    # 17b. THE OTHER HALF OF 17, and the reason narrowing the glob is safe rather than merely
    #      quiet. A check that ignores a foreign tree and a check that ignores EVERY tree look
    #      identical from a green run, and 17 alone cannot tell them apart — its expected
    #      result is zero either way. So the discrimination is asserted directly, with no
    #      verifier involved: plant one sandbox under a foreign tag and one under ours, and
    #      require the delta to name OURS and only ours. A single string compare carries both
    #      directions — a wrong count or a wrong path fails it.
    _dpre="$(_dsnap)"
    _dforeign="/tmp/atverify.foreign$$.control"
    _dmine="/tmp/atverify.$_DTAG.leak$$"
    mkdir -p "$_dforeign" "$_dmine"
    _dleaked="$(_dnewdirs "$_dpre")"
    rmdir "$_dforeign" "$_dmine" 2>/dev/null
    if [[ "$_dleaked" == "$_dmine" ]]; then
      pass "atuin autostart: the leak check still SEES a genuine leak under this run's tag while ignoring a foreign one — narrowing the glob did not make it blind"
    else
      fail "atuin autostart: the leak check must report exactly $_dmine as new and nothing else, got '$(printf '%s' "$_dleaked" | tr '\n' ' ')' — it is either blind to a real leak or still counting foreign sandboxes"
    fi

    # 18. A MALFORMED ANCHOR IS NOT AN ABSENT ONE. Absence is legitimate for THIS premise —
    #     nobody has written the line until a human measures it — which is exactly why the two
    #     must not be conflated: `=18.19`, or a valid value with a trailing token, would
    #     otherwise sail through as `unanchored` and the run would report a verdict against
    #     nothing. Cheap to assert: read_anchor runs before the sandbox is built, so no daemon
    #     is spawned on this path.
    _dvrepo="$(mktemp -d "$SANDBOX/dvrepo.XXXXXX")"
    mkdir -p "$_dvrepo/zsh" "$_dvrepo/scripts/lib" "$_dvrepo/lib" "$_dvrepo/atuin"
    cp "$_DVERIFY" "$_dvrepo/scripts/"
    cp "$HERE/scripts/lib/common.sh" "$HERE/scripts/lib/atuin-db.sh" "$_dvrepo/scripts/lib/"
    cp "$HERE/lib/ux.sh" "$_dvrepo/lib/" 2>/dev/null || true
    cp "$HERE/atuin/config.toml" "$_dvrepo/atuin/"
    _dbad=0
    for _dcase in "18.19" "18.19.0 EXTRA"; do
      {
        echo "# CORE_ATUIN_GUARD_VERIFIED_AGAINST=18.19.0"
        echo "# CORE_ATUIN_AUTOSTART_VERIFIED_AGAINST=$_dcase"
      } >"$_dvrepo/zsh/00-tools.zsh"
      _dout="$(cd "$_dvrepo" && CORE_COLOR=never "./scripts/verify-atuin-guard.sh" \
        --premise autostart --atuin "$_dstub/atuin-heals" --json 2>/dev/null)"
      [[ "$(_d_get "$_dout" verdict)" == unmeasurable ]] || _dbad=1
    done
    # Absence, by contrast, must still be allowed through as unanchored.
    echo "# CORE_ATUIN_GUARD_VERIFIED_AGAINST=18.19.0" >"$_dvrepo/zsh/00-tools.zsh"
    _dout="$(cd "$_dvrepo" && CORE_COLOR=never CORE_ATVERIFY_POLL=3 "./scripts/verify-atuin-guard.sh" \
      --premise autostart --atuin "$_dstub/atuin-heals" --json 2>/dev/null)"
    [[ "$(_d_get "$_dout" anchor_relation)" == unanchored ]] || _dbad=1
    _dreap
    if ((_dbad == 0)); then
      pass "atuin autostart: a malformed anchor is unmeasurable while an ABSENT one is still unanchored — the two are not conflated"
    else
      fail "atuin autostart: a malformed autostart anchor was treated as absent, so the run reported a verdict against nothing"
    fi

    # 19. THE LIBC MARKER MUST SURVIVE musl's EXIT STATUS. musl's ldd prints its banner and
    #     then exits NON-ZERO, and this script runs under `set -o pipefail` — so the obvious
    #     `ldd --version | grep -qi musl` is false even when grep matched, and every musl run
    #     loses the one marker that says which half of the fleet it spoke for. This repo has
    #     already paid for that exact mistake once (see CHANGELOG and bench-atuin-daemon.sh),
    #     which is why it is pinned here rather than left to a comment.
    _dshim="$(mktemp -d "$SANDBOX/dshim.XXXXXX")"
    for _dt in bash sh python3 sed grep awk tr cut head sleep mktemp rm cat kill ls chmod mkdir printf env find sort wc dirname basename readlink cp comm; do
      _dp="$(command -v "$_dt" 2>/dev/null)" && ln -sf "$_dp" "$_dshim/$_dt" 2>/dev/null
    done
    printf '#!/bin/sh\necho "musl libc (x86_64)" >&2\nexit 1\n' >"$_dshim/ldd"
    printf '#!/bin/sh\ncase "$1" in -m) echo x86_64 ;; *) echo Linux ;; esac\n' >"$_dshim/uname"
    chmod +x "$_dshim/ldd" "$_dshim/uname"
    _dout="$(PATH="$_dshim" CORE_COLOR=never "$_DVERIFY" --unmeasurable probe --json 2>/dev/null)"
    if [[ "$(_d_get "$_dout" host)" == *musl* ]]; then
      pass "atuin autostart: musl is detected even though its ldd exits non-zero (the pipefail trap this repo has hit before)"
    else
      fail "atuin autostart: a musl host reported host='$(_d_get "$_dout" host)' — the libc marker was lost to pipefail"
    fi

    # 20. Report coherence, §J3 case 7's counterpart with this premise's claims. The scope
      #   paragraph must NOT still say the autostart premise is unmeasured — that sentence was
      #   true until this mode existed and is exactly the kind of prose that rots — and must
      #   name the machines a green run here does and does not speak for.
    _drep="$SANDBOX/atverify-auto.md"
    _d_run atuin-heals --premise autostart --report "$_drep" --json
    _dreap
    if [[ -s "$_drep" ]] && printf '%s' "$_dout" | python3 -c '
import json,re,sys
d = json.load(sys.stdin)
rep = open(sys.argv[1]).read()
arms = set(d["arms"])
m = re.search(r"^\*\*Measured here:\*\* (.+)\.$", rep, re.M)
assert m, "no derived coverage sentence"
claimed = {a.strip().replace(" / ", "_") for a in m.group(1).split(",")}
assert claimed == arms, sorted(claimed ^ arms)
assert "premise: `autostart`" in rep, "the report does not say which premise it measured"
scope = rep.split("---\n\n", 1)[1]
# The claim this whole section retires. If it survives here, the report is telling a reader
# that nothing measures the thing the report is a measurement of.
assert "stand-down** is unmeasured" not in scope, "the autostart report still claims the premise is unmeasured"
for want in ("musl", "macOS", "3382", "--premise discard"):
    assert want in scope, want
# The teardown residual must be described as what it IS. An earlier version of this note
# claimed the run "preserves its sandbox rather than deleting one it could not account for"
# for a case NOTHING DETECTS — every check passes, the stop is accepted, and the tree is
# deleted around a live child. A scope note that promises a safety behaviour the code does not
# perform is the exact defect this section exists to catch, so the honest wording is pinned.
assert "undetected leak" in scope, "the scope note no longer names the teardown residual as undetected"
assert "preserving its sandbox rather than deleting" not in scope, "the scope note has re-acquired the preservation claim for a case nothing detects"
named = [a for a in arms if a.replace("_", " / ") in scope]
assert not named, "the scope section names measured arms: %s" % named
' "$_drep" 2>/dev/null; then
      pass "atuin autostart: --report names this premise, matches the arms that ran, and no longer calls autostart unmeasured"
    else
      fail "atuin autostart: the autostart report's prose does not match what it measured"
    fi
    fi  # known-good stub held
  fi    # apparatus probe
  _dreap
fi

# ── --json output contract (self-run) ─────────────────────────────────────────
# ── --json IS A CONTRACT: stdout carries ONE parseable object and nothing else ─
# The mode exists for CI steps and editor integrations that PARSE rather than scrape, so
# every guarantee it makes is machine-facing: a single JSON object on stdout, and a
# `result` that agrees with the same run without --json. Three separate bugs have broken
# one half or the other, each found by hand on a green tree (#508, #524, #511), and each
# time the suite went on certifying itself because no test ever ran --json.
#
# Two failure shapes this catches that nothing else does:
#   1. a fixture leaking to STDOUT — the last one was a no-op `git commit` printing
#      "nothing to commit, working tree clean", which made the object unparseable while
#      every assertion still passed;
#   2. an inherited CORE_JSON silencing a child gate's skip() lines, which flips assertions
#      that grep for them and reports a failing result on a healthy tree.
#
# Runs the suite against ITSELF at --scope none (the cheapest scope, a few seconds).
# CORE_TEST_SELFJSON=1 in the child is what stops the recursion, and the guard is on the
# PARENT so a nested run simply skips this section rather than re-entering it.
#
# Placed ABOVE the zsh-gated block below, not at the end of the file, because that block
# ends in `summary; exit` on a box where zsh is absent or shell scope is off — so anything
# after it is unreachable for exactly the `--scope none` invocation this gate is about.
if [[ "${CORE_TEST_SELFJSON:-0}" == 1 ]]; then
  : # nested self-run: this section is what invoked us
else
  hdr "--json output contract (self-run, hermetic)"
  # -u CORE_TEST_NESTED is this section obeying its own rule. audit-core.sh sets it so the
  # audit owns the summary and we print none — and the child would INHERIT it and print
  # nothing at all, so under `make audit` the gate saw 0 lines and failed for a reason that
  # had nothing to do with the contract. Exactly the shape #508/#524/#511 each took: a
  # fixture asserting on output while a variable that governs how that output is produced
  # leaks in from the parent.
  _sj_out="$(env -u CORE_TEST_NESTED CORE_TEST_SELFJSON=1 bash "$HERE/scripts/test-core.sh" --scope none --json 2>/dev/null)"
  _sj_lines="$(printf '%s\n' "$_sj_out" | grep -c . || true)"
  if [[ "$_sj_lines" == 1 ]]; then
    pass "--json: stdout is exactly one line (no fixture leaked onto it)"
  else
    fail "--json: stdout carried $_sj_lines lines, want 1 — something printed alongside the object:
$(printf '%s\n' "$_sj_out" | grep -v '^{' | head -5)"
  fi
  # Parse it for real rather than grepping: a truncated or interleaved object can still
  # contain the substring `"result":"ok"`, and a consumer would choke where a grep would not.
  if _sj_result="$(printf '%s' "$_sj_out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"])' 2>/dev/null)"; then
    pass "--json: stdout parses as JSON and exposes .result"
  else
    _sj_result=""
    if have python3; then
      fail "--json: stdout is not parseable JSON"
    else
      skip "--json parse (python3 not installed)"
    fi
  fi
  # THE property #511 was filed about: --json must not change the VERDICT. Compared against
  # the same scope without it, so a disagreement means the mode itself moved the result.
  if [[ -n "$_sj_result" ]]; then
    if env -u CORE_TEST_NESTED CORE_TEST_SELFJSON=1 bash "$HERE/scripts/test-core.sh" --scope none --quiet --color never >/dev/null 2>&1; then
      _sj_plain=ok
    else
      _sj_plain=failed
    fi
    if [[ "$_sj_result" == "$_sj_plain" ]]; then
      pass "--json: the verdict matches the identical run without --json (#511)"
    else
      fail "--json: reported '$_sj_result' where the same scope without --json reported '$_sj_plain' — the mode changed the result"
    fi
  fi
  unset _sj_out _sj_lines _sj_result _sj_plain
fi

# ── C9. os.capabilities schema validator (scripts/check-capabilities.sh) ─────
# The strict half of #663. The reader (band 02) is asserted in section A4, which is
# zsh-gated; this is NOT, and deliberately sits ABOVE that gate so it runs on every box
# — a bare container, a docs-scoped CI leg — where the reader itself cannot be exercised.
#
# It was written below the gate first, and never ran here at all: `have zsh` guards an
# early `exit 0`, so a bash assertion placed after it is silently absent rather than
# skipped. That is the green-because-absent result, and it is worth a comment because the
# file gives no other hint that its second half is conditional.
hdr "os.capabilities schema validator"
CAPCHK="$HERE/scripts/check-capabilities.sh"
CAPEX="$HERE/examples/os.capabilities.example"
if [[ ! -x "$CAPCHK" || ! -r "$CAPEX" ]]; then
  fail "check-capabilities.sh or the example declaration is missing"
else
  CAPV="$SANDBOX/capval"
  mkdir -p "$CAPV"
  # _cap_rejects <label> <sed-or-append expression applied to the example>
  _cap_rejects() { # <label> <file>
    if "$CAPCHK" "$2" >/dev/null 2>&1; then
      fail "validator: accepted $1 (it must not)"
    else
      pass "validator: rejects $1"
    fi
  }
  if "$CAPCHK" "$CAPEX" >/dev/null 2>&1; then
    pass "validator: the shipped example passes its own schema"
  else
    fail "validator: examples/os.capabilities.example does NOT satisfy the schema it documents"
  fi
  # An unknown key is the case that matters most: the reader ignores it in silence, so the
  # validator is the ONLY thing standing between a typo and a capability nothing dispatches.
  { cat "$CAPEX"; printf 'CLIPBOARD=wl-copy\n'; } >"$CAPV/unknown"
  _cap_rejects "an unknown key" "$CAPV/unknown"
  grep -v '^PKG_OWNS=' "$CAPEX" >"$CAPV/missing"
  _cap_rejects "a missing required key" "$CAPV/missing"
  sed 's/^PKG_SEARCH=.*/PKG_SEARCH=/' "$CAPEX" >"$CAPV/blank"
  _cap_rejects "a required key declared empty" "$CAPV/blank"
  sed 's/^SCHEDULER=.*/SCHEDULER=cron/' "$CAPEX" >"$CAPV/sched"
  _cap_rejects "a SCHEDULER outside the enum" "$CAPV/sched"
  { cat "$CAPEX"; printf 'PKG_SEARCH=dnf search\n'; } >"$CAPV/dupe"
  _cap_rejects "a duplicate key" "$CAPV/dupe"
  { cat "$CAPEX"; printf 'this is not an assignment\n'; } >"$CAPV/junk"
  _cap_rejects "a line that is not KEY=value" "$CAPV/junk"
  # Trailing whitespace: the reader TRIMS it, so a value carrying it would validate one way
  # and behave another. Rejecting it keeps the two halves of #663 telling the same story.
  { grep -v '^PKG_REMOVE=' "$CAPEX"; printf 'PKG_REMOVE=sudo dnf remove -y \n'; } >"$CAPV/ws"
  _cap_rejects "a value with trailing whitespace" "$CAPV/ws"
  _cap_rejects "an unreadable file" "$CAPV/nope-does-not-exist"
  # `none` is a REAL scheduler answer (a container, a box with neither init), not a
  # placeholder — asserting it keeps someone from "tightening" the enum to systemd|launchd.
  sed 's/^SCHEDULER=.*/SCHEDULER=none/' "$CAPEX" >"$CAPV/sched-none"
  if "$CAPCHK" "$CAPV/sched-none" >/dev/null 2>&1; then
    pass "validator: SCHEDULER=none is accepted (containers, boxes with neither init)"
  else
    fail "validator: SCHEDULER=none was rejected — it is a real answer, not a placeholder"
  fi
  # TOOLS_OPTIN is OPTIONAL: absent means "Core's built-in default applies".
  grep -v '^TOOLS_OPTIN=' "$CAPEX" >"$CAPV/no-optin"
  if "$CAPCHK" "$CAPV/no-optin" >/dev/null 2>&1; then
    pass "validator: TOOLS_OPTIN is optional (absent ⇒ Core's default)"
  else
    fail "validator: TOOLS_OPTIN was treated as required — it is not"
  fi
  # An inline `#` is NOT a comment inside a value (#715). This file looks like an env file
  # and its own header is dense with `#`, so this is the natural thing to author — and every
  # other rule waved it through, leaving the declared verb as the whole string, comment and
  # all, for a shell to run.
  { grep -v '^PKG_OWNS=' "$CAPEX"; printf 'PKG_OWNS=dnf provides   # which package owns this\n'; } >"$CAPV/inline-hash"
  _cap_rejects "an inline '#' inside a value" "$CAPV/inline-hash"
  # ...while a genuinely indented COMMENT must still be skipped. These two travel together:
  # the comment arm used to be spelled `[[:space:]]*'#'*`, a glob that matches one space then
  # anything then '#', which conflated the two cases in both directions.
  { cat "$CAPEX"; printf '   # an indented comment, itself containing a # character\n'; } >"$CAPV/indented-comment"
  if "$CAPCHK" "$CAPV/indented-comment" >/dev/null 2>&1; then
    pass "validator: an indented comment is still skipped"
  else
    fail "validator: rejected an indented comment — the comment arm is too strict"
  fi
  # A dangling `--packages` used to spin forever: `shift 2` with one positional left returns
  # non-zero AND does not shift, so `|| true` produced an infinite loop. Nine OS repos call
  # this from `make lint`, where that is a job burning to the runner timeout. `timeout` is
  # the assertion here — without it a regression HANGS THE SUITE instead of failing it.
  if have timeout; then
    timeout 10 "$CAPCHK" "$CAPEX" --packages >/dev/null 2>&1
    _cap_dangle_rc=$?
    if [[ "$_cap_dangle_rc" -eq 2 ]]; then
      pass "validator: a dangling --packages exits 2 (does not loop forever)"
    elif [[ "$_cap_dangle_rc" -eq 124 ]]; then
      fail "validator: a dangling --packages HUNG — the arity guard on shift 2 is gone (#715)"
    else
      fail "validator: a dangling --packages should exit 2, got $_cap_dangle_rc"
    fi
  else
    skip "validator: dangling --packages (no timeout(1) to bound a possible hang)"
  fi
fi

# ── zsh-gated sections (A load-order, B function units) ───────────────────────
# Everything below needs a real zsh. On a bare box we SKIP it (not fail) and fall
# through to the shared summary, so a Section-C failure still surfaces as exit 1.
if ! ((SCOPE_SHELL)) || ! have zsh; then
  hdr "zsh behavioral sections (load-order + function units)"
  if ! ((SCOPE_SHELL)); then
    skip "zsh behavioral sections (out of scope)"
  else
    skip "load-order smoke + function units (zsh not installed — runs in CI)"
  fi
  summary
  ((FAIL == 0)) || {
    { [[ "$NESTED" == 1 ]] || ((JSON)); } || printf '%stests FAILED%s\n' "$c_red" "$c_rst" >&2
    exit 1
  }
  { [[ "$NESTED" == 1 ]] || ((JSON)); } || printf '%stests OK%s\n' "$c_grn" "$c_rst"
  exit 0
fi

# ── A. load-order smoke test (drives the v4 numbered-fragment loader) ─────────
hdr "load-order smoke test (v4 numbered-fragment loader)"
# v4: an OS .zshrc sets ZSH_CFG + CORE_PROFILE and sources the vendored loader, which
# globs the numbered fragments (NN-*.zsh) in ZSH_CFG, sorts by NN, and sources each. We
# build a sandbox ZSH_CFG of SYMLINKS to the repo's Core fragments + the loader, then
# drive it exactly as a host would — exercising the REAL glob/sort/profile path, not a
# hand-rolled source loop. The .zwc land beside the symlinks in the sandbox, never the repo.
ZDOT="$SANDBOX/zdot"
mkdir -p "$ZDOT"
ln -s "$HERE/zsh/loader.zsh" "$ZDOT/loader.zsh"
core_frags=("$HERE"/zsh/[0-9][0-9]-*.zsh)
for f in "${core_frags[@]}"; do ln -s "$f" "$ZDOT/$(basename "$f")"; done

# Pre-seed empty plugin dirs at the v4 location ($XDG_DATA_HOME/zsh/plugins) so
# 45-plugins.zsh's first-run clone is a hermetic no-op (no network). The dir list lives
# once in common.sh (_seed_plugin_dirs), shared with the integration + bench.
_seed_plugin_dirs "$SANDBOX/data/zsh/plugins"

# Generate the sandbox .zshrc the v4 way: set ZSH_CFG + CORE_PROFILE, source the loader,
# print a sentinel. We deliberately do NOT key success on each fragment's exit code — a
# fragment whose LAST statement is a false guard (e.g. 20-aliases.zsh ends on
# `[[ -n $HAVE_GPING ]] && alias ping=gping`, false on a bare box) returns non-zero while
# having loaded perfectly. The real signal of a broken load-order contract is a RUNTIME
# error on stderr (a fragment using a fn/widget/var an EARLIER one must define first) — so
# we assert: the chain REACHED THE END (sentinel) with CLEAN stderr. Parse errors are
# already caught per-file by audit-core.sh's `zsh -n`.
{
  printf 'ZSH_CFG=%q\n' "$ZDOT"
  printf 'CORE_PROFILE=full\n'
  printf 'source "$ZSH_CFG/loader.zsh"\n'
  printf 'print -r -- "SMOKE_OK"\n'
} >"$ZDOT/.zshrc"

# Run one interactive zsh against the sandbox rc. We do NOT rely on zsh auto-sourcing
# $ZDOTDIR/.zshrc: a global /etc/zshenv can force ZDOTDIR (overriding the env we pass), and
# auto-load doesn't fire when stdout is captured (non-TTY). So -f disables rc auto-load, we
# set ZDOTDIR INSIDE -c (after /etc/zshenv ran) and `source` the rc explicitly; -i keeps the
# fragments' `[[ $- == *i* ]]` guards live. MISE_TRUSTED_CONFIG_PATHS pre-trusts the vendored
# mise config so `mise activate` doesn't abort under the sandbox HOME.
smoke_out="$(
  HOME="$SANDBOX" \
    XDG_CACHE_HOME="$SANDBOX/cache" XDG_STATE_HOME="$SANDBOX/state" \
    XDG_DATA_HOME="$SANDBOX/data" \
    XDG_RUNTIME_DIR="$SANDBOX/run" MISE_TRUSTED_CONFIG_PATHS="$HERE" \
    zsh -f -i -c "ZDOTDIR='$ZDOT'; source \"\$ZDOTDIR/.zshrc\"" 2>"$SANDBOX/smoke.err"
)"
# High-signal zsh runtime-error markers — what a real load-order break looks like.
smoke_errs="$(grep -Ei \
  'command not found|parse error|: no such file or directory|not defined|bad pattern|bad math expression|maximum nested' \
  "$SANDBOX/smoke.err" 2>/dev/null || true)"
if ! grep -q '^SMOKE_OK$' <<<"$smoke_out"; then
  fail "load-order chain did not reach the end (no SMOKE_OK sentinel — a fragment aborted)"
  [[ -s "$SANDBOX/smoke.err" ]] && sed 's/^/    /' "$SANDBOX/smoke.err" >&2
elif [[ -n "$smoke_errs" ]]; then
  fail "runtime errors during canonical load (load-order contract broken):"
  printf '%s\n' "$smoke_errs" | sed 's/^/    /' >&2
else
  pass "all ${#core_frags[@]} fragments loaded in NN order via the loader (clean stderr)"
fi

# ── A2. consumer integration (Core + 80-os + 99-local via the loader) ─────────
# Core NEVER loads alone in production: a host also carries the OS layer (80-os.zsh) and
# any machine overrides (99-local.zsh), both globbed by the loader from ZSH_CFG (bands
# >=70 always load, independent of CORE_PROFILE). Section A proves Core-in-isolation;
# this proves the documented CONSUMPTION — the Core→OS CONTRACT at the real fan-out shape.
# The 80-os stub uses exactly what an OS layer relies on Core to have left defined:
# _cache_eval (00-tools's API — NOT unfunctioned like _have is), _core_is_wsl (the second
# such API, added in #449 so six OS layers could stop re-deriving the same probe), the
# _core_* UX primitives (05-ui), and an alias override (the macOS rm→trash pattern).
# 99-local overrides a Core default. If Core ever stops exporting one of those, this fails
# — where Section A, loading Core alone, would stay green.
#
# IT ALSO PROVES WHAT BAND 80 USED TO PROVE AND NO LONGER CAN. The direnv/gh/uv/ty inits
# moved into Core in #449, so the generate→cache→source path for the four tools the whole
# fleet installs is now Core's own code on the real loader — see the stub generators below.
hdr "consumer integration (Core + 80-os + 99-local, v4 loader)"
INTEG="$SANDBOX/integ"
mkdir -p "$INTEG"
ln -s "$HERE/zsh/loader.zsh" "$INTEG/loader.zsh"
for f in "${core_frags[@]}"; do ln -s "$f" "$INTEG/$(basename "$f")"; done
_seed_plugin_dirs "$SANDBOX/integ-data/zsh/plugins"
# 80-os.zsh: realistic OS-layer fragment. Exercises the Core helpers an OS repo depends
# on; any reference to an undefined helper prints to stderr (the failure signal below).
# Stub generators for the four tools Core now hooks itself (#449). A real box has some
# subset of these installed; the sandbox has none, so without stubs the helpers bail on
# ${commands[…]} and all four lines are silent no-ops that could rot unnoticed. (Side effect
# worth naming so nobody chases it: the `uv` stub sets HAVE_UV, so 20-aliases.zsh defines
# uvr/uvs. Harmless here.)
#
# TWO SHAPES, because the two mechanisms have different observable end states (#579):
#   direnv is still SOURCED, so its generated init is a sentinel print and the sentinel
#   reaching stdout proves generate→cache→source ran, at band 00, under the real loader.
#   gh/uv/ty are no longer sourced at all — they are written into an fpath dir and autoloaded
#   — so a sentinel print would prove nothing and never appear. Their stubs emit a REAL
#   clap_complete-shaped script (`#compdef` header + the autoload shim), and the assertion
#   below reads $_comps instead. That is the stronger claim anyway: it checks the completion
#   is REGISTERED for the command in a live shell, which is the user-facing fact, and it
#   survives a future change of mechanism without needing to be rewritten again.
INTEGBIN="$SANDBOX/integ-bin"
mkdir -p "$INTEGBIN"
printf '#!/bin/sh\nprintf "%%s\\n" "print -r -- CORE_INIT_DIRENV"\n' >"$INTEGBIN/direnv"
for _it in gh uv ty; do
  printf '#!/bin/sh\ncat <<STUB\n#compdef %s\n_%s() { _message CORE_INIT_%s }\nif [ "\$funcstack[1]" = "_%s" ]; then\n  _%s "\$@"\nelse\n  compdef _%s %s\nfi\nSTUB\n' \
    "$_it" "$_it" "$(printf '%s' "$_it" | tr '[:lower:]' '[:upper:]')" "$_it" "$_it" "$_it" "$_it" >"$INTEGBIN/$_it"
done
for _it in direnv gh uv ty; do chmod +x "$INTEGBIN/$_it"; done
unset _it
cat >"$INTEG/80-os.zsh" <<'OSZSH'
# stub 80-os.zsh — must be able to use the API Core promises the OS layer.
(( $+functions[_cache_eval] )) || print -u2 "80-os.zsh: _cache_eval missing (00-tools API gone)"
(( $+functions[_core_ok]    )) || print -u2 "80-os.zsh: _core_ok missing (05-ui API gone)"
(( $+functions[_core_is_wsl] )) || print -u2 "80-os.zsh: _core_is_wsl missing (00-tools API gone)"
# The shape all six WSL-carrying OS layers adopt in place of their deleted probe (#449).
# The answer does not matter here; that the call works from band 80 does.
if _core_is_wsl; then alias winopen='explorer.exe'; fi
# the documented gh/uv/ty pattern: _cache_eval a tool AFTER 10-options.zsh set NO_CLOBBER.
# The generator must emit SOURCEABLE zsh (real tools emit an init script); a comment is
# a valid no-op init and proves the generate→cache→source path works under NO_CLOBBER.
_cache_eval faketool printf '# faketool cached init (integration stub)\n' >/dev/null
alias rm='rm -i'   # OS layer overriding a safety net (macOS does rm→trash here)
OSZSH
# 99-local.zsh: machine-specific overrides (identity/toggles). Overriding a Core default
# is the whole reason it loads LAST (band 99).
cat >"$INTEG/99-local.zsh" <<'LOCALZSH'
# stub 99-local.zsh — last word on this machine.
UPDATE_CHECK_ENABLED=0
LOCALZSH
{
  printf 'ZSH_CFG=%q\n' "$INTEG"
  printf 'CORE_PROFILE=full\n'
  printf 'source "$ZSH_CFG/loader.zsh"\n'
  # Report the COMPLETION REGISTRATION for the three that are no longer sourced (#579).
  printf 'for _t in gh uv ty; do print -r -- "CORE_COMP_${(U)_t}=${_comps[$_t]:-NONE}"; done\n'
  printf 'print -r -- "INTEG_OK"\n'
} >"$INTEG/.zshrc"
integ_out="$(
  HOME="$SANDBOX" \
    XDG_CACHE_HOME="$SANDBOX/integ-cache" XDG_STATE_HOME="$SANDBOX/integ-state" \
    XDG_DATA_HOME="$SANDBOX/integ-data" \
    XDG_RUNTIME_DIR="$SANDBOX/run" MISE_TRUSTED_CONFIG_PATHS="$HERE" \
    PATH="$INTEGBIN:$PATH" \
    zsh -f -i -c "ZDOTDIR='$INTEG'; source \"\$ZDOTDIR/.zshrc\"" 2>"$INTEG/integ.err"
)"
integ_errs="$(grep -Ei \
  'command not found|parse error|: no such file or directory|not defined|missing|bad pattern|bad math expression|maximum nested' \
  "$INTEG/integ.err" 2>/dev/null || true)"
if ! grep -q '^INTEG_OK$' <<<"$integ_out"; then
  fail "consumer load (Core+80-os+99-local) did not reach the end — a layer aborted"
  [[ -s "$INTEG/integ.err" ]] && sed 's/^/    /' "$INTEG/integ.err" >&2
elif [[ -n "$integ_errs" ]]; then
  fail "errors during consumer load (Core→OS contract broken):"
  printf '%s\n' "$integ_errs" | sed 's/^/    /' >&2
else
  pass "Core + 80-os + 99-local loaded via the loader (Core→OS contract holds)"
fi

# The four tool inits Core took over from the OS layers in #449. Asserted individually
# rather than as a set: when this breaks it is nearly always ONE tool (a renamed generator
# subcommand, a line moved across a band boundary), and a combined check would only say
# "something".
#
# direnv is SOURCED, so the sentinel its stub prints must reach stdout.
if grep -q '^CORE_INIT_DIRENV$' <<<"$integ_out"; then
  pass "consumer load: Core sourced the DIRENV init (was the OS layer's job until #449)"
else
  fail "consumer load: Core never sourced the DIRENV init — the block is not reaching a real shell"
fi
# gh/uv/ty are NOT sourced (#579) — they are generated into an fpath dir at band 00 and
# autoloaded by compinit at band 10. So assert the end state that actually matters: the
# command is REGISTERED to the tool's own completion function, in a real shell, under the
# real loader and the real band order. This also pins the carapace-precedence half — the
# band-45 re-assert runs after carapace in this load, so a regression that let the bridge
# win would show up here as the wrong function name, not merely as an absent one.
for _it in GH UV TY; do
  _it_lc="$(printf '%s' "$_it" | tr '[:upper:]' '[:lower:]')"
  if grep -q "^CORE_COMP_$_it=_$_it_lc\$" <<<"$integ_out"; then
    pass "consumer load: the $_it completion is registered from fpath (_comps[$_it_lc] = _$_it_lc)"
  else
    fail "consumer load: the $_it completion never registered — got '$(grep -o "^CORE_COMP_$_it=.*" <<<"$integ_out")'"
  fi
done
unset _it _it_lc

# ── A2b. _cache_eval convergence (#580) ──────────────────────────────────────
# _cache_eval decides "is this cache usable?" on `-s` alone, and it writes the generator's
# output straight at the destination. Both halves were wrong, and both failed SILENTLY —
# `2>/dev/null` is deliberate there (a generator's chatter must never be sourced), so a
# broken generator leaves nothing behind but the file itself.
#
# These fixtures drive the REAL _cache_eval, extracted from 00-tools.zsh by its own
# function header, against stub generators — the same "parse the shipped source, do not
# re-spell it" discipline the probe-coverage guards below use. Extracting rather than
# sourcing the whole file is deliberate: band 00 activates mise/atuin/starship against the
# host, which is neither hermetic nor fast.
#
# Each case runs the SAME shell twice. One run cannot tell "regenerated once" from
# "regenerates forever" — and forever is the actual defect.
hdr "_cache_eval convergence (#580)"
CEV="$SANDBOX/cache-eval"
mkdir -p "$CEV/bin"

# exits 0, prints nothing — a renamed/removed generator subcommand, the observed trigger.
printf '#!/bin/sh\nexit 0\n' >"$CEV/bin/ce-empty"
# prints a PARTIAL script, then fails — truncated init, the case that never self-heals.
printf '#!/bin/sh\nprintf %%s "alias ce=true\\nif [ "\nexit 1\n' >"$CEV/bin/ce-partial"
# prints nothing and fails — exit status alone would catch this one; -s alone would not.
printf '#!/bin/sh\nexit 3\n' >"$CEV/bin/ce-emptyfail"
# a healthy generator, to prove the fix does not break the path that always worked.
printf '#!/bin/sh\nprintf %%s "# ce good\\nalias cegood=true\\n"\n' >"$CEV/bin/ce-good"
chmod +x "$CEV/bin"/ce-*

# Run <tool> through _cache_eval N times in N separate shells; echo one line per run:
#   <size-in-bytes|MISSING> <would-regenerate-next: YES|no> <sourced-ok: ok|ERR>
_ce_runs() { # _ce_runs <tool> <count>
  local _i
  for _i in $(seq 1 "$2"); do
    XDG_CACHE_HOME="$CEV/cache" PATH="$CEV/bin:$PATH" HOME="$SANDBOX" \
      zsh -fc '
        setopt NO_CLOBBER   # 10-options.zsh sets this; the >| redirections depend on it
        eval "$(sed -n "/^_cache_eval() {/,/^}/p" "'"$HERE"'/zsh/00-tools.zsh")"
        _cache_eval '"$1"' '"$1"' && _ok=ok || _ok=ERR
        c="$XDG_CACHE_HOME/zsh/'"$1"'.zsh"
        if [[ -e "$c" ]]; then _sz=$(wc -c <"$c" | tr -d " "); else _sz=MISSING; fi
        printf "%s %s %s\n" "$_sz" "$([[ -s $c ]] && echo no || echo YES)" "$_ok"
      ' 2>/dev/null
  done
}

# 1. exits 0, prints nothing. Pre-fix: a 0-byte cache, so `-s` fails on EVERY later shell
#    and each one re-forks a generator that can never succeed — invisible, forever.
rm -rf "$CEV/cache"
_ce_out="$(_ce_runs ce-empty 2)"
if [[ -z "$(printf '%s\n' "$_ce_out" | awk '$2!="no"')" ]]; then
  pass "_cache_eval: a generator that exits 0 and prints nothing converges (no re-fork per shell)"
else
  fail "_cache_eval: empty-output generator never converges — every shell re-forks it"
  printf '%s\n' "$_ce_out" | sed 's/^/    /' >&2
fi

# 2. prints nothing AND fails. Same convergence requirement; separate case because a fix
#    that only checked $? would pass this and still leave case 1 broken.
rm -rf "$CEV/cache"
_ce_out="$(_ce_runs ce-emptyfail 2)"
if [[ -z "$(printf '%s\n' "$_ce_out" | awk '$2!="no"')" ]]; then
  pass "_cache_eval: a generator that prints nothing and exits non-zero converges"
else
  fail "_cache_eval: failing empty generator never converges"
  printf '%s\n' "$_ce_out" | sed 's/^/    /' >&2
fi

# 3. partial output then failure. `>|` truncates BEFORE the generator runs, so pre-fix the
#    cache held `alias ce=true\nif [ ` — non-empty AND newer than the binary, so BOTH halves
#    of the freshness test go false and that truncated init is sourced on every shell from
#    then on. Assert the fragment never lands, not merely that the run succeeded.
rm -rf "$CEV/cache"
_ce_runs ce-partial 2 >/dev/null
if [[ ! -f "$CEV/cache/zsh/ce-partial.zsh" ]] || ! grep -q 'if \[ *$' "$CEV/cache/zsh/ce-partial.zsh"; then
  pass "_cache_eval: a partially-written init is never installed (no truncated cache to source)"
else
  fail "_cache_eval: installed a TRUNCATED init — every later shell sources it"
  sed 's/^/    /' "$CEV/cache/zsh/ce-partial.zsh" >&2
fi

# 4. the last-good cache survives a generator that breaks later. Warm a good cache, then
#    swap the binary for a broken one and make it NEWER so the mtime half fires. Degrading
#    a working shell because a generator regressed is a strictly worse outcome than
#    serving yesterday's completions.
rm -rf "$CEV/cache"
printf '#!/bin/sh\nprintf %%s "# ce keep\\nalias cekeep=true\\n"\n' >"$CEV/bin/ce-keep"
chmod +x "$CEV/bin/ce-keep"
_ce_runs ce-keep 1 >/dev/null
printf '#!/bin/sh\nexit 0\n' >"$CEV/bin/ce-keep"
chmod +x "$CEV/bin/ce-keep"
touch "$CEV/bin/ce-keep"          # binary newer than cache -> the -nt half fires
_ce_out="$(_ce_runs ce-keep 2)"
if grep -q 'alias cekeep=true' "$CEV/cache/zsh/ce-keep.zsh" 2>/dev/null \
  && [[ -z "$(printf '%s\n' "$_ce_out" | awk '$2!="no"')" ]]; then
  pass "_cache_eval: keeps the last good cache when a generator breaks, and still converges"
else
  fail "_cache_eval: lost the last good cache (or kept re-forking) after a generator broke"
  printf '%s\n' "$_ce_out" | sed 's/^/    /' >&2
fi

# 5. the happy path still works — a fix that quarantined everything would pass 1-4.
rm -rf "$CEV/cache"
_ce_out="$(_ce_runs ce-good 2)"
if [[ -z "$(printf '%s\n' "$_ce_out" | awk '$2!="no" || $3!="ok"')" ]] \
  && grep -q 'alias cegood=true' "$CEV/cache/zsh/ce-good.zsh"; then
  pass "_cache_eval: a healthy generator still caches and sources its init"
else
  fail "_cache_eval: broke the working path"
  printf '%s\n' "$_ce_out" | sed 's/^/    /' >&2
fi
unset _ce_out

# ── _cache_completion: fpath autoload, not a source (#579) ────────────────────
# _cache_eval ends in `source`, which for uv means 6,976 lines read into EVERY interactive
# shell to serve a completion most shells never invoke — measured here at +35 ms per shell.
# _cache_completion writes the same generated text into an fpath directory instead. Same
# fixtures, same technique as the block above: extract the REAL function out of 00-tools.zsh
# and drive it across separate shells, so the code under test is the shipped code.
hdr "_cache_completion (fpath autoload)"
CCM="$SANDBOX/cachecomp"
rm -rf "$CCM"
mkdir -p "$CCM/bin"
# a healthy clap_complete-shaped generator: #compdef header + the autoload shim footer
printf '#!/bin/sh\nprintf %%s "#compdef cc-good\\n_cc-good() { _message ok }\\n"\n' >"$CCM/bin/cc-good"
# exits 0, prints nothing — the #580 shape, which must converge here too
printf '#!/bin/sh\nexit 0\n' >"$CCM/bin/cc-empty"
chmod +x "$CCM/bin"/cc-*

_cc_run() { # _cc_run <tool> → drives the real _cache_completion in a fresh shell
  XDG_CACHE_HOME="$CCM/cache" PATH="$CCM/bin:$PATH" HOME="$SANDBOX" \
    zsh -fc '
      setopt NO_CLOBBER   # 10-options.zsh sets this; the >| redirections depend on it
      eval "$(sed -n "/^_cache_completion() {/,/^}/p" "'"$HERE"'/zsh/00-tools.zsh")"
      _cache_completion '"$1"' '"$1"'
    ' 2>/dev/null
}

# 1. THE POINT OF THE CHANGE: it writes a file and sources NOTHING. A regression back to
#    `source` would still leave a working completion, so the only observable difference is
#    that the generator's output does not enter the calling shell.
rm -rf "$CCM/cache"
_cc_out="$(XDG_CACHE_HOME="$CCM/cache" PATH="$CCM/bin:$PATH" HOME="$SANDBOX" \
  zsh -fc '
    setopt NO_CLOBBER
    eval "$(sed -n "/^_cache_completion() {/,/^}/p" "'"$HERE"'/zsh/00-tools.zsh")"
    _cache_completion cc-good cc-good
    print -r -- "defined=${+functions[_cc-good]}"
  ' 2>/dev/null)"
if [[ -s "$CCM/cache/zsh/completions/_cc-good" ]] && [[ "$_cc_out" == "defined=0" ]]; then
  pass "_cache_completion: writes _<tool> into the fpath dir and sources nothing into the shell"
else
  fail "_cache_completion: did not write the fpath file, or leaked the completion into the shell ($_cc_out)"
fi

# 2. It lands in the CACHE dir, never in zsh/completions/ — that directory is Core's authored
#    set, listed per-file in core.manifest so an added file is a manifest failure.
if [[ ! -e "$HERE/zsh/completions/_cc-good" ]]; then
  pass "_cache_completion: generated files stay out of Core's authored zsh/completions/"
else
  fail "_cache_completion: wrote a generated completion into the manifest-checked authored dir"
fi

# 3. The compdump is invalidated on a regeneration. Without this the new file is INVISIBLE
#    for up to 24h: 10-options.zsh takes `compinit -C` when the dump is under a day old, and
#    -C skips the scan for new completion functions entirely.
rm -rf "$CCM/cache"
mkdir -p "$CCM/cache/zsh"
: >"$CCM/cache/zsh/zcompdump"
: >"$CCM/cache/zsh/zcompdump.zwc"
_cc_run cc-good
if [[ ! -e "$CCM/cache/zsh/zcompdump" && ! -e "$CCM/cache/zsh/zcompdump.zwc" ]]; then
  pass "_cache_completion: a regeneration invalidates the compdump (else compinit -C never sees the new file)"
else
  fail "_cache_completion: the stale compdump survived a regeneration — the completion would be invisible for 24h"
fi

# 4. …and a run that regenerates NOTHING must leave the dump alone, or every shell pays a
#    full compinit and the fast path is gone.
: >"$CCM/cache/zsh/zcompdump"
_cc_run cc-good
if [[ -e "$CCM/cache/zsh/zcompdump" ]]; then
  pass "_cache_completion: a no-op run leaves the compdump intact (the compinit -C fast path survives)"
else
  fail "_cache_completion: deleted the compdump when nothing was regenerated"
fi

# 5. An absent binary writes nothing and says nothing — the invariant that lets these callers
#    ship with no HAVE_* flag.
rm -rf "$CCM/cache"
_cc_out="$(_cc_run cc-absent-tool)"
if [[ -z "$_cc_out" && ! -d "$CCM/cache/zsh/completions" ]]; then
  pass "_cache_completion: an absent binary writes nothing and prints nothing (no HAVE_* flag needed)"
else
  fail "_cache_completion: an absent binary produced output or a cache dir ($_cc_out)"
fi

# 6. A generator that cannot succeed must CONVERGE, or every shell re-forks it forever
#    (#580). The marker is deliberately NOT an `_<tool>` stub: any file named _cc-empty in
#    fpath IS a completion function, so a stub would register an empty completion and shadow
#    whatever carapace would otherwise have bridged. Assert both halves.
rm -rf "$CCM/cache"
_cc_run cc-empty
_cc_run cc-empty
if [[ -e "$CCM/cache/zsh/completions/.cc-empty.failed" ]] &&
  [[ ! -e "$CCM/cache/zsh/completions/_cc-empty" ]]; then
  pass "_cache_completion: a failing generator converges on a dotfile marker, NOT an _<tool> stub that would shadow the bridged completion"
else
  fail "_cache_completion: failing generator did not converge, or wrote a stub into fpath"
fi

# 7. An upgrade re-opens the question: the binary's mtime is the only invalidation key.
rm -rf "$CCM/cache"
_cc_run cc-good
_cc_sz0="$(wc -c <"$CCM/cache/zsh/completions/_cc-good" | tr -d ' ')"
printf '#!/bin/sh\nprintf %%s "#compdef cc-good\\n_cc-good() { _message v2 }\\n# grown\\n"\n' >"$CCM/bin/cc-good"
chmod +x "$CCM/bin/cc-good"
touch "$CCM/bin/cc-good"
_cc_run cc-good
_cc_sz1="$(wc -c <"$CCM/cache/zsh/completions/_cc-good" | tr -d ' ')"
if [[ "$_cc_sz1" != "$_cc_sz0" ]]; then
  pass "_cache_completion: a newer binary regenerates the completion (mtime is the invalidation key)"
else
  fail "_cache_completion: an upgraded binary did not regenerate ($_cc_sz0 -> $_cc_sz1)"
fi
unset _cc_out _cc_sz0 _cc_sz1 CCM
unset -f _cc_run

# ── CI modernization floor: rules 2 and 7 (#521) ─────────────────────────────
# check-modern.sh had no behavioural coverage — every rule was "green on this tree",
# which cannot distinguish a rule that PASSES from a rule that never MATCHES. Rule 2 was
# in exactly that state: it had banned `ubuntu-22.04` since the floor was written and
# would have waved `ubuntu-22.04-arm` straight through.
#
# Hermetic: a throwaway git repo (the gate inventories through `git ls-files`, so a plain
# directory yields "no workflow/action files to check" and every assertion below would
# vacuously pass) holding only the script, its lib and a crafted workflow.
hdr "CI modernization floor (scripts/check-modern.sh rules 2, 3, 7 + 8)"
if ! have git; then
  skip "check-modern rule fixtures (git not installed)"
else
  CMF="$SANDBOX/check-modern"
  rm -rf "$CMF"
  mkdir -p "$CMF/scripts/lib" "$CMF/lib" "$CMF/.github/workflows"
  cp "$HERE/scripts/check-modern.sh" "$CMF/scripts/"
  cp "$HERE/scripts/modern-baseline.yml" "$CMF/scripts/"
  cp "$HERE/scripts/lib/common.sh" "$CMF/scripts/lib/"
  cp "$HERE/lib/ux.sh" "$CMF/lib/"
  git -C "$CMF" init -q 2>/dev/null
  git -C "$CMF" add -A 2>/dev/null

  # _cm_run <workflow-body> → the gate's stderr for that single workflow
  _cm_run() {
    printf '%s\n' "$1" >"$CMF/.github/workflows/probe.yml"
    git -C "$CMF" add -A 2>/dev/null
    # stdout (the one-line verdict) to /dev/null INSIDE the subshell, then the subshell's
    # stderr — where note() writes the violations — up to our stdout. Written this way
    # round rather than `2>&1 >/dev/null`, which does the same thing but reads as the
    # classic mistake.
    { ( cd "$CMF" && bash scripts/check-modern.sh >/dev/null ) || true; } 2>&1
  }

  # A clean baseline workflow: proves the fixture reaches the gate at all, so a later
  # "no violations" result means the rule passed rather than the harness misfiring.
  _cm_clean='name: p
on: [push]
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - run: echo hi'
  if [[ -z "$(_cm_run "$_cm_clean")" ]] \
    && ( cd "$CMF" && bash scripts/check-modern.sh 2>/dev/null | grep -q 'meets the modern baseline' ); then
    pass "check-modern fixture: a clean workflow reaches the gate and passes (harness is live)"
  else
    fail "check-modern fixture: harness misfire — a clean workflow did not reach the gate"
    _cm_run "$_cm_clean" | sed 's/^/    /' >&2
  fi

  # Rule 2: the variant suffixes. `ubuntu-22.04-arm` and `macos-14-xlarge` are named in the
  # SAME deprecation notices as their base labels, and both were slipping the ban.
  _cm_out="$(_cm_run 'name: p
on: [push]
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-22.04-arm
    timeout-minutes: 5
    steps:
      - run: echo hi
  b:
    runs-on: macos-14-xlarge
    timeout-minutes: 5
    steps:
      - run: echo hi
  c:
    runs-on: macos-14-large
    timeout-minutes: 5
    steps:
      - run: echo hi')"
  if [[ "$(grep -c 'EOL runner' <<<"$_cm_out")" == 3 ]]; then
    pass "check-modern rule 2: -arm / -large / -xlarge variants of a banned runner are caught"
  else
    fail "check-modern rule 2: variant-suffixed runners slipped the ban (want 3 hits)"
    printf '%s\n' "$_cm_out" | sed 's/^/    /' >&2
  fi

  # …and the base labels must still be caught (a suffix group that swallowed the plain
  # form would pass the test above while silently disabling the rule it extends).
  _cm_out="$(_cm_run 'name: p
on: [push]
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-22.04
    timeout-minutes: 5
    steps:
      - run: echo hi')"
  if grep -q 'EOL runner (ubuntu-22.04)' <<<"$_cm_out"; then
    pass "check-modern rule 2: the bare banned label is still caught (suffix group is optional)"
  else
    fail "check-modern rule 2: the suffix group broke the plain-label match"
    printf '%s\n' "$_cm_out" | sed 's/^/    /' >&2
  fi

  # A supported runner whose name merely CONTAINS a banned one must not fire.
  _cm_out="$(_cm_run 'name: p
on: [push]
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - run: echo hi')"
  if ! grep -q 'EOL runner' <<<"$_cm_out"; then
    pass "check-modern rule 2: a supported runner does not fire the ban"
  else
    fail "check-modern rule 2: false positive on a supported runner"
    printf '%s\n' "$_cm_out" | sed 's/^/    /' >&2
  fi

  # Rule 3's first-party exemption must be the POLICY's shape, not the whole owner. A bare
  # owner match let `uses: dotgibson/anything@main` through outright — wider than the @vN
  # policy it was named for, and asserted nowhere else, so the policy was documented in
  # RELEASE-STRATEGY.md and enforced by nothing.
  _cm_out="$(_cm_run 'name: p
on: [push]
permissions:
  contents: read
jobs:
  ok1:
    uses: dotgibson/dotfiles-core/.github/workflows/lint-call.yml@v4
  bad1:
    uses: dotgibson/dotfiles-core/.github/workflows/lint-call.yml@main
  bad2:
    uses: dotgibson/some-action@v1')"
  if [[ "$(grep -c 'outside the @vN reusable-workflow policy' <<<"$_cm_out")" == 2 ]] \
    && ! grep -q 'lint-call.yml@v4' <<<"$_cm_out"; then
    pass "check-modern rule 3: first-party @main and non-workflow refs are caught, @vN is not"
  else
    fail "check-modern rule 3: the owner exemption is still wider than the @vN policy"
    printf '%s\n' "$_cm_out" | sed 's/^/    /' >&2
  fi
  # A SHA-pinned first-party ref must also pass — the exemption is a shortcut, not the only
  # acceptable form, and a repo that chose to pin its caller must not be told off for it.
  _cm_out="$(_cm_run 'name: p
on: [push]
permissions:
  contents: read
jobs:
  ok:
    uses: dotgibson/dotfiles-core/.github/workflows/lint-call.yml@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')"
  if ! grep -qE 'unpinned action|@vN reusable-workflow policy' <<<"$_cm_out"; then
    pass "check-modern rule 3: a SHA-pinned first-party ref is still accepted"
  else
    fail "check-modern rule 3: SHA-pinned first-party ref was rejected"
    printf '%s\n' "$_cm_out" | sed 's/^/    /' >&2
  fi

  # Rule 7: a `${{ }}` expression is substituted by the runner, textually, BEFORE the
  # shell parses the script — so an attacker-controlled value there is code, not data.
  # Both the block-scalar and the one-line `run:` forms must be caught.
  _cm_out="$(_cm_run 'name: p
on: [push]
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: block scalar
        run: |
          echo "${{ github.event.pull_request.title }}"
      - name: one-line
        run: echo "${{ github.head_ref }}"')"
  if [[ "$(grep -c 'untrusted expression interpolated' <<<"$_cm_out")" == 2 ]]; then
    pass "check-modern rule 7: untrusted context spliced into a run: body is caught (block + inline)"
  else
    fail "check-modern rule 7: template injection into run: was not caught (want 2 hits)"
    printf '%s\n' "$_cm_out" | sed 's/^/    /' >&2
  fi

  # The three shapes that must NOT fire, asserted together because each is a live pattern
  # somewhere in the fleet and a false positive here is a red gate on every repo:
  #   - the same value routed through env: and read as $VAR (the prescribed remedy);
  #   - `inputs.*`, a first-party composite input (setup-core-tools/action.yml, ~8 steps);
  #   - a banned context in `if:` / `env:` / `concurrency:`, which are not shell.
  _cm_out="$(_cm_run 'name: p
on: [push]
permissions:
  contents: read
concurrency: ci-${{ github.head_ref }}
jobs:
  a:
    if: github.actor != "bot"
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: routed through env
        env:
          T: ${{ github.event.pull_request.title }}
        run: |
          echo "$T"
      - name: first-party composite input
        run: echo "${{ inputs.bindir }}"
      - name: dedent ends the block
        run: |
          echo safe
      - name: not a run body
        uses: ./.github/actions/x
        with:
          v: ${{ github.event.number }}')"
  if ! grep -q 'untrusted expression interpolated' <<<"$_cm_out"; then
    pass "check-modern rule 7: env:-routed, inputs.*, if:/concurrency: and with: do not fire"
  else
    fail "check-modern rule 7: false positive — this shape is the prescribed remedy"
    printf '%s\n' "$_cm_out" | sed 's/^/    /' >&2
  fi
  # Rule 8: a runner job with no timeout-minutes. GitHub's default is 360 minutes — six
  # hours of a held runner and a live GITHUB_TOKEN for a job that hung. `b` is the control
  # in the SAME fixture: a job that declares one must not be flagged, so a rule that simply
  # fired on every job would fail here rather than pass the negative case by luck.
  _cm_out="$(_cm_run 'name: p
on: [push]
permissions:
  contents: read
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
  b:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - run: echo hi')"
  if [[ "$(grep -c 'without timeout-minutes' <<<"$_cm_out")" == 1 ]] \
    && grep -q 'without timeout-minutes.*: a$' <<<"$_cm_out"; then
    pass "check-modern rule 8: a runner job with no timeout-minutes is caught (and only that one)"
  else
    fail "check-modern rule 8: want exactly one hit, naming job 'a'"
    printf '%s\n' "$_cm_out" | sed 's/^/    /' >&2
  fi

  # THE FALSE-FIRE THIS RULE IS SHAPED AROUND. A job that calls a reusable workflow (`uses:`
  # at job level) CANNOT legally carry timeout-minutes — GitHub rejects the workflow. Ten
  # jobs in this repo are exactly that shape, every one a notify-failure-call/notify-web-call.
  # Keying on `runs-on:` rather than "every job" is the whole reason the rule is written the
  # way it is, and this is the assertion that keeps it that way.
  _cm_out="$(_cm_run 'name: p
on: [push]
permissions:
  contents: read
jobs:
  call:
    uses: ./.github/workflows/other.yml
  local:
    uses: dotgibson/dotfiles-core/.github/workflows/lint-call.yml@v4')"
  if ! grep -q 'without timeout-minutes' <<<"$_cm_out"; then
    pass "check-modern rule 8: a reusable-workflow call job does not fire (it cannot carry one)"
  else
    fail "check-modern rule 8: false positive on a job that cannot legally set timeout-minutes"
    printf '%s\n' "$_cm_out" | sed 's/^/    /' >&2
  fi

  unset _cm_out _cm_clean
  unset -f _cm_run
fi

# ── A3. profile filtering (CORE_PROFILE ceilings + env/file resolution) ───────
# A2 proves the FULL chain; this proves the minimal/standard ceilings, that outer
# fragments (>=70) ALWAYS load regardless of profile, that an unknown/unset profile falls
# back to full, and that CORE_PROFILE resolves from the environment (wins) or a persistent
# $ZSH_CFG/profile one-liner. Uses lightweight STUB fragments (each echoes its NN) so it is
# fast and asserts the EXACT loaded set — independent of the real modules' side effects.
hdr "profile filtering (CORE_PROFILE ceilings + resolution)"
PROF="$SANDBOX/prof"
mkdir -p "$PROF"
ln -s "$HERE/zsh/loader.zsh" "$PROF/loader.zsh"
for nn in 00 02 05 10 15 20 25 30 35 40 45 50 55 60 80 85 99; do
  printf 'print -r -- "F%s"\n' "$nn" >"$PROF/$nn-stub.zsh"
done
# _prof_load <pre-source snippet> → space-joined NN list actually loaded. The snippet runs
# before `source loader.zsh`, so it can set CORE_PROFILE in the env or leave it unset.
_prof_load() { zsh -f -c "ZSH_CFG='$PROF'; $1; source '$PROF/loader.zsh'" 2>/dev/null | tr '\n' ' ' | sed 's/F//g; s/ *$//'; }
_prof_is() { if [[ "$2" == "$3" ]]; then pass "profile: $1"; else fail "profile: $1 — got [$2] want [$3]"; fi; }
# 02 is in every expectation below, not just _ALL: zsh/02-capabilities.zsh reads the OS
# layer's capability declaration, and a profile that dropped it would leave $_CORE_CAP
# empty — the dispatch table silently absent on exactly the lean boxes (#663).
_ALL="00 02 05 10 15 20 25 30 35 40 45 50 55 60 80 85 99"
_prof_is "full loads every band"          "$(_prof_load 'CORE_PROFILE=full')"     "$_ALL"
_prof_is "minimal = 00-30 + outer (>=70)" "$(_prof_load 'CORE_PROFILE=minimal')"  "00 02 05 10 15 20 25 30 80 85 99"
_prof_is "standard = 00-50 + outer (>=70)" "$(_prof_load 'CORE_PROFILE=standard')" "00 02 05 10 15 20 25 30 35 40 45 50 80 85 99"
_prof_is "unknown value falls back to full" "$(_prof_load 'CORE_PROFILE=bogus')"   "$_ALL"
_prof_is "unset defaults to full"         "$(_prof_load 'true')"                  "$_ALL"
printf 'minimal\n' >"$PROF/profile"                       # persistent one-liner
_prof_is "\$ZSH_CFG/profile one-liner selects minimal" "$(_prof_load 'true')" "00 02 05 10 15 20 25 30 80 85 99"
_prof_is "env CORE_PROFILE wins over the file"         "$(_prof_load 'CORE_PROFILE=standard')" "00 02 05 10 15 20 25 30 35 40 45 50 80 85 99"
# v4.0.1: a slightly-malformed $ZSH_CFG/profile one-liner must still resolve by its FIRST
# FIELD. Before the fix, a trailing space / extra token / surrounding whitespace landed in
# CORE_PROFILE verbatim, so the `case` matched no arm and silently fell through to `full`.
# `read -r CORE_PROFILE _` now takes just the first word (and trims surrounding whitespace).
_MIN="00 02 05 10 15 20 25 30 80 85 99"
_STD="00 02 05 10 15 20 25 30 35 40 45 50 80 85 99"
printf 'minimal \n' >"$PROF/profile" # trailing space
_prof_is "profile w/ trailing space still selects minimal" "$(_prof_load 'true')" "$_MIN"
printf 'standard extra tokens\n' >"$PROF/profile" # stray extra tokens after the profile word
_prof_is "profile w/ extra tokens still selects standard" "$(_prof_load 'true')" "$_STD"
printf '  full  \n' >"$PROF/profile" # surrounding whitespace
_prof_is "profile w/ surrounding whitespace still selects full" "$(_prof_load 'true')" "$_ALL"
# and the persisted CORE_PROFILE must be the TRIMMED first field, not the raw line.
_prof_val() { zsh -f -c "ZSH_CFG='$PROF'; $1; source '$PROF/loader.zsh'; print -r -- \"[\$CORE_PROFILE]\"" 2>/dev/null | tail -1; }
printf 'minimal \n' >"$PROF/profile"
_prof_is "CORE_PROFILE persists as the trimmed first field" "$(_prof_val 'true')" "[minimal]"
rm -f "$PROF/profile"
# same-NN tiebreak: two 85- fragments must load in LEXICAL order (85-r10 before 85-r2), NOT
# numeric/natural order — the loader's contract, and it must hold even under NUMERIC_GLOB_SORT.
printf 'print -r -- r2\n' >"$PROF/85-r2.zsh"
printf 'print -r -- r10\n' >"$PROF/85-r10.zsh"
_tie="$(zsh -f -c "ZSH_CFG='$PROF'; setopt numericglobsort; source '$PROF/loader.zsh'" 2>/dev/null | grep -E '^r(2|10)$' | tr '\n' ' ' | sed 's/ *$//')"
if [[ "$_tie" == "r10 r2" ]]; then pass "profile: same-NN tie breaks lexically (r10 before r2), even under NUMERIC_GLOB_SORT"; else fail "profile: same-NN tiebreak wrong — got [$_tie] want [r10 r2]"; fi
rm -f "$PROF/85-r2.zsh" "$PROF/85-r10.zsh"

# ── A4. os.capabilities reader (zsh/02-capabilities.zsh) ─────────────────────
# The reader is deliberately the PERMISSIVE half of #663: it skips anything it does not
# understand rather than breaking a login shell over a typo, and strictness lives in
# scripts/check-capabilities.sh (exercised further down, in bash, so it is covered even
# on a box with no zsh). What must be asserted here is that "permissive" does not mean
# "vague" — a value survives byte-for-byte, junk never lands in the table, and a box with
# NO declaration still gets a working shell.
#
# Every probe runs under `zsh -f`, which is the point: EXTENDED_GLOB is 10-options.zsh's,
# eight bands after this fragment, so the reader must parse with plain globbing. An earlier
# draft trimmed trailing space with ${v%%[[:space:]]##} and would have matched NOTHING here
# — silently, which is the failure mode this section exists to catch.
hdr "os.capabilities reader (band 02)"
if ! have zsh; then
  skip "os.capabilities reader (no zsh)"
else
  CAPD="$SANDBOX/caps"
  mkdir -p "$CAPD"
  # _cap_probe <capabilities-file-or-empty> <zsh snippet> → stdout of the snippet, run with
  # the fragment sourced exactly as the loader would source it (at top level, not in a
  # function — which is why the fragment cannot use `local`).
  _cap_probe() {
    local _f="$1" _snip="$2"
    zsh -f -c "CORE_CAPABILITIES_FILE='$_f'; source '$HERE/zsh/02-capabilities.zsh'; $_snip" 2>/dev/null
  }
  _cap_is() { if [[ "$2" == "$3" ]]; then pass "capabilities: $1"; else fail "capabilities: $1 — got [$2] want [$3]"; fi; }

  # A well-formed declaration, plus every shape the reader must IGNORE.
  cat >"$CAPD/good" <<'CAPS'
# a comment
   # an indented comment

PKG_INSTALL=sudo dnf install -y
PKG_SEARCH=dnf search
lowercase_key=ignored
Mixed_Case=ignored
not an assignment at all
PKG_EMPTY=
SCHEDULER=systemd
CAPS
  printf 'PKG_TRAILING=dnf provides   \n' >>"$CAPD/good"
  printf 'PKG_SEARCH=dnf whatprovides\n' >>"$CAPD/good"   # duplicate: LAST wins

  # A multi-word value is the whole reason this is not blib_read_pkgs (which strips ALL
  # whitespace); interior spacing must survive verbatim.
  _cap_is "multi-word value survives verbatim" \
    "$(_cap_probe "$CAPD/good" 'print -r -- "[$_CORE_CAP[PKG_INSTALL]]"')" "[sudo dnf install -y]"
  _cap_is "trailing whitespace is trimmed" \
    "$(_cap_probe "$CAPD/good" 'print -r -- "[$_CORE_CAP[PKG_TRAILING]]"')" "[dnf provides]"
  _cap_is "duplicate key: the last one wins" \
    "$(_cap_probe "$CAPD/good" 'print -r -- "[$_CORE_CAP[PKG_SEARCH]]"')" "[dnf whatprovides]"
  # Junk must not merely be tolerated — it must be ABSENT. A lowercase or mixed-case key
  # half-parsed into the table would be a capability nothing ever reads and nothing reports.
  #
  # zsh emits the keys UNSORTED, one per line, and bash sorts them. The obvious spelling —
  # `print -r -- "${(ko)_CORE_CAP}"` — silently does NOT sort: inside double quotes the
  # expansion is joined into a single word before the `o` flag applies, so `o` has one word
  # to order and returns hash order. It read as sorted and was not, which is precisely the
  # kind of assertion that passes for the wrong reason later. Sorting outside zsh depends on
  # no expansion-flag subtlety at all; LC_ALL=C pins collation across the four CI legs.
  _cap_keys="$(_cap_probe "$CAPD/good" 'print -rl -- ${(k)_CORE_CAP}' | LC_ALL=C sort | tr '\n' ' ')"
  _cap_is "only well-formed KEYS land in the table" "${_cap_keys% }" \
    "PKG_EMPTY PKG_INSTALL PKG_SEARCH PKG_TRAILING SCHEDULER"
  # The parser's scratch variables must not leak into the interactive shell. They cannot be
  # `local` (the fragment is sourced at top level), so the explicit unset is load-bearing.
  _cap_is "parser scratch vars do not leak" \
    "$(_cap_probe "$CAPD/good" 'print -r -- "[${_cap_line-unset}${_cap_k-unset}${_cap_v-unset}]"')" \
    "[unsetunsetunset]"

  # _core_cap is THE accessor, and its contract is that "declared empty" and "never
  # declared" behave identically — otherwise every consumer needs both checks.
  _cap_is "_core_cap returns a declared value" \
    "$(_cap_probe "$CAPD/good" '_core_cap PKG_SEARCH')" "dnf whatprovides"
  _cap_is "_core_cap falls back for an ABSENT key" \
    "$(_cap_probe "$CAPD/good" '_core_cap PKG_NOPE "the fallback"')" "the fallback"
  _cap_is "_core_cap falls back for a DECLARED-EMPTY key" \
    "$(_cap_probe "$CAPD/good" '_core_cap PKG_EMPTY "the fallback"')" "the fallback"
  _cap_is "_core_cap with no fallback is the empty string" \
    "$(_cap_probe "$CAPD/good" 'print -r -- "[$(_core_cap PKG_NOPE)]"')" "[]"

  # THE ABSENCE CONTRACT, which is the one this issue argued about: a box with no
  # declaration must get a WORKING shell and a warning, never a hard failure. The whole
  # point is that you can still fix the box you are SSH'd into.
  _cap_is "missing file still yields a usable shell" \
    "$(_cap_probe "$CAPD/does-not-exist" 'print -r -- "[${#_CORE_CAP}][$(_core_cap PKG_INSTALL fallback)]"')" \
    "[0][fallback]"
  _cap_absent_rc="$(zsh -f -c "CORE_CAPABILITIES_FILE='$CAPD/does-not-exist'; source '$HERE/zsh/02-capabilities.zsh'" 2>/dev/null; printf '%s' "$?")"
  _cap_is "missing file exits 0 (a warning, not a failure)" "$_cap_absent_rc" "0"
  # ...and the warning goes to STDERR, so it never pollutes a $(...) capture from a login
  # shell — the way a warning on stdout silently corrupts every script that captures one.
  _cap_warn_out="$(zsh -f -c "CORE_CAPABILITIES_FILE='$CAPD/does-not-exist'; CORE_CAP_LOUD=1; source '$HERE/zsh/02-capabilities.zsh'" 2>/dev/null)"
  _cap_is "the missing-file warning is NOT on stdout" "[$_cap_warn_out]" "[]"
  _cap_warn_err="$(zsh -f -c "CORE_CAPABILITIES_FILE='$CAPD/does-not-exist'; CORE_CAP_LOUD=1; source '$HERE/zsh/02-capabilities.zsh'" 2>&1 >/dev/null | head -n1)"
  case "$_cap_warn_err" in
    *"no OS capability declaration"*) pass "capabilities: the missing-file warning is on stderr" ;;
    *) fail "capabilities: expected a stderr warning for a missing declaration — got [$_cap_warn_err]" ;;
  esac
  # THE REGRESSION GUARD FOR #715. Silence on a missing declaration is the DEFAULT, and
  # this is the assertion that keeps it that way: absence is the normal state for every
  # box in the fleet until an OS repo authors its declaration, so a default-on warning
  # here is two lines of stderr on every shell, every tmux split and every `zsh -i -c`
  # everywhere. It shipped that way once. Asserting the SILENCE, not just that the opt-in
  # works, is what makes flipping the default back a red test rather than a fleet-wide
  # regression nobody notices until it is vendored out.
  _cap_quiet_err="$(zsh -f -c "CORE_CAPABILITIES_FILE='$CAPD/does-not-exist'; source '$HERE/zsh/02-capabilities.zsh'" 2>&1 >/dev/null)"
  _cap_is "a missing declaration is SILENT by default (no CORE_CAP_LOUD)" "[$_cap_quiet_err]" "[]"
  # The hint must point at AUTHORING the declaration. It used to say `--links-only`, which
  # re-runs the same `[[ -f ]]` guard that skipped the link — advice that cannot work.
  _cap_hint="$(zsh -f -c "CORE_CAPABILITIES_FILE='$CAPD/does-not-exist'; CORE_CAP_LOUD=1; source '$HERE/zsh/02-capabilities.zsh'" 2>&1 >/dev/null)"
  case "$_cap_hint" in
    *"os.capabilities.example"*) pass "capabilities: the warning points at authoring a declaration" ;;
    *) fail "capabilities: the warning should name the example file — got [$_cap_hint]" ;;
  esac

  # A file with no trailing newline: the `|| [[ -n "$line" ]]` arm. Without it the last
  # assignment in a hand-edited declaration is dropped, silently.
  printf 'PKG_INSTALL=apk add' >"$CAPD/no-newline"
  _cap_is "a final line with no trailing newline is still read" \
    "$(_cap_probe "$CAPD/no-newline" 'print -r -- "[$_CORE_CAP[PKG_INSTALL]]"')" "[apk add]"

  # An EMPTY declaration is well-formed input, not an error: the audit is what says a
  # required key is missing.
  : >"$CAPD/empty"
  _cap_is "an empty declaration yields an empty table, not an error" \
    "$(_cap_probe "$CAPD/empty" 'print -r -- "[${#_CORE_CAP}]"')" "[0]"
fi

# ── B. function unit tests ────────────────────────────────────────────────────
hdr "function unit tests (functions.zsh)"
FN="$HERE/zsh/30-functions.zsh"
# functions.zsh now routes its errors through ui.zsh's _core_* helpers, so the
# unit shell must source ui.zsh FIRST — the same ordering the real loader uses
# (tools → ui → … → functions). It loads before functions in every assertion below.
UI="$HERE/zsh/05-ui.zsh"

# Run an assertion under zsh; $1 = label, $2 = zsh body that must exit 0.
# On FAILURE we capture the child's combined stdout+stderr and print it INDENTED
# (mirroring the nvim/smoke sections above) — a red unit test must say WHY, not just
# its label, or a CI failure that fans out to nine repos forces a local re-reproduction.
# On PASS the output is discarded, so the expected _core_err/usage noise stays silent.
check() { # check <label> <zsh-body>
  local out
  if out="$(HOME="$SANDBOX" zsh -fc "source '$UI' || exit 1; source '$FN' || exit 1; $2" 2>&1)"; then
    pass "$1"
  else
    fail "$1"
    [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
}

# Like check, but SKIP (not fail) when a required external tool is absent — so the
# archive round-trip tests degrade gracefully on a bare box, mirroring the linter
# skips above. extract's own first branch is `ouch` when HAVE_OUCH is set; under
# `zsh -fc` that var is unset, so these exercise the hand-rolled case fallback.
check_dep() { # check_dep <label> <dep> <zsh-body>
  if ! have "$2"; then
    skip "$1 ($2 not installed)"
    return
  fi
  local out
  if out="$(HOME="$SANDBOX" zsh -fc "source '$UI' || exit 1; source '$FN' || exit 1; $3" 2>&1)"; then
    pass "$1"
  else
    fail "$1"
    [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
}

check "mkcd creates and enters a nested dir" \
  'd=$(mktemp -d); cd "$d"; mkcd a/b/c; [[ ${PWD:t} == c && -d "$d/a/b/c" ]]'
check "cdup climbs N directories" \
  'd=$(mktemp -d); mkdir -p "$d/a/b/c"; cd "$d/a/b/c"; cdup 2; [[ ${PWD:t} == a ]]'
# Defensive input guards (U1): a bad count / missing file / bad port must be REJECTED
# in Core's voice (non-zero), not silently no-op or handed to cp/python to fail raw.
check "cdup rejects a non-numeric count" \
  'cdup abc 2>/dev/null; (( $? != 0 ))'
check "cdup rejects a zero count" \
  'cdup 0 2>/dev/null; (( $? != 0 ))'
check "mkbak writes a timestamped .bak copy" \
  'd=$(mktemp -d); cd "$d"; print hi > f; mkbak f; set -- f.*.bak; [[ -f $1 ]]'
check "mkbak's .bak is byte-identical to the original" \
  'd=$(mktemp -d); cd "$d"; print -r -- payload > f; mkbak f; set -- f.*.bak; [[ -f $1 && "$(cat -- $1)" == payload ]]'
check "mkbak rejects a missing file" \
  'mkbak /no/such/file 2>/dev/null; (( $? != 0 ))'
check "mkbak with no argument is rejected" \
  'mkbak 2>/dev/null; (( $? != 0 ))'
# U6: a second backup must NOT clobber an existing .bak and must NOT prompt. Pre-create
# the timestamped target, then run mkbak with stdin closed: collision-safe means a SECOND
# .bak appears (≥2 total); had `cp -i` bled in, the closed stdin would abort the copy (1).
# Robust to the same-second/next-second race either way (distinct name OR distinct suffix).
check "mkbak never clobbers an existing .bak (collision-safe, non-interactive)" \
  'd=$(mktemp -d); cd "$d"; print hi > f; ts=$(date +%Y%m%d-%H%M%S); : > "f.$ts.bak"; mkbak f </dev/null >/dev/null 2>&1; n=$(print -l -- f.*.bak(N) | wc -l); (( n >= 2 ))'
check "serve rejects a non-numeric port" \
  'serve abc 2>/dev/null; (( $? != 0 ))'
check "serve rejects an out-of-range port" \
  'serve 99999 2>/dev/null; (( $? != 0 ))'
# serve -l/--local (#10): the loopback flag must be ACCEPTED as a flag (not mis-read as
# the port) while the port is still validated, and an unknown flag must be rejected — all
# before python ever binds, so these stay non-blocking.
check "serve rejects an unknown flag (-l/--local is the only flag)" \
  'serve --nope 2>/dev/null; (( $? != 0 ))'
check "serve -l is parsed as a flag and still validates the port" \
  'serve -l abc 2>/dev/null; (( $? != 0 ))'
# Uniform -h/--help contract (U6): every user-facing verb answers --help on STDOUT
# and returns 0 (a help REQUEST is success, not misuse). This also guards the bugs
# where --help used to be mis-read as an operand — serve as a bad port, extract as a
# missing file (both returned non-zero); the guard must short-circuit before that.
check "mkcd --help prints usage to stdout and returns 0" \
  'out=$(mkcd --help); (( $? == 0 )) && [[ $out == *"usage: mkcd"* ]]'
check "serve --help returns 0 (not mis-read as a bad port)" \
  'out=$(serve --help); (( $? == 0 )) && [[ $out == *"usage: serve"* ]]'
check "extract -h returns 0 (not mis-read as a missing file)" \
  'out=$(extract -h); (( $? == 0 )) && [[ $out == *"usage: extract"* ]]'
# pullall (#git): the parent dir is configurable, so input is validated in Core's
# voice — a non-directory and a bad PULLALL_JOBS are both REJECTED before any find/
# xargs runs. --help is the usual STDOUT-and-return-0 contract. The repo-less-dir
# case exercises the full find→xargs→summary pipeline hermetically (no network, no
# .git, so the workers exit early) and asserts the summary card + a clean exit.
check "pullall --help prints usage to stdout and returns 0" \
  'out=$(pullall --help); (( $? == 0 )) && [[ $out == *"usage: pullall"* ]]'
check "pullall rejects a non-directory parent" \
  'pullall /no/such/dir 2>/dev/null; (( $? != 0 ))'
check "pullall rejects a non-numeric PULLALL_JOBS" \
  'PULLALL_JOBS=x pullall "$(mktemp -d)" 2>/dev/null; (( $? != 0 ))'
check "pullall on a repo-less dir prints the summary and returns 0" \
  'd=$(mktemp -d); mkdir "$d/a" "$d/b"; out=$(pullall "$d" 2>&1); (( $? == 0 )) && [[ $out == *"pullall summary"* && $out == *"updated:  0"* ]]'
# Integration (the bulk of the logic the validation tests above don't reach): build a
# bare remote + a behind clone hermetically (mirrors the gcheck git_* tests below — a
# throwaway $GIT_AUTHOR_* identity and git init in mktemp), advance the remote, then run
# pullall and assert it fast-forwarded the clone (tally "updated: 1", a real new file on
# disk, zero failures). This exercises trunk auto-detection, the --ff-only pull, and the
# ✅ tally — the per-repo path that fans out to all nine OS repos.
check_dep "pullall fast-forwards a behind repo and tallies it (hermetic bare remote)" git \
  'export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e
   w=$(mktemp -d)
   git -c init.defaultBranch=main init -q --bare "$w/remote.git"
   git -c init.defaultBranch=main clone -q "$w/remote.git" "$w/seed"
   ( cd "$w/seed" && print -r -- one > a.txt && git add a.txt && git commit -q -m one && git push -q -u origin main )
   mkdir -p "$w/parent"
   git clone -q "$w/remote.git" "$w/parent/repoA"
   ( cd "$w/seed" && print -r -- two > b.txt && git add b.txt && git commit -q -m two && git push -q origin main )
   out=$(pullall "$w/parent" 2>&1)
   [[ $out == *"updated:  1"* && $out == *"failed:   0"* && -f "$w/parent/repoA/b.txt" ]]'
# The riskier path this PR added: a NON-fast-forward pull ($pull != 0) that ALSO hits a
# stash-pop conflict must report ❌ "pull failed AND a conflict …" and count as a failure,
# NOT a ⚠️ that claims the trunk was updated. Construct it hermetically: diverge the clone
# (local main commit) and the remote (a different commit) so --ff-only fails, then sit on a
# feature branch (forked from before the divergence) with a conflicting uncommitted change
# so the auto-stash pop conflicts after checkout. Asserts the gate + the failure tally.
check_dep "pullall reports a combined pull-failure + stash-pop conflict as a ❌" git \
  'export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e
   w=$(mktemp -d)
   git -c init.defaultBranch=main init -q --bare "$w/remote.git"
   git -c init.defaultBranch=main clone -q "$w/remote.git" "$w/seed"
   ( cd "$w/seed" && print -r -- base > x.txt && git add x.txt && git commit -q -m base && git push -q -u origin main )
   mkdir -p "$w/parent"
   git clone -q "$w/remote.git" "$w/parent/repoA"
   ( cd "$w/seed" && print -r -- remotemain > x.txt && git commit -q -am remotemain && git push -q origin main )
   ( cd "$w/parent/repoA" && print -r -- localmain > x.txt && git commit -q -am localmain && git checkout -q -b feature main~1 && print -r -- dirty > x.txt )
   out=$(pullall "$w/parent" 2>&1)
   [[ $out == *"failed:   1"* && $out == *"pull failed AND a conflict"* ]]'
# core-version (#4): reports the vendored Core stamp so an OS repo can tell WHICH Core
# it carries. $_CORE_VERSION_FILE resolves (via %x) to this repo's core.version here.
check "core-version prints the vendored SemVer stamp" \
  'out=$(core-version); (( $? == 0 )) && [[ $out == "dotfiles-core "[0-9]* ]]'
check "core-version --help returns 0 (not mis-read)" \
  'out=$(core-version --help); (( $? == 0 )) && [[ $out == *"usage: core-version"* ]]'
# core-doctor (#9): the shell-side health report. Must render and return 0 even on a
# bare box (every tool ✗) — it's read-only diagnostics, never a hard failure.
# Every group label must render, and a tool must land under the group it was filed in. The
# parity check below compares tool NAMES between the two inventories, so deleting a whole
# group — label and members, from both — slips past it; and the render test underneath only
# greps for "modern CLI", which predates the `data / net` and `dev / repo` groups. Assert all
# four labels, then that watchexec renders AFTER the `dev / repo` heading rather than merely
# somewhere in the report. (Parity then carries this to --json: render set == tools keys.)
check "core-doctor renders every group label and files watchexec under dev / repo" \
  '_core_have() { return 1; }
   _core_doctor_present() { return 1; }
   out=$(NO_COLOR=1 core-doctor 2>&1); (( $? == 0 )) \
     && [[ $out == *"modern CLI"* && $out == *"integrations"* ]] \
     && [[ $out == *"data / net"* && $out == *"dev / repo"* ]] \
     && [[ ${out#*"dev / repo"} == *watchexec* ]]'
check "core-doctor renders a health report and returns 0" \
  'out=$(NO_COLOR=1 core-doctor 2>&1); (( $? == 0 )) && [[ $out == *dotfiles-core* && $out == *"modern CLI"* ]]'
# core-doctor -v (#9): the version readout. Regression guard for a leak that made the whole
# flag useless — `local _v` sat INSIDE the per-tool loop, and zsh prints `name=value` when
# `local` re-declares a parameter that already holds one (TYPESET_SILENT is off under
# `emulate -L zsh`), so every tool after the first emitted a bare `_v=0.26.1` line into the
# report instead of annotating the ✓. Nothing drove -v, so it shipped broken. Hermetic: stub
# _core_have to admit specific tools and shadow those tools with functions (zsh resolves them
# for the `"$tool" --version` probe), so this asserts real rendering rather than whatever is
# on PATH. TWO tools, deliberately: the leak only fires on the SECOND re-declaration, so a
# single-tool version of this test passes against the unfixed code and guards nothing.
check "core-doctor -v annotates versions and leaks no _v= lines" \
  '_core_have() { [[ "$1" == (eza|bat) ]]; }
   _core_doctor_present() { [[ "$1" == (eza|bat) ]]; }
   eza() { print -r -- "eza 9.9.9"; }
   bat() { print -r -- "bat 8.8.8"; }
   out=$(NO_COLOR=1 core-doctor -v 2>&1); (( $? == 0 )) \
     && [[ $out == *"✓ eza 9.9.9"* ]] && [[ $out == *"✓ bat 8.8.8"* ]] && [[ $out != *"_v="* ]]'
check "core-doctor --help returns 0 (not mis-read)" \
  'out=$(core-doctor --help); (( $? == 0 )) && [[ $out == *"usage: core-doctor"* ]]'
# core-doctor --json (B12): a machine-readable object on stdout that actually parses and
# carries the tools/wired/atuin_daemon/resolved keys — so a statusline/editor/CI can consume
# health. atuin_daemon's shape is asserted exactly (not just present): it is the one field here
# describing state that can change under a LIVE shell, so a consumer polling it needs both
# booleans to keep meaning what they say.
check "core-doctor --json emits parseable JSON with tools/wired/atuin_daemon/resolved" \
  'out=$(core-doctor --json); print -r -- "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); assert set([\"version\",\"tools\",\"expected\",\"wired\",\"detection\",\"atuin_daemon\",\"resolved\"]) <= set(d); assert set(d[\"atuin_daemon\"]) == set([\"degraded\",\"was_up\"]); assert set(d[\"detection\"]) == set([\"ran\",\"missed\",\"stale\"]); assert isinstance(d[\"detection\"][\"ran\"], bool) and isinstance(d[\"detection\"][\"missed\"], list) and isinstance(d[\"detection\"][\"stale\"], list)"'
# The human report and --json now BOTH derive from _CORE_DOCTOR_GROUPS, so they agree by
# construction and this assertion should be tautological. It is kept precisely for that
# reason: it is the guard that stays red if someone reintroduces a second literal — which is
# how these two lived before, and they did silently desync. Treat a failure here as "the
# single source was forked", not as a missing tool. Assert the two NAME SETS are equal.
# _core_have is stubbed false so the render is deterministic:
# every tool prints as a plain ✗ (no --version forks), the "integrations wired" block skips
# every entry, and "resolved" carries no ✓/✗ markers — leaving the group lists as the only
# thing the regex can match. Skips rather than fails without python3, like the linters above.
check_dep "core-doctor's rendered tool set == --json tools (the two inventories can't drift)" python3 \
  '_core_have() { return 1; }
   _core_doctor_present() { return 1; }
   _r=$(NO_COLOR=1 core-doctor 2>&1); _j=$(core-doctor --json)
   _CD_R="$_r" _CD_J="$_j" python3 -c "
import json, os, re
body  = os.environ[\"_CD_R\"].split(chr(10), 1)[1]   # drop line 1: the header legend, not tools
body  = body.split(chr(10) + \"opt-in\")[0]           # and the trailing opt-in recap, which re-lists names
shown = set(re.findall(r\"[✓✗·] ([A-Za-z0-9_.-]+)\", body))
keys  = set(json.loads(os.environ[\"_CD_J\"])[\"tools\"])
assert shown, \"parsed no tools out of the rendered report\"
assert shown == keys, \"render-only: %s | json-only: %s\" % (sorted(shown - keys), sorted(keys - shown))
"'
# ── the third state (#513) ────────────────────────────────────────────────────────────
# `✗` is the doctor's only alarm channel, and PORTING-MATRIX.md's footnote ²¹ names a subset
# of the inventory that NO Linux repo's packages.txt and NO bootstrap.sh installs, on purpose.
# Rendering both as ✗ meant a correctly-provisioned box showed a wall of them, so a REAL
# regression — a tool that was installed and broke — landed in the same visual bucket as the
# ones that were never coming.
check "core-doctor renders opt-in absence as · and expected absence as ✗" \
  '_core_have() { return 1; }
   _core_doctor_present() { return 1; }
   out=$(NO_COLOR=1 core-doctor 2>&1)
   [[ $out == *"· lnav"* ]] && [[ $out == *"· git-absorb"* ]] \
     && [[ $out == *"✗ eza"* ]] && [[ $out == *"✗ jq"* ]] \
     && [[ $out != *"✗ lnav"* ]] && [[ $out != *"· eza"* ]]'
# The legend has to name all three or the third glyph is a mystery mark. Asserted because the
# glyph set and the legend are two literals in one function and drifted once already.
check "core-doctor's legend names all three states" \
  'out=$(NO_COLOR=1 core-doctor 2>&1 | head -n1)
   [[ $out == *"✓ present"* ]] && [[ $out == *"✗ expected but missing"* ]] \
     && [[ $out == *"· opt-in"* ]]'
# `·` and not `○`: the wired block below the tools uses ○ for "installed but IDLE". Two
# meanings for one glyph on one screen is the legibility problem this change is about, so the
# separation is pinned rather than left to whoever edits next.
check "core-doctor does not reuse the wired block's ○ for opt-in tools" \
  '_core_have() { return 1; }
   _core_doctor_present() { return 1; }
   out=$(NO_COLOR=1 core-doctor 2>&1)
   [[ $out != *"○ lnav"* ]] && [[ $out != *"○ ouch"* ]]'
# An opt-in tool must NOT join the "install missing" list. That block exists to tell the
# operator what to fix; listing something nothing was ever going to install is the same alarm
# fatigue one layer down.
check "core-doctor keeps opt-in tools out of the install-missing list" \
  '_core_have() { return 1; }
   _core_doctor_present() { return 1; }
   _pkgup_mgr() { print -r -- apt; }
   out=$(NO_COLOR=1 core-doctor 2>&1)
   inst=${out#*"install missing"}; inst=${inst%%"opt-in"*}
   [[ $out == *"install missing"* ]] && [[ $inst == *"eza"* ]] && [[ $inst != *"lnav"* ]]'
# THE POINT OF THE WHOLE CHANGE, in the machine-readable half: "no expected tool is missing"
# had no expressible form. `tools` alone can only answer "is every tool present", which is
# false on every correctly-provisioned box, so a provisioning gate could not be written at all.
check_dep "core-doctor --json exposes 'expected', so a gate can assert what actually matters" python3 \
  '_core_have() { return 1; }
   _core_doctor_present() { return 1; }
   _CD_J="$(core-doctor --json)" python3 -c "
import json, os
d = json.loads(os.environ[\"_CD_J\"])
t, e = d[\"tools\"], d[\"expected\"]
assert list(e) == list(t), \"expected and tools must share key set AND order\"
assert all(v is False for v in t.values()), \"the stub makes every tool absent\"
# with everything absent, the gate must flag exactly the EXPECTED ones — not all of them
gate = sorted(k for k, v in e.items() if v and not t[k])
optin = sorted(k for k, v in e.items() if not v)
assert \"lnav\" in optin and \"git-absorb\" in optin, optin
assert \"eza\" in gate and \"jq\" in gate, gate
assert not (set(gate) & set(optin)), \"a tool cannot be both\"
"'
# MAKE THE PROSE MECHANICALLY CHECKABLE. _CORE_DOCTOR_OPTIN is seeded from PORTING-MATRIX.md
# footnote ²¹, and a hand-copied list is how the matrix and the inventory drift apart — which
# is exactly what happened in the other direction when a probed tool shipped with no matrix
# row at all (#514). Re-derive the list from the matrix and require the two to agree.
#
# The rule, stated once here and in the array's comment: a tool is opt-in iff its Tool cell
# carries a ROW-level ²¹, or one of the two footnotes ²¹ itself calls "the same shape" (¹⁷
# jnv, ¹⁹ gping). Cell-level ²¹ (jj, ast-grep — Gentoo and Kali only) is deliberately NOT
# included: a Core-side list cannot say "opt-in there, expected here", and muting them
# globally would hide a real ✗ on the repos that do install them.
check_dep "core-doctor's opt-in list is derivable from PORTING-MATRIX footnote 21" python3 \
  '_MATRIX="'"$HERE"'/PORTING-MATRIX.md" _OPTIN="${_CORE_DOCTOR_OPTIN[*]}" python3 -c "
import os, re
lines = open(os.environ[\"_MATRIX\"]).read().split(chr(10))
# Only the AUTHORITATIVE package-names table, bounded to its own CONTIGUOUS rows. Footnote 21
# carries a coverage table of its own whose first column is backticked tool names, and it sits
# between this table and the next \"## \" heading — so slicing on headings swept it in. A
# derivation that reads the wrong table is worse than none, because it looks rigorous.
i = next(n for n, l in enumerate(lines) if l.startswith(\"## Package names (modern CLI stack)\"))
i = next(n for n in range(i, len(lines)) if lines[n].startswith(\"| Tool\"))
rows = []
while i < len(lines) and lines[i].startswith(\"|\"):
    rows.append(lines[i]); i += 1
want = set()
for cell in re.findall(r\"(?m)^\\| *([^|]+?) *\\|\", chr(10).join(rows)):
    name = re.split(r\"[ ⁰¹²³⁴⁵⁶⁷⁸⁹]\", cell, maxsplit=1)[0]
    if set(re.findall(r\"[⁰¹²³⁴⁵⁶⁷⁸⁹]+\", cell)) & set([\"²¹\", \"¹⁷\", \"¹⁹\"]):
        want.add(name)
have = set(os.environ[\"_OPTIN\"].split())
assert want, \"parsed no footnote-21 rows out of PORTING-MATRIX.md\"
assert want == have, \"matrix-only: %s | list-only: %s\" % (sorted(want - have), sorted(have - want))
"'
# ── detection divergence: `✓` must stop meaning "Core wired this" (#545) ─────
# HAVE_* is decided at band 00 against a PATH that keeps changing afterwards (mise's chpwd
# hook, 80-os.zsh, an 85-* role fragment, 99-local.zsh). core-doctor probes LIVE against the
# finished PATH, so a tool contributed by any of those rendered a clean ✓ while Core had
# wired nothing — no alias, no init, no flag. These drive the _CORE_PROBED ledger directly:
# `check` sources ui+functions ONLY, so band 00 never runs and the ledger is whatever the
# body sets, which is exactly the control this needs.
check "core-doctor marks a present-but-unwired tool with ⚠ and names it" \
  '_core_have() { return 0 }
   _core_doctor_present() { return 0 }
   typeset -gA _CORE_PROBED=(eza 1 procs 0)
   out=$(_CORE_FORCE_COLOR= core-doctor)
   [[ $out == *"procs⚠"* ]] || { print -r -- "no ⚠ on procs"; exit 1 }
   [[ $out != *"eza⚠"* ]]   || { print -r -- "⚠ on eza, which WAS probed"; exit 1 }
   [[ $out == *"not wired"* ]] || { print -r -- "no not-wired block"; exit 1 }
   [[ $out != *"mark="* ]]  || { print -r -- "local re-declaration leaked mark= into the report"; exit 1 }'
# The sentinel. Without a ledger, 00-tools.zsh never ran in this shell — a script, `zsh -c`,
# or this very harness — and the honest answer is to make NO claim. Reporting 41 unwired
# tools there would be worse than silence, and would red every unit harness in the suite.
check "core-doctor makes no wiring claim when detection never ran" \
  '_core_have() { return 0 }
   _core_doctor_present() { return 0 }
   out=$(_CORE_FORCE_COLOR= core-doctor)
   [[ $out != *"⚠"* ]]        || { print -r -- "⚠ rendered with no ledger"; exit 1 }
   [[ $out != *"not wired"* ]] || { print -r -- "not-wired block rendered with no ledger"; exit 1 }'
check_dep "core-doctor --json reports detection.ran=false when band 00 never loaded" python3 \
  '_core_have() { return 0 }
   _core_doctor_present() { return 0 }
   core-doctor --json | python3 -c "import json,sys; d=json.load(sys.stdin); assert d[\"detection\"][\"ran\"] is False, d[\"detection\"]; assert d[\"detection\"][\"missed\"] == [], d[\"detection\"]"'
# Second gate: a row Core does not probe AT ALL must draw no claim either. Without this,
# every doctor row with no 00-tools.zsh probe behind it would false-positive as unwired.
check "core-doctor makes no wiring claim for a row Core never probes" \
  '_core_have() { return 0 }
   _core_doctor_present() { return 0 }
   typeset -gA _CORE_PROBED=(eza 1)
   out=$(_CORE_FORCE_COLOR= core-doctor)
   [[ $out != *"op⚠"* ]] || { print -r -- "⚠ on a row with no ledger entry"; exit 1 }'
# The parity test above stubs _core_have FALSE and never populates the ledger, so it cannot
# fire this axis at all — which makes "the ⚠ is invisible to it by construction" an untested
# claim. Re-run the same comparison with the axis ACTIVELY firing.
check_dep "the render⇄json tool sets still match with the ⚠ axis firing" python3 \
  '_core_have() { return 0 }
   _core_doctor_present() { return 0 }
   typeset -gA _CORE_PROBED=(procs 0 jnv 0)
   _CD_R="$(NO_COLOR=1 core-doctor 2>&1)" _CD_J="$(core-doctor --json)" python3 -c "
import json, os, re
# Same two trims as the parity test this mirrors: line 1 is the legend (it contains the
# glyphs), and everything from the opt-in recap on re-lists names. The not-wired block sits
# AFTER opt-in precisely so this second trim covers it structurally.
body = os.environ[\"_CD_R\"].split(chr(10), 1)[1]
body = body.split(chr(10) + \"opt-in\")[0]
shown = set(re.findall(r\"[✓✗·] ([A-Za-z0-9_.-]+)\", body))
keys  = set(json.loads(os.environ[\"_CD_J\"])[\"tools\"])
assert shown, \"parsed no tools out of the rendered report\"
assert shown == keys, \"render-only: %s | json-only: %s\" % (sorted(shown - keys), sorted(keys - shown))
"'

# ── #631: the MIRROR of #545 — a flag set at band 00 for a binary that is now GONE ───────
# #545's case is present-but-unprobed. This is probed-but-absent: HAVE_* is still set, so
# 20-aliases.zsh's guard passed and defined an alias against a binary that no longer resolves.
# Deliberately NO fifth glyph — the row keeps its honest ✗ and the remedy lives in a `stale`
# block, so the legend and the render⇄json parity regex are both untouched.
check "core-doctor reports a stale flag in a 'stale' block, with no new glyph" \
  '_core_have() { return 1 }
   _core_doctor_present() { return 1 }
   typeset -gA _CORE_PROBED=(procs 1)
   out=$(NO_COLOR=1 core-doctor 2>&1)
   [[ $out == *"stale"* ]]  || { print -r -- "no stale block for a probed-then-absent tool"; exit 1 }
   [[ $out == *"procs"* ]]  || { print -r -- "stale block does not name the tool"; exit 1 }
   [[ $out == *"✗ procs"* ]] || { print -r -- "the row should still render an honest ✗"; exit 1 }'
# The point of the block is the ALIAS, not the tool: `ps` is the command that breaks, `procs`
# is trivia the user never typed. Read from the live `aliases` table, so it cannot drift from
# 20-aliases.zsh.
check "core-doctor names the ALIAS a stale flag left pointing at nothing" \
  '_core_have() { return 1 }
   _core_doctor_present() { return 1 }
   typeset -gA _CORE_PROBED=(procs 1)
   alias ps=procs
   out=$(NO_COLOR=1 core-doctor 2>&1)
   [[ $out == *"ps → procs"* ]] || { print -r -- "did not name the broken alias; got: ${out##*stale}"; exit 1 }'
# THE REGRESSION GUARD FOR #715, and the reason _core_doctor_present exists at all. This one
# does NOT stub the presence probe: it drives the REAL one, because the bug was IN the real
# one. `_core_have` is `command -v` and zsh's `command -v` resolves aliases, so a tool that
# had left $PATH still answered yes off the alias 20-aliases.zsh defines for it — the row
# rendered ✓, the else-branch never ran, and the tool never joined `stale`. `rg` was blind
# this way on every distro. Stubbing presence here would test the stub; shadowing a tool with
# an alias and asserting the row is still honest tests the thing that broke.
check "_core_doctor_present is blind to aliases (where _core_have was not)" \
  '_cdp_name=__core_alias_only_probe__
   alias $_cdp_name="true --pretend"
   _core_have "$_cdp_name" || { print -r -- "precondition gone: command -v no longer resolves aliases"; exit 1 }
   ! _core_doctor_present "$_cdp_name" || { print -r -- "presence probe still reads an alias as a tool"; exit 1 }
   _core_doctor_present sh || { print -r -- "presence probe lost a real PATH binary"; exit 1 }
   _core_doctor_present "$(command -v sh)" || { print -r -- "presence probe lost an absolute path"; exit 1 }
   ! _core_doctor_present /nope/not/a/binary || { print -r -- "presence probe accepted a bogus path"; exit 1 }'
# Both ledger gates apply here exactly as they do to the unwired axis — a doctor that claims
# staleness with no ledger would flag every absent tool on a bare box, which is most of them.
check "core-doctor makes no staleness claim when detection never ran" \
  '_core_have() { return 1 }
   _core_doctor_present() { return 1 }
   out=$(NO_COLOR=1 core-doctor 2>&1)
   [[ $out != *"stale"* ]] || { print -r -- "stale block rendered with no ledger"; exit 1 }'
# With _core_have stubbed FALSE every row is absent, so the second gate here is not "no block
# at all" (as it is for #545's ⚠, which fires on the present branch) but "only ledger rows
# appear in it". Asserted on the NAMES line alone — the prose underneath contains "open a new
# shell", and a substring match for a tool called `op` finds the "op" in "open".
check "core-doctor's stale block lists only rows Core actually probes" \
  '_core_have() { return 1 }
   _core_doctor_present() { return 1 }
   typeset -gA _CORE_PROBED=(eza 1)
   names=$(NO_COLOR=1 core-doctor 2>&1 | awk "/^stale\$/{getline; print; exit}")
   [[ ${names// /} == eza ]] \
     || { print -r -- "stale names line should be exactly \"eza\", got: [$names]"; exit 1 }'
# …and the false-positive mirror: a tool the ledger says was ABSENT at band 00 and is still
# absent is simply missing, not stale. Nothing was wired, so no alias can be dangling.
check "core-doctor does not call a never-detected tool stale" \
  '_core_have() { return 1 }
   _core_doctor_present() { return 1 }
   typeset -gA _CORE_PROBED=(procs 0)
   out=$(NO_COLOR=1 core-doctor 2>&1)
   [[ $out != *"stale"* ]] || { print -r -- "an absent-at-band-00 tool was reported stale"; exit 1 }'
check_dep "core-doctor --json exposes detection.stale, disjoint from detection.missed" python3 \
  '_core_have() { return 1 }
   _core_doctor_present() { return 1 }
   typeset -gA _CORE_PROBED=(procs 1 jnv 0)
   core-doctor --json | python3 -c "
import json, sys
d = json.load(sys.stdin)[\"detection\"]
assert d[\"ran\"] is True, d
assert \"procs\" in d[\"stale\"], d
assert \"jnv\" not in d[\"stale\"], d
assert set(d[\"stale\"]) & set(d[\"missed\"]) == set(), d
"'
# The parity test stubs _core_have FALSE, which is exactly the branch this axis fires on — so
# unlike #545's ⚠ it CAN perturb that comparison. Re-run it with the stale axis active to show
# the `stale` block is invisible to it (it sits past the opt-in trim, like `not wired`).
check_dep "the render⇄json tool sets still match with the stale axis firing" python3 \
  '_core_have() { return 1 }
   _core_doctor_present() { return 1 }
   typeset -gA _CORE_PROBED=(procs 1 btop 1)
   alias ps=procs
   _CD_R="$(NO_COLOR=1 core-doctor 2>&1)" _CD_J="$(core-doctor --json)" python3 -c "
import json, os, re
body = os.environ[\"_CD_R\"].split(chr(10), 1)[1]
body = body.split(chr(10) + \"opt-in\")[0]
shown = set(re.findall(r\"[✓✗·] ([A-Za-z0-9_.-]+)\", body))
keys  = set(json.loads(os.environ[\"_CD_J\"])[\"tools\"])
assert shown, \"parsed no tools out of the rendered report\"
assert shown == keys, \"render-only: %s | json-only: %s\" % (sorted(shown - keys), sorted(keys - shown))
"'

# Orphan guard: a name here that is not in _CORE_DOCTOR_GROUPS mutes nothing and reads as if
# it does — the failure mode of every list maintained beside another list.
check "every _CORE_DOCTOR_OPTIN entry is actually in the doctor inventory" \
  'local -a all=(); local gi
   for ((gi = 2; gi <= ${#_CORE_DOCTOR_GROUPS}; gi += 2)); do all+=(${=_CORE_DOCTOR_GROUPS[gi]}); done
   local o orphan=""
   for o in $_CORE_DOCTOR_OPTIN; do (( ${all[(I)$o]} )) || orphan="$orphan $o"; done
   [[ -z $orphan ]] || { print -r -- "orphaned opt-in entries:$orphan"; false }'

# The invariant that would have caught the drift this backfill fixed: every binary
# 00-tools.zsh probes must be REPORTED by the doctor. Twelve were not — ast-grep, difft,
# gping, hyperfine, jj, jnv, ouch, shellcheck, shfmt, tldr, uv, viddy were detected into
# HAVE_* flags and appeared in neither renderer, silently, for releases. Parity (above) only
# compares the doctor against itself, so it can never see this; the two lists agreed
# perfectly about a tool neither of them mentioned. Read the probe list straight out of the
# source file and require the inventory to cover it.
# Direction is deliberately one-way: probed ⊆ reported. The reverse would fail on `op` (no
# HAVE_OP — the doctor probes it live) and on `fd`/`bat`, which 00-tools.zsh sets from
# FD_BIN/BAT_BIN after resolving fdfind/batcat rather than with a bare `_have` line.
# `^_have +` and not `^_have `: 00-tools.zsh aligns a couple of trailing comments with two
# spaces (tldr is one), and the single-space form silently dropped those rows from the set —
# a coverage guard that read stronger than it was. The quantifier takes it 37 → 38.
check_dep "core-doctor reports every tool 00-tools.zsh probes (no silently undetected tools)" python3 \
  '_TOOLS_SRC="'"$HERE"'/zsh/00-tools.zsh" _CD_J="$(core-doctor --json)" python3 -c "
import json, os, re
probed   = set(re.findall(r\"(?m)^_have +([A-Za-z0-9_.-]+)\", open(os.environ[\"_TOOLS_SRC\"]).read()))
reported = set(json.loads(os.environ[\"_CD_J\"])[\"tools\"])
missing  = sorted(probed - reported)
assert probed, \"parsed no _have lines out of 00-tools.zsh\"
assert not missing, \"detected by 00-tools.zsh but absent from core-doctor: %s\" % missing
"'
# ...and now the REVERSE direction, which the note above declined to assert because three
# rows legitimately have no `_have` line. Declining it entirely left a hole: the check above
# derives its tool -> flag mapping from the very line that sets the flag, so DELETING
# `_have jq && HAVE_JQ=1` does not make it fail — it just removes jq from both sides and the
# suite goes quiet. That is the #447 failure mode itself (the doctor promising a tool Core
# never wired), so assert it directly, with the three exceptions named rather than waived.
#
# THE EXEMPTION LIST IS NOW EMPTY, and that is the point (#545). It used to read
# `exempt=(op fd bat)` with this rationale:
#
#     op is deliberate: the doctor probes it live and no alias or function is gated on it.
#
# which was simply false. 50-op.zsh:7 gates FOUR verbs — opsecret, openv, optoken, opssh —
# behind its own `command -v op`, at band 50, which still runs before 80-os.zsh, an 85-* role
# fragment and 99-local.zsh. So `op` had the exact divergence this test was meant to police,
# sitting inside the doctor's own inventory behind a comment asserting it could not.
#
# fd and bat were excused because their flags are set from FD_BIN/BAT_BIN (after resolving
# fdfind/batcat), so the assignments do not match `^_have`. Both now record into the
# _CORE_PROBED ledger under their CANONICAL names, which is what the doctor keys on — so the
# excuse is gone rather than merely tolerated.
#
# Two shapes are parsed, because detection is now recorded in two places: the classic
# `_have <tool> && HAVE_<X>=1` line, and an explicit `_CORE_PROBED[<tool>]=1`. Note `$` is
# outside the character class in the second pattern, so the generic `_CORE_PROBED[$1]=1`
# inside `_have` itself cannot match and be mistaken for a tool named `$1` — load-bearing.
#
# A NEW name showing up here is not an exception to add — it means a doctor row has no
# detection behind it, which is the bug.
# Pure zsh so it runs everywhere; _CORE_DOCTOR_GROUPS is the inventory the parity test above
# already proves equal to both renderers' output.
check "every core-doctor row has detection behind it (the exemption list is empty)" \
  'paired=(); missing=()
   for f in '"$HERE"'/zsh/00-tools.zsh '"$HERE"'/zsh/50-op.zsh; do
     for line in ${(f)"$(<$f)"}; do
       [[ $line =~ "^_have +([A-Za-z0-9_.-]+) +&& +HAVE_[A-Z0-9_]+=1" ]] && paired+=($match[1])
       [[ $line =~ "_CORE_PROBED\[([A-Za-z0-9_.-]+)\]=1" ]] && paired+=($match[1])
     done
   done
   (( ${#paired} >= 30 )) || { print -r -- "parsed only ${#paired} detection lines"; exit 1; }
   for ((gi = 2; gi <= ${#_CORE_DOCTOR_GROUPS}; gi += 2)); do
     for t in ${=_CORE_DOCTOR_GROUPS[gi]}; do
       (( ${paired[(I)$t]} )) || missing+=($t)
     done
   done
   (( ${#missing} == 0 )) || { print -r -- "doctor rows with no detection behind them: $missing"; exit 1; }'
# git-absorb is the first --json tools key that is NOT a bare identifier, and the JSON is
# hand-rolled by _core_doctor_json rather than produced by a serialiser — so the hyphen has
# to survive quoting on its own merit. The set-equality check above cannot see this: it
# compares the render against the JSON, so dropping the tool from BOTH literals still passes,
# and it never exercises a `true` value. Pin the key by name AND by value, with _core_have
# stubbed to match only git-absorb so one tool is true and the rest false — that also proves
# the emitter tracks detection per tool instead of painting the whole object one way.
check_dep "core-doctor --json emits the hyphenated git-absorb key and tracks its detection" python3 \
  '_core_have() { [[ "$1" == git-absorb ]]; }
   _core_doctor_present() { [[ "$1" == git-absorb ]]; }
   _CD_J="$(core-doctor --json)" python3 -c "
import json, os
tools = json.loads(os.environ[\"_CD_J\"])[\"tools\"]
assert \"git-absorb\" in tools, sorted(tools)
assert tools[\"git-absorb\"] is True, tools[\"git-absorb\"]
assert tools[\"eza\"] is False, tools[\"eza\"]
"'
# core-doctor "install missing" hint: the block is gated on _pkgup_mgr (from update.zsh,
# absent in this ui+functions harness) so the default render never reaches it. Stub the
# manager + force every tool ✗ (missing), then assert the copy-paste line renders AND the
# caveat points at PORTING-MATRIX.md rather than promising the package manager (or a single
# installer) can fetch everything — the regression guard for the unpackaged-tool guidance.
check "core-doctor 'install missing' hint points to PORTING-MATRIX.md for unpackaged tools" \
  '_pkgup_mgr() { print -r -- apt; }
   _core_have() { return 1; }
   _core_doctor_present() { return 1; }
   out=$(NO_COLOR=1 core-doctor 2>&1); (( $? == 0 )) \
     && [[ $out == *"install missing"* && $out == *"sudo apt install"* && $out == *"PORTING-MATRIX.md"* ]]'
# ...and the hint must NOT concatenate the manager verb with the tool list. That form read as
# paste-ready but never was: apt/dnf/zypper/pacman abort the whole transaction on one
# unresolvable name, and most of the inventory carries a package name that differs from the
# command (rg=ripgrep) or is unpackaged on some target. With _core_have false every tool is
# missing, so the old shape would render `sudo apt install eza bat …` — assert the verb is
# only ever followed by the <pkg> placeholder, and that the first tool name never trails it.
check "core-doctor's install hint offers a per-tool template, not a paste-ready batch command" \
  '_pkgup_mgr() { print -r -- apt; }
   _core_have() { return 1; }
   _core_doctor_present() { return 1; }
   out=$(NO_COLOR=1 core-doctor 2>&1); (( $? == 0 )) \
     && [[ $out == *"sudo apt install <pkg>"* ]] \
     && [[ $out != *"sudo apt install eza"* ]] \
     && [[ $out == *"command names"* ]]'
# _core_wired (U1): presence != wired. The probe is true ONLY when the integration's hook
# function is actually defined in this shell, and false for an idle/unknown one — that gap
# is exactly what the doctor's "integrations wired" line surfaces.
check "_core_wired detects an integration once its hook function exists" \
  'starship_precmd() { :; }; _core_wired starship'
check "_core_wired is false for an idle integration and an unknown name" \
  '_core_wired starship 2>/dev/null; (( $? != 0 )); _core_wired bogustool 2>/dev/null; (( $? != 0 ))'
# Upstream RENAMES the function its `init` emits, and Core sources that init verbatim — so a
# probe pinned to one spelling silently goes stale and reports a FALSE `○ (idle)` for a live
# integration (seen on starship 1.24.2 → prompt_starship_precmd, carapace-bin 1.5.7 →
# _carapace_completer; neither emits the historical name at all). Pin BOTH spellings per tool
# so dropping either fallback fails the audit instead of quietly recreating that bug.
check "_core_wired accepts starship's current hook name (prompt_starship_precmd)" \
  'prompt_starship_precmd() { :; }; _core_wired starship'
check "_core_wired accepts carapace's historical hook name (_carapace)" \
  '_carapace() { :; }; _core_wired carapace'
check "_core_wired accepts carapace's current hook name (_carapace_completer)" \
  '_carapace_completer() { :; }; _core_wired carapace'
check "_core_wired is false for an idle carapace" \
  '_core_wired carapace 2>/dev/null; (( $? != 0 ))'
# ── The wired list must not drift from the arms that implement it (#447) ──────────────
# _CORE_DOCTOR_WIRED is what BOTH renderers iterate; the `case` arms of _core_wired are what
# actually probe. Those were three hand-synced literals until this change, and — unlike the
# tool axis — nothing could see a drift: the render⇄json parity test above stubs _core_have
# false, which makes the "integrations wired" block skip every entry by construction. So the
# guard has to be built here, in both directions, because the two drifts are different bugs.
#
# The sentinel first, because the next assertion is vacuous without it: an unknown name must
# return exactly 2, not merely non-zero. Reverting that arm to `return 1` makes "no arm for
# this name" indistinguishable from "installed but idle" and silently disarms the check below.
check "_core_wired returns the distinct exit 2 for a name it has no arm for" \
  '_core_wired bogustool 2>/dev/null; (( $? == 2 ))'
# Direction 1 — every listed name has an arm. This is the drift that renders a WRONG report:
# a name in the array with no arm falls to `*)` and prints `○ (idle)` forever, on every box,
# no matter what the user installs or configures. Runtime, so it needs no source parsing.
# `_core_wired` is called with the hooks undefined, so a correctly-armed tool returns 1 here;
# only 2 is a failure.
check "every _CORE_DOCTOR_WIRED entry has a matching _core_wired arm" \
  'for t in $_CORE_DOCTOR_WIRED; do
     _core_wired "$t" 2>/dev/null
     (( $? == 2 )) && { print -r -- "no _core_wired arm for: $t"; exit 1; }
   done
   (( ${#_CORE_DOCTOR_WIRED} > 0 ))'
# Direction 2 — every arm is listed. This is the drift that renders a MISSING report: a tool
# gains a probe nobody iterates, so its wiredness is never shown and the omission is silent
# (exactly how twelve tools went unreported on the tool axis for releases). Not observable at
# runtime — an unlisted arm is unreachable by definition — so read the arms out of the source,
# the same technique as the "probed ⊆ reported" test above. Skips without python3, like its
# neighbours.
check_dep "every _core_wired arm appears in _CORE_DOCTOR_WIRED (no unreachable probes)" python3 \
  '_FN_SRC="'"$HERE"'/zsh/30-functions.zsh" _CD_W="$_CORE_DOCTOR_WIRED" python3 -c "
import os, re
src  = open(os.environ[\"_FN_SRC\"]).read()
body = re.search(r\"(?s)^_core_wired\\(\\) \\{.*?^\\}\", src, re.M).group(0)
arms = set(re.findall(r\"(?m)^  ([a-z][a-z0-9-]*)\\)\", body))
listed = set(os.environ[\"_CD_W\"].split())
assert arms, \"parsed no case arms out of _core_wired\"
assert not arms - listed, \"probed by _core_wired but never rendered: %s\" % sorted(arms - listed)
"'
# core-help (U5): the width-aware renderer must emit every verb and never crash on its
# kw arithmetic — including a pathologically narrow terminal where the key column clamps.
check "core-help renders all verbs (wide terminal)" \
  'out=$(COLUMNS=120 core-help 2>&1); (( $? == 0 )) && [[ $out == *mkcd* && $out == *"maint-install"* && $out == *serve* ]]'
check "core-help renders cleanly on a pathologically narrow terminal" \
  'out=$(COLUMNS=12 core-help 2>&1); (( $? == 0 )) && [[ $out == *mkcd* ]]'
# core-help <filter> (U4): a term shows ONLY matching rows (and drops the section
# scaffolding); an unmatched term reports it instead of printing an empty sheet.
check "core-help <term> filters to matching rows only" \
  'out=$(COLUMNS=120 core-help serve 2>&1); (( $? == 0 )) && [[ $out == *serve* && $out != *"maint-install"* ]]'
check "core-help reports when a filter matches nothing" \
  'out=$(COLUMNS=120 core-help zzzznope 2>&1); (( $? == 0 )) && [[ $out == *"no entries match"* ]]'
# U8: the git alias set (git.zsh) is now discoverable from the cheat sheet — the full
# view carries the git section, and a filter still narrows to a specific git row.
check "core-help surfaces the git alias section in the full sheet" \
  'out=$(COLUMNS=120 NO_COLOR=1 core-help 2>&1); (( $? == 0 )) && [[ $out == *"git (most-used"* && $out == *gpf* ]]'
check "core-help can filter to a git alias row" \
  'out=$(COLUMNS=120 NO_COLOR=1 core-help gpf 2>&1); (( $? == 0 )) && [[ $out == *gpf* && $out != *"maint-install"* ]]'
# Section-aware filter: a SECTION name (the completion offers these) surfaces its whole
# group even though the word appears in no row key/desc — e.g. `core-help keybindings`.
check "core-help filters by section name (keybindings → its rows, not others)" \
  'out=$(COLUMNS=120 NO_COLOR=1 core-help keybindings 2>&1); (( $? == 0 )) && [[ $out == *Ctrl-T* && $out != *"maint-install"* ]]'
check "core-help --help returns 0 (not mis-read as a filter)" \
  'out=$(core-help --help); (( $? == 0 )) && [[ $out == *"usage: core-help"* ]]'
# core umbrella dispatcher (B1): bare `core` is the cheat sheet (U6 — help, not an
# error), subcommands route to the core-* family, and an unknown subcommand fails in
# Core's voice with a did-you-mean against $_CORE_SUBCMDS.
check "core (no args) prints the cheat sheet (U6: bare core is help, not an error)" \
  'out=$(COLUMNS=120 core 2>&1); (( $? == 0 )) && [[ $out == *mkcd* && $out == *serve* ]]'
check "core help <term> routes to core-help and filters" \
  'out=$(COLUMNS=120 core help serve 2>&1); (( $? == 0 )) && [[ $out == *serve* && $out != *"maint-install"* ]]'
check "core version routes to core-version" \
  'out=$(core version); (( $? == 0 )) && [[ $out == "dotfiles-core "[0-9]* ]]'
check "core doctor routes to core-doctor" \
  'out=$(NO_COLOR=1 core doctor 2>&1); (( $? == 0 )) && [[ $out == *"modern CLI"* ]]'
check "core rejects an unknown subcommand with a did-you-mean" \
  'out=$(core verzion 2>&1); (( $? != 0 )) && [[ $out == *"did you mean core version"* ]]'
# Profile awareness (B1): under minimal/standard, 60-update is not loaded, so `up` is
# undefined. `core update` must report cleanly (mentioning CORE_PROFILE) rather than reach a
# missing command. Simulate the gated state by unfunction-ing `up` in a subshell.
check "core update reports cleanly when up is gated by CORE_PROFILE" \
  '( unfunction up 2>/dev/null; out=$(core update 2>&1); (( $? != 0 )) && [[ $out == *CORE_PROFILE* ]] )'
# U5: a usage error points back at the discoverability surface — `see: core-help <verb>`,
# the verb derived from the synopsis's first token, so every verb gets it for free.
check "usage errors carry a 'see: core-help <verb>' footer (U5)" \
  'out=$(serve 99999 2>&1); (( $? != 0 )) && [[ $out == *"see: core-help serve"* ]]'
check "the U5 usage footer is suppressible via CORE_USAGE_HINT=0" \
  'out=$(CORE_USAGE_HINT=0 serve 99999 2>&1); (( $? != 0 )) && [[ $out != *"see: core-help"* ]]'
# _core_suggest did-you-mean (U3/U1): nearest candidate on a near typo; SILENT when
# nothing is close or the input is too short to be a confident match.
check "_core_suggest returns the nearest flag for a near typo" \
  'out=$(_core_suggest --locl -l --local); [[ $out == "--local" ]]'
check "_core_suggest stays silent when nothing is close" \
  'out=$(_core_suggest zzzzzz -l --local); [[ -z $out ]]'
# Damerau/OSA (U12): an adjacent transposition scores 1, NOT 2 as plain Levenshtein would —
# guards the transposition path so a regression can't silently fall back to plain edit
# distance (which would drop near-miss suggestions like gts→gst back below the cutoff).
check "_core_lev scores an adjacent transposition as 1 (Damerau, not plain Levenshtein 2)" \
  '[[ $(_core_lev gts gst) == 1 ]]'
check "_core_suggest catches a transposition typo (gts → gst)" \
  'out=$(_core_suggest gts gst gco gaa); [[ $out == gst ]]'
# _core_errbox (U8): a ✗ headline line plus dim INDENTED body lines (plain when piped).
check "_core_errbox renders a headline and indented body lines" \
  'out=$(_core_errbox head why fix 2>&1); L=("${(@f)out}"); (( ${#L} == 3 )) && [[ ${L[1]} == *head* && ${L[2]} == "    why" && ${L[3]} == "    fix" ]]'
# _core_hint width-aware wrapping (U9): a known narrow width wraps with the
# continuation aligned under the text; an UNKNOWN width (non-tty, COLUMNS=0 here) must
# NOT wrap, so captured/logged hints stay one line (no regression for the other tests).
check "_core_hint stays one line when the terminal width is unknown" \
  'out=$(_core_hint install fzf, then retry 2>&1); L=("${(@f)out}"); (( ${#L} == 1 )) && [[ $out == *"hint: install"* ]]'
check "_core_hint wraps a long hint at a narrow COLUMNS with aligned continuation" \
  'out=$(COLUMNS=40 _core_hint alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima 2>&1); L=("${(@f)out}"); (( ${#L} >= 2 )) && [[ ${L[1]} == "  hint: "* && ${L[2]} == "        "* ]]'
check "extract rejects a non-existent file" \
  'extract /no/such/archive.tar.gz; (( $? != 0 ))'
check "extract rejects a known file of unknown format" \
  'd=$(mktemp -d); cd "$d"; : > mystery.qqq; extract mystery.qqq; (( $? != 0 ))'
check_dep "extract round-trips a .tar.gz" tar \
  'd=$(mktemp -d); cd "$d"; mkdir src; print -r -- hi > src/a.txt; tar czf a.tgz src; rm -rf src; extract a.tgz; [[ -f src/a.txt && "$(cat -- src/a.txt)" == hi ]]'
check_dep "extract round-trips a .gz" gzip \
  'd=$(mktemp -d); cd "$d"; print -r -- hi > f.txt; gzip f.txt; extract f.txt.gz; [[ -f f.txt && "$(cat -- f.txt)" == hi ]]'
# Defensive guards (U4): a multi-entry "tarbomb" must be flagged (with no TTY the
# contain-prompt declines and it extracts in place — both files land, we warned), and
# an extract that WOULD clobber an existing entry must abort untouched rather than
# silently overwrite. _core_confirm declining on no-TTY is what makes both deterministic.
check_dep "extract warns on a tarbomb but still unpacks (no TTY)" tar \
  'd=$(mktemp -d); cd "$d"; print x > one; print y > two; tar czf bomb.tgz one two; rm one two; extract bomb.tgz </dev/null; [[ -f one && -f two ]]'
check_dep "extract refuses to clobber an existing entry (no TTY)" tar \
  'd=$(mktemp -d); cd "$d"; mkdir src; print new > src/a.txt; tar czf a.tgz src; print OLD > src/a.txt; extract a.tgz </dev/null; rc=$?; [[ "$(cat -- src/a.txt)" == OLD && $rc -ne 0 ]]'
# gz/bz2 write NEXT TO the archive path, not into $PWD: `extract /dir/f.gz` must guard
# /dir/f, not ./f. Run it from a DIFFERENT cwd so a basename-only check would miss the
# clobber and overwrite (the bug this asserts against).
check_dep "extract guards the gz output at the archive's path, not \$PWD" gzip \
  'd=$(mktemp -d); sub="$d/sub"; mkdir -p "$sub"; print new > "$sub/f.txt"; gzip "$sub/f.txt"; print OLD > "$sub/f.txt"; cd "$d"; extract "$sub/f.txt.gz" </dev/null; rc=$?; [[ "$(cat -- "$sub/f.txt")" == OLD && $rc -ne 0 ]]'

# ── E. detection + UX unit tests (ui.zsh / update.zsh / maint.zsh) ────────────
# Sections A/B and audit-core.sh's static pass leave the highest-LOGIC, highest
# fan-out helpers unproven: the package-manager and scheduler detection LADDERS
# (which differ per distro and silently mis-fire) and ui.zsh's defensive no-TTY
# confirm. A regression in any of these ships to all nine OS repos — exactly what a
# behavioral gate must catch. Each is driven HERMETICALLY against a stubbed PATH
# (the same technique the clip ladder in section C uses), so the result is
# deterministic on every CI userland (glibc / BSD / musl) regardless of what's
# actually installed there.
hdr "detection + UX unit tests (ui / update / maint)"
_real_zsh="$(command -v zsh)"
UPD="$HERE/zsh/60-update.zsh"
MNT="$HERE/zsh/55-maint.zsh"
# A fake bin dir holding ONE stub command, used to pin a detection ladder's answer.
PMBIN="$SANDBOX/pmbin"
_pm_only() {
  rm -rf "$PMBIN"
  mkdir -p "$PMBIN"
  [[ -n "${1:-}" ]] && {
    printf '#!/bin/sh\n:\n' >"$PMBIN/$1"
    chmod +x "$PMBIN/$1"
  }
}

# Run a zsh assertion that must exit 0; on failure print the captured output indented
# (same diagnostics contract as check() above). Trailing args are `VAR=VAL` env prefixes
# applied to the child — used to isolate PATH for the detection ladders. Runs INTERACTIVE
# (-i): update.zsh gates its whole body behind `[[ $- == *i* ]]`, so a non-interactive
# `-fc` would source to a no-op. `$_real_zsh` (absolute) keeps zsh reachable even when
# the test isolates PATH down to the stub dir.
ucheck() { # ucheck <label> <zsh-body> [VAR=VAL ...]
  local label="$1" body="$2"
  shift 2
  local out
  # `env -u GHOSTTY_SHELL_FEATURES`, and it is NOT cosmetic. 00-tools.zsh stands the OSC 133
  # marks down when that variable is set and $TMUX is empty (line ~263), which is exactly the
  # environment every mark-ON case below pins: they pass TMUX= explicitly and say nothing
  # about Ghostty. A bare `env` inherits the caller's, so running `make audit` from a Ghostty
  # window — the reference terminal this repo ships a config for — cleared _CORE_OSC133,
  # left _core_osc133_prompt undefined, and red 7 assertions on a tree CI called green.
  # The section header already claims TERM and TMUX are pinned "wherever they matter"
  # BECAUSE env would otherwise leak the real values; this is the third variable that
  # reasoning applies to and it was the one missed.
  # Order is load-bearing: -u is an OPTION, "$@" the assignments after it, so cases (e)/(f)
  # setting GHOSTTY_SHELL_FEATURES=... explicitly still win over the unset.
  if out="$(HOME="$SANDBOX" env -u GHOSTTY_SHELL_FEATURES "$@" "$_real_zsh" -fic "$body" 2>&1)"; then
    pass "$label"
  else
    fail "$label"
    [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
}

# ui.zsh: _core_confirm is DEFENSIVE — with no controlling TTY (captured run, stdin
# redirected) it must DECLINE (non-zero), so wrapping a destructive action (please/up)
# in it is fail-safe in a pipe/cron/CI context instead of blocking or assuming yes.
ucheck "ui: _core_confirm declines with no TTY (fail-safe)" \
  "source '$UI'; _core_confirm 'x' </dev/null; (( \$? != 0 ))"

# ui.zsh: _core_spin must return the WRAPPED command's exit code (the non-TTY path
# runs it directly) — the contract plugins.zsh's first-run installer relies on to know
# a clone step failed. true → 0, false → non-zero.
ucheck "ui: _core_spin propagates the wrapped command's exit code" \
  "source '$UI'; _core_spin t true 2>/dev/null && ! _core_spin t false 2>/dev/null"

# ui.zsh: the spinner's animation loop must not become a BUSY loop when its pacing
# primitive stops pacing. _core_nap cannot report failure — it swallows both arms
# (`zselect … 2>/dev/null`, `sleep 0.1 2>/dev/null`) and always returns 0 — so a box with
# neither zsh/zselect nor a usable `sleep` silently turns a 100ms tick into an unthrottled
# spin that pegs a core for the whole wrapped command. Measured before the guard: 100% CPU
# for the command's full duration; after: 0%, same wall time, same exit status.
#
# Needs a REAL pty: _core_spin returns early unless stderr is a tty (`[[ ! -t 2 ]]` runs the
# command directly), so a captured run never reaches the loop at all — which is exactly how
# this went unnoticed. The command must also be a FUNCTION: with gum installed _core_spin
# delegates real binaries to `gum spin` and the hand-rolled loop is skipped.
#
# Also asserted: the guard leaves a STATIC "(still running…)" frame on its way out. Giving
# up on the animation must not mean going silent for the rest of the run — a stopped spinner
# and a wedged one look identical, and the wrapped command here still has seconds to go.
#
# Asserted on the ITERATION COUNT, not on CPU%: deterministic and CI-safe. With the guard,
# the loop stops animating just past 200; without it a broken nap runs six figures of
# iterations in the same window.
if have python3; then
  _spinout="$(python3 - "$UI" <<'PYSPIN' 2>/dev/null
import pty, os, sys, select, time, re
ui = sys.argv[1]
body = (
    "source %s; typeset -g NAPS=0; _core_nap(){ (( NAPS++ )); return 0 }; "
    "slowfn(){ sleep 3; return 7 }; _core_spin t slowfn; print RC=$?; print NAPS=$NAPS"
) % ui
pid, fd = pty.fork()
if pid == 0:
    os.execvp("zsh", ["zsh", "-f", "-i", "-c", body]); os._exit(1)
out, start = b"", time.time()
while time.time() - start < 60:
    r, _, _ = select.select([fd], [], [], 0.01)
    if r:
        try: d = os.read(fd, 262144)
        except OSError: break
        if not d: break
        out += d
    p, _st = os.waitpid(pid, os.WNOHANG)
    if p: break
else:
    os.kill(pid, 9)
txt = out.decode(errors="replace")
rc = re.findall(r"RC=(\d+)", txt)
naps = re.findall(r"NAPS=(\d+)", txt)
print("%s %s %s" % (rc[-1] if rc else "x", naps[-1] if naps else "x",
                    "STILL" if "still running" in txt else "SILENT"))
PYSPIN
  )"
  read -r _srrc _srnaps _srstill <<<"$_spinout"
  if [[ "$_srrc" == 7 && "$_srnaps" =~ ^[0-9]+$ ]] && ((_srnaps <= 250)); then
    pass "ui: _core_spin stops animating instead of busy-spinning when _core_nap cannot pace (naps=$_srnaps, rc=$_srrc)"
  else
    fail "ui: _core_spin busy-spins when _core_nap cannot pace (rc=$_srrc naps=$_srnaps; want rc=7 and naps<=250)"
  fi
  if [[ "$_srstill" == STILL ]]; then
    pass "ui: _core_spin leaves a '(still running…)' frame when the busy-spin guard fires"
  else
    fail "ui: _core_spin goes silent after the busy-spin guard fires (want a static '(still running…)' frame)"
  fi
else
  skip "_core_spin busy-loop guard (python3 absent — needs a pty to reach the animation loop)"
fi

# lib/ux.sh: ux_spin's loop body must be NORMALISED, because this library is SOURCED by
# callers running `set -euo pipefail` (bootstrap.sh is one). A bare command that fails inside
# the loop therefore kills the CALLER, not just the animation — and the case that matters is
# precisely the one the busy-spin guard above exists for: with a `sleep` that exits non-zero,
# an unnormalised `sleep 0.1` aborted the whole shell at 127 before the spin counter was ever
# incremented, so the guard could not run, the wrapped child was left running, and the cursor
# stayed hidden. Same pty requirement as above (ux_spin runs the command directly when stdout
# is not a tty, never reaching the loop), so this is python3-gated too.
if have python3; then
  _uxout="$(python3 - "$HERE/lib/ux.sh" <<'PYUX' 2>/dev/null
import pty, os, sys, select, time, re
ux = sys.argv[1]
# The wrapped command must SUCCEED and ux_spin must be called BARE. Both matter:
# `ux_spin … || rc=$?` puts the call in a tested context, which suspends `set -e` for the
# whole function body — so the very condition under test would be switched off, and the
# check would pass no matter what (it did, until this was corrected). A bare call keeps
# `set -e` live, and a succeeding command means the ONLY thing that can abort the script
# is the unnormalised pacing failure inside the loop.
script = (
    "set -euo pipefail\n"
    "source %s\n"
    "sleep() { return 127; }\n"          # pacing primitive absent / rejecting
    "fn() { command sleep 2; return 0; }\n"
    "ux_spin lbl fn\n"                   # BARE: set -e stays in force
    "echo UXRC=$?\n"
    "echo UXEND\n"
) % ux
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", "-c", script]); os._exit(1)
out, start = b"", time.time()
while time.time() - start < 60:
    r, _, _ = select.select([fd], [], [], 0.01)
    if r:
        try: d = os.read(fd, 262144)
        except OSError: break
        if not d: break
        out += d
    p, _st = os.waitpid(pid, os.WNOHANG)
    if p: break
else:
    os.kill(pid, 9)
txt = out.decode(errors="replace")
rc = re.findall(r"UXRC=(\d+)", txt)
print("%s %s %s" % (rc[-1] if rc else "x", "END" if "UXEND" in txt else "NOEND",
                    "STILL" if "still running" in txt else "SILENT"))
PYUX
  )"
  read -r _uxrc _uxend _uxstill <<<"$_uxout"
  if [[ "$_uxrc $_uxend" == "0 END" ]]; then
    pass "ux: ux_spin survives a failing pacing primitive under a 'set -e' sourcer"
  else
    fail "ux: a failing pacing primitive kills a 'set -e' caller of ux_spin (got '${_uxrc} ${_uxend}', want '0 END')"
  fi
  # Same guard-trip, same requirement as _core_spin's mirror above: ux_spin CLEARS the line
  # before `wait`, so without a static frame it shows nothing at all for the rest of the run
  # — the hang it cannot distinguish itself from. This is the stricter of the two cases.
  if [[ "$_uxstill" == STILL ]]; then
    pass "ux: ux_spin leaves a '(still running…)' frame when the busy-spin guard fires"
  else
    fail "ux: ux_spin goes silent after the busy-spin guard fires (want a static '(still running…)' frame)"
  fi

  # …and the COMMON path — a working `sleep`, guard never trips — must survive `set -e` too.
  # The case above only ever exercises the degraded branch, so every post-loop statement on
  # the happy path (cursor restore, the guard's own test, the ✓ frame, `rm -f`) was untested
  # under the very discipline this file is written for. That gap is not theoretical: an
  # arithmetic guard written as `((_degraded)) && { … }` returns 1 whenever _degraded is 0,
  # which is the normal case, and a future edit that moves it out of &&-list position (into a
  # bare statement, or a `local x=$((…))`) kills the caller on every successful spin.
  if have python3; then
    _uxok="$(python3 - "$HERE/lib/ux.sh" <<'PYUXOK' 2>/dev/null
import pty, os, sys, select, time, re
ux = sys.argv[1]
script = (
    "set -euo pipefail\n"
    "source %s\n"
    "fn() { command sleep 1; return 0; }\n"   # real sleep: the guard must NOT trip
    "ux_spin lbl fn\n"                        # BARE: set -e stays in force
    "echo UXRC=$?\n"
    "echo UXEND\n"
) % ux
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", "-c", script]); os._exit(1)
out, start = b"", time.time()
while time.time() - start < 60:
    r, _, _ = select.select([fd], [], [], 0.01)
    if r:
        try: d = os.read(fd, 262144)
        except OSError: break
        if not d: break
        out += d
    p, _st = os.waitpid(pid, os.WNOHANG)
    if p: break
else:
    os.kill(pid, 9)
txt = out.decode(errors="replace")
rc = re.findall(r"UXRC=(\d+)", txt)
print("%s %s %s" % (rc[-1] if rc else "x", "END" if "UXEND" in txt else "NOEND",
                    "STILL" if "still running" in txt else "QUIET"))
PYUXOK
    )"
    if [[ "$_uxok" == "0 END QUIET" ]]; then
      pass "ux: a normal ux_spin run survives 'set -e' and prints no degraded frame"
    else
      fail "ux: a normal ux_spin run under 'set -e' (got '${_uxok}', want '0 END QUIET')"
    fi
  fi
else
  skip "ux_spin set -e normalisation (python3 absent — needs a pty to reach the animation loop)"
fi

# ui.zsh: _core_nap is the spinner's per-frame delay primitive — it must return 0
# (the while-loop relies on it not aborting) and complete promptly via zselect WITHOUT
# forking a fractional `sleep` that busybox may reject. We can't time it portably here,
# but asserting it succeeds exercises the zselect path on every CI userland (glibc/musl)
# — the bare-box regression the old literal `sleep 0.1` risked. Driven without a TTY.
ucheck "ui: _core_nap completes and returns 0 (zselect tick, no fractional sleep fork)" \
  "source '$UI'; _core_nap; (( \$? == 0 ))"

# functions.zsh: the command-not-found handler (U1) is defined ONLY in an interactive
# shell (ucheck runs -fic), and on a near typo it must suggest the closest Core verb in
# Core's voice rather than zsh's terse default. extarct → extract is a 1-transposition miss.
ucheck "fn: command_not_found_handler suggests the nearest Core verb on a typo" \
  "source '$UI'; source '$FN'; out=\$(extarct foo 2>&1); [[ \$out == *'did you mean extract'* ]]"

# update.zsh: _pkgup_mgr must pick the manager that's actually on PATH. Isolate PATH to
# a lone apt-get stub (so the brew/pacman/dnf/zypper arms above it all miss) and disable
# the two background startup hooks, so the answer is deterministic on any runner.
_pm_only apt-get
ucheck "update: _pkgup_mgr detects apt from an isolated PATH" \
  "source '$UPD'; [[ \$(_pkgup_mgr) == apt ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# …and reports `none` when NO supported manager is reachable (the silent-stay path).
_pm_only ""
ucheck "update: _pkgup_mgr reports none on a bare PATH" \
  "source '$UPD'; [[ \$(_pkgup_mgr) == none ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# The startup hook's CLAIM-SLOT write must leave a POSITIONALLY WELL-FORMED cache, i.e.
# "-1\n<epoch>" and never "\n<epoch>". The hook persists whatever $count holds, and on the
# first shell of a fresh box there is no cache at all, so an unnormalised (or normalised-to-
# empty) count wrote a file whose first line was blank — the exact shape that, read back
# with an UNQUOTED (f) split, slides the epoch into the count slot and prints "1786128391
# updates available". The reader-side quoting is one half of the fix; this asserts the other.
#
# Deterministic against the refresh the hook backgrounds a line later: the stub `brew` sleeps,
# and _pkgup_count calls it twice, so the claim write is what is on disk when we look. The
# stub dir is PREPENDED to the real PATH (not isolated to it) because the hook needs `mkdir`;
# brew is first in _pkgup_mgr's ladder, so the stub still wins on any host.
#
# NOT ucheck, deliberately — this is the one update.zsh case that leaves the startup hook
# ENABLED, so it is the only one that forks the refresh. ucheck captures with `$(…)`, and a
# command substitution reads until the pipe's LAST writer closes: the disowned `&|` refresh
# inherits that pipe, so bash would sit there for as long as the stub sleeps even though the
# assertion finished in microseconds. Measured: 60.0s via ucheck, 8ms redirected to a file,
# same verdict — and it would have been paid on every leg of the CI matrix. Redirecting to a
# file means the parent waits only for the zsh it actually started. The stub's sleep is now
# just "comfortably longer than the assertion window", not a cost.
_PKGUPT="$SANDBOX/pkgup-claim"
rm -rf "$_PKGUPT"
mkdir -p "$_PKGUPT/bin" "$_PKGUPT/cache/zsh"
printf '#!/bin/sh\nsleep 10\n' >"$_PKGUPT/bin/brew"
chmod +x "$_PKGUPT/bin/brew"
if HOME="$SANDBOX" env PATH="$_PKGUPT/bin:$PATH" XDG_CACHE_HOME="$_PKGUPT/cache" CORE_WELCOME=0 \
  "$_real_zsh" -fic "source '$UPD'
   c=\$XDG_CACHE_HOME/zsh/pkg-updates
   [[ -r \$c ]] || { print -u2 'no cache written'; exit 1 }
   local -a l; l=(\"\${(@f)\$(<\$c)}\")
   [[ \${l[1]} == -1 ]] || { print -u2 \"count slot is '\${l[1]}', want -1\"; exit 1 }
   [[ \${l[2]} == <-> ]] || { print -u2 \"epoch slot is '\${l[2]}'\"; exit 1 }
   [[ -z \$(_pkgup_notice) ]]" >"$_PKGUPT/out" 2>&1; then
  pass "update: the claim-slot write leaves a well-formed cache (-1, not an empty count)"
else
  fail "update: the claim-slot write leaves a well-formed cache (-1, not an empty count)"
  [[ -s "$_PKGUPT/out" ]] && sed 's/^/    /' "$_PKGUPT/out" >&2
fi
# up --help must print usage and return 0 WITHOUT attempting an update — the bug the
# help guard fixes (it used to fall through, not being -y, and run the upgrade). Run
# on a bare PATH so a regressed guard reaching _pkgup_mgr → none → returns 1, failing
# this test loudly instead of silently passing.
_pm_only ""
ucheck "update: up --help returns 0 and does not attempt an update" \
  "source '$UI'; source '$UPD'; out=\$(up --help); (( \$? == 0 )) && [[ \$out == *'usage: up'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# up's pre-confirm PREVIEW: _pkgup_list surfaces the upgradable package NAMES (the
# count is already in the nudge) so `up` shows what will change before the destructive
# sync. Stub apt-get's `-s upgrade` simulate output; mgr pins to apt via isolated PATH.
rm -rf "$PMBIN"
mkdir -p "$PMBIN"
printf '#!/bin/sh\ncase "$*" in *"-s upgrade"*) printf "Inst foo [1.0] (1.1)\\nInst bar [2.0] (2.1)\\n";; esac\n' >"$PMBIN/apt-get"
chmod +x "$PMBIN/apt-get"
# The apt arm pipes to awk; the isolated PATH has only the stub, so symlink the real
# awk in (like the clip ladder symlinks bash/tr). It's not a package manager, so
# _pkgup_mgr still resolves to apt — the isolation we want.
ln -s "$(command -v awk)" "$PMBIN/awk"
ucheck "update: _pkgup_list surfaces upgradable package names (apt)" \
  "source '$UPD'; out=\$(_pkgup_list); [[ \$out == *foo* && \$out == *bar* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0

# REGRESSION (stdin): the probes must be UNPROMPTABLE. They run with stdout captured by
# $(...) and stderr discarded, so a package manager that stops to ask a question writes it
# where nobody can see and then blocks on the terminal forever — `up` printing "Complete!"
# and never returning, because _pkgup_refresh runs _pkgup_count in the FOREGROUND after the
# upgrade. (Live case: dnf5 keys repos per user under <cachedir>/<repo>/pubring, so a repo
# with repo_gpgcheck=1 whose key only reached root's keyring re-prompts every non-root
# --refresh, forever, since a declined import is never persisted.)
#
# The guard is `esac </dev/null` INSIDE each function. It deliberately is not on the function
# definition: `f() { ... } </dev/null` binds at definition time in zsh and does nothing at
# call time, which looks identical in review and fixes nothing — these tests are what tell
# the two apart.
#
# Asserted as "the probe did not EAT the caller's stdin" rather than "the probe did not
# hang": same property (an unpinned probe reaches the caller's stdin; a pinned one cannot),
# but it FAILS on regression instead of hanging. This harness has no timeout, so a test that
# detected the hang by hanging would wedge the suite rather than report it. The stub reads a
# line, so an unpinned probe swallows the sentinel and the outer read comes up empty.
rm -rf "$PMBIN"
mkdir -p "$PMBIN"
printf '#!/bin/sh\nprintf "Import key? [y/N]: "\nread -r a\nprintf "Inst foo [1.0] (1.1)\\n"\n' >"$PMBIN/apt-get"
chmod +x "$PMBIN/apt-get"
ln -s "$(command -v awk)" "$PMBIN/awk"
ln -s "$(command -v grep)" "$PMBIN/grep"
ucheck "update: _pkgup_count cannot consume the caller's stdin (unpromptable)" \
  "source '$UPD'; printf 'sentinel\\n' | { _pkgup_count >/dev/null; read -r l; [[ \$l == sentinel ]] }" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "update: _pkgup_list cannot consume the caller's stdin (unpromptable)" \
  "source '$UPD'; printf 'sentinel\\n' | { _pkgup_list >/dev/null; read -r l; [[ \$l == sentinel ]] }" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# Put the fixture back the way the checks below expect it. $PMBIN is shared state, and the
# stub above is the one thing in this file that BLOCKS: leaving it in place hands a prompting
# apt-get to every later check, including the startup-hook ones that run _pkgup_refresh with
# UPDATE_CHECK_ENABLED=1. With the stdin pin they survive it; without it they wedge the whole
# suite instead of failing the two tests above — which is exactly backwards for a regression
# test whose job is to report this bug.
rm -rf "$PMBIN"
mkdir -p "$PMBIN"
printf '#!/bin/sh\ncase "$*" in *"-s upgrade"*) printf "Inst foo [1.0] (1.1)\\nInst bar [2.0] (2.1)\\n";; esac\n' >"$PMBIN/apt-get"
chmod +x "$PMBIN/apt-get"
ln -s "$(command -v awk)" "$PMBIN/awk"
# REGRESSION (prompt_subst): _pkgup_notice prints its 'run up to apply' nudge via
# `print -P`. Under `setopt prompt_subst` (starship and any substitution prompt enable
# it) print -P performs command substitution on a backtick'd word — so a literal \`up\`
# in the string would RUN the up function at prompt-paint time. The nudge fires from a
# precmd hook BEFORE up() is even defined, surfacing as "command not found: up" (and, once
# defined, silently triggering a privileged upgrade prompt every shell). Define an up()
# sentinel, enable prompt_subst, seed a positive cached count, and assert the rendered
# nudge MENTIONS up but never EXECUTED it.
ucheck "update: _pkgup_notice nudge is prompt_subst-safe (mentions up, never runs it)" \
  "source '$UPD'; setopt prompt_subst; up(){ print RAN_UP }; mkdir -p \${_PKGUP_CACHE:h}; print -rl -- 3 \$EPOCHSECONDS >| \$_PKGUP_CACHE; out=\$(_pkgup_notice); [[ \$out == *\"run 'up'\"* && \$out != *RAN_UP* ]]" \
  XDG_CACHE_HOME="$SANDBOX/psubst-notice" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# REGRESSION (positional cache parse): _PKGUP_CACHE is "<count>\n<epoch>", read with a
# (f) split. Unquoted, zsh DROPS empty fields — so a cache whose count line is empty
# collapses to one element and the EPOCH shifts into the count slot. It then passes the
# <1-> test (an epoch IS a positive integer) and renders as "1786128391 updates available".
#
# Where the empty count comes from: NOT _pkgup_refresh, which normalises an empty result
# to -1 (`: "${n:=-1}"`). It is the startup hook's claim-slot write — on the first shell of
# a fresh box there is no cache, so $count is empty and the claim persists "\n<epoch>"
# while the background refresh is still in flight. Seed exactly that shape and assert the
# nudge stays SILENT.
ucheck "update: _pkgup_notice ignores an empty-count cache (epoch must not become the count)" \
  "source '$UPD'; mkdir -p \${_PKGUP_CACHE:h}; print -rl -- '' \$EPOCHSECONDS >| \$_PKGUP_CACHE; out=\$(_pkgup_notice); [[ -z \$out ]]" \
  XDG_CACHE_HOME="$SANDBOX/emptycount-notice" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# …and the healthy two-line cache still renders, so the quoting fix didn't just mute it.
ucheck "update: _pkgup_notice still renders a real cached count" \
  "source '$UPD'; mkdir -p \${_PKGUP_CACHE:h}; print -rl -- 7 \$EPOCHSECONDS >| \$_PKGUP_CACHE; out=\$(_pkgup_notice); [[ \$out == *'7 updates available'* ]]" \
  XDG_CACHE_HOME="$SANDBOX/goodcount-notice" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# The STARTUP HOOK has its own copy of the same positional read, and it is the one that
# matters: it decides the throttle AND writes the count back when it claims the slot, so an
# unquoted split there both re-fires the check every shell and PERSISTS the epoch as the
# count. _pkgup_notice tests cannot see that — they'd pass with this reader still broken.
# Seed the poisoned shape with a RECENT epoch: parsed correctly, `last` is now and the
# throttle must suppress any refresh, leaving the cache byte-identical. Parsed unquoted,
# `last` collapses to empty ⇒ 0, the window looks elapsed, and the claim-slot write fires
# and rewrites the file. Assert it is untouched.
ucheck "update: startup hook reads the cache positionally (empty count can't defeat the throttle)" \
  "zmodload zsh/datetime; mkdir -p \$XDG_CACHE_HOME/zsh; _c=\$XDG_CACHE_HOME/zsh/pkg-updates; print -rl -- '' \$EPOCHSECONDS >| \$_c; _before=\$(<\$_c); source '$UPD'; sleep 0.3; [[ \$(<\$_c) == \$_before ]]" \
  XDG_CACHE_HOME="$SANDBOX/hook-emptycount" UPDATE_CHECK_ENABLED=1 PATH="$PMBIN:$PATH" CORE_WELCOME=0
# Control: with a STALE epoch the same hook SHOULD claim the slot, so the assertion above
# is proving the throttle works, not that the hook is inert.
ucheck "update: startup hook still refreshes once the throttle window has elapsed" \
  "zmodload zsh/datetime; mkdir -p \$XDG_CACHE_HOME/zsh; _c=\$XDG_CACHE_HOME/zsh/pkg-updates; print -rl -- 5 1 >| \$_c; _before=\$(<\$_c); source '$UPD'; sleep 0.3; [[ \$(<\$_c) != \$_before ]]" \
  XDG_CACHE_HOME="$SANDBOX/hook-stale" UPDATE_CHECK_ENABLED=1 PATH="$PMBIN:$PATH" CORE_WELCOME=0
# up --dry-run (#8): the non-destructive inspect — list what WOULD upgrade and exit 0,
# applying nothing. Same apt stub as above; assert the names print and the rc is 0.
ucheck "update: up --dry-run lists pending packages and exits 0 (applies nothing)" \
  "source '$UI'; source '$UPD'; out=\$(up --dry-run); (( \$? == 0 )) && [[ \$out == *foo* && \$out == *bar* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# up strict flag parsing: every arg is parsed (not just $1), so an unknown flag is
# REJECTED in Core's voice (rc 1 — the verb-layer usage-error convention, same as
# serve/mkcd/…) instead of silently falling through to a real, privileged update —
# and -y/-n together (apply vs inspect-only) is refused as contradictory. Both
# rejections happen BEFORE _pkgup_mgr, so the manager doesn't matter.
ucheck "update: up rejects an unknown flag (rc 1, does not attempt an update)" \
  "source '$UI'; source '$UPD'; out=\$(up --bogus 2>&1); (( \$? == 1 )) && [[ \$out == *'unexpected argument'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "update: up refuses -y and -n together (mutually exclusive, rc 1)" \
  "source '$UI'; source '$UPD'; out=\$(up -y -n 2>&1); (( \$? == 1 )) && [[ \$out == *'mutually exclusive'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# up -i interactive selection (U2): contracts checked BEFORE any privileged apply.
# (a) -i is mutually exclusive with -y/-n; (b) with NO picker it errbox-names fzf/gum;
# (c) with a picker but no TTY it declines for the terminal; (d) --help advertises -i.
# (b)/(c) are kept DISTINCT so the message never conflates the two (Copilot, PR #15).
ucheck "update: up refuses -i with -y (three-way mutual exclusion, rc 1)" \
  "source '$UI'; source '$UPD'; out=\$(up -i -y 2>&1); (( \$? == 1 )) && [[ \$out == *'mutually exclusive'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# (b) no fzf AND no gum on the isolated PATH → the picker errbox, not a TTY/cancel message.
ucheck "update: up -i names fzf/gum when no picker is installed" \
  "source '$UI'; source '$UPD'; out=\$(up -i </dev/null 2>&1); (( \$? == 1 )) && [[ \$out == *'needs fzf or gum'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# (c) stub a picker (fzf) onto the isolated PATH so the picker check passes; a non-TTY run
# must then decline with the TERMINAL message — proving the two failure modes are separate.
printf '#!/bin/sh\n:\n' >"$PMBIN/fzf"
chmod +x "$PMBIN/fzf"
ucheck "update: up -i with a picker present still declines without a TTY" \
  "source '$UI'; source '$UPD'; out=\$(up -i </dev/null 2>&1); (( \$? == 1 )) && [[ \$out == *'needs an interactive terminal'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
rm -f "$PMBIN/fzf"
ucheck "update: up --help advertises -i/--interactive" \
  "source '$UI'; source '$UPD'; out=\$(up --help); (( \$? == 0 )) && [[ \$out == *'-i'* && \$out == *interactive* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# up -i must REFUSE on full-sync-only managers (pacman/emerge/apk): a partial upgrade there
# risks a broken system, so the safety model (documented in update.zsh) forbids it. Stub a
# pacman-only PATH so _pkgup_mgr resolves to it, then assert the refusal + rc 1.
_pm_only pacman
ucheck "update: up -i refuses on pacman (full-sync-only safety, rc 1)" \
  "source '$UI'; source '$UPD'; out=\$(up -i 2>&1); (( \$? == 1 )) && [[ \$out == *'does not support safe partial upgrades'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# core-help context-awareness (U7): a row whose tool is ABSENT on this box must be
# tagged "needs <tool>", while an always-on verb (mkcd) still renders normally. Drive
# it on a bare PATH so fzf is guaranteed missing, making the assertion deterministic.
_pm_only ""
ucheck "core-help annotates an unavailable tool (needs fzf when fzf absent)" \
  "source '$UI'; source '$FN'; out=\$(COLUMNS=120 NO_COLOR=1 core-help); [[ \$out == *'needs fzf'* && \$out == *mkcd* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# fzf.zsh verbs (fif/fbr) must degrade in Core's voice on a bare box — a raw "command
# not found" is the bug this guards (fcd already did; fif/fbr/zoxide-jump did not).
# Drive on an isolated PATH (fzf guaranteed absent) so the error path is deterministic.
FZF_FILE="$HERE/zsh/35-fzf.zsh"
_pm_only ""
ucheck "fif rejects cleanly without fzf (Core error voice, not 'command not found')" \
  "source '$UI'; source '$FZF_FILE' 2>/dev/null; out=\$(fif foo 2>&1); (( \$? != 0 )) && [[ \$out == *'fif: requires fzf'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "fbr rejects cleanly without fzf (Core error voice, not 'command not found')" \
  "source '$UI'; source '$FZF_FILE' 2>/dev/null; out=\$(fbr 2>&1); (( \$? != 0 )) && [[ \$out == *'fbr: requires fzf'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# zle-widget graceful degradation (regression gate for the Ctrl-T/Ctrl-R bare-box bug):
# both are bound UNCONDITIONALLY in bindings.zsh, so on a box without fzf/fd their widget
# bodies must warn in Core's voice and repaint — NOT leak a raw "command not found" (the
# class of bug fif/fbr/Alt-Z already guard; Ctrl-T/Ctrl-R lacked it). `zle` is stubbed to a
# no-op so `zle reset-prompt` is callable outside an active ZLE; PATH is isolated so fzf/fd
# are guaranteed absent. Alt-Z is asserted too, locking in the parity across all three.
_pm_only ""
ucheck "Ctrl-T widget degrades in Core's voice without fzf/fd (no 'command not found')" \
  "source '$UI'; source '$FZF_FILE' 2>/dev/null; zle() { : }; FD_BIN=''; out=\$(_fzf_file_no_hidden 2>&1); (( \$? != 0 )) && [[ \$out == *'Ctrl-T: needs'* && \$out != *'command not found'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "Ctrl-R widget degrades in Core's voice without fzf (no 'command not found')" \
  "source '$UI'; source '$FZF_FILE' 2>/dev/null; zle() { : }; out=\$(_fzf_history_clean 2>&1); (( \$? != 0 )) && [[ \$out == *'Ctrl-R: needs'* && \$out != *'command not found'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "Alt-Z widget degrades in Core's voice without zoxide/fzf (no 'command not found')" \
  "source '$UI'; source '$FZF_FILE' 2>/dev/null; zle() { : }; out=\$(_fzf_zoxide_jump 2>&1); (( \$? != 0 )) && [[ \$out == *'Alt-Z: needs'* && \$out != *'command not found'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# Colour degradation (U8): the nudge/welcome accents must drop from 24-bit hex to a
# 256-colour code when the terminal doesn't advertise truecolor — so a 16/256-colour
# TTY never receives a raw 24-bit escape. Assert both arms of the $COLORTERM gate.
ucheck "update: accents degrade to 256-colour without truecolor" \
  "source '$UPD'; [[ \$_PKGUP_ACCENT == 75 && \$_PKGUP_MUTED == 244 ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0 COLORTERM=
ucheck "update: accents use truecolor hex when COLORTERM advertises it" \
  "source '$UPD'; [[ \$_PKGUP_ACCENT == '#7aa2f7' ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0 COLORTERM=truecolor

# ── terminal-browser detection ladder (00-tools.zsh) + web/$BROWSER wiring (20-aliases.zsh) ──
# 00-tools.zsh resolves BROWSER_BIN (w3m preferred, then lynx/links2/links/elinks) and
# 20-aliases.zsh turns it into the `web` verb plus a HEADLESS-ONLY $BROWSER export. A
# regression here fans out to every OS repo, so pin the whole ladder + consumer
# hermetically against a stubbed PATH — the same isolation the pkg-mgr ladder uses.
# DISPLAY/WAYLAND_DISPLAY/OSTYPE are set INSIDE the body (zsh re-derives OSTYPE at
# startup, so an env prefix wouldn't stick) to drive the headless/GUI/macOS branches.
TOOLS_FILE="$HERE/zsh/00-tools.zsh"
ALIASES_FILE="$HERE/zsh/20-aliases.zsh"
BRBIN="$SANDBOX/brbin"
_br_only() { # _br_only [browser-name ...] — stub these onto an otherwise-empty bin dir
  rm -rf "$BRBIN"
  mkdir -p "$BRBIN"
  local n
  for n in "$@"; do
    printf '#!/bin/sh\n:\n' >"$BRBIN/$n"
    chmod +x "$BRBIN/$n"
  done
}
# (a) PRECEDENCE — w3m wins even when other text browsers are also present.
_br_only lynx w3m links
ucheck "browser: w3m takes precedence over other text browsers" \
  "source '$TOOLS_FILE'; [[ \$BROWSER_BIN == w3m && -n \${HAVE_BROWSER:-} ]]" \
  PATH="$BRBIN"
# (b) FALLBACK — with w3m absent, resolve the next present browser in the ladder.
_br_only lynx
ucheck "browser: falls back to lynx when w3m is absent" \
  "source '$TOOLS_FILE'; [[ \$BROWSER_BIN == lynx && -n \${HAVE_BROWSER:-} ]]" \
  PATH="$BRBIN"
# (c) NONE — no browser at all → HAVE_BROWSER stays unset and no `web` alias is defined.
_br_only
ucheck "browser: no browser present → HAVE_BROWSER unset, no web alias (graceful no-op)" \
  "source '$TOOLS_FILE'; source '$ALIASES_FILE'; [[ -z \${HAVE_BROWSER:-} ]] && ! (( \$+aliases[web] ))" \
  PATH="$BRBIN"
# (d) HEADLESS — no DISPLAY/WAYLAND_DISPLAY, non-macOS → `web` defined AND $BROWSER exported.
_br_only w3m
ucheck "browser: headless box defines web and exports \$BROWSER=w3m" \
  "DISPLAY=''; WAYLAND_DISPLAY=''; OSTYPE=linux-gnu; source '$TOOLS_FILE'; source '$ALIASES_FILE'; (( \$+aliases[web] )) && [[ \$BROWSER == w3m ]]" \
  PATH="$BRBIN"
# (e) GUI — a live \$DISPLAY must keep `web` but leave \$BROWSER untouched (no hijack).
ucheck "browser: a GUI \$DISPLAY keeps web but leaves \$BROWSER unset" \
  "DISPLAY=':0'; WAYLAND_DISPLAY=''; OSTYPE=linux-gnu; source '$TOOLS_FILE'; source '$ALIASES_FILE'; (( \$+aliases[web] )) && [[ -z \${BROWSER:-} ]]" \
  PATH="$BRBIN"
# (f) macOS — always a GUI, so \$BROWSER stays unset even when it looks headless.
ucheck "browser: macOS (OSTYPE=darwin) leaves \$BROWSER unset even with no DISPLAY" \
  "DISPLAY=''; WAYLAND_DISPLAY=''; OSTYPE=darwin24; source '$TOOLS_FILE'; source '$ALIASES_FILE'; (( \$+aliases[web] )) && [[ -z \${BROWSER:-} ]]" \
  PATH="$BRBIN"

# ── renamed binaries: fd/bat symmetry + an honest doctor (#418) ──────────────
# Debian/Ubuntu/Kali ship fd as `fdfind` and bat as `batcat`. 00-tools.zsh resolves both
# into FD_BIN/BAT_BIN, but the two were then handled ASYMMETRICALLY: 20-aliases.zsh gave
# fd an alias under its canonical name and bat none, so `bat` was untypeable on those
# boxes — and core-doctor reported `✗ bat` two lines above a `resolved` section printing
# `bat → batcat`. The ✓ that fd got was itself accidental: it came from zsh's `command -v`
# resolving the ALIAS, not from PATH, which is why `core-doctor -v` still printed a bare
# versionless `✓ fd` there (the probe forks `"$bin" --version`, a parameter expansion, and
# parameters are never alias-expanded — the error was swallowed by the pipeline).
# Both halves are pinned here against a stubbed PATH, hermetically, because a regression
# fans out to all nine OS repos and is invisible on macOS where the names are canonical.
RNBIN="$SANDBOX/rnbin"
_real_grep="$(command -v grep)"
_real_head="$(command -v head)"
_rn_only() { # _rn_only [binary-name ...] — stub these onto an otherwise-empty bin dir
  rm -rf "$RNBIN"
  mkdir -p "$RNBIN"
  local n
  for n in "$@"; do
    printf '#!/bin/sh\necho "%s 0.24.0"\n' "$n" >"$RNBIN/$n"
    chmod +x "$RNBIN/$n"
  done
  # grep/head are linked in, not stubbed: `core-doctor -v` pipes each tool's --version
  # through them, so case (c) cannot run on a PATH that lacks them. Linking the real ones
  # keeps the dir hermetic for the names that MATTER — a stubbed batcat/fdfind/bat/fd
  # still wins by precedence, and no real bat/fd from /usr/bin can leak in and hand the
  # version assertion someone else's release number on a Fedora or Debian runner.
  ln -sf "$_real_grep" "$RNBIN/grep"
  ln -sf "$_real_head" "$RNBIN/head"
}
# (a) SYMMETRY — the issue itself: on Debian names, BOTH tools are typeable canonically.
_rn_only batcat fdfind
ucheck "renamed: Debian names → alias bat=batcat AND alias fd=fdfind (symmetric)" \
  "source '$TOOLS_FILE'; source '$ALIASES_FILE'; [[ \${aliases[bat]} == batcat && \${aliases[fd]} == fdfind ]]" \
  PATH="$RNBIN"
# (b) HONEST DOCTOR — and it must NOT depend on (a). 20-aliases.zsh is deliberately NOT
# sourced here, so a ✓ can only come from _core_doctor_bin resolving $BAT_BIN/$FD_BIN.
ucheck "renamed: core-doctor --json reports bat/fd present without the aliases loaded" \
  "source '$TOOLS_FILE'; source '$UI'; source '$FN'; j=\$(core-doctor --json); [[ \$j == *'\"bat\":true'* && \$j == *'\"fd\":true'* ]]" \
  PATH="$RNBIN" CORE_NO_PAGER=1
# (c) VERSIONS — the latent half: -v forks the RESOLVED binary, so both rows carry a
# version. Before the fix this printed `✓ fd` bare, with the failure swallowed.
ucheck "renamed: core-doctor -v reads versions off the resolved binary" \
  "source '$TOOLS_FILE'; source '$UI'; source '$FN'; o=\$(core-doctor -v); [[ \$o == *'bat 0.24.0'* && \$o == *'fd 0.24.0'* ]]" \
  PATH="$RNBIN" CORE_NO_PAGER=1
# (d) CANONICAL NAMES — the non-Debian answer is unchanged: self-named aliases, still ✓.
_rn_only bat fd
ucheck "renamed: canonical names → aliases stay self-named and the doctor still reports ✓" \
  "source '$TOOLS_FILE'; source '$ALIASES_FILE'; source '$UI'; source '$FN'; j=\$(core-doctor --json); [[ \${aliases[bat]} == bat && \${aliases[fd]} == fd && \$j == *'\"bat\":true'* && \$j == *'\"fd\":true'* ]]" \
  PATH="$RNBIN" CORE_NO_PAGER=1
# (e) NEITHER — a bare box degrades: no HAVE_*, no bat/fd/cat alias, and an honest ✗.
_rn_only
ucheck "renamed: neither present → no bat/fd/cat alias and the doctor reports absent" \
  "source '$TOOLS_FILE'; source '$ALIASES_FILE'; source '$UI'; source '$FN'; j=\$(core-doctor --json); [[ -z \${HAVE_BAT:-} && -z \${HAVE_FD:-} ]] && ! (( \$+aliases[bat] )) && ! (( \$+aliases[fd] )) && ! (( \$+aliases[cat] )) && [[ \$j == *'\"bat\":false'* && \$j == *'\"fd\":false'* ]]" \
  PATH="$RNBIN" CORE_NO_PAGER=1


# ── user bindirs reach PATH BEFORE detection (#425) ──────────────────────────
# 00-tools.zsh prepends the per-user bindirs language installers write into, then probes
# for HAVE_* flags. It used to prepend only ~/.local/bin, so a `cargo install`ed tool —
# which lands in $CARGO_HOME/bin, and reached PATH only via the OS layer at band 80, a
# whole load-order band AFTER detection — got no flag, no alias, and no shell init, while
# core-doctor (which probes LIVE, later, against the finished PATH) reported it ✓. Same
# shell, two answers. atuin's own installer writes ~/.atuin/bin and had the identical
# hole, which is the severe one: no HAVE_ATUIN means `atuin init zsh` never runs, so
# Ctrl+E is dead and no history is recorded behind a green doctor row.
#
# Hermetic, and it has to be: the box running this suite has its own cargo/go/atuin dirs
# one way or the other, and neither arrangement can prove the other's. Each case pins HOME
# to a purpose-built fixture and PATH to a stub dir holding nothing but real grep/head.
#
# CARGO_HOME/GOBIN/GOPATH are neutralised (passed EMPTY — `:-` treats empty as unset) in
# every case that is not deliberately setting them. That is the same trap v4.13.2 fixed in
# the blib_user_bindirs_on_path fixture below: the resolution is `${CARGO_HOME:-$HOME/...}`
# precisely so a relocated dir still works, so a developer with CARGO_HOME exported in
# their own shell retargets the lookup, the fixture's dir never lands, and the case reds a
# perfectly healthy tree while no CI runner — none of which export it — ever sees it.
UBHOME="$SANDBOX/ubhome"
UBSYS="$SANDBOX/ubsys"
mkdir -p "$UBSYS"
ln -sf "$(command -v grep)" "$UBSYS/grep"
ln -sf "$(command -v head)" "$UBSYS/head"
_ub_fixture() { # _ub_fixture <reldir>:<tool> ... — fresh $UBHOME holding exactly these stubs
  rm -rf "$UBHOME"
  mkdir -p "$UBHOME"
  local spec d n
  for spec in "$@"; do
    d="${spec%%:*}"
    n="${spec##*:}"
    mkdir -p "$UBHOME/$d"
    # Answers --version and NOTHING else: `atuin init zsh` must emit no script, or
    # _cache_eval would source the stub's chatter back into the shell.
    printf '#!/bin/sh\n[ "$1" = --version ] && echo "%s 1.0.0"\nexit 0\n' "$n" >"$UBHOME/$d/$n"
    chmod +x "$UBHOME/$d/$n"
  done
}

# (a) THE REPORTED BUG: a cargo-installed tool is detected, aliased and wired.
_ub_fixture .cargo/bin:procs
ucheck "bindirs: a tool in ~/.cargo/bin sets HAVE_PROCS and gets its alias (#425)" \
  "source '$TOOLS_FILE'; source '$ALIASES_FILE'; [[ -n \${HAVE_PROCS:-} && \${aliases[ps]} == procs ]]" \
  HOME="$UBHOME" PATH="$UBSYS" CARGO_HOME= GOBIN= GOPATH=

# (a2) THE #545 AXIS, END TO END: a bindir that joins PATH AFTER band 00 leaves the tool
# present but unwired, and the doctor must say so. This is the real shape — 80-os.zsh, an
# 85-* role fragment or 99-local.zsh prepending a directory — reproduced by exporting PATH
# between sourcing 00-tools.zsh and asking the doctor. Needs python3 for the JSON read;
# `have` is checked inline because ucheck has no dep variant.
if have python3; then
  # python3 by ABSOLUTE path: $UBSYS is deliberately a near-empty PATH (grep + head only),
  # and widening it for these two cases would change the environment every other bindir
  # assertion is pinned against.
  _UB_PY="$(command -v python3)"
  _ub_fixture latebin:procs
  ucheck "detection: a bindir that joins PATH after band 00 is reported in detection.missed (#545)" \
    "source '$TOOLS_FILE'
     export PATH=\"\$HOME/latebin:\$PATH\"
     source '$UI'; source '$FN'
     core-doctor --json | '$_UB_PY' -c \"
import json, sys
d = json.load(sys.stdin)
assert d['detection']['ran'] is True, d['detection']
assert d['tools']['procs'] is True, 'the live probe should still see it'
assert 'procs' in d['detection']['missed'], d['detection']
\"" \
    HOME="$UBHOME" PATH="$UBSYS" CARGO_HOME= GOBIN= GOPATH=
  # …and the mirror case, which is what stops the above passing against a doctor that flags
  # EVERYTHING. Same tool, but in a directory 00-tools.zsh prepends itself (#425's
  # arrangement), so detection saw it and nothing is missed.
  _ub_fixture .cargo/bin:procs
  ucheck "detection: a tool detected at band 00 is NOT reported missed (no false positives)" \
    "source '$TOOLS_FILE'; source '$UI'; source '$FN'
     core-doctor --json | '$_UB_PY' -c \"
import json, sys
d = json.load(sys.stdin)
assert d['detection']['ran'] is True, d['detection']
assert d['tools']['procs'] is True, d['tools']
assert d['detection']['missed'] == [], d['detection']
\"" \
    HOME="$UBHOME" PATH="$UBSYS" CARGO_HOME= GOBIN= GOPATH=
  unset _UB_PY
else
  skip "detection: the #545 end-to-end cases (python3 not installed)"
fi

# (b) THE SEVERE ONE: atuin's own installer dir, whose miss silently loses history.
_ub_fixture .atuin/bin:atuin
ucheck "bindirs: a tool in ~/.atuin/bin sets HAVE_ATUIN (so atuin init zsh runs)" \
  "source '$TOOLS_FILE'; [[ -n \${HAVE_ATUIN:-} ]]" \
  HOME="$UBHOME" PATH="$UBSYS" CARGO_HOME= GOBIN= GOPATH=

# (c) RELOCATABLE: rustup honours $CARGO_HOME, so hard-coding ~/.cargo/bin would leave a
# relocated box still undetected. NOTE there is no ~/.cargo/bin in this fixture at all —
# the flag can only be set by resolving through the variable.
_ub_fixture xdgcargo/bin:procs
ucheck "bindirs: CARGO_HOME is honoured (a relocated cargo dir is still detected)" \
  "source '$TOOLS_FILE'; [[ -n \${HAVE_PROCS:-} ]]" \
  HOME="$UBHOME" PATH="$UBSYS" CARGO_HOME="$UBHOME/xdgcargo" GOBIN= GOPATH=

# (d) go honours $GOBIN first.
_ub_fixture gobin:xh
ucheck "bindirs: GOBIN is honoured" \
  "source '$TOOLS_FILE'; [[ -n \${HAVE_XH:-} ]]" \
  HOME="$UBHOME" PATH="$UBSYS" CARGO_HOME= GOBIN="$UBHOME/gobin" GOPATH=

# (e) …then $GOPATH — which is a path LIST, and go writes to the FIRST entry's bin/.
# Expanding "$GOPATH/bin" against /a:/b would probe a nonexistent "/a:/b/bin", so this
# asserts BOTH that the first entry is used and that no such bogus entry is built.
_ub_fixture gopath/bin:xh second/bin:gron
ucheck "bindirs: GOPATH's FIRST entry is used, and no bogus /a:/b/bin entry is built" \
  "source '$TOOLS_FILE'; [[ -n \${HAVE_XH:-} && -z \${HAVE_GRON:-} && \$PATH != *'gopath:'* ]]" \
  HOME="$UBHOME" PATH="$UBSYS" CARGO_HOME= GOBIN= GOPATH="$UBHOME/gopath:$UBHOME/second"

# (f) IDEMPOTENT: the guard is a containment test, so a second source must not duplicate.
# Duplicates are not cosmetic — 00-tools.zsh is re-sourced by `core reload`, and an
# unbounded PATH is a real leak over a long session.
_ub_fixture .cargo/bin:procs .local/bin:eza
ucheck "bindirs: sourcing twice adds each dir exactly once" \
  "source '$TOOLS_FILE'; source '$TOOLS_FILE'; p=(\${(s.:.)PATH}); [[ \${#\${(M)p:#\$HOME/.cargo/bin}} == 1 && \${#\${(M)p:#\$HOME/.local/bin}} == 1 ]]" \
  HOME="$UBHOME" PATH="$UBSYS" CARGO_HOME= GOBIN= GOPATH=

# (g) Only dirs that EXIST are added — no phantom entries on a box without go or atuin.
_ub_fixture .cargo/bin:procs
ucheck "bindirs: directories that do not exist are never added to PATH" \
  "source '$TOOLS_FILE'; [[ \$PATH != *'/go/bin'* && \$PATH != *'/.atuin/bin'* && \$PATH == *'/.cargo/bin'* ]]" \
  HOME="$UBHOME" PATH="$UBSYS" CARGO_HOME= GOBIN= GOPATH=

# (h) ORDER IS A DECISION, not an accident. Each existing dir is prepended, so the front of
# PATH ends up in reverse list order: ~/.atuin/bin ahead of ~/.local/bin. That matches
# lib/bootstrap-lib.sh's blib_user_bindirs_on_path, examples/atuin-daemon.service's
# Environment=PATH, and the OS layers — inverting it here would silently change which
# binary wins on a box holding atuin in both places.
_ub_fixture .cargo/bin:procs .local/bin:eza .atuin/bin:atuin
ucheck "bindirs: ~/.atuin/bin precedes ~/.local/bin, and all of them precede the old PATH" \
  "source '$TOOLS_FILE'; p=(\${(s.:.)PATH}); [[ \${p[(i)\$HOME/.atuin/bin]} -lt \${p[(i)\$HOME/.local/bin]} && \${p[(i)\$HOME/.local/bin]} -lt \${p[(i)$UBSYS]} ]]" \
  HOME="$UBHOME" PATH="$UBSYS" CARGO_HOME= GOBIN= GOPATH=

# (i) THE DISAGREEMENT ITSELF. The issue's symptom was not "no alias" but that core-doctor
# and the flags answered differently about the same tool in the same shell. Assert they now
# agree: the doctor says present AND Core wired it. Before the fix the first half passed and
# the second failed, which is exactly the bug.
_ub_fixture .cargo/bin:procs
ucheck "bindirs: core-doctor and HAVE_PROCS now agree about a cargo-installed tool (#425)" \
  "source '$TOOLS_FILE'; source '$ALIASES_FILE'; source '$UI'; source '$FN'; j=\$(core-doctor --json); [[ \$j == *'\"procs\":true'* && -n \${HAVE_PROCS:-} && \${aliases[ps]} == procs ]]" \
  HOME="$UBHOME" PATH="$UBSYS" CARGO_HOME= GOBIN= GOPATH= CORE_NO_PAGER=1

# ── ...and the same agreement for EVERY probed tool, not just the one that was reported ──
# #447's point: the five bugs it collected were one defect sampled five times, and the reason
# CI never caught any of them is that nothing asserted the two answers match. The check above
# pins procs because procs is what #425 happened to be reported against; a sixth tool
# packaged unusually would have walked straight past it. Generalise: for every tool
# 00-tools.zsh probes, "the doctor says present" and "Core set the flag" must be the SAME
# boolean. A disagreement in either direction is a bug — doctor=1/flag=0 is #425 exactly (a
# green row for a tool Core never wired, so no alias, and for atuin no history recorded),
# and doctor=0/flag=1 is the mirror (Core wired something the report calls absent).
#
# The tool -> flag mapping is READ OUT OF THE SOURCE, never restated here, so it cannot rot
# and needs no hand-maintained table for the two irregular names (ast-grep -> HAVE_ASTGREP,
# git-absorb -> HAVE_GIT_ABSORB). The `+` quantifiers matter: 00-tools.zsh aligns some
# comments with two spaces, and a single-space regex silently drops those rows.
#
# Excluded BY CONSTRUCTION rather than by a skip list, which is why the pattern is anchored
# to `^_have`: op has no _have line (the doctor probes it live), and fd/bat are set from
# FD_BIN/BAT_BIN inside `if` blocks after resolving fdfind/batcat — all three are pinned by
# their own tests above. Sourcing 20-aliases.zsh keeps this close to a real shell; the one
# alias that shadows a row name (`alias fd=$FD_BIN`) is already outside the pair list.
#
# Pure zsh, no python3: the values are bare true/false against a quoted unique key, so a
# substring test is exact — and unlike the check_dep neighbours this then runs everywhere
# instead of skipping on a box without python3. $'\42' is a literal double quote, which
# survives this bash layer without a thicket of backslashes.
# NO env overrides and no fixture: this one wants the REAL box — real PATH, real tools,
# whatever this runner happens to have installed. That is the whole point. It is only as
# strong as the runner is populated, but it costs nothing on a bare one (everything absent,
# everything unflagged, agreement holds) and it is the assertion that fails the moment a
# tool arrives by a route detection misses.
ucheck "core-doctor and every HAVE_* flag agree about the same box (#447)" \
  "source '$TOOLS_FILE'; source '$ALIASES_FILE'; source '$UI'; source '$FN'
   j=\$(core-doctor --json); bad=(); n=0
   # Narrow to the tools object before substring-matching. --json grew a sibling expected
   # object with the SAME key set (#513), so a bare match on <name>:true now finds whichever
   # object happens to say true — and for a tool that is expected but absent that is the
   # expected object, giving doctor=1 against an unset HAVE_ flag. The substring trick stays
   # (it keeps this assertion python3-free, so it runs on every box); it just has to be
   # pointed at one object. No literal quote marks in this comment: it lives inside a
   # double-quoted bash string, where one would end the string early.
   tj=\${j#*'\"tools\":{'}; tj=\${tj%%'}'*}
   for line in \${(f)\"\$(<'$TOOLS_FILE')\"}; do
     [[ \$line =~ '^_have +([A-Za-z0-9_.-]+) +&& +(HAVE_[A-Z0-9_]+)=1' ]] || continue
     t=\$match[1]; f=\$match[2]; (( n++ ))
     [[ \$tj == *\$'\\42'\$t\$'\\42'':true'* ]] && d=1 || d=0
     [[ -n \${(P)f:-} ]] && h=1 || h=0
     (( d == h )) || bad+=(\"\$t (doctor=\$d \$f=\$h)\")
   done
   (( n >= 30 )) || { print -r -- \"parsed only \$n tool->flag pairs out of 00-tools.zsh\"; exit 1; }
   (( \${#bad} == 0 )) || { print -r -- \"doctor and HAVE_* disagree: \${(j:, :)bad}\"; exit 1; }" \
  CORE_NO_PAGER=1
# ── _core_is_wsl: one WSL predicate for the fleet (00-tools.zsh, #449) ───────────
# Six OS layers each carried a byte-identical copy of this probe, and Core had the same fact
# twice more (bash's blib_is_wsl, and a private copy inside bin/clip) with neither reachable
# from zsh. Core owns it now, so it is Core's job to prove it — including the direction each
# individual copy was never tested in at all.
#
# HERMETIC IN BOTH DIRECTIONS, which is the entire reason $CORE_PROC_VERSION exists. This
# suite is developed on a WSL host and runs on non-WSL CI runners; against the real kernel
# version file exactly ONE of the two answers is assertable on each machine, so without a
# seam half the predicate would go untested everywhere and nobody would see the gap. Same
# seam, same reason, as bin/clip's CLIP_PROC_VERSION at the top of this file.
#
# WSL_DISTRO_NAME= IS PASSED EXPLICITLY IN EVERY FILE-PATH CASE. The predicate reads the env
# var FIRST, and a developer running this from inside WSL has it exported — so without the
# neutralisation every case below would pass for the wrong reason, on the one machine most
# likely to be running them. (The same trap the CARGO_HOME= neutralisation above documents.)
WSLFIX="$SANDBOX/wsl"
mkdir -p "$WSLFIX"
printf 'Linux version 6.6.87.2-microsoft-standard-WSL2 (root@build) #1 SMP\n' >"$WSLFIX/wsl2"
printf 'Linux version 4.4.0-19041-Microsoft (Microsoft@Microsoft.com) #488\n' >"$WSLFIX/wsl1"
printf 'Linux version 6.1.0 (nobody@nowhere) WSL banner, no vendor marker\n' >"$WSLFIX/wslword"
printf 'Linux version 5.15.0-generic (buildd@lcy02) #72-Ubuntu SMP\n' >"$WSLFIX/plain"

# (a) The env var short-circuits — asserted by pointing the seam at the NON-WSL fixture, so
# a predicate that consulted the file anyway would answer no and fail here.
ucheck "_core_is_wsl: WSL_DISTRO_NAME alone answers yes (the version file is never consulted)" \
  "source '$TOOLS_FILE'; _core_is_wsl" \
  WSL_DISTRO_NAME=Ubuntu CORE_PROC_VERSION="$WSLFIX/plain"

# (b)-(d) the file fallback, for a login that never inherited the env (su -, a unit, ssh cmd)
ucheck "_core_is_wsl: the WSL2 marker in the version file is WSL" \
  "source '$TOOLS_FILE'; _core_is_wsl" \
  WSL_DISTRO_NAME= CORE_PROC_VERSION="$WSLFIX/wsl2"
# WSL1 capitalises the vendor string. This is the case-fold (${_pv:l}), not a second pattern
# — drop the fold and every WSL1 box silently reads as plain Linux.
ucheck "_core_is_wsl: WSL1's capitalised marker is WSL (the case-fold, not a second pattern)" \
  "source '$TOOLS_FILE'; _core_is_wsl" \
  WSL_DISTRO_NAME= CORE_PROC_VERSION="$WSLFIX/wsl1"
ucheck "_core_is_wsl: a bare wsl marker with no vendor string is WSL (the second pattern)" \
  "source '$TOOLS_FILE'; _core_is_wsl" \
  WSL_DISTRO_NAME= CORE_PROC_VERSION="$WSLFIX/wslword"

# (e) THE NEGATIVE, which is the half no OS-layer copy could ever assert on its own box.
ucheck "_core_is_wsl: a plain Linux version string is NOT WSL" \
  "source '$TOOLS_FILE'; ! _core_is_wsl" \
  WSL_DISTRO_NAME= CORE_PROC_VERSION="$WSLFIX/plain"

# (f) No version file at all — the macOS/BSD path, where this must be silent and cheap
# rather than an error. Core runs on macOS; the six copies that moved here never did.
ucheck "_core_is_wsl: no version file and no env is NOT WSL (the macOS path, no error)" \
  "source '$TOOLS_FILE'; ! _core_is_wsl" \
  WSL_DISTRO_NAME= CORE_PROC_VERSION="$WSLFIX/absent"

# (g)-(i) the memo. It is what makes a per-prompt caller free, so it is worth pinning that it
# exists, that it is actually consulted, and that the documented escape re-probes.
ucheck "_core_is_wsl: memoises the answer into _CORE_IS_WSL" \
  "source '$TOOLS_FILE'; _core_is_wsl; [[ \$_CORE_IS_WSL == 1 ]]" \
  WSL_DISTRO_NAME= CORE_PROC_VERSION="$WSLFIX/wsl2"
ucheck "_core_is_wsl: the memo is honoured — a second call does not re-read the file" \
  "source '$TOOLS_FILE'; _core_is_wsl; CORE_PROC_VERSION='$WSLFIX/plain'; _core_is_wsl" \
  WSL_DISTRO_NAME= CORE_PROC_VERSION="$WSLFIX/wsl2"
ucheck "_core_is_wsl: unset _CORE_IS_WSL forces a re-probe (the documented escape)" \
  "source '$TOOLS_FILE'; _core_is_wsl; unset _CORE_IS_WSL; CORE_PROC_VERSION='$WSLFIX/plain'; ! _core_is_wsl" \
  WSL_DISTRO_NAME= CORE_PROC_VERSION="$WSLFIX/wsl2"

# (j) ZERO FORK, asserted the way the git exec-path suite asserts its own: a PATH holding
# nothing but RECORDING stubs, and an empty call log. This is the guard that fails if someone
# "simplifies" $(<file) into a `grep -qi` — which is exactly what the bash sibling does, and
# what this deliberately does not, because it runs on every interactive shell and a caller may
# put it in a hook. The log is truncated AFTER sourcing so the assertion is about the
# predicate, not about what 00-tools does on the way in.
WSLBIN="$SANDBOX/wslbin"
mkdir -p "$WSLBIN"
for _wc in cat grep head sed awk; do
  printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\nexit 0\n' "$_wc" "$WSLFIX" >"$WSLBIN/$_wc"
  chmod +x "$WSLBIN/$_wc"
done
unset _wc
ucheck "_core_is_wsl: reads the version file with no fork (no cat, no grep)" \
  "source '$TOOLS_FILE'; : >|'$WSLFIX/calls'; _core_is_wsl; [[ ! -s '$WSLFIX/calls' ]]" \
  WSL_DISTRO_NAME= CORE_PROC_VERSION="$WSLFIX/wsl2" PATH="$WSLBIN"

# (k) It is Core→OS API, so unlike _have it must SURVIVE 00-tools.zsh. The OS layer calls it
# at band 80; _have is unfunctioned at the end of that file and would not be there.
ucheck "_core_is_wsl: survives 00-tools.zsh (Core→OS API), where _have does not" \
  "source '$TOOLS_FILE'; (( \$+functions[_core_is_wsl] )) && (( ! \$+functions[_have] ))"

# ── band placement of the four tool inits (#449) — structure, not behaviour ──────
# Four decisions that BEHAVIOUR CANNOT SEE. Every one of them is silent when broken: the
# shell still starts, no error is printed, and the damage shows up as a feature quietly not
# working on a subset of hosts. Each assertion below therefore says WHAT breaks, not just
# that a line moved, because the message is the only thing a future contributor will read
# before deciding whether the constraint is real.
PLUGINS_FILE="$HERE/zsh/45-plugins.zsh"
# First-match line number. `grep -n | sed`, not `| head`: a file producer feeding an
# early-exiting reader is exactly the SIGPIPE shape audit-core.sh §5d bans.
_zln() { grep -nE "$2" "$1" | sed -n '1s/:.*//p'; } # _zln <file> <ere>
_zsay() { if [[ -n "$2" ]]; then pass "band placement: $1"; else fail "band placement: $1"; fi; }

_z_direnv_t="$(_zln "$TOOLS_FILE" '^_cache_eval[[:space:]]+direnv')"
_z_direnv_p="$(_zln "$PLUGINS_FILE" '^_cache_eval[[:space:]]+direnv')"
_z_mise="$(_zln "$TOOLS_FILE" '_cache_eval[[:space:]]+mise')"
_z_carapace="$(_zln "$PLUGINS_FILE" '_cache_eval[[:space:]]+--salt.*carapace')"

# (1) direnv stays at band 00. Band 45 is profile-gated (loader.zsh ceils `minimal` at 30)
# while band 80 — where this used to live — always loads, so filing it under 45 stops .envrc
# files loading on every minimal host and nothing anywhere says so.
_zsay "direnv's hook is in 00-tools.zsh, not 45-plugins.zsh — band 45 is profile-gated (minimal ceils at 30), so .envrc loading would silently die on minimal hosts" \
  "$([[ -n "$_z_direnv_t" && -z "$_z_direnv_p" ]] && echo ok)"

# (2) …and the three completions are GENERATED at band 00 (#579). Inverted from what this
# asserted before: they used to be sourced at band 45 because they called compdef. They are
# now written into an fpath directory instead, and fpath must be populated BEFORE compinit
# scans it — compinit is band 10, so band 00 is the only band that can guarantee it. Filed at
# band 45 the file would be written a whole shell too late to be seen.
_z_ok=1
for _zt in gh uv ty; do
  [[ -n "$(_zln "$TOOLS_FILE" "^_cache_completion[[:space:]]+${_zt}[[:space:]]")" ]] || _z_ok=""
  [[ -z "$(_zln "$PLUGINS_FILE" "^_cache_completion[[:space:]]+${_zt}[[:space:]]")" ]] || _z_ok=""
  # …and nothing SOURCES them any more. _cache_eval ends in `source`, which is the entire
  # 35 ms this change removes; a caller that slid back to it would be silent otherwise.
  [[ -z "$(_zln "$TOOLS_FILE" "^_cache_eval[[:space:]]+${_zt}[[:space:]]")" ]] || _z_ok=""
  [[ -z "$(_zln "$PLUGINS_FILE" "^_cache_eval[[:space:]]+${_zt}[[:space:]]")" ]] || _z_ok=""
done
unset _zt
_zsay "gh/uv/ty are GENERATED by _cache_completion in 00-tools.zsh and sourced by nothing — fpath must be populated before compinit (band 10) scans it, and _cache_eval would source 6,976 lines per shell" "$_z_ok"

# (3) …and the compdef re-assert is still AFTER carapace. This is the half that survives the
# move, and it is the whole reason a band-45 line still exists: fpath autoloading registers
# these at COMPINIT — band 10, i.e. BEFORE carapace at band 45 — so without re-asserting here
# the move would silently hand gh back to the bridged completion. Whichever compdef runs last
# owns the command.
_z_compdef="$(_zln "$PLUGINS_FILE" 'compdef "_\$t" "\$t"')"
_zsay "the gh/uv/ty compdef re-assert is AFTER the carapace block — fpath autoload registers at band 10, before carapace, so without this the bridged completion silently wins" \
  "$([[ -n "$_z_carapace" && -n "$_z_compdef" ]] && (( _z_compdef > _z_carapace )) && echo ok)"
unset _z_compdef

# (4) direnv after mise. Both PREPEND their hooks, so the one sourced last runs FIRST.
_zsay "direnv is initialised AFTER mise — both PREPEND their hooks, so the one sourced last runs first; inverting this changes per-directory env resolution with no visible symptom" \
  "$([[ -n "$_z_direnv_t" && -n "$_z_mise" ]] && (( _z_direnv_t > _z_mise )) && echo ok)"
unset _z_direnv_t _z_direnv_p _z_mise _z_carapace _z_ok

# ── git subcommands in git's exec-path: an honest doctor off $PATH (#424) ────
# The Debian family packages a git SUBCOMMAND into git's exec-path (`git --exec-path`) and
# keeps that directory off $PATH on purpose — git dispatches `git absorb` by looking there
# itself. Verified on Kali, git-absorb 0.6.17-2+b4: `dpkg -L` lists the exec-path binary and
# a man page and NOTHING in a PATH dir, `command -v git-absorb` finds nothing, and
# `git absorb --version` prints 0.6.17. core-doctor printed `✗ git-absorb` for a tool the
# reader had just used — #418's failure one directory further out, and it earns the same
# hermetic treatment for the same reason: the box running this suite has it one way or the
# other (a Kali runner ONLY in the exec-path, an Arch one ONLY on PATH) and neither can
# prove the other's path.
#
#   $GXROOT/bin/git                  stub: answers --exec-path, and LOGS every invocation
#   $GXROOT/lib/git-core/git-absorb  the subcommand — executable, NOT on $PATH
#   $GXROOT/bin/{grep,head}          real, symlinked: `core-doctor -v` pipes --version through them
#
# The bin/ · lib/git-core/ layout is not cosmetic: 00-tools.zsh's zero-fork fallback derives
# its candidates from ${commands[git]:h:h} rather than naming a distro path, so the tree has
# to be shaped like a real prefix for that half to be exercised at all. The call log is what
# lets the fork budget itself be asserted, in (d) and (e) and (h).
#
# HERMETIC AGAINST THE DEVELOPER'S OWN ENVIRONMENT. `ucheck` runs `env "$@" zsh`, which
# passes the named variables ON TOP of the inherited environment — it does not clear it. So
# a box with GIT_EXEC_PATH exported would leak it into every case here: the git stub honours
# the variable exactly as real git does, so it would answer with the developer's directory
# instead of $GXLIB and cases (a)-(h) would fail for a reason that has nothing to do with
# the code under test. Unset it once, here, for the whole block; the cases that need it
# pass it explicitly through ucheck's env.
unset GIT_EXEC_PATH
GXROOT="$SANDBOX/gitexec"
GXBIN="$GXROOT/bin"
GXLIB="$GXROOT/lib/git-core"
_gx_tree() { # _gx_tree [name ...] — rebuild the tree; each name also lands on $PATH as a stub
  rm -rf "$GXROOT"
  mkdir -p "$GXBIN" "$GXLIB"
  # $1/$* below belong to the /bin/sh stub being written, not to this shell — hence printf
  # with %s rather than an expanding heredoc.
  # The stub honours $GIT_EXEC_PATH exactly as real git does. That is not decoration: it is
  # the only way to move the exec-path BETWEEN two reports using nothing but an env var,
  # and this PATH is hermetic — it carries git, grep and head and nothing else, so a test
  # body cannot reach for `mv` to rearrange the tree.
  printf '#!/bin/sh\necho "$*" >>"%s/calls"\n[ "$1" = --exec-path ] && { echo "${GIT_EXEC_PATH:-%s}"; exit 0; }\nexit 1\n' \
    "$GXROOT" "$GXLIB" >"$GXBIN/git"
  printf '#!/bin/sh\necho "git-absorb 0.6.17"\n' >"$GXLIB/git-absorb"
  chmod +x "$GXBIN/git" "$GXLIB/git-absorb"
  local n
  for n in "$@"; do
    printf '#!/bin/sh\necho "%s 0.6.17"\n' "$n" >"$GXBIN/$n"
    chmod +x "$GXBIN/$n"
  done
  ln -sf "$_real_grep" "$GXBIN/grep"
  ln -sf "$_real_head" "$GXBIN/head"
}
# (a) THE ISSUE. 00-tools.zsh is deliberately NOT sourced, so a ✓ can only come from
#     _core_doctor_bin asking git — not from a HAVE_* flag and not from an alias.
_gx_tree
ucheck "git exec-path: core-doctor reports a subcommand that lives ONLY in git's exec-path" \
  "source '$UI'; source '$FN'; j=\$(core-doctor --json); [[ \$j == *'\"git-absorb\":true'* ]]" \
  PATH="$GXBIN" CORE_NO_PAGER=1
# (b) VERSIONS — the latent half, exactly as in the fd/bat suite above: -v forks the RESOLVED
#     binary. A bare `git-absorb --version` cannot run on this family at all, so this row
#     could not have carried a version even if presence had somehow been right.
ucheck "git exec-path: core-doctor -v reads the version off the exec-path binary" \
  "source '$UI'; source '$FN'; o=\$(core-doctor -v); [[ \$o == *'git-absorb 0.6.17'* ]]" \
  PATH="$GXBIN" CORE_NO_PAGER=1
# (c) NO LEAK — the row is keyed and PRINTED by its canonical name; the absolute path the
#     resolver hands back is an implementation detail and must not reach the report. The
#     `resolved` footer names the exec-path DIRECTORY, which is why this asserts against the
#     full binary path rather than against the directory.
ucheck "git exec-path: the report prints the canonical name, never the resolved absolute path" \
  "source '$UI'; source '$FN'; o=\$(NO_COLOR=1 core-doctor); [[ \$o == *'✓ git-absorb'* && \$o != *'$GXLIB/git-absorb'* ]]" \
  PATH="$GXBIN" CORE_NO_PAGER=1
# (d) ONE FORK PER REPORT. The cache is the reason forking here is acceptable at all; without
#     it the answer is re-derived per git-* row and per renderer. Driven through
#     _core_doctor_bin with TWO different names rather than through a report, deliberately:
#     _CORE_DOCTOR_GROUPS carries exactly one `git-*` row today, so a whole-report assertion
#     would read `== 1` with the cache torn out and prove nothing. Two names is the smallest
#     input that can tell a cache from its absence, and it stays honest if the inventory
#     never grows a second git subcommand.
_gx_tree
ucheck "git exec-path: two git-* rows resolve on ONE fork (the cache, not a one-row artefact)" \
  "source '$UI'; source '$FN'; _core_doctor_bin git-absorb; _core_doctor_bin git-imaginary; (( \$(grep -c -- '--exec-path' '$GXROOT/calls') == 1 ))" \
  PATH="$GXBIN" CORE_NO_PAGER=1
# (d2) …AND THE CACHE MUST NOT OUTLIVE ITS REPORT. Only the TTY render runs in a `$(…)`
#     subshell; --json and the non-TTY path run in the caller's shell, so core-doctor unsets
#     the cache on entry. Without that unset a shell that ran one report before git was
#     installed would keep answering from the cached EMPTY value forever. Asserted by
#     MOVING THE EXEC-PATH between two reports in ONE shell, via $GIT_EXEC_PATH, which the
#     git stub honours as real git does: the first report is pointed at an empty directory
#     and must say false, the second at the real one and must say true. A cache that outlives
#     its report answers the second from the first's directory and the assertion fails.
#     Done with an env var rather than by rearranging the tree because this PATH is hermetic
#     — no `mv` on it — and a body that shells out to a missing tool fails silently, which
#     is how the first draft of this case passed for the wrong reason.
_gx_tree
mkdir -p "$GXROOT/lib/git-core-empty"
#     REDIRECT TO A FILE, never `$(…)` — the same rule the OSC 133 block below states for its
#     own reason. A command substitution is itself a subshell, so it discards the cache on the
#     way out and this case passes no matter what core-doctor does. Redirection keeps both
#     reports in the one shell, which is the only place the leak is observable.
ucheck "git exec-path: a second report re-derives — the cache does not outlive its invocation" \
  "source '$UI'; source '$FN'
   export GIT_EXEC_PATH='$GXROOT/lib/git-core-empty'; core-doctor --json >'$GXROOT/j1'
   export GIT_EXEC_PATH='$GXLIB';                     core-doctor --json >'$GXROOT/j2'
   [[ \$(<'$GXROOT/j1') == *'\"git-absorb\":false'* && \$(<'$GXROOT/j2') == *'\"git-absorb\":true'* ]]" \
  PATH="$GXBIN" CORE_NO_PAGER=1
# (e) PATH FIRST. A git-absorb on $PATH must be used as-is and git must never be asked — this
#     is what keeps the fix free on every box that never had the bug.
_gx_tree git-absorb
ucheck "git exec-path: a git-absorb on \$PATH is used as-is — git is never forked to find it" \
  "source '$UI'; source '$FN'; j=\$(core-doctor --json); [[ \$j == *'\"git-absorb\":true'* ]] && [[ ! -s '$GXROOT/calls' ]]" \
  PATH="$GXBIN" CORE_NO_PAGER=1
# (f) HONEST ✗, twice: git present with no subcommand, and no git at all. core-doctor is
#     read-only diagnostics and must return 0 through both.
_gx_tree; rm -f "$GXLIB/git-absorb"
ucheck "git exec-path: git present but no subcommand in its exec-path → an honest ✗, rc 0" \
  "source '$UI'; source '$FN'; j=\$(core-doctor --json) && [[ \$j == *'\"git-absorb\":false'* ]]" \
  PATH="$GXBIN" CORE_NO_PAGER=1
_gx_tree; rm -f "$GXBIN/git" "$GXLIB/git-absorb"
ucheck "git exec-path: no git at all → an honest ✗ and no error (the empty answer is cached)" \
  "source '$UI'; source '$FN'; j=\$(core-doctor --json) && [[ \$j == *'\"git-absorb\":false'* ]]" \
  PATH="$GXBIN" CORE_NO_PAGER=1
# (g) THE RESOLVER'S CONTRACT: a RUNNABLE absolute path, which is what makes the -v fork work.
_gx_tree
ucheck "git exec-path: _core_doctor_bin hands back a runnable absolute path for the resolved row" \
  "source '$UI'; source '$FN'; _core_doctor_bin git-absorb; [[ \$REPLY == '$GXLIB/git-absorb' ]] && [[ \$(\$REPLY --version) == 'git-absorb 0.6.17' ]]" \
  PATH="$GXBIN"
# (h) 00-tools.zsh's half — and its ZERO-FORK contract in the same assertion: the flag must be
#     set from git's exec-path, derived via $commands, with `git` itself never invoked. This is
#     the guard that fails if someone "simplifies" the fallback into a $(git --exec-path).
_gx_tree
ucheck "git exec-path: HAVE_GIT_ABSORB is set from git's exec-path, with no fork (00-tools.zsh)" \
  "source '$TOOLS_FILE'; [[ -n \${HAVE_GIT_ABSORB:-} ]] && [[ ! -s '$GXROOT/calls' ]]" \
  PATH="$GXBIN"
_gx_tree; rm -f "$GXLIB/git-absorb"
ucheck "git exec-path: HAVE_GIT_ABSORB stays unset when the exec-path has no git-absorb" \
  "source '$TOOLS_FILE'; [[ -z \${HAVE_GIT_ABSORB:-} ]]" \
  PATH="$GXBIN"
# (i) $GIT_EXEC_PATH is git's own override, so the flag must honour it — asserted from a
#     directory OUTSIDE the derived prefix, or the derived candidate would satisfy it anyway.
_gx_tree; rm -f "$GXLIB/git-absorb"
mkdir -p "$GXROOT/elsewhere"
printf '#!/bin/sh\necho "git-absorb 0.6.17"\n' >"$GXROOT/elsewhere/git-absorb"
chmod +x "$GXROOT/elsewhere/git-absorb"
ucheck "git exec-path: \$GIT_EXEC_PATH is honoured for the flag (git's own override wins)" \
  "source '$TOOLS_FILE'; [[ -n \${HAVE_GIT_ABSORB:-} ]]" \
  PATH="$GXBIN" GIT_EXEC_PATH="$GXROOT/elsewhere"
# (i2) …and the INVERSE, which case (i) alone cannot see: the override must be EXCLUSIVE, not
#     one more candidate. GIT_EXEC_PATH REPLACES git's compiled-in exec-path — point it at an
#     empty directory and `git absorb` answers "'absorb' is not a git command" even with the
#     binary still sitting in the default one. So with the override empty and the DEFAULT
#     exec-path populated, the flag must stay unset: setting it would claim a subcommand git
#     can no longer dispatch, and core-doctor — which asks `git --exec-path` and therefore
#     inherits the override — would rightly disagree. #503 shipped the fall-through; this is
#     the guard against it coming back.
_gx_tree   # git-absorb IS in the default exec-path here; the override deliberately is not
mkdir -p "$GXROOT/empty-override"
ucheck "git exec-path: a \$GIT_EXEC_PATH without the subcommand wins over the default (no false ✓)" \
  "source '$TOOLS_FILE'; [[ -z \${HAVE_GIT_ABSORB:-} ]]" \
  PATH="$GXBIN" GIT_EXEC_PATH="$GXROOT/empty-override"
# …and the doctor must AGREE with the flag on that same box, which is the whole point of
# keeping the two in step (#425). The git stub honours GIT_EXEC_PATH exactly as real git
# does, so this puts both assertions on one configuration.
ucheck "git exec-path: flag and doctor agree under an empty override (both absent)" \
  "source '$TOOLS_FILE'; source '$UI'; source '$FN'; j=\$(core-doctor --json)
   [[ -z \${HAVE_GIT_ABSORB:-} && \$j == *'\"git-absorb\":false'* ]]" \
  PATH="$GXBIN" GIT_EXEC_PATH="$GXROOT/empty-override" CORE_NO_PAGER=1
# (i3) EXPORTED, not merely set. git reads GIT_EXEC_PATH from its ENVIRONMENT, so a plain
#     shell assignment — `scalar`, not `scalar-export` — is invisible to it. Treating any
#     non-empty parameter as authoritative gives the MIRROR of (i2): the flag honours an
#     override git ignores and reports absent while `git absorb` and the doctor both work.
#     Set INSIDE the body rather than passed through `ucheck`'s env, which is the whole
#     point — anything ucheck exports arrives as `scalar-export` and cannot express this.
#     git-absorb is in the default exec-path, so the correct answer is present-and-agreeing.
_gx_tree
#     `unset` FIRST, then assign: assigning to an already-exported parameter PRESERVES the
#     export attribute, so on a box where GIT_EXEC_PATH is exported a bare assignment would
#     leave it `scalar-export` and this case would fail for the wrong reason. Unsetting drops
#     the attribute with the value, and the plain assignment then creates a fresh `scalar`.
#     The type is asserted rather than assumed, so if that ever stops holding this fails
#     loudly instead of quietly testing the exported path twice.
ucheck "git exec-path: an UNEXPORTED GIT_EXEC_PATH is ignored, as git ignores it" \
  "unset GIT_EXEC_PATH; GIT_EXEC_PATH='$GXROOT/empty-override'   # set, deliberately NOT exported
   [[ \${(t)GIT_EXEC_PATH} == scalar ]] || return 1
   source '$TOOLS_FILE'; source '$UI'; source '$FN'; j=\$(core-doctor --json)
   [[ -n \${HAVE_GIT_ABSORB:-} && \$j == *'\"git-absorb\":true'* ]]" \
  PATH="$GXBIN" CORE_NO_PAGER=1

# ── OSC 133 prompt marks + the command-block rule (00-tools.zsh) ─────────────
# The marks are what tmux's next-prompt/previous-prompt (bound to ] / [ in
# tmux.reset.conf) read, so a regression here silently costs the keybinding its meaning
# with nothing to see on screen — precisely the shape a behavioral gate must catch. The
# hooks also moved OUT of the HAVE_STARSHIP gate (the marks must work on a bare box and
# over SSH, where the rule is starship-only), which is what cases (h)/(i) below pin.
#
# MECHANICS. Capture by REDIRECTING TO A FILE, never `$(…)`: the exit-code cases need $?
# to reach the hook intact, and a file redirect leaves it untouched with no subshell
# question to reason about. `(exit 7)` sets that status with no external binary, so the
# cases stay valid under an isolated PATH. TERM and TMUX are passed EXPLICITLY wherever
# they matter — this suite may itself be running inside tmux, under any terminal, and
# `env` would otherwise leak the real values into the assertion.
OSCOUT="$SANDBOX/osc133.out"
OSCEMPTY="$SANDBOX/oscempty" # an EMPTY PATH: no starship, so the rule cannot be drawn
mkdir -p "$OSCEMPTY"
# (a) THE A MARK IS IN $PROMPT, and it is there because a hook-emitted one does not
#     survive: zsh's prompt preamble ends in ED (\e[J) over the line the mark was just
#     written to, and tmux drops that line's prompt flag when it is cleared — measured on
#     3.7b, previous-prompt would not move at all. Zero-width %{…%}, or every prompt's
#     width math is off by the length of an escape sequence.
ucheck "osc133: the A mark is carried in \$PROMPT as a zero-width %{…%} escape" \
  "source '$TOOLS_FILE'; _core_osc133_prompt; [[ \$PROMPT == '%{'*']133;A'*'%}'* ]]" \
  TERM=xterm-256color TMUX=
# (a2) IDEMPOTENT — starship re-sets PROMPT every precmd, but on a box WITHOUT starship it
#      is static, so a hook that prepended unconditionally would grow a mark per prompt.
ucheck "osc133: re-marking an already-marked PROMPT does not stack marks" \
  "source '$TOOLS_FILE'; repeat 3 _core_osc133_prompt; p=\${PROMPT/']133;A'/}; [[ \$p != *']133;A'* ]]" \
  TERM=xterm-256color TMUX= PATH="$OSCEMPTY"
# (a3) APPENDED, not prepended: starship_precmd re-sets PROMPT wholesale, so a mark applied
#      before it would be discarded again on every prompt. The contract is RELATIVE — after
#      starship — not "last": the atuin guard appends itself after us at the end of this
#      file, and an OS (80) or host (99) fragment may append more. A stand-in starship_precmd
#      is seeded before sourcing (PATH has no real starship, so nothing else registers one),
#      which is what makes the ordering assertable at all on a box without the binary.
ucheck "osc133: the PROMPT hook is ordered AFTER starship_precmd (which re-sets PROMPT)" \
  "starship_precmd() { : }; precmd_functions=(starship_precmd); source '$TOOLS_FILE'; [[ -n \${precmd_functions[(r)_core_osc133_prompt]} ]] && (( \$precmd_functions[(i)_core_osc133_prompt] > \$precmd_functions[(i)starship_precmd] ))" \
  TERM=xterm-256color TMUX= PATH="$OSCEMPTY"
# (a4) …and it must be transparent to \$?, since it now sits between the command and any
#      hook an OS (80) or host (99) fragment appends after it.
ucheck "osc133: the PROMPT hook preserves \$? for later precmd hooks" \
  "source '$TOOLS_FILE'; (exit 7); _core_osc133_prompt; (( \$? == 7 ))" \
  TERM=xterm-256color TMUX=
# (a5) The transient prompt is the other half: collapsing a finished prompt REDRAWS that
#      line and clears its flag, and scrollback is what previous-prompt jumps THROUGH.
check "osc133: the transient prompt carries the mark too (scrollback stays jumpable)" \
  "grep -q 'TRANSIENT_PROMPT_TRANSIENT_PROMPT=\"\${_CORE_OSC133_MARK:-}\"' '$HERE/zsh/45-plugins.zsh'"
# (b) D carries the REAL exit code — the mark non-tmux OSC 133 consumers read for status.
ucheck "osc133: the D mark carries the real exit code (]133;D;7)" \
  "source '$TOOLS_FILE'; _CMD_BLOCK_RAN=1; (exit 7); _cmd_block_precmd >'$OSCOUT'; [[ \"\$(<'$OSCOUT')\" == *']133;D;7'* ]]" \
  TERM=xterm-256color TMUX=
# (c) The hook must RESTORE \$? — every later precmd (starship_precmd included) reads it,
#     and emitting a status mark makes that correctness load-bearing rather than cosmetic.
ucheck "osc133: _cmd_block_precmd returns the command's exit code, not its own" \
  "source '$TOOLS_FILE'; _CMD_BLOCK_RAN=1; (exit 7); _cmd_block_precmd >/dev/null; (( \$? == 7 ))" \
  TERM=xterm-256color TMUX=
# (b2) C is emitted at COMMAND START — the mark tmux's `-o` "jump to the output" variant
#      reads. Same -rn discipline: it must not open a line of its own.
ucheck "osc133: preexec emits the command-output mark (]133;C) and nothing else" \
  "source '$TOOLS_FILE'; _cmd_block_preexec >'$OSCOUT'; [[ \"\$(<'$OSCOUT')\" == *']133;C'* ]] && (( \$(wc -l <'$OSCOUT') == 0 ))" \
  TERM=xterm-256color TMUX=
# (d) A bare Enter: NO D and NO rule (both describe a command that ran) — the A mark is in
#     PROMPT, so an idle prompt is still a jump target without emitting anything. Pins the
#     _CMD_BLOCK_RAN gating the restructure moved. Empty PATH ⇒ no starship ⇒ the "no rule"
#     half is deterministic on any CI box.
ucheck "osc133: a bare prompt emits nothing — no D mark, no rule" \
  "source '$TOOLS_FILE'; _CMD_BLOCK_RAN=0; _cmd_block_precmd >'$OSCOUT'; [[ ! -s '$OSCOUT' ]]" \
  TERM=xterm-256color TMUX= PATH="$OSCEMPTY"
# (e) Ghostty injects its OWN prompt marking, so outside tmux Core stands down rather than
#     double-mark: no mark in PROMPT, and no C/D on the wire either.
ucheck "osc133: stands down under Ghostty's own shell integration (outside tmux)" \
  "source '$TOOLS_FILE'; _CMD_BLOCK_RAN=1; _cmd_block_precmd >'$OSCOUT'; [[ -z \$_CORE_OSC133_MARK && \$PROMPT != *']133;'* && \"\$(<'$OSCOUT')\" != *']133;'* ]]" \
  TERM=xterm-256color TMUX= GHOSTTY_SHELL_FEATURES=cursor,title
# (f) …but GHOSTTY_SHELL_FEATURES is EXPORTED and reaches the tmux server, while Ghostty
#     injects into the INITIAL shell only. Inside tmux Core is the only emitter — and tmux
#     copy mode is where the marks are actually spent — so it must NOT stand down there.
ucheck "osc133: still marks inside tmux under Ghostty (its integration isn't in the pane)" \
  "source '$TOOLS_FILE'; _core_osc133_prompt; [[ \$PROMPT == *']133;A'* ]]" \
  TERM=xterm-256color TMUX=/tmp/tmux-0/default,1,0 GHOSTTY_SHELL_FEATURES=cursor,title
# (g) A consumer that does not parse OSC (Emacs M-x shell) would render the sequence as
#     literal garbage in the prompt and above every command's output.
ucheck "osc133: stands down on TERM=dumb (no literal escape garbage)" \
  "source '$TOOLS_FILE'; _CMD_BLOCK_RAN=1; _cmd_block_precmd >'$OSCOUT'; [[ -z \$_CORE_OSC133_MARK && \$PROMPT != *']133;'* && \"\$(<'$OSCOUT')\" != *']133;'* ]]" \
  TERM=dumb TMUX=
# (h) THE HOIST: on a box with no starship the hooks must still be registered (marks are
#     not a prompt cosmetic) — and _cmd_block_precmd stays FIRST, so the rule and the D mark
#     land above whatever a later hook prints instead of interleaved with it.
ucheck "osc133: hooks registered without starship, and precmd stays first (output order)" \
  "source '$TOOLS_FILE'; [[ -z \${HAVE_STARSHIP:-} && \$precmd_functions[1] == _cmd_block_precmd && -n \${preexec_functions[(r)_cmd_block_preexec]} ]]" \
  TERM=xterm-256color TMUX= PATH="$OSCEMPTY"
# (i) The other side of that gate: marks stood down AND no starship means neither hook has
#     any work at all, so a shell must not carry either of them for the life of the session.
ucheck "osc133: no hooks at all when the marks stand down and starship is absent" \
  "source '$TOOLS_FILE'; [[ -z \${precmd_functions[(r)_cmd_block_precmd]} && -z \${preexec_functions[(r)_cmd_block_preexec]} && -z \${precmd_functions[(r)_core_osc133_prompt]} ]]" \
  TERM=dumb TMUX= PATH="$OSCEMPTY"

# (j) THE REGRESSION GATE on the harness itself, not on the shell layer — and the reason it
#     is here rather than left to CI: this bug was INVISIBLE to CI by construction. No runner
#     is hosted in Ghostty, so every mark-ON case above passed on ubuntu, macos, arch and
#     alpine while the identical tree red 7 assertions for an operator running `make audit`
#     from the terminal this repo ships a config for. A green CI lane was not evidence.
#
#     Drive one mark-ON assertion with GHOSTTY_SHELL_FEATURES genuinely EXPORTED — exactly
#     what a Ghostty-hosted audit does — and require the same verdict. This fails loudly if
#     anyone drops the `env -u` from ucheck. Exported for real, not passed as an argument:
#     an argument is the thing cases (e)/(f) already do and would test nothing, because the
#     leak is about what `env` INHERITS.
_osc_amb_set=0
[[ -n ${GHOSTTY_SHELL_FEATURES+x} ]] && _osc_amb_set=1
_osc_amb_saved="${GHOSTTY_SHELL_FEATURES-}"
export GHOSTTY_SHELL_FEATURES=cursor,title
ucheck "osc133: the harness is insulated from an ambient GHOSTTY_SHELL_FEATURES (an audit run inside Ghostty cannot red a green tree)" \
  "source '$TOOLS_FILE'; _core_osc133_prompt; [[ \$PROMPT == '%{'*']133;A'*'%}'* ]]" \
  TERM=xterm-256color TMUX=
# Restore rather than blanket-unset: the caller's environment is not ours to edit, and a
# later section reading it would otherwise see a value this block invented.
if ((_osc_amb_set)); then export GHOSTTY_SHELL_FEATURES="$_osc_amb_saved"; else unset GHOSTTY_SHELL_FEATURES; fi
unset _osc_amb_set _osc_amb_saved

# ── atuin: ATUIN_NOBIND + the OPT-IN daemon guard (00-tools.zsh) ──────────────
# Two things were ungated here. (1) ATUIN_NOBIND=true is what keeps atuin from grabbing
# the keys 40-bindings.zsh/35-fzf.zsh own (Ctrl+E is OURS, Ctrl+R stays on the fzf widget),
# and it doubles as the _cache_eval salt — yet nothing asserted it. (2) The daemon guard:
# with the daemon enabled and its socket absent or STALE, atuin does not fall back — measured
# on 18.19.0 it exits 0, prints a well-formed id, writes nothing to stderr and DISCARDS the
# entry. So Core probes the socket before the first prompt AND THEN, THROTTLED, FOR THE LIFE OF
# THE SHELL, and forces the daemon off permanently the first time a connect fails — which is what
# makes atuin really write SQLite. The stake is the history itself,
# not per-command latency. Case (d) below pins the OTHER half of that contract — the accept-but-silent
# state it deliberately does not claim to catch. Both are hermetic — no atuin
# binary needed: the guard is defined unconditionally (only its precmd registration is
# HAVE_ATUIN-gated), and a real listener comes from zsh's own zsocket.
# Cases (g)-(l) are the WATCHDOG half (dotgibson/dotfiles-core#366). They manufacture a
# mid-session daemon death by closing the listening fd `zsocket -l` handed back — the socket FILE
# survives, which is exactly case (c)'s stale state, but arrived at mid-run — and they time-travel
# past the throttle window by BACK-DATING _CORE_ATUIN_DAEMON_NEXT. This suite has no `sleep`
# anywhere and must not grow one. Two rules every body below obeys: never wrap the guard in
# `$(…)` or a pipeline (the globals and the precmd_functions edits would be lost to the subshell)
# — redirect stderr to a file under $SANDBOX and grep that instead; and where an assertion touches
# precmd_functions, pass PATH="$ATBIN:$PATH" so the registration actually happened, or the check
# is vacuously true.
ATBIN="$SANDBOX/atbin"
ATCACHE="$SANDBOX/atcache"
rm -rf "$ATBIN" "$ATCACHE"
mkdir -p "$ATBIN" "$ATCACHE/zsh" "$SANDBOX/atempty" # atempty = an EMPTY PATH: no atuin at all
printf '#!/bin/sh\n:\n' >"$ATBIN/atuin"
chmod +x "$ATBIN/atuin"
# EXPORTED, not merely set: an unexported ATUIN_NOBIND never reaches the atuin binary, so
# atuin would go back to grabbing the up-arrow and Ctrl+R behind Core's back.
ucheck "atuin: ATUIN_NOBIND is EXPORTED true (Core owns Ctrl+E / Ctrl+R, not atuin)" \
  "source '$TOOLS_FILE'; [[ \$ATUIN_NOBIND == true && \${(t)ATUIN_NOBIND} == *export* ]]"
# The other half of that contract: the init cache is SALTED on ATUIN_NOBIND, so flipping it
# selects a different cache instead of serving a stale init. A regression that dropped
# --salt would write the unsalted name and quietly reintroduce the stale-cache bug.
ucheck "atuin: the init cache is salted on ATUIN_NOBIND (atuin.true.zsh, not atuin.zsh)" \
  "source '$TOOLS_FILE'; [[ -f \$XDG_CACHE_HOME/zsh/atuin.true.zsh && ! -e \$XDG_CACHE_HOME/zsh/atuin.zsh ]]" \
  PATH="$ATBIN:$PATH" XDG_CACHE_HOME="$ATCACHE"
# The guard is REGISTERED only where atuin exists (the function itself is defined either way,
# so the tests below can drive it) — a bare box must not carry a precmd hook for a tool it
# does not have.
ucheck "atuin daemon: the guard is hooked onto precmd when atuin is present" \
  "source '$TOOLS_FILE'; [[ -n \${precmd_functions[(r)_core_atuin_daemon_guard]} ]]" \
  PATH="$ATBIN:$PATH" XDG_CACHE_HOME="$ATCACHE"
ucheck "atuin daemon: no precmd hook on a box without atuin (fully inert)" \
  "source '$TOOLS_FILE'; [[ -z \${precmd_functions[(r)_core_atuin_daemon_guard]} ]]" \
  PATH="$SANDBOX/atempty" XDG_CACHE_HOME="$ATCACHE"
# (a) NOT opted in — the guard must leave the env exactly as it found it (no daemon, no
#     socket probe, no surprise export on the eight machines that never asked for it).
ucheck "atuin daemon: guard is a no-op when the daemon was never opted into" \
  "source '$TOOLS_FILE'; _core_atuin_daemon_guard; [[ -z \${ATUIN_DAEMON__ENABLED:-} && -z \${_CORE_ATUIN_DAEMON_DEGRADED:-} ]]"
# (b) OPTED IN, socket unreachable — degrade to direct SQLite writes, which is what stops
#     atuin silently dropping every command it is handed.
ucheck "atuin daemon: an unreachable socket degrades the daemon off (no silently discarded history)" \
  "source '$TOOLS_FILE'; _core_atuin_daemon_guard; [[ \$ATUIN_DAEMON__ENABLED == false && -n \$_CORE_ATUIN_DAEMON_DEGRADED ]]" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/absent-atuin.sock"
# (c) A STALE socket FILE (bound then closed — no listener) is the case a plain -S test
#     passes, and the one that silently eats history rather than erroring. The connect
#     probe must still degrade.
ucheck "atuin daemon: a stale socket file (no listener) degrades too, not just an absent one" \
  "rm -f '$SANDBOX/stale-atuin.sock'; zmodload zsh/net/socket; zsocket -l '$SANDBOX/stale-atuin.sock'; exec {REPLY}>&-; source '$TOOLS_FILE'; [[ -S '$SANDBOX/stale-atuin.sock' ]] && { _core_atuin_daemon_guard; [[ \$ATUIN_DAEMON__ENABLED == false ]] }" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/stale-atuin.sock"
# (d) A LISTENING socket must be left alone — the guard exists to catch a dead daemon, not
#     to second-guess a working one. zsocket -l gives a real listener with no atuin involved.
#     Note what this listener also IS: accept-but-silent, i.e. the exact blind spot named in
#     00-tools.zsh (a socket-activated socket in front of a dead daemon looks like this). The
#     assertion therefore pins the guard's DOCUMENTED scope in both directions — it must not
#     claim to catch a state a connect cannot distinguish. A live listener also ARMS the
#     watchdog, so _CORE_ATUIN_DAEMON_WAS_UP is the healthy path's new observable.
ucheck "atuin daemon: a listening socket keeps the daemon enabled (accept-but-silent is out of scope)" \
  "rm -f '$SANDBOX/live-atuin.sock'; zmodload zsh/net/socket; zsocket -l '$SANDBOX/live-atuin.sock'; source '$TOOLS_FILE'; _core_atuin_daemon_guard; [[ \$ATUIN_DAEMON__ENABLED == true && -z \${_CORE_ATUIN_DAEMON_DEGRADED:-} && -n \$_CORE_ATUIN_DAEMON_WAS_UP ]]" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/live-atuin.sock"
# (d2) THE CANDIDATE LIST (#518). atuin PR #3910 (merged 2026-08-12, ships in 18.20.0) moves
#      the default socket for `systemd_socket = false` — the shape Core recommends — to
#      $TMPDIR/atuin-$UID/atuin.sock. The client got a legacy search list; this guard had
#      none and resolved ONE expression, so on 18.20.0 every shell would export
#      ATUIN_DAEMON__ENABLED=false at its first precmd and unhook, with NO warning
#      (_CORE_ATUIN_DAEMON_WAS_UP is never set on that path). Silent, fleet-wide, and in the
#      cheap direction — which is exactly why it would go unnoticed.
#
#      Each case puts a REAL listener on exactly one candidate and leaves the others absent,
#      so a guard that probed only the other path degrades and the assertion fails.
ATSOCKTMP="$SANDBOX/atsock"
mkdir -p "$ATSOCKTMP/atuin-$(id -u)" "$ATSOCKTMP/xdgrun" "$ATSOCKTMP/xdgdata/atuin"
# The 18.20.0 default, with XDG_RUNTIME_DIR set — i.e. a systemd box, where the OLD single
# expression would have resolved $XDG_RUNTIME_DIR/atuin.sock and found nothing.
ucheck "atuin daemon: finds the 18.20.0 default \$TMPDIR/atuin-\$UID/atuin.sock (#518)" \
  "rm -f '$ATSOCKTMP/atuin-$(id -u)/atuin.sock'; zmodload zsh/net/socket; zsocket -l '$ATSOCKTMP/atuin-$(id -u)/atuin.sock'; source '$TOOLS_FILE'; _core_atuin_daemon_guard; [[ \$ATUIN_DAEMON__ENABLED == true && -n \$_CORE_ATUIN_DAEMON_WAS_UP ]]" \
  ATUIN_DAEMON__ENABLED=true TMPDIR="$ATSOCKTMP" XDG_RUNTIME_DIR="$ATSOCKTMP/xdgrun" \
  XDG_DATA_HOME="$ATSOCKTMP/xdgdata"
# The legacy systemd path — a daemon predating 18.20.0, or one with systemd_socket = true,
# which PR #3910 left unchanged. Must still be reached.
ucheck "atuin daemon: still reaches the legacy \$XDG_RUNTIME_DIR/atuin.sock (#518)" \
  "rm -f '$ATSOCKTMP/xdgrun/atuin.sock'; zmodload zsh/net/socket; zsocket -l '$ATSOCKTMP/xdgrun/atuin.sock'; source '$TOOLS_FILE'; _core_atuin_daemon_guard; [[ \$ATUIN_DAEMON__ENABLED == true && -n \$_CORE_ATUIN_DAEMON_WAS_UP ]]" \
  ATUIN_DAEMON__ENABLED=true TMPDIR="$ATSOCKTMP/nowhere" XDG_RUNTIME_DIR="$ATSOCKTMP/xdgrun" \
  XDG_DATA_HOME="$ATSOCKTMP/xdgdata"
# The legacy data-dir path — macOS and anywhere XDG_RUNTIME_DIR is unset.
ucheck "atuin daemon: still reaches the legacy data-dir socket (#518)" \
  "rm -f '$ATSOCKTMP/xdgdata/atuin/atuin.sock'; zmodload zsh/net/socket; zsocket -l '$ATSOCKTMP/xdgdata/atuin/atuin.sock'; source '$TOOLS_FILE'; _core_atuin_daemon_guard; [[ \$ATUIN_DAEMON__ENABLED == true && -n \$_CORE_ATUIN_DAEMON_WAS_UP ]]" \
  ATUIN_DAEMON__ENABLED=true TMPDIR="$ATSOCKTMP/nowhere" XDG_RUNTIME_DIR= \
  XDG_DATA_HOME="$ATSOCKTMP/xdgdata"
# An EXPLICIT ATUIN_DAEMON__SOCKET_PATH must win outright and probe nothing else. Point it at
# an absent path while a live listener sits on a candidate: the guard must still degrade, or
# the config knob has stopped being authoritative — which would be a worse bug than the one
# this change fixes, since it silently overrides what the user asked for.
ucheck "atuin daemon: an explicit socket path wins outright (candidates are not tried) (#518)" \
  "rm -f '$ATSOCKTMP/xdgrun/atuin.sock'; zmodload zsh/net/socket; zsocket -l '$ATSOCKTMP/xdgrun/atuin.sock'; source '$TOOLS_FILE'; _core_atuin_daemon_guard; [[ \$ATUIN_DAEMON__ENABLED == false && -n \$_CORE_ATUIN_DAEMON_DEGRADED ]]" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/absent-atuin.sock" \
  TMPDIR="$ATSOCKTMP" XDG_RUNTIME_DIR="$ATSOCKTMP/xdgrun" XDG_DATA_HOME="$ATSOCKTMP/xdgdata"

# (e) AUTOSTART — atuin supervises its own daemon there (the no-systemd answer for
#     Alpine/macOS), so an absent socket is EXPECTED, not a fault. Don't disable it — and don't
#     keep re-probing for the life of the shell either: stand down means UNHOOK.
ucheck "atuin daemon: autostart owns the lifecycle, so the guard stands down and unhooks" \
  "source '$TOOLS_FILE'; _core_atuin_daemon_guard; [[ \$ATUIN_DAEMON__ENABLED == true && -z \${precmd_functions[(r)_core_atuin_daemon_guard]} ]]" \
  PATH="$ATBIN:$PATH" XDG_CACHE_HOME="$ATCACHE" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__AUTOSTART=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/absent-atuin.sock"
# (f) NOT OPTED IN → the guard unhooks PERMANENTLY. The machines that never asked for the daemon
#     must not carry even the throttle's integer compare for the life of the shell. This is a
#     STAND-DOWN, not the one-shot the guard used to be — an opted-in shell now stays hooked on
#     purpose, which is case (g). (This body never sets ATUIN_DAEMON__ENABLED, so it has always
#     exercised the stand-down; only the label was wrong.)
ucheck "atuin daemon: a shell that never opted in unhooks the guard for good" \
  "source '$TOOLS_FILE'; [[ -n \${precmd_functions[(r)_core_atuin_daemon_guard]} ]] && { _core_atuin_daemon_guard; [[ -z \${precmd_functions[(r)_core_atuin_daemon_guard]} ]] }" \
  PATH="$ATBIN:$PATH" XDG_CACHE_HOME="$ATCACHE"
# (g) WATCHDOG, NOT ONE-SHOT — the regression that would silently reintroduce #366. An opted-in
#     shell with a LIVE daemon must KEEP the hook, arm the throttle deadline, and record that it
#     was ever healthy. Without all three the shell reverts to the old behaviour: fine at
#     startup, then blind for the rest of its life.
ucheck "atuin daemon: an opted-in shell with a live daemon KEEPS the guard hooked and arms the window" \
  "zmodload zsh/net/socket
   rm -f '$SANDBOX/wd-live.sock'; zsocket -l '$SANDBOX/wd-live.sock'
   source '$TOOLS_FILE'; _core_atuin_daemon_guard
   [[ \$ATUIN_DAEMON__ENABLED == true && -n \$_CORE_ATUIN_DAEMON_WAS_UP ]] || exit 1
   [[ -n \${precmd_functions[(r)_core_atuin_daemon_guard]} ]] || exit 1
   (( _CORE_ATUIN_DAEMON_NEXT > 0 ))" \
  PATH="$ATBIN:$PATH" XDG_CACHE_HOME="$ATCACHE" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/wd-live.sock"
# (h) THROTTLE — the other half of (g), and what keeps the prompt path honest. Kill the daemon
#     INSIDE the window and probe again: the guard must NOT connect, so the shell stays enabled
#     and undegraded. If this ever goes green→red the throttle is gone and every prompt is paying
#     a connect(2).
ucheck "atuin daemon: a second precmd inside the window does not re-connect (throttled)" \
  "zmodload zsh/net/socket
   rm -f '$SANDBOX/thr.sock'; zsocket -l '$SANDBOX/thr.sock'; LFD=\$REPLY
   source '$TOOLS_FILE'; _core_atuin_daemon_guard
   (( _CORE_ATUIN_DAEMON_NEXT > 0 )) || exit 1
   exec {LFD}>&-                                   # the daemon dies; the stale socket file remains
   [[ -S '$SANDBOX/thr.sock' ]] || exit 1
   _core_atuin_daemon_guard
   [[ \$ATUIN_DAEMON__ENABLED == true && -z \${_CORE_ATUIN_DAEMON_DEGRADED:-} ]]" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/thr.sock"
# (i) MID-SESSION DEATH — the whole point of #366, driven end to end without a sleep: healthy
#     probe, daemon dies, BACK-DATE the deadline to travel past the window, probe again. The
#     shell must degrade, unhook for good, and say so EXACTLY once — that warning is the only
#     signal a session which is already open ever gets.
ucheck "atuin daemon: past the window a mid-session death degrades, warns once and unhooks" \
  "zmodload zsh/net/socket
   rm -f '$SANDBOX/wd.sock' '$SANDBOX/wd.err'; zsocket -l '$SANDBOX/wd.sock'; LFD=\$REPLY
   source '$UI'; source '$TOOLS_FILE'
   _core_atuin_daemon_guard
   [[ -n \$_CORE_ATUIN_DAEMON_WAS_UP ]] || exit 1
   exec {LFD}>&-
   _CORE_ATUIN_DAEMON_NEXT=0                       # time travel: no sleep in this suite, ever
   _core_atuin_daemon_guard 2>'$SANDBOX/wd.err'
   [[ \$ATUIN_DAEMON__ENABLED == false && -n \$_CORE_ATUIN_DAEMON_DEGRADED ]] || exit 1
   [[ -z \${precmd_functions[(r)_core_atuin_daemon_guard]} ]] || exit 1
   grep -q 'atuin daemon' '$SANDBOX/wd.err'" \
  PATH="$ATBIN:$PATH" XDG_CACHE_HOME="$ATCACHE" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/wd.sock"
# (j) SILENT AT STARTUP — the other side of (i), and the assertion that stops a well-meant future
#     change turning this into startup noise on every machine whose daemon simply is not running.
#     A shell ALREADY degraded at its first prompt had nothing change under it, so it must
#     degrade with an EMPTY stderr.
ucheck "atuin daemon: a shell that started with the daemon already down degrades SILENTLY" \
  "rm -f '$SANDBOX/quiet.err'
   source '$UI'; source '$TOOLS_FILE'
   _core_atuin_daemon_guard 2>'$SANDBOX/quiet.err'
   [[ \$ATUIN_DAEMON__ENABLED == false && -n \$_CORE_ATUIN_DAEMON_DEGRADED ]] || exit 1
   [[ -z \${_CORE_ATUIN_DAEMON_WAS_UP:-} ]] || exit 1
   [[ ! -s '$SANDBOX/quiet.err' ]]" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/absent-atuin.sock"
# (k) CLOCK SKEW, FAIL-SAFE — a deadline further out than one window cannot mean "early", it
#     means the clock moved (backwards NTP step, resume from suspend, or the EPOCHSECONDS/SECONDS
#     fallback changing source mid-shell — they share no epoch). Honouring it would park the
#     watchdog for the length of the jump, SILENTLY, which is the failure this hook exists to
#     end. So the guard must probe anyway.
ucheck "atuin daemon: a deadline beyond one window means the clock moved — probe anyway" \
  "source '$TOOLS_FILE'
   _CORE_ATUIN_DAEMON_NEXT=\$(( \${EPOCHSECONDS:-SECONDS} + 10 * _CORE_ATUIN_DAEMON_INTERVAL ))
   _core_atuin_daemon_guard
   [[ \$ATUIN_DAEMON__ENABLED == false && -n \$_CORE_ATUIN_DAEMON_DEGRADED ]]" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/absent-atuin.sock"
# (l) THE WINDOW is a real number with a real escape hatch — the knob is what makes a box where
#     connect(2) on that path is NOT cheap (a socket on a networked or wedged FS) tunable without
#     patching Core, and what makes the manual repro take 5s instead of 60.
#     The override is set AFTER sourcing, which is the only test of it worth having: os/<os>.zsh
#     (80) and 99-local.zsh (99) load after 00-tools.zsh, so that is where a per-machine knob is
#     actually written. Setting it BEFORE the source — the obvious way to write this — passes
#     even when the guard reads the env at source time and therefore ignores every real override.
ucheck "atuin daemon: the probe window defaults to 60s and the first precmd is due immediately" \
  "source '$TOOLS_FILE'; (( _CORE_ATUIN_DAEMON_INTERVAL == 60 && _CORE_ATUIN_DAEMON_NEXT == 0 ))"
ucheck "atuin daemon: CORE_ATUIN_PROBE_INTERVAL set by a LATER fragment still overrides the window" \
  "source '$TOOLS_FILE'
   CORE_ATUIN_PROBE_INTERVAL=5           # as os/<os>.zsh or 99-local.zsh would: after 00, not before
   _core_atuin_daemon_guard
   (( _CORE_ATUIN_DAEMON_INTERVAL == 5 ))" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/absent-atuin.sock"
# (m) \$REPLY CROSS-TALK — `local REPLY` inside the guard was a nicety when it ran once before the
#     first prompt. As a persistent hook it runs between every pair of commands, where
#     read/vared/zsocket/completion all live in \$REPLY, so dropping it would produce an
#     intermittent, unreproducible bug. Pin it.
ucheck "atuin daemon: the guard does not clobber the caller's \$REPLY" \
  "source '$TOOLS_FILE'; REPLY=mine; _core_atuin_daemon_guard; [[ \$REPLY == mine ]]" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/absent-atuin.sock"
# (n)-(p) \$? TRANSPARENCY, on all four exit paths. As a one-shot the guard could return whatever
#     it liked: it ran once, before the first prompt, and unhooked. As a PERSISTENT precmd it sits
#     in the hook list for the life of the shell, so any precmd an OS (80) or host (99) fragment
#     appends AFTER it would see the guard's status instead of the user's command — a prompt that
#     never shows a failure again, and nothing in Core would notice. That is why the guard opens
#     with `local -i _rc=\$?` (before `emulate -L zsh`, which resets it) and returns \$_rc from
#     every exit. Four paths, so four exits: throttled, healthy, degrade, stand-down.
ucheck "atuin daemon: \$? survives the guard on the healthy and throttled paths" \
  "zmodload zsh/net/socket
   rm -f '$SANDBOX/rc-live.sock'; zsocket -l '$SANDBOX/rc-live.sock'
   source '$TOOLS_FILE'
   false; _core_atuin_daemon_guard; (( \$? == 1 )) || exit 1   # healthy probe: arms the window
   (( _CORE_ATUIN_DAEMON_NEXT > 0 )) || exit 1
   false; _core_atuin_daemon_guard; (( \$? == 1 )) || exit 1   # throttled: the gate's early return
   true;  _core_atuin_daemon_guard; (( \$? == 0 ))             # and a success survives too" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/rc-live.sock"
ucheck "atuin daemon: \$? survives the guard on the degrade path" \
  "source '$UI'; source '$TOOLS_FILE'
   false; _core_atuin_daemon_guard; (( \$? == 1 )) || exit 1
   [[ -n \$_CORE_ATUIN_DAEMON_DEGRADED ]]" \
  ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__SOCKET_PATH="$SANDBOX/absent-atuin.sock"
ucheck "atuin daemon: \$? survives the guard on the stand-down path" \
  "source '$TOOLS_FILE'; false; _core_atuin_daemon_guard; (( \$? == 1 ))"

# atuin/config.toml must NOT write `enabled`/`autostart` into [daemon]. atuin layers the
# config FILE after the Environment source (settings.rs), so the later file source wins and
# any key written here SHADOWS its ATUIN_* override — which silently disabled the entire
# per-machine opt-in the OS layers rely on (verified against 18.19.0: zero connect() calls
# to the socket with the key present, one with it absent). Upstream's own defaults are
# already false/false, so leaving them unset ships the same OFF default AND lets the
# override through. A static assertion because the behavioural proof needs an atuin binary,
# which CI does not have.
# PARSE the TOML rather than pattern-match its text. Grep can only ever cover the spellings
# someone thought of: a `[daemon]` table, the dotted `daemon.enabled = false`, the inline
# table `daemon = { enabled = false }`, and `daemon . enabled = false` (TOML permits
# whitespace around the dots) all deserialize to the same key, and a regex that catches two
# of them reports green on the other two. What matters is the key atuin ends up resolving,
# so ask the parser. `tomllib` is stdlib since 3.11 and is already how audit-core.sh's
# config gate works; the graceful skip mirrors that gate too.
if [[ ! -f "$HERE/atuin/config.toml" ]]; then
  skip "atuin config: daemon override check (no atuin/config.toml)"
elif ! have python3 || ! python3 -c 'import tomllib' 2>/dev/null; then
  skip "atuin config: daemon override check (python3 tomllib unavailable)"
else
  _atd="$(python3 -c '
import tomllib, sys
d = tomllib.load(open(sys.argv[1], "rb")).get("daemon") or {}
print(" ".join(f"{k}={d[k]!r}" for k in ("enabled", "autostart") if k in d))
' "$HERE/atuin/config.toml" 2>/dev/null)" || _atd="__PARSE_FAILED__"
  if [[ "$_atd" == "__PARSE_FAILED__" ]]; then
    # Distinct from "key present": a file that will not parse is a different defect, owned by
    # audit-core.sh's config gate. Still red here — this assertion cannot vouch for a file it
    # could not read, and failing closed is the only safe reading.
    fail "atuin config: atuin/config.toml does not parse as TOML — cannot verify the daemon keys"
  elif [[ -z "$_atd" ]]; then
    pass "atuin config: daemon.enabled/autostart absent from the parsed TOML (ATUIN_* override not shadowed)"
  else
    fail "atuin config: parsed TOML sets daemon $_atd — this shadows the ATUIN_DAEMON__* override and disables the opt-in"
  fi
fi

# maint.zsh: _maint_scheduler must always resolve to a REAL scheduler token, never empty
# or garbage. With systemctl absent (isolated PATH) and crontab present as the fallback,
# it lands on cron (Linux/Alpine) or launchd (macOS, OSTYPE-driven) — both valid — so the
# assertion is the same green on every CI userland while still exercising the full ladder.
_pm_only crontab
ucheck "maint: _maint_scheduler resolves to a valid scheduler" \
  "source '$UI'; source '$MNT'; [[ \$(_maint_scheduler) == (systemd|launchd|cron) ]]" \
  PATH="$PMBIN"
# maint-log defensive input (#6): a non-numeric N must be rejected in Core's voice, not
# handed to `tail` to fail with a raw "invalid number". -f/--follow and a positive int
# are the only valid args (mirrors serve/cdup/mkbak's input guards).
ucheck "maint: maint-log rejects a non-numeric N in Core's voice" \
  "source '$UI'; source '$MNT'; out=\$(maint-log abc 2>&1); (( \$? != 0 )) && [[ \$out == *'maint-log: N must be'* ]]" \
  PATH="$PMBIN"

# ── maint scheduler artifacts (systemd unit / launchd plist / cron line) ──────
# maint-install GENERATES a systemd unit+timer, a launchd plist (XML), and a cron line —
# fan-out artifacts that, until now, had NO gate: a malformed OnCalendar, a broken plist,
# or a bad cron field only fails on the user's box, then fans out to nine repos. Every OTHER
# fan-out artifact class is gated (toml/yaml/json §6, workflows actionlint §8); this closes
# the maint hole the same way. Hermetic: override _maint_scheduler to pick the branch,
# stub systemctl/launchctl/crontab to no-ops (so nothing touches the real system), sandbox
# HOME/XDG, render at 09:30, then VALIDATE the generated artifact. The runner path resolves
# to this repo's maint/dotfiles-maint.sh via maint.zsh's %x, so the [[ -f ]] guard passes.
hdr "maint scheduler artifacts (systemd / launchd / cron, hermetic render)"
SCHEDBIN="$SANDBOX/schedbin"
mkdir -p "$SCHEDBIN"
for s in systemctl launchctl; do
  printf '#!/bin/sh\n:\n' >"$SCHEDBIN/$s"
  chmod +x "$SCHEDBIN/$s"
done
# crontab stub: `-l` prints nothing (no existing table); `-` captures the new table to a
# file so we can assert the generated line instead of mutating the real crontab.
printf '#!/bin/sh\ncase "$1" in -l) exit 0 ;; -) cat > "$CRON_CAPTURE" ;; *) exit 0 ;; esac\n' >"$SCHEDBIN/crontab"
chmod +x "$SCHEDBIN/crontab"

# systemd: the timer's OnCalendar must be the rendered HH:MM, and the service must point
# ExecStart at the runner. Override the scheduler so the branch runs on any host.
ucheck "maint: systemd timer+service render with a valid OnCalendar" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; maint-install 09:30 >/dev/null 2>&1; ud=\"\$XDG_CONFIG_HOME/systemd/user\"; [[ -f \"\$ud/dotfiles-maint.timer\" && -f \"\$ud/dotfiles-maint.service\" ]] || exit 1; grep -q 'OnCalendar=\*-\*-\* 09:30:00' \"\$ud/dotfiles-maint.timer\" || exit 1; grep -q 'ExecStart=.*dotfiles-maint.sh' \"\$ud/dotfiles-maint.service\"" \
  PATH="$SCHEDBIN:$PATH" XDG_CONFIG_HOME="$SANDBOX/sched-systemd"
# cron: the captured table line must be a well-formed 5-field schedule at MM HH, tagged.
# The runner is single-quoted, which is part of the contract rather than incidental: cron's
# command field is handed to /bin/sh, so a bare runner is split on whitespace and a $(…) in
# the path would be evaluated on every scheduled run. Anchoring on the closing quote is what
# makes dropping the quoting fail HERE rather than on the one box whose path contains a space.
ucheck "maint: cron line renders as a valid 5-field schedule with the runner quoted" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; maint-install 09:30 >/dev/null 2>&1; [[ -f \"\$CRON_CAPTURE\" ]] || exit 1; grep -qE '^30 09 \* \* \* .*dotfiles-maint\.sh'\\'' # dotfiles-maint\$' \"\$CRON_CAPTURE\"" \
  PATH="$SCHEDBIN:$PATH" CRON_CAPTURE="$SANDBOX/cron.captured"
# launchd: the plist must be WELL-FORMED XML (plistlib parses it) with the rendered
# Hour/Minute — the one artifact that's silent text the other gates never inspect. Needs
# python3 (stdlib plistlib); skip gracefully otherwise, like the linters above.
if have python3; then
  ucheck "maint: launchd plist is well-formed XML with the rendered Hour/Minute" \
    "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; maint-install 09:30 >/dev/null 2>&1; p=\"\$HOME/Library/LaunchAgents/com.dotfiles.maint.plist\"; [[ -f \"\$p\" ]] || exit 1; python3 -c 'import sys,plistlib; d=plistlib.load(open(sys.argv[1],\"rb\")); s=d[\"StartCalendarInterval\"]; sys.exit(0 if s[\"Hour\"]==9 and s[\"Minute\"]==30 else 1)' \"\$p\"" \
    PATH="$SCHEDBIN:$PATH" HOME="$SANDBOX/sched-launchd"
else
  skip "maint launchd plist (python3 absent — cannot parse plist XML)"
fi

# ── the PATH capture (the one seam where an OS prefix may enter the runner) ───
# maint/dotfiles-maint.sh is portable Core and names no Homebrew/pkgsrc/Nix prefix, so
# the scheduler unit is the ONLY thing that tells the unattended runner where this box
# keeps its binaries. Drop the capture in a refactor and nothing breaks loudly: the job
# still fires, still logs, still exits 0 — it just resolves no brew/mise and skips those
# steps silently. That is why this is asserted per-scheduler rather than trusted.
# A /sentinel/bin injected into PATH at install time must appear in the rendered unit.
ucheck "maint: systemd unit bakes in the installing shell's PATH" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; PATH=/sentinel/bin:\$PATH maint-install 09:30 >/dev/null 2>&1; grep -q '^Environment=\"PATH=.*/sentinel/bin' \"\$XDG_CONFIG_HOME/systemd/user/dotfiles-maint.service\"" \
  PATH="$SCHEDBIN:$PATH" XDG_CONFIG_HOME="$SANDBOX/sched-path-systemd"
# cron's command field is sh, so the PATH rides as an env prefix — and `%` is cron's
# newline metacharacter, which would truncate the line mid-PATH if it were not escaped.
# The sentinel deliberately contains one.
ucheck "maint: cron line carries the PATH, single-quoted, with % escaped" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; PATH='/sent%inel/bin':\$PATH maint-install 09:30 >/dev/null 2>&1; line=\$(cat \"\$CRON_CAPTURE\"); [[ \$line == *\"PATH='\"* ]] && [[ \$line == *'sent\\%inel'* ]]" \
  PATH="$SCHEDBIN:$PATH" CRON_CAPTURE="$SANDBOX/cron-path.captured"
# The decisive one. cron's command field is handed to /bin/sh, so a PATH entry holding
# $(…), a backtick, or a quote is CODE unless it is quoted as DATA — an unquoted or
# double-quoted assignment would evaluate it on every scheduled run, silently and with
# the user's privileges. Build the assignment exactly as maint-install does, then let a
# real /bin/sh parse it back and compare: nothing but a true round-trip passes this.
_mq_want='/we'"'"'ird/$(echo pwned)/`echo pwned`/"dq"/bin'
_mq_rendered="$(zsh -c "source '$UI'; source '$MNT'; _maint_sh_squote \"\$1\"" _ "$_mq_want" 2>/dev/null)"
_mq_got="$(sh -c "PATH=$_mq_rendered; printf '%s' \"\$PATH\"" 2>/dev/null)"
if [[ "$_mq_got" == "$_mq_want" ]]; then
  pass "maint: a hostile PATH round-trips through /bin/sh as data (no \$() evaluation)"
else
  fail "maint: PATH did not round-trip through sh (got '$_mq_got')"
fi
# launchd's plist is XML: an unescaped & in a directory name yields a malformed plist
# that launchctl rejects at load time, i.e. a schedule that silently never runs. Assert
# plistlib can still PARSE it and that the value round-trips — the escape and the parse
# together, since either alone would pass while the pair is broken.
if have python3; then
  ucheck "maint: launchd plist XML-escapes the PATH and still parses" \
    "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; PATH='/a&b/bin':\$PATH maint-install 09:30 >/dev/null 2>&1; python3 -c 'import sys,plistlib; d=plistlib.load(open(sys.argv[1],\"rb\")); sys.exit(0 if \"/a&b/bin\" in d[\"EnvironmentVariables\"][\"PATH\"] else 1)' \"\$HOME/Library/LaunchAgents/com.dotfiles.maint.plist\"" \
    PATH="$SCHEDBIN:$PATH" HOME="$SANDBOX/sched-path-launchd"
else
  skip "maint launchd PATH capture (python3 absent — cannot parse plist XML)"
fi
# systemd expands % SPECIFIERS inside Environment= (%h = home, %i = instance, …), so a
# legitimate PATH entry like /sent%h/bin would silently become /sent<homedir>/bin — or
# the unit would refuse to load on an unknown specifier. Quotes and backslashes carry
# unit-file syntax there too. Assert the three documented substitutions against a
# literal expectation rather than round-tripping through a reimplementation of the rule.
_ms_got="$(zsh -c "source '$UI'; source '$MNT'; _maint_systemd_escape \"\$1\"" _ '/a%h/b"c/d\e/bin' 2>/dev/null)"
_ms_want='/a%%h/b\"c/d\\e/bin'
if [[ "$_ms_got" == "$_ms_want" ]]; then
  pass "maint: systemd Environment= escapes %, \" and \\ (no specifier expansion)"
else
  fail "maint: systemd escape wrong (got '$_ms_got' want '$_ms_want')"
fi
# ...and the rendered unit actually carries it, so the helper cannot be wired up wrong.
ucheck "maint: the systemd unit's PATH survives a % in the installing PATH" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; PATH='/sent%h/bin':\$PATH maint-install 09:30 >/dev/null 2>&1; grep -q 'Environment=\"PATH=/sent%%h/bin' \"\$XDG_CONFIG_HOME/systemd/user/dotfiles-maint.service\"" \
  PATH="$SCHEDBIN:$PATH" XDG_CONFIG_HOME="$SANDBOX/sched-pct-systemd"

# ── the stale-unit detector (_maint_unit_needs_refresh) ──────────────────────
# This is what makes the migration survivable. A unit written before the PATH capture
# still fires, still logs, still exits 0 — and silently resolves no brew/mise. maint-status
# is the ONLY place that can surface it, so the detector is load-bearing rather than a
# nicety.
#
# The SECOND silent death is a unit whose recorded runner path no longer resolves: move
# the consuming repo and the scheduler keeps firing at the old absolute path. Observed in
# the wild, and invisible from every angle — `maint-status` printed the timer happily,
# `launchctl list` reported exit status 0 (the job had not fired since the move), and
# `maint-run` kept working because it re-resolves the runner from the live config rather
# than reading the unit. Only reading the unit back catches it, so each arm is asserted
# per-scheduler with a REAL runner path for the healthy fixture — point the "current"
# fixtures at a path that does not exist and this whole section passes vacuously.
#
# Four states per scheduler, and the last matters as much as the others: a box with NO
# schedule installed must stay quiet, or every such box is nagged forever.
_MRF="$SANDBOX/maint-refresh"
_MRF_RUNNER="$HERE/maint/dotfiles-maint.sh" # a path that really exists
_MRF_GONE="$_MRF/moved-away/core/maint/dotfiles-maint.sh"
rm -rf "$_MRF"
mkdir -p "$_MRF/bin" "$_MRF/sd-new/systemd/user" "$_MRF/sd-old/systemd/user" \
  "$_MRF/sd-dead/systemd/user" "$_MRF/sd-none" \
  "$_MRF/ld-new/Library/LaunchAgents" "$_MRF/ld-old/Library/LaunchAgents" \
  "$_MRF/ld-dead/Library/LaunchAgents" "$_MRF/ld-none"
printf '[Service]\nEnvironment="PATH=/x/bin"\nExecStart=/usr/bin/env bash %s\n' "$_MRF_RUNNER" \
  >"$_MRF/sd-new/systemd/user/dotfiles-maint.service"
printf '[Service]\nExecStart=/usr/bin/env bash %s\n' "$_MRF_RUNNER" \
  >"$_MRF/sd-old/systemd/user/dotfiles-maint.service"
printf '[Service]\nEnvironment="PATH=/x/bin"\nExecStart=/usr/bin/env bash %s\n' "$_MRF_GONE" \
  >"$_MRF/sd-dead/systemd/user/dotfiles-maint.service"
printf '<plist><dict><key>ProgramArguments</key><array><string>/bin/bash</string><string>%s</string></array><key>EnvironmentVariables</key><dict><key>PATH</key><string>/x/bin</string></dict></dict></plist>\n' \
  "$_MRF_RUNNER" >"$_MRF/ld-new/Library/LaunchAgents/com.dotfiles.maint.plist"
# ld-old is precisely the case a bare `EnvironmentVariables` presence test MISSES: the
# dict exists but carries no PATH, so the runner is still handed a stripped environment
# while the detector reports the schedule as current.
printf '<plist><dict><key>EnvironmentVariables</key><dict><key>LANG</key><string>C</string></dict></dict></plist>\n' \
  >"$_MRF/ld-old/Library/LaunchAgents/com.dotfiles.maint.plist"
# ld-dead is the observed macOS case, rendered as maint-install writes it (ProgramArguments
# on its own line, argv[0] the interpreter) so the argv[1] extraction is exercised for real.
printf '<plist><dict>\n  <key>ProgramArguments</key>\n  <array><string>/bin/bash</string><string>%s</string></array>\n  <key>EnvironmentVariables</key>\n  <dict><key>PATH</key><string>/x/bin</string></dict>\n</dict></plist>\n' \
  "$_MRF_GONE" >"$_MRF/ld-dead/Library/LaunchAgents/com.dotfiles.maint.plist"
printf '#!/bin/sh\ncase "$1" in -l) cat "${CRON_TABLE:-/dev/null}" ;; *) exit 0 ;; esac\n' >"$_MRF/bin/crontab"
chmod +x "$_MRF/bin/crontab"
# The PATH prefix is SINGLE-quoted, as _maint_sh_squote renders it — the runner extraction
# has to step over that assignment, so a fixture using bare or double quotes would let a
# parser that simply grabbed field 6 pass.
printf "30 09 * * * PATH='/x/bin' /usr/bin/env bash %s # dotfiles-maint\n" "$_MRF_RUNNER" >"$_MRF/cron-new"
printf '30 09 * * * /usr/bin/env bash %s # dotfiles-maint\n' "$_MRF_RUNNER" >"$_MRF/cron-old"
printf "30 09 * * * PATH='/x/bin' /usr/bin/env bash %s # dotfiles-maint\n" "$_MRF_GONE" >"$_MRF/cron-dead"
: >"$_MRF/cron-none"

ucheck "maint/refresh: systemd unit WITH the PATH capture and a resolvable runner is current" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; ! _maint_unit_needs_refresh" \
  XDG_CONFIG_HOME="$_MRF/sd-new"
ucheck "maint/refresh: systemd unit WITHOUT it is flagged stale (why=path)" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; _maint_unit_needs_refresh && [[ \$_MAINT_REFRESH_WHY == path ]]" \
  XDG_CONFIG_HOME="$_MRF/sd-old"
ucheck "maint/refresh: systemd unit whose runner path is gone is flagged (why=runner)" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; _maint_unit_needs_refresh && [[ \$_MAINT_REFRESH_WHY == runner ]]" \
  XDG_CONFIG_HOME="$_MRF/sd-dead"
ucheck "maint/refresh: no systemd unit at all stays quiet (no nag without a schedule)" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; ! _maint_unit_needs_refresh" \
  XDG_CONFIG_HOME="$_MRF/sd-none"
ucheck "maint/refresh: launchd plist WITH a PATH key and a resolvable runner is current" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; ! _maint_unit_needs_refresh" \
  HOME="$_MRF/ld-new"
ucheck "maint/refresh: launchd plist with EnvironmentVariables but NO PATH is flagged stale (why=path)" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; _maint_unit_needs_refresh && [[ \$_MAINT_REFRESH_WHY == path ]]" \
  HOME="$_MRF/ld-old"
ucheck "maint/refresh: launchd plist whose ProgramArguments runner is gone is flagged (why=runner)" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; _maint_unit_needs_refresh && [[ \$_MAINT_REFRESH_WHY == runner ]]" \
  HOME="$_MRF/ld-dead"
ucheck "maint/refresh: no launchd plist at all stays quiet" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; ! _maint_unit_needs_refresh" \
  HOME="$_MRF/ld-none"
ucheck "maint/refresh: cron line carrying a PATH and a resolvable runner is current" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; ! _maint_unit_needs_refresh" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-new"
ucheck "maint/refresh: cron line without a PATH is flagged stale (why=path)" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; _maint_unit_needs_refresh && [[ \$_MAINT_REFRESH_WHY == path ]]" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-old"
ucheck "maint/refresh: cron line whose runner path is gone is flagged (why=runner)" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; _maint_unit_needs_refresh && [[ \$_MAINT_REFRESH_WHY == runner ]]" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-dead"
ucheck "maint/refresh: an empty crontab stays quiet" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; ! _maint_unit_needs_refresh" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-none"
# The runner a unit records must be read back VERBATIM — the hint prints it, and an
# extraction that mangled it (dropping the PATH prefix's quoting, or half a path with a
# space) would still "detect" a dead runner while telling the operator the wrong path.
ucheck "maint/refresh: the recorded runner path is read back verbatim (launchd argv[1])" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; [[ \"\$(_maint_unit_runner)\" == '$_MRF_GONE' ]]" \
  HOME="$_MRF/ld-dead"
ucheck "maint/refresh: the recorded runner path is read back verbatim (cron, past the PATH prefix)" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; [[ \"\$(_maint_unit_runner)\" == '$_MRF_GONE' ]]" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-dead"

# ── the runner path is DATA in three different grammars ──────────────────────
# maint-install escapes the captured PATH per scheduler but wrote the RUNNER raw, and the
# runner is not a constant: it is wherever the consuming repo was cloned to. Every one of
# the three failures is silent or nearly so, which is why they survived —
#
#   systemd  % is a SPECIFIER in ExecStart, so a repo under …/a%h/… runs a different path
#            (or the unit refuses to load on an unknown one); an unquoted argument is also
#            split on whitespace, and " / \ carry unit-file syntax.
#   cron     % is cron's NEWLINE metacharacter: the command is truncated there and the
#            remainder is fed to it as stdin, so the job simply stops running. Unquoted,
#            the command field is also sh, so a space splits it and $(…) is CODE.
#   launchd  & < > make the plist malformed and `launchctl load` rejects it.
#
# One fixture path carries all of it — % space & < > " \ ' — and each arm asserts the full
# loop: maint-install renders it, _maint_unit_runner reads it back VERBATIM, and the unit
# reads as CURRENT rather than as a dead runner. That last part is the user-visible bug:
# before this, a repo at such a path got a broken schedule AND a maint-status that either
# said nothing or named the wrong file.
#
# The pre-existing fixtures above all use the older UNQUOTED shapes, so they double as the
# backward-compatibility gate: units already on disk are only rewritten when the operator
# re-runs maint-install, and must keep parsing until they do.
# Every hazard in one component. The last four are the ones a "looks about right" fixture
# misses: `$i`/`${j}` because systemd substitutes VARIABLES in ExecStart on top of its %
# specifiers, and `\n`/`\c` because they are the two-character sequences zsh's `echo`
# builtin would rewrite — `\c` truncating the crontab line outright. An earlier revision of
# this fixture used `\g`, which is not a recognized escape, so the whole hazard sat
# unexercised while the assertion read green.
_MRF_HOSTILE_DIR="$_MRF/hostile/a%h b&c<d>e\"f\\g'h\$i\${j}\\nk\\cl"
_MRF_HOSTILE="$_MRF_HOSTILE_DIR/dotfiles-maint.sh"
if mkdir -p "$_MRF_HOSTILE_DIR" 2>/dev/null && printf '#!/bin/bash\n:\n' >"$_MRF_HOSTILE" 2>/dev/null; then
  # A crontab stub that ROUND-TRIPS: `-` stores the table, `-l` reads that same table back.
  # The one above is read-only, and install-then-read is the whole point here.
  mkdir -p "$_MRF/rtbin"
  printf '#!/bin/sh\ncase "$1" in -l) [ -f "$CRON_TABLE" ] && cat "$CRON_TABLE"; exit 0 ;; -) cat > "$CRON_TABLE" ;; *) exit 0 ;; esac\n' >"$_MRF/rtbin/crontab"
  chmod +x "$_MRF/rtbin/crontab"
  : >"$_MRF/cron-hostile"
  # The path rides in through the ENVIRONMENT — it holds a single quote, a double quote and
  # a backslash, so interpolating it into the assertion body would rewrite the body itself.
  _MRF_RT="source '$UI'; source '$MNT'; _MAINT_SH=\"\$SH\"; _maint_scheduler() { echo SCHED }; maint-install 09:30 >/dev/null 2>&1; [[ \"\$(_maint_unit_runner)\" == \"\$SH\" ]] && ! _maint_unit_needs_refresh"

  ucheck "maint/refresh: a runner path holding % \$ \" \\ and a space round-trips through the systemd unit" \
    "${_MRF_RT/SCHED/systemd}" \
    PATH="$SCHEDBIN:$PATH" XDG_CONFIG_HOME="$_MRF/rt-sd" SH="$_MRF_HOSTILE"
  ucheck "maint/refresh: a runner path holding & < > and a quote round-trips through the launchd plist" \
    "${_MRF_RT/SCHED/launchd}" \
    PATH="$SCHEDBIN:$PATH" HOME="$_MRF/rt-ld" SH="$_MRF_HOSTILE"
  ucheck "maint/refresh: a runner path holding % and shell metacharacters round-trips through the cron line" \
    "${_MRF_RT/SCHED/cron}" \
    PATH="$_MRF/rtbin:$SCHEDBIN:$PATH" CRON_TABLE="$_MRF/cron-hostile" SH="$_MRF_HOSTILE"

  # ...and the same three artifacts read by something that is NOT this codebase. A round-trip
  # through our own reader proves only that the two halves AGREE — escape it wrongly and
  # unescape it wrongly the same way and the assertions above stay green while the scheduler
  # runs nothing. These pin the emitted text against the real grammar instead, the way the
  # PATH assertions already do.
  #
  # systemd has no parser to borrow on a macOS runner, so it gets the literal expectation:
  # the ONE directory component is spelled out post-escape (% doubled, " and \ backslashed)
  # rather than recomputed here — restating the rule in the test would let a wrong rule pass.
  if grep -qF 'ExecStart=/usr/bin/env bash "' "$_MRF/rt-sd/systemd/user/dotfiles-maint.service" 2>/dev/null &&
    grep -qF 'a%%h b&c<d>e\"f\\g'"'"'h$$i$${j}\\nk\\cl/dotfiles-maint.sh"' "$_MRF/rt-sd/systemd/user/dotfiles-maint.service" 2>/dev/null; then
    pass "maint: the systemd ExecStart runner is quoted with %, \$, \" and \\ escaped"
  else
    fail "maint: the systemd ExecStart runner is not escaped as expected"
  fi
  # cron: let a real /bin/sh parse the command back, after applying cron's OWN pass (\% → %)
  # exactly as crond would before handing the field over. Exactly one argument must come out
  # of it, spelled the same as the file on disk.
  # ONE line, AND that line reaches its terminating marker. maint-install runs under
  # `emulate -L zsh`, where `echo` interprets backslash escapes, so a `\n` in the runner
  # splits the entry in two and a `\c` truncates it and swallows the trailing newline.
  #
  # BOTH halves are needed, and the reason is worth stating because the obvious single check
  # does not work: with this fixture the two corruptions CANCEL in the line count — `\n`
  # adds a newline, `\c` removes the final one, and a line count of exactly 1 comes back
  # from a table that is in fact one wrapped fragment plus one unterminated one. What the
  # truncation cannot fake is arriving at the marker, since everything past the `\c` is
  # gone. Verified against a reverted copy of the module: `echo` yields marker-terminated=0
  # while `print -r` yields 1, with the line count reading 1 for both.
  _mr_nlines="$(wc -l <"$_MRF/cron-hostile" 2>/dev/null | tr -d ' ')"
  _mr_tagged="$(grep -c '# dotfiles-maint$' "$_MRF/cron-hostile" 2>/dev/null || true)"
  if [[ "$_mr_nlines" == 1 && "$_mr_tagged" == 1 ]]; then
    pass "maint: the cron entry is one marker-terminated line (no echo-escape split or truncation)"
  else
    fail "maint: cron table is $_mr_nlines line(s), $_mr_tagged marker-terminated — a backslash escape corrupted the entry"
  fi
  _mr_line="$(cat "$_MRF/cron-hostile" 2>/dev/null)"
  # A BARE % is one left over once every escaped \% is accounted for — testing for the
  # mere presence of \% would pass a line that escaped the PATH's % and not the runner's.
  if [[ "${_mr_line//\\%/}" == *'%'* ]]; then
    fail "maint: the cron line carries a BARE % — crond truncates the command there"
  else
    _mr_tok="${_mr_line% # dotfiles-maint}"
    _mr_tok="${_mr_tok#*"/usr/bin/env bash "}"
    _mr_tok="${_mr_tok//\\%/%}" # cron's own unescape
    _mr_got="$(sh -c "set -- $_mr_tok; printf '%s|%s' \"\$#\" \"\$1\"" 2>/dev/null)"
    if [[ "$_mr_got" == "1|$_MRF_HOSTILE" ]]; then
      pass "maint: the cron runner survives cron's % pass and reaches sh as one argument"
    else
      fail "maint: cron runner did not round-trip through sh (got '$_mr_got')"
    fi
  fi
  # launchd: plistlib is the third party, as it is for the PATH value two sections up.
  if have python3; then
    if python3 -c 'import sys,plistlib; d=plistlib.load(open(sys.argv[1],"rb")); sys.exit(0 if d["ProgramArguments"][1]==sys.argv[2] else 1)' \
      "$_MRF/rt-ld/Library/LaunchAgents/com.dotfiles.maint.plist" "$_MRF_HOSTILE" 2>/dev/null; then
      pass "maint: the launchd plist still parses and ProgramArguments[1] is the real path"
    else
      fail "maint: the launchd plist is malformed or ProgramArguments[1] is not the runner"
    fi
  else
    skip "maint launchd runner escape (python3 absent — cannot parse plist XML)"
  fi
else
  # Some filesystems (a CI runner on exFAT, a Windows-hosted mount) reject " or \ in a
  # name. Skipping is honest; silently passing would vouch for an escape never exercised.
  skip "maint runner-path escaping (this filesystem rejects a name holding \" or \\)"
fi

# The refusals — the other half of the contract, and the half that decides whether this
# feature is trustworthy. systemd's ExecStart and cron's command field are COMMANDS, not
# path fields, so a parse that swallows the whole tail turns `bash /a/live/runner --quiet`
# into the nonexistent path "/a/live/runner --quiet" and reports a HEALTHY job as dead.
# The launchd equivalent is an `<array>` that is not ProgramArguments' own value: skip over
# a non-array value there and the parser lifts the second string out of whatever key owns
# the NEXT array, naming a path the unit never runs. Each fixture below runs a runner that
# genuinely EXISTS, so a regression here is a false death notice, not a missed one.
mkdir -p "$_MRF/sd-args/systemd/user" "$_MRF/ld-displaced/Library/LaunchAgents"
printf '[Service]\nEnvironment="PATH=/x/bin"\nExecStart=/usr/bin/env bash %s --quiet\n' "$_MRF_RUNNER" \
  >"$_MRF/sd-args/systemd/user/dotfiles-maint.service"
printf "30 09 * * * PATH='/x/bin' /usr/bin/env bash %s >>/tmp/m.log # dotfiles-maint\n" "$_MRF_RUNNER" \
  >"$_MRF/cron-args"
printf '<plist><dict><key>ProgramArguments</key><string>%s</string><key>WatchPaths</key><array><string>/a</string><string>%s</string></array><key>EnvironmentVariables</key><dict><key>PATH</key><string>/x/bin</string></dict></dict></plist>\n' \
  "$_MRF_RUNNER" "$_MRF_GONE" >"$_MRF/ld-displaced/Library/LaunchAgents/com.dotfiles.maint.plist"

ucheck "maint/refresh: a systemd ExecStart with extra argv is refused, not read as one path" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  XDG_CONFIG_HOME="$_MRF/sd-args"
ucheck "maint/refresh: a cron command with a redirection is refused, not read as one path" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-args"
ucheck "maint/refresh: a later key's <array> is not mistaken for ProgramArguments'" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  HOME="$_MRF/ld-displaced"

# The same rule against the QUOTED shapes, where "one argument" is a property of where the
# closing quote sits rather than of whitespace. Both fixtures run a runner that exists, so
# a regression is again a false death notice. The third is the quoted counterpart of the
# `%` refusal below: there, a bare `%` reaches `_maint_lone_arg` and is rejected because
# nothing escaped it; here the value IS escaped, so a SINGLE `%` inside the quotes is a
# specifier that survived — a path we cannot reconstruct without reimplementing systemd's
# table, and therefore not evidence of anything either.
mkdir -p "$_MRF/sd-qargs/systemd/user" "$_MRF/sd-spec/systemd/user"
printf '[Service]\nEnvironment="PATH=/x/bin"\nExecStart=/usr/bin/env bash "%s" --quiet\n' "$_MRF_RUNNER" \
  >"$_MRF/sd-qargs/systemd/user/dotfiles-maint.service"
printf '[Service]\nEnvironment="PATH=/x/bin"\nExecStart=/usr/bin/env bash "/a%%h/dotfiles-maint.sh"\n' \
  >"$_MRF/sd-spec/systemd/user/dotfiles-maint.service"
printf "30 09 * * * PATH='/x/bin' /usr/bin/env bash '%s' >>/tmp/m.log # dotfiles-maint\n" "$_MRF_RUNNER" \
  >"$_MRF/cron-qargs"

ucheck "maint/refresh: a quoted systemd runner with argv after the closing quote is refused" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  XDG_CONFIG_HOME="$_MRF/sd-qargs"
ucheck "maint/refresh: a QUOTED systemd runner holding an unresolved % specifier is refused" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  XDG_CONFIG_HOME="$_MRF/sd-spec"
ucheck "maint/refresh: a quoted cron runner with a redirection after it is refused" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-qargs"

# The two metacharacters that sh QUOTING does not save you from, one per scheduler. cron
# translates % before sh ever sees the field, so a bare % inside the quotes still truncates
# the command; systemd substitutes $VAR inside double quotes, so `$HOME` there is not the
# path it runs. Both fixtures name a runner that RESOLVES if the metacharacter is merely
# ignored — so a reader that failed to refuse would hand back a confident wrong verdict
# about a job that does not run, which is worse than the noisy kind.
printf "30 09 * * * PATH='/x/bin' /usr/bin/env bash '%s' # dotfiles-maint\n" "$_MRF_RUNNER%h" \
  >"$_MRF/cron-qpct"
mkdir -p "$_MRF/sd-qvar/systemd/user"
printf '[Service]\nEnvironment="PATH=/x/bin"\nExecStart=/usr/bin/env bash "%s$HOME"\n' "$_MRF_RUNNER" \
  >"$_MRF/sd-qvar/systemd/user/dotfiles-maint.service"

ucheck "maint/refresh: a QUOTED cron runner carrying a bare % is refused (quoting is no defence)" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-qpct"
ucheck "maint/refresh: a QUOTED systemd runner carrying a \$VAR reference is refused" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  XDG_CONFIG_HOME="$_MRF/sd-qvar"

# A RELATIVE recorded runner is the one value that cannot be tested at all: `[[ -f ]]`
# resolves it against whatever directory maint-status was invoked from, so the same unit
# would read dead in one shell and alive in another — a verdict about the caller, not the
# unit. maint-install never writes one ($_MAINT_SH is `:A`-resolved at the top of the
# module), and a hand-edited unit can legitimately pair a relative script with systemd's
# WorkingDirectory= or cron's implicit $HOME. All three arms must stay quiet.
mkdir -p "$_MRF/sd-rel/systemd/user" "$_MRF/ld-rel/Library/LaunchAgents"
_MRF_REL='core/maint/dotfiles-maint.sh'
printf '[Service]\nEnvironment="PATH=/x/bin"\nExecStart=/usr/bin/env bash %s\n' "$_MRF_REL" \
  >"$_MRF/sd-rel/systemd/user/dotfiles-maint.service"
printf "30 09 * * * PATH='/x/bin' /usr/bin/env bash %s # dotfiles-maint\n" "$_MRF_REL" >"$_MRF/cron-rel"
printf '<plist><dict><key>ProgramArguments</key><array><string>/bin/bash</string><string>%s</string></array><key>EnvironmentVariables</key><dict><key>PATH</key><string>/x/bin</string></dict></dict></plist>\n' \
  "$_MRF_REL" >"$_MRF/ld-rel/Library/LaunchAgents/com.dotfiles.maint.plist"

ucheck "maint/refresh: a relative systemd runner is refused (verdict must not depend on cwd)" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  XDG_CONFIG_HOME="$_MRF/sd-rel"
ucheck "maint/refresh: a relative cron runner is refused (verdict must not depend on cwd)" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-rel"
ucheck "maint/refresh: a relative launchd runner is refused (verdict must not depend on cwd)" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  HOME="$_MRF/ld-rel"

# The last way to name a path the unit does not actually run: read an argument belonging to
# some OTHER program. Both fixtures below are healthy jobs — `/bin/echo /missing` succeeds —
# so extracting `/missing` from either would be a death notice for a live schedule. The
# interpreter has to be identified by POSITION (launchd argv[0]; cron's command, anchored to
# the closing quote of the PATH assignment), not merely found somewhere in the unit.
mkdir -p "$_MRF/ld-argv0/Library/LaunchAgents"
printf '<plist><dict><key>ProgramArguments</key><array><string>/bin/echo</string><string>%s</string></array><key>EnvironmentVariables</key><dict><key>PATH</key><string>/x/bin</string></dict></dict></plist>\n' \
  "$_MRF_GONE" >"$_MRF/ld-argv0/Library/LaunchAgents/com.dotfiles.maint.plist"
printf "30 09 * * * PATH='/x/bin' /bin/echo /usr/bin/env bash %s # dotfiles-maint\n" "$_MRF_GONE" >"$_MRF/cron-spliced"

ucheck "maint/refresh: a launchd argv[0] that is not the interpreter is refused" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  HOME="$_MRF/ld-argv0"
ucheck "maint/refresh: a cron command with another program spliced before the interpreter is refused" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-spliced"

# ...and the version of that splice which HIDES the anchor inside a quoted argument. This
# is why the PATH value is consumed as a real single-quoted token (_maint_squote_rest)
# rather than located by searching: `/bin/echo '␣/usr/bin/env bash /missing'` runs echo and
# is healthy, but contains a quote followed by the exact interpreter text, so any
# appearance-based anchor reads /missing back as our runner. The escaped-quote fixture is
# the other half — the scanner must step OVER a '\'' inside the value, or a legitimate
# PATH containing an apostrophe would stop the scan early and lose the real runner.
printf "30 09 * * * PATH='/x' /bin/echo ' /usr/bin/env bash %s' # dotfiles-maint\n" "$_MRF_GONE" >"$_MRF/cron-quoted"
printf "30 09 * * * PATH='/we'\\\\''ird/bin' /usr/bin/env bash %s # dotfiles-maint\n" "$_MRF_GONE" >"$_MRF/cron-squote"

ucheck "maint/refresh: a cron argument that merely QUOTES the interpreter text is refused" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-quoted"
ucheck "maint/refresh: a PATH value containing an escaped quote does not derail the scan" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; [[ \"\$(_maint_unit_runner)\" == '$_MRF_GONE' ]]" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-squote"

# launchd entity decoding. A plist may legally encode a quote as &quot;/&apos;, and launchd
# resolves it to the real filename — returning the encoded text would name a path that does
# not exist and call a live job dead. Anything we CANNOT decode (a numeric reference, an
# unknown entity) is refused for the same reason, from the other direction: a filename we
# cannot reconstruct is not evidence of anything.
mkdir -p "$_MRF/ld-entity/Library/LaunchAgents" "$_MRF/ld-numref/Library/LaunchAgents"
_MRF_QUOTED="$_MRF/moved'away/core/maint/dotfiles-maint.sh"
printf '<plist><dict><key>ProgramArguments</key><array><string>/bin/bash</string><string>%s/moved&apos;away/core/maint/dotfiles-maint.sh</string></array><key>EnvironmentVariables</key><dict><key>PATH</key><string>/x/bin</string></dict></dict></plist>\n' \
  "$_MRF" >"$_MRF/ld-entity/Library/LaunchAgents/com.dotfiles.maint.plist"
printf '<plist><dict><key>ProgramArguments</key><array><string>/bin/bash</string><string>%s&#47;gone&#47;dotfiles-maint.sh</string></array><key>EnvironmentVariables</key><dict><key>PATH</key><string>/x/bin</string></dict></dict></plist>\n' \
  "$_MRF" >"$_MRF/ld-numref/Library/LaunchAgents/com.dotfiles.maint.plist"

# The expectation rides in via the ENVIRONMENT, not interpolated into the assertion text:
# the whole point of this fixture is a path containing a single quote, which would close
# the quoting of the body itself. (The other verbatim checks above interpolate safely only
# because their paths happen to hold no quote — a hazard of the harness, not of the code.)
ucheck "maint/refresh: launchd decodes &apos; so the hint names the real filename" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; [[ \"\$(_maint_unit_runner)\" == \"\$WANT\" ]] && _maint_unit_needs_refresh && [[ \$_MAINT_REFRESH_WHY == runner ]]" \
  HOME="$_MRF/ld-entity" WANT="$_MRF_QUOTED"
ucheck "maint/refresh: a launchd path with an undecodable numeric reference is refused" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  HOME="$_MRF/ld-numref"

# The two causes are not mutually exclusive, and a unit predating the PATH capture is if
# anything the LIKELIEST to have been orphaned by a move as well — it is the oldest thing
# on the box. Reporting the milder cause there tells the operator "some steps will skip"
# about a job that does not run at all. The runner is inspected first for that reason, and
# these fixtures pin it per arm, since each arm detects the PATH separately. The cron one
# also exercises the pre-capture LINE SHAPE (no `PATH=` prefix): refusing to parse it would
# silently reintroduce the misclassification for exactly the units most likely to hit it.
mkdir -p "$_MRF/sd-old-dead/systemd/user" "$_MRF/ld-old-dead/Library/LaunchAgents"
printf '[Service]\nExecStart=/usr/bin/env bash %s\n' "$_MRF_GONE" \
  >"$_MRF/sd-old-dead/systemd/user/dotfiles-maint.service"
printf '<plist><dict><key>ProgramArguments</key><array><string>/bin/bash</string><string>%s</string></array><key>EnvironmentVariables</key><dict><key>LANG</key><string>C</string></dict></dict></plist>\n' \
  "$_MRF_GONE" >"$_MRF/ld-old-dead/Library/LaunchAgents/com.dotfiles.maint.plist"
printf '30 09 * * * /usr/bin/env bash %s # dotfiles-maint\n' "$_MRF_GONE" >"$_MRF/cron-old-dead"

ucheck "maint/refresh: a pre-capture systemd unit that is ALSO dead reports runner, not path" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; _maint_unit_needs_refresh && [[ \$_MAINT_REFRESH_WHY == runner ]]" \
  XDG_CONFIG_HOME="$_MRF/sd-old-dead"
ucheck "maint/refresh: a pre-capture launchd plist that is ALSO dead reports runner, not path" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; _maint_unit_needs_refresh && [[ \$_MAINT_REFRESH_WHY == runner ]]" \
  HOME="$_MRF/ld-old-dead"
ucheck "maint/refresh: a pre-capture cron line that is ALSO dead reports runner, not path" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; _maint_unit_needs_refresh && [[ \$_MAINT_REFRESH_WHY == runner ]]" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-old-dead"

# A `%` in the recorded runner means the literal text is NOT what runs. systemd expands
# specifiers in ExecStart (%h and friends) — the very expansion _maint_systemd_escape
# already doubles against in `Environment=` — and cron treats % as its newline
# metacharacter, so everything past it becomes stdin. `-f` on the raw text answers a
# question about a path nothing executes, so both arms must refuse. The fixtures use a
# runner that would RESOLVE if the % were simply ignored, so a reader that failed to
# refuse would emit a confident, wrong verdict rather than merely a noisy one.
mkdir -p "$_MRF/sd-pct/systemd/user"
printf '[Service]\nEnvironment="PATH=/x/bin"\nExecStart=/usr/bin/env bash %s\n' "$_MRF_RUNNER%h" \
  >"$_MRF/sd-pct/systemd/user/dotfiles-maint.service"
printf "30 09 * * * PATH='/x/bin' /usr/bin/env bash %s # dotfiles-maint\n" "$_MRF_RUNNER%m" >"$_MRF/cron-pct"

ucheck "maint/refresh: a systemd runner carrying a % specifier is refused (not the path that runs)" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  XDG_CONFIG_HOME="$_MRF/sd-pct"
ucheck "maint/refresh: a cron runner carrying % (cron's newline metacharacter) is refused" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; [[ -z \"\$(_maint_unit_runner)\" ]] && ! _maint_unit_needs_refresh" \
  PATH="$_MRF/bin:$PATH" CRON_TABLE="$_MRF/cron-pct"

# ── maint RUNNER stdin contract (hermetic, bash — the runner is not zsh) ──────
# The runner is unattended but inherits whatever stdin started it (a terminal, via
# `maint-run`). Every step's output goes to $LOG, so a step that PROMPTS asks its question
# where nobody can see it and then blocks on the tty forever — the run stops dead after the
# last ✓ with no error. Two separate redirects prevent that, in two different shapes, and
# both are easy to drop in a refactor without any other test noticing:
#
#   step()          `"$@" </dev/null >>"$LOG" 2>&1`   — covers every labelled step
#   package count   `fi </dev/null` on the if/elif    — that chain is NOT a step()
#
# These extract the REAL definitions out of the runner rather than restating them, so the
# assertions track the shipped code: delete a redirect and the extracted text changes and
# the check fails. The extractors match the block boundaries only (`^step() {`..`^}` and
# `^count=-1`..`^fi`), never the redirect itself — matching on `</dev/null` would make the
# test vacuously pass by finding nothing once the fix was gone.
hdr "maint runner stdin contract (unpromptable steps, hermetic)"
_MAINT_SH="$HERE/maint/dotfiles-maint.sh"
_MRT="$SANDBOX/maint-runner"
rm -rf "$_MRT"
mkdir -p "$_MRT/bin"

# A step that tries to eat a line of the caller's stdin. If step() has no redirect it
# succeeds and swallows the sentinel; with the redirect it reads EOF and the sentinel
# survives for the caller. Asserting on the SENTINEL (not on a hang) keeps a regression a
# fast failure — this suite has no timeout anywhere, so a test that detected the hang by
# hanging would wedge the run instead of reporting it.
if sed -n '/^step() {/,/^}/p' "$_MAINT_SH" >"$_MRT/step.bash" && [[ -s "$_MRT/step.bash" ]]; then
  if out="$(printf 'sentinel\n' | bash -c '
      LOG=/dev/null; log() { :; }
      . "'"$_MRT/step.bash"'"
      step "eats stdin" sh -c "read -r stolen; echo \"STOLE=\$stolen\" >&2"
      read -r survivor || survivor=GONE
      printf "%s\n" "$survivor"
    ' 2>/dev/null)" && [[ "$out" == sentinel ]]; then
    pass "maint: step() cannot consume the caller's stdin (unpromptable)"
  else
    fail "maint: step() cannot consume the caller's stdin (unpromptable) — got '${out:-}'"
  fi
else
  fail "maint: could not extract step() from ${_MAINT_SH##*/}"
fi

# Same contract, different construct: the upgradable-count chain is a bare if/elif, so it
# carries its own `</dev/null` on the `fi`. Driven with a prompting stub manager (the live
# case is dnf5 asking to import a repo_gpgcheck key into the per-user keyring, forever,
# because a declined import is never persisted).
printf '#!/bin/sh\nprintf "Import key? [y/N]: "\nread -r a\nprintf "pkg-alpha 1.0 updates\\n"\n' >"$_MRT/bin/stubmgr"
chmod +x "$_MRT/bin/stubmgr"
#
# The chain's arms now go through _pkgcount, so that helper is extracted alongside the chain
# (same block-boundary rule as step()). _to stays STUBBED here — this case is about stdin,
# and the real timeout is exercised by the separate case below.
sed -n '/^_pkgcount() {/,/^}/p' "$_MAINT_SH" >"$_MRT/pkgcount.bash"
if sed -n '/^count=-1$/,/^fi/p' "$_MAINT_SH" >"$_MRT/count.bash" &&
  [[ -s "$_MRT/count.bash" && -s "$_MRT/pkgcount.bash" ]]; then
  if out="$(printf 'sentinel\n' | bash -c '
      have() { [ "$1" = brew ] && return 1; command -v "$1" >/dev/null 2>&1; }
      _to() { shift; "$@"; }
      . "'"$_MRT/pkgcount.bash"'"
      MAINT_PKGCOUNT_TIMEOUT=30
      PATH="'"$_MRT/bin"'":$PATH
      # Shadow every manager arm onto the prompting stub so the chain is deterministic
      # regardless of which package managers the host actually has.
      for m in checkupdates pacman dnf zypper apt-get apk; do
        eval "$m() { stubmgr \"\$@\"; }"
      done
      . "'"$_MRT/count.bash"'" >/dev/null 2>&1
      read -r survivor || survivor=GONE
      printf "%s\n" "$survivor"
    ' 2>/dev/null)" && [[ "$out" == sentinel ]]; then
    pass "maint: package-count chain cannot consume the caller's stdin (unpromptable)"
  else
    fail "maint: package-count chain cannot consume the caller's stdin (unpromptable) — got '${out:-}'"
  fi
else
  fail "maint: could not extract the package-count chain from ${_MAINT_SH##*/}"
fi

# A package probe that TIMES OUT must leave the -1 "we don't know" sentinel, not 0.
# The old chain was `count=$(_to … <mgr> | grep -c …)`: when timeout SIGTERMs a stalled
# manager there is no output, grep prints 0, and grep's non-zero status — the pipeline's —
# is discarded by the assignment. So the daily log asserted "0 upgradable" (an up-to-date
# box) on exactly the failure the timeout was added to survive, and the sentinel two lines
# above the chain could never fire. This drives the REAL _to and _pkgcount (no stubs — the
# whole point is the status `timeout` itself reports) against a manager that stalls forever,
# with the bound turned down to 1s so the case costs about a second.
#
# That status is NOT one number across the fleet, which is why the observed rc is carried
# into the failure message: GNU coreutils reports expiry as 124, while BUSYBOX reports its
# SIGTERM as 143. A 124-only gate passed everywhere except Alpine, where this case caught it
# reporting a stalled manager as 0 — so if a future userland picks a third spelling, the
# failure here names it instead of just saying "want -1".
#
# The stall stub is a REAL EXECUTABLE named `brew`, not a shell function like the stdin case
# above: `timeout` execs its argument, so it cannot run a function (it would fail 127 and the
# case would pass for the wrong reason). `exec sleep` so the stub process IS the sleep and
# takes the SIGTERM directly instead of orphaning a 30s child. brew is first in the chain,
# and the stub dir is prepended, so this arm wins on any host — and it is an arm that goes
# through _to (the pacman arm deliberately does not).
if have timeout; then
  printf '#!/bin/sh\nexec sleep 30\n' >"$_MRT/bin/brew"
  chmod +x "$_MRT/bin/brew"
  sed -n '/^_to() {/,/^}/p' "$_MAINT_SH" >"$_MRT/to.bash"
  if [[ -s "$_MRT/to.bash" && -s "$_MRT/pkgcount.bash" && -s "$_MRT/count.bash" ]]; then
    if out="$(bash -c '
        PATH="'"$_MRT/bin"'":$PATH
        have() { command -v "$1" >/dev/null 2>&1; }
        . "'"$_MRT/to.bash"'"
        . "'"$_MRT/pkgcount.bash"'"
        MAINT_PKGCOUNT_TIMEOUT=1
        . "'"$_MRT/count.bash"'" >/dev/null 2>&1
        # The raw status too, so a userland whose timeout reports neither 124 nor 128+n is
        # named by the failure rather than merely disagreeing with it.
        _to 1 brew >/dev/null 2>&1
        printf "%s %s\n" "$count" "$?"
      ' 2>/dev/null)" && [[ "${out%% *}" == -1 ]]; then
      pass "maint: a timed-out package probe reports the -1 sentinel, not 0 upgradable (timeout rc=${out##* })"
    else
      fail "maint: a timed-out package probe reports count='${out%% *}' at timeout rc=${out##* } (want count -1 — 0 would log the box as up to date)"
    fi
  else
    fail "maint: could not extract _to/_pkgcount from ${_MAINT_SH##*/}"
  fi
else
  skip "maint timed-out package probe (no \`timeout\` — _to runs the command unbounded)"
fi

# …and pin the BUSYBOX spelling on EVERY host, not just the Alpine leg of the matrix. The
# case above asserts whatever the local timeout happens to report, so on a GNU box it only
# ever proves the 124 arm — which is exactly how a 124-only gate reached CI green here and
# red on Alpine. A fake `timeout` that exits 143 (128+SIGTERM, busybox's spelling) makes the
# other arm deterministic and instant: no sleeping, and `brew` succeeds immediately, so the
# ONLY thing that can produce -1 is _pkgcount reading the wrapper's status.
printf '#!/bin/sh\nexit 143\n' >"$_MRT/bin/timeout"
printf '#!/bin/sh\nexit 0\n' >"$_MRT/bin/brew"
chmod +x "$_MRT/bin/timeout" "$_MRT/bin/brew"
sed -n '/^_to() {/,/^}/p' "$_MAINT_SH" >"$_MRT/to.bash"
if [[ -s "$_MRT/to.bash" && -s "$_MRT/pkgcount.bash" && -s "$_MRT/count.bash" ]]; then
  if out="$(bash -c '
      PATH="'"$_MRT/bin"'":$PATH
      have() { command -v "$1" >/dev/null 2>&1; }
      . "'"$_MRT/to.bash"'"
      . "'"$_MRT/pkgcount.bash"'"
      MAINT_PKGCOUNT_TIMEOUT=1
      . "'"$_MRT/count.bash"'" >/dev/null 2>&1
      printf "%s\n" "$count"
    ' 2>/dev/null)" && [[ "$out" == -1 ]]; then
    pass "maint: a busybox-style timeout (143, not 124) also reports the -1 sentinel"
  else
    fail "maint: a busybox-style timeout (143) reports '${out:-}' (want -1 — this is the Alpine regression)"
  fi
else
  fail "maint: could not extract _to/_pkgcount from ${_MAINT_SH##*/}"
fi
rm -f "$_MRT/bin/timeout" "$_MRT/bin/brew"

# update.zsh: the first-run welcome (U2 — the cheat-sheet discoverability hint) must
# greet EXACTLY ONCE per machine. Drive _core_welcome directly (the TTY gate lives at
# its call site, so a captured run can exercise the greet+sentinel logic): first call
# prints the `core` front-door pointer and persists the sentinel; a second call is silent.
# An isolated XDG_STATE_HOME keeps the sentinel out of the shared sandbox.
ucheck "update: _core_welcome greets once, then the sentinel silences it" \
  "source '$UPD'; o1=\$(_core_welcome); [[ \$o1 == *\"run 'core'\"* ]] || exit 1; [[ -e \$XDG_STATE_HOME/dotfiles-core/.welcomed ]] || exit 1; o2=\$(_core_welcome); [[ -z \$o2 ]]" \
  XDG_STATE_HOME="$SANDBOX/welcome-once" NO_COLOR=1 UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# …and the startup hook stays SILENT without an interactive tty (captured/piped/CI):
# sourcing update.zsh prints no greet and writes no sentinel, so it never spams logs.
ucheck "update: welcome stays silent (no greet, no sentinel) without a tty" \
  "o=\$(source '$UPD'); [[ \$o != *'dotfiles Core loaded'* && ! -e \$XDG_STATE_HOME/dotfiles-core/.welcomed ]]" \
  XDG_STATE_HOME="$SANDBOX/welcome-notty" NO_COLOR=1 UPDATE_CHECK_ENABLED=0 CORE_WELCOME=1

# completions (U3 / DERIVED regression gate): every first-party PUBLIC verb must have a
# #compdef that compinit resolves off the vendored fpath dir — a missing/typo'd tag
# means no tab-completion for that command across all nine repos, with nothing else to
# catch it. The verb set is DERIVED from the source (top-level functions whose names
# don't start with `_`, Core's private-helper convention) minus an explicit allowlist
# of public-but-non-completable functions: the zsh-vi-mode init HOOK, the git-alias
# helpers, and the internal plugin updater — none are user verbs. So a NEW verb shipped
# WITHOUT a completion now FAILS here — the regression the OLD hardcoded list couldn't
# catch (it silently omitted update-check + opssh, which had no completion at all). This
# mirrors audit-core.sh's META_ALLOWLIST pattern: derive from the tree, exempt by name.
# `cheat` (alias → core-help) is appended so the aliased #compdef tag is exercised too.
COMP_ALLOWLIST=" git_main_branch git_current_branch zvm_after_init zplugin-update "
COMP_VERBS=()
while IFS= read -r _v; do
  case " $COMP_ALLOWLIST " in *" $_v "*) continue ;; esac
  COMP_VERBS+=("$_v")
done < <(grep -rhoE '^(function[[:space:]]+)?[A-Za-z][A-Za-z0-9_-]*\(\)|^function[[:space:]]+[A-Za-z][A-Za-z0-9_-]*[[:space:]]*\{' "$HERE"/zsh/*.zsh |
  sed -E 's/^function[[:space:]]+//; s/\(\).*//; s/[[:space:]]*\{.*//' |
  grep -vE '^_' | sort -u)
COMP_VERBS+=(cheat)
ucheck "completions: every first-party verb has a compinit-resolved completion (derived)" \
  "fpath=('$HERE/zsh/completions' \$fpath); autoload -Uz compinit && compinit -u -d '$SANDBOX/zcd-comp' >/dev/null 2>&1; for c in ${COMP_VERBS[*]}; do [[ -n \${_comps[\$c]:-} ]] || { print \"no completion registered for: \$c\"; exit 1; }; done"

# core-help coverage (B2): the cheat sheet is a HAND-MAINTAINED rows=() array — so a new
# verb is trivially forgotten and the one discoverability surface silently drifts from
# reality, with nothing to catch it across nine repos. Derive the public-verb set from the
# source (same technique as the completion gate above), then assert each appears in the
# RENDERED core-help output (rows OR the footer line, where the op/health/front-door verbs
# live). `cheat` is the alias and `core` is the dispatcher whose own help IS the sheet —
# both exempt. A verb shipped without a sheet entry now FAILS here. ui.zsh + functions.zsh
# are sourced so core-help renders; NO_COLOR keeps the match on plain text.
HELP_ALLOWLIST=" $COMP_ALLOWLIST cheat core "
HELP_VERBS=()
for _v in "${COMP_VERBS[@]}"; do
  case "$HELP_ALLOWLIST" in *" $_v "*) continue ;; esac
  HELP_VERBS+=("$_v")
done
ucheck "core-help lists every first-party verb (derived B2 coverage gate)" \
  "source '$UI'; source '$FN'; sheet=\$(COLUMNS=200 core-help 2>&1); for v in ${HELP_VERBS[*]}; do [[ \" \$sheet \" == *\" \$v \"* || \$sheet == *\"\$v \"* || \$sheet == *\" \$v\"* ]] || { print \"verb missing from core-help: \$v\"; exit 1; }; done" \
  NO_COLOR=1

# completion ↔ source flag drift (B7): the coverage test above proves a completion EXISTS;
# this proves its FLAGS still match the verb. Every long flag a flag-bearing completion
# advertises must still be mentioned in the verb's zsh source — so removing `--dry-run`
# from `up` (or renaming `--local`) without updating its #compdef now FAILS here instead
# of silently shipping a completion that offers a flag the verb rejects to all nine repos.
# Pure sed+grep (busybox-safe); comment lines in the completion are stripped first.
hdr "completion ↔ source flag drift (serve, up)"
_flag_drift() { # _flag_drift <verb> <completion-file> <source-file>
  local verb="$1" comp="$2" src="$3" f flags miss=0
  flags="$(sed 's/^[[:space:]]*#.*//' "$comp" | grep -oE -- '--[a-z][a-z-]+' | sort -u)"
  for f in $flags; do
    grep -q -- "$f" "$src" || {
      fail "completion '$verb' advertises $f, absent from $src (drift)"
      miss=1
    }
  done
  ((miss)) || pass "completion '$verb' flags all still present in its source"
}
_flag_drift serve "$HERE/zsh/completions/_serve" "$HERE/zsh/30-functions.zsh"
_flag_drift up "$HERE/zsh/completions/_up" "$HERE/zsh/60-update.zsh"

# ── git helper unit tests (git.zsh) (B2) ──────────────────────────────────────
# git.zsh's trunk/branch resolution (git_main_branch's 6-way ref search, git_current_branch's
# detached-HEAD fallback) is real logic that branch-aware aliases (gcom/grbm/gpu) ride on and
# that fans out to nine repos — yet it was the ONE shell module with no behavioral coverage (only
# `zsh -n`). Drive each helper against throwaway repos, hermetic: HOME → sandbox and git config
# pinned to /dev/null so the host's init.defaultBranch can't skew the result. Skips without git.
hdr "git helper unit tests (git.zsh)"
if ! have git; then
  skip "git helpers (git not installed)"
else
  GITZSH="$HERE/zsh/25-git.zsh"
  gcheck() { # gcheck <label> <zsh-body that must exit 0>
    local out
    if out="$(HOME="$SANDBOX" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e \
      zsh -fc "source '$GITZSH' || exit 1; $2" 2>&1)"; then
      pass "$1"
    else
      fail "$1"
      [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/    /' >&2
    fi
  }
  gcheck "git_current_branch reads the checked-out branch" \
    'd=$(mktemp -d); cd "$d"; git -c init.defaultBranch=main init -q .; [[ $(git_current_branch) == main ]]'
  gcheck "git_current_branch falls back to a short SHA on detached HEAD" \
    'd=$(mktemp -d); cd "$d"; git -c init.defaultBranch=main init -q .; git commit -q --allow-empty -m x; git checkout -q --detach HEAD; [[ -n $(git_current_branch) ]]'
  gcheck "git_current_branch is empty outside a repo" \
    'd=$(mktemp -d); cd "$d"; [[ -z $(git_current_branch) ]]'
  gcheck "git_main_branch resolves main when present" \
    'd=$(mktemp -d); cd "$d"; git -c init.defaultBranch=main init -q .; git commit -q --allow-empty -m x; [[ $(git_main_branch) == main ]]'
  gcheck "git_main_branch resolves master when that is the trunk" \
    'd=$(mktemp -d); cd "$d"; git -c init.defaultBranch=master init -q .; git commit -q --allow-empty -m x; [[ $(git_main_branch) == master ]]'
  gcheck "git_main_branch defaults to master when no known trunk exists" \
    'd=$(mktemp -d); cd "$d"; git -c init.defaultBranch=main init -q .; git commit -q --allow-empty -m x; git branch -m weirdtrunk; [[ $(git_main_branch) == master ]]'
  gcheck "git_main_branch ignores a dangling origin/HEAD (stale after a remote rename)" \
    'd=$(mktemp -d); cd "$d"; git -c init.defaultBranch=master init -q .; git commit -q --allow-empty -m x; git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main; [[ $(git_main_branch) == master ]]'
fi

# ── update.zsh per-manager parse (B5) ─────────────────────────────────────────
# The detection LADDER is covered above (apt), but _pkgup_count/_pkgup_list use a DISTINCT
# grep/awk heuristic PER manager — and only apt had a test. A regex that miscounts a header
# or blank row would ship silently to that one distro's repo. Pin each: isolate PATH to a
# lone manager stub (+ the coreutils its pipeline forks) so _pkgup_mgr resolves to it, feed
# canned `outdated` output, and assert the parsed count/names. Mirrors the apt stub above.
hdr "update.zsh per-manager parse (apk / dnf / zypper / pacman)"
_mgr_stub() { # _mgr_stub <mgr> <sh-body>
  rm -rf "$PMBIN"
  mkdir -p "$PMBIN"
  printf '#!/bin/sh\n%s\n' "$2" >"$PMBIN/$1"
  chmod +x "$PMBIN/$1"
  local t
  for t in grep awk sort cut sed; do
    [[ -e "$PMBIN/$t" ]] || ln -s "$(command -v "$t")" "$PMBIN/$t" 2>/dev/null
  done
}
_mgr_stub apk 'case "$*" in *"list -u"*) printf "a-1.0 ...\nb-2.0 ...\nc-3.0 ...\n" ;; esac'
ucheck "update: _pkgup_count parses apk (3 upgradable)" \
  "source '$UPD'; [[ \$(_pkgup_count) == 3 ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "update: _pkgup_list parses apk package names" \
  "source '$UPD'; out=\$(_pkgup_list); [[ \$out == *a-1.0* && \$out == *c-3.0* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
_mgr_stub dnf 'case "$*" in *check-update*) printf "bash.x86_64    5.1-2    baseos\nvim.x86_64    9.0-1    appstream\n" ;; esac'
ucheck "update: _pkgup_count parses dnf check-update (2 upgradable)" \
  "source '$UPD'; [[ \$(_pkgup_count) == 2 ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "update: _pkgup_list parses dnf package names" \
  "source '$UPD'; out=\$(_pkgup_list); [[ \$out == *bash.x86_64* && \$out == *vim.x86_64* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
_mgr_stub zypper 'case "$*" in *list-updates*) printf "v | repo | bash | 1 | 2 | x86_64\nv | repo | vim | 1 | 2 | x86_64\n" ;; esac'
ucheck "update: _pkgup_count parses zypper list-updates (2 upgradable)" \
  "source '$UPD'; [[ \$(_pkgup_count) == 2 ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "update: _pkgup_list parses zypper package names" \
  "source '$UPD'; out=\$(_pkgup_list); [[ \$out == *bash* && \$out == *vim* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
_mgr_stub pacman 'case "$*" in *-Qu*) printf "bash 5.1.0\nvim 9.0.0\n" ;; esac'
ucheck "update: _pkgup_count parses pacman -Qu (2 upgradable)" \
  "source '$UPD'; [[ \$(_pkgup_count) == 2 ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "update: _pkgup_list parses pacman package names" \
  "source '$UPD'; out=\$(_pkgup_list); [[ \$out == *bash* && \$out == *vim* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0

# ── op.zsh 1Password helpers (B7) ─────────────────────────────────────────────
# op.zsh fans out to nine repos and handles SECRETS, yet had zero behavioral coverage. The
# module short-circuits (returns) unless `op` is on PATH, so we stub a fake `op` (echoes
# its args) + a fake `clip` (captures stdin) on an isolated PATH — the same hermetic
# technique as the clip ladder — and assert the verbs' input-guards, the op:// path
# construction, and optoken's clip dependency. No real 1Password, no network, no secrets.
hdr "op.zsh 1Password helpers (hermetic stubs)"
OPZSH="$HERE/zsh/50-op.zsh"
OPBIN="$SANDBOX/opbin"
_op_reset() { # _op_reset [with-clip]
  rm -rf "$OPBIN"
  mkdir -p "$OPBIN"
  ln -s "$_real_zsh" "$OPBIN/zsh" 2>/dev/null
  # fake op: print the OTP for `item get --otp`, a table for `item list`, else echo args.
  cat >"$OPBIN/op" <<'OPSTUB'
#!/bin/sh
case "$*" in
*"item get"*--otp*) echo 123456 ;;
*"item list"*) printf 'NAME\tKEY\nmykey\tabc\n' ;;
*) printf 'op %s\n' "$*" ;;
esac
OPSTUB
  chmod +x "$OPBIN/op"
  if [[ "${1:-}" == with-clip ]]; then
    printf '#!/bin/sh\ncat >/dev/null\n' >"$OPBIN/clip"
    chmod +x "$OPBIN/clip"
  fi
}
# ocheck: source ui+op under a PATH that includes the op stub, run a body, expect exit 0.
ocheck() { # ocheck <label> <zsh-body> [extra PATH entries already in OPBIN]
  local out
  if out="$(PATH="$OPBIN:$PATH" HOME="$SANDBOX" "$_real_zsh" -fc "source '$UI'||exit 1; source '$OPZSH'||exit 1; $2" 2>&1)"; then
    pass "$1"
  else
    fail "$1"
    [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
}
if ! have zsh; then
  skip "op.zsh helpers (zsh not installed)"
else
  _op_reset with-clip
  # input guards: a missing required arg is a usage error (rc 1), in Core's voice.
  ocheck "opsecret with no arg is a usage error" 'opsecret 2>/dev/null; (( $? != 0 ))'
  ocheck "openv with no arg is a usage error" 'openv 2>/dev/null; (( $? != 0 ))'
  ocheck "optoken with no arg is a usage error" 'optoken 2>/dev/null; (( $? != 0 ))'
  # op:// path construction: opsecret <path> must call `op read op://<path>` verbatim.
  ocheck "opsecret builds the op:// read path" \
    'out=$(opsecret Personal/AWS/key); [[ $out == *"op read op://Personal/AWS/key"* ]]'
  # optoken copies the OTP via clip and confirms — present clip → success + the ok line.
  # "sent", not "copied": clip's OSC 52 last resort returns success once the escape is
  # WRITTEN, which is not the same as a terminal having accepted it (#525).
  ocheck "optoken fetches the OTP and hands it to clip" \
    'out=$(optoken Personal/GitHub 2>&1); (( $? == 0 )) && [[ $out == *"TOTP sent"* ]]'
  ocheck "opssh lists stored SSH keys (rc 0)" \
    'out=$(opssh 2>&1); (( $? == 0 )) && [[ $out == *mykey* ]]'
  # uniform --help contract: each op verb answers --help on stdout, rc 0.
  ocheck "opsecret --help returns 0 with usage" \
    'out=$(opsecret --help); (( $? == 0 )) && [[ $out == *"usage: opsecret"* ]]'
  # optoken's clip dependency (U4 errbox): with NO clip on PATH it must fail in Core's
  # voice (rc 1) rather than silently swallow the TOTP down a broken pipe.
  _op_reset # no clip this time
  ocheck "optoken fails clearly when clip is absent (no silent TOTP loss)" \
    'path=(/usr/bin /bin); out=$(optoken Personal/GitHub 2>&1); (( $? != 0 )) && [[ $out == *"requires Core"* && $out == *clip* ]]'
fi

# ── tmux status/popup scripts (U11) ───────────────────────────────────────────
# The tmux helper scripts fan out to nine repos and were covered only by bash -n + shellcheck
# (static). Their PORTABILITY CONTRACT — "emit a styled pill when there's something to show,
# emit NOTHING (segment vanishes) otherwise" — is pure logic that a bad edit could break
# silently (a status helper that errors blanks the whole bar). Drive the two data-driven
# ones hermetically against a stubbed PATH (same technique as the clip ladder): a fake
# `pmset`/`ip` pins the environment so the output is deterministic on every box.
# ── vim-tmux-navigator must not keep C-\ (#652-adjacent; see tmux/tmux.conf) ──
# The plugin binds FIVE keys at the tmux ROOT table, and the fifth (C-\ → select-pane -l)
# collides head-on with zsh's `Ctrl+\ → autosuggest-toggle` (zsh/40-bindings.zsh), which
# tmux/scripts/tmux-cheat.sh advertises by name. tmux wins that race in every shell pane,
# so the documented key was dead fleet-wide. tmux.conf disables just that mapping with an
# EMPTY @vim_navigator_mapping_prev.
#
# Two halves, and BOTH are load-bearing:
#   • the option is set, and set to EMPTY — any non-empty value re-binds a key
#   • it is set ABOVE the `run '…/tpm'` line — tpm sources the plugin's .tmux script, which
#     reads the option at that instant, so setting it afterwards is a silent no-op
# Neither half is visible to `tmux -f … source-file` in CI (no plugin checkout, no server),
# which is exactly why it is pinned here as text, like the gh/carapace order in 45-plugins.
hdr "tmux: vim-tmux-navigator's C-\\ mapping stays disabled (Ctrl+\\ belongs to zsh)"
TMUXCONF="$HERE/tmux/tmux.conf"
_vtn_line="$(grep -n "^[[:space:]]*set -g @vim_navigator_mapping_prev" "$TMUXCONF" | head -1)"
_tpm_line="$(grep -n "^[[:space:]]*run .*tpm/tpm" "$TMUXCONF" | head -1)"
if [[ -n "$_vtn_line" ]]; then
  pass "tmux.conf sets @vim_navigator_mapping_prev"
else fail "tmux.conf no longer sets @vim_navigator_mapping_prev — C-\\ is back on select-pane -l"; fi
if [[ "${_vtn_line#*:}" == *"''"* || "${_vtn_line#*:}" == *'""'* ]]; then
  pass "@vim_navigator_mapping_prev is EMPTY (the plugin's off switch)"
else fail "@vim_navigator_mapping_prev is non-empty — that binds a key: ${_vtn_line#*:}"; fi
if [[ -n "$_vtn_line" && -n "$_tpm_line" ]] && ((${_vtn_line%%:*} < ${_tpm_line%%:*})); then
  pass "@vim_navigator_mapping_prev is set BEFORE tpm runs (or it is a no-op)"
else fail "@vim_navigator_mapping_prev must precede the tpm run line (${_vtn_line%%:*} vs ${_tpm_line%%:*})"; fi
# The keys the plugin exists FOR must still be declared — this guard must never become a
# licence to drop the plugin's navigation along with its fifth key.
if grep -q "christoomey/vim-tmux-navigator" "$TMUXCONF"; then
  pass "vim-tmux-navigator is still loaded (C-h/j/k/l navigation intact)"
else fail "vim-tmux-navigator is gone — C-h/j/k/l no longer cross into nvim"; fi

hdr "tmux status/popup scripts (battery / netinfo, hermetic)"
TMUXBIN="$SANDBOX/tmuxbin"
BATTERY="$HERE/tmux/scripts/tmux-battery.sh"
NETINFO="$HERE/tmux/scripts/tmux-netinfo.sh"
_tmux_stub() { # _tmux_stub <name> <sh-body>
  rm -rf "$TMUXBIN"
  mkdir -p "$TMUXBIN"
  printf '#!/bin/sh\n%s\n' "$2" >"$TMUXBIN/$1"
  chmod +x "$TMUXBIN/$1"
}
# battery: a stubbed macOS `pmset` (87%, discharging) must yield a pill carrying "87%" —
# guarding the awk %-extraction the script's header explains (tmux mangles a literal '%').
_tmux_stub pmset 'printf -- "-InternalBattery-0 (id=1)\t87%%; discharging; 4:32 remaining present: true\n"'
out="$(PATH="$TMUXBIN:$PATH" bash "$BATTERY" 2>/dev/null)"
if [[ "$out" == *"87%"* && "$out" == *"#[fg="* ]]; then
  pass "tmux-battery renders a pill from pmset (87%)"
else fail "tmux-battery did not render the expected 87% pill (got: $out)"; fi
# netinfo: a tunnel iface up → an ORANGE pill naming the iface + addr.
_tmux_stub ip 'case "$*" in *"addr show tun0"*) echo "2: tun0 inet 10.8.0.2/24 scope global tun0" ;; esac'
out="$(PATH="$TMUXBIN:$PATH" bash "$NETINFO" 2>/dev/null)"
if [[ "$out" == *"tun0"* && "$out" == *"10.8.0.2"* ]]; then
  pass "tmux-netinfo renders the tunnel pill when a tun iface is up"
else fail "tmux-netinfo tunnel pill missing (got: $out)"; fi
# netinfo: no tunnel but a routable LAN → a GREEN pill with the LAN IP.
_tmux_stub ip 'case "$*" in *"route get"*) echo "1.1.1.1 via 192.168.1.1 dev en0 src 192.168.1.50 uid 0" ;; esac'
out="$(PATH="$TMUXBIN:$PATH" bash "$NETINFO" 2>/dev/null)"
if [[ "$out" == *"192.168.1.50"* ]]; then
  pass "tmux-netinfo falls back to the LAN pill"
else fail "tmux-netinfo LAN pill missing (got: $out)"; fi
# netinfo: nothing reachable → NOTHING printed (the segment vanishes — the portability
# contract that keeps it safe to ship to every repo). A non-empty output here is the bug.
_tmux_stub ip ':'
out="$(PATH="$TMUXBIN:$PATH" bash "$NETINFO" 2>/dev/null)"
if [[ -z "$out" ]]; then
  pass "tmux-netinfo emits nothing when no tunnel/LAN (segment vanishes)"
else fail "tmux-netinfo should be silent with no net, printed: $out"; fi

# ── tmux-claude.sh session routing (hermetic) ─────────────────────────────────
# Same reasoning as the block above, and the same technique: this script decides WHICH
# conversation you get, and every branch of that decision is invisible to the static
# gates (bash -n, lint). Getting it wrong is not a blank status bar but a lost thread —
# attaching to another repo's Claude, or spraying tmux errors instead of opening one. The
# `tmux` stub logs its argv and is programmable: TMUX_HAS_ON says from which has-session
# call onward the session "exists" (0 = never), TMUX_NEW_FAILS makes new-session fail.
# `cksum` is deliberately NOT stubbed — the duplicate-basename test is only meaningful if
# it exercises the real hash.
hdr "tmux-claude.sh session routing (hermetic)"
CLAUDESH="$HERE/tmux/scripts/tmux-claude.sh"
CBIN="$SANDBOX/claudebin"
_claude_env() { # _claude_env <cwd> [extra env assignments...]
  rm -f "$SANDBOX/tmux.log" "$SANDBOX/tmux.state"
  mkdir -p "$CBIN"
  cat >"$CBIN/tmux" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$TMUX_LOG"
case "$1" in
  has-session)
    n=$(cat "$TMUX_STATE" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" >"$TMUX_STATE"
    [ "${TMUX_HAS_ON:-0}" -ne 0 ] && [ "$n" -ge "${TMUX_HAS_ON:-0}" ] && exit 0
    exit 1 ;;
  new-session) [ -n "${TMUX_NEW_FAILS:-}" ] && exit 1; printf '%s\n' '$42' ;;
  show-option) printf '%s\n' tmux-256color ;;
esac
exit 0
STUB
  cat >"$CBIN/git" <<'STUB'
#!/bin/sh
[ -n "${GIT_ROOT:-}" ] || exit 128
printf '%s\n' "$GIT_ROOT"
STUB
  printf '#!/bin/sh\nexit 0\n' >"$CBIN/claude"
  chmod +x "$CBIN/tmux" "$CBIN/git" "$CBIN/claude"
}
_claude_run() { # _claude_run <cwd> ; env comes from the caller
  ( cd "$1" && PATH="$CBIN:$PATH" TERM=xterm \
    TMUX_LOG="$SANDBOX/tmux.log" TMUX_STATE="$SANDBOX/tmux.state" \
    bash "$CLAUDESH" >/dev/null 2>&1 )
}

# 1. No `claude` on PATH → the gate fires: a status-line message, and NO session created.
#    PATH is the STUB DIR ALONE here, not stub-dir-first: deleting the stub is not enough when
#    the box running the suite has a real `claude` installed (this very repo's CI does), and the
#    gate is the first thing the script does, so it needs nothing else on PATH to reach it.
_claude_env
rm -f "$CBIN/claude"
#    bash by ABSOLUTE path: a `PATH=… bash …` prefix sets PATH before the command is looked
#    up too, so a bare `bash` would not be found in the stub dir and nothing would run.
( cd /tmp && PATH="$CBIN" TERM=xterm GIT_ROOT=/tmp/repo-a TMUX_HAS_ON=0 \
  TMUX_LOG="$SANDBOX/tmux.log" TMUX_STATE="$SANDBOX/tmux.state" \
  "$(command -v bash)" "$CLAUDESH" >/dev/null 2>&1 )
if grep -q '^display-message' "$SANDBOX/tmux.log" && ! grep -q '^new-session' "$SANDBOX/tmux.log"; then
  pass "tmux-claude: absent \`claude\` gates out (message, no session)"
else fail "tmux-claude: absent-binary gate wrong: $(tr '\n' '|' <"$SANDBOX/tmux.log")"; fi

# 2. Inside a git repo → the session is named + rooted from the GIT ROOT, not the cwd.
_claude_env
GIT_ROOT=/tmp/repo-a TMUX_HAS_ON=0 _claude_run /tmp
if grep -q 'new-session .*-s _popup_claude_repo-a_[0-9]* -c /tmp/repo-a' "$SANDBOX/tmux.log"; then
  pass "tmux-claude: session is keyed and rooted on the git root"
else fail "tmux-claude: git-root routing wrong: $(grep '^new-session' "$SANDBOX/tmux.log")"; fi

# 3. Outside a repo (git fails) → fall back to the cwd rather than erroring out.
_claude_env
GIT_ROOT='' TMUX_HAS_ON=0 _claude_run /tmp
if grep -q 'new-session .*-s _popup_claude_tmp_[0-9]* -c /tmp' "$SANDBOX/tmux.log"; then
  pass "tmux-claude: falls back to cwd outside a git repo"
else fail "tmux-claude: non-repo fallback wrong: $(grep '^new-session' "$SANDBOX/tmux.log")"; fi

# 4. Session already exists → REUSE. A second new-session would fork the conversation.
_claude_env
GIT_ROOT=/tmp/repo-a TMUX_HAS_ON=1 _claude_run /tmp
if ! grep -q '^new-session' "$SANDBOX/tmux.log" && grep -q '^attach' "$SANDBOX/tmux.log"; then
  pass "tmux-claude: reuses an existing session instead of forking one"
else fail "tmux-claude: reuse path wrong: $(tr '\n' '|' <"$SANDBOX/tmux.log")"; fi

# 5. Two repos sharing a basename must NOT collide onto one conversation — the path hash is
#    the only thing separating them, so this is the test that keeps `docs/` from being shared.
_claude_env
GIT_ROOT=/tmp/one/docs TMUX_HAS_ON=0 _claude_run /tmp
n1="$(grep -o '_popup_claude_docs_[0-9]*' "$SANDBOX/tmux.log" | head -1)"
_claude_env
GIT_ROOT=/tmp/two/docs TMUX_HAS_ON=0 _claude_run /tmp
n2="$(grep -o '_popup_claude_docs_[0-9]*' "$SANDBOX/tmux.log" | head -1)"
if [[ -n "$n1" && -n "$n2" && "$n1" != "$n2" ]]; then
  pass "tmux-claude: same-basename repos get distinct sessions ($n1 vs $n2)"
else fail "tmux-claude: duplicate-basename collision ($n1 vs $n2)"; fi

# 6. The created session is made inert to tmux, or keystrokes never reach Claude's TUI.
_claude_env
GIT_ROOT=/tmp/repo-a TMUX_HAS_ON=0 _claude_run /tmp
missing=""
for o in "key-table popup" "status off" "prefix None" "detach-on-destroy on"; do
  grep -q "set-option .*$o" "$SANDBOX/tmux.log" || missing="$missing [$o]"
done
if [[ -z "$missing" ]]; then
  pass "tmux-claude: sets key-table/status/prefix/detach-on-destroy on the session"
else fail "tmux-claude: session options missing:$missing"; fi

# 7. RACE: new-session loses to a sibling client, but the session now exists. The loser must
#    attach to it, not carry an empty target into every command below (there is no `set -e`).
_claude_env
GIT_ROOT=/tmp/repo-a TMUX_HAS_ON=2 TMUX_NEW_FAILS=1 _claude_run /tmp
if grep -q '^attach -t _popup_claude_repo-a_[0-9]*$' "$SANDBOX/tmux.log"; then
  pass "tmux-claude: a lost create race still attaches to the winner's session"
else fail "tmux-claude: race path did not attach by name: $(tr '\n' '|' <"$SANDBOX/tmux.log")"; fi

# 8. Genuine creation failure (nothing exists afterwards) → report it, and do NOT attach to an
#    empty target, which is what produces the confusing bare tmux error.
_claude_env
GIT_ROOT=/tmp/repo-a TMUX_HAS_ON=0 TMUX_NEW_FAILS=1 _claude_run /tmp
if grep -q '^display-message could not start' "$SANDBOX/tmux.log" && ! grep -q '^attach' "$SANDBOX/tmux.log"; then
  pass "tmux-claude: a real creation failure reports instead of attaching to nothing"
else fail "tmux-claude: creation-failure path wrong: $(tr '\n' '|' <"$SANDBOX/tmux.log")"; fi

# ── serve macOS IP discovery (_serve_advertise, hermetic) ─────────────────────
# serve()'s tunnel/LAN URL discovery is split into _serve_advertise so this
# platform-specific path is testable without the blocking http.server. macOS ships
# no ip(8), so we isolate PATH to a stub bin WITHOUT `ip` (forcing the route+ipconfig
# branch), stub ipconfig/route to canned answers, and assert the advertised URLs —
# mirroring the tmux-netinfo hermetic tests above. ui.zsh/30-functions.zsh are pure
# definitions (no source-time forks), so they source cleanly under the isolated PATH.
hdr "serve macOS IP discovery (_serve_advertise, hermetic)"
SRVBIN="$SANDBOX/srvbin"
_serve_net() { # _serve_net <ipconfig-sh-body> <route-sh-body>
  rm -rf "$SRVBIN"
  mkdir -p "$SRVBIN"
  printf '#!/bin/sh\n%s\n' "$1" >"$SRVBIN/ipconfig"
  printf '#!/bin/sh\n%s\n' "$2" >"$SRVBIN/route"
  chmod +x "$SRVBIN/ipconfig" "$SRVBIN/route"
  local t
  for t in awk cut head; do
    [[ -e "$SRVBIN/$t" ]] || ln -s "$(command -v "$t")" "$SRVBIN/$t" 2>/dev/null
  done
}
# 1) a tunnel iface up → the tunnel URL is advertised first, naming the iface.
_serve_net 'case "$2" in tun0) echo 10.8.0.2 ;; esac' ':'
ucheck "serve: macOS discovery advertises the tunnel addr first (no ip(8))" \
  "source '$UI' || exit 1; source '$FN' || exit 1; out=\$(_serve_advertise 8000); [[ \$out == *'(tun0)'* && \$out == *'10.8.0.2'* ]]" \
  PATH="$SRVBIN"
# 2) no tunnel, default route present → the LAN addr from route(8)+ipconfig.
_serve_net 'case "$2" in en0) echo 192.168.1.50 ;; esac' 'printf "   interface: en0\n"'
ucheck "serve: macOS discovery falls back to the default-route LAN addr" \
  "source '$UI' || exit 1; source '$FN' || exit 1; out=\$(_serve_advertise 8000); [[ \$out == *'(lan)'* && \$out == *'192.168.1.50'* ]]" \
  PATH="$SRVBIN"
# 3) tunnel up but NO default route → must NOT reprint the tunnel addr as (lan)
#    (guards the stale-$ip reuse the Copilot review flagged).
_serve_net 'case "$2" in tun0) echo 10.8.0.2 ;; esac' ':'
ucheck "serve: a failed default route does not reprint the tunnel addr as (lan)" \
  "source '$UI' || exit 1; source '$FN' || exit 1; out=\$(_serve_advertise 8000); [[ \$out == *'(tun0)'* && \$out != *'(lan)'* ]]" \
  PATH="$SRVBIN"

# ── K. nvim orphan backstop (scripts/nvim-reachability.sh) ────────────────────
# core.manifest lists nvim/ as a DIRECTORY, so the audit's manifest⇄fs check auto-lists
# every path under it and cannot see an orphan. §4b of the audit is the backstop; this
# proves the backstop actually catches what it claims to, rather than merely existing —
# ── routine allowed-tools ⇄ workflow --allowedTools mirror (#633) ─────────────
# .github/workflows/claude-routines.yml states the invariant: "each job's --allowedTools MIRRORS
# the routine's own allowed-tools frontmatter (.claude/commands/<routine>.md) and is never
# broader." Nothing enforced it. The two live ~200 lines apart in different files, in different
# spellings (", " vs ","), and a routine that drifts BROADER hands a scheduled, token-bearing,
# Opus-driven job a capability its own definition never granted — while one that drifts NARROWER
# fails at runtime, weekly, in a job nobody watches unless it files an issue.
#
# Driven off the WORKFLOW side: every --allowedTools in the two rails must match the frontmatter
# of the routine its `claude -p "/<name>"` names. A command with no mirror is simply not
# scheduled (release-notes is dispatch-only, several are unscheduled) and is not a finding; a
# mirror naming a command that does not exist is.
if have python3; then
  hdr "routine allowed-tools mirror the workflow --allowedTools (#633)"
  _atm_out="$(
    HERE="$HERE" python3 - <<'PY'
import os, re, sys, glob

here = os.environ["HERE"]
rails = [".github/workflows/claude-routines.yml", ".github/workflows/claude-routines-call.yml"]

def norm(tools):
    # the two files spell the same list differently; compare as SETS of trimmed entries so
    # ordering and whitespace are not findings, but a missing or extra capability is.
    return frozenset(t.strip() for t in tools.split(",") if t.strip())

def frontmatter_tools(cmd):
    p = os.path.join(here, ".claude/commands/%s.md" % cmd)
    if not os.path.exists(p):
        return None
    with open(p, encoding="utf-8") as fh:
        text = fh.read()
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None
    m2 = re.search(r"^allowed-tools:[ \t]*(.+)$", m.group(1), re.M)
    return norm(m2.group(1)) if m2 else None

problems, checked = [], 0
for rail in rails:
    path = os.path.join(here, rail)
    if not os.path.exists(path):
        continue
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    # pair each --allowedTools with the nearest PRECEDING `claude -p "/<routine>"`
    for m in re.finditer(r'--allowedTools\s+"([^"]*)"', text):
        before = text[: m.start()]
        names = re.findall(r'claude -p "/([A-Za-z0-9_-]+)[^"]*"', before)
        if not names:
            problems.append("a --allowedTools with no `claude -p \"/<routine>\"` above it in %s" % rail)
            continue
        cmd = names[-1]
        checked += 1
        want = frontmatter_tools(cmd)
        if want is None:
            problems.append("%s: mirrors /%s, which has no .claude/commands/%s.md with allowed-tools"
                            % (rail, cmd, cmd))
            continue
        got = norm(m.group(1))
        if got != want:
            extra = sorted(got - want)
            missing = sorted(want - got)
            bits = []
            if extra:
                bits.append("BROADER than the frontmatter by: %s" % ", ".join(extra))
            if missing:
                bits.append("NARROWER than the frontmatter, missing: %s" % ", ".join(missing))
            problems.append("/%s in %s is %s" % (cmd, rail, "; and ".join(bits)))

if checked == 0:
    print("NONE")
elif problems:
    print("BAD %d" % checked)
    for p in problems:
        print("  " + p)
else:
    print("OK %d" % checked)
PY
  )"
  case "$_atm_out" in
  "OK "*)
    pass "allowed-tools mirror: every scheduled routine matches its workflow --allowedTools (${_atm_out#OK } mirror(s))"
    ;;
  NONE)
    fail "allowed-tools mirror: found no --allowedTools to check — the scan is broken, not the tree"
    ;;
  *)
    fail "allowed-tools mirror: a routine's frontmatter and its workflow --allowedTools disagree"
    fail_detail "$_atm_out"
    ;;
  esac
  unset _atm_out
else
  skip "allowed-tools mirror (python3 not installed)"
fi

# the same lesson the atuin-guard verification exists to enforce. Hermetic: a synthetic
# git repo with a miniature gerrrt tree, so it asserts the LOGIC, never this repo's tree.
#
# Every negative fixture asserts BOTH the finding text and exit status 1, because the
# script documents `1 = findings` as its CLI contract and audit-core.sh keys off the
# output — matching one without the other would leave half the contract untested.
if have git; then
  hdr "nvim orphan backstop (nvim-reachability.sh)"
  NVR="$HERE/scripts/nvim-reachability.sh"
  NREPO="$SANDBOX/nvimrepo"

  _nvr_fresh() { # build a minimal, fully REACHABLE gerrrt tree
    rm -rf "$NREPO"
    mkdir -p "$NREPO/nvim/lua/gerrrt/config" "$NREPO/nvim/lua/gerrrt/plugins" \
             "$NREPO/nvim/lua/gerrrt/servers" "$NREPO/nvim/lua/gerrrt/utils"
    git -C "$NREPO" init -q
    git -C "$NREPO" config user.email t@example.com
    git -C "$NREPO" config user.name tester
    printf 'require("gerrrt")\n'                          >"$NREPO/nvim/init.lua"
    printf 'require("gerrrt.config")\n'                   >"$NREPO/nvim/lua/gerrrt/init.lua"
    printf 'local M={} function M.check() end return M\n' >"$NREPO/nvim/lua/gerrrt/health.lua"
    printf 'require("gerrrt.config.lazy")\n'              >"$NREPO/nvim/lua/gerrrt/config/init.lua"
    # one explicit require, lazy's directory import, and the dynamic servers arm
    printf 'require("gerrrt.utils.term")\nrequire("lazy").setup({ { import = "gerrrt.plugins" } })\nrequire("gerrrt.servers")\n' \
                                                          >"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
    printf 'return {}\n'                                  >"$NREPO/nvim/lua/gerrrt/utils/term.lua"
    printf 'return {}\n'                                  >"$NREPO/nvim/lua/gerrrt/plugins/anything.lua"
    printf 'local servers = {\n\t"lua_ls",\n}\nfor _, n in ipairs(servers) do pcall(require, "gerrrt.servers." .. n) end\n' \
                                                          >"$NREPO/nvim/lua/gerrrt/servers/init.lua"
    printf 'return {}\n'                                  >"$NREPO/nvim/lua/gerrrt/servers/lua_ls.lua"
    git -C "$NREPO" add -A >/dev/null 2>&1
  }
  # Capture output and status TOGETHER. Note the deliberate absence of a pipeline here:
  # `"$NVR" … | grep -q` would return the SCRIPT's status under `set -o pipefail` (1
  # whenever findings exist), silently inverting every assertion below into the wrong
  # branch — which is exactly what the first version of this section did.
  _nvr_catches() { # <grep-pattern> <label>
    git -C "$NREPO" add -A >/dev/null 2>&1
    local out rc
    out="$(env -u CORE_JSON "$NVR" --root "$NREPO" 2>&1)"
    rc=$?
    if grep -q "$1" <<<"$out" && [[ $rc -eq 1 ]]; then
      pass "nvim-reachability: $2"
    else
      fail "nvim-reachability: $2 (rc=$rc, output=${out:-<empty>})"
    fi
  }
  _nvr_clean() { # <label>
    git -C "$NREPO" add -A >/dev/null 2>&1
    local out rc
    out="$(env -u CORE_JSON "$NVR" --root "$NREPO" 2>&1)"
    rc=$?
    if [[ -z "$out" && $rc -eq 0 ]]; then
      pass "nvim-reachability: $1"
    else
      fail "nvim-reachability: $1 (rc=$rc, output=${out:-<empty>})"
    fi
  }

  _nvr_fresh
  _nvr_clean "a fully reachable tree is clean"

  # the gap this whole section exists to close: a utils/ module nothing requires
  _nvr_fresh; printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/dead.lua"
  _nvr_catches 'gerrrt\.utils\.dead' "catches an orphaned utils/ module"

  # a stray top-level lua/gerrrt/*.lua (health.lua is the only legitimate one)
  _nvr_fresh; printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/junk.lua"
  _nvr_catches 'gerrrt\.junk' "catches a stray top-level module"

  # THE reason this is a graph walk and not a mention-scan: two dead modules that
  # require each other have a non-zero indegree but are reachable from nothing.
  _nvr_fresh
  printf 'require("gerrrt.utils.beta")\nreturn {}\n' >"$NREPO/nvim/lua/gerrrt/utils/alpha.lua"
  printf 'require("gerrrt.utils.alpha")\nreturn {}\n' >"$NREPO/nvim/lua/gerrrt/utils/beta.lua"
  _nvr_catches 'gerrrt\.utils\.alpha' "catches a disconnected require cycle"

  # a module named only in a COMMENT is not reached — comments are stripped before edges
  _nvr_fresh
  printf -- '-- require("gerrrt.utils.ghost")\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/ghost.lua"
  _nvr_catches 'gerrrt\.utils\.ghost' "a commented-out require does not count as an edge"

  # health.lua must NOT be flagged — Neovim discovers lua/**/health.lua by runtimepath
  _nvr_fresh; _nvr_clean "exempts health.lua (:checkhealth root)"

  # plugins/ must NOT be flagged — lazy imports the directory wholesale
  _nvr_fresh; printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/plugins/another.lua"
  _nvr_clean "exempts plugins/ (lazy imports the dir)"

  # an LSP module absent from the registry is dead config
  _nvr_fresh; printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/servers/pyright.lua"
  _nvr_catches 'pyright.*registry' "catches an unlisted LSP module"

  # the reverse — a registry name with no file is a RUNTIME load error
  _nvr_fresh
  printf 'local servers = {\n\t"lua_ls",\n\t"ghostls",\n}\n' >"$NREPO/nvim/lua/gerrrt/servers/init.lua"
  _nvr_catches 'ghostls' "catches a registry entry with no module file"

  # an unparseable registry must FAIL CLOSED — not emit N bogus findings, not go quiet
  _nvr_fresh
  printf 'local servers = vim.tbl_flatten({\n\t"lua_ls",\n})\n' >"$NREPO/nvim/lua/gerrrt/servers/init.lua"
  _nvr_catches 'could not parse' "fails closed on an unparseable registry"

  # …and so must a MISSING one: skipping it silently would disable the whole servers arm
  _nvr_fresh; rm -f "$NREPO/nvim/lua/gerrrt/servers/init.lua"
  _nvr_catches 'missing.*servers/init\.lua' "fails closed on a missing registry"

  # a `package.loaded["gerrrt.x"]` PEEK is not a load — health.lua uses exactly this to
  # inspect the registry without forcing it to load, and counting it as an edge would let
  # the whole servers/ arm look reachable from the health root with no real require left.
  _nvr_fresh
  printf 'local _ = package.loaded["gerrrt.utils.peeked"]\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/peeked.lua"
  _nvr_catches 'gerrrt\.utils\.peeked' "a package.loaded peek is not an edge"

  # a require inside a MULTILINE --[[ ]] block is still a comment; a line-only stripper
  # leaves the block interior searchable and would forge the edge
  _nvr_fresh
  printf -- '--[[\nrequire("gerrrt.utils.blockghost")\n]]\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/blockghost.lua"
  _nvr_catches 'gerrrt\.utils\.blockghost' "a multiline block comment is not an edge"

  # lua long comments come in levels — --[=[ … ]=], --[==[ … ]==] — and the closing
  # delimiter must match the opener's `=` count, so it cannot be hardcoded
  _nvr_fresh
  printf -- '--[=[\nrequire("gerrrt.utils.levelghost")\n]=]\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/levelghost.lua"
  _nvr_catches 'gerrrt\.utils\.levelghost' "a --[=[ level long comment is not an edge"

  # require() of a DIRECTORY is a runtime error, not a lazy import: it must be reported,
  # and it must NOT mark the directory's children reachable
  _nvr_fresh
  printf 'require("gerrrt.utils")\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/onlychild.lua"
  _nvr_catches 'dangling require' "reports require() of a module that does not exist"
  _nvr_catches 'gerrrt\.utils\.onlychild' "require() of a directory does not expand children"

  # a lazy import naming nothing at all is dead config, not a silent no-op
  _nvr_fresh
  printf 'require("lazy").setup({ { import = "gerrrt.nosuchdir" } })\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  _nvr_catches 'imports "gerrrt.nosuchdir"' "reports a lazy import that matches no module"

  # the inventory must map module names the way LUA does, or the walk marks the wrong rows
  # visited. Two files claiming one name: lua loads exactly one (package.path order), so
  # the other is dead config riding on its twin's reachability.
  _nvr_fresh
  mkdir -p "$NREPO/nvim/lua/gerrrt/utils/dup"
  printf 'require("gerrrt.utils.dup")\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/dup.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/dup/init.lua"
  _nvr_catches 'duplicate module id' "catches two files claiming one module id"

  # a dot inside a filename is not a path separator to lua: require("gerrrt.a.b") resolves
  # a/b.lua, never a.b.lua — so the file is unaddressable, and must not masquerade as the
  # module some other file legitimately owns
  _nvr_fresh
  printf 'require("gerrrt.utils.shadow")\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/shadow.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/shadow.init.lua"
  _nvr_catches 'unaddressable module file' "catches a literal-dot filename lua cannot address"

  # a repo with no nvim/ (every OS repo) is silently clean, not an error
  _nvr_fresh; rm -rf "$NREPO/nvim"
  _nvr_clean "no nvim/ tree is a clean no-op"
fi
# ── L. escalation + failure tally (lib/bootstrap-lib.sh) ──────────────────────
# The provisioning half of the bootstrap scaffold: blib_resolve_su picks the escalator,
# blib_priv runs a command through it, blib_user_bindirs_on_path stops the presence guards
# lying, and blib_note_fail/blib_failures_report make a half-provisioned box say so. All
# pure bash — no package manager, no network, no privileges — so it runs everywhere.
#
# Each of these encodes a real fresh-machine failure: a hard-coded `sudo` that exited 127
# on a container, a PATH-only guard that rebuilt every Rust crate on every run, and ~20
# `|| true` steps that still reported "bootstrap complete".
hdr "escalation + failure tally (blib_resolve_su / blib_priv / blib_note_fail)"
# NB: lib/bootstrap-lib.sh is deliberately NOT re-sourced here. Sections F and G already
# source it at file scope, and its `_CORE_BOOTSTRAP_LIB_SH` re-entry guard makes a repeat
# `source` a runtime no-op regardless. It is not free for `shellcheck -x` though: a third
# source re-reads the lib's `${XDG_STATE_HOME:-…}` expansions AFTER section H's subshell
# assignment of that same variable, which is enough to trip SC2030/SC2031 on section H's
# otherwise untouched line 2215.

# An explicitly-set BLIB_SU always wins — INCLUDING an empty one, which is the "already
# root / run directly" contract bootstrap-test.yml depends on. A resolver testing
# emptiness instead of set-ness would silently re-add sudo in CI.
_su_after() { (
  eval "$1"
  blib_resolve_su >/dev/null 2>&1
  printf '%s' "${BLIB_SU-UNSET}"
); }
if [[ "$(_su_after 'BLIB_SU=')" == "" ]]; then pass "blib_resolve_su: an explicit empty BLIB_SU is preserved"; else fail "blib_resolve_su clobbered an explicit BLIB_SU= (would re-add sudo as root)"; fi
if [[ "$(_su_after 'BLIB_SU=doas')" == "doas" ]]; then pass "blib_resolve_su: an explicit BLIB_SU=doas is preserved"; else fail "blib_resolve_su clobbered BLIB_SU=doas"; fi
# `command -v` also reports aliases, builtins and FUNCTIONS, so an exported `sudo()` makes
# it print the bare word `sudo`. Recording that defeats the absolute-path pinning (a bare
# name is re-resolved at every call) and could hand privileged execution to the function.
if [[ "$(id -u)" -ne 0 ]]; then
  # shellcheck disable=SC2030,SC2031,SC2123,SC2317,SC2329  # emptying PATH and defining a
  # shadowing `sudo` function are both the POINT here; the function is reached via
  # `command -v` and never called, which is why BOTH unreachability codes are suppressed.
  # SC2317 alone used to cover it; 0.10 split "this function is never invoked" out into
  # SC2329, so the older list went red on every audit leg over an info-level finding.
  _su_fn="$( unset BLIB_SU; PATH="$SANDBOX/emptybin"
    sudo() { :; }
    blib_resolve_su >/dev/null 2>&1
    printf '%s' "$BLIB_SU" )"
  if [[ -z "$_su_fn" ]]; then pass "blib_resolve_su ignores a shell FUNCTION named sudo"; else fail "blib_resolve_su recorded a non-executable [$_su_fn]"; fi
else
  skip "blib_resolve_su function-shadowing case (suite is running as root)"
fi

# With no escalator on PATH and not root, --require must FAIL (rc 1) rather than hand back
# a broken escalator; without --require it must SUCCEED (links-only needs no privileges).
mkdir -p "$SANDBOX/emptybin"
# shellcheck disable=SC2123  # emptying PATH is the POINT: it hides sudo/doas (and id)
_su_none() { ( unset BLIB_SU; PATH="$SANDBOX/emptybin"; blib_resolve_su "$@" >/dev/null 2>&1 ); }
if [[ "$(id -u)" -ne 0 ]]; then
  if _su_none --require; then fail "blib_resolve_su --require succeeded with no escalator and no root"; else pass "blib_resolve_su --require fails when there is no escalator"; fi
  if _su_none; then pass "blib_resolve_su (no --require) succeeds — links-only needs no privileges"; else fail "blib_resolve_su without --require must not fail"; fi
else
  # The MINIMAL-ROOT contract, and the only leg that can test it: as root with no id, sudo
  # or doas reachable, --require must SUCCEED with an empty BLIB_SU, because root needs no
  # escalator. This is exactly what $EUID buys — the previous `id -u` probe returned "" on a
  # PATH with no `id`, concluded "not root", and failed --require on the minimal container
  # this scaffold exists to serve. Non-root legs cannot reach the branch, so without this
  # case the regression ships unseen (and every root leg skipped the whole section).
  # shellcheck disable=SC2030,SC2031,SC2123  # emptying PATH is the point: it hides `id` too
  _su_root="$( unset BLIB_SU; PATH="$SANDBOX/emptybin"
    blib_resolve_su --require >/dev/null 2>&1 && printf 'ok/%s' "${BLIB_SU-UNSET}" || printf 'failed/%s' "${BLIB_SU-UNSET}" )"
  if [[ "$_su_root" == "ok/" ]]; then pass "blib_resolve_su --require succeeds as root on an empty PATH (no id/sudo/doas)"; else fail "root minimal-PATH --require regressed (got $_su_root; want ok/ with an empty BLIB_SU)"; fi
  skip "blib_resolve_su NON-root no-escalator cases (suite is running as root)"
fi

# "Resolve once" must mean ONCE: the recorded escalator has to survive a later PATH change,
# because blib_user_bindirs_on_path (same file) prepends user-writable dirs by design. A
# bare `sudo` would be re-resolved against the new PATH and could pick up a different
# binary — which would then receive the password prompt.
_su_pin_a="$(mktemp -d "$SANDBOX/supin-a.XXXXXX")"
_su_pin_b="$(mktemp -d "$SANDBOX/supin-b.XXXXXX")"
printf '#!/bin/sh\nexit 0\n' >"$_su_pin_a/sudo"; chmod +x "$_su_pin_a/sudo"
printf '#!/bin/sh\nexit 0\n' >"$_su_pin_b/sudo"; chmod +x "$_su_pin_b/sudo"   # the impostor
# Root-guarded, like the no-escalator cases above: as root the resolver correctly returns
# an EMPTY BLIB_SU (nothing to escalate with), so there is no path to pin. The Alpine and
# Arch audit legs run in root containers, which is exactly where an unguarded version of
# this assertion fails for the wrong reason.
if [[ "$(id -u)" -ne 0 ]]; then
  # shellcheck disable=SC2030,SC2031
  _su_pinned="$( unset BLIB_SU; PATH="$_su_pin_a:/usr/bin:/bin"
    blib_resolve_su >/dev/null 2>&1
    PATH="$_su_pin_b:$PATH"          # a later prepend, exactly what bindirs_on_path does
    printf '%s' "$BLIB_SU" )"
  if [[ "$_su_pinned" == "$_su_pin_a/sudo" ]]; then pass "blib_resolve_su pins the absolute path (survives a later PATH prepend)"; else fail "blib_resolve_su recorded [$_su_pinned] — a later PATH change can swap the escalator"; fi
else
  skip "blib_resolve_su path pinning (suite is running as root — no escalator to pin)"
fi

# blib_priv must never invoke an empty-string command: with BLIB_SU= it runs CMD directly,
# and with an escalator set it prefixes it (`env` stands in harmlessly for sudo).
if [[ "$(BLIB_SU='' blib_priv printf 'ran-%s' direct)" == "ran-direct" ]]; then pass "blib_priv with BLIB_SU= runs the command directly"; else fail "blib_priv mishandled an empty escalator"; fi
if [[ "$(BLIB_SU='env' blib_priv printf 'ran-%s' viasu)" == "ran-viasu" ]]; then pass "blib_priv routes through a non-empty BLIB_SU"; else fail "blib_priv did not route through BLIB_SU"; fi

# blib_user_bindirs_on_path: adds only EXISTING dirs, never duplicates.
#
# CARGO_HOME/GOBIN/GOPATH are UNSET here, as deliberately as HOME and PATH are pinned. These
# cases assert the $HOME-RELATIVE DEFAULTS, and the helper reaches those defaults only when
# the vars are absent — `${CARGO_HOME:-$HOME/.cargo}/bin`. Inherit an exported CARGO_HOME
# from the caller and the lookup retargets, so the fixture's own .cargo/bin never lands and
# the case reports "missed ~/.cargo/bin" on a perfectly healthy tree.
#
# Note where the leak actually lived: the RELOCATION block further down (search `_relo_home`)
# sets these vars explicitly and was always immune. It was the DEFAULT-path cases here that
# inherited. A gap between two blocks, not a coverage hole — and invisible to CI, because no
# runner exports CARGO_HOME while most developers' shells do. Same shape as the
# GHOSTTY_SHELL_FEATURES leak in the OSC 133 section: a fixture pins what it varies and
# inherits what it does not, so the ambient environment decides the verdict.
_bindirs_path() { (
  HOME="$1"
  PATH="/usr/bin"
  unset CARGO_HOME GOBIN GOPATH
  blib_user_bindirs_on_path
  blib_user_bindirs_on_path
  printf '%s' "$PATH"
); }
_bhome="$(mktemp -d "$SANDBOX/bindirs.XXXXXX")"
mkdir -p "$_bhome/.local/bin" "$_bhome/.cargo/bin" # deliberately NO go/bin, NO .atuin/bin
_bpath="$(_bindirs_path "$_bhome")"
case "$_bpath" in *"$_bhome/.local/bin"*) pass "blib_user_bindirs_on_path adds an existing ~/.local/bin" ;; *) fail "blib_user_bindirs_on_path missed ~/.local/bin" ;; esac
case "$_bpath" in *"$_bhome/.cargo/bin"*) pass "blib_user_bindirs_on_path adds an existing ~/.cargo/bin (the cargo-rebuild bug)" ;; *) fail "blib_user_bindirs_on_path missed ~/.cargo/bin" ;; esac
case "$_bpath" in *"$_bhome/go/bin"*) fail "blib_user_bindirs_on_path added a NON-EXISTENT dir (~/go/bin)" ;; *) pass "blib_user_bindirs_on_path skips directories that do not exist" ;; esac
if [[ "$(printf '%s' "$_bpath" | tr ':' '\n' | grep -cxF "$_bhome/.local/bin")" == "1" ]]; then pass "blib_user_bindirs_on_path is idempotent (no duplicate PATH entries)"; else fail "blib_user_bindirs_on_path duplicated a PATH entry on the second call"; fi

# The failure tally. Empty ⇒ silent AND rc 0; non-empty ⇒ rc 1 and every entry listed.
# That rc IS the contract a caller maps onto its --strict flag.
if (BLIB_FAILED=(); blib_failures_report >/dev/null); then pass "blib_failures_report returns 0 when nothing failed"; else fail "blib_failures_report must return 0 on an empty tally"; fi
if [[ -z "$(BLIB_FAILED=(); blib_failures_report 2>&1)" ]]; then pass "blib_failures_report prints nothing when nothing failed"; else fail "blib_failures_report printed on an empty tally"; fi
_tally_out="$(BLIB_FAILED=(); blib_note_fail 'carapace: RPM install failed' >/dev/null 2>&1; blib_note_fail 'op: install failed' >/dev/null 2>&1; blib_failures_report 2>&1 || true)"
case "$_tally_out" in *"2 step(s) did not complete"*) pass "blib_failures_report counts the recorded steps" ;; *) fail "blib_failures_report lost the count" ;; esac
case "$_tally_out" in *"carapace: RPM install failed"*) pass "blib_failures_report lists the first failure" ;; *) fail "blib_failures_report dropped a recorded failure" ;; esac
case "$_tally_out" in *"op: install failed"*) pass "blib_failures_report lists the last failure" ;; *) fail "blib_failures_report dropped the last failure" ;; esac
if (BLIB_FAILED=(); blib_note_fail x >/dev/null 2>&1; blib_failures_report >/dev/null 2>&1); then fail "blib_failures_report must return NON-zero when a step failed"; else pass "blib_failures_report returns non-zero when a step failed (drives --strict)"; fi
if [[ "$(BLIB_FAILED=(); blib_note_fail a >/dev/null 2>&1; blib_note_fail b >/dev/null 2>&1; blib_failed_count)" == "2" ]]; then pass "blib_failed_count reports the tally size"; else fail "blib_failed_count wrong"; fi
# bash 3.2 + `set -u`: an empty array expansion counts as UNSET, so a bare
# "${BLIB_FAILED[@]}" would abort the report on the HAPPY path. Prove the guarded form
# survives errexit+nounset — which is exactly how a bootstrap runs.
if (set -eu; BLIB_FAILED=(); blib_failures_report >/dev/null 2>&1); then pass "blib_failures_report survives set -eu with an empty tally (bash 3.2 array rule)"; else fail "blib_failures_report tripped set -u on an empty array"; fi

# ── the relocatable bindirs (CARGO_HOME / GOBIN / GOPATH) ────────────────────
# cargo honours $CARGO_HOME and go honours $GOBIN then $GOPATH/bin. Hard-coding
# ~/.cargo/bin would leave a box with a custom CARGO_HOME still rebuilding every crate on
# every run — the same bug, just relocated.
_relo_home="$(mktemp -d "$SANDBOX/relo.XXXXXX")"
mkdir -p "$_relo_home/xdgcargo/bin" "$_relo_home/gobin" "$_relo_home/gopath/bin"
_relo_path="$( HOME="$_relo_home" CARGO_HOME="$_relo_home/xdgcargo" GOBIN="$_relo_home/gobin" PATH=/usr/bin; export CARGO_HOME GOBIN; blib_user_bindirs_on_path; printf '%s' "$PATH" )"
case "$_relo_path" in *"$_relo_home/xdgcargo/bin"*) pass "blib_user_bindirs_on_path honours CARGO_HOME" ;; *) fail "blib_user_bindirs_on_path ignored CARGO_HOME" ;; esac
case "$_relo_path" in *"$_relo_home/gobin"*) pass "blib_user_bindirs_on_path honours GOBIN" ;; *) fail "blib_user_bindirs_on_path ignored GOBIN" ;; esac
# shellcheck disable=SC2030,SC2031  # a subshell-local PATH is the POINT of every probe below
_relo_path2="$( HOME="$_relo_home" GOPATH="$_relo_home/gopath" PATH=/usr/bin; unset GOBIN; export GOPATH; blib_user_bindirs_on_path; printf '%s' "$PATH" )"
case "$_relo_path2" in *"$_relo_home/gopath/bin"*) pass "blib_user_bindirs_on_path falls back to GOPATH/bin when GOBIN is unset" ;; *) fail "blib_user_bindirs_on_path ignored GOPATH" ;; esac
# GOPATH is a LIST: go installs into the FIRST entry's bin/. Appending /bin to the whole
# value would probe "/first:/second/bin", which exists nowhere — so the Go tools stay off
# PATH and get rebuilt every run, the exact failure this helper exists to prevent.
# shellcheck disable=SC2030,SC2031
_relo_path3="$( HOME="$_relo_home" GOPATH="$_relo_home/gopath:$_relo_home/second" PATH=/usr/bin; unset GOBIN; export GOPATH; blib_user_bindirs_on_path; printf '%s' "$PATH" )"
case "$_relo_path3" in *"$_relo_home/gopath/bin"*) pass "blib_user_bindirs_on_path uses GOPATH's FIRST entry when it is a list" ;; *) fail "blib_user_bindirs_on_path mishandled a multi-entry GOPATH (got: $_relo_path3)" ;; esac
case "$_relo_path3" in *":$_relo_home/second/bin"*|*"gopath:$_relo_home/second/bin"*) fail "blib_user_bindirs_on_path built a bogus path from a multi-entry GOPATH" ;; *) pass "blib_user_bindirs_on_path builds no bogus /a:/b/bin entry" ;; esac

# ── sudo keepalive (hermetic: a shimmed `sudo` on PATH, never the real one) ───
# The riskiest code in this batch — it forks a background refresher and installs no trap of
# its own — so pin the branches that decide whether it runs at all, that a failed FIRST
# authentication is reported (so a caller can abort before half-provisioning), and that
# stop() is idempotent and leaves no orphan.
_ka_bin="$(mktemp -d "$SANDBOX/kabin.XXXXXX")"
printf '#!/bin/sh\nexit 0\n' >"$_ka_bin/sudo"; chmod +x "$_ka_bin/sudo"
# TWO intervals, and the difference between them is deliberate — see each use site.
#   _KA_INTERVAL          the SHORT one, for the block that must watch the loop go round.
#   _KA_DEFAULT_INTERVAL  the SHIPPED default, for the block whose assertion needs a
#                         sleeper that would still be alive if stop() had not reaped it.
# The shipped default is pinned below rather than assumed: the sleeper shim keys on it, so
# a change to bootstrap-lib.sh that this file did not follow must say so by name instead of
# surfacing as the much vaguer "forked no sleeper".
_KA_INTERVAL=1
_KA_DEFAULT_INTERVAL=50
_ka_shipped="$(sed -n 's/^  local interval="${BLIB_SUDO_KEEPALIVE_INTERVAL:-\([0-9]*\)}"$/\1/p' "$HERE/lib/bootstrap-lib.sh")"
if [[ "$_ka_shipped" == "$_KA_DEFAULT_INTERVAL" ]]; then
  pass "keepalive: the shipped refresh interval is still ${_KA_DEFAULT_INTERVAL}s (the sleeper shim keys on it)"
else
  fail "keepalive: lib/bootstrap-lib.sh ships a ${_ka_shipped:-unreadable} refresh interval, but this suite's sleeper shim keys on ${_KA_DEFAULT_INTERVAL} — update _KA_DEFAULT_INTERVAL or the shim records nothing and the reaping assertion goes vacuous"
fi
# _ka_pid <BLIB_SU> <BLIB_DRY> — start the keepalive against the shimmed sudo, print the
# pid it recorded (empty when it correctly declined to fork). _ka_rc is the same, returning
# the rc instead. Both wrap the subshell so the SC2030/SC2031 suppression is stated once.
# shellcheck disable=SC2030,SC2031  # a subshell-local PATH is the POINT (hermetic sudo shim)
_ka_pid() { ( BLIB_SU="$1"; BLIB_DRY="$2"; BLIB_SUDO_KEEPALIVE_PID=""; PATH="$_ka_bin:$PATH"
  blib_sudo_keepalive_start >/dev/null 2>&1
  _p="${BLIB_SUDO_KEEPALIVE_PID:-}"
  blib_sudo_keepalive_stop  # reap BEFORE printing: a live refresher would otherwise be
  printf '%s' "$_p" ); }    # a second writer on this substitution's pipe
# shellcheck disable=SC2030,SC2031
_ka_rc() { ( BLIB_SU="$1"; BLIB_DRY="$2"; BLIB_SUDO_KEEPALIVE_PID=""; PATH="$_ka_bin:$PATH"
  blib_sudo_keepalive_start >/dev/null 2>&1 ); }
# not-sudo escalators must no-op: doas has no refreshable timestamp, root has nothing to prime.
if [[ -z "$(_ka_pid doas 0)" ]]; then pass "blib_sudo_keepalive_start no-ops under doas"; else fail "blib_sudo_keepalive_start started a refresher under doas"; fi
if [[ -z "$(_ka_pid '' 0)" ]]; then pass "blib_sudo_keepalive_start no-ops as root (BLIB_SU=)"; else fail "blib_sudo_keepalive_start started a refresher as root"; fi
# BLIB_DRY must PREVIEW, never authenticate or fork.
if [[ -z "$(_ka_pid sudo 1)" ]]; then pass "blib_sudo_keepalive_start forks nothing under BLIB_DRY"; else fail "blib_sudo_keepalive_start forked a refresher during a dry run"; fi
# BLIB_SU is documented as a single command TOKEN, so an absolute path is a valid override.
# Matching the literal string `sudo` skipped priming for it, silently restoring the very
# timestamp expiry (and invisible prompt) this helper exists to prevent.
if [[ -n "$(_ka_pid "$_ka_bin/sudo" 0)" ]]; then pass "blib_sudo_keepalive_start primes an absolute-path BLIB_SU (/…/sudo)"; else fail "an absolute-path BLIB_SU silently disabled the keepalive"; fi
# a FAILED initial `sudo -v` must return non-zero — that rc is what lets a caller abort.
printf '#!/bin/sh\nexit 1\n' >"$_ka_bin/sudo"
if _ka_rc sudo 0; then fail "blib_sudo_keepalive_start returned 0 when sudo -v failed"; else pass "blib_sudo_keepalive_start reports a failed initial authentication"; fi
# the happy path: it forks exactly one refresher, and stop() reaps it and is re-callable.
# The shim now RECORDS its argv, so the refresh MODE is assertable further down: a shim that
# merely exits 0 accepts `-n true` and `-n -v` alike, and the suite passed either way — it
# could not see the restricted-sudoers fix at all.
#
# `printf`, not `echo`: given argv `-n -v`, dash's echo eats the `-n` as its own no-newline
# flag and records a bare `-v` — a harness that reports the OLD behaviour as the new one.
_ka_argv="$_ka_bin/argv"
: >"$_ka_argv"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$_ka_argv" >"$_ka_bin/sudo"
# shellcheck disable=SC2030,SC2031  # subshell-local PATH again: the shimmed sudo
_ka_out="$( BLIB_SU=sudo; BLIB_DRY=0; BLIB_SUDO_KEEPALIVE_PID=""; PATH="$_ka_bin:$PATH"
  blib_sudo_keepalive_start >/dev/null 2>&1
  pid="$BLIB_SUDO_KEEPALIVE_PID"
  kill -0 "$pid" 2>/dev/null && alive=yes || alive=no
  blib_sudo_keepalive_stop
  sleep 0.2
  kill -0 "$pid" 2>/dev/null && after=alive || after=reaped
  blib_sudo_keepalive_stop   # second call must be a harmless no-op
  printf '%s/%s/%s' "$alive" "$after" "${BLIB_SUDO_KEEPALIVE_PID:-empty}" )"
case "$_ka_out" in yes/*) pass "blib_sudo_keepalive_start forks a live refresher" ;; *) fail "blib_sudo_keepalive_start did not fork a refresher (got $_ka_out)" ;; esac
case "$_ka_out" in */reaped/*) pass "blib_sudo_keepalive_stop reaps the refresher shell" ;; *) fail "blib_sudo_keepalive_stop left the refresher running (got $_ka_out)" ;; esac
# The refresh must use sudo's VALIDATION mode. `-n true` additionally requires the account
# to be authorised to run `true`, which a sudoers restricted to the provisioning commands
# denies — the refresh then fails silently and the timestamp expires, restoring the hang.
# The initial prime is a bare `-v`, so require the `-n -v` line specifically.
#
# Its OWN run, which POLLS for that line before stopping. Reusing the block above would
# make this scheduler-dependent: that one stops after a fixed short delay, and a loaded
# runner need not have scheduled the background loop's first refresh by then. It did not on
# macOS — the argv log held only the initial `-v` and the assertion failed for a timing
# reason that had nothing to do with the behaviour under test.
#
# THIS BLOCK CAN STALL FOR ONE FULL REFRESH INTERVAL, and the cause is NOT yet known. Read
# the next 20 lines before trying to fix it — two plausible explanations have already been
# measured and killed, and the interval seam only bounds the damage.
#
# MEASURED:
#   • It is INTERMITTENT, not the constant an earlier version of this comment asserted:
#     2 stalls in 16 instrumented suite runs (50.017s pre-seam, 20.016s driven at 20), every
#     other run 0.02–0.13s. Expect to see "already fast" and wrongly conclude it is fixed.
#   • The cost is exactly one interval + ~20ms, at every interval it has been driven at.
#   • During a stall, sampling /proc/<pid>/fd across the whole window (1644 samples): ONE
#     sleeper, all three fds on /dev/null the entire time, its parent — the refresher loop
#     shell — alive throughout. So the subshell was still inside blib_sudo_keepalive_stop,
#     whose `wait` was blocked on a loop shell that did not act on its TERM until its sleeper
#     expired on its own. This is a TEARDOWN stall.
#
# RULED OUT — do not re-propose these:
#   • Pipe retention by the refresher keeping the command substitution open. An unredirected
#     sleeper does reproduce the one-interval signature by construction (0.329s redirected vs
#     7.023s not, at an interval of 7), but the shipped loop redirects and the fd sampling
#     above never once caught a pipe. A matching duration is not a diagnosis.
#   • Rewriting this as `( … )` + reading the argv file afterwards, i.e. removing the
#     substitution. Measured on the converted block: 2 stalls in 2 runs, 30.012s and 30.013s.
#     The parent waits for the subshell either way, and the subshell is what blocks.
#
# RESOLVED (#529): teardown was the right suspect, but not for the expected reason. The
# trap's TERM DID reach the sleeper — `kill` returned 0 — and the sleeper went on to exit
# normally after its full interval anyway, with no signal blocked, ignored or caught. It was
# killable and the signal was lost, not refused. lib/bootstrap-lib.sh now follows the TERM
# with a KILL, which cannot be lost, and the gate further down forces that case with a
# SIGTERM-ignoring sleeper so it is not left to a 1-in-3 race.
#
# The mechanism behind the lost signal was never isolated, and nothing here should pretend
# otherwise: it reproduces only inside this suite. stop() alone is clean (0/60 at an interval
# of 5), this block outside the suite is clean (0/40, 0/30), and no start→stop delay from
# 0–50ms provokes it.
#
# BLIB_SUDO_KEEPALIVE_INTERVAL does NOT keep this poll short, whatever it may once have
# claimed: the poll is bounded by its own 100 × 0.1s, and the `-n -v` it waits for is written
# BEFORE the loop's first sleep, so it returns on iteration zero at any interval. What the
# seam does is cap a stall at ~1s instead of ~50s when the race fires.
# shellcheck disable=SC2030,SC2031  # subshell-local PATH: the shimmed sudo
_ka_mode="$( BLIB_SU="$_ka_bin/sudo"; BLIB_DRY=0; BLIB_SUDO_KEEPALIVE_PID=""; PATH="$_ka_bin:$PATH"
  BLIB_SUDO_KEEPALIVE_INTERVAL="$_KA_INTERVAL"
  : >"$_ka_argv"
  blib_sudo_keepalive_start >/dev/null 2>&1
  n=0
  while ((n < 100)); do grep -qe '-n -v' "$_ka_argv" 2>/dev/null && break; sleep 0.1; n=$((n + 1)); done
  blib_sudo_keepalive_stop
  tr '\n' '|' <"$_ka_argv" )"
case "$_ka_mode" in *"-n -v"*) pass "the background refresh uses 'sudo -n -v' (validation mode)" ;; *) fail "the refresher did not use -n -v (argv recorded: $_ka_mode)" ;; esac
# The refresher's SLEEPER is a separate process. Killing only the loop shell leaves it
# running — orphaned for up to its full duration — and the pid check above cannot see that,
# so it certified a "no orphan" property it never tested.
#
# Assert on THIS keepalive's own sleeper, by pid. Comparing a global `pgrep -x sleep` count
# before and after could not tell our sleeper from the box's, and failed in BOTH directions:
# an unrelated sleep exiting between the two snapshots dropped the count and passed the
# assertion while this keepalive had in fact leaked one, and an unrelated sleep starting
# failed it for something no one here did. On a CI leg (or a dev box running two suites at
# once) that is a coin toss, and the direction that matters is the silent pass.
#
# The shim records the sleeper's pid and then EXECs the real sleep, so the recorded pid IS
# the surviving process — no parent/child indirection to get wrong. Only the refresher's own
# sleeper is recorded: the harness's own short sleeps reach this shim through the same
# scoped PATH, and counting those would put us right back to measuring the box.
#
# This block deliberately does NOT shorten the interval the way the refresh-mode block above
# does, and that is the whole reason the two constants exist. The assertion here is that
# stop() REAPED the sleeper — which is only meaningful while the sleeper would otherwise
# still be running. Under a 1s interval it would exit on its own inside the poll window and
# the check would pass for a reason that has nothing to do with stop(): a silent vacuous
# pass, the exact failure mode the "recorded none" guard below exists to prevent.
_ka_sleeper_file="$SANDBOX/ka-sleeper.pids"
: >"$_ka_sleeper_file"
_ka_real_sleep="$(command -v sleep)"
cat >"$_ka_bin/sleep" <<SHIM
#!/bin/sh
case "\$1" in $_KA_DEFAULT_INTERVAL) printf '%s\n' "\$\$" >>"$_ka_sleeper_file" ;; esac
exec "$_ka_real_sleep" "\$@"
SHIM
chmod +x "$_ka_bin/sleep"
# shellcheck disable=SC2030,SC2031
# No fixed delays, in EITHER direction. A pre-stop sleep can fire before the refresher has
# been scheduled on a loaded runner (that is the macOS failure documented above), so poll
# for the recording instead. And a post-stop grace period is worse than useless here: it
# lets a NON-synchronous stop() pass whenever the sleeper happens to die shortly after,
# which is exactly the contract under test — so assert the instant stop() returns.
# shellcheck disable=SC2030,SC2031
( BLIB_SU="$_ka_bin/sudo"; BLIB_DRY=0; BLIB_SUDO_KEEPALIVE_PID=""; PATH="$_ka_bin:$PATH"
  blib_sudo_keepalive_start >/dev/null 2>&1
  n=0; while ((n < 100)) && [[ ! -s "$_ka_sleeper_file" ]]; do sleep 0.1; n=$((n + 1)); done
  blib_sudo_keepalive_stop ) >/dev/null 2>&1
_ka_sleeper_pid="$(head -n1 "$_ka_sleeper_file" 2>/dev/null || true)"
# An empty recording is a FAILURE, not a pass. If the shim never fired, no sleeper was ever
# forked and the reaping claim is vacuous — precisely the silent-pass mode being removed.
if [[ -z "$_ka_sleeper_pid" ]]; then
  fail "the keepalive forked no sleeper (shim recorded none) — the reaping assertion would be vacuous"
elif kill -0 "$_ka_sleeper_pid" 2>/dev/null; then
  fail "blib_sudo_keepalive_stop returned with its sleeper (pid $_ka_sleeper_pid) still alive — teardown is not synchronous"
else
  pass "blib_sudo_keepalive_stop reaps the SLEEPER before returning (synchronous teardown)"
fi
case "$_ka_out" in */empty) pass "blib_sudo_keepalive_stop clears the pid and is idempotent" ;; *) fail "blib_sudo_keepalive_stop did not clear the pid (got $_ka_out)" ;; esac
# BLIB_SUDO_KEEPALIVE_INTERVAL exists for this suite, which means the fleet now ships a knob
# that a stray value in someone's environment can reach. Its guard has to be tested, or the
# seam that made this suite fast is also a way to make a provisioning run hammer sudo in a
# busy-loop — the interval is the ONLY thing bounding that loop's rate.
#
# Assert on the argument the sleeper is actually given, not on the source: a regex that
# merely LOOKS right (`[0-9]*` accepts the empty string, `+` vs `*`) is precisely how a
# validator passes review and admits `0` anyway. The shim records argv; each case reads back
# what the loop asked for.
_ka_iv_argv="$_ka_bin/sleep-argv"
cat >"$_ka_bin/sleep" <<SHIM
#!/bin/sh
case "\$1" in 0.*) ;; *) printf '%s\n' "\$1" >>"$_ka_iv_argv" ;; esac
exec "$_ka_real_sleep" "\$@"
SHIM
chmod +x "$_ka_bin/sleep"
# _ka_iv <override> — run one keepalive cycle under that override, print the interval the
# refresher's sleeper was handed. Unset is spelled by passing the literal token `unset`.
# shellcheck disable=SC2030,SC2031
_ka_iv() { ( : >"$_ka_iv_argv"
  BLIB_SU="$_ka_bin/sudo"; BLIB_DRY=0; BLIB_SUDO_KEEPALIVE_PID=""; PATH="$_ka_bin:$PATH"
  if [[ "$1" == unset ]]; then unset BLIB_SUDO_KEEPALIVE_INTERVAL; else BLIB_SUDO_KEEPALIVE_INTERVAL="$1"; fi
  blib_sudo_keepalive_start >/dev/null 2>&1
  n=0; while ((n < 100)) && [[ ! -s "$_ka_iv_argv" ]]; do sleep 0.1; n=$((n + 1)); done
  blib_sudo_keepalive_stop ) >/dev/null 2>&1
  head -n1 "$_ka_iv_argv" 2>/dev/null || true; }
# The honoured case FIRST: a guard that rejects everything would pass every fail-safe case
# below and still have broken the seam this change exists for.
_ka_iv_got="$(_ka_iv "$_KA_INTERVAL")"
if [[ "$_ka_iv_got" == "$_KA_INTERVAL" ]]; then pass "keepalive: a valid BLIB_SUDO_KEEPALIVE_INTERVAL is honoured (the test seam works)"; else fail "keepalive: BLIB_SUDO_KEEPALIVE_INTERVAL=$_KA_INTERVAL was not honoured (sleeper got '${_ka_iv_got:-nothing}')"; fi
# `0` and `-1` are the values that turn the loop into a sudo busy-loop; the empty string is
# what an exported-but-unset variable looks like; `5s`/`abc` are ordinary typos. Every one
# must land on the shipped default, not on itself and not on an error.
_ka_iv_bad=0
for _ka_iv_case in 0 -1 "" 5s abc 1.5 " " 01; do
  _ka_iv_got="$(_ka_iv "$_ka_iv_case")"
  [[ "$_ka_iv_got" == "$_KA_DEFAULT_INTERVAL" ]] || { _ka_iv_bad=1; fail "keepalive: BLIB_SUDO_KEEPALIVE_INTERVAL='$_ka_iv_case' did not fall back to ${_KA_DEFAULT_INTERVAL}s — the sleeper got '${_ka_iv_got:-nothing}'"; }
done
((_ka_iv_bad)) || pass "keepalive: a zero/negative/non-numeric interval falls back to ${_KA_DEFAULT_INTERVAL}s (no sudo busy-loop from a stray override)"
_ka_iv_got="$(_ka_iv unset)"
if [[ "$_ka_iv_got" == "$_KA_DEFAULT_INTERVAL" ]]; then pass "keepalive: an unset interval is the shipped ${_KA_DEFAULT_INTERVAL}s (the seam changes no default)"; else fail "keepalive: with no override the sleeper got '${_ka_iv_got:-nothing}', not ${_KA_DEFAULT_INTERVAL}"; fi
rm -f "$_ka_bin/sleep"
# ── #529: stop() must not block when a TERM to the sleeper goes unheeded ─────
# The shipped hang was a race: a TERM aimed at the sleeper is sometimes accepted by kill(2)
# — rc 0 — and never acted on, so the handler's `wait` sits out the sleeper's entire
# interval and stop() blocks behind it. 50s in a real provisioning run. In this suite it
# reproduced about 1 run in 3 at a 30s interval and never once outside it, and a 1-in-3
# race is not a gate: it would pass on the run that mattered.
#
# So force the case instead of waiting for it. A sleeper that IGNORES SIGTERM is the lost
# signal made deterministic — SIG_IGN survives exec, so the real `sleep` inherits it from
# the shim. The handler's KILL cannot be caught or ignored, so stop() still returns at
# once; drop the KILL and this blocks for the whole interval, every time.
#
# Asserted on WALL CLOCK on purpose. "stop() eventually returned and the sleeper was gone"
# is true in BOTH cases — it is the passing-for-the-wrong-reason this exists to catch.
# NO fixed pre-stop delay, for the reason stated at the reaping block above: on a loaded
# runner a fixed sleep can elapse before the refresher has been scheduled at all, and then
# stop() finds no job to signal, returns instantly, and this passes with the KILL deleted —
# the vacuous pass it exists to prevent. Poll for the shim's recording instead, and treat an
# empty recording as a FAILURE rather than a pass.
#
# The shim records only the refresher's own sleeper (it keys on the interval), so the poll's
# 0.1s sleeps reaching the same shim are not counted. Timing is taken INSIDE the subshell
# around stop() alone, so the poll's own duration cannot mask a blocked teardown.
_ka_ign_iv=5
_ka_ign_file="$SANDBOX/ka-ignterm.pids"
_ka_ign_dur="$SANDBOX/ka-ignterm.dur"
: >"$_ka_ign_file"
: >"$_ka_ign_dur"
cat >"$_ka_bin/sleep" <<SHIM
#!/bin/sh
trap '' TERM
case "\$1" in $_ka_ign_iv) printf '%s\n' "\$\$" >>"$_ka_ign_file" ;; esac
exec "$_ka_real_sleep" "\$@"
SHIM
chmod +x "$_ka_bin/sleep"
# shellcheck disable=SC2030,SC2031  # subshell-local PATH: the shimmed sudo + sleep
( BLIB_SU="$_ka_bin/sudo"; BLIB_DRY=0; BLIB_SUDO_KEEPALIVE_PID=""; PATH="$_ka_bin:$PATH"
  BLIB_SUDO_KEEPALIVE_INTERVAL="$_ka_ign_iv"
  blib_sudo_keepalive_start >/dev/null 2>&1
  n=0; while ((n < 100)) && [[ ! -s "$_ka_ign_file" ]]; do sleep 0.1; n=$((n + 1)); done
  _ka_ign_t0=$SECONDS
  blib_sudo_keepalive_stop
  printf '%s' "$((SECONDS - _ka_ign_t0))" >"$_ka_ign_dur" ) >/dev/null 2>&1
rm -f "$_ka_bin/sleep"
_ka_ign_pid="$(head -n1 "$_ka_ign_file" 2>/dev/null || true)"
_ka_ign_d="$(cat "$_ka_ign_dur" 2>/dev/null || true)"
if [[ -z "$_ka_ign_pid" ]]; then
  fail "keepalive: no SIGTERM-ignoring sleeper was ever forked (shim recorded none) — the timing assertion would be vacuous (#529)"
elif [[ -n "$_ka_ign_d" ]] && ((_ka_ign_d < _ka_ign_iv - 1)); then
  pass "keepalive: stop() returns promptly when the sleeper ignores SIGTERM (${_ka_ign_d}s < ${_ka_ign_iv}s)"
else
  fail "keepalive: stop() blocked ${_ka_ign_d:-?}s waiting out a SIGTERM-ignoring sleeper (pid $_ka_ign_pid) — the handler's KILL is gone (#529)"
fi

# The TERM handler must target the JOB, never a pid. `$!` does not clear when `wait` reaps
# the sleeper, so a handler holding it signals that dead pid for the whole of the next
# `sudo -n -v` — and once the box has cycled through the pid space, whatever now owns it,
# as root. A saved copy is wrong the other way (assigned after the fork, so a TERM in
# between orphans the new sleeper). Only a job spec is set by the fork AND cleared by the
# reap. This is a STRUCTURAL gate because the failure needs a 50s iteration boundary plus a
# pid wrap to observe — unreachable in a suite, which is exactly why it needs pinning.
#
# The KILL is pinned here for the same reason but a different failure: a lone TERM is
# sometimes accepted by kill(2) and never acted on, and the handler then blocks in `wait`
# for the sleeper's whole interval (#529). Dropping the KILL back out would restore an
# intermittent 50s hang that the behavioral gate below can catch only because it forces the
# case with a TERM-ignoring sleeper — in the wild it is roughly a 1-in-3 race, so this line
# is what keeps someone from "simplifying" it away on a green run.
_ka_trap_want="trap 'kill %% 2>/dev/null; kill -9 %% 2>/dev/null; wait %% 2>/dev/null; exit 0' TERM"
# ONE matcher, used for BOTH the extraction and the count. Two matchers could disagree,
# and a gate whose two halves disagree is the failure this whole change is about.
#
# It recognises TERM ANYWHERE in the signal operand list, not only as the final token. The
# first version anchored on `.*TERM$`, which made a second handler invisible:
#     trap 'exit 0' TERM INT   -> not matched (TERM is not last)
#     trap 'exit 0' 15         -> not matched (numeric spelling)
# Bash gives a signal to the MOST RECENT trap, so either line added later would replace the
# keepalive's TERM behaviour while this gate still counted one handler, still saw the safe
# line, and still passed. That is a matcher asserting less than it appears to — precisely
# the defect this change exists to remove, sitting inside the fix for it.
#
# Anchoring the signal list AFTER the quoted handler is what keeps it honest in the other
# direction too: `trap 'echo TERM' INT` mentions TERM in the COMMAND and is correctly
# ignored, where a bare `.*TERM` would have matched it.
_ka_trap_re="^[[:space:]]*trap[[:space:]]+('[^']*'|\"[^\"]*\")[[:space:]]+([A-Za-z0-9]+[[:space:]]+)*(TERM|SIGTERM|15)([[:space:]]|\$)"
_ka_trap="$(grep -E "$_ka_trap_re" "$HERE/lib/bootstrap-lib.sh" 2>/dev/null)"
_ka_trap="${_ka_trap#"${_ka_trap%%[![:space:]]*}"}" # ltrim indentation, keep the statement
# Exactly one TERM handler is expected. If a second is ever added the equality below would
# compare a two-line string and red for a confusing reason, so say the real one out loud.
_ka_trap_n="$(grep -cE "$_ka_trap_re" "$HERE/lib/bootstrap-lib.sh" 2>/dev/null || echo 0)"
# REQUIRE the job spec, do not merely reject the pid spellings. A blacklist passes anything
# it did not think of — `trap 'exit 0' TERM` names no pid, sails through, and silently
# restores the orphan leak; so does a differently-named pid variable. Demand both halves
# positively (`kill %%` to signal the sleeper, `wait %%` to reap it before exiting) AND
# keep the pid rejection, so the two failure modes are covered from both directions.
if [[ -z "$_ka_trap" ]]; then
  fail "keepalive: no TERM handler found in lib/bootstrap-lib.sh — the reaping gate cannot check anything"
elif [[ "$_ka_trap_n" != 1 ]]; then
  fail "keepalive: expected exactly one TERM handler in lib/bootstrap-lib.sh, found $_ka_trap_n — this gate assumes the keepalive owns the only one"
elif [[ "$_ka_trap" == *'$!'* || "$_ka_trap" == *'_sleeper'* ]]; then
  fail "keepalive: the TERM handler targets a pid, not a job — \$! survives the reap and can signal a recycled pid: $_ka_trap"
elif [[ "$_ka_trap" != "$_ka_trap_want" ]]; then
  # WHOLE-HANDLER equality, not a pattern. Each looser form let something through, because
  # a wildcard between two command names asserts nothing about what sits in the gap:
  #   membership   accepted `exit 0; kill %%; wait %%`   (cleanup after the exit, dead code)
  #   ordered glob accepted `kill %%; exit 0; wait %%; exit 0` (reaps after exiting) and
  #                         `kill %%; wait %% & exit 0`  (reap backgrounded — not synchronous)
  # The production handler has exactly one safe form, so compare against it verbatim. A
  # deliberate change to it must update this expectation in the same commit — which is the
  # point: this gate exists because the failure needs a 50s boundary plus a pid wrap to
  # observe at runtime, so review is the only place it can be caught.
  fail "keepalive: the TERM handler is not the expected form.
    want: $_ka_trap_want
    got:  $_ka_trap"
else
  pass "keepalive: the TERM handler kills AND waits the job (%%), so it cannot leak or signal a recycled pid"
fi

# The matcher above is the gate's blind-spot surface: anything it cannot SEE is a handler
# that can replace the keepalive's TERM behaviour while the count stays 1 and the equality
# still compares the safe line. Bash gives a signal to the most recent trap, so an
# invisible second handler wins silently. Pin what it must see and what it must not, or
# the anchor can quietly narrow again (it did: `.*TERM$` missed both forms below).
_ka_re_is() { # _ka_re_is <label> <candidate-line> <want:0|1>
  local n
  n="$(printf '%s\n' "$2" | grep -cE "$_ka_trap_re")"
  if [[ "$n" == "$3" ]]; then pass "trap matcher: $1"; else fail "trap matcher: $1 (matched=$n want=$3)"; fi
}
_ka_re_is "sees the shipped handler" "    trap 'kill %% 2>/dev/null; kill -9 %% 2>/dev/null; wait %% 2>/dev/null; exit 0' TERM" 1
_ka_re_is "sees TERM when it is NOT the last operand" "    trap 'exit 0' TERM INT" 1
_ka_re_is "sees TERM after another signal" "    trap 'exit 0' INT TERM" 1
_ka_re_is "sees the SIGTERM spelling" "    trap 'exit 0' SIGTERM" 1
_ka_re_is "sees the numeric spelling (15)" "    trap 'exit 0' 15" 1
_ka_re_is "sees a double-quoted handler" '    trap "exit 0" TERM' 1
# The other direction: it must not fire on traps that do not take TERM, or the gate reds on
# unrelated edits and someone deletes it.
_ka_re_is "ignores a trap that does not take TERM" "    trap 'exit 0' HUP INT" 0
_ka_re_is "ignores TERM appearing inside the COMMAND, not the signal list" "    trap 'echo TERM' INT" 0

# ── blib_set_login_shell must never abort a completed wiring ─────────────────
# It runs at the very END of wire_links, so a failure here would discard an otherwise
# correct install. Shim zsh/getent/chsh so the function reaches its mutating half, then
# make each mutation fail and assert the whole thing still returns 0 under `set -e`.
_ls_bin="$(mktemp -d "$SANDBOX/lsbin.XXXXXX")"
printf '#!/bin/sh\nexit 0\n' >"$_ls_bin/zsh"; chmod +x "$_ls_bin/zsh"
# getent reports a NON-zsh current shell so the early "already zsh" return is not taken.
printf '#!/bin/sh\necho "u:x:1:1::/home/u:/bin/sh"\n' >"$_ls_bin/getent"; chmod +x "$_ls_bin/getent"
printf '#!/bin/sh\nexit 1\n' >"$_ls_bin/chsh"; chmod +x "$_ls_bin/chsh"   # chsh FAILS
printf '#!/bin/sh\nexit 1\n' >"$_ls_bin/tee"; chmod +x "$_ls_bin/tee"     # /etc/shells append FAILS
printf '#!/bin/sh\nexit 1\n' >"$_ls_bin/grep"; chmod +x "$_ls_bin/grep"   # ...so the append is attempted
for _b in id printf cut awk; do [[ -x "$_ls_bin/$_b" ]] || ln -sf "$(command -v "$_b")" "$_ls_bin/$_b" 2>/dev/null; done
if ( set -eu
     PATH="$_ls_bin:/usr/bin:/bin"
     BLIB_SU=""; BLIB_DRY=0; BLIB_ONLY=""; BLIB_SKIP=""
     blib_set_login_shell >/dev/null 2>&1 ); then
  pass "blib_set_login_shell returns 0 under set -e when /etc/shells AND chsh both fail"
else
  fail "blib_set_login_shell still aborts a completed wiring when its last step fails"
fi
# ...and it must SAY so rather than failing silently.
_ls_msg="$( PATH="$_ls_bin:/usr/bin:/bin" BLIB_SU="" BLIB_DRY=0 BLIB_ONLY="" BLIB_SKIP="" blib_set_login_shell 2>&1 || true )"
# Match the two warnings SEPARATELY and on strings unique to each. A bare *chsh* match is
# vacuous: the /etc/shells warning also says "chsh may refuse it", so it passed whether or
# not the chsh branch ever ran.
case "$_ls_msg" in *"could not add"*) pass "blib_set_login_shell warns when the /etc/shells append fails" ;; *) fail "blib_set_login_shell swallowed the /etc/shells failure (got: $_ls_msg)" ;; esac
case "$_ls_msg" in *"chsh failed"*) pass "blib_set_login_shell warns when chsh fails, naming the manual fallback" ;; *) fail "blib_set_login_shell swallowed the chsh failure (got: $_ls_msg)" ;; esac

# The OTHER no-op outcome: chsh is absent entirely (a distro without `shadow`). The login
# shell is just as unchanged as in the failure branch above, but this one announced itself
# with blib_say — blue `::` on STDOUT — so it read as a status line rather than a problem.
# The block above cannot cover it: its shim PATH always contains a chsh, and it merges
# stdout into stderr with 2>&1, so it could neither reach this branch nor tell the streams
# apart if it did. Hence a separate fixture, with the streams kept SEPARATE.
#
# PATH is the bindir ALONE — adding /usr/bin:/bin would find the system chsh and silently
# test the wrong branch. So every binary the function reaches for is shimmed or linked in.
_lsn_bin="$(mktemp -d "$SANDBOX/lsnbin.XXXXXX")"
printf '#!/bin/sh\nexit 0\n' >"$_lsn_bin/zsh"; chmod +x "$_lsn_bin/zsh"
printf '#!/bin/sh\necho "u:x:1:1::/home/u:/bin/sh"\n' >"$_lsn_bin/getent"; chmod +x "$_lsn_bin/getent"
# grep exits 0 = "$zsh_path is already listed in /etc/shells", so the privileged tee append
# is skipped and this stays a pure no-privilege test.
printf '#!/bin/sh\nexit 0\n' >"$_lsn_bin/grep"; chmod +x "$_lsn_bin/grep"
for _b in id cut awk printf; do [[ -x "$_lsn_bin/$_b" ]] || ln -sf "$(command -v "$_b")" "$_lsn_bin/$_b" 2>/dev/null; done
PATH="$_lsn_bin" BLIB_SU="" BLIB_DRY=0 BLIB_ONLY="" BLIB_SKIP="" \
  blib_set_login_shell >"$SANDBOX/lsn.out" 2>"$SANDBOX/lsn.err" || true
if grep -q "chsh not found" "$SANDBOX/lsn.err"; then
  pass "blib_set_login_shell warns on STDERR when chsh is absent"
else
  fail "blib_set_login_shell did not warn on stderr when chsh is absent (got: $(tr '\n' ' ' <"$SANDBOX/lsn.err"))"
fi
if grep -q "chsh not found" "$SANDBOX/lsn.out"; then
  fail "'chsh not found' is on STDOUT (blib_say regression — the shell was NOT changed, it must warn)"
else
  pass "'chsh not found' is NOT on stdout (no longer a blib_say status line)"
fi

# ── core_files_identical: the comparison that must not need diffutils ─────────
# sync-core.sh and update-nvim-plugins.sh both asked "did that rewrite change anything"
# with `cmp -s`, which needs diffutils. On a box without it, `command not found` is a
# non-zero exit indistinguishable from "differs", so sync-core.sh counted every candidate
# workflow as repointed (#572) and update-nvim-plugins.sh reported drift that did not
# exist. Both now call core_files_identical, so pin both directions AND the property that
# made the old shape fail: it must not depend on any binary outside git.
_cfi="$(mktemp -d "$SANDBOX/cfi.XXXXXX")"
printf 'alpha\nbeta\n' >"$_cfi/a"
printf 'alpha\nbeta\n' >"$_cfi/b"
printf 'alpha\nGAMMA\n' >"$_cfi/c"
printf 'alpha\nbeta' >"$_cfi/d" # same bytes as a, minus the trailing newline

if core_files_identical "$_cfi/a" "$_cfi/b"; then
  pass "core_files_identical: identical files compare equal"
else
  fail "core_files_identical: identical files reported as differing"
fi
if core_files_identical "$_cfi/a" "$_cfi/c"; then
  fail "core_files_identical: differing files reported as equal"
else
  pass "core_files_identical: differing files compare unequal"
fi
# The trailing-newline case is why this is a hash of the bytes and not `[[ $(cat a) == $(cat b) ]]`:
# command substitution strips trailing newlines from BOTH sides, so a real one-byte
# difference would compare equal and the rewrite would be skipped.
if core_files_identical "$_cfi/a" "$_cfi/d"; then
  fail "core_files_identical: a trailing-newline-only difference was missed (\$(cat) semantics leaked in)"
else
  pass "core_files_identical: a trailing-newline-only difference still counts as different"
fi
# A missing operand must read as "differs", so a caller that lost its temp file rewrites
# rather than silently skipping.
if core_files_identical "$_cfi/a" "$_cfi/nope"; then
  fail "core_files_identical: a missing operand compared equal"
else
  pass "core_files_identical: a missing operand counts as different"
fi
# The regression itself: with diffutils absent it must still be correct. Run it with a
# PATH holding only git, so any reintroduced cmp/diff call fails the way it did in #572.
_cfi_git="$(command -v git)"
_cfi_bin="$(mktemp -d "$SANDBOX/cfibin.XXXXXX")"
ln -s "$_cfi_git" "$_cfi_bin/git"
if PATH="$_cfi_bin" core_files_identical "$_cfi/a" "$_cfi/b" &&
  ! PATH="$_cfi_bin" core_files_identical "$_cfi/a" "$_cfi/c"; then
  pass "core_files_identical: correct on a PATH with git but no cmp/diff (the #572 box)"
else
  fail "core_files_identical: wrong answer without diffutils on PATH — the #572 regression is back"
fi
# And no caller may quietly go back to cmp — OR to diff, which is the same hole one step
# over: both ship in diffutils, so a box without it (the Arch CI container) has neither.
# Banning only `cmp` is what let a `diff <(…) <(…)` into this very file and red audit-arch
# while every local gate was green.
#
# `git diff` MUST be exempt — git is the one tool these scripts already cannot run without,
# which is why core_files_identical is built on git hash-object. Getting that exemption
# right is the whole difficulty, and the first attempt got it wrong: it enumerated the
# invocation forms it could think of (`git diff`, `git --no-pager diff`) and so false-fired
# on sync-core.sh's `git -C "$path" diff --cached`, reddening four CI legs on correct code.
#
# So the exemption is now structural rather than a list of spellings: `diff` is a git
# SUBCOMMAND if a `git` invocation precedes it in the same pipeline stage. `[^|;&]*` is what
# scopes it to that stage — it stops at a pipe, so `git log | diff -u - x` is still caught.
# _diffutils_hits is a function purely so the fixtures below can test BOTH directions; a
# gate whose exemption is untested is how the last one shipped broken.
_diffutils_hits() { # _diffutils_hits <file>… — print offending "file:line:text"
  # The comment filter must skip grep's "file:line:" PREFIX before looking for the #.
  # The original gate used `grep -v "^\s*#"` against this same prefixed stream, so it
  # never stripped a single comment — latent only because no commented `cmp -` existed.
  # -H as well as -n: grep OMITS the filename when handed a single file, so the output
  # format would change between the multi-file tree scan and a one-file fixture call — and
  # the comment filter below, which skips past "file:line:", would then miss the "#".
  grep -nHE '(^|[|;&( ])(cmp|diff)[[:space:]]+-' "$@" 2>/dev/null |
    grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' |
    grep -vE 'git[^|;&]*[[:space:]]diff[[:space:]]' || true
}
# Fixtures first: prove the matcher catches a real call and the exemption spares every git
# form actually used in this repo, before trusting its verdict on the tree.
_du_fx="$(mktemp -d "$SANDBOX/diffutils.XXXXXX")"
# The offending literals are ASSEMBLED, never written out, because this fixture lives inside
# a file the gate itself scans — spelled directly, test-core.sh would flag its own test data
# and the only fixes would be to stop scanning the very file that carried the real bug, or to
# stop testing the gate. (Same reason the pipefail scanner has a "does not flag its own
# definition" case.)
_du_d=diff _du_c=cmp
{
  printf 'if %s -u "$a" "$b" >/dev/null; then echo same; fi\n' "$_du_d"
  printf '%s -s "$a" "$b" && echo identical\n' "$_du_c"
  printf 'git log --oneline | %s -u - expected.txt\n' "$_du_d"
} >"$_du_fx/bad.sh"
cat >"$_du_fx/good.sh" <<'DUGOOD'
if git diff --quiet HEAD -- "$f"; then echo clean; fi
git --no-pager diff --no-index -- "$a" "$b"
git -C "$path" diff --cached --quiet
git -C "$path" diff --cached --quiet -- core
DUGOOD
# The commented-out call goes in the same assembled way, for the same reason.
printf '# %s -u is fine in a comment\n' "$_du_d" >>"$_du_fx/good.sh"
_du_bad="$(_diffutils_hits "$_du_fx/bad.sh" | wc -l | tr -d ' ')"
_du_good="$(_diffutils_hits "$_du_fx/good.sh" | wc -l | tr -d ' ')"
if [[ "$_du_bad" == 3 ]]; then
  pass "diffutils gate: catches diff, cmp, and a diff piped from git (3/3)"
else
  fail "diffutils gate: missed a real cmp/diff call (found $_du_bad of 3)"
fi
if [[ "$_du_good" == 0 ]]; then
  pass "diffutils gate: every git-subcommand form and a comment are exempt (no false fires)"
else
  fail "diffutils gate: false-fired on a legitimate git diff — $(_diffutils_hits "$_du_fx/good.sh" | tr '\n' ' ')"
fi
if _diffutils_hits "$HERE/scripts"/*.sh "$HERE/scripts/lib"/*.sh | grep -q .; then
  fail "a script calls cmp/diff again — use core_files_identical (#572)"
else
  pass "no script calls cmp (diffutils stays optional)"
fi

# ── _core_gitleaks_policy_hits: the secret-scan policy matcher (#623) ────────
# The gate audit-core.sh §5g rests on. Fixture-driven in BOTH directions before it is
# trusted on the real fleet, for the reason the diffutils gate above states outright: a gate
# whose exemption is untested is how the last one shipped broken.
#
# THE TRAP THIS PINS, and it cost real time while surveying for the issue: a naive
# `-c|--config` match also fires on the `-c` inside `--exit-code`, which two of the repos in
# scope actually pass. An invocation carrying `--exit-code` and NO config must still be a
# finding — that is case 2 below, and it is the whole reason the flag is matched as a word.
#
# The offending strings are ASSEMBLED with printf rather than spelled out, the same technique
# _core_owned_block_hits uses for its own self-reference problem: this repo scans itself, and
# a literal config-less invocation written here would be a finding in Core's own tree.
hdr "_core_gitleaks_policy_hits (secret-scan policy)"
_gph="$(mktemp -d "$SANDBOX/gpolicy.XXXXXX")"
_gp_w() { printf '%s\n' "$2" >"$_gph/$1"; } # _gp_w <file> <line>
_gp_is() {                                  # _gp_is <label> <file> <expected>
  local got
  got="$(_core_gitleaks_policy_hits "$_gph/$2")"
  if [[ "$got" == "$3" ]]; then
    pass "gitleaks policy: $1"
  else
    fail "gitleaks policy: $1 (want '$3', got '$got')"
  fi
}

_gp_scan="$(printf 'gitleaks %s' dir)"       # assembled: this file is scanned too
_gp_det="$(printf 'gitleaks %s' detect)"
_gp_hist="$(printf 'gitleaks %s' git)"

# FINDINGS — a scan running under whatever rule set gitleaks happens to pick up.
_gp_w a.mk "$_gp_scan . --no-banner --redact"
_gp_is "a config-less 'dir' scan is a finding" a.mk "1:no-config"
_gp_w b.mk "$_gp_hist --redact"
_gp_is "a config-less history scan is a finding" b.mk "1:no-config"
# THE --exit-code TRAP: contains the substring '-c', carries no policy, must still fire.
_gp_w c.mk "$_gp_det --no-git --redact --verbose --exit-code 1"
_gp_is "--exit-code does NOT read as -c (the false-positive trap this rule is built around)" c.mk "1:no-config"

# NOT FINDINGS — a policy is passed, in any of the spellings the fleet actually uses.
_gp_w d.mk "$_gp_scan . -c core/gitleaks.toml --no-banner --redact"
_gp_is "-c with Core's policy is clean" d.mk ""
_gp_w e.mk "$_gp_det --config core/gitleaks.toml --redact --exit-code 1"
_gp_is "--config alongside --exit-code is clean (both directions of the trap)" e.mk ""
_gp_w f.mk "$_gp_scan . --config=.gitleaks.toml --redact"
_gp_is "the --config=VALUE spelling is clean" f.mk ""
_gp_w g.mk "$_gp_scan . -c \"\$GITLEAKS_CONFIG\" --no-banner --redact -v"
_gp_is "a config passed through a variable is clean" g.mk ""

# NOT INVOCATIONS AT ALL — the discipline that keeps the gate switched on.
_gp_w h.mk "# $_gp_scan . --no-banner   (a comment describing the call)"
_gp_is "a commented-out invocation is not a finding" h.mk ""
_gp_w i.mk 'command -v gitleaks >/dev/null 2>&1 || { echo "gitleaks not installed"; exit 0; }'
_gp_is "a presence check that merely names gitleaks is not a finding" i.mk ""
_gp_w j.mk 'gitleaks version'
_gp_is "a non-scanning subcommand is not a finding" j.mk ""

# Core's OWN consumers must be clean, or §5g would be asking the fleet for something Core
# does not do itself — the same inverse property the owned-block scan asserts.
_gp_core_ok=1
for _gpf in "$HERE/audit-core.sh" "$HERE/scripts/audit-core.sh" "$HERE/Makefile"; do
  [[ -f "$_gpf" ]] || continue
  [[ -z "$(_core_gitleaks_policy_hits "$_gpf")" ]] || _gp_core_ok=0
done
if (( _gp_core_ok )); then
  pass "gitleaks policy: Core's own gitleaks calls all pass a config (Core meets the rule it sets)"
else
  fail "gitleaks policy: Core itself runs gitleaks with no config — the rule §5g applies to the fleet"
fi
unset _gp_scan _gp_det _gp_hist _gp_core_ok _gpf _gph
unset -f _gp_w _gp_is

# ── summary ───────────────────────────────────────────────────────────────────
summary
((FAIL == 0)) || {
  { [[ "$NESTED" == 1 ]] || ((JSON)); } || printf '%stests FAILED%s\n' "$c_red" "$c_rst" >&2
  exit 1
}
{ [[ "$NESTED" == 1 ]] || ((JSON)); } || printf '%stests OK%s\n' "$c_grn" "$c_rst"
