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

  <h3 align="center">🔵 dotfiles-Defense</h3>

  <p align="center">
    The defensive role layer — detection engineering and a Dockerized hunt lab.
    <br />
    <a href="https://dotgibson.github.io/dotfiles-web/docs"><strong>Explore the docs »</strong></a>
    <br />
    <br />
    <a href="https://dotgibson.github.io/dotfiles-web/purple/">Red ↔ Blue</a>
    &middot;
    <a href="https://github.com/dotgibson/dotfiles-Defense/issues/new?labels=bug">Report Bug</a>
    &middot;
    <a href="https://github.com/dotgibson/dotfiles-Defense/issues/new?labels=enhancement">Request Feature</a>
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
    <li><a href="#getting-started">Getting Started</a></li>
    <li><a href="#whats-in-this-layer">What's In This Layer</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->
## About The Project

**`dotfiles-Defense` is the defensive (blue) Role layer** — the mirror of
[`dotfiles-Offense`](https://github.com/dotgibson/dotfiles-Offense). Where Offense carries
the offensive engagement layer, this repo carries **detection engineering &
investigation**: hunt/triage tooling, version-controlled detection content
(Sigma, Sysmon, Zeek/Suricata, SIEM), and a Dockerized detection lab. The shared
**Core** (zsh, tmux, Neovim, git, starship) is vendored under `core/`; on top
sits your OS-native layer, and on top of that a unique **defense** stage.

It is **distro-agnostic** — you don't need a blue-team distro. The heavy stack is
containers, so host tools come from your OS layer and the lab comes up via
`docker/` (`siemup` / `siemdown`).

> **The one rule that matters:** this is a public repo, so **case, evidence, and
> log data never live in it.** All investigation data lives under `~/cases/`
> (outside the repo), exactly like Offense keeps engagements in `~/engagements/`.
> `mkcase` scaffolds a case outside the repo by design; the `.gitignore` is a
> backstop.

The full docs live on the [documentation site][docs].

The system is three layers; Defense is the blue Role stacked on an OS layer:

| Layer                | Lives in                                                                              | Owns                                                  |
| -------------------- | ------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| **Core**             | [`dotfiles-core`](https://github.com/dotgibson/dotfiles-core), vendored under `core/` | zsh, tmux, nvim, git, starship — identical everywhere |
| **OS-native**        | your existing `dotfiles-{Fedora,Arch,…}` layer                                        | package manager, clipboard, paths                     |
| **Role (defensive)** | `defense/`, `detections/`, `docker/` — **unique to this repo**                        | detection engineering + hunt lab                      |

### Languages

No new languages — this layer is shell and package config over
[Core's language stack](https://github.com/dotgibson/dotfiles-core#languages).

### Tools

- [![Docker][docker-shield]][docker-url]
- [![Sigma][sigma-shield]][sigma-url]
- [![Sysmon][sysmon-shield]][sysmon-url]
- [![Zeek][zeek-shield]][zeek-url]
- [![Suricata][suricata-shield]][suricata-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- GETTING STARTED -->
## Getting Started

### Prerequisites

Any OS with your dotfiles OS-native layer already set up, **Git**, and **Docker**
(for the detection lab). No specific distro is required — Security Onion and other
blue-team appliances are not dotfiles targets.

### Installation

```sh
git clone https://github.com/dotgibson/dotfiles-Defense ~/dotfiles-Defense
cd ~/dotfiles-Defense
./bootstrap.sh                 # symlinks Core + defense, wires the loader, checks docker
exec zsh
```

`core/` is a vendored subtree and is **already present** in a clone — there is no
submodule step. Host tools come from your OS-native layer; bring the heavy
detection stack up and down with `siemup` / `siemdown`.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- WHAT'S IN THIS LAYER -->
## What's In This Layer

The defense stage loads just before local overrides (`… os defense local`), and
holds workflow helpers only — all `HAVE_*`-guarded:

- `defense/defense.zsh` — case workflow (`mkcase`, `gocase`, `note`,
  `siemup` / `siemdown`)
- `defense/templates/` — `case.md` / `hunt.md` seeds
- `detections/` — version-controlled detection content (`sigma/`, `sysmon/`,
  `network/`, `siem/`)
- `docker/` — the detection-lab compose stack(s)
- `DEFENSE-METHODOLOGY.md` — the ATT&CK → data-source → detection map
- `core/` — vendored from `dotfiles-core` (read-only here; edit upstream)

The attack-paired mirror — what each detection is _looking for_ — lives in Offense's
`PURPLE-TEAM.md` and on the hub's red↔blue view:

> **[→ Offensive methodology (the red mirror)][methodology]** · **[dotfiles-Defense on the hub][repo-docs]**

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRIBUTING -->
## Contributing

This is a **Role layer** stacked on Core + an OS layer:

1. **Never hand-edit `core/`.** It is a vendored copy of `dotfiles-core`,
   overwritten on the next sync. Fix shared config **upstream**, then re-sync.
2. **Defensive config goes in the `defense` stage**, not in `core/`. Keep it
   distro-agnostic — host tools come from the OS layer.
3. **Keep the split and the discipline.** Attacker-authored detections stay in
   Offense's `PURPLE-TEAM.md` (cross-link, don't copy); case/evidence data never
   enters the repo. **Green the lint gate** (shellcheck + `bash -n` / `zsh -n`;
   vendored `core/` excluded).

Before pushing, run both checks the way CI runs them:

```bash
./tests/test-defense.sh    # behaviour: the role layer + the installer
./tests/lint-shell.sh      # shellcheck, at the version CI pins
```

`lint-shell.sh` exists because CI installs a **pinned** shellcheck while your
distro ships whatever it ships, and the two disagree about which checks exist —
so a file can be clean locally and red in CI for no visible reason. It reads the
pin and the flags out of the vendored `core/`, then runs the pinned version
(via docker when your local one differs), and says plainly when it cannot.

Bugs and ideas: open an
[issue](https://github.com/dotgibson/dotfiles-Defense/issues).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LICENSE -->
## License

Distributed under the MIT License. See [`LICENSE`](LICENSE) for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTACT -->
## Contact

Garrett Allen - [@gerrrrt](https://x.com/gerrrrt) - <garrettallen2@gmail.com> - [LinkedIn](https://linkedin.com/in/garrettallen2)

Project Link: [dotgibson](https://github.com/dotgibson/)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- Markdown Links & Images -->
[repo-docs]: https://dotgibson.github.io/dotfiles-web/docs/repos/dotfiles-Defense
[methodology]: https://dotgibson.github.io/dotfiles-web/docs/reference/offensive-methodology
[dotgibson-shield]: https://img.shields.io/github/v/release/dotgibson/dotfiles-core?style=plastic&label=dotgibson&labelColor=181717&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAF1klEQVR4nLSWbUxT7RnHr9PT09MXSltaoC9QXkqR16Iwhb0Iw8VYYE7jPri5aBaZzpmFZbpolpn4QeMyM%2BM%2B7MVt0Q9LNJIlxCzqxGWS6aKAig51vBQKIi3QltpCS0%2Fbc879pD1N3%2Bnz4fG5Pl2977v%2F331d131f5%2BZrddWQZAgAgy9uCRlefICzT6GeIsP%2FXF15kahmu9JglGmLRQoRQdIQWgu77BuWGe%2Fo%2BOqym8odApaWomTT1%2Bl2HqirahaTuJ9kQMggkgYhDRGfRiQDZBi9fuf52%2BD7l1b3ZhRcmq%2FMnBHmibuO7fvWoTalVoDjQRwL8RGgEOtzB0MbtBDnkRjGR0AgTK%2BQfNukr1LKXlhXKZpJSxTKGoFSq9vf16tQ8%2FiEh094Vu0L449mLGMup20DRWuFYVCiFm%2BvU36nTbOlMB%2BnCDxIOBzhvv6nFpc3TS0dUKDRHzh1Jk9O8wlPYN326Oa%2FJobnN8shAOxqKjrdXa8WSnGKWPewR%2FuHLG5P8oKUFJHi%2FH19F6UKEQ%2BnbJap27%2B%2BtWR15VAHgLkV%2F%2F0xW6OuQCfNE4PgmyX6f0xZKYbJDuj43lmtoYqHU%2FaZdwNXr4eoUG51zqgw%2B%2FCtrbm0UCeRynBhqVj2YC4RNC%2FuqStbKkydAODzeO7%2B6QYTpnOIYgB729R729RY9DAGafb0wDOHLwAA5vKK1mJNFoCpsxeLLn%2Fy91uU359719%2FfVXL%2BSM35IzU9rcXciCcQujz0imOfbGhOB0jkGo2hFQBW7Quzr0Zzq6vyBT%2FuKY%2BHErfBmQWLK1Lhr6l1OkleCqC0poPb%2FuTwv3OrA8DPDhgkokgLmLX77o86kqcGJmaj5xjr1JWlAAr1Js75MDEGAAI%2B1mvWX%2F1JY29XmYDPS5ZoNsrM24si1xSh3%2FRbGBYlz%2F73g41ztqliqYv1onyVHgDocMjjXASAKycavlqnZBHa2ajcasjv%2B8MbAPhRV9nI5MezB41crIPPHWOW9Gtl9XhDDCMCokIqSwGQ4shvyucFhEQCnqlSdm9k%2BdKt6XM%2FqO7aof7t8YbIIW5SHdpVIhUTAOAP0L8bmM3MHgJwByidQCgnhSmAqOEYnQ8AgRBr%2FuUzKsgggIs3pyVCfkeTCgAmFtaNOgm39C%2F3511r2W8JYvIAJbIaAwQ3vKAEoVgRaTQIBYKxqxgMs6euvdUXiQDgeHd5rV7K1fb2kC2rOgaYghQBMJ5grI3HUGuuhQiNIOWq8sy%2FLTgCKplgT0ZtCyprWw7%2FvKCyNr6yQqYg8cim59a9KQDnwv84R1%2F99UwAzsMya4vxeOYLN7YePGG%2BcAPjxXS%2BoavknFfOlRTAh8nHKNqLa1v2ZwK6dxQZtHk5ahu3%2FcYmLsoh%2B%2FsUgN%2BztDQzEvkYFBurGnan%2FS1%2B1P98L1FbxLIPzh193X%2FtwbmjiGUBYHd5nVFRCABPlxdtfh%2B3LHGKxof%2Bqo90C6yj58yi9Tm1kWjr94ZXsGhTuDuynAx2z0245yY4X06Kf9HWFd0N%2BuPbsUR64%2B3a57Erig2qIoOIlJSUNE69GWTZRFufXvRNL%2Fo2ywyJE1fMP6xWqHBEP5yfvP7%2FbAAAsFufG01mkVCqkGvLyrbNTD2mw9kfDckmE0oudx9rUZfhiF5Zd%2F%2F00QDF0NkBTJhanB3e0riHJIRKhXarqWfdu%2Bx0WnOot1ftuNR90lhQzEO0L7B2YvCm3b%2BWNI%2ByffSLq757%2BPcquYaIvBtgdcXycuzO9MzTFdccd9IwDNMVlDaXbzPXtxsVhQRDEQzl8i6d%2Buf12Y%2BONDVMo6vOfHWJxHLz3l811u8WAEZABCNAAHSI8n8k2HABKRJjLJ8JECxFMAE%2BHXhiGb7yn35vcCNDKVsEcSuv%2BEpn%2B7Etla0CwAQIOBLBhrkt85kAnwm8mX95e%2FTOa9vUZiIxQI43r0Kura9uN5SYNMoyuVDGZ2nK73C65iy28Rezo44152bSKYAvz3ifVA1lDn0WAAD%2F%2F%2FWvXexgMwqgAAAAAElFTkSuQmCC
[dotgibson-url]: https://github.com/dotgibson/dotfiles-core/releases/latest
[ci-shield]: https://img.shields.io/github/check-runs/dotgibson/dotfiles-Defense/main?style=plastic&logo=githubactions&logoColor=white&label=CI
[ci-url]: https://github.com/dotgibson/dotfiles-Defense/actions/workflows/lint.yml
[lastcommit-shield]: https://img.shields.io/github/last-commit/dotgibson/dotfiles-Defense?branch=main&style=plastic&logo=git&logoColor=white
[contributors-shield]: https://img.shields.io/github/contributors/dotgibson/dotfiles-Defense.svg?style=plastic&logo=github
[contributors-url]: https://github.com/dotgibson/dotfiles-Defense/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/dotgibson/dotfiles-Defense.svg?style=plastic&logo=github
[forks-url]: https://github.com/dotgibson/dotfiles-Defense/network/members
[stars-shield]: https://img.shields.io/github/stars/dotgibson/dotfiles-Defense.svg?style=plastic&logo=github
[stars-url]: https://github.com/dotgibson/dotfiles-Defense/stargazers
[issues-shield]: https://img.shields.io/github/issues/dotgibson/dotfiles-Defense?style=plastic&logo=github
[issues-url]: https://github.com/dotgibson/dotfiles-Defense/issues
[license-shield]: https://img.shields.io/github/license/dotgibson/dotfiles-Defense.svg?style=plastic
[license-url]: https://github.com/dotgibson/dotfiles-Defense/blob/main/LICENSE
[docs]: https://dotgibson.github.io/dotfiles-web/docs
[docker-shield]: https://img.shields.io/github/v/release/moby/moby?style=plastic&logo=docker&logoColor=white&label=Docker&labelColor=2496ED&color=3D59A1
[docker-url]: https://github.com/moby/moby
[sigma-shield]: https://img.shields.io/github/v/release/SigmaHQ/sigma?style=plastic&logo=gnometerminal&logoColor=24283B&label=Sigma&labelColor=BB9AF7&color=3D59A1
[sigma-url]: https://github.com/SigmaHQ/sigma
[sysmon-shield]: https://img.shields.io/badge/Sysmon-0078D6?style=plastic&logo=windows&logoColor=white
[sysmon-url]: https://learn.microsoft.com/sysinternals/downloads/sysmon
[zeek-shield]: https://img.shields.io/github/v/release/zeek/zeek?style=plastic&logo=gnometerminal&logoColor=24283B&label=Zeek&labelColor=BB9AF7&color=3D59A1
[zeek-url]: https://github.com/zeek/zeek
[suricata-shield]: https://img.shields.io/badge/Suricata-EF3B2D?style=plastic&logo=suricata&logoColor=white
[suricata-url]: https://suricata.io
