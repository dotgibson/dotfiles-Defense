#!/usr/bin/env bash
# scripts/audit-core.sh
# ──────────────────────────────────────────────────────────────────────────────
# THE AUDIT BUTTON — this repo's test suite.
#
# core.manifest calls itself "the contract. Audit scripts and the promotion
# checklist read it." This is that audit script. It verifies Core is internally
# consistent BEFORE it gets vendored (via scripts/sync-core.sh) into all nine OS repos,
# where a defect would fan out N-way.
#
# Checks (each is a section; a failure in one does not abort the others):
#   1. manifest <-> filesystem drift   — every manifest path exists; every
#                                         tracked Core file is listed or allowlisted
#  1b. routine reference integrity     — every .claude/ path the maintenance routines
#                                         say they READ exists and is tracked (the
#                                         mirror of §1: an accounted-for file that was
#                                         never tracked is invisible to git ls-files)
#   2. executable-bit assertions       — *.sh and bin/clip* must be +x in the
#                                         git index; zsh/*.zsh must NOT be (sourced)
#   3. shell syntax                     — bash -n on bash scripts; zsh -n on zsh modules
#   4. lua                              — luacheck nvim/        (if luacheck present)
#  4b. nvim module reachability        — no orphaned lua module under nvim/lua/gerrrt
#                                         (the backstop the directory-granular manifest
#                                          entry for nvim/ cannot provide)
#   5. lint                             — shellcheck            (if present)
#  5c. Core⇄OS boundary                — no OS-absolute paths in portable zsh modules
#  5d. pipefail SIGPIPE hazard        — no shell-string producer piped into a reader
#                                         that exits early (grep -q / awk exit / head)
#  5e. leaked RETURN trap             — no `trap … RETURN` that fails to disarm the
#                                         slot (it fires again in the CALLER's frame)
#   6. config files                     — toml/yaml parse-check (if python3 present)
#   7. markdown                          — markdownlint (if markdownlint-cli2 present)
#   8. workflows                         — actionlint on .github/workflows (if present)
#  8b. secrets                           — gitleaks working-tree scan (if present)
#   9. version consistency              — pre-commit hook revs == tool-versions.env;
#                                         core.version SemVer + CHANGELOG coherence
#  10. behavioral                       — load-order smoke + function units (test-core.sh)
#
# We deliberately do NOT enforce shfmt: the hand-tuned scripts here use an
# intentional compact one-liner style that shfmt would expand. shellcheck (real
# bugs) is enforced; formatting is left to .editorconfig + the author's eye.
#
# Graceful degradation (mirrors zsh/00-tools.zsh): a missing linter is SKIPPED with
# a notice, never a failure — so this runs on a bare box AND in CI, where the
# tools are installed. Exit status is non-zero only on a real FAIL.
#
# Usage:
#   ./scripts/audit-core.sh            # run every section
#   ./scripts/audit-core.sh --quiet    # only print SKIP/FAIL + the summary
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

QUIET=0
JSON=0           # --json: machine-readable summary on stdout (implies quiet); for CI/editors
STRICT=0         # --strict: treat any SKIP as a failure (a gate that didn't actually run)
REQUIRE_SIBLINGS=0 # --require-siblings: fail if a fleet-wide gate had no sibling OS repo
                   # to read. Opt-in: absent siblings are normal on a dev box, and the
                   # default must not red for where you happened to invoke from.
CHANGED=0        # --changed: derive the scope from the local git diff (fast dev loop)
SCOPE_EXPLICIT=0 # an explicit --scope always wins over --changed
# Scope gates the SLOW, area-specific sections so a per-area push (driven by
# scripts/ci-classify.sh) pays only for what it changed — e.g. a docs-only PR runs
# the cheap structural/config/markdown checks but skips the zsh and nvim toolchains.
# FAIL-CLOSED default: with no --scope, BOTH areas run (full audit), so a local
# `make audit`, pre-commit, and an un-classified push are never silently narrowed.
# Only ci.yml passes an explicit, classifier-derived --scope. The cheap, cross-cutting
# checks (manifest, exec-bits, toml/yaml/json, markdown, workflows, version) ALWAYS run.
SCOPE_SHELL=1
SCOPE_NVIM=1
SCOPE_ATUIN=1
# Shared palette + pass/skip/fail/hdr/have + _set_scope (one definition for every gate
# script). Sourced HERE — before the arg loop below calls _set_scope — and after QUIET
# is set so the lib's `: "${QUIET:=0}"` preserves it.
#
# Via the ALREADY-ABSOLUTE $HERE, not ${BASH_SOURCE[0]%/*}: line 48 has already cd'd,
# while BASH_SOURCE stays relative to the caller's original directory, so the two
# disagree the moment this script is invoked by a relative path from somewhere else.
# `bash ../../repo/scripts/audit-core.sh` printed "lib/common.sh: No such file or
# directory" and then carried on with every helper undefined. Pre-existing; found while
# fixing the same shape in check-modern.sh, and fixed here rather than left as the one
# copy of the bug the reader would trip over next.
# shellcheck source=scripts/lib/common.sh
source "$HERE/scripts/lib/common.sh"
# Render the active scope as test-core.sh expects it (a comma list of shell/nvim/atuin,
# or `none`).
_scope_str() {
  local s=""
  ((SCOPE_SHELL)) && s="shell"
  ((SCOPE_NVIM)) && s="${s:+$s,}nvim"
  ((SCOPE_ATUIN)) && s="${s:+$s,}atuin"
  printf '%s' "${s:-none}"
}

# Parse EVERY argument (not just $1), so an unknown flag OR a stray extra operand is
# REJECTED with a hint rather than silently ignored — `audit-core.sh --quiet extra`
# or a typo like `--hepl` used to slip through and just run the full audit, masking it.
# -h/--help prints usage and exits clean.
while (($#)); do
  case "$1" in
  -q | --quiet) QUIET=1 ;;
  --json) JSON=1 QUIET=1 CORE_JSON=1 && export CORE_JSON ;; # only JSON on stdout (incl. nested skips)
  --strict) STRICT=1 ;;
  --require-siblings) REQUIRE_SIBLINGS=1 ;;
  --scope)
    # Require an explicit value: without this, `--scope --quiet` would swallow the
    # next flag as the scope list and silently drop it.
    if (($# < 2)) || [[ "$2" == -* ]]; then
      printf 'audit-core.sh: --scope requires a value (shell,nvim,atuin|all|none)\n' >&2
      printf 'try: audit-core.sh --help\n' >&2
      exit 2
    fi
    shift
    _set_scope "$1"
    SCOPE_EXPLICIT=1
    ;;
  --scope=*)
    _set_scope "${1#*=}"
    SCOPE_EXPLICIT=1
    ;;
  --changed) CHANGED=1 ;;
  --color)
    if (($# < 2)) || ! _core_set_color "$2"; then
      printf 'audit-core.sh: --color requires a value (auto|always|never)\n' >&2
      printf 'try: audit-core.sh --help\n' >&2
      exit 2
    fi
    shift
    ;;
  --color=*)
    _core_set_color "${1#*=}" || {
      printf 'audit-core.sh: --color requires auto|always|never\n' >&2
      exit 2
    }
    ;;
  -h | --help)
    cat <<'EOF'
usage: audit-core.sh [-q|--quiet] [--strict] [--require-siblings] [--scope LIST] [--changed]
                     [--color WHEN] [--json] [-h|--help]

THE audit button — manifest/exec-bit/syntax/lint/config/markdown/workflow/
version/behavioral checks. CI and pre-commit run this exact script.

  -q, --quiet     only print SKIP/FAIL lines and the final summary
  --json          emit a machine-readable summary object on stdout (implies --quiet):
                  {pass,skip,fail,seconds,strict,tool_skips,env_skips,partial,
                  skipped[],result}. `partial` is true whenever anything skipped. For CI
                  steps / editor integrations that want to parse, not scrape, the result.
  --strict        fail if any gate SKIPPED because its TOOL is absent — that gate did
                  not actually run, so a "green" with such skips is only PARTIAL. An
                  out-of-scope skip (a narrowed --scope/--changed run) is intentional and
                  does NOT trip --strict, so this is safe on a fully-provisioned CI leg
                  where every IN-SCOPE tool is installed. The summary names every skip.
  --require-siblings
                  fail if a FLEET-WIDE gate (helper adoption, the gitleaks-policy sweep,
                  the coverage register) had no sibling OS repo checked out to read.
                  Those gates skip silently-by-default on a lone clone — including in CI,
                  which checks out only this repo — so they have never actually run there.
                  This is the flag that says "I expect full fleet coverage from this run".
  --scope LIST    limit the slow area-specific sections to a comma list:
                  shell, nvim, atuin, all (default), none. Cheap structural/config/
                  markdown/workflow/version checks always run. CI sets this from
                  scripts/ci-classify.sh; omit it locally to run the full audit.
                  `atuin` is the hermetic self-test of the premise detector
                  (scripts/verify-atuin-guard.sh) — the suite's most expensive
                  section by a wide margin, and reachable only from that script,
                  zsh/00-tools.zsh and atuin/.
  --color WHEN    auto (default) | always | never. `always` keeps colour when piped
                  (e.g. into `less -R`); NO_COLOR still wins. Also via CORE_COLOR env.
  --changed       derive the scope from your local git diff (working tree vs HEAD,
                  falling back to the branch delta vs the default branch) using the
                  SAME scripts/ci-classify.sh CI uses — so a docs- or nvim-only edit
                  skips the gates it can't affect, tightening the dev loop. Fails SAFE
                  to the full run when the diff can't be resolved. An explicit --scope
                  overrides this.
  -h, --help      show this help and exit
EOF
    exit 0
    ;;
  *)
    printf 'audit-core.sh: unexpected argument: %s\n' "$1" >&2
    printf 'try: audit-core.sh --help\n' >&2
    exit 2
    ;;
  esac
  shift
done

# ── --changed: derive the scope from the local git diff ───────────────────────
# Reuse the EXACT classifier CI runs (scripts/ci-classify.sh) so `make audit-changed`
# narrows to the same gates a push would — one definition of path→gate, no drift. The
# changed set is the working tree vs HEAD plus untracked files; when the tree is clean
# we fall back to the branch delta vs the default branch. Anything unresolvable → the
# full run (fail-safe), matching CI's "detection miss never hides a gate" rule. An
# explicit --scope already set SCOPE_EXPLICIT and wins.
_changed_scope() {
  if ! have git || ! git rev-parse --git-dir >/dev/null 2>&1; then
    printf 'all'
    return
  fi
  local files base
  files="$({
    git diff --name-only HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | sort -u)"
  if [[ -z "$files" ]]; then
    for base in origin/main main origin/master master; do
      git rev-parse -q --verify "$base" >/dev/null 2>&1 || continue
      files="$(git diff --name-only "$base"...HEAD 2>/dev/null)"
      break
    done
  fi
  [[ -n "$files" ]] || {
    printf 'all'
    return
  } # nothing resolvable → full (safe)
  local out scope=""
  out="$(printf '%s\n' "$files" | "$HERE/scripts/ci-classify.sh" 2>/dev/null)"
  # Parse via the shared reader (scripts/lib/common.sh): it sets CLASSIFY_SHELL/CLASSIFY_NVIM/
  # CLASSIFY_ATUIN and returns non-zero if the classifier errored or emitted garbage on ANY of
  # the three — in which case fail SAFE to the full run rather than silently returning "none"
  # and skipping every slow gate.
  if ! _core_read_classify "$out"; then
    printf 'all'
    return
  fi
  [[ "$CLASSIFY_SHELL" == true ]] && scope="shell"
  [[ "$CLASSIFY_NVIM" == true ]] && scope="${scope:+$scope,}nvim"
  [[ "$CLASSIFY_ATUIN" == true ]] && scope="${scope:+$scope,}atuin"
  printf '%s' "${scope:-none}"
}
if ((CHANGED)) && ((!SCOPE_EXPLICIT)); then
  _cs="$(_changed_scope)"
  ((QUIET)) || printf '%s== --changed → scope %s ==%s\n' "$c_blu" "$_cs" "$c_rst"
  _set_scope "$_cs"
