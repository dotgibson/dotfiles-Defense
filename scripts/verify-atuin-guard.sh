#!/usr/bin/env bash
# scripts/verify-atuin-guard.sh
# ──────────────────────────────────────────────────────────────────────────────
# _core_atuin_daemon_guard (zsh/00-tools.zsh) is not a preference. It is a workaround for
# ONE measured upstream fact: on atuin 18.19.0, with the daemon enabled and its socket
# absent or stale, `atuin history start` exits 0, prints a well-formed history id, writes
# nothing to stderr — and DISCARDS the entry (atuinsh/atuin#3561). A persistent precmd
# hook, a throttled connect(2) on the prompt path, and a one-way degrade in every
# interactive shell across nine repos are ALL justified by that single fact. Nothing else.
#
# The fact has already moved once, in the direction that makes it harder to notice (18.16.1
# failed LOUDLY — an empty ATUIN_HISTORY_ID, which then crashed `history end`). So it can
# move again, and until this script nothing watched: atuin is not pinned in mise/config.toml,
# has no renovate.json entry, and /tool-scout's allowed-tools carry no Bash, so it can
# compare version NUMBERS and never measure. This measures.
#
# TWO PREMISES, ONE PER RUN (dotgibson/dotfiles-core#402). The guard rests on a second
# upstream fact that the paragraphs above do not describe: under ATUIN_DAEMON__AUTOSTART it
# STANDS DOWN ENTIRELY — unhooks itself from precmd_functions and never probes — because atuin
# is supposed to supervise its own daemon there, making an absent socket a cue to start one
# rather than a fault. That covers Alpine and macOS, two of the eight machines, and on those
# two it is the ONLY mitigation. `--premise autostart` measures it.
#
# It is a separate MODE rather than four more arms bolted onto the matrix, for four reasons:
#
#   1. Different remedy, different title. A discard finding says "retire, version-gate or
#      reshape the guard". An autostart finding says something else entirely — and the naive
#      reading of it ("stop standing down") is actively harmful, because the degrade path
#      exports ATUIN_DAEMON__ENABLED=false, which under autostart deletes the spawn and
#      permanently defeats the only launcher those two machines have. One premise, one
#      verdict, one issue title, or a reader acts on prose written for the other one.
#   2. No control arm for a spawn. Every other arm here observes; this one has to CAUSE
#      something. "autostart did not spawn a daemon" and "this box cannot host a daemon" are
#      the same observation, so a MANUAL-spawn control has to run first and prove the box
#      before anything about upstream can be claimed.
#   3. Teardown is the hard part. atuin spawns a daemon whose PID this script never learns, so
#      cleanup goes through `atuin daemon stop` — a spelling upstream has already moved once
#      (#380) — and a stop that silently failed would leave a daemon writing into a tree the
#      EXIT trap is about to rm -rf.
#   4. The default target must stay laptop-safe. `make verify-atuin-guard` starts no
#      background process, and it must keep not doing so, which is why autostart is opt-in
#      with its own target rather than a widened default.
#
# THREE VERDICTS, NEVER TWO. The two-verdict version of this check is the one that already
# shipped and was wrong, so the third is the whole point:
#
#   holds         BOTH control arms wrote exactly one row, and BOTH unreachable shapes gave
#                 rc 0, an id on stdout, empty stderr, and a row delta of exactly 0. The
#                 guard still earns its place on every prompt in the fleet.
#   moved         the control arms wrote, and something about an unreachable shape is now
#                 different — or the closing control wrote MORE than one row, meaning the
#                 unreachable entries were spooled and replayed rather than discarded.
#                 zsh/00-tools.zsh's rationale block is OVERCLAIMING, and the guard needs
#                 retiring, version-gating or reshaping — a human decision, weighed as an
#                 eight-repo change.
#   unmeasurable  the apparatus could not be trusted: no atuin, no python3, the anchor could
#                 not be read, the sandbox could not be built, the row count came back -1,
#                 unreachability could not be PROVEN, or either control arm did not write.
#                 This is NOT `holds`. A detector that quietly stops detecting is
#                 indistinguishable from good news, and that is the failure this exists to
#                 prevent — so declining is a first-class outcome with its own exit code.
#
# WHY A CONTROL ARM. "The row count did not go up" is the same observation whether atuin
# discarded the write or the apparatus never wrote anything. The earlier copy-paste recipe
# conflated exactly those two: it seeded its DB with the daemon already enabled and
# unreachable, so on a build that discards, the DB was never created, the row count fell
# back to 0, and it printed the premise-holds signature from an apparatus that had never
# written a row. It was right by luck. So here a daemon-OFF write runs FIRST and must land
# exactly one row; if it cannot, nothing observed afterwards means anything.
#
# WHY A SECOND ONE, AT THE END. The opening control proves the apparatus at t=0 only, and an
# apparatus can stop writing MID-RUN — a DB that goes unwritable still READS fine, so the
# -1 sentinel never fires and four honest-looking zeros produce a `holds` from a run that
# measured nothing. The closing arm also probes the ONE-WAY-DEGRADE premise, which the four
# arms structurally cannot: Core degrades a shell permanently on the first failed connect
# because atuin is DISCARDING during the outage, and a build that instead SPOOLED those
# entries would leave the same delta of 0 behind — but flush them on the next successful
# write, landing 5 rows here instead of 1. That would INVERT the reasoning one-way rests on
# (dotgibson/dotfiles-core#383).
#
# WHY UNREACHABILITY IS PROVEN, NOT ASSUMED. A delta of zero against a socket that was
# quietly healthy would read as "still discarding" when the truth is "the daemon took it".
# So each shape is probed before anything is written — a bounded connect(2), plus the
# /proc/net/unix LISTEN scan where /proc is readable (the primitive from
# bench-atuin-daemon.sh's unit_owns_socket).
#
# EXIT CODE = VERDICT, AND THAT BREAKS ONE HOUSE IDIOM ON PURPOSE. audit-core.sh /
# test-core.sh / bench-core.sh all SKIP a missing prerequisite and exit 0, so they are safe
# to call on a bare box. Here exit 0 is a POSITIVE ASSERTION ABOUT UPSTREAM, so a bare box
# must not be able to produce it. A missing prerequisite still prints a skip line (and is
# still tallied by scripts/lib/common.sh) but exits 3:
#
#   0  holds        1  moved        2  usage error        3  unmeasurable
#
# `moved` exiting non-zero follows freshness.yml's --check mode: an intended non-zero is THE
# REPORT, NOT A CRASH, which is why the workflow reads the verdict out of --json instead of
# letting $? paint the run red.
#
# NO NETWORK, NO DOWNLOAD, NO PINS. This script measures an atuin binary it is HANDED
# (--atuin) or the one on PATH. Resolving and fetching "whatever upstream ships now" is the
# workflow's job, deliberately: fetching an unpinned upstream binary is a supply-chain
# decision that must be argued where the TOKENS live, not buried in a gate script a
# developer runs on their laptop. Keeping this side hermetic is also what makes it testable
# with no atuin present at all (scripts/test-core.sh Section J3).
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

# Shared palette + pass/skip/fail/have + the CORE_JSON convention.
# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"
# ROWCOUNT_PY / atuin_db_rows / atuin_db_checkpoint — the same schema model
# scripts/bench-atuin-daemon.sh's row rule rests on, so the two cannot drift apart.
# shellcheck source=scripts/lib/atuin-db.sh
source "${BASH_SOURCE[0]%/*}/lib/atuin-db.sh"

ATUIN_BIN=""
JSON=0
REPORT=""
FORCED_UNMEASURABLE=""
# WHICH PREMISE. `discard` is the default and must stay so: it starts no background process,
# which is what makes `make verify-atuin-guard` safe to run on a laptop. See the TWO PREMISES
# block in the header for why autostart is a separate mode rather than two more arms.
PREMISE=discard
# Bounded, so a wedged atuin (the accept-but-silent shape of atuinsh/atuin#3382) cannot hang
# a scheduled job until the runner's timeout kills it with no verdict at all.
TIMEOUT_S="${CORE_ATVERIFY_TIMEOUT:-30}"
# How many 0.1s ticks an autostart arm waits for its row. 100 (10s) is the default and is what
# CI uses — bench gives its equivalent check the same, because a cold-spawned daemon may be
# doing first-open migration work before it commits anything. The same bound is reused for
# waiting on a spawn to answer and on a stop to settle: all three are "how long may a daemon
# reasonably take", and three separate knobs would be three things to get out of step.
#
# LOWERING THIS MANUFACTURES FINDINGS, so it is documented as the test affordance it is rather
# than offered as tuning: an arm that gives up early reports delta 0, and the verdict block
# renders that as "autostart did not land the entry". scripts/test-core.sh §J4 sets it low
# because its stubs are deterministic and several of them are *supposed* to never write.
POLL_N="${CORE_ATVERIFY_POLL:-100}"
# WHOSE SANDBOX IS THIS. /tmp is a SHARED namespace, so the `atverify.` prefix alone cannot
# answer "did THIS run leave a tree behind" — and scripts/test-core.sh §J4 asserts exactly
# that, by snapshotting before and after and treating anything new as a leak. A second run on
# the same box (another worktree, two agents, `make audit` in one terminal while `make tag`
# audits in another) drops its own sandbox into that window and the first run reports a leak
# that never happened. It has already cost one false `make tag` failure — on the repo's most
# consequential command, where the natural operator response is to re-run or reach for
# TAG_SKIP_AUDIT=1. So every sandbox carries a per-run tag and the caller globs only its own.
#
# Defaulting to the PID is what keeps this script STANDALONE: `make verify-atuin-guard` and
# .github/workflows/atuin-guard-verify.yml pass nothing and still get a prefix no concurrent
# run can collide with, because two live processes cannot share a pid.
#
# Capped at 16 chars because the whole path is an AF_UNIX budget, not free text: sun_path caps
# near 108 bytes and the daemon socket sits at <sandbox>/home/.local/share/atuin/ (~35 bytes),
# which is the same reason /tmp is hardcoded above instead of $TMPDIR. 14 + 16 + 7 + 35 leaves
# room to spare; a tag longer than that would start spending it.
#
# `-`, NOT `:-`, and the difference is the whole point of the knob. The two bounds above use
# `:-`, so an empty CORE_ATVERIFY_TIMEOUT harmlessly means "the default" — but an empty tag is
# not a caller asking for the default, it is a caller whose tag EXPRESSION came out empty
# (`CORE_ATVERIFY_TAG="$some_unset_var"`). Defaulting that to the pid is the vacuous-pass shape
# this whole change exists to close: the script would sandbox under its pid while the caller
# globbed `/tmp/atverify..*`, which matches nothing, and the leak assertion would go green
# forever without ever looking at a sandbox. Unset is a default; empty is a bug, and falls
# through to the validator below to be rejected.
RUN_TAG="${CORE_ATVERIFY_TAG-$$}"

# Parse EVERY arg and reject an unknown one rather than ignore it — the same fail-closed
# contract as the gates, and as bench-atuin-daemon.sh's arg loop.
while (($#)); do
  case "$1" in
  --atuin)
    shift
    [[ $# -gt 0 ]] || {
      printf 'verify-atuin-guard.sh: --atuin needs a path\n' >&2
      exit 2
    }
    ATUIN_BIN="$1"
    ;;
  --premise)
    shift
    [[ $# -gt 0 ]] || {
      printf 'verify-atuin-guard.sh: --premise needs discard|autostart\n' >&2
      exit 2
    }
    # Checked against a closed set, not merely stored — the same lesson as --color below, and
    # it bites harder here. A typo that fell through would run the DEFAULT premise and then
    # report it under whatever the caller believed they had asked for: a confident verdict
    # about the wrong premise, filed under the wrong issue title. One premise, one verdict,
    # one title is the whole point of this mode existing (dotgibson/dotfiles-core#402).
    case "$1" in
    discard | autostart) PREMISE="$1" ;;
    *)
      printf 'verify-atuin-guard.sh: --premise needs discard|autostart (got %s)\n' "$1" >&2
      exit 2
      ;;
    esac
    ;;
  --json)
    JSON=1
    export CORE_JSON=1 # keeps skip() off stdout (scripts/lib/common.sh)
    ;;
  --report)
    shift
    [[ $# -gt 0 ]] || {
      printf 'verify-atuin-guard.sh: --report needs a path\n' >&2
      exit 2
    }
    REPORT="$1"
    ;;
  --unmeasurable)
    shift
    [[ $# -gt 0 ]] || {
      printf 'verify-atuin-guard.sh: --unmeasurable needs a reason\n' >&2
      exit 2
    }
    FORCED_UNMEASURABLE="$1"
    ;;
  --color)
    shift
    [[ $# -gt 0 ]] || {
      printf 'verify-atuin-guard.sh: --color needs auto|always|never\n' >&2
      exit 2
    }
    # Checked, not merely called. _core_set_color returns nonzero on a value outside
    # auto|always|never, and this script deliberately does not run under `set -e`, so an
    # unchecked call let `--color banana` fall through to a MEASUREMENT — turning a typo in
    # the caller's flags into a verdict about upstream. Every other bad flag here exits 2;
    # this one has to as well, or the usage contract is only true for some of the flags.
    _core_set_color "$1" || {
      printf 'verify-atuin-guard.sh: --color needs auto|always|never (got %s)\n' "$1" >&2
      exit 2
    }
    ;;
  -h | --help)
    cat <<'EOF'
usage: verify-atuin-guard.sh [--premise discard|autostart] [--atuin PATH] [--json]
                             [--report FILE] [--unmeasurable REASON] [--color WHEN]
                             [-h|--help]

