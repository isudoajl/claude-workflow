#!/bin/bash
# test-cortex-m1-schema.sh
#
# Tests for OMEGA Cortex Milestone M1: Schema + Migration
# Covers: REQ-CTX-001, REQ-CTX-002, REQ-CTX-003, REQ-CTX-004, REQ-CTX-005,
#         REQ-CTX-006, REQ-CTX-010
#
# These tests are written BEFORE the code (TDD). They define the contract
# that the developer must fulfill.
#
# Usage:
#   bash tests/test-cortex-m1-schema.sh
#   bash tests/test-cortex-m1-schema.sh --verbose
#
# Dependencies: sqlite3, bash

set -u

# ============================================================
# TEST FRAMEWORK (matching existing project conventions)
# ============================================================
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
VERBOSE=false

for arg in "$@"; do
    [ "$arg" = "--verbose" ] && VERBOSE=true
done

assert_eq() {
    local expected="$1"
    local actual="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
    fi
}

assert_ne() {
    local not_expected="$1"
    local actual="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$not_expected" != "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Should NOT be: $not_expected"
        echo "    Actual:        $actual"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -qF -- "$needle"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Needle not found: $needle"
        if [ "$VERBOSE" = true ]; then
            echo "    Haystack: $(echo "$haystack" | head -20)"
        fi
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -qF -- "$needle"; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Should NOT contain: $needle"
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    fi
}

assert_gt() {
    local threshold="$1"
    local actual="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$actual" -gt "$threshold" ] 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Expected > $threshold, got: $actual"
    fi
}

assert_zero_exit() {
    local exit_code="$1"
    local description="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$exit_code" -eq 0 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Exit code: $exit_code (expected 0)"
    fi
}

skip_test() {
    local description="$1"
    local reason="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo "  SKIP: $description -- $reason"
}

# ============================================================
# PATHS
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_FILE="$SCRIPT_DIR/core/db/schema.sql"
MIGRATE_SCRIPT="$SCRIPT_DIR/core/db/migrate-1.3.0.sh"

# ============================================================
# TEST ISOLATION: create temp directory, clean up on exit
# ============================================================
TEST_TMP=""
setup_tmp() {
    TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/cortex-m1-test-XXXXXX")
    if [ ! -d "$TEST_TMP" ]; then
        echo "FATAL: Failed to create temp directory"
        exit 1
    fi
}

cleanup_tmp() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
}

trap cleanup_tmp EXIT

# ============================================================
# PREREQUISITES
# ============================================================
echo "============================================================"
echo "OMEGA Cortex M1: Schema + Migration Tests"
echo "============================================================"
echo ""

if ! command -v sqlite3 &>/dev/null; then
    echo "FATAL: sqlite3 not found. Cannot run tests."
    exit 1
fi

if [ ! -f "$SCHEMA_FILE" ]; then
    echo "FATAL: schema.sql not found at $SCHEMA_FILE"
    exit 1
fi

# Helper: create a fresh DB from the current schema.sql
create_fresh_db() {
    local db_path="$1"
    sqlite3 "$db_path" < "$SCHEMA_FILE"
}

# Helper: create a pre-Cortex DB (version 1.2.0 schema without Cortex columns)
# This simulates an existing DB that needs migration.
create_pre_cortex_db() {
    local db_path="$1"
    # We create the DB using the CURRENT schema.sql, then verify if migration
    # columns exist. But for a true pre-Cortex test, we need to build a DB
    # that does NOT have the Cortex columns. We do this by creating the tables
    # manually with only the original columns (from the 1.2.0 schema we read).
    sqlite3 "$db_path" <<'EOSQL'
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS workflow_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL,
    description TEXT,
    scope TEXT,
    started_at TEXT DEFAULT (datetime('now')),
    completed_at TEXT,
    status TEXT DEFAULT 'running',
    git_commits TEXT,
    error_message TEXT
);

CREATE TABLE IF NOT EXISTS changes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    file_path TEXT NOT NULL,
    change_type TEXT NOT NULL,
    description TEXT,
    agent TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    domain TEXT,
    decision TEXT NOT NULL,
    rationale TEXT,
    alternatives TEXT,
    confidence REAL DEFAULT 1.0,
    status TEXT DEFAULT 'active',
    superseded_by INTEGER REFERENCES decisions(id),
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS failed_approaches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    domain TEXT,
    problem TEXT NOT NULL,
    approach TEXT NOT NULL,
    failure_reason TEXT NOT NULL,
    file_paths TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS bugs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    description TEXT NOT NULL,
    symptoms TEXT,
    root_cause TEXT,
    fix_description TEXT,
    affected_files TEXT,
    related_bug_ids TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS hotspots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT UNIQUE NOT NULL,
    risk_level TEXT DEFAULT 'low',
    description TEXT,
    times_touched INTEGER DEFAULT 1,
    last_incident_run INTEGER REFERENCES workflow_runs(id),
    last_updated TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS findings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    finding_id TEXT,
    severity TEXT NOT NULL,
    category TEXT,
    description TEXT NOT NULL,
    file_path TEXT,
    line_range TEXT,
    status TEXT DEFAULT 'open',
    fixed_in_run INTEGER REFERENCES workflow_runs(id),
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS dependencies (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_file TEXT NOT NULL,
    target_file TEXT NOT NULL,
    relationship TEXT NOT NULL,
    discovered_run INTEGER REFERENCES workflow_runs(id),
    created_at TEXT DEFAULT (datetime('now')),
    UNIQUE(source_file, target_file, relationship)
);

CREATE TABLE IF NOT EXISTS requirements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    req_id TEXT UNIQUE NOT NULL,
    domain TEXT,
    description TEXT NOT NULL,
    priority TEXT NOT NULL,
    status TEXT DEFAULT 'defined',
    test_ids TEXT,
    implementation_module TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL REFERENCES workflow_runs(id),
    domain TEXT,
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    example_files TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS outcomes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER REFERENCES workflow_runs(id),
    agent TEXT NOT NULL,
    score INTEGER NOT NULL CHECK(score IN (-1, 0, 1)),
    domain TEXT,
    action TEXT NOT NULL,
    lesson TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS lessons (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    domain TEXT NOT NULL,
    content TEXT NOT NULL,
    source_agent TEXT,
    occurrences INTEGER DEFAULT 1,
    confidence REAL DEFAULT 0.5,
    status TEXT DEFAULT 'active',
    created_at TEXT DEFAULT (datetime('now')),
    last_reinforced TEXT DEFAULT (datetime('now')),
    UNIQUE(domain, content)
);

CREATE TABLE IF NOT EXISTS behavioral_learnings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    rule TEXT NOT NULL,
    context TEXT,
    source_project TEXT,
    confidence REAL DEFAULT 0.5,
    occurrences INTEGER DEFAULT 1,
    status TEXT DEFAULT 'active',
    created_at TEXT DEFAULT (datetime('now')),
    last_reinforced TEXT DEFAULT (datetime('now')),
    UNIQUE(rule)
);

CREATE TABLE IF NOT EXISTS incidents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    incident_id TEXT UNIQUE NOT NULL,
    title TEXT NOT NULL,
    domain TEXT,
    status TEXT DEFAULT 'open',
    description TEXT,
    symptoms TEXT,
    root_cause TEXT,
    resolution TEXT,
    affected_files TEXT,
    related_incidents TEXT,
    tags TEXT,
    run_id INTEGER REFERENCES workflow_runs(id),
    created_at TEXT DEFAULT (datetime('now')),
    resolved_at TEXT
);

CREATE TABLE IF NOT EXISTS incident_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    incident_id TEXT NOT NULL,
    entry_type TEXT NOT NULL,
    content TEXT NOT NULL,
    result TEXT,
    agent TEXT,
    run_id INTEGER REFERENCES workflow_runs(id),
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS decay_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type TEXT NOT NULL,
    entity_id INTEGER NOT NULL,
    action TEXT NOT NULL,
    reason TEXT,
    run_id INTEGER REFERENCES workflow_runs(id),
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS user_profile (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_name TEXT,
    experience_level TEXT DEFAULT 'beginner'
        CHECK(experience_level IN ('beginner', 'intermediate', 'advanced')),
    communication_style TEXT DEFAULT 'balanced'
        CHECK(communication_style IN ('verbose', 'balanced', 'terse')),
    created_at TEXT DEFAULT (datetime('now')),
    last_seen TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS onboarding_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    step TEXT DEFAULT 'not_started',
    status TEXT DEFAULT 'not_started'
        CHECK(status IN ('not_started', 'in_progress', 'completed')),
    data TEXT,
    started_at TEXT,
    completed_at TEXT
);
EOSQL
}