fi

# Wall-clock from here, surfaced in the summary — so a long run (the headless nvim /
# zsh legs) reads as "took Ns", not "hung", and a regression in audit cost is visible.
SECONDS=0

# ── Overlap the behavioral suite with the static gates ────────────────────────
# scripts/test-core.sh (headless nvim ×2 + the zsh -i load legs) dominates wall-clock,
# and it shares NOTHING with the static sections below (manifest/exec-bit/syntax/lint/
# config) — they're read-only and independent. So kick it off NOW in the background and
# collect it at section 10, overlapping its slow legs with the fast static checks instead
# of running strictly after them. It still contributes EXACTLY one pass/fail to the
# summary (on its exit code), as before — only the wall-clock changes. Output is buffered
# to a file and re-printed in place at section 10 so it never interleaves with the static
# sections; CLICOLOR_FORCE keeps its colour when our own stdout is a tty. CORE_AUDIT_SERIAL=1
# forces the old inline behaviour (debugging / a shell with no job control).
BEHAV_BG=0
BEHAV_PID=""
BEHAV_OUT=""
TEST_ARGS=(--scope "$(_scope_str)")
((QUIET)) && TEST_ARGS+=(--quiet)
if [[ "${CORE_AUDIT_SERIAL:-0}" != 1 ]]; then
  BEHAV_OUT="$(mktemp "${TMPDIR:-/tmp}/core-audit-behav.XXXXXX")"
  # Force colour through the file capture only when OUR stdout is a real terminal.
  _behav_color=""
  [[ -t 1 && -z "${NO_COLOR:-}" ]] && _behav_color="CLICOLOR_FORCE=1"
  env $_behav_color CORE_TEST_NESTED=1 \
    ./scripts/test-core.sh ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} >"$BEHAV_OUT" 2>&1 &
  BEHAV_PID=$!
  BEHAV_BG=1
fi

# Reap the backgrounded behavioral child + remove its capture file on ANY exit. The
# normal path (section 10) already waits for it and rm's the temp; but a Ctrl-C — or
# an early FAIL/exit — mid-audit otherwise orphans the slow nvim/zsh leg and leaks the
# mktemp. EXIT does the cleanup (idempotent: kill on a reaped pid and a second rm -f are
# both no-ops); INT/TERM just exit with the conventional 128+signal code and let EXIT fire.
_audit_cleanup() {
  [[ -n "${BEHAV_PID:-}" ]] && kill "$BEHAV_PID" 2>/dev/null
  [[ -n "${BEHAV_OUT:-}" ]] && rm -f "$BEHAV_OUT"
}
trap _audit_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Tracked files that live in dotfiles-core but are NOT vendored into OS repos'
# core/ subtree — repo-meta and dev tooling. Anything tracked, not matched by the
# manifest, must appear here (or under a META_PREFIXES dir) or section 1 flags it.
META_ALLOWLIST=(
  README.md PORTING-MATRIX.md CONTRIBUTING.md CHANGELOG.md LICENSE SECURITY.md aliases.md CLAUDE.md
  ARCHITECTURE.md PORTABILITY.md VENDORING.md CODE_OF_CONDUCT.md
  PARITY.md RELEASE-STRATEGY.md RELEASE-RUNBOOK.md GITHUB-APP-AUTH.md V4-PROPOSAL.md V5-PROPOSAL.md
  core.manifest .gitignore .gitattributes .editorconfig .pre-commit-config.yaml .markdownlint.jsonc .shellcheckrc renovate.json .prettierrc.json gitleaks.toml
  Makefile cliff.toml
  nvim/.luacheckrc
  CODEOWNERS pull_request_template.md
)
# Directory prefixes whose tracked contents are allowlisted wholesale. scripts/ is
# this repo's DEV TOOLING (audit/test/bench/sync/update-plugins) — the gate scripts
# themselves, NOT shipped Core (absent from core.manifest, so not symlinked by an OS
# repo's bootstrap; only bin/clip* + the manifest paths are). The subtree copy still
# carries them physically — "not shipped" means "not in the manifest", not "not on disk".
# Listing the dir, not each script, means a new dev tool is covered the moment it lands
# here — the bin/-vs-scripts/ split is exactly what makes that unambiguous.
# .claude/ holds the Claude-Code config — the SessionStart hook (provisions the gate
# toolchain in a remote session) plus the maintenance routines (commands/ + agents/
# for /doc-audit, /tool-scout, /freshness-triage) — repo-meta tooling, not shipped Core
# (absent from core.manifest).
# .devcontainer/ is the dev-environment definition (one-command CI parity) — dev tooling
# too, not part of the shipped Core layer (not in core.manifest).
# assets/ is README media (the VHS demo tape + rendered gif) — repo-meta for the public
# showcase, not shipped Core (absent from core.manifest); it rides along physically in the
# subtree copy but is never symlinked.
META_PREFIXES=(examples/ .github/ scripts/ .claude/ .devcontainer/ assets/)


# ── 1. manifest <-> filesystem drift ─────────────────────────────────────────
hdr "manifest ↔ filesystem"
# Parse manifest: strip comments/blank lines, take the first whitespace token.
# Use a read loop (not `mapfile`) — mapfile is bash 4+, and this gate must also
# run on macOS's stock bash 3.2 (the dotfiles-MacBook target / the macOS CI leg).
MANIFEST_PATHS=()
while IFS= read -r p; do
  MANIFEST_PATHS+=("$p")
done < <(sed -e 's/#.*//' -e 's/[[:space:]]*$//' core.manifest | awk 'NF {print $1}')
for p in "${MANIFEST_PATHS[@]}"; do
  if [[ "$p" == */ ]]; then
    if [[ -d "$p" ]]; then pass "dir  $p"; else fail "manifest lists missing dir:  $p"; fi
  else
    if [[ -e "$p" ]]; then pass "file $p"; else fail "manifest lists missing file: $p"; fi
  fi
done

# Reverse direction: tracked Core files not covered by the manifest or allowlist.
is_listed() { # $1 = path
  local f="$1" m pre
  for m in "${MANIFEST_PATHS[@]}"; do
    [[ "$f" == "$m" ]] && return 0                # exact file match
    [[ "$m" == */ && "$f" == "$m"* ]] && return 0 # under a listed dir
  done
  for m in "${META_ALLOWLIST[@]}"; do [[ "$f" == "$m" ]] && return 0; done
  for pre in "${META_PREFIXES[@]}"; do [[ "$f" == "$pre"* ]] && return 0; done
  return 1
}
if have git && git rev-parse --git-dir >/dev/null 2>&1; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    is_listed "$f" || fail "tracked file not in manifest/allowlist: $f"
  done < <(git ls-files)
  pass "reverse-drift scan complete (tracked files all accounted for)"
else
  skip "reverse-drift scan (not a git checkout)"
fi

# ── 1b. routine reference integrity (the inverse of §1's reverse drift) ──────
# §1 above asks, in both directions, whether every TRACKED file is accounted for. This
# asks the mirror question: is every file the maintenance routines say they READ actually
# there, and actually shipped? Those are different failures and §1 structurally cannot see
# the second one — its reverse walk is fed by `git ls-files`, so a file that was never
# tracked is not in the stream and `is_listed` is never called on it. The manifest
# direction never looks either: .claude/ is repo-meta, allowlisted wholesale by
# META_PREFIXES, which is correct and is also why nothing was watching.
#
# WHY IT EXISTS. #661 taught /tool-scout to consult a decided-and-rejected ledger at
# .claude/tool-decisions.md, shipped the three files that reference it, and did not ship
# the ledger: .gitignore's `.claude/*` negations are per-DIRECTORY, so commands/ and
# agents/ vendored out while the file they point at stayed untracked (#700). The routine's
# own instruction is to say "none" when a candidate has no prior decision — so with no
# file every candidate resolves to "none", in the exact voice that means CHECKED. The
# report then asserts the ledger was consulted while consulting nothing, which is worse
# than the ambiguity #634 was filed to remove, because the absence is no longer visible.
# It is the same shape as core.manifest naming a verify-core backstop that never existed
# (#454): an assertion pointing at a file nobody created.
#
# TWO VERDICTS, NOT ONE. "absent" and "present but untracked" are different bugs with
# different fixes — author the file, versus negate it in .gitignore — and this defect was
# the second, which every report of it so far has called the first. Collapsing them into
# one message would hand the reader the wrong repair.
#
# PLAIN `git ls-files`, NOT _audit_ls. The rule is in common.sh: a gate asking "what does
# GIT RECORD?" takes the tracked list, and _audit_ls deliberately adds
# untracked-but-not-ignored files. Here that inclusion would be fatal rather than noisy —
# an ignored file is exactly what this gate exists to catch, and _audit_ls would wave the
# one on the author's disk straight through while every clone stayed broken.
#
# WHY IT BLOCKS ON ARRIVAL, the §5i argument: the tree is green the moment this lands (the
# four references all resolve), so every future hit is a regression introduced by the
# commit under test, not inherited fleet drift.
hdr "routine reference integrity"
if ! have git || ! git rev-parse --git-dir >/dev/null 2>&1; then
  skip "routine reference integrity (not a git checkout)"
else
  cref_fail=0
  # Newline-DELIMITED, not merely newline-separated: the leading and trailing newlines let
  # the membership test below match a whole line without a subprocess, and without
  # `.claude/tool-decisions.md` being satisfied by a hypothetical `x.claude/tool-decisions.md`.
  # A `grep -qxF` per reference would be the obvious spelling and is exactly what §5d
  # forbids — a shell string piped into a reader that exits early.
  cref_tracked=$'\n'"$(git ls-files)"$'\n'
  while IFS= read -r cref_src; do
    [[ -z "$cref_src" ]] && continue
    while IFS= read -r cref_hit; do
      [[ -z "$cref_hit" ]] && continue
      cref_line="${cref_hit%%:*}"
      cref_path="${cref_hit#*:}"
      if [[ ! -e "$cref_path" ]]; then
        fail "$cref_src:$cref_line names $cref_path, which does not exist — a routine instructed to read a missing file reports 'none' rather than failing, so the absence reads as a clean check"
        cref_fail=1
      elif [[ "$cref_tracked" != *$'\n'"$cref_path"$'\n'* ]]; then
        fail "$cref_src:$cref_line names $cref_path, which exists here but is NOT TRACKED — it reaches no clone, no CI run and none of the nine vendored repos. Negate it in .gitignore (#700)"
        cref_fail=1
      fi
    done <<EOF
