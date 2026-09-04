# core/zsh/55-maint.zsh
# ──────────────────────────────────────────────────────────────────────────────
# Control surface for the daily maintenance job (core/maint/dotfiles-maint.sh).
# Wires that script to whatever scheduler the box has, at a time you pick:
#   • Linux w/ systemd  → a `--user` systemd timer (Persistent: catches up if the
#                          machine was off at the scheduled time)
#   • macOS             → a launchd LaunchAgent (StartCalendarInterval)
#   • else (Alpine/Gentoo OpenRC, etc.) → a crontab line
#
#   maint-install [HH:MM]   install + enable (default 13:00)
#   maint-run               run it now, in the foreground
#   maint-log [N|-f]        show last N log lines (default 50), or follow
#   maint-status            when does it next run / is it enabled
#   maint-uninstall         remove the schedule
#
# LOAD ORDER: anywhere after tools; it only defines functions. (Pairs with
# 60-update.zsh — that's the per-shell nudge; this is the scheduled apply.)
# ──────────────────────────────────────────────────────────────────────────────

# Absolute path to the runner, resolved relative to THIS file (survives the
# core/ subtree living inside each OS repo). %x = path of the file being sourced.
typeset -g _MAINT_SH="${${(%):-%x}:A:h}/../maint/dotfiles-maint.sh"
_MAINT_SH="${_MAINT_SH:A}"
typeset -g _MAINT_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-maint/maint.log"

# _maint_scheduler — WHICH scheduler holds this box's daily run. The DISPATCHER, and it
# stays: switching on a capability rather than on an OS name is the correct cross-OS shape,
# and it is what ARCHITECTURE.md always said was right about this file. What changed in
# #665 is where the answer comes from — the OS layer declares it, and the probe below is
# what answers for a box that has not declared.
#
# THE PROBE SURVIVED #763, WHICH DELETED THE UNIT-DIRECTORY FALLBACK IT SITS BESIDE, and
# the difference is the point: `/run/systemd/system` and `crontab` are CAPABILITY probes —
# "what can this box run" — which is the shape PORTABILITY.md blesses everywhere. The
# directory that scheduler keeps its unit in was an OS-ABSOLUTE PATH, which is the shape
# Core may not carry at all. One is a probe; the other was OS knowledge. Only the second
# had to go.
_maint_scheduler() {
  emulate -L zsh
  # A declaration is authoritative, the same all-or-nothing rule `up` uses: an OS repo that
  # declares SCHEDULER=none is SAYING this box holds no timer, and probing past that answer
  # to install one anyway would make the declaration a suggestion.
  if ((${+functions[_core_cap]})) && ((${#_CORE_CAP})); then
    _core_cap SCHEDULER none
    return 0
  fi
  if [[ "$OSTYPE" == darwin* ]]; then
    echo launchd
  elif [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
    echo systemd
  elif command -v crontab >/dev/null 2>&1; then
    echo cron
  else echo none; fi
}

# _maint_unit_file [scheduler] — THE path this box's maint unit lives at: the declared
# DIRECTORY plus Core's own filename. Empty for cron (whose entry lives in the user's
# crontab, not a file of its own) and for `none`.
#
# CORE OWNS THE FILENAME, the OS layer owns the directory. `dotfiles-maint.service` and
# `com.dotfiles.maint` are the names `systemctl enable`, `launchctl` and the status verbs
# use, so a declaration that could rename the file would decouple the unit Core writes from
# the one it then enables — installed, reported healthy, never run.
#
# A leading `~` is expanded here rather than by the reader: the declaration is DATA, read
# and never sourced, so nothing has expanded it — and a `~/`-rooted dir is the natural thing to
# write. Only a LEADING `~/` is touched; anything else is the author's business.
_maint_unit_file() {
  emulate -L zsh
  local sched="${1:-$(_maint_scheduler)}" d=
  # DECLARED OR NOTHING (#763). Core used to carry a built-in directory per scheduler —
  # macOS's LaunchAgents directory for launchd, the systemd user dir for systemd — as a
  # stopgap for a box that had a new Core but had not yet re-run `./bootstrap.sh
  # --links-only` to link the declaration #667 authored. That launchd literal was the LAST
  # OS-absolute path in Core and the reason audit-core.sh §5c carried a per-line exception
  # for this file; both are gone, and §5c now scans this file like any other — which is why
  # the prefix is NAMED here rather than spelled. An undeclared box resolves no unit file,
  # and maint-install says so rather than writing a timer to a directory Core guessed at.
  ((${+functions[_core_cap]})) && d="$(_core_cap SCHEDULER_UNIT_DIR)"
  [[ -n "$d" ]] || { print -r -- ""; return 0 }
  [[ "$d" == '~/'* ]] && d="$HOME/${d#'~/'}"
  case "$sched" in
  systemd) print -r -- "${d%/}/dotfiles-maint.service" ;;
  launchd) print -r -- "${d%/}/com.dotfiles.maint.plist" ;;
  *) print -r -- "" ;;
  esac
}

# ── The PATH a scheduler must hand the runner ────────────────────────────────
# A scheduler (launchd/systemd/cron) starts the runner with a stripped environment,
# so it has to be TOLD where this box keeps its binaries. The runner used to answer
# that by hardcoding Homebrew's two prefixes — an OS-absolute path in portable Core,
# and precisely what the Core⇄OS boundary gate rejects.
#
# Instead: capture the LIVE PATH of the interactive shell doing the install and bake
# it into the unit. Whatever prefix this OS uses (Homebrew, pkgsrc, Nix, a distro
# path) is already correct in that PATH, so the OS supplies the truth and Core names
# nothing. The trade-off is that the unit is a SNAPSHOT — re-run `maint-install`
# after a PATH change (maint-status flags a unit that predates this).
_maint_unit_path() { print -r -- "$PATH" }

# Minimal XML escape for embedding that PATH in the launchd plist. A directory
# containing & < > is legal on every filesystem here and would otherwise produce a
# malformed plist that launchd rejects silently at load time.
_maint_xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"
  print -r -- "$s"
}

