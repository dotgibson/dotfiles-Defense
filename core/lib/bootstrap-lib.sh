# shellcheck shell=bash
# core/lib/bootstrap-lib.sh — shared BASH provisioning scaffold for OS bootstraps.
# ──────────────────────────────────────────────────────────────────────────────
# ONE definition of the symlink/loader/login-shell scaffold that every OS repo's
# bootstrap.sh used to hand-roll. Before this, ~half of each of the seven Linux/role
# bootstrap.sh files was the SAME code — link(), read_pkgs(), WSL detection, the big
# Core-symlink loop, the .zshrc loader heredoc, the default-shell logic — copy-pasted
# and then independently reformatted (tabs vs spaces), so a fix to any of it had to be
# made seven times by hand. That is exactly the N-way drift the Core layer exists to
# kill, leaking back through the one file that can't be vendored. This is the fix:
# the shared half lives here, vendored under core/lib/, and each bootstrap.sh shrinks
# to its genuinely OS-specific part (the package install) plus calls into these helpers.
#
# zsh/05-ui.zsh is the zsh-runtime UX lib; lib/ux.sh is its bash sibling; this is the bash
# PROVISIONING sibling. Like ux.sh it IS vendored into every OS repo (it's in
# core.manifest) precisely so bootstrap.sh — which runs before any zsh config — can
# `source core/lib/bootstrap-lib.sh` instead of duplicating it.
#
# SOURCED, not run: no shebang, mode 100644 (the audit's exec-bit section asserts this
# for lib/*.sh, the bash sibling of the sourced zsh/*.zsh modules). bash 3.2-safe (macOS):
# no associative arrays, no mapfile, no ${x,,}.
#
# CHICKEN-AND-EGG: the core/ subtree presence check CANNOT move here — you can't source
# a lib out of core/ before confirming core/ exists. Each bootstrap.sh keeps that one
# guard inline (three lines), then sources lib/ux.sh + this file and calls in.
#
# Messaging uses lib/ux.sh's UX_* palette when it has been sourced first (the intended
# order), and degrades to plain/no-colour when it hasn't — so this file has no hard
# ordering dependency on ux.sh.
#
# Usage (in an OS bootstrap.sh):
#   source "$DOTFILES/core/lib/ux.sh"
#   source "$DOTFILES/core/lib/bootstrap-lib.sh"
#   blib_is_wsl && IS_WSL=1
#   wire_links() {
#     blib_link_core      "$DOTFILES" "$CONFIG"
#     blib_link_os_layer  "$DOTFILES" "$CONFIG" fedora
#     blib_write_zshrc_loader        # param-less (v4): the loader globs the numbered fragments
#     blib_set_login_shell
#   }
#   provision() {
#     # Reads install/packages.txt into the caller's own array, so a missing or unreadable
#     # list is a REAL failure rather than an empty array with a success status (#460).
#     # Prefer this over `mapfile -t pkgs < <(blib_read_pkgs …)`, which discards the status.
#     blib_read_pkgs_into pkgs "$DOTFILES/install/packages.txt" || exit 1
#     ((${#pkgs[@]})) && dnf install -y "${pkgs[@]}"
#   }
# ──────────────────────────────────────────────────────────────────────────────

[[ -n "${_CORE_BOOTSTRAP_LIB_SH:-}" ]] && return 0
_CORE_BOOTSTRAP_LIB_SH=1

# ── dry-run + tallies ─────────────────────────────────────────────────────────
# BLIB_DRY=1 makes the mutating helpers (blib_link / blib_seed / blib_link_core /
# blib_write_zshrc_loader / blib_set_login_shell) PRINT what they WOULD do and change
# nothing — so a bootstrap's `--dry-run` previews the full plan. Default off, so every
# existing caller is byte-for-byte unaffected. The BLIB_* counters accumulate across a
# run; blib_wire_summary prints them. (MacBook adopts these so its --dry-run survives.)
BLIB_LINKED=0 BLIB_SEEDED=0 BLIB_BACKED=0 BLIB_RELINKED=0 BLIB_SKIPPED=0
_blib_dry() { [[ "${BLIB_DRY:-0}" != 0 ]]; }

# ── messages ──────────────────────────────────────────────────────────────────
# Thin wrappers over the UX_* palette (set by lib/ux.sh). When ux.sh wasn't sourced,
# UX_* expand empty and these stay plain — no hard dependency, no colour codes leak.
blib_say()  { printf '%s::%s %s\n'   "${UX_BLU:-}"  "${UX_RST:-}" "$*"; }
blib_ok()   { printf '%s%s%s %s\n'   "${UX_GRN:-}"  "${UX_OK:-+}"   "${UX_RST:-}" "$*"; }
blib_warn() { printf '%s%s%s %s\n'   "${UX_YEL:-}"  "${UX_WARN:-!}" "${UX_RST:-}" "$*" >&2; }

# ── WSL detection ─────────────────────────────────────────────────────────────
# Returns 0 on WSL (so callers do `blib_is_wsl && IS_WSL=1`). The same probe every
# bootstrap used: the WSL_DISTRO_NAME env first, then the microsoft/wsl marker in
# /proc/version (covers a login that didn't inherit the env).
# The zsh sibling is _core_is_wsl (core/zsh/00-tools.zsh), which is fork-free because it
# runs on every interactive shell; the grep here is fine because bootstrap runs once, in
# bash, before any shell layer exists to source. Keep the two rules in step — they answer
# the same question and a box where they disagree is a bug.
blib_is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" ]] && return 0
  grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null
}

# ── displaced-file backup naming ──────────────────────────────────────────────
# _blib_backup_suffix — the ONE definition of the `.pre-dotfiles.*` suffix every writer
# in the fleet appends. It had been open-coded three times in two different formats:
# blib_link and the .zshrc loader used `date +%s`, while the `link()` helper
# scripts/new-os-repo.sh generates used `date +%Y%m%d-%H%M%S`.
#
# That broke an invariant an OS repo's `--uninstall` DOCUMENTS and depends on:
#
#     The backup suffix is a zero-padded YYYYMMDD-HHMMSS stamp, so a lexical sort IS
#     chronological — the LAST glob match is the newest.
#
# False across the pair. A 10-digit epoch (`17…`) always sorts BEFORE a `20…` datestamp,
# so a date-stamped backup wins "newest" regardless of its real age and --uninstall
# restores the OLDER file over the newer one, silently. It was latent only because the
# two writers happened to own disjoint destinations; one overlap — an OS repo wiring a
# path Core also wires — and it fires (#464).
#
# So: ONE format, and it is the sortable one. A datestamp also has the edge over an epoch
# for a file a human is meant to find and identify on disk.
#
# The `.$$` tail is the second half of #464: both formats resolved to one SECOND and both
# writers use a bare `mv`, so two backups of the same destination inside one second
# overwrote each other — unlikely by hand, easy in a test loop or a scripted re-run. The
# PID only ever tiebreaks WITHIN a second (the stamp differs otherwise), so it does not
# disturb the cross-second ordering the sort relies on.
_blib_backup_suffix() { printf 'pre-dotfiles.%s.%s' "$(date +%Y%m%d-%H%M%S)" "$$"; }

# ── symlink with backup ───────────────────────────────────────────────────────
# blib_link <src> <dst> — replace an existing SYMLINK in place; back up a real file
# to <dst>.pre-dotfiles.<stamp>.<pid> first (see _blib_backup_suffix), ANNOUNCING the
# move on stderr. Idempotent (safe to re-run a bootstrap): an
# already-correct link is a no-op. A missing src is skipped (not a dangling link).
# Honors BLIB_DRY (plan only) and updates the BLIB_* counters.
#
# The two displacement cases are deliberately NOT symmetric, and both are RECORDED:
# a real file is moved aside (restorable from disk, counted in BLIB_BACKED); a symlink
# is removed and its old target is PRINTED and counted in BLIB_RELINKED. Keeping the
# symlink case a delete avoids littering ~/.config with one stray backup link per
# fragment per run — the repos being wired are symlink farms, so a role switch
# (Offense ↔ Defense) or a moved dotfiles tree relinks nearly everything. But deleting it
# unrecorded lost the one thing worth keeping: WHERE it used to point. The early return
# above means this branch is reached ONLY when the link points somewhere else, so every
# relink notice is real information, never re-run noise (issue #430).
blib_link() {
  local src="$1" dst="$2" was="" bak=""
  if [[ ! -e "$src" ]]; then
    blib_say "skip (missing): ${src##*/}"
    BLIB_SKIPPED=$((BLIB_SKIPPED + 1))
    return 0
  fi
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    BLIB_LINKED=$((BLIB_LINKED + 1)) # already correct → no-op
    return 0
  fi
  # readlink, not realpath: a DANGLING link still reports the path it recorded, which is
  # exactly what someone migrating off a since-deleted tree needs to read afterwards.
  [[ -L "$dst" ]] && was="$(readlink "$dst")"
  if _blib_dry; then
    if [[ -L "$dst" ]]; then
      blib_say "would relink: $dst (currently -> $was)"
      BLIB_RELINKED=$((BLIB_RELINKED + 1))
    elif [[ -e "$dst" ]]; then
      blib_say "would back up + link: $dst"
      BLIB_BACKED=$((BLIB_BACKED + 1))
    else
      blib_say "would link: $dst"
    fi
    BLIB_LINKED=$((BLIB_LINKED + 1))
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" ]]; then
    blib_say "relinking $dst (was -> $was)"
    rm -f "$dst"
    BLIB_RELINKED=$((BLIB_RELINKED + 1))
  elif [[ -e "$dst" ]]; then
    # ANNOUNCE it. The move itself was always correct — the file is preserved and
    # restorable, and --uninstall can put it back — but it happened MUTELY, and blib_link
    # wires roughly 34 of ~40 destinations in an OS-repo bootstrap, so silent clobbering
    # was the overwhelmingly common case rather than an edge one (#463). The only trace
    # was an aggregate `N backed up` in the closing summary, which says THAT something was
    # displaced and never WHAT or where it went.
    #
    # The audience for this path is precisely someone migrating an existing machine onto
    # the dotfiles — the person with the most to lose and the least context. From where
    # they sit, an unannounced move means their ~/.gitconfig simply stopped being theirs;
    # recovering it means already knowing the `.pre-dotfiles.` convention exists. That the
    # recovery path EXISTS is what made the silence expensive, not cheap.
    #
    # blib_warn (stderr) rather than blib_say: this is the one wiring outcome that touched
    # a file the user owned, so it should survive a caller that pipes stdout to a log.
    bak="$dst.$(_blib_backup_suffix)"
    mv "$dst" "$bak"
    blib_warn "backed up existing $dst -> $bak"
    BLIB_BACKED=$((BLIB_BACKED + 1))
  fi
  ln -s "$src" "$dst"
  BLIB_LINKED=$((BLIB_LINKED + 1))
}

# ── seed a starter file (copy, not symlink) ───────────────────────────────────
# blib_seed <src> <dst> <note> — COPY a starter file into place ONLY when dst is absent,
# for files the user edits locally and that must never be tracked back (git identity,
# sesh layout). A present dst is left untouched (never relinked/clobbered). Honors
# BLIB_DRY and counts. This is the one definition of the seed pattern blib_link_core
# previously inlined twice.
blib_seed() {
  local src="$1" dst="$2" note="$3"
  [[ -f "$src" && ! -e "$dst" ]] || return 0
  if _blib_dry; then
    blib_say "would seed: $dst ($note)"
    BLIB_SEEDED=$((BLIB_SEEDED + 1))
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  blib_say "seeded $dst — $note"
  BLIB_SEEDED=$((BLIB_SEEDED + 1))
}

