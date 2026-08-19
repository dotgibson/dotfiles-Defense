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
# fails SAFE to the full run rather than silently narrowing a gate on the 10-repo fan-out.
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
