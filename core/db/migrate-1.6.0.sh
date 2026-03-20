#!/bin/bash
# migrate-1.6.0.sh — Cortex middleware: add cortex_sync_state table
#
# Creates the cortex_sync_state table for tracking sync progress per backend.
# Part of M10: Middleware + Offline Resilience.
#
# Usage: bash core/db/migrate-1.6.0.sh [db_path]
#   db_path defaults to .claude/memory.db
#
# IDEMPOTENT: Safe to run multiple times. Uses CREATE TABLE IF NOT EXISTS.

set -e

DB="${1:-.claude/memory.db}"

if [ ! -f "$DB" ]; then
    echo "  migrate-1.6.0: DB not found at $DB — skipping migration"
    exit 0
fi

if ! command -v sqlite3 &>/dev/null; then
    echo "  migrate-1.6.0: sqlite3 not found — skipping migration"
    exit 0
fi

# --- Create cortex_sync_state table ---
sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS cortex_sync_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    backend TEXT NOT NULL,
    last_sync_at TEXT,
    last_export_at TEXT,
    pending_count INTEGER DEFAULT 0,
    updated_at TEXT DEFAULT (datetime('now'))
);"

echo "  migrate-1.6.0: Migration complete for $DB"
