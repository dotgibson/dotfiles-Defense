# core/zsh/45-plugins.zsh
# ──────────────────────────────────────────────────────────────────────────────
# Lightweight zsh plugin loader — no Oh My Zsh, no Zinit. Plugins are auto-cloned
# to $XDG_DATA_HOME/zsh/plugins on first launch (v4: cloned code is DATA, not config —
# it leaves the symlinked $ZDOTDIR tree). Portable: needs git + network on first run
# only. Load AFTER 35-fzf.zsh + 40-bindings.zsh so the
# vi-mode init fires the binding hook with the widgets already defined, and AFTER
# 10-options.zsh (which ran compinit — required by fzf-tab AND carapace).
#
# 2026 refresh:
#   • zsh-defer (romkatv) async-loads the two heaviest plugins (autosuggestions +
#     zsh-syntax-highlighting) AFTER the first prompt paints — the shell is
#     interactive instantly and they "catch up" a few ms later.
#   • carapace (multi-shell completion, 500+ commands) feeds INTO fzf-tab.
#
# zsh-syntax-highlighting (z-sy-h) ORDER RULE: per its README it must be sourced as
# LATE as possible (it wraps ZLE widgets, so anything that defines/redefines widgets
# must already be loaded), and zsh-history-substring-search MUST be sourced AFTER it
# (z-sy-h re-wraps history-substring-search's widgets when it sees them). We honour
# both: the highlighter is the LAST of the deferred trio, and history-substring-search
# is deferred right after it so its widgets are wrapped. Both run on the same deferred
# queue (FIFO), so the queued order == the source order.
#
# FORMATTER WARNING: the `(( $+functions[zsh-defer] ))` / `[fzf-tab-complete]`
# guards below MUST keep their hyphens un-spaced. A shell formatter (shfmt) that
# doesn't grok zsh will rewrite `[zsh-defer]` → `[zsh - defer]`, turning the
# associative-array key into an arithmetic expression that's always 0 — silently
# disabling deferral and the fzf-tab styling. Keep them exactly as written.
# ──────────────────────────────────────────────────────────────────────────────

ZPLUGINDIR="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"

# ── Pinned plugin revisions ───────────────────────────────────────────────────
# These plugins are the ONLY third-party CODE that runs in every interactive shell
# on every one of the 9 OS repos, yet they were the one thing this repo left
# UNPINNED while pinning its CI linters (ci.yml), pre-commit hooks (rev:), and even
# GitHub Actions by SHA. An unpinned `master` clone means an upstream breaking
# change — or a compromised tag — fans out to every machine on the next install.
# So pin each to a commit, exactly like the rest of the toolchain. Keyed by the
# FULL owner/name slug so `make update-plugins` (scripts/update-plugins.sh) can
# ls-remote each and rewrite the SHA deliberately — the runtime never floats.
# A plugin with no entry here falls back to the old floating `--depth=1` clone.
typeset -gA ZPLUGIN_PINS=(
  romkatv/zsh-defer                          53a26e287fbbe2dcebb3aa1801546c6de32416fa
  jeffreytse/zsh-vi-mode                      91cafe4a09b6670cb8e761aa413e5f7b9e00816f
  zsh-users/zsh-history-substring-search      14c8d2e0ffaee98f2df9850b19944f32546fdea5
  zsh-users/zsh-autosuggestions               85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5
  zsh-users/zsh-syntax-highlighting           1d85c692615a25fe2293bdd44b34c217d5d2bf04
  Aloxaf/fzf-tab                              24105b15714bfec37989ed5c5b6e60f572253019
  MichaelAquilina/zsh-you-should-use          5f3d129864ee4505043d88c3486224f1d75b692e
)

# Show first-run install progress with Core's spinner WHEN 05-ui.zsh is loaded; fall
# back to running the command plainly otherwise. An OS loader mid-migration may not
# source 05-ui.zsh yet, so `_core_spin` may not exist — never break install for it.
_zp_run() { # _zp_run <title> <cmd...>
  if (($+functions[_core_spin])); then
    _core_spin "$@"
  else
    shift
    "$@"
  fi
}

