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
# — the whole fleet gated by one definition of the schema instead of per-repo greps that
# drift. Seven repos declare; dotfiles-Offense and dotfiles-Defense are Role repos with no
# OS band of their own, so they declare nothing and inherit the OS layer's table (#667). audit-core.sh calls it on examples/os.capabilities.example, so
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
  SCHEDULER          # systemd | launchd | cron | none — see CAP_SCHEDULERS below, which
                     # is the authority; 55-maint.zsh branches on this
)
# OPTIONAL — and since #763 "absent" means the KEY'S OWN ABSENCE IS THE STATEMENT, not that
# Core substitutes a row of its own. Core carried per-manager and per-scheduler defaults
# behind these until then; they are deleted, so no PKG_ASSUME_YES means never auto-confirm,
# no PKG_UPGRADE_PARTIAL means `up -i` refuses, no SCHEDULER_UNIT_DIR means maint-install and
# maint-uninstall refuse on systemd/launchd, and no MAINT_UNATTENDED_UPGRADE means the
# scheduled runner will not apply. TOOLS_OPTIN is the ONE exception and says so at its entry:
# it is the only key that still falls back to a Core-side default, because omitting it means
# "I have not curated a list", not "nothing here is optional".
#
# EVERY key added for #664 is optional ON PURPOSE. The eight required verbs are what an
# archive cannot work without; these express the ways archives DIFFER, and an archive that
# needs none of them declares none. That kept #667's job — authoring these by hand across
# the fleet — as small as it could be, and it means a declaration written against the v5
# schema keeps validating.
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
#
#   ── what --packages must not nag about (#1087) ─────────────────────────────────────
#   PKG_UNLISTED_TOOLS   space-separated BINARY names that this declaration's verbs run and
#                        install/packages.txt deliberately does not name. Only --packages
#                        reads it, and only to stay quiet about them.
#
#                        WHY A DECLARATION AND NOT A LIST IN CORE. Three different reasons
#                        a verb's binary is absent from a repo's package list, and only the
#                        repo knows which applies: the BASE SYSTEM ships it (`apt-get`,
#                        `dnf`, `zypper`, `rpm`, `systemctl`), a package the repo DOES list
#                        provides it under another name (`checkupdates` from
#                        `pacman-contrib`, `equery` from `gentoolkit`), or the REPO SHIPS IT
#                        ITSELF (`gentoo-pkg-pending`, symlinked into ~/.local/bin by that
#                        repo's bootstrap). Core cannot tell those apart, and a hardcoded
#                        table of package-manager binaries here would be exactly the
#                        per-manager knowledge #763 deleted from Core. So the repo says so.
#
#                        MEASURED 2026-09-16, before this key existed: the cross-check fired
#                        on essentially every PKG_* verb the fleet declares — Debian 10,
#                        openSUSE and Fedora and Alpine and Gentoo 8 each, Arch 7 — because
#                        every one of those binaries falls into a category above. A gate
#                        that is ~100% false-positive teaches people to skim past it, which
#                        costs more than the case it was built to catch (a verb naming a
#                        tool nothing installs: `paru`, `nala`). Declaring the exceptions
#                        makes the remaining warnings mean something again.
#
#                        KEPT HONEST FROM BOTH ENDS. A name here that no declared verb
#                        actually runs is a FAILURE, not a warning — a stale entry silences
#                        a future verb nobody vetted. And with --packages, a name here that
#                        IS in packages.txt is a FAILURE too: the repo installs it, so the
#                        declaration contradicts itself. Omitting the key entirely keeps the
#                        old behaviour, so every existing declaration validates unchanged.
#
#   ── the scheduled runner (#665) ────────────────────────────────────────────────────
#   SCHEDULER_UNIT_DIR   the DIRECTORY this box's scheduler reads units from. REQUIRED when
#                        SCHEDULER is systemd or launchd (checked below), meaningless for
#                        cron (which has no file of its own) and none.
#
#                        A DIRECTORY, not a full path, and the distinction is load-bearing:
#                        WHERE units live is an OS fact and belongs here, but what Core
#                        calls its own job is Core's identity — `dotfiles-maint.service`,
#                        `com.dotfiles.maint`. Those names appear in `systemctl enable`,
#                        `launchctl` and the status verbs, so letting a declaration rename
#                        the file would silently decouple the unit Core WRITES from the one
#                        it then enables and reports on. This is the key that
#                        gets the last OS-ABSOLUTE PATH out of Core: `~/Library/LaunchAgents`
#                        appeared at six sites in zsh/55-maint.zsh and was the reason
#                        audit-core.sh §5c carried a per-file exception for it. An OS-absolute
#                        path is CORRECT in an OS repo's declaration and wrong in Core, which
#                        is the whole layering rule stated in one key.
#   MAINT_UNATTENDED_UPGRADE
#                        set to 1 to permit the scheduled runner to apply SYSTEM package
#                        upgrades on this box. ABSENT MEANS REFUSE, and that direction is
#                        load-bearing: a fail-open here silently enables unattended full
#                        upgrades on an engagement box. It is the SECOND of two gates — the
#                        operator's MAINT_SYSTEM_UPGRADE=1 env var is the first, and both
#                        must be true. Kali does not declare it (engagement boxes are
#                        updated by hand between ops); Arch and Gentoo do not either
#                        (a rolling distro that half-upgrades unattended is a broken box).
CAP_OPTIONAL=(
  TOOLS_OPTIN
  PKG_ASSUME_YES PKG_UPGRADE_PRE PKG_CLEANUP PKG_UPGRADE_PARTIAL
  PKG_COUNT_REFRESH PKG_COUNT_EXIT_TRUSTED
  PKG_PENDING_MATCH PKG_PENDING_FIELD PKG_PENDING_FS
  SCHEDULER_UNIT_DIR MAINT_UNATTENDED_UPGRADE
  PROVISIONER PKG_APPLY
  PKG_APPLY_PENDING PKG_APPLY_PENDING_EXIT
  PKG_UNLISTED_TOOLS
)
#   ── the non-mutable host (SHIPPED — NON-MUTABLE-HOST-PROPOSAL.md §4, #1004) ────────
#   Four OPTIONAL keys, and ALL FOUR ARE READ (#1049, Core v7.6.0): PROVISIONER,
#   PKG_APPLY, PKG_APPLY_PENDING and PKG_APPLY_PENDING_EXIT, by `up` and the shell-start
#   nudge, the maint runner and core-doctor. They were born as R2's prototype — its test
#   was whether a required key ends up a lie on an atomic, transactional or declarative
#   host, and the answer needed somewhere to put the truth — and they are now the schema
#   three fleet repos declare against: dotfiles-Fedora's fedora.atomic, dotfiles-openSUSE's
#   opensuse.microos and dotfiles-NixOS's nixos. Every existing declaration keeps
#   validating unchanged; that was the point, and the measured verdict (R2) was that the
#   schema is ADDITIVE, so no repo re-authored.
#
#   R2 PROTOTYPED SIX; TWO WERE RETIRED UNREAD (#1128). PKG_PENDING_EXIT_NONE and
#   PKG_PENDING_EXIT_SOME described a count verb whose answer is its EXIT STATUS rather
#   than its lines. The consumer that would have read them was never written,
#   PKG_APPLY_PENDING_EXIT covers the staged question that did ship, and no repo in the
#   fleet had ever declared either — which is the only reason dropping them from a
#   VENDORED validator was a minor and not a break. They are unknown keys now, and
#   refused as such. DO NOT ADD A NAME HERE WITHOUT ITS CONSUMER: an accepted key is a key
#   an OS repo may author, and an accepted key nobody reads is a declaration the box
#   silently ignores.
#   PROVISIONER          mutable (the default when absent) | atomic (image-based: bootc,
#                        Silverblue) | transactional (snapshot-based: MicroOS, Aeon) |
#                        declarative (NixOS). What a consumer branches on (#1049): `up`
#                        printing "staged — reboot to apply: <PKG_APPLY>" after an atomic
#                        or transactional upgrade, the maint runner staging only,
#                        core-doctor phrasing an install hint the host's way, `_pkgup_mgr`
#                        answering this token when no manager is on PATH.
#   PKG_APPLY            the verb that makes a STAGED change live — a reboot on atomic and
#                        transactional hosts (`sudo systemctl reboot`), absent where
#                        PKG_UPGRADE already activates (mutable, `nixos-rebuild switch`).
#                        Measured 2026-09-14: `rpm-ostree install` and
#                        `transactional-update pkg in` both return with the change staged
#                        and nothing on PATH until the reboot.
#   PKG_APPLY_PENDING / PKG_APPLY_PENDING_EXIT   (R5, measured 2026-09-14)
#                        a STAGED host asks a second question the count verb never did:
#                        is a change already waiting for PKG_APPLY? This verb answers with
#                        its exit status — `rpm-ostree status --pending-exit-77` (user-
#                        runnable, 0.2 s; EXIT=77), `test -e /run/reboot-needed` on MicroOS
#                        (EXIT absent = 0). It needs PKG_APPLY beside it (nothing to apply
#                        otherwise), is asked by the once-a-day refresh and the maint
#                        runner (#1049: cached with the boot id, so the per-shell path
#                        stays fork-free), and the nudge prints "update staged — reboot
#                        to apply" from it instead of a count. Declaring it UNDER
#                        PROVISIONER=atomic is the second way PKG_COUNT_PENDING may be
#                        absent: on an atomic host the AVAILABLE verb is root-only
#                        (`rpm-ostree upgrade --check` → "AutomaticUpdateTrigger not
#                        allowed for user", measured), so the runner's unattended staging
#                        does the asking and the user-side nudge reports the staged state.
#                        The provisioner is part of that rule, not context for it (#1057):
#                        the refusal is what makes the absence honest, and it was measured
#                        on rpm-ostree. A transactional or mutable host that declares this
#                        verb still owes its count verb — MicroOS answers
#                        `zypper -q list-updates` as the user and declares it.
#   PROVISIONER=declarative RELAXES ONE REQUIRED KEY: PKG_COUNT_PENDING may be absent. A
#   declarative host has no truthful unprivileged "packages pending" verb (the answer is
#   "what a rebuild would change", which needs root's channel), and `up` already reads an
#   absent count verb as the -1 sentinel that keeps the nudge silent. Every other required
#   key filled honestly on all three prototypes (nix-env -i / -e are the imperative
#   install and remove a NixOS box does have), so nothing else relaxes. PKG_APPLY_PENDING
#   (above) is the other relaxation, and it is PROVISIONER=atomic ONLY, for the reason
#   measured there. Both arms are gated on PROVISIONER; see the loop that applies them.
CAP_PROVISIONERS=(mutable atomic transactional declarative)
# The PKG_* keys whose value is a COMMAND. --packages cross-checks the leading binary of
# each of these against the repo's package list; the PKG_PENDING_* keys are awk data
# (`^Inst `, `3`, `|`) and checking their first token as if it were a binary would report
# nonsense. Kept as an explicit list rather than a `PKG_*` glob for exactly that reason.
CAP_COMMANDS=(
  PKG_REFRESH PKG_UPGRADE PKG_INSTALL PKG_REMOVE PKG_SEARCH PKG_OWNS PKG_COUNT_PENDING
  PKG_UPGRADE_PRE PKG_CLEANUP PKG_UPGRADE_PARTIAL PKG_COUNT_REFRESH PKG_APPLY PKG_APPLY_PENDING
)
# SCHEDULER's closed enum. `none` is a real answer (a container, a box with neither
# init), not a placeholder — it is what tells 55-maint.zsh to offer the manual verb
# instead of claiming a timer it cannot install.
#
# `cron` was MISSING until #665, and its absence was a defect in this list rather than a
# judgement about cron. zsh/55-maint.zsh has had a live cron arm all along — it is what an
# OpenRC box (Alpine, Gentoo) gets, having `crontab` and no systemd — so the schema was
# rejecting a value Core itself produces. Alpine's only honest declaration was `none`,
# which means "offer the manual verb, this box cannot hold a timer", on a box that can.
CAP_SCHEDULERS=(systemd launchd cron none)

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
prov="$(cap_value PROVISIONER)"
if [[ -n "$prov" ]] && ! in_list "$prov" "${CAP_PROVISIONERS[@]}"; then
  bad "-" "PROVISIONER must be one of: ${CAP_PROVISIONERS[*]} (got: $prov)"
