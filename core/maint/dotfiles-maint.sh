#!/usr/bin/env bash
# core/maint/dotfiles-maint.sh — the daily "update everything (that's safe)" runner.
# ──────────────────────────────────────────────────────────────────────────────
# Invoked by a scheduler (systemd user timer / launchd / cron) at a fixed time —
# install it with `maint-install` (see core/zsh/55-maint.zsh). Designed to run
# UNATTENDED and NON-INTERACTIVE: every step is guarded, time-limited, and failure
# of one step never aborts the rest. Updates the USER-SPACE stack (brew, plugin
# managers, editor) automatically — those are low-risk. SYSTEM packages are only
# *checked* (the shell nudge cache is refreshed); applying them stays manual via
# `up`, unless you explicitly opt in (and never on Arch/Gentoo/Kali — see below).
#
# Env knobs (set in the scheduler unit or your shell before a manual run):
#   MAINT_SYSTEM_UPGRADE=0   # 1 = also apply system pkgs (apt/dnf/zypper/brew ONLY)
#   ZPLUGINDIR=~/.local/share/zsh/plugins
#   MAINT_NVIM_TIMEOUT=600    MAINT_BREW_TIMEOUT=900    MAINT_TS_TIMEOUT=300
#   MAINT_RUSTUP_TIMEOUT=600 # seconds `rustup update` may block
#   MAINT_MISE_TIMEOUT=2700  # seconds EACH mise step may block (source builds — see below)
#   MAINT_ENABLED=1          # 0 = no-op (e.g. drop a guard on a Kali engagement box)
# ──────────────────────────────────────────────────────────────────────────────

# Fail on unset vars and broken pipes. `-e` is deliberately omitted: an unattended
# runner must let one failed step continue to the next (step() handles per-step rc),
# but nounset catches typo'd env knobs and pipefail surfaces mid-pipe failures.
set -uo pipefail

# A scheduler hands us a minimal environment: validate HOME first, then build a sane
# PATH — append any inherited PATH only when it's set, so a stripped cron/systemd env
# (which may omit PATH entirely) doesn't trip nounset before we've built one.
export HOME="${HOME:?}"
# ${CARGO_HOME:-$HOME/.cargo}/bin is where rustup drops the `rustup`/`cargo` shims
# (mise's rust backend installs rustup there too). A scheduler's minimal PATH omits
# it, so without this the `have rustup` guard below is false and the rust step
# silently skips — the exact unattended case it exists to cover. `:-` default keeps
# it nounset-safe when CARGO_HOME is unset.
# NO OS-specific prefix belongs here: this file is portable Core, vendored into every
# OS repo. The scheduler unit written by `maint-install` bakes in the LIVE PATH of the
# shell that installed it (zsh/55-maint.zsh), which is where a Homebrew/pkgsrc/Nix
# prefix legitimately enters — supplied by the OS, not hardcoded by Core. What remains
# below is only the POSIX floor for a hand-wired scheduler that supplies no PATH at all.
# ORDER IS LOAD-BEARING: intentional prepends, then the CAPTURED PATH, then the floor.
# The captured PATH must outrank the floor — an Apple-Silicon shell puts the Homebrew bin
# ahead of a legacy /usr/local/bin, and appending it last would silently run the legacy
# brew instead. The floor is a last resort for a hand-wired scheduler, not a preference.
export PATH="$HOME/.local/bin:${CARGO_HOME:-$HOME/.cargo}/bin${PATH:+:$PATH}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
# v4: plugins are DATA (under $XDG_DATA_HOME), no longer in the $ZDOTDIR config tree.
: "${ZPLUGINDIR:=${XDG_DATA_HOME}/zsh/plugins}"
: "${MAINT_ENABLED:=1}"
: "${MAINT_SYSTEM_UPGRADE:=0}"
: "${MAINT_NVIM_TIMEOUT:=600}"
: "${MAINT_TS_TIMEOUT:=300}" # seconds the headless TS parser update may block (see below)
: "${MAINT_BREW_TIMEOUT:=900}"
# Deliberately the largest knob here, because a mise step is the one that COMPILES.
# On musl (Alpine) mise defaults `all_compile` to true — every precompiled runtime it
# would otherwise fetch is glibc-linked — so node/python/ruby are built from source on
# every version bump, and node alone is tens of minutes. 2700s is sized for that build, not
# for a download: a cold node 24 build on a 32-core musl box was still in V8 past 21 minutes,
# so 1800 left too little headroom on a slower or busier machine — and a ceiling that trips
# on the healthy path would turn every LTS bump into a logged failure. Applies PER STEP,
# matching MAINT_BREW_TIMEOUT's shape.
: "${MAINT_MISE_TIMEOUT:=2700}"
# The upgradable-count probe below refreshes package metadata over the network. It is a
# nudge, not a transaction — a slow mirror must cost us an accurate number, never the run.
: "${MAINT_PKGCOUNT_TIMEOUT:=180}"
# Log rotation bound (B6): trim to MAINT_LOG_KEEP lines once the log passes
# MAINT_LOG_MAX, so an append-only daily log can't grow without limit. Configurable so
# a noisy box can keep more history (or a tiny one less); KEEP < MAX or trimming churns.
: "${MAINT_LOG_MAX:=800}"
: "${MAINT_LOG_KEEP:=600}"