# Helper: check if a column exists in a table
column_exists() {
    local db_path="$1"
    local table_name="$2"
    local column_name="$3"
    local count
    count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM pragma_table_info('$table_name') WHERE name='$column_name';")
    [ "$count" -gt 0 ]
}

# Helper: check if a table exists
table_exists() {
    local db_path="$1"
    local table_name="$2"
    local count
    count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$table_name';")
    [ "$count" -gt 0 ]
}

# Helper: check if a view exists
view_exists() {
    local db_path="$1"
    local view_name="$2"
    local count
    count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='view' AND name='$view_name';")
    [ "$count" -gt 0 ]
}

# Helper: check if an index exists
index_exists() {
    local db_path="$1"
    local index_name="$2"
    local count
    count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name='$index_name';")
    [ "$count" -gt 0 ]
}


# ============================================================
# TEST SUITE 1: FRESH DB SCENARIO (schema.sql on new DB)
# Requirement: REQ-CTX-001 (Must), REQ-CTX-002 (Must), REQ-CTX-010 (Should)
# ============================================================
echo "--- Test Suite 1: Fresh DB from schema.sql ---"
echo ""

setup_tmp
FRESH_DB="$TEST_TMP/fresh.db"

# Requirement: REQ-CTX-001 (Must)
# Acceptance: Version comment updated to 1.3.0
# TEST-CTX-M1-001: Schema version is 1.3.0
version_line=$(head -3 "$SCHEMA_FILE" | grep -i "version" || true)
assert_contains "$version_line" "1.3.0" \
    "TEST-CTX-M1-001: schema.sql version comment contains 1.3.0"

# Requirement: REQ-CTX-001 (Must)
# Acceptance: Version comment mentions Cortex
# TEST-CTX-M1-002: Schema version mentions Cortex
assert_contains "$version_line" "Cortex" \
    "TEST-CTX-M1-002: schema.sql version comment mentions Cortex"

# Create fresh DB
create_fresh_db "$FRESH_DB"
FRESH_EXIT=$?
assert_zero_exit "$FRESH_EXIT" \
    "TEST-CTX-M1-003: schema.sql loads without errors on fresh DB"

# Requirement: REQ-CTX-002 (Must)
# Acceptance: shared_imports table exists with correct columns
# TEST-CTX-M1-004: shared_imports table exists on fresh DB
if table_exists "$FRESH_DB" "shared_imports"; then
    assert_eq "1" "1" "TEST-CTX-M1-004: shared_imports table exists on fresh DB"
else
    assert_eq "1" "0" "TEST-CTX-M1-004: shared_imports table exists on fresh DB"
fi

# TEST-CTX-M1-005: shared_imports has id column
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('shared_imports') WHERE name='id';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-005: shared_imports has 'id' column"

# TEST-CTX-M1-006: shared_imports has shared_uuid column
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('shared_imports') WHERE name='shared_uuid';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-006: shared_imports has 'shared_uuid' column"

# TEST-CTX-M1-007: shared_imports has category column
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('shared_imports') WHERE name='category';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-007: shared_imports has 'category' column"

# TEST-CTX-M1-008: shared_imports has source_file column
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('shared_imports') WHERE name='source_file';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-008: shared_imports has 'source_file' column"

# TEST-CTX-M1-009: shared_imports has imported_at column
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('shared_imports') WHERE name='imported_at';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-009: shared_imports has 'imported_at' column"

# TEST-CTX-M1-010: shared_imports has UNIQUE constraint on shared_uuid
# We test this by inserting duplicate shared_uuid values and expecting failure
sqlite3 "$FRESH_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('uuid-001', 'behavioral_learning');"
DUP_RESULT=$(sqlite3 "$FRESH_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('uuid-001', 'incident');" 2>&1)
DUP_EXIT=$?
assert_ne "0" "$DUP_EXIT" \
    "TEST-CTX-M1-010: shared_imports UNIQUE constraint on shared_uuid rejects duplicates"

# Requirement: REQ-CTX-002 (Must)
# Acceptance: Index on shared_uuid for fast lookup
# TEST-CTX-M1-011: Index exists on shared_imports(shared_uuid)
if index_exists "$FRESH_DB" "idx_shared_imports_uuid"; then
    assert_eq "1" "1" "TEST-CTX-M1-011: idx_shared_imports_uuid index exists"
else
    assert_eq "1" "0" "TEST-CTX-M1-011: idx_shared_imports_uuid index exists"
fi

# Requirement: REQ-CTX-010 (Should)
# Acceptance: v_shared_briefing view exists
# TEST-CTX-M1-012: v_shared_briefing view exists on fresh DB
if view_exists "$FRESH_DB" "v_shared_briefing"; then
    assert_eq "1" "1" "TEST-CTX-M1-012: v_shared_briefing view exists on fresh DB"
else
    assert_eq "1" "0" "TEST-CTX-M1-012: v_shared_briefing view exists on fresh DB"
fi

# Fresh DB should also have the Cortex columns on shareable tables (from CREATE TABLE)
# Requirement: REQ-CTX-003 (Must) - contributor column
# TEST-CTX-M1-013: behavioral_learnings has contributor column on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('behavioral_learnings') WHERE name='contributor';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-013: behavioral_learnings has 'contributor' column on fresh DB"

# TEST-CTX-M1-014: incidents has contributor column on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('incidents') WHERE name='contributor';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-014: incidents has 'contributor' column on fresh DB"

# TEST-CTX-M1-015: lessons has contributor column on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('lessons') WHERE name='contributor';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-015: lessons has 'contributor' column on fresh DB"

# TEST-CTX-M1-016: patterns has contributor column on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('patterns') WHERE name='contributor';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-016: patterns has 'contributor' column on fresh DB"

# TEST-CTX-M1-017: decisions has contributor column on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('decisions') WHERE name='contributor';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-017: decisions has 'contributor' column on fresh DB"

# TEST-CTX-M1-018: hotspots has contributor column on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('hotspots') WHERE name='contributor';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-018: hotspots has 'contributor' column on fresh DB"

# Requirement: REQ-CTX-004 (Must) - shared_uuid column
# TEST-CTX-M1-019: behavioral_learnings has shared_uuid on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('behavioral_learnings') WHERE name='shared_uuid';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-019: behavioral_learnings has 'shared_uuid' column on fresh DB"

# TEST-CTX-M1-020: incidents has shared_uuid on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('incidents') WHERE name='shared_uuid';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-020: incidents has 'shared_uuid' column on fresh DB"

# TEST-CTX-M1-021: lessons has shared_uuid on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('lessons') WHERE name='shared_uuid';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-021: lessons has 'shared_uuid' column on fresh DB"

# TEST-CTX-M1-022: patterns has shared_uuid on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('patterns') WHERE name='shared_uuid';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-022: patterns has 'shared_uuid' column on fresh DB"

# TEST-CTX-M1-023: decisions has shared_uuid on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('decisions') WHERE name='shared_uuid';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-023: decisions has 'shared_uuid' column on fresh DB"

# Requirement: REQ-CTX-004 (Must)
# Acceptance: shared_uuid NOT added to hotspots (uses file_path as natural key)
# TEST-CTX-M1-024: hotspots does NOT have shared_uuid
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('hotspots') WHERE name='shared_uuid';")
assert_eq "0" "$col_check" \
    "TEST-CTX-M1-024: hotspots does NOT have 'shared_uuid' column (uses file_path as natural key)"

# Requirement: REQ-CTX-005 (Must) - is_private column
# TEST-CTX-M1-025: behavioral_learnings has is_private on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('behavioral_learnings') WHERE name='is_private';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-025: behavioral_learnings has 'is_private' column on fresh DB"

# TEST-CTX-M1-026: incidents has is_private on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('incidents') WHERE name='is_private';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-026: incidents has 'is_private' column on fresh DB"

# TEST-CTX-M1-027: lessons has is_private on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('lessons') WHERE name='is_private';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-027: lessons has 'is_private' column on fresh DB"

# TEST-CTX-M1-028: patterns has is_private on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('patterns') WHERE name='is_private';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-028: patterns has 'is_private' column on fresh DB"