$(_core_claude_ref_hits "$cref_src")
EOF
  done <<EOF
$(git ls-files '.claude/commands/*.md' '.claude/agents/*.md')
EOF
  ((cref_fail)) || pass "routine reference integrity (every .claude/ path the routines name resolves and is tracked)"
  unset cref_fail cref_tracked cref_src cref_hit cref_line cref_path
fi

# ── 1c. unreferenced .claude/ files (the half §1b structurally cannot reach) ──
# §1b asks whether every .claude/ path a routine NAMES is shipped. That only fires because
# something pointed at the file. This asks the question with no reference to lean on: is any
# file under .claude/ sitting on this disk and going nowhere?
#
# WHY BOTH ARE NEEDED. #700 was caught only because three routine files named the ledger. A
# .claude/ file nothing references — a new subagent, a convention-named config a hook reads,
# a second ledger — has no such witness, and `.gitignore`'s blanket `.claude/*` means git
# prints nothing about it: not in `git status`, not added by `git add -A`, not in any content
# gate here (they all read the working tree, where it is present and correct). The audit was
# answering "is this tree consistent" — it was — while nobody asked "will this reach a clone".
#
# THE RULE THAT WINS IS THE VERDICT. The scanner asks `git check-ignore -v` which line hid the
# file. The blanket `.claude/*` means nobody decided anything about it; any more specific rule
# means somebody wrote a line naming it, which is a decision and stays quiet. So
# settings.local.json is exempt because .gitignore names it, not because this gate lists it,
# and the next per-machine file becomes exempt the moment its rule is written.
#
# The two verdicts §1b separates do not arise here: a file this gate sees always EXISTS (it
# was found on disk), so "author it" is never the repair. The repair is always one .gitignore
# line — a negation if it should ship, a specific rule if it should not.
#
# WHY IT BLOCKS ON ARRIVAL, the §5i/§1b argument: the tree is green the moment this lands —
# settings.local.json is the only untracked file under .claude/, and it carries its own rule —
# so every future hit is a regression introduced by the commit under test.
hdr "unreferenced .claude/ files"
if ! have git || ! git rev-parse --git-dir >/dev/null 2>&1; then
  skip "unreferenced .claude/ files (not a git checkout)"
elif [[ ! -d .claude ]]; then
  skip "unreferenced .claude/ files (no .claude/ directory)"
else
  cunt_fail=0
  while IFS= read -r cunt_path; do
    [[ -z "$cunt_path" ]] && continue
    fail "$cunt_path exists here but git will never ship it — it is hidden by the blanket \`.claude/*\` rule, so it reaches no clone, no CI run and none of the nine vendored repos, and nothing else reports it. Negate it in .gitignore if it is shared; give it its own ignore rule if it is per-machine (#700)"
    cunt_fail=1
  done <<EOF
$(_core_claude_untracked_hits "$HERE")
EOF
  ((cunt_fail)) || pass "unreferenced .claude/ files (every file under .claude/ either ships or is deliberately ignored)"
  unset cunt_fail cunt_path
fi

# ── 2. executable-bit assertions ─────────────────────────────────────────────
hdr "executable bits"
if have git && git rev-parse --git-dir >/dev/null 2>&1; then
  while IFS= read -r line; do
    mode="${line%% *}"
    path="${line#* }"
    case "$path" in
    scripts/lib/*.sh | lib/*.sh)
      # Sourced bash libraries — the bash sibling of zsh/*.zsh: no shebang, NOT
      # executable. scripts/lib/ is dev-tooling; lib/ (core/lib/ux.sh) is the VENDORED
      # bash UX lib bootstrap.sh sources. Must precede the generic *.sh arm (first match).
      if [[ "$mode" == 100644 ]]; then
        pass "src  $path"
      else fail "sourced lib must NOT be executable, is $mode: $path"; fi
      ;;
    *.sh | bin/clip | bin/clip-paste)
      if [[ "$mode" == 100755 ]]; then
        pass "+x   $path"
      else fail "must be executable (100755), is $mode: $path"; fi
      ;;
    zsh/*.zsh)
      if [[ "$mode" == 100644 ]]; then
        pass "src  $path"
      else fail "sourced module must NOT be executable, is $mode: $path"; fi
      ;;
    esac
  done < <(git ls-files -s | awk '{print $1, $4}')
else
  skip "exec-bit check (not a git checkout)"
fi

# ── 3. shell syntax ──────────────────────────────────────────────────────────
hdr "shell syntax (bash -n / zsh -n)"
while IFS= read -r f; do
  if bash -n "$f" 2>/dev/null; then pass "bash -n $f"; else fail "bash syntax error: $f"; fi
done < <(_audit_ls '*.sh' 'bin/clip' 'bin/clip-paste')
if ((SCOPE_SHELL)); then
  if have zsh; then
    # The sourced modules AND the autoloaded completion functions (zsh/completions/_*,
    # no .zsh extension) — both are zsh that fans out to nine repos; both must parse.
    while IFS= read -r f; do
      if zsh -n "$f" 2>/dev/null; then pass "zsh -n  $f"; else fail "zsh syntax error: $f"; fi
    done < <(_audit_ls 'zsh/*.zsh' 'zsh/completions/*')
  else
    skip "zsh -n (zsh not installed)"
  fi
else
  skip "zsh -n (out of scope)"
fi

# ── 4. lua ───────────────────────────────────────────────────────────────────
hdr "lua (luacheck)"
# PROBE BEFORE LINTING, so a broken toolchain is never reported as a defect in nvim/ (#726).
# `have luacheck` is a weak precondition: luarocks generates a wrapper that `exec`s an ABSOLUTE
# interpreter path, so the name stays on PATH long after the lua it was built against is gone,
# and the wrapper still answers `command -v`.
#
# EXIT CODE ALONE CANNOT SEPARATE THE TWO, which is why this is a probe and not a status check.
# luacheck's own vocabulary is 0 clean / 1 warnings / 2 syntax errors / 3 I/O error, and a
# LOAD failure — luacheck's source failing to parse or a module going missing — also exits 1.
# That is the documented mise/config.toml case: luacheck 1.2.0 cannot load under Lua 5.5 at
# all ("attempt to assign to const variable" in its own source), and it would land here as
# exit 1, indistinguishable from honest lint warnings. A missing interpreter is the easier
# shape (the shell's 126/127) and would be separable; the 5.5 one is not.
#
# `--version` lints nothing and exercises the same module load, so ANY failure from it is a
# toolchain failure by construction. One extra process on a leg that only runs when nvim/ is
# in scope.
if ! ((SCOPE_NVIM)); then
  skip "luacheck (out of scope)"
elif ! have luacheck; then
  # Name the 5.4 requirement HERE, at the moment the reader learns they need the tool —
  # mise/config.toml carries the full explanation, but nobody reaching for `luarocks install
  # luacheck` is reading a runtime pin file (#726).
  skip "luacheck (not installed — install it against an explicit Lua 5.4; luacheck 1.2.0 cannot load under 5.5, see mise/config.toml)"
else
  # The probe lints nothing; only its STATUS matters, and its output is the diagnostic to
  # show when it fails. luacheck discovers .luacheckrc by searching UP from the CWD, not the
  # target — so the lint pass runs from inside nvim/, where nvim/.luacheckrc lives. From repo
  # root it would miss the config and emit hundreds of false "undefined vim" warnings.
  lua_probe="$(luacheck --version 2>&1)"
  lua_probe_rc=$?
  if ((lua_probe_rc == 0)); then
    lua_out="$(cd nvim && luacheck . --no-color 2>&1)"
    lua_rc=$?
  else
    lua_out="$lua_probe"
    lua_rc=0
  fi
  # The three-way call is in common.sh so test-core.sh can drive every branch; this only
  # renders. Same split §1b uses, and for the same reason.
  case "$(_core_luacheck_verdict "$lua_probe_rc" "$lua_rc")" in
  ok)
    pass "luacheck nvim/"
    ;;
  broken)
    fail "luacheck is on PATH but cannot RUN — a broken toolchain, NOT a lint finding in nvim/. If it was installed with luarocks against mise's lua, that is the trap mise/config.toml describes; the sanctioned installers each pin their own 5.4. Re-running luacheck will only repeat this."
    fail_detail "$lua_probe"
    ;;
  broken-midrun)
    fail "luacheck stopped being runnable mid-audit (exit $lua_rc) — the toolchain broke after the version probe passed, so this is not a lint finding in nvim/"
    fail_detail "$lua_out"
    ;;
  *)
    fail "luacheck reported issues — run: (cd nvim && luacheck .)"
    fail_detail "$lua_out"
    ;;
  esac
  unset lua_rc lua_probe_rc lua_probe lua_out
fi

# ── 4b. nvim module reachability (the orphan backstop) ───────────────────────
# core.manifest lists `nvim/` as a DIRECTORY, so §1's manifest⇄fs drift check auto-lists
# every new path under it and cannot see an orphan — a lua module nothing loads would sit
# in the tree and fan out to all nine OS repos silently. core.manifest said that gap was
# covered "by verify-core.sh instead"; that script has never existed here (#454). The real
# logic — a graph walk from nvim/init.lua, not a "is this name mentioned" scan — lives in
# the script below, along with the rationale for its roots and its two resolved edges. It
# is a standalone script rather than an inline block precisely so test-core.sh can drive
# it against synthetic fixtures. Findings arrive one per line; each becomes a fail.
hdr "nvim module reachability"
if ! ((SCOPE_NVIM)); then
  skip "nvim reachability (out of scope)"
elif [[ ! -d nvim/lua/gerrrt ]]; then
  skip "nvim reachability (no nvim/lua/gerrrt)"
else
  # Gate on the EXIT STATUS as well as the output. Deciding purely on "did it print
  # anything" means a silent non-zero exit — the script killed, or dying before it can
  # emit a diagnostic — reads as a passing gate, which is the one outcome a backstop must
  # never produce. Pass requires rc 0 AND no findings; anything else fails, and a
  # status-without-output still says something actionable rather than nothing.
  orph_out="$("$HERE/scripts/nvim-reachability.sh" --root "$HERE" 2>&1)"
  orph_rc=$?
  if [[ -n "$orph_out" ]]; then
    while IFS= read -r orph_line; do
      [[ -n "$orph_line" ]] && fail "nvim: $orph_line"
    done <<EOF
$orph_out
EOF
    ((orph_rc == 0)) && fail "nvim: reachability reported findings but exited 0 (contract violation)"
  elif ((orph_rc == 0)); then
    pass "nvim module reachability (no orphaned lua modules)"
  else
    fail "nvim: reachability exited $orph_rc with no output — the gate did not actually run"
  fi
fi

# ── 5. lint (shellcheck) ─────────────────────────────────────────────────────
hdr "lint (shellcheck)"
if ! ((SCOPE_SHELL)); then
  skip "shellcheck (out of scope)"
elif have shellcheck; then
  sc_fail=0
  while IFS= read -r f; do
    if ! sc_out="$(shellcheck -x "$f" 2>&1)"; then
      sc_fail=1
      fail "shellcheck: $f"
      fail_detail "$sc_out"
    fi
  done < <(_audit_ls '*.sh' 'bin/clip' 'bin/clip-paste')
  ((sc_fail)) || pass "shellcheck (all bash scripts clean)"
else
  skip "shellcheck (not installed)"
fi

# ── 5b. fzf preview binary resolution (regression gate) ──────────────────────
# fzf / fzf-tab previews run their command STRING in a subshell, so a LITERAL `bat`
# there printed "command not found" in every preview pane on Debian/Ubuntu — those
# distros ship bat as `batcat` — a silent breakage that fanned out to those OS repos
# with no failing gate. The fix routes previews through $BAT_BIN (00-tools.zsh resolves
# the real name) with a cat/ls fallback. Lock it so the bug can't recur: no uncommented
# preview line in zsh/35-fzf.zsh or zsh/45-plugins.zsh may invoke a literal bat/batcat, and
# 35-fzf.zsh must still reference $BAT_BIN. Pure sed+grep (busybox-safe), shell-scoped.
hdr "fzf preview binary resolution"
if ((SCOPE_SHELL)); then
  pv_fail=0
  for f in zsh/35-fzf.zsh zsh/45-plugins.zsh; do
    # Strip comments (from the first #), then flag a bare lowercase bat/batcat command
    # token — $BAT_BIN (uppercase) is intentionally NOT matched, which is the point.
    if sed 's/#.*//' "$f" | grep -qE '(^|[^A-Za-z_$])bat(cat)?[[:space:]]'; then
      pv_fail=1
      fail "literal bat/batcat in a preview command ($f) — route it through \$BAT_BIN"
    fi
  done
  grep -q 'BAT_BIN' zsh/35-fzf.zsh || {
    pv_fail=1
    fail "zsh/35-fzf.zsh no longer references \$BAT_BIN (preview resolution lost)"
  }
  # fzf-tab appends $realpath itself and does NOT substitute fzf's `{}` placeholder. So a
  # fzf-tab preview must use the placeholder-free $_FZF_TAB_PREVIEW_CMD — NOT $_FZF_PREVIEW_CMD
  # (which ends in `{}`, the bug: that trailing `{}` reaches the previewer as a phantom arg),
  # and not an inline literal `{}` either. Flag any fzf-preview line that pairs $realpath with
  # the wrong var or a stray `{}`. ($_FZF_TAB_PREVIEW_CMD is not a substring of the check, so
  # the correct line passes.)
  while IFS= read -r _pvln; do
    [[ "$_pvln" == *fzf-preview* && "$_pvln" == *"\$realpath"* ]] || continue
    if [[ "$_pvln" == *'{}'* || "$_pvln" == *"\$_FZF_PREVIEW_CMD"* ]]; then
      pv_fail=1
      fail "fzf-tab preview must use \$_FZF_TAB_PREVIEW_CMD (no {} / no \$_FZF_PREVIEW_CMD): $_pvln"
    fi
  done < <(sed 's/#.*//' zsh/45-plugins.zsh)
  ((pv_fail)) || pass "fzf/fzf-tab previews resolve \$BAT_BIN (no literal bat/batcat, no stray {})"
