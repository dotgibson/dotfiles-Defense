# core/zsh/fzf.zsh
# fzf config + custom zle widgets. Promoted from the Mac; portable across boxes
# (needs fzf + fd + bat + eza; all in the Core stack). The zle widgets defined
# here are bound to keys in bindings.zsh, so load this BEFORE bindings/plugins.

# =========================================================
# fzf core
# =========================================================
export FZF_DEFAULT_COMMAND='fd --type f --hidden --strip-cwd-prefix --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND='fd --type d --hidden --strip-cwd-prefix --exclude .git'

# --color is an EXPLICIT tokyonight-storm palette (matches starship.toml + the
# tmux bar), not the terminal default: this keeps fzf on-theme even when we SSH
# into an unthemed box or run under a terminal whose palette isn't tokyonight.
export FZF_DEFAULT_OPTS='
  --height=60%
  --layout=reverse
  --border=rounded
  --prompt="❯  "
  --pointer="➔ "
  --preview-window=right:65%:wrap:border-left
  --color=border:#27a1b9
  --color=fg:#c0caf5
  --color=gutter:#16161e
  --color=header:#ff9e64
  --color=hl:#2ac3de
  --color=hl+:#2ac3de
  --color=info:#545c7e
  --color=marker:#ff007c
  --color=pointer:#ff007c
  --color=prompt:#2ac3de
  --color=query:#c0caf5:regular
  --color=scrollbar:#27a1b9
  --color=separator:#ff9e64
  --color=spinner:#ff007c
'

export FZF_CTRL_R_OPTS='
  --prompt="History ❯ "
  --sort
'

# Previews run in a subshell with the literal command string baked in, so the binary
# name must be RESOLVED here — not assumed. tools.zsh (loaded before this file) sets
# $BAT_BIN to the real name (Debian/Ubuntu ship bat as `batcat`); using a literal
# `bat` printed "command not found" in every preview pane on those distros. Fall back
# to cat/ls on a bare box so the pane shows the file/dir instead of an error.
if [[ -n ${BAT_BIN:-} ]]; then
  export _FZF_PREVIEW_CMD="$BAT_BIN --color=always --style=plain,numbers --line-range=:500 {}"
  # fzf-tab does NOT substitute fzf's `{}` placeholder — it appends $realpath itself.
  # So it needs the SAME previewer WITHOUT the trailing `{}`; reusing $_FZF_PREVIEW_CMD
  # there leaked a literal `{}` arg into bat (a phantom "No such file", swallowed by
  # 2>/dev/null — and a wrong preview if a file named `{}` existed). Keep the two forms
  # distinct: `{}` for fzf proper, placeholder-free for fzf-tab (plugins.zsh appends it).
  export _FZF_TAB_PREVIEW_CMD="$BAT_BIN --color=always --style=plain,numbers --line-range=:500"
else
  export _FZF_PREVIEW_CMD='cat {}'
  export _FZF_TAB_PREVIEW_CMD='cat'
fi
# Dir preview: eza when present, classic `ls` otherwise (eza has no rename quirk — the
# only failure mode is absence, so a fallback is all it needs).
if [[ -n ${HAVE_EZA:-} ]]; then
  export _FZF_DIR_PREVIEW='eza --icons=always --tree --level=1 {}'
else
  export _FZF_DIR_PREVIEW='ls -la {}'
fi
export FZF_CTRL_T_OPTS="--preview '$_FZF_PREVIEW_CMD'"
export FZF_ALT_C_OPTS="--preview '$_FZF_DIR_PREVIEW'"

# =========================================================
# Widget: Ctrl+T — file picker (no hidden files)
# =========================================================
_fzf_file_no_hidden() {
  local result
  # Bound unconditionally in bindings.zsh (Ctrl-T), so guard here: on a box without
  # fzf/fd, warn in Core's voice and repaint the prompt instead of running an empty
  # "$FD_BIN" (unset on a bare box) piped into a missing fzf ("command not found").
  # Mirrors the Alt-Z (_fzf_zoxide_jump) guard below.
  if ! _core_have fzf || [[ -z ${FD_BIN:-} ]]; then
    _core_warn "Ctrl-T: needs fzf + fd"
    zle reset-prompt
    return 1
  fi
  result=$("$FD_BIN" --type f --strip-cwd-prefix --exclude .git | fzf --preview "$_FZF_PREVIEW_CMD") &&
    LBUFFER+="$result"
  zle reset-prompt
}

zle -N _fzf_file_no_hidden

# =========================================================
# Widget: Alt+Z — zoxide project jumper
# =========================================================
_fzf_zoxide_jump() {
  local result
  # Bound unconditionally in bindings.zsh, so guard here: on a box without zoxide/fzf,
  # warn in Core's voice and repaint the prompt rather than spewing "command not found".
  if ! _core_have zoxide || ! _core_have fzf; then
    _core_warn "Alt-Z: needs zoxide + fzf"
    zle reset-prompt
    return 1
  fi
  result=$(zoxide query -l | fzf \
    --no-sort \
    --prompt="Jump to Folder ❯ " \
    --preview="$_FZF_DIR_PREVIEW")
  if [[ -n "$result" ]]; then
    cd "$result" || return
  fi
  zle reset-prompt
}
zle -N _fzf_zoxide_jump