[[ "$MAINT_ENABLED" == 1 ]] || exit 0

LOG_DIR="$XDG_STATE_HOME/dotfiles-maint"
LOG="$LOG_DIR/maint.log"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/dotfiles-maint.lock"
mkdir -p "$LOG_DIR"

# ── single-instance lock (mkdir is atomic) ───────────────────────────────────
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "$(date '+%F %T')  another run holds the lock ($LOCK) — exiting" >>"$LOG"
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# ── keep the log from growing forever (B6: trim to KEEP once past MAX) ─────────
if [[ -f "$LOG" ]] && [[ "$(wc -l <"$LOG" 2>/dev/null || echo 0)" -gt "$MAINT_LOG_MAX" ]]; then
  # script scope, not a function — `local` is illegal here and prints an error.
  tmp="$(mktemp "${LOG}.XXXXXX")" && tail -n "$MAINT_LOG_KEEP" "$LOG" >"$tmp" && mv "$tmp" "$LOG"
fi

log() { echo "$(date '+%F %T')  $*" | tee -a "$LOG"; }
have() { command -v "$1" >/dev/null 2>&1; }

# portable timeout (GNU `timeout` / macOS `gtimeout`; else run unbounded)
_to() {
  local secs="$1"
  shift
  if have timeout; then
    timeout "$secs" "$@"
  elif have gtimeout; then
    gtimeout "$secs" "$@"
  else "$@"; fi
}

# _pkgcount <secs> <grep-ere> <cmd...> — count matching lines from a network-touching
# package probe, distinguishing "0 upgradable" from "we never got an answer".
#
# A bare `count=$(_to … <mgr> | grep -c …)` cannot make that distinction: when timeout
# SIGTERMs a stalled manager there is no output, `grep -c` prints 0, and grep's non-zero
# status — the pipeline's, since grep is the last stage — is discarded by the assignment.
# So the -1 sentinel below is bypassed on the exact failure the timeout exists to survive
# (a mirror that accepts the connection and then stalls), and the daily log asserts the box
# is up to date when nothing was measured.
#
# Capture first, then gate on how the probe DIED and deliberately NOT on the manager's own
# status: these managers use exit status to MEAN things — dnf check-update exits 100 when
# updates EXIST, pacman -Qu / checkupdates exit non-zero when there are NONE — so a general
# non-zero gate would report "unknown" on the healthy path.
#
# Two shapes count as "no answer", because `timeout` does not report one way everywhere:
#   · 124 — GNU coreutils (and macOS gtimeout) on expiry.
#   · >=128 — killed by a signal (128+n). BUSYBOX timeout reports its SIGTERM this way, as
#     143, NOT as 124; Alpine's audit caught exactly that, having reported a stalled manager
#     as 0 upgradable with the 124-only test. 137 is the same story if it escalates to KILL.
# The >=128 arm is safe to be broad: no manager in the ladder above exits anywhere near
# there on its own (dnf tops out at 100, zypper ~107, apk 99), and a probe that any signal
# cut short genuinely did not answer, whoever sent it.
#
# When neither timeout nor gtimeout is installed _to runs the command bare; nothing can then
# expire, and only a real signal reaches the >=128 arm — which is still the honest answer.
_pkgcount() {
  local secs="$1" pat="$2" out rc
  shift 2
  out="$(_to "$secs" "$@" 2>/dev/null)"
  rc=$?
  if ((rc == 124 || rc >= 128)); then
    echo -1
    return 0
  fi
  printf '%s\n' "$out" | grep -cE "$pat"
}

