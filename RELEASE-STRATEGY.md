# Release Strategy

How and when changes ship across the ten-repo fleet. This is the **policy
layer** that ties together the machinery already in the tree — `core.version`,
`scripts/release.sh`, `scripts/sync-core.sh`, the `core.lock` provenance stamp,
`scripts/fleet-drift.sh`, and the weekly bots — into one cadence, one tagging
discipline, and one safe-rollout path. When a rule here drifts from `README.md`
or `CONTRIBUTING.md`, those win; fix this.

> Looking for the **exact commands** to cut a release (Core, the OS-repo rollout, or
> htpx)? See **`RELEASE-RUNBOOK.md`** — the step-by-step recipe. This doc is the *why*
> and *when*; the runbook is the *what to type*.

The short version: **Core is the only thing that is versioned and released. The
OS and Role repos are consumers that pull a named Core version when they choose
to.** Releases are cut on a predictable monthly rhythm (plus out-of-band for
security), tagged `vX.Y.Z`, proven green by the audit before they fan out, and
rolled out canary-first so a bad Core can never reach all eight operating
systems at once.

## 1. The unit of release

The fleet is not eight things that each version themselves. It is **one
versioned thing (Core) vendored into thin per-OS consumers**:

- **Core** (`dotfiles-core`) carries the SemVer in `core.version` (currently
  `1.2.0`). It is the single source of truth, vendored into each OS repo's
  `core/` via `git subtree`. A defect here fans out N-way, so Core is the thing
  that earns a version number, a tag, and a changelog.
- **OS-native repos** (`dotfiles-{MacBook,Fedora,Arch,openSUSE,Alpine,Gentoo}`)
  and **Role repos** (`dotfiles-Kali`, `dotfiles-Defense`) are **not**
  independently versioned. They are stamped with the Core they carry — the
  generated `core.lock` records `core_version`, `core_sha`, and `core_branch` —
  so "what Core does Alpine run?" is answerable offline without a release
  number of its own.
- **`dotfiles-Windows`** is the exception: it vendors **no** `core/` subtree (so no
  `core.lock`) and **carries its own `vX.Y.Z`** — advanced by an automatic patch when
  the `nvim/`/`starship/` assets it mirrors from Core move, or by a deliberate
  minor/major a human cuts for host work (see the runbook §3).
- **`dotfiles-web`** documents the system; it ships when its content is true,
  not on this cadence.

This is deliberate. Versioning eight repos independently would multiply the
release surface eightfold for no benefit: the OS layer is a thin shim over
package manager, clipboard, and paths, and most of what changes a host is Core.

## 2. Release cadence

Three tracks moving at three speeds. Conflating them is what causes cascade
failures — keep them separate.

| Track | Trigger | Frequency | Tagged | Blast radius |
| --- | --- | --- | --- | --- |
| Continuous integration | every merge to `main` | per-merge | no | none until synced |
| Routine pin bumps | the freshness bot | weekly (Mon 06:00 UTC) | no | one PR to review |
| Tagged Core release | calendar + on-demand | monthly + security | `vX.Y.Z` | the whole fleet |

### Continuous (per-merge)

`main` is always green: `ci.yml` runs the audit on every push and PR, and the
fan-out gate in `sync-core.sh` refuses to vendor a red tree. Merging to `main`
is **not** a release — nothing reaches a host until a sync happens. This is what
lets you commit freely without fear of breaking a live machine.

### Routine (weekly, automated)

The weekly bots **report first** — they open a PR or a deduped issue and never
vendor anything on their own. They run on two offset slots so the reviews don't
all land at once:

- **Mondays 06:00 UTC** — `freshness.yml` (rolls the zsh-plugin + nvim pins
  forward as a PR) and `fleet-drift.yml` (flags any OS repo lagging Core's tip).
- **Tuesdays 07:00 UTC** — `claude-routines.yml` (`/doc-audit` + `/tool-scout`),
  deliberately offset a day behind freshness so its findings issue lands after
  that week's pin PR.

Plugin and nvim pin bumps are batched into the weekly freshness PR, never landed
per-tool, so the fleet sees one reviewed step a week rather than a trickle of
unaudited churn. A quiet week means nothing needs doing.

### Tagged releases (monthly + security)

Cut a tagged Core release **once a month** on a fixed day (e.g. the first
Monday, after that week's freshness PR has merged and baked on `main`), plus
**out-of-band** for a security fix or a regression that is actively biting a
host.

Why monthly is the sweet spot for an eight-OS fleet:

- **Weekly tags** would 8× the fan-out churn — every OS repo re-syncs, every
  host re-bootstraps — for changes that are mostly already on `main` and
  available to anyone who wants them early.
- **Quarterly tags** let Core drift far enough from the synced fleet that a
  sync becomes a big, risky catch-up instead of a small, boring one.
- **Monthly** keeps each release small enough to reason about and roll back,
  while giving the weekly pin bumps time to bake on `main` before they are
  frozen into a tag.

### SemVer, mapped to dotfiles

`release.sh` enforces clean `X.Y.Z` (no pre-release suffix) and a matching dated
CHANGELOG heading. Choose the bump by **blast radius on a host**, not by how big
the diff looks:

- **MAJOR** — a breaking change a host must adapt to: reordering the load chain,
  removing or renaming a public alias / binding / function, changing the
  `bootstrap.sh` symlink contract, or dropping a manifest path. These force
  action on every OS repo; flag them loudly in the CHANGELOG.
- **MINOR** — additive and backward-compatible: a new zsh module, a new alias,
  a new function, a new keybinding that displaces nothing.
- **PATCH** — a fix or doc change with no interface change, including a pin bump
  that does not change observable behavior.

## 3. Repository architecture

The question "`common/` + OS subdirectories, or heavy conditionals in one
`.zshrc`?" has a third answer, and it is the one already in use because the
first two break at eight-OS scale.

### Why the two common approaches fail here

- **One `.zshrc` full of `case "$OS"` branches.** Every host parses every other
  host's logic; BSD-vs-GNU coreutils, systemd-vs-OpenRC, and Windows paths do
  not reduce to clean conditionals; and a single typo in the shared file breaks
  *all* hosts at once. The blast radius is the whole fleet for every edit.
- **`common/` + `os/<name>/` in one monorepo.** Better — but every host still
  clones every OS's files, there is no per-OS release isolation (you cannot pin
  Alpine to an older shared version without pinning everyone), and Windows
  (PowerShell, not a Unix tree) does not fit the layout.

### The model in use (recommended)

A **three-layer, multi-repo model with Core vendored by `git subtree`**:

| Layer | Lives in | Owns |
| --- | --- | --- |
| **Core** | `dotfiles-core`, vendored into each OS repo's `core/` | zsh modules, tmux, nvim, git, starship — identical everywhere |
| **OS-native** | one repo per OS | package manager, clipboard, paths, bootstrap |
| **Role** | `dotfiles-Kali` (offensive), `dotfiles-Defense` (blue) | engagement / detection tooling layered on an OS |

Each OS repo therefore carries **only** vendored Core plus its own thin OS layer
— not the other seven OSes' files. The zsh **load order is the contract**
(`tools → ui → options → history → aliases → git → functions → fzf → bindings →
plugins → op → maint → update → os → local`); OS and Role repos extend it by
appending stages (`… os offensive local` on Kali, `… os defense local` on
Defense), never by editing Core.

Why `git subtree` rather than a submodule: the vendored `core/` is present
offline with no second clone step, its history is squashed into the OS repo, and
the "edit upstream, then `make sync`" discipline is enforced by the audit and
`fleet-drift.sh`. The cost — never hand-edit `core/` in an OS repo — is the same
rule the whole system already lives by.

## 4. Safe deployment: testing Arch without breaking Alpine or macOS

This is the core safety question, and the architecture answers most of it *by
construction* before any tagging discipline is added.

### A change "meant for Arch" is one of two things

1. **OS-specific** (a `pacman`/AUR tweak, an Arch path). It belongs in
   `dotfiles-Arch`'s own `os/` layer and goes in **no** Core release. Alpine,
   macOS, and the rest literally never see it — they vendor Core, not each
   other's OS layers. This is total isolation for free; it is also the "is it
   Core?" test doing its job. **If a change is not identical on every machine,
   it is not Core, and it cannot reach another OS.**
2. **Actually Core** (identical everywhere). Then it is *supposed* to reach all
   eight — so the safety you want is not isolation but a **staged rollout** with
   a rollback per OS, below.

### Why a host cannot be broken behind your back

A Core change reaches a live host only after **three independent opt-in gates**,
in order. Core never pushes to a machine:

1. It is merged and **tagged** in `dotfiles-core` (and `release.sh` + the
   `sync-core.sh` gate both require a green audit first).
2. The target OS repo **pulls** it (`git subtree pull` / `make sync`) and
   commits the new `core.lock`.
3. The host **re-bootstraps or re-sources** to pick up the new files.

Skip any one and the host stays on what it had. An Alpine container that never
runs step 2 is unaffected by anything you tag, forever.

### Pin OS repos to a tag, not to `main`

Today `core.lock` records a `core_sha` on `main` — meaning "whatever `main`
happened to be at sync time." Tighten this so each OS repo vendors a **named
tag**:

```sh
# in an OS repo, adopt a specific Core release rather than main's tip
git subtree pull --prefix=core <core-remote> v1.3.0 --squash
```

Now "what Alpine runs" is a frozen, named version, and rolling one OS back is
just pulling the previous tag there — it touches no other repo. `sync-core.sh`
stamps the release into each `core.lock` as a `core_tag` field (`git describe`
of the vendored commit), so the named version is recorded automatically and
`make fleet-drift` reports against it, not just the SHA.

### The staged rollout for a Core release

1. **Tag** `vX.Y.Z` in Core. The audit is green (enforced by `release.sh` and
   the fan-out gate).
2. **Canary** into one low-risk repo first — `dotfiles-MacBook` (the reference
   implementation) or a throwaway Alpine/Arch container. Bootstrap it and smoke
   test: shell starts, load order intact, no broken bindings.
3. **Bake** on the canary for a few days. Real use surfaces what CI cannot.
4. **Fan out**: on release, the `sync-fanout` workflow
   (`.github/workflows/sync-fanout.yml`) opens a `core.lock`-bump PR against every
   repo in `scripts/os-repos.txt`, pinned to the released commit — so the fan-out is
   now "merge the PRs," canary first, instead of a remembered `make sync` (which
   still works locally). `make fleet-drift` confirms every repo converged on the new
   tag. The PRs are opened, never auto-merged — the opt-in gates above are intact.
5. **Roll back per OS** if needed: re-pull the previous tag in just the affected
   repo. Alpine rolling back to `v1.2.0` does not touch macOS on `v1.3.0` — the
   repos are independent consumers.

### Pinning reusable workflows (the `@vN` policy)

The fleet's reusable workflows (`bootstrap-test.yml`, `core-integrity-call.yml`) are
called cross-repo from each OS repo. Pinning the caller's `uses:` ref trades off two
things: **determinism** (a mutable `@main` can change a repo's CI with zero diff in
that repo — a real supply-chain concern for an *integrity* guard) against
**auto-propagation** (a guard/bootstrap improvement should reach every repo without
hand-bumping N callers).

The policy resolves both with a **moving major tag**: callers pin to **`@vN`** (e.g.
`@v2`), and `tag-release.sh` force-advances `vN` to each new `vN.x` at release time
(alongside the immutable `vX.Y.Z` tag). So a caller's behavior can change **only via a
Core release** (deterministic between releases), yet patch/minor guard fixes still fan
out automatically; a major bump is the one intentional, reviewed caller edit. This is
GitHub's own recommended pattern for reusable workflows.

- **Authoring:** new callers use `@vN` for the current major (not `@main`, not a bare SHA).
- **Bootstrapping a major:** `vN` is created/advanced by `make tag PUSH=1`; the very first
  `vN` can also be stamped by hand (`git tag -f vN vN.0.0 && git push -f origin vN`).
- **Trade vs. exact-SHA pinning:** a SHA is maximally deterministic but needs a manual
  caller bump fleet-wide on every change — rejected as too high-churn for a first-party,
  same-owner reusable workflow.

### What CI must prove before a tag

The pre-tag gate is already most of the way there and should be treated as
release-blocking:

- `ci.yml` runs the full audit on push and PR across four userlands: the
  **Ubuntu** (glibc) and **macOS bash 3.2** matrix legs, plus container legs for
  **Alpine** (`audit-alpine` — musl + busybox) and **Arch** (`audit-arch` — the
  rolling GNU toolchain, newer than Ubuntu LTS). So a Bashism that breaks the
  Mac, a busybox-applet assumption that breaks Alpine, or a coreutils deprecation
  that will bite Arch first is all caught before a tag.
- `bootstrap-test.yml` exercises the bootstrap path.
- The behavioral suite (`test-core.sh`) checks load order and function units
  cross-shell.

## 5. Checklists

### Cut a Core release

```sh
make release VERSION=X.Y.Z   # bumps core.version, promotes CHANGELOG, runs the audit
git diff                     # review the two-file change
make tag PUSH=1              # commit + annotated tag vX.Y.Z, re-run the audit, push
```

Pushing the tag triggers `.github/workflows/release.yml`, which publishes the
**GitHub Release** automatically — its body is the curated `CHANGELOG.md` section
for `vX.Y.Z` (the workflow refuses to publish if the tag doesn't match
`core.version` or the section is missing). `make release-notes` (git-cliff) stays
available for drafting a body by hand if you want to edit it before publishing.

### Tag baseline

The fleet already carries annotated tags `v1.0.0`–`v1.2.0`, so there is no
one-time adoption step — `core.version` (`1.2.0`) matches the latest tag, and the
next release just runs the checklist above to cut `v1.2.1` / `v1.3.0`. The
`core_tag` provenance only appears in each `core.lock` on the next `make sync`,
which is when `git describe` first has a tag to resolve against the vendored
commit.

### Fan out and verify

```sh
make sync          # vendor the tagged Core into every OS repo (green audit required)
make fleet-drift   # confirm no repo lags the new tag
```

### Roll one OS back

```sh
# in the affected OS repo only
git subtree pull --prefix=core <core-remote> v<previous> --squash
```

## 6. Tooling that backs this policy

The pieces this policy leaned on are now wired:

- **`core_tag` in `core.lock`.** `sync-core.sh` stamps `git describe` of the
  vendored commit into each repo's `core.lock`, and `make fleet-drift` surfaces
  it — so the dashboard reports drift against named releases, not just SHAs.
- **Per-OS container smoke in CI.** `ci.yml` runs the shell-scope audit on
  **Alpine** (`audit-alpine`, musl + busybox) and **Arch** (`audit-arch`, the
  rolling GNU toolchain) on top of the Ubuntu + macOS matrix — closing the
  "passed on Fedora, assumed elsewhere" gap before a tag.
- **`make tag`.** `scripts/tag-release.sh` commits `core.version` + `CHANGELOG`
  and creates the annotated `vX.Y.Z` tag (re-running the audit gate), so
  `make release VERSION=X.Y.Z && make tag` is the whole cut end to end. Pushing
  stays opt-in (`make tag PUSH=1`).
- **Auto-published GitHub Release.** `.github/workflows/release.yml` fires on a
  `vX.Y.Z` tag push and publishes the Release, its body taken from the curated
  `CHANGELOG.md` section — gated on the tag matching `core.version`.

### Where GitHub Releases come from (four paths)

Almost every tag becomes a **Release** automatically, by one of four routes — the
exception is a deliberate `dotfiles-Windows` minor/major, which a human tags and
releases by hand (last row). The automatic split is forced by GitHub's rule that
**a tag pushed by `GITHUB_TOKEN` cannot trigger another workflow** (anti-recursion),
so a CI-cut tag can't rely on a separate `on: push: tags` workflow:

| Repo | Tag cut by | Release created by | Notes source |
| ---- | ---------- | ------------------ | ------------ |
| **dotfiles-core** | you (`make tag` → push) | `release.yml` (`on: push: tags`) — fires because *you* pushed the tag | curated `CHANGELOG.md` section |
| **OS repos** (×8) | `auto-tag.sh` in CI on a `core/**` fan-out | `auto-tag.sh --release`, **in the same job** (the token-pushed tag can't trigger `release.yml`) | grouped Conventional-Commit notes (`auto-tag.sh` → `--notes-file`; `--generate-notes` only as the empty-range fallback) |
| **dotfiles-Windows** — auto patch | `auto-tag.sh` in CI on an `nvim/`/`starship/` sync | same as OS repos (calls `auto-tag-call.yml@v3`) | grouped Conventional-Commit notes (same `auto-tag.sh` `--notes-file` path) |
| **dotfiles-Windows** — deliberate minor/major | **you**, by hand for host work (`git tag` → push) | **you** (`gh release create --notes-file`) — auto-tag only ever patches and never fires on a CHANGELOG commit or a tag push | curated `CHANGELOG.md` section |

So: Core releases read like the changelog; OS-repo and Windows **auto-patch** releases get
grouped Conventional-Commit notes generated by `auto-tag.sh` (they carry no curated per-tag
CHANGELOG of their own), and those auto
paths are idempotent and need no manual tag/Release push. The one exception is a **deliberate
`dotfiles-Windows` minor/major** for accumulated host work: there is no `release.yml` on that
repo, so a human promotes its `CHANGELOG.md` and cuts the tag + Release by hand. Both Windows
flows are in `RELEASE-RUNBOOK.md` §3.

### Still worth doing

- **Promote `audit-arch`/`audit-alpine` to required checks** in branch
  protection so a regression on either userland blocks a merge to `main`. This is
  a GitHub **repo setting**, not a file: Settings → Branches → the `main` rule →
  *Require status checks to pass* → add `audit-arch` and `audit-alpine`.
