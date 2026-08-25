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
# For _audit_ls — this gate inventories files whose CONTENT it then checks, so it must
# see untracked ones (see the rule in common.sh). Sourced for that alone; this script
# keeps its own `note`/output style. The lib is idempotent and defines no name this
# script also defines.
#
# Via the ALREADY-ABSOLUTE $HERE, not ${BASH_SOURCE[0]%/*}: we have just cd'd, and
# BASH_SOURCE stays relative to the caller's original directory. Invoking this script
# by a relative path from elsewhere — `bash ../../repo/scripts/check-modern.sh` — then
# resolves the lib against the wrong base and, under `set -e`, exits before the gate
# runs at all. Verified: that invocation reported "lib/common.sh: No such file or
# directory" until this line used $HERE.
# shellcheck source=scripts/lib/common.sh
source "$HERE/scripts/lib/common.sh"
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
while IFS= read -r _f; do [ -n "$_f" ] && FILES+=("$_f"); done < <(_audit_ls \
  '.github/workflows/*.yml' '.github/workflows/*.yaml' \
  '.github/actions/*/action.yml' '.github/actions/*/action.yaml')
[ "${#FILES[@]}" -gt 0 ] || { echo "check-modern: no workflow/action files to check"; exit 0; }

# Workflows alone — rule 5 gates a key that only exists at workflow scope, so it must
# not see the composite action.yml files above.
WORKFLOWS=()
while IFS= read -r _f; do [ -n "$_f" ] && WORKFLOWS+=("$_f"); done < <(_audit_ls \
  '.github/workflows/*.yml' '.github/workflows/*.yaml')

violations=0
note() { printf '  ✗ %s\n' "$*" >&2; violations=$((violations + 1)); }

# ── 1) banned deprecated workflow-command patterns ───────────────────────────
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  while IFS= read -r hit; do note "banned pattern ($pat): $hit"; done \
    < <(grep -HnF -- "$pat" "${FILES[@]}" 2>/dev/null || true)
done < <(_yaml_list banned_patterns)

# ── 2) banned EOL runner labels (in runs-on: or a matrix os: list) ───────────
# The `(-(arm|large|xlarge))?` group is load-bearing. The label class that terminates the
# match has no hyphen in it, so without the group a ban on `ubuntu-22.04` did NOT match
# `runs-on: ubuntu-22.04-arm` — the `-` fails every alternative. GitHub names those exact
# variants in the same deprecation notices as the base labels (runner-images#14254 lists
# `ubuntu-22.04` AND `ubuntu-22.04-arm`; #13518 lists `macos-14`, `macos-14-large`,
# `macos-14-xlarge`), so the list was right and the matcher was leaky.
# Matching the suffix here rather than adding six more entries keeps `banned_runners`
# reading as ONE label per image, and covers every present and future variant of every
# label already on it — including ones added later.
while IFS= read -r rn; do
  [ -n "$rn" ] || continue
  while IFS= read -r hit; do note "EOL runner ($rn): $hit"; done \
    < <(grep -HnE "(runs-on|os):.*(^|[[:space:],\"'[])${rn}(-(arm|large|xlarge))?([[:space:],\"'*]|\]|\$)" "${FILES[@]}" 2>/dev/null || true)
done < <(_yaml_list banned_runners)