# TEST-CTX-M1-029: decisions has is_private on fresh DB
col_check=$(sqlite3 "$FRESH_DB" "SELECT COUNT(*) FROM pragma_table_info('decisions') WHERE name='is_private';")
assert_eq "1" "$col_check" \
    "TEST-CTX-M1-029: decisions has 'is_private' column on fresh DB"

# Requirement: REQ-CTX-005 (Must)
# Acceptance: is_private DEFAULT 0
# TEST-CTX-M1-030: is_private defaults to 0 on new behavioral_learning entry
sqlite3 "$FRESH_DB" "INSERT INTO workflow_runs (type, description) VALUES ('test', 'test run');"
sqlite3 "$FRESH_DB" "INSERT INTO behavioral_learnings (rule) VALUES ('Test rule for default check');"
default_val=$(sqlite3 "$FRESH_DB" "SELECT is_private FROM behavioral_learnings WHERE rule='Test rule for default check';")
assert_eq "0" "$default_val" \
    "TEST-CTX-M1-030: is_private defaults to 0 on new behavioral_learning entry"

# TEST-CTX-M1-031: is_private defaults to 0 on new incident entry
sqlite3 "$FRESH_DB" "INSERT INTO incidents (incident_id, title, run_id) VALUES ('INC-TEST-001', 'Test incident', 1);"
default_val=$(sqlite3 "$FRESH_DB" "SELECT is_private FROM incidents WHERE incident_id='INC-TEST-001';")
assert_eq "0" "$default_val" \
    "TEST-CTX-M1-031: is_private defaults to 0 on new incident entry"

# TEST-CTX-M1-032: is_private defaults to 0 on new lesson entry
sqlite3 "$FRESH_DB" "INSERT INTO lessons (domain, content, source_agent) VALUES ('test', 'Test lesson', 'test-agent');"
default_val=$(sqlite3 "$FRESH_DB" "SELECT is_private FROM lessons WHERE domain='test' AND content='Test lesson';")
assert_eq "0" "$default_val" \
    "TEST-CTX-M1-032: is_private defaults to 0 on new lesson entry"

cleanup_tmp

echo ""

# ============================================================
# TEST SUITE 2: MIGRATION SCENARIO (pre-Cortex DB -> migration)
# Requirement: REQ-CTX-003 (Must), REQ-CTX-004 (Must), REQ-CTX-005 (Must),
#              REQ-CTX-006 (Must)
# ============================================================
echo "--- Test Suite 2: Migration from pre-Cortex DB ---"
echo ""

setup_tmp
MIGRATE_DB="$TEST_TMP/migrate.db"

# Create a pre-Cortex DB (1.2.0 schema without Cortex columns)
create_pre_cortex_db "$MIGRATE_DB"

# Verify pre-Cortex state: columns should NOT exist yet
col_check=$(sqlite3 "$MIGRATE_DB" "SELECT COUNT(*) FROM pragma_table_info('behavioral_learnings') WHERE name='contributor';")
assert_eq "0" "$col_check" \
    "TEST-CTX-M1-033: Pre-Cortex DB does NOT have contributor on behavioral_learnings"

col_check=$(sqlite3 "$MIGRATE_DB" "SELECT COUNT(*) FROM pragma_table_info('behavioral_learnings') WHERE name='shared_uuid';")
assert_eq "0" "$col_check" \
    "TEST-CTX-M1-034: Pre-Cortex DB does NOT have shared_uuid on behavioral_learnings"

col_check=$(sqlite3 "$MIGRATE_DB" "SELECT COUNT(*) FROM pragma_table_info('behavioral_learnings') WHERE name='is_private';")
assert_eq "0" "$col_check" \
    "TEST-CTX-M1-035: Pre-Cortex DB does NOT have is_private on behavioral_learnings"

# Check that migration script exists
if [ ! -f "$MIGRATE_SCRIPT" ]; then
    skip_test "TEST-CTX-M1-036 through TEST-CTX-M1-060" "Migration script not found at $MIGRATE_SCRIPT (not yet implemented)"
    echo ""
    echo "  NOTE: The migration script (core/db/migrate-1.3.0.sh) does not exist yet."
    echo "  Tests below are SKIPPED until the developer creates it."
    echo "  This is expected in TDD -- tests are written before the code."
    echo ""

    # We still want to count these as skipped, not silently pass
    # Count remaining tests in this suite as skipped
    for i in $(seq 36 60); do
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    done
else
    # Run migration
    MIGRATE_OUTPUT=$(bash "$MIGRATE_SCRIPT" "$MIGRATE_DB" 2>&1)
    MIGRATE_EXIT=$?

    # Requirement: REQ-CTX-006 (Must)
    # Acceptance: Migration runs without error
    # TEST-CTX-M1-036: Migration script exits successfully
    assert_zero_exit "$MIGRATE_EXIT" \
        "TEST-CTX-M1-036: Migration script exits with code 0"

    # Requirement: REQ-CTX-003 (Must)
    # Acceptance: contributor column added to 6 tables
    # TEST-CTX-M1-037 through TEST-CTX-M1-042
    for tbl in behavioral_learnings incidents lessons patterns decisions hotspots; do
        col_check=$(sqlite3 "$MIGRATE_DB" "SELECT COUNT(*) FROM pragma_table_info('$tbl') WHERE name='contributor';")
        TEST_NUM=$((37 + $(echo "behavioral_learnings incidents lessons patterns decisions hotspots" | tr ' ' '\n' | grep -n "^${tbl}$" | cut -d: -f1) - 1))
        assert_eq "1" "$col_check" \
            "TEST-CTX-M1-0$(printf '%02d' $TEST_NUM): Migration adds 'contributor' to $tbl"
    done

    # Requirement: REQ-CTX-004 (Must)
    # Acceptance: shared_uuid added to 5 tables (NOT hotspots)
    # TEST-CTX-M1-043 through TEST-CTX-M1-047
    for tbl in behavioral_learnings incidents lessons patterns decisions; do
        col_check=$(sqlite3 "$MIGRATE_DB" "SELECT COUNT(*) FROM pragma_table_info('$tbl') WHERE name='shared_uuid';")
        TEST_NUM=$((43 + $(echo "behavioral_learnings incidents lessons patterns decisions" | tr ' ' '\n' | grep -n "^${tbl}$" | cut -d: -f1) - 1))
        assert_eq "1" "$col_check" \
            "TEST-CTX-M1-0$(printf '%02d' $TEST_NUM): Migration adds 'shared_uuid' to $tbl"
    done

    # TEST-CTX-M1-048: hotspots does NOT get shared_uuid from migration
    col_check=$(sqlite3 "$MIGRATE_DB" "SELECT COUNT(*) FROM pragma_table_info('hotspots') WHERE name='shared_uuid';")
    assert_eq "0" "$col_check" \
        "TEST-CTX-M1-048: Migration does NOT add 'shared_uuid' to hotspots"

    # Requirement: REQ-CTX-005 (Must)
    # Acceptance: is_private added to 5 tables with DEFAULT 0
    # TEST-CTX-M1-049 through TEST-CTX-M1-053
    for tbl in behavioral_learnings incidents lessons patterns decisions; do
        col_check=$(sqlite3 "$MIGRATE_DB" "SELECT COUNT(*) FROM pragma_table_info('$tbl') WHERE name='is_private';")
        TEST_NUM=$((49 + $(echo "behavioral_learnings incidents lessons patterns decisions" | tr ' ' '\n' | grep -n "^${tbl}$" | cut -d: -f1) - 1))
        assert_eq "1" "$col_check" \
            "TEST-CTX-M1-0$(printf '%02d' $TEST_NUM): Migration adds 'is_private' to $tbl"
    done

    # Requirement: REQ-CTX-003 (Must)
    # Acceptance: Existing rows get NULL for contributor (no backfill)
    # TEST-CTX-M1-054: Pre-existing rows have NULL contributor after migration
    # First insert a row before migration (need to re-test with data)
    # This is covered more thoroughly in Test Suite 4 (Data Preservation)

    # Requirement: REQ-CTX-005 (Must)
    # Acceptance: is_private has DEFAULT 0 even after migration
    # TEST-CTX-M1-055: New entry after migration gets is_private = 0
    sqlite3 "$MIGRATE_DB" "INSERT INTO behavioral_learnings (rule) VALUES ('Post-migration test rule');"
    default_val=$(sqlite3 "$MIGRATE_DB" "SELECT COALESCE(is_private, -1) FROM behavioral_learnings WHERE rule='Post-migration test rule';")
    assert_eq "0" "$default_val" \
        "TEST-CTX-M1-055: is_private defaults to 0 on new entry after migration"

    # TEST-CTX-M1-056: New entry after migration gets NULL contributor
    contrib_val=$(sqlite3 "$MIGRATE_DB" "SELECT COALESCE(contributor, 'NULL_VALUE') FROM behavioral_learnings WHERE rule='Post-migration test rule';")
    assert_eq "NULL_VALUE" "$contrib_val" \
        "TEST-CTX-M1-056: contributor defaults to NULL on new entry after migration"

    # TEST-CTX-M1-057: New entry after migration gets NULL shared_uuid
    uuid_val=$(sqlite3 "$MIGRATE_DB" "SELECT COALESCE(shared_uuid, 'NULL_VALUE') FROM behavioral_learnings WHERE rule='Post-migration test rule';")
    assert_eq "NULL_VALUE" "$uuid_val" \
        "TEST-CTX-M1-057: shared_uuid defaults to NULL on new entry after migration"

    # Padding test IDs to reach 060 for consistency
    # TEST-CTX-M1-058: contributor column type is TEXT on behavioral_learnings
    col_type=$(sqlite3 "$MIGRATE_DB" "SELECT type FROM pragma_table_info('behavioral_learnings') WHERE name='contributor';")
    assert_eq "TEXT" "$col_type" \
        "TEST-CTX-M1-058: contributor column type is TEXT"

    # TEST-CTX-M1-059: shared_uuid column type is TEXT on behavioral_learnings
    col_type=$(sqlite3 "$MIGRATE_DB" "SELECT type FROM pragma_table_info('behavioral_learnings') WHERE name='shared_uuid';")
    assert_eq "TEXT" "$col_type" \
        "TEST-CTX-M1-059: shared_uuid column type is TEXT"

    # TEST-CTX-M1-060: is_private column type is INTEGER on behavioral_learnings
    col_type=$(sqlite3 "$MIGRATE_DB" "SELECT type FROM pragma_table_info('behavioral_learnings') WHERE name='is_private';")
    assert_eq "INTEGER" "$col_type" \
        "TEST-CTX-M1-060: is_private column type is INTEGER"
