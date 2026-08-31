#!/usr/bin/env bash
# tmux-cheat.sh — a searchable cheatsheet of THIS config's tmux keys, zsh
# widgets, custom commands, aliases, and git aliases. Bound to `prefix + ?`
# (see tmux.conf pop-ups block). fzf-searchable; Enter copies the selected
# command/key to the system clipboard via Core's `clip`. Falls back to the
# pager when fzf isn't installed.
#
# Lives in Core (portable, shared by every repo). To add an entry, drop one
# more `e <group> <key> <description>` line in the data section below.
#
# NOTE: keep this in sync by hand — it documents the config, it does not read it.

set -u

# tmux pop-ups inherit the tmux SERVER's environment, which can be minimal; make sure
# fzf and Core's `clip` resolve. Nothing here is hardcoded: this is portable Core, and
# an absolute Homebrew-prefix path would be wrong on eight of the nine repos it ships to.
#
# $HOME/.local/bin is portable — bootstrap installs `clip` there on every OS. A brew
# prefix, if this box has one, is DISCOVERED rather than named: $HOMEBREW_PREFIX is
# exported by `brew shellenv`, so the server usually carries it, with `brew --prefix`
# as the fallback when brew is already on PATH. If neither resolves we add nothing and
# the script takes its existing pager fallback — a missing tool degrades visibly,
# whereas a wrong absolute path is a silent lie on every non-brew machine.
export PATH="$HOME/.local/bin:$PATH"
_brew_prefix="${HOMEBREW_PREFIX:-}"
if [[ -z "$_brew_prefix" ]] && command -v brew >/dev/null 2>&1; then
  _brew_prefix="$(brew --prefix 2>/dev/null)"
fi
[[ -n "$_brew_prefix" && -d "$_brew_prefix/bin" ]] && export PATH="$PATH:$_brew_prefix/bin"
unset _brew_prefix

rows=()
e() { rows+=("$1"$'\t'"$2"$'\t'"$3"); } # group, key/command, description

# ── TMUX · prefix is C-a ──────────────────────────────────────────────────────
e tmux "C-a" "PREFIX  (double-tap = last window)"
e tmux "prefix r" "reload tmux.conf"
e tmux "prefix c" "new window (keeps path)"
e tmux "prefix ," "rename window"
e tmux "prefix &" "kill window"
e tmux "prefix S" "choose session"
e tmux "prefix d" "detach"
e tmux "prefix R" "refresh client"
e tmux "M-H / M-L" "previous / next window (no prefix)"
e tmux "S-Left / S-Right" "previous / next window (no prefix)"
e pane "prefix h/j/k/l" "select pane  L/D/U/R"
e pane "C-h/j/k/l" "select pane AND cross into nvim splits"
e pane "M-arrows" "select pane (no prefix)"
e pane "prefix |" "split vertical (keeps path)"
e pane "prefix -" "split horizontal (keeps path)"
e pane "prefix \\" "full-height vertical split"
e pane "prefix _" "full-width horizontal split"
e pane "prefix H/J/K/L" "resize pane (hold to repeat)"
e pane "prefix m" "zoom / maximize pane toggle"
e pane "prefix x" "kill pane"
e pane "prefix X" "swap pane down"
e pane "prefix P" "toggle per-pane titles"
e pane "prefix *" "synchronize-panes (type into all)"
e popup "prefix w" "popup menu"
e pane "prefix F" "new floating pane (tmux 3.7+)"
e popup "prefix T" "scratch terminal"
e popup "prefix g" "lazygit"
e popup "prefix a" "Claude Code (one session per repo)"
e popup "prefix f" "sesh session picker"
e popup "prefix u" "fzf URLs out of the pane"
e popup "prefix ?" "this cheatsheet"
e copy "prefix Enter" "enter copy-mode (vi)"
e copy "v" "begin selection (in copy-mode)"
e copy "C-v" "rectangle/block toggle"
e copy "y" "copy selection -> system clipboard (clip)"
e copy "Escape" "cancel copy-mode"

# ── SHELL · zsh key widgets ───────────────────────────────────────────────────
e key "Ctrl-T" "fzf file picker -> insert path"
e key "Ctrl-R" "fzf history search"
e key "Ctrl-E" "Atuin history TUI"
e key "Ctrl-G" "sesh session picker"
e key "Alt-Z" "zoxide jump (fzf)"
e key "Ctrl-\\" "toggle autosuggestions"
e key "Up / Down" "history substring search"
e key "Ctrl-Left/Right" "move by word"