else
  skip "fzf preview resolution (out of scope)"
fi

# ── 5c. Core⇄OS boundary (portable shell modules carry no OS-absolute paths) ──
# README's contract: "if it changes when the OS changes, it does NOT belong in Core."
# That rule is documented but was ungated — a hard-coded /opt/homebrew, /home/linuxbrew,
# or macOS ~/Library path could slip into a portable shell module and fan out to nine repos
# where it is simply wrong. Assert the sourced zsh modules stay OS-agnostic. EXCLUDED:
# zsh/55-maint.zsh — the scheduler CONTROL SURFACE whose launchd arm legitimately writes
# ~/Library/LaunchAgents (it switches on _maint_scheduler, the correct cross-OS shape);
# only THOSE lines are exempt, not the whole file (see the per-line note below).
# Comment-stripped first, so an explanatory comment naming an OS path can't trip it.
# Pure sed+grep (busybox-safe), and CROSS-CUTTING rather than shell-scoped — the scope is
# the manifest, so it covers configs and the nvim tree too, and no --scope may skip it.
hdr "Core⇄OS boundary (no OS paths in portable Core files)"
# The scope is DERIVED FROM core.manifest, not from a hand-kept list. That list had
# quietly fallen behind the manifest three times: first the symlinked configs were
# ungated (a real /opt/homebrew drift was found downstream, baked into mise/config.toml),
# then bin/, maint/ and tmux/scripts/ — and when THOSE were added, zsh/completions/*,
# lib/ux.sh, lib/bootstrap-lib.sh and .bin/sync-upstream.sh were still missing. Every one
# of those omissions is the same bug, so the fix is structural: the manifest already IS
# the definition of "what is Core", and a file added to it is now scanned automatically.
# The blind spot cannot silently reopen, because reopening it would mean the file is not
# Core at all — which section 1 already fails on.
#
# It is also UNCONDITIONAL now (no SCOPE_SHELL guard). It used to be shell-scoped, but it
# now covers manifested nvim/, toml and config files too, and it is pure sed+grep over
# ~150 small files — cheap and cross-cutting, like the manifest/exec-bit/markdown gates.
# A narrowed --scope run must not be able to skip a fan-out-correctness check.
#
# EXCLUDED, both deliberately and visibly — and note the exemption is per-LINE, not
# per-file, for the one module that needs it:
#   · zsh/55-maint.zsh — the scheduler CONTROL SURFACE, whose launchd arm legitimately
#     writes ~/Library/LaunchAgents (it switches on _maint_scheduler, the correct
#     cross-OS shape). Only the LaunchAgents lines are dropped. Skipping the whole file
#     would re-open the blind spot inside it: an accidental /opt/homebrew or /mnt/c
#     added to maint-install, or to any other function there, would sail through.
#   · *.example — user-edited illustrations, not the live config.
bnd_fail=0
while IFS= read -r f; do
  case "$f" in
  *.example) continue ;; # user-edited illustration, not live config
  esac
  [[ -f "$f" ]] || continue
  # NOTHING is stripped. Comment-stripping was a false-negative machine: `#` is a comment
  # in shell and toml but the LENGTH OPERATOR in Lua, a delimiter inside a string is code
  # (`export P="#/opt/…"`), and a line inside a heredoc or a Lua long-bracket string is
  # runtime data however it starts. Each fix uncovered the next, because getting it right
  # needs a parser for all five grammars this now scans.
  #
  # So the rule is simply: a manifested Core file must not contain an OS-absolute path
  # ANYWHERE, prose included. Name the prefix instead of spelling it — "the Homebrew
  # prefix", not the literal. That costs one wording choice in a comment and buys a gate
  # with no hiding places at all.
  bnd_src="$(cat "$f")"
  # Then drop ONLY the sanctioned lines of the one exempt file — everything else in it
  # is still scanned.
  # REDACT the sanctioned segment; do not drop the line. Dropping it would exempt
  # everything else on that line too, so a second literal riding along on a legitimate
  # LaunchAgents assignment would evade the gate. Replacing just the segment leaves the
  # rest of the line to be scanned normally.
  [[ "$f" == zsh/55-maint.zsh ]] && bnd_src="${bnd_src//Library\/LaunchAgents/<sanctioned-launchd-path>}"
  if grep -qE '/opt/homebrew|/home/linuxbrew|/usr/local/Cellar|/Library/|/mnt/c/' <<<"$bnd_src"; then
    bnd_fail=1
    fail "OS-specific path in a portable Core file ($f) — it belongs in the OS layer, not Core"
  fi
done < <(
  # Expand the manifest: directory entries (nvim/) into their files, file entries as-is.
  #
  # _audit_ls, not plain `git ls-files`: this list feeds a CONTENT scan — each file is
  # cat'd and grepped for OS-absolute paths above — so it sits on the content side of the
  # rule in common.sh. It reads like a manifest question and is not one; the manifest
  # names the DIRECTORY, and every file under it is in scope whether or not git has seen
  # it yet. Without this, a new nvim/ lua module hardcoding a Homebrew prefix would pass
  # the boundary gate locally and only fail after `git add` — the same blind spot this
  # rule exists to close, wearing manifest clothing.
  for m in "${MANIFEST_PATHS[@]}"; do
    if [[ "$m" == */ ]]; then _audit_ls "$m"; else printf '%s\n' "$m"; fi
  done | sort -u
)
((bnd_fail)) || pass "every manifested Core file carries no OS-absolute path (scope derived from core.manifest)"

# ── 5d. pipefail SIGPIPE hazard (regression gate) ────────────────────────────
# Under `set -o pipefail`, piping into a reader that EXITS EARLY turns a success into a
# failure. `grep -q` stops on its first match, `awk` on its `exit`, `head` after N lines;
# the writer then takes EPIPE and dies with 141, and pipefail reports the PIPELINE as
# failed even though the reader matched.
#
# This repo has hit it three times. Twice it was found and fixed by hand — the CHANGELOG
# records a 4000-line `git show` into `grep -q` reporting "no heading" on a file that had
# one, and test-core.sh has an assertion literally named "the pipefail trap this repo has
# hit before" for `ldd --version | grep -qi musl`. The third broke `main`:
# nvim-reachability.sh invented two orphans because a visited module's membership lookup
# returned 141 (#458). The fix each time was a hand sweep of the tree — correct for its
# moment, and unable to cover code written afterwards. Hence a gate (#459).
#
# SCOPE IS DELIBERATELY NARROW: a SHELL-STRING producer (`printf`/`echo`) into an
# early-exiting reader. `sed <file> | head -n1` — a FILE producer, ~15 instances — is left
# alone on purpose: converting those is not free, and a gate that fires fifteen times on
# working code is a gate someone turns off.
#
# THE REMEDY IS "REMOVE THE PIPE", NOT "ALWAYS USE A HERESTRING". A herestring appends a
# newline, so `printf '%s' "\$v" | head -c 3` and `head -c 3 <<<"\$v"` differ by a byte —
# for a byte-counting reader the naive rewrite corrupts the value. Capturing to a variable
# preserves the producer's exact bytes; a herestring is the right fix wherever a trailing
# newline is immaterial, which is most places but not all.
#
# The scanner is textual (see _core_pipefail_hits) and so a heuristic backstop, not a
# proof: a pipeline split across lines, or a reader reached via a variable, is not seen.
hdr "pipefail SIGPIPE hazard"
if ! ((SCOPE_SHELL)); then
  skip "pipefail SIGPIPE (out of scope)"
