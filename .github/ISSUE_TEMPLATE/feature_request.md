---
name: Feature request
about: Propose a new Core file or a change to an existing one
title: "feat: "
labels: enhancement
---

## What do you want to add or change?

A clear description of the proposal.

## Is it actually Core?

Core is the config that is **identical on every machine** and **not** offensive
tooling. Confirm it passes the three-layer test (see CONTRIBUTING.md):

- [ ] It is identical on every machine (not OS-specific: no package manager,
      paths, or clipboard logic).
- [ ] It is not offensive/engagement tooling (that lives in `dotfiles-Kali`).
- [ ] If it's a new file, I'll add its path to `core.manifest` (the contract).

## Why

What this enables, or what pain it removes. Since a change here fans out to all
eight OS repos, note any blast radius worth weighing.
