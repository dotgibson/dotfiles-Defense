<!-- This repo is the defensive ROLE layer and vendors ONE subtree (core/). It owns no
     OS-native layer — that is the OS repos'. Most review mistakes here are
     "right change, wrong layer", or a rule edit that leaves a generated artifact behind. -->

## What & why

<!-- One or two lines. -->

## Which layer does this belong to?

- [ ] It is **not** in `core/` — that tree is vendored from
      [dotfiles-core](https://github.com/dotgibson/dotfiles-core) and is overwritten on
      the next sync. Identical-everywhere config is fixed **upstream**.
- [ ] Changes with the **OS** (packages, paths, an `ID=` gate) belong in the matching
      OS repo, **not here**. Changes with the **analyst** → `defense/`, `detections/`.

## If you touched a detection

- [ ] `make drift` green — the generated artifacts (`COVERAGE.md`,
      `coverage-layer.json`, the SIEM deploy forms) are regenerated, not hand-edited.
      These are byte-compared in CI; a stale one reads as an unrelated red gate.
- [ ] `make methodology` green — `DEFENSE-METHODOLOGY.md` still describes the rules
      that exist, and the README's gate list still matches `sigma.yml`.
- [ ] `make validation-gates` green — the new rule has validation coverage, and any
      new fixture has provenance.
- [ ] ATT&CK technique IDs are real (`make attack-tags`; needs the network).
- [ ] If a `filter_*` rule changed: it still has a true negative.

## Environment data never enters this repo

- [ ] No real hostnames, internal IPs, user names, credentials, or captured telemetry
      from a live estate. Fixtures are synthetic or vendor-documented — see
      `docker/validation/check-fixture-provenance.sh`.

## Checks

- [ ] `make lint` green (pinned shellcheck + `bash -n`/`zsh -n` + markdownlint)
- [ ] `make test` green
- [ ] If `bootstrap.sh` changed: `./bootstrap.sh --dry-run` reviewed, and re-run twice
      to confirm it is still idempotent

## Notes

<!-- Load-order implications, follow-up sync, anything reviewers should know. -->
