#!/usr/bin/env bash
# scripts/bench-atuin-daemon.sh
# ──────────────────────────────────────────────────────────────────────────────
# Measure the ONE claim atuin daemon adoption never proved: that letting the daemon
# own the SQLite writes removes the DB-lock contention every shell and every tmux
# pane otherwise pays. core/atuin/config.toml and zsh/00-tools.zsh both assert that
# rationale on UPSTREAM's authority — it was never measured here — and this script
# is what turns it into a number.
#
# WHAT THIS COVERS, AND WHAT IT CANNOT. Proving the claim on the paths the fleet
# actually ships needs hardware: a real Fedora box for the systemd-unit path and a
# real musl box for the autostart path. This script does NOT stand in for those. What
# a plain Linux container DOES reproduce is the TOPOLOGY of the Alpine path — no
# systemd user manager, XDG_RUNTIME_DIR unset, so atuin falls back to
# ~/.local/share/atuin/atuin.sock, which is exactly the path _core_atuin_daemon_guard
# (zsh/00-tools.zsh) resolves. That is enough to measure the contention mechanism
# directly and to confirm atuin and the guard agree on the socket path — a fact the
# behavioral suite can today only assert from reading upstream's settings.rs.
#
# So a green run here NARROWS the gap; it does not close it. Every number this prints
# carries these caveats, and the summary repeats them — computed from the run that actually
# happened, not hardcoded — so a figure cannot be quoted without them:
#   · a container, not real hardware        · glibc, not musl
#   · no systemd unit (the Fedora path)     · local disk, not a network home
#   · synthetic commands, not a real session
#
# TWO OF THOSE ROWS NOW HAVE A LEVER. `--systemd` measures the systemd-unit path, and
# CORE_ATBENCH_BASE moves the sandbox onto a network home. See --help for both.
#
# UNVALIDATED-SYSTEMD. `--systemd` has NEVER been executed against a real systemd user bus:
# it was written where `systemd-run --user` cannot connect to one, so only its fail-closed
# skip path has ever run. It is shipped anyway because the alternative — leaving the Fedora
# box with a harness that structurally cannot test its own path — is worse, but a first real
# run is VALIDATION, not data. Check three things before believing any figure it prints:
# the unit stayed `active` for the whole arm, MainPID owned the listening socket, and the
# row deltas were exact. `git grep UNVALIDATED-SYSTEMD` enumerates every place that claim is
# made, which is the set to update once it has actually run.
#
# WHAT IT MEASURES — TWO METRICS, AND THE DIFFERENCE IS NOT COSMETIC. Every run reports
# both, because a shell hook does not pay for the two calls the same way:
#
#   PROMPT LATENCY   `atuin history start` alone. atuin's `_atuin_preexec` runs it in a
#                    COMMAND SUBSTITUTION — `id=$(atuin history start --hook ...)` — so the
#                    shell blocks on it. This is what a human waits for, and the only
#                    metric that may be quoted as "per-command latency".
#   TOTAL WRITE WORK `start` + `end` together. `_atuin_precmd` fires `end` into a detached
#                    background subshell — `(atuin history end ... &)` — so it costs the
#                    box, never the prompt. Real load; NOT latency.
#
# Until this split existed the harness timed the two together and printed one table, so
# every figure it had ever produced was TOTAL WRITE WORK wearing a latency label. That is
# not a hypothetical mislabelling: this repo's own records disagree about the tail, and the
# disagreement lines up exactly with the metric. The runs that timed the pair concluded the
# far tail got WORSE with the daemon; the one run that timed only the blocking call (real
# Fedora, systemd) measured p99 improving 49-69%. `end` is where the two diverge — with the
# daemon off it is the slower of the two calls (the UPDATE costs more than the INSERT) and
# with it on they equalise — so folding it into a "latency" number moves the metric most
# precisely where the daemon is being judged. Treat the pre-split figures recorded in
# atuin/config.toml as total-write-work, and re-measure before restating any tail claim.
#
# Both are computed from ONE timed pass, not two runs: the writer takes a timestamp between
# the calls. So the two tables are strictly comparable — same samples, same contention.
#
# Reported as p50/p95/p99 so the TAIL (the thing the daemon is adopted for) is visible and
# not averaged away, under N concurrent writers sharing one already-busy history DB.
# Three arms:
#   off              Core's shipped default: every writer opens the DB itself
#   on               daemon enabled and already running (the supervised shape)
#   autostart-first  no daemon running, autostart=true — isolates the daemon-SPAWN
#                    cost the FIRST command in a fresh shell pays, which is unique to
#                    the Alpine path and has its own open question upstream of here
#
# It runs the atuin BINARY directly rather than through Core's zsh load chain: the
# subject is atuin's write path, not shell startup. Startup cost is bench-core.sh's
# job, and the daemon is not on the startup path at all.
#
# NOT part of `make audit`, deliberately: this needs a real atuin binary and it starts
# a background daemon. The audit gate does neither. Report-only, no budget, no exit
# code to gate on — like bench-core.sh's default mode.
#
# Graceful degradation (mirrors audit-core.sh / test-core.sh / bench-core.sh): any
# missing prerequisite SKIPs and exits 0, so this is safe to call on a bare box.
#
# Usage:
#   ./scripts/bench-atuin-daemon.sh                       # the three-arm comparison
#   ./scripts/bench-atuin-daemon.sh --systemd             # via a transient user unit
#   CORE_ATBENCH_WRITERS=16 ./scripts/bench-atuin-daemon.sh   # heavier contention
#   CORE_ATBENCH_SEED=50000 ./scripts/bench-atuin-daemon.sh   # a busier history DB
#   CORE_ATBENCH_BASE=/net/home/you ./scripts/bench-atuin-daemon.sh   # network home
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

# Shared palette + have()/skip() (this script keeps its own result-table printfs).
# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

# Tuning is via env (see header). Parse EVERY arg and reject an unknown one (or a stray
# extra) rather than ignore it — the same fail-closed contract as the gates.
SYSTEMD=0
# NOTE the `shift`: until --systemd existed every branch below exited, so the loop could not
# spin and the missing shift was invisible. A flag that merely SETS something needs it.
while (($#)); do
  case "$1" in
  --systemd) SYSTEMD=1 ;;
  -h | --help)
    cat <<'EOF'
usage: bench-atuin-daemon.sh [--systemd] [-h|--help]

Measure atuin's per-command write cost with the daemon OFF vs ON, under concurrent
writers sharing one busy history DB. Hermetic (throwaway HOME) and report-only.

TWO METRICS, from one timed pass, reported as two tables:
  PROMPT LATENCY     `history start` alone — the call _atuin_preexec blocks the prompt
                     on. The only figure that may be quoted as per-command latency.
  TOTAL WRITE WORK   `start` + `end` — _atuin_precmd backgrounds `end`, so this is load
                     on the box, not time at the prompt.
Keep them apart when reporting: timing the pair and calling it latency is what left this
repo's own records disagreeing about whether the daemon helps or hurts the tail.

By default this reproduces the TOPOLOGY of the Alpine/no-systemd path only — not musl,
not real hardware, not a network home. Results carry those caveats.

  --systemd   Measure the SYSTEMD-UNIT path instead: run the daemon from a sandbox-scoped
              TRANSIENT unit (systemd-run --user), with XDG_RUNTIME_DIR pointed at the
              sandbox, so atuin resolves its default $XDG_RUNTIME_DIR/atuin.sock — the
              branch the default mode structurally cannot reach. It never touches your real
              atuin-daemon.service. Without a systemd user bus it SKIPs; it never falls back
              to the no-systemd path, because those numbers under a systemd label are the
              one thing this flag exists to prevent. The autostart arm is skipped (autostart
              and a supervised unit are mutually exclusive).
              UNVALIDATED-SYSTEMD: written where no user bus exists, so only the fail-closed
              skip path has ever executed. Treat a first real run as validation, not data.

Tuning via environment:
  CORE_ATBENCH_WRITERS=<n>   concurrent writer processes (default 8 — a busy tmux)
  CORE_ATBENCH_ITERS=<n>     commands each writer runs (default 200)
  CORE_ATBENCH_SEED=<n>      history rows pre-seeded into the DB (default 20000)
  CORE_ATBENCH_REPS=<n>      fresh-shell repetitions for autostart-first (default 10)
  CORE_ATBENCH_BASE=<dir>    put the sandbox HOME + history DB under <dir> instead of /tmp,
                             so the contention claim can be measured on a NETWORK HOME. The
                             socket is forced onto a short local path (AF_UNIX does not work
                             on NFS/SMB and sun_path caps near 108 bytes), which means such a
                             run does NOT exercise atuin's default socket resolution — the
                             output says so, and withdraws the socket-agreement check.
