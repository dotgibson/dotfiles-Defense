#!/usr/bin/env bash
# dotfiles-Defense/bootstrap.sh
# Wire the defensive (blue) role layer onto an already-provisioned box.
# Distro-agnostic: does NOT install OS packages (your OS-native layer does that).
# Idempotent. Stacks: vendored Core + your OS-native layer + DEFENSE role.
#
#   ./bootstrap.sh                 # symlinks + loader + tool/docker checks
#   ./bootstrap.sh --links-only    # just (re)create symlinks
#   ./bootstrap.sh --no-check      # skip the host-tool / docker probe
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
LINKS_ONLY=0
DO_CHECK=1

for a in "$@"; do case "$a" in
  --links-only) LINKS_ONLY=1 ;;
  --no-check) DO_CHECK=0 ;;
  -h | --help)
    sed -n '2,12p' "$0"
    exit 0
    ;;
  *)
    echo "unknown arg: $a" >&2
    exit 1
    ;;
  esac done

say() { printf '\e[36m::\e[0m %s\n' "$*"; }
ok() { printf '\e[32m+\e[0m %s\n' "$*"; }
warn() { printf '\e[33m!\e[0m %s\n' "$*"; }

# ── core/ subtree present? ────────────────────────────────────────────────────
if [[ ! -d "$DOTFILES/core/zsh" ]]; then
  echo "core/ subtree missing. One time, from the repo root run:" >&2
  echo "  git subtree add --prefix=core <dotfiles-core remote> main --squash" >&2
  exit 1
fi

link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" ]]; then
    rm -f "$dst"
  elif [[ -e "$dst" ]]; then mv "$dst" "$dst.pre-dotfiles.$(date +%s)"; fi
  ln -s "$src" "$dst" || { echo "link failed: $dst" >&2; return 1; }
}

# ── Host-tool / docker probe (report only — never installs) ──────────────────
check_tools() {
  say "checking host tools (install missing ones via your OS layer — see install/README.md)"
  local t missing=0
  for t in docker jq tshark zeek suricata chainsaw hayabusa sigma yara velociraptor vol log2timeline.py; do
    if command -v "$t" >/dev/null 2>&1; then
      ok "found: $t"
    else
      warn "missing: $t"
      missing=$((missing + 1))
    fi
  done
  if command -v docker >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
      ok "docker compose available — \`siemup\` will work"
    else warn "docker present but compose plugin missing — siemup needs it"; fi
  fi
  if ((missing == 0)); then
    ok "all probed tools present"
  else warn "$missing tool(s) missing (optional — install what you need)"; fi
}

wire_links() {
  local f
  say "symlinking Core"
  for f in "$DOTFILES"/core/zsh/*.zsh; do link "$f" "$CONFIG/zsh/$(basename "$f")"; done
  [[ -f "$DOTFILES/core/tmux/tmux.conf" ]] && link "$DOTFILES/core/tmux/tmux.conf" "$CONFIG/tmux/tmux.conf"
  [[ -f "$DOTFILES/core/tmux/tmux.reset.conf" ]] && link "$DOTFILES/core/tmux/tmux.reset.conf" "$CONFIG/tmux/tmux.reset.conf"
  if [[ -d "$DOTFILES/core/tmux/scripts" ]]; then
    link "$DOTFILES/core/tmux/scripts" "$CONFIG/tmux/scripts"
    chmod +x "$DOTFILES"/core/tmux/scripts/*.sh 2>/dev/null || true
  fi
  [[ -f "$DOTFILES/core/starship/starship.toml" ]] && link "$DOTFILES/core/starship/starship.toml" "$CONFIG/starship.toml"
  [[ -d "$DOTFILES/core/nvim" ]] && link "$DOTFILES/core/nvim" "$CONFIG/nvim"
  [[ -f "$DOTFILES/core/git/gitconfig" ]] && link "$DOTFILES/core/git/gitconfig" "$HOME/.gitconfig"

  say "symlinking DEFENSE role layer"
  link "$DOTFILES/defense/defense.zsh" "$CONFIG/zsh/defense.zsh"
  [[ -d "$DOTFILES/defense/templates" ]] && link "$DOTFILES/defense/templates" "$CONFIG/defense/templates"

  if [[ ! -f "$HOME/.zshrc" ]] || ! grep -q "dotfiles-managed v2" "$HOME/.zshrc" 2>/dev/null; then
    say "writing .zshrc loader (adds the 'defense' stage)"
    [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$HOME/.zshrc.pre-dotfiles.$(date +%s)"
    cat >"$HOME/.zshrc" <<'ZRC'
# dotfiles-managed v2 — do not hand-edit; local tweaks go in ~/.config/zsh/local.zsh
: "${XDG_CONFIG_HOME:=$HOME/.config}"
export EDITOR=nvim VISUAL=nvim
: "${ZDOTDIR:=$XDG_CONFIG_HOME/zsh}"
export ZDOTDIR
ZSH_CFG="$ZDOTDIR"
# Core order + the 'defense' stage (unique to this repo), just before local.
_CORE_MODULES=(tools ui options history aliases git functions fzf bindings plugins op maint update os defense local)
if [[ -r "$ZSH_CFG/loader.zsh" ]]; then
  source "$ZSH_CFG/loader.zsh"
else
  print -u2 -- "zshrc: Core loader not found at $ZSH_CFG/loader.zsh — re-run the dotfiles bootstrap."
fi
unset _CORE_MODULES
ZRC
  fi
  ok "symlinks wired"
}

# --links-only skips the host-tool/docker probe too (it's the "just wire symlinks" path);
# without consulting LINKS_ONLY here, --links-only would still run the probe and the flag
# would be dead. --no-check skips it independently.
((DO_CHECK && !LINKS_ONLY)) && check_tools
wire_links
say "case data lives in ~/cases (outside this repo) — run \`mkcase <name>\` to start one"
ok "Defense bootstrap complete — open a new shell, or: exec zsh"
