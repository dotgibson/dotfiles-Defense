# core/zsh/history.zsh
# ──────────────────────────────────────────────────────────────────────────────
# Portable zsh history config. NEW in the 2026 refresh, and it matters even with
# atuin: atuin IMPORTS from and (by default) shadows zsh history, and
# zsh-history-substring-search (bound to the arrow keys in bindings.zsh) reads the
# in-memory history list — both need HISTFILE/SAVEHIST set sanely. Previously this
# lived (if at all) in each OS .zshrc; centralizing it here removes that drift.
#
# LOAD ORDER: source THIRD, after options.zsh, before aliases.zsh.
# ──────────────────────────────────────────────────────────────────────────────

[[ $- == *i* ]] || return 0

# v4: history is mutable STATE, not config — it lives under $XDG_STATE_HOME, not in the
# symlinked $ZDOTDIR config tree. (Pre-v4 hosts had ~/.config/zsh/.zsh_history; the
# bootstrap relocates it here on re-bootstrap so no history is lost.)
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=200000 # lines kept in memory
SAVEHIST=200000 # lines written to $HISTFILE
[[ -d ${HISTFILE:h} ]] || mkdir -p "${HISTFILE:h}"

setopt EXTENDED_HISTORY     # write :start:elapsed;command (atuin import-friendly)
setopt SHARE_HISTORY        # share across live sessions (implies incremental append)
setopt HIST_IGNORE_ALL_DUPS # drop older dup when a command repeats (supersedes HIST_IGNORE_DUPS)
setopt HIST_FIND_NO_DUPS # don't show dups when searching
setopt HIST_IGNORE_SPACE # a leading space keeps a command out of history
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY   # expand !! to the line for review, don't run blind
setopt HIST_NO_STORE # don't store the `history`/`fc` calls themselves
setopt HIST_SAVE_NO_DUPS

# Never record obviously sensitive one-liners to the plaintext HISTFILE. atuin
# has its own richer filtering (history_filter in config.toml) — this is the
# belt-and-suspenders for the flat file. Operator habit: prefix anything spicy
# with a space (HIST_IGNORE_SPACE) and it never lands anywhere.
HISTORY_IGNORE='(pass show *|pass read *|pass insert *|op read*|*--password[ =]*|*--token[ =]*|*--api-key[ =]*|*PASSWORD=*|*TOKEN=*|*API_KEY*|*APIKEY*|*SECRET*|*ACCESS_KEY=*)'
