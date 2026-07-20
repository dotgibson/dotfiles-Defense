#!/usr/bin/env bash
# scripts/bench-core.sh
# ──────────────────────────────────────────────────────────────────────────────
# Measure Core's contribution to interactive-shell startup time — the metric this
# repo invests in (cached starship/zoxide/mise/atuin init in tools.zsh, deferred
# heavy plugins in plugins.zsh) but never actually MEASURED, so a regression could
# ship silently to all 9 OS repos. This is the missing perf guard: run it before
# and after a change to the load path to see the delta.
#
# It benchmarks the SAME canonical load chain scripts/test-core.sh asserts, in the
# SAME hermetic sandbox (throwaway HOME/ZDOTDIR, pre-seeded EMPTY plugin dirs so
# the first-run clone is a no-op) — so the number reflects Core's own load cost,
# reproducibly and with no network.
#
# Graceful degradation (mirrors audit-core.sh / test-core.sh): with no zsh OR no
# hyperfine it SKIPs and exits 0, so it is safe to call anywhere. hyperfine is the
# tool tools.zsh already detects as HAVE_HYPERFINE and the perf note in tools.zsh
# already points at (`hyperfine 'zsh -i -c exit'`).
#
# By default this only REPORTS the number (informational). Set CORE_BENCH_BUDGET_MS
# to turn it into a GATE: the script exits non-zero if the mean startup exceeds the
# budget, so a perf regression can fail CI instead of shipping silently to 9 repos.
# Enforcement needs python3 to read hyperfine's JSON; with no budget set, behaviour
# is unchanged (report only). Graceful skip still wins on a box with no zsh/hyperfine.
#
# Usage:
#   ./scripts/bench-core.sh                      # report the canonical-chain mean
#   CORE_BENCH_RUNS=20 ./scripts/bench-core.sh    # override the min run count
#   CORE_BENCH_BUDGET_MS=60 ./scripts/bench-core.sh  # FAIL if mean > 60 ms (gate mode)
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

# Shared palette + have()/skip() (this script keeps its own bench-table printfs).
# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

# Tuning is via env (CORE_BENCH_RUNS / CORE_BENCH_BUDGET_MS, see header). Flags: --profile
# (B11: per-module cost attribution) and -h/--help. Parse EVERY arg and reject an unknown
# one (or a stray extra) rather than ignore it — same fail-closed contract as the gates.
PROFILE=0
while (($#)); do
  case "$1" in
  --profile) PROFILE=1 ;;
  -h | --help)
    cat <<'EOF'
usage: bench-core.sh [--profile] [-h|--help]

Hermetic benchmark of the canonical zsh load chain. Report-only unless a budget is set.

  --profile                   per-module load-cost breakdown (attributes the total to
                              each module, slowest first) instead of the aggregate mean —
                              so a regression points at the culprit module. Needs zsh only.
  -h, --help                  show this help and exit

Tuning via environment:
  CORE_BENCH_RUNS=<n>          minimum hyperfine runs (default 10)
  CORE_BENCH_BUDGET_MS=<ms>    FAIL if the mean exceeds this (gate mode; needs python3)
EOF
    exit 0
    ;;
  *)
    printf 'bench-core.sh: unexpected argument: %s\n' "$1" >&2
    printf 'try: bench-core.sh --help\n' >&2
    exit 2
    ;;
  esac
  shift
done

if ! have zsh; then
  skip "bench skipped (zsh not installed)"
  exit 0
fi
# hyperfine is only needed for the aggregate benchmark, NOT for --profile (which times
# each module in-process via zsh/datetime) — so don't skip the profile run for its absence.
if ((!PROFILE)) && ! have hyperfine; then
  skip "bench skipped (hyperfine not installed — tools.zsh detects it as HAVE_HYPERFINE)"
  exit 0
fi

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/core-bench.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

# The sandbox ZDOTDIR (holds the generated .zshrc). v4: plugins moved to $XDG_DATA_HOME,
# so seeding them no longer creates $SANDBOX/zdot as a side effect — make it explicitly.
mkdir -p "$SANDBOX/zdot"
# Pre-seed empty plugin dirs so 45-plugins.zsh's first-run `git clone` is a no-op
# (hermetic, no network) — v4: plugins live under $XDG_DATA_HOME/zsh/plugins, not $ZDOTDIR.
_seed_plugin_dirs "$SANDBOX/data/zsh/plugins"

# The numbered Core fragments in load order (no os/local — those belong to OS repos). Used
# by the --profile per-module attribution below (which times each source individually).
CORE_MODULES=(00-tools 05-ui 10-options 15-history 20-aliases 25-git 30-functions 35-fzf 40-bindings 45-plugins 50-op 55-maint 60-update)
export CORE_DIR="$HERE/zsh"

