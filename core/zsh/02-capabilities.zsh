# core/zsh/02-capabilities.zsh — read the OS layer's capability declaration (v5).
# ──────────────────────────────────────────────────────────────────────────────
# THE POINT. Core's own test (CONTRIBUTING.md) is "if it changes when the OS changes,
# it is not Core" — and Core broke it 154 times: 88 package-manager references in
# 60-update.zsh, 49 in maint/dotfiles-maint.sh, 17 in 30-functions.zsh, including a
# `grep -qi tumbleweed /etc/os-release` to pick `zypper dup` over `zypper up`.
#
# ARCHITECTURE.md defended that as "one verb with N backends", and the defence of the
# VERB is correct — `up` belongs in Core so every machine has the same muscle memory.
# What expired is the defence of the IMPLEMENTATION: one verb with N backends is what
# a dispatch table is for. The verb stays here; the backends move to the layer that
# changes with the OS, and this file reads them back.
#
# This fragment ONLY populates the table. Nothing in Core dispatches through it yet —
# `up` (#664), the maint scheduler (#665) and core-doctor's opt-in split (#666) are
# separate changes. Landing the schema alone keeps the foundational commit small.
#
# WHY A DATA FILE AND NOT A FRAGMENT. loader.zsh globs `[0-9][0-9]-*.zsh` and sources
# by NN order, so a declaration named `os.capabilities` is never globbed — it has to be
# READ. That is deliberate: the declaration is DATA authored by the OS repo, not code
# Core sources into your interactive shell.
#
# WHY EXTRACTED, NOT SOURCED. `source`-ing a per-repo file into a login shell is a
# code-execution surface: any line in it runs. Extraction cannot execute anything.
# This mirrors the reasoning already recorded at scripts/setup.sh:23-26 for
# tool-versions.env — "no `source`, so no shellcheck follow needed" — and keeps the same
# KEY=value shape, so the file is equally readable from bash (maint/dotfiles-maint.sh
# is not zsh) with a one-line `sed`.
#
# WHY BAND 02. It must precede every consumer; the earliest is 30-functions. Band 02
# sits inside the Core band (00-69), so EVERY profile loads it — `minimal`'s ceiling is
# 30 — which matters because a lean profile must not silently lose the dispatch table.
# It is deliberately NOT folded into 00-tools.zsh: that file is the single init point
# for TOOL DETECTION, and a capability declaration is a different concern.
#
# NO EXTENDED_GLOB HERE. `setopt EXTENDED_GLOB` is 10-options.zsh's, eight bands later,
# so `#`/`##`/`^` are literal in this file. The trailing-space trim below is a `%?` loop
# for exactly that reason; do not "simplify" it to `${v%%[[:space:]]##}`, which would
# match nothing at this point in the chain and fail silently.
#
# WHY IT WARNS RATHER THAN FAILS. A box with no declaration keeps working on Core's
# existing hardcoded ladders. The alternative — hard-failing at startup — would leave
# an unusable interactive shell on a box you are very likely SSH'd into precisely to
# fix it. Enforcement belongs in the audit (a gate you run), not the login shell.
#
# BIN/CLIP IS DELIBERATELY NOT HERE. Its backend ladder stays hardcoded: bin/clip is
# re-exec'd by nvim and tmux on EVERY yank and paste, and its WSL probe was already
# rewritten to avoid forking a `grep` per invocation (see bin/clip's header). Adding a
# file read and parse to that path would give back exactly what that bought, for a
# value that changes once per machine.
# ──────────────────────────────────────────────────────────────────────────────

# The table. Global and associative: consumers read it through _core_cap below, and an
# undeclared key yields the empty string.
typeset -gA _CORE_CAP=()

# Where blib_link_os_layer lands the OS repo's declaration (os/<os>.capabilities).
# Overridable for the test suite, which seeds a file in a throwaway $ZSH_CFG.
: "${CORE_CAPABILITIES_FILE:=${ZSH_CFG:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}/os.capabilities}"

if [[ -r "$CORE_CAPABILITIES_FILE" ]]; then
  # Parsed in-shell rather than by forking a `sed`: this runs on every interactive shell
  # and the file is ~10 lines. `IFS= read -r` preserves interior spacing, which matters
  # because the values ARE multi-word command prefixes (`sudo dnf install -y`).
  #
  # Deliberately strict about what counts as a key: a line must match KEY=value where
  # KEY is [A-Z][A-Z0-9_]*. Anything else — a comment, a blank line, a stray token, a
  # lowercase key — is skipped in silence rather than half-parsed into the table. The
  # audit is what REPORTS a malformed declaration; the shell just refuses to be confused
  # by one. No top-level `local` (nothing else in Core uses it outside a function, and
  # this file is sourced at the loader's scope, not inside one) — hence the _cap_ prefix
  # and the explicit unset.
  while IFS= read -r _cap_line || [[ -n "$_cap_line" ]]; do
    [[ "$_cap_line" == [A-Z]*=* ]] || continue
    _cap_k="${_cap_line%%=*}"
    [[ "$_cap_k" == *[^A-Z0-9_]* ]] && continue
    _cap_v="${_cap_line#*=}"
    # Trim trailing whitespace only. A leading space would be part of a command prefix
    # and is the author's business; a trailing one is invisible and always an accident.
    while [[ "$_cap_v" == *[[:space:]] ]]; do _cap_v="${_cap_v%?}"; done
    _CORE_CAP[$_cap_k]="$_cap_v"
  done <"$CORE_CAPABILITIES_FILE"
  unset _cap_line _cap_k _cap_v
elif [[ -n "${CORE_CAP_LOUD:-}" ]]; then
  # ABSENT IS THE NORMAL STATE, so silence is the default and this warning is OPT-IN.
  # It shipped the other way round and could not have been right: no OS repo has authored
  # os/<os>.capabilities yet, blib_link_os_layer's `[[ -f ]]` guard therefore links nothing,
  # and this branch is unthrottled — so every interactive shell, every tmux split and every
  # `zsh -i -c` on every box in the fleet printed two lines of stderr. The remedy it named
  # was worse than the noise: `bootstrap.sh --links-only` re-runs the SAME guard, so an
  # operator who followed the advice saw nothing change and the warning persist.
  #
  # Nothing dispatches through $_CORE_CAP yet, so a missing declaration costs a box exactly
  # nothing today — there is no user-visible degradation to warn anyone about. When a
  # consumer lands, the thing to warn about is that consumer falling back, at ITS call site,
  # where the message can name what actually degraded. Flip this default back only when the
  # warning can be both true and actionable.
  #
  # 05-ui.zsh defines _core_warn/_core_hint — and it loads AFTER this fragment, so those
  # helpers do not exist yet. Write the plain thing rather than call a function that is
  # not there. stderr, so it never pollutes a `$(...)` capture from a login shell.
  print -u2 -- "core: no OS capability declaration at ${CORE_CAPABILITIES_FILE}"
  print -u2 -- "  -> Core is using its built-in defaults. To declare this OS's verbs, author"
  print -u2 -- "     os/<os>.capabilities in your OS repo (see core/examples/os.capabilities.example),"
  print -u2 -- "     then re-run its ./bootstrap.sh --links-only to link it."
fi

# _core_cap <key> [fallback] — read one capability, echoing <fallback> when the key is
# absent OR declared empty. THE accessor: consumers must not index _CORE_CAP directly,
# so that "declared but empty" and "never declared" collapse to one behaviour, here.
_core_cap() {
  emulate -L zsh
  local _v="${_CORE_CAP[$1]:-}"
  print -r -- "${_v:-${2-}}"
}
