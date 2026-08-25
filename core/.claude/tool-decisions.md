# Tool decisions — considered and declined

The register of tools Core **evaluated and did not adopt**, and why — plus the ones it is
**holding**, each with the event that would end the hold.

`/tool-scout`'s baseline (`PORTING-MATRIX.md`, `zsh/00-tools.zsh`, `zsh/20-aliases.zsh`,
`mise/config.toml`, `zsh/45-plugins.zsh`, `nvim/lazy-lock.json`) describes what Core **has**.
None of it records what Core **considered and declined**, so a rejected tool was
indistinguishable from one never evaluated — and a weekly scan re-proposed it on the next pass.

That is not a tidiness problem. A re-proposal arrives with a fresh case-for and **no
counter-argument attached**, so the decision gets re-made on half the evidence. `hexyl` was
ranked #3 "adopt" on 2026-08-18, six days after #395 closed it `NOT_PLANNED`; it would have been
adopted on that pass if the report had been actioned without someone happening to remember.

**This file is a required read for `/tool-scout`, and the routine must state, per candidate,
whether a prior decision exists.** Filing a decision is not enough if nothing reads it.

## How to use it

- **Scouting.** A candidate appearing below is not automatically dead — but it may only be
  re-proposed against the recorded reasoning, naming what changed. "It is good" is not what
  changed. A new maintainer, a new scan, or a new release note is not what changed either.
- **Deciding.** When an issue closes `NOT_PLANNED` on a tool, add a row here in the same pass.
  The GitHub issue holds the argument; this file is the index that makes it findable by the one
  process that would otherwise re-litigate it.
- **Watching.** A held-not-declined row goes under "Watching" with the **event** that would end
  the hold, never a vague "revisit later". Two of the three rows there had their original reason
  expire without anyone noticing, which is how a stale hold survives: the next scan reads the old
  reason, finds it no longer true, and reads that as permission rather than as a prompt to write
  a new one. If a condition is met, say so and argue afresh.
- **Reversing.** Adopting something listed here is fine. Move the row to "Reversed" with the
  issue that reversed it, so the trail survives.

## Declined

