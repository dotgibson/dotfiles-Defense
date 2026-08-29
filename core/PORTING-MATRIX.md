# Distro Porting Matrix

How to stamp `dotfiles-Arch`, `dotfiles-openSUSE`, `dotfiles-Alpine`,
`dotfiles-Gentoo`, and `dotfiles-Debian` from the `dotfiles-Fedora` template. The structure is identical
every time — only three things change per distro: **package manager commands**,
**package names**, and **distro quirks**. Core never changes (it's vendored).
Offense (Kali) and macOS appear in the reference tables below for convenience, but
they're their own lineages — built directly, **not** stamped from this template (see
_Repo status_ at the bottom).

## Per-repo recipe

1. `cp -r dotfiles-Fedora dotfiles-<Distro>`
2. Rename `os/fedora.zsh` → `os/<distro>.zsh`; swap clipboard + pkg-manager aliases.
3. Replace `install/packages.txt` with that distro's names (table below).
4. In `bootstrap.sh`: swap the `dnf` block for the distro's installer and the
   `/etc/os-release` guard string.
5. Re-vendor Core and stamp `core.lock`, from a **Core** checkout:
   `git checkout v5 && CORE_BRANCH="$(git rev-parse v5^{commit})" ./scripts/sync-core.sh dotfiles-<Distro>`
   — a **released tag, never `main`**, and the **peeled commit**, never `refs/tags/v5`
   (the tags are annotated; see `RELEASE-STRATEGY.md` §4). Step 1 already copied Fedora's `core/` across, so there is no
   `git subtree add` to run here (it would fail: _prefix 'core' already exists_). That
   one-time add is only for a repo with no `core/` at all — `scripts/new-os-repo.sh`
   does it for greenfield repos. Skip this step and `core-integrity` reports the
   inherited tree against Fedora's lock.
6. Update the README's "specifics" section to that distro's quirks.

## Package-manager commands