# run a labeled step, capture rc, never abort the script
#
# </dev/null is load-bearing, not tidiness. This runner is unattended by design, but it
# inherits whatever stdin it was started with — a terminal, when invoked via `maint-run`.
# Every step's output goes to $LOG, so a step that decides to PROMPT (dnf asking to import
# a repo signing key, git asking for credentials on an expired token, ssh asking to trust a
# host key, tpm's per-plugin clones) writes the question to the log where nobody sees it and
# then blocks on the tty forever. The run appears to stop dead after the last ✓ with no
# error — the exact shape of dotfiles-Fedora's "maint-run never completes". Handing every
# step an EOF turns each of those into a fast, logged failure that the ✗ path reports and
# continues past, which is the behaviour this runner already promises.
step() {
  local label="$1"
  shift
  log "▶ ${label}"
  if "$@" </dev/null >>"$LOG" 2>&1; then log "  ✓ ${label}"; else log "  ✗ ${label} (rc=$?) — continuing"; fi
}

log "═══════════ dotfiles-maint start ($(uname -s) $(hostname 2>/dev/null)) ═══════════"

# ── Homebrew ──────────────────────────────────────────────────────────────────
# `have brew` is the whole test. The two Homebrew prefixes this used to probe by
# absolute path were the last OS-specific literals in portable Core; the scheduler unit
# now carries the installing shell's PATH, so a box with brew resolves it here without
# Core naming a prefix. A unit written before that change carries no PATH — re-run
# `maint-install` once to refresh it (maint-status reports when that is pending).
if have brew; then
  step "brew update" _to "$MAINT_BREW_TIMEOUT" brew update
  step "brew upgrade" _to "$MAINT_BREW_TIMEOUT" brew upgrade
  step "brew cleanup" brew cleanup -s
fi

# ── mise (runtime/tool versions per your config) ──────────────────────────────
if have mise; then
  step "mise plugins update" _to "$MAINT_MISE_TIMEOUT" mise plugins update
  step "mise upgrade" _to "$MAINT_MISE_TIMEOUT" mise upgrade --yes
  # `mise upgrade` keeps each tool current WITHIN its configured constraint
  # (python="3.12" tracks 3.12.x) but never crosses a pin — moving 3.12→3.13 is a
  # deliberate call (breakage risk for pinned tooling), so it stays manual. Surface
  # the cross-pin bumps that are available so they don't go unnoticed: `--bump`
  # compares against the latest version BEYOND the pin (plain `outdated` only shows
  # within-constraint staleness, which the upgrade just cleared). Report-only, like
  # the `up` nudge for system packages below — apply with `mise up --bump <tool>`.
  #
  # Bounded and rc-gated for the reason _pkgcount documents at length: this probe hits the
  # network to resolve "latest beyond the pin", and a registry that accepts the connection
  # and then stalls yields EMPTY output. A bare `[[ -n "$bump" ]]` reads that emptiness as
  # the happy path and logs "all runtimes current" — asserting a fact nothing measured.
  #
  # The GATE HERE IS STRICTER THAN _pkgcount's, and deliberately so — do not "fix" the
  # inconsistency. _pkgcount cannot test `rc != 0` because the managers it wraps OVERLOAD
  # exit status to mean things: `dnf check-update` exits 100 when updates EXIST, `pacman -Qu`
  # exits non-zero when there are NONE, so a general non-zero gate would report "unknown" on
  # their healthy path. That forced it down to testing only how the probe DIED (124 = GNU or
  # gtimeout expiry; >=128 = killed by a signal, which is how busybox timeout reports its own
  # SIGTERM as 143), leaving a fast hard failure to fall through as "0 upgradable".
  #
  # `mise outdated` overloads nothing: 0 whether or not bumps exist, non-zero only on a real
  # failure. So ANY non-zero is honestly "we did not get an answer" — a stall, a 500 from the
  # registry, a mise that died on a broken config — and all of them belong in the same third
  # state rather than masquerading as good news. rc is logged so the daily log can tell them
  # apart after the fact (124/143 = the timeout fired; anything else = mise itself failed).
  bump="$(_to "$MAINT_MISE_TIMEOUT" mise outdated --bump --no-header 2>/dev/null)"
  bump_rc=$?
  if ((bump_rc != 0)); then
    log "mise: bump check UNAVAILABLE (rc=${bump_rc} — mise failed, or the probe exceeded ${MAINT_MISE_TIMEOUT}s) — nudge stays silent"
  elif [[ -n "$bump" ]]; then
    log "mise: bumps available beyond your pins (apply manually: mise up --bump <tool>):"
    printf '%s\n' "$bump" | tee -a "$LOG"
  else
    log "mise: all runtimes current within their pins (no cross-pin bumps available)"
  fi