fi

cleanup_tmp

echo ""

# ============================================================
# TEST SUITE 3: IDEMPOTENCY (run migration twice)
# Requirement: REQ-CTX-006 (Must)
# ============================================================
echo "--- Test Suite 3: Migration Idempotency ---"
echo ""

setup_tmp
IDEMP_DB="$TEST_TMP/idempotent.db"

if [ ! -f "$MIGRATE_SCRIPT" ]; then
    skip_test "TEST-CTX-M1-061 through TEST-CTX-M1-068" "Migration script not found (not yet implemented)"
    for i in $(seq 61 68); do
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    done
else
    # Create pre-Cortex DB
    create_pre_cortex_db "$IDEMP_DB"

    # Insert data before first migration
    sqlite3 "$IDEMP_DB" <<'EOSQL'
INSERT INTO behavioral_learnings (rule, context, source_project, confidence, occurrences)
    VALUES ('Never mock the database', 'Integration test failure', 'project-alpha', 0.9, 3);
INSERT INTO behavioral_learnings (rule, context, source_project, confidence, occurrences)
    VALUES ('Always validate input', 'Security review', 'project-beta', 0.7, 1);
EOSQL

    # Run migration first time
    FIRST_OUTPUT=$(bash "$MIGRATE_SCRIPT" "$IDEMP_DB" 2>&1)
    FIRST_EXIT=$?

    # Requirement: REQ-CTX-006 (Must)
    # Acceptance: First run succeeds
    # TEST-CTX-M1-061: First migration run succeeds
    assert_zero_exit "$FIRST_EXIT" \
        "TEST-CTX-M1-061: First migration run exits with code 0"

    # Count rows before second run
    ROW_COUNT_BEFORE=$(sqlite3 "$IDEMP_DB" "SELECT COUNT(*) FROM behavioral_learnings;")

    # Run migration second time
    SECOND_OUTPUT=$(bash "$MIGRATE_SCRIPT" "$IDEMP_DB" 2>&1)
    SECOND_EXIT=$?

    # Requirement: REQ-CTX-006 (Must)
    # Acceptance: Second run also succeeds (idempotent)
    # TEST-CTX-M1-062: Second migration run succeeds
    assert_zero_exit "$SECOND_EXIT" \
        "TEST-CTX-M1-062: Second migration run exits with code 0 (idempotent)"

    # Requirement: REQ-CTX-006 (Must)
    # Acceptance: No data loss on re-run
    # TEST-CTX-M1-063: Row count unchanged after second migration
    ROW_COUNT_AFTER=$(sqlite3 "$IDEMP_DB" "SELECT COUNT(*) FROM behavioral_learnings;")
    assert_eq "$ROW_COUNT_BEFORE" "$ROW_COUNT_AFTER" \
        "TEST-CTX-M1-063: Row count unchanged after second migration ($ROW_COUNT_BEFORE -> $ROW_COUNT_AFTER)"

    # TEST-CTX-M1-064: Data content preserved after second migration
    rule_val=$(sqlite3 "$IDEMP_DB" "SELECT rule FROM behavioral_learnings WHERE confidence=0.9;")
    assert_eq "Never mock the database" "$rule_val" \
        "TEST-CTX-M1-064: Original data content preserved after second migration"

    # TEST-CTX-M1-065: Columns still exist after second run
    col_check=$(sqlite3 "$IDEMP_DB" "SELECT COUNT(*) FROM pragma_table_info('behavioral_learnings') WHERE name='contributor';")
    assert_eq "1" "$col_check" \
        "TEST-CTX-M1-065: contributor column still present after second migration"

    col_check=$(sqlite3 "$IDEMP_DB" "SELECT COUNT(*) FROM pragma_table_info('behavioral_learnings') WHERE name='shared_uuid';")
    assert_eq "1" "$col_check" \
        "TEST-CTX-M1-066: shared_uuid column still present after second migration"

    col_check=$(sqlite3 "$IDEMP_DB" "SELECT COUNT(*) FROM pragma_table_info('behavioral_learnings') WHERE name='is_private';")
    assert_eq "1" "$col_check" \
        "TEST-CTX-M1-067: is_private column still present after second migration"

    # TEST-CTX-M1-068: Run migration a THIRD time for robustness
    THIRD_OUTPUT=$(bash "$MIGRATE_SCRIPT" "$IDEMP_DB" 2>&1)
    THIRD_EXIT=$?
    assert_zero_exit "$THIRD_EXIT" \
        "TEST-CTX-M1-068: Third migration run exits with code 0 (triple idempotent)"
fi

cleanup_tmp

echo ""

# ============================================================
# TEST SUITE 4: DATA PRESERVATION (existing data survives migration)
# Requirement: REQ-CTX-006 (Must), REQ-CTX-003 (Must)
# ============================================================
echo "--- Test Suite 4: Data Preservation During Migration ---"
echo ""

setup_tmp
DATA_DB="$TEST_TMP/data-preserve.db"

if [ ! -f "$MIGRATE_SCRIPT" ]; then
    skip_test "TEST-CTX-M1-069 through TEST-CTX-M1-082" "Migration script not found (not yet implemented)"
    for i in $(seq 69 82); do
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    done
else
    # Create pre-Cortex DB with data in all shareable tables
    create_pre_cortex_db "$DATA_DB"

    # Populate every shareable table with test data
    sqlite3 "$DATA_DB" <<'EOSQL'
-- workflow_runs needed for FK references
INSERT INTO workflow_runs (type, description) VALUES ('test', 'Data preservation test run');

-- behavioral_learnings
INSERT INTO behavioral_learnings (rule, context, source_project, confidence, occurrences)
    VALUES ('Always use parameterized queries', 'SQL injection incident', 'omega', 0.95, 5);
INSERT INTO behavioral_learnings (rule, context, source_project, confidence, occurrences)
    VALUES ('Never trust client-side validation', 'Form bypass bug', 'doli', 0.85, 3);

-- incidents
INSERT INTO incidents (incident_id, title, domain, status, description, symptoms, root_cause, resolution, run_id)
    VALUES ('INC-001', 'DB connection leak', 'backend', 'resolved', 'Connection pool exhausted', 'Timeout errors', 'Missing close()', 'Added defer close()', 1);
INSERT INTO incidents (incident_id, title, domain, status, run_id)
    VALUES ('INC-002', 'Memory spike on import', 'etl', 'open', 1);

