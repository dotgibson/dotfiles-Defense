#!/usr/bin/env bash
# dotfiles-Defense/bootstrap.sh
# Wire the defensive (blue) role layer onto an already-provisioned box.
# Distro-agnostic: does NOT install OS packages (your OS-native layer does that).
# Idempotent. Stacks: vendored Core + your OS-native layer + DEFENSE role.
#
# THE DRIVER FORM (dotgibson/dotfiles-core#976; this repo is the fleet's pilot). The shared
# half of a bootstrap — the flags, the escalator, the Core symlink surface, the band-85 role
# stage, the managed ~/.zshrc loader, the closing report — is core/lib/bootstrap-lib.sh ::
# blib_main, ONE definition instead of nine hand-rolled copies. This file declares what the
# repo is, defines the hooks that are genuinely Defense's (the forensics host-tool probe and
# the closing case-data / login-shell notes), and hands over. `--help` prints both halves.
#
#   ./bootstrap.sh                 # symlinks + loader + tool/docker checks
#   ./bootstrap.sh --no-check      # skip the host-tool / docker probe
#   ./bootstrap.sh --links-only    # just (re)create symlinks
#   ./bootstrap.sh --dry-run       # print the full plan, change nothing
#   ./bootstrap.sh --only zsh,git  # wire only these groups (also --only=zsh,git)
#   ./bootstrap.sh --strict        # exit 1 if a step the shared scaffold ran did not complete
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
DO_CHECK=1

# ── core/ subtree present? ────────────────────────────────────────────────────
# CHICKEN-AND-EGG: this one guard cannot move into the lib — you cannot source a file
# out of core/ before confirming core/ exists (see bootstrap-lib.sh's header). So it
# stays inline, ahead of the two `source` lines below — and it checks the paths those
# lines actually READ, not just core/zsh as a proxy. A half-vendored subtree (core/zsh
# present, core/lib absent) would otherwise die on bash's own `source: No such file`
# under set -e, losing the one message that says how to fix it.
for req in core/zsh core/lib/ux.sh core/lib/bootstrap-lib.sh; do
  if [[ ! -e "$DOTFILES/$req" ]]; then
    echo "vendored core/ missing or incomplete (no $req). A clone always has core/;" >&2
    echo "if building fresh, take a RELEASED TAG (never main, or core-integrity reports" >&2
    echo "the fresh tree as TAMPERED), then let the fan-out stamp core.lock:" >&2
    echo "  git subtree add --prefix=core <dotfiles-core remote> refs/tags/v7 --squash" >&2
    echo "  make sync          # in dotfiles-core" >&2
    exit 1
  fi
done

# ux.sh first — it sets the UX_* palette the blib_* message helpers read; sourced the
# other way round they still work, just uncoloured.
# shellcheck source=core/lib/ux.sh
source "$DOTFILES/core/lib/ux.sh"
# shellcheck source=core/lib/bootstrap-lib.sh
source "$DOTFILES/core/lib/bootstrap-lib.sh"

# ── what this repo is (read by blib_main) ─────────────────────────────────────
BOOTSTRAP_NAME="Defense"
# The band-85 role stage and defense/templates, via blib_link_role_layer — the helper
# Offense already used while this file hand-rolled the same links (the fork the lib's own
# comment named). No BOOTSTRAP_OS: the 80 band belongs to your OS-native repo, not this one.
BOOTSTRAP_ROLE=defense
# Report-only, deliberately: blib_set_login_shell is correct, but it sudo's (chsh, and an
# append to /etc/shells), and this bootstrap's contract is "does NOT install OS packages",
# line 4 — so the closing hook names the remedy (blib_login_shell_hint) and lets the
# operator run it. With no provisioning hook either, the driver resolves no escalator.
BOOTSTRAP_LOGIN_SHELL=0

# ── hooks (called by blib_main, in its order; shellcheck cannot see that) ─────
# shellcheck disable=SC2329
bootstrap_usage() {
  cat <<'USAGE'
bootstrap.sh — wire the defensive (blue) role layer onto an already-provisioned box.
Distro-agnostic: installs no OS packages (your OS-native layer does that). Idempotent.

  --no-check      skip the host-tool / docker probe (the shared flags follow)
USAGE
}
# shellcheck disable=SC2329
bootstrap_flag() {
  case "$1" in
  --no-check)
    DO_CHECK=0
    return 0
    ;;
  esac
  return 1
}

