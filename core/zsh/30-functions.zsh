# core/zsh/functions.zsh
# ──────────────────────────────────────────────────────────────────────────────
# Cross-OS shell functions. Pure POSIX-ish where possible so they behave the
# same on macOS zsh, Linux zsh, and Alpine's busybox-adjacent environment.
# Nothing OS-specific or offensive here — those live in the OS / Kali repos.
# ──────────────────────────────────────────────────────────────────────────────

# Resolved path to the vendored version stamp. core.version sits one dir ABOVE zsh/,
# so from this module: %x = the file being sourced, :A resolves the bootstrap symlink
# back into core/zsh/functions.zsh, :h:h climbs to core/, then /core.version. Captured
# at source time (the proven pattern from options.zsh / maint.zsh).
typeset -g _CORE_VERSION_FILE="${${(%):-%x}:A:h:h}/core.version"

# _core_install_prefix <mgr>  → the copy-pasteable "install" command prefix for a
# package manager (the verb differs per distro: apt install / pacman -S / apk add / …).
# Pure mapping, no probing — callers pass the manager from update.zsh's _pkgup_mgr. Used
# by core-doctor (U2) and the command-not-found handler (U1) to turn a missing tool into
# an actionable line instead of a bare ✗. Unknown/none → non-zero, caller stays silent.
_core_install_prefix() {
  case "$1" in
  brew)   print -r -- "brew install" ;;
  pacman) print -r -- "sudo pacman -S" ;;
  dnf)    print -r -- "sudo dnf install" ;;
  zypper) print -r -- "sudo zypper install" ;;
  apt)    print -r -- "sudo apt install" ;;
  apk)    print -r -- "sudo apk add" ;;
  emerge) print -r -- "sudo emerge" ;;
  *)      return 1 ;;
  esac
}

# core-version — print the vendored Core layer's version. Lets you tell WHICH Core a
# given OS repo carries from inside it: the subtree squash records the commit, this
# records the human SemVer (core.version, bumped at release to match the git tag).
core-version() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "core-version" "print the vendored Core layer's version"; return 0; }
  if [[ -r "$_CORE_VERSION_FILE" ]]; then
    print -r -- "dotfiles-core $(<"$_CORE_VERSION_FILE")"
  else
    _core_err "core-version: version stamp not found at $_CORE_VERSION_FILE"
    return 1
  fi
}

# ── core — the umbrella front door (B1) ───────────────────────────────────────
# ONE discoverable namespace over Core's first-party verbs, so a newcomer types a
# single command (`core`) and finds everything instead of having to already know
# `core-help` / `core-doctor` / `up` by name. The standalone verbs still exist
# (muscle memory + their own completions); this is an additive front door, not a
# replacement — and it keeps the generic-sounding verbs (`up`, `serve`) reachable
# under a namespaced form that won't be mistaken for some other tool.
#   core                  → the cheat sheet  (U6: bare `core` is help, never an error)
#   core help [filter]    → core-help
#   core doctor [-v]      → core-doctor
#   core version          → core-version
#   core update [-y|-n]   → up
# The subcommand list is the single source the completion (_core) and the
# unknown-subcommand did-you-mean both read, so they can't drift.
typeset -ga _CORE_SUBCMDS=(help doctor version update)
core() {
  emulate -L zsh
  local sub="${1:-}"
  (($#)) && shift
  case "$sub" in
  "" | -h | --help | help) core-help "$@" ;;
  doctor) core-doctor "$@" ;;
  version | -V | --version) core-version "$@" ;;
  update)
    # `up` lives in 60-update, which the minimal/standard CORE_PROFILEs omit. Dispatch only
    # when it is actually loaded — otherwise report cleanly instead of reaching a missing
    # command (the front door stays availability-aware even when the surface is reduced).
    if (( $+functions[up] )); then
      up "$@"
    else
      _core_err "core update: the updater (\`up\`) is not loaded under CORE_PROFILE=${CORE_PROFILE:-full}"
      _core_hint "it lives in the update/maintenance bands — set CORE_PROFILE=full to enable it"
      return 1
    fi
    ;;
  *)
    _core_err "core: unknown subcommand: ${sub}"
    local _sug
    _sug="$(_core_suggest "$sub" "${_CORE_SUBCMDS[@]}")"
    [[ -n "$_sug" ]] && _core_hint "did you mean core ${_sug}?"
    _core_usage "core <${(j:|:)_CORE_SUBCMDS}>"
    return 1
    ;;
  esac
}

# core-doctor — the shell counterpart to nvim's `:checkhealth gerrrt`: a scannable
# report of which modern-CLI tools Core detected on THIS box and which integrations are
# live, so you can see at a glance what's degraded to a classic fallback. Probes live
# via _core_have (command -v), so it's honest even if tools.zsh hasn't run, and shows
# the RESOLVED binary names (fd vs fdfind, bat vs batcat) — the cross-distro detail that
# silently changes behaviour. Read-only: it inspects, never installs.
# Public verb: render the health report, paging it when taller than the window (a small
# split + core-doctor -v). Same wrapper shape as core-help: TTY-only paging, forced colour
# through the capture, direct render (byte-identical) on a pipe/redirect/the unit tests.
# _core_wired <tool> — is this integration actually WIRED into the live shell, not
# merely installed? Presence (command -v) ≠ active: starship can be on PATH while the
# prompt is plain, atuin installed while Ctrl-E is dead, mise present while the chpwd
# hook never registered. Probe the function/widget each tool's init defines, so
# core-doctor can tell "✓ present" from "✓ present AND working". Returns non-zero for an
# unknown tool. (Inherited into core-doctor's `$()` capture: zsh forks keep functions +
# the $widgets/$precmd_functions params readable.)
_core_wired() {
  case "$1" in
  starship) (( $+functions[starship_precmd] )) ;;
  atuin)    [[ -n ${widgets[atuin-search]:-} ]] || (( $+functions[_atuin_precmd] )) ;;
  mise)     (( $+functions[_mise_hook] )) || (( $+functions[__mise_hook] )) ;;
  zoxide)   (( $+functions[__zoxide_hook] )) || (( $+functions[__zoxide_z] )) ;;
  carapace) (( $+functions[_carapace] )) ;;
  *) return 1 ;;
  esac
}

