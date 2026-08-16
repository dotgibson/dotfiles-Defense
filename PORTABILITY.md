# PORTABILITY.md — what "portable" means in Core, concretely

Core is authored once here and vendored into eight OS repos. A file in `core.manifest`
runs on **macOS (bash 3.2, BSD userland), glibc Linux, musl/busybox Alpine, and rolling
Arch** — so "portable" is not a style preference here, it is the contract that keeps one
tree correct on every machine.

`CONTRIBUTING.md` answers _is it Core?_ This answers _how do I write Core that survives
the fan-out?_ Both were previously only in scattered code comments, which is exactly how
`maint/dotfiles-maint.sh` and `tmux/scripts/tmux-cheat.sh` ended up carrying
`/opt/homebrew` paths into eight repos where seven of them do not exist.

When a rule here drifts from `README.md` or `CONTRIBUTING.md`, those win — fix this.

## 1. The floor is bash 3.2

macOS still ships **bash 3.2** (2007), and `make audit` runs there. Every bash script in
this repo — including the dev tooling in `scripts/` — must parse and run on it.

**Banned outright:**

| Feature | Version | Use instead |
| --- | --- | --- |
| `declare -A` / associative arrays | bash 4.0 | parallel arrays, or a `case` |
| `mapfile` / `readarray` | bash 4.0 | `while IFS= read -r … do … done < <(…)` |
| `${var^^}` / `${var,,}` | bash 4.0 | `tr '[:lower:]' '[:upper:]'` |
| `wait -n` | bash 4.3 | batched `wait` over collected PIDs |
| `&>>`, `\|&` | bash 4.0 | `>>file 2>&1`, `2>&1 \|` |

Live examples of the workaround, all load-bearing: `scripts/audit-core.sh` uses a read
loop rather than `mapfile` for the manifest scan; `scripts/sync-core.sh` uses batched
waits (not `wait -n`) for its parallel prefetch; `lib/bootstrap-lib.sh` and `lib/ux.sh`
both state the constraint at the top.

`set -u` on bash 3.2 also treats an **empty array expansion as unset**, which is why you
will see `"${arr[@]+"${arr[@]}"}"` rather than a bare `"${arr[@]}"`.

## 2. Coreutils are not GNU coreutils

macOS ships BSD tools; Alpine ships busybox. A flag that works on your machine is not
evidence.

**Banned, with the portable form:**

| Non-portable | Why | Portable form |
| --- | --- | --- |
| `sed -i` | BSD requires an arg to `-i` | write to `$(mktemp …)` then `mv` |
| `readlink -f` | not on BSD | a `cd`/`pwd -P` helper |
| `stat -c` / `stat -f` | inverted between GNU and BSD | avoid; use `[[ -nt ]]`, `wc -c` |
| `date -r`, `date -d` | different meanings | for _now_: `${EPOCHSECONDS:-$(date +%s)}` |
| `grep -P` | not in busybox | `grep -E` |
| `sort -V` | not in busybox | `sort` on zero-padded fields |
| `mktemp` with no template | BSD requires one | `mktemp "prefix.XXXXXX"` |
| `xargs -P` | busybox may reject it | branch to plain `xargs` when serial |

`${EPOCHSECONDS:-$(date +%s)}` only covers **now** — it is not a general `date`
replacement. Reading a file's mtime or parsing a supplied date has no portable one-liner:
compare files with `[[ -nt ]]` instead of reading timestamps, and keep any date arithmetic
in epoch seconds you produced yourself.

`grep -q`, `grep -E`, `sort -u`, `cut -c`, `tr -d` are safe everywhere and used freely.

A knob is only a fallback if the code actually takes a different path: `pullall`
documents `PULLALL_JOBS=1` as the busybox escape hatch but still passes `-P "$jobs"`
either way (`zsh/30-functions.zsh:766-768`), so on the one platform it exists for it
fails exactly as before. Branch around the flag, do not just change its value.

Two shipped examples worth copying: `zsh/20-aliases.zsh` probes `diff --color=auto` once
and caches the answer rather than assuming GNU diff (busybox and BSD diff lack it);
`maint/dotfiles-maint.sh` defines `_to()` to use GNU `timeout`, else macOS `gtimeout`,
else run unbounded, and separately treats **both** rc 124 (GNU) and rc ≥128 (busybox
signals its SIGTERM as 143) as "the probe never answered".

## 3. Reach OS capability through a shim, never a path

**This is the rule the boundary gate enforces.** `scripts/audit-core.sh` §5c rejects
`/opt/homebrew`, `/home/linuxbrew`, `/usr/local/Cellar`, `/Library/` and `/mnt/c/` in any
manifested Core file. Its scope is derived from `core.manifest`, so adding a file to the
manifest puts it under the gate automatically.

