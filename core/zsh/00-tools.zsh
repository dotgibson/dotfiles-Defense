# core/zsh/00-tools.zsh
# ──────────────────────────────────────────────────────────────────────────────
# Tool detection + the single place every shell-hook tool is initialised. Load
# this FIRST (before options/history/aliases/fzf/bindings/plugins/op).
#
# Why this file exists: the modern CLI stack (eza, bat, fd, ...) is not present
# on every box, and package names differ per distro (fd -> `fdfind` on Debian,
# bat -> `batcat`). We detect what's installed, set HAVE_* flags + canonical
# binary names, and degrade gracefully instead of erroring on a bare box.
#
# This is also the ONE place zoxide/starship/atuin/mise are initialised. Their
# `init`/`activate zsh` scripts are static text for a given binary version, so we
# CACHE all four: generate once and `source` the cache (one cheap read) instead
# of spawning a subprocess on every shell start. The per-shell/per-dir variation
# lives in the RUNTIME hooks those scripts register, not in the generated text,
# so caching the generation changes nothing about behaviour. _cache_eval re-runs
# the generator whenever the binary is newer than its cache. Measure with:
#     hyperfine 'zsh -i -c exit'
# ──────────────────────────────────────────────────────────────────────────────

# Interactive shells only. Scripts get raw POSIX.
[[ $- == *i* ]] || return 0

