#!/usr/bin/env bash
# scripts/nvim-reachability.sh
# ──────────────────────────────────────────────────────────────────────────────
# THE nvim ORPHAN BACKSTOP — is every lua module under nvim/ actually loadable?
#
# core.manifest lists `nvim/` as a DIRECTORY, not per-file, because the vendored
# lazy.nvim tree legitimately churns wholesale as plugins and servers come and go, so
# per-file listing would be maintenance noise. The cost of that choice is that the
# audit's §1 manifest⇄filesystem drift check cannot see an orphan here: any new path
# under nvim/ is auto-"listed", so a lua module that nothing loads sits in the tree
# indefinitely, gets vendored into all eight OS repos, and no gate says a word.
#
# core.manifest said that gap was "covered by verify-core.sh instead". That script has
# never existed in this repo (dotgibson/dotfiles-core#454) — so the backstop the comment
# promised was nothing at all. This is it.
#
# HOW IT WORKS — a real graph traversal, not an "is this name mentioned anywhere" scan.
# The distinction matters: a mention-scan passes two dead modules that require EACH OTHER
# (a disconnected cycle), and passes a module named only in some other file's comment.
# Both are exactly the orphan this exists to catch. So:
#
#   1. Inventory every module under nvim/lua/gerrrt (dir/init.lua ⇒ `gerrrt.dir`).
#   2. Strip lua comments, then read each file's edges — any quoted `gerrrt.*` string,
#      which covers `require("gerrrt.x")` and lazy's `{ import = "gerrrt.plugins" }`.
#   3. Walk outward from the ROOTS and flag every module never visited.
#
# The roots, and why each is a root rather than an exemption:
#
#   nvim/init.lua   the entry point Neovim loads; everything real hangs off it.
#   gerrrt.health   Neovim discovers lua/**/health.lua by runtimepath for :checkhealth.
#                   Nothing requires it and nothing should — it is genuinely a second
#                   entry point, so it is a ROOT, not a special case.
#
# Two edges cannot be read literally from the source and are resolved during the walk:
#
#   directory import   `{ import = "gerrrt.plugins" }` names a DIRECTORY, not a module.
#                      A target with no file of its own but with `target.*` children
#                      expands to all of them — which is what lazy.nvim does.
#   dynamic require    servers/init.lua does `pcall(require, "gerrrt.servers." .. name)`
#                      over its `servers` list, so the literal string is a dead end.
#                      Visiting `gerrrt.servers` expands to the listed names — that
#                      registry is the only static evidence those modules are wanted.
#
# The registry is ALSO checked both ways, because a generic "unreachable" is a worse
# message than the truth: a module in no list entry is dead config, and a list entry with
# no module file is a runtime load error servers/init.lua reports at startup. Both a
# missing and an unparseable registry FAIL CLOSED — silently skipping the registry check
# would disable the whole servers/ arm, which is precisely how this class of gap starts.
#
# LOOKUPS FEED THEIR INPUT BY HERESTRING, NEVER BY PIPE. Do not "simplify" any of the
# `grep -q … <<<"$s"` or `awk … <<<"$s"` forms back to `printf '%s\n' "$s" | …`.
#
# This script runs under `set -o pipefail`, and every one of those readers exits EARLY —
# `grep -q` on its first match, `awk` on its `exit`. The writer then takes EPIPE and dies
# with 141, and pipefail makes the PIPELINE non-zero even though the reader succeeded. A
# module that IS visited therefore reads as unvisited and is reported as an orphan, and
# the "printf: write error: Broken pipe" on stderr is captured by §4b as a finding in its
# own right.
#
# It is timing-dependent — the writer must still be writing when the reader exits — so it
# passes on small trees and on most runs. Measured on a large input, the piped form gave
# 20/20 false negatives. This is exactly how it reached main once.
#
# Output contract: one finding per line on stdout, no colour, no decoration — the caller
# (audit-core.sh §4b) turns each line into a `fail`. Silence means clean.
# Exit: 0 = clean, 1 = findings, 2 = usage / cannot run.
#
# bash 3.2 safe (macos-latest runs the 2007 bash): no mapfile, no associative arrays.
#
# Usage:
#   ./scripts/nvim-reachability.sh            # check this repo
#   ./scripts/nvim-reachability.sh --root DIR # check a repo elsewhere (tests use this)
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# For _audit_ls — this backstop inventories module FILES and reads their contents, so it
# must see untracked ones (see the rule in common.sh); a brand-new lua module that nothing
# requires is an orphan whether or not git has met it yet. Sourced BEFORE the `cd "$ROOT"`
# below, while BASH_SOURCE still resolves against the invocation directory.
# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || {
        echo "--root needs a directory" >&2
        exit 2
      }
      ROOT="$2"
      shift 2
      ;;
    -h | --help)
      sed -n '2,55p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

