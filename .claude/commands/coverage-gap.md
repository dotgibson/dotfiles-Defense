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
- `detections/navigator/gen-coverage.sh` — its `TACTICS` table enumerates **all 15**
  ATT&CK tactics (including the ones with zero rules), so the absent columns are
  computable directly. It is 15, not 14, because ATT&CK v19 split Defense Evasion into
  **Stealth (TA0005)** and **Defense Impairment (TA0112)** — both carry rules here. Read
  the table, don't trust this count if the two ever disagree.
- `DEFENSE-METHODOLOGY.md` — the ATT&CK → data-source → detection map this repo
  *intends* to cover. **Holes are measured against this intended set, not against all
  of ATT&CK.**
- `DEFENSE-METHODOLOGY.md`'s **"Declined coverage" section and its
  `methodology-check: known-absent` marker** — the answered set. Two different things
  live in that marker: techniques **covered outside Sigma** (the whole `network/` plane
  — they read "0" in `COVERAGE.md` by design) and techniques **deliberately declined**,
  each with a stated reopen-condition. Treat both as **answered, not open**: do not
  re-report one unless its stated reopen-condition has actually changed (e.g. a
  TLS-inspecting proxy now exists, Sysmon Event 3 is now enabled, GCP Data Access
  logging is now on). Re-deriving them from the ATT&CK matrix is the single most common
  way this routine produces noise. The long form is in `detections/README.md`'s
  "Coverage gaps (honest notes)".
- **Check the corpus, not just the artifacts, before ranking anything as absent.** The
  generated files are drift-gated but only as fresh as the last commit — a rule merged
  after they were written still shows as a hole. `grep -ri 't1234' detections/` costs
  nothing and is the difference between a real finding and a stale one.

## What to compute

1. **Zero-coverage tactics** — of the 15 ATT&CK tactics `gen-coverage.sh`'s `TACTICS`
   table enumerates, which have no rule at all? (Compare it against `COVERAGE.md`'s
   present set.) Note which are *intended* (named in the methodology) vs legitimately
   out of scope.
2. **Thin tactics** — a tactic carried by a single fragile rule, or with far fewer
   techniques than the methodology implies.
3. **Uncovered intended techniques** — techniques named in `DEFENSE-METHODOLOGY.md`
   (or its data sources) with no rule. Verify each ATT&CK ID against live MITRE (IDs
   move; sub-techniques get renumbered) — and verify the **tactic** it belongs to
   before ranking it as filling a thin tactic row. A technique's name is not its
   tactic: T1530 *Data from Cloud Storage* reads like exfiltration and is Collection
   (TA0009), so closing it moves the Collection row and leaves Exfiltration untouched.
   Rank on the tactic ATT&CK actually assigns, or the ranking rationale is wrong even
   when the gap is real.
4. **Red↔blue holes** — if a `../dotfiles-Offense` sibling is present, attacks in its
   red corpus with no detection here. (Skip with a note if the sibling isn't checked
   out.)

   **Walk `offensive/companion/entries/red/*.md`, not `PURPLE-TEAM.md` alone.** Each red
   entry's frontmatter carries `attack.techniques` and the `pair:` naming its blue
   counterpart, which is the machine-readable set. `PURPLE-TEAM.md` is a *projection* of
   that corpus — the Windows-event-ID subset, ~24 of ~102 entries by its own admission —
   so a check that reads only it can only ever return "no holes", because every technique
   it names is on-prem AD the corpus already covers. #209 reported exactly that
   non-result. The real frontier is in the entries that do not project.

   Compare against **all three** Defense planes, not just Sigma: `detections/sigma/`
   `attack.tNNNN` tags, plus the native ATT&CK IDs in `detections/network/` (Suricata
   `metadata:`, Zeek comments) and `detections/siem/` (Sentinel `relevantTechniques:`,
   Splunk stanza names). A technique covered on the wire or by a correlation rule is
   covered; only `COVERAGE.md` cannot see it. Then subtract the `known-absent` marker
   before reporting anything.

## How to report

A ranked table, most-central-to-the-threat-model first:

- **tactic / technique (verified ATT&CK ID)** · current coverage (0 / thin) · why it
  matters for *this repo's* threat model · the logsource a detection would use.
- End with the honest headline: "N of 15 tactics covered; the highest-value hole is
  X." "Coverage matches the methodology — no material gaps this cycle" is a valid,
  useful result.

Report-first — propose the holes to fill; author no rules. A rule that gets adopted
lands under `detections/sigma/` and must regenerate the drift-gated artifacts
(`gen-coverage.sh`, `gen-navigator.sh`, `gen-siem.sh` — bare form), per the repo's
normal flow. Keep the red↔blue split intact. Do not edit anything unless I explicitly
ask.
