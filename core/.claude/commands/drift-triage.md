---
description: Interpret fleet-drift into ranked, per-repo remediation (report-first)
argument-hint: "[repo, optional — defaults to the whole fleet]"
allowed-tools: Read, Grep, Glob, WebSearch, Bash(./scripts/fleet-drift.sh:*), Bash(git log:*), Bash(git describe:*), Bash(git tag:*)
---

# /drift-triage

`fleet-drift.yml` reports **which** repos have drifted from the latest Core release,
but it doesn't judge *how far behind* or *what to do*. Answer that: for each repo,
how far off it is, what it's missing, and the exact remediation — **ranked** so the
most-stale / highest-risk repo is first.

The sweep has **three** states, and they take different remediations. Read the row,
don't assume red:

| Row | Meaning | Remediation |
| --- | --- | --- |
| `✓ current` | nothing owed. Either pinned exactly to the reference tag, or — for `✓ current (nvim up to date)` on Windows — a `nvim/` subtree already byte-identical to the release's, whatever its marker reads | none |
| `• current (ahead of vX.Y.Z …, on origin/main)` | carries **unreleased** Core — newer than the tag, still on main's lineage. **Not drift**; does not fail the sweep on its own | **cut a release** (see below) |
| `✗ BEHIND` / `DIFFERS` / `OFF-LINEAGE` / `DIVERGED` / `missing …` | genuine drift; forces exit **1** | `make sync`, or investigate the recorded sha |

The states **mix**. A sweep can be stale in one repo and unpinned in seven: the `•`
rows and the unreleased tally still print on a red run, and the exit code is 1
because of the `✗` rows. Read the exit code from the run itself, not from which row
types you can see.

A `•` row carries **two** numbers, and they mean different things:

- **`ahead of vX.Y.Z by N`** — a **release** is owed. `make sync` alone cannot fix
  this: it re-vendors the same lineage and stamps another `git describe` string, so
  the tag stays missing.
- **`N behind its tip`** — the fleet has not been re-synced since Core moved on, so
  a **sync** is owed as well. No such clause means the row sits exactly on main's
  tip and only the release is outstanding.

When both appear, the order is release **then** sync (`RELEASE-RUNBOOK.md`): syncing
first just re-stamps another untagged `describe` string, while the post-release sync
closes the unvendored commits *and* re-pins `core_tag` to a clean `vX.Y.Z`.

Scope for this run: **$ARGUMENTS** (empty = whole fleet).

## Baseline first — interpret, don't just echo

`fleet-drift.yml` already computes the drift rows and files/updates the standing
`"ci-failure: fleet-drift sweep is red"` issue; `core-integrity` gates each vendored
tree. Re-running the sweep here is fine — that's how you *gather* the current rows —
but the deliverable is the **interpretation** (how far behind, what's missing, what
to run), never a copy of the sweep's raw output.

**Run the sweep; never reconstruct it.** Do **not** re-derive the verdict by reading
`core.lock` markers and applying the classifier's logic yourself: that has already
produced a confident report that contradicted the script
(`dotgibson/dotfiles-core#381`).

**A non-zero exit is not a failure to run.** Read the exit code before deciding:

| Exit | Meaning | What to do |
| --- | --- | --- |
| `0` | no repo lags (may still carry `•` unreleased rows) | interpret the rows |
| `1` | **drift found — the sweep ran fine.** This is the case the routine exists for | **interpret the rows**; never treat it as a failed run |
| `2` | usage error (bad `--root`/`--ref`/`--color`) | the invocation is wrong — fix it and re-run |
| denied / not executed | the tool call never produced a sweep | say so plainly and **stop** |

Only the last two rows mean "no sweep". An **unrun** sweep is a finding to report,
not a gap to fill in by hand — but a **red** sweep is the deliverable's raw material,
so stopping on exit 1 would refuse exactly the job this routine was written to do.

## What to do

1. **Read the current state.** Run the sweep from this repo's root:

   ```bash
   ./scripts/fleet-drift.sh --color never
   ```

   The leading `./` is required — it's what the tool allowlist matches. No other flag
   is needed: `--root` defaults to this repo's *parent*, which is where the fleet is
   checked out (in CI too), and the baseline defaults to the latest released Core
   tag. Pass `--root DIR` only if the fleet lives somewhere else. `--add-dir` is a
   Claude Code flag, not a script flag — passing it to the script is a usage error.

   Also read this repo's `core.version` + latest `vX.Y.Z` tag.
2. **Compute the gap** per repo. For the eight Core-vendoring repos: `core.lock`'s
   `core_tag` / `core_sha` vs the latest tag → how many releases it skipped. For a
   `•` row, the gap that matters is the two numbers in the row itself: commits ahead
   of the tag (a release is owed) and `behind its tip` (a sync is owed).

   **dotfiles-Windows is not measured that way.** It vendors only the `nvim/`
   subtree, and `_classify_subtree` deliberately calls an *older* `.core-ref`
   **current** when no later release touched `nvim/` — the marker is only re-stamped
   when that subtree actually changes. Subtracting its marker tag from the latest
   Core tag therefore manufactures a "N releases behind" that isn't real; that is
   exactly the false diagnosis `#381` reached. **Trust the row's verdict**, and if you
   need to quantify, count only releases that actually changed the subtree:

   ```bash
   git log --oneline <marker-commit>..<latest-tag> -- nvim/
   ```

   Empty output means the vendored tree is byte-identical to the release's — current,
   with nothing owed.
3. **Weigh what it's missing:** read `CHANGELOG.md` across the skipped range. A
   security / hardening fix outranks a docs-only bump — rank by that, not just by
   count-behind.
4. **Give the exact remediation** per repo, matched to its state: `make sync` for a
   repo that genuinely **lags**; `nvim-sync.ps1` + `starship-sync.ps1` (Windows); a
   **release cut** for `•` unreleased rows, followed by `make sync` only if the row
   also reported `behind its tip` — in that order, per the table above. Flag any repo
   that would need manual conflict resolution.

## How to report

Ranked, most-stale / highest-risk first:

- **`<repo>` — N releases behind (vX.Y.Z → vA.B.C)** · what it's missing (1 line) ·
  the remediation command.
- **Unreleased** — the `•` rows: how far ahead of the tag, whether they're also
  behind main's tip, and that the fix is a release cut. Say plainly that these are
  **not** drift — but do **not** infer the exit code from them. A `•` row does not
  fail the sweep *on its own*; it coexists with `✗` rows in a mixed run, which exits
  **1** and still prints the unreleased tally. Report the exit code you actually
  observed, never one deduced from the row types.
- **Current** — the repos with nothing owed, so a green run is trustworthy. Report
  Windows from its subtree verdict, not from its marker's tag: `✓ current (nvim up
  to date)` means done, even when `.core-ref` names an older release.

If the sweep exited 0 with no `•` rows, say so in one line — a fully-pinned fleet is
the whole point, and a routine that manufactures concern from a green run is worse
than one that says nothing.

Report-first — this routine *proposes* the sync or the release; it does not run
either. Do not edit anything unless I explicitly ask.
