#!/usr/bin/env bash

# Define session name for scratchpad
session="_popup_scratchpad"

# Create session if it doesn't exist
if ! tmux has -t "$session" 2>/dev/null; then
  session_id="$(tmux new-session -dP -s "$session" -F '#{session_id}')"
  tmux set-option -s -t "$session_id" key-table popup
  tmux set-option -s -t "$session_id" status off
  tmux set-option -s -t "$session_id" prefix None
  session="$session_id"
fi

# Force THIS session to detach its client when the session is destroyed, overriding the
# global `detach-on-destroy off` (tmux.conf) that makes a dying session jump to another.
# Without this override, exiting the scratchpad shell destroys this session and the popup
# client — instead of closing — hops to your MAIN session, attaching a second (popup-sized,
# 80%×80%) client to it: tmux then clamps the main session to the popup's size and double-
# draws it, so the scratchpad appears to "take over" and the real terminal is left garbled.
# Detaching on destroy closes the popup cleanly instead. Per-session, so real sessions keep
# the global jump-don't-exit behaviour. Applied on EVERY open, not just at creation: the
# scratch session is persistent, so one created before this option existed would otherwise
# keep the inherited global `off` and still hijack the main session on its next close.
# `$session` is the session id (freshly created) or the name (already running) — a valid
# target either way.
tmux set-option -t "$session" detach-on-destroy on

# Attach to the scratchpad session inside the popup.
# display-popup launches this script with TERM UNSET (it does NOT inherit the calling
# pane's TERM), so the nested `tmux attach` finds no terminfo and dies with
# "open terminal failed: terminal does not support clear". Ensure a usable TERM first:
# keep a valid one if present; otherwise adopt the SAME terminal tmux gives its panes by
# reading default-terminal from the live server (so this tracks the config instead of
# hardcoding it), and only hardcode tmux-256color if that query is empty or its terminfo
# is unavailable. (No `>/dev/null`: a tmux client must render to the popup's terminal —
# redirecting its output away is itself a cause of "open terminal failed".)
if [[ -z "${TERM:-}" ]] || ! infocmp "$TERM" >/dev/null 2>&1; then
  _dt="$(tmux show-option -gv default-terminal 2>/dev/null)"
  if [[ -n "$_dt" ]] && infocmp "$_dt" >/dev/null 2>&1; then
    export TERM="$_dt"
  else
    export TERM=tmux-256color
  fi
fi
exec tmux attach -t "$session"