# Optional third arg: override the sourced filename
_zplugin_load() {
  local repo="${1}" name="${2}" srcfile="${3:-}"
  local plugin_path="${ZPLUGINDIR}/${name}"
  local pin="${ZPLUGIN_PINS[$repo/$name]:-}"

  if [[ ! -d "$plugin_path" ]]; then
    mkdir -p "$ZPLUGINDIR"
    if [[ -n "$pin" ]]; then
      # Fetch EXACTLY the pinned commit (shallow, detached) — reproducible and
      # supply-chain-pinned. GitHub serves arbitrary SHAs via `fetch`, so we never
      # download history we don't run. On any failure, remove the half-built dir so
      # the next shell retries cleanly instead of sourcing an empty checkout. The
      # network-bound fetch carries a spinner; the local git steps are instant.
      #
      # B11: after checkout, ASSERT the resulting HEAD equals the pin before we source a
      # single line. The pin IS the trust anchor — git verifies object SHAs on fetch, but
      # this is cheap defence-in-depth that fails CLOSED if a remote ever resolves the
      # request to a different object (a tampered/misconfigured mirror): we wipe the dir
      # and refuse, rather than silently sourcing code that isn't the SHA we vouched for.
      git init -q "$plugin_path" &&
        git -C "$plugin_path" remote add origin "https://github.com/${repo}/${name}" &&
        _zp_run "installing ${name}@${pin:0:7}" \
          git -C "$plugin_path" fetch -q --depth 1 origin "$pin" &&
        git -C "$plugin_path" checkout -q --detach FETCH_HEAD &&
        [[ "$(git -C "$plugin_path" rev-parse HEAD 2>/dev/null)" == "$pin" ]] ||
        {
          echo "ERROR: failed to install ${name}@${pin:0:12} (or it did not resolve to the pinned commit)" >&2
          rm -rf "$plugin_path"
          return 1
        }
    else
      _zp_run "installing ${name}" \
        git clone --depth=1 "https://github.com/${repo}/${name}" "$plugin_path" ||
        {
          echo "ERROR: failed to install ${name}" >&2
          return 1
        }
    fi
  fi
  # NB: an already-present plugin is sourced AS-IS — no per-start `git` call — so
  # the hot path keeps zero plugin subprocesses. Reconciling a moved pin is the job
  # of `zplugin-update` / the maint runner, not every interactive shell.

  if [[ -n "$srcfile" ]] && [[ -f "${plugin_path}/${srcfile}" ]]; then
    source "${plugin_path}/${srcfile}"
  elif [[ -f "${plugin_path}/${name}.plugin.zsh" ]]; then
    source "${plugin_path}/${name}.plugin.zsh"
  elif [[ -f "${plugin_path}/${name}.zsh" ]]; then
    source "${plugin_path}/${name}.zsh"
  elif [[ -f "${plugin_path}/${name}.sh" ]]; then
    source "${plugin_path}/${name}.sh"
  fi
}

