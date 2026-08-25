# Changelog

All notable changes to this repo's own layer — the defensive role layer
(`detections/`, `defense/`, `docker/`, `install/`), `bootstrap.sh`, and the tooling
around the vendored `core/` subtree.

**Not** in scope: changes inside `core/`. That is a vendored copy with its own
changelog
([dotfiles-core](https://github.com/dotgibson/dotfiles-core/blob/main/CHANGELOG.md)).
A sync that bumps `core.lock` is worth a line here; the upstream contents are not.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**This file starts at the point it was added, and deliberately does not backfill.**
The repo has 69 tags, and every one of them is an automatic patch bump that
`auto-tag.yml` cut in response to a `core/**` push — so the tag history records *what
was vendored when*, not a maintained release line. Reconstructing 69 headings from it
would produce 69 lines of "Core was bumped", which is both untrue as a changelog and
already recorded in `core.lock`. `dotfiles-Offense`, this repo's mirror, reached the
same conclusion: 87 tags, no version headings, and a note saying why. Real entries go
under `[Unreleased]` from here.

## [Unreleased]

### Added

- **The repo hygiene surface: `Makefile`, `CONTRIBUTING.md`, `.editorconfig`,
  `.gitattributes`, and the PR/issue templates.** This repo and `dotfiles-Offense` are
  deliberate mirrors — equal CI weight at 14 workflows each, and Defense carries *more*
  tracked files — but Defense was the only repo in the fleet missing all of these at
  once.

  The `Makefile` is the one with immediate value: every gate here was already real and
  already scripted, but there was no front door, so reproducing CI locally meant reading
  `.github/workflows/` and reconstructing the command list by hand. It wires what
  exists — `tests/lint-shell.sh`, `tests/test-defense.sh`, the four `--check` drift
  gates, the methodology and validation-coverage gates, `lab-smoke.sh` — and reads
  `MARKDOWNLINT_VERSION` from the vendored Core pins so a local run matches CI exactly.

  **Offense's target list was not ported wholesale**, because that would have recreated
  in reverse the exact bug Offense's Makefile was written to fix: `core-sync`,
  `core-lock` and the `companion-*` targets name scripts this repo does not have (Core
  is pushed *into* here by `dotfiles-core`'s own `make sync`, and this repo vendors no
  htpx companion). They are absent rather than stubbed.

  `.gitattributes` is the one with teeth. `dotfiles-Arch/CLAUDE.md` documents what its
  absence costs when a repo is touched from Windows over a UNC share: a `.sh` that
  picks up CRLF gets a shebang of `…/env bash\r` and dies with *"bad interpreter"* —
  text that looks perfectly valid and that both `shellcheck` and `bash -n` accept. It
  also pins `*.rules`, `*.zeek` and `*.pcap`, which are this repo's product and are
  parsed by tools that are not uniformly CRLF-tolerant.

  Adding this file also makes Defense visible to `dotfiles-web`'s changelog feed, which
  derives from each repo's `CHANGELOG.md` and had been skipping this one for want of the
  file. (dotgibson/dotfiles-Defense#196)
