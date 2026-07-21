# Core Aliases Cheat Sheet

Most aliases sourced from `zsh/20-aliases.zsh` and `zsh/25-git.zsh`; exception: `cheat` is
defined in `zsh/30-functions.zsh` (alias for `core-help`). Tool aliases are guarded
by detection flags — if the tool is not installed, the classic command is used instead.
Load order: `00-tools.zsh` sets `HAVE_*` flags first, then `20-aliases.zsh` reads them.

The user-facing **shell functions** from `zsh/30-functions.zsh` are listed too (see
[Shell Functions](#shell-functions)) — you type them like any other command, so they
belong on the same cheat sheet.

## Modern CLI Replacements

| Alias | Expands To | Requires |
| ------- | ----------- | ---------- |
| `ls` | `eza --group-directories-first --icons=auto` | eza |
| `ll` | `eza -lah --group-directories-first --icons=auto --git` | eza |
| `la` | `eza -a --group-directories-first --icons=auto` | eza |
| `lt` | `eza --tree --level=2 --icons=auto` | eza |
| `llt` | `eza --tree --level=3 -l --icons=auto` | eza |
| `tree` | `eza --tree --icons=auto` | eza |
| `cat` | `bat --paging=never` | bat |
| `catp` | `bat` (paged) | bat |
| `fd` | `fdfind` or `fd` (Debian-aware) | fd-find / fd |
| `rg` | `rg --smart-case` | ripgrep |
| `cd` | `z` (directory jumper) | zoxide |
| `cdi` | `zi` (interactive jump) | zoxide |
| `du` | `dust` | dust |
| `ps` | `procs` | procs |
| `top` | `btop` | btop |
| `htop` | `btop` | btop |
| `watch` | `viddy` | viddy |
| `df` | `duf` | duf |
| `fm` | `yazi` | yazi |
| `y` | `yazi` | yazi |
| `http` | `xh` | xh |
| `https` | `xh --https` | xh |
| `md` | `glow --pager` | glow |
| `dns` | `doggo` | doggo |
| `ping` | `gping` | gping |
| `help` | `tldr` | tldr |

## Editors & Launchers

| Alias | Expands To |
| ------- | ------------ |
| `vim` | `nvim` |
| `lg` | `lazygit` |
| `notes` | `cd "$NOTES_DIR" && nvim .` |
| `cheat` | `core-help` (built-in help index) |

## Navigation & Safety

| Alias | Expands To |
| ------- | ------------ |
| `-` | `cd -` (previous directory) |
| `diff` | `diff --color=auto` |
| `rm` | `rm -i` (interactive) |
| `cp` | `cp -i` (interactive) |
| `mv` | `mv -i` (interactive) |
| `mkdir` | `mkdir -p` (create parents) |

## Named Directories

Zsh named directories (from `zsh/20-aliases.zsh` via `hash -d`) — type them anywhere a
path is expected, e.g. `cd ~dots` or `nvim ~proj/foo`:

| Shortcut | Expands To |
| ------- | ------------ |
| `~dots` | `$HOME/.config` |
| `~proj` | `$HOME/Projects` |

## Network

| Alias | Expands To |
| ------- | ------------ |
| `myip` | `curl -fsS https://ifconfig.me` |
| `ports` | `ss -tulpn` (falls back to `netstat -tulpn`) |

## Jujutsu

Active when `jj` is installed — `00-tools.zsh` detects the binary and sets `HAVE_JJ`
automatically. No manual config required; install `jj` and these aliases appear.

| Alias | Expands To |
| ------- | ------------ |
| `jjs` | `jj status` |
| `jjl` | `jj log` |
| `jjd` | `jj diff` |

## Shell Functions

Sourced from `zsh/30-functions.zsh`. These are functions rather than aliases because
they take arguments, validate them, or need real control flow — but you invoke them
exactly like any other command. Every one accepts `--help`, ships a completion, and is
also listed by `core help` (aliased to `cheat` above); the descriptions below are the
same one-liners those surfaces print.

| Command | Does |
| ------- | ------------ |
| `mkcd <dir>` | make a directory (and parents) and cd into it |
| `cdup [n]` | climb n directories (default 1); `cdup 3` == `cd ../../..` |
| `fcd` | fuzzy-cd into any subdirectory (fzf + fd, degrades to find) |
| `extract <archive>` | unpack any archive (tar/zip/7z/rar/…); guards tarbombs + clobbers |
| `mkbak <file>` | timestamped `.bak` copy of a file before you edit it |
| `serve [-l\|--local] [port]` | HTTP server in the CWD (default 8000); all interfaces, or loopback with `-l` |
| `genpw [length]` | random alphanumeric password (default 16) via openssl, `/dev/urandom` fallback |
| `please` | re-run the last command with sudo (previews + confirms first) |
| `pullall [dir]` | pull every git repo under a dir in parallel (prunes, stashes, fast-forwards trunk) |

Note `cdup`, not `up` — `up` is the package-updater in `zsh/60-update.zsh`.

`extract` and `please` confirm before doing something destructive or privileged — an
overwrite/tarbomb scatter, and running your last command as root. That confirmation
*declines* when there is no TTY, so a scripted or piped run fails safe rather than
proceeding unattended. `serve` binds all interfaces on purpose (it's an ad-hoc
file-transfer server); pass `-l` to keep it on loopback.

## Upstream Sync

A function (not an alias), so it works from inside any OS repo's vendored
`core/` subtree without needing `.bin` on `PATH`.

| Command | Expands To |
| ------- | ------------ |
| `gsync` | `.bin/sync-upstream.sh` — pushes an OS repo's vendored `core/` subtree back upstream to dotfiles-core |

---

## Git Aliases

Sourced from `zsh/25-git.zsh` (OMZ-compatible). Three interactive fuzzy helpers
(`gaf`, `grf`, `grsf`) are functions, not aliases — see `zsh/25-git.zsh` for details.

### Core

| Alias | Expands To |
| ------- | ------------ |
| `g` | `git` |

### Status

| Alias | Expands To |
| ------- | ------------ |
| `gst` | `git status` |
| `gss` | `git status --short` |
| `gsb` | `git status --short --branch` |

### Staging

| Alias | Expands To |
| ------- | ------------ |
| `ga` | `git add` |
| `gaa` | `git add --all` |
| `gap` | `git add --patch` |

### Commit

| Alias | Expands To |
| ------- | ------------ |
| `gc` | `git commit --verbose` |
| `gcm` | `git commit --message` |
| `gca` | `git commit --verbose --all` |
| `gcam` | `git commit --all --message` |
| `gc!` | `git commit --verbose --amend` |
| `gcn!` | `git commit --verbose --no-edit --amend` |

### Branch

| Alias | Expands To |
| ------- | ------------ |
| `gb` | `git branch` |
| `gba` | `git branch --all` |
| `gbd` | `git branch --delete` |
| `gbD` | `git branch --delete --force` |
| `gbm` | `git branch --move` |

### Checkout / Switch

| Alias | Expands To |
| ------- | ------------ |
| `gco` | `git checkout` |
| `gcb` | `git checkout -b` |
| `gcom` | `git checkout <main branch>` |
| `gsw` | `git switch` |
| `gswc` | `git switch --create` |
| `gswm` | `git switch <main branch>` |

### Diff

| Alias | Expands To |
| ------- | ------------ |
| `gd` | `git diff` |
| `gds` | `git diff --staged` |
| `gdw` | `git diff --word-diff` |
| `gdft` | `git difftool --tool=difftastic` (opt-in structural diff; requires `HAVE_DIFFT`) |

### Log

| Alias | Expands To |
| ------- | ------------ |
| `glog` | `git log --oneline --decorate --graph` |
| `gloga` | `git log --oneline --decorate --graph --all` |
| `glol` | Compact pretty log (abbreviated hash + relative time) |
| `glola` | Compact pretty log — all branches |

### Fetch / Pull / Push

| Alias | Expands To |
| ------- | ------------ |
| `gf` | `git fetch` |
| `gfa` | `git fetch --all --prune --tags` |
| `gl` | `git pull` |
| `gpr` | `git pull --rebase` |
| `gp` | `git push` |
| `gpu` | `git push --set-upstream origin <branch>` |
| `gpf` | `git push --force-with-lease` (safe force) |
| `gpf!` | `git push --force` (raw force) |

### Stash

| Alias | Expands To |
| ------- | ------------ |
| `gsta` | `git stash push` |
| `gstaa` | `git stash push --include-untracked` |
| `gstp` | `git stash pop` |
| `gstl` | `git stash list` |
| `gstd` | `git stash drop` |

### Rebase

| Alias | Expands To |
| ------- | ------------ |
| `grb` | `git rebase` |
| `grbi` | `git rebase --interactive` |
| `grbm` | `git rebase <main branch>` |
| `grbc` | `git rebase --continue` |
| `grba` | `git rebase --abort` |

### Reset / Restore

| Alias | Expands To |
| ------- | ------------ |
| `grh` | `git reset` |
| `grhh` | `git reset --hard` |
| `grs` | `git restore` |
| `grss` | `git restore --staged` |

### Remote / Merge

| Alias | Expands To |
| ------- | ------------ |
| `gr` | `git remote` |
| `grv` | `git remote --verbose` |
| `gm` | `git merge` |
| `gma` | `git merge --abort` |
