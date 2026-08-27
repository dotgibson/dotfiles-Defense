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
  PKG_UPGRADE        # upgrade everything installed, INTERACTIVELY — the dialect that is
                     # `dup` on Tumbleweed. Auto-confirm is PKG_ASSUME_YES, not baked in
                     # here: `up` without -y must still let the manager show its own
                     # transaction summary and ask, which is what it has always done.
  PKG_INSTALL        # install named packages, non-interactive
  PKG_REMOVE         # remove named packages, non-interactive
  PKG_SEARCH         # search the archive by name/description
  PKG_OWNS           # which package owns this path/binary
  PKG_COUNT_PENDING  # list pending upgrades — what `up`'s once-a-day nudge counts
  SCHEDULER          # systemd | launchd | none — 55-maint.zsh branches on this today
)
# OPTIONAL — absent means "Core's built-in default applies".
#
# EVERY key added for #664 is optional ON PURPOSE. The eight required verbs are what an
# archive cannot work without; these express the ways archives DIFFER, and an archive that
# needs none of them declares none. That keeps #667's job — authoring nine of these by
# hand — as small as it can be, and it means a declaration written against the v5 schema
# keeps validating.
#
#   TOOLS_OPTIN          space-separated tools core-doctor reports as OPT-IN rather than
#                        MISSING. Absent → Core's _CORE_DOCTOR_OPTIN fallback in
#                        zsh/30-functions.zsh.
#
#   ── how `up` applies (#664) ────────────────────────────────────────────────────────
#   PKG_ASSUME_YES       the flag `up -y` appends to PKG_UPGRADE (and to PKG_CLEANUP).
#                        ABSENT MEANS NEVER AUTO-CONFIRM: `up -y` then behaves like `up`
#                        and the manager asks for itself. That is the right answer for
#                        Arch (partial-upgrade breakage), Gentoo (`-a` always asks anyway)
#                        and Alpine — omit it rather than inventing a flag.
#   PKG_UPGRADE_PRE      a command run immediately BEFORE PKG_UPGRADE, on both the full
#                        and the partial path. FAILURE ABORTS THE UPGRADE — an upgrade
#                        computed against an index that could not be refreshed is how a
#                        box half-applies. Omit where the manager refreshes in one verb
#                        (`dnf --refresh`, `pacman -Syu`).
#   PKG_CLEANUP          a command run after a SUCCESSFUL full upgrade (never after a
#                        partial one, which removes nothing). `apt-get autoremove`,
#                        `brew cleanup`.
#   PKG_UPGRADE_PARTIAL  upgrade only the named packages. ITS ABSENCE IS A SAFETY
#                        DECLARATION: `up -i` refuses on an archive that declares none,
#                        which is how Arch, Gentoo and Alpine say "this must update as a
#                        whole". Do not declare one to be helpful.
#
#   ── how `up` counts (#664) ─────────────────────────────────────────────────────────
#   Core runs PKG_COUNT_PENDING and reads ONE package name per matching line out of its
#   output. These three say how, and are passed to awk as data — never eval'd:
#   PKG_COUNT_REFRESH    a command run before PKG_COUNT_PENDING in the COUNT path only
#                        (not the list path). Homebrew needs it; nothing else does.
#   PKG_COUNT_EXIT_TRUSTED
#                        set to 1 when a NON-ZERO exit from PKG_COUNT_PENDING means "could
#                        not answer", so the count reports the -1 unknown sentinel instead
#                        of 0. OFF BY DEFAULT because most archives overload that status:
#                        `dnf check-update` exits 100 when updates EXIST, and `pacman -Qu`
#                        and `checkupdates` exit non-zero when there are NONE. Gentoo
#                        declares it — an `emerge --pretend` that cannot resolve is common,
#                        and reporting 0 there says "up to date" while Portage is stuck.
#   PKG_PENDING_MATCH    ERE selecting the lines that name a package. Default `.`.
#   PKG_PENDING_FIELD    which field of a matching line holds the name. Default 1.
#   PKG_PENDING_FS       awk field separator. Default whitespace. zypper's table is `|`.
CAP_OPTIONAL=(
  TOOLS_OPTIN
  PKG_ASSUME_YES PKG_UPGRADE_PRE PKG_CLEANUP PKG_UPGRADE_PARTIAL
  PKG_COUNT_REFRESH PKG_COUNT_EXIT_TRUSTED
  PKG_PENDING_MATCH PKG_PENDING_FIELD PKG_PENDING_FS
)
# The PKG_* keys whose value is a COMMAND. --packages cross-checks the leading binary of
# each of these against the repo's package list; the PKG_PENDING_* keys are awk data
# (`^Inst `, `3`, `|`) and checking their first token as if it were a binary would report
# nonsense. Kept as an explicit list rather than a `PKG_*` glob for exactly that reason.
CAP_COMMANDS=(
  PKG_REFRESH PKG_UPGRADE PKG_INSTALL PKG_REMOVE PKG_SEARCH PKG_OWNS PKG_COUNT_PENDING
  PKG_UPGRADE_PRE PKG_CLEANUP PKG_UPGRADE_PARTIAL PKG_COUNT_REFRESH
)
# SCHEDULER's closed enum. `none` is a real answer (a container, a box with neither
# init), not a placeholder — it is what tells 55-maint.zsh to offer the manual verb
# instead of claiming a timer it cannot install.
CAP_SCHEDULERS=(systemd launchd none)

