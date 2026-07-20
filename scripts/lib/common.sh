# shellcheck shell=bash
# scripts/lib/common.sh — shared output helpers for the gate scripts.
# ──────────────────────────────────────────────────────────────────────────────
# ONE definition of the colour palette + pass/skip/fail/hdr/have that
# audit-core.sh, test-core.sh, bench-core.sh, sync-core.sh and update-plugins.sh
# all need — replacing five copy-pasted ~15-line blocks that could (and did) drift.
#
# This is a SOURCED library, not a runnable script — so, exactly like zsh/*.zsh, it
# carries NO shebang and stays mode 100644 (the audit's exec-bit section asserts
# this: scripts/lib/*.sh is the bash sibling of the sourced zsh modules). The
# `# shellcheck shell=bash` directive above keeps the linter in bash mode without a
# shebang. bash 3.2-safe (no associative arrays / mapfile) so it runs on macOS too.
#
# Usage (from any scripts/*.sh):
#   source "${BASH_SOURCE[0]%/*}/lib/common.sh"
# ──────────────────────────────────────────────────────────────────────────────

# Idempotent: a second source is a no-op (a script + the audit both sourcing it,
# or future nesting, must not redefine or re-zero the counters).
[[ -n "${_CORE_COMMON_SH:-}" ]] && return 0
_CORE_COMMON_SH=1

# Palette. Coloured ONLY when stdout is a real terminal and NO_COLOR is unset
# (https://no-color.org) — so `make audit > log`, `| less`, or a captured CI run
# gets clean text instead of raw \e[..m escapes littering the file. This mirrors
# zsh/05-ui.zsh, which gates its runtime helpers the same way: ONE colour rule across
# the dev tooling and the shell layer. (fail() writes to stderr, but keying the whole
# palette on stdout keeps it simple and means a redirect strips every escape at once;
# a plain `2>&1 | tee log` therefore stays readable too.) Codes live here, once.
# CLICOLOR_FORCE keeps colour on even when stdout is NOT a tty — used when a parent
# captures a child's output to a file and re-prints it to a real terminal (audit-core.sh
# overlaps the behavioral suite this way). NO_COLOR still wins (https://no-color.org).
# Colour MODE, re-evaluable so a script's `--color WHEN` flag can override the default
# AFTER this lib is sourced (the gate scripts source common.sh before their arg loop).
#   auto   (default) — colour on a TTY (or CLICOLOR_FORCE), off when piped/redirected
#   always           — colour regardless of TTY (e.g. piping into `less -R`)
#   never            — never
# NO_COLOR (https://no-color.org) is a hard override-OFF that wins over `always`.
: "${CORE_COLOR:=auto}"
# Palette now lives ONCE in the vendored bash UX lib (core/lib/ux.sh), shared with each OS
# repo's bootstrap.sh — so the colour rule isn't hand-rolled in three places (B5). Source
# it (sibling of this repo: scripts/lib/ → ../../lib/ux.sh) and map its UX_* into the c_*
# names every gate script already uses, keeping this lib's public API byte-identical.
# shellcheck source=lib/ux.sh
source "${BASH_SOURCE[0]%/*}/../../lib/ux.sh"
_core_palette() {
  UX_COLOR="${CORE_COLOR:-auto}"
  ux_palette
  c_grn=$UX_GRN c_yel=$UX_YEL c_red=$UX_RED c_blu=$UX_BLU c_rst=$UX_RST
}
_core_palette

# Tallies + quiet flag. Initialised with `:=` so a caller that runs under `set -u`
# (all of them) never trips an unbound-variable error on the first pass()/skip().
# A script that doesn't count (sync/update-plugins) simply ignores the totals.
: "${QUIET:=0}"
: "${PASS:=0}"
: "${SKIP:=0}"
: "${FAIL:=0}"
# Labels of the checks that SKIPPED, so a caller can report exactly WHICH gates didn't
# run (e.g. a CI-installed linter absent locally) instead of just a count — the
# difference between "green" and "green but partial". Declared once (this lib is
# idempotent), appended by skip() below.
_CORE_SKIPS=()

# _core_set_color <when> — validate WHEN (auto|always|never) and re-evaluate the palette.
# Non-zero on a bad value so the caller can usage-error. Every gate script's `--color`
# flag routes through this; `CORE_COLOR=<when>` in the environment works without a flag
# (so even scripts with no --color flag, e.g. bench-core.sh, honour it).
_core_set_color() {
  case "$1" in
  auto | always | never)
    CORE_COLOR="$1"
    _core_palette
    return 0
    ;;
  *) return 1 ;;
  esac
}

