# core/zsh/20-aliases.zsh
# ──────────────────────────────────────────────────────────────────────────────
# Aliases for the modern CLI stack. Every alias touching an optional tool is
# GUARDED by a HAVE_* flag from 00-tools.zsh, so on a bare box (fresh server, rescue
# shell) you transparently get the classic command. Load AFTER 00-tools.zsh.
# Anything offensive/engagement-flavoured lives in dotfiles-Kali, not here.
# ──────────────────────────────────────────────────────────────────────────────

# ── ls -> eza ─────────────────────────────────────────────────────────────────
if [[ -n ${HAVE_EZA:-} ]]; then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -lah --group-directories-first --icons=auto --git'
  alias la='eza -a  --group-directories-first --icons=auto'
  alias lt='eza --tree --level=2 --icons=auto'
  alias llt='eza --tree --level=3 -l --icons=auto'
  alias tree='eza --tree --icons=auto'
  (($+functions[compdef])) && compdef eza=ls # reuse ls completion for eza
else
  alias ll='ls -lah'
  alias la='ls -A'
fi

# ── cat -> bat (resolved name from 00-tools.zsh) ────────────────────────────────
if [[ -n ${HAVE_BAT:-} ]]; then
  alias cat="$BAT_BIN --paging=never"
  alias catp="$BAT_BIN"   # paged, full bat
  export BAT_THEME="ansi" # follow the terminal palette (tokyonight via ghostty)
  export MANPAGER="sh -c 'col -bx | $BAT_BIN -l man -p'"
fi

# ── find -> fd ────────────────────────────────────────────────────────────────
[[ -n ${HAVE_FD:-} ]] && alias fd="$FD_BIN"

# ── grep stays POSIX for scripts; rg is its own command (smart-case default) ──
[[ -n ${HAVE_RG:-} ]] && alias rg='rg --smart-case'

# ── cd -> zoxide (z), interactive jump (zi), `-` to previous dir ─────────────
if [[ -n ${HAVE_ZOXIDE:-} ]]; then
  alias cd='z'
  alias cdi='zi'
fi
alias -- -='cd -'

# ── disk / process / monitor ──────────────────────────────────────────────────
[[ -n ${HAVE_DUST:-} ]]  && alias du='dust'
[[ -n ${HAVE_PROCS:-} ]] && alias ps='procs'
[[ -n ${HAVE_BTOP:-} ]]  && alias top='btop' && alias htop='btop'
[[ -n ${HAVE_VIDDY:-} ]] && alias watch='viddy'
# df → duf (modern, mountpoint-aware); classic `df -h` stays the bare-box fallback.
if [[ -n ${HAVE_DUF:-} ]]; then alias df='duf'; else alias df='df -h'; fi

# ── file manager ──────────────────────────────────────────────────────────────
[[ -n ${HAVE_YAZI:-} ]] && {
  alias fm='yazi'
  alias y='yazi'
}

# ── 2026 modern stack additions (all guarded; classics untouched) ────────────
# xh: Rust HTTPie — for poking APIs / web targets. curl stays for scripts.
[[ -n ${HAVE_XH:-} ]] && {
  alias http='xh'
  alias https='xh --https'
}
# glow: render markdown in the terminal (engagement notes, READMEs)
[[ -n ${HAVE_GLOW:-} ]] && alias md='glow --pager'
# doggo: modern dig (DNS recon). dig stays as-is; this is a distinct verb.
[[ -n ${HAVE_DOGGO:-} ]] && alias dns='doggo'
# gron / sd are their own commands (no alias — never shadow sed in scripts).
# jq / yq / hyperfine / shellcheck / shfmt are likewise their own commands: they
# shadow nothing classic, so they get HAVE_* detection in 00-tools.zsh but no alias.