# ── Host-tool / docker probe (report only — never installs) ──────────────────
# `command -v` answers "is this on $PATH", which is NOT the question "is this tool on
# the box". Several of the tools below are routinely installed somewhere $PATH never
# sees, and calling those "missing" sends you to reinstall something you already have:
#
#   • zeek   — installs under its own prefix, /opt/zeek/bin, which upstream does not
#              add to $PATH (the tarball and the official packages both do this)
#   • vol    — volatility3 is commonly run out of a checkout's venv, or shipped under
#              its script name vol.py rather than vol
#
# The opposite error would be just as wrong: defense.zsh invokes these by bare name
# (`zeek -r …`, `vol -f …`), so a tool that is present but off $PATH is still unusable
# by this layer. So report three states, not two — on PATH, present-but-unreachable
# (with the one-line fix), and genuinely absent — and count only the last as missing.
#
# _probe_offpath <tool> — echo an executable path for <tool> found OFF $PATH, else fail.
# Deliberately a short, general list: tool-owned prefixes, unpacked release trees and snap.
# It does not go hunting through $HOME — a probe that guesses at arbitrary checkout
# locations would be slow and would still miss.
_probe_offpath() {
  local t="$1" p
  for p in "/opt/$t/bin/$t" "/usr/local/$t/bin/$t" "$HOME/.local/share/$t/$t" "/snap/bin/$t"; do
    [ -x "$p" ] && {
      printf '%s\n' "$p"
      return 0
    }
  done
  return 1
}

# _probe_altname <tool> — echo an alternate command name for <tool> that IS on $PATH.
# Same idea as Core's fd->fdfind / bat->batcat resolution: one capability, several names
# depending on how it was packaged.
_probe_altname() {
  local t="$1" a
  case "$t" in
  vol) set -- vol.py volatility3 ;;
  *) return 1 ;;
  esac
  for a in "$@"; do
    command -v "$a" >/dev/null 2>&1 && {
      printf '%s\n' "$a"
      return 0
    }
  done
  return 1
}

# _probe_list — the tools to probe, read from install/tools.lst (column 1, comments and
# blanks stripped). Single source: the list used to be a literal here AND prose in
# install/README.md, with nothing keeping the two in step. Now the file is the list, the
# README points at it, and tests/test-defense.sh asserts this parser agrees with it.
_probe_list() {
  local f="$DOTFILES/install/tools.lst"
  [ -r "$f" ] || {
    blib_warn "install/tools.lst is missing or unreadable — cannot probe host tools"
    return 1
  }
  sed 's/#.*//' "$f" | awk 'NF { print $1 }'
}

check_tools() {
  blib_say "checking host tools (install missing ones via your OS layer — see install/README.md)"
  local t missing=0 unreachable=0 found="" tools=""
  tools="$(_probe_list)" || return 0
  [ -n "$tools" ] || {
    blib_warn "install/tools.lst lists no tools — nothing probed"
    return 0
  }
  # Order is the file's order, and zsh leads it deliberately: it is the shell this entire
  # layer runs in, so its absence is categorically worse than a missing forensics tool.
  # The end-of-run guard says so loudly — this just makes it visible alongside the rest.
  for t in $tools; do
    if command -v "$t" >/dev/null 2>&1; then
      blib_ok "found: $t"
    elif found="$(_probe_altname "$t")"; then
      blib_ok "found: $t (as \`$found\`)"
    elif found="$(_probe_offpath "$t")"; then
      blib_warn "unreachable: $t is installed at $found but is not on \$PATH"
      blib_warn "  defense.zsh calls it by bare name — fix with:  ln -s $found ~/.local/bin/$t"
      unreachable=$((unreachable + 1))
    else
      blib_warn "missing: $t"
      missing=$((missing + 1))
    fi
  done
  if command -v docker >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
      blib_ok "docker compose available — \`siemup\` will work"
    else blib_warn "docker present but compose plugin missing — siemup needs it"; fi
  fi
  if ((missing == 0 && unreachable == 0)); then
    blib_ok "all probed tools present"
  else
    ((missing > 0)) &&
      blib_warn "$missing tool(s) missing — the forensics tools are optional; zsh is not"
    ((unreachable > 0)) &&
      blib_warn "$unreachable tool(s) installed but off \$PATH — symlink them (see above) or this layer cannot call them"
  fi
  # Report-only, like the rest of this probe: an unreachable tool is a warning, never a
  # non-zero exit. Callers that want to gate on it read the counts above.
  return 0
}

# shellcheck disable=SC2329
bootstrap_check() {
  if ((DO_CHECK)); then check_tools; fi
}

# What only this repo knows at the end. blib_login_shell_hint is the report-only guard:
# everything above wires a zsh config, and on a box with no zsh — or with zsh installed but
# not the login shell — every step still "succeeds" and nothing ever loads. It returns
# non-zero when zsh is ABSENT, which tells the driver the wiring is inert and to print no
# "complete" line; with zsh present but not the login shell it names the chsh fix and sets
# the closing hint to "for this session: exec zsh".
# shellcheck disable=SC2329
bootstrap_closing() {
  blib_say "case data lives in ~/cases (outside this repo) — run \`mkcase <name>\` to start one"
  blib_login_shell_hint
}

blib_main "$@"