# ── adopt a config the TOOL ITSELF rewrites ───────────────────────────────────
# blib_adopt <src> <dst> <note> — like blib_seed, but it also MIGRATES an existing
# symlink at dst into a real file, and reports drift once Core moves on.
#
# Why this exists, in one sentence: a symlinked config is a WRITE PATH BACK INTO THE
# VENDORED TREE, and for a config whose own tool rewrites it, that path gets used.
#
# The case that produced this: ~/.config/mise/config.toml was symlinked to
# core/mise/config.toml, so `mise use -g ruby@4.0` — an ordinary, documented command,
# and the exact one mise's own header advertises — wrote straight THROUGH the symlink
# into vendored Core. That tree must byte-match upstream (core-integrity reports it as
# TAMPERED otherwise) and sync-core.sh refuses to fan out into a repo with a dirty tree,
# so one routine command silently took that repo out of the next fleet sync. The write
# also stripped the trailing comments explaining each pin, because mise rewrites the
# file rather than editing the line.
#
# blib_link is still right for the ~34 configs a tool only ever READS (tmux, starship,
# lazygit, vimrc): the symlink is what makes a Core edit reach every box for free, and
# nothing writes back through it. Reach for blib_adopt ONLY where the tool writes its
# own config. The `jj` config is the other live instance of that shape — `jj config set
# --user` rewrites it in place — and atuin/lazygit/tealdeer are worth re-checking.
#
# The trade this makes, stated plainly: dst stops tracking Core. A later Core edit no
# longer reaches an adopted box on its own. That is why drift is REPORTED rather than
# silently tolerated — the divergence becomes a visible, checkable condition instead of
# an invisible override, the same bargain fleet-drift.sh and core-integrity already make
# elsewhere in this repo. Reconciling is the user's call: theirs wins by default.
#
# Deliberately NOT conf.d. mise reads ~/.config/mise/conf.d/*.toml, which looks like the
# tidier home for a shared layer. It does not help, and it can REPRODUCE the bug above.
# Measured on mise 2026.5.16, isolated XDG_CONFIG_HOME, NEUTRAL cwd — mise walks up from
# the cwd, so run these from outside any repo or you will read a project config instead:
#   · conf.d OUTRANKS config.toml, in both directions. mise states this itself:
#       "lua is defined in …/conf.d/00-core.toml which overrides the global config"
#   · inside conf.d the LOWEST-numbered file wins — 00-core.toml beat 99-local.toml,
#     the REVERSE of the systemd conf.d convention almost everyone will assume
#   · read this with `mise current <tool>` or `mise which <tool>`, NOT `mise ls` /
#     `mise ls --current`: those print one line per config file, which is easy to misread
#     as a precedence answer — that misreading produced the first, wrong version of this note
#
# HOW VERIFYING THIS GOES WRONG. Both ways below were hit for real while establishing the
# above — by two people independently — so spend the two minutes:
#   · THE CWD IS THE WHOLE STORY. mise walks UP from the cwd and treats `mise/config.toml`
#     as a PROJECT config path, so a fixture root containing mise/config.toml loads that
#     file TWICE — once as the global config via XDG_CONFIG_HOME, once as a project config —
#     and PROJECT outranks global conf.d. config.toml then appears to win and the whole
#     conclusion inverts. Run from a directory with no `mise/config.toml` in ANY ancestor;
#     "a different directory" is not enough, and it looks completely fine when it is wrong.
#   · NEITHER `mise current` NOR `mise which` DETECTS THAT. Measured: under the confounded
#     cwd both report the project value and agree with each other, so cross-checking the two
#     proves nothing.
#   · `mise config ls` CATCHES ONLY THE LOUD SHAPE, so do not lean on it. There are two, and
#     only the second produced the wrong note here:
#       SHAPE 1  cwd sits in some OTHER project that has its own mise/config.toml. That file
#                is a distinct path, so `mise config ls` shows an extra entry — and in
#                practice mise refuses it outright until `mise trust`, so this shape
#                announces itself. A file-count check works here.
#       SHAPE 2  cwd sits UNDER the XDG tree itself, so the GLOBAL config.toml is ALSO
#                discovered as the project config. Same path, already trusted, no prompt —
#                `mise config ls` prints exactly your fixture count and exactly your fixture
#                paths. Nothing looks wrong, and the ordering is still inverted.
#     So the only safeguard that covers both is the cwd rule in the bullet above: no
#     `mise/config.toml` in ANY ancestor. Check that, not the file count.
#
# The hazard is WHERE `mise use -g` writes — the highest-precedence file that ALREADY
# EXISTS. With Core's pins in a conf.d file that gives two failures and no good case:
#   · fresh box, no ~/.config/mise/config.toml yet — `mise use -g lua@5.5.1` writes
#     straight INTO conf.d/00-core.toml. Where that is Core's symlink, this is the
#     original write-through bug, reproduced exactly.
#   · config.toml already present — the write lands there and is then SHADOWED by Core's
#     conf.d entry. mise does WARN, so it is not silent, but the user's global choice
#     does not take effect and the warning names two paths rather than the cause.
# A plain copy has neither failure. Verify with `mise current` before "fixing" this.
blib_adopt() {
  local src="$1" dst="$2" note="$3" was=""
  if [[ ! -f "$src" ]]; then
    blib_say "skip (missing): ${src##*/}"
    BLIB_SKIPPED=$((BLIB_SKIPPED + 1))
    return 0
  fi
  # A symlink here is a box provisioned by the OLDER layout. Migrate it: the content is
  # identical either way (it resolves to src), so this loses nothing and closes the write
  # path. readlink, not realpath — a DANGLING link still reports what it recorded, which
  # is what someone reading the log afterwards needs.
  if [[ -L "$dst" ]]; then
    was="$(readlink "$dst")"
    if _blib_dry; then
      blib_say "would adopt: $dst (currently -> $was) — $note"
      BLIB_SEEDED=$((BLIB_SEEDED + 1))
      return 0
    fi
    rm -f "$dst"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    blib_say "adopted $dst — was a symlink -> $was; now a real file you own ($note)"
    BLIB_SEEDED=$((BLIB_SEEDED + 1))
    return 0
  fi
  if [[ ! -e "$dst" ]]; then
    if _blib_dry; then
      blib_say "would seed: $dst ($note)"
      BLIB_SEEDED=$((BLIB_SEEDED + 1))
      return 0
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    blib_say "seeded $dst — $note"
    BLIB_SEEDED=$((BLIB_SEEDED + 1))
    return 0
  fi
  # dst is a real file the user owns. NEVER clobber it — just say whether it still
  # matches Core. git hash-object rather than cmp/diff: byte-exact, needs no repository,
  # and removes the diffutils dependency instead of probing for it (the #572 box had git
  # but neither cmp nor diff).
  if [[ "$(git hash-object -- "$src" 2>/dev/null)" != "$(git hash-object -- "$dst" 2>/dev/null)" ]]; then
    blib_warn "drift: $dst differs from Core's ${src##*/} — yours is kept; reconcile by hand if you want Core's version"
  fi
  return 0
}

# ── read a package list ───────────────────────────────────────────────────────
# blib_read_pkgs <file> — print one clean package name per line, stripping inline
# (#...) comments and all whitespace (package names contain none).
#
# A MISSING OR UNREADABLE FILE IS NOW AN ERROR, not silence (#460). This read with a bare
# redirect and no existence check, and every caller reaches it through a process
# substitution:
#
#     mapfile -t pkgs < <(blib_read_pkgs "$DOTFILES/install/packages.txt")
#
# `mapfile` reports the exit status of ITSELF, not of the process inside `< <( … )`. So a
# missing file left the caller holding a zero-length array WITH A SUCCESS STATUS, and two
# very different situations became indistinguishable:
#
#   · packages.txt deliberately all-comments  → "lists no packages — skipping"
#   · packages.txt MISSING FROM THE CLONE     → "lists no packages — skipping"
#
# The second is a broken checkout — an incomplete clone, a bad sync, a typo'd path — and
# it provisioned NOTHING while reporting that as intended. On a fresh machine that is the
# difference between "no extras requested" and "none of your tooling was installed". Same
# class as #459: the status of the thing that actually failed never reaches the caller.
#
# `-r`, NOT `-f`, deliberately: dotfiles-Debian passes a PROCESS SUBSTITUTION here
# (`blib_read_pkgs <(pkg_filter_lines "$base_list" "$OS_ID")`) to drop the lines annotated
# for other distros. That argument is a `/dev/fd/N` pipe, which `-f` rejects — an existence
# check written the obvious way would break a working caller.
#
# Returning non-zero is NECESSARY BUT NOT SUFFICIENT for the process-substitution form,
# which discards it regardless. Callers that need the status must move to
# blib_read_pkgs_into below, which assigns in the caller's own frame; this guard makes the
# failure LOUD (stderr) even where the status is thrown away.
blib_read_pkgs() {
  local line
  [[ -r "$1" ]] || {
    blib_warn "package list not readable: $1"
    return 1
  }
  while IFS= read -r line; do
    line="${line%%#*}"           # drop everything from the first # onward
    line="${line//[[:space:]]/}" # package names contain no whitespace
    [[ -n "$line" ]] || continue
    printf '%s\n' "$line"
  done <"$1"
  # Explicit, now that the status MEANS something: this used to end on
  # `[[ -n "$line" ]] && printf …`, whose status is the loop's status, so a list whose
  # final line was blank or a comment — the common shape — returned 1. Harmless while
  # every caller discarded it; a landmine the moment one stops.
  return 0
}

# blib_read_pkgs_into <arrayname> <file> — parse a package list into the CALLER'S OWN
# array variable, so `|| die` actually works:
#
#     blib_read_pkgs_into pkgs "$DOTFILES/install/packages.txt" || exit 1
#
# This is the robust shape the process-substitution form cannot have. `mapfile -t pkgs
# < <(blib_read_pkgs …)` runs the reader in a SUBSHELL and reports mapfile's status, so
# the reader's failure is structurally unreachable. Assigning here — in the current shell,
# with the redirect on the `while` rather than a pipe — keeps both the data and the status.
#
# Returns 1 on a missing/unreadable file (after emptying the array, so no stale contents
# survive a failed read) and 2 on a malformed array name. Accepts a `/dev/fd/N` process
# substitution exactly like blib_read_pkgs, so Debian's pkg-filter shape still works.
#
# BASH 3.2-SAFE, which rules out the two obvious implementations: `local -n` namerefs are
# 4.3 and `mapfile` is 4.0, while lib/*.sh must run on the macOS system bash (PORTABILITY.md
# §1). Hence the index-append loop and the eval. Note that under `set -u` on bash 3.2 an
# EMPTY array expansion counts as unset, so callers still want the
# `"${pkgs[@]+"${pkgs[@]}"}"` idiom used elsewhere in this file.
blib_read_pkgs_into() {
  local _name="$1" _file="$2" _line _n=0
  # Validate BEFORE the eval below. The name is spliced into an assignment, so anything
  # but a plain shell identifier is a code-injection hole rather than a typo. Rejected:
  # empty, anything with a character outside [A-Za-z0-9_], and a leading digit.
  case "$_name" in
  '' | *[!A-Za-z0-9_]* | [0-9]*)
    blib_warn "blib_read_pkgs_into: not a valid array name: $_name"
    return 2
    ;;
  esac
  # Empty FIRST, so a failed read cannot leave the caller reading a previous run's list.
  eval "$_name=()"
  [[ -r "$_file" ]] || {
    blib_warn "package list not readable: $_file"
    return 1
  }
  while IFS= read -r _line; do
    _line="${_line%%#*}"
    _line="${_line//[[:space:]]/}"
    [[ -n "$_line" ]] || continue
    # `arr[i]=$v` — bash 3.2 has no `+=` for arrays, and an assignment RHS undergoes
    # neither word splitting nor globbing, so the unquoted $_line inside the eval is safe.
    # The braces are for shellcheck (SC1087): ${_name} is the array NAME being spliced in,
    # not an array element being read.
    eval "${_name}[\$_n]=\$_line"
    _n=$((_n + 1))
  done <"$_file"
  return 0
}

