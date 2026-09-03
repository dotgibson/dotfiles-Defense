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
# Why load_os_repos() sets rather than prints — see its definition below. Declared here with
# `:=` for the same reason as the tallies: a caller under `set -u` reads it on the failure
# path, before any successful load has assigned it.
: "${CORE_OS_REPOS_ERR:=}"
# Labels of the checks that SKIPPED, so a caller can report exactly WHICH gates didn't
# run (e.g. a CI-installed linter absent locally) instead of just a count — the
# difference between "green" and "green but partial". Declared once (this lib is
# idempotent), appended by skip() below.
_CORE_SKIPS=()

# ENVIRONMENT skips — a THIRD class, distinct from the two the summary already knew about.
# A skip is one of:
#   · tool absent      — a real coverage gap; --strict reds on it
#   · out of scope     — the caller NARROWED the run (--scope/--changed); intentional
#   · environment      — the run COULD NOT cover it here: a sibling OS repo isn't checked
#                        out, so the fleet-wide gates have nothing to read
# The third used to be filed under the second by WORDING: the sibling-absence skips were
# deliberately phrased "out of scope" so the substring test that classifies skips would
# keep --strict green. That made the message text the classifier, so making the wording
# honest would have silently changed gate behaviour — and it conflated "you asked me to
# narrow this" with "this box can't run it", which are not the same claim. A run narrowed
# by --scope is a request; an absent sibling is an accident of where you invoked from.
# Recording the class STRUCTURALLY (here) instead of textually lets the wording say what
# is actually true and lets --require-siblings gate it. Appended by skip_env() below.
_CORE_ENV_SKIPS=()
# Indices into _CORE_SKIPS of the entries above — see skip_env() for why the index and not
# the text is what the classifier keys on.
_CORE_ENV_SKIP_IDX=()
# Indices of NOTE skips — see skip_note(). Separate from the environment list because the two
# answer different questions: --require-siblings reds on environment, nothing reds on a note.
_CORE_NOTE_SKIP_IDX=()

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
# skip_env <label> — a skip this BOX could not cover (a sibling OS repo isn't checked out),
# as opposed to one the caller narrowed away. Tallies like any other skip, and additionally
# records the class so the summary can name it and --require-siblings can red on it.
skip_env() {
  # Record the INDEX this skip will occupy in _CORE_SKIPS, not just its text. The classifier
  # needs to identify environment skips WITHOUT re-reading their wording — recording the text
  # alone forced the caller to subtract counts, and that subtraction was only correct while no
  # skip_env message happened to contain "out of scope". Which is the exact defect the
  # environment class was introduced to remove, one layer down: prose deciding a gate. $SKIP is
  # still the pre-increment count here, so it IS the 0-based index of the entry skip() appends.
  _CORE_ENV_SKIP_IDX+=("$SKIP")
  _CORE_ENV_SKIPS+=("$*")
  skip "$@"
}
# skip_note <label> — a skip that is NOT a coverage gap: the gate ran, reached a conclusion,
# and is declining to assert one part of it because there is genuinely nothing to assert.
# Nothing is missing, so nothing should red on it.
#
# THE THIRD QUESTION. tool ("install it"), environment ("clone the sibling"), out-of-scope
# ("you narrowed the run") all say something is ABSENT. This one says the opposite: the run
# was complete and the honest report includes a half that cannot be asserted. §9f's parity
# default is the case — pwsh gets Ctrl+Arrow from a PSReadLine default, so there is no string
# to grep, and parity-check.sh reports it rather than inventing a needle that cannot fail.
#
# WHY IT NEEDS ITS OWN CLASS. Without one it falls through to TOOL, and --strict — documented
# as "a gate SKIPPED because its TOOL is absent" — would fail a fully-provisioned box purely
# because the contract is being honest about a framework default. That would also disagree
# with `parity-check.sh --strict`, which accepts the same reported default. A gate punished
# for reporting honestly teaches the next author to stop reporting.
#
# Recorded by INDEX, never by wording, for skip_env's reason.
skip_note() {
  _CORE_NOTE_SKIP_IDX+=("$SKIP")
  skip "$@"
}
# _core_tool_skip_count — how many skips are a REAL coverage gap (an absent tool), printed
# to stdout. The three classes are tool / out-of-scope / environment; this counts the first.
#
# It lives HERE, in the shared lib, rather than inline in audit-core.sh's summary — and that
# placement is the point, not tidiness. The previous version was inline, and the test meant to
# guard it re-implemented the same loop in the test file. Both stayed green while the defect
# they existed to catch was fully reintroduced in audit-core.sh, because the test exercised its
# own copy and never the code that runs. A test that cannot fail when the shipped logic changes
# is documentation, not a gate.
#
# Same render-vs-judge split as _core_luacheck_verdict (#728) and §1b: the caller renders, the
# helper decides, and test-core.sh drives the helper directly.
#
# Environment and NOTE skips are identified by the INDEX skip_env/skip_note recorded, never by
# their wording — see skip_env() for why. Out-of-scope skips are still matched on text, which
# is correct: that class IS a statement the caller makes in prose about a run it deliberately
# narrowed. Four classes now, and only the leftover — a genuinely absent tool — is counted.
_core_tool_skip_count() {
  local _s _e _i=0 _n=0 _is_env
  for _s in ${_CORE_SKIPS[@]+"${_CORE_SKIPS[@]}"}; do
    _is_env=0
    for _e in ${_CORE_ENV_SKIP_IDX[@]+"${_CORE_ENV_SKIP_IDX[@]}"}; do
      [[ "$_i" == "$_e" ]] && {
        _is_env=1
        break
      }
    done
    for _e in ${_CORE_NOTE_SKIP_IDX[@]+"${_CORE_NOTE_SKIP_IDX[@]}"}; do
      [[ "$_i" == "$_e" ]] && {
        _is_env=1
        break
      }
    done
    _i=$((_i + 1))
    ((_is_env)) && continue
    [[ "$_s" == *"out of scope"* ]] || _n=$((_n + 1))
  done
  printf '%d' "$_n"
}
fail() {
  FAIL=$((FAIL + 1))
  printf '%s✗%s %s\n' "$c_red" "$c_rst" "$*" >&2
}
# fail_detail <captured-output> — print a failing tool's OWN report under the ✗ line.
#
# The audit's job is to say WHAT failed; the tool has already computed WHY. Discarding it
# meant a red CI run named a gate and nothing else — "✗ markdownlint reported issues" with
# no rule, no file, no line — and CI is precisely where you cannot re-run the tool by hand
# (dotgibson/dotfiles-core#456).
#
# stderr, like fail(), so --json keeps stdout clean for the summary object. Indented so it
# reads as detail rather than as further findings, and capped so a pathological run cannot
# bury the summary; the "run:" hint on each fail line stays the route to the full output.
#
# NB the herestrings: `head` exits after N lines, so `printf … | head` under `set -o
# pipefail` is the SIGPIPE trap this repo has hit three times (#459). `head <<<` has no
# upstream to kill, and the `| sed` downstream consumes everything without exiting early.
CORE_FAIL_DETAIL_LINES="${CORE_FAIL_DETAIL_LINES:-40}"
fail_detail() {
  local out="${1:-}" n
  [ -n "$out" ] || return 0
  n="$(wc -l <<<"$out" | tr -d ' ')"
  head -n "$CORE_FAIL_DETAIL_LINES" <<<"$out" | sed 's/^/    /' >&2
  if [ "${n:-0}" -gt "$CORE_FAIL_DETAIL_LINES" ]; then
    printf '    … %s more line(s) — run the command above for the rest\n' \
      "$((n - CORE_FAIL_DETAIL_LINES))" >&2
  fi
}
hdr() { ((QUIET)) || printf '\n%s== %s ==%s\n' "$c_blu" "$*" "$c_rst"; }

# ── area scope (shared by audit-core.sh + test-core.sh) ───────────────────────
# Both gate scripts gate their SLOW per-area sections on these flags so a per-area run
# pays only for what it touched. They carried BYTE-IDENTICAL copies of this parser — the
# exact "two copies that drift" pattern this lib exists to kill — so it lives here once.
# FAIL-CLOSED default: unset → every area on (full run). An empty or unknown scope token
# fails SAFE to the full run rather than silently narrowing a gate on the nine-repo fan-out.
: "${SCOPE_SHELL:=1}"
: "${SCOPE_NVIM:=1}"
: "${SCOPE_ATUIN:=1}"
_set_scope() { # _set_scope <comma-list: shell,nvim,atuin | all | none>
  SCOPE_SHELL=0
  SCOPE_NVIM=0
  SCOPE_ATUIN=0
  local tok had=0 prog="${0##*/}"
  local IFS=,
  for tok in $1; do
    had=1
    case "$tok" in
    shell) SCOPE_SHELL=1 ;;
    nvim) SCOPE_NVIM=1 ;;
    # `atuin` is the hermetic self-test of scripts/research/verify-atuin-guard.sh — the premise
    # DETECTOR's own harness, not shipped Core (it is absent from core.manifest and nothing
    # vendors it). Its own axis because it is by far the most expensive thing the suite
    # does — measured at 197s of a 286s run, 68% — while being unreachable from almost
    # every change that pays for it. The real measurement, against live upstream atuin,
    # runs on manual dispatch of .github/workflows/atuin-guard-verify.yml (#687); this axis
    # only decides
    # whether the STUB-driven self-test also runs on a given push.
    atuin) SCOPE_ATUIN=1 ;;
    all | full)
      SCOPE_SHELL=1
      SCOPE_NVIM=1
      SCOPE_ATUIN=1
      ;;
    none) ;;
    *) # unknown token → run EVERYTHING (fail-safe), matching ci.yml's safe default
      printf '%s: unknown scope %s — running full (fail-safe)\n' "$prog" "$tok" >&2
      SCOPE_SHELL=1
      SCOPE_NVIM=1
      SCOPE_ATUIN=1
      ;;
    esac
  done
  # An EMPTY scope (no tokens) is ambiguous → fail SAFE to the full run rather than
  # silently skipping every slow gate. `none` is the EXPLICIT "always-on checks only" token.
  ((had)) || {
    printf '%s: empty scope — running full (fail-safe)\n' "$prog" >&2
    SCOPE_SHELL=1
    SCOPE_NVIM=1
    SCOPE_ATUIN=1
  }
}

