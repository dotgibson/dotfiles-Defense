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
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/home/linuxbrew/.linuxbrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"
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

# run a labeled step, capture rc, never abort the script
step() {
  local label="$1"
  shift
  log "▶ ${label}"
  if "$@" >>"$LOG" 2>&1; then log "  ✓ ${label}"; else log "  ✗ ${label} (rc=$?) — continuing"; fi
}

log "═══════════ dotfiles-maint start ($(uname -s) $(hostname 2>/dev/null)) ═══════════"

# ── Homebrew ──────────────────────────────────────────────────────────────────
if have brew || [[ -x /opt/homebrew/bin/brew || -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  # Put brew on PATH if a scheduler handed us a minimal env without it. Explicit
  # if/else (not `A && B || C`): under SC2015 that idiom silently runs C when B
  # fails, and conflates "test failed" with "shellenv failed" — here we want a
  # plain Apple-Silicon-else-Linuxbrew branch.
  if ! have brew; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
  fi
  step "brew update" _to "$MAINT_BREW_TIMEOUT" brew update
  step "brew upgrade" _to "$MAINT_BREW_TIMEOUT" brew upgrade
  step "brew cleanup" brew cleanup -s
fi

# ── mise (runtime/tool versions per your config) ──────────────────────────────
if have mise; then
  step "mise plugins update" mise plugins update
  step "mise upgrade" mise upgrade --yes
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
if have brew; then
  count=$(brew outdated --quiet 2>/dev/null | grep -c .)
elif have checkupdates; then
  count=$(checkupdates 2>/dev/null | grep -c .)
elif have pacman; then
  count=$(pacman -Qu 2>/dev/null | grep -c .)
elif have dnf; then
  count=$(dnf -q --refresh check-update 2>/dev/null | grep -cE '^[a-zA-Z0-9][^ ]*[[:space:]]')
elif have zypper; then
  count=$(zypper -q list-updates 2>/dev/null | grep -c '^v ')
elif have apt-get; then
  count=$(apt-get -s upgrade 2>/dev/null | grep -cE '^Inst ')
elif have apk; then
  count=$(apk list -u 2>/dev/null | grep -c .)
fi
printf '%s\n%s\n' "${count:--1}" "$(date +%s)" >"$PKG_CACHE"
log "system packages: ${count} upgradable (cache refreshed; apply with \`up\`)"

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