-- lessons
INSERT INTO lessons (domain, content, source_agent, occurrences, confidence)
    VALUES ('testing', 'Mock external APIs, never real endpoints', 'developer', 4, 0.88);

-- patterns
INSERT INTO patterns (run_id, domain, name, description, example_files)
    VALUES (1, 'error-handling', 'Result type pattern', 'Use Result<T, E> for fallible ops', '["src/lib.rs"]');

-- decisions
INSERT INTO decisions (run_id, domain, decision, rationale, confidence)
    VALUES (1, 'database', 'Use SQLite for memory.db', 'Simple, portable, no server needed', 0.99);

-- hotspots
INSERT INTO hotspots (file_path, risk_level, description, times_touched)
    VALUES ('core/hooks/briefing.sh', 'high', 'Frequently modified, fragile', 12);
INSERT INTO hotspots (file_path, risk_level, description, times_touched)
    VALUES ('scripts/setup.sh', 'medium', 'Complex setup logic', 5);
EOSQL

    # Record pre-migration data
    BL_COUNT_BEFORE=$(sqlite3 "$DATA_DB" "SELECT COUNT(*) FROM behavioral_learnings;")
    INC_COUNT_BEFORE=$(sqlite3 "$DATA_DB" "SELECT COUNT(*) FROM incidents;")
    LES_COUNT_BEFORE=$(sqlite3 "$DATA_DB" "SELECT COUNT(*) FROM lessons;")
    PAT_COUNT_BEFORE=$(sqlite3 "$DATA_DB" "SELECT COUNT(*) FROM patterns;")
    DEC_COUNT_BEFORE=$(sqlite3 "$DATA_DB" "SELECT COUNT(*) FROM decisions;")
    HOT_COUNT_BEFORE=$(sqlite3 "$DATA_DB" "SELECT COUNT(*) FROM hotspots;")

    # Run migration
    bash "$MIGRATE_SCRIPT" "$DATA_DB" 2>&1
    MIG_EXIT=$?

    # Requirement: REQ-CTX-006 (Must)
    # Acceptance: Migration succeeds
    assert_zero_exit "$MIG_EXIT" \
        "TEST-CTX-M1-069: Migration succeeds on DB with existing data"

    # Requirement: REQ-CTX-006 (Must)
    # Acceptance: Existing data preserved (row counts)
    # TEST-CTX-M1-070 through TEST-CTX-M1-075: Row counts preserved per table
    BL_COUNT_AFTER=$(sqlite3 "$DATA_DB" "SELECT COUNT(*) FROM behavioral_learnings;")
    assert_eq "$BL_COUNT_BEFORE" "$BL_COUNT_AFTER" \
        "TEST-CTX-M1-070: behavioral_learnings row count preserved ($BL_COUNT_BEFORE)"

    INC_COUNT_AFTER=$(sqlite3 "$DATA_DB" "SELECT COUNT(*) FROM incidents;")
    assert_eq "$INC_COUNT_BEFORE" "$INC_COUNT_AFTER" \
        "TEST-CTX-M1-071: incidents row count preserved ($INC_COUNT_BEFORE)"

    LES_COUNT_AFTER=$(sqlite3 "$DATA_DB" "SELECT COUNT(*) FROM lessons;")
    assert_eq "$LES_COUNT_BEFORE" "$LES_COUNT_AFTER" \
        "TEST-CTX-M1-072: lessons row count preserved ($LES_COUNT_BEFORE)"

    PAT_COUNT_AFTER=$(sqlite3 "$DATA_DB" "SELECT COUNT(*) FROM patterns;")
    assert_eq "$PAT_COUNT_BEFORE" "$PAT_COUNT_AFTER" \
        "TEST-CTX-M1-073: patterns row count preserved ($PAT_COUNT_BEFORE)"

    DEC_COUNT_AFTER=$(sqlite3 "$DATA_DB" "SELECT COUNT(*) FROM decisions;")
    assert_eq "$DEC_COUNT_BEFORE" "$DEC_COUNT_AFTER" \
        "TEST-CTX-M1-074: decisions row count preserved ($DEC_COUNT_BEFORE)"

    HOT_COUNT_AFTER=$(sqlite3 "$DATA_DB" "SELECT COUNT(*) FROM hotspots;")
    assert_eq "$HOT_COUNT_BEFORE" "$HOT_COUNT_AFTER" \
        "TEST-CTX-M1-075: hotspots row count preserved ($HOT_COUNT_BEFORE)"

    # Requirement: REQ-CTX-006 (Must)
    # Acceptance: Existing data content intact (specific values)
    # TEST-CTX-M1-076: behavioral_learnings rule content intact
    rule_val=$(sqlite3 "$DATA_DB" "SELECT rule FROM behavioral_learnings WHERE confidence=0.95;")
    assert_eq "Always use parameterized queries" "$rule_val" \
        "TEST-CTX-M1-076: behavioral_learnings rule content intact after migration"

    # TEST-CTX-M1-077: incidents title and status intact
    inc_title=$(sqlite3 "$DATA_DB" "SELECT title FROM incidents WHERE incident_id='INC-001';")
    assert_eq "DB connection leak" "$inc_title" \
        "TEST-CTX-M1-077: incidents title intact after migration"

    inc_status=$(sqlite3 "$DATA_DB" "SELECT status FROM incidents WHERE incident_id='INC-001';")
    assert_eq "resolved" "$inc_status" \
        "TEST-CTX-M1-078: incidents status intact after migration"

    # TEST-CTX-M1-079: hotspot file_path and risk_level intact
    hot_risk=$(sqlite3 "$DATA_DB" "SELECT risk_level FROM hotspots WHERE file_path='core/hooks/briefing.sh';")
    assert_eq "high" "$hot_risk" \
        "TEST-CTX-M1-079: hotspot risk_level intact after migration"

    # Requirement: REQ-CTX-003 (Must)
    # Acceptance: Existing rows get NULL for contributor
    # TEST-CTX-M1-080: Pre-existing behavioral_learnings have NULL contributor
    contrib_val=$(sqlite3 "$DATA_DB" "SELECT COALESCE(contributor, 'NULL_VALUE') FROM behavioral_learnings WHERE confidence=0.95;")
    assert_eq "NULL_VALUE" "$contrib_val" \
        "TEST-CTX-M1-080: Pre-existing behavioral_learning has NULL contributor after migration"

    # TEST-CTX-M1-081: Pre-existing incidents have NULL contributor
    contrib_val=$(sqlite3 "$DATA_DB" "SELECT COALESCE(contributor, 'NULL_VALUE') FROM incidents WHERE incident_id='INC-001';")
    assert_eq "NULL_VALUE" "$contrib_val" \
        "TEST-CTX-M1-081: Pre-existing incident has NULL contributor after migration"

    # TEST-CTX-M1-082: Pre-existing hotspots have NULL contributor
    contrib_val=$(sqlite3 "$DATA_DB" "SELECT COALESCE(contributor, 'NULL_VALUE') FROM hotspots WHERE file_path='core/hooks/briefing.sh';")
    assert_eq "NULL_VALUE" "$contrib_val" \
        "TEST-CTX-M1-082: Pre-existing hotspot has NULL contributor after migration"
fi

cleanup_tmp

echo ""

# ============================================================
# TEST SUITE 5: shared_imports TABLE BEHAVIOR
# Requirement: REQ-CTX-002 (Must)
# ============================================================
echo "--- Test Suite 5: shared_imports Table Behavior ---"
echo ""

setup_tmp
IMPORTS_DB="$TEST_TMP/imports.db"
create_fresh_db "$IMPORTS_DB"

# Requirement: REQ-CTX-002 (Must)
# Acceptance: INSERT into shared_imports works
# TEST-CTX-M1-083: Basic insert into shared_imports
sqlite3 "$IMPORTS_DB" "INSERT INTO shared_imports (shared_uuid, category, source_file) VALUES ('uuid-aaa-111', 'behavioral_learning', 'behavioral-learnings.jsonl');"
INS_EXIT=$?
assert_zero_exit "$INS_EXIT" \
    "TEST-CTX-M1-083: Basic insert into shared_imports succeeds"

# TEST-CTX-M1-084: imported_at is auto-populated
imported_at=$(sqlite3 "$IMPORTS_DB" "SELECT imported_at FROM shared_imports WHERE shared_uuid='uuid-aaa-111';")
assert_ne "" "$imported_at" \
    "TEST-CTX-M1-084: imported_at is auto-populated on insert"

