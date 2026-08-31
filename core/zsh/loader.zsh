# core/zsh/loader.zsh — the canonical numbered-fragment loader (v4).
# ──────────────────────────────────────────────────────────────────────────────
# v4 replaced the hand-declared `_CORE_MODULES` name array with numbered fragments:
# every Core module is `NN-name.zsh`, the OS layer lands as `80-os.zsh`, a role stage
# as `85-*.zsh`, and host tweaks as `99-local.zsh` — all symlinked FLAT into $ZSH_CFG.
# An OS .zshrc no longer lists module names; it sets the config dir and sources this
# file, which globs the fragments, sorts by the NN prefix, and sources each in order:
#
#     ZSH_CFG="${ZDOTDIR:-$HOME/.config/zsh}"
#     source "$ZSH_CFG/loader.zsh"
#
# CRITICAL — this is SOURCED at the caller's scope, NOT wrapped in a function. The
# fragments set options (setopt), define aliases, and run compinit; those must persist
# into the interactive shell. A function body with `emulate -L`/LOCAL_OPTIONS (as most
# Core helpers use) would REVERT every option change on return — silently breaking the
# shell. So the loop runs inline; its `_cl_*` scratch vars are unset at the end. The one
# name it leaves behind on purpose is $ZSH_CFG, defaulted just below when the caller did
# not set it — 02-capabilities.zsh reads it back to find the OS declaration.
#
# EVERY `NN-*.zsh` in $ZSH_CFG is sourced. No ceiling, no filter, no opt-out: v5 deleted
# `CORE_PROFILE`, which was the only mechanism that ever skipped a fragment. The bands —
# Core 00-69, OS-native 70-84, Role 85-94, host-local 95-99 — are a HUMAN convention for
# reserving ranges between the layers, and this file deliberately does NOT enforce them.
# It never could honestly: everything is flattened into one $ZSH_CFG, so the loader has no
# owner metadata, and the gate it used to apply keyed off the NUMBER, not authorship. That
# is the point of the change, not a regression in it. An OS or role repo that squats a Core
# gap (`22-foo.zsh`, to run between 20-aliases and 25-git) is now merely UNCONVENTIONAL: it
# loads, exactly where it asked to. Under the old ceiling that same file was treated as Core
# and could silently VANISH on a lean host, with nothing in the shell to say why. Respect
# the ranges anyway, for the reason that outlives the gate: a flat symlink dir holds exactly
# one `22-foo.zsh`, so a number an OS repo takes is a number a later Core release cannot.
#
# What this file DOES enforce is shape and order. SHAPE: exactly two digits and a dash, or
# it is not a fragment at all — which is why loader.zsh, carrying no NN- prefix, can live in
# the very directory it globs. ORDER: a sort on the fixed-width NN, with a same-NN tie (a
# misconfiguration, since the ranges exist to prevent one) broken lexically by filename,
# deterministically, on every machine.
#
# Each fragment is byte-compiled to a sibling .zwc before sourcing: `source file`
# auto-loads `file.zwc` wordcode when it is present and current, skipping a re-parse —
# meaningful across ~13 fragments on every shell. The compile only runs when the source
# is newer than its .zwc (or the .zwc is missing), so it self-heals: edit a fragment (or
# `git pull`) and the next shell recompiles just that file. zcompile is a builtin (no
# `>` redirection), so 10-options.zsh's NO_CLOBBER doesn't apply, and it writes the .zwc
# atomically. The .zwc lands beside the fragment symlink in $ZSH_CFG (a real, writable
# dir of symlinks), never the repo; `2>/dev/null` keeps a read-only $ZSH_CFG a silent
# no-op that just sources the plain script. NOTE: the .zwc MUST sit beside its source —
# that is how zsh's automatic wordcode pickup works — so byte-compiled wordcode is the
# one piece of runtime state the v4 XDG split deliberately leaves in $ZSH_CFG rather
# than relocating to $XDG_CACHE_HOME (history/compdump/plugins do move).
# ──────────────────────────────────────────────────────────────────────────────

: "${ZSH_CFG:=${ZDOTDIR:-$HOME/.config/zsh}}"
# Nothing to do without a config dir — keeps a bare source (e.g. a tool that sources
# this file with no fragments present) a clean no-op, even under `setopt nounset`.
[[ -d "$ZSH_CFG" ]] || return 0

# Plain (not `local`) scratch vars + an explicit unset at the end: this file is SOURCED
# at the caller's top level, where `local` is an error — mirroring the inline loop it
# replaces. `[0-9][0-9]-` matches EXACTLY the two-digit NN prefix a fragment must carry,
# so loader.zsh itself (no NN- prefix) is never globbed and a malformed `1-`/`100-` name is
# ignored rather than mis-banded; `N` is nullglob (no fragments → clean no-op).
# Sort EXPLICITLY with the `(o)` parameter flag — a lexical sort independent of the caller's
# NUMERIC_GLOB_SORT option — NOT the glob's own `n`/numeric sort. The fixed-width 2-digit NN
# still orders correctly lexically, and a same-NN tie breaks lexically by filename exactly as
# the contract promises (numeric sort would instead put `85-r10` AFTER `85-r2`, natural order).
_cl_frags=("$ZSH_CFG"/[0-9][0-9]-*.zsh(N))
for _cl_f in "${(@o)_cl_frags}"; do
  # The glob matches NAMES, not contents, so a DANGLING symlink — a fragment whose repo file
  # moved, the ordinary state mid-`git pull` or mid-vendor-sync in a dir that is nothing but
  # symlinks — still matches, and `source` on it writes to stderr, which the load-order smoke
  # test reads as a broken chain. One absent fragment is not a reason to fail the whole shell.
  [[ -r "$_cl_f" ]] || continue
  # NO trailing name arg = script mode: writes "$_cl_f.zwc" (a function-name arg would
  # switch zcompile to digest mode, which `source` can't use as wordcode — keep it single-arg).
  [[ -s "$_cl_f.zwc" && ! "$_cl_f" -nt "$_cl_f.zwc" ]] || zcompile -R -- "$_cl_f" 2>/dev/null
  source "$_cl_f"
done
unset _cl_frags _cl_f
