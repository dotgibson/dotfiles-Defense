# core/zsh/loader.zsh — the canonical numbered-fragment loader (v4).
# ──────────────────────────────────────────────────────────────────────────────
# v4 replaced the hand-declared `_CORE_MODULES` name array with numbered fragments:
# every Core module is `NN-name.zsh`, the OS layer lands as `80-os.zsh`, a role stage
# as `85-*.zsh`, and host tweaks as `99-local.zsh` — all symlinked FLAT into $ZSH_CFG.
# An OS .zshrc no longer lists module names; it sets the config dir + profile and
# sources this file, which globs the fragments, sorts by the NN prefix, and sources
# each in order:
#
#     ZSH_CFG="${ZDOTDIR:-$HOME/.config/zsh}"
#     source "$ZSH_CFG/loader.zsh"
#
# The profile is resolved by this file (not the caller): an explicit CORE_PROFILE in the
# environment wins; else a one-liner in $ZSH_CFG/profile (minimal|standard|full); else full.
#
# CRITICAL — this is SOURCED at the caller's scope, NOT wrapped in a function. The
# fragments set options (setopt), define aliases, and run compinit; those must persist
# into the interactive shell. A function body with `emulate -L`/LOCAL_OPTIONS (as most
# Core helpers use) would REVERT every option change on return — silently breaking the
# shell. So the loop runs inline; its `_cl_*` scratch vars are unset at the end. It does
# deliberately leave `CORE_PROFILE` set in the shell (resolved just below), so subshells
# and the user can read back the active profile — that persistence is intentional, not a leak.
#
# CORE_PROFILE gates by BAND NUMBER, not authorship (the loader has no owner metadata —
# everything is flattened into one $ZSH_CFG). Fragments numbered 00-69 are the "Core band"
# and are profile-gated: `minimal` stops after 30-functions, `standard` after 50-op, `full`
# loads all of 00-69. Fragments >=70 (OS at 80, role at 85-94, host-local at 99) ALWAYS
# load regardless of profile — so essential OS/host setup lives there and a lean profile
# can never drop it. COROLLARY: a fragment an OS/role repo deliberately places in a Core
# gap (e.g. 22-foo.zsh, to run mid-chain between 20-aliases and 25-git) rides the Core band
# and is therefore profile-gated too. If it must always load, number it >=70. Ordering is a
# pure numeric sort on NN; a same-NN tie (a misconfiguration) breaks lexically by filename.
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

# Profile resolution — THIS file is the single point of truth (the managed .zshrc no
# longer pre-sets it): an explicit CORE_PROFILE in the environment wins; else the first
# WORD of a persistent $ZSH_CFG/profile one-liner; else the `full` default below.
# Read the first field only (`_` soaks up the rest): a stray trailing token or trailing
# whitespace in the file then can't smuggle itself into CORE_PROFILE and make the `case`
# below miss every arm and fall through to `full`.
if [[ -z ${CORE_PROFILE:-} && -r "$ZSH_CFG/profile" ]]; then
  read -r CORE_PROFILE _ < "$ZSH_CFG/profile"
fi

: "${CORE_PROFILE:=full}"
# Core-band ceiling per profile: Core fragments (00-69) numbered ABOVE it are skipped;
# outer fragments (>=70) always load. An unknown value falls through to `full` (safest).
case "$CORE_PROFILE" in
  minimal)  _cl_ceil=30 ;;
  standard) _cl_ceil=50 ;;
  *)        _cl_ceil=69 ;;
esac

# Plain (not `local`) scratch vars + an explicit unset at the end: this file is SOURCED
# at the caller's top level, where `local` is an error — mirroring the inline loop it
# replaces. `[0-9][0-9]-` matches EXACTLY the two-digit NN prefix the band contract requires,
# so loader.zsh itself (no NN- prefix) is never globbed and a malformed `1-`/`100-` name is
# ignored rather than mis-banded; `N` is nullglob (no fragments → clean no-op).
# Sort EXPLICITLY with the `(o)` parameter flag — a lexical sort independent of the caller's
# NUMERIC_GLOB_SORT option — NOT the glob's own `n`/numeric sort. The fixed-width 2-digit NN
# still orders correctly lexically, and a same-NN tie breaks lexically by filename exactly as
# the contract promises (numeric sort would instead put `85-r10` AFTER `85-r2`, natural order).
_cl_frags=("$ZSH_CFG"/[0-9][0-9]-*.zsh(N))
for _cl_f in "${(@o)_cl_frags}"; do
  [[ -r "$_cl_f" ]] || continue
  _cl_nn=$(( 10#${${_cl_f:t}%%-*} ))                   # leading NN as base-10 (leading-zero safe)
  (( _cl_nn < 70 && _cl_nn > _cl_ceil )) && continue   # profile gate — Core band only
  # NO trailing name arg = script mode: writes "$_cl_f.zwc" (a function-name arg would
  # switch zcompile to digest mode, which `source` can't use as wordcode — keep it single-arg).
  [[ -s "$_cl_f.zwc" && ! "$_cl_f" -nt "$_cl_f.zwc" ]] || zcompile -R -- "$_cl_f" 2>/dev/null
  source "$_cl_f"
done
unset _cl_frags _cl_f _cl_nn _cl_ceil
