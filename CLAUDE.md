# CLAUDE.md — dotfiles-Defense

Project memory for Claude Code. For the shared Core rules see dotfiles-core's
[`README.md`](https://github.com/dotgibson/dotfiles-core/blob/main/README.md) and [`CONTRIBUTING.md`](https://github.com/dotgibson/dotfiles-core/blob/main/CONTRIBUTING.md) —
upstream, not in `core/`, which vendors only what a machine actually runs.

## What this repo is

`dotfiles-Defense` is the **defensive (blue) Role layer** of the dotfiles system
(Core → OS-native → Role). It is the mirror of `dotfiles-Offense`: detection
engineering & investigation instead of offense — hunt/triage tooling,
version-controlled detection content, and a Dockerized detection lab. It is
**distro-agnostic**: host tools come from the OS-native layer, heavy stack in
containers.

## The rule that bites

- `core/` is a vendored copy of dotfiles-core — never edit it here; fix
  upstream then sync. It arrives by a **pinned fetch plus
  `git read-tree --prefix=core/`**, with `core.lock` recording the commit — not
  `git subtree` (dotgibson/dotfiles-core#587). A `git subtree pull` would move
  `core/` without `core.lock` and leave `core-integrity` reporting **TAMPERED**;
  `core/VENDORING.md` has the mechanism.
- The loader adds a **`defense` stage** (`… os defense local`) — keep blue config
  there, not in `core/`.
- **Case/evidence data NEVER lives in the repo.** It lives in `~/cases/`; the
  `.gitignore` is only a backstop. `mkcase` scaffolds outside the repo.
- **Red vs blue is a split, not a merge.** Attacker-authored detections stay in
  Offense's `PURPLE-TEAM.md`; defender-authored capability lives here. Cross-link.

## Where things are

- `defense/defense.zsh` — role layer: `HAVE_*` detection, `mkcase`/`gocase`/`note`, `siemup`/`siemdown`
- `defense/templates/` — `case.md` / `hunt.md`
- `detections/` — `sigma/`, `sysmon/`, `network/`, `siem/`
- `docker/` — the detection-lab compose stack(s)
- `DEFENSE-METHODOLOGY.md` — ATT&CK → data-source → detection map
- `bootstrap.sh` — symlinks Core + defense, writes the loader, checks docker
- `core/` — vendored Core (read-only here)