# ── SHELL · custom commands ───────────────────────────────────────────────────
e cmd "up" "apply system updates  (up -y = auto-confirm apt/dnf/zypper)"
e cmd "update-check" "force the update check now"
e cmd "serve [port]" "HTTP server in cwd; prints tunnel/LAN URL"
e cmd "extract <file>" "extract any archive type"
e cmd "mkcd <dir>" "mkdir + cd into it"
e cmd "fcd" "fuzzy-cd into a subdirectory"
e cmd "fif <text>" "find text inside files (rg + fzf)"
e cmd "fbr" "fuzzy git-branch checkout"
e cmd "mkbak <file>" "timestamped backup of a file"
e cmd "please" "re-run last command with sudo"
e cmd "notes" "open notes dir in nvim"
e cmd "myip" "show public IP"
e cmd "ports" "list listening ports"
e cmd "zplugin-update" "update zsh plugins"
e maint "maint-install [HH:MM]" "schedule daily maintenance (default 13:00)"
e maint "maint-run" "run maintenance now (foreground)"
e maint "maint-log [N|-f]" "view maintenance log (last N / follow)"
e maint "maint-status" "when maintenance next runs"
e maint "maint-uninstall" "remove the maintenance schedule"

# ── SHELL · aliases ───────────────────────────────────────────────────────────
e alias "ll / la / lt / llt" "eza listings (long / all / tree)"
e alias "cat / catp" "bat (no-pager / paged)"
e alias "cd / cdi" "zoxide jump / interactive"
e alias "du" "dust"
e alias "ps" "procs"
e alias "top / htop" "btop"
e alias "y / fm" "yazi file manager"
e alias "http / https" "xh (HTTPie)"
e alias "md" "glow (render markdown)"
e alias "dns" "doggo (DNS lookups)"
e alias "g / gs / gd / gl" "git / status / diff / log-graph"
e alias "lg" "lazygit"
e alias "vim" "nvim"

# ── GIT · aliases (run as: git <x>) ───────────────────────────────────────────
e git "git st" "status -sb"
e git "git lg" "pretty graph log (all branches)"
e git "git last" "show last commit + stat"
e git "git co" "checkout"
e git "git br" "branch -vv"
e git "git cm" "commit -m"
e git "git ca / can" "amend / amend --no-edit"
e git "git fix" "commit --fixup (pairs with autosquash)"
e git "git wip / unwip" "quick WIP commit / undo it"
e git "git undo" "soft-reset last commit (keep changes staged)"
e git "git uncommit" "mixed-reset last commit (unstage)"
e git "git discard" "checkout -- (drop file changes)"
e git "git nuke" "clean -fd + reset --hard  (DESTRUCTIVE)"
e git "git pushf" "push --force-with-lease"
e git "git sl / sp / ss" "stash list / pop / save"
e git "git wt / wa / wl" "worktree / add / list"
e git "git mine" "commits authored by you"
e git "git aliases" "list every git alias"

# ── render ────────────────────────────────────────────────────────────────────
# core:theme:gen cheat-sgr
GC=$'\033[38;2;122;162;247m' # tokyonight blue (group)
DIM=$'\033[38;2;86;95;137m'  # comment (description)
# core:theme:end cheat-sgr
RST=$'\033[0m'

# Hoisted out of the fzf invocation below: a marker cannot sit inside a continued
# command, so the --color comma-list gets its own assignment. GENERATED.
# core:theme:gen cheat-fzf-colors
_CHEAT_FZF_COLORS='border:#7aa2f7,prompt:#7dcfff,header:#565f89'
# core:theme:end cheat-fzf-colors

format() { # emits:  <ansi pretty>\t<copy-token>
  printf '%s\n' "${rows[@]}" | awk -F'\t' -v gc="$GC" -v dim="$DIM" -v rst="$RST" '
    { printf "%s%-6s%s %-24s %s%s%s\t%s\n", gc, $1, rst, $2, dim, $3, rst, $2 }'
}

copy() { # $1 = text to put on the clipboard — returns non-zero if nothing landed
  # The exit status is PROPAGATED, not swallowed. `clip`'s last resort is an OSC 52
  # escape, which genuinely fails on a box with no clipboard backend and no terminal to
  # write to; discarding that left the caller announcing a copy that never happened.
  if command -v clip >/dev/null 2>&1; then
    printf '%s' "$1" | clip
  elif command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$1" | pbcopy
  else
    echo "tmux-cheat: no clipboard tool (clip or pbcopy) on PATH" >&2
    return 1
  fi
}

# --list (or no fzf): dump the plain table through the pager.
if [ "${1:-}" = "--list" ] || ! command -v fzf >/dev/null 2>&1; then
  format | sed 's/\t.*$//' | ${PAGER:-less -R}
  exit 0
fi

sel=$(format | fzf --ansi --delimiter=$'\t' --with-nth=1 \
  --no-sort --layout=reverse --border=rounded \
  --prompt='cheat ❯ ' \
  --header='Enter: copy to clipboard   ·   Esc: close' \
  --color="$_CHEAT_FZF_COLORS")
[ -n "$sel" ] || exit 0
# A failed copy has to reach the user through tmux, not through stderr: this runs under
# `display-popup -E`, which tears the popup down the instant the command exits, so
# anything written to stderr here is painted and destroyed in the same frame.
# `display-message` lands in the status line and survives the popup closing.
if copy "$(printf '%s' "$sel" | cut -f2-)"; then
  exit 0
fi
tmux display-message "cheat: copy failed — no clipboard backend reachable" 2>/dev/null || true
exit 1
