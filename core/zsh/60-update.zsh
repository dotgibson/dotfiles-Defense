# core/zsh/60-update.zsh
# ──────────────────────────────────────────────────────────────────────────────
# "Tell me when there are updates, don't make me remember." A throttled,
# fully-backgrounded check on shell start that prints a single one-line nudge if
# packages are upgradable — then APPLYING is your call via `up`.
#
# WHY NOT update+upgrade on every shell:
#   • blocks every pane/split/sesh-session on a package sync (kills the startup
#     work in 00-tools.zsh); concurrent shells deadlock on the dpkg/rpm lock
#   • needs root on every shell (password prompt, or passwordless sudo = privesc)
#   • unattended `-y` upgrades are dangerous on Arch (partial-upgrade breakage),
#     Gentoo (multi-hour compiles), and Kali (engagement reproducibility)
#   • hangs when offline
# So: this CHECKS (no root, backgrounded, throttled to once/day) and NUDGES. The
# real upgrade is `up` (interactive) or an OS-layer timer — see the tail comment.
#
# LOAD ORDER: source near the END of your loader (after `plugins`), so the notice
# prints just above your first prompt.
#
# Config (override in os/local before this is sourced):
#   UPDATE_CHECK_ENABLED   1        # set 0 to disable the check entirely (e.g. Kali during ops)
#   UPDATE_CHECK_INTERVAL  86400    # seconds between background checks
# ──────────────────────────────────────────────────────────────────────────────

[[ $- == *i* ]] || return 0
: "${UPDATE_CHECK_ENABLED:=1}"
: "${UPDATE_CHECK_INTERVAL:=86400}"
typeset -g _PKGUP_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/pkg-updates"

# Fork-free per-shell path: $EPOCHSECONDS (a zsh/datetime param) replaces `date +%s`,
# and $(<file) replaces `sed -n Np` — removing three subprocess spawns from EVERY
# interactive shell (the same anti-fork thesis as 00-tools.zsh's cached inits; `date`/`sed`
# each cost ~1.7ms/call vs ~0ms for the builtins). Falls back to `date` if the module
# is somehow unavailable, so behaviour is identical on an ancient zsh.
zmodload -F zsh/datetime p:EPOCHSECONDS 2>/dev/null

# Accent colours for the nudge + welcome below (they feed `print -P %F{…}`). These
# come from 05-ui.zsh's canonical palette ($_CORE_ACCENT_SPEC/$_CORE_MUTED_SPEC — the one
# place $COLORTERM is interpreted) when it's loaded, which it is in canonical order
# (ui precedes update). The COLORTERM branch below is a STANDALONE fallback for the
# unit tests, which source this module alone: it reproduces the same truecolor-hex vs
# 256-colour choice so a 16/256-colour TTY never gets a raw 24-bit escape.
# core:theme:gen pkgup-accent-tiers
if [[ -n ${_CORE_ACCENT_SPEC:-} ]]; then
  typeset -g _PKGUP_ACCENT=$_CORE_ACCENT_SPEC _PKGUP_MUTED=$_CORE_MUTED_SPEC
elif [[ "${COLORTERM:-}" == (24bit|truecolor) ]]; then
  typeset -g _PKGUP_ACCENT='#7aa2f7' _PKGUP_MUTED='#565f89'
else
  typeset -g _PKGUP_ACCENT=75 _PKGUP_MUTED=244
fi
# core:theme:end pkgup-accent-tiers

# privilege helper: sudo, else doas (Alpine), else run bare
_pkgup_priv() {
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v doas >/dev/null 2>&1; then
    doas "$@"
  else "$@"; fi
}

# which package manager is this box? (brew wins on macOS). THE PROBE, and it stays: a
# `command -v` ladder is the shape PORTABILITY.md blesses, and the token it returns is
# also the label every user-facing string in `up` interpolates ("via ${mgr}").
# What it no longer decides is WHAT TO RUN — that is _pkgup_verb, below.
_pkgup_mgr() {
  if command -v brew >/dev/null 2>&1; then
    echo brew
  elif command -v pacman >/dev/null 2>&1; then
    echo pacman
  elif command -v dnf >/dev/null 2>&1; then
    echo dnf
  elif command -v zypper >/dev/null 2>&1; then
    echo zypper
  elif command -v apt-get >/dev/null 2>&1; then
    echo apt
  elif command -v apk >/dev/null 2>&1; then
    echo apk
  elif command -v emerge >/dev/null 2>&1; then
    echo emerge
  else echo none; fi
}

