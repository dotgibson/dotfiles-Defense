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

Run these in a clean `dotfiles-core` checkout. `vX.Y.Z` is the new version — bump the
**minor** for features, the **patch** for fixes only (see `core.version` for current).

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
git fetch origin
git tag -fa vX.Y.Z origin/main -m vX.Y.Z
git tag -f  vN     origin/main          # vN = the major alias, e.g. v2
git push origin vX.Y.Z ; git push -f origin vN   # ';' not '&&' — independent pushes
```

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

For the policy behind all of this — cadence, canary order, why only Core is versioned —
see `RELEASE-STRATEGY.md`.