# ── editor + misc QoL ─────────────────────────────────────────────────────────
alias vim='nvim'
# diff: colourise ONLY when this box's diff actually supports `--color` (GNU does;
# BSD/macOS diff — the dotfiles-MacBook target — and busybox diff on Alpine do NOT,
# where an unconditional alias would make every `diff` invocation error). `--color`
# support is a STABLE property of the box's diff binary, so probing it forks the real
# `diff` on every shell for an answer that never changes. Cache the verdict keyed on the
# binary's mtime (the same invalidation _cache_eval uses): re-probe only when diff is
# newer than the cache — e.g. after a GNU/BSD toolchain change. When the cache dir isn't
# writable the live probe still decides correctly, so correctness never depends on the
# cache. (df → duf/df -h above.)
() {
  emulate -L zsh
  local bin="${commands[diff]}" cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/diff-color"
  [[ -z "$bin" ]] && return          # no diff at all → no alias
  if [[ -e "$cache" && ! "$bin" -nt "$cache" ]]; then
    [[ -s "$cache" ]] && alias diff='diff --color=auto'   # fresh cache, zero forks
    return
  fi
  # (re)probe once, then persist the verdict (non-empty = supported) for next start.
  # `>|` forces the write past 10-options.zsh's NO_CLOBBER (loaded before 20-aliases.zsh).
  if diff --color=auto /dev/null /dev/null >/dev/null 2>&1; then
    alias diff='diff --color=auto'
    mkdir -p "${cache:h}" 2>/dev/null && print -rn -- 1 >| "$cache" 2>/dev/null
  else
    mkdir -p "${cache:h}" 2>/dev/null && print -rn -- '' >| "$cache" 2>/dev/null
  fi
}

# ── git ───────────────────────────────────────────────────────────────────────
# The git alias set is the single source of truth in 25-git.zsh (OMZ-style, loaded
# right after this file). Only the non-git lazygit launcher lives here.
alias lg='lazygit'

# difftastic (difft): AST/structural diff — an OPT-IN companion to delta, never the
# default pager. delta stays the daily syntax-highlighting diff; `gdft [<ref>]` reviews
# a change by *structure*, so formatting-only churn (rewraps, moved elements, trailing
# commas) shows as no syntactic change. Wired through git's difftool (see the
# difftool "difftastic" block in git/gitconfig); guarded so it only exists when installed.
[[ -n ${HAVE_DIFFT:-} ]] && alias gdft='git difftool --tool=difftastic'

# ── jujutsu (jj) — OPT-IN, colocated git companion (NEVER shadows git) ─────────
# Guarded by HAVE_JJ (00-tools.zsh): on a box without jj these simply don't exist, so
# nothing breaks. jj is additive — it runs on top of the same `.git` repo and never
# replaces git, so we deliberately do NOT alias `git`. Just a few short verbs for the
# operator who's opted in (config: core/jujutsu/config.toml → ~/.config/jj/config.toml).
[[ -n ${HAVE_JJ:-} ]] && {
  alias jjs='jj status'
  alias jjl='jj log'
  alias jjd='jj diff'
}

# ── upstream sync (gsync) ─────────────────────────────────────────────────────
# `gsync` pushes an OS repo's vendored core/ subtree back upstream to dotfiles-core.
# Resolve the runner relative to THIS file (survives the core/ subtree living
# inside each OS repo) — the same %x trick 55-maint.zsh uses for its runner, so the
# shortcut works without putting .bin on PATH. A function (not an alias) so a
# dotfiles path containing whitespace stays one word and any args pass through.
typeset -g _SYNC_UPSTREAM_SH="${${(%):-%x}:A:h}/../.bin/sync-upstream.sh"
_SYNC_UPSTREAM_SH="${_SYNC_UPSTREAM_SH:A}"
gsync() { "$_SYNC_UPSTREAM_SH" "$@"; }

# ── named directories (~dots, ~proj) ──────────────────────────────────────────
hash -d dots="$HOME/.config"
hash -d proj="$HOME/Projects"

# ── notes (general note-taking; NOTES_DIR defaults to ~/Notes) ───────────────
: "${NOTES_DIR:=$HOME/Notes}"
alias notes='cd "$NOTES_DIR" && nvim .'

# ── safety nets (POSIX, intentionally NOT modernized) ────────────────────────
# rm: macOS overrides this to `trash` in os/macos.zsh when trash(1) is available.
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -p'

# ── help / docs ───────────────────────────────────────────────────────────────
# tealdeer: `help <cmd>` → community-curated quick-reference (complement to man).
[[ -n ${HAVE_TLDR:-} ]] && alias help='tldr'

# ── network conveniences (stay in Core; anything engagement-flavored -> Kali)─
alias myip='curl -fsS https://ifconfig.me 2>/dev/null && echo'
alias ports='ss -tulpn 2>/dev/null || netstat -tulpn'
[[ -n ${HAVE_GPING:-} ]] && alias ping='gping'
# NOTE: `serve` is now a function in 30-functions.zsh (prints the reachable URL and
# takes an optional port), replacing the old `python3 -m http.server` alias.
