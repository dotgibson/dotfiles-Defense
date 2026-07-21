# 25-git.zsh — curated git aliases + helpers
#
# Provenance: a hand-picked subset of the oh-my-zsh `git` plugin, with the
# framework, auto-updater, and ~100 rarely-used aliases stripped out. Drop this
# into dotfiles-core as a standalone zsh module; it sources cleanly on its own
# and carries no OMZ dependency.
#
# Naming matches OMZ so existing muscle memory transfers. Two intentional
# deviations from upstream, both safety upgrades:
#   - gpf  -> --force-with-lease (OMZ's gpf is a raw --force; lease refuses to
#            clobber commits you haven't seen). Raw force is still here as gpf!.
#   - no destructive aliases bound to bare letters that shadow common typos.
#
# Branch-aware aliases resolve the trunk via git_main_branch(), so they work
# whether a repo uses main, master, trunk, etc.

# ── helpers ──────────────────────────────────────────────────────────────────

# Current branch name (empty outside a repo / on detached HEAD failure).
function git_current_branch() {
  local ref
  # `git branch --show-current` (git 2.22+) is the porcelain for the checked-out branch.
  # It prints empty on a detached HEAD — fall back to a short SHA there — and stays empty
  # outside a repo (rev-parse also fails), preserving both original behaviours.
  ref=$(command git branch --show-current 2>/dev/null)
  [[ -n $ref ]] && { echo "$ref"; return; }
  command git rev-parse --short HEAD 2>/dev/null
}

# Resolve the trunk branch for this repo (main, master, trunk, ...).
function git_main_branch() {
  command git rev-parse --git-dir &>/dev/null || return
  local ref
  # Fast path: origin/HEAD names the remote's default branch authoritatively in ONE call
  # (the usual case for a cloned repo) — no need to probe the candidate list. symbolic-ref
  # succeeds even when origin/HEAD is DANGLING (points at a branch pruned/renamed upstream),
  # so verify the referent actually exists before trusting it; a stale target falls through.
  if ref=$(command git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
    && command git show-ref -q --verify "refs/remotes/$ref"; then
    echo "${ref#origin/}"
    return 0
  fi
  # Fallback (origin/HEAD unset or stale): probe the known trunk names locally + on remotes.
  for ref in refs/{heads,remotes/{origin,upstream}}/{main,trunk,mainline,default,stable,master}; do
    if command git show-ref -q --verify "$ref"; then
      echo "${ref:t}"
      return 0
    fi
  done
  echo master
}

# ── git itself ────────────────────────────────────────────────────────────────
alias g='git'

# ── status / inspection ──────────────────────────────────────────────────────
alias gst='git status'
alias gss='git status --short'
alias gsb='git status --short --branch'

# ── staging ──────────────────────────────────────────────────────────────────
alias ga='git add'
alias gaa='git add --all'
alias gap='git add --patch'

# ── commit ───────────────────────────────────────────────────────────────────
alias gc='git commit --verbose'
alias gcm='git commit --message'              # NOTE: OMZ uses gcm for "checkout main"
alias gca='git commit --verbose --all'
alias gcam='git commit --all --message'
alias 'gc!'='git commit --verbose --amend'
alias 'gcn!'='git commit --verbose --no-edit --amend'   # amend, keep message

# ── branch ───────────────────────────────────────────────────────────────────
alias gb='git branch'
alias gba='git branch --all'
alias gbd='git branch --delete'
alias 'gbD'='git branch --delete --force'
alias gbm='git branch --move'

# ── checkout / switch ────────────────────────────────────────────────────────
alias gco='git checkout'
alias gcb='git checkout -b'
alias gcom='git checkout "$(git_main_branch)"'
alias gsw='git switch'
alias gswc='git switch --create'
alias gswm='git switch "$(git_main_branch)"'

# ── diff ─────────────────────────────────────────────────────────────────────
alias gd='git diff'
alias gds='git diff --staged'
alias gdw='git diff --word-diff'

# ── log ──────────────────────────────────────────────────────────────────────
alias glog='git log --oneline --decorate --graph'
alias gloga='git log --oneline --decorate --graph --all'
alias glol="git log --graph --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset'"
alias glola="git log --graph --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --all"

# ── fetch / pull / push ──────────────────────────────────────────────────────
alias gf='git fetch'
alias gfa='git fetch --all --prune --tags'
alias gl='git pull'
alias gpr='git pull --rebase'
alias gp='git push'
alias gpu='git push --set-upstream origin "$(git_current_branch)"'
alias gpf='git push --force-with-lease'       # safe force (upgrade vs OMZ)
alias 'gpf!'='git push --force'               # raw force, explicit

# ── stash ────────────────────────────────────────────────────────────────────
alias gsta='git stash push'
alias gstaa='git stash push --include-untracked'
alias gstp='git stash pop'
alias gstl='git stash list'
alias gstd='git stash drop'

# ── rebase ───────────────────────────────────────────────────────────────────
alias grb='git rebase'
alias grbi='git rebase --interactive'
alias grbm='git rebase "$(git_main_branch)"'
alias grbc='git rebase --continue'
alias grba='git rebase --abort'

# ── reset / restore ──────────────────────────────────────────────────────────
alias grh='git reset'                         # unstage / soft-ish (no --hard)
alias grhh='git reset --hard'
alias grs='git restore'
alias grss='git restore --staged'

# ── remote / merge ───────────────────────────────────────────────────────────
alias gr='git remote'
alias grv='git remote --verbose'
alias gm='git merge'
alias gma='git merge --abort'

# ── fzf-assisted staging / restore ────────────────────────────────────────────
# Interactive counterparts to the static aliases above: fuzzy multi-select instead
# of typing paths. Portable (depend only on git + fzf, both in the Core stack); each
# guards on fzf like the zle widgets in 35-fzf.zsh, so a bare box degrades cleanly. NUL
# piping via tr keeps paths with spaces intact through xargs.
function gaf() {  # fuzzy `git add` — pick from modified + untracked
  _core_have fzf || { _core_warn "gaf: needs fzf"; return 1; }
  local files
  files=$(command git ls-files --modified --others --exclude-standard |
    fzf --multi --prompt='add> ' --preview 'git diff --color=always -- {} | head -200') || return
  [[ -n $files ]] && print -r -- "$files" | tr '\n' '\0' | xargs -0 git add -- && command git status --short
}
function grf() {  # fuzzy `git restore` — discard unstaged changes to picked files
  _core_have fzf || { _core_warn "grf: needs fzf"; return 1; }
  local files
  files=$(command git diff --name-only |
    fzf --multi --prompt='restore> ' --preview 'git diff --color=always -- {} | head -200') || return
  [[ -n $files ]] && print -r -- "$files" | tr '\n' '\0' | xargs -0 git restore --
}
function grsf() { # fuzzy `git restore --staged` — unstage picked files
  _core_have fzf || { _core_warn "grsf: needs fzf"; return 1; }
  local files
  files=$(command git diff --staged --name-only |
    fzf --multi --prompt='unstage> ' --preview 'git diff --staged --color=always -- {} | head -200') || return
  [[ -n $files ]] && print -r -- "$files" | tr '\n' '\0' | xargs -0 git restore --staged --
}
