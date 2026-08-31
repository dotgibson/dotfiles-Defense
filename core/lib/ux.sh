# shellcheck shell=bash
# core/lib/ux.sh — shared BASH terminal-UX primitives (B5).
# ──────────────────────────────────────────────────────────────────────────────
# ONE definition of the colour palette, the UTF-8→ASCII glyph fallback, and the
# spinner for the bash layer — so the dev-tooling gates (scripts/lib/common.sh) and
# each OS repo's pre-shell installer (bootstrap.sh) stop hand-rolling their own copies
# that drift. zsh/05-ui.zsh is the zsh-runtime counterpart of this file; this is its bash
# sibling, and unlike common.sh it IS vendored into every OS repo (it's in core.manifest)
# precisely so bootstrap.sh — which runs before any zsh config and so cannot source
# 05-ui.zsh — can `source core/lib/ux.sh` instead of duplicating ~80 lines.
#
# SOURCED, not run: no shebang, mode 100644 (the audit's exec-bit section asserts this for
# lib/*.sh, the bash sibling of the sourced zsh/*.zsh modules). bash 3.2-safe (macOS): no
# associative arrays, no mapfile, no ${x,,}.
#
# Usage:
#   source "<path>/core/lib/ux.sh"
#   ux_palette; ux_glyphs            # already called at source time; re-call after a flag
#   ux_spin "installing" some-cmd …  # spinner that returns the command's exit status
# ──────────────────────────────────────────────────────────────────────────────

# UX_* are a PALETTE/GLYPH API consumed by sourcers (common.sh, bootstrap.sh), so several
# look unused from inside this file — that's expected for a sourced lib.
# shellcheck disable=SC2034
[[ -n "${_CORE_UX_SH:-}" ]] && return 0
_CORE_UX_SH=1

# ── palette ───────────────────────────────────────────────────────────────────
# Colour ON only when stdout is a TTY (or CLICOLOR_FORCE) and NO_COLOR is unset
# (https://no-color.org), gated by UX_COLOR (auto|always|never) so a `--color WHEN` flag
# can re-evaluate it. Identical rule to scripts/lib/common.sh and zsh/05-ui.zsh — now in ONE
# place. Re-callable: change UX_COLOR / the env, call ux_palette again.
: "${UX_COLOR:=auto}"
ux_palette() {
  local on=0
  case "${UX_COLOR:-auto}" in
  always) on=1 ;;
  never) on=0 ;;
  *) { [[ -t 1 || -n "${CLICOLOR_FORCE:-}" ]]; } && on=1 ;;
  esac
  [[ -n "${NO_COLOR:-}" ]] && on=0
  if ((on)); then
    UX_GRN=$'\e[32m' UX_YEL=$'\e[33m' UX_RED=$'\e[31m' UX_BLU=$'\e[34m' UX_DIM=$'\e[2;37m' UX_RST=$'\e[0m'
    # Branded accent + muted grey, the ONE place $COLORTERM is interpreted for the bash
    # layer: a truecolor token when the terminal advertises 24-bit, else a 256-colour
    # approximation — the same "degrade, don't assume" tiering zsh/05-ui.zsh applies, now
    # mirrored here so bootstrap.sh's accent (the first thing seen on a new box) matches
    # the steady-state prompt instead of flat 16-colour (U5).
    # The two tiers themselves are GENERATED from theme/palette.toml; the
    # dispatch above is not. make gen-theme.
    # core:theme:gen ux-accent-tiers
    case "${COLORTERM:-}" in
    24bit | truecolor) UX_ACCENT=$'\e[1;38;2;122;162;247m' UX_MUTED=$'\e[38;2;86;95;137m' ;;
    *) UX_ACCENT=$'\e[1;38;5;111m' UX_MUTED=$'\e[38;5;103m' ;;
    esac
    # core:theme:end ux-accent-tiers
  else
    UX_GRN='' UX_YEL='' UX_RED='' UX_BLU='' UX_DIM='' UX_RST=''
    UX_ACCENT='' UX_MUTED=''
  fi
}
ux_palette