fi

# ── rust toolchains (mise delegates rolling channels to rustup) ───────────────
# mise's rust support doesn't install a standalone toolchain — it sets
# RUSTUP_TOOLCHAIN and hands off to rustup. So a rolling channel (stable/beta/
# nightly, as in mise/config.toml's `rust = "stable"`) is ALWAYS "satisfied" from
# mise's view: `mise upgrade` above is a no-op for it and never advances the
# toolchain. Moving stable forward (1.88 → 1.89 …) is rustup's job, so do it here
# — otherwise rust silently falls behind until someone runs `rustup update` by
# hand. Guarded on `have rustup`: no-op on boxes where the package manager owns
# rust (the distro note in mise/config.toml) and rustup isn't installed.
if have rustup; then
  step "rustup update" _to "${MAINT_RUSTUP_TIMEOUT:-600}" rustup update
fi

# ── zsh plugins (mirrors your zplugin-update) ─────────────────────────────────
# Pin-aware, keyed off the CONFIG, not the on-disk checkout state. plugins.zsh pins
# each plugin to a commit in ZPLUGIN_PINS; the intent is that a pinned plugin is held
# AT its pin and never floats. An earlier version used "is HEAD detached?" as the
# proxy for "is it pinned?" — but those diverge: a plugin cloned BEFORE pinning was
# introduced (or by the old floating `--depth=1` path) sits on a branch even though
# it IS pinned in config, so it was wrongly treated as unpinned and `pull --ff-only`'d
# every run — floating it off its pin, and logging a false "pull failed" for any whose
# branch can't fast-forward (upstream rebased / shallow clone). So decide by pin
# MEMBERSHIP instead: for a pinned plugin, re-assert the recorded SHA (fetch + detach,
# exactly like zplugin-update) so a branch checkout is reconciled back onto its pin and
# a rolled pin is actually applied here; only genuinely unpinned plugins fast-forward.
# Pins are read from plugins.zsh (the sourced Core module in $ZDOTDIR) with the same
# grep update-plugins.sh uses — no bash-4 assoc array, so this stays macOS bash-3.2 safe.
PLUGINS_ZSH="${ZDOTDIR:-$HOME/.config/zsh}/45-plugins.zsh"
# _pin_for <plugin-dir-name> → prints the 40-hex pin for owner/<name>, or nothing.
# The trailing whitespace+sha in the pattern anchors the match to a full pin row, so a
# name can't partial-match a longer sibling slug.
_pin_for() {
  [[ -f "$PLUGINS_ZSH" ]] || return 0
  grep -oE "[A-Za-z0-9_.-]+/$1[[:space:]]+[0-9a-f]{40}" "$PLUGINS_ZSH" 2>/dev/null |
    awk 'NR==1{print $2}'
}
if [[ -d "$ZPLUGINDIR" ]]; then
  log "▶ zsh plugins ($ZPLUGINDIR)"
  [[ -f "$PLUGINS_ZSH" ]] || log "  – $PLUGINS_ZSH not found — cannot read pins; unpinned fast-forward only"
  for d in "$ZPLUGINDIR"/*/; do
    [[ -d "$d/.git" ]] || continue
    name="$(basename "$d")"
    pin="$(_pin_for "$name")"
    if [[ -n "$pin" ]]; then
      # Pinned: hold at the recorded SHA. Already there → no network, just note it.
      # Otherwise fetch exactly that commit and detach onto it (reproducible, and the
      # way plugins.zsh installs a pin); verify HEAD landed on the pin before claiming it.
      if [[ "$(git -C "$d" rev-parse HEAD 2>/dev/null)" == "$pin" ]]; then
        log "  • ${name} pinned (${pin:0:7}) — held"
      elif git -C "$d" fetch -q --depth 1 origin "$pin" >>"$LOG" 2>&1 &&
        git -C "$d" checkout -q --detach FETCH_HEAD >>"$LOG" 2>&1 &&
        [[ "$(git -C "$d" rev-parse HEAD 2>/dev/null)" == "$pin" ]]; then
        log "  ✓ ${name} → pinned ${pin:0:7}"
      else
        log "  ✗ ${name} (could not set pin ${pin:0:7}) — continuing"
      fi
    elif ! git -C "$d" symbolic-ref -q HEAD >/dev/null 2>&1; then
      log "  • ${name} detached (unpinned) — held"
    elif git -C "$d" pull --ff-only >>"$LOG" 2>&1; then
      log "  ✓ ${name}"
    else
      log "  ✗ ${name} (pull failed) — continuing"
    fi
  done
fi

# ── byte-compile zsh modules + plugins (.zwc) ─────────────────────────────────
# Mirrors the compile-on-source loop in .zshrc, but pre-warms the cache here so
# the first shell after a dotfiles/plugin update doesn't pay the compile, AND
# additionally compiles the (deferred, heavy) plugin sources the .zshrc loop
# never touches — which is why this runs right AFTER the plugin pull above, so a
# freshly-updated plugin gets recompiled. Each file is compiled only when its
# source is newer than its .zwc (or the .zwc is missing); `source`/autoload then
# load the wordcode and skip re-parsing. zcompile is a zsh builtin, so shell out
# to zsh (-f: skip rc files; $1: the resolved ZDOTDIR). Failures are non-fatal.
if have zsh; then
  ZDOTDIR_RESOLVED="${ZDOTDIR:-$HOME/.config/zsh}"
  ZCOMPDUMP_RESOLVED="${XDG_CACHE_HOME}/zsh/zcompdump"
  # v4: the compdump moved to $XDG_CACHE_HOME and plugins to $XDG_DATA_HOME, so pass all
  # three paths as args rather than deriving them from $zd (the config dir) inside.
  # shellcheck disable=SC2016  # single quotes are intentional: $zd/$cd/$pd/$f are expanded
  # by the INNER `zsh -f -c` (with $1/$2/$3 passed as args below), not by this outer bash.
  step "zsh: byte-compile fragments + plugins" zsh -f -c '
    emulate -L zsh
    setopt extended_glob null_glob
    local zd=$1 cd=$2 pd=$3 f
    local -a targets=(
      $zd/<->-*.zsh             # numbered Core fragments (what .zshrc sources each shell)
      $cd                       # completion dump (10-options.zsh compiles at start; pre-warm)
      $pd/**/*.zsh              # plugin sources (heavy; deferred — loop skips these)
    )
    for f in $targets; do
      [[ -f $f ]] || continue
      [[ -s $f.zwc && ! $f -nt $f.zwc ]] || zcompile -R -- $f 2>/dev/null
    done
  ' dotfiles-maint-zcompile "$ZDOTDIR_RESOLVED" "$ZCOMPDUMP_RESOLVED" "$ZPLUGINDIR"
