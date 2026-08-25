# core/zsh/30-functions.zsh
# ──────────────────────────────────────────────────────────────────────────────
# Cross-OS shell functions. Pure POSIX-ish where possible so they behave the
# same on macOS zsh, Linux zsh, and Alpine's busybox-adjacent environment.
# Nothing OS-specific or offensive here — those live in the OS / Offense repos.
# ──────────────────────────────────────────────────────────────────────────────

# Resolved path to the vendored version stamp. core.version sits one dir ABOVE zsh/,
# so from this module: %x = the file being sourced, :A resolves the bootstrap symlink
# back into core/zsh/30-functions.zsh, :h:h climbs to core/, then /core.version. Captured
# at source time (the proven pattern from 10-options.zsh / 55-maint.zsh).
typeset -g _CORE_VERSION_FILE="${${(%):-%x}:A:h:h}/core.version"

# _core_install_prefix <mgr>  → the copy-pasteable "install" command prefix for a
# package manager (the verb differs per distro: apt install / pacman -S / apk add / …).
# Pure mapping, no probing — callers pass the manager from 60-update.zsh's _pkgup_mgr. Used
# by core-doctor (U2) and the command-not-found handler (U1) to turn a missing tool into
# an actionable line instead of a bare ✗. Unknown/none → non-zero, caller stays silent.
_core_install_prefix() {
  case "$1" in
  brew)   print -r -- "brew install" ;;
  pacman) print -r -- "sudo pacman -S" ;;
  dnf)    print -r -- "sudo dnf install" ;;
  zypper) print -r -- "sudo zypper install" ;;
  apt)    print -r -- "sudo apt install" ;;
  apk)    print -r -- "sudo apk add" ;;
  emerge) print -r -- "sudo emerge" ;;
  *)      return 1 ;;
  esac
}

# core-version — print the vendored Core layer's version. Lets you tell WHICH Core a
# given OS repo carries from inside it: the subtree squash records the commit, this
# records the human SemVer (core.version, bumped at release to match the git tag).
core-version() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "core-version" "print the vendored Core layer's version"; return 0; }
  if [[ -r "$_CORE_VERSION_FILE" ]]; then
    print -r -- "dotfiles-core $(<"$_CORE_VERSION_FILE")"
  else
    _core_err "core-version: version stamp not found at $_CORE_VERSION_FILE"
    return 1
  fi
}

# ── core — the umbrella front door (B1) ───────────────────────────────────────
# ONE discoverable namespace over Core's first-party verbs, so a newcomer types a
# single command (`core`) and finds everything instead of having to already know
# `core-help` / `core-doctor` / `up` by name. The standalone verbs still exist
# (muscle memory + their own completions); this is an additive front door, not a
# replacement — and it keeps the generic-sounding verbs (`up`, `serve`) reachable
# under a namespaced form that won't be mistaken for some other tool.
#   core                  → the cheat sheet  (U6: bare `core` is help, never an error)
#   core help [filter]    → core-help
#   core doctor [-v]      → core-doctor
#   core version          → core-version
#   core update [-y|-n]   → up
# The subcommand list is the single source the completion (_core) and the
# unknown-subcommand did-you-mean both read, so they can't drift.
typeset -ga _CORE_SUBCMDS=(help doctor version update)
core() {
  emulate -L zsh
  local sub="${1:-}"
  (($#)) && shift
  case "$sub" in
  "" | -h | --help | help) core-help "$@" ;;
  doctor) core-doctor "$@" ;;
  version | -V | --version) core-version "$@" ;;
  update)
    # `up` lives in 60-update, which the minimal/standard CORE_PROFILEs omit. Dispatch only
    # when it is actually loaded — otherwise report cleanly instead of reaching a missing
    # command (the front door stays availability-aware even when the surface is reduced).
    if (( $+functions[up] )); then
      up "$@"
    else
      _core_err "core update: the updater (\`up\`) is not loaded under CORE_PROFILE=${CORE_PROFILE:-full}"
      _core_hint "it lives in the update/maintenance bands — set CORE_PROFILE=full to enable it"
      return 1
    fi
    ;;
  *)
    _core_err "core: unknown subcommand: ${sub}"
    local _sug
    _sug="$(_core_suggest "$sub" "${_CORE_SUBCMDS[@]}")"
    [[ -n "$_sug" ]] && _core_hint "did you mean core ${_sug}?"
    _core_usage "core <${(j:|:)_CORE_SUBCMDS}>"
    return 1
    ;;
  esac
}

# core-doctor — the shell counterpart to nvim's `:checkhealth gerrrt`: a scannable
# report of which modern-CLI tools Core detected on THIS box and which integrations are
# live, so you can see at a glance what's degraded to a classic fallback. Probes live
# via _core_have (command -v), so it's honest even if 00-tools.zsh hasn't run, and shows
# the RESOLVED binary names (fd vs fdfind, bat vs batcat) — the cross-distro detail that
# silently changes behaviour. Read-only: it inspects, never installs.
# Public verb: render the health report, paging it when taller than the window (a small
# split + core-doctor -v). Same wrapper shape as core-help: TTY-only paging, forced colour
# through the capture, direct render (byte-identical) on a pipe/redirect/the unit tests.
# _core_wired <tool> — is this integration actually WIRED into the live shell, not
# merely installed? Presence (command -v) ≠ active: starship can be on PATH while the
# prompt is plain, atuin installed while Ctrl-E is dead, mise present while the chpwd
# hook never registered. Probe the function/widget each tool's init defines, so
# core-doctor can tell "✓ present" from "✓ present AND working". (Inherited into
# core-doctor's `$()` capture: zsh forks keep functions + the $widgets/$precmd_functions
# params readable.)
# THREE exit states, and the third one is load-bearing: 0 wired, 1 known but idle, 2 the
# name has no arm here at all. Both are "not wired" to the two callers, which test only for
# zero — the split exists so a TEST can tell them apart, because they are different bugs.
# An idle tool is a true report about the box; a name with no arm is a report about US, and
# renders a permanent `○ (idle)` that no amount of installing or configuring can clear.
# _CORE_DOCTOR_WIRED is what the renderers iterate, so a name added there and not here is
# exactly that silent-forever row; the suite asserts every listed name avoids 2.
# Each arm accepts BOTH the historical and the current upstream name: starship and
# carapace renamed the functions their `init` emits, so probing only the old name
# reported a FALSE `○ (idle)` for an integration that was demonstrably driving the
# prompt/completion (measured on starship 1.24.2 → prompt_starship_precmd, and
# carapace-bin 1.5.7 → _carapace_completer; neither emits the old name at all). Keep
# the old names so boxes pinned to older releases keep reporting wired.
#
# THE COMPLETION THREE NEED A DIFFERENT PROBE SHAPE, and getting it wrong is the same scar
# as above. gh/uv/ty are wired by a `compdef` registration, so their wiring fact lives in
# $_comps — NOT in $+functions. The two are not the same claim: $+functions[_gh] says a
# FUNCTION by that name exists, $_comps[gh] says the COMMAND is registered to one, and only
# the second is what makes `gh <TAB>` work. A function can exist without being registered —
# left behind by a sourced script, or marked autoloadable by compinit — so the function probe
# can report wired when nothing is. (Measured, since it is the obvious thing to reach for and
# it is misleading in the other direction too: an fpath-autoloaded `_uv` reports
# $+functions[_uv] == 1 while its body is still the `builtin autoload -XU` stub. So the
# function probe is not merely weaker here, it answers a different question.) Tested for
# NON-EMPTY rather than `== _gh` on purpose — when carapace legitimately owns the command the
# row is still honestly wired, just not by the tool's own script.
#
# direnv probes the hook it installs. Both spellings, for the same reason as the pairs above:
# `direnv hook zsh` defines _direnv_hook AND prepends it to precmd_functions/chpwd_functions,
# and a future release could plausibly keep one without the other.
_core_wired() {
  case "$1" in
  starship) (( $+functions[starship_precmd] )) || (( $+functions[prompt_starship_precmd] )) ;;
  atuin)    [[ -n ${widgets[atuin-search]:-} ]] || (( $+functions[_atuin_precmd] )) ;;
  mise)     (( $+functions[_mise_hook] )) || (( $+functions[__mise_hook] )) ;;
  zoxide)   (( $+functions[__zoxide_hook] )) || (( $+functions[__zoxide_z] )) ;;
  carapace) (( $+functions[_carapace] )) || (( $+functions[_carapace_completer] )) ;;
  direnv)   (( $+functions[_direnv_hook] )) || (( ${precmd_functions[(I)_direnv_hook]} )) ;;
  gh)       [[ -n ${_comps[gh]:-} ]] ;;
  uv)       [[ -n ${_comps[uv]:-} ]] ;;
  ty)       [[ -n ${_comps[ty]:-} ]] ;;
  *) return 2 ;;  # no arm for this name — see the three-state note above
  esac
}

# ── The doctor's tool inventory — ONE definition, read by BOTH renderers ──────────────
# Flat label/list pairs. zsh arrays are 1-based, so the ODD indices (1, 3, …) hold the group
# labels and the EVEN ones (2, 4, …) hold that group's space-separated tools — which is why
# the human report walks it from 1 and the --json flattener walks it from 2, both stepping 2.
# The report iterates it directly; _core_doctor_json flattens it. It used to be TWO hand-synced
# literals, and they drifted in both directions at once: twelve tools that 00-tools.zsh
# detects — ast-grep, difft, gping, hyperfine, jj, jnv, ouch, shellcheck, shfmt, tldr, uv,
# viddy — were reported by neither, while the pair could also disagree with each other with
# nothing to catch it. One source removes the second failure by construction; the parity
# test in scripts/test-core.sh now guards against a second literal being reintroduced.
#
# Membership rule, so additions land somewhere defensible rather than at the end:
#   modern CLI   — replaces a classic Unix command (ls, cat, du, ps, top, df, watch, man)
#   integrations — wires into the shell itself: prompt, hooks, widgets, completion, sessions
#   data / net   — reads/transforms data, or talks to the network
#   dev / repo   — writing and versioning code: lint, format, benchmark, search, diff, VCS
# fd/bat appear under their CANONICAL names; 00-tools.zsh resolves fdfind/batcat into
# FD_BIN/BAT_BIN, _core_doctor_bin (just below) probes the resolved binary, and the
# "resolved" line at the bottom of the report shows which one won.
# The terminal browser is deliberately absent: BROWSER_BIN picks from w3m/lynx/links2/links/
# elinks, so there is no single name to probe — a fixed `w3m` row would read ✗ on a box
# that has lynx and is working fine.
typeset -ga _CORE_DOCTOR_GROUPS=(
  "modern CLI"   "eza bat fd rg fzf zoxide delta dust duf procs btop yazi viddy tldr ouch"
  "integrations" "starship atuin mise carapace gum sesh"
  "data / net"   "jq yq jnv gron sd xh doggo gping glow lnav op"
  "dev / repo"   "ast-grep shellcheck shfmt hyperfine watchexec uv jj difft git-absorb"
)

