---
description: Research the modern-CLI stack for newer/better tools worth adopting
argument-hint: "[tool, category, or theme — optional]"
allowed-tools: Task, Read, Grep, Glob, WebSearch, WebFetch
---

# /tool-scout

Surface **cutting-edge tools and methods** the system does not yet use — the chore
no script can do, because it needs live research and taste. The goal is a
reviewable proposal, not a blind upgrade.

Focus for this run: **$ARGUMENTS** (empty = scan the whole modern-CLI stack).

Delegate the web research to the `tool-scout` subagent (it has WebSearch/WebFetch
and its own context) and relay its ranked proposal.

## Establish the baseline first

Before researching, read what the system already ships so you do not "discover"
something already in use:

- `PORTING-MATRIX.md` — the modern-CLI stack and per-distro package names.
- `zsh/00-tools.zsh`, `zsh/20-aliases.zsh` — what is detected and aliased.
- `mise/config.toml` — pinned language runtimes.
- `zsh/45-plugins.zsh`, `nvim/lazy-lock.json` — pinned plugins.

## What to research

1. **Direct upgrades.** For each tool in the stack (eza, bat, fd, ripgrep, zoxide,
   fzf, git-delta, btop, starship, atuin, yazi, tealdeer, duf, jq/yq, hyperfine,
   ouch, lazygit, sesh, mise), is there a major new release or feature worth
   adopting — or a newer tool that has overtaken it?
2. **New categories.** Tools/methods that fit this stack's philosophy (fast, modern
   replacements for classic Unix tools; ergonomic shell/tmux/nvim workflow) that
   the system has no equivalent for yet.
3. **Method shifts.** Better ways to do what the repo already does (e.g. plugin
   management, runtime pinning, prompt, history, session management).

For each candidate, verify it is real and current (check the project's repo and
latest release date — do not trust a single blog post), and note its packaging
across the distros in `PORTING-MATRIX.md` (this decides how hard it is to adopt).

## How to report

A ranked shortlist, each with:

- **What it is** and what it replaces or adds.
- **Why it fits** this system's philosophy (or why it does not).
- **Adoption cost** — packaging per distro, config churn, whether it touches the
  load order or the manifest.
- **Recommendation** — adopt / watch / skip, with a one-line rationale.

Propose changes only; do not edit config unless I ask. If I adopt one, the change
is Core (`PORTING-MATRIX.md`, `zsh/`, maybe `mise/`), so keep `core.manifest` in
step, add a `CHANGELOG.md` entry, and `make audit` before the PR.
