#!/usr/bin/env bash
# scripts/test-core.sh
# ──────────────────────────────────────────────────────────────────────────────
# BEHAVIORAL tests for Core — the layer scripts/audit-core.sh's static analysis can't
# reach. audit-core.sh proves the modules PARSE (zsh -n) and that the manifest and
# exec-bits are consistent; this proves the modules actually LOAD TOGETHER in the
# canonical order and that the pure shell functions DO what they claim. A defect
# here passes every per-file `zsh -n` cleanly and still fans out to 9 OS repos —
# which is exactly the gap this file closes.
#
# Two sections, both zsh-gated and degrading gracefully (mirrors audit-core.sh):
#   A. load-order smoke test  — source every zsh module in the README's canonical
#                               order inside ONE hermetic interactive zsh and
#                               assert the whole chain loads (catches cross-module
#                               contract breakage: a module that needs a var/fn an
#                               EARLIER module must define first).
#   B. function unit tests    — exercise the pure functions in functions.zsh
#                               (mkcd / cdup / mkbak / extract) and assert behavior.
#
# Hermetic: a throwaway $HOME/$ZDOTDIR/$XDG_CACHE_HOME is used, and the plugin dirs
# are pre-seeded EMPTY so plugins.zsh's first-run `git clone` is skipped — the test
# needs no network and writes nothing outside its tempdir.
#
# Graceful degradation: with no zsh installed (a bare box), both sections SKIP and
# the script exits 0 — identical philosophy to audit-core.sh, so this is safe to
# call from CI, pre-commit, and a developer's laptop alike.
#
# Usage:
#   ./scripts/test-core.sh            # run every section
#   ./scripts/test-core.sh --quiet    # only print SKIP/FAIL + the summary
# ──────────────────────────────────────────────────────────────────────────────

# This harness embeds zsh code as single-quoted literals on purpose: the `$…`
# inside them must be expanded by the zsh CHILD, not by this bash parent. SC2016
# (un-expanded `$` in single quotes) is therefore a false positive file-wide.
# shellcheck disable=SC2016
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

QUIET=0
JSON=0 # --json: machine-readable summary on stdout (implies quiet); mirrors audit-core.sh
# Scope mirrors audit-core.sh: gate the slow AREA-specific sections so a per-area run
# does less. FAIL-CLOSED default (no --scope → both areas run). The cross-cutting,
# pure-bash sections (clipboard ladder, CI-classifier) ALWAYS run — they are fast and
# guard runtime artifacts shared by every area. audit-core.sh passes the classifier's
# verdict here; a bare `./scripts/test-core.sh` runs everything.
SCOPE_SHELL=1
SCOPE_NVIM=1
# Shared palette + pass/skip/fail/hdr/have + _set_scope + _seed_plugin_dirs (one
# definition for every gate script). Sourced HERE — before the arg loop calls _set_scope
# — and after QUIET is set so the lib's `: "${QUIET:=0}"` preserves it.
# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

# Same flag contract as audit-core.sh: parse EVERY arg and reject an unknown option or
# a stray extra operand instead of ignoring it; -h/--help prints usage. (audit-core.sh
# invokes this with --quiet/--scope or nothing.)
while (($#)); do
  case "$1" in
  -q | --quiet) QUIET=1 ;;
  --scope)
    # Require an explicit value (mirrors audit-core.sh): `--scope --quiet` must not
    # eat the next flag as the scope list.
    if (($# < 2)) || [[ "$2" == -* ]]; then
      printf 'test-core.sh: --scope requires a value (shell,nvim|all|none)\n' >&2
      printf 'try: test-core.sh --help\n' >&2
      exit 2
    fi
    shift
    _set_scope "$1"
    ;;
  --scope=*) _set_scope "${1#*=}" ;;
  --json) JSON=1 QUIET=1 CORE_JSON=1 && export CORE_JSON ;; # only JSON on stdout
  --color)
    if (($# < 2)) || ! _core_set_color "$2"; then
      printf 'test-core.sh: --color requires a value (auto|always|never)\n' >&2
      printf 'try: test-core.sh --help\n' >&2
      exit 2
    fi
    shift
    ;;
  --color=*)
    _core_set_color "${1#*=}" || {
      printf 'test-core.sh: --color requires auto|always|never\n' >&2
      exit 2
    }
    ;;
  -h | --help)
    cat <<'EOF'
usage: test-core.sh [-q|--quiet] [--scope LIST] [--color WHEN] [--json] [-h|--help]

Behavioral suite: clipboard ladder + nvim headless load + nvim event callbacks
+ zsh load-order smoke + function/unit + detection tests. Degrades gracefully
when zsh/nvim are absent.

  -q, --quiet     only print SKIP/FAIL lines and the final summary
  --scope LIST    limit the slow area sections: shell, nvim, all (default), none.
                  The clipboard + CI-classifier sections always run.
  --color WHEN    auto (default) | always | never; NO_COLOR still wins. (CORE_COLOR env.)
  --json          machine-readable summary on stdout (implies --quiet):
                  {pass,skip,fail,seconds,skipped[],result}
  -h, --help      show this help and exit
EOF
    exit 0
    ;;
  *)
    printf 'test-core.sh: unexpected argument: %s\n' "$1" >&2
    printf 'try: test-core.sh --help\n' >&2
    exit 2
    ;;
  esac
  shift
done

# Wall-clock for the standalone summary (mirrors audit-core.sh) — the headless nvim
# leg can take a few seconds, so showing elapsed reads as progress, not a hang.
SECONDS=0

# When invoked from audit-core.sh (CORE_TEST_NESTED=1) the audit owns the summary,
# so we suppress ours and only signal pass/fail via the exit code.
NESTED="${CORE_TEST_NESTED:-0}"
summary() {
  [[ "$NESTED" == 1 ]] && return 0
  if ((JSON)); then
    local _result _first=1 _s
    ((FAIL == 0)) && _result=ok || _result=failed
    printf '{"pass":%d,"skip":%d,"fail":%d,"seconds":%d,"skipped":[' \
      "$PASS" "$SKIP" "$FAIL" "$SECONDS"
    for _s in ${_CORE_SKIPS[@]+"${_CORE_SKIPS[@]}"}; do
      _s="${_s//\\/\\\\}"
      _s="${_s//\"/\\\"}"
      ((_first)) || printf ','
      printf '"%s"' "$_s"
      _first=0
    done
    printf '],"result":"%s"}\n' "$_result"
    return 0
  fi
  printf '\n%s──────── test summary ────────%s\n' "$c_blu" "$c_rst"
  printf '  %spass %d%s   %sskip %d%s   %sfail %d%s   %s(%ds)%s\n' \
    "$c_grn" "$PASS" "$c_rst" "$c_yel" "$SKIP" "$c_rst" "$c_red" "$FAIL" "$c_rst" \
    "$c_blu" "$SECONDS" "$c_rst"
}

# One throwaway sandbox for the whole run; clean it up no matter how we exit. It is
# created BEFORE the zsh gate because Section C (clipboard) is pure bash and must run
# even where zsh is absent — bin/clip's whole reason to exist is bare-box portability.
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/core-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

# ── C. clipboard detection ladder (bin/clip / bin/clip-paste) ─────────────────
# bin/clip is the single highest-fan-out runtime artifact in Core — used by zsh
# (pbcopy alias), tmux (copy-pipe), AND nvim (clipboard provider), across all 9 OS
# repos — yet its WSL→macOS→Wayland→X11 ladder had no test, only `bash -n`. We drive
# the ladder HERMETICALLY: PATH is pointed at a fake bin holding a stub `uname` that
# reports the OS we want, a stub `grep` that answers the /proc/version probe, and
# stub backends that print a marker instead of touching a real clipboard — then we
# assert the RIGHT backend was exec'd. PATH is the fake dir ONLY (a real `bash`
# symlink keeps the `#!/usr/bin/env bash` shebang resolvable), so backend probing is
# fully deterministic regardless of what the host happens to have installed. Pure
# bash — runs with no zsh, exactly where bin/clip most needs to work.
hdr "clipboard detection ladder (bin/clip, bin/clip-paste)"
CLIP="$HERE/bin/clip"
CLIPPASTE="$HERE/bin/clip-paste"
CBIN="$SANDBOX/clipbin"
_real_bash="$(command -v bash)"
_real_tr="$(command -v tr)"

_stub() {
  printf '#!/bin/sh\n%s\n' "$2" >"$CBIN/$1"
  chmod +x "$CBIN/$1"
}
# Fresh fake bin + cleared env before each scenario. `bash` is symlinked so the
# shebang resolves under the stripped PATH; `uname` defaults to "Linux" and Darwin
# cases override it. The WSL probe now reads /proc/version via a bash builtin (no
# grep fork — see bin/clip), so we point CLIP_PROC_VERSION at a NON-WSL fixture; the
# WSL cases either set WSL_DISTRO_NAME or overwrite that fixture with a microsoft one.
_clip_reset() {
  rm -rf "$CBIN"
  mkdir -p "$CBIN"
  unset WSL_DISTRO_NAME WAYLAND_DISPLAY
  ln -s "$_real_bash" "$CBIN/bash"
  _stub uname 'echo Linux'
  printf 'Linux version 6.1.0-0 (gcc) #1 SMP\n' >"$CBIN/procversion"
  export CLIP_PROC_VERSION="$CBIN/procversion"
}
# Assert prog's stdout is exactly the marker the chosen backend prints.
_clip_is() { # _clip_is <label> <prog> <expected>
  local out
  out="$(printf 'payload' | PATH="$CBIN" "$2" 2>/dev/null)"
  if [[ "$out" == "$3" ]]; then pass "$1"; else fail "$1 (got '${out}', want '${3}')"; fi
}
# Assert prog exits non-zero — the no-backend-found path.
_clip_fails() { # _clip_fails <label> <prog>
  if printf 'payload' | PATH="$CBIN" "$2" >/dev/null 2>&1; then
    fail "$1 (expected non-zero exit)"
  else pass "$1"; fi
}

# clip (copy) — each scenario leaves ONLY the intended backend reachable.
_clip_reset
export WSL_DISTRO_NAME=Ubuntu
_stub clip.exe 'echo WSL'
_clip_is "clip → clip.exe when WSL_DISTRO_NAME set" "$CLIP" WSL
unset WSL_DISTRO_NAME
_clip_reset
# WSL with NO WSL_DISTRO_NAME — detection must come from /proc/version content.
printf 'Linux version 5.15.0-microsoft-standard-WSL2\n' >"$CBIN/procversion"
_stub clip.exe 'echo WSL'
_clip_is "clip → clip.exe via /proc/version (no WSL_DISTRO_NAME)" "$CLIP" WSL
_clip_reset
_stub uname 'echo Darwin'
_stub pbcopy 'echo MAC'
_clip_is "clip → pbcopy on Darwin" "$CLIP" MAC
_clip_reset
export WAYLAND_DISPLAY=wayland-0
_stub wl-copy 'echo WL'
_clip_is "clip → wl-copy under Wayland" "$CLIP" WL
unset WAYLAND_DISPLAY
_clip_reset
_stub xclip 'echo XCLIP'
_clip_is "clip → xclip on X11" "$CLIP" XCLIP
_clip_reset
_stub xsel 'echo XSEL'
_clip_is "clip → xsel when xclip absent" "$CLIP" XSEL
_clip_reset
_clip_fails "clip exits non-zero with no backend" "$CLIP"

# clip-paste (paste) — mirror ladder; the WSL leg also strips the CR powershell adds.
_clip_reset
export WSL_DISTRO_NAME=Ubuntu
ln -s "$_real_tr" "$CBIN/tr"
_stub powershell.exe 'printf "WSLPASTE\r"'
_clip_is "clip-paste → powershell + CR-strip on WSL" "$CLIPPASTE" WSLPASTE
unset WSL_DISTRO_NAME
_clip_reset
# WSL detected from /proc/version alone (no WSL_DISTRO_NAME).
printf 'Linux version 5.15.0-microsoft-standard-WSL2\n' >"$CBIN/procversion"
ln -s "$_real_tr" "$CBIN/tr"
_stub powershell.exe 'printf "WSLPASTE\r"'
_clip_is "clip-paste → powershell via /proc/version (no WSL_DISTRO_NAME)" "$CLIPPASTE" WSLPASTE
_clip_reset
_stub uname 'echo Darwin'
_stub pbpaste 'echo MAC'
_clip_is "clip-paste → pbpaste on Darwin" "$CLIPPASTE" MAC
_clip_reset
export WAYLAND_DISPLAY=wayland-0
_stub wl-paste 'echo WL'
_clip_is "clip-paste → wl-paste under Wayland" "$CLIPPASTE" WL
unset WAYLAND_DISPLAY
_clip_reset
_stub xclip 'echo XCLIP'
_clip_is "clip-paste → xclip -o on X11" "$CLIPPASTE" XCLIP
_clip_reset
_clip_fails "clip-paste exits non-zero with no backend" "$CLIPPASTE"

# ── D. Neovim config load (nvim/, headless) ───────────────────────────────────
# nvim/ is the largest body of code in Core yet was validated only by luacheck
# (static). Lua that is luacheck-clean can still be a BROKEN config — a bad vim API
# call, a malformed lazy spec — that surfaces only when nvim actually starts, and it
# fans out to 9 repos. This loads the AUTHORED Lua headlessly: the pure config layer
# (globals/options/keymaps/autocmds/clipboard/providers) AND every plugin SPEC file
# (require evaluates the spec TABLE; lazy's deferred config/keys callbacks do NOT run,
# so no plugin needs to be installed — every plugin `require` in this tree is inside
# such a callback). Hermetic + offline, mirroring how the zsh tests pre-seed empty
# plugin dirs; graceful skip when nvim is absent, exactly like the linters. Real
# plugin RUNTIME (the deferred callbacks) is out of scope — luacheck covers its syntax.
hdr "neovim config load (nvim/ headless)"
if ! ((SCOPE_NVIM)); then
  skip "nvim config load (out of scope)"
