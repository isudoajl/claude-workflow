#!/bin/bash
# Initialize or migrate the institutional memory database
# Usage: bash scripts/db-init.sh [target_dir]
# If no target_dir, uses current directory

set -e

TARGET_DIR="${1:-.}"
DB_PATH="$TARGET_DIR/.claude/memory.db"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_FILE="$SCRIPT_DIR/core/db/schema.sql"

# Check sqlite3
if ! command -v sqlite3 &> /dev/null; then
    echo "ERROR: sqlite3 not found. Install it first."
    echo "  macOS: brew install sqlite3"
    echo "  Ubuntu: sudo apt install sqlite3"
    exit 1
fi

# Ensure .claude/ exists
mkdir -p "$TARGET_DIR/.claude"

if [ -f "$DB_PATH" ]; then
    echo "   Institutional memory DB already exists at $DB_PATH"
    # Run schema with IF NOT EXISTS — safe to re-run for migrations
    sqlite3 "$DB_PATH" < "$SCHEMA_FILE"
    echo "   Schema migrated (new tables/views added if any)"
else
    echo "   Creating institutional memory DB at $DB_PATH"
    sqlite3 "$DB_PATH" < "$SCHEMA_FILE"
    echo "   Schema initialized"
fi

# Run migrations (idempotent, order matters — glob sorts alphabetically)
for MIGRATE_SCRIPT in "$SCRIPT_DIR/core/db/migrate-"*.sh; do
    if [ -f "$MIGRATE_SCRIPT" ]; then
        bash "$MIGRATE_SCRIPT" "$DB_PATH" || echo "  WARNING: $(basename "$MIGRATE_SCRIPT") had errors (non-blocking)"
    fi
done

# Copy query reference files for agents
mkdir -p "$TARGET_DIR/.claude/db-queries"
cp "$SCRIPT_DIR/core/db/queries/"*.sql "$TARGET_DIR/.claude/db-queries/"
echo "   Query references copied to .claude/db-queries/"

# Verify
TABLE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
VIEW_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='view';")
echo "   DB ready: $TABLE_COUNT tables, $VIEW_COUNT views"
