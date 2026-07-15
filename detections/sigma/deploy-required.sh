#!/usr/bin/env bash
# deploy-required.sh — the pre-deploy checklist for Sigma rules that ship a placeholder.
# ──────────────────────────────────────────────────────────────────────────────
# A handful of rules can't be meaningful until an operator substitutes an
# environment-specific value — a delegation-admin list, the real DC computer accounts,
# sanctioned app (client) IDs, known Snowflake stages. Those spots carry a
# `DEPLOY-REQUIRED:` marker in a YAML comment. A "# replace me" note isn't enforcement,
# so this makes the list DISCOVERABLE: run it before deploying and fill each one.
#
#   deploy-required.sh          # list every rule + its DEPLOY-REQUIRED line(s)
#
# Advisory by design — it ALWAYS exits 0. The repo ships the placeholders on purpose
# (they're deploy-time, not repo-time), so this reports; it does not gate CI. Wiring it
# as a hard gate would fail on the intentional placeholders.
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
MARKER='DEPLOY-REQUIRED'

count=0
while IFS= read -r -d '' file; do
  if grep -q "$MARKER" -- "$file"; then
    count=$((count + 1))
    printf '\n%s\n' "${file#"$HERE"/}"
    grep -n "$MARKER" -- "$file" | sed 's/^/  /'
  fi
done < <(find "$HERE" -type f -name '*.yml' -print0 | sort -z)

if [[ "$count" -eq 0 ]]; then
  echo "deploy-required: no DEPLOY-REQUIRED markers found — nothing to substitute."
else
  printf '\n%d rule file(s) need a deploy-time substitution before they are meaningful.\n' "$count"
fi
