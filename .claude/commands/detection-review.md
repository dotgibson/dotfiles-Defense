---
description: Judgment review of the Sigma detection corpus — quality, ATT&CK coverage holes, red↔blue gaps (report-first)
argument-hint: "[tactic, logsource, or theme — optional, e.g. credential_access, sysmon, cloud]"
allowed-tools: Read, Grep, Glob, WebSearch, WebFetch, Bash(./detections/sigma/convert.sh:*), Bash(./detections/navigator/gen-coverage.sh:*), Bash(./detections/navigator/gen-navigator.sh:*), Bash(git ls-files:*), Bash(git log:*), Bash(find:*), Bash(sigma check:*)
---

# /detection-review

Review the **quality and coverage** of the Sigma detection corpus in
`detections/sigma/` — the judgment half of the detection gate. `sigma.yml` already
*enforces* the mechanical half on every change (structural lint, compile-to-Splunk,
and the Navigator/COVERAGE/SIEM drift gates), so this routine does **not** re-check
what CI already proves. It reviews what a linter cannot: is a rule **well-scoped**,
is the **coverage** honest against the threats this repo says it defends, and does
every attack in the red mirror have a blue answer here.

The goal is a **reviewable report, not edits** — like every routine in this fleet,
report-first: propose, rank, and link; change nothing.

Focus for this run: **$ARGUMENTS** (empty = the whole corpus).

## Establish what's already proven (don't re-litigate CI)

Read these first so you review the judgment layer, not the mechanical one:

- `detections/navigator/COVERAGE.md` — the generated ATT&CK roll-up (by tactic /
  technique / logsource). This is your coverage map; it is drift-gated, so trust it.
- `DEFENSE-METHODOLOGY.md` — the ATT&CK → data-source → detection map this repo is
  *supposed* to cover. Coverage holes are measured against **this**, not against all
  of ATT&CK.
- `detections/sigma-validation-config.yml` + `.github/workflows/sigma.yml` — what CI
  already gates (so you don't report a structural issue the hard gate would catch).
- The rules themselves — `git ls-files 'detections/sigma/**/*.yml'`.

CI green means the rules parse, compile, and their tags/coverage artifacts are in
sync. It does **not** mean they're good detections. That's this routine's job.

## What to review (the judgment CI can't do)

1. **Rule scoping — the FP/evasion balance.** For each rule (or the focused subset):
   is the `detection` block **too broad** (matches benign activity → alert fatigue)
   or **too narrow / brittle** (keys on one easily-changed artifact → trivially
   evaded)? Flag rules whose `condition` doesn't really pin the technique, rules
   missing obvious `filter`/exclusion for known-benign callers, and rules that rely
   on a spoofable field (image name, description) instead of a robust signal.
2. **Logsource ↔ detection coherence.** Does the `logsource` (product/service/category)
   actually carry the fields the `detection` references? A rule that reads a field the
   declared source never emits is dead. Cross-check the field names against the event
   the logsource implies (e.g. a 4688 rule using Sysmon-only fields).
3. **ATT&CK coverage holes — measured against the methodology.** From `COVERAGE.md`
   and `DEFENSE-METHODOLOGY.md`, which **prioritized** tactics/techniques have thin
   (one fragile rule) or zero coverage? Rank the holes by how central the technique is
   to this repo's stated threat model — not by raw ATT&CK breadth. Verify any
   technique ID you cite against live MITRE ATT&CK (it moves; sub-techniques get
   renumbered).
4. **Red↔blue pairing gaps (the mirror).** Defense is the blue mirror of `dotfiles-Kali`.
   If a sibling `../dotfiles-Kali` checkout is present, scan its `PURPLE-TEAM.md` and
   the `offensive/companion` red entries for attacks that have **no** corresponding
   detection here. A documented attack with no blue answer is the highest-value gap.
   (Skip this dimension with a note if the sibling checkout isn't available.)
5. **Metadata that changes triage quality.** Beyond schema: is `level` proportionate
   to the technique's severity, is `status` honest (no stale `experimental` on a rule
   that's been stable), are `falsepositives` and `references` populated enough that a
   responder can triage the alert? These aren't lint failures but they degrade the
   corpus.

## How to report

A ranked shortlist, most-valuable first. For each finding:

- **The rule(s) or gap** — exact file path(s) under `detections/sigma/`, or the
  uncovered tactic/technique (with its verified ATT&CK ID).
- **Why it matters** — the concrete failure mode: *false-positive source X*, *evaded
  by Y*, *technique Z from PURPLE-TEAM.md has no detection*, *dead field reference*.
- **The proposed change** — tighten this condition, add this filter, author a new rule
  for this logsource, re-level this rule. Concrete enough to act on, but **do not make
  the edit**.
- **Confidence** — high / needs-a-human-look, one line of rationale.

Lead with your single strongest finding. "The corpus is well-scoped and coverage
matches the methodology — no material gaps this cycle" is a valid, useful result;
say so plainly rather than manufacturing findings.

## If a finding is adopted

The change is detection content: a new/edited rule under `detections/sigma/`. Whoever
picks it up must regenerate the drift-gated artifacts (`gen-navigator.sh`,
`gen-coverage.sh`, `gen-siem.sh` — bare form) and let `sigma.yml` gate the result, per
the repo's normal flow. Keep the red↔blue split intact: attacker-authored detections
belong in Kali's `PURPLE-TEAM.md`, defender-authored capability here. Propose only —
do not edit rules unless asked.
