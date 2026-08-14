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

_maint_scheduler() {
  if [[ "$OSTYPE" == darwin* ]]; then
    echo launchd
  elif [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
    echo systemd
  elif command -v crontab >/dev/null 2>&1; then
    echo cron
  else echo none; fi
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

# Escape a value for a systemd unit's quoted `Environment=` assignment. systemd expands
# % SPECIFIERS there (%h = home directory, %i = instance, …), so a literal % must be
# DOUBLED or a legitimate PATH entry like /sent%h/bin silently becomes /sent<homedir>/bin
# — or the unit fails to load outright on an unknown specifier. Inside double quotes
# systemd also processes C-style escapes, so \ and " need escaping too, and the backslash
# pass must come FIRST or it would re-escape the backslashes the quote pass adds.
_maint_systemd_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//\%/%%}"
  print -r -- "$s"
}

# Read back the runner path a scheduler unit RECORDS, or print nothing when there is no
# unit (or none can be parsed out of it). Deliberately not `$_MAINT_SH`: the whole point
# is that the two can drift. `$_MAINT_SH` is re-resolved from %x every shell, so it always
# names wherever the config lives NOW — which is why `maint-run` keeps working after the
# consuming repo moves while the scheduler, holding the absolute path frozen at install
# time, has been firing at a path that no longer exists.
#
# Silence on an unparseable unit is intentional: this feeds a "your job is dead" warning,
# and a hand-edited unit in a shape Core never wrote is not evidence of that.
_maint_unit_runner() {
  local f line xml rest
  case "$(_maint_scheduler)" in
  systemd)
    f="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/dotfiles-maint.service"
    [[ -f "$f" ]] || return 0
    line="$(grep '^ExecStart=/usr/bin/env bash ' "$f" 2>/dev/null | head -n 1)"
    [[ -n "$line" ]] && print -r -- "${line#ExecStart=/usr/bin/env bash }"
    ;;
  launchd)
    # ProgramArguments[1] — argv[0] is the interpreter, argv[1] the runner. Parsed with
    # zsh string ops rather than python3/plutil: this is a login-shell function, and the
    # suite's plist parsing (plistlib) is a TEST-side luxury Core itself cannot assume.
    f="$HOME/Library/LaunchAgents/com.dotfiles.maint.plist"
    [[ -f "$f" ]] || return 0
    xml="$(<"$f")"
    xml="${xml//$'\n'/ }" # tolerate the array wrapped across lines
    rest="${xml#*<key>ProgramArguments</key>}"
    [[ "$rest" != "$xml" && "$rest" == *"<array>"* ]] || return 0
    rest="${${rest#*<array>}%%</array>*}"
    rest="${${rest#*<string>}#*</string>}" # drop argv[0]
    [[ "$rest" == *"<string>"*"</string>"* ]] || return 0
    rest="${${rest#*<string>}%%</string>*}"
    # Undo the entity encoding a well-formed plist carries. &amp; LAST, mirroring
    # _maint_xml_escape doing & FIRST — the other order would decode a path that really
    # contained the text "&lt;" into "<". (maint-install writes ProgramArguments raw and
    # only escapes the PATH value, so today this is a no-op on units Core wrote; it is
    # what keeps the read side correct for a hand-written or later-escaped plist.)
    rest="${rest//&lt;/<}"; rest="${rest//&gt;/>}"; rest="${rest//&amp;/&}"
    print -r -- "$rest"
    ;;
  cron)
    line="$(crontab -l 2>/dev/null | grep -F '# dotfiles-maint')"
    # Strip the trailing marker, then take what follows the interpreter. The line now
    # opens with a single-quoted `PATH=…` env prefix (see _maint_sh_squote), so anchoring
    # on `/usr/bin/env bash ` — and on its LAST occurrence, in case a PATH entry contains
    # the string — is what survives that prefix.
    line="${line% # dotfiles-maint}"
    [[ "$line" == *"/usr/bin/env bash "* ]] && print -r -- "${line##*/usr/bin/env bash }"
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
# No schedule installed is not a complaint, hence the -f / -n guards before each test.
typeset -g _MAINT_REFRESH_WHY=''
_maint_unit_needs_refresh() {
  local f line runner
  _MAINT_REFRESH_WHY=''
  case "$(_maint_scheduler)" in
  systemd)
    f="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/dotfiles-maint.service"
    [[ -f "$f" ]] || return 1
    grep -q '^Environment="PATH=' "$f" || { _MAINT_REFRESH_WHY=path; return 0; }
    ;;
  launchd)
    # Test for the PATH KEY, not merely for an EnvironmentVariables dict: a plist
    # carrying some unrelated variable would otherwise read as current while the
    # runner still gets a stripped PATH — the exact silent-skip this detects.
    f="$HOME/Library/LaunchAgents/com.dotfiles.maint.plist"
    [[ -f "$f" ]] || return 1
    grep -q '<key>PATH</key>' "$f" || { _MAINT_REFRESH_WHY=path; return 0; }
    ;;
  cron)
    line="$(crontab -l 2>/dev/null | grep -F '# dotfiles-maint')"
    [[ -n "$line" ]] || return 1
    [[ "$line" == *PATH=* ]] || { _MAINT_REFRESH_WHY=path; return 0; }
    ;;
  *) return 1 ;;
  esac
  runner="$(_maint_unit_runner)"
  [[ -n "$runner" && ! -f "$runner" ]] && { _MAINT_REFRESH_WHY=runner; return 0; }
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
    local ud="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    mkdir -p "$ud"
    cat >"$ud/dotfiles-maint.service" <<EOF
[Unit]
Description=dotfiles daily maintenance (brew, plugins, nvim, mise)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment="PATH=$(_maint_systemd_escape "$(_maint_unit_path)")"
ExecStart=/usr/bin/env bash $_MAINT_SH
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
    local plist="$HOME/Library/LaunchAgents/com.dotfiles.maint.plist"
    mkdir -p "${plist:h}" "${_MAINT_LOG:h}"
    cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.dotfiles.maint</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$_MAINT_SH</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$(_maint_xml_escape "$(_maint_unit_path)")</string></dict>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>$((10#$hh))</integer><key>Minute</key><integer>$((10#$mm))</integer></dict>
  <key>StandardOutPath</key><string>$_MAINT_LOG</string>
  <key>StandardErrorPath</key><string>$_MAINT_LOG</string>
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
    local cron_path
    cron_path="$(_maint_sh_squote "$(_maint_unit_path)")"
    cron_path="${cron_path//\%/\\%}"
    (
      crontab -l 2>/dev/null | grep -vF "$marker"
      echo "$mm $hh * * * PATH=$cron_path /usr/bin/env bash $_MAINT_SH $marker"
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
maint-uninstall() {
  _core_wants_help "$1" && { _core_help "maint-uninstall" "remove the scheduled maintenance job"; return 0; }
  case "$(_maint_scheduler)" in
  systemd)
    systemctl --user disable --now dotfiles-maint.timer 2>/dev/null
    rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/dotfiles-maint."{service,timer}
    systemctl --user daemon-reload
    _core_ok "removed systemd timer"
    ;;
  launchd)
    local p="$HOME/Library/LaunchAgents/com.dotfiles.maint.plist"
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