fi

# ── tmux plugins (TPM) ────────────────────────────────────────────────────────
TPM="$HOME/.config/tmux/plugins/tpm/bin"
if [[ -x "$TPM/update_plugins" ]]; then
  step "tmux: install new plugins" "$TPM/install_plugins"
  step "tmux: update plugins" "$TPM/update_plugins" all
fi

# ── Neovim: lazy.nvim sync + treesitter parsers + Mason registry ──────────────
if have nvim; then
  # One headless session: Lazy! sync (bang = synchronous), then update treesitter parsers,
  # then refresh the Mason registry, then quit.
  #
  # TREESITTER (main branch): there is NO :TSUpdateSync — that was a master-branch command, and
  # `+silent! ...` would have swallowed the "not an editor command" error, so parsers never
  # updated. On main, update is the async Lua API require('nvim-treesitter').update(); it returns
  # a task we must :wait() on, or a bare +qa! quits before parsers finish compiling. We update
  # only the INSTALLED parsers (a no-arg update resolves to 'all' and would try to pull every
  # parser); require() is pcall-guarded and auto-loads the plugin via lazy's require shim.
  step "neovim: Lazy sync / TSUpdate / MasonUpdate" \
    _to "$MAINT_NVIM_TIMEOUT" nvim --headless \
    "+Lazy! sync" \
    -c 'lua local ok,ts=pcall(require,"nvim-treesitter"); if ok then local p=require("nvim-treesitter.config").get_installed("parsers"); if #p>0 then ts.update(p):wait((tonumber(vim.env.MAINT_TS_TIMEOUT) or 300)*1000) end end' \
    "+silent! MasonUpdate" "+qa!"
fi