EOF
    exit 0
    ;;
  *)
    printf 'bench-atuin-daemon.sh: unexpected argument: %s\n' "$1" >&2
    printf 'try: bench-atuin-daemon.sh --help\n' >&2
    exit 2
    ;;
  esac
  shift
done

# ── validate the request ──────────────────────────────────────────────────────
# Before any prerequisite check, because a malformed knob is a CALLER error (exit 2, like an
# unknown flag), not a missing prerequisite (skip, exit 0). WRITERS=0 matters most: it makes
# every arm vacuously "complete" AND vacuously row-correct (0 samples, 0 rows), which is the
# one way to get a green run that measured nothing at all.
for _k in WRITERS ITERS SEED REPS; do
  eval "_v=\${CORE_ATBENCH_$_k:-}"
  [[ -z "$_v" ]] && continue
  # ^[1-9][0-9]*$ — canonical positive integers ONLY, in one test. `^[0-9]+$` plus an
  # arithmetic `< 1` looks equivalent and is not: `08` passes the digit class, and bash then
  # reads it as OCTAL, so `((_v < 1))` dies with "value too great for base" instead of
  # producing the promised exit 2 — and the bad value goes on to break the writer loops.
  # Rejecting the zero-padded form outright also rejects `0` and non-numerics, so this one
  # pattern replaces all three checks. (scripts/auto-tag.sh carries an octal-safety test for
  # the same trap.)
  if [[ ! "$_v" =~ ^[1-9][0-9]*$ ]]; then
    printf 'bench-atuin-daemon.sh: CORE_ATBENCH_%s must be a positive integer with no leading zero: %s\n' \
      "$_k" "$_v" >&2
    exit 2
  fi
done

