#!/usr/bin/env bash
# scripts/check-capabilities.sh
# ──────────────────────────────────────────────────────────────────────────────
# Validate an OS repo's `os.capabilities` declaration against Core's schema (#663).
#
# WHY THIS IS A SCRIPT AND NOT AN audit-core.sh SECTION. The file it validates does
# not live in this repo — it is authored per OS repo (os/<os>.capabilities, #667).
# A section buried inside Core's own gate could only ever check Core's example copy.
# As a standalone taking a PATH, the SAME validator runs from `make audit` here AND
# from each OS repo's `make lint` as `core/scripts/check-capabilities.sh os/<os>.capabilities`
# — nine repos gated by one definition of the schema instead of nine hand-written
# greps that drift. audit-core.sh calls it on examples/os.capabilities.example, so
# the shipped example is held to the same rules the fleet is.
#
# THE SCHEMA IS DECLARED HERE, ONCE. Core's reader (zsh/02-capabilities.zsh) is
# deliberately permissive — it skips anything it does not understand rather than
# breaking your login shell over a typo. That is only safe because strictness lives
# here: an unknown key, a missing required verb or a bad SCHEDULER is a FAILED GATE,
# not a mystery at 3am on a box you are SSH'd into.
#
# Usage:
#   ./scripts/check-capabilities.sh <file>
#   ./scripts/check-capabilities.sh <file> --packages install/packages.txt
#
# --packages turns on the cross-check that each PKG_* verb's leading binary is a
# package the repo actually installs. It is OPT-IN because Core has no packages.txt
# of its own; an OS repo passes its list and gets the check for free.
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# ── the schema ────────────────────────────────────────────────────────────────
# REQUIRED — every OS repo must declare all of these. They are the union of what
# `up` (#664), the maint scheduler (#665) and core-doctor (#666) dispatch through;
# an OS repo that cannot express one of them is a real portability finding, not a
# reason to relax the gate.
CAP_REQUIRED=(
  PKG_REFRESH        # bring the package index up to date (may be a no-op verb)
  PKG_UPGRADE        # upgrade everything installed — the dialect that is `dup` on Tumbleweed
  PKG_INSTALL        # install named packages, non-interactive
  PKG_REMOVE         # remove named packages, non-interactive
  PKG_SEARCH         # search the archive by name/description
  PKG_OWNS           # which package owns this path/binary
  PKG_COUNT_PENDING  # list pending upgrades — what `up`'s once-a-day nudge counts
  SCHEDULER          # systemd | launchd | none — 55-maint.zsh branches on this today
)
# OPTIONAL — absent means "Core's built-in default applies".
#   TOOLS_OPTIN  space-separated tools core-doctor reports as OPT-IN rather than MISSING.
#                Absent → Core's _CORE_DOCTOR_OPTIN fallback in zsh/30-functions.zsh.
CAP_OPTIONAL=(TOOLS_OPTIN)
# SCHEDULER's closed enum. `none` is a real answer (a container, a box with neither
# init), not a placeholder — it is what tells 55-maint.zsh to offer the manual verb
# instead of claiming a timer it cannot install.
CAP_SCHEDULERS=(systemd launchd none)

FILE="" PKGFILE="" RC=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --packages) PKGFILE="${2:-}"; shift 2 || true ;;
    -h|--help)  sed -n '2,30p' "$0"; exit 0 ;;
    -*)         printf 'check-capabilities: unknown option: %s\n' "$1" >&2; exit 2 ;;
    *)          FILE="$1"; shift ;;
  esac
done

if [[ -z "$FILE" ]]; then
  printf 'usage: check-capabilities.sh <os.capabilities> [--packages install/packages.txt]\n' >&2
  exit 2
fi
if [[ ! -r "$FILE" ]]; then
  printf 'FAIL %s: not readable\n' "$FILE" >&2
  exit 1
fi

bad() { printf 'FAIL %s:%s: %s\n' "$FILE" "$1" "$2" >&2; RC=1; }

# `in_list <needle> <haystack...>` — bash 3.2 has no associative arrays and this gate
# must run on macOS's stock shell, same constraint audit-core.sh works under.
in_list() { local n="$1"; shift; local i; for i in "$@"; do [[ "$i" == "$n" ]] && return 0; done; return 1; }

SEEN=""   # space-delimited "  KEY " tokens; the padding makes the substring test exact
VALUES="" # newline-delimited "KEY<TAB>value", re-read below for the cross-checks

