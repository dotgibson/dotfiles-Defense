# Changelog

All notable changes to **dotfiles-core** are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Core is the single source of truth vendored into nine repos by `scripts/sync-core.sh`,
which materializes `core/` at the exact commit it resolved (it stopped using
`git subtree pull` in #587, and stopped re-resolving the branch at vendor time in #556).
Every entry below is therefore a change those repos receive on their next sync —
this file is the human-readable record of _what_ a sync will bring, complementing
the SHA that `scripts/sync-core.sh` now prints. To cut a release, move the
`[Unreleased]` items under a new `## [vX.Y.Z] - YYYY-MM-DD` heading and tag the
commit (`git tag -a vX.Y.Z -m vX.Y.Z`).

## [Unreleased]

## [v4.19.0] - 2026-08-25

### Added

- **The CI floor now requires `timeout-minutes:` on every runner job — `require_job_timeout`.**
  Left unset, GitHub's default is **360 minutes**: six hours of a held runner and a live
  `GITHUB_TOKEN` for a job that hung on a prompt, a network stall, or a step that was
  tampered with.

  Unlike the rest of `scripts/modern-baseline.yml` this rule is **not** driven by a dated
  upstream deprecation, and the baseline comment says so plainly rather than dressing it up.
  The reason to encode it now is structural: Core owns all six `*-call.yml@v4` reusable
  workflows the fleet consumes, so the jobs the OS repos actually execute are defined here. A
  floor rule locks in a property currently held only by convention across 47 jobs — cheap
  while the fleet is at 47/47, expensive once someone lands job 48 without one.

  **Keyed on `runs-on:`, not on "every job."** A job that calls a reusable workflow (`uses:`
  at job level — there are 10, every one a `notify-failure-call`/`notify-web-call`) cannot
  legally carry `timeout-minutes`, so requiring it there would be a guaranteed false fire.
  Both directions are covered by fixtures in the existing hermetic `check-modern` harness:
  one job missing a timeout is caught while its declaring sibling is not, and a
  reusable-workflow call job does not fire.

  **No workflow edits — nothing was below the proposed floor.** Adopted at zero fix-first
  cost. (#707)

- **`tealdeer/config.toml` — the page cache nothing was refreshing.** `help` is a Core alias
  (`zsh/20-aliases.zsh`, `HAVE_TLDR`-guarded) and tealdeer is packaged across the fleet, but Core
  shipped no config for it and `maint/dotfiles-maint.sh` has no `tldr --update` step. Upstream's
  `auto_update` defaults to **false**, so the two facts compose into a gap nobody owned: on a
  fresh box `help ls` fails with _"page not found"_ until someone runs `tldr --update` by hand,
  and on an old box the pages rot silently. Three lines of `[updates]` fix both without touching
  the maintenance runner. `auto_update_interval_hours` is set to 168 rather than upstream's 720
  so the refresh tracks the weekly maintenance cadence instead of lagging a month behind it.

  **The file is deliberately conservative, and the reason is not the obvious one.** tealdeer
  1.9.0 (2026-08-24) made config parsing **error on unknown keys** (upstream #516); before that
  an unknown key was silently ignored. So the risk does not run the direction it first appears:
  a newer key is not what breaks an old build — an old build ignores it — but any key this file
  gets wrong is now a hard failure on every 1.9.0+ box, surfacing on **every** `tldr` invocation,
  which on this fleet means `help` stops working outright. Core is vendored to nine repos running
  whatever tealdeer their distro ships (`PORTING-MATRIX.md` ¹: Tumbleweed 1.8.0; Leap 16.x has no
  package at all), so nothing here is newer than 1.8.0 — and `updates.warn_cache_age`, which is
  1.9.0-only, is left out on purpose rather than by omission.

  Symlinked, not seeded: Core owns the file and it is identical everywhere, so `blib_link` is
  right and `blib_seed` (`sesh.toml`, `local.gitconfig` — files the user edits locally) is not.
  Wired into the existing `tools` group, so no new `BLIB_MODULES` entry. (#702)

- **The OS layer can now DECLARE its package-manager verbs instead of Core hardcoding
  them.** Core's own test (`CONTRIBUTING.md`) is _"if it changes when the OS changes, it is
  not Core"_ — and Core broke it **154 times**: 88 package-manager references in
  `zsh/60-update.zsh`, 49 in `maint/dotfiles-maint.sh`, 17 in `zsh/30-functions.zsh`,
  including a `grep -qi tumbleweed /etc/os-release` to choose `zypper dup` over `zypper up`.

  `ARCHITECTURE.md` defended that as _"one verb with N backends"_, and the defence of the
  **verb** is right — `up` belongs in Core so every machine has the same muscle memory. What
  expired is the defence of the **implementation**: one verb with N backends is what a
  dispatch table is for. The verb stays; the backends move to the layer that changes with
  the OS.

  An OS repo now authors `os/<os>.capabilities` — flat `KEY=value`, **read and never
  sourced**, so a per-repo file is not a code-execution surface in your login shell (the
  precedent and the reasoning are `scripts/tool-versions.env` and `scripts/setup.sh:23-26`).
  Values are multi-word command prefixes, which is why `blib_read_pkgs` could not be reused:
  it strips _all_ whitespace.

  - `zsh/02-capabilities.zsh` — a new Core fragment at **band 02** that reads the
    declaration into `$_CORE_CAP`, with `_core_cap <key> [fallback]` as the accessor.
    Inside the Core band, so **every** `CORE_PROFILE` loads it: `minimal`'s ceiling is 30,
    and a lean profile must not silently lose the dispatch table.
  - `blib_link_os_layer` links it as a **fifth** OS overlay, beside the `.zsh`/`.conf`/
    `.gitconfig` it already links. Every OS repo's `bootstrap.sh` calls that helper today,
    so no repo edits a bootstrap to adopt this — it authors a file.
  - `scripts/check-capabilities.sh` is the schema, and the gate: unknown key, missing or
    empty required verb, duplicate key, `SCHEDULER` outside `systemd|launchd|none`, and
    trailing whitespace are all failures. It takes a **path**, so the same validator runs
    from Core's `make audit` (on the shipped example) and from each OS repo's own lint as
    `core/scripts/check-capabilities.sh os/<os>.capabilities` — nine repos gated by one
    definition instead of nine greps that drift. `--packages install/packages.txt` adds an
    opt-in cross-check that each verb's binary is one the repo installs.
  - `examples/os.capabilities.example` — the Fedora declaration to copy from, held to that
    same gate so the fleet's template cannot drift from the fleet's schema.

  **Nothing in Core dispatches through `$_CORE_CAP` yet** — `up`, the maint scheduler and
  `core-doctor`'s opt-in split are separate changes. Landing the schema alone keeps the
  foundational commit reviewable, and means a box with no declaration behaves exactly as
  before.

  Two decisions worth recording, because both went against the original proposal:

  - **A missing declaration falls back silently; it does not fail, and it does not warn.**
    A hard failure at shell startup leaves an unusable interactive shell on a box you are
    very likely SSH'd into precisely to fix it. Enforcement belongs in a gate you run, not
    in the login shell. Nor does it warn: absence is the normal state until an OS repo
    authors its declaration, so a default-on warning is two lines of stderr on every shell
    on every box in the fleet. Set `CORE_CAP_LOUD=1` to opt into it.
  - **The clipboard backend is deliberately _not_ in the schema.** `bin/clip` is re-exec'd
    by nvim and tmux on **every** yank and paste, and its WSL probe was already rewritten to
    avoid forking a `grep` per invocation. Adding a file read and parse to that path would
    spend exactly what that optimisation bought, for a value that changes once per machine.

- **A recorded jq security floor of ≥ 1.8.2 — `PORTING-MATRIX.md` footnote ³⁴.** jq 1.8.2
  (2026-06-20) fixes **16 CVEs** — heap and stack overflows, out-of-bounds reads, an integer
  overflow, a use-after-free and a hash-collision DoS — every one reachable **through parsing
  input**, which is the tool's entire job. That is load-bearing here because jq is pointed at
  output produced by machines other than yours: Core sets `HAVE_JQ` and this repo prescribes
  `jq -e '.detection.missed == []'` as the provisioning gate a role layer runs against
  `core-doctor --json`. Below the floor today: Alpine 3.22–3.24 and Fedora 43/44 (1.8.1),
  Debian 13 / Ubuntu 24.04 (1.7.1), Leap 15.x (1.6).

  **It is recorded, and deliberately not enforced.** Debian backports security fixes without
  bumping the version, so on the whole Debian/Kali/Ubuntu lane a `1.7.1-x` build may carry all,
  some or none of these and `jq --version` is not evidence either way — a version gate would
  false-positive across the lane. The footnote states this as a third shape alongside the two
  version-sensitive rows already in the file, because they point opposite ways and the
  distinction is the whole content: `⁵` (tree-sitter) **mandates** a version check, since apk is
  honestly old; `²²` (`sd`) **forbids** one and mandates capability probing, since `--version`
  lies. jq's version is neither honest nor probeable — nothing in the CLI surface reveals which
  patches a build carries — so there is nothing to detect from the shell. Core itself is
  unaffected: `HAVE_JQ` is detect-only with no alias, and nothing in Core shells out to jq. (#702)

- **`examples/mise.tools.toml` — the tools nothing upgrades, routed through the step that already
  runs.** `maint/dotfiles-maint.sh` runs `mise upgrade --yes` and `rustup update` and has **no**
  cargo/go re-install step, so roughly fifteen tools — `viddy`, `yazi`, `ouch`, `jj`, `ast-grep`,
  `jnv`, `watchexec`, `tealdeer`, `dust`, `sesh`, `doggo`, `gron`, `shfmt`, `glow`, `yq`, `duf`,
  plus `carapace`/`starship`/`atuin` — are installed once and then rot silently on up to eight
  machines. `PORTING-MATRIX.md` already recorded the gap twice (footnote ²⁵'s "no
  `cargo install-update` step", footnote ²⁷'s "nothing upgrades carapace afterwards"); footnote
  ²⁵ now carries the path out instead of only the complaint.

  Declaring a tool under `[tools]` with a `cargo:` / `go:` / `ubi:` backend makes the existing
  maintenance step do the work, and `lockfile = true` records exact resolved versions **and
  checksums** — a strictly better trust anchor than the unsigned release-URL route ²⁷ warns
  about. Two caveats are written into the file rather than assumed: **Alpine must take `cargo:`,
  never `ubi:`/`aqua:`** (those prebuilts are glibc-linked — the same trap `mise/config.toml`
  documents for `foundry`), and **`ouch` must force a build without default features** there,
  since bzip3's build script runs bindgen, which `dlopen`s libclang, which a static musl link
  defeats (footnote ¹⁴).

  **Core's share is the example and the paragraph, by design.** Which backend a given box needs
  is an OS question, so the real `[tools]` declarations belong in each OS repo — Core cannot
  answer it for eight of them at once. Like everything in `examples/`, it is wired into no
  bootstrap. (#702)

- **`/freshness-triage` can see the two bump classes it was blind to, and a guard that keeps the
  routine rails honest.** Both gaps were _structural_ — they recurred on every run, not just the
  one that reported them.

  **The Renovate dashboard.** Renovate parks bumps on a per-repo Dependency Dashboard issue
  without opening a PR — rate-limited, awaiting approval, or grouped-and-pending. Reading it
  needs `gh issue list`, which was outside the command's `allowed-tools`, so the routine derived
  its Renovate verdict from PR absence alone. PR absence is equally consistent with _nothing to
  bump_ and _several bumps parked on the dashboard_. The report said "not assessed" — honest, and
  it said it every week.

  **Bot liveness.** Zero open PRs is likewise consistent with the bot never having run. A healthy
  `freshness.yml` with nothing to do and one that has not fired in a month produced the
  **identical** report. That is the failure a freshness routine most needs to catch, since a
  silently dead bot degrades exactly like a current tree. `gh run list --workflow=freshness.yml`
  is now allowed, and a run that has not _completed successfully_ within **10 days** — one missed
  weekly run plus slack — is a finding in its own right, reported above the per-PR verdicts,
  because a dead updater invalidates the "nothing to triage" reading underneath it.

  Neither is covered by the #636 dashboard, which counts open Renovate _PRs_ and _links_ the
  dashboard issue without reading it, and has no liveness signal at all. `release-readiness`
  already carries both capabilities, so this is no new security posture; the nvim build-hook
  restriction is untouched.

  **The guard.** `claude-routines.yml` states the invariant — each job's `--allowedTools` mirrors
  the routine's own frontmatter and is never broader — and nothing enforced it. The two live
  ~200 lines apart, in different files, in different spellings. `test-core.sh` now checks every
  mirror in both rails against the frontmatter of the routine its `claude -p "/<name>"` names,
  comparing as sets so ordering and whitespace are not findings. Drift **broader** hands a
  scheduled, token-bearing job a capability its definition never granted; drift **narrower**
  fails at runtime, weekly, in a job nobody watches. Verified in both directions; 9 mirrors
  currently match.

- **`core-doctor` reports the mirror of #545: a `HAVE_*` flag set for a binary that is now
  gone.** #545 shipped the silent half — present at report time, never wired. This is the other
  state: detected at band 00, flag set, `20-aliases.zsh`'s guard passed and defined the alias —
  and the binary is no longer on `PATH`.

  #631 filed this as low-priority and argued against taking it, on the grounds that the failure
  is loud and self-explanatory and would need a fifth glyph. **Both halves turn out not to
  hold, and that is why this landed.**

  It is loud only for tools that shadow nothing. Six aliases shadow **classic commands** — `ps`,
  `top`/`htop`, `watch`, `df`, `ping`, `help` — and there a stale flag does not fail to give you
  `procs`, it **breaks `ps`**, with a message naming a binary the user never typed. `core-doctor`
  is what you reach for at that point, and `✗ procs` does not connect to "your `ps` is broken".
  So the block names the dangling **aliases**, not the tools, read from the live `aliases` table
  so it cannot drift from `20-aliases.zsh`.

  And it needs **no fifth glyph**. The row keeps its honest `✗` — which is already correct about
  presence — and the remedy lives in a `stale` block, exactly as `not wired` does. The legend
  keeps its three states, the alarm-fatigue budget #620 was careful with is not spent, and the
  render⇄json parity regex is untouched (the block sits past the `opt-in` trim, structurally
  invisible to it). That comparison is re-run with this axis actively firing, since unlike
  #545's `⚠` it fires on the branch the parity test stubs.

  PATH shrinking mid-session is not exotic here: `mise activate zsh` registers a `chpwd` hook
  that rewrites `PATH` on every `cd`, so a toolchain two directories away can take a binary with
  it. `--json` gains `detection.stale` beside `missed` — its own key, not a widened one, and
  disjoint from `missed` by construction. Both ledger gates from `_core_doctor_unwired` apply
  unchanged; only the comparison flips.

- **A decided-and-rejected ledger for `/tool-scout` — `.claude/tool-decisions.md`.** The
  routine's baseline is five files (`PORTING-MATRIX.md`, `zsh/00-tools.zsh`,
  `zsh/20-aliases.zsh`, `mise/config.toml`, `zsh/45-plugins.zsh` + `nvim/lazy-lock.json`) that
  all describe what Core **has**. Nothing recorded what Core **considered and declined**, so a
  rejected tool was indistinguishable from one never evaluated.

  `hexyl` came back ranked #3 "adopt" on 2026-08-18, six days after #395 closed it
  `NOT_PLANNED` and refiled it as `dotfiles-Kali#182`. #395's own body anticipated it —
  _"filed so the decision is recorded rather than silently re-proposed by next week's scan"_ —
  and recording it was not enough, because nothing in the routine read it.

  The cost is not a wasted ranking slot. A re-proposal arrives with a fresh case-for and **no
  counter-argument attached**, so the decision gets re-made on half the evidence; `hexyl` would
  have been adopted on that pass if the report had been actioned without someone happening to
  remember. `fastgron` is the near-miss in the same report — correctly skipped, with reasoning
  the report itself noted should be written down, caught by luck rather than by process.

  Seeded with both. The load-bearing half is that **the routine is made to read it**: the
  instruction lands in `.claude/commands/tool-scout.md` _and_ `.claude/agents/tool-scout.md`,
  since the subagent does the actual ranking and would otherwise get it second-hand. A listed
  tool may be re-proposed only against the recorded reasoning, naming what changed, and the
  report states the prior decision per candidate — explicitly "none" when there is none, since
  an omitted line reads the same as an unchecked one.

  `/os-package-availability` and `/modernize` share the shape but are deliberately left alone:
  both already carry a working in-band equivalent (the "intentionally excluded" comments in
  `packages.txt`, and the machine-readable floor in `scripts/modern-baseline.yml`). That
  reasoning is recorded in the ledger itself so it is not re-proposed either.

- **`V5-PROPOSAL.md` — the design record for the next major.** Core is at `4.18.0`
  with the whole fleet synced to it and an empty backlog; nothing in the repo
  proposed a v5, and the only `v5` strings anywhere were `RELEASE-RUNBOOK.md` using
  `v4`→`v5` as the worked example for the moving-alias procedure. So the machinery
  for cutting a major was documented and rehearsed while the _content_ of one was
  not written down anywhere.

  The proposal follows `V4-PROPOSAL.md`'s structure and states one thesis: **the OS
  layer becomes a contract instead of a convention.** v4 made the _load order_
  declarative — modules stopped being a hand-listed array and became `NN-` fragments
  the loader globs — and v5 does the same to capability, payload and surface. Four
  bundled changes, chosen because they touch the same three contracts (the
  `bootstrap.sh` symlink set, the load chain, and what a vendored `core/` contains),
  so the fleet re-bootstraps once rather than four times:

  1. **`os.capabilities`** — each OS repo declares its package-manager verbs,
     clipboard backend, scheduler and opt-in tool split, and Core dispatches through
     the declaration. Core currently carries **154 package-manager references** —
     88 in `zsh/60-update.zsh`, 49 in `maint/dotfiles-maint.sh`, 17 in
     `zsh/30-functions.zsh` — in the layer whose own test is "if it changes when the
     OS changes, it's not Core". `CHANGELOG.md:927-931` already recorded that fixing
     `core-doctor`'s opt-in classification "needs a per-repo manifest"; this is it.
  2. **Vendor only what is Core** — the `core.manifest` payload is 1.4 MB and a
     vendored `core/` is 5.9 MB, so **76% of what ships to every machine is not
     Core**. The largest single item is `assets/demo.gif` at 1.8 MB, larger than the
     entire Core payload, replicated into nine trees where no README displays it.
  3. **Retire what nothing uses, declare what things do** — delete `CORE_PROFILE`
     (nothing writes the `$ZSH_CFG/profile` it reads, no OS repo mentions it, and
     `bootstrap-test.yml` asserts `~/.zshrc` must not set it), which also closes the
     unenforceable band-squatting footgun `VENDORING.md:185-192` documents; and turn
     `HAVE_*` from 43 accidental exports into a stated API, since five are consumed
     downstream and none are declared anywhere.
  4. **`clip` learns what a secret is** — `optoken` pipes a live TOTP through `clip`,
     which on a headless box reaches OSC 52 and, under the `set-clipboard on` that
     `tmux/tmux.conf:45` itself sets, leaves the code in a `tmux show-buffer`-readable
     paste buffer.

  §11 records the non-goals with their reasons — renumbering the bands (~470
  references across 62 files, and `V4-PROPOSAL.md` §9 already resolved against it),
  retiring the bare verb names, consolidating `bootstrap.sh`, and an nvim overhaul —
  plus four open questions the implementation must answer rather than assume. It is
  **report-first**: nothing here is implemented, and an issue the proposal rejects
  should be closed `not_planned` with a reason rather than left open.

  `V5-PROPOSAL.md` joins the `META_ALLOWLIST` in `scripts/audit-core.sh` beside
  `V4-PROPOSAL.md`, so §1's manifest-drift check accounts for it.

### Changed

- **nvim plugin pins move forward for three plugins.** `alpha-nvim`, `nvim-lspconfig` and
  `schemastore.nvim` advance to the commits a sandboxed headless `Lazy! sync` resolved:
  `6c6a89d` → `4ba26e4`, `221c438` → `af9adce`, and `73e89eb` → `5f2a3b5`.

  Every new SHA was verified to exist upstream and to be a strict fast-forward of the one it
  replaces (`status=ahead`, `behind_by=0` in all three — no rewrite or force-push), and each
  range was read before promotion:

  - **`alpha-nvim`** one commit: _clear stale button keymaps on redraw_. Core does define its
    own dashboard buttons (`plugins/alpha-nvim.lua` sets `startify.section.top_buttons.val`),
    so this is a fix that lands on configuration Core actually ships, not a no-op.
  - **`nvim-lspconfig`** six commits: two new server configs (`ms_terraform_lsp`,
    `rust_glancer`), one fix making `rust_analyzer` show a non-error message when `rustc` or
    `cargo` is missing, and three generated `configs.md` updates. Core registers neither new
    server and does not configure `rust_analyzer` — its Terraform server is `terraformls`,
    untouched here.
  - **`schemastore.nvim`** one commit: a catalog refresh.

  Nothing renames or removes an API Core calls.

  **Recorded after the fact.** The roll landed in #675 as a lockfile-only commit, so it
  reached `main` with no `[Unreleased]` entry — `CONTRIBUTING.md` requires one and nothing in
  `audit-core.sh` can enforce it (§9 checks that `core.version` has a matching dated heading,
  not that a change brought an entry). Pins are what stop plugins floating silently into
  eight repos, so every roll is a change those repos receive on their next sync, and there is
  no carve-out for automation. Same finding, same argument, as the sweep recorded earlier in
  this file. (`nvim/lazy-lock.json`, #675)

- **The secret-scan policy gate (`audit-core.sh` §5g) now BLOCKS.** It shipped advisory in
  #623, on the principle §5f states: repos are short on arrival, and a gate that is red from
  its first run is a gate someone turns off. That reason has expired — the fleet is clean.

  `dotfiles-Alpine` and `dotfiles-Gentoo` each carried a root `.gitleaks.toml`. gitleaks
  auto-discovers a config at the scan root, so those files silently governed **every** local
  scan in their repos, including invocations that pass no `-c` and look, from the command line,
  like stock scans. Both rule sets were simultaneously _narrower_ than Core's (gitleaks' stock
  defaults, with Core's variable-reference allowlist dropped) and _wider_ (whole-path
  exemptions for `core/`, and in Gentoo's case `README.md`). Being green under them was not
  evidence of being clean; it was evidence of being measured differently.

  CI was never affected: the reusable `lint-call.yml` secrets leg passes `-c` explicitly and an
  explicit config beats auto-discovery. The entire divergence lived in the author-time path —
  which is where it is least likely to be noticed, and where a hook greener than CI does the
  most damage.

  Both are now deleted (`dotfiles-Alpine#133`, `dotfiles-Gentoo#125`), and both repos verified
  clean under `core/gitleaks.toml` — working tree, plus all 271 commits of Gentoo's history,
  which is what proved its `README.md` exemption stale. No Core sync was needed: Core's
  variable-reference allowlist already covers the `core/CHANGELOG.md` line the stock
  `curl-auth-user` rule flags. All nine OS repos now measure by the same policy.

  Blocking is the right posture here specifically because this failure is **quiet**. A repo
  running its own rule set is green, and stays green as that rule set drifts, because nothing
  compares it to Core's — so the next person to look sees a passing gate, which is worse than a
  red one. Advisory suits a finding people can see; not one whose whole hazard is that it looks
  fine. Still skipped when siblings are not checked out, exactly like §5f, so it is inert in CI
  (which clones only Core) and bites locally and in fleet sweeps.

- **`V5-PROPOSAL.md` §11 records the bare-verb-name decision instead of deferring it.**
  The section listed retiring `up` / `serve` / `gsync` / `maint-*` as an open question
  tracked in #692, ending _"it must be decided before the tag, not left open for a whole
  major cycle."_ #692 is now closed `not_planned` — the names stay — so the paragraph
  asserted an open decision that had already been made.

  It now records the outcome and the grounds for revisiting: the additive dispatcher in
  #684 already buys the coherence, while deletion buys namespace purity at the cost of
  daily friction on the most-typed verbs plus churn across 28 completions, `core-help`'s
  rows, `_core_suggest`, `aliases.md` and `PARITY.md` (a two-repo change). Reopening needs
  evidence of a real collision — `up` and `serve` are genuinely collision-prone and a
  shadowing `up` fails silently — not a fresh aesthetic objection.

  The point of #692 was that an unrecorded decision gets silently re-proposed, so leaving
  the RFC saying "must be decided" while the answer sat only in a closed issue was the
  same failure one level up. (#692)

### Fixed

- **`CONTRIBUTING.md`'s "adding a new Core file" checklist named a list that no longer exists,
  and omitted three that do.** Step 6 sent you to give the new directory a home in "the two
  path lists", one of which was §5c of `scripts/audit-core.sh` — whose scope became
  **manifest-derived**, as `scripts/audit-core.sh:583` says out loud. So the step sent a
  careful reader looking for something to edit that is not there, at the one moment they were
  most likely to be careful.

  The three lists it did **not** name are the ones with no gate behind them:
  `scripts/test-core.sh`'s `_lr_d` fixture directory list — **the one that fails quietly**,
  because a missing source makes `blib_link` early-return (`lib/bootstrap-lib.sh:127-131`) and
  every assertion below it pass vacuously; the grouped `_lr_is_link_to` assertions; and
  `dotfiles-MacBook/bootstrap.sh`'s `--uninstall` `dests` array, the only hand-maintained one
  in the fleet. The rewrite also names all **three** prose enumerations in
  `lib/bootstrap-lib.sh` that `:436` tells you to keep in step, where the checklist mentioned
  none.

  **Reading the list it now tells you to edit found the gap it predicts:** `mise/config.toml`
  and `atuin/config.toml` had never been in the `_lr_is_link_to` group, so the link run proved
  their sources were copied but never that the links land where bootstrap promises. Both are
  asserted now. (#718)

- **A missing `os/<os>.capabilities` warned on every shell, on every box, with a remedy that
  could not work.** `zsh/02-capabilities.zsh`'s `else` branch was unconditional and
  unthrottled, and three facts composed into a fleet-wide stderr leak: no OS repo has authored
  a declaration yet, `blib_link_os_layer`'s `[[ -f ]]` guard therefore links nothing, and
  `CORE_CAP_QUIET` was set by exactly one thing in this repo — `scripts/test-core.sh`. Band 02
  loads under every `CORE_PROFILE`, so every interactive shell, every tmux split and every
  `zsh -i -c` printed two lines. The hint was the worse half: it named
  `./bootstrap.sh --links-only`, which re-runs the _same_ guard, so an operator who followed
  it saw nothing change and the warning persist.

  **Silence is now the default and the warning is opt-in via `CORE_CAP_LOUD=1`.** Absence is
  the normal state, and nothing dispatches through `$_CORE_CAP` yet — so there is no
  degradation to warn about. When a consumer lands, the warning belongs at _its_ call site,
  where it can name what actually fell back. The message now points at authoring the
  declaration (`examples/os.capabilities.example`) rather than at re-running bootstrap. Two
  prose claims that this falsified are corrected in the same change: this file's own
  "byte-for-byte unaffected", and `lib/bootstrap-lib.sh`'s "warns once" — there was no
  once-per-box state anywhere in the fragment. (#715)

- **`scripts/check-capabilities.sh`: a dangling `--packages` looped forever.** `shift 2` with
  fewer than two positionals returns non-zero **and leaves the positional parameters
  unchanged** (POSIX; bash follows). `shift 2 || true` swallowed the status but not the
  non-shift, so `$1` stayed `--packages` and `while [[ $# -gt 0 ]]` never terminated. This
  script is called from nine OS repos' `make lint`, where an infinite loop is a job that burns
  to the runner timeout instead of failing in a readable way. It now checks arity and exits 2.
  (#715)

- **`scripts/check-capabilities.sh` accepted an inline `#` as part of a verb.** The file looks
  like an env file and its own header is dense with `#` comments, so
  `PKG_OWNS=dnf provides   # which package owns this` is the natural thing to author — and
  every rule waved it through: the comment arm only matched a line _starting_ with `#`, the
  trailing-whitespace rule saw a final `s`, and `--packages` inspects only the first token.
  Core's reader stores the whole string, so the declared verb became the command _and the
  comment_. The same arm had a second edge: spelled `[[:space:]]*'#'*`, it is a glob matching
  one whitespace character, then anything, then `#` — so an **indented assignment containing a
  `#`** was skipped in silence and resurfaced as `required key missing` with the line sitting
  right there in the file. Both arms fixed; both directions covered by tests. (#715)

- **`core-doctor` rendered `✓` off an alias for a tool that had left PATH.** `_core_have` is
  `command -v` and zsh's `command -v` **resolves aliases**; `zsh/20-aliases.zsh` defines three
  aliases whose name equals a doctor row (`bat`, `fd`, `rg`). So the presence branch matched
  the alias, the `else` branch never ran, and `_core_doctor_stale` was never asked — `rg foo`
  answering `command not found` while `core-doctor` printed `✓ rg`. That is precisely the
  failure #631 was written to surface, silently excluded for three rows: `rg` on every distro,
  and `fd`/`bat` everywhere except Debian, where they resolve to `fdfind`/`batcat` and have no
  alias. The probe is now a PATH lookup with no alias layer, reusing the idiom already in the
  file. (#715)

- **`scripts/check-capabilities.sh --help` leaked past the end of its header.** `sed -n '2,30p'`
  against a header block ending at line 28, printing `set -uo pipefail` into the help output.
  (#715)

- **`zsh/35-fzf.zsh` claimed the shell and tmux share one session picker. They do not.** The
  `Ctrl-G` widget runs its own inline `sesh list | fzf`; `tmux/scripts/tmux-sesh.sh`'s richer
  picker — `--height 100%`, a border label, and the `ctrl-a`/`ctrl-t`/`ctrl-g`/`ctrl-d`
  mode-switch reloads — is reached **only when sesh is absent**, on the fallback path. So the two
  have been drifting in the one direction the comment promised they could not, and a reader
  fixing the tmux picker had no reason to look at the shell one. The comment now says which path
  is which and points at the row that records the option of collapsing them.

  **That row is the other half.** `/tool-scout` (#702) ranked adopting sesh's built-in
  `sesh picker` as _adopt, low priority_, on the grounds that **both** recorded blockers were
  spent. Only one is. #518 held it on _"no preview"_ — genuinely spent, since sesh 2.28.0
  (2026-07-27) added an opt-in preview pane, custom icons and index jumping. #376 held it on
  **loss of fzf theming**, and that one still stands: verified against the binary rather than the
  docs, the complete `[tui]` key set is `prompt`, `placeholder`, `show_icons`, `show_windows`,
  `preview`, `preview_width`, `preview_min_width`, `preview_border`, the three `alias_*` keys and
  `separator_aware` — **no colour key of any kind, and no `SESH_*` environment override**
  (`preview_border` picks a divider glyph, not a colour).

  Core's tokyonight-storm palette lives **once**, in `FZF_DEFAULT_OPTS`, and every picker
  inherits it deliberately. Adopting would swap the two most-used pickers on the box for
  unthemeable ones across eight machines, to gain a preview pane the fzf path already has via
  `--preview 'sesh preview {}'`. Declined and recorded in `.claude/tool-decisions.md` under
  Watching, with the condition that would reverse it: a colour schema under `[tui]` — not a new
  release, and not the preview pane, which is already here. (#702)

- **A scripted `nvim -c 'write'` never formatted anything — conform.nvim spawns Mason formatters
  without declaring mason as a dependency.** The same undeclared edge as the nvim-lint fix below
  (#652), in `plugins/conform.lua`, with a worse shape. conform loads on `BufWritePre` and spawns
  Mason-installed formatters (`prettierd`, `gofumpt`, `clang-format`, `php-cs-fixer`,
  `sql-formatter`, `ktlint`, `google-java-format`, `taplo`, …), which resolve only once
  `mason.setup()` has prepended `<data>/mason/bin` to `vim.env.PATH`; conform declared **no
  `dependencies` at all**, and mason arrived incidentally via `nvim-lspconfig` (`User FilePost`)
  and `mason-tool-installer` (`VeryLazy`) — neither of which lazy.nvim orders against it.

  Unlike #652 this is **not a race**: `-c` commands run _before_ `VimEnter`, so `VeryLazy` has not
  fired and the `vim.schedule`'d `User FilePost` emit in `config/autocmds.lua` has not either.
  mason has therefore _never_ loaded by `BufWritePre`, deterministically. Measured on macOS with a
  `{"a":1,   "b":[1,2,3]}` fixture and `prettierd` (Mason-**only** here — `stylua` and `shfmt` also
  sit on the base `PATH` and mask this): `nvim --headless f.json -c 'write' -c 'qa!'` formatted
  **0/4**, with mason unloaded and `executable("prettierd")` = 0 at `BufWritePre`; the same write
  deferred past startup — the interactive shape — formatted **4/4**.

  It failed **silently**, which is why it survived: conform auto-skips a formatter that is not on
  `PATH` (the same self-gating that makes the optional formatters in the map safe on a box without
  them), so there was no error, no `vim.notify`, nothing in `:messages` — the file was just written
  unformatted, and a later `:ConformInfo` showed the formatter as available. Invisible
  interactively, and every time for `nvim -c` writes in a Makefile, git hook, or CI check.
  Declaring `dependencies = { { "mason-org/mason.nvim", opts = {} } }` fixes it at **4/4** and costs
  nothing (startup over five runs: 92.3 ms before, 89.9 ms after — noise). `scripts/test-core.sh`
  §D's #652 assertion is now table-driven and covers both specs. (#703)

- **Two `PORTING-MATRIX.md` claims about atuin that upstream had not yet earned.** Footnote ²⁰
  asserted the daemon socket default _"moved in atuin **18.20.0**"_. It has moved in **no
  release, stable or beta**: PR #3910 merged 2026-08-12, _after_ `v18.20.0-beta.3` (2026-08-07),
  and the newest stable is 18.19.0 (2026-08-03), which still resolves the old path. The change is
  now dated by its **merge** rather than by a version — naming an unshipped version is how a
  reader concludes their box is already on the new path. #518's pre-emptive handling stands
  unchanged: probing the new default and both legacy paths is ahead of upstream, which is the
  right direction, and only the prose was wrong.

  The same footnote also gains a watch note on **`atuinsh/atuin#3957`** (opened 2026-08-20, open,
  unreviewed), which would make the _daemon_ unlink a stale socket on bind failure. Footnote ²⁰'s
  finding that "the healing lives in the **client**" is the measured basis of `--premise
  autostart` and of `CORE_ATUIN_AUTOSTART_VERIFIED_AGAINST`; if #3957 merges, that premise stops
  holding. Recorded, not acted on — and the note says explicitly not to touch the anchor, which
  is a claim the premise was **re-measured**, not a version bump. (#702)

- **The decided-and-rejected ledger held two rows while ten scans' worth of decisions sat only in
  closed issues.** `.claude/tool-decisions.md` shipped seeded with `hexyl` and `fastgron` — the
  two the CHANGELOG named — but #327, #376 and #518 had between them declined a further fifteen
  tools with real recorded reasoning that the file did not carry. A ledger the routine is
  _required_ to read is only as good as its coverage, and the gap was invisible from inside it.
  Backfilled from the issues themselves rather than from memory.

  It also grows a **Watching** section, which it lacked entirely — a held-not-declined tool had
  nowhere to live, so it read as either adopted or rejected. Every watch row now names the
  **event** that would end the hold, because two of the three had their original reason expire
  without anyone noticing. `xan` is the worked example and gets the long form: it was held on
  packaging (#376) and on frequency (#327), and **both have expired** — 0.60.0 is in Arch
  official, Gentoo GURU, Homebrew and nixpkgs, and Core's bar for an opt-in `HAVE_*`-gated tool
  is visibly lower already (`jnv` is in no `packages.txt` anywhere and was adopted regardless).
  The reason it stays held is a new and more durable one: 0.60.0's notes _lead_ with breaking
  command-line argument changes, and Core has been bitten by exactly that in exactly this family
  — `sd` 1.1.0, where the failure was silent and `--version` could not tell you which behaviour
  you had (footnote ²²). The condition is now stated: two consecutive minors with no breaking
  argument changes. A stale hold is the failure mode this file exists to stop, in the same way a
  forgotten decline is. (#702)

- **Seven prose claims that the fleet had already falsified.** The 2026-08-25 `/doc-audit`
  sweep (#701) read ~326 matrix cells, ~150 aliases and all 69 manifest entries and found the
  code right and the prose behind it in seven places. Corrected here; two of the seven were
  wider than the report said.

  - **`lib/bootstrap-lib.sh` retired a migration that is still open.** It said _"BOTH role
    repos now call this helper, so there is nothing left to migrate."_ `Offense` does;
    `Defense` still hand-rolls the band in its own `wire_defense_stage` and never names
    `blib_link_role_layer`. `core.manifest` and `PORTING-MATRIX.md` both record the split
    correctly — this comment was the only one of the three that claimed it was finished. Its
    companion paragraph is also moved back to the present tense: Defense's `BLIB_DRY` fork is
    live, not historical, and is precisely what adopting the helper would retire.
  - **Four Kali cells in `PORTING-MATRIX.md` are `asset²⁸`, not package names** —
    `git-delta`, `difftastic`, `mise` and `uv`. #701 named the first three; `uv` carries the
    identical defect and reads _more_ plausible, because kali-rolling genuinely does ship
    `uv` 0.9.17 — but `dotfiles-Debian` fetches the pinned `UV_VERSION` asset on every
    target, so the cell was recording what the archive **contains** rather than what the repo
    **installs**. That is exactly the failure the `²¹ᵃ` inherited-not-verified caveat warns
    about, and it is now stated there as the test to apply to the cells still unmarked.
    `difftastic` is the sharpest: `dotfiles-Debian`'s `packages.txt` carries a five-line
    postmortem about this specific mistake, and the matrix still carried the error it
    describes. Footnote ²⁸ widens past its Debian-only framing (the two columns reach the
    same cell for opposite reasons) and ³⁰ drops the claim that Kali's bootstrap uses
    `mise.run` — it has not since the lane moved.
  - **"Eight machines + `Defense` = the nine" counted `Offense` as a machine.** Arithmetic
    right, taxonomy a release out of date: `Offense` shed `os/` when the Kali lane moved to
    `dotfiles-Debian`, so it qualifies for the exemption that sentence grants `Defense`. Now
    seven machines + `Offense` + `Defense`. This was a passage, not a line — the surrounding
    atuin-daemon block counted eight in three more places and still listed `Kali` as a
    machine of its own, an identity no repo has owned since the move. Kali folds into the
    `Debian/Ubuntu` row, which is wired, so the wired count is three of seven.
  - **`README.md` listed the verbs that live only in `core help` and missed two.** `up` and
    `update-check` are both real (`zsh/60-update.zsh`) and absent from `aliases.md`. Walking
    `core-help`'s full `rows` array against the cheat sheet says those are the only two
    function verbs missing — so the list is completed rather than softened to "e.g.", and
    the keybindings group (in neither document) is now named too.

  The sweep's remaining findings were already correct and are recorded as clean: every
  manifest entry traced both directions, all three alias sets resolving, and the
  release-pinned `dotfiles-web` mirror correctly lagging `main` by exactly one unreleased
  paragraph rather than drifting. (#701)

- **`.claude/tool-decisions.md` was written, referenced from four places, and never tracked.**
  #661 taught `/tool-scout` to consult the decided-and-rejected ledger and shipped the three
  files that point at it. It did not ship the ledger: `.gitignore`'s `.claude/*` carries
  **per-directory** negations, so `commands/` and `agents/` vendored out while the file they
  read stayed ignored. It existed only on the machine that authored it.

  That is worse than a plain missing file, because the routine's own instruction is to say
  _"none"_ when a candidate has no prior decision. With no ledger **every** candidate resolves
  to "none" — in the exact voice that means _checked_ — so the report asserts the ledger was
  consulted while consulting nothing. #634 was filed because a rejected tool was
  indistinguishable from one never evaluated; it still was, now with a line claiming otherwise.
  `hexyl` came back ranked #3 "adopt" six days after #395 closed it, which is the recurrence
  the ledger exists to stop.

  The fix is one `.gitignore` line, and the reason it took three reports to find is that
  everything else pointed the other way — `.claude/` is repo-meta, correctly allowlisted
  wholesale by `audit-core.sh`, so no manifest question was ever wrong.

  **`audit-core.sh` §1b makes the class detectable.** §1 asks whether every _tracked_ file is
  accounted for, in both directions, and its reverse walk is fed by `git ls-files` — so it
  catches a tracked file that is unaccounted for and structurally cannot see an accounted-for
  file that was never tracked. §1b asks the mirror question: every `` `.claude/…` `` path the
  routines say they read must **resolve on disk and be tracked**. Absent and
  present-but-untracked report as different failures, since they have different repairs — and
  this one was the second, which all three reports of it called the first. It blocks rather
  than advises on the §5i grounds: the tree is green on arrival, so every future hit is a
  regression in the commit under test. (`_core_claude_ref_hits` in `scripts/lib/common.sh`,
  with its unit in `scripts/test-core.sh`.)

  It rhymes with `core.manifest` naming a `verify-core` backstop that never existed (#454) —
  an assertion pointing at a file nobody created. The sharper version here: #634 shipped a
  mechanism to stop decisions being recorded where nothing reads them, and the mechanism
  itself was recorded where nothing can read it. (#700)

- **Opening a file linted it only about half the time — nvim-lint's on-open replay raced
  mason.nvim's `PATH` prepend.** `plugins/nvim-lint.lua` loads on `User FilePost` and replays
  the triggering buffer at the end of its `config()`, because that buffer's real `BufReadPost`
  has already fired by then. The replay spawns Mason-installed linters, which resolve only once
  `mason.setup()` has prepended `<data>/mason/bin` to `vim.env.PATH` — and nvim-lint declared no
  dependencies at all. `nvim-lspconfig` loads on the **same event** and pulls mason in as its
  own dependency, but lazy.nvim orders a plugin against its **declared dependencies only**,
  never against another plugin on the same event. Which of the two ran first was therefore
  undefined, and losing the race meant `vim.uv.spawn` got `ENOENT` on a bare `rubocop`.

  Measured over six opens each: ruby/rubocop linted **4/6** on macOS and **3/6** on native
  Windows, markdown/markdownlint-cli2 **2/6**. The controls are what pin it — `sh`/shellcheck,
  which lives on the PATH nvim inherits rather than under Mason, was **6/6** and never failed,
  and rubocop itself went **6/6** when Mason's bin directory was pre-seeded onto `PATH` before
  nvim started. Nothing about the linters, the filetypes or the config gates was involved.

  It read as flakiness for two issues rather than as a missing binary because `:w` always
  worked: by the first save mason has long since fixed `PATH`. On Windows the failure was also
  **fully silent** — no error, no notification, no `:messages` entry — so an unlinted file was
  indistinguishable from a clean one (macOS at least printed `Error running rubocop: ENOENT`).
  Both rows in the original Windows report were Mason binaries, so it had no base-PATH linter
  acting as a control, which is why the scope sat at "Windows-only" until it was measured
  elsewhere.

  The fix is one declaration: nvim-lint now names `mason-org/mason.nvim` in its `dependencies`,
  so lazy loads mason — `setup()` and all — before the replay runs. It costs no startup time,
  because mason was already being loaded at that event; the edge simply was not written down.
  Verified on macOS by A/B on one box: **3/6 before, 6/6 after**, with every `ENOENT` gone.

  `scripts/test-core.sh` §D gains a spec-level assertion as the regression net. The ordering
  being guarded is a lazy.nvim guarantee, so re-deriving it at runtime would test lazy rather
  than this config, and the race cannot be reproduced hermetically anyway (it needs lazy,
  nvim-lint and mason really installed) — whereas _dropping_ the dependency is luacheck-clean,
  load-clean and regresses only intermittently on a real machine, which is exactly the profile
  that needs a static gate. Two comments that had gone stale against the replay are corrected
  in the same change: `config/autocmds.lua`'s "nvim-lint is driven by BufWritePost/InsertLeave
  only — nothing to replay", and `nvim-lint.lua`'s own header. (#652,
  dotgibson/dotfiles-MacBook#191)

## [v4.18.0] - 2026-08-24

### Added

- **A weekly, genuinely unstubbed bootstrap — `real-bootstrap.yml`.** The per-PR gates cover
  two thirds of the problem and cannot cover the third. `bootstrap-test.yml`'s `--links-only`
  leg returns before `provision()` and asserts the wiring; its opt-in `provision-stub` leg
  executes `provision()` with the package managers and downloaders shimmed, covering the
  control flow. Neither installs anything, so a **wrong package name**, a **bad or rotated
  repo key**, any **failure branch** (the stubs always return 0), and anything invoked by
  **absolute path** are invisible to both.

  Enabling the stubbed run across the fleet also proved a hard limit: a run that installs
  nothing can never satisfy a bootstrap that verifies a tool is PRESENT afterwards. openSUSE's
  exits 2 for exactly that reason — an honest "this box is half-provisioned" signal. Neither
  side should bend: weakening the exit removes the one signal an operator needs, and teaching
  the job to tolerate exit 2 masks a genuine abort. The only honest resolution is a run where
  the packages really install.

  **The matrix is derived, not listed.** `scripts/fleet-bootstrap-matrix.py` reads each repo's
  own `bootstrap-test.yml` caller for its `image:` and `prep:`, so the weekly run can never
  drift from what the per-PR gate actually uses — a repo bumping its image is followed with no
  edit in Core. Eight legs today, across seven repos.

  **Advisory: it files an issue, it blocks nothing.** Weekly and network-bound, it asserts
  other people's package archives as much as our own scripts, and a hard gate on that reds
  unrelated PRs whenever a mirror hiccups — which is how these lanes get switched off. It
  reuses `notify-failure-call.yml`, the same posture the other sweeps already take. A run that
  derives zero legs fails loudly rather than passing green, because an advisory gate that
  silently never runs reads as coverage.

  MacBook and Defense are deliberately outside it, and both say so in their own
  `.github/core-gates.txt`: MacBook's `provision()` hard-exits without the Command Line Tools
  and this job is Linux-container-only, and Defense's `fresh-bootstrap.yml` already boots a
  bare image and runs `bootstrap.sh` for real. (#589)

- **The adoption audit now covers the files it could not see: workflows and Makefiles.**
  `audit-core.sh` §5f reports which OS repos have not adopted `lib/bootstrap-lib.sh`'s
  helpers, and it greps `bootstrap.sh` **only**. The identical drift class — Core grows a
  capability, some repos keep a hand-rolled predecessor, nothing notices — lives in the
  workflow and Makefile dimension too, and it went red across four repos on the 2026-08-23
  sync.

  Core's reusable `lint-call.yml` secrets leg states the rule (_one policy file, Core's, so
  no repo can widen its own allowlist_) and passes `-c`. Repos running their own gitleaks with
  no config used the **stock** rule set instead, where `curl-auth-user` matches on
  credential-shaped position rather than content — so the vendored `core/CHANGELOG.md`, which
  documents that very allowlist, was flagged. Core's explanation of the rule read as a
  violation of it, on a sync that carried no credential.

  New §5g makes two claims, kept separate so each can be true alone: every
  `gitleaks dir|detect|git` invocation carries a config flag, and a repo-local
  `.gitleaks.toml` must `[extend]` `core/gitleaks.toml` rather than replace it. A repo that
  needs a distro-specific rule is not doing anything wrong; dropping the fleet's policy to get
  it is. Advisory and skipped when siblings are absent, exactly like §5f.

  The matcher lives in `scripts/lib/common.sh :: _core_gitleaks_policy_hits` and is
  fixture-tested in both directions, because of a trap worth naming: a naive `-c|--config`
  match also fires on the `-c` inside `--exit-code`, which two of the repos in scope actually
  pass. The flag is matched as a whole word, and the test pins it.

- **A gate × repo coverage register — `scripts/fleet-coverage.sh` and `make fleet-coverage`.**
  There was no single place recording which repo satisfies which gate, and how. Coverage was
  inferred by reading the `uses:` lines in each repo's workflows — and that inference is wrong
  for any repo that satisfies a gate its own way.

  It has misfired twice, identically, both times in good faith: dotgibson/dotfiles-MacBook#154
  (the RETURN-trap gate, which had in fact been ported by hand) and #178 (the `provision-stub`
  job, where `provision()` was already gated on the macOS leg via a `BOOTSTRAP_BREW` seam).
  Same failure mode two gates apart, because a rollout audit had no way to distinguish
  _not covered_ from _covered elsewhere_.

  **Derived, not hand-maintained** — the load-bearing decision. The `reusable` cells are read
  from each repo's real `uses:` lines at run time, and the gate list is read from Core's own
  tree, so a new reusable workflow joins the register the moment it exists. Only the cells
  that _cannot_ be derived are declared, in each repo's `.github/core-gates.txt`. This repo
  has been burned by frozen counts before — one commit fixed eleven of them (#519) — and
  `RELEASE-RUNBOOK.md` already set the precedent: _count them rather than trusting a number
  frozen into this doc_.

  `audit-core.sh` §5h asserts every gate × repo cell is filled, so a new gate cannot ship
  without each repo declaring a position on it. Advisory and skipped when siblings are absent,
  like §5f/§5g. Five cells needed a declaration and now have one: MacBook's `lint-call` and
  `bootstrap-test`, Defense's `bootstrap-test` and `claude-routines-call`, and Offense's
  `claude-routines-call`. (#607)

- **core-doctor reports the four integrations Core wires itself: direnv, gh, uv and ty.**
  `_CORE_DOCTOR_WIRED` listed five tools and none of these, so the doctor was silent about
  integrations Core drives directly — it hooks direnv in `zsh/00-tools.zsh` and registers the
  gh/uv/ty completions in `zsh/45-plugins.zsh`. Before those moved into Core they were the OS
  layer's at band 80, and arguably not Core's to report on; they are Core's now.

  All four satisfy the list's own membership rule — a tool belongs there iff its activation
  defines something observable in _this_ shell that `_core_wired` can probe:

  | tool | probe |
  | --- | --- |
  | `direnv` | `_direnv_hook` — the function, or its `precmd_functions` entry |
  | `gh` / `uv` / `ty` | the tool's `$_comps` entry |

  The completion three needed a **different probe shape**, and it is the same scar the
  starship/carapace arms already carry. Their wiring fact is the `compdef` registration in
  `$_comps`, not a defined function: the completion function is autoloaded lazily, so
  `$+functions[_gh]` would report a permanent `○ (idle)` for a correctly registered
  completion. The arms test `$_comps` for non-emptiness rather than for a specific value, so
  the row stays honest when carapace legitimately owns the command.

  **No `HAVE_DIRENV`/`HAVE_GH`/`HAVE_TY` flags, and no presence rows** — decided rather than
  overlooked. `_cache_eval` self-guards on `${commands[…]}`, so nothing would consume such a
  flag; and a `_CORE_DOCTOR_GROUPS` row for gh or ty would render a permanent ✗, because no
  Linux repo's `packages.txt` installs either. Muting that correctly means adding them to
  `_CORE_DOCTOR_OPTIN`, which is derived from `PORTING-MATRIX.md`'s footnote ²¹ and asserted
  against it — a matrix change, not a list edit, and a separate piece of work. (#581)

- **`audit-core.sh` §5i fails when a tracked file carries a leftover conflict marker.**
  `bcdd7dd` (#650) committed a literal base marker into `CHANGELOG.md`, at the end of
  `[Unreleased]`'s Fixed section, and it sat on `main` undetected until #656 tripped over it.
  Under `zdiff3` a conflict has **four** marker lines, not three, and the base one is the half
  that gets missed precisely because it only exists in that style.

  It was not cosmetic. git refuses to parse a conflict region containing a stray marker, so
  rebasing onto the affected `main` produced `error: could not parse conflict hunks in
  CHANGELOG.md`. `CONTRIBUTING.md` requires every user-visible change to touch `[Unreleased]`,
  so one marker there taxed every future branch in the repo.

  Nothing else could see it: `bash -n` / `zsh -n` never read markdown, markdownlint reads the
  line as ordinary paragraph text, and gitleaks is looking for credentials. The marker is
  valid text everywhere — the same reason §5d (pipefail) and §5e (RETURN trap) exist as
  textual scans. The rule lives beside them in `scripts/lib/common.sh ::
  _core_conflict_marker_hits`.

  **It blocks rather than reports**, unlike §5f/§5g. Those arrive red across seven repos, so
  they advise; this tree is clean today (zero hits across every tracked file), so the gate is
  green on arrival and every future hit is a regression introduced by the commit under test —
  the exact condition §5f names for promoting an advisory check to a failing one.

  **No allowlist, deliberately.** The obvious design exempts the files that legitimately
  contain markers — the matcher, the gate, the fixtures. None need it: `common.sh` assembles
  its patterns from fragments (the discipline §5d/§5e already follow) and `test-core.sh`
  writes its fixtures into `$SANDBOX` at run time, so they are never tracked and never
  scanned. A doc that must _show_ a marker indents it by one space; column 0 is what git keys
  on and what the gate keys on.

  **The separator is treated differently.** A bare row of seven `=` is also a setext H1
  underline, which `.markdownlint.jsonc` permits (MD003 defaults to `consistent`, not `atx`),
  so it counts only when the file also carries a marker that names a ref — the same
  file-level precondition idiom `_core_pipefail_hits` uses. The knowing trade-off: a
  resolution that deleted every marker _except_ the separator is not caught. Every marker
  naming a ref always is, and #650 was one of those.

  Fixture-tested in both directions, and that mattered: the first version of the matcher
  **failed open**. `|` is ERE's alternation operator, so a literal row of seven pipes read as
  eight empty alternatives and the scanner reported nothing, on any input — a green gate
  checking nothing. A firing-only test would have passed the broken version too, since it was
  silent on clean fixtures as well. Two of the nine assertions pin the self-reference property
  outright, so the matcher can never start reporting its own source.

### Changed

- **The reusable lint workflow's markdown leg is now BLOCKING.** It shipped advisory in
  v4.16 for one release cycle, for the reason any new leg has to: callers pin the moving
  `@v4` tag, so every repo sees a new gate the moment auto-tag moves — before a maintainer
  can act on anything it reports.

  The backlog was measured, not assumed. Eight of the nine fleet repos carried findings —
  **162 in total**, roughly 130 of them MD060 (table pipe alignment). All nine were cleared
  first, and the flip landed only once `markdownlint-cli2` was green on every one, so no
  repo is red on arrival.

  The `if/else` that swallowed the exit is gone. Two things are deliberately unchanged: the
  `command -v markdownlint-cli2 || exit 1` guard, which matters _more_ now rather than less
  — exiting 127 because the linter is absent and exiting 1 because it found issues are
  different facts, and only the second is the caller's to fix — and `working-directory:
  caller`, without which markdownlint would walk up and silently apply **Core's**
  `.markdownlint.jsonc` to the caller's files instead of the caller's own. (#592)

- **`uv`'s 6,976-line completion is no longer sourced on every shell — it autoloads from
  `fpath`.** `_cache_eval` turns a generator into a cached file and then `source`s that file
  on every interactive shell. That is the right shape for `direnv` (14 lines) and `gh` (212).
  It is the wrong shape for `uv`, whose cached completion is 6,976 lines read into every shell
  to serve a completion most shells never invoke.

  Measured here with `hyperfine`, against a compinit-ready baseline of 4.7 ms:

  | | mean |
  | --- | --- |
  | baseline (compinit only) | 4.7 ms ± 0.3 |
  | shipped: `source` gh+uv+ty every shell | 40.2 ms ± 2.1 |
  | this change: `fpath` autoload | 5.0 ms ± 0.3 |

  So the per-shell cost of these three drops from **+35.5 ms to +0.3 ms**.

  `clap_complete`'s output is already built for this — it opens with `#compdef <tool>` and
  closes with the standard autoload shim — so the new `_cache_completion` helper writes it to
  `$XDG_CACHE_HOME/zsh/completions/_<tool>` instead of sourcing it. It keeps `_cache_eval`'s
  two load-bearing invariants verbatim: `${commands[…]}` for a fork-free probe that stays
  silent on a box without the tool (which is why these callers still need no `HAVE_*` flag),
  and the binary-mtime regeneration key.

  Three things this had to get right, all of them silent if wrong:

  - **`fpath` must be populated before `compinit` scans it.** Generation therefore moves from
    band 45 to band 00; `compinit` is band 10.
  - **The cached compdump hides new files.** `compinit -C`, taken whenever the dump is under
    24 h old, skips the scan for new completion functions entirely — so a freshly written
    `_uv` would be invisible for up to a day. A regeneration now deletes the dump, which
    works precisely because band 00 precedes band 10: that shell pays one full `compinit`,
    every later shell keeps the fast path.
  - **carapace must not win the command back.** carapace bridges `gh` among hundreds of
    others, and the last `compdef` owns the command. Autoloading registers at band 10, i.e.
    _before_ carapace at band 45 — so a three-line `compdef` re-assert stays at band 45,
    after carapace, exactly where the sourced version used to be. `compdef` only rebinds a
    name; it does not read the 6,976 lines, so this costs nothing.

  The negative cache for a generator that cannot succeed is a `.<tool>.failed` dotfile rather
  than `_cache_eval`'s comment-only stub: any file named `_uv` in `fpath` **is** a completion
  function, so a stub would register an empty completion and shadow the bridged one that
  would otherwise have served. `compinit` only scans names beginning with `_`, so the dotfile
  converges without being visible to the completion system.

  A side benefit: band 45 is profile-gated (`minimal` ceils at 30, `standard` at 50), so these
  completions did not exist at all under those profiles. Generated at band 00 and registered
  at band 10, they now do.

  The old `$XDG_CACHE_HOME/zsh/{gh,uv,ty}.zsh` caches are left behind, unused and harmless;
  delete them to reclaim the space. (#579)

- **`bootstrap-test.yml` now tells you how to choose `packages_check`'s probe, because the
  obvious command is wrong on most distros and both ways it is wrong look healthy.** The
  header documented the input as `packages_check: apk info` and said nothing else. That is
  Alpine's correct answer and a trap as a template — wiring the same shape into four OS
  repos surfaced two distinct failure modes, each of which produces a gate a reviewer would
  sign off on.

  A name-exact probe raises FALSE ALARMS. `bootstrap.sh` installs these names with the
  package manager's install verb, which honours Provides, so the probe has to ask the same
  question. Fedora retired `wget` for `wget2` with `wget2-wget` carrying `Provides: wget`,
  so `dnf install wget` works while `dnf info wget` fails; on Arch `sh` is a `provides` of
  bash, not a package; on openSUSE `python3-pip` is satisfied by a versioned
  `python3XX-pip`. Worse, such a list can pass today and break later: none of Arch's ~45
  names sat behind a `provides` when this was wired, so the name-exact probe was green and
  would have gone red on some future PR that had nothing to do with it.

  A probe that never rejects gives FALSE CONFIDENCE. `apk policy` and `zypper info` both
  exit 0 for a name that exists nowhere — a gate that cannot fail, indistinguishable from
  real coverage. So a green run is not evidence on its own; the header now prescribes the
  negative control that is (a scratch list holding one real name, one provides-only name,
  and one bogus name, which must go red naming only the bogus one).

  The note carries the four probes verified against both rules, and two adjacent traps the
  same exercise turned up: a path-filtered caller that omits `install/**` gets a
  package-list gate that cannot fire on a package-list change, and prep must leave the
  index readable — Alpine's `apk add --no-cache` deliberately leaves none.

  Docs only; no behavioural change to the workflow.

### Fixed

- **`CHANGELOG.md` contained a credential-shaped string that tripped stock secret scanners.**
  The v4.x entry documenting `gitleaks.toml` quoted, in a code fence, the exact healthcheck
  line the allowlist was written for. That put a credential-shaped token in a public file
  vendored into every consumer — so any repo scanning the vendored tree under the stock rule
  set flagged this paragraph, and four did.

  The example is now described rather than quoted, which loses nothing: the point was always
  the _shape_, and the prose states it. Verified with the pinned gitleaks 8.30.1 — the
  vendored tree scanned under stock rules reports **1 leak before, 0 after**. This removes the
  hazard for every downstream scanner rather than requiring all nine to opt into the policy,
  and it is independent of the audit work above. (#623)

- **`bootstrap-test.yml`'s header claimed no gate in the fleet runs `provision()` — false in
  two directions.** The block stated, in capitals, that `--links-only` returns before
  `provision()` and "NO GATE IN THE FLEET RUNS provision() AT ALL". That was true when it was
  written and has not been since v4.14.2, which added the opt-in `provision-stub` job to this
  very file ~200 lines below the claim. It is also false the other way: `dotfiles-MacBook`
  executes `provision()` on its `macos smoke` leg via `make test-repo` through a
  `BOOTSTRAP_BREW` seam, gated by `REPO_TESTS_GATE_PROVISION=1` so the leg cannot quietly
  stop gating.

  This header is the most-read description of what the fleet does and does not cover, and it
  is vendored into every repo — so a stale absolute keeps generating issues filed in good
  faith against it (dotgibson/dotfiles-MacBook#178 was filed on exactly this premise). The
  same sentence was repeated in `lint-call.yml`'s RETURN-trap note, so fixing one file alone
  would have left it in the fleet; both are corrected.

  The rewrite also states the macOS absence as a **decision rather than a gap**:
  `bootstrap-test.yml` is Linux-container-only, and a `provision()` that hard-exits without
  the Command Line Tools can only reach one branch there — so a repo in that position gates
  it in its own CI instead. And it names the non-obvious part: the two approaches are
  complementary, not redundant. Core's shims always succeed, so failure branches stay
  unexercised; MacBook's stub always fails, so it covers exactly those branches. (#606)

- **`make sync` vendored onto whatever the local clone happened to be — no staleness guard.**
  `sync-core.sh` had a dirty-tree guard ("uncommitted work?") and nothing that asked "current
  with the remote?". So a sync materialized `core/` onto a stale base, reported
  `updated 9 / failed 0`, and the operator found out at `git push` — nine repos already
  committed to, every push rejected as non-fast-forward. Observed on the 2026-08-23 sync with
  all nine between 1 and 5 commits behind.

  There is now a **pre-flight** check: each target's remote is fetched and its behind-count
  read before the fan-out loop mutates anything. Ahead is fine (unpushed local work); only
  behind refuses. A repo with no `@{upstream}` has no counterpart to be behind and is passed
  over in silence, and an unreachable remote is reported but does not refuse — this guard
  exists to catch a stale clone, and a network blip is a different failure.

  The refusal names the **correct** recovery, which is the non-obvious part. Rebasing the sync
  commit is not it: materializing `core/` replays safely because it is fully determined by the
  Core SHA, but `_sync_pin_workflows` is a `sed` over the target's _own_ existing workflow
  files, so a replay computed against a tree that no longer exists can apply cleanly and still
  be wrong. The correct fix is to bring each repo up to date and re-run the sync, which is
  idempotent by design.

  Applied to `--dry-run` too, and placed before the audit gate, for the same reason as the
  existing `unknown`-commit refusal: a rehearsal that would refuse should say so, and it should
  not cost a full audit first. Escape hatch: `SYNC_SKIP_STALE=1`. (#622)

- **The hand-vendoring instructions said `main`; the fan-out deliberately pins the released
  commit.** Three docs and the scaffolder told a human to
  `git subtree add --prefix=core <core-remote> main --squash`, while `sync-fanout.yml` states
  the opposite in as many words: each PR vendors the exact commit the tag points at
  (`CORE_BRANCH=<sha>`), so `core.lock` records that commit and `git describe` stamps the
  named tag.

  That contradiction bites. `core-integrity` validates `core/` against the commit `core.lock`
  records, so a tree vendored from whatever `main` happened to be is not that commit — a
  freshly hand-vendored repo could fail its own tamper check before it had done anything
  wrong. `dotfiles-MacBook` hit exactly this and corrected its own copies, two of which were
  live error paths printed by `bootstrap.sh`; the copies inside the vendored subtree could
  not be fixed downstream, because the next sync overwrites them.

  `ARCHITECTURE.md`, `PORTING-MATRIX.md` and `VENDORING.md` now point at `refs/tags/v4` and
  name the `core.lock` step that `subtree add` does not perform. `new-os-repo.sh` defaults
  `CORE_BRANCH` to `refs/tags/v4`, and the README it generates no longer suggests a raw
  `git subtree pull` — the stale-lock path `VENDORING.md` warns about, and a model #587
  abandoned outright.

  `sync-core.sh`'s own `CORE_BRANCH` default stays `main` on purpose: the fan-out always
  overrides it, and `main` is the right default for a maintainer's ad-hoc `make sync`. It is
  now documented as such, with the first-time-vendoring case called out. (#588)

- **The `mise` steps in the daily maint runner are no longer unbounded.** `brew`, `nvim` and
  `rustup` each run under `_to`; the three `mise` calls did not, so a hung one had nothing to
  cut it short and the whole unattended run stopped there. The new `MAINT_MISE_TIMEOUT`
  (default `2700`, applied per step like `MAINT_BREW_TIMEOUT`) closes that.

  It is deliberately the largest knob in the file, because a `mise` step is the only one that
  _compiles_. On musl, mise flips `all_compile` to true by default — every precompiled runtime
  it would otherwise fetch (nodejs.org's tarballs, python-build-standalone, the `jdx/ruby`
  prebuilts) is glibc-linked and cannot run there — so on Alpine node/python/ruby are built
  from source on every version bump, and node alone is tens of minutes. 2700s is sized for
  that build, not for a download — a cold node 24 build on a 32-core musl box was still in V8
  past 21 minutes, so a lower ceiling would trip on the healthy path and turn every LTS bump
  into a logged failure. On a glibc box the same steps unpack a binary and never come near the
  ceiling, so the value costs those boxes nothing.

  `mise outdated --bump` is now bounded too, and needed the `_pkgcount` treatment to go with
  it: that probe hits the network, and a registry that accepts the connection and then stalls
  yields **empty output**. The old bare `[[ -n "$bump" ]]` read that emptiness as the happy
  path and logged "all runtimes current within their pins" — asserting a fact nothing had
  measured, the exact failure the `_pkgcount` comment block was written about. The rc is now
  captured and any non-zero reports as `bump check UNAVAILABLE` instead of masquerading as
  good news, with the rc included so the log can distinguish the causes after the fact.

  That gate is **stricter than `_pkgcount`'s, deliberately** — the two are not meant to
  converge. `_pkgcount` can only test _how the probe died_ (124, or `>=128` for a signal,
  which is how busybox `timeout` reports its own SIGTERM as 143) because the managers it
  wraps overload exit status to mean things: `dnf check-update` exits 100 when updates exist,
  `pacman -Qu` exits non-zero when there are none. A general non-zero gate would report
  "unknown" on their healthy path. `mise outdated` overloads nothing — 0 whether or not bumps
  exist, non-zero only on a real failure — so a fast hard failure (a 500 from the registry, a
  mise that died on a broken config) is just as much "we got no answer" as a stall, and is now
  reported that way rather than falling through as good news. (#641)

- **Three `INSTALL:` lines claimed a mise pin without saying which fleet they meant.** (#642)
  "mise pins ruby" / "mise pins temurin-21" are all true here — `mise/config.toml` pins
  `ruby = "3.4"` and `java = "temurin-21"`. These were never stale comments; they were
  **unqualified** ones, silently assuming a mise-managed Unix box. That is exactly the
  assumption an `INSTALL:` line exists to make explicit, and `nvim/` is the one Core tree
  `dotfiles-Windows` vendors — a host with neither pin.

  `ruby_lsp.lua` is where it had teeth. On Windows ruby is winget-owned and ships no MSYS2
  DevKit, so every C-extension gem fails to build and `ruby-lsp` (with `rubocop`) dies on
  `prism` with an error naming neither ruby nor the missing toolchain:

  ```text
  make: *** No rule to make target '/C/Ruby40-x64/include/ruby-4.0.0/ruby.h' ...
  ```

  A reader following that line went hunting for a mise pin that will never exist there, while
  the one thing that unblocks them — an elevated `ridk install 1 3` — went unmentioned.

  `jdtls.lua` and `kotlin_language_server.lua` misled without breaking: Windows gets a JDK
  either way, just scoop-owned **openjdk25** rather than mise's temurin-21 — a different owner
  _and_ a different major, both of which satisfy the servers. Their qualifiers are one clause
  each, proportional to the stakes; ruby's earns the longer note.

  All three now name the fleet they describe. `intelephense.lua` already modelled this by
  stating its negative case outright ("mise does NOT pin"). Comment-only; no behaviour change,
  and nothing here reads the text. (`nvim/lua/gerrrt/servers/ruby_lsp.lua`,
  `nvim/lua/gerrrt/servers/jdtls.lua`, `nvim/lua/gerrrt/servers/kotlin_language_server.lua`)

- **rubocop linting and formatting were silent no-ops on Windows — every signal said healthy.**
  (#646) `nvim-lint` and `conform` both pass `--server` to rubocop, and RuboCop's server mode
  needs fork/UNIX sockets. A native-Windows ruby prints
  `RuboCop server is not supported by this Ruby.`, writes **nothing** to stdout, and **exits 0**:

  ```text
  $ rubocop --format json --force-exclusion --server --stdin main.rb
  RuboCop server is not supported by this Ruby.
  $ echo $?
  0
  ```

  The zero exit is what made this invisible. nvim-lint parsed an empty payload, found no offenses,
  and had no non-zero status to complain about — nothing in `:messages`, nothing through
  `vim.notify`, and `:ConformInfo` still reported rubocop `available` because the binary really is
  installed. Ruby buffers simply went unlinted and unformatted. `ruby_lsp` masked it further: its
  own Prism diagnostics still appear, so a Ruby buffer shows _a_ diagnostic, just never a rubocop
  one.

  Both specs now strip `--server` behind a `vim.fn.has("win32")` guard — the idiom `health.lua`,
  `nvim-dap.lua` and `blink-cmp.lua` already use. The Unix fleet keeps it, where it is a genuine
  speedup rather than a no-op. Both overrides **filter** the upstream arg list instead of restating
  it, so an upstream change cannot silently drift past them; conform's resolves lazily at format
  time so the builtin module is not required during lazy-spec evaluation.

  Verified on the host that has the problem (Ruby 4.0.6 x64-mingw-ucrt, rubocop 1.89.0 from Mason)
  by vendoring the patched files into `dotfiles-Windows` and running headless: rubocop diagnostics
  went 0 → 4, matching the CLI exactly, and conform's format went from leaving the buffer untouched
  to actually rewriting it. Windows receives this on its next `nvim-sync.ps1`.
  (`nvim/lua/gerrrt/plugins/nvim-lint.lua`, `nvim/lua/gerrrt/plugins/conform.lua`)

- **`Ctrl+\` (toggle autosuggestions) was dead inside tmux — which is every shell.**
  `zsh/40-bindings.zsh` binds `^\` to `autosuggest-toggle`, and `tmux/scripts/tmux-cheat.sh`
  advertises it by name. It never fired. `vim-tmux-navigator` binds **five** keys at the tmux
  ROOT table, not four: `C-h/j/k/l` plus `C-\` → `select-pane -l`. That fifth binding forwards
  the key to the pane only when the pane is running vim/fzf; a shell pane is neither, so tmux
  consumed `C-\` and zsh never saw the byte. Since every OS repo's `zshrc` `exec tmux` on login,
  the key was dead in essentially every shell on every box in the fleet.

  The zsh half was never the problem, and is unchanged — a PTY driven through the full config
  shows `main` aliased to `viins`, `"^\\" autosuggest-toggle` bound, the widget present, and
  `_ZSH_AUTOSUGGEST_DISABLED` flipping `0 → 1 → 0` on two `0x1C` bytes. The 40-bindings comment
  about binding it unconditionally (the widget is deferred, so a `$+widgets` guard would always
  be false) remains correct.

  `tmux/tmux.conf` now sets `@vim_navigator_mapping_prev ''`, which disables that one mapping
  and leaves `C-h/j/k/l` — the reason the plugin is here — untouched. Dropping the plugin's side
  rather than moving zsh's is what the rest of the tree already assumed:
  `nvim/lua/gerrrt/plugins/vim-tmux-navigator.lua` maps only `<C-h/j/k/l>` and deliberately never
  mapped `<C-\>`, so `TmuxNavigatePrevious` was a lazy `cmd` bound to nothing. "Previous pane"
  was half-wired; the autosuggest toggle is documented.

  An empty value is the plugin's off switch: its `get_tmux_option()` falls back to the default
  only when `show-options -gq` prints nothing, and a defined-but-empty option prints its own
  name — so the value resolves to `""` and the `for k in $(echo "")` loop never runs. Verified
  end-to-end on tmux 3.7c: root `C-\` disappears, `C-h/j/k/l` survive, and a PTY client attached
  to a server carrying this conf toggles the suggestion on `Ctrl+\`.

  The option **must** stay above the trailing `run '…/tpm'` — tpm sources the plugin's `.tmux`
  script, which reads it at that moment — so `scripts/test-core.sh` pins the value, the
  emptiness, and the line order, in the same spirit as the gh/carapace order in `45-plugins.zsh`.

## [v4.17.0] - 2026-08-24

### Added

- **The CI floor gains rule 7: no attacker-controlled expression may be spliced into a
  `run:` body.** A `${{ }}` expression is substituted by the _runner_, textually, before the
  shell ever parses the script — so a PR title or a branch name is not data at that point,
  it is source code. The remedy is to route it through `env:` and read `$VAR`, which the
  shell treats as a value.

  The fleet already does this everywhere, and says so at the call sites — `auto-tag-call.yml`
  spells out that "caller-supplied values reach the script through the ENVIRONMENT, never
  spliced into the `run:` body", and `notify-web-call.yml` states the same. But a comment is
  not a gate: nothing stopped the next reusable workflow from splicing
  `${{ github.event.pull_request.title }}` straight into a shell block. `actionlint`, which
  the audit already runs, has no equivalent rule, so this was a real gap in current coverage.

  `banned_run_interpolation_contexts` in `modern-baseline.yml` lists `github.event.`,
  `github.head_ref`, `github.actor` and `github.triggering_actor`. `inputs.` is deliberately
  absent: `setup-core-tools/action.yml` interpolates `${{ inputs.bindir }}` inline in ~8
  `run:` steps, and that is a first-party composite input — banning it would be a fix-first
  migration for no security gain.

  Enforcement is the same block-scalar walk rule 6 uses for the checkout/`with:`
  association: find the `run:` key, take its column, and treat every more-indented line as
  body until the first non-blank dedent. Matching happens _inside_ each `${{ … }}` span
  rather than against the raw line, so a context name appearing in prose beside a step is
  not a false fire. Scoped to workflows _and_ composite actions, since a composite's `run:`
  is the same hazard.

  Green on the current tree with no workflow edits. (#521)

- **`core-doctor` now says when a tool is present but Core never wired it.** A `✓` used to
  read as "Core wired this" when all it ever meant was "this is on `PATH` right now" — and
  the difference was invisible.

  Every `HAVE_*` flag is decided at band 00, against a `PATH` that keeps changing afterwards:
  `mise activate` registers a `chpwd` hook that rewrites it on every `cd`, `80-os.zsh` loads
  at band 80, an `85-*` role fragment at 85, and `99-local.zsh` — the user's own escape hatch
  — at 99. A tool contributed by any of them gets no flag, no alias and no shell init. The
  doctor, which probes live against the finished `PATH`, reported it `✓` anyway.

  Such a row now renders `✓ procs⚠` plus a `not wired` block that names the tool **and the
  directory that joined late**, which is what makes it actionable — the remedy is to move
  that prepend into `00-tools.zsh`'s bindir list. Where the directory was already there, the
  tool was simply installed after the shell started, and the message says so instead.

  `⚠` is a **modifier on `✓`, not a fourth presence glyph**: the tool genuinely is present,
  so `✓` is not wrong. That keeps the legend's three states intact, and keeps the
  render⇄JSON parity test blind to it by construction.

  `--json` gains `detection.ran` / `detection.missed`. Named `detection`, not `wiring`,
  because it sits beside `wired` — which answers the unrelated question of whether an
  integration registered its hooks — and a consumer reading both would conflate them. The
  gate is `jq -e '.detection.missed == []'`.

  **How it is recorded matters.** The obvious approach — have `core-doctor` parse
  `00-tools.zsh`'s `_have <tool> && HAVE_<X>=1` lines at runtime — handles only the
  flag-_name_ irregulars (`ast-grep`→`HAVE_ASTGREP` but `git-absorb`→`HAVE_GIT_ABSORB`, three
  lines apart) and is blind to every probe that does not take that shape: the `fd`/`bat`
  ladder, the derived flags, the `git-absorb` exec-path backfill. It would need those special
  cases anyway, plus a parser, plus logic to locate the file at runtime in a vendored tree.

  So `_have` records its own verdict instead, into a `_CORE_PROBED` ledger keyed on the
  canonical tool name — which makes every irregular disappear. It stores `0` as well as `1`,
  because "Core probed this and said no" must be distinguishable from "Core does not probe
  this tool at all", or every row the doctor knows and `00-tools.zsh` does not would
  false-positive. Cost: ~45 array stores at startup, no forks, no stats — the zero-fork
  contract is untouched.

  Two gates keep it honest: no ledger at all means band 00 never ran in this shell (a script,
  `zsh -c`, the unit harness) and **no claim is made**; no entry for a row means Core does not
  probe it, and again no claim. Both are checked in the render and in `--json`, so the two
  renderers cannot disagree about whether the axis applies.

  `05-ui.zsh`'s `_core_have` is deliberately **not** merged with `_have` despite an identical
  body, and now says so: it is the live probe the doctor itself calls, so recording there
  would write the doctor's own lookups into the ledger and make every row it probed report as
  wired — exactly the false `✓` this exists to expose. (#545)

### Fixed

- **`_cache_eval` now converges on a generator that produces nothing.** It decided whether a
  cache was usable on `-s` alone — "the file is non-empty" — and wrote the generator's output
  straight at the destination with `>|`, which truncates _before_ the generator runs and never
  looks at its exit status. Two failure modes followed, and both were invisible:

  - **Generator exits 0 and prints nothing** → a 0-byte cache. `-s` then fails forever, so the
    _next_ shell regenerates, and the next. The cache never converges: every interactive shell
    pays a fork for a tool that is permanently un-cached, with no error, no output and nothing
    in the prompt to show for it.
  - **Generator prints part of a script and then dies** → the cache is non-empty _and_ newer
    than the binary, so **both** halves of the freshness test go false and a truncated init is
    sourced on every shell from then on. That one never self-heals.

  The silence is not incidental. `2>/dev/null` on the generator is deliberate and correct — a
  generator's chatter must never be sourced into the shell — so the "command not found"-shaped
  signal is discarded by design, and the file is all that is left to judge by.

  Now the output goes to a temp file and is installed only if the generator **exited 0, wrote
  something, and the result parses** (`zsh -n`, the same "prove it parses before you keep it"
  discipline `update-plugins.sh` applies to a rolled plugin pin). A generator that breaks after
  a good cache existed keeps the last good cache — degrading a working shell because a
  generator regressed is strictly worse than serving yesterday's completions — and the cache is
  touched so the mtime half stops re-firing. With nothing good to fall back on, a comment-only
  negative cache lands: valid zsh, sources to a no-op, and non-empty, so the per-shell fork
  stops. It regenerates when the binary's mtime moves, which an upgrade does.

  The `zsh -n` fork is paid on the regeneration path only — once per tool per upgrade, not once
  per shell — and is skipped where `zsh` is not on `$PATH` rather than failing every
  regeneration.

  **Why now:** the trigger is a renamed or removed generator subcommand, and `_cache_eval`
  gained three new callers in #578 — one of them `ty`, a pre-1.0 type checker whose
  `generate-shell-completion` is exactly the CLI surface that gets renamed before 1.0. Eleven
  tools reach this path, counting the `brew shellenv` / `pyenv init` callers OS repos add
  through the documented Core→OS API.

  The suite gains five fixtures, each running the same shell **twice** — one run cannot tell
  "regenerated once" from "regenerates forever", and forever is the defect. Four of the five
  fail against the previous implementation. (#580)

- **The banned-runner rule was silently missing the `-arm` / `-large` / `-xlarge` variants.**
  This was a defect in a rule the floor already declared, not a new floor. The label class
  that terminates the match contains no hyphen, so with `ubuntu-22.04` in `banned_runners`,
  `runs-on: ubuntu-22.04-arm` did **not** match — the `-` fails every alternative. Same for
  `macos-14-large` and `macos-14-xlarge`.

  That matters because GitHub names those exact labels in the same deprecation notices as
  their base images: `runner-images#14254` lists `ubuntu-22.04` **and** `ubuntu-22.04-arm`;
  `#13518` lists `macos-14`, `macos-14-large` and `macos-14-xlarge`. The list was right; the
  matcher was leaky, and had been since the floor was written.

  Fixed by matching an optional variant suffix rather than adding six more list entries —
  that keeps `banned_runners` reading as one label per image and covers every present and
  future variant of every label on it, including ones added later. (#521)

- **`check-modern.sh` gains its first behavioural coverage.** Every rule was previously
  only "green on this tree", which cannot distinguish a rule that _passes_ from a rule that
  never _matches_ — and rule 2 was in exactly that state. The new fixtures build a throwaway
  git repo (the gate inventories through `git ls-files`, so a plain directory yields "no
  workflow/action files to check" and every assertion would vacuously pass) and assert both
  directions: that each rule fires on the violating shape, and that the prescribed remedy,
  `inputs.*`, and `if:`/`env:`/`concurrency:`/`with:` contexts do **not** fire. Both new
  rules' fixtures fail against the previous script. (#521)

- **`clip`'s OSC 52 fallback was unreachable from the one tmux binding that names it.**
  `bin/clip`'s header claimed tmux needed no special handling, because `set-clipboard on`
  makes tmux consume a pane's OSC 52 and forward it. That is true for a **pane** process —
  nvim, `optoken`, the cheat popup. It is not true for the yank binding:

  ```text
  tmux.reset.conf:  bind -T copy-mode-vi y  send -X copy-pipe-and-cancel "clip"
  ```

  `copy-pipe` runs its command through tmux's `job_run()` — a child of the **daemonized
  server**, which has called `setsid()` and has no controlling terminal, and whose stderr is
  `dup2`'d to `/dev/null`. So the `/dev/tty` open fails with `ENXIO`, the error message goes
  nowhere, and `clip` exits 1 in silence.

  Prefix-`y` still copied only because `window_copy_copy_pipe()` also calls
  `window_copy_copy_buffer()`, which under `set-clipboard on` emits its **own** OSC 52 from
  the server side. That is tmux covering for us, not `clip` working — so the comment credited
  the wrong mechanism, and the next person to touch `set-clipboard` would have lost copy-out
  on exactly the headless box the fallback was written for, with an in-file comment saying it
  was handled.

  `_osc52_copy` now falls back to `tmux load-buffer -w -`, which reaches the client from the
  **server** side and needs no tty at all. The raw payload is reconstructed by decoding the
  base64 rather than being stashed on the way in: a shell variable is not binary-safe
  (command substitution strips trailing newlines and cannot carry a NUL), and a temp file
  would add `mktemp`/`cat`/`rm` to a path that runs on the most minimal boxes we support —
  and would put a TOTP on disk, since `optoken` pipes one through here. Verified byte-exact
  for tabs and trailing newlines.

  The large-payload write-splitting hazard is now stated in the file rather than left
  implicit: writing to a character device is line-buffered and the sequence contains no
  newline, so a payload past `BUFSIZ` leaves as several `write()` calls on a tty the
  foreground TUI also owns.

  New fixtures reproduce the real shape with `setsid` — the only faithful reproduction, since
  a redirected or closed stdin does not detach the controlling terminal — and skip on macOS,
  which has no `setsid`. Both fail against the previous `bin/clip`. (#525)
- **`tmux-cheat`'s `copy()` discarded `clip`'s exit status,** so a failed copy was completely
  silent. It now propagates, and the caller reports through `tmux display-message` rather
  than stderr: the script runs under `display-popup -E`, which tears the popup down the
  instant the command exits, so anything on stderr is painted and destroyed in the same
  frame. (#525)
- **`optoken` overclaimed.** OSC 52 succeeds as soon as the escape is **written**, not when a
  terminal accepts it — clipboard writes are refused by default in several emulators and
  unimplemented in others, and the failure is a silent drop. The message is now "TOTP sent to
  the clipboard". The function also now documents a disclosure its own rationale did not
  cover: under `set-clipboard on` tmux accepts the escape **and** creates a tmux paste
  buffer, so the code is readable via `tmux show-buffer` by anything that can reach the tmux
  socket — which "never lands in your shell history/scrollback" does not address. (#525)

- **`make sync` vendored the branch tip while stamping the SHA it resolved ~250s earlier.**
  `sync-core.sh` resolves Core's tip once, up front, then runs the pre-fan-out audit, then
  vendored by re-resolving the **branch**. Those are two different resolutions of `main`. A
  push to Core inside that window — a docs PR merging, say — gave `core/` the newer tree
  while `core.lock` recorded the older SHA, and `make core-integrity` then reported the repo
  `TAMPERED (core/ edited since sync)`. For a tree nobody hand-edited. The diagnosis pointed
  at the wrong thing entirely, which is the part that cost the most time. Reported firing
  three times in a single afternoon.

  The fix pins everything to the commit that was resolved: the fetch asks for that SHA
  (falling back to a ref fetch purely as an object-delivery mechanism on remotes that refuse
  unadvertised wants), and the tree is materialized as `<sha>^{tree}` — never `FETCH_HEAD`,
  which is by definition the new tip and would have re-created the bug inside its own fix.

  A serial fan-out is now consistent **by construction**: every repo materializes the same
  commit however long the loop takes. And a warm repo needs no network at all, because the
  fetch short-circuits on `cat-file`, which makes a re-run of the same sync fully offline.

  Two further instances of the same bug are fixed with it, neither of which was in the
  report:

  - **`core_tag`** was resolved with a `|| git describe "$CORE_BRANCH"` fallback that
    re-resolved the branch at describe time — so a moved branch stamped a tag belonging to a
    **different commit**, into `core.lock` _and_ onto every rewritten workflow pin comment in
    all nine repos. That comment is what Renovate reads to pick the next bump.
  - **The `git-subtree-split:` trailer** was stamped from the same stale snapshot. Consumer
    tooling (`dotfiles-MacBook`'s `verify-core`) warns when it disagrees with the lock, so
    the fleet was emitting a wrong marker too.

  And the `unknown` path turned out to be a third producer of the identical symptom, with no
  race required: it materialized `core/` from the branch and then skipped writing `core.lock`
  entirely. A sync must vendor a **named** commit, so that now refuses outright, before the
  audit and before anything is written. Two latent defects on that path are fixed as well —
  an unreachable remote killed the script at `set -e` with exit 128 and **no output at all**
  (`ls-remote`'s stderr is deliberately suppressed), and the bare `git rev-parse` fallback
  echoed the unresolvable ref to stdout, so the `unknown` sentinel it was tested against
  could never actually be produced by that path.

  The sync now **checks its own work**: after each repo it compares `HEAD:core` against the
  pinned tree. That comparison moved into a new shared `scripts/lib/core-lock.sh` so the
  producer's self-check and `core-integrity.sh`'s verdict are one implementation — two would
  let a sync pass its own assertion and still be reported dirty. It reports and buckets the
  repo as failed rather than exiting, because `sync-fanout.yml` runs the script under
  `bash -e` and an abort would deny PRs to every repo that synced correctly; and it prints
  the recovery command rather than auto-reverting, since on the idempotent path no commit was
  made and a blind `reset --hard HEAD~1` would destroy a good one.

  `sync-fanout.yml` gains the matching post-condition. Its three existing ones all compare
  the **lock to the intent**; none looked at what `core/` actually contained, which is the
  axis this bug broke.

  The audit gate now compares **full** SHAs — `rev-parse --short=12` returns _more_ than 12
  characters when 12 would be ambiguous, a latent spurious refusal that grows more likely as
  history does — and the parallel prefetch is pinned too, picking up the `--no-tags` it was
  missing (without it every prefetch dragged Core's whole tag namespace, including the moving
  `v4` alias, into every OS repo).

  Twelve new fixtures. The race is reproduced **deterministically**, with no sleeps, by
  having the stub audit push to Core mid-run — the audit gate is the one place guaranteed to
  sit inside the window. It runs three ways: direct-SHA fetch, with `allowReachableSHA1InWant`
  **off** so the fallback is exercised (the case that catches a `FETCH_HEAD`-based fallback),
  and with the parallel prefetch on. `core-integrity.sh` also gains its first behavioural
  coverage, since extracting its classifier could otherwise have changed the verdict
  silently. All three race fixtures fail against the previous implementation. (#556)

- **`op` had this bug, inside the doctor's own inventory, behind a test comment asserting it
  could not.** The coverage guard excused `op` on the grounds that "the doctor probes it live
  and no alias or function is gated on it". That was false: `50-op.zsh`'s `command -v op`
  guard gates **four** verbs — `opsecret`, `openv`, `optoken`, `opssh` — and band 50 still
  runs before `80-os.zsh`, an `85-*` role fragment and `99-local.zsh`.

  `op` now records into the ledger too, and with `fd`/`bat` recording under their canonical
  names, **the guard's exemption list is empty** — a list that had grown to three entries,
  one of them wrong, now has none. (#545)

- **The atuin daemon guard now probes a candidate list, not one path — before upstream moves
  it.** atuin PR #3910 (merged 2026-08-12, shipping in **18.20.0**) changes the default daemon
  socket for `systemd_socket = false` — the shape Core recommends — from
  `$XDG_RUNTIME_DIR/atuin.sock` (falling back to the data dir where that is unset) to
  **`$TMPDIR/atuin-$UID/atuin.sock`**. `systemd_socket = true` is unchanged.

  atuin's own client gained a legacy search list so it can still reach an older daemon.
  `_core_atuin_daemon_guard` had none: it resolved exactly one expression. On 18.20.0, with
  the plain always-running unit Core recommends, the daemon would bind the new path, `zsocket`
  would fail, and **every shell would export `ATUIN_DAEMON__ENABLED=false` at its first precmd
  and unhook the watchdog — permanently, with no warning**, because
  `_CORE_ATUIN_DAEMON_WAS_UP` is never set on that path. It fails in the cheap direction
  (history still lands; only the lock relief is lost), which is exactly why it would have gone
  unnoticed on every systemd machine at once.

  The guard now tries the 18.20.0 default first, then the two legacy locations, stopping at
  the first that answers — the same shape as the `git-absorb` exec-path loop, so the zero-fork
  discipline is intact. An explicit `ATUIN_DAEMON__SOCKET_PATH` still wins outright and probes
  nothing else, because a config knob that silently got second-guessed would be a worse bug
  than the one this fixes.

  **The cost, stated rather than hidden:** a genuinely-absent daemon now pays N failed connects
  per probe instead of one. Each is ~0.06–0.10 ms (measured in this file's own bench), the
  probe is throttled, and the degrade is one-way — so such a box pays it at most twice before
  unhooking for good.

  Verified independently against upstream rather than taken from the scout's report: 18.19.0
  is still the newest **stable** release, so this lands with roughly a release of lead time.
  The anchors stay at `18.19.0` — bumping them asserts a measurement nobody has taken yet, and
  that needs an on-box `atuin daemon start && ss -lx | grep atuin` against an 18.20.0 beta.

  Three prose claims that the change falsifies are corrected with it (`atuin/config.toml`,
  `PORTING-MATRIX.md`, and the socket-path note in `bench-atuin-daemon.sh`), and two harness
  bugs it would have introduced are fixed:

  - `bench-atuin-daemon.sh` **printed** a ✓ beside a hand-copy of the guard's single
    expression. That is prose, and it would have kept printing ✓ while the guard and atuin had
    drifted apart — the one failure the check exists to catch. It now **asserts** membership of
    the candidate list and fails loudly otherwise.
  - `verify-atuin-guard.sh` isolated atuin's socket into its sandbox by unsetting
    `XDG_RUNTIME_DIR`. Under 18.20.0 that is no longer sufficient: with `TMPDIR` unset under
    `env -i`, atuin would resolve `/tmp/atuin-$UID/atuin.sock` — outside the sandbox, and
    possibly a socket the developer's own daemon is already holding. `TMPDIR` is now pinned
    into the sandbox. (#518)

- **Docs caught up with a fleet topology change they were still describing the old way.**
  `dotfiles-Offense` shed its OS-native layer entirely — no `os/`, no `install/packages.txt`,
  no `scripts/tool-versions.env` — and adopted `blib_link_role_layer`, with the Kali package
  lane moving to `dotfiles-Debian`'s `only:kali` / `skip:kali` tiers. `dotfiles-Debian` is
  therefore a first-class ubuntu/debian/**kali** target now, not the frozen-Ubuntu-LTS one the
  docs described.

  That single move is what made most of the surviving drift, rather than several independent
  errors:

  - `core.manifest` and `PORTING-MATRIX.md` both said **neither** role repo had adopted the
    role-layer helper. `Offense` has; `Defense` still hand-rolls the band in
    `wire_defense_stage`, and migrating it is what actually remains.
  - The matrix said `Offense` "also carries its own OS-native layer (Debian/apt,
    kali-rolling)". It does not.
  - Two footnotes asserted Kali "installs it nowhere" and "installs nothing from this family".
    Both are false: `dotfiles-Debian`'s `only:kali` tier installs a substantial subset.
  - Three Kali cells were demonstrably wrong — `lazygit` was marked `²¹` (available, not
    installed) and `starship` `script³` when both are apt packages there, and `atuin` was
    marked `³` (best-effort script) when it is a pinned, checksummed release asset.

  The Kali column as a whole is **not** re-derived here, and the table now says so: a caveat
  marks it as inherited-not-verified until `/os-package-availability` has run against the new
  owner. Correcting three cells and claiming the column is verified would be the same mistake
  the `²¹` footnote block already made once.

  Also corrected: footnote `¹⁴` listed `ouch` among Alpine's `testing`-repo tools, but Alpine's
  own bootstrap says it is unpackaged there outright; the OSC 52 `clip` fallback was still
  described as a pending fix, having shipped in **v4.13.0** (and gained the tmux server-side
  path in #525); and `README.md` offered `--dry-run` to macOS only, when all nine bootstraps
  implement it and the Linux list also omitted Debian, Defense and Offense.

  Finally, eleven stale fleet counts across `ci.yml`, `pr-link-check.yml`, `zsh/10-options.zsh`,
  `zsh/45-plugins.zsh`, `tmux/scripts/tmux-claude.sh`, `scripts/lib/common.sh` and
  `scripts/test-core.sh` — variously "8 OS repos", "10-repo fan-out" and "ten repos" — now
  agree with `scripts/os-repos.txt` (**nine** vendoring repos; **eleven** including Core and
  `dotfiles-Windows`). Two were wrong in a more interesting way than the count: `common.sh`
  disagreed with itself two functions apart, and `pr-link-check.yml` described ci.yml's matrix
  as "macOS + seven distros" when it is ubuntu + macOS + alpine + arch. (#519)

- **The CI floor's first-party SHA-pin exemption was wider than the policy it was named for.**
  Rule 3 exempted any `uses:` whose owner is `dotgibson` with a bare owner-string match, so
  `uses: dotgibson/anything@main` passed the gate outright.

  `RELEASE-STRATEGY.md`'s exemption is narrower than that: it is the `@vN` moving-major policy
  for the fleet's own **reusable workflows**. Nothing asserted that shape, so the policy was
  documented in one place and enforced in none.

  The exemption now requires `dotgibson/<repo>/.github/workflows/<name>.yml@v<N>`. Anything
  else from the same owner **falls through** to the 40-hex requirement rather than being
  rejected outright — a first-party caller that chose to SHA-pin is stricter than `@vN`, not
  weaker, and must not be told off for it.

  **Fix-first, in the same PR:** `core-integrity-call.yml`'s copy-paste caller stub documented
  `@main`. It was the only non-`@v4` first-party ref in `.github/`, and it contradicted
  `bootstrap-test.yml`, which spells out that stubs pin `@vN` "NOT @main". That mattered more
  than a stray doc comment usually would — the stub advertised the exact shape whose acceptance
  the exemption's own premise depends on being impossible. (#521)

### Changed

- **`zsh-syntax-highlighting` pin moves to `2fc57d63067c`.** The only pin of the eight that
  was behind; the other seven and every `nvim/lazy-lock.json` entry were already current.

  The range is **one upstream commit, and it touches only `tests/README.md`** (+2/-2, fixing
  relative links) — verified against the upstream compare before landing rather than inferred
  from the SHA moving. So this is a pin refresh with no runtime change at all, which is worth
  saying plainly: this plugin runs a highlighter on every keystroke, so "the pin moved" and
  "behaviour moved" are worth keeping distinct in the record.

  `update-plugins.sh` re-fetches and `zsh -n` parses each rolled pin before writing, so the
  new commit is proven fetchable and syntactically valid, not just newer.

## [v4.16.0] - 2026-08-23

### Changed

- **nvim plugin pins move forward for three plugins.** `flash.nvim`, `nvim-lspconfig` and
  `nvim-treesitter` advance to the commits lazy.nvim had already resolved on a live box.

  Every new SHA was verified to exist upstream and to be a strict fast-forward of the one it
  replaces (`status=ahead`, `behind_by=0` in all three — no rewrite or force-push), and each
  range was read before promotion:

  - **`flash.nvim`** `b634694` → `5f0f270`, 2 commits: a Neovim 0.13 search-state fix (#496)
    plus auto-generated vimdocs. Core calls `require("flash").jump()` — public API, untouched.
  - **`nvim-lspconfig`** `bff1bd6` → `221c438`, 3 commits: the only functional change is
    `lsp/ols.lua` skipping its config when the `odin` command is missing, and Core does not
    configure `ols`. The two servers Core _does_ touch here are cosmetic — `gopls` gains one
    docstring line in its type annotations, `volar` nine additive annotation lines (Core's
    only mention of `volar` is the comment in `servers/vue_ls.lua` recording that rename).
  - **`nvim-treesitter`** `074aa44` → `8b98b44`, 2 commits: a parser bot update, and `djot`
    marked unmaintained. Core does not reference `djot`.

  Nothing renames or removes an API Core calls.

  **Provenance, because it is the failure mode this repo keeps re-learning:** these bumps were
  found as an uncommitted edit to `dotfiles-MacBook`'s **vendored** `core/nvim/lazy-lock.json`
  — the same shape as the v4.14.0 entry, which found the previous set sitting in
  `dotfiles-Fedora`'s vendored tree. That tree is a copy: `scripts/sync-core.sh` refuses a
  dirty repo outright, so the edit blocks the next fan-out rather than surviving it, and once
  committed there it would be overwritten and lost on the following `lazy sync`. They belong
  here, once, and reach every machine by fan-out.

### Added

- **`core-doctor` gets a third state, so `✗` means something again.** (#513)
  `_CORE_DOCTOR_GROUPS` probes 41 tools; `PORTING-MATRIX.md`'s footnote ²¹ says a documented
  subset of them is installed by **no** Linux repo's `packages.txt` and **no** `bootstrap.sh`,
  deliberately. Both were rendered `✗`, so a correctly-provisioned box reported a wall of
  failures for tools that were never in scope. `✗` is the doctor's only alarm channel — when a
  healthy box shows nine permanent ones the operator stops reading them, and a real regression
  lands in the same visual bucket as the ones that were never coming.

  Now `✓ present | ✗ expected but missing | · opt-in, not installed`, with the opt-in rows
  listed once under their own heading and kept out of the `install missing` block, which
  exists to name things worth fixing. `·` rather than the `○` the issue proposed: `○` already
  means "installed but **idle**" in the wired block below, and one glyph with two meanings on
  one screen is the legibility problem this change is about.

  `--json` grows an `expected` object beside `tools`, sharing its key set and order, so a
  provisioning gate can finally assert _"no expected tool is missing"_ — a question that had
  no expressible form, since `tools` alone can only answer "is every tool present", which is
  false on every correctly-provisioned box. A separate object rather than widening `tools`
  from bool to enum, which would break every existing consumer for a question they were not
  asking. The exit code deliberately does not move: `core-doctor` is read-only diagnostics.

  Membership is a **rule, not a judgement call** — a tool is opt-in iff its `PORTING-MATRIX.md`
  Tool cell carries a row-level ²¹, or one of the two footnotes ²¹ itself names as the same
  shape (¹⁷ `jnv`, ¹⁹ `gping`). A test re-derives the list from the matrix and fails if the two
  disagree, so the prose is mechanically checked rather than hand-copied — the gap that let a
  probed tool ship with no matrix row at all (#514). Known limitation, recorded rather than
  papered over: `jj` and `ast-grep` carry ²¹ only in the Gentoo and Kali _cells_, and a
  Core-side list cannot say "opt-in there, expected here", so they stay expected. Fixing that
  properly needs a per-repo manifest; this is the fallback default until one exists.

- **`bootstrap-test.yml` now asserts the OS overlay — the part an OS repo actually owns.**
  (#473)
  The `links-only` job asserted `loader.zsh`, `80-os.zsh`, `starship.toml`,
  `lazygit/config.yml`, `nvim`, `.vimrc`, `.gitconfig`, plus conditional `atuin` and the
  seeded `sesh`. It did **not** assert a single thing `blib_link_os_layer` produces — so a
  regression in the OS overlay was invisible to the one test whose stated purpose is "the
  part bootstrap.sh OWNS: the wiring it produces."

  Now asserted: `~/.config/tmux/os.conf`, `~/.config/git/os.gitconfig`,
  `~/.ssh/config.d/50-os.conf`, `~/.ssh/config`, `~/.config/jj/config.toml`,
  `~/.config/mise/config.toml`, and `~/.local/bin/clip` + `clip-paste` — plus the ssh
  permission side effects nothing checked (`0700` on `~/.ssh`, `~/.ssh/sockets` and
  `~/.ssh/config.d`). Those modes are not cosmetic: ssh silently ignores a config under a
  loose directory, so a bootstrap that linked the file but left `~/.ssh` at `0755`
  produces a box where the config is present and **inert**, which is harder to diagnose
  than a missing link.

  Every check **self-arms on the caller tree** rather than taking a new input, following
  the `os/*.zsh` and `atuin` precedent already in the file — a role repo ships no `os/`
  overlay and correctly links nothing, and a repo on an older vendored `core/` has no
  `core/jujutsu` to link, so an unconditional check would red a repo doing exactly the
  right thing.

  `0600` on `~/.ssh/config` is **deliberately not** asserted, and the workflow says why:
  Core does not chmod that file and must not, because it is a symlink into the consumer's
  vendored `core/` tree. The reasoning was already recorded in `lib/bootstrap-lib.sh`; it
  is now recorded at the gate too, so the next audit does not re-file the request.

- **New opt-in `packages_check` input — package names are gated at last.** (#474)
  `--links-only` returns before `provision()`, so `install/packages.txt` — the most
  volatile file in every OS repo, on distros including **rolling releases** — was validated
  by no blocking gate anywhere in the fleet. Real drift already happened: `doggo` moved
  AUR → `extra` on Arch and broke a file nobody had edited.

  The `provision_stub` job does not cover this and cannot: it replaces the package managers
  with no-ops, so a wrong package name is precisely the class of bug it is blind to.
  `packages_check` covers that blind spot from the other side, resolving every name against
  the real distro repos — `pacman -Si`, `dnf list`, `apk info`, `zypper info` — with no
  download and no install.

  The input is a **string** (the resolve command) rather than a boolean, so Core does not
  have to own a distro-to-command table that would need editing here every time a repo
  joins the fleet or a package manager changes its flags. A companion `packages_file`
  input (default `install/packages.txt`) covers the repo whose list carries per-distro
  annotations — dotfiles-Debian filters through its own `scripts/pkg-filter.sh` and should
  point this at a pre-filtered file.

  It reads the list with `blib_read_pkgs_into`, the **same parser** `bootstrap.sh` uses, so
  CI cannot pass on a list bootstrap would read differently — and an unreadable list fails
  loudly instead of resolving zero packages green, which for this job would otherwise be a
  permanent silent false pass. Every unresolved name is collected and reported together
  rather than failing on the first, since a rolling-release rename usually arrives in
  batches.

  `dotfiles-Arch` carries a repo-local `packages.yml` doing exactly this with a
  `TODO(upstream)` pointing here; it collapses to a caller once this lands. Worth a
  `schedule:` trigger in the caller as well as `pull_request` — a rename upstream breaks a
  file nobody edited, so there is no PR to attach the failure to.

- **`lint-call.yml` now runs a blocking secret scan, so the OS repos are covered for the
  first time.** (#462, #472)
  Core scanned itself twice — the gitleaks pre-commit hook at author time and
  `audit-core.sh` §8b in CI — and pinned `GITLEAKS_VERSION` + `GITLEAKS_SHA256` in
  `scripts/tool-versions.env`. Both scanned dotfiles-core. The reusable `lint-call.yml` is
  the **only CI the OS repos have**, and it ran shellcheck, shfmt, `bash -n`, `zsh -n`,
  actionlint and markdownlint — none of which looks for a credential.

  So **no OS repo had ever had its own files scanned for secrets**, including the repos
  that actually hold an `ssh/config` and seed a git identity. §8b's own comment names the
  stake: Core "fans out to 9 PUBLIC repos, where a committed token amplifies N-way." Core
  was covered; every fan-out target was not. GitHub push protection is a partial backstop
  only — it matches _provider_ token patterns, so it misses a private key pasted into an
  `ssh/config`, and the non-provider setting that would catch it is org-governed and off
  by default.

  Four decisions, each recorded in full on the job:

  - **Unfiltered, so it can be marked required.** The callers' other workflows carry
    `paths-ignore` filters and never start on a docs-only PR; a required check that never
    reports blocks the PR forever, which is the practical reason `lint` cannot be required
    today. This leg has no filter.
  - **`gitleaks dir`, not `gitleaks git`** — the working tree, not history. One historical
    finding would pin the check red permanently and wedge every PR once required, and
    could only be cleared by a rewrite.
  - **`--redact`** — the repos are public and Actions logs world-readable, so an
    unredacted finding would write the secret into a log while reporting it.
  - **The whole tree, `core/` included.** Every other leg excludes `core/**` because it is
    gated upstream, but that reasoning is about lint _opinions_; a credential is a
    credential wherever it sits.

- **`gitleaks.toml` — one secret-scanning policy for the fleet.** Read by all four
  consumers (the pre-commit hook, `audit-core.sh` §8b, the new `secrets` job, and a
  consumer's own `make secrets`), so author time and CI cannot disagree about what counts
  as a finding. Same discipline as `scripts/tool-versions.env`: one definition, referenced
  everywhere, changed deliberately.

  It **extends** the upstream rule set (`useDefault = true`), so a gitleaks bump still
  brings new detections, and removes nothing. It narrows exactly one false-positive class:
  a credential position holding a **variable reference** rather than a value. Several
  default rules match on position rather than content — `curl-auth-user` fires on anything
  in the credential slot of curl's basic-auth flag — and infra config in this fleet routinely
  puts a variable there, which is the _secure_ shape. The fleet's only finding was
  dotfiles-Defense's OpenSearch healthcheck: a Compose `CMD-SHELL` test that passes the user
  `admin`, and a `$$`-escaped reference to `OPENSEARCH_INITIAL_ADMIN_PASSWORD` as the
  password, into that flag.

  (Described rather than quoted, deliberately. Reproducing the literal line here put a
  credential-SHAPED token in this file, which is a public repo vendored into every consumer —
  so any repo scanning the vendored tree under the stock rule set flagged this paragraph, and
  four of them did on the 2026-08-23 sync. Core's explanation of the allowlist read as a
  violation of it. Please do not restore the code fence. See #623.)

  The `$$` is deliberate — it stops Compose interpolating at render time, keeping the
  password out of `docker compose config` and `docker inspect`. Reporting that as a leak
  inverts the incentive: it flags the careful form and is silent on the careless one.

  The allowlist targets the matched **value**, not a path, rule or repo, so a real
  credential on the same line of the same file is still caught — verified both directions
  before landing. All twelve repos scan clean under it, so the gate is green on arrival
  rather than red for a maintainer to chase.

### Fixed

- **`/os-package-availability` citations rotted between filing and fixing.**
  (`.claude/commands/os-package-availability.md`)
  The routine already had a rule for citations that are wrong _when written_ ("Read a line
  before you cite it", added after the 2026-08-09 macbook run pointed at `duf` and
  `visidata`). It had nothing for the other half: a citation that was **right when written
  and stale by the time anyone acted on it**. Being careful does not prevent that one — these
  reports are filed as issues and sit open while the files they point into keep moving, and a
  bare line number is the part of a citation with no redundancy, so when it rots there is
  nothing to detect the rot with.

  The routine now requires an **anchor string** — the literal text of the line, or a short
  unique fragment — quoted alongside every `file:line`, and says plainly that the text is the
  address and the number is only a hint. It also tells whoever acts on an older report to
  locate by the anchor and re-read before editing, and to treat _no match_ as a finding in its
  own right: the line has been edited or removed, so the claim needs re-checking rather than
  applying.

  Prompted by the run that shipped it. The 2026-08-23 macbook report cited the `watchexec`
  version stamp at `PORTING-MATRIX.md:552`; it was `:552` when written and `:577` when fixed,
  because Core went v4.14.0 → v4.15.1 in between and that footnote was itself rewritten.
  Nothing was wrong with the report — the file moved out from under it — and the anchor text
  was still an exact match the whole time.

- **A bootstrapped box committed as `Your Name <you@example.com>` and said nothing.** (#476)
  `blib_seed` copies `git/local.gitconfig.example` to `~/.config/git/local.gitconfig`, and
  `git/gitconfig` `[include]`s it — and the example shipped a **live** `name`/`email`. So a
  freshly bootstrapped box had a perfectly valid identity, `git commit` succeeded, and the
  author was the placeholder. Before bootstrap that same box had no identity at all and the
  commit would have failed loudly, which is the correct behaviour: **bootstrapping made the
  failure mode strictly worse**, and the result lands in public repo history where authorship
  cannot be fixed retroactively.

  Two coordinated edits, because either alone is inert: `git/gitconfig` now sets
  `[user] useConfigOnly = true` so git refuses to invent an author, and the example's
  `name`/`email` are commented out so the seeded copy — included _after_ that setting — cannot
  supply one. An unconfigured box now gets git's own error naming the two commands to run;
  filling the seed in works exactly as before. Note `[alias] mine` reads `git config
  user.email` and so now fails on an unconfigured box rather than matching nothing — the same
  improvement, loud rather than silent.

- **The lazy-seed assertion asked git about the worktree, so it failed the maintainer and
  passed the tarball.** (`scripts/test-core.sh`)
  Section D's third assertion read `git status --porcelain nvim/lazy-lock.json` and required
  it to be empty, under the heading "the state lockfile links back into the vendored tree (or
  the seed was modified)". That asks whether the **worktree** is dirty, which is a different
  question from "did this run write through into the vendored tree" — and it answered the
  intended one wrongly in **both** directions:

  - **False red.** `./scripts/update-nvim-plugins.sh` — the sanctioned way to move the nvim
    pins — leaves an uncommitted seed by design, so `make audit` failed until the author
    committed. A gate that fires on the workflow it exists to protect is one people learn to
    route around, which is the same lesson the #465 comment directly above it already records
    about consumer vendoring gates. Hit for real while landing the pins in this release.
  - **False green.** The clause was guarded by `git rev-parse --show-toplevel`, so outside a
    git checkout — a release tarball, a vendored `core/` — it short-circuited to true and the
    assertion silently stopped asserting.

  Now a pre-run snapshot of the seed is compared to the post-run file with
  `core_files_identical` (git-hash based; diffutils is not guaranteed, #572). Neither failure
  mode survives, and it needs no repository.

  **What it does and does not prove, since the distinction is the whole point.** It does _not_
  catch the #465 bug: lazy is stubbed here, nothing plays the part of lazy rewriting its
  lockfile, and "the vendored file is untouched" would pass on the pre-fix code too — that is
  why the previous comment declined to assert it, and assertions 1 and 2 remain what pin #465.
  It _does_ catch `config/lazy.lua`'s own **seeding**, which unlike lazy really does run here,
  against a config dir symlinked at the vendored tree: `seed` resolves to the real
  `nvim/lazy-lock.json`, so an inverted `fs_copyfile`, an `fs_symlink`, or anything else that
  writes the seed instead of reading it would corrupt the fleet's pins from a plain editor
  start. Verified by sabotaging `lazy.lua` to append to the seed: the assertion fires and
  names the file. The conflated condition was also split in two, so a symlinked state lockfile
  and a mutated seed no longer report the same message.

- **The atuin autostart premise was concurrency-sensitive, and it blocked every release.** (#495)
  The block is hermetic with respect to atuin, systemd and the network — but not with respect
  to another copy of **itself**. Its leak assertion reasons about what appeared under shared
  `/tmp` during a window and its reap assertions about processes; neither can tell this run's
  residue from a concurrent run's. The release path audits **twice** (`make release`, then
  `make tag`), so a cut needed two consecutive lucky greens. The observed shape was the tell:
  one unmodified tree went `pass 261  fail 0` and then `pass 260  fail 1` nine minutes later,
  and across three attempts the failure _count_ varied — 6, then 4, then 0 — which a real
  defect does not do. The only way through was `TAG_SKIP_AUDIT=1`, i.e. eroding the gate the
  runbook depends on.

  Three fixes, and the first is a defect in its own right whatever the root cause:

  `_d_forks_alive` read the fork log with no existence check. Bash applies redirections left
  to right, so the file is opened **before** `2>/dev/null` takes effect — a missing one printed
  a raw `No such file or directory` on inherited stderr _and_ still returned `0`,
  indistinguishable from a genuinely clean reap. Its sibling `_d_spawned` has always checked
  `-s`; this one was the outlier.

  The three call sites read `.forked` the instant the run returned, but the stub writes it from
  the child it just forked — so "not there yet" and "never forked" were the same observation at
  the wrong moment, and the failure named the wrong thing ("the stub never forked, so the
  reaping assertion proved nothing"). Now a bounded poll, ~2s at 50ms.

  And the block takes an exclusivity lock, skipping when another run holds it. A skip is
  honest; a flaky fail is not. `mkdir` rather than `flock` (absent on macOS, and this suite
  runs there) or `pgrep` — a process probe cannot work here at all, because `audit-core.sh`
  runs `test-core.sh` in the **background of the same audit**, so it would find its own sibling
  and skip every run. The holder's pid is recorded and a lock whose holder is gone is taken
  over, so a SIGKILLed run cannot turn one crash into a permanently silent skip.

- **`PORTING-MATRIX.md`: the Gentoo column again — a tool that got packaged, and a version
  trap the matrix had only ever recorded for Debian.** Reported by the
  `/os-package-availability` routine as `dotgibson/dotfiles-Gentoo#116`; the OS-layer half
  lands in that repo. Verified 2026-08-23 against packages.gentoo.org and `gentoo/guru@master`.

  - **`tree-sitter-cli` on Gentoo is `dev-util/tree-sitter-cli`, not `cargo³`** — 0.26.11 is
    **stable on amd64** and clears ⁵'s 0.26.1 floor, so it needs neither a keyword line nor a
    source build. `dotfiles-Gentoo` had been `cargo install`ing it on every privileged run.
    Row and footnote ⁵ updated — ⁵ now carries this story for **two** distros in a fortnight,
    Gentoo alongside the openSUSE one from #599.
  - **New footnote ³³ — "the package exists" is not "the package is usable".** Gentoo is the
    second target where `neovim` resolves and gives you a version Core's config cannot load:
    the newest **stable** ebuild is 0.11.7 against nvim-treesitter `main`'s hard 0.12
    requirement, with 0.12.0–0.12.3 sitting in the tree as `~arch`. Debian reaches the same
    wrong version through a frozen archive (²⁸); Gentoo reaches it through **keywords**, which
    no availability check can see. ³³ tabulates both and the Debian paragraph now points at it.
  - **Gentoo's `ouch` cell is `cargo` by choice, not for lack of a package** — GURU carries
    `app-arch/ouch` 0.8.1. ²¹ now says so, the way ²⁵ already did for `watchexec`, leaving
    `ast-grep`¹¹ and `jnv`¹⁷ as the family's genuinely-unpackaged Gentoo entries.

- **`--json` reported a failing result on a healthy tree, and its stdout was not parseable.** (#511)
  Two independent breakages of the same contract, both live on an unmodified `main`.

  `--json` exports `CORE_JSON=1` so nested gates keep stdout clean, and `skip()` prints nothing
  in that mode. The fixtures run real gate scripts and assert on their human-readable output —
  so a child inheriting the export lost exactly the lines being asserted on. This is the
  **fourth** fixture bitten by it (`$EDITOR`, `LC_ALL`, `CORE_COLOR`, `CORE_JSON`), and the
  third fixed one at a time: `tag-release` (#508), `sync-core` (#524), and now `fleet-drift`,
  whose renamed-clone assertion greps for the `not checked out` line that `skip()` emits.
  Reproduced before the fix: `test-core.sh --scope none --json` reported `fail:1` where the
  identical run without `--json` reported `fail:0`.

  Fixed at the default rather than the symptom. `test-core.sh` now does `export -n CORE_JSON`
  once, after argument parsing: the value stays readable in its own shell, so its `skip()` is
  still quiet and the JSON object still clean, but **no child inherits it** — closing the class
  for every fixture, present and future, by both routes in (`--json` here, and `audit-core.sh
  --json` putting it in the environment). The per-call `env -u CORE_JSON` pins are kept and
  extended to every fixture that captures a gate's output, because they document the hazard at
  the call site and keep each fixture correct if it is lifted elsewhere.

  Separately, stdout carried three lines, not one: a fixture wrote `core payload v2` that an
  earlier section had already committed, so `git commit` staged nothing and printed `nothing to
  commit, working tree clean` — onto the stream `--json` promises carries only the object. That
  no-op also hollowed out the fixture it sat in: it is the #587 two-prior-syncs reproduction,
  and with no round-2 commit the remote never moved, so there was only ever one.

- **Nothing ever ran `--json`, which is why three bugs in it shipped green.** (#511)
  New `--json output contract` section: the suite runs itself at `--scope none --json` and
  asserts stdout is exactly one line, that it **parses** as JSON (not that it contains a
  substring — a truncated object can still match a grep), and that its `result` agrees with the
  identical run without `--json`. `CORE_TEST_SELFJSON=1` in the child stops the recursion, and
  `-u CORE_TEST_NESTED` is this section obeying its own rule: without it the child inherited the
  audit's nesting flag, printed no summary at all, and the gate failed under `make audit` for a
  reason unrelated to the contract. It sits above the zsh-gated block, whose `summary; exit` on
  a zsh-less box would otherwise make it unreachable for precisely the `--scope none`
  invocation it exists to check. Verified to bite: re-introducing the no-op commit fails it
  with `stdout carried 3 lines, want 1`.

- **`watchexec` 2.6.1 on Arch and Homebrew — the four-repo version stamp has split.**
  (`PORTING-MATRIX.md`)
  Footnote `²⁵`'s availability block asserted one version on behalf of four package repos:
  "**Arch `extra`, openSUSE Tumbleweed, Homebrew, nixpkgs** — 2.5.1, current." Two of the four
  have since moved. Arch `extra` carries **2.6.1-1** and Homebrew **2.6.1**; openSUSE
  Tumbleweed and nixpkgs are still on 2.5.1. That bullet is now two, and the block carries a
  `versions re-verified 2026-08-23` stamp beside the existing coverage dates.

  Re-checked against each repo's own package pages, per the convention the footnote itself
  declares — not a repology snapshot. The other three bullets hold unchanged: Alpine
  `community` 2.5.1-r0, GURU 2.5.0 (top non-`9999` ebuild), and Fedora/Debian/Kali still
  package it nowhere.

  **The shape of the defect is the reusable part.** A bullet that lumps N repos into a single
  version claim is true only while all N agree, and it rots silently the moment one moves —
  there is no wrong-looking text to catch, because the line still reads as a fact. This one
  surfaced through `/os-package-availability macbook` (dotfiles-MacBook#185), which is
  **Homebrew-scoped by construction** and could only ever see one of the four; the Arch half
  was found by re-reading the whole bullet rather than only the repo that was reported. Prefer
  one bullet per repo where the versions are load-bearing.

  The footnote's actual assertion — Homebrew packages `watchexec`, and the MacBook `Brewfile`
  deliberately declines it — was correct throughout and is unchanged. No package list changed:
  that same audit found all 77 `Brewfile` entries resolving under their canonical names.
- **`PORTING-MATRIX.md`'s Alpine claims had drifted: a version floor stated fleet-wide that
  holds on two of five branches, and two "no bootstrap installs it" absolutes that Alpine
  falsifies.** (dotfiles-Alpine#122) Documentation only — no Core behaviour changes.

  Footnote ⁵ quoted tree-sitter-cli `0.26.7` for **Alpine** as though it were the whole distro;
  that is the v3.24/edge version. v3.21 carries `0.24.4-r0` and v3.22/v3.23 carry `0.25.10-r0`,
  all three **below** nvim-treesitter's `>= 0.26.1` floor. The note is now split per release and
  records that `dotfiles-Alpine`'s cargo fallback is **version**-guarded rather than
  presence-guarded — a presence guard sees apk's 0.25.10, skips the build, and leaves the box
  below the floor in silence. (The openSUSE half of this footnote, added by #599, is untouched.)

  Footnote ¹⁷ said no `bootstrap.sh` installs `jnv`; `dotfiles-Alpine` does, via cargo
  best-effort, so its cell is now `cargo³`. Footnote ²¹ had already been corrected on this
  point by #565, and now that ¹⁷ agrees with it, ¹⁷ also names Gentoo's opt-in extras build
  and defers to ²¹ as the authority rather than keeping a second count in sync by hand.

  Footnote ³¹ said neither Charm tool is go-installed by any `bootstrap.sh`. `dotfiles-Alpine`
  go-installs `glow` and always has — on the stale `github.com/charmbracelet/glow/v2` path,
  which still resolves and so quietly pinned an abandoned major instead of failing. `glow` is
  now a row in the module-path table at its real path, `charm.land/glow/v3`.

  Footnote ¹⁴'s `testing`-only list gained `tealdeer`, which it had always omitted.

- **`core.lock` recorded `core_tag=v4` — the moving alias, not the release it pins.** (#515)
  Every cut writes the specific `vX.Y.Z` and then re-points the major alias `v4`, so the alias
  is the newer tag and a bare `git describe --tags` picks it. All nine repos were stamped
  `core_tag=v4`: a provenance field naming a target that is deliberately moved on the next
  release. `core_version` was right beside it and correct, which is what makes this a bug
  rather than a design choice — two adjacent fields describing one commit at two precisions,
  with the less precise one feeding the tooling.

  Not cosmetic, unlike its `core_branch` sibling (#453): `core_tag` is read twice. `fleet-drift`
  renders it as the RECORDED column, so the fleet dashboard answered "which Core is this box
  on?" with "4.x" for every repo; and it is written verbatim as the trailing `# vX.Y.Z` comment
  on every SHA-pinned reusable caller the fan-out rewrites — the comment Renovate reads to pick
  the next bump, so `# v4` handed Renovate a target that never changes.

  Both `describe` calls now filter to the `vX.Y.Z` shape (the idiom `fleet-drift.sh` already
  used), which excludes bare-major aliases by construction. When only an alias exists, describe
  fails and `core_tag` is **omitted** — the field is documented as conditional, and an absent
  tag is honest where `v4` was not. The fix reaches a repo on its next sync.

- **The fan-out opened a PR for a repo whose workflow-pin rewrite had failed.** (#484)
  `sync-core.sh` fails such a repo — `err()` prints a `✗` and counts it failed — but that
  verdict cannot reach `sync-fanout.yml`: the script exits 0 by design (it runs under `bash -e`,
  so a non-zero would abort the step and deny PRs to the repos that _did_ sync), and `core.lock`
  is deliberately still written and committed, because withholding it would add a self-blocking
  dirty tree on top of the drift. The gate's two post-conditions — branch ≥1 commit ahead, and
  `core.lock` pins the target — are therefore **both satisfied** by exactly the repo that should
  be held back, so the release shipped a tree that vendors one Core and runs another: the #482
  split, reopened, with only a `✗` in the job log to say so.

  The gate now asserts the artefact instead of trusting the producer. Before pushing, it
  re-derives every `dotgibson/dotfiles-core/.github/workflows/<name>@<40-hex>` pin from the
  files on disk and requires each to equal the released commit; a mismatch marks the repo ❌ and
  skips the push, matching the two existing post-condition failures. Offline, and independent of
  how the sync reported — so `sync-core.sh`'s exit-0 contract, which must not change, is
  untouched. Callers on the mutable `@v4` alias match no 40-hex and are correctly ignored.

- **`sync-core.sh` said "N workflow pin(s)" while counting workflow FILES.** (#491)
  `_sync_pin_workflows` increments once per file rewritten, and one file can carry several
  pins, so the number and the noun disagreed in both commit-message forms — while the `ok()`
  line in the same function already said `file(s)`. Both now say `workflow file(s)`, and
  `VENDORING.md` says the same; that sentence also documented only the older `core.lock → …`
  form and now covers the `sync Core → …` one the materialize rework (#587) introduced.

- **The carapace footnote still said three OS repos call the impossible `go install`.** They
  no longer do, and had not for a while — the claim, and the "each is tracked in its own repo"
  that followed it, was the last stale paragraph of footnote ²⁷. `dotfiles-Arch/bootstrap.sh`
  prints a `paru -S carapace-bin` hint and go-installs only sesh; `dotfiles-openSUSE`'s
  installs upstream's `linux_<arch>.rpm` via zypper and go-installs only doggo and sesh; and
  `dotfiles-Offense` installs no carapace at all now that it is a pure Role layer. Rewritten as
  a past-tense resolution note rather than decremented to "two", so the footnote still reads as
  the contract those three fixes were made against. (dotgibson/dotfiles-Arch#111)

- **The nvim lockfile no longer drifts inside the byte-verified vendored tree.** (#465)
  `nvim/lazy-lock.json` is tracked inside `core/` — the one tree a consumer must keep
  byte-for-byte upstream — and `lazy.nvim` **rewrites it in place** whenever plugins are
  installed or updated, while an OS repo bootstrap-symlinks `~/.config/nvim` into that
  very tree. So on any machine that runs nvim at all, a file in the vendored tree was
  permanently dirty.

  Not a tidiness problem, and not user error. **Opening the editor once was enough**: a
  freshly-bootstrapped openSUSE box repinned 10 plugins and a fresh Gentoo box 2, with
  nobody running `:Lazy update`. The consumer-side vendoring gates then fired — `make
  check-core`, a `no-core-edits` pre-commit hook, `core-integrity` at PR time — all
  correctly, all against the operator, because the writer was `lazy.nvim` and not a
  person. `make test` was red on any box where nvim had been opened until someone ran
  `git checkout -- core/nvim/lazy-lock.json`, and on a box without the guard installed a
  routine `git add -A` swept the drift into an unrelated PR. A pre-push gate that a normal
  editor session turns red is a gate people learn to ignore, which is the opposite of what
  it is for.

  "Don't edit `core/`" is not a rule an operator can keep when the writer is the very tool
  the file configures. So the file moves, exactly as v4 already did for zsh history
  (`15-history.zsh` put `HISTFILE` under `$XDG_STATE_HOME` because history is mutable
  _state_, not config):

  - `$XDG_STATE_HOME/nvim/lazy-lock.json` — the **mutable** lockfile this machine writes.
  - `core/nvim/lazy-lock.json` — the read-only fleet **seed**, still the reproducible
    plugin set every machine starts from. `make update-nvim-plugins` upstream remains the
    only thing that moves it.

  A first-run seed copy (state absent → copy the vendored pins) preserves reproducibility
  on a fresh machine, which is the half a bare relocation would have lost.

  `scripts/update-nvim-plugins.sh` follows the lockfile to the sandbox's state dir and
  copies the synced pins back into the repo — and because `lazy.lua` seeds an empty state
  dir from the committed file, a sync still rolls **forward** from the current pins rather
  than re-resolving every plugin from its default branch.

  **Consumers can drop their `lazy-lock.json` carve-out** once they vendor this Core.
  `dotfiles-MacBook/test/verify-core.sh` excludes the file's _content_ from its
  byte-for-byte gate while presence-checking it; with the drift gone, it can be gated like
  everything else in `core/`.

- **`blib_link` announces a backup instead of taking one silently.** (#463)
  The regular-file branch moved a displaced file to `.pre-dotfiles.*` correctly — the
  content was preserved and `--uninstall` could restore it — and then said nothing. Only
  an aggregate `N backed up` in the closing summary hinted at it, which reports _that_
  something moved and never _what_ or _where it went_.

  `blib_link` wires roughly **34 of ~40 destinations** in an OS-repo bootstrap, so silent
  clobbering was the overwhelmingly common case rather than an edge one. The audience for
  that path is precisely someone migrating an existing machine onto the dotfiles — the
  person with the most to lose and the least context — and from where they sit an
  unannounced move means their `~/.gitconfig` simply stopped being theirs. That a recovery
  path _existed_ is what made the silence expensive: reconstructing it required already
  knowing the `.pre-dotfiles.` convention, which was documented only in a source comment.

  It now warns on stderr, naming both the destination and the backup path. The managed
  `~/.zshrc` writer, the other Core backup site, does the same.

- **One backup timestamp format, so the lexical-sort invariant `--uninstall` relies on is
  finally true.** (#464)
  Backup filenames were written in two formats by three call sites: `blib_link` and the
  `.zshrc` loader used `date +%s`, while the `link()` helper `scripts/new-os-repo.sh`
  generates used `date +%Y%m%d-%H%M%S`. An OS repo's `unlink_dest` documents — and depends
  on — "the suffix is a zero-padded `YYYYMMDD-HHMMSS` stamp, so a lexical sort IS
  chronological; the LAST glob match is the newest."

  That was **false across the pair**: a 10-digit epoch (`17…`) always sorts before a `20…`
  datestamp, so a date-stamped backup won "newest" regardless of its real age and
  `--uninstall` would restore the older file over the newer one with no error. It was
  latent only because the two writers happened to own disjoint destinations; one overlap —
  an OS repo wiring a path Core also wires — and it fires. The comment asserting the
  invariant is what made it hard to spot in review, since it reads as already-verified.

  Every writer now goes through one `_blib_backup_suffix` helper producing
  `pre-dotfiles.<YYYYmmdd-HHMMSS>.<pid>`. The `.<pid>` tail closes the second half: both
  formats resolved to one second and both writers use a bare `mv`, so two backups of the
  same destination inside one second overwrote each other — easy to hit in a test loop or
  a scripted re-run. The PID only ever tiebreaks _within_ a second, so cross-second
  ordering is untouched.

  `scripts/test-core.sh` now pins the format and, separately, the invariant itself: two
  backups a second apart must come out of a plain `sort` in chronological order.

- **A missing package list is a failure again, instead of an empty one.** (#460)
  `blib_read_pkgs` read its file with a bare redirect and no existence check, and every
  OS bootstrap reaches it through a process substitution:

  ```bash
  mapfile -t pkgs < <(blib_read_pkgs "$DOTFILES/install/packages.txt")
  ```

  `mapfile` reports the exit status of _itself_, not of the process inside `< <( … )`. So
  a missing or unreadable file left the caller holding a **zero-length array with a success
  status**, and two very different situations became indistinguishable: a `packages.txt`
  that is deliberately all comments, and a `packages.txt` that is _missing from the clone_.
  Both printed "lists no packages — skipping". The second is a broken checkout — an
  incomplete clone, a bad sync, a typo'd path — and it provisioned **nothing at all** while
  reporting that as intended. On a fresh machine that is the difference between "no extras
  requested" and "none of your tooling was installed". Same class as #459: the status of
  the thing that actually failed never reached the caller.

  `blib_read_pkgs` now warns and returns 1 on an unreadable file, which makes the failure
  loud even where the status is discarded. The check is `-r`, not `-f`, deliberately:
  dotfiles-Debian passes a **process substitution** here to drop the lines annotated for
  other distros, and that argument is a `/dev/fd/N` pipe that `-f` would reject.

- **New `blib_read_pkgs_into <array> <file>`** — the shape the process-substitution form
  cannot have. It assigns into the **caller's own array**, in the current shell, so
  `blib_read_pkgs_into pkgs "$list" || exit 1` actually works:

  ```bash
  provision() {
    blib_read_pkgs_into pkgs "$DOTFILES/install/packages.txt" || exit 1
    ((${#pkgs[@]})) && dnf install -y "${pkgs[@]}"
  }
  ```

  Returns 1 on an unreadable file (after emptying the array, so a caller that ignores the
  status cannot install a stale list) and 2 on a malformed array name — the name is spliced
  into an assignment, so validating it is a code-injection control, not a typo check. Kept
  bash 3.2-safe, which rules out both obvious implementations: `local -n` namerefs are 4.3
  and `mapfile` is 4.0, while `lib/*.sh` must run on the macOS system bash.

  Four OS repos (openSUSE, Arch, Gentoo, Debian) had each hand-rolled a caller-side
  precondition for this; Alpine, Fedora and Offense had not. Migrating a caller to this
  helper replaces all of them with one gate that cannot be forgotten.

## [v4.15.1] - 2026-08-22

### Fixed

- **The fan-out no longer depends on a commit trailer that squash-merge destroys.** (#587)
  `make sync` used `git subtree pull --squash`, which locates its base by grepping history
  for the previous sync commit's `git-subtree-split:` trailer. Every fleet repo
  squash-merges its fan-out PR, and a squash keeps the original body only if it happens to
  be carried over — so the trailer died intermittently.

  The damage was never a missing marker; it was a **wrong base**. Subtree silently fell
  back to the newest _surviving_ trailer and replayed every change since onto a tree that
  already contained them. Seven of nine repos lost the marker in the v4.14.3 round, and
  the **v4.15.0 fan-out then failed in all nine at once**, conflicting on
  `core/CHANGELOG.md` and `core/core.version` — the two files every release rewrites, so
  the two guaranteed to overlap.

  **Merging was the wrong operation to begin with.** `core/` is a pure vendored copy,
  never edited downstream (`blib_install_core_guard` rejects it, `core-integrity.sh` proves
  it byte-for-byte). "Make `core/` identical to Core@`core_sha`" has exactly one correct
  answer and no merge base, so the sync now materializes the tree with `read-tree
  --prefix` — the same plumbing `git subtree add` uses, so file modes come from the tree
  object rather than being reconstructed. It cannot conflict, needs no trailer, and is
  immune to whatever the merge policy does to commit bodies. It is also **self-healing**:
  a `core/` that drifted for any reason is corrected by the next sync instead of
  conflicting against its own drift.

  Two consequences worth knowing. The sync is now **one atomic commit** per repo rather
  than two — `core/`, `core.lock` and the workflow pins land together, closing the window
  where `core/` had moved but `core.lock` had not (the state `core-integrity` reports as
  TAMPERED). And the subtree trailer is still **emitted**, accurately, purely so consumer
  tooling that reads it as a fallback keeps working; nothing depends on it any more, so a
  squash eating it is now harmless rather than the thing that breaks the next release.

  Pinned by a fixture that strips the trailer from every commit and then syncs to a newer
  Core. It **fails** against the old `subtree pull` implementation and passes against this
  one — the earlier draft of it did not, because a `subtree pull` round produced two
  commits and amending `HEAD` rewrote the wrong one.

## [v4.15.0] - 2026-08-22

### Changed

- **Core owns the ssh client config; seven OS repos stop each maintaining a copy.** (#450)
  `blib_link_core` — Core's shared bootstrap library — read `$dotfiles/ssh/config`, the
  **OS repo's root**: a hard dependency on a file Core neither shipped nor listed in
  `core.manifest`, guarded by a `[[ -f ]]` that made "this repo forgot" and "this repo
  opted out" the same silent outcome. Seven repos did provide one. Their `Host *` blocks
  were **byte-identical** — connection multiplexing, keepalives, the KEX/cipher/MAC
  allowlists, `StrictHostKeyChecking ask`, `ForwardAgent no`. The only functional
  divergence in the entire fleet was one repo's per-service key names; everything else
  that had drifted was comments. Nothing in the file is OS-, libc- or package-manager
  specific, so by the "is it Core?" test it always belonged here.

  It is now `core/ssh/config`, in the manifest, linked from `core/` like every other
  file `blib_link_core` wires. Verified behaviour-neutral rather than assumed:
  `ssh -G github.com` against the new file is **byte-identical** to the same query
  against the config it replaces.

  **Per-host variance gets a drop-in, not a fork.** The file `Include`s
  `~/.ssh/config.d/*.conf` as its **first** directive, because ssh resolves each keyword
  first-match-wins — placed at the bottom it would be silently inert. `blib_link_core`
  creates that directory (0700), so a machine's per-service keys, work bastions or
  1Password socket path live there, untracked, instead of forking the whole config.
  A repo with a genuinely OS-specific need ships `ssh/os.conf`, which
  `blib_link_os_layer` links to `~/.ssh/config.d/50-os.conf` — the same overlay shape as
  `os/<os>.zsh` and `os/<os>.gitconfig`. One measured caveat is documented in the file:
  `IdentityFile` **accumulates** rather than first-wins, so a drop-in's key is tried
  first and Core's stays a fallback; `User` and `StrictHostKeyChecking` override outright.

  **The `chmod 600` is gone, deliberately.** Core used to `chmod` the _source_ file —
  reaching into the consumer repo's working tree to change a tracked file's mode, which
  post-move would mean Core chmod'ing its own vendored tree in nine repos. It was never
  needed: ssh refuses a config that is group- or world-**writable**, and git checks out
  0644, which already satisfies that. The 0700 on `~/.ssh`, `~/.ssh/sockets` and
  `~/.ssh/config.d` stays — ssh does require those. A test pins the absence so it cannot
  creep back.

  **For OS-repo maintainers:** delete your root `ssh/config` **only after** you have
  vendored this Core (check `core.lock`) — reversed, the box has no ssh config at all.
  `VENDORING.md` has the deletion order and the drop-in table.

### Added

- **The reusable lint gate finally lints markdown — all eight caller repos, no per-repo
  workflow.** (#452) `lint-call.yml` had no markdown leg at all, so **no OS repo's markdown
  was ever linted in CI**, even though every one of them ships a `.markdownlint.jsonc`.
  Those configs were decoration; one says so in its own header. Core lints its own markdown
  (`audit-core.sh` §7 plus a pre-commit hook), so this was a gap in the _reusable_ gate
  specifically, not in Core's hygiene — and markdown is the file class `shellcheck` and
  `zsh -n` never inspect, and the one a non-maintainer is most likely to read: each OS
  repo's README is the public landing page for that layer.

  Scoped like every other leg (`git ls-files '*.md' ':!:core/**'` plus the caller's own
  `extra_ls_files_excludes`), and run from the caller's checkout so `markdownlint-cli2`
  discovers **its** config rather than Core's — the two agree today, but the caller owns
  its own rules. `markdownlint-cli2` is npm rather than a release asset, so it is installed
  from the `MARKDOWNLINT_VERSION` pin exactly as `ci.yml` already does, instead of teaching
  the SHA-256-verifying composite action a package manager it does not speak.

  **ADVISORY this release, BLOCKING the next — measured, not guessed.** Run across the
  fleet with each repo's own config and excludes before landing: Debian 0, Offense 0,
  MacBook 1, Gentoo 16, Alpine 17, Fedora 18, openSUSE 20, Arch 26, Defense 52. Seven of
  nine would have gone red the moment auto-tag moves `@v4`, before any maintainer could
  act — callers pin a moving major tag. The backlog is smaller than 150 findings looks:
  **130 are MD060** (table pipe alignment) and `markdownlint-cli2 --fix` clears most of it
  (17 → 5 on the worst single file). Core's own 33 markdown files are already clean under
  the same rules, so this is caller drift, not an unreasonable house style.

  One deliberate difference from the shfmt leg it borrows its non-blocking shape from: a
  **missing linter hard-fails**. The `if <tool>; then … else warn; fi` idiom cannot tell
  exit 127 from exit 1, so a broken install would report as an ordinary advisory warning
  and the leg would look like it had run for the whole release cycle. An advisory gate that
  silently never runs is worse than no gate, because it reads as coverage.

### Fixed

- **`core.lock` records `core_ref`, a field that means what it is named.** (#453)
  `sync-core.sh` wrote `core_branch=$CORE_BRANCH`, and `sync-fanout.yml` deliberately sets
  `CORE_BRANCH="$target_sha"` so each release PR vendors the exact released commit rather
  than a moving `main`. That pinning is correct and stays — the defect was persisting it
  into a field named, and documented in `VENDORING.md`, as a _branch_. Every OS repo's lock
  file therefore carried `core_branch` identical to `core_sha`: a file disagreeing with its
  own contract, in the fleet's provenance record, with a field that added no information.

  Named for what it holds, it earns its place. `core_sha` says _which commit_; `core_ref`
  says _how it was chosen_ — a pinned commit for a release fan-out, a branch name for an
  ad-hoc `make sync`. Each repo picks the new field up on its next sync. Two fixtures pin
  it: the branch case, and the pinned-SHA case that was the actual bug — plus an assertion
  that the old name is _gone_, since emitting both would satisfy the new check while
  leaving the contradiction in every lock file.

  **One consumer had to be fixed first, and this entry originally said there were none.**
  The rename shipped on the claim that nothing read `core_branch` — which was verified
  inside this repo only, where it is true (`fleet-drift.sh` and `core-integrity.sh` read
  `core_sha`). `dotfiles-Offense` reads it, and is the only fleet member that does: it
  vendors Core on its own schedule via `scripts/sync-core.sh` rather than waiting for the
  fan-out. Unfixed, that script would have **died** on the renamed lock, and its
  `check-core-freshness.sh` would have done something worse than dying — fallen back to
  `main` and compared the vendored tree against main's tip while reporting success,
  watching nothing, in the state that repo is in most of the time.

  Fixed in dotgibson/dotfiles-Offense#233 **before** this release could reach it: both
  now prefer `core_ref` and fall back to `core_branch`, so locks of either vintage work
  and the rollout order cannot bite. Recorded here rather than quietly corrected, because
  "nothing reads this field" is exactly the kind of claim a fleet-wide rename rests on,
  and the check that produced it was scoped to one repo.

- **The three zsh entry files a new OS repo is stamped with are now lintable.** (#451)
  `scripts/new-os-repo.sh` emitted `zsh/zshenv`, `zsh/zprofile` and `zsh/zshrc`
  **extensionless** — mirroring their symlink destinations (`~/.zshenv`,
  `$ZDOTDIR/.zprofile`, `$ZDOTDIR/.zshrc`), which have no extension either. The reusable
  lint gate selects repo-owned zsh with `git ls-files '*.zsh'`, so none of the three ever
  matched, and none was syntax-checked in any repo, from the day the generator was added.

  `~/.zshenv` is what makes that worth more than a rename: it is sourced on **every** zsh
  invocation, non-interactive ones included, and it carries the ZDOTDIR indirection — so a
  syntax error there does not degrade the shell, it breaks login shells outright on every
  box running that layer. Simultaneously the highest-blast-radius file in an OS repo and
  the only one the gate could not see.

  The generator now writes `*.zsh` and links them to the same unchanged destinations, so
  the fix is behaviour-neutral. **`lint-call.yml`'s two zsh legs additionally select the
  three bare names by hand**, which covers the copies already written — `dotfiles-MacBook`
  hand-wrote all three — without requiring a rename in each repo. Verified no repo goes
  red on arrival: MacBook's three parse today, and the change takes it from 1 linted zsh
  file to 4. A pathspec that matches nothing is inert, so it is a no-op elsewhere.

  A new `test-core.sh` fixture pins all of it — the `.zsh` names, the absence of the bare
  ones, agreement between the scaffolded filenames and the generated `bootstrap.sh` link
  lines, and `zsh -n` over the result. Confirmed to fail when the defect is reintroduced.

### Documentation

- **`verify-core` is no longer named as a gate that runs, because it has never existed.**
  (#454) The name was cited across the docs and code comments as the byte-for-byte
  split-vs-upstream check backing several claims — `VENDORING.md`'s gate table listed it
  against two of the three Core references, `core.manifest` credited it as the reason a
  section needed no other backstop, and three comments in `sync-core.sh` plus one each in
  `sync-fanout.yml` and `test-core.sh` described it running alongside `core-integrity`.
  `ls scripts/verify-core.sh` has never found anything. Every surviving mention now says
  so explicitly; `core-integrity.sh` — which resolves `core.lock`'s `core_sha` to a tree
  and compares it with the vendored `core/` — is named where a real gate belongs. The
  load-bearing half of this was already fixed: `nvim/`'s directory-granular manifest entry
  cited the phantom as its orphan backstop, and `scripts/nvim-reachability.sh` (audit §4b)
  is the real one.

- **The docs' claim about per-repo `make core-lock` targets was false, and the truth
  matters more after #453.** They said the target is "absent in most consumers, and where
  it exists it only prints a redirect back to the fan-out". Four consumers have one, and
  only `dotfiles-Offense`'s is a redirect: `dotfiles-Arch`, `dotfiles-MacBook` and
  `dotfiles-openSUSE` each carry an **independent generator of a format Core owns** — and
  they have already drifted from it and from each other. Arch hardcodes `core_branch=main`,
  so regenerating a release-pinned lock silently discards which commit was vendored;
  openSUSE writes the SHA into that field; MacBook reads the previous value back. None
  knows about the `core_ref` rename, so running one now emits a lock the fleet's own docs
  and tooling disagree with. `VENDORING.md` and `RELEASE-STRATEGY.md` now say this plainly
  and name `sync-core.sh` as the only sanctioned writer. The three local generators are a
  fleet-side fix, not a Core one — filed separately.

- **`RELEASE-STRATEGY.md` listed six OS-native repos, not seven — `dotfiles-Debian` was
  missing.** The bullet is about repos that carry no version of their own and are stamped
  instead by the `core.lock` this repo generates for them. `dotfiles-Debian` vendors `core/`
  and has a `core.lock` like the rest, so the document that defines the fan-out understated
  it by one repo. `dotfiles-Windows` stays out of that list deliberately, and correctly: the
  next bullet names it as the exception with no `core/` subtree, no `core.lock`, and a
  `vX.Y.Z` of its own. Part of one drift with several faces — the same list had lost
  `dotfiles-Debian` in six OS repos' READMEs, and `dotfiles-Debian`'s own README had lost
  `dotfiles-Fedora` in its place. `CLAUDE.md` had it right throughout and is the copy the
  rest were corrected against.

## [v4.14.3] - 2026-08-21

### Fixed

- **`sync-core.sh`'s idempotence check failed open when `cmp` was missing, so a fan-out
  reported repointing workflow pins it never touched.** (#572) `_sync_pin_workflows` asked
  "did that rewrite change anything" with `cmp -s`. `cmp` ships in **diffutils**, which is
  not guaranteed present — a Tumbleweed box in this fleet had none, so neither `cmp` nor
  `diff` existed. A missing binary exits non-zero, which is indistinguishable from "the
  files differ", so every candidate file took the changed-branch.

  Observed on a real v4.14.x fan-out: seven of nine repos reported 6–12 workflow rewrites
  and committed **zero**, and the false counts reached nine repos' commit subjects before
  being corrected by hand. Contents were never corrupted — an unchanged file was rewritten
  to identical bytes, so git recorded nothing — but a genuine rewrite failure and a missing
  `cmp` were indistinguishable in the output.

  The same call sat in `update-nvim-plugins.sh`, failing the other way: it reported drift
  that did not exist, which under `--check` is exit 2 — the freshness gate going red on a
  lockfile that never moved. One failing open and one failing closed off the same absent
  binary is the tell that the comparison, not either caller, was the wrong shape.

  Both now call `core_files_identical` in `scripts/lib/common.sh`, which hashes with
  `git hash-object`. That removes the dependency rather than detecting it: byte-exact, no
  repository required, and git is the one tool these scripts already cannot run without.
  `sha256sum` was the other candidate and is wrong for this fleet — macOS ships `shasum`,
  not `sha256sum`, and these scripts run on the MacBook too. `$(cat a) == $(cat b)` was
  rejected for stripping trailing newlines from both sides, which would silently miss a
  real one-byte difference; a test pins that case. Six assertions cover both directions, a
  missing operand, the trailing-newline case, and correctness on a PATH carrying git and no
  diffutils — plus a grep that fails the suite if any script reintroduces `cmp`.

## [v4.14.2] - 2026-08-21

### Fixed

- **The `provision-stub` job shipped in v4.14.1 could not run.** It read its shim from the
  CALLER's vendored `core/scripts/`, which is a different distribution channel from the
  workflow that uses it: the workflow reaches a caller the moment the `v4` alias moves, while
  `core/scripts/` only arrives when that repo merges its `core.lock` fan-out PR. Every repo in
  that window got the job without the script and hard-failed with
  `core/scripts/provision-shim.sh missing — vendored Core predates it`.

  Harmless in practice — `provision_stub` defaults false and no repo had opted in — but the
  first one to try (dotgibson/dotfiles-Debian#12) reded immediately.

  The stubs are now built **inline in the job**, so there is exactly one artifact distributed
  at exactly one ref. An intermediate attempt using a second Core checkout pinned at
  `github.job_workflow_sha` was abandoned: it silently ran an _older_ revision of the script
  than the run reported using, which is a worse failure than the one it replaced. Deletes
  `scripts/provision-shim.sh` and `.github/actionlint.yaml` (whose only suppression existed
  for `job_workflow_sha`).

  Verified end-to-end before release this time, on `ubuntu:24.04` and `kalilinux/kali-rolling`
  both: the full stubbed bootstrap walks apt, the 32-package base stack, fourteen SHA-pinned
  installs, both vendor apt repos, carapace and unattended-upgrades, then crosses into
  `wire_links` and finishes at `32 linked · 2 seeded · 0 backed up`.

- **Footnote ³² said the OS layer wires direnv; v4.14.1 moved that into Core, in the same
  release.** (#449) The `direnv` row's footnote was written days before #578 landed and
  described the arrangement it replaced — "what makes it work is each OS repo's
  `os/<distro>.zsh` at band 80". v4.14.1 ships both that sentence and the commit that made it
  false, which is precisely the defect class #568 and #569 were filed for, reintroduced by the
  footnote that was added alongside them.

  Rewritten to what the code now does: Core wires direnv at `zsh/00-tools.zsh` band 00, and
  the footnote records why that band rather than 45 (it registers a hook, not a compdef, and
  band 00 loads under every `CORE_PROFILE` while 45 is ceilinged out of `minimal`) and why it
  is sourced last of the four inits (direnv prepends to `precmd_functions`/`chpwd_functions`,
  so sourcing after mise reproduces the resolution order an `.envrc` pinning tool versions
  expects). The thesis changes with it: direnv is no longer "the one row Core neither installs
  nor detects" — Core now **wires** it while still neither installing nor detecting it.

  The Kali paragraph needed the same correction and for the same reason. It argued
  `dotfiles-Offense` misses the hook because it has no `os/` layer — true at band 80, false at
  band 00, where the hook reaches it from Core like everywhere else. It is live there now and
  simply finds no binary, since that repo still installs none.

## [v4.14.1] - 2026-08-21

### Added

- **CI can now run `provision()` for real, with the network stubbed.** (#575) `--links-only`
  returns before `provision()` is entered, so package installation, retries, upstream
  installers, repo/key setup and every failure path around them were executed by **no CI job
  anywhere in the fleet**. That is how a leaked RETURN trap shipped green through review in
  two repos: it aborted every fresh-box run _after_ installing everything and _before_
  `wire_links`, and the one job that looks at `bootstrap.sh` never reached the function it
  was in (`dotgibson/dotfiles-Debian#2`).

  Adds `scripts/provision-shim.sh` — **a new file every OS repo receives in `core/scripts/`
  on its next sync** — which builds a PATH shim of logging no-ops for the package managers,
  downloaders and privilege tools a `provision()` reaches for, plus an **opt-in**
  `provision-stub` job that runs the real bootstrap behind it. Most of that bug class is
  control flow rather than I/O, so it executes without installing a package or touching the
  network.

  `sudo`/`doas` are not swallowed — they drop the escalation and re-exec the tail, so
  `sudo apt-get install x` still reaches the apt-get stub and is still logged. `git` is
  deliberately not stubbed, since bootstraps clone real things the caller pre-seeds and
  stubbing it would mask wiring bugs this job should catch. The job asserts more than a zero
  exit: the bug it exists for aborted _after_ `provision()` did its work, so it also checks
  the symlink graph survived on the far side, and prints the intercepted command log.

  Opt-in, so nothing changes for a repo that does not enable the job.

### Fixed

- **`PORTING-MATRIX.md`: the Gentoo column told two lies, and a third that was bigger than
  both.** Reported by the `/os-package-availability` routine as
  `dotgibson/dotfiles-Gentoo#85`; the OS-layer halves already landed there in
  `dotfiles-Gentoo#98` (gum) and `#103` (jj), and this is the matrix catching up.

  - **`gum` on Gentoo is not `app-misc/gum`** — that atom exists in neither `::gentoo` nor
    GURU, in any category. The cell now reads `mise³⁰`, `gum` is struck from ¹²'s GURU list,
    and ¹² records why an entry there can only ever emerge as a `skipped:` line — which reads
    like a keyword mask and invites an `accept_keywords` "fix" that unmasks nothing. That is
    how it survived in `guru_install` for months. ³⁰ gains the caveat that
    `gentoo/mise-tools.toml` is the **`--user` path only**, so a privileged Gentoo bootstrap
    installs no gum at all.
  - **`jujutsu` on Gentoo is packaged, as `dev-vcs/jj`** (`~amd64`, added 2025-12-04, EAPI 8).
    The cell moves from `cargo²¹` to `` `dev-vcs/jj`²¹ `` and ⁸ names the trap: the atom is
    `jj`; `dev-vcs/jujutsu` has never existed. **Kali's `cargo²¹` is unchanged** — jj really
    is still absent from stable Debian/Kali apt. ⁸ also stops reading Gentoo's `packages.txt`
    omission as a decline: it is a deliberate placement, because that file is the
    unconditional emerge and jj must stay skippable by `--no-extras`.
  - **The ²¹ "available, not installed" family was verified against `install/packages.txt`
    alone** — and Gentoo is the repo that installs most from `bootstrap.sh` instead, precisely
    because everything opt-in has to live in the script. So **four of the eight Gentoo cells
    in ²¹'s table read `—` for tools bootstrap installs**: `shfmt` (go, unconditional), `ouch`
    and `watchexec` (cargo, opt-in extras) and `gping` (emerged from GURU). Corrected here,
    along with ⁷, ¹⁹ and ²⁵, which each carried the same claim in prose. ²¹ now says two
    repos' bootstraps install from this family (Alpine and Gentoo), not one, and records the
    single-file verification as the root cause so the row does not go stale the same way
    again. `watchexec`'s Gentoo cell also moves `GURU²⁵` → `cargo²⁵`: GURU carries 2.5.0, but
    the bootstrap routes around it and builds `watchexec-cli` for upstream-latest.

- **`direnv` is installed by six of the fleet's seven package lists and had no row in the
  matrix at all.** (`dotgibson/dotfiles-openSUSE#89`) The `/os-package-availability` audit of
  `dotfiles-openSUSE` reported it as its one coverage gap rather than drift: `direnv` appeared
  in `PORTING-MATRIX.md` only inside footnote ¹², as one of the Gentoo GURU atoms. So a reader
  asking "what is direnv called on Alpine" found nothing, and the next audit comparing a
  package list against the table found a name the table did not know. It has a row now, and it
  sits next to `mise` rather than in alphabetical order — this table has never been
  alphabetical, and the two are the same mechanism: both are `_cache_eval`'d hook generators
  emitted from `os/<distro>.zsh` at band 80, and Core's own `examples/mise.project.toml` calls
  mise's `[env]` block "the direnv replacement" and its `[hooks]` block "the other half of
  direnv".

  Six of the seven cells are a bare `direnv`, verified 2026-08-21 against each distro's own
  index: Arch `extra` 2.37.1-1, Alpine `community` 2.37.1-r7 (v3.24 — a Go binary, so a native
  musl build), openSUSE Tumbleweed 2.37.1 with Leap 16.0 and 16.1 both at 2.34.0 through
  Backports (`bp160.1.13` / `bp161.1.9`, both arches), kali-rolling 2.37.1-1, Ubuntu 24.04
  `universe` 2.32.1-2ubuntu0.24.04.3 and Debian trixie 2.32.1-2+b16. Gentoo is the exception
  and is GURU-only — `app-shells/direnv` at 2.37.1, no `::gentoo` atom, and `dev-util/direnv`
  does not exist — so that cell reads `` `app-shells/direnv` ``¹², where the warning already
  lived and which therefore needed no edit.

  New footnote ³² records what makes the row unlike its neighbours, because no existing
  footnote shape fits it. It is not ²¹'s "available, not installed" — six repos install it —
  and not ¹⁷/¹⁹'s detect-only, because **Core does not detect it at all**: there is no
  `HAVE_DIRENV`, no alias and no `core-doctor` row. It is the only row in the table wired by
  the OS layer instead of by Core; the `direnv hook zsh` that makes it work is emitted by each
  OS repo's `os/<distro>.zsh` at band 80. Core's one stake is `starship/starship.toml`'s
  `[direnv]` module, which Core switches on (`disabled = false` — starship ships it off by
  default) so `.envrc` state is visible rather than a directory silently waiting on
  `direnv allow`. `dotfiles-Offense` (Kali) is the single fleet gap, and it is structural
  rather than a judgment about direnv — that repo carries no `install/packages.txt` and, since
  band 80 moved to the OS repo underneath it, no `os/` layer, so nothing there installs the
  package or evaluates the hook.

  One version floor is recorded because it is the only point where a frozen archive touches
  Core: starship runs `direnv status --json`, and the `--json` flag is **silently ignored below
  direnv 2.33.0** — `src/modules/direnv.rs` says so and parses the text output instead. Every
  target above clears that floor except `dotfiles-Debian`'s two lanes, both on 2.32.1. It
  degrades rather than breaks, which is why that repo's `install/packages.txt` declares no
  `# min:` floor for it.

- **Footnote ¹⁹ said both that Gentoo's `bootstrap.sh` emerges `gping` and that it does not.**
  (#568) #565 rewrote the footnote's opening to record that `dotfiles-Gentoo` really does emerge
  `net-analyzer/gping` from GURU in its `guru_install` pass — and that naming the atom only in a
  `packages.txt` comment is a pointer to that call rather than a decline. Its closing sentence
  was left behind still saying the opposite: "unlike the ¹² atoms `bootstrap.sh` does **not**
  emerge it, so enable GURU per ¹² and `emerge net-analyzer/gping` by hand." A reader who got to
  the end of the footnote was told to do by hand what the bootstrap had already done, and the
  "unlike the ¹² atoms" framing inverted the actual relationship — the same rewrite had just
  added `gping` to ¹²'s GURU list, so it is one of them.

  The tail now agrees with the head: GURU-only, no main-tree atom, emerged **like** the ¹²
  atoms in the same `guru_install` pass, nothing left to do by hand. Verified against
  `dotfiles-Gentoo/bootstrap.sh`, where `net-analyzer/gping` is the last atom in that call.

- **Footnote ²¹ claimed Kali installs `ast-grep`, and the `ast-grep` row's `³` rested on that
  claim.** (#569) The note carved out an explicit exception — "Kali **does** install `ast-grep`
  (`bootstrap.sh`, cargo best-effort), which is why that one cell keeps its ³ while its Gentoo
  neighbour does not" — which is why the Kali column kept a `cargo³` there after `ouch`,
  `jujutsu` and `lazygit` lost theirs in the same pass. There is no such install.
  `dotfiles-Offense`'s `bootstrap.sh` contains no `ast-grep` at all, and its only two `cargo`
  mentions are the comment and `export` that put `~/.cargo/bin` on PATH for tools an operator
  added by hand — which is precisely the ²¹ contract, not a ³ one.

  This mattered beyond the prose because ³ means "`bootstrap.sh` installs it best-effort", so a
  ³ with no installer behind it reads as "you will get this" and delivers nothing — the exact
  overclaim ²¹ was written to correct, surviving inside ²¹ itself for one tool. The `ast-grep`
  Kali cell is now `cargo²¹`, matching `ouch` and `jujutsu` in that column, and the list of
  cells that previously overclaimed a `³` gains `ast-grep` on Kali alongside Gentoo.

- **`bootstrap-test` and `lint` disagreed about the same `bootstrap.sh`, and only one of
  them applied the fleet's shellcheck exclusions.** (#517) `lint-call.yml` set
  `SHELLCHECK_OPTS` with Core's curated `SC1090,SC1091,SC2015,SC2088` exclusions;
  `bootstrap-test.yml` lints the same file and set nothing. So the four codes Core has
  explicitly decided are not defects still blocked — just in the other gate, and the same
  commit could be green in `lint` and red in `bootstrap`.

  The failure mode is nastier than the disagreement itself, because the two gates run on
  different triggers: `lint` on every push and PR, `bootstrap` only when `bootstrap.sh` or
  `core/` changes. A repo stays green for weeks, then a bootstrap-touching PR reds with an
  error naming a rule the fleet documented as excluded. The natural reading is "the
  exclusion list is wrong" and the natural fix is to weaken the shell script to satisfy it —
  which is what happened in `dotfiles-Gentoo` before anyone noticed the gates simply
  disagreed.

  The workaround had already spread by the time this was found: `dotfiles-Arch`, `-Debian`
  and `-Fedora` each carry an independent copy of Core's exclusion list in their own
  `.shellcheckrc`, none aware of the others, while `-Offense` and `-openSUSE` have a
  `.shellcheckrc` without it and `-MacBook`, `-Alpine`, `-Defense` and `-Gentoo` have none
  at all. Setting it in the workflow fixes all nine at once, including the six no per-repo
  workaround ever reached.

  **Nothing changes colour on merge** — all nine `bootstrap.sh` files pass both invocations
  today, so this closes a latent trap rather than a live break. GitHub cannot import an env
  value from one workflow into another, so the literal is necessarily authored twice;
  `scripts/test-core.sh` now asserts the two copies are equal, the same shape as the
  `os-repos.txt` fallback-array check and for the same reason. Deliberately **not** done:
  adding a `disable=` line to Core's own `.shellcheckrc` — Core's tree is green without
  those exclusions, and adding them would weaken its own gate to match a rule written for
  consumers. The per-repo `.shellcheckrc` fragmentation is tracked separately in #564.

## [v4.14.0] - 2026-08-21

### Changed

- **Seven OS repos stop hand-maintaining the same shell-hook block; Core owns it.** (#449)
  `direnv hook zsh`, `gh completion -s zsh`, `uv generate-shell-completion zsh` and
  `ty generate-shell-completion zsh` were duplicated across every `os/*.zsh` in the fleet —
  portable zsh with nothing OS-specific in it, maintained once per repo, and already drifted
  into **three variants of one block**: Alpine and Gentoo carried only two of the four tools,
  and one copy suppressed the generator's stderr in its fallback arm where the others did
  not. So whether your shell completed `uv` depended on which OS you booted. They now live
  in Core, and Alpine, Gentoo and the Debian family gain `uv`/`ty` completions for free.

  **Split by kind rather than kept together**, because the two halves have different
  constraints. `direnv` goes to `zsh/00-tools.zsh` alongside the zoxide/mise/atuin inits: it
  registers a hook, needs no `compinit`, and band 00 loads under **every** `CORE_PROFILE` —
  filed under band 45 it would silently stop `.envrc` files loading on minimal hosts, which
  is a broken feature rather than a missing convenience. `gh`/`uv`/`ty` go to
  `zsh/45-plugins.zsh` immediately **after** the carapace block: they call `compdef`, so they
  must follow `compinit`, and they must follow carapace so a tool's own completion keeps
  overriding carapace's bridged one — the order they already ran in at band 80, so this
  preserves behaviour rather than changing it. All four move, `ty` included: `_cache_eval`
  bails on an absent binary, so a host without the tool pays nothing.

  One ordering that is easy to lose and now has a test behind it: direnv **prepends** its
  hook to `precmd_functions`/`chpwd_functions`, and so does mise — whichever is sourced last
  runs first. The direnv line therefore sits _after_ the mise line, reproducing exactly the
  order these hooks had while direnv was hooked from band 80.

  **Measured startup cost, because one of these four is not free.** Sourcing the cached
  inits in a compinit-ready shell, 100+ runs each (`hyperfine`): `direnv` (14 lines) and
  `gh` (212) are together **+0.6 ms** over a 12.9 ms baseline — noise. `uv` ships a
  **6,976-line** completion and `ty` 325, and the pair costs **+37 ms**. The five repos that
  already hooked all four have been paying that all along and see no change; Alpine, Gentoo
  and the Debian family newly pay it, but only on a host that actually has `uv` installed.
  That is the price of the fleet agreeing on one answer, and it is worth knowing rather
  than discovering. Sourcing 7k lines on every shell to serve one `<TAB>` is the wrong
  shape long-term — the fix is an `fpath` autoload rather than a `source`, filed separately.
  Note the bench job cannot see any of this: it runs a hermetic sandbox with none of these
  binaries, so every call is a two-token no-op there.

  **For OS-repo maintainers:** nothing to do until you vendor this. After the sync, delete
  your local copy (`VENDORING.md` has the list). Running both is harmless in the meantime —
  direnv's hook guards its own registration, a repeated `compdef` re-points the same binding,
  and Core reuses the same cache files, so the transitional window behaves exactly as today.

- **nvim plugin pins move forward for five plugins.** `nui.nvim`, `nvim-lint`,
  `nvim-lspconfig`, `package-info.nvim` and `schemastore.nvim` advance to the commits
  lazy.nvim had already resolved on a live box, 2–7 days ahead of the pins Core carried.

  Every new SHA was verified to exist upstream and to be newer than the one it replaces,
  and each range was read before promotion: `nui.nvim` one additive commit (borderless
  tables, `set_data`, cell navigation); `nvim-lint` two (zlint source name, relative
  `artifactLocation.uri` in sarif output); `nvim-lspconfig` twelve, all per-server fixes
  or additions plus generated docs (`vhdl_ls`, `tsc`, `symfony_lsp`, `slang-server`,
  `php_lsp`, `oxc`); `package-info.nvim` one notification fix; `schemastore.nvim` two
  catalog refreshes. Nothing renames or removes an API Core calls.

  Provenance worth recording, because it is the failure mode this repo warns about: these
  bumps were found as an uncommitted edit to `dotfiles-Fedora`'s **vendored** `core/nvim/
  lazy-lock.json`. That tree is a copy — the next `make sync` overwrites it — so the bumps
  were days from being silently reverted, and would have come back on the next `lazy sync`
  to be lost again. They belong here, once, and reach every machine by fan-out.

### Added

- **`_core_is_wsl` — one WSL predicate for the whole fleet, and a gate against the copies
  coming back.** (#449) Six OS repos carried a byte-identical `_IS_WSL=0; …` probe to gate
  their Windows-interop niceties. Core had the same fact twice more and neither was reachable
  from zsh: `blib_is_wsl` (bash, forks `grep`, no test seam) and a private copy inside
  `bin/clip`. Eight implementations of one predicate, in two languages, drifting
  independently. `zsh/00-tools.zsh` now exports `_core_is_wsl` as a second Core→OS API
  alongside `_cache_eval` — fork-free (`$(<file)`, no `cat`, no `grep`, because unlike the
  bootstrap sibling this runs on every interactive shell), **lazily memoised** into
  `_CORE_IS_WSL` so a shell that never asks never pays, and carrying a `$CORE_PROC_VERSION`
  test seam. The seam is not decoration: without it the "this box is not WSL" case cannot be
  asserted on a WSL development host and "this box is WSL" cannot be asserted on a CI runner,
  so half the predicate would go untested on every machine. `PORTABILITY.md` gains the shim
  row and documents the narrow **env-fact exception** to its own `command -v` rule.

- **A gate against portable logic stranded outside Core.** (#449) `audit-core.sh` §5c catches
  OS-specifics leaking _into_ Core; nothing caught the reverse, which is why the block above
  went unnoticed long enough to drift three ways — it could only be found by reading two
  layers side by side. `scripts/lib/common.sh` gains `_core_owned_block_hits`, the single
  definition of "this repo re-implements something Core owns", and
  `.github/workflows/lint-call.yml` gains a leg that runs it over each caller's repo-owned
  `*.zsh`. It flags exact generator invocations rather than tool names, so hooking a tool
  that exists on one OS and nowhere else — the OS layer's actual job — is never a finding.

  Unlike the `RETURN`-trap gate it has **no `audit-core.sh` counterpart**, on purpose: Core's
  own tree contains every pattern it scans for, which is the point. The Core-side guard is
  the _inverse_ assertion in `scripts/test-core.sh` — if Core ever loses a block, the gate
  would be making nine repos delete a feature nobody provides. And it **warns in this release
  and blocks in the next**, because unlike that gate it is red-on-arrival by construction: no
  OS repo can delete its copy until it has vendored the Core that replaces it.

- **A gate against leaked `RETURN` traps, for the fleet and for Core's own tree.**
  (#552, #555, #558; refs #512, #461) A bash `RETURN` trap is a **global slot, not a
  function-scoped one**: armed inside a function it survives into the _caller's_ frame and
  fires a second time on that frame's return, where the local it cleans up is out of scope
  and `set -u` makes it fatal. In `dotfiles-Debian` that aborted `provision()` after every
  package had installed but before `wire_links` ran — a box carrying the whole stack and
  not one symlink, wearing the costume of a near-complete run
  (dotgibson/dotfiles-Debian#2).

  Nothing could see it, and nothing was wrong with the gates that missed it. The broken
  line is **valid bash**, so `lint-call.yml`'s shellcheck and `bash -n` legs both pass it;
  and `bootstrap-test.yml` only ever runs `--links-only`, so no job anywhere in the fleet
  executes `provision()` at all. A textual scan is the only thing that catches this class,
  which is why it is its own leg rather than another `SHELLCHECK_OPTS` entry.

  `scripts/lib/common.sh` gains `_core_return_trap_hits`, the single definition of the
  rule. `audit-core.sh` §5e runs it over Core's own tree (which lint-call.yml never checks
  out), and `lint-call.yml` sources it to gate its callers — **so a caller repo now fails
  its required `lint` check on a leaked trap.** Every repo in the fleet was verified green
  against the rule before release, so nothing reds on arrival.

  **That is eight repos, not nine.** `dotfiles-MacBook` does not call `lint-call.yml` at
  all — it carries its own `shell lint` job in `ci.yml` — so the leg reaches Alpine, Arch,
  Debian, Defense, Fedora, Gentoo, Offense and openSUSE, and MacBook is ungated. Its tree
  is clean today (checked directly, not inferred), and its vendored `core/` and SHA-pinned
  Core workflow refs do advance with the fan-out, so this is a coverage gap rather than
  drift. Whether MacBook should adopt the reusable gate or grow the leg in its own `ci.yml`
  is open.

  Two notes for anyone writing one of these. The correct form is
  `trap 'trap - RETURN; …' RETURN` — disarm first, and keep it first, so an early `return`
  inside the body cannot skip it. And when this bug does surface at runtime the reported
  line number is a **decoy**: bash attributes a `RETURN` trap to the last nested function
  _definition_ in the frame, so Debian's abort blamed `_add_vendor_repo`, which had nothing
  to do with it. Grep for the trap, not the line.

  The pattern is deliberately looser than the one dotfiles-Debian shipped. `trap` is
  matched as a word **anywhere on the line**, because anchoring to line-start misses
  `f() { trap … RETURN; }` — the one-line body, and the likeliest shape; against a fixture
  carrying four broken forms the anchored version catches one. The signal is matched as a
  **token** rather than as the last word, so a trailing comment and a two-signal
  `RETURN EXIT` are caught too. Whole-line comments are filtered, because Debian's own fix
  carries three comment lines naming the signal directly above its corrected traps — an
  unfiltered scanner would red the repo that fixed the bug. Ten fixtures in
  `scripts/test-core.sh` pin both halves, plus two assertions that keep `lint-call.yml`
  calling the helper instead of growing a second copy of the expression.

  **zsh is out of scope, permanently:** it has no `RETURN` signal at all
  (`trap 'x' RETURN` → _undefined signal_), so the bug cannot exist there.

### Fixed

- **Every `core.lock` in the fleet told the reader to recover with `make core-lock`, a
  command that mostly does not exist and does not regenerate the lock where it does.**
  (#557) `sync-core.sh` stamped that hint into the generated header unconditionally, and it
  was wrong three ways at once: the target is absent from `dotfiles-core` itself and from
  most consumers (which carry no root `Makefile`); in the one repo that has it,
  `dotfiles-Offense`, it regenerates nothing and just prints a redirect back to the
  fan-out; and it pointed away from the recovery `VENDORING.md` already prescribes — re-run
  the fan-out from Core, never patch the lock by hand.

  That line is read at the worst possible moment. `core-integrity.sh` reports `TAMPERED
  (core/ edited since sync)` whenever the vendored tree and the lock disagree, which reads
  like someone hand-edited `core/`; the first thing the confused reader does is open
  `core.lock`, where the header sent them to a dead end. The generated header now names the
  real recovery and says why the hand route fails, and the two docs that repeated the
  `make core-lock` caveat are corrected — they warned it was _missing_ in some repos,
  which understated it: it does not do the job anywhere.

  Note for the first sync after this lands: the header's bytes change, so `sync-core.sh`'s
  idempotency skip will not fire on that pass and each repo takes one
  `chore(core): core.lock → …` commit. Nothing else moves. Left open in #557: whether
  `dotfiles-Offense` should keep a `core-lock` target now that nothing points at it.

- **The doctor's wirable list was three hand-synced copies with nothing able to see a drift,
  and no test asserted that a `✓` row means Core actually wired anything.** (#447) Meta-issue
  #447 collected five bugs — #418, #420, #423, #424, #425 — as one defect: a name used as a
  proxy for a capability. All five are fixed and closed, and the seam that fixed the presence
  half is `_core_doctor_bin`, which resolves a canonical row name to the binary that actually
  backs it (`fd`→`$FD_BIN`, `bat`→`$BAT_BIN`, `git-*`→git's exec-path). Its proposed
  `_core_have_override` was **not** taken, for the reasons recorded at the v4.13.2 entry below
  and in `30-functions.zsh` — that decision stands and this change does not revisit it.

  What #447 was right about, and what was still outstanding, is the OTHER axis. `_core_wired`'s
  `case` arms, `_core_doctor_json`'s `wir=(…)` and `_core_doctor_render`'s `wirable=(…)` were
  three literals of the same five names, kept in step by hand — precisely the arrangement
  `_CORE_DOCTOR_GROUPS` exists to prevent on the tool axis. Worse, it was **unobservable**: the
  render⇄json parity test stubs `_core_have` false, which makes the "integrations wired" block
  skip every entry, so the one guard that might have noticed is blind to this list by
  construction. There is now a single `_CORE_DOCTOR_WIRED`, read by both renderers, and the
  drift is guarded in both directions — a name listed with no `case` arm (which renders a
  permanent `○ (idle)` no user action can clear) and an arm no renderer iterates (which
  reports nothing at all, the way twelve tools went unreported on the tool axis for releases).
  To make the first testable, `_core_wired`'s fallthrough returns **2** — "no arm for this
  name" — where an idle-but-known tool still returns 1. Both callers test only for zero, so
  no report changes: the rendered output and `--json` are byte-identical across this change.

  And #447's "worth pairing with a test" now exists, generalised past the single tool it was
  written against: for **every** tool `00-tools.zsh` probes, "the doctor says present" and
  "Core set the `HAVE_*` flag" must be the same boolean, on the real box the suite runs on.
  That is #425's disagreement stated as an invariant instead of an anecdote — it had a
  `procs`-shaped check only because `procs` is what got reported. The tool→flag mapping is
  read out of the source, so the two irregular names (`ast-grep`→`HAVE_ASTGREP`,
  `git-absorb`→`HAVE_GIT_ABSORB`) need no table and cannot rot. A second guard closes the hole
  that mapping leaves behind — deriving both sides from the same line means DELETING a
  detection line removes it from the comparison rather than failing it — by requiring every
  doctor row to have a probe behind it, with `op`, `fd` and `bat` named as the three
  deliberate exceptions rather than waived in prose.

  Also: the existing "reports every tool 00-tools.zsh probes" guard anchored on `^_have`
  followed by exactly one literal space, and `00-tools.zsh` aligns some trailing comments with
  two — so `tldr` had been silently outside its coverage. 37 rows → 38.

- **`jnv` is in Arch's `extra` now, so the matrix stopped sending Arch users to the AUR.**
  (dotgibson/dotfiles-Arch#87) The package landed as `jnv` 0.7.1-1 on 2026-04-01; `pacman -Si
  jnv` on a current box reports `Repository: extra`. The table's Arch cell said `AUR` and
  footnote ¹⁷ prescribed `paru -S jnv`, which asked readers to build an AUR helper for a tool
  `pacman` has been able to install for four months.

  Footnote ²⁴ also used jnv as its yardstick for the worst packaging shape in the table —
  lnav is "macOS-only in practice" _rather than jnv's "barely packaged anywhere" one_. With
  brew and `extra` both carrying it that overstates the case, so the contrast is now the
  narrower and still-true one: two platforms package jnv, everywhere else is `cargo`.

  What has **not** changed is the decision underneath: jnv stays detect-only on Linux. It is
  in no `install/packages.txt` and no `bootstrap.sh` installs it, so `HAVE_JNV` still lights
  only for a box that opted in. Being packaged made the _instruction_ wrong, not the policy —
  wiring it into the per-repo bootstrap remains the tracked follow-up it already was.

- **`PORTING-MATRIX.md`'s openSUSE story was written for Leap 15.6, which is EOL.**
  (`dotgibson/dotfiles-openSUSE#89`)
  Four passages still described a release nobody runs; two of them gave advice that is now
  wrong rather than merely dated. All figures below were verified against the `repo/oss`
  binary indexes for Leap 16.0, Leap 16.1 and Tumbleweed on 2026-08-21 — both arches, since
  the Python packages are `noarch` and an `x86_64`-only pass misses them.

  `tealdeer` (footnote ¹) is the one real availability break: it is in Tumbleweed at 1.8.0 and
  in **neither** Leap 16.0 nor 16.1. The footnote said "also Leap 15.6 … on older Leap, cargo
  install", which reads as _newer Leap has it_ — the opposite of the truth. It now names the
  two ways in on Leap (the `utilities` OBS repo, which really does build it, or cargo) and
  records the trap `dotfiles-openSUSE` hit shipping the fallback: the crate is `tealdeer` and
  the binary is `tldr`, so a presence guard on the crate name never fires.

  Footnote ¹⁸ hedged that "**Leap 15.x was not separately audited**" and told readers to fall
  back to the ³ cargo/go path there. Leap 16.x _has_ now been audited, and all seven of that
  footnote's packages resolve on both 16.0 and 16.1 via Backports — `starship` 1.21.1, `atuin`
  18.3.0, `yazi` 25.5.31, `viddy` 0.4.0, `ouch` 0.5.1, `doggo` 1.0.5, `ast-grep` 0.28.0. So
  `zypper in` is the right first move on Leap too; the note now frames those versions as a
  floor to check rather than prescribing a source build nobody needs.

  That same footnote closed by saying moving these into `install/packages.txt` was
  "deliberately **not** done". `dotfiles-openSUSE` has since made the opposite call — its list
  is packaged-first and carries `starship`, `atuin` and `yazi`, which is what keeps three
  unpinned `curl | sh` installers off its happy path. The footnote was describing a policy the
  fleet had already reversed.

  Footnote ¹⁹ (`gping`) cited Leap 15.6 at 1.16.1. Both supported Leaps carry 1.17.3 through
  Backports (`bp160.1.13` / `bp161.1.6`), so the tool is available there without adding a repo.

- **Docs-only PRs were permanently unmergeable.** `audit-alpine` and `audit-arch` are
  required status checks on `main`, but both carried a job-level
  `if: needs.changes.outputs.shell == 'true'` — so any change that touched no shell files
  reported the `skipped` conclusion, which a repository ruleset does not accept as satisfying
  a required check. The branch was then blocked with "5 of 5 required status checks are
  expected" and no way to clear it short of an admin override. Both legs now run
  unconditionally and gate their **steps** instead, so they report `success` on a change they
  cannot be affected by, at the cost of one runner boot. The container is still never spun for
  a docs- or nvim-only change, which was the whole point of the axis.

- **`PORTING-MATRIX.md` no longer claims a fleet-wide absence that one repo falsifies.**
  (dotgibson/dotfiles-Alpine#103) Seven footnotes asserted some form of "no Linux repo's
  `install/packages.txt` carries it" or "the only tool in this table that nothing in the fleet
  installs". Re-verified 2026-08-21 against all six Linux repos plus the MacBook `Brewfile`:
  `dotfiles-Alpine` carries `hyperfine`, `shellcheck`, `shfmt`, `lnav`, `git-absorb`, `gping`,
  `watchexec` and `jujutsu`, and installs `ouch` from `bootstrap.sh`; `dotfiles-Gentoo` carries
  four of those. The audit that filed this proposed narrowing the claims to "except
  `dotfiles-Alpine`" — that would have been a second wrong absolute, since it could only see
  the Alpine caller. So ²¹ now carries a per-tool coverage table and the prose defers to it,
  while ⁸, ¹⁹, ²⁴ and ²⁶ name their real exceptions and ²⁵ is rewritten rather than qualified.

  ¹⁴ was the one with teeth: it prescribed keeping `duf`/`glow`/`ouch` in Alpine's
  `packages.txt` "as a best-effort that `apk add` skips" — the exact footgun that repo
  documents against, since `apk` fails the whole transaction on one unknown name, so a
  permanently-unresolvable entry breaks the bulk `apk add` on **every** run. It also called
  `ouch` a `go install`; it is `cargo install --locked ouch --no-default-features`, because
  bzip3's bindgen build cannot `dlopen` libclang under musl's static linking.

- **`PORTING-MATRIX.md` no longer sends a reader to a row that isn't there, a `go install`
  that builds the wrong major, or a shadowed `sg`.** (#431) The issue asked for an apt column
  for Debian/Ubuntu distinct from Kali's; that landed with `dotfiles-Debian` in #505, and every
  tool the issue measured on Ubuntu 24.04 now matches the column. What its noble provisioning
  also exposed — and what this fixes — are three things that were wrong for the whole fleet,
  not just apt boxes.

  `core-doctor` probes `mise` and `uv`, and both have a `HAVE_*` flag, but neither had a row in
  the package table — so for exactly those two the "install missing" hint's promise ("see
  `core/PORTING-MATRIX.md` for the per-tool name and install path") resolved to nothing. They
  have rows now, with a footnote (³⁰) for the chicken-and-egg `mise` creates: six other
  footnotes prescribe `mise use -g <x>` as the fallback, and every `bootstrap.sh` reaches for
  `mise exec go@latest` when no Go toolchain is present, so it is a prerequisite of the table
  rather than an entry in it. `uv` turns out to be the sharpest argument for splitting the two
  apt columns in the first place: kali-rolling ships `uv` 0.9.17 and Ubuntu 24.04 ships none.

  The `go³` cells named no module paths, and the module path is usually not the repo URL. Four
  of the six go-installable rows need a major-version suffix, a `cmd/` subpath, or both —
  `github.com/joshmedeski/sesh/v2`, `github.com/mikefarah/yq/v4`, `mvdan.cc/sh/v3/cmd/shfmt`,
  `github.com/mr-karan/doggo/cmd/doggo` — so a naive `go install <repo>@latest` fails or
  silently builds an abandoned major. Footnote ³¹ now lists all of them, verified against each
  project's own `go.mod`. That verification caught a live one: Charm has moved its tools off
  GitHub as a module host, so `glow` is `charm.land/glow/v3` and `gum` is `charm.land/gum/v2`.
  #431 reported `github.com/charmbracelet/glow/v2`, which was correct when it was filed and is
  now two majors stale.

  Footnote ¹¹ claimed `sg` "can collide with `setgroups`" and that ast-grep "shadows nothing".
  Both were wrong. `sg(1)` is a symlink to `newgrp` — from `login` on the Debian family,
  `shadow` elsewhere — and the `ast-grep` crate installs `sg` as a second binary. The second
  claim was merely imprecise until #425, which put `${CARGO_HOME:-~/.cargo}/bin` on PATH ahead
  of `/usr/bin`: on any box with a `cargo install`ed ast-grep, a bare `sg` now runs the search
  tool instead of switching group. A hypothetical shadow became a real one, and the doc still
  said it couldn't happen.

- **A `cargo install`ed tool now gets its `HAVE_*` flag, its alias and its shell
  integration — `core-doctor` and the flags no longer disagree about the same box.** (#425)
  `zsh/00-tools.zsh` put only `~/.local/bin` on PATH before probing, and computed all 43
  `HAVE_*` flags immediately after. The Rust bindir arrived far later — via the OS layer at
  band 80, and via mise's activation 200 lines further down the same file — so anything
  `cargo install` had written to `~/.cargo/bin` was simply invisible at detection time.
  `core-doctor`, which probes live from an interactive prompt against the finished PATH,
  saw it and printed `✓`. Same shell, two answers, and the flags were the ones that
  mattered: `20-aliases.zsh` never made the alias.

  That subset is not small — `PORTING-MATRIX.md` prescribes cargo as the source for
  `procs`, `xh`, `atuin`, `ouch`, `jnv`, `ast-grep`, `watchexec`, `difft`, `viddy` and
  `yazi` on distros that do not package them — and for atuin the failure was not cosmetic.
  An unset `HAVE_ATUIN` means `atuin init zsh` never runs, so Ctrl+E is dead and **no
  history is recorded at all**, while the doctor reports `✓ atuin` in the tool row and
  `○ atuin (idle)` below it. That reads as "installed but idle" rather than "Core never
  initialised it", which is why this could sit unnoticed.

  All four per-user bindirs now join PATH before detection, not just cargo's: `~/.local/bin`,
  `${CARGO_HOME:-~/.cargo}/bin`, `$GOBIN` (falling back to the **first** entry of `$GOPATH`,
  which is a path list — expanding `$GOPATH/bin` against `/a:/b` would probe a nonexistent
  `/a:/b/bin`), and `~/.atuin/bin`, which is where atuin's own installer writes and so had
  the identical hole. The cargo and go dirs are resolved through their environment variables
  rather than hard-coded, because rustup and go honour them and a box that relocates one
  would otherwise keep missing its tools — hard-coding `~/.cargo/bin` does not fix this bug,
  it moves it somewhere less obvious.

  This is deliberately the same list, the same resolution and the same order as
  `lib/bootstrap-lib.sh`'s `blib_user_bindirs_on_path`, which fixed the identical blind spot
  on the bash side in v4.13.2: bootstrap's `command -v` guards and the shell's `HAVE_*`
  probes must not be able to disagree about where a tool lives. Neither can source the other
  — one is bash and runs before any Core shell exists — so both carry a note pointing at the
  other. The order puts `~/.atuin/bin` ahead of `~/.local/bin`, matching
  `examples/atuin-daemon.service` and the OS layers rather than inverting them, and a test
  pins it so it stays a decision.

  The OS layers' own prepends (`os/*.zsh`) become inert rather than duplicative — both sides
  guard on `":$PATH:" != *":$d:"*`, so the later one simply finds the dir already there. They
  can be dropped on their next pass; nothing breaks if they are not.

  Nine hermetic cases cover it, each pinning `HOME` to a fixture and `PATH` to a stub dir:
  the reported reproducer, the atuin variant, `CARGO_HOME`/`GOBIN`/`GOPATH` relocation,
  idempotence, phantom-directory rejection, the ordering, and the disagreement itself
  (`core-doctor --json` and `$HAVE_PROCS` asserted to agree). All nine are red against the
  previous `00-tools.zsh`. They neutralise an inherited `CARGO_HOME`/`GOBIN`/`GOPATH` for the
  reason v4.13.2 records: the resolution exists so a relocated dir still works, so a
  developer who exports one retargets the lookup and reds a healthy tree while no CI runner
  — none of which export it — ever sees the failure.

  Worth noting what this does **not** fix, and #425 says so explicitly: `HAVE_*` is still a
  snapshot taken at band 00, while PATH keeps being assembled through band 99. mise's
  `hook-env` rewrites it per directory, and `80-os.zsh`, an `85-*` role and `99-local.zsh`
  all load after every probe, so a tool contributed by any of those still gets no flag while
  the doctor reports it present. A `✓` still means "on PATH when you asked", not "Core wired
  this". That half is tracked separately.

- **`PORTING-MATRIX.md` footnote ⁸ no longer tells the reader `dnf install jujutsu` works.**
  It listed Fedora among the distros that package jj. Fedora does not: there is no
  `jujutsu`, `jj` or `jj-cli` on F43, F44 or rawhide, and — unlike `sd` and `gron`, which
  were dropped — no retired build to point back at. Fedora now sits with Debian/Kali and
  Gentoo in the `cargo install --locked jj-cli` group. Documentation-only: jj is opt-in and
  carried in no OS repo's `packages.txt`, so nothing installs differently — but the footnote
  is the one place a reader looks for the install path, and it named a package manager that
  would have answered "No match".

## [v4.13.2] - 2026-08-19

### Fixed

- **`make audit` no longer reds `blib_user_bindirs_on_path` for anyone with `CARGO_HOME`
  set.** The helper resolves the cargo bindir through `${CARGO_HOME:-$HOME/.cargo}/bin`
  deliberately — hard-coding `~/.cargo/bin` would break a box that relocates it, which is the
  bug it exists to prevent. Its fixture asserts the `$HOME`-relative defaults, and those are
  reached only when the vars are absent; but the subshell pinned just `HOME` and `PATH`, so an
  exported `CARGO_HOME` retargeted the lookup and the fixture's own `.cargo/bin` never landed.
  A developer with Rust configured — most operators, and exactly who `make audit` runs for —
  saw a failure on a healthy tree, while no CI runner exports it and all four lanes stayed
  green.

  The fixture now unsets `CARGO_HOME`, `GOBIN` and `GOPATH`. Worth noting where the leak
  actually lived: the relocation block further down the same file sets these vars explicitly
  and was always immune — it was the default-path cases that inherited. A gap between two
  blocks rather than a coverage hole, and the same shape as the `GHOSTTY_SHELL_FEATURES` leak
  fixed one release earlier.

- **A stalled Ubuntu security index no longer reds CI lanes that never needed it.** The Linux
  setup step gated on `apt-get update` succeeding, and under `set -euxo pipefail` a second
  failed refresh killed the step before `apt-get install zsh` was ever attempted. On both
  2026-08-18 and 2026-08-19 `archive.ubuntu.com`'s `noble-security` index stalled mid-fetch
  (with the Azure regional mirror dark, every index `Ign:`), and the job died at `timeout(1)`'s
  exit 124 with no test executed — while the same logs showed `Hit: … noble InRelease`
  succeeding. Only the _security_ pocket wedged; `zsh` lives in `noble/main`. The archive was
  reachable for everything the job actually needed, and it failed anyway.

  The refresh is now best-effort and the **install is the gate** — a stale index nothing reads
  is not this job's problem, whereas not having `zsh` still fails it. The install carries its
  own `timeout(1)` bound so it cannot hang in the refresh's place. The block was duplicated
  verbatim across five workflows (`ci.yml` twice, plus `lint-call.yml`, `sync-fanout.yml`,
  `atuin-guard-verify.yml`); all five are fixed, since fixing one would have left the same
  stall live on four other lanes.

- **`make audit` no longer reds 7 OSC 133 assertions when it is run from inside Ghostty.**
  `00-tools.zsh` deliberately stands the marks down when `GHOSTTY_SHELL_FEATURES` is set and
  `$TMUX` is empty — Ghostty injects its own prompt marking outside tmux, so Core must not
  double-mark. Every mark-ON case in `scripts/test-core.sh`'s OSC 133 section pins `TERM` and
  `TMUX` explicitly for exactly that reason, but `ucheck` ran a bare `env`, which inherits the
  caller's environment. Auditing from the terminal this repo ships a config for therefore
  cleared `_CORE_OSC133`, left `_core_osc133_prompt` undefined, and failed 7 assertions about
  the shell layer while proving nothing about it.

  `ucheck` now runs `env -u GHOSTTY_SHELL_FEATURES`; the per-case assignments come after the
  option, so the two cases that set it deliberately still win. **CI could not have caught
  this** — no runner is hosted in Ghostty, so all four audit lanes were green on the identical
  tree — which is why the regression gate added alongside drives a mark-ON case with the
  variable genuinely exported rather than passed as an argument.

- **A repo renamed upstream is no longer skipped by the whole fleet toolchain because its
  clone directory still carries the old name.** `scripts/os-repos.txt` names the fleet by
  repo NAME, and `sync-core.sh`, `fleet-drift.sh` and `core-integrity.sh` each turned that
  name into a path by string-joining it onto the fleet root. Git follows a GitHub rename on
  its own; a directory name does not. So a machine that cloned `dotfiles-Kali` before it
  became `dotfiles-Offense` had a correct remote, a correct `core/` subtree and a correct
  `core.lock` — and the fan-out skipped it as "not cloned", drift reported "not checked out",
  and the integrity sweep could not have seen a tampered `core/` there at all. Two of those
  three are false-CLEAN results on gates whose entire job is to notice, and the only remedy
  on offer was "go `mv` the directory", on every machine, for every future rename.

  All three now resolve through one shared `resolve_repo_dir` (`scripts/lib/common.sh`):
  the directory-name lookup stays the fast path and keeps precedence, and only when no such
  directory exists does it ask each sibling clone what it actually is, matching on the repo
  slug in `origin`'s URL. Both URL shapes parse (`https://host/owner/repo` and
  `git@host:owner/repo`, with or without `.git`) and matching is case-insensitive, as GitHub
  itself is. A clone whose origin names a different repo is not adopted, one with no origin
  is stepped over rather than aborting the sweep, and a genuinely absent repo still reports
  against the conventional path so the advice names where it looked. `sync-core.sh` prints
  the resolved path when it isn't the conventional one, so a fan-out into a pre-rename
  directory is visible in the log instead of a surprise underneath the git output.

### Documentation

- **`blib_link_role_layer`'s migration note described a migration that has since
  happened.** It read, in the present tense, that "the offensive repo hand-rolls
  `<config>/kali/templates`" and instructed a consumer to relocate them and update two
  shipped docs "in the same change that adopts the helper". dotfiles-Offense adopted the
  helper and did exactly that, so the instruction now describes work that is done —
  misleading anyone reading the helper to decide what a consumer still owes it. Rewritten
  as the record of a completed move, keeping the reasoning that matters (why the
  destination is named for the ROLE rather than the distro, and why neither a compat
  symlink nor a namespace parameter was the answer). Comment only — no behaviour changes,
  but it is vendored into all nine consuming repos, so the stale text was live fleet-wide.

## [v4.13.1] - 2026-08-18

### Fixed

- **The reusable `bootstrap-test` no longer assumes every caller has an OS-native layer.**
  It asserted `~/.config/zsh/80-os.zsh` unconditionally, which is right for the nine OS
  repos and wrong for a ROLE repo: `dotfiles-Offense` and `dotfiles-Defense` wire Core plus
  a band-85 role stage and deliberately link nothing at band 80, so the shared test red a
  repo doing exactly the right thing. The check now arms itself on whether the caller ships
  an `os/*.zsh` — self-derived, the same way the atuin check is, rather than a new input
  every role repo would have to remember to pass. Found by `dotfiles-Offense` as it dropped
  its OS layer to `dotfiles-Debian`.

## [v4.13.0] - 2026-08-18

### Documentation

- **Corrected the keepalive stall's stated cause, and recorded what is actually known.** The
  `sudo -n -v` assertion in `scripts/test-core.sh` can stall for one full refresh interval.
  The code described that cost as a determinate property ("EXACTLY ONE INTERVAL … measured
  three ways"); instrumenting 16 suite runs shows it is **intermittent** — two stalls
  (50.017s, and 20.016s driven at 20), every other run 0.02–0.13s. A race, which is why it
  usually reproduces as "already fast" and reads as fixed.

  Two explanations are now ruled out in the comments rather than left for the next person to
  re-derive. Pipe retention keeping the command substitution open reproduces the one-interval
  signature by construction (0.329s redirected vs 7.023s not, at an interval of 7), but
  sampling `/proc/<pid>/fd` across an entire stall — 1644 samples — found one sleeper with all
  three fds on `/dev/null` throughout and its loop shell alive, so nothing was holding a pipe.
  Removing the substitution therefore does not help either: measured on the converted block,
  2 stalls in 2 runs.

  What the sampling does show is a **teardown** stall — the loop did not act on its `TERM`
  until its sleeper expired, while the caller sat in `blib_sudo_keepalive_stop`'s `wait`. That
  pointed at the right place, and it is fixed in the entry below (#529); this entry changes no
  behaviour on its own. `BLIB_SUDO_KEEPALIVE_INTERVAL` does not bound the poll as was claimed.

### Fixed

- **`ci.yml` ran the whole matrix twice on every branch push, and the comment claiming it
  did not was wrong.** `on:` fired for both `push: branches: ["**"]` and `pull_request`,
  and the concurrency key was documented as deduping that — it cannot. `github.ref` is
  `refs/heads/<branch>` on a push and `refs/pull/<n>/merge` on a pull_request, so the two
  events land in different groups and both run to completion.

  The cost was 7 job-runs becoming 14, and — worse — each check _name_ existing twice on
  one SHA, leaving the merge gate to take whichever finished last. #531 was blocked
  exactly that way: its `pull_request` `audit (ubuntu-latest)` passed, then the `push`
  run's copy concluded `cancelled` and that was the result the ruleset saw.

  `push` is now `main`-only, with `pull_request` covering branches. The two events were
  never redundant, which is why `pull_request` is the one kept: `push` tests the branch
  head, `pull_request` tests an ephemeral merge into `main` — what merging actually
  produces. A branch pushed with no PR open now gets no CI until one exists; that is
  already the fleet convention, since every OS repo ships `branches: [main, master]` and
  this repo was the lone holdout.

- **CI's `apt-get update` is now bounded, so a wedged Ubuntu mirror fails fast instead of
  hanging a job to death.** On 2026-08-18 `archive.ubuntu.com`'s `noble-security` index
  stalled mid-fetch and took out four `audit (ubuntu-latest)` legs at 15 minutes each —
  every one in the install step, with the audit never reaching a test. The Azure regional
  mirror was dark (every `azure.archive.ubuntu.com` index `Ign:`), so apt fell back to
  `archive.ubuntu.com`, fetched three of four indexes, and wedged on the fourth.

  The `find -delete` already in front of these updates does not cover that, and was never
  meant to: it drops **third-party** repos from `sources.list.d`, while
  `azure.archive.ubuntu.com` is Ubuntu's own **regional mirror** in the main sources list.
  Different repo class, different failure.

  All five CI `apt-get update` sites now run under three layers —
  `Acquire::http|https::Timeout=20` bounds a single connection, `Acquire::Retries=3`
  re-attempts a failed index, and `timeout -k 10 120` is the backstop, because a transfer
  that trickles keeps the socket warm and evades apt's own timeout entirely. The whole
  thing is retried once, then allowed to fail: a genuinely unreachable archive must go
  red, not be papered over.

  The **120s** is load-bearing, not a round number. The bound has to be small relative to
  each job's `timeout-minutes` or it merely relocates the hang — two 300s attempts inside
  a 15-minute job would leave 5 minutes for an audit that needs ~7, and the job would
  still die. A healthy update here is 5-15s, so 2x120s is generous for the slowest honest
  run and still leaves 11 of the 15 minutes for the audit.

  `lint-call.yml` is among the five, so every OS repo consuming it at `@v4` picks this up
  when the tag next moves. It stays inlined rather than extracted to a shared script
  precisely because that workflow checks Core out at `ref: v4` — a script added on `main`
  would not exist there until a release.

- **`blib_sudo_keepalive_stop` could block for a full refresh interval — 50s in a real
  provisioning run** (#529). The helper exists to stop a bootstrap hanging on an invisible
  sudo prompt; intermittently it did the hanging itself.

  A `TERM` aimed at the refresher's sleeper is sometimes **accepted by `kill(2)` and never
  acted on**. Measured in-loop: `kill` returns 0, and 30.003s later the sleeper exits
  normally having slept its whole interval, with the handler blocked in `wait` and `stop()`
  blocked behind it. The sleeper had no signal blocked, ignored or caught — it was killable,
  and the signal was lost rather than refused.

  The handler now sends `KILL` after `TERM`. It cannot be lost or ignored, and it is safe
  precisely because the target is a bare `sleep`: no state, nothing to flush. There is no
  grace period between the two — which signal ends the sleeper does not matter, and pausing
  to find out would put latency back into teardown. (Its exit status proves nothing either
  way: with no gap, a sleeper that simply was not scheduled in between dies of `KILL` and
  reports 137 even when `TERM` was delivered normally.) Measured outcome: **zero stalls
  across 7 instrumented runs with `stop()` steady at 2–3ms**, against roughly one 30s stall
  every 2–3 runs before.

  **The mechanism was not isolated** and the fix does not claim to explain it — it
  reproduces only inside the full behavioral suite, never standalone, at no delay between
  `start()` and `stop()` from 0–50ms, and not through the suite's own `sleep` shim. Since a
  1-in-3 race cannot gate anything, the new regression test forces the case instead: a
  sleeper that **ignores `SIGTERM`** is the lost signal made deterministic, and `stop()` is
  asserted on wall clock to return well inside the interval. Without the `KILL` it blocks
  the full interval, every time.

- **`audit-core.sh --json` reported `failed` on a tree the identical non-JSON run passed**
  (#524). `--json` is documented as an output-format switch — "lets a CI step / editor parse
  the result instead of scraping coloured text" — so it must not move the verdict, and it was
  moving it in the direction that matters: a **false red**.

  `--json` sets and **exports** `CORE_JSON=1`, which is right for its purpose (nested gates must
  keep stdout clean for the JSON object), and `common.sh`'s `skip()` then prints nothing. Because
  the variable is exported it also reached the hermetic fixture that runs `sync-core.sh`, whose
  absent- and `core/`-less-repo reports go through `skip()` — and two assertions grep for exactly
  those lines. They failed for a reason unrelated to what they test; `sync-core.sh`'s bucketing
  was never wrong.

  This trap had already been found once and fixed in ONE place: `_tr_run` carries `-u CORE_JSON`
  with a comment describing this precise mechanism. Its two siblings never got it. Both now do —
  including the `--dry-run` call site, which was not failing only because it happens not to assert
  on `skip()` output, and which is the identical trap one assertion away.

  The regression gate is the point, though. The bug was **invisible from inside a normal run**:
  both assertions passed under a bare `test-core.sh` and failed only when the parent was invoked
  with `--json`, so the suite went on certifying `sync-core` while the JSON interface called the
  tree red. A new check drives the same fixture with `CORE_JSON=1` exported and requires the
  identical verdict, so the failure now surfaces in an ordinary run. It asserts on the skip LINES
  rather than the summary counts on purpose: the counts come from `sync-core.sh`'s own `printf`
  and survive a silenced `skip()`, so a count-only assertion would have passed straight through
  this bug.
- **`HAVE_GIT_ABSORB` was set for a subcommand `git absorb` could no longer dispatch**, when
  `GIT_EXEC_PATH` is set. Shipped in #503 and caught in its own review. `GIT_EXEC_PATH`
  **replaces** git's compiled-in exec-path rather than adding to it — point it at an empty
  directory and `git absorb` answers `'absorb' is not a git command` even with the binary
  still sitting in the default location. The fallback treated it as one more candidate and
  fell through to the derived `<git-prefix>/{lib,libexec}/git-core` paths, so the flag said
  present while `core-doctor` — which asks `git --exec-path`, and therefore inherits the
  override — correctly said absent. That is the exact flag-vs-doctor disagreement of #425,
  re-created on a new axis by the change meant to remove it. An **exported** override is now
  probed **exclusively** — exported because git reads the variable from its environment, so
  a plain shell assignment (`scalar`, not `scalar-export`) never reaches git and must be
  ignored here too, or the mirror-image disagreement appears: the flag honouring an override
  git does not see. Three tests pin it: the flag stays unset under an empty exported
  override with the default exec-path populated, flag and doctor are asserted to agree on
  that configuration, and an unexported `GIT_EXEC_PATH` is ignored by both.

  The block is also made hermetic against the developer's own environment. `ucheck` runs
  `env "$@" zsh`, which layers the named variables ON TOP of the inherited environment rather
  than clearing it, and the suite's git stub honours `GIT_EXEC_PATH` exactly as real git does
  — so on a box with that variable exported, four of these cases failed for a reason
  unrelated to the code under test. It is now unset once for the whole block, and the
  unexported case unsets before assigning, because assigning to an already-exported parameter
  preserves the export attribute.

  Three documentation claims contradicted each other after #503 and are reconciled:
  `PORTING-MATRIX.md`'s ²⁶ preamble still said flatly that git-absorb installs on `PATH`,
  two paragraphs above the correction saying the Debian family does not; the v4.10.0 entry's
  "Homebrew and Debian/Kali all on 0.9.0" is now superseded inline, since Kali ships
  0.6.17-2+b4 and so openSUSE was not the only laggard; and this entry's own "whole Debian
  family" is narrowed to what was actually observed — Kali on-box, Ubuntu 24.04 from the
  reporter, Debian proper unverified. (`zsh/00-tools.zsh`, `scripts/test-core.sh`,
  `CHANGELOG.md`, `PORTING-MATRIX.md`)

- **`make publish` swallowed the one notice it had for you, and could hang a local
  `make audit`.** Follow-ups to the v4.12.2 publish — three found in review of the fix for
  it, one from running the release, and one correcting recovery advice that this changelog
  itself had got wrong:

  `tag-release.sh` called a `note` helper that **does not exist** — `scripts/lib/common.sh`
  defines `pass`/`skip`/`fail`/`hdr`/`have` — so the line printed `note: command not found`
  and the operator never saw its message. That branch only runs when `main` has advanced
  past the release commit, an uncommon path no test covered, and a bare word that might be
  a command on `$PATH` is not something the linter can flag. It fired for real while
  publishing v4.12.2, discarding exactly the notice it exists to give: that `git describe`
  on `main` would now report commits-since rather than a clean tag. A new assertion greps
  the publish output for `command not found` — deliberately generic, so it catches the next
  undefined helper rather than only this one.

  The `tag.gpgsign` probe inherited `$EDITOR`. With no message and no `-m`, git opens an
  editor to collect one — so on a developer's interactive `make audit` it would launch vim
  and **block the suite**, where CI (no editor) merely errored. Verified by simulating a
  blocking editor: git really does invoke it. The probe now forces a no-op editor, so the
  empty-message failure is deterministic and key-free everywhere.

  `RELEASE-RUNBOOK.md` and `RELEASE-STRATEGY.md` still documented the manual alias fallback
  as a bare `git tag -f`, the exact form the fix declares broken — a signing operator
  following either would have hit the same abort, and a non-signing one would have created
  a lightweight alias contradicting the new contract. Both now use `git tag -fa … -m`.

- **`core-doctor` reported `✗ git-absorb` on Debian-family boxes, for a tool that was
  installed and working** (#424). Debian packaging puts a `git-<verb>` subcommand in git's
  **exec-path** — the directory `git --exec-path` names — and keeps it off `PATH` on
  purpose: git finds the binary there itself, and the user invokes it as `git absorb`. The
  presence probe was `command -v git-absorb`, so the row was wrong wherever that convention
  is followed. Two boxes, two distros: **Kali** `git-absorb` 0.6.17-2+b4, verified on-box —
  `dpkg -L` lists `/usr/lib/git-core/git-absorb` and a man page and nothing in a `PATH`
  directory, `command -v` finds nothing, and `git absorb --version` works — and **Ubuntu
  24.04** 0.6.11, from the reporter's `dpkg -L` in #424. Debian proper is **not** verified;
  its package page lists 0.9.0-2 and nobody has checked where that build lands, so the
  claim here is the convention plus two confirmations of it, not a survey. The `✗` implied
  the verb was unavailable, so a reader would go install what they already had.

  `_core_doctor_bin` (`30-functions.zsh`) gains a `git-*` arm that resolves through git's
  exec-path when the bare name misses, and hands back an **absolute path**. That is what
  both consumers need: `command -v` on a path is exactly as honest as the `PATH` probe, and
  `core-doctor -v` forks `"$bin" --version`, which a bare `git-absorb` could not run on this
  family at all — so the version readout is fixed in the same change, the way #418's
  `bat`/`batcat` fix was. The path never reaches the report; the render and the `--json`
  keys still print the canonical name.

  **Fork budget.** `PATH` is probed first, so a box that never had the bug (Arch, Alpine,
  Gentoo, Homebrew, macOS) pays one lookup and no fork. Only a miss asks git, and the answer
  is cached in `_CORE_GIT_EXEC_PATH` for the life of one report — `core-doctor` drops the
  cache on entry, since only the TTY render runs in a `$(…)` subshell and a cache left
  standing would answer for a box that has since installed git or moved `GIT_EXEC_PATH`.
  Three tests pin this: two `git-*` names resolve on one fork, git is never invoked at all
  when the subcommand is on `PATH`, and a second report re-derives after the exec-path moves.

  `00-tools.zsh` is fixed too, without breaking its zero-fork contract: `HAVE_GIT_ABSORB`
  falls back to a stat of `<git-prefix>/{lib,libexec}/git-core`, with the prefix derived from
  zsh's builtin `$commands` hash rather than spelled out as a distro path — or, when an
  **exported** `$GIT_EXEC_PATH` is in effect, of that directory **exclusively**, since it
  replaces git's compiled-in exec-path rather than adding to it. (That shipped as an additive
  candidate list; the correction and its reasoning are in the entry above.)
  Skipped entirely when the `PATH` probe already hit. The flag has no consumer today,
  but #425 is the reminder that a `HAVE_*` flag and the doctor disagreeing about the same box
  is itself a bug — and a test now pins the no-fork property, so "simplifying" it into a
  `$(git --exec-path)` fails CI.

  Meta-issue #447 proposed instead giving `_core_have` a tri-state override hook. Not taken:
  `_core_have` is a general primitive that `05-ui.zsh` calls on every confirm/spin/gum probe,
  so an override there taxes every call site to fix one command's inventory — and answering
  "present" for a name that cannot be executed would mislead any future caller. Resolving to
  a runnable path is strictly more information. `_core_doctor_bin` was already the seam for
  exactly this class.

  Two docs claimed the opposite of the truth and are corrected: `PORTING-MATRIX.md`'s ²⁶
  footnote ("no mainstream package does this") and the v4.10.0 entry below, which now carries
  the correction inline rather than being quietly rewritten. The version cell is corrected in
  the same pass — Kali ships 0.6.17-2+b4, not Debian's 0.9.0-2, so the two are no longer
  quoted as one cell, and whether Debian's own build uses the exec-path is marked unverified.
  Latent elsewhere: Git for Windows has a `mingw64/libexec/git-core` with the same shape, but
  scoop/winget/cargo installs land on `PATH`, so no `dotfiles-Windows` change is needed yet.

- **`clip` had no way to copy from a headless box, so `pbcopy`, tmux's `copy-pipe` and
  nvim's `"+y` were all dead over plain ssh.** The ladder ran WSL → macOS → Wayland →
  X11 and then gave up, and none of those exist on a machine you only ever ssh into —
  which is exactly where copying _out_ of the terminal matters most. It now falls back
  to **OSC 52**: the payload goes to the terminal as an escape sequence and the terminal
  emulator puts it on the clipboard of the machine you are sitting at, with nothing
  installed on the remote end. Core's tmux already sets `set-clipboard on`, so tmux
  forwards it rather than needing passthrough wrapping.

  Deliberately **last** in the ladder — a real backend is bidirectional and does not
  depend on terminal support — and it writes to `/dev/tty`, never stdout, because `clip`
  is used in pipelines and as nvim's provider where stdout carries the caller's data.

- **`clip`/`clip-paste` exec'd `xclip`/`xsel` without checking `DISPLAY`.** The Wayland
  branch above them checked `WAYLAND_DISPLAY`; the X11 ones checked only that the binary
  existed. On any desktop distro where something pulled `xclip` in as a dependency,
  `command -v` succeeded over ssh and the exec then failed for want of a display —
  _instead of_ falling through to a fallback that would have worked. This is what made
  the new OSC 52 branch unreachable in the most common real configuration.

- **`clip-paste` still fails on a headless box, and now says why.** There is no safe
  OSC 52 read: it means querying the terminal and waiting for a reply that most
  terminals refuse to send (letting a remote host read your clipboard is a genuine
  hazard), and one that never replies blocks forever. Nothing is lost — pasting _into_ a
  remote shell is what the terminal's own paste already does. The error names the
  asymmetry so it does not read as `clip` being broken too.

- **`make publish` could not move the `v4` major alias when `tag.gpgsign` is enabled.**
  `scripts/tag-release.sh` moved the alias with a bare `git tag -f`, expecting a
  lightweight ref. Under `tag.gpgsign = true` git makes every tag **signed** — therefore
  annotated — so the message-less form aborts with `fatal: no tag message?`. The publish
  died there, after the immutable `vX.Y.Z` tag had already been created locally — harmless
  debris, since `--publish` consults only whether the tag exists on **origin** and then
  force-recreates the local one, so a direct `make publish` retry works.

  The failure was well-placed — it happens **before** the atomic push, so nothing
  half-landed and neither `release.yml` nor `sync-fanout.yml` fired — but the release
  could not complete, and `v4` is the moving alias every OS repo's reusable-workflow
  caller pins to. Found cutting v4.12.2, the first release published from a box with tag
  signing on ([#506](https://github.com/dotgibson/dotfiles-core/issues/506)).

  The alias is now annotated with a message, exactly like the immutable tag beside it —
  which is also the better artefact for a force-moved pointer, since it records who moved
  it and when. Two assertions pin it: that a message-less `git tag -f` really does abort
  under `gpgsign` (so the guard is guarding something), and that the script no longer uses
  that form. Neither needs a signing key, so both run in CI — where this bug was
  structurally invisible, because CI signs nothing.

### Changed

- **The fleet entry `dotfiles-Kali` is renamed to `dotfiles-Offense`**, making the Role layer's
  two repos symmetric (`dotfiles-Offense` red / `dotfiles-Defense` blue) and naming the repo
  after the role it carries rather than the distro it happened to be built on. The GitHub
  repo is renamed in place rather than recreated, so it keeps its stars, issues and PRs, and
  existing clones and remotes keep working through GitHub's redirect.

  The rename is a **four-file coordinated edit**, exactly as `scripts/os-repos.txt`'s own
  header warns: the data file plus the hardcoded fallback arrays in `scripts/sync-core.sh`,
  `scripts/fleet-drift.sh` and `scripts/core-integrity.sh` — the fallbacks being what runs
  precisely when nobody is watching. `scripts/test-core.sh` asserts all four agree, so a
  partial rename fails the audit rather than silently dropping a repo from the fan-out.
  Fan-out order is unchanged: case-insensitively, `offense` sorts into the same slot `kali`
  held, between `gentoo` and `opensuse`.

  **Rename the GitHub repo and your local checkout together with this change.** The
  entries in `scripts/os-repos.txt` are _directory_ names — `sync-core.sh` resolves each
  against `REPOS_ROOT` on your disk — so a box still holding `~/…/dotfiles-Kali` gets
  that repo skipped by the fan-out. It says so (`skip: dotfiles-Offense (not cloned at
  …)`) rather than failing quietly, but a skipped repo is a repo that stops receiving
  Core, and `fleet-drift.sh` will report it red until the directory is renamed.

  Only the **repo name** moves. Every reference to Kali the _distro_ stays: `maint`'s
  `OS_ID == kali` upgrade guard, the `kalilinux/kali-rolling` CI images, the `Kali (apt)`
  columns in `PORTING-MATRIX.md`, and the Debian/Kali binary-name notes are all unaffected by
  what a repository is called. Historical `CHANGELOG.md` entries keep the old name too — they
  record what happened at the time.

  This is the first step of a larger split: `dotfiles-Offense` still carries its own
  OS-native layer today, and that half is moving to `dotfiles-Debian` so the role repo stacks
  on an OS repo the way `dotfiles-Defense` already does. Core's docs describe the repo as it
  is now, not as it will be.

- **Corrected a stale claim that `dotfiles-Defense` does not source the shared bootstrap
  scaffold** (`core.manifest`, `PORTING-MATRIX.md`). It does — and has since it stopped
  hand-forking the shared half. Both documents called it "the one documented exception" to
  `lib/bootstrap-lib.sh` and said its `bootstrap.sh` does not call `blib_link_core`; it calls
  it directly. What a role repo actually skips is `blib_link_os_layer`, because the `80` band
  belongs to the OS repo underneath — and `blib_link_role_layer` is what it will call in its
  place. Both documents now separate that contract from today's reality: neither role repo has
  adopted the helper yet (Defense still runs its own `wire_defense_stage`, Offense still calls
  `blib_link_os_layer`), because the helper has to ship in a Core release and fan out first.

- **CI's critical path drops from ~8 minutes to ~3, with no gate removed.** Measured, not
  guessed: on a typical PR run every job starts in parallel, so wall-clock is the slowest —
  `audit (macos-latest)` at 7m33, of which 7m08 is `audit-core.sh` itself and only ~25s is
  checkout plus every tool install. The structure was already doing its job (parallel legs,
  change detection, tool caching, the behavioral suite overlapped with the static gates,
  `cancel-in-progress`); the cost was concentrated in the suite. Profiling
  `scripts/test-core.sh` at **24% CPU** — waiting, not computing — put **247s of 286s in two
  places**, with the remaining ~600 tests costing ~40s combined. Both are addressed below.
  A plain shell change now runs the suite in **43s**.

### Added

- **A first-class Role band in the bootstrap scaffold and in tmux** — `blib_link_role_layer`
  (`lib/bootstrap-lib.sh`) and a `role.conf` hook (`tmux/tmux.conf`). Core has always
  documented a Role layer (band `85`–`94`) but shipped no wiring for one, so both role repos
  hand-rolled it — and had already drifted apart doing so: dotfiles-Defense honoured
  `BLIB_DRY` when dropping the stale pre-v4 unnumbered link and dotfiles-Offense did not, which
  made `--dry-run` mutate the box in one repo and not the other.

  `blib_link_role_layer <dotfiles> <config> <role>` is the twin of `blib_link_os_layer`, and
  `<role>` names both the directory and the file stem exactly as `<os>` does — so
  `offensive/offensive.zsh` and `defense/defense.zsh` are already where it expects them and
  nothing has to move. It links `<role>/<role>.zsh` → `zsh/85-<role>.zsh`,
  `<role>/<role>.conf` → `tmux/role.conf`, and `<role>/templates/` →
  `<config>/<role>/templates`, all `blib_want`-gated and all honouring `BLIB_DRY`.

  The tmux half is the part Core genuinely did not have. `tmux.conf` carried exactly ONE
  overlay hook — `os.conf` — so a role's tmux bits had nowhere to go, and dotfiles-Offense's
  `prefix + e` engagement popup was consequently smuggled into `os/kali.conf`, an OS overlay
  a role repo has no business owning. `role.conf` is sourced **after the pop-up bindings**,
  not beside `os.conf`, and the placement is load-bearing: `os.conf` only ever _sets_ options,
  whereas a role layer BINDS KEYS, and tmux gives a key to its last binding. Sourced early,
  any future Core `bind e` would silently take the key back.

  **One destination moves, for consumers to handle deliberately.** Defense already lands
  its templates at `<config>/defense/templates`, but the offensive repo hand-rolls
  `<config>/kali/templates` — named for the distro, which is the naming this rename
  retires. Adopting the helper there relocates them to `<config>/offensive/templates`, and
  two shipped docs quote the old path by hand (`offensive/hacktheplanet`'s
  `pseudo-shell.py` line, and `offensive/ippsec`); both need updating in the same change
  that adopts the helper. Deliberately not papered over with a compat symlink — that would
  preserve a `~/.config/kali/` on a repo no longer called Kali.

  **One role per box.** Both roles land on band `85`, so a machine wired for Offense and then
  Defense gets `85-offensive.zsh` and `85-defense.zsh` loading in glob order and a single
  `tmux/role.conf` owned by whichever ran last. That is not a supported configuration — an
  attacker station and an analyst station are different boxes — and spreading the roles across
  separate bands would only make the breakage quieter. There is deliberately no role
  `gitconfig` hook either: Core's `gitconfig` `[include]`s `os.gitconfig` and
  `local.gitconfig` only, neither role repo has ever had one, and an unused include rots.

- **`BLIB_SUDO_KEEPALIVE_INTERVAL` — the sudo keepalive's refresh interval is injectable**
  (`lib/bootstrap-lib.sh`), defaulting to the shipped 50s. It exists as a TEST SEAM: the block
  asserting that the background refresher uses `sudo -n -v` (validation mode, the
  restricted-sudoers fix) was measured costing **exactly one refresh interval** — 50.02s against
  the shipped default, and 3.02s / 7.02s when the interval was set to 3 and 7 — which was
  **17% of the whole behavioral suite for a single test**, on every CI leg of every repo. It now
  costs about a second.

  The delay is not the poll: the loop refreshes _before_ it sleeps, so the test's grep for
  `-n -v` matches on its first iteration. Something in that block waits out one sleeper anyway,
  and the same block reproduced standalone completes in 0.02s — so the responsible construct is
  suite-context-dependent and is deliberately **not** claimed here. The seam bounds the cost; it
  does not explain it, and the underlying asymmetry is worth its own look.

  The override is guarded **fail-safe, not fail-closed**: a zero, negative, non-numeric or
  leading-zero value falls back to 50 rather than erroring, because the interval is the only
  thing bounding that loop's rate and a typo in a test seam must not turn a provisioning run
  into a busy-loop hammering `sudo`. Four new gates pin it — the honoured case first (a guard
  that rejected everything would pass every fallback case and still have broken the seam), then
  eight bad values, then the unset default. They assert on the argument the sleeper is actually
  handed rather than on the source, since a regex that merely looks right is exactly how a
  validator passes review and admits `0` anyway. The suite also pins the shipped default by
  name, because its sleeper shim keys on it.
- **An `atuin` scope axis, so the premise detector's self-test stops riding on every push.**
  `scripts/ci-classify.sh` now emits a third `atuin=<true|false>` line alongside `shell`/`nvim`,
  and `--scope atuin` gates the two hermetic sections that drive `scripts/verify-atuin-guard.sh`.
  Those sections were **197s of a 286s suite — 68% of it**, and the largest single cost on the
  fan-out's critical path, while testing the DETECTOR against stub binaries rather than testing
  Core: the script is dev tooling, absent from `core.manifest` and vendored nowhere, and its real
  job — measuring live upstream atuin — runs weekly in `atuin-guard-verify.yml`, never on a push.
  A one-line edit to `zsh/10-ui.zsh` was paying all 197s for a harness it cannot reach.

  Coverage is preserved rather than traded away, in three ways. The axis is reachable from
  everything that can actually move it: `scripts/` (already infra → full run), `zsh/00-tools.zsh`
  (which carries `_core_atuin_daemon_guard`, the guard the detector protects) and `atuin/`.
  The Alpine and Arch legs receive the same classifier verdict through the environment — never
  interpolated into a `run:` body, per #422 — so musl/busybox and rolling-glibc coverage of the
  self-test is dropped only from pushes that could never move it. And `atuin-guard-verify.yml`
  gains a `selftest` job that runs the whole thing **unconditionally, every week**, on the same
  schedule as the measurement that trusts it: the measure jobs rely on the detector to tell a
  real upstream move from a broken apparatus, so a regressed `unmeasurable` verdict would file a
  confident issue claiming the premise MOVED when nothing had. It is wired into `notify-failure`
  for that reason, and deliberately needs nothing and is needed by nothing — a red self-test must
  sit beside the live measurement saying which to believe, not suppress it.

  Skipping stays **fail-closed at the classifier**, as before: an unrecognised path, an empty
  scope or an unparseable classifier line all force the full run. `_core_read_classify` validates
  `atuin=` exactly as strictly as the other two axes, so a classifier this reader cannot parse can
  never be read as "skip the most expensive gate".

- **`dotfiles-Debian` joins the fleet as the ninth Core-vendoring repo.** It was planned
  once, cancelled, and left a "no longer being pursued" note in `scripts/os-repos.txt`
  on the grounds that `dotfiles-Kali` covered the Debian family. That reasoning does not
  survive contact with a plain Ubuntu box: Kali is a rolling sid derivative carrying a
  67-package offensive role layer. The note is removed and the repo registered — in
  `scripts/os-repos.txt` **and** in the hardcoded fallback arrays in `sync-core.sh`,
  `fleet-drift.sh` and `core-integrity.sh`, which are what actually run when the data
  file is unreadable and would otherwise have silently omitted it.
- **`claude-routines-call.yml` accepts `distro: debian`.** That allowlist is enforced at
  runtime (`::error::unsupported distro`), not merely documented, so the new repo's
  routine caller would have red-failed without this. `/os-package-availability` gains
  the matching guidance, including the rule that on a frozen LTS "does the name resolve"
  and "is it a version Core can use" are different questions.
- **`PORTING-MATRIX.md` gains a Debian/Ubuntu column** in both tables, a quirks
  paragraph, a clipboard row, and footnotes ²⁸ (pinned upstream release asset) and ²⁹
  (deliberately not installed). **The column-order contract changed**: the last cell on
  a package row is now Debian/Ubuntu, not Kali — `/os-package-availability` asserted the
  old order and has been updated with it.

## [v4.12.2] - 2026-08-17

### Added

- **CI now fails a `fix(…)` PR that closes no issue and gives no reason.** #446 fixed two
  reported bugs — #420 (starship) and #423 (carapace) — and merged green with no closing
  keyword in its body. GitHub therefore linked nothing, both issues stayed **open**, and
  days later a reader re-derived a 2021 upstream function rename and re-ran the reproducer
  to re-confirm a bug that had already shipped in v4.12.0. The code was correct the whole
  time; the _link_ was missing, and no check objected.

  `.github/workflows/pr-link-check.yml` now asks GitHub for the PR's
  `closingIssuesReferences` — the same field GitHub itself uses to auto-close on merge, so
  cosmetic text like "Refs #420" cannot satisfy it — and requires a `fix(…)` PR to close at
  least one issue. The escape hatch is a `No-Issue: <reason>` line in the body, because a
  genuine fix is often found and fixed in one pass with nothing filed; the reason is what a
  future reader finds in place of a link. `pull_request_template.md` documents both routes.

  Gated set is `fix` only, matched with the delimiter-aware Conventional-Commit regex from
  `scripts/gen-release-notes.sh`, so `fixup:` and ordinary prose that merely starts with
  the word are untouched. That is deliberately the stricter of the repo's two parsers —
  `cliff.toml` groups on a bare `^fix`, which would also sweep in `fixup:` — because a
  false `not-gated` only declines to ask for a link, while a false gate would demand one
  from a PR that is not a fix and teach authors to route around the check. The verdict
  logic lives in
  `scripts/ci-pr-link.sh` rather than inline YAML — shellcheck'd and unit-tested in
  `scripts/test-core.sh`, following the `scripts/ci-classify.sh` precedent — and it is its
  own workflow rather than a job in `ci.yml` so that a body edit re-runs one GraphQL query
  instead of the whole nine-repo audit matrix.

### Fixed

- **The pipefail SIGPIPE scanner was half-blind, and was hiding a live hazard in the
  PR-link gate.** `_core_pipefail_hits` required grep's `q` to be the **last letter** of
  the flag cluster, so `grep -q` and `grep -xq` were caught while `grep -qx` and
  `grep -Eqi` walked straight past — the identical hazard, differing only in spelling.

  Widening the pattern to allow the `q` anywhere flags exactly **one** line that was
  already in the tree: `ci-pr-link.sh`'s `No-Issue:` probe, `printf … | grep -Eqi` under
  `set -o pipefail`. `grep` exits on its first match, `printf` takes `EPIPE`, and the
  pipeline reports 141 — so a PR body larger than the pipe buffer would make a **valid**
  `No-Issue:` line evaluate false and fail a correctly-exempt PR. That is the escape hatch
  failing into a false accusation: the same shape as the probe bug above, one layer down.
  It survived because a PR body fits the buffer, which is precisely the "happens to work"
  the scanner exists to eliminate.

  Both land together — widening the regex without fixing the line it newly catches would
  turn the audit red. Four assertions now pin every spelling (`-q`, `-xq`, `-qx`, `-Eqi`)
  plus a grep with no quiet flag at all, so the gate cannot go half-blind again.

- **`pr-link-check` no longer tells a correctly-linked PR that it has no linked issue.**
  The probe coerced any non-numeric count to zero, so **"I could not reach the API"** and
  **"this PR has no link"** produced the same verdict and the same message. During a run of
  GitHub 503s it failed #499 — which links #498 — with "this `fix(…)` PR closes no issue
  and gives no reason", and offered `No-Issue:` as the remedy. The link was intact
  throughout; re-running the identical job minutes later returned `linked=1`.

  Fail-closed was the right call and is unchanged — a broken probe must never silently pass
  an unlinked fix PR. What was wrong is that the check asserted something it did not know.
  An undeterminable count now gets its own `probe-failed` verdict which says plainly that
  the API was unreachable and the job should be re-run, so the exit code carries the
  **policy** while the verdict carries the **claim**.

  The workflow also retries the probe four times with quadratic backoff (0s/2s/6s/12s),
  requiring a numeric result rather than merely exit 0 — `gh` can return success with an
  empty body on a partial GraphQL response, which the old code would have read as a
  confident zero. And the `No-Issue:` escape hatch is now evaluated **before** the
  probe-failure verdict: it is read from the PR body and needs no API call, so a PR that
  already carries its reason is no longer blocked by an outage it does not depend on.
- **`make audit` could report a fully green run while never reading the file the change
  was about.** The audit's content gates — `bash -n`, `zsh -n`, shellcheck, the pipefail
  scanner, and the toml/yaml/json parsers — enumerated their targets with a bare
  `git ls-files`, which lists **only tracked files**. A brand-new script or config was
  therefore invisible until the moment it was `git add`ed, and each gate still printed its
  "all clean" pass. A green audit that had not opened the file is strictly worse than a red
  one: it is indistinguishable from a real pass.

  This shipped. `scripts/ci-pr-link.sh` passed a local **261 pass / 0 fail** audit while
  still untracked, then failed all four CI legs (ubuntu, macOS, Alpine, Arch) on two SC2016
  violations that had been in the file the whole time.

  The audit was already inconsistent with itself about this: its `--changed` scope
  derivation counts untracked files when deciding which _areas_ run, and the walk-based
  gates (`luacheck .`, markdownlint's `**/*.md` glob) have always seen them. Only the
  `git ls-files` gates disagreed, and nothing surfaced the disagreement.

  All twelve content gates now enumerate through a shared `_audit_ls` helper
  (`scripts/lib/common.sh`) that unions tracked with untracked-but-not-ignored, honouring
  `.gitignore` so scratch files stay out. That covers every gate script `make audit`
  consults, not just `audit-core.sh`: `check-modern.sh`'s workflow inventory and
  `nvim-reachability.sh`'s lua-module inventory had the same blind spot, so an untracked
  workflow could evade the modernization floor and an untracked module the orphan
  backstop. `audit-core.sh`'s own §5c boundary scan was affected too, in a form worth
  naming — it expands `nvim/` from the manifest and then reads every file it names, so it
  reads like a manifest question while actually being a content one. The rule is documented where the next gate author
  will read it: a gate asking **"is this file's content valid?"** uses `_audit_ls`, while a
  gate asking **"what does git record?"** (manifest drift, index exec-bits) keeps plain
  `git ls-files`, because an untracked file has no git state to check. The helper lives in
  the shared lib rather than in `audit-core.sh` so `scripts/test-core.sh` exercises the real
  implementation instead of a copy that could drift; five new assertions pin the behaviour,
  including that a gitignored script stays excluded and that the enumeration split stays
  exact, per file — twelve content gates through the helper, three git-state gates
  direct. That last one is deliberately a tripwire rather than a floor: an "at least N
  helper calls" check would sit green while a _newly added_ gate reintroduced the bug with
  a bare `git ls-files`, so adding either kind of enumeration now fails the suite until
  someone decides which side of the rule it belongs on.

  **Exec-bits deliberately unchanged.** That gate reads index modes (`git ls-files -s`), and
  an untracked file has no index entry — it falls on the git-state side of the rule above.

- **A failed `tpm` clone announced itself as a status line, so tmux quietly ended up with
  no plugin manager.** `blib_link_core`'s one-time clone reported failure with `blib_say` —
  the blue `::` on **stdout**, the identical shape to the `cloning tpm` progress line
  immediately above it — and discarded git's error with `>/dev/null 2>&1`. Behind a proxy,
  offline, or against a rate limit, the run therefore produced a box whose tmux had no
  theme and no resurrect/continuum, with nothing in the log that stood out and no way to
  find out why.

  It now uses `blib_note_fail`, which warns on **stderr** and records the step, and git's
  own output is captured and printed indented under the failure instead of dropped — on a
  clone failure that output _is_ the diagnosis (DNS, proxy, TLS, rate limit).

  **Scope — this is the first lib-internal caller of `blib_note_fail`.** The v4.11.0 entry
  below scoped that API as "new, not yet wired into any bootstrap", meaning adoption by
  _consumers_. A clone that happens inside Core is the case a consumer cannot observe for
  itself: `dotfiles-MacBook` had to add a post-hoc "is the tpm directory there?" check to
  its own `bootstrap.sh` precisely because this failure was unreportable
  ([dotfiles-MacBook#133](https://github.com/dotgibson/dotfiles-MacBook/issues/133)). No
  consumer changes behaviour from this alone — `blib_note_fail` calls `blib_warn`
  internally, so a bootstrap that ignores `BLIB_FAILED` sees exactly the corrected warning
  and nothing else. A bootstrap that _does_ fold the tally in now learns about a failure it
  previously could not see, and can drop its local directory probe.

  Same shape, same fix, one line away: `blib_set_login_shell`'s "chsh not found" branch
  also used `blib_say` while its sibling failure branch used `blib_warn`, though the
  outcome — login shell unchanged — is identical. It is a warning now too.

  Covered by four assertions in `scripts/test-core.sh`'s link-run section, hermetic and
  offline: `GIT_ALLOW_PROTOCOL=file` makes git refuse the https transport, so the clone
  fails deterministically without depending on the remote being reachable or unreachable.
  They pin the stream (stderr, not stdout), the tally, and the git-error passthrough.

- **One repo's failed push aborted the entire fan-out, so a release reached none of the
  fleet.** The per-repo loop in `sync-fanout.yml` treats every error as per-repo — record
  it, set `fail=1`, move to the next repo — except the three calls that talk to the remote:
  `git push` and the `gh pr list` / `gh pr create` after it, all unguarded under
  `set -euo pipefail` (a failing command substitution exits too). The first failure
  therefore exited the step outright, skipping the remaining repos entirely.

  It fired on the v4.12.1 cut. `dotfiles-MacBook` is first in `scripts/os-repos.txt`, and
  its push was refused with _"refusing to allow a GitHub App to create or update workflow
  `.github/workflows/auto-tag.yml` without `workflows` permission"_ — the fleet App has no
  `workflows` grant, and since [#482](https://github.com/dotgibson/dotfiles-core/issues/482)
  the fan-out rewrites `.github/workflows/*` SHA pins in repos that pin a Core caller. That
  one repo took the other seven with it: five had synced cleanly and were ready to open a
  PR, and none did. The release existed on `main` and in no OS repo at all.

  All three are now guarded like every other per-repo step, so a bad repo costs one PR
  instead of the fleet. The `workflows`-permission rejection is recognised by name and
  reported with the grant to make, since GitHub's message is opaque unless you already know
  the fan-out edits workflow files.

  `GITHUB-APP-AUTH.md` prescribed the failure it now has to fix: it listed Contents and
  Pull requests and said "Everything else: **No access**", so an operator following the
  setup guide built an App that cannot push the workflow-pin changes #482 added. It now
  requires **Workflows: Read and write**, says why only some repos trigger it while every
  installation still needs the grant (the permission is a property of the App; the SHA pin
  belongs to each caller workflow, and only those repos put one in a sync branch),
  and warns that editing an existing App's permissions mints the OLD set until the
  installation owner accepts the review request.

  The same staleness ran through the release docs: `RELEASE-RUNBOOK.md` and
  `RELEASE-STRATEGY.md` both named `dotfiles-Windows` as the **sole** SHA-pinning caller
  (the runbook froze it as "27 of 28"), when `dotfiles-MacBook` pins four callers and
  `dotfiles-Defense` one. Both now split the cases by the property that actually matters at
  release time — pinned **inside** the fan-out (MacBook, Defense: `sync-core.sh` moves the
  pin automatically since #482, which is _why_ the App needs Workflows write) versus pinned
  **outside** it (Windows: vendors no `core/`, so nothing moves its pin and it needs a hand
  bump). The frozen count is replaced by a one-liner that derives it from the callers, since
  a hand-maintained tally is what rotted here.

  Guarding the `gh` calls matters as much as the push, and fails in a nastier shape: a rate
  limit or a per-repo API error there strands every _later_ repo even though this one's
  branch is already on the remote — work done and merely unannounced. Those cases now say
  so explicitly rather than surfacing as an opaque step abort, and they report the PR state
  as **unknown**: the lookup itself is what failed, so an open PR may simply be hidden by
  the same outage, and "no PR exists" would invite a duplicate. The summary asks the
  operator to check the branch and open one only if none is there.

  **Deliberately not "retry without the workflow changes".** `core.lock` and the pins name
  the same Core; landing the lock while silently keeping stale pins is exactly the
  vendors-one-Core-runs-another split #482 closed, and it is invisible to `core-integrity`
  and `verify-core` — which is what let it survive the first time. Failing that repo loudly
  is the correct degradation; re-creating the split is not.

## [v4.12.1] - 2026-08-16

### Fixed

- **`blib_link` deleted a displaced symlink with no record, while backing up a regular
  file** ([#430](https://github.com/dotgibson/dotfiles-core/issues/430)). A real file at
  the destination was moved to `<dst>.pre-dotfiles.<epoch>` and counted; a symlink was
  `rm -f`'d — whatever it pointed at — with no backup, no counter, and nothing in the run
  summary. The early return above that branch only skips an **already-correct** link, so
  the delete was reached precisely when the link pointed somewhere else, which is the one
  case worth recording.

  Not the rare path, the common one: the repos being wired are symlink farms, so `$dst` is
  far more often a symlink than a regular file. `dotfiles-Kali` and `dotfiles-Defense` are
  designed to coexist as red/blue twins, and whichever bootstrapped second silently
  discarded the other's links; a user migrating off a hand-rolled tree lost every record of
  where their fragments used to point. `bootstrap.sh` is advertised as idempotent and safe
  to re-run, and backup-on-clobber is what made that credible — the guarantee quietly did
  not hold for the thing it actually encounters most.

  A displaced link is now **printed with its old target** (`relinking <dst> (was -> …)`)
  and counted in a new `BLIB_RELINKED` tally, and the dry-run says what it is about to
  displace (`would relink: <dst> (currently -> …)`) instead of a bare "would relink", which
  read as _repoint_ rather than _discard unrecorded_. Deliberately logged rather than moved
  aside: backing a symlink up would leave one stray link per fragment per run in
  `~/.config` — a role switch relinks nearly everything — and the counter is deliberately
  **separate from `BLIB_BACKED`** rather than folded into it, because "backed up" promises a
  restorable `.pre-dotfiles.*` file on disk and the OS repos' unlink/restore paths read
  exactly those. `blib_wire_summary` therefore gains a field:
  `N linked · M seeded · K backed up · R relinked · S skipped`. An already-correct link is
  still a silent no-op, so a plain re-run prints no relink noise.

- **The fan-out moved the tree and the lock, and left the pins pointing at the previous
  Core** ([#482](https://github.com/dotgibson/dotfiles-core/issues/482)). An OS repo names
  the vendored Core in three places — the `core/` subtree, `core.lock`'s `core_sha`, and,
  in any repo that SHA-pins its reusable callers, the workflow `uses:` pins.
  `sync-core.sh` wrote the first two and had no concept of the third, so a fan-out produced
  a repo that **vendored one Core and ran another**.

  Not cosmetic: `auto-tag-call` holds `contents: write` and pushes tags, `notify-web-call`
  is handed two secrets. And the drift was silent by construction — `core-integrity`
  compares a tree object and `verify-core` a byte-for-byte split, so both stay green while
  a workflow points somewhere else entirely. It reached production on the v4.12.0 fan-out
  and surfaced only because `dotfiles-MacBook` had just built its own pin gate; every other
  repo takes the mutable `@v4` alias, which the release force-advances, so nothing else
  showed a symptom.

  The pins now move in the **same commit** that stamps `core.lock` (landing them apart
  would leave a window where the repo's own gate is red on `main`). Two boundaries, both
  tested: only an existing 40-hex pin moves — a caller on `@v4` is left alone, because
  taking the alias is a deliberate per-repo policy and silently converting it to a SHA pin
  would change that repo's update model behind its back — and the trailing `# vX.Y.Z` moves
  with the SHA, since Renovate reads it and a pin check compares it against `core_tag`
  independently, so rewriting one without the other only trades one red gate for another.
  A third-party action pinned in the identical `@<sha> # <version>` shape is matched on the
  `dotgibson/dotfiles-core/` prefix and skipped.

  The idempotency check widened from `core.lock` to the whole staged set. Scoped to
  `core.lock` it reported "current" and dropped the pin fix on exactly the repos a
  pre-fix fan-out had already left stale.

## [v4.12.0] - 2026-08-16

### Added

- **`audit-core.sh` §5d — a gate for the `pipefail` + SIGPIPE trap this repo keeps hitting.**
  Under `set -o pipefail`, piping into a reader that exits early turns a success into a
  failure: `grep -q` stops on its first match, `awk` on its `exit`, `head` after N lines, the
  writer takes EPIPE and dies with 141, and pipefail reports the pipeline as failed even
  though the reader matched.

  Three occurrences so far. Two were found and fixed by hand — a 4000-line `git show` into
  `grep -q` reporting "no heading" on a file that had one, and `ldd --version | grep -qi
  musl` reading false on every musl box, whose assertion is still named "the pipefail trap
  this repo has hit before". The third broke `main`: `nvim-reachability.sh` invented two
  orphans because a visited module's lookup returned 141. Each fix included a sweep of the
  tree, correct at the time and unable to cover code written afterwards.

  The gate is scoped to a **shell-string** producer (`printf`/`echo`) feeding an
  early-exiting reader, in files that actually `set -o pipefail`. That shape converts to a
  herestring with no behavioural difference and no reason to prefer the pipe, so a finding
  is never a judgement call. `sed <file> | head -n1` — a file producer, ~15 instances — is
  deliberately out of scope: converting those is not free, and a gate that fires fifteen
  times on working code is a gate someone turns off.

  Four existing instances converted (`check-modern.sh`, `parity-check.sh`, `test-core.sh`
  ×2). All fed small values and none was a live bug — which is precisely why a hand sweep
  leaves them, and why the next author copies the shape somewhere the producer is large.

  The scanner lives in `scripts/lib/common.sh` as `_core_pipefail_hits`, beside
  `_core_fail_digest` and for the same reason: so `test-core.sh` can drive it on fixtures.
  A gate for a bug that has recurred three times is only worth having if it demonstrably
  fires, and probe-testing caught a defect in this one before it shipped — it used to scan
  any file that merely _mentioned_ pipefail in a comment, which is the false-positive class
  that gets a gate switched off. Eight assertions pin both halves: the three banned reader
  forms are caught, and the herestring fix, a comment describing the hazard, a file with no
  `pipefail`, a file producer, and the library's own definition are all left alone.

- **`audit-core.sh` §4b — the nvim orphan backstop `core.manifest` claimed already existed.**
  `core.manifest` lists `nvim/` as a directory rather than per-file, because a vendored
  lazy.nvim tree churns wholesale and per-file listing would be noise. The stated
  justification was that "verify-core.sh (byte-for-byte vs upstream) is the orphan backstop
  here instead" — but **`verify-core.sh` has never existed in this repo**. So from the day
  `nvim/` went directory-granular, §1's manifest⇄fs check auto-listed every new path under it
  and nothing else looked: a lua module nothing loads could sit in the tree indefinitely and
  fan out to all eight OS repos, silently. luacheck does not help — it lints the files it is
  handed and does no reachability analysis.

  §4b walks the load graph instead — a real traversal, not an "is this name mentioned
  anywhere" scan. That distinction is the whole point: a mention-scan passes two dead modules
  that require _each other_ (a disconnected cycle, non-zero indegree, reachable from nothing),
  and passes a module named only in another file's comment. Both are exactly the orphan this
  exists to catch. So it inventories every module, strips lua comments, reads each file's
  edges, then walks outward from the roots and flags every module never visited.

  Only real load expressions count as edges — the module name must be preceded by
  `require` (covering `require("x")`, `require "x"`, and `pcall(require, "x")`) or by
  lazy's `import =`. Matching every quoted `gerrrt.*` string would still be a mention scan:
  `health.lua` deliberately peeks `package.loaded["gerrrt.servers"]` precisely so it does
  _not_ load the registry, and counting that as an edge would let the whole `servers/` arm
  look reachable from the health root even with every real `require("gerrrt.servers")`
  deleted. Comment stripping handles `--[[ … ]]` blocks across lines too, since a
  line-only stripper leaves the block interior searchable.

  Two roots, both genuine entry points rather than exemptions: `nvim/init.lua`, and
  `gerrrt.health` — which Neovim discovers by runtimepath for `:checkhealth`, so nothing
  requires it and nothing should. Two edges cannot be read literally from source and are
  resolved during the walk: a **directory import** (`gerrrt.plugins` names a directory, so a
  target with no file expands to its `target.*` children, as lazy does), and
  the **dynamic require** in `servers/init.lua`, which does
  `pcall(require, "gerrrt.servers." .. name)` over its `servers` list — so visiting
  `gerrrt.servers` expands to the listed names, that registry being the only static evidence
  those modules are wanted.

  The edge KIND is carried through the walk, because the two resolve differently at a
  missing target: `import` expands to children, but a `require` with no module behind it is
  a dangling require lua raises at runtime, and is reported. Treating every fileless target
  as a directory import meant `require("gerrrt.utils")` silently marked every
  `gerrrt.utils.*` child reachable.

  The inventory itself is validated, since the walk is only as sound as its name→file map:
  `.init` is stripped for a real `*/init.lua` path only (doing it on the module string let a
  file named `foo.init.lua` masquerade as module `foo`), a dot inside a filename is reported
  as unaddressable (lua resolves `gerrrt.a.b` through `a/b.lua`, never `a.b.lua`), and two
  files claiming one module id fail — lua loads exactly one of them, so the other is dead
  config that would otherwise ride on its twin's reachability.

  The registry is also checked **both** ways, because a generic "unreachable" is a worse
  message than the truth: a module in no list entry is dead config; a list entry with no module
  file is a runtime load error `servers/init.lua` reports at startup. A missing **or**
  unparseable registry fails closed — silently skipping it would disable the entire `servers/`
  arm, which is how this class of gap starts in the first place.

  Verified against planted fixtures for every class it claims to catch — orphaned `utils/`
  module, stray top-level module, disconnected require cycle, comment-only mention, multiline
  block comment, `package.loaded` peek, `require()` of a directory, lazy import matching
  nothing, duplicate module id, unaddressable dotted filename, unlisted LSP module, registry
  entry with no file, unparseable registry, missing registry — plus the
  two exemptions (a false positive on `health.lua` or `plugins/` would make the gate
  unusable). Each negative fixture asserts the finding text **and** exit status 1, so the
  documented CLI contract is covered too. The real tree is clean: all **97 lua modules under
  `nvim/lua/gerrrt/`** are reachable today. That module set is the gate's scope — `nvim/init.lua`
  is the entry point it walks _from_ rather than a vertex, and `lazy-lock.json` and
  `.luacheckrc` are not lua modules at all. bash 3.2 safe, so the macos-latest CI leg runs it. Closes the
  `nvim/` half of #454.
- **`lib/bootstrap-lib.sh` gains the privilege-escalation API a bootstrap needs in order to
  stop hard-coding `sudo` — available for adoption; no caller yet.**
  `blib_resolve_su [--require]` resolves the escalator **once** into `BLIB_SU`
  (an explicitly set value always wins, _including_ an empty one; else root needs nothing,
  else `sudo`, else `doas`), and `blib_priv` is the public way to run a privileged command.
  Every OS bootstrap wrote `sudo` inline at roughly a dozen call sites, which is wrong on
  precisely the machines a bootstrap meets first: `fedora:latest` and `alpine:3.20` ship
  **no sudo**, and neither does a WSL distro's first boot (root, before `/etc/wsl.conf`
  installs the default user) or a minimal Server image. Those runs died at the _first_
  package-manager line with `sudo: command not found` — exit 127 under `set -e`, before
  doing anything at all. It is also why `bootstrap-test.yml` can exercise only
  `--links-only`, and must pass `BLIB_SU=` to manage even that. `--require` makes "not root
  and no escalator" a hard error for a provisioning run, while a links-only run correctly
  continues (wiring symlinks needs no privileges).

- **`blib_sudo_keepalive_start` / `blib_sudo_keepalive_stop` — the API for keeping a sudo
  timestamp warm, which greatly reduces the chance that an adopting bootstrap stalls on an
  invisible password prompt.** A mitigation, not a guarantee: the background refresh
  deliberately swallows its own failures rather than killing the run, and a sudoers with no
  reusable timestamp (`timestamp_timeout=0`) cannot be kept warm at all. A bootstrap's privileged calls are interleaved with from-source `cargo`/`go`
  builds that take minutes, comfortably outliving sudo's 5-minute timestamp. sudo writes
  its prompt to **stderr** and reads from the TTY, so a later call whose stderr is
  redirected (`>/dev/null 2>&1`, ubiquitous in these scripts) stopped dead at a prompt
  nobody could see: no output, no progress, indistinguishable from a hang, and reproducible
  only on a box slow enough to cross the timeout. Prime once up front, refresh in the
  background, and return non-zero if that first authentication fails so the caller can
  abort before half-provisioning. A no-op under `doas` (no refreshable timestamp) and as
  root.

- **`blib_user_bindirs_on_path` — the helper an adopting bootstrap calls to stop its
  presence guards lying.** A bootstrap's
  `command -v <tool>` guards decide whether to spend _minutes_ building from source, but
  they are answered by the PATH of whatever shell launched the bootstrap — on a fresh box,
  bash. `cargo install` writes `~/.cargo/bin` and `go install` writes `$GOBIN`
  (`~/.local/bin` by convention here), while `~/.cargo/bin` reaches PATH only via the OS
  zsh layer — i.e. only inside a Core shell that does not exist yet. So every guard
  reported "missing" and every re-run rebuilt the entire from-source tool set. Adds only
  directories that exist, and never twice.

- **`blib_note_fail` / `blib_failed_count` / `blib_failures_report` — the tally an adopting
  bootstrap uses so a half-provisioned box says so.** A bootstrap is full of steps that must not abort the run (a COPR that
  is down, a rate-limited API, a crate that fails to build), so each is written `|| true` —
  and the script then printed "bootstrap complete" and exited 0 regardless, making a box
  that got none of its extra tooling indistinguishable from a good one, to CI and operator
  alike. `blib_failures_report` returns non-zero when anything was recorded, which is the
  contract a caller maps onto its own `--strict` flag.

  **Scope:** these are new APIs, not yet wired into any bootstrap. Nothing in the fleet
  changes behaviour from this release alone — each OS repo adopts them after the next
  sync, starting with `dotfiles-Fedora` (whose `bootstrap.sh` currently carries
  equivalent logic inline) as the reference implementation, then per `PORTING-MATRIX.md`.

  All four are covered by a new hermetic section in `scripts/test-core.sh` (no package
  manager, no network, no privileges), including the bash 3.2 `set -u` empty-array rule
  that would otherwise crash the report on the _happy_ path.

- **`PORTABILITY.md` — how to write Core that survives the fan-out.** The rules were
  real and consistently followed, but recorded only in ~8 scattered code comments, so
  they were unteachable to a new contributor and unenforced for new files. That is the
  likely root cause of the Homebrew paths that sat in `maint/` and `tmux/scripts/`.
  It documents the bash 3.2 floor (with the banned constructs and their portable forms),
  the BSD/busybox coreutils traps, the shim pattern with the full inventory of shipped
  shims, what to do when a capability genuinely cannot be probed, and why the `have()`
  probe is redefined per loading context on purpose.

- **`VENDORING.md` — the same contract from an OS repo's side.** Previously scattered
  across `ARCHITECTURE.md`, `RELEASE-RUNBOOK.md` and a source comment, so a downstream
  maintainer had no single answer to: which `core/` paths may I touch, what does
  `core.lock` mean, which number band may I claim, how do I upstream a fix. Includes the
  footgun that was documented only in `zsh/loader.zsh` — a fragment dropped in a **gap in
  the Core band** (say `22-foo.zsh`) is gated as Core and silently vanishes under
  `CORE_PROFILE=minimal`.

- **`CODE_OF_CONDUCT.md`** — the one standard community-health file that was missing
  while the README actively solicits contributions.

- **Core now performs a real bootstrap link run in its own suite.** `bootstrap-test.yml`
  asserts the symlink graph, but it is `workflow_call`-only and dotfiles-core ships no
  `bootstrap.sh` — so it only ever runs from the eight OS repos. Core unit-tested the
  `blib_*` helpers and never linked anything, which meant a `bootstrap-lib.sh` regression
  was caught **downstream, in eight repos**, instead of here.

  Seven assertions now link the actual Core tree into a sandbox `$HOME`/`$XDG_CONFIG_HOME`
  and check the graph a consumer depends on: every numbered fragment lands flat in
  `$ZSH_CFG` (the load-order contract `loader.zsh` globs), `loader.zsh` itself is linked,
  `nvim/` resolves as a directory symlink, tmux/starship/lazygit/jj/gitconfig/vimrc land
  at their promised destinations, `clip` and `clip-paste` are executable on
  `~/.local/bin`, the **seeded** files (`local.gitconfig`, `sesh.toml`) are real copies
  rather than symlinks — a symlink there would track a user's git identity back into
  Core — and a second pass is a no-op that backs nothing up. Hermetic: the `tpm`
  directory is pre-seeded so the one network call in the function is skipped.

- **`scripts/sync-core.sh` has tests.** The highest-blast-radius script in the repo —
  it gates on the audit, `git subtree pull`s into eight working trees, and stamps
  `core.lock` — had **no coverage at all**. Its only proof was `sync-fanout.yml` running
  it for real against the live fleet, i.e. the fleet was the test.

  Twelve assertions on hermetic fixtures (a miniature of the real topology: a vendored
  origin, a local checkout, and a throwaway fleet, with `audit-core.sh` stubbed so the
  gate can be driven red and green in-process). Every case is a **refusal or an
  idempotency property**, because that is how this script fails: a broken guard does not
  throw, it fans a bad tree out to eight repos and reports success.

  Covered: a red audit refuses the fan-out **and** refuses before mutating anything;
  local `HEAD` ≠ remote tip refuses (what you audited is not what would vendor); an
  uncloned repo and a `core/`-less repo are _skipped_, not failed; `dotfiles-Windows`
  appears in neither the fleet file nor the fallback array; `--dry-run` prints the plan
  and commits nothing; `core.lock` lands at the repo **root** with the full sha, version
  and branch; the tree is clean afterwards so the next run is not self-blocked;
  re-syncing an unchanged sha manufactures no commit; and a dirty target is refused,
  counted failed, and does **not** abandon the repos after it.

### Changed

- **A release tag can no longer exist before its commit is on `main`.** `make tag` used
  to commit _and_ tag in one step, leaving a local `vX.Y.Z` on a commit that was not yet
  merged. That window is not closable by discipline: `--no-follow-tags` governs _your_
  push, while the tag lives in shared `.git` state any other process can push.

  It happened. During the v4.11.0 cut a concurrent session pushed its own branch with
  `push.followTags` set, carried the release tag to origin, and fired `release.yml` and
  `sync-fanout.yml` against an unmerged commit — publishing a Release and opening eight
  vendor PRs across the fleet against a commit that was never on `main`. Nothing merged,
  because `sync-fanout` opens PRs and never merges them, but the number had to be retired:
  release tags are immutable by ruleset, so `v4.11.0` could not be re-pointed.

  The invariant is structural now, not procedural — **a `vX.Y.Z` tag only ever exists on a
  commit already on `origin/main`**. `make tag` commits and creates no tag at all, so a
  stray push has nothing to carry. `make publish` runs after the PR merges and refuses
  unless `origin/main` actually carries this `core.version`, then tags `origin/main` and
  pushes. `--push` is withdrawn — its whole semantic was the hazard — and fails with a
  pointer to `--publish`.

  Phase 2 tags the **release commit**, not `origin/main`'s tip. `core.version` does not
  change again until the next release, so "the tip carries this version" stays true for
  every commit that lands afterwards — tagging the tip would sweep work still under
  `[Unreleased]` into the release, and `release.yml` builds the Release body from the
  `[vX.Y.Z]` section, so that work would ship undescribed. It resolves the commit that
  _set_ `core.version` to this value and tags that, reporting when the tip has moved on.

  It also validates that commit's `[vX.Y.Z]` section before creating any tag — that it
  **exists and is non-empty**, using `release.yml`'s own `awk` so the two cannot disagree
  about what empty means. `release.yml` builds the Release body from that section and
  rejects an empty one, and `release.sh` will promote an empty `[Unreleased]` without
  complaint; publishing first and discovering either afterwards leaves an immutable tag on
  a release that cannot be published, burning the version for a reason knowable up front.

  `make release`'s printed recipe is updated to match. It still ended with
  `git tag -a` + `git push --tags`, so an operator following the output it generates would
  have recreated exactly the pre-merge tag this change exists to eliminate.

  Both refs go up in a single `--atomic` push, with a `--force-with-lease` on the `vN`
  alias. Pushed separately they can half-land: `vX.Y.Z` published while `vN` is stale fires
  the workflows against a stale alias, and a re-run then refuses because the immutable tag
  already exists. The lease rejects the push if another publisher moved `vN` after this run read it, and an
  **ancestry check** covers the gap before that read: whatever `vN` points at must be an
  ancestor of the commit being tagged, so the alias can only ever move forward. Both are
  needed — a publisher finishing _before_ the read is seen as this run's own expected
  value, so the lease alone would be satisfied while `vN` rolled backward.

  This also makes the merge method irrelevant to the tag. Eleven behavioural assertions
  cover it — including that the tag does **not** follow a tip that advanced after the
  release merged; the script previously had none, which is how the ordering survived.

- **The audit now names the behavioural assertion that failed, in the failure line itself.**
  It said `behavioral tests failed — run: ./scripts/test-core.sh`, which sends the operator
  away to reproduce a result the run already had. For an _intermittent_ failure that is advice
  that cannot be taken: the re-run passes and the evidence is gone. That is not hypothetical —
  it cost two occurrences of an unattributed flake, both lost because the `✗` scrolled past far
  above the summary and only the summary survived being piped through `tail`.

  The suite's output is already buffered for the background run, so the names cost one `grep`
  and travel wherever the fail line travels: the summary block, `--json`, the CI job log, a
  truncated paste in an issue. Not a CI _annotation_ — `fail()` writes to stderr and `ci.yml`
  runs `audit-core.sh` directly with nothing emitting `::error::`, and claiming a destination
  this does not reach would be the same overclaim the digest exists to prevent. The names are
  joined without rewriting the records, so a message containing a literal `|` (nine assertions
  do, `'exec … || exec …' cannot fall back` among them) is not spaced out into false
  boundaries — two failures reading as four is worse than terse in the one line someone has
  when they cannot reproduce the failure. Up to three are named, then a count (`+N more`)
  rather than a
  silent truncation, because "one flaky assertion" and "the whole section is down" need telling
  apart before deciding to re-run or investigate. A run that exits non-zero having printed no
  `✗` at all — a crash, a kill, a timeout — now says _that_, instead of an empty list beside a
  red line.

  Matched after stripping SGR escapes rather than anchoring on a bare `✗`: `fail()` prefixes
  the mark with `$c_red`, so an anchored match finds nothing whenever colour is on — a detector
  that would go quiet in exactly the runs someone is watching. The serial path
  (`CORE_AUDIT_SERIAL=1`) keeps the old line; its output is not captured, and piping it to
  capture would cost the live colour output that mode exists to give.

  The rendering lives in `scripts/lib/common.sh` as `_core_fail_digest` **so the suite can
  test it**, which matters more here than usual: every branch of it fails _quietly_, producing
  a plausible line that has silently lost the name — indistinguishable from the flake merely
  not being nameable. Proving those by making a real gate fail would mean recursively invoking
  the audit or hand-injecting a fault, and CI repeats neither, so five assertions drive it on
  fixtures instead: a **coloured** `✗` is still extracted, five failures render as three names
  plus a true total, exactly three grow no `(+0 more)` tail, a message carrying its own literal
  `||` survives verbatim rather than gaining false boundaries, and both a marker-less log and
  an unreadable file yield empty so a crash is never misreported as assertions. Confirmed as
  real regression tests by mutation — dropping the escape-strip makes the coloured case yield
  nothing, dropping the overflow notice reddens that case alone, and the pipe fixture fails
  against the join this entry replaces.

- **`ARCHITECTURE.md` now names Core's two deliberate exceptions** instead of leaving
  them to be rediscovered as drift. `zsh/55-maint.zsh` was already excepted in writing at
  the gate; `zsh/60-update.zsh` — ~480 lines of seven-package-manager logic, including a
  Tumbleweed check to choose `zypper dup` over `zypper up` — was justified only in a code
  comment. The reasoning is sound (one verb, N backends, exactly like `bin/clip`) and now
  says so where the layering rule is stated.

- **The maint runner no longer names an OS prefix; the scheduler unit supplies the PATH.**
  A scheduler starts the runner with a stripped environment, which is why the Homebrew
  prefixes were hardcoded. `maint-install` now captures the **live PATH** of the shell
  installing it and bakes it into the unit — `Environment="PATH=…"` (systemd), an
  `EnvironmentVariables` dict (launchd, XML-escaped), and an env-prefixed command
  (cron, POSIX single-quoted and then `%`-escaped, in that order — cron hands its
  command field to `/bin/sh`, so an unquoted or double-quoted value containing `$(…)`
  or a backtick would be **evaluated on every scheduled run**). Whatever prefix this OS
  uses is already correct in that
  PATH, so the OS supplies the truth and Core hardcodes nothing. The brew step is now
  gated on `have brew` alone.

  **Action required on an existing schedule:** a unit written before this change carries
  no PATH, so the runner falls back to the POSIX floor and the brew/mise steps skip
  silently — the job still succeeds while doing less. Re-run `maint-install` once.
  `maint-status` detects this and says so rather than leaving it to be noticed.

- **`tmux-cheat.sh` discovers a brew prefix instead of naming one** — `$HOMEBREW_PREFIX`
  (exported by `brew shellenv`, so the tmux server usually carries it), falling back to
  `brew --prefix`. When neither resolves it adds nothing and takes the existing pager
  fallback: a missing tool degrades visibly, where a wrong absolute path was a silent
  lie on every non-brew machine.

### Fixed

- **A failing linter gate named itself and nothing else.** Five sections — luacheck,
  shellcheck, markdownlint, actionlint, gitleaks — ran their tool with `>/dev/null 2>&1`
  and reported a one-line verdict, so a red run said `✗ markdownlint reported issues` with
  no rule, no file and no line. Each ended with a "run it yourself" hint, which is fine
  locally and useless in CI — the one place the tool is installed, the finding is already
  computed, and re-running it costs a push and a full CI cycle per guess. Diagnosing a
  single MD049 violation this way took three round-trips.

  Output is now captured and printed beneath the `✗`, via a shared `fail_detail` in
  `scripts/lib/common.sh`: stderr (so `--json` keeps stdout parseable), indented (so it
  reads as detail, not as further findings), and capped at `CORE_FAIL_DETAIL_LINES` (40)
  so a pathological run cannot bury the summary it is meant to explain.

  gitleaks also gains `-v --no-color`, without which it prints only `leaks found: N` and
  the file/line/rule stay hidden — the same non-answer. Printing its report is safe
  precisely because `--redact` is already in use: the value is replaced with `REDACTED`,
  so the report names the file, line, rule and fingerprint without reproducing the secret.

- **`core-doctor` reported `✗ bat` on Debian/Ubuntu/Kali for a tool that was installed and
  fully wired** (#418). Those distros ship the binary as `batcat`; `00-tools.zsh` resolves
  it into `$BAT_BIN`, and `cat`, `catp`, `MANPAGER`, the fzf file preview and `fif`'s preview
  all ran on it. The report still called it absent — two lines above its own `resolved`
  section printing `bat → batcat` — and listed `bat` under "install missing", advising an
  install of something already present.

  The cause was an asymmetry between the only two renamed tools. `20-aliases.zsh` gave `fd`
  an alias under its canonical name and `bat` none, so `bat` was untypeable by the name its
  README, man page and every upstream recipe use. `bat` now carries the matching
  `alias bat="$BAT_BIN"` (a no-op `alias bat=bat` where the name is already canonical; zsh
  does not re-expand an alias to its own name).

  That alias is **not** what makes the report honest, though it looks like it would: zsh's
  `command -v` resolves aliases, so `fd`'s `✓` had been coming from the alias rather than
  from PATH all along. The doctor now resolves each row through a new `_core_doctor_bin` —
  one definition shared by the human render and `--json`, so they cannot drift — which maps
  `fd`/`bat` to `$FD_BIN`/`$BAT_BIN` and everything else to itself. Presence, the
  install-missing list and the JSON `tools` object all follow the real binary; the JSON keys
  stay canonical (`.tools.bat`, never `.tools.batcat`) for existing consumers.

  Resolving there also fixed a second defect the alias could never have reached.
  `core-doctor -v` forks `"$tool" --version`, and a **parameter** expansion is never
  alias-expanded — so on Debian the probe ran `fd`, hit `command not found`, and had the
  error swallowed by the pipeline: the row rendered as a bare, versionless `✓ fd`. Both rows
  now fork the resolved binary and print their version. Five cases in `scripts/test-core.sh`
  pin it against a stubbed PATH (Debian names, canonical names, neither), with the doctor
  assertions deliberately run **without** `20-aliases.zsh` loaded so a `✓` can only come from
  the resolver.

- **`PORTING-MATRIX.md`'s `carapace = go³` cells named an install path that cannot be
  followed on any platform.** Footnote ³ promises `go install` where a tool is unpackaged,
  and the carapace row pointed openSUSE and Kali straight at it. That install cannot succeed
  for **any published version**, for two independent reasons: `carapace-bin`'s `go.mod`
  carries `replace` directives (`spf13/pflag`, `kevinburke/ssh_config`), and `go install
  pkg@version` refuses any module that does; and the generated sources
  (`pkg/{actions,conditions}/*_generated.go`) are not committed, so even a plain `go build`
  on a clone fails until `cmd/carapace/main.go`'s `go:generate` lines have run. Checked
  exhaustively rather than inferred from the current release: across all **184 tags** from
  v0.0.3 (2020-08-31) to v1.7.3 (2026-06-30), 184 carry a `replace` directive and 0 commit
  the generated sources. That scope is the operative part — `go install` takes any
  `@version`, and pinning an older one fails identically. Nor is it a transient break to
  wait out: upstream's own `.goreleaser.yml` runs `go generate ./cmd/...` as a pre-build
  hook, and the AUR's from-source PKGBUILD does the same, so this is the intended build
  shape.

  The three cells now point at a new footnote ²⁷ carrying a route per target — the upstream
  `.rpm` for openSUSE (the block `dotfiles-Fedora`'s `bootstrap.sh` already ships and has
  proven), the `.deb` for Kali/Debian, and the AUR **`carapace-bin`** for Arch (the prebuilt
  one; the AUR's bare `carapace` is a from-source, x86_64-only build). Alpine and Gentoo were
  already correct and are now documented as verified rather than merely unmarked. ²⁷ also
  records what the release-URL route costs — no repo is added, so nothing upgrades carapace
  afterwards — the unsigned-artifact wrinkle that makes `zypper -n` stricter than dnf here,
  and the source build as the escape hatch with its real binary size (81.6 MB released,
  ~114 MB unstripped). Footnote ³ gained a pointer so the general `go install` promise is not
  read back onto this row.

  `dotfiles-Arch`, `dotfiles-Kali` and `dotfiles-openSUSE` still make the impossible call in
  their `bootstrap.sh`, failing invisibly because `_dotfiles_go_install` discards the
  explanation; each is tracked in its own repo against this footnote. (`PORTING-MATRIX.md`)
- **The nvim reachability gate invented orphans on `main`.** The membership lookups piped
  into an early-exiting reader — `printf '%s\n' "$visited" | grep -qxF "$m"` — while the
  script runs under `set -o pipefail`. `grep -q` exits on its first match, the writer takes
  EPIPE and dies with 141, and pipefail makes the pipeline non-zero **even though the reader
  matched**: a module that _is_ visited reads as unvisited and is reported as an orphan, with
  `printf: write error: Broken pipe` captured as a finding alongside it.

  Timing-dependent — the writer must still be writing when the reader exits — so it passed
  every PR run and failed on the push to `main`. Measured on a large input, the piped form
  gave 20/20 false negatives and the herestring 0/20. Every lookup now feeds its input by
  herestring, `awk … <<<"$mods"` included, since `awk`'s `exit` closes the pipe the same way.
- **`blib_set_login_shell` could throw away a complete, correct wiring over its last,
  purely cosmetic step.** It runs at the very end of `wire_links`, after every symlink is
  already in place — but neither the `/etc/shells` append nor `chsh` tolerated failure, so
  under the caller's `set -e` a host with a read-only `/etc` (a container), a restricted
  `chsh`, or an LDAP/SSSD-backed account aborted the whole bootstrap. Worse, the operator
  saw a bare `tee: /etc/shells: Permission denied` and no indication of what had or had not
  been done. Both steps now warn and continue, naming the manual command to finish the job.

- **`grep -q` on a large piped producer read a match as a failure under `pipefail`.** The
  new `origin/main` CHANGELOG guard piped a 4000-line file into `grep -q`, which exits the
  moment it matches — leaving `git show` to die of `SIGPIPE`, and `set -o pipefail` then
  surfaced git's 141 rather than grep's 0. The check reported "no heading" on a file that
  had one. Captured to a variable instead. Swept the rest of the tree for the same shape:
  the other instances pipe small `printf`/`find` output that fits the pipe buffer, so they
  never trip it, and the one borderline case in `test-core.sh` was made immune anyway.

- **The atuin autostart apparatus gate now tells a slow box apart from a broken detector.**
  The gate proves the box can bind and connect an AF_UNIX socket with python3 alone, then
  runs a known-good stub and treats any verdict other than `holds` as a regression in
  `verify-atuin-guard.sh` — deliberately, because the obvious "skip unless it holds" form
  uses the code under test as its own apparatus check and would let a real regression skip
  every assertion below while leaving the audit green.

- **`core-doctor` no longer reports a false `○ (idle)` for starship and carapace.**
  `_core_wired` probed only `starship_precmd` and `_carapace`, but both tools renamed the
  functions their `init` emits — starship 1.24.2 emits `prompt_starship_precmd` and
  carapace-bin 1.5.7 emits `_carapace_completer`, and neither emits the old name at all.
  Since Core sources each tool's own init (`_cache_eval starship starship init zsh`), the
  probe silently went stale as the tools moved, so every box on a current starship or
  carapace saw `○ (idle)` for an integration that was demonstrably driving the prompt and
  completion (measured: 1760 carapace-bridged commands, `PROMPT` set by starship). That is
  the exact failure the probe exists to prevent, inverted — a misleading `○` instead of a
  misleading `✓`. Both arms now accept the old **and** current names, so boxes pinned to
  older releases keep reporting wired.

- **The atuin autostart apparatus gate no longer reds when the box is merely slow.** The
  gate proves the box can bind and connect an AF_UNIX socket with python3 alone, then runs a
  known-good stub and treats any verdict other than `holds` as a regression in
  `verify-atuin-guard.sh` — deliberately, because the obvious "skip unless it holds" form uses
  the code under test as its own apparatus check, and would let a real regression skip every
  assertion below while leaving the audit green.

  The strictness was right; the **deadline** was not. §J4 runs at `CORE_ATVERIFY_POLL=3`,
  chosen so the many negative cases do not idle away a long bound — but for the one stub that
  is supposed to succeed at everything, that bound is not idle waiting, it is a deadline:
  300ms for a spawned daemon to bind and answer. A loaded runner misses it, the verifier
  declines with "a daemon started by hand … never answered" exactly as designed, and the gate
  rendered that property of the box as a defect in the detector. It reddened an audit leg for
  a change that had nothing to do with atuin.

  The tempting repair — skip on `unmeasurable` — is wrong, and the reason is recorded in the
  code because it is easy to re-derive incorrectly: that verdict is the verifier's fail-closed
  answer for a family of causes, and most are deterministic and _are_ the detector (a renamed
  or duplicated anchor, control-arm row accounting that no longer matches, and `internal: no
  verdict was reached (this is a bug in verify-atuin-guard.sh)`). Skipping on it would silence
  sixteen assertions while the subject announces its own bug, and no amount of retrying
  separates those from slowness, since every one of them repeats.

  So nothing skips. The known-good run simply gets a deadline with real headroom — 30 ticks
  instead of 3, plus one retry — while every negative case keeps the tight bound. A transient
  stall now has to land twice inside a 10x-wider window to be seen at all. Measured on the
  repo's own fixture with all four arms holding: 10.9s at 3 ticks, 14.0s at 30, 23.4s at 100 —
  so this costs about three seconds of wall clock, once per suite, and 30 rather than 100
  because `--premise autostart` also spends the bound _proving unreachability_, which no
  amount of promptness shortens. The gate keeps the property that matters: it cannot go quiet,
  because every verdict other than `holds` still reddens it. The three failures are now told
  apart — `moved` (miscategorising correct behaviour), `unmeasurable` (declining where it
  should measure, carrying the verifier's own reason), and no parseable verdict at all (the
  apparatus failing to report, carrying stderr — the Alpine shape where a stray line merged
  into the JSON).

- **The atuin autostart suite no longer reports an unmeasurable run as an upstream finding.**
  `verify-atuin-guard.sh` has three verdicts on purpose — `holds`, `moved`, and
  `unmeasurable` for "the apparatus could not be trusted, never a finding about upstream" —
  but the socket-only-stop assertion in `scripts/test-core.sh` compared against `holds` and
  swept everything else into a single `else`, so a declined run printed the exact claim the
  third verdict exists to prevent: that a zombie daemon had kept committing into later arms.

  It is the only arm in that section expecting the POSITIVE verdict from an otherwise
  well-behaved stub, so it alone inherits every environmental way a run can honestly decline.
  The section runs at `CORE_ATVERIFY_POLL=3` — 300ms for the manual-spawn control's daemon to
  bind and answer — which a loaded box misses, yielding "a daemon started by hand never
  answered … An apparatus limit, not a finding" with **nothing having survived**. That
  reddened `audit-alpine` on an unrelated docs-only PR; a rerun of the identical commit went
  green.

  The three states are now distinguished: `holds` with no survivor passes, `unmeasurable`
  skips with the verifier's own reason surfaced, and `moved` fails as the real finding. A
  run that produces no parseable verdict at all is reported as its own outcome carrying
  stderr, rather than being read as `moved` — that shape has a history here, being how §J4
  first went red on Alpine when a stray musl-side line merged into the JSON. The
  assertion does not go quiet in exchange — the survivor half is now checked unconditionally
  and stays a failure under any verdict, because a live daemon is a leak whether or not the
  run could measure. A contaminated control cannot hide behind the skip either: the opening
  control runs before any daemon exists, the spawn control while the socket is still present,
  and the closing drain control only after the owner pid is confirmed dead — so the zombie's
  rows have no route to `unmeasurable`, only to `moved` or a survivor.

- **A concurrent test run no longer fails the audit with a sandbox leak that never
  happened.** `verify-atuin-guard.sh --premise autostart` built its sandbox at
  `/tmp/atverify.XXXXXX`, and the `test-core.sh` assertion that a completed run leaves no
  sandbox behind enumerated that prefix _globally_ — snapshot before, snapshot after,
  anything new is a leak. `/tmp` has other writers, so a second suite running on the same
  box during the window was counted as the first run's leak. Two worktrees, two agents, or
  simply `make audit` in one terminal while `make tag` audits in another was enough.

  It cost a real `make tag` — `leaked 1 new sandbox dir(s)` on the repo's most consequential
  command, where the operator's natural next move is to re-run or reach for
  `TAG_SKIP_AUDIT=1`. A release gate that teaches the operator to skip it is worse than no
  gate.

  Sandboxes now carry a per-run tag — `/tmp/atverify.<tag>.XXXXXX`, from the new
  `CORE_ATVERIFY_TAG` — and the assertion globs only its own. The tag **defaults to the
  script's pid**, so `make verify-atuin-guard` and `atuin-guard-verify.yml` pass nothing and
  still get a prefix no concurrent run can collide with; two live processes cannot share a
  pid. It is validated as 1-16 characters of `[A-Za-z0-9_-]` and rejected rather than
  sanitized, because it becomes a path component and a caller that globs its own tag needs
  the tag it passed. The cap is an AF_UNIX budget, not style: `sun_path` ends near 108 bytes
  and the daemon socket sits inside the sandbox, which is the same reason `/tmp` is
  hardcoded there instead of `$TMPDIR`.

  An **empty** tag is rejected rather than defaulted, which is why the knob reads `${…-$$}`
  and not the `${…:-…}` its two neighbours use. An empty value is not a caller asking for the
  default — it is a caller whose tag expression came out empty — and accepting it would
  sandbox under the pid while the caller globbed `/tmp/atverify..*`, matching nothing and
  greening the leak assertion forever. That is the same vacuous pass the self-check exists to
  catch, arriving by a different door.

  The validation runs **in the C locale**, and this is a defect that was shipping rather than a
  precaution: POSIX defines a range like `[A-Z]` by _collation_ rather than codepoint, and on
  **glibc under `en_US.utf8` the unpinned pattern accepts `tág`** — measured on the Ubuntu CI
  leg, not reasoned about, so the ASCII-only contract was not being enforced there at all. It is
  invisible from macOS, where all 84 installed UTF-8 locales reject the same sample, which is
  exactly why Core cannot take one userland's answer for the fleet's. The byte cap
  is the same fault one step downstream: `{1,16}` counts _characters_, so sixteen multibyte ones
  are up to 64 bytes and the limit stops being the AF_UNIX budget it exists to be. Downstream,
  not separate — every character in `[A-Za-z0-9_-]` is single-byte ASCII, so the count can only
  diverge from the byte length once collation has already leaked a non-ASCII character in.

  The suite reports **how much of this it actually exercised**, rather than implying more. It
  asks the box for its installed UTF-8 locales (`locale -a`, falling back to named candidates
  on musl, which ships no such command) and looks for one under which the _unpinned_ pattern
  really accepts a non-ASCII sample. Finding one, it names it and the case genuinely fails if
  the pin is removed; finding none, the result states the count and says the pin is unexercised
  there, asserted by contract only. Across the fleet that reads: Ubuntu **exercised under
  `en_US.utf8`**, while macOS (84 installed), Arch (1 installed) and Alpine (7 candidates, since
  musl ships no `locale`) report contract-only — so one leg proves the fix and the other three
  say honestly that they cannot. The no-match case then runs
  under `LC_ALL=C` rather than an empty `LC_ALL`, which is not "no locale" at all but a
  fall-through to the caller's `LANG`: an unprobed locale that could be the very one that
  accepts the sample, making the run exercise the pin while the line claimed it had not.

  Two earlier drafts of this check were vacuous — one probed for multibyte _decoding_, which a
  locale can do while still collating `á` outside `[A-Za-z]`, so it passed identically with the
  pin removed. That is the shape this file already exists to refuse, and the coverage line is
  now part of the assertion rather than a comment about it.

  Two assertions, because narrowing a glob and blinding it look identical from a green run.
  The leak check now plants a foreign-tagged sandbox _inside_ its own window and still
  requires a clean delta; a companion case plants one foreign and one of its own and
  requires the delta to name its own and only its own. The existing self-check — which fails
  loudly when the glob cannot enumerate at all, after an unfollowed `/tmp` symlink once made
  this pass vacuously on macOS — is unchanged, and matters more now: a tag that never reached
  the script would empty both snapshots the same way.

- **`maint-status` now reports a scheduler unit whose runner path no longer exists.**
  `_maint_unit_needs_refresh` only ever asked whether the unit carried a PATH capture, so
  the other way a scheduled job dies silently went unreported: move the consuming repo and
  the scheduler keeps firing at the absolute runner path frozen into the unit at install
  time. Found on a real machine, where a launchd agent had been pointing at a path that had
  not existed for months.

  Nothing surfaced it from any angle. `maint-status` printed the timer happily, `launchctl
  list` showed exit status 0 because the job had not fired since the move, and `maint-run`
  kept working — it resolves the runner relative to the live config rather than reading the
  unit, which is exactly why the breakage stayed invisible.

  The detector now also reads the runner back out of the unit — `ProgramArguments[1]` from
  the launchd plist, the path after `ExecStart=/usr/bin/env bash` in the systemd service,
  the command past cron's single-quoted `PATH=` prefix — and flags it when it does not
  resolve. Both causes are fixed by re-running `maint-install`, so the hint now says _which_
  happened: a stale unit predating the PATH capture is a snapshot to refresh, a dead runner
  path usually means the repo moved.

  Each arm matches the exact shape `maint-install` renders and stays quiet on anything
  else, because a "close enough" parse turns a live job into a false death notice: the
  systemd and cron arms read a _command_, not a path field, so a hand-edited
  `… bash /runner --quiet` or `… bash /runner >>/log` must not be read as one long,
  nonexistent path; and the launchd array must be `ProgramArguments`' own value rather
  than the next array in the plist. A recorded path must also be absolute, which
  `maint-install` always writes: a relative one would be resolved by `[[ -f ]]` against
  whatever directory `maint-status` was invoked from, making the verdict a property of the
  caller rather than of the unit. A box with no schedule installed stays quiet too.

  Every token is located by _position_ rather than by appearance: launchd's `argv[0]` must
  be the interpreter, and cron's `PATH=` value is consumed as a real single-quoted token, so
  a command that merely contains text resembling the interpreter — inside the assignment, or
  inside a later quoted argument — can never have its argument read back as our runner. On
  the launchd side the encoded forms a plist may legally use (`&quot;`, `&apos;`) are decoded
  so the hint names the real filename, and anything undecodable (a numeric character
  reference, an unknown entity) is refused for the same reason the rest is: a filename that
  cannot be reconstructed is not evidence of anything.

  The two causes can coexist, and a unit predating the PATH capture is if anything the
  likeliest to have been orphaned by a move as well — so the runner is inspected first and
  `path` is the fallback. Reporting the milder cause there would tell the operator that some
  steps will skip on a job that does not run at all.

  A `%` in the recorded runner disqualifies it in both command-reading arms, because in
  neither is the literal text what runs: systemd expands `%` specifiers in `ExecStart` — the
  expansion `_maint_systemd_escape` already doubles against in `Environment=` — and cron
  reads `%` as its newline metacharacter.

  Thirty-one behavioral assertions — twelve scheduler states, four that a recorded path is
  extracted correctly (two read back verbatim, plus escaped-quote scanning and `&apos;`
  decoding), twelve that an extended command, a displaced array, a relative path, a
  spliced-in program, a quoted look-alike, an undecodable reference, or a `%`-bearing value
  is refused rather than mis-parsed, and three that a dead runner outranks a stale PATH. The healthy fixtures point
  at a runner that really exists, or the whole section would pass vacuously.

- **The release cut no longer tells the operator to do something the repo forbids.**
  `RELEASE-RUNBOOK.md` §1.1 step 4 said "merge commit, not squash", and `tag-release.sh`
  printed the same hint twice. Merge commits are disabled — `mergeCommitAllowed` and
  `rebaseMergeAllowed` are false, and `main`'s ruleset pins
  `allowed_merge_methods: ["squash"]` — so the instruction was impossible to follow, and it
  was printed at the worst possible moment: mid-cut, by the repo's highest-stakes command,
  where the natural reaction is to assume the _ruleset_ is misconfigured and go change it.
  v4.10.0 had already shipped as a squash (`cd4278e`, one parent) in silent contradiction.

  The "not squash" clause was never load-bearing. It was descriptive — added in #106 (first
  shipped in v2.1.1) to record how releases merged then, since #95, the v2.0.0 release, had
  landed as a real merge commit back when merge commits were still enabled — and left behind
  when they were turned off. What makes the recipe correct is step 5 tagging `origin/main`,
  the post-merge tip, so
  `release.yml`'s `core.version`-at-the-tagged-commit guard, `git describe`, and the `vN`
  alias are all satisfied by a squashed tip. `RELEASE-RUNBOOK.md` now records that reasoning
  under §"Why squash is fine", including the instruction to trust the repo over the docs if
  they ever disagree again.

  `tag-release.sh` now names **no** merge method rather than swapping one hardcoded claim
  for another. Deriving the wording from the live setting would need `gh` and a network
  call, which its offline-safe next-steps output cannot take, and there is no
  settings-as-code file to read instead. Naming a method was never actionable anyway —
  GitHub only offers the methods a repo enables, so the operator cannot pick a disallowed
  one. The hints now state the property that actually matters (step 2 tags `origin/main`,
  so the merge method cannot affect the tag), which has no way to go stale.

- **The boundary scan no longer strips comments at all.** Stripping was a false-negative
  machine: `#` is a comment in shell and TOML but the **length operator** in Lua, so
  `local p = t[#t] .. "<prefix>/bin"` was truncated and passed; a delimiter inside a string
  is code, so `export P="#<prefix>/bin"` was truncated too; and a line inside a heredoc or
  a Lua long-bracket string is runtime data however it starts. Each fix uncovered the next,
  because getting it right needs a parser for all five grammars the gate now scans.

  The rule is flat instead: a manifested Core file must not contain an OS-absolute path
  **anywhere, prose included** — name the prefix rather than spelling it. Two comments in
  `maint/` and `tmux/scripts/` were reworded to comply. That costs a wording choice and
  buys a gate with no hiding places.

  The one sanctioned exemption is now **redacted rather than dropped**. Removing the whole
  `LaunchAgents` line exempted everything else on it, so a second literal riding along on a
  legitimate assignment evaded the gate; only the sanctioned segment is replaced now, and
  the rest of the line is scanned normally. Verified against the old filter: with
  `_x="<prefix>/bin"` appended to a `LaunchAgents` line, the line-drop passed it and the
  redaction catches it.

- **`V4-PROPOSAL.md` no longer claims v4 is unreleased.** Its status block said
  _"IMPLEMENTED … pending the v4.0.0 release cut"_ and described the work as sitting on a
  branch — ten minor releases after v4.0.0 shipped. It is now marked as the historical
  design record it is, pointing at `ARCHITECTURE.md` / `PORTABILITY.md` / `VENDORING.md`
  for how the shipped system actually behaves.

- **The Core⇄OS boundary gate was green while two Core files carried Homebrew paths.**
  `audit-core.sh` §5c rejects OS-absolute paths in portable Core, but its file list
  stopped at `zsh/*.zsh` plus the symlinked configs — so `bin/`, `maint/`, and
  `tmux/scripts/`, all manifested Core that ships to eight repos, were never scanned.
  They were not clean: `maint/dotfiles-maint.sh` hardcoded `/opt/homebrew/{bin,sbin}`
  and `/home/linuxbrew/.linuxbrew/bin` in its PATH _and_ probed both by absolute path
  to run `brew shellenv`, and `tmux/scripts/tmux-cheat.sh` did the same in its pop-up
  PATH. The rule was documented, believed enforced, and was not — on seven of the eight
  target machines those paths do not exist.

  The gate's scope is now **derived from `core.manifest`** rather than hand-kept. That
  list had fallen behind three separate times — first the symlinked configs, then the
  `bin/`/`maint/`/`tmux/scripts/` executables, and even then it still omitted
  `zsh/completions/*`, `lib/ux.sh`, `lib/bootstrap-lib.sh` and `.bin/sync-upstream.sh`.
  Every omission was the same bug, so the fix is structural: the manifest already _is_
  the definition of "what is Core", and a file added to it is scanned automatically. The
  blind spot cannot silently reopen, because reopening it would mean the file is not Core
  at all — which the manifest gate already fails on. Coverage went from 19 files to 167
  (including the vendored `nvim/` tree).

  The gate is also unconditional now: it used to be `SCOPE_SHELL`-gated, but it is pure
  `sed`+`grep` and cross-cutting, so a narrowed `--scope` run must not be able to skip a
  fan-out-correctness check.

  The one exemption — `zsh/55-maint.zsh`, whose launchd arm legitimately writes
  `~/Library/LaunchAgents` — is now **per-line rather than per-file**. Skipping the whole
  module would have re-opened the blind spot _inside_ it: an accidental `/opt/homebrew`
  added to `maint-install`, or to any other function there, would have sailed through.
  Only the `LaunchAgents` lines are dropped; everything else in the file is scanned.

  Verified the way a gate change has to be: the previous tree is **red** under the new
  scope and green under the old one, which is the only evidence that the widening bites.

- **`maint-install` now escapes the runner path it writes into every scheduler unit.** The
  write-side half of the `%` problem the entry above only closed on the read side: the
  captured PATH was already escaped three different ways, one per scheduler grammar — but
  the runner alongside it went in **raw**, and it is no more of a constant: it is wherever
  the consuming repo happens to have been cloned. A single metacharacter in that path
  produced a broken schedule, and all three failures were silent or nearly so:

  - **systemd** expands `%` **specifiers** in `ExecStart=` (`%h` = home directory, `%i` =
    instance, …), so a repo under `…/a%h/…` ran a different path entirely — or the unit
    refused to load outright on an unknown one. It substitutes **variables** there too, so
    a component literally named `${HOME}` was equally not the path that ran. The
    `Environment=` line one row above was already protected against the specifiers — and
    performs no variable substitution at all, which is why `$` needs its own pass rather
    than a wider shared helper. The argument was also unquoted, so `systemd` split the
    runner on whitespace, and a `"` or `\` in the name carried unit-file syntax rather than
    being part of the filename.
  - **cron** treats `%` as its **newline** metacharacter: the command was truncated there
    and the remainder handed to it as stdin, so the job simply stopped running.
    `maint-install` already escaped `%` in the PATH portion and not in the runner. The
    runner was unquoted besides, so a space split the command and a `$(…)` or a backtick in
    the path was _code_, evaluated on every scheduled run.
  - **launchd** got `&`, `<` or `>` straight into `ProgramArguments`, yielding a malformed
    plist that `launchctl load` rejects. The PATH value two lines below was already escaped.

  Each field now goes through the escape its own grammar needs: the systemd runner is
  written **quoted**, through the `Environment=` helper plus a command-line-only `$` → `$$`
  pass (quoting is what reduces whitespace, `"` and `\` to the same substitutions `%` and
  `$` already needed), the cron runner through the same single-quote-then-escape-`%` pair as
  the cron PATH, and the launchd runner — along with the two log paths, which had the same
  hole — through the plist's XML escape.

  The crontab entry is also emitted with `print -r` rather than `echo`. `maint-install` runs
  under `emulate -L zsh`, where the `echo` builtin **interprets backslash escapes** — so two
  characters in a directory name were enough to corrupt the table that the careful quoting
  above had just produced: `\n` split the entry across two lines and `\c` truncated it
  outright, leaving a schedule that silently was not the one anyone asked for.

  `_maint_unit_runner` decodes each new encoding symmetrically, so `maint-status` keeps
  naming the real filename. It stays as strict as it was, and the strictness is the same
  rule in three places: a value the reader cannot _reconstruct_ is not evidence of anything,
  so it is refused rather than guessed at. The systemd arm therefore refuses a closing quote
  with argv after it, a surviving `%` specifier, and a surviving `$VAR` reference — the text
  in the file is then not the path systemd runs, and resolving either would mean
  reimplementing systemd's specifier table and reading the unit's environment block. The
  cron arm refuses a **bare** `%` — one that is not our own `\%` — because sh quoting is no
  defence there: cron translates the field before `sh` ever sees it, so the command is
  truncated at that `%` whatever the quotes say. That test has to run _before_ the `\%`
  decode, which would otherwise destroy the evidence of which kind of `%` it was. The
  launchd arm already applied the same rule to an undecodable entity reference.

  The older unquoted shapes still parse, because a unit on disk is only rewritten when the
  operator re-runs `maint-install` — and a `%` in one of those is still refused outright by
  `_maint_lone_arg`, which remains the right answer there: nothing escaped it, so the
  recorded text genuinely is not the path that runs.

  Twelve further assertions: one round-trip per scheduler through a runner path holding
  `% $ ${} & < > " \ '`, a space, and the two-character sequences `\n` and `\c` — installed,
  read back verbatim, and reported as _current_ rather than as a dead runner — one per
  scheduler confirming the same artifact through a party that is not this codebase
  (`/bin/sh` parses the cron command back after applying cron's own `\%` pass, `plistlib`
  parses the plist, and the systemd `ExecStart` is pinned against a literal expectation),
  one that the crontab entry is a single **marker-terminated** line, and five refusals for
  the quoted shapes. That one is stated as a pair deliberately: with this fixture the two
  `echo` corruptions cancel in the line count — `\n` adds a newline and `\c` removes the
  final one — so a bare "is it one line" check reads green on a table that is one wrapped
  fragment plus one unterminated one. Reaching the marker is what truncation cannot fake.
  A round-trip through our own reader alone would pass a matched pair of wrong escapes, and
  a fixture whose backslash pair is not a recognized escape passes the `echo` hazard without
  ever exercising it — the first revision of this one used `\g` and did exactly that. The
  whole block skips, rather than passing vacuously, on a filesystem that will not take `"`
  or `\` in a name. The pre-existing cron render assertion now anchors on the runner's
  closing quote, so dropping the quoting fails there rather than on the one box whose path
  has a space.

### Security

- **Caller-supplied workflow inputs no longer reach a `run:` body as code.**
  `auto-tag-call.yml` spliced `${{ inputs.bump }}` straight into its script in a job
  holding `contents: write` **and** `persist-credentials: true`, so a caller passing
  `bump: 'patch"; …; #'` could run arbitrary code with the tag-push token. It was the
  one place the fleet broke the rule `notify-web-call.yml` states outright — _"a
  caller-supplied string must not be able to write shell"_.

  Both `bump` and `release` now arrive through `env:`, and `bump` is checked against a
  `patch|minor|major` allowlist at runtime — `workflow_call` inputs cannot be
  `type: choice` (that is `workflow_dispatch`-only), so the type system will not do it.
  A typo now fails with the valid set instead of reaching `auto-tag.sh`'s arg parser.

  `claude-routines-call.yml` had the same shape with `${{ inputs.distro }}` in a job
  holding `CLAUDE_CODE_OAUTH_TOKEN`; it now goes through `env:` too, and is likewise
  allowlisted to the six distro names its own input contract already documents — `env:`
  makes the value shell-safe, but the Claude prompt is an _instruction_ channel, so an
  arbitrary string there remains a prompt-injection vector. No `run:` body in any
  workflow interpolates an expression any more.

  Neither rejection path echoes the raw value back. The runner parses stdout line by
  line, so a multiline input can open a new `::…::` command on the following line and
  forge or suppress annotations no matter how well it is shell-quoted; both paths strip
  `CR`/`LF`/`%`/`:` and truncate first, mirroring how `atuin-guard-verify.yml` already
  handles upstream-derived text.

## [v4.10.0] - 2026-08-13

### Added

- **The `autostart` stand-down is measured now, not assumed** (`dotgibson/dotfiles-core#402`).
  `_core_atuin_daemon_guard` stands down _entirely_ under `ATUIN_DAEMON__AUTOSTART` — it
  unhooks itself from `precmd_functions` and never probes — because atuin is supposed to
  supervise its own daemon there. That covers **Alpine and macOS**, two of the eight machines,
  and on those two it was the only mitigation. Nothing measured it: the weekly detector never
  set the variable, so a green run said nothing about those rows, and an upstream regression
  would have cost them their history with no symptom — the same failure mode as #366.

  `scripts/verify-atuin-guard.sh` gains `--premise discard|autostart` (default `discard`) plus
  `make verify-atuin-guard-autostart`, and the weekly workflow gains `measure-autostart` and
  `report-autostart` jobs with their own issue titles. **One premise, one verdict, one title**:
  an autostart finding needs a different remedy from a discard one, and would otherwise arrive
  under a heading that misdescribes it. The default target still starts no background process —
  asserted by construction, since the stub logs every invocation it receives.

  The measurement's own discipline is the interesting part. Because this premise is _caused_
  rather than observed, "autostart did not spawn a daemon" and "this box cannot host a daemon"
  are the same observation — so a **manual-spawn control** runs first and its failure is
  `unmeasurable`, never a finding about upstream. A second control tries a manual bind over a
  _stale_ socket and records the answer, which is what separates "the client will not re-spawn
  after a crash" from "the daemon cannot bind over a leftover inode". Teardown goes through
  `atuin daemon stop` and is **proven** by a connect rather than believed from an exit status,
  escalating to the socket's owning PID and then a signal; the run refuses to spawn at all on a
  build lacking either subcommand, because a daemon it cannot reap would be left writing into a
  tree the exit trap is about to delete.

  Two upstream facts this established on 18.19.0, both recorded in `PORTING-MATRIX.md`: the
  **stale-socket shape is the load-bearing one** — every `atuin history start` is a fresh
  process, so "fire-and-forget" can only mean a crashed daemon's leftover inode defeats the
  spawn — and the healing lives in the **client**, since `atuin daemon start` alone refuses over
  a stale inode with `Address already in use` while the autostart path unlinks it first. Also
  measured, and load-bearing for the arms: with a daemon serving, `history start` writes nothing
  and the row lands on `history end`.

  `/tool-scout` loses a standing upstream question it could only ever have answered from release
  notes, and the report names the trap in its own remedy: "make the guard stop standing down" is
  the fix that breaks those two machines, because the degrade path sets
  `ATUIN_DAEMON__ENABLED=false` and under autostart that removes the spawn itself.

- **`git-absorb` — auto-route staged hunks into the earlier commit each belongs to**
  (`dotgibson/dotfiles-core#394`). `00-tools.zsh` now detects `git-absorb` and sets
  `HAVE_GIT_ABSORB`. It works out which earlier commit each **staged hunk** belongs to and
  writes the `fixup!` commits for you; `git/gitconfig` already sets
  `rebase.autosquash = true`, so `git rebase -i` folds them in without further ceremony. It
  is the automatic counterpart to the `git fix` alias Core has always shipped — `git fix
  <sha>` when you know the target commit, `git absorb` when you don't. That `[alias]` line
  now carries a comment saying so.

  **This is the house-style ideal: a tool that needs no alias at all.** It installs as
  `git-absorb` on `PATH`, which git dispatches as the `git absorb` subcommand, so it shadows
  nothing and `20-aliases.zsh` gains only a note explaining why there's nothing to add.
  Detection exists purely so `core-doctor` can report it, where it joins the `dev / repo`
  group. One documented caveat: the probe is `command -v git-absorb`, so a distro that
  installed the binary into git's `libexec/git-core` instead of a `PATH` directory would
  give a working `git absorb` and an unset flag — no mainstream package does, and probing
  `git absorb --version` would add a `git` fork to every interactive shell, which
  `00-tools.zsh` exists to avoid.

  **Correction (#424).** "No mainstream package does" was wrong when it shipped. Debian-family
  packages do exactly this on both boxes anyone has checked — **Kali** `git-absorb`
  0.6.17-2+b4, whose only binary is the one in git's exec-path, and **Ubuntu 24.04** 0.6.11
  from the reporter's `dpkg -L` in #424 — so this release's `core-doctor` reported
  `✗ git-absorb` on boxes where `git absorb` worked. **Debian proper is unverified**, then and
  now; the claim is the packaging convention plus two confirmations of it, not a survey.
  Fixed in the `[Unreleased]` entry above. Corrected inline
  rather than rewritten, because it was wrong when shipped and the record should say so.

  The same correction supersedes the version line below: **Kali was never on 0.9.0.** It
  ships `git-absorb` 0.6.17-2+b4 — verified on-box 2026-08-17 — so "Homebrew and Debian/Kali
  all on 0.9.0" reads one package-page figure onto two distros that had already diverged,
  and openSUSE was therefore not the only laggard. Debian proper remains unverified.

  It is also the first `core-doctor --json` key that is not a bare identifier, so the
  function's docstring now says which parsers care: the key is emitted quoted and the JSON
  is valid, but jq's dot shorthand reads `.tools.git-absorb` as a subtraction — consumers
  write `.tools["git-absorb"]`.

  Packaged essentially everywhere and installed nowhere on Linux, so it takes the ²¹
  "available, not installed" shape and joins that footnote's macOS-only bullet alongside
  `lnav`. Verified against each distro's own package pages: Arch `extra`, Alpine
  `community`, **Gentoo `dev-vcs/git-absorb` stable on amd64 in the main tree** (no GURU),
  Homebrew and Debian/Kali all on 0.9.0 — note repology reports the Debian **source**
  package as `rust-git-absorb` while the **binary** you install is `git-absorb`. **openSUSE
  Tumbleweed is the one laggard at 0.6.17**, the gap #394 flagged, now confirmed rather than
  snapshotted. New `PORTING-MATRIX.md` row and footnote ²⁶. (`zsh/00-tools.zsh`,
  `zsh/20-aliases.zsh`, `zsh/30-functions.zsh`, `git/gitconfig`, `PORTING-MATRIX.md`)

- **`watchexec` — event-driven repetition, the third corner of a triangle Core had two of**
  (`dotgibson/dotfiles-core#393`). `00-tools.zsh` now detects `watchexec` and sets
  `HAVE_WATCHEXEC`. `viddy` re-runs a command on a **timer** and `hyperfine` re-runs it a
  fixed **count** while measuring; nothing re-ran it when **files changed** — the
  "re-run the tests when I save" verb (`watchexec -e py -- pytest`). Own command, inert
  without the binary, and deliberately **not** aliased to `watch`: `20-aliases.zsh` already
  points `watch` at `viddy`, and collapsing "re-run on a timer" into "re-run on a change"
  would silently hand you the wrong one. It also opens a new `dev / repo` group in both of
  `core-doctor`'s inventories.

  **It is the one tool in the matrix that nothing in the fleet installs, macOS included** —
  unlike `lnav`, the MacBook `Brewfile` doesn't carry it either, so every machine is opt-in.
  Arch `extra`, openSUSE Tumbleweed, Alpine `community` (native musl) and Homebrew are all
  on 2.5.1; **Gentoo has it in GURU only** at 2.5.0 — and it is deliberately kept out of
  footnote ¹²'s GURU list, which enumerates what `dotfiles-Gentoo` actually installs, not
  what exists (the `gping`¹⁹ precedent). **Fedora and Debian/Kali don't package it at all**
  — confirmed against Fedora's own package search, not a repology snapshot — so those two
  take `cargo install --locked watchexec-cli`; note the crate is `watchexec-cli`, because
  plain `watchexec` on crates.io is the library and installs no binary. New
  `PORTING-MATRIX.md` row and footnote ²⁵. (`zsh/00-tools.zsh`, `zsh/20-aliases.zsh`,
  `zsh/30-functions.zsh`, `PORTING-MATRIX.md`)

- **`lnav` — the missing "read a log as a log" verb** (`dotgibson/dotfiles-core#392`).
  `00-tools.zsh` now detects `lnav` and sets `HAVE_LNAV`. Core had no tool for this
  category at all: `bat`/`rg` read a log as **lines**, `jq`/`gron`/`jnv` read it as
  **JSON**, `glow` as markdown — none of them knows that a log is a sequence of
  timestamped records. `lnav` autodetects the common formats, merges several files into
  one timeline ordered by timestamp, follows like `tail -f`, and exposes the parsed
  records to SQL. It's its own command with no alias (like `jq`/`gron`/`jnv`) and is inert
  without the binary, so nothing changes on a box that doesn't have it.

  Unlike the Rust/Go tools already in the matrix it is a **C++** CLI, so there is no
  `cargo install`/`go install` escape hatch — but it doesn't need one: upstream ships
  **static musl binaries** each release (`lnav-0.14.0-linux-musl-x86_64.zip` plus an
  `arm64` twin), so the fallback on an unpackaged or lagging box is "unzip the official
  build", not "compile it". It is **detect-only on Linux**: no Linux repo's `install/packages.txt` carries
  it and no `bootstrap.sh` installs it, so the flag lights up only once you install it
  yourself; **macOS is the exception, where the `Brewfile` has carried it since
  2026-07-15**. That is `hyperfine`/`shellcheck`/`shfmt`/`ouch`'s situation, so `lnav`
  joins that bullet in footnote ²¹ and its row carries ²¹ alongside its own ²⁴.

  Every version was read off the distro's own package page rather than a repology snapshot,
  and **Fedora is reported per release** because it is a versioned distro and one
  unqualified "current" hides the answer: **F45/Rawhide 0.14.0, F44 0.13.2, F43 0.12.4**.
  Arch `extra`, openSUSE Tumbleweed and Homebrew are on 0.14.0, and **Alpine has a native
  musl build in `community`**. Two targets lag enough to name: **Gentoo at 0.11.2** — the
  only version in the tree, and the package needs a new maintainer — and **Kali/Debian at
  0.13.2**. On any of them the upstream static musl zip gets you 0.14.0 without waiting for
  the package. New `PORTING-MATRIX.md` row and footnote ²⁴, and `lnav` joins the
  `data / net` group in both of `core-doctor`'s inventories. (`zsh/00-tools.zsh`,
  `zsh/20-aliases.zsh`, `zsh/30-functions.zsh`, `PORTING-MATRIX.md`)

- **OSC 133 semantic prompt marks — `[` / `]` jump between prompts in tmux copy mode**
  (`dotgibson/dotfiles-core#391`). Core emitted no OSC sequences at all, while tmux has parsed
  OSC 133 since 3.4 and exposed `previous-prompt` / `next-prompt` in copy mode the whole time —
  the capability was already paid for on every machine (the fleet floor is Gentoo's 3.6a) and
  simply unused. `zsh/00-tools.zsh` now marks prompts and `tmux/tmux.reset.conf` binds `[` / `]`
  in `copy-mode-vi` to jump between them, turning "scroll up hunting for where that command
  started" into a keypress. No new file, no binary, no `core.manifest` change; `{` / `}` are
  deliberately left alone (vi previous/next-paragraph), and no version gate is needed.

  **The `A` mark lives in `$PROMPT`, and that is measured rather than preferred.** The obvious
  implementation — emit `\e]133;A\e\\` from `precmd`, next to the command-block rule that
  already runs there — does not work, and fails silently: zsh's prompt preamble ends in `ED`
  (`\e[J`, "erase to end of screen") over the very line the mark was just written to, and tmux
  drops a line's prompt flag when that line is cleared. Measured on tmux 3.7b, `previous-prompt`
  then does not move at all — the feature looks implemented and does nothing. Embedding it in
  `PROMPT` as a zero-width `%{…%}` escape means it is re-emitted on every prompt _draw_, after
  that `ED`, which is also why every other shell integration marks prompts this way. The hook
  that applies it is APPENDED to `precmd_functions`, so it runs after `starship_precmd` re-sets
  `PROMPT` wholesale, and is idempotent for the box where `PROMPT` is static and would otherwise
  grow one mark per prompt. `45-plugins.zsh` carries the same mark on the transient prompt:
  collapsing a finished prompt to `❖` redraws that line too, and scrollback is exactly what
  `previous-prompt` jumps _through_.

  Only `A` and `C` are marks tmux documents a dependence on, so that is the subset;
  `D;<exit>` is emitted anyway because it is free from the exit code already captured and is
  what non-tmux OSC 133 consumers read for per-command status. `C`/`D` stay hook output — being
  cleared costs them nothing, since nothing reads them back off the grid. The marks **stand
  down** in two places: under Ghostty's own shell integration, but only OUTSIDE tmux —
  `GHOSTTY_SHELL_FEATURES` is exported and reaches the tmux server, while Ghostty injects into
  the initial shell only, so guarding on the variable alone would have silenced the marks in
  exactly the place they are spent — and on `TERM=dumb`, which would render them as literal
  `]133;A` garbage. Fourteen behavioural cases in `scripts/test-core.sh` pin all of it.

  One premise of #391 did **not** survive measurement and is recorded here so it is not
  re-derived: that `_cmd_block_precmd` returning its last `print`'s status rather than the
  command's left `starship_precmd` reading the wrong `$?`. zsh saves and restores `$?` around
  **each** hook in `precmd_functions` — measured on 5.9, every hook sees the command's code
  regardless of what the one before it returned, a non-zero return does not stop the rest of
  the chain, and it never reaches the prompt's own `%(?..)`. The hook now returns `$ec`
  anyway, as the contract the `D;<exit>` mark is written against, but nothing was broken and
  nothing user-visible changed — including starship's error indicator, which was always
  correct. The same correction applies to the "run our precmd FIRST so `$?` is the command's"
  comment that line has carried since P12: the ordering is worth keeping for OUTPUT order,
  not for `$?`.

- **The atuin daemon's systemd path is measured, and the tail claim holds on it**
  (`dotgibson/dotfiles-core#352`). Adoption's whole justification was that the daemon owning
  the SQLite writes removes the DB-lock contention every shell and tmux pane pays, and it had
  never been measured here for want of a systemd box. `--systemd` has now run — seven times, on
  Fedora 44 under WSL2 with a real user manager, a real transient unit, glibc 2.43 and atuin
  18.19.0 — and every run passed the three checks a first real run had to: the unit stayed
  active for the whole arm, its `MainPID` owned the listening socket, and the row deltas were
  exact. On **prompt latency** — `history start` alone, the call `_atuin_preexec` blocks the
  shell on, and the only figure quotable as latency — with the history DB on a local ext4 home,
  three runs: **p50 1.55× / 1.55× / 1.60×, p95 2.50× / 2.33× / 2.17×, p99 2.91× / 3.25× /
  1.35× faster**. The median win was already known; the tail win is the part that was borrowed
  from upstream and is now measured — with the caveat the third run makes plain, that the p99
  _sign_ is stable while its _magnitude_ is not, so the tail belongs in the record as "faster
  in every run, 1.4–3.3×" rather than as a number. It agrees in direction with the one earlier
  blocking-call run (p99 improving 49–69%) — but that was **the same machine** days earlier,
  not a second host, so it is reproducibility over time and not independent corroboration.
  Total write work (`start` + `end`, which the hook backgrounds)
  improves at p50/p95 too, but its p99 remains unresolved — expected, since `end` is exactly
  where the two metrics diverge.

  **Storage backing turned out to be the confounder**, which is the part worth carrying
  forward. Same harness, same host, same day, prompt-latency p99: **tmpfs** flips sign run to
  run (2.23× slower, then 1.48× and 2.04× faster), **ext4** wins in every run (1.35–3.25×), and a
  high-latency **non-local filesystem** wins 26–43× — daemon-off p99 there is 0.8–1.1 _seconds_
  while daemon-on stays flat at ~27 ms. Without a real fsync there is barely a lock to contend
  over, so the mechanism only becomes visible where storage is slow enough for lock hold time
  to matter. That is the likeliest explanation for this repo's contradictory older figures,
  whose storage was never recorded — likeliest, not established, since nobody re-ran them. The
  harness now prints the sandbox filesystem on **every** run, not only under
  `CORE_ATBENCH_BASE`, and adds "durable storage" to the not-covered list when the DB lands on
  tmpfs, because the default sandbox lives in `/tmp` — which is precisely where the tail is
  least readable. `atuin/config.toml` records all of it, relabels the older pair-timed and
  unknown-storage tables as the weaker evidence they are, and names the cheap re-run that would
  settle the musl question (the same Alpine container with the DB on real disk). The
  `UNVALIDATED-SYSTEMD` marker is retired across the harness, `Makefile` and the suite; what
  replaces it on the user-visible surface is the caveat that outlives the runs — not bare
  metal, not a real multi-pane session, not musl on hardware, and a 9p mount is a proxy for a
  network home rather than one. The autostart spawn cost reproduced on real disk at **+42.16 ms**
  (p50), in line with the ~+41/+45 ms seen in containers.

- **The modernization floor now bans `allow-unsafe-pr-checkout`, the one input that can
  re-open a "pwn request" in this fleet.** `actions/checkout` v7 (2026-06-18) started
  refusing to check out fork-PR code under `pull_request_target` / `workflow_run` — a
  `repository:`, `ref:`, or head SHA resolving to the fork — and backported that enforcement
  on 2026-07-20 to v3.7.0/v4.4.0/v5.1.0/v6.1.0/v7.0.1. The single escape hatch is an input
  GitHub deliberately named to be easy to spot in code review and static analysis, so
  `scripts/modern-baseline.yml` now greps for it as a rule-1 banned pattern. Nothing had to
  be fixed first: the string appears nowhere, there is no `pull_request_target` in the fleet,
  and the lone `workflow_run` trigger (`sync-fanout.yml`) checks out a released tag rather
  than a fork ref — so this is purely preventative, and it fans out N-way to the OS and role
  repos that consume `lint-call.yml@v4` and friends. `dotfiles-Kali` / `dotfiles-Defense` are
  exactly the repos where someone might one day reach for `pull_request_target`. Rule 1's
  existing `grep -HnF` sweep already covers both `.github/workflows/` and
  `.github/actions/`, so no new enforcement branch was needed in `check-modern.sh`.
  Also refreshes the `banned_runners` rationale with `ubuntu-22.04`'s now-fully-published
  schedule — deprecation opens 2026-09-17, brownouts 2027-03-23/03-30/04-06/04-13, fully
  unsupported 2027-04-17 (`actions/runner-images#14254`); comment-only, the ban itself has
  been in place since it was added pre-emptively.

- **`scripts/bench-atuin-daemon.sh` — the atuin daemon's latency claim is no longer purely
  borrowed.** Adoption's whole justification is that the daemon owns the SQLite writes so
  shells stop contending for the DB lock, and that was cited from upstream, never measured
  here. The script measures the per-command pair a shell hook actually runs
  (`history start` + `history end`) under N concurrent writers sharing one seeded history
  DB, daemon off vs on, reported as p50/p95/p99 — plus the daemon-spawn cost the **first**
  command pays on the autostart path, which is unique to machines with no service manager.
  Report-only and deliberately **not** part of `make audit` (it needs a real atuin binary and
  starts a background daemon); `make bench-atuin` runs it, and it SKIPs cleanly on a box
  without atuin. It also asserts behaviourally something the hermetic suite can only take on
  faith from upstream's `settings.rs`: that atuin, with `XDG_RUNTIME_DIR` unset, binds
  exactly the socket path `_core_atuin_daemon_guard` probes.

  The harness now also covers the two paths it structurally could not, and enforces a rule
  that stops it lying. **`--systemd`** measures the systemd-unit path: `env -i` guaranteed
  `XDG_RUNTIME_DIR` was unset, so atuin's default `$XDG_RUNTIME_DIR/atuin.sock` — the Fedora
  shape, and the _other_ branch of `_core_atuin_daemon_guard`'s expression — was unreachable
  by construction. It runs the daemon from a sandbox-scoped **transient** unit
  (`systemd-run --user`), never your `atuin-daemon.service`, points `XDG_RUNTIME_DIR` at the
  sandbox so it cannot collide with a real daemon, asserts the unit's `MainPID` actually
  holds the listening socket, and **skips rather than degrades** without a user bus —
  reporting no-systemd numbers under a systemd label is the one thing the flag exists to
  prevent. _It shipped **unvalidated** — written where `systemd-run --user` could not reach a
  bus, so only its fail-closed skip path had ever executed — and has since been validated
  against a real user manager; see the entry below._ **`CORE_ATBENCH_BASE`** puts the sandbox HOME
  and history DB on a network home, with the socket deliberately decoupled onto a short local
  path — `AF_UNIX` does not work on NFS/SMB and `sun_path` caps near 108 bytes — and discloses
  the cost of that, which is that such a run no longer exercises atuin's default socket
  resolution, so the socket-agreement claim is **withdrawn** rather than weakened. And every
  arm must now prove its writes landed: the DB's row delta has to equal the samples the arm
  claims, or the arm is not reported. That is not hypothetical — with the daemon enabled and
  unreachable, atuin 18.19.0 exits 0, prints a well-formed history id, writes nothing to
  stderr and discards the entry (`atuinsh/atuin#3561`), which is the fastest table this
  script can produce for work that never happened. The check covers both halves, since
  `history end` _updates_ the row rather than inserting one and a pure row count would sail
  past a silently-discarded `end`.

- **The atuin daemon bench's fail-closed surface is now pinned by the suite**
  (`scripts/test-core.sh` Section J2). `make audit` can never run the bench itself — it needs
  a real atuin, a real zsh and a background daemon — which is precisely why the parts that
  _are_ hermetic are worth asserting: that `--help` documents every knob including the
  scope caveat a figure must be quoted with, that an unknown argument still exits 2, that a malformed
  `CORE_ATBENCH_WRITERS` or `CORE_ATBENCH_BASE` exits 2 rather than skipping (`WRITERS=0`
  otherwise makes every arm vacuously complete _and_ vacuously row-correct), and that
  `--systemd` against a stubbed busless `systemctl` skips with **no results table** — the
  no-degradation requirement expressed executably rather than asserted in prose. The
  row-count SQL is extracted from the script and _executed_ against a synthetic table, the
  same "run it, don't pattern-match it" idiom Section J uses on the example unit's `ExecStart`.

- **The guard's upstream premise is now measured weekly in CI — and the check it replaces
  could report "all clear" from an apparatus that had never written a row**
  (`dotgibson/dotfiles-core#383`).
  `_core_atuin_daemon_guard` is a workaround for one measured fact: on atuin 18.19.0, with the
  daemon enabled and its socket unreachable, `atuin history start` exits 0, prints an id, stays
  silent on stderr and **discards the entry** (`atuinsh/atuin#3561`). A persistent `precmd` hook,
  a throttled `connect(2)` on the prompt path, and a one-way degrade in every interactive shell
  across eight repos are justified by that fact alone.

  The copy-paste recipe that carried the standing re-verification **failed open**. It seeded its
  database through the unreachable-daemon path, so on a build that discards, the database was
  never created; its row count masked every failure as `0`; and before and after were therefore
  both `0`, which is the premise-holds signature. It was right by luck, not by measurement — and
  any apparatus failure at all, a missing `python3` or an unreadable DB, read the same way.
  Measuring "the row count did not go up" without first proving the apparatus _can_ write
  measures nothing.

  `scripts/verify-atuin-guard.sh` replaces it and reports **three** verdicts rather than two,
  because the third is the one that matters: `holds`, `moved`, and `unmeasurable` — the last
  meaning the apparatus could not be trusted, which is emphatically **not** good news and never
  collapses into `holds`. A daemon-**off** control arm runs first and must write exactly one row
  before any verdict is allowed. Both unreachable shapes the guard claims to catch are measured —
  an absent socket and a stale socket file left by a crashed daemon — and each is **proven**
  unreachable first, by a bounded `connect(2)` and the `/proc/net/unix` LISTEN scan, so a delta
  of zero can never rest on a socket that was quietly healthy. Exit codes are the verdict
  (`0`/`1`/`3`), which deliberately breaks this repo's skip-and-exit-0 idiom in one place: exit 0
  is a positive assertion about upstream, so a bare box must not be able to produce it.

  `.github/workflows/atuin-guard-verify.yml` runs it every Tuesday at 13:00 UTC against
  **whatever atuin upstream ships that week** — the one thing in this repo deliberately _not_
  pinned, because a pinned atuin would re-measure a version whose behaviour is already recorded
  and miss the next release, which is the one that actually costs history. That inversion is
  bounded structurally rather than by trust, in three jobs: `resolve` holds a token and verifies
  the download's checksum and GitHub build-provenance attestation but never executes a byte of it
  (`gh attestation verify` has no anonymous mode, which is what forces the split); `measure` holds
  **no** token at all and is the only job that runs upstream code, refusing to proceed unless the
  asset still hashes to the digest `resolve` attested; `report` holds `issues: write` and never
  sees the binary, consuming only an opaque base64 blob. `holds` files nothing — a bot that opens
  an issue weekly to say nothing changed gets muted.

  Review hardening, because the first cut of this got three of them wrong in ways that
  matter. The detector now measures **four** arms, not two — `{absent, stale}` x
  `{--hook, plain}` — because atuin's own `init zsh` emits
  `atuin history start --hook -- "$1"`, so the plain form is a path no shell in the fleet
  actually runs and a change scoped to hook mode could have broken every prompt while the
  detector reported `holds`. An **unreadable database mid-run is now `unmeasurable`, not
  `moved`**: `atuin_db_rows` returns `-1` on a failed read, `after - before` then goes
  negative, and the verdict block read that as "the row count changed" — the same
  apparatus-versus-upstream conflation the control arm exists to prevent, pointing the
  other way. And a history id is checked for **shape**, not merely non-emptiness: the
  premise is that the shell gets an id it can hand to `history end`, so a deprecation
  notice on stdout must not read as a pass. In the workflow, a value derived from an
  upstream file can no longer forge job outputs (a multi-line `.sha256` could append
  `ok=true` after `ok=false` and get an unattested asset measured), and a verifier that
  exits outside the documented 0/1/3 — or leaves an unparseable `verdict.json` — now fails
  the job instead of passing for a quiet week.

  A **second control arm runs last**, and it closes two holes at once. The opening control
  proves the apparatus at `t=0` only — but a database that stops being **writable** mid-run
  still **reads** fine, so the `-1` sentinel never fires, all four arms report an
  honest-looking delta of `0`, and the run reports `holds` from an apparatus that had quietly
  died. It also probes the premise the four arms structurally cannot see: the one-way degrade
  is correct only while atuin **discards** during the outage, and an atuin that **spooled**
  those entries would leave exactly the same absence behind — then flush them on the next
  successful write, landing five rows on the closing arm instead of one. That would invert the
  reasoning `zsh/00-tools.zsh` degrades on, so `> 1` is a `moved` finding and `< 1` is
  `unmeasurable`; the verdict vocabulary is unchanged, and the only new outcomes are ways to
  **not** reach `holds`. What it still cannot see is stated rather than implied: a spool only a
  live daemon would drain needs a daemon spawned to observe.

  Finally, the report no longer disclaims coverage it has. Its scope paragraph went on saying
  "`--hook` is not exercised" after the matrix was widened to four arms — in the same output as
  a reason that said "all four arms (absent/stale x hook/plain)" — and the assertion that
  should have caught it grepped for two nouns the false sentence also contained. The coverage
  claim is now **derived** from the arms that actually ran, in both renderers, because a
  hand-written one is a second copy of the matrix and the second copy is the one that rots; the
  test checks the report and the JSON from a single run for **agreement** rather than for
  keywords.

  The row-count SQL and its fail-closed `-1` now live in `scripts/lib/atuin-db.sh`, shared with
  `scripts/bench-atuin-daemon.sh`: both rest on the same claim about atuin's schema, so a forked
  copy would let one gate keep believing a model the other had already found stale.
  `zsh/00-tools.zsh` gains a machine-readable `# CORE_ATUIN_GUARD_VERIFIED_AGAINST=` anchor,
  because grepping the surrounding prose — which also names 18.16.1 — is how a detector silently
  starts comparing against the wrong version.

- **`/tool-scout` now re-checks the workarounds whose justification can expire**
  (`dotgibson/dotfiles-core#383`).
  `_core_atuin_daemon_guard` is not a preference — it is a workaround for one measured
  upstream fact (atuin 18.19.0 discards a history entry when the daemon is enabled and
  its socket is unreachable, `atuinsh/atuin#3561`), and every millisecond it spends on
  the prompt path is justified by that fact alone. Nothing was watching whether it stayed
  true: atuin is not pinned in `mise/config.toml` and has no `renovate.json` entry, so a
  version bump arrives silently on whichever machine updates first, and the behaviour has
  already changed once in the direction that makes it harder to notice (18.16.1 failed
  loudly; 18.19.0 fails silently). The routine now carries a standing re-verification list
  and the version each workaround was verified against.

  The **measurement** is deliberately not there and must not be copied back: that is what
  `scripts/verify-atuin-guard.sh` and its weekly job are for (entry above), and the recipe
  that used to live in the routine is the one that failed open. What is left is the half a
  script cannot do — compare the anchor in `zsh/00-tools.zsh` to atuin's newest release, lead
  with any open verdict issue, and weigh the remedy as an eight-repo change — plus the
  upstream questions no measurement here can reach: whether atuin still health-checks its own
  daemon under `autostart` (the guard stands down entirely there, and that is the **only**
  mitigation on Alpine and macOS), and whether it has gained a client-side buffer that would
  invert the one-way degrade. A changelog that does not mention the bug is still not evidence
  the bug is gone, so a release past the anchor is a finding in its own right.
  Re-verifications lead the report rather than competing inside the ranked shortlist, and
  "nothing is due" must be said out loud, since silence reads the same as forgetting.

### Fixed

- **Three latent faults in `scripts/verify-atuin-guard.sh`**, each harmless while nothing
  spawned and each load-bearing once something does (`dotgibson/dotfiles-core#402`). `run_one`
  captured stdout with `$( )`, which blocks on **pipe EOF rather than child exit** — a client
  that daemonized without reopening stdio would have hung the arm forever, and `timeout` could
  not have cut it, since it signals only its direct child. A hit bound rendered as a **finding**:
  `rc 124` reached the verdict block as "exit code is 124, was 0" and reported an apparatus limit
  as `moved`; it is now `unmeasurable` with a named reason. And `AT_ENV` was assigned inside
  `measure()`, so under `set -u` any trap reading it after an early return died exactly when
  cleanup mattered most.

- **`core-doctor` was silently blind to twelve tools Core already detects.** `00-tools.zsh`
  probes 38 binaries into `HAVE_*` flags, but the health report only ever knew about 29 —
  **`ast-grep`, `difft`, `gping`, `hyperfine`, `jj`, `jnv`, `ouch`, `shellcheck`, `shfmt`,
  `tldr`, `uv`, `viddy`** were detected and then reported by neither the human report nor
  `--json`. Every one of them had been adopted without touching the doctor, over several
  releases, and nothing caught it. All twelve are now reported.

  **The two inventories are one inventory.** `groups` (human) and `alltools` (`--json`) were
  hand-synced literals; both now derive from a single `_CORE_DOCTOR_GROUPS` definition, so
  they cannot disagree by construction. The parity test is kept as the guard against a
  second literal reappearing. A new test closes the gap parity structurally cannot see — it
  reads the `_have` lines out of `zsh/00-tools.zsh` and requires the inventory to cover
  them, so a future adoption that skips the doctor fails the suite by name. (Direction is
  one-way on purpose: `op` has no `HAVE_OP`, and `fd`/`bat` are set from `FD_BIN`/`BAT_BIN`
  after resolving `fdfind`/`batcat`.) The group definition now carries the membership rule,
  so additions land somewhere defensible instead of at the end.

  **The legend was scoped to what is true.** It read `✗ falls back to classic`, which held
  when the report was mostly command replacements. Most of the inventory is now opt-in
  tooling that shadows nothing — there is no classic `ast-grep` or `jj` — so it now reads
  `✗ absent; the replacements below fall back to the classic command`. The terminal browser
  stays deliberately absent from the report: `BROWSER_BIN` picks from w3m/lynx/links2/links/
  elinks, so a fixed `w3m` row would read ✗ on a box running lynx perfectly well.
  (`zsh/30-functions.zsh`, `scripts/test-core.sh`)

- **`core-doctor`'s install hint advertised a paste-ready command that could not run.** It
  printed `<manager> <every missing tool>` as one line — `sudo dnf install rg lnav …`. But
  apt/dnf/zypper/pacman all abort the **whole transaction** on a single unresolvable name,
  and unresolvable names are the common case here, not the edge: these are **command**
  names, while the package is frequently called something else (`rg`=`ripgrep`,
  `delta`=`git-delta`, `fd`=`fd-find` on Debian, `dust`=`du-dust`, `yq`=`go-yq`,
  `op`=`1password-cli`), and several tools are not packaged at all on some targets (`sesh`
  anywhere, `watchexec` on Fedora/Kali, `carapace` and `yazi` on Kali). So one bad entry
  silently blocked the good ones — `sudo dnf install rg` alone already failed.

  At least 12 of the inventory names break the line on some box, which is why this is not
  fixed with an exclusion list; and the alternative, a per-distro command→package map, is a
  rot-prone duplicate of `PORTING-MATRIX.md`. The hint now prints the missing tools **as
  names**, states that they are command names and that packages differ, gives the manager
  verb as a per-tool template (`sudo dnf install <pkg>`), and points at the matrix for the
  authoritative name. A new test asserts the template form is present and that the verb is
  never followed by a real tool name, so the batch form cannot come back.
  (`zsh/30-functions.zsh`, `scripts/test-core.sh`)

- **`core-doctor -v` printed `_v=0.26.1` garbage instead of version annotations — the flag
  never worked.** `local _v` sat inside the per-tool loop in `_core_doctor_render`, and zsh
  prints `name=value` when `local` re-declares a parameter that already holds one
  (`TYPESET_SILENT` is off, including under `emulate -L zsh`). So the first tool annotated
  its `✓` correctly and **every tool after it emitted a bare `_v=…` line into the report**,
  which is why the leak needs two present tools to show up at all. Declaring `_v` once
  alongside `gi`/`tool`/`line` fixes it; the assignment inside the loop is unchanged.

  This shipped broken and survived because **nothing drove the `-v` path** — the suite only
  asserted that the default render emits a group heading and that `--json` carries its
  top-level keys. There is now a hermetic case that stubs `_core_have` plus two shadowing
  tool functions and asserts both that versions render and that no `_v=` line appears. It
  uses **two** tools deliberately: a single-tool version of the same test passes against the
  unfixed code and would have guarded nothing. (`zsh/30-functions.zsh`,
  `scripts/test-core.sh`)

- **A timed-out package probe was logged as "0 upgradable" — an up-to-date box — instead of
  "unknown"** (`dotgibson/dotfiles-core#380`). Every arm of the maint runner's upgradable-count
  chain was `count=$(_to "$MAINT_PKGCOUNT_TIMEOUT" <mgr> | grep -c …)`, and that shape cannot
  tell the two apart: when `timeout` SIGTERMs a stalled manager there is no output, `grep -c`
  prints `0`, and grep's non-zero status — the pipeline's, since it is the last stage — is
  discarded by the assignment. So the `count=-1` "we don't know" sentinel was bypassed on
  precisely the failure the timeout had been added to survive (a mirror that accepts the
  connection and then stalls), and the daily log asserted the box was current when nothing
  had been measured. Counting now goes through a `_pkgcount` helper that captures first and
  gates on **how the probe died** — 124, the GNU/`gtimeout` expiry status, or `>=128`, killed
  by a signal — rather than on the manager's status. That second arm is not belt-and-braces:
  **BusyBox `timeout` reports its SIGTERM as 143, not as 124**, so a 124-only gate was green
  on every leg of the CI matrix except Alpine, where it still logged a stalled manager as `0`.
  Gating on the manager's status instead would have been wrong in the other direction, because
  these managers use exit status to mean things: `dnf check-update` exits 100 when updates
  **exist**, `pacman -Qu` and `checkupdates` exit non-zero when there are **none**, so a general
  non-zero gate would have reported "unknown" on the healthy path. The `pacman -Qu` arm stays
  unwrapped and counted directly: it reads the local DB, cannot stall, and its `0` is real. The
  log line now says `count UNAVAILABLE` with the bound that was exceeded, instead of printing
  the sentinel as `-1 upgradable`. The nudge was never affected either way — it needs a positive
  count — so this was a log-and-cache honesty defect, which is the whole reason the sentinel
  exists. Two new tests cover it: one drives the real `timeout` against a manager that stalls
  (the pre-existing case stubs `_to` away by design) and reports the observed status, and one
  pins the BusyBox spelling on every host rather than only on the Alpine leg.

- **The `up` nudge's cache could still be written malformed by the shell that claims the
  throttle slot** (`dotgibson/dotfiles-core#380`). The writer-side normalisation added with the
  reader-side quoting set `count` to **empty** on a fresh box, and the claim-slot write then
  persisted that empty value — producing exactly the `"\n<epoch>"` file the fix was supposed to
  prevent, whose unquoted `(f)` split slides the epoch into the count slot and prints
  "1786128391 updates available". Only the quoted `"${(@f)…}"` read was actually holding the
  line. It now normalises to the `-1` sentinel, so the cache is well-formed at rest: it reads
  back cleanly, `_pkgup_notice`'s `<1->` gate rejects it, and the nudge stays silent until the
  backgrounded refresh lands a real number. The comments claiming the race was closed from both
  ends now describe what the code does.

- **`ux_spin` could take down a `set -euo pipefail` caller after its animation loop, and went
  silent when its busy-spin guard fired** (`dotgibson/dotfiles-core#380`). The loop body was
  normalised (`|| :`) on the ground that this library is _sourced_ — `bootstrap.sh` runs under
  `set -euo pipefail` — but every statement after `done` was still bare. A failed cursor-restore
  `printf` therefore aborted the caller with the cursor still hidden and the wrapped child still
  running: the identical end state documented for the unnormalised `sleep`. A failure in either
  result branch aborted between `wait` and `rm -f`, leaking the mktemp file. All of them are
  normalised now; `rc` is captured and returned explicitly, so nothing the caller sees changed.
  Separately, both spinners now leave one **static `(still running…)` frame** when the busy-spin
  guard trips. `ux_spin` cleared the line before the blocking `wait`, so a long command on a box
  with a broken pacing primitive showed _nothing at all_ for the rest of the run —
  indistinguishable from the hang the elapsed-time readout exists to rule out — while
  `_core_spin` left a frozen glyph, which reads as "wedged". The wording, not the glyph, is what
  distinguishes "the animation gave up" from "the command did"; the glyph itself comes from the
  existing frame set, so the non-UTF-8 fallback is honoured rather than a hardcoded braille cell.
  The two mirrors agree again.

- **`bench-atuin-daemon.sh` started the daemon with a spelling the shipped unit deliberately
  probes for** (`dotgibson/dotfiles-core#380`). Both starters ran `atuin daemon start`
  unconditionally, while `examples/atuin-daemon.service` goes to real trouble to ask the binary
  which spelling it has, because the subcommand does not exist on older builds. The bench failed
  closed there — socket never appears, ON arm dropped, no wrong number printed — but the
  diagnostic blamed the daemon rather than the spelling, on exactly the machines most likely to
  hit it. The bench now runs the same probe once at startup and reuses the answer in both the
  plain and `--systemd` paths. `daemon stop` in the teardown is left alone on purpose: it is
  already best-effort and the `kill` below it is what actually stops the process.

- **The weekly `fleet-drift` sweep reported the fleet's ordinary state as a failure.** The
  sweep anchors to the latest **released** Core tag — deliberately, to avoid a false
  "BEHIND by N" on every unreleased commit — but `make sync` has never fanned out from a tag:
  `sync-core.sh` resolves `git ls-remote <remote> main` and vendors the branch **tip**, which
  is why the `core_tag` it stamps looks like `v4.9.3-56-g44a44fc`. Those two facts contradict
  each other on every day between releases. `_classify` treated anything not byte-identical to
  the reference as drift, so a single sync in an unreleased week put all eight Unix repos at
  "AHEAD by N", exit 1, a red run and a filed issue — while printing "run `make sync`", the
  one action guaranteed to push them further ahead. Green was only ever the accident of the
  fleet happening to sit exactly on a tag commit.

  A recorded commit ahead of the reference **and** an ancestor of `origin/main` (falling back
  to `main`) now reads as current: it carries newer Core off the released lineage, the
  opposite of the staleness this dashboard exists to find. The tolerance is deliberately
  narrow — ahead but **not** on main means the repo was synced from something that is not
  Core's release lineage, and still fails, as do behind, diverged, and a marker this clone
  cannot measure. With no mainline ref resolvable at all it fails closed and says so rather
  than green-lighting a lineage it could not check. This is the same false positive `dd4f529`
  fixed for `dotfiles-Windows` in `_classify_subtree`; the Unix repos had carried it since.

  Two things that made the red run hard to read are fixed with it. The header printed the
  reference's **sha** beside the **current branch** — `Fleet drift vs Core f95fc2b88218
  (main)` — so a sweep anchored to `v4.9.3` looked like a comparison against main's tip; it
  now names what was actually resolved. And `make sync` is advised only for repos that
  genuinely lag, since it would overwrite an off-lineage marker rather than reconcile it.
  `scripts/test-core.sh` now drives the classifier hermetically against a throwaway Core —
  a tag, commits past it, and an off-main commit — pinning every verdict, including that real
  staleness still fails.

  Green is not the same as finished, so ahead-on-main rows get their **own** verdict rather
  than a plain `✓`: a yellow `•`, plus a closing `N repo(s) carrying UNRELEASED Core` tally
  that prints even under `--quiet`. That tally — not the exit code — is now where "the fleet
  is running Core newer than any release" lives. It is a state that is fine to run and wrong
  to leave indefinitely, and flattening it into the same green as a properly pinned fleet
  would have traded one bad signal for a missing one. The fix it names is a release, not a
  sync.

- **`--strict` printed a red row and still exited 0.** It is documented — in the header and
  in `Exit:` — to turn a not-checked-out repo from a skip into a failure, and it did bump the
  counter and print red, but it never set the drift flag, so the script returned success and
  every caller read the run as clean. A repo that was never cloned is now drift; it is
  deliberately **not** counted as stale, because `make sync` cannot repair a repo that isn't
  there, and the closing advice no longer offers a recipe that would not work.

- **An unresolvable `--ref` was silently answered with a different question.** `--ref
  nosuchref` fell through the resolution ladder to `origin/main` and reported against it,
  while the banner still named `nosuchref` — the same class of mislabel as the header bug
  above, and worse, because the caller had been explicit. The fallback ladder exists for the
  _default_ path (no tags yet, or a clone too shallow to reach one); an explicit ref that
  does not resolve is now a usage error (exit 2).

- **Six documents still described a bot deleted a month earlier — including the routine whose
  job is to watch it.** Core retired `.github/dependabot.yml` when the fleet moved to the
  shared Renovate preset in v3.2.0, but the prose never followed.
  `.claude/commands/freshness-triage.md` told the triage routine to expect `dependabot.yml`
  PRs, while `scripts/freshness-dashboard.sh` was already counting `author:app/renovate` — so
  the routine was briefed to hunt for an author that can never appear, in the same repo whose
  dashboard knew better. `CONTRIBUTING.md` sent contributors to `dependabot.yml` for the
  commit-prefix convention, a file that has not existed since v3.2.0. The rest were comments
  in `freshness.yml`, `claude-routines.yml`, and `update-plugins.sh` explaining the freshness
  bot's reason for existing by contrast with the wrong bot. All six now name Renovate, and
  those that pointed at a config file point at `renovate.json`; the triage brief — the one
  document that has to act on the answer — additionally carries the `ci(deps):` prefix and the
  `app/renovate` author signature a run should look for, which the passing mentions elsewhere
  do not need. The routine brief additionally gains what #377's own caveat exposed: Renovate
  parks bumps on a **Dependency Dashboard** issue that opens no PR, so an empty PR queue is
  not an empty bump queue — and since reading it needs `gh issue list`, outside this command's
  `allowed-tools`, the brief now says to report the dashboard as unchecked rather than
  conclude "nothing to triage".

  `Makefile`'s `update-hooks` help was corrected differently, by **deletion**: it justified
  the target with "dependabot has no pre-commit ecosystem", and Renovate _does_ ship a
  `pre-commit` manager. The dependency dashboard (#186) settles it — Renovate detects only
  `devcontainer`, `github-actions`, `mise`, and `renovate-config` here, so the target is still
  load-bearing — but that is a fact about the org preset's current configuration, living in
  `dotgibson/.github`, and encoding it in a help string is how the previous claim rotted. The
  line now states what the target does and nothing about which bot doesn't do it.

  Historical `CHANGELOG.md` entries are left alone — they were true when written.

- **A shell that outlived atuin's daemon recorded nothing, silently, for the rest of its
  life.** `_core_atuin_daemon_guard` was a startup probe: one `zsocket` connect at the first
  `precmd`, then it unhooked itself. That covers a shell started _after_ the daemon went away
  and nothing else — so a long-lived tmux pane whose daemon stopped underneath it (the ordinary
  case under systemd `Linger=no`, where the user daemon dies with the last login session) kept
  handing every command to a socket nobody was listening on. atuin 18.19.0 neither falls back
  nor complains: `atuin history start` exits 0, prints a well-formed history id, writes nothing
  to stderr and **discards the entry** (`atuinsh/atuin#3561` — and note the direction of travel,
  since 18.16.1 at least failed loudly). A day of history, gone, with no symptom until you go
  looking for a command you know you ran.

  The guard is now a **watchdog**. It stays on `precmd` and re-probes, throttled to at most one
  `connect(2)` every 60 seconds; when the window has not elapsed the per-prompt cost is a single
  arithmetic expression over three integers — no fork, no syscall — which is the honest version
  of this layer's startup-cost discipline. What that discipline forbids on the prompt path is an
  _unconditional_ syscall, not the compare that decides whether to make one. The probe itself
  measures ~0.06–0.10 ms against a local unix socket, so the window could be far shorter; it is
  60 s because `precmd` fires per **prompt**, not per second — which already bounds the probe
  rate by how fast you type — and because the throttle's real job is the socket path that is
  _not_ local, where `connect(2)` can block with no timeout available. `CORE_ATUIN_PROBE_INTERVAL`
  is the escape hatch for such a box.

  Three properties are deliberate, and the suite now pins each. **Degradation is one-way**: the
  first failed connect disables the daemon for that shell and unhooks the guard for good. Direct
  writes always work, so a false positive — a probe landing in the shipped unit's `RestartSec=3`
  gap, say — costs only the lock relief until the next shell, whereas the opposite error costs
  the history; and during that gap atuin _is_ discarding, so degrading early is still right.
  **The warning is mid-session only**: a shell already degraded at its first prompt stays as
  silent as it has always been (nothing changed under it, and machines that simply never run the
  daemon must not learn a line of startup noise), while a shell that _had_ a working daemon and
  lost it prints one `_core_warn` line — "once" being structural, since the degrade path unhooks
  before it warns. **And the throttle fails safe**: its deadline is honoured only while it is at
  most one window away, so a backwards NTP step, a resume from suspend, or the
  `$EPOCHSECONDS`/`$SECONDS` fallback changing source mid-shell all fall through to a probe
  rather than parking the watchdog for the length of the jump. `core-doctor` now says which of
  the two degradations happened, and `core-doctor --json` grows an `atuin_daemon` object so a
  statusline can see a silently degraded shell without the user going looking.

  The prose has been corrected along with the code, because it asserted the opposite trade:
  `zsh/00-tools.zsh` claimed "it is a startup probe, NOT a watchdog" and that "re-probing every
  precmd would put a `connect(2)` in the prompt path", and `examples/atuin-daemon.service` told
  you sessions already open "keep discarding". `atuin/config.toml` and `PORTING-MATRIX.md`
  footnote ²⁰ are updated to match.

- **The spinner could peg a CPU core for the entire length of the command it was
  decorating.** `_core_spin`'s animation loop is paced entirely by `_core_nap`, and
  `_core_nap` cannot report failure: it swallows both arms (`zselect … 2>/dev/null`,
  `sleep 0.1 2>/dev/null`) and unconditionally returns 0. On a box where neither can
  actually sleep — no `zsh/zselect` module and no usable `sleep` — the 100ms tick silently
  became an unthrottled spin. Measured on the real function under a pty: **100% CPU for the
  command's full duration, versus 0% with the guard**, same wall time and same exit status
  either way. The animation is cosmetic and the `wait` is what matters, so the loop now
  detects a nap that is not pacing it (>200 iterations inside 5s, unreachable with a working
  tick) and stops _animating_ rather than stopping the command, falling through to the
  blocking wait. `lib/ux.sh`'s `ux_spin` carried the same shape around a bare `sleep 0.1`
  and gets the same guard, keeping the bash and zsh spinners the deliberate mirrors they are
  documented to be. Two things made this hard to see and are worth recording: the loop is
  unreachable without a **tty** (`[[ ! -t 2 ]]` runs the command directly, so every captured
  or piped run takes the passthrough path), and where `gum` is installed `_core_spin`
  delegates real binaries to `gum spin` — leaving the hand-rolled loop live only for
  **function** arguments, which is exactly what `up` passes it (`_pkgup_list_to`). The new
  regression test therefore drives a real pty with a function argument, and asserts on the
  iteration count (~201 guarded, six figures unguarded) rather than on CPU%, which is not
  deterministic enough for CI.

- **`/os-package-availability` cited line numbers it never read.** The macbook run on
  2026-08-09 (dotfiles-MacBook#120) filed a correct green verdict — all 76 `Brewfile`
  entries re-verified as resolving — but pointed two of its citations at the wrong
  entries: `dust` at `Brewfile:53` when `:53` is `duf`, and `gnu-sed` at `:64` when `:64`
  is `visidata`. The names were right and the packages resolve, so nothing was
  mis-diagnosed; the reference was simply to a neighbouring line. Package lists make this
  the cheapest possible error — they are dense, every entry inserted above a name shifts
  it, and neighbours look alike — and the routine's reporting rules asked for `file:line`
  without ever saying to confirm the line. The prompt now requires reading the line before
  citing it, and forbids carrying a number over from a previous run's report, inferring it
  from a nearby entry, or quoting a grep hit it has not re-checked. A green run with wrong line
  numbers is the corrosive case: it invites the reader to distrust the citations that are
  correct, which is the whole value of an availability audit.

- **`PORTING-MATRIX.md` claimed two Gentoo atoms that do not exist.** The Gentoo run of
  `/os-package-availability` on 2026-08-09 (dotfiles-Gentoo#80) returned a clean verdict for
  `install/packages.txt` — every atom in the Gentoo install list still resolves — but caught
  the matrix asserting main-tree packaging for two tools that are not in `::gentoo` at all:
  `dev-vcs/jujutsu` (row + footnote 8) and `dev-go/shfmt` (row + footnote 7). Both 404 on
  packages.gentoo.org and return nothing on search. Re-verification went one step further than
  the report and closed off the obvious fallback: **neither is in GURU either** — the overlay
  carries no `dev-vcs/jj`, and the `dev-go/shfmt` atom exists in no repository anywhere (the
  third-party overlays that ship shfmt call it `dev-util/shfmt`). Both Gentoo cells now render
  as `cargo³`/`go³`, the footnote-3 convention already used for `ouch`, `ast-grep`, and `sesh`,
  and footnotes 7 and 8 say plainly that the tool is absent from the main tree **and** the
  overlay rather than naming an atom a reader would try to `emerge`. Footnote 7 had hedged
  ("verify the exact package on first stamp"), which is exactly the hedge that lets a wrong
  atom survive a review — a name in the Gentoo column reads as a promise that `emerge <atom>`
  works, and for these two it never did. No OS repo's `packages.txt` needed an edit: jj and
  shfmt are opt-in/dev tooling and were already carried in none of them, so nothing was ever
  installing the wrong name.

  The same pass caught a second, older error in footnote 8 that had nothing to do with Gentoo:
  the cargo fallback was written as `cargo install jujutsu`, and **`jujutsu` is not the crate
  that installs `jj`.** It is a stub pinned at 0.7.2 whose own description reads "You don't want
  this crate - you want the `jj-cli` crate"; the real one is `jj-cli` (0.44.0). That fallback is
  what the Debian/Kali `cargo³` cell points at too, so the one wrong crate name had been the
  documented install route for every unpackaged distro, not just the two rows this change
  touches. It now reads `cargo install --locked jj-cli`, matching the `--locked` form the OS
  bootstraps already use for their own cargo builds.

- **Every atuin bench figure ever produced was labelled latency and was not.** The harness
  timed `history start` and `history end` in one span, but a shell hook does not pay for the
  two calls the same way: atuin's `_atuin_preexec` takes `start` in a command substitution,
  so the prompt blocks on it, while `_atuin_precmd` fires `end` into a detached background
  subshell — `(atuin history end ... &)` — where it costs the box and nothing else. Timing
  the pair measures total write work; only `start` is time a human waits. The writer now
  takes a timestamp **between** the two calls (both metrics from one pass, so the tables are
  strictly comparable — same samples, same contention) and the results print as two clearly
  separated tables, latency first, each saying what it may be quoted for.

  This is not a presentational fix: **it puts the far-tail conclusion back in question.** The
  recorded finding that the daemon trades frequent small waits for rarer, larger stalls comes
  entirely from pair-timed runs, while the one measurement that timed only the blocking call
  (Fedora 44 under WSL2, systemd unit) found p99 improving 49–69%. `end` is precisely where
  the two would diverge — with the daemon off it is the slower call, and with it on they
  equalise. `atuin/config.toml` and `zsh/00-tools.zsh` now relabel their figures as total
  write work and mark the tail question **open in both directions** rather than settled
  against the daemon; the p50/p95 win is unaffected and still holds on every host tried.
  No new measurements are claimed here — this change makes the re-measurement possible.

  The parser is the risky half and is tested accordingly (`test-core.sh` Section J2): the
  previous one split each file on all whitespace, so two-column input would have flattened
  into one distribution of double the length — a table that looks completely normal and is
  completely wrong. The stats block is now extracted and _executed_ against synthetic samples
  whose two columns differ, pinning that each table reports its own, and a malformed sample
  line refuses the arm instead of being coerced.

- **The atuin bench dropped an arm roughly one run in eight, and the reason looked like
  atuin misbehaving under contention.** `history start` is not the only write a command
  makes: `meta.db` (and the `key` beside it) are created lazily by the first `history end`.
  The warmup in `db_reset` ran `history start` _alone_, so `meta.db` did not exist when the
  writers launched and all N of them raced to create and migrate it on their first
  `history end` — one losing on `UNIQUE constraint failed: _sqlx_migrations.version`, which
  aborted that writer at iteration 1 and cost the whole arm. It was always the _first_ arm,
  because `meta.db` survived a `db_reset` that only ever removed `history.db`. The warmup now
  runs a complete `start`+`end` pair, and the snapshot/restore covers the whole data
  directory rather than one file — which also delivers what the old comment already claimed:
  `records.db` grew monotonically across arms before this, so each arm was measured against a
  bigger sync store than the one before it, exactly the variable being controlled for.

- **The bench could never detect musl, and mislabelled the one run where that mattered.**
  `ldd --version 2>&1 | grep -qi musl` looks right but cannot work under the `set -o pipefail`
  in force at the top of the script: musl's `ldd` exits non-zero after printing its banner, so
  the pipeline fails even though `grep` matched. Every musl run therefore reported
  `unknown libc` _and_ went on to list musl among the things it had not covered — on the one
  run where that was false, and on the cheapest of the remaining gaps. Now the output is
  captured and matched as a string.

- **The showcase was never told a release had happened, and had not been since the
  notification was written.** `notify-web.yml` listens for `release: published`, but the
  Release is created by `release.yml` running `gh release create` under the built-in
  `GITHUB_TOKEN` — and an event raised by `GITHUB_TOKEN` never starts another workflow run
  (the same recursion guard that stops a `GITHUB_TOKEN` push from firing `pull_request`).
  So the Release published, the event was inert, and dotfiles-web's
  `repository_dispatch: types: [core-release]` received not one POST in its lifetime.
  Nothing about the dispatch itself was broken — right event type, right target, working
  token — which is why it read as healthy from both ends. User-visible downstream: the
  site's only remaining refresh was a Tuesday cron, so its committed `generated.json` sat
  two releases behind (v4.7.1 against Core's 4.9.3) and every published install command was
  pinned to a stale `--branch`. `release.yml` now dispatches `core-release` itself from a
  job after `publish`, where no guard applies; `notify-web-call.yml` grew an `event_type`
  input (default `refresh`, so the `@v4` callers across the fleet are untouched), validated
  against an allowlist because a typo'd type POSTs 204 and triggers nothing. That job is
  `best_effort`, because `sync-fanout` gates on this workflow's overall conclusion and a
  failed notification must never be able to stop a published tag from reaching the OS
  repos. `notify-web.yml` keeps its `release:` trigger for a Release published by hand from
  the UI, and now documents the trap so the dead path isn't mistaken for the live one.

- **`/os-package-availability` could query a single release and still return "Clean" —
  the one verdict the routine exists to rule out.** Step 1 said to confirm each name
  "still exists in this distro's repos" without ever saying _which_ releases to look in,
  so a run against one release could not distinguish "present everywhere" from "already
  dropped in the next release" — and would report a version read from stable as evidence
  the name resolves, full stop. That is not hypothetical: the Fedora run filed a Clean
  verdict while `tealdeer` and `procs` had both gone orphan and neither had been rebuilt
  for rawhide/F45, quoting their F43/F44 versions as passes. Both still install today and
  break on the F45 upgrade, which is exactly the early warning this audit is for. The
  routine now picks targets by **release model**: versioned distros (Fedora, openSUSE Leap,
  Alpine stable) need every currently-supported stable release plus that distro's own
  development branch where one exists, while rolling targets (Arch, Gentoo, Homebrew, Kali,
  Tumbleweed) have a single current repo that is itself full coverage. It also requires
  every quoted version to name the release it came from; classifies "in stable, gone from
  that distro's development branch" as **Drifted** rather than a pass; and requires a Clean
  verdict to state its release coverage and reconcile N-checked against N-in-list, so a
  partial run has to call itself partial.
- **`claude-routines-call.yml` ran the routines from a frozen `v3` checkout.** The reusable
  workflow checks out dotfiles-core to get the routine prompt, `PORTING-MATRIX.md` and the
  pinned CLI, and pinned that checkout to `ref: v3` — directly under a comment reading
  "Core@v4 at ROOT … (v4 = the current major, matching the `@v4` callers)". `v3` is frozen
  at v3.9.0 (2026-07-19) while the line has since reached v4.9.3, and the routine prompt
  differs between the two, so every scheduled run has been executing the v3.9.0 prompt no
  matter what shipped in v4 — including the fix above. Bumped to `v4` so the callers and the
  content they run agree.
- **`lint-call.yml` and `auto-tag-call.yml` ran the fleet from the same frozen `v3`
  checkout.** The defect above was not confined to the routines workflow — these two
  reusable workflows carry it in the three remaining pins, and the lint one is the
  consequential half. Both check out dotfiles-core for the pinned
  `scripts/tool-versions.env`, the `setup-core-tools` composite and the release scripts, and
  pinned that checkout to `ref: v3` while every comment beside them declared v4
  (`lint-call.yml:57` reads "v4 = the current major, matching the `@v4` callers"; the
  auto-tag step said "pin to the SAME major line callers pin this workflow to (@v4)" and
  then pinned v3 in the same breath). So every OS repo's lint gate has been running v3.9.0's
  pinned tools — shellcheck 0.10.0, shfmt 3.8.0, actionlint 1.7.8 — while Core lints itself
  with 0.11.0 / 3.13.1 / 1.7.12: the fleet was held to a weaker gate than the repo defining
  it. Bumped all three pins to the moving `v4` alias.

  Measured before bumping, against `dotfiles-Fedora` with the gate's exact
  `SHELLCHECK_OPTS` and file selection: shellcheck 0.10.0 → 0.11.0 is **byte-identical**
  (exit 0, no findings either way) and actionlint 1.7.8 → 1.7.12 likewise. `shfmt` is
  advisory by construction — the step wraps it in an `if/else` that swallows the drift exit
  rather than setting `continue-on-error` (`lint-call.yml:156-170`), so new formatting
  opinions in 3.13.1 can only warn; note that a genuine shfmt _install_ failure still reds
  the step, which is the point of not using `continue-on-error`. So the bump is expected to
  be a no-op for the blocking legs rather than a new-findings event — verified on one repo,
  not all eight.

- **`up` and the maintenance runner could hang forever, invisibly, on a package manager
  that stopped to ask a question.** dnf5 verifies repository _metadata_ signatures against a
  per-repo, **per-user** keyring (`<cachedir>/<repo>/pubring`), not the rpm keyring. So a
  repo with `repo_gpgcheck=1` whose signing key only ever reached root's keyring — the
  ordinary outcome of a bootstrap that runs `sudo rpm --import` and then `sudo dnf install`
  — re-prompts to import it on every **non-root** `--refresh`, and since a declined import
  is never persisted, it prompts again forever. Every probe that hits this runs with stdout
  captured by `$(...)` and stderr sent to `/dev/null`, so the question is invisible while it
  holds the terminal. `_pkgup_count`/`_pkgup_list` were documented as backgrounded, where
  zsh's `nomonitor` hands a job `/dev/null` stdin and the shape was accidentally safe — but
  `up` calls `_pkgup_refresh` in the **foreground** once the upgrade finishes, so it inherits
  the terminal and `up` prints `Complete!` and then never returns. The runner's
  upgradable-count block is not a `step()`, so it had no stdin discipline at all and the run
  stopped dead after the last ✓ with no error. Pin stdin so the probes cannot be prompted
  regardless of caller, give `step()` the same treatment — which closes the identical
  exposure on the git-credential and tpm paths — and bound the count probe with `_to`
  (`MAINT_PKGCOUNT_TIMEOUT`, default 180s) for the separate case of a mirror that accepts
  the connection and then stalls. The redirect goes on the `case`/`fi`, **not** the function
  definition: in zsh `f() { … } </dev/null` binds at definition time and does nothing at
  call time, so it reads as correct in review while fixing nothing. Regression tests assert
  the probes cannot consume the _caller's_ stdin rather than asserting they don't hang —
  same property, but it fails instead of wedging a suite that has no timeout anywhere.

- **`examples/atuin-daemon.service` started the daemon by a deprecated name, and that
  failure mode is silent.** `ExecStart` ran `atuin daemon`; 18.19.0 warns on every start and
  points at `atuin daemon start`. On its own that is cosmetic — but with the daemon enabled
  and unreachable, atuin exits 0, prints a well-formed history id, writes nothing to stderr
  and discards the entry. So the day the old spelling is removed, `ExecStart` fails and
  `Restart=on-failure`/`RestartSec=3` retries it forever with nothing ever listening.
  Scoped honestly: a Core shell started _after_ that is fine — `_core_atuin_daemon_guard`
  probes the socket at its first `precmd`, finds nothing, and forces the daemon off so atuin
  writes SQLite directly. The exposure is shells that had already completed that one-shot
  probe while the daemon was alive, and anyone consuming this unit _without_ Core's guard —
  which, `examples/` being a copy-paste target, is precisely who it is written for.
  The unit now asks the binary which spelling it has and execs that, because the subcommand
  does not exist on older atuin and this file is copy-pasted onto machines Core does not
  control. Two things that do _not_ work and are pinned by tests: `exec A || exec B` (once
  `exec` succeeds the process is replaced, so a non-zero exit can never reach the `||`), and
  probing with `atuin daemon --help` (exits 0 on both spellings, so it proves nothing —
  which is why `dotfiles-Fedora`'s existing capability probe would have installed a unit the
  binary rejects). New `scripts/test-core.sh` Section J covers the file, including
  `systemd-analyze verify`; note it remains classified repo-meta by `ci-classify`, so an
  examples-only change still gates nothing.

- **`exec zsh` — the documented first step after a bootstrap — dropped you into
  `zsh-newuser-install` with no Core loaded.** The managed `~/.zshrc` _exports_
  `ZDOTDIR=$XDG_CONFIG_HOME/zsh`, but nothing ever created `$ZDOTDIR/.zshrc`. The first
  shell was fine (`ZDOTDIR` unset ⇒ zsh reads `~/.zshrc`); every zsh started from inside it
  inherited the export, found none of `.zshenv`/`.zprofile`/`.zshrc`/`.zlogin` there, and was
  treated as a brand-new user. The wizard was the visible half — the real damage was a shell
  with no fragments, no plugins, no prompt. On a non-TTY there was no wizard at all, just a
  silently empty shell; and the wizard's own option `(0)` writes a comment-only
  `$ZDOTDIR/.zshrc`, permanently suppressing it while permanently keeping the shell empty.
  `blib_write_zshrc_loader` now seeds `$ZDOTDIR/.zshrc` as a link to `~/.zshrc` (via
  `blib_link`, so it backs up, is dry-run aware, and is idempotent) — including on the
  already-managed early-return path, so boxes bootstrapped before this fix are reconciled on
  the next run rather than only on a fresh write. Note `scripts/bench-core.sh` and
  `scripts/new-os-repo.sh` already built the coherent `$ZDOTDIR` model, which is exactly why
  the suite never caught this; Section I of `scripts/test-core.sh` now asserts it.

- **The update nudge could report a Unix timestamp as the package count** — e.g.
  `󰚰 1786128391 updates available`. `_PKGUP_CACHE` is positional (`"<count>\n<epoch>"`) but
  both readers split it with an _unquoted_ `${(f)…}`, and zsh drops empty fields from an
  unquoted expansion. The empty count is not something `_pkgup_refresh` can write — it
  normalises an empty result to `-1`. It comes from the startup hook itself: on the first
  shell of a fresh box there is no cache, so the count it reads is empty, and claiming the
  throttle slot persists that empty field alongside a fresh timestamp while the background
  refresh is still in flight. Read back unquoted, the leading empty field vanishes and the
  epoch shifts into the count slot — where it passes the `<1->` positive-integer check and
  renders. From there it is self-sustaining: `last` shifts to empty ⇒ `0`, which defeats the
  once-a-day throttle so the check re-fires on _every_ shell, each one rewriting the bogus
  count. Both reads are now quoted (`"${(@f)…}"`), and a non-numeric count is discarded
  before it can be written back, closing the race from the writer side too.

- **`zsh/00-tools.zsh` documented an atuin fallback that does not exist.** The comment on
  `_core_atuin_daemon_guard` said an absent or stale daemon socket makes "every atuin call
  pay a failed connect and an error" and that "atuin then writes SQLite directly" — so a
  missing daemon "must cost latency". Measured against atuin 18.19.0, none of that holds:
  `atuin history start` exits 0, prints a well-formed history id, writes nothing to stderr,
  and **discards the entry** (verified for an absent socket, a stale socket file, and with
  and without `--hook`; the daemon-off control writes every row). The guard is therefore
  data-loss prevention, not a latency optimisation, and the "startup probe, not a watchdog"
  caveat is correspondingly sharper: a daemon that dies mid-session costs that shell every
  subsequent command, unrecorded and unannounced. Comment corrected; no behaviour change.

- **`core.manifest` advertised a keybinding that does not exist.** Its `zsh/35-fzf.zsh`
  stanza named `Ctrl-F/R` for the fzf widgets; `zsh/40-bindings.zsh` binds `^T`, and there is
  no `^F` binding anywhere in Core — `PARITY.md` even records that zsh moved off `Ctrl+F`.
  A one-token error, but in the file the system calls its contract, vendored verbatim into
  eight repos, so it misinformed eight copies at once. Now `Ctrl-T/R`.

- **Three `PORTING-MATRIX.md` footnotes asserted "nothing installs this" against repos that
  do**, and two of them contradicted each other:

  - ¹⁷ said `jnv` is in no `Brewfile`; `dotfiles-MacBook/Brewfile` carries it. Scoped to
    Linux, with macOS named as the exception.
  - ¹⁹ said no repo installs `gping`; the same `Brewfile` carries it. Same scoping.
  - ¹² listed `gping` among Gentoo's GURU-overlay atoms while ¹⁹ said nothing installs it.
    ¹⁹ was right: `gping` appears nowhere in `dotfiles-Gentoo`'s `guru_install` list, its
    `packages.txt`, or its `bootstrap.sh` at all. Dropped from ¹².

- **The matrix sent Kali to `mise`/`cargo` for `tree-sitter-cli`, which it apt-installs.**
  `dotfiles-Kali/install/packages.txt` carries the plain apt name and its `bootstrap.sh` has
  no tree-sitter installer, so the ³ footnote pointed at a path the repo never takes.

- **Footnote ⁹ named an AUR package that does not exist.** It said sesh is "Packaged in the
  AUR (`sesh`)"; the AUR has no package under that bare name. The real one is `sesh-bin`,
  which declares `provides`/`conflicts` on `sesh` — so `paru -S sesh` resolves anyway, which
  is precisely why the wrong name read as correct. Confirmed against the AUR RPC: an `info`
  lookup for `sesh` returns nothing, and a name search returns eight packages, none of them a
  bare `sesh`, ruling out a source-build entry alongside `sesh-bin`. The Arch cell on the
  sesh row still reads `AUR`, which was always accurate; only the footnote was wrong.

- **`lib/bootstrap-lib.sh` still gave the atuin advice v4.9.3 corrected.** It told you to
  re-apply a backed-up local config "via `ATUIN_*` env" with no carve-out — the exact pattern
  that release proved does not work for the ten keys `atuin/config.toml` sets. This was the
  last surviving instance; `PORTING-MATRIX.md`, `examples/README.md` and both OS layers were
  already correct.

- **A cross-reference dangled one release after it was written.** The v4.8.0 correction note
  pointed at "the `[Unreleased]` entry on the daemon opt-in"; cutting v4.9.3 promoted that
  entry, leaving the pointer aimed at an empty section. Now names `[v4.9.3]` — the hazard of
  referring to `[Unreleased]` from a dated section at all.

- **Core told you it fans out to nine OS repos. It fans out to eight.** `scripts/os-repos.txt`
  has been the canonical fleet — and has documented `dotfiles-Windows` and `dotfiles-Debian` as
  deliberately absent — for several releases, but five comments still asserted the old count:
  `.github/workflows/release.yml`, `.github/workflows/ci.yml`, `scripts/update-nvim-plugins.sh`,
  `scripts/test-core.sh`, and `scripts/audit-core.sh`. `ARCHITECTURE.md` is deliberately
  **unchanged**: "one Core plus nine machine repos" counts machine repos _including_ Windows and
  is correct — the two numbers are both right in their own sentence, which is exactly why a
  find-and-replace would have broken it. (`.github/workflows/release.yml`,
  `.github/workflows/ci.yml`, `scripts/update-nvim-plugins.sh`, `scripts/test-core.sh`,
  `scripts/audit-core.sh`)

- **`gsync` was documented as an alias in a file deleted in v4.** It is a _function_ —
  `zsh/20-aliases.zsh` says so two lines above the definition, and explains why (a dotfiles path
  containing whitespace must stay one word). Three places carried the stale `zsh/aliases.zsh`
  path, a filename that has not existed since the v4 `NN-name.zsh` renumbering.
  (`core.manifest`, `zsh/completions/_gsync`, `.bin/sync-upstream.sh`)

- **`blib_link_core`'s own comments under-sold what it links.** The doc header omitted lazygit,
  jujutsu and the seeded sesh config; the `tools` group banner omitted jujutsu and atuin —
  both of which the code directly beneath it links. The complete enumeration already existed at
  the top of the file, so both now point at it as the canonical list. (`lib/bootstrap-lib.sh`)

- **Pre-v4 module names in comments that describe _current_ behaviour.** `tools.zsh`,
  `options.zsh`, `ui.zsh` and `maint.zsh` have been `00-tools.zsh`, `10-options.zsh`,
  `05-ui.zsh` and `55-maint.zsh` since v4. Note `blib_migrate_v4` deliberately **keeps** the
  unnumbered names — it exists to delete stale pre-v4 symlinks, so there the old spelling is
  the correct one. (`core.manifest`, `lib/bootstrap-lib.sh`)

- **`PORTING-MATRIX.md` promised bootstrap installs that do not exist.** The `³` marker means
  "bootstrap.sh installs it best-effort", but six cells carried it with no installer behind
  them — `ouch` and `jujutsu` on Gentoo and Kali, `ast-grep` and `shfmt` on Gentoo — verified
  against each repo's `bootstrap.sh` and `install/packages.txt`. Kali _does_ install `ast-grep`,
  so that cell keeps its `³`. A new `²¹` marker records the honest state, reusing the
  detect-only shape `jnv`¹⁷ and `gping`¹⁹ already established: **available, not installed**.
  It also covers four rows that are macOS-Brewfile-only in practice (`hyperfine`, `shellcheck`,
  `shfmt`, `ouch` — no Linux repo installs any of them), and `lazygit` on Kali, the sharpest
  case: every other Linux repo installs it, Kali installs it nowhere, and Core ships
  `alias lg='lazygit'` regardless. This is the same overclaim already corrected once for
  openSUSE. Alpine's `ouch` cell also gains the `¹⁴` testing-repo footnote every comparable
  cell already had. (`PORTING-MATRIX.md`)

- **The atuin-daemon table read as shipped state when it is mostly a recipe.** The exports are
  wired on two of the seven Core-vendoring machines the table covers (Fedora, Alpine) — now
  marked `✔`, with the other five labelled as the documented recipe and `Windows` called out as
  neither, being out of scope. The marker is per machine rather than per row, since the systemd
  row holds a wired Fedora next to four unwired ones. `Defense` is dropped from the systemd row:
  that row tells
  you to put exports in `os/<os>.zsh`, and Defense is distro-agnostic with no `os/` layer, as
  the same file says under "Repo status". The `Built:` list also omitted `Defense` entirely.
  (`PORTING-MATRIX.md`)

- **`dotfiles-Defense` is now recorded as the documented scaffold exception.** `core.manifest`
  claimed `lib/bootstrap-lib.sh` is sourced by _each_ OS repo's `bootstrap.sh`; Defense
  hand-rolls its own `link()` and `.zshrc` heredoc instead. That is deliberate — Defense is a
  role layer stacking onto an already-provisioned host, where the OS repo underneath has
  already run the scaffold — so the claim is narrowed rather than the code changed.
  (`core.manifest`, `PORTING-MATRIX.md`)

- **`README.md` billed `aliases.md` as the "full" cheat sheet.** It omits the function verbs
  `core help` indexes (`fif`, `fbr`, `maint-*`, `op*`). `core help` is the complete index and
  now says so; `aliases.md` is described as the curated companion. (`README.md`)

- **`/doc-audit` compared a release-pinned mirror against `main`, and reported a false
  positive.** `dotfiles-web`'s `porting-matrix.md` is diffed by its own CI against Core at
  `releases/latest` — the newest **release tag**, not `main`. The routine had no such
  carve-out, so it measured the page against `main` and called it "a pre-correction
  snapshot". It was not: it was byte-identical to Core at `v4.9.3` and its check was green.
  Acting on that report re-mirrored `main` into a file whose contract is the tag and turned a
  passing check red, which is how it was caught. The routine now states the reference frame
  explicitly, and that a mirror lagging `main` while matching the newest release is
  **correct, not drift**. (`.claude/commands/doc-audit.md`)

- **The `refresh` row implied Arch has a refresh alias. It deliberately does not.**
  `sudo pacman -Sy` was listed with no note, while `dotfiles-Arch`'s `os/arch.zsh` explains at
  length that there is no `-Sy` alias **on purpose** — refresh-then-install is the
  partial-upgrade footgun, so it ships `pacu` (full `-Syu`) and `pacout` (`checkupdates`,
  which never touches the sync DB). New footnote `²³` records that the cell is completeness,
  not a recommendation. (`PORTING-MATRIX.md`)

### Changed

- **`fleet-drift` now says how far behind main's tip an unreleased row still is**
  (`dotgibson/dotfiles-core#381`). `_classify` measured the recorded sha against the release
  **tag** only, and `git merge-base --is-ancestor` is reflexive at both ends — so "on
  `origin/main`" was equally true of a repo synced this morning and one synced five weeks
  ago, and both printed the identical `current (ahead of vX.Y.Z by N, on origin/main)`. A
  **stalled fan-out was therefore invisible inside a green sweep**: at the time of writing the
  whole fleet sat 56 commits past `v4.9.3` while main had moved 111 past it, and nothing in
  the report named the 55 unvendored commits. The ahead-on-main row now appends
  `, N behind its tip` when that distance is non-zero.

  **Report-only, and deliberately so.** The `current` prefix, the `•` third state, the
  `UNRELEASED` tally, `DRIFT`/`STALE`/`OFFLINEAGE` and every exit code are unchanged — a green
  run stays green. The previous entry in this file taught readers that a fleet-drift wording
  change implied a verdict change; this one does not. Re-reddening the sweep once the fleet
  drifts far enough from main was considered and rejected: that is exactly the #371 failure
  mode where the fleet's ordinary between-release state pages a human, and the threshold would
  be unjustifiable. The two numbers now read as a pair — _ahead of the tag_ says a release is
  owed, _behind its tip_ says a `make sync` is owed.

  Zero omits the clause entirely rather than printing `0 behind its tip`, which keeps an
  at-tip row byte-identical to its old wording — and makes the suite's existing `…, on main)`
  regex a live oracle for that case. `_classify_subtree` (dotfiles-Windows) deliberately gets
  nothing: its marker is re-stamped only when `nvim/` changes, so a behind-main count there
  would report a lag for every Core commit that touched anything else — the exact false-BEHIND
  that the subtree path exists to eliminate.

- **`/drift-triage` can run the sweep it is built to interpret** (`dotgibson/dotfiles-core#381`).
  The routine's own step 1 told it to run `scripts/fleet-drift.sh` — without the leading `./`
  that `Bash(./scripts/fleet-drift.sh:*)` matches, so every invocation was **denied** — and to
  pass the sibling fleet "via `--add-dir`", a Claude Code flag the script's parser rejects with
  a usage error. Neither is needed: `--root` already defaults to this repo's parent, which is
  where the fleet is checked out in CI too. The command is now spelled out literally as
  `./scripts/fleet-drift.sh --color never`.

  The consequence was not a missing section but a **wrong report**: blocked from its primary
  tool, the routine reconstructed `_classify`'s logic by hand from the `core.lock` markers,
  reached the opposite verdict from the script (red, when the sweep exits 0), and shipped it
  without a hedge. The command now forbids that explicitly — an unrun sweep is a finding to
  report, not a gap to fill in — and documents the three row states with the remediation each
  one actually takes, since a `•` unreleased row is fixed by **cutting a release**, never by
  the `make sync` the old text prescribed for everything.

- **The atuin latency question is closed, and the part that will never be measured is now
  recorded as a decision rather than a backlog** (`dotgibson/dotfiles-core#352`). The
  measurable half is measured — see the `bench-atuin-daemon.sh` entries under **Added**. The
  remaining four rows (musl on real
  hardware, a real NFS/SMB home, bare metal, a real multi-pane session) need machines this
  project does not have and will not get, so `atuin/config.toml` now states plainly that
  their rationale stays **borrowed from upstream** on purpose. The mechanism is measured;
  what is borrowed is its magnitude on hardware nobody here runs. An open issue promising
  numbers that cannot arrive is worse than a documented decision not to chase them.

  Also corrects an overclaim this changelog and `atuin/config.toml` both carried: the earlier
  systemd-unit run was described as a second, independent Fedora host corroborating the new
  figures. It is the **same machine** — Fedora 44 / kernel 6.18.33.2 (WSL2) — measured days
  apart. That is reproducibility over time, not independent corroboration, and every figure
  in the record comes from one WSL2 host. Overstating corroboration is precisely the failure
  #352 was filed to catch, so it is fixed at every site that made the claim: `atuin/config.toml`,
  `scripts/bench-atuin-daemon.sh`'s header, and **both** unreleased entries in this file — the
  one above and the earlier `bench(fix)` entry, which described the same run as "real Fedora
  hardware" too. That fourth site was missed on the first pass because the check that was
  supposed to prove the claim filtered CHANGELOG line numbers by a guessed section boundary
  instead of the actual `## [Unreleased]` extent, and so excluded the line it needed to catch.

- **`sd` silently stopped matching across newlines, and its `--version` won't tell you.**
  Upstream 1.1.0 made **line-by-line** processing the default and moved the old whole-file
  behaviour behind `--across` / `-A`. Nothing in Core breaks — `sd` is detect-only
  (`HAVE_SD`) and deliberately un-aliased, and no Core code shells out to it — but a
  multiline pattern in muscle memory or in a role script now matches nothing, leaves the
  input untouched, and **still exits 0**, so the caller carries on as if it had rewritten
  the file. Verified behaviourally rather than read off the release notes:
  `sd 'alpha\nbeta' X` on two-line input returns rc=0 with the input unchanged, and
  `sd --across` matches.

  This earns a `PORTING-MATRIX.md` footnote (²²) rather than a detection change for two
  separate reasons. **Core needs no runtime change**: nothing here calls `sd`, so there is
  nothing to gate. And **the version string could not carry a gate anyway** — the Homebrew
  **1.1.0** build self-reports `sd 1.0.0`, so `HAVE_SD` could never have keyed off it.
  Consumers that genuinely must know — a role script targeting both builds — **feature**-detect
  instead, with `sd --help | grep -q -- --across`, and add `-A` only when the probe says the
  flag exists; hard-coding it breaks the pre-1.1.0 builds this matrix tracks, which already
  match whole-file. Same class of footnote as `batcat` (⁴) and the mikefarah-vs-kislyuk `yq`
  split (⁶): the command is not quite what its name implies. Found by the weekly
  `/tool-scout` scan (#376).

- **`pre-commit` moved off a known-broken patch: `4.6.1 → 4.6.2`.** 4.6.2's sole content is a
  fix for a 4.6.1 regression in `language: node` hooks whose `package.json` declares a
  `scripts.build` key, under npm 11.x (pre-commit#3737). It is **not** fixing a live failure
  here — markdownlint-cli2 is Core's only node hook, and v0.23.2's manifest carries
  `build-docker-image` and friends but no plain `build`, so it misses the trigger condition.
  Taken anyway, on the principle that sitting on a patch upstream has already superseded is a
  bet the next hook addition doesn't collect. One line in `scripts/tool-versions.env`; the
  three consumers (`ci.yml`, `scripts/setup.sh`, `.devcontainer/devcontainer.json`) all read
  the variable, so no literal moved with it. **No checksum refresh applies** — `PRECOMMIT` is a
  pip install, not a raw release download, so it carries no `*_SHA256` and is absent from both
  `scripts/update-tool-checksums.sh` and the audit's section 9b. No `.pre-commit-config.yaml`
  change either: the audit's version-consistency section gates `PRECOMMIT_HOOKS_VERSION` (the
  hook repo's `rev:`), never the pre-commit binary. Of the nine remaining pins, the eight gate
  tools were checked against upstream in the same pass and are current; `CLAUDE_CODE_VERSION`
  is the one exception, deliberately left at `2.1.222` with `2.1.227` available — it changes
  the scheduled routine bots' behavior, and moving it alongside an unrelated fix would make a
  later routine regression ambiguous to bisect. It moves on its own.

- **The daemon's contention claim now has a musl number.** Measured in an Alpine 3.21
  container (real Alpine userland, real musl, no systemd) against a glibc control on the same
  host, atuin 18.19.0, two runs each. The p50 win holds and is the most robust result so far
  (~1.4x on both libcs), but the far tail is where they **diverge**: on musl the p99 was worse
  with the daemon on _both_ runs — a stable sign, where glibc gives a coin flip. That is the
  strongest evidence yet against selling the daemon as a tail fix, and it lands on the path
  Alpine actually ships. `atuin/config.toml` carries the table and the caveat that a container
  is not real hardware.

- **The `@vN` pinning policy is no longer stated as universal, because it is 27 of 28.**
  `dotfiles-Windows` SHA-pins its `auto-tag-call` caller on purpose — immunity to a moved tag,
  traded against the auto-fan-out — and both `RELEASE-RUNBOOK.md` and `RELEASE-STRATEGY.md`
  read as though every caller tracks `@v4`. Worse, the runbook's own straggler sweep
  (`grep -rl 'uses:.*@v4'` across `scripts/os-repos.txt`) **structurally cannot find it**:
  Windows vendors no `core/`, so it is not in that list. It is therefore invisible to the
  grep and unmoved by the alias — currently several releases behind. Both documents now name
  the exception and say to check it by hand.

- **The daemon rationale in `atuin/config.toml` and `zsh/00-tools.zsh` now reports what was
  measured, and it is not the whole pitch.** A container run reproducing the topology of the
  Alpine path (no systemd, `XDG_RUNTIME_DIR` unset) puts the median and p95 win at
  ~1.4× and 1.2–1.3× — real, and steady across runs. But **p99 flips sign run to run and
  the maximum is consistently ~2× worse with the daemon on**: it trades frequent small lock
  waits for rarer, larger stalls. "Removes the tail latency" was therefore an overclaim in
  both files and is now scoped to the typical command rather than the worst one. The
  autostart path's first command additionally pays ~+41 ms for the spawn. Still unmeasured
  and still needing hardware nobody has to hand: musl, the systemd-unit path, and a network
  home — where the claim is strongest and least tested.

- **Plugin pins rolled forward.** Routine freshness sweep, landed by the bot and previously
  unrecorded here. Six Neovim plugins in `nvim/lazy-lock.json` (`fzf-lua`, `nvim-lspconfig`,
  `nvim-tree.lua`, `nvim-treesitter`, `package-info.nvim`, `schemastore.nvim`) and the zsh
  `zsh-syntax-highlighting` pin in `zsh/45-plugins.zsh`. Pins are what stop plugins floating
  silently into eight repos, so every roll is a change those repos receive on their next sync
  — `CONTRIBUTING.md` requires it in the changelog, and there is no carve-out for automation.
  (`nvim/lazy-lock.json`, `zsh/45-plugins.zsh`)

## [v4.9.3] - 2026-08-06

### Fixed

- **The atuin daemon opt-in never worked. `ATUIN_DAEMON__ENABLED=true` was silently
  ignored on every machine.** Core shipped `atuin/config.toml` with `[daemon] enabled =
  false` written out explicitly, and that assertion is what broke it: atuin builds its
  config as defaults → **environment** → config **file**, adding the file source last
  (`settings.rs` — the `Environment` source goes in at the builder, the file at
  `build_config()` afterwards), and in the `config` crate the later source wins. So any key
  this file mentions **shadows its `ATUIN_*` override**. The one key the whole per-OS design
  depends on being overridable was the one Core asserted.

  The fix is to write no value: `enabled` and `autostart` are now left unset. Upstream's own
  defaults are already `false`/`false` (`settings.rs:1515-1516`), so Core still ships the
  daemon **off** — off by default rather than off by assertion — and the override reaches it.

  **Measured, not reasoned**, against atuin **18.19.0** built from crates.io. `atuin doctor`
  reports the resolved `daemon_enabled`, and the client was straced for `connect()` on the
  socket, which is the only thing that distinguishes the two paths — exit codes cannot,
  because the client degrades silently to direct SQLite when the daemon is unreachable,
  which is exactly why this went unnoticed:

  | Config | `daemon_enabled` | `connect(atuin.sock)` |
  | --- | --- | --- |
  | `enabled = false` written + `ATUIN_DAEMON__ENABLED=true` | `false` | **0 calls** |
  | key absent + `ATUIN_DAEMON__ENABLED=true` | `true` | 1 call |
  | no config file at all + `ATUIN_DAEMON__ENABLED=true` | `true` | — |
  | **after this change**, no env | `false` | — |
  | **after this change**, `ATUIN_DAEMON__ENABLED=true` | `true` | 1 call |

  What this was costing the fleet: `dotfiles-Fedora`'s bootstrap installed and enabled a
  systemd unit that started a daemon **no client ever talked to**, and `dotfiles-Alpine`'s
  exports were inert. Core's guard made it quieter still — it reads `ATUIN_DAEMON__ENABLED`
  from the environment, where it _was_ set, so on Fedora it found the unit's socket present,
  stood down satisfied, and reported healthy while every write went straight to SQLite.
  Nothing was broken for a user; the feature simply did not exist.

  `scripts/test-core.sh` now asserts the two keys stay unset, negative-tested by putting
  `enabled = false` back and watching it fail. The check is static because the behavioural
  proof needs an atuin binary CI does not have. The same trap applies to any future
  per-machine key — asserting even its default disables the override — which is now stated
  in the config header, `PORTING-MATRIX.md` footnote 20, and beside the block itself.

  **Three follow-ups from review, all of them the same defect wearing other hats:**

  - The guard scanned only inside a literal `[daemon]` table, so the equally valid dotted
    form `daemon.enabled = false` at top level recreated the bug and passed green. Widening
    the regex was still the wrong shape — `daemon = { enabled = false }` and
    `daemon . enabled = false` are also valid and also deserialize to the same key, so a
    pattern match can only ever cover the spellings someone thought of. The guard now
    **parses** the TOML with `tomllib` (the idiom `audit-core.sh`'s config gate already
    uses) and inspects the resolved `daemon` table, which is what atuin itself resolves.
    All four spellings negative-tested; an unparseable file fails distinctly rather than
    being read as clean.
  - The config header advertised `export ATUIN_SEARCH_MODE=prefix` as its example of an
    override — while the same file writes `search_mode = "fuzzy"`, which makes that export
    silently ignored. Documenting the precedence trap and then demonstrating it was the
    worst of both. The example now uses `sync_address`, a key the file genuinely leaves
    unset, and the header names the ten settings that are deliberately **not** overridable
    so the distinction is explicit rather than inferred.
  - The v4.8.0 upgrade note told adopters to port `sync_address`, `auto_sync` and
    `filter_mode` to `ATUIN_*` overrides. The first two work; `filter_mode` is written by
    this file and cannot. That entry now carries the correction inline rather than being
    quietly rewritten — it was wrong when shipped, and the record should say so.

  Verified against atuin 18.19.0 rather than assumed: with Core's config in place,
  `ATUIN_SEARCH_MODE=prefix` still resolves to `fuzzy` and `ATUIN_FILTER_MODE=prefix` still
  resolves to `global`.

## [v4.9.2] - 2026-08-05

### Changed

- **`RELEASE-RUNBOOK.md` §1.1 now branches _before_ staging, so a cut never touches `main`.**
  The old order ran `make release` / `make tag` from `main` and only created
  `release/vX.Y.Z` at the push in step 3 — but `tag-release.sh` commits to whatever branch
  you are standing on, so the release commit landed on the operator's local `main`, one
  ahead of origin, on a protected branch it must never be pushed to. Every cut then needed a
  `git reset --hard origin/main` afterwards that the runbook never mentioned; cutting v4.9.1
  tripped it twice. Branching first (new step 1) makes the cleanup unnecessary rather than
  undocumented — verified by running both orders end-to-end in a throwaway clone: the new
  one leaves `main` **0 ahead**, the old one **1 ahead**. Steps renumbered 0–5, and the four
  cross-references to "§1.1 step 4" (including the `@vN` bump-type callout heading) moved
  with them.

- **The local `vN` alias move is now stated where it happens.** `make tag` force-moves `vN`
  onto the not-yet-merged release commit (`scripts/tag-release.sh`), so between step 3 and
  step 5 a local read of `v4` reports a commit origin does not have. Nothing was wrong with
  the behaviour — it is what keeps the alias from drifting — but it was undocumented, and an
  unexplained local/remote disagreement on the ref every reusable-workflow caller pins to is
  worth one sentence. Both the runbook and the script's own printed recipe now say it.

- **New "Abandoning a cut" section**, for a release staged and then reconsidered (a bump
  reclassified, a wrong version) — which is exactly what happened between v4.10.0 and
  v4.9.1. It restages rather than patching the branch in place, since the branch name
  encodes the version, and it undoes both local-only artefacts. The `git tag -d vX.Y.Z vN`
  line deletes the alias **explicitly** rather than leaving it to the fetch: `--tags
  --force` only _updates_ tags origin already has, so on a MAJOR — where the alias is newly
  minted and origin has never seen it — a fetch leaves a bogus local `v5` pointing at a
  deleted commit. Found by running the recipe against both cases in a throwaway clone, not
  by reading it.

  There is now **one** cleanup recipe, not two. The troubleshooting table carried its own,
  written for the old flow — delete `vX.Y.Z`, `git reset --hard HEAD~1` — which under
  branch-first leaves the release branch standing and `vN` still on the abandoned commit. It
  now points at the section instead of competing with it. The same `vN` omission was in
  `tag-release.sh`'s printed guidance, which claimed to undo "both local artefacts" while
  naming only one; both found in review by Copilot. The genuinely distinct cases the table
  covered are kept: staging without committing is still a plain
  `git checkout -- core.version CHANGELOG.md`, and abandoning **after the tag reached
  origin** — the `PUSH=1` path, where a Release is published and the fan-out has already
  fired — is now written out in the section, with the advice to cut the intended version
  forward rather than unwind a published one.

## [v4.9.1] - 2026-08-05

### Fixed

- **`make release-notes` emitted its sections alphabetically, so Bug Fixes led and Features
  came fourth.** Tera's `group_by` sorts groups by their key string, and `cliff.toml` gave it
  bare names — so git-cliff rendered `Bug Fixes` → `Chores` → `Documentation` → `Features`,
  burying what a release _added_ under what it _repaired_. `scripts/gen-release-notes.sh`,
  the no-git-cliff twin, has always emitted `commit_parsers` order (Features first), which is
  the more useful order for a release body — so this converges the two by moving git-cliff to
  the twin's order rather than degrading the twin to alphabetical.

  Each `commit_parsers` group now carries a `<N>` sort-key prefix (`group = "<0> Features"`),
  and the template strips it back out with `striptags` — git-cliff's own documented idiom for
  ordered groups, so headings still render as `### Features`. Verified against git-cliff
  **2.13.1**: over a synthetic repo exercising all groups and over `v4.8.0..v4.9.0`, the twin
  and git-cliff now produce identical output — same sections, same order, same bullets.

  **Two guards, because the order is now written down twice** (`cliff.toml`'s `<N>` keys and
  the twin's `ORDER` array). `scripts/test-core.sh` parses both and diffs them, so a change to
  one without the other fails the audit instead of drifting silently; and it pins the ceiling
  those single-digit keys carry — at ten groups the list is exactly full, and an eleventh
  would need two-digit keys throughout, since `<10>` sorts between `<1>` and `<2>`. Both
  assertions were negative-tested (perturb the config, watch them fail) rather than assumed.

  The order guard **sorts before comparing**, which is the whole of its value: git-cliff
  renders the lexical order of the full group strings, so a line's position in
  `commit_parsers` decides nothing. A guard that read the file top-to-bottom would have
  passed while `<0>` and `<1>` were swapped in place — and git-cliff 2.13.1 confirms that
  swap really does put Bug Fixes back ahead of Features. It now extracts each group with its
  key, sorts as Tera does (`LC_ALL=C`, so the runner's locale cannot move it), and strips the
  keys only afterwards, so what is compared is the effective output order.

  **A boundary this does _not_ cross, now documented in the script header:** given a range
  that spans an intermediate tag, git-cliff segments its output per release — `v4.7.0..v4.9.0`
  renders three blocks with repeating headings — while the twin flattens the range into one
  set of groups. Neither caller ever asks for such a range (`make release-notes` passes the
  commits since the last `release vX` commit; `auto-tag.sh` passes `<last-tag>..<new-tag>`),
  so on every range either tool is actually given they agree exactly. Teaching awk to segment
  by tag would be real complexity for a shape no caller produces.

- **`gen-release-notes.sh` kept the Conventional-Commit prefix that `cliff.toml` tells
  git-cliff to strip.** The script bills itself as the first-party twin of `make
  release-notes` — same grouping, same bullets, no git-cliff binary — but rendered
  `- Fix(ci): point core-freshness at the released tag (0e85561)` where git-cliff renders
  `- Point core-freshness at the released tag (0e85561)`. Two things were wrong with that:
  the type repeated the heading it sat under (`### Bug Fixes` → `Fix(ci):`), and
  `upper_first` was applied to the raw subject, capitalising the type into a `Fix(ci):`
  that is not a valid Conventional type. The cause was a one-line mismatch —
  `cliff.toml` sets `conventional_commits = true`, which makes git-cliff parse each subject
  and expose `commit.message` as the **description alone**, with type, scope and the
  breaking `!` split off into `commit.scope` / `commit.breaking`. The twin never did that
  parse, so `{{ commit.message | upper_first }}` and its awk equivalent were not the same
  expression.

  Verified rather than reasoned: git-cliff **2.13.1** was built and run against this repo's
  own `cliff.toml`, and the twin's bullets are now byte-identical to it over
  `v4.8.0..v4.9.0`, `v4.7.0..v4.9.0` (21 bullets), and a synthetic repo covering scoped,
  breaking, skipped and unconventional subjects. That run also corrected a second, subtler
  case: a subject that is nothing but a prefix (`refactor:`) is **dropped**, because
  git-conventional requires a description and `filter_unconventional` discards what it
  cannot parse — git-cliff emits no Refactoring group at all for that input, so neither
  does the twin.

  **One deliberate divergence, and it is the reason this was worth fixing carefully:**
  git-cliff renders a breaking commit indistinguishably from an ordinary one, because this
  template interpolates only `commit.message` and never `commit.breaking` — confirmed
  against the real binary, which turns `feat(y)!: upend a contract` into a bullet with no
  marker at all. Stripping the prefix would have made that invisible here too, collapsing
  `feat!:` and `feat:` into the same line. A release-notes draft is the one document where
  a breaking change must not be silent — it is what drives the SemVer major bump — so the
  twin now prefixes those bullets with `**BREAKING**` instead of losing them.

  `scripts/test-core.sh`'s block for this script had **pinned the bug**: it asserted
  `Feat(x): add a thing`, so the prefix-retaining output was the tested contract rather
  than an escape. It now asserts both directions (the description is present _and_ no
  bullet carries a `type(scope):` prefix), plus the breaking marker and the
  description-less drop — four new assertions, nine in the block.

## [v4.9.0] - 2026-08-05

### Removed

- **The per-repo `core-freshness` watcher is retired** — `core-freshness-call.yml` is deleted
  here, and the seven callers plus their seven copies of `test/check-core-freshness.sh` are
  removed in the OS repos. It answered a question that is now answered twice over, better:

  - **`fleet-drift.yml`** already runs the same comparison centrally, Mondays 06:00 UTC — an
    hour _before_ the per-repo watchers ran — against the latest **released** Core tag, failing
    red with a summary when any repo lags. One job, whole fleet, including `dotfiles-Defense`,
    which never had a watcher at all and so was silently unwatched by the old design.
  - **`sync-fanout.yml`** opens a `core.lock`-bump PR in every OS repo the moment a release
    publishes, so a weekly "you are behind" nudge restates what the bot already did and left
    a PR for.

  **It was also wrong for most of its life, which is what surfaced all this.** It compared each
  repo's `core.lock` against `refs/heads/main` by strict equality, so any commit landing on Core
  between releases reported the whole fleet behind while every repo sat on the newest release
  with nothing to pull. Not drift — a false alarm, weekly: MacBook and Fedora failed the
  identical scheduled runs on 2026-06-29, 07-06, 07-20, 07-27 and 08-03, green only on 07-13,
  where a sync happened to land near main's tip. Five months of red is how a nudge stops being
  read. A first pass repointed it at `refs/tags/v4`; this supersedes that, so the fix ships as
  a deletion rather than as a corrected job no consumer would ever run.

  `fleet-drift.sh` never had either bug, which is the strongest argument for keeping only it:
  it has defaulted to the latest released tag from the start (its header records that measuring
  against tip reported a false "BEHIND by N" for every unreleased commit — the same lesson,
  learned earlier), and it resolves refs with `rev-parse "${r}^{commit}"`, so it is immune to the
  annotated-vs-lightweight tag trap that the per-repo SHA comparison walked into.

  The duplication left behind — seven hand-maintained copies of `check-core-freshness.sh`,
  MacBook's already drifted from the six that agreed — was filed as #341 and is closed by this
  removal rather than by consolidating copies of something redundant.

  **One operational note worth keeping**, since the retired job's summary was the only place it
  was written down: do not hand-run `git subtree pull` to update a vendored `core/`. It updates
  the tree but not `core.lock`, which makes `core-integrity.sh` report the freshly-synced tree
  as `TAMPERED` (it compares the tree against the commit the lock pins), and the documented
  repair is not portable — `dotfiles-Alpine` has no root `Makefile`, so `make core-lock` does
  not exist there. `sync-core.sh` commits both together; merge the sync PR the fan-out opened,
  or re-dispatch `sync-fanout` for the one repo.

  Ordering matters and is worth recording: the **callers go first**. They pin
  `uses: …/core-freshness-call.yml@v4`, so deleting the definition while a caller still
  references it turns a retired job into a failing one. This deletion only reaches the fleet
  when the `v4` alias next moves, by which time the callers are gone.

  `core-integrity.yml` is untouched in every repo — the vendored `core/` is still verified
  against the commit its `core.lock` pins.

### Fixed

- **`examples/atuin-daemon.service` could not start atuin on the repos most likely to use it.**
  The unit listed `%h/.local/bin:/usr/local/bin:/usr/bin` on the assumption that a
  binary-distributed atuin lands beside starship and mise. It does not: atuin's own installer
  hard-codes `$HOME/.atuin/bin` (`install.sh`, `ATUIN_BIN="$HOME/.atuin/bin/atuin"`), and
  `dotfiles-Fedora`'s bootstrap installs it exactly that way — `curl -fsSL https://setup.atuin.sh
  | sh` — because atuin is not reliably packaged on Fedora. A user unit inherits none of your
  shell PATH, so `ExecStart=/bin/sh -c 'exec atuin daemon'` would have failed **`status=127`**
  on the first box to copy it: systemd starts `/bin/sh` fine, and the shell exits 127 when
  `exec` cannot resolve `atuin`. (The neighbouring `203/EXEC` is the _other_ failure — what
  systemd reports when it cannot execute `ExecStart` itself, i.e. the hard-coded absolute path
  this unit deliberately avoids.) `%h/.atuin/bin` now leads the unit's PATH, and the comment
  names all three real locations rather than two. Found by `/doc-audit`.

  **A related gap this does _not_ close**, because it needs checking on live hardware first:
  `zsh/00-tools.zsh` adds only `~/.local/bin` to PATH, and `dotfiles-Fedora`'s `os/fedora.zsh`
  adds `~/.local/bin` + `~/.cargo/bin` — neither adds `~/.atuin/bin`. On a box where atuin came
  from its own installer, `_have atuin` may therefore fail, leaving `HAVE_ATUIN` unset and the
  whole atuin integration silently absent. The unit is fixed either way; the shell-side PATH is
  a separate question to answer on a real Fedora box.

- **`PORTING-MATRIX.md` promised the atuin socket guard "whatever the launcher" — it stands
  down on two of the eight machines.** The footnote's own table sends **Alpine and macOS** down
  the `autostart` path, and `zsh/00-tools.zsh` deliberately returns early there: under
  `autostart` an absent socket is the client's _cue to start one_, so disabling the daemon
  would permanently defeat the only launcher those machines have. The guard's scope was stated
  correctly in `atuin/config.toml`, in the code comment, and in the v4.8.0 changelog entry —
  the matrix was the one place that overclaimed, and it is the sentence an operator reads while
  deciding how to run the daemon. It now scopes the paragraph to the systemd-unit launcher and
  says plainly what covers the other two. `scripts/test-core.sh` already pinned the stand-down,
  so the code was never in doubt.

- **Three surfaces said `fleet-drift` measures against Core's tip; it measures against the
  latest released tag.** `Makefile`'s `fleet-drift` help, `RELEASE-STRATEGY.md`'s Monday-sweep
  bullet, and `scripts/core-integrity.sh`'s "INTEGRITY companion" note all said "tip".
  `scripts/fleet-drift.sh` has defaulted to the newest `vX.Y.Z` since it was written, and its
  header records why: measuring against tip "reported a false 'BEHIND by N' for every
  unreleased commit on main". This matters more than a word choice now — the entry above
  retires the per-repo watcher _because_ `fleet-drift` compares against the released tag, so a
  doc saying "tip" undercut the stated rationale.

  Both found by `/doc-audit`.

- **The rest of that `/doc-audit` sweep — nine more places where prose had drifted from the
  code.** Grouped by what was wrong, not by file:

  **Counts and pins that were simply stale.** "9 OS repos" survived in **32 comments across 11
  files** (`ci.yml`, `audit-core.sh`, `test-core.sh`, `45-plugins.zsh`, `CODEOWNERS`, …) after
  an earlier audit corrected only the prose; the fleet is **eight** (`scripts/os-repos.txt`).
  Every caller-stub example and "current major" note said `@v3`; the fleet actually pins
  **`@v4`** — verified against `core-integrity.yml`, `lint.yml` and `bootstrap.yml` in three
  repos, so the `@v3`→`@v4` bump _was_ performed and only the docs lagged.
  `RELEASE-RUNBOOK.md`'s major-bump walkthrough now uses `v4`→`v5` as its example, and
  `RELEASE-STRATEGY.md` no longer hard-codes a `core.version` (it said `3.6.0`).

  **`PARITY.md` listed a divergence as alignment.** It claimed `grep`→rg was aligned across
  shells. It is not, and the reason matters: pwsh defines `grep`→rg
  (`dotfiles-Windows/powershell/core/00-aliases.ps1`), while Core deliberately leaves `grep`
  POSIX because shadowing it on a Unix box changes what every script in `$PATH` gets. That is
  a `deliberate` divergence — the status PARITY.md already has for exactly this — so it is now
  recorded as one rather than quietly listed as the same. Its source pointer also still named
  the pre-v4 unnumbered fragments (`zsh/{aliases,git,…}.zsh`).

  **Invariants that stopped being true.** `20-aliases.zsh` and `core.manifest` both asserted
  that the aliases module "intentionally carries no git aliases" — nine lines above a
  `HAVE_DIFFT`-gated `gdft`; both now name the two tool-detection exceptions (`lg`, `gdft`),
  and `aliases.md` stops filing `gdft` under a heading that says it comes from `25-git.zsh`.
  `10-options.zsh` and `15-history.zsh` claimed to load "SECOND" and "THIRD"; `05-ui.zsh`
  displaced both, so they now cite the `NN` prefix as the contract instead of a hand-counted
  position — which is what `core.manifest` already says.

  **A self-invalidating instruction.** `/doc-audit`'s own check #1 told auditors to compare a
  README "Layout" tree that no longer exists, so it could neither pass nor fail. It now points
  at the real three-way inventory: `core.manifest` ↔ `git ls-files` ↔ `blib_link_core`.

  **Guidance that contradicted the entry above.** `RELEASE-STRATEGY.md`'s two `git subtree
  pull` recipes carried the stale-`core.lock` trap this changelog had just documented; both now
  carry the caveat, and the rollback one notes that pulling an older tag merges backwards
  rather than un-merging. Also: `aliases.md` promised the user-facing `30-functions.zsh` verbs
  but omitted `core`, `core-doctor` and `core-version`; `ARCHITECTURE.md`'s definition of Core
  read as a closed list that omitted six manifest entries; `CLAUDE.md`'s load chain dropped the
  role band; `RELEASE-STRATEGY.md` named 2 of the 7 reusable workflows; and `sync-core.sh` had
  one surviving reference to the retired freshness watcher.

## [v4.8.0] - 2026-08-05

### Added

- **atuin gets a Core config, and its daemon becomes an OPT-IN capability (#335).** Core has
  initialised atuin since v3 (`zsh/00-tools.zsh`) while shipping **no atuin config at all** —
  every setting was whatever atuin defaulted to that release. New `atuin/config.toml`
  (symlinked to `~/.config/atuin/config.toml`, the default path, in `core.manifest`) closes
  that, and carries the `[daemon]` block the adoption is about.

  **The daemon ships OFF.** atuin's daemon owns the SQLite writes so shells stop contending
  for the DB lock — the tail latency a busy multi-pane box pays — but a shell that starts a
  background daemon as a side effect of being opened is a behaviour change on eight machines.
  A machine opts in from its own OS layer with atuin's native env overrides
  (`ATUIN_DAEMON__ENABLED=true`, plus `ATUIN_DAEMON__AUTOSTART=true` where nothing else
  supervises it), never by editing the vendored Core file. The **launcher is OS-native** and
  stays in the OS repos: `PORTING-MATRIX.md` footnote 20 gives the per-machine table
  (systemd user unit · Alpine/macOS via atuin's own autostart · Windows out of scope) and
  `examples/atuin-daemon.service` is the ready-to-copy unit. Fedora first, Alpine second.

  **`00-tools.zsh` gains `_core_atuin_daemon_guard`** — a one-shot precmd hook that probes the
  daemon socket and forces the daemon off for that shell when nothing is listening, so an
  absent or **stale** socket (the file survives a crashed daemon) costs the lock relief
  instead of a failed connect and an error on every command. It connects rather than
  stat-ing, because a stale socket file passes `[[ -S … ]]`; equally, when `zsh/net/socket`
  is unavailable it degrades rather than fall back to that same existence test — the daemon
  stays on only where a connect actually succeeded. It runs at the first prompt (the OS/host
  fragments load after `00-tools`), stands down under `autostart` (atuin health-checks its
  own daemon there), unhooks itself after one run, and says nothing; `core-doctor` reports
  the degraded state. Scope, stated plainly: it cannot detect an **accept-but-silent** socket
  — systemd socket activation holding the socket while the daemon behind it is dead — which
  is the shape of the indefinite freeze in `atuinsh/atuin#3382`; no cheap shell-side probe
  can, which is why the shipped guidance prefers the plain always-running unit over the
  `.socket` variant. The `atuin init zsh` call is deliberately **not** gated — that script is
  daemon-agnostic, so gating it would only cost the Ctrl+E TUI.

  Other settings in the new config are explicit versions of what Core already asserts
  elsewhere: `enter_accept = false` (the TUI hands the command back for review — the same
  contract as `HIST_VERIFY` in `15-history.zsh`), `keymap_mode = "auto"` (the fleet runs
  zsh-vi-mode), `secrets_filter` + a `history_filter` mirroring `HISTORY_IGNORE` — which
  `15-history.zsh` has promised atuin does since it was written, with nowhere to put it — and
  `update_check = false` (Core owns update nudges; no second network call on the hot path).
  Account/sync settings are deliberately absent. `scripts/test-core.sh` gains **ten** atuin
  assertions (six for the guard, two for its registration/inertness, and the `ATUIN_NOBIND`
  export + `_cache_eval --salt` contract that were never pinned) plus two `ci-classify` rows,
  all hermetic — the live and stale sockets come from zsh's own `zsocket`, so no atuin binary
  is needed.

  **On upgrade — read this one.** atuin writes its own `~/.config/atuin/config.toml` on first
  run, so unlike jujutsu/lazygit this is the Core link that will routinely find a **real file**
  on a box that has already used atuin. Bootstrap moves it to `…config.toml.pre-dotfiles.<epoch>`
  before linking (a pre-existing **symlink** is replaced without a backup — that is `blib_link`'s
  long-standing behaviour, not new here). atuin has no `include` directive, so port anything you
  had customised — `sync_address`, `auto_sync`, `filter_mode` — to `ATUIN_*` env overrides in your
  OS or `99-local` layer rather than editing the vendored file.
  **Corrected later:** that works for `sync_address` and `auto_sync`, which this file leaves
  unset, but **not** for `filter_mode`, which it writes — a key the Core config sets cannot be
  env-overridden at all. To vary one of those per machine, delete it from `atuin/config.toml`.
  See the `[v4.9.3]` entry on the daemon opt-in for why.

### Changed

- **Audited every pin in `scripts/tool-versions.env` and bumped five.** This is the class
  neither bot touches — `/freshness-triage` covers zsh/nvim plugin locks and dependabot PRs,
  Renovate covers manifests, and the CLI gate pins sit in the gap between them, which is how
  `pre-commit` drifted six minors and the Claude Code CLI thirty-seven patches behind. Audited
  all ten against upstream:

  | Pin | Was | Now | |
  | --- | --- | --- | --- |
  | `NVIM_VERSION` | 0.12.3 | **0.12.4** | one patch |
  | `ACTIONLINT_VERSION` | 1.7.8 | **1.7.12** | four patches |
  | `PRECOMMIT_VERSION` | 4.0.1 | **4.6.1** | six minors |
  | `CLAUDE_CODE_VERSION` | 2.1.185 | **2.1.222** | the routine bots' own CLI |
  | `SHFMT_VERSION` | 3.8.0 | **3.13.1** | five minors — see below |
  | shellcheck · luacheck · markdownlint-cli2 · gitleaks · pre-commit-hooks | | | already current |

  `NVIM_SHA256` and `ACTIONLINT_SHA256` recomputed with `make update-tool-checksums`, then
  **cross-checked against upstream independently** rather than trusted from our own download —
  these hashes are the supply-chain trust anchor for the whole gate toolchain, so a
  self-computed hash proves only that the download was self-consistent. actionlint matches its
  published `actionlint_1.7.12_checksums.txt`; neovim matches the `digest` GitHub reports for
  the release asset. The three unbumped hashes re-derived byte-identical, which is its own
  integrity signal. No `.pre-commit-config.yaml` change was needed — all four hook `rev:`s
  (pre-commit-hooks, shellcheck, markdownlint-cli2, gitleaks) were already current, so the
  audit's version-consistency section stays green.

  **`shfmt` 3.8.0 → 3.13.1 was verified by hand, because Core's own CI genuinely can't check
  it.** Core does not gate shfmt (`CONTRIBUTING.md` says so — the compact one-liner style here
  is exactly what shfmt would expand), so this pin exists _only_ to give `setup-core-tools` one
  verified shfmt for its OS-repo consumers, and a green tick on a Core PR proves nothing about
  it. Two things make the bump safe, both checked rather than assumed:

  1. **The consumer step is advisory.** `lint-call.yml`'s shfmt step wraps the run in an
     `if/else` that swallows the drift exit and emits `::warning::` instead — deliberately
     non-blocking without `continue-on-error`, so a genuine _install_ failure still reds. A
     formatter behaviour change therefore cannot turn an OS repo red; only a bad SHA or a
     missing release asset could.
  2. **3.13.1 formats identically to 3.8.0 here.** Both binaries were run with the exact flags
     the consumer uses (`-i 2`) over all 33 shell scripts in this repo. Both flag the same 10
     files, and formatting each corpus with `-w` produced **byte-identical** trees. The only
     difference between the two versions' `-d` output is presentational: 3.13.1 adds a
     `diff a b` header line and splits hunks more finely.

  `SHFMT_SHA256` refreshed and cross-checked against the `digest` GitHub publishes for
  `shfmt_v3.13.1_linux_amd64` (`fb096c5d…`).

### Documentation

- **`aliases.md` now documents the three aliases it had been silently missing.** `web`
  (→ `$BROWSER_BIN`, `zsh/20-aliases.zsh:65`), `uvr` (→ `uv run`) and `uvs` (→ `uv sync`)
  (:144-145) have all shipped for a while, tool-gated like every other modern-CLI swap, but
  none appeared in the alias reference — so the doc undersold what a box actually gets. `web`
  joins _Editors & Launchers_ with a note on the `w3m → lynx → links2 → links → elinks`
  resolution order and on why `$BROWSER` is exported only on a headless box; `uvr`/`uvs` get
  their own **uv (Python)** section mirroring how the `jj` aliases are documented.
- **`PORTING-MATRIX.md` now has a `gping` row, so the `ping` alias has an install path.**
  `zsh/00-tools.zsh` has set `HAVE_GPING` and `zsh/20-aliases.zsh` has aliased `ping`→`gping`
  since v3, and both `aliases.md` and `PARITY.md` advertise it — but the matrix listed no
  package for any distro, making it the one aliased tool with no documented way to get it.
  New footnote ¹⁹ records what the audit turned up: gping is in **no** repo's
  `install/packages.txt` and no `bootstrap.sh`, so like `jnv`¹⁷ it is **detect-only** — the row
  is the path for when you install it yourself. Packaging verified per-distro rather than
  assumed: Arch `extra`, Alpine `community` (native musl), Debian/Kali apt (source
  `rust-gping`, **binary** `gping`), Homebrew, nixpkgs; Gentoo is GURU-only
  (`net-analyzer/gping`, added to footnote ¹²); openSUSE Leap 15.6 ships 1.16.1 in `main/oss`
  while Tumbleweed builds from Factory, so that cell says verify-then-fall-back rather than
  claiming a binary this fleet has not confirmed.

  Reported by the 2026-08-04 `/doc-audit` sweep (S1, S2) — see #328.

## [v4.7.1] - 2026-08-03

### Fixed

- **`/os-package-availability` no longer files column-shifted matrix findings.** The
  Alpine run on 2026-08-02 reported four `PORTING-MATRIX.md` cells as stale
  (`starship`/`yazi`/`tree-sitter-cli`/`viddy` still on `script³`/`cargo³`) and asked
  for two footnote rewrites. All six were already correct: the routine had read the
  **Kali (apt)** column — the last cell on each row — as if it were Alpine, and
  re-proposed footnote wording the footnotes already carried. A report-first routine
  that flags a correct table is worse than one that finds nothing, since it invites a
  "fix" that introduces the drift it claimed to catch.

  The prompt now anchors both reads: count columns from the header row (`Arch |
  openSUSE | Alpine | Gentoo | Kali`, last cell is Kali), quote the whole row and name
  the column header before citing a cell, and quote a footnote's current text before
  calling it stale. Reporting rules require that evidence in the issue body, so a
  misalignment is visible to a reader instead of shipping as a finding.

- **The freshness dashboard no longer renders GitHub API error bodies as data.** The
  2026-08-03 board (#324) printed `{"message":"Not Found",…,"status":"404"}` as
  `dotfiles-web`'s release tag and a 403 secondary-rate-limit body as `htpx`'s open-issue
  count. Cause: on an HTTP error `gh api` **skips the `--jq` filter and copies the raw
  response body to stdout**, writing only its one-line summary to stderr — so the helpers'
  `2>/dev/null || true` silenced the wrong stream and discarded the one reliable signal,
  the exit code. The error JSON became "the value", and every `// empty` and emptiness
  guard downstream waved it through; the `— (no tags)` branch was unreachable for any repo
  whose 404 body carries a `message` key, and a third site (the Renovate tally) had the
  same latent defect.

  The helpers now capture stdout, test the exit code, and drop stdout on failure — and they
  propagate that status, so the board can tell "the API answered: none" (`— (no tags)`)
  from "we never got an answer" (`?`), a distinction it was previously asserting without
  evidence. The ~24 search-API calls are paced under GitHub's 30/minute authenticated
  ceiling (the workflow authenticates with the stock `GITHUB_TOKEN` and its lower shared
  quota), and a 403/429 gets a widening backoff under two brakes: an **exhausted** ladder
  latches, so the remaining calls stop re-waiting on a limit that demonstrably isn't
  clearing, while total backoff sleep is capped for the whole run — a ladder that _recovers_
  must not latch, but 24 calls each riding out a fresh transient limit would otherwise sleep
  for 12 minutes against a 15-minute job timeout. Both brakes are files, not variables, since
  the helpers run inside command substitution and a variable would not survive the subshell.
  `scripts/test-core.sh` now drives all of it against a `gh` stub reproducing the real error
  shape; the script had no behavioral coverage before.

## [v4.7.0] - 2026-08-01

### Added

- **`prefix + a` opens Claude Code in a tmux popup — `tmux/scripts/tmux-claude.sh` (new).** The
  nvim integration gives you Claude _coupled to an editing session_ (buffers, selection,
  diagnostics, diffs); this is the other half — Claude from a shell pane, mid-rebase, or in a
  directory with no editor open. Same shape as the `prefix + g` lazygit popup, rooted at
  `#{pane_current_path}`, and gated on the `claude` binary the way `tmux-sesh.sh` gates on `sesh`
  (absent, it puts the reason on the status line rather than doing a silent nothing).

  It is deliberately **not** `display-popup -E claude`, the way lazygit is bound. lazygit is
  stateless, so killing its popup costs nothing — a conversation is not, and dismissing a raw
  `-E claude` popup would take the thread with it. So this follows `tmux-scratch.sh` instead: a
  persistent detached session the popup attaches to, making `prefix + a` toggle _visibility_
  rather than lifetime. It inherits that script's three hard-won fixes — per-session
  `detach-on-destroy on` (or quitting hops the popup client onto your main session at popup
  dimensions and double-draws the real terminal), the `TERM` repair (`display-popup` launches with
  `TERM` unset, so a nested `tmux attach` otherwise dies with "terminal does not support clear"),
  and `status off` / `prefix None` / `key-table popup` so every keystroke reaches Claude's TUI.

  Sessions are keyed on the **git root**, not the cwd: every pane inside a repo shares one
  conversation, which is the granularity the work actually has, and a single global session would
  hand you `dotfiles-Kali`'s thread while you sat in `dotfiles-core`. The name carries a `cksum`
  hash of the full path so two repos sharing a basename cannot collide onto one conversation —
  `cksum` rather than `md5sum`/`md5`, which diverge between Linux and macOS.
- **`<C-y>` in fzf-lua sends the selection to Claude Code as @-mentions.** The tree-based
  @-mention (`<leader>as` in nvim-tree/oil) adds one file, so putting six files in context meant six
  navigations. fzf is already multi-select — `--multi` is on for the file pickers, `<Tab>` marks and
  `<A-a>` toggles all — so `plugins/fzf-lua.lua` now turns "the files involved in this change" into
  one gesture. From the grep pickers each entry carries a line number, so a hit is sent as its own
  location rather than the whole file (fzf-lua reports 1-indexed lines; `send_at_mention` documents
  its range as 0-indexed, so the action converts). Entries are parsed with `fzf-lua.path
  .entry_to_file` rather than by hand, since they carry devicon prefixes and grep entries are
  `file:line:col:text`. Covers `<leader>ff` / `fg` / `fb` / `fr` from one `actions.files` entry, and
  is documented in `cheatsheet.lua` alongside the multi-select keys.

  Three details worth recording. The action table carries a **leading `true`** — fzf-lua's
  inheritance marker (`config.lua` switches the merge to `tbl_deep_extend("keep", yours, defaults)`
  when `[1] == true`, then strips it). Without it a user action table _replaces_ fzf-lua's defaults
  wholesale, silently dropping `enter`, `ctrl-s/v/t` and `alt-q/Q/i/h/f` — i.e. opening a file at
  all. Line forwarding is **restricted to the grep family** (resume key containing `grep`), because
  `entry_to_file` also reports a positive line for buffer entries — `providers/buffers.lua`
  serializes each buffer's current cursor `lnum` — so forwarding it everywhere would make
  `<leader>fb` send the one line you were parked on instead of the file. And unlike
  `plugins/claudecode-nvim.lua` this is **not** `cond`-gated: fzf-lua is a core finder that must
  load everywhere, so gating the spec would mean an `executable()` probe at startup on every box in
  the fleet. The action fails soft instead, and since it only runs on a keypress it can afford to
  probe properly and name which failure it hit — CLI absent, CLI installed after Neovim started (the
  `cond` is evaluated once at startup, so a restart is needed), or the plugin genuinely failing to
  load, in which case the real error is shown rather than swallowed.

- **Claude Code IDE integration for Neovim (`coder/claudecode.nvim`).** `nvim/lua/gerrrt/plugins/claudecode-nvim.lua`
  adds the first runtime Claude surface in the fleet — until now Claude Code existed only as pinned
  CI automation (`scripts/tool-versions.env`, `.github/workflows/claude-routines.yml`). The plugin
  speaks the same WebSocket/MCP protocol as the official VS Code and JetBrains extensions: Neovim
  runs the server and writes `~/.claude/ide/<port>.lock`, and the `claude` CLI attaches to it. The
  payoff over a bare terminal pane is that Claude's edits arrive as a native `:diffsplit` you accept
  with `:w` (or `<leader>aa`) and can edit before accepting, visual selections send with their real
  file and line range, and Claude reads the session's LSP diagnostics over MCP rather than
  re-running a build. Keys live under a new `<leader>a` prefix (`ac` toggle, `as` send selection /
  add file from an nvim-tree or oil buffer, `ab` add buffer, `aa`/`ad` accept/deny diff, `am` model,
  `ar`/`aC` resume/continue, `aS` status), registered as the `ai / claude` group in
  `plugins/which-key.lua` and documented in `cheatsheet.lua`.

  Two deliberate departures from upstream's install spec, both fleet-driven:
  - **No `folke/snacks.nvim` dependency.** Upstream defaults its terminal to snacks, which Core does
    not ship and which would overlap fzf-lua, mini.notify and alpha. `terminal.provider = "native"`
    uses a plain `:terminal` split instead, keeping faith with the no-dap-ui/no-toggleterm stance in
    `config/autocmds.lua` and adding exactly one entry to `lazy-lock.json`. `provider = "none"`
    remains a one-line switch for driving `claude` from a tmux pane and attaching with `/ide`.
  - **The whole spec is `cond`-gated on the `claude` binary.** Core vendors into eight OS repos and
    the CLI is in none of their package lists, so on almost every box the plugin must be inert —
    the same reasoning as the existing `uv` gate for the pytest maps. `nvim/lua/gerrrt/health.lua`
    gains a `:checkhealth gerrrt` section that reports the gate (and, once loaded, the IDE lock
    file) so an absent `<leader>a` reads as intentional rather than broken.

  Installing the CLI itself stays out of Core: it is an npm/brew install and therefore OS-native.

- **Terminal buffers are escapable and navigable — `nvim/lua/gerrrt/utils/term.lua` (new).** A
  Neovim terminal buffer forwards every keystroke to the program inside it, and both of Core's
  terminals call `startinsert`, so you land in terminal mode where Core's `<C-h/j/k/l>`
  (vim-tmux-navigator, normal mode only) never reach Neovim. The split reads as a trap. Neovim's
  reserved `<C-\><C-n>` was always the way out, but nothing in the config said so — Core shipped no
  terminal-mode keymaps at all (`mode = "t"` appeared nowhere under `nvim/`). The defect was
  discoverability, not behavior.

  `utils/term.lua` now owns the rule, and both terminals opt in: Claude's split
  (`plugins/claudecode-nvim.lua`) and the **pytest split** (`config/autocmds.lua`), which shared the
  gap all along — it just never surfaced there, since that split is read-only output you glance at
  rather than a prompt you sit inside. Note `:q` needs normal mode too, so even closing one starts
  with `<C-\><C-n>`. Buffer-local `<M-h/j/k/l>` leave terminal mode and navigate in one keystroke;
  `cheatsheet.lua` documents all of it as one **Terminal buffers** card rather than a copy per
  terminal, since the panel shows every card at once.

  The navigator's own `<C-h/j/k/l>` are deliberately **not** widened into terminal mode: `<C-h>` is
  ASCII 8 (backspace) and `<C-j>` is ASCII 10 (newline), so claiming them would break editing at an
  interactive prompt — `<C-w>` (delete-word) is out for the same reason. `<M-…>` is unclaimed by the
  TUIs involved; mini.move owns `<A-h/j/k/l>` in normal/visual only, a different mode. The maps stay
  buffer-local so a terminal Core did not open (`:terminal`, a plugin's own) keeps its keys
  untouched — for Claude's, the buffer is identified by asking the plugin
  (`claudecode.terminal.get_active_terminal_bufnr()`) rather than matching the `term://` name, which
  would also hit a plain shell started in a directory containing the word "claude".
- **Python workflow ergonomics for the Astral stack (uv/ruff/ty).** Three small, additive changes
  that make the already-wired Python setup easier to drive day-to-day:
  - `zsh/20-aliases.zsh` adds `uvr` (`uv run`) and `uvs` (`uv sync`), guarded by a new `HAVE_UV`
    flag in `zsh/00-tools.zsh` so a bare box simply doesn't get them. `uv run` resolves the
    project's `.venv` itself, so these cover the daily loop without manual venv activation.
  - `nvim/lua/gerrrt/config/autocmds.lua` adds buffer-local pytest runners on Python buffers —
    `<leader>tt` (whole suite) and `<leader>tf` (current file) — running `uv run pytest` as an
    argv-form terminal job rooted at the uv project (not Neovim's cwd). Gated on `uv` being present,
    plugin-free (no neotest, matching the config's no-dap-ui/no-toggleterm stance), and complementing
    the existing DAP "debug test method" (`<leader>dm`). `<leader>t` is registered as the `test`
    group in `nvim/lua/gerrrt/plugins/which-key.lua` and documented in `cheatsheet.lua`; a headless
    probe in `scripts/test-core.sh` asserts the maps register on a Python buffer.
  - `mise/config.toml` documents the deliberate Python ownership split (mise supplies the global
    mise-managed interpreter for global tools; uv owns per-project envs) so the two managers' roles
    are explicit.
- **`mise` now supplies the `zig`, `terraform`, and `foundry` toolchains.** `plugins/conform.lua`
  declares `zigfmt`, `terraform_fmt`, and `forge_fmt` fleet-wide, so `:checkhealth` (and
  `:checkhealth gerrrt`) reported them as "unavailable — command not found" on every box lacking the
  binary. Adding them to `mise/config.toml` means `mise install` provides `zig fmt`, `terraform fmt`,
  and `forge fmt` (via foundry's `forge`) everywhere Core lands, with a note that foundry's
  glibc-linked prebuilt must be excluded via `disable_tools` / `MISE_DISABLE_TOOLS` on Alpine (musl),
  since mise merges global + local `[tools]` and omission alone doesn't drop an inherited tool.

### Fixed

- **`buf-config` is now a known filetype, silencing the `:checkhealth vim.lsp` "Unknown filetype"
  warning.** `nvim/lua/gerrrt/servers/buf_ls.lua` advertises `buf-config` as one of buf_ls's
  filetypes, but nothing mapped buf's config files to it — so the health check flagged it and buf_ls
  never attached to `buf.yaml` / `buf.gen.yaml`. `nvim/lua/gerrrt/config/autocmds.lua` now registers
  buf's full v2 config surface (`buf.yaml`, `buf.gen.yaml`, `buf.work.yaml`, `buf.policy.yaml`,
  `buf.lock`) via `vim.filetype.add`, so the filetype is known (warning gone) and buf_ls serves them
  with buf-aware completion/diagnostics. Highlighting is preserved by aliasing `buf-config` to the
  yaml parser (`vim.treesitter.language.register`), which hands the buffers to nvim-treesitter's own
  install/start lifecycle. Covered by a new assertion in `scripts/test-core.sh` (each buf basename
  resolves to `buf-config`; the parser alias resolves to `yaml`).
- **`PORTING-MATRIX.md`'s openSUSE column no longer understates what Tumbleweed packages.** Seven
  tools were marked bootstrap-only (`script³`/`cargo³`/`go³`) that the main OSS binary repo
  (`repo-oss`) now ships first-class — `starship`, `atuin`, `yazi`, `viddy`, `ouch`, `doggo`,
  `ast-grep` — so anyone stamping or maintaining `dotfiles-openSUSE` from the matrix was being
  told to build from source what `zypper in` already provides. Each now names its real package
  under a new footnote ¹⁸, which also records the caveat the audit could not close: **Leap 15.x
  was not separately audited** and rolls slower, so verify with `zypper se` there. Footnote ¹⁶
  (viddy) dropped openSUSE from its "not packaged" list to match. Docs-only — no `bootstrap.sh`
  or `packages.txt` behavior changes.
  The correction also surfaced a **latent overclaim**: of the seven, only `starship`, `atuin`,
  `yazi`, `viddy` and `doggo` are actually installed by `dotfiles-openSUSE`'s `bootstrap.sh`
  (presence-guarded, so a packaged binary short-circuits them). **`ouch` and `ast-grep` have no
  installer there at all**, so their old `cargo³` cells promised a ³ fallback that never existed —
  footnote ¹⁸ now says so, and names packaging as their only automatic path.

## [v4.6.0] - 2026-07-30

### Added

- **`:checkhealth gerrrt` now reports LSP / formatter / linter readiness.** The built-in
  `:checkhealth vim.lsp` only lists clients _attached to the live session_, so run from the
  dashboard it reads "No active clients" and says nothing about whether your configured tools
  are installed. Three new sections in `nvim/lua/gerrrt/health.lua` report per-tool state:
  - **LSP servers** — every wanted server (from `nvim/lua/gerrrt/servers/init.lua`) as
    attached / enabled-idle / pending-enable / binary-missing / override-failed, via a new
    read-only `M.status()` export that reuses the module's own wanted-list and
    `binary_available()`. It tracks _registered_ (our override loaded) and _enabled_ (we called
    `vim.lsp.enable`) as **distinct** facts — not inferred from `vim.lsp.config[name]`, which
    also resolves upstream lspconfig defaults — so a failed override or an installed-but-not-yet-
    enabled binary is reported accurately.
  - **Formatters (conform)** — rendered from conform's own `list_all_formatters()` availability.
  - **Linters (nvim-lint)** — from `linters_by_ft` + the SAST `semgrep`, checking each linter's
    real builtin `cmd`.

  All three are **side-effect-free**: they observe `package.loaded` and never `require()` a plugin
  (which would force-load it and, for the LSP stack, register/enable servers before nvim-lspconfig's
  defaults are on the runtimepath), so from the dashboard they say "open a file, then re-run" rather
  than mutating the session. Missing binaries are info (not warnings) on `DOTFILES_OFFLINE` boxes.
  Covered by new assertions in `scripts/test-core.sh` (the D4 registry probe exercises `status()`;
  the checkhealth probe asserts all four sections render).
  (`nvim/lua/gerrrt/health.lua`, `nvim/lua/gerrrt/servers/init.lua`, `scripts/test-core.sh`)

### Changed

- **Dev toolchain and plugin pins rolled forward.** Routine freshness sweep. The gate
  toolchain was bumped in `scripts/tool-versions.env` (the single source — `ci.yml` and
  `make setup` read it, and the audit's consistency gate enforces the `.pre-commit-config.yaml`
  revs match it): **shellcheck** `0.10.0 → 0.11.0` (with its `SHELLCHECK_SHA256` recomputed
  via `scripts/update-tool-checksums.sh`), **markdownlint-cli2** `0.22.1 → 0.23.2`, and
  **pre-commit-hooks** `v5.0.0 → v6.0.0`. Plugin pins were rolled to upstream: the zsh
  `zsh-transient-prompt` pin (`zsh/45-plugins.zsh`) and four Neovim plugins in
  `nvim/lazy-lock.json` (`nvim-lspconfig`, `package-info.nvim`, `rainbow-delimiters.nvim`,
  `schemastore.nvim`). (`scripts/tool-versions.env`, `.pre-commit-config.yaml`,
  `zsh/45-plugins.zsh`, `nvim/lazy-lock.json`)

### Fixed

- **`:checkhealth gerrrt` clipboard false alarm on native Windows.** On the Windows host
  (where `dotfiles-Windows` vendors only `nvim/` and never runs Core's bootstrap), the
  clipboard section warned "Core's cross-OS clipboard scripts are not on PATH (clip: found,
  clip-paste: missing)" — misleading, because `clip` only "found" as Windows' built-in
  `clip.exe` and the Unix/WSL `clip`/`clip-paste` ladder simply does not apply there:
  `config/clipboard.lua` wires an OS-appropriate provider instead (the `clip-windows`
  provider — `clip.exe` copy + PowerShell paste — when `clip.exe` is present, else the OSC52
  fallback). `nvim/lua/gerrrt/health.lua` now detects native Windows (`has("win32")`, false
  under WSL), records that the Unix probe is inapplicable, and defers to `:checkhealth
  vim.provider` for the live backend rather than running the ladder or re-deriving the
  provider itself. (`nvim/lua/gerrrt/health.lua`)
- **noice.nvim cmdline regex highlighting.** Added the `regex` Tree-sitter parser to
  `ensure_installed` in `nvim/lua/gerrrt/plugins/nvim-treesitter.lua`. noice runs a
  floating command line (`cmdline_popup`), which uses the `regex` parser to syntax-
  highlight the pattern in `:s/…/` substitutions and searches; without it, `:checkhealth
  noice` warned "`regex` parser is not installed. Highlighting of the cmdline for `regex`
  might be broken." It installs on next launch via the existing `ensure_installed` diff.

## [v4.5.0] - 2026-07-28

### Added

- **`jnv` — interactive JSON explorer.** `00-tools.zsh` now detects `jnv` and sets
  `HAVE_JNV`: a dual-pane jq-filter editor + collapsible JSON viewer that fills the
  "explore an unfamiliar API/JSON response" gap between `jq` (transform), `gron`
  (grep), and `yq` (YAML). It's its own command with no alias (like `jq`/`gron`/
  `ast-grep`) and is inert without the binary. A Rust CLI (embeds `jaq`, no external
  `jq` dependency). **Detect-only for now** — Core lights up `HAVE_JNV` when the binary
  is present, but `jnv` is not yet wired into any OS repo's `Brewfile`/`packages.txt`/
  `bootstrap.sh` (install it via `brew`/AUR/Nix or `cargo install --locked jnv`);
  fleet auto-install is a tracked follow-up. New `PORTING-MATRIX.md` row and footnote.
  (`zsh/00-tools.zsh`, `zsh/20-aliases.zsh`, `PORTING-MATRIX.md`)

### Fixed

- **`fleet-drift` false red on `dotfiles-Windows`.** The sweep measures every repo
  against the latest Core **release tag**, but `dotfiles-Windows` vendors only the
  `nvim/` subtree and tracks Core's **main tip** (synced by the nvim-sync bot, which
  re-stamps its marker only when `nvim/` actually changes). So its recorded commit can
  legitimately be a _descendant_ of the release tag (an unreleased `nvim/` commit pulled
  between releases) or an _ancestor_ of it (a release that changed no `nvim/` files
  leaves the marker behind while the vendored tree is byte-identical) — and the old
  commit-vs-tag comparison flagged both as drift, failing the run and filing a spurious
  ci-failure issue. `dotfiles-Windows` is now judged against `nvim/`'s last change
  reachable from the reference (`git rev-list -1 REF -- nvim`), so both states read as
  current while a genuinely stale `nvim/` tree still fails. (`scripts/fleet-drift.sh`)
- **alpha-nvim greeter crash on `nvim` launch.** The dashboard footer was built by
  assigning raw strings into startify's `footer` section, but that section is a
  `group` whose `val` must hold element tables — alpha then called
  `layout_element[nil]` and threw a `VimEnter` autocommand error (nil-call at
  `alpha.lua:362`). The footer is now a `text` element, mutated in place so the
  layout's captured reference renders it. (`nvim/lua/gerrrt/plugins/alpha-nvim.lua`)
- **`PORTING-MATRIX.md` Alpine column caught up with `community`.** starship, yazi,
  tree-sitter-cli and viddy have landed in Alpine's `community` repo (native musl
  builds) since these rows were written — the matrix now shows the apk package for
  each instead of `script³`/`cargo³`, footnote ⁵ notes the `community` tree-sitter-cli
  is the musl build that clears the ≥ 0.26.1 floor, and footnotes ⁸/¹⁶ drop the stale
  "not in Alpine" claim for jujutsu/viddy. Availability doc only; `dotfiles-Alpine`
  carries the matching `packages.txt` move. (`PORTING-MATRIX.md`)
- **`PORTING-MATRIX.md` openSUSE `yq` corrected to the Go-install path.** The row
  claimed stock `yq` on openSUSE is mikefarah's Go build, but the main OSS `yq` is
  kislyuk's separate **Python** `yq` (the Go build ships only from a personal OBS
  repo) — so a stock `zypper in yq` lands the wrong tool. The openSUSE cell is now
  `go³` and footnote ⁶ explains it; `dotfiles-openSUSE` go-installs the mikefarah
  build in `bootstrap.sh` alongside doggo/carapace/sesh. (`PORTING-MATRIX.md`)

### Security

- **Container digest-pin rule now covers every image surface, tightly.** Rule 4 in
  `check-modern.sh` only anchored on an `image:` value or a `docker run|build|pull`
  command, so an unpinned `container: node:20` shorthand or a `uses: docker://alpine:3.21`
  container action slipped the floor — neither is `owner/repo@sha` form, so the action
  sha-pin rule (3) misses them too. The rule now extracts the single image reference from
  each clean surface (`image:`, `container:` shorthand, `uses: docker://`) and requires an
  `@sha256:` digest on it: this also catches a bare `container: alpine` / `docker://alpine`
  (implicit mutable `latest`, which a `name:tag` regex missed) and correctly accepts a
  digest-only `alpine@sha256:…` (previously mis-flagged), while `docker run` keeps its
  tolerant token scan. No live violations in the fleet today — pre-emptive, closing the gap
  before an OS/role repo (which inherit the `*-call.yml@v3` workflows) reaches for one.
  (`scripts/check-modern.sh`,
  `scripts/modern-baseline.yml`)

## [v4.4.0] - 2026-07-27

### Added

- **Terminal web browser wiring.** `00-tools.zsh` now resolves a `BROWSER_BIN`
  (prefers `w3m`, falls back to any present `lynx`/`links2`/`links`/`elinks`) and
  sets `HAVE_BROWSER`. `20-aliases.zsh` exposes a `web` verb everywhere the browser
  is present, and exports `$BROWSER` **only on a headless box** (no `$DISPLAY`/
  `$WAYLAND_DISPLAY`, non-macOS) so GUI-opening tools aren't hijacked on a desktop.
  The OS repos add `w3m` to their package lists. (`zsh/00-tools.zsh`,
  `zsh/20-aliases.zsh`)

## [v4.3.0] - 2026-07-25

### Changed

- **Linters now run on file open, not only on save.** nvim-lint fired only on
  `BufWritePost`/`InsertLeave`, so an opened file showed no lint diagnostics until you
  saved it or toggled in/out of insert mode. Added `BufReadPost` to the trigger events
  (plus a one-shot replay of the first buffer, which loads just after its own
  `BufReadPost`), so diagnostics surface on open. Heavy whole-package/repo linters
  (golangci-lint, cpplint, checkstyle, phpstan, sqlfluff, tflint, semgrep) stay
  save-only — they run on `BufWritePost` and nowhere else.
  (`nvim/lua/gerrrt/plugins/nvim-lint.lua`)

### Removed

- **Dropped Nix language support** (added in v4.2.0) — unused in practice, and the only
  language of that batch with ongoing install cost. Removed the `nil_ls` server config,
  the `alejandra` formatter, the `statix` linter, the `nix` treesitter parser, and the
  `alejandra`/`statix` Mason packages (so they no longer install on every box). No `.nix`
  tooling remains; re-add per the v4.2.0 pattern if Nix ever comes back.
  (`nvim/lua/gerrrt/servers/nil_ls.lua`, `nvim/lua/gerrrt/servers/init.lua`,
  `nvim/lua/gerrrt/plugins/{conform,nvim-lint,nvim-treesitter,mason-tool-installer}.lua`)

### Fixed

- **Cleared the rustaceanvim `vim.lsp.get_buffers_by_client_id()` deprecation warning
  (removed in Nvim 0.13).** The v6 line still calls it, so the fix required bumping the
  version spec from `^6` to `^8` (the fix landed in v7.0.0) and the lockfile to v8.0.5.
  Chose `^8` over `^9` on purpose — v9's only breaking change is dropping Neovim 0.11
  support, and Core vendors to a fleet that may not all be on 0.12; v8 keeps the fix and
  `neovim >= 0.11`. The v7/v8 breaking changes (ra-multiplex → lspmux, drop
  `.vscode/settings.json`) don't affect this config. (The remaining `vim.validate{}`
  warning is from diffview.nvim, which upstream hasn't fixed — removal isn't until
  Nvim 1.0, so it's benign.)
  (`nvim/lua/gerrrt/plugins/rustaceanvim.lua`, `nvim/lazy-lock.json`)

## [v4.2.0] - 2026-07-24

### Added

- **Ten new languages get the full editor toolchain — Ruby, Java, Kotlin, PHP, Zig,
  SQL, Protobuf, GraphQL, Terraform/HCL, and Nix.** Each gains an LSP server
  (`nvim/lua/gerrrt/servers/*.lua`, enabled through `servers/init.lua`), a formatter
  (`nvim/lua/gerrrt/plugins/conform.lua`), a treesitter parser
  (`nvim/lua/gerrrt/plugins/nvim-treesitter.lua`), and — where one fits — a linter
  (`nvim/lua/gerrrt/plugins/nvim-lint.lua`). New Mason packages are declared in
  `nvim/lua/gerrrt/plugins/mason-tool-installer.lua`; runtime-dependent installers
  (Ruby/JVM/PHP tools) degrade gracefully via the existing binary-guard. `ruby_lsp`
  and `jdtls` are registered in `servers/init.lua`'s `fn_cmd_binaries` because
  lspconfig ships their `cmd` as a function.

- **SAST via semgrep**, wired as a gated `nvim-lint` linter for the security-relevant
  filetypes — it runs only when a project `.semgrep.yml`/`.semgrep.yaml` is present, so
  it never triggers a network `--config auto` fetch. (`nvim/lua/gerrrt/plugins/nvim-lint.lua`,
  `mason-tool-installer.lua`)

- **Solidity formatting** (`forge fmt`) closes the one prior formatter gap, and
  SCSS/LESS join the prettierd map. (`nvim/lua/gerrrt/plugins/conform.lua`)

- **Broader `<leader>cn` docgen conventions** (rust/go/java/php/ruby/c/cpp/lua) added to
  neogen. (`nvim/lua/gerrrt/plugins/neogen.lua`)

### Fixed

- **`nvim-lint` now lints compound filetypes.** The runner matched only the exact
  `filetype`, so dotted filetypes like `yaml.ansible` or a Helm `yaml.gotmpl` were never
  linted (conform, which splits on `.`, still formatted them). The autocmd now resolves
  linters across every filetype component and generalises the per-linter config-gating.
  (`nvim/lua/gerrrt/plugins/nvim-lint.lua`)

- **Cleared the remaining `:checkhealth` warnings.** Disabled render-markdown's unused
  LaTeX support (three warnings for an uninstalled latex parser + pylatexenc CLIs) and
  dropped the unregistered `markdown.mdx` filetype from marksman.
  (`nvim/lua/gerrrt/plugins/render-markdown.lua`, `nvim/lua/gerrrt/servers/marksman.lua`)

- **The sesh session picker no longer prints raw ANSI codes around its icons.**
  `sesh list --icons` colour-codes its glyphs (blue for sessions/tmux, cyan for zoxide
  dirs), but the two `fzf` callers lacked `--ansi`, so the escape sequences rendered
  literally (`[34m…[39m`) instead of colouring the icon. Added `--ansi` to both entry
  points — the Ctrl-G shell widget and the `prefix+f` tmux picker.
  (`zsh/35-fzf.zsh`, `tmux/scripts/tmux-sesh.sh`)

## [v4.1.0] - 2026-07-23

### Changed

- **Forced a steady block cursor in tmux.** `tmux/tmux.conf` now sets
  `cursor-style block`, so panes render a non-blinking block cursor regardless of
  the terminal's own default. (`tmux/tmux.conf`)

- **Bumped the pinned Python and Ruby runtimes off their security-only lines.**
  `mise/config.toml`: `python = "3.12"` → `"3.14"` and `ruby = "3.3"` → `"3.4"`.
  Both pins had aged into security-only maintenance, so they no longer receive
  bugfix releases: Python 3.12's bugfix window ended ~2025-04 (security-only until
  2028-10), and Ruby 3.3 dropped to security maintenance on 2026-04-01 (EOL
  ~2027-03). Targets chosen for runway, not just currency: **Python 3.14** (GA
  2025-10-07) has bugfix support through 2027-10 — 3.13 was skipped because its
  bugfix window ends 2026-10-06, only months out; **Ruby 3.4** (GA 2024-12-25) is
  in normal maintenance (the next line is 4.0, too fresh to point security tooling
  at). Both are supported by the pentest tooling the intent comments name
  (impacket/bloodhound-python, evil-winrm). Java (`temurin-21`, still a current
  LTS) and Lua (`5.4`, current stable) stay put. Regenerate `mise.lock` on a real
  box with `mise install` after syncing. (`mise/config.toml`)

### Added

- **New `/runtime-freshness` routine.** On-demand `.claude/` routine (report-first,
  like `/freshness-triage`) that decides whether the _pinned_ runtimes in
  `mise/config.toml` (python/ruby/java/lua) are due to cross a pin — weighing EOL
  calendars and tooling compatibility, the judgment the maint job's `mise outdated
  --bump` nudge can't make. Registered in `CLAUDE.md`'s routines list.
  (`.claude/commands/runtime-freshness.md`)

- **Scheduled maintenance now surfaces cross-pin runtime bumps.** `mise upgrade`
  keeps each runtime current only _within_ its configured constraint
  (`python = "3.12"` tracks 3.12.x); crossing a pin to a new minor/major is a
  deliberate call and stays manual. The daily runner now logs `mise outdated
  --bump` after the upgrade step — a report-only nudge listing runtimes with a
  newer version available beyond their pin (apply with `mise up --bump <tool>`),
  mirroring the existing "system packages: N upgradable (apply with `up`)" line.
  (`maint/dotfiles-maint.sh`)

### Fixed

- **Scheduled maintenance now advances the Rust toolchain.** The daily runner ran
  `mise upgrade --yes`, but mise's rust support delegates to rustup (it sets
  `RUSTUP_TOOLCHAIN` rather than installing a standalone toolchain), so a rolling
  channel like `mise/config.toml`'s `rust = "stable"` reads as always-satisfied —
  `mise upgrade` never moved it forward and Rust silently fell behind until someone
  ran `rustup update` by hand. `dotfiles-maint.sh` now runs `rustup update` after
  the mise step, guarded on `have rustup` (no-op where the package manager owns
  rust and rustup isn't installed) and time-limited by `MAINT_RUSTUP_TIMEOUT`
  (default 600s). (`maint/dotfiles-maint.sh`)

- **`sync-core.sh` summary now counts repos, not ✓ lines.** The footer printed the
  line-level `$PASS` counter as "updated" — the pre-flight audit ✓ plus two `ok()`
  per healthy repo (subtree pull + core.lock) — so a clean 8-repo fan-out reported
  "updated 17" (1 + 2×8), reading as if the sync had touched repos that don't
  exist. Worse, the count didn't even match the ✓ lines on screen: the guard-install
  ✓ came from `blib_ok`, which prints the same green check without incrementing
  `$PASS`. The headline row now tallies REPOS, each in exactly one bucket (updated /
  skipped / failed — failed wins if the repo printed any ✗), plus an "(of N
  targeted)" total; `blib_ok` is routed through the shared tally so the line-level
  counters on the second `checks:` row match the visible ✓/–/✗ lines one-for-one.
  (`scripts/sync-core.sh`)

- **nvim: first file opened in a bare session got no filetype — no syntax/treesitter
  highlighting, no LSP, no linter.** When Neovim started without a file argument
  (dashboard, `nvim` then `:e`, any picker), the first real buffer's `BufReadPost`
  fired `User FilePost` synchronously, loading nvim-lspconfig _inside_ that autocmd
  chain. `vim.lsp.enable()`'s post-startup `doautoall … FileType` replay set Vim's
  global `did_filetype` flag mid-chain, so when the runtime's `filetypedetect`
  handler (registered after ours) reached `:setf`, it was a documented no-op — the
  buffer ended up with an empty filetype and nothing keyed off `FileType` ever ran.
  Every _subsequent_ buffer worked (the FilePost augroup had self-deleted), which is
  why the bug looked like "the first file is dead until I open a second one".
  `nvim <file>` startups were unaffected (FilePost fires at `UIEnter` there, outside
  any read chain). Fix: fire FilePost via `vim.schedule()` so the deferred-plugin
  burst lands after the read chain completes — filetype detection runs unpoisoned,
  and the exactly-once contract is preserved by deleting the augroup _before_
  scheduling. The D3 contract test now also asserts the first file ends up with a
  non-empty filetype, simulating vim.lsp.enable's group-scoped FileType replay in
  the hermetic probe so the poisoning path stays covered (verified red on the
  pre-fix code, green after). (`nvim/lua/gerrrt/config/autocmds.lua`,
  `scripts/test-core.sh`)

## [v4.0.2] - 2026-07-21

### Added

- **`aliases.md` documents the shell functions, not just the aliases.** The cheat sheet
  covered `zsh/20-aliases.zsh`/`25-git.zsh` but said nothing about the user-facing
  functions in `zsh/30-functions.zsh`, deferring them to `core help` — so the one
  reference people actually open omitted nine commands they type daily. New **Shell
  Functions** section covering `mkcd`, `cdup`, `fcd`, `extract`, `mkbak`, `serve`,
  `genpw`, `please`, and `pullall`, plus the `cdup`-vs-`up` naming trap and the
  fail-safe (no-TTY declines) behaviour of the `extract`/`please` confirmations. Each row
  reuses that function's own `_core_help` one-liner verbatim, so the doc and the
  `--help`/`core help` output can't drift apart. Docs only — no behavior change.

### Changed

- **Docs/comments: finish the v4 numbered-fragment rename.** The v4.0.0 rename moved the
  files and updated the manifest/docs but left the pre-v4 flat names (`tools.zsh`,
  `plugins.zsh`, …) scattered through the fragments' own cross-reference comments and a
  few dev scripts. Renumbered them all to the `NN-name.zsh` form — every fragment's
  self-header and every "loads after `10-options.zsh`" / "guarded by `00-tools.zsh`"
  comment across `zsh/*.zsh`, plus `bench-core.sh`, `audit-core.sh`, `update-plugins.sh`,
  `ci.yml`, `lib/ux.sh`, `jujutsu/config.toml`, and others. Deliberately left untouched:
  historical `CHANGELOG.md` entries, `V4-PROPOSAL.md`, and the intentional pre-v4 names in
  the migration path (`bootstrap-lib.sh`'s stale-symlink cleanup, `test-core.sh`'s migration
  fixtures). Also: `aliases.md` gains a **Named Directories** section for the `~dots`/`~proj`
  `hash -d` shortcuts, and `PORTING-MATRIX.md` clarifies that `Defense` is a distro-agnostic
  Role repo (absent from the OS-stamp table by design, not omission). Comment/doc only —
  no behavior change.

### Security

- **`actions/checkout` no longer leaves the job token in `.git/config` on 32 of 35 steps.**
  Checkout persists the token by default, so any later step in the job — a third-party
  linter, a scripted tool, one of the LLM routines reading the tree — can read it back out
  of the working copy. Every checkout in the repo now states `persist-credentials:`
  explicitly: `false` on the 32 that only read code, `true` on the three that genuinely
  push (auto-tag's tag push and the freshness bot's two branch pushes), each carrying a
  comment saying why. The eight `claude-routines` checkouts are the biggest win — those
  jobs run an agent over repository content, so the persisted token was a standing
  exfiltration target alongside the `--allowedTools` restriction already in place. Enforced
  by a new `require_explicit_persist_credentials` dimension in
  `scripts/modern-baseline.yml`; `check-modern.sh` associates each `with:` block with its
  own `uses:` by walking step bounds, so a `persist-credentials:` on a neighbouring step
  cannot satisfy the rule. Requiring the _key_ rather than the _value_ `false` is what
  keeps the pushers' exemptions at the call site instead of in a drift-prone list.
- **CI floor raised: every workflow must declare a top-level `permissions:` block, and the
  node20 opt-out is banned.** Two additions to `scripts/modern-baseline.yml`, both of which
  the fleet already satisfied — this encodes existing practice as a floor rather than asking
  for a migration. (1) New `require_workflow_permissions` dimension: without a top-level
  block a job inherits the repo-wide default token scope, so naming it makes the
  least-privilege grant a deliberate, reviewable line. `check-modern.sh` anchors the match at
  column 0 — a job-level `permissions:` narrows a default, it doesn't establish one — and
  scopes the rule to `.github/workflows/` since the key is invalid in a composite
  `action.yml`. (2) `ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION` joins `banned_patterns`: it
  forces a node20 action to keep running on node20, which stops working outright when node20
  leaves the runners in fall 2026, so it's a dead end worth closing before something lands on
  it. Fleet-wide via the `lint-call.yml@v3` reusable workflow the OS repos inherit.

## [v4.0.1] - 2026-07-20

### Fixed

- **`loader.zsh` profile resolution reads only the first field of `$ZSH_CFG/profile`.**
  A trailing space or stray extra token in the profile one-liner previously landed in
  `CORE_PROFILE` verbatim, so the `case` matched no arm and silently fell through to
  `full`. `read -r CORE_PROFILE _ < …` now takes just the first word (and trims
  surrounding whitespace), so a slightly-malformed one-liner still resolves to the
  intended profile. Also clarified the loader header comment: `CORE_PROFILE` is
  deliberately left in scope after sourcing (so subshells and the user can read the
  active profile), not only the `_cl_*` scratch vars.

## [v4.0.0] - 2026-07-20

### Added

- **`CORE_PROFILE` (`minimal` / `standard` / `full`).** Selects which
  Core-band fragments (`00`–`69`) the loader sources — `minimal` stops after `30-functions`,
  `standard` after `50-op`, `full` loads all Core — so a headless box can skip the
  interactive-heavy stages `minimal` omits: fzf widgets (`35`), vi-mode bindings (`40`), the
  plugin stack (`45` — autosuggestions/syntax-highlighting/carapace/fzf-tab), the 1Password
  helpers (`50`), and the maintenance + update surface (`55`/`60`). (Atuin/history and the
  aliases live in `00`–`30`, so they still load under `minimal`.) It resolves from the
  environment or a `$ZSH_CFG/profile` one-liner, and gates **only** Core fragments;
  OS/role/host fragments (`>=70`) always load, so
  a lean profile never drops essential OS setup or `99-local.zsh`. It is a pure loader
  concern — install-time provisioning selection stays with `bootstrap.sh`'s existing
  `--only`/`--skip` (`blib_want`) groups, so `bootstrap.sh --only zsh` + `CORE_PROFILE=minimal`
  compose orthogonally. Defaults to `full` (today's behaviour).
- **Neovim: debugging via `nvim-dap` + `nvim-dap-python`.** Breakpoints, stepping, and variable
  inspection under a new `<leader>d` which-key group, with palette-aware gutter signs and rows in
  the cheatsheet. Loaded on its keymaps and `Dap*` commands **only** — it costs nothing at startup
  and nothing on file open, not even the `User FilePost` hook. That required turning off
  rustaceanvim's `dap.autoload_configurations` (on by default): it calls `require('dap')` on
  rust-analyzer attach, which lazy.nvim module-autoloads, so merely opening a `.rs` file pulled in
  the whole DAP stack and could kick off background `cargo` work. The tradeoff is explicit — a bare
  `<leader>dc` no longer sees rust-analyzer's debuggables, so Rust sessions start from the new
  `<leader>dR` (`:RustLsp debuggables`), after which the normal `<leader>d*` keys apply.
  `nvim-dap-ui` is deliberately not
  included: `dap.ui.widgets` covers scopes/frames/hover (`<leader>ds`/`df`/`dw`) without the extra
  plugin, its `nvim-nio` dependency, or session-driven window management. The debug adapter is
  resolved most-preferred-first — Mason's `debugpy` if you installed it, then `uv`, then
  `python3`. `debugpy` is deliberately **not** in `ensure_installed`: Mason's PyPI installer always
  runs `python -m venv` then pip, so listing it would fail the install pass on every startup on the
  Debian/Kali and Alpine hosts that lack `python3-venv`/`py3-pip` — the exact dependency the `uv`
  fallback exists to avoid. Install it by hand with `:MasonInstall debugpy` where you want it. Verified end to end on a real session via the `uv` path: breakpoint hit,
  frame `add @ line 2`, locals `a = 2` / `b = 3`.
  This also revives `plugins/rustaceanvim.lua`'s DAP adapter block, which was dead code — it needs
  `nvim-dap` present, and `nvim-dap` was never installed.
- **Neovim: the statusline shows the active Python virtual environment.** A new block left of the
  LSP server list renders the uv/venv name (`.venv`) in Python buffers, resolving
  `VIRTUAL_ENV` → `UV_PROJECT_ENVIRONMENT` → `<project root>/.venv`, probing `pyvenv.cfg` so it is
  correct on every platform. Absolute `UV_PROJECT_ENVIRONMENT` values are detected in all three
  forms — POSIX `/…`, Windows drive-qualified `C:\…`, and UNC `\\server\share` — since a
  leading-`/` test alone would misread the latter two as relative and silently report the wrong env. It walks upward from the buffer, so a file in a subdirectory still
  reports the project's env, and it collapses to nothing outside Python so no width is spent
  elsewhere. The lookup is memoised in `vim.b` — a statusline component is re-evaluated on every
  redraw, so the filesystem walk runs once per buffer, never inline. Display only: it does not
  configure ty, which already discovers `.venv` on its own.

### Removed

- **Neovim: the `matchparen`, `rplugin` and `spellfile` runtime plugins are no longer sourced**, and
  `showmatch` is no longer set. `matchparen` was the costly one: it registers 10 autocmds, three of
  which (`CursorMovedI`, `TextChangedI`, `TextChangedP`) re-scan for a matching bracket on _every
  keystroke_ in insert mode. `showmatch` doubled that from the other side — it does not highlight
  the match, it jumps the cursor to it for `matchtime` tenths of a second every time you type a
  closing bracket. `rplugin` (remote-plugin manifest) is dead weight with the perl/ruby providers
  already off, and `spellfile` auto-downloads spellfiles over the network — unwanted generally and
  wrong on a `DOTFILES_OFFLINE` box. **`%` is unaffected**: `matchit` (extended `%` over
  `if`/`end`, tags, …) and `editorconfig` are deliberately kept, and both the matchit and builtin
  `%` motions were verified identical before and after. What this does give up is the automatic
  highlight of the bracket paired with the one under the cursor — `rainbow-delimiters` colors by
  nesting depth and only where a treesitter parser is installed, so it is a different cue, not a
  replacement. NvChad disables 26 runtime plugins including
  `matchit`; that list is not copied — each entry here carries a stated reason.

### Changed

- **BREAKING (v4.0.0) — loader & layout overhaul.** Core's zsh modules are renamed to
  numbered fragments (`00-tools` … `60-update`), and the loader (`zsh/loader.zsh`) now
  globs `NN-*.zsh` in `$ZSH_CFG`, sorts by the `NN` prefix, and sources each — replacing
  the hand-declared `_CORE_MODULES` name array an OS `.zshrc` used to pass. The `NN`
  prefix is the ordering contract; bands are Core `00`–`69`, OS-native `70`–`84`, role
  `85`–`94`, host-local `95`–`99` (the OS layer is now `80-os.zsh`, a role stage `85-*.zsh`,
  host tweaks `99-local.zsh`). A layer may still place a fragment in a Core gap to run
  mid-chain, but gating and ordering key off the `NN` number, not authorship: a fragment in
  `00`–`69` is profile-gated as Core (number always-load setup `>=70`), and a same-`NN` tie
  breaks lexically by filename. This aligns the zsh module structure with the
  PowerShell host layer's `NN-name` convention (`PARITY.md`). **Every OS/Role repo must
  re-vendor and update its `bootstrap.sh` loader stanza** — `blib_write_zshrc_loader` now
  emits a stanza that simply `source`s `$ZSH_CFG/loader.zsh` (managed marker
  `dotfiles-managed v4`) and takes no module list; it deliberately does **not** assign
  `CORE_PROFILE`, leaving resolution to the loader (env → `$ZSH_CFG/profile` one-liner →
  `full`). `blib_migrate_v4` relocates the pre-v4 layout automatically on re-bootstrap.
  Design + per-repo runbook in `V4-PROPOSAL.md`.
- **BREAKING (v4.0.0) — mutable zsh state moves to XDG dirs.** History
  (`$XDG_STATE_HOME/zsh/history`), the completion dump (`$XDG_CACHE_HOME/zsh/zcompdump`),
  and plugins (`$XDG_DATA_HOME/zsh/plugins`) leave the symlinked `$ZDOTDIR` config tree,
  which now holds config **plus** the byte-compiled `.zwc` wordcode written beside each
  fragment symlink — the one deliberate exception, because that is how zsh's automatic
  wordcode pickup works (`source file` loads `file.zwc` only when it sits beside `file`).
  `bootstrap.sh` (`blib_migrate_v4`) relocates an existing `~/.config/zsh/.zsh_history`,
  `plugins/`, and drops the stale pre-v4 symlinks/compdump on re-bootstrap so nothing is
  lost. Hosts must **re-bootstrap**, not just re-source.
- **Neovim: statusline components now read the statusline's window, not the current one.** With
  `globalstatus = true` one bar is shared by every window, so `bufnr = 0` was subtly wrong whenever
  the bar was redrawn for a window you weren't in. Custom components now resolve through
  `vim.g.statusline_winid` (the discipline NvChad's `stl/utils.lua` uses). The attached-server list
  is also width-gated at 100 columns, since the diagnostic counts beside it carry the actionable
  information on a narrow window.
- **Neovim: LSP server modules are now plain config tables, and the server list exists once.**
  Each `lua/gerrrt/servers/<name>.lua` returned a `function(capabilities)` factory that called
  `vim.lsp.config()` itself; `servers/init.lua` then invoked all 19 by hand and re-listed the same
  19 names in a separate `wanted` table, so every name was written twice. The leaves are now pure
  data, capabilities are advertised once on the `vim.lsp.config("*")` wildcard, and one `servers`
  list drives both registration and enabling. `utils/lsp.lua`'s `with_snippets()` is gone —
  html/cssls set only the `snippetSupport` leaf and inherit the rest via the wildcard deep-merge.
  Verified by diffing the fully-resolved config of all 19 servers before and after: **identical**.
  Note the configs deliberately stay on explicit `vim.lsp.config(name, …)` calls rather than moving
  to `lsp/<name>.lua` on the runtimepath: rtp files are merged in rtp order with the user config dir
  _first_, so nvim-lspconfig's own `lsp/<name>.lua` would override ours (verified — a probe setting
  `cmd = { "PROBE_CMD" }` resolved to `cmd = { "gopls" }`). Explicit calls always win.
  `scripts/test-core.sh` is updated to assert the new contract (a non-empty table, not a function).
- **Neovim: the SchemaStore catalogues are no longer built unconditionally.** `servers/jsonls.lua`
  and `servers/yamlls.lua` resolved `require("schemastore").{json,yaml}.schemas()` inline in their
  `settings`, which ran while the server was being _configured_ — and `servers/init.lua` configures
  all 19 servers in one pass. That pass runs **once per session** (the `User FilePost` loader is
  one-shot), so the cost was not per-buffer; the problem is that it was paid **regardless of
  filetype** — a session that only ever opens Lua files still materialised the entire 1,368-entry
  JSON schema catalogue. Both now resolve it in `before_init`, which Neovim runs once per client
  instance, so the cost lands only when a jsonls/yamlls client actually starts. Verified: a Lua
  buffer no longer loads the `schemastore` module at all, a JSON buffer still gets all 1,368 schemas.
- **Neovim: treesitter's installed-parser lookup is cached.** `get_installed()` walks two install
  directories off disk (~0.19ms) and returns a fresh list; it was called inside the `FileType`
  callback and then scanned linearly, so every buffer open paid a directory walk plus an O(n)
  search. It is now built once into a set and answered by hash lookup, and invalidated on every
  parser mutation — including `:TSInstall`/`:TSUpdate`/`:TSUninstall`, which bypass the plugin's own
  install entry point — so the set can never go stale against what is on disk.
- **Neovim: `lazy.nvim` now defaults specs to `lazy = true`.** Every spec is already covered — most
  declare an `event`/`ft`/`cmd`/`keys` trigger, and the pure-data/dependency specs
  (`webdev-icons.lua`, `schemastore.lua`, the luvit-meta entry in `lazydev-nvim.lua`) declare
  `lazy = true` explicitly and load via `require` or another spec's `dependencies`. So the
  loaded-plugin set is byte-identical before and after (verified, 25 plugins on first file open).
  This is a regression net: a future spec added with neither a trigger nor an explicit `lazy` stays
  lazy instead of silently landing on the startup path.

- **Neovim: file-plugins now load after the UI is ready (`User FilePost`)** — `nvim-lspconfig`,
  `gitsigns`, `nvim-lint` and `todo-comments` hung off `BufReadPre`/`BufReadPost`, which fire
  _before_ Neovim finishes starting. Measured on a real TTY, `BufReadPost` lands at ~44ms while the
  UI isn't ready until ~131ms, so ~87ms of plugin work sat in front of the editor appearing. A new
  self-deleting autocmd in `config/autocmds.lua` emits a `User FilePost` event once startup is done
  and a real file buffer is open, and those four specs now load on it.
  **Opening a file: 165.9ms → 99.0ms (-40%).** Bare `nvim` is unchanged (~37ms).
  The event waits for `UIEnter` when a UI exists, and falls back to `VimEnter` only when there is
  genuinely no UI (`nvim --headless`), where `UIEnter` never fires — gating on `UIEnter` alone (as
  NvChad does) would silently disable LSP, linting and git signs in every headless/CI session,
  including this repo's own audit, while accepting `VimEnter` in a TTY would fire ~5ms early and pull
  the plugins back in front of the first paint. `scripts/test-core.sh` asserts the exactly-once
  contract in both startup shapes. No `FileType` replay is needed; each of the
  four self-attaches to already-open buffers (`vim.lsp.enable()` re-runs `doautoall`, gitsigns
  iterates `nvim_list_bufs()`, todo-comments attaches to visible windows, nvim-lint is write-driven).

### Fixed

- **Neovim: focusing the file tree blanked the whole statusline.** `plugins/lualine-nvim.lua` set
  both `disabled_filetypes = { statusline = { "NvimTree" } }` and `extensions = { "nvim-tree", … }`.
  lualine evaluates `disabled_filetypes` and returns `nil` **before** it consults extensions
  (`lualine.nvim/lua/lualine.lua:298-306`), so the `nvim-tree` extension was permanently unreachable
  — and because `globalstatus = true` means one shared bar, that `nil` blanked the statusline for
  _every_ window whenever the tree held focus. Dropped the disable and kept the extension. Verified:
  with `ft=NvimTree` focused, `lualine.statusline()` returned `nil` before, renders 81 cells now.
- **Neovim: visual-mode git staging silently staged the entire hunk.** `<leader>gs` / `<leader>gr`
  were mapped in `{ "n", "v" }` to bare `gs.stage_hunk` / `gs.reset_hunk`. `range` is the **first**
  parameter of both (`gitsigns.nvim/lua/gitsigns/actions.lua:288`, `:376`) and a Lua keymap rhs is
  invoked with no arguments, so `range` was always `nil` — partial-hunk staging, the only reason to
  map visual mode, never happened. (Nothing reads the visual selection implicitly; only the
  `:Gitsigns` command wrapper populates `range`, from command modifiers.) Normal and visual are now
  separate mappings, with the visual pair passing `{ line("."), line("v") }` — upstream's documented
  form — and bound to `x` rather than `v` so they do not also fire in select-mode. Verified end to
  end in a real repo: staging lines 2-3 of a 3-line hunk staged exactly those two.
- **Neovim: the Node.js and python3 providers are disabled, clearing the config's only health
  warning.** The node provider's sole consumers are remote plugins, but `config/lazy.lua` disables
  the `rplugin` manifest loader, no installed plugin ships a manifest, and nothing references
  `node_host` — so it was unreachable while still emitting a permanent `:checkhealth` WARNING.
  python3 goes too: `vimade` is the only thing in the tree that mentions python, and it never
  reaches that path here. `vimade#SetupRenderer()` (`vimade/autoload/vimade.vim:30-43`)
  short-circuits to the Lua renderer whenever `renderer == 'auto'` and `supports_lua_renderer`, and
  only the _else_ branch calls `SetupPython()`; `supports_lua_renderer` needs
  `nvim_get_hl` + `nvim_win_set_hl_ns`, present since 0.11, and nvim-treesitter's main branch
  already hard-requires 0.12 here — so the python fallback is unreachable. Confirmed at runtime:
  `ACTIVE renderer = lua`, `vimade_python_setup = 0`, and `has('python3')` was never evaluated.
  (nvim-dap-python spawns debugpy as an external DAP adapter — a subprocess, not this provider.)
  Disabling both makes the cleanup portable: otherwise any fleet machine without `pynvim` keeps
  emitting the same warning. `:checkhealth` is now **0 errors, 0 warnings** across every section.
- **Neovim: `gsn` (surround `update_n_lines`) never existed.** `plugins/mini-nvim.lua` passed
  `update_n_lines = "gsn"` in mini.surround's `mappings`, but that is not a key in its schema
  (`add`/`delete`/`find`/`find_left`/`highlight`/`replace`/`suffix_last`/`suffix_next`) and unknown
  keys are accepted silently — `setup()` returned OK and no mapping was created, while every other
  `gs*` map did exist. Mapped explicitly instead, as upstream's own docs prescribe
  (`mini/surround.lua:909`), so the prefix the file advertises is real.

- **Neovim: SchemaStore catalogues never reached `jsonls` or `yamlls`.** Both resolved their
  schemas in `before_init` by re-binding `config.settings` with `vim.tbl_deep_extend`. The client
  binds `client.settings = config.settings` in `Client.create()` (runtime
  `lua/vim/lsp/client.lua:409`) **before** `before_init` runs (`:571`), and `tbl_deep_extend`
  returns a _new_ table — so the client kept the original and the catalogue was silently dropped.
  Both delivery paths (`workspace/didChangeConfiguration` push and the `lookup_section` pull) read
  `client.settings`. `yamlls` was the worse case: it disables its own built-in store
  (`schemaStore.enable = false`) and so ended up with _neither_ catalogue. Now mutated in place.
  Verified live: `jsonls` 0 → **1368** schemas, `yamlls` 0 → **1279** with the built-in store still
  off. Note Neovim's own docs demonstrate the broken re-binding form (`client.lua:36-41`).
- **Neovim: the `gr*` default-keymap cleanup deleted nothing, so `gr` still waited `timeoutlen`.**
  `utils/lsp.lua` called `vim.keymap.del("n", lhs, { buffer = bufnr })`, but Neovim creates
  `grn`/`gra`/`grr`/`gri`/`grt`/`grx` as **global** maps (`lua/vim/_core/defaults.lua`). Every
  delete raised `E31: No such mapping`, swallowed by the `pcall`. Dropped the `buffer` key, added
  the two 0.12 additions (`grt`, `grx`) that were missing, and hoisted the loop out of `on_attach`
  — it is global state that was being re-attempted per attaching client (twice on a Python buffer:
  `ruff` + `ty`). Verified: all six now report unmapped after boot. `grx` (`vim.lsp.codelens.run`)
  was the one default with no existing equivalent in this config, so it gains a replacement under
  the `<leader>c` "code" prefix: **`<leader>cL` runs CodeLens** (capital L — lowercase
  `<leader>cl` is Trouble's LSP refs/defs, and these maps are buffer-local, so taking it would have
  shadowed Trouble on every LSP-attached buffer). The others already had
  one (`grn` → `<leader>rn`, `gra` → `<leader>ca`, `grr` → `gr`, `gri` → `gi`, `grt` → `gy`).
- **Neovim: `binary_available()` was a no-op for `ts_ls`, `yamlls` and `tailwindcss`.** Current
  nvim-lspconfig ships `cmd` as a _function_ (a project-local `node_modules/.bin` probe) for those,
  and the guard's `type(cmd) ~= "table" → return true` branch waved them straight through. They
  were enabled unconditionally, still produced the recurring `spawn … ENOENT` the guard exists to
  suppress, and never appeared in the "LSP not enabled" notice. Now available if the well-known
  global binary is on `PATH` **or** a `node_modules/.bin/<binary>` is reachable from the cwd. Both
  tests are needed: those launchers prefer a project-local binary and only then fall back to the
  global one, but this enable pass runs before any client (so before `root_dir` exists) — answering
  "unavailable" means no client ever starts and the launcher never runs, so a global-only test would
  break the common "no global install, just a devDependency" layout. The local test is a heuristic
  and is deliberately biased to fail open.
- **Neovim: `mini.nvim` dragged the whole treesitter stack onto the startup path.** It declared
  `nvim-treesitter-textobjects` as a `dependencies` entry, and lazy.nvim loads dependencies _with_
  the parent — so mini's `VeryLazy` overrode the `BufReadPost`/`BufNewFile` trigger that both
  nvim-treesitter and -textobjects declare, running treesitter's parser-directory scan and possible
  `install` pass on the dashboard. Removed; mini.ai resolves the `textobjects` queries lazily at
  textobject-use time, by which point `BufReadPost` has loaded them. Measured in a real PTY: a bare
  `nvim` went from **13 loaded plugins to 11**, dropping ~15.5 ms of post-`UIEnter` work.
  (Time-to-`NVIM STARTED` is unchanged — this work always landed _after_ that marker.)
- **Neovim: `vim.hl.on_yank` is version-gated rather than hard-coded.** It is deprecated on Neovim
  HEAD (0.13-dev) in favour of `vim.hl.hl_op`, which does **not** exist on 0.12.4 — so a rename
  would break every machine still on stable. Probes for the new name and falls back, and the
  adjacent comment asserting "there is no `vim.hl.hl_op`" is corrected.
- **Neovim: `blink.cmp` is now a declared dependency of `nvim-lspconfig`.** `servers/init.lua`
  calls `require("blink.cmp").get_lsp_capabilities()`, which lazy's require-hook already pulled
  blink (and `friendly-snippets`) in at `User FilePost` — so blink's own `event = "InsertEnter"`
  was never the trigger that loaded it. This declares what already happened; it is not a speed-up,
  and blink cannot be deferred further because capabilities must be advertised in `initialize`.

### Changed (internal)

- **Neovim: the cheatsheet now covers what it claims to.** An audit against the real keymaps found
  the panel had drifted from the config it documents. Added a **Completion (blink.cmp)** card — the
  seven completion-menu keys had no row at all — and a **Move lines (mini.move)** card for
  `<A-hjkl>`, another whole feature that was absent. Also added `<leader>bn`/`bp`, `<leader>cl`
  (Trouble LSP refs/defs), `]t`/`[t`, `gsh` and `gsn`; corrected two descriptions (`<leader>rc` said
  "Edit init.lua" where the keymap's `desc` is "Edit config"; `<leader>e` dropped the load-bearing
  "closes Zen if active" side effect). The header's "EVERY curated binding" claim is now scoped to
  say what is deliberately excluded (transient-UI keys: the rename float, oil buffers, alpha's
  buttons, the panel's own `q`/`<Esc>`) rather than overstating.
- **Neovim: which-key names three prefixes that rendered as unnamed.** `<leader>r` (edit config,
  rename symbol), `<leader>o` (organize imports) and `<leader>p` (copy file path) had real children
  but no `group` entry. `<leader>p` is declared for normal mode only — in visual it is itself a
  mapping (paste-without-yank), not a prefix.
- **Neovim: removed dead and misleading plugin config.** Each verified against the installed plugin
  source, not assumed:
  - `bufferline`: dropped `hover.reveal = { "close" }`. `get_close_icon()`
    (`bufferline.nvim/lua/bufferline/ui.lua:263-270`) consults `reveal` and then unconditionally
    bails on `if not options.show_buffer_close_icons then return end` — which is `false` here, so
    there was never a close icon to reveal. `hover` stays on for hover highlighting.
  - `nvim-tree`: `view = { adaptive_size = true }` → `view = { width = {} }`. `adaptive_size` is a
    2023-01-15 legacy key that nvim-tree silently rewrites (`legacy.lua:73-81`); with no explicit
    width it produces `{ min = nil }`, i.e. `{}`. Verified equivalent by running the migration and
    comparing deep-equal. Note `{}` is not "unbounded" — nvim-tree fills the absent keys with its
    own defaults (`view-state.lua:5-6,77-78`), so the pane sizes to content but never narrower than
    30 columns; confirmed at runtime as `width = 30`, `max_width = -1`.
  - `fidget`: `winblend = 0` → `100` (its default). The old comment said this matched "transparent
    floats" — backwards; fidget's docs (`notification/window.lua:33-49`) describe `100` as the
    see-through setting and anything less as blending with what's underneath.
  - `nvim-treesitter-context`: dropped `separator = nil` — assigning `nil` in a table literal omits
    the key, and `nil` is already the default, so it read as a setting but did nothing.
  - `conform`: dropped a `config` function that re-implemented lazy.nvim's default for a spec with
    `opts`. Verified the 20 `formatters_by_ft` entries still apply without it.
  - `blink.cmp`: corrected a comment claiming the snippet keys use native `vim.snippet` — with
    `preset = "luasnip"` they route to LuaSnip; blink picks the engine by preset.
- **Neovim: `<leader>ha` refuses an unnamed buffer.** harpoon keys its list by file path, so adding
  a scratch buffer stored an unnavigable empty entry and toasted a bare `"Harpoon: added "`.
- **Neovim: `keymaps.lua` Ex-command maps use `<Cmd>…<CR>` instead of `:…<CR>`** (11 split/tab/
  resize maps). `:` switches to cmdline-mode first — it echoes, is subject to cmdline mappings and
  abbreviations, and clobbers a pending count or visual selection; `<Cmd>` does not.
- **Neovim: `<leader>pa` reports via `vim.notify`, not `print`**, so the copied path lands in the
  mini.notify toast like every other message instead of the message area (and no longer risks a
  hit-enter prompt on a long path). Also handles the no-file case.
- **Neovim: the `<LeftDrag>`/`<LeftRelease>` maps moved from `options.lua` to `keymaps.lua`**, and
  the undodir setup dropped two redundant `vim.fn.expand()` calls on an already-absolute
  `stdpath("state")` path (now built with `vim.fs.joinpath`).

## [v3.9.0] - 2026-07-19

### Added

- **Neovim: shared `utils/palette.lua`** — a single source of truth for the active tokyonight
  palette. The `"storm"` style string and the `require("tokyonight.colors").setup{}` pcall dance
  were duplicated across lualine, bufferline, and the cheatsheet; they now all resolve through this
  one module (change the style once). It also exposes a NvChad-`base_30` semantic map (`black2`,
  `statusline_bg`, `nord_blue`, `dark_purple`, …) so the block/pill styling is written in NvChad's
  own vocabulary while still tracking the theme.
- **Neovim: scroll-percentage indicator** in the lualine statusline (right bubble, next to the
  cursor location) so you can see how far through a file you are.
- **Neovim: NvChad-style inline LSP renamer** (`utils/renamer.lua`) — `<leader>rn` now opens a
  small cursor-anchored, git-red-bordered prompt prefilled with the symbol (`<CR>` applies across
  the workspace, `<Esc>`/`q` cancels) instead of the bare cmdline prompt.
- **Neovim: colorify-style colour highlighter** (`nvim-colorizer.lua`, catgoose fork) — inline
  colour swatches over the visible viewport: CSS colour literals (`#rrggbb`, `rgb()/hsl()`) plus
  Tailwind utility-class colours via the Tailwind LSP. ccc.nvim is kept for the interactive
  `:CccPick` picker (its always-on highlighter is now off).

### Changed

- **Neovim: statusline & tabline go hybrid-NvChad.** The bufferline adopts NvChad's tabufline model
  where buffer state is conveyed by BACKGROUND on a solid opaque bar — the active buffer lifts to a
  lighter raised block, inactive buffers recede to the bar colour — while the editor stays
  transparent. The blink.cmp menu gains NvChad's colored kind-icon column (via `BlinkCmpKind*`
  highlights) with an icon-left / kind-text-right layout. The `<leader>?` cheatsheet renders as a
  solid opaque card.
- **Neovim: signature help is owned by blink.cmp.** The manual `CursorHoldI`
  `vim.lsp.buf.signature_help` autocmd was removed — blink's own signature window handled the same
  case and the two floats could stack while idle. `<C-s>` stays as the manual trigger.
- **Neovim: the central Mason install manifest moved** out of conform.nvim (which is lazy on
  `BufWritePre`, so `run_on_start` really meant "on first save") into its own `VeryLazy`-loaded
  `plugins/mason-tool-installer.lua`, so a fresh box installs its toolchain near startup.

### Removed

- **Neovim: trimmed unused plugins** — the full in-editor **debugger stack** (nvim-dap,
  nvim-dap-ui, nvim-dap-virtual-text, mason-nvim-dap, and every `<leader>d*` keymap), the **test
  runner** (neotest + neotest-python/-golang), vim-dadbod (DB UI), incline.nvim (dropbar's winbar
  covers split identity), aerial.nvim (Trouble + fzf-lua + dropbar cover symbols), nvim-spectre,
  git-conflict.nvim, and mini.indentscope — along with their keymaps, which-key groups, and
  cheatsheet sections. (16 entries removed from `lazy-lock.json`, including transitive dependencies.)

### Fixed

- **Neovim: heavy linters no longer run on `InsertLeave`.** golangci-lint / cpplint scan the whole
  package per run; they are now restricted to `BufWritePost` (save-only) while fast per-file linters
  keep the snappier cadence.
- **Neovim: bash-language-server no longer emits `SC1071` on zsh.** Its built-in shellcheck
  integration is disabled (`bashIde.shellcheckPath = ""`) so zsh buffers keep completion/hover
  without the "shellcheck only supports sh/bash/…" phantom diagnostic.
- **Neovim: `:w` can't be broken by a missing mini.nvim.** The format-on-save
  `mini.trailspace.trim()` call is now pcall-guarded.

## [v3.8.0] - 2026-07-18

### Changed

- **Neovim UI moves to an NvChad-styled statusline + bufferline.** `lualine` now uses a
  hand-built theme derived from tokyonight's resolved palette (mode/location render as rounded
  accent **pills**, git/cwd as a lighter block, filename on the base run) instead of the bundled
  `tokyonight` theme — so the blocks read as opaque islands on the transparent bar and follow
  NvChad's structure. `bufferline` gains palette-aware highlights so the active buffer lifts as a
  subtle raised block with an accent underline while inactive buffers dim into the bar. Both are
  computed at plugin-load (pcall-guarded), so a fresh box falls back to the bundled/auto theming.
- **LSP hover, signature help, and the diagnostic float share one padded, rounded card style.**
  Hover/signature pass an explicit rounded border with width/height caps (a huge docstring becomes
  a tidy box); the diagnostic float drops its header row and gains a left pad + width cap.
  Signature help now also pops **automatically** when you rest inside a function's arguments
  (`CursorHoldI`, gated on server support, suppressed while the completion menu is open).
- **`which-key` and the `<leader>?` cheatsheet restyled to mirror NvChad's keymap visualizer.**
  which-key gets a minimal rounded, padded, left-aligned column popup with NvChad-palette colors
  (blue keys, red descriptions, green groups); the cheatsheet's category headings become
  full-width accent **pill** bars (cycling colors) with blue keys — both palette-aware, with a
  semantic-link fallback on a bare box.

### Fixed

- **Neovim `taplo` (TOML) root detection.** `root_markers` listed the glob `"*.toml"`, which
  `vim.fs.root`/`vim.fs.find` do not support — so it never matched and taplo always fell back to
  `.git`, giving a lone TOML file outside a repo a cwd root. Replaced with real manifest names
  (`pyproject.toml`, `Cargo.toml`, `foundry.toml`, `taplo.toml`, `.taplo.toml`, `.git`).
- **Neovim `<leader>oi` (organize imports) no longer binds where it can't work or races the
  formatter.** A server that ENUMERATES its code-action kinds without `source[.organizeImports]` is
  now skipped (so the map no longer silently no-ops on e.g. `lua_ls`); a server that only reports a
  bare `true` or a provider table without kinds still gets the map, since it can't be ruled out. The
  racy fixed-`50ms` post-format timer is dropped — formatting stays owned by format-on-save and
  `<leader>cf`.
- **Neovim cursor-restore skips commit buffers.** `gitcommit`/`gitrebase` buffers open at the top
  again instead of jumping to a stale mark from a previous commit.
- **Neovim folding has a single owner.** `nvim-ufo` computes folds via its own treesitter+indent
  providers, so the global `foldmethod=expr` + treesitter `foldexpr` in `options.lua` was redundant
  per-buffer work (UFO never reads `foldexpr`). Dropped it; UFO now owns folding outright.

### Changed (internal)

- Deduped the identical `snippetSupport` capability boilerplate in the Neovim `html`/`cssls`
  server specs into a shared `utils.lsp.with_snippets` helper; standardized autocmd augroups on an
  explicit `{ clear = true }`; corrected a stale comment claiming no `vim.notify`-competing
  notifier is installed (fidget is, for LSP progress only — no clash).

## [v3.7.0] - 2026-07-17

### Changed

- **Neovim clipboard gains a gated OSC52 last-resort provider.** When no native clipboard
  backend is on PATH (no Core `clip`/`clip-paste`, no `clip.exe`, and none of `pbcopy` /
  `wl-copy` / `xclip` / `xsel` / `win32yank`), `"+y`/`"+p` route over the terminal's OSC52
  sequence — closing the "yank does nothing over tmux/psmux/SSH" gap on headless/remote boxes.
  A working native provider is never overridden, so a normal desktop is unaffected.
- **Neovim clipboard paste uses `Get-Clipboard -Raw` on Windows**, so multi-line pastes no
  longer arrive split/CRLF-mangled.
- **Windows-correct Neovim Python DAP + LuaSnip build.** debugpy/venv interpreters resolve to
  `Scripts\python.exe` (and `python`, not `python3`) on Windows; LuaSnip skips its
  `make install_jsregexp` build where there's no toolchain. All gated on `has("win32")`.
- **Neovim LSP capabilities fetch is `pcall`-guarded** (a blink load failure no longer aborts
  the whole server stack), and `emmet_ls` now attaches to `html`.
- **Starship prompt gains venv, package, git-metrics, and WSL indicators.** `[python]` shows the
  active `$virtualenv`; a `$package` version indicator and an `$env_var` slot are wired into
  `format` (surfacing a previously-unplaced `ENGAGEMENT` var and a new `WSL_DISTRO_NAME` badge);
  `git_metrics` is enabled; a documented opt-in `docker_version` custom is included (off by default).
- **`git_main_branch` resolves the trunk in one call.** It reads `origin/HEAD` directly
  (`git symbolic-ref`) and only falls back to probing the trunk-name candidate list when
  that is unset — instead of firing up to 18 `git show-ref` subprocesses every call. It sits
  on the hot path (`gcom` / `gswm` / `grbm`).
- **`git_current_branch` uses the git porcelain.** It now reads `git branch --show-current`
  (git 2.22+) instead of the hand-rolled `symbolic-ref` + return-code dance; the short-SHA
  fallback on a detached HEAD and the empty result outside a repo are both preserved.
- **`_core_suggest` no longer forks per candidate.** `_core_lev` gained a fork-free out-var
  mode, so scoring a mistyped Core verb against the alias/subcommand list runs in-process
  rather than spawning a command substitution for each candidate (~80+ on a bad `please`).
- **`pullall` tallies its summary in a single `awk` pass** instead of four `grep -c` scans of
  the same buffer.
- **Collapsed a dead `status-left` conditional** in `tmux/tmux.conf` to a constant — all three
  branches resolved to the same colour.
- **Decoupled `--help` from header line numbers.** `update-plugins.sh`,
  `update-nvim-plugins.sh`, and `freshness-dashboard.sh` now print usage from a heredoc rather
  than `sed -n '<a>,<b>p' "$0"`, which silently mis-printed whenever the header comment moved
  (the coupling `sync-core.sh` already documents having removed).
- **Removed redundant zsh history setopts** (`zsh/history.zsh`): `INC_APPEND_HISTORY` (implied
  by `SHARE_HISTORY`) and `HIST_IGNORE_DUPS` (superseded by `HIST_IGNORE_ALL_DUPS`) were
  no-ops, so they are dropped.

### Security

- **session-start hook verifies its tool downloads.** `install_tarball` and the neovim
  install in `.claude/hooks/session-start.sh` now download to a file and check the pinned
  SHA-256 from `scripts/tool-versions.env` before extracting — failing closed when a
  checksum is absent or mismatched — instead of piping `curl … | tar` unverified. Brings the
  remote-session gate toolchain in line with the CI composite action, which already verifies.
- **claude-routines run with least-privilege tools.** Each job's `--allowedTools` now mirrors
  its routine's own `allowed-tools` frontmatter rather than granting unrestricted `Bash`; the
  web-reading routines (tool-scout, freshness-triage, modernize, release-readiness,
  drift-triage) no longer pair arbitrary shell with `WebFetch`/`WebSearch`, closing a
  prompt-injection → `CLAUDE_CODE_OAUTH_TOKEN` exfiltration path. `drift-triage`'s command
  frontmatter is scoped to match.
- **`HISTORY_IGNORE` covers more secret shapes** (`zsh/history.zsh`): `--flag=value` forms and
  env-assignment credentials (`TOKEN=`, `PASSWORD=`, `*ACCESS_KEY=`, `APIKEY`) that the
  space-only patterns let slip now stay out of the plaintext `$HISTFILE`.

### Fixed

- **Cheatsheet uses a non-deprecated highlight API.** `nvim/lua/gerrrt/cheatsheet.lua` now
  calls `nvim_buf_set_extmark` instead of the deprecated `nvim_buf_add_highlight` (slated for
  removal on Neovim nightly), so `:Cheatsheet` / `<leader>?` keeps working on current Neovim.

## [v3.6.1] - 2026-07-16

### Documentation

- **`docs(runbook)`: spell out how release cuts differ by bump type.**
  `RELEASE-RUNBOOK.md` now adds the Core-release bump-selection table, the step-4
  `@vN` alias split for PATCH/MINOR vs MAJOR, the extra MAJOR rollout `uses:` bump,
  the htpx SemVer guide, and the "undo a staged `make release`" troubleshooting
  path. `RELEASE-STRATEGY.md` is updated alongside it so the current-version examples
  stay aligned with the live Core release line.

## [v3.6.0] - 2026-07-16

### Added

- **`feat(nvim)`: five editor quality-of-life tweaks.** Cherry-picked from an external
  config the handful of behaviours that beat or fill a gap in ours (the rest we already run
  better-configured equivalents of). (1) `i`/`a`/`A` on a blank line auto-indents via `"_cc`
  (black-hole register, guarded on `count == 0` so `3i`/`10a` keep native behaviour);
  (2) an async `git fetch` on `VimEnter` toasts when the upstream is ahead of `HEAD` — pinned
  to the startup cwd, argv-form (Windows-portable), and only reported after a _successful_
  fetch; (3) `vimade` dims inactive windows and cursorline is now shown only in the active
  window (markdown/text/gitcommit keep their cursorline-off policy); (4) a macro-recording
  indicator in the lualine mode block; (5) `exrc` for project-local config. The `git fetch`
  toast and `exrc` are both gated on `DOTFILES_OFFLINE` so they stay inert on engagement boxes,
  and `exrc` additionally relies on Neovim's `vim.secure` trust prompt for untrusted repos.

## [v3.5.2] - 2026-07-14

### Fixed

- **`fix(tmux)`: trailing space after the copy-mode icon.** The status-bar copy-mode
  indicator was `󰆏#S` (glyph abutting the session name); it is now `󰆏 #S` — a single
  space keeps the pill readable at a glance without otherwise changing the layout.

### Documentation

- **`docs(runbook,strategy)`: document the deliberate dotfiles-Windows minor/major
  release flow.** `RELEASE-RUNBOOK.md` §3 only covered the automatic PATCH path
  (mirror-sync → auto-tag). A new §3b covers the human-driven minor/major flow: the
  version decision via `/release-readiness` + `/release-notes`, the
  `packages.lock.json` re-pin (including the winget-export-vs-ARP mapping gap that
  silently drops installed-but-unmapped apps), CHANGELOG promotion, and
  `gh release create` (there is no `release.yml` on the Windows repo). Simultaneously,
  `RELEASE-STRATEGY.md` is corrected: dotfiles-Windows is now carved out as the
  standalone exception that carries its own vX.Y.Z but no `core/` subtree, and the
  notes-source column is fixed (`--notes-file` via auto-tag.sh is the automatic path;
  `--generate-notes` is only the fallback for empty/unconventional ranges).

## [v3.5.1] - 2026-07-14

### Changed

- **`ci(modern)`: ban the `macos-14` runner in the modern-CI floor.** `macos-14`
  (Sonoma) images entered deprecation on 2026-07-06 and are fully unsupported on
  2026-11-02, so `scripts/modern-baseline.yml` now lists it under `banned_runners`
  alongside `macos-13`. Pre-emptive and free — the fleet rides `macos-latest`, so no
  workflow references the pinned label today; `check-modern.sh` enforces it.

### Documentation

- **`docs(matrix)`: `watch`→`viddy` is now a first-class, provisioned tool.**
  `PORTING-MATRIX.md` gains a `viddy` row so the `watch`→`viddy` alias Core already
  ships (`HAVE_VIDDY`-guarded in `zsh/aliases.zsh`) is actually installed — macOS
  already had it via Homebrew; the Linux/Kali repos now install it best-effort in
  `bootstrap.sh` via `cargo install viddy` (viddy is a Rust CLI, so the same cargo path
  as yazi/dust — Arch, which ships no rust toolchain, prints a `paru -S viddy` hint).
  Inert without the binary, so boxes that skip it keep classic `watch`.

## [v3.5.0] - 2026-07-13

### Changed

- **`fix(git)`: delta's `syntax-theme` is now `ansi` (was `TwoDark`).** delta now follows
  the terminal's Tokyo Night ANSI palette, matching `BAT_THEME=ansi` (already set in
  `aliases.zsh`) so `git diff` and `bat` render syntax the same way — and matching the
  Windows host, which already used `ansi`. Part of the Windows↔Mac terminal parity pass.

### Fixed

- **`fix(nvim)`: `<leader>rc` and the alpha dashboard "Config" button open `init.lua`
  on Windows too.** Both hardcoded `~/.config/nvim/init.lua`, which doesn't exist on the
  Windows host — Neovim there reads `%LOCALAPPDATA%\nvim` — so the binding opened a phantom
  path. They now resolve the config dir at runtime via `vim.fn.stdpath("config")`, so the
  same binding lands on the real `init.lua` on every platform.

### Parity (cross-shell contract)

- **`feat(parity)`: the aligned tool-swap manifest gains `df`→duf, `top`/`htop`→btop,
  `fm`/`y`→yazi, `md`→glow (pwsh `gmd`), and `ping`→gping.** These were already defined
  in `zsh/aliases.zsh`; adding them to `scripts/parity-aliases.txt` makes
  `parity-check.sh` enforce them bidirectionally against the pwsh host's `provides:`
  contract (the Windows PowerShell port added the matching functions in the same pass).
- **`feat(parity)`: `Ctrl+\` autosuggest/prediction toggle is now `aligned`, not
  `deliberate`.** The Windows host binds `Ctrl+\` to flip PSReadLine's `PredictionSource`,
  mirroring zsh's `autosuggest-toggle`; `parity-check.sh` now enforces the needle on both
  shells. PARITY.md's Aliases prose also now documents the full curated git shorthand set
  as aligned across zsh + pwsh.
  > **Merge order:** the pwsh side of these rows ships in the `dotfiles-Windows` parity PR.
  > Merge (or land together with) that PR so the weekly `parity-check.yml` — which clones
  > `dotfiles-Windows` `main` — sees the matching pwsh definitions and stays green.

## [v3.4.0] - 2026-07-12

### Added

- **`feat(freshness)`: the weekly fleet board gains three live cross-repo signals.**
  `scripts/freshness-dashboard.sh` now queries the GitHub API (best-effort, gated on `gh` +
  a token — the workflow provides both, a local run degrades to an "unavailable" note) for:
  **own-tag release drift** (commits each repo has merged since its last release tag — its
  own unreleased work, distinct from Core-tag vendoring drift), an **open Renovate PR tally**
  per repo (how many dependency PRs are waiting right now, beside the existing dashboard
  links), and **judgment-layer routine issues** (links to each repo's open `.claude`-routine
  issues — doc-audit, os-package-availability, coverage-gap, … — so the board references the
  stale-docs and coverage-hole signals rather than recomputing them). Still a never-failing
  reporter (always exits 0).
- **`feat(routines)`: three new judgment routines + a reusable OS-repo routine workflow.**
  - `/shell-review` (`.claude/commands/shell-review.md`) — weekly (Tue 11:00) read of the
    week's changed `zsh`/`bash` for runtime footguns lint can't catch (the tmux-scratchpad
    and doctor-hint classes), report-first.
  - `/drift-triage` (`.claude/commands/drift-triage.md`) — weekly (Tue 12:00) interpretation
    of Monday's `fleet-drift` sweep into ranked per-repo remediation, report-first.
  - `/os-package-availability` (`.claude/commands/os-package-availability.md`) — audits an OS
    repo's `install/packages.txt`/`Brewfile` for renamed/dropped/moved packages against
    upstream + `PORTING-MATRIX.md`. Shipped as a **reusable workflow**
    (`.github/workflows/claude-routines-call.yml`) so each OS repo consumes it as a ~5-line
    `@v3` caller (inverted checkout, like `lint-call.yml`) rather than a 6× copy.
  All inert-by-default (preflight `CLAUDE_CODE_OAUTH_TOKEN` gate) and report-first.

### Changed

- **`perf(zsh)`: drop `zstyle ':completion:*' rehash true` — no more per-Tab `$PATH` stat storm.**
  `rehash true` (`zsh/options.zsh`) forced zsh to rebuild its external-command hash — stat every
  directory in `$PATH` — on _every_ completion attempt, which is perceptible on an NFS home,
  linuxbrew, or a large mise-shims `$PATH`, and fanned out to all eight OS repos. Removed; a
  newly-installed binary now surfaces after `hash -r` or a new shell (the maint runner already
  refreshes the command hash after installs). A regression-guard comment records why it stays out.
- **`chore(bin)`: make `.bin/sync-upstream.sh` overridable for forks/mirrors.**
  `CORE_REPO_URL` and `TARGET_BRANCH` now read `${VAR:-default}`, so a fork, a mirror, or a
  renamed org can `gsync` without editing this vendored file.

### Fixed

- **`docs(porting)`: correct the `PORTING-MATRIX.md` package cells the `/os-package-availability`
  routine flagged as drifted.** Alpine `duf`/`glow` are back to `testing` (they were never
  promoted to `community` on stable, incl. 3.24 — a July flip that claimed otherwise is reverted,
  and footnote ¹⁴ restored); Alpine `tldr` now shows `cargo³` (`testing`-only → bootstrap builds
  it from source) and Alpine `ouch` is corrected to `testing` (`testing`-only, not auto-installed);
  and Gentoo `tealdeer`/`yazi`/`lazygit` are marked GURU-only
  (footnote ¹²) alongside a note that `direnv` is `app-shells/direnv`, not the non-existent
  `dev-util/direnv`. Matches the OS-repo bootstrap reality (Alpine cargo/go-install fallbacks;
  Gentoo `guru_install`). Also: Arch `atuin` drops the stale "(AUR for some)" qualifier and Arch
  `doggo` moves from `AUR³` to `doggo` (both now first-class in `extra`), and the openSUSE
  `tealdeer` footnote ¹ is de-hedged (it's in Tumbleweed main OSS, not devel-only).
- **`fix(zsh)`: `compinit` block no longer leaks a global `zcd` into every interactive shell.**
  `zsh/options.zsh` declared `local zcd=…` at the file's sourced top level, where zsh (which has
  only function scope) silently promotes `local` to an ordinary **global** — polluting the
  namespace on every shell start across all eight OS repos and contradicting the codebase's own
  anon-function convention (`zsh/aliases.zsh`) and `loader.zsh`'s "no top-level `local`" rule. The
  cache body is now wrapped in an anonymous function so `zcd` is genuinely function-scoped;
  `compinit` declares its state `typeset -g`, so the completion system persists unchanged.
- **`fix(zsh)`: `serve` now prints a reachable URL and QR on macOS.**
  `serve` (`zsh/functions.zsh`) gated all tunnel/LAN IP discovery on `command -v ip`, but macOS
  ships no `ip(8)`, so on a Mac it degraded to a bare "serving on port N" with no LAN URL and no
  QR. Added a `route(8)` + `ipconfig` fallback branch — the same Linux/macOS split
  `tmux/scripts/tmux-netinfo.sh` already uses — so tunnel-first, then default-route LAN discovery
  works on a Mac. No change on Linux/WSL.
- **`fix(nvim)`: undo dir now derives from `stdpath("state")`, not a hardcoded path.**
  `options.lua` hardcoded `~/.local/share/nvim/undodir`; it now uses `vim.fn.stdpath("state")`,
  so undo history lands in the right tree under a relocated `XDG_STATE_HOME` and on macOS.
- **`fix(nvim)`: drop the no-op `vim.opt.encoding = "UTF-8"`.**
  Neovim's internal encoding is always UTF-8; setting it post-startup is a no-op at best and a
  footgun at worst. Removed; a comment records why it stays out.
- **`fix(tmux)`: popup previews degrade on Debian / a bare box.**
  `tmux-menu.sh`'s engagement preview now falls back `bat`→`batcat` (Debian renames the binary),
  and `tmux-sesh.sh`'s project preview falls back `eza`→`ls` when eza is absent — matching how
  the zsh widgets already resolve these.
- **`fix(starship)`: the Linux VPN segment uses a portable `ip link show` probe, not `ifconfig`.**
  `custom.vpn_linux` shelled out to `ifconfig` (net-tools), which modern distros don't ship by
  default, so the tunnel indicator silently never appeared. It now parses `ip link show` — the
  common form supported by BOTH iproute2 AND BusyBox's `ip` applet (Alpine's default), so it works
  on every Linux target including the BusyBox outlier. `custom.vpn_macos` keeps `ifconfig` (native).
- **`docs(git)`: spell out the `includeIf` work-identity failure mode.**
  Clarified that a missing `~/.config/git/config-work` makes git silently fall back to your
  default identity (no error), with the exact commands to seed it.
- **`fix(git)`: `prune-branches` uses `grep -E`, not deprecated `egrep`.**
  The `prune-branches` alias (`git/gitconfig`) shelled out to `egrep`, which GNU grep ≥3.8 prints
  a deprecation warning for on every invocation. Switched to `grep -Ev`; `xargs -r` is kept (GNU
  needs it to skip empty input, and modern BSD/macOS xargs supports it), so the alias is quiet on
  the Linux target and unchanged in behaviour on the macOS/BSD target it ships to.
- **`fix(scripts)`: checksum refresh falls back to `shasum -a 256` off-Linux.**
  `scripts/update-tool-checksums.sh` hard-called `sha256sum` (GNU coreutils); a run on the macOS
  box (which ships `shasum -a 256`, not `sha256sum`) died. It now probes and falls back, so the
  tool works on either platform.
- **`fix(maint)`: `dotfiles-maint.sh` enables `set -uo pipefail`.**
  The unattended daily runner had no `set` options, so a typo'd env knob expanded to empty and a
  mid-pipe failure was masked. Added `set -uo pipefail` (every env knob is already `:=`/`:-`
  defaulted); `-e` stays deliberately omitted so one failed step never aborts the rest — that
  remains `step()`'s job.
- **`fix(tmux)`: the popup scripts enable `set -u`.**
  `tmux-menu.sh`, `tmux-scratch.sh`, and `tmux-sesh.sh` carried no `set` options, unlike their
  siblings; a typo'd variable would expand to empty silently. Added `set -u` (all three already
  guard `${TMUX:-}`/`${TERM:-}` etc.); `-e`/`pipefail` stay off because the fzf pickers exit
  non-zero on a normal operator cancel.
- **`fix(scripts)`: the freshness board's live signals honour an env token.**
  `scripts/freshness-dashboard.sh` gated its GitHub-API "live signals" on `gh auth status`
  alone, whose exit/output varies by `gh` version — so in CI (which authenticates via
  `GH_TOKEN`, not `gh auth login`) the release-drift / Renovate-count / routine-issue
  sections could be mis-detected as unavailable. It now treats a `GH_TOKEN`/`GITHUB_TOKEN`
  env var as sufficient (what `gh api` actually uses), falling back to `gh auth status`
  for local runs with stored credentials.

## [v3.3.0] - 2026-07-09

### Changed

- **`perf(zsh)`: cut per-shell subprocess forks on the interactive startup path.**
  `_cache_eval` (`zsh/tools.zsh`) now resolves each tool's binary via zsh's fork-free
  `$commands` hash instead of `$(command -v …)`, removing one command-substitution fork
  per cached tool (~8/shell across starship/zoxide/mise/atuin/carapace + the os-layer
  gh/uv/ty callers). The `diff --color` capability probe (`zsh/aliases.zsh`) is now
  cached (keyed on the `diff` binary's mtime, invalidated on a toolchain change) instead
  of running the real `diff` on every shell; a live probe still decides correctly when
  the cache dir isn't writable. No behavioural change — same aliases, faster launch.
- **`docs(zsh)`: make `core-doctor`'s "install missing" hint honest about unpackaged tools.**
  The batch hint printed a blanket `<pkg-manager> install <all-missing>`, implying the package
  manager can install every tool. On some distros a few modern-CLI tools aren't packaged at
  all (they're binary-distributed, and the right method — a distro package, `mise use -g`,
  `go install`, `cargo install`, or a vendor repo — varies per tool and distro), so the line
  fails on those. The caveat now states that names differ per distro **and** that not every
  tool is packaged everywhere, pointing to `PORTING-MATRIX.md` for the authoritative per-tool
  install path instead of implying the package manager covers all of them. Output-only; the
  package-manager line itself is unchanged.

### Fixed

- **`fix(tmux)`: scratchpad popup (`prefix + T`) no longer hijacks the main session on close.**
  `tmux-scratch.sh` runs the scratchpad as a persistent `_popup_scratchpad` session the popup
  `attach`es to. On close, exiting the shell destroys that session, and the global
  `detach-on-destroy off` (tmux.conf) made the popup's client jump to the MAIN session instead
  of closing — attaching a second, popup-sized (80%×80%) client, so tmux clamped the main
  session to the popup's size and double-drew it (the scratchpad "took over" and the real
  terminal was left garbled). The scratch session now sets `detach-on-destroy on` for itself,
  so its client detaches (popup closes cleanly) when it's destroyed; real sessions keep the
  global jump-don't-exit behaviour.

## [v3.2.0] - 2026-07-08

### Removed

- **`token-health.yml` — the weekly PAT-expiry probe, now redundant (G2 finish line).** The
  probe existed to catch a `FLEET_SYNC_TOKEN` / `WEBHOOK_SECRET` PAT silently expiring before it
  broke the fan-out or the docs-refresh. With every consumer migrated to GitHub App
  installation tokens (`GITHUB-APP-AUTH.md`) and both PATs deleted, there is nothing left to
  probe — a minted token lives ~1 hour and cannot silently expire. Removed the workflow and its
  references (the freshness dashboard's "Token health" section is now a "Fleet auth" note; the
  cron-stagger and sync-fanout failure-hint comments no longer mention it).

- **`dotfiles-Defense-PLAN.md` — the pre-build planning skeleton, now obsolete.**
  The doc was a "ready-to-instantiate skeleton for a future `dotfiles-Defense`
  repo," written before that repo existed. `dotfiles-Defense` is now a public,
  released repo (v1.0.x) that actively vendors Core, so the plan is spent — and,
  worse, it actively misled the `/doc-audit` routine into reporting Defense as
  "unbuilt/absent." Deleted (git history retains it) and dropped from the
  `audit-core.sh` META_ALLOWLIST.

### Added

- **`ast-grep` is now a recognized opt-in tool.** AST-aware structural code
  search/rewrite — the syntax-tree complement to `ripgrep` (text), `sd` (regex), and
  `gron` (JSON). `tools.zsh` sets `HAVE_ASTGREP` when the binary is present; it's its
  own command with **no alias** (like `gron`/`sd`), so it shadows nothing and is inert
  without the binary. `PORTING-MATRIX.md` documents install sources (Arch `extra`,
  Alpine `community` musl build, Homebrew; else `cargo`/`mise`/`npm`/`pip`). Surfaced
  by `/tool-scout` as the one true capability gap in the stack.

- **ci: raised the modernization floor — banned retired runners + old action runtimes.**
  `scripts/modern-baseline.yml` now bans `macos-13` (retired 2025-12-04), `windows-2019`
  (unsupported 2025-06-30), and `ubuntu-22.04` (deprecation opens 2026-09-17) as runner
  labels, and the `using: node16` / `using: node20` action runtimes (Node 24 is the
  default since 2026-06-16). Pure no-regression guard — the fleet uses none of these, so
  `check-modern.sh` stays green; it just bars re-introducing a dead runner or runtime.
  Surfaced by `/modernize`.

- **Cross-platform alias parity is now a data-driven manifest (Track A).** The aligned
  modern-CLI tool-swap aliases (`ls`→eza, `cat`→bat, `ps`→procs, …) live in a flat
  `scripts/parity-aliases.txt` manifest; `parity-check.sh` reads it and asserts each row
  **bidirectionally** — the zsh alias is defined in `zsh/aliases.zsh` AND the pwsh name is
  in `dotfiles-Windows`'s `00-aliases.ps1` `provides:` contract — so a rename or drop on
  either shell fails the weekly `parity-check`. Naming exceptions (`ps`→procs is `pss` on
  pwsh) are recorded in the manifest. Extends the check from a handful of hand-coded
  needles to the full tool-swap surface; adding an aligned alias is one manifest row.

- **`notify-web` dispatch mints a GitHub App token; sync-fanout mint gated on the key (G2).**
  The reusable `notify-web-call.yml` now mints a short-lived `dotfiles-web`-scoped GitHub App
  token for the `repository_dispatch` (replacing the `WEBHOOK_SECRET` Bearer PAT) when the
  fleet App is configured and the caller passes `FLEET_APP_PRIVATE_KEY`, else it falls back to
  `WEBHOOK_SECRET`. Because `FLEET_APP_ID` is one org-wide variable, the mint is gated on a
  `HAS_APP_KEY` presence flag (an env derived from a secret comparison — secrets can't be
  tested in `if:`) so a caller that hasn't been migrated (or a repo the key isn't scoped to)
  falls back cleanly instead of failing on an empty key. The same defensive gate is added to
  the Core `sync-fanout` mint. Core's own standalone `notify-web.yml` dispatcher (not a caller
  of the reusable) mints the App token inline via the same pattern. Reusable-caller repos pass
  the key in a follow-up (after `v3` advances).

- **`sync-fanout` mints a GitHub App token for the Core fan-out (G2 canary).** Following
  `GITHUB-APP-AUTH.md`, the Core fan-out now mints a short-lived GitHub App installation
  token (`actions/create-github-app-token`, SHA-pinned), scoped to the App's installed repos
  (the fan-out targets — no second copy of `scripts/os-repos.txt` to drift), instead of
  relying on the broad, hand-rotated `FLEET_SYNC_TOKEN` PAT. It is **backward-compatible**: the mint
  step runs only when the `FLEET_APP_ID` variable is set and otherwise falls back to the PAT,
  so this is inert until the fleet App is registered. First consumer migrated; `htpx`
  `sync-fanout` and the `notify-web` dispatch follow the same pattern.

- **`GITHUB-APP-AUTH.md` — the runbook to retire the fleet's cross-repo PATs (G2).** Both
  `FLEET_SYNC_TOKEN` (cross-repo push + PR in `sync-fanout`) and `WEBHOOK_SECRET` (the
  `repository_dispatch` Bearer to `dotfiles-web`) are broad, hand-rotated PATs that expire
  on a date nobody watches. The runbook specifies replacing them with **one GitHub App**
  that mints **short-lived, per-repo-scoped installation tokens** at run time
  (`actions/create-github-app-token`), a **backward-compatible** workflow pattern (mint when
  `vars.FLEET_APP_ID` is set, else fall back to the legacy PAT — so merging is inert until
  the App is registered), and the migrate → verify → retire order. Registering the App and
  resolving the action's pinned SHA are owner actions; the runbook is the design + the exact
  steps. Once it lands, the `token-health` probe becomes redundant (a minted token cannot
  silently expire).

- **`/release-readiness` + `/release-notes` maintenance routines — the judgment layer over the
  release mechanics.** `/release-readiness` is the go/no-go gate in front of `RELEASE-RUNBOOK.md`:
  it weighs the unreleased `CHANGELOG` work, the audit status, version coherence, and fleet drift
  into a **READY-to-cut-vX.Y.Z / HOLD** verdict with the next command to run. `/release-notes`
  drafts the next release's grouped notes from Conventional Commits (git-cliff, or the first-party
  `gen-release-notes.sh` when the binary is absent) as raw material to curate into `[Unreleased]`.
  Both are report-first (they edit nothing). `release-readiness` rides the `claude-routines` rail
  weekly (Tue 10:00 UTC, last in the Opus stagger); `release-notes` is dispatch-only (you draft at
  release time, not on a beat). Both `fetch-depth: 0` for the `git log <last-release>..HEAD` range.

- **Real release notes for OS-repo tags — `scripts/gen-release-notes.sh` (G5).** OS-repo
  auto-releases shipped a bare tag with GitHub's raw PR-list (`--generate-notes`); they now
  ship a grouped Conventional-Commit changelog. `auto-tag.sh --release` drafts the notes for
  the `latest..NEXT` range and feeds them to `gh release create --notes-file`, falling back
  to `--generate-notes` when a range has no conventional commits. The generator is the
  **first-party twin of Core's `cliff.toml`** — same grouping (Features / Bug Fixes / … in
  commit-parser order) and one-bullet-per-commit shape, but pure `git` + `awk` so it needs
  no git-cliff binary (the fleet's "no third-party CI tool we can't pin" discipline — the
  same reason zizmor stayed deferred). Also bumps `auto-tag-call.yml`'s internal core
  checkout from the stale `@v2` to `@v3` (it now carries both release scripts).

- **A weekly fleet freshness dashboard — one hub health board.** `scripts/freshness-dashboard.sh`
  consolidates the fleet's otherwise-scattered freshness signals — vendoring drift
  (`fleet-drift.sh`), vendored-`core/` integrity (`core-integrity.sh`), and zsh/nvim
  plugin-pin freshness (`update-*-plugins.sh --check`) — into a single glanceable markdown
  board, with links to each repo's Renovate dependency dashboard and the token-health probe.
  `.github/workflows/freshness-dashboard.yml` runs it Mondays 10:00 UTC (after the morning
  sweeps settle) and files a deduplicated issue that updates in place. It _reports_, never
  mutates — the sub-gates still enforce; this is the "how healthy is the fleet this week?"
  view in one place. Run locally with `make freshness-dashboard`.

- **A `/modernize` maintenance routine — the judgment half of the modernization floor.**
  `check-modern.sh` _enforces_ the current floor (`scripts/modern-baseline.yml`); this
  routine scouts what the _next_ floor should be. It reads the declared floor and the
  fleet's workflows, researches the latest runner/action deprecations (EOL runner
  labels, the `node16`→`node20`→`node24` action-runtime treadmill, pinning-discipline
  gaps, new hardening dimensions), and files a **report-first** proposal — the exact
  baseline edit, the dated upstream source, and whether it is enforceable today or needs
  fix-first workflow changes. Runs headless weekly on the `claude-routines` rail (Tue
  09:00 UTC, last in the Opus stagger) and files a deduplicated issue; edits nothing.

- **Renovate adoption via a shared org preset (replaces Dependabot).** The fleet's
  dependency-update policy now lives once in `dotgibson/.github` (`default.json`) and
  every repo opts in with a three-line `renovate.json` that extends it — the same
  hub-and-spoke centralization Phase 1 applied to reusable workflows, now for
  dependency management (closes the "no Dependabot/Renovate outside core & Windows"
  gap). The preset keeps Renovate in lock-step with the modernization floor
  (`scripts/modern-baseline.yml`): it _maintains_ SHA-pinned actions and `@sha256:`
  container digests rather than un-pinning them, groups third-party action bumps into
  one weekly `ci(deps):` PR, and deliberately leaves the fleet's own `dotgibson/**`
  reusable-workflow refs on their moving `@v3` major tag (advanced by the release
  process, not a bot). Core retires its standalone `.github/dependabot.yml`;
  `renovate.json` is allowlisted in `audit-core.sh` as repo-meta.

- **A modernization floor for CI: `scripts/modern-baseline.yml` + `scripts/check-modern.sh`,
  gated by `audit-core.sh` (section 8c).** The baseline declares what "modern" means — no
  removed workflow commands (`::set-output`/`::save-state`/…), no EOL runners, every external
  action pinned to a 40-hex SHA (the fleet's own `@vN` reusable workflows exempt), and every
  container image pinned to an `@sha256:` digest — and the checker enforces it so a workflow
  can't silently regress below it. This generalizes the fleet's existing SHA-pin discipline
  into one contract and closes the last break in it (mutable container tags: `alpine:3.21` and
  `archlinux:latest` in `ci.yml` are now digest-pinned). Run standalone with `make check-modern`.

- **difftastic (`difft`): an opt-in, structure-aware diff companion to delta.**
  `tools.zsh` now detects it (`HAVE_DIFFT`), `git/gitconfig` defines a
  `difftool "difftastic"` plus a `git dft` alias, and `aliases.zsh` adds a
  `HAVE_DIFFT`-guarded `gdft` shortcut. difftastic diffs by AST (tree-sitter), so
  formatting-only churn — rewraps, moved elements, trailing commas — shows as no
  syntactic change. It is deliberately **additive, never the default**: delta stays
  the `git diff` syntax-highlighting pager and difft is only reached on demand via
  `git dft`/`gdft`, so nothing changes on a box without the binary. Documented in
  `PORTING-MATRIX.md` (packaged on Arch/Alpine-musl/Fedora/Gentoo/openSUSE/Homebrew/
  Debian-Kali; `cargo`/`mise` where unpackaged).

### Fixed

- **docs: `PORTING-MATRIX.md` clipboard section claimed the backend is "swapped
  in `os/<distro>.zsh`".** Clipboard selection actually lives in Core's cross-OS
  `clip`/`clip-paste` scripts — each `os/*.zsh` only aliases `pbcopy`/`pbpaste` to
  them. Reworded the heading to "Clipboard packages to install" (the table's
  package names were always correct); surfaced by `/doc-audit`.

- **ci: `update-nvim-plugins.sh` exited non-zero when the lock was already
  current.** In apply mode the "already current" branch ended on `((CHECK))`
  (exit status 1 when `CHECK=0`), so the script returned 1 with nothing wrong —
  and under the freshness bot's `set -e` that turned a no-op week into a red nvim
  job (and, now that failure-alerting works, a false issue). It exits 0 explicitly.

- **docs: `aliases.md` was missing `gdft`.** The difftastic-backed `git difftool`
  shortcut (added alongside `HAVE_DIFFT` and `git dft`) landed in `zsh/aliases.zsh`
  without a matching entry in the cheat sheet — added to the Diff table.

- **maint: the daily runner now reconciles pinned zsh plugins by CONFIG, not
  checkout state.** `maint/dotfiles-maint.sh` decided "pinned vs unpinned" by
  asking whether a plugin's `HEAD` was detached — but a plugin cloned before
  `plugins.zsh` began pinning (or by the old floating `--depth=1` path) sits on a
  branch even though it IS pinned in `ZPLUGIN_PINS`. Those were wrongly
  `git pull --ff-only`'d every run: floating them off their pins, and logging a
  false `✗ … (pull failed)` for any whose branch couldn't fast-forward (e.g.
  `zsh-syntax-highlighting`). The loop now reads the pins straight from
  `plugins.zsh` (same grep `update-plugins.sh` uses — bash-3.2 safe) and, for any
  pinned plugin, re-asserts the recorded SHA (fetch + detach, mirroring
  `zplugin-update`): a branch checkout is reconciled back onto its pin, a rolled
  pin is now actually applied by the runner, and plugins already at their pin do
  zero network. Only genuinely unpinned plugins still fast-forward.

## [v3.1.0] - 2026-07-06

### Added

- **`assets/`: a reproducible VHS tape for the README hero demo.**
  `assets/demo.tape` scripts a short terminal tour (eza, bat, zoxide, `core help`,
  `glog`) that renders to `assets/demo.gif` via `vhs assets/demo.tape`, so the hero
  can be regenerated rather than hand-recorded. `assets/README.md` documents the
  render steps; `assets/` is allowlisted in `audit-core.sh` as repo-meta (it rides
  along in the subtree copy but is never symlinked).
- **README: a structured four-row badge block at the top.** Row 1 is repo
  status & automation — live `ci` and `core-integrity` Actions status,
  open-issue / open-PR counts, repo size, and latest release. Row 2 is the
  MIT license (auto-detected from `LICENSE`) plus last-commit / commit-activity.
  Row 3 is the languages (Zsh, Bash, Lua, TOML, YAML, JSON) and Row 4 the
  tooling (Neovim, Vim, tmux, Starship, Git, 1Password). Tools with no
  simpleicon (`mise`, `lazygit`, `jujutsu`, `sesh`, `fzf`) share a substitute
  `gnometerminal` glyph on a Tokyo Night purple label.
  Every brand color is taken from the `simple-icons` dataset (e.g. Lua `000080`,
  Git `F03C2E`, 1Password `145FE4`). Vim is the `vim/vimrc` fallback editor for
  boxes with no nvim, not just the `vim=nvim` alias; the tooling row covers
  every tool Core ships a dedicated config for. Each Row 3/4 badge links to its
  upstream project on GitHub and, where the project publishes releases/tags,
  shows the current upstream version live (Neovim, Vim, tmux, Starship, Git,
  Lua, TOML, mise, lazygit, jujutsu, sesh, fzf); Zsh, Bash, YAML, JSON, and
  1Password have no clean upstream version and stay plain. On the versioned
  badges the name side carries the brand color and the version side is a Tokyo
  Night blue (not grey). Row 1 leads with a `dotgibson` badge that shows the
  current release version (dynamic `github/v/release`) with the org avatar as
  its icon (base64 data-URI logo) and links to the latest release. All `flat-square`; the old hardcoded `audit-passing`
  shield is replaced by the live `ci` status it stood in for.
- **nvim: `utils/ui-highlights.lua` — a flat table of NvChad-flavored highlight
  overrides.** Hairline window splits (`WinSeparator`/`VertSplit`), minimal
  rounded floats (`NormalFloat`/`FloatBorder`/`FloatTitle`), a border-tinted
  fzf-lua palette (`FzfLua*`), a matching blink.cmp menu/docs palette
  (`BlinkCmp*`), and NvChad's dim-linenr / bright-current-line gutter. Applied
  through tokyonight's `on_highlights` in `plugins/theme.lua`, so it re-runs on
  every `:colorscheme` and recolors from whatever `style`/theme is active — no
  `ColorScheme` autocmd, no per-plugin hardcoded hexes. Deliberately one flat
  function, not a helper framework.

### Changed

- **README: reworked into a lean public landing page.** Replaced the long-form
  technical README with a concise landing page — a lead stating Core is the vendored
  foundation layer (you install an OS repo, not this one), an at-a-glance three-layer
  table, a modern-CLI Usage section framed by the `HAVE_*` detection-flag fallback,
  and the repo's real contribution contract. The deep architecture and reference
  material now lives on the documentation hub at `dotfiles-web`. Fixed broken links
  along the way (`LICENSE`, `aliases.md`, the issue-template deep-links, a malformed
  acknowledgment link), and scoped MD033 in `.markdownlint.jsonc` with
  `allowed_elements` so the intentional showcase inline HTML passes the markdown gate
  while the rule still catches unexpected tags. The hero image is now the rendered
  terminal demo (`assets/demo.gif`, produced from `assets/demo.tape`).
- **nvim: the statusline now wears NvChad's rounded block look.** `plugins/lualine-nvim.lua`
  keeps its sections and (intentionally) its existing diagnostic glyphs — which
  stay in lockstep with `utils/diagnostics.lua` and the tabline — but swaps
  powerline arrows for NvChad's half-circle bubble caps (U+E0B6 / U+E0B4)
  and drops inner component separators so each half reads as one clean run of
  blocks. Adds a cwd (project basename) segment on the right, the cue a global
  statusline otherwise loses. Still a standard lualine config — no NvChad
  backend, no statusline caching, no managed toggle state.
- **nvim: fzf-lua now mirrors NvChad's telescope layout.** `plugins/fzf-lua.lua`
  gains `winopts`/`fzf_opts` translated 1:1 from `nvchad/configs/telescope.lua`
  (width 0.87, height 0.80, 55% preview on the right, prompt on top, a
  U+F002 magnifier prompt prefix, a U+F0DA selection caret) with rounded
  borders — the minimal
  NvChad finder look, on the finder you actually run (fzf-lua, not telescope).
- **nvim: the bufferline tabline picks up NvChad's flat-tab modified dot.**
  `plugins/bufferline-nvim.lua` sets `modified_icon` to the same ● (f111) used by
  lualine and incline, and annotates `separator_style = "thin"` as the flat,
  NvChad-tabufline-style rectangular tabs it already produces.

## [v3.0.1] - 2026-07-03

### Changed

- **nvim: the cheatsheet's three entry points now share one opener.** `<leader>?`
  and the `:Cheatsheet` / `:Cheat` user commands each inlined the same
  `require("gerrrt.cheatsheet").open()` thunk; they now call a single local
  `open_cheatsheet`, so the three can't drift and a future option/argument is a
  one-line edit. No user-visible change — `require` is still deferred to first open.

### Fixed

- **`gsync` was undocumented in `aliases.md`.** The upstream-sync helper
  (`zsh/aliases.zsh`, pushes an OS repo's vendored `core/` back to dotfiles-core)
  had no entry in the aliases cheat sheet. Added an "Upstream Sync" section.

## [v3.0.0] - 2026-07-02

### Added

- **nvim: a full-screen keybinding cheatsheet — the whole map, not the live
  prompt.** which-key is great at "I pressed `<leader>`, what's next?" but useless
  for "what do I even have?" — so the config's ~30 lazy plugin specs accreted
  features faster than muscle memory could keep up. The new
  `lua/gerrrt/cheatsheet.lua` renders every curated binding at once in a centered,
  NVChad-style floating panel: task-grouped cards (Essentials, Flash, LSP & Code,
  the three Git groups, Debug, Test, Folds, Text objects & Surround, Sessions, …)
  auto-packed into as many columns as the terminal is wide, tokyonight-themed via
  `default = true` highlight links so it also degrades cleanly on a bare box.
  Opened with **`<leader>?`** or **`:Cheatsheet`** (`:Cheat`); `q` / `<Esc>` close.
  Pure Neovim API, no new plugin dependency, and the module is `require`-d lazily
  so it costs nothing at startup. It is **hand-curated on purpose**: most mappings
  are bound lazily and aren't registered until their plugin loads, so scraping
  `nvim_get_keymap()` at open time would show a half-empty, load-order-dependent
  list — the table is the intentional, always-complete picture, and lives beside
  the specs it mirrors so a new binding gets a new row in the same review.

### Changed

- **nvim: `<leader>?` now opens the new cheatsheet instead of which-key's
  buffer-local-keys popup; that popup moves to `<leader>wk`.** Repointing a public
  binding is the one intentional breaking change in this release — the whole map
  is the more useful thing to keep on the mnemonic "help" key, and the live
  per-buffer prompt is one keystroke away under a new (which-key-labelled) `w`
  group. Existing `<leader>?` muscle memory now lands on the bigger view.

- **starship: pin an explicit `command_timeout = 1300` (was the implicit 500ms
  default).** The value is both a correctness knob and a safety valve. Correctness:
  a `git status` on a large or cold repo can exceed 500ms, and the default would
  blank the git segment mid-render; 1300ms clears that on real repos. Safety valve:
  `command_timeout` is the bound at which starship abandons AND kills the external
  command backing a segment (the `git_*` modules, any `[custom]` command). When a
  git call wedges — a stale `.git/index.lock`, a repo on a slow `\\wsl$`/network
  path, a hung credential probe — the child is now reaped at this bound instead of
  left running. That matters most on Windows, where an un-reaped git child orphans
  and one-per-prompt-render piles up into hundreds of stuck `git.exe` (enough that
  scoop/winget can't then replace the in-use git binary to update it). Pairs with a
  Windows-side pwsh change that makes shell-spawned git fail fast rather than block
  on an auth prompt.
- **Repo-location references migrated from the `Gerrrt` personal account to the
  `dotgibson` org.** Vendored-out URLs (`.bin/sync-upstream.sh`, `ARCHITECTURE.md`),
  the reusable-workflow `uses:` refs, the showcase Pages badge (`gerrrt.github.io` →
  `dotgibson.github.io`), and the `github.repository_owner == 'dotgibson'` guards in
  `release`/`sync-fanout`/`notify-web` (which silently no-op under any other owner)
  now point at the new org. The nvim `lua/gerrrt/**` module namespace and the
  `@gerrrt` code-owner are deliberately unchanged — those are the personal handle,
  not repo locations.

## [v2.6.0] - 2026-06-30

### Added

- **`sesh` detection (`HAVE_SESH`) — finishing wiring Core already half-shipped.**
  `sesh` (joshmedeski's smart tmux session manager) was already driven by the
  `Ctrl-G` shell widget (`fzf.zsh`), the `prefix + f` tmux popup (`tmux-sesh.sh`),
  a seeded `sesh/sesh.toml.example`, and listed in `core-doctor`'s integrations —
  but `tools.zsh` never set a `HAVE_SESH` flag for it the way it does for the
  other detected tools. (Detection itself still worked — the `Ctrl-G`/`prefix + f`
  fallback keys off `command -v sesh`, and `core-doctor` already probes `sesh`
  the same way.) `tools.zsh` now sets
  `HAVE_SESH` (like `HAVE_GUM`, no `_core_wired` arm — sesh registers no persistent
  shell hook, so presence ≈ wired), and `PORTING-MATRIX.md` gains a `sesh` row +
  footnote documenting the `go install github.com/joshmedeski/sesh/v2@latest` build
  path (the **v2** module path; `go` is already a pinned mise runtime) for the
  distros that don't package it. No `core.manifest` change — the `.example` is
  already listed.
- **`RELEASE-RUNBOOK.md`** — the step-by-step, copy-paste recipe for cutting a release
  (Core, the OS-repo fan-out rollout, and htpx), plus a "dry-run a new cross-repo
  workflow before relying on it" habit and a troubleshooting table. Complements
  `RELEASE-STRATEGY.md` (the policy); cross-linked from it and `CLAUDE.md`.

### Changed

- **nvim: disable `<LeftDrag>` and `<LeftRelease>` in all modes unconditionally.**
  Previously these were suppressed only when inside a `$TMUX` session, in Normal and
  Visual modes. They are now `<Nop>` in Normal, Insert, and Visual modes regardless of
  environment, eliminating accidental mouse-drag selections during terminal use.

- **`bootstrap-test.yml` retries the per-distro `prep` step (up to 5x with backoff).**
  The reusable links-only job ran the dep install once; a transient distro-mirror
  timeout (notably openSUSE Tumbleweed's OSS CDN) then redded the job — and every Core
  fan-out PR — on a network blip. The retry is fleet-wide (one place, every caller);
  a genuinely broken prep still fails loud after the attempts are exhausted.

## [v2.5.0] - 2026-06-29

### Added

- **jujutsu (`jj`) as an OPT-IN, colocated git companion.** Additive — it never replaces
  git. New `jujutsu/config.toml` (symlinked to `~/.config/jj/config.toml`, in
  `core.manifest`) sets a sensible colocated-friendly default (`ui.default-command = "log"`,
  `auto-local-bookmark`; identity intentionally unset — jj does NOT inherit git's
  `user.name`/`user.email`, so an opt-in author sets it once with `jj config set --user
  user.name/user.email`). `tools.zsh` gains `HAVE_JJ`
  detection and `aliases.zsh` a few `HAVE_JJ`-guarded verbs (`jjs`/`jjl`/`jjd`); nothing
  is aliased over `git`. On a box without `jj` everything is inert. `PORTING-MATRIX.md`
  documents per-distro packaging (packaged on Arch/openSUSE/Gentoo/Fedora/Homebrew/nix;
  `cargo install jujutsu` on Alpine(musl)/Debian-Kali — same pattern as yazi/ouch).

### Changed

- **zsh syntax highlighter swapped: `fast-syntax-highlighting` →
  `zsh-users/zsh-syntax-highlighting` (z-sy-h).** The pin moves to z-sy-h (a maintained,
  first-party `zsh-users` plugin) and the load order is corrected per its README: the
  highlighter is now the LAST widget-wrapping plugin sourced, with
  `zsh-history-substring-search` deferred immediately after it so its widgets get wrapped.
  The `FAST_THEME`/`FAST_HIGHLIGHT` theming is replaced by minimal `ZSH_HIGHLIGHT_HIGHLIGHTERS`
  (`main` + `brackets`) and `ZSH_HIGHLIGHT_STYLES` recoloured to the Tokyo Night Storm palette.
- **`fleet-drift.sh` anchors to the latest released Core tag by default, not the working
  tip.** Fan-out stamps each OS repo with the Core _tag_ it carries, so the dashboard now
  measures against the newest `vX.Y.Z` (via `git describe`), falling back to
  `origin/main`/`main`/`HEAD`. An explicit `--ref`/`$CORE_REF_SHA` still wins. This stops
  the false "BEHIND by N" the report showed for every unreleased commit on `main`
  (CHANGELOG/auto-tag churn between releases); the `fleet-drift.yml` workflow drops its
  `--ref HEAD` accordingly.

### Fixed

- **`auto-tag.sh` exit-code contract hardened + tested.** Added a defence-in-depth guard so
  `_next_version` fails loudly (non-zero) on a non-`X.Y.Z` input instead of producing a
  garbage component, and the call site now propagates that failure rather than tagging a
  bogus `v`. The behavioral suite (`test-core.sh`) now asserts the full exit-code contract
  hermetically (no network/gh): success → 0, no-op → 0, validation error → 2, and a real
  create failure (a `--push` onto an already-taken tag name, tripping Guard 2) → non-zero.

- **`auto-tag.sh --release` fails CI when an opted-in Release create actually fails.** The
  `gh release create` error branch called `fail` but the script still exited 0, so a real
  failure (gh present, API error) went green with no Release. It now `exit 1`s there — the
  tag still stands (pushed above), but CI goes red so you create the Release manually. The
  two non-failure exits stay deliberate: gh absent → skip, Release already exists → no-op.
  Also added `--release` to the `usage()` synopsis line (it was only in the flag list) and
  clarified its gh/skip semantics.

## [v2.4.1] - 2026-06-29

### Changed

- **`tag-release.sh` recipe spells out the land-then-tag order.** The printed next-steps
  now make the sequence explicit — land the release commit via PR (a merge commit), _then_
  tag `origin/main` (the merged tip) so the tag sits on `main`'s HEAD and `git describe`
  stays clean — instead of tagging the pre-merge commit and re-pointing. The two tag pushes
  use `;`, not `&&` (an "already exists" on the first must not skip the second — the `vN`
  move). `PUSH=1` now warns that it tags the pre-merge commit and prints the re-point steps.

## [v2.4.0] - 2026-06-29

### Added

- **OS-repo / Windows auto-tags now publish a GitHub Release too (`auto-tag.sh
  --release`).** Core releases already become Releases on tag push (`release.yml`), but the
  OS-repo tags `auto-tag.sh` cuts in CI were bare — no Releases page entry. A token-pushed
  tag can't trigger a separate `on: push: tags` workflow (GitHub anti-recursion), so the
  Release is now created in the SAME job: `auto-tag.sh --release` runs `gh release create
  <tag> --generate-notes` right after pushing (idempotent — a no-op if the Release exists;
  a missing `gh` just leaves the tag, never fails). `auto-tag-call.yml` gained a `release`
  input (default `true`) and passes `--release`, so every consumer of `@v2` gets Releases
  on its next fan-out. Reusable beyond `core/` consumers: any repo (e.g. dotfiles-Windows
  on an `nvim/`/`starship/` sync) can call the workflow to self-tag-and-release.

## [v2.3.0] - 2026-06-29

### Fixed

- **`auto-tag.sh` hardened against irregular tags + arg edge cases.** Tag discovery now
  filters to a strict `^vX.Y.Z$` regex instead of git's loose `--list` glob, so a
  prerelease/suffixed tag (`v1.2.3-rc1`) or a moving major alias (`v2`) can no longer be
  mistaken for the latest release (which would have double-tagged or fed a non-numeric
  component into the bump). Version components are coerced base-10 (`10#`) so a zero-padded
  tag (`v1.08.0`) doesn't trip octal arithmetic. `--bump`/`--initial`/`--color` now error
  cleanly on a missing value instead of mis-consuming the next flag. `usage()` documents
  every flag + default, and the re-push hint quotes `$REPO`/`$NEXT`.
- **`auto-tag-call.yml` pins its `dotfiles-core` checkout to `@v2`.** The script is now
  fetched from the same major line callers pin the workflow to, so the tag-cutter's
  behavior can't drift from the pinned `@v2` definition between releases (matching the
  `@vN` policy). Dropped the redundant `fetch-tags` (fetch-depth 0 already brings tags).

## [v2.2.0] - 2026-06-29

### Added

- **Automatic OS-repo release tagging on Core fan-out
  (`.github/workflows/auto-tag-call.yml` + `scripts/auto-tag.sh`).** An OS repo carries two version lines — the Core it vendors
  (`core.lock`, advanced by `sync-core.sh` on every sync) and its OWN `vX.Y.Z` tag, which
  used to move only by hand and so drifted (most repos froze at an old tag; the newest had
  none). A new reusable `workflow_call` lets each OS repo cut its next tag automatically
  when a fan-out lands new `core/` on its `main`: PATCH-bump by default (a new Core is a
  maintenance bump of the consumer), `bump: minor|major` for a deliberate release. The
  version math lives in `scripts/auto-tag.sh` (shellcheck-clean, dry-run by default), is idempotent
  (a no-op when HEAD is already a `vX.Y.Z` release), and tags in CI — so no operator
  round-trip and no reliance on a local tag push. Each OS repo adds a three-line caller
  (`on: push` to `main`, `paths: ['core/**']`).

## [v2.1.1] - 2026-06-29

### Fixed

- **`bootstrap.sh --links-only` no longer aborts when zsh isn't installed.**
  `blib_set_login_shell` did `zsh_path="$(command -v zsh)"`; with zsh absent that
  substitution exits non-zero, and under the bootstrap's `set -e` it aborted the run
  _before_ the `[[ -n "$zsh_path" ]] || return 0` guard that was meant to handle the
  missing-zsh case — surfacing as a links-only CI failure in the one base image
  without zsh preinstalled (`gentoo/stage3`). Now `command -v zsh || true`, so the
  guard decides, not errexit. No behavior change where zsh is present.
- **`tag-release.sh --push` no longer pushes the protected `main` branch.** `main`
  enforces required status checks (GH013), so the old step — `git push origin "$BRANCH"
  && git push origin "$TAG" && git push -f origin "$MAJOR"`, branch FIRST — had its
  branch push rejected, which short-circuited the `&&` chain so the tags never pushed
  either: `--push` failed outright and could never complete a release through the push
  path. The step now pushes the immutable `vX.Y.Z` tag and force-moves the `vN` major
  alias ONLY (tags aren't branch-protected), then prints the PR recipe to land the
  release commit on `main` (`HEAD:release/vX.Y.Z` → PR → merge commit), matching how
  releases actually ship (e.g. #95). The non-push recipe block was corrected the same way.

## [v2.1.0] - 2026-06-29

### Fixed

- **`starship.toml` VPN segment no longer spams on Windows.** The `[custom.vpn]`
  probe (`ifconfig …`) is Unix-only; once the canonical file synced to the Windows
  host verbatim, starship ran it every prompt and hit `command_timeout` with a noisy
  `custom command … timed out` WARN. Split it into OS-gated `[custom.vpn_macos]` /
  `[custom.vpn_linux]` modules (a custom module's `os` takes one value — no "unix"),
  so Windows matches neither and never runs the probe. Unchanged on macOS/Linux.

### Added

- **Core-integrity CI guard (`make core-integrity` + `core-integrity.yml`).** A
  durable, CI-runnable tamper check: it compares each OS repo's vendored `core/` tree
  object against the commit its `core.lock` pins (content-addressed, so any hand-edit
  diverges the hash). Replaces the local-only `.git/hooks` core-guard, which couldn't
  run on a fresh clone or in CI. Companion to `fleet-drift` (integrity vs staleness) —
  both run weekly and on demand.
- **Per-repo core-guard (`core-integrity-call.yml` + `core-integrity.sh --self`).**
  A reusable `workflow_call` an OS repo invokes from its own CI to BLOCK a hand-edit
  to its vendored `core/` at PR time (prevention), where the central sweep only
  DETECTS one after the fact. Runs the same tree-SHA comparison via a new `--self`
  mode that checks exactly one repo against its `core.lock`. Each OS repo adds a
  three-line caller.

### Changed

- **Reusable-workflow pin policy: `@vN` moving major tag.** `tag-release.sh` now
  force-advances a `vN` major tag (e.g. `v2`) to each `vN.x` release, alongside the
  immutable `vX.Y.Z` tag. Cross-repo callers of the fleet's reusable workflows
  (`bootstrap-test.yml`, `core-integrity-call.yml`) pin to `@vN` instead of `@main`:
  deterministic between releases (a caller's CI can't change with zero diff in its
  repo) yet still auto-propagating patch/minor guard fixes. Documented in
  `RELEASE-STRATEGY.md`. (Foundation only — re-pinning the existing `@main` callers
  fleet-wide is a follow-up once a `v2` tag is published.)
- **`fleet-drift.sh` labels the Windows row by release tag too.** `_check_repo`
  gained a fourth `tag-key` argument (default `core_tag`); the Windows row passes
  `tag`, so once `dotfiles-Windows`'s `nvim-sync.ps1` stamps a `tag = <release>`
  field into `nvim/.core-ref` (its companion change), the dashboard shows `v2.0.0`
  for Windows instead of the bare SHA — all nine rows now speak in release names.
  Backward compatible: with no tag recorded it still falls back to the short SHA,
  and the drift verdict stays SHA-based. Verified both paths against a fixture.
- **`starship.toml` is now cross-shell (one canonical file).** Added
  `powershell_indicator` to `[shell]` so the single Core `starship.toml` renders under
  both zsh and PowerShell, and dotfiles-Windows now syncs this file verbatim (its new
  `starship-sync.ps1`) instead of carrying a drifted copy. Benign on zsh — starship
  only renders the active shell's indicator.

## [v2.0.0] - 2026-06-28

> **Breaking — keybindings realigned.** The zsh file-picker moved off `Ctrl+F` to
> **`Ctrl+T`**, and the cross-shell keys were settled fleet-wide: **`Ctrl+E`** atuin
> TUI, **`Ctrl+R`** quick fzf history, **`Ctrl+G`** jump-to-session (navi dropped its
> `Ctrl+G` widget for the `navi` command), **`Alt+Z`** zoxide jump. Update muscle
> memory and re-source your shell (or restart it) after the next `make sync`. This is
> the breaking change that makes this release **2.0.0** rather than a 1.x bump;
> everything else below is additive or a fix.

### Changed

- **`/freshness-triage` now covers the CLI tool pins.** The routine reviewed zsh/nvim/
  actions bumps but said nothing about `scripts/tool-versions.env` — the one bump class
  that also needs `make update-tool-checksums` to refresh its `*_SHA256`. Added a section
  so a `*_VERSION` change without its checksum is flagged **Hold** (the audit only checks
  the hash is _present_, not correct, so a stale hash otherwise fails late at the action's
  `sha256sum -c` in CI). Routine-doc only; no code change.
- **Cross-shell keybindings aligned (PARITY.md decisions resolved).** The four open
  parity decisions are settled and implemented on both shells: **Ctrl+T** = file picker
  (zsh moved off `Ctrl+F`), **Ctrl+E** = atuin TUI / **Ctrl+R** = quick fzf history,
  **Ctrl+G** = jump-to-session everywhere (zsh sesh; the host gets a psmux sessionizer,
  with navi demoted from its Ctrl+G widget to the `navi` command), and **Alt+Z** = zoxide
  jump + `gaf`/`grf`/`grsf` fuzzy git staging ported to pwsh. Core's functional change is
  the file-picker rebind (`zsh/bindings.zsh`: `Ctrl+F`→`Ctrl+T`), with the announced key
  updated everywhere it appears (`zsh/fzf.zsh` warning + comments, the `core-help` cheat
  row in `zsh/functions.zsh`, `tmux/scripts/tmux-cheat.sh`, `README.md`, and the
  `test-core.sh` assertions); the pwsh half lands in `dotfiles-Windows`. The six rows
  moved to `aligned` (file-picker, atuin, dir-jump, session-picker, fuzzy-git, cheat) are
  each enforced by a `scripts/parity-check.sh` needle. `make audit` + `make parity-check` green.
- **`bootstrap-lib.sh` gains opt-in dry-run + tallies** (`lib/bootstrap-lib.sh`) — the
  shared provisioning scaffold now honors `BLIB_DRY=1`: `blib_link` / `blib_seed` /
  `blib_link_core` / `blib_write_zshrc_loader` / `blib_set_login_shell` PRINT what they
  would do and change nothing — every mutation (symlink, backup, seed copy, chmod, the tpm
  clone, the ssh perms, the `.zshrc` write, the `chsh`) is guarded — so an OS bootstrap's
  `--dry-run` can preview the whole plan instead of each repo hand-rolling it. `blib_link`
  also gained an idempotent already-correct-link no-op and a missing-source skip; the two
  inline git/sesh seed blocks are unified into a new `blib_seed`; `BLIB_*` counters +
  `blib_wire_summary` give a "N linked · M seeded · K backed up" footer. **Backward
  compatible** — `BLIB_DRY` defaults off and the non-dry path is byte-for-byte the prior
  behaviour, so the already-adopted Fedora/Arch/Alpine/openSUSE/Gentoo/Kali bootstraps are
  unaffected. This unblocks MacBook adopting the shared scaffold without losing its
  `--dry-run`. Verified: dry run creates zero files; a real run wires all 25 links + 2
  seeds; a re-run backs up nothing.
- **De-forked `update.zsh`'s per-shell path** (`zsh/update.zsh`) — the throttle check
  and the upgrade nudge ran `date +%s` once and `sed -n Np` twice on **every**
  interactive shell, three subprocess spawns (~1.7 ms each, measured) on the critical
  path before the first prompt — the exact fork tax this stack's cached inits + deferred
  plugins exist to avoid. Replaced with zsh builtins: `$EPOCHSECONDS` (a `zsh/datetime`
  param) for the clock and `$(<file)` + `${(f)…}` for the two-line cache read, removing
  all three forks (~5 ms off a warm shell) with byte-identical behaviour and a `date`
  fallback if the module is unavailable. Profiled with `make profile`; the `_pkgup_*`
  parse + nudge unit tests are unchanged and green. (A profile-led pivot: caching
  `tools.zsh`'s `command -v` probes — only ~1.8 ms total, and a stale cache could hide a
  newly-installed tool — was measured and rejected as not worth the footgun.)
- **Dropped `dotfiles-Debian` from the documented fleet.** The Debian OS-native
  repo was only ever planned, never created, and is no longer being pursued — so
  the fleet docs that named it as a real target were ahead of reality. Removed it
  from the OS-native repo lists (`README.md`, `CLAUDE.md`, `CONTRIBUTING.md`,
  `SECURITY.md`, `PORTING-MATRIX.md`), reframed it in `scripts/os-repos.txt` from
  "planned" to a documented permanent absence (so it is not re-added), and dropped
  it from the `claude-routines` fleet-clone loop. This also reconciles the
  "nine-repo system" / "seven vendoring OS repos" counts, which the phantom Debian
  entry had thrown off by one. Debian _distro-family_ facts (the `bat`→`batcat` /
  `fd`→`fdfind` renames, Kali being Debian-family) are unaffected and retained.
- **Hardened the Track B module selector** (`lib/bootstrap-lib.sh`) — two fixes from
  review of the fan-out PRs. `blib_select` now **fails fast on an unknown flag** (a
  `*)` arm warns + `exit 1` instead of silently falling through without recording a
  selection, so a caller typo can't make filtering appear to "work" while wiring
  everything). And `blib_selected_note` now **mirrors `blib_want`'s precedence**: since
  `--only` is an allowlist that wins when set, a co-present `--skip` is ignored — the
  note reports a single active mode (`only` when set, otherwise `skip`) rather than
  appending a misleading `(skipped: …)` suffix that was never applied. **Backward
  compatible** — the single-selector and no-selector paths are unchanged. `test-core.sh`
  Section G gains an unknown-flag rejection case, a `--skip`/both-set precedence check on
  the note, and a `BLIB_MODULES` drift guard pinning the production group list to the
  tested oracle. `make audit` green.

### Added

- **Auto-published GitHub Releases on tag push** (`.github/workflows/release.yml`).
  Pushing a `vX.Y.Z` tag now publishes the GitHub Release automatically, finishing
  the `make release … && make tag PUSH=1` path. The Release body is the curated
  `CHANGELOG.md` section for that version (not a git-cliff commit digest — CHANGELOG
  is the source-of-truth prose), and the job refuses to publish unless the tag is a
  clean SemVer that matches `core.version` at the tagged commit and the section
  exists. Uses the built-in `GITHUB_TOKEN` via the preinstalled `gh` CLI — no PAT,
  no third-party action. Re-running updates the existing Release's notes idempotently.
  Also refreshed `cliff.toml`'s header (the repo DOES git-tag now) and
  `RELEASE-STRATEGY.md` (§5 checklist + §6) to match.
- **Release-automation: the three gaps `RELEASE-STRATEGY.md` flagged are now
  wired.** (1) `sync-core.sh` stamps a `core_tag` field (`git describe` of the
  vendored commit) into each OS repo's `core.lock`, and `fleet-drift.sh` shows it
  in the `RECORDED` column — so the drift dashboard speaks in named releases, not
  just SHAs (the SHA still drives the verdict; the tag is display only, and the
  line is emitted only once Core actually carries a tag, keeping `core.lock`
  byte-identical to today until the first release). (2) A new `audit-arch` leg in
  `ci.yml` runs the shell-scope audit inside `archlinux:latest` (rolling glibc
  toolchain, newer than Ubuntu LTS), mirroring the existing `audit-alpine`
  (musl/busybox) leg — so Core is proven on both named container userlands before
  a tag. (3) `scripts/tag-release.sh` + `make tag` finish a release: commit
  `core.version` + `CHANGELOG`, create the annotated `vX.Y.Z` tag, re-run the
  audit gate; pushing is opt-in (`make tag PUSH=1`). `make release VERSION=X.Y.Z
  && make tag` is now the whole cut end to end.
- **`RELEASE-STRATEGY.md` — the cadence, tagging, and rollout policy.** The repo
  shipped all the release _machinery_ (`core.version`, `scripts/release.sh`, the
  `sync-core.sh` fan-out gate, `core.lock` provenance, the Monday freshness/drift
  bots) but no documented _policy_ tying it together. The new doc adds that: Core
  as the sole versioned unit, a three-track cadence (continuous / weekly pin bumps
  / monthly + security tags), SemVer mapped to host blast-radius, why the
  three-layer subtree model beats `common/`-plus-conditionals, and a canary-first
  staged rollout so a Core release reaches one OS before all eight. Registered in the audit's
  `META_ALLOWLIST`. Docs-only; no behavioral change.
- **`dotfiles-Defense` joins the fleet as the defensive (blue) Role.** The
  three-layer model always had room for a second Role beside `dotfiles-Kali`;
  defender-authored capability (Sigma rules, Sysmon baselines, Zeek/Suricata
  tuning, SIEM content, the hunt/triage workflow, a Dockerized detection lab) now
  has its own repo instead of living as attack-paired notes in Kali's
  `PURPLE-TEAM.md`. Core is vendored into it like any OS/Role repo, so the fleet
  grows: **nine → ten** config repos, **eight → nine** machine repos, **seven →
  eight** Core-vendoring targets. This sync carries the count + Role-layer wording
  updates fleet-wide (`README.md`, `CLAUDE.md`, `ARCHITECTURE.md`, `SECURITY.md`,
  `CONTRIBUTING.md`, the issue templates) and adds `dotfiles-Defense` to
  `scripts/os-repos.txt` so `sync-core.sh` fans Core into it. Docs/data only; no
  behavioral change to Core.
- **`bootstrap-lib.sh` gains `--only`/`--skip` module selection** (`lib/bootstrap-lib.sh`)
  — the shared scaffold can now wire a SUBSET of the Core groups: `zsh nvim tmux git
  prompt tools`. New `blib_select <--only|--skip> <csv>` (validates a comma-separated
  selector — empty / leading / trailing / doubled commas and unknown groups all abort),
  `blib_want <group>` (consulted by `blib_link_core`, `blib_link_os_layer`,
  `blib_write_zshrc_loader`, `blib_set_login_shell`), and `blib_selected_note` for a
  summary suffix. Each OS overlay rides with its Core group (`os.zsh`→zsh, `os.conf`→tmux,
  `os.gitconfig`→git). This is the Core half of the dotfiles-web Bootstrap Command
  Generator's "Track B"; each OS `bootstrap.sh` just routes its `--only`/`--skip` here.
  **Backward compatible** — with neither selector set everything is wired exactly as
  before, so every existing caller is unaffected. `make audit` green.
- **`gsync` upstream-sync shortcut** (`.bin/sync-upstream.sh`, `zsh/aliases.zsh`) —
  a one-word alias that `git subtree push`es an OS repo's vendored `core/` subtree
  back upstream to dotfiles-core (`main`) — the prefix that matches the registered
  `core/` ⇄ root@main subtree boundary. The runner refuses to run unless a `core/`
  subtree is present (so it no-ops in dotfiles-core, the source of truth) and bails
  on a dirty working tree. The alias resolves the script relative to the sourced
  module via the `${(%):-%x}` trick (the same one `maint.zsh` uses), so the
  shortcut survives the `core/` subtree vendoring without putting `.bin` on `PATH`.
  Registered in `core.manifest`.
- **`ARCHITECTURE.md`** — a strategic architecture overview: the three-layer
  model and its boundary test, the full fleet map (which repos vendor `core/`
  and which don't), the one-directional subtree vendoring topology, the
  load-bearing zsh load order, the audit gate, and the rationale for the model.
  Sits above `README.md`/`CONTRIBUTING.md` (which stay operational) and
  cross-references them. Added to the audit's repo-meta allowlist; it is docs,
  not shipped Core.
- **`parity-check` gate** (`scripts/parity-check.sh`, `make parity-check`, weekly
  `.github/workflows/parity-check.yml`) — mechanises the `aligned` rows of `PARITY.md`:
  asserts a distinctive needle (starship/zoxide/atuin init, the fzf tokyonight palette,
  the `fd` default command) is present in **both** a zsh source and the pwsh source,
  failing when one side drifts. Reads pwsh from a sibling `dotfiles-Windows` checkout
  (skipped with a notice if absent, unless `--strict`; the workflow clones it and runs
  `--strict`), the same cross-repo pattern as `fleet-drift.sh`. The fzf-palette row is
  the regression guard for the parity fix just shipped; keybinding rows join the checker
  as each open decision is made. `make audit` green.
- **`PARITY.md` — the cross-shell parity contract** — the source of truth for what
  "the same on zsh and PowerShell" means, mapping every prompt/alias/keybinding/
  function capability to `aligned` (must stay in step), `deliberate` (intentional
  platform difference), or `gap` (open item). Makes the WSL-zsh ↔ Windows-pwsh
  divergences a documented decision instead of silent drift, and names the open
  decisions (the `Ctrl+G` sesh-vs-navi collision, the file-picker key, the atuin
  key, the `gaf`/`grf`/`grsf` + `Alt+Z` ports). Paired with a same-change fix that
  brings the **fzf tokyonight-storm palette to pwsh** (`dotfiles-Windows`
  `powershell/core/10-tools.ps1`), which previously fell back to terminal-default
  colours — the first `aligned` row closed. A future `scripts/parity-check.sh` can
  mechanise the `aligned` rows the way `fleet-drift.sh` mechanised provenance.
- **`core/` edit guard** (`blib_install_core_guard` in `lib/bootstrap-lib.sh`, wired into
  `scripts/sync-core.sh`) — a local `pre-commit` hook that refuses commits touching the
  vendored `core/` subtree, turning the prose rule "never hand-edit `core/`" into a
  mechanical block. Motivated by a real incident: an upstream "Lazy lock update" edited a
  vendored `core/nvim/lazy-lock.json` directly, drifting it from canonical Core. `sync-core.sh`
  now (re)installs the hook into every repo it fans out to (so the protection lands on the
  maintainer's machine, where the edit happens) and exempts its own legitimate subtree
  writes via `DOTFILES_ALLOW_CORE_EDIT=1`; a one-off bypass is the standard
  `git commit --no-verify`. Idempotent and non-destructive — it never clobbers a
  pre-existing unrelated `pre-commit` hook. Covered by hermetic git tests in
  `scripts/test-core.sh`. (Wiring it into each OS `bootstrap.sh` for fresh clones rides
  along with the pending `bootstrap-lib.sh` adoption.)
- **Fleet-drift check** (`scripts/fleet-drift.sh`, `make fleet-drift`, and a weekly
  `.github/workflows/fleet-drift.yml`) — reads every OS repo's `core.lock`
  (`core_sha=…`) plus `dotfiles-Windows`'s `nvim/.core-ref` (`commit = …`) and reports
  which repos lag Core's tip (BEHIND/AHEAD/DIVERGED, quantified in commits). Closes the
  gap where the per-repo provenance markers existed but nothing compared them, so a repo
  could silently sit on a stale Core (how the nvim lockfile drifted). Read-only — the
  fix is a human running `make sync`; a not-checked-out repo is skipped unless `--strict`.
  The reference commit is `--ref`/`$CORE_REF_SHA` → `origin/main` → `main` → `HEAD`.
  Fleet list is the same `scripts/os-repos.txt` `sync-core.sh` reads; the scheduled
  workflow anonymously shallow-clones the public repos and fails red on drift.
- **`.github/workflows/bootstrap-test.yml`** — a _reusable_ (`workflow_call`)
  bootstrap integration test, authored once here and called by a thin ~10-line
  stub in each OS repo, so the OS repos gain CI without each carrying a duplicated
  copy of the logic (the same fan-out the Core layer exists to kill). Two jobs:
  `lint` runs `shellcheck -x` + `bash -n` + `--help` on `bootstrap.sh` (the OS
  repos previously had no CI at all, so this is their first gate); `links-only`
  runs `bootstrap.sh --links-only` inside the target distro's container and
  asserts the symlink graph + the generated `~/.zshrc` (it pre-seeds the tpm dir
  to skip the network clone, mirroring `test-core.sh`'s offline technique, and
  leaves the actual module load — already covered hermetically by `test-core.sh` —
  alone). Callers pass `image`/`prep`/`offensive`; Kali sets `offensive: true`.
- **`lib/bootstrap-lib.sh`** — a vendored BASH provisioning scaffold that ends the
  per-repo bootstrap fan-out. Roughly half of each OS bootstrap.sh was the _same_
  code — `link()`, `read_pkgs()`, WSL detection, the Core-symlink loop, the `.zshrc`
  loader heredoc, the default-login-shell logic — copy-pasted and then independently
  reformatted, so a fix had to be made in every repo by hand (the exact N-way drift
  Core exists to kill, leaking through the one file that can't be vendored). The
  shared half now lives here as `blib_*` helpers (`blib_link`, `blib_read_pkgs`,
  `blib_is_wsl`, `blib_link_core`, `blib_link_os_layer`, `blib_write_zshrc_loader`,
  `blib_set_login_shell`), sourced by each bootstrap.sh alongside `lib/ux.sh`. The
  loader writer takes the module list as an argument, so a role repo (Kali) injects
  its `offensive` stage; the login-shell helper takes `$BLIB_SU` so a doas-only or
  root box works. The `core/`-presence check stays inline per bootstrap (you cannot
  source a lib out of `core/` before confirming `core/` exists). Listed in
  `core.manifest`; sourced (non-exec) like `lib/ux.sh`. Adopting it in each OS
  bootstrap.sh is a follow-up that lands after this is synced out.
- **`pullall [dir]` shell function** (`zsh/functions.zsh`) — fast-update every git
  repo under a parent directory in parallel: prunes deleted remote branches,
  stashes uncommitted tracked changes, switches to each repo's auto-detected trunk
  (main/master/trunk/… via `origin/HEAD`, not a hard-coded `main`), fast-forwards
  it, pops the stash back (reporting a pop conflict instead of swallowing it), then
  prints a summary card. The parent directory is configurable (argument →
  `$PULLALL_DIR` → CWD) so Core stays machine-agnostic; parallelism via
  `xargs -P` (`$PULLALL_JOBS`, default 10). Colour is TTY/`NO_COLOR`-aware and
  repo paths are passed positionally (no shell injection from odd names). Ships
  with a `_pullall` completion, a `core-help` row, and behavioural tests.
- **`dotfiles-Defense-PLAN.md`** — a forward-looking architecture note plus a
  complete, ready-to-instantiate skeleton for a future `dotfiles-Defense` repo
  (the defensive/blue Role layer that mirrors `dotfiles-Kali`). Records the
  red/blue split decision, the trigger for standing the repo up, the layer-table
  identity, and every scaffold file verbatim (README, CLAUDE.md, bootstrap,
  `defense.zsh`, methodology, gitignore, compose stub, templates) so the repo can
  be `git init`-ed when the trigger is met. Added to the audit's repo-meta
  allowlist; it is planning, not shipped Core.
- **Claude Code project memory + maintenance routines** (`CLAUDE.md`, `.claude/`) —
  a root `CLAUDE.md` encoding the three-layer model, the "is it Core?" test, the
  manifest contract, and the load order so every Claude session reasons from the
  real rules. Three on-demand slash commands automate the judgment-heavy chores the
  audit can't: `/doc-audit` (prose-vs-reality drift across the fleet, via the
  `doc-consistency` subagent), `/tool-scout` (research the modern-CLI stack for
  tools worth adopting, via the `tool-scout` subagent), and `/freshness-triage`
  (review dependency-bump PRs against upstream changelogs). All report-first; none
  vendor out without a green `make audit`. `CLAUDE.md` added to the audit's
  repo-meta allowlist (`.claude/` was already a prefix).
- **Scheduled maintenance bots** (`.github/workflows/claude-routines.yml`) — run the
  `/doc-audit` and `/tool-scout` routines headless on a weekly cron (and on demand),
  filing findings as a deduplicated GitHub issue. The Claude Code CLI is installed
  from npm (pinned via `CLAUDE_CODE_VERSION` in `scripts/tool-versions.env`) — no
  third-party action, mirroring `freshness.yml`. Auth is a Claude subscription token
  (`CLAUDE_CODE_OAUTH_TOKEN`, from `claude setup-token`); inert until that secret is
  set (the workflow no-ops with a warning otherwise).
- **`make release-notes` + `cliff.toml`** — git-cliff config + a Makefile target that
  drafts a GitHub Release body from Conventional Commits since the last release commit.
  Scoped dev-tooling (audit allowlist, not `core.manifest`, zero runtime cost); it does
  **not** generate `CHANGELOG.md` (that stays hand-curated and is promoted by
  `scripts/release.sh`). Surfaced by `/tool-scout` (issue #44).
- **`aliases.md`** is now surfaced in the changelog — the cross-fleet aliases cheat
  sheet (Core + per-OS + offensive layers), previously shipped without an entry.

### Fixed

- **`blib_set_login_shell` no longer trusts a non-executable `command -v zsh`.**
  `command -v` also resolves aliases/functions, so a shadowed `zsh` could yield an
  alias body rather than a path; it's now required to resolve to a real executable
  (`[[ -x ]]`) before being handed to `chsh`/`usermod`. The `/etc/passwd` fallback
  (used when `getent` is absent, e.g. busybox/Alpine) switched from a `grep "^$user:"`
  regex to `awk -F: -v u="$user"`, so a username containing a regex metacharacter
  can't mis-match. Robustness only; no behavior change for normal setups.
- **Startup nudges no longer execute under a substitution prompt** (`zsh/update.zsh`).
  `_pkgup_notice` ("N updates available — run \`up\` to apply") and `_core_welcome`
  ("dotfiles Core loaded — run \`core\`…") rendered their hints with `print -P` and wrapped
  the verb in **backticks**. Under `setopt prompt_subst` — which starship and any
  substitution prompt enable — `print -P` performs command substitution, so the backtick'd
  word was _executed_ rather than printed: the update nudge fires from a precmd hook before
  `up()` is defined, surfacing as `command not found: up` on every package-manager box (and,
  once defined, silently triggering a privileged upgrade). Both hints now use single quotes
  (`'up'` / `'core'`), which are literal under prompt expansion; the `NO_COLOR` branch already
  used the safe `print -r`. Surfaced by a `make sync` audit failing on a starship MacBook. A
  new `test-core.sh` regression seeds a cached count under `prompt_subst` with an `up()`
  sentinel and asserts the nudge mentions `up` but never runs it.
- **`dotfiles-Defense-PLAN.md` scaffold: `bootstrap.sh` `--links-only` was dead.** The
  reproduced `bootstrap.sh` set `LINKS_ONLY` but never read it, so `--links-only` still ran
  the host-tool/docker probe (and shellcheck flagged the unused var). Guard the probe with
  `(( DO_CHECK && ! LINKS_ONLY ))` so `--links-only` truly just wires symlinks, and rewrite
  the `(( missing == 0 )) && ok || warn` line as if/then/else. The scaffold is now
  shellcheck-clean and was exercised end-to-end in a sandbox (`--links-only` wires Core +
  the defense stage); the "validated" note now says so. Planning doc only (allowlisted
  repo-meta) — nothing shipped/vendored.
- **`gsync` runner + core-guard installer hardening** (review follow-up to the
  fan-out PRs). `.bin/sync-upstream.sh`: normalize to the git toplevel first so
  `gsync` works from any subdirectory (it is an absolute-path runner); use
  `git status --porcelain` for the clean-tree check so untracked files also block
  (`git diff-index HEAD` missed them); and reword the failure hint to be
  auth-agnostic (the remote is HTTPS, not SSH) and point at the right re-pull
  command for an OS repo. `zsh/aliases.zsh`: `gsync` is now a wrapper function,
  not an alias, so a dotfiles path containing whitespace stays one word and args
  pass through — with a matching `_gsync` completion and `core-help` row.
  `lib/bootstrap-lib.sh` `blib_install_core_guard`: detect the git work tree and
  hooks dir via `git rev-parse` (so worktrees/submodules, where `.git` is a file,
  get the guard too), skip with a warning when `core.hooksPath` is set (installing
  into the ignored `.git/hooks` was false protection), and return non-zero instead
  of silently succeeding if the hooks dir can't be created. New hermetic test
  covers the `core.hooksPath` skip.
- **`sync-core.sh` pre-fan-out audit no longer false-fails on the core-guard test.**
  The script `export`s `DOTFILES_ALLOW_CORE_EDIT=1` for its own legitimate subtree
  commits, but that exemption was still in the environment when it ran the
  pre-fan-out `audit-core.sh` — whose behavioral suite commits to a throwaway
  `core/` and asserts the guard hook BLOCKS it. The inherited exemption made that
  assertion fail, reding an otherwise-green tree and forcing `SYNC_SKIP_AUDIT=1`.
  The audit now runs via `env -u DOTFILES_ALLOW_CORE_EDIT` (it never writes to
  `core/`, so it needs no exemption); the fan-out commits keep theirs.
- **`bootstrap-lib.sh` now wires three Core files it silently dropped.**
  `blib_link_core` linked starship/nvim/mise/git/tmux/clip but omitted
  `core/lazygit/config.yml` (→ `~/.config/lazygit/config.yml`), `core/vim/vimrc`
  (→ `~/.vimrc`), and the `core/sesh/sesh.toml.example` seed
  (→ `~/.config/sesh/sesh.toml`) — three files that are in `core.manifest` (the
  manifest comments even spell out their destinations) yet reached no machine,
  inherited from the per-repo bootstraps this library consolidated. lazygit + vim
  symlink like starship; sesh is seeded (copied, never relinked) like the git
  identity file. The matching `bootstrap-test.yml` assertions for these three were
  briefly **deferred** — that reusable test is referenced `@main` by every adopter, so
  it can only assert what each adopter's CURRENT vendored `core/` produces, and asserting
  the wiring before `make sync` propagated it would have red-flagged Fedora/Kali. They are
  **now re-added**: every adopter's `core.lock` is at a Core that includes the wiring, so
  the `@main` test asserts lazygit/`~/.vimrc`/seeded-sesh again without false reds.
- **`freshness.yml` opens its pin-bump PRs against the default branch**, not the
  dispatched ref (`GITHUB_REF_NAME`), and uses a ref-independent concurrency group —
  so a manual run from a feature branch can't target the wrong base or race the cron.
- **`aliases.md`** — corrected the `myip` expansion (it redirects stderr:
  `curl -fsS https://ifconfig.me 2>/dev/null && echo`) and repo-qualified the
  cross-repo source paths in the header so they don't read as broken local links.
- **`doc-consistency` subagent** — aligned its system description with the canonical
  nine-repo, three-layer (Core → OS-native → Role) wording.
- **`audit-core.sh`** — clarified the META-allowlist comments: those files are "not
  shipped Core" (absent from `core.manifest`), not "never vendored" (the subtree copy
  carries them physically).
- **Doc drift caught by `/doc-audit`** — corrected "vendored into/fans out to _nine_
  OS repos" → _eight_ (Windows vendors no `core/`) in `CHANGELOG.md` + `CONTRIBUTING.md`;
  added the manifest-listed `zsh/loader.zsh` and `lazygit/config.yml` to the README
  Layout tree; completed the README tmux-scripts list (added `tmux-battery`/`tmux-cheat`);
  and attributed the `cheat` alias to `functions.zsh` (not `aliases.zsh`) in `aliases.md`.

### Security

- **CI tool downloads are now SHA-256 verified.** The `setup-core-tools` composite
  action previously fetched its pinned gate binaries (shellcheck, actionlint, gitleaks,
  neovim) with `curl … | tar` and **no integrity check** — a tampered or MITM'd release
  asset would have executed inside the gate. Each install now downloads to a file,
  verifies it against a pinned hash from `scripts/tool-versions.env`, and only then
  installs; a mismatch fails the build. `shfmt` was folded into the action (it was the
  last tool still installed via inline `curl` in the OS-repo lint workflows), so one
  verified definition now covers every downloaded gate tool.
- **`scripts/tool-versions.env`** gained a `*_SHA256` per downloaded tool (the single
  source the action reads alongside each `*_VERSION`), plus `SHFMT_VERSION`.
- **`scripts/audit-core.sh`** gained a "tool download integrity" section that fails the
  audit if any pinned `*_VERSION` lacks a 64-hex `*_SHA256` — a version can no longer be
  bumped without refreshing its checksum.
- **`scripts/update-tool-checksums.sh`** (new) recomputes the pinned hashes from the
  exact assets the action downloads, so a version bump is a one-command checksum refresh.
- **`setup-core-tools` skips only on its OWN verified binary, not any `command -v` match.**
  The install steps short-circuited on `command -v <tool>`, which also matches a binary
  preinstalled on the runner (`ubuntu-latest` ships shellcheck) — so the verified install
  was silently skipped and the gate ran the unpinned, unverified system shellcheck. Each
  step now skips only when the binary is already in the action's own `bindir` (a genuine
  cache restore); the caller prepends `bindir` to `PATH`, so the verified binary always
  shadows any preinstalled one. Restores the integrity + pinning guarantee for shellcheck.

## [v1.2.0] - 2026-06-21

### Added

- **fzf-assisted git staging** (`zsh/git.zsh`) — `gaf` / `grf` / `grsf`, fuzzy
  multi-select counterparts to `git add` / `restore` / `restore --staged`. Each
  guards on `fzf` like the `fzf.zsh` zle widgets, depends only on git + fzf (both
  in the Core stack), and NUL-pipes paths so filenames with spaces survive `xargs`.
- **`vim/vimrc`** — a plugin-free, self-contained vim fallback for boxes where only
  stock vim exists (minimal containers, rescue shells, freshly-SSH'd servers). netrw
  as the file browser, no network, keybindings echoing the Neovim config. The OS
  bootstrap symlinks it to `~/.vimrc`.

### Changed

- **Adaptive eslint linting** (`nvim/lua/gerrrt/plugins/nvim-lint.lua`) — the eslint
  family (js/ts/jsx/tsx/svelte/vue) now lints only when an eslint config is found
  upward from the buffer, mirroring the existing SC1071/ruff guards. Prevents
  `eslint_d`'s hard error from surfacing as a phantom diagnostic in projects with no
  eslint config. Non-eslint linters still run unconditionally.

## [v1.1.0] - 2026-06-19

## [v1.0.0] - 2026-06-18

### Added

- **lazygit theme** (`lazygit/config.yml`) — a tokyonight-storm theme matching
  `starship.toml`, the tmux bar, and `zsh/fzf.zsh`, so lazygit (reached via the `lg`
  alias and the `prefix + g` tmux popup) reads as one palette with the rest of the
  stack. Bootstrap symlinks it to `~/.config/lazygit/config.yml`.
- **`genpw [length]`** — portable random-password generator (`zsh/functions.zsh`):
  prefers `openssl`, falls back to `/dev/urandom` so it works on a bare rescue shell.
  Ships with its completion (`zsh/completions/_genpw`) and a `core-help` entry.
- **fzf tokyonight palette** — `FZF_DEFAULT_OPTS` (`zsh/fzf.zsh`) now sets an explicit
  tokyonight-storm `--color` set instead of inheriting the terminal palette, keeping
  fzf on-theme even over SSH into an unthemed box.
- Audit **`--strict`** now fails only on gates skipped because their TOOL is absent (an
  out-of-scope skip stays intentional), so CI runs it on the Linux leg — closing the last
  "green because a linter silently failed to install" gap. CI also installs `python3-yaml`
  so the YAML-parse gate is honest under `--strict`.
- **Core⇄OS boundary** audit gate: portable `zsh/*.zsh` modules may carry no OS-absolute
  paths (`/opt/homebrew`, `~/Library`, …), mechanically enforcing the README's "if it
  changes with the OS it isn't Core" rule. `zsh/maint.zsh` (the OS-switched scheduler
  surface) is the documented exception.
- **`core.version` ↔ `CHANGELOG`** coherence gate: a prerelease stamp must keep an
  `[Unreleased]` section open; a release stamp must have a matching `## [vX.Y.Z]` heading.
- Behavioral coverage for `git.zsh` (`git_main_branch`/`git_current_branch` trunk +
  detached-HEAD resolution) and for `_pkgup_count`/`_pkgup_list` parsing on
  apk/dnf/zypper/pacman — previously only apt was exercised.
- `core-help` now lists the most-used **git aliases** (the OMZ-style set in `git.zsh`),
  so they are discoverable from the cheat sheet.
- `core.version` — a human-readable SemVer stamp vendored into every OS repo, plus a
  `core-version` verb that reads it, so you can tell WHICH Core a given OS repo carries
  from inside it (the subtree squash records the commit; this records the version).
  `scripts/sync-core.sh` prints it on fan-out and the audit asserts it is well-formed.
- `core-doctor` — the shell counterpart to nvim's `:checkhealth gerrrt`: a scannable
  report of which modern-CLI tools Core detected on this box and which integrations are
  live, including the RESOLVED binary names (`fd`/`fdfind`, `bat`/`batcat`) and the
  detected package manager. Read-only.
- `up -n`/`--dry-run` — list the packages that WOULD upgrade and exit, touching nothing
  (the non-destructive inspect the count-only nudge didn't offer).
- `make audit-changed` (`audit-core.sh --changed`) — scope the audit to what your local
  git diff touches, via the SAME `scripts/ci-classify.sh` CI uses; fails safe to the
  full run when the diff can't be resolved.
- First-party completions for `fif`, `fbr`, `core-version`, and `core-doctor`, and a
  `core.version`/`up --dry-run`-aware `_up`; the completion-parity test now covers them.
- `.shellcheckrc` — repo-wide ShellCheck config (`external-sources`, `source-path`,
  `shell=bash`) so author-time, CI, and editor lint identically.
- `zsh/ui.zsh` — shared terminal-UX primitives (`_core_err`/`_core_warn`/`_core_ok`/
  `_core_hint`/`_core_usage`/`_core_confirm`/`_core_spin`), gum-aware with a plain
  fallback on every helper. Loads right after `tools` in the canonical chain and is
  adopted across `functions.zsh`, `op.zsh`, `update.zsh`, and `plugins.zsh`, replacing
  ad-hoc `echo "Usage: …"` lines with one consistent voice (colour only on a TTY,
  `NO_COLOR` honoured, diagnostics to stderr).
- `core-help` (alias `cheat`): a grouped, column-aligned cheat sheet of Core's
  functions, keybindings, and maintenance verbs — the shell counterpart to which-key.
  Plus a once-per-machine first-run hint pointing at it (`CORE_WELCOME=0` to silence).
- First-party zsh completions (`zsh/completions/`) for Core's own verbs — `up`,
  `extract` (archive files only), `mkcd`, `mkbak`, `maint-log`, `openv` — fpath-added
  by `options.zsh` (symlink-safe; no bootstrap symlink needed). The audit now `zsh -n`s
  them alongside `zsh/*.zsh`.
- `scripts/lib/common.sh` — one definition of the colour palette + `pass`/`skip`/`fail`/
  `hdr`/`have` shared by all five gate scripts (the block had been copy-pasted ×5). A
  sourced lib, so — like `zsh/*.zsh` — it stays mode 100644; the audit's exec-bit
  section gained a `scripts/lib/*.sh` arm to assert exactly that.
- `scripts/tool-versions.env` — single source for the pinned dev-tool versions, read by
  CI (loaded into `$GITHUB_ENV`), `make setup`, and the audit. `scripts/setup.sh` +
  `make setup`: a one-command dev bootstrap (pre-commit hooks + version doctor + audit).
- `actionlint` gate on the workflows: an audit section (graceful skip when absent) plus
  a pinned CI install — the workflow YAML is now validated, not just parsed.
- Audit version-consistency section: the `.pre-commit-config.yaml` hook revs are gated
  to equal `scripts/tool-versions.env`, so a one-sided pin bump fails the audit.
- Hermetic behavioral tests for `bin/clip` / `bin/clip-paste` (the highest-fan-out
  runtime artifact — used by zsh, tmux, and nvim): a new section in
  `scripts/test-core.sh` drives the WSL→macOS→Wayland→X11 detection ladder against a
  fake `PATH`, asserting the right backend is chosen. Runs even where zsh is absent.
- Headless Neovim config-load smoke test in `scripts/test-core.sh`: loads the authored
  config layer and every plugin spec offline (no install), catching luacheck-clean Lua
  that is nonetheless a broken config. CI ships a pinned `nvim` (`NVIM_VERSION`) so it
  runs on both userlands instead of skipping.
- Alpine (musl/busybox) CI leg, run via a bind-mounted container, finally exercising
  the busybox-coreutils compatibility the scripts have always claimed.
- `scripts/update-plugins.sh` + `make update-plugins`: deliberately roll the pinned
  zsh-plugin SHAs to upstream HEAD — the runtime-plugin mirror of `make update-hooks`.
- Markdown lint gate: `.markdownlint.jsonc` rule config, a `markdownlint` section in
  `scripts/audit-core.sh` (graceful skip when absent), a `markdownlint-cli2` pre-commit
  hook, and a pinned CI install step — so the docs (the deliverable on a public
  showcase repo) are gated like everything else.
- `scripts/bench-core.sh` gained an optional `CORE_BENCH_BUDGET_MS` budget gate (fails
  when the canonical-chain startup mean exceeds the budget), plus a non-blocking CI
  `bench` job that reports the number on every push.
- `SECURITY.md` and `.github/ISSUE_TEMPLATE/` (bug + feature + config) round out the
  GitHub community profile; `CONTRIBUTING.md` documents a Conventional Commits
  convention.
- Broader behavioral coverage in `scripts/test-core.sh`: `mkbak` byte-identity,
  `extract` unknown-format rejection, and `extract` round-trips for `.tar.gz`/`.gz`
  (the latter skip gracefully when `tar`/`gzip` are absent).
- CI runs the audit on a `[ubuntu-latest, macos-latest]` matrix, gating the macOS
  (bash 3.2 / BSD userland) target — `dotfiles-MacBook` — alongside Linux.
- `scripts/audit-core.sh` and the pre-commit config parse-check every tracked TOML and
  YAML file, catching malformed `starship.toml` / `mise/config.toml` / workflow
  YAML that is valid text but dead at runtime for every consumer.
- This `CHANGELOG.md`.
- `scripts/sync-core.sh` reports the exact dotfiles-core revision (short SHA) each OS
  repo receives, so a sync is traceable.
- `scripts/bench-core.sh` + `make bench`: a hermetic hyperfine benchmark of the
  canonical Core load chain, so startup-perf regressions (the thing tools.zsh's
  caching and plugins.zsh's deferral exist to prevent) are measurable, not silent.
- A `command_not_found_handler` (zsh): a mistyped command now gets a Core-voice miss
  that suggests the nearest Core verb on a near typo (`extarct` → `extract`, via a
  small built-in Levenshtein) or, failing that, an install line for this box's detected
  package manager — instead of zsh's terse default. Interactive-only; `CORE_CNF_ENABLED=0`
  opts out.
- `make doctor` (`scripts/setup.sh --doctor`): the read-only half of `make setup` —
  reports each dev tool against its pin with no install and no audit, for quick "is my
  toolchain aligned with CI?" triage.
- `core-help <word>` filters the cheat sheet to matching rows (and reports a no-match
  cleanly), so jumping to one verb beats scanning the whole sheet.
- `serve` renders the reachable URL as a terminal QR code when `qrencode` is present
  (scan-to-open from a phone) — graceful skip when it isn't.
- `scripts/audit-core.sh --strict`: treat any SKIP as a failure (a gate whose tool was
  absent did not actually run), for release/CI verification where every gate must execute.
- `ui.zsh` primitives: `_core_errbox` (multi-line what/why/fix error blocks),
  `_core_suggest`/`_core_lev` (did-you-mean), reused across the runtime helpers.

### Changed

- The `command_not_found_handler` now also weighs this shell's **aliases** when proposing
  a "did you mean?", so a near miss like `gts`→`gst` is caught, not just the Core verbs.
- The markdown gate resolves `markdownlint-cli2` via PATH → `npx --no-install` →
  `node_modules`, so an off-PATH global install runs instead of skipping (the most-skipped
  gate in remote sessions).
- `_cache_eval` gained `--salt`; the `atuin`/`carapace` inits fold `ATUIN_NOBIND`/
  `CARAPACE_BRIDGES` into the cache filename, so flipping that env busts the cache
  instead of serving a stale init.
- Higher-friction failures now use the structured `_core_errbox` (headline + why/fix):
  `up` with no package manager, and `serve` without `python3`.
- `scripts/setup.sh` provisions `luacheck` via `luarocks` (no clean mise source) and
  emits precise, actionable install hints — closing the last manual onboarding gap.
- Defensive confirms on impactful interactive actions: `please` now previews the exact
  `sudo …` line and confirms before eval'ing it as root (and refuses with no previous
  command); `up` pre-confirms `Apply updates with <mgr>?` before touching the system
  (skipped by `-y`); `serve` warns plainly that it binds `0.0.0.0` and exposes the CWD.
- First-run plugin install shows a spinner on the network-bound `git fetch`/`clone`
  (gum spin when present, a hand-rolled braille spinner otherwise), guarded so an OS
  loader that hasn't adopted `ui.zsh` yet still installs plainly.
- CI is now incremental: a `changes` job classifies the diff and gates the narrow,
  expensive legs — `nvim`+`luacheck` installs run only when `nvim/` changed, and the
  Alpine and bench jobs only when the shell layer changed. SAFE DEFAULT: an unresolved
  diff base or any infra change runs everything, so detection can never hide a check.
- The startup-perf `bench` CI job is now an enforced regression gate
  (`CORE_BENCH_BUDGET_MS=120` over 50 warmed runs), not a report-only, continue-on-error
  step — a gross startup regression now fails the build instead of shipping silently.
- The pinned linter versions moved out of `ci.yml`'s `env:` block into
  `scripts/tool-versions.env`; CI loads them via a "Load pinned tool versions" step.
- Split `bin/` into shipped vs. tooling: `bin/` now holds only what is vendored into
  the OS repos (`clip`, `clip-paste`); the gate scripts moved to `scripts/`
  (`audit-core.sh`, `test-core.sh`, `bench-core.sh`, `sync-core.sh`,
  `update-plugins.sh`). The audit allowlists `scripts/` wholesale, so a new dev tool
  is covered the moment it lands. No consumer impact — those scripts were never in
  the manifest, so they were never vendored.
- `scripts/audit-core.sh` no longer uses the bash-4-only `mapfile`, so the gate itself
  runs on macOS's stock bash 3.2.
- The audit summary now NAMES the checks that skipped (tool absent) and labels such a
  run PARTIAL rather than hiding the gap behind a bare count — several skipped gates
  (markdownlint, actionlint, gitleaks, luacheck, nvim) are CI-enforced, so a clean local
  box can still differ from the gate.
- `core-doctor` now turns its `✗` tools into a copy-pasteable install line for this box's
  package manager, instead of leaving the reader to look each one up.
- Spinner (`_core_spin`) shows elapsed time and ends with a still `✓`/`✗` result frame, so
  a long step reads as progress and finishes with a legible outcome; `extract` routes the
  quiet unpack formats through it. Unknown-format `extract` errors print a what/why/fix block.
- `serve`/`up` suggest the nearest valid flag on an unknown option (did-you-mean).
- De-duplicated the gate scripts: the `_set_scope` area parser, the hermetic plugin-seed
  list, and the `ci-classify.sh` output reader now live once in `scripts/lib/common.sh`
  (consumed by `audit-core.sh`, `test-core.sh`, `bench-core.sh`) — they had drift-prone
  copies. `op.zsh` verbs gained the `emulate -L zsh` every other Core verb uses.

### Security

- Pinned the seven runtime zsh plugins to commit SHAs (`ZPLUGIN_PINS` in
  `zsh/plugins.zsh`) — the last unpinned link in a toolchain that already pins CI
  linters, pre-commit hooks, and GitHub Actions. An unpinned `master` clone fanned an
  upstream breaking change — or a compromised tag — out to all eight machines on the
  next install; installs now fetch exactly the pinned commit.

### Fixed

- `fbr`'s fzf preview used `{1}`, which on the current-branch row (`* main`) is the
  literal `*` — so the preview ran `git log *` and broke. It now lists clean branch
  names (`--format='%(refname:short)'`, `*/HEAD` dropped) and previews `{}`; a remote-only
  pick strips `origin/` on checkout to create the matching local tracking branch.
- `mkbak` could prompt or clobber: `cp -i` (from `aliases.zsh`, parsed first) bled into
  it, so a same-second second backup stopped for a y/n. It now picks the next free `.bak`
  suffix and copies via `command cp`, staying collision-safe and non-interactive.
- `_core_confirm`'s gum path defaulted to **Yes** while the `[y/N]` fallback defaulted to
  No — so the same destructive prompt (`please`/`up`/extract-overwrite) was one-Enter-to
  confirm under gum. It now passes `gum confirm --default=false`, a consistent safe default.
- The `_core-help` completion claimed "takes no arguments", but `core-help` accepts a
  `[filter]`; it now completes that filter with the verbs/sections the cheat sheet knows.
- `serve` now pre-checks the port is bindable (with `SO_REUSEADDR`, as `http.server`
  does) and fails in Core's voice instead of letting a taken port surface a Python traceback.
- `diff` was unconditionally aliased to `diff --color=auto`, which BSD/macOS `diff` (the
  dotfiles-MacBook target) does not support — every `diff` invocation would error there.
  The alias is now applied only after a feature-probe confirms this box's `diff` accepts it.
- fzf / fzf-tab previews hardcoded `bat`/`eza`, so every preview pane printed
  "command not found" on Debian/Ubuntu (bat ships as `batcat`) and on any box without
  eza. Previews now resolve `$BAT_BIN` with a `cat`/`ls` fallback, and a new audit
  section (`fzf preview binary resolution`) locks it so the regression can't recur.
- `fif`, `fbr`, and the Alt-Z zoxide-jump widget assumed `fzf`/`rg`/`git`/`zoxide`
  were present; they now degrade in Core's voice (`_core_err`/`_core_hint`) like `fcd`,
  instead of a raw "command not found".
- Removed leaked `</content>`/`</invoke>` template artifacts from the end of this
  changelog — the exact bug class the new markdown gate now catches.
- Restored non-executable mode (`100644`) on the twelve `zsh/*.zsh` modules. They
  are sourced, not executed, and had regressed to `100755`, failing the audit's
  exec-bit invariant — the exact bug class the audit exists to catch, fanning out
  to all eight OS repos.
- Registered `CODEOWNERS`, `dependabot.yml`, and `pull_request_template.md` in the
  audit's `META_ALLOWLIST` so the manifest reverse-drift scan accounts for them.
