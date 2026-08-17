# Distro Porting Matrix

How to stamp `dotfiles-Arch`, `dotfiles-openSUSE`, `dotfiles-Alpine`, and
`dotfiles-Gentoo` from the `dotfiles-Fedora` template. The structure is identical
every time — only three things change per distro: **package manager commands**,
**package names**, and **distro quirks**. Core never changes (it's vendored).
Kali and macOS appear in the reference tables below for convenience, but they're
their own lineages — built directly, **not** stamped from this template (see
_Repo status_ at the bottom).

## Per-repo recipe

1. `cp -r dotfiles-Fedora dotfiles-<Distro>`
2. Rename `os/fedora.zsh` → `os/<distro>.zsh`; swap clipboard + pkg-manager aliases.
3. Replace `install/packages.txt` with that distro's names (table below).
4. In `bootstrap.sh`: swap the `dnf` block for the distro's installer and the
   `/etc/os-release` guard string.
5. `git subtree add --prefix=core <dotfiles-core> main --squash`
6. Update the README's "specifics" section to that distro's quirks.

## Package-manager commands

| Action    | Arch                     | openSUSE                                         | Alpine                    | Gentoo                          | Kali (apt)                   |
| --------- | ------------------------ | ------------------------------------------------ | ------------------------- | ------------------------------- | ---------------------------- |
| refresh   | `sudo pacman -Sy`²³      | `sudo zypper refresh`                            | `doas apk update`         | `sudo emerge --sync`            | `sudo apt-get update`        |
| upgrade   | `sudo pacman -Syu`       | Leap: `zypper up` · **Tumbleweed: `zypper dup`** | `doas apk upgrade`        | `sudo emerge -uDN @world`       | `sudo apt-get full-upgrade`  |
| install   | `sudo pacman -S <pkg>`   | `sudo zypper in <pkg>`                           | `doas apk add <pkg>`      | `sudo emerge <atom>`            | `sudo apt-get install <pkg>` |
| remove    | `sudo pacman -Rns <pkg>` | `sudo zypper rm <pkg>`                           | `doas apk del <pkg>`      | `sudo emerge --depclean <atom>` | `sudo apt-get remove <pkg>`  |
| search    | `pacman -Ss <term>`      | `zypper se <term>`                               | `apk search <term>`       | `emerge -s <term>`              | `apt-cache search <term>`    |
| owns-file | `pacman -Qo <path>`      | `zypper se --provides <f>`                       | `apk info --who-owns <f>` | `equery belongs <path>`         | `dpkg -S <path>`             |

## Package names (modern CLI stack)

| Tool             | Arch              | openSUSE     | Alpine            | Gentoo (atom)              | Kali (apt)        |
| ---------------- | ----------------- | ------------ | ----------------- | -------------------------- | ----------------- |
| eza              | `eza`             | `eza`        | `eza`             | `sys-apps/eza`             | `eza`             |
| bat              | `bat`             | `bat`        | `bat`             | `sys-apps/bat`             | `bat`⁴            |
| fd               | `fd`              | `fd`         | `fd`              | `sys-apps/fd`              | `fd-find`⁴        |
| ripgrep          | `ripgrep`         | `ripgrep`    | `ripgrep`         | `sys-apps/ripgrep`         | `ripgrep`         |
| zoxide           | `zoxide`          | `zoxide`     | `zoxide`          | `app-shells/zoxide`        | `zoxide`          |
| fzf              | `fzf`             | `fzf`        | `fzf`             | `app-shells/fzf`           | `fzf`             |
| git-delta        | `git-delta`       | `git-delta`  | `delta`           | `dev-util/git-delta`       | `git-delta`       |
| btop             | `btop`            | `btop`       | `btop`            | `sys-process/btop`         | `btop`            |
| tldr             | `tealdeer`        | `tealdeer`¹  | cargo³            | `app-misc/tealdeer`¹²      | `tealdeer`        |
| neovim           | `neovim`          | `neovim`     | `neovim`          | `app-editors/neovim`       | `neovim`          |
| lazygit          | `lazygit`         | `lazygit`    | `lazygit`         | `dev-vcs/lazygit`¹²        | `lazygit`²¹       |
| zsh              | `zsh`             | `zsh`        | `zsh`²            | `app-shells/zsh`           | `zsh`             |
| tmux             | `tmux`            | `tmux`       | `tmux`            | `app-misc/tmux`            | `tmux`            |
| starship         | `starship`        | `starship`¹⁸ | `starship`        | `app-shells/starship`      | script³           |
| atuin²⁰          | `atuin`           | `atuin`¹⁸    | `atuin`           | `app-shells/atuin`         | `atuin`³          |
| yazi             | `yazi`            | `yazi`¹⁸     | `yazi`            | `app-misc/yazi`¹²          | cargo³            |
| tree-sitter-cli⁵ | `tree-sitter-cli` | cargo³       | `tree-sitter-cli` | cargo³                     | `tree-sitter-cli` |
| jq               | `jq`              | `jq`         | `jq`              | `app-misc/jq`              | `jq`              |
| yq⁶              | `go-yq`           | go³          | `yq-go`           | `app-misc/yq-go`           | `yq-go`           |
| duf              | `duf`             | `duf`        | testing¹⁴         | `sys-fs/duf`               | `duf`             |
| dust             | `dust`            | `dust`       | `dust`            | `sys-block/dust`           | `du-dust`⁴        |
| procs            | `procs`           | `procs`      | `procs`           | `sys-process/procs`        | `procs`           |
| viddy¹⁶          | AUR¹⁶             | `viddy`¹⁸    | `viddy`           | cargo³                     | cargo³            |
| sd²²             | `sd`              | `sd`         | `sd`              | `sys-apps/sd`¹²            | `sd`              |
| gron             | `gron`            | `gron`       | `gron`            | go³                        | `gron`            |
| jnv¹⁷            | AUR               | cargo        | cargo             | cargo                      | cargo             |
| lnav²¹ ²⁴        | `lnav`            | `lnav`       | `lnav`            | `app-admin/lnav`²⁴         | `lnav`²⁴          |
| glow             | `glow`            | `glow`       | testing¹⁴         | `app-misc/glow`¹²          | `glow`¹⁵          |
| gum              | `gum`             | `gum`        | `gum`             | `app-misc/gum`¹²           | `gum`¹⁵           |
| xh               | `xh`              | `xh`         | `xh`              | `net-misc/xh`¹²            | `xh`              |
| doggo            | `doggo`           | `doggo`¹⁸    | `doggo`           | `net-dns/doggo`            | go³               |
| gping¹⁹          | `gping`           | `gping`¹⁹    | `gping`           | GURU¹⁹                     | `gping`¹⁹         |
| carapace         | AUR²⁷             | rpm²⁷        | `carapace`        | `app-shells/carapace`¹²    | deb²⁷             |
| op (1Password)¹³ | AUR               | vendor rpm   | vendor apk        | GURU¹²                     | vendor apt        |
| hyperfine²¹      | `hyperfine`       | `hyperfine`  | `hyperfine`       | `app-benchmarks/hyperfine` | `hyperfine`       |
| watchexec²¹ ²⁵   | `watchexec`       | `watchexec`  | `watchexec`       | GURU²⁵                     | cargo²⁵           |
| shellcheck²¹     | `shellcheck`      | `ShellCheck` | `shellcheck`      | `dev-util/shellcheck`      | `shellcheck`      |
| shfmt⁷ ²¹        | `shfmt`           | `shfmt`      | `shfmt`           | go²¹                       | `shfmt`⁷          |
| ouch²¹           | `ouch`            | `ouch`¹⁸     | testing¹⁴         | cargo²¹                    | cargo²¹           |
| jujutsu (jj)⁸    | `jujutsu`         | `jujutsu`    | `jujutsu`         | cargo²¹                    | cargo²¹           |
| sesh⁹            | AUR⁹              | go⁹          | go⁹               | go⁹                        | go⁹               |
| difftastic¹⁰     | `difftastic`      | `difftastic` | `difftastic`      | `dev-util/difftastic`      | `difftastic`      |
| git-absorb²¹ ²⁶  | `git-absorb`      | `git-absorb` | `git-absorb`      | `dev-vcs/git-absorb`       | `git-absorb`      |
| ast-grep¹¹       | `ast-grep`        | `ast-grep`¹⁸ | `ast-grep`        | cargo²¹                    | cargo³            |
| w3m              | `w3m`             | `w3m`        | `w3m`             | `www-client/w3m`           | `w3m`             |

¹ openSUSE: in Tumbleweed main OSS as `tealdeer` (also Leap 15.6); on older Leap, `cargo install tealdeer`.
² Alpine default shell is `ash`; you must `apk add zsh` explicitly.
³ Not packaged or stale → bootstrap.sh installs it best-effort (upstream
installer / `cargo install` / `go install` / AUR), the same pattern bootstrap
already uses on Fedora. Add `cargo`/`rust` (or a `go` toolchain) to packages.
`go install` targets land in `~/.local/bin` via `GOBIN` so they're on PATH.
**`carapace` is the one documented exception to the `go install` half of this** — that
module can never be `go install`ed, on any platform, so its cells point at ²⁷ instead.
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
**Arch:** `extra` carries 0.26.9 (clears the floor). Where unpackaged:
`mise use -g tree-sitter` or `cargo install tree-sitter-cli`. On **Alpine** the
`community` package **is** the musl build (0.26.7, clears the floor) — prefer it
over cargo/any prebuilt binary.
⁶ yq: this matrix targets **mikefarah's Go `yq`** (the jq-for-YAML). Distros also
ship **Python `yq`** (kislyuk) under the same `yq` name; if you land the wrong
one, install the Go build via `mise use -g yq` or the upstream release binary.
On **openSUSE** the main OSS `yq` is the kislyuk **Python** build (the Go build
only ships from a personal OBS repo), so `dotfiles-openSUSE` go-installs the
mikefarah build in `bootstrap.sh` (`go³`) rather than packaging the wrong `yq`.
⁷ shfmt: not always in stable apt (Debian/Kali), and **not packaged on Gentoo** —
absent from `::gentoo` and from GURU (third-party overlays carry it as
`dev-util/shfmt`; there is no `dev-go/shfmt` atom), so Gentoo takes the `go²¹`
path — by hand: no `bootstrap.sh` installs it. If the package is missing, `mise use -g shfmt` or
`go install mvdan.cc/sh/v3/cmd/shfmt@latest`. (These mid-2026 rows are
best-effort — verify the exact package on first stamp of each distro.)
⁸ jujutsu (jj): OPT-IN, additive git companion — never replaces git, so a box
without it just skips the HAVE_JJ-gated aliases. Packaged on Arch (`jujutsu`),
openSUSE (`jujutsu`), Fedora (`jujutsu`), Homebrew (`jj`), nixpkgs (`jujutsu`)
and Alpine (`community` — a native musl build); **not** in stable Debian/Kali
apt, and **not on Gentoo** — absent from `::gentoo` **and** from GURU — so both
take `cargo install --locked jj-cli`, the same cargo pattern as yazi/ouch. The
crate is **`jj-cli`**, not `jujutsu`: the `jujutsu` crate is a stub pinned at
0.7.2 whose own description reads "You don't want this crate - you want the
`jj-cli` crate", so `cargo install jujutsu` lands a redirect rather than the
VCS. As an opt-in tool it is availability-documented here but not carried in any
OS repo's `packages.txt` yet. The config (`jujutsu/config.toml`) is inert
without the binary.
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
`ripgrep` (text), `sd` (regex), and `gron` (JSON). Own command, **no alias** (like `gron`/`sd`),
so it shadows nothing; prefer the `ast-grep` binary name over `sg` (which can collide with
`setgroups`). Core sets `HAVE_ASTGREP` when present. Packaged on Arch (`extra`) and Alpine
(`community` — a musl build, so the outlier is covered) and Homebrew; elsewhere via
`cargo install ast-grep` / `mise` / `npm` / `pip`. Inert without the binary — nothing depends on it.
¹² Gentoo **GURU overlay** (`sd`, `glow`, `gum`, `xh`, `carapace`, `1password-cli`, `tealdeer`,
`yazi`, `lazygit`, `direnv`): not in the main `::gentoo` tree. Enable once with `eselect
repository enable guru && emaint sync -r guru`, then `emerge` the atom. bootstrap.sh does this
best-effort, per-atom (one masked atom doesn't block the rest), in its `guru_install` pass —
which runs AFTER the main-tree emerge, so these must not sit in the main `packages.txt` blocks
or they're skipped. direnv is `app-shells/direnv` (not `dev-util/direnv`, which does not exist);
verify `app-misc/gum`'s exact category on a synced tree.
¹³ op = **1Password CLI**. bootstrap.sh installs it from 1Password's official **signed** repo,
which differs per family: dnf/rpm repo (Fedora/openSUSE), apt repo (Debian/Kali), apk repo
(Alpine — a native musl build, so it's fine on the musl outlier), the AUR `1password-cli`
(Arch), and the GURU `app-misc/1password-cli` (Gentoo). A vendor repo, **not** the OS repo;
the apt/rpm setup is rollback-safe (a failed install removes the added repo entry).
¹⁴ Alpine **testing** repo (`duf`, `glow`, `ouch`): musl-fine tools that live in `testing` (never
promoted to `community` on stable, incl. 3.24), which isn't enabled by default on a stable
release. bootstrap.sh `go install`s them instead (static, musl-safe) rather than force-enabling
`testing`; they stay in `packages.txt` only as a best-effort that `apk add` skips.
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
`jq` needed). **On Linux this is detect-only — unlike the ³ tools, `jnv` is in no
`install/packages.txt` and no `bootstrap.sh` installs it, so Core lights up `HAVE_JNV` only
once you install it yourself. macOS is the exception: the `Brewfile` carries it.** The cells above name where each platform gets it when you opt in —
macOS `brew install jnv`, Arch `paru -S jnv` (AUR), Nix, or elsewhere `cargo install --locked
jnv` (musl-safe on Alpine) — not an automatic install. Wiring it into the per-repo bootstrap
(the ³ best-effort path viddy/yazi use) is a tracked follow-up in the OS repos; there is
no confirmed Gentoo GURU atom yet either, so verify on the next Gentoo stamp.

¹⁸ openSUSE **Tumbleweed** now ships these first-class in the main OSS **binary** repo
(`repo-oss`, i.e. `.../tumbleweed/repo/oss` — built from OBS `openSUSE:Factory`; note
`src-oss` is the _source_-RPM repo and is not what `zypper in` resolves against), so
`zypper in` beats the upstream-installer/cargo/go fallback these rows used to prescribe:
`starship`, `atuin`, `yazi`, `viddy`, `ouch`, `doggo`, `ast-grep`.
**Leap 15.x was not separately audited** and rolls slower — on Leap, verify with
`zypper se <pkg>` and fall back to the ³ path if it's absent. The rows are named for
Tumbleweed because that's the flavor this fleet targets.
Five of the seven (`starship`, `atuin`, `yazi`, `viddy`, `doggo`) are also installed by
`dotfiles-openSUSE`'s `bootstrap.sh`, which stays correct and harmless either way — each
install is presence-guarded, so a packaged binary just short-circuits it. **`ouch` and
`ast-grep` are not**: that bootstrap has no installer for them, so the old `cargo³` cells
promised a fallback that never existed and the package name above is their only automatic
path. Moving any of these into `install/packages.txt` is a separate judgment call — it
trades upstream-latest for the distro build — and is deliberately **not** done here; for
`ouch`/`ast-grep` it is the _only_ way to get them installed without doing it by hand.

¹⁹ gping: the `ping` replacement — Core aliases `ping`→`gping` (`HAVE_GPING`-guarded in
`zsh/20-aliases.zsh`), so a box without the binary just keeps classic `ping`. **Detect-only on
Linux, like `jnv`¹⁷: gping is in no Linux repo's `install/packages.txt` and no `bootstrap.sh`
installs it — the macOS `Brewfile` does carry it**,
so the alias only lights up once you install it yourself — this row exists so there is a
documented path when you do. (`aliases.md` and `PARITY.md` have advertised the alias since
v3; the matrix row is what was missing.) A **Rust** CLI → `cargo install gping` anywhere
unpackaged. Packaged: Arch `extra`, Alpine `community` (a native musl build, so the outlier is
covered), Homebrew (`gping`), nixpkgs, and Debian/Kali apt — where the **source** package is
`rust-gping` but the **binary** you install is plain `gping` (Debian trixie 1.19.0, sid/Kali
rolling 1.20.4). openSUSE: **Leap 15.6** carries it first-class in `main/oss` but well behind
(1.16.1); **Tumbleweed** builds it from Factory, so verify with `zypper se gping` and fall back
to cargo if your snapshot lacks it. Gentoo is **GURU-only** (`net-analyzer/gping`) — there is
no main-tree atom, and unlike the ¹² atoms `bootstrap.sh` does **not** emerge it, so enable
GURU per ¹² and `emerge net-analyzer/gping` by hand. Inert without the binary; nothing depends on it.

²⁰ atuin **daemon mode** — the one part of the atuin story that is NOT Core's to decide.
Core ships `atuin/config.toml` (symlinked to `~/.config/atuin/config.toml`) with the
`[daemon]` block **off**; the daemon owns the SQLite writes so shells stop contending for
the DB lock, which is where atuin's tail latency comes from on a busy multi-pane box. What
differs per machine is how the daemon gets **launched**, so that half lives in the OS repo:

| Machine                                                      | How the daemon runs                                                                                                                                                                                                              | What the OS layer exports                                     |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Fedora✔ · Arch · openSUSE · Gentoo (systemd) · Kali          | `systemd --user` unit — copy `examples/atuin-daemon.service` into `~/.config/systemd/user/`, then `systemctl --user enable --now atuin-daemon` (and `loginctl enable-linger $USER` if you want it alive outside a login session) | `ATUIN_DAEMON__ENABLED=true`                                  |
| Alpine✔ (musl, no systemd)                                   | atuin supervises its own daemon — no unit, no service manager, nothing to install                                                                                                                                                | `ATUIN_DAEMON__ENABLED=true` + `ATUIN_DAEMON__AUTOSTART=true` |
| macOS                                                        | same as Alpine: `autostart` beats hand-writing a launchd plist, and `XDG_RUNTIME_DIR` is unset there so the socket lands in the data dir — which atuin resolves itself                                                           | `ATUIN_DAEMON__ENABLED=true` + `ATUIN_DAEMON__AUTOSTART=true` |
| Windows                                                      | out of scope — `dotfiles-Windows` vendors no `core/` and replicates its host config in PowerShell                                                                                                                                | —                                                             |

The exports belong in that repo's `os/<os>.zsh` (loader fragment 80), **never** in the Core
config: Core is vendored identically to every repo, so a per-machine value there would be
wrong on the other seven. `autostart` is mutually exclusive with `systemd_socket = true` —
pick the unit or pick autostart, not both.

**✔ marks the machines where the exports are actually wired today — Fedora and Alpine, two
of the seven Core-vendoring machines this table covers.** The marker is per **machine**, not
per row: the systemd row holds a wired Fedora alongside four unwired ones. For the other
five — Arch, openSUSE, Gentoo and Kali (sharing that row with Fedora) plus macOS — the cell
is the documented recipe, not a shipped state, so follow the rollout order below (Fedora
first as the template, Alpine second as the design's real constraint, then the rest) rather
than assuming your repo already does this. The `Windows` row is neither wired nor pending:
it is out of scope, vendoring no `core/` at all. **`Defense` has no row here by design** —
it is distro-agnostic and carries no `os/` layer, so its atuin exports come from whichever
OS repo is underneath it (see "Repo status"). Seven machines + `Defense` = the eight
Core-vendoring repos in `scripts/os-repos.txt`.

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

²¹ **Available, not installed** — the same detect-only shape as `jnv`¹⁷ and `gping`¹⁹, and
the counterpart to ³. These cells name where the tool comes from **when you opt in**; no
Linux repo's `install/packages.txt` carries it and no `bootstrap.sh` installs it, so Core
lights the `HAVE_*` probe only once you install it yourself.

- `hyperfine`, `shellcheck`, `shfmt`, `ouch`, `lnav`²⁴, `git-absorb`²⁶ are **macOS-only in
  practice**: the MacBook `Brewfile` carries them; **no** Linux repo does. The packaged
  names in their rows are what you would install by hand, not what a bootstrap gives you.
  (Deliberately not a counted list — "all four" went stale the first time this family grew.)
- The cells that previously showed **³** here — `ouch` and `jujutsu` on Gentoo **and** Kali,
  `ast-grep` and `shfmt` on Gentoo, `lazygit` on Kali — promised a best-effort bootstrap
  install that **does not exist**, verified against each repo's `bootstrap.sh` and
  `install/packages.txt`. `lazygit` is the sharpest case: every other Linux repo installs it,
  Kali installs it nowhere, and Core ships `alias lg='lazygit'` regardless.
- Kali **does** install `ast-grep` (`bootstrap.sh`, cargo best-effort), which is why that one
  cell keeps its ³ while its Gentoo neighbour does not.

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

²³ Arch `refresh` (the **Package-manager commands** table above) is listed for
completeness — **`dotfiles-Arch` deliberately ships no alias for it.** A bare
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
**Detect-only on Linux, like `jnv`¹⁷ and `gping`¹⁹**: it is in no Linux repo's
`install/packages.txt` and no `bootstrap.sh` installs it, so Core lights `HAVE_LNAV` only
once you install it yourself. **macOS is the exception — the MacBook `Brewfile` carries
it** (added 2026-07-15), which puts `lnav` squarely in ²¹'s "macOS-only in practice" family
rather than jnv's "barely packaged anywhere" one: every distro in the table above ships it,
none of them installs it for you.

Versions **verified against each distro's own package pages** on 2026-08-12, not taken from
a repology snapshot. Upstream is 0.14.0 (2026-04-12). Rolling targets get one query each,
because that query is the complete answer; **Fedora is versioned, so every supported stable
release is named separately** rather than collapsed into one unqualified ✓:

| Target | Release | lnav |
| --- | --- | --- |
| Arch | `extra` (rolling) | 0.14.0-1 |
| openSUSE | Tumbleweed (rolling) | 0.14.0 |
| Alpine | `edge/community` — **native musl build** | 0.14.0-r0 |
| Homebrew | rolling | 0.14.0 |
| **Fedora** | **Rawhide / F45** | **0.14.0-3.fc45** |
| **Fedora** | **F44** | **0.13.2-2.fc44** |
| **Fedora** | **F43** | **0.12.4-2.fc43** |
| **Kali/Debian** | rolling / sid | **0.13.2** |
| **Gentoo** | `app-admin/lnav` | **0.11.2** |

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

**The only tool in this table that nothing in the fleet installs — including macOS.**
Unlike `lnav`²⁴ and the rest of ²¹'s "macOS-only in practice" bullet, the MacBook
`Brewfile` does not carry `watchexec` either, so every machine is opt-in. Availability,
verified 2026-08-12:

- **Arch `extra`, openSUSE Tumbleweed, Homebrew, nixpkgs** — 2.5.1, current.
- **Alpine `community`** — 2.5.1-r0, a native musl build.
- **Gentoo: GURU only**, at 2.5.0 — there is no `::gentoo` atom. Note this is **not** in
  ¹²'s GURU list on purpose: that footnote enumerates what `dotfiles-Gentoo`'s
  `guru_install` pass actually installs, and it does not install this. Same shape as
  `gping`¹⁹'s `GURU¹⁹` cell.
- **Fedora and Debian/Kali do not package it at all** (confirmed: Fedora's package search
  returns no results across F43/44/45/Rawhide/EPEL). Those two take
  `cargo install --locked watchexec-cli` — note the crate is **`watchexec-cli`**; plain
  `watchexec` on crates.io is the library, and installing that gives you no binary.

Do **not** read the `cargo` cells as a `³`: no `bootstrap.sh` installs this, and
`maint/dotfiles-maint.sh` runs `rustup update` but has no `cargo install-update` step, so
a hand-`cargo`-installed `watchexec` is never refreshed by the maintenance job. That is
already true of `ouch`/`jj`/`ast-grep` — a documentation gap this footnote records rather
than a new one.

²⁶ git-absorb: OPT-IN — works out which earlier commit each **staged hunk** belongs to and
writes the `fixup!` commits for you; `git rebase -i --autosquash` then folds them in, and
`git/gitconfig` already sets `rebase.autosquash = true`, so the second half is automatic.
It is the **automatic** counterpart to `git fix` (`commit --fixup`, `git/gitconfig`'s
`[alias]` block), which is the **manual** form: with `git fix <sha>` you name the target
commit yourself, and `git absorb` works one out per hunk. Reach for `git fix` when you know
where a change belongs and `git absorb` when you would otherwise go looking.

**The house-style ideal for a new tool: it needs no alias at all.** git-absorb installs as
`git-absorb` on `PATH`, which git dispatches as the `git absorb` subcommand — so it shadows
nothing classic and `zsh/20-aliases.zsh` gains no entry, only a note saying why.
`HAVE_GIT_ABSORB` exists purely so `core-doctor` can report it. One detection caveat: the
probe is `command -v git-absorb`, so a distro that installs the binary into git's
`libexec/git-core` rather than a `PATH` directory would give you a working `git absorb` and
an unset flag. No mainstream package does this — the distro packages (Arch, Debian/Kali,
Alpine, Gentoo) land it in `/usr/bin`, and Homebrew links it into its own prefix `bin`
(`/opt/homebrew/bin` on Apple silicon, `/usr/local/bin` on Intel), which is a different
directory but equally on `PATH`. Probing `git absorb --version` instead would add a `git`
fork to every interactive shell — which `zsh/00-tools.zsh` exists to avoid.

**Detect-only on Linux**, and packaged essentially everywhere — the ²¹ shape, not `jnv`¹⁷'s.
The MacBook `Brewfile` carries it; no Linux `install/packages.txt` does. Verified 2026-08-12
against each distro's own package pages:

- **Arch `extra`** 0.9.0-2, **Alpine `community`** 0.9.0-r0, **Gentoo `dev-vcs/git-absorb`**
  0.9.0 (**stable on amd64**, in the main tree — no GURU needed), **Homebrew** 0.9.0.
- **Debian/Kali `git-absorb`** 0.9.0-2. Note repology reports the **source** package as
  `rust-git-absorb`; the **binary** package you install is `git-absorb`, confirmed on
  packages.debian.org. Fedora is the same shape (`rust-git-absorb` source, `git-absorb`
  binary).
- **openSUSE Tumbleweed is the one laggard, at 0.6.17** — the gap #394 flagged, confirmed
  here rather than left as a repology snapshot. Re-check on the next openSUSE stamp.

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

**Three OS repos still call the impossible `go install`** and have been failing invisibly at
it, because `_dotfiles_go_install` sends the explanation to `/dev/null` and downgrades the
failure to a deferred note: `dotfiles-Arch/bootstrap.sh`, `dotfiles-Kali/bootstrap.sh` and
`dotfiles-openSUSE/bootstrap.sh`. Each is tracked in its own repo; this footnote is the
contract they should be fixed against.

## Clipboard packages to install (backends for Core's `clip`)

<!-- Clipboard selection lives in Core's cross-OS clip/clip-paste scripts; each
     os/<distro>.zsh only aliases pbcopy/pbpaste to them — no distro swaps a
     backend in its zsh layer. This table is the packages each backend needs. -->

| Distro      | Wayland                                      | X11 fallback                                           |
| ----------- | -------------------------------------------- | ------------------------------------------------------ |
| Arch        | `wl-clipboard` (`wl-copy`/`wl-paste`)        | `xclip`                                                |
| openSUSE    | `wl-clipboard`                               | `xclip`                                                |
| Alpine      | `wl-clipboard`                               | `xclip` / `xsel` (often headless — may be neither)     |
| Gentoo      | `gui-apps/wl-clipboard`                      | `x11-misc/xclip`                                       |
| Kali (WSL2) | n/a — Core's `clip` shells out to `clip.exe` | `wl-clipboard`/`xclip` install but sit inert under WSL |

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

**Kali (WSL2)** — The one repo that isn't stamped from Fedora: it's Debian-family
(apt) and carries a unique **offensive role layer** on top of the usual OS layer,
adding an `offensive` stage to the zsh loader (`… os offensive local`). Two things
actually bite. (1) Debian renames binaries — `bat`→`batcat`, and the `fd-find`
package installs `fdfind`; Core handles both. (2) **WSL2 is NAT'd**, so a listener
or reverse shell in Kali isn't reachable from your LAN until you enable **mirrored
networking** — which lives in the _Windows-side_ `%UserProfile%\.wslconfig`
(`networkingMode=mirrored`, Win11 22H2+), **not** `/etc/wsl.conf`. Keep all
engagement data in `~/engagements` (outside the repo); the repo ships a paranoid
`.gitignore` as backup.

---

### Repo status

- **Built:** `core`, `Fedora` (template), `MacBook`, `Arch`, `openSUSE`,
  `Alpine`, `Gentoo`, `Kali`, `Defense`. That is the eight Core-vendoring repos
  (`scripts/os-repos.txt`) plus `core` itself; `Windows` vendors no `core/` and is
  tracked separately.
- **Stamp-pending (this doc):** none — all four template stamps are complete.
- `Kali` (apt + offensive layer) and `MacBook` (Homebrew) are their own lineages,
  built directly rather than stamped from Fedora. `Windows` is tracked separately
  from this matrix.
- **Role repos:** `Kali` (offensive) and `Defense` (defensive) both vendor
  Core, but only `Kali` carries an OS-native layer (Debian/apt). `Defense` is
  **distro-agnostic** — it stacks its blue-team stage on whatever OS-native layer is
  underneath — so it has no row in this OS-stamp matrix by design, not by omission.
  For the same reason `Defense` is the **one documented exception** to the shared
  bootstrap scaffold: its `bootstrap.sh` does not source `lib/bootstrap-lib.sh`'s
  `blib_link_core` (the other seven do). It layers onto an already-provisioned host,
  where the OS repo underneath has already run the scaffold, so it hand-rolls the
  partial re-link it needs. Deliberate, not drift — `core.manifest` records it too.

### Stamping order (all complete — kept as the recommended sequence for reference)

1. **Arch** ✓ — almost everything is in-repo; closest to Fedora effort.
2. **openSUSE** ✓ — straightforward once you internalize `dup` vs `up`.
3. **Alpine** ✓ — forces you to reason about musl and minimalism (great for the
   container/rescue skills a red-teamer wants).
4. **Gentoo** ✓ — the capstone; USE flags + source builds teach you the most.
