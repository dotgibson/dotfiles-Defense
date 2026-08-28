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
| **Role**      | `dotfiles-Offense` (red) · `dotfiles-Defense` (blue)  | you as an operator   | offensive engagement tooling · defensive detection/hunt tooling |

The boundary rule, stated as a test:

- If it changes when the **operating system** changes, it is **OS-native** — it
  belongs in the platform repo.
- If it changes when **you as an operator** change, it is **Role** — it belongs
  in a role repo (`dotfiles-Offense` for offense, `dotfiles-Defense` for defense).
- Everything left over is **Core**, and it lives in `dotfiles-core` only.

Core is not "the Neovim config" or "the shell config" — it is the entire
machine-independent surface: the zsh module chain, the tmux base, Neovim, git,
starship, and mise, plus the smaller configs that are equally identical everywhere
(atuin, lazygit, jujutsu, the seeded sesh starter, the stock-vim fallback, and the
shared bash libs), taken together. `core.manifest` is the exhaustive list; this
sentence is the shape, not the inventory.

`PORTABILITY.md` is the companion rule set: once something *is* Core, that document
defines what it may assume about the machine it lands on. `VENDORING.md` is the same
contract read from the consuming OS repo's side.

### The deliberate exception

The test above is absolute, so the one place Core knowingly departs from it is named
here rather than left to be rediscovered as drift:

- **`zsh/55-maint.zsh`** — the scheduler control surface, and what is left of it is now
  small and time-boxed. Since #665 the scheduler itself and the directory its unit lives in
  are **declared** (`SCHEDULER`, `SCHEDULER_UNIT_DIR`), so `~/Library/LaunchAgents` no
  longer appears at the six call sites it used to — it survives only in the built-in
  fallback for a box that has not declared yet. `audit-core.sh` §5c's exception now covers
  that one block, and retires with it in #667.

  The launchd plist and the systemd unit **templates** stay in Core deliberately, and are
  not the exception. They are portable text parameterised by paths, selected by
  `_maint_scheduler` — the correct cross-OS shape. Pushing them into the OS repos would put
  one systemd unit in seven copies with no owner, which is the hand-maintained N-way drift
  `VENDORING.md` records as the #449 failure. What belongs to the OS layer is *where* the
  unit goes, not *what it says*.

