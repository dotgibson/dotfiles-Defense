#!/usr/bin/env bash
# scripts/update-plugins.sh
# ──────────────────────────────────────────────────────────────────────────────
# Deliberately roll the pinned zsh-plugin revisions in zsh/plugins.zsh forward to
# each upstream's current default-branch HEAD. This is the runtime-plugin mirror of
# `make update-hooks` (pre-commit autoupdate) and the manual SHELLCHECK_VERSION /
# LUACHECK_VERSION bumps in ci.yml: pins exist so nothing floats silently into the
# 9 OS repos, and THIS is the one place they move — under review, not on their own.
#
# Single source of truth: the ZPLUGIN_PINS associative array in zsh/plugins.zsh.
# We parse the `owner/name  <40-hex sha>` rows straight out of it, `git ls-remote`
# each for HEAD, and rewrite only the SHA in place — so the plugin LIST never has
# to be repeated here and can never drift from what actually loads.
#
# Usage:
#   ./scripts/update-plugins.sh            # bump every pin to upstream HEAD, in place
#   ./scripts/update-plugins.sh --dry-run  # show what WOULD change, touch nothing
#   ./scripts/update-plugins.sh --check    # like --dry-run but EXIT 2 if any pin is
#                                            stale — the freshness GATE the weekly
#                                            .github/workflows/freshness.yml runs so a
#                                            rotting pin is surfaced proactively (the
#                                            runtime-plugin analog of dependabot, which
#                                            only watches the github-actions ecosystem).
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1
PLUGINS_FILE="zsh/plugins.zsh"

# _verify_pin <slug> <sha> — prove a rolled pin is actually USABLE before it can be
# committed + fanned out: shallow-fetch EXACTLY that commit (the same way plugins.zsh
# installs a pin), resolve the entry file (mirroring _zplugin_load's search order), and
# `zsh -n` it. The behavioral suite pre-seeds EMPTY plugin dirs (no network), so it never
# touches the real pinned code — a HEAD that 404s, vanished to GC, or won't parse would
# otherwise sail through `make audit` and ship to 9 repos. Returns 0 = loads; non-zero else.
_verify_pin() {
  local slug="$1" sha="$2" d f src="" rc=0
  local name="${slug##*/}" # separate `local`: same-statement refs to slug don't take effect (SC2318)
  d="$(mktemp -d "${TMPDIR:-/tmp}/verify-pin.XXXXXX")" || return 2
  if git init -q "$d" 2>/dev/null &&
    git -C "$d" remote add origin "https://github.com/${slug}" 2>/dev/null &&
    git -C "$d" fetch -q --depth 1 origin "$sha" 2>/dev/null &&
    git -C "$d" checkout -q --detach FETCH_HEAD 2>/dev/null; then
    # Mirror _zplugin_load's entry-file resolution, INCLUDING its srcfile override: the one
    # pinned plugin whose entry doesn't match ${name}.* is zsh-you-should-use, loaded as
    # you-should-use.plugin.zsh (plugins.zsh) — i.e. the name with the leading `zsh-` dropped.
    # Cover that with ${name#zsh-}.plugin.zsh so rolling its pin doesn't falsely fail (rc=4).
    # (zsh-syntax-highlighting's entry is zsh-syntax-highlighting.zsh — matched by $name.zsh.)
    for f in "$name.plugin.zsh" "$name.zsh" "$name.sh" "${name#zsh-}.plugin.zsh"; do
      [[ -f "$d/$f" ]] && {
        src="$d/$f"
        break
      }
    done
    if [[ -z "$src" ]]; then
      rc=4
    elif ! zsh -n "$src" 2>/dev/null; then rc=5; fi
  else
    rc=3
  fi
  rm -rf "$d"
  return "$rc"
}

# --check is a non-mutating drift report (implies dry-run) that exits 2 when behind.
DRY=0
CHECK=0
case "${1:-}" in
--dry-run | -n) DRY=1 ;;
--check) DRY=1 CHECK=1 ;;
"") ;;
-h | --help)
  cat <<'EOF'
update-plugins.sh — roll the pinned zsh-plugin SHAs in zsh/plugins.zsh to upstream HEAD.

  ./scripts/update-plugins.sh            bump every pin to upstream HEAD, in place
  ./scripts/update-plugins.sh --dry-run  show what WOULD change, touch nothing
  ./scripts/update-plugins.sh --check    like --dry-run but exit 2 if any pin is stale
                                         (the freshness gate .github/workflows/freshness.yml runs)
EOF
  exit 0
  ;;
*)
  printf 'update-plugins.sh: unexpected argument: %s (try --help)\n' "$1" >&2
  exit 2
  ;;
