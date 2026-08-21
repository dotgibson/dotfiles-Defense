#!/usr/bin/env bash
# .claude/hooks/session-start.sh — provision the Core gate toolchain for
# Claude Code on the web, so `make audit` runs FOR REAL in a remote session.
# ──────────────────────────────────────────────────────────────────────────────
# WHY THIS EXISTS: a fresh remote container ships bash + python only, so
# `scripts/audit-core.sh` SKIPS every meaningful gate (zsh -n, shellcheck, the
# behavioral suite, luacheck, markdownlint, actionlint) and still reports "audit
# OK" — a FALSE green. This installs exactly the linters CI installs, at the SAME
# pins (scripts/tool-versions.env is the single source), so an agent session can
# verify changes the way CI does instead of trusting a green-because-absent run.
#
# Mirrors .github/workflows/ci.yml's install steps. Best-effort + idempotent +
# non-interactive: every tool is guarded by `have`, so a re-run (or a cached
# container that already has them) is a fast no-op, and one tool failing never
# blocks the session — a doctor summary at the end shows what's present.
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# Web/remote sessions only. On a local box you bring your own toolchain (or run
# `make setup`); this hook must never reach for sudo/apt on a developer's laptop.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$ROOT" || exit 0

# Single source of truth for the pinned versions — the same file CI loads into
# $GITHUB_ENV and `make setup` reads. Bump a pin there and this follows.
if [ -r scripts/tool-versions.env ]; then
  set -a
  # shellcheck disable=SC1091
  . scripts/tool-versions.env
  set +a
fi

have() { command -v "$1" >/dev/null 2>&1; }
log() { printf '[session-start] %s\n' "$*"; }
# Prefer sudo when not already root; degrade to bare (container often runs as root).
SUDO=""
[ "$(id -u)" -ne 0 ] && have sudo && SUDO="sudo"

# ── apt base packages (zsh, hyperfine, luarocks + lua dev headers) ────────────
# Some prebaked images carry third-party PPAs with expired/forbidden signing that
# abort `apt-get update` wholesale; we only need the base Ubuntu repos, so on a
# failed update we move non-Ubuntu source lists aside and retry (idempotent).
apt_update() {
  $SUDO apt-get update -qq 2>/dev/null && return 0
  log "apt-get update failed — disabling third-party sources, retrying"
  $SUDO mkdir -p /etc/apt/sources.list.d.disabled 2>/dev/null || true
  for f in /etc/apt/sources.list.d/*; do
    [ -e "$f" ] || continue
    case "${f##*/}" in
    ubuntu.sources | ubuntu.list) ;;
    *) $SUDO mv "$f" /etc/apt/sources.list.d.disabled/ 2>/dev/null || true ;;
    esac
  done
  $SUDO apt-get update -qq 2>/dev/null || true
}

if ! have zsh || ! have hyperfine || ! have luarocks; then
  if have apt-get; then
    apt_update
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq --no-install-recommends \
      zsh hyperfine luarocks lua5.4 liblua5.4-dev >/dev/null 2>&1 ||
      log "apt install hit issues (some tools may be missing — see doctor below)"
  else
    log "no apt-get — skipping zsh/hyperfine/luarocks (install them by hand)"
  fi
fi

# Trust the system CA for tools that bundle their own (npm) — remote envs often
# sit behind a TLS-terminating proxy whose root is only in the OS trust store.
CA=/etc/ssl/certs/ca-certificates.crt
[ -r "$CA" ] && export NODE_EXTRA_CA_CERTS="$CA"

# Helper: install a pinned release tarball to /usr/local/bin (like CI does).
# Downloads to a file, VERIFIES the pinned SHA-256 (fail closed — no checksum, no
# install), THEN extracts. Mirrors setup-core-tools/action.yml: the tarball must
# never be piped straight into tar unverified (a MITM'd asset would run as the gate).
install_tarball() { # install_tarball <bin> <url> <sha256> <tar-flags> [member]
  local bin="$1" url="$2" sha="$3" flags="$4" member="${5:-}"
  have "$bin" && return 0
  local tmp f
  tmp="$(mktemp -d)"
  f="$tmp/${url##*/}"
  if [ -z "$sha" ]; then
    log "no pinned SHA-256 for $bin — refusing unverified install (check scripts/tool-versions.env)"
  elif ! curl -fsSL -o "$f" "$url"; then
    log "could not download $bin from $url"
  elif ! echo "${sha}  ${f}" | sha256sum -c - >/dev/null 2>&1; then
    log "SHA-256 mismatch for $bin — refusing to install (expected ${sha})"
  elif tar "$flags" -f "$f" -C "$tmp" ${member:+"$member"} 2>/dev/null; then
    local found
    found="$(find "$tmp" -type f -name "$bin" 2>/dev/null | head -n1)"
    [ -n "$found" ] && $SUDO install -m755 "$found" "/usr/local/bin/$bin" 2>/dev/null
  fi
  rm -rf "$tmp"
  have "$bin" || log "could not install $bin from $url"
}

# ── shellcheck (pinned + verified) ────────────────────────────────────────────
[ -n "${SHELLCHECK_VERSION:-}" ] && install_tarball shellcheck \
  "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" "${SHELLCHECK_SHA256:-}" -xJ

# ── actionlint (pinned + verified) ────────────────────────────────────────────
[ -n "${ACTIONLINT_VERSION:-}" ] && install_tarball actionlint \
  "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" "${ACTIONLINT_SHA256:-}" -xz actionlint