# ── module selection (Track B: --only / --skip) ───────────────────────────────
# Optional filtering of the wiring GROUPS so a bootstrap can re-link a subset (e.g.
# `--only zsh,nvim`). The groups and what each covers in the link helpers below:
#   zsh    — core/zsh/*.zsh, os/<os>.zsh, <role>/<role>.zsh + <role>/templates,
#            the managed ~/.zshrc loader, login shell
#   nvim   — core/nvim, the core/vim/vimrc fallback
#   tmux   — tmux.conf/reset/scripts + tpm, os/<os>.conf, <role>/<role>.conf
#   git    — core gitconfig, os/<os>.gitconfig, the once-seeded local identity
#   prompt — starship.toml
#   tools  — lazygit, mise, jujutsu, atuin, tealdeer, bin/clip*, core/ssh/config
#            (+ ssh/os.conf), the seeded sesh config
# Default (neither BLIB_ONLY nor BLIB_SKIP set) wires EVERYTHING, so every existing
# caller is byte-for-byte unaffected. A bootstrap's arg loop routes its --only/--skip
# to blib_select; the helpers consult blib_want. bash 3.2-safe (no arrays needed).
BLIB_ONLY="" BLIB_SKIP=""
BLIB_MODULES="zsh nvim tmux git prompt tools"

# blib_select <--only|--skip> <csv> — validate VALUE (comma-separated group names with
# no empty / leading / trailing / doubled commas and no whitespace, so `zsh,,nvim`,
# `zsh,`, ``, `*` all abort) against BLIB_MODULES and record it. Aborts on a malformed
# selector or an unknown group. Called (not in a subshell) from each bootstrap so its
# `exit 1` aborts the bootstrap.
blib_select() {
  local flag="$1" csv="$2" out="" tok
  [[ "$csv" =~ ^[A-Za-z]+(,[A-Za-z]+)*$ ]] || {
    blib_warn "$flag needs comma-separated module names (no empty/extra commas), e.g. $flag zsh,nvim (valid: $BLIB_MODULES)"
    exit 1
  }
  local IFS=,
  for tok in $csv; do
    case " $BLIB_MODULES " in
      *" $tok "*) ;;
      *) blib_warn "unknown module: $tok (valid: $BLIB_MODULES)"; exit 1 ;;
    esac
    out="${out:+$out }$tok"
  done
  case "$flag" in
    --only) BLIB_ONLY="$out" ;;
    --skip) BLIB_SKIP="$out" ;;
    *) blib_warn "blib_select: unknown flag '$flag' (expected --only or --skip)"; exit 1 ;;
  esac
}

# blib_want <group> — should GROUP be wired? --only is an allowlist (wins when set);
# otherwise everything except the --skip names. Used as `if blib_want X; then …`.
blib_want() {
  if [[ -n "$BLIB_ONLY" ]]; then
    case " $BLIB_ONLY " in *" $1 "*) return 0 ;; *) return 1 ;; esac
  fi
  case " $BLIB_SKIP " in *" $1 "*) return 1 ;; *) return 0 ;; esac
}

# blib_selected_note — " (only: …)" / " (skipped: …)" suffix for a final summary line,
# empty when nothing was filtered. Mirrors blib_want's precedence: --only is an allowlist
# that WINS when set, so a --skip alongside it is ignored — report only the active mode
# (never both) to keep the closing message honest about what was actually wired.
blib_selected_note() {
  if [[ -n "$BLIB_ONLY" ]]; then
    printf ' (only: %s)' "$BLIB_ONLY"
  elif [[ -n "$BLIB_SKIP" ]]; then
    printf ' (skipped: %s)' "$BLIB_SKIP"
  fi
}

# ── one-time pre-v4 → v4 layout migration ─────────────────────────────────────
# blib_migrate_v4 <config> — bring a host installed under the pre-v4 layout up to the
# numbered-fragment + XDG-state layout. Every step is idempotent (a no-op once done),
# so it is safe to run on every bootstrap:
#   • history is now mutable STATE: move ~/.config/zsh/.zsh_history → $XDG_STATE_HOME/zsh/history
#   • a host-local override is now a numbered fragment: rename local.zsh → 99-local.zsh so
#     the loader's NN-*.zsh glob picks it up (an un-renamed local.zsh would silently stop loading)
#   • plugins are now DATA: move ~/.config/zsh/plugins → $XDG_DATA_HOME/zsh/plugins so an
#     upgraded host keeps its existing checkouts (an offline host would otherwise re-clone
#     the whole stack — and, with no network, simply lose its plugins).
#   • Core modules are now NN-name.zsh and the OS layer is 80-os.zsh: drop the stale
#     unnumbered symlinks (tools.zsh … update.zsh, os.zsh) + their .zwc so they don't linger
#     as dangling links. blib_link_core/blib_link_os_layer relink the new names right after.
#   • drop the stale pre-v4 compdump that lived in the config tree (now under $XDG_CACHE_HOME).
blib_migrate_v4() {
  local config="$1" m
  local zdir="$config/zsh"
  local state="${XDG_STATE_HOME:-$HOME/.local/state}/zsh"
  local data="${XDG_DATA_HOME:-$HOME/.local/share}/zsh"
  # history → $XDG_STATE_HOME (only when the old file exists and the new one doesn't yet). If
  # BOTH exist (a partial migration), the v4 shell reads ONLY $state/history — do NOT clobber
  # it, and do NOT silently leave the pre-v4 file to rot: warn so its lines are merged, not lost.
  if [[ -f "$zdir/.zsh_history" && ! -e "$state/history" ]]; then
    if _blib_dry; then
      blib_say "would move .zsh_history → $state/history"
    else
      mkdir -p "$state" && mv "$zdir/.zsh_history" "$state/history" && blib_ok "history moved to $state/history"
    fi
  elif [[ -f "$zdir/.zsh_history" && -e "$state/history" ]]; then
    blib_warn "both $zdir/.zsh_history (pre-v4) and $state/history exist — the v4 shell reads ONLY the latter; the pre-v4 file is left in place to merge (e.g. cat it into $state/history), not discarded."
  fi
  # local.zsh → 99-local.zsh (preserve the host's overrides under the new glob). If BOTH
  # exist (a partial/manual migration), the v4 loader sources ONLY 99-local.zsh — do NOT
  # silently orphan the old file; warn so the operator merges it rather than losing overrides.
  if [[ -e "$zdir/local.zsh" && ! -e "$zdir/99-local.zsh" ]]; then
    if _blib_dry; then
      blib_say "would rename local.zsh → 99-local.zsh"
    else
      mv "$zdir/local.zsh" "$zdir/99-local.zsh" && blib_ok "local.zsh → 99-local.zsh"
    fi
  elif [[ -e "$zdir/local.zsh" && -e "$zdir/99-local.zsh" ]]; then
    blib_warn "both local.zsh and 99-local.zsh exist in $zdir — the v4 loader sources ONLY 99-local.zsh; merge your overrides from local.zsh into it (left in place, not removed)."
  fi
  # plugins dir → $XDG_DATA_HOME (v4 moved ZPLUGINDIR out of the config tree). Move the whole
  # checkout so an upgraded host keeps its cloned plugins instead of re-cloning them (which an
  # offline host cannot do). If BOTH exist, leave the pre-v4 one in place and warn.
  if [[ -d "$zdir/plugins" && ! -e "$data/plugins" ]]; then
    if _blib_dry; then
      blib_say "would move plugins/ → $data/plugins"
    else
      mkdir -p "$data" && mv "$zdir/plugins" "$data/plugins" && blib_ok "plugins moved to $data/plugins"
    fi
  elif [[ -d "$zdir/plugins" && -e "$data/plugins" ]]; then
    blib_warn "both $zdir/plugins (pre-v4) and $data/plugins exist — v4 uses the latter; remove the stale $zdir/plugins once you have confirmed the move."
  fi
  _blib_dry && return 0
  # stale unnumbered Core module symlinks (+ their .zwc) and the old flat os.zsh.
  for m in tools ui options history aliases git functions fzf bindings plugins op maint update os; do
    [[ -L "$zdir/$m.zsh" ]] && rm -f "$zdir/$m.zsh" "$zdir/$m.zsh.zwc"
  done
  # stale pre-v4 compdump in the config tree (10-options.zsh now writes it to $XDG_CACHE_HOME).
  rm -f "$zdir/.zcompdump" "$zdir/.zcompdump.zwc"
}

