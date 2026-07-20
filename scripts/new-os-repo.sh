#!/usr/bin/env bash
# scripts/new-os-repo.sh — scaffold a new OS repo that vendors Core (B3).
# ──────────────────────────────────────────────────────────────────────────────
# Onboarding a new OS repo was a tribal, multi-step ritual (README "Adding a new file"
# + "How an OS repo consumes Core"): git init, `git subtree add`, hand-write a .zshrc
# loader in the EXACT canonical order, stub an os/<os>.zsh, write a bootstrap. Get the
# load order wrong and the shell breaks in ways the per-file linters never catch. This
# turns all of it into one command, generating a skeleton that already loads Core
# correctly and is ready for `bootstrap.sh`.
#
# Usage:
#   ./scripts/new-os-repo.sh <OSName> [target-dir]      # e.g. Fedora  (→ ../dotfiles-Fedora)
#   ./scripts/new-os-repo.sh Fedora --dry-run           # print the plan, write nothing
#   ./scripts/new-os-repo.sh Fedora --no-vendor         # skeleton only, skip the subtree add
#
# It vendors Core via `git subtree add --prefix=core` from this repo's origin (override
# with CORE_REMOTE), then writes the entry .zshrc/.zshenv/.zprofile, an os/<os>.zsh stub,
# a starter bootstrap, and a .gitignore. The canonical module order lives in ONE place
# here, so a scaffolded repo can never start out of order.
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

# v4: the load order is the numbered fragments' NN prefix, globbed by the vendored
# loader — a scaffolded .zshrc no longer lists module names, it just sources the loader.
CORE_REMOTE="${CORE_REMOTE:-$(git -C "$HERE" remote get-url origin 2>/dev/null || echo '')}"
CORE_BRANCH="${CORE_BRANCH:-main}"

usage() {
  cat <<'EOF'
usage: new-os-repo.sh <OSName> [target-dir] [--dry-run] [--no-vendor]

Scaffold a new OS repo that vendors Core: subtree-add core/, then write a correct
.zshrc loader (canonical order), os/<os>.zsh, a starter bootstrap, and .gitignore.

  <OSName>       e.g. Fedora, Arch, Gentoo  (repo defaults to ../dotfiles-<OSName>)
  target-dir     override the destination directory
  --dry-run, -n  print every planned action; create nothing
  --no-vendor    scaffold the files but skip the `git subtree add` (do it yourself later)

Env: CORE_REMOTE (default: this repo's origin), CORE_BRANCH (default: main)
EOF
}

OS="" TARGET="" DRY=0 NO_VENDOR=0
for a in "$@"; do
  case "$a" in
  -h | --help)
    usage
    exit 0
    ;;
  --dry-run | -n) DRY=1 ;;
  --no-vendor) NO_VENDOR=1 ;;
  -*)
    fail "unknown flag: $a"
    usage >&2
    exit 2
    ;;
  *)
    if [[ -z "$OS" ]]; then OS="$a"
    elif [[ -z "$TARGET" ]]; then TARGET="$a"
    else
      fail "unexpected extra argument: $a"
      exit 2
    fi
    ;;
  esac
done
[[ -n "$OS" ]] || {
  fail "an OS name is required (e.g. Fedora)"
  usage >&2
  exit 2
}
TARGET="${TARGET:-$(dirname "$HERE")/dotfiles-$OS}"
os_lc="$(printf '%s' "$OS" | tr '[:upper:]' '[:lower:]')"

hdr "scaffold dotfiles-$OS"
echo ":: target   = $TARGET"
echo ":: core     = $CORE_REMOTE ($CORE_BRANCH)"
((DRY)) && echo ":: DRY RUN — nothing will be written"

if [[ -e "$TARGET" && ! -d "$TARGET" ]]; then
  fail "$TARGET exists and is not a directory"
  exit 1
fi
if [[ -d "$TARGET/.git" ]]; then
  fail "$TARGET is already a git repo — refusing to overwrite (scaffold a fresh dir)"
  exit 1
fi

# w <path> <<heredoc — write a file (honouring --dry-run + announcing), making parents.
w() {
  local path="$1"
  if ((DRY)); then
    skip "would write ${path#"$TARGET"/}"
    cat >/dev/null
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  cat >"$path"
  pass "wrote ${path#"$TARGET"/}"
}

((DRY)) || mkdir -p "$TARGET"
((DRY)) || git -C "$TARGET" init -q

# ── vendor Core ───────────────────────────────────────────────────────────────
if ((NO_VENDOR)); then
  skip "skipping subtree add (--no-vendor) — run later: git -C '$TARGET' subtree add --prefix=core '$CORE_REMOTE' '$CORE_BRANCH' --squash"
elif ((DRY)); then
  skip "would: git -C '$TARGET' subtree add --prefix=core '$CORE_REMOTE' '$CORE_BRANCH' --squash"
elif [[ -z "$CORE_REMOTE" ]]; then
  fail "CORE_REMOTE empty (set origin on dotfiles-core, or export CORE_REMOTE) — scaffolding files, skipping vendor"
else
  # subtree add needs at least one commit on the new repo first.
  git -C "$TARGET" commit -q --allow-empty -m "init dotfiles-$OS" 2>/dev/null
  if git -C "$TARGET" subtree add --prefix=core "$CORE_REMOTE" "$CORE_BRANCH" --squash >/dev/null 2>&1; then
    pass "vendored Core into core/ (subtree)"
  else
    fail "subtree add failed (offline/unreachable?) — files scaffolded; vendor later with the command in --no-vendor"
  fi
fi