cd "$ROOT" 2>/dev/null || {
  echo "not a directory: $ROOT" >&2
  exit 2
}
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "not a git work tree: $ROOT" >&2
  exit 2
}
[ -d nvim/lua/gerrrt ] || exit 0 # nothing to check (an OS repo, or nvim not vendored)

rc=0
srv_init=nvim/lua/gerrrt/servers/init.lua

# ── inventory: "<module>\t<file>", one per line ───────────────────────────────
# The mapping must be exactly how LUA resolves a module name, or the walk marks the wrong
# rows visited. Two traps, both previously live:
#
#   `.init` is stripped only for a real `*/init.lua` path. Doing it on the module STRING
#   let a file literally named `foo.init.lua` masquerade as module `foo` — a name lua
#   resolves through `foo.lua` or `foo/init.lua` and never through `foo.init.lua`.
#
#   A dot inside a filename is not a path separator to lua. `require("gerrrt.a.b")` looks
#   for `a/b.lua`, so `a.b.lua` is unaddressable dead weight; it is reported below rather
#   than silently folded into a name some other file legitimately owns.
#
# THE BLOCK BELOW IS WRITTEN FOR BASH 3.2 — macos-latest runs the 2007 bash, whose $(…)
# parser is a naive scanner rather than a real recursive parse. Three things broke it
# during review, each a separate red CI run:
#
#   1. NO `case` INSIDE THE SUBSTITUTION. This is the big one. The scanner counts
#      parentheses, and a case pattern terminator — `init.lua)` — looks exactly like the
#      closing paren of the $(…), so the substitution "ends" mid-statement and the rest of
#      the file becomes a syntax error. Plain if/elif below; a leading-paren form
#      (`(init.lua)`) also works but relies on the reader knowing why.
#   2. No nested $(…) inside it either. Pure parameter expansion instead —
#      ${var//\//.} is 3.2-clean and needs no subshell.
#   3. No prose comments inside it at all. The scanner reads comment text while matching,
#      so a lone backtick or quote there — which prose about shell quoting inevitably
#      contains — aborts the parse with "unexpected EOF". Hence this explanation living
#      out here rather than beside the code it describes.
#
# None of this is visible to `bash -n` on a modern bash, to shellcheck, or to the ubuntu,
# Alpine and Arch legs. The macos leg is the only thing that catches it.
mods="$(_audit_ls 'nvim/lua/gerrrt/*.lua' | while IFS= read -r f; do
  [ -n "$f" ] || continue
  rel="${f#nvim/lua/gerrrt/}"
  base="${rel%.lua}"
  if [ "$rel" = init.lua ]; then
    mod_path=""
  elif [ "${rel%/init.lua}" != "$rel" ]; then
    mod_path="${base%/init}"
  else
    mod_path="$base"
  fi
  if [ -n "$mod_path" ]; then mod="gerrrt.${mod_path//\//.}"; else mod="gerrrt"; fi
  printf '%s\t%s\n' "$mod" "$f"
done)"
[ -n "$mods" ] || exit 0

# A filename lua cannot address at all.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  b="${f##*/}"
  case "${b%.lua}" in
    *.*) echo "unaddressable module file — $f has a dot in its filename; lua resolves gerrrt.a.b through a/b.lua, never a.b.lua"
      rc=1 ;;
  esac
done <<EOF
$(_audit_ls 'nvim/lua/gerrrt/*.lua')
EOF

# Two files claiming one module name: lua loads exactly one of them (package.path order),
# so the other is dead config that the walk would mark visited along with its twin.
while IFS= read -r dup; do
  [ -n "$dup" ] || continue
  files="$(awk -F'\t' -v m="$dup" '$1 == m { printf "%s ", $2 }' <<<"$mods")"
  echo "duplicate module id \"$dup\" — claimed by: ${files% }"
  rc=1
