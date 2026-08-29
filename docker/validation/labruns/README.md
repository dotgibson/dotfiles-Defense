# Lab runs — the record of a detection actually being fired

`DEFENSE-METHODOLOGY.md` states the principle: **a detection isn't real until it's fired on
purpose.** Step 4 of the lifecycle ("Validate (purple) — run the technique from Offense, confirm
the rule fires") is the one step this repo could not previously show its work for, because
nothing recorded the result anywhere a reader could check.

This directory is that record. One file per run, named `YYYY-MM-<subject>.md`.

## Why it exists separately from the fixtures

`docker/validation/` proves a rule fires against **our** fixture. Where the fixture was
hand-written from the same belief that produced the rule, that proves internal consistency and
nothing about what the provider emits — the #149 shape, which
`docker/validation/fixture-provenance.tsv` exists to make visible.

A lab run is the thing that breaks the circle. It is also the only route by which a provenance
row can honestly reach `captured`. So the ledger note cites the run record, and the run record
carries the evidence the note is claiming.

## What a run record must contain

- **The question**, and the issue tracking it.
- **The source of the telemetry** — pinned. A first-party capture names the host, the Sysmon
  build and the attack that produced it; a third-party capture names the corpus and the commit.
- **The raw event**, verbatim. Not a summary of it.
- **What fired** — the shipped rule, run against that telemetry, with the engine and version.
- **What the run does NOT settle.** This is the half that keeps the ledger honest; a run that
  claims more than it measured is worse than no run.

## Provenance tiers a run can support

`captured` is reserved for **first-party** capture — our config, our host, our attack. A
third-party capture is strong evidence about the *provider's* behaviour and earns
`vendor-documented`, which is how the ledger already records the captured Splunk EID 20 sample
behind the WMI rows. The distinction is not pedantry: a third-party EVTX proves what some Sysmon
build emitted on someone else's host, which is exactly the claim a schema question needs and
exactly not the claim "our shipped config produces this" needs.
