# core/zsh/05-ui.zsh
# ──────────────────────────────────────────────────────────────────────────────
# Shared terminal-UX primitives for Core's interactive commands — one consistent
# voice for errors, hints, confirms, and progress, so 30-functions.zsh / 50-op.zsh /
# 60-update.zsh / 55-maint.zsh / 45-plugins.zsh stop hand-rolling ad-hoc `echo "Usage: …"`
# lines. The dev-tooling scripts already have this polish (scripts/lib/common.sh);
# this is its runtime, end-user counterpart.
#
# gum-aware, with a plain fallback on every helper, so a bare box (fresh server,
# rescue shell) degrades to readable text instead of erroring. gum is detected
# live (`command -v`), NOT via 00-tools.zsh's HAVE_GUM — these helpers must also work
# under the function unit tests, which source this file ALONE in a `zsh -fc`.
#
# LOAD ORDER: source EARLY, right after 00-tools.zsh — every later module may call it.
# Deliberately NOT interactivity-guarded (no `[[ $- == *i* ]] || return`): it only
# DEFINES functions, and the unit tests source it non-interactively.
# ──────────────────────────────────────────────────────────────────────────────

# Palette. Colour is applied only when stderr is a TTY and NO_COLOR is unset, so
# captured/piped output (the unit tests grep stderr) stays plain. Glyphs match the
# repo's existing ✓/–/✗ idiom (scripts/lib/common.sh, the 60-update.zsh nudge).
typeset -g _CORE_C_RED=$'\e[31m' _CORE_C_YEL=$'\e[33m' _CORE_C_GRN=$'\e[32m'
typeset -g _CORE_C_DIM=$'\e[2;37m' _CORE_C_RST=$'\e[0m'

# Canonical accent palette — the ONE place $COLORTERM is interpreted for Core's
# branded blue accent + muted grey. Two forms, because Core renders colour two ways:
# raw ANSI escapes (core-help / core-doctor) and prompt `%F{…}` specs (the update
# nudge / welcome). Truecolor tokens when the terminal advertises 24-bit, else a
# 256-colour approximation — the same "degrade, don't assume" rule as NO_COLOR. This
# replaces the per-module COLORTERM blocks that 60-update.zsh and 30-functions.zsh each
# hand-rolled (they now consume these), so the accent has one definition, not three.
if [[ "${COLORTERM:-}" == (24bit|truecolor) ]]; then
  typeset -g _CORE_C_ACCENT=$'\e[1;38;2;122;162;247m' _CORE_C_MUTED=$'\e[38;2;86;95;137m'
  typeset -g _CORE_ACCENT_SPEC='#7aa2f7' _CORE_MUTED_SPEC='#565f89'
else
  typeset -g _CORE_C_ACCENT=$'\e[1;38;5;111m' _CORE_C_MUTED=$'\e[38;5;103m'
  typeset -g _CORE_ACCENT_SPEC=75 _CORE_MUTED_SPEC=244
fi

# Glyphs + spinner frames degrade to ASCII when the locale is NOT UTF-8 (no *utf8*/*utf-8*
# in LC_ALL/LC_CTYPE/LANG). A C/POSIX-locale terminal — a fresh server, a rescue shell, a
# serial console: the exact bare box this layer targets — renders the braille spinner and
# the ✓/✗/⚠ marks as mojibake boxes otherwise. One definition, consumed by every helper
# below, so the fallback is consistent across ok/err/warn/errbox/spin.
if [[ "${${LC_ALL:-${LC_CTYPE:-${LANG:-}}}:l}" == *utf(-|)8* ]]; then
  typeset -g _CORE_G_OK='✓' _CORE_G_ERR='✗' _CORE_G_WARN='⚠'
  typeset -ga _CORE_SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