# user-local bin (mise/starship/atuin/clip/carapace land here) must be on PATH
# BEFORE we probe for those tools, or they won't be detected on a fresh shell.
[[ -d "$HOME/.local/bin" && ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin:$PATH"

_have() { command -v "$1" >/dev/null 2>&1; }

# ── Cache helper: source a tool's init script, regenerate only when the binary
# is newer than the cache (or the cache is missing). Turns an eval-of-subprocess
# into a plain source. Used for the tools whose init output is deterministic. ──
#
# CACHE-INVALIDATION: the cache is rebuilt when the *binary* is newer than it (the
# mtime check below). A tool whose init output ALSO depends on env read at generation
# time — ATUIN_NOBIND for atuin, CARAPACE_BRIDGES for carapace — passes that env via
# `_cache_eval --salt`, which folds it into the cache FILENAME, so flipping the env
# selects a different cache and regenerates. (Salt-free callers — starship/zoxide/mise,
# whose output doesn't vary on env here — keep the plain mtime-only behaviour.)
_cache_eval() { # _cache_eval [--salt <sig>] <name> <command...>
  # --salt folds an env SIGNATURE into the cache filename, so changing env the generator
  # reads at generation time (ATUIN_NOBIND, CARAPACE_BRIDGES) selects a DIFFERENT cache
  # and regenerates — closing the "flip the env, keep the stale cache" caveat above for
  # those callers. Sanitised to a path-safe token. Salt-free callers are unchanged.
  local salt=""
  if [[ "$1" == --salt ]]; then salt="$2"; shift 2; fi
  local name="$1"
  shift
  local dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
  local sig="${salt//[^A-Za-z0-9]/_}"
  local cache="$dir/${name}${sig:+.$sig}.zsh"
  # Resolve the binary via zsh's $commands hash (name -> absolute path) instead of
  # $(command -v ...): the builtin lookup is fork-free, where the command-substitution
  # forks a subshell on EVERY _cache_eval call (~8/shell across starship/zoxide/mise/
  # atuin/carapace + os-layer gh/uv/ty). The tools cached here are all external binaries,
  # so $commands is populated for them; an absent tool yields "" and we bail as before.
  local bin="${commands[$1]}"
  [[ -z "$bin" ]] && return 0
  if [[ ! -s "$cache" || "$bin" -nt "$cache" ]]; then
    [[ -d "$dir" ]] || mkdir -p "$dir"
    # `>|` forces the overwrite: 10-options.zsh sets NO_CLOBBER, under which a plain
    # `>` onto an existing cache raises "file exists" (a shell-level redirection
    # error that 2>/dev/null does NOT suppress). This regen path runs whenever the
    # tool's binary is newer than the cache — e.g. right after a brew upgrade. It
    # surfaced only for the os.zsh callers (gh/uv/ty) because they run AFTER
    # 10-options.zsh sets NO_CLOBBER; the 00-tools.zsh callers run before it.
    "$@" >|"$cache" 2>/dev/null
  fi
  source "$cache"
}

# ── Resolve binaries that ship under alternate names on some distros ──────────
# Debian/Ubuntu ship fd as `fdfind` and bat as `batcat` to avoid name clashes.
if _have fd; then
  FD_BIN=fd
elif _have fdfind; then FD_BIN=fdfind; fi

if _have bat; then
  BAT_BIN=bat
elif _have batcat; then BAT_BIN=batcat; fi

# Terminal web browser: prefer w3m (the one we package fleet-wide), but fall back
# to any other text browser already on the box so a bare machine still gets one.
for _b in w3m lynx links2 links elinks; do
  if _have "$_b"; then BROWSER_BIN=$_b; break; fi
done
unset _b

# ── HAVE_* flags consumed by 20-aliases.zsh / 30-functions.zsh / 35-fzf.zsh ────────────
_have eza && HAVE_EZA=1
_have rg && HAVE_RG=1
_have zoxide && HAVE_ZOXIDE=1
_have fzf && HAVE_FZF=1
_have starship && HAVE_STARSHIP=1
_have atuin && HAVE_ATUIN=1
_have delta && HAVE_DELTA=1
_have yazi && HAVE_YAZI=1
_have btop && HAVE_BTOP=1
_have dust && HAVE_DUST=1
_have procs && HAVE_PROCS=1
_have mise && HAVE_MISE=1
_have uv && HAVE_UV=1              # Astral project-Python manager (20-aliases.zsh: uvr/uvs; os/*.zsh caches its completion)
_have carapace && HAVE_CARAPACE=1 # completion engine — init in 45-plugins.zsh
# 2026 additions (20-aliases.zsh guards each):
_have xh && HAVE_XH=1
_have glow && HAVE_GLOW=1
_have doggo && HAVE_DOGGO=1
_have gron && HAVE_GRON=1
_have sd && HAVE_SD=1
_have ast-grep && HAVE_ASTGREP=1    # AST-aware structural search/rewrite — own command, no alias (the syntax-tree complement to rg=text, sd=regex, gron=JSON). Opt-in; inert without the binary.
_have gum && HAVE_GUM=1
_have viddy && HAVE_VIDDY=1         # modern watch (20-aliases.zsh: watch → viddy)
_have gping && HAVE_GPING=1         # graphical ping (20-aliases.zsh: ping → gping)
_have tldr  && HAVE_TLDR=1          # tealdeer binary (20-aliases.zsh: help → tldr)
# mid-2026 additions — data / disk / dev tooling (see PORTING-MATRIX package table):
_have jq && HAVE_JQ=1               # JSON processor (gron greps; jq transforms — complements)
_have yq && HAVE_YQ=1              # YAML/JSON/XML processor (the jq of YAML)
_have jnv && HAVE_JNV=1            # interactive jq-filter editor + collapsible JSON viewer — own command, no alias (the "explore" verb to jq's "transform"/gron's "grep"). Opt-in; inert without the binary.
_have duf && HAVE_DUF=1             # modern df (20-aliases.zsh: df → duf, with df -h fallback)
_have ouch && HAVE_OUCH=1          # one-binary archive (un)packer (30-functions.zsh: extract prefers it)
_have hyperfine && HAVE_HYPERFINE=1 # benchmarking (the perf note at the top of this file uses it)
_have shellcheck && HAVE_SHELLCHECK=1 # shell linter (own command — no alias)
_have shfmt && HAVE_SHFMT=1        # shell formatter (own command — no alias)
_have jj && HAVE_JJ=1              # jujutsu — OPT-IN, colocated git companion (20-aliases.zsh: jjs/jjl/jjd)
_have sesh && HAVE_SESH=1          # smart tmux session manager — drives Ctrl-G (35-fzf.zsh) + prefix+f (tmux-sesh.sh); both fall back to find+fzf when unset
_have difft && HAVE_DIFFT=1        # difftastic — AST/structural diff; OPT-IN companion to delta (git dft), never the default pager (20-aliases.zsh: gdft)
[[ -n ${FD_BIN:-} ]] && HAVE_FD=1
[[ -n ${BAT_BIN:-} ]] && HAVE_BAT=1
[[ -n ${BROWSER_BIN:-} ]] && HAVE_BROWSER=1  # terminal web browser (20-aliases.zsh: web + headless BROWSER)

# ── Tool env — set BEFORE the init evals below ────────────────────────────────
# starship reads its theme from the default ~/.config/starship.toml (bootstrap
# symlinks core/starship/starship.toml there), so no STARSHIP_CONFIG is needed.
# starship already renders the active venv, so silence Python's own prefix.
export VIRTUAL_ENV_DISABLE_PROMPT=1
# atuin binds NOTHING automatically — 40-bindings.zsh owns Ctrl+E (atuin TUI) and
# keeps Ctrl+R on the custom fzf history widget. (Replaces --disable-up-arrow.)
export ATUIN_NOBIND=true

# ── Initialise shell-hook tools ───────────────────────────────────────────────
# All CACHED via _cache_eval: the `init`/`activate` scripts these emit are static
# *text* (function defs + hook registration) for a given binary version — the
# per-shell/per-dir variation happens at RUNTIME inside the sourced hooks, not in
# the generated script — so caching the generation is safe and removes the last
# two per-shell subprocess spawns. _cache_eval regenerates whenever the binary is
# newer than the cache (e.g. after an upgrade). See the invalidation caveat above.
[[ -n ${HAVE_STARSHIP:-} ]] && _cache_eval starship starship init zsh

# Keep starship's right prompt alive. 45-plugins.zsh (loaded after this file) pulls
# in romkatv/zsh-defer to async-load the heavy plugins; zsh-defer's prompt-reset
# path blanks RPS1 (== RPROMPT), which silently wipes the right prompt starship
# just set — left prompt survives, right vanishes. Rather than depend on the
# installed zsh-defer version (current master only blanks RPS1 when it's unset,
# but older builds do it unconditionally), capture starship's RPROMPT now and
# re-assert it on every precmd so it survives the deferred-plugin load.
if [[ -n ${HAVE_STARSHIP:-} && -n ${RPROMPT:-} ]]; then
  typeset -g _STARSHIP_RPROMPT=$RPROMPT
  typeset -gi _STARSHIP_RPROMPT_TRIES=0
  autoload -Uz add-zsh-hook
  # B13: harden the workaround so it can't misbehave if zsh-defer's internals change.
  #  (1) RESTORE ONLY WHEN BLANKED — re-assert only if RPROMPT is currently empty, so we
  #      fix zsh-defer's reset but never clobber a non-empty RPROMPT an OS/local layer set
  #      on purpose (the old unconditional assignment would stomp it on every precmd).
  #  (2) SELF-REMOVE — the blank happens right after the FIRST prompt (the deferred-plugin
  #      load); a few precmds past that the guard's job is done, so it unhooks itself
  #      instead of running forever. If a future zsh-defer stops blanking RPS1 entirely,
  #      this then simply no-ops a couple of times and detaches — no lingering side effect.
  _starship_keep_rprompt() {
    [[ -z ${RPROMPT:-} ]] && RPROMPT=$_STARSHIP_RPROMPT
    ((++_STARSHIP_RPROMPT_TRIES >= 3)) && add-zsh-hook -d precmd _starship_keep_rprompt
  }
  add-zsh-hook precmd _starship_keep_rprompt
fi

# ── Command-block separators (Pass 2, P12) ────────────────────────────────────
# A thin full-width rule drawn above each prompt that FOLLOWED a command, colored by
# that command's exit status: dim (#414868) on success, red (#f7768e) on failure. It
# turns scrollback into visually delimited "blocks" — scan the left edge for red to
# find what broke. Pure precmd/preexec output (NO ZLE widget), so unlike a transient
# prompt it cannot collide with zsh-vi-mode. A bare Enter draws no rule (the preexec
# flag gates it), so idle prompts don't stack rules.
if [[ -n ${HAVE_STARSHIP:-} ]]; then
  autoload -Uz add-zsh-hook
  typeset -gi _CMD_BLOCK_RAN=0
  _cmd_block_preexec() { _CMD_BLOCK_RAN=1 }
  _cmd_block_precmd() {
    local ec=$?                               # captured FIRST — real command exit code
    (( _CMD_BLOCK_RAN )) || return            # nothing ran → no rule
    _CMD_BLOCK_RAN=0
    local w=${COLUMNS:-80} col
    if (( ec == 0 )); then col='%F{#414868}'; else col='%F{#f7768e}'; fi
    print -rP -- "${col}${(l:w::─:)}%f"
  }
  add-zsh-hook preexec _cmd_block_preexec
  add-zsh-hook precmd  _cmd_block_precmd
  # Run our precmd FIRST so $? is the command's exit code, not starship_precmd's.
  precmd_functions=(_cmd_block_precmd ${precmd_functions:#_cmd_block_precmd})
fi

[[ -n ${HAVE_ZOXIDE:-} ]] && _cache_eval zoxide zoxide init zsh
# mise: the chpwd-hook activation, now cached. The hook still resolves tools live
# per-dir; only the activation script's *generation* is cached. (If you'd rather
# use native shims — mise/config.toml has experimental=true — switch to
# `mise activate zsh --shims` or put "$(mise where)"/shims on PATH and drop this
# line; pick ONE deliberately.)
[[ -n ${HAVE_MISE:-} ]] && _cache_eval mise mise activate zsh
# atuin: init script is static text; ATUIN_NOBIND (set above) is read at generation, so
# salt the cache on it — flipping ATUIN_NOBIND now busts the cache instead of serving stale.
[[ -n ${HAVE_ATUIN:-} ]] && _cache_eval --salt "${ATUIN_NOBIND:-}" atuin atuin init zsh

# ── atuin daemon (OPT-IN) — degrade to direct writes when it isn't reachable ───
# atuin's daemon owns the SQLite writes and shells talk to it over a unix socket, which
# relieves the DB-lock contention every shell and every tmux pane otherwise pays —
# measured at ~1.4x on p50 and ~1.2-1.3x on p95. Whether it helps or hurts the FAR tail
# is unsettled: the runs that said "worse" timed `history start` + `history end`
# together, but the hook backgrounds `end`, and the one run that timed only the blocking
# call found p99 improving instead. Don't sell it as a tail fix, or as a tail regression,
# until that is re-measured (scripts/bench-atuin-daemon.sh reports the two metrics
# separately; full numbers and caveats in the config). Core
# ships the [daemon] block OFF (core/atuin/config.toml); a machine opts IN from its OS
# layer (os/<os>.zsh) or host layer (99-local) with atuin's own env overrides —
# ATUIN_DAEMON__ENABLED=true, plus ATUIN_DAEMON__AUTOSTART=true where nothing else
# supervises the daemon (Alpine/macOS). The LAUNCHER is OS-native and lives there too.
#
# What this guards, precisely — the distinction matters, so no overclaiming: with the
# daemon enabled and its socket ABSENT or STALE (the file survived a crashed daemon,
# nothing listening), atuin does NOT fall back to a direct write. Measured on 18.19.0:
# `atuin history start` exits 0, prints a well-formed history id, writes nothing to
# stderr — and DISCARDS the entry. No error, no fallback, no row. Verified for an absent
# socket, a stale socket file, and with and without --hook; the daemon-off control writes
# every row. (It also makes the dead-socket path benchmark FASTER than a direct write,
# 4.17 ms vs 8.27 ms mean, because it is timing a no-op.)
#
# So this guard is DATA-LOSS PREVENTION, not a latency optimisation: keep probing (see the
# throttle below) and, the first time nothing is listening, force the daemon off for THIS shell
# so atuin really does write SQLite directly. Mostly silent by design — but what a missing daemon
# would otherwise cost is the history itself, not milliseconds.
#
# What it does NOT guard: an ACCEPT-BUT-SILENT socket — something is listening (systemd
# socket activation holding the socket while the daemon behind it is dead or wedged) and
# the connect succeeds, so no cheap shell-side probe can tell it from a healthy daemon.
# That is the shape of upstream atuinsh/atuin#3382's indefinite freeze, and it is why
# core/atuin/config.toml recommends the plain always-running unit over the .socket
# variant, and `autostart = true` (atuin health-checks its own daemon) where there is no
# service manager. Proving liveness would mean a bounded application-level request on the
# startup path — a fork and a timeout per shell, which this file exists to avoid.
#
# It is a WATCHDOG, not merely a startup probe — because the silent-discard behaviour above is
# what makes that difference load-bearing. A daemon that dies mid-session costs that shell not
# latency but EVERY command it runs afterwards, unrecorded and unannounced; on a long-lived tmux
# session (especially with Linger=no, where the daemon stops with the last login session) that is
# how a day of history disappears with no symptom until you go looking for a command you know you
# ran — dotgibson/dotfiles-core#366. So the hook STAYS on precmd and re-probes, THROTTLED: a real
# connect(2) at most once every $_CORE_ATUIN_DAEMON_INTERVAL seconds, behind a clock comparison,
# so the per-prompt cost in the healthy case is one arithmetic expression over three integers.
# That is the honest version of this file's startup-cost discipline: what it forbids on the prompt
# path is an UNCONDITIONAL syscall, not the compare that decides whether to make one. Measured
# here, the probe itself is ~0.06-0.10ms against a local unix socket (the zmodload after the first
# is ~8us), so the window could be far shorter than it is. It is 60s because precmd fires per
# PROMPT, not per second — an idle pane pays nothing and records nothing, so the probe rate is
# already bounded by how fast you type — and because the throttle's real job is the case where
# connect(2) is NOT cheap: a socket path on a networked or wedged filesystem, where it can block
# with no timeout available to us. CORE_ATUIN_PROBE_INTERVAL is the escape hatch for that box.
#
# DEGRADATION IS ONE-WAY. The first failed connect disables the daemon for this shell and unhooks
# the guard for good; it never re-enables. Direct writes always work, so a false positive costs
# only the lock relief until the next shell — the same asymmetry the zsh/net/socket fallback below
# is decided on. That is also why a probe landing in the shipped unit's RestartSec=3 gap is allowed
# to degrade a shell that would have recovered: during that gap atuin IS discarding, so degrading
# is the right answer even when it is early. Re-enabling would mean trusting, on the prompt path
# and for the rest of the session, a socket we just watched lie.
#
# IT WARNS EXACTLY ONCE, AND ONLY MID-SESSION. A shell already degraded at its first prompt says
# nothing — nothing changed under the user, and the machines that simply do not run the daemon
# must not learn a new line of startup noise. A shell that HAD a working daemon and lost it prints
# one _core_warn line, because its history plumbing changed under a session that is still open.
# _CORE_ATUIN_DAEMON_WAS_UP is the entire discriminator, and "once" is structural (the degrade path
# unhooks before it warns), not a second flag to keep in sync.
#
# THE CLOCK, at load position 00. $EPOCHSECONDS is a zsh/datetime parameter and 60-update.zsh —
# fragment 60 — is what loads that module, AFTER this file. It does not matter: the hook's BODY
# first runs at the first precmd, by which point every fragment has been sourced, so in a normal
# shell EPOCHSECONDS is already there and costs this file nothing. Loading zsh/datetime here
# instead would be a module load on every interactive shell to buy an answer that is already free.
# Where it is genuinely absent — CORE_PROFILE=minimal stops after 30-functions, and the unit tests
# source this file alone — ${EPOCHSECONDS:-SECONDS} falls back to $SECONDS (seconds since this
# shell started, a builtin parameter, no module). Both are fork-free integers that only go up,
# which is all a throttle needs; the guard's gate handles the fact that they share no epoch.
#
# NOT gated: `atuin init zsh` above. That script is daemon-agnostic — the daemon is used
# at COMMAND time by the hooks it registers — so gating it would only cost the Ctrl+E TUI.
# Runs at the FIRST precmd, not at source time — and then, throttled, for the life of the
# shell: the OS (80) and host (99) fragments load
# AFTER this file, so the opt-in env isn't set yet while 00-tools.zsh is being sourced.
# A named function (not an inline hook body) so scripts/test-core.sh can drive it directly.
# precmd_functions is edited DIRECTLY (the same idiom as the _cmd_block_precmd reorder
# above) rather than via add-zsh-hook: on a box with atuin but no starship, autoloading
# add-zsh-hook for this one registration is a measurable ~1ms of shell startup — the exact
# cost this file exists to avoid — and APPEND is all we need. Appending also keeps the
# `$?`-sensitive hooks (_cmd_block_precmd, starship_precmd) first, where they must be.
# The guard's whole state — grepping _CORE_ATUIN_DAEMON_ returns all of it. Declared
# unconditionally, like the function itself; only the precmd REGISTRATION below is
# HAVE_ATUIN-gated, because scripts/test-core.sh drives the guard on a box with no atuin and a
# test that has to construct the state it then asserts on proves nothing. Two typesets, ~1us
# each: the entire startup cost of turning the probe into a watchdog.
#   _INTERVAL  seconds between real connects — and, in the gate below, the largest clock jump the
#              throttle will believe. Seeded with the DEFAULT here and re-resolved from
#              CORE_ATUIN_PROBE_INTERVAL inside the guard, NOT read from the environment at this
#              point: os/<os>.zsh (80) and 99-local.zsh (99) load AFTER this file, so a
#              per-machine knob is not set yet while 00-tools.zsh is being sourced — the same
#              load-order fact that puts the whole probe on the first precmd. Reading it here
#              would silently ignore every override written in the layer that would actually
#              write one. A garbage or negative value evaluates to <= 0 under `typeset -gi`,
#              which means "probe every prompt": fail-safe, in the direction that keeps history.
#   _NEXT      earliest clock value at which the next connect may happen. 0 = due now, which is
#              why the FIRST precmd probes undelayed. The tests back-date it to time-travel.
typeset -gi _CORE_ATUIN_DAEMON_INTERVAL=60
typeset -gi _CORE_ATUIN_DAEMON_NEXT=0
_core_atuin_daemon_guard() {
  local -i _rc=$? # FIRST line: emulate resets $?. The hook is PERSISTENT now, so a precmd an OS
                  # (80) or host (99) fragment appends AFTER it would otherwise see our return
                  # value instead of the user's command status. Two integer ops buys that
                  # transparency for good; the one-shot never had to care.
  emulate -L zsh
  # THROTTLE — the whole per-prompt cost of the healthy case: one arithmetic expression over three
  # integers. No fork, no subshell, no syscall, and no parameter EXPANSION beyond the clock read
  # (inside (( )) a bare name IS the parameter). The second conjunct is the one that matters:
  # honour the deadline only while it is at most one interval away. A deadline further out than
  # that does not mean we are early, it means the CLOCK moved under us — a backwards NTP step, a
  # resume from suspend, or the EPOCHSECONDS/SECONDS fallback changing source mid-shell (they
  # share no epoch) — and honouring it would park the watchdog for the length of the jump,
  # silently, which is the exact failure this hook exists to end. Every skew case therefore falls
  # through to a probe: wrong in the cheap direction, never in the expensive one.
  local -i now=${EPOCHSECONDS:-SECONDS} # ${:-} yields the literal NAME; -i evaluates it
  (( now < _CORE_ATUIN_DAEMON_NEXT &&
     _CORE_ATUIN_DAEMON_NEXT - now <= _CORE_ATUIN_DAEMON_INTERVAL )) && return $_rc
  # STAND-DOWN, permanently. Both conditions are settled by the time the first precmd runs (80 and
  # 99 have been sourced), and a machine that never opted in must not carry even the compare above
  # for the life of the shell — so this UNHOOKS rather than returning.
  # The truthy set is config-rs's (the crate atuin parses this env with), not just "true":
  # someone who writes ATUIN_DAEMON__ENABLED=1 has opted in as far as atuin is concerned,
  # so the guard must agree or it silently sits out exactly when it is needed. AUTOSTART means
  # atuin supervises the daemon itself, so an absent socket there is a cue to start one, not a fault.
  if [[ ${ATUIN_DAEMON__ENABLED:l} != (1|t|true|y|yes|on) ]] ||
    [[ ${ATUIN_DAEMON__AUTOSTART:l} == (1|t|true|y|yes|on) ]]; then
    precmd_functions=(${precmd_functions:#_core_atuin_daemon_guard})
    return $_rc
  fi
  # Resolve the window HERE rather than at source time, for the same load-order reason the whole
  # probe is deferred to the first precmd: 80/99 have not been sourced yet while this file is,
  # so a per-machine CORE_ATUIN_PROBE_INTERVAL would be invisible to a source-time read. Once per
  # PROBE (not per prompt), immediately before a zmodload and a connect(2) — so one parameter
  # expansion is free here, while the throttle gate above stays expansion-free. Re-resolving each
  # probe also means the knob can be changed mid-session and takes effect at the next window.
  typeset -gi _CORE_ATUIN_DAEMON_INTERVAL=${CORE_ATUIN_PROBE_INTERVAL:-60}
  # Same default atuin resolves: $XDG_RUNTIME_DIR/atuin.sock, falling back to the data dir
  # where XDG_RUNTIME_DIR is unset (macOS). Re-resolved on EVERY probe, never cached: if
  # XDG_RUNTIME_DIR is torn down mid-session (systemd removes /run/user/$UID at the last logout —
  # the SAME event that stops the daemon under Linger=no) we must follow atuin to the path it will
  # actually use, not keep probing one nobody binds any more.
  local sock="${ATUIN_DAEMON__SOCKET_PATH:-${XDG_RUNTIME_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/atuin}/atuin.sock}"
  # A real connect, because a stale socket FILE passes a plain -S test — which is exactly
  # the case that hangs. zsocket returns non-zero immediately when nothing is listening;
  # on success it hands back an open fd in $REPLY that we close right away. REPLY is
  # LOCAL: zsocket writes it, and clobbering the caller's REPLY from a precmd hook would
  # be a nasty little cross-talk bug — which matters MORE now than it did as a one-shot, because
  # this runs between every pair of commands for the life of the shell and read/vared/zsocket/
  # completion all live in $REPLY. `--` because the path comes from the environment.
  #
  # The daemon stays on ONLY when a connect actually succeeded. If zsh/net/socket is
  # missing (it ships with zsh everywhere the fleet runs, so this is near-dead code), we
  # fall through to the disable path rather than settling for `[[ -S $sock ]]` — trusting
  # the existence test would leave the daemon enabled on exactly the stale socket this
  # guard exists to catch. Cost of being wrong that way is the lock relief, and
  # core-doctor says so; cost of the other way is the failure mode itself.
  local REPLY
  if zmodload -F zsh/net/socket +b:zsocket 2>/dev/null && zsocket -- "$sock" 2>/dev/null; then
    exec {REPLY}>&-
    typeset -g _CORE_ATUIN_DAEMON_WAS_UP=1 # "a connect worked here, at least once"
    typeset -gi _CORE_ATUIN_DAEMON_NEXT=$((now + _CORE_ATUIN_DAEMON_INTERVAL))
    return $_rc
  fi
  # DEGRADE — one way, and terminal. Unhook FIRST, so nothing below can leave the hook armed to
  # warn a second time; "once" is structural, not a fourth flag to keep in sync.
  precmd_functions=(${precmd_functions:#_core_atuin_daemon_guard})
  export ATUIN_DAEMON__ENABLED=false                           # degrade to direct SQLite writes
  typeset -g _CORE_ATUIN_DAEMON_DEGRADED=1                     # core-doctor reports it
  # Warn ONLY if this shell ever had a working daemon. Already-down-at-startup stays as silent as
  # it has always been — nothing changed under the user.
  [[ -n ${_CORE_ATUIN_DAEMON_WAS_UP:-} ]] || return $_rc
  local msg="atuin daemon went away — this shell now writes history directly (no lock relief)"
  # 05-ui.zsh is fragment 05 and this body runs at precmd, so _core_warn/_core_hint are always
  # there in a real shell. The fallback is for this file sourced STANDALONE (the unit tests, an OS
  # repo poking at it): a message this shell only ever gets one chance to deliver is not worth
  # losing to a missing helper. Plain ASCII, because 05-ui.zsh is also where the non-UTF-8 glyph
  # degradation lives.
  if (($+functions[_core_warn])); then
    _core_warn "$msg"
    _core_hint "restart the daemon, then open a new shell to use it again; core-doctor shows the state"
  else
    print -u2 -r -- "! $msg"
  fi
  return $_rc
}
[[ -n ${HAVE_ATUIN:-} ]] &&
  precmd_functions=(${precmd_functions:#_core_atuin_daemon_guard} _core_atuin_daemon_guard)

unfunction _have 2>/dev/null
