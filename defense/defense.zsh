# dotfiles-Defense/defense/defense.zsh
# ──────────────────────────────────────────────────────────────────────────────
# The DEFENSE (blue) layer. Sourced by the Defense .zshrc loader in its own stage:
#   tools → … → op → maint → update → os → DEFENSE → local
# (mirror of Kali's `offensive` stage — the blue role no other repo has.)
#
# Same discipline as Core/Kali: every alias/function touching an optional tool is
# GUARDED by a HAVE_* flag, so this file is inert on a box where the tool isn't
# installed instead of erroring on shell start. Distro-agnostic — tools come from
# whatever OS-native layer you run; the heavy stack runs in Docker (siemup).
#
# Investigation DATA never lives in this repo — it lives in $CASES_DIR
# (default ~/cases), which the repo .gitignore also blocks as a backstop.
# ──────────────────────────────────────────────────────────────────────────────

# Interactive shells only — scripts get raw POSIX (mirrors Core's tools.zsh).
[[ $- == *i* ]] || return 0

_have() { command -v "$1" >/dev/null 2>&1; }

# ── Detection: HAVE_* flags for the blue stack ───────────────────────────────
# Network / packet
_have zeek        && HAVE_ZEEK=1
_have suricata    && HAVE_SURICATA=1
_have tshark      && HAVE_TSHARK=1
_have ngrep       && HAVE_NGREP=1
# Windows log triage
_have chainsaw    && HAVE_CHAINSAW=1
_have hayabusa    && HAVE_HAYABUSA=1
_have evtx_dump   && HAVE_EVTXDUMP=1
# Detection content
_have sigma       && HAVE_SIGMA=1        # sigma-cli / pySigma
_have yara        && HAVE_YARA=1
# Endpoint / live response / forensics
_have velociraptor && HAVE_VELO=1
_have osqueryi    && HAVE_OSQUERY=1
_have vol         && HAVE_VOL=1          # Volatility 3
_have log2timeline.py && HAVE_PLASO=1
# Lab / containers
_have docker      && HAVE_DOCKER=1
# jq is the universal log scalpel; many helpers below assume it
_have jq          && HAVE_JQ=1

# ── Workspace root (OUTSIDE the repo — keep it that way) ─────────────────────
: "${CASES_DIR:=$HOME/cases}"
: "${DEFENSE_DIR:=${${(%):-%x}:A:h:h}}"   # repo root (this file is defense/defense.zsh)
export CASES_DIR DEFENSE_DIR

# ── Tool ergonomics (guarded) ─────────────────────────────────────────────────
[[ -n ${HAVE_CHAINSAW:-} ]] && alias hunt-evtx='chainsaw hunt --mapping /usr/share/chainsaw/mappings/sigma-event-logs-all.yml -s'
[[ -n ${HAVE_SIGMA:-}    ]] && alias sigma-lint='sigma check'
[[ -n ${HAVE_TSHARK:-}   ]] && alias pcap-conv='tshark -q -z conv,tcp -r'
[[ -n ${HAVE_VELO:-}     ]] && alias velo='velociraptor'

