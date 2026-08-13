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
  # zsh leads the list deliberately: it is the shell this entire layer runs in, so its
  # absence is categorically worse than a missing forensics tool. The end-of-run guard
  # says so loudly — this line just makes it visible in the probe alongside the rest.
  for t in zsh docker jq tshark zeek suricata chainsaw hayabusa sigma yara velociraptor vol log2timeline.py; do
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
  else warn "$missing tool(s) missing — the forensics tools are optional; zsh is not"; fi
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
  # v4: the loader globs NUMBERED fragments ($ZSH_CFG/NN-*.zsh). The defense role stage is
  # band 85 — it sorts AFTER the OS layer (80-os.zsh, from the OS-native repo) and BEFORE
  # host-local (99-local.zsh), preserving the old `… os defense local` order. Drop any stale
  # pre-v4 unnumbered link so the loader doesn't see a dead entry.
  [[ -L "$CONFIG/zsh/defense.zsh" ]] && rm -f "$CONFIG/zsh/defense.zsh"
  link "$DOTFILES/defense/defense.zsh" "$CONFIG/zsh/85-defense.zsh"
  [[ -d "$DOTFILES/defense/templates" ]] && link "$DOTFILES/defense/templates" "$CONFIG/defense/templates"

  if [[ ! -f "$HOME/.zshrc" ]] || ! grep -q "dotfiles-managed v4" "$HOME/.zshrc" 2>/dev/null; then
    say "writing .zshrc loader (v4 numbered fragments; the defense stage rides band 85)"
    [[ -f "$HOME/.zshrc" ]] && cp "$HOME/.zshrc" "$HOME/.zshrc.pre-dotfiles.$(date +%s)"
    cat >"$HOME/.zshrc" <<'ZRC'
# dotfiles-managed v4 — do not hand-edit; local tweaks go in ~/.config/zsh/99-local.zsh
: "${XDG_CONFIG_HOME:=$HOME/.config}"
export EDITOR=nvim VISUAL=nvim
: "${ZDOTDIR:=$XDG_CONFIG_HOME/zsh}"
export ZDOTDIR
ZSH_CFG="$ZDOTDIR"
# v4: the loader globs $ZSH_CFG/NN-*.zsh and sources by numeric prefix. It no longer
# takes a module-name list — the load order is the numbering itself: Core 00-69, the
# OS layer at 80-os.zsh, this repo's defense stage at 85-defense.zsh, host-local at
# 99-local.zsh. (So `… os defense local` is preserved without an explicit array.)
if [[ -r "$ZSH_CFG/loader.zsh" ]]; then
  source "$ZSH_CFG/loader.zsh"
else
  print -u2 -- "zshrc: Core loader not found at $ZSH_CFG/loader.zsh — re-run the dotfiles bootstrap."
fi
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

# Everything above wires a zsh config. On a box with no zsh — or with zsh installed but not
# the login shell — every step still "succeeds" and nothing ever loads. So this is checked
# OUTSIDE check_tools: --no-check and --links-only skip a tool probe, but must not silence a
# correctness guard. Non-fatal, matching how missing host tools are handled — the script is
# idempotent by design and has to stay re-runnable on a box mid-provisioning.
# Best-effort, and it MUST NOT abort: this file runs under `set -euo pipefail`, where
# pipefail makes `getent … | cut` return getent's status rather than cut's. getent exits 2
# when the user is not in the passwd DB, and is 127 when absent altogether (it is not
# universal outside glibc) — either would take the whole bootstrap down on its last line,
# turning the non-fatal guard below into the loudest possible failure. So every lookup is
# guarded, in descending order of trust: getent, then /etc/passwd, then $SHELL. All three
# may come up empty; the guard reports that as "unknown" rather than caring.
detect_login_shell() {
  local user shell_field=""
  user="$(id -un 2>/dev/null || true)"
  if [[ -n "$user" ]]; then
    if command -v getent >/dev/null 2>&1; then
      shell_field="$(getent passwd "$user" 2>/dev/null | cut -d: -f7 || true)"
    fi
    if [[ -z "$shell_field" && -r /etc/passwd ]]; then
      shell_field="$(awk -F: -v u="$user" '$1 == u { print $7; exit }' /etc/passwd 2>/dev/null || true)"
    fi
  fi
  printf '%s' "${shell_field:-${SHELL:-}}"
}

login_shell="$(detect_login_shell)"
if ! command -v zsh >/dev/null 2>&1; then
  warn "zsh is NOT installed — the config above is wired but inert; nothing reads ~/.zshrc"
  warn "  your OS-native layer owns package installation (see install/README.md)"
elif [[ "$login_shell" != *zsh ]]; then
  warn "zsh is installed, but your login shell is ${login_shell:-unknown}"
  warn "  fix: chsh -s $(command -v zsh)  — takes effect at next login"
  ok "Defense bootstrap complete — for this session: exec zsh"
else
  ok "Defense bootstrap complete — open a new shell, or: exec zsh"
fi