# ── System packages: refresh the shell-nudge cache (NON-ROOT count) ───────────
# Distro detection for the Kali / opt-in apply guard below.
OS_ID=""
[[ -r /etc/os-release ]] && OS_ID="$(
  # shellcheck source=/dev/null  # generated system file; nothing to follow at lint time
  . /etc/os-release 2>/dev/null
  echo "$ID"
)"
PKG_CACHE="$XDG_CACHE_HOME/zsh/pkg-updates"
mkdir -p "${PKG_CACHE%/*}"
count=-1
# This chain does NOT go through step(), so it gets step()'s stdin discipline explicitly:
# the `</dev/null` on `fi` below covers every branch (command substitutions inherit the
# compound statement's stdin). Without it these are the worst-shaped calls in the runner —
# stdout is swallowed by $(...), stderr by 2>/dev/null, so a manager that stops to ask a
# question is both invisible AND blocking. dnf5 is the live case: it verifies repo metadata
# against a PER-USER keyring (<cachedir>/<repo>/pubring), so a repo with repo_gpgcheck=1
# whose key only ever reached root's keyring makes every non-root --refresh prompt to import
# it — and since the answer never arrives it is never persisted, so it prompts again forever.
# EOF makes that a declined key and a slightly-low count instead of a dead run.
#
# _pkgcount bounds the ones that touch the network (via _to), for the other failure: a
# mirror that accepts the connection and then stalls — and, unlike a bare `… | grep -c`,
# reports -1 rather than 0 when the bound actually fires (see its comment above).
# pacman -Qu reads the local DB only: it cannot stall, so it stays unwrapped and counted
# directly — a 0 from it is a real 0.
if have brew; then
  count=$(_pkgcount "$MAINT_PKGCOUNT_TIMEOUT" '.' brew outdated --quiet)
elif have checkupdates; then
  count=$(_pkgcount "$MAINT_PKGCOUNT_TIMEOUT" '.' checkupdates)
elif have pacman; then
  count=$(pacman -Qu 2>/dev/null | grep -c .)
elif have dnf; then
  count=$(_pkgcount "$MAINT_PKGCOUNT_TIMEOUT" '^[a-zA-Z0-9][^ ]*[[:space:]]' dnf -q --refresh check-update)
elif have zypper; then
  count=$(_pkgcount "$MAINT_PKGCOUNT_TIMEOUT" '^v ' zypper -q list-updates)
elif have apt-get; then
  count=$(_pkgcount "$MAINT_PKGCOUNT_TIMEOUT" '^Inst ' apt-get -s upgrade)
elif have apk; then
  count=$(_pkgcount "$MAINT_PKGCOUNT_TIMEOUT" '.' apk list -u)
fi </dev/null
printf '%s\n%s\n' "${count:--1}" "$(date +%s)" >"$PKG_CACHE"
# Log the sentinel as UNKNOWN, not as "-1 upgradable". -1 is how the cache spells "we did
# not get an answer" (no supported manager, or the probe hit MAINT_PKGCOUNT_TIMEOUT), and
# the whole point of keeping it distinct from 0 is that the daily log must not assert the
# box is up to date when nothing was measured. The nudge stays silent either way — it
# needs a positive count — so this is the only place the difference is visible.
if [[ "${count:--1}" == -* ]]; then
  log "system packages: count UNAVAILABLE (no supported manager, or the probe exceeded ${MAINT_PKGCOUNT_TIMEOUT}s) — nudge stays silent"
else
  log "system packages: ${count} upgradable (cache refreshed; apply with \`up\`)"
fi

# ── Optional system apply (opt-in, and only where unattended is sane) ─────────
if [[ "$MAINT_SYSTEM_UPGRADE" == 1 ]]; then
  if [[ "$OS_ID" == kali ]]; then
    log "system upgrade SKIPPED: Kali — update engagement boxes by hand between ops"
  elif have pacman || have emerge; then
    log "system upgrade SKIPPED: Arch/Gentoo must not be upgraded unattended — run \`up\`"
  else
    # passwordless sudo required for this to work non-interactively; otherwise it
    # logs a sudo failure and moves on (safe).
    if have brew; then
      : # brew already upgraded above
    elif have dnf; then
      step "system: dnf upgrade" sudo -n dnf -y upgrade --refresh
    elif have zypper; then
      step "system: zypper up" sudo -n zypper --non-interactive up
    elif have apt-get; then
      step "system: apt upgrade" sh -c 'sudo -n apt-get update && sudo -n apt-get -y full-upgrade && sudo -n apt-get -y autoremove'
    fi
  fi
fi

log "═══════════ dotfiles-maint done ═══════════"