fi
for k in "${CAP_REQUIRED[@]}"; do
  # The relaxations the prototype schema makes (see CAP_OPTIONAL's note): a declarative
  # host may leave the count verb out, because it has no truthful one; so may an ATOMIC
  # host that declares PKG_APPLY_PENDING, because its AVAILABLE verb is root-only and its
  # nudge reports the staged state instead.
  #
  # BOTH ARMS ARE GATED ON PROVISIONER, and the second one was not until #1057. Ungated,
  # any repo could drop a required verb by declaring a staged-change probe beside it —
  # PKG_APPLY=sudo systemctl reboot with PKG_APPLY_PENDING=test -e /var/run/reboot-required
  # is entirely truthful on Debian and Ubuntu, and would have bought a mutable host an
  # exemption it does not need. `up` then reads the absent count verb as the -1 sentinel
  # and goes permanently silent about available updates, with this gate asserting the
  # declaration is complete. ATOMIC ONLY, because that is what was measured: the root-only
  # refusal is rpm-ostree's ("AutomaticUpdateTrigger not allowed for user"). The fleet's
  # one transactional host answers `zypper -q list-updates` unprivileged and declares it,
  # so it never needed this; a transactional host that genuinely cannot answer can widen
  # the arm, with the measurement behind it. See also gen-porting-matrix.sh, which renders
  # a cell only where THIS rule accepts the absence — one rule, two readers.
  [[ "$k" == PKG_COUNT_PENDING && "$prov" == declarative ]] && continue
  [[ "$k" == PKG_COUNT_PENDING && "$prov" == atomic && -n "$(cap_value PKG_APPLY_PENDING)" ]] && continue
  case "$SEEN" in
    *" $k "*)
      v="$(cap_value "$k")"
      [[ -z "${v//[[:space:]]/}" ]] && bad "-" "required key is empty: $k"
      ;;
    *) bad "-" "required key missing: $k" ;;
  esac
