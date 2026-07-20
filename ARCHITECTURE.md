# Architecture

The strategic view of the dotfiles system: how the layers are drawn, how Core
fans out to every machine, and why the model is built this way. For the
operational detail (how to consume Core, the manifest contract, the audit gate)
see [`README.md`](README.md) and [`CONTRIBUTING.md`](CONTRIBUTING.md); this
document is the altitude above them.

## The problem this solves

A dotfiles setup that serves more than one machine eventually faces the same
fork in the road: either every machine keeps its **own copy** of the shared
config (and they drift), or the shared config is **centralized** (and you fight
submodules, or collapse everything into one unportable monorepo).

This system centralizes — but vendors the result so a clone is self-contained.
The shared config is authored once, in `dotfiles-core`, and physically copied
into each machine repo via `git subtree`. There is no N-way reconciliation, no
`git submodule update --init`, and no per-machine drift to chase after the fact.

## The three-layer model

Every file in the fleet has exactly one home, decided by a single question: what
does this change *with*?

| Layer         | Lives in                                              | Changes with         | Examples                                                        |
| ------------- | ----------------------------------------------------- | -------------------- | --------------------------------------------------------------- |
| **Core**      | `dotfiles-core`, vendored into each OS repo's `core/` | nothing — identical  | zsh modules, tmux base, Neovim, git, starship, mise             |
| **OS-native** | one repo per platform                                 | the operating system | package manager, paths, clipboard backend                       |
| **Role**      | `dotfiles-Kali` (red) · `dotfiles-Defense` (blue)     | you as an operator   | offensive engagement tooling · defensive detection/hunt tooling |

The boundary rule, stated as a test:

- If it changes when the **operating system** changes, it is **OS-native** — it
  belongs in the platform repo.
- If it changes when **you as an operator** change, it is **Role** — it belongs
  in a role repo (`dotfiles-Kali` for offense, `dotfiles-Defense` for defense).
- Everything left over is **Core**, and it lives in `dotfiles-core` only.

Core is not "the Neovim config" or "the shell config" — it is the entire
machine-independent surface: the zsh module chain, the tmux base, Neovim, git,
starship, and mise, taken together.

## The fleet

Ten repositories make up the configuration system (one Core plus nine machine
repos), with `dotfiles-web` as an eleventh public repo that documents the system
rather than configuring a machine.

| Repository          | Layer            | Vendors `core/`? | Notes                                                      |
| ------------------- | ---------------- | ---------------- | ---------------------------------------------------------- |
| `dotfiles-core`     | Core             | n/a (source)     | Single source of truth; fanned out to the rest.            |
| `dotfiles-MacBook`  | OS-native        | yes              | Homebrew; reference implementation, synced first.          |
| `dotfiles-Fedora`   | OS-native        | yes              | dnf; the template the other Linux repos stamp from.        |
| `dotfiles-Arch`     | OS-native        | yes              | pacman + AUR, rolling release.                             |
| `dotfiles-openSUSE` | OS-native        | yes              | zypper; Tumbleweed (`dup`) + Leap (`up`) aware.            |
| `dotfiles-Alpine`   | OS-native        | yes              | musl + busybox + doas; the lean outlier.                   |
| `dotfiles-Gentoo`   | OS-native        | yes              | emerge from source; USE flags, full atoms.                 |
| `dotfiles-Kali`     | Role / offensive | yes              | Core + apt OS layer + the offensive role layer.            |
| `dotfiles-Defense`  | Role / defensive | yes              | Core + OS layer + the defensive detection/hunt role layer. |
| `dotfiles-Windows`  | Native host      | no               | pwsh / scoop / winget; Core is reimplemented, not ported.  |
| `dotfiles-web`      | Showcase (none)  | no               | Astro docs site; the system's public face.                 |

