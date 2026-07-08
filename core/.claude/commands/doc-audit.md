---
description: Cross-check docs against reality across the dotfiles fleet
argument-hint: "[repo-or-area, optional — defaults to full sweep]"
allowed-tools: Task, Read, Grep, Glob, Bash(git status:*), Bash(git diff:*), Bash(git ls-files:*), Bash(git log:*), Bash(ls:*)
---

# /doc-audit

Find **semantic drift** between what the docs claim and what the system actually
is — the class of inconsistency `scripts/audit-core.sh` cannot catch because it is
about meaning, not structure.

Scope for this run: **$ARGUMENTS** (empty = full fleet sweep).

Delegate the heavy reading to the `doc-consistency` subagent so the sweep does not
fill this conversation with file dumps — launch it with the Task tool and relay
its report. Then, only if asked, open a PR with the fixes.

## What to check

Run these cross-checks (skip any out of the requested scope):

1. **README layout ↔ `core.manifest` ↔ filesystem.** The "Layout" tree in
   `README.md` should describe the same files the manifest lists and that exist on
   disk. Flag files present but undocumented, documented but absent, or in the
   wrong layer.
2. **`aliases.md` ↔ its alias sources, in every repo that ships one.** Core's
   `aliases.md` against `zsh/aliases.zsh` + `zsh/git.zsh`; **and each role repo's
   `aliases.md` against its own role source** — `dotfiles-Kali/aliases.md` ↔
   `offensive/offensive.zsh`, `dotfiles-Defense/aliases.md` ↔ `defense/defense.zsh`.
   Every documented alias/function should exist in the source, and notable source
   aliases/helpers (e.g. a new `redup`, `gdft`) should be documented. Flag stale,
   renamed, or undocumented entries. (This is the fleet-wide alias-cheatsheet upkeep
   that used to run as a separate daily routine — it lives here now.)
3. **`PORTING-MATRIX.md` ↔ each OS repo.** For each distro, check the
   package-manager commands and package names against that repo's
   `install/packages.txt` and `os/<distro>.zsh`. Flag a package renamed upstream,
   a command that drifted, or a distro the matrix and the repo disagree on.
4. **Vendored `core/` freshness.** Read each sibling OS repo's `core.lock` and
   compare `core_sha` / `core_version` against this repo's `core.version` and HEAD.
   Flag any repo whose vendored Core is behind (needs `make sync`).
5. **`CHANGELOG.md` `[Unreleased]` ↔ recent commits.** Surface user-visible
   commits since the last release that have no changelog entry.
6. **Cross-repo claims.** The repo count, the layer model, and install commands
   are repeated across many READMEs and `dotfiles-web`. Flag copies that disagree.

## How to report

Group findings by severity:

- **Drift (fix needed)** — a concrete mismatch, with `file:line` on both sides and
  the one-line fix.
- **Stale (likely outdated)** — probably wrong but needs your call.
- **Clean** — what was checked and matched, so a green run is trustworthy.

Do not edit anything unless I explicitly ask. If I do, fix Core **here** (never in
a vendored `core/`), keep `core.manifest` in step, add a `CHANGELOG.md` entry, and
run `make audit` before proposing the PR.