elif have nvim; then
  probe="$SANDBOX/nvim-probe.lua"
  cat >"$probe" <<'LUA'
vim.opt.runtimepath:prepend(vim.env.CORE_NVIM_DIR)
local errs = {}
local function try(mod)
  local ok, err = pcall(require, mod)
  if not ok then errs[#errs + 1] = mod .. " → " .. tostring(err) end
end
for _, m in ipairs({
  "gerrrt.config.globals", "gerrrt.config.options", "gerrrt.config.keymaps",
  "gerrrt.config.autocmds", "gerrrt.config.clipboard", "gerrrt.config.providers",
}) do try(m) end
-- :checkhealth gerrrt module — loaded only by checkhealth at runtime, so this is its
-- only load gate. Require it AND assert it exposes a check() function.
do
  local ok, m = pcall(require, "gerrrt.health")
  if not ok then
    errs[#errs + 1] = "gerrrt.health → " .. tostring(m)
  elseif type(m) ~= "table" or type(m.check) ~= "function" then
    errs[#errs + 1] = "gerrrt.health → did not return a table with a check() function"
  end
end
-- every plugin spec must require cleanly and return a lazy spec table
local pdir = vim.env.CORE_NVIM_DIR .. "/lua/gerrrt/plugins"
for _, f in ipairs(vim.fn.readdir(pdir) or {}) do
  local name = f:match("^(.+)%.lua$")
  if name then
    local mod = "gerrrt.plugins." .. name
    local ok, res = pcall(require, mod)
    if not ok then
      errs[#errs + 1] = mod .. " → " .. tostring(res)
    elseif type(res) ~= "table" then
      errs[#errs + 1] = mod .. " → did not return a spec table"
    end
  end
end
-- LSP layer: servers/init.lua wires 13 server configs + the on_attach/diagnostics
-- helpers, but ALL of it runs inside a deferred plugin callback (plugins/nvim-lspconfig)
-- — so the loop above never touches it, and luacheck (static) was its only gate. A bad
-- vim.lsp.config{} call or a typo'd capability there is luacheck-clean and breaks only on
-- first file-open, then fans out 9×. Close that: require utils.lsp/diagnostics, and every
-- servers/* LEAF (each returns a `function(capabilities)`; requiring it evaluates the file
-- WITHOUT calling it, so no blink.cmp/lspconfig need be installed). servers/init.lua itself
-- is skipped — it require()s blink.cmp, a plugin absent from this hermetic probe.
-- utils.ui-highlights has the SAME gap: it's only require()d inside tokyonight's deferred
-- on_highlights callback (plugins/theme.lua), which the plugins/* loop above never runs — so
-- add it here too. It returns `M` with an `apply(hl, c)` function; requiring evaluates the
-- file without calling apply, so no tokyonight/colorscheme need be present.
for _, m in ipairs({ "gerrrt.utils.lsp", "gerrrt.utils.diagnostics", "gerrrt.utils.ui-highlights" }) do
  try(m)
end
local sdir = vim.env.CORE_NVIM_DIR .. "/lua/gerrrt/servers"
for _, f in ipairs(vim.fn.readdir(sdir) or {}) do
  local name = f:match("^(.+)%.lua$")
  if name and name ~= "init" then
    local mod = "gerrrt.servers." .. name
    local ok, res = pcall(require, mod)
    if not ok then
      errs[#errs + 1] = mod .. " → " .. tostring(res)
    elseif type(res) ~= "function" then
      errs[#errs + 1] = mod .. " → did not return a function(capabilities)"
    end
  end
end
if #errs > 0 then
  io.stderr:write(table.concat(errs, "\n") .. "\n")
  vim.cmd("cquit 1")
end
vim.cmd("quitall!")
LUA
  # -u the probe AS init (so the repo's real bootstrap never runs → no lazy clone, no
  # network), headless, no shada/swap. A clean exit means every authored module and
  # spec loaded; the probe `:cquit 1`s with the offending modules on stderr otherwise.
  nvim_err="$SANDBOX/nvim.err"
  if CORE_NVIM_DIR="$HERE/nvim" nvim --headless -u "$probe" -i NONE -n +qa >/dev/null 2>"$nvim_err"; then
    pass "nvim loaded all config + plugin specs + LSP server configs (no lua errors)"
  else
    fail "nvim config/plugin-spec/lsp load error:"
    [[ -s "$nvim_err" ]] && sed 's/^/    /' "$nvim_err" >&2
  fi

  # Actually RUN :checkhealth gerrrt. The probe above only proves gerrrt.health LOADS and
  # exposes check(); this FIRES check() in the real checkhealth context, so a runtime error
  # in its vim.health calls (a typo'd h.warn, a bad API) is caught — nothing else exercises
  # it. -u NONE keeps it hermetic; --cmd puts nvim/ on the runtimepath so checkhealth
  # discovers lua/gerrrt/health.lua; we write the report buffer out and assert OUR section
  # rendered (h.start("dotfiles-core: …") is check()'s first call, so its absence means
  # check() never ran or threw immediately). checkhealth never prompts, so headless can't hang.
  ckrep="$SANDBOX/checkhealth.txt"
  ckerr="$SANDBOX/checkhealth.err"
  : >"$ckrep"
  # Pass the paths via ENV and fnameescape() them INSIDE vim (the idiom the event probe
  # below uses), so a space in $SANDBOX/$HERE can't break the Ex `set rtp`/`write` parsing.
  # `-c` runs post-startup in order: rtp is set before checkhealth scans it, before write.
  # Capture stderr (not /dev/null) so a failure with an empty report is still diagnosable.
  CORE_NVIM_DIR="$HERE/nvim" CORE_CK_REP="$ckrep" \
    nvim --headless -u NONE -i NONE -n \
    -c 'execute "set rtp^=" .. fnameescape($CORE_NVIM_DIR)' \
    -c 'checkhealth gerrrt' \
    -c 'execute "write!" fnameescape($CORE_CK_REP)' \
    -c 'qa!' >/dev/null 2>"$ckerr"
  if grep -q "dotfiles-core" "$ckrep" 2>/dev/null; then
    pass "checkhealth gerrrt ran (health report rendered)"
  else
    fail "checkhealth gerrrt did not render its section (check() missing or threw):"
    [[ -s "$ckrep" ]] && sed 's/^/    /' "$ckrep" >&2
    [[ -s "$ckerr" ]] && sed 's/^/    /' "$ckerr" >&2
  fi
else
  skip "nvim config load (nvim not installed — runs in CI)"
fi

# ── D2. Neovim event-driven autocmd callbacks (nvim/, headless) ───────────────
# Section D proves the modules LOAD; it does not prove their EVENT CALLBACKS run.
# An autocmd registers fine and only its callback fires later — on a yank, a save,
# an LSP attach — so a bad vim API call inside one is luacheck-clean, load-clean, and
# breaks only when you actually edit. That blind spot shipped a real bug: the
# TextYankPost highlight called a non-existent `vim.hl.hl_op`, throwing on every yank
# AND delete (TextYankPost fires on both) while the edit still ran — a red error with
# no failing gate, fanned out to 9 repos. This closes it: load the autocmds, then
# FIRE the events and assert the callbacks ran clean.
#
# Events are triggered via post-startup `-c` commands (NOT inside the `-u` init): an
# autocmd error during init makes headless nvim block on a "Press ENTER" prompt,
# whereas a `-c` error is reported and nvim proceeds to the next command — so the
# gate can never hang in CI. The require itself stays in `-u` and `cquit`s on failure
# (no prompt). Detection is STDERR-NON-EMPTY, not exit code: a fired-callback error
# does not change nvim's exit status (both clean and broken runs exit 0), it only
# prints — exactly the signature the bug has. BufWritePre (format-on-save) and
# LspAttach are deliberately NOT fired here: their callbacks require plugins
# (mini.trailspace/conform) or a live LSP attach, neither present in this hermetic
# probe — luacheck covers their syntax; runtime is out of scope.
hdr "neovim event callbacks (nvim/ headless)"
if ! ((SCOPE_NVIM)); then
  skip "nvim event callbacks (out of scope)"
elif have nvim; then
  evt_probe="$SANDBOX/nvim-events.lua"
  cat >"$evt_probe" <<'LUA'
vim.opt.runtimepath:prepend(vim.env.CORE_NVIM_DIR)
-- Register the autocmds. A require failure cquit's immediately (no ENTER prompt);
-- the EVENTS themselves are fired by the caller's -c flags, after startup.
local ok, err = pcall(require, "gerrrt.config.autocmds")
if not ok then
  io.stderr:write("require gerrrt.config.autocmds → " .. tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
LUA
  evt_file="$SANDBOX/probe.txt"
  printf 'one\ntwo\nthree\n' >"$evt_file"
  evt_err="$SANDBOX/nvim-events.err"
  # Fire each registered event once: yank + delete (TextYankPost — the regression
  # above), a markdown FileType (the per-filetype view options), and a real file open
  # (BufReadPost — cursor restore). Any callback that throws prints to stderr. The file
  # path is passed via $CORE_EVT_FILE and opened through fnameescape() rather than
  # interpolated into the Ex command, so a $SANDBOX/$TMPDIR containing spaces is safe.
  CORE_NVIM_DIR="$HERE/nvim" CORE_EVT_FILE="$evt_file" nvim --headless -u "$evt_probe" -i NONE -n \
    -c 'call setline(1, ["alpha","bravo","charlie"])' \
    -c 'normal! yy' -c 'normal! dd' \
    -c 'setfiletype markdown' \
    -c 'execute "edit" fnameescape($CORE_EVT_FILE)' \
    -c 'qa!' </dev/null >/dev/null 2>"$evt_err"
  if [[ -s "$evt_err" ]]; then
    fail "nvim autocmd callback errored when fired (e.g. the yank/delete highlight):"
    sed 's/^/    /' "$evt_err" >&2
  else
    pass "nvim event callbacks fired clean (TextYankPost yank+delete, FileType, BufReadPost)"
  fi
else
  skip "nvim event callbacks (nvim not installed — runs in CI)"
fi

# ── E. CI path classifier (scripts/ci-classify.sh) ────────────────────────────
# ci.yml's change-detection picks which gates run per push. That logic now lives in
# scripts/ci-classify.sh (pulled out of the workflow YAML so it can be linted + tested);
# this asserts the contract the workflow depends on: known paths map to the right gates,
# the __ALL__ sentinel runs everything, and — the regression that matters — an
# UNRECOGNISED top-level path FAILS CLOSED to the full run instead of silently skipping
# a gate on the 9-repo fan-out. Pure bash, so it runs even where zsh/nvim are absent.
hdr "CI path classifier (scripts/ci-classify.sh)"
CLASSIFY="$HERE/scripts/ci-classify.sh"
_classify_is() { # _classify_is <label> <newline-input> <want-shell> <want-nvim>
  local got
  got="$(printf '%s\n' "$2" | "$CLASSIFY" 2>/dev/null)"
  if [[ "$got" == "shell=$3"$'\n'"nvim=$4" ]]; then
    pass "$1"
  else
    fail "$1 (got: ${got//$'\n'/ }; want shell=$3 nvim=$4)"
  fi
}
_classify_is "zsh/ change → shell gate only" 'zsh/ui.zsh' true false
_classify_is "nvim/ change → nvim gate only" 'nvim/init.lua' false true
_classify_is "docs (*.md) change → no gate" 'README.md' false false
_classify_is "infra (scripts/) change → full run" 'scripts/audit-core.sh' true true
_classify_is "infra (.shellcheckrc) change → full run" '.shellcheckrc' true true
_classify_is "__ALL__ sentinel → full run" '__ALL__' true true
_classify_is "unrecognised path → FAIL CLOSED to full run" 'newdir/thing.xyz' true true
_classify_is "mixed shell+nvim set → union of both" $'zsh/ui.zsh\nnvim/init.lua' true true

# ── F. core/ pre-commit guard (lib/bootstrap-lib.sh blib_install_core_guard) ───
# The guard hook (installed by sync-core.sh on every fan-out, and by a bootstrap on a
# fresh clone) is the mechanical backstop for "never hand-edit vendored core/". Drive it
# hermetically in throwaway git repos: assert it BLOCKS a core/ commit, ALLOWS a non-core
# commit, ALLOWS a core/ commit under the sync escape hatch, and never clobbers a foreign
# pre-commit hook. Pure bash + git (skipped where git is absent, like the nvim sections).
if have git; then
  hdr "core/ pre-commit guard (blib_install_core_guard)"
  # shellcheck source=lib/bootstrap-lib.sh
  source "$HERE/lib/bootstrap-lib.sh"
  # Pin git config to /dev/null (like the gcheck helper) so a host/CI global
  # core.hooksPath would not make git ignore our per-repo hook, and a global
  # commit.gpgsign can't break the non-core commit — keeps these assertions hermetic.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  GREPO="$SANDBOX/guardrepo"
  _guard_fresh() { # fresh repo with the guard installed
    rm -rf "$GREPO"
    mkdir -p "$GREPO/core"
    git -C "$GREPO" init -q
    git -C "$GREPO" config user.email t@example.com
    git -C "$GREPO" config user.name tester
    blib_install_core_guard "$GREPO" >/dev/null 2>&1
  }
  _guard_commit() { # _guard_commit <relpath> <allow:0|1> → echoes ok|blocked
    printf 'edit' >"$GREPO/$1"
    git -C "$GREPO" add -A
    local rc
    if [[ "${2:-0}" == 1 ]]; then
      DOTFILES_ALLOW_CORE_EDIT=1 git -C "$GREPO" commit -q -m x >/dev/null 2>&1
      rc=$?
    else
      git -C "$GREPO" commit -q -m x >/dev/null 2>&1
      rc=$?
    fi
    [[ $rc -eq 0 ]] && echo ok || echo blocked
  }

  _guard_fresh
  if [[ -x "$GREPO/.git/hooks/pre-commit" ]]; then pass "guard: pre-commit hook installed (+x)"; else fail "guard: hook missing or not executable"; fi

  _guard_fresh
  if [[ "$(_guard_commit core/x.txt 0)" == blocked ]]; then pass "guard: blocks a commit touching core/"; else fail "guard: did NOT block a core/ edit"; fi

  _guard_fresh
  if [[ "$(_guard_commit README.md 0)" == ok ]]; then pass "guard: allows a non-core commit"; else fail "guard: wrongly blocked a non-core commit"; fi

  _guard_fresh
  if [[ "$(_guard_commit core/y.txt 1)" == ok ]]; then pass "guard: DOTFILES_ALLOW_CORE_EDIT exempts a sync write"; else fail "guard: escape hatch did not allow a core/ commit"; fi

  # a pure DELETION of a vendored file (git rm core/…) drifts from Core too — must be blocked
  _guard_fresh
  printf 'seed' >"$GREPO/core/seed.txt"; git -C "$GREPO" add -A
  DOTFILES_ALLOW_CORE_EDIT=1 git -C "$GREPO" commit -q -m seed >/dev/null 2>&1
  git -C "$GREPO" rm -q core/seed.txt >/dev/null 2>&1
  if git -C "$GREPO" commit -q -m del >/dev/null 2>&1; then fail "guard: did NOT block a core/ deletion"; else pass "guard: blocks a core/ deletion (git rm)"; fi

  # a pre-existing, unrelated pre-commit hook must be preserved (not clobbered)
  rm -rf "$GREPO"; mkdir -p "$GREPO/core"; git -C "$GREPO" init -q
  printf '#!/bin/sh\nexit 0\n' >"$GREPO/.git/hooks/pre-commit"; chmod +x "$GREPO/.git/hooks/pre-commit"
  blib_install_core_guard "$GREPO" >/dev/null 2>&1
  if grep -q 'dotfiles-core-guard' "$GREPO/.git/hooks/pre-commit"; then fail "guard: clobbered a pre-existing custom hook"; else pass "guard: preserves a pre-existing custom pre-commit hook"; fi

  # core.hooksPath set → git ignores .git/hooks, so installing there is false
  # protection. The installer must skip rather than write an ignored hook.
  rm -rf "$GREPO"; mkdir -p "$GREPO/core"; git -C "$GREPO" init -q
  git -C "$GREPO" config core.hooksPath .githooks
  blib_install_core_guard "$GREPO" >/dev/null 2>&1
  if [[ -e "$GREPO/.git/hooks/pre-commit" ]] && grep -q 'dotfiles-core-guard' "$GREPO/.git/hooks/pre-commit" 2>/dev/null; then
    fail "guard: wrote into the ignored .git/hooks despite core.hooksPath"
  else
    pass "guard: skips when core.hooksPath is set (no false protection)"
  fi

  # worktree support (the reason the installer asks git instead of testing for a `.git`
  # DIR): in a linked worktree `.git` is a FILE, and hooks live in the shared common dir.
  # Install into the worktree and assert the guard actually blocks a core/ commit there.
  rm -rf "$GREPO"; mkdir -p "$GREPO/core"; git -C "$GREPO" init -q
  git -C "$GREPO" config user.email t@example.com; git -C "$GREPO" config user.name tester
  printf 'seed' >"$GREPO/seed.txt"; git -C "$GREPO" add -A
  git -C "$GREPO" commit -q -m seed >/dev/null 2>&1   # a worktree needs a commit to branch from
  GWT="$SANDBOX/guardwt"; rm -rf "$GWT"
  if git -C "$GREPO" worktree add -q "$GWT" -b wt >/dev/null 2>&1; then
    mkdir -p "$GWT/core"
    blib_install_core_guard "$GWT" >/dev/null 2>&1
    printf 'edit' >"$GWT/core/wt.txt"; git -C "$GWT" add -A
    if git -C "$GWT" commit -q -m x >/dev/null 2>&1; then
      fail "guard: did NOT block a core/ edit in a worktree (.git is a file)"
    else
      pass "guard: blocks a core/ edit in a linked worktree"
    fi
  else
    skip "guard: worktree case (git worktree unavailable)"
  fi
fi

# ── F2. auto-tag version math + exit-code contract (scripts/auto-tag.sh) ──────
# auto-tag.sh cuts an OS repo's next vX.Y.Z when a Core fan-out lands. Drive its
# (dry-run) computation hermetically: it must patch-bump the latest STRICT SemVer tag
# while IGNORING a prerelease/suffixed tag (v1.2.0-rc1) and the moving major alias (v1),
# stay octal-safe on a zero-padded component (v1.08.0), seed an untagged repo, no-op when
# HEAD is already a release, and usage-error a bad --bump — the exact glob/parse
# regressions a loose `git tag --list` glob would let through. THEN the exit-code contract
# the script's fix(release) history is all about: success → 0, no-op → 0, validation error
# → 2, and a REAL push failure → non-zero (never a silent green). The first three legs are
# hermetic (no network, no gh); the push-failure leg deliberately drives the real `git push`
# error branch — there is no `origin` in the sandbox, so the push fails and the script goes
# non-zero, which is exactly the contract under test. Pure bash + git.
if have git; then
  hdr "auto-tag version math + exit-code contract (scripts/auto-tag.sh)"
  AT="$HERE/scripts/auto-tag.sh"
  ATR="$SANDBOX/atrepo"
  _at_fresh() {
    rm -rf "$ATR"
    mkdir -p "$ATR"
    git -C "$ATR" init -q
    git -C "$ATR" config user.email t@example.com
    git -C "$ATR" config user.name tester
    git -C "$ATR" commit -q --allow-empty -m c1
  }
  _at_would() { # [bump] → echoes the tag it WOULD cut (dry-run), or noop / err
    local out
    out="$("$AT" "$ATR" ${1:+--bump "$1"} --color never 2>&1)" || {
      echo err
      return 0
    }
    if grep -q 'already tagged' <<<"$out"; then
      echo noop
    else
      sed -n 's/.*would tag \(v[0-9][0-9.]*\).*/\1/p' <<<"$out"
    fi
  }

  _at_assert() { # _at_assert <label> <want> [bump]
    local got
    got="$(_at_would "${3:-}")"
    if [[ "$got" == "$2" ]]; then pass "$1"; else fail "$1 (got $got, want $2)"; fi
  }

  _at_fresh
  git -C "$ATR" tag -a v1.2.0 -m v1.2.0
  git -C "$ATR" tag -a v1.2.0-rc1 -m rc      # prerelease — must be ignored
  git -C "$ATR" tag v1                       # moving major alias — must be ignored
  git -C "$ATR" commit -q --allow-empty -m c2 # HEAD now past the tags
  _at_assert "auto-tag: patch-bumps latest strict tag, ignoring rc + vN alias" v1.2.1
  _at_assert "auto-tag: minor bump" v1.3.0 minor

  _at_fresh
  git -C "$ATR" tag -a v1.08.0 -m x          # zero-padded component — must not octal-error
  git -C "$ATR" commit -q --allow-empty -m c2
  _at_assert "auto-tag: octal-safe on a zero-padded component" v1.9.0 minor

  _at_fresh # no tags at all → seed the initial
  _at_assert "auto-tag: seeds v0.1.0 when the repo has no tag" v0.1.0

  _at_fresh
  git -C "$ATR" tag -a v2.0.0 -m x           # HEAD itself tagged → idempotent no-op
  _at_assert "auto-tag: no-op when HEAD already carries a release" noop

  _at_assert "auto-tag: rejects an invalid --bump" err bogus

  _at_fresh # --release is meaningless without --push (can't release an unpushed tag)
  if "$AT" "$ATR" --release --color never >/dev/null 2>&1; then
    fail "auto-tag: --release without --push should error"
  else
    pass "auto-tag: --release requires --push"
  fi

  # ── exit-code contract (the band-aids' history is exactly about exit codes) ──
  # auto-tag.sh has had repeated fix(release) commits over its exit codes: a no-op must
  # be 0, a usage/validation error 2, and a REAL create failure non-zero (not a silent
  # green). Assert all three legs HERMETICALLY — no network, no gh. Helper: run + echo rc.
  _at_rc() { "$AT" "$ATR" "$@" --color never >/dev/null 2>&1; echo $?; }

  # 1) SUCCESS leg — a plain dry-run on a tagged repo computes a bump and exits 0.
  _at_fresh
  git -C "$ATR" tag -a v1.0.0 -m v1.0.0
  git -C "$ATR" commit -q --allow-empty -m c2
  if [[ "$(_at_rc)" == 0 ]]; then pass "auto-tag: success (dry-run computes a bump) exits 0"; else fail "auto-tag: dry-run should exit 0"; fi

  # 2) NO-OP leg — HEAD already carries a release → idempotent, exits 0 (not an error).
  _at_fresh
  git -C "$ATR" tag -a v1.0.0 -m v1.0.0   # tags HEAD
  if [[ "$(_at_rc)" == 0 ]]; then pass "auto-tag: no-op (HEAD already tagged) exits 0"; else fail "auto-tag: no-op should exit 0"; fi

  # 3) USAGE/VALIDATION error — a malformed --initial is rejected with exit 2 (not 1).
  _at_fresh   # untagged repo, so --initial is the seed path that validates it
  if [[ "$(_at_rc --initial 1.2)" == 2 ]]; then pass "auto-tag: malformed --initial exits 2"; else fail "auto-tag: bad --initial should exit 2"; fi

  # 4) REAL PUSH-FAILURE leg — exercise auto-tag.sh's push error branch (the one that
  #    `fail`s + exits 1 when `git push origin <tag>` fails). On a freshly-tagged repo the
  #    bump is computable and unique, so the script creates the tag and then tries to push
  #    it; the sandbox has NO `origin` remote, so the push genuinely fails and the script
  #    goes non-zero. This is the "a real push failure must go red, not green" contract the
  #    fix(release) history is about. (Not hermetic — it intentionally hits the push path;
  #    if an `origin` were ever added to the sandbox this leg would need a guaranteed-to-fail
  #    remote instead.)
  _at_fresh
  git -C "$ATR" tag -a v1.0.0 -m v1.0.0         # latest release on c1
  git -C "$ATR" commit -q --allow-empty -m c2   # HEAD past the tag → a real bump (v1.0.1) to push
  _rc_push="$(_at_rc --push)"
  if [[ "$_rc_push" != 0 ]]; then pass "auto-tag: --push with no reachable origin fails non-zero (rc=$_rc_push)"; else fail "auto-tag: failed push should exit non-zero, got 0"; fi
else
  skip "auto-tag version math + exit-code contract (git unavailable)"
fi

# ── G. module selection (lib/bootstrap-lib.sh blib_select / blib_want) ─────────
# Track B's --only/--skip gate. blib_select VALIDATES a comma-separated selector and
# records BLIB_ONLY/BLIB_SKIP; blib_want is the allowlist/skiplist predicate the link
# helpers consult; blib_selected_note is the summary suffix. Pure bash (no git/zsh),
# so it runs everywhere: assert the regex rejects empty/leading/trailing/doubled
# commas + non-letters + spaces + unknown groups, accepts + normalises a clean
# selector, and that blib_want honours only-wins-over-skip precedence.
hdr "module selection (blib_select / blib_want)"
# shellcheck source=lib/bootstrap-lib.sh
source "$HERE/lib/bootstrap-lib.sh"

# Drift guard: the cases below hardcode the six groups as an independent oracle (so a
# corrupted BLIB_MODULES can't make them pass vacuously). Pin the production list to that
# oracle HERE so adding/renaming a group trips one obvious assertion instead of silently
# skewing every _want_set expectation.
if [[ "$BLIB_MODULES" == "zsh nvim tmux git prompt tools" ]]; then pass "BLIB_MODULES matches the tested group set"; else fail "BLIB_MODULES drifted from the tested oracle (got '$BLIB_MODULES') — update Section G"; fi

# blib_select aborts (exit 1) on bad input — drive it in a subshell and read the rc.
_sel_rc() { ( blib_select "$1" "$2" ) >/dev/null 2>&1; }
for _bad in 'zsh,,nvim' 'zsh,' ',zsh' '' '*' 'a b' 'bogus' 'zsh nvim'; do
  if _sel_rc --only "$_bad"; then fail "blib_select accepted a bad selector: '$_bad'"; else pass "blib_select rejects '$_bad'"; fi
done

# an unknown flag (not --only/--skip) must fail fast, not silently no-op the selection.
if _sel_rc --bogus 'zsh'; then fail "blib_select accepted an unknown flag"; else pass "blib_select rejects an unknown flag"; fi

# a clean selector is accepted and normalised to space-separated (subshell: blib_select
# would mutate the suite's own BLIB_ONLY otherwise).
_only_norm="$( blib_select --only 'zsh,nvim'; printf '%s' "$BLIB_ONLY" )"
if [[ "$_only_norm" == "zsh nvim" ]]; then pass "blib_select accepts zsh,nvim → 'zsh nvim'"; else fail "blib_select did not normalise zsh,nvim (got '$_only_norm')"; fi

# blib_want over the six groups under each mode. Dynamic scope: the `local` BLIB_ONLY/
# BLIB_SKIP here is exactly what blib_want reads.
_want_set() {
  local BLIB_ONLY="$1" BLIB_SKIP="$2" g w=""
  for g in zsh nvim tmux git prompt tools; do
    if blib_want "$g"; then w+="$g "; fi
  done
  printf '%s' "${w% }"
}
if [[ "$(_want_set '' '')" == "zsh nvim tmux git prompt tools" ]]; then pass "blib_want: default wires every group"; else fail "blib_want: default did not wire all groups"; fi
if [[ "$(_want_set 'zsh nvim' '')" == "zsh nvim" ]]; then pass "blib_want: --only is an allowlist"; else fail "blib_want: --only allowlist wrong"; fi
if [[ "$(_want_set '' 'tmux')" == "zsh nvim git prompt tools" ]]; then pass "blib_want: --skip drops the named group"; else fail "blib_want: --skip wrong"; fi
if [[ "$(_want_set 'zsh' 'zsh')" == "zsh" ]]; then pass "blib_want: --only wins over --skip"; else fail "blib_want: precedence wrong (only should win)"; fi

# blib_selected_note — empty when unfiltered, reflects the active selection otherwise.
if [[ -z "$( blib_selected_note )" ]]; then pass "blib_selected_note: empty when nothing is filtered"; else fail "blib_selected_note: not empty by default"; fi
if [[ "$( blib_select --only zsh,nvim; blib_selected_note )" == " (only: zsh nvim)" ]]; then pass "blib_selected_note: shows the --only suffix"; else fail "blib_selected_note: --only suffix wrong"; fi
if [[ "$( blib_select --skip tmux; blib_selected_note )" == " (skipped: tmux)" ]]; then pass "blib_selected_note: shows the --skip suffix"; else fail "blib_selected_note: --skip suffix wrong"; fi
# precedence: when both are set --only wins in blib_want, so the note must report ONLY the
# only-mode (showing a skipped suffix that's actually ignored would be misleading).
if [[ "$( blib_select --only zsh; blib_select --skip nvim; blib_selected_note )" == " (only: zsh)" ]]; then pass "blib_selected_note: --only wins, --skip not shown"; else fail "blib_selected_note: should report only-mode when both set"; fi

# ── zsh-gated sections (A load-order, B function units) ───────────────────────
# Everything below needs a real zsh. On a bare box we SKIP it (not fail) and fall
# through to the shared summary, so a Section-C failure still surfaces as exit 1.
if ! ((SCOPE_SHELL)) || ! have zsh; then
  hdr "zsh behavioral sections (load-order + function units)"
  if ! ((SCOPE_SHELL)); then
    skip "zsh behavioral sections (out of scope)"
  else
    skip "load-order smoke + function units (zsh not installed — runs in CI)"
  fi
  summary
  ((FAIL == 0)) || {
    { [[ "$NESTED" == 1 ]] || ((JSON)); } || printf '%stests FAILED%s\n' "$c_red" "$c_rst" >&2
    exit 1
  }
  { [[ "$NESTED" == 1 ]] || ((JSON)); } || printf '%stests OK%s\n' "$c_grn" "$c_rst"
  exit 0
fi

# ── A. load-order smoke test ──────────────────────────────────────────────────
hdr "load-order smoke test (canonical .zshrc chain)"
# The README/manifest canonical order. There is no os/local module here — those
# are supplied by each OS repo's loader and are out of Core's scope.
CORE_MODULES=(tools ui options history aliases git functions fzf bindings plugins op maint update)

# Pre-seed empty plugin dirs so plugins.zsh's first-run clone is a no-op (hermetic,
# no network). _zplugin_load finds the dir, skips the clone, finds no source file,
# and moves on — exercising the load-order logic without pulling from GitHub. The dir
# list lives once in common.sh (_seed_plugin_dirs), shared with the integration + bench.
_seed_plugin_dirs "$SANDBOX/zdot/plugins"

# Generate the sandbox .zshrc: source every Core module in canonical order, then
# print a sentinel. We deliberately do NOT key success on each module's exit code —
# a module whose LAST statement is a false guard (e.g. aliases.zsh ends on
# `[[ -n $HAVE_GPING ]] && alias ping=gping`, false on a bare box) returns non-zero
# while having loaded perfectly. The real signal of a broken load-order contract is
# a RUNTIME error on stderr (a module using a fn/widget/var an EARLIER module must
# define first) — so we assert: the chain REACHED THE END (sentinel) with CLEAN
# stderr. Parse errors are already caught per-file by audit-core.sh's `zsh -n`.
export CORE_DIR="$HERE/zsh"
{
  printf 'for _m in %s; do source "$CORE_DIR/$_m.zsh"; done\n' "${CORE_MODULES[*]}"
  printf 'print -r -- "SMOKE_OK"\n'
} >"$SANDBOX/zdot/.zshrc"

# Run one interactive zsh against the sandbox rc. We do NOT rely on zsh auto-sourcing
# $ZDOTDIR/.zshrc: a global /etc/zshenv can force ZDOTDIR (overriding the env we pass), and
# auto-load doesn't fire when stdout is captured (non-TTY). So -f disables rc auto-load, we
# set ZDOTDIR INSIDE -c (after /etc/zshenv ran) and `source` the rc explicitly; -i keeps the
# modules' `[[ $- == *i* ]]` guards live. MISE_TRUSTED_CONFIG_PATHS pre-trusts the vendored
# mise config so `mise activate` doesn't abort under the sandbox HOME.
smoke_out="$(
  HOME="$SANDBOX" CORE_DIR="$CORE_DIR" \
    XDG_CACHE_HOME="$SANDBOX/cache" XDG_STATE_HOME="$SANDBOX/state" \
    XDG_RUNTIME_DIR="$SANDBOX/run" MISE_TRUSTED_CONFIG_PATHS="$HERE" \
    zsh -f -i -c "ZDOTDIR='$SANDBOX/zdot'; source \"\$ZDOTDIR/.zshrc\"" 2>"$SANDBOX/smoke.err"
)"
# High-signal zsh runtime-error markers — what a real load-order break looks like.
smoke_errs="$(grep -Ei \
  'command not found|parse error|: no such file or directory|not defined|bad pattern|bad math expression|maximum nested' \
  "$SANDBOX/smoke.err" 2>/dev/null || true)"
if ! printf '%s' "$smoke_out" | grep -q '^SMOKE_OK$'; then
  fail "load-order chain did not reach the end (no SMOKE_OK sentinel — a module aborted)"
  [[ -s "$SANDBOX/smoke.err" ]] && sed 's/^/    /' "$SANDBOX/smoke.err" >&2
elif [[ -n "$smoke_errs" ]]; then
  fail "runtime errors during canonical load (load-order contract broken):"
  printf '%s\n' "$smoke_errs" | sed 's/^/    /' >&2
else
  pass "all ${#CORE_MODULES[@]} modules loaded in canonical order (clean stderr)"
fi

# ── A2. consumer integration (Core + os/local layers) ─────────────────────────
# Core NEVER loads alone in production: each OS repo's .zshrc sources it in canonical
# order and THEN its own os.zsh + local.zsh (README: tools→…→update→os→local). Section
# A proves Core-in-isolation; this proves the documented CONSUMPTION — that the Core→OS
# CONTRACT holds at the real 9-repo fan-out shape. The os.zsh stub here uses exactly
# what an OS layer relies on Core to have left defined: _cache_eval (tools.zsh's API for
# the OS layer's gh/uv/ty inits — NOT unfunctioned like _have is), the _core_* UX
# primitives, and an alias override (the macOS rm→trash pattern). local.zsh overrides a
# Core default. If Core ever stops exporting one of those, this fails — where Section A,
# loading Core alone, would stay green.
hdr "consumer integration (Core + os/local layers, canonical loader)"
INTEG="$SANDBOX/integ"
_seed_plugin_dirs "$INTEG/plugins"
# os.zsh: realistic OS-layer file. Exercises the Core helpers an OS repo depends on;
# any reference to an undefined helper prints to stderr (the failure signal below).
cat >"$INTEG/os.zsh" <<'OSZSH'
# stub os.zsh — must be able to use the API Core promises the OS layer.
(( $+functions[_cache_eval] )) || print -u2 "os.zsh: _cache_eval missing (tools.zsh API gone)"
(( $+functions[_core_ok]    )) || print -u2 "os.zsh: _core_ok missing (ui.zsh API gone)"
# the documented gh/uv/ty pattern: _cache_eval a tool AFTER options.zsh set NO_CLOBBER.
# The generator must emit SOURCEABLE zsh (real tools emit an init script); a comment is
# a valid no-op init and proves the generate→cache→source path works under NO_CLOBBER.
_cache_eval faketool printf '# faketool cached init (integration stub)\n' >/dev/null
alias rm='rm -i'   # OS layer overriding a safety net (macOS does rm→trash here)
OSZSH
# local.zsh: machine-specific overrides (identity/toggles). Overriding a Core default
# is the whole reason it loads LAST.
cat >"$INTEG/local.zsh" <<'LOCALZSH'
# stub local.zsh — last word on this machine.
UPDATE_CHECK_ENABLED=0
LOCALZSH
{
  printf 'for _m in %s; do source "$CORE_DIR/$_m.zsh"; done\n' "${CORE_MODULES[*]}"
  printf 'source "$ZDOTDIR/os.zsh"\n'
  printf 'source "$ZDOTDIR/local.zsh"\n'
  printf 'print -r -- "INTEG_OK"\n'
} >"$INTEG/.zshrc"
integ_out="$(
  HOME="$SANDBOX" CORE_DIR="$CORE_DIR" \
    XDG_CACHE_HOME="$SANDBOX/integ-cache" XDG_STATE_HOME="$SANDBOX/integ-state" \
    XDG_RUNTIME_DIR="$SANDBOX/run" MISE_TRUSTED_CONFIG_PATHS="$HERE" \
    zsh -f -i -c "ZDOTDIR='$INTEG'; source \"\$ZDOTDIR/.zshrc\"" 2>"$INTEG/integ.err"
)"
integ_errs="$(grep -Ei \
  'command not found|parse error|: no such file or directory|not defined|missing|bad pattern|bad math expression|maximum nested' \
  "$INTEG/integ.err" 2>/dev/null || true)"
if ! printf '%s' "$integ_out" | grep -q '^INTEG_OK$'; then
  fail "consumer load (Core+os+local) did not reach the end — a layer aborted"
  [[ -s "$INTEG/integ.err" ]] && sed 's/^/    /' "$INTEG/integ.err" >&2
elif [[ -n "$integ_errs" ]]; then
  fail "errors during consumer load (Core→OS contract broken):"
  printf '%s\n' "$integ_errs" | sed 's/^/    /' >&2
else
  pass "Core + os + local loaded in canonical order (Core→OS contract holds)"
fi

# ── B. function unit tests ────────────────────────────────────────────────────
hdr "function unit tests (functions.zsh)"
FN="$HERE/zsh/functions.zsh"
# functions.zsh now routes its errors through ui.zsh's _core_* helpers, so the
# unit shell must source ui.zsh FIRST — the same ordering the real loader uses
# (tools → ui → … → functions). It loads before functions in every assertion below.
UI="$HERE/zsh/ui.zsh"

# Run an assertion under zsh; $1 = label, $2 = zsh body that must exit 0.
# On FAILURE we capture the child's combined stdout+stderr and print it INDENTED
# (mirroring the nvim/smoke sections above) — a red unit test must say WHY, not just
# its label, or a CI failure that fans out to 9 repos forces a local re-reproduction.
# On PASS the output is discarded, so the expected _core_err/usage noise stays silent.
check() { # check <label> <zsh-body>
  local out
  if out="$(HOME="$SANDBOX" zsh -fc "source '$UI' || exit 1; source '$FN' || exit 1; $2" 2>&1)"; then
    pass "$1"
  else
    fail "$1"
    [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
}

# Like check, but SKIP (not fail) when a required external tool is absent — so the
# archive round-trip tests degrade gracefully on a bare box, mirroring the linter
# skips above. extract's own first branch is `ouch` when HAVE_OUCH is set; under
# `zsh -fc` that var is unset, so these exercise the hand-rolled case fallback.
check_dep() { # check_dep <label> <dep> <zsh-body>
  if ! have "$2"; then
    skip "$1 ($2 not installed)"
    return
  fi
  local out
  if out="$(HOME="$SANDBOX" zsh -fc "source '$UI' || exit 1; source '$FN' || exit 1; $3" 2>&1)"; then
    pass "$1"
  else
    fail "$1"
    [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
}

check "mkcd creates and enters a nested dir" \
  'd=$(mktemp -d); cd "$d"; mkcd a/b/c; [[ ${PWD:t} == c && -d "$d/a/b/c" ]]'
check "cdup climbs N directories" \
  'd=$(mktemp -d); mkdir -p "$d/a/b/c"; cd "$d/a/b/c"; cdup 2; [[ ${PWD:t} == a ]]'
# Defensive input guards (U1): a bad count / missing file / bad port must be REJECTED
# in Core's voice (non-zero), not silently no-op or handed to cp/python to fail raw.
check "cdup rejects a non-numeric count" \
  'cdup abc 2>/dev/null; (( $? != 0 ))'
check "cdup rejects a zero count" \
  'cdup 0 2>/dev/null; (( $? != 0 ))'
check "mkbak writes a timestamped .bak copy" \
  'd=$(mktemp -d); cd "$d"; print hi > f; mkbak f; set -- f.*.bak; [[ -f $1 ]]'
check "mkbak's .bak is byte-identical to the original" \
  'd=$(mktemp -d); cd "$d"; print -r -- payload > f; mkbak f; set -- f.*.bak; [[ -f $1 && "$(cat -- $1)" == payload ]]'
check "mkbak rejects a missing file" \
  'mkbak /no/such/file 2>/dev/null; (( $? != 0 ))'
check "mkbak with no argument is rejected" \
  'mkbak 2>/dev/null; (( $? != 0 ))'
# U6: a second backup must NOT clobber an existing .bak and must NOT prompt. Pre-create
# the timestamped target, then run mkbak with stdin closed: collision-safe means a SECOND
# .bak appears (≥2 total); had `cp -i` bled in, the closed stdin would abort the copy (1).
# Robust to the same-second/next-second race either way (distinct name OR distinct suffix).
check "mkbak never clobbers an existing .bak (collision-safe, non-interactive)" \
  'd=$(mktemp -d); cd "$d"; print hi > f; ts=$(date +%Y%m%d-%H%M%S); : > "f.$ts.bak"; mkbak f </dev/null >/dev/null 2>&1; n=$(print -l -- f.*.bak(N) | wc -l); (( n >= 2 ))'
check "serve rejects a non-numeric port" \
  'serve abc 2>/dev/null; (( $? != 0 ))'
check "serve rejects an out-of-range port" \
  'serve 99999 2>/dev/null; (( $? != 0 ))'
# serve -l/--local (#10): the loopback flag must be ACCEPTED as a flag (not mis-read as
# the port) while the port is still validated, and an unknown flag must be rejected — all
# before python ever binds, so these stay non-blocking.
check "serve rejects an unknown flag (-l/--local is the only flag)" \
  'serve --nope 2>/dev/null; (( $? != 0 ))'
check "serve -l is parsed as a flag and still validates the port" \
  'serve -l abc 2>/dev/null; (( $? != 0 ))'
# Uniform -h/--help contract (U6): every user-facing verb answers --help on STDOUT
# and returns 0 (a help REQUEST is success, not misuse). This also guards the bugs
# where --help used to be mis-read as an operand — serve as a bad port, extract as a
# missing file (both returned non-zero); the guard must short-circuit before that.
check "mkcd --help prints usage to stdout and returns 0" \
  'out=$(mkcd --help); (( $? == 0 )) && [[ $out == *"usage: mkcd"* ]]'
check "serve --help returns 0 (not mis-read as a bad port)" \
  'out=$(serve --help); (( $? == 0 )) && [[ $out == *"usage: serve"* ]]'
check "extract -h returns 0 (not mis-read as a missing file)" \
  'out=$(extract -h); (( $? == 0 )) && [[ $out == *"usage: extract"* ]]'
# pullall (#git): the parent dir is configurable, so input is validated in Core's
# voice — a non-directory and a bad PULLALL_JOBS are both REJECTED before any find/
# xargs runs. --help is the usual STDOUT-and-return-0 contract. The repo-less-dir
# case exercises the full find→xargs→summary pipeline hermetically (no network, no
# .git, so the workers exit early) and asserts the summary card + a clean exit.
check "pullall --help prints usage to stdout and returns 0" \
  'out=$(pullall --help); (( $? == 0 )) && [[ $out == *"usage: pullall"* ]]'
check "pullall rejects a non-directory parent" \
  'pullall /no/such/dir 2>/dev/null; (( $? != 0 ))'
check "pullall rejects a non-numeric PULLALL_JOBS" \
  'PULLALL_JOBS=x pullall "$(mktemp -d)" 2>/dev/null; (( $? != 0 ))'
check "pullall on a repo-less dir prints the summary and returns 0" \
  'd=$(mktemp -d); mkdir "$d/a" "$d/b"; out=$(pullall "$d" 2>&1); (( $? == 0 )) && [[ $out == *"pullall summary"* && $out == *"updated:  0"* ]]'
# Integration (the bulk of the logic the validation tests above don't reach): build a
# bare remote + a behind clone hermetically (mirrors the gcheck git_* tests below — a
# throwaway $GIT_AUTHOR_* identity and git init in mktemp), advance the remote, then run
# pullall and assert it fast-forwarded the clone (tally "updated: 1", a real new file on
# disk, zero failures). This exercises trunk auto-detection, the --ff-only pull, and the
# ✅ tally — the per-repo path that fans out to all 9 OS repos.
check_dep "pullall fast-forwards a behind repo and tallies it (hermetic bare remote)" git \
  'export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e
   w=$(mktemp -d)
   git -c init.defaultBranch=main init -q --bare "$w/remote.git"
   git -c init.defaultBranch=main clone -q "$w/remote.git" "$w/seed"
   ( cd "$w/seed" && print -r -- one > a.txt && git add a.txt && git commit -q -m one && git push -q -u origin main )
   mkdir -p "$w/parent"
   git clone -q "$w/remote.git" "$w/parent/repoA"
   ( cd "$w/seed" && print -r -- two > b.txt && git add b.txt && git commit -q -m two && git push -q origin main )
   out=$(pullall "$w/parent" 2>&1)
   [[ $out == *"updated:  1"* && $out == *"failed:   0"* && -f "$w/parent/repoA/b.txt" ]]'
# The riskier path this PR added: a NON-fast-forward pull ($pull != 0) that ALSO hits a
# stash-pop conflict must report ❌ "pull failed AND a conflict …" and count as a failure,
# NOT a ⚠️ that claims the trunk was updated. Construct it hermetically: diverge the clone
# (local main commit) and the remote (a different commit) so --ff-only fails, then sit on a
# feature branch (forked from before the divergence) with a conflicting uncommitted change
# so the auto-stash pop conflicts after checkout. Asserts the gate + the failure tally.
check_dep "pullall reports a combined pull-failure + stash-pop conflict as a ❌" git \
  'export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e
   w=$(mktemp -d)
   git -c init.defaultBranch=main init -q --bare "$w/remote.git"
   git -c init.defaultBranch=main clone -q "$w/remote.git" "$w/seed"
   ( cd "$w/seed" && print -r -- base > x.txt && git add x.txt && git commit -q -m base && git push -q -u origin main )
   mkdir -p "$w/parent"
   git clone -q "$w/remote.git" "$w/parent/repoA"
   ( cd "$w/seed" && print -r -- remotemain > x.txt && git commit -q -am remotemain && git push -q origin main )
   ( cd "$w/parent/repoA" && print -r -- localmain > x.txt && git commit -q -am localmain && git checkout -q -b feature main~1 && print -r -- dirty > x.txt )
   out=$(pullall "$w/parent" 2>&1)
   [[ $out == *"failed:   1"* && $out == *"pull failed AND a conflict"* ]]'
# core-version (#4): reports the vendored Core stamp so an OS repo can tell WHICH Core
# it carries. $_CORE_VERSION_FILE resolves (via %x) to this repo's core.version here.
check "core-version prints the vendored SemVer stamp" \
  'out=$(core-version); (( $? == 0 )) && [[ $out == "dotfiles-core "[0-9]* ]]'
check "core-version --help returns 0 (not mis-read)" \
  'out=$(core-version --help); (( $? == 0 )) && [[ $out == *"usage: core-version"* ]]'
# core-doctor (#9): the shell-side health report. Must render and return 0 even on a
# bare box (every tool ✗) — it's read-only diagnostics, never a hard failure.
check "core-doctor renders a health report and returns 0" \
  'out=$(NO_COLOR=1 core-doctor 2>&1); (( $? == 0 )) && [[ $out == *dotfiles-core* && $out == *"modern CLI"* ]]'
check "core-doctor --help returns 0 (not mis-read)" \
  'out=$(core-doctor --help); (( $? == 0 )) && [[ $out == *"usage: core-doctor"* ]]'
# core-doctor --json (B12): a machine-readable object on stdout that actually parses and
# carries the tools/wired/resolved keys — so a statusline/editor/CI can consume health.
check "core-doctor --json emits parseable JSON with tools/wired/resolved" \
  'out=$(core-doctor --json); print -r -- "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); assert set([\"version\",\"tools\",\"wired\",\"resolved\"]) <= set(d)"'
# _core_wired (U1): presence != wired. The probe is true ONLY when the integration's hook
# function is actually defined in this shell, and false for an idle/unknown one — that gap
# is exactly what the doctor's "integrations wired" line surfaces.
check "_core_wired detects an integration once its hook function exists" \
  'starship_precmd() { :; }; _core_wired starship'
check "_core_wired is false for an idle integration and an unknown name" \
  '_core_wired starship 2>/dev/null; (( $? != 0 )); _core_wired bogustool 2>/dev/null; (( $? != 0 ))'
# core-help (U5): the width-aware renderer must emit every verb and never crash on its
# kw arithmetic — including a pathologically narrow terminal where the key column clamps.
check "core-help renders all verbs (wide terminal)" \
  'out=$(COLUMNS=120 core-help 2>&1); (( $? == 0 )) && [[ $out == *mkcd* && $out == *"maint-install"* && $out == *serve* ]]'
check "core-help renders cleanly on a pathologically narrow terminal" \
  'out=$(COLUMNS=12 core-help 2>&1); (( $? == 0 )) && [[ $out == *mkcd* ]]'
# core-help <filter> (U4): a term shows ONLY matching rows (and drops the section
# scaffolding); an unmatched term reports it instead of printing an empty sheet.
check "core-help <term> filters to matching rows only" \
  'out=$(COLUMNS=120 core-help serve 2>&1); (( $? == 0 )) && [[ $out == *serve* && $out != *"maint-install"* ]]'
check "core-help reports when a filter matches nothing" \
  'out=$(COLUMNS=120 core-help zzzznope 2>&1); (( $? == 0 )) && [[ $out == *"no entries match"* ]]'
# U8: the git alias set (git.zsh) is now discoverable from the cheat sheet — the full
# view carries the git section, and a filter still narrows to a specific git row.
check "core-help surfaces the git alias section in the full sheet" \
  'out=$(COLUMNS=120 NO_COLOR=1 core-help 2>&1); (( $? == 0 )) && [[ $out == *"git (most-used"* && $out == *gpf* ]]'
check "core-help can filter to a git alias row" \
  'out=$(COLUMNS=120 NO_COLOR=1 core-help gpf 2>&1); (( $? == 0 )) && [[ $out == *gpf* && $out != *"maint-install"* ]]'
# Section-aware filter: a SECTION name (the completion offers these) surfaces its whole
# group even though the word appears in no row key/desc — e.g. `core-help keybindings`.
check "core-help filters by section name (keybindings → its rows, not others)" \
  'out=$(COLUMNS=120 NO_COLOR=1 core-help keybindings 2>&1); (( $? == 0 )) && [[ $out == *Ctrl-T* && $out != *"maint-install"* ]]'
check "core-help --help returns 0 (not mis-read as a filter)" \
  'out=$(core-help --help); (( $? == 0 )) && [[ $out == *"usage: core-help"* ]]'
# core umbrella dispatcher (B1): bare `core` is the cheat sheet (U6 — help, not an
# error), subcommands route to the core-* family, and an unknown subcommand fails in
# Core's voice with a did-you-mean against $_CORE_SUBCMDS.
check "core (no args) prints the cheat sheet (U6: bare core is help, not an error)" \
  'out=$(COLUMNS=120 core 2>&1); (( $? == 0 )) && [[ $out == *mkcd* && $out == *serve* ]]'
check "core help <term> routes to core-help and filters" \
  'out=$(COLUMNS=120 core help serve 2>&1); (( $? == 0 )) && [[ $out == *serve* && $out != *"maint-install"* ]]'
check "core version routes to core-version" \
  'out=$(core version); (( $? == 0 )) && [[ $out == "dotfiles-core "[0-9]* ]]'
check "core doctor routes to core-doctor" \
  'out=$(NO_COLOR=1 core doctor 2>&1); (( $? == 0 )) && [[ $out == *"modern CLI"* ]]'
check "core rejects an unknown subcommand with a did-you-mean" \
  'out=$(core verzion 2>&1); (( $? != 0 )) && [[ $out == *"did you mean core version"* ]]'
# U5: a usage error points back at the discoverability surface — `see: core-help <verb>`,
# the verb derived from the synopsis's first token, so every verb gets it for free.
check "usage errors carry a 'see: core-help <verb>' footer (U5)" \
  'out=$(serve 99999 2>&1); (( $? != 0 )) && [[ $out == *"see: core-help serve"* ]]'
check "the U5 usage footer is suppressible via CORE_USAGE_HINT=0" \
  'out=$(CORE_USAGE_HINT=0 serve 99999 2>&1); (( $? != 0 )) && [[ $out != *"see: core-help"* ]]'
# _core_suggest did-you-mean (U3/U1): nearest candidate on a near typo; SILENT when
# nothing is close or the input is too short to be a confident match.
check "_core_suggest returns the nearest flag for a near typo" \
  'out=$(_core_suggest --locl -l --local); [[ $out == "--local" ]]'
check "_core_suggest stays silent when nothing is close" \
  'out=$(_core_suggest zzzzzz -l --local); [[ -z $out ]]'
# Damerau/OSA (U12): an adjacent transposition scores 1, NOT 2 as plain Levenshtein would —
# guards the transposition path so a regression can't silently fall back to plain edit
# distance (which would drop near-miss suggestions like gts→gst back below the cutoff).
check "_core_lev scores an adjacent transposition as 1 (Damerau, not plain Levenshtein 2)" \
  '[[ $(_core_lev gts gst) == 1 ]]'
check "_core_suggest catches a transposition typo (gts → gst)" \
  'out=$(_core_suggest gts gst gco gaa); [[ $out == gst ]]'
# _core_errbox (U8): a ✗ headline line plus dim INDENTED body lines (plain when piped).
check "_core_errbox renders a headline and indented body lines" \
  'out=$(_core_errbox head why fix 2>&1); L=("${(@f)out}"); (( ${#L} == 3 )) && [[ ${L[1]} == *head* && ${L[2]} == "    why" && ${L[3]} == "    fix" ]]'
# _core_hint width-aware wrapping (U9): a known narrow width wraps with the
# continuation aligned under the text; an UNKNOWN width (non-tty, COLUMNS=0 here) must
# NOT wrap, so captured/logged hints stay one line (no regression for the other tests).
check "_core_hint stays one line when the terminal width is unknown" \
  'out=$(_core_hint install fzf, then retry 2>&1); L=("${(@f)out}"); (( ${#L} == 1 )) && [[ $out == *"hint: install"* ]]'
check "_core_hint wraps a long hint at a narrow COLUMNS with aligned continuation" \
  'out=$(COLUMNS=40 _core_hint alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima 2>&1); L=("${(@f)out}"); (( ${#L} >= 2 )) && [[ ${L[1]} == "  hint: "* && ${L[2]} == "        "* ]]'
check "extract rejects a non-existent file" \
  'extract /no/such/archive.tar.gz; (( $? != 0 ))'
check "extract rejects a known file of unknown format" \
  'd=$(mktemp -d); cd "$d"; : > mystery.qqq; extract mystery.qqq; (( $? != 0 ))'
check_dep "extract round-trips a .tar.gz" tar \
  'd=$(mktemp -d); cd "$d"; mkdir src; print -r -- hi > src/a.txt; tar czf a.tgz src; rm -rf src; extract a.tgz; [[ -f src/a.txt && "$(cat -- src/a.txt)" == hi ]]'
check_dep "extract round-trips a .gz" gzip \
  'd=$(mktemp -d); cd "$d"; print -r -- hi > f.txt; gzip f.txt; extract f.txt.gz; [[ -f f.txt && "$(cat -- f.txt)" == hi ]]'
# Defensive guards (U4): a multi-entry "tarbomb" must be flagged (with no TTY the
# contain-prompt declines and it extracts in place — both files land, we warned), and
# an extract that WOULD clobber an existing entry must abort untouched rather than
# silently overwrite. _core_confirm declining on no-TTY is what makes both deterministic.
check_dep "extract warns on a tarbomb but still unpacks (no TTY)" tar \
  'd=$(mktemp -d); cd "$d"; print x > one; print y > two; tar czf bomb.tgz one two; rm one two; extract bomb.tgz </dev/null; [[ -f one && -f two ]]'
check_dep "extract refuses to clobber an existing entry (no TTY)" tar \
  'd=$(mktemp -d); cd "$d"; mkdir src; print new > src/a.txt; tar czf a.tgz src; print OLD > src/a.txt; extract a.tgz </dev/null; rc=$?; [[ "$(cat -- src/a.txt)" == OLD && $rc -ne 0 ]]'
# gz/bz2 write NEXT TO the archive path, not into $PWD: `extract /dir/f.gz` must guard
# /dir/f, not ./f. Run it from a DIFFERENT cwd so a basename-only check would miss the
# clobber and overwrite (the bug this asserts against).
check_dep "extract guards the gz output at the archive's path, not \$PWD" gzip \
  'd=$(mktemp -d); sub="$d/sub"; mkdir -p "$sub"; print new > "$sub/f.txt"; gzip "$sub/f.txt"; print OLD > "$sub/f.txt"; cd "$d"; extract "$sub/f.txt.gz" </dev/null; rc=$?; [[ "$(cat -- "$sub/f.txt")" == OLD && $rc -ne 0 ]]'

# ── E. detection + UX unit tests (ui.zsh / update.zsh / maint.zsh) ────────────
# Sections A/B and audit-core.sh's static pass leave the highest-LOGIC, highest
# fan-out helpers unproven: the package-manager and scheduler detection LADDERS
# (which differ per distro and silently mis-fire) and ui.zsh's defensive no-TTY
# confirm. A regression in any of these ships to all 9 OS repos — exactly what a
# behavioral gate must catch. Each is driven HERMETICALLY against a stubbed PATH
# (the same technique the clip ladder in section C uses), so the result is
# deterministic on every CI userland (glibc / BSD / musl) regardless of what's
# actually installed there.
hdr "detection + UX unit tests (ui / update / maint)"
_real_zsh="$(command -v zsh)"
UPD="$HERE/zsh/update.zsh"
MNT="$HERE/zsh/maint.zsh"
# A fake bin dir holding ONE stub command, used to pin a detection ladder's answer.
PMBIN="$SANDBOX/pmbin"
_pm_only() {
  rm -rf "$PMBIN"
  mkdir -p "$PMBIN"
  [[ -n "${1:-}" ]] && {
    printf '#!/bin/sh\n:\n' >"$PMBIN/$1"
    chmod +x "$PMBIN/$1"
  }
}

# Run a zsh assertion that must exit 0; on failure print the captured output indented
# (same diagnostics contract as check() above). Trailing args are `VAR=VAL` env prefixes
# applied to the child — used to isolate PATH for the detection ladders. Runs INTERACTIVE
# (-i): update.zsh gates its whole body behind `[[ $- == *i* ]]`, so a non-interactive
# `-fc` would source to a no-op. `$_real_zsh` (absolute) keeps zsh reachable even when
# the test isolates PATH down to the stub dir.
ucheck() { # ucheck <label> <zsh-body> [VAR=VAL ...]
  local label="$1" body="$2"
  shift 2
  local out
  if out="$(HOME="$SANDBOX" env "$@" "$_real_zsh" -fic "$body" 2>&1)"; then
    pass "$label"
  else
    fail "$label"
    [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
}

# ui.zsh: _core_confirm is DEFENSIVE — with no controlling TTY (captured run, stdin
# redirected) it must DECLINE (non-zero), so wrapping a destructive action (please/up)
# in it is fail-safe in a pipe/cron/CI context instead of blocking or assuming yes.
ucheck "ui: _core_confirm declines with no TTY (fail-safe)" \
  "source '$UI'; _core_confirm 'x' </dev/null; (( \$? != 0 ))"

# ui.zsh: _core_spin must return the WRAPPED command's exit code (the non-TTY path
# runs it directly) — the contract plugins.zsh's first-run installer relies on to know
# a clone step failed. true → 0, false → non-zero.
ucheck "ui: _core_spin propagates the wrapped command's exit code" \
  "source '$UI'; _core_spin t true 2>/dev/null && ! _core_spin t false 2>/dev/null"

# ui.zsh: _core_nap is the spinner's per-frame delay primitive — it must return 0
# (the while-loop relies on it not aborting) and complete promptly via zselect WITHOUT
# forking a fractional `sleep` that busybox may reject. We can't time it portably here,
# but asserting it succeeds exercises the zselect path on every CI userland (glibc/musl)
# — the bare-box regression the old literal `sleep 0.1` risked. Driven without a TTY.
ucheck "ui: _core_nap completes and returns 0 (zselect tick, no fractional sleep fork)" \
  "source '$UI'; _core_nap; (( \$? == 0 ))"

# functions.zsh: the command-not-found handler (U1) is defined ONLY in an interactive
# shell (ucheck runs -fic), and on a near typo it must suggest the closest Core verb in
# Core's voice rather than zsh's terse default. extarct → extract is a 1-transposition miss.
ucheck "fn: command_not_found_handler suggests the nearest Core verb on a typo" \
  "source '$UI'; source '$FN'; out=\$(extarct foo 2>&1); [[ \$out == *'did you mean extract'* ]]"

# update.zsh: _pkgup_mgr must pick the manager that's actually on PATH. Isolate PATH to
# a lone apt-get stub (so the brew/pacman/dnf/zypper arms above it all miss) and disable
# the two background startup hooks, so the answer is deterministic on any runner.
_pm_only apt-get
ucheck "update: _pkgup_mgr detects apt from an isolated PATH" \
  "source '$UPD'; [[ \$(_pkgup_mgr) == apt ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# …and reports `none` when NO supported manager is reachable (the silent-stay path).
_pm_only ""
ucheck "update: _pkgup_mgr reports none on a bare PATH" \
  "source '$UPD'; [[ \$(_pkgup_mgr) == none ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# up --help must print usage and return 0 WITHOUT attempting an update — the bug the
# help guard fixes (it used to fall through, not being -y, and run the upgrade). Run
# on a bare PATH so a regressed guard reaching _pkgup_mgr → none → returns 1, failing
# this test loudly instead of silently passing.
_pm_only ""
ucheck "update: up --help returns 0 and does not attempt an update" \
  "source '$UI'; source '$UPD'; out=\$(up --help); (( \$? == 0 )) && [[ \$out == *'usage: up'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# up's pre-confirm PREVIEW: _pkgup_list surfaces the upgradable package NAMES (the
# count is already in the nudge) so `up` shows what will change before the destructive
# sync. Stub apt-get's `-s upgrade` simulate output; mgr pins to apt via isolated PATH.
rm -rf "$PMBIN"
mkdir -p "$PMBIN"
printf '#!/bin/sh\ncase "$*" in *"-s upgrade"*) printf "Inst foo [1.0] (1.1)\\nInst bar [2.0] (2.1)\\n";; esac\n' >"$PMBIN/apt-get"
chmod +x "$PMBIN/apt-get"
# The apt arm pipes to awk; the isolated PATH has only the stub, so symlink the real
# awk in (like the clip ladder symlinks bash/tr). It's not a package manager, so
# _pkgup_mgr still resolves to apt — the isolation we want.
ln -s "$(command -v awk)" "$PMBIN/awk"
ucheck "update: _pkgup_list surfaces upgradable package names (apt)" \
  "source '$UPD'; out=\$(_pkgup_list); [[ \$out == *foo* && \$out == *bar* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# REGRESSION (prompt_subst): _pkgup_notice prints its 'run up to apply' nudge via
# `print -P`. Under `setopt prompt_subst` (starship and any substitution prompt enable
# it) print -P performs command substitution on a backtick'd word — so a literal \`up\`
# in the string would RUN the up function at prompt-paint time. The nudge fires from a
# precmd hook BEFORE up() is even defined, surfacing as "command not found: up" (and, once
# defined, silently triggering a privileged upgrade prompt every shell). Define an up()
# sentinel, enable prompt_subst, seed a positive cached count, and assert the rendered
# nudge MENTIONS up but never EXECUTED it.
ucheck "update: _pkgup_notice nudge is prompt_subst-safe (mentions up, never runs it)" \
  "source '$UPD'; setopt prompt_subst; up(){ print RAN_UP }; mkdir -p \${_PKGUP_CACHE:h}; print -rl -- 3 \$EPOCHSECONDS >| \$_PKGUP_CACHE; out=\$(_pkgup_notice); [[ \$out == *\"run 'up'\"* && \$out != *RAN_UP* ]]" \
  XDG_CACHE_HOME="$SANDBOX/psubst-notice" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# up --dry-run (#8): the non-destructive inspect — list what WOULD upgrade and exit 0,
# applying nothing. Same apt stub as above; assert the names print and the rc is 0.
ucheck "update: up --dry-run lists pending packages and exits 0 (applies nothing)" \
  "source '$UI'; source '$UPD'; out=\$(up --dry-run); (( \$? == 0 )) && [[ \$out == *foo* && \$out == *bar* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# up strict flag parsing: every arg is parsed (not just $1), so an unknown flag is
# REJECTED in Core's voice (rc 1 — the verb-layer usage-error convention, same as
# serve/mkcd/…) instead of silently falling through to a real, privileged update —
# and -y/-n together (apply vs inspect-only) is refused as contradictory. Both
# rejections happen BEFORE _pkgup_mgr, so the manager doesn't matter.
ucheck "update: up rejects an unknown flag (rc 1, does not attempt an update)" \
  "source '$UI'; source '$UPD'; out=\$(up --bogus 2>&1); (( \$? == 1 )) && [[ \$out == *'unexpected argument'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "update: up refuses -y and -n together (mutually exclusive, rc 1)" \
  "source '$UI'; source '$UPD'; out=\$(up -y -n 2>&1); (( \$? == 1 )) && [[ \$out == *'mutually exclusive'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# up -i interactive selection (U2): contracts checked BEFORE any privileged apply.
# (a) -i is mutually exclusive with -y/-n; (b) with NO picker it errbox-names fzf/gum;
# (c) with a picker but no TTY it declines for the terminal; (d) --help advertises -i.
# (b)/(c) are kept DISTINCT so the message never conflates the two (Copilot, PR #15).
ucheck "update: up refuses -i with -y (three-way mutual exclusion, rc 1)" \
  "source '$UI'; source '$UPD'; out=\$(up -i -y 2>&1); (( \$? == 1 )) && [[ \$out == *'mutually exclusive'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# (b) no fzf AND no gum on the isolated PATH → the picker errbox, not a TTY/cancel message.
ucheck "update: up -i names fzf/gum when no picker is installed" \
  "source '$UI'; source '$UPD'; out=\$(up -i </dev/null 2>&1); (( \$? == 1 )) && [[ \$out == *'needs fzf or gum'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# (c) stub a picker (fzf) onto the isolated PATH so the picker check passes; a non-TTY run
# must then decline with the TERMINAL message — proving the two failure modes are separate.
printf '#!/bin/sh\n:\n' >"$PMBIN/fzf"
chmod +x "$PMBIN/fzf"
ucheck "update: up -i with a picker present still declines without a TTY" \
  "source '$UI'; source '$UPD'; out=\$(up -i </dev/null 2>&1); (( \$? == 1 )) && [[ \$out == *'needs an interactive terminal'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
rm -f "$PMBIN/fzf"
ucheck "update: up --help advertises -i/--interactive" \
  "source '$UI'; source '$UPD'; out=\$(up --help); (( \$? == 0 )) && [[ \$out == *'-i'* && \$out == *interactive* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# up -i must REFUSE on full-sync-only managers (pacman/emerge/apk): a partial upgrade there
# risks a broken system, so the safety model (documented in update.zsh) forbids it. Stub a
# pacman-only PATH so _pkgup_mgr resolves to it, then assert the refusal + rc 1.
_pm_only pacman
ucheck "update: up -i refuses on pacman (full-sync-only safety, rc 1)" \
  "source '$UI'; source '$UPD'; out=\$(up -i 2>&1); (( \$? == 1 )) && [[ \$out == *'does not support safe partial upgrades'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# core-help context-awareness (U7): a row whose tool is ABSENT on this box must be
# tagged "needs <tool>", while an always-on verb (mkcd) still renders normally. Drive
# it on a bare PATH so fzf is guaranteed missing, making the assertion deterministic.
_pm_only ""
ucheck "core-help annotates an unavailable tool (needs fzf when fzf absent)" \
  "source '$UI'; source '$FN'; out=\$(COLUMNS=120 NO_COLOR=1 core-help); [[ \$out == *'needs fzf'* && \$out == *mkcd* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# fzf.zsh verbs (fif/fbr) must degrade in Core's voice on a bare box — a raw "command
# not found" is the bug this guards (fcd already did; fif/fbr/zoxide-jump did not).
# Drive on an isolated PATH (fzf guaranteed absent) so the error path is deterministic.
FZF_FILE="$HERE/zsh/fzf.zsh"
_pm_only ""
ucheck "fif rejects cleanly without fzf (Core error voice, not 'command not found')" \
  "source '$UI'; source '$FZF_FILE' 2>/dev/null; out=\$(fif foo 2>&1); (( \$? != 0 )) && [[ \$out == *'fif: requires fzf'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "fbr rejects cleanly without fzf (Core error voice, not 'command not found')" \
  "source '$UI'; source '$FZF_FILE' 2>/dev/null; out=\$(fbr 2>&1); (( \$? != 0 )) && [[ \$out == *'fbr: requires fzf'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# zle-widget graceful degradation (regression gate for the Ctrl-T/Ctrl-R bare-box bug):
# both are bound UNCONDITIONALLY in bindings.zsh, so on a box without fzf/fd their widget
# bodies must warn in Core's voice and repaint — NOT leak a raw "command not found" (the
# class of bug fif/fbr/Alt-Z already guard; Ctrl-T/Ctrl-R lacked it). `zle` is stubbed to a
# no-op so `zle reset-prompt` is callable outside an active ZLE; PATH is isolated so fzf/fd
# are guaranteed absent. Alt-Z is asserted too, locking in the parity across all three.
_pm_only ""
ucheck "Ctrl-T widget degrades in Core's voice without fzf/fd (no 'command not found')" \
  "source '$UI'; source '$FZF_FILE' 2>/dev/null; zle() { : }; FD_BIN=''; out=\$(_fzf_file_no_hidden 2>&1); (( \$? != 0 )) && [[ \$out == *'Ctrl-T: needs'* && \$out != *'command not found'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "Ctrl-R widget degrades in Core's voice without fzf (no 'command not found')" \
  "source '$UI'; source '$FZF_FILE' 2>/dev/null; zle() { : }; out=\$(_fzf_history_clean 2>&1); (( \$? != 0 )) && [[ \$out == *'Ctrl-R: needs'* && \$out != *'command not found'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "Alt-Z widget degrades in Core's voice without zoxide/fzf (no 'command not found')" \
  "source '$UI'; source '$FZF_FILE' 2>/dev/null; zle() { : }; out=\$(_fzf_zoxide_jump 2>&1); (( \$? != 0 )) && [[ \$out == *'Alt-Z: needs'* && \$out != *'command not found'* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# Colour degradation (U8): the nudge/welcome accents must drop from 24-bit hex to a
# 256-colour code when the terminal doesn't advertise truecolor — so a 16/256-colour
# TTY never receives a raw 24-bit escape. Assert both arms of the $COLORTERM gate.
ucheck "update: accents degrade to 256-colour without truecolor" \
  "source '$UPD'; [[ \$_PKGUP_ACCENT == 75 && \$_PKGUP_MUTED == 244 ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0 COLORTERM=
ucheck "update: accents use truecolor hex when COLORTERM advertises it" \
  "source '$UPD'; [[ \$_PKGUP_ACCENT == '#7aa2f7' ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0 COLORTERM=truecolor

# maint.zsh: _maint_scheduler must always resolve to a REAL scheduler token, never empty
# or garbage. With systemctl absent (isolated PATH) and crontab present as the fallback,
# it lands on cron (Linux/Alpine) or launchd (macOS, OSTYPE-driven) — both valid — so the
# assertion is the same green on every CI userland while still exercising the full ladder.
_pm_only crontab
ucheck "maint: _maint_scheduler resolves to a valid scheduler" \
  "source '$UI'; source '$MNT'; [[ \$(_maint_scheduler) == (systemd|launchd|cron) ]]" \
  PATH="$PMBIN"
# maint-log defensive input (#6): a non-numeric N must be rejected in Core's voice, not
# handed to `tail` to fail with a raw "invalid number". -f/--follow and a positive int
# are the only valid args (mirrors serve/cdup/mkbak's input guards).
ucheck "maint: maint-log rejects a non-numeric N in Core's voice" \
  "source '$UI'; source '$MNT'; out=\$(maint-log abc 2>&1); (( \$? != 0 )) && [[ \$out == *'maint-log: N must be'* ]]" \
  PATH="$PMBIN"

# ── maint scheduler artifacts (systemd unit / launchd plist / cron line) ──────
# maint-install GENERATES a systemd unit+timer, a launchd plist (XML), and a cron line —
# fan-out artifacts that, until now, had NO gate: a malformed OnCalendar, a broken plist,
# or a bad cron field only fails on the user's box, then fans out to 9 repos. Every OTHER
# fan-out artifact class is gated (toml/yaml/json §6, workflows actionlint §8); this closes
# the maint hole the same way. Hermetic: override _maint_scheduler to pick the branch,
# stub systemctl/launchctl/crontab to no-ops (so nothing touches the real system), sandbox
# HOME/XDG, render at 09:30, then VALIDATE the generated artifact. The runner path resolves
# to this repo's maint/dotfiles-maint.sh via maint.zsh's %x, so the [[ -f ]] guard passes.
hdr "maint scheduler artifacts (systemd / launchd / cron, hermetic render)"
SCHEDBIN="$SANDBOX/schedbin"
mkdir -p "$SCHEDBIN"
for s in systemctl launchctl; do
  printf '#!/bin/sh\n:\n' >"$SCHEDBIN/$s"
  chmod +x "$SCHEDBIN/$s"
done
# crontab stub: `-l` prints nothing (no existing table); `-` captures the new table to a
# file so we can assert the generated line instead of mutating the real crontab.
printf '#!/bin/sh\ncase "$1" in -l) exit 0 ;; -) cat > "$CRON_CAPTURE" ;; *) exit 0 ;; esac\n' >"$SCHEDBIN/crontab"
chmod +x "$SCHEDBIN/crontab"

# systemd: the timer's OnCalendar must be the rendered HH:MM, and the service must point
# ExecStart at the runner. Override the scheduler so the branch runs on any host.
ucheck "maint: systemd timer+service render with a valid OnCalendar" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo systemd }; maint-install 09:30 >/dev/null 2>&1; ud=\"\$XDG_CONFIG_HOME/systemd/user\"; [[ -f \"\$ud/dotfiles-maint.timer\" && -f \"\$ud/dotfiles-maint.service\" ]] || exit 1; grep -q 'OnCalendar=\*-\*-\* 09:30:00' \"\$ud/dotfiles-maint.timer\" || exit 1; grep -q 'ExecStart=.*dotfiles-maint.sh' \"\$ud/dotfiles-maint.service\"" \
  PATH="$SCHEDBIN:$PATH" XDG_CONFIG_HOME="$SANDBOX/sched-systemd"
# cron: the captured table line must be a well-formed 5-field schedule at MM HH, tagged.
ucheck "maint: cron line renders as a valid 5-field schedule" \
  "source '$UI'; source '$MNT'; _maint_scheduler() { echo cron }; maint-install 09:30 >/dev/null 2>&1; [[ -f \"\$CRON_CAPTURE\" ]] || exit 1; grep -qE '^30 09 \* \* \* .*dotfiles-maint\.sh # dotfiles-maint\$' \"\$CRON_CAPTURE\"" \
  PATH="$SCHEDBIN:$PATH" CRON_CAPTURE="$SANDBOX/cron.captured"
# launchd: the plist must be WELL-FORMED XML (plistlib parses it) with the rendered
# Hour/Minute — the one artifact that's silent text the other gates never inspect. Needs
# python3 (stdlib plistlib); skip gracefully otherwise, like the linters above.
if have python3; then
  ucheck "maint: launchd plist is well-formed XML with the rendered Hour/Minute" \
    "source '$UI'; source '$MNT'; _maint_scheduler() { echo launchd }; maint-install 09:30 >/dev/null 2>&1; p=\"\$HOME/Library/LaunchAgents/com.dotfiles.maint.plist\"; [[ -f \"\$p\" ]] || exit 1; python3 -c 'import sys,plistlib; d=plistlib.load(open(sys.argv[1],\"rb\")); s=d[\"StartCalendarInterval\"]; sys.exit(0 if s[\"Hour\"]==9 and s[\"Minute\"]==30 else 1)' \"\$p\"" \
    PATH="$SCHEDBIN:$PATH" HOME="$SANDBOX/sched-launchd"
else
  skip "maint launchd plist (python3 absent — cannot parse plist XML)"
fi

# update.zsh: the first-run welcome (U2 — the cheat-sheet discoverability hint) must
# greet EXACTLY ONCE per machine. Drive _core_welcome directly (the TTY gate lives at
# its call site, so a captured run can exercise the greet+sentinel logic): first call
# prints the `core` front-door pointer and persists the sentinel; a second call is silent.
# An isolated XDG_STATE_HOME keeps the sentinel out of the shared sandbox.
ucheck "update: _core_welcome greets once, then the sentinel silences it" \
  "source '$UPD'; o1=\$(_core_welcome); [[ \$o1 == *\"run 'core'\"* ]] || exit 1; [[ -e \$XDG_STATE_HOME/dotfiles-core/.welcomed ]] || exit 1; o2=\$(_core_welcome); [[ -z \$o2 ]]" \
  XDG_STATE_HOME="$SANDBOX/welcome-once" NO_COLOR=1 UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
# …and the startup hook stays SILENT without an interactive tty (captured/piped/CI):
# sourcing update.zsh prints no greet and writes no sentinel, so it never spams logs.
ucheck "update: welcome stays silent (no greet, no sentinel) without a tty" \
  "o=\$(source '$UPD'); [[ \$o != *'dotfiles Core loaded'* && ! -e \$XDG_STATE_HOME/dotfiles-core/.welcomed ]]" \
  XDG_STATE_HOME="$SANDBOX/welcome-notty" NO_COLOR=1 UPDATE_CHECK_ENABLED=0 CORE_WELCOME=1

# completions (U3 / DERIVED regression gate): every first-party PUBLIC verb must have a
# #compdef that compinit resolves off the vendored fpath dir — a missing/typo'd tag
# means no tab-completion for that command across all 9 repos, with nothing else to
# catch it. The verb set is DERIVED from the source (top-level functions whose names
# don't start with `_`, Core's private-helper convention) minus an explicit allowlist
# of public-but-non-completable functions: the zsh-vi-mode init HOOK, the git-alias
# helpers, and the internal plugin updater — none are user verbs. So a NEW verb shipped
# WITHOUT a completion now FAILS here — the regression the OLD hardcoded list couldn't
# catch (it silently omitted update-check + opssh, which had no completion at all). This
# mirrors audit-core.sh's META_ALLOWLIST pattern: derive from the tree, exempt by name.
# `cheat` (alias → core-help) is appended so the aliased #compdef tag is exercised too.
COMP_ALLOWLIST=" git_main_branch git_current_branch zvm_after_init zplugin-update "
COMP_VERBS=()
while IFS= read -r _v; do
  case " $COMP_ALLOWLIST " in *" $_v "*) continue ;; esac
  COMP_VERBS+=("$_v")
done < <(grep -rhoE '^(function[[:space:]]+)?[A-Za-z][A-Za-z0-9_-]*\(\)|^function[[:space:]]+[A-Za-z][A-Za-z0-9_-]*[[:space:]]*\{' "$HERE"/zsh/*.zsh |
  sed -E 's/^function[[:space:]]+//; s/\(\).*//; s/[[:space:]]*\{.*//' |
  grep -vE '^_' | sort -u)
COMP_VERBS+=(cheat)
ucheck "completions: every first-party verb has a compinit-resolved completion (derived)" \
  "fpath=('$HERE/zsh/completions' \$fpath); autoload -Uz compinit && compinit -u -d '$SANDBOX/zcd-comp' >/dev/null 2>&1; for c in ${COMP_VERBS[*]}; do [[ -n \${_comps[\$c]:-} ]] || { print \"no completion registered for: \$c\"; exit 1; }; done"

# core-help coverage (B2): the cheat sheet is a HAND-MAINTAINED rows=() array — so a new
# verb is trivially forgotten and the one discoverability surface silently drifts from
# reality, with nothing to catch it across 9 repos. Derive the public-verb set from the
# source (same technique as the completion gate above), then assert each appears in the
# RENDERED core-help output (rows OR the footer line, where the op/health/front-door verbs
# live). `cheat` is the alias and `core` is the dispatcher whose own help IS the sheet —
# both exempt. A verb shipped without a sheet entry now FAILS here. ui.zsh + functions.zsh
# are sourced so core-help renders; NO_COLOR keeps the match on plain text.
HELP_ALLOWLIST=" $COMP_ALLOWLIST cheat core "
HELP_VERBS=()
for _v in "${COMP_VERBS[@]}"; do
  case "$HELP_ALLOWLIST" in *" $_v "*) continue ;; esac
  HELP_VERBS+=("$_v")
done
ucheck "core-help lists every first-party verb (derived B2 coverage gate)" \
  "source '$UI'; source '$FN'; sheet=\$(COLUMNS=200 core-help 2>&1); for v in ${HELP_VERBS[*]}; do [[ \" \$sheet \" == *\" \$v \"* || \$sheet == *\"\$v \"* || \$sheet == *\" \$v\"* ]] || { print \"verb missing from core-help: \$v\"; exit 1; }; done" \
  NO_COLOR=1

# completion ↔ source flag drift (B7): the coverage test above proves a completion EXISTS;
# this proves its FLAGS still match the verb. Every long flag a flag-bearing completion
# advertises must still be mentioned in the verb's zsh source — so removing `--dry-run`
# from `up` (or renaming `--local`) without updating its #compdef now FAILS here instead
# of silently shipping a completion that offers a flag the verb rejects to all 9 repos.
# Pure sed+grep (busybox-safe); comment lines in the completion are stripped first.
hdr "completion ↔ source flag drift (serve, up)"
_flag_drift() { # _flag_drift <verb> <completion-file> <source-file>
  local verb="$1" comp="$2" src="$3" f flags miss=0
  flags="$(sed 's/^[[:space:]]*#.*//' "$comp" | grep -oE -- '--[a-z][a-z-]+' | sort -u)"
  for f in $flags; do
    grep -q -- "$f" "$src" || {
      fail "completion '$verb' advertises $f, absent from $src (drift)"
      miss=1
    }
  done
  ((miss)) || pass "completion '$verb' flags all still present in its source"
}
_flag_drift serve "$HERE/zsh/completions/_serve" "$HERE/zsh/functions.zsh"
_flag_drift up "$HERE/zsh/completions/_up" "$HERE/zsh/update.zsh"

# ── git helper unit tests (git.zsh) (B2) ──────────────────────────────────────
# git.zsh's trunk/branch resolution (git_main_branch's 6-way ref search, git_current_branch's
# detached-HEAD fallback) is real logic that branch-aware aliases (gcom/grbm/gpu) ride on and
# that fans out to 9 repos — yet it was the ONE shell module with no behavioral coverage (only
# `zsh -n`). Drive each helper against throwaway repos, hermetic: HOME → sandbox and git config
# pinned to /dev/null so the host's init.defaultBranch can't skew the result. Skips without git.
hdr "git helper unit tests (git.zsh)"
if ! have git; then
  skip "git helpers (git not installed)"
else
  GITZSH="$HERE/zsh/git.zsh"
  gcheck() { # gcheck <label> <zsh-body that must exit 0>
    local out
    if out="$(HOME="$SANDBOX" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e \
      zsh -fc "source '$GITZSH' || exit 1; $2" 2>&1)"; then
      pass "$1"
    else
      fail "$1"
      [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/    /' >&2
    fi
  }
  gcheck "git_current_branch reads the checked-out branch" \
    'd=$(mktemp -d); cd "$d"; git -c init.defaultBranch=main init -q .; [[ $(git_current_branch) == main ]]'
  gcheck "git_current_branch falls back to a short SHA on detached HEAD" \
    'd=$(mktemp -d); cd "$d"; git -c init.defaultBranch=main init -q .; git commit -q --allow-empty -m x; git checkout -q --detach HEAD; [[ -n $(git_current_branch) ]]'
  gcheck "git_current_branch is empty outside a repo" \
    'd=$(mktemp -d); cd "$d"; [[ -z $(git_current_branch) ]]'
  gcheck "git_main_branch resolves main when present" \
    'd=$(mktemp -d); cd "$d"; git -c init.defaultBranch=main init -q .; git commit -q --allow-empty -m x; [[ $(git_main_branch) == main ]]'
  gcheck "git_main_branch resolves master when that is the trunk" \
    'd=$(mktemp -d); cd "$d"; git -c init.defaultBranch=master init -q .; git commit -q --allow-empty -m x; [[ $(git_main_branch) == master ]]'
  gcheck "git_main_branch defaults to master when no known trunk exists" \
    'd=$(mktemp -d); cd "$d"; git -c init.defaultBranch=main init -q .; git commit -q --allow-empty -m x; git branch -m weirdtrunk; [[ $(git_main_branch) == master ]]'
fi

# ── update.zsh per-manager parse (B5) ─────────────────────────────────────────
# The detection LADDER is covered above (apt), but _pkgup_count/_pkgup_list use a DISTINCT
# grep/awk heuristic PER manager — and only apt had a test. A regex that miscounts a header
# or blank row would ship silently to that one distro's repo. Pin each: isolate PATH to a
# lone manager stub (+ the coreutils its pipeline forks) so _pkgup_mgr resolves to it, feed
# canned `outdated` output, and assert the parsed count/names. Mirrors the apt stub above.
hdr "update.zsh per-manager parse (apk / dnf / zypper / pacman)"
_mgr_stub() { # _mgr_stub <mgr> <sh-body>
  rm -rf "$PMBIN"
  mkdir -p "$PMBIN"
  printf '#!/bin/sh\n%s\n' "$2" >"$PMBIN/$1"
  chmod +x "$PMBIN/$1"
  local t
  for t in grep awk sort cut sed; do
    [[ -e "$PMBIN/$t" ]] || ln -s "$(command -v "$t")" "$PMBIN/$t" 2>/dev/null
  done
}
_mgr_stub apk 'case "$*" in *"list -u"*) printf "a-1.0 ...\nb-2.0 ...\nc-3.0 ...\n" ;; esac'
ucheck "update: _pkgup_count parses apk (3 upgradable)" \
  "source '$UPD'; [[ \$(_pkgup_count) == 3 ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "update: _pkgup_list parses apk package names" \
  "source '$UPD'; out=\$(_pkgup_list); [[ \$out == *a-1.0* && \$out == *c-3.0* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
_mgr_stub dnf 'case "$*" in *check-update*) printf "bash.x86_64    5.1-2    baseos\nvim.x86_64    9.0-1    appstream\n" ;; esac'
ucheck "update: _pkgup_count parses dnf check-update (2 upgradable)" \
  "source '$UPD'; [[ \$(_pkgup_count) == 2 ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "update: _pkgup_list parses dnf package names" \
  "source '$UPD'; out=\$(_pkgup_list); [[ \$out == *bash.x86_64* && \$out == *vim.x86_64* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
_mgr_stub zypper 'case "$*" in *list-updates*) printf "v | repo | bash | 1 | 2 | x86_64\nv | repo | vim | 1 | 2 | x86_64\n" ;; esac'
ucheck "update: _pkgup_count parses zypper list-updates (2 upgradable)" \
  "source '$UPD'; [[ \$(_pkgup_count) == 2 ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "update: _pkgup_list parses zypper package names" \
  "source '$UPD'; out=\$(_pkgup_list); [[ \$out == *bash* && \$out == *vim* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
_mgr_stub pacman 'case "$*" in *-Qu*) printf "bash 5.1.0\nvim 9.0.0\n" ;; esac'
ucheck "update: _pkgup_count parses pacman -Qu (2 upgradable)" \
  "source '$UPD'; [[ \$(_pkgup_count) == 2 ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0
ucheck "update: _pkgup_list parses pacman package names" \
  "source '$UPD'; out=\$(_pkgup_list); [[ \$out == *bash* && \$out == *vim* ]]" \
  PATH="$PMBIN" UPDATE_CHECK_ENABLED=0 CORE_WELCOME=0

# ── op.zsh 1Password helpers (B7) ─────────────────────────────────────────────
# op.zsh fans out to 9 repos and handles SECRETS, yet had zero behavioral coverage. The
# module short-circuits (returns) unless `op` is on PATH, so we stub a fake `op` (echoes
# its args) + a fake `clip` (captures stdin) on an isolated PATH — the same hermetic
# technique as the clip ladder — and assert the verbs' input-guards, the op:// path
# construction, and optoken's clip dependency. No real 1Password, no network, no secrets.
hdr "op.zsh 1Password helpers (hermetic stubs)"
OPZSH="$HERE/zsh/op.zsh"
OPBIN="$SANDBOX/opbin"
_op_reset() { # _op_reset [with-clip]
  rm -rf "$OPBIN"
  mkdir -p "$OPBIN"
  ln -s "$_real_zsh" "$OPBIN/zsh" 2>/dev/null
  # fake op: print the OTP for `item get --otp`, a table for `item list`, else echo args.
  cat >"$OPBIN/op" <<'OPSTUB'
#!/bin/sh
case "$*" in
*"item get"*--otp*) echo 123456 ;;
*"item list"*) printf 'NAME\tKEY\nmykey\tabc\n' ;;
*) printf 'op %s\n' "$*" ;;
esac
OPSTUB
  chmod +x "$OPBIN/op"
  if [[ "${1:-}" == with-clip ]]; then
    printf '#!/bin/sh\ncat >/dev/null\n' >"$OPBIN/clip"
    chmod +x "$OPBIN/clip"
  fi
}
# ocheck: source ui+op under a PATH that includes the op stub, run a body, expect exit 0.
ocheck() { # ocheck <label> <zsh-body> [extra PATH entries already in OPBIN]
  local out
  if out="$(PATH="$OPBIN:$PATH" HOME="$SANDBOX" "$_real_zsh" -fc "source '$UI'||exit 1; source '$OPZSH'||exit 1; $2" 2>&1)"; then
    pass "$1"
  else
    fail "$1"
    [[ -n "$out" ]] && printf '%s\n' "$out" | sed 's/^/    /' >&2
  fi
}
if ! have zsh; then
  skip "op.zsh helpers (zsh not installed)"
else
  _op_reset with-clip
  # input guards: a missing required arg is a usage error (rc 1), in Core's voice.
  ocheck "opsecret with no arg is a usage error" 'opsecret 2>/dev/null; (( $? != 0 ))'
  ocheck "openv with no arg is a usage error" 'openv 2>/dev/null; (( $? != 0 ))'
  ocheck "optoken with no arg is a usage error" 'optoken 2>/dev/null; (( $? != 0 ))'
  # op:// path construction: opsecret <path> must call `op read op://<path>` verbatim.
  ocheck "opsecret builds the op:// read path" \
    'out=$(opsecret Personal/AWS/key); [[ $out == *"op read op://Personal/AWS/key"* ]]'
  # optoken copies the OTP via clip and confirms — present clip → success + the ok line.
  ocheck "optoken fetches the OTP and copies it via clip" \
    'out=$(optoken Personal/GitHub 2>&1); (( $? == 0 )) && [[ $out == *"TOTP copied"* ]]'
  ocheck "opssh lists stored SSH keys (rc 0)" \
    'out=$(opssh 2>&1); (( $? == 0 )) && [[ $out == *mykey* ]]'
  # uniform --help contract: each op verb answers --help on stdout, rc 0.
  ocheck "opsecret --help returns 0 with usage" \
    'out=$(opsecret --help); (( $? == 0 )) && [[ $out == *"usage: opsecret"* ]]'
  # optoken's clip dependency (U4 errbox): with NO clip on PATH it must fail in Core's
  # voice (rc 1) rather than silently swallow the TOTP down a broken pipe.
  _op_reset # no clip this time
  ocheck "optoken fails clearly when clip is absent (no silent TOTP loss)" \
    'path=(/usr/bin /bin); out=$(optoken Personal/GitHub 2>&1); (( $? != 0 )) && [[ $out == *"requires Core"* && $out == *clip* ]]'
fi

# ── tmux status/popup scripts (U11) ───────────────────────────────────────────
# The tmux helper scripts fan out to 9 repos and were covered only by bash -n + shellcheck
# (static). Their PORTABILITY CONTRACT — "emit a styled pill when there's something to show,
# emit NOTHING (segment vanishes) otherwise" — is pure logic that a bad edit could break
# silently (a status helper that errors blanks the whole bar). Drive the two data-driven
# ones hermetically against a stubbed PATH (same technique as the clip ladder): a fake
# `pmset`/`ip` pins the environment so the output is deterministic on every box.
hdr "tmux status/popup scripts (battery / netinfo, hermetic)"
TMUXBIN="$SANDBOX/tmuxbin"
BATTERY="$HERE/tmux/scripts/tmux-battery.sh"
NETINFO="$HERE/tmux/scripts/tmux-netinfo.sh"
_tmux_stub() { # _tmux_stub <name> <sh-body>
  rm -rf "$TMUXBIN"
  mkdir -p "$TMUXBIN"
  printf '#!/bin/sh\n%s\n' "$2" >"$TMUXBIN/$1"
  chmod +x "$TMUXBIN/$1"
}
# battery: a stubbed macOS `pmset` (87%, discharging) must yield a pill carrying "87%" —
# guarding the awk %-extraction the script's header explains (tmux mangles a literal '%').
_tmux_stub pmset 'printf -- "-InternalBattery-0 (id=1)\t87%%; discharging; 4:32 remaining present: true\n"'
out="$(PATH="$TMUXBIN:$PATH" bash "$BATTERY" 2>/dev/null)"
if [[ "$out" == *"87%"* && "$out" == *"#[fg="* ]]; then
  pass "tmux-battery renders a pill from pmset (87%)"
else fail "tmux-battery did not render the expected 87% pill (got: $out)"; fi
# netinfo: a tunnel iface up → an ORANGE pill naming the iface + addr.
_tmux_stub ip 'case "$*" in *"addr show tun0"*) echo "2: tun0 inet 10.8.0.2/24 scope global tun0" ;; esac'
out="$(PATH="$TMUXBIN:$PATH" bash "$NETINFO" 2>/dev/null)"
if [[ "$out" == *"tun0"* && "$out" == *"10.8.0.2"* ]]; then
  pass "tmux-netinfo renders the tunnel pill when a tun iface is up"
else fail "tmux-netinfo tunnel pill missing (got: $out)"; fi
# netinfo: no tunnel but a routable LAN → a GREEN pill with the LAN IP.
_tmux_stub ip 'case "$*" in *"route get"*) echo "1.1.1.1 via 192.168.1.1 dev en0 src 192.168.1.50 uid 0" ;; esac'
out="$(PATH="$TMUXBIN:$PATH" bash "$NETINFO" 2>/dev/null)"
if [[ "$out" == *"192.168.1.50"* ]]; then
  pass "tmux-netinfo falls back to the LAN pill"
else fail "tmux-netinfo LAN pill missing (got: $out)"; fi
# netinfo: nothing reachable → NOTHING printed (the segment vanishes — the portability
# contract that keeps it safe to ship to every repo). A non-empty output here is the bug.
_tmux_stub ip ':'
out="$(PATH="$TMUXBIN:$PATH" bash "$NETINFO" 2>/dev/null)"
if [[ -z "$out" ]]; then
  pass "tmux-netinfo emits nothing when no tunnel/LAN (segment vanishes)"
else fail "tmux-netinfo should be silent with no net, printed: $out"; fi

# ── summary ───────────────────────────────────────────────────────────────────
summary
((FAIL == 0)) || {
  { [[ "$NESTED" == 1 ]] || ((JSON)); } || printf '%stests FAILED%s\n' "$c_red" "$c_rst" >&2
  exit 1
}
{ [[ "$NESTED" == 1 ]] || ((JSON)); } || printf '%stests OK%s\n' "$c_grn" "$c_rst"
