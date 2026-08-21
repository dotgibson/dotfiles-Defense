---
description: Review recently-changed zsh/bash for runtime footguns lint can't catch (report-first)
argument-hint: "[since-ref or path, optional — defaults to changes since the last release tag]"
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*), Bash(git ls-files:*), Bash(git show:*), Bash(git describe:*)
---

# /shell-review

Read the shell that changed recently and find the **behavioural footguns**
`shellcheck` / `zsh -n` can't — the class that passes lint and still bites at
runtime. This is the review that would have caught this session's real bugs: a tmux
popup that hijacked the main session on close, and a doctor hint that overclaimed
what a package manager could install.

Scope for this run: **$ARGUMENTS** (empty = every `zsh/*.zsh` + `**/*.sh` changed
since the last release tag — `git diff "$(git describe --tags --abbrev=0)"..HEAD`).

## Baseline first — don't re-litigate what CI proves

`scripts/audit-core.sh` (run by `ci.yml` and `make audit`) already runs the shell
gates on every change — `shellcheck`, `bash -n`, `zsh -n`, and the behavioural suite.
This routine does **not** re-report a shellcheck finding — it reads for *semantics*:
what the code will DO on a real box.

## What to check (the footgun classes)

1. **tmux / terminal state.** `display-popup` + `attach` vs `switch-client`; a
   session/client that survives its target being destroyed (interaction with
   `detach-on-destroy off`); `key-table` / `prefix` / `status` set with the wrong
   `set-option` flag; an option set only at creation that a *persistent* object
   needs on every open. (The scratchpad-hijack class.)
2. **Docs vs reality.** A comment or user-facing hint that **overclaims** — "install
   with X" where X can't install all of it, or advice that contradicts
   `PORTING-MATRIX.md`. (The doctor-hint class.)
3. **Quoting & word-splitting.** Unquoted expansions in paths/globs; array-vs-string
   confusion; `${x}` where `"$x"` is meant; `[ ]` vs `[[ ]]` pitfalls.
4. **`set -e` / subshell / `exec` traps.** A non-zero exit wrongly swallowed **or**
   wrongly fatal; `exec` that replaces the shell unexpectedly; a `$(...)`/`( )`
   subshell that drops state the caller needs.
5. **Idempotency & re-run safety.** Logic gated on "create-if-absent" that never
   re-applies a setting a persistent object needs on later runs (the class where a
   fix only helps freshly-created state).
6. **Startup-cost regressions** in `zsh/*.zsh` — a new per-shell fork/subprocess on
   the interactive path (the fleet gates `CORE_BENCH_BUDGET_MS`; flag anything that
   would blow it).

## How to report

Rank strongest first; cite `file:line`, the runtime failure it causes, its trigger,
and the one-line fix:

- **Bug (will misbehave)** — a concrete runtime failure, with the input/box that
  triggers it.
- **Risk (likely)** — a fragile pattern that will bite under some condition.
- **Clean** — files reviewed with nothing found, so a green run is trustworthy.

Report-first. Fix Core **here** (never a vendored `core/`), keep `core.manifest` in
step, add a `CHANGELOG.md` entry, and run `make audit` before proposing a PR. Do not
edit anything unless I explicitly ask.
