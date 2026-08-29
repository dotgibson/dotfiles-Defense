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
# Default to the RELEASED major alias, never `main`: the fan-out pins every repo to the
# exact commit a release tag points at, so a tree vendored from whatever `main` happened
# to be is not a commit any core.lock would record — and core-integrity reports the fresh
# subtree as TAMPERED before the repo has done anything wrong (#588).
CORE_BRANCH="${CORE_BRANCH:-refs/tags/v5}"

usage() {
  cat <<'EOF'
usage: new-os-repo.sh <OSName> [target-dir] [--dry-run] [--no-vendor]

Scaffold a new OS repo that vendors Core: subtree-add core/, then write a correct
.zshrc loader (canonical order), os/<os>.zsh, a starter bootstrap, and .gitignore.

  <OSName>       e.g. Fedora, Arch, Gentoo  (repo defaults to ../dotfiles-<OSName>)
  target-dir     override the destination directory
  --dry-run, -n  print every planned action; create nothing
  --no-vendor    scaffold the files but skip the `git subtree add` (do it yourself later)

Env: CORE_REMOTE (default: this repo's origin)
     CORE_BRANCH (default: refs/tags/v5 — a RELEASED tag, never main; pin a specific
                  vX.Y.Z to freeze the tree at a known version)
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
#
# THE .zsh EXTENSION IS LOAD-BEARING (#451). Core's reusable lint gate syntax-checks
# repo-owned zsh with `git ls-files '*.zsh'` (.github/workflows/lint-call.yml). Emitted
# as plain `zshenv`/`zprofile`/`zshrc`, these three matched nothing and were the only
# files in a generated repo that CI never checked — while ~/.zshenv in particular is
# sourced on EVERY zsh invocation, including non-interactive ones, and carries the
# ZDOTDIR indirection. A syntax error there does not degrade the shell, it breaks login
# shells outright on every box running that layer. Highest blast radius in the repo, and
# the one file the gate could not see. The symlink DESTINATION is ~/.zshenv regardless of
# the source filename, so the extension costs nothing.
w "$TARGET/zsh/zshenv.zsh" <<'EOF'
# zsh/zshenv.zsh → ~/.zshenv. Point ZDOTDIR at ~/.config/zsh so the rest of the shell
# config lives under XDG. Keep this file tiny — it runs for EVERY zsh (incl. scripts).
#
# Do NOT rename this to plain `zshenv` to match the symlink: the .zsh suffix is what
# puts it in front of the lint gate's `git ls-files '*.zsh'` (#451).
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
EOF

w "$TARGET/zsh/zprofile.zsh" <<'EOF'
# zsh/zprofile.zsh → $ZDOTDIR/.zprofile. Login-shell setup (PATH, env). Interactive
# config lives in .zshrc. Add OS login-time bits here.
#
# The .zsh suffix is load-bearing for the lint gate — see zshenv.zsh (#451).
EOF

w "$TARGET/zsh/zshrc.zsh" <<'EOF'
# zsh/zshrc.zsh → $ZDOTDIR/.zshrc — interactive shell.
# The .zsh suffix is load-bearing for the lint gate — see zshenv.zsh (#451).
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
# It may use any Core helper (00-tools.zsh's _cache_eval and _core_is_wsl, 05-ui.zsh's
# _core_* primitives).
#
# Core ALREADY hooks direnv/gh/uv/ty and already answers "is this WSL?" (_core_is_wsl) —
# do not re-add either here. Seven os layers each carried a copy until dotfiles-core#449,
# and the reusable lint workflow now flags a duplicate. See VENDORING.md.
EOF

# ── OS capability declaration stub (#663/#667) ────────────────────────────────
# THE SAME ARGUMENT AS THE LOAD ORDER ABOVE. This script centralises the canonical
# module order in ONE place so a scaffolded repo can never start out of order; the
# capability table is the other thing a repo cannot be correct without and cannot
# discover for itself. A repo scaffolded without one boots into Core's built-in
# fallback rows and looks fine — which is exactly how the fleet ended up with nine
# repos and zero declarations for two releases after the schema landed.
#
# SCHEMA-VALID FROM BIRTH, so `make capabilities` and Core's audit §9c are green on
# day one and the author edits values rather than fighting a red gate. Every REQUIRED
# key is present; the values are dnf's and are WRONG for any other archive, which the
# banner says in the one place someone will actually read it.
#
# The optional keys are deliberately NOT stubbed out as commented placeholders. In this
# schema an OMISSION IS A STATEMENT — no PKG_ASSUME_YES means "never auto-confirm", no
# PKG_UPGRADE_PARTIAL means "`up -i` refuses", no MAINT_UNATTENDED_UPGRADE means
# "refuse" — so a stub that pre-declares them would hand every new repo the permissive
# answer by default. Point at the example instead; it documents all of them.
w "$TARGET/os/$os_lc.capabilities" <<EOF
# os/$os_lc.capabilities — the $OS capability declaration (Core v5, #663).
#
# ┌──────────────────────────────────────────────────────────────────────────┐
# │ REPLACE EVERY VALUE BELOW. They are FEDORA's (dnf), copied so this file   │
# │ satisfies the schema from birth — they are NOT defaults and nothing in    │
# │ Core falls back to them. On any other archive they are simply wrong.      │
# └──────────────────────────────────────────────────────────────────────────┘
#
# Read (never sourced) by Core's zsh/02-capabilities.zsh into \$_CORE_CAP, and by
# core/maint/dotfiles-maint.sh, which is bash. bootstrap.sh links it to
# \$ZDOTDIR/os.capabilities.
#
# core/PORTING-MATRIX.md §"Package-manager commands" tabulates all seven archives and
# is the transcription source. core/examples/os.capabilities.example documents every
# key, including the OPTIONAL ones this stub deliberately omits — in this schema an
# omission is a STATEMENT (no PKG_ASSUME_YES = never auto-confirm; no
# PKG_UPGRADE_PARTIAL = \`up -i\` refuses; no MAINT_UNATTENDED_UPGRADE = refuse), so
# read that file before adding one.
#
# Validate with:  core/scripts/check-capabilities.sh os/$os_lc.capabilities
#
# A \`#\` INSIDE A VALUE IS NOT A COMMENT — the reader keeps it. Notes go above.

# ── package-manager verbs (all required) ──────────────────────────────────────
PKG_REFRESH=sudo dnf check-update
# The INTERACTIVE upgrade verb — no auto-confirm flag here; that is PKG_ASSUME_YES.
PKG_UPGRADE=sudo dnf upgrade --refresh
PKG_INSTALL=sudo dnf install -y
PKG_REMOVE=sudo dnf remove -y
PKG_SEARCH=dnf search
PKG_OWNS=dnf provides
# What \`up\`'s once-a-day "N updates available" nudge counts, and the verb that
# diverges most across archives. Non-root and non-mutating, always.
PKG_COUNT_PENDING=dnf -q --refresh check-update

# ── scheduler (required) ──────────────────────────────────────────────────────
# systemd | launchd | cron | none. \`cron\` is what an OpenRC box gets; \`none\` is a
# real answer (a container) and tells the maint layer to offer the manual verb
# rather than claim a timer it cannot install.
SCHEDULER=systemd
# REQUIRED for systemd and launchd; cron and none take NONE. A DIRECTORY, not a full
# path — Core appends its own unit name. An OS-absolute path is CORRECT here and
# wrong in Core, which is this key's whole point.
SCHEDULER_UNIT_DIR=~/.config/systemd/user
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
  local src="\$1" dest="\$2" bak=""
  [[ -e "\$src" ]] || return 0
  if [[ -L "\$dest" && "\$(readlink "\$dest")" == "\$src" ]]; then return 0; fi
  mkdir -p "\$(dirname "\$dest")"
  [[ -L "\$dest" ]] && rm -f "\$dest"
  # ONE fleet-wide backup format: a zero-padded YYYYMMDD-HHMMSS stamp (so a lexical sort
  # is chronological, which is what --uninstall relies on to pick the newest) plus \$\$
  # (so two backups of the same dest inside one second cannot overwrite each other).
  # Matches core/lib/bootstrap-lib.sh's _blib_backup_suffix — keep the two in step (#464).
  # Announced, not silent: a displaced real file is the one wiring outcome that touched
  # something the user owned (#463).
  if [[ -e "\$dest" ]]; then
    bak="\$dest.pre-dotfiles.\$(date +%Y%m%d-%H%M%S).\$\$"
    mv "\$dest" "\$bak"
    echo "backed up existing \${dest/#\$HOME/~} -> \${bak/#\$HOME/~}" >&2
  fi
  ln -s "\$src" "\$dest"
  echo "linked \${dest/#\$HOME/~}"
}

# Core zsh modules + entry layer
for f in "\$REPO"/core/zsh/*.zsh; do link "\$f" "\$CFG/zsh/\$(basename "\$f")"; done
link "\$REPO/os/$os_lc.zsh" "\$CFG/zsh/80-os.zsh"
# The capability DECLARATION. Un-numbered and not a .zsh on purpose: the loader globs
# [0-9][0-9]-*.zsh, so this is never sourced into your shell — it is DATA that Core
# READS, which is what keeps a per-repo file off the code-execution path.
link "\$REPO/os/$os_lc.capabilities" "\$CFG/zsh/os.capabilities"
link "\$REPO/zsh/zshenv.zsh"   "\$HOME/.zshenv"
link "\$REPO/zsh/zprofile.zsh" "\$CFG/zsh/.zprofile"
link "\$REPO/zsh/zshrc.zsh"    "\$CFG/zsh/.zshrc"
# Core configs
link "\$REPO/core/starship/starship.toml" "\$CFG/starship.toml"
link "\$REPO/core/tmux/tmux.conf"         "\$CFG/tmux/tmux.conf"
link "\$REPO/core/tmux/tmux.reset.conf"   "\$CFG/tmux/tmux.reset.conf"
link "\$REPO/core/nvim"                   "\$CFG/nvim"
link "\$REPO/core/git/gitconfig"          "\$HOME/.gitconfig"
# mise is COPIED, not linked: \`mise use -g\` rewrites this file, and through a symlink
# that write lands in the vendored core/ tree (tampered tree + skipped fleet sync). The
# full bootstrap (core/lib/bootstrap-lib.sh) uses blib_adopt here, which also migrates an
# existing symlink and reports drift; this starter template just avoids creating one.
if [[ ! -e "\$CFG/mise/config.toml" ]]; then
  mkdir -p "\$CFG/mise"
  cp "\$REPO/core/mise/config.toml" "\$CFG/mise/config.toml"
  echo "seeded \${CFG/#\$HOME/~}/mise/config.toml (yours to edit)"
fi
echo "done — open a new shell or: exec zsh"
EOF
((DRY)) || chmod +x "$TARGET/bootstrap.sh" 2>/dev/null

w "$TARGET/.gitignore" <<'EOF'
# machine-local / never tracked
zsh/99-local.zsh
.config/git/local.gitconfig
*.zwc
# Crash dumps. `core.[0-9]*`, NOT `core.*`: this repo tracks core.lock, and bare `core` is
# the vendored Core DIRECTORY — a blanket rule would hide either one silently.
core.[0-9]*
EOF

w "$TARGET/README.md" <<EOF
# dotfiles-$OS

The $OS machine repo. Vendors [Core](../dotfiles-core) under \`core/\`
and adds the $OS-native layer (\`os/$os_lc.zsh\`, package manager, paths).

## The capability declaration

\`os/$os_lc.capabilities\` tells Core how THIS archive updates: the package-manager
verbs, the scheduler, and which tools are opt-in here. Core's \`up\`, its maintenance
runner and \`core-doctor\` all dispatch through it, so it is the file that stops Core
from carrying $OS knowledge it has no business having.

**The scaffold shipped Fedora's values.** Replace them —
\`core/PORTING-MATRIX.md\` §"Package-manager commands" tabulates every archive, and
\`core/examples/os.capabilities.example\` documents every key. Then:

\`\`\`bash
core/scripts/check-capabilities.sh os/$os_lc.capabilities
\`\`\`

In this schema an **omission is a statement**: no \`PKG_ASSUME_YES\` means never
auto-confirm, no \`PKG_UPGRADE_PARTIAL\` means \`up -i\` refuses, and no
\`MAINT_UNATTENDED_UPGRADE\` means the scheduled runner will not apply system upgrades
here. Leave a key out to mean those things; do not add one to be helpful.

## Install

\`\`\`bash
./bootstrap.sh
\`\`\`

## Update Core

Core is fanned out **from Core**, not pulled from here. A raw \`git subtree pull\` moves
\`core/\` but not \`core.lock\`, and \`core-integrity\` then reports this tree as TAMPERED.

Normally a sync arrives as a PR from Core's fan-out and you just merge it. To run one
by hand, from a \`dotfiles-core\` checkout:

\`\`\`bash
./scripts/sync-core.sh dotfiles-$OS   # materializes core/ AND stamps core.lock
\`\`\`

Then, in this repo:

\`\`\`bash
./bootstrap.sh          # re-link any new/changed Core files
\`\`\`
EOF

printf '\n%s──────── dotfiles-%s scaffolded ────────%s\n' "$c_blu" "$OS" "$c_rst"
if ((DRY)); then
  echo "dry-run — nothing was written."
else
  # The registration step is named HERE because it is the one thing the scaffold cannot do
  # for you and the one thing nothing downstream will remind you about: a repo that exists
  # but is not in scripts/os-repos.txt is invisible to the fan-out, to fleet-drift and to
  # core-integrity, and every one of them stays green while ignoring it. Since #669 that
  # registration is a single line rather than four coordinated edits — see VENDORING.md.
  cat <<EOF
  next:
    cd "$TARGET"
    git add -A && git commit -m "scaffold dotfiles-$OS"
    ./bootstrap.sh            # wire the symlinks
    \$EDITOR os/$os_lc.zsh     # add your $OS-native bits

  THEN FIX THE CAPABILITY DECLARATION — it was scaffolded with FEDORA's verbs so the
  schema is satisfied from birth, and they are wrong for any other archive:
    \$EDITOR os/$os_lc.capabilities
    core/scripts/check-capabilities.sh os/$os_lc.capabilities

  then, back in dotfiles-core — REGISTER IT, or the fleet never sees this repo:
    echo dotfiles-$OS >> scripts/os-repos.txt   # one line; keep the list sorted
    ./scripts/sync-core.sh dotfiles-$OS         # materializes core/ and stamps core.lock
EOF
fi