# =========================================================
# Widget: Ctrl+R — custom history searcher
# =========================================================
_fzf_history_clean() {
  local result
  # Bound unconditionally in bindings.zsh (Ctrl-R), so guard here: on a box without
  # fzf, warn in Core's voice and repaint rather than spewing "command not found"
  # from the missing fzf. Mirrors the Alt-Z (_fzf_zoxide_jump) guard above.
  if ! _core_have fzf; then
    _core_warn "Ctrl-R: needs fzf"
    zle reset-prompt
    return 1
  fi
  result=$(fc -rl 1 | awk '{$1=""; print substr($0,2)}' |
    fzf --prompt="History ❯ " --query="$LBUFFER")
  if [[ -n "$result" ]]; then
    LBUFFER="$result"
  fi
  zle reset-prompt
}
zle -N _fzf_history_clean

# =========================================================
# Widget: Ctrl+G — session picker (sesh, with graceful fallback)
# 2026 refresh: was a hand-rolled find+fzf sessionizer; now delegates to the same
# tmux-sesh.sh that prefix+f uses, so shell and tmux share one picker. sesh is
# zoxide-aware and names sessions from the git repo; the script falls back to the
# old find+fzf behaviour if sesh isn't installed yet.
# =========================================================
_tmux_sessionizer() {
  local picker="$HOME/.config/tmux/scripts/tmux-sesh.sh"
  if command -v sesh >/dev/null 2>&1; then
    local selected
    selected=$(sesh list --icons | fzf --reverse --prompt='⚡  ' --preview 'sesh preview {}')
    [[ -z "$selected" ]] && {
      zle reset-prompt
      return
    }
    if [[ -n "$TMUX" ]]; then
      sesh connect "$selected"
    else
      BUFFER="sesh connect \"$selected\""
      zle accept-line
    fi
  elif [[ -x "$picker" ]]; then
    "$picker"
  fi
  zle reset-prompt
}
zle -N _tmux_sessionizer

# =========================================================
# Global utility: fif — find text inside files
# =========================================================
fif() {
  _core_wants_help "$1" && { _core_help "fif <search_term>" "find text inside files (rg + fzf + preview)"; return 0; }
  [[ -z "$1" ]] && { _core_usage "fif <search_term>"; return 1; }
  # Defensive: degrade in Core's voice on a bare box instead of a raw "command not
  # found" — matches fcd's guard (functions.zsh).
  _core_have fzf || { _core_err "fif: requires fzf"; _core_hint "install fzf, then retry"; return 1; }
  _core_have rg  || { _core_err "fif: requires ripgrep (rg)"; _core_hint "install ripgrep, then retry"; return 1; }
  # Preview the first match with $BAT_BIN's line highlight when bat is present; fall
  # back to a plain `cat` pane on a bare box (the highlight-line flag is bat-specific).
  local fif_preview
  if [[ -n ${BAT_BIN:-} ]]; then
    fif_preview="$BAT_BIN --style=numbers --color=always --highlight-line \$(rg --line-number --no-messages \"\$FIF_TERM\" {} | cut -d: -f1 | head -n 1) {}"
  else
    fif_preview='cat {}'
  fi
  FIF_TERM="$1" rg --files-with-matches --no-messages "$1" | fzf \
    --height 80% --layout=reverse --border=rounded \
    --prompt="Text Match ❯ " \
    --preview "$fif_preview" \
    --preview-window="right:65%:wrap:border-left"
}

# =========================================================
# Global utility: fbr — fuzzy git branch checkout
# =========================================================
fbr() {
  _core_wants_help "$1" && { _core_help "fbr" "fuzzy git-branch checkout (local + remote)"; return 0; }
  _core_have fzf || { _core_err "fbr: requires fzf"; _core_hint "install fzf, then retry"; return 1; }
  _core_have git || { _core_err "fbr: requires git"; return 1; }
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    _core_err "fbr: not inside a git repository"
    return 1
  }
  local branch
  # List CLEAN branch names (no leading '* '/whitespace, no '<remote>/HEAD' alias) so the
  # preview's {} is a real ref. The old form previewed `{1}`, which on the current-branch
  # row ('* main') is the literal '*' — so `git log *` errored/blanked. On checkout, strip a
  # leading 'origin/' so picking a remote-only branch creates the matching local tracking branch.
  # NOTE: the strip is origin-ONLY on purpose — a universal `${branch#*/}` would mangle a
  # slash-containing LOCAL name (feature/foo → foo). A non-origin remote pick (e.g.
  # upstream/foo) is left as-is and `git checkout` resolves it as best it can — a rare
  # multi-remote case not worth risking the common local-branch path for.
  branch=$(git branch --all --format='%(refname:short)' 2>/dev/null |
    grep -vE '/HEAD$' | sort -u |
    fzf --preview 'git log --oneline --color=always {} | head -20') &&
    [[ -n "$branch" ]] && git checkout "${branch#origin/}"
}
