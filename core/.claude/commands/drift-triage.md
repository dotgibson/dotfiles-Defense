---
description: Interpret fleet-drift into ranked, per-repo remediation (report-first)
argument-hint: "[repo, optional — defaults to the whole fleet]"
allowed-tools: Read, Grep, Glob, Bash, WebSearch
---

# /drift-triage

`fleet-drift.yml` reports **which** repos have drifted from the latest Core release,
but only as red rows — it doesn't judge *how far behind* or *what to do*. Answer
that: for each lagging repo, how many Core releases behind it is, what it's missing,
and the exact remediation — **ranked** so the most-stale / highest-risk repo is first.

Scope for this run: **$ARGUMENTS** (empty = whole fleet).

## Baseline first — interpret, don't just echo

`fleet-drift.yml` already computes the drift rows and files/updates the standing
`"ci-failure: fleet-drift sweep is red"` issue; `core-integrity` gates each vendored
tree. Re-running `scripts/fleet-drift.sh` here is fine — that's how you *gather* the
current rows — but the deliverable is the **interpretation** (how far behind, what's
missing, what to run), never a copy of the sweep's raw output.

## What to do

1. **Read the current state.** Run `scripts/fleet-drift.sh` against the fleet checked
   out beside this repo (siblings via `--add-dir`; the drift baseline is the latest
   released Core tag). Also read this repo's `core.version` + latest `vX.Y.Z` tag.
2. **Compute the gap** per lagging repo: its `core.lock` `core_tag` / `core_sha`
   (Windows: `nvim/.core-ref`) vs the latest tag → how many releases it skipped.
3. **Weigh what it's missing:** read `CHANGELOG.md` across the skipped range. A
   security / hardening fix outranks a docs-only bump — rank by that, not just by
   count-behind.
4. **Give the exact remediation** per repo: `make sync` (Unix vendoring repos),
   `nvim-sync.ps1` + `starship-sync.ps1` (Windows), and flag any that would need a
   manual conflict resolution.

## How to report

Ranked, most-stale / highest-risk first:

- **`<repo>` — N releases behind (vX.Y.Z → vA.B.C)** · what it's missing (1 line) ·
  the remediation command.
- **Current** — the repos already up to date, so a green run is trustworthy.

Report-first — this routine *proposes* the sync; it does not run it. Do not edit
anything unless I explicitly ask.