else
  pf_fail=0
  while IFS= read -r pf_f; do
    [ -n "$pf_f" ] || continue
    while IFS= read -r pf_line; do
      [ -n "$pf_line" ] || continue
      fail "pipefail: $pf_f:$pf_line — shell-string producer feeds a reader that exits early; remove the pipe (capture to a variable, or a herestring where a trailing newline is immaterial)"
      pf_fail=1
    done <<EOF
$(_core_pipefail_hits "$pf_f")
EOF
  done <<EOF
$(_audit_ls '*.sh' 'bin/clip' 'bin/clip-paste')
EOF
  ((pf_fail)) || pass "pipefail (no shell-string producer feeds an early-exiting reader)"
fi

# ── 5e. leaked RETURN trap (fleet regression gate) ───────────────────────────
# A bash RETURN trap is a GLOBAL slot, not a function-scoped one. Armed inside a function it
# survives into the CALLER's frame and fires a SECOND time on that frame's return, where the
# local it cleans up is out of scope and `set -u` makes it fatal. dotgibson/dotfiles-Debian#2:
# every fresh-box bootstrap died the instant provision() returned, AFTER installing everything
# but BEFORE wire_links — a box carrying the whole stack and not one symlink.
#
# WHY IT NEEDS ITS OWN SECTION rather than a shellcheck rule: shellcheck cannot see it. The
# broken line is valid bash, and `bash -n` passes it too. §5's shellcheck leg and §3's syntax
# leg both run over the offending file and both go green. Only a textual scan catches it.
#
# WHY IT IS A CORE CONCERN even though the two known instances were in OS repos: this is the
# tree that fans out to nine of them, and `lib/bootstrap-lib.sh` is exactly the kind of code
# that arms cleanup traps. .github/workflows/lint-call.yml carries the same rule for the
# CALLER repos, but it checks the caller out into `caller/` and never looks at Core's own
# 38 shell scripts. This section is that half. The two must stay in step —
# scripts/lib/common.sh :: _core_return_trap_hits is the canonical expression of the rule.
#
# Scope matches §5d: repo-owned bash, including the extensionless bin/clip helpers. zsh is
# excluded on purpose — it has no RETURN signal, so the bug cannot exist there.
hdr "leaked RETURN trap"
if ! ((SCOPE_SHELL)); then
  skip "RETURN trap (out of scope)"
else
  rt_fail=0
  while IFS= read -r rt_f; do
    [ -n "$rt_f" ] || continue
    while IFS= read -r rt_line; do
      [ -n "$rt_line" ] || continue
      fail "RETURN trap: $rt_f:$rt_line — armed without disarming the slot; it will fire again in the CALLER's frame. Make the body disarm FIRST: trap 'trap - RETURN; …' RETURN"
      rt_fail=1
    done <<EOF
$(_core_return_trap_hits "$rt_f")
EOF
  done <<EOF
$(_audit_ls '*.sh' 'bin/clip' 'bin/clip-paste')
EOF
  ((rt_fail)) || pass "RETURN traps (every one disarms the slot before the caller's frame sees it)"
fi

# ── 5f. bootstrap-lib helper adoption across the fleet ───────────────────────
# Core ships lib/bootstrap-lib.sh so the shared half of a bootstrap stops being hand-forked
# nine ways. Helpers get ADDED to it over time — usually because one repo hit a bug — and
# nothing has ever checked whether the other eight picked them up. So the file grows a fix
# and the fleet keeps the defect (#516).
#
# Measured when this section was written, and it is not a hypothetical spread:
#   blib_resolve_su 2/9 · blib_sudo_keepalive_start 1/9 · blib_user_bindirs_on_path 1/9 ·
#   blib_note_fail + blib_failures_report 2/9 · blib_wire_summary 7/9 ·
#   blib_install_core_guard 7/9 · BLIB_DRY 9/9
# Each gap is a live defect in the repos missing it: no blib_resolve_su means a hand-rolled
# `[[ "$(id -u)" -eq 0 ]]`, an ARITHMETIC comparison where an empty `id` output evaluates as
# 0 and the whole run proceeds unescalated; no blib_sudo_keepalive_start means sudo's
# timestamp expires during a long install and the re-prompt goes to a discarded stderr, i.e.
# a silent hang; no blib_failures_report means the script can record failures via
# blib_note_fail and then exit 0 announcing "complete".
#
# REPORT, DO NOT BLOCK — deliberately, and this is the load-bearing design decision.
# Seven of nine repos are short on arrival, so a failing gate would be red from its first
# run, and a gate that is red on arrival is a gate someone turns off. It states the gap and
# leaves remediation to per-repo work. Turn it into a fail only once the fleet is clean.
#
# --STRICT SAFETY: the "sibling not checked out" skip goes through skip_env, which records
# it as an ENVIRONMENT skip. --strict counts only TOOL-absent skips, so this section stays
# inert there — CI checks out only this repo. It used to achieve that by WORDING the skip
# "out of scope" so the substring classifier would let it through, which made the message
# text the gate and conflated "you narrowed this" with "this box cannot run it". The class
# is structural now, so the wording is free to say what is actually true, and
# --require-siblings can red on precisely this case without touching --strict.
#
# Reads scripts/os-repos.txt with the light sed idiom (as freshness-dashboard.sh does) and
# NOT the three-script pattern with a hardcoded fallback array: os-repos.txt documents that
# adding a target is four coordinated edits, and test-core.sh asserts those four agree. A
# fourth reader should not join that contract for a purely advisory check.
hdr "bootstrap-lib helper adoption (advisory)"
_ha_root="$(cd "$HERE/.." && pwd)"
if [[ ! -r "$HERE/scripts/os-repos.txt" ]]; then
  skip_env "helper adoption (scripts/os-repos.txt unreadable — cannot enumerate the fleet)"
else
  # <helper> <what its absence costs>. Kept here rather than in bootstrap-lib.sh so the
  # rationale lives with the check that reports it; VENDORING.md carries the human contract.
  _ha_checked=0
  _ha_missing=0
  _ha_absent=0
  while IFS= read -r _ha_repo; do
    [ -n "$_ha_repo" ] || continue
    _ha_dir="$(resolve_repo_dir "$_ha_root" "$_ha_repo")" || _ha_dir="$_ha_root/$_ha_repo"
    if [[ ! -f "$_ha_dir/bootstrap.sh" ]]; then
      _ha_absent=$((_ha_absent + 1))
      continue
    fi
    _ha_checked=$((_ha_checked + 1))
    _ha_gaps=""
    for _ha_h in blib_resolve_su blib_sudo_keepalive_start blib_user_bindirs_on_path \
      blib_note_fail blib_failures_report blib_wire_summary blib_install_core_guard BLIB_DRY; do
      # A ROLE repo layers on top of an OS repo's bootstrap and does no package installation
      # of its own, so the two helpers that exist for long privileged installs do not apply.
      # Exempting them is what keeps the report actionable rather than noisy — the same shape
      # as the doctor's own exemption list.
      case "$_ha_repo:$_ha_h" in
      dotfiles-Defense:blib_sudo_keepalive_start | dotfiles-Offense:blib_sudo_keepalive_start | \
        dotfiles-Defense:blib_user_bindirs_on_path | dotfiles-Offense:blib_user_bindirs_on_path)
        continue
        ;;
      esac
      grep -q "$_ha_h" "$_ha_dir/bootstrap.sh" 2>/dev/null || _ha_gaps="$_ha_gaps $_ha_h"
    done
    if [[ -n "$_ha_gaps" ]]; then
      _ha_missing=$((_ha_missing + 1))
      ((${CORE_JSON:-0})) || printf '  %s%s%s %s does not call:%s\n' "${c_yel}" "•" "${c_rst}" "$_ha_repo" "$_ha_gaps"
    fi
  done < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$HERE/scripts/os-repos.txt")

  if ((_ha_checked == 0)); then
    skip_env "helper adoption (no sibling OS repo checked out — nothing to read here)"
  elif ((_ha_missing)); then
    # pass(), not fail(): see REPORT, DO NOT BLOCK above. The count is the signal; the
    # per-repo lines printed just above are the detail.
    pass "helper adoption: $_ha_missing of $_ha_checked checked-out repo(s) have not adopted every helper (advisory — see the lines above, VENDORING.md has the contract)"
  else
    pass "helper adoption: every checked-out OS repo calls the whole bootstrap-lib contract ($_ha_checked repo(s))"
  fi
  ((_ha_absent)) && skip_env "helper adoption: $_ha_absent repo(s) not checked out — not covered by this run"
fi

# ── 5g. the secret-scan policy, in the files §5f cannot see ──────────────────
# §5f reports which repos have not adopted lib/bootstrap-lib.sh's helpers, and it greps
# bootstrap.sh ONLY. The identical drift class — Core grows a capability, some repos keep a
# hand-rolled predecessor, nothing notices — lives in the WORKFLOW and MAKEFILE dimension too,
# and it went red across four repos on the 2026-08-23 sync (#623).
#
# WHAT HAPPENED. Core's gitleaks.toml narrows one false-positive class: a credential position
# holding a VARIABLE REFERENCE rather than a value. Core's reusable lint-call.yml secrets leg
# states the rule — "ONE POLICY FILE, Core's … no repo can widen its own allowlist" — and
# passes -c accordingly. Four repos ran their own gitleaks with no config at all, so they used
# the stock rule set, where `curl-auth-user` matches on credential-shaped POSITION rather than
# content. The vendored core/CHANGELOG.md documents that very allowlist and quotes the example
# it was written for, so CORE'S EXPLANATION OF THE RULE READ AS A VIOLATION OF IT, on a sync
# that carried no credential. Two further repos were green only because each keeps its own root
# .gitleaks.toml that gitleaks auto-discovers — the same defect failing in the quiet direction,
# which is worse: a private allowlist can widen over time with nothing comparing it to Core's,
# and the next person to look sees a passing gate (#624).
#
# TWO CHECKS, because they are two different claims and each must be able to be true alone:
#   (a) every `gitleaks dir|detect|git` invocation carries a config flag at all
#       (scripts/lib/common.sh :: _core_gitleaks_policy_hits, fixture-tested both directions);
#   (b) a repo-local .gitleaks.toml must `[extend]` core/gitleaks.toml, so a repo can ADD a
#       distro-specific rule without silently DROPPING the fleet's.
# A repo that legitimately needs local rules is not doing anything wrong; replacing Core's
# policy rather than extending it is.
#
# BLOCKING as of #624 — it shipped advisory, for the reason §5f gives: repos are short on
# arrival, and a gate that is red from its first run is a gate someone turns off. That reason
# has expired. The fleet is clean: dotfiles-Alpine and dotfiles-Gentoo each carried a private
# .gitleaks.toml that gitleaks auto-discovered, so every local scan there ran under a rule set
# that was simultaneously narrower than Core's (stock defaults, Core's variable-reference
# allowlist dropped) and wider (whole-path exemptions). Both are gone, both verified clean under
# core/gitleaks.toml — working tree and, for Gentoo, all 271 commits of history. All 9 repos now
# measure the same way, so this can hold the line instead of narrating it. Same move §5i makes,
# for the same stated reason.
#
# The failure is quiet by nature — a private allowlist widens over time with nothing comparing
# it to Core's, and the next person to look sees a passing gate. Advisory is the wrong posture
# for a finding whose whole hazard is that it looks fine.
#
# Same skip_env (ENVIRONMENT) class as §5f — --strict counts only TOOL-absent skips, so this
# is inert there (CI checks out only this repo) and bites locally and in any sweep that clones
# the fleet. --require-siblings is what makes an absent sibling red.
hdr "secret-scan policy adoption"
_gp_root="$(cd "$HERE/.." && pwd)"
if [[ ! -r "$HERE/scripts/os-repos.txt" ]]; then
  skip_env "gitleaks policy (scripts/os-repos.txt unreadable — cannot enumerate the fleet)"
