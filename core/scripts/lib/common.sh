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
    # `atuin` is the hermetic self-test of scripts/verify-atuin-guard.sh — the premise
    # DETECTOR's own harness, not shipped Core (it is absent from core.manifest and nothing
    # vendors it). Its own axis because it is by far the most expensive thing the suite
    # does — measured at 197s of a 286s run, 68% — while being unreachable from almost
    # every change that pays for it. The real measurement, against live upstream atuin,
    # runs weekly in .github/workflows/atuin-guard-verify.yml; this axis only decides
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
  direnv-hook) echo "core/zsh/00-tools.zsh (band 00 — loads under every CORE_PROFILE)" ;;
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

_audit_ls() { # _audit_ls <pathspec>… — content-gate file set, deduped
  {
    git ls-files -- "$@" 2>/dev/null
    git ls-files --others --exclude-standard -- "$@" 2>/dev/null
  } | sort -u
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
