# Security Policy

`dotfiles-core` ships **configuration only** — shell modules, a Neovim tree, tmux,
git, starship, and mise. It is not a running service and stores no credentials or
machine state (see `.gitignore`: secrets, `*.bak`, and `zsh/99-local.zsh` never get
tracked). Even so, this repo is the keystone of a ten-repo system: it is vendored
into every OS repo via `git subtree`, so a defect here **fans out N-way**. That
makes two classes of issue worth a security report rather than a normal issue:

- a tracked file that leaks a secret, token, or other sensitive value, and
- a Core script (`bin/clip*`, `maint/dotfiles-maint.sh`, `tmux/scripts/*`, or the
  `scripts/*.sh` dev tooling) that can be coerced into running untrusted input on a
  consumer's or maintainer's machine.

## Reporting a vulnerability

**Please do not open a public issue for a security report.** Use GitHub's private
vulnerability reporting instead: the **Security** tab → **Report a vulnerability**.
That keeps the details private until a fix has been synced out to the OS repos.

Include, where you can:

- the file and line involved, and which Core layer it sits in,
- how it is reached at runtime (sourced module, `bin/` script, tmux popup, …), and
- a minimal reproduction.

You can expect an acknowledgement within a few days. A confirmed fix lands here
first, then propagates to each OS repo on the next `./scripts/sync-core.sh`.

## Scope

In scope: anything tracked in this repository. Out of scope: the OS-native repos
(`dotfiles-{MacBook,Windows,Fedora,…}`) and `dotfiles-Kali` — report issues that
are specific to those layers in their own repositories.
