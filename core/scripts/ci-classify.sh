#!/usr/bin/env bash
# scripts/ci-classify.sh — map a set of changed paths to which CI gates must run.
# ──────────────────────────────────────────────────────────────────────────────
# ci.yml's change-detection decides, per push, whether the shell matrix / nvim
# steps / Alpine + bench legs run. That logic used to be inline bash INSIDE the
# workflow YAML: untested, unlinted, and drift-prone — a NEW top-level path not
# added to its glob lists would silently skip a gate, and a skipped gate fans out
# to all eight OS repos undetected. Pulling it here makes it shellcheck-clean, unit-
# tested (scripts/test-core.sh asserts the mapping), and FAIL-CLOSED.
#
# Reads changed paths on stdin, one per line (or the single token `__ALL__` when the
# diff base couldn't be resolved). Writes two KEY=value lines to stdout:
#     shell=<true|false>
#     nvim=<true|false>
# so the caller can append them straight to $GITHUB_OUTPUT.
#
# Buckets (first match per file wins):
#   • infra      scripts/ .github/ .claude/ core.manifest core.version
#                .pre-commit-config.yaml .shellcheckrc Makefile — cross-cutting, force
#                the FULL run
#   • nvim       nvim/**                         → nvim
#   • shell      zsh/ bin/ maint/ tmux/ sesh/ starship/ mise/ atuin/ git/ **/*.sh → shell
#   • inert      *.md + repo-meta dotfiles + examples/ (nothing links it) → no gate
#   • anything else → FAIL CLOSED: force the full run and log it. Getting the inert
#     list wrong only costs a wasted full run (safe); the old code's failure mode was
#     a SKIPPED gate (unsafe) — this inverts that, matching ci.yml's "safe default".
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

shell=false
nvim=false
full() {
  shell=true
  nvim=true
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
  zsh/* | bin/* | maint/* | tmux/* | sesh/* | starship/* | mise/* | atuin/* | git/* | *.sh) shell=true ;;
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

printf 'shell=%s\nnvim=%s\n' "$shell" "$nvim"