have() { command -v "$1" >/dev/null 2>&1; }

# pass/skip/fail keep a running tally; hdr prints a section banner. `((QUIET))` is
# always guarded by `|| …` so it can't abort a caller that runs under `set -e`
# (a bare `((0))` returns status 1).
pass() {
  PASS=$((PASS + 1))
  ((QUIET)) || printf '%s✓%s %s\n' "$c_grn" "$c_rst" "$*"
}
skip() {
  SKIP=$((SKIP + 1))
  _CORE_SKIPS+=("$*")
  # Always shown (even under --quiet) so a skip is never silent — EXCEPT in --json mode,
  # where stdout must carry only the JSON object (CORE_JSON=1, set by the caller's --json
  # arm and exported to nested gates). The skip is still tallied + recorded either way.
  ((${CORE_JSON:-0})) || printf '%s–%s %s\n' "$c_yel" "$c_rst" "$*"
}
fail() {
  FAIL=$((FAIL + 1))
  printf '%s✗%s %s\n' "$c_red" "$c_rst" "$*" >&2
}
hdr() { ((QUIET)) || printf '\n%s== %s ==%s\n' "$c_blu" "$*" "$c_rst"; }

# ── area scope (shared by audit-core.sh + test-core.sh) ───────────────────────
# Both gate scripts gate their SLOW per-area sections on these flags so a per-area run
# pays only for what it touched. They carried BYTE-IDENTICAL copies of this parser — the
# exact "two copies that drift" pattern this lib exists to kill — so it lives here once.
# FAIL-CLOSED default: unset → both areas on (full run). An empty or unknown scope token
# fails SAFE to the full run rather than silently narrowing a gate on the 9-repo fan-out.
: "${SCOPE_SHELL:=1}"
: "${SCOPE_NVIM:=1}"
_set_scope() { # _set_scope <comma-list: shell,nvim | all | none>
  SCOPE_SHELL=0
  SCOPE_NVIM=0
  local tok had=0 prog="${0##*/}"
  local IFS=,
  for tok in $1; do
    had=1
    case "$tok" in
    shell) SCOPE_SHELL=1 ;;
    nvim) SCOPE_NVIM=1 ;;
    all | full)
      SCOPE_SHELL=1
      SCOPE_NVIM=1
      ;;
    none) ;;
    *) # unknown token → run EVERYTHING (fail-safe), matching ci.yml's safe default
      printf '%s: unknown scope %s — running full (fail-safe)\n' "$prog" "$tok" >&2
      SCOPE_SHELL=1
      SCOPE_NVIM=1
      ;;
    esac
  done
  # An EMPTY scope (no tokens) is ambiguous → fail SAFE to the full run rather than
  # silently skipping every slow gate. `none` is the EXPLICIT "always-on checks only" token.
  ((had)) || {
    printf '%s: empty scope — running full (fail-safe)\n' "$prog" >&2
    SCOPE_SHELL=1
    SCOPE_NVIM=1
  }
}

# Pre-seed the EMPTY plugin dirs the hermetic zsh tests + bench need so plugins.zsh's
# first-run `git clone` is a no-op (no network). ONE plugin list, two consumers
# (test-core.sh load-order/integration sandboxes + bench-core.sh) — previously copied
# in three places, so a new pinned plugin had to be added to each by hand.
_seed_plugin_dirs() { # _seed_plugin_dirs <parent-dir>
  local parent="$1" p
  mkdir -p "$parent"
  for p in zsh-defer zsh-vi-mode zsh-history-substring-search \
    zsh-autosuggestions zsh-syntax-highlighting fzf-tab zsh-you-should-use; do
    mkdir -p "$parent/$p"
  done
}

# Read ci-classify.sh's two-line `shell=<bool>`/`nvim=<bool>` contract into
# CLASSIFY_SHELL/CLASSIFY_NVIM. Returns NON-ZERO when either key is missing or not a
# clean true/false (a classifier error or garbage) — so the caller can fail SAFE to the
# full run rather than trust a half-parsed verdict. ONE reader for the contract the audit
# (`--changed`) consumes, instead of re-implementing the sed parse + validation per site.
_core_read_classify() { # _core_read_classify <classifier-output>
  CLASSIFY_SHELL="$(printf '%s\n' "$1" | sed -n 's/^shell=//p')"
  CLASSIFY_NVIM="$(printf '%s\n' "$1" | sed -n 's/^nvim=//p')"
  case "$CLASSIFY_SHELL" in true | false) ;; *) return 1 ;; esac
  case "$CLASSIFY_NVIM" in true | false) ;; *) return 1 ;; esac
  return 0
}
