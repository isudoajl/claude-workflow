#!/bin/bash
# migrate-1.3.0.sh — Cortex schema migration for existing (pre-Cortex) databases
#
# Adds contributor, shared_uuid, is_private columns to shareable tables.
# Creates shared_imports table and v_shared_briefing view.
#
# Usage: bash core/db/migrate-1.3.0.sh [db_path]
#   db_path defaults to .claude/memory.db
#
# IDEMPOTENT: Safe to run multiple times. Checks column existence before ALTER TABLE.

set -e

DB="${1:-.claude/memory.db}"

if [ ! -f "$DB" ]; then
    echo "  migrate-1.3.0: DB not found at $DB — skipping migration"
    exit 0
fi

if ! command -v sqlite3 &>/dev/null; then
    echo "  migrate-1.3.0: sqlite3 not found — skipping migration"
    exit 0
fi

# Helper: add column if it does not exist
# Usage: add_column_if_missing TABLE COLUMN TYPE [DEFAULT]
add_column_if_missing() {
    local table="$1"
    local column="$2"
    local col_type="$3"
    local default_clause="${4:-}"

    local exists
    exists=$(sqlite3 "$DB" "SELECT COUNT(*) FROM pragma_table_info('$table') WHERE name='$column';")

    if [ "$exists" = "0" ]; then
        local sql="ALTER TABLE $table ADD COLUMN $column $col_type"
        if [ -n "$default_clause" ]; then
            sql="$sql DEFAULT $default_clause"
        fi
        sqlite3 "$DB" "$sql;"
    fi
}

# --- Add contributor column to all shareable tables ---
add_column_if_missing "behavioral_learnings" "contributor" "TEXT"
add_column_if_missing "incidents"            "contributor" "TEXT"
add_column_if_missing "lessons"              "contributor" "TEXT"
add_column_if_missing "patterns"             "contributor" "TEXT"
add_column_if_missing "decisions"            "contributor" "TEXT"
add_column_if_missing "hotspots"             "contributor" "TEXT"

# --- Add shared_uuid column to shareable tables (NOT hotspots) ---
add_column_if_missing "behavioral_learnings" "shared_uuid" "TEXT"
add_column_if_missing "incidents"            "shared_uuid" "TEXT"
add_column_if_missing "lessons"              "shared_uuid" "TEXT"
add_column_if_missing "patterns"             "shared_uuid" "TEXT"
add_column_if_missing "decisions"            "shared_uuid" "TEXT"

# --- Add is_private column to shareable tables (NOT hotspots) ---
add_column_if_missing "behavioral_learnings" "is_private" "INTEGER" "0"
add_column_if_missing "incidents"            "is_private" "INTEGER" "0"
add_column_if_missing "lessons"              "is_private" "INTEGER" "0"
add_column_if_missing "patterns"             "is_private" "INTEGER" "0"
add_column_if_missing "decisions"            "is_private" "INTEGER" "0"

# --- Create shared_imports table ---
sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS shared_imports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    shared_uuid TEXT NOT NULL,
    category TEXT NOT NULL,
    source_file TEXT,
    imported_at TEXT DEFAULT (datetime('now'))
);"

# --- Create unique index on shared_imports(shared_uuid) ---
sqlite3 "$DB" "CREATE UNIQUE INDEX IF NOT EXISTS idx_shared_imports_uuid ON shared_imports(shared_uuid);"

# --- Create v_shared_briefing view ---
# Drop and recreate to ensure latest definition (view might reference columns that changed)
sqlite3 "$DB" "DROP VIEW IF EXISTS v_shared_briefing;"
sqlite3 "$DB" "CREATE VIEW IF NOT EXISTS v_shared_briefing AS
SELECT
    id, rule, confidence, occurrences, context, source_project, contributor,
    created_at, last_reinforced
FROM behavioral_learnings
WHERE confidence >= 0.8
  AND status = 'active'
  AND COALESCE(is_private, 0) = 0
ORDER BY confidence DESC, occurrences DESC;"

echo "  migrate-1.3.0: Migration complete for $DB"