# ── Detection lab: bring the Docker stack up / down ──────────────────────────
# Compose lives in $DEFENSE_DIR/docker. Override which stack with DEFENSE_STACK.
: "${DEFENSE_STACK:=detection-lab}"
_compose() {  # prefer Compose v2 (`docker compose`); warn on the EOL v1 fallback
  # Auto-load docker/.env (gitignored) so the real stack gets its secrets — the
  # placeholder stub needs none, so a missing file is fine.
  local envfile="$DEFENSE_DIR/docker/.env" envargs=()
  [[ -f "$envfile" ]] && envargs=(--env-file "$envfile")
  if docker compose version >/dev/null 2>&1; then
    docker compose "${envargs[@]}" "$@"
  else
    # Legacy docker-compose v1 is EOL and ignores `depends_on: condition:
    # service_healthy` — the detection lab's health-gating won't apply. Still run it.
    echo "⚠ using legacy docker-compose (v1) — install Compose v2 for health-gated startup" >&2
    docker-compose "${envargs[@]}" "$@"
  fi
}
siemup() {
  [[ -n ${HAVE_DOCKER:-} ]] || { echo "docker not installed" >&2; return 1; }
  local f="$DEFENSE_DIR/docker/${DEFENSE_STACK}.compose.yml"
  [[ -f "$f" ]] || { echo "no compose file: $f" >&2; return 1; }
  echo ":: bringing up '$DEFENSE_STACK' (detached)"; _compose -f "$f" up -d
}
siemdown() {
  [[ -n ${HAVE_DOCKER:-} ]] || { echo "docker not installed" >&2; return 1; }
  local f="$DEFENSE_DIR/docker/${DEFENSE_STACK}.compose.yml"
  [[ -f "$f" ]] || { echo "no compose file: $f" >&2; return 1; }
  _compose -f "$f" down "$@"
}
siemlogs() {
  [[ -n ${HAVE_DOCKER:-} ]] || { echo "docker not installed" >&2; return 1; }
  local f="$DEFENSE_DIR/docker/${DEFENSE_STACK}.compose.yml"
  [[ -f "$f" ]] || { echo "no compose file: $f" >&2; return 1; }
  _compose -f "$f" logs -f "$@"
}

# ── Case scaffolding ──────────────────────────────────────────────────────────
# mkcase <name> — create a dated, structured investigation workspace and cd into
# it. Sets $CASE for the session so other helpers target it. case.md (the brief)
# is created FIRST and opened so scope/authorization is written down before work.
mkcase() {
  [[ -z "$1" ]] && { echo "Usage: mkcase <incident-or-codename>" >&2; return 1; }
  local slug name root
  slug=$(echo "$1" | tr '[:upper:] ' '[:lower:]_' | tr -cd '[:alnum:]_-')
  name="$(date +%Y%m%d)-${slug}"
  root="$CASES_DIR/$name"
  if [[ -d "$root" ]]; then
    echo "Case already exists: $root"; export CASE="$root"; cd "$root"; return 0
  fi
  mkdir -p "$root"/{evidence,network,timeline,iocs,report,notes}
  if [[ -f "$DEFENSE_DIR/defense/templates/case.md" ]]; then
    sed "s/__CASE__/$name/; s/__CREATED__/$(date +%Y-%m-%dT%H:%M:%S%z)/" \
      "$DEFENSE_DIR/defense/templates/case.md" > "$root/case.md"
  else
    printf 'CASE: %s\nCREATED: %s\n' "$name" "$(date +%Y-%m-%dT%H:%M:%S%z)" > "$root/case.md"
  fi
  [[ -f "$DEFENSE_DIR/defense/templates/hunt.md" ]] && cp "$DEFENSE_DIR/defense/templates/hunt.md" "$root/hunt.md"
  : > "$root/notes/notes.md"
  export CASE="$root"; cd "$root"
  echo "✓ case at $root  (\$CASE set)"
  echo "  → fill in case.md (scope + authorization) BEFORE you touch evidence."
  ${EDITOR:-nvim} "$root/case.md"
}

# gocase — fzf-jump between existing cases (mirrors Kali's `eng` widget). NOT named
# `case`: that's a zsh reserved word, so a `case` function can be defined but never called.
gocase() {
  [[ -d "$CASES_DIR" ]] || { echo "no $CASES_DIR yet — run mkcase" >&2; return 1; }
  local sel
  sel=$(find "$CASES_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r \
        | fzf --prompt="Case ❯ " \
              --preview="cat {}/case.md 2>/dev/null || ls -la {}")
  [[ -z "$sel" ]] && return 0
  cd "$sel" || return 1
  export CASE="$sel"
}

# note — timestamped line into the active case's running notes (audit trail)
note() {
  local dir="${CASE:-$PWD}/notes"; mkdir -p "$dir"
  printf '%s  %s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$*" >> "$dir/notes.md"
}

unfunction _have 2>/dev/null
