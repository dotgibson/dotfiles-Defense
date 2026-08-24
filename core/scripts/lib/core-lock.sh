# shellcheck shell=bash
# scripts/lib/core-lock.sh — ONE definition of "does this repo's core/ match its core.lock?"
# ──────────────────────────────────────────────────────────────────────────────
# The comparison lives here because TWO gates need it and they sit on opposite sides of
# the same fact: sync-core.sh PRODUCES the vendored tree and the lock that describes it,
# and core-integrity.sh REPORTS on the pair later. While only the reporter could make the
# comparison, a sync could land a tree and a lock that disagreed and still exit 0 — the
# mismatch surfaced whenever an unrelated command next ran the integrity check, as a
# `TAMPERED (core/ edited since sync)` verdict on a tree nobody had touched (#556).
#
# Two implementations of one comparison would be worse than one shared one: the producer's
# self-check has to mean exactly what the reporter will later say, or a sync can pass its
# own assertion and still be reported dirty.
#
# This is a SOURCED library, not a runnable script — so, like scripts/lib/common.sh, it
# carries NO shebang and stays mode 100644 (audit-core.sh's exec-bit section asserts this).
# bash 3.2-safe (no associative arrays / mapfile) so it runs on macOS too.
#
# Every function is PURE — reads only, no shared-state writes. Callers run them in command
# substitutions (subshells), where a write would be lost anyway, and both callers run under
# different `set` options (sync-core.sh uses `set -euo pipefail`, core-integrity.sh
# `set -uo pipefail`), so nothing here may depend on either.

# Read a `key=value` value from a core.lock-style file. Tolerates surrounding whitespace;
# first match wins.
core_lock_read_kv() { # core_lock_read_kv <file> <key>
  sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//p" "$1" 2>/dev/null | head -n1
}

# The tree object a consumer has actually vendored at core/. Present in any checkout,
# including a depth-1 clone — it is read from the commit, not from history.
core_lock_vendored_tree() { # core_lock_vendored_tree <consumer-dir>
  git -C "$1" rev-parse --verify --quiet 'HEAD:core' 2>/dev/null
}

# The tree object a given Core commit SHOULD produce: dotfiles-core's whole tree at that
# commit. Fails when the object is absent, which is itself meaningful — the lock names a
# commit that is not in this Core's history (a phantom or rewritten sha).
core_lock_expected_tree() { # core_lock_expected_tree <core-dir> <sha>
  git -C "$1" rev-parse --verify --quiet "${2}^{tree}" 2>/dev/null
}

# Classify a consumer's vendored core/ against the commit its core.lock pins.
# Echoes a status string; "pristine" is the only clean one.
#
# <core-dir> is REQUIRED rather than defaulting to a caller global: a library that reaches
# for the caller's $HERE couples the two in a way that is invisible at the call site and
# breaks the moment a second caller has a different one. sync-core.sh resolves the expected
# tree inside the CONSUMER (which is guaranteed to hold the object after its fetch), while
# core-integrity.sh resolves it in Core itself — the same comparison, two vantage points.
core_lock_classify() { # core_lock_classify <consumer-dir> <recorded-sha> <core-dir>
  local dir="$1" rec="$2" core="$3" vend exp
  [[ -n "$rec" ]] || { echo "no core_sha recorded"; return; }
  vend="$(core_lock_vendored_tree "$dir")" ||
    { echo "no vendored core/ (not a subtree consumer?)"; return; }
  [[ -n "$vend" ]] ||
    { echo "no vendored core/ (not a subtree consumer?)"; return; }
  exp="$(core_lock_expected_tree "$core" "$rec")" ||
    { echo "UNVERIFIABLE (locked sha not in Core history)"; return; }
  [[ -n "$exp" ]] ||
    { echo "UNVERIFIABLE (locked sha not in Core history)"; return; }
  if [[ "$vend" == "$exp" ]]; then echo "pristine"; else echo "TAMPERED (core/ edited since sync)"; fi
}