# AGGREGATE benchmark: drive the REAL v4 loader against a symlinked $ZSH_CFG (like the smoke
# test), so the number includes glob + profile resolution + the compile/wordcode fast path —
# a faithful production startup, and a regression in the loader itself is now visible. (The
# --profile mode below keeps direct per-fragment sourcing, which is what per-module timing needs.)
ln -s "$HERE/zsh/loader.zsh" "$SANDBOX/zdot/loader.zsh"
for f in "$HERE"/zsh/[0-9][0-9]-*.zsh; do ln -s "$f" "$SANDBOX/zdot/$(basename "$f")"; done
# $ZDOTDIR/$ZSH_CFG stay LITERAL in the written .zshrc (expanded by the zsh child at startup,
# not this bash parent) — so the single quotes are intentional. shellcheck disable=SC2016
# shellcheck disable=SC2016
printf 'ZSH_CFG="$ZDOTDIR"\nsource "$ZSH_CFG/loader.zsh"\n' >"$SANDBOX/zdot/.zshrc"

# ── --profile: per-module cost attribution (B11) ──────────────────────────────
# The aggregate mean tells you startup got slower; it doesn't tell you WHICH module. This
# sources the canonical chain in ONE hermetic interactive zsh, timing each module with
# zsh/datetime's $EPOCHREALTIME, and prints the breakdown slowest-first — so a regression
# points at the culprit. Informational (no gate); needs zsh only, not hyperfine.
if ((PROFILE)); then
  printf '\n%s== Core startup profile (per-module, hermetic) ==%s\n' "$c_blu" "$c_rst"
  # shellcheck disable=SC2016  # $EPOCHREALTIME/$m/$CORE_DIR expand in the zsh CHILD.
  prof_body='zmodload zsh/datetime
    typeset -F prev=$EPOCHREALTIME now total=0
    for _m in '"${CORE_MODULES[*]}"'; do
      source "$CORE_DIR/$_m.zsh" 2>/dev/null
      now=$EPOCHREALTIME
      printf "%8.1f ms  %s\n" $(( (now-prev)*1000 )) "$_m"
      (( total += (now-prev)*1000 )); prev=$now
    done
    printf "%8.1f ms  %s\n" $total "TOTAL"'
  HOME="$SANDBOX" ZDOTDIR="$SANDBOX/zdot" \
    XDG_CACHE_HOME="$SANDBOX/cache" XDG_STATE_HOME="$SANDBOX/state" \
    XDG_RUNTIME_DIR="$SANDBOX/run" XDG_DATA_HOME="$SANDBOX/data" CORE_DIR="$CORE_DIR" \
    zsh -ic "$prof_body" 2>/dev/null | sort -rn | sed "s/^/  /"
  printf '%s(per-module wall time; TOTAL sorts to the top — run twice, the 2nd is warm)%s\n' "$c_blu" "$c_rst"
  exit 0
fi

runs="${CORE_BENCH_RUNS:-10}"
printf '\n%s== Core startup benchmark (canonical .zshrc chain, hermetic) ==%s\n' "$c_blu" "$c_rst"

# `zsh -i -c exit` sources the sandbox .zshrc (interactive, so the modules' `[[ $-
# == *i* ]]` guards pass) and exits. --warmup primes the fs/exec cache so the
# reported mean is steady-state, not first-run cold. --export-json captures the
# mean for the optional budget gate below (the human table still prints).
BUDGET="${CORE_BENCH_BUDGET_MS:-}"
json="$SANDBOX/bench.json"
HOME="$SANDBOX" ZDOTDIR="$SANDBOX/zdot" \
  XDG_CACHE_HOME="$SANDBOX/cache" XDG_STATE_HOME="$SANDBOX/state" \
  XDG_RUNTIME_DIR="$SANDBOX/run" XDG_DATA_HOME="$SANDBOX/data" CORE_DIR="$CORE_DIR" \
  hyperfine --warmup 3 --min-runs "$runs" --export-json "$json" 'zsh -i -c exit'

# ── optional budget gate ──────────────────────────────────────────────────────
# Report-only unless CORE_BENCH_BUDGET_MS is set. hyperfine's JSON reports the mean
# in SECONDS; python3 converts to ms and compares. No budget → no gate; a budget
# with no python3 → loud skip rather than a false pass (the gate must be honest).
[[ -z "$BUDGET" ]] && exit 0
if ! have python3; then
  skip "budget set ($BUDGET ms) but python3 absent — cannot read hyperfine JSON; not gating"
  exit 0
fi
mean_ms="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["results"][0]["mean"]*1000)' "$json" 2>/dev/null)"
[[ -n "$mean_ms" ]] || {
  printf '%s✗%s could not parse hyperfine JSON for the budget gate\n' "$c_red" "$c_rst" >&2
  exit 1
}
if python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) <= float(sys.argv[2]) else 1)' "$mean_ms" "$BUDGET"; then
  printf '%s✓%s startup mean %.1f ms within budget %s ms\n' "$c_grn" "$c_rst" "$mean_ms" "$BUDGET"
else
  printf '%s✗%s startup mean %.1f ms EXCEEDS budget %s ms — perf regression\n' "$c_red" "$c_rst" "$mean_ms" "$BUDGET" >&2
  exit 1
fi
