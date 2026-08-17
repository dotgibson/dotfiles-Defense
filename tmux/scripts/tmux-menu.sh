#!/usr/bin/env bash
# core/tmux/scripts/tmux-menu.sh — prefix+w popup switcher.
# ──────────────────────────────────────────────────────────────────────────────
# Lists sessions + their windows and lets you fzf-jump between them. If an
# engagements dir exists ($ENGAGEMENTS_DIR, default ~/engagements), those are
# surfaced too — create-or-switch, same as tmux-eng.sh.
#
# CORE / PORTABLE: this is engagement-AGNOSTIC. On any box without an
# engagements dir (i.e. everything that isn't Kali), the ◆ section simply never
# renders and behaviour is identical to before — so it's safe to sync to all
# repos via sync-core.sh.
#
# Tab-delimited rows carry  «display ⇥ kind ⇥ payload» ; fzf shows only the
# display field (--with-nth=1) but returns the whole line, which we dispatch on.
# ──────────────────────────────────────────────────────────────────────────────

set -u

ENGAGEMENTS_DIR="${ENGAGEMENTS_DIR:-$HOME/engagements}"

build_menu() {
  # ── Sessions + windows (skip the popup scratch sessions) ──────────────────
  tmux list-sessions -F '#S' | grep -v '^_popup_' | while IFS= read -r s; do
    printf '▼ %s\tswitch\t%s\n' "$s" "$s"
    tmux list-windows -t "$s" -F "#I"$'\t'"#W" | while IFS=$'\t' read -r idx wname; do
      printf '  ⦿ %s:%s %s\tswitch\t%s:%s\n' "$s" "$idx" "$wname" "$s" "$idx"
    done
  done

  # ── Engagements (only if the dir exists — keeps this portable Core) ───────
  if [[ -d "$ENGAGEMENTS_DIR" ]]; then
    find "$ENGAGEMENTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null |
      sort -r | while IFS= read -r dir; do
      printf '◆ %s\teng\t%s\n' "$(basename "$dir")" "$dir"
    done
  fi
}

# Preview: live pane content for sessions/windows; the scope sheet for engagements.
# shellcheck disable=SC2016  # single quotes are intentional: fzf re-evaluates this
# string in its own subshell per row, where {} is fzf's placeholder and $line/$kind/
# $payload are bound there — expanding them in this shell would defeat the preview.
preview='line={}
kind=$(printf "%s" "$line" | cut -f2)
payload=$(printf "%s" "$line" | cut -f3)
case "$kind" in
  eng)    { bat --color=always --style=plain "$payload/scope/scope.txt" 2>/dev/null \
              || batcat --color=always --style=plain "$payload/scope/scope.txt" 2>/dev/null; } \
            || ls -la "$payload" ;;
  switch) tmux capture-pane -ep -t "$payload" 2>/dev/null ;;
esac'

selected=$(build_menu |
  fzf --reverse \
    --prompt="Go ❯ " \
    --delimiter='\t' \
    --with-nth=1 \
    --preview="$preview" \
    --preview-window="right:55%:wrap:border-left")

[[ -z "$selected" ]] && exit 0

kind=$(printf '%s' "$selected" | cut -f2)
payload=$(printf '%s' "$selected" | cut -f3)

case "$kind" in
eng)
  # Create the engagement session if it isn't open yet, then switch.
  name=$(basename "$payload" | tr '[:upper:] .' '[:lower:]__')
  if ! tmux has-session -t "$name" 2>/dev/null; then
    tmux new-session -ds "$name" -c "$payload"
    tmux set-environment -t "$name" ENGAGEMENT "$payload"
  fi
  tmux switch-client -t "$name"
  ;;
switch)
  tmux switch-client -t "$payload"
  ;;
esac