# _core_doctor_json — machine-readable health (B12). The gate scripts emit --json; the
# RUNTIME health verb did not, so a statusline/editor/CI could not consume it. One object
# on stdout, never paged: {version, tools{name:bool}, wired{name:bool}, resolved{…}}.
# Pure zsh (no python): tool names are fixed identifiers, so no escaping is needed.
_core_doctor_json() {
  emulate -L zsh
  local ver="unknown"
  [[ -r "$_CORE_VERSION_FILE" ]] && ver="$(<"$_CORE_VERSION_FILE")"
  local -a alltools=(
    eza bat fd rg fzf zoxide delta dust duf procs btop yazi
    starship atuin mise carapace gum sesh jq yq gron sd xh doggo glow op
  )
  local -a wir=(starship atuin mise zoxide carapace)
  local t first=1
  print -rn -- "{\"version\":\"${ver}\",\"tools\":{"
  for t in $alltools; do
    ((first)) || print -rn -- ","; first=0
    if _core_have "$t"; then print -rn -- "\"$t\":true"; else print -rn -- "\"$t\":false"; fi
  done
  print -rn -- "},\"wired\":{"
  first=1
  for t in $wir; do
    ((first)) || print -rn -- ","; first=0
    if _core_have "$t" && _core_wired "$t"; then print -rn -- "\"$t\":true"; else print -rn -- "\"$t\":false"; fi
  done
  print -rn -- "},\"resolved\":{\"fd\":\"${FD_BIN:-}\",\"bat\":\"${BAT_BIN:-}\""
  (($+functions[_pkgup_mgr])) && print -rn -- ",\"pkg_manager\":\"$(_pkgup_mgr)\""
  print -r -- "}}"
}

core-doctor() {
  emulate -L zsh
  # --json (anywhere on the line) → machine-readable, never paged (B12).
  local a
  for a in "$@"; do [[ "$a" == --json ]] && { _core_doctor_json; return 0; }; done
  if [[ -t 1 && -z ${CORE_NO_PAGER:-} ]]; then
    local _out
    _out="$(_CORE_FORCE_COLOR=1 _core_doctor_render "$@")"
    local _rc=$?
    _core_page "$_out"
    return $_rc
  fi
  _core_doctor_render "$@"
}
_core_doctor_render() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "core-doctor [-v|--versions] [--json]" "report Core's detected tools + which integrations are actually wired (-v adds versions; --json for machines)"; return 0; }
  # Default stays fast + scannable (one `command -v` per tool). -v/--versions opts INTO a
  # version readout next to each ✓ — useful for spotting an ancient fzf/bat — at the cost of
  # one `--version` fork per present tool, so it is deliberately NOT the default. --json is
  # intercepted by the wrapper before here, so it never reaches this arm.
  local show_versions=0
  case "${1:-}" in
  -v | --versions) show_versions=1 ;;
  "") ;;
  *)
    _core_err "core-doctor: unexpected argument: $1"
    _core_usage "core-doctor [-v|--versions] [--json]"
    return 1
    ;;
  esac
  local g='' c='' d='' r=''
  if [[ ( -t 1 || -n ${_CORE_FORCE_COLOR:-} ) && -z ${NO_COLOR:-} ]]; then
    # green/cyan stay local (doctor's own ✓/group semantics); the dim muted reuses
    # ui.zsh's canonical $_CORE_C_MUTED so "muted grey" has one definition Core-wide.
    g=$'\e[32m' c=$'\e[36m' d="${_CORE_C_MUTED:-$'\e[2;37m'}" r=$'\e[0m'
  fi
  local ver="unknown"
  [[ -r "$_CORE_VERSION_FILE" ]] && ver="$(<"$_CORE_VERSION_FILE")"
  print -r -- "${c}dotfiles-core ${ver}${r} ${d}— core-doctor (✓ present · ✗ falls back to classic)${r}"

  # Grouped tool report: "group label" then a space-separated tool list. A tool is
  # ✓ when it resolves on PATH, ✗ (dimmed) when Core degrades to the classic command.
  local -a groups=(
    "modern CLI"   "eza bat fd rg fzf zoxide delta dust duf procs btop yazi"
    "integrations" "starship atuin mise carapace gum sesh"
    "data / net"   "jq yq gron sd xh doggo glow op"
  )
  local gi tool line
  local -a missing=()
  for ((gi = 1; gi <= ${#groups}; gi += 2)); do
    print -r -- "${c}${groups[gi]}${r}"
    line=""
    for tool in ${=groups[gi + 1]}; do
      if _core_have "$tool"; then
        if ((show_versions)); then
          # Best-effort, like setup.sh's _doctor: pull the first semver-ish token from
          # the tool's own --version. Unparseable → just the ✓ (never an error).
          local _v
          _v="$("$tool" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"
          line+="  ${g}✓${r} ${tool}${_v:+ ${d}${_v}${r}}"
        else
          line+="  ${g}✓${r} ${tool}"
        fi
      else line+="  ${d}✗ ${tool}${r}"; missing+=("$tool"); fi
    done
    print -r -- " $line"
  done

  # Actionable: turn the ✗'d tools into a copy-pasteable install line for THIS box's
  # package manager (U2), instead of leaving the reader to look each one up. Best-effort
  # — gated on update.zsh's _pkgup_mgr being loaded (it isn't in the unit harness, which
  # sources ui+functions alone) and on a known manager. Two honesty caveats, because a
  # blanket `pkg install <all>` misleads: (1) package NAMES can differ from the command
  # (rg=ripgrep); (2) not every modern-CLI tool is PACKAGED on every distro — some are
  # binary-distributed and the right method varies per tool AND distro (a distro package,
  # `mise use -g`, `go install`, `cargo install`, or a vendor repo — e.g. `op`). Rather
  # than embed a rot-prone per-distro table here (that is exactly what PORTING-MATRIX.md
  # is), point the reader at the matrix for the authoritative per-tool install path.
  if ((${#missing})) && (($+functions[_pkgup_mgr])); then
    local _mgr _pfx
    _mgr="$(_pkgup_mgr)"
    if _pfx="$(_core_install_prefix "$_mgr")"; then
      print -r -- "${c}install missing${r}"
      print -r -- "  ${d}${_pfx} ${missing[*]}${r}"
      print -r -- "  ${d}names differ per distro (rg=ripgrep, delta=git-delta), and some aren't packaged${r}"
      print -r -- "  ${d}on every distro — see core/PORTING-MATRIX.md for the per-tool install path${r}"
    fi
  fi

  # Active-integration probe (U1): presence (command -v, above) is NOT the same as wired.
  # Report which integrations actually registered their hooks/widgets in THIS shell, so a
  # "starship installed but the prompt is plain" or "atuin present but Ctrl-E is dead" is
  # visible instead of a misleading green ✓. ○ = installed but idle (not wired here). Only
  # the present ones are listed (an absent tool already shows ✗ in the group above).
  local -a wirable=(starship atuin mise zoxide carapace)
  local w wline=""
  for w in $wirable; do
    _core_have "$w" || continue
    if _core_wired "$w"; then wline+="  ${g}✓${r} ${w}"
    else wline+="  ${d}○ ${w} (idle)${r}"; fi
  done
  if [[ -n "$wline" ]]; then
    print -r -- "${c}integrations wired${r}"
    print -r -- " $wline"
  fi

  # Resolved binary names + the detected package manager — the behaviour-affecting bits
  # a bare ✓/✗ hides (Debian's fd→fdfind/bat→batcat; which `up` manager fires here).
  print -r -- "${c}resolved${r}"
  print -r -- "  ${d}fd → ${FD_BIN:-(none)}    bat → ${BAT_BIN:-(none)}${r}"
  if (($+functions[_pkgup_mgr])); then
    print -r -- "  ${d}package manager → $(_pkgup_mgr)${r}"
  fi
}

# mkcd — make a directory and cd into it
mkcd() {
  _core_wants_help "$1" && { _core_help "mkcd <dir>" "make a directory (and parents) and cd into it"; return 0; }
  [[ -z "$1" ]] && { _core_usage "mkcd <dir>"; return 1; }
  mkdir -p -- "$1" && cd -- "$1"
}

# cdup — climb N directories (cdup 3 == cd ../../..). NOT named `up`: that's the
# package-updater in update.zsh. N defaults to 1 and must be a positive integer —
# a typo'd `cdup x` should say so, not silently no-op (the loop never runs) and leave
# you wondering why you didn't move.
cdup() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "cdup [n]" "climb n directories (default 1); cdup 3 == cd ../../.."; return 0; }
  local n="${1:-1}" p=""
  if [[ "$n" != <-> ]] || ((n < 1)); then
    _core_err "cdup: count must be a positive integer (got '$n')"
    _core_usage "cdup [n]"
    return 1
  fi
  while ((n-- > 0)); do p="../$p"; done
  cd "$p" || return
}

# _extract_dispatch — the raw unpack, NO safety guard. Split out of extract() so the
# "contain a tarbomb in a subdir" path (below) can re-run the unpack in that subdir
# WITHOUT re-entering the guard (which would see the same multi-entry archive and
# recurse forever). ouch (if installed) handles every format from one binary; the
# hand-rolled case is the bare-box fallback.
_extract_dispatch() {
  [[ -n ${HAVE_OUCH:-} ]] && { ouch decompress "$1"; return; }
  case "$1" in
  *.tar.bz2 | *.tbz2) tar xjf "$1" ;;
  *.tar.gz | *.tgz) tar xzf "$1" ;;
  *.tar.xz) tar xJf "$1" ;;
  *.tar) tar xf "$1" ;;
  *.bz2) bunzip2 -f "$1" ;;
  *.gz) gunzip -f "$1" ;;
  *.zip) unzip "$1" ;;
  *.7z) 7z x "$1" ;;
  *.rar) unrar x "$1" ;;
  *)
    _core_errbox "extract: unknown archive format" \
      "file:      ${1:t}" \
      "supported: .tar.gz/.tgz · .tar.bz2/.tbz2 · .tar.xz · .tar · .gz · .bz2 · .zip · .7z · .rar" \
      "tip:       install 'ouch' to (un)pack every format from one binary"
    return 1
    ;;
  esac
}