done
# PKG_APPLY_PENDING (R5): a staged-change probe only means something beside PKG_APPLY, and
# its optional _EXIT is one status in 1-255 (absent = "exit 0 means staged").
ap_pend="$(cap_value PKG_APPLY_PENDING)"
ap_exit="$(cap_value PKG_APPLY_PENDING_EXIT)"
if [[ -n "$ap_pend" && -z "$(cap_value PKG_APPLY)" ]]; then
  bad "-" "PKG_APPLY_PENDING says a change is waiting for PKG_APPLY, which is not declared"
fi
if [[ -n "$ap_exit" ]]; then
  [[ -n "$ap_pend" ]] || bad "-" "PKG_APPLY_PENDING_EXIT describes PKG_APPLY_PENDING's exit status, which is not declared"
  # A LEADING ZERO IS REJECTED, NOT NORMALISED (#1057). `(( ))` re-expands a named variable
  # as an arithmetic expression, where an all-digit string starting with 0 is OCTAL: 077 was
  # silently accepted AS 63 — a declaration whose author wrote one status and got another —
  # and 099 was an invalid-octal-digit ERROR that `(( ))` reported by returning false, which
  # this script (no `set -e`) discarded. The `| 0` arm below only ever caught the literal 0,
  # so 00 and 000 walked through the "omit it to mean zero" rule too. An exit status is
  # written 77, never 077, so the whole class is refused rather than decoded; 10# on the
  # survivor keeps the comparison decimal no matter what a later edit lets past. This was
  # one of TWO copies of the check until #1128 retired PKG_PENDING_EXIT_NONE / _SOME; it is
  # the only one now, so a second copy is something to fold into it, not to write beside it.
  case "$ap_exit" in
    *[!0-9]* | 0 | 0?*) bad "-" "PKG_APPLY_PENDING_EXIT must be an exit status 1-255, with no leading zero (got: $ap_exit)" ;;
    *) ((10#$ap_exit > 255)) && bad "-" "PKG_APPLY_PENDING_EXIT must be an exit status 1-255, with no leading zero (got: $ap_exit)" ;;
  esac
fi

# PKG_UNLISTED_TOOLS (#1087): every name must be one a declared verb actually runs.
# STALENESS IS A FAILURE, not a warning. The key's whole job is to silence a warning, so an
# entry nobody checks against is a silencer waiting for a verb that was never vetted — a
# repo that drops `checkupdates` for something else keeps the exemption and hears nothing
# about the replacement. Computed from the same leading-token rule the cross-check uses, so
# the two cannot disagree about what a verb "runs"; that rule lives in verb_bin.
verb_bin() { # <verb value> → the binary it runs, minus the privilege tool
  local _v="$1" _b="${1%% *}"
  if [[ "$_b" == sudo || "$_b" == doas ]]; then _v="${_v#* }"; _b="${_v%% *}"; fi
  printf '%s' "$_b"
}
unlisted="$(cap_value PKG_UNLISTED_TOOLS)"
if [[ -n "$unlisted" ]]; then
  RUNBINS=" "
  while IFS='	' read -r k v; do
    [[ -n "$v" ]] || continue
    in_list "$k" "${CAP_COMMANDS[@]}" || continue
    RUNBINS="$RUNBINS$(verb_bin "$v") "
  done <<EOF
$VALUES
EOF
  for t in $unlisted; do
    case "$RUNBINS" in
      *" $t "*) ;;
      *) bad "-" "PKG_UNLISTED_TOOLS names \"$t\", which no declared verb runs — drop it (a stale exemption silences a verb nobody vetted)" ;;
    esac
  done