# POSIX single-quote a value for a /bin/sh command line — cron hands its command field
# to sh, so an UNQUOTED (or double-quoted) PATH is code, not data: a directory holding
# $(…) or a backtick would be EVALUATED at every scheduled run, and one holding a double
# quote would simply make the line malformed. Inside single quotes nothing is special to
# the shell, so the only case to handle is an embedded single quote — closed, escaped,
# reopened as the classic '\'' sequence.
_maint_sh_squote() {
  local s="$1" q="'" esc="'\\''"
  print -r -- "'${s//$q/$esc}'"
}

# Escape a value for a DOUBLE-QUOTED field in a systemd unit. systemd expands % SPECIFIERS
# (%h = home directory, %i = instance, …), so a literal % must be DOUBLED or a legitimate
# PATH entry like /sent%h/bin silently becomes /sent<homedir>/bin — or the unit fails to
# load outright on an unknown specifier. Inside double quotes systemd also processes C-style
# escapes, so \ and " need escaping too, and the backslash pass must come FIRST or it would
# re-escape the backslashes the quote pass adds.
_maint_systemd_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//\%/%%}"
  print -r -- "$s"
}

# ...and the extra pass a COMMAND LINE needs on top of that. `ExecStart=` is not a path
# field: systemd performs environment-variable substitution there, so a checkout under a
# directory literally named `${HOME}` — or any `$FOO` — would execute a different path, or
# an empty one. A literal dollar is written `$$`. That pass belongs HERE and not in
# _maint_systemd_escape, because `Environment=` performs no variable substitution: `$` is
# an ordinary character in the PATH value, and doubling it there would corrupt it.
#
# Quoting is the other half of what makes ExecStart safe. Unquoted, systemd would split the
# runner on whitespace and a lone " would open a quoted section swallowing the rest of the
# line; quoting reduces both to the substitutions above. (Single quotes need no escape —
# inside double quotes systemd treats them literally.)
_maint_systemd_exec_escape() {
  local s
  s="$(_maint_systemd_escape "$1")"
  s="${s//\$/\$\$}"
  print -r -- "$s"
}