The canonical Core-vendoring fleet is `scripts/os-repos.txt` — eight repos.
`dotfiles-Windows` is deliberately absent from it: its host layer is replicated
from scratch in PowerShell rather than ported one-to-one from the Unix Core, so
it carries no vendored `core/` subtree and `sync-core.sh` must never fan out into
it. (`dotfiles-Debian` was once planned but is no longer pursued — the Debian
family is covered by `dotfiles-Kali`'s apt OS layer.)

## Vendoring topology

Core flows in one direction — authored here, copied out:

```text
                    ┌──────────────────────┐
                    │     dotfiles-core    │  single source of truth
                    │  (core.manifest =    │
                    │   the contract)      │
                    └──────────┬───────────┘
                               │  git subtree pull --prefix=core … --squash
        ┌──────────┬───────────┼───────────┬──────────┬──────────┐
        ▼          ▼           ▼           ▼          ▼          ▼
   MacBook     Fedora       Arch      openSUSE     Alpine     Gentoo
   (+ Kali and Defense, which each stack a Role layer — offensive / defensive — on top of an OS layer)

   dotfiles-Windows  ──  no subtree; Core reimplemented natively in PowerShell
```

Each machine repo vendors Core under `core/` once:

```bash
git subtree add --prefix=core https://github.com/dotgibson/dotfiles-core main --squash
```

After a Core change, one helper fans it out to the whole fleet:

```bash
./scripts/sync-core.sh            # subtree-pull main into every os-repos.txt target
./scripts/sync-core.sh --dry-run  # preview, change nothing
```

Because the subtree squash records the exact Core commit, a tagged clone of any
OS repo carries the precise Core it was tested with — the human-readable SemVer
lives in `core.version` and is vendored alongside it so a machine can report
which Core it runs.

The cardinal rule that follows from this topology: **never edit a vendored
`core/` tree in an OS repo.** It is a copy and is overwritten on the next sync.
Fix Core here, then fan it out.

## Load order is load-bearing

The zsh fragment chain is sourced in one canonical order, declared in
`core.manifest` and driven by `zsh/loader.zsh` — which globs the numbered
`NN-*.zsh` fragments in `$ZSH_CFG` and sources them by their `NN` prefix:

```text
00-tools → 05-ui → 10-options → 15-history → 20-aliases → 25-git → 30-functions
      → 35-fzf → 40-bindings → 45-plugins → 50-op → 55-maint → 60-update
      → 80-os → 85-<role> → 99-local
```

The order encodes real dependencies: `00-tools` initializes atuin and `35-fzf`
defines its widgets before `45-plugins` loads zsh-vi-mode (which fires the binding
hook); `10-options` runs `compinit` before `45-plugins` (fzf-tab and carapace need
it); `25-git` loads after `20-aliases` so its comprehensive git set is the single
source of truth. The chain ends with the OS layer (`80-os`), any role stage
(`85-*`), then `99-local`, so a machine can override Core last without editing it.
Bands: Core `00`–`69`, OS-native `70`–`84`, role `85`–`94`, host `95`–`99`. Do not
reorder casually.

## The one gate

`scripts/audit-core.sh` is the single definition of "Core is healthy" — manifest
drift in both directions, exec-bit assertions, shell and Lua syntax, shellcheck,
luacheck, markdownlint, and a behavioral test suite. CI, the pre-commit hook, and
`make audit` all call it. A red tree must never be vendored out, so it is green
before any sync.

```bash
make audit          # the full gate
make audit-changed  # only what the current diff touches
make sync           # fan Core out to every OS repo (after a green audit)
```

The manifest is the contract that the gate enforces: a file is Core **only** if
it is listed in `core.manifest`. Repo-meta and dev tooling (this document, the
other root docs, `.github/`, `.claude/`, `scripts/`) live in the audit's
allowlist instead — present in the repo, but never symlinked onto a machine.

## Why this model

- **Clone-and-go.** Subtree vendors the actual files, so a fresh clone of any
  machine repo just works — no submodule flags, no recursive init. These are
  public showcase repos people browse, so the first-run experience matters.
- **Author once, fan out.** A Core fix is written in one place and synced to
  every machine, instead of being hand-applied N times and drifting.
- **One home per file.** The boundary test means there is never a question of
  where a change goes — and never two copies of the same setting to keep aligned.
- **Honest by construction.** The manifest plus the audit gate make "what is
  Core" machine-checkable, so the docs and the code cannot quietly disagree.