else
  typeset -g _CORE_G_OK='ok' _CORE_G_ERR='x' _CORE_G_WARN='!'
  typeset -ga _CORE_SPIN_FRAMES=('-' '\' '|' '/')
fi

_core_have() { command -v "$1" >/dev/null 2>&1; }
# Colourise fd $1 (default 2 = stderr)? The fd must be a terminal AND NO_COLOR
# unset (https://no-color.org). Each helper asks about the stream it ACTUALLY
# writes to — _core_ok (stdout) passes 1, the stderr helpers use the default 2 —
# so `cmd | cat` (stdout piped, stderr still a TTY) never leaks colour into the pipe.
_core_color() { [[ -t ${1:-2} && -z ${NO_COLOR:-} ]]; }

# ── messages ──────────────────────────────────────────────────────────────────
# err/warn/hint/usage go to STDERR (diagnostics, never pollute a captured stdout);
# ok goes to STDOUT (it's a result). None of them exits — a zsh helper that called
# `exit` would kill the user's interactive shell. Callers do `_core_err …; return 1`.
_core_ok() { # success line → stdout (so it checks fd 1, not fd 2)
  if _core_color 1; then print -r -- "${_CORE_C_GRN}${_CORE_G_OK}${_CORE_C_RST} $*"
  else print -r -- "${_CORE_G_OK} $*"; fi
}
_core_err() { # error line → stderr
  if _core_color; then print -u2 -r -- "${_CORE_C_RED}${_CORE_G_ERR}${_CORE_C_RST} $*"
  else print -u2 -r -- "${_CORE_G_ERR} $*"; fi
}
_core_warn() { # warning line → stderr
  if _core_color; then print -u2 -r -- "${_CORE_C_YEL}${_CORE_G_WARN}${_CORE_C_RST} $*"
  else print -u2 -r -- "${_CORE_G_WARN} $*"; fi
}
_core_hint() { # dim follow-up "hint:" line → stderr (the fix, after an error)
  # Word-wrap to $COLUMNS so a long fix-it hint (e.g. extract's supported-formats list)
  # doesn't overflow a narrow tmux split and hard-wrap mid-word. Pure zsh (no fold(1)
  # dependency — this runs on busybox too); continuation lines align under the text.
  emulate -L zsh
  local prefix='  hint: ' indent='        ' # indent width == prefix width (8)
  # Wrap only to a KNOWN terminal width. Non-interactive/piped zsh leaves COLUMNS at 0
  # (or unset) — treat that as "width unknown → don't wrap", so captured/logged hints
  # stay one line; a real narrow pane (small positive COLUMNS) wraps, floored so it
  # can't collapse into useless slivers.
  local width=${COLUMNS:-0}
  if ((width <= 0)); then width=10000
  elif ((width < 24)); then width=24; fi
  local avail=$((width - ${#prefix}))
  local -a words=(${=*}) lines=()
  local cur='' w
  for w in $words; do
    if [[ -z "$cur" ]]; then cur="$w"
    elif ((${#cur} + 1 + ${#w} <= avail)); then cur="$cur $w"
    else
      lines+=("$cur")
      cur="$w"
    fi
  done
  [[ -n "$cur" ]] && lines+=("$cur")
  ((${#lines})) || lines=('')
  local i body
  for ((i = 1; i <= ${#lines}; i++)); do
    ((i == 1)) && body="${prefix}${lines[i]}" || body="${indent}${lines[i]}"
    if _core_color; then print -u2 -r -- "${_CORE_C_DIM}${body}${_CORE_C_RST}"
    else print -u2 -r -- "$body"; fi
  done
}
_core_usage() { # "usage: …" → stderr, then a dim "see: core-help <verb>" footer (U5)
  local synopsis="$*"
  if _core_color; then print -u2 -r -- "${_CORE_C_DIM}usage:${_CORE_C_RST} $synopsis"
  else print -u2 -r -- "usage: $synopsis"; fi
  # Point a usage error at the discoverability surface — every Core verb prints `usage:`
  # on misuse but none pointed back at the cheat sheet, so a confused user had no next
  # step. Derive the verb from the synopsis's FIRST token (every caller passes
  # "<verb> …"), so callers need no change. `core-help <verb>` filters to that verb's
  # row. Suppress with CORE_USAGE_HINT=0 (e.g. an OS layer that finds it noisy).
  [[ "${CORE_USAGE_HINT:-1}" == 1 ]] || return 0
  local verb="${synopsis%%[ 	]*}"
  [[ -n "$verb" ]] || return 0
  if _core_color; then print -u2 -r -- "${_CORE_C_DIM}  see: core-help ${verb}${_CORE_C_RST}"
  else print -u2 -r -- "  see: core-help ${verb}"; fi
}

# _core_errbox <headline> [body line...]  → a multi-line error BLOCK on stderr for the
# few highest-friction failures (an unknown archive format, no package manager): a red
# headline, then dim indented body lines (why / fix / docs). Single-line errors stay on
# _core_err — this is reserved for the cases where the extra layout earns its space.
_core_errbox() {
  local head="$1"; shift
  if _core_color; then print -u2 -r -- "${_CORE_C_RED}${_CORE_G_ERR}${_CORE_C_RST} ${head}"
  else print -u2 -r -- "${_CORE_G_ERR} ${head}"; fi
  local l
  for l in "$@"; do
    if _core_color; then print -u2 -r -- "${_CORE_C_DIM}    ${l}${_CORE_C_RST}"
    else print -u2 -r -- "    ${l}"; fi
  done
}

# ── did-you-mean ───────────────────────────────────────────────────────────────
# _core_lev <a> <b>  → edit (Levenshtein) distance between two strings, on stdout.
# Inputs are command/flag names (a handful of chars), so the O(n·m) table is trivial.
# Pure zsh (1-based arrays under `emulate -L zsh`; scalar[i] yields the i-th char), so
# it runs on a bare box with no awk/python. Powers _core_suggest's "did you mean?".
# _core_lev <a> <b> [outvar]  → edit distance. With outvar, writes it into that variable
# (no subshell); without, prints on stdout. The outvar form lets _core_suggest score a
# whole candidate list without forking a command substitution per candidate.
_core_lev() {
  emulate -L zsh
  local a="$1" b="$2" outvar="$3"
  local -i la=${#a} lb=${#b} i j cost del ins sub trn m res
  if ((la == 0)); then
    res=$lb
  elif ((lb == 0)); then
    res=$la
  else
    # 1-based rows; index (k+1) holds column k (k = 0..lb). NOTE: array-element assignment
    # subscripts must NOT contain spaces (`prev[j+1]=`, not `prev[j + 1]=`) — with spaces
    # zsh parses the LHS as a glob word, not an assignment ("bad pattern: prev[j").
    #
    # Damerau/OSA, not plain Levenshtein: we ALSO score an adjacent transposition as ONE
    # edit (needs the row two back, prev2), so a finger-fumble like `gts`→`gst` or
    # `cmod`→`comd` is distance 1 — the single most common real typo class — instead of 2,
    # which _core_suggest's ≤2 cutoff would otherwise treat the same as two unrelated edits.
    local -a prev2 prev cur
    for ((j = 0; j <= lb; j++)); do prev[j+1]=$j; done
    for ((i = 1; i <= la; i++)); do
      cur[1]=$i
      for ((j = 1; j <= lb; j++)); do
        [[ "${a[i]}" == "${b[j]}" ]] && cost=0 || cost=1
        del=$((prev[j+1] + 1)); ins=$((cur[j] + 1)); sub=$((prev[j] + cost))
        m=$del; ((ins < m)) && m=$ins; ((sub < m)) && m=$sub
        # adjacent transposition: a[i] matches b[j-1] AND a[i-1] matches b[j].
        if ((i > 1 && j > 1)) && [[ "${a[i]}" == "${b[j-1]}" && "${a[i-1]}" == "${b[j]}" ]]; then
          trn=$((prev2[j-1] + 1)); ((trn < m)) && m=$trn
        fi
        cur[j+1]=$m
      done
      prev2=("${prev[@]}")
      prev=("${cur[@]}")
    done
    res=${prev[lb+1]}
  fi
  if [[ -n $outvar ]]; then
    : "${(P)outvar::=$res}"
  else
    print -r -- "$res"
  fi
}

# _core_suggest <input> <candidate...>  → echo the single CLOSEST candidate when it's a
# near miss (distance ≤ 2 AND < the input's length, so a 1-char typo doesn't "match"
# everything), else nothing. Callers do: s=$(_core_suggest bad a b c); [[ -n $s ]] && …
_core_suggest() {
  emulate -L zsh
  local input="$1"; shift
  local best="" c
  local -i d bestd=99
  for c in "$@"; do
    _core_lev "$input" "$c" d   # writes the distance into $d, no subshell
    ((d < bestd)) && { bestd=$d; best=$c; }
  done
  ((bestd <= 2 && bestd < ${#input})) && [[ -n "$best" ]] && print -r -- "$best"
}

# ── help ──────────────────────────────────────────────────────────────────────
# _core_wants_help <arg>  → true when arg is -h/--help. Lets every Core verb answer
# `cmd -h`/`cmd --help` uniformly. A help REQUEST is success, not misuse — so the
# verb returns 0 and prints to STDOUT (the _core_usage error path is stderr+return 1).
# This also fixes verbs where --help used to be mis-read as an operand (e.g. `up`
# treated it as not-`-y` and proceeded; `serve`/`extract` rejected it as a bad port/
# file): the guard short-circuits before any of that.
_core_wants_help() { [[ "$1" == (-h|--help) ]]; }
# _core_help <synopsis> [description line...]  → print a verb's help to STDOUT
# (so `cmd --help | less` works) using the same dim "usage:" idiom as _core_usage.
_core_help() {
  local synopsis="$1"
  shift
  if _core_color 1; then print -r -- "${_CORE_C_DIM}usage:${_CORE_C_RST} $synopsis"
  else print -r -- "usage: $synopsis"; fi
  # One indented line PER remaining arg, honouring the "description line..." contract
  # (callers pass a single line today, but this lets a verb give multi-line help).
  local d
  for d in "$@"; do print -r -- "  $d"; done
}

# ── paging ──────────────────────────────────────────────────────────────────────
# For the long, scannable verbs (core-help's full sheet, core-doctor -v) that can be
# taller than a tmux split. _core_page prints content, routing it through $PAGER ONLY
# when stdout is a real TTY and the content is taller than the window — so a pipe, a
# redirect, or the unit tests (all non-TTY) get a byte-identical unpaged print and never
# block on an interactive pager. Colour must be baked into <content> already: a caller
# pages by FORCING colour on (the renderer can't see a TTY through the pipe), the same
# trick scripts/lib/common.sh uses with CLICOLOR_FORCE. CORE_NO_PAGER=1 disables it.
_core_pager_cmd() { # → the pager command line on stdout, or non-zero when none/disabled
  [[ -n ${CORE_NO_PAGER:-} ]] && return 1
  local p="${PAGER:-less}"
  # Match on the COMMAND TOKEN, not the whole $PAGER string: a user may set
  # PAGER='bat -p' or PAGER='/usr/bin/bat --paging=always', so strip args first
  # (${p%% *}) THEN take the basename (:t). Matching ${p:t} on the full string would
  # miss those (':t' of "bat -p" is "bat -p"), letting bat still corrupt the output —
  # the exact case this guard exists to prevent.
  local cmd="${p%% *}"
  # less needs -R to render our ANSI; -F quits if it fits one screen (so a short sheet
  # doesn't trap you in the pager), -X doesn't clear the screen, -I case-folds search.
  #
  # U7: bat is a SYNTAX HIGHLIGHTER, not an ANSI-faithful pager. Our content is coloured
  # BEFORE paging (callers force colour on — the pager can't see a TTY through the pipe),
  # and bat re-highlights it: a green line comes back overlaid with bat's own white fg and
  # double-wrapped escapes (verified empirically). So a bat-based $PAGER is routed to less,
  # which preserves incoming ANSI with -R — fixing the prior behaviour where PAGER=bat ran
  # bare and corrupted the help/doctor sheet. (bat stays the right tool for fzf/file
  # previews, where IT does the colouring — just not for already-coloured text.)
  if [[ ${cmd:t} == (less|bat|batcat) ]]; then
    _core_have less && { print -r -- "less -FIRX"; return 0; }
  else
    _core_have "$cmd" && { print -r -- "$p"; return 0; }
  fi
  return 1
}
_core_page() { # _core_page <content>
  emulate -L zsh
  local content="$1" pager
  local -i nlines=${#${(f)content}}
  if [[ -t 1 ]] && ((nlines > LINES)) && pager="$(_core_pager_cmd)"; then
    print -r -- "$content" | ${=pager}
  else
    print -r -- "$content"
  fi
}

# ── confirm ───────────────────────────────────────────────────────────────────
# _core_confirm <prompt>  → 0 = yes, non-zero = no. Defensive by default: with no
# controlling TTY (a pipe, a cron job, a captured run) it DECLINES rather than
# blocking or assuming yes — so wrapping a destructive action in it is fail-safe.
# gum confirm when present (arrow-key UI); else a one-keystroke `read -q`. BOTH default
# to NO: gum's built-in default is the affirmative button, so `--default=false` is
# passed to match the `[y/N]` fallback — otherwise the same destructive prompt (please /
# up / extract-overwrite) would be one-Enter-to-confirm under gum and one-Enter-to-decline
# without it. Consistent safe default across both paths.
_core_confirm() {
  local prompt="${1:-Proceed?}"
  [[ -t 0 && -t 2 ]] || return 1 # no TTY → safe "no"
  if _core_have gum; then
    gum confirm --default=false "$prompt"
  else
    local reply
    read -q "reply?${prompt} [y/N] "
    local rc=$?
    print -u2 -- '' # newline after the single-char read
    return $rc
  fi
}

# ── input / choose ──────────────────────────────────────────────────────────────
# Companions to _core_confirm for the other two interactive reads — a free-text line and
# a one-of-N pick — so a Core verb (or an OS layer) gets arrow-key/edit UX where gum is
# present and a clean plain fallback where it isn't, instead of hand-rolling a bare `read`
# each time (U9). Same discipline as _core_confirm: no controlling TTY → return non-zero
# WITHOUT reading, so a piped/cron/captured context fails safe rather than blocking.

# _core_input <prompt> [--secret] [--placeholder TEXT]  → one line on STDOUT.
# gum input (cursor editing; --password masks) when present; else zsh `read` (`-s` masks).
_core_input() {
  emulate -L zsh
  local prompt="Value:" placeholder="" secret=0
  while (($#)); do
    case "$1" in
    --secret) secret=1 ;;
    --placeholder) placeholder="${2:-}"; shift ;;
    *) prompt="$1" ;;
    esac
    shift
  done
  [[ -t 0 && -t 2 ]] || return 1 # no TTY → fail safe, read nothing
  if _core_have gum; then
    if ((secret)); then gum input --password --prompt "$prompt "
    else gum input --prompt "$prompt " ${placeholder:+--placeholder "$placeholder"}; fi
    return
  fi
  local reply
  if ((secret)); then
    read -rs "reply?$prompt "
    print -u2 -- '' # newline after the silent read (the keystrokes weren't echoed)
  else
    read -r "reply?$prompt "
  fi
  print -r -- "$reply"
}

# _core_choose <item...>  → the chosen item on STDOUT, non-zero if nothing was picked.
# gum choose (arrow keys + type-to-filter) when present; else a numbered zsh `select` menu.
_core_choose() {
  emulate -L zsh
  (($#)) || return 1
  [[ -t 0 && -t 2 ]] || return 1
  if _core_have gum; then
    gum choose -- "$@"
    return
  fi
  local PS3="choose> " reply
  select reply in "$@"; do
    [[ -n "$reply" ]] && { print -r -- "$reply"; return 0; }
  done
  return 1
}

# ── progress ──────────────────────────────────────────────────────────────────
# _core_nap  → sleep ~100 ms for one spinner frame. Uses zsh's zselect (a builtin,
# no fork, and busybox-safe) when the module loads, falling back to fractional
# `sleep` otherwise — busybox `sleep` (Alpine, a named target) does NOT reliably
# accept a fractional argument, so the old literal `sleep 0.1` could error per frame
# on a bare box. Factored out so the delay primitive is unit-testable WITHOUT a TTY
# (the animated spin path needs one; this does not). Always returns 0.
_core_nap() {
  if zmodload -e zsh/zselect 2>/dev/null || zmodload zsh/zselect 2>/dev/null; then
    zselect -t 10 2>/dev/null # -t is in centiseconds → 10 = 100 ms
  else
    sleep 0.1 2>/dev/null
  fi
  return 0
}

# _core_spin <title> <cmd...>  → run cmd while showing a spinner; return cmd's
# exit code. Non-TTY → just runs it (no animation bytes in logs/pipes). gum spin
# when present; else a hand-rolled braille spinner. `nomonitor` silences the
# job-control "[1] <pid>" / "done" chatter the background job would otherwise emit.
_core_spin() {
  local title="$1"
  shift
  (($#)) || return 0
  if [[ ! -t 2 ]]; then "$@"; return; fi
  # gum spin runs its argument as an EXTERNAL process, so it CANNOT execute a zsh function
  # — callers legitimately pass one (e.g. 60-update.zsh's _pkgup_list_to), and gum would die
  # with `exec: "<fn>": executable file not found in $PATH`. Use gum only when the command
  # is a real binary/builtin; for a function, fall through to the hand-rolled spinner below,
  # which runs "$@" in-shell (a backgrounded function still resolves in the subshell).
  if _core_have gum && (( ! ${+functions[$1]} )); then
    gum spin --spinner dot --title "$title" --show-error -- "$@"
    return
  fi
  # localtraps scopes the INT trap below to THIS function; nomonitor silences the
  # job-control "[1] <pid>"/"done" chatter the background job would otherwise emit.
  setopt localoptions localtraps nomonitor
  local -a fr=("${_CORE_SPIN_FRAMES[@]}")
  local -i nfr=${#fr}
  # Colour honours NO_COLOR even though stderr is a TTY here (the cursor/erase escapes
  # below are control, not colour, so they always apply). Blank vars = plain output.
  local _g='' _r='' _d='' _x=''
  _core_color && { _g=$_CORE_C_GRN _r=$_CORE_C_RED _d=$_CORE_C_DIM _x=$_CORE_C_RST; }
  # Elapsed-time readout so a long step reads as PROGRESS, not a hang. SECONDS is
  # function-local under `emulate -L zsh` (set by the caller), so zero it here.
  local SECONDS=0
  printf '\e[?25l' >&2 # hide the cursor so it doesn't blink ON TOP of the glyph
  "$@" &
  local pid=$!
  # Ctrl-C during the spin would otherwise kill the loop mid-frame and leave a frozen
  # glyph + a HIDDEN cursor behind. Trap it: FORWARD the interrupt to the wrapped job
  # (SIGINT, not SIGTERM, so it actually stops a child that only handles ^C) and reap it
  # with `wait` before returning — so the work really halts instead of lingering in the
  # background — then clear the line, restore the cursor, and propagate as 130 (128+SIGINT).
  trap 'kill -INT "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; printf "\r\e[K\e[?25h" >&2; return 130' INT
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r%s %s %s(%ds)%s' "${fr[$((i % nfr + 1))]}" "$title" "$_d" "$SECONDS" "$_x" >&2
    _core_nap
    ((i++))
  done
  wait "$pid"
  local rc=$?
  # Replace the spinner with a STILL result frame — a green ✓ or red ✗ + the elapsed
  # time — so the line ends with a legible outcome instead of vanishing. Restore the
  # cursor either way. Colour follows the same stderr-TTY/NO_COLOR rule as the rest, via
  # the local _g/_r/_d/_x (blank when _core_color is false) — NOT the global constants.
  if ((rc == 0)); then
    printf '\r\e[K%s%s%s %s %s(%ds)%s\n' "$_g" "$_CORE_G_OK" "$_x" "$title" "$_d" "$SECONDS" "$_x" >&2
  else
    printf '\r\e[K%s%s%s %s %s(%ds, exit %d)%s\n' "$_r" "$_CORE_G_ERR" "$_x" "$title" "$_d" "$SECONDS" "$rc" "$_x" >&2
  fi
  printf '\e[?25h' >&2 # restore the cursor
  return $rc
}
