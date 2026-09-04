# core/zsh/50-op.zsh
# 1Password CLI helpers — portable across machines. The macOS SSH-agent socket
# path is OS-specific and lives in os/macos.zsh, NOT here. If `op` isn't
# installed, this file does nothing.
# Docs: https://developer.1password.com/docs/cli

# `op` has the band-00 divergence too (#545), and it is the one row the doctor's own
# coverage test used to exempt on the grounds that "no alias or function is gated on it".
# That was false: this guard gates FOUR verbs — opsecret, openv, optoken, opssh — and band
# 50 still runs before 80-os.zsh, an 85-* role fragment, or 99-local.zsh. An `op`
# contributed by any of those is on PATH for the doctor's live probe and has no functions
# defined here, which is exactly the silent `✓` the ledger exists to expose.
#
# Recorded here rather than through `_have`, which 00-tools.zsh unfunctions at its end.
# Guarded on the array existing: a subscript assignment to an undeclared parameter is an
# error in zsh, and this file must stay sourceable on its own (the unit harness does that).
if command -v op >/dev/null 2>&1; then
  (( ${+_CORE_PROBED} )) && _CORE_PROBED[op]=1
else
  (( ${+_CORE_PROBED} )) && _CORE_PROBED[op]=0
  return 0
fi

# opsecret — fetch a secret by vault/item/field path
# Usage: opsecret "Personal/AWS/access_key_id"
opsecret() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "opsecret <vault>/<item>/<field>" "fetch a 1Password secret by path"; return 0; }
  if [[ -z "$1" ]]; then
    _core_usage "opsecret <vault>/<item>/<field>"
    return 1
  fi
  op read "op://$1"
}

# openv — run a command with secrets from a .env.op template
# Usage: openv .env.op npm run dev   (.env.op format: KEY=op://vault/item/field)
openv() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "openv <env-template-file> <command...>" "run a command with secrets from a .env.op template"; return 0; }
  if [[ -z "$1" ]]; then
    _core_usage "openv <env-template-file> <command...>"
    return 1
  fi
  op run --env-file="$1" -- "${@:2}"
}

# optoken — copy a TOTP code to the clipboard via Core's cross-OS `clip`
# Usage: optoken "Personal/GitHub"
optoken() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "optoken <vault>/<item>" "copy a TOTP code to the clipboard"; return 0; }
  [[ -z "$1" ]] && { _core_usage "optoken <vault>/<item>"; return 1; }
  # `clip` is the cross-OS copier this verb's whole purpose depends on — fail in Core's
  # voice if it isn't resolvable rather than letting the pipe swallow the code silently.
  _core_have clip || {
    _core_errbox "optoken: requires Core's 'clip' on PATH" \
      "why: the TOTP is piped to clip so it never lands in your shell history/scrollback" \
      "fix: wire core/bin/clip onto PATH (bootstrap links it into ~/.local/bin)"
    return 1
  }
  local otp
  otp=$(op item get "$1" --otp) || return 1
  # `--sensitive` (#690): on a box with no real clipboard backend — the headless-over-ssh
  # shelf that is the documented norm for part of the fleet — clip's OSC 52 last resort
  # under tmux used to leave the code in a tmux paste buffer, readable by anything on the
  # socket via `tmux show-buffer`, for as long as the buffer lived. Core's own
  # `set-clipboard on` (tmux.conf) is what made that the default, so the "never lands in
  # your history or scrollback" rationale above was inverted on exactly those boxes. With
  # the flag, clip reaches the outer terminal through DCS passthrough when the pane allows
  # it (no buffer at all), else through a named buffer it deletes in the same breath — and
  # it says so on stderr in that case, so the signal arrives at the moment it matters
  # rather than living in this comment. A real backend (pbcopy/wl-copy/xclip) is unchanged
  # by the flag; so is every other caller of clip, which never passes it.
  #
  # "sent", not "copied", stays the strongest true claim: OSC 52 succeeds as soon as the
  # escape is WRITTEN, not when a terminal accepts it — clipboard writes are refused by
  # default in several emulators (xterm's disallowedWindowOps) and unimplemented in others,
  # and the failure is a silent drop.
  #
  # opsecret is not in this picture: it prints via `op read` and never touches clip.
  printf '%s' "$otp" | clip --sensitive && _core_ok "TOTP sent to the clipboard"
}

# opssh — list SSH keys stored in 1Password
opssh() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "opssh" "list SSH keys stored in 1Password"; return 0; }
  op item list --categories "SSH Key" --format table
}