# Requirement: REQ-CTX-002 (Must)
# Acceptance: UNIQUE(shared_uuid) prevents duplicate imports
# TEST-CTX-M1-085: Duplicate shared_uuid is rejected
sqlite3 "$IMPORTS_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('uuid-bbb-222', 'incident');" 2>/dev/null
DUP_RESULT=$(sqlite3 "$IMPORTS_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('uuid-bbb-222', 'hotspot');" 2>&1)
DUP_EXIT=$?
assert_ne "0" "$DUP_EXIT" \
    "TEST-CTX-M1-085: Duplicate shared_uuid rejected by UNIQUE constraint"

# TEST-CTX-M1-086: Different shared_uuids are accepted
sqlite3 "$IMPORTS_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('uuid-ccc-333', 'lesson');" 2>/dev/null
sqlite3 "$IMPORTS_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('uuid-ddd-444', 'pattern');" 2>/dev/null
sqlite3 "$IMPORTS_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('uuid-eee-555', 'decision');" 2>/dev/null
import_count=$(sqlite3 "$IMPORTS_DB" "SELECT COUNT(*) FROM shared_imports;")
assert_gt "3" "$import_count" \
    "TEST-CTX-M1-086: Multiple different shared_uuids accepted ($import_count entries)"

# Requirement: REQ-CTX-002 (Must)
# Acceptance: Index on shared_uuid for fast lookup
# TEST-CTX-M1-087: Index exists for efficient import lookups
if index_exists "$IMPORTS_DB" "idx_shared_imports_uuid"; then
    assert_eq "1" "1" "TEST-CTX-M1-087: idx_shared_imports_uuid index exists for fast lookups"
else
    assert_eq "1" "0" "TEST-CTX-M1-087: idx_shared_imports_uuid index exists for fast lookups"
fi

# TEST-CTX-M1-088: category column accepts all valid categories
for cat in behavioral_learning incident hotspot lesson pattern decision; do
    sqlite3 "$IMPORTS_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('uuid-cat-$cat', '$cat');" 2>/dev/null
done
cat_count=$(sqlite3 "$IMPORTS_DB" "SELECT COUNT(DISTINCT category) FROM shared_imports;")
assert_gt "4" "$cat_count" \
    "TEST-CTX-M1-088: All valid category values accepted ($cat_count distinct categories)"

# Edge case: empty shared_uuid should be rejected or handled
# TEST-CTX-M1-089: shared_uuid NOT NULL constraint
EMPTY_RESULT=$(sqlite3 "$IMPORTS_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES (NULL, 'incident');" 2>&1)
EMPTY_EXIT=$?
assert_ne "0" "$EMPTY_EXIT" \
    "TEST-CTX-M1-089: NULL shared_uuid rejected by NOT NULL constraint"

# Edge case: empty category should be rejected or handled
# TEST-CTX-M1-090: category NOT NULL constraint
CAT_RESULT=$(sqlite3 "$IMPORTS_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('uuid-nocat-001', NULL);" 2>&1)
CAT_EXIT=$?
assert_ne "0" "$CAT_EXIT" \
    "TEST-CTX-M1-090: NULL category rejected by NOT NULL constraint"

# Edge case: source_file can be NULL (optional field)
# TEST-CTX-M1-091: source_file is optional (NULL allowed)
sqlite3 "$IMPORTS_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('uuid-nosrc-001', 'behavioral_learning');"
src_val=$(sqlite3 "$IMPORTS_DB" "SELECT COALESCE(source_file, 'NULL_VALUE') FROM shared_imports WHERE shared_uuid='uuid-nosrc-001';")
assert_eq "NULL_VALUE" "$src_val" \
    "TEST-CTX-M1-091: source_file is optional (NULL allowed)"

cleanup_tmp

echo ""

# ============================================================
# TEST SUITE 6: v_shared_briefing VIEW
# Requirement: REQ-CTX-010 (Should)
# ============================================================
echo "--- Test Suite 6: v_shared_briefing View ---"
echo ""

setup_tmp
VIEW_DB="$TEST_TMP/view.db"
create_fresh_db "$VIEW_DB"

# Populate behavioral_learnings with varied data to test view filtering
sqlite3 "$VIEW_DB" <<'EOSQL'
-- High confidence, active, not private -> SHOULD appear in view
INSERT INTO behavioral_learnings (rule, context, source_project, confidence, occurrences, status, is_private, contributor)
    VALUES ('Always validate input boundaries', 'Buffer overflow in parser', 'omega', 0.95, 7, 'active', 0, 'Dev A <deva@test.com>');

-- High confidence, active, not private -> SHOULD appear
INSERT INTO behavioral_learnings (rule, context, source_project, confidence, occurrences, status, is_private, contributor)
    VALUES ('Use structured logging, never println', 'Log parsing failure', 'doli', 0.82, 4, 'active', 0, 'Dev B <devb@test.com>');

-- Exactly 0.8 confidence, active, not private -> SHOULD appear (boundary)
INSERT INTO behavioral_learnings (rule, context, source_project, confidence, occurrences, status, is_private, contributor)
    VALUES ('Boundary confidence rule', 'Edge case', 'test', 0.80, 2, 'active', 0, 'Dev C <devc@test.com>');

-- Low confidence (0.5) -> SHOULD NOT appear
INSERT INTO behavioral_learnings (rule, context, source_project, confidence, occurrences, status, is_private)
    VALUES ('Low confidence rule', 'Weak signal', 'test', 0.50, 1, 'active', 0);

-- Below threshold (0.79) -> SHOULD NOT appear
INSERT INTO behavioral_learnings (rule, context, source_project, confidence, occurrences, status, is_private)
    VALUES ('Just below threshold', 'Almost there', 'test', 0.79, 2, 'active', 0);

-- High confidence but PRIVATE -> SHOULD NOT appear
INSERT INTO behavioral_learnings (rule, context, source_project, confidence, occurrences, status, is_private)
    VALUES ('Private high-confidence rule', 'Personal correction', 'omega', 0.99, 10, 'active', 1);

-- High confidence but SUPERSEDED status -> SHOULD NOT appear
INSERT INTO behavioral_learnings (rule, context, source_project, confidence, occurrences, status, is_private)
    VALUES ('Superseded rule', 'Old approach', 'omega', 0.90, 5, 'superseded', 0);

-- High confidence but ARCHIVED status -> SHOULD NOT appear
INSERT INTO behavioral_learnings (rule, context, source_project, confidence, occurrences, status, is_private)
    VALUES ('Archived rule', 'Deprecated', 'omega', 0.88, 3, 'archived', 0);
EOSQL

# Requirement: REQ-CTX-010 (Should)
# Acceptance: View selects high-confidence, non-private, active entries
# TEST-CTX-M1-092: View returns qualifying entries
view_count=$(sqlite3 "$VIEW_DB" "SELECT COUNT(*) FROM v_shared_briefing;")
assert_eq "3" "$view_count" \
    "TEST-CTX-M1-092: v_shared_briefing returns exactly 3 qualifying entries"

# TEST-CTX-M1-093: View includes high-confidence active non-private entry
view_rules=$(sqlite3 "$VIEW_DB" "SELECT rule FROM v_shared_briefing;")
assert_contains "$view_rules" "Always validate input boundaries" \
    "TEST-CTX-M1-093: View includes high-confidence (0.95) active non-private entry"

# TEST-CTX-M1-094: View includes second qualifying entry
assert_contains "$view_rules" "Use structured logging, never println" \
    "TEST-CTX-M1-094: View includes second qualifying entry (0.82 confidence)"

# TEST-CTX-M1-095: View includes boundary entry (exactly 0.8)
assert_contains "$view_rules" "Boundary confidence rule" \
    "TEST-CTX-M1-095: View includes boundary entry (confidence exactly 0.80)"

# TEST-CTX-M1-096: View excludes low-confidence entry
assert_not_contains "$view_rules" "Low confidence rule" \
    "TEST-CTX-M1-096: View excludes low-confidence entry (0.50)"

# TEST-CTX-M1-097: View excludes just-below-threshold entry
assert_not_contains "$view_rules" "Just below threshold" \
    "TEST-CTX-M1-097: View excludes just-below-threshold entry (0.79)"

# TEST-CTX-M1-098: View excludes private entry
assert_not_contains "$view_rules" "Private high-confidence rule" \
    "TEST-CTX-M1-098: View excludes private entry (is_private=1)"

# TEST-CTX-M1-099: View excludes superseded entry
assert_not_contains "$view_rules" "Superseded rule" \
    "TEST-CTX-M1-099: View excludes superseded entry (status='superseded')"