# ── symlink the vendored Core surface ─────────────────────────────────────────
# blib_link_core <dotfiles> <config> — link everything Core ships, identically on
# every OS: the zsh modules, tmux base + reset + popup scripts, starship, nvim (+ the
# core/vim/vimrc fallback), lazygit, mise, jujutsu, atuin, tealdeer, git config (+ a once-seeded
# local identity), the cross-OS bin/clip* helpers, the ssh client config, a once-seeded
# sesh config, and a one-time tpm clone. Keep this in step with the group list at the
# top of this file — that is the canonical enumeration. OS-specific overlays
# (os/<os>.*, ssh/os.conf) are NOT here — call blib_link_os_layer for those.
blib_link_core() {
  local dotfiles="$1" config="$2" f s tpm_log

  # ── zsh — the Core module chain (os/<os>.zsh comes from blib_link_os_layer) ──
  if blib_want zsh; then
    blib_migrate_v4 "$config"   # one-time pre-v4 → v4 layout migration (idempotent)
    blib_say "symlinking Core zsh modules"
    # v4: Core modules are numbered fragments (core/zsh/NN-name.zsh). The glob still links
    # them by basename into $config/zsh flat; the loader globs NN-*.zsh there.
    for f in "$dotfiles"/core/zsh/*.zsh; do
      blib_link "$f" "$config/zsh/$(basename "$f")"
    done
  fi

  # ── nvim — the config tree + the stock-vim fallback (core/vim/vimrc -> ~/.vimrc) ─
  if blib_want nvim; then
    [[ -d "$dotfiles/core/nvim" ]] && blib_link "$dotfiles/core/nvim" "$config/nvim"
    [[ -f "$dotfiles/core/vim/vimrc" ]] && blib_link "$dotfiles/core/vim/vimrc" "$HOME/.vimrc"
  fi

  # ── tmux — base + reset + popup scripts + a one-time tpm clone ────────────────
  if blib_want tmux; then
    [[ -f "$dotfiles/core/tmux/tmux.conf" ]] && blib_link "$dotfiles/core/tmux/tmux.conf" "$config/tmux/tmux.conf"
    [[ -f "$dotfiles/core/tmux/tmux.reset.conf" ]] && blib_link "$dotfiles/core/tmux/tmux.reset.conf" "$config/tmux/tmux.reset.conf"
    # tmux popup + status scripts — symlink the DIR (not per-file) so a script added upstream
    # wires itself on the next sync, and ensure they're runnable. Deliberately not enumerating
    # the bindings here: this comment named "prefix w/T/f" and had already fallen behind `?`.
    if [[ -d "$dotfiles/core/tmux/scripts" ]]; then
      blib_link "$dotfiles/core/tmux/scripts" "$config/tmux/scripts"
      _blib_dry || chmod +x "$dotfiles"/core/tmux/scripts/*.sh 2>/dev/null || true
    fi
    # tmux plugin manager (tpm) — clone once so the theme + resurrect/continuum load.
    # Plugins still need one install pass: `prefix + I` in tmux.
    if [[ ! -d "$config/tmux/plugins/tpm" ]]; then
      if _blib_dry; then
        blib_say "would clone tpm (tmux plugin manager)"
      else
        blib_say "cloning tpm (tmux plugin manager)"
        # Announce a FAILED clone as a failure, not as a status line. This branch used
        # blib_say — the same blue `::` on stdout as the "cloning tpm" line above — and
        # discarded git's error with `>/dev/null 2>&1`, so behind a proxy tmux ended up
        # with no plugin manager and nothing in the log stood out. blib_note_fail warns on
        # STDERR and records the step, so a bootstrap that folds in the tally can decline
        # to call the run clean (the caller's own --strict / exit-code policy decides).
        #
        # Capture combined output instead of dropping it: on success it is noise, on
        # failure it is the entire diagnosis (DNS, proxy, TLS, rate limit).
        if tpm_log="$(git clone --depth=1 https://github.com/tmux-plugins/tpm "$config/tmux/plugins/tpm" 2>&1)"; then
          blib_ok "tpm cloned — run prefix + I in tmux to install plugins"
        else
          blib_note_fail "tpm clone failed — tmux will start with no plugins; clone it by hand, then press prefix + I"
          printf '%s\n' "$tpm_log" | sed 's/^/    /' >&2 # git's own error, under the failure
        fi
      fi
    fi
  fi

  # ── prompt — starship theme at the DEFAULT path (00-tools.zsh inits starship against
  # ~/.config/starship.toml with no STARSHIP_CONFIG). ──────────────────────────
  if blib_want prompt; then
    [[ -f "$dotfiles/core/starship/starship.toml" ]] && blib_link "$dotfiles/core/starship/starship.toml" "$config/starship.toml"
  fi

  # ── git — Core gitconfig + the once-seeded local identity (os/<os>.gitconfig comes
  # from blib_link_os_layer). ──────────────────────────────────────────────────
  if blib_want git; then
    [[ -f "$dotfiles/core/git/gitconfig" ]] && blib_link "$dotfiles/core/git/gitconfig" "$HOME/.gitconfig"
    # seeded ONCE (copied, never tracked back, never relinked) via the shared blib_seed.
    blib_seed "$dotfiles/core/git/local.gitconfig.example" "$config/git/local.gitconfig" \
      "FILL IN your name & email"
  fi

  # ── tools — lazygit, mise, jujutsu, atuin, tealdeer, the cross-OS bin/clip*
  #    helpers, ssh, the seeded sesh config ──────────────────────────────────────
  if blib_want tools; then
    # lazygit tokyonight theme — DEFAULT path (reached via the `lg` alias + the
    # `prefix + g` tmux popup). In core.manifest, so it wires like starship above.
    [[ -f "$dotfiles/core/lazygit/config.yml" ]] && blib_link "$dotfiles/core/lazygit/config.yml" "$config/lazygit/config.yml"
    # mise — ADOPTED (real file), not symlinked, because mise REWRITES this file:
    # `mise use -g <tool>@<ver>` is documented in the config's own header, and through a
    # symlink it wrote into vendored core/ and stripped the pin comments on the way. See
    # blib_adopt for the full reasoning, the drift trade, and why conf.d is the wrong fix.
    [[ -f "$dotfiles/core/mise/config.toml" ]] && blib_adopt "$dotfiles/core/mise/config.toml" "$config/mise/config.toml" "mise rewrites this file; yours to edit"
    # jujutsu (jj) — OPT-IN colocated git companion. Linked unconditionally (like lazygit
    # above); the config is inert without the jj binary, and the zsh aliases are HAVE_JJ-gated.
    [[ -f "$dotfiles/core/jujutsu/config.toml" ]] && blib_link "$dotfiles/core/jujutsu/config.toml" "$config/jj/config.toml"
    # atuin — the config 00-tools.zsh's `atuin init zsh` never had. DEFAULT path (no
    # ATUIN_CONFIG_DIR needed), linked unconditionally like the two above; inert without
    # the binary. NOTE: a hand-written ~/.config/atuin/config.toml is BACKED UP by
    # blib_link (…pre-dotfiles.<stamp>.<pid>, and it says so) — re-apply anything local
    # via ATUIN_* env in the
    # OS/host layer, which is also how a machine turns the daemon on. CAVEAT: an ATUIN_*
    # override only reaches atuin for a key the Core config does NOT itself set (atuin adds
    # the config file as a source AFTER the environment, so the file wins). See that file's
    # header for the ten it sets; varying one of those means deleting it, not exporting.
    [[ -f "$dotfiles/core/atuin/config.toml" ]] && blib_link "$dotfiles/core/atuin/config.toml" "$config/atuin/config.toml"
    # tealdeer — the `tldr` binary's config, DEFAULT path. Linked unconditionally like the
    # three above and inert without the binary. It exists to turn ON auto_update, which
    # upstream ships OFF: `help` is a Core alias but nothing refreshes the page cache, so a
    # fresh box's `help` fails until someone runs `tldr --update` by hand.
    [[ -f "$dotfiles/core/tealdeer/config.toml" ]] && blib_link "$dotfiles/core/tealdeer/config.toml" "$config/tealdeer/config.toml"
    # portable sesh config, seeded ONCE (edited locally, never tracked back).
    blib_seed "$dotfiles/core/sesh/sesh.toml.example" "$config/sesh/sesh.toml" \
      "edit freely; not tracked from here"

    # cross-OS helper scripts from Core onto PATH (~/.local/bin).
    if [[ -d "$dotfiles/core/bin" ]]; then
      _blib_dry || mkdir -p "$HOME/.local/bin"
      for s in clip clip-paste; do
        if [[ -f "$dotfiles/core/bin/$s" ]]; then
          blib_link "$dotfiles/core/bin/$s" "$HOME/.local/bin/$s"
          _blib_dry || chmod +x "$dotfiles/core/bin/$s" 2>/dev/null || true
        fi
      done
    fi

    # ssh client config (keys are NEVER tracked — only ssh/config). Core's, from
    # core/, like every other file above: this used to read "$dotfiles/ssh/config" —
    # the OS repo's ROOT — so Core's shared library had a hard dependency on a file
    # each of nine repos had to happen to provide at exactly that path, and the
    # [[ -f ]] guard made "the repo forgot" and "the repo opted out" the same
    # outcome. Seven repos provided it, with byte-identical `Host *` blocks (#450).
    #
    # ssh is strict about permissions: ~/.ssh must be 0700, ControlMaster needs the
    # sockets dir to exist, and config.d is where the host-local overrides the
    # vendored config Includes live (see core/ssh/config's header for the
    # first-match-wins ordering that makes them win).
    #
    # NO chmod on the config file itself. ssh refuses a config that is group- or
    # world-WRITABLE; git checks out 0644, which already satisfies that. The old
    # `chmod 600 "$dotfiles/ssh/config"` reached into the consumer repo's working
    # tree to change a tracked file's mode — and now that the file lives in core/,
    # it would be Core chmod'ing its own vendored tree in nine repos. Don't restore it.
    if [[ -f "$dotfiles/core/ssh/config" ]]; then
      if _blib_dry; then
        blib_say "would link core/ssh/config into ~/.ssh (0700 ~/.ssh + sockets + config.d)"
      else
        blib_say "symlinking core/ssh/config"
        mkdir -p "$HOME/.ssh/sockets" "$HOME/.ssh/config.d"
        chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets" "$HOME/.ssh/config.d"
        blib_link "$dotfiles/core/ssh/config" "$HOME/.ssh/config"
        blib_ok "ssh/config linked into ~/.ssh (generate a key with: ssh-keygen -t ed25519)"
      fi
    fi
  fi
}

# ── symlink the OS-native overlays ────────────────────────────────────────────
# blib_link_os_layer <dotfiles> <config> <os> — link the five OS overlay files when
# present: os/<os>.conf → tmux/os.conf, os/<os>.zsh → zsh/80-os.zsh (the loader's OS
# band), os/<os>.gitconfig → git/os.gitconfig (included by Core's gitconfig),
# os/<os>.capabilities → zsh/os.capabilities (read by Core's 02-capabilities.zsh), and
# ssh/os.conf → ~/.ssh/config.d/50-os.conf (Included by Core's ssh/config).
#
# The ssh overlay is the ESCAPE HATCH for #450, and it is deliberately the only one
# whose source is NOT under os/: it is named ssh/os.conf, next to where each repo's
# ssh/config used to sit, so a repo that genuinely needs OS-specific ssh has an
# obvious place to put THAT — rather than re-forking the whole client config, which
# is how seven repos came to hand-maintain byte-identical copies of one file. No OS
# repo ships one today; the [[ -f ]] guard makes that the normal case, not a gap.
blib_link_os_layer() {
  local dotfiles="$1" config="$2" os="$3"
  # Each overlay rides with its Core group: os.conf→tmux, os.gitconfig→git, os.zsh→zsh,
  # ssh/os.conf→tools (the group that links Core's ssh/config in the first place).
  if blib_want tmux && [[ -f "$dotfiles/os/$os.conf" ]]; then
    blib_link "$dotfiles/os/$os.conf" "$config/tmux/os.conf"
  fi
  if blib_want git && [[ -f "$dotfiles/os/$os.gitconfig" ]]; then
    blib_link "$dotfiles/os/$os.gitconfig" "$config/git/os.gitconfig"
  fi
  if blib_want zsh && [[ -f "$dotfiles/os/$os.zsh" ]]; then
    blib_say "symlinking $os OS-native layer"
    # v4: the OS layer is the numbered fragment 80-os.zsh (band 70-84). The loader globs
    # it by NN prefix and sources it in order, like every other fragment.
    blib_link "$dotfiles/os/$os.zsh" "$config/zsh/80-os.zsh"
  fi
  # v5: the capability DECLARATION (#663) — the OS layer's package-manager verbs,
  # scheduler and opt-in tool list as KEY=value data, read (never sourced) by Core's
  # zsh/02-capabilities.zsh and by maint/dotfiles-maint.sh, which is bash.
  #
  # It rides with the zsh group and lands in $ZSH_CFG beside the fragments because that
  # is the one directory both readers already know how to find. It is NOT itself a
  # fragment: the loader globs [0-9][0-9]-*.zsh, so an un-numbered, un-.zsh file is
  # never sourced into your shell — which is the entire point of shipping it as data.
  #
  # UNNUMBERED DESTINATION, deliberately. os/<os>.zsh lands at 80- because it is ORDERED
  # against the rest of the chain; a declaration is read on demand by whoever wants it,
  # so a band number would only imply a load position it does not have.
  #
  # The [[ -f ]] guard was the migration path while no OS repo had authored a declaration.
  # #667 authored them, so on a synced repo this now links — and the guard keeps its second
  # job: it is what makes a Role repo (no os/ band) and a partially-synced checkout a no-op
  # rather than an error.
  #
  # THIS LINK IS NOW LOAD-BEARING, which it was not before #763. Core used to carry built-in
  # package-manager and scheduler tables behind the declaration, so a box with no symlink
  # kept working on those; they are gone. Without this link `up` has no upgrade verb,
  # `maint-install` refuses on systemd/launchd and core-doctor prints no install hint —
  # each saying so in its own voice, and each naming `--links-only` as the fix. Presence is
  # enforced by the audit (§9c), not by bootstrap: a bootstrap that hard-failed here would
  # be refusing to set up the very box that needs setting up.
  #
  # "warns once" is what this comment used to claim, and it was false twice over (#715):
  # there is no once-per-box state anywhere in that fragment, and the warning fired on
  # every shell. Silence is now the default there and the warning is opt-in via
  # CORE_CAP_LOUD — precisely because this guard makes absence the normal state.
  if blib_want zsh && [[ -f "$dotfiles/os/$os.capabilities" ]]; then
    blib_link "$dotfiles/os/$os.capabilities" "$config/zsh/os.capabilities"
  fi
  # ssh overlay → a config.d drop-in. Numbered 50- so a host-local file can sort either
  # side of it deliberately; Core's Include globs *.conf in lexical order, and ssh's
  # first-match-wins means a lower number beats this one. Directory created here rather
  # than relied upon: `--only zsh` skips blib_link_core, which is what creates it.
  if blib_want tools && [[ -f "$dotfiles/ssh/os.conf" ]]; then
    _blib_dry || { mkdir -p "$HOME/.ssh/config.d"; chmod 700 "$HOME/.ssh" "$HOME/.ssh/config.d"; }
    blib_link "$dotfiles/ssh/os.conf" "$HOME/.ssh/config.d/50-os.conf"
  fi
}

# ── symlink the Role overlays ─────────────────────────────────────────────────
# blib_link_role_layer <dotfiles> <config> <role> — the Role-layer twin of
# blib_link_os_layer, for the repos that sit ON TOP of an OS-native layer rather than
# being one: dotfiles-Offense (role `offensive`) and dotfiles-Defense (role `defense`).
#
# <role> names BOTH the directory and the file stem, exactly as <os> does above, so
# no SOURCE file has to move: offensive/offensive.zsh and defense/defense.zsh are
# already where this expects them.
#
#   <role>/<role>.zsh   → zsh/85-<role>.zsh   (the loader's Role band, 85-94)
#   <role>/<role>.conf  → tmux/role.conf      (Core's tmux.conf sources this last)
#   <role>/templates/   → <config>/<role>/templates
#
# ONE DESTINATION MOVED, and this is the record of it. dotfiles-Defense always landed
# its templates at <config>/defense/templates, but the offensive repo hand-rolled
# <config>/kali/templates — named for the distro, which is exactly the naming the rename
# retired. Adopting this helper there relocated them to <config>/offensive/templates and
# updated the two shipped docs that quoted the old path by hand (offensive/hacktheplanet's
# pseudo-shell.py line, and offensive/ippsec). Kept as the reason the destination is named
# for the ROLE and not the distro. Deliberately NOT solved with a compat symlink (it would
# preserve a ~/.config/kali/ on a repo no longer called Kali) or a namespace parameter
# (an argument whose only job is to keep a retired name alive).
#
# ONE ROLE REPO CALLS THIS, NOT BOTH. Offense does (its bootstrap.sh calls
# blib_link_role_layer); Defense still hand-rolls the band in its own wire_defense_stage,
# and adopting the helper there is what remains. core.manifest and PORTING-MATRIX.md both
# record the same split — this comment used to claim the migration was finished, which was
# the only one of the three that said so.
#
# Defense hand-rolls TWO of the three links (85-defense.zsh and templates); there is no
# tmux/role.conf link because dotfiles-Defense/defense/ ships no defense.conf, whereas
# Offense does ship offensive.conf. So the migration is low-risk: the tmux branch below is
# [[ -f ]]-guarded and would simply no-op there.
#
# This exists because both role repos hand-rolled the same links and had already drifted:
# Defense honours BLIB_DRY directly rather than the library's _blib_dry() when dropping the
# stale pre-v4 link, and Offense did not — so a --dry-run in one repo mutated the box and in
# the other did not. Present tense on Defense's half, deliberately: that fork is still live
# and is the thing adopting the helper would retire.
#
# ONE ROLE PER BOX. Both roles land on band 85, so a machine that wired Offense and
# then Defense would have 85-offensive.zsh and 85-defense.zsh loading in glob order and
# a single tmux/role.conf that only the second one to run owns. That is not a supported
# configuration — an attacker station and an analyst station are different boxes — and
# spreading the roles across separate bands would only make the breakage quieter.
#
# NO role gitconfig hook, deliberately: Core's gitconfig [include]s os.gitconfig and
# local.gitconfig only, neither role repo has ever had one, and an unused include is a
# hook that rots. Add it here AND in git/gitconfig if a role ever needs one.
blib_link_role_layer() {
  local dotfiles="$1" config="$2" role="$3"

  if blib_want zsh && [[ -f "$dotfiles/$role/$role.zsh" ]]; then
    blib_say "symlinking $role role layer"
    # v4: the loader globs NUMBERED fragments ($ZSH_CFG/NN-*.zsh), so a pre-v4 unnumbered
    # link is not just stale — it is INERT, and it sits there looking wired. Drop it, via
    # the dry-run guard so a preview stays a preview.
    if [[ -L "$config/zsh/$role.zsh" ]]; then
      if _blib_dry; then
        blib_say "would drop stale pre-v4 link: $config/zsh/$role.zsh"
      else
        rm -f "$config/zsh/$role.zsh"
      fi
    fi
    blib_link "$dotfiles/$role/$role.zsh" "$config/zsh/85-$role.zsh"
  fi

  if blib_want tmux && [[ -f "$dotfiles/$role/$role.conf" ]]; then
    blib_link "$dotfiles/$role/$role.conf" "$config/tmux/role.conf"
  fi

  # Templates ride with the zsh group: they are the role's scaffolding (engagement /
  # case skeletons), surfaced under $config for discoverability. The role's own helpers
  # read them out of the checkout, not from here.
  if blib_want zsh && [[ -d "$dotfiles/$role/templates" ]]; then
    blib_link "$dotfiles/$role/templates" "$config/$role/templates"
  fi
}

# ── wiring summary ────────────────────────────────────────────────────────────
# blib_wire_summary — print the BLIB_* tallies accumulated by blib_link / blib_seed
# since the counters were last reset (they start at 0 on source). Optional: a caller
# that wants a one-line "N linked · M seeded · K backed up" footer calls this after
# its wire_links. Prefixes "(dry run) " under BLIB_DRY so a preview reads as a preview.
# "backed up" and "relinked" are separate on purpose: the first promises a restorable
# .pre-dotfiles.<stamp>.<pid> file on disk, the second only that the old target was
# printed. Both are now also announced individually as they happen (#463) — this footer
# is the tally, not the record.
blib_wire_summary() {
  local pre=""
  _blib_dry && pre="(dry run) "
  blib_ok "${pre}${BLIB_LINKED} linked · ${BLIB_SEEDED} seeded · ${BLIB_BACKED} backed up · ${BLIB_RELINKED} relinked · ${BLIB_SKIPPED} skipped"
}

# ── write the .zshrc entry loader ─────────────────────────────────────────────
# blib_write_zshrc_loader [ignored...] — write the managed ~/.zshrc that sets the env
# the Core fragments expect and sources the vendored v4 loader. v4 needs no module list:
# the loader globs the numbered fragments (Core NN-*.zsh + the OS 80-os.zsh + any role
# 85-*.zsh + host 99-local.zsh) itself, so a role repo just symlinks its fragment into
# the 85 band (no custom-list arg). Any legacy args are accepted and IGNORED so a
# pre-v4 caller does not break. Idempotent: a no-op if a "dotfiles-managed v4" loader is
# already in place; backs up any prior ~/.zshrc first (incl. a pre-v4 "v2" one, which no
# longer matches, so it is upgraded). The heredocs are single-quoted, so $HOME/$ZDOTDIR/
# etc. stay LITERAL in the written file (evaluated at shell start, not at write time).
#
# The entry file EXPORTS ZDOTDIR (see the heredoc below), so it must also exist AT
# $ZDOTDIR/.zshrc — see _blib_seed_zdotdir_rc.
blib_write_zshrc_loader() {
  blib_want zsh || return 0   # the .zshrc loader belongs to the zsh group
  local rc="$HOME/.zshrc" rc_bak=""

  if [[ -f "$rc" ]] && grep -q "dotfiles-managed v4" "$rc" 2>/dev/null; then
    # Already managed — but a box bootstrapped before the seeding below existed still
    # has no $ZDOTDIR/.zshrc, so reconcile that here rather than only on a fresh write.
    _blib_seed_zdotdir_rc "$rc"
    return 0
  fi
  if _blib_dry; then
    blib_say "would write managed ~/.zshrc loader (v4 numbered-fragment glob)"
    # Preview the seeding too — BLIB_DRY's contract is the FULL plan, and this is a
    # second file the real run creates.
    _blib_seed_zdotdir_rc "$rc"
    return 0
  fi
  blib_say "writing .zshrc loader"
  # Same one format as blib_link, via the same helper (#464) — and announced, for the
  # same reason (#463). This one is a `cp` rather than a `mv` because the heredoc below
  # overwrites $rc in place; the user's prior ~/.zshrc is still displaced from the only
  # location that matters to them, so it is still worth saying out loud.
  if [[ -f "$rc" ]]; then
    rc_bak="$rc.$(_blib_backup_suffix)"
    cp "$rc" "$rc_bak"
    blib_warn "backed up existing $rc -> $rc_bak"
  fi

  cat >"$rc" <<'ZRC'
# dotfiles-managed v4 — do not hand-edit; local tweaks go in ~/.config/zsh/99-local.zsh
# This entry file sets the env the Core fragments expect (no ~/.zshenv is assumed), then
# sources the vendored v4 loader, which globs the numbered fragments and sources them in
# NN order.

# ── XDG + env ─────────────────────────────────────────────────────────────────
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
export EDITOR=nvim VISUAL=nvim
export NOTES_DIR="${NOTES_DIR:-$HOME/Notes}"

# ── the vendored v4 loader ────────────────────────────────────────────────────
# 10-options.zsh owns the nav/glob setopts + compinit + completion zstyles; 15-history.zsh
# owns HISTFILE/HISTSIZE. v4 keeps mutable state OUT of the config tree: history →
# $XDG_STATE_HOME, compdump → $XDG_CACHE_HOME, plugins → $XDG_DATA_HOME. ZSH_CFG is the
# config dir where the numbered fragment symlinks (and their .zwc wordcode) live.
: "${ZDOTDIR:=$XDG_CONFIG_HOME/zsh}"
export ZDOTDIR
ZSH_CFG="$ZDOTDIR"

if [[ -r "$ZSH_CFG/loader.zsh" ]]; then
  source "$ZSH_CFG/loader.zsh"
else
  print -u2 -- "zshrc: Core loader not found at $ZSH_CFG/loader.zsh — re-run the dotfiles bootstrap to (re)link Core."
fi
ZRC
  _blib_seed_zdotdir_rc "$rc"
}

# _blib_seed_zdotdir_rc <managed-rc> — make the entry file reachable AT $ZDOTDIR too.
#
# The managed ~/.zshrc EXPORTS ZDOTDIR=$XDG_CONFIG_HOME/zsh. That is fine for the shell
# that reads ~/.zshrc (ZDOTDIR is unset at that point, so zsh looks in $HOME), but every
# zsh started from inside it INHERITS the export and looks in $ZDOTDIR instead — where,
# without this, there is no .zshrc/.zshenv/.zprofile/.zlogin at all. zsh then treats the
# user as brand new and runs zsh-newuser-install, and none of Core loads. `exec zsh` is
# the documented first step after a bootstrap (README "Getting Started"), so the very
# first thing a fresh box is told to do walked straight into the wizard.
#
# Worse than the wizard: on a non-TTY there is no wizard, just a shell with no Core.
# And the wizard's own option (0) writes a comment-only $ZDOTDIR/.zshrc, which silences
# it permanently while leaving the shell empty — the failure becomes invisible.
#
# Seed it as a LINK, not a copy, so it tracks ~/.zshrc when the loader is regenerated.
# Re-entrant by construction: the file resolves ZDOTDIR with := (a no-op when already
# exported) and loader.zsh globs [0-9][0-9]-*.zsh, which ".zshrc" cannot match — so being
# read via $ZDOTDIR sources the fragments exactly once, same as via $HOME.
_blib_seed_zdotdir_rc() {
  local rc="$1"
  # Resolve ZDOTDIR the same way the written entry file does.
  local zdot="${ZDOTDIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}"
  # ZDOTDIR pointing at $HOME means ~/.zshrc IS the $ZDOTDIR entry — nothing to seed, and
  # linking would make it its own target.
  [[ -n "$zdot" && "$zdot" != "$HOME" ]] || return 0
  local dst="$zdot/.zshrc"
  # INVERTED LAYOUT: some setups point ~/.zshrc AT $ZDOTDIR/.zshrc rather than the other
  # way round. The two path STRINGS still differ, so a string compare sees nothing wrong,
  # but they are one file — and blib_link would move the real file aside and leave the two
  # symlinks referring to each other. That is an ELOOP on the next shell: zsh resolves
  # $ZDOTDIR/.zshrc → ~/.zshrc → $ZDOTDIR/.zshrc and gives up. Compare RESOLVED files
  # (-ef is dev+inode, symlinks followed), gated on rc actually being a link so the normal
  # layout — where dst is our own symlink back to a real rc — still reaches blib_link and
  # keeps its idempotent no-op accounting.
  if [[ -L "$rc" && "$rc" -ef "$dst" ]]; then
    blib_warn "$dst already resolves to $rc — leaving it alone (linking would make a symlink cycle)"
    return 0
  fi
  # On a FRESH dry run ~/.zshrc has not been written yet, so blib_link would report the
  # source missing rather than previewing the link. Say what the real run would do.
  if _blib_dry && [[ ! -e "$rc" ]]; then
    blib_say "would seed $dst -> ~/.zshrc"
    return 0
  fi
  blib_link "$rc" "$dst"
}

# ── privilege escalation ──────────────────────────────────────────────────────
# _blib_priv <cmd...> — run CMD under $BLIB_SU (default `sudo`), or directly when
# it's empty (already root). Keeps the escalator a single token and never invokes an
# empty-string command — so a doas-only box (BLIB_SU=doas) or a root box (BLIB_SU="")
# both work. A caller on Alpine sets BLIB_SU="$SU" before calling the helpers below.
_blib_priv() {
  local su="${BLIB_SU-sudo}"
  if [[ -n "$su" ]]; then "$su" "$@"; else "$@"; fi
}
# blib_priv is the PUBLIC name for the same thing — an OS bootstrap should call this for
# every privileged command instead of writing `sudo` inline. `_blib_priv` predates it and
# stays as the internal spelling the helpers in this file already use.
blib_priv() { _blib_priv "$@"; }

# ── non-destructive write of a ROOT-OWNED system file ─────────────────────────
# blib_install_system_file <rendered-content> <dst> — install CONTENT at DST under
# $BLIB_SU, backing up whatever was there first. The system-file counterpart to blib_link:
# same guarantee (nothing the user owned is destroyed unannounced), same backup naming, same
# BLIB_BACKED tally, same BLIB_DRY behaviour.
#
# WHY THIS EXISTS. blib_link has backed up a displaced real file since the beginning, but the
# other way a bootstrap writes to a machine — `_blib_priv tee` into /etc — had no equivalent,
# so every OS repo hand-rolled it, and one did not. `dotfiles-Arch` rendered /etc/wsl.conf and
# teed it over the top on every run of a script its own docs call idempotent. That was not a
# theoretical hazard: on a real box the pre-existing /etc/wsl.conf carried `[boot] systemd=true`
# and the run destroyed it (#475). A file under /etc is the one class where the user has the
# least ability to notice and the most to lose — it is not in their home, no editor has it
# open, and the loss surfaces at the next boot.
#
# THREE OUTCOMES, and the first is the common one:
#   • byte-identical  → nothing is written, nothing is counted, nothing is said. This is what
#     makes a second run genuinely idempotent rather than merely harmless-looking: without it
#     every re-run would produce another backup, and a directory of twenty identical
#     .pre-dotfiles copies is its own kind of damage.
#   • present and different → `cp -a` to <dst>.pre-dotfiles.<stamp>.<pid>, then write. `cp -a`,
#     NOT blib_link's `mv`: the original must stay in place with its owner, mode and timestamps
#     intact, because /etc entries are frequently read by something that must not see the file
#     briefly vanish, and because the backup should be root-owned like the original rather than
#     inheriting whoever ran the bootstrap. The stamp comes from _blib_backup_suffix, so a
#     system backup sorts and reads exactly like a dotfile one (#464) — one convention to know.
#   • absent → write it, and say so. No backup, nothing to count.
#
# COMPARISON IS A BASH STRING COMPARE, deliberately, and this is the one place it beats
# core_files_identical's `git hash-object`. This helper runs during provisioning, which on a
# fresh box can be BEFORE git is installed — and a comparison that errors is indistinguishable
# from "they differ", which would make every run take the backup-and-write branch: exactly the
# failure mode #572 documents for a missing `cmp`. A string compare needs no binary at all.
# Its one imprecision is that $(...) strips trailing newlines from both sides, so two renderings
# differing ONLY in trailing blank lines compare equal. That is the right direction: the quiet
# one. This helper always writes the same rendering, so the only way to reach that case is a
# human having touched the file, and treating that as "no change" leaves their file alone
# rather than backing it up and overwriting it to no visible purpose.
#
# The destination is read back through _blib_priv too — a 0600 root-owned file is not readable
# by the invoking user, and reading it directly would fail and be misread as "differs".
#
# Returns 0 on success or no-op. On failure it warns, records via blib_note_fail so
# blib_failures_report can surface it, and still returns 0 — a bootstrap must not die under
# `set -e` because one /etc write was refused, and the tally is what keeps that honest.
blib_install_system_file() {
  local content="${1-}" dst="${2-}" cur="" bak=""
  if [[ -z "$dst" ]]; then
    blib_warn "blib_install_system_file: no destination given"
    return 0
  fi
  # NORMALISE THE CONTENT ONCE, and compare and write the same normalised value. $(...) below
  # strips trailing newlines from what is on disk but nothing strips them from the argument, so
  # a caller passing a heredoc — the natural way to render a config file, and the way every
  # /etc writer in the fleet does it — would compare unequal against the file this helper
  # itself just wrote, and take the back-up-and-rewrite branch on EVERY run. That is precisely
  # the non-idempotence the helper exists to remove, reintroduced one layer up.
  while [[ "$content" == *$'\n' ]]; do content="${content%$'\n'}"; done
  # `_blib_priv test -e`, not `[[ -e ]]`: the path may live in a directory the invoking user
  # cannot traverse, where a plain test answers "absent" for a file that is very much there.
  if _blib_priv test -e "$dst" 2>/dev/null; then
    cur="$(_blib_priv cat "$dst" 2>/dev/null || true)"
    if [[ "$cur" == "$content" ]]; then
      BLIB_SKIPPED=$((BLIB_SKIPPED + 1))
      return 0 # already exactly this — say nothing, count nothing, write nothing
    fi
    if _blib_dry; then
      blib_say "would back up + write: $dst"
      BLIB_BACKED=$((BLIB_BACKED + 1))
      return 0
    fi
    bak="$dst.$(_blib_backup_suffix)"
    if ! _blib_priv cp -a "$dst" "$bak" 2>/dev/null; then
      blib_note_fail "could not back up $dst — leaving it untouched rather than overwriting it"
      return 0
    fi
    # blib_warn (stderr), matching blib_link: this is a file the machine owned, and the notice
    # must survive a caller that pipes stdout to a log.
    blib_warn "backed up existing $dst -> $bak"
    BLIB_BACKED=$((BLIB_BACKED + 1))
  else
    if _blib_dry; then
      blib_say "would write: $dst"
      return 0
    fi
    _blib_priv mkdir -p "$(dirname "$dst")" 2>/dev/null || true
  fi
  if printf '%s\n' "$content" | _blib_priv tee "$dst" >/dev/null 2>&1; then
    blib_say "wrote $dst"
  else
    blib_note_fail "could not write $dst${bak:+ — the original is preserved at $bak}"
  fi
  return 0
}

# blib_resolve_su [--require] — resolve the escalator ONCE into BLIB_SU, and export it.
#
# Every OS bootstrap.sh hard-codes `sudo` at a dozen call sites. That is wrong on every box
# where there is no sudo to call — and those are exactly the boxes a bootstrap meets first:
# a distro container (fedora:latest and alpine:3.20 both ship without sudo), a WSL distro's
# first boot (root, before /etc/wsl.conf installs the default user), and a minimal Server
# image. The script then died at its FIRST package-manager line with `sudo: command not
# found` — exit 127 under `set -e`, before doing anything at all. It is also why
# bootstrap-test.yml can exercise only --links-only, and must pass BLIB_SU= to do even that.
#
# Precedence: an explicitly set BLIB_SU always wins, INCLUDING an empty one (BLIB_SU= means
# "run directly"), which is why this tests ${BLIB_SU+x} and not emptiness. Otherwise root
# needs nothing, else sudo, else doas.
#
# --require makes "not root and no escalator" a hard error (returns 1). Without it the
# caller gets an empty BLIB_SU and a warning, which is the correct outcome for a
# links-only run — wiring symlinks needs no privileges at all.
# _blib_su_path <name> — set $_BLIB_SU_PATH to NAME's absolute executable path and return
# 0, or return 1. `command -v` alone is not enough: it also resolves aliases, builtins and
# shell functions, so a `sudo()` function in the environment makes it print `sudo`. Require
# a value that starts with / and is actually executable.
_BLIB_SU_PATH=""
_blib_su_path() {
  local p
  p="$(command -v "$1" 2>/dev/null || true)"
  [[ "$p" == /* && -x "$p" ]] || return 1
  _BLIB_SU_PATH="$p"
  return 0
}

blib_resolve_su() {
  local require=0
  [[ "${1:-}" == "--require" ]] && require=1
  if [[ -n "${BLIB_SU+x}" ]]; then
    export BLIB_SU
    return 0
  fi
  # STRING compare, and tolerate `id` itself being unavailable. `[[ "$(id -u)" -eq 0 ]]` is
  # an ARITHMETIC comparison, and bash evaluates an empty string there as 0 — so on a box
  # where `id` is missing or off PATH the old form concluded "we are root", skipped the
  # --require error, and then ran every privileged command unescalated.
  #
  # $EUID rather than `id -u`: it is a bash BUILTIN, so it needs no PATH lookup, no fork,
  # and cannot be shadowed. The previous fix only failed CLOSED to "not root" when `id` was
  # missing, which is safe against a wrong answer but wrong against a right one — a genuine
  # root shell with no id/sudo/doas then got a --require failure, breaking the exact
  # minimal-root bootstrap this helper exists to support.
  local uid="$EUID"
  # Pin the ABSOLUTE path, not the bare name. "Resolve once" has to mean once: this file
  # also ships blib_user_bindirs_on_path, which deliberately prepends user-writable dirs
  # (~/.local/bin, $CARGO_HOME/bin, $GOBIN) to PATH — so a bare `sudo` recorded here would
  # be re-resolved against a DIFFERENT PATH at every later call. A `sudo` dropped in one of
  # those dirs would then receive the password prompt, and the keepalive would prime one
  # binary while _blib_priv escalated with another.
  #
  # _blib_su_path resolves a REAL EXECUTABLE or nothing: `command -v` also reports aliases,
  # builtins and shell FUNCTIONS, so an exported `sudo()` makes it print the bare word
  # `sudo`. Recording that would defeat the pinning above (a bare name is re-resolved at
  # every call) and could hand privileged execution to the function itself.
  if [[ "$uid" == "0" ]]; then
    BLIB_SU=""
  elif _blib_su_path sudo; then
    BLIB_SU="$_BLIB_SU_PATH"
  elif _blib_su_path doas; then
    BLIB_SU="$_BLIB_SU_PATH"
  else
    BLIB_SU=""
    if ((require)); then
      blib_warn "not root, and neither sudo nor doas is installed — cannot install packages"
      blib_warn "re-run as root, install sudo, or use --links-only (which needs no privileges)"
      export BLIB_SU
      return 1
    fi
    blib_warn "no privilege escalator found — privileged steps run directly and may fail"
  fi
  export BLIB_SU
  return 0
}

# ── keep the sudo timestamp warm ──────────────────────────────────────────────
# blib_sudo_keepalive_start / blib_sudo_keepalive_stop — prime sudo ONCE up front, then
# refresh it in the background for the life of the caller.
#
# The bug this exists for: a bootstrap's privileged calls are interleaved with package
# builds that take MINUTES (cargo/go from source), comfortably outliving sudo's 5-minute
# timestamp. sudo writes its prompt to STDERR and reads the password from the TTY — so a
# later call whose stderr is redirected (`>/dev/null 2>&1`, ubiquitous in these scripts)
# stops dead at a prompt nobody can see. No output, no progress, indistinguishable from a
# hang, and it reproduces only on a box slow enough to cross the timeout.
#
# Only meaningful for sudo: doas has no refreshable timestamp and root has nothing to
# prime. Returns non-zero if the initial authentication fails, so a caller can abort
# before doing half a provision.
BLIB_SUDO_KEEPALIVE_PID=""
blib_sudo_keepalive_start() {
  # Match on the BASENAME, then invoke the RESOLVED token. BLIB_SU is documented as a single
  # command token, and `BLIB_SU=/usr/bin/sudo` is a perfectly valid one — but comparing it to
  # the literal string `sudo` silently declined to prime it, so the timestamp expired mid-run
  # and the invisible-prompt hang came straight back. Calling a bare `sudo` below would have
  # been the same bug from the other end (priming one binary, escalating with another).
  local su="${BLIB_SU-sudo}"
  [[ "${su##*/}" == sudo ]] || return 0
  [[ -z "$BLIB_SUDO_KEEPALIVE_PID" ]] || return 0 # already running
  # The refresh INTERVAL, seconds. 50s is a comfortable fraction of the timestamp lifetime
  # described above, not a tuning knob — no caller should need to change it for a real run.
  #
  # It is a variable rather than a literal for the TEST SUITE's benefit. It was introduced to
  # bound a stall in the block asserting that this loop refreshes with `sudo -n -v`, which
  # cost one full interval — 50.02s against the shipped default.
  #
  # That stall is INTERMITTENT (2 in 16 instrumented runs, not the constant first reported)
  # and its cause is still UNKNOWN. What sampling during a stall does show is that the loop
  # below did not act on its TERM until its sleeper expired, while the caller sat in
  # blib_sudo_keepalive_stop's `wait` — so the suspect is this trap/teardown path, not the
  # test's output capture as previously written here. scripts/test-core.sh carries the full
  # measurement and the two explanations already ruled out; read it before changing the loop.
  #
  # That teardown stall is FIXED below (#529): the TERM is now followed by a KILL, which
  # cannot be lost or ignored. So the seam is no longer what caps the damage — it bounds
  # only the TEST, and no real run should ever set it. The lost-signal mechanism itself was
  # never isolated; the note on the trap says exactly what is measured and what is not.
  #
  # The `>/dev/null 2>&1` on the loop below is what keeps this helper's own sleeper out of a
  # caller's pipe, and is load-bearing for exactly that reason — see the stdio note further
  # down. Do not remove it because "the refresher prints nothing anyway".
  #
  # FAIL-SAFE, not fail-closed: a non-numeric or zero override falls back to 50 rather than
  # erroring. This is a test seam, and a typo in it must not turn a provisioning run into a
  # busy-loop hammering sudo (or into a hard failure) on someone's machine.
  local interval="${BLIB_SUDO_KEEPALIVE_INTERVAL:-50}"
  [[ "$interval" =~ ^[1-9][0-9]*$ ]] || interval=50
  _blib_dry && {
    blib_say "would prime sudo and keep its timestamp warm for the run"
    return 0
  }
  "$su" -v || return 1
  # `kill -0 "$$"`: $$ is the PARENT shell's pid even inside this background subshell, so
  # the refresher stops when the bootstrap exits even if the caller's trap is missed.
  # stdio redirected on purpose: the refresher OUTLIVES the call that started it, and a
  # child holding the caller's stdout keeps a pipe or command substitution open. A caller
  # writing `out=$(step_that_primes_sudo)` would then block until the whole bootstrap
  # exits, rather than returning — a hang observed nowhere near its cause.
  #
  # `-n -v` (not `-n true`): -v is sudo's VALIDATION mode, which refreshes the timestamp and
  # nothing else. `sudo -n true` additionally requires the account to be authorised to run
  # `true`, so on a sudoers restricted to the provisioning commands the refresh is denied,
  # the failure is swallowed by `|| true`, and the timestamp quietly expires — putting back
  # the invisible-prompt hang this whole helper exists to prevent.
  #
  # The trap is what makes stop() able to REAP. Without it, `kill` signals only this loop
  # shell; the `sleep` it is blocked in is a separate process that survives, orphaned, for
  # up to its full duration. Trapping TERM lets us kill the current sleeper explicitly.
  #
  # It is armed ONCE, BEFORE the loop — i.e. before anything can fork. Arming it per
  # iteration (after `sleep &`) left a window in which a sleeper already existed but no
  # handler did: the parent records the loop pid the instant `&` returns, so a stop()
  # landing in that window killed the loop under the DEFAULT disposition and orphaned the
  # freshly forked sleep for its full duration — the exact leak this helper exists to
  # prevent, surviving inside its own fix. Measured with the window held open: orphaned
  # 5/5 with the trap inside the loop, 0/5 with it hoisted.
  #
  # The handler names the JOB (`%%`), not a pid — neither `$!` nor a saved copy. Both pid
  # forms are wrong, in opposite directions:
  #   • a copy (`_sleeper=$!`) is assigned one statement AFTER the fork, so a TERM landing
  #     in between fires the handler holding the PREVIOUS sleeper and orphans the new one —
  #     the same race as arming the trap late, just narrower.
  #   • `$!` closes that (the fork sets it) but never clears: after `wait` reaps the
  #     sleeper, `$!` still holds its dead pid, so a TERM during the next `sudo -n -v` —
  #     a 50-second window, every iteration — signals that pid anyway. Once the box has
  #     cycled through the pid space it belongs to an unrelated process, and this runs as
  #     root. Verified: after `wait "$p"`, `$!` still equals `$p`.
  # A job spec has both properties at once, which is the whole reason to use one: the job
  # table is updated BY the fork (so `%%` names a just-forked sleeper, keeping the orphan
  # window shut) and CLEARED by the reap (so `kill %%` matches nothing at all once the
  # sleeper is gone, rather than something else). Verified both ways.
  {
    # kill THEN wait: without the wait the handler exits the moment the signal is sent, so
    # the loop shell dies while its sleeper is still alive or unreaped — and stop()'s own
    # `wait` returns on the shell, not the sleeper. Teardown then only LOOKED synchronous
    # because the test slept afterwards. Reaping here is what makes stop()'s contract true.
    #
    # TERM then KILL, because one TERM is not enough. A signal aimed at the sleeper is
    # sometimes accepted by kill(2) — rc 0 — and simply never acted on: the sleeper runs
    # its FULL interval and exits 0, while this handler blocks in `wait` and stop() blocks
    # behind it. Measured in-loop: `TRAP kill rc=0` followed 30.003s later by `TRAP wait
    # rc=0`, with the sleeper showing no signal blocked, ignored or caught (SigBlk/SigIgn/
    # SigCgt all zero) — so it was killable and the signal was lost, not refused. That is
    # the whole of #529: an intermittent 50s hang in a helper whose job is to keep a
    # provisioning run from hanging.
    #
    # The mechanism was NOT isolated. It reproduces only inside the full behavioral suite
    # (roughly 1 run in 2–3 at a 30s interval) and never standalone — not with a plain
    # sleeper, not through the suite's own `sleep` shim, and not at any delay between
    # start() and stop() from 0 to 50ms. So this is a fix validated by measurement rather
    # than by explanation, and it is written that way on purpose.
    #
    # A follow-up KILL costs nothing and cannot be lost or ignored. It is safe precisely
    # because the target is a bare `sleep`: no state, nothing to flush, nothing to corrupt.
    # There is deliberately NO grace period between the two — which signal actually ends the
    # sleeper does not matter, and pausing to let TERM land first would put latency straight
    # back into teardown.
    #
    # Do NOT read the sleeper's exit status as evidence about any of this. With no gap
    # between the signals, a sleeper that merely was not scheduled in between dies of KILL
    # and reports 137 even though TERM was delivered perfectly normally — so 137 and 143 are
    # scheduler-dependent outcomes and separate nothing. (An earlier version of this comment
    # cited a count of 137s as "rescues"; it could not have meant that.)
    #
    # What IS measured is the outcome: zero stalls across 7 instrumented suite runs with
    # stop() steady at 2–3ms, against roughly one 30s stall every 2–3 runs without the KILL.
    # And the gate in scripts/test-core.sh does not depend on any of that — it forces the
    # lost-signal case with a sleeper that ignores SIGTERM, where removing this line blocks
    # teardown for the whole interval every single time.
    trap 'kill %% 2>/dev/null; kill -9 %% 2>/dev/null; wait %% 2>/dev/null; exit 0' TERM
    while true; do
      "$su" -n -v 2>/dev/null || true
      sleep "$interval" &
      wait %% 2>/dev/null
      kill -0 "$$" 2>/dev/null || exit 0
    done
  } >/dev/null 2>&1 &
  BLIB_SUDO_KEEPALIVE_PID=$!
}
blib_sudo_keepalive_stop() {
  [[ -n "$BLIB_SUDO_KEEPALIVE_PID" ]] || return 0
  kill "$BLIB_SUDO_KEEPALIVE_PID" 2>/dev/null || true
  # `wait` for the refresher so stop() is synchronous: it returns once the loop has run its
  # TERM trap and torn down its sleeper, rather than leaving both to be reaped whenever.
  # Redirected because bash reports a signal-terminated job on stderr.
  wait "$BLIB_SUDO_KEEPALIVE_PID" 2>/dev/null || true
  BLIB_SUDO_KEEPALIVE_PID=""
}

