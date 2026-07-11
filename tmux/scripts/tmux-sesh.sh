#!/usr/bin/env bash
# core/tmux/scripts/tmux-sesh.sh — smart session picker (sesh) with fallback.
# ──────────────────────────────────────────────────────────────────────────────
# Replaces the old tmux-sessionizer.sh. If `sesh` (joshmedeski/sesh) is installed
# it drives the picker — zoxide-aware, git-repo-named sessions, sesh.toml configs
# (engagement layouts live in dotfiles-Kali's sesh config). If sesh ISN'T present
# yet, we degrade to the classic find+fzf behaviour so the prefix+f popup and the
# Ctrl-G shell widget keep working during the transition. PORTABLE CORE.
#
# Bound to: prefix + f (tmux.conf) and Ctrl-G (zsh, via fzf.zsh widget).
# ──────────────────────────────────────────────────────────────────────────────
set -u

if command -v sesh >/dev/null 2>&1; then
  # sesh list = configs + running tmux sessions + zoxide dirs; connect creates-or-switches
  selected=$(
    sesh list --icons | fzf \
      --reverse --border-label ' sesh ' --prompt '⚡  ' \
      --height 100% \
      --bind 'tab:down,btab:up' \
      --bind 'ctrl-a:change-prompt(⚡  )+reload(sesh list --icons)' \
      --bind 'ctrl-t:change-prompt(🪟  )+reload(sesh list -t --icons)' \
      --bind 'ctrl-g:change-prompt(⚙️  )+reload(sesh list -c --icons)' \
      --bind 'ctrl-d:change-prompt(📁  )+reload(sesh list -z --icons)' \
      --preview-window 'right:55%' \
      --preview 'sesh preview {}'
  )
  [[ -z "$selected" ]] && exit 0
  exec sesh connect "$selected"
fi

# ── Fallback: classic find + fzf sessionizer (no sesh installed) ──────────────
SEARCH_DIRS=("$HOME/Projects" "$HOME/dev" "$HOME/work" "$HOME/.config" "$HOME/engagements")
find_args=()
for d in "${SEARCH_DIRS[@]}"; do [[ -d "$d" ]] && find_args+=("$d"); done
[[ ${#find_args[@]} -eq 0 ]] && exit 0

selected=$(find "${find_args[@]}" -mindepth 1 -maxdepth 2 -type d 2>/dev/null |
  fzf --reverse --prompt 'Project ❯ ' \
    --preview '{ eza --icons --tree --level=1 {} 2>/dev/null || ls -la {} 2>/dev/null; } | head -30')
[[ -z "$selected" ]] && exit 0

name=$(basename "$selected" | tr '[:upper:] .' '[:lower:]__')
tmux has-session -t "$name" 2>/dev/null || tmux new-session -ds "$name" -c "$selected"
if [[ -n "${TMUX:-}" ]]; then tmux switch-client -t "$name"; else tmux attach -t "$name"; fi