# Pre-seed the EMPTY plugin dirs the hermetic zsh tests + bench need so 45-plugins.zsh's
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

# Read ci-classify.sh's three-line `shell=<bool>`/`nvim=<bool>`/`atuin=<bool>` contract into
# CLASSIFY_SHELL/CLASSIFY_NVIM/CLASSIFY_ATUIN. Returns NON-ZERO when ANY of the three keys is
# missing or not a clean true/false (a classifier error or garbage) — so the caller can fail
# SAFE to the full run rather than trust a half-parsed verdict. ONE reader for the contract the
# audit (`--changed`) consumes, instead of re-implementing the sed parse + validation per site.
_core_read_classify() { # _core_read_classify <classifier-output>
  CLASSIFY_SHELL="$(printf '%s\n' "$1" | sed -n 's/^shell=//p')"
  CLASSIFY_NVIM="$(printf '%s\n' "$1" | sed -n 's/^nvim=//p')"
  CLASSIFY_ATUIN="$(printf '%s\n' "$1" | sed -n 's/^atuin=//p')"
  case "$CLASSIFY_SHELL" in true | false) ;; *) return 1 ;; esac
  case "$CLASSIFY_NVIM" in true | false) ;; *) return 1 ;; esac
  # Validated exactly as strictly as the other two, deliberately. Defaulting a missing or
  # malformed `atuin=` to false would read a classifier this reader cannot parse as
  # "skip the most expensive gate" — the silent-skip failure mode ci-classify.sh's whole
  # fail-closed design exists to invert. A garbage line fails here and the caller runs full.
  case "$CLASSIFY_ATUIN" in true | false) ;; *) return 1 ;; esac
  return 0
}