# ── 3) external action `uses:` must pin a 40-hex SHA (fleet's own owner exempt) ─
if _yaml_bool require_action_sha_pin; then
  exempt="$(_yaml_val sha_pin_exempt_owner)"
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    ref="${m##*@}"
    spec="${m#*uses:}"; spec="${spec#"${spec%%[![:space:]]*}"}"  # text after `uses:`, ltrimmed
    owner="${spec%%/*}"
    # THE FIRST-PARTY EXEMPTION IS NARROW, and it has to be. This was a bare `continue` on an
    # owner-string match, so `uses: dotgibson/anything@main` passed the gate outright — and
    # nothing else in the tree asserted the `@vN` policy that JUSTIFIES the exemption, so the
    # policy was documented in RELEASE-STRATEGY.md and enforced nowhere.
    #
    # What the policy actually says is narrower than "this owner is trusted": it is the moving
    # MAJOR tag, on the fleet's own REUSABLE WORKFLOWS. So require that exact shape —
    # dotgibson/<repo>/.github/workflows/<name>.yml@v<N> — and let anything else from the same
    # owner fall through to the 40-hex requirement, which is the right default for a ref whose
    # contract is not governed by the release process.
    why="unpinned action (need a 40-hex SHA)"
    if [ -n "$exempt" ] && [ "$owner" = "$exempt" ]; then
      if grep -qE "^${exempt}/[A-Za-z0-9_.-]+/\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml@v[0-9]+$" <<<"$spec"; then
        continue                                                     # @vN reusable workflow: the policy's own shape
      fi
      # Not the policy's shape — so it FALLS THROUGH to the same 40-hex requirement everything
      # else faces, rather than being rejected outright. A first-party caller that chose to
      # SHA-pin is stricter than @vN, not weaker, and must not be told off for it.
      why="first-party ref outside the @vN reusable-workflow policy (use @vN, or pin a 40-hex SHA)"
    fi
    grep -qE '^[0-9a-f]{40}$' <<<"$ref" || note "$why: $m"
  done < <(grep -HnoE "uses:[[:space:]]*[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[^[:space:]\"']+" "${FILES[@]}" 2>/dev/null || true)
fi

# ── 4) container images must pin an @sha256: digest ──────────────────────────
# A pinned reference ends in @sha256:<hex>; anything else — a bare `alpine` (implicit
# `latest`), an `alpine:3.21` tag — is mutable and moves under you. Images reach CI four
# ways, handled in two groups:
#   (a) single-token surfaces — `image: <ref>`, the `container: <ref>` SHORTHAND (the
#       block form's `image:` child is caught by the same `image:` rule), and a
#       `uses: docker://<ref>` container action. Extract the one reference token and check
#       it directly, so a bare `alpine`/`node:20` is caught (a name:tag-only regex misses
#       it) and a digest-only `alpine@sha256:…` is accepted (that same regex would mis-read
#       it as unpinned). The shorthand and docker:// forms also slip sha-pin rule (3) — not
#       owner/repo form — so rule 4 is the only thing that can catch them.
#   (b) `docker run|build|pull … <image>` commands — the image sits among flags/mounts/args
#       (`-v "$PWD:/x"`, `-w /x`), so keep the tolerant name:tag[@sha256] scan: a mount path
#       has no lowercase name:tag shape and won't be mistaken for an image.
# No live unpinned uses in the fleet today; this keeps the pinning contract airtight before
# an OS/role repo (which inherit the *-call.yml@v4 workflows) reaches for one.
if _yaml_bool require_container_digest_pin; then
  # (a) clean single-token surfaces
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    content="${line#*:*:}"                          # strip grep's file:linenum: prefix
    case "$content" in
    *docker://*) ref="${content##*docker://}" ;;    # uses: docker://<ref>
    *) ref="${content#*:}" ;;                        # image:/container: → value after the key
    esac
    ref="${ref#"${ref%%[![:space:]]*}"}"            # ltrim
    ref="${ref%%[[:space:]]*}"                       # first whitespace-delimited token only
    ref="${ref#[\"\']}"; ref="${ref%[\"\']}"         # strip one wrapping quote
    [ -n "$ref" ] || continue                        # value-less key (e.g. a workflow input) → skip
    case "$ref" in *@sha256:*) continue ;; esac      # digest-pinned (name:tag@sha256 or name@sha256)
    note "container image not digest-pinned ($ref): $line"
  done < <(grep -HnE '(^[[:space:]]*image:[[:space:]]*[^[:space:]#]|^[[:space:]]*container:[[:space:]]*[^[:space:]#]|uses:[[:space:]]*docker://)' "${FILES[@]}" 2>/dev/null || true)
  # (b) docker run|build|pull commands — tolerant scan for a name:tag[@sha256] token
  img_re='([a-z0-9]+([._-][a-z0-9]+)*/)*[a-z0-9]+([._-][a-z0-9]+)*:[a-z0-9][a-z0-9._-]*(@sha256:[0-9a-f]+)?'
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    content="${line#*:*:}"
    while IFS= read -r img; do
      [ -n "$img" ] || continue
      case "$img" in *@sha256:*) continue ;; esac    # already digest-pinned
      note "container image not digest-pinned ($img): $line"
    done < <(printf '%s\n' "$content" | grep -oE "$img_re" 2>/dev/null || true)
  done < <(grep -HnE 'docker[[:space:]]+(run|build|pull)' "${FILES[@]}" 2>/dev/null || true)
