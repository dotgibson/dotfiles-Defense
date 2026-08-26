#!/usr/bin/env bash
# detections/sigma/convert.sh — compile every Sigma rule to a SIEM backend.
#
# Sigma is the source of truth; this is the "compile to your backend" step from
# DEFENSE-METHODOLOGY.md, made reproducible. It compiles each rule with the chosen
# pySigma backend (default: splunk) and prints the query per tactic dir. It is also
# the local twin of the CI smoke test in .github/workflows/sigma.yml, which runs the
# same `sigma convert` to prove every rule still compiles.
#
# --without-pipeline keeps raw logical field names (good for a compile/validation
# check). For DEPLOYABLE output, add a processing pipeline that maps fields to your
# data model, e.g.:  sigma convert -t splunk -p splunk_windows detections/sigma/<dir>/
#
# Usage:  detections/sigma/convert.sh [backend]      # default backend: splunk
# Deps:   sigma-cli + the backend plugin
#         pip install sigma-cli pysigma-backend-splunk
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BACKEND="${1:-splunk}"

# `sigma` (PyPI sigma-cli entrypoint, what CI installs) or `sigma-cli` (distro packages).
# SIGMA_BIN overrides both.
SIGMA_BIN="${SIGMA_BIN:-$(command -v sigma 2>/dev/null || command -v sigma-cli 2>/dev/null || true)}"
if [[ -z "$SIGMA_BIN" ]]; then
  echo "neither 'sigma' nor 'sigma-cli' found — pip install sigma-cli pysigma-backend-${BACKEND}" >&2
  exit 1
fi

# Present-but-backendless is a real state: distro packages ship the CLI without backends.
# `sigma plugin list` cannot tell us (it lists installable, not installed), but an invalid
# target makes the CLI enumerate what it actually has.
probe="$("$SIGMA_BIN" convert -t __probe__ /dev/null 2>&1 || true)"
if [[ "$probe" == *"is not one of"* ]]; then
  have="$(printf '%s' "$probe" | sed -n "s/.*is not one of \(.*\)\. - run.*/\1/p" | tr -d "' ")"
  case ",$have," in
  *",$BACKEND,"*) ;;
  *)
    echo "$SIGMA_BIN has no '$BACKEND' backend — installed: ${have:-(none)}" >&2
    echo "  pip install pysigma-backend-${BACKEND}" >&2
    exit 1
    ;;
  esac
fi

rc=0
for dir in "$HERE"/*/; do
  [[ -d "$dir" ]] || continue
  printf '\n### %s\n' "$(basename "$dir")"
  "$SIGMA_BIN" convert -t "$BACKEND" --without-pipeline "$dir" || rc=1
done
exit "$rc"