# The runner maint-install records is ALWAYS absolute — `$_MAINT_SH` is `:A`-resolved at
# the top of this file — so a relative value is a shape Core never wrote. It is also the
# one value this function must not hand back even if it wanted to: `[[ -f ]]` would resolve
# it against whatever directory maint-status happens to be run FROM, so a hand-edited unit
# pairing a relative script with systemd's `WorkingDirectory=` (or cron's implicit $HOME)
# would read as dead or alive depending on where the operator was standing. Requiring an
# absolute path is what makes the verdict a property of the unit rather than of the caller.
_maint_abs_path() { [[ "$1" == /* ]] }

# ...and for the two arms that read a COMMAND rather than a path field, exactly one bare
# argument: no flags, no redirection, nothing after the path. That is what separates "the
# runner maint-install wrote" from a hand-edited command line that merely starts with it.
#
# A `%` disqualifies it outright, in BOTH those arms, because in neither is the recorded
# text the path that actually runs: systemd expands % SPECIFIERS in ExecStart (%h = home,
# %i = instance, …), the same expansion _maint_systemd_escape already doubles against in
# `Environment=`; and cron reads % as its newline metacharacter, so everything past it is
# stdin rather than command. Testing the literal text with `-f` would therefore answer a
# question about a path nothing executes — false either way, dead or alive.
_maint_lone_arg() { [[ "$1" != *[[:space:]]* && "$1" != *%* ]] && _maint_abs_path "$1" }

# Consume one POSIX single-quoted token from the FRONT of $1 and print whatever follows
# it; non-zero if the token is unterminated. _maint_sh_squote renders an embedded quote as
# the classic '\'' — closed, escaped, reopened — so the closing quote is the first one NOT
# followed by \''. Scanning for it is what makes the interpreter's position PROVABLE rather
# than merely likely: without it, a command hiding the text `' /usr/bin/env bash ` inside
# the assignment's value or a later argument reads exactly like the real thing, and the
# argument of some other program gets reported as our dead runner.
_maint_squote_rest() {
  local t="$1"
  [[ "$t" == \'* ]] || return 1
  t="${t#\'}"
  while true; do
    [[ "$t" == *\'* ]] || return 1 # unterminated
    t="${t#*\'}"                   # step past the next quote
    [[ "$t" == \\\'\'* ]] || break  # not an escaped quote → that one closed the token
    t="${t#\\\'\'}"
  done
  print -r -- "$t"
}

# The systemd counterpart: decode ONE double-quoted ExecStart argument that spans the whole
# of $1, undoing exactly the substitutions _maint_systemd_exec_escape applies. Non-zero on
# anything it could not have written — a closing quote with argv after it, an unterminated
# token, a C escape we never emit (\n, \t), a bare % , or a bare $ .
#
# Those last two are the load-bearing cases, and they are the same case: `%h` is a SPECIFIER
# and `$HOME` a VARIABLE REFERENCE, so in neither is the string in the file the path systemd
# runs. Resolving them ourselves would mean reimplementing systemd's specifier table and
# reading the unit's environment block. A path we cannot reconstruct is not evidence of a
# dead job — the same rule the launchd arm applies to an entity reference it cannot decode.
_maint_systemd_unquote() {
  local t="$1" out='' run
  [[ "$t" == \"* ]] || return 1
  t="${t#\"}"
  while true; do
    case "$t" in
    '"') print -r -- "$out"; return 0 ;; # the closing quote must END the value…
    '"'*) return 1 ;;                    # …or what follows is a second argument
    '\\'*) out+='\'; t="${t#'\\'}" ;;
    '\"'*) out+='"'; t="${t#'\"'}" ;;
    '\'*) return 1 ;;   # some other C escape — not a shape maint-install renders
    '%%'*) out+='%'; t="${t#%%}" ;;
    '%'*) return 1 ;;   # an unresolved specifier
    '$$'*) out+='$'; t="${t#\$\$}" ;;
    '$'*) return 1 ;;   # an unresolved variable reference
    '') return 1 ;;     # unterminated
    # A run of ordinary characters, consumed in one step. The class must include the
    # BACKSLASH as well as " % and $ , or a \\ sitting mid-path would be copied through
    # undecoded instead of collapsing to the single \ the path really holds.
    *)
      run="${t%%[\\\"%\$]*}"
      out+="$run"
      t="${t#"$run"}"
      ;;
    esac
  done
}

# Read back the runner path a scheduler unit RECORDS, or print nothing when there is no
# unit (or none can be parsed out of it). Deliberately not `$_MAINT_SH`: the whole point
# is that the two can drift. `$_MAINT_SH` is re-resolved from %x every shell, so it always
# names wherever the config lives NOW — which is why `maint-run` keeps working after the
# consuming repo moves while the scheduler, holding the absolute path frozen at install
# time, has been firing at a path that no longer exists.
#
# Silence on an unparseable unit is intentional: this feeds a "your job is dead" warning,
# and a hand-edited unit in a shape Core never wrote is not evidence of that. Each arm
# therefore matches the EXACT shape maint-install renders and bails on anything else —
# "close enough" parsing is what turns a live job into a false death notice.
_maint_unit_runner() {
  local f line cmd xml rest argv0 sq dq esc
  case "$(_maint_scheduler)" in
  systemd)
    f="$(_maint_unit_file systemd)"
    [[ -n "$f" && -f "$f" ]] || return 0
    line="$(grep '^ExecStart=/usr/bin/env bash ' "$f" 2>/dev/null | head -n 1)"
    [[ -n "$line" ]] || return 0
    line="${line#ExecStart=/usr/bin/env bash }"
    if [[ "$line" == \"* ]]; then
      # The shape maint-install writes: the runner as one double-quoted, escaped argument.
      # _maint_systemd_unquote enforces that the closing quote ends the line, so `… bash
      # "/existing/runner" --quiet` is refused rather than read as one long path.
      line="$(_maint_systemd_unquote "$line")" || return 0
      _maint_abs_path "$line" && print -r -- "$line"
    else
      # The pre-quoting shape, still on disk wherever maint-install has not been re-run.
      # EXACTLY one argument: `… bash /existing/runner --quiet` is a hand-edited unit that
      # runs a script that IS there; treating the whole suffix as a path would report that
      # live job as dead. (That writer emitted the path bare, so a runner containing
      # whitespace was already a broken unit — staying quiet is right there too.)
      _maint_lone_arg "$line" && print -r -- "$line"
    fi
    ;;
  launchd)
    # ProgramArguments[1] — argv[0] is the interpreter, argv[1] the runner. Parsed with
    # zsh string ops rather than python3/plutil: this is a login-shell function, and the
    # suite's plist parsing (plistlib) is a TEST-side luxury Core itself cannot assume.
    f="$(_maint_unit_file launchd)"
    [[ -n "$f" && -f "$f" ]] || return 0
    xml="$(<"$f")"
    xml="${xml//$'\n'/ }" # tolerate the array wrapped across lines
    rest="${xml#*<key>ProgramArguments</key>}"
    [[ "$rest" != "$xml" ]] || return 0
    # The array must be THIS key's value — only whitespace may sit between them. A bare
    # `*<array>` would skip over a non-array value here and lift the second string out of
    # some later key's array, naming a path this unit never runs.
    rest="${rest#"${rest%%[^[:space:]]*}"}"
    [[ "$rest" == "<array>"* && "$rest" == *"</array>"* ]] || return 0
    rest="${${rest#<array>}%%</array>*}"
    [[ "$rest" == *"<string>"*"</string>"* ]] || return 0
    # argv[0] must be the interpreter maint-install writes. A hand-edited
    # ["/bin/echo", "/missing"] is a perfectly healthy job — reading ITS argv[1] as our
    # runner would report it dead on the strength of an argument to another program.
    argv0="${${rest#*<string>}%%</string>*}"
    [[ "$argv0" == "/bin/bash" ]] || return 0
    rest="${${rest#*<string>}#*</string>}" # drop argv[0]
    [[ "$rest" == *"<string>"*"</string>"* ]] || return 0
    rest="${${rest#*<string>}%%</string>*}"
    # Undo the entity encoding a well-formed plist carries. &amp; LAST, mirroring
    # _maint_xml_escape doing & FIRST — the other order would decode a path that really
    # contained the text "&lt;" into "<". (maint-install writes ProgramArguments raw and
    # only escapes the PATH value, so today this is a no-op on units Core wrote; it is
    # what keeps the read side correct for a hand-written or later-escaped plist, which
    # may legally encode a quote as &quot;/&apos; that launchd resolves to the real name.)
    # The quote replacements go through variables: a backslash in the replacement text of
    # ${x//pat/repl} stays LITERAL in zsh, so the obvious `\'` decodes &apos; to \' — a
    # path that does not exist, i.e. the false death notice this arm exists to avoid.
    sq="'" dq='"'
    rest="${rest//&lt;/<}"; rest="${rest//&gt;/>}"
    rest="${rest//&quot;/$dq}"; rest="${rest//&apos;/$sq}"
    # Any OTHER reference — a numeric one like &#47;, or an entity we do not know — leaves
    # us holding text that is not the filename launchd runs. In well-formed XML a raw & is
    # illegal, so once the known entities are accounted for, a surviving & is exactly that
    # case. Refuse rather than guess: a path we cannot read is not evidence of a dead job.
    [[ "${rest//&amp;/}" == *"&"* ]] && return 0
    rest="${rest//&amp;/&}"
    # Absolute only — same reasoning as the other two arms. No lone-argument test here:
    # a plist argv element has exact boundaries, so a space in it is part of the path
    # rather than a second argument.
    _maint_abs_path "$rest" && print -r -- "$rest"
    ;;
  cron)
    line="$(crontab -l 2>/dev/null | grep -F '# dotfiles-maint')"
    # Strip the trailing marker, then require one of the shapes maint-install has written —
    # today's, and the two older ones (before the runner was quoted, and before the PATH
    # capture). Both legacy forms stay parseable because a line on disk is only rewritten
    # when the operator re-runs maint-install:
    #
    #   <mm> <hh> * * * PATH='<value>' /usr/bin/env bash '<runner>' # dotfiles-maint
    #   <mm> <hh> * * * PATH='<value>' /usr/bin/env bash <runner>   # dotfiles-maint
    #   <mm> <hh> * * * /usr/bin/env bash <runner>                  # dotfiles-maint
    #
    # The old form matters precisely because it is the unit most likely to ALSO have a
    # stale runner path: refusing to parse it would classify a completely dead pre-capture
    # job as a mere "some steps will skip".
    #
    # Every token is located by POSITION, never by searching: the five schedule fields,
    # then the assignment, whose value is consumed as a real single-quoted token so the
    # interpreter that follows is provably the command cron runs — not text that merely
    # looks like it. Matching on appearance is what let `PATH='/x' /bin/echo '␣/usr/bin/env
    # bash /missing'` (a healthy job running /bin/echo) hand back /missing as our runner.
    line="${line% # dotfiles-maint}"
    if [[ "$line" == [0-9]*" "[0-9]*" * * * PATH='"* ]]; then
      cmd="$(_maint_squote_rest "${line#*" * * * PATH="}")" || return 0
      [[ "$cmd" == " "* ]] || return 0
      cmd="${cmd# }"
    elif [[ "$line" == [0-9]*" "[0-9]*" * * * "* ]]; then
      cmd="${line#*" * * * "}"
    else
      return 0
    fi
    # Anchored at the START of the command, so a program spliced ahead of the interpreter
    # cannot slip through the second shape either.
    [[ "$cmd" == "/usr/bin/env bash "* ]] || return 0
    line="${cmd#"/usr/bin/env bash "}"
    # A BARE % — one left over once every escaped \% is accounted for — is cron's newline
    # metacharacter, and sh quoting is no defence: cron translates the field BEFORE sh ever
    # sees it, so the command is truncated there and the rest becomes stdin. The recorded
    # text is then not what runs, in the quoted shape exactly as in the legacy one, where
    # _maint_lone_arg refuses it. This MUST be tested before the decode below, which would
    # otherwise turn our own \% into a % and destroy the evidence of which kind it was.
    [[ "${line//\\%/}" == *%* ]] && return 0
    # Now peel the two layers, in the reverse of the order maint-install applies them: the
    # cron-level \% → % first, leaving the sh-level single-quoted token.
    line="${line//\\%/%}"
    if [[ "$line" == \'* ]]; then
      # The shape maint-install writes. Consume the token as a real single-quoted token —
      # nothing may follow it, which is what refuses `… bash '/existing/runner' >>/tmp/log`.
      rest="$(_maint_squote_rest "$line")" || return 0
      [[ -z "$rest" ]] || return 0
      line="${line#\'}"
      line="${line%\'}"
      sq="'" esc="'\\''"
      # Quoted so zsh matches the sequence LITERALLY: unquoted, the \' inside it would be
      # read as a pattern escape and match three quotes rather than the four-character
      # '\'' that _maint_sh_squote actually emits.
      line="${line//"$esc"/$sq}"
      # No lone-argument test: a single-quoted token has exact boundaries, so whitespace
      # inside it is part of the path rather than a second argument (as in the launchd arm).
      _maint_abs_path "$line" && print -r -- "$line"
    else
      # The pre-quoting shape. Same one-argument rule as the systemd arm, and cron needed
      # it more: the command field is a full sh command line, so `… bash /existing/runner
      # >>/tmp/log` or a trailing flag would otherwise be read as one long, nonexistent
      # path and reported as a dead job.
      _maint_lone_arg "$line" && print -r -- "$line"
    fi
    ;;
  esac
}

# True only when a schedule EXISTS but is broken in one of two silent ways, recorded in
# $_MAINT_REFRESH_WHY so maint-status can say WHICH:
#
#   path   — written before Core baked the PATH into it. Still runs, still exits 0; it
#            just hands the runner a stripped PATH, so brew/mise/nvim resolve to nothing
#            and those steps skip.
#   runner — the recorded runner path no longer resolves. The consuming repo moved and
#            the unit still points at the old location, so the job is simply dead. This
#            is the more invisible of the two: `maint-status` prints the timer happily,
#            `launchctl list` reports exit status 0 while the job has not fired since the
#            move, and `maint-run` keeps working because it re-resolves the runner from
#            the live config instead of reading the unit.
#
# Either way the fix is the same (`maint-install` rewrites the unit), but the operator is
# owed the distinction — one is a stale snapshot, the other means their repo moved.
#
# The two are NOT mutually exclusive, and a unit that predates the capture is if anything
# the likeliest one to have been left behind by a move as well. So the runner is inspected
# FIRST and `path` is the fallback: reporting the older, milder cause on a job that does
# not run at all would tell the operator some steps will skip when in fact none do.
#
# No schedule installed is not a complaint, hence the -f / -n guards before each test.
typeset -g _MAINT_REFRESH_WHY=''
_maint_unit_needs_refresh() {
  local f line runner has_path=''
  _MAINT_REFRESH_WHY=''
  case "$(_maint_scheduler)" in
  systemd)
    f="$(_maint_unit_file systemd)"
    [[ -n "$f" && -f "$f" ]] || return 1
    grep -q '^Environment="PATH=' "$f" && has_path=1
    ;;
  launchd)
    # Test for the PATH KEY, not merely for an EnvironmentVariables dict: a plist
    # carrying some unrelated variable would otherwise read as current while the
    # runner still gets a stripped PATH — the exact silent-skip this detects.
    f="$(_maint_unit_file launchd)"
    [[ -n "$f" && -f "$f" ]] || return 1
    grep -q '<key>PATH</key>' "$f" && has_path=1
    ;;
  cron)
    line="$(crontab -l 2>/dev/null | grep -F '# dotfiles-maint')"
    [[ -n "$line" ]] || return 1
    [[ "$line" == *PATH=* ]] && has_path=1
    ;;
  *) return 1 ;;
  esac
  runner="$(_maint_unit_runner)"
  [[ -n "$runner" && ! -f "$runner" ]] && { _MAINT_REFRESH_WHY=runner; return 0; }
  [[ -n "$has_path" ]] || { _MAINT_REFRESH_WHY=path; return 0; }
  return 1
}

maint-install() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "maint-install [HH:MM]" "schedule the daily safe-update job (24h, default 13:00)"; return 0; }
  local when="${1:-13:00}"
  if [[ "$when" != <0-23>:<0-59> ]]; then
    _core_usage "maint-install [HH:MM]   (24h, e.g. 13:00)"
    return 1
  fi
  local hh="${when%%:*}" mm="${when##*:}"
  if [[ ! -f "$_MAINT_SH" ]]; then
    _core_err "maint: runner not found at $_MAINT_SH"
    return 1
  fi
  chmod +x "$_MAINT_SH" 2>/dev/null

  case "$(_maint_scheduler)" in
  systemd)
    # The declared path names the .service; the .timer is its sibling, derived rather
    # than declared twice — two keys that must agree is two keys that can disagree.
    local svc tmr ud
    svc="$(_maint_unit_file systemd)"
    if [[ -z "$svc" ]]; then
      _core_err "maint-install: SCHEDULER=systemd but no SCHEDULER_UNIT_DIR is declared"
      _core_hint "declare it in os/<os>.capabilities (see core/examples/os.capabilities.example)"
      _core_hint "if your OS repo already ships one, re-run its ./bootstrap.sh --links-only"
      return 1
    fi
    tmr="${svc%.service}.timer"
    ud="${svc:h}"
    mkdir -p "$ud"
    cat >"$svc" <<EOF
[Unit]
Description=dotfiles daily maintenance (brew, plugins, nvim, mise)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment="PATH=$(_maint_systemd_escape "$(_maint_unit_path)")"
ExecStart=/usr/bin/env bash "$(_maint_systemd_exec_escape "$_MAINT_SH")"
EOF
    cat >"$ud/dotfiles-maint.timer" <<EOF
[Unit]
Description=Run dotfiles maintenance daily at $when

[Timer]
OnCalendar=*-*-* $hh:$mm:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now dotfiles-maint.timer
    _core_ok "systemd user timer installed for $when — next runs:"
    systemctl --user list-timers dotfiles-maint.timer --no-pager 2>/dev/null
    _core_hint "headless/server box you're not always logged into? run: loginctl enable-linger $USER"
    ;;
  launchd)
    local plist
    plist="$(_maint_unit_file launchd)"
    if [[ -z "$plist" ]]; then
      _core_err "maint-install: SCHEDULER=launchd but no SCHEDULER_UNIT_DIR is declared"
      _core_hint "declare it in os/<os>.capabilities (see core/examples/os.capabilities.example)"
      _core_hint "if your OS repo already ships one, re-run its ./bootstrap.sh --links-only"
      return 1
    fi
    mkdir -p "${plist:h}" "${_MAINT_LOG:h}"
    cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.dotfiles.maint</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$(_maint_xml_escape "$_MAINT_SH")</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$(_maint_xml_escape "$(_maint_unit_path)")</string></dict>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>$((10#$hh))</integer><key>Minute</key><integer>$((10#$mm))</integer></dict>
  <key>StandardOutPath</key><string>$(_maint_xml_escape "$_MAINT_LOG")</string>
  <key>StandardErrorPath</key><string>$(_maint_xml_escape "$_MAINT_LOG")</string>
  <key>RunAtLoad</key><false/>
</dict></plist>
EOF
    launchctl unload "$plist" 2>/dev/null
    launchctl load "$plist" && _core_ok "launchd agent installed for $when (com.dotfiles.maint)"
    ;;
  cron)
    local marker="# dotfiles-maint"
    # cron hands the command field to /bin/sh, so a leading `PATH=…` is just an
    # env-prefixed command — and it stays local to this job, unlike a bare `PATH=`
    # crontab line, which would silently re-point every OTHER job in the table.
    #
    # TWO escapes, and the ORDER matters. First POSIX single-quote the value, so sh
    # treats it as data — unquoted or double-quoted, a directory containing $(…) or a
    # backtick would be evaluated on every scheduled run. Then escape `%`, which is
    # cron's own newline metacharacter and would otherwise truncate the line mid-PATH.
    # Quoting first is what makes the `%` pass safe: it only ever sees the final text.
    #
    # The RUNNER gets the identical treatment, and needs it just as much: it is a word on
    # the same sh command line and lives at whatever path the consuming repo was cloned
    # to. Bare, a `%` there truncates the command and feeds the remainder to it as stdin —
    # a job that silently stops running, which is precisely the failure maint-status is
    # supposed to be able to see.
    local cron_path cron_runner
    cron_path="$(_maint_sh_squote "$(_maint_unit_path)")"
    cron_path="${cron_path//\%/\\%}"
    cron_runner="$(_maint_sh_squote "$_MAINT_SH")"
    cron_runner="${cron_runner//\%/\\%}"
    # `print -r`, never `echo`: maint-install runs under `emulate -L zsh`, where the echo
    # builtin INTERPRETS backslash escapes. Both fields are paths that may legitimately hold
    # a backslash, and two characters is all it takes — `\n` or `\t` in a directory name is
    # rewritten before cron ever sees the table, and `\c` truncates the line outright, which
    # is a schedule that silently stops existing. -r is the whole point; -- guards a value
    # that begins with a dash.
    (
      crontab -l 2>/dev/null | grep -vF "$marker"
      print -r -- "$mm $hh * * * PATH=$cron_path /usr/bin/env bash $cron_runner $marker"
    ) | crontab -
    _core_ok "cron entry installed for $when"
    crontab -l 2>/dev/null | grep -F "$marker"
    ;;
  *)
    _core_errbox "maint-install: no supported scheduler found" \
      "why: none of systemd (user), launchd, or cron is available on this box" \
      "fix: install one, or run maintenance by hand / from your own timer:" \
      "     maint-run        # run the daily job now, in the foreground" \
      "     */1 …            # or wire \`$_MAINT_SH\` into whatever scheduler you do have"
    return 1
    ;;
  esac
}

maint-run() {
  _core_wants_help "$1" && { _core_help "maint-run" "run the daily maintenance job now, in the foreground"; return 0; }
  echo "running $_MAINT_SH ..."
  /usr/bin/env bash "$_MAINT_SH"
}
maint-log() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "maint-log [N|-f]" "show last N maintenance-log lines (default 50), or follow"; return 0; }
  # Defensive input handling (mirrors serve/cdup/mkbak): a bad N must be rejected in
  # Core's voice, not handed to `tail` to fail with a raw "tail: invalid number".
  if [[ -n "$1" && "$1" != (-f|--follow) && "$1" != <1-> ]]; then
    _core_err "maint-log: N must be a positive integer or -f/--follow (got '$1')"
    _core_usage "maint-log [N|-f]"
    return 1
  fi
  [[ -r "$_MAINT_LOG" ]] || {
    echo "no log yet at $_MAINT_LOG"
    return 0
  }
  if [[ "$1" == (-f|--follow) ]]; then tail -f "$_MAINT_LOG"; else tail -n "${1:-50}" "$_MAINT_LOG"; fi
}
maint-status() {
  _core_wants_help "$1" && { _core_help "maint-status" "when does the job next run / is it enabled"; return 0; }
  case "$(_maint_scheduler)" in
  systemd)
    systemctl --user list-timers dotfiles-maint.timer --no-pager 2>/dev/null
    systemctl --user status dotfiles-maint.service --no-pager 2>/dev/null | head -5
    ;;
  launchd) launchctl list 2>/dev/null | grep -i dotfiles || echo "not loaded" ;;
  cron) crontab -l 2>/dev/null | grep -F "# dotfiles-maint" || echo "no cron entry" ;;
  *) echo "no scheduler" ;;
  esac
  # Both causes are fixed by re-running maint-install, but they mean different things:
  # say which, or the operator reads "stale unit" and never learns their repo moved.
  if _maint_unit_needs_refresh; then
    case "$_MAINT_REFRESH_WHY" in
    runner)
      _core_hint "this schedule runs $(_maint_unit_runner) — which no longer exists, so the job is dead"
      _core_hint "(the repo moved; maint-run still works because it re-resolves it) — re-run: maint-install"
      ;;
    *) _core_hint "this schedule predates the PATH capture — brew/mise steps will skip; re-run: maint-install" ;;
    esac
  fi
  return 0
}
# AN UNRESOLVABLE UNIT PATH MUST NOT REPORT SUCCESS, and this is the sharp edge of #763.
# Both branches used to guard the removal with `[[ -n "$path" ]] &&` and then print "removed"
# unconditionally — harmless while Core carried a built-in unit directory, because the path
# was never empty. It is now: a box whose declaration is not linked resolves nothing, and on
# launchd that meant `launchctl unload` never ran, the plist stayed on disk, the agent kept
# FIRING, and the operator was told it had been removed. A false success on an uninstall is
# worse than a refusal, because nobody checks twice.
#
# THE TWO SCHEDULERS FAIL DIFFERENTLY, so they say different things. systemd's disable runs
# by unit NAME and needs no path, so the timer really does stop — only the files are left
# behind, and the message says exactly that. launchd needs the plist path to unload at all,
# so nothing has happened and the message must not pretend otherwise. Both return non-zero,
# so a script driving this notices; both name --links-only, which is the actual remedy.
maint-uninstall() {
  _core_wants_help "$1" && { _core_help "maint-uninstall" "remove the scheduled maintenance job"; return 0; }
  case "$(_maint_scheduler)" in
  systemd)
    systemctl --user disable --now dotfiles-maint.timer 2>/dev/null
    local svc
    svc="$(_maint_unit_file systemd)"
    if [[ -z "$svc" ]]; then
      systemctl --user daemon-reload
      _core_err "maint-uninstall: timer disabled, but its unit files could NOT be removed"
      _core_hint "no SCHEDULER_UNIT_DIR is declared, so Core cannot name them"
      _core_hint "if your OS repo already ships a declaration, re-run its ./bootstrap.sh --links-only, then re-run this"
      return 1
    fi
    rm -f "$svc" "${svc%.service}.timer"
    systemctl --user daemon-reload
    _core_ok "removed systemd timer"
    ;;
  launchd)
    local p
    p="$(_maint_unit_file launchd)"
    if [[ -z "$p" ]]; then
      _core_err "maint-uninstall: cannot locate the launchd agent — it is STILL LOADED and will keep running"
      _core_hint "no SCHEDULER_UNIT_DIR is declared, so Core cannot name the plist to unload"
      _core_hint "if your OS repo already ships a declaration, re-run its ./bootstrap.sh --links-only, then re-run this"
      return 1
    fi
    launchctl unload "$p" 2>/dev/null
    rm -f "$p"
    _core_ok "removed launchd agent"
    ;;
  cron)
    (crontab -l 2>/dev/null | grep -vF "# dotfiles-maint") | crontab -
    _core_ok "removed cron entry"
    ;;
  esac
}