# _extract_run — dispatch with a progress spinner on the QUIET formats (tar/gz/bz2),
# so a large unpack reads as progress instead of a frozen terminal (U6). Chatty
# unpackers (zip/7z/rar) and ouch print their own output, so run those directly rather
# than fight their bytes with the spinner. _core_spin's non-TTY path just runs the
# command, so scripted/piped extracts and the unit tests behave exactly as before.
_extract_run() {
  emulate -L zsh
  if [[ -z ${HAVE_OUCH:-} && "$1" == (*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.tar|*.gz|*.bz2) ]] \
    && (($+functions[_core_spin])); then
    _core_spin "extracting ${1:t}" _extract_dispatch "$1"
  else
    _extract_dispatch "$1"
  fi
}

# extract — one command for any archive, with two defences applied BEFORE anything
# is written to disk:
#   • tarbomb guard — an archive with several top-level entries would scatter them
#     across the CWD; offer to contain it in ./<archive-name>/ instead.
#   • clobber guard — if a top-level entry already exists, confirm before overwriting.
# Both peek at the listing first (best-effort per format; unlistable → just unpack).
# Confirmation is via _core_confirm, which DECLINES with no TTY — so a scripted /
# piped run never silently overwrites, and a single-rooted archive (the common case)
# sails straight through untouched.
extract() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "extract <archive>" "unpack any archive (tar/zip/7z/rar/…); guards tarbombs + clobbers"; return 0; }
  [[ -z "$1" ]] && { _core_usage "extract <archive>"; return 1; }
  [[ -f "$1" ]] || {
    _core_err "extract: '$1' is not a file"
    return 1
  }
  local archive="$1" abs="${1:A}"

  # Entries this archive would write. tar/zip extract relative to the CWD, so their
  # top-level names are CWD-relative; gz/bz2 instead write NEXT TO the archive, so the
  # target is the archive's full path minus the compression suffix (${abs:r}) — not a
  # CWD basename. Getting that right means `extract /some/dir/file.gz` correctly checks
  # /some/dir/file for clobber, not ./file. Drop any '.'/'' rows (leading-'./'  tars).
  # We list/dispatch via $abs throughout, which also sidesteps a leading-'-' filename
  # being read as an option by tar/unzip/gunzip. Unlistable formats → empty → no guard.
  local -a top
  case "$archive" in
  *.tar.bz2 | *.tbz2 | *.tar.gz | *.tgz | *.tar.xz | *.tar)
    top=(${(f)"$(tar tf "$abs" 2>/dev/null | cut -d/ -f1 | sort -u)"}) ;;
  *.zip)
    top=(${(f)"$(unzip -Z1 "$abs" 2>/dev/null | cut -d/ -f1 | sort -u)"}) ;;
  *.gz | *.bz2)
    top=("${abs:r}") ;;
  esac
  top=(${top:#.}) # strip a bare '.' top entry (leading './' archives)

  if ((${#top})); then
    # Tarbomb: more than one top-level entry. Contain it in a subdir (default-safe:
    # with no TTY _core_confirm declines and we fall through to extract-in-place,
    # having at least warned).
    if ((${#top} > 1)); then
      local into="${archive:t:r}"
      into="${into%.tar}"
      _core_warn "extract: '${archive:t}' has ${#top} top-level entries — would scatter across $(pwd)"
      if _core_confirm "extract into ./${into}/ instead?"; then
        mkdir -p -- "$into" || {
          _core_err "extract: cannot create '$into'"
          return 1
        }
        (cd -- "$into" && _extract_run "$abs")
        return
      fi
    fi
    # Clobber: any existing top-level target. Confirm before overwriting; declined
    # (or no TTY) → abort with nothing touched.
    local t
    local -a clobber=()
    for t in "${top[@]}"; do [[ -e "$t" ]] && clobber+=("$t"); done
    if ((${#clobber})); then
      _core_warn "extract: would overwrite existing: ${clobber[*]}"
      _core_confirm "overwrite?" || {
        _core_warn "extract: cancelled (nothing overwritten)"
        return 1
      }
    fi
  fi

  _extract_run "$abs"
}

# fcd — fuzzy-cd into any subdirectory (needs fzf + fd, degrades to find)
fcd() {
  _core_wants_help "$1" && { _core_help "fcd" "fuzzy-cd into any subdirectory (fzf + fd, degrades to find)"; return 0; }
  _core_have fzf || {
    _core_err "fcd: requires fzf"
    _core_hint "install fzf, then retry"
    return 1
  }
  local dir
  if [[ -n ${HAVE_FZF:-} && -n ${HAVE_FD:-} ]]; then
    dir=$("$FD_BIN" --type d --hidden --exclude .git | fzf) && cd "$dir"
  else
    dir=$(find . -type d -not -path '*/.git/*' 2>/dev/null | fzf) && cd "$dir"
  fi
}

# please — re-run the last command with sudo. PREVIEWS the command and CONFIRMS
# first: this eval's your previous line as root, so a fat-fingered history entry
# (or a function that left something unexpected as the last command) should not
# silently run privileged. _core_confirm declines with no TTY, so this is fail-safe
# in a non-interactive context too.
please() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "please" "re-run the last command with sudo (previews + confirms first)"; return 0; }
  local last
  last="$(fc -ln -1 2>/dev/null)"
  if [[ -z "${last//[[:space:]]/}" ]]; then
    _core_err "please: no previous command to re-run"
    return 1
  fi
  _core_warn "about to run as root:  sudo ${last}"
  _core_confirm "proceed?" || {
    _core_warn "please: cancelled"
    return 1
  }
  eval "sudo ${last}"
}

# mkbak — timestamped backup of a file before you edit it. Validates its input in
# Core's voice instead of letting `cp` emit a raw "missing operand"/"No such file"
# (the rest of functions.zsh — mkcd, extract — guards the same way).
mkbak() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "mkbak <file>" "timestamped .bak copy of a file before you edit it"; return 0; }
  [[ -z "$1" ]] && {
    _core_usage "mkbak <file>"
    return 1
  }
  [[ -f "$1" ]] || {
    _core_err "mkbak: '$1' is not a regular file"
    return 1
  }
  # Collision-safe + non-interactive. Two backups in the same second must NOT clobber
  # the first, and mkbak must never PROMPT — but `cp -i` bleeds in from aliases.zsh
  # (parsed before this module), so a same-second collision would stop for a y/n. Pick
  # the next free .bak suffix, and copy via `command cp` to bypass the interactive alias.
  local ts dst n=1
  ts="$(date +%Y%m%d-%H%M%S)"
  dst="$1.$ts.bak"
  while [[ -e "$dst" ]]; do dst="$1.$ts.$((n++)).bak"; done
  command cp -p -- "$1" "$dst" && _core_ok "backup: ${dst:t}"
}

# _serve_advertise <port> — print the reachable http:// URLs for a 0.0.0.0 serve
# (tunnel/callback IP first in interface-priority order, then the default-route LAN IP)
# and return the best QR target in $REPLY. Split out of `serve` so the platform-specific
# discovery is HERMETICALLY testable (stub ip/ipconfig/route) without the blocking
# http.server. Linux/WSL uses ip(8); macOS/BSD ship none, so fall back to route(8)+ipconfig
# — the same split tmux/scripts/tmux-netinfo.sh uses; the tunnel list is kept aligned with
# that script's TUN_IFACES so no interface (tun1/tun2/wg1/…) is silently skipped.
_serve_advertise() {
  emulate -L zsh
  local port="$1" ip i qr_url="" dev
  local -a tun_ifaces=(tun0 tun1 tun2 wg0 wg1 proton0 nordlynx tailscale0 utun3 utun4 utun5)
  if command -v ip >/dev/null 2>&1; then # Linux / WSL
    for i in "${tun_ifaces[@]}"; do
      ip=$(ip -4 -o addr show "$i" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
      [[ -n "$ip" ]] && {
        echo "  → http://${ip}:${port}/   (${i})"
        qr_url="http://${ip}:${port}/"
        break
      }
    done
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}')
    [[ -n "$ip" ]] && { echo "  → http://${ip}:${port}/   (lan)"; : "${qr_url:=http://${ip}:${port}/}"; }
  elif command -v ipconfig >/dev/null 2>&1; then # macOS / BSD — no ip(8)
    for i in "${tun_ifaces[@]}"; do
      ip=$(ipconfig getifaddr "$i" 2>/dev/null)
      [[ -n "$ip" ]] && {
        echo "  → http://${ip}:${port}/   (${i})"
        qr_url="http://${ip}:${port}/"
        break
      }
    done
    # Reset ip before the LAN lookup: route(8) may find no default interface, and the
    # guarded assignment below would otherwise leave a tunnel address in $ip and reprint
    # it as "(lan)". (The Linux branch's unconditional ip=$(…) self-clears.)
    ip=""
    dev=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    [[ -n "$dev" ]] && ip=$(ipconfig getifaddr "$dev" 2>/dev/null)
    [[ -n "$ip" ]] && { echo "  → http://${ip}:${port}/   (lan)"; : "${qr_url:=http://${ip}:${port}/}"; }
  fi
  REPLY="$qr_url"
}

# serve — quick HTTP server in the CWD, printing the URLs it's actually reachable
# at (tunnel IP first, then LAN). Replaces the old `serve` alias. Binds all
# interfaces on purpose: this is your ad-hoc file-transfer server. Optional port.
#   serve            # port 8000
#   serve 8080       # port 8080
serve() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "serve [-l|--local] [port]" "HTTP server in the CWD (default 8000); all interfaces, or loopback with -l"; return 0; }
  # Parse flags + the optional port in ANY order: a typo'd flag is rejected in Core's
  # voice rather than silently treated as a bad port. -l/--local binds 127.0.0.1 (the
  # "just me" case) instead of the default all-interfaces exposure.
  local port="" local_only=0 arg
  for arg in "$@"; do
    case "$arg" in
    -l | --local) local_only=1 ;;
    -*)
      _core_err "serve: unknown option: $arg"
      local _sug
      _sug="$(_core_suggest "$arg" -l --local)"
      [[ -n "$_sug" ]] && _core_hint "did you mean ${_sug}?"
      _core_usage "serve [-l|--local] [port]"
      return 1
      ;;
    *)
      if [[ -n "$port" ]]; then
        _core_err "serve: too many arguments (got an extra '$arg')"
        _core_usage "serve [-l|--local] [port]"
        return 1
      fi
      port="$arg"
      ;;
    esac
  done
  : "${port:=8000}"
  # Defensive input handling: a typo'd port should be rejected cleanly, not handed to
  # python to fail with a stack trace (or, worse, a non-numeric value coerced oddly).
  if [[ "$port" != <-> ]] || ((port < 1 || port > 65535)); then
    _core_err "serve: port must be 1-65535 (got '$port')"
    _core_usage "serve [-l|--local] [port]"
    return 1
  fi
  _core_have python3 || {
    _core_errbox "serve: requires python3" \
      "why: serve runs Python's built-in http.server" \
      "fix: install python3, then retry"
    return 1
  }
  # Defensive (U7): a port already in use surfaces from http.server as a raw Python
  # traceback. Probe a bind FIRST — with SO_REUSEADDR set exactly as http.server does, so
  # the probe agrees with the real bind — and fail in Core's voice instead. Runs only after
  # the port/flags validated above, so a scripted bad-input run never reaches it.
  local bind_host="0.0.0.0"
  ((local_only)) && bind_host="127.0.0.1"
  if ! python3 - "$bind_host" "$port" 2>/dev/null <<'PY'
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind((sys.argv[1], int(sys.argv[2]))); s.close()
except OSError:
    sys.exit(1)
PY
  then
    _core_err "serve: port ${port} is already in use on ${bind_host}"
    _core_hint "pick another port, e.g. serve $((port + 1))"
    return 1
  fi
  # --local: bind loopback only — nothing leaves this host. No exposure warning, no
  # LAN/tunnel URL discovery (none would be reachable anyway).
  if ((local_only)); then
    echo "serving $(pwd) on 127.0.0.1:${port}  (local only — Ctrl-C to stop)"
    echo "  → http://127.0.0.1:${port}/   (localhost)"
    python3 -m http.server --bind 127.0.0.1 "$port"
    return
  fi
  # Default: bind ALL interfaces on purpose (ad-hoc file transfer), so say so plainly —
  # on an untrusted network the CWD is reachable by anyone who can route to this host
  # until you Ctrl-C. Use `serve -l` to keep it to loopback.
  _core_warn "serve binds 0.0.0.0:${port} — the CWD is exposed on every interface (use -l for loopback only)"
  echo "serving $(pwd) on port ${port}  (Ctrl-C to stop)"
  # Advertise the reachable tunnel/LAN URLs. The platform-specific IP discovery lives in
  # _serve_advertise (hermetically testable, no blocking server): it prints the URL lines
  # and returns the best QR target in $REPLY.
  local qr_url
  _serve_advertise "$port"
  qr_url="$REPLY"
  # Scan-to-open: this server's whole point is ad-hoc transfer to another device, so when
  # qrencode is present render the reachable URL as a QR — point a phone at it, no typing
  # a LAN IP. Graceful skip when qrencode is absent (just the URLs above), like every
  # other optional-tool path in Core.
  if [[ -n "$qr_url" ]] && _core_have qrencode; then
    echo "  scan to open ${qr_url} :"
    qrencode -t ANSIUTF8 "$qr_url"
  fi
  python3 -m http.server "$port"
}

# genpw — print a random password. Portable by design: prefers openssl (present on
# essentially every box), falls back to /dev/urandom so it still works on a bare
# rescue shell with nothing installed. Default length 16; pass a length to override.
#   genpw          # 16-char alnum password
#   genpw 32       # 32-char
genpw() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "genpw [length]" "random alphanumeric password (default 16) via openssl, /dev/urandom fallback"; return 0; }
  local len="${1:-16}"
  # Reject a non-numeric / zero length cleanly in Core's voice rather than emitting an
  # empty string (head -c 0) that looks like success.
  if [[ "$len" != <-> ]] || ((len < 1)); then
    _core_err "genpw: length must be a positive integer (got '$len')"
    _core_usage "genpw [length]"
    return 1
  fi
  if _core_have openssl; then
    # base64 then strip to alnum, so the byte count we draw comfortably exceeds $len.
    openssl rand -base64 $((len * 2)) | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c "$len"
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$len"
  fi
  echo
}

