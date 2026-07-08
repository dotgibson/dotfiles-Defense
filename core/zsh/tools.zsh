# core/zsh/tools.zsh
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
  local bin
  bin="$(command -v "$1" 2>/dev/null)"
  [[ -z "$bin" ]] && return 0
  if [[ ! -s "$cache" || "$bin" -nt "$cache" ]]; then
    [[ -d "$dir" ]] || mkdir -p "$dir"
    # `>|` forces the overwrite: options.zsh sets NO_CLOBBER, under which a plain
    # `>` onto an existing cache raises "file exists" (a shell-level redirection
    # error that 2>/dev/null does NOT suppress). This regen path runs whenever the
    # tool's binary is newer than the cache — e.g. right after a brew upgrade. It
    # surfaced only for the os.zsh callers (gh/uv/ty) because they run AFTER
    # options.zsh sets NO_CLOBBER; the tools.zsh callers run before it.
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

# ── HAVE_* flags consumed by aliases.zsh / functions.zsh / fzf.zsh ────────────
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
_have carapace && HAVE_CARAPACE=1 # completion engine — init in plugins.zsh
# 2026 additions (aliases.zsh guards each):
_have xh && HAVE_XH=1
_have glow && HAVE_GLOW=1
_have doggo && HAVE_DOGGO=1
_have gron && HAVE_GRON=1
_have sd && HAVE_SD=1
_have ast-grep && HAVE_ASTGREP=1    # AST-aware structural search/rewrite — own command, no alias (the syntax-tree complement to rg=text, sd=regex, gron=JSON). Opt-in; inert without the binary.
_have gum && HAVE_GUM=1
_have viddy && HAVE_VIDDY=1         # modern watch (aliases.zsh: watch → viddy)
_have gping && HAVE_GPING=1         # graphical ping (aliases.zsh: ping → gping)
_have tldr  && HAVE_TLDR=1          # tealdeer binary (aliases.zsh: help → tldr)
# mid-2026 additions — data / disk / dev tooling (see PORTING-MATRIX package table):
_have jq && HAVE_JQ=1               # JSON processor (gron greps; jq transforms — complements)
_have yq && HAVE_YQ=1              # YAML/JSON/XML processor (the jq of YAML)
_have duf && HAVE_DUF=1             # modern df (aliases.zsh: df → duf, with df -h fallback)
_have ouch && HAVE_OUCH=1          # one-binary archive (un)packer (functions.zsh: extract prefers it)
_have hyperfine && HAVE_HYPERFINE=1 # benchmarking (the perf note at the top of this file uses it)
_have shellcheck && HAVE_SHELLCHECK=1 # shell linter (own command — no alias)
_have shfmt && HAVE_SHFMT=1        # shell formatter (own command — no alias)
_have jj && HAVE_JJ=1              # jujutsu — OPT-IN, colocated git companion (aliases.zsh: jjs/jjl/jjd)
_have sesh && HAVE_SESH=1          # smart tmux session manager — drives Ctrl-G (fzf.zsh) + prefix+f (tmux-sesh.sh); both fall back to find+fzf when unset
_have difft && HAVE_DIFFT=1        # difftastic — AST/structural diff; OPT-IN companion to delta (git dft), never the default pager (aliases.zsh: gdft)
[[ -n ${FD_BIN:-} ]] && HAVE_FD=1
[[ -n ${BAT_BIN:-} ]] && HAVE_BAT=1

# ── Tool env — set BEFORE the init evals below ────────────────────────────────
# starship reads its theme from the default ~/.config/starship.toml (bootstrap
# symlinks core/starship/starship.toml there), so no STARSHIP_CONFIG is needed.
# starship already renders the active venv, so silence Python's own prefix.
export VIRTUAL_ENV_DISABLE_PROMPT=1
# atuin binds NOTHING automatically — bindings.zsh owns Ctrl+E (atuin TUI) and
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

# Keep starship's right prompt alive. plugins.zsh (loaded after this file) pulls
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

unfunction _have 2>/dev/null