Measure an upstream fact that _core_atuin_daemon_guard (zsh/00-tools.zsh) is premised on.
TWO premises, one per run, selected with --premise:

  discard    (default) With the daemon enabled and its socket unreachable, does
             `atuin history start` still exit 0, print an id, stay silent on stderr, and
             DISCARD the entry (atuinsh/atuin#3561)? Starts no background process.
  autostart  With ATUIN_DAEMON__AUTOSTART set and the socket unreachable, does atuin
             SPAWN a daemon and land the entry? The guard stands down entirely under that
             variable, on exactly this assumption, and that stand-down is the ONLY
             mitigation on Alpine and macOS. SPAWNS A REAL DAEMON (see teardown below).

Hermetic: a throwaway HOME/XDG under env -i, Core's own atuin/config.toml, and a DB this
run creates and deletes. It never touches your real history.

Two unreachable shapes are measured under BOTH premises, because the guard's rationale claims
both:
  absent   the socket path does not exist
  stale    a real AF_UNIX socket file with nothing listening (a crashed daemon)
Each is measured with and without --hook (the form atuin's own `init zsh` emits, and so the
only one a real shell runs), and each is PROVEN unreachable before anything is written, so a
verdict can never rest on a socket that was quietly healthy. Under --premise autostart the
`stale` shape is the load-bearing one: every `atuin history start` is a fresh process, so
"fire-and-forget" can only mean that a dead daemon's leftover socket inode defeats the spawn.

A daemon-OFF control arm runs first and must write exactly one row. It is the apparatus
check: if the control cannot write, nothing observed afterwards means anything, and the
verdict is `unmeasurable` rather than a guess. A second one runs LAST and must also write
exactly one row: it proves the apparatus was still writable after the arms ran, and a delta
above 1 means atuin spooled the unreachable entries and replayed them rather than discarding
them — which would invert the premise the guard's one-way degrade rests on.

--premise autostart adds TWO MORE CONTROLS, and they are what make a finding attributable.
"autostart did not spawn a daemon" and "this box cannot host a daemon" are the same
observation, so a MANUAL spawn (`atuin daemon start`) runs first and must work; if it cannot,
the verdict is `unmeasurable`, never a finding about upstream. A second manual spawn is then
attempted over a STALE socket, and its result is recorded rather than gated — it is what
separates "the client will not re-spawn after a crash" from "the daemon cannot bind over a
stale inode", which are different bugs in different layers.

TEARDOWN, under --premise autostart. atuin spawns a daemon whose PID this script never learns,
so it is stopped through `atuin daemon stop` and the stop is PROVEN (a connect must start
failing) before anything is unlinked or removed. The run refuses to spawn at all unless both
`daemon start` and `daemon stop` exist on the binary under test — a spelling upstream has
moved before — because a daemon that cannot be stopped would be left writing into a tree this
script is about to delete. If a stop cannot be proven even after escalating to a signal, the
sandbox is PRESERVED and its path printed.

VERDICTS AND EXIT CODES. The codes are shared; what `holds` REQUIRES is not, because the two
premises assert opposite things about the same four arms:
  0  holds         --premise discard:   controls wrote 1 each; every arm rc 0, id printed,
                                        empty stderr, and a row delta of 0 (it discarded).
                   --premise autostart: both controls passed; every arm rc 0, id printed, a
                                        daemon that ANSWERS on the socket, and a row delta of
                                        1 (the entry landed). stderr is recorded but NOT
                                        judged — a spawned daemon inherits this process's
                                        descriptor, so its output and the client's cannot be
                                        told apart.
  1  moved         the controls passed; something above differs — the rationale now overclaims
  2  usage error
  3  unmeasurable  the apparatus could not be trusted. NOT "holds".

Exit 0 is a positive assertion about upstream, so — unlike the other gate scripts — a
missing prerequisite exits 3, not 0.

  --premise WHICH       discard (default) | autostart. One premise per run, one verdict, one
                        issue title. The default starts no background process, which is what
                        keeps `make verify-atuin-guard` safe to run on a laptop; the autostart
                        mode has its own target, `make verify-atuin-guard-autostart`.
  --atuin PATH          measure this binary instead of the one on PATH
  --json                one JSON object on stdout; exit status matches the human path
  --report FILE         write an issue-ready markdown report (no title heading)
  --unmeasurable REASON emit a well-formed unmeasurable verdict WITHOUT measuring, so a
                        caller that failed before the binary existed (a download, a
                        checksum) reports through this one renderer instead of
                        hand-rolling prose at the call site
  --color WHEN          auto|always|never (CORE_COLOR works too)

Environment:
  CORE_ATVERIFY_TIMEOUT=<s>   per-call timeout (default 30). A call that never returns is
                              itself a finding — see atuinsh/atuin#3382.
  CORE_ATVERIFY_TAG=<tag>     1-16 chars of [A-Za-z0-9_-] naming this run's sandboxes, which
                              are created as /tmp/atverify.<tag>.XXXXXX (default: this
                              script's pid). Set it when the caller needs to tell ITS
                              sandboxes apart from a concurrent run's in shared /tmp.
EOF
    exit 0
    ;;
  *)
    printf 'verify-atuin-guard.sh: unexpected argument: %s\n' "$1" >&2
    printf 'try: verify-atuin-guard.sh --help\n' >&2
    exit 2
    ;;
  esac
  shift
done

# Canonical-integer test, not `^[0-9]+$` plus an arithmetic compare: those look equivalent
# and are not — `08` passes the digit class and bash then reads it as OCTAL. Same guard
# bench-atuin-daemon.sh applies to its knobs.
[[ "$TIMEOUT_S" =~ ^[1-9][0-9]*$ ]] || {
  printf 'verify-atuin-guard.sh: CORE_ATVERIFY_TIMEOUT must be a positive integer with no leading zero: %s\n' \
    "$TIMEOUT_S" >&2
  exit 2
}
[[ "$POLL_N" =~ ^[1-9][0-9]*$ ]] || {
  printf 'verify-atuin-guard.sh: CORE_ATVERIFY_POLL must be a positive integer with no leading zero: %s\n' \
    "$POLL_N" >&2
  exit 2
}
# Rejected, not sanitized. This value becomes a path component under /tmp, so a `/` or a `..`
# in it is a caller bug that would put the sandbox somewhere the cleanup trap does not expect;
# and a caller that globs its own tag needs the tag it PASSED, not a quietly rewritten one.
#
# IN THE C LOCALE, and BOTH halves of the pattern need it. POSIX defines a range like [A-Z] by
# COLLATION rather than codepoint, so under a UTF-8 locale it may admit letters this contract
# does not mean to allow — and Core ships to glibc, musl and BSD userlands, which do not agree
# with each other about that. The cap needs it just as much: `{1,16}` counts CHARACTERS, so
# sixteen multibyte ones are up to 64 bytes and the limit silently stops being the AF_UNIX
# budget it exists to be. Under LC_ALL=C both become bytes, which is the unit that matters.
# A subshell rather than an assignment, so the locale cannot leak into the report rendering.
(
  LC_ALL=C
  [[ "$RUN_TAG" =~ ^[A-Za-z0-9_-]{1,16}$ ]]
) || {
  printf 'verify-atuin-guard.sh: CORE_ATVERIFY_TAG must be 1-16 characters of [A-Za-z0-9_-]: %s\n' \
    "$RUN_TAG" >&2
  exit 2
}

# ── the whole verdict lives in these scalars ──────────────────────────────────
# Flat scalars, not associative arrays: this must run on macOS's stock bash 3.2, the same
# constraint scripts/lib/common.sh pins.
VERDICT=""
REASON=""
AT_VER="unknown"
ANCHOR="unknown"
ANCHOR_REL="unknown" # same | newer | older | unanchored | unknown
# WHERE this ran, because for the autostart premise that is half the verdict's worth. The two
# machines the stand-down protects are Alpine/musl and macOS; a green run ON one of them is
# direct evidence for that row, and a green run on glibc Linux — the CI default — is the
# weakest evidence in the whole arrangement. A hardcoded "glibc only" caveat was wrong the
# first time this was run by hand on a Mac, which is exactly the machine it most wanted.
HOST_KIND="unknown"
CTL_DELTA=-1
# The CLOSING daemon-off control arm's delta. A flat scalar beside CTL_DELTA and deliberately
# NOT an entry in ARM_NAME below: it is a control, not a measurement of the premise, and the
# report table and the JSON `arms` object both mean "an unreachable shape we measured".
DRAIN_DELTA=-1
# Parallel indexed arrays, one entry per measured arm — bash 3.2 has no associative arrays
# (scripts/lib/common.sh pins that constraint), and four arms x five facts as flat scalars
# was twenty names to keep in step. The index is the arm; ARM_NAME[i] is "shape_hookmode".
ARM_NAME=() ARM_RC=() ARM_DELTA=() ARM_IDOK=() ARM_ERR=()
# The delta each arm was REQUIRED to produce — 0 under `discard` (the entry is thrown away),
# 1 under `autostart` (a daemon comes up and the entry lands). Carried per arm rather than
# inferred from PREMISE at render time, because the arm names are identical across the two
# premises and a reader looking at `"delta":1` in the JSON has no other way to tell a healthy
# autostart arm from a discard arm that just broke.
ARM_EXPECT=()
# Did a daemon become REACHABLE on this arm? `yes`/`no` under `autostart` — the arm's central
# observation, and the one the row delta cannot make on its own: a delta of 0 is what both "no
# daemon spawned" and "a daemon spawned and dropped the entry" look like. `na` under `discard`,
# where the arms assert the opposite and prove it before writing.
ARM_SPAWN=()
# ── autostart-premise state (all inert under the default `discard` premise) ───
SPAWN_CTL_DELTA=-1        # manual-spawn control A: the daemon-ON write, must be 1
SPAWN_CTL_STALE_OK=na     # control B: yes|no|na — can `daemon start` bind OVER a stale inode?
SOCK=""                   # atuin's own default socket path inside the sandbox
AT_DAEMON_ARGV=()         # `daemon` vs `daemon start`, resolved once by daemon_probe_argv
DAEMON_MAYBE_UP=0         # 1 from the instant a spawn is attempted until a stop is PROVEN
MANUAL_DAEMON_PID=""      # set only for daemons WE start; an autostart one has no PID for us
LAST_OWNER_PID=""         # who owned the socket BEFORE the last stop — the only handle on a
                          # detached daemon, and resolvable only while the socket still exists
CLEANED=0                 # cleanup() idempotence — INT and EXIT both reach it on a Ctrl-C
_label=""                 # premise name for the one-line human verdict at the very bottom
TRACKED_PGIDS=""          # every process group we started; reaped by cleanup()
RUN_REC=""                # run_one's record — a global precisely so no subshell eats it
_pgid=""
_ok="" _rc="" _delta="" _idok="" _err=""   # run_one record fields, read via IFS
SB="" LOCALDIR=""
# FILE SCOPE, not measure()-local, even though measure() is what fills them. The EXIT trap
# reads AT_ENV to stop a daemon, and this script runs under `set -u`: an early `return` from
# measure() (a missing python3, an unreadable anchor — both before line one of the sandbox
# build) would otherwise leave the name unbound and kill the trap with "unbound variable"
# exactly when cleanup matters most. scripts/bench-atuin-daemon.sh declares its equivalents
# at file scope for the same reason.
AT_VARS=() AT_ENV=()
BOUNDED=true            # false when neither timeout(1) nor gtimeout(1) exists (see measure())
TIMEOUT_CMD=()          # the bounding prefix, empty when unbounded

# The ONLY two ways this script reaches a non-`holds` conclusion. Never `holds` by omission:
# VERDICT starts empty and is set explicitly, so a path that forgets to decide cannot fall
# through into good news.
unmeasurable() {
  VERDICT=unmeasurable
  REASON="$1"
}
moved() {
  VERDICT=moved
  REASON="$1"
}

# BOTH codes, deliberately: shellcheck renamed this diagnostic between the versions the
# fleet actually runs. 0.11.0 (the pin in scripts/tool-versions.env, used by CI's ubuntu and
# macOS legs) reports a trap-only function as SC2329 "never invoked"; 0.10.0 — which is what
# `apk add shellcheck` gives the Alpine leg — reports the same thing as SC2317 "unreachable"
# on the body instead. Disabling only the pinned version's code passes locally and on ubuntu
# and still fails Alpine, which is exactly how this went red the first time. An unknown code
# in a disable directive is ignored, so naming both is safe in either direction.
# SC2016 as well: the backticks in the preserved-sandbox message below are MARKDOWN-ish prose
# naming a command, not command substitution — single quotes are exactly right for a printf
# format string, the same call emit_report makes further down.
# shellcheck disable=SC2329,SC2317,SC2016  # invoked indirectly, by the EXIT trap below
# reap_tracked_groups — kill anything still alive in the process groups we started: the four
# autostart arms AND the manual-spawn control. Runs AFTER the proven stop, never between arms: the daemon an arm just spawned is in
# that group too, and killing it early would destroy the very thing prove_reachable is about
# to ask about. Both signals are best-effort — an empty or already-dead group is the normal
# case, and `kill` failing on one is not news.
# shellcheck disable=SC2329,SC2317  # invoked from cleanup, which the traps invoke
reap_tracked_groups() {
  local g keep=""
  [[ -n "$TRACKED_PGIDS" ]] || return 0
  for g in $TRACKED_PGIDS; do kill -TERM "-$g" 2>/dev/null; done
  sleep 0.2
  for g in $TRACKED_PGIDS; do kill -KILL "-$g" 2>/dev/null; done
  sleep 0.1
  # RETAIN WHAT IS STILL ALIVE. Clearing the list unconditionally made the groups_quiet check
  # that follows every call to this function succeed BY CONSTRUCTION — it was asking an empty
  # list whether anything remained. A SIGKILL that failed, or a process that had not finished
  # exiting, was then read as a proven teardown and its sandbox deleted around it. The list IS
  # the evidence; a reap may only drop what it can show is gone.
  for g in $TRACKED_PGIDS; do
    kill -0 -- "-$g" 2>/dev/null && keep+=" $g"
  done
  TRACKED_PGIDS="${keep# }"
  return 0
}

# Same both-codes disable as reap_tracked_groups above, and SC2016 for the markdown-ish backticks
# in the preserved-sandbox message: single quotes are right for a printf format string.
# shellcheck disable=SC2329,SC2317,SC2016  # invoked indirectly, by the traps below
cleanup() {
  ((CLEANED)) && return 0
  CLEANED=1
  local stopped=1
  # STOP BEFORE REMOVE, and only remove once the stop is proven. Under --premise autostart a
  # daemon may still hold this tree open, and `rm -rf` on a directory a live process is
  # committing SQLite into leaves it writing to unlinked inodes — a corrupted DB and a
  # stranded process, from the cleanup step. Nothing in the default premise ever spawns, so
  # DAEMON_MAYBE_UP is 0 and this whole branch is skipped.
  if ((DAEMON_MAYBE_UP)) && [[ -n "$SOCK" ]]; then
    daemon_stop_proven "$SOCK" || stopped=0
  fi
  # Unconditionally, and after the stop attempt rather than instead of it: this catches the
  # forked-but-never-bound children the socket-based teardown cannot see, and it must still
  # run on the preserve path below — a tree we are keeping is no reason to keep processes.
  reap_tracked_groups
  # RE-PROVE AFTER REAPING. The daemon is in the arm's process group, so reap_tracked_groups can
  # be the step that finally kills what the socket-scoped stop could not — and without this
  # re-check cleanup would keep the sandbox and print a "STILL answering" warning about a
  # process that is by then gone. The preserve path has to be a genuine last resort, or the
  # one message that must always be true stops being true.
  if ((stopped == 0)) && [[ -n "$SOCK" ]] && stop_settled "$SOCK" "$((POLL_N < 30 ? POLL_N : 30))"; then
    stopped=1
  fi
  if ((stopped == 0)); then
    # The one path that leaves state behind, so it must never be quiet. Refusing to delete is
    # NOT the first response — daemon_stop_proven has already asked, signalled and SIGKILLed,
    # and reap_tracked_groups has had its turn, by the time we get here. Keeping the tree is the
    # least-bad end state: an orphaned daemon still holding the files it believes it owns
    # beats an orphaned daemon plus a half-deleted tree.
    printf 'verify-atuin-guard.sh: a daemon is STILL answering on %s after `atuin daemon stop`, SIGTERM and SIGKILL.\n' "$SOCK" >&2
    printf 'verify-atuin-guard.sh: the sandbox has been PRESERVED rather than deleted, because removing a tree a live daemon is writing into would corrupt it.\n' >&2
    printf 'verify-atuin-guard.sh: stop that process, then: rm -rf %s\n' "$LOCALDIR" >&2
    return 0
  fi
  [[ -n "$LOCALDIR" ]] && rm -rf "$LOCALDIR"
  return 0
}
trap cleanup EXIT
# INT and TERM as well, which matters only now that a premise spawns. bash runs an EXIT trap
# when the shell dies of SIGINT, but NOT of SIGTERM — and SIGTERM is exactly what a scheduled
# job's timeout sends. Without these, the one situation most likely to strand a daemon (a run
# killed mid-arm) would be the one situation cleanup never ran in. CLEANED above makes the
# double visit on Ctrl-C (INT handler, then EXIT) harmless.
# shellcheck disable=SC2329,SC2317  # same both-codes reason as cleanup above
trap 'cleanup; exit 130' INT
# shellcheck disable=SC2329,SC2317
trap 'cleanup; exit 143' TERM

# ── the anchor ────────────────────────────────────────────────────────────────
# Read the ONE machine-readable line in zsh/00-tools.zsh, anchored at column 0 with nothing
# but the value after the `=`. Deliberately NOT a grep for a bare version pattern anywhere
# in the file: that rationale paragraph also names 18.16.1, and a detector comparing against
# the wrong number is worse than one that never runs. Exactly ONE match is required — zero
# means the anchor was renamed or deleted, two means the file disagrees with itself, and
# both are `unmeasurable` rather than a default.
#
# ONE ANCHOR PER PREMISE, keyed by the caller. An anchor is a claim that a HUMAN measured
# this premise against that version — emit_report says exactly that, and refuses to treat
# moving it as a version bump. Sharing one line between the two premises would make that
# sentence ambiguous about which premise was re-measured, and would let a green autostart
# run silently re-date the silent-discard claim that nine repos' prompt hooks rest on.
# The autostart key is allowed to be ABSENT: see anchor_optional below.
read_anchor() {
  local key="$1" raw valid
  # RAW occurrences of the key — whatever follows it — counted SEPARATELY from occurrences
  # with a well-formed value. Counting only well-formed ones made `# KEY=18.19` indis-
  # tinguishable from no key at all, and for the autostart premise, where absence is
  # legitimate, that turns a typo into a silent `unanchored` run instead of the `unmeasurable`
  # this function's whole contract promises. It also hid a valid line paired with a malformed
  # duplicate — a file disagreeing with itself, which is never anything but unmeasurable.
  #
  # Deliberately NOT a grep for a bare version pattern anywhere in the file: that rationale
  # paragraph also names 18.16.1, and a detector comparing against the wrong number is worse
  # than one that never runs.
  raw="$(grep -c "^# ${key}=" zsh/00-tools.zsh 2>/dev/null || true)"
  valid="$(grep -c "^# ${key}=[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*[[:space:]]*\$" zsh/00-tools.zsh 2>/dev/null || true)"
  ((raw == 0)) && return 1  # absent — legitimate for autostart, fatal for discard
  ((raw > 1)) && return 2   # stated more than once: the file contradicts itself
  ((valid == 1)) || return 3
  ANCHOR="$(sed -n "s/^# ${key}=\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)[[:space:]]*\$/\1/p" \
    zsh/00-tools.zsh 2>/dev/null)"
  return 0
}

