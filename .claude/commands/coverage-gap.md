---
description: Rank the ATT&CK tactics/techniques the repo intends to cover but doesn't (report-first)
argument-hint: "[tactic or theme — optional, e.g. command_and_control, cloud]"
allowed-tools: Read, Grep, Glob, Bash(./detections/navigator/gen-coverage.sh:*), Bash(git ls-files:*), WebSearch, WebFetch
---

# /coverage-gap

Answer one quantitative question: **which ATT&CK tactics and techniques does this
repo intend to cover but currently doesn't — ranked?** This is the *numbers* half of
the coverage story; `/detection-review` handles the *qualitative* scoping (is a rule
good). Keep them distinct — this routine counts and ranks holes; it does not critique
individual rule `condition`s.

Focus for this run: **$ARGUMENTS** (empty = the whole matrix).

## Baseline first — read the generated coverage, don't recompute it

`sigma.yml` drift-gates the coverage artifacts, so trust them:

- `detections/navigator/COVERAGE.md` — the roll-up by tactic / technique / logsource
  (the *present* set).
- `detections/navigator/coverage-layer.json` — the machine-readable ATT&CK layer
  (`score` = rules per technique).
- `detections/navigator/gen-coverage.sh` — its `TACTICS` table enumerates **all 14**
  ATT&CK tactics (including the ones with zero rules), so the absent columns are
  computable directly.
- `DEFENSE-METHODOLOGY.md` — the ATT&CK → data-source → detection map this repo
  *intends* to cover. **Holes are measured against this intended set, not against all
  of ATT&CK.**

## What to compute

1. **Zero-coverage tactics** — of the 14 ATT&CK tactics, which have no rule at all?
   (From `gen-coverage.sh`'s table vs `COVERAGE.md`'s present set.) Note which are
   *intended* (named in the methodology) vs legitimately out of scope.
2. **Thin tactics** — a tactic carried by a single fragile rule, or with far fewer
   techniques than the methodology implies.
3. **Uncovered intended techniques** — techniques named in `DEFENSE-METHODOLOGY.md`
   (or its data sources) with no rule. Verify each ATT&CK ID against live MITRE (IDs
   move; sub-techniques get renumbered).
4. **Red↔blue holes** — if a `../dotfiles-Kali` sibling is present, attacks in its
   `PURPLE-TEAM.md` / `offensive/companion` red entries with no detection here. (Skip
   with a note if the sibling isn't checked out.)

## How to report

A ranked table, most-central-to-the-threat-model first:

- **tactic / technique (verified ATT&CK ID)** · current coverage (0 / thin) · why it
  matters for *this repo's* threat model · the logsource a detection would use.
- End with the honest headline: "N of 14 tactics covered; the highest-value hole is
  X." "Coverage matches the methodology — no material gaps this cycle" is a valid,
  useful result.

Report-first — propose the holes to fill; author no rules. A rule that gets adopted
lands under `detections/sigma/` and must regenerate the drift-gated artifacts
(`gen-coverage.sh`, `gen-navigator.sh`, `gen-siem.sh` — bare form), per the repo's
normal flow. Keep the red↔blue split intact. Do not edit anything unless I explicitly
ask.
