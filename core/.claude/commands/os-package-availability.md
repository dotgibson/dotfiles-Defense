---
description: Audit an OS repo's package list against upstream availability + PORTING-MATRIX.md (report-first)
argument-hint: "<distro> — fedora | arch | opensuse | alpine | gentoo | macbook"
allowed-tools: Read, Grep, Glob, Bash(git ls-files:*), Bash(ls:*), WebSearch, WebFetch
---

# /os-package-availability

Answer one question for a single distro's package list: **is every entry still
installable under the name we use, and does it still belong here?** Package
*versions* are handled by the freshness bots and Renovate; this is about
*availability and naming drift* — the pain a version bump can't see: a package
renamed upstream, dropped from the repos, moved to a secondary channel
(AUR / COPR / RPM Fusion / Packman / Alpine edge), or now shipped only as a
binary / `cargo install` / `go install`.

Distro for this run: **$ARGUMENTS** (one of `fedora`, `arch`, `opensuse`,
`alpine`, `gentoo`, `macbook`). The calling OS repo is checked out beside this one
and exposed to the CLI via `--add-dir` (as `caller/`). Read its
`install/packages.txt` (for macbook, its `Brewfile`), and read `PORTING-MATRIX.md`
from this dotfiles-core checkout.

## Baseline first — don't re-litigate what CI proves

`lint.yml` / `core-integrity` already gate structure and vendored-`core/` freshness;
the freshness bots + Renovate already bump *versions*. This routine does **not**
re-check those. It checks the one thing nothing else does: whether the *names in
the list still resolve upstream*.

## What to check

1. **Name resolution.** For each package in the caller's list, confirm the name
   still exists in this distro's repos — search the canonical index (Fedora
   Packages / Arch + AUR / openSUSE OBS / Alpine pkgs / Gentoo portage /
   Homebrew formulae). Flag: **renamed** (old → new), **dropped**, or **moved** to
   a secondary repo.
2. **Cross-check `PORTING-MATRIX.md`.** Its package-name table has columns for
   **Arch, openSUSE, Alpine, Gentoo, and Kali only** — `fedora` and `macbook` have
   **no column** (Fedora is the template the others are stamped from; macOS is
   Homebrew). So for `fedora`/`macbook`, do **not** cite or invent a matrix column —
   verify names against the upstream index (Fedora Packages / Homebrew formulae) plus
   the matrix's distro-general **footnotes**. For the other four, compare the caller's
   list against its column *and* footnotes, and flag a tool the matrix says is packaged
   that isn't (or vice-versa), or a footnote gone stale — e.g. a "cargo³" note for a
   tool now first-class in the repos, or a rename the matrix hasn't recorded.
3. **Respect the "intentionally excluded" convention.** Some tools are
   **deliberately absent** from `packages.txt` because they're not reliably packaged
   (bootstrap installs them: starship, atuin, yazi; lazygit via COPR on Fedora; …).
   The list documents these in comments — do **not** flag them as "missing." Only a
   genuine drift counts.
4. **New availability.** A tool previously bootstrap-only or cargo-only that a
   distro now packages first-class → a candidate to move **into** the list (and to
   update the matrix footnote).

## How to report

Group by severity, cite `file:line` on both sides, and give the exact one-line fix
(old name → new name; add / remove; matrix footnote to correct):

- **Broken (fix needed)** — a name that no longer resolves as written.
- **Drifted (likely)** — renamed / moved but still installable under an alias, or a
  stale matrix footnote.
- **Clean** — what was checked and still resolves, so a green run is trustworthy.
  Quantify: N packages checked, which distro index was queried.

Report-first. Fixes to a package list land in the **OS repo**
(`install/packages.txt` / `Brewfile`); fixes to the matrix land in **dotfiles-core**
(`PORTING-MATRIX.md`). Do not edit anything unless I explicitly ask.