# The key for the premise under measurement, and whether its absence is fatal.
#
# `discard` REQUIRES its anchor: that premise has been measured since #366, so a missing line
# means the anchor was renamed or deleted and the run cannot say what it is comparing against.
#
# `autostart` does NOT, and that asymmetry is the honest one. Until a human runs this mode and
# writes the number down, there is no prior measurement to compare against — so the run reports
# `anchor: none`, `anchor_relation: unanchored`, and still measures. Refusing to measure
# instead would file an `unmeasurable` issue every Tuesday until someone bootstrapped it, which
# trains the reader to ignore the one title that must never be ignored.
anchor_key() {
  case "$PREMISE" in
  autostart) printf 'CORE_ATUIN_AUTOSTART_VERIFIED_AGAINST' ;;
  *) printf 'CORE_ATUIN_GUARD_VERIFIED_AGAINST' ;;
  esac
}

# ver_cmp a b → prints -1 / 0 / 1. Field-wise integer compare: no `sort -V` (GNU-only in
# practice) and no bash 4 constructs, so this behaves the same on macOS.
# detect_host — "Darwin arm64", "Linux x86_64 musl", "Linux x86_64 glibc". The libc split is
# the part that matters: musl is a whole third of the fleet and is what the discard premise
# has always disclaimed. `ldd --version` prints to stderr on glibc and stdout on musl, so both
# streams are read; anything unrecognised stays unnamed rather than guessed at.
detect_host() {
  local s m ldd_out=""
  s="$(uname -s 2>/dev/null)" || s="unknown"
  m="$(uname -m 2>/dev/null)" || m="unknown"
  # CAPTURE, THEN MATCH ON THE STRING — never `ldd --version | grep`. `set -o pipefail` is in
  # force at the top of this script, and musl's ldd exits NON-ZERO after printing its banner,
  # so the pipe form fails the whole pipeline even when grep matched. Every musl run would
  # report no libc at all, on the one machine where that marker is the evidence. This repo has
  # already paid for that exact mistake once: scripts/bench-atuin-daemon.sh carries the same
  # capture-first idiom and the same warning. The `|| true` is load-bearing, not habit.
  if [[ "$s" == Linux ]] && have ldd; then
    ldd_out="$(ldd --version 2>&1 || true)"
  fi
  case "$ldd_out" in
  *[Mm]usl*) HOST_KIND="${s} ${m} musl" ;;
  *GLIBC* | *[Gg]libc* | *"GNU libc"*) HOST_KIND="${s} ${m} glibc" ;;
  *) HOST_KIND="${s:-unknown} ${m:-unknown}" ;;
  esac
}

