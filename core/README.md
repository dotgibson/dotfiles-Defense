<!-- Back to top link -->
<a id="readme-top"></a>

<!-- Project Shields -->
<div align="center"><nobr>

[![dotgibson][dotgibson-shield]][dotgibson-url]<!--
-->[![CI][ci-shield]][ci-url]<!--
-->![Last Commit][lastcommit-shield]<!--
-->[![Contributors][contributors-shield]][contributors-url]<!--
-->[![Forks][forks-shield]][forks-url]<!--
-->[![Stargazers][stars-shield]][stars-url]<!--
-->[![Issues][issues-shield]][issues-url]<!--
-->[![MIT License][license-shield]][license-url]

</nobr></div>

<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://github.com/dotgibson/">
    <img src="https://raw.githubusercontent.com/dotgibson/.github/main/profile/logo.png" alt="Logo" width="80" height="80">
  </a>

  <h3 align="center">🧬 dotfiles-core</h3>

  <p align="center">
    The foundation layer of a cross-platform dotfiles system.
    <br />
    <a href="https://dotgibson.github.io/dotfiles-web/docs"><strong>Explore the docs »</strong></a>
    <br />
    <br />
    <a href="https://dotgibson.github.io/dotfiles-web/playground/">View Demo</a>
    &middot;
    <a href="https://github.com/dotgibson/dotfiles-core/issues/new?labels=bug&template=bug_report.md">Report Bug</a>
    &middot;
    <a href="https://github.com/dotgibson/dotfiles-core/issues/new?labels=enhancement&template=feature_request.md">Request Feature</a>
  </p>
</div>

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#languages">Languages</a></li>
        <li><a href="#tools">Tools</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->
## About The Project

