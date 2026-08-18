#!/usr/bin/env bash
# core/tmux/scripts/tmux-claude.sh — Claude Code in a popup, one session per project.
# ──────────────────────────────────────────────────────────────────────────────
# The nvim integration (core/nvim/lua/gerrrt/plugins/claudecode-nvim.lua) gives you Claude
# COUPLED to an editing session — buffers, selection, diagnostics, diffs. This is the other
# half: Claude anywhere, from a shell pane, mid-rebase, in a directory with no editor open.
# Same shape as the `prefix + g` lazygit popup, rooted at #{pane_current_path}.
#
# Bound to: prefix + a (tmux.conf).
#
# WHY THIS IS NOT `display-popup -E claude`, the way lazygit is:
# lazygit is stateless — killing the popup costs nothing. A CONVERSATION IS NOT. Dismissing
# a raw `-E claude` popup would kill the session and lose the thread, which makes it worse
# than useless. So this follows tmux-scratch.sh instead: a persistent detached session the
# popup ATTACHES to, so `prefix + a` toggles visibility rather than lifetime. Quit Claude
# itself (/quit, or C-d) when you actually want the conversation gone.
#
# ONE SESSION PER PROJECT, keyed on the git root (not the cwd): every pane inside a repo
# shares one conversation, which is the granularity you actually think in. A single global
# session would hand you dotfiles-Offense's thread while you're sitting in dotfiles-core — the
# fleet is ten repos, so that would be wrong most of the time.
# ──────────────────────────────────────────────────────────────────────────────
set -u

# Gate on the binary, like tmux-sesh.sh gates on `sesh`. `claude` is in no OS repo's package
# list, so on most boxes this key must do nothing — but SILENTLY nothing is a bug report, so
# say why on the status line. display-message rather than echo: the popup closes the instant
# this script exits, so anything printed here would only flash.
if ! command -v claude >/dev/null 2>&1; then
  tmux display-message "claude CLI not installed — see :checkhealth gerrrt (nvim) for the same gate"
  exit 0
fi

# Root the conversation at the repo, falling back to the popup's cwd outside one.
root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
[[ -z "$root" ]] && root="$PWD"

# Session name: readable stem + a hash of the FULL path so two repos that happen to share a
# basename (a `docs/` in each of ten repos) don't collide onto one conversation. cksum, not
# md5sum/md5 — those diverge between Linux and macOS, and this file ships to both.
# ${root##*/} rather than basename: the command substitution strips basename's trailing newline,
# but `tr -c` runs BEFORE that and turns it into a trailing "_", so the name grew a stray
# separator. Parameter expansion has no newline to launder.
stem="$(printf '%s' "${root##*/}" | tr -c '[:alnum:]_-' '_' | tr '[:upper:]' '[:lower:]')"
hash="$(printf '%s' "$root" | cksum | cut -d' ' -f1)"
session="_popup_claude_${stem}_${hash}"

if ! tmux has-session -t "=$session" 2>/dev/null; then
  # -P -F gives us the session id, which is a stable target even if the name is later changed.
  session_id="$(tmux new-session -dP -s "$session" -c "$root" -F '#{session_id}' claude 2>/dev/null)" ||
    session_id=""

  if [[ -n "$session_id" ]]; then
    # Make the nested session inert to tmux so every keystroke reaches Claude's TUI: no status
    # bar, no prefix, and an empty key table. Same treatment tmux-scratch.sh gives its shell.
    tmux set-option -s -t "$session_id" key-table popup
    tmux set-option -s -t "$session_id" status off
    tmux set-option -s -t "$session_id" prefix None
    session="$session_id"
  elif tmux has-session -t "=$session" 2>/dev/null; then
    # LOST A RACE, which is a success: two clients can both see no session, and the one that
    # loses `new-session` gets "duplicate session". This script has no `set -e` (a failed
    # set-option must never strand you without a popup), so without this branch the loser would
    # carry an EMPTY session_id into every command below and spray errors instead of opening the
    # conversation its sibling just created. The winner already applied the options.
    : # fall through and attach by name
  else
    # Creation genuinely failed and nothing exists to attach to — say so rather than handing
    # `tmux attach` an empty target and letting it produce the confusing error.
    tmux display-message "could not start a Claude session for $root"
    exit 1
  fi
fi

# Force THIS session to detach its client when the session is destroyed, overriding the global
# `detach-on-destroy off` (tmux.conf) that makes a dying session jump to another. Without it,
# quitting Claude would hop the popup client to your MAIN session at popup dimensions, clamping
# and double-drawing your real terminal. Applied on EVERY open, not just at creation: a session
# created before this option existed would otherwise keep the inherited global `off`.
tmux set-option -t "$session" detach-on-destroy on

# display-popup launches this script with TERM UNSET (it does NOT inherit the calling pane's),
# so the nested `tmux attach` below would die with "open terminal failed: terminal does not
# support clear". Keep a valid TERM if present; otherwise adopt the same one tmux gives its
# panes by reading default-terminal from the live server, and only hardcode as a last resort.
if [[ -z "${TERM:-}" ]] || ! infocmp "$TERM" >/dev/null 2>&1; then
  _dt="$(tmux show-option -gv default-terminal 2>/dev/null)"
  if [[ -n "$_dt" ]] && infocmp "$_dt" >/dev/null 2>&1; then
    export TERM="$_dt"
  else
    export TERM=tmux-256color
  fi
fi
exec tmux attach -t "$session"