Nothing is exempt by syntax — **not even comments**. Comment-stripping was tried and
removed: `#` is a comment in shell and TOML but the _length operator_ in Lua; a delimiter
inside a string is code; a line inside a heredoc or a Lua long-bracket string is runtime
data however it starts. Every fix uncovered the next, because doing it correctly needs a
parser for all five grammars the gate now scans.

So the rule is flat: **a manifested Core file must not contain an OS-absolute path
anywhere, prose included.** Name the prefix instead of spelling it — write "the Homebrew
prefix", not the literal. That costs one wording choice in a comment and buys a gate with
no hiding places.

The pattern: **one verb, N backends, chosen by probing for a capability — not by
branching on an OS name.**

| Capability | Shim | Selects by |
| --- | --- | --- |
| clipboard | `bin/clip`, `bin/clip-paste` | `$WSL_DISTRO_NAME` → `pbcopy` → `wl-copy` → `xclip` → `xsel` |
| scheduler | `_maint_scheduler` (`zsh/55-maint.zsh`) | launchd / `/run/systemd/system` / `crontab` |
| package manager | `_pkgup_mgr` (`zsh/60-update.zsh`) | `command -v` over seven managers |
| privilege | `_pkgup_priv`, `_blib_priv` | `sudo` → `doas` → bare |
| timeout | `_to` (`maint/dotfiles-maint.sh`) | `timeout` → `gtimeout` → unbounded |
| binary-name drift | `$FD_BIN`, `$BAT_BIN` (`zsh/00-tools.zsh`) | `fd`/`fdfind`, `bat`/`batcat` |
| layer seam | numbered bands (`zsh/loader.zsh`) | file number, see `VENDORING.md` |

`command -v` is the workhorse. Prefer it to `uname`/`$OSTYPE`: probing for the tool you
are about to run is both more precise and correct on machines the OS test never
anticipated.

**When the capability genuinely cannot be probed**, push the knowledge outward rather
than hardcoding it:

- to the **OS layer** — `os/<os>.zsh` (band 70–84) is where a real OS path belongs;
- to **install time** — `maint-install` captures the live `$PATH` and writes it into the
  scheduler unit, so the runner needs no prefix of its own;
- to an **env var the environment already provides** — `tmux-cheat.sh` reads
  `$HOMEBREW_PREFIX` (exported by `brew shellenv`) and falls back to `brew --prefix`.

If none of those work, degrade **visibly**: add nothing and let the feature fall back, as
`tmux-cheat.sh` does to its pager. A wrong absolute path is a silent lie on seven
machines; a missing optional tool is a visible, local degradation.

### The two documented exceptions

They are exceptions to **different things**, which is worth keeping straight:

1. **`zsh/55-maint.zsh`** is excepted **at the gate**. Its launchd arm legitimately writes
   `~/Library/LaunchAgents` and embeds a plist; its systemd arm embeds a unit. It switches
   on `_maint_scheduler`, the correct cross-OS shape, so the OS-specific text is the
   payload rather than an assumption. §5c drops only its `LaunchAgents` lines — the rest of
   the file is scanned like any other, so unrelated drift inside it still fails.
2. **`zsh/60-update.zsh`** is excepted **architecturally, not at the gate**. It is a
   seven-package-manager driver — the canonical OS-layer concern — kept in Core so `up` is
   one verb everywhere. It needs no gate exclusion because it names no OS-absolute path;
   it would fail §5c like anything else if it did. See `ARCHITECTURE.md`.

`*.example` files are also skipped: they are user-edited illustrations, not live config.

## 4. The `have()` probe is redefined per context, deliberately

`command -v "$1" >/dev/null 2>&1` appears under several names — `_have`
(`zsh/00-tools.zsh`), `_core_have` (`zsh/05-ui.zsh`), `ux_have` (`lib/ux.sh`), `have`
(`scripts/lib/common.sh`), `have` (`maint/dotfiles-maint.sh`), `have`
(`.claude/hooks/session-start.sh`).

That is **intentional, not drift**. Each lives in a different loading context — an
interactive zsh module, a sourced bash library, a gate-script library, a standalone
unattended runner, a repo-meta hook — and they have no shared ancestor to source from.
Giving them one would create a load-order dependency where none exists today, in a tree
whose whole load story is ordering.

Define it locally in a new context too. Do not invent a shared `lib/have.sh`.

## 5. Before you push

```bash
make audit
```

That is the whole gate. Two things worth knowing about it:

- A missing linter **skips** rather than fails, and the summary then labels the run
  `PARTIAL`. A local green with skips is not the same as CI green — read the summary.
- The boundary gate (§5c) is the one that catches layering mistakes. It is cheap and
  unconditional, so a narrowed `--scope` cannot skip it.
