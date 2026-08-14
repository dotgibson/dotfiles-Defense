#!/usr/bin/env bash
# dotfiles-Defense/bootstrap.sh
# Wire the defensive (blue) role layer onto an already-provisioned box.
# Distro-agnostic: does NOT install OS packages (your OS-native layer does that).
# Idempotent. Stacks: vendored Core + your OS-native layer + DEFENSE role.
#
# The SHARED half of a bootstrap — link-with-backup, the Core symlink surface, the
# managed ~/.zshrc loader — is CALLED out of core/lib/bootstrap-lib.sh, not copied.
# That file exists because every OS repo used to hand-roll the same code and then
# drift; this repo was drifting the same way. What stays here is the genuinely
# Defense-specific part: the forensics host-tool probe and the band-85 role stage.
#
#   ./bootstrap.sh                 # symlinks + loader + tool/docker checks
#   ./bootstrap.sh --links-only    # just (re)create symlinks
#   ./bootstrap.sh --no-check      # skip the host-tool / docker probe
#   ./bootstrap.sh --dry-run       # print the full plan, change nothing
#   ./bootstrap.sh --only=zsh,git  # wire only these groups
#   ./bootstrap.sh --skip=tmux     # wire everything except these
#     groups: zsh nvim tmux git prompt tools (the band-85 role stage rides `zsh`)
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
LINKS_ONLY=0
DO_CHECK=1
ONLY_CSV=""
SKIP_CSV=""

for a in "$@"; do case "$a" in
  --links-only) LINKS_ONLY=1 ;;
  --no-check) DO_CHECK=0 ;;
  --dry-run) BLIB_DRY=1 ;;
  # Stashed, not applied: the validator (blib_select) lives in the library, which cannot
  # be sourced until the subtree guard below has run. Applied right after the source.
  --only=*) ONLY_CSV="${a#*=}" ;;
  --skip=*) SKIP_CSV="${a#*=}" ;;
  -h | --help)
    sed -n '2,19p' "$0"
    exit 0
    ;;
  *)
    echo "unknown arg: $a" >&2
    exit 1
    ;;
  esac done

# ── core/ subtree present? ────────────────────────────────────────────────────
# CHICKEN-AND-EGG: this one guard cannot move into the lib — you cannot source a file
# out of core/ before confirming core/ exists (see bootstrap-lib.sh's header). So it
# stays inline, ahead of the two `source` lines below — and it checks the paths those
# lines actually READ, not just core/zsh as a proxy. A half-vendored subtree (core/zsh
# present, core/lib absent) would otherwise die on bash's own `source: No such file`
# under set -e, losing the one message that says how to fix it.
for req in core/zsh core/lib/ux.sh core/lib/bootstrap-lib.sh; do
  if [[ ! -e "$DOTFILES/$req" ]]; then
    echo "core/ subtree missing or incomplete (no $req). One time, from the repo root run:" >&2
    echo "  git subtree add --prefix=core <dotfiles-core remote> main --squash" >&2
    exit 1
  fi
done

# ux.sh first — it sets the UX_* palette the blib_* message helpers read; sourced the
# other way round they still work, just uncoloured.
# shellcheck source=core/lib/ux.sh
source "$DOTFILES/core/lib/ux.sh"
# shellcheck source=core/lib/bootstrap-lib.sh
source "$DOTFILES/core/lib/bootstrap-lib.sh"

# Now that blib_select exists, validate the stashed selectors. It aborts on a malformed
# selector or an unknown group name, so it must be called directly (never in a subshell).
if [[ -n "$ONLY_CSV" ]]; then blib_select --only "$ONLY_CSV"; fi
if [[ -n "$SKIP_CSV" ]]; then blib_select --skip "$SKIP_CSV"; fi

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

