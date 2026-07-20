# core/zsh/op.zsh
# 1Password CLI helpers — portable across machines. The macOS SSH-agent socket
# path is OS-specific and lives in os/macos.zsh, NOT here. If `op` isn't
# installed, this file does nothing.
# Docs: https://developer.1password.com/docs/cli

command -v op >/dev/null 2>&1 || return 0

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
  printf '%s' "$otp" | clip && _core_ok "TOTP copied to clipboard"
}

# opssh — list SSH keys stored in 1Password
opssh() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "opssh" "list SSH keys stored in 1Password"; return 0; }
  op item list --categories "SSH Key" --format table
}