# ── Which of those rows Core actually EXPECTS a bootstrap to install ──────────────────
# The third state. Every row above used to render as ✓ or ✗, and PORTING-MATRIX.md's footnote
# ²¹ ("Available, not installed") says a documented subset of them is installed by NO Linux
# repo's packages.txt and by NO bootstrap.sh — deliberately. Those two facts contradicted each
# other: a correctly-provisioned box reported a wall of ✗ for tools that were never in scope.
#
# ✗ is the doctor's only alarm channel. When a healthy box shows nine permanent ones, the
# operator stops reading them — and a REAL regression, a tool that was installed and broke,
# lands in the same visual bucket as the ones that were never coming. That is alarm fatigue
# engineered into the tool, and it also made the doctor unusable as a provisioning gate: there
# was no exit code and no --json shape meaning "this box got everything it was supposed to
# get" (#513).
#
# MEMBERSHIP IS A RULE, NOT A JUDGEMENT CALL: a tool belongs here iff its Tool cell in
# PORTING-MATRIX.md carries a ROW-level ²¹, or one of the two footnotes ²¹ itself names as
# "the same shape" (¹⁷ jnv, ¹⁹ gping). scripts/test-core.sh re-derives this list from the
# matrix and fails if the two disagree — so the prose stops being hand-maintained, which is
# the gap that let a probed tool ship with no matrix row at all (#514).
#
# THE KNOWN LIMITATION, recorded so it is not rediscovered: `jj` and `ast-grep` carry ²¹ only
# in the Gentoo and Kali CELLS — Arch, openSUSE and Alpine package and install them. A
# Core-side list cannot express "opt-in over there, expected here", and muting them globally
# would hide a genuine ✗ on the repos that do install them. So they stay expected, and are
# ✗ on the two repos where they are not.
#
# THE PER-REPO ANSWER IS NAMED AND LANDING: `TOOLS_OPTIN` in the OS layer's os.capabilities
# declaration (#663), read into $_CORE_CAP by zsh/02-capabilities.zsh. This comment used to
# specify a different artifact — "an `install/expected-tools.txt` each bootstrap ships" — and
# v5 deliberately decided against it: one declaration per OS repo carrying the package verbs,
# the scheduler AND the tool split beats a second per-repo file with its own path, its own
# reader and its own way to go stale. Recorded rather than silently reworded, because a Core
# comment specifying a file the system decided not to build is exactly the drift #662 exists
# to stop.
#
# So the array below is NOT a placeholder awaiting that file. It is the DEFAULT a box falls
# back to when its OS repo declares no TOOLS_OPTIN — which, until #666 wires the doctor
# through $_CORE_CAP, is still every box.
typeset -ga _CORE_DOCTOR_OPTIN=(
  lnav hyperfine watchexec shellcheck shfmt ouch git-absorb jnv gping
)

# _core_doctor_optin <tool> → 0 if the tool is opt-in (absence is expected, never an alarm).
# A function rather than an inline loop because both renderers ask, and they must not drift.
_core_doctor_optin() {
  local _o
  for _o in $_CORE_DOCTOR_OPTIN; do [[ "$_o" == "$1" ]] && return 0; done
  return 1
}

# _core_doctor_unwired <tool> → 0 iff Core's band-00 detection MISSED this tool.
#
# Callers ask only about tools the LIVE probe has already found, so a 0 here means exactly
# "it is here now, but it was not here when Core decided what to wire" — no alias, no shell
# init, no HAVE_* flag, while the row above says ✓. The cause is always the same: a
# directory that joined PATH after band 00 (80-os.zsh, an 85-* role fragment, 99-local.zsh,
# or mise's per-directory chpwd hook), or an install that happened after this shell started.
#
# TWO gates, and both matter:
#   1. No ledger at all → Core's detection never ran in this shell (the function unit
#      harness sources ui+functions alone; so does any script, or `zsh -c`). Make NO claim:
#      reporting 41 unwired tools there would be worse than saying nothing.
#   2. No entry for this row → Core does not probe this tool. Also no claim. Without this,
#      every row the doctor knows and 00-tools.zsh does not would false-positive.
# Checked in the render and in --json as well, so the two renderers cannot disagree about
# whether the axis applies.
#
# The MIRROR case lives in _core_doctor_stale below (#631) — same two gates, comparison
# flipped, asked from the other branch of the render loop.
_core_doctor_unwired() {
  (( ${+_CORE_PROBED} ))     || return 1   # detection never ran here
  (( ${+_CORE_PROBED[$1]} )) || return 1   # Core does not probe this row
  [[ ${_CORE_PROBED[$1]} == 1 ]] && return 1
  return 0
}

# _core_doctor_stale <tool> → 0 iff Core's band-00 detection FOUND this tool and it is now GONE.
#
# The exact mirror of _core_doctor_unwired: the same two ledger gates, the comparison flipped,
# and asked from the ABSENT branch of the render loop rather than the present one. So a 0 here
# means "Core saw it at band 00, set HAVE_*, and let 20-aliases.zsh define an alias against it —
# and the binary is not on PATH any more". PATH shrinking mid-session is not exotic here: mise's
# chpwd hook rewrites PATH on every `cd` (00-tools.zsh), so a toolchain two directories away can
# take a binary with it.
#
# WHY THIS IS WORTH REPORTING AT ALL, given the row already renders ✗ and the failure is loud:
# it is only loud for tools that shadow nothing. Six aliases shadow CLASSIC commands — `ps`,
# `top`/`htop`, `watch`, `df`, `ping`, `help` — and there a stale flag does not fail to give you
# `procs`, it BREAKS `ps`, with a message naming a binary the user never typed. core-doctor is
# what you reach for then, and ✗ procs does not connect to "your ps is broken". The block that
# consumes this makes the connection by naming the ALIASES, not the tools (#631).
_core_doctor_stale() {
  (( ${+_CORE_PROBED} ))     || return 1   # detection never ran here
  (( ${+_CORE_PROBED[$1]} )) || return 1   # Core does not probe this row
  [[ ${_CORE_PROBED[$1]} == 1 ]] || return 1
  return 0
}

# ── The doctor's WIRABLE inventory — ONE definition, read by BOTH renderers ───────────
# The same single-source rule as _CORE_DOCTOR_GROUPS above, applied to the other axis. This
# list lived as two `local -a` literals — one in _core_doctor_json, one in
# _core_doctor_render — plus the `case` arms of _core_wired: three copies hand-synced with
# nothing to catch a drift. The render⇄json parity test cannot see this list at all, because
# it stubs _core_have false, which makes the "integrations wired" block skip every entry by
# construction. So the one seam the tool axis had a guard for, the wired axis had neither a
# single source NOR a test (#447).
#
# NOT folded into _CORE_DOCTOR_GROUPS' "integrations" group, which is a superset: gum and
# sesh belong there (they ARE integrations a reader wants presence for) but neither
# registers a hook, widget or completer, so neither is wirable and both would render a
# permanent `○ (idle)`. Presence and wiredness are different questions about different sets.
#
# Membership rule: a tool belongs here iff its own `init`/activation defines something
# observable in THIS shell — a function, a widget, a precmd hook — that _core_wired can
# probe. If you cannot name the thing to probe, it is not wirable; add it to a group above
# and stop there. Adding a name here without an arm in _core_wired fails the suite.
# direnv/gh/uv/ty joined in #581: Core hooks direnv in zsh/00-tools.zsh and registers the
# three completions in zsh/45-plugins.zsh, so these are four integrations Core itself drives
# and the doctor said nothing about. Each names its probe easily, which is the membership
# rule above: direnv → _direnv_hook, and gh/uv/ty → their $_comps entry.
#
# PRESENCE ROWS ARE DELIBERATELY NOT ADDED HERE. Wiredness and presence are different
# questions about different sets (see the note above), and a _CORE_DOCTOR_GROUPS row for
# gh/ty would render a permanent ✗: no Linux repo's packages.txt installs either, so they
# belong in _CORE_DOCTOR_OPTIN — which is DERIVED from PORTING-MATRIX.md's footnote ²¹ and
# asserted against it, so muting them is a matrix change, not a list edit. Adding the rows
# without that would manufacture exactly the alarm fatigue the opt-in state exists to stop.
typeset -ga _CORE_DOCTOR_WIRED=(starship atuin mise zoxide carapace direnv gh uv ty)