else
  _gp_checked=0
  _gp_bad=0
  _gp_absent=0
  while IFS= read -r _gp_repo; do
    [ -n "$_gp_repo" ] || continue
    _gp_dir="$(resolve_repo_dir "$_gp_root" "$_gp_repo")" || _gp_dir="$_gp_root/$_gp_repo"
    if [[ ! -d "$_gp_dir/.git" ]]; then
      _gp_absent=$((_gp_absent + 1))
      continue
    fi
    _gp_checked=$((_gp_checked + 1))
    _gp_gaps=""
    # (a) invocations with no policy at all
    for _gp_f in "$_gp_dir"/Makefile "$_gp_dir"/.github/workflows/*.yml "$_gp_dir"/.github/workflows/*.yaml; do
      [[ -f "$_gp_f" ]] || continue # unmatched glob stays literal (nullglob is off)
      _gp_h="$(_core_gitleaks_policy_hits "$_gp_f")"
      [[ -n "$_gp_h" ]] || continue
      _gp_gaps="$_gp_gaps
      ${_gp_f#"$_gp_dir"/}: $(printf '%s' "$_gp_h" | sed 's/:no-config//' | tr '\n' ',' | sed 's/,$//') — gitleaks runs with no -c/--config, so the STOCK rule set applies, not Core's"
    done
    # (b) a private config that replaces Core's instead of extending it
    if [[ -f "$_gp_dir/.gitleaks.toml" ]] &&
      ! grep -qE '^[[:space:]]*path[[:space:]]*=.*core/gitleaks\.toml' "$_gp_dir/.gitleaks.toml"; then
      _gp_gaps="$_gp_gaps
      .gitleaks.toml: a private rule set that does not [extend] core/gitleaks.toml — gitleaks auto-discovers it, so EVERY scan here silently runs under it"
    fi
    if [[ -n "$_gp_gaps" ]]; then
      _gp_bad=$((_gp_bad + 1))
      ((${CORE_JSON:-0})) || printf '  %s%s%s %s%s\n' "${c_yel}" "•" "${c_rst}" "$_gp_repo" "$_gp_gaps"
    fi
  done < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$HERE/scripts/os-repos.txt")

  if ((_gp_checked == 0)); then
    skip_env "gitleaks policy (no sibling OS repo checked out — nothing to read here)"
  elif ((_gp_bad)); then
    fail "gitleaks policy: $_gp_bad of $_gp_checked checked-out repo(s) do not measure by Core's policy (see the lines above; VENDORING.md has the contract)"
  else
    pass "gitleaks policy: every checked-out OS repo scans under Core's policy ($_gp_checked repo(s))"
  fi
  ((_gp_absent)) && skip_env "gitleaks policy: $_gp_absent repo(s) not checked out — not covered by this run"
fi

# ── 5h. the gate x repo coverage register ────────────────────────────────────
# Coverage used to be inferred by reading the `uses:` lines in each repo's workflows, and
# that inference is WRONG for any repo that satisfies a gate its own way. It has misfired
# twice, identically, both times in good faith: dotfiles-MacBook#154 (the RETURN-trap gate,
# ported by hand) and dotfiles-MacBook#178 (the provision-stub job, already gated on the
# macOS leg via a BOOTSTRAP_BREW seam). Same failure mode two gates apart, because a rollout
# audit had no way to tell "not covered" from "covered elsewhere" (#607).
#
# scripts/fleet-coverage.sh derives the `reusable` cells from each repo's real `uses:` lines
# and reads .github/core-gates.txt for the ones that cannot be derived. This asserts every
# cell is filled — so a NEW reusable workflow cannot ship without each repo declaring a
# position on it, which is the property that makes the register stay true.
#
# Advisory and "out of scope"-skipped when siblings are absent, like §5f/§5g.
hdr "gate x repo coverage register (advisory)"
if [[ ! -x "$HERE/scripts/fleet-coverage.sh" ]]; then
  skip "coverage register (scripts/fleet-coverage.sh missing — out of scope)"
else
  _fc_out="$("$HERE/scripts/fleet-coverage.sh" --check 2>&1)"
  _fc_rc=$?
  if [[ "$_fc_out" == *"no sibling repo checked out"* ]]; then
    skip_env "coverage register (no sibling OS repo checked out — nothing to read here)"
  elif ((_fc_rc == 0)); then
    pass "coverage register: $_fc_out"
  else
    # pass(), not fail(): see REPORT, DO NOT BLOCK on §5f.
    ((${CORE_JSON:-0})) || printf '%s\n' "$_fc_out" | sed 's/^/  /'
    pass "coverage register: undeclared gate x repo cell(s) — advisory; each repo declares in .github/core-gates.txt (VENDORING.md has the contract)"
  fi
  unset _fc_out _fc_rc
fi

# ── 5i. leftover conflict markers (tracked files) ────────────────────────────
# A conflict resolved by hand can leave a marker behind, and bcdd7dd (#650) did exactly
# that: a literal base marker landed in CHANGELOG.md at the end of [Unreleased]'s Fixed
# section and sat on main undetected. Under zdiff3 a conflict has FOUR marker lines, not
# three, and the base one is the half people forget because it only exists in that style.
#
# WHY IT BLOCKS RATHER THAN REPORTS, unlike §5f/§5g above: this is not fleet drift that
# arrives red on seven repos. The tree is clean today (measured: zero hits across every
# tracked file), so the gate is green on arrival and every future hit is a genuine
# regression introduced by the commit under test. That is the condition §5f names for
# turning an advisory check into a failing one.
#
# WHY IT IS WORTH A GATE. git refuses to parse a conflict region containing a stray
# marker — rebasing onto the affected main produced `error: could not parse conflict
# hunks in CHANGELOG.md` — and CONTRIBUTING.md requires every user-visible change to
# touch [Unreleased], so one marker there taxes every future branch. Nothing else sees
# it: `bash -n`/`zsh -n` never read markdown, markdownlint reads the line as ordinary
# paragraph text, and gitleaks is looking for credentials.
#
# NO ALLOWLIST, ON PURPOSE. The obvious design is to exempt the files that legitimately
# CONTAIN markers — this script, the matcher, the test fixtures. None of them need it:
# scripts/lib/common.sh assembles its patterns from fragments (the discipline §5d/§5e
# already follow), and test-core.sh writes its fixtures into $SANDBOX at run time, so
# they are never tracked and never scanned. An allowlist would be a hole in the one gate
# whose value is that it has none. A doc that genuinely must SHOW a marker indents it by
# one space — column 0 is what git keys on, and what this gate keys on.
#
# Scope is every tracked text file, not just shell: the defect that motivated this was in
# markdown. Binaries are skipped by the matcher's `grep -I` (assets/ carries images).
hdr "leftover conflict markers"
cm_fail=0
while IFS= read -r cm_f; do
  [ -n "$cm_f" ] || continue
  while IFS= read -r cm_line; do
    [ -n "$cm_line" ] || continue
    fail "conflict marker: $cm_f:$cm_line — a resolution left a VCS marker behind; git cannot parse a conflict region containing one. Delete it (under zdiff3 a conflict has FOUR marker lines, and the base one is the half that gets missed)"
    cm_fail=1
  done <<EOF
$(_core_conflict_marker_hits "$cm_f")
EOF
done <<EOF
$(_audit_ls '*')
EOF
((cm_fail)) || pass "conflict markers (no tracked file carries a leftover marker)"

# ── 6. config files (toml / yaml parse) ──────────────────────────────────────
# A malformed starship.toml / mise config.toml / ci.yml is still valid *text* —
# so zsh -n and shellcheck never look at it — yet it breaks every one of the 9
# consumers at runtime (dead prompt, dead runtime manager, dead CI). Assert that
# every tracked TOML and YAML file actually PARSES. Best-effort + graceful skip,
# exactly like the linters above: TOML via python3 `tomllib` (stdlib since 3.11),
# YAML via python3 PyYAML when importable. pre-commit's check-toml/check-yaml are
# the hermetic author-time mirror of this same gate.
hdr "config files (toml / yaml)"
if have python3 && python3 -c 'import tomllib' 2>/dev/null; then
  while IFS= read -r f; do
    if python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$f" 2>/dev/null; then
      pass "toml $f"
    else fail "toml parse error: $f"; fi
  done < <(_audit_ls '*.toml' '*.toml.example')
else
  skip "toml parse (python3 tomllib unavailable — needs python ≥3.11)"
fi
if have python3 && python3 -c 'import yaml' 2>/dev/null; then
  while IFS= read -r f; do
    # safe_load_all: workflow/compose YAML can be multi-document (--- separators).
    if python3 -c 'import yaml,sys; list(yaml.safe_load_all(open(sys.argv[1])))' "$f" 2>/dev/null; then
      pass "yaml $f"
    else fail "yaml parse error: $f"; fi
  done < <(_audit_ls '*.yml' '*.yaml')
else
  skip "yaml parse (python3 PyYAML not importable)"
fi
# JSON: nvim/lazy-lock.json pins every Neovim plugin's commit for a reproducible
# editor across the 8 repos — a truncated/corrupt lock breaks `:Lazy restore` for
# all of them, and like the toml/yaml above it's valid *text* the other gates skip.
# `*.json` (not `*.jsonc`) so the JSONC config files keep their comments. json is in
# the stdlib, so this only needs python3 — no extra import gate like PyYAML.
if have python3; then
  while IFS= read -r f; do
    if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null; then
      pass "json $f"
    else fail "json parse error: $f"; fi
  done < <(_audit_ls '*.json')
else
  skip "json parse (python3 unavailable)"
fi

# ── 7. markdown (markdownlint) ────────────────────────────────────────────────
# The docs ARE the deliverable on a public showcase repo, and they're the one file
# class shellcheck/zsh -n/toml-yaml never look at — so a leaked template tag or a
# broken heading ships unnoticed (it did: see CHANGELOG.md's history). markdownlint
# is the gate; .markdownlint.jsonc is the shared rule config (line-length off for
# the wide tables, everything structural on). Graceful skip when absent, exactly
# like the linters above; pre-commit's markdownlint-cli2 hook is the author-time
# mirror, and CI installs it so the gate actually runs there.
hdr "markdown (markdownlint)"
# Resolve a RUNNABLE markdownlint WITHOUT requiring it on PATH — the npm global bin
# frequently lands off PATH, making this the most-skipped gate in remote sessions even
# when the tool IS installed. Prefer a PATH binary; else `npx --no-install` (resolves a
# global/local install with NO network fetch); else a repo-local node_modules bin. Only a
# genuinely-absent tool still skips — which --strict (a fully-provisioned CI leg) then catches.
_mdl=()
if have markdownlint-cli2; then
  _mdl=(markdownlint-cli2)
elif have npx && npx --no-install markdownlint-cli2 --version >/dev/null 2>&1; then
  _mdl=(npx --no-install markdownlint-cli2)
elif [[ -x node_modules/.bin/markdownlint-cli2 ]]; then
  _mdl=(node_modules/.bin/markdownlint-cli2)
fi
if ((${#_mdl[@]})); then
  if md_out="$("${_mdl[@]}" "**/*.md" 2>&1)"; then
    pass "markdownlint (all tracked markdown clean)"
  else
    fail "markdownlint reported issues — run: markdownlint-cli2 '**/*.md'"
    fail_detail "$md_out"
  fi
