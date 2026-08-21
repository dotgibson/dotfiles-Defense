#!/usr/bin/env bash
# detections/siem/check-splunk-precedence.sh — no Splunk deploy form may depend on
# operator precedence for its filter to bind.
# ──────────────────────────────────────────────────────────────────────────────
# WHY. pySigma's Splunk backend does not parenthesise a top-level OR against a top-level
# NOT. A rule whose condition is `(a or b) and not filter` compiles to
#
#     source="WinEventLog:Security" (a) OR (b) NOT (filter)
#
# which is correct ONLY because the search command's documented evaluation order is
# parentheses, then NOT, then OR, then AND — OR binding tighter than the implicit ANDs is
# what makes the leading source= term and the NOT group apply to BOTH branches. Read with
# AND binding first, the same text says `(source AND a) OR (b AND NOT filter)`: branch (a)
# escapes the filter entirely and matches off any source. eval and where evaluate AND
# before OR, so moving such a search into one — as Splunk ES correlation searches
# sometimes do — silently inverts it.
#
# Nothing else here would notice. zircolite evaluates the SIGMA condition, where the
# parentheses are explicit; the drift gate compares the generated file byte-for-byte, not
# semantically. So the rule lints, compiles, fires on its true positive and stays silent
# on its true negative while the deployed form's correctness rests on a precedence rule
# nobody wrote down. Same shape as fixture-provenance: CI proves CONSISTENT, not CORRECT.
#
# What this gate does is refuse to let a new one arrive unnoticed. It does not — and
# cannot — decide whether a given search is right; both instances present when it was
# written are right. It requires that each one be looked at once and signed off, so the
# third is a review conversation instead of a silent behaviour change. See #166.
#
# Kusto and Lucene emit `((a) OR (b)) AND (NOT (filter))` explicitly and are not checked.
#
# Usage: detections/siem/check-splunk-precedence.sh [repo-root]
# Exit:  0 = every same-depth OR/NOT is allowlisted;  1 = otherwise;  2 = bad invocation
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

