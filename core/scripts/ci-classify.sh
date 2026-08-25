#!/usr/bin/env bash
# scripts/ci-classify.sh — map a set of changed paths to which CI gates must run.
# ──────────────────────────────────────────────────────────────────────────────
# ci.yml's change-detection decides, per push, whether the shell matrix / nvim
# steps / Alpine + bench legs run. That logic used to be inline bash INSIDE the
# workflow YAML: untested, unlinted, and drift-prone — a NEW top-level path not
# added to its glob lists would silently skip a gate, and a skipped gate fans out
# to all nine OS repos undetected. Pulling it here makes it shellcheck-clean, unit-
# tested (scripts/test-core.sh asserts the mapping), and FAIL-CLOSED.
#
# Reads changed paths on stdin, one per line (or the single token `__ALL__` when the
# diff base couldn't be resolved). Writes three KEY=value lines to stdout:
#     shell=<true|false>
#     nvim=<true|false>
#     atuin=<true|false>
# so the caller can append them straight to $GITHUB_OUTPUT.
#
# Buckets (first match per file wins):
#   • infra      scripts/ .github/ .claude/ core.manifest core.version
#                .pre-commit-config.yaml .shellcheckrc Makefile — cross-cutting, force
#                the FULL run
#   • atuin      zsh/00-tools.zsh + atuin/**      → shell AND atuin
#   • nvim       nvim/**                         → nvim
#   • shell      zsh/ bin/ maint/ tmux/ sesh/ starship/ mise/ git/ tealdeer/ **/*.sh → shell
#   • inert      *.md + repo-meta dotfiles + examples/ (nothing links it) → no gate
#   • anything else → FAIL CLOSED: force the full run and log it. Getting the inert
#     list wrong only costs a wasted full run (safe); the old code's failure mode was
#     a SKIPPED gate (unsafe) — this inverts that, matching ci.yml's "safe default".
#
# WHY atuin IS ITS OWN AXIS. The `atuin` gate is the hermetic self-test of
# scripts/verify-atuin-guard.sh — 197s of a 286s behavioral suite, 68% of it, and the
# single largest cost on the CI critical path. It exercises the premise DETECTOR against
# stub binaries; the detector's real job, measuring live upstream atuin, runs weekly in
# .github/workflows/atuin-guard-verify.yml and not on pushes at all. So the only changes
# that can move its result are the detector itself (scripts/, already infra → full) and
# the guard it protects, `_core_atuin_daemon_guard` in zsh/00-tools.zsh, plus the atuin/
# config tree. A change to zsh/10-ui.zsh paid all 197s for a harness it cannot reach.
#
# Note the ORDER below: zsh/00-tools.zsh must be matched BEFORE the general `zsh/*` arm,
# because first match per file wins.
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

shell=false
nvim=false
atuin=false
full() {
  shell=true
  nvim=true
  atuin=true
}

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ "$f" == "__ALL__" ]]; then
    full
    break
  fi
  case "$f" in
  scripts/* | .github/* | .claude/* | core.manifest | core.version | .pre-commit-config.yaml | .shellcheckrc | Makefile) full ;;
  nvim/*) nvim=true ;;
  # The guard's own module and the atuin config tree — the only non-infra paths that can
  # change what the premise detector's self-test observes. Matched BEFORE the general
  # `zsh/*` arm below, which would otherwise swallow 00-tools.zsh as plain shell.
  zsh/00-tools.zsh | atuin/*)
    shell=true
    atuin=true
    ;;
  zsh/* | bin/* | maint/* | tmux/* | sesh/* | starship/* | mise/* | git/* | tealdeer/* | *.sh) shell=true ;;
  # examples/ is repo-meta: bootstrap links NOTHING from it (see examples/README.md), so a
  # change there gates nothing — it would otherwise hit the fail-closed arm and force a full
  # run with an "unrecognised path" line, which reads like a bug rather than a showcase edit.
  *.md | examples/* | LICENSE | CODEOWNERS | .gitignore | .gitattributes | .editorconfig | .markdownlint.jsonc | .prettierrc.json) ;;
  *)
    printf "ci-classify: unrecognised path '%s' → forcing full run (add it to a bucket)\n" "$f" >&2
    full
    ;;
  esac
done

printf 'shell=%s\nnvim=%s\natuin=%s\n' "$shell" "$nvim" "$atuin"
