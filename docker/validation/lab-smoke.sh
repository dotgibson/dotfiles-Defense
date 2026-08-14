#!/usr/bin/env bash
# docker/validation/lab-smoke.sh — prove the detection lab actually boots.
#
# WHY. Phases 0–2 of LAB-VALIDATION-PLAN.md are gated: the network plane runs through real
# Zeek/Suricata, and the host + cloud Sigma planes run through zircolite and sigma_eval.
# None of them need the lab, because the whole design is replay-against-fixtures. Which
# means the lab itself — the OpenSearch + Dashboards stack behind `siemup`, a headline verb
# of this repo — was never started by anything. Its compose file was checked for VALIDITY
# (`docker compose config`), which proves it parses and nothing more.
#
# This starts it for real and asserts the two things that make it useful:
#   1. OpenSearch reaches cluster health green|yellow (the compose healthcheck's own bar)
#   2. Dashboards reaches overall green/available — which also proves it authenticated to
#      OpenSearch, so it is the check that exercises the credential wiring end to end
#
# `compose up --wait` does the first for us: it blocks on the healthcheck, and Dashboards
# declares `depends_on: {opensearch: {condition: service_healthy}}`, so a stack that never
# goes healthy fails the command rather than hanging.
#
# SAFE TO RUN ON A DEV BOX, with one caveat it enforces: if the lab is ALREADY running it
# refuses, rather than tearing down a lab you are using. Pass --force to override.
#
# Memory: OpenSearch is pinned to a 1 GB heap and Dashboards wants a few hundred MB more, so
# this needs roughly 3 GB free. CI runners have it; a small laptop may not, which is exactly
# why this is a script CI calls rather than something wired into the fast test suite.
#
# Usage: docker/validation/lab-smoke.sh [--force] [--keep]
#          --force  proceed even if the stack is already up (tears it down first)
#          --keep   leave the stack running afterwards (default: always tear down)
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO" || exit 1

force=0
keep=0
for a in "$@"; do
  case "$a" in
  --force) force=1 ;;
  --keep) keep=1 ;;
  -h | --help)
    sed -n '2,31p' "$0"
    exit 0
    ;;
  *)
    echo "unknown arg: $a" >&2
    exit 1
    ;;
  esac
done

stack="${DEFENSE_STACK:-detection-lab}"
compose_file="docker/${stack}.compose.yml"
env_file="docker/.env"
[ -r "$compose_file" ] || {
  echo "::error::no compose file: $compose_file"
  exit 1
}

compose() { docker compose --env-file "$env_file" -f "$compose_file" "$@"; }

# ── refuse to disturb a lab in use ────────────────────────────────────────────
if [ "$force" -eq 0 ] && [ -r "$env_file" ] &&
  [ -n "$(compose ps -q 2>/dev/null)" ]; then
  echo "the $stack stack is already running — refusing to disturb it." >&2
  echo "re-run with --force to tear it down and smoke-test from cold." >&2
  exit 1
fi

# ── credentials ───────────────────────────────────────────────────────────────
# An existing docker/.env is a real local secret: use it, never overwrite it. Only when
# there is none (CI, a fresh clone) do we mint a throwaway one. OpenSearch 2.12+ enforces
# complexity, so the generated password must satisfy it or the container refuses to start
# — which would look like a stack failure rather than a bad password.
created_env=0
if [ ! -r "$env_file" ]; then
  # head closing the pipe gives tr a SIGPIPE and a "write error: Broken pipe" on stderr,
  # which looks like a failure in the log of a job whose whole job is to be trustworthy.
  pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 24)Aa1!"
  umask 077
  sed "s|^OPENSEARCH_INITIAL_ADMIN_PASSWORD=.*|OPENSEARCH_INITIAL_ADMIN_PASSWORD=${pw}|" \
    docker/"${stack}".env.example >"$env_file"
  created_env=1
  echo ":: minted a throwaway $env_file for this run"
fi
# shellcheck disable=SC1090,SC1091
admin_pw="$(sed -n 's/^OPENSEARCH_INITIAL_ADMIN_PASSWORD=//p' "$env_file" | head -n1)"
[ -n "$admin_pw" ] && [ "$admin_pw" != "SET_ME" ] || {
  echo "::error::$env_file has no usable OPENSEARCH_INITIAL_ADMIN_PASSWORD (the example ships an intentionally invalid SET_ME)" >&2
  exit 1
}