# _core_fail_digest <file> — condense the ✗ lines of a nested gate's CAPTURED output into
# one line: `N: first | second | third (+M more)`, or EMPTY when the file holds no ✗ at all.
#
# WHY A DIGEST EXISTS. A wrapper that reports only "the nested suite failed — go re-run it"
# sends the operator away to reproduce a result the run already had, and for an INTERMITTENT
# failure that is advice which cannot be taken: the re-run passes and the evidence is gone.
# The digest rides along in the wrapper's own fail line, so the names survive wherever that
# line goes — a summary block, --json, a CI job log, a `tail` of a long log. (A CI ANNOTATION
# is NOT among them: fail() writes to stderr and ci.yml runs audit-core.sh directly, with
# nothing emitting `::error::`. Naming a destination this does not reach would be the same
# overclaim the digest exists to prevent, one layer up.)
#
# LIVES HERE, not inline in the caller, so it is REACHABLE BY TESTS. Every branch below is a
# quiet-failure risk rather than an obvious one, and verifying them by making a real gate fail
# means either recursively invoking that gate or hand-injecting faults — neither of which CI
# repeats. Both gate scripts already source this file, so the suite can drive it on fixtures.
#
# ESCAPES ARE STRIPPED rather than anchoring on a bare ✗: fail() above prefixes the mark with
# $c_red, so an anchored match finds nothing whenever colour is on — a detector that would go
# quiet in exactly the runs someone is watching.
#
# NAMES ARE CAPPED AT THREE, then counted (+M more) rather than silently truncated: a suite
# that failed wholesale would otherwise render an unreadable wall, and "one flaky assertion"
# versus "the whole section is down" is the distinction a reader needs before deciding whether
# to re-run or to investigate. The leading N is the TRUE total, not the number shown.
_core_fail_digest() { # _core_fail_digest <captured-output-file>
  local f="${1:-}" esc lines n why
  [[ -n "$f" && -r "$f" ]] || return 0
  esc="$(printf '\033')"
  lines="$(sed "s/${esc}\[[0-9;]*m//g" "$f" 2>/dev/null | grep '^✗' | sed 's/^✗[[:space:]]*//')"
  [[ -n "$lines" ]] || return 0
  n="$(printf '%s\n' "$lines" | grep -c .)"
  # JOINED WITHOUT REWRITING THE RECORDS. The obvious `tr '\n' '|' | sed 's/|/ | /g'` also
  # spaces out every literal `|` INSIDE a message, and assertions here really do contain them
  # — `'exec … || exec …' cannot fall back` is one of nine in test-core.sh. Two failures then
  # render with four apparent boundaries while the count says 2, which is worse than terse:
  # it invents structure in the one line someone reads when they cannot reproduce the failure.
  local l i=0
  why=""
  while IFS= read -r l; do
    [[ -n "$l" ]] || continue
    i=$((i + 1))
    ((i <= 3)) || break
    why="${why:+$why | }$l"
  done <<<"$lines"
  ((n > 3)) && why="$why (+$((n - 3)) more)"
  printf '%s: %s' "$n" "$why"
}

# ── pipefail SIGPIPE scanner (audit-core.sh §5d) ──────────────────────────────
# _core_pipefail_hits <file> — print the line number of every place <file> pipes a
# SHELL-STRING producer (printf/echo) into a reader that EXITS EARLY: grep in a quiet mode,
# awk reaching an `exit`, head after its count. Under `set -o pipefail` the writer then
# takes EPIPE, dies with 141, and the pipeline reports failure even though the reader
# succeeded. Silence = clean.
#
# It lives here rather than inline in the gate for the same reason _core_fail_digest does:
# so test-core.sh can drive it on fixtures. A gate never shown to fire is a gate nobody
# should trust — and testing this one caught three defects in it before it shipped.
#
# WHAT THIS IS: a textual scan, and so a HEURISTIC BACKSTOP rather than a proof. It does
# not parse shell. The limits, stated so nobody reads a green §5d as more than it is:
#   * a pipeline split across lines is not seen
#   * a reader reached through a variable or eval is not seen
#   * the banned text inside a quoted string still matches — there is no lexer here, which
#     is why test-core.sh assembles its fixtures instead of spelling them out
# It catches the shape people actually write; all three real occurrences in this repo were
# one-liners of exactly that shape.
#
# Two deliberate narrowings, both about not crying wolf:
#   * the file must actually enable pipefail — `set -euo pipefail`, `set -o pipefail`,
#     `set -e -o pipefail` and `set -o errexit -o pipefail` all count; naming it in prose
#     does not
#   * comment lines are skipped, so writing ABOUT the hazard does not trip the gate
# A FILE producer (`sed x | head -n1`) is out of scope: converting those is not free, and a
# gate that fires on working code is a gate someone turns off.
_core_pipefail_hits() { # _core_pipefail_hits <file>
  local f="${1:-}" re
  [ -f "$f" ] || return 0
  # `-o pipefail` in ANY position of a `set`, compact or split. An earlier version anchored
  # on the first option token and so skipped `set -e -o pipefail` outright — a guard that
  # silently permits the hazard, which is the worst way for this to be wrong.
  grep -qE '^[[:space:]]*set[[:space:]].*o[[:space:]]+pipefail' "$f" 2>/dev/null || return 0
  # Assembled from fragments so this very line cannot match the pattern it defines — the
  # scanner reads every tracked shell script, and common.sh is one of them.
  # grep: any quiet spelling (-q, -Eq, -E -q, --quiet). awk: an `exit` that is a statement
  # rather than the word inside a string — `awk '{ print "exit" }'` exits nothing.
  # `-[a-zA-Z]*q[a-zA-Z]*`, NOT `-[a-zA-Z]*q`: the q may sit ANYWHERE in the flag cluster.
  # The old form required it to be the LAST letter, so `grep -q` and `grep -xq` were caught
  # while `grep -qx` and `grep -Eqi` walked straight past — the same hazard, differing only
  # in spelling. A gate that misses a spelling of the thing it guards is indistinguishable
  # from one that works, which is the failure mode this scanner exists to prevent.
  # Widening it flags exactly ONE line that was already in the tree (ci-pr-link.sh's
  # No-Issue probe, fixed in the same change), so this is a real catch, not new noise.
  re="(printf|echo)[^|]*[|][[:space:]]*(grep[^|]*(-[a-zA-Z]*q[a-zA-Z]*|--quiet)([[:space:]]|\$)|head([[:space:]]|\$)|awk[^|]*[^\"'[:alnum:]_]exit)"
  grep -nE "$re" "$f" 2>/dev/null |
    awk -F: '{ l = $0; sub(/^[0-9]+:/, "", l); if (l !~ /^[[:space:]]*#/) print $1 }'
}

# ── leaked-RETURN-trap scanner (audit-core.sh §5e) ────────────────────────────
# _core_return_trap_hits <file> — print the line number of every place <file> arms a bash
# RETURN trap whose body does not disarm the slot. Silence = clean.
#
# A bash RETURN trap is a GLOBAL slot, not a function-scoped one. Arm one inside a function
# and it stays armed in the CALLER's frame, firing a SECOND time when the caller returns —
# where the local it was cleaning up is out of scope and `set -u` makes that fatal:
#
#     f()     { local tmp; tmp=$(mktemp -d); trap CLEANUP RETURN; ...; }
#     outer() { f; ...; }        # ← aborts HERE, on outer's return, not on f's
#
# That is dotgibson/dotfiles-Debian#2. Its bootstrap died the instant provision() returned,
# AFTER installing every package but BEFORE wire_links ran — a box carrying the whole stack
# and not one symlink. It shipped green because nothing could see it: the broken line is
# valid bash, so shellcheck and `bash -n` pass it, and bootstrap-test.yml only ever runs
# --links-only, so no gate executes provision() at all (#512, #461). When it does surface,
# the reported line number is a DECOY — bash attributes a RETURN trap to the last nested
# function DEFINITION in the frame, so Debian's abort blamed `_add_vendor_repo`, which had
# nothing to do with it. Grepping for the trap is the only reliable way to find it.
#
# It lives here rather than inline in the gate for the same reason _core_pipefail_hits does:
# so test-core.sh can drive it on fixtures. Same rule as the fleet-facing leg in
# .github/workflows/lint-call.yml — that one gates the CALLER repos, this one gates Core's
# own tree, which lint-call.yml never checks out. Keep the two in step.
#
# WHAT THIS IS: a textual scan, and so a HEURISTIC BACKSTOP rather than a proof. It does not
# parse shell. A trap armed through a variable or `eval` is not seen, and neither is one
# assembled across lines. It catches the shape people actually write.
#
# TWO DELIBERATE LOOSENESS DECISIONS, each of which a tighter pattern got wrong under test:
#   * RETURN is matched as a SIGNAL TOKEN — whitespace, `;` or end-of-line after it — not as
#     the last word on the line. Anchoring to end-of-line waves through a trailing comment
#     and through a two-signal `RETURN EXIT`, and both leak identically.
#   * `trap` is matched as a WORD ANYWHERE on the line, not anchored to line-start. Anchoring
#     waves through the ONE-LINE function body, which is exactly where this hides. The guard
#     dotfiles-Debian shipped anchors, and misses that form; against a fixture carrying four
#     broken shapes it catches one.
# And two narrowings, both about not crying wolf:
#   * comment lines are skipped, so writing ABOUT the hazard does not trip the gate — this
#     repo now documents it in three places, and Debian's own fix carries three such comment
#     lines directly above the corrected traps
#   * a body that disarms the slot is the FIX, not the bug, and is never a finding
#
# BASH ONLY. zsh has no RETURN signal at all (`trap ... RETURN` → "undefined signal"), so the
# zsh modules are out of scope rather than silently scanned.
_core_return_trap_hits() { # _core_return_trap_hits <file>
  local f="${1:-}" re dis
  [ -f "$f" ] || return 0
  # ASSEMBLED FROM FRAGMENTS, like _core_pipefail_hits above, so these lines cannot match the
  # pattern they define — the scanner reads every tracked shell script, and common.sh is one
  # of them. (The concatenation is also what keeps the literal disarm text off this line.)
  re="(^|[[:space:]]|;)trap[[:space:]].*[[:space:]]RETURN"'([[:space:]]|;|$)'
  dis='trap[[:space:]]+-[[:space:]]+RETURN'
  grep -nE "$re" "$f" 2>/dev/null |
    awk -F: -v dis="$dis" '{ l = $0; sub(/^[0-9]+:/, "", l);
                             if (l !~ /^[[:space:]]*#/ && l !~ dis) print $1 }'
}

# ── _core_owned_block_hits: portable logic that Core owns, re-implemented locally ──
# _core_owned_block_hits <file> — print `<line>:<rule-id>` for every place <file>
# re-implements a block Core now owns. Silence = clean. Consumed by the reusable
# .github/workflows/lint-call.yml, which runs it over each caller repo's own *.zsh.
#
# WHY THIS EXISTS. Seven OS repos each hand-maintained a copy of the direnv/gh/uv/ty init
# block, and six a copy of the WSL probe — entirely portable zsh, maintained N times, and
# already drifted into three variants of one block by the time anyone counted (#449). Core
# took both over. Nothing stops a repo re-adding them: the duplicate is valid zsh, `zsh -n`
# passes it, and the shell keeps working (the second copy is a redundant re-source, not an
# error) — so the drift would come back invisibly, exactly as it arrived. audit-core.sh §5c
# catches OS-specifics leaking INTO Core; this is the missing other direction.
#
# ONE ASYMMETRY WORTH STATING, because it differs from _core_return_trap_hits above: that
# rule holds for Core's own tree too, so audit-core.sh §5e runs it here. THIS one does NOT,
# and must not — Core's zsh/00-tools.zsh and zsh/45-plugins.zsh contain these exact strings,
# and that is the entire point. There is deliberately no audit section calling this. The
# Core-side guard is the INVERSE assertion in scripts/test-core.sh, which fails if Core ever
# stops carrying the blocks it makes the fleet drop: a gate that forces nine repos to delete
# something Core has quietly lost is worse than no gate at all.
#
# ONE PATTERN IS DELIBERATELY OBFUSCATED: the WSL rule spells the kernel version file as
# `/proc/versio[n]` — an ERE character class matching exactly one letter — so that the rule
# TABLE does not match the rule it defines. This is the same self-reference problem the two
# scanners above solve by assembling their patterns from fragments; only this one line needs
# it, because only it contains a bare literal rather than a `[[:space:]]`-broken one. Write
# it plainly and the helper reports itself. (It is `.sh`, and lint-call.yml scans `*.zsh`, so
# nothing in production would ever have noticed — which is precisely why it is fixed here.)
#
# WHAT IT IS: a textual scan, so a heuristic backstop rather than a proof — the same caveat
# the scanners above carry. It catches the shape people actually write, which is also the
# shape all seven copies actually had, not one assembled through a variable.
#
# FALSE-POSITIVE DISCIPLINE, which is what keeps a gate switched on:
#   * the patterns are exact GENERATOR INVOCATIONS, not tool names. `alias dv=direnv`,
#     `direnv allow`, `gh pr create`, and an OS repo's own `_cache_eval brew brew shellenv`
#     are all untouched — an OS-only tool's hook stays the OS layer's business, which is the
#     whole point of the band.
#   * comment lines are skipped, so a repo may write "direnv hook zsh is Core's now, see
#     core/zsh/00-tools.zsh" in the very comment that replaces the deleted block.
#   * the WSL rule keys on the kernel version file and on `_IS_WSL=`, NOT on
#     $WSL_DISTRO_NAME. Reading the distro NAME (for a prompt, a title, a hostname) is a
#     different use from re-implementing the DETECTION, and only the latter is Core's.
# There is deliberately NO inline allow-marker escape hatch, for the reason §5e gives for
# not having one: an escape hatch is an invitation to silence a real finding.
#
# TABLE-DRIVEN — adding a block Core takes over is ONE line in the heredoc. Fields are
# whitespace-separated (`read -r rule re`), so the ERE must contain no LITERAL space; use
# [[:space:]], as every pattern below does. Quoted heredoc, so `$` stays an ERE anchor and
# nothing is expanded. bash 3.2-safe: no associative array, no mapfile (PORTABILITY.md §1).
_core_owned_block_hits() { # _core_owned_block_hits <file>
  local f="${1:-}" rule re
  [ -f "$f" ] || return 0
  while read -r rule re; do
    [ -n "$rule" ] || continue
    grep -nE "$re" "$f" 2>/dev/null |
      awk -F: -v rule="$rule" '{ l = $0; sub(/^[0-9]+:/, "", l);
                                 if (l !~ /^[[:space:]]*#/) print $1 ":" rule }'
  done <<'EOF' | sort -t: -k1,1n -u
direnv-hook (^|[^[:alnum:]_-])direnv[[:space:]]+hook[[:space:]]+zsh
gh-completion (^|[^[:alnum:]_-])gh[[:space:]]+completion[[:space:]]+-s[[:space:]]+zsh
uv-completion (^|[^[:alnum:]_-])uv[[:space:]]+generate-shell-completion[[:space:]]+zsh
ty-completion (^|[^[:alnum:]_-])ty[[:space:]]+generate-shell-completion[[:space:]]+zsh
wsl-detect /proc/versio[n]|(^|[^[:alnum:]_])_IS_WSL[[:space:]]*=
EOF
}

# _core_owned_block_owner <rule-id> — the Core file that owns that block, for the
# remediation line. A `case`, not a second table, so it cannot fall out of step silently:
# an unknown id returns non-zero and the caller prints the generic pointer instead.
_core_owned_block_owner() { # _core_owned_block_owner <rule-id>
  case "$1" in
  direnv-hook) echo "core/zsh/00-tools.zsh (band 00, beside the other per-directory hook inits)" ;;
  gh-completion | uv-completion | ty-completion) echo "core/zsh/00-tools.zsh (band 00, generated into an fpath dir; compdef re-assert in 45-plugins.zsh after carapace)" ;;
  wsl-detect) echo "core/zsh/00-tools.zsh :: _core_is_wsl" ;;
  *) return 1 ;;
  esac
}