# ── user bindirs on PATH ──────────────────────────────────────────────────────
# blib_user_bindirs_on_path — prepend the per-user bindirs that language installers write
# into, so a bootstrap's `command -v <tool>` guards tell the TRUTH.
#
# Without this those guards are answered by the PATH of whatever shell launched the
# bootstrap — on a fresh box, bash, which has none of these entries. `cargo install` writes
# ~/.cargo/bin and `go install` writes $GOBIN (~/.local/bin by convention here), while
# ~/.cargo/bin reaches PATH only inside a Core shell, which does not exist yet. So every
# guard reported "missing" and every re-run rebuilt the whole from-source tool set: minutes
# of work, silently discarded, on every single bootstrap.
#
# zsh/00-tools.zsh now prepends this SAME four-dir list, resolved the same way, before it
# probes for HAVE_* flags (#425 — it used to add only ~/.local/bin, and cargo-installed
# tools reached PATH a whole load-order band too late to be detected). The duplication is
# deliberate and the two must stay in step: this file is bash and runs before any Core shell
# exists, that one is zsh and runs in every interactive shell, so neither can source the
# other. Change the dirs or their resolution here, change them there.
#
# Only directories that EXIST are added, and never twice, so this is safe to call more than
# once and cannot inject a bogus PATH entry.
#
# The cargo/go dirs are RELOCATABLE and must be resolved through their env vars, not
# hard-coded: `cargo install` honours $CARGO_HOME and `go install` honours $GOBIN, then
# $GOPATH. Hard-coding ~/.cargo/bin means a box with a custom CARGO_HOME keeps missing its
# installed crates and rebuilding them on every run — the very bug this fixes, just moved
# somewhere less obvious. maint/dotfiles-maint.sh already resolves cargo the same way.
#
# GOPATH is a PATH LIST, and that distinction matters: with GOBIN unset, `go install`
# writes to the bin/ of GOPATH's FIRST entry. Expanding "${GOPATH}/bin" against
# GOPATH=/a:/b would probe the nonexistent "/a:/b/bin" — so the Go tools stay off PATH and
# get rebuilt every run, which is precisely the failure this helper exists to prevent.
# CARGO_HOME, by contrast, IS a single directory, so `${CARGO_HOME:-…}/bin` is correct.
blib_user_bindirs_on_path() {
  local d gobin gopath
  if [[ -n "${GOBIN:-}" ]]; then
    gobin="$GOBIN"
  else
    gopath="${GOPATH:-$HOME/go}"
    gobin="${gopath%%:*}/bin" # first entry only
  fi
  for d in "$HOME/.local/bin" \
    "${CARGO_HOME:-$HOME/.cargo}/bin" \
    "$gobin" \
    "$HOME/.atuin/bin"; do
    [[ -d "$d" ]] || continue
    case ":$PATH:" in
    *":$d:"*) ;;
    *) PATH="$d:$PATH" ;;
    esac
  done
  export PATH
}

