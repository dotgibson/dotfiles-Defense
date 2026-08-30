# Contributing to dotfiles-core

This repo is the **Core layer** — the config that is identical on every machine —
authored once here and vendored into each OS repo's `core/`.
A change here fans out to all nine OS repos, so the bar is: _is this truly Core,
and is it healthy?_

## Is it actually Core?

Before adding anything, run the README's test. It belongs here **only** if:

- it is **identical on every machine** (not OS-specific), **and**
- it is **not offensive/engagement** tooling.

Otherwise it lives elsewhere:

| If it changes when…                                               | It belongs in…                                              |
| ----------------------------------------------------------------- | ----------------------------------------------------------- |
| the **operating system** changes (pkg manager, paths, clipboard)  | the OS repo (`dotfiles-{MacBook,Fedora,Arch,…}`)            |
| **you as an operator** change (C2/wordlists; or detections/hunts) | `dotfiles-Offense` (offense) / `dotfiles-Defense` (defense) |
| neither — it's the same everywhere                                | **here**                                                    |

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

If you install luacheck yourself, **build it against an explicit Lua 5.4.** luacheck 1.2.0 (its
last release) cannot load under 5.5 at all — 5.5 made some locals const, tripping "attempt to
assign to const variable" inside luacheck's own source. `luarocks install luacheck` picks up
whatever Lua your `luarocks` was built for, and on this repo's own box that is mise's, which
`mise/config.toml` pins to 5.5 for the Neovim work. CI and the SessionStart hook each pin a 5.4
of their own for this reason.

A luarocks wrapper also `exec`s an **absolute** interpreter path, so it keeps answering
`command -v` long after the Lua it was built against is upgraded away — §4 probes
`luacheck --version` before linting so that reports as a broken toolchain rather than as a
defect in `nvim/` (#726).

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
- **Core owns portable shell logic once.** The mirror of the rule above, and the harder
  direction to notice: if you find the same portable block in two OS repos, that is a
  **Core** change, not two OS changes. §5c cannot see it — it scans for OS-specifics leaking
  into Core, not portable logic stranded outside it. `scripts/lib/common.sh ::
  _core_owned_block_hits` is the list of blocks already moved, and the reusable `lint`
  workflow fails a caller repo that grows one back.
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
6. Give the new file's top-level directory a bucket in `scripts/ci-classify.sh`
   (an unrecognised path fails closed to a full CI run), with a matching
   `_classify_is` line in `scripts/test-core.sh`. The classifier emits three axes —
   `shell`, `nvim` and `atuin` — and `atuin` is narrow on purpose: it gates the
   premise detector's hermetic self-test, the single most expensive thing the suite
   does, so only `scripts/`, `zsh/00-tools.zsh` and `atuin/` reach it. Widening it
   is a real cost on every push in the fleet.

   **§5c of `scripts/audit-core.sh` is deliberately NOT on this list.** Its scope is
   derived from `core.manifest` — the file says so at `scripts/audit-core.sh:583` —
   so a path added to the manifest in step 4 is scanned automatically. This step used
   to send you there to edit a hand-kept list; that list is gone, and looking for it
   wastes the one moment you were most likely to be careful.
7. For a **symlinked config**, update the three lists that step 5's link does not
   reach on its own. Nothing gates these, which is why they are enumerated here:
   - `scripts/test-core.sh` — the `_lr_d` fixture directory list for the link run.
     **This is the one that fails quietly.** Miss it and the source never lands in
     the sandbox, `blib_link` early-returns on a missing src
     (`lib/bootstrap-lib.sh:127-131`), and any assertion you add below passes
     vacuously. Nothing goes red.
   - `scripts/test-core.sh` — the grouped `_lr_is_link_to` assertions, plus the pass
     message that names them. Assert the destination bootstrap actually promises.
   - `dotfiles-MacBook/bootstrap.sh` — the `--uninstall` `dests` array, the only
     hand-maintained one in the fleet. Miss it and `--uninstall` removes one fewer
     thing than install creates, leaving a dangling symlink.
8. Keep the prose enumerations in `lib/bootstrap-lib.sh` in step with the link you
   added in step 5 — `:436` tells you to, and there are **three**, not one: the group
   list at `:310-311`, `blib_link_core`'s header at `:431-435`, and the `tools`
   section banner at `:510-511`.
9. `./scripts/audit-core.sh` — green before you push.
10. `./scripts/sync-core.sh` to vendor it into every OS repo.

Steps 6–8 are a checklist rather than a gate on purpose, and it is worth knowing why:
the audit enforces `core.manifest` in both directions, but nothing can enforce "and
you also told the classifier, the fixture and the uninstall path about it". That makes
the accuracy of _this list_ load-bearing — a checklist that names a retired list and
omits a silently-failing one inverts its own value.
