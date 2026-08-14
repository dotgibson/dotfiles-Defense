# Security policy

## Reporting a vulnerability

Use **GitHub private vulnerability reporting**, which is enabled here. That keeps the
report private until a fix exists.

From this repository: **Security** tab → **Report a vulnerability**. That path is the
canonical one and stays correct in a fork or after a transfer, where a hard-coded URL
would not. For convenience on the canonical repo, the form is at
<https://github.com/dotgibson/dotfiles-Defense/security/advisories/new>.

Please do **not** open a public issue for anything exploitable.

This is a personal-but-public showcase project with a single maintainer, so there is no
response-time commitment. Reports are read and acted on in good faith; if you need a
guaranteed SLA, this is not that kind of project, and it is better to know that up front
than to infer it from silence.

## What is in scope

This repository ships shell configuration, an installer, and version-controlled detection
content. The interesting attack surface is small but real:

- **`bootstrap.sh`** — runs on a developer's machine and creates symlinks in `$HOME`.
  Anything that makes it write outside its documented surface, or clobber a file without
  the backup it promises, is in scope.
- **`defense/defense.zsh`** — sourced into every interactive shell. Command injection
  through a case name, a note, or an environment variable is in scope.
- **`.github/workflows/`** — in particular `auto-tag.yml`, which runs with
  `contents: write`. Anything that lets an unprivileged actor influence what it executes
  is in scope.
- **`docker/`** — the detection lab. Note that it ships a deliberately invalid
  `SET_ME` sentinel password so an unedited config fails loudly instead of booting with a
  known credential. A way to make it boot with a predictable credential anyway is in scope.

## What is out of scope

- **Vulnerabilities in the tools this repo probes for** — zeek, suricata, chainsaw,
  hayabusa, volatility3 and friends are third-party software that this repo neither
  vendors nor installs. Report those to their own maintainers.
- **`core/`** — a vendored subtree of
  [dotfiles-core](https://github.com/dotgibson/dotfiles-core). It is never edited here.
  Report Core issues upstream; they reach this repo through a sync.
- **Detection rules that miss something.** A rule with a coverage gap is a bug, not a
  vulnerability — please open a normal issue, they are welcome.

## A note on evidence

Case and investigation data never lives in this repository. It lives in `~/cases`,
outside the repo, and `.gitignore` blocks investigation artefacts only as a backstop. If
you find a path where this repo's tooling would write evidence *into* the repository —
where it could then be committed and published — treat that as a vulnerability and report
it privately. That is the property this design exists to guarantee.