# ── deferred failures ─────────────────────────────────────────────────────────
# blib_note_fail / blib_failed_count / blib_failures_report — record a best-effort step
# that did not work, then report them together at the end.
#
# A bootstrap is full of steps that must NOT abort the run: a COPR that is down, a
# rate-limited API, a crate that fails to build. Every one is therefore written `|| true`
# or `|| warn` — and the script then finished with "bootstrap complete" and exit 0, so a
# box that got none of its extra tooling was indistinguishable from a good one, to CI and
# to the operator alike.
#
# blib_failures_report returns non-zero when anything was recorded, so a caller can map
# that onto its own --strict flag.
BLIB_FAILED=()
blib_note_fail() {
  BLIB_FAILED[${#BLIB_FAILED[@]}]="$1" # bash 3.2-safe append (arrays have no += there)
  blib_warn "$1"
}
blib_failed_count() { printf '%s' "${#BLIB_FAILED[@]}"; }
blib_failures_report() {
  ((${#BLIB_FAILED[@]})) || return 0
  printf '\n%s%s%s %s\n' "${UX_YEL:-}" "${UX_WARN:-!}" "${UX_RST:-}" \
    "${#BLIB_FAILED[@]} step(s) did not complete:"
  # `"${arr[@]+"${arr[@]}"}"`: on bash 3.2 `set -u` treats an empty array expansion as
  # unset. The count guard above makes it non-empty here, but keep the idiom so a later
  # edit that moves this line cannot reintroduce the crash.
  printf '    - %s\n' "${BLIB_FAILED[@]+"${BLIB_FAILED[@]}"}"
  printf '\n'
  return 1
}

# ── make zsh the default login shell ──────────────────────────────────────────
# blib_set_login_shell — set zsh as the user's LOGIN shell (a fresh WSL/login session
# starts the login shell, not `exec zsh`). Idempotent: acts only if it isn't already
# zsh. Reads the current shell via getent when present, else straight from /etc/passwd
# (busybox/Alpine has no getent).
blib_set_login_shell() {
  blib_want zsh || return 0   # the default-login-shell switch belongs to the zsh group
  local zsh_path user current
  # command -v also resolves aliases/functions; require a real executable path
  # before we hand it to chsh/usermod (an alias body is not a valid login shell).
  # `|| true`: when zsh is ABSENT (e.g. a links-only run in a bare container with no
  # zsh installed), command -v exits non-zero — and under the caller's `set -e` that
  # failing substitution aborts bootstrap BEFORE the guard below can handle it. Swallow
  # the rc so the empty-path guard is what decides, not errexit.
  zsh_path="$(command -v zsh || true)"
  [[ -n "$zsh_path" && -x "$zsh_path" ]] || return 0
  user="$(id -un)"
  if command -v getent >/dev/null 2>&1; then
    current="$(getent passwd "$user" | cut -d: -f7)"
  else
    # awk with the user as data, not a grep regex — a username containing a regex
    # metacharacter (legal under some NSS setups) would otherwise mis-match.
    current="$(awk -F: -v u="$user" '$1 == u { print $7 }' /etc/passwd)"
  fi
  [[ "$current" == "$zsh_path" ]] && return 0

  if _blib_dry; then
    blib_say "would set login shell to $zsh_path"
    return 0
  fi
  blib_say "setting zsh as default login shell"
  # NEITHER of the next two steps may abort the bootstrap. This runs at the very END of
  # wire_links, after every symlink is already in place, so a box where /etc/shells is
  # read-only or chsh is restricted (a hardened host, an LDAP/SSSD account, a container
  # with a read-only /etc) would throw away a COMPLETE and correct wiring over the one
  # cosmetic step left — and under `set -e` the failure surfaced as a bare `tee:
  # Permission denied` with no explanation of what had or hadn't been done.
  if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
    printf '%s\n' "$zsh_path" | _blib_priv tee -a /etc/shells >/dev/null 2>&1 ||
      blib_warn "could not add $zsh_path to /etc/shells — chsh may refuse it; add that line by hand"
  fi
  if command -v chsh >/dev/null 2>&1; then
    if _blib_priv chsh -s "$zsh_path" "$user"; then
      blib_ok "default shell -> zsh (applies to NEW logins)"
    else
      blib_warn "chsh failed — set it by hand: chsh -s $zsh_path $user (or usermod -s $zsh_path $user)"
    fi
  else
    # blib_warn, not blib_say: the login shell was NOT changed, which is the same outcome
    # as the chsh-failed branch above — it must read like one, on stderr.
    blib_warn "chsh not found (install the 'shadow' package) — set it manually with usermod -s $zsh_path $user"
  fi
}

# ── guard the vendored core/ tree ─────────────────────────────────────────────
# blib_install_core_guard <repo_root> — install a local pre-commit hook that refuses
# commits touching the vendored core/ tree. That tree is overwritten on the next
# `make sync`, so a hand-edit there is silent drift (exactly how the nvim lockfile
# diverged). The hook lives in .git/hooks (untracked, per-machine); sync-core.sh
# (re)installs it on every fan-out, and a bootstrap can call it on a fresh clone.
# Idempotent: it (re)writes OUR hook but never clobbers a pre-existing unrelated one.
# Legitimate sync writes are exempt via $DOTFILES_ALLOW_CORE_EDIT (set by
# sync-core.sh) or the standard `git commit --no-verify`.
blib_install_core_guard() {
  local root="${1:-.}" hooks hook hookspath marker='dotfiles-core-guard'
  # Ask git, not a literal `.git`-dir test: in worktrees and submodules `.git` is a
  # FILE, not a directory, so `[[ -d $root/.git ]]` would wrongly skip the install.
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    blib_warn "core-guard: $root is not a git working tree — skipped"; return 0; }
  # A configured core.hooksPath makes git IGNORE the per-repo hooks dir, so writing
  # into .git/hooks would be a silent no-op (false protection). Warn and skip.
  hookspath="$(git -C "$root" config --get core.hooksPath 2>/dev/null || true)"
  if [[ -n "$hookspath" ]]; then
    blib_warn "core-guard: $root sets core.hooksPath ($hookspath) — skipped; install the guard there yourself"
    return 0
  fi
  # Resolve the real hooks dir (handles worktrees/submodules, where it lives in the
  # common git dir). --git-path returns a path relative to $root, so absolutize it.
  hooks="$(git -C "$root" rev-parse --git-path hooks 2>/dev/null)" || {
    blib_warn "core-guard: $root — could not resolve the git hooks dir — skipped"; return 1; }
  [[ "$hooks" = /* ]] || hooks="$root/$hooks"
  hook="$hooks/pre-commit"
  if [[ -e "$hook" ]] && ! grep -q "$marker" "$hook" 2>/dev/null; then
    blib_warn "core-guard: $root already has a custom pre-commit hook — left as-is"
    return 0
  fi
  # Surface a failure to create the hooks dir instead of silently returning success
  # (a returned 0 would leave the guard uninstalled with no signal to the caller).
  mkdir -p "$hooks" || { blib_warn "core-guard: $root — could not create $hooks — skipped"; return 1; }
  cat >"$hook" <<'HOOK'
#!/usr/bin/env bash
# dotfiles-core-guard — installed by dotfiles-core; do not edit by hand.
# Refuses commits that modify the vendored core/ tree, which is OVERWRITTEN on the
# next `make sync` — so a hand-edit there is silent drift. Edit Core upstream in
# dotfiles-core instead. Legitimate sync writes set DOTFILES_ALLOW_CORE_EDIT=1; or
# bypass once with `git commit --no-verify`.
[ -n "${DOTFILES_ALLOW_CORE_EDIT:-}" ] && exit 0
# No --diff-filter: catch EVERY staged change under core/ — adds/mods/renames AND
# deletions (git rm core/…) and type changes, which drift from canonical Core too.
staged=$(git diff --cached --name-only -- core/ 2>/dev/null) || exit 0
[ -z "$staged" ] && exit 0
{
  printf 'dotfiles-core-guard: refusing to commit edits to the vendored core/ tree:\n'
  printf '%s\n' "$staged" | sed 's/^/    /'
  printf '%s\n' \
    '' \
    'core/ is a vendored copy of dotfiles-core, overwritten on the next `make sync`.' \
    'Fix it upstream in dotfiles-core (make audit), then `make sync` to fan it out.' \
    'Override for a real sync:  DOTFILES_ALLOW_CORE_EDIT=1 git commit …   (or: git commit --no-verify)'
} >&2
exit 1
HOOK
  chmod +x "$hook"
  blib_ok "core-guard: pre-commit installed in ${root##*/}"
}