# _pkgup_verb <key> — THE resolution point, and the only thing in this file that decides
# what a package manager is asked to do. Every value it returns comes from the OS layer's
# os.capabilities declaration; an unresolved key is the empty string, which every caller
# reads as "this archive does not offer that".
#
# THE BUILT-IN TABLE THAT USED TO SIT ABOVE THIS IS GONE (#763). Core carried one row per
# manager — seven archives' upgrade/count/cleanup verbs, plus a `grep -qi tumbleweed
# /etc/os-release` probe to choose `zypper dup` over `zypper up` — as a stopgap for a box
# that had a new Core but had not yet re-run `./bootstrap.sh --links-only` to link the
# declaration #667 authored for it. That window has closed: every OS repo declares, and
# every box reads its own declaration. Do not reintroduce a default here — a row in Core is
# OS knowledge in the one layer that must not have any, which is the whole point of #663.
#
# ALL OR NOTHING, AND THAT IS STILL THE POINT. Reading the declaration per key with a
# built-in behind it was the obvious shape and it was wrong, because in this schema an
# OMISSION IS A STATEMENT:
#
#   · no PKG_ASSUME_YES      → never auto-confirm; `up -y` lets the manager ask
#   · no PKG_UPGRADE_PARTIAL → `up -i` refuses; this archive updates as a whole
#
# A declaration cannot mean "never" if Core supplies a default for the key you left out.
# So a declaration that is missing a REQUIRED verb is a BROKEN declaration, and the thing
# that catches it is scripts/check-capabilities.sh — a gate you run — not a silent
# substitution at 3am.
#
# THE $+functions GUARD IS NOT DEFENSIVE PADDING. zsh/02-capabilities.zsh is band 02, far
# ahead of this file, so in a real shell _core_cap is always there — but this module is also
# sourced ALONE by the unit suite, the same situation the colour ladder at the top of this
# file already has a standalone arm for. Answer "not offered" rather than erroring out of a
# lone source; an undeclared box now degrades VISIBLY, at each caller's own error message,
# which is what deleting the fallbacks bought.
_pkgup_verb() {
  emulate -L zsh
  ((${+functions[_core_cap]})) || { print -r -- ""; return 0 }
  _core_cap "$1"
}

