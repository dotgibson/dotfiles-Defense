# Cross-shell parity contract

The fleet drives two interactive shells: **zsh** (Core, vendored into every Unix
repo) and **PowerShell** (the `dotfiles-Windows` host layer, reimplemented natively
— it does *not* vendor Core). A cross-platform operator moving between WSL-zsh and
Windows-pwsh in the same day should find the same muscle memory on both.

This file is the **source of truth** for what "the same" means. Each capability is
one of:

- **`aligned`** — same behaviour + same trigger on both shells. Changing one side
  without the other is a regression; keep them in step.
- **`deliberate`** — intentionally different because the platforms differ (a tool
  is Windows-only, or the host has no tmux). Documented so it's a *decision*, not
  drift.
- **`gap`** — a capability one shell has and the other could, but doesn't yet.
  An open item, not a promise.

> Sources: zsh in `zsh/{aliases,git,fzf,bindings,tools}.zsh`; pwsh in
> `dotfiles-Windows/powershell/core/{00-aliases,10-tools,20-functions}.ps1`.

## Prompt & tool init

| Capability | zsh | pwsh | Status |
| --- | --- | --- | --- |
| Prompt | starship (`starship.toml`) | starship (same `starship.toml`) | `aligned` |
| Theme | tokyonight-storm | tokyonight-storm | `aligned` |
| Smart `cd` | zoxide (`cd`→`z`, `cdi`/`zi`) | zoxide (`cd` hijacked, `zi`) | `aligned` |
| History sync | atuin | atuin | `aligned` (engine) |
| Completion | carapace + fzf-tab | carapace + PSFzf + CompletionPredictor | `deliberate` |

## Aliases

The alias surface is broadly `aligned`: `ll`/`la`, `cat`→bat, `grep`→rg, `http`→xh,
`dns`→doggo, `du`→dust, `watch`→viddy, `lg`→lazygit, and the git shorthands
(`g`, `gst`/`gss`, `ga`/`gaa`, `gc`/`gcm`, `gco`, `gd`, `gl` pull / `gp` push,
`glog`) resolve to the same intent on both shells. Per-shell extras are noted as
gaps below.

The **aligned tool-swap aliases** (the classic-command → modern-tool re-points) are
pinned as a flat manifest — [`scripts/parity-aliases.txt`](scripts/parity-aliases.txt)
— so `parity-check.sh` enforces each one **bidirectionally**: the zsh alias must be
defined in `zsh/aliases.zsh` **and** the pwsh name must be in `00-aliases.ps1`'s
`provides:` contract. Where the two shells must use different names (e.g. `ps`→procs is
`pss` on pwsh, since `ps` is a core cmdlet) the manifest records the exception, so a
rename on one side without the other is caught. Adding an aligned tool-swap is one
manifest row, not a code change.

## Keybindings

| Capability | zsh | pwsh | Status |
| --- | --- | --- | --- |
| History search | `Ctrl+R` (fzf widget) | `Ctrl+R` (PSFzf) | `aligned` |
| FZF palette | tokyonight-storm `--color` | tokyonight-storm `--color` | `aligned` |
| FZF source cmd | `fd` (`FZF_DEFAULT_COMMAND`) | `fd` (`FZF_DEFAULT_COMMAND`) | `aligned` |
| File picker | `Ctrl+T` (`_fzf_file_no_hidden`) | `Ctrl+T` (PSFzf) | `aligned` |
| atuin TUI | `Ctrl+E` (`_atuin_search_widget`) | `Ctrl+E` (`Invoke-AtuinSearch`) | `aligned` |
| Dir jump | `Alt+Z` (zoxide) / `Alt+C` (fzf) | `Alt+Z` (zoxide `zi`) / `Alt+C` (PSFzf) | `aligned` |
| Session picker | `Ctrl+G` (sesh) | `Ctrl+G` (psmux sessionizer) | `aligned` — jump-to-session both |
| Cheatsheet | `cheat` / `core-help` | `navi` / `cheat` | `deliberate` — command, not a keybind |
| Autosuggest toggle | `Ctrl+\` | PSReadLine predictive (always on) | `deliberate` |
| Word nav | `Ctrl+←/→` | `Ctrl+←/→` (PSReadLine) | `aligned` |

## Functions

| Capability | zsh | pwsh | Status |
| --- | --- | --- | --- |
| `extract`, `mkbak`, `serve`, `fif`, `fbr` | yes | yes | `aligned` |
| Fuzzy git stage/restore (`gaf`/`grf`/`grsf`) | yes | yes | `aligned` |
| `cheat` (cht.sh / navi) | `cheat` | `cheat` / `navi` | `aligned` |

## Resolved decisions

The four formerly-open keybinding decisions were settled together and implemented on
both shells in the same change:

1. **`Ctrl+G` → jump-to-session on both** (Option A). zsh keeps sesh; the Windows host
   binds a psmux sessionizer (zoxide + project roots → `mux`), the bare-prompt port of
   `psmux-sesh.ps1`. navi loses its Ctrl+G widget and is now the `navi` command, freeing
   the key — so Ctrl+G means the same thing everywhere.
2. **File picker → `Ctrl+T` on both** (the fzf-ecosystem default; zsh moved off `Ctrl+F`).
3. **atuin → `Ctrl+E` on both**, `Ctrl+R` = quick fzf history on both. (atuin's pwsh
   module ignores `ATUIN_NOBIND`, so the host rebinds after init: `Ctrl+E` →
   `Invoke-AtuinSearch`, `Ctrl+R`/arrows handed back.)
4. **Ported to pwsh** — `gaf`/`grf`/`grsf` fuzzy git staging and `Alt+Z` zoxide jump.

All four rows are now `aligned` and enforced by `parity-check.sh`.

## Enforcement

`scripts/parity-check.sh` (`make parity-check`) mechanises the `aligned` rows: it
asserts a distinctive needle for each is present in BOTH a zsh source and the pwsh
source, and exits non-zero when one side drifts. It reads pwsh from a sibling
`dotfiles-Windows` checkout (skipped with a notice if absent, unless `--strict`),
exactly like `scripts/fleet-drift.sh`. The weekly `.github/workflows/parity-check.yml`
clones `dotfiles-Windows` and runs it `--strict`, failing red on drift.

When a row here moves to `aligned`, add a matching check to `parity-check.sh` in the
same change — the check is the enforcement. Every `aligned` row above (including the
keybindings settled in **Resolved decisions**) has a corresponding check today; a new
alignment is not done until its needle is added.