fi

# ── 5) every workflow declares a top-level permissions: block ────────────────
# Anchored at column 0 so a job-level `  permissions:` doesn't satisfy the rule —
# a job grant narrows the workflow default, it doesn't establish one.
if _yaml_bool require_workflow_permissions && [ "${#WORKFLOWS[@]}" -gt 0 ]; then
  for wf in "${WORKFLOWS[@]}"; do
    grep -qE '^permissions:[[:space:]]*$|^permissions:[[:space:]]+' "$wf" \
      || note "no top-level permissions: block (least-privilege): $wf"
  done
fi

# ── 6) every actions/checkout states persist-credentials: explicitly ─────────
# Needs the step's `with:` block associated with its `uses:`, which a line-at-a-time
# grep can't do — so walk each checkout back to the `- ` that opens its step, forward to
# the next sibling `- ` (or any dedent past it), and look for the key inside that window.
# Both orderings work: the key is found whether `with:` precedes or follows `uses:`.
if _yaml_bool require_explicit_persist_credentials && [ "${#WORKFLOWS[@]}" -gt 0 ]; then
  for wf in "${WORKFLOWS[@]}"; do
    while IFS= read -r hit; do
      [ -n "$hit" ] && note "checkout without an explicit persist-credentials: $hit"
    done < <(awk '
      { l[NR] = $0 }
      END {
        for (i = 1; i <= NR; i++) {
          if (l[i] !~ /uses:[[:space:]]*actions\/checkout@/) continue
          s = i
          while (s > 1 && l[s] !~ /^[[:space:]]*-[[:space:]]/) s--
          match(l[s], /^[[:space:]]*/); ind = RLENGTH
          e = s + 1
          while (e <= NR) {
            if (l[e] ~ /^[[:space:]]*$/) { e++; continue }
            match(l[e], /^[[:space:]]*/); ii = RLENGTH
            if (ii < ind) break
            if (ii == ind && l[e] ~ /^[[:space:]]*-[[:space:]]/) break
            e++
          }
          ok = 0
          for (j = s; j < e; j++)
            if (l[j] ~ /^[[:space:]]*persist-credentials:[[:space:]]*(true|false)([[:space:]]|$)/) ok = 1
          if (!ok) printf "%s:%d\n", FILENAME, i
        }
      }
    ' "$wf" 2>/dev/null || true)
  done
fi

# ── 7) no attacker-controlled expression spliced into a `run:` body ──────────
# A `${{ }}` expression is substituted by the RUNNER, textually, before the shell ever
# sees the script — so an attacker-controlled value (a PR title, a branch name) is not
# data, it is source code. The fleet already routes those through `env:` and reads `$VAR`,
# and says so at the call sites (auto-tag-call.yml, notify-web-call.yml) — but a comment
# is not a gate, and `actionlint`, which the audit already runs, has no equivalent rule.
#
# Scoped to FILES, not WORKFLOWS: a composite action's `run:` is the same hazard, and
# rule 3 already treats composite refs as in-scope.
#
# The context list deliberately excludes `inputs.*`. setup-core-tools/action.yml
# interpolates `${{ inputs.bindir }}` inline in ~8 run: steps; that is a FIRST-PARTY
# composite input, and banning it is a fix-first migration for no security gain.
#
# Structurally the same block-scalar walk as rule 6: find the `run:` key, take its
# column, and treat every more-indented line as body until the first non-blank dedent.
# Checking happens INSIDE each `${{ … }}` span rather than against the raw line, so a
# context name appearing in prose or in a comment beside the step is not a false fire.
if [ -n "$(_yaml_list banned_run_interpolation_contexts)" ]; then
  _ctx_list="$(_yaml_list banned_run_interpolation_contexts | tr '\n' ' ')"
  for f in "${FILES[@]}"; do
    while IFS= read -r hit; do
      [ -n "$hit" ] && note "untrusted expression interpolated into a run: body (route it through env: and read \$VAR): $hit"
    done < <(awk -v ctxs="$_ctx_list" '
      function flag(line, ln,   rest, p, q, expr, k) {
        rest = line
        while ((p = index(rest, "${{")) > 0) {
          rest = substr(rest, p + 3)
          q = index(rest, "}}")
          if (q == 0) { expr = rest; rest = "" }
          else        { expr = substr(rest, 1, q - 1); rest = substr(rest, q + 2) }
          for (k = 1; k <= nctx; k++)
            if (index(expr, ctx[k]) > 0) {
              gsub(/^[[:space:]]+|[[:space:]]+$/, "", expr)
              printf "%s:%d: ${{ %s }}\n", FILENAME, ln, expr
              return
            }
        }
      }
      BEGIN { nctx = split(ctxs, ctx, " ") }
      { l[NR] = $0 }
      END {
        for (i = 1; i <= NR; i++) {
          if (l[i] !~ /^[[:space:]]*(-[[:space:]]+)?run:/) continue
          # block scalar (`run: |`, `run: >-`, `run: |2`) vs a one-line `run: cmd`
          if (l[i] !~ /^[[:space:]]*(-[[:space:]]+)?run:[[:space:]]*[|>][0-9]*[-+]?[[:space:]]*$/) {
            flag(l[i], i)
            continue
          }
          ind = index(l[i], "run:") - 1
          for (e = i + 1; e <= NR; e++) {
            if (l[e] ~ /^[[:space:]]*$/) continue          # blanks belong to the block
            match(l[e], /^[[:space:]]*/)
            if (RLENGTH <= ind) break                      # first real dedent ends it
            flag(l[e], e)
          }
        }
      }
    ' "$f" 2>/dev/null || true)
  done
  unset _ctx_list
fi

# ── 8) every runner job declares timeout-minutes ─────────────────────────────
# Left unset, GitHub's default is 360 minutes — six hours of a held runner and a live
# GITHUB_TOKEN for a job that hung on a prompt, a network stall, or a step that was
# tampered with. Core owns all six *-call.yml@v4 reusable workflows the fleet consumes,
# so the jobs the OS repos actually execute are defined HERE; a floor rule locks in a
# property currently held only by convention.
#
# KEYED ON `runs-on:`, NOT on "every job". A job that calls a reusable workflow (`uses:`
# at job level) cannot legally carry timeout-minutes, so requiring it there would be a
# guaranteed false fire. Scoped to WORKFLOWS, not FILES: a composite action has no jobs.
#
# Structurally the same job-block walk as rule 6's checkout walk, awk-only and bash-3.2
# safe. `jobs:` opens the section; any column-0 key closes it; a 2-space key opens a job.
if _yaml_bool require_job_timeout && [ "${#WORKFLOWS[@]}" -gt 0 ]; then
  for wf in "${WORKFLOWS[@]}"; do
    while IFS= read -r hit; do
      [ -n "$hit" ] && note "job without timeout-minutes (GitHub's default is 360m): $hit"
    done < <(awk '
      /^jobs:[[:space:]]*$/ { injobs = 1; next }
      /^[A-Za-z_]/          { injobs = 0 }
      injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
        if (job != "" && runner && !t) printf "%s:%d: %s\n", FILENAME, ln, job
        job = $1; sub(/:$/, "", job); ln = NR; runner = 0; t = 0; next
      }
      injobs && /^    runs-on:/         { runner = 1 }
      injobs && /^    timeout-minutes:/ { t = 1 }
      END { if (job != "" && runner && !t) printf "%s:%d: %s\n", FILENAME, ln, job }
    ' "$wf" 2>/dev/null || true)
  done
fi

if [ "$violations" -eq 0 ]; then
  echo "check-modern: CI meets the modern baseline (${#FILES[@]} workflow/action files)"
  exit 0
fi
printf 'check-modern: %d violation(s) below the floor (scripts/modern-baseline.yml)\n' "$violations" >&2
exit 1
