#!/usr/bin/env bash
# scripts/audit-core.sh
# ──────────────────────────────────────────────────────────────────────────────
# THE AUDIT BUTTON — this repo's test suite.
#
# core.manifest calls itself "the contract. Audit scripts and the promotion
# checklist read it." This is that audit script. It verifies Core is internally
# consistent BEFORE it gets vendored (via scripts/sync-core.sh) into all 9 OS repos,
# where a defect would fan out N-way.
#
# Checks (each is a section; a failure in one does not abort the others):
#   1. manifest <-> filesystem drift   — every manifest path exists; every
#                                         tracked Core file is listed or allowlisted
#   2. executable-bit assertions       — *.sh and bin/clip* must be +x in the
#                                         git index; zsh/*.zsh must NOT be (sourced)
#   3. shell syntax                     — bash -n on bash scripts; zsh -n on zsh modules
#   4. lua                              — luacheck nvim/        (if luacheck present)
#   5. lint                             — shellcheck            (if present)
#  5c. Core⇄OS boundary                — no OS-absolute paths in portable zsh modules
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
# Shared palette + pass/skip/fail/hdr/have + _set_scope (one definition for every gate
# script). Sourced HERE — before the arg loop below calls _set_scope — and after QUIET
# is set so the lib's `: "${QUIET:=0}"` preserves it.
# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"
# Render the active scope as test-core.sh expects it (shell,nvim | shell | nvim | none).
_scope_str() {
  local s=""
  ((SCOPE_SHELL)) && s="shell"
  ((SCOPE_NVIM)) && s="${s:+$s,}nvim"
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
  --scope)
    # Require an explicit value: without this, `--scope --quiet` would swallow the
    # next flag as the scope list and silently drop it.
    if (($# < 2)) || [[ "$2" == -* ]]; then
      printf 'audit-core.sh: --scope requires a value (shell,nvim|all|none)\n' >&2
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
usage: audit-core.sh [-q|--quiet] [--strict] [--scope LIST] [--changed] [--color WHEN] [--json] [-h|--help]

THE audit button — manifest/exec-bit/syntax/lint/config/markdown/workflow/
version/behavioral checks. CI and pre-commit run this exact script.

  -q, --quiet     only print SKIP/FAIL lines and the final summary
  --json          emit a machine-readable summary object on stdout (implies --quiet):
                  {pass,skip,fail,seconds,strict,tool_skips,skipped[],result}. For CI
                  steps / editor integrations that want to parse, not scrape, the result.
  --strict        fail if any gate SKIPPED because its TOOL is absent — that gate did
                  not actually run, so a "green" with such skips is only PARTIAL. An
                  out-of-scope skip (a narrowed --scope/--changed run) is intentional and
                  does NOT trip --strict, so this is safe on a fully-provisioned CI leg
                  where every IN-SCOPE tool is installed. The summary names every skip.
  --scope LIST    limit the slow area-specific sections to a comma list:
                  shell, nvim, all (default), none. Cheap structural/config/
                  markdown/workflow/version checks always run. CI sets this from
                  scripts/ci-classify.sh; omit it locally to run the full audit.
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
  # Parse via the shared reader (scripts/lib/common.sh): it sets CLASSIFY_SHELL/CLASSIFY_NVIM
  # and returns non-zero if the classifier errored or emitted garbage — in which case fail
  # SAFE to the full run rather than silently returning "none" and skipping every slow gate.
  if ! _core_read_classify "$out"; then
    printf 'all'
    return
  fi
  [[ "$CLASSIFY_SHELL" == true ]] && scope="shell"
  [[ "$CLASSIFY_NVIM" == true ]] && scope="${scope:+$scope,}nvim"
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
  ARCHITECTURE.md
  PARITY.md RELEASE-STRATEGY.md RELEASE-RUNBOOK.md GITHUB-APP-AUTH.md V4-PROPOSAL.md
  core.manifest .gitignore .gitattributes .editorconfig .pre-commit-config.yaml .markdownlint.jsonc .shellcheckrc renovate.json
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
done < <(git ls-files '*.sh' 'bin/clip' 'bin/clip-paste' 2>/dev/null)
if ((SCOPE_SHELL)); then
  if have zsh; then
    # The sourced modules AND the autoloaded completion functions (zsh/completions/_*,
    # no .zsh extension) — both are zsh that fans out to 9 repos; both must parse.
    while IFS= read -r f; do
      if zsh -n "$f" 2>/dev/null; then pass "zsh -n  $f"; else fail "zsh syntax error: $f"; fi
    done < <(git ls-files 'zsh/*.zsh' 'zsh/completions/*' 2>/dev/null)
  else
    skip "zsh -n (zsh not installed)"
  fi
else
  skip "zsh -n (out of scope)"
fi

# ── 4. lua ───────────────────────────────────────────────────────────────────
hdr "lua (luacheck)"
if ! ((SCOPE_NVIM)); then
  skip "luacheck (out of scope)"
elif have luacheck; then
  # luacheck discovers .luacheckrc by searching UP from the CWD, not the target —
  # so run it from inside nvim/, where nvim/.luacheckrc lives. From repo root it
  # would miss the config and emit hundreds of false "undefined vim" warnings.
  if (cd nvim && luacheck . --no-color >/dev/null 2>&1); then
    pass "luacheck nvim/"
  else
    fail "luacheck reported issues — run: (cd nvim && luacheck .)"
  fi
else
  skip "luacheck (not installed)"
fi

# ── 5. lint (shellcheck) ─────────────────────────────────────────────────────
hdr "lint (shellcheck)"
if ! ((SCOPE_SHELL)); then
  skip "shellcheck (out of scope)"
elif have shellcheck; then
  sc_fail=0
  while IFS= read -r f; do
    shellcheck -x "$f" >/dev/null 2>&1 || {
      sc_fail=1
      fail "shellcheck: $f"
    }
  done < <(git ls-files '*.sh' 'bin/clip' 'bin/clip-paste' 2>/dev/null)
  ((sc_fail)) || pass "shellcheck (all bash scripts clean)"
else
  skip "shellcheck (not installed)"
fi

# ── 5b. fzf preview binary resolution (regression gate) ──────────────────────
# fzf / fzf-tab previews run their command STRING in a subshell, so a LITERAL `bat`
# there printed "command not found" in every preview pane on Debian/Ubuntu — those
# distros ship bat as `batcat` — a silent breakage that fanned out to those OS repos
# with no failing gate. The fix routes previews through $BAT_BIN (tools.zsh resolves
# the real name) with a cat/ls fallback. Lock it so the bug can't recur: no uncommented
# preview line in zsh/35-fzf.zsh or zsh/45-plugins.zsh may invoke a literal bat/batcat, and
# fzf.zsh must still reference $BAT_BIN. Pure sed+grep (busybox-safe), shell-scoped.
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
# or macOS ~/Library path could slip into a portable shell module and fan out to 9 repos
# where it is simply wrong. Assert the sourced zsh modules stay OS-agnostic. EXCLUDED:
# zsh/55-maint.zsh — the scheduler CONTROL SURFACE whose launchd arm legitimately writes
# ~/Library/LaunchAgents (it switches on _maint_scheduler, the correct cross-OS shape).
# Comment-stripped first, so an explanatory comment naming an OS path can't trip it.
# Pure sed+grep (busybox-safe), shell-scoped like the other shell-layer gates.
hdr "Core⇄OS boundary (no OS paths in portable Core files)"
if ((SCOPE_SHELL)); then
  bnd_fail=0
  # Scan BOTH the portable shell modules AND the SYMLINKED config files (mise, git,
  # tmux, starship). The latter were previously ungated — yet they are vendored and
  # symlinked verbatim into every OS repo just like the zsh modules, so a hard-coded
  # /opt/homebrew in starship.toml or an /Library/ path in gitconfig fans out N-way
  # exactly the same way. A real drift of this shape was found downstream (an OS path
  # baked into mise/config.toml). The os/ layer is where those belong. The .example
  # templates are EXCLUDED — they are user-edited illustrations, not the live config.
  while IFS= read -r f; do
    [[ "$f" == zsh/55-maint.zsh ]] && continue # OS-switched scheduler surface (see above)
    if sed 's/#.*//' "$f" | grep -qE '/opt/homebrew|/home/linuxbrew|/usr/local/Cellar|/Library/|/mnt/c/'; then
      bnd_fail=1
      fail "OS-specific path in a portable Core file ($f) — it belongs in the OS layer, not Core"
    fi
  done < <(git ls-files 'zsh/*.zsh' \
    'mise/config.toml' 'git/gitconfig' \
    'tmux/tmux.conf' 'tmux/tmux.reset.conf' 'starship/starship.toml' 2>/dev/null)
  ((bnd_fail)) || pass "portable Core files (shell modules + symlinked configs) carry no OS-absolute paths"
else
  skip "Core⇄OS boundary (out of scope)"
fi

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
  done < <(git ls-files '*.toml' '*.toml.example' 2>/dev/null)
else
  skip "toml parse (python3 tomllib unavailable — needs python ≥3.11)"
fi
if have python3 && python3 -c 'import yaml' 2>/dev/null; then
  while IFS= read -r f; do
    # safe_load_all: workflow/compose YAML can be multi-document (--- separators).
    if python3 -c 'import yaml,sys; list(yaml.safe_load_all(open(sys.argv[1])))' "$f" 2>/dev/null; then
      pass "yaml $f"
    else fail "yaml parse error: $f"; fi
  done < <(git ls-files '*.yml' '*.yaml' 2>/dev/null)
else
  skip "yaml parse (python3 PyYAML not importable)"
fi
# JSON: nvim/lazy-lock.json pins every Neovim plugin's commit for a reproducible
# editor across the 9 repos — a truncated/corrupt lock breaks `:Lazy restore` for
# all of them, and like the toml/yaml above it's valid *text* the other gates skip.
# `*.json` (not `*.jsonc`) so the JSONC config files keep their comments. json is in
# the stdlib, so this only needs python3 — no extra import gate like PyYAML.
if have python3; then
  while IFS= read -r f; do
    if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null; then
      pass "json $f"
    else fail "json parse error: $f"; fi
  done < <(git ls-files '*.json' 2>/dev/null)
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
  if "${_mdl[@]}" "**/*.md" >/dev/null 2>&1; then
    pass "markdownlint (all tracked markdown clean)"
  else
    fail "markdownlint reported issues — run: markdownlint-cli2 '**/*.md'"
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
  if actionlint >/dev/null 2>&1; then
    pass "actionlint (workflows valid)"
  else
    fail "actionlint reported issues — run: actionlint"
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
  if gitleaks dir . --no-banner --redact >/dev/null 2>&1; then
    pass "gitleaks (no secrets in the working tree)"
  else
    fail "gitleaks found potential secrets — run: gitleaks dir . --redact"
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

# core.version is the human-readable Core stamp vendored into all 9 OS repos (read by
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
  rm -f "$BEHAV_OUT"
  if ((_behav_rc == 0)); then
    pass "behavioral tests (load-order smoke + function units)"
  else
    fail "behavioral tests failed — run: ./scripts/test-core.sh"
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

# Count tool-skips (absent tool = real coverage gap) vs out-of-scope skips up front so
# both the human summary and the --json object can report it. (Done before either render.)
_tool_skips=0
for _s in ${_CORE_SKIPS[@]+"${_CORE_SKIPS[@]}"}; do
  [[ "$_s" == *"out of scope"* ]] || _tool_skips=$((_tool_skips + 1))
done

# ── machine-readable summary (--json): one object on stdout, then exit with the same
# status the human path would. Lets a CI step / editor parse the result instead of
# scraping coloured text. Strings are JSON-escaped (\ and ") via parameter expansion. ──
if ((JSON)); then
  if ((FAIL > 0)); then
    _result=failed
  elif ((STRICT && _tool_skips > 0)); then
    _result=failed-strict
  else _result=ok; fi
  printf '{"pass":%d,"skip":%d,"fail":%d,"seconds":%d,"strict":%s,"tool_skips":%d,"skipped":[' \
    "$PASS" "$SKIP" "$FAIL" "$SECONDS" "$( ((STRICT)) && echo true || echo false)" "$_tool_skips"
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
((FAIL == 0)) || {
  printf '%saudit FAILED%s\n' "$c_red" "$c_rst" >&2
  exit 1
}
if ((STRICT && _tool_skips > 0)); then
  printf '%saudit FAILED (--strict: %d gate(s) skipped because their tool is absent — must all run)%s\n' "$c_red" "$_tool_skips" "$c_rst" >&2
  exit 1
fi
printf '%saudit OK%s\n' "$c_grn" "$c_rst"