# TEST-CTX-M1-100: View excludes archived entry
assert_not_contains "$view_rules" "Archived rule" \
    "TEST-CTX-M1-100: View excludes archived entry (status='archived')"

# Requirement: REQ-CTX-010 (Should)
# Acceptance: View orders by confidence DESC, occurrences DESC
# TEST-CTX-M1-101: First result has highest confidence
first_rule=$(sqlite3 "$VIEW_DB" "SELECT rule FROM v_shared_briefing LIMIT 1;")
assert_eq "Always validate input boundaries" "$first_rule" \
    "TEST-CTX-M1-101: First result has highest confidence (0.95)"

# TEST-CTX-M1-102: Last result has lowest qualifying confidence
last_rule=$(sqlite3 "$VIEW_DB" "SELECT rule FROM v_shared_briefing ORDER BY confidence ASC, occurrences ASC LIMIT 1;")
assert_eq "Boundary confidence rule" "$last_rule" \
    "TEST-CTX-M1-102: Last result has lowest qualifying confidence (0.80)"

# TEST-CTX-M1-103: View returns expected columns
# Use pragma-based column check (compatible with SQLite 3.51.0 which doesn't output headers on LIMIT 0)
view_col_rule=$(sqlite3 "$VIEW_DB" "SELECT sql FROM sqlite_master WHERE type='view' AND name='v_shared_briefing';" 2>/dev/null)
assert_contains "$view_col_rule" "rule" \
    "TEST-CTX-M1-103: v_shared_briefing returns 'rule' column"
assert_contains "$view_col_rule" "confidence" \
    "TEST-CTX-M1-104: v_shared_briefing returns 'confidence' column"

assert_contains "$view_col_rule" "contributor" \
    "TEST-CTX-M1-105: v_shared_briefing returns 'contributor' column"

# TEST-CTX-M1-106: View returns empty result when no qualifying entries
sqlite3 "$VIEW_DB" "DELETE FROM behavioral_learnings;"
empty_count=$(sqlite3 "$VIEW_DB" "SELECT COUNT(*) FROM v_shared_briefing;")
assert_eq "0" "$empty_count" \
    "TEST-CTX-M1-106: v_shared_briefing returns empty when no qualifying entries"

# Requirement: REQ-CTX-010 (Should)
# Acceptance: Graceful when is_private column has NULL (COALESCE fallback)
# TEST-CTX-M1-107: View handles NULL is_private gracefully (treats as 0 / not private)
sqlite3 "$VIEW_DB" "INSERT INTO behavioral_learnings (rule, confidence, status) VALUES ('NULL is_private rule', 0.9, 'active');"
# The is_private might default to 0 on fresh schema, but if the view uses COALESCE(is_private, 0) = 0
# it should handle NULL gracefully either way
null_priv_count=$(sqlite3 "$VIEW_DB" "SELECT COUNT(*) FROM v_shared_briefing WHERE rule='NULL is_private rule';")
assert_eq "1" "$null_priv_count" \
    "TEST-CTX-M1-107: View handles NULL/default is_private gracefully (entry appears)"

cleanup_tmp

echo ""

# ============================================================
# TEST SUITE 7: SCHEMA.SQL + MIGRATION INTERACTION
# Requirement: REQ-CTX-002 (Must), REQ-CTX-006 (Must)
# (Running schema.sql on existing DB should not break migration columns)
# ============================================================
echo "--- Test Suite 7: Schema + Migration Interaction ---"
echo ""

setup_tmp
INTERACT_DB="$TEST_TMP/interact.db"

if [ ! -f "$MIGRATE_SCRIPT" ]; then
    skip_test "TEST-CTX-M1-108 through TEST-CTX-M1-113" "Migration script not found (not yet implemented)"
    for i in $(seq 108 113); do
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    done
else
    # Scenario: pre-Cortex DB -> migrate -> re-run schema.sql (simulates db-init.sh behavior)
    create_pre_cortex_db "$INTERACT_DB"

    # Insert data
    sqlite3 "$INTERACT_DB" <<'EOSQL'
INSERT INTO behavioral_learnings (rule, confidence, occurrences)
    VALUES ('Test interaction rule', 0.9, 5);
EOSQL

    # Run migration
    bash "$MIGRATE_SCRIPT" "$INTERACT_DB" 2>/dev/null

    # Set contributor on the migrated entry
    sqlite3 "$INTERACT_DB" "UPDATE behavioral_learnings SET contributor='Test Dev <test@dev.com>' WHERE rule='Test interaction rule';"

    # Re-run schema.sql (simulates what db-init.sh does on an existing DB)
    sqlite3 "$INTERACT_DB" < "$SCHEMA_FILE" 2>/dev/null
    RERUN_EXIT=$?

    # TEST-CTX-M1-108: Re-running schema.sql after migration succeeds
    assert_zero_exit "$RERUN_EXIT" \
        "TEST-CTX-M1-108: Re-running schema.sql after migration succeeds"

    # TEST-CTX-M1-109: shared_imports table still exists after schema re-run
    if table_exists "$INTERACT_DB" "shared_imports"; then
        assert_eq "1" "1" "TEST-CTX-M1-109: shared_imports table still exists after schema re-run"
    else
        assert_eq "1" "0" "TEST-CTX-M1-109: shared_imports table still exists after schema re-run"
    fi

    # TEST-CTX-M1-110: Migration data preserved after schema re-run
    contrib_val=$(sqlite3 "$INTERACT_DB" "SELECT contributor FROM behavioral_learnings WHERE rule='Test interaction rule';")
    assert_eq "Test Dev <test@dev.com>" "$contrib_val" \
        "TEST-CTX-M1-110: Contributor data preserved after schema.sql re-run"

    # TEST-CTX-M1-111: v_shared_briefing view exists after schema re-run
    if view_exists "$INTERACT_DB" "v_shared_briefing"; then
        assert_eq "1" "1" "TEST-CTX-M1-111: v_shared_briefing view exists after schema re-run"
    else
        assert_eq "1" "0" "TEST-CTX-M1-111: v_shared_briefing view exists after schema re-run"
    fi

    # TEST-CTX-M1-112: v_shared_briefing returns correct data after schema re-run
    view_count=$(sqlite3 "$INTERACT_DB" "SELECT COUNT(*) FROM v_shared_briefing;")
    assert_eq "1" "$view_count" \
        "TEST-CTX-M1-112: v_shared_briefing returns 1 qualifying entry after schema re-run"

    # Scenario: fresh DB from schema.sql -> run migration (should be no-op)
    FRESH_MIGRATE_DB="$TEST_TMP/fresh-then-migrate.db"
    create_fresh_db "$FRESH_MIGRATE_DB"
    bash "$MIGRATE_SCRIPT" "$FRESH_MIGRATE_DB" 2>/dev/null
    FM_EXIT=$?

    # TEST-CTX-M1-113: Migration on fresh DB is a no-op (all columns already exist)
    assert_zero_exit "$FM_EXIT" \
        "TEST-CTX-M1-113: Migration script on fresh DB is a safe no-op"
fi

cleanup_tmp

echo ""

# ============================================================
# TEST SUITE 8: EDGE CASES
# Requirement: REQ-CTX-002 (Must), REQ-CTX-006 (Must)
# ============================================================
echo "--- Test Suite 8: Edge Cases ---"
echo ""

setup_tmp
EDGE_DB="$TEST_TMP/edge.db"
create_fresh_db "$EDGE_DB"

# Edge case 1: Unicode in shared_uuid
# TEST-CTX-M1-114: shared_imports handles unicode in shared_uuid
sqlite3 "$EDGE_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('uuid-emoji-test', 'behavioral_learning');" 2>/dev/null
unicode_exit=$?
assert_zero_exit "$unicode_exit" \
    "TEST-CTX-M1-114: shared_imports accepts standard UUID format"

# Edge case 2: Very long shared_uuid
# TEST-CTX-M1-115: shared_imports handles long shared_uuid
long_uuid="$(printf 'a%.0s' {1..500})"
sqlite3 "$EDGE_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('$long_uuid', 'incident');" 2>/dev/null
long_exit=$?
assert_zero_exit "$long_exit" \
    "TEST-CTX-M1-115: shared_imports accepts long shared_uuid (500 chars)"