ver_cmp() {
  local i x y
  local -a A B
  local IFS=.
  # shellcheck disable=SC2206  # deliberate word-splitting on IFS=. — that IS the parse
  A=($1)
  # shellcheck disable=SC2206
  B=($2)
  unset IFS
  for ((i = 0; i < 4; i++)); do
    x="${A[i]:-0}"
    y="${B[i]:-0}"
    [[ "$x" =~ ^[0-9]+$ ]] || x=0
    [[ "$y" =~ ^[0-9]+$ ]] || y=0
    if ((10#$x > 10#$y)); then
      printf '1'
      return 0
    elif ((10#$x < 10#$y)); then
      printf -- '-1'
      return 0
    fi
  done
  printf '0'
}

# ── unreachability proof ──────────────────────────────────────────────────────
# prove_unreachable <path> — 0 when nothing is listening, 1 when something is (or when we
# cannot tell). Two independent checks, both fail-closed:
#   (1) /proc/net/unix, where readable: field 6 == 01 is LISTEN, field 8 is the path. This
#       is the primitive bench-atuin-daemon.sh's unit_owns_socket uses. Linux-only.
#   (2) a real connect(2) via python, bounded by a short timeout. A refusal (ECONNREFUSED)
#       or a missing path is the proof we want; a SUCCESSFUL connect means something is
#       serving the socket and the measurement below would be meaningless.
prove_unreachable() {
  local p="$1"
  if [[ -r /proc/net/unix ]] &&
    awk -v path="$p" '$6=="01" && $NF==path {found=1} END{exit !found}' /proc/net/unix 2>/dev/null; then
    return 1 # something is LISTENing on it
  fi
  [[ -e "$p" ]] || return 0 # absent path: nothing can be listening
  python3 - "$p" <<'PY' 2>/dev/null
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(2)
try:
    s.connect(sys.argv[1])
except OSError:
    sys.exit(0)          # refused / gone — genuinely unreachable
else:
    s.close()
    sys.exit(1)          # someone answered
PY
}

# make_stale <path> — bind+listen a real AF_UNIX socket, then exit without unlinking, so the
# inode survives with nothing behind it. That is the shape a crashed daemon leaves, and the
# one a plain `[[ -S ]]` test cannot tell from health.
make_stale() {
  python3 - "$1" <<'PY' 2>/dev/null
import os, socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
s.listen(1)
os._exit(0)              # no unlink, no close: the socket file stays behind
PY
  [[ -S "$1" ]]
}

# ── daemon lifecycle (only --premise autostart reaches any of this) ───────────
# prove_reachable <path> — 0 ONLY when a connect(2) actually succeeds.
#
# Deliberately NOT `! prove_unreachable`, and this is the single easiest place in the file to
# introduce a false `holds`. THE FAIL-CLOSED DIRECTION INVERTS WITH THE PREMISE.
# prove_unreachable answers "not unreachable" both when something is listening AND when it
# could not tell, which is the right way round when a wrongly-claimed unreachable socket would
# manufacture a discard finding. Here the dangerous error is the mirror image: "could not
# tell" must never be scored as "a daemon came up", or a box where python3 silently broke
# would report the autostart premise holding — the exact shape of good-news-by-omission this
# script exists to refuse.
#
# No /proc branch either, unlike prove_unreachable. A LISTEN row says a socket is BOUND, not
# that anything answers, and "bound but wedged" is atuinsh/atuin#3382's shape — which must not
# score as a healthy spawn. Only a completed connect counts as proof a daemon is serving.
prove_reachable() {
  local p="$1"
  [[ -S "$p" ]] || return 1
  python3 - "$p" <<'PY' 2>/dev/null
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(2)
try:
    s.connect(sys.argv[1])
except OSError:
    sys.exit(1)          # refused / gone — nothing is serving it
else:
    s.close()
    sys.exit(0)          # someone answered: a daemon is up
PY
}

# wait_reachable / wait_unreachable <path> <tries> — poll at 0.1s. 100 tries (10s) is bench's
# bound for the same wait (its daemon_start loop), and a cold daemon doing first-open work on
# records.db/meta.db is exactly what needs it.
wait_reachable() {
  local p="$1" tries="$2" i
  for ((i = 0; i < tries; i++)); do
    prove_reachable "$p" && return 0
    sleep 0.1
  done
  return 1
}

# groups_quiet — 0 when no process group we started still has a living member. `kill -0` on a
# NEGATED pgid asks about the whole group, and succeeds while any member remains.
groups_quiet() {
  local g
  for g in $TRACKED_PGIDS; do
    kill -0 -- "-$g" 2>/dev/null && return 1
  done
  return 0
}

# stop_settled <sock> <tries> — the stop is settled only when the socket has stopped answering
# AND every group we started is empty.
#
# "NOTHING ANSWERS" IS NOT "THE DAEMON EXITED", and the gap between them is not theoretical:
# a daemon that unlinks its socket early in shutdown, or a `daemon stop` that returns while
# teardown is still running, both leave a process that no longer answers and still HOLDS THE
# DB. A socket-only proof accepts that as stopped — after which the next arm measures against
# a daemon it did not start, and cleanup rm -rf's a tree that process is still writing into.
# The group check is what closes it: for a daemon we started by hand we would have a pid, but
# for one atuin forked we never do, and the group covers both.
# socket_quiet_within <path> <tries> — poll until nothing answers. The negation of
# prove_reachable, NOT prove_unreachable: during teardown a vanished socket file is a
# perfectly good way for a daemon to have shut down, and prove_unreachable's `[[ -e ]]`
# short-circuit would conflate that with "the file was unlinked out from under us".
socket_quiet_within() {
  local p="$1" tries="$2" i
  for ((i = 0; i < tries; i++)); do
    prove_reachable "$p" || return 0
    sleep 0.1
  done
  return 1
}

# stop_settled <sock> <tries> — the two-part stop proof, and the ONLY thing that may conclude
# a daemon is gone.
#
# "NOTHING ANSWERS" IS NOT "THE DAEMON EXITED", and the gap is not theoretical: a daemon that
# unlinks its socket early in shutdown, or a `daemon stop` that returns while teardown is
# still running, both leave a process that no longer answers and still HOLDS THE DB. A
# socket-only proof accepts that as stopped — after which the next arm measures against a
# daemon it did not start, and cleanup rm -rf's a tree that process is still writing into.
#
# The two halves are treated differently ON PURPOSE. The socket is POLLED, because a daemon
# legitimately takes a moment to go down. The process groups are NOT: anything still alive in
# one is a detached daemon with no socket left to resolve an owner from, so it will not exit
# on its own and waiting for it just spends the whole bound before the signal that was always
# going to be needed. Reap, then re-ask.
stop_settled() {
  # ORDER IS LOAD-BEARING: the KNOWN owner is waited for, and only then are survivors treated
  # as strays. A daemon we asked to stop is not a stray — it is a process legitimately
  # shutting down, and the manual control's daemon sits in a tracked group, so reaping first
  # sent it SIGTERM 200ms after its socket vanished, mid final-flush. That control's row delta
  # is verdict-bearing, which means a corrupted flush there would not merely lose data: it
  # would manufacture a verdict. Give the owner its whole configured bound; whatever is left
  # afterwards never asked to leave and never will.
  socket_quiet_within "$1" "$2" || return 1
  owner_gone "$2" || return 1
  groups_quiet || reap_tracked_groups
  groups_quiet
}

# owner_gone <tries> — the pid that owned the socket BEFORE the stop must actually be gone.
#
# THIS IS THE ONLY HALF THAT REACHES A REAL AUTOSTART DAEMON, and the reason the other two are
# not enough. Measured on 18.19.0: a client-spawned daemon DETACHES — the arm ran in process
# group 88291 and the daemon it started landed in 88299 — so `groups_quiet` answers "nothing
# left" about a group the daemon was never in, and the socket goes silent the moment shutdown
# unlinks it, which can be well before the final DB flush. Both halves therefore say "stopped"
# while the process is alive and still writing. Only the pid settles it, and the pid can only
# be looked up while the socket it owns still exists — which is why it is captured BEFORE the
# stop rather than after.
owner_gone() {
  local tries="$1" i
  # Empty means the socket was ALREADY unowned when we looked — nothing to wait for.
  [[ -n "$LAST_OWNER_PID" ]] || return 0
  # `unknown` means a socket WAS being served and this box could not say by whom (no lsof, an
  # unreadable /proc). That is not the same fact, and treating it as one is fail-OPEN in the
  # single place this file cannot afford it: the socket and group checks both pass for a
  # detached daemon, so an unresolvable owner is the only remaining evidence, and calling it
  # "no owner" deletes the sandbox around a live process. Never settles.
  [[ "$LAST_OWNER_PID" == unknown ]] && return 1
  for ((i = 0; i < tries; i++)); do
    kill -0 "$LAST_OWNER_PID" 2>/dev/null || {
      LAST_OWNER_PID=""
      return 0
    }
    sleep 0.1
  done
  return 1
}

# Which spelling drives the daemon on THIS build — the same probe, for the same reason, as
# scripts/bench-atuin-daemon.sh and examples/atuin-daemon.service. `atuin daemon` is deprecated
# in favour of `atuin daemon start` (18.19.0 warns on every start) but the subcommand is absent
# on older builds. It must be `daemon start --help`, not `daemon --help`: the latter exits 0 on
# BOTH spellings and proves nothing.
#
# WHERE THIS IS STRICTER THAN THE BENCH, on purpose. The bench tolerates a missing
# `daemon stop`, because it holds the PID of the daemon it started and `kill` is what actually
# stops it. Here atuin spawns the daemon and this script is never told the PID, so a build
# without `daemon stop` is one whose daemon we cannot reliably reap — left running against a
# sandbox the EXIT trap is about to delete. Refusing to spawn costs an `unmeasurable` run;
# spawning anyway costs a stranded process writing into a deleted tree. Returns 1 for a missing
# start, 2 for a missing stop, so the caller can say which.
daemon_probe_argv() {
  ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} "$ATUIN_BIN" daemon start --help >/dev/null 2>&1 || return 1
  ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} "$ATUIN_BIN" daemon stop --help >/dev/null 2>&1 || return 2
  AT_DAEMON_ARGV=(daemon start)
  return 0
}

# socket_owner_pid <path> — the pid holding <path> open, or nothing. Linux resolves the
# socket's inode from /proc/net/unix (field 7) and scans /proc/<pid>/fd for the matching
# `socket:[inode]` link — the primitive bench-atuin-daemon.sh's unit_owns_socket uses. macOS
# has no /proc, so lsof is the equivalent. Best-effort: an empty answer only costs the
# escalation path below, and the caller already treats "still answering" as the failure.
socket_owner_pid() {
  local p="$1" ino d
  if [[ -r /proc/net/unix ]]; then
    ino="$(awk -v path="$p" '$NF==path {print $7; exit}' /proc/net/unix 2>/dev/null)"
    [[ -n "$ino" ]] || return 1
    # readlink per fd rather than `ls -l | grep`: the glob is what shellcheck wants (SC2010),
    # and an exact string compare beats a substring match that `socket:[123]` would also
    # satisfy for inode 1234. Only ever walked on the escalation path, so the syscall cost is
    # paid exactly when something has already gone wrong.
    local f
    for d in /proc/[0-9]*; do
      for f in "$d"/fd/*; do
        [[ "$(readlink "$f" 2>/dev/null)" == "socket:[${ino}]" ]] || continue
        printf '%s' "${d#/proc/}"
        return 0
      done
    done
    return 1
  fi
  have lsof || return 1
  ino="$(lsof -t -- "$p" 2>/dev/null | head -n1)"
  [[ -n "$ino" ]] || return 1
  printf '%s' "$ino"
}

# daemon_start_manual <sock> — start a daemon OURSELVES and wait for it to answer.
#
# This is the control the whole autostart premise hangs off. "autostart did not spawn a
# daemon" and "this box cannot host a daemon" are the same observation, and only one of them
# is a fact about upstream; running a manual spawn first is what tells them apart. No
# TIMEOUT_CMD prefix, deliberately — this process is meant to outlive the call.
daemon_start_manual() {
  local sock="$1"
  DAEMON_MAYBE_UP=1
  # TRACKED LIKE THE ARMS ARE, and for the same reason. A PID is not enough here either: if
  # this build forks a child that hangs before binding and the parent then exits,
  # MANUAL_DAEMON_PID names a corpse, wait_reachable fails, cleanup sees an absent socket and
  # calls it stopped, and reap_manual has nothing to kill — the sandbox goes while that child
  # lives. The process group is the only handle that covers it. No `wait` here, unlike the
  # arms: this process is meant to outlive the call.
  set -m
  "${AT_ENV[@]}" ATUIN_DAEMON__ENABLED=true \
    "$ATUIN_BIN" ${AT_DAEMON_ARGV[@]+"${AT_DAEMON_ARGV[@]}"} \
    </dev/null >>"$SB/daemon.log" 2>&1 &
  MANUAL_DAEMON_PID=$!
  TRACKED_PGIDS="$TRACKED_PGIDS $MANUAL_DAEMON_PID"
  set +m
  wait_reachable "$sock" "$POLL_N"
}

# daemon_stop_proven <sock> — stop whatever serves <sock>, and PROVE it stopped. Non-zero only
# when something is still answering at the end.
#
# PROOF, not a stop command's exit status. `atuin daemon stop` returning 0 says the request was
# accepted, not that the process is gone — and every later arm's "the socket was unreachable
# before I wrote" gate, plus the EXIT trap's licence to rm -rf, both rest on this having really
# worked. An unproven stop is how the four arms silently stop being independent.
#
# ESCALATION, not refusal. Ask through the socket; then, for a daemon we started, use the PID
# we have; then, for an autostart daemon we were never told about, resolve the owner from the
# socket itself. Never `pkill atuin`: the developer running this may have their own daemon on
# their own socket, and it is none of this script's business (bench makes the same rule).
# A manual spawn that NEVER BOUND still left a process behind: nothing answers the socket, so
# the "it stopped" proof passes honestly — and the child is alive anyway, perhaps retrying.
# That is a leak the socket cannot see, and it is only reapable here because a manual spawn is
# the one case where we hold a PID at all. An autostart daemon has no equivalent; that is what
# socket_owner_pid is for.
reap_manual() {
  [[ -n "$MANUAL_DAEMON_PID" ]] || return 0
  if kill -0 "$MANUAL_DAEMON_PID" 2>/dev/null; then
    kill -TERM "$MANUAL_DAEMON_PID" 2>/dev/null
    sleep 0.2
    kill -KILL "$MANUAL_DAEMON_PID" 2>/dev/null
  fi
  wait "$MANUAL_DAEMON_PID" 2>/dev/null
  MANUAL_DAEMON_PID=""
  return 0
}

daemon_stop_proven() {
  local sock="$1" sig half
  ((DAEMON_MAYBE_UP)) || return 0
  # CAPTURE THE OWNER FIRST. This is the only window in which a detached autostart daemon is
  # identifiable at all: it is not in any group we hold, and once shutdown unlinks the socket
  # there is nothing left to resolve it by. Looking it up AFTER the stop — which is what this
  # did — can only ever find a daemon that failed to remove its socket, i.e. never the case
  # that matters.
  if prove_reachable "$sock"; then
    LAST_OWNER_PID="$(socket_owner_pid "$sock")" || LAST_OWNER_PID=""
    # Something IS serving it, so "no owner" is not an available answer — it is a failed
    # lookup, and it fails closed.
    [[ -n "$LAST_OWNER_PID" ]] || LAST_OWNER_PID="unknown"
  fi
  # NO `else` CLEARING IT, deliberately. A vanished socket does not retract an owner captured
  # earlier — on a retry it is the only thing still known about that process. This function
  # runs again from the EXIT trap after a failed inter-arm stop, by which point the socket is
  # long gone; an else-branch reset made owner_gone pass on that second call and the sandbox be
  # deleted around the very daemon the first call had failed to account for. owner_gone clears
  # the state itself once the pid is CONFIRMED gone, which is the only correct place to.
  ${AT_ENV[@]+"${AT_ENV[@]}"} ATUIN_DAEMON__ENABLED=true \
    ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} "$ATUIN_BIN" daemon stop >/dev/null 2>&1
  if stop_settled "$sock" "$POLL_N"; then
    DAEMON_MAYBE_UP=0
    reap_manual
    return 0
  fi
  half=$((POLL_N / 2 + 1))
  # A daemon we started by hand: we hold its pid directly.
  if [[ -n "$MANUAL_DAEMON_PID" ]]; then
    for sig in TERM KILL; do
      kill "-$sig" "$MANUAL_DAEMON_PID" 2>/dev/null
      # A daemon WE started is accounted for by its own pid, so an unresolvable socket owner
      # is not an outstanding question here the way it is for a detached one.
      kill -0 "$MANUAL_DAEMON_PID" 2>/dev/null || [[ "$LAST_OWNER_PID" != unknown ]] || LAST_OWNER_PID=""
      if stop_settled "$sock" "$half"; then
        DAEMON_MAYBE_UP=0
        reap_manual
        return 0
      fi
    done
  fi
  # A detached one: the pid captured before the stop is the only thing that can still name it.
  if [[ -n "$LAST_OWNER_PID" ]]; then
    for sig in TERM KILL; do
      kill "-$sig" "$LAST_OWNER_PID" 2>/dev/null
      if stop_settled "$sock" "$half"; then
        DAEMON_MAYBE_UP=0
        reap_manual
        return 0
      fi
    done
  fi
  return 1
}

# ── the measurement ───────────────────────────────────────────────────────────
# One `atuin history start` under the sandbox env, capturing rc, stdout (the history id)
# and stderr, and the row delta it caused.
DB=""
# run_one <mode> <sock> <hook:yes|no> <settle_s> <poll_n> <dmode>
#   -> sets RUN_REC to "readok|rc|delta|idok|err" (5 fields, `|`-joined; err has | and
#      newlines stripped)
#
# A GLOBAL, NOT STDOUT, and that is load-bearing rather than stylistic. `line="$(run_one ...)"`
# runs the whole function in a COMMAND-SUBSTITUTION SUBSHELL, so every assignment it makes is
# discarded when that subshell exits — which silently defeated the process-group tracking
# below: TRACKED_PGIDS was appended to in the child and read as empty in the parent, so
# reap_tracked_groups had nothing to reap and the whole guard was inert. Anything run_one needs to
# tell the parent has to come back this way.
#
# ALL SIX REQUIRED, none optional. `settle` and `poll_n` used to be trailing defaults, and two
# optional trailing positionals of the same type is precisely how a caller ends up passing a
# poll count into the settle slot and waiting 100 seconds for one row.
#
# <dmode> is what the daemon env looks like:
#   off    ATUIN_DAEMON__ENABLED=false                  — the control arms
#   sock   ENABLED=true + SOCKET_PATH=<sock>            — the discard premise's unreachable arms
#   on     ENABLED=true, atuin's own default socket     — the manual-spawn control's write
#   auto   ENABLED=true + AUTOSTART=true, default sock  — the autostart premise's arms
#
# WHY `auto` AND `on` DO NOT FORCE ATUIN_DAEMON__SOCKET_PATH. With XDG_RUNTIME_DIR unset,
# atuin resolves its default socket under the sandbox data dir — the same expression
# _core_atuin_daemon_guard resolves, and specifically the macOS branch of it. Letting atuin
# pick therefore asserts socket-path AGREEMENT between client, daemon and guard for free, on
# exactly the machines this premise is about; pinning the path would withdraw that claim
# (bench-atuin-daemon.sh makes the same argument about its own forced-path mode).
#
# readok is NOT cosmetic. atuin_db_rows returns -1 when it cannot read the DB, and -1 is
# indistinguishable from a legitimate count in arithmetic: `after - before` with an
# unreadable `after` yields a NEGATIVE delta, which the verdict block would then read as
# "the row count changed" and report as `moved`. That is the design's central conflation
# pointing the other way — an apparatus failure rendered as a finding about upstream — so
# a failed read is flagged here and turned into `unmeasurable` by the caller. It also
# BREAKS the poll immediately: retrying a read that just spent SQLite's 30-second busy
# timeout, twenty times, is ten minutes of a scheduled job proving nothing.
run_one() {
  local mode="$1" sock="$2" hook="$3" settle="$4" poll_n="$5" dmode="$6"
  local before after rc end_rc id err idok=0 i
  local -a env_extra=() hookarg=()
  case "$dmode" in
  auto) env_extra=("ATUIN_DAEMON__ENABLED=true" "ATUIN_DAEMON__AUTOSTART=true") ;;
  on) env_extra=("ATUIN_DAEMON__ENABLED=true") ;;
  sock) env_extra=("ATUIN_DAEMON__ENABLED=true" "ATUIN_DAEMON__SOCKET_PATH=$sock") ;;
  *) env_extra=("ATUIN_DAEMON__ENABLED=false") ;;
  esac
  # --hook is what REAL SHELLS RUN: atuin's own `init zsh` emits
  # `atuin history start --hook -- "$1"` from _atuin_preexec. Measuring only the plain
  # form would measure a code path no shell in the fleet takes, so an upstream change
  # scoped to hook mode could break every prompt while this still reported `holds`.
  [[ "$hook" == yes ]] && hookarg=(--hook)
  before="$(atuin_db_rows "$DB")"
  ((before < 0)) && {
    RUN_REC='0|-1|-1|0|'
    return 0
  }
  # STDOUT TO A FILE, NOT A COMMAND SUBSTITUTION, and stdin from /dev/null. `id="$(…)"` reads
  # until PIPE EOF, not until the child exits — so a build whose client daemonizes without
  # reopening stdio would hand the write end of that pipe to a daemon that never exits, and
  # the substitution would block FOREVER. `timeout` cannot save it: it signals its direct
  # child, which has already returned, while the inherited fd holds the pipe open. The bound
  # at TIMEOUT_CMD exists precisely to stop a wedged atuin (atuinsh/atuin#3382) from hanging a
  # scheduled job with no verdict, and this was the one hole it did not cover. Costs nothing
  # on today's builds; the `--premise autostart` arms below spawn a daemon on purpose, which
  # is what turns this from theoretical into the likely first failure.
  # One definition per call, invoked through _tracked or directly, so the bounded foreground
  # form and the process-grouped form cannot drift apart.
  _start_call() {
    "${AT_ENV[@]}" "${env_extra[@]}" \
      "ATUIN_SESSION=$(printf '%032x' 1)" \
      ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} "$ATUIN_BIN" history start \
      ${hookarg[@]+"${hookarg[@]}"} -- "verify-$mode" \
      </dev/null >"$SB/out.$mode" 2>"$SB/err.$mode"
  }
  # _tracked <fn> — run <fn> in its OWN PROCESS GROUP and record the group id, so anything it
  # forks can be reaped later even if that child never binds a socket. atuin forks a daemon
  # this script is never told the PID of, and socket_owner_pid can only recover one that
  # actually BOUND — so a child that forks and then hangs, or dies, before binding is
  # invisible to every other teardown path there is: nothing answers the socket,
  # wait_unreachable succeeds instantly, DAEMON_MAYBE_UP is cleared, and the sandbox is
  # removed with that child still alive. `set -m` puts an asynchronous job in a new process
  # group, which makes the group id a handle on the whole tree rather than just the client.
  #
  # BOTH HALVES OF THE PAIR go through this under `auto`, not just `start`. atuin reaches its
  # daemon through the same autostarting path from `history end` as from `history start`, and
  # both run here with the same AUTOSTART env — so an `end` that forks its own never-binding
  # daemon would be untracked for exactly the same reason `start` was, and the fix would have
  # covered only the half that happened to be noticed first.
  #
  # WHAT THIS DOES AND DOES NOT COVER. TWO handles, and they are disjoint. A real atuin daemon
  # DETACHES (measured: arm group 88291, daemon group 88299), so the group never holds it —
  # the pid captured from the socket before the stop is what covers that one. The group covers
  # a child that forked and hung BEFORE binding while still in our group, which owns no socket
  # and so can never be looked up.
  #
  # THE RESIDUAL, stated exactly — because a scope claim that overclaims is the defect this
  # whole file exists to prevent, and the first version of this comment committed it. A child
  # that detached AND never bound is invisible to BOTH handles: it left the group via setsid,
  # and it owns no socket for an owner lookup to name it by. Trace it and every check passes —
  # socket_quiet_within succeeds because nothing ever bound, owner_gone succeeds because no
  # owner was ever captured, groups_quiet succeeds because the group really is empty. So the
  # stop is ACCEPTED, DAEMON_MAYBE_UP is cleared, and cleanup DELETES the sandbox while that
  # child is still running. It is not preserved. Nothing detects it, and the preserve path
  # below never fires for it — that path covers a stop that FAILED, not one that was never
  # asked the right question.
  #
  # A third handle for it existed briefly — matching processes by the sandbox path in their
  # environment — and was removed deliberately: exact only on Linux, a different mechanism on
  # macOS, and in two consecutive reviews the source of fail-open defects of its own (it read
  # "this platform cannot look" as "nothing is there", and the reap it required cleared the
  # very list the proof then consulted). Removing it traded a narrow, silent leak for a
  # broader class of silent WRONG ANSWERS, which is the right trade for this file. The leak is
  # the price, and it is named here rather than dressed up as a guarded failure.
  _tracked() {
    local _r
    set -m
    "$1" &
    _pgid=$!
    TRACKED_PGIDS="$TRACKED_PGIDS $_pgid"
    wait "$_pgid"
    _r=$?
    set +m
    return "$_r"
  }
  if [[ "$dmode" == auto ]]; then
    _tracked _start_call
    rc=$?
  else
    _start_call
    rc=$?
  fi
  # Newlines stripped rather than only the trailing one `$( )` would have eaten: is_history_id
  # demands exactly 32 hex characters, so any build that prints more than the bare id fails
  # the check either way — and joining the lines keeps a multi-line surprise visible in the
  # report instead of silently truncated to its first line.
  id="$(tr -d '\n' <"$SB/out.$mode" 2>/dev/null)"
  # PAIRED start+end WHENEVER A DAEMON IS SERVING, because that is when the row actually
  # lands. Measured on 18.19.0, in this sandbox: with the daemon OFF, `history start` INSERTs
  # the row immediately and `history end` updates it in place — the model scripts/lib/atuin-db.sh
  # encodes. With a daemon answering, `start` merely hands the in-flight command over and
  # NOTHING is written; the count moves only when `end` arrives. A start-only autostart arm
  # would therefore report a delta of 0 against a perfectly healthy daemon, and the verdict
  # block would render that as "autostart did not land the entry" — a false finding about the
  # two machines least able to absorb one. Pairing is also what a real shell does: atuin's own
  # `init zsh` calls start from _atuin_preexec and end from _atuin_precmd.
  #
  # Not done for the `sock` (unreachable) or `off` arms. `off` needs no partner — the row is
  # already in — and the discard premise has measured start-only since #366; changing what
  # those four arms issue would silently redefine the record they are compared against.
  if [[ "$dmode" == on || "$dmode" == auto ]] && is_history_id "$id"; then
    _end_call() {
      "${AT_ENV[@]}" "${env_extra[@]}" \
        ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} "$ATUIN_BIN" history end --exit 0 "$id" \
        </dev/null >/dev/null 2>>"$SB/err.$mode"
    }
    if [[ "$dmode" == auto ]]; then
      _tracked _end_call
    else
      _end_call
    fi
    end_rc=$?
    # THE PAIR'S STATUS, not just the opening half's. Under these two dmodes the row lands on
    # `end`, which makes `end` the verdict-bearing call — and discarding its status left a
    # BOUNDED `end` that timed out looking like a success: rc stayed at the `start`'s 0, the
    # row was missing, and the verdict block read that as "the entry did not land". An
    # apparatus limit filed as an upstream regression, arriving through the one door the
    # timeout guard below could not see, because the timeout never reached `rc`.
    ((rc == 0)) && rc=$end_rc
  fi
  # `|` stripped as well as newlines: this string is a FIELD in the record below, and an
  # stderr line containing a pipe would otherwise shift every field after it.
  err="$(tr -d '\n|' <"$SB/err.$mode" 2>/dev/null | cut -c1-200)"
  # A daemon-owned write can be committed slightly after the client returns, so give the
  # row a bounded moment to appear before concluding it never did. Bounded and short: the
  # expected delta here is 0, and waiting long for a 0 proves nothing, but NOT waiting at
  # all would manufacture a false `holds` on a build that writes asynchronously.
  # POLL COUNT IS THE CALLER'S, because the right bound inverts with the premise. 20 (2s) is
  # argued above for an arm whose expected delta is 0. An autostart arm expects 1, written by a
  # daemon cold-spawned milliseconds earlier and possibly still doing first-open migration work
  # on records.db/meta.db — bench gives its equivalent check 100 (10s) for exactly that. At 2s
  # on a loaded runner a healthy-but-slow daemon reports 0, and the verdict block would render
  # that as "autostart did not heal": a false finding, about the two machines least able to
  # afford one.
  after=-1
  for ((i = 0; i < poll_n; i++)); do
    after="$(atuin_db_rows "$DB")"
    ((after < 0)) && break
    ((after > before)) && break
    sleep 0.1
  done
  # SETTLE — only the drain arm passes this, and only the drain arm needs it. The poll above
  # breaks the instant the count goes UP, which is exactly right for an arm whose expected
  # delta is 0 but wrong for the one arm expecting 1: a build that replays a spool would very
  # plausibly commit this command's own row first and the spooled ones a moment later, and
  # breaking on the first increment would read that as a delta of 1 — the discard signature —
  # from the arm that exists to catch it. One sleep, once, on one arm: the four measurement
  # arms' timing is untouched.
  if [[ "$settle" != 0 ]] && ((after >= 0)); then
    sleep "$settle"
    after="$(atuin_db_rows "$DB")"
  fi
  ((after < 0)) && {
    RUN_REC="0|${rc}|-1|0|${err}"
    return 0
  }
  # A WELL-FORMED id, not merely a non-empty line. The premise this script measures says
  # atuin "prints a well-formed history id", and the shell then hands that id to
  # `history end` — an empty or malformed one is exactly what crashed 18.16.1. Warning
  # text on stdout would satisfy "non-empty" and produce a false `holds`. atuin emits
  # UUIDv7 in simple hex form: 32 lowercase hex digits, no dashes.
  is_history_id "$id" && idok=1
  RUN_REC="1|${rc}|$((after - before))|${idok}|${err}"
}

# record_arm <name> <expected-delta> <spawned:yes|no|na> — append one arm to the parallel
# arrays, reading the rc/delta/idok/err scalars run_one's caller has just parsed. Seven
# appends in step across two premises was the kind of thing that goes wrong silently: a
# forgotten ARM_EXPECT+= would leave the arrays a different length and the verdict loop would
# read an unset index under `set -u`. One writer, so they cannot drift.
record_arm() {
  ARM_NAME+=("$1")
  ARM_EXPECT+=("$2")
  ARM_SPAWN+=("$3")
  ARM_RC+=("$_rc")
  ARM_DELTA+=("$_delta")
  ARM_IDOK+=("$_idok")
  ARM_ERR+=("$_err")
}

# A history id as atuin actually emits one: UUIDv7 in 32-character simple-hex form. The
# premise is not "stdout was non-empty" — it is that the shell gets an id it can hand to
# `history end`, which is what 18.16.1's EMPTY id broke. A warning line, a deprecation
# notice or any other stray stdout would satisfy a mere -n test and produce `holds` for a
# build whose output would then fail in a real shell.
is_history_id() { [[ "$1" =~ ^[0-9a-f]{32}$ ]]; }

# ── premise: discard — {absent, stale} x {hook, plain}, nothing may be written ─
# FOUR arms, not two. --hook is the form atuin's own `init zsh` emits from _atuin_preexec,
# i.e. the only one a real shell in this fleet ever runs; the plain form is what #366 measured
# and what keeps this comparable to that record. An upstream change scoped to hook mode would
# break every prompt while a plain-only detector still said `holds`, and a hook-only detector
# would lose the tie to the original measurement — so both, and `holds` requires all four.
arms_discard() {
  local shape sock hook h
  for shape in absent stale; do
    case "$shape" in
    absent)
      sock="$LOCALDIR/absent.sock"
      ;;
    stale)
      sock="$LOCALDIR/stale.sock"
      make_stale "$sock" || {
        unmeasurable "could not manufacture a stale socket file — the shape a crashed daemon leaves is half of what the guard claims to catch, and an unmeasured half is not a pass"
        return 1
      }
      ;;
    esac
    prove_unreachable "$sock" || {
      unmeasurable "the ${shape} socket is not actually unreachable — something answered a connect, so a row delta of zero here would mean 'the daemon took it', not 'atuin discarded it'"
      return 1
    }
    for hook in hook plain; do
      h=no
      [[ "$hook" == hook ]] && h=yes
      run_one "${shape}-${hook}" "$sock" "$h" 0 20 sock
      IFS='|' read -r _ok _rc _delta _idok _err <<<"$RUN_REC"
      [[ "$_ok" == 1 ]] || {
        unmeasurable "the ${shape}/${hook} arm could not read the history DB (row count -1) — an unreadable DB is an apparatus failure, not evidence that upstream changed"
        return 1
      }
      record_arm "${shape}_${hook}" 0 na
    done
  done
  return 0
}

# ── premise: autostart — the same two shapes, but a daemon MUST appear ────────
# The guard stands down entirely under ATUIN_DAEMON__AUTOSTART on the premise that atuin
# supervises its own daemon. This measures that. `stale` is the load-bearing shape: every
# `atuin history start` is a fresh process, so "fire-and-forget" cannot mean "the client stops
# checking" — it can only mean that a dead daemon's leftover socket inode defeats the spawn,
# which is precisely what a crashed daemon leaves behind on Alpine and macOS.
arms_autostart() {
  local shape hook h rc

  SOCK="$SB/.local/share/atuin/atuin.sock"
  # AF_UNIX sun_path caps near 108 bytes, and a bind past it fails with a diagnostic that
  # looks nothing like "your path is too long" — it looks like a daemon that would not start,
  # i.e. like a finding. Nothing in this script bound a socket until this premise existed, so
  # the check did not either; /tmp was already chosen over $TMPDIR for the same reason.
  if ((${#SOCK} > 100)); then
    unmeasurable "the sandbox socket path is ${#SOCK} bytes, at or past the AF_UNIX sun_path limit — no daemon could bind here, which is this box's directory layout rather than anything about atuin"
    return 1
  fi

  daemon_probe_argv
  rc=$?
  if ((rc == 1)); then
    unmeasurable "this atuin has no 'daemon start' subcommand, so the manual-spawn control cannot run — and without that control, 'autostart did not spawn a daemon' and 'this box cannot host a daemon' are the same observation, neither of which may be reported as a finding about upstream"
    return 1
  elif ((rc == 2)); then
    unmeasurable "this atuin has 'daemon start' but no 'daemon stop', so a daemon spawned here could not be reliably stopped — refusing to start one at all, because a daemon left writing into a sandbox this run is about to delete is worse than an unmeasured premise"
    return 1
  fi

  # ── manual-spawn control A: can this box host a daemon AT ALL? ──────────────
  # The discriminator. Everything below it is only interpretable because this passed.
  rm -f "$SOCK"
  daemon_start_manual "$SOCK" || {
    unmeasurable "a daemon started by hand ('atuin ${AT_DAEMON_ARGV[*]}') never answered on ${SOCK} — this sandbox cannot host a daemon, so nothing here can be said about whether autostart would have started one. An apparatus limit, not a finding"
    return 1
  }
  # CAN THIS BOX NAME THE OWNER OF A SOCKET? The arms spawn daemons that DETACH, so the pid
  # captured before a stop is the only handle on them — and without it no stop could ever be
  # proven, leaving four unreapable daemons behind a run that then refuses to delete its own
  # sandbox. Same rule as the `daemon stop` probe, applied one layer down: do not start what
  # you cannot prove you can stop. Checked HERE, against a daemon whose pid we do hold, so
  # declining costs one controlled teardown and nothing else.
  if ! socket_owner_pid "$SOCK" >/dev/null 2>&1; then
    reap_manual
    reap_tracked_groups
    DAEMON_MAYBE_UP=0
    rm -f "$SOCK"
    unmeasurable "a daemon is answering on ${SOCK} and this box cannot say which process owns it (no lsof, or an unreadable /proc) — an autostart daemon DETACHES, so that pid is the only way a stop could ever be proven, and spawning four of them here would leave daemons this run could not reap"
    return 1
  fi
  run_one spawnctl "$SOCK" no 1 "$POLL_N" on
  IFS='|' read -r _ok _rc SPAWN_CTL_DELTA _idok _err <<<"$RUN_REC"
  if [[ "$_ok" != 1 ]] || ((SPAWN_CTL_DELTA != 1)); then
    unmeasurable "with a hand-started daemon up and answering, a write landed ${SPAWN_CTL_DELTA} rows rather than 1 (readok=${_ok}) — the daemon-backed write path does not work in this sandbox, so an autostart arm landing no row would prove nothing about autostart"
    return 1
  fi
  daemon_stop_proven "$SOCK" || {
    unmeasurable "the hand-started daemon could not be stopped, even after SIGKILL — refusing to continue, because every arm below needs a proven-dead starting state and the sandbox is about to be deleted"
    return 1
  }
  rm -f "$SOCK"

  # ── manual-spawn control B: can a daemon bind OVER a stale socket? ──────────
  # RECORDED, NOT GATED, and that distinction is the whole point of this arm. If the stale
  # autostart arms below fail, three explanations survive: the client will not re-spawn after
  # a crash (the finding Alpine and macOS need), the daemon itself cannot bind over a leftover
  # inode (a real finding too, but in a different layer and a different bug to file), or the
  # apparatus made an inode nothing could unlink. This separates the second from the first.
  make_stale "$SOCK" || {
    unmeasurable "could not manufacture a stale socket file for the bind control — the stale shape is the load-bearing half of this premise, and an unmeasured half is not a pass"
    return 1
  }
  if daemon_start_manual "$SOCK"; then
    SPAWN_CTL_STALE_OK=yes
  else
    SPAWN_CTL_STALE_OK=no
  fi
  daemon_stop_proven "$SOCK" || {
    unmeasurable "the daemon from the stale-bind control could not be stopped, even after SIGKILL — refusing to continue with a live daemon on the socket the arms below depend on being dead"
    return 1
  }
  rm -f "$SOCK"

  # ── the matrix, each arm from a PROVEN-dead start ───────────────────────────
  for shape in absent stale; do
    for hook in hook plain; do
      # TEARDOWN FIRST, PROVEN, EVERY TIME. The previous arm spawned a daemon on THIS SAME
      # path — the arms deliberately share atuin's default socket rather than forcing one
      # each — so without a proven stop, arm N+1 starts against a healthy daemon, measures
      # nothing, and reports a spawn it did not cause.
      daemon_stop_proven "$SOCK" || {
        unmeasurable "the daemon from the previous arm is still answering on ${SOCK} — the arms share one socket path, so an unproven stop means the next arm's starting state is not ours to claim"
        return 1
      }
      # ORDER IS LOAD-BEARING: the stop is proven BEFORE the unlink. prove_unreachable returns
      # 0 for a path that does not exist, so unlinking first would make "the daemon stopped"
      # and "the file is gone" the same observation, and the gate below would pass for free.
      rm -f "$SOCK"
      if [[ "$shape" == stale ]]; then
        make_stale "$SOCK" || {
          unmeasurable "could not manufacture a stale socket file for the ${shape}/${hook} arm — the shape a crashed daemon leaves is the load-bearing half of this premise"
          return 1
        }
      fi
      prove_unreachable "$SOCK" || {
        unmeasurable "the ${shape} socket was already reachable before the ${hook} arm ran — something answered a connect, so a daemon being there afterwards would say nothing about whether autostart started one"
        return 1
      }
      h=no
      [[ "$hook" == hook ]] && h=yes
      # Set BEFORE the call, not after: from the instant atuin is invoked with AUTOSTART it
      # may have forked a daemon, and a run killed between here and the next line must still
      # reach the teardown path in cleanup().
      DAEMON_MAYBE_UP=1
      run_one "auto-${shape}-${hook}" "$SOCK" "$h" 1 "$POLL_N" auto
      IFS='|' read -r _ok _rc _delta _idok _err <<<"$RUN_REC"
      [[ "$_ok" == 1 ]] || {
        unmeasurable "the ${shape}/${hook} arm could not read the history DB (row count -1) — an unreadable DB is an apparatus failure, not evidence about upstream"
        return 1
      }
      # A short wait, not the full 10s: if the row landed the daemon is certainly up already,
      # and this only has to catch the narrow "daemon came up but the entry did not land"
      # case without adding ten seconds to every arm of a build that spawns nothing.
      if wait_reachable "$SOCK" "$((POLL_N < 30 ? POLL_N : 30))"; then
        record_arm "${shape}_${hook}" 1 yes
      else
        record_arm "${shape}_${hook}" 1 no
      fi
    done
  done

  daemon_stop_proven "$SOCK" || {
    unmeasurable "the last arm's daemon could not be stopped, even after SIGKILL — the closing control arm below writes through a direct client, and its number cannot be trusted while a daemon still holds the DB"
    return 1
  }
  rm -f "$SOCK"
  # Safe now, and only now. The closing control's delta is a verdict-bearing number read by a
  # direct client, and scripts/lib/atuin-db.sh's rule is that a checkpoint is only ever safe
  # where NO daemon holds the file open — asking for one mid-arm would pick a lock fight with
  # the very process under measurement.
  atuin_db_checkpoint "$DB"
  return 0
}

measure() {
  have python3 || {
    unmeasurable "python3 is not installed — the row count is what the whole verdict rests on"
    return
  }
  [[ -n "$ATUIN_BIN" ]] || ATUIN_BIN="$(command -v atuin 2>/dev/null)"
  [[ -n "$ATUIN_BIN" && -x "$ATUIN_BIN" ]] || {
    unmeasurable "no executable atuin to measure (looked for --atuin, then PATH)"
    return
  }
  # BOUNDING THE CALL, PORTABLY. macOS ships coreutils' timeout as `gtimeout` and has no
  # plain `timeout` at all — maint/dotfiles-maint.sh's _to() exists for exactly this — so a
  # hard requirement on `timeout` would make this script permanently `unmeasurable` on the
  # macOS third of the fleet, which is a broken detector rather than a cautious one.
  # Where neither exists we still measure, unbounded, and SAY SO: the bound guards against
  # a wedged atuin (the accept-but-silent shape of atuinsh/atuin#3382) hanging a scheduled
  # job, which is a real but narrow hazard — narrower than never measuring at all.
  # `${arr[@]+"${arr[@]}"}`, not `"${arr[@]}"`: macOS ships bash 3.2, where expanding an
  # EMPTY array under `set -u` is an "unbound variable" error rather than zero words.
  # --foreground WHERE SUPPORTED, and not as a nicety. GNU timeout puts the command it runs
  # into a NEW PROCESS GROUP of its own, so that it can signal the whole group on expiry —
  # which means atuin and everything it forks land in timeout's group, not in the group the
  # autostart arm created. `kill -- -$pgid` then reaches the subshell and timeout and nothing
  # else, and the whole process-group teardown silently reaps nothing. (Measured: arm group
  # 15189, forked child's group 15194.) `--foreground` suppresses that regrouping.
  #
  # What it gives up is timeout's own group-kill on expiry — it then signals only its direct
  # child. That is covered here and was not covered before: reap_tracked_groups kills the arm's
  # group at cleanup, so a grandchild that outlives an expired bound is caught either way.
  # Probed rather than assumed, because busybox timeout has no such flag (and does not
  # regroup, so it needs none) — the same reason the gtimeout branch exists at all.
  if have timeout; then
    TIMEOUT_CMD=(timeout "$TIMEOUT_S")
    timeout --foreground 1 true >/dev/null 2>&1 && TIMEOUT_CMD=(timeout --foreground "$TIMEOUT_S")
  elif have gtimeout; then
    TIMEOUT_CMD=(gtimeout "$TIMEOUT_S")
    gtimeout --foreground 1 true >/dev/null 2>&1 && TIMEOUT_CMD=(gtimeout --foreground "$TIMEOUT_S")
  else
    TIMEOUT_CMD=()
    BOUNDED=false
  fi
  local akey arc
  akey="$(anchor_key)"
  read_anchor "$akey"
  arc=$?
  if ((arc == 3)); then
    unmeasurable "zsh/00-tools.zsh has a '# ${akey}=' line whose value is not an X.Y.Z version — a malformed anchor is not the same as an absent one, and this run will not silently treat it as unanchored"
    return
  elif ((arc == 2)); then
    unmeasurable "zsh/00-tools.zsh states '# ${akey}=' more than once — the file disagrees with itself about what was measured, and a detector that picks one of two contradictory anchors is worse than one that declines"
    return
  elif ((arc == 1)); then
    if [[ "$PREMISE" == autostart ]]; then
      ANCHOR=none
      ANCHOR_REL=unanchored
    else
      unmeasurable "could not read a '# ${akey}=' line from zsh/00-tools.zsh — the anchor was renamed or deleted"
      return
    fi
  fi

  # Bounded by the SAME per-call timeout as the measurement arms. This is the FIRST call the
  # script makes into the binary under test, so an atuin wedged the way atuinsh/atuin#3382
  # wedges one hung here — before any arm ran — until the scheduled job's own 15-minute
  # timeout killed it, producing no verdict at all rather than the promised `unmeasurable`.
  # A timed-out or empty result falls through to AT_VER=unknown, which the anchor comparison
  # below already handles, so the bound costs nothing when the binary is healthy.
  AT_VER="$(${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} "$ATUIN_BIN" --version 2>/dev/null |
    grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"
  [[ -n "$AT_VER" ]] || AT_VER="unknown"
  # `none` is not a version, so it is not compared: ANCHOR_REL stays `unanchored` and the
  # report leads with "this may be the first measurement of this premise rather than a change
  # in it" — which is a different finding, with a different remedy, from a premise that moved.
  if [[ "$AT_VER" != unknown && "$ANCHOR" != none ]]; then
    case "$(ver_cmp "$AT_VER" "$ANCHOR")" in
    0) ANCHOR_REL=same ;;
    1) ANCHOR_REL=newer ;;
    *) ANCHOR_REL=older ;;
    esac
  fi

  # /tmp, not $TMPDIR: AF_UNIX sun_path caps near 108 bytes and macOS's TMPDIR is long
  # enough on its own to blow that — the same reason bench-atuin-daemon.sh hardcodes /tmp.
  # The $RUN_TAG component is what makes this tree attributable to THIS run in a directory
  # every other run also writes to — see the CORE_ATVERIFY_TAG block near the top.
  LOCALDIR="$(mktemp -d "/tmp/atverify.${RUN_TAG}.XXXXXX")" || {
    unmeasurable "could not create a sandbox under /tmp"
    return
  }
  SB="$LOCALDIR/home"
  mkdir -p "$SB/.config/atuin" "$SB/.local/share" || {
    unmeasurable "could not build the sandbox tree"
    return
  }

  # MANDATORY, not hygiene: atuin/config.toml leaves [daemon] enabled/autostart UNSET on
  # purpose, because atuin layers the config FILE after the Environment source, so any key
  # written there SHADOWS its ATUIN_* override. Without Core's real config in place, an
  # ATUIN_DAEMON__ENABLED=true below would be silently ignored, every arm would measure the
  # daemon-OFF path, and the run would report a confident, entirely false `moved`.
  cp atuin/config.toml "$SB/.config/atuin/config.toml" 2>/dev/null || {
    unmeasurable "could not copy atuin/config.toml into the sandbox — without it the daemon env override is shadowed and every arm measures the wrong path"
    return
  }

  # env -i, not merely HOME=: anything we do not name — ATUIN_CONFIG_DIR, ATUIN_DB_PATH, a
  # stray ATUIN_DAEMON__* from the caller's shell — would otherwise reach atuin and could
  # point it at the developer's real files. XDG_RUNTIME_DIR is deliberately UNSET so atuin
  # resolves its default socket under the sandbox data dir rather than the real /run/user.
  AT_VARS=(
    "PATH=$PATH"
    "HOME=$SB"
    "XDG_DATA_HOME=$SB/.local/share"
    "XDG_CONFIG_HOME=$SB/.config"
    "XDG_CACHE_HOME=$SB/.cache"
    "XDG_STATE_HOME=$SB/.local/state"
    "TERM=dumb"
  )
  AT_ENV=(env -i "${AT_VARS[@]}")
  DB="$SB/.local/share/atuin/history.db"

  # SEED WITH THE DAEMON OFF. This is the fix for the exact bug the earlier recipe had:
  # seeding through the unreachable-daemon path means that on a build which discards, the DB
  # is never created at all, and every later count reads 0 — which then looks like "the rows
  # did not land", i.e. the premise holding, from an apparatus that never worked.
  "${AT_ENV[@]}" ATUIN_DAEMON__ENABLED=false "ATUIN_SESSION=$(printf '%032x' 0)" \
    ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} "$ATUIN_BIN" history start -- "verify-seed" >/dev/null 2>&1
  [[ -s "$DB" ]] || {
    unmeasurable "the daemon-off seed did not create a history DB at all — this atuin cannot write in the sandbox, so nothing measured here would mean anything"
    return
  }
  atuin_db_checkpoint "$DB"

  # ── control arm: daemon OFF must write exactly one row ──────────────────────
  # Plain (no --hook) on purpose: this arm proves the APPARATUS can write, and keeping it
  # on the same form the original #366 measurement used keeps the two comparable.
  run_one control "" no 0 20 off
  IFS='|' read -r _ok _rc CTL_DELTA _idok _err <<<"$RUN_REC"
  if [[ "$_ok" != 1 || "$CTL_DELTA" != 1 ]]; then
    unmeasurable "the daemon-OFF control arm wrote ${CTL_DELTA} rows, not 1 — the apparatus cannot be trusted, so neither can any verdict drawn from it (readok=${_ok}: 0 means the history DB could not be read at all; a delta other than 1 means this atuin's per-command row model is not the one this script encodes)"
    return
  fi

  # ── the premise-specific matrix ─────────────────────────────────────────────
  # Everything above is shared: the same preflight, the same sandbox, the same opening
  # control. Everything below differs, so each premise's argument lives in one readable block
  # rather than interleaved behind conditionals. Both set `unmeasurable` themselves and
  # return 1, so the caller never has to guess whether a verdict was already reached.
  if [[ "$PREMISE" == autostart ]]; then
    arms_autostart || return
  else
    arms_discard || return
  fi

  # ── closing control arm: daemon OFF must STILL write exactly one row ────────
  # Two jobs the opening control cannot do, and the second is why #383 asked for it.
  #
  # (a) It proves the apparatus was still writable AFTER the arms ran. The opening control
  #     proves it at t=0 only, and a DB that goes UNWRITABLE mid-run still READS fine — so
  #     `readok` never fires, all four arms report a delta of 0, and the run reports `holds`
  #     from an apparatus that had quietly stopped working. That is the same
  #     apparatus-versus-upstream conflation the opening control exists to prevent, one step
  #     further along the timeline.
  #
  # (b) It is the cheapest probe of the ONE-WAY-DEGRADE premise (zsh/00-tools.zsh). Core
  #     degrades a shell PERMANENTLY on the first failed connect specifically because atuin
  #     is DISCARDING during the outage, so degrading early is still correct. If atuin ever
  #     buffers and replays instead, that reasoning INVERTS and one-way becomes the wrong
  #     default — and the four arms cannot see the difference, because a spooled entry and a
  #     discarded one both leave the row count at 0 while the socket is unreachable. A build
  #     that spools the four and flushes them on the next successful write lands HERE as a
  #     delta of 5, not 1. A delta of exactly 1 does not DISPROVE buffering — a spool only a
  #     live daemon would drain is out of reach without spawning one — and the report says so
  #     rather than implying coverage.
  #
  # Plain, no --hook, matching the opening control: this arm measures the apparatus, and
  # keeping the two controls on the same form makes their deltas directly comparable.
  run_one drain "" no 1 20 off
  IFS='|' read -r _ok _rc DRAIN_DELTA _idok _err <<<"$RUN_REC"
  if [[ "$_ok" != 1 ]] || ((DRAIN_DELTA < 1)); then
    unmeasurable "the CLOSING daemon-off control arm wrote ${DRAIN_DELTA} rows, not 1 — the apparatus stopped writing partway through this run, so the zeros the four arms reported are not evidence about upstream (readok=${_ok}: 0 means the history DB could not be read at all)"
    return
  fi

  # ── the verdict ─────────────────────────────────────────────────────────────
  # `holds` is the CONJUNCTION of every property zsh/00-tools.zsh claims, on every arm.
  # Written as an explicit list of failures rather than one boolean, so the report can say
  # WHICH property moved on WHICH arm — "it changed" is not actionable, and the remedy
  # differs depending on whether it now errors, now writes, or now says something.
  local -a diffs=()
  local n
  for ((n = 0; n < ${#ARM_NAME[@]}; n++)); do
    local a="${ARM_NAME[n]//_/ }"
    # A HIT BOUND IS NOT A FINDING. Three statuses, not one, because the expiry status is NOT
    # one number across this fleet: GNU coreutils reports 124, BUSYBOX reports its SIGTERM as
    # 143, and an escalation to SIGKILL surfaces as 137. This repo has already paid for that
    # difference once — scripts/test-core.sh's `_to` case documents a 124-only gate that
    # passed everywhere except Alpine — and Alpine is one of the two machines THIS premise
    # exists to protect, so a 124-only gate here would go wrong exactly where it matters most.
    # The plain `rc != 0` test below rendered any of them as
    # "exit code is 124, was 0" — an APPARATUS LIMIT dressed up as an upstream change, filed
    # under a title that says the premise moved. That is the exact conflation the control arms
    # exist to prevent, arriving through the one door they do not watch. A call that never
    # returns is still a real observation (it is atuinsh/atuin#3382's shape), so it is named
    # rather than swallowed — but as `unmeasurable`, which is what "we could not tell" means.
    case "${ARM_RC[n]}" in
    124 | 137 | 143)
      unmeasurable "the ${a} arm did not return within CORE_ATVERIFY_TIMEOUT=${TIMEOUT_S}s and was killed (rc ${ARM_RC[n]}; GNU reports expiry as 124, busybox as 143, an escalated SIGKILL as 137) — a wedged atuin is the accept-but-silent shape of atuinsh/atuin#3382, not evidence that the premise moved, so this run measured nothing rather than found something"
      return
      ;;
    esac
    [[ "${ARM_RC[n]}" == 0 ]] || diffs+=("${a}: exit code is ${ARM_RC[n]}, was 0")
    if [[ "$PREMISE" == autostart ]]; then
      # THE SPAWN IS THE PREMISE. Checked before the delta, because it is the more specific
      # observation: a delta of 0 is what "no daemon came up" and "a daemon came up and threw
      # the entry away" both look like, and those are different upstream bugs. Naming the
      # spawn first means the report says which one happened.
      [[ "${ARM_SPAWN[n]}" == yes ]] ||
        diffs+=("${a}: no daemon became reachable on the socket — atuin did NOT start one, so an absent socket is now a fault rather than a cue, and the guard's stand-down leaves this shape unprotected")
      [[ "${ARM_DELTA[n]}" == "${ARM_EXPECT[n]}" ]] ||
        diffs+=("${a}: the row count changed by ${ARM_DELTA[n]}, expected ${ARM_EXPECT[n]} — the entry issued while the socket was unreachable did not land")
      # NO stderr rule here, deliberately. The daemon atuin spawns INHERITS this process's
      # fd 2, so its startup tracing lands in the same capture as the client's — asynchronously,
      # and possibly after the read. "The client complained" and "the daemon logged" are not
      # separable through an inherited descriptor, so asserting silence would turn an apparatus
      # artefact into a finding about upstream. Reported in the table, never in the verdict.
    else
      [[ "${ARM_DELTA[n]}" == "${ARM_EXPECT[n]}" ]] ||
        diffs+=("${a}: the row count changed by ${ARM_DELTA[n]}, was ${ARM_EXPECT[n]} (it no longer discards)")
      [[ -z "${ARM_ERR[n]}" ]] || diffs+=("${a}: it now writes to stderr — \"${ARM_ERR[n]}\"")
    fi
    [[ "${ARM_IDOK[n]}" == 1 ]] || diffs+=("${a}: stdout is not a well-formed history id (32 hex digits), and a malformed id is what crashed \`history end\` on 18.16.1")
  done
  # The drain arm reads as a `moved` finding only ABOVE 1 — below it is an apparatus failure
  # and was already turned into `unmeasurable` above. Routed through the same `diffs` list as
  # the arms so the "say WHICH property moved" reporting is reused rather than forked, and so
  # a run where both the arms AND the drain moved reports both.
  if ((DRAIN_DELTA != 1)); then
    if [[ "$PREMISE" == autostart ]]; then
      diffs+=("drain: the daemon-off write that closed the run landed ${DRAIN_DELTA} rows, not 1 — the autostart arms' own entries had already landed, so a surplus row here means something was withheld during the run and flushed into this write")
    else
      diffs+=("drain: the first successful write after four unreachable ones landed ${DRAIN_DELTA} rows, not 1 — this atuin BUFFERS and replays rather than discarding, which INVERTS the premise the one-way degrade in zsh/00-tools.zsh rests on")
    fi
  fi

  if ((${#diffs[@]})); then
    local joined="" d
    for d in "${diffs[@]}"; do joined+="; $d"; done
    moved "${joined#; }"
  else
    VERDICT=holds
    if [[ "$PREMISE" == autostart ]]; then
      # Says WHY four single-command arms amount to fleet coverage, because that inference is
      # the whole load-bearing step and it is not self-evident: atuin's client is a fresh
      # process per command, so "does a fresh client spawn a daemon when the socket is
      # unreachable" IS the self-healing mechanism, not a proxy for it. Scoped to what ran —
      # a shell whose daemon dies mid-session is still out of reach here.
      REASON="all ${#ARM_NAME[@]} arms ($(arms_sentence)) started a daemon that answered on the socket and landed exactly 1 row from an unreachable start — including the stale-socket shape a crashed daemon leaves behind. Every \`atuin history start\` is a fresh process, so per-command spawn IS the self-healing mechanism, and the stand-down in zsh/00-tools.zsh still has something behind it on Alpine and macOS"
    else
      # Scoped to what the closing arm actually established. "Nothing was spooled" would be the
      # same overclaim this run's scope paragraph exists to prevent: a delta of 1 rules out a
      # spool that a daemon-off write DRAINS, and says nothing about one only a live daemon would.
      REASON="all ${#ARM_NAME[@]} arms ($(arms_sentence)) still exit 0, print a well-formed id, stay silent on stderr, and discard the entry — and the daemon-off write that followed them landed exactly 1 row, so nothing was replayed into it"
    fi
  fi
}

# ── render ────────────────────────────────────────────────────────────────────
# What this run actually measured, DERIVED from ARM_NAME rather than written out beside the
# loop that fills it. Both prose claims about coverage — the `holds` reason and the report —
# read from here, because a hand-written coverage claim is a second copy of the matrix and the
# second copy is the one that rots: the arm list was extended to four in review, and the
# report's scope paragraph went on saying `--hook` was not exercised while two hook arms ran,
# in the same output as a reason that said "all four arms (absent/stale x hook/plain)".
# An empty list is a legitimate answer — an `unmeasurable` run measured nothing, and saying
# that is more useful than inheriting a list from a run that did.
arms_sentence() {
  local n out=""
  ((${#ARM_NAME[@]})) || {
    printf 'nothing — no arm ran'
    return
  }
  for ((n = 0; n < ${#ARM_NAME[@]}; n++)); do out+=", ${ARM_NAME[n]//_/ / }"; done
  printf '%s' "${out#, }"
}

json_escape() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null; }

emit_json() {
  # `premise` FIRST, and not merely for tidiness: the arm names are identical across the two
  # premises while their pass conditions are opposites, so this field is the only thing that
  # tells a reader whether `"delta":1` is the healthy answer or the finding. The workflow
  # reads it back to pick which issue title to file under.
  printf '{"premise":"%s","verdict":"%s","reason":"%s","atuin_version":"%s","host":"%s","anchor":"%s","anchor_relation":"%s",' \
    "$PREMISE" "$VERDICT" "$(json_escape "$REASON")" "$AT_VER" "$HOST_KIND" "$ANCHOR" "$ANCHOR_REL"
  printf '"control_delta":%s,"drain_delta":%s,"spawn_control_delta":%s,"spawn_control_stale":"%s","bounded":%s,"arms":{' \
    "${CTL_DELTA:--1}" "${DRAIN_DELTA:--1}" "${SPAWN_CTL_DELTA:--1}" "$SPAWN_CTL_STALE_OK" "$BOUNDED"
  local n first=1
  for ((n = 0; n < ${#ARM_NAME[@]}; n++)); do
    ((first)) || printf ','
    first=0
    printf '"%s":{"rc":%s,"delta":%s,"expected_delta":%s,"spawned":"%s","stderr_empty":%s,"id_wellformed":%s}' \
      "${ARM_NAME[n]}" "${ARM_RC[n]}" "${ARM_DELTA[n]}" "${ARM_EXPECT[n]}" "${ARM_SPAWN[n]}" \
      "$([[ -z "${ARM_ERR[n]}" ]] && echo true || echo false)" \
      "$([[ "${ARM_IDOK[n]}" == 1 ]] && echo true || echo false)"
  done
  printf '}}\n'
}

# shellcheck disable=SC2016  # the backticks below are MARKDOWN code spans in the report,
# not command substitution — single quotes are exactly right for a printf format string.
emit_report() {
  # No title heading: .github/workflows/file-routine-issue.sh supplies one, and a second
  # would nest under it. Issue-ready markdown, so a human can act without opening the run.
  {
    printf '**Verdict: `%s`** (premise: `%s`)\n\n%s\n\n' "$VERDICT" "$PREMISE" "$REASON"
    printf '| | |\n| --- | --- |\n'
    printf '| atuin measured | `%s` |\n' "$AT_VER"
    printf '| measured on | `%s` |\n' "$HOST_KIND"
    printf '| verified-against anchor (`# %s=` in `zsh/00-tools.zsh`) | `%s` (%s) |\n' \
      "$(anchor_key)" "$ANCHOR" "$ANCHOR_REL"
    printf '| daemon-off control arm (opening) | wrote %s row(s) — must be 1 |\n' "$CTL_DELTA"
    if [[ "$PREMISE" == autostart ]]; then
      # The two controls that make an autostart finding attributable. Printed even when they
      # passed, because their VALUE is what lets a reader rule out "the box could not host a
      # daemon" without re-running anything.
      printf '| manual-spawn control (`atuin %s`) | wrote %s row(s) — must be 1; this is the arm that separates "autostart did not spawn" from "this box cannot host a daemon" |\n' \
        "${AT_DAEMON_ARGV[*]:-daemon start}" "$SPAWN_CTL_DELTA"
      printf '| manual-spawn control, over a **stale** socket | `%s` — can the daemon bind over a leftover inode *by itself*? `no` is not a fault on its own: on 18.19.0 the daemon refuses with `Address already in use` while the autostart **client** unlinks the inode first, so `no` here beside spawning stale arms below means the client is doing the healing. It is what a FAILING stale arm needs read against — `no` says that client-side unlink is the whole mechanism and has regressed; `yes` says the daemon could have bound anyway. |\n' \
        "$SPAWN_CTL_STALE_OK"
    fi
    printf '| daemon-off control arm (closing) | wrote %s row(s) — must be 1; above 1 means entries were withheld during the run and flushed into it |\n' "$DRAIN_DELTA"
    [[ "$BOUNDED" == true ]] ||
      printf '| call bound | **none** — no `timeout`/`gtimeout` on this box, so a wedged atuin could not have been cut short |\n'
    local n
    for ((n = 0; n < ${#ARM_NAME[@]}; n++)); do
      if [[ "$PREMISE" == autostart ]]; then
        printf '| %s | daemon reachable after: **%s**, delta %s (expected %s), rc %s, id %s, stderr %s |\n' \
          "${ARM_NAME[n]//_/ / }" "${ARM_SPAWN[n]}" "${ARM_DELTA[n]}" "${ARM_EXPECT[n]}" "${ARM_RC[n]}" \
          "$([[ "${ARM_IDOK[n]}" == 1 ]] && echo well-formed || echo MALFORMED)" \
          "$([[ -z "${ARM_ERR[n]}" ]] && echo empty || echo "\"${ARM_ERR[n]}\" (client + daemon, not separable — not judged)")"
      else
        printf '| %s | rc %s, delta %s, stderr %s, id %s |\n' \
          "${ARM_NAME[n]//_/ / }" "${ARM_RC[n]}" "${ARM_DELTA[n]}" \
          "$([[ -z "${ARM_ERR[n]}" ]] && echo empty || echo "\"${ARM_ERR[n]}\"")" \
          "$([[ "${ARM_IDOK[n]}" == 1 ]] && echo well-formed || echo MALFORMED)"
      fi
    done
    printf '\n'
    case "${PREMISE}/${VERDICT}" in
    discard/moved)
      printf 'The premise `_core_atuin_daemon_guard` rests on has changed, so the rationale block in `zsh/00-tools.zsh` is now overclaiming. Decide deliberately whether the guard should be **retired**, **version-gated**, or **reshaped** — and weigh it as an eight-repo change: retiring it removes a `precmd` hook from every interactive shell in the fleet. Re-measure by hand before deciding; do not act on this report alone.\n\n'
      printf 'If the premise is genuinely gone, the anchor line `# CORE_ATUIN_GUARD_VERIFIED_AGAINST=` in `zsh/00-tools.zsh` should only move as part of that decision — editing it is a claim that the premise was re-measured, not a version bump.\n\n'
      ;;
    autostart/moved)
      printf 'The premise the `ATUIN_DAEMON__AUTOSTART` stand-down rests on did not hold in this run. That stand-down covers **Alpine and macOS**, and on those two machines it is the **only** mitigation: `_core_atuin_daemon_guard` unhooks itself from `precmd_functions` and never probes at all.\n\n'
      [[ "$ANCHOR_REL" == unanchored ]] &&
        printf 'There is no `# CORE_ATUIN_AUTOSTART_VERIFIED_AGAINST=` line in `zsh/00-tools.zsh`, so this may be the **first measurement of this premise rather than a change in it**. If so the finding is that those two machines have been unprotected all along — a different thing from an upstream regression, with a different urgency. Weigh it as that before reaching for a version gate.\n\n'
      # THE TRAP, NAMED. The obvious remedy is the one that breaks the two machines this
      # premise is about, and a report that let a reader reach for it would do more damage
      # than the finding it is reporting.
      printf 'Do **not** reach for "make the guard stop standing down" as a reflex. Its degrade path exports `ATUIN_DAEMON__ENABLED=false`, and under `autostart` that removes the spawn itself — permanently defeating the only launcher Alpine and macOS have, which is the very outcome the stand-down exists to avoid. The remedies that do not cost those machines their history are: **probe but warn instead of disabling**; **stand down only after N consecutive failed spawns**; or **unlink a stale socket before deferring to autostart**. Re-measure by hand before deciding; do not act on this report alone.\n\n'
      ;;
    autostart/unmeasurable)
      printf 'This is **not** good news and must not be read as one. Nothing was established, so the `autostart` stand-down is currently unverified rather than confirmed. Note in particular that a failure of the **manual-spawn control** means *this box could not host a daemon at all* — an apparatus limit, never a finding about upstream. Repair the detector (`scripts/verify-atuin-guard.sh`), then re-run `make verify-atuin-guard-autostart`.\n\n'
      ;;
    */unmeasurable)
      printf 'This is **not** good news and must not be read as one. The check could not establish anything, so the guard'"'"'s justification is currently unverified rather than confirmed. Repair the detector (`scripts/verify-atuin-guard.sh`), then re-run.\n\n'
      ;;
    autostart/holds)
      printf 'No action needed on this premise. Read the scope note below before treating it as fleet coverage, though: the two machines that depend on this stand-down are the two least like the box that just measured it.\n\n'
      [[ "$ANCHOR_REL" == unanchored ]] &&
        printf 'This premise has no anchor yet. If you are satisfied with this run, record it by writing `# CORE_ATUIN_AUTOSTART_VERIFIED_AGAINST=%s` into `zsh/00-tools.zsh` beside the stand-down block — that line is a human'"'"'s claim to have measured it, which is why nothing writes it automatically.\n\n' "$AT_VER"
      ;;
    */holds)
      printf 'No action needed. The guard still earns its place.\n\n'
      ;;
    esac
    printf -- '**Measured here:** %s.\n\n' "$(arms_sentence)"
    if [[ "$PREMISE" == autostart ]]; then
      printf -- '---\n\n**Scope this does not cover**, stated so it is not mistaken for coverage. This ran on `%s`, and the two machines this premise protects are **Alpine/musl and macOS** — so weigh it accordingly: a run on one of those two is direct evidence for that row and still says nothing about the other, while a run on glibc Linux (what the scheduled job uses) is the *weakest* evidence in this whole arrangement for either of them. It measures a **fresh client** spawning a daemon from an unreachable socket; a long-lived shell whose daemon dies mid-session is not exercised. Teardown is proven two ways — the pid that owned the socket before the stop, and the process group each arm ran in — which between them cover a daemon that detached after binding and a child that hung before it. A child that did **both** (detached, then never bound) is detected by **neither**, and this run does not notice it: it is left running and its sandbox is deleted underneath it. That is an undetected leak, not a guarded one — the preserved-sandbox path covers a stop that failed, not a process nothing ever looked for. A daemon that wedges (`atuinsh/atuin#3382`) escapes only if it wedges **after** completing the measured pair: one that wedges during it shows up here as an expired bound (`unmeasurable`) or a row that never landed (`moved`), because every arm must also exit 0 and land exactly one row. The **silent-discard** premise is a separate mode (`--premise discard`) and is not measured by this run. stderr is recorded but never judged: the spawned daemon inherits this process'"'"'s descriptor, so its tracing and the client'"'"'s are not separable.\n' "$HOST_KIND"
    else
      printf -- '---\n\n**Scope this does not cover**, stated so it is not mistaken for coverage. This ran on `%s`; the scheduled job runs it on Linux x86_64 glibc, and the Alpine/musl half of the fleet is unmeasured either way. The **`autostart` stand-down** is not measured by *this* run: it is a separate premise with its own mode (`--premise autostart`, `make verify-atuin-guard-autostart`), its own anchor and its own verdict, because measuring it means spawning a real daemon and owning its teardown — so a green run here says nothing about it in either direction. **Buffer-and-replay** is probed only by the closing daemon-off control arm above; a spool that only a live daemon would drain is out of reach for the same reason. The accept-but-silent socket (`atuinsh/atuin#3382`) is structurally out of scope: this measures *unreachable*, and that shape is *reachable and lying*.\n' "$HOST_KIND"
    fi
  } >"$REPORT"
}

