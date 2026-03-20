#!/bin/bash
# test-cortex-m10-middleware.sh
#
# Tests for OMEGA Cortex Milestone M10: Middleware + Offline Resilience
# Covers: REQ-CTX-045 (middleware pipeline), REQ-CTX-046 (real-time import),
#          REQ-CTX-047 (offline-first), REQ-CTX-048 (backend migration)
#
# These tests validate:
# - MIDDLEWARE section in sync-adapters.md
# - Format transformation, batching, retry, conflict pre-check documentation
# - Offline cache (.pending-exports.jsonl) documentation
# - Real-time import for cloud/self-hosted backends documentation
# - Offline-first resilience documentation
# - Backend migration command concept documentation
# - cortex_sync_state table in schema.sql
# - migrate-1.6.0.sh idempotent migration script
#
# Usage:
#   bash tests/test-cortex-m10-middleware.sh
#   bash tests/test-cortex-m10-middleware.sh --verbose
#
# Dependencies: bash, grep, sqlite3

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

assert_contains_regex() {
    local haystack="$1"
    local pattern="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -qE "$pattern"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Pattern not matched: $pattern"
        if [ "$VERBOSE" = true ]; then
            echo "    Haystack: $(echo "$haystack" | head -20)"
        fi
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

# ============================================================
# RESOLVE PROJECT ROOT
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SYNC_ADAPTERS="$PROJECT_ROOT/core/protocols/sync-adapters.md"
SCHEMA_SQL="$PROJECT_ROOT/core/db/schema.sql"
MIGRATE_SCRIPT="$PROJECT_ROOT/core/db/migrate-1.6.0.sh"

echo "============================================================"
echo "OMEGA Cortex M10: Middleware + Offline Resilience Tests"
echo "============================================================"
echo "  Project root: $PROJECT_ROOT"
echo "  Sync adapters protocol: $SYNC_ADAPTERS"
echo "  Schema SQL: $SCHEMA_SQL"
echo "  Migration script: $MIGRATE_SCRIPT"
echo ""

# Read file contents
SYNC_CONTENT=""
if [ -f "$SYNC_ADAPTERS" ]; then
    SYNC_CONTENT=$(cat "$SYNC_ADAPTERS")
fi

SCHEMA_CONTENT=""
if [ -f "$SCHEMA_SQL" ]; then
    SCHEMA_CONTENT=$(cat "$SCHEMA_SQL")
fi

MIGRATE_CONTENT=""
if [ -f "$MIGRATE_SCRIPT" ]; then
    MIGRATE_CONTENT=$(cat "$MIGRATE_SCRIPT")
fi

# ============================================================
# TEST SUITE 1: MIDDLEWARE Section Exists
# TEST-CTX-M10-001 through TEST-CTX-M10-003
# ============================================================
echo "--- MIDDLEWARE Section (TEST-CTX-M10-001 to TEST-CTX-M10-003) ---"

# TEST-CTX-M10-001: sync-adapters.md has MIDDLEWARE section
assert_contains "$SYNC_CONTENT" "## MIDDLEWARE" "TEST-CTX-M10-001 sync-adapters.md has MIDDLEWARE section"

# TEST-CTX-M10-002: @INDEX block references MIDDLEWARE section with line range
INDEX_BLOCK=$(head -20 "$SYNC_ADAPTERS" 2>/dev/null || echo "")
assert_contains_regex "$INDEX_BLOCK" "MIDDLEWARE.*[0-9]+-[0-9]+" "TEST-CTX-M10-002 @INDEX references MIDDLEWARE section with line range"

# TEST-CTX-M10-003: MIDDLEWARE section is substantial (documents the pipeline)
TESTS_RUN=$((TESTS_RUN + 1))
MIDDLEWARE_LINES=$(echo "$SYNC_CONTENT" | sed -n '/^## MIDDLEWARE/,/^## /p' | wc -l | tr -d ' ')
if [ "$MIDDLEWARE_LINES" -gt 30 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M10-003 MIDDLEWARE section is substantial ($MIDDLEWARE_LINES lines)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M10-003 MIDDLEWARE section too short ($MIDDLEWARE_LINES lines, expected >30)"
fi

echo ""

# ============================================================
# TEST SUITE 2: Middleware Pipeline Documentation
# TEST-CTX-M10-004 through TEST-CTX-M10-010
# ============================================================
echo "--- Middleware Pipeline (TEST-CTX-M10-004 to TEST-CTX-M10-010) ---"

# TEST-CTX-M10-004: Documents format transformation (memory.db row -> adapter entry format)
assert_contains_regex "$SYNC_CONTENT" "[Ff]ormat [Tt]ransform" "TEST-CTX-M10-004 Documents format transformation"

# TEST-CTX-M10-005: Documents batching with max 50 per batch for cloud
assert_contains_regex "$SYNC_CONTENT" "[Bb]atch.*50|50.*batch|max.*50.*batch|batch.*max.*50" "TEST-CTX-M10-005 Documents batching (max 50 per batch)"

# TEST-CTX-M10-006: Documents retry with exponential backoff (1s, 2s, 4s)
assert_contains_regex "$SYNC_CONTENT" "[Ee]xponential.*backoff|backoff.*1s.*2s.*4s|1s,.*2s,.*4s" "TEST-CTX-M10-006 Documents retry with exponential backoff"

# TEST-CTX-M10-007: Documents max 3 retries
assert_contains_regex "$SYNC_CONTENT" "[Mm]ax.*3.*retr|3.*retries|retry.*3" "TEST-CTX-M10-007 Documents max 3 retries"

# TEST-CTX-M10-008: Documents conflict pre-check (content_hash collision)
assert_contains_regex "$SYNC_CONTENT" "[Cc]onflict.*pre-check|content_hash.*collision|pre-check.*content_hash" "TEST-CTX-M10-008 Documents conflict pre-check"

# TEST-CTX-M10-009: Documents offline cache file (.pending-exports.jsonl)
assert_contains "$SYNC_CONTENT" ".pending-exports.jsonl" "TEST-CTX-M10-009 Documents offline cache (.pending-exports.jsonl)"

# TEST-CTX-M10-010: Documents pending flush (flush pending exports before new ones)
assert_contains_regex "$SYNC_CONTENT" "[Pp]ending.*flush|[Ff]lush.*pending" "TEST-CTX-M10-010 Documents pending flush behavior"

echo ""

# ============================================================
# TEST SUITE 3: Middleware Pipeline Flow Diagram
# TEST-CTX-M10-011
# ============================================================
echo "--- Pipeline Flow (TEST-CTX-M10-011) ---"

# TEST-CTX-M10-011: Documents the pipeline flow (Curator -> Middleware -> Adapter)
assert_contains_regex "$SYNC_CONTENT" "Curator.*Adapter|Format.*Batch.*Conflict|Curator.*Output.*Format" "TEST-CTX-M10-011 Documents pipeline flow (Curator -> Middleware -> Adapter)"

echo ""

# ============================================================
# TEST SUITE 4: Real-Time Import Documentation
# TEST-CTX-M10-012 through TEST-CTX-M10-017
# ============================================================
echo "--- Real-Time Import (TEST-CTX-M10-012 to TEST-CTX-M10-017) ---"

# TEST-CTX-M10-012: Documents cortex-config.json backend detection for import
assert_contains_regex "$SYNC_CONTENT" "cortex-config.json.*backend|backend.*detect|briefing.*cortex-config" "TEST-CTX-M10-012 Documents cortex-config.json backend detection"

# TEST-CTX-M10-013: Documents HTTP pull for cloud/self-hosted backends
assert_contains_regex "$SYNC_CONTENT" "HTTP.*pull|curl.*since|HTTP.*import" "TEST-CTX-M10-013 Documents HTTP pull for cloud backends"

# TEST-CTX-M10-014: Documents last_sync_timestamp tracking
assert_contains "$SYNC_CONTENT" "last_sync_timestamp" "TEST-CTX-M10-014 Documents last_sync_timestamp tracking"

# TEST-CTX-M10-015: Documents 5-second timeout for HTTP calls
assert_contains_regex "$SYNC_CONTENT" "5.*second.*timeout|timeout.*5|5s.*timeout" "TEST-CTX-M10-015 Documents 5-second timeout"

# TEST-CTX-M10-016: Documents fallback chain (HTTP -> files -> skip)
assert_contains_regex "$SYNC_CONTENT" "[Ff]allback.*chain|HTTP.*fall.*back|fallback.*skip" "TEST-CTX-M10-016 Documents fallback chain"

# TEST-CTX-M10-017: Documents cortex_sync_state table for tracking
assert_contains "$SYNC_CONTENT" "cortex_sync_state" "TEST-CTX-M10-017 Documents cortex_sync_state table"

echo ""

# ============================================================
# TEST SUITE 5: Offline-First Resilience Documentation
# TEST-CTX-M10-018 through TEST-CTX-M10-023
# ============================================================
echo "--- Offline-First Resilience (TEST-CTX-M10-018 to TEST-CTX-M10-023) ---"

# TEST-CTX-M10-018: Documents core invariant (local memory.db always functional)
assert_contains_regex "$SYNC_CONTENT" "local.*memory.db.*always|memory.db.*always.*functional|[Cc]ore.*invariant.*local" "TEST-CTX-M10-018 Documents core invariant (local always works)"

# TEST-CTX-M10-019: Documents git-jsonl is inherently offline-first
assert_contains_regex "$SYNC_CONTENT" "[Gg]it.*JSONL.*offline|inherently.*offline|offline.*by.*design" "TEST-CTX-M10-019 Documents git-jsonl inherently offline-first"

# TEST-CTX-M10-020: Documents pending exports queue for cloud/self-hosted offline
assert_contains_regex "$SYNC_CONTENT" "queue.*export|export.*queue|pending.*offline" "TEST-CTX-M10-020 Documents pending exports queue"

# TEST-CTX-M10-021: Documents graceful degradation message
assert_contains_regex "$SYNC_CONTENT" "[Uu]sing local knowledge only|local.*knowledge.*only|backend unavailable" "TEST-CTX-M10-021 Documents graceful degradation message"

# TEST-CTX-M10-022: Documents "never error, never block" principle
assert_contains_regex "$SYNC_CONTENT" "[Nn]ever error.*never block|[Nn]ever.*block.*never.*degrade|[Nn]ever.*error.*block" "TEST-CTX-M10-022 Documents never error, never block principle"

# TEST-CTX-M10-023: Documents connectivity-based flush on next session
assert_contains_regex "$SYNC_CONTENT" "next.*session.*connectivity|connectivity.*returns|connectivity.*flush" "TEST-CTX-M10-023 Documents connectivity-based flush"

echo ""

# ============================================================
# TEST SUITE 6: Backend Migration Documentation
# TEST-CTX-M10-024 through TEST-CTX-M10-028
# ============================================================
echo "--- Backend Migration (TEST-CTX-M10-024 to TEST-CTX-M10-028) ---"

# TEST-CTX-M10-024: Documents /omega:cortex-migrate command concept
assert_contains "$SYNC_CONTENT" "cortex-migrate" "TEST-CTX-M10-024 Documents cortex-migrate command"

# TEST-CTX-M10-025: Documents --from and --to flags
assert_contains "$SYNC_CONTENT" "--from" "TEST-CTX-M10-025a Documents --from flag"
assert_contains "$SYNC_CONTENT" "--to" "TEST-CTX-M10-025b Documents --to flag"

# TEST-CTX-M10-026: Documents source -> target flow (import from source, export to target)
assert_contains_regex "$SYNC_CONTENT" "import.*source|source.*import.*target.*export|source.*target" "TEST-CTX-M10-026 Documents source -> target flow"

# TEST-CTX-M10-027: Documents non-destructive behavior (source preserved)
assert_contains_regex "$SYNC_CONTENT" "[Nn]on-destructive|source.*preserved|source.*data.*preserved" "TEST-CTX-M10-027 Documents non-destructive behavior"

# TEST-CTX-M10-028: Documents completeness validation (count comparison)
assert_contains_regex "$SYNC_CONTENT" "count.*comparison|[Vv]alidate.*completeness|completeness.*valid" "TEST-CTX-M10-028 Documents completeness validation"

echo ""

# ============================================================
# TEST SUITE 7: Schema -- cortex_sync_state Table
# TEST-CTX-M10-029 through TEST-CTX-M10-034
# ============================================================
echo "--- Schema: cortex_sync_state (TEST-CTX-M10-029 to TEST-CTX-M10-034) ---"

# TEST-CTX-M10-029: cortex_sync_state table defined in schema.sql
assert_contains "$SCHEMA_CONTENT" "cortex_sync_state" "TEST-CTX-M10-029 cortex_sync_state table defined in schema.sql"

# TEST-CTX-M10-030: Has backend column
assert_contains_regex "$SCHEMA_CONTENT" "cortex_sync_state" "TEST-CTX-M10-030-prereq cortex_sync_state exists"
SYNC_TABLE_DDL=$(echo "$SCHEMA_CONTENT" | sed -n '/CREATE TABLE IF NOT EXISTS cortex_sync_state/,/);/p')
assert_contains "$SYNC_TABLE_DDL" "backend TEXT" "TEST-CTX-M10-030 cortex_sync_state has backend column"

# TEST-CTX-M10-031: Has last_sync_at column
assert_contains "$SYNC_TABLE_DDL" "last_sync_at" "TEST-CTX-M10-031 cortex_sync_state has last_sync_at column"

# TEST-CTX-M10-032: Has last_export_at column
assert_contains "$SYNC_TABLE_DDL" "last_export_at" "TEST-CTX-M10-032 cortex_sync_state has last_export_at column"

# TEST-CTX-M10-033: Has pending_count column
assert_contains "$SYNC_TABLE_DDL" "pending_count" "TEST-CTX-M10-033 cortex_sync_state has pending_count column"

# TEST-CTX-M10-034: Uses CREATE TABLE IF NOT EXISTS
assert_contains "$SCHEMA_CONTENT" "CREATE TABLE IF NOT EXISTS cortex_sync_state" "TEST-CTX-M10-034 Uses CREATE TABLE IF NOT EXISTS for cortex_sync_state"

echo ""

# ============================================================
# TEST SUITE 8: Schema -- Functional SQLite Tests
# TEST-CTX-M10-035 through TEST-CTX-M10-038
# ============================================================
echo "--- Schema: SQLite Functional (TEST-CTX-M10-035 to TEST-CTX-M10-038) ---"

if ! command -v sqlite3 &>/dev/null; then
    echo "  SKIP: sqlite3 not available -- skipping functional schema tests"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 4))