fi

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

# SCHEDULER_UNIT_PATH is CONDITIONALLY required: systemd and launchd each keep the unit in
# a file whose location only this OS knows, and Core no longer carries a default for it.
# cron has no file of its own (the entry lives in the user's crontab) and `none` installs
# nothing, so requiring it there would be asking for a value with nothing to say.
unitp="$(cap_value SCHEDULER_UNIT_DIR)"
case "$sched" in
systemd | launchd)
  [[ -z "${unitp//[[:space:]]/}" ]] &&
    bad "-" "SCHEDULER=$sched requires SCHEDULER_UNIT_DIR (the directory units live in)"
  ;;
cron | none)
  [[ -n "$unitp" ]] &&
    bad "-" "SCHEDULER=$sched takes no SCHEDULER_UNIT_DIR (cron has no unit file)"
  ;;
esac
# A DIRECTORY, so a value ending in .service/.plist is someone declaring the full path —
# the exact confusion the dir-vs-path split exists to prevent. Core appends its own
# filename, so a path here would produce `…/dotfiles-maint.service/dotfiles-maint.service`.
case "$unitp" in
*.service | *.plist | *.timer)
  bad "-" "SCHEDULER_UNIT_DIR is a DIRECTORY; Core appends its own unit name (got: $unitp)"
  ;;