else
  skip "markdownlint (markdownlint-cli2 not installed — npm i -g markdownlint-cli2)"
fi

# ── 8. workflows (actionlint) ─────────────────────────────────────────────────
# .github/workflows/*.yml is a fan-out artifact with no gate of its own: the YAML
# parse in section 6 proves it's well-formed text, not that the workflow is VALID —
# a bad `needs:`, an undefined job output, or a shellcheck error inside a run: block
# all parse as YAML and still break CI for every push. actionlint catches those (and
# runs shellcheck on the run: scripts). Graceful skip when absent, like every linter
# above; CI installs it pinned (ACTIONLINT_VERSION) so the gate actually runs there.
hdr "workflows (actionlint)"
if have actionlint; then
  if al_out="$(actionlint 2>&1)"; then
    pass "actionlint (workflows valid)"
  else
    fail "actionlint reported issues — run: actionlint"
    fail_detail "$al_out"
  fi
else
  skip "actionlint (not installed — go install github.com/rhysd/actionlint/cmd/actionlint@latest)"
fi

# ── 8b. secrets (gitleaks) ────────────────────────────────────────────────────
# Core ships 1Password helpers (zsh/50-op.zsh), a git-identity template, and history
# secret-ignore patterns — and fans out to 9 PUBLIC repos, where a committed token
# amplifies N-way. None of the gates above look for secrets: shellcheck/zsh -n read
# syntax, the toml/yaml/json checks read structure, markdownlint reads prose. So
# scan the working tree for credentials. `gitleaks dir` is the filesystem scan (every
# tracked + untracked file at HEAD), the CI mirror of the gitleaks pre-commit hook
# (which guards the commit diff at author time). Always-on + graceful skip, exactly
# like the linters above; CI installs it pinned (GITLEAKS_VERSION) so it runs there.
hdr "secrets (gitleaks)"
if have gitleaks; then
  # -v is what makes the captured output worth anything: without it gitleaks prints only
  # "leaks found: N" and the file/line/rule stay hidden — the same non-answer this change
  # exists to remove. --no-color matches the flag already passed to luacheck, so the text
  # captured into a log is plain rather than escape sequences.
  # -c gitleaks.toml: the ONE fleet policy (see that file's header). Without it this
  # gate and lint-call.yml's `secrets` job would run different rule sets against the same
  # class of tree — and a finding that is real here and allowlisted there (or the reverse)
  # is worse than either gate alone, because it makes the disagreement look like a bug in
  # the code rather than in the config.
  if gl_out="$(gitleaks dir . -c gitleaks.toml --no-banner --redact -v --no-color 2>&1)"; then
    pass "gitleaks (no secrets in the working tree)"
  else
    fail "gitleaks found potential secrets — run: gitleaks dir . -c gitleaks.toml --redact -v"
    # Safe to print BECAUSE of --redact: gitleaks replaces the matched value with
    # REDACTED, so the report names the file, line, rule and fingerprint without
    # reproducing the secret. Drop --redact and this becomes the one gate whose output
    # must stay dark.
    fail_detail "$gl_out"
  fi
else
  skip "gitleaks (not installed — https://github.com/gitleaks/gitleaks/releases)"
fi

# ── 8c. modernization floor (check-modern.sh) ────────────────────────────────
# actionlint (8) proves a workflow is VALID; it says nothing about whether it's MODERN.
# scripts/modern-baseline.yml declares the floor (no ::set-output, no EOL runners, every
# external action SHA-pinned, every container image @sha256-pinned) and check-modern.sh
# enforces it — so a workflow can't silently regress below it (this closes G8: mutable
# container tags were the one break in the fleet's otherwise-strict pinning). Pure
# bash+awk, always run (our own script, no `have` gate).
hdr "modernization floor (check-modern.sh)"
if _cm_out="$("$HERE/scripts/check-modern.sh" 2>&1)"; then
  pass "check-modern (CI meets scripts/modern-baseline.yml)"
else
  printf '%s\n' "$_cm_out" >&2
  fail "check-modern found violations (above) — run: ./scripts/check-modern.sh"
fi

# ── 9. version consistency (tool-versions.env ↔ .pre-commit-config.yaml) ──────
# scripts/tool-versions.env is the SINGLE SOURCE for the pinned dev-tool versions.
# CI loads it directly (no literals left in ci.yml), but .pre-commit-config.yaml is
# static YAML that can't read it — so the hook `rev:` fields are the one place a pin
# can still drift. Gate them: assert each hook rev equals its version here. A bump in
# one place without the other fails the audit instead of silently shipping mismatched
# author-time vs CI tooling. Pure bash + awk (busybox-safe); skips if either is gone.
hdr "version consistency (tool-versions.env ↔ pre-commit)"
VERSIONS_ENV="scripts/tool-versions.env"
PRECOMMIT_CFG=".pre-commit-config.yaml"
if [[ -r "$VERSIONS_ENV" && -r "$PRECOMMIT_CFG" ]]; then
  _ver() { sed -n "s/^$1=//p" "$VERSIONS_ENV" | head -n1; }
  # The rev: line immediately following a given repo: line in the pre-commit config.
  _pc_rev() { awk -v r="$1" '$0 ~ "repo:.*" r {f=1} f && $1=="rev:" {print $2; exit}' "$PRECOMMIT_CFG"; }
  _check_pin() { # _check_pin <repo-substr> <env-key> <label>
    local want got
    want="v$(_ver "$2")"
    got="$(_pc_rev "$1")"
    if [[ -n "$got" && "$got" == "$want" ]]; then
      pass "pre-commit $3 rev $got == tool-versions.env"
    else
      fail "pre-commit $3 rev '${got:-<none>}' != tool-versions.env '$want' — bump one to match"
    fi
  }
  _check_pin "koalaman/shellcheck-precommit" SHELLCHECK_VERSION shellcheck
  _check_pin "DavidAnson/markdownlint-cli2" MARKDOWNLINT_VERSION markdownlint
  _check_pin "gitleaks/gitleaks" GITLEAKS_VERSION gitleaks
  _check_pin "pre-commit/pre-commit-hooks" PRECOMMIT_HOOKS_VERSION pre-commit-hooks
else
  skip "version consistency ($VERSIONS_ENV or $PRECOMMIT_CFG unreadable)"
fi

# ── 9a. os.capabilities schema (the shipped example is held to the fleet's gate) ──
# scripts/check-capabilities.sh defines the v5 capability schema (#663) and is the
# validator each OS repo runs on its own os/<os>.capabilities. Core has no declaration
# of its own — it is the CONSUMER, not an OS layer — so what there is to gate here is
# the EXAMPLE the nine repos copy from.
#
# That is not a formality. examples/os.capabilities.example is the thing a human reads
# when authoring a real one (#667), so an example carrying a key the validator rejects
# would hand every OS repo the same defect nine times, and Core's own reader would skip
# it in silence. Running the fleet's gate on the fleet's template closes that: the
# example cannot drift from the schema without reddening this audit.
hdr "os.capabilities schema (example ↔ validator)"
CAP_CHECK="scripts/check-capabilities.sh"
CAP_EXAMPLE="examples/os.capabilities.example"
if [[ -x "$CAP_CHECK" && -r "$CAP_EXAMPLE" ]]; then
  if cap_out="$("$CAP_CHECK" "$CAP_EXAMPLE" 2>&1)"; then
    pass "os.capabilities example validates against the schema"
  else
    while IFS= read -r cap_line; do
      [ -n "$cap_line" ] || continue
      fail "os.capabilities: $cap_line"
    done <<EOF
$cap_out
EOF
  fi
else
  skip "os.capabilities schema ($CAP_CHECK or $CAP_EXAMPLE missing)"
fi

# ── 9b. tool download integrity (every downloaded *_VERSION has a *_SHA256) ────
# The setup-core-tools composite action verifies each release download against a
# pinned SHA-256 from tool-versions.env before installing it — the real supply-chain
# control over the gate toolchain (a tampered or MITM'd asset fails the build instead
# of running). That guarantee only holds if the hash exists: a version bumped without
# refreshing its checksum would trip the action's `:?` guard at best, or verify against
# a stale digest at worst. Gate it here — every tool the action downloads must carry a
# 64-hex *_SHA256 beside its *_VERSION. Recompute with scripts/update-tool-checksums.sh.
hdr "tool download integrity (version ⇒ checksum)"
if [[ -r "$VERSIONS_ENV" ]]; then
  _v() { sed -n "s/^$1=//p" "$VERSIONS_ENV" | head -n1; }
  _check_sha() { # _check_sha <env-prefix> <label>
    local ver sha
    ver="$(_v "${1}_VERSION")"
    sha="$(_v "${1}_SHA256")"
    if [[ -z "$ver" ]]; then
      fail "tool integrity: ${1}_VERSION missing — the action downloads $2"
    elif [[ "$sha" =~ ^[0-9a-f]{64}$ ]]; then
      pass "tool integrity: $2 $ver has a 64-hex ${1}_SHA256"
    else
      fail "tool integrity: $2 $ver has no valid ${1}_SHA256 — run scripts/update-tool-checksums.sh"
    fi
  }
  _check_sha SHELLCHECK shellcheck
  _check_sha ACTIONLINT actionlint
  _check_sha GITLEAKS gitleaks
  _check_sha NVIM neovim
  _check_sha SHFMT shfmt
else
  skip "tool download integrity ($VERSIONS_ENV unreadable)"
fi