# ── main ──────────────────────────────────────────────────────────────────────
# BEFORE the branch, not inside measure(): the forced-unmeasurable path skips measure()
# entirely, and it is the path the scheduled job takes whenever a download or checksum fails —
# so leaving it here is the difference between a report that says where it ran and one that
# says `unknown` on exactly the runs a human is most likely to be reading closely.
detect_host

if [[ -n "$FORCED_UNMEASURABLE" ]]; then
  # A caller that failed before a binary ever existed (a download, a checksum, an
  # attestation) reports through this same renderer, so the wording a human reads cannot
  # drift from the code that produces it.
  unmeasurable "$FORCED_UNMEASURABLE"
else
  measure
fi

# Belt and braces: an unset verdict is a bug in the flow above, and the safe reading of a
# bug is "we do not know", never "all is well".
[[ -n "$VERDICT" ]] || unmeasurable "internal: no verdict was reached (this is a bug in verify-atuin-guard.sh)"

[[ -n "$REPORT" ]] && emit_report
if ((JSON)); then
  emit_json
else
  # NAMED, not just "the premise". Both modes print one line to a terminal, and an operator
  # who ran the autostart target reading "atuin guard premise HOLDS" has been told the wrong
  # thing about the wrong fact — the same one-premise-one-verdict rule the issue titles follow.
  case "$PREMISE" in
  autostart) _label="autostart self-healing" ;;
  *) _label="silent-discard" ;;
  esac
  case "$VERDICT" in
  holds) pass "atuin ${_label} premise HOLDS on ${AT_VER} — $REASON" ;;
  moved) fail "atuin ${_label} premise MOVED on ${AT_VER} — $REASON" ;;
  *) skip "atuin ${_label} premise UNMEASURABLE — $REASON" ;;
  esac
fi

case "$VERDICT" in
holds) exit 0 ;;
moved) exit 1 ;;
*) exit 3 ;;
esac
