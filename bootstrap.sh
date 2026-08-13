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
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
LINKS_ONLY=0
DO_CHECK=1

for a in "$@"; do case "$a" in
  --links-only) LINKS_ONLY=1 ;;
  --no-check) DO_CHECK=0 ;;
  --dry-run) BLIB_DRY=1 ;;
  -h | --help)
    sed -n '2,16p' "$0"
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
# stays inline, ahead of the two `source` lines below.
if [[ ! -d "$DOTFILES/core/zsh" ]]; then
  echo "core/ subtree missing. One time, from the repo root run:" >&2
  echo "  git subtree add --prefix=core <dotfiles-core remote> main --squash" >&2
  exit 1
fi

# ux.sh first — it sets the UX_* palette the blib_* message helpers read; sourced the
# other way round they still work, just uncoloured.
# shellcheck source=core/lib/ux.sh
source "$DOTFILES/core/lib/ux.sh"
# shellcheck source=core/lib/bootstrap-lib.sh
source "$DOTFILES/core/lib/bootstrap-lib.sh"

# ── Host-tool / docker probe (report only — never installs) ──────────────────
check_tools() {
  blib_say "checking host tools (install missing ones via your OS layer — see install/README.md)"
  local t missing=0
  # zsh leads the list deliberately: it is the shell this entire layer runs in, so its
  # absence is categorically worse than a missing forensics tool. The end-of-run guard
  # says so loudly — this line just makes it visible in the probe alongside the rest.
  for t in zsh docker jq tshark zeek suricata chainsaw hayabusa sigma yara velociraptor vol log2timeline.py; do
    if command -v "$t" >/dev/null 2>&1; then
      blib_ok "found: $t"
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
  if ((missing == 0)); then
    blib_ok "all probed tools present"
  else blib_warn "$missing tool(s) missing — the forensics tools are optional; zsh is not"; fi
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
    if _blib_dry; then
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