# core.version is the human-readable Core stamp vendored into all nine OS repos (read by
# the `core-version` verb). A missing or malformed stamp would fan out a bogus version
# everywhere, so assert it exists and is SemVer-shaped (MAJOR.MINOR.PATCH, optional
# -prerelease). Single line only — the verb and sync-core.sh both read it whole.
if [[ -r core.version ]]; then
  cv="$(tr -d '[:space:]' <core.version)"
  if [[ "$cv" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    pass "core.version well-formed ($cv)"
  else
    fail "core.version malformed ('$cv') — expected SemVer MAJOR.MINOR.PATCH[-pre]"
  fi
else
  fail "core.version missing — the vendored version stamp (core-version reads it)"
fi

# core.version ↔ CHANGELOG coherence. A release is a TWO-file edit (bump core.version,
# move CHANGELOG's [Unreleased] under a dated heading) done by hand — so the two drift.
# Gate it: a -dev/prerelease stamp means work-in-progress, so CHANGELOG must keep an
# [Unreleased] section open; a CLEAN release stamp (X.Y.Z) must have a matching heading
# (## [vX.Y.Z] / ## [X.Y.Z]). Catches "bumped the stamp but forgot the CHANGELOG entry"
# (and vice-versa) before it fans out. Pure grep (busybox-safe); skips if a file is gone.
if [[ -r core.version && -r CHANGELOG.md ]]; then
  cvc="$(tr -d '[:space:]' <core.version)"
  if [[ "$cvc" == *-* ]]; then
    if grep -qE '^## +\[[Uu]nreleased\]' CHANGELOG.md; then
      pass "core.version ($cvc) is prerelease and CHANGELOG keeps an [Unreleased] section"
    else
      fail "core.version ($cvc) is prerelease but CHANGELOG.md has no [Unreleased] section"
    fi
  elif grep -qE "^## +\[v?${cvc//./\\.}\]" CHANGELOG.md; then
    pass "core.version ($cvc) has a matching CHANGELOG release heading"
  else
    fail "core.version ($cvc) has no '## [v$cvc]' heading in CHANGELOG.md — cut the release section"
  fi
else
  skip "core.version ↔ CHANGELOG coherence (a file is unreadable)"
fi

# ── 10. behavioral tests (load-order smoke + function unit tests) ─────────────
# Static analysis above proves the modules PARSE; this proves they LOAD TOGETHER
# in canonical order and that the pure functions behave. Delegated to test-core.sh
# (single source of truth) but folded into ONE audit summary via CORE_TEST_NESTED.
# Self-gates on zsh: with none installed it SKIPs, exactly like sections 3–5.
hdr "behavioral (scripts/test-core.sh)"
# Collect the suite launched in the background near the top (overlapping its slow legs
# with the static gates above). `wait` yields the child's exit code; we re-print its
# buffered output in place, then fold the result into ONE pass/fail line — identical to
# the old inline run, just time-shifted. CORE_AUDIT_SERIAL=1 takes the inline path below.
if ((BEHAV_BG)); then
  if wait "$BEHAV_PID"; then _behav_rc=0; else _behav_rc=$?; fi
  # In --json mode the behavioral output must not reach stdout (JSON-only); send it to
  # stderr so it's still there for debugging. Otherwise print it in place as before.
  if [[ -s "$BEHAV_OUT" ]]; then
    if ((JSON)); then cat "$BEHAV_OUT" >&2; else cat "$BEHAV_OUT"; fi
  fi
  # NAME WHAT BROKE, in the fail line itself. "run: ./scripts/test-core.sh" sends the operator
  # away to reproduce a result this run already has — and for an INTERMITTENT failure that is
  # advice that cannot be taken: the re-run passes and the evidence is gone. It has already
  # cost two occurrences of an unattributed flake here, both lost because the ✗ scrolled past
  # far above the summary and only the summary survived being piped through `tail`.
  #
  # Read BEFORE the buffer is removed. The rendering itself lives in common.sh so the suite can
  # test it on fixtures — see _core_fail_digest for why each of its branches is a quiet-failure
  # risk that hand-injecting a fault would not keep honest.
  _behav_digest="$(_core_fail_digest "$BEHAV_OUT")"
  rm -f "$BEHAV_OUT"
  if ((_behav_rc == 0)); then
    pass "behavioral tests (load-order smoke + function units)"
  elif [[ -n "$_behav_digest" ]]; then
    fail "behavioral tests failed ($_behav_digest) — run: ./scripts/test-core.sh"
  else
    # rc says failed and no ✗ was printed: the suite died before it could report (a crash, a
    # kill, a timeout). Say THAT rather than render an empty list, which would read as zero
    # failures beside a red line and send the reader hunting a mismatch that is not there.
    fail "behavioral tests failed — it exited $_behav_rc without printing a ✗, so it died before reporting; run: ./scripts/test-core.sh"
  fi
else
  # Serial fallback. `${arr[@]+"${arr[@]}"}`, not `"${arr[@]}"`: under `set -u`, expanding
  # an EMPTY array raises "unbound variable" on bash < 4.4 — i.e. macOS's stock bash 3.2,
  # which this gate must run on. The `+` form expands to nothing when unset/empty and to
  # the quoted elements otherwise, so the non-QUIET (empty TEST_ARGS) path doesn't abort.
  if CORE_TEST_NESTED=1 ./scripts/test-core.sh ${TEST_ARGS[@]+"${TEST_ARGS[@]}"}; then
    pass "behavioral tests (load-order smoke + function units)"
  else
    fail "behavioral tests failed — run: ./scripts/test-core.sh"
  fi
fi

# Partition the skips up front so both the human summary and the --json object can report
# it. (Done before either render.) Three classes, not two:
#   tool         absent tool — a real coverage gap; --strict reds
#   out of scope the caller narrowed the run (--scope/--changed) — intentional
#   environment  a sibling OS repo isn't checked out — recorded STRUCTURALLY by skip_env,
#                not by wording, so the message can say what is true without moving a gate
# Environment skips are subtracted rather than string-matched: they are already counted in
# the non-"out of scope" tally above, and skip_env is the only thing that declares them.
# This keeps --strict's meaning EXACTLY as it was (absent tools only) while letting
# --require-siblings gate the third class on its own.
# The tool/scope/environment partition is decided by _core_tool_skip_count in
# scripts/lib/common.sh, NOT here. It was inline until the test meant to guard it turned out to
# re-implement the same loop in test-core.sh — so both stayed green while the defect they
# existed to catch was reintroduced in this file. Rendering stays here; the judgement is the
# helper's, and test-core.sh drives that helper directly. Same split as _core_luacheck_verdict.
#
# Assigned ONCE, straight from the helper. Do not post-process it: the original bug was exactly
# a second statement adjusting this number after the classification was already correct, and a
# static assertion in test-core.sh now fails if this stops being a single assignment.
_env_skips=${#_CORE_ENV_SKIPS[@]}
_tool_skips="$(_core_tool_skip_count)"

# ── machine-readable summary (--json): one object on stdout, then exit with the same
# status the human path would. Lets a CI step / editor parse the result instead of
# scraping coloured text. Strings are JSON-escaped (\ and ") via parameter expansion. ──
if ((JSON)); then
  if ((FAIL > 0)); then
    _result=failed
  elif ((STRICT && _tool_skips > 0)); then
    _result=failed-strict
  elif ((REQUIRE_SIBLINGS && _env_skips > 0)); then
    # New verdict, but only reachable via --require-siblings, which nothing passes today —
    # so it cannot move an existing consumer's result. `ok` deliberately keeps its meaning:
    # `partial` below is ADDITIVE rather than a new `ok-*` spelling, because the "--json
    # must not change the VERDICT" invariant compares this string against the plain run.
    _result=failed-siblings
  else _result=ok; fi
  printf '{"pass":%d,"skip":%d,"fail":%d,"seconds":%d,"strict":%s,"tool_skips":%d,"env_skips":%d,"partial":%s,"skipped":[' \
    "$PASS" "$SKIP" "$FAIL" "$SECONDS" "$( ((STRICT)) && echo true || echo false)" "$_tool_skips" "$_env_skips" \
    "$( ((SKIP > 0)) && echo true || echo false)"
  _first=1
  for _s in ${_CORE_SKIPS[@]+"${_CORE_SKIPS[@]}"}; do
    _s="${_s//\\/\\\\}"
    _s="${_s//\"/\\\"}"
    ((_first)) || printf ','
    printf '"%s"' "$_s"
    _first=0
  done
  printf '],"result":"%s"}\n' "$_result"
  [[ "$_result" == ok ]] && exit 0 || exit 1
fi

# ── summary ──────────────────────────────────────────────────────────────────
printf '\n%s──────── audit summary ────────%s\n' "$c_blu" "$c_rst"
printf '  %spass %d%s   %sskip %d%s   %sfail %d%s   %s(%ds)%s\n' \
  "$c_grn" "$PASS" "$c_rst" "$c_yel" "$SKIP" "$c_rst" "$c_red" "$FAIL" "$c_rst" \
  "$c_blu" "$SECONDS" "$c_rst"
# Name the SKIPPED gates so a "green" run is honestly labelled PARTIAL: a check whose tool
# was absent did not actually run, and several of those (markdownlint, actionlint, gitleaks,
# luacheck, nvim) ARE enforced in CI — so a clean local box can still differ from the gate.
# This makes the gap explicit instead of hiding it behind a bare count. --strict turns it red.
# Partition the skips: a gate skipped because its TOOL is absent is a real coverage gap;
# one skipped because its AREA is out of scope (a narrowed --scope/--changed run) is
# intentional. --strict fails ONLY on the former, so it can run on a fully-provisioned CI
# leg (every in-scope tool installed) without tripping on deliberately-narrowed areas.
if ((SKIP > 0)); then
  printf '  %s%d check(s) SKIPPED — this run is PARTIAL, not full:%s\n' "$c_yel" "$SKIP" "$c_rst" >&2
  for _s in "${_CORE_SKIPS[@]}"; do
    printf '    %s–%s %s\n' "$c_yel" "$c_rst" "$_s" >&2
  done
fi
# Say what the fleet-wide gates need, and how to get it. These skip on ANY lone clone —
# including CI, which checks out only this repo — so without this line the reader has no
# way to learn that three gates have simply never run for them.
if ((_env_skips > 0)); then
  printf '  %s%d of those are FLEET-WIDE gates with no sibling repo to read — they did not run.%s\n' \
    "$c_yel" "$_env_skips" "$c_rst" >&2
  printf '  %sClone the OS repos beside this one (see scripts/os-repos.txt), or pass --require-siblings to make this red.%s\n' \
    "$c_yel" "$c_rst" >&2
fi
((FAIL == 0)) || {
  printf '%saudit FAILED%s\n' "$c_red" "$c_rst" >&2
  exit 1
}
if ((STRICT && _tool_skips > 0)); then
  printf '%saudit FAILED (--strict: %d gate(s) skipped because their tool is absent — must all run)%s\n' "$c_red" "$_tool_skips" "$c_rst" >&2
  exit 1
fi
if ((REQUIRE_SIBLINGS && _env_skips > 0)); then
  printf '%saudit FAILED (--require-siblings: %d fleet-wide gate(s) had no sibling OS repo to read)%s\n' "$c_red" "$_env_skips" "$c_rst" >&2
  exit 1
fi
# THE LAST LINE IS THE ONE PEOPLE READ. A bare "audit OK" after a run that skipped a third
# of the fleet-wide gates is the false green this whole script exists to prevent — the body
# said PARTIAL, but the verdict said OK, and the verdict is what gets quoted in a PR. Say it
# where it cannot be missed. Exit status is unchanged (0): partial is not failure, and
# --strict / --require-siblings remain the ways to make it one.
if ((SKIP > 0)); then
  printf '%saudit OK — PARTIAL (%d check(s) skipped; see above)%s\n' "$c_yel" "$SKIP" "$c_rst"
else
  printf '%saudit OK%s\n' "$c_grn" "$c_rst"
fi
