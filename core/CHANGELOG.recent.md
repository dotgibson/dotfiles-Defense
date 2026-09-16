# Changelog — recent releases

GENERATED FILE — do not edit by hand. `scripts/gen-changelog-recent.sh` rewrites it
wholesale, `scripts/release.sh` runs that generator on every release, and
`scripts/audit-core.sh` §9e fails when this file is not byte-identical to a fresh
render. To fix a conflict or a stray edit, re-run the generator — never patch it.

The last 8 released sections of `CHANGELOG.md` (v7.9.0 … v7.4.2), vendored into every OS repo's
`core/` by `core.vendor` so `core whatsnew` can answer offline. The full changelog is
repo-meta and stays upstream:
[dotgibson/dotfiles-core/CHANGELOG.md](https://github.com/dotgibson/dotfiles-core/blob/main/CHANGELOG.md).

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

## [v7.4.4] - 2026-09-13

### Changed

- **`new-os-repo.sh` scaffolds the starter bootstrap in the driver form** (#999). A repo
  born from the generator declares what it is (`BOOTSTRAP_NAME`, `BOOTSTRAP_OS`,
  `BOOTSTRAP_LOGIN_SHELL=0` — a starter must not `chsh`), links its ZDOTDIR entry pair in
  `bootstrap_wire_post_loader`, and hands over to `blib_main` — the shape all eight fleet
  repos on the driver have (#986) rather than the one they just left. The starter's hand
  copy of the link step (and of `blib_link`'s backup suffix, "keep the two in step") goes,
  and so does its `zsh/zshrc.zsh` copy of the loader: the driver writes the managed
  `~/.zshrc` and seeds `$ZDOTDIR/.zshrc` as a symlink to it, one definition for the fleet.
  The generated `test/check-links.sh` asserts that shape, stands a placeholder in for the
  tpm clone (the one network fetch in the wiring; the suite tests links, not GitHub), and
  keeps its three idempotency witnesses — which now hold the driver to the same bar.
  (`scripts/new-os-repo.sh`, `scripts/test/35-new-os-repo.sh`)

### Fixed

- **A second bootstrap run invokes no mutating command** (#999, found by holding the
  driver to the scaffold's idempotency witness). `blib_link_core` ran `chmod +x` on Core's
  tmux scripts and `bin/` tools and `mkdir -p`/`chmod 700` on `~/.ssh` on EVERY run, and
  `blib_install_core_guard` rewrote an identical pre-commit hook every time — no-ops on
  disk, but a witness that logs every `mkdir`/`chmod` reads each as a change. Every one
  now asks first (`_blib_ensure_exec`, `_blib_private_dir`, a byte compare against the
  hook text held in `_blib_core_guard_hook`) and the hook's bytes are unchanged.
  (`lib/bootstrap-lib.sh`)

## [v7.4.3] - 2026-09-13

### Changed

- **Alpine is on the bootstrap driver, MacBook is exempt by design — the `blib_main` row
  closes at 8/9 + 1 exempt** (closes #986; dotgibson/dotfiles-Alpine#194, on v7.4.2). Alpine
  declares doas-first (`BOOTSTRAP_SU_PREFER=doas`) and the driver resolves with it; its
  `~/.zshenv` ZDOTDIR shim takes the post-loader slot, and its root-probe test now pins the
  declaration plus the hand-over instead of a literal `blib_resolve_su` call. MacBook's
  `--json`/`--uninstall`/`--quiet` surface and its own reporting channel are a consumed
  contract the driver does not model, so §5f records the exemption with that reason
  rather than a gap — the assertion is that no bootstrap in the fleet is on the pre-driver
  shape by accident. Eight repos run on the driver; the starter that `new-os-repo.sh`
  writes is the one bootstrap still in the old shape (#999).
  (`scripts/audit/40-fleet-registers.sh`)

- **Arch is on the bootstrap driver — the `blib_main` row reads 7/9** (#986;
  dotgibson/dotfiles-Arch#174, on v7.4.2). The rolling-release repo declares its
  exit-1-on-any-miss contract (`BOOTSTRAP_STRICT_DEFAULT=1`) instead of hand-rolling it;
  the Arch check is `bootstrap_guard`, the pacman phase is `bootstrap_provision` with the
  body unchanged, the dry-run preview is `bootstrap_check`, and its `-E` ERR trap stays,
  stepping aside for the driver's own `return` verdicts. 446 → 421 lines.
  (`scripts/audit/40-fleet-registers.sh`)

- **Offense and Gentoo are on the bootstrap driver — the `blib_main` row reads 6/9** (#986;
  dotgibson/dotfiles-Offense#328, dotgibson/dotfiles-Gentoo#187, both on v7.4.2). The two
  lazy-escalation repos: Offense declares `BOOTSTRAP_ROLE=offensive`, no login shell and
  `BOOTSTRAP_SU=lazy`, so only `--install` escalates, inside its own hook; Gentoo declares
  lazy too and keeps its `--user` fallback — the guard resolves an escalator and downgrades
  to user mode when there is none, the provision hook primes the keepalive itself, and
  `provision_user` folds into `bootstrap_provision`. Both keep their package bodies verbatim.
  619 + 1316 → 551 + 1236 lines. (`scripts/audit/40-fleet-registers.sh`)

## [v7.4.2] - 2026-09-13

### Fixed

- **openSUSE is recorded on the `blib_install_core_guard` row — the row closes at 9/9** (#986;
  follow-up to #992). A `blib_main` caller is credited with the whole helper contract, and the
  driver installs the Core guard openSUSE's own bootstrap never had, so §5f read the repo as
  `advanced` on that row the moment dotgibson/dotfiles-openSUSE#186 merged — the state the
  v7.4.1 fan-out audit meets. Same shape as Defense in #988. (`scripts/audit/40-fleet-registers.sh`)