# pullall — fast-update every git repo under a parent directory, IN PARALLEL. For
# each repo it prunes deleted remote branches, stashes any uncommitted (tracked)
# changes, switches to the repo's trunk (main/master/trunk/… — auto-detected, NOT
# assumed to be "main"), fast-forwards it, then pops your stash back. A summary card
# tallies updated / warnings / failed / pruned at the end.
#
#   pullall            # repos under $PULLALL_DIR (or the CWD if it's unset)
#   pullall ~/code     # repos under an explicit directory
#
# The parent directory is deliberately NOT hard-coded — Core is identical on every
# machine, but /Users/you/projects vs /home/you/code is not. Pass it as an argument,
# or pin it once in your ~/.zshrc.local (the machine-local layer Core loads last):
#   export PULLALL_DIR="$HOME/projects"
# Parallelism defaults to 10 workers; override with PULLALL_JOBS.
#
# Heads-up: this rewrites working state across MANY repos. It is stash-safe (your
# uncommitted tracked changes are popped back, and a pop conflict is reported, never
# swallowed), but a repo you left on a feature branch ends up on its trunk — run it
# where that's what you want. The pull is --ff-only, so a diverged trunk is reported
# as a failure rather than silently merged.
# Portability: needs `xargs -P` (parallel). Present on macOS/BSD and GNU findutils; a
# stripped busybox/Alpine xargs without parallel support will reject -P — set
# PULLALL_JOBS=1 there, or install findutils.
pullall() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "pullall [dir]" "pull every git repo under a dir in parallel (prunes, stashes, fast-forwards trunk)"; return 0; }

  local parent="${1:-${PULLALL_DIR:-$PWD}}"
  if [[ ! -d "$parent" ]]; then
    _core_err "pullall: not a directory: $parent"
    _core_hint "pass a directory, or set PULLALL_DIR (e.g. in ~/.zshrc.local)"
    _core_usage "pullall [dir]"
    return 1
  fi
  local jobs="${PULLALL_JOBS:-10}"
  if [[ "$jobs" != <-> ]] || ((jobs < 1)); then
    _core_err "pullall: PULLALL_JOBS must be a positive integer (got '$jobs')"
    return 1
  fi

  # Colour is decided ONCE here (TTY- and NO_COLOR-aware) and handed to the workers
  # as exported vars. The workers run under /bin/sh, where Core's _core_* helpers
  # don't exist — so they print with printf and these pre-resolved escapes (real ESC
  # bytes, or empty when colour is off). `local -x` exports to the child processes
  # AND restores the caller's environment when pullall returns.
  local -x G='' Y='' R='' NC=''
  if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' NC=$'\e[0m'
  fi
  local bold='' rst=''
  [[ -n "$NC" ]] && { bold=$'\e[1m' rst=$'\e[0m'; }

  print -r -- "${bold}🔄 Updating git repos under ${parent} …${rst}"
  print

  # Each worker receives its repo path as $1 — passed POSITIONALLY, not interpolated
  # into the script text — so a path with spaces, quotes, or shell metacharacters
  # can't break the worker or inject a command. -print0/-0 keep odd names intact; -P
  # runs $jobs workers at once. Output is captured (not streamed) so we can tally it.
  local output
  output=$(find "$parent" -mindepth 1 -maxdepth 1 -type d -print0 \
    | xargs -0 -I {} -P "$jobs" sh -c '
      repo="$1"
      cd "$repo" 2>/dev/null || exit 0
      [ -e .git ] || exit 0            # plain clone (dir) or worktree/submodule (file)
      name=$(basename "$repo")

      # 1. prune deleted remote branches — report only when something was actually pruned
      prune=$(git fetch --prune 2>&1)
      if printf "%s\n" "$prune" | grep -q "\[deleted\]"; then
        printf "%s\n" "$prune" | grep "\[deleted\]" | while IFS= read -r line; do
          printf "%s\n" "${Y}🧹 ${name}: ${line}${NC}"
        done
      fi

      # 2. stash uncommitted (tracked) changes so checkout/pull cannot be blocked by them
      stashed=0
      if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        git stash push -m "Auto-stash by pullall" >/dev/null 2>&1 && stashed=1
      fi

      # 3. resolve the trunk for THIS repo — origin/HEAD if set, else the first of
      #    main/master/trunk that exists, else fall back to the current branch.
      trunk=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
      trunk=${trunk#origin/}
      if [ -z "$trunk" ]; then
        for b in main master trunk; do
          if git show-ref -q --verify "refs/heads/$b"; then trunk="$b"; break; fi
        done
      fi
      [ -z "$trunk" ] && trunk=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

      # 4. switch to the trunk
      if ! git checkout "$trunk" >/dev/null 2>&1; then
        printf "%s\n" "${R}❌ ${name}: could not switch to ${trunk}${NC}"
        [ "$stashed" -eq 1 ] && git stash pop >/dev/null 2>&1
        exit 0
      fi

      # 5. fast-forward the trunk
      git pull --ff-only origin "$trunk" >/dev/null 2>&1
      pull=$?

      # 6. restore the stash (report a pop conflict instead of leaving it on the stack silently).
      #    The wording is gated on $pull: if the fast-forward ALSO failed, the trunk was not
      #    updated, so dont claim it was — that combined failure is a ❌, not a ⚠️.
      if [ "$stashed" -eq 1 ]; then
        if ! git stash pop >/dev/null 2>&1; then
          if [ "$pull" -eq 0 ]; then
            printf "%s\n" "${Y}⚠️  ${name}: updated ${trunk}, but a conflict blocked restoring your local changes${NC}"
          else
            printf "%s\n" "${R}❌ ${name}: pull failed AND a conflict blocked restoring your local changes${NC}"
          fi
          exit 0
        fi
      fi

      # 7. per-repo status line
      if [ "$pull" -eq 0 ]; then
        if [ "$stashed" -eq 1 ]; then
          printf "%s\n" "${G}✅ ${name}: updated ${trunk} & restored your changes${NC}"
        else
          printf "%s\n" "${G}✅ ${name}: updated ${trunk}${NC}"
        fi
      else
        printf "%s\n" "${R}❌ ${name}: network or non-fast-forward error during pull${NC}"
      fi
    ' _ {})

  print -r -- "$output"

  # Tally the emoji markers in ONE awk pass instead of four grep -c scans of the same
  # buffer. index() is byte-based (locale-independent for the multibyte glyphs) and, like
  # grep -c, counts matching LINES; awk always prints four integers, so the arithmetic
  # below stays safe even when $output is empty (0 0 0 0).
  local ok warn fail pruned
  read -r ok warn fail pruned <<<"$(printf '%s\n' "$output" | awk '
    index($0,"✅"){o++} index($0,"⚠️"){w++} index($0,"❌"){f++} index($0,"🧹"){p++}
    END{printf "%d %d %d %d\n", o, w, f, p}')"

  print
  print -r -- "${bold}📊 pullall summary${rst}"
  print -r -- "  ${G}updated:${NC}  $ok"
  ((warn > 0)) && print -r -- "  ${Y}warnings:${NC} $warn"
  print -r -- "  ${R}failed:${NC}   $fail"
  ((pruned > 0)) && print -r -- "  ${Y}pruned:${NC}   $pruned remote branch(es)"

  # A clean run returns 0; any ❌ makes pullall non-zero so it composes in scripts.
  return $((fail > 0))
}

# core-help (alias: cheat) — a scannable cheat sheet of what Core actually gives
# you on this box: the shell functions, the custom keybindings, and the update /
# maintenance verbs. Static + instant — the discoverability surface for the Core
# layer (the shell counterpart to which-key in Neovim). Rows are "key|description"
# pairs grouped under "§heading" markers, so the list stays trivially editable.
# Public verb: render the sheet, paging it through $PAGER when it's taller than the
# terminal (the full sheet easily overflows a tmux split). Paging only kicks in on a real
# TTY; a pipe/redirect/the unit tests take the direct render path below — byte-identical
# to before — so nothing captured changes. Colour is FORCED on for the captured render
# (_core_page's pipe would otherwise look non-TTY and blank it); _core_page then prints or
# pages. A filtered/short sheet that fits one screen is printed inline (less -F).
core-help() {
  emulate -L zsh
  if [[ -t 1 && -z ${CORE_NO_PAGER:-} ]]; then
    local _out
    _out="$(_CORE_FORCE_COLOR=1 _core_help_render "$@")"
    local _rc=$?
    _core_page "$_out"
    return $_rc
  fi
  _core_help_render "$@"
}
_core_help_render() {
  emulate -L zsh
  _core_wants_help "$1" && { _core_help "core-help [filter]" "scannable cheat sheet of Core's functions, keys & maintenance; pass a word to filter"; return 0; }
  # Optional case-insensitive filter: `core-help serve` jumps straight to the matching
  # rows instead of scanning the whole sheet (U4). Empty → the full grouped cheat sheet.
  local filter="${(L)1:-}"
  # Raw ANSI (not prompt %F) + `print -r` below, so a literal backslash in a key
  # (Ctrl-\) survives — print -P would consume it as an escape. Colour only on a
  # TTY; piped/redirected output stays plain.
  # Accent + muted come from ui.zsh's canonical palette ($_CORE_C_ACCENT/$_CORE_C_MUTED
  # — the one place $COLORTERM is interpreted, truecolor-aware), so the cheat sheet, the
  # update nudge, and core-doctor share one branded blue instead of three hand-rolled
  # copies. The TTY/NO_COLOR blanking below still applies locally.
  local title="${_CORE_C_ACCENT:-}" dc="${_CORE_C_MUTED:-}"
  local te=$'\e[0m' kc=$'\e[36m' ke=$'\e[0m' de=$'\e[0m'
  # Blank colour off a non-TTY UNLESS the paging wrapper forced it on (_CORE_FORCE_COLOR),
  # and always off under NO_COLOR — so the captured-for-paging render keeps its colour.
  if { [[ ! -t 1 ]] && [[ -z ${_CORE_FORCE_COLOR:-} ]]; } || [[ -n ${NO_COLOR:-} ]]; then title='' te='' kc='' ke='' dc='' de=''; fi
  # Rows are "key|description" or "key|description|requires" — the optional third
  # field names a command this entry NEEDS. When it's absent on THIS box the row is
  # dimmed and tagged "— needs <cmd>", so the cheat sheet reflects what actually works
  # here instead of advertising widgets/verbs that would no-op (fzf/atuin/sesh/zoxide
  # aren't on every box). Verbs that degrade gracefully (extract, up, maint) carry no
  # requirement — they always work.
  local -a rows=(
    "§navigation & files"
    "mkcd <dir>|make a directory and cd into it"
    "cdup [n]|climb n directories (default 1)"
    "extract <archive>|unpack any archive (tar/zip/7z/rar/…)"
    "mkbak <file>|timestamped .bak copy before you edit"
    "fcd|fuzzy-cd into any subdirectory|fzf"
    "serve [-l] [port]|HTTP server in the CWD (-l = loopback only); prints reachable URLs|python3"
    "genpw [length]|random alphanumeric password (default 16; openssl, urandom fallback)"
    "please|re-run your last command with sudo (previews + confirms first)"
    "§search"
    "fif <text>|find text inside files (rg + fzf + preview)|fzf"
    "fbr|fuzzy git-branch checkout|fzf"
    "§git (most-used — full OMZ-style set in git.zsh)"
    "g <args>|git"
    "gst / gss|status / short status"
    "ga / gaa|stage file(s) / stage all"
    "gc / gcm <msg>|commit (verbose) / commit -m"
    "gco / gcb <branch>|checkout / checkout -b"
    "gp / gl|push / pull"
    "gpf|push --force-with-lease (safe force)"
    "gaf / grf / grsf|fuzzy stage / restore / unstage (multi-select)|fzf"
    "gd / gds|diff / diff --staged"
    "glog|graph log (oneline, decorated)"
    "grbm|rebase onto the trunk branch"
    "pullall [dir]|pull every git repo under a dir in parallel (stashes, fast-forwards trunk)"
    "§keybindings"
    "Ctrl-T|file picker → insert path at cursor|fzf"
    "Ctrl-R|history search|fzf"
    "Ctrl-E|Atuin history TUI|atuin"
    "Ctrl-G|session picker (sesh)|sesh"
    "Alt-Z|zoxide project jump|zoxide"
    "Ctrl-\\|toggle autosuggestions"
    "§updates & maintenance"
    "up [-y]|apply package updates (interactive; confirms first)"
    "update-check|refresh the 'updates available' nudge"
    "gsync|push this repo's vendored core/ subtree back upstream to dotfiles-core"
    "maint-install [HH:MM]|schedule the daily safe-update job"
    "maint-run|run daily maintenance now"
    "maint-log [-f]|view (or follow) the maintenance log"
    "maint-status|when the job next runs / is it enabled"
    "maint-uninstall|remove the scheduled maintenance job"
  )
  local ver=""
  [[ -r "$_CORE_VERSION_FILE" ]] && ver=" v$(<"$_CORE_VERSION_FILE")"
  if [[ -n "$filter" ]]; then
    print -r -- "${title}dotfiles Core${ver} — cheat sheet${te} ${dc}(filter: ${filter})${de}"
  else
    print -r -- "${title}dotfiles Core${ver} — cheat sheet${te} ${dc}(run \`core-help\` anytime · \`core-help <word>\` to filter)${de}"
  fi
  # Key column is derived from the WIDEST key, not a fixed 22 — so alignment stays
  # correct if a longer verb is ever added (the old hard-coded width silently broke
  # alignment past 22 chars) and isn't padded wider than the content needs. On a narrow
  # terminal, clamp it (and truncate an over-long key) so it can't swallow the whole
  # line and leave no room for the description.
  local line key desc req kw=0
  local -a parts
  for line in "${rows[@]}"; do
    [[ "$line" == §* ]] && continue
    key="${line%%|*}"
    ((${#key} > kw)) && kw=${#key}
  done
  local cols=${COLUMNS:-80}
  ((kw > cols - 22)) && kw=$((cols - 22)) # keep room for a readable description
  ((kw < 6)) && kw=6
  local matched=0 cur_section=""
  for line in "${rows[@]}"; do
    if [[ "$line" == §* ]]; then
      # Track the section a row belongs to (lowercased) so a filter can match by SECTION
      # name too — e.g. `core-help keybindings` surfaces that whole group even though the
      # word never appears in any row's key/desc. (Completion offers these section terms.)
      cur_section="${(L)${line#§}}"
      # Section headers print only in the UNFILTERED view — a filter wants the matching
      # rows, not the scaffolding around them.
      [[ -n "$filter" ]] && continue
      print -r -- "${title}${line#§}${te}"
    else
      parts=("${(@s:|:)line}")
      key="${parts[1]}"
      desc="${parts[2]}"
      req="${parts[3]:-}" # optional: a command this row needs to actually work
      # Filtered: skip rows whose key+description AND owning section don't contain the term
      # (case-insensitive) — so both a verb term (`serve`) and a section term (`navigation`)
      # narrow correctly, and a completion-suggested section name never yields "no matches".
      [[ -n "$filter" && "${(L)key} ${(L)desc}" != *"$filter"* && "$cur_section" != *"$filter"* ]] && continue
      matched=1
      key="${key[1,kw]}"  # truncate an over-long key to the (possibly clamped) column
      if [[ -n "$req" ]] && ! _core_have "$req"; then
        # Unavailable on this box — dim the whole row and name what to install.
        print -r -- "  ${dc}${(r:$kw:)key} ${desc} — needs ${req}${de}"
      else
        print -r -- "  ${kc}${(r:$kw:)key}${ke} ${dc}${desc}${de}"
      fi
    fi
  done
  if [[ -n "$filter" ]]; then
    ((matched)) || print -r -- "  ${dc}no entries match '${filter}' — run \`core-help\` for the full sheet${de}"
    return 0
  fi
  print -r -- "${dc}  1Password: opsecret · openv · optoken · opssh    health: core-doctor · version: core-version${de}"
  print -r -- "${dc}  front door: core <help|doctor|version|update>  (run \`core\` for this sheet anytime)${de}"
}
alias cheat='core-help'

# ── command-not-found handler (U1) ────────────────────────────────────────────
# A mistyped command otherwise gets zsh's terse default (or, on Debian, the distro's
# package suggester). Replace it with a Core-voice miss that (a) suggests the nearest
# Core verb/alias when it's a near typo (`extarct` → extract) and (b) offers an install
# line via the package manager update.zsh already detects — turning a dead end into a
# next step. Defined ONLY in an interactive shell: the unit harness sources this file
# non-interactively (`zsh -fc`) and must NOT install a global handler. Opt out with
# CORE_CNF_ENABLED=0 (e.g. an OS layer that prefers the distro's own suggester).
: "${CORE_CNF_ENABLED:=1}"
if [[ $- == *i* ]] && ((CORE_CNF_ENABLED)); then
  command_not_found_handler() {
    emulate -L zsh
    local cmd="$1"
    _core_err "command not found: ${cmd}"
    # Did-you-mean against Core's own verbs — where typos land most often.
    local -a _verbs=(
      core mkcd cdup extract mkbak fcd serve genpw fif fbr up update-check
      maint-install maint-run maint-log maint-status maint-uninstall
      core-help core-doctor core-version
      opsecret openv optoken opssh
    )
    # Also weigh this shell's defined ALIASES — the most-typed commands (the g* git set,
    # ll/la, lg, …) live there, so a near miss like `gts`→`gst` or `gco`→`gci` gets caught
    # too, not just the Core verbs. ${(k)aliases} is the alias-name set in the live shell.
    _verbs+=(${(k)aliases})
    local _sug
    _sug="$(_core_suggest "$cmd" $_verbs)"
    if [[ -n "$_sug" ]]; then
      _core_hint "did you mean ${_sug}?"
    elif (($+functions[_pkgup_mgr])); then
      # No near Core verb — offer an install path for THIS box's package manager.
      local _pfx
      _pfx="$(_core_install_prefix "$(_pkgup_mgr)")" && _core_hint "try: ${_pfx} ${cmd}"
    fi
    return 127
  }
fi
