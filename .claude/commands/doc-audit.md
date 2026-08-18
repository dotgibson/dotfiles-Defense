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

1. **`core.manifest` ↔ `git ls-files` ↔ `blib_link_core`.** The real three-way
   inventory: every manifest path exists and is tracked, every tracked Core file is
   listed (or allowlisted), and every symlinked config is actually wired by
   `lib/bootstrap-lib.sh`. Flag files present but unwired, wired but unlisted, or in
   the wrong layer. (The README carries no file tree — it documents behaviour, not
   inventory — so do not look for a "Layout" section; `audit-core.sh` covers the
   manifest↔filesystem halves mechanically, leaving the bootstrap-wiring half here.)
2. **`aliases.md` ↔ its alias sources, in every repo that ships one.** Core's
   `aliases.md` against `zsh/20-aliases.zsh` + `zsh/25-git.zsh`; **and each role repo's
   `aliases.md` against its own role source** — `dotfiles-Offense/aliases.md` ↔
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

   **Mind the reference frame.** Most of `dotfiles-web` documents Core's `main`, but
   `src/content/docs/reference/porting-matrix.md` is a **release-pinned mirror**: its
   CI (`.github/workflows/data-freshness.yml`) diffs it against Core's latest
   **release tag**, not `main`. Resolve the tag first, then fetch the file at it —
   two calls, because `releases/latest` is its own endpoint and is not a valid
   `ref` value:

   ```bash
   tag=$(gh api repos/dotgibson/dotfiles-core/releases/latest --jq .tag_name)
   gh api "repos/dotgibson/dotfiles-core/contents/PORTING-MATRIX.md?ref=${tag}" \
     --jq .content | tr -d '\n' | base64 -d
   ```

   Compare the page against **that**. Diffing it against `main` reports every
   unreleased Core change as web drift, and "fixing" it re-mirrors `main` into a file
   whose contract is the tag, turning a green check red. That exact false positive
   shipped in the 2026-08-11 sweep (#375, finding 5). The mirror is **correct when it
   lags `main` but matches the newest release**; it is genuinely stale only once a
   release Core has cut is not reflected in it.

## How to report

Group findings by severity:

- **Drift (fix needed)** — a concrete mismatch, with `file:line` on both sides and
  the one-line fix.
- **Stale (likely outdated)** — probably wrong but needs your call.
- **Clean** — what was checked and matched, so a green run is trustworthy.

Do not edit anything unless I explicitly ask. If I do, fix Core **here** (never in
a vendored `core/`), keep `core.manifest` in step, add a `CHANGELOG.md` entry, and
run `make audit` before proposing the PR.
