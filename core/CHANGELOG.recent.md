# Changelog — recent releases

GENERATED FILE — do not edit by hand. `scripts/gen-changelog-recent.sh` rewrites it
wholesale, `scripts/release.sh` runs that generator on every release, and
`scripts/audit-core.sh` §9e fails when this file is not byte-identical to a fresh
render. To fix a conflict or a stray edit, re-run the generator — never patch it.

The last 8 released sections of `CHANGELOG.md` (v7.12.0 … v7.5.0), vendored into every OS repo's
`core/` by `core.vendor` so `core whatsnew` can answer offline. The full changelog is
repo-meta and stays upstream:
[dotgibson/dotfiles-core/CHANGELOG.md](https://github.com/dotgibson/dotfiles-core/blob/main/CHANGELOG.md).

## [v7.12.0] - 2026-09-24

### Security

- **The CI floor's template-injection rule now covers push-trigger ref names and workflow
  inputs.** Rule 7 of `scripts/modern-baseline.yml` bans an attacker-influenced `${{ }}`
  expression inside a `run:` body, and it named `github.head_ref` — the fork branch on a
  pull request — but not `github.ref_name`, which on a `push` or tag event is the same
  attacker-chosen string by another trigger (git refnames allow `$ ; & | ( ) { }`). It now
  bans `github.ref_name` and, for uniformity, `github.base_ref`. And its `inputs.` exemption,
  earned by the composite `setup-core-tools/action.yml`, was applied to every gated file,
  which left bare `inputs.*` ungated in the workflows — where it is `workflow_dispatch` free
  text or a value a sibling repo feeds one of Core's `*-call.yml@vN` workflows. A new rule
  7b (`banned_run_interpolation_contexts_workflow_only`) bans it under `.github/workflows/`
  alone. Both were free: every occurrence in the tree was already routed through `env:`
  (#1160).

- **The CI floor bans `secrets: inherit`, and Core stops documenting it.** The caller
  example at the top of `claude-routines-call.yml`, the shape the seven OS repos were told
  to copy, passed `secrets: inherit`. That hands the called `@v7` workflow every secret the
  caller repo holds, declared or not, at a moving tag the caller does not pin. The seven live
  callers had already moved to the explicit `CLAUDE_CODE_OAUTH_TOKEN:` mapping, so only the
  comment was wrong, and it now shows the mapping. A new rule 9 in `scripts/modern-baseline.yml`
  (`banned_call_secrets`) reads the value the way rule 5b reads `write-all`: anchored to the
  key, bare or quoted, a trailing comment tolerated. It was green on arrival, and no workflow
  in the fleet passes it (#1160).

### Changed

- **Two zsh plugin pins roll forward in `zsh/45-plugins.zsh`** (#1156, the freshness bot):
  `zsh-history-substring-search` `14c8d2e0ffae` → `a0bdb0d47dba` and `zsh-syntax-highlighting`
  `2fc57d63067c` → `0bfcb582e71d`. This is the one change in the release that reaches a
  host, so it is recorded here even though a bot landed it — `CONTRIBUTING.md` has no
  carve-out for automation. Both ranges were read against the upstream compare: the first is
  two commits touching only `README.md` (+2/-2, a zplug snippet fix), the second one commit
  adding an Arch install path to `INSTALL.md` (+8/-0). So the pins move and no plugin code
  does; the other six pins were already current.
- **The scaffold's README is now linted for real, and held to Core's.** The suite drove the
  scaffolded repo's markdown leg through a shim that records argv and exits 0, so the README
  `new-os-repo.sh` writes was never judged by the `.markdownlint.jsonc` it writes beside it,
  and its hand-copied shield block could drift from Core's unnoticed (#1162).
  `35-new-os-repo.sh` now runs the real `markdownlint-cli2` on it wherever the tool is
  installed (CI's main leg installs the pinned one), and asserts the header and every
  shield link definition match Core's `README.md` with the repo name swapped. `dotgibson-*`
  (Core's release, on purpose) and `ci-url` (`lint.yml`, not `ci.yml`) are the stated
  exceptions.
- **`new-os-repo.sh` writes the fleet's shield row into the README it scaffolds.** A checkup
  that fetched every badge and link target across the fifteen public READMEs found the two
  newest repos opening with no shield row at all — `dotfiles-NixOS` because this scaffold
  wrote none, and its generated `.markdownlint.jsonc` deliberately left out the MD033
  allowance the row needs ("a fresh OS repo has no showcase page"). The scaffold now writes
  the eight-badge row above the title, the link definitions at the end, the CI badge pointing
  at the `lint.yml` it also writes, and the scoped `MD033` `allowed_elements` stanza the
  siblings carry — so the next repo starts where dotfiles-NixOS had to be brought to by hand
  ([dotfiles-NixOS#11](https://github.com/dotgibson/dotfiles-NixOS/pull/11)). The same
  checkup fixed a dead bash link here (#1151), two logo slugs simple-icons no longer ships in
  each of `dotfiles-Windows` and `dotfiles-Defense`, and `dotfiles-Offense`'s Python badge,
  which read CPython's GitHub releases — it publishes tags — and rendered "no releases or repo
  not found".
- **Two tool pins roll forward: `markdownlint-cli2` 0.23.2 → 0.23.3 and the maintenance
  bots' Claude Code CLI 2.1.273 → 2.1.281.** The weekly freshness review (#1159) found them
  the only pins behind upstream that are not deliberately held. `markdownlint-cli2` 0.23.3
  only updates dependencies, and both versions pin the `markdownlint` library at 0.41.1, so
  no rule is added, renamed or given a new default in Core or in the `lint-call.yml`
  consumers. The pre-commit hook's `rev` moves with it, because §9 keeps the two in step.
  Both are registry installs, so there is no `*_SHA256` to refresh. `shfmt` stays held at
  3.13.1 (#813).
- **Both atuin guard premises re-measured against 18.23.0; both `VERIFIED_AGAINST` anchors move**
  ([#1158](https://github.com/dotgibson/dotfiles-core/issues/1158), run 35956975589). Upstream
  released 18.23.0 on 2026-09-22, one minor past the 18.22.0 the anchors in `zsh/00-tools.zsh`
  carried. One `atuin-guard-verify` dispatch, checksum and build-provenance verified:
  silent discard `holds` (its report job skipped), and autostart self-healing is `moved`
  exactly as it was on 18.22.0. `absent` and `stale` spawn a daemon and land their row, and
  `wedged` blocks on the pidfile lock and loses it (upstream `atuinsh/atuin#4114`, still open).
  That is the shape #1102 already answers by probing and warning rather than standing down, so
  the auto-filed #1177 asks nothing new of Core. Editing an anchor is a claim that the premise
  was re-measured at that version, so this is that claim and not a version bump.

  18.23.0 continues 18.22.0's direction, and the block now says so: an FTS index over captured
  command output and a sync engine replacing the event bus both sit behind the socket, with no
  client-side spool or direct-write fallback (the one PR that would have changed the client's
  connect shape, atuin #4168, closed unmerged). A dead socket still discards, and
  `atuinsh/atuin#3382` (accept-but-silent) is still open, so the steer away from socket
  activation stays.

### Fixed

- **The test suite no longer writes to the developer's real `~/.config/zsh/.zshrc`.** Every
  fixture moves `HOME` into the sandbox, but an interactive fleet shell also exports
  `ZDOTDIR=~/.config/zsh`, and the driver defaults `ZDOTDIR` only when it is unset. So a
  `make audit` (or `make release`) run from such a shell had the driver and scaffold
  fixtures re-point the real `$ZDOTDIR/.zshrc` into a temp dir, deleted at exit, and the
  next shell started bare. The same inherited mise activation state made sandboxed shells
  error on an untrusted `mise/config.toml`, so the audit went red locally while CI stayed
  green. `test-core.sh` now unsets `ZDOTDIR`, the four `XDG_*_HOME` dirs and every
  `MISE_*`/`__MISE_*` variable before any fragment runs, and `05-suite-shape.sh` asserts
  that none survive. The `test/check-links.sh` that `new-os-repo.sh` scaffolds clears the
  same variables itself.
- **The fan-out count gate no longer reads binary files.** `_core_fanout_count_hits` ran its
  awk over every tracked file, `assets/demo.gif` included, so every `make audit` printed a
  gawk `Invalid multibyte data detected` warning under a UTF-8 locale. It now skips any file
  containing a NUL byte. It does not use `grep -I`, because BusyBox grep accepts that flag
  and ignores it. The verdict never changed (a GIF makes no fan-out claim); the audit's
  output is quieter.
- **`new-os-repo.sh` writes the `LICENSE` its README shield advertises.** The shield row
  added above carries an MIT License badge linking `blob/main/LICENSE`, but nothing wrote
  that file (it is in neither `core.manifest` nor `core.vendor`), so a new repo's first
  push would show `license | not identified` and a link that 404s. The scaffold now writes
  Core's `LICENSE` (the whole fleet's, byte for byte) with the birth year, and the
  generated `.markdownlint.jsonc` names the real reason `MD041` is off: the README opens
  with the back-to-top anchor and shield row, not an H1.

### Documentation

- **`PORTING-MATRIX.md` and the README stop contradicting the fleet**
  ([#1174](https://github.com/dotgibson/dotfiles-core/issues/1174), from the #1157 sweep).
  The sesh row's Arch cell asserted `AUR⁹`, but `dotfiles-Arch` go-installs sesh and says
  the AUR `sesh-bin` is not needed; it is now `go⁹`, and footnote ⁹ names Arch among the
  go-install consumers. Footnote ³³ gave Gentoo's `~arch` neovim range two ways eleven lines
  apart (0.12.5 and 0.12.3); both now read 0.12.5, as the TSV does. Footnote ³⁴ said jq 1.8.2
  reached "all three" supported Alpine stable branches; Alpine carries four, and 3.21 is
  still on 1.7.1. The README's install steps gain the Defense clone and name Debian and
  NixOS among the Linux distros, matching the "all ten bootstraps" line beneath them.

- **Every registered README hero is now filmed** — the tenth, `dotfiles-NixOS`'s, landed as
  [dotfiles-NixOS#8](https://github.com/dotgibson/dotfiles-NixOS/pull/8), so the "still to
  be filmed" prose in `CLAUDE.md`, `assets/hero-repos.txt` and `assets/README.md` is retired.
  It was the one row no rootless chroot could film — its host guard asserts
  `sudo nixos-rebuild switch --upgrade` and `up -n` probes `$PATH` for it — so it was filmed
  on NixOS-WSL, and `assets/README.md` gains "Filming the NixOS hero": the two-rebuild
  install, nixpkgs' own render kit (vhs 0.11.0, not the 0.12.0 that writes no gif), the
  Adwaita Mono rejection the `❖` fallback needs, and the trap that is NixOS-WSL's alone — a
  `nixos-rebuild switch` resets the kernel-global `binfmt_misc` table, which every distro on
  the machine shares, so the distro you drive from loses `wsl.exe` until it is re-registered
  (the recipe is there). The install also surfaced
  [dotfiles-NixOS#6](https://github.com/dotgibson/dotfiles-NixOS/issues/6): `home.nix` named
  two attributes nixpkgs does not have, invisible to that repo's parse-only gate. `§9k`'s
  rule stands: a registered tape with no gif is a skip, so a re-render that has not landed
  never blocks the gate.
- **`PORTING-MATRIX.md` gains an eza fleet-version table (footnote ³⁹), against a 0.23.5
  floor.** 0.23.5 added `--hyperlink=auto` and lines-of-code counting, and an older eza
  rejects the flag outright. The `/tool-scout` scan in
  [#1158](https://github.com/dotgibson/dotfiles-core/issues/1158) held it on a watch that ends
  only when every lane is at or above that version, and until now nothing recorded where the
  lanes sit. `scripts/fleet-package-versions.tsv` now carries seventeen rows, each read from
  the distro's own index. Seven are at or above; Alpine edge/3.24/3.23 and Gentoo stable are
  one patch short on 0.23.4; Ubuntu 24.04 (0.18.2), both Leap backports (0.20.4), Debian 13
  (0.21.0) and Alpine 3.22/3.21 are further back. `gen-porting-matrix.sh` registers the block
  and marks the eza row. Core enforces no eza floor, and `zsh/` passes no flag that needs one.

## [v7.11.0] - 2026-09-18

### Changed

- **`gen-desktop-parity.sh`'s registry is the placement shape `gen-theme.sh` already has**
  ([#1144](https://github.com/dotgibson/dotfiles-core/issues/1144), second of two; closes it).
  The move onto the shared library (#1145) kept its registry as it was: a `repo<TAB>path`
  array with the one block id held apart in a constant — the same facts as a
  placement `BLOCKS` (`id path repo`), permuted, because there was exactly one block. It is
  now that `BLOCKS`: one block, two rows, the same id on both, and the sibling checkout is
  resolved through the library's `region_block_path` rather than a second copy of the
  `resolve_repo_dir` + `-e .git` rule. With that, all four region generators declare exactly
  one registry, named `BLOCKS`, whose first column is the block id — the prefix contract the
  first half of #1144 documented — and the region-library bullet in `CLAUDE.md` stops saying
  the registries are "still four different shapes". Both live copies verify byte-identically;
  what stays this script's is the policy (an absent sibling is exit 3, a present sibling with
  a missing file or region is exit 1), which no registry column carries.

- **The four region generators' registries are one shape — and the measurement says two,
  not one** ([#1144](https://github.com/dotgibson/dotfiles-core/issues/1144), first of two).
  One symptom was left by #1129 deliberately: `gen-theme.sh` and `gen-aliases.sh` each had a
  `BLOCKS` that meant different things, `gen-porting-matrix.sh`'s registry was three parallel
  variables (`BLOCK_IDS`, `LOCAL_BLOCKS`, `FV_TOOLS`), and `gen-desktop-parity.sh` held its one
  block id outside its registry altogether. The issue asked whether the differences were
  accidental or real before anything converged. Column by column they are **two honest
  shapes**: a _placement_ registry (`id path repo`) for blocks that live in many files, some
  in sibling repos — theme has it, desktop-parity has the same facts permuted — and a
  _descriptor_ registry (`id …`) for a single target document whose rows say how to render
  each block — aliases has it, porting-matrix had it split three ways. They do not merge: the
  five-column union would put a constant path on 21 alias rows and two empty columns on 18
  theme rows, documenting nothing. What they share is a **prefix contract**, now documented
  and read by `scripts/lib/gen-region.sh`: one registry per generator, named `BLOCKS`, a TSV
  heredoc, column 1 the block id, the columns declared in the comment above it.

  **What that bought.** `gen-porting-matrix.sh`'s three variables are one
  `id<TAB>scope<TAB>tool` table, so three of its preflight checks — a subset or a tool naming
  an unregistered id, a tool mapped twice — are impossible by construction and are gone; the
  comment warning the suite off matching `LOCAL_BLOCKS` when it grepped `^BLOCK_IDS=` is gone
  with them, because there is one variable. The behavioural suite's four bespoke `awk`
  source parsers (five with `PKG_ROWS`) are one library call, `region_registry_from_script`,
  which lives beside the shape it parses. `gen-theme.sh`'s hand-rolled sibling resolver and
  by-file preflight grouping are the library's `region_resolve_targets` and
  `region_preflight_targets`, which `gen-desktop-parity.sh` takes next. `aliases.md`,
  `PORTING-MATRIX.md` and every themed consumer regenerate byte-identically.

  **One behaviour moved, on purpose.** "Is this sibling checked out?" is now the fleet's one
  rule everywhere — `resolve_repo_dir`, then `-e <dir>/.git` — where `gen-theme.sh` alone had
  tested the bare directory, so a same-named directory that was not a clone read as checked
  out there and as absent in `gen-porting-matrix.sh` and `gen-desktop-parity.sh`. It now
  reads as absent (exit 3, reported) in all three.

- **The last generator is on the shared library, the last off-grammar marker is gone, and
  the pair that lived in two other repos was renamed without a red in between**
  ([#1129](https://github.com/dotgibson/dotfiles-core/issues/1129)).
  `gen-desktop-parity.sh` was the outlier on both counts: its markers carried no `core:`
  prefix and no block id — `grep -Fx` against two hardcoded literals, in a file format that
  could therefore hold exactly one generated region forever — and it kept its own awk
  renderer, its own count checks and its own atomic install. It now calls
  `scripts/lib/gen-region.sh` like the other three, and every live copy carries
  `<!-- core:desktop-parity:gen parity -->`. **There is no second marker regex left in this
  repo.**

  **The interesting part is the sequencing, not the diff.** This generator's only live
  marker pairs are in `dotfiles-Windows/desktop/PARITY.md` and
  `dotfiles-MacBook/sketchybar/PARITY.md`, so Core and those repos could not change a string
  in one commit — whichever side moved first would red the other, and
  `.github/workflows/parity-check.yml` clones both siblings from `main` weekly and runs
  `--check --strict`. So it took three: Core learned the canonical form while still
  _accepting_ the id-less pair
  ([#1143](https://github.com/dotgibson/dotfiles-core/pull/1143)), the two siblings were
  renamed one repo at a time
  ([dotfiles-Windows#272](https://github.com/dotgibson/dotfiles-Windows/pull/272),
  [dotfiles-MacBook#259](https://github.com/dotgibson/dotfiles-MacBook/pull/259)), and the
  legacy arm goes here. The gate was green at every step, including the mixed state where
  one copy was renamed and the other was not — which was checked, not assumed.

  **A copy left behind now reds, and that is a new assertion rather than a side effect.** A
  legacy marker no longer matches the grammar at all, so it is not a marker — it is prose.
  Without a check the walker would pass such a file through untouched, the byte comparison
  would compare it against itself, and `--check` would report green over a copy it no longer
  covers: coverage loss reading as health. `region_preflight_file` turns that into
  `registered block is missing: parity`, and the behavioural suite pins it in the failing
  direction.

  **Severity is translated on purpose, and the code says so.** The library returns 2 — _this
  document is structurally broken_. This generator still exits **1**, because an unmarked
  copy is the drift being gated rather than an absence, and `audit-core.sh` §9i is written
  around exactly that; propagating the library's return code would file a broken marker as
  "the gate could not run". No gate id moved, and §9i, §9d, §9g and §9h contain no marker
  literals at all.

  One user-visible message changed: an `end` before its `gen` is now reported as
  `unterminated 'core:desktop-parity:gen parity' region` rather than the generator's own
  _appears before_. That is the point rather than collateral — since
  [#1141](https://github.com/dotgibson/dotfiles-core/pull/1141) the preflight and the
  walker report the same faults in the same words, and keeping a hand-written ordering grep
  for a nicer sentence would have left exactly one hand-written marker check alive in the
  repo. Two checks the old generator could not express at all came free: a **crossed or
  nested** pair, and a **block id nobody renders** — the second being unrepresentable under a
  grammar with no ids.

  **What #1129 did not do, on purpose.** Its third listed symptom was that the registries are
  per-generator and structurally different, and they still are: two generators call theirs
  `BLOCKS` and mean different columns, one has three parallel registries, and one holds its
  block id outside the registry entirely. Four awk parsers in the suite read those registries'
  _source shape_ — a coupling `gen-porting-matrix.sh` already documents as load-bearing — so a
  rename there is a suite change first. Landing it on top of a three-repo marker rename would
  have made any red impossible to attribute. Measured and deferred in
  [#1144](https://github.com/dotgibson/dotfiles-core/issues/1144), which also asks the prior
  question: whether those four shapes are one thing wearing four names, or four honest small
  ones.

- **The docs learned the second vendored line — Core is on _both_ ends of a vendoring
  contract now**
  ([#1126](https://github.com/dotgibson/dotfiles-core/issues/1126)).
  Step 5 of `NVIM-SPLIT-PROPOSAL.md` §3.5, and the last: it describes what steps 1-4 did
  rather than what they were meant to do. `ARCHITECTURE.md`'s topology section opened with
  _"Core flows in one direction — authored here, copied out"_ and drew a diagram to match;
  `CLAUDE.md`, `README.md` and `ARCHITECTURE.md` each listed `nvim` in the column naming
  what Core **owns**. The diagram now has an arrow pointing _in_, the inbound lock is
  explained where `core.lock` is (`nvim.lock` names its source because, unlike Core's, that
  source is not implicit — `dotfiles-Offense/companion.lock` has carried the same shape for
  the same reason), and the editor is described as reaching a machine in three hops:
  `dotfiles-nvim` → `dotfiles-core` → that repo's `core/`, with `dotfiles-Windows` skipping
  the middle one.

  **`RELEASE-RUNBOOK.md` gained a fifth flow.** `## 5. Cut a dotfiles-nvim release` sits
  beside htpx's — the other repo the fleet vendors _from_ — so the header table, which had
  said four, now says five and carries a row whose "fans out to" column points inward. The
  old §5 and §6 shifted to §6 and §7; the one citation of them in the tree
  (`sync-fanout.yml`) moved with them. §1.1 gained the step it had been missing: the editor
  pin moves **at a Core release and nowhere else** (§7(3)), which `release-readiness`
  already told a reader while the runbook itself did not.

  **Two premises in the issue were wrong, and the prose says what is true instead.** htpx
  was said to "already document the shape" — it does, in exactly one place, so for
  `VENDORING.md`, `ARCHITECTURE.md`, `README.md` and `CLAUDE.md` this _created_ the inward
  prose rather than extending a precedent. And _"the colour rule now spans two repos"_ is
  true for the opposite reason to the obvious one: `nvim/` was never a `gen-theme` target
  and has never carried a `# core:theme:gen` block, because the editor holds zero hex
  literals and asks the plugin. What crossed the boundary is the **assertion** —
  `dotfiles-nvim` vendors `theme/palette.toml` _out_ of Core and runs the tokyonight-pin and
  `M.style` checks that `gen-theme.sh --refresh` can only make with a live Neovim, so they
  now run on every pin bump instead of nowhere at all.

  **The sweep went wider than the six files named**, because the same staleness sat
  elsewhere: `RELEASE-STRATEGY.md` — the _policy_ the runbook answers to — still batched the
  editor pin into the weekly freshness PR and still said `freshness.yml` rolls it forward,
  both of which #1123 and §7(3) had already contradicted; it and `RELEASE-RUNBOOK.md` also
  still sourced `dotfiles-Windows`' `nvim/` mirror from Core, which #1124 changed. Smaller
  corrections in `GITHUB-APP-AUTH.md`, `SECURITY.md`, `CONTRIBUTING.md`, `PORTABILITY.md`,
  the two `tool-scout` files (which pointed the scout at a vendored, gate-protected
  lockfile), the bug-report template (which invited editor bugs into the wrong repo) and
  `V8-PROPOSAL.md`, whose extract-or-freeze deferral is now resolved. In
  `PORTING-MATRIX.md` only footnote prose moved: footnotes ⁵ and ³³ attribute the Neovim
  0.12 floor to the repo that authors the pin. **The floor itself is unchanged**, and the
  generated blocks were not touched.

  `NVIM-SPLIT-PROPOSAL.md` flips **DECIDED → SHIPPED** with this entry, since §3.5
  completes here. All five steps ride the same release, so the file still names no version.

- **Core stopped running the editor's tests — and the gate that had been lodging with
  them moved somewhere it actually runs**
  ([#1125](https://github.com/dotgibson/dotfiles-core/issues/1125)).
  Step 4 of `NVIM-SPLIT-PROPOSAL.md` §3.5. `scripts/test/15-nvim.sh` (802 lines of headless
  Neovim fixtures), `scripts/nvim-reachability.sh` and the nvim half of
  `scripts/test/80-nvim-reachability.sh` were **byte-identical** to the copies
  [`dotfiles-nvim`](https://github.com/dotgibson/dotfiles-nvim) has run since
  [#1122](https://github.com/dotgibson/dotfiles-core/issues/1122) — there against a pinned,
  SHA-verified Neovim with the committed plugin pins installed, which is the one thing Core's
  runners structurally cannot do. Retiring them drops duplicates, not coverage, and that was
  checked by diffing the files rather than by trusting the plan.

  **The second file was two gates wearing one name.** Below the nvim half sat the `#633`
  routine `allowed-tools` ⇄ workflow `--allowedTools` mirror, which has nothing to do with
  the editor and would have been deleted by anyone reading the filename. It survives as
  `scripts/test/24-routine-allowed-tools.sh` — and _24_, not _80_, because `NN >= 60` is the
  zsh band: `scripts/test/60-loader.sh` ends the whole run when `SCOPE_SHELL` is off or zsh
  is missing, so at 80 the mirror never ran under `--scope nvim`, `--scope atuin` or
  `--scope none`. It is python3 and two file reads, so it now sits in the always-run
  pure-bash band, ungated.

  **luacheck stays, for a corrected reason.** §7(2) kept it because _it catches a corrupt
  sync_; since [#1123](https://github.com/dotgibson/dotfiles-core/issues/1123) that is
  §9q's job, which compares `nvim/`'s committed tree against `nvim.lock` byte for byte,
  offline and always-on. §4 is defence in depth over a vendored tree and now says so. §4b
  (the live reachability run) retired with the script it drove; the walk happens in
  `dotfiles-nvim`'s own audit, on the same tree, before the release `nvim.lock` pins — which
  is what `core.manifest`, `CONTRIBUTING.md` and `VENDORING.md` now say instead of citing a
  section that no longer exists. Section ids are stable, so `4b` is retired, never reused.

  `.github/workflows/ci.yml` keeps its Neovim install: the
  [#829](https://github.com/dotgibson/dotfiles-core/issues/829) regression in
  `scripts/test/73-maint-runner.sh` still needs a real editor. That step's comment records
  that its `if:` is keyed on the wrong axis for that consumer — tracked separately rather
  than changed here. One stale citation found while reading around this: §2 of the proposal
  gave Core's luacheck gate the id `§2`, which has been `§4` for as long as it has existed.

- **The marker-region walker is one library, and the generator with the most consumers
  gained the two structural checks it never had**
  ([#1129](https://github.com/dotgibson/dotfiles-core/issues/1129)).
  Four generators — `gen-theme.sh`, `gen-aliases.sh`, `gen-porting-matrix.sh` and
  `gen-desktop-parity.sh` — each re-derived "find the markers, replace what is between
  them, write the file atomically", and each detected a _different subset_ of the ways a
  marker pair can be malformed. `scripts/lib/gen-region.sh` is now that walker, the
  grammar, the structural preflight and the install, once. This release moves
  `gen-theme.sh` onto it; the other three follow.

  **The duplication was the symptom; the gap was the defect.** `gen-theme.sh` renders 16
  blocks across files that are symlinked into `$HOME` on every box, plus two in sibling
  repos — and it was the one generator that could not see a **crossed or nested** marker
  pair, and never checked that every `gen` had exactly one matching `end`.
  `gen A, gen B, end A, end B` has one marker of each kind per id, so its per-block count
  could not notice, and its walker consumed the inner `gen` as stale body — silently
  dropping block B from the file. `gen-aliases.sh` and `gen-porting-matrix.sh` had both
  checks; the script whose output ships to every host had neither. Both now fail with
  exit 2 and name themselves, which is a **behaviour change**: input that used to pass
  quietly is now refused loudly.

  The second fix is structural. `gen-theme.sh`'s preflight counted markers with a
  _second, hand-written regex_ rather than the one its walker used, which is how it came
  to count `gen` markers alone while the walker honoured both kinds. `region_markers`
  derives its answer by running the walker's own matcher, so a marker the walker would
  honour can no longer be one the structural checks overlook.

  **No marker string changed, and none will here.** `core:theme`, `core:aliases` and
  `core:porting-matrix` are already the `core:<ns>:gen <id>` grammar, and `core:theme` in
  particular is a cross-language contract: `dotfiles-Windows` runs its own
  `gen-theme.ps1` over the same markers, with its own palette, registry and Pester suite,
  which Core neither calls nor gates. The one off-grammar namespace is
  `desktop-parity` — no `core:` prefix, no block id — and its only live marker pairs sit
  in two sibling repos, so it is sequenced separately.

  The gate ids are untouched: §9d, §9g, §9h and §9i classify each generator's `--check`
  exit code and contain no marker literals at all. `scripts/test/43-gen-region.sh` tests
  the grammar and the walker once, and each generator's fragment keeps the cases that
  prove it still wires the library up in its own namespace.

- **The next major is policy now: triggered by a non-empty Breaking Backlog, never
  scheduled — and the cost of cutting one lives beside the commands that cut it**
  ([#1118](https://github.com/dotgibson/dotfiles-core/issues/1118)).
  Scoping `v8.0.0` at `v7.10.0` found nothing to scope: no open PRs, nothing **breaking**
  under `[Unreleased]`, and every milestone at `open_issues = 0` — the **Breaking Backlog**
  included. That is the third time. `V8-PROPOSAL.md` was written in exactly this state at `7.3.0` and closed
  _DECIDED — no major comes out of this proposal_; `NON-MUTABLE-HOST-PROPOSAL.md` was then
  named the right next major until R2 measured the `os.capabilities` schema **additive**,
  and shipped as four minors instead. Each time the answer was re-derived from scratch,
  because it was recorded in a closed proposal rather than in policy.

  `RELEASE-STRATEGY.md` now states the rule the repo has been following without saying so:
  a major is cut **when the Breaking Backlog is non-empty and a release is due**, and an
  empty backlog means there is no major to scope — a healthy state, not a gap. The three
  dissolved themes are cited as the record. What settles it every time is the second
  tiebreaker in `RELEASE-RUNBOOK.md` §1.0 — _if nothing a host already uses changes
  meaning, it is at most a MINOR_ — and a candidate that dissolves under it was never major
  content.

  `RELEASE-RUNBOOK.md` gains the other half: the five costs of actually cutting one,
  promoted out of `V8-PROPOSAL.md` §7, which says outright that they _belong to **any**
  major_ and which has been stranded inside a closed record for a release that never
  happened. The `@vN` sweep and why it goes first; the `dotfiles-Windows` hand bump no gate
  catches, where forgetting cost a full major behind for five releases; Core's own in-tree
  `vN` strings behind §8a, §8a-bis and §8a-ter — the entry counts them with a snippet rather
  than a frozen number, because §7's _"roughly thirty"_ is **52 across 13 files** today; the
  `core_lock_expected_tree` ordering rule measured at `v6.0.0`; and the fleet App
  installation list that is not in git, which 403'd at the end of `v7.9.0`.

  Neither file is in `core.manifest` or `core.vendor`, so none of this ships to a host.

- **Two more generators lost their hand-rolled walkers, and `--local` kept the one
  behaviour only it uses**
  ([#1129](https://github.com/dotgibson/dotfiles-core/issues/1129)).
  `gen-aliases.sh` and `gen-porting-matrix.sh` now call `scripts/lib/gen-region.sh` for the
  marker grammar, the block walker and the structural preflight, leaving them the parts
  that are actually theirs: the alias extractor and the matrix's fleet readers. Between
  them that is **180 lines deleted against 68 added**, and `aliases.md` and
  `PORTING-MATRIX.md` both regenerate byte-identically.

  The two were already copies — `gen-aliases.sh`'s walker was labelled _"gen-theme.sh's
  build_file, HTML-comment markers"_ and `gen-porting-matrix.sh`'s _"gen-aliases.sh's,
  HTML-comment markers"_ — so the diagnostics were already identical but for a prefix.
  That is exactly why the library takes the namespace, the program name and the
  registry-hint as parameters: every message these two emit is unchanged to the byte,
  including the remediation that names `BLOCKS` in one and `BLOCK_IDS` in the other, and
  the ~35 exact-string assertions in `scripts/test/41-gen-matrix-parity.sh` needed no edit.

  **The subset render is the one thing that was not shared, and now is.**
  `gen-porting-matrix.sh --local` re-renders only the blocks whose inputs are in-repo and
  passes every other block's on-disk body through verbatim, so the region is a no-op in the
  byte comparison rather than an empty one — the seam that lets `--check` answer on a lone
  clone. It is still the only caller of that arm, which makes it the library feature most
  likely to be quietly broken later, so `scripts/test/43-gen-region.sh` pins both it and
  the direction that matters more: a crossed pair is still refused when **neither** block
  is in the render subset. `--local` narrows what is rendered, never what is checked.

- **`dotgibson/dotfiles-nvim` exists, and one of §7's answers was corrected while shipping
  it** ([#1122](https://github.com/dotgibson/dotfiles-core/issues/1122)).
  Step 1 of `NVIM-SPLIT-PROPOSAL.md` §3.5. The editor is now authored in
  [`dotfiles-nvim`](https://github.com/dotgibson/dotfiles-nvim) with its history preserved:
  the `nvim/` tree object is **identical on both sides**, so step 2's non-negotiable —
  Core's first sync back must be byte-identical
  ([#1123](https://github.com/dotgibson/dotfiles-core/issues/1123)) — is true by
  construction rather than by inspection. That repo's gate does what Core's structurally
  cannot: it installs the committed pins with `:Lazy! restore`, starts the editor, and runs
  `:checkhealth gerrrt`. **Core has not changed yet** — it still authors `nvim/`, nothing is
  vendored, and steps 2–5 are untouched.

  **§7(1) was written against a premise that does not hold.** It says `gen-theme.sh` writes
  a `# core:theme:gen` block into the nvim colours. There is no such block and there never
  was — `scripts/gen-theme.sh:11` and `theme/palette.toml:9` both say why, in the same
  words: _nvim never had the problem; it holds zero hex literals and asks the plugin._ The
  editor was the exception that proved _"colour is generated, not typed"_, not a consumer
  of it.

  The coupling §7(1) was reaching for is real and runs the other way. `gen-theme.sh
  --refresh` resolves the palette **from** the tokyonight revision pinned in
  `nvim/lazy-lock.json`, at the style in `palette.lua`, and refuses unless
  `theme/palette.toml`'s `source_commit` and `style` agree with those two — the only machine
  check tying the palette to the editor, and one that is maintainer-only, needs a live nvim,
  and never runs on the `--check` path. Across the whole fleet it ran **nowhere**. After the
  split the pin moves in one repo while the palette lives in another, so that check now runs
  in the repo where the pin moves: `dotfiles-nvim` vendors `palette.toml` beside a
  `theme/.core-ref` — the shape `dotfiles-Windows` already uses — and asserts both values in
  pure bash on every pin bump, reading an empty parse as its own failure because two empty
  strings compare equal.

  `NVIM-SPLIT-PROPOSAL.md` records the correction in §7(1) and in §2.1, §2.3, §3.2 and §3.4,
  which each repeated the same wrong claim. `scripts/os-repos.txt` gains the
  DELIBERATELY-ABSENT note the proposal's closing paragraph asked for: the arrow points the
  other way, and the name belongs in `fleet-app-scope.sh`'s `EXTRA_REPOS` if the App is ever
  installed there — not in the fleet list.

- **The last off-grammar marker learns its canonical form, and accepts both while the two
  sibling repos catch up**
  ([#1129](https://github.com/dotgibson/dotfiles-core/issues/1129)).
  `desktop-parity` was the one namespace outside the `core:<ns>:gen <id>` grammar — no
  `core:` prefix, no block id, matched with `grep -Fx` against two hardcoded literals, in a
  file format that could therefore hold exactly one block forever.
  `scripts/gen-desktop-parity.sh` now writes `<!-- core:desktop-parity:gen parity -->` and
  **accepts the old pair as well**.

  **The prefix is provenance, not tidiness.** `core:` names the repo whose generator owns
  the region, and these blocks live in `dotfiles-Windows/desktop/PARITY.md` and
  `dotfiles-MacBook/sketchybar/PARITY.md` — files whose only clue that _dotfiles-core_
  rewrites them is the marker itself. By the same rule `dotfiles-Offense`'s own
  `gen-views.sh` is correctly `companion:` and always was.

  **Both forms, because the targets are in other repos.** Core and the two siblings cannot
  change a string in one commit: whichever side moved first would red the other, and
  `.github/workflows/parity-check.yml` clones both siblings from `main` weekly and runs
  `--check --strict`. So Core learns the new form first, the siblings are renamed next, and
  the legacy arm goes once no live copy carries it.

  The asymmetry is the mechanism: the legacy pair is **accepted on read and never emitted
  on write**. A render echoes whichever marker the target file carries, verbatim, so a
  sibling still on the old pair stays green and nothing rewrites a marker in another repo's
  file — which would be a cross-repo edit disguised as a render. A **mixed** pair is
  refused, though, because it renders perfectly and is therefore invisible to every other
  check: one marker claiming an id while the other does not is a file disagreeing with
  itself, and a count of one `gen` and one `end` is valid in every combination.

  Severity is unchanged: a malformed marker here is exit **1**, not 2, because _an unmarked
  copy is the drift being gated, not an absence_ — the contract §9i classifies on.

- **The nvim split is decided: A2 — extract into `dotfiles-nvim`, Core keeps vendoring it**
  ([#1120](https://github.com/dotgibson/dotfiles-core/issues/1120)).
  `NVIM-SPLIT-PROPOSAL.md` had sat at `DECISION PENDING` since 2026-09-14, after three
  earlier deferrals (v4, `V5-PROPOSAL.md` §11, `V8-PROPOSAL.md` §10), and its own gate said
  the author picks A2 or B _on the file_. Nothing downstream could be filed until that
  happened — the milestone's issue queue did not exist yet, by design. A2 is picked, and
  **none of the three conditions §5 named as recommendation-flipping fired**: the editor has
  not settled, the drift check needs no second integrity model, and §7(1) resolves cleanly.

  The four open questions are answered rather than left to the migration, because they were
  the conditions on the recommendation. The theme answer is the one that mattered:
  `dotfiles-nvim` **vendors `theme/palette.toml`**, so _"colour is generated, not typed"_
  stays true on both sides of the vendor boundary. (The mechanism was **corrected while
  step 1 shipped** — see the entry above: the generated block this originally described
  does not exist, and what the nvim repo carries is the assertion `--refresh` makes, not a
  generator run.) luacheck stays in Core over the vendored copy as an integrity check;
  Core bumps `nvim.lock` **with the next Core release**, never on every nvim release, or the
  churn returns through the lock.

  Deciding is not shipping: nothing has moved, §3.5 is now the runbook, and the file flips
  to SHIPPED when it has. A2 is a **minor** — `core/nvim` keeps its path, `core.manifest`
  keeps its entry and `blib_link_core` is untouched (§3.4), which per `RELEASE-STRATEGY.md`
  is the whole test. One consequence recorded up front: `dotfiles-nvim` is a repo Core
  vendors _from_, not one Core fans out _to_, so it does not belong in
  `scripts/os-repos.txt`.

- **`dotfiles-Windows` vendors the editor from `dotfiles-nvim` directly, and the fleet-drift
  row that judged it became a two-lock compare** ([#1124](https://github.com/dotgibson/dotfiles-core/issues/1124),
  [dotfiles-Windows#271](https://github.com/dotgibson/dotfiles-Windows/pull/271)).
  `NVIM-SPLIT-PROPOSAL.md` §3.5 step 3. Windows vendors no `core/`, but it always consumed
  the editor alone through a bespoke mirror pinned to a Core ref that had nothing to do with
  when the editor changed — §3.1 called that the tell. It now pins `dotgibson/dotfiles-nvim`
  releases in a root-level `nvim.lock` wearing _this_ repo's field names, so the two are peers
  on one release line rather than a mirror and its source. That sync moved **no editor bytes**:
  the same byte-identical guarantee step 2 met, now observed on the second consumer.

  **The Core-side change was forced, not cosmetic.** `fleet-drift.sh`'s Windows row ran
  `_classify_subtree`, which asked — inside _Core's_ object store — whether the recorded sha
  contained Core's latest `nvim/` change. A `dotfiles-nvim` sha is not in Core's history at
  all, so the moment Windows re-pinned, that check would have fallen through to `_classify`
  and reported `DIFFERS (sha not in local history)` on a perfectly healthy repo: red forever,
  with remediation advice that could not help. The ancestry question also stopped being the
  right one — both sides now pin the same upstream, so `_classify_nvim_pin` compares the two
  recorded releases instead. Offline: no `dotfiles-nvim` objects, no network, no clone.

  **Ahead is a note, not drift**, for the reason [#371](https://github.com/dotgibson/dotfiles-core/issues/371)
  established on the Unix side. Windows' bot syncs weekly; Core adopts an editor release only
  with a Core release (§7(3)). Windows carrying a _newer_ editor than `nvim.lock` is therefore
  the ordinary between-releases state, and reddening it would make the dashboard cry wolf most
  weeks. `BEHIND` is the signal that the weekly bot stopped. Ordering is a three-field numeric
  compare — `v1.9.0` sorts after `v1.10.0` lexically, and a string compare would call a
  genuinely newer editor stale, then advise a re-sync that changes nothing.

  `_classify_subtree` is **deleted**: Windows was its only caller, and its whole rationale
  (_"a release that changed no `nvim/` files"_) evaporated once the two sides stopped being
  measured against each other's history. Seven new legs in `scripts/test/31-fleet-drift.sh`
  cover the replacement, added deliberately **after** the `--strict` legs, which assert on the
  row rather than the exit code precisely because the fixture root had no `dotfiles-Windows`
  clone. (`scripts/fleet-drift.sh`, `scripts/test/31-fleet-drift.sh`,
  `.github/workflows/fleet-drift.yml`, `.github/workflows/freshness-dashboard.yml`,
  `RELEASE-RUNBOOK.md`, `.claude/commands/drift-triage.md`, `NVIM-SPLIT-PROPOSAL.md`)

- **Core vendors the editor instead of authoring it: `nvim/` is now a pinned copy of
  `dotfiles-nvim`, behind `nvim.lock`**
  ([#1123](https://github.com/dotgibson/dotfiles-core/issues/1123)).
  Step 2 of `NVIM-SPLIT-PROPOSAL.md` §3.5, and the one that actually moves the boundary.
  `nvim.lock` records which `dotgibson/dotfiles-nvim` revision this Core carries;
  `scripts/sync-nvim.sh` refreshes the pair. The direction is the whole point: `core.lock`
  is written **by** this repo **into** each OS repo, this one is written **into** this repo
  by a source it does not control — `dotfiles-Offense`'s `companion.lock` is the same shape
  for the same reason, which is why it carries `nvim_repo` and `nvim_branch` that
  `core.lock` has no need of.

  **The first sync moved nothing, and that was the requirement.** Core's `nvim/` tree object
  and `dotfiles-nvim`'s were already the same `60fe8d8`, so `git diff --stat -- nvim/`
  across the first `sync-nvim.sh` is empty — which is what keeps the fleet's next `core.lock`
  bump free of editor content, so the extraction reaches every host invisibly. Nothing an OS
  repo consumes changed: `core/nvim` keeps its path, `core.manifest` keeps its single
  directory entry, `blib_link_core` is untouched.

  The transport is `git read-tree --prefix=nvim/`, not `git subtree` and not a copy loop.
  `dotfiles-nvim`'s history was rewritten by `filter-repo` at extraction, so it shares no
  commit with this repo and there is no subtree to pull; staging the upstream tree _object_
  is also the only transport that cannot perturb bytes or modes, without which the
  byte-identical assertion would not mean anything.

  **The drift gate is §9q**, and it needs no network, no tool and no object store: the lock
  records `nvim_tree` — the tree hash itself — so the check is `git rev-parse HEAD:nvim`
  against one line of a file. `core-integrity.sh` answers the same question for an OS repo's
  `core/` by resolving the pinned commit, which it can because that repo fetched it; Core
  holds no `dotfiles-nvim` objects, and a gate that self-skips offline would be
  green-because-absent in exactly the clone where a corrupt sync landed. So it is the same
  tree-hash integrity model §5 asked for rather than a second one — made always-on. luacheck
  **stays** over the vendored copy (§7(2)): it is the cheapest leg in the gate, and a corrupt
  sync is a failure a vendored tree has and a source tree cannot.

  **The freshness job traded a leg for a nudge.** Rolling the editor's plugin pins moved to
  `dotfiles-nvim`, which has a real Neovim to test a bump against; `scripts/update-nvim-plugins.sh`
  and its `nvim-plugins` job are gone from here. In their place `scripts/check-nvim-freshness.sh`
  reports how many editor _releases_ `nvim.lock` is behind — releases, because that is the unit
  §7(3) decided in: Core adopts the editor **with a Core release**, never on every nvim release,
  and without something measuring the lag _"at Core's pace"_ decays into _"never"_. It opens no
  PR by design. Two things fall out: the freshness dashboard no longer installs a Neovim it
  had stopped needing, and `freshness-triage` may now run the check itself — the old script was
  denied a token-bearing job because `:Lazy! sync` executes upstream build hooks, and the new
  one only `git ls-remote`s.

### Removed

- **Two capability keys the schema accepted and nothing ever read**
  ([#1128](https://github.com/dotgibson/dotfiles-core/issues/1128)).
  `PKG_PENDING_EXIT_NONE` and `PKG_PENDING_EXIT_SOME` arrived with R2's non-mutable-host
  prototype keys (`NON-MUTABLE-HOST-PROPOSAL.md` §4.1) to describe a count verb whose
  answer is its exit status — `rpm-ostree upgrade --check --unchanged-exit-77`. They were
  declared optional, validated properly (numeric, 1-255, no leading zero, never both, only
  beside `PKG_COUNT_PENDING`), and **the consumer that would have read them was never
  written**. `PKG_APPLY_PENDING_EXIT` covers the staged question that did ship, and it is
  the key `zsh/02-capabilities.zsh` and the maint runner actually read.

  **Why a schema removal is a minor here and would not be in general.**
  `scripts/check-capabilities.sh` is vendored, seven OS repos run it from their own
  `core/`, and an unknown key is a hard failure — so dropping a name is normally the
  reverse-ratchet shape [#1104](https://github.com/dotgibson/dotfiles-core/issues/1104)
  documents, where Core breaks a repo that was doing nothing wrong. It is safe in this one
  case for one measured reason: **nothing declares them.** Re-verified before merging
  rather than taken from the issue — all twelve `os/*.capabilities` across the fleet, in
  both the working trees and `origin/main`, plus the three R2 prototypes under
  `scripts/research/nonmutable/`. Zero hits, so no repo's declaration changes validity and
  all twelve still validate unchanged.

  **The retirement is pinned, not merely absent.** `scripts/test/55-capabilities.sh` loses
  eight assertions that existed only for these keys and gains one asserting the name now
  lands on the unknown-key arm — because "we deleted it" and "it cannot come back without
  its consumer" are different claims, and only the second is worth a test. The `#1057`
  leading-zero rationale moved rather than died: it was written once and cited from both
  copies of the check, and `PKG_APPLY_PENDING_EXIT` is the only copy now.

  Prose was corrected where it describes the tree as it **is** — the validator's own
  header, `examples/os.capabilities.example`, `scripts/research/README.md` — and left
  where it records what R2 and R5 **measured**, which is still true as written. The §4.1
  table keeps the row, marked retired, because six later passages in that document cite
  the key by name and a table that never introduces it would leave them dangling.

### Fixed

- **The reusable showcase-dispatch header promised a tolerance it had already
  withdrawn** ([#1127](https://github.com/dotgibson/dotfiles-core/issues/1127)).
  `.github/workflows/notify-web-call.yml`'s AUTH paragraph told readers that
  `WEBHOOK_SECRET` _"survives as a deprecated no-op purely so callers still passing it keep
  working"_. There is no such input. `v7.0.0` removed the declaration — the one removal that
  was genuinely waiting on a MAJOR, recorded as discharged in `GITHUB-APP-AUTH.md` and in
  `scripts/sync-core.sh:390`.

  **Stale would have been the benign version; this was inverted.** Removing an accepted
  `workflow_call` secret is a breaking change to a published contract precisely because a
  caller that keeps passing it _fails workflow validation before its own code runs_ — the
  reason the removal was held for v7 in the first place. A maintainer opening the reusable
  to decide whether their caller was safe to leave alone read the opposite of the truth, and
  this file is the contract the fleet's callers consume at `@v7`. The header now names the
  removal and its consequence, and points at the section that owns the reasoning.

  `.github/workflows/notify-web.yml` carries the same paragraph but stops at the PAT's
  deletion and claims nothing about a surviving input — it is not a reusable and never
  declared one. Checked rather than assumed; unchanged. The declaration was the only wrong
  site: the `FLEET_APP_PRIVATE_KEY` description twelve lines below it already called itself
  _the SOLE active dispatch credential_.

- **The `#829` regression ran on vendored-editor bumps and was skipped on the diffs that
  can break it** ([#1136](https://github.com/dotgibson/dotfiles-core/issues/1136)).
  `.github/workflows/ci.yml` installs Neovim only when the `nvim` axis is true. Until
  [#1125](https://github.com/dotgibson/dotfiles-core/issues/1125) that was right — the
  binary's main consumer was `scripts/test/15-nvim.sh`, which genuinely was about `nvim/`.
  With that retired upstream the sole remaining consumer is
  `scripts/test/73-maint-runner.sh`'s
  [#829](https://github.com/dotgibson/dotfiles-core/issues/829) regression, whose subject is
  `maint/dotfiles-maint.sh` — and `ci-classify.sh` maps `maint/*` to `shell`. So editing the
  test installed the editor; editing the code it guards did not.

  It could not go red, either: the fragment skips on `have nvim` alone, and the behavioral
  suite reaches the audit as _one_ backgrounded pass/fail (`scripts/audit-core.sh:270`), so
  its skips never reach `--strict`'s tool-skip counter.

  The Linux install now fires on `nvim OR shell`, which is seconds of pinned tarball. **macOS
  stays on the nvim axis**, deliberately asymmetric: `brew install neovim` is minutes, and
  paying it on every macOS shell leg would buy a second run of an OS-agnostic test. The
  narrower trigger still earns its keep — that fragment is written to the bash 3.2 floor on
  purpose, and macOS is the only leg that executes it on 2007's bash.

  Teaching `ci-classify.sh` to set `nvim=true` for `maint/*` was rejected: that axis means
  _"the editor tree changed"_ and also drives audit `§4` and every `SCOPE_NVIM` section, so
  overloading it to mean _"install a tool"_ would make it lie — and
  `scripts/test/22-ci-classify.sh` pins its behaviour with fixtures.

- **`V8-PROPOSAL.md` §7 said where its cost list went, instead of quietly disagreeing with it**
  ([#1130](https://github.com/dotgibson/dotfiles-core/issues/1130)).
  Promoting the MAJOR cost list into `RELEASE-RUNBOOK.md` §1.1 left §7 a frozen duplicate of a
  living checklist — the worse failure mode, because a reader who finds §7 first gets numbers
  that were already wrong. It had drifted twice over: _"roughly thirty"_ in-tree `v7` strings
  were **52 across 13 files** by `v7.10.0`, and it predates the fleet App installation cost
  altogether. §7's status note now points at the runbook and names its own drift, rather than
  promising a sync a closed record cannot keep — the lesson `GITHUB-APP-MIGRATION.md` already
  draws about frozen files that track live state.

- **The App-installation register named the wrong failure for a missing self-PR install**
  ([#1116](https://github.com/dotgibson/dotfiles-core/issues/1116)).
  `scripts/fleet-app-scope.sh` printed one sentence over every fatal `MISSING` row —
  _"is a push target and the App cannot reach it — this is the v7.9.0 403"_ — and
  `fleet-app-scope.yml`'s job summary and the issue it files said the same. That is true of
  the fan-out targets and false of the three installs that exist for a repo's _own_
  self-PRs. It went wrong the first time it mattered. PR #1111 added `dotfiles-Windows` to
  the expected set on the strength of an install that, it turns out, had never existed, and
  the register then told its reader that a release was about to 403 on a repo the fan-out
  has never pushed to.

  The row now classifies against the fan-out list before it composes. A fan-out target
  keeps the 403, said precisely: it lands on the _push_, at the end of a release. A self-PR
  install reports its own failure instead — the mint _inside_ that repo answers `404` on
  `/repos/<owner>/<repo>/installation`, its bots fall back to `GITHUB_TOKEN`, and their PRs
  go back to sitting `BLOCKED`, **while every one of those jobs stays green**. That is the
  shape issue #1110 predicted, and the shape that had been running unwatched since
  `dotgibson/dotfiles-Windows#268`. The non-fatal `!` arm carries the class too, and
  `scripts/test/90-policy-gates.sh` holds the derivation — matched on the `CORE_OS_REPOS[*]`
  membership test, not on the English — so the two kinds cannot be collapsed back into one
  sentence by a later edit.

  `GITHUB-APP-AUTH.md` takes the general lesson under _A new fleet repo is TWO
  registrations_: it is a rule about this whole install list, not only about fan-out
  targets, and **the org half goes first**. Either order leaves the register red for a
  while; only one of them leaves real machinery quietly broken while it is.

## [v7.10.0] - 2026-09-17

### Added

- **The autostart premise now measures a wedged daemon — the one shape that made the guard's
  old `autostart` stand-down wrong rather than merely unhelpful**
  ([#1091](https://github.com/dotgibson/dotfiles-core/issues/1091)).
  `scripts/research/verify-atuin-guard.sh --premise autostart` measured four arms,
  `{absent, stale} × {hook, plain}`: a socket that is gone, and a socket file whose listener
  exited. Neither is a daemon whose PID is _alive_ and which has simply stopped serving — and
  atuin decides whether to autostart from the **pidfile alone**, so in that shape the one
  process that cannot serve is also the one blocking its own replacement, indefinitely
  (upstream `atuinsh/atuin#4114`, open against 18.22.0).

  That matters because `zsh/00-tools.zsh` unhooks `_core_atuin_daemon_guard` entirely under
  `ATUIN_DAEMON__AUTOSTART`, on the strength of atuin supervising its own daemon — and on
  Alpine and macOS that stand-down is the only mitigation there is. A `wedged × {hook, plain}`
  pair now measures it, built by starting a real daemon and unlinking its socket out from
  under it. Six arms, and the report, the JSON and the derived coverage sentence all follow
  from the arm list rather than restating it.

  Three things the shape forced, each of which was a real defect while it was missing.
  `prove_unreachable` reads `/proc/net/unix` for a LISTEN row on the path, and a wedged daemon
  **still has one** — the kernel keeps the bound name after the directory entry is gone — so
  the arm proves unreachability from the vanished name plus a refused connect instead. The
  wedged pair is also the only point in a run where two daemons are alive at once, which the
  single-daemon teardown machinery cannot tell apart; the wedged one is therefore reaped by
  pid **before** the socket-scoped stop runs, and reversing those two left a real autostart
  daemon committing into the closing drain control, turning a clean `holds` into a `moved`
  about rows nothing upstream wrote. And a daemon that _exits_ with its socket cannot exhibit
  the shape at all, so that is `unmeasurable` with its own sentence rather than a quiet pass.

  Covered by three cases in `scripts/test/52-atuin-autostart.sh` on two new stub modes: one
  that heals absent and stale and fails only wedged (so no four-arm run could have caught it),
  one that dies on unlink, and an assertion that the finding names the pidfile mechanism
  rather than an absent socket — the two have different remedies, and unlinking a stale socket
  or counting failed spawns reaches the wedged shape exactly zero times.

  **It is not free, and the number is stated rather than absorbed.** Each wedged arm starts a
  real daemon, waits a fixed second to confirm it survived losing its socket, and runs a full
  stop-and-prove teardown; the self-test drives that through more than a dozen stub builds.
  Measured on a loaded dev box, the `atuin` scope went from **309s to 672s**, so
  `atuin-guard-verify.yml`'s self-test job moves from a 15-minute ceiling to 25 — 15 was no
  longer clear of the slowest observed run, it was inside it. `ci.yml` is unaffected in the
  common case: it has run this scope only when the detector, `zsh/00-tools.zsh` or `atuin/`
  actually change since #699.

- **The fan-out proves the App installation covers its targets, and a register asks the same
  question between releases** ([#1071](https://github.com/dotgibson/dotfiles-core/issues/1071)).
  The fan-out's write scope is the GitHub App's _installation_, deliberately — hardcoding a
  repository list on the mint would be a second copy of `scripts/os-repos.txt` that could
  drift. But that installation is `repository_selection=selected` and nothing compared the two
  lists, so registering a repo in `os-repos.txt` left half the registration undone with no gate
  to say so.
- **The bash 3.2 floor gate learns the half that never runs at all.** §5k has covered the
  features 3.2 does not _have_ since #874 — they parse, then fail at run time. #1075 found
  the other half: syntax 3.2's parser _refuses_, where `bash -n` rejects the file and
  nothing in it executes. `scripts/lib/common.sh :: _core_bash32_parse_hits` is the new
  scanner, called from §5k beside `_core_bash4_hits` over the same files, and kept a
  separate helper because the older one's contract explicitly promises "a builtin or a
  syntax bash 3.2 does not have", which this is not.

  **The entry is a `case` opening a command substitution with bare patterns**, and it is a
  trap rather than a hazard. Measured against a bash 3.2.0 built for the purpose, not
  inferred from the CI red — all four parse on bash 5:

  ```text
  x=$(case $v in a) echo A;; esac)             3.2: syntax error near `;;', ALWAYS
  x="$(case $v in a) echo A;; esac)"           3.2: fine — until an arm contains a '
  x="$(case $v in a) echo "it's";; esac)"      3.2: unexpected EOF looking for matching '
  x="$(case $v in (a) echo "it's";; esac)"     3.2: FINE — the leading ( is the fix
  ```

  So the double quotes are what make it _work_, and the construct can sit in the tree
  parsing perfectly until somebody edits English prose in a case arm. That is how it
  arrived: a research script's verdict string came to read _the snapshot's copy won_, went
  green on bash 5 through `bash -n`, ShellCheck and three Linux legs, and reddened only on
  `macos-latest`, eleven minutes in. The needle is therefore the bare pattern and not the
  apostrophe — a leading `(` on every pattern fixes both shapes, so the rule has one fix
  and no judgement call. `while`, `if` and `until` bodies inside a substitution are
  unaffected, and so are backticks; it is `case` alone.

  Green on arrival over all 121 tracked shell files, which is the property #748's ledger
  asks of a new gate. Seven arms in the scanner suite pin it, and the two fixtures the
  scanner flags are exactly the two a real 3.2 refuses while the three it passes are
  exactly the three a real 3.2 accepts. Both documented gaps are named in the helper: a
  `case` appearing later inside a multi-command substitution, and a substitution whose
  subject holds parentheses — the latter excluded deliberately, because without that clamp
  a prose arm reading `echo "built in place"` supplies a second ` in ` and the rule fires
  on correct code.
- **A harness for R1's last three unmeasured cells** (`NON-MUTABLE-HOST-PROPOSAL.md` §5,
  #1052). `scripts/research/nonmutable-r1-cells.sh`, behind a new `r1cells` input on
  `research-nonmutable-vm.yml`. Two of the three are claims a **shipped** declaration
  already makes, which no run has asked a host to confirm.

  **`dnf search` on a booted bootc host** — `dotfiles-Fedora/os/fedora.atomic.capabilities`
  declares `PKG_SEARCH=dnf search`; R1 probed only `dnf install` there (a refusal that
  arrives after resolving 317 packages) and only `dnf -q provides` in a container. It is
  asked **before** the leg's bootstrap passes, because R6 measured that a provision run
  writes a COPR repo file and breaks every later `dnf`, and **as the user**, because the
  key is declared with no escalator. `makecache` goes first: against a cold cache every
  query is a false miss, which is a fact about the harness, not the target.

  **`chsh` across a NixOS switch** — the cell was open because a `build-vm` guest carries
  no `/etc/nixos/configuration.nix`. So the workflow builds a **second generation** on the
  runner and the guest activates it over the shared `/nix/store` — no evaluation, no
  network, no store write of its own. It is built as `-A vm` and its system closure read
  back out of the runner script, not as `-A system`: that attribute builds a real machine
  and asserts a root filesystem and a bootloader this configuration never declares, because
  the vm variant supplies both implicitly — and hand-declaring them would leave gen2's
  fstab disagreeing with the machine actually running, which `switch-to-configuration` acts
  on. The whole gen2 step is best-effort with the probe outside it, after the first dispatch
  showed the failure mode that matters: an _optional_ fidelity upgrade running under
  `set -e` took the _required_ measurement down with it. Without a store path the script
  replays the current generation's activation and says so in the report. The action is
  `test`, not `switch`: `switch` also
  installs a boot loader, which a guest booted from QEMU's `-kernel` has none of, and the
  activation half is where `users-groups` runs. The full verb runs afterwards anyway, so
  the run records _why_ it fails rather than the bare exit status. Both a declared user
  (root) and an imperative one (`useradd`, which `users.mutableUsers` permits) are chsh'd,
  because reverting only the declared one would be a narrower boundary than
  `dotfiles-NixOS/bootstrap.sh` claims.

  **An `/etc` edit across `transactional-update dup`** — the loss case transactional-update(8)
  documents (a file changed both during the update and afterwards in the running system)
  cannot be waited for, so it is forced: the snapshot is opened **first** with `run`, both
  halves are written, and the `dup` closes it with `--continue`. Opening first is what
  makes a no-op `dup` harmless — there is already a dirty snapshot to close. Four markers
  separate carried from shadowed from absent, and the payload rides beside them: the two
  writes `blib_set_login_shell` makes. Phase 2 fills in its own table and leads with the
  guard that matters — **the booted subvolume did not change, so this round measured
  nothing** — because a failed transaction deletes its own snapshot and every row would
  otherwise read as "carried".
- **`sync-fanout` checks that the fleet App installation covers every target before it
  clones anything** (#1071). The fan-out's write scope is the GitHub App's _installation_,
  deliberately — hardcoding a repository list on the mint would be a second copy of
  `scripts/os-repos.txt` that could drift. But that installation is
  `repository_selection=selected` and nothing compared the two lists, so registering a repo
  in `os-repos.txt` left half the registration undone with no gate to say so.

  It shipped exactly once. `dotfiles-NixOS` joined the fleet in #1064; the v7.9.0 fan-out
  cloned, audited and synced all ten repos and then failed on the tenth push —
  `Permission to dotgibson/dotfiles-NixOS.git denied to dotgibson-fleet-sync[bot]` — after
  every expensive step had already run (#1070).

  A pre-flight in `sync-fanout.yml` now reads the installation with the token it has just
  minted and fails **before the first clone**, naming the repo and the Organization-Owner fix.
  A `check_only: true` dispatch runs the pre-flights and stops, so the scope can be checked
  _before_ a release instead of discovered at the end of one.

  **The comparison itself lives in `scripts/fleet-app-scope.sh`**, the App-installation
  register, rather than inline in the workflow: the same question is worth asking on a
  schedule, and a second spelling of it is how a gate ends up covering a different list than
  the thing it gates. The register derives the expected set the way every fleet gate derives
  the fleet (`os-repos.txt` through `load_os_repos`, plus the two exceptions
  `GITHUB-APP-AUTH.md` names — no second copy of the list) and reports **both** directions: a
  push target the App cannot reach, and a repo installed that nothing writes to.

  **The two halves of the question are readable from opposite environments**, which shapes the
  whole change. The _grant_ half (installation present, un-suspended, holding exactly the
  documented verbs) needs an org-admin token, so it runs on a maintainer box via
  `make fleet-app-scope`. The _reach_ half (which repos does it cover?) needs an installation
  token no local environment can mint, so it runs in CI — which a **scheduled** job can do,
  and `.github/workflows/fleet-app-scope.yml` now does every Monday, red plus a deduplicated
  issue. Each half reports its own coverage, an unread half is never a pass, and a real finding
  outranks one, so the bare reporter stays green locally while `--check` exits 3 there.

  The fan-out's pre-flight _warns_ rather than blocking when it cannot read: a blind check must
  not deny every repo its PR, which is the failure the fan-out loop already exists to avoid.
  Its mint now names `permission-metadata: read`, the verb that read spends. Not a fix for a
  live defect — a narrowed mint turns out to keep the mandatory grant, verified against the
  live API — but a mint that does not say what it spends is one nobody can audit.
- **`PKG_UNLISTED_TOOLS` — a declaration says which verb binaries its package list
  deliberately does not name** ([#1087](https://github.com/dotgibson/dotfiles-core/issues/1087)).
  A new optional capability key, read only by `check-capabilities.sh --packages`.

  That cross-check warns when a `PKG_*` verb's leading binary is absent from the repo's
  `install/packages.txt`, to catch a verb naming a tool nothing installs — `paru`, `nala`.
  Measured across all twelve fleet declarations on 2026-09-16, it fired on **essentially
  every verb the fleet declares**: Debian 10 warnings, openSUSE and Fedora and Alpine and
  Gentoo 8 each, Arch 7, and `capabilities` is a prerequisite of `lint` in each repo's
  Makefile — so eight repos printed that wall on every run. The signal it was built for was
  buried in it, and a gate that is ~100% false-positive teaches people to skim past it.

  The cause is that **three unrelated things** make a binary absent from a package list,
  and only the repo knows which applies: the base system ships it (`apt-get`, `dnf`,
  `zypper`, `rpm`, `systemctl`), a package the repo _does_ list provides it under another
  name (`checkupdates` from `pacman-contrib`, `equery` from `gentoolkit`), or the repo
  ships it itself (`gentoo-pkg-pending`, symlinked onto PATH by its own bootstrap). Core
  cannot tell them apart, and a hardcoded table of package-manager binaries here would be
  exactly the per-manager knowledge #763 deleted from Core — so the declaration says so.

  Measured with the key declared, all ten noisy declarations go to **zero**. The first
  attempt at the narrower fix is recorded because it is the tempting one: skipping only
  `PKG_INSTALL`'s own binary zeroes six declarations and cuts Debian 10 → 2, but leaves
  `fedora.atomic` at 3 and `opensuse.microos` at 5 — the staged hosts run four base
  binaries across their verbs, not one manager, so "the package manager" was never the
  right category.

  **Kept honest from both ends**, so an exemption list cannot rot into a blanket silencer:
  a name no declared verb runs is a **failure** (a stale entry silences a future verb
  nobody vetted), and a name the repo's own `packages.txt` installs is a **failure** (the
  exemption is simply false). Entries match as whole tokens, so `rpm` does not cover
  `rpm-ostree`. The contradiction is reported once per tool rather than once per verb —
  `dnf` leads six of Fedora's verbs, and the first draft printed the same line six times,
  which is the noise this key exists to remove.

  **Additive**: omitting the key is exactly the old behaviour, verified against all twelve
  declarations, so nothing in the fleet changes until a repo opts in. The sibling repos
  adopt it one PR each; this is the half that lets them.

- **Footnotes ⁵ and ³³ enumerate from the TSV instead of from prose, and the mechanism that
  already did it for jq stopped being jq-only**
  ([#1082](https://github.com/dotgibson/dotfiles-core/issues/1082)). Footnote ³³'s neovim
  table was hand-written and was **wrong four times in four months** — dotfiles-Gentoo#116
  (the stable ebuild was 0.11.7 while the footnote read the tree as current),
  dotfiles-Alpine#170 (three of five supported branches below the floor, quoted as one fleet
  answer for a release cycle), dotfiles-openSUSE#178 (an exemption that stopped being true the
  day Leap 16.0 shipped) and dotfiles-Fedora#192. Footnote ⁵ had the same problem in
  per-platform prose rather than a table. `scripts/fleet-package-versions.tsv` was built for
  exactly this and held **one tool**, because `render_fleet_versions()` hard-coded
  `local tool="jq"`.

  It now takes `<tool> <block-id>`, and a third registry beside `BLOCK_IDS`/`LOCAL_BLOCKS` —
  `FV_TOOLS`, id→tool — says which block renders which. **Declared, not derived from the id**,
  for the same reason `LOCAL_BLOCKS` is declared: `fleet-versions` is jq's and says so nowhere
  in its name, and deriving would forbid any tool whose name is not a legal marker id. Two
  couplings went with it: `render_block` replaces the per-id `case` in `render_for` **and** the
  one on the `--local` path, so a block registered with nothing behind it is now a loud 2 on
  every path rather than on one; and the fleet-version tables render lazily, which is what
  lets the registry carry N tools without N shell variables bash 3.2 cannot key by id.

  **The landing commit moves no generated byte for jq.** `fleet-versions` keeps its id, so
  `PORTING-MATRIX.md`'s existing block is untouched and the `--check` diff stays readable.

  `preflight` gained the check that closes the defect CLASS rather than its instance: the
  `FV_TOOLS` tools and the TSV's `floor` lines must be the same set, **both directions**. With
  one tool, "a tool in the TSV that no block renders" was impossible. With N it is the same
  failure in a new costume — rows recorded, nothing rendering them, and the footnote they were
  recorded for back to prose nothing can contradict. Nothing else in the repo would have said
  so.

  **Every row was re-read from the distro's own index on 2026-09-17**, not transcribed from the
  footnotes — stamping a `verified` date on a number nobody re-derived is the failure this file
  exists to end. Alpine's five branches from `APKINDEX`, Fedora 43/44 from `mdapi` and 45/rawhide
  from `dl.fedoraproject.org`, Arch and Homebrew from their JSON APIs, openSUSE's three lanes
  from `download.opensuse.org`'s `primary.xml`, Gentoo's keywords from `packages.gentoo.org`,
  Debian from `sources.debian.org` and Ubuntu from Launchpad. That immediately found a fifth
  correction: footnote ⁵ said Gentoo's `tree-sitter-cli` stable was **0.26.11** with 0.26.12
  `~`-keyworded on every arch; **0.26.12 is stable** on amd64, arm, arm64, ppc, ppc64 and x86.

  Two rules the rows now follow, both load-bearing and both written into the TSV header.
  `<version>` is the **upstream triple**, never the distro build string: the floor comparison
  truncates either way, but `update-fleet-versions.sh` compares the recorded string to the
  probe's answer, so `0.12.2-r0` would read as drift on the first bot run and be rewritten.
  And `<probe>` is `-` **whenever the probe would answer a different question** — the Gentoo
  rows record the newest STABLE-keyworded ebuild while Repology reports the newest ebuild
  regardless of keyword, and openSUSE ships the tree-sitter CLI in a package called
  `tree-sitter`, a different project. A wrong `<probe>` there produces a green audit and a bot
  PR that quietly deletes the finding, and no gate catches it; it is a review item, and the
  header now says so.

  What stays hand-written is the argument, which is ³⁴'s contract unchanged. ³³ keeps its
  four-mechanism account and loses only the table; the `Gentoo, fixed` row does not migrate
  because a counterfactual about a `>=` keyword line is not an observation of any target, and
  Debian's `no — see ²⁸` does not because a derived verdict cell cannot hold a cross-reference.
  ⁵ keeps all five platform traps — the Mac `tree-sitter-cli`-not-`tree-sitter` inversion, the
  openSUSE inversion against it, Gentoo's keyword and maintainer-needed hedges, Fedora's
  blocking F43 lane, Alpine's version-vs-presence guard — and loses only its numbers.

  `update-fleet-versions.sh` now names a **whole tool** whose project slug answered nothing,
  separately from the per-row `?` lines: fifteen of those read as fifteen unlucky lanes rather
  than one wrong name, and the tool name is used verbatim as the Repology slug. Reported, never
  failed — a permanently wrong slug should not red the weekly bot, and the staleness reporter
  already names any row past `FRESH_DAYS` on every `make audit`.

  Four new cases in `scripts/test/41-gen-matrix-parity.sh`, the fixture now derived from
  `FV_TOOLS` so a fourth tool costs a registry line and no test edit. The one that matters
  asserts **each block renders its own tool's rows and names it in the header**: a renderer
  still keyed to jq would print jq's rows into all three regions and file every row's
  provenance under one id, and every pre-existing assertion would still pass — the coverage
  loop sees the id, the widths are uniform, the verdicts derive correctly. Verified by
  re-introducing the defect: three cases red, naming `no-own-rows`, `wrong-header` and
  `leaked-jq` per block.

- **A repo that loses the ruleset binding `main` now pages a human**
  ([#1081](https://github.com/dotgibson/dotfiles-core/issues/1081)). `fleet-protection.yml` was
  the last weekly fleet sweep whose only output was a red run: it wrote a job summary, exited
  non-zero, and stopped there, while `fleet-drift.yml` and `fleet-app-scope.yml` both filed a
  deduplicated issue through `notify-failure-call.yml`. It now does too.

  The asymmetry mattered more here than anywhere, because this sweep is the one whose _own_
  origin story is a blind spot: it exists because a Core fan-out was pushed straight to `main`
  on two repos — one with no ruleset at all, one carrying an admin bypass
  (`dotgibson/dotfiles-Alpine#146`) — and nobody noticed. A check that catches the recurrence
  into a tab nobody watches reproduces the defect it was written to close.

  The `details` string names the fix path, which is local and needs admin credentials
  (`make fleet-protection`, then `--migrate`), and says that the job runs `--rulesets-only` so
  classic protection is unread by design. It also warns not to assume _which_ finding fired:
  no ruleset, a bypass actor and _could not read_ are three different verdicts the script
  keeps distinguishable, and all three are rc=1.

- **The job counts `check-modern`'s rule 8 argues from are gated, so they stop drifting**
  ([#1081](https://github.com/dotgibson/dotfiles-core/issues/1081)). Rule 8's rationale in
  `scripts/modern-baseline.yml` claimed _all 47 runner jobs here already set one_ and
  _cheap while the fleet is at 47/47_ over a tree holding **58**. Eleven runner jobs had
  been added and nothing read the sentence against the tree.

  Not cosmetic, which is the reason to gate it rather than retype it. Rule 8's whole
  argument is that the property is held _universally_ today and the floor is therefore
  cheap to encode — `58/58` **is** the evidence for "cheap", so `47/47` over a tree of 58
  withdraws the argument while still looking like it makes it.

  `scripts/check-modern.sh` grew a `--job-census`, and rule 8's own job walk moved behind
  the same helper that answers it, so the number the prose quotes and the number the rule
  enforces cannot be two different things. `scripts/test/90-policy-gates.sh` holds all six
  claim sites to it — three in the rationale, one in the rule's `uses:` aside, one in the
  test fragment that asserts the rule's shape.

  **Keyed on the claim, not the number**, which is §9m's rule for §9m's reason: three
  numbers are legitimately correct in that one comment about three different sets (runner
  jobs, reusable-call jobs, and the six `*-call.yml@vN` workflows Core owns), so a check on
  bare integers would red on lines that are right. A claim the gate can no longer _find_ is
  a finding too — otherwise rewording the prose silently retires the check.

### Changed

- **The atuin guard no longer stands down under `autostart` — it probes, and warns without
  disabling** ([#1102](https://github.com/dotgibson/dotfiles-core/issues/1102), measured in run
  35171886253). `_core_atuin_daemon_guard` used to unhook itself entirely whenever
  `ATUIN_DAEMON__AUTOSTART` was set, on the premise that atuin supervises its own daemon there.
  A sixth harness arm measured that premise against **18.22.0** and it does not hold: `absent`
  and `stale` both spawn a daemon and land their row, while a daemon whose pid is _alive_ and
  which has stopped serving is never replaced — atuin reads that pid as health. Worse than
  upstream's own report, the client does not merely decline to spawn, it blocks on the pidfile
  lock and then exits 1 (`ERROR error=timed out waiting for lock`). That covers Alpine and
  macOS, where the stand-down meant nothing was watching at all.

  **What it does not do is the part worth reading.** The obvious fix — stop standing down, let
  the existing degrade path run — exports `ATUIN_DAEMON__ENABLED=false`, and under `autostart`
  that removes the _spawn_ itself, permanently defeating the only launcher those two machines
  have. So the guard now stays hooked and probes, and on a failed connect changes **nothing**:
  no export, no degrade flag. A socket that is merely unreachable is still a cue rather than a
  fault — `precmd` runs before the first command, so on a box where nothing has spawned the
  daemon yet that is the normal state, and warning there would put a new line of startup noise
  on exactly the machines this is meant to help.

  The one thing it announces is the wedge, and the discriminator is upstream's own broken test
  read the other way round: a live pid in the pidfile _while nothing answers the socket_ is the
  definition of the shape, because that pid is what blocks the respawn. One warning naming the
  pid to kill, then it unhooks — "once" stays structural. Fork-free, as everything on that path
  must be: a `[[ -r ]]`, a `read` from a redirect and a `kill -0` are all builtins. The
  numeric-glob guard on the pid is load-bearing rather than defensive — `kill -0 0` signals the
  whole process group and always succeeds, so an empty or garbage pidfile would otherwise read
  as wedged on every box that has one.

  `core-doctor` reports it as a third state rather than folding it into the two it had: this
  shell is neither healthy nor degraded, the daemon is still enabled and still the launcher, and
  the pid is carried through to `--json` as `wedged_pid` because the pid _is_ the remedy. Six
  cases in `scripts/test/71-prompt-atuin.sh`, all six red against the previous guard, including
  the four garbage-pidfile shapes.

- **`extract` pins `ouch`'s pre-0.8.0 unpack location, so one archive gives one tree on every
  box** ([#1045](https://github.com/dotgibson/dotfiles-core/issues/1045)). ouch 0.8.0
  (`ouch-org/ouch#962`) changed its default: an archive now unpacks into `./<basename>/` instead
  of the CWD, with a new `--here` restoring the old shape. `zsh/30-functions.zsh` still called
  `ouch decompress` bare, and the fleet is split _today_ — openSUSE Leap ships 0.5.1, Alpine's
  index 0.6.1, GURU 0.8.2, Arch 0.8.3 — so the same `extract foo.tar.gz` scattered into `$PWD`
  on one supported box and nested into `./foo/` on another, with no error on either. Everything
  around that call assumed the CWD: the tarbomb guard `mkdir`s its own containment directory and
  cd's into it (ouch then nested a second one inside), the clobber guard tests CWD-relative names
  (so it could veto a collision that could not happen while missing one that could), and the
  hand-rolled `tar`/`unzip` fallback for a box with no ouch never moved at all.

  `extract` now **probes** `ouch decompress --help` for `--here` and passes it where it exists.
  That is `PORTING-MATRIX.md`'s `sd` rule (footnote ²²) — sniff a version only where the version
  is honest, otherwise ask the CLI what it can do — and it is fail-safe in a way a version
  compare is not: a build without `--here` is a build that already extracts into the CWD, so the
  flag comes out absent exactly where passing it would have been wrong. One fork, paid only by an
  interactive `extract`, never on the startup path.

  **A second, older divergence came out of measuring the first.** ouch writes a single
  decompressed `.gz`/`.bz2` into the CWD on _every_ version, while `gunzip`/`bunzip2` write next
  to the archive — which is the target the clobber guard checks (`${abs:r}`). On an ouch box
  `extract /sub/f.gz` therefore overwrote `./f`, a path the guard never looked at: measured here,
  a file in `$PWD` was destroyed with no warning and nothing landed beside the archive. ouch now
  runs from the archive's own directory for those two formats, so the guard and the unpack agree.

  Four behavioural cases cover the ouch arm in `scripts/test/65-functions.sh`, on a new
  `check_ouch` helper. Nothing in the suite had ever executed that branch — `check`/`check_dep`
  run `zsh -fc`, where `HAVE_OUCH` is unset — which is how a change of default reached the fleet
  without a red test. Three of the four go red against the previous code.

- **`NON-MUTABLE-HOST-PROPOSAL.md` is SHIPPED, and the milestone closes without a major**
  (#1053, the §4.6 rollout tracker). Its header still read _PROPOSED — a minor, not a
  major_, describing §4 as the thing still to do, after every step of §4.6 had landed and
  every issue filed from it had closed. Those steps, and the release each shipped in: `up`,
  the shell-start nudge, the maint runner and `core-doctor` learning the staged host
  (#1049, `v7.6.0`); `bootstrap-test.yml`'s
  `provisioner:` input, the sweep's VM-only skip and the register's `real-bootstrap` gate
  (#1050, `v7.7.0`); the **atomic** variant in `dotfiles-Fedora`
  (dotgibson/dotfiles-Fedora#186) and the **transactional** variant in `dotfiles-openSUSE`
  (dotgibson/dotfiles-openSUSE#191), whose matrix columns rendered in `v7.8.0` and
  `v7.9.0`; and `dotfiles-NixOS`, the **declarative** target and the tenth repo, with the
  home-manager boundary R3 measured (#1051, `v7.9.0`). Every repo Core vendors into is
  pinned at `v7.9.0`. So the status line becomes _SHIPPED — a closed record_, the way
  `V5-PROPOSAL.md`'s did, each runbook step carries the issue and release that discharged
  it, and §5's exit criteria record that **both** consequences the research flagged as
  outliving it are discharged too — dotgibson/dotfiles-openSUSE#201 moved the login-shell
  writes _inside_ the pending snapshot (the `/etc` loss case #1052 measured), and the
  `blib_set_login_shell` declarative arm shipped with the NixOS repo itself, printing the
  `users.users.<you>.shell` declaration instead of running `chsh`.

  **`V8-PROPOSAL.md` is corrected in the same pass**, because it is where this repo keeps
  its roadmap findings and it was carrying a claim measurement disproved: the non-mutable
  host as _"the right **next** major"_ whose schema break makes every vendoring repo
  re-author its declaration. R2 measured it **additive** — six _optional_ keys, zero
  re-authors — so §10 gains a second `*Closed.*` finding beside the "one source, generated
  outward" one it already carries, in the same voice: right about the destination, wrong
  about the bump class. That is twice in a row a roadmap theme's predicted major dissolved
  under measurement, and with it the next major's content is again unwritten.

  **Three comment blocks stopped being true when the keys shipped**, and are fixed here
  rather than left for a reader to trip over. `scripts/check-capabilities.sh`'s
  `CAP_OPTIONAL` note called them _"Four OPTIONAL keys … READ BY NO CONSUMER YET"_ while
  citing #1049 as a reader two lines below itself — there are six, four are read, and three
  fleet repos declare against them. `scripts/test/55-capabilities.sh` said the same, plus
  _"the relaxation stays exactly one key wide, on exactly one provisioner"_ when the
  validator has had **two** relaxations of `PKG_COUNT_PENDING` since R5 (declarative, and
  any host declaring `PKG_APPLY_PENDING`) — both already pinned by cases, only the prose was
  stale. And `scripts/research/README.md` was still titled for R1 alone; the phase is
  closed through R6 and is now marked **archived**, the way the atuin guard beside it is.
  No logic changed in any of the three. `examples/os.capabilities.example` now points a new
  declaration at the three that _ship_ rather than at R2's prototypes.
  (`NON-MUTABLE-HOST-PROPOSAL.md`, `V8-PROPOSAL.md`, `scripts/check-capabilities.sh`,
  `scripts/test/55-capabilities.sh`, `scripts/research/README.md`,
  `examples/os.capabilities.example`)

- **`mise/config.toml` stopped asserting an impossibility mise never had**
  ([#1045](https://github.com/dotgibson/dotfiles-core/issues/1045)). The `lockfile = true`
  block concluded that mise _"does not lock a GLOBAL config's tools"_, from a measurement of a
  bare `mise lock` returning `! No tools configured to lock`. The measurement was right and the
  conclusion was not — `mise lock` targets only the active **project** config root by design,
  and `mise lock --global` is the form that locks this file. Re-measured on the _same_ mise
  2026.5.16 the comment cites: `mise lock --global --dry-run` resolves all 11 declared tools
  across all 7 platforms into `~/.config/mise/mise.lock`. So the flag was never the obstacle,
  and the block's own stated goal — floating `lts`/`latest`/`stable` that still resolve
  identically on boxes provisioned a month apart — is reachable.

  What survives the correction is the reason it is not reached _yet_: that lockfile is written
  **per box**, and this file is copied rather than symlinked, so a lock generated on one machine
  reaches no other. Shipping one fleet-wide has to answer the header's trade — "your local copy
  always wins" and "this is the pinned toolchain everywhere" cannot both be true of the same
  file — which is a design decision and belongs to `/runtime-freshness`, the routine `CLAUDE.md`
  gives this file to. No behaviour changed here and no lockfile was generated.

  Also corrected three lines below: the global-only-settings note still said this file is
  _symlinked_ to `~/.config/mise/config.toml`, which the file's own header has contradicted at
  length since bootstrap started adopting it instead.

- **One pin bumped on the weekly freshness review, one re-held, and the routine that could
  not tell them apart given its history back** ([#1047](https://github.com/dotgibson/dotfiles-core/issues/1047)).
  `scripts/tool-versions.env` is the class no bot covers, so the routine re-audits all ten
  against upstream by hand each week. Eight were still current; the two that were not split:

  | Pin | Was | Now | |
  | --- | --- | --- | --- |
  | `CLAUDE_CODE_VERSION` | 2.1.265 | **2.1.273** | the routine bots' own CLI |
  | `SHFMT_VERSION` | 3.13.1 | 3.13.1 | **held again** — see below |

  claude-code is patch-only drift in the CLI eight `claude-routines.yml` jobs install, with no
  security fix and no forcing function; it rides along with the review that noticed it. No
  checksum step: claude-code is an npm registry install, deliberately outside the `*_SHA256`
  block, `update-tool-checksums.sh`'s five-asset table and §9b's `_check_sha` list. Nothing
  in `.pre-commit-config.yaml` moves either, so §9 stays green untouched.

  **shfmt stays at 3.13.1, and 3.14.1 does not reopen the question.** The hold was decided
  in #813 because 3.14.0 changed shfmt's _output_, not just its behaviour, and the pin exists
  only so `setup-core-tools` installs one verified shfmt for MacBook and the distro/role lint
  workflows — where the step is advisory (`::warning::`, not red), so a bump would not break
  them, it would nag on every run until each repo reformats, with no diff in this repo to warn
  you. 3.14.1 _adds_ output changes on top of that (literal tabs kept in `<<-` heredoc bodies,
  heredoc indentation corrected inside command substitutions), so it moves the cost up, not
  down. The condition is unchanged: bump it alongside a reformat pass across the consumers.

  **The report proposed merging it anyway, and the reason is the interesting part.** The
  routine said so itself in its method caveat — _"this checkout is a shallow clone (single
  commit), so I couldn't read local bump history"_. Its `--allowedTools` have granted
  `Bash(git log:*)` and `Bash(git diff:*)` all along; the checkout simply left nothing for
  them to read, so a deliberate park was indistinguishable from an overlooked pin. Two fixes,
  because either alone leaves a hole:

  - `freshness-triage`'s checkout takes `fetch-depth: 0`, joining `release-readiness`,
    `release-notes`, `shell-review` and `drift-triage`, which each already carry it with a
    comment saying which `git log` a shallow clone would starve.
  - The reason moves to where clone depth cannot hide it: a `# held:` comment above
    `SHFMT_VERSION` in the pin file the routine reads every week regardless, and a paragraph
    in `.claude/commands/freshness-triage.md` making the convention a rule — a pin carrying
    a `# held:` note is reported as **Hold** restating the standing reason, and only a newer
    release that removes the cost (or adds a security fix) reopens it.

- **R1's three remaining cells are measured, and the research phase's last open question is
  closed** (`NON-MUTABLE-HOST-PROPOSAL.md` §5, #1052, runs 35130669056 and 35133704599).
  Two of the three were claims a _shipped_ declaration already made.

  **`dnf search` on a booted bootc host holds as declared.** A hit is exit 0 in 1.2 s **as
  the user**, and an unprivileged `dnf -q makecache` populates the cache first — so
  `dotfiles-Fedora/os/fedora.atomic.capabilities`'s `PKG_SEARCH=dnf search` needs no
  escalator on an atomic host any more than on a mutable one. The read-only half of `dnf`
  is untouched by the read-only root; only the transaction is refused. The new fact is that
  a **miss is also exit 0**, so hit and miss are indistinguishable by status on dnf5 and a
  consumer has to read the output. Nothing reads that status today, which is why this
  changes no code — but it is what a future "is it available?" reader would get wrong.

  **The `/etc` loss case on a transactional host is confirmed, and it lands on the driver's
  own writes.** A file changed both inside a staged snapshot and afterwards in the running
  system keeps only the snapshot's copy on the next boot; a running-only edit made after the
  snapshot opened does carry forward, exactly as transactional-update(8) documents. Measured
  with markers written at three distinguishable moments, plus the real pair: **`/etc/shells`
  lost its post-snapshot append, and the `chsh`'d login shell kept the snapshot's value.**
  That matters because `PKG_INSTALL` on that host _is_ a staging verb, so every provisioning
  run leaves a snapshot open behind it and `blib_set_login_shell` writes into a copy of
  `/etc` the next boot discards, silently. The remedy belongs in `dotfiles-openSUSE`'s
  transactional arm, not in a declaration key, and is tracked as
  dotgibson/dotfiles-openSUSE#199.

  Two `transactional-update` facts fell out of the same run: `dup` refuses outright when any
  enabled repo fails to refresh (zypper exit 4) and deletes its own snapshot on the way out.
  So the transition those markers crossed was the preceding `run` snapshot rather than a
  completed `dup` — recorded as the weaker claim it is. Opening the snapshot _before_ the
  update is the only reason the experiment survived the failure.

  **`chsh` across a NixOS activation reverts — but only for a user the configuration
  declares.** Measured across a _real_ second generation, with two users chsh'd to the same
  path: `root`, which `users.users.root.shell` declares, came back with the declared shell;
  an imperative `useradd` account kept its hand-set one. So `users.mutableUsers = true` does
  not mean hand edits stick — it means the merge leaves undeclared users alone while
  rewriting every declared user's shell on each activation. The hand edit survives exactly
  where nobody needs it to, and is reverted on the operator's own account, which is the
  measurement `dotfiles-NixOS/bootstrap.sh`'s _"would work here … and is still wrong"_ has
  been asserting without. `/etc/shells` is not regenerated to include the new shell either.

  Two things that would mislead a future reader, recorded with it: `chsh` warns _"invalid
  shell"_ for a path outside `/etc/shells` and **takes anyway** (exit 0, a warning not a
  refusal); and `switch-to-configuration test` exited **4** while activation ran normally —
  the non-zero was `home-manager-root.service` failing, not the activation.

  And R1's oldest loose end is tied off: `nixos-rebuild` has exited 1 on these guests since
  iteration 3 with no recorded cause. Running the full `switch` after the verdict names it —
  the **bootloader** half, `grub-install` refusing an ext2 VM disk (_"will not proceed with
  blocklists"_). The activation half had already completed, so a `build-vm` guest can be
  activated but never switched; no future harness should read a `switch` failure there as a
  fact about NixOS.

- **The 2026-09-15 `/tool-scout` scan's four declines are in the ledger**
  ([#1045](https://github.com/dotgibson/dotfiles-core/issues/1045)). `rip2`, `tlrc`, `bottom`
  and routing Core's zsh fzf widgets through `fzf --tmux`, each with the reasoning that decided
  it, appended to `.claude/tool-decisions.md`'s Declined table. The scan itself could not write
  them — its ledger edit was permission-blocked, so it printed the rows at the end of the report
  instead. That is the failure mode the ledger exists to prevent: a decline that lives only in a
  closed issue is a decline the next scan re-proposes, which is how `hexyl` came back six days
  after #395 rejected it. Three of the four are lateral-tool declines (`no capability delta`);
  the fourth records a design argument about picker behaviour that would otherwise be re-made
  every time fzf ships a tmux feature.

- **`scripts/os-repos.txt` no longer claims to be the only step.** Its header said "THIS
  FILE IS THE ONLY EDIT", which is why #1064 stopped there; it now names the App
  installation as the second registration, with the Organization-Owner path to add it.
  The same correction lands in `VENDORING.md`'s onboarding section (with why this is _not_
  a return of the four-copies problem #669 removed: those were four copies of one fact,
  this is one fact in each of two systems that cannot read each other) and in the guidance
  `scripts/new-os-repo.sh` prints after scaffolding a repo.
- **Both atuin guard premises re-measured against 18.22.0; both `VERIFIED_AGAINST` anchors move**
  ([#1045](https://github.com/dotgibson/dotfiles-core/issues/1045), run 35163334747). Upstream
  released 18.22.0 on 2026-09-09, one minor past the 18.21.0 the anchors in `zsh/00-tools.zsh`
  carried — which `scripts/research/README.md` names as the cue to re-measure. One
  `atuin-guard-verify` dispatch, checksum and build-provenance verified: `holds` on the
  silent-discard premise and `holds` on autostart self-healing, with the hermetic detector
  self-test green beside them. Both report jobs skipped, which is how that workflow says
  `holds`. Editing an anchor is a claim that the premise was re-measured at that version, so
  this is that claim and not a version bump.

  **18.22.0 raises the guard's stakes rather than lowering them**, and the block now says so:
  the release moves history deletion (atuin #4045) and sync (#4055) into the daemon and adds
  command-output capture with a periodic flush (#4070), so a dead-socket window costs more than
  the single history row it cost on 18.19.0. It also adds a _second_ socket under
  `/tmp/atuin-$UID` for the pty-proxy — the same directory as the guard's first candidate, which
  is not a collision because the candidate list names `atuin.sock` explicitly. Recorded so the
  next reader does not have to re-derive it.

  **And a gap the four arms have always had is now written down where the stand-down lives.**
  `absent` has no socket, `stale` has a socket file with no process — neither is a daemon whose
  PID is _alive_ but which is not serving. atuin autostarts from the pidfile alone, so a wedged
  PID blocks the respawn indefinitely (upstream `atuinsh/atuin#4114`, open against 18.22.0), and
  that is the one arm where standing down is wrong — on Alpine and macOS, where autostart is the
  only mitigation there is. Tracked as a new harness arm in #1091, deliberately not bundled
  here: adding an arm inside a re-measurement would conflate "upstream moved" with "we started
  measuring more".

- **`GITHUB-APP-AUTH.md` documents `Metadata: read`**, the fourth permission the
  installation API actually returns. GitHub grants it mandatorily and offers no way to
  switch it off, so a doc naming three verbs against an API returning four is how the new
  grant assertion would have been "corrected" into permanent red. Also: `fleet-app-scope.yml`
  joins the per-mint consumer table, and `freshness.yml`'s row said ×2 for three mint steps.
- **`RELEASE-RUNBOOK.md`** stops asserting the App is "installed on every target repo" and
  says what now checks it, plus a troubleshooting row for the symptom itself — nine pushes
  and a 403 on the tenth.
- **`scripts/freshness-dashboard.sh`** said of the fleet App that there is "nothing to
  probe here". There was: its reach. The board now links the register that probes it
  rather than recomputing it (it holds no App mint, deliberately).
- **§3 keeps the parser's message instead of discarding it.** `bash -n` and `zsh -n` ran
  under `2>/dev/null`, so a syntax failure reported `bash syntax error: <file>` and nothing
  else — no line, no reason. When the only leg that disagrees is macOS's bash 3.2, that is
  the entire question, and #1075 spent a CI round trip bisecting a file by hand for want of
  a line number that was sitting in the stderr the check was throwing away. Both now pass
  the message to `fail_detail`. §5k's new rule above catches one construct locally; this
  covers every other way a parser can refuse, including the gaps that rule names.
- **nvim plugin pins move forward for five plugins.** `fzf-lua`, `gitsigns.nvim`,
  `nvim-tree.lua`, `render-markdown.nvim` and `schemastore.nvim` advance to upstream HEAD —
  the set a 2026-09-16 re-run of the fleet health board's signals (#794) found stale, four
  days after #965 rolled the previous one. The other three signals were green on the same
  run: all **ten** vendored `core/` trees pristine at `v7.9.0` (the tables count
  `dotfiles-NixOS` for the first time, #1064); every repo current except `dotfiles-Windows`,
  whose 28-commit gap is its Tuesday `nvim-sync` cron rather than drift — the one Core
  commit in the range that touches `nvim/` landed after this week's run; and all eight zsh
  plugin pins current.

  Every new SHA is a strict fast-forward of the one it replaces (`status=ahead`,
  `behind_by=0` in all five), and each range was read before promotion:

  - **`fzf-lua`** `05e44d3` → `02bc882`, 3 commits: a `keymap_edit` action fix in
    `path.lua`, emmylua 0.25.1 type-lint fixes, CI vimdoc autogen. The fix lands on a
    picker Core binds (`require("fzf-lua").keymaps`) — editing a mapping from that picker
    now resolves its source location.
  - **`gitsigns.nvim`** `f2421c5` → `8d79f24`, 9 commits: a unified diff panel (staging,
    cursor preservation, `--diff=none`), `nowait` blame bindings, and
    `refactor(compat)!: drop support for Neovim 0.10`. The breaking commit is inert here —
    the fleet floor is Neovim 0.12.0 (`scripts/tool-versions.env`, `PORTING-MATRIX.md`).
    `M.diff` gained an `opts` parameter ahead of its callback, with an `@overload` for the
    old arity; Core does not call it. All eight entry points Core does bind are
    **byte-identical** across the range: `nav_hunk`, `stage_hunk`, `reset_hunk`,
    `stage_buffer`, `preview_hunk`, `blame_line`, `diffthis` and `:Gitsigns select_hunk`.
  - **`nvim-tree.lua`** `882c54f` → `8d81449`, 1 commit: `experimental.session_restore_nvim`
    flips to `true` by default. It requires Neovim 0.13+, so it is inert at the fleet's
    floor; when the floor crosses it, it restores tree buffers for the sessions
    `persistence.nvim` already saves rather than competing with them. Core sets no
    `experimental` key, so it takes the default either way.
  - **`render-markdown.nvim`** `a778444` → `640a3ec`, 1 commit: the 8.14.0 release commit
    alone — changelog, doc date, `M.version` string, tests. Its headline feature
    (multiline table cells) was already at the pin this replaces.
  - **`schemastore.nvim`** `72d144a` → `71cd030`, 3 commits: two catalog refreshes plus a
    workflow change that drops a PAT. Data and `.github/` only.

  Nothing renames or removes an API Core calls.

### Fixed

- **§5f's ledger documented a nine-repo fleet — every stated ratio was one repo behind.**
  The ledger _rows_ were correct and `dotfiles-NixOS` (#1064) is in all of them, so the
  gate has been measuring the right thing; it was the comment block above them that still
  read `/9`, along with "hand-forked _nine_ ways" and "whether the other _eight_ picked
  them up". All nine figures now read against the ten-repo fleet, and each was **derived
  from the ledger rows and the exemption `case`** rather than hand-counted:
  `blib_resolve_su` 9/10, `blib_sudo_keepalive_start` 8/10, `blib_user_bindirs_on_path`
  8/10, `blib_note_fail` 9/10, `blib_failures_report` 10/10, `blib_wire_summary` 9/10,
  `blib_install_core_guard` 10/10, `BLIB_DRY` 10/10, `blib_main` 9/10.

  Two distinctions the old text blurred and this keeps: the six exemptions are Defense ×4
  and MacBook ×2, so `blib_user_bindirs_on_path` is 8/10 with **one** exempt and
  `dotfiles-MacBook` genuinely _short_ — not a tenth exemption — and `blib_wire_summary`
  has no exemption at all. The forward-looking MacBook note now says its row would read
  10/10, not 9/9, if that repo's surface ever shrank to what `blib_main` covers.

  **The driver ratchet itself is complete and was not the problem**: 9 of 10 on
  `blib_main`, `dotfiles-MacBook` outside by design, 10/10 compliant. NixOS arrived
  already on the driver, so the repo that moved the denominator did not reopen the
  ratchet. `scripts/new-os-repo.sh` loses its "eight callers" count for the same reason
  the ratios drifted — the issue reference says everything the number did, and cannot go
  stale.

- **Rule 4 can see an image bound to a shell variable** — the surface that hid three
  unpinned refs from it ([#1099](https://github.com/dotgibson/dotfiles-core/issues/1099)).
  This is #1055's finding one level up, and worth naming as a pattern: that one was rule 4
  keyed on a _tool name_ (`docker`), so podman walked past it; this one is the same rule
  keyed on a _command_, so `img='nixos/nix:latest'` fed through a matrix and run as
  `"$IMAGE"` walked past it too. A gate keyed on where a hazard usually appears misses it
  wherever it appears next.

  The new scan is **deliberately narrower than the command scan, and has to be**. A command
  line supplies the context that says "this argument is an image"; an assignment supplies
  none, so the value has to carry that evidence itself. It therefore requires a registry- or
  namespace-qualified reference — `quay.io/fedora/x:44`, `nixos/nix:latest` — and skips a
  bare `img=alpine:3.21`, which nothing in the token distinguishes from `START=12:30`. That
  is the same bare-name gap the command scan already documents, reached from the other side,
  and it is now the only one left in the rule.

  Held by a third rule-4 assertion carrying both halves in one fixture, because the
  narrowness _is_ the rule: the two qualified refs fire, while a pinned ref, a
  `localhost:5000/…` build, a bare `alpine:3.21`, a `START=12:30` and an
  `URL=https://example.com:8080/x` all stay silent. Red against the previous script, green
  against this one, and green on a tree where the three refs are pinned — so it distinguishes
  a rule that passes from one that never matches.

- **The research matrix's three container images were unpinned, two of them mutable
  `:latest`** ([#1099](https://github.com/dotgibson/dotfiles-core/issues/1099)).
  `research-nonmutable.yml` picks its image in the plan job's `case` and hands it to the
  matrix, so `quay.io/fedora/fedora-bootc:44`, `registry.opensuse.org/opensuse/tumbleweed:latest`
  and `nixos/nix:latest` never appeared on a command line — the later jobs only ever see
  `docker pull "$IMAGE"`. `check-modern.sh` rule 4 reads command lines and `FROM`, not shell
  assignments, so the file passed the floor green while the same file already pinned
  `registry.fedoraproject.org/fedora:44@sha256:61beafd3…` twelve lines further down. Drift
  against its own established shape, not an exemption.

  All three now carry a digest. **Pinning a rolling image is a deliberate trade and the file
  now says so**: tumbleweed and nixos/nix move continuously, so a digest freezes what the
  harness measures — right for a research run, since a measurement nobody can reproduce is
  not a measurement, but it means the digests must be refreshed whenever the research is
  re-run, or a later run reports a 2026-09 image as if it were current. The comment claiming
  the matrix legs "pin by variable" was a euphemism for _not pinned_; it is now simply true.
  The pull step's name carried the whole reference, which a digest turns into an unreadable
  hundred-character title, so it names `matrix.target` instead.

  Pinning the three was only half of
  [#1099](https://github.com/dotgibson/dotfiles-core/issues/1099); the entry above is the
  other half, which teaches the rule to see the surface that hid them.
- **Three external container images ran unpinned, and the gate that forbids exactly that
  could not see them**
  ([#1055](https://github.com/dotgibson/dotfiles-core/issues/1055)). `check-modern.sh`
  rule 4 requires an `@sha256:` digest on every container image. It was keyed on the tool
  name `docker` and read one physical line at a time — so `research-nonmutable-vm.yml`,
  which drives containers with _podman_, builds one from a heredoc `Containerfile`, and
  wraps a long command across `\` continuations, reached three images with no digest at
  all while the floor reported zero violations:

  ```text
  FROM quay.io/fedora/fedora-bootc:42               a Containerfile FROM — no surface matched it
  docker.io/library/registry:2                      `sudo podman run` — podman was not in the verb scan
  quay.io/centos-bootc/bootc-image-builder:latest   podman, AND behind three `\` continuations
  ```

  The third is the one to lead with: a `:latest` tag, re-resolved every run by
  `--pull=newer`, executed `--privileged`. All three are now digest-pinned, and
  `--pull=newer` is gone — chasing a moving tag is its whole job, and against a digest it
  does nothing but mislead the next reader. bootc-image-builder publishes no semver tag
  upstream, only `latest` and raw git SHAs, so `latest@sha256:…` _is_ its pinned form.

  **Rule 4 now covers the surfaces that hid them.** The command scan is engine-agnostic
  (`docker|podman`, with `create` beside `run|build|pull`), joins `\` continuations into
  one logical line, and reads a Containerfile `FROM`. Widening a tolerant `name:tag` scan
  that way drags in tokens that merely _look_ like images, so it now tests each whitespace
  token **anchored** and skips what cannot be pinned: a port map (`-p 5000:5000`), a `:ro`
  mount, a `--flag=value`, a `"$IMAGE"` variable, the image being built by `-t`, and a local
  registry or a `localhost/…` image built in the same job. Without that filter the rule
  reds on the very file it was widened for, over work nobody can fix.

  Rule 4 had no behavioural coverage before this — it was "green on this tree", which cannot
  tell a rule that passes from one that never matches. Two assertions now hold it, one per
  half, and the positive one asserts the continuation hit at the _chain head_ line, which a
  per-line scan cannot produce. Two LATENT gaps stay open deliberately, named in the code: a
  bare `docker run alpine` with no tag — that same tag requirement is what stops a
  multi-stage `FROM builder` from ever false-firing — and a `FROM` buried mid-line.

  The generalisable lesson is in the shape of the old rule, not in the images: it was keyed
  on a tool name rather than on the hazard, so a workflow reaching for a different container
  runtime walked straight past it. A third gap, named beside those two, is that lesson
  recurring one level up: keying on a _surface_ leaves an ASSIGNMENT hiding the literal just
  as well as a different runtime did. `research-nonmutable.yml` picks its image in a `case`
  and runs `docker run … "$IMAGE"`, so three refs — two of them mutable `:latest` — never
  reach a command line at all. Scanning shell assignments wants its own filter and its own
  tests rather than a bolt-on here, so it is filed as
  [#1099](https://github.com/dotgibson/dotfiles-core/issues/1099) and documented in the rule,
  which is the only honest way to hold a known miss.

- **`--list` was silent about a third of `PORTING-MATRIX.md`, and the test asserting
  otherwise passed** ([#1096](https://github.com/dotgibson/dotfiles-core/issues/1096)).
  `scripts/gen-porting-matrix.sh --list` is documented in its own `--help` as "every cell's
  provenance", but only `render_commands` and `render_packages` ever wrote to `$LISTFILE`:
  63 `commands` rows and 288 `packages` rows against **zero** for `fleet-versions`, whose
  table carries 17 targets. `render_fleet_versions` referenced neither `LISTFILE` nor
  `MODE`.

  It now emits three cells per target, and the distinction is the point: the version and
  the `verified` date are _recorded_ in `scripts/fleet-package-versions.tsv`, while the
  `vs ≥ floor` verdict is _computed_ from the version against the floor row — so that cell
  cites **both** lines it depends on, because provenance naming only the version row would
  hide the half that moves on a floor bump. Line numbers come from `awk`'s `NR` over the
  whole file rather than a counter over the comment-filtered stream, so `file:line` points
  at the line a reader opens.

  **The more interesting half was the test.** `scripts/test/41-gen-matrix-parity.sh` already
  asserted "`--list` names each cell's provenance" and passed throughout, because it
  spot-checks four individual rows and never asked whether a block was missing. The new
  assertion derives the expected set from `BLOCK_IDS` and fails until every registered
  block appears, the way `preflight` already refuses an unregistered marker — verified by
  removing the emission and watching it red, in the state where the old spot-check still
  went green.

  `--list --local` consequently becomes a real narrowed listing instead of the usage error
  #1092 made it: that refusal existed only while the in-repo block contributed no rows,
  where scoping would have produced an empty listing that exited 0.

- **`PORTING-MATRIX.md` was silent about Fedora on both halves of the nvim-treesitter
  requirement, and the report that noticed named the wrong release**
  ([#1010](https://github.com/dotgibson/dotfiles-core/issues/1010)). The non-mutable-host
  harness measured `neovim` 0.11.5 and `tree-sitter-cli` 0.25.10 on a `fedora-bootc:42`
  container and read them as Fedora's answer. Fedora 42 went **EOL on 2026-05-13** and that
  quay tag has been frozen since; `dotfiles-Fedora`'s own `packages.yml` declares the lanes
  as **F43/F44 blocking**, F45 and rawhide advisory. Re-measured 2026-09-16 against
  `packages.fedoraproject.org` and `mdapi.fedoraproject.org`, and the finding survives on a
  release somebody is actually on: **F43 carries `neovim` 0.11.6-1.fc43 and
  `tree-sitter-cli` 0.25.10-2.fc43, below both floors** (≥ 0.12.0, ≥ 0.26.1), while F44, F45
  and rawhide clear both at 0.12.5 and 0.26.11.

  Footnote ³³ therefore names **five** targets rather than four, and a **fourth mechanism**.
  Fedora is neither a frozen archive (Debian), nor a keyword split (Gentoo), nor frozen
  concurrent branches (Alpine, openSUSE Leap): it **rebases inside a release for some
  packages and not others**, so F44 crossed 0.11 → 0.12 in `updates` while F43 ends its life
  on the 0.11 branch. That makes upgrading release the only lever on F43 — the mechanic ³⁴
  already records for jq on this same distro, and the exact inverse of Alpine's in-place
  backport. Footnote ⁵'s Fedora line, which said only _verify ≥ 0.26.1, else mise/cargo_,
  gains the same per-lane spread it already gave Alpine.

  `dotfiles-Fedora` repeats Alpine's asymmetry precisely: a floor recorded in prose for
  nvim-treesitter's _dependency_ and nothing at all for its _host_, which leaves it the last
  repo in the fleet with no floor guard. Filed as dotfiles-Fedora#192; it moves no matrix
  cell, because the package table has no Fedora column to derive.

  **The harness pin is the part that generalises.** Both research workflows pinned
  `fedora-bootc:42` (and a digest-pinned `fedora:42`) for a question about _host shape_, and
  its package versions were then read as the distro's. Both now pin **`:44`**, a blocking
  lane. R1–R6's verb findings stand as measured on `:42` and
  `NON-MUTABLE-HOST-PROPOSAL.md` keeps saying so — what it now also says is that their
  package versions are not evidence about the fleet. Footnote ³³'s closing rule widens with
  it: ask the keyword question, the branch question **and the rebase question**.

  Not fixed here, and filed as
  [#1082](https://github.com/dotgibson/dotfiles-core/issues/1082): ³³'s table is
  hand-written prose that has now gone stale four times (dotfiles-Gentoo#116,
  dotfiles-Alpine#170, dotfiles-openSUSE#178, this), while
  `scripts/fleet-package-versions.tsv` — dated rows, a derived verdict, a weekly bot —
  exists for exactly that and holds only `jq`.
- **`--dry-run` hid the only thing it had to say: that it would displace your `~/.zshrc`**
  ([#1057](https://github.com/dotgibson/dotfiles-core/issues/1057)). `blib_write_zshrc_loader`'s
  `BLIB_DRY` branch announced _would write managed ~/.zshrc loader_ and returned — it never
  tested `[[ -f "$rc" ]]`, so `blib_wire_summary` closed the plan with `0 backed up` and the
  real run then warned `backed up existing ~/.zshrc -> ~/.zshrc.pre-dotfiles.…`. Wiring is
  otherwise all symlinks into paths Core owns; this is the **one** action in the pass that
  touches a file the user wrote, on exactly the box where it matters — a migrating machine
  with a hand-written zshrc — and the dry run is what they read _before_ consenting.
  `#1026` fixed the real run's tally and left this half behind, which made it the only
  backup site in the library that did not preview: `blib_link` has said _would back up +
  link_ and `blib_install_system_file` _would back up + write_ all along. The phrase here is
  deliberately the latter's, so the library has one grep for "a backup was planned", and it
  is emitted **after** the "would write" line because that is the order the real run acts
  in. A `BLIB_DRY` twin of `#1026`'s test pins the count, the absent backup file and the
  untouched skeleton; a second case pins the fresh box, where nothing is displaced and
  nothing is counted.
- **Any host could buy its way out of a required package verb by declaring a reboot probe**
  ([#1057](https://github.com/dotgibson/dotfiles-core/issues/1057)). `scripts/check-capabilities.sh`
  relaxes `PKG_COUNT_PENDING` in two cases, and only the `PROVISIONER=declarative` one was
  gated on the provisioner. The other accepted `PKG_APPLY_PENDING` from anybody — so a
  mutable repo declaring the entirely truthful `PKG_APPLY=sudo systemctl reboot` beside
  `PKG_APPLY_PENDING=test -e /var/run/reboot-required` (Debian and Ubuntu both have that
  file) could drop the count verb and stay green. `up` then reads the absent verb as the
  `-1` sentinel and goes permanently silent about available updates, on a host with a
  perfectly good unprivileged count verb, with the gate asserting the declaration is
  complete. The arm is now **`atomic` only**, which is what was measured: the root-only
  refusal is rpm-ostree's (_AutomaticUpdateTrigger not allowed for user_). The fleet's one
  transactional host answers `zypper -q list-updates` as the user and declares it, so it
  never needed the exemption — all twelve declarations still validate unchanged.
  `scripts/gen-porting-matrix.sh` carries the same rule in awk under a comment reading
  _ONE RULE, TWO READERS_, and moved with it; no rendered cell changes.
- **A leading zero made an exit status mean something else, silently**
  ([#1057](https://github.com/dotgibson/dotfiles-core/issues/1057)). `(( ))` re-expands a
  named variable as an arithmetic expression, so an all-digit string starting with `0` is
  **octal**: `PKG_APPLY_PENDING_EXIT=077` validated as 63, and `099` was an invalid-octal-digit
  error that `(( ))` reported by returning false — into a script deliberately running
  without `set -e`, which discarded it. `00` and `000` walked past the "omit it to mean
  zero" rule as well, because the reject arm only ever matched the literal `0`. Two copies
  of the check had it (`PKG_PENDING_EXIT_NONE`/`_SOME` and `PKG_APPLY_PENDING_EXIT`) and
  both are fixed together, since a fix to one would have left the other lying. An exit
  status is written `77`, never `077`, so the class is refused rather than decoded; `10#`
  keeps the surviving comparison decimal regardless. Ten cases pin it. This was in the
  weekly review's _Clean_ list — correctly, as to control flow, and the arithmetic was the
  part nobody had run.
- **The capability cross-check told openSUSE to install the shell builtin `test`**
  ([#1057](https://github.com/dotgibson/dotfiles-core/issues/1057)). `--packages` warns when
  a verb's leading token is absent from `install/packages.txt`; MicroOS answers the staged
  question with `test -e /run/reboot-needed`, and no distro packages `test`, so no edit to
  any list could ever silence it. Builtins are skipped now. This is the one narrowing the
  check can make portably — it runs on a CI Ubuntu box against Fedora, Arch and Alpine
  declarations, so asking whether `zypper` exists _there_ would answer about the wrong
  machine, while a builtin is a builtin everywhere. It is a small correction to a noisy
  check: measured across the fleet, every mutable declaration already draws 7–10 of these
  warnings (Debian 10, all of them `apt-get`/`apt-cache`/`dpkg`), which the code comment
  has always anticipated and which is now tracked separately.
- **The R4 prototype patches promised a package the package manager had dropped**
  ([#1090](https://github.com/dotgibson/dotfiles-core/issues/1090)). `dotfiles-openSUSE`'s
  `zypper_install` silently drops names `zypper se --match-exact` cannot find on that
  MicroOS snapshot — recording a `_note_fail` and moving on — but yazi's hint was keyed on
  `TU_STAGED`, the run's **tally**, so it fired whenever any of the other ~40 packages had
  staged. Trigger: yazi absent from the enabled repos, which is real (it has lived in a
  devel repo). The operator was told _yazi is in the next snapshot — live after the
  reboot_, the `elif` skipped the advice naming the fix, and after the reboot yazi was
  simply not there. That is the doctor-hint class exactly: a hint promising what the
  package manager did not do. The patch now records the staged **names** and asks about
  yazi; the tally keeps counting, because the closing "N package(s) transacted" line is a
  genuine count. Membership is a padded whole-token test, so `yazi-fm` does not answer for
  `yazi`.
- **The R4 Fedora patch could leave a truncated COPR file and brick `dnf` for the rest of
  the run** ([#1090](https://github.com/dotgibson/dotfiles-core/issues/1090)). It curled
  the repo file straight into `/etc/yum.repos.d` under `>/dev/null 2>&1 || true`. Measured
  against curl 8.18.0: a 404 writes nothing — that is `-f` working, and it is the case
  anyone would test — but a connection dropped **mid-body** exits 18 with the partial
  bytes already on disk, and a 197-byte `[copr]\nbaseurl=…` fragment is a broken `.repo`.
  dnf parses every file in that directory, so one bad line fails **every later dnf call**
  with _Error in configuration file_: not just lazygit, but the rest of the bootstrap and
  the box afterwards. R6 had already measured that downstream cost from the other
  direction, when the reusable job's curl shim wrote the word `shim` to an `-o` path (run
  34938554648) — on a real box there is no shim to blame. It now downloads to a temp file
  and `install`s it only on success, so the directory either gets the whole file or none
  of it; curl runs unprivileged, since only the move into `/etc` needs the escalator; and
  the failure is reported instead of swallowed twice.
- **`nonmutable-r6.sh` split its report across two files when `--out` was relative**
  ([#1090](https://github.com/dotgibson/dotfiles-core/issues/1090)). `: >"$out"` truncates
  against the invocation cwd, then `cd "$repo_dir"` sends every later `say`/`excerpt`
  somewhere else: measured, 286 bytes at the path the caller named and 1,469 bytes hidden
  under the repo. Latent — both workflow call sites pass an absolute path — and now one
  file of 1,755 bytes either way. The script already records the twin of this hazard, in
  the comment on `resolve_all`'s local `out`.

  All three were found by the weekly `/shell-review` (#1057) and are prototype patches
  under `scripts/research/`, vendored nowhere. They are fixed here because §4.3 says a
  repo PR starts from them, so a defect left in place is one that gets copied out. Both
  patches were regenerated mechanically against their recorded base commits and re-checked
  with `git apply`; the declarations they create still validate.

- **The `fleet-versions` block went unchecked on every lone clone — including all of CI**
  ([#1046](https://github.com/dotgibson/dotfiles-core/issues/1046)).
  `PORTING-MATRIX.md` has three generated blocks, and only two of them read the sibling OS
  repos: `fleet-versions` renders from `scripts/fleet-package-versions.tsv`, in this repo.
  But the whole of `--check` sat behind the fleet resolve — `resolve_fleet` exits 3 about
  125 lines before that table is ever rendered — so §9h skipped **as a unit** and filed an
  environment SKIP over an input it was holding. A hand-edit to that table was invisible to
  the gate everywhere the fleet was not beside the repo, which is every CI leg and every
  git worktree.

  `scripts/gen-porting-matrix.sh --local` is the scoped half: it selects the new
  `LOCAL_BLOCKS` registry, resolves no fleet, and passes every other marked region through
  **exactly as found on disk** — so the existing byte-exact whole-file compare reduces to
  "do the local blocks match" and the `%x` sentinel, `core_files_identical` and the
  `git diff --no-index` report are reused rather than copied. 3 is unreachable under it, by
  construction, which is the property §9h now classifies on rather than inferring.

  **It is a write mode too, deliberately.** A gate that reds on a box whose only repair
  needs a fleet that box does not have is a gate nobody can act on, so the failure names
  `scripts/gen-porting-matrix.sh --local` — and `41-gen-matrix-parity.sh` asserts that what
  it writes is byte-identical to what the full render writes, that it leaves the
  fleet-derived regions untouched, and that a broken marker in a region it does **not**
  render is still the structural 2. §9h's exit-3 arm now reports a pass for the in-repo
  block beside a **scoped** skip naming the two tables that genuinely were not covered;
  `--strict` and `--require-siblings` keep their meanings.
- **The fleet App register called `dotfiles-Windows` surplus, and the doc told an Org Owner
  to remove it** ([#1110](https://github.com/dotgibson/dotfiles-core/issues/1110)).
  `GITHUB-APP-AUTH.md`'s install list withheld that repo on the grounds that it vendors no
  `core/`, is absent from `scripts/os-repos.txt` and is not a fan-out target. All three are
  still true, and none of them is why the install is there any more. Its three weekly sync
  bots — `nvim-sync.yml`, `starship-sync.yml`, `theme-sync.yml` — opened their PRs with
  `GITHUB_TOKEN`, so GitHub's recursion guard meant `ci.yml` never fired, no required context
  ever arrived, and every sync PR sat `BLOCKED` until a human closed and reopened it
  (dotgibson/dotfiles-Windows#265). They now mint the App token in the shape `freshness.yml`
  uses (dotgibson/dotfiles-Windows#268), which is the **self-PR** justification `dotfiles-core`
  has held since #1071 — so the same reasoning that puts Core on the list puts Windows on it.

  The install already existed, so nothing was broken; the risk ran the other way.
  `scripts/fleet-app-scope.sh` reported it under _"installed but nothing writes to it"_ — a
  `_fatal` row, so the weekly register was **red** — and acting on either that or the doc would
  have taken those three bots back to weekly manual reopens. Because they degrade rather than
  fail, the only symptom would have been sync PRs quietly going `BLOCKED` again. The expected
  set is now thirteen repos, the consumer table carries the three bots as its own row, and the
  grant half is untouched: they take a strict subset of the verbs the App holds and
  deliberately not `Workflows: write`.

  **One gate moved with it, and was found dead on the way.**
  `scripts/test/90-policy-gates.sh` holds the script's expected set to the doc section, and its
  forbidden-pair check read `EXTRA_REPOS` through `grep -o 'dotfiles-[A-Za-z]*'` — which can
  never match `htpx`, the only name it still forbids. That was survivable only while
  `dotfiles-Windows` was also forbidden and _did_ match; reducing the list to `htpx` alone would
  have left the assertion vacuous and passing. It now parses every token in the declaration,
  and asserts the declaration is still the single line that parse assumes.

- **Three Core docs said `dotfiles-Defense` still hand-rolls its band-85 role stage.** It
  shipped `blib_link_role_layer` in #976 (its own dotfiles-Defense#292, 2026-09-13), and
  `wire_defense_stage` exists nowhere in that repo outside its vendored `core/` copies of
  these very files. The claim was triplicated **by design** — `core.manifest`,
  `lib/bootstrap-lib.sh` and `PORTING-MATRIX.md` each cited the others as corroboration —
  so it could not self-correct, and two of the three are vendored out to the whole list.
  `lib/bootstrap-lib.sh` had become self-contradictory, asserting the fork at `:832` while
  documenting and implementing the adopted path at `:1670` and `:1849`. All three are now
  past tense, and the retired `BLIB_DRY`-fork paragraph is gone: that divergence is what
  the helper existed to end, and both repos now go through `_blib_dry()`.
- **Seven places said `PORTING-MATRIX.md` had two generated blocks**, three of them
  mis-attributing the third's source and two of them — `.claude/commands/doc-audit.md` and
  `.claude/agents/doc-consistency.md` — telling the doc-audit routine that the footnote
  region is entirely hand-written. That is how a generated block living inside footnote ³⁴
  stayed outside the auditor's remit. Both now point at `BLOCK_IDS` as the registry rather
  than naming a count, and flag the one overlap. Also corrected: `Makefile`'s `make help`
  line, `PORTING-MATRIX.md`'s size (~1,350 → ~1,570 lines) and its hand-written footnote
  count (~1,100 → ~1,230).
- **`atuin-guard-verify`'s report still described the stand-down #1102 removed, and filed an
  issue recommending the fix that had just shipped**
  ([#1112](https://github.com/dotgibson/dotfiles-core/issues/1112)). The detector measures
  **upstream** — nothing in it sources `zsh/00-tools.zsh` except a `grep` for the anchor, and
  the verdict is computed from `ARM_SPAWN` alone. That is right, and is unchanged here: `moved`
  is the honest answer while `atuinsh/atuin#4114` is open. What was wrong is everything the run
  then _said_. The finding string ended _"and the guard's stand-down leaves this shape
  unprotected"_, and the remedy paragraph still listed **"probe but warn instead of disabling"**
  as something to consider — which shipped in #1102.

  The cost is measurable rather than theoretical: the weekly routine filed
  [#1109](https://github.com/dotgibson/dotfiles-core/issues/1109) at `04:01Z`, **two minutes
  after #1106 merged at `03:59Z`**, recommending the change that had just landed. The report is
  the issue body, so it would have recurred every run.

  Re-measured before touching anything — `--premise autostart` against atuin **18.22.0** (the
  anchor, `same`) on `Linux x86_64 glibc`: `moved`, with `absent` and `stale` × `{hook, plain}`
  all spawning and landing their row, and both `wedged` arms spawning **no** at delta 0, rc 1.
  Identical to the run #1109 reports. The upstream fact has not moved; Core's answer to it
  already had.

  So the report now leads with what Core already does, and asks what is **left**: a socket
  health check upstream (`atuinsh/atuin#4114`), or a shape the guard's warning does not
  recognise. The trap paragraph stays, narrowed to the thing that is still wrong — the degrade
  path, which under `autostart` deletes the spawn Alpine and macOS depend on. The same
  correction lands in `.github/workflows/atuin-guard-verify.yml`, `scripts/research/README.md`,
  `scripts/test/52-atuin-autostart.sh`'s comments, `PORTING-MATRIX.md` (whose §autostart
  paragraphs contradicted the one #1106 added, in the same document), and
  `.claude/commands/tool-scout.md` — that last one being the guidance a future `/tool-scout`
  follows on _seeing_ a `moved` verdict, which until now warned the reader off the fix that
  shipped.

- **Footnote ³¹ listed six `go install` rows while its own prose counted seven** — `duf`
  was missing, though `dotfiles-Alpine/bootstrap.sh:493` go-installs it. The prose was the
  correct half: with `duf` the set is seven and exactly five need a major-version suffix, a
  `cmd/` subpath or a different host, so the row was added and the sentence left alone.
- **`core status`'s dispatch comment omitted `--deep`**, which `_core_status_render`'s
  `--help` line has advertised and the function has parsed all along — drift inside the
  block whose stated job is to be the one source the completion, the did-you-mean and the
  usage lines all read.
- **The README's optional-flags tour omitted Arch's `--no-flatpak` and Gentoo's
  `--no-extras`**, both real, and `.claude/agents/doc-consistency.md` still called this an
  _eleven_-repo system — the auditor's own charter, stale since `dotfiles-NixOS` made the
  whole system twelve.

## [v7.9.0] - 2026-09-16

### Added

- **`PORTING-MATRIX.md` renders the atomic and declarative editions** — the two columns
  #1062 could not add (runbook step 5 of `NON-MUTABLE-HOST-PROPOSAL.md` §4.6, #1051).
  `dotfiles-Fedora` gains `Atomic=os/fedora.atomic.capabilities` as a second label beside
  `Workstation` (the idiom openSUSE already uses for three), and `dotfiles-NixOS` gets a
  column of its own.

  **What blocked them was one line.** `scripts/gen-porting-matrix.sh` refused any
  declaration missing a key `CMD_ROWS` names — and both of these legally omit
  `PKG_COUNT_PENDING`, which `scripts/check-capabilities.sh` permits under
  `PROVISIONER=declarative` and whenever `PKG_APPLY_PENDING` is declared beside it. That is
  why #1062 shipped openSUSE's transactional column, which declares the count verb, and
  deferred Fedora's, which does not.

  The generator now renders an absent key **only where the validator would accept its
  absence**, keyed to the same two conditions so one rule has two readers. A **staged** host
  shows the verb it does have with the question it answers outside the code span —
  `` `rpm-ostree status --pending-exit-77` (staged?) `` — because it cannot cheaply say how
  many packages are pending (that verb is root-only there) but can say whether a change is
  already staged, which is what the nudge runs. A **declarative** host shows `—`:
  packages-pending is not a thing NixOS knows, and the nearest question needs root and
  lists derivations. Anywhere else a missing verb is still `exit 2`, which is what keeps
  the gate honest for the eight mutable declarations.

  The cell builder now compares **rendered** strings rather than raw values when collapsing
  a multi-label column to one — the old code rebuilt the code span from a raw value plus
  whatever placeholder the last loop pass left behind, which is wrong the moment one
  declaration renders something that is not a code span.

  Pinned by four arms in the parity suite (the staged tail, the bare dash, neither
  relaxation → 2 naming the column _and_ its label, and that `declarative` excuses the
  count verb and nothing else) over a fixture fleet that grew `dotfiles-NixOS` and the two
  relaxed declarations. The pre-existing "a declaration missing a verb is a structural
  failure" assertion is the load-bearing one and is untouched: widening the relaxation to
  any absent key fails it, plus two of the four new arms.

  `PKG_COLUMNS` is deliberately unchanged — `dotfiles-NixOS` ships no `install/packages.txt`
  (`nix/home.nix` owns the package set), so the packages table, its 8-field row assertion
  and §9p's five-repo `TOOLS_OPTIN` list are all untouched. Footnote ³⁵ is now scoped to the
  Workstation half, since the atomic edition genuinely does have a standalone index refresh.
  (`scripts/gen-porting-matrix.sh`, `PORTING-MATRIX.md`,
  `scripts/test/41-gen-matrix-parity.sh`)

- **`dotfiles-NixOS` is the fleet's tenth Core-vendoring repo** (runbook step 5 of
  `NON-MUTABLE-HOST-PROPOSAL.md` §4.6, #1051). NixOS is the one non-mutable target that
  could not be a variant of an existing repo — R4 measured it as _"no package list in
  Fedora's format, no `dnf`-shaped verbs, and a different owner for packages and the shell
  declaration"_ — so `scripts/os-repos.txt` grows by one and every register that counts the
  fleet grows with it.

  **The boundary the new repo ships is R3's measurement, not a preference.**
  `nix/` owns packages, `PATH`, tpm and the login-shell declaration; the bootstrap driver
  owns every link and the zsh entry, and `home.nix` declares no `home.file` and no
  `programs.zsh`. The driver relinks whatever home-manager links, silently and without a
  backup (a differing symlink is a relink, not a foreign file); home-manager tolerates that
  for every path whose content matches and refuses to activate **at all** over the one whose
  bytes differ — `$ZDOTDIR/.zshrc`, where `-b` cannot help because it backs up only a
  _regular_ foreign file, never a foreign symlink. One file, total deadlock. The repo's
  `blib_set_login_shell` arm prints `users.users.<name>.shell = pkgs.zsh;` instead of running
  `chsh`, because a hand-set login shell is exactly the state `nixos-rebuild switch` does not
  reproduce — the repo's own arm, not a lib change.

  Core's side is the registration and the sweep it forces: the §5f helper ledger gains
  `dotfiles-NixOS` on **all nine** rows (§5f credits the whole `blib_main` contract to a
  driver adopter, so a partial ledger is `advanced` → fail, once per missed row), §9m's
  fan-out count moves 32 tracked claims from nine to ten, and `assets/hero-repos.txt` gains
  its row — with the tape rendered and the **gif deliberately pending**, which §9k weighs as
  a skip rather than a red.
  (`scripts/os-repos.txt`, `scripts/audit/40-fleet-registers.sh`, `scripts/lib/common.sh`,
  `assets/hero-repos.txt`, `ARCHITECTURE.md`, `CLAUDE.md`, `PORTABILITY.md`,
  `PORTING-MATRIX.md`, `RELEASE-STRATEGY.md`, `RELEASE-RUNBOOK.md`, `VENDORING.md`,
  `SECURITY.md`, `README.md`, `core.vendor`)

- **`scripts/fleet-protection.sh`'s `REPOS` array is now gated against `scripts/os-repos.txt`**
  — the second fleet list, and the one nothing compared. #669 deleted three hardcoded
  fallback arrays precisely so a registered repo could not vanish from a gate;
  `fleet-protection.sh` kept one for a real reason (it also audits `dotfiles-core`, and asks
  GitHub rather than the disk), and nothing checked it. Verified while adding the tenth repo:
  no audit fragment, no test fragment and no workflow referenced it. The failure mode is the
  quiet one — a repo missing from the array is not a red gate, it is branch protection nobody
  is auditing on a repo that looks covered because every other register lists it. The new
  assertion is **bidirectional**, unlike the §5f ledger's own integrity check (which catches a
  typo but not an omission — and an omission is what the next `os-repos.txt +1` produces).
  (`scripts/test/90-policy-gates.sh`, `scripts/fleet-protection.sh`)

### Fixed

- **`new-os-repo.sh` stamped the annotated TAG OBJECT as vendoring provenance, not the
  peeled commit** (#1065). Its default `CORE_BRANCH` is `refs/tags/v7`, and it resolved
  that with `git ls-remote <remote> <ref> | awk 'NR==1'` — which for an annotated tag
  returns the tag object. Not "the first of two lines": asked plainly, that is the _only_
  line there is, so the peeled ref has to be requested explicitly. Measured at v7.8.0 —
  `refs/tags/v7` → `a96cf64c58b5` (a tag object), `refs/tags/v7^{}` → `a4907d555d9f` (the
  commit every `core.lock` in the fleet records). Every scaffolded repo therefore committed
  `chore(core): vendor Core at <tag object>`, contradicting the rule `ARCHITECTURE.md` and
  `VENDORING.md` both state outright and the block's own comment ("the provenance must name
  one commit").

  **The tree was never wrong** — `core_vendor_materialize` hands the SHA to `git read-tree`,
  which peels — so this was a false claim rather than a broken vendor. Confirmed on the
  repo that found it: `dotfiles-NixOS`'s `core/` tree is `760df33cf00e`, byte-identical to
  `dotfiles-Alpine`'s at v7.8.0.

  **The same read was in `sync-core.sh`, one step from `core.lock`.** It defaults to a
  branch and the fan-out passes a SHA, so no live path reached it — but that script's own
  usage text says _"pass a released tag"_, and there the tag object would have been written
  into `core.lock` as `core_sha`, where all ten siblings record the commit. Both callers now
  go through one resolver, `core_vendor_remote_commit` in `scripts/lib/core-vendor.sh`
  (Core-only, already sourced by both), which asks for the bare **and** peeled ref in one
  network call and prefers the peeled one **by shape rather than by position**.

  Deliberately **not** changed: `tag-release.sh`'s read of `refs/tags/$MAJOR`. That one
  wants the raw ref value, because `--force-with-lease` compares the _ref's_ value — which
  for an annotated tag _is_ the tag object — and it peels separately for its ancestry
  check. Peeling there would break the lease.

  Pinned by six assertions against a local fixture remote with a real annotated tag (no
  network): the peel, the object type, the lightweight-tag and branch cases, and that a bare
  SHA stays **unresolvable** so the fan-out's local `rev-parse` fallback is untouched. The
  fixture asserts its own premise first — that the tag object and the commit actually differ
  — because the whole test would pass vacuously on a lightweight tag.
  (`scripts/lib/core-vendor.sh`, `scripts/new-os-repo.sh`, `scripts/sync-core.sh`,
  `scripts/test/32-sync-core.sh`)

## [v7.8.0] - 2026-09-15

### Changed

- **`PORTING-MATRIX.md`'s openSUSE column renders the transactional edition** (runbook step
  4 of `NON-MUTABLE-HOST-PROPOSAL.md` §4.6, dotgibson/dotfiles-openSUSE#191 / #195).
  `scripts/gen-porting-matrix.sh`'s registry names the third declaration,
  `Transactional=os/opensuse.microos.capabilities`, in the Leap idiom, so the commands
  table's upgrade / install / remove cells now carry `Transactional: sudo
  transactional-update dup` / `-n pkg in` / `-n pkg rm` beside the two zypper flavours;
  every other cell is unchanged (the transactional edition is a Tumbleweed base and reads
  its archive). Registry order is render order, and the section comment says so. The
  Fedora atomic column follows once dotgibson/dotfiles-Fedora#189 lands. The generator's
  fixture fleet carries the third declaration too, so the parity suite pins a
  three-label cell beside the one-value cell.
  (`scripts/gen-porting-matrix.sh`, `PORTING-MATRIX.md`, `scripts/test/41-gen-matrix-parity.sh`)

## [v7.7.0] - 2026-09-15

### Added

- **`bootstrap-test.yml` learns the staged host: the `provisioner:` input, the sweep's
  VM-only skip, the register's `real-bootstrap` gate, and the scaffold's stamps** (#1050,
  runbook step 2 of `NON-MUTABLE-HOST-PROPOSAL.md` §4.6). A container is not the host
  (no `/run/ostree-booted`, a writable `/usr`), so a variant repo's stubbed provision walked
  its mutable branch and never reached the staging path (R6, measured). `provisioner:
  atomic|transactional` (empty = mutable, unchanged) exports `BOOTSTRAP_PROVISIONER` into
  the provision-stub run, shims `rpm-ostree bootc transactional-update snapper btrfs`,
  makes the `rpm` shim answer `-q` with 1 so the variant's base-image filter keeps its
  names, and fails the leg unless the run prints the staged closing line ("reboot to
  apply"). `scripts/fleet-bootstrap-matrix.py` skips such a caller (the unstubbed sweep
  would install down the mutable branch) and names it VM-only via a `::notice::` that
  `real-bootstrap.yml` writes into the run summary. `scripts/fleet-coverage.sh` grows a
  derived `real-bootstrap` gate: `sweep` for a mutable caller, `real-bootstrap none <why>`
  required of a provisioner-only repo, and a caller-less repo inherits its `bootstrap-test`
  declaration. `scripts/new-os-repo.sh` stamps `PROVISIONER` / `PKG_APPLY` /
  `PKG_APPLY_PENDING` as commented examples into the capability stub and shows the staging
  shape of a provision hook in the starter bootstrap. (`scripts/test/{33-bootstrap-matrix,
  35-new-os-repo,56-fleet-vocabulary}.sh`)

## [v7.6.0] - 2026-09-15

### Added

- **`up`, the shell-start nudge, the maint runner and `core-doctor` learn the staged
  host** (#1049, runbook step 1 of `NON-MUTABLE-HOST-PROPOSAL.md` §4.6). Three optional
  declaration keys — `PROVISIONER`, `PKG_APPLY`, `PKG_APPLY_PENDING` (+ `_EXIT`) — are read
  for the first time, and every branch is on a key the nine mutable repos never declare, so
  their behaviour and their nudge cache are byte-identical. On an atomic (bootc) or
  transactional (MicroOS) host: `up` closes with `staged — reboot to apply: <PKG_APPLY>`
  (the verb is printed, never run), `up -n` with no count verb says the host stages instead
  of "nothing to upgrade", and the nudge prints **`󰚰 update staged — reboot to apply`** in
  place of a count. The STAGED question is asked by the refresh (`_pkgup_refresh`, and
  the maint runner after its optional apply) and cached as lines 3–4 of `pkg-updates`
  (`staged`/`idle` + the kernel's boot id), so the per-shell path stays fork-free and a
  reboot silences the line at the next shell. `MAINT_UNATTENDED_UPGRADE` under `atomic`
  is stage-only and logs `staged — reboot to apply (never run by this runner)`;
  `declarative` (NixOS) is treated as mutable, `_pkgup_mgr` answers the `PROVISIONER`
  token when no manager is on PATH (so `up` no longer refuses NixOS), and `core-doctor`'s
  install hint says "reboot to use" over a staged change and "add it to `home.packages` /
  `environment.systemPackages`" on a declarative host. Unit tests are the R5 shim replay:
  the research declarations' package half against stub managers answering with the
  measured exit statuses. (`zsh/02-capabilities.zsh` `_core_cap_staged`,
  `zsh/60-update.zsh`, `maint/dotfiles-maint.sh`, `zsh/30-functions.zsh`,
  `scripts/test/{65-functions,73-maint-runner,74-zsh-helpers}.sh`)

- **The R4 harness for the non-mutable host research, and its answer** (#1004). Two
  prototype patches under `scripts/research/nonmutable/r4/` give `dotfiles-Fedora` and
  `dotfiles-openSUSE` an atomic / transactional _variant_ (a host marker, a second
  declaration relinked by `bootstrap_wire_pre_loader`, a staging path, a "reboot to
  apply" line); `scripts/research/nonmutable-variant.sh` applies and runs them on the
  booted guests, and `research-nonmutable-vm.yml`'s `r4=true` input drives the run,
  reboot and re-run. Measured verdict, in `NON-MUTABLE-HOST-PROPOSAL.md` §5: **variant**
  (118 + 18 and 65 + 10 lines; NixOS stays a new repo). The `trailing-whitespace`
  pre-commit hook now leaves `*.patch` alone — a blank diff context line is a lone space.

- **`PKG_APPLY_PENDING` / `PKG_APPLY_PENDING_EXIT`, the staged-change probe, for the
  non-mutable host research** (R5 of `NON-MUTABLE-HOST-PROPOSAL.md`, #1004).
  `scripts/check-capabilities.sh` accepts the pair (optional; the probe needs `PKG_APPLY`
  beside it, the exit is 1–255) and lets `PKG_COUNT_PENDING` be absent when it is
  declared — on an atomic host the "is there something newer" verb is root-only
  (measured), so the nudge reports the staged state instead. Read by no consumer yet; the
  bootc and MicroOS prototypes under `scripts/research/nonmutable/` declare it. Also the R5
  harness (`scripts/research/nonmutable-r5.sh`, the VM legs' `r5=true`, a registry-backed
  bootc origin). (`scripts/check-capabilities.sh`, `examples/os.capabilities.example`,
  `scripts/test/55-capabilities.sh`)

- **The R6 harness for the non-mutable host research, and the research phase's close**
  (#1004). `scripts/research/nonmutable-r6.sh` runs the reusable `bootstrap-test.yml` legs'
  own recipes inside the three container images against the R4 variant, plus the same
  stubbed run with `BOOTSTRAP_PROVISIONER` forced — the seam the variant patches carry so
  a container can reach the staging path at all; `research-nonmutable.yml`'s `r6=true`
  drives it. `NON-MUTABLE-HOST-PROPOSAL.md` §5 carries the CI matrix a target is born
  with, the VM-only gap list, and the note that every exit criterion is met — the next
  step is the §4 rewrite to PROPOSED.

- **`NON-MUTABLE-HOST-PROPOSAL.md` is PROPOSED** (#1004). §4 is now the proposal — a
  minor, not a major: the six optional capability keys (shipped), three consumer changes
  (`up` and the nudge, the maint runner, `core-doctor`), one CI input
  (`bootstrap-test.yml` `provisioner:`), atomic / transactional variants for
  `dotfiles-Fedora` and `dotfiles-openSUSE`, and a `dotfiles-NixOS` repo with the
  home-manager boundary written down — with §4.6 as the per-repo runbook and every line
  citing §5's measurements. The former §6 and §8 stay as the record of what a major would
  have cost and what was asked.

### Fixed

- **The `~/.zshrc` loader's backup is counted** (#1026). `blib_write_zshrc_loader` backed up
  a pre-existing real `~/.zshrc` and warned about it, but never bumped `BLIB_BACKED`, so the
  closing tally said `0 backed up` on the same run that printed the backup (the R3 research
  run on Fedora exposed it). Every backup site now counts; the bootstrap-lib suite asserts it.

## [v7.5.0] - 2026-09-14

### Added

- **Four prototype `os.capabilities` keys, for the non-mutable host research** (R2 of
  `NON-MUTABLE-HOST-PROPOSAL.md`, #1004). `scripts/check-capabilities.sh` accepts
  `PROVISIONER` (`mutable` | `atomic` | `transactional` | `declarative`), `PKG_APPLY` (the
  verb that makes a staged change live), and `PKG_PENDING_EXIT_SOME` / `_NONE` (a count
  verb whose answer is its exit status) — all optional, all read by no consumer yet — and
  lets `PKG_COUNT_PENDING` be absent under `PROVISIONER=declarative`. Every existing
  declaration validates unchanged. The three prototype declarations they were written for
  live under `scripts/research/nonmutable/`, each validated, with the R2 verdict
  (additive — no schema version, no re-author) in their README. (`scripts/check-capabilities.sh`,
  `examples/os.capabilities.example`, `scripts/test/55-capabilities.sh`)
- **The R3 harness for the non-mutable host research, and its answer** (#1004).
  `scripts/research/nonmutable/home.nix` is a home-manager module that tries to own
  everything the driver wires as out-of-store links into the vendored `core/`;
  `scripts/research/nonmutable-home-manager.sh` applies it, runs the repo's
  `bootstrap.sh --links-only` over the result, switches again and records who owns each
  path. `research-nonmutable.yml` gained a `homemanager` leg (Fedora 42, standalone) and
  `research-nonmutable-vm.yml`'s NixOS guest applies it as a NixOS module. Measured
  verdict, in `NON-MUTABLE-HOST-PROPOSAL.md` §5: **coexist** — the driver overwrites
  home-manager's links silently, home-manager tolerates the driver's links but refuses to
  activate over its zsh entry, so a fleet `home.nix` owns packages, the shell declaration,
  tpm and PATH and declares no files.

### Fixed

- **The sudo keepalive no longer dies on a non-interactive run whose sudo needs no
  password** (#1018, found by the non-mutable-host research on a booted bootc guest). The
  prime was a bare `sudo -v`, and sudoers' default `verifypw=all` makes `-v` prompt unless
  _every_ rule matching the user is NOPASSWD — Fedora's stock wheel rule beside a NOPASSWD
  drop-in is one passworded rule too many, so a run with no terminal ended "authentication
  failed" on a host where every command was passwordless. `blib_sudo_keepalive_start` now
  primes by how the run can answer: `-v` at a terminal; `-A -v` when `SUDO_ASKPASS` is set;
  otherwise `-n -v`, then `-n true`, then a warning that names the actual problem (no
  terminal and a password required) before the driver's "cannot provision packages" line.
  (`lib/bootstrap-lib.sh`, `scripts/test/85-escalation.sh`)