# ── the DEFENSE role stage (band 85) ─────────────────────────────────────────
# The one wiring step Core knows nothing about: Core ships bands 00-69, the OS-native
# repo lands 80-os.zsh, and this repo owns 85. Grouped under `zsh` so --skip zsh drops
# the role stage with the rest of the shell rather than half-wiring it.
wire_defense_stage() {
  blib_want zsh || return 0
  blib_say "symlinking DEFENSE role layer"
  # v4: the loader globs NUMBERED fragments ($ZSH_CFG/NN-*.zsh). The defense role stage is
  # band 85 — it sorts AFTER the OS layer (80-os.zsh, from the OS-native repo) and BEFORE
  # host-local (99-local.zsh), preserving the old `… os defense local` order. Drop any stale
  # pre-v4 unnumbered link so the loader doesn't see a dead entry.
  if [[ -L "$CONFIG/zsh/defense.zsh" ]]; then
    # BLIB_DRY, not the library's _blib_dry(): the underscore marks that helper private,
    # and this is the documented public knob. Sole raw mutation in this file — every
    # other change goes through blib_link, which honours dry-run itself.
    if [[ "${BLIB_DRY:-0}" != 0 ]]; then
      blib_say "would drop stale pre-v4 link: $CONFIG/zsh/defense.zsh"
    else
      rm -f "$CONFIG/zsh/defense.zsh"
    fi
  fi
  blib_link "$DOTFILES/defense/defense.zsh" "$CONFIG/zsh/85-defense.zsh"
  if [[ -d "$DOTFILES/defense/templates" ]]; then
    blib_link "$DOTFILES/defense/templates" "$CONFIG/defense/templates"
  fi
}

wire_links() {
  # Core's whole shipped surface, one call: the numbered zsh fragments, nvim + the vim
  # fallback, tmux (+ tpm), starship, git, and the tools group. This repo previously
  # linked a hand-picked SUBSET of that and silently missed the rest.
  blib_link_core "$DOTFILES" "$CONFIG"
  # No blib_link_os_layer: the 80 band belongs to your OS-native repo, not this one.
  # Writes the managed ~/.zshrc AND seeds $ZDOTDIR/.zshrc — the entry file exports
  # ZDOTDIR, so without that second file every nested zsh finds no startup files, runs
  # zsh-newuser-install, and loads none of Core.
  blib_write_zshrc_loader
  wire_defense_stage
  blib_wire_summary
}

# --links-only skips the host-tool/docker probe too (it's the "just wire symlinks" path);
# without consulting LINKS_ONLY here, --links-only would still run the probe and the flag
# would be dead. --no-check skips it independently.
((DO_CHECK && !LINKS_ONLY)) && check_tools
wire_links
blib_say "case data lives in ~/cases (outside this repo) — run \`mkcase <name>\` to start one"

# Everything above wires a zsh config. On a box with no zsh — or with zsh installed but not
# the login shell — every step still "succeeds" and nothing ever loads. So this is checked
# OUTSIDE check_tools: --no-check and --links-only skip a tool probe, but must not silence a
# correctness guard. Non-fatal, matching how missing host tools are handled — the script is
# idempotent by design and has to stay re-runnable on a box mid-provisioning.
#
# Deliberately NOT blib_set_login_shell: that helper is correct, but it sudo's (chsh, and an
# append to /etc/shells). This bootstrap's contract is report-only — "does NOT install OS
# packages", line 4 — so it names the remedy and lets the operator run it.
#
# Best-effort, and it MUST NOT abort: this file runs under `set -euo pipefail`, where
# pipefail makes `getent … | cut` return getent's status rather than cut's. getent exits 2
# when the user is not in the passwd DB, and is 127 when absent altogether (it is not
# universal outside glibc) — either would take the whole bootstrap down on its last line,
# turning the non-fatal guard below into the loudest possible failure. So every lookup is
# guarded, in descending order of trust: getent, then /etc/passwd, then $SHELL. All three
# may come up empty; the guard reports that as "unknown" rather than caring.
detect_login_shell() {
  local user shell_field=""
  user="$(id -un 2>/dev/null || true)"
  if [[ -n "$user" ]]; then
    if command -v getent >/dev/null 2>&1; then
      shell_field="$(getent passwd "$user" 2>/dev/null | cut -d: -f7 || true)"
    fi
    if [[ -z "$shell_field" && -r /etc/passwd ]]; then
      shell_field="$(awk -F: -v u="$user" '$1 == u { print $7; exit }' /etc/passwd 2>/dev/null || true)"
    fi
  fi
  printf '%s' "${shell_field:-${SHELL:-}}"
}

login_shell="$(detect_login_shell)"
if ! command -v zsh >/dev/null 2>&1; then
  blib_warn "zsh is NOT installed — the config above is wired but inert; nothing reads ~/.zshrc"
  blib_warn "  your OS-native layer owns package installation (see install/README.md)"
elif [[ "$login_shell" != *zsh ]]; then
  blib_warn "zsh is installed, but your login shell is ${login_shell:-unknown}"
  blib_warn "  fix: chsh -s $(command -v zsh)  — takes effect at next login"
  blib_ok "Defense bootstrap complete — for this session: exec zsh"
else
  blib_ok "Defense bootstrap complete — open a new shell, or: exec zsh"
fi
