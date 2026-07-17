# Release Runbook

The **exact commands**, in order, to cut a release anywhere in the fleet. This is the
hands-on companion to `RELEASE-STRATEGY.md` — that doc is the *policy* (what is
versioned, when, why); this is the *recipe* (what to type). When they disagree,
`RELEASE-STRATEGY.md` wins; fix this.

Four flows live here — three are independently versioned (Core, dotfiles-Windows, htpx);
the OS-repo rollout is the consumer side of the Core line, not its own version:

| Flow | Versioned thing | Trigger | Fans out to | Section |
| --- | --- | --- | --- | --- |
| **Core** | `dotfiles-core` (`core.version`) | `make release` + push tag | the 8 OS repos' `core/` | [1](#1-cut-a-core-release) |
| **OS-repo rollout** | not versioned (stamped `core.lock`) | merging the fan-out PRs | the live hosts (on bootstrap) | [2](#2-roll-a-core-release-out-to-the-os-repos) |
| **dotfiles-Windows** | `dotfiles-Windows` (own `vX.Y.Z`) | mirror-sync `nvim/`+`starship/` (auto-patch) **or** a manual CHANGELOG promotion + tag (minor/major) | the Windows host (on bootstrap) | [3](#3-cut-a-dotfiles-windows-release) |
| **htpx** | `htpx` (`CHANGELOG.md`) | push a CHANGELOG bump to `main` | `dotfiles-Kali` (`companion.lock`) | [4](#4-cut-an-htpx-release) |

These lines are independent and update different files, so they never collide: a Core
release bumps each OS repo's `core.lock`; an htpx release bumps Kali's `companion.lock`;
and `dotfiles-Windows` carries its own version, advanced **two ways** — an automatic patch when
the `nvim/`/`starship/` assets it mirrors from Core move, and a deliberate minor/major a human
cuts for host work (both flows in §3). It vendors no `core/` subtree.

---

## 1. Cut a Core release

Run these in a clean `dotfiles-core` checkout. `vX.Y.Z` is the new version; **pick the
bump first** with §1.0, then run the cut in §1.1 (see `core.version` for the current
number — the current major is what the `@vN` alias points at, e.g. `v3` while on `3.x`).

### 1.0 Pick the bump: major, minor, or patch

Choose by **blast radius on a host, not by how big the diff looks**. The canonical
policy is `RELEASE-STRATEGY.md` §2 ("SemVer, mapped to dotfiles"); this is the
operator-facing summary so you don't have to leave the runbook:

| Bump | `X.Y.Z` moves | Cut it when… | Concrete triggers |
| --- | --- | --- | --- |
| **PATCH** | `Z` → `Z+1` | a fix or doc change with **no interface change** | a bug fix; a zsh-plugin / nvim pin bump with no observable behavior change; a doc correction |
| **MINOR** | `Y` → `Y+1`, `Z` → `0` | **additive** and backward-compatible | a new zsh module, alias, function, or keybinding that **displaces nothing** a host already relies on |
| **MAJOR** | `X` → `X+1`, `Y`,`Z` → `0` | a host must **adapt** to keep working | reordering the load chain; removing/renaming a public alias, binding, or function; changing the `bootstrap.sh` symlink contract; dropping a `core.manifest` path |

When it's ambiguous, decide with these three:

- If a host that blindly re-bootstraps could **break, or lose a command it relied on**,
  it's **MAJOR** — even if the diff is a single line.
- If nothing a host already uses changes meaning, it's at most **MINOR** — even if the
  diff is large (a whole new module is still just additive).
- "Is this fix visible to a user?" is **not** the MAJOR test — a visible fix is still a
  **PATCH** as long as no interface is added, removed, or renamed.

Two consequences to remember before you type anything:

- **Flag a MAJOR loudly in the CHANGELOG.** It forces action on every OS repo at rollout
  (they must adapt), so the `[Unreleased]` → `[vX.Y.Z]` section should call the break out
  explicitly, not bury it under "changed".
- **The cut commands are identical for all three bumps except one step** — the moving
  `@vN` major-alias handling in §1.1 step 4. Read that callout; it's the only place major
  and minor/patch diverge mechanically.

### 1.1 Run the cut

```bash
# 0. Start from a clean, green, up-to-date main.
git checkout main && git fetch origin && git pull --ff-only origin main
make audit                          # the one gate — must be green before tagging

# 1. Stage the release (bumps core.version + promotes CHANGELOG [Unreleased], re-audits).
make release VERSION=X.Y.Z
git diff                            # sanity-check: only core.version + CHANGELOG heading moved

# 2. Commit + annotated tag locally (re-audits; does NOT push).
make tag

# 3. main is protected, so land the release COMMIT via a PR (merge commit, not squash).
git push origin HEAD:release/vX.Y.Z
gh pr create --base main --head release/vX.Y.Z --title "release vX.Y.Z"
#    ... review, let CI go green, then MERGE with a merge commit ...

# 4. After the PR merges, tag the MERGED tip and push the tags (keeps git describe clean).
#    The `vN` line is the ONE step that differs by bump type — see the callout below.
git fetch origin
git tag -fa vX.Y.Z origin/main -m vX.Y.Z
git tag -f  vN     origin/main          # vN = the major alias, e.g. v3 (v4 on a MAJOR)
git push origin vX.Y.Z ; git push -f origin vN   # ';' not '&&' — independent pushes
```

#### Step 4, by bump type — the moving `@vN` major alias

Every reusable workflow in the fleet pins its caller to `@vN` (currently `@v3`), and step 4
is where that alias moves. What you do with it depends on the bump you chose in §1.0
(policy: `RELEASE-STRATEGY.md` §"Pinning reusable workflows"):

- **PATCH or MINOR** — the major number is unchanged, so `vN` stays the **same** alias
  (e.g. `v3`). Step 4 as written force-advances it to the new tip, and every caller pinned
  `@v3` picks the change up automatically on its next run. **No caller edits.** This
  auto-fan-out of guard/bootstrap fixes is the whole reason the alias moves.
- **MAJOR** — you are minting a **new** major. In step 4, `vN` is the **new** alias (e.g.
  `v4`), created fresh at the merged tip (`git tag -f v4 origin/main && git push -f origin v4`).
  **Leave the previous alias frozen:** do *not* run the `vN` line against `v3` — advancing it
  would push the breaking change onto every caller still pinned `@v3`. Then bump the callers
  that should adopt the new major from `@v3` to `@v4` **by hand** — that fleet-wide `uses:`
  edit is the single intentional, reviewed change a MAJOR is meant to be, and it's tracked as
  part of rollout (§2), not this step.

> The `make tag` shortcut path handles the alias itself, safely for either case:
> `tag-release.sh` derives the alias from the version (`MAJOR="v${VERSION%%.*}"`), so a
> `v4.0.0` cut force-moves **`v4`** (creating it) and never touches `v3`. It does **not**,
> however, bump the fleet's callers from `@v3` to `@v4` — that hand edit is still yours on a
> MAJOR.

### What happens automatically after the tag

1. `release.yml` publishes the GitHub Release — the body is the curated `CHANGELOG.md`
   section for the tag (extracted with one awk pass), **not** git-cliff. (`make
   release-notes` is a separate git-cliff helper for manually *drafting* a body; it is
   not what CI publishes.)
2. `sync-fanout.yml` opens a `core.lock`-bump PR in every repo in `scripts/os-repos.txt`,
   each vendoring `vX.Y.Z` via `git subtree pull --squash`. **It opens PRs, never merges.**
   (Requires the `FLEET_SYNC_TOKEN` secret on `dotfiles-core`.)

Then continue to section 2 to roll it out.

> Shortcut: `make tag PUSH=1` tags and pushes in one step, but it tags the **pre-merge**
> commit and then needs a re-point (it prints the recipe). The steps above avoid that —
> prefer them.

---

## 2. Roll a Core release out to the OS repos

The fan-out from section 1 leaves one open PR per OS repo. Roll them out **canary-first**,
never all at once (per `RELEASE-STRATEGY.md`).

1. Merge **`dotfiles-MacBook`** first (the canary). Let it bake.
2. Then merge the remaining Linux/Role repos' `core.lock` PRs.
3. On each host, the change lands when you re-run `./bootstrap.sh` (or pull).

**If this was a MAJOR release,** the fan-out `core.lock` PRs are not the whole rollout: any
repo whose CI pins a reusable workflow at the old `@vN` also needs its `uses:` ref bumped to
the new major (`@v3` → `@v4`) — the deliberate caller edit from §1.1 step 4. `make fleet-drift`
won't surface this: it compares each repo's recorded `core.lock` / `nvim/.core-ref` provenance
against Core, not its workflow `uses:` pins — so finding the stragglers is a manual sweep
(e.g. `grep -rl 'uses:.*@v3' .github/workflows` across the repos in `scripts/os-repos.txt`).
PATCH/MINOR releases skip this entirely: the moving alias already carried them.

If an OS-repo PR's `links-only` job fails on a **mirror timeout** (e.g. openSUSE's OSS
CDN), just re-run the job — the prep step retries automatically. A genuinely broken
prep still fails loud. `dotfiles-Windows` is **not** in the subtree fan-out — it has its
own release line (section 3).

---

## 3. Cut a dotfiles-Windows release

`dotfiles-Windows` is standalone (no `core/` subtree, and it isn't vendored), so a release
**fans out to nothing** — but it **versions itself two ways**:

- **3a — automatic PATCH**, when a mirror-sync lands new `nvim/`/`starship/` content on `main`.
- **3b — a deliberate MINOR/MAJOR**, cut by a human for accumulated *host* work (the PowerShell
  profile & modules, Windows Terminal, the scoop/winget packages, `psmux`, the WSL bridge).

Because auto-tag's patch tags advance mechanically on every mirror-sync, the **tag line runs
ahead of the `CHANGELOG.md` headings** (e.g. tags at `v1.1.6` while the last `## [vX.Y.Z]`
heading is still `v1.1.0`). Host work only ever earns a patch from auto-tag until a human
promotes it — recognizing that moment, and reconciling the two lines, is what 3b is for.

### 3a. Automatic patch (mirror-sync)

Run in a clean `dotfiles-Windows` checkout (PowerShell):

```powershell
# 1. Mirror the shared Core assets. Pin an exact Core release for a reproducible sync
#    (recommended when rolling a Core release onto the host); omit -Ref to track main.
.\nvim-sync.ps1     -Ref vX.Y.Z      # nvim/ (includes lazy-lock.json)
.\starship-sync.ps1 -Ref vX.Y.Z      # starship/starship.toml

# 2. Review, then commit only if content actually moved.
git diff nvim/ starship/
git add nvim/ starship/ ; git commit -m "sync nvim/starship from Core vX.Y.Z"

# 3. Land on main (PR -> merge if protected) — the push triggers auto-tag.yml.
```

After the push, `auto-tag.yml` sees the new `nvim/`/`starship/` content and PATCH-bumps
Windows' own tag + Release (delegating to Core's reusable `auto-tag-call.yml@v3`). It is
idempotent (a no-op if HEAD is already tagged) and deliberately **skips** a
`.core-ref`-marker-only change, so a timestamp-only re-sync never cuts a spurious tag.

You usually don't run the sync by hand: the **`nvim-sync` and `starship-sync` bots**
(weekly, Tuesdays 08:00 UTC, plus `workflow_dispatch`) open a PR when Core's `nvim/` or
`starship/` actually changed — merging that PR is the whole release. Run the scripts
manually only to pull a specific Core release immediately (e.g. right after cutting one).

### 3b. Deliberate minor/major (host work)

`auto-tag.yml` **only ever produces a patch**, and it fires on pushes to `main` that touch
`nvim/`/`starship/` — **not** on a CHANGELOG commit or a tag push. There is no `release.yml`
on this repo, so a minor/major is a **fully manual** flow that nothing auto-publishes. Run in
a clean checkout (PowerShell):

```powershell
# 1. Decide the version. The repo's own routines REPORT (they never tag):
#      /release-readiness  -> go/no-go + recommended SemVer (meaningful host work vs mechanical churn)
#      /release-notes      -> drafts the CHANGELOG entry from Conventional Commits
#    Breaking host change -> major; a feat/perf -> minor; only fix/chore/sync -> patch (let 3a handle it).

# 2. Refresh the package lock so the release ships current pins (also clears the open
#    package-freshness issue). The generator REBUILDS the lock from scratch:
.\packages\Update-PackageLock.ps1 -DryRun    # preview, writes nothing
.\packages\Update-PackageLock.ps1            # regenerate packages.lock.json
#    Gotcha: versions are resolved via `winget export`, which OMITS an installed app it can't
#    map to a winget source (even though `winget install`/`upgrade` still see it via ARP) — so
#    that app is DROPPED from the new lock, not carried over at its old pin. Confirm the real
#    version with `winget list --id <id>` and re-add its one pin line, or `winget uninstall`
#    then `winget install --id <id> -e` to register the source so future re-pins capture it.
git diff packages/packages.lock.json         # review only — it lands with the CHANGELOG in step 4

# 3. Promote the CHANGELOG: move [Unreleased] under `## [vX.Y.Z] - <today>`, open a fresh
#    empty [Unreleased] above it, and curate the prose (surface behavior changes loudly, e.g.
#    the psmux warm/destroy-unattached flip). Do NOT fold a real nvim/starship sync into this
#    release: merging a sync fires auto-tag (3a) and publishes an intervening PATCH tag/Release
#    that races the manual tag below. If you need the latest Core assets, land them as a
#    separate 3a PR FIRST, let that auto-patch settle, then cut this release touching only
#    CHANGELOG.md + packages.lock.json.

# 4. Land the CHANGELOG + lock on main via PR (main is protected). Base the branch on the
#    LATEST origin/main so a stale checkout can't drop current commits or pull in unrelated
#    ones — `git switch -c` carries the working-tree edits from steps 2-3 forward:
git fetch origin
git switch -c release/vX.Y.Z origin/main
git add CHANGELOG.md packages/packages.lock.json
git commit -m "release vX.Y.Z"
git push -u origin release/vX.Y.Z
gh pr create --base main --head release/vX.Y.Z --title "release vX.Y.Z"
#    ... review, let CI go green, then MERGE ...

# 5. Cut the tag + Release BY HAND — auto-tag won't. The version must also clear the drifted
#    tag floor (if tags are at v1.1.6, the next deliberate tag is >= v1.1.7; a minor like
#    v1.2.0 clears it):
git fetch origin
git tag -a vX.Y.Z origin/main -m vX.Y.Z
git push origin vX.Y.Z
#    save the new CHANGELOG section to notes.md, then pass it via a FILE — the CHANGELOG's
#    backticks/quotes would be reinterpreted inside a double-quoted inline `--notes "..."` arg:
gh release create vX.Y.Z --title vX.Y.Z --notes-file notes.md
```

Then close the `release-readiness` / `release-notes` tracking issues for the cut version.

---

## 4. Cut an htpx release

Run in a clean `htpx` checkout. htpx versions itself from its `CHANGELOG.md`.

**Which bump?** htpx is a content corpus, so read SemVer as impact on its consumers —
`dotfiles-Kali` (which regenerates the marked `hacktheplanet` / `PURPLE-TEAM.md` blocks from
the entries via `gen-views.sh`, drift-gated by `companion.yml`) and anyone browsing with the
`htpx` picker:

- **PATCH** — an existing entry is corrected in place: a fixed or retargeted detection, a
  metadata/typo fix, a tightened query. No new entries, no format change. (The v2.4.0
  `### Changed` "asrep-probing-4771 retargeted" line is patch-shaped work.)
- **MINOR** — the corpus **grows** backward-compatibly: new red↔blue pairs, a new unpaired
  entry, a new tactic/technique covered. (v2.4.0's "+2 pairs, +1 recon entry" = minor.)
- **MAJOR** — a change Kali's regeneration or the `htpx` picker must **adapt** to: the entry
  frontmatter / `{{slot}}` format, the `gen-views.sh` marker contract, or the
  `entries/red|blue/` layout. These break the `companion.yml` drift-gate until Kali re-syncs,
  so flag them loudly.

```bash
git checkout main && git fetch origin && git pull --ff-only origin main
```

1. Edit `CHANGELOG.md`: move the `[Unreleased]` entries under a new dated heading and
   open a fresh empty `[Unreleased]` above it:

   ```text
   ## [Unreleased]

   ## [vX.Y.Z] - YYYY-MM-DD
   ### Fixed
   - ... (the entries that were under [Unreleased])
   ```

2. Land the bump on `main` (PR -> merge, like any change):

   ```bash
   git checkout -b release/vX.Y.Z
   git commit -am "docs(changelog): release vX.Y.Z"
   git push -u origin release/vX.Y.Z
   gh pr create --base main --head release/vX.Y.Z --title "release vX.Y.Z"
   #    ... merge ...
   ```

3. The push to `main` triggers `auto-tag.yml`, which tags `vX.Y.Z` and publishes the
   Release. `sync-fanout.yml` then opens a `chore(companion): sync htpx -> vX.Y.Z` PR
   against `dotfiles-Kali` (bumps `companion.lock` only — never `core.lock`).
4. Review and merge that dotfiles-Kali PR.

Requires the `FLEET_SYNC_TOKEN` secret on the **htpx** repo (write to dotfiles-Kali).
htpx is read with the built-in token, so `FLEET_SYNC_TOKEN` needs no htpx access.

### Backfill an already-released tag

The automatic fan-out resolves the tag from the **commit that triggered it**. To fan out
a tag whose release happened earlier (or whose fan-out failed at the time), use the manual
path instead of a re-run:

**Actions -> `sync-fanout` -> Run workflow -> `tag: vX.Y.Z`**

That path takes the tag from the input rather than from HEAD, so it works regardless of
where `main` is now.

---

## 5. Before relying on a new cross-repo workflow

Cross-repo workflows (`sync-fanout`, anything that clones/pushes/PRs another repo) only
take effect once on the **default branch** — GitHub reads `workflow_run` / `workflow_dispatch`
triggers from `main`, never from a feature branch. So they cannot be exercised by PR CI,
and bugs in them surface only at a real release.

After merging a new or changed cross-repo workflow, **dry-run it before depending on it**:

1. Trigger it manually against a **past** tag: Actions -> the workflow -> Run workflow ->
   `tag: <an-already-released-version>`.
2. Confirm it does the right thing (opens the expected PR, touches only the expected
   files). Close the dry-run PR if one was opened.
3. Only then cut the next real release that relies on it.

This catches the auth-scope, argument, and resolve-path bugs that PR CI cannot see.

---

## 6. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `tag-release.sh: tag vX.Y.Z already exists` | re-running a finished release | bump `core.version`, or delete the tag to re-cut |
| fan-out PR's `links-only` fails on `curl error 28` / `No provider of 'zsh'` | distro mirror timeout | re-run the job (prep retries 5x); not a code defect |
| `sync-fanout` skips with `'' is not a clean vX.Y.Z release tag` | triggered from a commit with no tag on it | use the manual backfill (section 4) with `tag: vX.Y.Z` |
| fan-out fails `could not read Username for 'https://github.com'` | a git op reading a private repo without auth | the read must be authenticated (built-in token for own repo, `FLEET_SYNC_TOKEN` for cross-repo) |
| fan-out aborts `core.lock differs ...` | an htpx sync touched Core | by design — htpx fan-out must never change `core.lock`; investigate the sync |
| `make tag` refuses: `no '## [vX.Y.Z]' heading` | `make release` wasn't run | run `make release VERSION=X.Y.Z` first |
| staged a release with `make release` but want to hold off (add more commits first) | changed your mind before committing | `make release` only edits two files (no commit, no tag), so `git checkout -- core.version CHANGELOG.md` fully undoes it — restoring the single `[Unreleased]` so later commits append to it. If you *also* ran `make tag`, first `git tag -d vX.Y.Z` then `git reset --hard HEAD~1` (confirm `git show --stat HEAD` is the release commit). If you already pushed the tag, also `git push origin :refs/tags/vX.Y.Z` |

For the policy behind all of this — cadence, canary order, why only Core is versioned —
see `RELEASE-STRATEGY.md`.