esac

# MAINT_UNATTENDED_UPGRADE is a FLAG whose only honest value is 1, for the same reason
# PKG_COUNT_EXIT_TRUSTED is: `=0` reads as DECLARED, so writing it to mean "do not apply
# upgrades unattended" would permit exactly what it was meant to forbid. Omission is how a
# repo refuses, and refusing is the default.
unatt="$(cap_value MAINT_UNATTENDED_UPGRADE)"
case "$unatt" in
'' | 1) ;;
*) bad "-" "MAINT_UNATTENDED_UPGRADE must be 1 if declared; omit it to refuse (got: $unatt)" ;;
esac

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
    # Padded at both ends for the same whole-token reason as PKGNAMES: an exemption for
    # `rpm` must not also cover `rpm-ostree`. $unlisted is already whitespace-separated by
    # the schema, so word-splitting it and re-joining normalises any run of spaces.
    UNLISTED=" $(printf '%s' "$unlisted" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//') "
    # A declared exemption that the repo DOES install is a contradiction, and a failure:
    # the exemption is false and the next reader would believe it. Reported ONCE PER TOOL
    # and not inside the per-verb loop below — `dnf` leads eight of Fedora's verbs, so the
    # per-verb form printed the same line eight times, which is the noise this key exists
    # to remove.
    for t in $unlisted; do
      case "$PKGNAMES" in
        *" $t "*) bad "-" "PKG_UNLISTED_TOOLS names \"$t\", but $PKGFILE installs it — remove the exemption" ;;
      esac
    done
    while IFS='	' read -r k v; do
      [[ -n "$v" ]] || continue
      in_list "$k" "${CAP_COMMANDS[@]}" || continue
      # The leading token, minus the privilege tool: `sudo`/`doas` is not the package
      # manager, and Alpine's is `doas`. Only the first REAL token is checked; flags and
      # subcommands are the OS repo's business. verb_bin is that rule, defined once above
      # so the staleness check on PKG_UNLISTED_TOOLS cannot disagree with this one.
      bin="$(verb_bin "$v")"
      [[ -n "$bin" ]] || continue
      # A SHELL BUILTIN IS NOT A PACKAGE ON ANY HOST (#1057). MicroOS answers the staged
      # question with `test -e /run/reboot-needed`, whose leading token is `test` — no
      # distro packages that, so no edit to any packages.txt could ever silence the
      # warning. This is the ONE narrowing the cross-check can make portably: the checker
      # runs on a CI Ubuntu box against Fedora, Arch and Alpine declarations, so asking
      # whether `zypper` exists HERE would answer a question about the wrong machine,
      # while `test` is a builtin everywhere and the answer travels.
      # Read into a variable first so the `case` subject is a plain expansion, keeping
      # this clear of the `case`-inside-a-substitution shape audit §5k gates (#1077).
      bin_kind="$(type -t "$bin" 2>/dev/null || true)"
      case "$bin_kind" in builtin | keyword) continue ;; esac
      # DECLARED AS DELIBERATELY UNLISTED (#1087) — the base system ships it, a listed
      # package provides it under another name, or this repo ships it itself. The repo is
      # the only one that knows which, so it says so and this stays quiet. A name declared
      # here that IS in the package list is a contradiction, and a failure: the repo
      # installs it, so the exemption is false and the next reader would believe it.
      case "$UNLISTED" in *" $bin "*) continue ;; esac
      # A package manager is very often not in its own package list (dnf on Fedora,
      # apt on Debian ship with the base system), so this is a WARNING, not a failure:
      # its job is catching a verb that names a tool nothing installs — `paru`, `brew`,
      # `nala`. Before #1087 that was the whole rule, and it fired on essentially every
      # verb the fleet declares (Debian 10, most repos 7-8) because the base-system case
      # was indistinguishable from the real one. PKG_UNLISTED_TOOLS is how a repo tells
      # them apart; what is left here is a binary the declaration runs, the repo does not
      # install, and nobody has vouched for.
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