# ── _core_gitleaks_policy_hits: a secret scan measured by Core's policy, or nobody's ──
# _core_gitleaks_policy_hits <file> — print `<line>:<reason>` for every gitleaks invocation
# in <file> that does not carry a config flag. Silence = clean.
#
# WHY. Core's reusable lint-call.yml secrets leg states the rule: ONE POLICY FILE, Core's, so
# every repo is measured the same way and no repo can widen its own allowlist. The rule is
# stated in Core and honoured by Core's reusable — and nothing enforced it on the repo side.
# On the 2026-08-23 sync four repos ran their own gitleaks with NO config, so they used the
# stock rule set; `curl-auth-user` matches on credential-shaped POSITION rather than content,
# so the vendored core/CHANGELOG.md — which documents that very allowlist and quotes the
# example it was written for — was flagged. Core's explanation of the rule read as a
# violation of it, on a sync that carried no credential (#623).
#
# Two more repos were green only because each keeps its OWN root .gitleaks.toml that gitleaks
# auto-discovers — the "repo widens its own allowlist" case the policy argues against, failing
# in the quiet direction, which is worse (#624).
#
# THE RULE IS "CARRIES A CONFIG FLAG", NOT "NAMES CORE'S FILE", and that is deliberate. A repo
# may legitimately need a local rule set for a distro-specific pattern Core has no business
# knowing about; the honest shape there is to EXTEND Core's rather than replace it. So this
# scan answers "is a policy passed at all", and whether that policy descends from Core's is
# the separate question audit-core.sh §5g asks of the config file itself. Splitting them keeps
# each check able to say something true on its own.
#
# THE FALSE-POSITIVE TRAP, which cost real time while surveying for the issue: a naive
# `-c|--config` match also fires on the `-c` inside `--exit-code`, which two of the repos in
# scope actually pass. The flag must be matched as a WHOLE WORD — hence the `(^|[[:space:]])`
# prefix and the `(=|[[:space:]])` suffix on the short form.
#
# Comment lines are skipped, so a repo may describe the policy in the comment above the call —
# which every already-corrected repo does, at length.
_core_gitleaks_policy_hits() { # _core_gitleaks_policy_hits <file>
  local f="${1:-}" line n=0 body
  [ -f "$f" ] || return 0
  while IFS= read -r line; do
    n=$((n + 1))
    body="${line#"${line%%[![:space:]]*}"}"
    case "$body" in '#'* | '@#'*) continue ;; esac
    # An invocation, not a mention: `gitleaks` followed by one of its scanning subcommands.
    printf '%s\n' "$line" | grep -qE '(^|[^[:alnum:]_-])gitleaks[[:space:]]+(dir|detect|git)([[:space:]]|$)' || continue
    # Whole-word config flag. `--exit-code` must NOT count as `-c`.
    printf '%s\n' "$line" | grep -qE '(^|[[:space:]])(-c(=|[[:space:]])|--config(=|[[:space:]]))' && continue
    printf '%s:%s\n' "$n" "no-config"
  done <"$f"
}

# ── _audit_ls: the file set the CONTENT gates inspect ─────────────────────────
# Tracked files PLUS untracked-but-not-ignored ones. The distinction matters, and it
# cost a real round-trip: a brand-new script is invisible to `git ls-files` until the
# moment it is `git add`ed, so every content gate in audit-core.sh used to skip the one
# file a change was actually about — and still printed its cheerful "all clean" pass.
# That is a green audit which proved nothing, strictly worse than a red one.
#
# It happened on scripts/ci-pr-link.sh (#496): `make audit-changed` reported 261 pass /
# 0 fail locally while shellcheck never opened the file, then CI failed all four audit
# legs on two SC2016 violations that had been there the whole time.
#
# The audit was already internally inconsistent about this: its _changed_scope() counts
# untracked files when deciding which AREAS run, and the walk-based gates (luacheck's
# `luacheck .`, markdownlint's `**/*.md` glob) have always seen them. Only the
# `git ls-files` gates disagreed, and nothing surfaced the disagreement.
#
# THE RULE, so a new gate lands on the right side of it:
#   * Does the gate ask "is this file's CONTENT valid?" (syntax, lint, parse) → use
#     _audit_ls. An untracked file is about to be committed; catching it now is the
#     entire point of a local gate.
#   * Does the gate ask "what does GIT RECORD?" (manifest reverse-drift, index exec-bits)
#     → use plain `git ls-files`. An untracked file has no git state to check, so
#     including it would be meaningless rather than merely noisy.
#
# The rule binds every gate script `make audit` consults, not just audit-core.sh:
# check-modern.sh (workflow/action inventory) and nvim-reachability.sh (lua module
# inventory) source this lib for the same reason. scripts/test-core.sh asserts the exact
# split per file, so adding either kind of enumeration anywhere fails the suite until
# someone picks a side.
#
# The trap to watch for: a gate can READ like a manifest/git question and still be a
# content one. audit-core.sh's §5c expands `nvim/` from the manifest and then cat|greps
# every file it names — the manifest chooses the SCOPE, but the check is about contents,
# so it belongs on the _audit_ls side. Ask what the gate does with the list, not where
# the list came from.
# --exclude-standard honours .gitignore, so scratch files and build output stay out.
# Lives here rather than in audit-core.sh so test-core.sh can exercise the REAL
# implementation instead of a copy that could drift from it.
# ── _core_conflict_marker_hits: a resolution that left a marker behind ────────
# _core_conflict_marker_hits <file> — print the line number of every leftover VCS
# conflict marker in <file>. Silence = clean. Consumed by audit-core.sh §5h.
#
# WHY THIS EXISTS. bcdd7dd (#650) committed a literal `|||||||` base marker into
# CHANGELOG.md, at the end of [Unreleased]'s Fixed section, and it sat on main
# undetected. It is the base half of a zdiff3 conflict that was resolved by deleting the
# open/separator/close lines but not the base one — the half that only exists under
# zdiff3/diff3, which is exactly why the eye skips it.
#
# It is not cosmetic. git refuses to parse a conflict region that contains a stray marker,
# so rebasing a branch onto main produced `error: could not parse conflict hunks in
# CHANGELOG.md`. [Unreleased] is the one section every user-visible change is REQUIRED to
# touch (CONTRIBUTING.md), so one stray marker there taxes every future branch in the repo.
#
# NOTHING ELSE CATCHES IT. `bash -n`/`zsh -n` never see a markdown file; markdownlint reads
# the line as ordinary paragraph text; gitleaks looks for credentials. The marker is valid
# text everywhere, which is the same reason §5d/§5e exist as textual scans.
#
# ASSEMBLED FROM FRAGMENTS, exactly as _core_pipefail_hits and _core_return_trap_hits are,
# and here it is load-bearing rather than tidy: the scanner reads every tracked file and
# common.sh is one of them, so a pattern written literally would report the line that
# defines it. This is also why the gate needs NO allowlist — see §5h.
#
# THE SEPARATOR IS TREATED DIFFERENTLY, and deliberately. The open/base/close markers each
# carry a trailing space and a ref, so they are unambiguous on sight. A bare row of seven
# `=` is not: it is also a setext H1 underline, and .markdownlint.jsonc runs MD003 at its
# default `consistent`, which permits setext as long as a file is consistent about it. So
# the separator counts only when the file ALSO carries an unambiguous marker — the same
# file-level precondition idiom _core_pipefail_hits uses when it gates on `set -o pipefail`
# before scanning at all.
#
# THE TRADE-OFF THAT BUYS: a resolution that deleted every marker EXCEPT the separator is
# not caught. That is accepted knowingly — a lone separator is textually indistinguishable
# from a legitimate underline, and a gate that reds a correct document is a gate someone
# turns off (the reasoning §5f spells out). Every marker that names a ref is always caught,
# and the #650 defect was one of those.
_core_conflict_marker_hits() { # _core_conflict_marker_hits <file>
  local f="${1:-}" open base close sep named
  [ -f "$f" ] || return 0
  # Seven of each, built rather than typed. `printf %.0s` repeats the char per argument.
  #
  # THE BASE MARKER IS BUILT AS A CHARACTER CLASS, and it has to be: `|` is ERE's
  # alternation operator, so a literal row of seven pipes dropped into the pattern below
  # reads as eight EMPTY alternatives — an expression that matches the empty string
  # everywhere and therefore reports nothing anywhere. It fails OPEN, silently, which is
  # the worst way for a gate to be wrong. `[|]` is the same one character, inert.
  open="$(printf '<%.0s' 1 2 3 4 5 6 7)"
  base="$(printf '[|]%.0s' 1 2 3 4 5 6 7)"
  close="$(printf '>%.0s' 1 2 3 4 5 6 7)"
  sep="$(printf '=%.0s' 1 2 3 4 5 6 7)"
  # The three that name a ref: marker, then a space, at column 0. Always a defect.
  named="^($open|$base|$close) "
  # -I skips binaries (assets/ carries images); -a would spray NUL bytes at the caller.
  if grep -qIE "$named" "$f" 2>/dev/null; then
    # File is genuinely conflicted, so a bare separator here is a marker too, not an underline.
    grep -nIE "$named|^$sep\$" "$f" 2>/dev/null | cut -d: -f1
  else
    grep -nIE "$named" "$f" 2>/dev/null | cut -d: -f1
  fi
}