# ── gitleaks (pinned + verified) — the audit's secrets section runs `gitleaks dir`, so
# without this a remote session's secrets gate would SKIP: a "green because absent" for
# secrets, the exact false-green this hook exists to prevent. Same tarball pattern above. ──
[ -n "${GITLEAKS_VERSION:-}" ] && install_tarball gitleaks \
  "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" "${GITLEAKS_SHA256:-}" -xz gitleaks

# ── neovim (pinned + verified) — extracted to /opt, symlinked onto PATH (CI's Linux path).
# Verify the pinned SHA-256 before unpacking as root — same fail-closed rule as above. ──
if [ -n "${NVIM_VERSION:-}" ] && ! have nvim; then
  nvim_tmp="$(mktemp -d)"
  nvim_tgz="$nvim_tmp/nvim-linux-x86_64.tar.gz"
  if [ -z "${NVIM_SHA256:-}" ]; then
    log "no pinned SHA-256 for neovim — refusing unverified install (check scripts/tool-versions.env)"
  elif ! curl -fsSL -o "$nvim_tgz" "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-x86_64.tar.gz"; then
    log "could not download neovim"
  elif ! echo "${NVIM_SHA256}  ${nvim_tgz}" | sha256sum -c - >/dev/null 2>&1; then
    log "SHA-256 mismatch for neovim — refusing to install (expected ${NVIM_SHA256})"
  elif $SUDO tar -xz -f "$nvim_tgz" -C /opt 2>/dev/null; then
    $SUDO ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim 2>/dev/null
  fi
  rm -rf "$nvim_tmp"
  have nvim || log "could not install neovim"
fi

# ── luacheck (pinned, via luarocks against Lua 5.4) ───────────────────────────
if [ -n "${LUACHECK_VERSION:-}" ] && ! have luacheck && have luarocks; then
  $SUDO luarocks --lua-version 5.4 install luacheck "${LUACHECK_VERSION}" >/dev/null 2>&1 ||
    log "luacheck install via luarocks failed (needs lua5.4 + liblua5.4-dev)"
fi

# ── markdownlint-cli2 (pinned, via npm) ───────────────────────────────────────
# This is the gate that SILENTLY SKIPPED most often in remote sessions (npm's global
# bin frequently lands off PATH), and markdown IS the deliverable on these showcase
# repos — so missing it is the exact "audit OK because absent" false-green this hook
# exists to kill. Resolve the bin from npm ITSELF (prefix/bin) rather than guessing
# with find, then fall back to a find sweep across the layouts the prefix probe misses.
if [ -n "${MARKDOWNLINT_VERSION:-}" ] && ! have markdownlint-cli2 && have npm; then
  $SUDO --preserve-env=NODE_EXTRA_CA_CERTS npm install -g "markdownlint-cli2@${MARKDOWNLINT_VERSION}" >/dev/null 2>&1 || true
  # 1. Ask npm where its global bin is (authoritative) and symlink onto PATH.
  if ! have markdownlint-cli2; then
    for npm_prefix in "$(npm prefix -g 2>/dev/null)" "$(npm config get prefix 2>/dev/null)"; do
      [ -n "$npm_prefix" ] || continue
      if [ -x "$npm_prefix/bin/markdownlint-cli2" ]; then
        $SUDO ln -sf "$npm_prefix/bin/markdownlint-cli2" /usr/local/bin/markdownlint-cli2 2>/dev/null
        break
      fi
    done
  fi
  # 2. Last resort: sweep the common global-install roots (covers nvm/volta/npm-global).
  if ! have markdownlint-cli2; then
    mdl="$(find /opt /usr/local /usr/lib "${HOME}/.npm-global" -name markdownlint-cli2 -type f 2>/dev/null | head -n1)"
    [ -n "$mdl" ] && $SUDO ln -sf "$mdl" /usr/local/bin/markdownlint-cli2 2>/dev/null
  fi
  have markdownlint-cli2 || log "could not install markdownlint-cli2 — the markdown gate WILL SKIP"
fi

# ── PyYAML (the audit's YAML parse section imports it; tomllib/json are stdlib) ─
if have python3 && ! python3 -c 'import yaml' 2>/dev/null; then
  python3 -m pip install --quiet --break-system-packages pyyaml >/dev/null 2>&1 || true
fi

# ── doctor: report what the audit will actually be able to run ────────────────
# An absent tool means `make audit` SKIPS that gate while still printing "audit OK" —
# a false green. So count the misses and warn LOUDLY at the end: a remote green is only
# trustworthy if you know which gates actually ran. (python3 ships in the base image and
# zsh/shellcheck/gitleaks are the load-bearing ones; nvim/luacheck only matter for nvim
# changes, but we still surface them so the picture is complete.)
log "toolchain ready — gate availability:"
missing=0
for t in zsh shellcheck luacheck nvim markdownlint-cli2 actionlint gitleaks hyperfine python3; do
  if have "$t"; then
    printf '  ✓ %s\n' "$t"
  else
    printf '  – %s (gate will skip)\n' "$t"
    missing=$((missing + 1))
  fi
done
if [ "$missing" -gt 0 ]; then
  log "WARNING: $missing gate tool(s) unavailable — \`make audit\` may report OK while SKIPPING them; treat a green run as partial until these resolve"
fi
log "run \`make audit\` to verify Core end-to-end"
exit 0