# _core_doctor_bin <tool> → REPLY = the binary that actually BACKS that row.
# The rows above are canonical names, but two of them are not the binary on every distro:
# Debian/Ubuntu/Kali ship fd as `fdfind` and bat as `batcat`, and 00-tools.zsh resolves
# those into FD_BIN/BAT_BIN. Probing the canonical name therefore reported `✗ bat` for a
# tool that was installed and fully wired — two lines above the `resolved` section printing
# the very binary it had found. `fd` escaped that only by ACCIDENT: 20-aliases.zsh defines
# `alias fd="$FD_BIN"` and zsh's `command -v` resolves aliases, so the ✓ came from the alias
# rather than from PATH. That accident did not extend to the -v readout, which forks
# `"$tool" --version` — a PARAMETER expansion, never alias-expanded — so `core-doctor -v`
# printed a bare versionless `✓ fd` on Debian and swallowed the error. Resolving here fixes
# presence and version together, and rests on FD_BIN/BAT_BIN rather than on an alias.
# Sets REPLY instead of printing: $(…) forks, and this is called once per tool per report.
# ONE definition, called by BOTH the render and --json, so the two cannot drift (same rule
# as _CORE_DOCTOR_GROUPS above). The :- fallbacks keep the answer byte-identical when
# 00-tools.zsh has not run — the unit harness sources ui+functions alone.
# A SECOND class joined fd/bat later: a git SUBCOMMAND, which is not on $PATH at all on the
# Debian family (the `git-*` arm below, #424). #447 proposed instead giving _core_have a
# tri-state override hook; rejected, because _core_have is a general primitive that 05-ui.zsh
# calls on every confirm/spin/gum probe — this taxes one command's inventory rather than
# every call site — and because an override answering "present" for `git-absorb` would hand a
# caller a name it cannot execute, where resolving to a path hands back something runnable.
#
# _core_git_exec_path → REPLY = git's exec-path (its libexec/git-core), "" when there is no
# git or it will not answer. THE ONE FORK the tool probe is allowed, and it fires only when a
# `git-*` row has already MISSED on $PATH, so a box that never had the bug pays nothing.
# Cached so a report with several git subcommands, and the two renderers, ask at most once.
# `${+_CORE_GIT_EXEC_PATH}` tests that the parameter EXISTS, not that it is non-empty: a box
# with no git caches the EMPTY answer, and an emptiness test would re-fork on every later row.
# typeset -g, because every caller is already inside a function that has `local`-ed its own
# scratch (REPLY/bin/_v in _core_doctor_render, REPLY in _core_doctor_json) — a plain
# assignment would die with that frame and the cache would not survive one loop iteration.
# Lifetime is ONE REPORT, not one shell, and that is ENFORCED by core-doctor unsetting the
# cache on entry — it cannot be left to the subshell. Only the TTY render runs inside a `$(…)`
# capture; `--json` and the non-TTY path both run in the caller's shell, so without the unset
# an interactive session would carry the answer — including a cached EMPTY one — across a git
# install or a PATH/GIT_EXEC_PATH change and report the row wrong for the rest of the session.
# `command git`, not `git`: the real binary's account of its own layout.
_core_git_exec_path() {
  if ((!${+_CORE_GIT_EXEC_PATH})); then
    typeset -g _CORE_GIT_EXEC_PATH=""
    _core_have git && _CORE_GIT_EXEC_PATH="$(command git --exec-path 2>/dev/null)"
  fi
  REPLY="$_CORE_GIT_EXEC_PATH"
}

_core_doctor_bin() {
  case "$1" in
  fd)  REPLY="${FD_BIN:-fd}" ;;
  bat) REPLY="${BAT_BIN:-bat}" ;;
  git-*)
    # A git SUBCOMMAND (#424) — the second shape where the canonical row name is not a name
    # on $PATH. The Debian family packages these into git's exec-path and keeps that
    # directory OFF $PATH deliberately, because git dispatches `git absorb` by looking there
    # itself. Verified on Kali, git-absorb 0.6.17-2+b4: `dpkg -L` lists the exec-path binary
    # and a man page and NOTHING in a PATH dir, `command -v git-absorb` finds nothing, and
    # `git absorb` works. So the doctor printed `✗` for a tool the reader had just used —
    # #418's failure one directory further out.
    #
    # PATH FIRST, always: where the bare name hits (Arch, Alpine, Gentoo, Homebrew, macOS)
    # this costs one lookup and no fork, and only a MISS asks git where its subcommands live.
    # Probed with _core_have and NOT a bare `command -v`, so that a stubbed _core_have stays
    # authoritative — scripts/test-core.sh's git-absorb --json case stubs exactly that — and
    # so the short-circuit is honoured in the unit harness.
    #
    # The answer is an ABSOLUTE path, which is what BOTH consumers need: `command -v` on a
    # path succeeds for an executable file and fails for a non-executable one, so presence
    # stays as honest as the PATH probe; and the -v readout forks `"$bin" --version`, which a
    # bare `git-absorb` could not do at all on this family. It never reaches the report — the
    # render and the --json keys both print $tool, the canonical name.
    #
    # REPLY doubles as the scratch for the exec-path (this function keeps no locals, so the
    # `local`-in-a-loop hazard documented in _core_doctor_render cannot appear here); the
    # else-branch re-states the canonical name on the miss path so an absent tool still
    # reports under the name the reader would install.
    REPLY="$1"
    if ! _core_have "$1"; then
      _core_git_exec_path
      if [[ -n "$REPLY" && -x "$REPLY/$1" ]]; then REPLY="$REPLY/$1"; else REPLY="$1"; fi
    fi
    ;;
  *)   REPLY="$1" ;;
  esac
}