esac
# Reject a stray extra operand too (e.g. `--check extra`), matching the arg discipline
# in scripts/bench-core.sh / audit-core.sh — a silent ignore makes typos easy to miss.
if (($# > 1)); then
  printf 'update-plugins.sh: unexpected argument: %s (try --help)\n' "$2" >&2
  exit 2
fi

# Shared palette + have() (this script keeps its own ↑/– pin-row formatting below).
# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

have git || {
  printf '%s✗%s git not found — required to resolve upstream SHAs\n' "$c_red" "$c_rst" >&2
  exit 1
}
[[ -f "$PLUGINS_FILE" ]] || {
  printf '%s✗%s %s not found\n' "$c_red" "$c_rst" "$PLUGINS_FILE" >&2
  exit 1
}

# Pull the `owner/name  <sha>` rows out of ZPLUGIN_PINS. The grep matches a slug
# (owner/name) followed by a 40-hex commit — the exact shape of a pin row, so the
# array's comments and braces are ignored without needing to track block bounds.
# Read loop, NOT `mapfile` — mapfile is bash 4+, and this tooling must also run on
# macOS's stock bash 3.2 (the same constraint audit-core.sh documents for the gate).
ROWS=()
while IFS= read -r _row; do ROWS+=("$_row"); done < <(
  grep -oE '[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+[[:space:]]+[0-9a-f]{40}' "$PLUGINS_FILE"
)
[[ ${#ROWS[@]} -gt 0 ]] || {
  printf '%s✗%s no pinned plugins found in %s (is ZPLUGIN_PINS populated?)\n' "$c_red" "$c_rst" "$PLUGINS_FILE" >&2
  exit 1
}

printf '%s== rolling %d plugin pin(s) → upstream HEAD%s ==%s\n' \
  "$c_blu" "${#ROWS[@]}" "$([[ $DRY == 1 ]] && echo '  (dry-run)')" "$c_rst"

changed=0
fail=0
CHANGED_PINS=()
for row in "${ROWS[@]}"; do
  slug="${row%%[[:space:]]*}" # owner/name
  old="${row##*[[:space:]]}"  # current 40-hex sha
  new="$(git ls-remote "https://github.com/${slug}" HEAD 2>/dev/null | awk 'NR==1{print $1}')"
  if [[ -z "$new" ]]; then
    printf '%s✗%s %-44s could not reach upstream\n' "$c_red" "$c_rst" "$slug" >&2
    fail=1
    continue
  fi
  if [[ "$new" == "$old" ]]; then
    printf '%s–%s %-44s up to date (%s)\n' "$c_yel" "$c_rst" "$slug" "${old:0:12}"
    continue
  fi
  printf '%s↑%s %-44s %s → %s\n' "$c_grn" "$c_rst" "$slug" "${old:0:12}" "${new:0:12}"
  changed=$((changed + 1))
  ((DRY)) && continue
  CHANGED_PINS+=("$slug $new") # remember for the post-roll load verification below
  # Replace just this pin's SHA. Both old and new are 40-hex, so the literal old
  # SHA is unique in the file — a plain in-place substitution is unambiguous.
  tmp="$(mktemp "${PLUGINS_FILE}.XXXXXX")"
  sed "s/${old}/${new}/" "$PLUGINS_FILE" >"$tmp" && mv "$tmp" "$PLUGINS_FILE"
done

if ((fail)); then
  printf '%ssome upstreams were unreachable — pins left unchanged for those%s\n' "$c_red" "$c_rst" >&2
  exit 1
fi

# ── post-roll load verification (B13) ─────────────────────────────────────────
# A roll just rewrote SHAs the audit can't validate (its hermetic suite uses EMPTY
# plugin dirs). Prove each rolled pin fetches + parses BEFORE you commit it. zsh-gated
# + graceful (no zsh → a notice, not a hard stop, mirroring the gate scripts).
if ((!DRY)) && ((${#CHANGED_PINS[@]})); then
  if have zsh; then
    printf '%s== verifying %d rolled pin(s) fetch + parse ==%s\n' "$c_blu" "${#CHANGED_PINS[@]}" "$c_rst"
    vfail=0
    for _pair in "${CHANGED_PINS[@]}"; do
      _slug="${_pair%% *}"
      _sha="${_pair##* }"
      _verify_pin "$_slug" "$_sha"
      _rc=$?
      if ((_rc == 0)); then
        printf '%s✓%s %-44s fetches + parses (zsh -n)\n' "$c_grn" "$c_rst" "$_slug"
      else
        printf '%s✗%s %-44s rolled pin FAILED verification (rc=%d)\n' "$c_red" "$c_rst" "$_slug" "$_rc" >&2
        vfail=1
      fi
    done
    if ((vfail)); then
      printf '%sone or more rolled pins do not load — do NOT commit; revert them in %s%s\n' "$c_red" "$PLUGINS_FILE" "$c_rst" >&2
      exit 1
    fi
  else
    printf '%s–%s zsh absent — cannot verify rolled pins load; run make audit on a box with zsh before committing\n' "$c_yel" "$c_rst" >&2
  fi
fi

if ((CHECK)); then
  # Freshness gate: exit 2 (distinct from the unreachable-upstream exit 1 above) when
  # any pin is behind, so the scheduled workflow can surface drift; 0 when all current.
  if ((changed)); then
    printf '%s%d plugin pin(s) are BEHIND upstream — run: make update-plugins%s\n' "$c_yel" "$changed" "$c_rst" >&2
    exit 2
  fi
  printf '%s✓ all plugin pins current.%s\n' "$c_grn" "$c_rst"
  exit 0
fi
if ((DRY)); then
  printf '%s%d pin(s) would change. Re-run without --dry-run to apply.%s\n' "$c_blu" "$changed" "$c_rst"
elif ((changed)); then
  printf '%s✓ %d pin(s) updated in %s — review the diff, run make audit, then commit.%s\n' \
    "$c_grn" "$changed" "$PLUGINS_FILE" "$c_rst"
else
  printf '%s✓ all pins already current.%s\n' "$c_grn" "$c_rst"
fi
