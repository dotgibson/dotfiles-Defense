---
description: Scout the next CI modernization floor and propose baseline bumps
argument-hint: "[dimension or theme — optional, e.g. runners, actions, security]"
allowed-tools: Task, Read, Grep, Glob, WebSearch, WebFetch, Bash(./scripts/check-modern.sh), Bash(git ls-files:*), Bash(git log:*)
---

# /modernize

Propose how to **raise the CI modernization floor** — the judgment half of the
`check-modern.sh` gate, which can *enforce* a floor but cannot know when the
industry has moved it. `scripts/modern-baseline.yml` **declares** what "modern"
means, `scripts/check-modern.sh` **enforces** it, and this routine scouts what the
**next** floor should be. The goal is a reviewable proposal, not a blind bump — you
**raise the floor deliberately, never lower it**, and you never edit the baseline
without approval.

Focus for this run: **$ARGUMENTS** (empty = scan every dimension).

## Establish the current floor first

Before researching, read what the floor already declares so you do not "discover" a
rule that is already in force:

- `scripts/modern-baseline.yml` — the declared floor (banned patterns, banned
  runners, SHA-pin + container-digest requirements). This is the source of truth.
- `scripts/check-modern.sh` — how each rule is enforced (so a proposal that needs a
  new *check dimension*, not just a new list entry, is costed honestly).
- The fleet's actual workflows — `git ls-files '.github/workflows/*.yml'` here, and
  note the OS repos inherit the reusable `*-call.yml@v3` workflows, so a floor bump
  fans out N-way just like Core.

Run `./scripts/check-modern.sh` to see the fleet's *current* standing against the
floor before proposing to move it.

## What to research (live — deprecations are dated events)

1. **EOL runner labels.** Check GitHub's `actions/runner-images` deprecation
   schedule and changelog. Which `ubuntu-*` / `macos-*` / `windows-*` labels have a
   **published** retirement date that has passed or is imminent? Each belongs in
   `banned_runners`. Separately, flag any runner the fleet *currently uses* that is
   approaching EOL — that is a fix-first, not a floor-bump-first.
2. **Removed/deprecated workflow features.** New `::command::` deprecations, and the
   **action runtime** treadmill (`node16` → `node20` → `node24`): when GitHub
   announces a runtime brownout/removal, actions still on it must move. Decide
   whether this is a new `banned_patterns` entry or a new check dimension.
3. **Pinning-discipline gaps.** Does the SHA-pin / `@sha256:` digest rule miss a
   surface the fleet now uses — `docker://` container actions in `uses:`, a new
   `image:` location, composite-action refs? Propose closing the gap.
4. **New floor dimensions.** GitHub-recommended modern/security practices worth
   encoding next: explicit least-privilege `permissions:` blocks,
   `persist-credentials: false` on checkout, pinned reusable-workflow *inputs*.
   Propose these as **watch** candidates unless the fleet already satisfies them.

Verify every deprecation against the **primary source** (the GitHub Changelog or the
`runner-images` repo), with the date — do not trust a single blog post. A "banned"
entry the fleet cannot yet satisfy is a staged migration, not a floor you can flip on.

## How to report

A ranked shortlist. For each proposed floor change:

- **The exact baseline edit** — which key in `scripts/modern-baseline.yml` gains or
  changes which value (show the line), and whether `check-modern.sh` needs a new
  dimension to enforce it.
- **Why now** — the upstream deprecation/announcement with its date and link.
- **Enforceability today** — run the rule mentally (or via `check-modern.sh`) against
  the fleet: does it pass now, or does it flag workflows that must be fixed **first**?
  Name the fix-first work and the safe order (fix workflows → then raise the floor).
- **Recommendation** — raise now / stage (fix-first) / watch / skip, one-line rationale.

Lead with your single strongest recommendation. "The floor is already current —
nothing to raise this cycle" is a valid, useful result; say so plainly.

## If a proposal is adopted

The change is Core dev tooling: `scripts/modern-baseline.yml` (and maybe a new
enforcement branch in `scripts/check-modern.sh`), plus any **fix-first** workflow
edits so the raised floor stays green. Add a `CHANGELOG.md` entry under
`[Unreleased]` and run `make audit` (which runs `check-modern.sh` at §8c) before the
PR. Propose only — do not edit the baseline unless I ask.