else
    # Create temp DB from schema.sql
    TMPDB=$(mktemp /tmp/omega-m10-test-XXXXXX.db)
    trap "rm -f $TMPDB" EXIT

    sqlite3 "$TMPDB" < "$SCHEMA_SQL" 2>/dev/null

    # TEST-CTX-M10-035: cortex_sync_state table exists in fresh DB
    TABLE_EXISTS=$(sqlite3 "$TMPDB" "SELECT name FROM sqlite_master WHERE type='table' AND name='cortex_sync_state';" 2>/dev/null)
    assert_eq "cortex_sync_state" "$TABLE_EXISTS" "TEST-CTX-M10-035 cortex_sync_state table exists in fresh DB"

    # TEST-CTX-M10-036: Can insert a row with all expected columns
    TESTS_RUN=$((TESTS_RUN + 1))
    if sqlite3 "$TMPDB" "INSERT INTO cortex_sync_state (backend, last_sync_at, last_export_at, pending_count) VALUES ('git-jsonl', '2026-03-20T12:00:00Z', '2026-03-20T12:00:00Z', 0);" 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M10-036 Can insert row with all expected columns"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M10-036 Insert into cortex_sync_state failed"
    fi

    # TEST-CTX-M10-037: Has updated_at column with default
    UPDATED_AT=$(sqlite3 "$TMPDB" "SELECT updated_at FROM cortex_sync_state WHERE id=1;" 2>/dev/null)
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -n "$UPDATED_AT" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M10-037 updated_at column has default value ($UPDATED_AT)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M10-037 updated_at column missing or no default"
    fi

    # TEST-CTX-M10-038: pending_count defaults to 0
    PENDING=$(sqlite3 "$TMPDB" "INSERT INTO cortex_sync_state (backend) VALUES ('cloudflare-d1'); SELECT pending_count FROM cortex_sync_state WHERE id=2;" 2>/dev/null)
    assert_eq "0" "$PENDING" "TEST-CTX-M10-038 pending_count defaults to 0"

    rm -f "$TMPDB"
