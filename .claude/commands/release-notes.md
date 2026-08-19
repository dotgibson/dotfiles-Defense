---
description: Draft the next release's notes from Conventional Commits (report-first)
argument-hint: "[from-ref — optional, defaults to the last release]"
allowed-tools: Task, Read, Grep, Glob, Bash(make release-notes), Bash(./scripts/gen-release-notes.sh:*), Bash(git log:*), Bash(git tag:*)
---

# /release-notes

Draft the release body for the next tag from its Conventional Commits — the report-first
preview a maintainer curates into `CHANGELOG.md` before `make release`. Complements
`/release-readiness` (which decides *whether* to release); this drafts *what goes in it*.

Range for this run: **$ARGUMENTS** (empty = since the last release; otherwise the range `$ARGUMENTS..HEAD`).

## How to draft

1. **Resolve the range.** From the last release to `HEAD`:
   `git log --grep='^release v' -1 --format=%H` (or the latest strict `vX.Y.Z` tag) → `HEAD`.
2. **Generate the grouped notes**, in this order of preference:
   - `make release-notes` — git-cliff + `cliff.toml`, when git-cliff is installed.
   - `./scripts/gen-release-notes.sh . "<last-tag>" HEAD` — the **first-party twin** that
     produces the same grouped output (Features / Bug Fixes / … in commit-parser order)
     with no git-cliff binary. Use this whenever git-cliff is absent (e.g. headless CI).
3. **Present the draft as-is**, then add a short **editorial pass**:
   - which bullets are user-facing vs internal plumbing,
   - anything that reads as a **breaking change** (surface it loudly — it drives the SemVer
     major bump),
   - a suggested one-line **release headline**.

`CHANGELOG.md` prose is hand-curated (the *rationale* for a change, not its commit subject),
so treat the generated bullets as **raw material** for the `[Unreleased]` section — a
scaffold to curate, not a drop-in. Report only — do **not** edit `CHANGELOG.md` or cut a tag.