# ── _core_claude_ref_hits: a routine pointing at a file nobody ships ─────────
# _core_claude_ref_hits <file> — print `LINE:PATH` for every backticked `.claude/…`
# path <file> names. Silence = the file references nothing under .claude/. Consumed by
# audit-core.sh §1b, which decides whether each path RESOLVES and is TRACKED.
#
# EXTRACTION ONLY, and the split is deliberate. Judging existence needs a worktree and
# judging trackedness needs an index; a scanner that did either could not be driven
# against the $SANDBOX fixtures test-core.sh writes. So this prints what was referenced
# and the audit prints what is wrong with it — the same division _core_pipefail_hits
# uses when it reports a line and leaves the verdict to §5d.
#
# WHY THIS EXISTS. #661 taught /tool-scout to read a decided-and-rejected ledger at
# .claude/tool-decisions.md and shipped three files that reference it — and not the
# ledger. .gitignore's `.claude/*` has per-directory negations, so commands/ and agents/
# vendored out while the file they point at was never tracked (#700). The routine then
# resolves every candidate to "none", in the exact voice that means CHECKED, so the
# report asserts the ledger was consulted while consulting nothing.
#
# NOTHING ELSE CATCHES IT. audit-core.sh §1's reverse-drift check reads `git ls-files`,
# so it sees tracked files that are unaccounted for and has no concept of an
# accounted-for file that was never tracked. .claude/ is allowlisted wholesale as
# repo-meta, so the manifest direction never looks either. markdownlint does not resolve
# links, and these are code spans rather than links in the first place.
#
# BACKTICKED ONLY. Every reference in the routine docs today is a code span (measured:
# four, all `.claude/tool-decisions.md`), and prose that merely says ".claude" in passing
# is not a claim about a file. Requiring the backticks keeps the gate keyed on the form
# that means "this exact path".
#
# GLOBS ARE SKIPPED. A pattern is not a path — `.claude/commands/*.md` describes a set and
# resolving it would mean inventing a semantics the referencing prose does not have.
# A trailing `:NN` line reference is stripped: `.claude/commands/tool-scout.md:164` is a
# citation of the same file, and the line number is not part of the name.
# ── _core_parity_verdict: what did the parity gate actually establish? ────────
# _core_parity_verdict <rc> <parity-check-output> — print exactly one of:
#   ok-full        every aligned row is covered AND holds on both shells
#   ok-defaults    ditto, except one or more pwsh halves are framework defaults that
#                  parity-check.sh REPORTED rather than asserted
#   ok-no-sibling  coverage held, but dotfiles-Windows is absent so pwsh was not read
#   drift          a real finding: an unenforced row, or one that drifted out of a shell
#   broken         the gate could not run, which must NOT be rendered as a clean contract
#
# WHY A HELPER, rather than the `if` chain this replaces. The three success cases are three
# DIFFERENT claims, and audit-core.sh got the distinction wrong twice in one review round —
# once by inheriting CORE_JSON=1 (which silences the very skip line the classification reads,
# so a --json run reported a full zsh+pwsh pass on a box with no pwsh file), and once by
# printing an unqualified "holds across zsh + pwsh" and only admitting the unasserted halves
# on the next line. Both shipped as falsely-complete audit reports. Inline in audit-core.sh
# the logic is unreachable from a test; here test-core.sh drives it directly.
#
# Same render-vs-judge split as _core_luacheck_verdict (#728) and §1b: the caller renders,
# the helper decides. The output is matched on parity-check.sh's own notice wording, which
# is why test-core.sh also pins that the two stay in step.
_core_parity_verdict() { # _core_parity_verdict <rc> <output>
  local rc="${1:-0}" out="${2:-}"
  case "$rc" in
  0) ;;
  1) printf 'drift\n'; return 0 ;;
  *) printf 'broken\n'; return 0 ;;
  esac
  # Order matters: with no sibling repo the pwsh half never runs at all, so the
  # framework-default rows are never reached and cannot also be reported.
  case "$out" in
  *"dotfiles-Windows not checked out"*) printf 'ok-no-sibling\n'; return 0 ;;
  *"nothing to grep"*) printf 'ok-defaults\n'; return 0 ;;
  esac
  printf 'ok-full\n'
}

# ── _core_luacheck_verdict: is that non-zero a LINT finding or a broken tool? ──
# _core_luacheck_verdict <probe-rc> <lint-rc> — print exactly one of:
#   ok             clean
#   broken         luacheck cannot run at all (the --version probe failed)
#   broken-midrun  it stopped being runnable between the probe and the lint pass
#   issues         luacheck ran and has something to say about nvim/
#
# WHY A PROBE RC IS AN INPUT AT ALL, rather than deciding from the lint rc alone. luacheck's
# own vocabulary is 0 clean / 1 warnings / 2 syntax errors / 3 I/O error — and a LOAD failure
# also exits 1. That is not hypothetical: luacheck 1.2.0 cannot load under Lua 5.5 ("attempt
# to assign to const variable" in its own source, see mise/config.toml), so the single most
# likely toolchain failure lands on the same code as honest warnings and is UNDECIDABLE here
# without a second signal. `luacheck --version` lints nothing and loads the same modules, so
# its rc is that signal.
#
# 126/127 are the shell's "could not exec", never one of luacheck's codes, so a lint rc in
# that range after a passing probe means the tool broke mid-audit — a different sentence to
# print, and cheap to separate (#726).
_core_luacheck_verdict() { # _core_luacheck_verdict <probe-rc> <lint-rc>
  local probe_rc="${1:-0}" lint_rc="${2:-0}"
  case "$probe_rc" in 0) ;; *) printf 'broken\n'; return 0 ;; esac
  case "$lint_rc" in 0) printf 'ok\n'; return 0 ;; esac
  if [ "$lint_rc" -ge 126 ] 2>/dev/null; then printf 'broken-midrun\n'; return 0; fi
  printf 'issues\n'
}

# ── _core_claude_untracked_hits: a .claude/ file that will never leave this box ──
# _core_claude_untracked_hits <repo-root> — print every path under .claude/ that git will
# not ship AND that nothing will ever tell you about. Silence = clean.
#
# THE OTHER HALF OF §1b. _core_claude_ref_hits finds a file a routine NAMES but git does not
# carry. That only works because something pointed at the missing file. A .claude/ file
# nothing references — a new subagent, a config a hook reads by convention, a second ledger —
# vanishes with no reference to betray it, and #700's whole lesson was that the vanishing is
# silent (see the .gitignore comment block).
#
# THE DISCRIMINATOR IS THE RULE THAT WINS, NOT A HAND-KEPT ALLOWLIST. `.gitignore` blocks
# `.claude/*` wholesale and re-admits members one by one, so "untracked" alone cannot separate
# a file someone forgot to negate from one that is ignored ON PURPOSE. `git check-ignore -v`
# names the winning rule, and that answers it exactly:
#   · the blanket `.claude/*`  → nobody decided anything about this file → FINDING
#   · any more specific rule   → someone wrote a line naming it → deliberate, stays quiet
# So `.claude/settings.local.json`, which has its own line, is exempt by construction rather
# than by being listed here — and a future per-machine file becomes exempt the moment someone
# writes its rule, with no edit to this function.
#
# UNTRACKED-BUT-VISIBLE IS DELIBERATELY NOT A FINDING. A new file that git can see is already
# `git status`'s job, and flagging it would turn the audit red for every work-in-progress file
# in the tree. The defect this exists for is invisibility: a blanket rule hid the file, so no
# other signal exists. That is the whole scope.
_core_claude_untracked_hits() { # _core_claude_untracked_hits <repo-root>
  local root="${1:-.}" tracked f rel line before pat
  [ -d "$root/.claude" ] || return 0
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || return 0
  # Newline-DELIMITED for a whole-line membership test with no subprocess per file, and so
  # `.claude/a.md` is not satisfied by `x.claude/a.md` — the same reasoning audit-core.sh
  # §1b gives for its own tracked list.
  tracked=$'\n'"$(git -C "$root" ls-files '.claude/*')"$'\n'
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#"$root"/}"
    [ "$tracked" != "${tracked/$'\n'"$rel"$'\n'/}" ] && continue # already ships
    # check-ignore exits 1 when the path is NOT ignored, which is the untracked-but-visible
    # case above — no output, so the loop below simply does not run. Fed by a heredoc, not a
    # pipe: audit-core.sh runs with pipefail and that exit 1 would read as a scanner failure.
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      before="${line%%	*}" # the `source:line:pattern` half, before the tab
      pat="${before#*:}"
      pat="${pat#*:}"
      case "$pat" in
      '.claude/*' | '.claude/**') printf '%s\n' "$rel" ;;
      esac
    done <<EOF
$(git -C "$root" check-ignore -v "$rel" 2>/dev/null)
EOF
  done <<EOF
$(find "$root/.claude" -type f 2>/dev/null | sort)
EOF
}

_core_claude_ref_hits() { # _core_claude_ref_hits <file>
  local f="${1:-}" line n p
  [ -f "$f" ] || return 0
  # Backtick assembled rather than typed: this file is itself scanned by §5i's
  # every-tracked-file walk, and the discipline of building the delimiter is the same one
  # _core_conflict_marker_hits follows for the reason spelled out there.
  local bt; bt="$(printf '\140')"
  # Fed by a heredoc rather than a pipe: this file sets no `set -e`, but audit-core.sh
  # runs with pipefail, and a grep that matches nothing exits 1 — through a pipe that
  # makes a clean "no references here" read as a scanner failure. The heredoc form is
  # also what §5d asks of every producer→reader pair in this tree.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n="${line%%:*}"; p="${line#*:}"
    p="${p#"$bt"}"; p="${p%"$bt"}"   # strip the delimiters
    p="${p%:[0-9]*}"                  # `…/tool-scout.md:164` cites a line, not a file
    case "$p" in
      *'*'* | *'?'* | */) continue ;; # a pattern or a directory, not a file claim
    esac
    printf '%s:%s\n' "$n" "$p"
  done <<EOF
$(grep -nIo "${bt}\.claude/[^${bt}]*${bt}" "$f" 2>/dev/null)
EOF
}

