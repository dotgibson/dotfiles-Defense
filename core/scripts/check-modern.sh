#!/usr/bin/env bash
# scripts/check-modern.sh
# ──────────────────────────────────────────────────────────────────────────────
# Enforce scripts/modern-baseline.yml against this repo's GitHub Actions workflows
# and composite actions. This is the "ensure" half of the modernization floor: the
# baseline DECLARES what modern means, this script CHECKS it, and audit-core.sh runs
# it as a gate (section 8c) so CI can't silently regress below the floor.
#
# Exit 0 = meets the floor. Exit 1 = one or more violations (printed to stderr).
# Run standalone (`./scripts/check-modern.sh` / `make check-modern`) or via the audit.
# Pure bash + awk/grep (busybox-safe); the flat baseline schema is parsed without a
# YAML library — the same "no dependency" discipline as tool-versions.env.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
BASELINE="scripts/modern-baseline.yml"
[ -r "$BASELINE" ] || { echo "check-modern: $BASELINE missing" >&2; exit 1; }

# ── minimal greppable-YAML readers (flat schema only: scalars + `- ` lists) ──────
_yaml_list() { # $1 = key → each list item, dequoted
  awk -v k="$1" '
    $0 ~ "^"k":[[:space:]]*$" { f=1; next }
    /^[A-Za-z_]/ { f=0 }
    f && /^[[:space:]]*-[[:space:]]*/ {
      sub(/^[[:space:]]*-[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); gsub(/^"|"$/, ""); print
    }
  ' "$BASELINE"
}
_yaml_bool() { grep -qE "^$1:[[:space:]]*true([[:space:]]|\$)" "$BASELINE"; }
_yaml_val()  { sed -nE "s/^$1:[[:space:]]*//p" "$BASELINE" | head -n1 | tr -d '"'; }

# ── the files we gate: workflows + composite actions ─────────────────────────
# Plain read loop, not `mapfile` — macOS ships bash 3.2 (no mapfile), which the audit
# runs this under, same bash-3.2 discipline as the rest of Core.
FILES=()
while IFS= read -r _f; do [ -n "$_f" ] && FILES+=("$_f"); done < <(git ls-files \
  '.github/workflows/*.yml' '.github/workflows/*.yaml' \
  '.github/actions/*/action.yml' '.github/actions/*/action.yaml' 2>/dev/null)
[ "${#FILES[@]}" -gt 0 ] || { echo "check-modern: no workflow/action files to check"; exit 0; }

violations=0
note() { printf '  ✗ %s\n' "$*" >&2; violations=$((violations + 1)); }

# ── 1) banned deprecated workflow-command patterns ───────────────────────────
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  while IFS= read -r hit; do note "banned pattern ($pat): $hit"; done \
    < <(grep -HnF -- "$pat" "${FILES[@]}" 2>/dev/null || true)
done < <(_yaml_list banned_patterns)

# ── 2) banned EOL runner labels (in runs-on: or a matrix os: list) ───────────
while IFS= read -r rn; do
  [ -n "$rn" ] || continue
  while IFS= read -r hit; do note "EOL runner ($rn): $hit"; done \
    < <(grep -HnE "(runs-on|os):.*(^|[[:space:],\"'[])${rn}([[:space:],\"'*]|\]|\$)" "${FILES[@]}" 2>/dev/null || true)
done < <(_yaml_list banned_runners)

# ── 3) external action `uses:` must pin a 40-hex SHA (fleet's own owner exempt) ─
if _yaml_bool require_action_sha_pin; then
  exempt="$(_yaml_val sha_pin_exempt_owner)"
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    ref="${m##*@}"
    spec="${m#*uses:}"; spec="${spec#"${spec%%[![:space:]]*}"}"  # text after `uses:`, ltrimmed
    owner="${spec%%/*}"
    { [ -n "$exempt" ] && [ "$owner" = "$exempt" ]; } && continue   # own reusable workflows: @vN policy
    printf '%s' "$ref" | grep -qE '^[0-9a-f]{40}$' || note "unpinned action (need a 40-hex SHA): $m"
  done < <(grep -HnoE "uses:[[:space:]]*[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[^[:space:]\"']+" "${FILES[@]}" 2>/dev/null || true)
fi

# ── 4) container images must pin an @sha256: digest ──────────────────────────
# Scope to the two places images appear (an `image:` value or a `docker run|build|pull`
# command) so arbitrary `key:value` text in run-scripts isn't mistaken for an image.
if _yaml_bool require_container_digest_pin; then
  img_re='([a-z0-9]+([._-][a-z0-9]+)*/)*[a-z0-9]+([._-][a-z0-9]+)*:[a-z0-9][a-z0-9._-]*(@sha256:[0-9a-f]+)?'
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    content="${line#*:*:}"   # strip grep's file:linenum: prefix (it looks like path/name:tag)
    while IFS= read -r img; do
      [ -n "$img" ] || continue
      case "$img" in *@sha256:*) continue ;; esac       # already digest-pinned
      note "container image not digest-pinned ($img): $line"
    done < <(printf '%s\n' "$content" | grep -oE "$img_re" 2>/dev/null || true)
  done < <(grep -HnE '(^[[:space:]]*image:[[:space:]]|docker[[:space:]]+(run|build|pull))' "${FILES[@]}" 2>/dev/null || true)
fi

if [ "$violations" -eq 0 ]; then
  echo "check-modern: CI meets the modern baseline (${#FILES[@]} workflow/action files)"
  exit 0
fi
printf 'check-modern: %d violation(s) below the floor (scripts/modern-baseline.yml)\n' "$violations" >&2
exit 1
