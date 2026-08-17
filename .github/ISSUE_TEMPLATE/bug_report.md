---
name: Bug report
about: A Core file is broken, behaves wrong, or fails the audit
title: "bug: "
labels: bug
---

<!--
Reminder: this is the Core layer, vendored into eight OS repos via git subtree.
If the problem is OS-specific (package manager, paths, clipboard) it belongs in
the OS repo; if it's offensive/engagement tooling, it belongs in dotfiles-Kali.
See CONTRIBUTING.md for the three-layer test.
-->

## What's wrong

A clear description of the bug.

## Which Core file(s)

e.g. `zsh/00-tools.zsh`, `scripts/audit-core.sh`, `nvim/lua/gerrrt/...`

## How to reproduce

Steps, or a minimal command. If it's a load-order/runtime break, the output of:

```bash
./scripts/audit-core.sh        # the one gate
./scripts/test-core.sh         # behavioral (load-order + function units)
```

## Expected vs actual

What you expected, and what happened instead.

## Environment

- OS / distro:
- zsh version (`zsh --version`):
- Relevant tool versions (shellcheck, luacheck, …):
