#!/bin/bash
# migrate-1.4.0.sh — Add severity column to incidents table
#
# Adds severity TEXT DEFAULT 'medium' to incidents.
# Creates idx_incidents_severity index.
# Recreates v_incident_search view to include severity.
#
# Usage: bash core/db/migrate-1.4.0.sh [db_path]
#   db_path defaults to .claude/memory.db
#
# IDEMPOTENT: Safe to run multiple times. Checks column existence before ALTER TABLE.

set -e

DB="${1:-.claude/memory.db}"

if [ ! -f "$DB" ]; then
    echo "  migrate-1.4.0: DB not found at $DB — skipping migration"
    exit 0
fi

if ! command -v sqlite3 &>/dev/null; then
    echo "  migrate-1.4.0: sqlite3 not found — skipping migration"
    exit 0
fi

# Check if severity column already exists
EXISTS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM pragma_table_info('incidents') WHERE name='severity';")

if [ "$EXISTS" = "0" ]; then
    sqlite3 "$DB" "ALTER TABLE incidents ADD COLUMN severity TEXT DEFAULT 'medium';"
fi

# Create index (idempotent)
sqlite3 "$DB" "CREATE INDEX IF NOT EXISTS idx_incidents_severity ON incidents(severity);"

# Recreate v_incident_search to include severity
sqlite3 "$DB" "DROP VIEW IF EXISTS v_incident_search;"
sqlite3 "$DB" "CREATE VIEW IF NOT EXISTS v_incident_search AS
SELECT
    i.incident_id, i.title, i.domain, i.severity, i.status,
    i.description, i.symptoms, i.root_cause, i.resolution,
    i.tags,
    (SELECT COUNT(*) FROM incident_entries e WHERE e.incident_id = i.incident_id) as entry_count,
    i.created_at, i.resolved_at
FROM incidents i
ORDER BY
    CASE i.status WHEN 'open' THEN 0 WHEN 'investigating' THEN 1 WHEN 'resolved' THEN 2 WHEN 'closed' THEN 3 END,
    i.id DESC;"

echo "  migrate-1.4.0: Migration complete for $DB"