# ── _core_vendor_ref_hits: does a vendored script reach a file nobody vendors? ──
# _core_vendor_ref_hits <file> — print `LINE:PATH` for every repo-root-relative path
# <file> resolves at RUNTIME. Silence = it reaches nothing outside itself. Consumed by
# audit-core.sh §1e, which walks the closure from core.vendor's `# entry` roots and
# decides whether each reached path is actually vendored.
#
# EXTRACTION ONLY, same split as _core_claude_ref_hits above and for the same reason:
# judging "is this path in the vendored set" needs the two list files, so a scanner that
# did it could not be driven against test-core.sh's fixtures.
#
# WHY THIS EXISTS. #676 stopped vendoring the whole repo, so a script that DOES ship can
# now `source` a sibling that does NOT. Nothing else would catch it: §1's reverse drift
# reads `git ls-files` and sees a tracked, accounted-for file either way; core-integrity
# compares tree hashes and a consistently-wrong subset hashes consistently. The failure
# surfaces on a box, at runtime, as `no such file or directory` — in a consumer repo's CI,
# one fan-out later, pointing at Core.
#
# TWO SHAPES, both anchored on something that means "from the repo root":
#   `# shellcheck source=<path>`  — this tree puts one above every `source` line, and it is
#       already repo-root-relative by convention, which makes it the highest-signal and
#       lowest-guess form available. It is a directive, so it cannot drift from the source
#       line under it without shellcheck itself complaining.
#   `"$HERE/<path>"`             — $HERE is the repo root in every gate script here
#       (`cd "${BASH_SOURCE[0]%/*}/.."`), so what follows the slash is a repo path.
#
# SKIPPED, deliberately, and this is the honest part of the gate:
#   - anything with a `$` after the anchor — `$HERE/$f` is a variable, not a path;
#   - globs and trailing `/` — a pattern describes a set, and resolving it would mean
#     inventing a semantics the code does not have (the _core_claude_ref_hits argument);
#   - COMPUTED paths with no directive, e.g. common.sh's
#     `_CORE_OS_REPOS_FILE="$(cd -P "${BASH_SOURCE[0]%/*}/..")/os-repos.txt"`. Those are
#     invisible here by construction. They are covered by being listed BY HAND in
#     core.vendor with their consumer named — the same posture §1b takes toward .claude/.
#   - Lua `require`s and YAML `uses:`. nvim/ ships wholesale so the first cannot break;
#     the second is why .github/actions/setup-core-tools/action.yml is hand-listed.
#
# A gate that claimed to see all of that would be worse than one that says what it misses.
_core_vendor_ref_hits() { # _core_vendor_ref_hits <file>
  local f="${1:-}" line n p
  [ -f "$f" ] || return 0
  # Both greps are ANCHORED, and the $HERE one drops comment lines, because this scanner is
  # itself a tracked shell file that DOCUMENTS the two shapes it looks for. Unanchored, it
  # reported its own prose as references — a scanner that cannot read its own source without
  # tripping is one nobody trusts the output of.
  #
  # Heredoc, not a pipe: a grep that matches nothing exits 1, and under audit-core.sh's
  # pipefail that would make "this file reaches nothing" read as a scanner failure.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n="${line%%:*}"; p="${line#*:}"
    case "$p" in
      *'$'* | *'*'* | *'?'* | *'`'* | *'..'* | */ | '') continue ;;
    esac
    printf '%s:%s\n' "$n" "$p"
  done <<EOF
$( { grep -nIE '^[[:space:]]*# shellcheck source=[^ ]+$' "$f" 2>/dev/null |
       sed 's/:[[:space:]]*# shellcheck source=/:/'
     grep -nIE '\$\{?HERE\}?/[A-Za-z0-9_./-]+' "$f" 2>/dev/null |
       grep -vE '^[0-9]+:[[:space:]]*#' |
       sed -E 's/^([0-9]+):.*\$\{?HERE\}?\/([A-Za-z0-9_./-]+).*$/\1:\2/'
   } )
EOF
}

_audit_ls() { # _audit_ls <pathspec>… — content-gate file set, deduped
  {
    git ls-files -- "$@" 2>/dev/null
    git ls-files --others --exclude-standard -- "$@" 2>/dev/null
  } | sort -u
}