BASE="${CORE_ATBENCH_BASE:-}"
if [[ -n "$BASE" ]]; then
  # Absolute required: this script cd's to the repo root above, so a relative base would
  # silently resolve against it and scatter a sandbox through the working tree.
  if [[ "$BASE" != /* ]]; then
    printf 'bench-atuin-daemon.sh: CORE_ATBENCH_BASE must be an absolute path: %s\n' "$BASE" >&2
    exit 2
  fi
  if [[ ! -d "$BASE" ]]; then
    printf 'bench-atuin-daemon.sh: CORE_ATBENCH_BASE is not a directory: %s\n' "$BASE" >&2
    exit 2
  fi
  if [[ ! -w "$BASE" ]]; then
    printf 'bench-atuin-daemon.sh: CORE_ATBENCH_BASE is not writable: %s\n' "$BASE" >&2
    exit 2
  fi
fi

# ── mode preflight (fail-closed) ──────────────────────────────────────────────
# Deliberately BEFORE the tool prerequisites below: a --systemd run on a box with no user
# bus is doomed whether or not atuin exists, and the mode skip is the more specific answer
# to what the caller actually asked for. (scripts/test-core.sh depends on this ordering to
# assert the fail-closed path without stubbing atuin/zsh/python3 — if an earlier external
# dependency ever appears, that test breaks loudly, which is the point.)
#
# Binary presence is NOT a sufficient probe. systemd-run and systemctl exist in plenty of
# containers that have no user manager at all; `systemctl --user show-environment` is what
# distinguishes "the tool is installed" from "there is a bus to talk to", and it is cheaper
# and less side-effecting than starting a canary unit to find out.
if ((SYSTEMD)); then
  _sd_ok=1
  have systemctl && have systemd-run || _sd_ok=0
  ((_sd_ok)) && [[ -d /run/systemd/system ]] || _sd_ok=0
  ((_sd_ok)) && systemctl --user show-environment >/dev/null 2>&1 || _sd_ok=0
  if ((!_sd_ok)); then
    skip "atuin daemon bench --systemd skipped (no systemd user manager — 'systemctl --user' cannot reach a bus)"
    printf '   Refusing to fall back to the no-systemd path: those numbers would be reported\n'
    printf '   under a systemd label, which is the one thing --systemd exists to prevent.\n'
    printf '   Run without --systemd for the no-systemd topology.\n'
    printf '   (UNVALIDATED-SYSTEMD: to date only this skip path has ever executed.)\n'
    exit 0
  fi
fi

# ── prerequisites ─────────────────────────────────────────────────────────────
# atuin is the subject; zsh times the writers with $EPOCHREALTIME (the same idiom
# bench-core.sh --profile uses); python3 seeds the DB and computes the percentiles
# (already this repo's convention for "needs real parsing/arithmetic" — bench-core.sh's
# budget gate and audit-core.sh's config gate both lean on it).
for _t in atuin zsh python3; do
  if ! have "$_t"; then
    skip "atuin daemon bench skipped ($_t not installed)"
    exit 0
  fi
done

WRITERS="${CORE_ATBENCH_WRITERS:-8}"
# 200 x 8 writers = 1600 samples per arm. Sized for the METRIC THAT MATTERS: p99 of 400
# samples is the 4th-worst observation, which moves by tens of percent between runs — a
# tail benchmark whose default cannot support a stable tail number is worse than none,
# because it invites a conclusion the data does not carry. At 1600 the p50/p95 are steady
# run-to-run; the p99 still is not, and the summary says so rather than pretending.
ITERS="${CORE_ATBENCH_ITERS:-200}"
SEED="${CORE_ATBENCH_SEED:-20000}"
REPS="${CORE_ATBENCH_REPS:-10}"

# ── sandbox ───────────────────────────────────────────────────────────────────
# Deliberately NOT ${TMPDIR:-/tmp} (which is what bench-core.sh uses): the daemon binds
# an AF_UNIX socket under $HOME, and sun_path caps at ~108 bytes. Under a long TMPDIR
# the daemon dies with "path must be shorter than SUN_LEN" (atuin-daemon/src/server.rs)
# — an obscure failure that reads as "the daemon is broken" rather than "your tmpdir is
# long". A short, fixed base plus the explicit preflight below keeps that legible.
#
# TWO directories, not one. LOCALDIR is always short and always LOCAL, and holds the runtime
# dir and hence the socket. SB holds HOME and the databases, and is the same directory as
# LOCALDIR unless CORE_ATBENCH_BASE moves it. That split is what makes a network-home run
# possible at all: AF_UNIX does not work on NFS/SMB, so the socket can never live beside the
# DB there. With no base override the two are identical and the layout is exactly as before.
LOCALDIR="$(mktemp -d /tmp/atbench.XXXXXX)" || {
  skip "atuin daemon bench skipped (could not create a sandbox under /tmp)"
  exit 0
}
if [[ -n "$BASE" ]]; then
  SB="$(mktemp -d "$BASE/atbench.XXXXXX")" || {
    # LOCALDIR already exists and the EXIT trap is not installed yet, so clean it up by hand
    # or every failed network-home setup leaves a /tmp/atbench.* behind.
    rm -rf "$LOCALDIR"
    skip "atuin daemon bench skipped (could not create a sandbox under $BASE)"
    exit 0
  }
else
  SB="$LOCALDIR"
fi
# The runtime dir lives on LOCALDIR even in the default mode, so --systemd and
# CORE_ATBENCH_BASE compose. In the default case this IS "$SB/run" at mode 0700.
RUNDIR="$LOCALDIR/run"
mkdir -p "$RUNDIR"
chmod 700 "$RUNDIR"
DAEMON_PID=""
UNIT=""
# Ask the daemon in OUR SANDBOX to shut down, via its own socket. Never `pkill atuin`:
# the pattern is process-wide, so a developer running `make bench-atuin` on their
# workstation would kill the real daemon their shells are using. Everything here is
# scoped by AT_ENV (defined below) to the throwaway HOME, so it can only ever reach the
# daemon this script started. Safe before AT_ENV exists — the guard makes it a no-op.
daemon_stop() {
  # In systemd mode this is a HARD NO-OP, and the unit is torn down by unit_stop instead.
  # Not for the reason the spec gives (that `atuin daemon stop` might reach the developer's
  # real daemon — it cannot, because XDG_RUNTIME_DIR is sandboxed, so the command resolves
  # OUR socket). The real hazards are both about fighting the service manager: `atuin daemon
  # stop` would kill the transient unit's process behind systemd's back, leaving the "on"
  # arm quietly measuring an enabled-but-unreachable daemon — the exact silent-discard shape
  # the row rule exists to catch — and `rm -f "$SOCK"` would unlink a live unit's bound
  # socket. It is also the belt to that braces: if the sandboxed runtime dir is ever
  # relaxed, this no-op is what still stops the generic path reaching a real daemon.
  ((SYSTEMD)) && return 0
  [[ ${#AT_ENV[@]} -gt 0 ]] &&
    "${AT_ENV[@]}" ATUIN_DAEMON__ENABLED=true atuin daemon stop >/dev/null 2>&1
  if [[ -n "$DAEMON_PID" ]]; then
    kill "$DAEMON_PID" 2>/dev/null
    wait "$DAEMON_PID" 2>/dev/null
    DAEMON_PID=""
  fi
  [[ -n "$SOCK" ]] && rm -f "$SOCK"
  return 0
}
# Stop only OUR transient unit, by its unique name. Never `systemctl --user stop
# atuin-daemon` — that is the developer's own service.
unit_stop() {
  ((SYSTEMD)) || return 0
  [[ -n "$UNIT" ]] || return 0
  systemctl --user stop "$UNIT" >/dev/null 2>&1
  systemctl --user reset-failed "$UNIT" >/dev/null 2>&1
  return 0
}
# The autostart arm has atuin spawn a daemon this script never learns the PID of, so a
# PID-only cleanup would leave it running against a HOME that is about to be deleted.
# Stopping through the socket first catches that one too.
AT_ENV=()
AT_VARS=()
SOCK=""
cleanup() {
  daemon_stop
  # BEFORE the rm -rf, or the daemon spends its last moments writing into a deleted tree.
  unit_stop
  # Only ever the mktemp-created directories — never $CORE_ATBENCH_BASE itself, which is a
  # caller-supplied path and the one thing here that must never meet `rm -rf`.
  [[ -n "$SB" ]] && rm -rf "$SB"
  [[ -n "$LOCALDIR" && "$LOCALDIR" != "$SB" ]] && rm -rf "$LOCALDIR"
  return 0
}
trap cleanup EXIT

# Which socket path atuin will resolve, decided once, here — and the SUN_LEN preflight then
# checks whichever one this run actually uses. That is the point: before, the check was
# hardcoded to the data-dir path and so could not describe a run that used any other.
# Filesystem type of a path, for the disclosure below. `stat -f -c %T` is GNU-only and this
# script is meant to run on macOS too, where `-f` means something else entirely — so probe
# it and fall back rather than printing "stat: illegal option" into a results header.
fs_type() {
  local t=""
  t="$(stat -f -c %T "$1" 2>/dev/null)" && [[ -n "$t" ]] && {
    printf '%s' "$t"
    return 0
  }
  t="$(df -P "$1" 2>/dev/null | awk 'NR==2 {print $1}')" && [[ -n "$t" ]] && {
    printf 'on %s' "$t"
    return 0
  }
  printf 'unknown fs'
}

SOCK_FORCED=""
if [[ -n "$BASE" ]]; then
  # A network-home sandbox cannot host the socket at all, so it is pinned to the local
  # runtime dir via ATUIN_DAEMON__SOCKET_PATH. This is the honest cost of the mode, and it
  # is disclosed in the banner, on the arm labels and in the caveat block.
  SOCK_FORCED="$RUNDIR/atuin.sock"
  SOCK="$SOCK_FORCED"
elif ((SYSTEMD)); then
  # atuin's DEFAULT when XDG_RUNTIME_DIR is set — the first branch of the guard's
  # expression, which the env -i mode structurally cannot reach.
  SOCK="$RUNDIR/atuin.sock"
else
  SOCK="$SB/.local/share/atuin/atuin.sock"
fi
if ((${#SOCK} > 100)); then
  skip "atuin daemon bench skipped (socket path is ${#SOCK} bytes — AF_UNIX caps near 108)"
  exit 0
fi

# Run against Core's REAL config, not a synthetic one: the [daemon] block's deliberately
# UNSET enabled/autostart keys are precisely what lets the ATUIN_* env overrides below
# reach atuin at all (see the long comment in atuin/config.toml), so a bench with its own
# config would silently stop testing the thing Core actually ships.
mkdir -p "$SB/.config/atuin"
cp "$HERE/atuin/config.toml" "$SB/.config/atuin/config.toml"

# `env -i` — an EMPTY environment, not merely HOME reassigned. Setting HOME alone is not
# hermetic and the failure is destructive rather than cosmetic: a caller who exports
# XDG_DATA_HOME (common) would send atuin's data dir OUTSIDE the sandbox, so the seeding
# step below would import 20k synthetic rows straight into THEIR REAL history DB. An
# inherited ATUIN_DAEMON__ENABLED would likewise run the "off" arm with the daemon on and
# quietly invalidate the comparison. Starting from nothing and naming every variable makes
# both impossible, and in the DEFAULT mode it is also what guarantees the topology this
# reproduces: XDG_RUNTIME_DIR cannot be set, so atuin must fall back to the data-dir socket.
#
# The variables live in AT_VARS, ONE list with two consumers: `env -i "${AT_VARS[@]}"` for
# the writers, and one `--setenv=` per entry for the transient unit in systemd mode.
# systemd-run has no `env -i`, so naming every variable is its only equivalent — and
# deriving the unit's list mechanically from the same array is what keeps the two identical.
# A variable present here but missing from the unit would be inherited from the user
# manager's environment, which is how a bench daemon ends up opening the developer's REAL
# history.db. Not a drift worth risking to a second hand-maintained list.
AT_VARS=(
  "PATH=$PATH"
  "HOME=$SB"
  "XDG_DATA_HOME=$SB/.local/share"
  "XDG_CONFIG_HOME=$SB/.config"
  "XDG_CACHE_HOME=$SB/.cache"
  "XDG_STATE_HOME=$SB/.local/state"
  "TERM=${TERM:-dumb}"
)
# ONLY in systemd mode. Adding it unconditionally would destroy the default mode's entire
# premise — that XDG_RUNTIME_DIR cannot be set, so the data-dir fallback is forced.
((SYSTEMD)) && AT_VARS+=("XDG_RUNTIME_DIR=$RUNDIR")
[[ -n "$SOCK_FORCED" ]] && AT_VARS+=("ATUIN_DAEMON__SOCKET_PATH=$SOCK_FORCED")
AT_ENV=(env -i "${AT_VARS[@]}")

printf '\n%s== atuin daemon: per-command write latency under contention ==%s\n' "$c_blu" "$c_rst"
if ((SYSTEMD)); then
  printf '   %s writers x %s commands, %s-row seeded DB, XDG_RUNTIME_DIR=%s\n' \
    "$WRITERS" "$ITERS" "$SEED" "$RUNDIR"
  printf '%s   !! UNVALIDATED-SYSTEMD: this mode has never been executed against a real\n' "$c_yel"
  printf '      systemd user bus. It was written where one does not exist, so only its\n'
  printf '      fail-closed skip path has ever run. Treat this run as its first\n'
  printf '      validation, not as data.%s\n' "$c_rst"
else
  printf '   %s writers x %s commands, %s-row seeded DB, XDG_RUNTIME_DIR unset\n' \
    "$WRITERS" "$ITERS" "$SEED"
fi
if [[ -n "$BASE" ]]; then
  printf '   base override: HOME + history DB under %s (%s)\n' "$BASE" "$(fs_type "$SB")"
  printf '   socket forced to %s\n' "$SOCK_FORCED"
  printf '%s   ATUIN_DAEMON__SOCKET_PATH is set, so this run does NOT exercise atuin'"'"'s DEFAULT\n' "$c_yel"
  printf '   socket resolution — the same flaw the earlier Fedora run had. It is unavoidable:\n'
  printf '   AF_UNIX does not work on NFS/SMB and sun_path caps near 108 bytes, so a\n'
  printf '   network-home sandbox cannot host the socket. What this measures is DB contention\n'
  printf '   on that storage; what it does not measure is where atuin decides to put its\n'
  printf '   socket.%s\n' "$c_rst"
  # Classified by NAMING THE NETWORK filesystems and warning about everything else, not the
  # other way round. An allowlist of local types silently passes anything it has not heard
  # of — and `stat -f -c %T` prints things like "ext2/ext3" and "fuseblk" that no such list
  # reliably anticipates (that exact string is why the first version of this check never
  # fired on ext4). Erring toward the warning is also the safe direction: the cost of a
  # spurious note is a line of output, the cost of a missing one is a local run quoted as a
  # network-home result.
  case "$(fs_type "$SB")" in
  nfs | nfs4 | smb | smb2 | cifs | 9p | afs | fuse.sshfs | fuseblk) ;;
  *)
    printf '%s   note: %s does not look like a network filesystem (%s) — this is NOT a\n' \
      "$c_yel" "$BASE" "$(fs_type "$SB")"
    printf '   network-home run despite the override, and must not be quoted as one.%s\n' "$c_rst"
    ;;
  esac
fi

# ── seed a BUSY history DB ────────────────────────────────────────────────────
# The claim is about lock contention, and lock hold times grow with the table — a bench
# against an empty DB would measure almost nothing. Bulk-load via `atuin import zsh`
# (~1.5 s for 20k rows); the same rows pushed through `atuin history start` one at a
# time is ~25 ms each, i.e. minutes, which would make a realistic seed impractical.
python3 - "$SB/.zsh_history" "$SEED" <<'PY'
import random, sys
# Extended-zsh-history format: ": <start>:<elapsed>;<command>". Deterministic seed so two
# runs of this script build the identical DB and their numbers stay comparable.
path, n = sys.argv[1], int(sys.argv[2])
rnd = random.Random(20250807)
verbs = ['git status', 'ls -la', 'cargo build --release', 'rg needle src/',
         'make audit', 'docker ps -a', 'kubectl get pods -n prod', 'nvim README.md']
with open(path, 'w') as fh:
    for i in range(n):
        fh.write(': %d:0;%s %d\n' % (1700000000 + i, rnd.choice(verbs), i))
PY
"${AT_ENV[@]}" "HISTFILE=$SB/.zsh_history" atuin import zsh >/dev/null 2>&1
DB="$SB/.local/share/atuin/history.db"
if [[ ! -s "$DB" ]]; then
  skip "atuin daemon bench skipped (seeding the history DB produced nothing)"
  exit 0
fi
# FOLD THE WAL BACK IN before anything snapshots this file. atuin opens SQLite in WAL
# mode, so a freshly-imported history.db is only half the story — the rest, INCLUDING the
# _sqlx_migrations rows, is in history.db-wal. Copying the main file alone (as db_reset
# does) yields a DB that looks seeded but reads as UN-MIGRATED, and then every writer
# races to apply the migrations at once and loses on
# `UNIQUE constraint failed: _sqlx_migrations.version`. That is a defect in the harness,
# not a property of atuin, and it would otherwise be measured as if it were one.
# Fold a database's WAL back into its main file. Only ever called where no daemon holds the
# file open — at seed time and inside db_reset — so it cannot contend with the process under
# measurement. (db_rows deliberately does NOT checkpoint, for exactly that reason.)
db_checkpoint() {
  python3 -c 'import sqlite3, sys
try:
    con = sqlite3.connect(sys.argv[1], timeout=30)
    con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    con.close()
except Exception:
    pass' "$1" 2>/dev/null
}
db_checkpoint "$DB"
rows="$(python3 -c 'import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute("select count(*) from history").fetchone()[0])' "$DB" 2>/dev/null)"
printf '   seeded: %s rows (%s)\n' "${rows:-?}" "$(du -h "$DB" | cut -f1)"

# history.db is NOT the only database atuin writes per command, and the other two are why
# this arm used to die. `atuin import` creates history.db and records.db; meta.db (and the
# `key` beside it) are created lazily by the FIRST `history end` — the error surfaces from
# atuin-client/src/meta.rs. The old warmup ran `history start` ALONE, so meta.db did not
# exist when the writers launched and all N of them raced to create and migrate it on their
# first `history end`, one losing on
# `UNIQUE constraint failed: UNIQUE constraint failed: _sqlx_migrations.version`.
#
# That aborted a writer at iteration 1 and cost the whole arm. Measured on HEAD: ~1 run in 8
# at 4 writers, and only ever the FIRST arm — because meta.db, once created, survived
# db_reset (which only ever removed history.db). A silently dropped arm is the cheap
# outcome; the expensive one is that it looked like a property of atuin under contention.
#
# So: run ONE COMPLETE pair here, serially, to bring the whole data dir into existence, then
# snapshot the DIRECTORY rather than the single file. Snapshotting all of it is also what
# finally delivers what the old comment only claimed — every arm starting from the same
# state. records.db grew monotonically across arms before this, so each arm was measured
# against a bigger sync store than the one before it, which is precisely the variable this
# is supposed to be controlling for.
_warm_id="$("${AT_ENV[@]}" "ATUIN_SESSION=$(printf '%032x' 0)" \
  atuin history start -- "bench-datadir-init" 2>/dev/null)"
[[ -n "$_warm_id" ]] &&
  "${AT_ENV[@]}" "ATUIN_SESSION=$(printf '%032x' 0)" \
    atuin history end --exit 0 "$_warm_id" >/dev/null 2>&1
DATADIR="$(dirname "$DB")"
SEEDDIR="$SB/seed-datadir"
for _d in "$DATADIR"/*.db; do db_checkpoint "$_d"; done
cp -a "$DATADIR" "$SEEDDIR"

# Row count as SQLite sees it RIGHT NOW, optionally filtered. Kept in a variable, not
# inlined, so scripts/test-core.sh can EXTRACT and execute this exact SQL against a
# synthetic table — the same "run it, don't pattern-match it" idiom Section J uses on the
# example unit's ExecStart. The trailing newline before the closing quote is what the
# extraction sed keys on; don't collapse it.
#
# Deliberately NO wal_checkpoint here, unlike the seeding step above: a reader on a WAL
# database already sees committed WAL frames, and asking for a checkpoint while the daemon
# still holds the file open would pick a lock fight with the very process just measured.
# (db_checkpoint serves a different purpose — making the data-dir SNAPSHOT self-contained,
# since a directory copy captures the main files as they are.) A plain read-write connect, not
# `mode=ro`: read-only access to a WAL DB needs a usable -shm, and a crashed writer can
# leave a -wal without one, which would fail the open and wrongly condemn a good arm.
# Any failure prints -1, which can only ever FAIL a comparison, never satisfy one.
ROWCOUNT_PY='import sqlite3, sys
try:
    con = sqlite3.connect(sys.argv[1], timeout=30)
    print(con.execute("select count(*) from history where " + sys.argv[2]).fetchone()[0])
    con.close()
except Exception:
    print(-1)
'
db_rows() { python3 -c "$ROWCOUNT_PY" "$DB" "${1:-1=1}" 2>/dev/null; }

# Rows present after db_reset (the seed plus its one warmup write), so an arm's expected
# delta is exactly WRITERS x ITERS. Set by db_reset; declared here for `set -u`.
BASE_ROWS=0
# Same, counting only FINISHED rows. atuin's model, verified against 18.19.0: `history
# start` inserts with duration = -1 and `history end` overwrites it with the real duration.
# db_reset's warmup runs a COMPLETE pair, so its row is finished by the time both baselines
# are taken — it sits inside each of them, and both expected deltas are therefore exactly
# WRITERS x ITERS.
BASE_DONE=0
# Whether the sentinel model above actually holds on the atuin in front of us. Confirmed
# per-run rather than assumed, so a future atuin that changes it degrades to "cannot check
# the end half" instead of failing every arm for the wrong reason.
DONE_CHECKABLE=0

# arm_wrote <expected-delta> <label> — THE STANDING RULE. An arm that expects a failed
# connect to cost time needs a row-count assertion or it reports a speedup for doing
# nothing. This is not hypothetical: with the daemon enabled and its socket unreachable,
# atuin 18.19.0 exits 0, prints a well-formed history id, writes nothing to stderr and
# DISCARDS the entry (atuinsh/atuin#3561 — 18.16.1 failed loudly; the silence is a
# REGRESSION). Every timing check upstream of here passes on that path, and the resulting
# table is the fastest one this script can print — for work that never happened.
#
# Sample counting cannot catch it, because the samples are real; only the DB can. So each
# arm is confirmed against the table itself before it is allowed into the results.
#
# Polls rather than reading once: when the daemon owns the writes, the last writer can
# return before the daemon has committed, and failing an arm for that would be a harness
# artefact. Bounded (~10 s) and fail-closed — a poll that never reaches the expected count
# refuses the arm exactly the way run_writers() refuses a short one.
# A third argument of `quiet` suppresses the success line (the autostart arm calls this
# once per rep and would otherwise print ten near-identical ✓s); failures always print.
arm_wrote() {
  local want="$1" label="$2" quiet="${3:-}" i got=0 done_got=0
  for ((i = 0; i < 100; i++)); do
    got=$(($(db_rows) - BASE_ROWS))
    ((got >= want)) && break
    sleep 0.1
  done
  # `!=`, not `<`: an OVERSHOOT is just as wrong as a shortfall — it means writes this arm
  # does not account for leaked in, so the timings no longer describe the rows that landed,
  # or atuin's per-command row model changed and the expectation below is stale. Either way
  # the honest move is to refuse, and the message names which.
  if ((got != want)); then
    if ((got > want)); then
      printf '   %s✗%s %s: the DB grew by %s rows for %s samples — MORE than expected.\n' \
        "$c_red" "$c_rst" "$label" "$got" "$want" >&2
      printf "     atuin's per-command row model may have changed; revisit the expected-row\n" >&2
      printf '     formula in this script. Not reporting this arm.\n' >&2
    else
      printf '   %s✗%s %s: the DB grew by %s rows for %s samples — the writers reported\n' \
        "$c_red" "$c_rst" "$label" "$got" "$want" >&2
      printf '     success but atuin did not persist. This is the silent-discard shape:\n' >&2
      printf '     with the daemon enabled and unreachable atuin exits 0, prints a valid\n' >&2
      printf '     history id and drops the entry (atuinsh/atuin#3561). Not reporting it.\n' >&2
    fi
    return 1
  fi
  # The count above only proves `history start` landed — `end` UPDATES that row rather than
  # inserting one, so an atuin silently discarding every `end` would sail through it. Check
  # the finished-row delta too, but only where the sentinel model was confirmed for this
  # build (see DONE_CHECKABLE): binding when we know the schema, a note when we don't.
  if ((DONE_CHECKABLE)); then
    for ((i = 0; i < 100; i++)); do
      done_got=$(($(db_rows 'duration >= 0') - BASE_DONE))
      ((done_got >= want)) && break
      sleep 0.1
    done
    if ((done_got != want)); then
      printf '   %s✗%s %s: %s/%s rows were FINISHED (duration filled in). The `history\n' \
        "$c_red" "$c_rst" "$label" "$done_got" "$want" >&2
      printf '     end` half did not land even though the rows exist. Not reporting it.\n' >&2
      return 1
    fi
  fi
  [[ "$quiet" == quiet ]] ||
    printf '   %s✓%s %s rows landed: %s/%s%s\n' "$c_grn" "$c_rst" "$label" "$got" "$want" \
      "$( ((DONE_CHECKABLE)) && printf ' (all finished)' || printf ' (end-half uncheckable)')"
  return 0
}

db_reset() {
  # Restore the WHOLE data dir, not just history.db — see the snapshot comment above.
  rm -rf "$DATADIR"
  cp -a "$SEEDDIR" "$DATADIR"
  # One SERIAL pair before the concurrent ones — a COMPLETE pair, `start` then `end`.
  # Whatever a first-open still has to do (WAL re-creation, migration bookkeeping in any of
  # the three databases) then happens once, in a single process, instead of being raced N
  # ways by the writers — which is a property of a cold data dir, not of the daemon, and
  # would otherwise land inside the measurement or abort a writer outright.
  local warm_id
  warm_id="$("${AT_ENV[@]}" "ATUIN_SESSION=$(printf '%032x' 0)" \
    atuin history start -- "bench-warmup" 2>/dev/null)"
  # SELF-CALIBRATE the sentinel model on the atuin actually in front of us, in the one
  # window where it is observable: `start` has run and `end` has not, so exactly one row
  # must be unfinished. If that holds, the end-half check in arm_wrote is binding for this
  # run; if it doesn't, atuin's schema is not what this script believes and the check stands
  # down rather than failing every arm on a wrong assumption. Fail-open ONLY here, where the
  # schema is genuinely unknown — everywhere else the rule binds.
  if [[ -n "$warm_id" && "$(db_rows 'duration < 0')" == 1 ]]; then
    DONE_CHECKABLE=1
  else
    DONE_CHECKABLE=0
  fi
  [[ -n "$warm_id" ]] &&
    "${AT_ENV[@]}" "ATUIN_SESSION=$(printf '%032x' 0)" \
      atuin history end --exit 0 "$warm_id" >/dev/null 2>&1
  # Fold the warmup's WAL back in before the writers open the files, so they start from a
  # self-contained main DB. Safe here because db_reset always runs with NO daemon live
  # (arm 2 resets before daemon_start; arm 3 calls daemon_stop first).
  local d
  for d in "$DATADIR"/*.db; do db_checkpoint "$d"; done
  # AFTER the complete warmup pair, so the baselines include it and each arm's expected
  # delta is exactly WRITERS x ITERS on BOTH counts.
  BASE_ROWS="$(db_rows)"
  BASE_DONE="$(db_rows 'duration >= 0')"
  # A baseline that failed to read poisons every delta after it, so refuse outright rather
  # than measure against garbage.
  # A baseline that failed to read poisons every delta after it. Note that EVERY call site
  # must gate on this status — a `return 1` nothing checks is not a fail-closed check, it is
  # a comment.
  if ((BASE_ROWS < 0)) || ((BASE_DONE < 0)); then
    printf '   %s✗%s could not read a row-count baseline from %s\n' \
      "$c_red" "$c_rst" "$DB" >&2
    return 1
  fi
  return 0
}

# ── the writer ────────────────────────────────────────────────────────────────
# One process per simulated pane, timing the pair a real shell hook calls. zsh, not bash:
# $EPOCHREALTIME (zsh/datetime) gives sub-ms wall time with no fork, the same way
# bench-core.sh --profile attributes per-module cost.
#
# ATUIN_SESSION is set per writer because a real shell has one (atuin init exports it) and
# distinct sessions are what distinct tmux panes look like to atuin.
#
# A FAILED call must never be recorded as a fast one. `atuin history start` against a dead
# daemon errors in a millisecond, and timing that would produce a beautiful low-latency
# table for work that never happened — the most dangerous possible output from a benchmark,
# because it looks like the result you were hoping for. So each command's status is
# checked, the writer aborts on the first failure, and the caller below refuses any arm
# that did not return exactly WRITERS x ITERS samples.
# THE INTERMEDIATE TIMESTAMP IS THE POINT. `start` is what the prompt blocks on; `end` is
# backgrounded by the real hook. Timing only the outer span — which is what this did until
# the split — cannot separate them afterwards, so every arm has to take t1 as it goes.
# Two columns per line, `start_ms pair_ms`, one line per iteration (run_writers counts
# lines, so the sample-count rule is unaffected).
cat >"$SB/writer.zsh" <<'ZSH'
zmodload zsh/datetime
typeset -F t0 t1 t2
typeset out=$1 iters=$2 tag=$3 id
: >| $out
for i in {1..$iters}; do
  t0=$EPOCHREALTIME
  if ! id=$(atuin history start -- "bench-$tag-$i --flag value" 2>/dev/null) || [[ -z $id ]]; then
    print -ru2 -- "writer $tag: 'history start' failed at iteration $i"
    exit 1
  fi
  t1=$EPOCHREALTIME
  if ! atuin history end --exit 0 $id >/dev/null 2>&1; then
    print -ru2 -- "writer $tag: 'history end' failed at iteration $i"
    exit 1
  fi
  t2=$EPOCHREALTIME
  printf '%.6f %.6f\n' $(( (t1 - t0) * 1000 )) $(( (t2 - t0) * 1000 )) >> $out
done
ZSH

# run_writers <outdir> [extra env assignments...] — fan out $WRITERS concurrent writers
# and wait for all of them. Contention is the point, so they must overlap.
#
# Returns non-zero if ANY writer failed or the arm came up short of
# WRITERS x ITERS samples, so the caller can refuse to report a partial arm rather than
# quietly average whatever survived.
run_writers() {
  local outdir="$1"
  shift
  mkdir -p "$outdir"
  local w pids=() rc=0
  for ((w = 1; w <= WRITERS; w++)); do
    "${AT_ENV[@]}" "$@" "ATUIN_SESSION=$(printf '%032x' "$w")" \
      zsh "$SB/writer.zsh" "$outdir/$w.txt" "$ITERS" "$w" >>"$SB/writer.log" 2>&1 &
    pids+=("$!")
  done
  for w in "${pids[@]}"; do wait "$w" || rc=1; done
  local want=$((WRITERS * ITERS)) got
  got="$(cat "$outdir"/*.txt 2>/dev/null | grep -c .)"
  if ((rc != 0)) || [[ "$got" != "$want" ]]; then
    printf '   %s✗%s arm incomplete: %s/%s samples — not reporting it (see %s)\n' \
      "$c_red" "$c_rst" "${got:-0}" "$want" "$SB/writer.log" >&2
    return 1
  fi
  return 0
}

daemon_start() {
  ((SYSTEMD)) && {
    unit_start
    return
  }
  "${AT_ENV[@]}" ATUIN_DAEMON__ENABLED=true atuin daemon start >"$SB/daemon.log" 2>&1 &
  DAEMON_PID=$!
  local i
  for ((i = 0; i < 100; i++)); do
    [[ -S "$SOCK" ]] && return 0
    sleep 0.1
  done
  return 1
}

# Start the daemon from a sandbox-scoped TRANSIENT unit. Two deliberate departures from the
# shipped examples/atuin-daemon.service, both because a bench is not a deployment:
#
#   · a UNIQUE unit name. A fixed `atbench-daemon` collides with a concurrent run and with a
#     leftover failed unit from a crashed one ("Unit ... already exists"), which would turn
#     one earlier crash into a permanent skip. The atbench- prefix keeps it unmistakably ours
#     and unmistakably not the user's atuin-daemon.service, which is the actual requirement.
#   · Restart=no, where the shipped unit uses Restart=on-failure/RestartSec=3. Fidelity would
#     be actively harmful here: a daemon that dies mid-arm and is silently restarted three
#     seconds later yields an arm whose samples straddle two daemons and a gap, reported as
#     one number. Restart=no makes a mid-arm death visible, and the row rule catches it
#     independently.
#
# The control-plane calls (systemd-run, systemctl) must run in OUR environment, because
# reaching the user bus needs the real XDG_RUNTIME_DIR/DBUS_SESSION_BUS_ADDRESS. Only the
# DAEMON gets the sandbox values, via --setenv. Conflating the two is the easy mistake here:
# it would either fail to find the bus, or point a real daemon at the sandbox.
unit_start() {
  UNIT="atbench-daemon-${LOCALDIR##*.}"
  local atuin_bin env_bin i
  # A unit inherits none of our PATH, so resolve both binaries to absolute paths here.
  atuin_bin="$(command -v atuin)"
  env_bin="$(command -v env)"
  local sdrun=(
    systemd-run --user --quiet --collect --unit="$UNIT"
    --description='atuin daemon (bench sandbox — transient, not your real unit)'
    --property=Restart=no --property=TimeoutStopSec=5
  )
  # The payload runs under `env -i "${AT_VARS[@]}"`, NOT via a list of --setenv flags.
  # --setenv only ADDS or OVERRIDES: the unit still inherits the user manager's whole
  # environment, so anything AT_VARS does not happen to name — ATUIN_CONFIG_DIR,
  # ATUIN_DAEMON__SOCKET_PATH, a stray ATUIN_DB_PATH — reaches the daemon and can point it
  # at the developer's real files. That is the same non-hermeticity `env -i` exists to
  # prevent for the writers, and it is worse here, because this process is the one doing
  # the writing. systemd-run itself still runs in OUR environment: it needs the real
  # XDG_RUNTIME_DIR/DBUS_SESSION_BUS_ADDRESS to reach the bus. Only the payload is scrubbed.
  sdrun+=(-- "$env_bin" -i "${AT_VARS[@]}" ATUIN_DAEMON__ENABLED=true "$atuin_bin" daemon start)
  "${sdrun[@]}" >"$SB/daemon.log" 2>&1 || return 1
  for ((i = 0; i < 100; i++)); do
    [[ -S "$SOCK" ]] && return 0
    sleep 0.1
  done
  return 1
}

# A5 — the unit systemd thinks it started must be the process actually holding the socket.
# Pure procfs, so no dependency on ss/lsof: field 6 of /proc/net/unix is the state (01 =
# LISTEN), field 7 the SOCKET inode (not the filesystem inode — for AF_UNIX they differ, and
# `stat -c %i` gives the wrong one), and the last field the path.
#
# FAIL CLOSED, WITHOUT EXCEPTION: the arm is reported only when MainPID is positively shown
# to hold the listening socket. Every other outcome — mismatch, no LISTEN entry, no MainPID,
# no procfs, an unreadable fd table — refuses it.
#
# There WAS a carve-out here for an unreadable /proc/net/unix, on the reasoning that a
# missing capability is not a finding and this script's contract is that missing tools skip
# rather than fail. It is gone, for two reasons. It defended a state the mode cannot reach:
# --systemd only gets past its preflight when a systemd USER BUS answers, which means Linux
# with a mounted /proc, so "has a user manager but no readable /proc/net/unix" is very nearly
# impossible. And it was the single remaining route by which this harness could print a
# systemd latency number that nothing had verified — the exact shape of unearned claim the
# whole exercise exists to remove. A mode that cannot prove what it measured should decline
# to measure, not annotate.
#
# Because every branch now refuses, the ONLY thing distinguishing them is the message, so
# each one has to name the real cause — see the fd-table case below.
unit_owns_socket() {
  local mainpid ino fd
  mainpid="$(systemctl --user show -p MainPID --value "$UNIT" 2>/dev/null)"
  [[ -n "$mainpid" && "$mainpid" != 0 ]] || {
    printf '   %s✗%s unit %s reports no MainPID\n' "$c_red" "$c_rst" "$UNIT" >&2
    return 1
  }
  [[ -r /proc/net/unix ]] || {
    printf '   %s✗%s cannot read /proc/net/unix — unit↔socket ownership is unprovable here,\n' \
      "$c_red" "$c_rst" >&2
    printf '     so this arm is not reported rather than reported unverified\n' >&2
    return 1
  }
  ino="$(awk -v p="$SOCK" '$6=="01" && $NF==p {print $7; exit}' /proc/net/unix 2>/dev/null)"
  [[ -n "$ino" ]] || {
    printf '   %s✗%s no LISTEN entry for %s, though the socket exists — nothing is serving it\n' \
      "$c_red" "$c_rst" "$SOCK" >&2
    return 1
  }
  # An unreadable or absent fd table would otherwise fall through to the "something else is
  # listening" verdict below — a refusal for a WRONG stated reason, because the glob stays
  # literal and every readlink comes back empty. Both outcomes refuse; only one of them is
  # true, and a benchmark that misreports why it refused is a benchmark that gets debugged in
  # the wrong place.
  [[ -r "/proc/$mainpid/fd" ]] || {
    printf '   %s✗%s cannot read /proc/%s/fd — cannot prove the unit holds the socket\n' \
      "$c_red" "$c_rst" "$mainpid" >&2
    return 1
  }
  for fd in "/proc/$mainpid/fd"/*; do
    [[ "$(readlink "$fd" 2>/dev/null)" == "socket:[$ino]" ]] && {
      printf '   %s✓%s unit MainPID %s owns the listening socket\n' \
        "$c_grn" "$c_rst" "$mainpid"
      return 0
    }
  done
  printf '   %s✗%s unit MainPID %s does NOT hold %s — something else is listening\n' \
    "$c_red" "$c_rst" "$mainpid" "$SOCK" >&2
  return 1
}
# (daemon_stop is defined up with cleanup — it must exist before the EXIT trap can fire.)

# ── arm 1: daemon OFF (Core's shipped default) ────────────────────────────────
# This arm MUST precede any daemon start. A4 is right that it needs no special handling, but
# only because of that ordering: a live daemon holding a second SQLite connection against the
# same file would inflate the direct writers and make the off arm look worse than it is.
# That property is load-bearing and otherwise invisible — do not reorder the arms.
printf '\n%s-- arm: daemon OFF (direct SQLite writes) --%s\n' "$c_blu" "$c_rst"
OFF_OK=0
db_reset &&
  run_writers "$SB/off" && arm_wrote "$((WRITERS * ITERS))" "daemon off" && OFF_OK=1

# ── arm 2: daemon ON, already running (the supervised shape) ──────────────────
printf '%s-- arm: daemon ON (writes via the unix socket) --%s\n' "$c_blu" "$c_rst"
DAEMON_OK=0
if db_reset && daemon_start; then
  # The socket-path agreement check the behavioral suite cannot make: atuin must bind the
  # SAME path _core_atuin_daemon_guard probes. If these ever diverge, the guard silently
  # probes a path nothing listens on and disables the daemon on every shell of a machine
  # that correctly opted in. WHICH claim is available depends on the mode, so branch rather
  # than print one that isn't true.
  if [[ -n "$SOCK_FORCED" ]]; then
    # Withdraw the claim rather than weaken it. The guard's expression reads
    # ${ATUIN_DAEMON__SOCKET_PATH:-...} FIRST, so with the override in play the two agree by
    # construction and the interesting default-resolution branch goes untested. Printing a ✓
    # here would be the most quotable false claim this script could make.
    printf '   –  socket-path agreement NOT asserted this run: ATUIN_DAEMON__SOCKET_PATH was\n'
    printf '      forced, and the guard honours that same variable first, so agreement here\n'
    printf '      is by construction and proves nothing.\n'
  elif ((SYSTEMD)); then
    printf '   %s✓%s socket-path agreement: atuin bound %s\n' "$c_grn" "$c_rst" "$SOCK"
    # shellcheck disable=SC2016
    printf '     %s\n' \
      '(= $XDG_RUNTIME_DIR/atuin.sock — the FIRST branch of the expression' \
      ' _core_atuin_daemon_guard resolves, the one the default mode cannot reach)'
  else
    printf '   %s✓%s socket-path agreement: atuin bound %s\n' "$c_grn" "$c_rst" \
      "${SOCK/#"$SB"/\$HOME}"
    # The ${...} below is QUOTED PROSE — the guard's expression reproduced verbatim so the
    # two can be compared by eye. Expanding it here would print this sandbox's path twice.
    # shellcheck disable=SC2016
    printf '     %s\n' \
      '(= ${XDG_DATA_HOME:-$HOME/.local/share}/atuin/atuin.sock — the expression' \
      ' _core_atuin_daemon_guard resolves in zsh/00-tools.zsh)'
  fi
  # Ownership is a property of the MODE, not of which socket-agreement claim was printable,
  # so it runs whenever a unit is supervising the daemon. Hanging it off the `elif` above
  # meant CORE_ATBENCH_BASE + --systemd took the first branch and silently skipped the
  # MainPID assertion — the two modes are documented as composable, so that combination has
  # to keep the invariant the flag advertises.
  ((SYSTEMD)) && { unit_owns_socket || DAEMON_FAIL=1; }
  # The row check matters MOST on this arm: it is the one where a dead-or-wedged socket
  # produces fast, plausible, entirely fictional numbers.
  ((${DAEMON_FAIL:-0})) ||
    { run_writers "$SB/on" ATUIN_DAEMON__ENABLED=true &&
      arm_wrote "$((WRITERS * ITERS))" "daemon on" && DAEMON_OK=1; }
else
  printf '   %s✗%s daemon did not come up — see %s\n' "$c_red" "$c_rst" "$SB/daemon.log"
  sed 's/^/     /' "$SB/daemon.log" 2>/dev/null
  # Under a unit the daemon's own output goes to the journal, not that file, so the log
  # above is usually empty and the real reason is one command away.
  if ((SYSTEMD)) && [[ -n "$UNIT" ]]; then
    systemctl --user status "$UNIT" --no-pager 2>&1 | sed 's/^/     /'
    journalctl --user -u "$UNIT" -n 50 --no-pager 2>&1 | sed 's/^/     /'
    printf '     (a non-persistent user journal may show nothing here)\n'
  fi
fi

# ── arm 3: autostart, FIRST command in a fresh shell (the Alpine-only cost) ────
# Where nothing supervises the daemon, atuin spawns it itself — so the first command
# after a cold boot pays for that spawn and every later one does not. The Alpine issue
# singled this out, and it is invisible to the two arms above (both measure steady
# state). Each rep is a genuinely cold start: daemon stopped, socket removed.
#
# Skipped entirely under --systemd, and not merely as tidiness: with the unit running an
# autostart arm just reconnects to it and measures nothing new, and with the unit stopped it
# measures the NO-SYSTEMD path and would print it under a systemd heading. Both outcomes are
# the failure this mode exists to prevent. The two are also mutually exclusive by design —
# the guard itself returns early when ATUIN_DAEMON__AUTOSTART is truthy.
if ((SYSTEMD)); then
  printf '%s-- arm: autostart — SKIPPED in --systemd mode --%s\n' "$c_blu" "$c_rst"
  printf '   autostart and a supervised unit are mutually exclusive; run without --systemd\n'
  printf '   for that number.\n'
  FIRST_REPS=0
  mkdir -p "$SB/first"
  : >"$SB/first/first.txt"
  : >"$SB/first/steady.txt"
else
printf '%s-- arm: autostart, FIRST command in a fresh shell (%s reps) --%s\n' \
  "$c_blu" "$REPS" "$c_rst"
daemon_stop
mkdir -p "$SB/first"
: >"$SB/first/first.txt"
: >"$SB/first/steady.txt"
FIRST_REPS=0
for ((r = 1; r <= REPS; r++)); do
  # Stop the daemon this rep's predecessor autostarted BEFORE resetting the DB — swapping
  # the file out from under a live daemon is not a cold start, it is a corrupt one. Via
  # the socket, never `pkill`: the process-wide pattern would reach the real daemon a
  # developer's own shells are using.
  daemon_stop
  db_reset || continue
  # iters=6: line 1 is the cold first command (it pays the spawn), lines 2-6 are the
  # steady state immediately after — same process topology, so the delta IS the spawn.
  # The row check is not optional here either — and this arm is the likeliest to need it,
  # because autostart is the path where nothing but atuin itself guarantees a daemon is
  # listening. A rep whose six rows did not land is dropped rather than averaged in.
  "${AT_ENV[@]}" ATUIN_DAEMON__ENABLED=true ATUIN_DAEMON__AUTOSTART=true \
    "ATUIN_SESSION=$(printf '%032x' "$((900 + r))")" \
    zsh "$SB/writer.zsh" "$SB/first/rep$r.txt" 6 "first$r" >>"$SB/writer.log" 2>&1 &&
    arm_wrote 6 "autostart rep $r" quiet &&
    {
      FIRST_REPS=$((FIRST_REPS + 1))
      head -1 "$SB/first/rep$r.txt" >>"$SB/first/first.txt" 2>/dev/null
      tail -n +2 "$SB/first/rep$r.txt" >>"$SB/first/steady.txt" 2>/dev/null
    }
done
daemon_stop
# Say so when reps were dropped. Silently reporting 4 reps under a "(10 reps)" heading is
# the same class of error the row rule exists to prevent.
if ((FIRST_REPS != REPS)); then
  printf '   %s✗%s only %s/%s reps wrote their rows — the rest are excluded\n' \
    "$c_red" "$c_rst" "$FIRST_REPS" "$REPS" >&2
fi
fi

# ── results ───────────────────────────────────────────────────────────────────
# Percentiles, not a mean: the daemon is adopted for the TAIL, and a mean hides exactly
# the lock-wait spikes that motivate it.
printf '\n%s== results (ms per command) ==%s\n' "$c_blu" "$c_rst"
ON_LABEL="daemon on"
((SYSTEMD)) && ON_LABEL="daemon on (systemd unit) [UNVALIDATED]"
[[ -n "$SOCK_FORCED" ]] && ON_LABEL="$ON_LABEL (socket forced)"
# No "(ownership unverified)" variant any more: unit_owns_socket refuses the arm outright
# rather than letting an unproven one through with a caveat on the label, so that state
# cannot reach this table.
python3 - "$SB" "$OFF_OK" "$DAEMON_OK" "$ON_LABEL" <<'PY'
import glob, math, os, sys

sb, off_ok, daemon_ok = sys.argv[1], sys.argv[2] == '1', sys.argv[3] == '1'

def load(pattern):
    """-> (latency, total), each sorted. Column 0 is `history start` ALONE — the call
    atuin's _atuin_preexec blocks the prompt on. Column 1 is start+end, which
    _atuin_precmd backgrounds. Both come back from ONE pass so the two tables are the
    same samples, and so a malformed file is reported once rather than per-table."""
    lat, tot, bad = [], [], 0
    for path in sorted(glob.glob(pattern)):
        with open(path) as fh:
            for line in fh:
                if not line.strip():
                    continue
                parts = line.split()
                # Fail closed on a malformed line rather than coercing whatever is there.
                # The pre-split parser split the WHOLE file on whitespace, so two-column
                # input would have been read as twice as many single samples — silently
                # interleaving the two metrics into one distribution and printing a table
                # that looks entirely normal. Refusing the arm is the only safe response.
                if len(parts) != 2:
                    bad += 1
                    continue
                lat.append(float(parts[0]))
                tot.append(float(parts[1]))
    if bad:
        print('  !! %d malformed sample line(s) under %s — arm refused' % (bad, pattern))
        return [], []
    return sorted(lat), sorted(tot)

def pct(xs, p):
    # Nearest-rank, ceil(p/100 * n) — always a value that was actually observed, and no
    # interpolation choice to argue about. NOT round(p/100*n + 0.5): Python rounds halves
    # to even, so an exact .5 rank (n=10 at p50, n=50 at p50 — both of which the autostart
    # arm hits by default) picked the rank ABOVE and biased the reported spawn cost upward.
    return xs[min(len(xs) - 1, max(0, math.ceil(p / 100.0 * len(xs)) - 1))]

def row(label, xs, width=18):
    if not xs:
        print('  %-*s %s' % (width, label, '(no samples)'))
        return
    print('  %-*s %7d %9.2f %9.2f %9.2f %9.2f %9.2f' % (
        width, label, len(xs), sum(xs) / len(xs),
        pct(xs, 50), pct(xs, 95), pct(xs, 99), xs[-1]))

# An arm that did not complete is dropped entirely rather than reported short: a
# half-populated latency table is indistinguishable from a real one once it is quoted.
off_lat, off_tot = load(os.path.join(sb, 'off', '*.txt')) if off_ok else ([], [])
on_lat, on_tot = load(os.path.join(sb, 'on', '*.txt')) if daemon_ok else ([], [])

# The arm LABEL is where the caveats have to live, because the table is what gets pasted
# into an issue and every other marker in this script is upstream of the copy buffer.
on_label = sys.argv[4]
w = max(18, len(on_label))


def table(heading, note, off, on):
    print()
    print('  %s' % heading)
    for line in note:
        print('  %s' % line)
    print()
    print('  %-*s %7s %9s %9s %9s %9s %9s'
          % (w, 'arm', 'n', 'mean', 'p50', 'p95', 'p99', 'max'))
    print('  ' + '-' * (74 + w - 18))
    row('daemon off', off, w)
    row(on_label, on, w)
    if off and on:
        print()
        for name, p in (('p50', 50), ('p95', 95), ('p99', 99)):
            a, b = pct(off, p), pct(on, p)
            # Report the direction honestly. The daemon is SUPPOSED to win on the tail; if
            # it does not, that is the finding, and dressing it up would defeat the point
            # of measuring at all.
            verb = 'faster' if b < a else 'SLOWER'
            print('  %-4s  off %8.2f ms -> on %8.2f ms   (%.2fx %s with the daemon)'
                  % (name, a, b, (a / b if b else 0) if b < a else (b / a if a else 0), verb))


# Latency first, deliberately: it is the metric the adoption argument is about, so it is
# the one that should be under the cursor when someone copies a table out of here.
table('PROMPT LATENCY — `atuin history start` only.',
      ['The call the shell BLOCKS on (_atuin_preexec takes it in a command',
       'substitution). This is the only table that may be quoted as per-command',
       'latency — the time a human actually waits at the prompt.'],
      off_lat, on_lat)

table('TOTAL WRITE WORK — `history start` + `history end`.',
      ['_atuin_precmd fires `end` into a detached background subshell, so this is',
       'load on the box, NOT time at the prompt. Real, and worth watching for DB',
       'contention — but quoting it as latency is what produced this repo\'s',
       'contradictory tail results.'],
      off_tot, on_tot)

first, first_tot = load(os.path.join(sb, 'first', 'first.txt'))
steady, steady_tot = load(os.path.join(sb, 'first', 'steady.txt'))
if first:
    print()
    print('  autostart path — the cost unique to a machine with no service manager:')
    print('  (prompt latency — the spawn is paid on the blocking `start` call)')
    print('  %-18s %7s %9s %9s %9s %9s %9s' % ('', 'n', 'mean', 'p50', 'p95', 'p99', 'max'))
    row('first command', first)
    row('then steady', steady)
    if steady:
        print()
        print('  the spawn costs the first command %+.2f ms vs steady state (p50)'
              % (pct(first, 50) - pct(steady, 50)))
        if first_tot and steady_tot:
            print('  (%+.2f ms measured as total write work — same samples, both calls)'
                  % (pct(first_tot, 50) - pct(steady_tot, 50)))
PY

# The caveats have to describe THIS run, not the run that happened to be done first.
# `make bench-atuin` is runnable on macOS, on musl, and on a systemd host, so hardcoding
# "a glibc container" would eventually stamp that label on a run where it is simply false
# — the precise kind of unearned claim this whole exercise exists to remove. Detect and
# report what is actually true here; only the socket topology is enforced by the script.
host_os="$(uname -s 2>/dev/null || echo unknown)"
host_arch="$(uname -m 2>/dev/null || echo unknown)"
# Capture ldd's output and MATCH ON THE STRING rather than piping into grep. The pipe form
# could never detect musl: `set -o pipefail` is in force at the top of this script, musl's
# ldd exits NON-ZERO after printing its banner, and pipefail then fails the whole pipeline
# even though grep matched. So every musl run reported "unknown libc" AND went on to list
# musl among the things it had not covered — on the one run where that was false. The `|| true`
# is load-bearing for exactly that reason, not defensive habit.
host_libc="unknown libc"
_ldd_out=""
have ldd && _ldd_out="$(ldd --version 2>&1 || true)"
case "$_ldd_out" in
*[Mm]usl*) host_libc="musl" ;;
*GLIBC* | *[Gg]libc* | *"GNU libc"*) host_libc="glibc" ;;
*) [[ "$host_os" == Darwin ]] && host_libc="Darwin libc" ;;
esac
if ((SYSTEMD)); then
  host_init="systemd user manager; measured THROUGH a transient unit ($UNIT)"
elif [[ -d /run/systemd/system ]]; then
  host_init="systemd present (but unused: this run never takes the unit path)"
else
  host_init="no systemd"
fi

# What the socket topology actually was — the old text asserted "XDG_RUNTIME_DIR is unset",
# which BOTH new modes falsify.
if ((SYSTEMD)); then
  topology="XDG_RUNTIME_DIR was pointed at $RUNDIR (mode 0700) — deliberately not your real
runtime dir — so atuin resolved its default runtime-dir socket inside the sandbox, and no
real daemon could be reached, started or stopped."
elif [[ -n "$SOCK_FORCED" ]]; then
  topology="the socket was FORCED to $SOCK_FORCED via ATUIN_DAEMON__SOCKET_PATH, because the
sandbox HOME is under $BASE and AF_UNIX cannot live there. Default socket resolution was
therefore not under test."
else
  topology="the socket topology is the one thing this script ENFORCES — an empty environment,
so XDG_RUNTIME_DIR is unset and atuin must use the data-dir socket."
fi

# Built as a list rather than one sentence with inline conditionals: with musl, systemd and
# the network home all independently coverable, the inline form became unreadable and, worse,
# could not stop claiming things a given run had actually covered.
notcovered=("any real multi-pane session on real hardware")
((SYSTEMD)) || notcovered+=("the systemd-unit path")
[[ -n "$BASE" ]] || notcovered+=("a network home (where the contention claim is strongest)")
[[ "$host_libc" == musl ]] || notcovered+=("musl")
# One per line: the joined sentence ran well past any sane width once three of the four
# entries could be present at once.
notcovered_str="$(printf '\n  · %s' "${notcovered[@]}")"

cat <<EOF

Measured on: $host_os/$host_arch, $host_libc, $host_init, atuin $(atuin --version 2>/dev/null |
  awk '{print $2}')$([[ -n "$BASE" ]] && printf ', history DB on %s at %s' "$(fs_type "$SB")" "$BASE").
For this run, $topology

$(printf '%s' "$c_yel")These numbers narrow the gap; they do not close it.$(printf '%s' "$c_rst") Whatever this host is, the
run did not cover:$notcovered_str
$( ((SYSTEMD)) && printf '\n%s\n' "UNVALIDATED-SYSTEMD: --systemd itself has never been validated against a real systemd
user bus. If this run produced numbers, it is the first — check that the unit stayed active
for the whole arm, that MainPID owned the socket, and that the row deltas were exact, before
treating any figure here as data.")

Run it twice before believing the tail. p50 and p95 settle quickly; p99 and max are
the last to, and a single run's p99 can flip sign. If two runs disagree on a
percentile, that percentile is noise — report it as unresolved, not as a result.

Quote the PROMPT LATENCY table when the claim is about what a command costs the user.
The TOTAL WRITE WORK table includes \`history end\`, which the shell hook backgrounds —
real load, but nobody waits for it. Say which table a number came from.
EOF