[![dotgibson — terminal demo][product-screenshot]](https://dotgibson.github.io/dotfiles-web)

**`dotfiles-core` is the foundation layer** — the shell, editor, and tooling config
that stays identical on every machine. It's authored once here and vendored into each
per-OS repo, so you don't install this repo directly: you clone the repo for your
platform (macOS, Kali, Fedora, …), which already carries Core inside it. Full docs live
at the [documentation site][docs].

The system is three layers — Core here, an OS-native layer per machine, and an optional
role layer — each building on the one below:

| Layer | Lives in | Owns |
| --- | --- | --- |
| **Core** | this repo → vendored into every OS repo's `core/` | zsh, tmux, nvim, git, starship — identical everywhere |
| **OS-native** | `dotfiles-{MacBook,Windows,Fedora,Arch,…}` | package manager, clipboard, paths |
| **Role** | `dotfiles-Kali`, `dotfiles-Defense` | offensive / defensive tooling |

The rationale (why subtree, how a sync fans out) lives on the [docs site][docs]; this
README is the quick tour.

Like most dotfiles, this started as a personal itch. Every tweak to my terminal led to refactoring something else, and the cycle didn't stop until the whole environment finally felt like home. Once it did, I wanted the exact same setup on every machine I touch — no productivity gaps when hopping between them. That's `dotgibson`: my terminal workflow, made portable.

It won't be everyone's ideal — dotfiles are personal — but the pieces here are meant to be borrowed, and it keeps evolving as I find better ways to build it. Suggestions and issues are always welcome; thanks to everyone whose own configs inspired this one.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Languages

* [![Zsh][zsh-shield]][zsh-url]
* [![Bash][bash-shield]][bash-url]
* [![Lua][lua-shield]][lua-url]
* [![TOML][toml-shield]][toml-url]
* [![YAML][yaml-shield]][yaml-url]
* [![JSON][json-shield]][json-url]

### Tools

* [![Neovim][neovim-shield]][neovim-url]
* [![Vim][vim-shield]][vim-url]
* [![Tmux][tmux-shield]][tmux-url]
* [![Starship][starship-shield]][starship-url]
* [![Git][git-shield]][git-url]
* [![1Password][1password-shield]][1password-url]
* [![Mise][mise-shield]][mise-url]
* [![LazyGit][lazygit-shield]][lazygit-url]
* [![jujutsu][jujutsu-shield]][jujutsu-url]
* [![sesh][sesh-shield]][sesh-url]
* [![fzf][fzf-shield]][fzf-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- GETTING STARTED -->
## Getting Started

Every repo follows the same shape: clone, optionally dry-run to preview the symlink plan, then bootstrap. Core is vendored, so a clone is self-contained with no submodule flags. Just pick a platform and go.

### Prerequisites

All you need up front is **Git** and your platform's base toolchain — `bootstrap.sh`
provisions everything else (zsh, tmux, nvim, starship, and friends). Platform-specific
setup notes live in each OS repo's README and the [docs site][docs]; the essentials:

* **macOS** — Xcode [Command Line Tools](https://developer.apple.com/documentation/xcode/command-line-tools)
* **Windows** — PowerShell 7 and Developer Mode
* **Kali** — built for WSL2

### Installation

1. Clone the repo for your platform. Releases are tagged per repo — replace
   `vX.Y.Z` with the latest tag from that repo's **Releases** page.

   ```sh
   # MacOS
   git clone --branch vX.Y.Z https://github.com/dotgibson/dotfiles-MacBook ~/dotfiles-MacBook
   cd ~/dotfiles-MacBook

   # Kali
   git clone --branch vX.Y.Z https://github.com/dotgibson/dotfiles-Kali ~/dotfiles-Kali
   cd ~/dotfiles-Kali

   # Linux distros (Fedora, Arch, openSUSE, Alpine, Gentoo)
   git clone --branch vX.Y.Z https://github.com/dotgibson/dotfiles-Fedora ~/dotfiles-Fedora
   cd ~/dotfiles-Fedora
   ```

   ```pwsh
   # Windows
   git clone --branch vX.Y.Z https://github.com/dotgibson/dotfiles-Windows.git
   cd dotfiles-Windows
   .\install.ps1
   ```

2. Preview the plan (optional)

   ```sh
   # MacOS
   ./bootstrap.sh --links-only --dry-run

   # Linux distros (Fedora, Arch, openSUSE, Alpine, Gentoo)
   ./bootstrap.sh --links-only
   ```

3. Provision + Wire

   ```sh
   # MacOS
   ./bootstrap.sh
   exec zsh

   # Kali
   ./bootstrap.sh

   # Linux Distros
   ./bootstrap.sh
   exec zsh
   ```

   ```pwsh
   .\install.ps1
   ```

4. Optional

   ```sh
   # MacOS
   # Apply system defaults
   ./bootstrap.sh --macos-defaults

   # Kali
   # Enable mirrored networking on the windows side
   # Drop windows.wslconfig.example at %UserProfile%\.wslconfig, then from Windows:
   wsl.exe --shutdown

   # Fedora / openSUSE
   # --no-flatpak
   # skips Flatpak

   # Gentoo
   # --no-sync
   # skips the slow emerge --sync on re-runs

   # Arch
   # Stage-0 prep in SETUP.md should be run first

   # Alpine
   # run as root or with doas
   # enable the community repo
   ```

   ```pwsh
   # Windows
   # set name/email in ~/.gitconfig.local
   wsl --shutdown
   ```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- USAGE EXAMPLES -->
## Usage

Core swaps the classic Unix tools for modern equivalents — but only when they're
installed. Detection flags (`HAVE_*`) are resolved at load time, so every alias falls
back to the classic command on a box that doesn't have the newer one. Nothing breaks;
things just get nicer where they can.

| You type | You get | When present |
| --- | --- | --- |
| `ls` / `ll` | `eza` — icons, git status, tree view | eza |
| `cat` | `bat` — syntax highlighting | bat |
| `cd` | `zoxide` — frecency-ranked jumps | zoxide |
| `top` | `btop` | btop |
| `du` / `df` | `dust` / `duf` | dust, duf |
| `vim` | `nvim` | always |

Run `core help` (aliased `cheat`) for the built-in index of every command, or browse the
full [alias cheat sheet](aliases.md) — including the OMZ-compatible git suite (`gst`,
`gcb`, `glog`, `gpf`, …).

_For more, see the [Documentation][docs]._

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- ROADMAP -->
## Roadmap

* [x] Add Changelog
* [x] Add back to top links
* [ ] Add Additional tools
* [ ] README.md overhaul for entire project

See the [open issues](https://github.com/dotgibson/dotfiles-core/issues) for a full list of proposed features (and known issues).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRIBUTING -->
## Contributing

Contributions are **greatly appreciated**. Because Core is vendored into every OS repo,
a change here fans out to all of them — so see [`CONTRIBUTING.md`](CONTRIBUTING.md) for
what counts as Core, the manifest contract, and the `make audit` gate. The short version:

1. Fork the project and branch off `main`
2. Make your change, keeping it Core (identical on every machine, not OS-specific)
3. Run `make audit` until it's green
4. Open a pull request with a [Conventional Commits](https://www.conventionalcommits.org/) title

Prefer a quick idea? Open an issue with the "enhancement" tag.

### Top contributors

<a href="https://github.com/dotgibson/dotfiles-core/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=dotgibson/dotfiles-core" alt="contrib.rocks image" />
</a>

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LICENSE -->
## License

Distributed under the MIT License. See `LICENSE` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTACT -->
## Contact

Garrett Allen - [@gerrrrt](https://x.com/gerrrrt) - <garrettallen2@gmail.com> - [LinkedIn](https://linkedin.com/in/garrettallen2)

Project Link: [dotgibson](https://github.com/dotgibson/)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- ACKNOWLEDGMENTS -->
## Acknowledgments

Here are some of my favorite dotfile configurations.

* [Neovim (Tony, btw.)](https://github.com/tonybanters/nvim)
* [Dotfiles (omerxx)](https://github.com/omerxx/dotfiles)
* [Dotfiles (josean-dev)](https://github.com/josean-dev/dev-environment-files)
* [Dotfiles (hendrikmi)](https://github.com/hendrikmi/dotfiles)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- Markdown Links & Images -->
[dotgibson-shield]: https://img.shields.io/github/v/release/dotgibson/dotfiles-core?style=flat-square&label=dotgibson&labelColor=181717&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAF1klEQVR4nLSWbUxT7RnHr9PT09MXSltaoC9QXkqR16Iwhb0Iw8VYYE7jPri5aBaZzpmFZbpolpn4QeMyM%2BM%2B7MVt0Q9LNJIlxCzqxGWS6aKAig51vBQKIi3QltpCS0%2Fbc879pD1N3%2Bnz4fG5Pl2977v%2F331d131f5%2BZrddWQZAgAgy9uCRlefICzT6GeIsP%2FXF15kahmu9JglGmLRQoRQdIQWgu77BuWGe%2Fo%2BOqym8odApaWomTT1%2Bl2HqirahaTuJ9kQMggkgYhDRGfRiQDZBi9fuf52%2BD7l1b3ZhRcmq%2FMnBHmibuO7fvWoTalVoDjQRwL8RGgEOtzB0MbtBDnkRjGR0AgTK%2BQfNukr1LKXlhXKZpJSxTKGoFSq9vf16tQ8%2FiEh094Vu0L449mLGMup20DRWuFYVCiFm%2BvU36nTbOlMB%2BnCDxIOBzhvv6nFpc3TS0dUKDRHzh1Jk9O8wlPYN326Oa%2FJobnN8shAOxqKjrdXa8WSnGKWPewR%2FuHLG5P8oKUFJHi%2FH19F6UKEQ%2BnbJap27%2B%2BtWR15VAHgLkV%2F%2F0xW6OuQCfNE4PgmyX6f0xZKYbJDuj43lmtoYqHU%2FaZdwNXr4eoUG51zqgw%2B%2FCtrbm0UCeRynBhqVj2YC4RNC%2FuqStbKkydAODzeO7%2B6QYTpnOIYgB729R729RY9DAGafb0wDOHLwAA5vKK1mJNFoCpsxeLLn%2Fy91uU359719%2FfVXL%2BSM35IzU9rcXciCcQujz0imOfbGhOB0jkGo2hFQBW7Quzr0Zzq6vyBT%2FuKY%2BHErfBmQWLK1Lhr6l1OkleCqC0poPb%2FuTwv3OrA8DPDhgkokgLmLX77o86kqcGJmaj5xjr1JWlAAr1Js75MDEGAAI%2B1mvWX%2F1JY29XmYDPS5ZoNsrM24si1xSh3%2FRbGBYlz%2F73g41ztqliqYv1onyVHgDocMjjXASAKycavlqnZBHa2ajcasjv%2B8MbAPhRV9nI5MezB41crIPPHWOW9Gtl9XhDDCMCokIqSwGQ4shvyucFhEQCnqlSdm9k%2BdKt6XM%2FqO7aof7t8YbIIW5SHdpVIhUTAOAP0L8bmM3MHgJwByidQCgnhSmAqOEYnQ8AgRBr%2FuUzKsgggIs3pyVCfkeTCgAmFtaNOgm39C%2F3511r2W8JYvIAJbIaAwQ3vKAEoVgRaTQIBYKxqxgMs6euvdUXiQDgeHd5rV7K1fb2kC2rOgaYghQBMJ5grI3HUGuuhQiNIOWq8sy%2FLTgCKplgT0ZtCyprWw7%2FvKCyNr6yQqYg8cim59a9KQDnwv84R1%2F99UwAzsMya4vxeOYLN7YePGG%2BcAPjxXS%2BoavknFfOlRTAh8nHKNqLa1v2ZwK6dxQZtHk5ahu3%2FcYmLsoh%2B%2FsUgN%2BztDQzEvkYFBurGnan%2FS1%2B1P98L1FbxLIPzh193X%2FtwbmjiGUBYHd5nVFRCABPlxdtfh%2B3LHGKxof%2Bqo90C6yj58yi9Tm1kWjr94ZXsGhTuDuynAx2z0245yY4X06Kf9HWFd0N%2BuPbsUR64%2B3a57Erig2qIoOIlJSUNE69GWTZRFufXvRNL%2Fo2ywyJE1fMP6xWqHBEP5yfvP7%2FbAAAsFufG01mkVCqkGvLyrbNTD2mw9kfDckmE0oudx9rUZfhiF5Zd%2F%2F00QDF0NkBTJhanB3e0riHJIRKhXarqWfdu%2Bx0WnOot1ftuNR90lhQzEO0L7B2YvCm3b%2BWNI%2ByffSLq757%2BPcquYaIvBtgdcXycuzO9MzTFdccd9IwDNMVlDaXbzPXtxsVhQRDEQzl8i6d%2Buf12Y%2BONDVMo6vOfHWJxHLz3l811u8WAEZABCNAAHSI8n8k2HABKRJjLJ8JECxFMAE%2BHXhiGb7yn35vcCNDKVsEcSuv%2BEpn%2B7Etla0CwAQIOBLBhrkt85kAnwm8mX95e%2FTOa9vUZiIxQI43r0Kura9uN5SYNMoyuVDGZ2nK73C65iy28Rezo44152bSKYAvz3ifVA1lDn0WAAD%2F%2F%2FWvXexgMwqgAAAAAElFTkSuQmCC
[dotgibson-url]: https://github.com/dotgibson/dotfiles-core/releases/latest
[ci-shield]: https://img.shields.io/github/actions/workflow/status/dotgibson/dotfiles-core/ci.yml?branch=main&style=flat-square&logo=githubactions&logoColor=white&label=CI
[ci-url]: https://github.com/dotgibson/dotfiles-core/actions/workflows/ci.yml
[lastcommit-shield]: https://img.shields.io/github/last-commit/dotgibson/dotfiles-core?branch=main&style=flat-square&logo=git&logoColor=white
[contributors-shield]: https://img.shields.io/github/contributors/dotgibson/dotfiles-core.svg?style=flat-square&logo=github
[contributors-url]: https://github.com/dotgibson/dotfiles-core/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/dotgibson/dotfiles-core.svg?style=flat-square&logo=github
[forks-url]: https://github.com/dotgibson/dotfiles-core/network/members
[stars-shield]: https://img.shields.io/github/stars/dotgibson/dotfiles-core.svg?style=flat-square&logo=github
[stars-url]: https://github.com/dotgibson/dotfiles-core/stargazers
[issues-shield]: https://img.shields.io/github/issues/dotgibson/dotfiles-core?style=flat-square&logo=github
[issues-url]: https://github.com/dotgibson/dotfiles-core/issues
[license-shield]: https://img.shields.io/github/license/dotgibson/dotfiles-core.svg?style=flat-square
[license-url]: https://github.com/dotgibson/dotfiles-core/blob/main/LICENSE
[product-screenshot]: assets/demo.gif
[docs]: https://dotgibson.github.io/dotfiles-web/docs
[zsh-shield]: https://img.shields.io/badge/Zsh-F15A24?style=flat-square&logo=zsh&logoColor=white
[zsh-url]: https://github.com/zsh-users/zsh
[bash-shield]: https://img.shields.io/badge/Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white
[bash-url]: https://github.com/bminor/bash
[lua-shield]: https://img.shields.io/github/v/tag/lua/lua?sort=semver&style=flat-square&logo=lua&logoColor=white&label=Lua&color=000080
[lua-url]: https://github.com/lua/lua
[toml-shield]: https://img.shields.io/github/v/tag/toml-lang/toml?sort=semver&style=flat-square&logo=toml&logoColor=white&label=TOML&color=9C4121
[toml-url]: https://github.com/toml-lang/toml
[yaml-shield]: https://img.shields.io/badge/YAML-CB171E?style=flat-square&logo=yaml&logoColor=white
[yaml-url]: https://github.com/yaml
[json-shield]: https://img.shields.io/badge/JSON-000000?style=flat-square&logo=json&logoColor=white
[json-url]: https://www.json.org
[neovim-shield]: https://img.shields.io/github/v/release/neovim/neovim?style=flat-square&logo=neovim&logoColor=white&label=Neovim&labelColor=57A143&color=3D59A1
[neovim-url]: https://github.com/neovim/neovim
[vim-shield]: https://img.shields.io/github/v/tag/vim/vim?sort=semver&style=flat-square&logo=vim&logoColor=white&label=Vim&labelColor=019733&color=3D59A1
[vim-url]: https://github.com/vim/vim
[tmux-shield]: https://img.shields.io/github/v/release/tmux/tmux?style=flat-square&logo=tmux&logoColor=white&label=tmux&labelColor=1BB91F&color=3D59A1
[tmux-url]: https://github.com/tmux/tmux
[starship-shield]: https://img.shields.io/github/v/release/starship/starship?style=flat-square&logo=starship&logoColor=white&label=Starship&labelColor=DD0B78&color=3D59A1
[starship-url]: https://github.com/starship/starship
[git-shield]: https://img.shields.io/github/v/tag/git/git?sort=semver&style=flat-square&logo=git&logoColor=white&label=Git&labelColor=F03C2E&color=3D59A1
[git-url]: https://github.com/git/git
[1Password-shield]: https://img.shields.io/badge/1Password-145FE4?style=flat-square&logo=1password&logoColor=white
[1Password-url]: https://github.com/1Password
[mise-shield]: https://img.shields.io/github/v/release/jdx/mise?style=flat-square&logo=gnometerminal&logoColor=24283B&label=mise&labelColor=BB9AF7&color=3D59A1
[mise-url]: https://github.com/jdx/mise
[lazygit-shield]: https://img.shields.io/github/v/release/jesseduffield/lazygit?style=flat-square&logo=gnometerminal&logoColor=24283B&label=lazygit&labelColor=BB9AF7&color=3D59A1
[lazygit-url]: https://github.com/jesseduffield/lazygit
[jujutsu-shield]: https://img.shields.io/github/v/release/jj-vcs/jj?style=flat-square&logo=gnometerminal&logoColor=24283B&label=jujutsu&labelColor=BB9AF7&color=3D59A1
[jujutsu-url]: https://github.com/jj-vcs/jj
[sesh-shield]: https://img.shields.io/github/v/release/joshmedeski/sesh?style=flat-square&logo=gnometerminal&logoColor=24283B&label=sesh&labelColor=BB9AF7&color=3D59A1
[sesh-url]: https://github.com/joshmedeski/sesh
[fzf-shield]: https://img.shields.io/github/v/release/junegunn/fzf?style=flat-square&logo=gnometerminal&logoColor=24283B&label=fzf&labelColor=BB9AF7&color=3D59A1
[fzf-url]: https://github.com/junegunn/fzf