cleanup() {
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo
    echo ":: stack failed — logs follow"
    compose logs --no-color --tail=60 2>&1 | sed 's/^/   /'
  fi
  if [ "$keep" -eq 0 ]; then
    echo ":: tearing down"
    compose down --remove-orphans >/dev/null 2>&1
  else
    echo ":: leaving the stack up (--keep)"
  fi
  # Never leave a minted secret behind; a real one is left exactly as found.
  [ "$created_env" -eq 1 ] && [ "$keep" -eq 0 ] && rm -f "$env_file"
  exit "$rc"
}
trap cleanup EXIT

# ── prepare the bind-mount target ─────────────────────────────────────────────
# Found by this script's first-ever run: the compose mounts ./<stack>/data/opensearch, and
# where that directory does not exist Docker creates it ROOT-owned. The OpenSearch image
# runs as uid 1000, so the node dies with
#   AccessDeniedException: /usr/share/opensearch/data/nodes
# and the stack never becomes healthy. It only bites a FIRST boot, which is why a lab that
# has run before never shows it — and why nothing had ever caught it.
#
# siemup does the same thing for real users (defense.zsh, _siem_data_dir). Here we can also
# chown, because CI has passwordless sudo and its runner uid is not 1000.
data_dir="docker/${stack}/data/opensearch"
mkdir -p "$data_dir"
owner="$(stat -c '%u' "$data_dir" 2>/dev/null || echo unknown)"
if [ "$owner" != "1000" ]; then
  if sudo -n true 2>/dev/null; then
    sudo chown -R 1000:1000 "docker/${stack}/data"
    echo ":: chowned $data_dir to uid 1000 (OpenSearch's user)"
  else
    echo "::error::$data_dir is owned by uid $owner but OpenSearch runs as uid 1000."
    echo "   fix: sudo chown -R 1000:1000 docker/${stack}/data"
    exit 1
  fi
fi

# ── boot ──────────────────────────────────────────────────────────────────────
echo ":: starting $stack (this pulls ~1 GB on a cold cache)"
compose up -d --wait --wait-timeout 300 || {
  echo "::error::the stack did not become healthy within 300s"
  exit 1
}
echo ":: all services report healthy"

# ── assert OpenSearch is genuinely serving ────────────────────────────────────
health="$(curl -sk -u "admin:${admin_pw}" https://localhost:9200/_cluster/health 2>/dev/null)"
case "$health" in
*'"status":"green"'* | *'"status":"yellow"'*)
  echo ":: opensearch cluster health OK"
  ;;
*)
  echo "::error::opensearch did not report green/yellow: ${health:-<no response>}"
  exit 1
  ;;
esac

# ── assert Dashboards is up AND authenticated to OpenSearch ───────────────────
# The only check here that exercises the credential wiring end to end: Dashboards reports
# "available" only once it has actually talked to OpenSearch with the admin password.
#
# RETRIED, deliberately. `compose up --wait` waits for a service to be *healthy* only where
# a healthcheck exists; Dashboards declares none, so --wait considers it ready the moment
# the container is RUNNING. Its Node process then takes a while to serve /api/status, so a
# single-shot curl races the app's startup and would fail intermittently — a flaky check
# nobody trusts is worse than no check.
# AUTHENTICATED, and that is the point rather than an inconvenience. OpenSearch ships the
# security plugin enabled, so Dashboards answers /api/status with 401 until credentials are
# supplied — the first run of this check learned that the hard way. Passing the admin
# password here is what makes this an end-to-end credential assertion: a wrong password in
# docker/.env fails at this line rather than silently producing a lab nobody can log into.
status=""
for _ in $(seq 1 30); do
  status="$(curl -s --max-time 5 -u "admin:${admin_pw}" http://localhost:5601/api/status 2>/dev/null)"
  case "$status" in
  *'"state":"green"'* | *'"level":"available"'*) break ;;
  esac
  sleep 5
done

case "$status" in
*'"state":"green"'* | *'"level":"available"'*)
  echo ":: dashboards available (and authenticated to opensearch)"
  ;;
*)
  echo "::error::dashboards did not reach overall green/available within 150s: $(printf '%s' "${status:-<no response>}" | head -c 300)"
  exit 1
  ;;
esac

# Both spellings are accepted because Dashboards 2.x reports status.overall.state
# ("green") while other builds report .level ("available"); pinning to one would make this
# fail on a version bump for no real reason.
#
# This asserts the FULL bar again. It was briefly relaxed to "serves an authenticated
# status document", because the compose authenticated Dashboards as `admin` and the
# security plugin then 403'"'"'d on /_plugins/_security/tenantinfo, so overall status never
# went green. That was a defect in the stack rather than in the check, and it is now fixed
# at the source: the compose uses the `kibanaserver` service account the plugin actually
# grants those privileges to.

echo
echo "detection lab smoke test passed: opensearch healthy, dashboards available"
