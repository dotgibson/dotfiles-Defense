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

| Tool             | Arch                   | openSUSE     | Alpine       | Gentoo (atom)              | Kali (apt)      |
| ---------------- | ---------------------- | ------------ | ------------ | -------------------------- | --------------- |
| eza              | `eza`                  | `eza`        | `eza`        | `sys-apps/eza`             | `eza`           |
| bat              | `bat`                  | `bat`        | `bat`        | `sys-apps/bat`             | `bat`⁴          |
| fd               | `fd`                   | `fd`         | `fd`         | `sys-apps/fd`              | `fd-find`⁴      |
| ripgrep          | `ripgrep`              | `ripgrep`    | `ripgrep`    | `sys-apps/ripgrep`         | `ripgrep`       |
| zoxide           | `zoxide`               | `zoxide`     | `zoxide`     | `app-shells/zoxide`        | `zoxide`        |
| fzf              | `fzf`                  | `fzf`        | `fzf`        | `app-shells/fzf`           | `fzf`           |
| git-delta        | `git-delta`            | `git-delta`  | `delta`      | `dev-util/git-delta`       | `git-delta`     |
| btop             | `btop`                 | `btop`       | `btop`       | `sys-process/btop`         | `btop`          |
| tldr             | `tealdeer`             | `tealdeer`¹  | `tealdeer`   | `app-misc/tealdeer`        | `tealdeer`      |
| neovim           | `neovim`               | `neovim`     | `neovim`     | `app-editors/neovim`       | `neovim`        |
| lazygit          | `lazygit`              | `lazygit`    | `lazygit`    | `dev-vcs/lazygit`          | `lazygit`       |
| zsh              | `zsh`                  | `zsh`        | `zsh`²       | `app-shells/zsh`           | `zsh`           |
| tmux             | `tmux`                 | `tmux`       | `tmux`       | `app-misc/tmux`            | `tmux`          |
| starship         | `starship`             | script³      | script³      | `app-shells/starship`      | script³         |
| atuin            | `atuin` (AUR for some) | script³      | `atuin`      | `app-shells/atuin`         | `atuin`³        |
| yazi             | `yazi`                 | cargo³       | cargo³       | `app-misc/yazi`            | cargo³          |
| tree-sitter-cli⁵ | `tree-sitter-cli`      | cargo³       | cargo³       | cargo³                     | `mise`/`cargo`³ |
| jq               | `jq`                   | `jq`         | `jq`         | `app-misc/jq`              | `jq`            |
| yq⁶              | `go-yq`                | `yq`         | `yq`         | `app-admin/go-yq`          | `yq`            |
| duf              | `duf`                  | `duf`        | `duf`        | `sys-fs/duf`               | `duf`           |
| hyperfine        | `hyperfine`            | `hyperfine`  | `hyperfine`  | `app-benchmarks/hyperfine` | `hyperfine`     |
| shellcheck       | `shellcheck`           | `ShellCheck` | `shellcheck` | `dev-util/shellcheck`      | `shellcheck`    |
| shfmt⁷           | `shfmt`                | `shfmt`      | `shfmt`      | `dev-go/shfmt`             | `shfmt`⁷        |
| ouch             | `ouch`                 | cargo³       | `ouch`       | cargo³                     | cargo³          |
| jujutsu (jj)⁸    | `jujutsu`              | `jujutsu`    | cargo³       | `dev-vcs/jujutsu`          | cargo³          |
| sesh⁹            | AUR⁹                   | go⁹          | go⁹          | go⁹                        | go⁹             |
| difftastic¹⁰     | `difftastic`           | `difftastic` | `difftastic` | `dev-util/difftastic`      | `difftastic`    |
| ast-grep¹¹       | `ast-grep`             | cargo³       | `ast-grep`   | cargo³                     | cargo³          |

¹ openSUSE: may be in `devel` repos; if absent, `cargo install tealdeer`.
² Alpine default shell is `ash`; you must `apk add zsh` explicitly.
³ Not packaged or stale → use the upstream installer / `cargo install` (same
pattern bootstrap.sh already uses on Fedora). Add `cargo`/`rust` to packages.
⁴ Debian/Kali ship these under different binary names — `bat` runs as `batcat`,
the `fd-find` package installs `fdfind`. Core's `tools.zsh` already resolves
both, so aliases and config work unchanged.
⁵ nvim-treesitter (pinned to `main`) needs tree-sitter-cli ≥ 0.26.1. **Mac:**
`tree-sitter-cli` via brew — **not** `tree-sitter`, which is now lib-only.
**Fedora:** `tree-sitter-cli` via dnf (verify ≥ 0.26.1, else mise/cargo).
**Arch:** `extra` carries 0.26.9 (clears the floor). Where unpackaged:
`mise use -g tree-sitter` or `cargo install tree-sitter-cli`. On **Alpine** it
must be a musl build — prefer cargo over any prebuilt binary.
⁶ yq: this matrix targets **mikefarah's Go `yq`** (the jq-for-YAML). Distros also
ship **Python `yq`** (kislyuk) under the same `yq` name; if you land the wrong
one, install the Go build via `mise use -g yq` or the upstream release binary.
⁷ shfmt: not always in stable apt (Debian/Kali) and the Gentoo atom is
`dev-go/shfmt`. If the package is missing, `mise use -g shfmt` or
`go install mvdan.cc/sh/v3/cmd/shfmt@latest`. (These mid-2026 rows are
best-effort — verify the exact package on first stamp of each distro.)
⁸ jujutsu (jj): OPT-IN, additive git companion — never replaces git, so a box
without it just skips the HAVE_JJ-gated aliases. Packaged on Arch (`jujutsu`),
openSUSE (`jujutsu`), Gentoo (`dev-vcs/jujutsu`), Fedora (`jujutsu`), Homebrew
(`jj`) and nixpkgs (`jujutsu`); not in Alpine (musl — `cargo install jujutsu`)
or stable Debian/Kali apt (`cargo install jujutsu`) — same cargo pattern as
yazi/ouch. The config (`jujutsu/config.toml`) is inert without the binary.
⁹ sesh: smart tmux session manager that Core already drives from the `Ctrl-G`
shell widget (`fzf.zsh`) and the `prefix + f` tmux popup (`tmux-sesh.sh`); both
degrade to a `find`+`fzf` sessionizer when it's absent. `core-doctor` already
reports `sesh` via its own `command -v` probe (it does not read `HAVE_SESH`);
`tools.zsh` now also sets `HAVE_SESH` for parity with the other detected tools.
Packaged in the AUR (`sesh`), Homebrew
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

### Stamping order (all complete — kept as the recommended sequence for reference)

1. **Arch** ✓ — almost everything is in-repo; closest to Fedora effort.
2. **openSUSE** ✓ — straightforward once you internalize `dup` vs `up`.
3. **Alpine** ✓ — forces you to reason about musl and minimalism (great for the
   container/rescue skills a red-teamer wants).
4. **Gentoo** ✓ — the capstone; USE flags + source builds teach you the most.