# ── the fleet list: ONE reader, and the file is MANDATORY ───────────────────
# scripts/os-repos.txt is the fleet. It used to be the fleet *and* three hardcoded fallback
# arrays — one each in sync-core.sh, fleet-drift.sh and core-integrity.sh — for when the file
# was missing or unreadable, so adding a target was four coordinated edits and the copy you
# forgot was the one that ran: the fallback fires in exactly the situation you are least able
# to notice it. test-core.sh asserted the four agreed, which is a backstop for a design flaw
# rather than a fix (#669).
#
# So there is now ONE parser, here, and no fallback at all. An unreadable or empty fleet list
# is a hard, loud failure in the three fan-out gates — the same posture real-bootstrap.yml
# takes when it derives zero legs, on the grounds that a gate which silently never runs reads
# as coverage. A sweep that quietly checks nothing is the failure this replaces, not a
# degraded mode worth keeping.
#
# Path is derived from THIS FILE's location (scripts/lib/ → ../os-repos.txt), not from each
# caller's $HERE: test-core.sh's fixtures copy common.sh into <fixture>/scripts/lib/ and write
# <fixture>/scripts/os-repos.txt, so this resolves correctly in the real repo and in every
# sandbox without the callers having to agree on a variable name — and it fixes the one caller
# (freshness-dashboard.sh) that was reading a cwd-relative path.
# `cd -P`'d rather than left as scripts/lib/../os-repos.txt: this path is printed in every
# error and skip message this loader produces, and a reader who has to mentally collapse a
# `lib/..` is one step further from checking whether the file is there.
_CORE_OS_REPOS_FILE="$(cd -P "${BASH_SOURCE[0]%/*}/.." 2>/dev/null && pwd)/os-repos.txt"

# Fills the global CORE_OS_REPOS. Returns 0, or non-zero with CORE_OS_REPOS_ERR set to the
# reason — it does NOT print. ONE message, three postures: the fan-out gates `fail` + exit 2,
# audit-core.sh's advisory sibling checks skip_env, test-core.sh's fleet scan skips. A loader
# that called fail() itself would force the advisory callers to red an unrelated section.
#
# A global array rather than stdout, deliberately: bash 3.2 has no mapfile (this runs on
# macOS), and `while read … < <(load_os_repos)` would throw away the return code in the
# process substitution — which is the whole signal.
#
# Takes NO arguments, deliberately. An optional `[<file>]` override was the obvious shape
# and every caller passed nothing, which is exactly what shellcheck SC2119 flags: a function
# with an unused optional $1 makes a bare call ambiguous with "inherit the script's $1", and
# it fired on all six callers. There is one fleet list; a seam nobody uses is not worth a
# per-call-site disable comment.
load_os_repos() { # load_os_repos — fill CORE_OS_REPOS from the fleet list
  local f="$_CORE_OS_REPOS_FILE" line
  CORE_OS_REPOS=()
  CORE_OS_REPOS_ERR=""
  [[ -r "$f" ]] || {
    CORE_OS_REPOS_ERR="fleet list unreadable: $f"
    return 2
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"                         # strip trailing comments
    line="${line#"${line%%[![:space:]]*}"}"    # ltrim
    line="${line%"${line##*[![:space:]]}"}"    # rtrim
    [[ -n "$line" ]] && CORE_OS_REPOS+=("$line")
  done <"$f"
  # Comments-only is the same hazard as absent: the caller would sweep an empty fleet and
  # report green. Callers may therefore expand "${CORE_OS_REPOS[@]}" after rc 0 without
  # tripping `set -u` on an empty array (bash <= 4.3).
  ((${#CORE_OS_REPOS[@]})) || {
    CORE_OS_REPOS_ERR="fleet list is empty: $f"
    return 2
  }
  return 0
}

# ── fleet-member resolution: by DIRECTORY NAME, then by REMOTE URL ─────────────
# scripts/os-repos.txt names the fleet by repo NAME, and sync-core.sh, fleet-drift.sh
# and core-integrity.sh all turned that name into a path by string-joining it onto the
# repos root. That coupling is invisible right up until a repo is RENAMED upstream: a
# box still holding the clone under its old directory name has the right remote, the
# right subtree and the right core.lock, and the fan-out skips it anyway — reporting
# "not cloned" for a repo that is sitting right there. dotfiles-Kali → dotfiles-Offense
# hit exactly this, and the only remedy on offer was "go `mv` the directory", on every
# machine, forever, for every future rename.
#
# So: keep the directory-name lookup as the fast path (it is right ~always, and costs no
# process), and fall back to asking each sibling clone what it actually IS. git remotes
# follow a rename automatically, so the clone's origin URL is the durable identity that
# the directory name only approximates.
#
# bash 3.2-safe (no associative arrays, no ${var,,}) — this runs on macOS too.

_repo_slug_of() { # _repo_slug_of <dir> — lowercased repo name from <dir>'s origin URL
  local url
  url="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 1
  [[ -n "$url" ]] || return 1
  url="${url%/}"      # a trailing slash would otherwise eat the whole name
  url="${url##*[/:]}" # both URL shapes at once: https://host/owner/repo AND git@host:owner/repo
  url="${url%.git}"
  [[ -n "$url" ]] || return 1
  # Case-fold: GitHub repo names are case-INSENSITIVE, so a clone of `dotfiles-offense`
  # is the same repo as `dotfiles-Offense` and must not read as a different one.
  printf '%s' "$url" | tr '[:upper:]' '[:lower:]'
}

resolve_repo_dir() { # resolve_repo_dir <root> <repo-name> — echo the clone path, or return 1
  local root="$1" name="$2" want dir slug
  [[ -n "$root" && -n "$name" ]] || return 1
  # Fast path, and deliberately `-d` on the directory rather than on its .git: this must
  # stay byte-identical to the string-join it replaces, so a conventional layout resolves
  # exactly as before (including to a path that exists but is not a repo — the callers
  # each have their own .git/core.lock checks and must keep making that call themselves).
  [[ -d "$root/$name" ]] && {
    printf '%s\n' "$root/$name"
    return 0
  }
  # Fallback: no directory of that name, so look for a clone that says it IS this repo.
  want="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  for dir in "$root"/*; do
    # `-e`, not `-d`: .git is a FILE in a worktree or a submodule checkout.
    [[ -e "$dir/.git" ]] || continue
    slug="$(_repo_slug_of "$dir")" || continue
    [[ "$slug" == "$want" ]] || continue
    printf '%s\n' "$dir"
    return 0
  done
  return 1
}

# ── byte-identical file comparison, without diffutils ──────────────────────────
# `cmp -s A B` was the obvious way to ask "did that rewrite change anything", and it is
# how sync-core.sh and update-nvim-plugins.sh both asked it. cmp ships in **diffutils**,
# which is not guaranteed present: a Tumbleweed box in this fleet had none installed, so
# neither `cmp` nor `diff` existed at all.
#
# A missing cmp does not fail usefully. `command not found` is a non-zero exit, and that
# is indistinguishable from "the files differ" — so both callers silently took their
# differ-branch for every file, in opposite directions:
#   - sync-core.sh counted every candidate workflow as repointed, writing inflated counts
#     into nine repos' commit messages while committing no workflow change at all (#572);
#   - update-nvim-plugins.sh reported drift that did not exist, which under --check is
#     exit 2 — the freshness gate going red on a lockfile that never moved.
# One failing open and the other failing closed off the same missing binary is the tell
# that the comparison, not either caller, was the wrong shape.
#
# git hash-object rather than a `command -v cmp` preflight: it removes the dependency
# instead of detecting it. It is byte-exact (SHA-1 over the blob — no newline
# normalisation, no text/binary heuristic), it needs no repository (verified: it hashes
# fine with cwd outside any work tree), and git is the one tool every script here already
# cannot run without. `sha256sum` was the other candidate and is wrong for this fleet:
# macOS ships `shasum`, not `sha256sum`, and these scripts run on the MacBook too.
#
# A missing operand counts as "differs" so a caller that lost its temp file rewrites
# rather than silently skipping — the safe direction for every caller here.
core_files_identical() { # core_files_identical <a> <b> — 0 iff byte-identical
  [[ -f "$1" && -f "$2" ]] || return 1
  [[ "$(git hash-object -- "$1")" == "$(git hash-object -- "$2")" ]]
}

# ── _core_workflow_ref_hits: a reusable workflow pinned to a foreign major ────
# _core_workflow_ref_hits <repo-root> <expected-major> — print every step that checks
# dotfiles-core out at `ref: vN` where N is not the current major. Silence = clean.
#
# WHY THIS EXISTS. The `*-call.yml` reusable workflows check dotfiles-core out a SECOND
# time to supply the scripts the job actually runs, at a hardcoded `ref: vN`. That ref
# has to move with every major bump, and it has now failed to twice:
#
#   · v3 → v4 — four sites left on `ref: v3` (frozen at v3.9.0). Present from v4.0.0
#     and not corrected until v4.10.0: TEN minor releases running the previous major's
#     scripts.
#   · v4 → v5 — six sites left on `ref: v4` (frozen at v4.19.0) while every caller
#     moved to `@v5`, so the workflow BODY was v5 and the scripts it ran were not.
#
# Both times the fix shipped with a comment telling the next person to keep it in step —
# claude-routines-call.yml still carries the v3 one, and lint-call.yml:90 says "keep in
# step on a major bump" in as many words. Both comments were written AFTER the first
# occurrence and neither prevented the second, because nothing FAILED: the ref resolves,
# the checkout succeeds, the job goes green, and it silently runs older code. That is the
# green-because-absent shape of #700, and the lesson is the same one recorded on
# _core_tool_skip_count — a comment is not a gate.
#
# WHY IT COMPARES AGAINST core.version. core.version is the major the tree IS; the refs
# are the major the tree CLAIMS to run. Those cannot legitimately disagree, so the
# comparison needs no list to maintain and no allowlist to drift.
#
# THE RELEASE ORDERING THIS IMPLIES, so nobody "fixes" a red release by loosening it:
# `make release VERSION=6.0.0` bumps core.version, so this gate goes red until the refs
# move to v6 in the SAME change. That is the intent — it is the "keep in step" comment
# made executable. It is safe even though the `v6` alias does not exist until `make
# publish`: Core's own CI never exercises these files (they are for OS repos to CALL),
# and an OS repo still pinned `@v5` reads the v5-TAGGED copy, which still says v5.
# Nobody reads main's copy in the window between the two.
#
# SCOPE IS THE dotfiles-core CHECKOUT, NOT EVERY `ref:`. The association is made per
# STEP — a chunk starting at a `- ` list item — so a `ref:` belonging to some other
# repository's checkout is never attributed here. A ref that is not `v<digits>` (a SHA,
# a branch, an expression) is deliberately NOT judged: this gate answers "which major",
# and inventing a second opinion about pinning style would make it two gates wearing one
# name. Order within the step does not matter; both keys are read before judging.
_core_workflow_ref_hits() { # _core_workflow_ref_hits <repo-root> <expected-major>
  local root="${1:-.}" want="${2:-}" f
  [ -n "$want" ] || return 0
  [ -d "$root/.github/workflows" ] || return 0
  for f in "$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    awk -v want="$want" -v file="${f#"$root"/}" '
      function flush(   i, ver, line, isdf) {
        if (n == 0) { return }
        isdf = 0; ver = ""; line = 0
        for (i = 0; i < n; i++) {
          if (buf[i] ~ /^[[:space:]]*repository:[[:space:]].*dotfiles-core[[:space:]]*$/) { isdf = 1 }
          if (buf[i] ~ /^[[:space:]]*ref:[[:space:]]*v[0-9]+[[:space:]]*$/) {
            ver = buf[i]
            sub(/^[[:space:]]*ref:[[:space:]]*v/, "", ver)
            sub(/[[:space:]]*$/, "", ver)
            line = ln[i]
          }
        }
        if (isdf && ver != "" && ver != want) {
          printf "%s:%d: checks out dotfiles-core at ref: v%s, but core.version is major v%s\n", \
            file, line, ver, want
        }
        n = 0
      }
      /^[[:space:]]*-[[:space:]]/ { flush() }
      { buf[n] = $0; ln[n] = NR; n++ }
      END { flush() }
    ' "$f"
  done
}

# ── _core_workflow_example_hits: a DOCUMENTED caller example on a foreign major ──
# _core_workflow_example_hits <repo-root> <expected-major> — print every commented
# caller example in .github/workflows/ that names a dotfiles-core reusable workflow at
# `@vN` where N is not the current major. Silence = clean.
#
# WHY THIS EXISTS, and why _core_workflow_ref_hits was not enough. That guard reads
# `ref:` KEYS and proves the workflow checks Core out at the right major. It does not
# read comments — so at v5 → v6 every `ref:` moved correctly and TWENTY-FIVE `@v5`
# references survived in the prose describing them (#821), including the copyable
# `uses:` examples in six `*-call.yml` headers. Nothing failed, because nothing was
# wrong in the code. An OS repo maintainer standing up a new caller from one of those
# examples pins a RETIRED major, and the resulting drift is exactly the silent kind
# _core_workflow_ref_hits was built to end.
#
# The sharpest illustration is claude-routines-call.yml, where the comment warning that
# this line "has now gone stale twice" sat directly above a correct `ref: v6` while
# itself saying `@v5`. Same defect, one level up, inside its own warning — which is the
# lesson both sibling helpers already record: a comment is not a gate.
#
# SCOPE IS A WORKFLOW PATH, NOT EVERY `@vN`. It matches only
# `dotgibson/dotfiles-core/.github/workflows/<file>@vN` — a string that is always a
# copyable caller reference and never narrative.
#
# THE OWNER IS PART OF THE MATCH, AND SO IS A LEFT BOUNDARY. Without them a bare
# `dotfiles-core/...` substring matches inside ANOTHER repository's name — a documented
# `someone/not-dotfiles-core/.github/workflows/x.yml@v5` would be reported as a stale
# Core example and would fail this always-on gate for a file it has no business judging.
# The boundary is `(^|[^A-Za-z0-9._-])`: the character before the owner must not itself
# be a repo-name character, so `notdotgibson/dotfiles-core/...` is excluded too. That distinction is load-bearing, because
# legitimate historical `vN` prose exists and MUST NOT be judged:
#
#   · claude-routines-call.yml narrates the v4→v5 cut ("every caller moved to `@v5`").
#   · lint-call.yml names the release the os.capabilities schema landed in (Core v5),
#     and the repos whose vendored core/ predates it.
#
# Bumping any of those would state something false, so a blanket `@vN` scan would be
# WORSE than no gate: it would train the next person to "fix" true sentences. The path
# anchor makes the match unambiguous without an allowlist to drift.
#
# WHAT IT DELIBERATELY DOES NOT CATCH. Bare prose ("pinned to v5", "only when v5
# moves") is not judged — it is indistinguishable from the historical sentences above
# without a marker, and this gate is not worth a marker convention. That prose is a
# human review question; the actively harmful case, a copyable example pinning a dead
# major, is the one made executable here.
_core_workflow_example_hits() { # _core_workflow_example_hits <repo-root> <expected-major>
  local root="${1:-.}" want="${2:-}" f
  [ -n "$want" ] || return 0
  [ -d "$root/.github/workflows" ] || return 0
  for f in "$root"/.github/workflows/*.yml "$root"/.github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    awk -v want="$want" -v file="${f#"$root"/}" '
      # COMMENT LINES ONLY. A live `uses:` belongs to check-modern.sh, which owns
      # pinning policy; this gate is about the example a human copies.
      /^[[:space:]]*#/ {
        line = $0
        while (match(line, /(^|[^A-Za-z0-9._-])dotgibson\/dotfiles-core\/\.github\/workflows\/[A-Za-z0-9._-]+@v[0-9]+/)) {
          ref = substr(line, RSTART, RLENGTH)
          ver = ref
          sub(/^.*@v/, "", ver)
          if (ver != want) {
            printf "%s:%d: caller example pins @v%s, but core.version is major v%s\n", \
              file, NR, ver, want
          }
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' "$f"
  done
}

# ── _core_make_gate_hits: local gates that cannot do what their name says ─────
# _core_make_gate_hits <repo-root> — print every Makefile gate in <repo-root> that
# announces a check it does not perform. Silence = clean. Output is `Makefile:LINE: msg`.
#
# WHY THIS EXISTS. dotgibson/dotfiles-core#775 swept eight OS repos by hand and found
# ELEVEN instances of three shapes, none of which any gate had ever caught:
#
#   · A SKIP THAT CANNOT SKIP (5). `@command -v x || { echo "skipping"; exit 0; }` on one
#     recipe line, the tool itself on the NEXT. make runs each recipe line in its OWN
#     shell, so the `exit 0` ends only that line: the target prints "skipping" and then
#     runs the missing tool anyway, exiting 127. Debian, Fedora (twice), Offense, Defense.
#   · A CHECK THAT CANNOT FAIL (1). openSUSE's `lint-sh` ended `shellcheck …; echo "ok"`.
#     With a semicolon the echo runs regardless AND becomes the line's exit status, so
#     the checker printed a screenful of findings and the target reported ok, exit 0.
#     Its two siblings used `&&` and `|| exit 1` and were correct, which is precisely why
#     nobody looked: it resembled working code.
#   · A BLOCKING CI LEG WITH NO LOCAL MIRROR (3). Arch, Gentoo and openSUSE shipped a
#     .markdownlint.jsonc that only CI ever read, for a leg blocking since #592 — a
#     required check nobody could run before pushing.
#
# WHY A GATE AND NOT ANOTHER NOTE. dotfiles-Debian's CHANGELOG already recorded the first
# shape, fixed it in ONE target, and wrote "The same shape is still present in the other
# OS repos' Makefiles." That note was correct, was never acted on, and the defect was
# still in five repos when someone finally swept by hand. Same lesson as
# _core_workflow_ref_hits records for the `ref: vN` majors: a comment is not a gate.
#
# PRIOR ART, and why this does not replace it. dotfiles-MacBook/test/check-skip-guards.sh
# tests the FIRST shape at RUNTIME — it rebuilds a PATH without the guarded tool and runs
# each target, which is stronger evidence than reading text. But it is one repo's script,
# it can only judge the repo it sits in, and it needs the tool to be genuinely absent. This
# is the static, fleet-portable complement: weaker per finding, but it can judge eight
# repos from outside, which is what the sweep actually needed. Keep both.
#
# WHY TEXTUAL AND NOT `make -n`. Running the recipes would need every tool installed and
# would EXECUTE them; the defect is in the recipe's SHAPE, readable without running
# anything. That also lets it judge a repo it is not standing in — which it must, because
# the callers live in eight other repositories and Core's audit can only see Core.
#
# SCOPE. Only `Makefile` at <repo-root>. Continuation lines are JOINED first, because every
# rule here is about what one LOGICAL recipe line does — the broken guards spanned two
# physical lines and the fixed ones span four. Judging physical lines inverts both answers.
_core_make_gate_hits() { # _core_make_gate_hits <repo-root>
  local root="${1:-.}" mk="${1:-.}/Makefile" mirror=0

  [ -f "$mk" ] || return 0

  # R3 needs to know whether markdownlint is reachable AT ALL, not merely whether the
  # Makefile spells it. Core runs it from scripts/audit-core.sh §7 behind `make audit`, so
  # a Makefile-only test would report Core — the repo that authored the rule — as the one
  # repo missing it. Look in the repo-owned scripts too, and never inside vendored core/.
  local _p _rc probed=0
  for _p in "$mk" "$root/scripts" "$root/test" "$root/tests"; do
    [ -e "$_p" ] || continue
    # NO --exclude-dir / -I. Both are GNU extensions; busybox grep REJECTS the first, so on
    # Alpine this probe exited non-zero, was read as "no mirror", and reported Core — the
    # repo that authors the rule — as the one repo missing it. A false finding produced by
    # an unsupported flag, inside the gate whose entire subject is checks that answer
    # wrongly. Neither flag was needed: none of the paths searched is core/ or .git.
    grep -rq 'markdownlint' "$_p" 2>/dev/null
    _rc=$?
    case "$_rc" in
      0) mirror=1; probed=1; break ;;
      1) probed=1 ;;  # searched it, genuinely absent
      *) : ;;         # grep could not search this path — that is not evidence of absence
    esac
  done
  # If NOTHING could be searched, R3 has no evidence either way, so it says nothing rather
  # than asserting a missing mirror. Unknown and absent are different facts and only one is
  # a defect — the same distinction scripts/os-repos.txt draws for the fan-out gates, which
  # fail loudly rather than sweep a substituted list. Suppressing here is the safe
  # direction: R1/R2/R4 still run, and a real missing mirror surfaces the moment a working
  # grep is present.
  [ "$probed" = 1 ] || mirror=1

  awk -v cfg="$( [ -f "$root/.markdownlint.jsonc" ] && echo 1 || echo 0 )" -v mirror="$mirror" '
    # tool_runs(line, tool) — does `line` INVOKE tool, as opposed to merely probing for it
    # with `command -v tool`? The probes are erased first, so `command -v zsh` alone is not
    # an invocation while `zsh -n "$f"` is. This is the whole difference between a guard
    # that skips correctly and one that does not.
    function tool_runs(line, tool,   s, q) {
      # Quoted text is PROSE, not a command. Erasing it first is what makes this rule
      # work at all: every one of these guards names the missing tool in its own skip
      # message ("markdownlint-cli2 not installed: npm i -g markdownlint-cli2 …"), so a
      # naive word match found the tool on the guard line and concluded the guard was
      # fine. That single omission suppressed all five real findings on the first run.
      q = sprintf("%c", 39)
      s = line
      gsub(/"[^"]*"/, " ", s)
      gsub(q "[^" q "]*" q, " ", s)
      gsub(/command[ \t]+-v[ \t]+[^ \t;|&)}]+/, " ", s)
      gsub(/have[ \t]+[^ \t;|&)}]+/, " ", s)
      return (s ~ ("(^|[^-_/[:alnum:]])" tool "([^-_[:alnum:]]|$)"))
    }
    function flush_recipe(   i, j, tool, guarded) {
      for (i = 1; i <= ln; i++) {
        # ── R1: a skip that cannot skip ──────────────────────────────────────
        # Fires ONLY on the shape that actually breaks: a `command -v TOOL` probe whose
        # `exit 0` is meant to skip TOOL, where TOOL is not on this logical line but IS on
        # a later one. That precision matters — dotfiles-Alpine guards shellcheck and then
        # runs shellcheck ON THE SAME LINE, so its `exit 0` skips exactly what it promises
        # and must not be reported. A blunter "exit 0 before the last line" rule called
        # that a defect, and would have taught the fleet to ignore this gate.
        if (i < ln && lbody[i] ~ /(^|[^0-9a-zA-Z_])exit[ \t]+0([^0-9]|$)/ \
            && match(lbody[i], /command[ \t]+-v[ \t]+[^ \t;|&)}]+/)) {
          tool = substr(lbody[i], RSTART, RLENGTH)
          sub(/^command[ \t]+-v[ \t]+/, "", tool)
          if (!tool_runs(lbody[i], tool)) {
            guarded = 0
            for (j = i + 1; j <= ln; j++) { if (tool_runs(lbody[j], tool)) { guarded = j; break } }
            if (guarded) {
              printf "Makefile:%d: target `%s` says it skips when `%s` is missing, but the `exit 0` ends only THIS recipe line — line %d runs `%s` anyway (make gives each line its own shell)\n", \
                lstart[i], target, tool, lstart[guarded], tool
            }
          }
        }
        # ── R2: a check that cannot fail ─────────────────────────────────────
        # A checker whose status is dropped by a bare `;` before a success echo. The
        # `[^;&|]*;` is load-bearing: it requires NOTHING between the checker and the
        # semicolon, so `zsh -n "$f" || exit 1; … echo ok` and `bash -n $(F) && echo ok`
        # — both correct, both present in this fleet — are not reported. Only the arm that
        # genuinely throws the status away is.
        if (lbody[i] ~ /(shellcheck|markdownlint-cli2|actionlint|luacheck)[^;&|]*;[ \t]*\\?[ \t]*(echo|printf)[^;]*(ok|OK|pass|clean)/) {
          printf "Makefile:%d: target `%s` ends a checker with `;` before a success echo — the echo runs regardless AND becomes the line exit status, so findings print and the target still exits 0 (use `&&`)\n", \
            lstart[i], target
        }
      }
      ln = 0
    }
    /markdownlint-cli2/ {
      # ── R4: a local scope narrower than the blocking gate ─────────────────
      # The gate lints `git ls-files "*.md" ":!:core/**"` — recursive. A bare quoted glob
      # is top-level only (plus whatever single directory is spelled out), so it silently
      # under-covers: in three repos the .github/ templates were CI-enforced and locally
      # invisible, and in dotfiles-MacBook — whose own ci.yml runs the very same target —
      # nothing anywhere linted them. A make VARIABLE is trusted: it is the shape every
      # correct repo uses, and chasing its definition here would make this a second parser.
      if ($0 ~ /["'"'"']\*\.md["'"'"']/ && $0 !~ /\$\(/) {
        printf "Makefile:%d: markdownlint runs on a `*.md` glob — top-level only, while the gate lints `git ls-files \"*.md\" \":!:core/**\"` recursively, so anything under .github/ is enforced and locally invisible\n", NR
      }
    }
    /^\t/ {
      body = $0
      sub(/^\t/, "", body)
      if (cont) { lbody[ln] = lbody[ln] " " body }
      else      { ln++; lbody[ln] = body; lstart[ln] = NR }
      cont = (body ~ /\\[ \t]*$/)
      next
    }
    { cont = 0; if (ln) { flush_recipe() } }
    /^[^\t#. ][^:=]*:([^=]|$)/ { target = $0; sub(/:.*/, "", target) }
    END {
      if (ln) { flush_recipe() }
      # ── R3: a blocking CI leg with no local mirror ────────────────────────
      # A .markdownlint.jsonc declares that this repo has markdown house rules. Since #592
      # the reusable gate ENFORCES them and blocks. Carrying the config with no way to run
      # it locally is a required check the author cannot exercise — the inverse of the two
      # shapes above, and why three repos shipped a config that was pure decoration.
      if (cfg == 1 && mirror == 0) {
        print "Makefile:1: .markdownlint.jsonc exists but nothing in this repo runs markdownlint — the reusable gate has BLOCKED on it since dotgibson/dotfiles-core#592, so this is a required check with no local mirror"
      }
    }
  ' "$mk"
}
