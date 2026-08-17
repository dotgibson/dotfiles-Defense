# Contributing to dotfiles-core

This repo is the **Core layer** — the config that is identical on every machine —
authored once here and vendored into each OS repo's `core/` via `git subtree`.
A change here fans out to all eight OS repos, so the bar is: _is this truly Core,
and is it healthy?_

## Is it actually Core?

Before adding anything, run the README's test. It belongs here **only** if:

- it is **identical on every machine** (not OS-specific), **and**
- it is **not offensive/engagement** tooling.

Otherwise it lives elsewhere:

| If it changes when…                                               | It belongs in…                                           |
| ----------------------------------------------------------------- | -------------------------------------------------------- |
| the **operating system** changes (pkg manager, paths, clipboard)  | the OS repo (`dotfiles-{MacBook,Fedora,Arch,…}`)         |
| **you as an operator** change (C2/wordlists; or detections/hunts) | `dotfiles-Kali` (offense) / `dotfiles-Defense` (defense) |
| neither — it's the same everywhere                                | **here**                                                 |

## The manifest is the contract

`core.manifest` is the canonical inventory of what Core ships. Adding a new Core
file means adding its path to `core.manifest` in the same change — the audit
enforces this in both directions:

- every path listed in the manifest must exist on disk, and
- every tracked file must be either listed in the manifest or in the audit's
  repo-meta allowlist (docs, CI config, dev tooling).

Repo-meta and dev tooling (this file, `LICENSE`, `.github/`, `scripts/sync-core.sh`,
`scripts/audit-core.sh`, …) are **not** vendored into OS repos, so they live in the
allowlist in `scripts/audit-core.sh` rather than the manifest.

## Run the audit before you push

`scripts/audit-core.sh` is the test suite. It checks manifest↔filesystem drift,
executable-bit invariants, shell syntax (`bash -n` / `zsh -n`), `luacheck`, nvim
module reachability (§4b), and `shellcheck`. It degrades gracefully — a missing
linter is skipped, not failed — so it runs on a bare box as well as in CI.

One section is worth knowing about when you touch `nvim/`: **§4b
(`scripts/nvim-reachability.sh`)** fails on a lua module nothing can require.
`core.manifest` lists `nvim/` as a _directory_, so the manifest↔filesystem check
auto-lists every path under it and cannot see an orphan — §4b is the backstop
instead. Adding a module under `lua/gerrrt/utils/` or at the top level means
something must `require()` it by name; a new `servers/<name>.lua` must be added to
the `servers` list in `servers/init.lua` (those are required dynamically, so that
list is the only evidence a static check has). `plugins/` is exempt — lazy imports
the whole directory.

```bash
./scripts/audit-core.sh           # full run
./scripts/audit-core.sh --quiet   # only skips/failures + summary
```

The same script runs in CI (`.github/workflows/ci.yml`) on every push and PR, so
local and CI share one definition of "healthy."

### Pre-commit (optional but recommended)

```bash
pip install pre-commit && pre-commit install
pre-commit run --all-files
```

This wires up `shellcheck`, the standard whitespace/shebang hooks, and the audit
itself at commit time. Two deliberate non-checks:

- **shfmt is not enforced.** The scripts here use an intentional compact
  one-liner style that `shfmt` would expand.
- **luacheck only runs via the audit** (from inside `nvim/`), because it
  discovers `.luacheckrc` by searching up from the working directory — run from
  the repo root it misses `nvim/.luacheckrc` and floods false "undefined vim"
  warnings.

## Conventions

- **Executable bits matter.** Anything invoked by path (the `bin/` clip shims, the
  `scripts/` dev tooling and `tmux/scripts/` popups, the maint runner) must be `+x`;
  the `zsh/*.zsh`
  modules are **sourced**, so they must stay non-executable. The audit asserts
  both, so a regression fails CI rather than reaching a machine.
- **Indentation** is 2-space across the tree (`.editorconfig`).
- **Keep OS-specific bits out.** Strip clipboard/paths/package-manager logic into
  the OS repo; Core stays portable. **[`PORTABILITY.md`](PORTABILITY.md) is the how** —
  the bash-3.2 floor, the BSD/busybox coreutils traps, and the shim pattern to reach an
  OS capability without naming a path. Read it before your first Core change; the boundary
  gate (`audit-core.sh` §5c) enforces it, and its scope is derived from `core.manifest`,
  so a file you add is checked the moment you list it.
- **Working in an OS repo instead?** [`VENDORING.md`](VENDORING.md) is the consumer-side
  contract: what `core/` and `core.lock` mean, which number band your file may claim, and
  how to send a fix back upstream.

## Commit messages

Use a [Conventional Commits](https://www.conventionalcommits.org/) prefix so the
log reads as a changelog and tooling can group it (Renovate already commits with
a `ci` prefix; see `renovate.json`):

```text
type(scope): short imperative summary

optional body explaining the why
```

Common types here: `fix`, `feat`, `test`, `ci`, `docs`, `chore`, `perf`. The
scope is the Core area touched — `zsh`, `nvim`, `tmux`, `audit`, `changelog`, etc.
A user-visible change should land in `CHANGELOG.md` under `[Unreleased]` in the
same commit.

## Adding a new Core file (checklist)

1. Confirm it's Core (the table above).
2. Drop it into the matching path.
3. Strip out anything OS-specific.
4. Add the path to `core.manifest`.
5. Wire the symlink into each OS repo's `bootstrap.sh` if it needs one — for a
   symlinked **config** (not a `zsh/` module) that means the matching group in
   `blib_link_core` (`lib/bootstrap-lib.sh`), which every bootstrap sources.
6. Give the new file's top-level directory a home in the two path lists that fan
   out from it: the Core⇄OS boundary scan in `scripts/audit-core.sh` (§5c — a
   vendored config gets no OS-absolute paths either) and a bucket in
   `scripts/ci-classify.sh` (an unrecognised path fails closed to a full CI run),
   with a matching `_classify_is` line in `scripts/test-core.sh`.
7. `./scripts/audit-core.sh` — green before you push.
8. `./scripts/sync-core.sh` to vendor it into every OS repo.