fi

echo ""

# ============================================================
# TEST SUITE 9: Migration Script
# TEST-CTX-M10-039 through TEST-CTX-M10-044
# ============================================================
echo "--- Migration Script (TEST-CTX-M10-039 to TEST-CTX-M10-044) ---"

# TEST-CTX-M10-039: migrate-1.6.0.sh exists
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$MIGRATE_SCRIPT" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M10-039 migrate-1.6.0.sh exists"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M10-039 migrate-1.6.0.sh does not exist at $MIGRATE_SCRIPT"
fi

# TEST-CTX-M10-040: Script is executable or has shebang
TESTS_RUN=$((TESTS_RUN + 1))
if head -1 "$MIGRATE_SCRIPT" 2>/dev/null | grep -q "#!/bin/bash"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M10-040 migrate-1.6.0.sh has bash shebang"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M10-040 migrate-1.6.0.sh missing bash shebang"
fi

# TEST-CTX-M10-041: Migration creates cortex_sync_state table
assert_contains "$MIGRATE_CONTENT" "cortex_sync_state" "TEST-CTX-M10-041 Migration creates cortex_sync_state table"

# TEST-CTX-M10-042: Migration uses CREATE TABLE IF NOT EXISTS (idempotent)
assert_contains "$MIGRATE_CONTENT" "CREATE TABLE IF NOT EXISTS" "TEST-CTX-M10-042 Migration uses CREATE TABLE IF NOT EXISTS (idempotent)"

