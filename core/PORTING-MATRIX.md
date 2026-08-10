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
| refresh   | `sudo pacman -Sy`        | `sudo zypper refresh`                            | `doas apk update`         | `sudo emerge --sync`            | `sudo apt-get update`        |
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
| lazygit          | `lazygit`         | `lazygit`    | `lazygit`         | `dev-vcs/lazygit`¹²        | `lazygit`         |
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
| sd               | `sd`              | `sd`         | `sd`              | `sys-apps/sd`¹²            | `sd`              |
| gron             | `gron`            | `gron`       | `gron`            | go³                        | `gron`            |
| jnv¹⁷            | AUR               | cargo        | cargo             | cargo                      | cargo             |
| glow             | `glow`            | `glow`       | testing¹⁴         | `app-misc/glow`¹²          | `glow`¹⁵          |
| gum              | `gum`             | `gum`        | `gum`             | `app-misc/gum`¹²           | `gum`¹⁵           |
| xh               | `xh`              | `xh`         | `xh`              | `net-misc/xh`¹²            | `xh`              |
| doggo            | `doggo`           | `doggo`¹⁸    | `doggo`           | `net-dns/doggo`            | go³               |
| gping¹⁹          | `gping`           | `gping`¹⁹    | `gping`           | GURU¹⁹                     | `gping`¹⁹         |
| carapace         | AUR³              | go³          | `carapace`        | `app-shells/carapace`¹²    | go³               |
| op (1Password)¹³ | AUR               | vendor rpm   | vendor apk        | GURU¹²                     | vendor apt        |
| hyperfine        | `hyperfine`       | `hyperfine`  | `hyperfine`       | `app-benchmarks/hyperfine` | `hyperfine`       |
| shellcheck       | `shellcheck`      | `ShellCheck` | `shellcheck`      | `dev-util/shellcheck`      | `shellcheck`      |
| shfmt⁷           | `shfmt`           | `shfmt`      | `shfmt`           | go³                        | `shfmt`⁷          |
| ouch             | `ouch`            | `ouch`¹⁸     | testing           | cargo³                     | cargo³            |
| jujutsu (jj)⁸    | `jujutsu`         | `jujutsu`    | `jujutsu`         | cargo³                     | cargo³            |
| sesh⁹            | AUR⁹              | go⁹          | go⁹               | go⁹                        | go⁹               |
| difftastic¹⁰     | `difftastic`      | `difftastic` | `difftastic`      | `dev-util/difftastic`      | `difftastic`      |
| ast-grep¹¹       | `ast-grep`        | `ast-grep`¹⁸ | `ast-grep`        | cargo³                     | cargo³            |
| w3m              | `w3m`             | `w3m`        | `w3m`             | `www-client/w3m`           | `w3m`             |

¹ openSUSE: in Tumbleweed main OSS as `tealdeer` (also Leap 15.6); on older Leap, `cargo install tealdeer`.
² Alpine default shell is `ash`; you must `apk add zsh` explicitly.
³ Not packaged or stale → bootstrap.sh installs it best-effort (upstream
installer / `cargo install` / `go install` / AUR), the same pattern bootstrap
already uses on Fedora. Add `cargo`/`rust` (or a `go` toolchain) to packages.
`go install` targets land in `~/.local/bin` via `GOBIN` so they're on PATH.
⁴ Debian/Kali ship these under different binary names — `bat` runs as `batcat`,
the `fd-find` package installs `fdfind`, and the `du-dust` package installs the
`dust` command. Core's `00-tools.zsh` already resolves them, so aliases and config
work unchanged.
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
`dev-util/shfmt`; there is no `dev-go/shfmt` atom), so Gentoo takes the `go³`
path. If the package is missing, `mise use -g shfmt` or
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
¹⁴ Alpine **testing** repo (`duf`, `glow`): musl-fine Go tools that live in `testing` (never
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
(the ³ best-effort path viddy/yazi/ouch use) is a tracked follow-up in the OS repos; there is
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
| Fedora · Arch · openSUSE · Gentoo (systemd) · Kali · Defense | `systemd --user` unit — copy `examples/atuin-daemon.service` into `~/.config/systemd/user/`, then `systemctl --user enable --now atuin-daemon` (and `loginctl enable-linger $USER` if you want it alive outside a login session) | `ATUIN_DAEMON__ENABLED=true`                                  |
| Alpine (musl, no systemd)                                    | atuin supervises its own daemon — no unit, no service manager, nothing to install                                                                                                                                                | `ATUIN_DAEMON__ENABLED=true` + `ATUIN_DAEMON__AUTOSTART=true` |
| macOS                                                        | same as Alpine: `autostart` beats hand-writing a launchd plist, and `XDG_RUNTIME_DIR` is unset there so the socket lands in the data dir — which atuin resolves itself                                                           | `ATUIN_DAEMON__ENABLED=true` + `ATUIN_DAEMON__AUTOSTART=true` |
| Windows                                                      | out of scope — `dotfiles-Windows` vendors no `core/` and replicates its host config in PowerShell                                                                                                                                | —                                                             |

The exports belong in that repo's `os/<os>.zsh` (loader fragment 80), **never** in the Core
config: Core is vendored identically to every repo, so a per-machine value there would be
wrong on the other seven. `autostart` is mutually exclusive with `systemd_socket = true` —
pick the unit or pick autostart, not both.

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

Under the **systemd-unit** launcher, `zsh/00-tools.zsh` probes the socket once before the first
prompt and forces the daemon **off for that shell** when nothing is listening: an absent — or stale,
i.e. left behind by a crashed daemon — socket otherwise costs atuin a failed connect on every
command. So a dead daemon costs the lock relief, not every prompt. `core-doctor` shows the
degraded state; nothing else says a word.

**Under `autostart` the probe deliberately does not run** — and that is the Alpine and macOS
rows above, so on two of the eight machines this safety net is not the thing keeping you out
of trouble. It stands down because an absent socket is then the client's _cue to start one_,
not a fault; disabling the daemon there would permanently defeat the only launcher those
machines have. atuin's own health-checking is what covers them.

The probe's limit, because it decides which unit you should install: it cannot tell an
**accept-but-silent** socket from a healthy one. systemd **socket activation** produces
exactly that state when the daemon behind the socket is dead — the socket keeps accepting,
the client waits, and that is the indefinite freeze in `atuinsh/atuin#3382`. Prefer the plain
always-running service above; if you do use a `.socket` unit with `systemd_socket = true`,
you are outside what Core can protect.

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
  `Alpine`, `Gentoo`, `Kali`.
- **Stamp-pending (this doc):** none — all four template stamps are complete.
- `Kali` (apt + offensive layer) and `MacBook` (Homebrew) are their own lineages,
  built directly rather than stamped from Fedora. `Windows` is tracked separately
  from this matrix.
- **Role repos:** `Kali` (offensive) and `Defense` (defensive) both vendor
  Core, but only `Kali` carries an OS-native layer (Debian/apt). `Defense` is
  **distro-agnostic** — it stacks its blue-team stage on whatever OS-native layer is
  underneath — so it has no row in this OS-stamp matrix by design, not by omission.

### Stamping order (all complete — kept as the recommended sequence for reference)

1. **Arch** ✓ — almost everything is in-repo; closest to Fedora effort.
2. **openSUSE** ✓ — straightforward once you internalize `dup` vs `up`.
3. **Alpine** ✓ — forces you to reason about musl and minimalism (great for the
   container/rescue skills a red-teamer wants).
4. **Gentoo** ✓ — the capstone; USE flags + source builds teach you the most.