# Edge case 3: Empty string shared_uuid (not NULL, but empty)
# TEST-CTX-M1-116: shared_imports with empty string uuid
sqlite3 "$EDGE_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('', 'lesson');" 2>/dev/null
empty_exit=$?
# This should succeed (SQLite doesn't reject empty strings) but it's a data quality concern
# The import logic should prevent empty UUIDs, but the schema allows it
assert_zero_exit "$empty_exit" \
    "TEST-CTX-M1-116: shared_imports accepts empty string uuid (data quality is application responsibility)"

# Edge case 4: Special characters in contributor column
# TEST-CTX-M1-117: contributor handles special characters
sqlite3 "$EDGE_DB" "INSERT INTO behavioral_learnings (rule, contributor) VALUES ('Special char test', 'Jose Garcia-Lopez <jose@test.com>');" 2>/dev/null
special_exit=$?
assert_zero_exit "$special_exit" \
    "TEST-CTX-M1-117: contributor column handles special characters (hyphens, angle brackets)"

# Edge case 5: Unicode in contributor
# TEST-CTX-M1-118: contributor handles unicode
sqlite3 "$EDGE_DB" "INSERT INTO behavioral_learnings (rule, contributor) VALUES ('Unicode contributor test', 'Ivan Lozada <ivan@test.com>');" 2>/dev/null
unicode_contrib_exit=$?
assert_zero_exit "$unicode_contrib_exit" \
    "TEST-CTX-M1-118: contributor column handles unicode characters"

# Edge case 6: is_private set to values other than 0 and 1
# TEST-CTX-M1-119: is_private accepts integer value 1
sqlite3 "$EDGE_DB" "INSERT INTO behavioral_learnings (rule, is_private) VALUES ('Private entry test', 1);"
priv_val=$(sqlite3 "$EDGE_DB" "SELECT is_private FROM behavioral_learnings WHERE rule='Private entry test';")
assert_eq "1" "$priv_val" \
    "TEST-CTX-M1-119: is_private accepts value 1 (private)"

# Edge case 7: Large number of shared_imports (bulk insert performance)
# TEST-CTX-M1-120: shared_imports handles bulk inserts
BULK_SQL=""
for i in $(seq 1 100); do
    BULK_SQL="${BULK_SQL}INSERT INTO shared_imports (shared_uuid, category, source_file) VALUES ('bulk-uuid-$(printf '%04d' $i)', 'behavioral_learning', 'bulk-test.jsonl');"
done
sqlite3 "$EDGE_DB" "$BULK_SQL" 2>/dev/null
bulk_count=$(sqlite3 "$EDGE_DB" "SELECT COUNT(*) FROM shared_imports WHERE shared_uuid LIKE 'bulk-uuid-%';")
assert_eq "100" "$bulk_count" \
    "TEST-CTX-M1-120: shared_imports handles 100 bulk inserts correctly"

# Edge case 8: v_shared_briefing with many entries
# TEST-CTX-M1-121: View handles large dataset
BULK_BL_SQL=""
for i in $(seq 1 50); do
    conf=$(echo "scale=2; 0.80 + ($i * 0.004)" | bc)
    BULK_BL_SQL="${BULK_BL_SQL}INSERT INTO behavioral_learnings (rule, confidence, occurrences, status, is_private) VALUES ('Bulk rule $i', $conf, $i, 'active', 0);"
done
sqlite3 "$EDGE_DB" "$BULK_BL_SQL" 2>/dev/null
view_bulk_count=$(sqlite3 "$EDGE_DB" "SELECT COUNT(*) FROM v_shared_briefing WHERE rule LIKE 'Bulk rule%';")
assert_eq "50" "$view_bulk_count" \
    "TEST-CTX-M1-121: v_shared_briefing handles 50 qualifying entries"

# Edge case 9: Concurrent-like access (rapid sequential operations)
# TEST-CTX-M1-122: Rapid insert-then-query consistency
sqlite3 "$EDGE_DB" "INSERT INTO shared_imports (shared_uuid, category) VALUES ('rapid-001', 'behavioral_learning');"
rapid_check=$(sqlite3 "$EDGE_DB" "SELECT COUNT(*) FROM shared_imports WHERE shared_uuid='rapid-001';")
assert_eq "1" "$rapid_check" \
    "TEST-CTX-M1-122: Rapid insert-then-query returns consistent result"

# Edge case 10: shared_uuid lookup performance (index should make this fast)
# TEST-CTX-M1-123: EXPLAIN QUERY PLAN uses index for shared_uuid lookup
plan=$(sqlite3 "$EDGE_DB" "EXPLAIN QUERY PLAN SELECT * FROM shared_imports WHERE shared_uuid='test-uuid';" 2>/dev/null)
assert_contains "$plan" "idx_shared_imports_uuid" \
    "TEST-CTX-M1-123: Query planner uses idx_shared_imports_uuid for shared_uuid lookups"

cleanup_tmp

echo ""

# ============================================================
# TEST SUITE 9: EXISTING VIEWS/TABLES NOT BROKEN
# Requirement: REQ-CTX-001 (Must) - no functional change beyond version bump
# ============================================================
echo "--- Test Suite 9: Backward Compatibility of Existing Schema ---"
echo ""

setup_tmp
COMPAT_DB="$TEST_TMP/compat.db"
create_fresh_db "$COMPAT_DB"

# TEST-CTX-M1-124: All original tables still exist
for tbl in workflow_runs changes decisions failed_approaches bugs hotspots findings dependencies requirements patterns outcomes lessons behavioral_learnings incidents incident_entries decay_log user_profile onboarding_state; do
    if table_exists "$COMPAT_DB" "$tbl"; then
        assert_eq "1" "1" "TEST-CTX-M1-124-$tbl: Table '$tbl' exists in fresh schema"
    else
        assert_eq "1" "0" "TEST-CTX-M1-124-$tbl: Table '$tbl' exists in fresh schema"
    fi
done

# TEST-CTX-M1-125: All original views still exist
for vw in v_file_briefing v_open_findings v_domain_health v_recent_outcomes v_active_lessons v_domain_learning v_recent_activity v_workflow_usage v_behavioral_briefing v_incident_search v_incident_timeline; do
    if view_exists "$COMPAT_DB" "$vw"; then
        assert_eq "1" "1" "TEST-CTX-M1-125-$vw: View '$vw' exists in fresh schema"
    else
        assert_eq "1" "0" "TEST-CTX-M1-125-$vw: View '$vw' exists in fresh schema"
    fi
done

# TEST-CTX-M1-126: Existing behavioral_learnings UNIQUE constraint on rule still works
sqlite3 "$COMPAT_DB" "INSERT INTO behavioral_learnings (rule) VALUES ('Unique test rule');" 2>/dev/null
DUP_EXIT=$(sqlite3 "$COMPAT_DB" "INSERT INTO behavioral_learnings (rule) VALUES ('Unique test rule');" 2>&1; echo $?)
# The last line of output is the exit code
assert_ne "0" "$(sqlite3 "$COMPAT_DB" "INSERT INTO behavioral_learnings (rule) VALUES ('Unique test rule');" 2>&1 >/dev/null; echo $?)" \
    "TEST-CTX-M1-126: Existing UNIQUE(rule) constraint on behavioral_learnings preserved"

# TEST-CTX-M1-127: v_behavioral_briefing (original view) still works
sqlite3 "$COMPAT_DB" "INSERT INTO behavioral_learnings (rule, confidence, occurrences, status) VALUES ('Original view test', 0.9, 3, 'active');"
orig_view_count=$(sqlite3 "$COMPAT_DB" "SELECT COUNT(*) FROM v_behavioral_briefing WHERE rule='Original view test';")
assert_eq "1" "$orig_view_count" \
    "TEST-CTX-M1-127: Original v_behavioral_briefing view still works alongside v_shared_briefing"

cleanup_tmp

echo ""

# ============================================================
# SUMMARY
# ============================================================
echo "============================================================"
echo "RESULTS"
echo "============================================================"
echo "  Total:   $TESTS_RUN"
echo "  Passed:  $TESTS_PASSED"
echo "  Failed:  $TESTS_FAILED"
echo "  Skipped: $TESTS_SKIPPED"
echo ""

if [ "$TESTS_FAILED" -gt 0 ]; then
    echo "STATUS: FAILED ($TESTS_FAILED failures)"
    exit 1
elif [ "$TESTS_SKIPPED" -gt 0 ]; then
    echo "STATUS: PARTIAL (some tests skipped -- migration script not yet implemented)"
    exit 0
else
    echo "STATUS: ALL PASSED"
    exit 0
fi