done <<EOF
$(cut -f1 <<<"$mods" | sort | uniq -d)
EOF

_file_for() { awk -F'\t' -v m="$1" '$1 == m { print $2; exit }' <<<"$mods"; }
_children_of() { awk -F'\t' -v p="$1." 'index($1, p) == 1 { print $1 }' <<<"$mods"; }

# Strip lua comments — every form. A line-only `sed 's/--.*$//'` leaves the interior of a
# multiline block fully searchable, so a module named inside one would still forge an edge.
# Lua long comments are `--[[ … ]]` AND the level forms `--[=[ … ]=]`, `--[==[ … ]==]`, …
# with matching `=` counts, so the closing delimiter is derived from the opener rather than
# hardcoded. State (`blk`, `close_re`) carries across lines.
_strip_comments() {
  awk '
    { line = $0
      if (blk) {                                    # inside a long comment from a prior line
        if (match(line, close_re)) { line = substr(line, RSTART + RLENGTH); blk = 0 }
        else { print ""; next }
      }
      while (match(line, /--\[=*\[/)) {             # long comment opening on this line
        eqs = RLENGTH - 4                            # "--[" + "[" is 4 chars; the rest are "="
        close_re = "\\]"
        for (i = 0; i < eqs; i++) close_re = close_re "="
        close_re = close_re "\\]"
        head = substr(line, 1, RSTART - 1)
        rest = substr(line, RSTART + RLENGTH)
        if (match(rest, close_re)) { line = head substr(rest, RSTART + RLENGTH) }
        else { line = head; blk = 1; break }
      }
      if (!blk && (c = index(line, "--")) > 0) line = substr(line, 1, c - 1)
      print line
    }' "$1"
}

# Edges out of one file, as "<kind> <module>" — kind is `req` or `imp`.
#
# ONLY REAL LOAD EXPRESSIONS COUNT. Matching every quoted `gerrrt.*` string was still a
# mention scan, just a comment-free one: health.lua deliberately peeks
# `package.loaded["gerrrt.servers"]` precisely so it does NOT load the registry, and
# counting that as an edge would let the entire servers/ arm look reachable from the
# health root even if the real `require("gerrrt.servers")` were deleted. So the module
# name must be preceded by `require` (covering `require("x")`, `require "x"`, and the
# `pcall(require, "x")` form) or by lazy's `import =`.
#
# The KIND is carried because the two resolve differently at a missing target: `import`
# names a directory and expands to its children, while a `require` for which no module
# file exists is a dangling require lua would raise at runtime.
#
# A trailing dot (from `"gerrrt.servers." .. name`) is dropped — that edge comes from the
# registry instead.
#
# KNOWN LIMIT, deliberately not "fixed": the contents of string literals are still in
# scope, so `local help = 'require("gerrrt.x")'` would forge an edge. Ignoring string
# interiors — the obvious lexer-shaped fix — would be WORSE here, because a require inside
# a string is very often a real load in this codebase: `plugins/alpha-nvim.lua:44` uses
# `"<cmd>lua require('persistence').load()<cr>"`, and that require genuinely executes when
# the mapping fires. A lexer would classify it inert and report a live module as an orphan.
# Between a rare false negative (someone writes a real module path inside inert prose) and
# a false positive that reds CI on a correct tree, the false negative is the safer failure
# for a guard. Revisit if the inert-string case ever actually occurs.
_edges_of() {
  [ -f "$1" ] || return 0
  code="$(_strip_comments "$1")"
  {
    printf '%s\n' "$code" |
      grep -oE 'require[[:space:]]*[(,]?[[:space:]]*["'"'"']gerrrt[A-Za-z0-9_.-]*["'"'"']' |
      grep -oE 'gerrrt[A-Za-z0-9_.-]*' | sed -e 's/\.$//' -e 's/^/req /'
    printf '%s\n' "$code" |
      grep -oE 'import[[:space:]]*=[[:space:]]*["'"'"']gerrrt[A-Za-z0-9_.-]*["'"'"']' |
      grep -oE 'gerrrt[A-Za-z0-9_.-]*' | sed -e 's/\.$//' -e 's/^/imp /'
  } | sort -u
}

# ── the LSP registry (also the dynamic edge out of `gerrrt.servers`) ──────────
# Fail closed on BOTH failure modes. A missing servers/init.lua used to skip the whole
# registry arm silently, so deleting it disabled the check instead of failing.
srv_listed=""
if [ -f "$srv_init" ]; then
  srv_listed="$(awk '/^local servers = \{/,/^\}/' "$srv_init" | grep -oE '"[a-z_0-9]+"' | tr -d '"' | sort -u)"
  if [ -z "$srv_listed" ]; then
    echo "could not parse the \`local servers = {…}\` registry in $srv_init"
    rc=1
  fi
elif [ -n "$(_children_of gerrrt.servers)" ]; then
  echo "missing $srv_init, but servers/ modules exist — the registry check cannot run"
  rc=1
fi

# ── walk the graph from the roots ─────────────────────────────────────────────
# Queue entries are "<kind> <module>". Roots: whatever nvim/init.lua pulls in, plus
# gerrrt.health (runtimepath-discovered by :checkhealth — a genuine second entry point,
# not an exemption).
queue="$(_edges_of nvim/init.lua)
req gerrrt.health"
visited=""

while [ -n "$queue" ]; do
  entry="${queue%%
*}"
  if [ "$entry" = "$queue" ]; then queue=""; else queue="${queue#*
}"; fi
  [ -n "$entry" ] || continue
  kind="${entry%% *}"
  m="${entry#* }"
  grep -qxF "$m" <<<"$visited" && continue
  visited="$visited