| tool | verdict | where | why, in one line |
| --- | --- | --- | --- |
| `hexyl` | role layer, not Core | [#395](https://github.com/dotgibson/dotfiles-core/issues/395) → [dotfiles-Kali#182](https://github.com/dotgibson/dotfiles-Kali/issues/182) | "Inspect a binary" leans engagement-flavoured and is low-frequency; fails `CONTRIBUTING.md`'s Core test |
| `fastgron` | skip | [#518](https://github.com/dotgibson/dotfiles-core/issues/518) | `gron` is dormant-but-**complete** and universally packaged; speed is not the binding constraint |
| `zellij` | skip | [#376](https://github.com/dotgibson/dotfiles-core/issues/376) | tmux is Core-deep — two confs, seven scripts, sesh, `Ctrl-G`, the status line — for no capability sesh doesn't already cover |
| `just` | skip | [#376](https://github.com/dotgibson/dotfiles-core/issues/376), [#518](https://github.com/dotgibson/dotfiles-core/issues/518) | justfiles are per-**project**; `mise [tasks]` already covers it and is already documented in `examples/mise.project.toml` |
| `dysk` | skip | [#376](https://github.com/dotgibson/dotfiles-core/issues/376), [#518](https://github.com/dotgibson/dotfiles-core/issues/518) | lateral to `duf`, and `duf` is **not** stale (0.9.1, 2025-09-08) — a swap with no capability delta |
| `qsv` | skip | [#327](https://github.com/dotgibson/dotfiles-core/issues/327) | heavier CSV suite; `xan` is the leaner fit for the same gap — decide the gap first, not the tool |
| `jless` | skip | [#327](https://github.com/dotgibson/dotfiles-core/issues/327) | superseded by `jnv`, which Core adopted — same job, and `jnv` embeds `jaq` so it needs no external `jq` |
| `bandwhich` | skip | [#327](https://github.com/dotgibson/dotfiles-core/issues/327) | ~1–2 years since a release at the time of review; no maintained replacement need |
| `mprocs` | skip | [#327](https://github.com/dotgibson/dotfiles-core/issues/327), [#518](https://github.com/dotgibson/dotfiles-core/issues/518) | stale on review, and tmux already owns "run several things side by side" on every box |
| `tere` | skip | [#327](https://github.com/dotgibson/dotfiles-core/issues/327) | covered by `zoxide` (jump) + `yazi` (browse) — the two verbs it merges are both already wired |
| `choose` | skip | [#327](https://github.com/dotgibson/dotfiles-core/issues/327) | covered by `sd` and `awk`; a third field-extraction syntax to remember, not a missing one |
| `gitu` / `serie` | skip | [#327](https://github.com/dotgibson/dotfiles-core/issues/327) | the git surface is saturated — lazygit + delta + difftastic + jj + nvim diffview/fugitive |
| `television` | skip | [#518](https://github.com/dotgibson/dotfiles-core/issues/518) | architectural, not versional: fzf 0.74.3 is faster, and Core's fzf-tab + widget investment makes a swap pure cost |
| `pay-respects` | skip | [#518](https://github.com/dotgibson/dotfiles-core/issues/518) | command-correction wants a **shell hook**, which the zero-fork startup contract rules out |
| `uutils coreutils` | not Core's call | [#518](https://github.com/dotgibson/dotfiles-core/issues/518) | swapping the system coreutils is a **distro** decision; it changes with the OS, so it fails the Core test |
| `numbat` / `serpl` | skip | [#518](https://github.com/dotgibson/dotfiles-core/issues/518) | rejected without deep research, deliberately — no gap either one fills in this stack |
| `cargo-update` | skip | [#702](https://github.com/dotgibson/dotfiles-core/issues/702) | would close the ²⁵ gap, but it is a heavy source build with native deps on exactly the boxes that lack a package for it |

### `hexyl` — the long form

`CONTRIBUTING.md`'s test settles it: a thing is Core only if it is identical on every machine
**and** not OS-specific **and** not offensive/engagement tooling. If it changes when *the
operator* changes, it belongs in the role layer.

The case *for* was real and cheap — no binary-inspection verb exists anywhere in the stack,
0.17.0 is packaged everywhere (no `cargo` path on any target), zero config, no alias, inert
without the binary. It was declined anyway on frequency and flavour: the [#376] scan ranked it
*adopt-if-you-want* rather than a clear win, which is itself the signal that it is not
fleet-wide. If it only ever gets used on Kali, that is where the row goes.

**What would change the decision:** evidence of routine use outside an engagement context — not
a better `hexyl`.

[#376]: https://github.com/dotgibson/dotfiles-core/issues/376

### `fastgron` — the long form

Correctly skipped by the [#518] scan on its own initiative; recorded here because the scan
itself noted the reasoning should be written down "so a future scout doesn't re-litigate it".
`gron` has not shipped in a while, and that is not a defect: it is a *finished* tool with a
stable job and universal packaging. `fastgron` is faster, but nothing in this stack is bottlenecked
on `gron`'s throughput, and adopting it trades universal availability for a benchmark.

**What would change the decision:** `gron` actually breaking (a distro dropping it, or a bug
upstream declines to fix), not `fastgron` getting faster.

[#518]: https://github.com/dotgibson/dotfiles-core/issues/518

## Watching

Not declined — held, with a **stated condition**. A watch row is only useful if it names the
event that would end it, so every row here carries one. A watch whose condition has been met is
no longer a watch, and re-proposing it needs a fresh argument rather than the old one repeated.

| tool | held since | the condition that would end the watch |
| --- | --- | --- |
| `xan` | [#327](https://github.com/dotgibson/dotfiles-core/issues/327), [#376](https://github.com/dotgibson/dotfiles-core/issues/376), re-held [#702](https://github.com/dotgibson/dotfiles-core/issues/702) | two consecutive minors with **no breaking argument changes** — see the long form; the original packaging and frequency reasons have both expired |
| `csvlens` | [#518](https://github.com/dotgibson/dotfiles-core/issues/518) | reaching Alpine `community`. **Still unmet** as of 2026-08-25 (0.15.1, 2026-01-08; Arch/Homebrew/nixpkgs only) |
| `trippy` | [#327](https://github.com/dotgibson/dotfiles-core/issues/327), [#376](https://github.com/dotgibson/dotfiles-core/issues/376), [#518](https://github.com/dotgibson/dotfiles-core/issues/518) | a release that lands, **plus** an answer to `CAP_NET_RAW`. Neither has moved: 0.13.0 is from 2025-05-05, and 0.14.0's behaviour change was pre-announced and undelivered |
| `sesh picker` (sesh's built-in TUI, replacing the `sesh list \| fzf` pipe) | [#376](https://github.com/dotgibson/dotfiles-core/issues/376), [#518](https://github.com/dotgibson/dotfiles-core/issues/518), re-held [#702](https://github.com/dotgibson/dotfiles-core/issues/702) | a **colour/theme schema in `[tui]`**. #518's "no preview" blocker is spent; #376's "loss of fzf theming" is **not**, and it is the one that costs something |

### `xan` — the long form, because its reason changed

The right category and a real gap: Core has `jq`, `yq`, `gron` and `jnv` for JSON/YAML and
**nothing for CSV/TSV**. It is the `gron`/`sd`/`ast-grep` shape — own command, no alias,
`HAVE_*`-gated, inert without the binary — so the adoption cost is close to zero.

**Two reasons were recorded, and both have since expired.** [#327] held it because "CSV is a
narrower daily need than JSON" — a frequency argument. [#376] held it because "4 distros need
`cargo³`" — a packaging argument. Packaging is now demonstrably not the bar: 0.60.0 is in Arch
official, Gentoo GURU, Homebrew and nixpkgs, and Core's bar for an opt-in `HAVE_*`-gated tool is
visibly lower than that already — `jnv` is in no `install/packages.txt` anywhere (PORTING-MATRIX
footnote ¹⁷) and was adopted regardless.

**The reason it is still held is a different one, and it is the durable one.** 0.60.0's release
notes *lead* with breaking changes to command-line arguments. Core has been bitten once by
exactly that in exactly this family: `sd` 1.1.0 changed its default to line-by-line matching,
failed **silently** on multi-line patterns, and — the part that made it expensive —
`sd --version` could not tell you which behaviour you had (PORTING-MATRIX footnote ²²). A tool
whose argument semantics are still moving is one whose documented recipes go quietly wrong on
the boxes that upgrade first, and this fleet upgrades at eight different rates.

**What would end the watch:** two consecutive minor releases with no breaking argument changes.
Not a wider package footprint — that argument is already spent — and not a better `xan`.

[#327]: https://github.com/dotgibson/dotfiles-core/issues/327

### `sesh picker` — the long form, because the report said this was settled

The 2026-08-25 scan ([#702]) ranked this *adopt, low priority* on the grounds that **both**
recorded blockers were "factually spent" and that any future decline "has to argue ergonomics,
not capability". Half of that is right. The other half is why this row exists.

**Spent:** [#518] held it on "no preview; feature-detect with fallback". sesh **2.28.0**
(2026-07-27) added an opt-in preview pane, custom icons, `#{1-9}` index jump and aliases. That
blocker is genuinely gone, and the subcommand is real — `sesh picker` carries `--preview`,
`--prompt`, `--placeholder`, `--icons`, `--query` and the `-c`/`-t`/`-z` mode flags that match
the four reload binds `tmux/scripts/tmux-sesh.sh` builds by hand.

**Not spent:** [#376] held it on **loss of fzf theming**, and sesh still has no way to be
themed. Verified against the 2026-08-25 binary rather than the docs — the complete set of
`[tui]` keys is `prompt`, `placeholder`, `show_icons`, `show_windows`, `preview`,
`preview_width`, `preview_min_width`, `preview_border`, `alias_auto_connect`,
`alias_auto_connect_delay`, `alias_filter_prefix` and `separator_aware`. **No colour key of any
kind, and no `SESH_*` environment override either.** `preview_border` picks a divider glyph
(`line`/`thick`/`double`/`none`), not a colour.

That is not an ergonomic preference, it is the recorded blocker still standing. Core's
tokyonight-storm palette lives **once**, in `FZF_DEFAULT_OPTS` (`zsh/35-fzf.zsh`), and every
picker in the stack inherits it — deliberately, so a themed prompt and an unthemed picker never
sit next to each other. Adopting `sesh picker` would swap the two most-used pickers on the box
(`Ctrl-G` in the shell, `prefix + f` in tmux) for ones that cannot be themed at all, on eight
machines, to gain a preview pane the fzf path **already has** via `--preview 'sesh preview {}'`.

**What would change the decision:** a colour or theme schema under `[tui]` — at which point the
palette question becomes "where does it live" rather than "can it exist", and the answer is a
`[tui]` block in `sesh/sesh.toml.example` carrying a comment that names `zsh/35-fzf.zsh` as the
source of truth. Not a new release on its own, and not the preview pane, which is already here.

**Worth doing regardless, and independent of this decision:** `zsh/35-fzf.zsh` claims the shell
and tmux "share one picker". They do not — the shell widget runs its own inline, less-featured
copy and only delegates to `tmux/scripts/tmux-sesh.sh` when sesh is **absent**. That comment is
wrong today whichever way this row goes.

[#702]: https://github.com/dotgibson/dotfiles-core/issues/702

## Reversed

*None yet.*

## Scope — why only `/tool-scout` reads this

`/os-package-availability` and `/modernize` have the same weekly-scan-with-no-memory shape, but
both already carry a working in-band equivalent and do **not** need this file:

- `/os-package-availability` — the "intentionally excluded" convention: tools deliberately absent
  from `packages.txt` because they are not reliably packaged (starship, atuin, yazi — installed by
  bootstrap instead) are documented in comments **in the list itself**, and the routine is
  instructed not to flag them.
- `/modernize` — the floor it scouts against is declared in `scripts/modern-baseline.yml` and
  enforced by `scripts/check-modern.sh`. A rule already in force is machine-readable, so the
  routine cannot rediscover it.

`/tool-scout` was the outlier: its baseline is five files that all describe the shipped stack,
with nowhere for a negative decision to live. If either sibling later grows a decision that has
no in-band home, add it here rather than inventing a third mechanism.