# TEST-CTX-M10-043: Migration handles missing DB gracefully
assert_contains_regex "$MIGRATE_CONTENT" "not found|not exist|skipping|skip" "TEST-CTX-M10-043 Migration handles missing DB gracefully"

# TEST-CTX-M10-044: Migration is idempotent (functional test)
if ! command -v sqlite3 &>/dev/null; then
    echo "  SKIP: sqlite3 not available -- skipping migration idempotency test"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
else
    TMPDB2=$(mktemp /tmp/omega-m10-migrate-XXXXXX.db)
    # Create a minimal existing DB (simulating pre-1.6.0)
    sqlite3 "$TMPDB2" "CREATE TABLE IF NOT EXISTS workflow_runs (id INTEGER PRIMARY KEY);"

    # Run migration twice
    TESTS_RUN=$((TESTS_RUN + 1))
    bash "$MIGRATE_SCRIPT" "$TMPDB2" >/dev/null 2>&1
    bash "$MIGRATE_SCRIPT" "$TMPDB2" >/dev/null 2>&1
    MIGRATE_TABLE=$(sqlite3 "$TMPDB2" "SELECT name FROM sqlite_master WHERE type='table' AND name='cortex_sync_state';" 2>/dev/null)
    if [ "$MIGRATE_TABLE" = "cortex_sync_state" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M10-044 Migration is idempotent (runs twice without error)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M10-044 Migration idempotency failed"
    fi
    rm -f "$TMPDB2"
fi

echo ""

# ============================================================
# TEST SUITE 10: Schema Version
# TEST-CTX-M10-045
# ============================================================
echo "--- Schema Version (TEST-CTX-M10-045) ---"

# TEST-CTX-M10-045: Schema version updated to 1.6.0
assert_contains_regex "$SCHEMA_CONTENT" "Version:.*1\.6\.0" "TEST-CTX-M10-045 Schema version updated to 1.6.0"

echo ""

# ============================================================
# TEST SUITE 11: M8/M9 Regression
# TEST-CTX-M10-046 through TEST-CTX-M10-051
# ============================================================
echo "--- M8/M9 Regression (TEST-CTX-M10-046 to TEST-CTX-M10-051) ---"

# TEST-CTX-M10-046: sync-adapters.md still has @INDEX block
assert_contains "$INDEX_BLOCK" "@INDEX" "TEST-CTX-M10-046 sync-adapters.md @INDEX block still present"

# TEST-CTX-M10-047: INTERFACE section still present
assert_contains "$SYNC_CONTENT" "## INTERFACE" "TEST-CTX-M10-047 INTERFACE section still present"

# TEST-CTX-M10-048: GIT-JSONL-ADAPTER section still present
assert_contains "$SYNC_CONTENT" "## GIT-JSONL-ADAPTER" "TEST-CTX-M10-048 GIT-JSONL-ADAPTER section still present"

# TEST-CTX-M10-049: CLOUD-ADAPTER section still present
assert_contains "$SYNC_CONTENT" "## CLOUD-ADAPTER" "TEST-CTX-M10-049 CLOUD-ADAPTER section still present"

# TEST-CTX-M10-050: CONFIGURATION section still present
assert_contains "$SYNC_CONTENT" "## CONFIGURATION" "TEST-CTX-M10-050 CONFIGURATION section still present"

# TEST-CTX-M10-051: ERROR-HANDLING section still present
assert_contains "$SYNC_CONTENT" "## ERROR-HANDLING" "TEST-CTX-M10-051 ERROR-HANDLING section still present"

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
    echo "STATUS: PARTIAL (some tests skipped -- code not yet implemented)"
    exit 0
else
    echo "STATUS: ALL PASSED"
    exit 0
fi