if [[ $# -gt 1 ]]; then
  echo "check-splunk-precedence: unexpected argument '$2'" >&2
  echo "usage: check-splunk-precedence.sh [repo-root]" >&2
  exit 2
fi

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="${1:-$(cd -- "$HERE/../.." && pwd)}"
cd "$REPO" || exit 1

ALLOWLIST="detections/siem/splunk-precedence-allowlist.tsv"
[ -r "$ALLOWLIST" ] || {
  echo "::error::missing: $ALLOWLIST"
  exit 1
}

TARGETS=(
  detections/siem/splunk/savedsearches.generated.conf
  detections/siem/splunk/savedsearches.conf
)

python3 - "$ALLOWLIST" "${TARGETS[@]}" <<'PY'
import sys

allow_path, targets = sys.argv[1], sys.argv[2:]

# allowlist rows: <file><TAB><stanza><TAB><reason>. Keyed on the stanza title because the
# generated conf carries no rule path — a retitled rule therefore falls OUT of the
# allowlist and fails loudly, which is the right direction to be wrong in.
allowed, bad_rows = {}, []
with open(allow_path, encoding="utf-8") as fh:
    for n, line in enumerate(fh, 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3 or not parts[2].strip() or parts[2].strip() == "-":
            bad_rows.append((n, line.rstrip("\n")))
            continue
        allowed[(parts[0], parts[1])] = parts[2]

def segments(expr):
    """Split a search body on top-level pipes, respecting quotes and parens."""
    out, buf, depth, quoted = [], [], 0, False
    for ch in expr:
        if ch == '"':
            quoted = not quoted
        if not quoted:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            elif ch == "|" and depth == 0:
                out.append("".join(buf))
                buf = []
                continue
        buf.append(ch)
    out.append("".join(buf))
    return out

def offending_scopes(expr):
    """Depths at which both an OR and a NOT appear in the SAME paren scope."""
    stack, hits, quoted, i = [{"or": False, "not": False}], [], False, 0
    while i < len(expr):
        ch = expr[i]
        if ch == '"':
            quoted = not quoted
            i += 1
            continue
        if quoted:
            i += 1
            continue
        if ch == "(":
            stack.append({"or": False, "not": False})
        elif ch == ")":
            frame = stack.pop() if len(stack) > 1 else None
            if frame and frame["or"] and frame["not"]:
                hits.append(len(stack))
        else:
            for word in ("OR", "NOT"):
                if expr.startswith(word, i) and (i == 0 or not expr[i - 1].isalnum()):
                    end = i + len(word)
                    if end >= len(expr) or not expr[end].isalnum():
                        stack[-1][word.lower()] = True
                        i = end
                        break
            else:
                i += 1
                continue
            continue
        i += 1
    if stack and stack[0]["or"] and stack[0]["not"]:
        hits.append(0)
    return sorted(set(hits))

findings, seen = [], set()
for path in targets:
    try:
        raw = open(path, encoding="utf-8").read()
    except OSError:
        continue  # an absent hand-authored form is not a failure
    stanza = "(no stanza)"
    # rebuild continued lines: a trailing backslash joins to the next physical line
    logical, acc = [], ""
    for line in raw.split("\n"):
        acc += line
        if acc.endswith("\\"):
            acc = acc[:-1]
            continue
        logical.append(acc)
        acc = ""
    if acc:
        logical.append(acc)

    for line in logical:
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            stanza = s[1:-1]
            continue
        if not s.startswith("search ="):
            continue
        body = s.split("=", 1)[1].strip()
        for idx, seg in enumerate(segments(body)):
            seg = seg.strip()
            if not seg:
                continue
            cmd = "search" if idx == 0 else seg.split(None, 1)[0].lower()
            if cmd not in ("search", "where", "eval"):
                continue
            if not offending_scopes(seg):
                continue
            key = (path, stanza)
            if key in seen:
                continue
            seen.add(key)
            findings.append((path, stanza, cmd, seg))

rc = 0
if bad_rows:
    print("::error::%d allowlist row(s) are malformed (need <file>\\t<stanza>\\t<reason>, "
          "reason non-empty):" % len(bad_rows))
    for n, row in bad_rows:
        print("  %s:%d: %s" % (allow_path, n, row))
    rc = 1

unlisted = [f for f in findings if (f[0], f[1]) not in allowed]
if unlisted:
    print("::error::%d Splunk search(es) mix OR and NOT in the same paren scope, so the "
          "filter binds only by operator precedence:" % len(unlisted))
    for path, stanza, cmd, seg in unlisted:
        print("  %s" % path)
        print("    [%s]  (%s command)" % (stanza, cmd))
        print("    %s" % (seg if len(seg) <= 160 else seg[:157] + "..."))
        if cmd in ("where", "eval"):
            print("    NOTE: %s evaluates AND before OR — this reading is INVERTED "
                  "relative to a search command." % cmd)
    print("  This is not automatically a bug: under search-command precedence "
          "(parens, NOT, OR, AND) it is correct.")
    print("  Confirm the filter really binds to every branch, then record it:")
    print("    add '<file>\\t<stanza>\\t<why it is correct>' to %s" % allow_path)
    print("  See #166.")
    rc = 1

stale = [k for k in allowed if k not in {(f[0], f[1]) for f in findings}]
if rc == 0:
    print("splunk precedence: %d search(es) mix OR and NOT at one depth, all allowlisted"
          % len(findings))
    for path, stanza, _c, _s in findings:
        print("  %s [%s]" % (path, stanza))
    if stale:
        print("note: %d allowlist row(s) no longer match any search — safe to remove:"
              % len(stale))
        for path, stanza in stale:
            print("  %s [%s]" % (path, stanza))
sys.exit(rc)
PY