# _core_doctor_json — machine-readable health (B12). The gate scripts emit --json; the
# RUNTIME health verb did not, so a statusline/editor/CI could not consume it. One object
# on stdout, never paged: {version, tools{name:bool}, wired{name:bool},
# atuin_daemon{degraded:bool, was_up:bool}, resolved{…}}.
# Pure zsh (no python): tool names are a fixed list of literals with no quotes, backslashes
# or control characters in them, so no escaping is needed. They are NOT all bare identifiers
# — `git-absorb` has a hyphen. The key is emitted quoted, so the JSON is valid and any real
# parser is fine; only jq's dot shorthand isn't, because it reads `.tools.git-absorb` as a
# subtraction. Consumers write `.tools["git-absorb"]`.
_core_doctor_json() {
  emulate -L zsh
  local ver="unknown"
  [[ -r "$_CORE_VERSION_FILE" ]] && ver="$(<"$_CORE_VERSION_FILE")"
  # Flattened from _CORE_DOCTOR_GROUPS rather than restated, so this object and the human
  # report cannot disagree. Group order is preserved, which keeps the key order stable for
  # anything diffing successive --json runs.
  local -a alltools=()
  local _gi
  for ((_gi = 2; _gi <= ${#_CORE_DOCTOR_GROUPS}; _gi += 2)); do
    alltools+=(${=_CORE_DOCTOR_GROUPS[_gi]})
  done
  # Read from the single source, not restated — same rule as the tools object above.
  local -a wir=("${_CORE_DOCTOR_WIRED[@]}")
  # REPLY is declared HERE, with the rest — _core_doctor_bin writes it, and `local` inside
  # the loop would re-declare an already-set parameter (see the `local … _v` note in
  # _core_doctor_render for what that costs).
  # `missed` joins the declarations here for the same reason REPLY does — it is appended to
  # inside the loop, and a `local` there would re-declare a set parameter.
  local t first=1 REPLY
  local -a missed=() gone=()
  print -rn -- "{\"version\":\"${ver}\",\"tools\":{"
  for t in $alltools; do
    ((first)) || print -rn -- ","; first=0
    # Probe the RESOLVED binary, but key the object on the CANONICAL name: consumers and
    # the render⇄json parity test both look up `.tools.bat`, not `.tools.batcat`.
    _core_doctor_bin "$t"
    if _core_have "$REPLY"; then
      print -rn -- "\"$t\":true"
      # Collected on the present branch of the loop that is already running, rather than in
      # a second pass: the question only applies to a tool that IS here now (#545).
      _core_doctor_unwired "$t" && missed+=("$t")
    else
      print -rn -- "\"$t\":false"
      # The mirror, on the ABSENT branch of the same loop and for the same reason: the
      # question only applies to a tool that is NOT here now (#631).
      _core_doctor_stale "$t" && gone+=("$t")
    fi
  done
  # "expected" is what makes this object assertable (#513). "tools" alone can only answer
  # "is every tool present", which is false on every correctly-provisioned box — footnote ²¹
  # names a subset no bootstrap installs. With this a provisioning gate can ask the question
  # that actually has a right answer:
  #
  #   jq -e 'all(.expected | to_entries[]; .value | not or (.key as $k | $tools[$k]))'
  #   …or plainly: no tool with expected=true may have tools=false.
  #
  # A SEPARATE object rather than turning "tools" into a tri-state string: "tools" is a
  # published shape with consumers, and widening bool→enum would break every one of them for
  # a question they were not asking. Same key set and same order as "tools", so the two zip.
  # The exit code deliberately does not move — core-doctor is read-only diagnostics and
  # returns 0 on a bare box by design; a gate reads this field, not $?.
  print -rn -- "},\"expected\":{"
  first=1
  for t in $alltools; do
    ((first)) || print -rn -- ","; first=0
    if _core_doctor_optin "$t"; then print -rn -- "\"$t\":false"; else print -rn -- "\"$t\":true"; fi
  done
  print -rn -- "},\"wired\":{"
  first=1
  for t in $wir; do
    ((first)) || print -rn -- ","; first=0
    if _core_have "$t" && _core_wired "$t"; then print -rn -- "\"$t\":true"; else print -rn -- "\"$t\":false"; fi
  done
  # atuin's daemon state: the one Core integration that can change under a LIVE shell, and the
  # one whose failure mode is silent data loss (00-tools.zsh). `degraded` is the actionable bit;
  # `was_up` separates a daemon that died mid-session (the user got one warning) from one that
  # was never reachable (silent by design). A statusline is exactly the consumer that should be
  # able to see a degraded shell without the user going looking. Both false on the machines that
  # never opted in. NOT exposing an `opted_in` field on purpose: after degradation
  # ATUIN_DAEMON__ENABLED reads false, so it would lie.
  # Detection divergence (#545). "ran" is the consumer's "this shell can answer the
  # question at all" flag — false in any context where 00-tools.zsh never loaded (a script,
  # `zsh -c`, the function unit harness), where "missed" is necessarily empty and means
  # nothing. The gate a provisioning script wants is `jq -e '.detection.missed == []'`.
  #
  # NOT named "wiring": this object sits beside "wired", which answers an unrelated question
  # (did an integration register its hooks in this shell), and a consumer reading both
  # `.wired` and `.wiring.*` would conflate them.
  print -rn -- "},\"detection\":{\"ran\":"
  if (( ${+_CORE_PROBED} )); then print -rn -- true; else print -rn -- false; fi
  print -rn -- ",\"missed\":["
  first=1
  for t in $missed; do
    ((first)) || print -rn -- ","; first=0
    print -rn -- "\"$t\""
  done
  # "stale" is the mirror of "missed" and gets its OWN key rather than widening either
  # (#631) — same reason "expected" is not folded into "tools": both are published shapes
  # with consumers, and a reader asking "did Core miss anything" must not have to filter a
  # merged list. The two are disjoint by construction: a tool is present-and-unprobed or
  # absent-and-probed, never both. `jq -e '.detection.stale == []'` is the gate.
  print -rn -- "],\"stale\":["
  first=1
  for t in $gone; do
    ((first)) || print -rn -- ","; first=0
    print -rn -- "\"$t\""
  done
  print -rn -- "]"
  print -rn -- "},\"atuin_daemon\":{\"degraded\":"
  if [[ -n ${_CORE_ATUIN_DAEMON_DEGRADED:-} ]]; then print -rn -- true; else print -rn -- false; fi
  print -rn -- ",\"was_up\":"
  if [[ -n ${_CORE_ATUIN_DAEMON_WAS_UP:-} ]]; then print -rn -- true; else print -rn -- false; fi
  print -rn -- "},\"resolved\":{\"fd\":\"${FD_BIN:-}\",\"bat\":\"${BAT_BIN:-}\""
  (($+functions[_pkgup_mgr])) && print -rn -- ",\"pkg_manager\":\"$(_pkgup_mgr)\""
  print -r -- "}}"
}

core-doctor() {
  emulate -L zsh
  # Drop the exec-path cache so THIS report re-derives it (at most once — see
  # _core_git_exec_path). Only the TTY branch below runs the render in a `$(…)` subshell that
  # would discard it anyway; --json and the non-TTY path run right here, so a cache left
  # standing would outlive its report and answer for a box that has since installed git,
  # installed the subcommand, or moved GIT_EXEC_PATH. A health check that goes stale is worse
  # than one that forks once.
  unset _CORE_GIT_EXEC_PATH
  # --json (anywhere on the line) → machine-readable, never paged (B12).
  local a
  for a in "$@"; do [[ "$a" == --json ]] && { _core_doctor_json; return 0; }; done
  if [[ -t 1 && -z ${CORE_NO_PAGER:-} ]]; then
    local _out
    _out="$(_CORE_FORCE_COLOR=1 _core_doctor_render "$@")"
    local _rc=$?
    _core_page "$_out"
    return $_rc
  fi
  _core_doctor_render "$@"
}
_core_doctor_render() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "core-doctor [-v|--versions] [--json]" "report Core's detected tools + which integrations are actually wired (-v adds versions; --json for machines)"; return 0; }
  # Default stays fast + scannable (one `command -v` per tool). -v/--versions opts INTO a
  # version readout next to each ✓ — useful for spotting an ancient fzf/bat — at the cost of
  # one `--version` fork per present tool, so it is deliberately NOT the default. --json is
  # intercepted by the wrapper before here, so it never reaches this arm.
  local show_versions=0
  case "${1:-}" in
  -v | --versions) show_versions=1 ;;
  "") ;;
  *)
    _core_err "core-doctor: unexpected argument: $1"
    _core_usage "core-doctor [-v|--versions] [--json]"
    return 1
    ;;
  esac
  local g='' c='' d='' r='' y=''
  if [[ ( -t 1 || -n ${_CORE_FORCE_COLOR:-} ) && -z ${NO_COLOR:-} ]]; then
    # green/cyan stay local (doctor's own ✓/group semantics); the dim muted reuses
    # 05-ui.zsh's canonical $_CORE_C_MUTED so "muted grey" has one definition Core-wide.
    # y is the ⚠ modifier on a present-but-unwired row (#545) — the same borrow pattern.
    g=$'\e[32m' c=$'\e[36m' d="${_CORE_C_MUTED:-$'\e[2;37m'}" r=$'\e[0m'
    y="${_CORE_C_YEL:-$'\e[33m'}"
  fi
  local ver="unknown"
  [[ -r "$_CORE_VERSION_FILE" ]] && ver="$(<"$_CORE_VERSION_FILE")"
  # Legend scoped to what is actually true. "✗ falls back to classic" held when the report
  # was mostly command replacements, but most of the inventory is now opt-in tooling that
  # shadows nothing — there is no classic `ast-grep` or `jj` to degrade to, so a blanket
  # promise of a fallback misread every ✗ outside the first group.
  print -r -- "${c}dotfiles-core ${ver}${r} ${d}— core-doctor (✓ present | ✗ expected but missing | · opt-in, not installed)${r}"

  # Grouped tool report, straight off the one inventory defined above _core_doctor_json.
  # A tool is ✓ when it resolves on PATH, ✗ (dimmed) when it is absent — which for the
  # replacements in "modern CLI" means Core degrades to the classic command, and for the
  # opt-in tools elsewhere simply means the verb is unavailable.
  local -a groups=("${_CORE_DOCTOR_GROUPS[@]}")
  # _v is declared HERE, not at its use site inside the loop below. zsh prints `name=value`
  # when `local` re-declares a parameter that already holds one (TYPESET_SILENT is off under
  # `emulate -L zsh`), so a `local _v` inside the loop dumped a literal `_v=0.26.1` line into
  # the report on every iteration after the first — `core-doctor -v` rendered garbage instead
  # of versions. Nothing caught it because no test drove the -v path.
  # `bin` and REPLY join _v here for the same reason: _core_doctor_bin writes REPLY, and
  # both are assigned once per tool inside the loop.
  local gi tool line _v bin mark REPLY
  # `mark` joins _v/bin/REPLY up here for the reason spelled out just above: a `local` that
  # re-declares an already-set parameter INSIDE the loop makes zsh print `name=value` into
  # the report. That shipped once already, as literal `_v=0.26.1` lines.
  local -a missing=() optin=() unwired=() latedirs=() stale=()
  for ((gi = 1; gi <= ${#groups}; gi += 2)); do
    print -r -- "${c}${groups[gi]}${r}"
    line=""
    for tool in ${=groups[gi + 1]}; do
      # `tool` is what we PRINT (the canonical name); `bin` is what we PROBE and fork.
      _core_doctor_bin "$tool"; bin=$REPLY
      if _core_have "$bin"; then
        # ⚠ is a MODIFIER on ✓, not a fourth presence state: the tool genuinely IS present,
        # so ✓ is not wrong — what is wrong is reading it as "Core wired this". Rendering it
        # as an annotation (the same shape the atuin-daemon note below uses) keeps the
        # legend's three states intact, and keeps the render⇄json parity test blind to it by
        # construction: that test matches `[✓✗·] (name)`, so a suffixed glyph still yields
        # exactly the tool name.
        mark=""
        if _core_doctor_unwired "$tool"; then mark="${y}⚠${r}"; unwired+=("$tool"); fi
        if ((show_versions)); then
          # Best-effort, like setup.sh's _doctor: pull the first semver-ish token from
          # the tool's own --version. Unparseable → just the ✓ (never an error). Assigned,
          # never re-declared: see the `local … _v` note above the loop.
          _v="$("$bin" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"
          line+="  ${g}✓${r} ${tool}${mark}${_v:+ ${d}${_v}${r}}"
        else
          line+="  ${g}✓${r} ${tool}${mark}"
        fi
      elif _core_doctor_optin "$tool"; then
        # ABSENT AND THAT IS CORRECT — footnote ²¹. Rendered, because "you could have this"
        # is worth knowing, but with a glyph that is not an alarm and without joining the
        # install list below. `·` rather than the `○` used in the wired block further down:
        # there ○ means "installed but IDLE", and one glyph carrying two meanings on one
        # screen is precisely the legibility problem this change is about.
        line+="  ${d}· ${tool}${r}"; optin+=("$tool")
        # An opt-in tool can go stale too — the hazard is the HAVE_* flag and the alias it
        # gated, and neither cares that absence is "correct" for this row (#631).
        _core_doctor_stale "$tool" && stale+=("$tool")
      else
        line+="  ${d}✗ ${tool}${r}"; missing+=("$tool")
        _core_doctor_stale "$tool" && stale+=("$tool")
      fi
    done
    print -r -- " $line"
  done

  # Name the ✗'d tools and give THIS box's install verb (U2), so the reader is not left
  # looking each one up. Gated on 60-update.zsh's _pkgup_mgr being loaded (it isn't in the
  # unit harness, which sources ui+functions alone) and on a known manager.
  #
  # What this deliberately does NOT print is `<prefix> <every missing tool>` as one line.
  # That read as paste-ready and was not: apt/dnf/zypper/pacman all abort the WHOLE
  # transaction on a single unresolvable name, so one bad entry blocked the good ones too.
  # And bad entries are the common case, not the edge — these are COMMAND names, while the
  # package is often called something else (rg=ripgrep, delta=git-delta, fd=fd-find on
  # Debian, dust=du-dust, yq=go-yq, op=1password-cli), and several tools are not packaged
  # at all on some targets (sesh anywhere, watchexec on Fedora/Kali, carapace and yazi on
  # Kali). At least 12 of the names in `groups` above break the line on some box, so an
  # exclusion list cannot rescue it — and the alternative, a command→package map per
  # distro, is a rot-prone duplicate of PORTING-MATRIX.md, which is where that data lives.
  # So: print the names as names, the verb as a template, and point at the matrix.
  if ((${#missing})) && (($+functions[_pkgup_mgr])); then
    local _mgr _pfx
    _mgr="$(_pkgup_mgr)"
    if _pfx="$(_core_install_prefix "$_mgr")"; then
      print -r -- "${c}install missing${r}"
      print -r -- "  ${d}${missing[*]}${r}"
      print -r -- "  ${d}those are command names — the package is often called something else${r}"
      print -r -- "  ${d}(rg=ripgrep, delta=git-delta) and some aren't packaged on every distro,${r}"
      print -r -- "  ${d}so install per tool: ${_pfx} <pkg>${r}"
      print -r -- "  ${d}see core/PORTING-MATRIX.md for the per-tool name and install path${r}"
    fi
  fi
  # The opt-in rows get ONE line, not the block above. They are not a problem to fix, so
  # they do not get a remedy; naming them is only so `·` is legible without the legend.
  if ((${#optin})); then
    print -r -- "${c}opt-in${r}"
    print -r -- "  ${d}${optin[*]}${r}"
    print -r -- "  ${d}no bootstrap installs these — · is informational, never a failure${r}"
  fi

  # Present, but Core never wired it (#545). Placed AFTER the opt-in block deliberately:
  # the render⇄json parity test splits the body on "\nopt-in" and discards everything past
  # it, so anything here is invisible to that comparison structurally, not just because the
  # names are printed bare.
  #
  # The hint names the CAUSE, which is what makes it actionable. A directory that is on PATH
  # now but was not at band 00 is a load-order problem the OS/role layer can fix by moving
  # the prepend earlier; a tool whose directory was already there was simply installed after
  # this shell started, and a new shell is the whole remedy.
  if ((${#unwired})); then
    print -r -- "${c}not wired${r}"
    print -r -- "  ${d}${unwired[*]}${r}"
    print -r -- "  ${d}present now, but absent when Core ran detection — no alias, no init${r}"
    local _u _ud
    for _u in $unwired; do
      _core_doctor_bin "$_u"; _ud="${commands[$REPLY]:-}"
      [[ -n "$_ud" ]] || continue
      _ud="${_ud:h}"
      [[ -n "${_CORE_PROBE_PATH:-}" && ":${_CORE_PROBE_PATH}:" == *":${_ud}:"* ]] && continue
      [[ " ${latedirs[*]} " == *" $_ud "* ]] || latedirs+=("$_ud")
    done
    if ((${#latedirs})); then
      print -r -- "  ${d}these joined PATH after detection: ${latedirs[*]}${r}"
      print -r -- "  ${d}move the prepend into 00-tools.zsh's bindir list to fix it for good${r}"
    else
      print -r -- "  ${d}installed after this shell started — open a new shell${r}"
    fi
  fi

  # Set at band 00, GONE now (#631) — the mirror of `not wired` above, and placed here for the
  # same structural reason: everything past "\nopt-in" is discarded by the render⇄json parity
  # test, so this block cannot perturb it.
  #
  # NO NEW GLYPH, deliberately. The row already renders ✗, which is honest about presence — a
  # fourth mark would spend the alarm-fatigue budget #620 was careful with, and would have to be
  # threaded through the legend and the parity regex. What ✗ cannot say is the part that matters:
  # the HAVE_* flag from band 00 is STILL SET, so 20-aliases.zsh's guard passed and an alias was
  # defined against a binary that no longer resolves.
  #
  # So the block names the ALIASES rather than the tools. `ps` is the failure the user meets;
  # `procs` is trivia they never typed. The pairs are read from the LIVE `aliases` table rather
  # than from a table kept here — it is the definitive answer for this shell, it costs no fork,
  # and it cannot go stale against 20-aliases.zsh. In the unit harness (ui+functions alone, no
  # aliases) the loop simply finds none and the tool list still prints.
  if ((${#stale})); then
    print -r -- "${c}stale${r}"
    print -r -- "  ${d}${stale[*]}${r}"
    print -r -- "  ${d}detected at startup, gone now — HAVE_* is still set, so the aliases stand${r}"
    local _s _sb _ak _af
    local -a broken=() _aw=()
    for _s in $stale; do
      _core_doctor_bin "$_s"; _sb=$REPLY
      for _ak in ${(k)aliases}; do
        # Split into a real array first. `${${(z)x}[1]}` subscripts the STRING, not the words —
        # it yields "p" for `alias ps=procs`, which silently matched nothing.
        _aw=( ${(z)aliases[$_ak]} )
        # first word, basename'd: `alias fd="$FD_BIN"` stores an absolute path.
        _af=${_aw[1]:t}
        [[ $_af == "$_sb" || $_af == "$_s" ]] || continue
        broken+=("$_ak → $_af")
      done
    done
    if ((${#broken})); then
      print -r -- "  ${d}these aliases now point at nothing: ${broken[*]}${r}"
      print -r -- "  ${d}reinstall the tool, or unalias to get the classic command back${r}"
    else
      print -r -- "  ${d}no alias points at them in this shell — reinstall or open a new shell${r}"
    fi
  fi

  # Active-integration probe (U1): presence (command -v, above) is NOT the same as wired.
  # Report which integrations actually registered their hooks/widgets in THIS shell, so a
  # "starship installed but the prompt is plain" or "atuin present but Ctrl-E is dead" is
  # visible instead of a misleading green ✓. ○ = installed but idle (not wired here). Only
  # the present ones are listed (an absent tool already shows ✗ in the group above).
  local -a wirable=("${_CORE_DOCTOR_WIRED[@]}")
  local w wline=""
  for w in $wirable; do
    _core_have "$w" || continue
    if _core_wired "$w"; then
      wline+="  ${g}✓${r} ${w}"
      # atuin's daemon is OPT-IN and can degrade at two different moments: 00-tools.zsh's
      # _core_atuin_daemon_guard probes the socket before the first prompt and then,
      # throttled, for the life of the shell, turning the daemon off when nothing is
      # listening so history still records — just without the daemon's lock relief. Both
      # paths end in the same place, but only one of them was ANNOUNCED: startup
      # degradation is silent by design, while a mid-session death printed one warning,
      # possibly hours ago and possibly scrolled away. Silent is right at the prompt,
      # invisible is not, so the doctor says which happened.
      if [[ $w == atuin && -n ${_CORE_ATUIN_DAEMON_DEGRADED:-} ]]; then
        if [[ -n ${_CORE_ATUIN_DAEMON_WAS_UP:-} ]]; then
          wline+=" ${d}(daemon died mid-session → direct writes)${r}"
        else
          wline+=" ${d}(daemon socket unreachable at startup → direct writes)${r}"
        fi
      fi
    else wline+="  ${d}○ ${w} (idle)${r}"; fi
  done
  if [[ -n "$wline" ]]; then
    print -r -- "${c}integrations wired${r}"
    print -r -- " $wline"
  fi

  # Resolved binary names + the detected package manager — the behaviour-affecting bits
  # a bare ✓/✗ hides (Debian's fd→fdfind/bat→batcat; which `up` manager fires here).
  print -r -- "${c}resolved${r}"
  print -r -- "  ${d}fd → ${FD_BIN:-(none)}    bat → ${BAT_BIN:-(none)}${r}"
  # …and git's exec-path, but ONLY when it was consulted — i.e. some `git-*` row missed on
  # $PATH and _core_doctor_bin asked git where its subcommands live (#424). Where the
  # subcommand is on $PATH the cache is never populated and this prints nothing, so the
  # common report is byte-identical. Same principle as the fd→fdfind line above it: show the
  # behaviour-affecting resolution that a bare ✓ hides. Carries no ✓/✗ glyph, so the
  # render⇄json set-equality test (which matches `[✓✗] <name>`) is blind to it by construction.
  [[ -n ${_CORE_GIT_EXEC_PATH:-} ]] && print -r -- "  ${d}git exec-path → ${_CORE_GIT_EXEC_PATH}${r}"
  if (($+functions[_pkgup_mgr])); then
    print -r -- "  ${d}package manager → $(_pkgup_mgr)${r}"
  fi
}

# mkcd — make a directory and cd into it
mkcd() {
  _core_wants_help "$1" && { _core_help "mkcd <dir>" "make a directory (and parents) and cd into it"; return 0; }
  [[ -z "$1" ]] && { _core_usage "mkcd <dir>"; return 1; }
  mkdir -p -- "$1" && cd -- "$1"
}

# cdup — climb N directories (cdup 3 == cd ../../..). NOT named `up`: that's the
# package-updater in 60-update.zsh. N defaults to 1 and must be a positive integer —
# a typo'd `cdup x` should say so, not silently no-op (the loop never runs) and leave
# you wondering why you didn't move.
cdup() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "cdup [n]" "climb n directories (default 1); cdup 3 == cd ../../.."; return 0; }
  local n="${1:-1}" p=""
  if [[ "$n" != <-> ]] || ((n < 1)); then
    _core_err "cdup: count must be a positive integer (got '$n')"
    _core_usage "cdup [n]"
    return 1
  fi
  while ((n-- > 0)); do p="../$p"; done
  cd "$p" || return
}

# _extract_dispatch — the raw unpack, NO safety guard. Split out of extract() so the
# "contain a tarbomb in a subdir" path (below) can re-run the unpack in that subdir
# WITHOUT re-entering the guard (which would see the same multi-entry archive and
# recurse forever). ouch (if installed) handles every format from one binary; the
# hand-rolled case is the bare-box fallback.
_extract_dispatch() {
  [[ -n ${HAVE_OUCH:-} ]] && { ouch decompress "$1"; return; }
  case "$1" in
  *.tar.bz2 | *.tbz2) tar xjf "$1" ;;
  *.tar.gz | *.tgz) tar xzf "$1" ;;
  *.tar.xz) tar xJf "$1" ;;
  *.tar) tar xf "$1" ;;
  *.bz2) bunzip2 -f "$1" ;;
  *.gz) gunzip -f "$1" ;;
  *.zip) unzip "$1" ;;
  *.7z) 7z x "$1" ;;
  *.rar) unrar x "$1" ;;
  *)
    _core_errbox "extract: unknown archive format" \
      "file:      ${1:t}" \
      "supported: .tar.gz/.tgz · .tar.bz2/.tbz2 · .tar.xz · .tar · .gz · .bz2 · .zip · .7z · .rar" \
      "tip:       install 'ouch' to (un)pack every format from one binary"
    return 1
    ;;
  esac
}

# _extract_run — dispatch with a progress spinner on the QUIET formats (tar/gz/bz2),
# so a large unpack reads as progress instead of a frozen terminal (U6). Chatty
# unpackers (zip/7z/rar) and ouch print their own output, so run those directly rather
# than fight their bytes with the spinner. _core_spin's non-TTY path just runs the
# command, so scripted/piped extracts and the unit tests behave exactly as before.
_extract_run() {
  emulate -L zsh
  if [[ -z ${HAVE_OUCH:-} && "$1" == (*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.tar|*.gz|*.bz2) ]] \
    && (($+functions[_core_spin])); then
    _core_spin "extracting ${1:t}" _extract_dispatch "$1"
  else
    _extract_dispatch "$1"
  fi
}

# extract — one command for any archive, with two defences applied BEFORE anything
# is written to disk:
#   • tarbomb guard — an archive with several top-level entries would scatter them
#     across the CWD; offer to contain it in ./<archive-name>/ instead.
#   • clobber guard — if a top-level entry already exists, confirm before overwriting.
# Both peek at the listing first (best-effort per format; unlistable → just unpack).
# Confirmation is via _core_confirm, which DECLINES with no TTY — so a scripted /
# piped run never silently overwrites, and a single-rooted archive (the common case)
# sails straight through untouched.
extract() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "extract <archive>" "unpack any archive (tar/zip/7z/rar/…); guards tarbombs + clobbers"; return 0; }
  [[ -z "$1" ]] && { _core_usage "extract <archive>"; return 1; }
  [[ -f "$1" ]] || {
    _core_err "extract: '$1' is not a file"
    return 1
  }
  local archive="$1" abs="${1:A}"

  # Entries this archive would write. tar/zip extract relative to the CWD, so their
  # top-level names are CWD-relative; gz/bz2 instead write NEXT TO the archive, so the
  # target is the archive's full path minus the compression suffix (${abs:r}) — not a
  # CWD basename. Getting that right means `extract /some/dir/file.gz` correctly checks
  # /some/dir/file for clobber, not ./file. Drop any '.'/'' rows (leading-'./'  tars).
  # We list/dispatch via $abs throughout, which also sidesteps a leading-'-' filename
  # being read as an option by tar/unzip/gunzip. Unlistable formats → empty → no guard.
  local -a top
  case "$archive" in
  *.tar.bz2 | *.tbz2 | *.tar.gz | *.tgz | *.tar.xz | *.tar)
    top=(${(f)"$(tar tf "$abs" 2>/dev/null | cut -d/ -f1 | sort -u)"}) ;;
  *.zip)
    top=(${(f)"$(unzip -Z1 "$abs" 2>/dev/null | cut -d/ -f1 | sort -u)"}) ;;
  *.gz | *.bz2)
    top=("${abs:r}") ;;
  esac
  top=(${top:#.}) # strip a bare '.' top entry (leading './' archives)

  if ((${#top})); then
    # Tarbomb: more than one top-level entry. Contain it in a subdir (default-safe:
    # with no TTY _core_confirm declines and we fall through to extract-in-place,
    # having at least warned).
    if ((${#top} > 1)); then
      local into="${archive:t:r}"
      into="${into%.tar}"
      _core_warn "extract: '${archive:t}' has ${#top} top-level entries — would scatter across $(pwd)"
      if _core_confirm "extract into ./${into}/ instead?"; then
        mkdir -p -- "$into" || {
          _core_err "extract: cannot create '$into'"
          return 1
        }
        (cd -- "$into" && _extract_run "$abs")
        return
      fi
    fi
    # Clobber: any existing top-level target. Confirm before overwriting; declined
    # (or no TTY) → abort with nothing touched.
    local t
    local -a clobber=()
    for t in "${top[@]}"; do [[ -e "$t" ]] && clobber+=("$t"); done
    if ((${#clobber})); then
      _core_warn "extract: would overwrite existing: ${clobber[*]}"
      _core_confirm "overwrite?" || {
        _core_warn "extract: cancelled (nothing overwritten)"
        return 1
      }
    fi
  fi

  _extract_run "$abs"
}

# fcd — fuzzy-cd into any subdirectory (needs fzf + fd, degrades to find)
fcd() {
  _core_wants_help "$1" && { _core_help "fcd" "fuzzy-cd into any subdirectory (fzf + fd, degrades to find)"; return 0; }
  _core_have fzf || {
    _core_err "fcd: requires fzf"
    _core_hint "install fzf, then retry"
    return 1
  }
  local dir
  if [[ -n ${HAVE_FZF:-} && -n ${HAVE_FD:-} ]]; then
    dir=$("$FD_BIN" --type d --hidden --exclude .git | fzf) && cd "$dir"
  else
    dir=$(find . -type d -not -path '*/.git/*' 2>/dev/null | fzf) && cd "$dir"
  fi
}

# please — re-run the last command with sudo. PREVIEWS the command and CONFIRMS
# first: this eval's your previous line as root, so a fat-fingered history entry
# (or a function that left something unexpected as the last command) should not
# silently run privileged. _core_confirm declines with no TTY, so this is fail-safe
# in a non-interactive context too.
please() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "please" "re-run the last command with sudo (previews + confirms first)"; return 0; }
  local last
  last="$(fc -ln -1 2>/dev/null)"
  if [[ -z "${last//[[:space:]]/}" ]]; then
    _core_err "please: no previous command to re-run"
    return 1
  fi
  _core_warn "about to run as root:  sudo ${last}"
  _core_confirm "proceed?" || {
    _core_warn "please: cancelled"
    return 1
  }
  eval "sudo ${last}"
}

# mkbak — timestamped backup of a file before you edit it. Validates its input in
# Core's voice instead of letting `cp` emit a raw "missing operand"/"No such file"
# (the rest of 30-functions.zsh — mkcd, extract — guards the same way).
mkbak() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "mkbak <file>" "timestamped .bak copy of a file before you edit it"; return 0; }
  [[ -z "$1" ]] && {
    _core_usage "mkbak <file>"
    return 1
  }
  [[ -f "$1" ]] || {
    _core_err "mkbak: '$1' is not a regular file"
    return 1
  }
  # Collision-safe + non-interactive. Two backups in the same second must NOT clobber
  # the first, and mkbak must never PROMPT — but `cp -i` bleeds in from 20-aliases.zsh
  # (parsed before this module), so a same-second collision would stop for a y/n. Pick
  # the next free .bak suffix, and copy via `command cp` to bypass the interactive alias.
  local ts dst n=1
  ts="$(date +%Y%m%d-%H%M%S)"
  dst="$1.$ts.bak"
  while [[ -e "$dst" ]]; do dst="$1.$ts.$((n++)).bak"; done
  command cp -p -- "$1" "$dst" && _core_ok "backup: ${dst:t}"
}

# _serve_advertise <port> — print the reachable http:// URLs for a 0.0.0.0 serve
# (tunnel/callback IP first in interface-priority order, then the default-route LAN IP)
# and return the best QR target in $REPLY. Split out of `serve` so the platform-specific
# discovery is HERMETICALLY testable (stub ip/ipconfig/route) without the blocking
# http.server. Linux/WSL uses ip(8); macOS/BSD ship none, so fall back to route(8)+ipconfig
# — the same split tmux/scripts/tmux-netinfo.sh uses; the tunnel list is kept aligned with
# that script's TUN_IFACES so no interface (tun1/tun2/wg1/…) is silently skipped.
_serve_advertise() {
  emulate -L zsh
  local port="$1" ip i qr_url="" dev
  local -a tun_ifaces=(tun0 tun1 tun2 wg0 wg1 proton0 nordlynx tailscale0 utun3 utun4 utun5)
  if command -v ip >/dev/null 2>&1; then # Linux / WSL
    for i in "${tun_ifaces[@]}"; do
      ip=$(ip -4 -o addr show "$i" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
      [[ -n "$ip" ]] && {
        echo "  → http://${ip}:${port}/   (${i})"
        qr_url="http://${ip}:${port}/"
        break
      }
    done
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}')
    [[ -n "$ip" ]] && { echo "  → http://${ip}:${port}/   (lan)"; : "${qr_url:=http://${ip}:${port}/}"; }
  elif command -v ipconfig >/dev/null 2>&1; then # macOS / BSD — no ip(8)
    for i in "${tun_ifaces[@]}"; do
      ip=$(ipconfig getifaddr "$i" 2>/dev/null)
      [[ -n "$ip" ]] && {
        echo "  → http://${ip}:${port}/   (${i})"
        qr_url="http://${ip}:${port}/"
        break
      }
    done
    # Reset ip before the LAN lookup: route(8) may find no default interface, and the
    # guarded assignment below would otherwise leave a tunnel address in $ip and reprint
    # it as "(lan)". (The Linux branch's unconditional ip=$(…) self-clears.)
    ip=""
    dev=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    [[ -n "$dev" ]] && ip=$(ipconfig getifaddr "$dev" 2>/dev/null)
    [[ -n "$ip" ]] && { echo "  → http://${ip}:${port}/   (lan)"; : "${qr_url:=http://${ip}:${port}/}"; }
  fi
  REPLY="$qr_url"
}

# serve — quick HTTP server in the CWD, printing the URLs it's actually reachable
# at (tunnel IP first, then LAN). Replaces the old `serve` alias. Binds all
# interfaces on purpose: this is your ad-hoc file-transfer server. Optional port.
#   serve            # port 8000
#   serve 8080       # port 8080
serve() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "serve [-l|--local] [port]" "HTTP server in the CWD (default 8000); all interfaces, or loopback with -l"; return 0; }
  # Parse flags + the optional port in ANY order: a typo'd flag is rejected in Core's
  # voice rather than silently treated as a bad port. -l/--local binds 127.0.0.1 (the
  # "just me" case) instead of the default all-interfaces exposure.
  local port="" local_only=0 arg
  for arg in "$@"; do
    case "$arg" in
    -l | --local) local_only=1 ;;
    -*)
      _core_err "serve: unknown option: $arg"
      local _sug
      _sug="$(_core_suggest "$arg" -l --local)"
      [[ -n "$_sug" ]] && _core_hint "did you mean ${_sug}?"
      _core_usage "serve [-l|--local] [port]"
      return 1
      ;;
    *)
      if [[ -n "$port" ]]; then
        _core_err "serve: too many arguments (got an extra '$arg')"
        _core_usage "serve [-l|--local] [port]"
        return 1
      fi
      port="$arg"
      ;;
    esac
  done
  : "${port:=8000}"
  # Defensive input handling: a typo'd port should be rejected cleanly, not handed to
  # python to fail with a stack trace (or, worse, a non-numeric value coerced oddly).
  if [[ "$port" != <-> ]] || ((port < 1 || port > 65535)); then
    _core_err "serve: port must be 1-65535 (got '$port')"
    _core_usage "serve [-l|--local] [port]"
    return 1
  fi
  _core_have python3 || {
    _core_errbox "serve: requires python3" \
      "why: serve runs Python's built-in http.server" \
      "fix: install python3, then retry"
    return 1
  }
  # Defensive (U7): a port already in use surfaces from http.server as a raw Python
  # traceback. Probe a bind FIRST — with SO_REUSEADDR set exactly as http.server does, so
  # the probe agrees with the real bind — and fail in Core's voice instead. Runs only after
  # the port/flags validated above, so a scripted bad-input run never reaches it.
  local bind_host="0.0.0.0"
  ((local_only)) && bind_host="127.0.0.1"
  if ! python3 - "$bind_host" "$port" 2>/dev/null <<'PY'
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind((sys.argv[1], int(sys.argv[2]))); s.close()
except OSError:
    sys.exit(1)
PY
  then
    _core_err "serve: port ${port} is already in use on ${bind_host}"
    _core_hint "pick another port, e.g. serve $((port + 1))"
    return 1
  fi
  # --local: bind loopback only — nothing leaves this host. No exposure warning, no
  # LAN/tunnel URL discovery (none would be reachable anyway).
  if ((local_only)); then
    echo "serving $(pwd) on 127.0.0.1:${port}  (local only — Ctrl-C to stop)"
    echo "  → http://127.0.0.1:${port}/   (localhost)"
    python3 -m http.server --bind 127.0.0.1 "$port"
    return
  fi
  # Default: bind ALL interfaces on purpose (ad-hoc file transfer), so say so plainly —
  # on an untrusted network the CWD is reachable by anyone who can route to this host
  # until you Ctrl-C. Use `serve -l` to keep it to loopback.
  _core_warn "serve binds 0.0.0.0:${port} — the CWD is exposed on every interface (use -l for loopback only)"
  echo "serving $(pwd) on port ${port}  (Ctrl-C to stop)"
  # Advertise the reachable tunnel/LAN URLs. The platform-specific IP discovery lives in
  # _serve_advertise (hermetically testable, no blocking server): it prints the URL lines
  # and returns the best QR target in $REPLY.
  local qr_url
  _serve_advertise "$port"
  qr_url="$REPLY"
  # Scan-to-open: this server's whole point is ad-hoc transfer to another device, so when
  # qrencode is present render the reachable URL as a QR — point a phone at it, no typing
  # a LAN IP. Graceful skip when qrencode is absent (just the URLs above), like every
  # other optional-tool path in Core.
  if [[ -n "$qr_url" ]] && _core_have qrencode; then
    echo "  scan to open ${qr_url} :"
    qrencode -t ANSIUTF8 "$qr_url"
  fi
  python3 -m http.server "$port"
}

# genpw — print a random password. Portable by design: prefers openssl (present on
# essentially every box), falls back to /dev/urandom so it still works on a bare
# rescue shell with nothing installed. Default length 16; pass a length to override.
#   genpw          # 16-char alnum password
#   genpw 32       # 32-char
genpw() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "genpw [length]" "random alphanumeric password (default 16) via openssl, /dev/urandom fallback"; return 0; }
  local len="${1:-16}"
  # Reject a non-numeric / zero length cleanly in Core's voice rather than emitting an
  # empty string (head -c 0) that looks like success.
  if [[ "$len" != <-> ]] || ((len < 1)); then
    _core_err "genpw: length must be a positive integer (got '$len')"
    _core_usage "genpw [length]"
    return 1
  fi
  if _core_have openssl; then
    # base64 then strip to alnum, so the byte count we draw comfortably exceeds $len.
    openssl rand -base64 $((len * 2)) | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c "$len"
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$len"
  fi
  echo
}

# pullall — fast-update every git repo under a parent directory, IN PARALLEL. For
# each repo it prunes deleted remote branches, stashes any uncommitted (tracked)
# changes, switches to the repo's trunk (main/master/trunk/… — auto-detected, NOT
# assumed to be "main"), fast-forwards it, then pops your stash back. A summary card
# tallies updated / warnings / failed / pruned at the end.
#
#   pullall            # repos under $PULLALL_DIR (or the CWD if it's unset)
#   pullall ~/code     # repos under an explicit directory
#
# The parent directory is deliberately NOT hard-coded — Core is identical on every
# machine, but /Users/you/projects vs /home/you/code is not. Pass it as an argument,
# or pin it once in your ~/.zshrc.local (the machine-local layer Core loads last):
#   export PULLALL_DIR="$HOME/projects"
# Parallelism defaults to 10 workers; override with PULLALL_JOBS.
#
# Heads-up: this rewrites working state across MANY repos. It is stash-safe (your
# uncommitted tracked changes are popped back, and a pop conflict is reported, never
# swallowed), but a repo you left on a feature branch ends up on its trunk — run it
# where that's what you want. The pull is --ff-only, so a diverged trunk is reported
# as a failure rather than silently merged.
# Portability: needs `xargs -P` (parallel). Present on macOS/BSD and GNU findutils; a
# stripped busybox/Alpine xargs without parallel support will reject -P — set
# PULLALL_JOBS=1 there, or install findutils.
pullall() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "pullall [dir]" "pull every git repo under a dir in parallel (prunes, stashes, fast-forwards trunk)"; return 0; }

  local parent="${1:-${PULLALL_DIR:-$PWD}}"
  if [[ ! -d "$parent" ]]; then
    _core_err "pullall: not a directory: $parent"
    _core_hint "pass a directory, or set PULLALL_DIR (e.g. in ~/.zshrc.local)"
    _core_usage "pullall [dir]"
    return 1
  fi
  local jobs="${PULLALL_JOBS:-10}"
  if [[ "$jobs" != <-> ]] || ((jobs < 1)); then
    _core_err "pullall: PULLALL_JOBS must be a positive integer (got '$jobs')"
    return 1
  fi

  # Colour is decided ONCE here (TTY- and NO_COLOR-aware) and handed to the workers
  # as exported vars. The workers run under /bin/sh, where Core's _core_* helpers
  # don't exist — so they print with printf and these pre-resolved escapes (real ESC
  # bytes, or empty when colour is off). `local -x` exports to the child processes
  # AND restores the caller's environment when pullall returns.
  local -x G='' Y='' R='' NC=''
  if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' NC=$'\e[0m'
  fi
  local bold='' rst=''
  [[ -n "$NC" ]] && { bold=$'\e[1m' rst=$'\e[0m'; }

  print -r -- "${bold}🔄 Updating git repos under ${parent} …${rst}"
  print

  # Each worker receives its repo path as $1 — passed POSITIONALLY, not interpolated
  # into the script text — so a path with spaces, quotes, or shell metacharacters
  # can't break the worker or inject a command. -print0/-0 keep odd names intact; -P
  # runs $jobs workers at once. Output is captured (not streamed) so we can tally it.
  local output
  output=$(find "$parent" -mindepth 1 -maxdepth 1 -type d -print0 \
    | xargs -0 -I {} -P "$jobs" sh -c '
      repo="$1"
      cd "$repo" 2>/dev/null || exit 0
      [ -e .git ] || exit 0            # plain clone (dir) or worktree/submodule (file)
      name=$(basename "$repo")

      # 1. prune deleted remote branches — report only when something was actually pruned
      prune=$(git fetch --prune 2>&1)
      if printf "%s\n" "$prune" | grep -q "\[deleted\]"; then
        printf "%s\n" "$prune" | grep "\[deleted\]" | while IFS= read -r line; do
          printf "%s\n" "${Y}🧹 ${name}: ${line}${NC}"
        done
      fi

      # 2. stash uncommitted (tracked) changes so checkout/pull cannot be blocked by them
      stashed=0
      if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        git stash push -m "Auto-stash by pullall" >/dev/null 2>&1 && stashed=1
      fi

      # 3. resolve the trunk for THIS repo — origin/HEAD if set, else the first of
      #    main/master/trunk that exists, else fall back to the current branch.
      trunk=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
      trunk=${trunk#origin/}
      if [ -z "$trunk" ]; then
        for b in main master trunk; do
          if git show-ref -q --verify "refs/heads/$b"; then trunk="$b"; break; fi
        done
      fi
      [ -z "$trunk" ] && trunk=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

      # 4. switch to the trunk
      if ! git checkout "$trunk" >/dev/null 2>&1; then
        printf "%s\n" "${R}❌ ${name}: could not switch to ${trunk}${NC}"
        [ "$stashed" -eq 1 ] && git stash pop >/dev/null 2>&1
        exit 0
      fi

      # 5. fast-forward the trunk
      git pull --ff-only origin "$trunk" >/dev/null 2>&1
      pull=$?

      # 6. restore the stash (report a pop conflict instead of leaving it on the stack silently).
      #    The wording is gated on $pull: if the fast-forward ALSO failed, the trunk was not
      #    updated, so dont claim it was — that combined failure is a ❌, not a ⚠️.
      if [ "$stashed" -eq 1 ]; then
        if ! git stash pop >/dev/null 2>&1; then
          if [ "$pull" -eq 0 ]; then
            printf "%s\n" "${Y}⚠️  ${name}: updated ${trunk}, but a conflict blocked restoring your local changes${NC}"
          else
            printf "%s\n" "${R}❌ ${name}: pull failed AND a conflict blocked restoring your local changes${NC}"
          fi
          exit 0
        fi
      fi

      # 7. per-repo status line
      if [ "$pull" -eq 0 ]; then
        if [ "$stashed" -eq 1 ]; then
          printf "%s\n" "${G}✅ ${name}: updated ${trunk} & restored your changes${NC}"
        else
          printf "%s\n" "${G}✅ ${name}: updated ${trunk}${NC}"
        fi
      else
        printf "%s\n" "${R}❌ ${name}: network or non-fast-forward error during pull${NC}"
      fi
    ' _ {})

  print -r -- "$output"

  # Tally the emoji markers in ONE awk pass instead of four grep -c scans of the same
  # buffer. index() is byte-based (locale-independent for the multibyte glyphs) and, like
  # grep -c, counts matching LINES; awk always prints four integers, so the arithmetic
  # below stays safe even when $output is empty (0 0 0 0).
  local ok warn fail pruned
  read -r ok warn fail pruned <<<"$(printf '%s\n' "$output" | awk '
    index($0,"✅"){o++} index($0,"⚠️"){w++} index($0,"❌"){f++} index($0,"🧹"){p++}
    END{printf "%d %d %d %d\n", o, w, f, p}')"

  print
  print -r -- "${bold}📊 pullall summary${rst}"
  print -r -- "  ${G}updated:${NC}  $ok"
  ((warn > 0)) && print -r -- "  ${Y}warnings:${NC} $warn"
  print -r -- "  ${R}failed:${NC}   $fail"
  ((pruned > 0)) && print -r -- "  ${Y}pruned:${NC}   $pruned remote branch(es)"

  # A clean run returns 0; any ❌ makes pullall non-zero so it composes in scripts.
  return $((fail > 0))
}

# core-help (alias: cheat) — a scannable cheat sheet of what Core actually gives
# you on this box: the shell functions, the custom keybindings, and the update /
# maintenance verbs. Static + instant — the discoverability surface for the Core
# layer (the shell counterpart to which-key in Neovim). Rows are "key|description"
# pairs grouped under "§heading" markers, so the list stays trivially editable.
# Public verb: render the sheet, paging it through $PAGER when it's taller than the
# terminal (the full sheet easily overflows a tmux split). Paging only kicks in on a real
# TTY; a pipe/redirect/the unit tests take the direct render path below — byte-identical
# to before — so nothing captured changes. Colour is FORCED on for the captured render
# (_core_page's pipe would otherwise look non-TTY and blank it); _core_page then prints or
# pages. A filtered/short sheet that fits one screen is printed inline (less -F).
core-help() {
  emulate -L zsh
  if [[ -t 1 && -z ${CORE_NO_PAGER:-} ]]; then
    local _out
    _out="$(_CORE_FORCE_COLOR=1 _core_help_render "$@")"
    local _rc=$?
    _core_page "$_out"
    return $_rc
  fi
  _core_help_render "$@"
}
_core_help_render() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "core-help [filter]" "scannable cheat sheet of Core's functions, keys & maintenance; pass a word to filter"; return 0; }
  # Optional case-insensitive filter: `core-help serve` jumps straight to the matching
  # rows instead of scanning the whole sheet (U4). Empty → the full grouped cheat sheet.
  local filter="${(L)1:-}"
  # Raw ANSI (not prompt %F) + `print -r` below, so a literal backslash in a key
  # (Ctrl-\) survives — print -P would consume it as an escape. Colour only on a
  # TTY; piped/redirected output stays plain.
  # Accent + muted come from 05-ui.zsh's canonical palette ($_CORE_C_ACCENT/$_CORE_C_MUTED
  # — the one place $COLORTERM is interpreted, truecolor-aware), so the cheat sheet, the
  # update nudge, and core-doctor share one branded blue instead of three hand-rolled
  # copies. The TTY/NO_COLOR blanking below still applies locally.
  local title="${_CORE_C_ACCENT:-}" dc="${_CORE_C_MUTED:-}"
  local te=$'\e[0m' kc=$'\e[36m' ke=$'\e[0m' de=$'\e[0m'
  # Blank colour off a non-TTY UNLESS the paging wrapper forced it on (_CORE_FORCE_COLOR),
  # and always off under NO_COLOR — so the captured-for-paging render keeps its colour.
  if { [[ ! -t 1 ]] && [[ -z ${_CORE_FORCE_COLOR:-} ]]; } || [[ -n ${NO_COLOR:-} ]]; then title='' te='' kc='' ke='' dc='' de=''; fi
  # Rows are "key|description" or "key|description|requires" — the optional third
  # field names a command this entry NEEDS. When it's absent on THIS box the row is
  # dimmed and tagged "— needs <cmd>", so the cheat sheet reflects what actually works
  # here instead of advertising widgets/verbs that would no-op (fzf/atuin/sesh/zoxide
  # aren't on every box). Verbs that degrade gracefully (extract, up, maint) carry no
  # requirement — they always work.
  local -a rows=(
    "§navigation & files"
    "mkcd <dir>|make a directory and cd into it"
    "cdup [n]|climb n directories (default 1)"
    "extract <archive>|unpack any archive (tar/zip/7z/rar/…)"
    "mkbak <file>|timestamped .bak copy before you edit"
    "fcd|fuzzy-cd into any subdirectory|fzf"
    "serve [-l] [port]|HTTP server in the CWD (-l = loopback only); prints reachable URLs|python3"
    "genpw [length]|random alphanumeric password (default 16; openssl, urandom fallback)"
    "please|re-run your last command with sudo (previews + confirms first)"
    "§search"
    "fif <text>|find text inside files (rg + fzf + preview)|fzf"
    "fbr|fuzzy git-branch checkout|fzf"
    "§git (most-used — full OMZ-style set in 25-git.zsh)"
    "g <args>|git"
    "gst / gss|status / short status"
    "ga / gaa|stage file(s) / stage all"
    "gc / gcm <msg>|commit (verbose) / commit -m"
    "gco / gcb <branch>|checkout / checkout -b"
    "gp / gl|push / pull"
    "gpf|push --force-with-lease (safe force)"
    "gaf / grf / grsf|fuzzy stage / restore / unstage (multi-select)|fzf"
    "gd / gds|diff / diff --staged"
    "glog|graph log (oneline, decorated)"
    "grbm|rebase onto the trunk branch"
    "pullall [dir]|pull every git repo under a dir in parallel (stashes, fast-forwards trunk)"
    "§keybindings"
    "Ctrl-T|file picker → insert path at cursor|fzf"
    "Ctrl-R|history search|fzf"
    "Ctrl-E|Atuin history TUI|atuin"
    "Ctrl-G|session picker (sesh)|sesh"
    "Alt-Z|zoxide project jump|zoxide"
    "Ctrl-\\|toggle autosuggestions"
    "§updates & maintenance"
    "up [-y]|apply package updates (interactive; confirms first)"
    "update-check|refresh the 'updates available' nudge"
    "gsync|push this repo's vendored core/ subtree back upstream to dotfiles-core"
    "maint-install [HH:MM]|schedule the daily safe-update job"
    "maint-run|run daily maintenance now"
    "maint-log [-f]|view (or follow) the maintenance log"
    "maint-status|when the job next runs / is it enabled"
    "maint-uninstall|remove the scheduled maintenance job"
  )
  local ver=""
  [[ -r "$_CORE_VERSION_FILE" ]] && ver=" v$(<"$_CORE_VERSION_FILE")"
  if [[ -n "$filter" ]]; then
    print -r -- "${title}dotfiles Core${ver} — cheat sheet${te} ${dc}(filter: ${filter})${de}"
  else
    print -r -- "${title}dotfiles Core${ver} — cheat sheet${te} ${dc}(run \`core-help\` anytime · \`core-help <word>\` to filter)${de}"
  fi
  # Key column is derived from the WIDEST key, not a fixed 22 — so alignment stays
  # correct if a longer verb is ever added (the old hard-coded width silently broke
  # alignment past 22 chars) and isn't padded wider than the content needs. On a narrow
  # terminal, clamp it (and truncate an over-long key) so it can't swallow the whole
  # line and leave no room for the description.
  local line key desc req kw=0
  local -a parts
  for line in "${rows[@]}"; do
    [[ "$line" == §* ]] && continue
    key="${line%%|*}"
    ((${#key} > kw)) && kw=${#key}
  done
  local cols=${COLUMNS:-80}
  ((kw > cols - 22)) && kw=$((cols - 22)) # keep room for a readable description
  ((kw < 6)) && kw=6
  local matched=0 cur_section=""
  for line in "${rows[@]}"; do
    if [[ "$line" == §* ]]; then
      # Track the section a row belongs to (lowercased) so a filter can match by SECTION
      # name too — e.g. `core-help keybindings` surfaces that whole group even though the
      # word never appears in any row's key/desc. (Completion offers these section terms.)
      cur_section="${(L)${line#§}}"
      # Section headers print only in the UNFILTERED view — a filter wants the matching
      # rows, not the scaffolding around them.
      [[ -n "$filter" ]] && continue
      print -r -- "${title}${line#§}${te}"
    else
      parts=("${(@s:|:)line}")
      key="${parts[1]}"
      desc="${parts[2]}"
      req="${parts[3]:-}" # optional: a command this row needs to actually work
      # Filtered: skip rows whose key+description AND owning section don't contain the term
      # (case-insensitive) — so both a verb term (`serve`) and a section term (`navigation`)
      # narrow correctly, and a completion-suggested section name never yields "no matches".
      [[ -n "$filter" && "${(L)key} ${(L)desc}" != *"$filter"* && "$cur_section" != *"$filter"* ]] && continue
      matched=1
      key="${key[1,kw]}"  # truncate an over-long key to the (possibly clamped) column
      if [[ -n "$req" ]] && ! _core_have "$req"; then
        # Unavailable on this box — dim the whole row and name what to install.
        print -r -- "  ${dc}${(r:$kw:)key} ${desc} — needs ${req}${de}"
      else
        print -r -- "  ${kc}${(r:$kw:)key}${ke} ${dc}${desc}${de}"
      fi
    fi
  done
  if [[ -n "$filter" ]]; then
    ((matched)) || print -r -- "  ${dc}no entries match '${filter}' — run \`core-help\` for the full sheet${de}"
    return 0
  fi
  print -r -- "${dc}  1Password: opsecret · openv · optoken · opssh    health: core-doctor · version: core-version${de}"
  print -r -- "${dc}  front door: core <help|doctor|version|update>  (run \`core\` for this sheet anytime)${de}"
}
alias cheat='core-help'

# ── command-not-found handler (U1) ────────────────────────────────────────────
# A mistyped command otherwise gets zsh's terse default (or, on Debian, the distro's
# package suggester). Replace it with a Core-voice miss that (a) suggests the nearest
# Core verb/alias when it's a near typo (`extarct` → extract) and (b) offers an install
# line via the package manager 60-update.zsh already detects — turning a dead end into a
# next step. Defined ONLY in an interactive shell: the unit harness sources this file
# non-interactively (`zsh -fc`) and must NOT install a global handler. Opt out with
# CORE_CNF_ENABLED=0 (e.g. an OS layer that prefers the distro's own suggester).
: "${CORE_CNF_ENABLED:=1}"
if [[ $- == *i* ]] && ((CORE_CNF_ENABLED)); then
  command_not_found_handler() {
    emulate -L zsh
    local cmd="$1"
    _core_err "command not found: ${cmd}"
    # Did-you-mean against Core's own verbs — where typos land most often.
    local -a _verbs=(
      core mkcd cdup extract mkbak fcd serve genpw fif fbr up update-check
      maint-install maint-run maint-log maint-status maint-uninstall
      core-help core-doctor core-version
      opsecret openv optoken opssh
    )
    # Also weigh this shell's defined ALIASES — the most-typed commands (the g* git set,
    # ll/la, lg, …) live there, so a near miss like `gts`→`gst` or `gco`→`gci` gets caught
    # too, not just the Core verbs. ${(k)aliases} is the alias-name set in the live shell.
    _verbs+=(${(k)aliases})
    local _sug
    _sug="$(_core_suggest "$cmd" $_verbs)"
    if [[ -n "$_sug" ]]; then
      _core_hint "did you mean ${_sug}?"
    elif (($+functions[_pkgup_mgr])); then
      # No near Core verb — offer an install path for THIS box's package manager.
      local _pfx
      _pfx="$(_core_install_prefix "$(_pkgup_mgr)")" && _core_hint "try: ${_pfx} ${cmd}"
    fi
    return 127
  }
fi
