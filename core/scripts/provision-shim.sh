#!/usr/bin/env sh
# scripts/provision-shim.sh — build a PATH shim that neuters provisioning side effects.
# ──────────────────────────────────────────────────────────────────────────────
# WHY THIS EXISTS: `--links-only` returns before provision() is entered, so package
# installation, retries, upstream installers, repo/key setup and every failure path around
# them are executed by NO CI job anywhere in the fleet (#575, and #461/#512 before it). One
# bug class has already shipped green twice on the back of that: a RETURN trap leaked from
# verified_install into provision()'s frame and aborted every fresh-box run AFTER installing
# everything and BEFORE wire_links (dotgibson/dotfiles-Debian#2).
#
# WHAT IT BUYS, AND WHAT IT DOES NOT. Most of that bug class is CONTROL FLOW, not I/O — a
# leaked trap, a bare `refresh` aborting under `set -e`, an unchecked GPG import, a tool
# assumed present on a minimal image. Running provision() with the package managers and
# downloaders replaced by logging no-ops executes those paths without installing anything or
# touching the network. It asserts that provision() RUNS AND RETURNS, not that provisioning
# WORKS: no package is really installed, so nothing here can tell you a package name is
# wrong or a repo key is bad. That remains the job of a real (periodic) bootstrap.
#
# HONEST LIMITS, so a green run is not over-read:
#   * a stub returns 0, so a code path that only executes on package-manager FAILURE is
#     still unexercised — the shim proves the happy path returns, not the sad one
#   * a stub writes no file, so a step that downloads and then unpacks will not find its
#     asset; those steps must tolerate it, or the repo is not shim-clean yet
#   * anything invoked by absolute path (/usr/bin/apt-get) bypasses the shim entirely
#
# It prints the shim directory on stdout and nothing else, so a caller can do:
#     PATH="$(sh core/scripts/provision-shim.sh):$PATH"
#
# POSIX sh, not bash: it runs inside whatever the distro image ships before any prep has
# necessarily installed bash (alpine's default shell is ash).
# ──────────────────────────────────────────────────────────────────────────────
set -eu

BIN="${PROVISION_SHIM_DIR:-${TMPDIR:-/tmp}/provision-shim}"
LOG="${PROVISION_SHIM_LOG:-$BIN/../provision-shim.log}"
mkdir -p "$BIN"
: >"$LOG"

# The commands a provision() reaches for. Package managers, privilege escalation, and the
# downloaders that fetch out-of-band assets. `git` is deliberately ABSENT: bootstraps clone
# real things (tpm) that the caller pre-seeds instead, and stubbing git would mask wiring
# bugs this job should still catch.
for cmd in \
  apt-get apt apt-key add-apt-repository dpkg debconf-set-selections \
  dnf yum rpm \
  pacman paru yay \
  zypper \
  apk \
  emerge eselect layman \
  brew \
  snap flatpak \
  curl wget \
  gpg gpg2 gpgconf \
  systemctl update-alternatives unattended-upgrade \
  pipx go cargo npm; do
  cat >"$BIN/$cmd" <<STUB
#!/usr/bin/env sh
# provision-shim: logged no-op. See core/scripts/provision-shim.sh.
printf '%s %s\n' "$cmd" "\$*" >>"$LOG"
exit 0
STUB
  chmod +x "$BIN/$cmd"
done

# sudo/doas are special: swallowing them would skip the command they wrap, hiding whatever
# provision() actually meant to run. Re-exec the tail instead, so `sudo apt-get install x`
# still reaches the apt-get stub above and still gets logged.
for cmd in sudo doas; do
  cat >"$BIN/$cmd" <<'STUB'
#!/usr/bin/env sh
# provision-shim: drop the escalation, run the command. See core/scripts/provision-shim.sh.
while [ $# -gt 0 ]; do
  case "$1" in
    -n | -E | -H | -k) shift ;;
    -u) shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
[ $# -eq 0 ] && exit 0
exec "$@"
STUB
  chmod +x "$BIN/$cmd"
done

printf '%s\n' "$BIN"