function zplugin-update {
  local dir name pin
  for dir in "${ZPLUGINDIR}"/*/; do
    if [[ -d "$dir" ]]; then
      name=$(basename "$dir")
      # A pinned plugin is held AT its pin — `make update-plugins` is the only thing
      # that moves a pin. So here we re-assert the recorded SHA (fetch+detach) rather
      # than pulling a branch that would drift the runtime off its pin. Unpinned
      # plugins keep the old fast-forward-pull behaviour. We scan the ZPLUGIN_PINS keys
      # for the slug whose tail is /$name (the dir basename), so a pin can be keyed by
      # the full owner/name without the owner having to be spelled out again here.
      pin=""
      local k
      for k in "${(@k)ZPLUGIN_PINS}"; do [[ "$k" == */"$name" ]] && pin="${ZPLUGIN_PINS[$k]}"; done
      if [[ -n "$pin" ]]; then
        echo "Pinning ${name} → ${pin:0:12}..."
        git -C "$dir" fetch -q --depth 1 origin "$pin" 2>/dev/null &&
          git -C "$dir" checkout -q --detach FETCH_HEAD 2>/dev/null &&
          [[ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" == "$pin" ]] ||
          echo "  ! could not set ${name} to ${pin:0:12}" >&2
      else
        echo "Updating ${name} (unpinned)..."
        git -C "$dir" pull --ff-only 2>/dev/null
      fi
    fi
  done
}

# ── zsh-defer FIRST, so we can defer the heavy plugins below ──────────────────
_zplugin_load romkatv zsh-defer
# helper: defer if zsh-defer loaded, else load synchronously (bare-box safe)
_defer_or_now() {
  if (($+functions[zsh-defer])); then zsh-defer _zplugin_load "$@"; else _zplugin_load "$@"; fi
}

# =========================================================
# Plugins
# =========================================================
# Loaded NOW: zsh-vi-mode MUST be synchronous — it resets all bindings on init
# and fires the zvm_after_init hook (40-bindings.zsh) that registers our keymap, so
# it has to run on the critical path.
_zplugin_load jeffreytse zsh-vi-mode

# DEFERRED (heavy; not needed before the first prompt). The widgets these provide
# are bound in the zvm_after_init hook (40-bindings.zsh), but — exactly like
# autosuggest-toggle below — bindkey happily records a binding to a not-yet-loaded
# widget, and the widget materialises right after the first prompt, long before
# you could press the key. So history-substring-search is deferred too: its
# history-substring-search-up/down widgets (Up/Down in 40-bindings.zsh) only need to
# exist by keypress, and deferring takes its source cost off shell startup.
# NOTE: autosuggest-toggle (bound to Ctrl-\ in 40-bindings.zsh) is bound
# UNCONDITIONALLY there for the same reason — a widget-exists guard at vi-mode
# init time would always be false and silently drop the bind.
#
# ORDER (load-bearing — see the z-sy-h note in the header): autosuggestions, THEN
# zsh-syntax-highlighting as the LAST widget-wrapping plugin, THEN
# zsh-history-substring-search so z-sy-h has already wrapped ZLE before hss adds its
# widgets (z-sy-h's README requires hss to be sourced after it). zsh-defer's queue is
# FIFO, so this queue order is the eventual source order.
_defer_or_now zsh-users zsh-autosuggestions
_defer_or_now zsh-users zsh-syntax-highlighting
_defer_or_now zsh-users zsh-history-substring-search

# zsh-syntax-highlighting theming — minimal: the `main` highlighter (default) plus
# `brackets` (match/mismatch), recoloured to the Tokyo Night Storm palette already
# used by starship.toml. ZSH_HIGHLIGHT_STYLES is read live by the highlighter as it
# repaints, so setting it here (before or after the deferred source) takes effect on
# the first repaint. (Replaces the old fast-syntax-highlighting FAST_THEME/FAST_HIGHLIGHT
# theming — z-sy-h uses ZSH_HIGHLIGHT_HIGHLIGHTERS + ZSH_HIGHLIGHT_STYLES instead.)
typeset -ga ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets)
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[command]='fg=#9ece6a'              # green  — valid command
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#9ece6a'              # green
ZSH_HIGHLIGHT_STYLES[function]='fg=#9ece6a'             # green
ZSH_HIGHLIGHT_STYLES[alias]='fg=#9ece6a'                # green
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#f7768e'        # red    — bad command/syntax
ZSH_HIGHLIGHT_STYLES[path]='fg=#7aa2f7'                 # blue   — existing path
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#e0af68' # yellow
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#e0af68' # yellow
ZSH_HIGHLIGHT_STYLES[comment]='fg=#565f89'              # muted comment

# ── carapace: multi-shell completion engine (feeds fzf-tab). After compinit. ──
if [[ -n ${HAVE_CARAPACE:-} ]]; then
  export CARAPACE_BRIDGES='zsh,fish,bash' # borrow completions a tool ships for another shell
  zstyle ':completion:*' format $'\e[2;37m── %d ──\e[m'
  # Salt the cache on CARAPACE_BRIDGES (read at generation) so changing the bridge list
  # busts the cache — mirrors 00-tools.zsh's atuin/ATUIN_NOBIND salting.
  [[ -n ${HAVE_CARAPACE:-} ]] && _cache_eval --salt "${CARAPACE_BRIDGES:-}" carapace carapace _carapace zsh
fi

# fzf-tab (load after compinit + carapace, before other completion wrappers)
_zplugin_load Aloxaf fzf-tab
if (($+functions[fzf-tab-complete])); then
  zstyle ':fzf-tab:*' fzf-command fzf
  # Resolve the preview binaries the same way 35-fzf.zsh does — fzf-tab runs these in a
  # subshell, so a literal `eza`/`bat` would break on a bare box (no eza) or Debian
  # (bat is `batcat`). The cd preview degrades to `ls`; the file preview reuses the
  # placeholder-free $_FZF_TAB_PREVIEW_CMD (bat→cat, set in 35-fzf.zsh, loaded before this)
  # and lets fzf-tab append $realpath. NB: $_FZF_PREVIEW_CMD ends in fzf's `{}`, which
  # fzf-tab does NOT substitute — using it here would pass a stray literal `{}` to bat.
  if [[ -n ${HAVE_EZA:-} ]]; then
    zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza --icons --tree --level=1 $realpath'
  else
    zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -la $realpath'
  fi
  zstyle ':fzf-tab:complete:*:*' fzf-preview '$_FZF_TAB_PREVIEW_CMD $realpath 2>/dev/null'
  zstyle ':fzf-tab:*' switch-group '<' '>'
fi

# zsh-you-should-use — reminds you of aliases when typing full commands
_defer_or_now MichaelAquilina zsh-you-should-use you-should-use.plugin.zsh
export YSU_MESSAGE_POSITION="after"
export YSU_MODE="BESTMATCH"
export YSU_IGNORED_ALIASES=("ls" "ll" "la" "cd" "-")