# ── glyphs ────────────────────────────────────────────────────────────────────
# Degrade to ASCII when the locale is NOT UTF-8 (a C/POSIX rescue shell renders the
# braille spinner + ✓/✗ marks as mojibake otherwise) — the same rule as zsh/05-ui.zsh and
# bootstrap.sh. bash 3.2-safe lowercasing via tr (no ${x,,}). UX_SPIN_FRAMES is a STRING
# of single-width frames, indexed per-char by ux_spin.
ux_glyphs() {
  local lc
  lc="$(printf '%s' "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" | tr '[:upper:]' '[:lower:]')"
  case "$lc" in
  *utf-8* | *utf8*) UX_OK='✓' UX_ERR='✗' UX_WARN='⚠' UX_INFO='•' UX_SPIN_FRAMES='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' ;;
  *) UX_OK='ok' UX_ERR='x' UX_WARN='!' UX_INFO='-' UX_SPIN_FRAMES='-\|/' ;;
  esac
}
ux_glyphs

ux_have() { command -v "$1" >/dev/null 2>&1; }

# ── messages ──────────────────────────────────────────────────────────────────
# ux_wrap <width> <text...> — echo TEXT hard-wrapped at WORD boundaries to WIDTH
# columns, one wrapped line per output line. Pure bash (no fold(1) — runs on a bare
# box / busybox), bash 3.2-safe. WIDTH <= 0 means "width unknown → don't wrap" (emit
# one line), the same rule zsh/05-ui.zsh's _core_hint uses for a non-TTY COLUMNS of 0.
# noglob is toggled around the deliberate word-split so a `*` in the text can't expand.
ux_wrap() {
  local width="$1"
  shift
  if ((width <= 0)); then
    printf '%s\n' "$*"
    return 0
  fi
  local cur='' word _reglob=0
  case $- in *f*) ;; *) _reglob=1 ;; esac
  set -f
  # Word-split is the POINT here (wrap operates on individual words); noglob is on, so
  # an unquoted $* is safe — silence the quote-it advice that doesn't apply.
  # shellcheck disable=SC2048,SC2086
  for word in $*; do
    if [[ -z "$cur" ]]; then
      cur="$word"
    elif ((${#cur} + 1 + ${#word} <= width)); then
      cur="$cur $word"
    else
      printf '%s\n' "$cur"
      cur="$word"
    fi
  done
  ((_reglob)) && set +f
  [[ -n "$cur" ]] && printf '%s\n' "$cur"
  return 0
}

# ux_hint <text...> — dim follow-up "→" line on stderr (the fix-it after a skip/warn),
# word-wrapped to $COLUMNS so a long hint doesn't hard-wrap mid-word in a narrow tmux
# split. The bash sibling of zsh/05-ui.zsh's _core_hint; the indent aligns under the text.
ux_hint() {
  local prefix='→ ' indent='  ' width="${COLUMNS:-0}"
  ((width > 0 && width < 24)) && width=24 # floor: never collapse into useless slivers
  local first=1 line
  while IFS= read -r line; do
    if ((first)); then
      printf '%s%s%s%s\n' "$UX_DIM" "$prefix" "$line" "$UX_RST" >&2
      first=0
    else
      printf '%s%s%s%s\n' "$UX_DIM" "$indent" "$line" "$UX_RST" >&2
    fi
  done < <(ux_wrap "$((width > 0 ? width - 2 : 0))" "$*")
}

# ux_errbox <headline> [body...] — multi-line error BLOCK on stderr: a red headline,
# then dim indented body lines (why / fix / docs). The bash sibling of zsh/05-ui.zsh's
# _core_errbox, reserved for the few highest-friction failures (no brew, core/ missing)
# where the extra layout earns its space; single-line errors stay on a plain printf (U12).
ux_errbox() {
  local head="$1"
  shift
  printf '%s%s%s %s\n' "$UX_RED" "$UX_ERR" "$UX_RST" "$head" >&2
  local l
  for l in "$@"; do printf '%s    %s%s\n' "$UX_DIM" "$l" "$UX_RST" >&2; done
}

# ── spinner ───────────────────────────────────────────────────────────────────
# ux_spin <label> <cmd...> — run an opaque long step with a live spinner, returning the
# command's own exit status. Output is captured and shown ONLY on failure (a clean run
# stays quiet). On a non-TTY (CI, piped) it runs the command with output passing through
# and emits a scannable done/failed marker, so logs read as discrete steps. A Ctrl-C
# forwards SIGINT to the child, reaps it, restores the cursor, and returns 130 — the
# caller's own trap (e.g. bootstrap's on_interrupt) then takes over. Mirrors zsh/05-ui.zsh's
# _core_spin so the bash + zsh layers behave identically.
ux_spin() {
  local label="$1"
  shift
  (($#)) || return 0
  # No TTY → run plainly, mark the outcome WITH the elapsed time so a slow step is
  # diagnosable from a CI/piped log, not just a bare done marker (U10). We can't use a
  # `local SECONDS` reset here — bash (unlike zsh) drops SECONDS' auto-increment magic
  # once it's localised — so delta against the global SECONDS, which we only READ.
  if [[ ! -t 1 ]]; then
    printf '  %s%s%s %s…\n' "$UX_YEL" "$UX_INFO" "$UX_RST" "$label"
    local rc=0 _t0=$SECONDS _el
    "$@" || rc=$?
    _el=$((SECONDS - _t0))
    if ((rc == 0)); then printf '  %s%s%s %s %s(%ds)%s\n' "$UX_GRN" "$UX_OK" "$UX_RST" "$label" "$UX_DIM" "$_el" "$UX_RST"
    else printf '  %s%s%s %s — failed (exit %d, %ds)\n' "$UX_RED" "$UX_ERR" "$UX_RST" "$label" "$rc" "$_el" >&2; fi
    return "$rc"
  fi
  local out rc
  out="$(mktemp -t ux-spin.XXXXXX)" || {
    "$@"
    return $?
  }
  "$@" >"$out" 2>&1 &
  local pid=$! frames="$UX_SPIN_FRAMES" i=0 _t0=$SECONDS _el
  # Forward a signal to the child, reap it, restore the cursor, then return 130. SAVE the
  # caller's existing traps first and RESTORE them after (not a blind `trap - …`), so a
  # caller with its own handler (e.g. bootstrap's on_interrupt) keeps it — the spinner
  # composes with an app-level trap instead of silently clearing it. We trap BOTH INT and
  # TERM: TERM matters for CI cancellation — a SIGTERM mid-spin would otherwise orphan the
  # child AND leave the cursor hidden (this lib only handled INT, while bootstrap's own
  # spin() already handled both; now the bash sibling matches) (U11).
  local _prev_int _prev_term
  _prev_int="$(trap -p INT)"
  _prev_term="$(trap -p TERM)"
  trap 'kill -INT  "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; printf "\e[?25h"; return 130' INT
  trap 'kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; printf "\e[?25h"; return 130' TERM
  printf '\e[?25l' # hide cursor while spinning
  # Elapsed-time readout in the frame so a long step reads as PROGRESS, not a hang (U1).
  # Delta against the (read-only) global SECONDS — a localised SECONDS loses its magic in bash.
  # Same busy-spin guard as zsh/05-ui.zsh's _core_spin (these two are deliberate mirrors).
  # `sleep 0.1` is the only thing pacing this loop, and a `sleep` that is absent, non-numeric
  # (some minimal/BusyBox builds reject fractional seconds), or otherwise failing returns
  # instantly — turning a 100ms tick into an unthrottled spin that pegs a core for the whole
  # run. The animation is cosmetic and `wait` is what matters, so stop ANIMATING and fall
  # through to the blocking wait: no CPU, same exit status. 200 iterations inside 5s cannot
  # happen with a working tick (that would take ~20s), so a slow command never trips it.
  # Both statements in the loop body are NORMALISED (`|| :`) because this file is SOURCED by
  # callers running `set -euo pipefail` — bootstrap.sh is one — so a bare command that fails
  # kills the caller outright. That is not hypothetical: with a `sleep` that exits non-zero,
  # an unnormalised `sleep 0.1` aborts the whole shell at exit 127 BEFORE `_spins` is ever
  # incremented, so the guard below can never run, the wrapped child is left running, and the
  # cursor stays hidden. Verified under a pty: SHELL_EXIT=127, no UX_RC, no end marker.
  # Normalising is also what lets a failing tick reach the guard rather than abort. stderr is
  # dropped so a missing `sleep` cannot emit 200 "command not found" lines on the way there.
  # (The printf gets the same treatment: this animation is decoration, and decoration must
  # never take down its caller — a closed or dead terminal makes it fail the same way.)
  #
  # EVERY statement after the loop is normalised for the same reason, not just the loop body.
  # The argument does not stop at `done`: a bare printf that fails at the cursor-restore line
  # below aborts the caller with the cursor still HIDDEN and the child still RUNNING — the
  # identical end state described above for the unnormalised `sleep`. A bare printf (or `sed`)
  # in the result branches aborts between `wait` and `rm -f "$out"`, leaking the mktemp file.
  # `rc` is captured and returned explicitly, so `|| :` never changes what the caller sees.
  local _spins=0 _degraded=0
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r  %s%s%s %s %s(%ds)%s' "$UX_YEL" "${frames:i++%${#frames}:1}" "$UX_RST" "$label" "$UX_DIM" "$((SECONDS - _t0))" "$UX_RST" 2>/dev/null || :
    sleep 0.1 2>/dev/null || :
    _spins=$((_spins + 1))
    if ((_spins > 200 && SECONDS - _t0 < 5)); then _degraded=1; break; fi
  done
  printf '\e[?25h\r\033[K' 2>/dev/null || : # restore cursor, column 0, clear line
  # A tripped busy-spin guard means there are no more frames for the REST of the run, which
  # can be minutes. Clearing the line and going straight to `wait` would show nothing at all
  # for that whole time — indistinguishable from the hang the elapsed-time readout exists to
  # rule out (U1), and the very failure mode the guard is trying to survive gracefully. Leave
  # ONE static frame behind instead. The wording, not the glyph, is what does the work: a
  # frozen spinner still reads as "wedged", "(still running…)" reads as "the animation gave
  # up, the command did not". _core_spin's mirror of this leaves the same line. The glyph
  # comes from $frames — NOT a hardcoded braille cell — so the non-UTF-8 fallback set
  # (UX_SPIN_FRAMES='-\|/') is honoured instead of printing mojibake on such a terminal.
  # `if`, not `((_degraded)) && { … }`: an arithmetic test that evaluates to 0 RETURNS 1, so
  # the &&-list as a whole fails on the common (non-degraded) path. Bash's set -e exempts
  # &&-lists, so it does survive — but relying on that here, in the one function whose entire
  # contract is "never take down a `set -e` caller", is the wrong place to be clever.
  if ((_degraded)); then
    printf '  %s%s%s %s %s(still running…)%s' "$UX_YEL" "${frames:0:1}" "$UX_RST" "$label" "$UX_DIM" "$UX_RST" 2>/dev/null || :
  fi
  eval "${_prev_int:-trap - INT}"    # restore the caller's prior INT trap (or clear if none)
  eval "${_prev_term:-trap - TERM}"  # ditto for TERM
  _el=$((SECONDS - _t0))
  # Both result frames lead with \r\033[K so they overwrite the static frame above when the
  # guard fired (and are a harmless no-op at column 0 when it did not).
  if wait "$pid"; then
    rc=0
    printf '\r\033[K  %s%s%s %s %s(%ds)%s\n' "$UX_GRN" "$UX_OK" "$UX_RST" "$label" "$UX_DIM" "$_el" "$UX_RST" 2>/dev/null || :
  else
    rc=$?
    printf '\r\033[K  %s%s%s %s — failed (exit %d, %ds)\n' "$UX_RED" "$UX_ERR" "$UX_RST" "$label" "$rc" "$_el" >&2 || :
    sed 's/^/    /' "$out" >&2 || :
  fi
  rm -f "$out" || :
  return "$rc"
}