**Both exceptions are now scheduled for demolition in the same change (#667)**, which is
the point of the declaration: what is left in Core is a stopgap for boxes that have not
declared, not a standing carve-out.

**There used to be a second, larger one**, and retiring it is what `os.capabilities` was for.
`zsh/60-update.zsh` — the `up` verb — knew how seven package managers count and apply
updates, including a `grep -qi tumbleweed /etc/os-release` to choose `zypper dup` over
`zypper up`. The defence was that `up` is **one verb with N backends**, structurally
identical to `bin/clip`, and that every machine having the same muscle memory was worth
the cost. The defence of the *verb* was right and still holds; the defence of the
*implementation* expired, because one verb with N backends is what a dispatch table is
for. Since #664 the verb is a dispatcher: it resolves what to run through `_pkgup_verb`
from the OS layer's `os.capabilities` declaration, and the backends belong to the layer
that changes when the OS does.

Two things about that are worth knowing rather than rediscovering:

- **Core still carries built-in defaults**, one table at the top of `zsh/60-update.zsh`
  in the declaration's own `KEY=value` shape. It is a stopgap with a demolition date:
  #667 authors the nine declarations that replace it, and it is deleted in the same
  change. Until then it is what every box actually runs, because no repo has declared yet.
  It is data in one marked place rather than control flow through five `case` statements,
  and each row is the transcription source for the repo that will replace it.
- **The line between interactive and unattended apply has not moved.** `60-update.zsh`
  never applies unattended — `up` is a verb you run. Scheduled apply lives one file over,
  in `maint/dotfiles-maint.sh`, and is **opt-in and deliberately narrowed**: off unless
  `MAINT_SYSTEM_UPGRADE=1`, and even then refused on Kali (engagement boxes) and on
  Arch/Gentoo (rolling distros that must not upgrade unattended). That file dispatches
  through the same declaration in #665; what Core will not do, either way, is apply
  *by default*.

## The fleet

Eleven repositories make up the configuration system (one Core plus ten machine
repos), with `dotfiles-web` as a twelfth public repo that documents the system
rather than configuring a machine.

| Repository          | Layer            | Vendors `core/`? | Notes                                                      |
| ------------------- | ---------------- | ---------------- | ---------------------------------------------------------- |
| `dotfiles-core`     | Core             | n/a (source)     | Single source of truth; fanned out to the rest.            |
| `dotfiles-MacBook`  | OS-native        | yes              | Homebrew; reference implementation, synced first.          |
| `dotfiles-Fedora`   | OS-native        | yes              | dnf; the template the other Linux repos stamp from.        |
| `dotfiles-Arch`     | OS-native        | yes              | pacman + AUR, rolling release.                             |
| `dotfiles-Debian`   | OS-native        | yes              | apt; Ubuntu 24.04 LTS — the only frozen target.            |
| `dotfiles-openSUSE` | OS-native        | yes              | zypper; Tumbleweed (`dup`) + Leap (`up`) aware.            |
| `dotfiles-Alpine`   | OS-native        | yes              | musl + busybox + doas; the lean outlier.                   |
| `dotfiles-Gentoo`   | OS-native        | yes              | emerge from source; USE flags, full atoms.                 |
| `dotfiles-Offense`  | Role / offensive | yes              | Core + apt OS layer + the offensive role layer.            |
| `dotfiles-Defense`  | Role / defensive | yes              | Core + OS layer + the defensive detection/hunt role layer. |
| `dotfiles-Windows`  | Native host      | no               | pwsh / scoop / winget; Core is reimplemented, not ported.  |
| `dotfiles-web`      | Showcase (none)  | no               | Astro docs site; the system's public face.                 |

The canonical Core-vendoring fleet is `scripts/os-repos.txt` — nine repos.
`dotfiles-Windows` is deliberately absent from it: its host layer is replicated
from scratch in PowerShell rather than ported one-to-one from the Unix Core, so
it carries no vendored `core/` subtree and `sync-core.sh` must never fan out into
it.

`dotfiles-Debian` and `dotfiles-Offense` are both Debian-family and both use apt, which
is not duplication: `dotfiles-Offense` targets Kali, a *rolling* sid derivative, and
exists for the offensive role layer stacked on top, while `dotfiles-Debian` is a plain
OS-native layer for a *frozen* Ubuntu LTS. The freeze is the whole difference — it is why that
repo carries version floors and a large pinned-asset set that no rolling repo needs.

## Vendoring topology

Core flows in one direction — authored here, copied out:

```text
                    ┌──────────────────────┐
                    │     dotfiles-core    │  single source of truth
                    │  (core.manifest =    │
                    │   the contract)      │
                    └──────────┬───────────┘
                               │  make sync — core/ materialized at core_sha
     ┌────────┬────────┬───┴────┬────────┬────────┬────────┐
     ▼        ▼        ▼        ▼        ▼        ▼        ▼
  MacBook  Fedora    Arch    Debian  openSUSE  Alpine   Gentoo
   (+ Offense and Defense, which each stack a Role layer — offensive / defensive — on top of an OS layer)

   dotfiles-Windows  ──  no subtree; Core reimplemented natively in PowerShell
```

Each machine repo vendors Core under `core/` once — from a **released tag, never
`main`**. The automated fan-out pins every repo to the exact commit a release tag
points at, so a tree vendored from `main` is not a commit any `core.lock` would
record, and `core-integrity` reports the fresh subtree as TAMPERED:

```bash
git subtree add --prefix=core https://github.com/dotgibson/dotfiles-core refs/tags/v4 --squash
```

`refs/tags/v4` is the moving major alias — the latest release in the v4 line. Pin a
specific `vX.Y.Z` instead when you want the tree frozen at a known version.

That leaves the repo with `core/` but **no `core.lock`**, so stamp provenance from a
Core checkout before treating the repo as vendored (`sync-core.sh` is the only
sanctioned writer of that file):

```bash
CORE_BRANCH=refs/tags/v4 ./scripts/sync-core.sh dotfiles-<Distro>
```

After a Core change, the same helper fans it out to the whole fleet:

```bash
./scripts/sync-core.sh            # materialize main's tree into every os-repos.txt target
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
00-tools → 02-capabilities → 05-ui → 10-options → 15-history → 20-aliases → 25-git
      → 30-functions → 35-fzf → 40-bindings → 45-plugins → 50-op → 55-maint → 60-update
      → 80-os → 85-<role> → 99-local
```

The order encodes real dependencies: `02-capabilities` reads the OS layer's capability
declaration before any consumer (the earliest is `30-functions`), and sits inside the Core
band so every `CORE_PROFILE` loads it — `minimal`'s ceiling is 30, and a lean profile must
not silently lose the dispatch table; `00-tools` initializes atuin and `35-fzf`
defines its widgets before `45-plugins` loads zsh-vi-mode (which fires the binding
hook); `10-options` runs `compinit` before `45-plugins` (fzf-tab and carapace need
it — and so do the tool-native `gh`/`uv`/`ty` completions Core registers on the line
immediately after carapace, late enough that a tool's own completion still overrides
carapace's bridged one); `25-git` loads after `20-aliases` so its comprehensive git set is the single
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
