# core/zsh/10-options.zsh
# ──────────────────────────────────────────────────────────────────────────────
# Portable zsh options + the completion system. NEW in the 2026 refresh: this
# centralizes setopts and `compinit` that previously had to live in each OS repo's
# .zshrc loader (i.e. up to seven copies of the same portable config — exactly the
# drift this whole Core layer exists to kill).
#
# LOAD ORDER: source this SECOND, right after 00-tools.zsh. compinit must run here so
# it's done before fzf-tab and carapace (both in 45-plugins.zsh) and before any
# `compdef` calls (e.g. the eza completion reuse in 20-aliases.zsh).
#
# Idempotent: if your OS .zshrc still calls compinit itself, REMOVE it there —
# the sentinel below makes a double-source here a no-op, but it can't stop a
# separate caller.
# ──────────────────────────────────────────────────────────────────────────────

[[ $- == *i* ]] || return 0

# ── setopt: navigation ────────────────────────────────────────────────────────
setopt AUTO_CD    # `dotfiles-core` == `cd dotfiles-core`
setopt AUTO_PUSHD # cd pushes onto the dir stack
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt CDABLE_VARS

# ── setopt: globbing / misc ───────────────────────────────────────────────────
setopt EXTENDED_GLOB        # #, ~, ^ in globs (and the (#qN) qualifiers below)
setopt GLOB_DOTS            # globs match dotfiles (handy in a dotfiles repo)
setopt NO_NOMATCH           # don't error when a glob matches nothing
setopt INTERACTIVE_COMMENTS # allow # comments at the interactive prompt
setopt NO_BEEP
setopt NO_CLOBBER # `>` won't overwrite; use `>|` to force
setopt NUMERIC_GLOB_SORT

# ── setopt: completion behaviour ──────────────────────────────────────────────
setopt COMPLETE_IN_WORD # complete from both ends of the word
setopt ALWAYS_TO_END
setopt PATH_DIRS
setopt AUTO_MENU
setopt NO_MENU_COMPLETE # show the menu, don't auto-insert the first match
unsetopt FLOW_CONTROL   # free up Ctrl-S / Ctrl-Q

# ── Core's own completions for its first-party commands ───────────────────────
# Ship completion functions for up/extract/mkcd/mkbak/maint-log/openv so Core's
# verbs tab-complete like any system command. Resolve the dir relative to THIS
# file (`%x` = path being sourced; `:A` resolves the bootstrap symlink back to
# core/zsh/), and prepend to fpath BEFORE compinit scans it. No bootstrap symlink
# needed — fpath points straight at the vendored core/zsh/completions.
typeset -g _CORE_COMPDIR="${${(%):-%x}:A:h}/completions"
[[ -d "$_CORE_COMPDIR" ]] && fpath=("$_CORE_COMPDIR" $fpath)

# ── Completion system (cached: rebuild .zcompdump at most once per 24h) ────────
# The body is wrapped in an anonymous function so `local zcd` is genuinely
# function-scoped. This file is SOURCED at the caller's top level, where zsh (which
# has ONLY function scope) turns a bare `local` into an ordinary GLOBAL — leaking
# `zcd` into every interactive shell, fleet-wide. The anon-function wrap mirrors the
# cache pattern in 20-aliases.zsh and honours loader.zsh's "no top-level local" rule.
# compinit is safe to run in here: it declares its state with `typeset -g`, so the
# completion system persists into the shell after the function returns.
typeset -g _CORE_COMPINIT_DONE
if [[ -z $_CORE_COMPINIT_DONE ]]; then
  _CORE_COMPINIT_DONE=1
  autoload -Uz compinit
  () {
    # v4: the compdump is regenerable CACHE, not config — under $XDG_CACHE_HOME, not the
    # symlinked $ZDOTDIR config tree. Ensure the dir exists (compinit -d won't create it).
    local zcd="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
    [[ -d ${zcd:h} ]] || mkdir -p "${zcd:h}"
    # (#qN.mh+24): exists, is a file, modified >24h ago → do the full security check
    if [[ -n ${zcd}(#qN.mh+24) ]]; then
      compinit -d "$zcd"
    else
      compinit -C -d "$zcd" # fresh enough → skip the check (fast path)
    fi
    # compile the dump for a faster next start
    [[ -s "$zcd" && (! -s "${zcd}.zwc" || "$zcd" -nt "${zcd}.zwc") ]] && zcompile "$zcd"
  }
fi

# ── Completion styling (zstyle) — portable, theme-neutral ─────────────────────
zstyle ':completion:*' completer _extensions _complete _approximate
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{blue}── %d ──%f'
zstyle ':completion:*:warnings' format '%F{red}no matches%f'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompcache"
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
# NB: intentionally NO `zstyle ':completion:*' rehash true`. That re-stats EVERY $PATH
# entry on EVERY completion attempt — perceptible latency on an NFS home, linuxbrew, or
# a large mise-shims $PATH, and it fans out to all 8 OS repos. A newly-installed binary
# surfaces after `hash -r` or a new shell; the maint runner already refreshes the
# command hash after installs, so the per-Tab stat storm buys nothing here.
