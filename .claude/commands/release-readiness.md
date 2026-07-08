---
description: Go/no-go readiness check before cutting a Core release
argument-hint: "[target version X.Y.Z — optional]"
allowed-tools: Task, Read, Grep, Glob, Bash(./scripts/audit-core.sh:*), Bash(./scripts/fleet-drift.sh:*), Bash(./scripts/update-plugins.sh --check), Bash(./scripts/update-nvim-plugins.sh --check), Bash(git log:*), Bash(git tag:*), Bash(cat core.version)
---

# /release-readiness

Answer ONE question: **is Core ready to cut a release right now, and if so, what version?**
This is the go/no-go gate that sits in front of `RELEASE-RUNBOOK.md` — it reports, it never
releases.

Target for this run: **$ARGUMENTS** (empty = infer the next version from the unreleased work).

## The readiness checklist (gather, then judge)

1. **Is there unreleased work worth shipping?** Read `CHANGELOG.md`'s `[Unreleased]` section
   and the Conventional Commits since the last release (`git log <last-release-tag>..HEAD`).
   If `[Unreleased]` is empty or only trivial, the verdict is "hold — nothing to ship yet."
2. **Is the tree green?** The one gate is `scripts/audit-core.sh`. A release cut off a red
   tree is never valid — note the audit status (the latest CI run on `main`, or `make audit`).
3. **Version coherence.** `core.version` vs the latest `vX.Y.Z` tag vs the `CHANGELOG.md`
   headings must line up (`release.sh` promotes `[Unreleased]` → a dated heading, opening a
   fresh one). Propose the next SemVer from the unreleased content: a breaking change → major,
   a `feat` → minor, only `fix`/`chore`/`docs` → patch.
4. **Is the fleet in a releasable state?** `fleet-drift.sh` (are the OS repos on the latest
   Core?) and pin freshness (`update-*-plugins.sh --check`). A release fans out, so surface
   any drift or stale pins that ought to settle first — **advisory**, not hard blockers.
5. **Any open blockers?** Open `freshness-triage` **Hold** verdicts, a failing scheduled
   sweep, or a security bump that should ride the release.

## How to report

A one-line **verdict** up top — **READY to cut vX.Y.Z** or **HOLD** — then:

- **What would ship** — the grouped highlights from `[Unreleased]` (the release's story).
- **Proposed version + why** — the SemVer bump the unreleased content implies.
- **Blockers / pre-flight** — anything that must be true first (red audit, fleet drift, a
  Hold PR), each with the one command that clears it, in `RELEASE-RUNBOOK.md` order.
- **Next command** — literally `make release VERSION=X.Y.Z` when READY, or the specific
  blocker to clear when HOLD.

Report only — do **not** run `release.sh` / `tag-release.sh` or edit `core.version` /
`CHANGELOG.md`. The maintainer drives `RELEASE-RUNBOOK.md` from here.
