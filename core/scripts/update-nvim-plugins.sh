#!/usr/bin/env bash
# scripts/update-nvim-plugins.sh
# ──────────────────────────────────────────────────────────────────────────────
# Deliberately roll the pinned Neovim plugin revisions in nvim/lazy-lock.json
# forward. This is the lazy.nvim counterpart of scripts/update-plugins.sh (which
# bumps the zsh-plugin SHAs): pins exist so nothing floats silently into the 9 OS
# repos, and THIS is the one place the nvim ones move — under review, not on their own.
#
# Why a committed lockfile at all: lazy.nvim clones plugins from their default
# branches (config/lazy.lua), so without nvim/lazy-lock.json every box — and every
# vendored OS repo — resolves a DIFFERENT commit, i.e. a non-reproducible editor.
# The tracked lockfile pins all of them; `:Lazy restore` installs exactly those.
#
# How it works: run the REPO's real nvim config headlessly in a throwaway HOME whose
# config dir is symlinked to nvim/, so lazy writes the lockfile straight back into
# nvim/lazy-lock.json. `:Lazy! sync` installs/updates/cleans and rewrites the lock.
# The throwaway data dir means this never touches the maintainer's own nvim install;
# the trade-off is it re-clones the plugins each run — fine for an occasional,
# reviewed bump (the same "deliberate, not automatic" philosophy as update-plugins.sh).
#
# Usage:
#   ./scripts/update-nvim-plugins.sh            # bump pins to latest, rewrite the lock
#   ./scripts/update-nvim-plugins.sh --dry-run  # show what WOULD change, restore the lock
#   ./scripts/update-nvim-plugins.sh --check    # like --dry-run but EXIT 2 if the lock
#                                                 is stale — the lazy-lock half of the
#                                                 weekly freshness gate (see
#                                                 .github/workflows/freshness.yml).
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1
LOCK="nvim/lazy-lock.json"

# --check is a non-mutating drift report (implies dry-run) that exits 2 when stale.
DRY=0
CHECK=0
case "${1:-}" in
--dry-run | -n) DRY=1 ;;
--check) DRY=1 CHECK=1 ;;
"") ;;
-h | --help)
  cat <<'EOF'
update-nvim-plugins.sh — roll the pinned Neovim plugin revisions in nvim/lazy-lock.json.

  ./scripts/update-nvim-plugins.sh            bump pins to latest, rewrite the lock
  ./scripts/update-nvim-plugins.sh --dry-run  show what WOULD change, restore the lock
  ./scripts/update-nvim-plugins.sh --check    like --dry-run but exit 2 if the lock is stale
                                              (the lazy-lock half of the weekly freshness gate)
EOF
  exit 0
  ;;
*)
  printf 'update-nvim-plugins.sh: unexpected argument: %s (try --help)\n' "$1" >&2
  exit 2
  ;;
esac
# Reject a stray extra operand too (e.g. `--dry-run extra`), matching the arg discipline
# in scripts/bench-core.sh / audit-core.sh — a silent ignore makes typos easy to miss.
if (($# > 1)); then
  printf 'update-nvim-plugins.sh: unexpected argument: %s (try --help)\n' "$2" >&2
  exit 2
fi

# Shared palette + have() (one definition for every gate script).
# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

have nvim || {
  printf '%s✗%s nvim not found — required to resolve and write the lockfile\n' "$c_red" "$c_rst" >&2
  exit 1
}
have git || {
  printf '%s✗%s git not found — required to clone the plugins\n' "$c_red" "$c_rst" >&2
  exit 1
}

# Snapshot the current lock so --dry-run can restore it and a real run can diff.
HAD_LOCK=0
BEFORE="$(mktemp "${TMPDIR:-/tmp}/lazy-lock.before.XXXXXX")"
[[ -f "$LOCK" ]] && {
  cp "$LOCK" "$BEFORE"
  HAD_LOCK=1
}

# Throwaway XDG tree; config/nvim → the repo, so lazy writes nvim/lazy-lock.json.
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/core-nvim-lock.XXXXXX")"
cleanup() { rm -rf "$SANDBOX" "$BEFORE"; }
trap cleanup EXIT
mkdir -p "$SANDBOX/config" "$SANDBOX/data" "$SANDBOX/state" "$SANDBOX/cache"
ln -s "$HERE/nvim" "$SANDBOX/config/nvim"

printf '%s== syncing nvim plugins → upstream%s ==%s\n' \
  "$c_blu" "$([[ $DRY == 1 ]] && echo '  (dry-run)')" "$c_rst"

# DOTFILES_OFFLINE=0 so the offline guard never suppresses the sync we explicitly want.
if ! HOME="$SANDBOX" XDG_CONFIG_HOME="$SANDBOX/config" XDG_DATA_HOME="$SANDBOX/data" \
  XDG_STATE_HOME="$SANDBOX/state" XDG_CACHE_HOME="$SANDBOX/cache" DOTFILES_OFFLINE=0 \
  nvim --headless "+Lazy! sync" +qa </dev/null >"$SANDBOX/sync.log" 2>&1; then
  printf '%s✗%s :Lazy! sync failed — last lines:\n' "$c_red" "$c_rst" >&2
  tail -n 15 "$SANDBOX/sync.log" >&2
  exit 1
fi

if [[ ! -f "$LOCK" ]]; then
  printf '%s✗%s sync completed but %s was not written\n' "$c_red" "$c_rst" "$LOCK" >&2
  exit 1
fi

# Report the delta (added/removed/changed plugin commits) in human terms.
if cmp -s "$BEFORE" "$LOCK"; then
  printf '%s✓ all nvim plugin pins already current.%s\n' "$c_grn" "$c_rst"
  # "Already current" is success in BOTH modes — check (gate passes) and apply
  # (nothing to update). Exit 0 explicitly: `((CHECK)) && exit 0` would, in apply
  # mode (CHECK=0), leave `((0))` (exit status 1) as the script's LAST command, so
  # under a caller's `set -e` the freshness bot's nvim job goes red on a no-op week.
  exit 0
else
  # Show only the changed plugin entries (the lock is one JSON line per plugin).
  git --no-pager diff --no-index -- "$BEFORE" "$LOCK" 2>/dev/null |
    grep -E '^[+-][[:space:]]*"' || true
  if ((DRY)); then
    if ((HAD_LOCK)); then cp "$BEFORE" "$LOCK"; else rm -f "$LOCK"; fi # restore: touch nothing tracked
    # --check is the freshness gate: exit 2 on drift (distinct from the exit-1 failures
    # above) so the scheduled workflow surfaces a stale lock; plain --dry-run stays exit 0.
    if ((CHECK)); then
      printf '%snvim plugin pins are BEHIND — run: make update-nvim-plugins%s\n' "$c_yel" "$c_rst" >&2
      exit 2
    fi
    printf '%snvim plugin pins WOULD change. Re-run without --dry-run to apply.%s\n' "$c_blu" "$c_rst"
  else
    printf '%s✓ %s updated — review the diff, run make audit, then commit.%s\n' \
      "$c_grn" "$LOCK" "$c_rst"
  fi
fi