**This table is the transcription source for `os/<os>.capabilities`** (#667) — every cell
below becomes a `PKG_*` value in some repo's declaration, so a wrong cell here is a wrong
verb on a real box. **That transcription has now happened**: seven repos declare (the two
Role repos have no OS band and inherit the OS layer's table), so this is no longer only a
reference — it is the upstream of live files, and `audit-core.sh` §9c holds every one of
them to the schema. Two cells could not be transcribed flat and are worth knowing about:
openSUSE's `dup`-vs-`up` split and Debian's Kali lane each became a **second declaration
file** their repo's `bootstrap.sh` relinks, because a declaration is data and cannot probe. It gained its **macOS and Fedora columns** in #664: they had been
missing since the table was written, even though `dotfiles-MacBook` is the reference
implementation and `dotfiles-Fedora` is the template the other Linux repos stamp from —
so the two most-copied repos had nothing to copy.

The **count-pending** row is what `up`'s once-a-day nudge runs, and it is the most
divergent of the lot — the one Core hardcoded worst. It must be **non-root and must not
mutate the system**, which is why Arch counts with `checkupdates` (a user-space copy of
the sync DB, never the real one) rather than `-Sy` — and why Gentoo, which cannot answer
it cheaply at all, pays for a real resolve rather than the fast wrong answer.

| Action        | macOS (brew)              | Fedora (dnf)                    | Arch                     | openSUSE                                         | Alpine                    | Gentoo                          | Kali (apt)                   | Debian/Ubuntu (apt)          |
| ------------- | ------------------------- | ------------------------------- | ------------------------ | ------------------------------------------------ | ------------------------- | ------------------------------- | ---------------------------- | ---------------------------- |
| refresh       | `brew update`             | `dnf check-update`³⁵            | `sudo pacman -Sy`²³      | `sudo zypper refresh`                            | `doas apk update`         | `sudo emerge --sync`            | `sudo apt-get update`        | `sudo apt-get update`        |
| upgrade       | `brew upgrade`            | `sudo dnf upgrade --refresh`    | `sudo pacman -Syu`       | Leap: `zypper up` · **Tumbleweed: `zypper dup`** | `doas apk upgrade`        | `sudo emerge -auvDN @world`     | `sudo apt-get full-upgrade`  | `sudo apt-get full-upgrade`  |
| count-pending | `brew outdated --quiet`³⁶ | `dnf -q --refresh check-update` | `checkupdates`²³         | `zypper -q list-updates`                         | `apk list -u`             | `emerge -puDN @world`³⁷         | `apt-get -s upgrade`         | `apt-get -s upgrade`         |
| install       | `brew install <pkg>`      | `sudo dnf install <pkg>`        | `sudo pacman -S <pkg>`   | `sudo zypper in <pkg>`                           | `doas apk add <pkg>`      | `sudo emerge <atom>`            | `sudo apt-get install <pkg>` | `sudo apt-get install <pkg>` |
| remove        | `brew uninstall <pkg>`    | `sudo dnf remove <pkg>`         | `sudo pacman -Rns <pkg>` | `sudo zypper rm <pkg>`                           | `doas apk del <pkg>`      | `sudo emerge --depclean <atom>` | `sudo apt-get remove <pkg>`  | `sudo apt-get remove <pkg>`  |
| search        | `brew search <term>`      | `dnf search <term>`             | `pacman -Ss <term>`      | `zypper se <term>`                               | `apk search <term>`       | `emerge -s <term>`              | `apt-cache search <term>`    | `apt-cache search <term>`    |
| owns-file     | `brew which-formula`³⁸    | `dnf provides <path>`           | `pacman -Qo <path>`      | `zypper se --provides <f>`                       | `apk info --who-owns <f>` | `equery belongs <path>`         | `dpkg -S <path>`             | `dpkg -S <path>`             |

## Package names (modern CLI stack)

> **The Kali column changed owner.** It described `dotfiles-Offense` while that repo carried
> the Kali OS band. It no longer does — `dotfiles-Offense` shed its OS-native layer entirely,
> and the lane moved to `dotfiles-Debian`'s `only:kali` / `skip:kali` tiers. The seven cells
> the move demonstrably falsified are corrected (`lazygit`, `starship`, `atuin` in the first
> round; `git-delta`, `difftastic`, `mise`, `uv` in the second), and so are the two footnotes
> that asserted "Kali installs nothing" — but the column as a whole has
> **not** been re-derived cell-by-cell against the new owner. Treat unmarked Kali cells as
> inherited rather than verified until `/os-package-availability` has run against
> `dotfiles-Debian`'s kali tier. (²¹ᵃ marks this caveat, not a per-cell claim.)
>
> **The second round is what this caveat predicted, and it arrived by the predicted route.**
> All four were resolved against `dotfiles-Debian` rather than inherited: `git-delta` is
> `# skip:kali` because it is in apt on noble and trixie and absent from kali-rolling;
> `difftastic` never made the `only:kali` tier at all; and `mise` and `uv` are fetched by
> `verified_install` on every target, so their apt availability — `uv` genuinely _is_ in
> kali-rolling — was never what the cell should have recorded. **A cell here documents what
> this fleet installs, not what the archive contains.** That distinction is what made `uv`
> wrong while looking right, and it is the one to apply to the cells still unmarked.

| Tool             | Arch              | openSUSE      | Alpine            | Gentoo (atom)              | Kali (apt)²¹ᵃ     | Debian/Ubuntu |
| ---------------- | ----------------- | ------------- | ----------------- | -------------------------- | ----------------- | ------------- |
| eza              | `eza`             | `eza`         | `eza`             | `sys-apps/eza`             | `eza`             | `eza`         |
| bat              | `bat`             | `bat`         | `bat`             | `sys-apps/bat`             | `bat`⁴            | `bat`⁴        |
| fd               | `fd`              | `fd`          | `fd`              | `sys-apps/fd`              | `fd-find`⁴        | `fd-find`⁴    |
| ripgrep          | `ripgrep`         | `ripgrep`     | `ripgrep`         | `sys-apps/ripgrep`         | `ripgrep`         | `ripgrep`     |
| zoxide           | `zoxide`          | `zoxide`      | `zoxide`          | `app-shells/zoxide`        | `zoxide`          | `zoxide`      |
| fzf              | `fzf`             | `fzf`         | `fzf`             | `app-shells/fzf`           | `fzf`             | `fzf`         |
| git-delta        | `git-delta`       | `git-delta`   | `delta`           | `dev-util/git-delta`       | asset²⁸           | `git-delta`   |
| btop             | `btop`            | `btop`        | `btop`            | `sys-process/btop`         | `btop`            | `btop`        |
| tldr             | `tealdeer`        | `tealdeer`¹   | cargo³            | `app-misc/tealdeer`¹²      | `tealdeer`        | `tealdeer`    |
| neovim³³         | `neovim`          | `neovim`      | `neovim`          | `app-editors/neovim`       | `neovim`          | asset²⁸       |
| lazygit          | `lazygit`         | `lazygit`     | `lazygit`         | `dev-vcs/lazygit`¹²        | `lazygit`         | asset²⁸       |
| zsh              | `zsh`             | `zsh`         | `zsh`²            | `app-shells/zsh`           | `zsh`             | `zsh`         |
| tmux             | `tmux`            | `tmux`        | `tmux`            | `app-misc/tmux`            | `tmux`            | `tmux`        |
| starship         | `starship`        | `starship`¹⁸  | `starship`        | `app-shells/starship`      | `starship`        | asset²⁸       |
| atuin²⁰          | `atuin`           | `atuin`¹⁸     | `atuin`           | `app-shells/atuin`         | asset²⁸           | asset²⁸       |
| mise³⁰           | `mise`            | script³⁰      | script³⁰          | script³⁰                   | asset²⁸           | asset²⁸       |
| direnv³²         | `direnv`          | `direnv`      | `direnv`          | `app-shells/direnv`¹²      | `direnv`          | `direnv`      |
| yazi             | `yazi`            | `yazi`¹⁸      | `yazi`            | `app-misc/yazi`¹²          | cargo³            | —²⁹           |
| tree-sitter-cli⁵ | `tree-sitter-cli` | `tree-sitter` | `tree-sitter-cli` | `dev-util/tree-sitter-cli` | `tree-sitter-cli` | asset²⁸       |
| jq³⁴             | `jq`              | `jq`          | `jq`              | `app-misc/jq`              | `jq`              | `jq`          |
| yq⁶              | `go-yq`           | `yq`          | `yq-go`           | `app-misc/yq-go`           | `yq-go`           | go³           |
| duf              | `duf`             | `duf`         | testing¹⁴         | `sys-fs/duf`               | `duf`             | `duf`         |
| dust             | `dust`            | `dust`        | `dust`            | `sys-block/dust`           | `du-dust`⁴        | asset²⁸       |
| procs            | `procs`           | `procs`       | `procs`           | `sys-process/procs`        | `procs`           | asset²⁸       |
| viddy¹⁶          | AUR¹⁶             | `viddy`¹⁸     | `viddy`           | cargo³                     | cargo³            | —²⁹           |
| sd²²             | `sd`              | `sd`          | `sd`              | `sys-apps/sd`¹²            | `sd`              | `sd`          |
| gron             | `gron`            | `gron`        | `gron`            | go³                        | `gron`            | `gron`        |
| jnv¹⁷            | `jnv`             | cargo         | cargo³            | cargo                      | cargo             | —²⁹           |
| lnav²¹ ²⁴        | `lnav`            | `lnav`        | `lnav`            | `app-admin/lnav`²⁴         | `lnav`²⁴          | `lnav`        |
| glow             | `glow`            | `glow`        | testing¹⁴         | `app-misc/glow`¹²          | `glow`¹⁵          | charm apt     |
| gum              | `gum`             | `gum`         | `gum`             | mise³⁰                     | `gum`¹⁵           | charm apt     |
| xh               | `xh`              | `xh`          | `xh`              | `net-misc/xh`¹²            | `xh`              | asset²⁸       |
| doggo            | `doggo`           | `doggo`¹⁸     | `doggo`           | `net-dns/doggo`            | go³               | go³           |
| gping¹⁹          | `gping`           | `gping`¹⁹     | `gping`           | GURU¹⁹                     | `gping`¹⁹         | `gping`       |
| carapace         | AUR²⁷             | rpm²⁷         | `carapace`        | `app-shells/carapace`¹²    | deb²⁷             | deb²⁷         |
| op (1Password)¹³ | AUR               | vendor rpm    | vendor apk        | GURU¹²                     | vendor apt        | vendor apt    |
| hyperfine²¹      | `hyperfine`       | `hyperfine`   | `hyperfine`       | `app-benchmarks/hyperfine` | `hyperfine`       | `hyperfine`   |
| watchexec²¹ ²⁵   | `watchexec`       | `watchexec`   | `watchexec`       | cargo²⁵                    | cargo²⁵           | —²⁹           |
| shellcheck²¹     | `shellcheck`      | `ShellCheck`  | `shellcheck`      | `dev-util/shellcheck-bin`  | `shellcheck`      | `shellcheck`  |
| shfmt⁷ ²¹        | `shfmt`           | `shfmt`       | `shfmt`           | go²¹                       | `shfmt`⁷          | `shfmt`       |
| ouch²¹           | `ouch`            | `ouch`¹⁸      | testing¹⁴         | GURU¹² ²¹                  | cargo²¹           | —²⁹           |
| jujutsu (jj)⁸    | `jujutsu`         | `jujutsu`     | `jujutsu`         | `dev-vcs/jj`²¹             | cargo²¹           | —²⁹           |
| sesh⁹            | AUR⁹              | go⁹           | go⁹               | go⁹                        | go⁹               | go³           |
| difftastic¹⁰     | `difftastic`      | `difftastic`  | `difftastic`      | `dev-util/difftastic`      | asset²⁸           | asset²⁸       |
| git-absorb²¹ ²⁶  | `git-absorb`      | `git-absorb`  | `git-absorb`      | `dev-vcs/git-absorb`       | `git-absorb`      | `git-absorb`  |
| ast-grep¹¹       | `ast-grep`        | `ast-grep`¹⁸  | `ast-grep`        | cargo²¹                    | cargo²¹           | —²⁹           |
| uv³⁰             | `uv`              | `python-uv`   | `uv`              | `dev-python/uv`            | asset²⁸           | asset²⁸       |
| w3m              | `w3m`             | `w3m`         | `w3m`             | `www-client/w3m`           | `w3m`             | `w3m`         |

¹ openSUSE: in Tumbleweed main OSS as `tealdeer` (1.8.0). **Not in Leap 16.0 or 16.1** —
it shipped in 15.6, which is EOL, and the name is absent from both arches of each 16.x
`repo/oss` (checked 2026-08-21). Two ways in on Leap **16.0**: the `utilities` OBS repo,
which does build it (`.../repositories/utilities/16.0/x86_64/tealdeer-1.8.0-lp160.49.8.x86_64.rpm`)
but is a third-party channel `dotfiles-openSUSE` deliberately does not auto-add, same call as
Packman; or `cargo install --locked tealdeer`, which its `bootstrap.sh` now runs
presence-guarded. **On Leap 16.1 there is only the second** — `utilities` builds tealdeer for
**16.0 only**, its index listing `16.0/` plus three Factory flavors and no `16.1/` at all
(checked 2026-08-22, dotfiles-openSUSE#113). The retry hint in that bootstrap used to offer
the 16.0 repo unconditionally, which on a 16.1 box adds a 16.0 channel.
Guard on **`tldr`**, not `tealdeer` — the crate and the binary it installs
have different names (dotfiles-openSUSE#102).
² Alpine default shell is `ash`; you must `apk add zsh` explicitly.
³ Not packaged or stale → bootstrap.sh installs it best-effort (upstream
installer / `cargo install` / `go install` / AUR), the same pattern bootstrap
already uses on Fedora. Add `cargo`/`rust` (or a `go` toolchain) to packages.
`go install` targets land in `~/.local/bin` via `GOBIN` so they're on PATH.
**`carapace` is the one documented exception to the `go install` half of this** — that
module can never be `go install`ed, on any platform, so its cells point at ²⁷ instead.
The module path is rarely the repo URL — see ³¹ for the exact one per tool.
⁴ Debian/Kali ship these under different binary names — `bat` runs as `batcat`,
the `fd-find` package installs `fdfind`, and the `du-dust` package installs the
`dust` command. Core's `00-tools.zsh` already resolves them, so aliases and config
work unchanged. `20-aliases.zsh` additionally aliases `bat`/`fd` back to their
canonical names, so both are typeable as documented upstream, and `core-doctor`
probes the RESOLVED binary — it reports `✓` for a renamed tool rather than the `✗`
that once contradicted the `resolved` line in the same report.
⁵ nvim-treesitter (pinned to `main`) needs tree-sitter-cli ≥ 0.26.1. **Mac:**
`tree-sitter-cli` via brew — **not** `tree-sitter`, which is now lib-only.
**Fedora:** `tree-sitter-cli` via dnf (verify ≥ 0.26.1, else mise/cargo).
**Arch:** `extra` carries 0.26.9 (clears the floor).
**openSUSE:** the CLI is in the **base `tree-sitter` package** (0.26.8 on Tumbleweed,
Leap 16.1 and Leap 16.0 — clears the floor); what got split off there is the shared
_library_, as `tree-sitter0_26`. There is **no** `tree-sitter-cli` package on openSUSE, and
searching for that name is precisely why `dotfiles-openSUSE` carried this as `cargo³` and
cargo-built the CLI on every box until dotfiles-openSUSE#113. **Note the inversion against
the Mac line two above** — brew's `tree-sitter` is the lib-only formula and `tree-sitter-cli`
is the one you want; openSUSE is the exact opposite, so the same name means opposite things
on the two platforms and neither instinct transfers.
**Gentoo:** `dev-util/tree-sitter-cli` 0.26.11 is **stable on amd64** and clears the floor,
so it takes no `package.accept_keywords` line and no cargo build — `dotfiles-Gentoo`
cargo-built the crate until 2026-08-23, when the atom was found to have been packaged and
stabilised underneath it (dotfiles-Gentoo#116). Between this, the openSUSE paragraph above
(dotfiles-openSUSE#113) and the Alpine one below (dotfiles-Alpine#122), **three distros in
this one footnote moved in a fortnight** — re-query this row on every stamp.
Where unpackaged: `mise use -g tree-sitter` or `cargo install tree-sitter-cli`.
**Alpine:** the `community` package **is** the musl build on every branch, but it clears
the floor on only **two of five** — v3.24 (`0.26.7-r0`) and edge (`0.26.7-r1`). v3.21
carries `0.24.4-r0` and v3.22/v3.23 carry `0.25.10-r0`, all three **below** it. This note
used to quote 0.26.7 unqualified, which is the v3.24/edge version read as fleet-wide.
Prefer the package on the two branches where it clears; on the other three
`dotfiles-Alpine`'s `bootstrap.sh` supplies a conforming build via cargo, and that guard is
**version**-checked rather than presence-checked — a presence guard sees apk's 0.25.10,
skips the build, and leaves the box below the floor in silence (dotfiles-Alpine#122).
`~/.cargo/bin` is prepended ahead of `/usr/bin` by `zsh/00-tools.zsh`, so the cargo build
genuinely shadows the older apk one.
⁶ yq: this matrix targets **mikefarah's Go `yq`** (the jq-for-YAML). Distros also
ship **Python `yq`** (kislyuk) under the same `yq` name; if you land the wrong
one, install the Go build via `mise use -g yq` or the upstream release binary.
**openSUSE is the exception to that warning, not an instance of it.** The main OSS `yq`
**is** the mikefarah Go build — 4.53.3 on Tumbleweed and on Leap 16.1/16.0 (`bp161`/`bp160`)
— and kislyuk's Python tool ships under its own name, `python313-yq` / `python314-yq`, so
the collision cannot happen there. This footnote used to say the reverse, and
`dotfiles-openSUSE` go-installed the Go build on that basis; as of
dotfiles-openSUSE#113 it packages `yq` and keeps the go-install as a presence-guarded
fallback (its guard matches the mikefarah string in `yq --version`, so the packaged build
satisfies it and the block no-ops).
⁷ shfmt: not always in stable apt (Debian/Kali), and **not packaged on Gentoo** —
absent from `::gentoo` and from GURU (third-party overlays carry it as
`dev-util/shfmt`; there is no `dev-go/shfmt` atom), so Gentoo takes the `go²¹`
path — and there, unusually for a ²¹ row, `bootstrap.sh` **does** install it:
`dotfiles-Gentoo` go-installs shfmt unconditionally alongside gron and sesh,
because nvim's conform formatter is wired to it. If the package is missing,
`mise use -g shfmt` or `go install mvdan.cc/sh/v3/cmd/shfmt@latest`. (These mid-2026 rows are
best-effort — verify the exact package on first stamp of each distro.)
⁸ jujutsu (jj): OPT-IN, additive git companion — never replaces git, so a box
without it just skips the HAVE_JJ-gated aliases. Packaged on Arch (`jujutsu`),
openSUSE (`jujutsu`), Homebrew (`jj`), nixpkgs (`jujutsu`) and Alpine
(`community` — a native musl build), and **on Gentoo as `dev-vcs/jj`** — mind the
name, the atom is `jj`; `dev-vcs/jujutsu` has never existed and is the trap this
row used to fall into. Added 2025-12-04 (`dev-vcs/jj: new package, add 0.36.0`,
EAPI 8, maintainer `chutzpah@gentoo.org`); every ebuild is `~amd64` with no stable
version, so it needs a `package.accept_keywords` line. **Not** in stable
Debian/Kali apt and **not on Fedora** — `dnf` has no `jujutsu`, `jj` or `jj-cli`
on F43/F44/rawhide and no retired build to point at, unlike `sd`/`gron` which
were dropped — so those two take `cargo install --locked jj-cli`, the same cargo
pattern as yazi/ouch. The crate is **`jj-cli`**, not `jujutsu`: the `jujutsu`
crate is a stub pinned at 0.7.2 whose own description reads "You don't want this
crate - you want the `jj-cli` crate", so `cargo install jujutsu` lands a redirect
rather than the VCS — a second reason to spell it `jj` on both packaging paths.
As an opt-in tool it is carried in exactly one OS repo's `packages.txt` —
`dotfiles-Alpine` (package `jujutsu`, binary `jj`). Arch lists it only as a
commented opt-in you run by hand. **Gentoo installs it, but not from
`packages.txt`**: that file is the UNCONDITIONAL emerge, and an atom there would
land on a `--no-extras` run, so `bootstrap.sh` emerges `dev-vcs/jj` from its
opt-in extras block instead (`scripts/check-packages.sh` check 7 gates the
hard-coded atom). Read the absence from Gentoo's list as a deliberate placement,
not a decline. The config (`jujutsu/config.toml`) is inert without the binary.
⁹ sesh: smart tmux session manager that Core already drives from the `Ctrl-G`
shell widget (`35-fzf.zsh`) and the `prefix + f` tmux popup (`tmux-sesh.sh`); both
degrade to a `find`+`fzf` sessionizer when it's absent. `core-doctor` already
reports `sesh` via its own `command -v` probe (it does not read `HAVE_SESH`);
`00-tools.zsh` now also sets `HAVE_SESH` for parity with the other detected tools.
Packaged in the AUR as `sesh-bin` (which
`provides`/`conflicts` `sesh`, so `paru -S sesh` still resolves — there is no
AUR package under the bare name), Homebrew
(`sesh`), and nixpkgs (`sesh`); **not** in Arch-official, openSUSE, Alpine,
Gentoo, Fedora, or Debian/Kali apt — so most of the fleet uses
`go install github.com/joshmedeski/sesh/v2@latest` (note the **v2** module path),
the same build path as starship/yazi/atuin where unpackaged. `go` is already a
pinned mise runtime, so the install works everywhere; `mise use -g go` first on a
bare box. The seeded `sesh/sesh.toml.example` config is inert without the binary.
¹⁰ difftastic (`difft`): OPT-IN structural/AST diff — a **companion to delta, not a
replacement**. delta stays the default `git diff` pager; difft is wired as an on-demand
git difftool (`git dft`, and the `gdft` shell alias — see `git/gitconfig`), never as a
`GIT_EXTERNAL_DIFF`/pager override, so it never shadows delta. Binary is `difft` (Core
sets `HAVE_DIFFT`). Packaged on Arch (`extra`), Alpine (`community` — a musl build, so the
usual outlier is covered), Fedora, Gentoo (`dev-util/difftastic`), openSUSE, Homebrew
(`difftastic`) and Debian/Kali apt; where unpackaged, `cargo install difftastic` or `mise`.
Inert without the binary — the `gdft` alias is `HAVE_DIFFT`-guarded and `git dft` just errors.
¹¹ ast-grep: OPT-IN AST-aware structural search/rewrite — the syntax-tree complement to
`ripgrep` (text), `sd` (regex), and `gron` (JSON). Core adds **no alias** (like `gron`/`sd`) — but
the crate installs a SECOND binary, `sg`, and **that name is already taken**: `sg(1)` is a symlink
to `newgrp`, shipped by `login` on the Debian family and by `shadow` elsewhere. Since #425 put
`${CARGO_HOME:-~/.cargo}/bin` on PATH ahead of `/usr/bin`, a `cargo install`ed ast-grep now WINS
that lookup, so a bare `sg` runs the search tool rather than switching group. Prefer the `ast-grep`
name, and reach the real one as `newgrp` (or `/usr/bin/sg`). This footnote used to say `sg` "can
collide with `setgroups`" and that ast-grep "shadows nothing" — both were wrong, and #425 turned
the second into a live shadow rather than a hypothetical one. Core sets `HAVE_ASTGREP` when
present. Packaged on Arch (`extra`) and Alpine (`community` — a musl build, so the outlier is
covered) and Homebrew; elsewhere via `cargo install ast-grep` / `mise` / `npm` / `pip`. Inert
without the binary — nothing depends on it.
¹² Gentoo **GURU overlay** (`sd`, `glow`, `xh`, `carapace`, `1password-cli`, `tealdeer`,
`yazi`, `lazygit`, `direnv`, `gping`¹⁹): not in the main `::gentoo` tree. Enable once with
`eselect repository enable guru && emaint sync -r guru`, then `emerge` the atom. bootstrap.sh
does this best-effort, per-atom (one masked atom doesn't block the rest), in its `guru_install`
pass — which runs AFTER the main-tree emerge, so these must not sit in the main `packages.txt`
blocks or they're skipped. They are named in a `packages.txt` comment instead, which is a
**pointer to that call, not a decline** — bootstrap really does emerge them. direnv is
`app-shells/direnv` (not `dev-util/direnv`, which does not exist). **`gum` is not on this list
and must not be added back**: `app-misc/gum` exists in neither GURU nor `::gentoo` (nor as
`app-shells/gum` or `dev-util/gum`), so an entry can only ever emerge as a `skipped:` line —
which reads like a keyword mask and gets "fixed" with an `accept_keywords` entry that unmasks
nothing. That is exactly how it survived in `guru_install` for months; see ³⁰ for what provides
gum on Gentoo now.

**`ouch` is a GURU atom too, but it is NOT in that `guru_install` list** — it is opt-in, and
`--no-extras` has to be able to skip it. `dotfiles-Gentoo` therefore has a third seam,
`guru_extras_install`, for the one pairing neither existing list covers: overlay-sourced AND
opt-in. It was `cargo install --locked ouch` until dotgibson/dotfiles-Gentoo#133, on the same
upstream-latest reasoning `watchexec`²⁵ still carries. That reasoning does not survive contact
here twice over. The cargo build **cannot succeed on a GCC/libstdc++ box at all**: ouch's
default `unrar` feature pulls `unrar-ng-sys`, whose `build.rs` unconditionally adds
`-stdlib=libc++`. And GURU's `app-arch/ouch` is 0.8.1 — the _same_ version as upstream's
latest release, with a `src_prepare()` that seds exactly that flag out. So the route-around
bought no version and cost the tool, on every run, silently.

**`shellcheck` on Gentoo is `dev-util/shellcheck-bin`, and the `-bin` is load-bearing.**
`dev-util/shellcheck` is the Haskell build: it needs `>=dev-haskell/aeson-1.4.0` and the rest
of the GHC chain, every one `~arch`, so keywording _shellcheck_ alone unmasks nothing and the
emerge still fails — while the `accept_keywords` file you were told to edit now carries the
entry you were told to add. That is the `gum` trap above arriving from the other direction, and
it is the more expensive one: reaching the source atom by hand costs ~60 `dev-haskell/*`
keyword lines plus a GHC build. `dev-util/shellcheck-bin` is upstream's own static release,
`KEYWORDS="-* amd64 ~arm arm64"` — **stable** on amd64 and arm64, so it needs no keyword line
at all. Note the leading `-*`: on x86, ppc64 or riscv it is reachable only via `**`, never
`~arch`. The two atoms block each other (`RDEPEND="!dev-util/shellcheck"`), so a box that
already merged the source one must `emerge --unmerge dev-util/shellcheck` first.
¹³ op = **1Password CLI**. bootstrap.sh installs it from 1Password's official **signed** repo,
which differs per family: dnf/rpm repo (Fedora/openSUSE), apt repo (Debian/Kali), apk repo
(Alpine — a native musl build, so it's fine on the musl outlier), the AUR `1password-cli`
(Arch), and the GURU `app-misc/1password-cli` (Gentoo). A vendor repo, **not** the OS repo;
the apt/rpm setup is rollback-safe (a failed install removes the added repo entry).
¹⁴ Alpine **testing-or-unpackaged** (`duf`, `glow`, `tealdeer` — plus `ouch`, which is not in
`testing` either, it is **unpackaged on Alpine outright**; `bootstrap.sh` says so at its cargo
call site). The first three are musl-fine tools that live in `testing` (never promoted to
`community` on stable, incl. 3.24), which isn't enabled by default on a stable release. bootstrap.sh builds them from source instead of force-enabling `testing`,
and the paths are **not** all the same one: `duf` + `glow` take `go install` (static,
musl-safe), `tealdeer` takes a plain `cargo install --locked tealdeer` (it is the `tldr` row's
`cargo³`, which is why that row does not cite this note), while `ouch` takes
`cargo install --locked ouch --no-default-features` — bzip3's `libbzip3-sys` build
script runs bindgen, bindgen `dlopen`s libclang, and Rust's musl toolchain links statically, so
the DEFAULT feature set cannot build on the outlier at all (installing clang does not help).
None of the four is listed in `install/packages.txt`, and putting them there "as a best-effort"
is a **footgun the OS repo documents against**: `apk` fails the whole transaction on one unknown
name, so a permanently-unresolvable entry breaks the bulk `apk add` on EVERY run and forces the
per-package retry loop across the entire list.
¹⁵ Kali `glow`/`gum`: recent **Debian sid** packages (Kali rolling tracks testing/sid). If they
haven't migrated to your snapshot, bootstrap falls back to `go install` / the Charm apt repo
(`repo.charm.sh/apt`).
¹⁶ viddy: the `watch` replacement — Core aliases `watch`→`viddy` (`HAVE_VIDDY`-guarded in
`zsh/20-aliases.zsh`), so a box without the binary just keeps classic `watch`. viddy is a
**Rust** CLI (rewritten from Go upstream), so it installs via `cargo install viddy`, **not**
`go install`. Packaged on Homebrew (`viddy`, already in the macOS `Brewfile`) and the AUR;
**not** in Arch-official, Gentoo, or Debian/Kali apt, but now in **Alpine**
`community` (a native musl build — apk-installed, with the cargo build kept as a fallback)
and **openSUSE** Tumbleweed `repo-oss` (see ¹⁸).
Where unpackaged, `bootstrap.sh` builds it best-effort via `cargo install --locked viddy`
(the same cargo path as yazi/dust/tealdeer). **Arch** is the exception: it ships no rust toolchain and builds no AUR
helper (see its `packages.txt`), so bootstrap prints a hint to `paru -S viddy` instead of
auto-installing. Inert without the binary.

¹⁷ jnv: OPT-IN interactive jq-filter editor + collapsible JSON viewer — the "explore an
unfamiliar API/JSON response" verb, complementing `jq` (transform), `gron` (grep), and `yq`
(YAML). Its own command (no alias, like `jq`/`gron`/`ast-grep`), `HAVE_JNV`-guarded in
`zsh/00-tools.zsh`, inert without the binary. A **Rust** CLI (embeds `jaq`, so no external
`jq` needed). **On Linux this is detect-only on every repo but one — `jnv` is in no
`install/packages.txt` anywhere, so Core lights up `HAVE_JNV` only once you install it
yourself. The exceptions, per ²¹: `dotfiles-Alpine`'s `bootstrap.sh` DOES install it
(cargo, best-effort — hence `cargo³` in its cell, since `jnv` is unpackaged on all five
Alpine branches including `testing` on edge, making cargo its only source there), and
`dotfiles-Gentoo` cargo-builds it in the opt-in extras block that `--no-extras` skips. On
macOS the `Brewfile` carries it.** Everywhere else the row above names where that platform
gets it when you opt in — Arch `pacman -S jnv`, Nix, or `cargo install --locked jnv` — not
an automatic install. **Arch's cell used to read `AUR` and
this footnote used to prescribe `paru -S jnv`; both are now wrong.** jnv entered `extra` as
0.7.1-1 on 2026-04-01, confirmed on-box with `pacman -Si jnv` (`Repository: extra`), so no AUR
helper is involved on Arch any more. Wiring it into the per-repo bootstrap
(the ³ best-effort path viddy/yazi use) is done on Alpine and Gentoo and remains a tracked
follow-up on the rest; there is no confirmed Gentoo GURU atom yet either, so verify on the
next Gentoo stamp.

¹⁸ openSUSE **Tumbleweed** now ships these first-class in the main OSS **binary** repo
(`repo-oss`, i.e. `.../tumbleweed/repo/oss` — built from OBS `openSUSE:Factory`; note
`src-oss` is the _source_-RPM repo and is not what `zypper in` resolves against), so
`zypper in` beats the upstream-installer/cargo/go fallback these rows used to prescribe:
`starship`, `atuin`, `yazi`, `viddy`, `ouch`, `doggo`, `ast-grep`.
**Leap 16.0 and 16.1 have now been audited** (dotfiles-openSUSE#89, verified against both
releases' `repo/oss` binary indexes on 2026-08-21) — the supported Leap is 16.x; 15.6, which
this note used to hedge about, is EOL. **All seven resolve on both**, via Backports rather
than the main OSS repo — `starship` 1.21.1, `atuin` 18.3.0, `yazi` 25.5.31, `viddy` 0.4.0,
`ouch` 0.5.1, `doggo` 1.0.5, `ast-grep` 0.28.0 (`bp160`/`bp161` disttags). So `zypper in`
is the right first move on Leap too, and the ³ fallback is no longer the expected path for
these seven — but Leap pins where Tumbleweed rolls, so treat those versions as a floor and
take the ³ path when a row needs something newer. The rows are named for Tumbleweed because
that's the flavor this fleet targets.
Five of the seven (`starship`, `atuin`, `yazi`, `viddy`, `doggo`) are also installed by
`dotfiles-openSUSE`'s `bootstrap.sh`, which stays correct and harmless either way — each
install is presence-guarded, so a packaged binary just short-circuits it. **`ouch` and
`ast-grep` are not**: that bootstrap has no installer for them, so the old `cargo³` cells
promised a fallback that never existed and the package name above was, for a while, a name you
had to type yourself. Moving any of these into `install/packages.txt` is a separate judgment
call — it trades upstream-latest for the distro build. **`dotfiles-openSUSE` has since made
that call the other way**: its list flipped to packaged-first, and `starship`, `atuin` and
`yazi` are now in it, so the three `curl | sh` installers only run as a fallback — and as of
dotfiles-openSUSE#113 **`ouch` and `ast-grep` are in it too**, which is what finally closes the
gap this paragraph opened: no installer plus no list entry had meant no automatic path at all.
`viddy` deliberately stays out (cargo, for upstream-latest), and `doggo` likewise (go, same
reason) — those two are declines, not gaps.

¹⁹ gping: the `ping` replacement — Core aliases `ping`→`gping` (`HAVE_GPING`-guarded in
`zsh/20-aliases.zsh`), so a box without the binary just keeps classic `ping`. **Detect-only on
every Linux repo except `dotfiles-Alpine` and `dotfiles-Gentoo`** — Alpine's
`install/packages.txt` carries `gping` outright, and Gentoo emerges `net-analyzer/gping` from
GURU in its `guru_install` pass. Gentoo's list names the atom only in a comment because
overlay-only atoms **must** live there (the main-tree emerge runs before GURU is enabled, so an
atom in the list proper would be skipped and never retried) — that comment is a pointer to the
call, **not** a decline, which is what this footnote used to read it as. The macOS `Brewfile`
carries it too. On the other seven repos the alias lights up only once you install it yourself —
this row exists so there is a documented path when you do. (`aliases.md` and `PARITY.md` have advertised the alias since
v3; the matrix row is what was missing.) A **Rust** CLI → `cargo install gping` anywhere
unpackaged. Packaged: Arch `extra`, Alpine `community` (a native musl build, so the outlier is
covered), Homebrew (`gping`), nixpkgs, and Debian/Kali apt — where the **source** package is
`rust-gping` but the **binary** you install is plain `gping` (Debian trixie 1.19.0, sid/Kali
rolling 1.20.4). openSUSE: **Leap 16.0 and 16.1** both carry it via Backports at 1.17.3
(`gping-1.17.3-bp160.1.13` / `-bp161.1.6`, verified 2026-08-21) — behind, but present without
adding a repo; **Tumbleweed** builds it from Factory (1.20.1). The old 15.6/1.16.1 reading
here predated Leap 16 and 15.6 is now EOL. Gentoo is **GURU-only** (`net-analyzer/gping`) — there
is no main-tree atom, so it is emerged **like the ¹² atoms**, in the same `guru_install` pass and
from the same overlay; nothing there is left for you to do by hand. Inert without the binary;
nothing depends on it.

²⁰ atuin **daemon mode** — the one part of the atuin story that is NOT Core's to decide.
Core ships `atuin/config.toml` (symlinked to `~/.config/atuin/config.toml`) with the
`[daemon]` block **off**; the daemon owns the SQLite writes so shells stop contending for
the DB lock, which is where atuin's tail latency comes from on a busy multi-pane box. What
differs per machine is how the daemon gets **launched**, so that half lives in the OS repo:

| Machine                                                              | How the daemon runs                                                                                                                                                                                                              | What the OS layer exports                                     |
| -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Fedora✔ · Debian/Ubuntu/Kali✔ · Arch · openSUSE · Gentoo (systemd)   | `systemd --user` unit — copy `examples/atuin-daemon.service` into `~/.config/systemd/user/`, then `systemctl --user enable --now atuin-daemon` (and `loginctl enable-linger $USER` if you want it alive outside a login session) | `ATUIN_DAEMON__ENABLED=true`                                  |
| Alpine✔ (musl, no systemd)                                           | atuin supervises its own daemon — no unit, no service manager, nothing to install                                                                                                                                                | `ATUIN_DAEMON__ENABLED=true` + `ATUIN_DAEMON__AUTOSTART=true` |
| macOS                                                                | same as Alpine: `autostart` beats hand-writing a launchd plist — the socket path is atuin's own to resolve (see the note below the table)                                                                                        | `ATUIN_DAEMON__ENABLED=true` + `ATUIN_DAEMON__AUTOSTART=true` |
| Windows                                                              | out of scope — `dotfiles-Windows` vendors no `core/` and replicates its host config in PowerShell                                                                                                                                | —                                                             |

**Where the daemon socket lives is changing, and has NOT shipped in any release yet.**
Upstream PR #3910 (merged 2026-08-12) changes the default for `systemd_socket = false` — the
shape Core recommends — from `$XDG_RUNTIME_DIR/atuin.sock` (falling back to
`$XDG_DATA_HOME/atuin/atuin.sock` where that is unset) to **`$TMPDIR/atuin-$UID/atuin.sock`**.
`systemd_socket = true` is unchanged.

**This note used to say the move landed in 18.20.0. It has landed in no release, stable or
beta.** #3910 merged 2026-08-12, _after_ `v18.20.0-beta.3` (2026-08-07); the newest stable is
**18.19.0** (2026-08-03), which still resolves the old path. Date the change by its merge, not
by a version, until a release actually carries it — naming an unshipped version is how a
reader concludes their box is already on the new path.

Two consequences worth recording, both stated against the merged behaviour rather than a
release. The old macOS reasoning — "`XDG_RUNTIME_DIR` is unset there so the socket lands in
the data dir" — stops being true, and macOS's per-user `$TMPDIR` actually _unifies_ macOS and
Linux rather than splitting them. And atuin's own client gained a legacy search list, while
Core's guard resolved exactly one expression: once this ships it would have probed a path
nothing binds, exported `ATUIN_DAEMON__ENABLED=false` at every shell's first precmd and
unhooked the watchdog — permanently, and with **no warning**, because
`_CORE_ATUIN_DAEMON_WAS_UP` is never set on that path. Fixed pre-emptively in #518: the guard
now probes the new default and both legacy paths, newest first, so it follows a daemon across
the version boundary in either direction. Being ahead of upstream here is the right
direction — only the prose claiming a shipped version was wrong.

The exports belong in that repo's `os/<os>.zsh` (loader fragment 80), **never** in the Core
config: Core is vendored identically to every repo, so a per-machine value there would be
wrong on the other eight. `autostart` is mutually exclusive with `systemd_socket = true` —
pick the unit or pick autostart, not both.

**✔ marks the machines where the exports are actually wired today — Fedora,
Debian/Ubuntu/Kali and Alpine, three of the seven Core-vendoring machines this table
covers.** The marker is per **machine**, not per row: the systemd row holds a wired Fedora
and a wired Debian/Ubuntu/Kali alongside three unwired ones. For the other four — Arch,
openSUSE and Gentoo (sharing that row with Fedora) plus macOS — the cell is the documented
recipe, not a shipped state, so follow the rollout order below (Fedora first as the template,
Alpine second as the design's real constraint, then the rest) rather than assuming your repo
already does this.

**`Kali` is not a machine of its own here, and used to be listed as one.** It was
`dotfiles-Offense`'s identity while that repo carried the Kali OS band; the band moved to
`dotfiles-Debian`'s `only:kali` tier, so Kali is now one of that repo's three targets and
inherits its wiring — which is why it moved into the wired cell rather than staying beside
it. Nothing was left owning a `Kali` row.

`dotfiles-Debian` is wired end to end: its `os/debian.zsh` exports `ENABLED`, and — because
Ubuntu **has** systemd, so the `AUTOSTART` fallback never fires there — its `bootstrap.sh`
also installs and enables the `systemd --user` unit. Exporting `ENABLED` without installing
a launcher is the one state this note warns against, and on a systemd box the autostart
escape hatch does not cover for it. The `Windows` row is neither wired nor pending:
it is out of scope, vendoring no `core/` at all. **Neither role repo has a row here, both
by the same design** — `Defense` and `Offense` are distro-agnostic and carry no `os/`
layer, so their atuin exports come from whichever OS repo is underneath them (see "Repo
status"). Seven machines + `Offense` + `Defense` = the nine Core-vendoring repos in
`scripts/os-repos.txt`.

That used to read "eight machines + `Defense`", which counted `Offense` as a machine. The
arithmetic was right and the label was a release out of date: `Offense` shed `os/`,
`install/packages.txt` and `scripts/tool-versions.env` when the Kali lane moved, so it now
qualifies for exactly the exemption this paragraph grants `Defense`.

**For those exports to work at all, `atuin/config.toml` must leave `enabled` and `autostart`
unset** — and it does. atuin builds its config as defaults → environment → config **file**,
with the file source added last, so in the `config` crate the file WINS: any key written
there shadows its `ATUIN_*` override. Core previously wrote `enabled = false` explicitly,
which silently made every export in this table a no-op — measured against atuin 18.19.0, the
client made zero `connect()` calls to the daemon socket with the key present and one with it
absent. Upstream's defaults are already `false`, so leaving the keys out ships the same OFF
default while letting the override through. `scripts/test-core.sh` asserts they stay out. Adoption order is Fedora first (the template the
Linux repos are stamped from), Alpine second (it is the design's real constraint, so proving
it early is worth more than doing it last), then the rest.

Under the **systemd-unit** launcher, `zsh/00-tools.zsh` probes the socket before the first prompt
and then, throttled to at most one `connect(2)` a minute, for the life of the shell, forcing the
daemon **off for that shell** the first time a connect fails: an absent — or stale, i.e. left
behind by a crashed daemon — socket does not cost atuin a failed write, it costs the row. So a
dead daemon costs the lock relief, not your history — including for a session that was already
open when the daemon went away, which is the case the one-shot probe used to miss entirely
(`dotgibson/dotfiles-core#366`). Degradation is **one-way**: the guard unhooks itself and never
re-enables, because direct writes always work, so the only price of being early is the lock relief
until the next shell. A shell that was **already** degraded when it started stays silent — nothing
changed under it — while one whose daemon died **mid-session** prints a single warning, that being
the case where an open session's plumbing changed underneath it. `core-doctor` distinguishes the
two afterwards, and `core-doctor --json` exposes them as `atuin_daemon.degraded` / `.was_up`.

`--json` also carries `detection.ran` / `detection.missed` (#545). `missed` names tools that
are on `PATH` now but were **not** when Core ran detection at band 00 — so they have no
`HAVE_*` flag, no alias and no shell init, however green their row looks. The cause is a
directory that joined `PATH` later (`80-os.zsh`, an `85-*` role fragment, `99-local.zsh`, or
mise's per-directory hook), and the remedy is to move that prepend into `00-tools.zsh`'s
bindir list. `ran` is false wherever band 00 never loaded — a script, `zsh -c`, the unit
harness — and `missed` is then necessarily empty and means nothing, so a provisioning gate
should read `jq -e '.detection.missed == []'` only after checking `.detection.ran`.

`detection.stale` is its mirror (#631): tools Core **did** detect at band 00 and that are gone
from `PATH` now. The flag is still set, so `20-aliases.zsh` already defined the alias it gated
— which matters most for the six that shadow classic commands (`ps`, `top`/`htop`, `watch`,
`df`, `ping`, `help`), where the result is not a missing `procs` but a broken `ps`. The report
names the dangling **aliases** rather than the tools for that reason. The usual cause on a live
shell is mise's `chpwd` hook taking a toolchain away on a `cd`. Same `ran` caveat, same gate
shape: `jq -e '.detection.stale == []'`. The two lists are disjoint by construction — a row is
present-and-unprobed or absent-and-probed, never both.
`CORE_ATUIN_PROBE_INTERVAL` tunes the window for a box where `connect(2)` on that path is not
cheap. One wrinkle worth knowing: the disable is an `export` (that is how it reaches the `atuin`
binary), so a shell started _from_ a degraded shell inherits `ATUIN_DAEMON__ENABLED=false` and
stands down as "never opted in" — harmless, since it also writes directly, but it will not pick
the daemon back up until you start a shell from a clean parent.

**Under `autostart` the probe deliberately does not run** — and that is the Alpine and macOS
rows above, so on two of the eight machines this safety net is not the thing keeping you out
of trouble. It stands down because an absent socket is then the client's _cue to start one_,
not a fault; disabling the daemon there would permanently defeat the only launcher those
machines have. atuin's own health-checking is what covers them — and that is now **measured
rather than assumed** (`dotgibson/dotfiles-core#402`). It is a second premise with its own
mode, its own anchor line in `zsh/00-tools.zsh` and its own issue title:
`scripts/verify-atuin-guard.sh --premise autostart` (or `make verify-atuin-guard-autostart`)
spawns a real daemon, checks that one appears and that the entry lands from each unreachable
shape, and proves the teardown before deleting anything. The weekly workflow runs it as a
separate job from the silent-discard one.

Two things that measurement established on 18.19.0, both worth knowing before you touch these
rows. The **stale-socket shape is the load-bearing one** — every `atuin history start` is a
fresh process, so "fire-and-forget" can only mean that a crashed daemon's leftover inode
defeats the spawn, and a check that only tried an absent socket would miss it. And the healing
lives in the **client**: `atuin daemon start` on its own refuses over a stale inode with
`Address already in use`, while the autostart path unlinks it first.

**Watch `atuinsh/atuin#3957` — it would make that last sentence wrong.** Opened 2026-08-20,
still open and unreviewed, it makes the **daemon** unlink a stale socket on bind failure. The
"healing lives in the client" finding is the measured basis of `--premise autostart` and of
`CORE_ATUIN_AUTOSTART_VERIFIED_AGAINST` in `zsh/00-tools.zsh`; if #3957 merges, the daemon
heals itself and the premise the stand-down rests on no longer holds. **No action while it is
unmerged** — and in particular do not edit that anchor, which is a claim the premise was
re-measured, not a version bump. Re-run `make verify-atuin-guard-autostart` if it lands.

Still not covered, so the default `--premise discard` caveats are not the only ones: the
scheduled job runs on glibc Linux, which is neither of the two machines this premise protects,
and a run that is green there is the weakest evidence in the whole arrangement for these rows.
Running `make verify-atuin-guard-autostart` on the Alpine or macOS box itself is what actually
speaks for it.

The probe's limit, because it decides which unit you should install: it cannot tell an
**accept-but-silent** socket from a healthy one. systemd **socket activation** produces
exactly that state when the daemon behind the socket is dead — the socket keeps accepting,
the client waits, and that is the indefinite freeze in `atuinsh/atuin#3382`. Prefer the plain
always-running service above; if you do use a `.socket` unit with `systemd_socket = true`,
you are outside what Core can protect.

²¹ **Available, not installed** — the same shape as `jnv`¹⁷ and `gping`¹⁹, and the
counterpart to ³. These cells name where the tool comes from **when you opt in**, so on
the repos that do not carry it Core lights the `HAVE_*` probe only once you install it
yourself. That promise now actually holds for a `cargo install`, which is what #425 fixed:
`${CARGO_HOME:-~/.cargo}/bin` used to reach PATH via the OS layer at band 80, a whole
load-order band after `00-tools.zsh` probed, so the flag stayed dark and the alias was never
made while `core-doctor` — probing live, later — reported the tool present. It joins PATH
before detection now.

**Coverage here is per tool, never a fleet-wide zero** — the table below is the authority, not
the prose. **Two** repos' `bootstrap.sh` really do install entries from this family:
`dotfiles-Alpine` (`ouch` and `jnv`¹⁷, via cargo¹⁴) and `dotfiles-Gentoo` (`shfmt`
unconditionally via `go`; `ouch`, `ast-grep`¹¹, `jnv`¹⁷ and `watchexec`²⁵ via cargo, plus
`dev-vcs/jj`⁸ via emerge, all in an opt-in extras block that `--no-extras` skips; and `gping`¹⁹
via GURU). For the other seven repos "no bootstrap installs it" still holds.

**How the Gentoo half of that went unnoticed is the lesson worth keeping:** this table was
previously verified against each repo's `install/packages.txt` **alone**, and Gentoo is the repo
that installs the most from `bootstrap.sh` instead — deliberately, because `packages.txt` is its
UNCONDITIONAL emerge and everything opt-in must therefore live in the script. Verified against
`packages.txt`, four of the eight Gentoo cells below read `—` when bootstrap installs the tool.
**Check both files, or this row goes stale again.**

Verified 2026-08-21 (Gentoo column re-verified against `bootstrap.sh` as well) against all six
Linux repos plus the MacBook `Brewfile` — a **—** means detect-only there, and the packaged name
in that tool's row above is what you would install by hand rather than what a bootstrap gives
you:

| Tool           | macOS `Brewfile` | Alpine             | Gentoo                                    | Arch / Debian / Fedora / openSUSE |
| -------------- | ---------------- | ------------------ | ----------------------------------------- | --------------------------------- |
| `hyperfine`    | ✓                | `hyperfine`        | `app-benchmarks/hyperfine`                | —                                 |
| `shellcheck`   | ✓                | `shellcheck`       | `dev-util/shellcheck-bin`                 | —                                 |
| `shfmt`        | ✓                | `shfmt`            | bootstrap, go⁷ (unconditional)            | —                                 |
| `ouch`         | ✓                | bootstrap, cargo¹⁴ | bootstrap, `app-arch/ouch` (extras)       | openSUSE: `ouch`¹⁸; others —      |
| `lnav`²⁴       | ✓                | `lnav`             | `app-admin/lnav`                          | —                                 |
| `git-absorb`²⁶ | ✓                | `git-absorb`       | `dev-vcs/git-absorb`                      | —                                 |
| `gping`¹⁹      | ✓                | `gping`            | bootstrap, `net-analyzer/gping` (GURU¹²)  | —                                 |
| `watchexec`²⁵  | —                | `watchexec`        | bootstrap, cargo `watchexec-cli` (extras) | —                                 |

- **The `ouch` row's last cell is split because that column is four repos, not one.**
  `dotfiles-openSUSE` added `ouch` to its `install/packages.txt` in dotfiles-openSUSE#113, so
  the tool is no longer detect-only there while it still is on Arch/Debian/Fedora. Note this
  is a **`packages.txt`** addition, not a `bootstrap.sh` one — so the "two repos' `bootstrap.sh`"
  count above stays right, and this is exactly the both-files distinction the lesson two
  paragraphs up warns about. `ast-grep` moved the same way in the same PR but has no row here.
- "extras" above means Gentoo's opt-in block: installed by default, **skipped by
  `--no-extras`**. That flag is the one thing keeping these honest as ²¹ entries rather than ³
  ones — the tool is still something you can decline.
- **Gentoo's `ouch` cell is a cargo cell by CHOICE, not by availability** — the same shape as
  `watchexec`²⁵, and worth stating because only one of the two said so. GURU carries
  `app-arch/ouch` (0.7.1, 0.8.0, **0.8.1**) and `::gentoo` carries no `ouch` at any category;
  `dotfiles-Gentoo` `cargo install`s it anyway, for upstream-latest. Read the cell as "cargo,
  over an available overlay ebuild", not "nothing packages it". Verified 2026-08-23 against
  `gentoo/guru@master`. The genuinely-unpackaged Gentoo entries in this family are
  `ast-grep`¹¹ and `jnv`¹⁷, absent from both trees.
- This list used to read "**macOS-only in practice**: the MacBook `Brewfile` carries them;
  **no** Linux repo does." Every row above falsifies that — Alpine carries seven of the eight
  outright and Gentoo installs all eight, four of them from `bootstrap.sh`. Keep it a **per-tool**
  statement: the family is defined by "Core probes it, and most repos leave installing it to
  you", not by a distro, and no longer by "no bootstrap installs it" — two now do.
  (Deliberately not a counted list — "all four" went stale the first time this family grew,
  "no Linux repo does" the second, and "`ouch` is the one entry" the third.)
- The cells that previously showed **³** here — `ouch` on Gentoo **and** Kali, `jujutsu` on
  Kali, `ast-grep` on Gentoo **and** Kali, `shfmt` on Gentoo, `lazygit` on Kali — promised a
  best-effort bootstrap install that **does not exist**, verified against each repo's
  `bootstrap.sh` and `install/packages.txt`. (Gentoo's `ouch`, `ast-grep` and `shfmt` have since
  _acquired_ such an install, and `jujutsu` on Gentoo is now the packaged `dev-vcs/jj`⁸ — the
  correction stands for Kali, and for what those cells claimed when it was made.) `lazygit` is the sharpest case: every other Linux repo installs it,
  Kali installs it through `dotfiles-Debian`'s `only:kali` tier (`install/packages.txt`),
  and Core ships `alias lg='lazygit'` regardless.
- **Kali's lane moved.** This note used to read "Kali installs nothing from this family",
  which was true while `dotfiles-Offense` owned the Kali OS band. It no longer does:
  `dotfiles-Debian` owns that lane through its `only:kali` / `skip:kali` tiers, and installs
  a substantial subset. `ast-grep` is still absent there, which is the claim that survives.
  This note used to carve out
  an exception saying it did — "`bootstrap.sh`, cargo best-effort" — and that is why the
  `ast-grep` row kept a `³` in its Kali cell after its neighbours lost theirs. There is no such
  install: `dotfiles-Offense`'s `bootstrap.sh` contains no `ast-grep`, and its only two `cargo`
  mentions are the comment and `export` that put `~/.cargo/bin` on PATH for tools **an operator
  added by hand** — which is the ²¹ contract, not a ³ one. The cell is now `cargo²¹`, matching
  `ouch` and `jujutsu` in the same column.

This is the same overclaim already corrected once for openSUSE (`ouch`/`ast-grep`): ³ means
"bootstrap.sh installs it best-effort", so a ³ with no installer behind it reads as "you
have this" when you do not.

²² sd **changed its default in 1.1.0**: it now processes input **line by line**, and the old
whole-file behaviour moved behind `--across` / `-A`. The failure mode is **silent** — a pattern
that spans a newline (`sd 'foo\nbar' baz`) matches nothing, leaves the input unchanged, and
still **exits 0**, so a script carries on as though it had rewritten the file. Confirmed
behaviourally here rather than taken from the release notes. Worse, **`sd --version` cannot
tell you which behaviour you have** — the Homebrew 1.1.0 build self-reports `sd 1.0.0` — so
version sniffing is useless and a `HAVE_SD` version gate is not an option. Probe the flag
instead: `sd --help | grep -q -- --across`. Core itself is **unaffected**: `sd` is detect-only
(`HAVE_SD` in `zsh/00-tools.zsh`) with deliberately no alias (`zsh/20-aliases.zsh` — never
shadow `sed` in scripts), and nothing in Core shells out to it. This is a warning for muscle
memory and for the role layers.

Do **not** blanket-add `-A` to role scripts. The flag does not exist before 1.1.0, and this
matrix exists precisely because distros lag (Gentoo takes `sd` from the GURU overlay), so a
script that hard-codes it **breaks on the older build** — which already matches whole-file
and needs no flag. A script that must run against both feature-detects and builds the flag
list, rather than assuming either default:

```sh
sd_across=(); sd --help 2>/dev/null | grep -q -- --across && sd_across=(-A)
sd "${sd_across[@]}" 'foo\nbar' baz file
```

²³ Arch `refresh` **and** `count-pending` (the **Package-manager commands** table above).
`refresh` is listed for completeness — **`dotfiles-Arch` deliberately ships no alias for
it** — and `count-pending` is `checkupdates` for the same reason the alias does not exist. A bare
`pacman -Sy` is safe on its own, but refreshing the sync DB and then installing is
the partial-upgrade footgun, so `os/arch.zsh` provides only `pacu` (a full `-Syu`)
and `pacout` (`checkupdates`, which lists updates without touching the sync DB at
all). There is no `-Sy <pkg>` alias **on purpose** — see "Distro quirks" below. Do
not "helpfully" add one.

²⁴ lnav: OPT-IN log reader — the verb Core had no tool for. `bat`/`rg` read a log as
**lines**, `jq`/`gron`/`jnv` read it as **JSON**, `glow` as markdown; `lnav` reads it as a
**log**: it autodetects common formats, merges several files into one timeline ordered by
timestamp, follows like `tail -f`, and exposes the parsed records to SQL. Its own command
(no alias, like `jq`/`gron`/`jnv`), `HAVE_LNAV`-guarded in `zsh/00-tools.zsh`, inert
without the binary. A **C++** CLI, so it has no `cargo`/`go install` escape hatch like the
Rust/Go tools above — but it does not need one: upstream publishes **static musl binaries**
per release (`lnav-0.14.0-linux-musl-x86_64.zip`, and an `arm64` twin), so the fallback on
an unpackaged or lagging box is "unzip the official build", not "compile it". That is also
the cleanest way to get 0.14.0 onto Gentoo or Debian/Kali without waiting for the package.
**No `bootstrap.sh` installs it anywhere**, but it is not detect-only across the board:
`dotfiles-Alpine` (`lnav`) and `dotfiles-Gentoo` (`app-admin/lnav`) both carry it in
`install/packages.txt`, and the MacBook `Brewfile` has it too (added 2026-07-15). On the other
four Linux repos Core lights `HAVE_LNAV` only once you install it yourself. So `lnav` sits in
²¹'s family — probed but never bootstrap-installed — rather than jnv's thinner "two platforms
package it, cargo everywhere else" one: every distro in the table above ships lnav, and two of
the repos ask for it.

Versions **verified against each distro's own package pages** on 2026-08-12, not taken from
a repology snapshot. Upstream is 0.14.0 (2026-04-12). Rolling targets get one query each,
because that query is the complete answer; **Fedora is versioned, so every supported stable
release is named separately** rather than collapsed into one unqualified ✓:

| Target          | Release                                  | lnav              |
| --------------- | ---------------------------------------- | ----------------- |
| Arch            | `extra` (rolling)                        | 0.14.0-1          |
| openSUSE        | Tumbleweed (rolling)                     | 0.14.0            |
| Alpine          | `edge/community` — **native musl build** | 0.14.0-r0         |
| Homebrew        | rolling                                  | 0.14.0            |
| **Fedora**      | **Rawhide / F45**                        | **0.14.0-3.fc45** |
| **Fedora**      | **F44**                                  | **0.13.2-2.fc44** |
| **Fedora**      | **F43**                                  | **0.12.4-2.fc43** |
| **Kali/Debian** | rolling / sid                            | **0.13.2**        |
| **Gentoo**      | `app-admin/lnav`                         | **0.11.2**        |

So "Fedora has it" is true but "Fedora is current" is only true on F45/Rawhide — F44 and F43
track one and two minors back respectively. Two targets lag enough to be worth naming:

- **Gentoo `app-admin/lnav` is 0.11.2** — the only version in the tree, stable on amd64/x86,
  and the package is flagged as **needing a new maintainer**, so do not expect it to close
  the gap on its own. Three minor releases behind. Re-check on the next Gentoo stamp.
- **Kali/Debian `lnav` is 0.13.2** — one minor behind, the smaller gap of the two.

On either, the upstream static musl zip above is the way to 0.14.0 without waiting.

²⁵ watchexec: OPT-IN **event**-driven repetition — the third corner of a triangle Core
already had two of. `viddy` re-runs on a **timer** (`watch`), `hyperfine` re-runs a fixed
**count** and measures; `watchexec` re-runs when **files change** (`watchexec -e py --
pytest`). Its own command, `HAVE_WATCHEXEC`-guarded in `zsh/00-tools.zsh`, inert without
the binary. Deliberately **not** aliased to `watch` — `zsh/20-aliases.zsh` already points
`watch` at `viddy`, and collapsing "re-run on a timer" into "re-run on a change" would
silently hand you the wrong one.

**The one tool in ²¹'s family that inverts it: macOS is the machine that doesn't get it.**
The MacBook `Brewfile` does not carry `watchexec` — the only ²¹ entry it skips — while
`dotfiles-Alpine`'s `install/packages.txt` carries it outright and `dotfiles-Gentoo`
cargo-installs it from the extras block. The other seven machines are opt-in.
(This paragraph used to read "the only tool in this table that nothing in the fleet installs,
including macOS"; Alpine falsified the first half, and Gentoo — checked against `bootstrap.sh`
rather than `packages.txt` alone — falsified what was left of it.) Availability, verified
2026-08-12, Linux-repo coverage re-verified 2026-08-21 against both files, versions
re-verified 2026-08-23 against each repo's own package pages:

- **Arch `extra` and Homebrew** — 2.6.1 (Arch's package revision is `2.6.1-1`).
- **openSUSE Tumbleweed and nixpkgs** — 2.5.1, still current there. (These two shared a
  line with Arch and Homebrew while all four sat at 2.5.1; the split is what that line looks
  like once two of the four move and two do not.)
- **Alpine `community`** — 2.5.1-r0, a native musl build.
- **Gentoo: GURU carries 2.5.0**, and there is no `::gentoo` atom — but the cell reads
  `cargo²⁵`, not `GURU`, because `dotfiles-Gentoo` does not emerge that atom: it
  `cargo install`s `watchexec-cli` in its opt-in extras block instead, for upstream-latest.
  That is why this is **not** in ¹²'s GURU list — that footnote enumerates what the
  `guru_install` pass actually emerges. It is **no longer** the same shape as `gping`¹⁹,
  which _is_ emerged from GURU; watchexec is now the one GURU-available tool the Gentoo
  bootstrap deliberately routes around.
- **Fedora and Debian/Kali do not package it at all** (confirmed: Fedora's package search
  returns no results across F43/44/45/Rawhide/EPEL). Those two take
  `cargo install --locked watchexec-cli` — note the crate is **`watchexec-cli`**; plain
  `watchexec` on crates.io is the library, and installing that gives you no binary.

Do **not** read **Kali's** `cargo` cell as a `³`: no `bootstrap.sh` installs it there.
**Gentoo's `cargo` cell is the exception** — its bootstrap does install `watchexec-cli`, in
the opt-in extras block `--no-extras` skips. Either way `maint/dotfiles-maint.sh` runs
`rustup update` but has no `cargo install-update` step, so a `cargo`-installed `watchexec`
is never refreshed by the maintenance job — which bites the Gentoo box too, bootstrap or
not. That is already true of `ouch`/`jj`/`ast-grep`.

**That gap now has a prescribed path: declare the tool as a mise backend and the maintenance
job already runs the upgrade.** `maint/dotfiles-maint.sh` runs `mise upgrade --yes` and
`rustup update` and has no cargo/go re-install step, so roughly fifteen tools across the stack
— `viddy`, `yazi`, `ouch`, `jj`, `ast-grep`, `jnv`, `watchexec`, `tealdeer`, `dust`, `sesh`,
`doggo`, `gron`, `shfmt`, `glow`, `yq`, `duf`, plus `carapace`/`starship`/`atuin` ²⁷ — are
installed once and then never refreshed on up to eight machines. Declaring them under
`[tools]` with a `cargo:` / `go:` / `ubi:` backend makes the step that **already runs** do the
work, and `lockfile = true` records the exact resolved versions and checksums — a strictly
better trust anchor than the unsigned release-URL route ²⁷ warns about. `examples/mise.tools.toml`
is the worked global-tools example.

Two caveats that decide whether this works rather than merely resolves. **Alpine must take
`cargo:`, never `ubi:` or `aqua:`** — those prebuilts are glibc-linked, the exact trap
`mise/config.toml` documents for `foundry`. And **`ouch` on Alpine must force a source build
without default features**, per ¹⁴ — the default set cannot build on musl at all.

**Core's share of this is the example and this paragraph.** The `[tools]` declarations
themselves are per-OS-repo work, which is the correct layering: which backend a given box
needs is an OS question, and Core cannot answer it for eight of them at once.

²⁶ git-absorb: OPT-IN — works out which earlier commit each **staged hunk** belongs to and
writes the `fixup!` commits for you; `git rebase -i --autosquash` then folds them in, and
`git/gitconfig` already sets `rebase.autosquash = true`, so the second half is automatic.
It is the **automatic** counterpart to `git fix` (`commit --fixup`, `git/gitconfig`'s
`[alias]` block), which is the **manual** form: with `git fix <sha>` you name the target
commit yourself, and `git absorb` works one out per hunk. Reach for `git fix` when you know
where a change belongs and `git absorb` when you would otherwise go looking.

**The house-style ideal for a new tool: it needs no alias at all.** git-absorb installs as
`git-absorb` — on `PATH` in the common case, in git's exec-path on the Debian family (see
below) — and git dispatches it as the `git absorb` subcommand either way, so it shadows
nothing classic and `zsh/20-aliases.zsh` gains no entry, only a note saying why.
`HAVE_GIT_ABSORB` is set for symmetry with the other detected tools and **has no _alias_ consumer
today** — `core-doctor` probes the tool itself rather than reading the flag, so the two are
independent paths to the same question and are kept in agreement deliberately (#425).
**Debian-family packages do install it into git's exec-path rather than onto `PATH`** — on
the two boxes anyone has actually checked. **Kali**, `git-absorb` 0.6.17-2+b4, verified
2026-08-17: `dpkg -L git-absorb` lists `/usr/lib/git-core/git-absorb` and a man page and
nothing else, `command -v git-absorb` finds nothing, and `git absorb --version` works.
**Ubuntu 24.04**, 0.6.11, from the reporter's `dpkg -L` in #424. **Debian proper is
unverified** — its package page lists 0.9.0-2 and nobody has looked at where that build
lands, so read the heading as the packaging convention plus two confirmations of it, not as
a survey of the family. The convention itself is standard for a `git-<verb>` subcommand and
not an oddity: git finds it via `--exec-path`, the user invokes it as `git absorb`, and it
is intentionally absent from `PATH`.

This paragraph used to say no mainstream package did that, and #424 is what the wrong claim
cost — `core-doctor` reported `✗ git-absorb` on boxes where the tool was installed and the
only supported way to call it worked, so a reader would go install what they already had.
Both sides now look past `PATH`:

- `core-doctor` resolves any `git-*` row through `git --exec-path` when the bare name misses
  (`zsh/30-functions.zsh`, `_core_git_exec_path` + the `git-*` arm of `_core_doctor_bin`).
  One fork, only on a miss, cached per report, and the resolved absolute path is what the
  `-v` version readout then executes.
- `HAVE_GIT_ABSORB` falls back to a **zero-fork** stat. An **exported** `$GIT_EXEC_PATH` is
  probed **exclusively**, because that is what it means to git — it replaces the compiled-in
  exec-path rather than adding to it, and an _unexported_ parameter of that name never
  reaches git at all, so it is ignored here too. With no such override it stats
  `<git-prefix>/{lib,libexec}/git-core`, the prefix derived from zsh's builtin `$commands`
  hash rather than hard-coded. `zsh/00-tools.zsh` still forks nothing at shell start, which
  is the constraint that made the original PATH-only probe look reasonable.

Where the two can still differ: a git built with its libexec outside its own prefix, with
the subcommand not linked onto `PATH`. `core-doctor` is authoritative there — it asks git —
and the flag is a best-effort approximation.

Arch, Alpine, Gentoo and Homebrew land the binary on `PATH` (Homebrew in its own prefix
`bin`, `/opt/homebrew/bin` on Apple silicon and `/usr/local/bin` on Intel), so those boxes
never reach the fallback — but that is package-page evidence, not an on-box check, so treat
it with the same caution as the version stamps below.

**No `bootstrap.sh` installs it**, and it is packaged essentially everywhere — the ²¹ shape,
not `jnv`¹⁷'s. The MacBook `Brewfile` carries it, and so do `dotfiles-Alpine`
(`git-absorb`) and `dotfiles-Gentoo` (`dev-vcs/git-absorb`) in their `install/packages.txt`;
the other four Linux repos are detect-only (re-verified 2026-08-21). Package versions verified
2026-08-12 against each distro's own package pages:

- **Arch `extra`** 0.9.0-2, **Alpine `community`** 0.9.0-r0, **Gentoo `dev-vcs/git-absorb`**
  0.9.0 (**stable on amd64**, in the main tree — no GURU needed), **Homebrew** 0.9.0.
- **Debian `git-absorb`** 0.9.0-2 per packages.debian.org, but **Kali rolling ships
  0.6.17-2+b4** — verified on-box 2026-08-17. The two now have their own columns above, and
  this is a case where that matters: Kali is a laggard here rather than a Debian follower.
  Whether Debian's own 0.9.0-2 also installs into git's exec-path is **not** verified — only
  the Kali build is, so the ²⁶ footnote's on-box evidence covers the Kali column. Note repology
  reports the **source** package as `rust-git-absorb`; the **binary** package you install is
  `git-absorb`, confirmed on packages.debian.org. Fedora is the same shape
  (`rust-git-absorb` source, `git-absorb` binary).
- **openSUSE Tumbleweed is the other laggard, also at 0.6.17** — the gap #394 flagged,
  confirmed here rather than left as a repology snapshot. Re-check on the next openSUSE
  stamp.

²⁷ carapace: **`go install` cannot work here, on any platform, for any published version.**
This row used to read `go³`, and following that footnote fails on every box. It is the one
row where ³'s `go install` arm is not merely stale but impossible, so it gets its own paths.
Two independent blockers, both **properties of how the module is built** rather than a broken
build waiting to be fixed:

1. `carapace-bin`'s `go.mod` carries two **`replace`** directives (`spf13/pflag` →
   `carapace-sh/carapace-pflag`, `kevinburke/ssh_config` → `carapace-sh/ssh_config`), and
   `go install pkg@version` refuses any module that does — a `replace` would make the build
   differ from building that module as the main module: _"The go.mod file for the module
   providing named packages contains one or more replace directives. It must not contain
   directives that would cause it to be interpreted differently than if it were the main
   module."_
2. The **generated sources are not committed**: `pkg/actions/actions_generated.go` and
   `pkg/conditions/conditions_generated.go` are absent from a fresh clone, and
   `cmd/carapace/main.go`'s `go:generate` lines produce them.

Blocker 1 kills `go install`; blocker 2 kills the obvious workaround (`go build ./cmd/carapace`
on a clone) until `go generate` has run.

**The scope is every version, not just the current one** — which matters, because `go install`
takes any `@version` you name and the obvious next move on a failure is to pin an older one.
Don't: it fails identically. Checked exhaustively over the whole tag history on 2026-08-15
(`git clone --bare --filter=blob:none`, then `git show <tag>:go.mod` for each of the 184 tags
from **v0.0.3, 2020-08-31, through v1.7.3, 2026-06-30**):

- **184 of 184 tags carry a `replace` directive.** Zero exceptions. The count rose from one to
  two at v1.6.0, which is immaterial — one is enough.
- **0 of 184 tags commit `pkg/actions/actions_generated.go`.** It has never been in the tree.

So this is not an extrapolation from the current release: in nearly six years of tags there has
never been a version you could `go install`. Upstream's own `.goreleaser.yml` runs
`go generate ./cmd/...` as a pre-build hook and the AUR's from-source `carapace` PKGBUILD does
the same — this is the intended build shape, not an oversight. Upstream _could_ drop the
`replace` directives or start committing the generated sources in a future release, and this
row can be revisited if they do, but that would reverse six years of practice: treat it as a
change to watch for, not one to assume. **Re-check only on an announced change, and verify
with an actual `go install` before believing it.**

**The route is the upstream release artifact**, which goreleaser publishes per arch as
`.rpm`, `.deb`, `.apk` and `.tar.gz` (v1.7.3, 2026-06-30). Per target:

- **openSUSE** — the `linux_<arch>.rpm`. This is exactly the route `dotfiles-Fedora`'s
  `bootstrap.sh` already ships and has proven end-to-end; port that block, don't re-derive
  it. One difference from dnf that will bite: **upstream signs nothing** (there is no `signs:`
  stanza in `.goreleaser.yml`), and while dnf4 installs an unsigned local/URL rpm without
  complaint, `zypper -n` aborts on one — so a non-interactive install needs
  `--no-gpg-checks`. Same shape for Alpine's `.apk` (`--allow-untrusted`) if you ever need it.

  Be clear-eyed about what that flag gives up rather than pasting it as boilerplate: with no
  signature to check, **the only trust anchor left is HTTPS to the GitHub release origin**,
  and you are installing as root. Upstream does publish a `checksums.txt`, but it is
  unsigned and served from the same origin as the asset — it catches a truncated or corrupted
  download, not a compromised release, so it is not a substitute for a signature. A repo that
  wants a real anchor should pin the version and record the SHA-256 **in its own tree**, which
  is precisely the shape `scripts/tool-versions.env` + `scripts/update-tool-checksums.sh`
  already use for the gate toolchain (`.github/actions/setup-core-tools` verifies before
  installing). That is a heavier contract than any other bootstrap-installed tool carries
  today — starship and atuin come from upstream installer scripts, which verify less — so it
  is a deliberate per-repo call, not something this row silently mandates.
- **Kali/Debian** — the `linux_<arch>.deb`, same asset set (`amd64`/`arm64`). `apt-get
  install` wants a path, not a URL, so this is curl-to-a-tempfile then `apt-get install
  ./carapace-bin_*.deb` (which resolves deps, unlike bare `dpkg -i`).
- **Arch** — the AUR, and the package name matters: **`carapace-bin`** (1.7.3-1, `provides`/
  `conflicts` `carapace`, covers x86_64/aarch64/i686) just unpacks the upstream tarball, while
  the AUR also carries a from-source **`carapace`** that is x86_64-only and needs a Go
  toolchain. Prefer `paru -S carapace-bin`. Note the same exception ¹⁶ records for viddy:
  `dotfiles-Arch`'s bootstrap builds no AUR helper, so on a bare box this is a manual step —
  or lift the binary straight out of the upstream `.tar.gz` into `~/.local/bin`.
- **Alpine (`carapace`, `community`) and Gentoo (`app-shells/carapace`, GURU per ¹²) need no
  fallback at all** — both are genuinely packaged and both bootstraps install them. Those two
  cells carry no ²⁷ because they are verified fine, not because they were skipped.

**What the release-URL route costs you, stated plainly:** installing from a release URL adds
no repo, so **nothing upgrades carapace afterwards** — not `zypper dup`/`apt upgrade`, not
`maint/dotfiles-maint.sh`, and not a later bootstrap either (a `command -v carapace` guard
short-circuits the whole block once the binary exists). Upstream ships no rpm/apt repo and
neither distro packages it, so there is no upgrade source to point at; updating is a
deliberate manual step and `carapace --version` is how you would know you are behind. That is
the real cost, and it is still the right trade: `go install` cannot work at all, so the choice
is a manually-updated binary or no carapace. Arch is the exception — `carapace-bin` from the
AUR is a normal package that `paru -Syu` refreshes.

**Building from source** is the escape hatch for an arch with no published artifact. Verified
end-to-end in #416:

```bash
git clone --depth 1 https://github.com/carapace-sh/carapace-bin.git
cd carapace-bin
go generate ./cmd/...                          # writes the *_generated.go files
go build -o ~/.local/bin/carapace ./cmd/carapace
```

Two caveats. **Size:** this is a big binary either way — 500+ bundled completers put
upstream's released amd64 build at **81.6 MB on disk** (from a ~14 MiB download), and a plain
`go build` lands nearer 114 MB because it is unstripped and skips upstream's `-tags release`;
add `-ldflags='-s -w' -tags release` to close most of the gap. **Version:** the build will
self-report `carapace-bin develop` no matter what you clone. That is **not** a shallow-clone
artifact, as it first appears — `cmd/carapace/main.go` initializes `var version = "develop"`
and nothing in the build derives it from git, so a full clone and a checked-out tag report
`develop` too. The version is injected at link time or not at all; pass it yourself, as both
upstream's goreleaser and the AUR PKGBUILD do:
`-ldflags="-s -w -X main.version=v<tag>"`.

Core's side is unchanged by any of this: `zsh/00-tools.zsh` sets `HAVE_CARAPACE`, and
`zsh/45-plugins.zsh` runs `carapace _carapace zsh` through `_cache_eval` **after** `compinit`
(`zsh/10-options.zsh`), feeding fzf-tab. Inert without the binary.

**All three OS repos that called the impossible `go install` have been fixed**, and this
footnote is the contract each was fixed against. `dotfiles-Arch/bootstrap.sh` prints a
`paru -S carapace-bin` hint instead: Arch is the one target with a real, upgradable package,
and hand-placing the upstream binary in `~/.local/bin` would silently shadow it forever.
`dotfiles-openSUSE/bootstrap.sh` installs upstream's `linux_<arch>.rpm` release asset via
`zypper` (`--no-gpg-checks --allow-unsigned-rpm`), accepting that nothing upgrades it after.
`dotfiles-Offense` installs no carapace at all: it stopped being an OS-native layer, and the
Debian family it used to cover is `dotfiles-Debian`'s job now.

²⁸ **Pinned upstream release asset** — on Debian/Ubuntu, on Kali, or on both.
`dotfiles-Debian` installs this from a version- and SHA-256-pinned GitHub release asset via
`bootstrap.sh`'s `verified_install` (pins in its `install/tool-versions.env`, refreshed by
`scripts/update-tool-checksums.sh`). It is fail-closed: a missing pin, failed
download, or hash mismatch skips that tool loudly rather than installing anything
unverified.

**The two columns reach this cell for opposite reasons**, which is why the marker now
appears in both. On **Debian/Ubuntu** it is scarcity: Ubuntu 24.04 either has no package at
all or has one below the version Core needs. On **Kali** it is more often the reverse —
`verified_install` is `command -v`-guarded, so on a tool apt _does_ supply it no-ops and the
apt name wins; the asset fires only where kali-rolling genuinely lacks the name (`delta`,
`hexyl` — the two apt has on noble and trixie but not on kali-rolling), or where the repo
takes the pinned asset on **every** target regardless of the archive (`mise`, `uv`, and the
rest of the `verified_install` block). That last case is the one that reads wrong: a cell
saying `uv` was defensible from kali-rolling's contents and still false about what gets
installed. **A cell records what this fleet installs.**

**Neovim is the exception in shape** — its asset is a directory tree
(`bin/` + `lib/` + `share/nvim/runtime`), so it uses `verified_tree_install` and lands
in `~/.local/opt` with a symlink into `~/.local/bin`; copying the bare binary yields an
editor whose `$VIMRUNTIME` points at nothing. Deliberately _not_ the AppImage: Ubuntu
24.04 sets `kernel.apparmor_restrict_unprivileged_userns=1`, which blocks the
unprivileged user namespace an AppImage needs to mount itself.

²⁹ **Not installed on `dotfiles-Debian`.** Unlike a `³`/`cargo³` cell, this is not "you
install it by hand" — it is a decision. `yazi`, `viddy` and `ast-grep` are cargo-only and
noble's rustc is **1.75**, too old to build them; shipping a toolchain that fails
halfway through a long build is worse than not shipping the tool. `jnv`, `ouch`,
`jujutsu` and `watchexec` are likewise unpackaged there and not worth a hand-maintained
pin. All are `HAVE_*`-guarded in Core, so the shell degrades cleanly. Want one on a
particular box? `mise use -g rust`, then `cargo install --locked <tool>` — and as of #425
the next login picks it up on its own, no symlink into `~/.local/bin` needed.

³⁰ **`mise` and `uv` — the two the doctor probes but this table used to omit.**
`core-doctor` reports on both (`_CORE_DOCTOR_GROUPS` in `zsh/30-functions.zsh`) and both
get a `HAVE_*` flag, so a `✗` for either sent the reader to a matrix with no row to find —
the one promise `zsh/30-functions.zsh`'s "install missing" hint makes. **`mise` is the
chicken-and-egg row**: footnotes ¹, ⁶, ⁷, ¹⁰, ¹¹ and ²⁹ all prescribe `mise use -g <x>` as
a fallback, and every `bootstrap.sh` reaches for `mise exec go@latest` when no Go toolchain
is present, so it is a prerequisite of this table rather than an entry in it. Only **Arch**
packages it (`extra`); openSUSE and Gentoo have none, and the bootstraps there use the
official installer (`curl -fsSL https://mise.run | sh`, landing in `~/.local/bin`). Alpine
_does_ carry `mise` in `community`, but `dotfiles-Alpine` still takes `mise.run` for the musl
build — hence `script³⁰`, not a package name, in that cell. **Kali used to be in that
sentence and no longer belongs there:** its bootstrap is now `dotfiles-Debian`'s, which never
calls `mise.run` at all — it takes the pinned `MISE_VERSION` asset on every target, Kali
included, so that cell is `asset²⁸`.

`uv` used to be filed here as the cleanest illustration of why the Kali and Debian/Ubuntu
columns had to be split at all (`dotgibson/dotfiles-core#431`), on the grounds that
**kali-rolling ships `uv` 0.9.17 while Ubuntu 24.04 ships nothing** — uv reached Debian only
in sid/trixie. Both halves of that are still true about the **archives**, and it is no longer
the right reading of the row: `uv` is absent from the `only:kali` tier and
`dotfiles-Debian`'s `bootstrap.sh` fetches the pinned `UV_VERSION` asset on **every** target,
so both columns are `asset²⁸` and neither is derived from apt. The split earns its keep
elsewhere (`difftastic`, `git-delta`, `hexyl` — names apt has on noble and trixie and not on
kali-rolling); `uv` is instead the cleanest illustration of the failure the ²¹ᵃ caveat above
warns about, a cell that recorded what the archive **contains** rather than what the repo
**installs**. openSUSE's is named `python-uv` (Tumbleweed — Leap
was not separately audited, so verify with `zypper se python-uv` and fall back to ³ there),
and Gentoo's is `dev-python/uv`, not a bare `uv`.

**mise also appears in this table as a _provider_, in exactly one cell: `gum` on Gentoo.**
Charm's gum is packaged nowhere Portage can reach — not `::gentoo`, not GURU, in any category
(see ¹²) — so `dotfiles-Gentoo` declares it in `gentoo/mise-tools.toml`, which mise installs as
a prebuilt, checksum-verified binary with no compiler and no privileges. **Read that cell with
one caveat:** that manifest is installed only on the **`--user`** (no-root) path, so a
_privileged_ Gentoo bootstrap installs no gum at all. On that path it is a hand-install —
`mise use -g gum`, or `go install charm.land/gum/v2@latest` (the module path, **not** the
GitHub URL — see ³¹).

³¹ **`go install` module paths — the repo URL is usually NOT the module path.** Five of the
seven go-installable rows need a major-version suffix, a `cmd/` subpath, a different HOST, or a
combination, and a naive `go install github.com/<org>/<repo>@latest` fails or silently builds
an abandoned major.
Verified against each project's own `go.mod`, and these are the exact strings the fleet's
`bootstrap.sh` files already pass to `_dotfiles_go_install`:

| Tool    | `go install <path>@latest`            |
| ------- | ------------------------------------- |
| `doggo` | `github.com/mr-karan/doggo/cmd/doggo` |
| `sesh`  | `github.com/joshmedeski/sesh/v2`      |
| `yq`    | `github.com/mikefarah/yq/v4`          |
| `shfmt` | `mvdan.cc/sh/v3/cmd/shfmt`            |
| `gron`  | `github.com/tomnomnom/gron`           |
| `glow`  | `charm.land/glow/v3`                  |

**Charm's tools moved off GitHub as a module host** — `glow` is now `charm.land/glow/v3`
(v3.0.0, 2026-08-11) and `gum` is `charm.land/gum/v2` (v2.0.0). Both still _live_ on GitHub;
only the module path changed. #431 reported `github.com/charmbracelet/glow/v2`, which was
right when it was filed and is now two majors stale — a good reason to re-read `go.mod`
rather than trust a remembered path. **`dotfiles-Alpine` go-installs `glow`** — `glow` is
`testing`-only on Alpine¹⁴, so `go install` is its real source there, and that call carried the
stale `github.com/charmbracelet/glow/v2` until dotfiles-Alpine#122 moved it to
`charm.land/glow/v3`. It resolved either way, which is precisely how it went unnoticed:
`@latest` on the old path quietly pins the newest **v2** tag instead of failing. `gum` is
go-installed by no `bootstrap.sh` (the Debian/Kali cells use Charm's apt repo, see ¹⁵), so that
one is for the reader installing by hand.

³² direnv: per-directory environment loader — **Core wires it but neither installs nor
detects it.** There is no `HAVE_DIRENV` and no alias: `_cache_eval` already bails on an
absent binary, so the hook needs no flag to guard it. Since #581 `core-doctor` does carry a
**wired** row for it (probing `_direnv_hook`), but still no presence row — wiredness and
presence are different questions, and the latter is what would need detection. Since **v4.14.1**
the `direnv hook zsh` that makes it work lives in Core, at `zsh/00-tools.zsh` **band 00**,
where #449 pulled seven byte-drifted `os/*.zsh` copies up into one. Band 00 and not 45,
because it registers a hook rather than a compdef and band 00 loads under every
`CORE_PROFILE` while 45 is ceilinged out of `minimal`; filed under 45 it would silently stop
`.envrc` files loading on minimal hosts. (Since #579 the gh/uv/ty completions are generated
at band 00 too, but for a different reason — an `fpath` directory has to be populated before
`compinit` scans it — and they keep a `compdef` re-assert at band 45.) It is sourced **last** of the
four inits on purpose: direnv prepends `_direnv_hook` to `precmd_functions` and
`chpwd_functions`, so sourcing it after mise reproduces the order these hooks had at band 80
— direnv's per-directory env resolves before mise's, which is what an `.envrc` that pins tool
versions expects. An OS repo that still carries the old band-80 block is harmless but
redundant, and drops out on its next Core sync.

Core's other stake is `starship/starship.toml`'s **`[direnv]` module**, which Core switches on
(`disabled = false`; starship ships this module **off** by default): it renders `.envrc` state
on the `srf1` band so a directory waiting on `direnv allow` is visible rather than silently
unloaded. The module only draws inside a direnv-controlled tree, so a box without the binary
loses a segment, not the prompt.

**Installed, not merely available** — the inverse of ²¹. Six of the seven package lists carry
it outright (`dotfiles-Arch`, `-openSUSE`, `-Alpine`, `-Debian`, `-Fedora`, and the MacBook
`Brewfile`), and `dotfiles-Gentoo` emerges `app-shells/direnv` in its `guru_install` pass per
¹². **`dotfiles-Offense` (Kali) is the single gap, and it is structural rather than a call
about direnv**: that repo carries no `install/packages.txt`, so nothing there installs the
package. It does now get the **hook** — that arrives from Core at band 00 like everywhere
else, which is a change from the band-80 arrangement, where Offense missed it too for having
no `os/` layer at all. So the hook is live there and simply finds no binary. The Kali cell
above is the apt name you would install by hand.

Verified 2026-08-21 against each distro's own index: **Arch `extra`** 2.37.1-1, **Alpine
`community`** 2.37.1-r7 (v3.24 — a Go binary, so a native musl build), **openSUSE** Tumbleweed
2.37.1 with **Leap 16.0 and 16.1 both at 2.34.0** through Backports (`bp160.1.13` /
`bp161.1.9`, both arches), **kali-rolling** 2.37.1-1, **Ubuntu 24.04 `universe`**
2.32.1-2ubuntu0.24.04.3 and **Debian trixie** 2.32.1-2+b16. **Gentoo is GURU-only** — 2.37.1,
`~amd64 ~x86`, no `::gentoo` atom and no `dev-util/direnv`; see ¹². Where unpackaged, the
module path is `github.com/direnv/direnv/v2` — the `/v2` is not optional, the ³¹ trap again.

One version line, because it is the only place a frozen archive touches Core: starship runs
`direnv status --json`, and **the `--json` flag is silently ignored below direnv 2.33.0** —
starship's own `src/modules/direnv.rs` says exactly that and falls back to parsing the text
output. Every target above clears that floor except `dotfiles-Debian`'s two lanes, both on
2.32.1. It degrades rather than breaks, which is why that repo's `install/packages.txt`
declares no `# min:` floor for it.

³³ **neovim — "the package exists" is not "the package is usable", and Gentoo is the
SECOND target where that bites.** Core's nvim pins nvim-treesitter to `main`
(`nvim/lazy-lock.json`), which hard-requires **Neovim 0.12**. Two cells in the neovim
row above resolve perfectly and give you something Core's config will not load on:

| Target        | What `neovim` actually gets you       | Clears 0.12? |
| ------------- | ------------------------------------- | ------------ |
| **Debian**    | Ubuntu 24.04 `neovim` **0.9.5**       | no — see ²⁸  |
| **Gentoo**    | newest **stable** ebuild, **0.11.7**  | no           |
| Gentoo, fixed | **0.12.3**, via the `>=` keyword line | yes          |

The two get there by different mechanisms and only one of them looks like a problem.
Debian's is a **frozen archive**: the version is simply old, `apt` says so, and
`dotfiles-Debian` declares a `# min:0.12.0` floor its CI enforces. Gentoo's is
**keywords**: 0.12.0–0.12.3 are all in `::gentoo` right now, all `~arch`, so a stable
profile silently picks 0.11.7 and reports success. Nothing in an availability check can
see it — the atom exists, installs, and is the wrong version.

`dotfiles-Gentoo` therefore borrows Debian's contract and pairs it with the Portage-native
fix: `# min:0.12.0` next to the atom in `install/packages.txt`, a **version-restricted**
`>=app-editors/neovim-0.12.0 ~__ARCH__` in `gentoo/package.accept_keywords` (restricted so
0.11.x keeps tracking stable), and a check in `scripts/check-packages.sh` that fails when a
declared floor is not reachable. Filed as dotfiles-Gentoo#116, verified 2026-08-23.

**If you stamp a new source-based or stable/testing-split target, ask the keyword question,
not just the name question.** Every other column here is rolling, which is why this trap has
only ever shown up on the fleet's two non-rolling lanes.

³⁴ **jq — a recorded security floor of ≥ 1.8.2, and deliberately NOT a version gate.**
1.8.2 (2026-06-20) fixes **16 CVEs** — heap and stack overflows, out-of-bounds reads, an
integer overflow, a use-after-free, and a hash-collision DoS. Every one of them is reachable
**through parsing input**, which is the entire job of the tool. That matters here because jq
is pointed at output produced by machines other than yours: Core sets `HAVE_JQ`
(`zsh/00-tools.zsh`) and this file prescribes `jq -e '.detection.missed == []'` as the
provisioning gate a role layer runs against `core-doctor --json` ²⁰.

Fleet position at the time of writing: **at or above the floor** on Arch, Gentoo, openSUSE
Tumbleweed, Homebrew and Alpine edge. **Below it** on Alpine 3.22/3.23/3.24 and Fedora 43/44
(1.8.1), Debian 13 / Ubuntu 24.04 (1.7.1), and Leap 15.x (1.6).

**Do not build a guard on `jq --version`.** On the Debian family the version string is not
evidence either way — Debian backports security fixes without bumping the version, so a
`1.7.1-x` build may carry all, some or none of these, and a version gate would false-positive
across the whole Debian/Kali/Ubuntu lane. This is a third shape, distinct from the two other
version-sensitive rows in this file, and the distinction is the point: `⁵` (tree-sitter)
mandates a **version** check because apk is honestly old, and `²²` (`sd`) forbids one and
mandates **capability probing** because `--version` lies. jq's version is neither honest nor
probeable — nothing in the CLI surface reveals which patches a build carries. So this is a
floor you _record_ and act on when provisioning, not one you can detect from the shell.

Core itself is unaffected: nothing in Core shells out to jq (`HAVE_JQ` is detect-only, no
alias — the same shape as `gron`/`sd`). This is a note for the role layers and for anyone
piping untrusted JSON through a distro jq.

³⁵ Fedora `refresh` is `dnf check-update`, and it is **not really a refresh** — dnf has no
standalone index-refresh verb. Refreshing is a _flag_ on the verb that needs it
(`dnf upgrade --refresh`), which is why the Fedora `upgrade` and `count-pending` cells both
carry it and why `os/fedora.capabilities` declares no `PKG_UPGRADE_PRE`. The schema calls
`PKG_REFRESH` "may be a no-op verb" for exactly this case.

³⁶ macOS `count-pending` is two commands, and it is the only archive where that is true.
`brew outdated` reports against the **locally cached** formula index, so without a `brew
update` first it reports a stale set — sometimes empty on a box with dozens of upgrades
pending. That is what the optional `PKG_COUNT_REFRESH` key exists for. Core runs it on the
**count** path only: the _list_ path (`up`'s pre-confirm preview) deliberately skips it,
because the once-a-day nudge that produced the count already paid for the network.

³⁷ Gentoo `count-pending` **is** the real dependency calculation, and it is the one cell
here that cost a measurement to get right (#753 → #756). The obvious answer is `eix -u`,
which is what Core shipped: it is fast and it reads its own cache. It also answers the
wrong question. `eix -u` asks "is a higher version present in the tree?"; `up` runs
`emerge -uDN @world`, which asks "what will actually change?" — and on a healthy box those
diverge permanently. Measured on a real machine: eix said 70 where emerge merged 8, and
after a full update **and** a depclean eix still said 2 against emerge's 0. Three causes,
only the first of which an operator can ever clear — orphans (installed but no longer
reachable from `@world`), **slots** (the newest thing in SLOT 5.1 is not the newest across
all slots), and **consumer pins** (a dependent pinning `=cat/pkg-1.2*` the resolver will
not move past). The last two never clear, so no filter over eix's output fixes this; only
the resolver knows.

The cost is real and was weighed rather than assumed: ~10s against eix's 0.25s. The caller
that pays it is throttled to once a day and runs disowned, so it never blocks a prompt, and
`up`'s foreground use already sits behind a spinner. A once-a-day background resolve is
affordable; a nudge that **cannot reach zero on a healthy box** is not, because it stops
being a signal that anything needs doing. Root is not needed (`--pretend` installs nothing)
and it takes no merge lock, so it is safe beside a real emerge.

A failed resolve must report the `-1` **unknown** sentinel, never 0 — a box whose Portage
cannot resolve is not a box with nothing to do. That is what the optional
`PKG_COUNT_EXIT_TRUSTED` key is for, and Gentoo is the only archive that declares it: most
overload the exit status of their count verb (dnf exits 100 when updates _exist_; `pacman
-Qu` and `checkupdates` exit non-zero when there are _none_), so Core ignores it by default.
³⁸ macOS `owns-file` has no good answer and the cell is the least trustworthy in the table.
`brew which-formula` maps a **command name** to the formula providing it, which is not the
same question as "which package owns this path" that every other column answers. Homebrew
has no path-ownership index; the nearest real equivalent is grepping the install receipts
under the Homebrew prefix, which is neither a stable interface nor something Core may name.
Treat this cell as "the closest available", and prefer not to build a gate on it.

## Clipboard packages to install (backends for Core's `clip`)

<!-- Clipboard selection lives in Core's cross-OS clip/clip-paste scripts; each
     os/<distro>.zsh only aliases pbcopy/pbpaste to them — no distro swaps a
     backend in its zsh layer. This table is the packages each backend needs. -->

> **This table is deliberately NOT an `os.capabilities` source, unlike the
> package-manager table above.** #667 listed it as one; #663 had already decided
> otherwise and the schema has no clipboard key, so
> `scripts/check-capabilities.sh` rejects one. The reason is in
> `zsh/02-capabilities.zsh`: `bin/clip` is re-exec'd by nvim and tmux on **every
> yank and paste**, and its WSL probe was already rewritten once to avoid forking
> a `grep` per invocation. Adding a file read and parse to that path would give
> back exactly what that bought — for a value that changes once per machine.
> The ladder stays hardcoded. Do not re-open this without a measurement.

| Distro        | Wayland                                      | X11 fallback                                                                                                                                                                                                                                                                                                                                                                                                                         |
| ------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Arch          | `wl-clipboard` (`wl-copy`/`wl-paste`)        | `xclip`                                                                                                                                                                                                                                                                                                                                                                                                                              |
| openSUSE      | `wl-clipboard`                               | `xclip`                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Alpine        | `wl-clipboard`                               | `xclip` / `xsel` (often headless — may be neither)                                                                                                                                                                                                                                                                                                                                                                                   |
| Gentoo        | `gui-apps/wl-clipboard`                      | `x11-misc/xclip`                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Kali (WSL2)   | n/a — Core's `clip` shells out to `clip.exe` | `wl-clipboard`/`xclip` install but sit inert under WSL                                                                                                                                                                                                                                                                                                                                                                               |
| Debian/Ubuntu | `wl-clipboard`                               | `xclip` — but `dotfiles-Debian` installs **neither**: it targets headless SSH-only boxes, so `clip` has no _local_ backend. Since **v4.13.0** it falls back to OSC 52 — the terminal you are sitting at puts the payload on its own clipboard, with nothing installed on the remote end — and since #525 it also reaches tmux's server-side buffer, which is the path `copy-pipe` needs. See its README's _Headless clipboard_ note. |

## Distro quirks worth a README note (and that will actually bite you)

**Arch** — Rolling release; update often or not at all (partial upgrades break
things — never `-Sy <pkg>` without `-u`). Most modern tools are in official
repos; the rest are one `paru -S` away in the AUR. Enable `multilib` if you'll
run 32-bit/Wine tooling. Cleanest distro for this stack.

**openSUSE** — Two flavors, and the update command differs: **Tumbleweed**
(rolling) uses `zypper dup`, **Leap** (stable) uses `zypper up`. Get this wrong
and you either don't update or you half-update. Add the **Packman** repo (the
openSUSE analog to RPM Fusion) for codecs. `zypper` has the best dependency
solver of any of these — lean on it.

**Alpine** — The real outlier: **musl libc, not glibc.** Prebuilt binaries
linked against glibc (some `cargo`-less installer scripts, some vendor blobs)
**will not run** — prefer `apk` packages or musl-target builds. Default shell is
`ash` (busybox), default privilege tool is `doas` (not `sudo`), and many
"classic" commands are busybox applets with fewer flags. This is your
small-footprint / container / rescue-disk distro — keep its layer lean and don't
fight the musl grain.

**Gentoo** — Source-based: `emerge` **compiles** packages, so expect real build
time (mitigate with binary packages via a binhost, and tune `MAKEOPTS`). **USE
flags** gate features at compile time — this is the whole point of Gentoo and
where the learning is. Tool _names_ are full atoms (`category/name`). Treat this
repo as your "understand the system from the ground up" build; it's the most
educational and the most time-expensive.

**Offense (Kali / WSL2)** — The one repo that isn't stamped from Fedora: it's Debian-family
(apt) and carries a unique **offensive role layer** on top of the usual OS layer,
adding an `offensive` stage to the zsh loader (`… os offensive local`). Two things
actually bite. (1) Debian renames binaries — `bat`→`batcat`, and the `fd-find`
package installs `fdfind`; Core handles both. (2) **WSL2 is NAT'd**, so a listener
or reverse shell in Kali isn't reachable from your LAN until you enable **mirrored
networking** — which lives in the _Windows-side_ `%UserProfile%\.wslconfig`
(`networkingMode=mirrored`, Win11 22H2+), **not** `/etc/wsl.conf`. Keep all
engagement data in `~/engagements` (outside the repo); the repo ships a paranoid
`.gitignore` as backup.

**Debian/Ubuntu** — the fleet's only **frozen** target, and that is the whole
character of the repo. `dotfiles-Debian` aims at **Ubuntu 24.04 LTS** (April 2024)
while proving `debian:trixie` in CI, so unlike every rolling sibling, "apt has it" is
not the same question as "apt has a version Core can use". Two packages resolve
perfectly and break the stack: **neovim** (noble 0.9.5 vs the 0.12 that
nvim-treesitter's `main` hard-requires — ³³ tabulates this against Gentoo, which
reaches the same wrong version by a different route) and **tree-sitter-cli** (noble
0.20.8 vs the 0.26.1 floor in footnote ⁵ — no Debian/Ubuntu suite short of sid clears it). Its
`install/packages.txt` therefore declares `# min:` floors that CI enforces, and a
dozen tools come from pinned upstream assets instead (²⁸). Three more traps:
**`yq`** in apt is kislyuk's _Python_ tool, and the Go build (`yq-go`) is sid-only, so
neither name is safe to list; **`cargo`** is 1.75, too old to build yazi/ast-grep/viddy,
which are simply not installed (²⁹); and **`needrestart`**, preinstalled on Ubuntu
Server, interposes on apt with a full-screen prompt that `DEBIAN_FRONTEND` does _not_
suppress — an unattended bootstrap over SSH hangs forever without `NEEDRESTART_MODE=a`.
Vendor-signed apt repos (Charm, 1Password) are used where upstream offers them; **PPAs
are not**, because they are keyed to an Ubuntu series and would break the Debian lane.

---

### Repo status

- **Built:** `core`, `Fedora` (template), `MacBook`, `Arch`, `Debian`, `openSUSE`,
  `Alpine`, `Gentoo`, `Offense`, `Defense`. That is the nine Core-vendoring repos
  (`scripts/os-repos.txt`) plus `core` itself; `Windows` vendors no `core/` and is
  tracked separately.
- **Stamp-pending (this doc):** none — all five template stamps are complete.
- `Offense` (apt + offensive layer) and `MacBook` (Homebrew) are their own lineages,
  built directly rather than stamped from Fedora. `Windows` is tracked separately
  from this matrix.
- **Role repos:** `Offense` (offensive) and `Defense` (defensive) both vendor
  Core. `Offense` **used to** carry its own OS-native layer (Debian/apt,
  kali-rolling) and no longer does: it shed `os/`, `install/packages.txt` and
  `scripts/tool-versions.env` entirely, and the Kali package lane moved to
  `dotfiles-Debian`'s `only:kali` tier — so that repo is now a first-class
  ubuntu/debian/**kali** target rather than a frozen-Ubuntu-LTS one, and `Offense`
  is a pure role layer. `Defense` is
  **distro-agnostic** — it stacks its blue-team stage on whatever OS-native layer is
  underneath — so it has no row in this OS-stamp matrix by design, not by omission.
  Both role repos source the shared bootstrap scaffold (`lib/bootstrap-lib.sh`) and
  call `blib_link_core` exactly as the OS repos do. Where they differ is the `80`
  band, which belongs to the OS repo underneath: the contract is that a role repo
  skips `blib_link_os_layer` and calls `blib_link_role_layer` instead, wiring the
  `85` band and `tmux/role.conf`. **`Offense` has adopted it**; `Defense` has not —
  it still hand-rolls the band in its own `wire_defense_stage`, and migrating it is
  what remains. Deliberate, not drift — `core.manifest` records the same split.
- `Debian` is stamped from Fedora structurally, but takes its **apt idioms** from
  `Offense` — the fleet's other Debian-family repo. It is the only **frozen** target
  (Ubuntu 24.04 LTS), which is why it carries by far the largest out-of-band install
  surface (²⁸) and the only version-floor gate in the fleet.

### Stamping order (all complete — kept as the recommended sequence for reference)

1. **Arch** ✓ — almost everything is in-repo; closest to Fedora effort.
2. **openSUSE** ✓ — straightforward once you internalize `dup` vs `up`.
3. **Alpine** ✓ — forces you to reason about musl and minimalism (great for the
   container/rescue skills a red-teamer wants).
4. **Gentoo** ✓ — the capstone; USE flags + source builds teach you the most.
5. **Debian/Ubuntu** ✓ — added last, and the one that breaks the pattern: the
   structure ports cleanly, but a frozen LTS means the interesting work is deciding
   what apt can honestly supply and pinning the rest. Read its `CLAUDE.md` before
   changing `install/packages.txt`.