$m"

  f="$(_file_for "$m")"
  if [ -z "$f" ]; then
    # No module file. What that MEANS depends on how we got here, which is why the edge
    # kind is carried: `import` names a directory (lazy expands it to its children), but
    # a `require` with no module behind it is a dangling require lua raises at runtime.
    # Treating every fileless target as a directory import made `require("gerrrt.utils")`
    # silently mark every gerrrt.utils.* child reachable.
    if [ "$kind" = imp ]; then
      kids="$(_children_of "$m")"
      if [ -n "$kids" ]; then
        queue="$queue
$(printf '%s\n' "$kids" | sed 's/^/req /')"
      else
        echo "lazy imports \"$m\" but no module matches it"
        rc=1
      fi
    else
      echo "dangling require — \"$m\" is required but no such module file exists"
      rc=1
    fi
    continue
  fi

  queue="$queue
$(_edges_of "$f")"

  # The dynamic arm: `gerrrt.servers` require()s each listed name at runtime.
  if [ "$m" = gerrrt.servers ] && [ -n "$srv_listed" ]; then
    queue="$queue
$(printf '%s\n' "$srv_listed" | sed 's/^/req gerrrt.servers./')"
  fi
done

# ── report ───────────────────────────────────────────────────────────────────
# servers/* are reported by the registry check below instead: "in no registry entry" is
# a truer diagnosis than "unreachable" for a module the walk could only reach via a list.
while IFS="$(printf '\t')" read -r m f; do
  [ -n "$m" ] || continue
  case "$m" in gerrrt.servers.*) continue ;; esac
  grep -qxF "$m" <<<"$visited" && continue
  echo "orphaned module — nothing reaches \"$m\" from nvim/init.lua ($f)"
  rc=1
done <<EOF
$mods
EOF

if [ -n "$srv_listed" ]; then
  # a module file in no registry entry is dead config …
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    name="${m#gerrrt.servers.}"
    if ! grep -qx "$name" <<<"$srv_listed"; then
      echo "orphaned LSP module — nvim/lua/gerrrt/servers/$name.lua is in no \`servers\` registry entry (dead config)"
      rc=1
    fi
  done <<EOF
$(_children_of gerrrt.servers)
EOF
  # … and a registry entry with no module file is a runtime load error.
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if [ ! -f "nvim/lua/gerrrt/servers/$name.lua" ]; then
      echo "\`servers\` lists \"$name\" but nvim/lua/gerrrt/servers/$name.lua does not exist"
      rc=1
    fi
  done <<EOF
$srv_listed
EOF
fi

exit $rc