FILE="" PKGFILE="" RC=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    # `shift 2` with fewer than 2 positionals returns non-zero AND LEAVES THEM UNCHANGED
    # (POSIX; bash follows). The old `shift 2 || true` swallowed the status but not the
    # non-shift, so a dangling `--packages` left $1 as `--packages` and the loop never
    # terminated. This is called from nine OS repos' `make lint`, where an infinite loop
    # is a job that burns to the runner timeout instead of failing in a readable way.
    --packages)
      [[ $# -ge 2 ]] || { printf 'check-capabilities: --packages needs a path\n' >&2; exit 2; }
      PKGFILE="$2"; shift 2 ;;
    -h|--help)  sed -n '2,28p' "$0"; exit 0 ;;
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
  # `[[:space:]]*'#'*` looks like "optional indent, then #" and is not: in a glob,
  # `[[:space:]]` is ONE character and `*` is "anything", so it also matched an INDENTED
  # ASSIGNMENT CONTAINING A '#' — skipped in silence, then reported as `required key
  # missing` with the line sitting right there in the file. Strip the indent first and
  # anchor on the '#', so "optionally indented comment" means exactly that.
  case "${line#"${line%%[![:space:]]*}"}" in
    ''|'#'*) continue ;;
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
  # THIS FILE IS NOT AN ENV FILE, however much it looks like one — its own header is dense
  # with `#` comments, so `PKG_OWNS=dnf provides   # which package owns this` is the natural
  # thing to author and every other rule here waves it through: the comment arm only matches
  # a line that STARTS with `#`, the trailing-whitespace rule sees a final `s`, and
  # --packages only inspects the first token. Core's reader stores the whole string, so the
  # declared verb silently becomes `dnf provides # which package owns this`. Say so here
  # rather than let a shell run it.
  if [[ "$val" == *' #'* ]]; then
    bad "$LINENO_" "$key: '#' does not start a comment inside a value (the reader keeps it)"
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

# PKG_COUNT_EXIT_TRUSTED is a FLAG, and the only honest value is 1. Anything else would
# be read as "declared", so a `PKG_COUNT_EXIT_TRUSTED=0` meaning to switch it OFF would
# switch it firmly ON — the worst possible direction for a typo in a key whose whole job
# is deciding whether a broken resolve reads as "nothing to do".
trust="$(cap_value PKG_COUNT_EXIT_TRUSTED)"
case "$trust" in
  '' | 1) ;;
  *) bad "-" "PKG_COUNT_EXIT_TRUSTED must be 1 if declared; omit it to mean off (got: $trust)" ;;
esac

# PKG_PENDING_FIELD indexes an awk field, so it must be a positive integer. A typo here
# does not fail at runtime — awk reads a different column and `up` reports confident
# nonsense — which is precisely the failure mode a gate is for.
fld="$(cap_value PKG_PENDING_FIELD)"
case "$fld" in
  '') ;;
  *[!0-9]* | 0) bad "-" "PKG_PENDING_FIELD must be a positive integer (got: $fld)" ;;
esac

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
      [[ -n "$v" ]] || continue
      in_list "$k" "${CAP_COMMANDS[@]}" || continue
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