# cap_value <key> — echo the declared value (empty when absent), status 1 when absent.
#
# NO PIPE, deliberately. `printf '%s' "$VALUES" | awk '$1==k {print; exit}'` is the exact
# shape audit-core.sh §5d gates against: under `set -o pipefail` the awk exits on its
# match, the printf takes EPIPE and dies 141, and the PIPELINE reports failure on the
# success path. This repo has hit that three times; a bash read loop has neither the
# hazard nor a fork.
cap_value() {
  local _k _v
  while IFS='	' read -r _k _v; do
    if [[ "$_k" == "$1" ]]; then printf '%s' "$_v"; return 0; fi
  done <<EOF
$VALUES
EOF
  return 1
}
LINENO_=0
while IFS= read -r line || [[ -n "$line" ]]; do
  LINENO_=$((LINENO_ + 1))
  # Comments and blank lines are the only non-assignment content allowed. A leading
  # `#` may be indented; anything else that is not KEY=value is a typo, and reporting
  # it is the whole reason this gate exists (the shell reader would skip it silently).
  case "$line" in
    ''|[[:space:]]*'#'*|'#'*) continue ;;
  esac
  [[ -z "${line//[[:space:]]/}" ]] && continue

  if [[ "$line" != *=* ]]; then
    bad "$LINENO_" "not a KEY=value assignment: $line"; continue
  fi
  key="${line%%=*}"
  val="${line#*=}"

  if [[ "$key" != [A-Z]* || "$key" == *[^A-Z0-9_]* ]]; then
    bad "$LINENO_" "key must match [A-Z][A-Z0-9_]*: $key"; continue
  fi
  if ! in_list "$key" "${CAP_REQUIRED[@]}" "${CAP_OPTIONAL[@]}"; then
    bad "$LINENO_" "unknown key: $key (schema: scripts/check-capabilities.sh)"; continue
  fi
  case "$SEEN" in *" $key "*) bad "$LINENO_" "duplicate key: $key (the reader keeps the LAST)";; esac
  SEEN="$SEEN $key "

  # Trailing whitespace is invisible and always an accident; the shell reader trims it,
  # so a value that only differs by it would behave one way and read another. Reject it
  # here rather than let the two disagree.
  if [[ "$val" == *[[:space:]] ]]; then
    bad "$LINENO_" "$key has trailing whitespace"
  fi
  VALUES="${VALUES}${key}	${val}
"
done < "$FILE"

# Required keys: present AND non-empty. "Declared empty" is how _core_cap spells
# "not declared", so an empty required verb is the same defect as a missing one.
for k in "${CAP_REQUIRED[@]}"; do
  case "$SEEN" in
    *" $k "*)
      v="$(cap_value "$k")"
      [[ -z "${v//[[:space:]]/}" ]] && bad "-" "required key is empty: $k"
      ;;
    *) bad "-" "required key missing: $k" ;;
  esac
done

# SCHEDULER's enum.
sched="$(cap_value SCHEDULER)"
if [[ -n "$sched" ]] && ! in_list "$sched" "${CAP_SCHEDULERS[@]}"; then
  bad "-" "SCHEDULER must be one of: ${CAP_SCHEDULERS[*]} (got: $sched)"
fi

# Cross-check: the binary each PKG_* verb actually runs should be one the repo installs.
# The leading token is skipped when it is `sudo`/`doas` — the privilege tool is not the
# package manager, and Alpine's is `doas`. Only the FIRST real token is checked; flags
# and subcommands are the OS repo's business.
if [[ -n "$PKGFILE" ]]; then
  if [[ ! -r "$PKGFILE" ]]; then
    printf 'FAIL %s: --packages file not readable\n' "$PKGFILE" >&2; RC=1
  else
    # Strip trailing comments (the `# only:kali` / `# min:X.Y.Z` annotations
    # dotfiles-Debian uses) and take the bare name. Padded with spaces on both sides so
    # the membership test below is a whole-token match, not a substring one — `dnf` must
    # not be satisfied by a package called `dnf-plugins-core`.
    PKGNAMES=" $(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$PKGFILE" | awk 'NF {print $1}' | tr '\n' ' ')"
    while IFS='	' read -r k v; do
      [[ "$k" == PKG_* && -n "$v" ]] || continue
      # The leading token, minus the privilege tool: `sudo`/`doas` is not the package
      # manager, and Alpine's is `doas`. Only the first REAL token is checked; flags and
      # subcommands are the OS repo's business.
      bin="${v%% *}"
      if [[ "$bin" == sudo || "$bin" == doas ]]; then
        v="${v#* }"
        bin="${v%% *}"
      fi
      [[ -n "$bin" ]] || continue
      # A package manager is very often not in its own package list (dnf on Fedora,
      # apt on Debian ship with the base system), so this is a WARNING, not a failure:
      # its job is catching a verb that names a tool nothing installs — `paru`, `brew`,
      # `nala` — not re-litigating what the base image ships.
      case "$PKGNAMES" in
        *" $bin "*) ;;
        # Double quotes, not backticks: shellcheck reads a backticked %s inside a
        # single-quoted format as a command substitution and files SC2016.
        *) printf 'warn %s: %s runs "%s", which is not in %s\n' "$FILE" "$k" "$bin" "$PKGFILE" >&2 ;;
      esac
    done <<EOF
$VALUES
EOF
  fi
fi

if [[ "$RC" -eq 0 ]]; then
  printf 'ok   %s (%s required keys, schema v5)\n' "$FILE" "${#CAP_REQUIRED[@]}"
fi
exit "$RC"
