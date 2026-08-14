# shellcheck shell=bash
# scripts/lib/atuin-db.sh — read atuin's history DB the way both atuin gates read it.
# ──────────────────────────────────────────────────────────────────────────────
# ONE definition of the row-count SQL and the WAL checkpoint, shared by
# scripts/bench-atuin-daemon.sh (which refuses to REPORT an arm whose writes did not land)
# and scripts/verify-atuin-guard.sh (which refuses to reach a VERDICT whose control arm
# did not write). Both rest on the same claim about atuin's schema — that a command is one
# row in `history`, and that `history end` UPDATES that row rather than inserting another
# — so a forked copy would let one gate keep believing a model the other had already found
# stale. That is exactly the drift scripts/lib/common.sh exists to kill.
#
# A SOURCED library, so — like scripts/lib/common.sh, and like zsh/*.zsh — it carries NO
# shebang and stays mode 100644. scripts/audit-core.sh's exec-bit section asserts it: the
# `scripts/lib/*.sh` arm deliberately precedes the generic `*.sh` arm, which would
# otherwise demand 100755. bash 3.2-safe (macOS): no associative arrays, no mapfile.
#
# Usage, from any scripts/*.sh:
#   source "${BASH_SOURCE[0]%/*}/lib/atuin-db.sh"
# ──────────────────────────────────────────────────────────────────────────────

# Idempotent: a script and a gate it invokes may both source this, and redefining the
# functions under a caller running with `set -u` is a needless way to fail.
[[ -n "${_CORE_ATUIN_DB_SH:-}" ]] && return 0
_CORE_ATUIN_DB_SH=1

# Row count as SQLite sees it RIGHT NOW, optionally filtered. Kept in a variable, not
# inlined, so scripts/test-core.sh can EXTRACT and execute this exact SQL against a
# synthetic table — the same "run it, don't pattern-match it" idiom Section J uses on the
# example unit's ExecStart. The extraction sed keys on the `ROWCOUNT_PY='` opener at column
# 0 and on the lone closing quote on its own line; don't collapse either.
#
# Deliberately NO wal_checkpoint here, unlike atuin_db_checkpoint below: a reader on a WAL
# database already sees committed WAL frames, and asking for a checkpoint while a daemon
# still holds the file open would pick a lock fight with the very process under
# measurement. A plain read-write connect, not `mode=ro`: read-only access to a WAL DB
# needs a usable -shm, and a crashed writer can leave a -wal without one, which would fail
# the open and wrongly condemn a healthy run.
#
# ANY failure prints -1, and that is the whole fail-closed contract. -1 can only ever BREAK
# an equality check, never satisfy one — so a DB that could not be read is never mistaken
# for a DB that legitimately did not grow. Those two are indistinguishable by row count
# alone, and conflating them is precisely how a detector reports "nothing changed" when
# what actually happened is "I stopped being able to tell".
ROWCOUNT_PY='import sqlite3, sys
try:
    con = sqlite3.connect(sys.argv[1], timeout=30)
    print(con.execute("select count(*) from history where " + sys.argv[2]).fetchone()[0])
    con.close()
except Exception:
    print(-1)
'

# atuin_db_rows <db-path> [sql-predicate] — row count, or -1 when it cannot be read.
atuin_db_rows() { python3 -c "$ROWCOUNT_PY" "$1" "${2:-1=1}" 2>/dev/null; }

# atuin_db_checkpoint <db-path> — fold a database's WAL back into its main file.
#
# Only ever safe where NO daemon holds the file open (at seed time, and between arms), so
# it cannot contend with the process under measurement. Needed because atuin opens SQLite
# in WAL mode: a freshly-imported history.db is only half the story, and the rest —
# INCLUDING the _sqlx_migrations rows — is in history.db-wal. Copy or read the main file
# alone and you get a DB that looks seeded but reads as UN-MIGRATED, after which every
# writer races to apply the migrations at once and loses on
# `UNIQUE constraint failed: _sqlx_migrations.version`. That is a defect in the harness,
# not a property of atuin, and it would otherwise be measured as if it were one.
#
# Silent on failure by design: a checkpoint is an optimisation for the snapshot, never a
# correctness gate. atuin_db_rows above is the gate, and it fails closed.
atuin_db_checkpoint() {
  python3 -c 'import sqlite3, sys
try:
    con = sqlite3.connect(sys.argv[1], timeout=30)
    con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    con.close()
except Exception:
    pass' "$1" 2>/dev/null
}