# _pkgup_run <word...> — run one resolved verb, mapping a declared privilege prefix onto
# what this box actually has. A leading `sudo`/`doas` in a declaration NAMES THE INTENT
# ("this needs root"), not the tool: Alpine has doas and not sudo, and a container has
# neither. Strip it and hand the rest to _pkgup_priv, which is the ladder. A value with
# no prefix (`brew upgrade`) runs bare, which for Homebrew is the only correct answer.
#
# NO ARGUMENTS IS SUCCESS, deliberately: that is how an undeclared optional step
# (PKG_UPGRADE_PRE, PKG_CLEANUP) becomes a no-op inside the && chain in `up` without the
# chain needing to know which manager it is on.
_pkgup_run() {
  (($#)) || return 0
  if [[ "$1" == sudo || "$1" == doas ]]; then
    shift
    (($#)) || return 0
    _pkgup_priv "$@"
  else
    "$@"
  fi
}

# Best-effort, NON-ROOT list of upgradable package NAMES, one per line. The single parse
# path for every archive: run the declared count verb, keep the lines that match
# PKG_PENDING_MATCH, print field PKG_PENDING_FIELD of each. That is the whole of what
# used to be seven hand-written grep/awk heuristics — the divergence between archives is
# now three declared values (an ERE, a field index, a separator) rather than seven code
# branches, and the defaults `.` / 1 / whitespace cover the archives that need none.
#
# The values reach awk through -v and -F, never through eval: a declaration is data, and
# this is the one place it would have been tempting to forget that.
#
# The </dev/null hangs off the command GROUP, not the function definition — `f() { … }
# </dev/null` binds at DEFINITION time in zsh and does nothing at call time. The safety
# has to hold for every caller: `up` runs this in the FOREGROUND via _pkgup_refresh once
# an upgrade finishes, with stdout captured by $(...) and stderr discarded, so a manager
# that stops to ask a question writes the prompt where nobody can see it and then blocks
# on the terminal forever. That is how `up` came to print "Complete!" and hang for good
# on Fedora: a repo with repo_gpgcheck=1 whose signing key only ever reached root's
# keyring makes every non-root --refresh ask to import it, and a declined import is never
# persisted, so it asks again every time. Pinning stdin makes the probe unpromptable no
# matter who calls it or how.
_pkgup_pending() {
  emulate -L zsh
  local cmd match field fs
  cmd="$(_pkgup_verb PKG_COUNT_PENDING)"
  [[ -n "$cmd" ]] || return 1
  match="$(_pkgup_verb PKG_PENDING_MATCH)"
  : "${match:=.}"
  field="$(_pkgup_verb PKG_PENDING_FIELD)"
  : "${field:=1}"
  fs="$(_pkgup_verb PKG_PENDING_FS)"
  # "${fsarg[@]}" on an EMPTY array expands to zero words in zsh, not to one empty
  # string — so awk never sees a stray `-F ''` when no separator is declared.
  local -a fsarg=()
  [[ -n "$fs" ]] && fsarg=(-F "$fs")
  # The status this function returns is the COUNT COMMAND's, taken out of $pipestatus —
  # NOT the pipeline's, which is awk's and is 0 whether or not the manager answered. Only
  # _pkgup_count acts on it, and only for an archive that declared the status meaningful
  # (PKG_COUNT_EXIT_TRUSTED); the list path ignores it, because a partial list is still a
  # better preview than none.
  {
    ${=cmd} 2>/dev/null |
      awk "${fsarg[@]}" -v m="$match" -v f="$field" \
        '$0 ~ m { v = $f; gsub(/^[ \t]+|[ \t]+$/, "", v); if (v != "") print v }'
    return ${pipestatus[1]}
  } </dev/null
}

# Best-effort, NON-ROOT count of upgradable packages.
# Offline / unknown → prints -1 (caller stays silent). Never touches the system.
_pkgup_count() {
  emulate -L zsh
  local refresh
  # No count verb for this archive — no manager at all, or one that declares none. The -1
  # SENTINEL is what keeps the nudge silent; do not "improve" it to 0, which reads as
  # "checked, nothing pending" and is a different claim.
  [[ -n "$(_pkgup_verb PKG_COUNT_PENDING)" ]] || {
    print -r -- -1
    return 0
  }
  # Homebrew's outdated list is stale until the formula index is fetched, and no other
  # archive needs a separate step. Count path only: the LIST path deliberately skips it
  # because the nudge that produced the count already paid for the network.
  refresh="$(_pkgup_verb PKG_COUNT_REFRESH)"
  [[ -n "$refresh" ]] && { ${=refresh} >/dev/null 2>&1 </dev/null }
  # MOST ARCHIVES OVERLOAD THE EXIT STATUS OF THEIR COUNT VERB, which is why Core ignores
  # it by default and simply counts lines: `dnf check-update` exits 100 when updates
  # EXIST, and `pacman -Qu` and `checkupdates` exit non-zero when there are NONE. Reading
  # any of those as failure would report "unknown" on a perfectly healthy box.
  #
  # PKG_COUNT_EXIT_TRUSTED is how an archive says its verb is not like that — that a
  # non-zero exit means it could not answer. Gentoo declares it, because an
  # `emerge --pretend` that cannot resolve is common (blocks, conflicts) and reporting 0
  # there would tell you that you are up to date while Portage is stuck (#756). Capture
  # FIRST and branch on THAT status, then count: piping straight into `grep -c` would take
  # grep's status, which is 1 on the healthy zero-matches case and would emit both a count
  # and a sentinel.
  local _p
  if [[ -n "$(_pkgup_verb PKG_COUNT_EXIT_TRUSTED)" ]]; then
    if _p="$(_pkgup_pending)"; then
      print -r -- "$_p" | grep -c .
    else
      print -r -- -1
    fi
    return 0
  fi
  _pkgup_pending | grep -c .
}

# Best-effort LIST of upgradable package names — the names behind _pkgup_count's number,
# used by `up` to PREVIEW what will change before you confirm. Same non-root,
# no-system-mutation command, minus the count path's network refresh.
# Empty/unknown manager → nothing, so the caller just falls back to a name-only confirm.
_pkgup_list() { _pkgup_pending; }

# Refresh → writes "<count>\n<epoch>" to the cache. Backgrounded by the startup hook, but
# `up` calls it in the FOREGROUND after an upgrade — see _pkgup_count on why that matters.
_pkgup_refresh() {
  local n
  n="$(_pkgup_count 2>/dev/null)"
  n="${n//[^0-9-]/}"
  : "${n:=-1}"
  mkdir -p "${_PKGUP_CACHE:h}"
  print -r -- "$n" >|"$_PKGUP_CACHE"       # >| : force past NO_CLOBBER (cache pre-exists)
  print -r -- "${EPOCHSECONDS:-$(date +%s)}" >>"$_PKGUP_CACHE"
}

# Capture _pkgup_list into a file so a spinner can wrap the slow, SILENT fetch (brew
# outdated / apt -s can stall a second or two with no output) while the caller still gets
# the names. `>|` forces past 10-options.zsh's NO_CLOBBER (the mktemp target pre-exists).
_pkgup_list_to() { _pkgup_list >|"$1" 2>/dev/null; }

# _up_pending — populate the caller's `pending` array with upgradable package names,
# behind a spinner on a TTY (U8). Falls back to a plain capture with no spinner on a
# pipe/non-TTY or when 05-ui.zsh's _core_spin isn't loaded — so captured/scripted runs and
# the unit tests are byte-identical to the old inline `pending=(${(f)"$(_pkgup_list)"})`.
# Relies on zsh dynamic scope: `mgr` + `pending` are the caller's locals.
_up_pending() {
  if (($+functions[_core_spin])) && [[ -t 2 ]]; then
    local _f
    if _f="$(mktemp "${TMPDIR:-/tmp}/up-list.XXXXXX" 2>/dev/null)" && [[ -n "$_f" ]]; then
      _core_spin "checking ${mgr} for upgradable packages" _pkgup_list_to "$_f"
      pending=(${(f)"$(<"$_f")"})
      rm -f "$_f"
      return 0
    fi
  fi
  pending=(${(f)"$(_pkgup_list 2>/dev/null)"})
}

# _up_select <pkg...> — interactive multi-select (U2), printing the chosen names. gum's
# checklist when present, else fzf --multi; non-zero (silent) if neither is available so
# the caller can fall back. The caller already gated this on a TTY.
_up_select() {
  if _core_have gum; then
    printf '%s\n' "$@" | gum choose --no-limit --header "select packages to upgrade (space toggles, enter confirms)"
  elif _core_have fzf; then
    printf '%s\n' "$@" | fzf --multi --prompt "upgrade> " --header "TAB selects · ENTER confirms · ESC cancels"
  else
    return 1
  fi
}

# Manual force: `update-check`
update-check() {
  _core_wants_help "$1" && { _core_help "update-check" "refresh the cached 'updates available' nudge now"; return 0; }
  _pkgup_refresh && _pkgup_notice
}

# Print the one-line nudge from cache (instant; no work).
_pkgup_notice() {
  [[ -r "$_PKGUP_CACHE" ]] || return 0
  # fork-free read: $(<file) is a zsh builtin; (f) splits the 2-line cache on newlines.
  # The split MUST be quoted — "${(@f)...}" — because this cache is POSITIONAL. Unquoted,
  # zsh drops empty fields, so a cache whose count line is empty ("\n<epoch>") collapses to
  # one element and the EPOCH lands in _l[1], the count slot. It then passes the <1-> test
  # below (an epoch is a positive integer) and prints as "1786128391 updates available".
  # No in-repo writer produces that shape any more: _pkgup_refresh normalises an empty
  # result to -1 (`: "${n:=-1}"`), and the startup hook's claim-slot write — which used to
  # be the live source, persisting the empty count it had just read on a box with no cache
  # yet while its background refresh was still in flight — now normalises to -1 too. The
  # quoting stays because it is what makes the read POSITIONALLY safe regardless: a
  # truncated write, a hand-edited cache, or a future writer that forgets the sentinel.
  local -a _l
  _l=("${(@f)$(<"$_PKGUP_CACHE")}")
  local count=${_l[1]:-}
  [[ "$count" == <1-> ]] || return 0 # zsh numeric-range glob: only positive ints
  # NOTE: no backticks in a `print -P` string — under PROMPT_SUBST (which starship and
  # any prompt-substitution prompt enable) print -P command-substitutes them, so
  # `\`up\`` would actually RUN `up`. Single quotes are literal under prompt expansion.
  print -P "%F{$_PKGUP_ACCENT}󰚰 ${count} update$([[ $count -ne 1 ]] && print s) available%f %F{$_PKGUP_MUTED}— run 'up' to apply%f"
}

# ── Startup hook: throttle + background the check, then show cached nudge ──────
# The manager probe (_pkgup_mgr — up to 7 `command -v` forks) used to run on EVERY
# interactive shell, in a synchronous `$()` on the critical path before the first
# prompt — against this stack's own startup-perf thesis (cached inits in 00-tools.zsh,
# deferred plugins, the bench budget gate). It's only NEEDED when the once/day throttle
# window has actually elapsed and we're about to refresh, so it now lives INSIDE that
# branch. The nudge (_pkgup_notice) just reads the cache — no probe — so it still prints
# every shell. (A box with no manager simply has no positive count cached, so the nudge
# stays silent there exactly as before.)
if ((UPDATE_CHECK_ENABLED)); then
  () {
    local now last=0 count=
    now=${EPOCHSECONDS:-$(date +%s)}
    # fork-free read of the 2-line cache ("<count>\n<epoch>") — $(<file) is a builtin.
    # Quoted split (see _pkgup_notice): unquoted, an empty count line is elided and BOTH
    # fields shift — count becomes the epoch and `last` becomes empty, i.e. 0, which also
    # defeats the once-a-day throttle below and re-fires the check on every single shell.
    if [[ -r "$_PKGUP_CACHE" ]]; then
      local -a _l
      _l=("${(@f)$(<"$_PKGUP_CACHE")}")
      count=${_l[1]:-}
      last=${_l[2]:-0}
    fi
    [[ "$last" == <-> ]] || last=0
    # Same fail-closed treatment for the count, because the claim-slot write below persists
    # whatever is in $count. On the FIRST shell of a fresh box there is no cache, so $count
    # is empty and the claim would write "\n<epoch>" — which, read back unquoted, is precisely
    # how the epoch used to become the count. Normalise to the -1 SENTINEL, not to empty: an
    # empty $count leaves the file positionally malformed (the quoted "${(@f)…}" reader split
    # is then the only thing standing between it and that bug), whereas -1 keeps the cache
    # well-formed at rest. It reads back cleanly through the (-|)<-> test above, and
    # _pkgup_notice's <1-> gate rejects it, so the nudge stays silent until the backgrounded
    # _pkgup_refresh lands a real number a moment later. This is what actually closes the
    # race from the writer side; the reader-side quoting closes it from the other.
    [[ "$count" == (-|)<-> ]] || count=-1
    # Throttle FIRST (cheap: a clock read + a cache read, both fork-free), then — only when
    # due — pay for the manager probe. No elapsed window → no probe, the common per-shell path.
    if ((now - last >= UPDATE_CHECK_INTERVAL)) && [[ "$(_pkgup_mgr)" != none ]]; then
      # Claim the slot immediately (bump the timestamp) so sibling shells opened
      # in the same instant don't all fire, then refresh in a disowned subshell.
      mkdir -p "${_PKGUP_CACHE:h}"
      {
        print -r -- "$count"
        print -r -- "$now"
      } >|"$_PKGUP_CACHE" 2>/dev/null    # >| : force past NO_CLOBBER (cache pre-exists)
      { _pkgup_refresh; } &|
    fi
  }
  _pkgup_notice
fi

# ── First-run hint: once per machine, point a new shell at the cheat sheet ──────
# A brand-new clone gives no clue that `serve`, `extract`, `fif`, or the Ctrl-T/G
# widgets exist. Print ONE unobtrusive line the first time, throttled by a sentinel
# (like the nudge above), then never again. Set CORE_WELCOME=0 to silence entirely.
#
# Factored into a named function (not an inline anonymous block) so it's unit-testable
# — the greet-once / sentinel-persists / NO_COLOR contract is exercised by test-core.sh.
# The TTY gate lives at the CALL SITE, so the function itself is pure greet+sentinel
# logic the test can drive with captured stdout.
_core_welcome() {
  emulate -L zsh
  local stamp="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-core/.welcomed"
  [[ -e "$stamp" ]] && return 0
  # Only greet once the sentinel actually PERSISTS — otherwise a read-only state dir
  # (write fails) would re-greet on every shell start, forever. `>|` forces past
  # NO_CLOBBER; `|| return` bails (no greet) when we can't remember we did.
  mkdir -p "${stamp:h}" 2>/dev/null && : >|"$stamp" 2>/dev/null || return 0
  if [[ -z ${NO_COLOR:-} ]]; then
    # Single quotes, not backticks: print -P command-substitutes backticks under
    # PROMPT_SUBST (it would RUN `core`). The raw fallback below is print -r (safe).
    print -P "%F{$_PKGUP_ACCENT}👋 dotfiles Core loaded%f %F{$_PKGUP_MUTED}— run 'core' for functions, keys & maintenance%f"
  else
    print -r -- "👋 dotfiles Core loaded — run 'core' for functions, keys & maintenance"
  fi
}
# Greet only an interactive TERMINAL — a redirected/captured stdout (or the load-order
# smoke test) gets nothing — and only when not disabled.
: "${CORE_WELCOME:=1}"
if ((CORE_WELCOME)) && [[ -t 1 ]]; then _core_welcome; fi

# ── Version-bump nudge: once per Core version, point at `core whatsnew` (#680) ────────
# The nudge above is about PACKAGES; this one is about CORE ITSELF. A host that syncs
# 5.4.0 → 5.5.0 receives hundreds of changed files and is told nothing, which is the gap
# `core whatsnew` closes — but a verb nobody knows exists closes nothing, so a bump
# announces itself ONCE and then stays quiet until the next one.
#
# STANDALONE-SOURCE SAFE. The state helpers and the version-file global live in band 30 and
# this is band 60, so they are present in a real shell (the loader sorts by NN prefix) but
# NOT when the unit suite sources this file alone. Guard on the FUNCTION rather than assume
# it — the $+functions pattern this file already uses for _pkgup_mgr. The := fallbacks below
# serve that same standalone case, exactly as _PKGUP_ACCENT's do.
: "${CORE_WHATSNEW_NUDGE:=1}"
: "${_CORE_VERSION_FILE:=${${(%):-%x}:A:h:h}/core.version}"
: "${_CORE_WHATSNEW_STATE:=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-core/whatsnew}"

_core_whatsnew_nudge() {
  emulate -L zsh
  ((${+functions[_core_whatsnew_state_read]})) || return 0
  [[ -r "$_CORE_VERSION_FILE" ]] || return 0
  local cur
  cur="$(<"$_CORE_VERSION_FILE")"
  cur="${cur//[[:space:]]/}"
  _core_whatsnew_ver_ok "$cur" || return 0

  local ws_seen='' ws_announced='' ws_from=''
  _core_whatsnew_state_read

  # NO STATE AT ALL — a fresh box, or one upgrading from a Core that predates this feature.
  # SEED and stay silent: there is no honest "from" version to name, and a brand-new box has
  # just been greeted by _core_welcome above. This branch is what makes the suppression
  # STRUCTURAL rather than dependent on print order — do not "simplify" it away.
  if [[ -z "$ws_announced" ]]; then
    _core_whatsnew_state_write "${ws_seen:-$cur}" "$cur" "$ws_from"
    return 0
  fi
  [[ "$ws_announced" == "$cur" ]] && return 0
  # Already caught up in another shell — record it and stay quiet.
  if [[ "$ws_seen" == "$cur" ]]; then
    _core_whatsnew_state_write "$ws_seen" "$cur" "$ws_from"
    return 0
  fi
  # PERSIST BEFORE PRINTING, and bail on a failed write — the _core_welcome rule above: a
  # state dir we cannot write to must not make this re-announce on every shell, forever.
  # `seen` is carried through UNCHANGED: announcing is not reading, and collapsing the two
  # is what would make a multi-hop "moved X → Y" understate the jump.
  _core_whatsnew_state_write "$ws_seen" "$cur" "$ws_from" || return 0

  local from="${ws_seen:-$ws_announced}"
  if [[ -z ${NO_COLOR:-} ]]; then
    # Single quotes, not backticks — print -P command-substitutes backticks under
    # PROMPT_SUBST and would RUN `core whatsnew`. $from/$cur are safe to interpolate into a
    # prompt string only because _core_whatsnew_ver_ok allowlists their charset; a stray %
    # would otherwise be a prompt escape.
    print -P "%F{$_PKGUP_ACCENT}✨ Core moved ${from} → ${cur}%f %F{$_PKGUP_MUTED}— run 'core whatsnew' to see what changed%f"
  else
    print -r -- "✨ Core moved ${from} → ${cur} — run 'core whatsnew' to see what changed"
  fi
}
# TTY gate at the CALL SITE, like _core_welcome above: the function stays pure
# compare+stamp+print logic the unit suite can drive with captured stdout.
if ((CORE_WHATSNEW_NUDGE)) && [[ -t 1 ]]; then _core_whatsnew_nudge; fi

# ══════════════════════════════════════════════════════════════════════════════
# up — apply updates. INTERACTIVE by design, and now a DISPATCHER: the verb is Core's
# so every machine has the same muscle memory, but what it runs is resolved through
# _pkgup_verb from the OS layer's os.capabilities declaration — Core names no verb of its own.
#
# `up -y` auto-confirms only where the archive declared a PKG_ASSUME_YES token to append.
# pacman/emerge/apk declare none and so are never auto-confirmed (Arch partial-upgrade,
# Gentoo compile time, musl rolling) — the same three that were named in a `case` here.
# Refreshes the cache afterward so the nudge clears.
#   up        # review & confirm
#   up -y     # auto-confirm where the archive says that is safe
# ══════════════════════════════════════════════════════════════════════════════
up() {
  emulate -L zsh
  # Help BEFORE anything else: without this, `up --help` fell through (not `-y`, so
  # yes=0) and proceeded to actually apply updates — a help flag must never do that.
  _core_wants_help "$1" && { _core_help "up [-y|--yes] [-n|--dry-run] [-i|--interactive]" "apply package updates (interactive; -y auto-confirms where safe; -n only lists; -i pick packages)"; return 0; }
  # Parse EVERY argument (not just $1) so flag ORDER doesn't matter and an unknown
  # flag or stray operand is REJECTED in Core's voice — matching the fail-closed
  # parsers in scripts/*.sh. The old `[[ "$1" == … ]]` form silently ignored a
  # second flag (`up -n -y`) and let a typo like `up --bogus` fall through to a real,
  # privileged update. Usage errors return 1, the convention every Core VERB uses
  # (serve/mkcd/cdup/…); the gate SCRIPTS use 2, but `up` is a verb, not a gate.
  local yes=0 dry=0 interactive=0 arg
  for arg in "$@"; do
    case "$arg" in
    -y | --yes) yes=1 ;;
    -n | --dry-run) dry=1 ;;
    -i | --interactive) interactive=1 ;;
    *)
      _core_err "up: unexpected argument: $arg"
      local _sug
      _sug="$(_core_suggest "$arg" -y --yes -n --dry-run -i --interactive)"
      [[ -n "$_sug" ]] && _core_hint "did you mean ${_sug}?"
      _core_usage "up [-y|--yes] [-n|--dry-run] [-i|--interactive]"
      return 1
      ;;
    esac
  done
  # The three modes are mutually exclusive: -n only inspects, -y auto-applies everything,
  # -i hand-picks. Refuse a contradiction rather than letting one silently win.
  if ((yes + dry + interactive > 1)); then
    _core_err "up: -y/--yes, -n/--dry-run and -i/--interactive are mutually exclusive"
    _core_usage "up [-y|--yes] [-n|--dry-run] [-i|--interactive]"
    return 1
  fi
  # The auto-confirm TOKEN is declared, not assumed. Absent (pacman/emerge/apk, and any
  # archive whose declaration omits it) means `up -y` behaves like `up` and the manager
  # asks for itself — which is exactly what those three did when the flag was hardcoded.
  local -a y=()
  local mgr
  mgr="$(_pkgup_mgr)"
  if [[ "$mgr" == none ]]; then
    _core_errbox "up: no supported package manager found" \
      "why: none of brew/pacman/dnf/zypper/apt/apk/emerge is on PATH" \
      "fix: install your distro's package manager, or update by hand"
    return 1
  fi
  # THE DECLARATION CHECK RUNS BEFORE EVERY MODE BRANCH, and it has to. PKG_UPGRADE is a
  # REQUIRED key, so its absence means this box has no usable declaration at all — and that
  # is a fact about the box, not about the mode you asked for. It used to be checked down at
  # the dispatch, after `-n` and `-i` had already returned, which made `up -n` on an
  # undeclared box print "nothing to upgrade": _up_pending resolves no PKG_COUNT_PENDING,
  # reads the empty list as an empty ANSWER, and asserts the box is up to date when nothing
  # was measured. That is the same 0-vs-unknown confusion the -1 sentinel exists to prevent
  # in _pkgup_count, arriving through a different door. An undeclared box must say so in
  # every mode, including the read-only ones.
  if [[ -z "$(_pkgup_verb PKG_UPGRADE)" ]]; then
    _core_errbox "up: no upgrade verb declared for ${mgr}" \
      "why: this box's os.capabilities names no PKG_UPGRADE (or none is linked at all)" \
      "fix: declare PKG_UPGRADE in os/<os>.capabilities (see core/examples/os.capabilities.example)" \
      "fix: if your OS repo already ships one, re-run its ./bootstrap.sh --links-only"
    return 1
  fi
  # Dry run: show what WOULD upgrade and exit 0, touching nothing — the non-destructive
  # inspect that the count-only nudge and the (interactive-only) pre-confirm preview
  # didn't offer. Uses the same non-root, no-mutation _pkgup_list as the preview below.
  if ((dry)); then
    local -a pending
    _up_pending
    if ((${#pending})); then
      _core_ok "up: ${#pending} package$([[ ${#pending} -ne 1 ]] && echo s) upgradable via ${mgr}:"
      print -rl -- "${(@)pending/#/    }"
    else
      _core_ok "up: nothing to upgrade (via ${mgr})"
    fi
    return 0
  fi
  # ── interactive selection (U2): hand-pick WHICH packages to upgrade. This HONORS the
  # safety model: a partial upgrade is offered only where the archive says one is safe,
  # and refused everywhere else with a pointer back at a full `up`. Needs a TTY + fzf or
  # gum; selecting IS the consent, so the generic confirm below is skipped for -i. ──
  local -a selected=()
  if ((interactive)); then
    # WHO IS SAFE IS DECLARED, NOT LISTED. This was a `case` naming pacman/emerge/apk —
    # the three archives that must update as a whole (Arch partial-break, Gentoo compile
    # time, musl rolling). It is now the ABSENCE of PKG_UPGRADE_PARTIAL, which those three
    # declare no value for. Same three refuse, and two things improve: an archive Core has
    # never heard of gets the safe answer by DEFAULT rather than being waved through, and a
    # distro that gains a safe partial form declares one instead of editing this file.
    #
    # This is why _pkgup_verb treats a declaration as all-or-nothing, and why Core no
    # longer keeps a built-in row to fall back to (#763). If an omitted key fell back to a
    # default for whatever manager happened to be on PATH, a repo that deliberately declared
    # no partial verb would have this check answered for it — the refusal would silently
    # stop refusing.
    if [[ -z "$(_pkgup_verb PKG_UPGRADE_PARTIAL)" ]]; then
      _core_errbox "up -i: ${mgr} does not support safe partial upgrades" \
        "why: ${mgr} must update as a whole — a partial upgrade risks a broken system" \
        "fix: run a full \`up\` (or \`up -y\`) instead"
      return 1
    fi
    # Two distinct -i requirements, checked separately so a message is never misleading:
    # (1) a picker must exist, and (2) we need a real terminal. Checking the picker FIRST
    # means an empty result further down can ONLY mean the user dismissed it (ESC / nothing
    # selected) — never "no tool", which Copilot flagged the old conflated message for.
    if ! _core_have fzf && ! _core_have gum; then
      _core_errbox "up -i: needs fzf or gum for interactive selection" \
        "why: -i opens a checklist to pick packages; neither picker is on PATH" \
        "fix: install fzf (or gum), or run a full \`up\` / \`up -y\` instead"
      return 1
    fi
    [[ -t 0 && -t 2 ]] || {
      _core_err "up -i: needs an interactive terminal"
      return 1
    }
    local -a pending
    _up_pending
    if ((! ${#pending})); then
      _core_ok "up: nothing to upgrade (via ${mgr})"
      return 0
    fi
    selected=("${(@f)$(_up_select "${pending[@]}")}")
    selected=(${selected:#}) # drop empty lines
    if ((! ${#selected})); then
      _core_warn "up: no packages selected — cancelled"
      return 1
    fi
    _core_warn "up: upgrading ${#selected} selected package(s) via ${mgr}"
  fi
  # Defensive pre-confirm (skipped by -y AND by -i, whose selection is the consent): name
  # the manager BEFORE touching the system, so `up` on the wrong box is a one-keystroke
  # abort, not a surprise sync. _core_confirm declines with no TTY, so `up` stays interactive-only.
  if ((! yes && ! interactive)); then
    # Preview WHAT will change, not just the manager: the nudge already shows a count,
    # so surface the names too — informed consent before a privileged, hard-to-undo
    # sync. Best-effort + capped (a 300-package upgrade shouldn't scroll the confirm
    # off-screen) and TTY-only (no point listing when the confirm below will decline).
    if [[ -t 2 ]]; then
      local -a pending
      _up_pending
      if ((${#pending})); then
        local n=${#pending} cap=20
        _core_warn "up: ${n} package$([[ $n -ne 1 ]] && echo s) upgradable via ${mgr}:"
        print -u2 -rl -- "${(@)pending[1,cap]/#/    }"
        # When the preview is capped, close the loop: point at the non-destructive
        # full listing instead of leaving "… and N more" as a dead end.
        ((n > cap)) && {
          print -u2 -- "    … and $((n - cap)) more"
          _core_hint "run \`up -n\` to list all ${n}"
        }
      fi
    fi
    _core_confirm "Apply updates with ${mgr}?" || {
      _core_warn "up: cancelled"
      return 1
    }
  fi
  ((yes)) && y=(${=$(_pkgup_verb PKG_ASSUME_YES)})
  # Graceful interrupt (U3): a Ctrl-C mid-sync would otherwise drop you back at the prompt
  # with no word on what state you're in. localtraps scopes this to `up`; the message
  # reassures that re-running is safe (every manager path is idempotent). The manager
  # itself gets the SIGINT too (shared foreground group) and stops; we just frame it.
  setopt localoptions localtraps
  trap '_core_warn "up: interrupted — safe to re-run \`up\` (every path is idempotent)"; return 130' INT
  local rc=0
  # ── the dispatch ────────────────────────────────────────────────────────────
  # Seven `case` arms became four resolved verbs and one chain. `selected` is non-empty
  # ONLY under -i on an archive that declared a partial verb (above); every other path
  # leaves it empty, so default/-y/-n behaviour is what it always was.
  local -a _pre _cmd _clean
  _pre=(${=$(_pkgup_verb PKG_UPGRADE_PRE)})
  if ((${#selected})); then
    _cmd=(${=$(_pkgup_verb PKG_UPGRADE_PARTIAL)} "${selected[@]}")
  else
    _cmd=(${=$(_pkgup_verb PKG_UPGRADE)} "${y[@]}")
    # Append the auto-confirm token to the cleanup too, not just the upgrade: an
    # unattended `up -y` that then stops to ask whether to autoremove has not been
    # unattended. Only on the FULL path — a partial upgrade removes nothing.
    _clean=(${=$(_pkgup_verb PKG_CLEANUP)})
    ((${#_clean})) && _clean+=("${y[@]}")
  fi
  # No second PKG_UPGRADE guard here: the check above already refused an archive with no
  # upgrade verb, before any mode branch could return. The partial path cannot arrive empty
  # either — `up -i` refuses outright when PKG_UPGRADE_PARTIAL is absent — so a guard on
  # $_cmd at this point would be unreachable, and an unreachable guard reads as protection
  # that is not there.
  # _pkgup_run is a no-op on an empty verb, so the chain is the same shape whether or not
  # this archive has a pre-step or a cleanup step. PKG_UPGRADE_PRE failing ABORTS: an
  # upgrade computed against an index that could not be refreshed is the thing that
  # half-applies a box, and three of the four archives that have a pre-step already
  # chained it this way.
  _pkgup_run "${_pre[@]}" &&
    _pkgup_run "${_cmd[@]}" &&
    _pkgup_run "${_clean[@]}"
  rc=$?
  trap - INT
  # Defensive failure framing (U9): a non-zero manager exit is usually offline or a held
  # package lock — surface that in Core's voice instead of leaving the user with a raw
  # apt/brew traceback and no next step. The refresh still runs so the nudge re-syncs.
  if ((rc != 0)); then
    _core_errbox "up: ${mgr} did not complete (exit ${rc})" \
      "why: most often no network, or another package operation holds the lock" \
      "fix: check connectivity / wait for the other run, then re-run \`up\` (safe to repeat)"
  fi
  _pkgup_refresh 2>/dev/null
  return $rc
}

# ── True hands-off auto-APPLY belongs at the OS layer, not here ───────────────
# The VERBS now live at the OS layer too — os/<os>.capabilities, read by
# zsh/02-capabilities.zsh — so a distro that changes how it upgrades edits its own repo
# rather than this file. What follows is the remaining advice, which is about the OS
# scheduler and was never Core's to run.
#
# If you want a box to update itself unattended, do it with the OS scheduler in
# that distro's repo — NOT in this portable file, and NOT on shell start:
#   • Fedora : dnf-automatic  (set apply_updates=yes; security-only is the sane default)
#   • Debian : unattended-upgrades  (security pocket only)
#   • any    : a systemd timer running `up -y`  (weekly, with Persistent=true)
#   • Arch / Gentoo : DON'T. Update them by hand with `up`.
#   • Kali   : DON'T auto-apply on an engagement box — pin versions, update between ops.
