# Core Aliases Cheat Sheet

Most aliases sourced from `zsh/aliases.zsh` and `zsh/git.zsh`; exception: `cheat` is
defined in `zsh/functions.zsh` (alias for `core-help`). Tool aliases are guarded
by detection flags — if the tool is not installed, the classic command is used instead.
Load order: `tools.zsh` sets `HAVE_*` flags first, then `aliases.zsh` reads them.

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

## Network

| Alias | Expands To |
| ------- | ------------ |
| `myip` | `curl -fsS https://ifconfig.me` |
| `ports` | `ss -tulpn` (falls back to `netstat -tulpn`) |

## Jujutsu

Active when `jj` is installed — `tools.zsh` detects the binary and sets `HAVE_JJ`
automatically. No manual config required; install `jj` and these aliases appear.

| Alias | Expands To |
| ------- | ------------ |
| `jjs` | `jj status` |
| `jjl` | `jj log` |
| `jjd` | `jj diff` |

## Upstream Sync

A function (not an alias), so it works from inside any OS repo's vendored
`core/` subtree without needing `.bin` on `PATH`.

| Command | Expands To |
| ------- | ------------ |
| `gsync` | `.bin/sync-upstream.sh` — pushes an OS repo's vendored `core/` subtree back upstream to dotfiles-core |

---

## Git Aliases

Sourced from `zsh/git.zsh` (OMZ-compatible). Three interactive fuzzy helpers
(`gaf`, `grf`, `grsf`) are functions, not aliases — see `zsh/git.zsh` for details.

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
