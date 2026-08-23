#!/usr/bin/env bash
# scripts/update-nvim-plugins.sh
# ──────────────────────────────────────────────────────────────────────────────
# Deliberately roll the pinned Neovim plugin revisions in nvim/lazy-lock.json
# forward. This is the lazy.nvim counterpart of scripts/update-plugins.sh (which
# bumps the zsh-plugin SHAs): pins exist so nothing floats silently into the 8 OS
# repos, and THIS is the one place the nvim ones move — under review, not on their own.
#
# Why a committed lockfile at all: lazy.nvim clones plugins from their default
# branches (config/lazy.lua), so without nvim/lazy-lock.json every box — and every
# vendored OS repo — resolves a DIFFERENT commit, i.e. a non-reproducible editor.
# The tracked lockfile pins all of them; `:Lazy restore` installs exactly those.
#
# How it works: run the REPO's real nvim config headlessly in a throwaway HOME whose
# config dir is symlinked to nvim/. `:Lazy! sync` installs/updates/cleans and rewrites the
# lock, which lands in the sandbox's XDG_STATE_HOME (config/lazy.lua points lazy's
# `lockfile` at state, since a file lazy rewrites in place must not live in the vendored
# tree — #465); this script then copies it back into nvim/lazy-lock.json. lazy.lua seeds an
# empty state dir from that same file, so the sync rolls FORWARD from the committed pins.
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

# Throwaway XDG tree; config/nvim → the repo, so the sandbox runs THIS repo's real config.
#
# The lockfile lazy writes is no longer nvim/lazy-lock.json directly: config/lazy.lua now
# points `lockfile` at $XDG_STATE_HOME/nvim/lazy-lock.json, because a lockfile lazy rewrites
# in place cannot live inside the byte-verified vendored tree (#465). So the sandbox's STATE
# dir is where the sync lands, and this script copies the result back into the repo — which
# is the correct division either way: lazy owns the machine's mutable lockfile, and THIS
# SCRIPT is the one thing allowed to move the fleet's committed seed.
#
# The seeding in lazy.lua does the rest: the sandbox state dir starts empty, so the first
# thing that config does is copy nvim/lazy-lock.json into it. A sync therefore still rolls
# FORWARD from the repo's current pins rather than re-resolving every plugin from its
# default branch — which is what makes the reported delta meaningful.
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/core-nvim-lock.XXXXXX")"
cleanup() { rm -rf "$SANDBOX" "$BEFORE"; }
trap cleanup EXIT
mkdir -p "$SANDBOX/config" "$SANDBOX/data" "$SANDBOX/state" "$SANDBOX/cache"
ln -s "$HERE/nvim" "$SANDBOX/config/nvim"
# Where lazy will actually write it: stdpath("state") is $XDG_STATE_HOME/nvim.
SANDBOX_LOCK="$SANDBOX/state/nvim/lazy-lock.json"

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

# Assert on the file lazy ACTUALLY writes, not on the repo copy — otherwise a sync that
# silently wrote nothing would be masked by the seed copy still sitting in the repo, and
# "no changes" would be reported for a run that did nothing at all.
if [[ ! -f "$SANDBOX_LOCK" ]]; then
  printf '%s✗%s sync completed but %s was not written\n' "$c_red" "$c_rst" "$SANDBOX_LOCK" >&2
  exit 1
fi
# Bring the synced pins back into the repo, where they are the fleet seed under review.
# Both the diff report and the --dry-run restore below operate on $LOCK, exactly as before,
# so everything downstream of here is unchanged.
cp "$SANDBOX_LOCK" "$LOCK"

# Report the delta (added/removed/changed plugin commits) in human terms.
if core_files_identical "$BEFORE" "$LOCK"; then
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