# ── entry layer (ZDOTDIR model): ~/.zshenv → ZDOTDIR; .zprofile/.zshrc in $ZDOTDIR ──
w "$TARGET/zsh/zshenv" <<'EOF'
# zsh/zshenv → ~/.zshenv. Point ZDOTDIR at ~/.config/zsh so the rest of the shell
# config lives under XDG. Keep this file tiny — it runs for EVERY zsh (incl. scripts).
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
EOF

w "$TARGET/zsh/zprofile" <<'EOF'
# zsh/zprofile → $ZDOTDIR/.zprofile. Login-shell setup (PATH, env). Interactive
# config lives in .zshrc. Add OS login-time bits here.
EOF

w "$TARGET/zsh/zshrc" <<'EOF'
# zsh/zshrc → $ZDOTDIR/.zshrc — interactive shell.
# Sources the vendored v4 Core loader, which globs the numbered fragments (Core NN-*.zsh
# + this repo's 80-os.zsh + any 99-local.zsh) and sources them in NN order. v4 keeps
# mutable state out of the config tree: history→$XDG_STATE_HOME, compdump→$XDG_CACHE_HOME,
# plugins→$XDG_DATA_HOME.
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
ZSH_CFG="${ZDOTDIR:-$HOME/.config/zsh}"
# CORE_PROFILE (minimal | standard | full) gates Core fragments (bands 00-69). The loader
# resolves it: environment wins, else a one-liner in "$ZSH_CFG/profile", else full. Do not
# pre-set it here, or that file could never take effect.
if [[ -r "$ZSH_CFG/loader.zsh" ]]; then
  source "$ZSH_CFG/loader.zsh"
else
  print -u2 -- "zshrc: Core loader not found — re-run bootstrap.sh to (re)link Core."
fi
EOF

# ── OS layer stub ─────────────────────────────────────────────────────────────
w "$TARGET/os/$os_lc.zsh" <<EOF
# os/$os_lc.zsh — the $OS interactive layer (symlinked to \$ZDOTDIR/80-os.zsh by bootstrap;
# band 80 = OS-native, so the loader always sources it regardless of CORE_PROFILE).
# Put OS-specific aliases, PATH, and package-manager bits HERE — never in Core.
# It may use any Core helper (00-tools.zsh's _cache_eval, 05-ui.zsh's _core_* primitives).
EOF

# ── starter bootstrap ─────────────────────────────────────────────────────────
w "$TARGET/bootstrap.sh" <<EOF
#!/usr/bin/env bash
# bootstrap.sh — symlink the vendored Core + the $OS os/ layer into place. Idempotent.
# Generated by dotfiles-core/scripts/new-os-repo.sh — extend with $OS provisioning.
set -euo pipefail
REPO="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
CFG="\$HOME/.config"
[[ -d "\$REPO/core" ]] || { echo "core/ subtree missing — run the subtree add first" >&2; exit 1; }

link() { # link <src> <dest> — back up a real file once, then symlink
  local src="\$1" dest="\$2"
  [[ -e "\$src" ]] || return 0
  if [[ -L "\$dest" && "\$(readlink "\$dest")" == "\$src" ]]; then return 0; fi
  mkdir -p "\$(dirname "\$dest")"
  [[ -L "\$dest" ]] && rm -f "\$dest"
  [[ -e "\$dest" ]] && mv "\$dest" "\$dest.pre-dotfiles.\$(date +%Y%m%d-%H%M%S)"
  ln -s "\$src" "\$dest"
  echo "linked \${dest/#\$HOME/~}"
}

# Core zsh modules + entry layer
for f in "\$REPO"/core/zsh/*.zsh; do link "\$f" "\$CFG/zsh/\$(basename "\$f")"; done
link "\$REPO/os/$os_lc.zsh" "\$CFG/zsh/80-os.zsh"
link "\$REPO/zsh/zshenv"   "\$HOME/.zshenv"
link "\$REPO/zsh/zprofile" "\$CFG/zsh/.zprofile"
link "\$REPO/zsh/zshrc"    "\$CFG/zsh/.zshrc"
# Core configs
link "\$REPO/core/starship/starship.toml" "\$CFG/starship.toml"
link "\$REPO/core/tmux/tmux.conf"         "\$CFG/tmux/tmux.conf"
link "\$REPO/core/tmux/tmux.reset.conf"   "\$CFG/tmux/tmux.reset.conf"
link "\$REPO/core/nvim"                   "\$CFG/nvim"
link "\$REPO/core/git/gitconfig"          "\$HOME/.gitconfig"
link "\$REPO/core/mise/config.toml"       "\$CFG/mise/config.toml"
echo "done — open a new shell or: exec zsh"
EOF
((DRY)) || chmod +x "$TARGET/bootstrap.sh" 2>/dev/null

w "$TARGET/.gitignore" <<'EOF'
# machine-local / never tracked
zsh/99-local.zsh
.config/git/local.gitconfig
*.zwc
EOF

w "$TARGET/README.md" <<EOF
# dotfiles-$OS

The $OS machine repo. Vendors [Core](../dotfiles-core) under \`core/\` (git subtree)
and adds the $OS-native layer (\`os/$os_lc.zsh\`, package manager, paths).

## Install

\`\`\`bash
./bootstrap.sh
\`\`\`

## Update Core

\`\`\`bash
git subtree pull --prefix=core $CORE_REMOTE $CORE_BRANCH --squash
./bootstrap.sh          # re-link any new/changed Core files
\`\`\`
EOF

printf '\n%s──────── dotfiles-%s scaffolded ────────%s\n' "$c_blu" "$OS" "$c_rst"
if ((DRY)); then
  echo "dry-run — nothing was written."
else
  cat <<EOF
  next:
    cd "$TARGET"
    git add -A && git commit -m "scaffold dotfiles-$OS"
    ./bootstrap.sh            # wire the symlinks
    \$EDITOR os/$os_lc.zsh     # add your $OS-native bits
EOF
fi
