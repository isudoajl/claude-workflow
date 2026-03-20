#!/bin/bash
# test-cortex-m8-sync-adapters.sh
#
# Tests for OMEGA Cortex Milestone M8: Sync Adapter Abstraction + Git Adapter Refactor
# Covers: REQ-CTX-039 (Sync Adapter abstraction layer), REQ-CTX-040 (Git JSONL adapter)
#
# These tests validate:
# - core/protocols/sync-adapters.md structure and content
# - Adapter interface contract (export, import, status, health)
# - Configuration documentation (.omega/cortex-config.json)
# - Git JSONL adapter documentation
# - Curator adapter awareness
# - Deployment via setup.sh
#
# Usage:
#   bash tests/test-cortex-m8-sync-adapters.sh
#   bash tests/test-cortex-m8-sync-adapters.sh --verbose
#
# Dependencies: bash, grep

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

assert_lt() {
    local threshold="$1"
    local actual="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$actual" -lt "$threshold" ] 2>/dev/null; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Expected < $threshold, got: $actual"
    fi
}

# ============================================================
# RESOLVE PROJECT ROOT
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SYNC_ADAPTERS="$PROJECT_ROOT/core/protocols/sync-adapters.md"
CURATOR_AGENT="$PROJECT_ROOT/core/agents/curator.md"
SETUP_SCRIPT="$PROJECT_ROOT/scripts/setup.sh"

echo "============================================================"
echo "OMEGA Cortex M8: Sync Adapter Abstraction Tests"
echo "============================================================"
echo "  Project root: $PROJECT_ROOT"
echo "  Sync adapters protocol: $SYNC_ADAPTERS"
echo "  Curator agent: $CURATOR_AGENT"
echo ""

# ============================================================
# TEST SUITE 1: Protocol File Existence & Structure
# TEST-CTX-M8-001 through TEST-CTX-M8-007
# ============================================================
echo "--- Protocol File Structure (TEST-CTX-M8-001 to TEST-CTX-M8-007) ---"

# TEST-CTX-M8-001: sync-adapters.md exists
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$SYNC_ADAPTERS" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M8-001 sync-adapters.md exists"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M8-001 sync-adapters.md does not exist at $SYNC_ADAPTERS"
fi

# Read the file content for remaining tests
SYNC_CONTENT=""
if [ -f "$SYNC_ADAPTERS" ]; then
    SYNC_CONTENT=$(cat "$SYNC_ADAPTERS")
fi

# TEST-CTX-M8-002: Has @INDEX block in first 15 lines
INDEX_BLOCK=$(head -15 "$SYNC_ADAPTERS" 2>/dev/null || echo "")
assert_contains "$INDEX_BLOCK" "@INDEX" "TEST-CTX-M8-002 @INDEX block present in first 15 lines"

# TEST-CTX-M8-003: Has INTERFACE section
assert_contains "$SYNC_CONTENT" "## INTERFACE" "TEST-CTX-M8-003 INTERFACE section exists"

# TEST-CTX-M8-004: Has GIT-JSONL-ADAPTER section
assert_contains "$SYNC_CONTENT" "## GIT-JSONL-ADAPTER" "TEST-CTX-M8-004 GIT-JSONL-ADAPTER section exists"

# TEST-CTX-M8-005: Has CONFIGURATION section
assert_contains "$SYNC_CONTENT" "## CONFIGURATION" "TEST-CTX-M8-005 CONFIGURATION section exists"

# TEST-CTX-M8-006: Has ERROR-HANDLING section
assert_contains "$SYNC_CONTENT" "## ERROR-HANDLING" "TEST-CTX-M8-006 ERROR-HANDLING section exists"

# TEST-CTX-M8-007: Total file under 300 lines
if [ -f "$SYNC_ADAPTERS" ]; then
    LINE_COUNT=$(wc -l < "$SYNC_ADAPTERS" | tr -d ' ')
    assert_lt 300 "$LINE_COUNT" "TEST-CTX-M8-007 sync-adapters.md under 300 lines (actual: $LINE_COUNT)"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M8-007 cannot count lines -- file missing"
fi

echo ""

# ============================================================
# TEST SUITE 2: Interface Contract
# TEST-CTX-M8-008 through TEST-CTX-M8-016
# ============================================================
echo "--- Interface Contract (TEST-CTX-M8-008 to TEST-CTX-M8-016) ---"

# TEST-CTX-M8-008: Documents export(entries) method
assert_contains_regex "$SYNC_CONTENT" "export.*entries" "TEST-CTX-M8-008 Documents export(entries) method"

# TEST-CTX-M8-009: Documents import(since) method
assert_contains_regex "$SYNC_CONTENT" "import.*since" "TEST-CTX-M8-009 Documents import(since) method"

# TEST-CTX-M8-010: Documents status() method
assert_contains "$SYNC_CONTENT" "status()" "TEST-CTX-M8-010 Documents status() method"

# TEST-CTX-M8-011: Documents health() method
assert_contains "$SYNC_CONTENT" "health()" "TEST-CTX-M8-011 Documents health() method"

# TEST-CTX-M8-012: Documents ExportResult return type
assert_contains "$SYNC_CONTENT" "ExportResult" "TEST-CTX-M8-012 Documents ExportResult return type"

# TEST-CTX-M8-013: ExportResult includes exported count
assert_contains_regex "$SYNC_CONTENT" "exported.*int" "TEST-CTX-M8-013 ExportResult includes exported count"

# TEST-CTX-M8-014: ExportResult includes reinforced count
assert_contains_regex "$SYNC_CONTENT" "reinforced.*int" "TEST-CTX-M8-014 ExportResult includes reinforced count"

# TEST-CTX-M8-015: Documents BackendStats return type
assert_contains "$SYNC_CONTENT" "BackendStats" "TEST-CTX-M8-015 Documents BackendStats return type"

# TEST-CTX-M8-016: Documents HealthResult return type
assert_contains "$SYNC_CONTENT" "HealthResult" "TEST-CTX-M8-016 Documents HealthResult return type"

echo ""

# ============================================================
# TEST SUITE 3: Configuration Documentation
# TEST-CTX-M8-017 through TEST-CTX-M8-022
# ============================================================
echo "--- Configuration (TEST-CTX-M8-017 to TEST-CTX-M8-022) ---"

# TEST-CTX-M8-017: Documents backend field
assert_contains_regex "$SYNC_CONTENT" '"backend"' "TEST-CTX-M8-017 Documents backend field"

# TEST-CTX-M8-018: Documents git-jsonl as a backend value
assert_contains "$SYNC_CONTENT" "git-jsonl" "TEST-CTX-M8-018 Documents git-jsonl backend value"

# TEST-CTX-M8-019: Documents git-jsonl as default
assert_contains_regex "$SYNC_CONTENT" "default.*git-jsonl|git-jsonl.*default" "TEST-CTX-M8-019 Documents git-jsonl as default backend"

# TEST-CTX-M8-020: Documents zero config for git-jsonl
assert_contains_regex "$SYNC_CONTENT" "[Zz]ero.*(config|configuration)" "TEST-CTX-M8-020 Documents zero config for git-jsonl"

# TEST-CTX-M8-021: Documents cortex-config.json location
assert_contains "$SYNC_CONTENT" "cortex-config.json" "TEST-CTX-M8-021 Documents cortex-config.json"

# TEST-CTX-M8-022: Documents .omega/ as config directory
assert_contains "$SYNC_CONTENT" ".omega/cortex-config.json" "TEST-CTX-M8-022 Documents .omega/cortex-config.json location"

echo ""

# ============================================================
# TEST SUITE 4: Git JSONL Adapter Documentation
# TEST-CTX-M8-023 through TEST-CTX-M8-028
# ============================================================
echo "--- Git JSONL Adapter (TEST-CTX-M8-023 to TEST-CTX-M8-028) ---"

# TEST-CTX-M8-023: Git adapter documents export to .omega/shared/
assert_contains "$SYNC_CONTENT" ".omega/shared/" "TEST-CTX-M8-023 Git adapter references .omega/shared/ directory"

# TEST-CTX-M8-024: Git adapter documents JSONL file writes
assert_contains "$SYNC_CONTENT" "behavioral-learnings.jsonl" "TEST-CTX-M8-024 Git adapter documents behavioral-learnings.jsonl"

# TEST-CTX-M8-025: Git adapter documents import from shared files
assert_contains_regex "$SYNC_CONTENT" "import.*shared|shared.*import" "TEST-CTX-M8-025 Git adapter documents import from shared files"

# TEST-CTX-M8-026: Git adapter documents status counting entries
assert_contains_regex "$SYNC_CONTENT" "status.*count|count.*entries" "TEST-CTX-M8-026 Git adapter documents status counting entries"

# TEST-CTX-M8-027: Git adapter documents health check for directory
assert_contains_regex "$SYNC_CONTENT" "health.*directory|directory.*exist|writable" "TEST-CTX-M8-027 Git adapter documents health check for directory"

# TEST-CTX-M8-028: Git adapter documents content_hash deduplication
assert_contains "$SYNC_CONTENT" "content_hash" "TEST-CTX-M8-028 Git adapter documents content_hash deduplication"

echo ""

# ============================================================
# TEST SUITE 5: Error Handling
# TEST-CTX-M8-029 through TEST-CTX-M8-033
# ============================================================
echo "--- Error Handling (TEST-CTX-M8-029 to TEST-CTX-M8-033) ---"

# TEST-CTX-M8-029: Documents pending exports on failure
assert_contains "$SYNC_CONTENT" ".pending-exports.jsonl" "TEST-CTX-M8-029 Documents pending exports cache"

# TEST-CTX-M8-030: Documents graceful degradation
assert_contains_regex "$SYNC_CONTENT" "[Nn]ever crash|error-tolerant|[Dd]egrade gracefully" "TEST-CTX-M8-030 Documents error tolerance / graceful degradation"

# TEST-CTX-M8-031: Documents fallback to git-jsonl
assert_contains_regex "$SYNC_CONTENT" "fall.*back.*git-jsonl|fallback.*git-jsonl|git-jsonl.*fallback" "TEST-CTX-M8-031 Documents fallback to git-jsonl"

# TEST-CTX-M8-032: Documents failed import behavior
assert_contains_regex "$SYNC_CONTENT" "[Ff]ailed.*[Ii]mport|[Ii]mport.*fail" "TEST-CTX-M8-032 Documents failed import behavior"

# TEST-CTX-M8-033: Documents unhealthy backend handling
assert_contains_regex "$SYNC_CONTENT" "[Uu]nhealthy.*[Bb]ackend|[Bb]ackend.*unhealthy|healthy.*false" "TEST-CTX-M8-033 Documents unhealthy backend handling"

echo ""

# ============================================================
# TEST SUITE 6: @INDEX Completeness
# TEST-CTX-M8-034 through TEST-CTX-M8-039
# ============================================================
echo "--- @INDEX Completeness (TEST-CTX-M8-034 to TEST-CTX-M8-039) ---"

# TEST-CTX-M8-034: @INDEX references INTERFACE section
assert_contains "$INDEX_BLOCK" "INTERFACE" "TEST-CTX-M8-034 @INDEX references INTERFACE"

# TEST-CTX-M8-035: @INDEX references GIT-JSONL-ADAPTER section
assert_contains "$INDEX_BLOCK" "GIT-JSONL-ADAPTER" "TEST-CTX-M8-035 @INDEX references GIT-JSONL-ADAPTER"

# TEST-CTX-M8-036: @INDEX references CLOUD-ADAPTER section
assert_contains "$INDEX_BLOCK" "CLOUD-ADAPTER" "TEST-CTX-M8-036 @INDEX references CLOUD-ADAPTER"

# TEST-CTX-M8-037: @INDEX references SELF-HOSTED-ADAPTER section
assert_contains "$INDEX_BLOCK" "SELF-HOSTED-ADAPTER" "TEST-CTX-M8-037 @INDEX references SELF-HOSTED-ADAPTER"

# TEST-CTX-M8-038: @INDEX references CONFIGURATION section
assert_contains "$INDEX_BLOCK" "CONFIGURATION" "TEST-CTX-M8-038 @INDEX references CONFIGURATION"

# TEST-CTX-M8-039: @INDEX references ERROR-HANDLING section
assert_contains "$INDEX_BLOCK" "ERROR-HANDLING" "TEST-CTX-M8-039 @INDEX references ERROR-HANDLING"

echo ""

# ============================================================
# TEST SUITE 7: Curator Adapter Awareness
# TEST-CTX-M8-040 through TEST-CTX-M8-042
# ============================================================
echo "--- Curator Adapter Awareness (TEST-CTX-M8-040 to TEST-CTX-M8-042) ---"

CURATOR_CONTENT=""
if [ -f "$CURATOR_AGENT" ]; then
    CURATOR_CONTENT=$(cat "$CURATOR_AGENT")
fi

# TEST-CTX-M8-040: Curator mentions cortex-config.json
assert_contains "$CURATOR_CONTENT" "cortex-config.json" "TEST-CTX-M8-040 Curator mentions cortex-config.json"

# TEST-CTX-M8-041: Curator mentions adapter-agnostic
assert_contains_regex "$CURATOR_CONTENT" "adapter-agnostic|adapter.agnostic" "TEST-CTX-M8-041 Curator mentions adapter-agnostic"

# TEST-CTX-M8-042: Curator mentions backend selection
assert_contains_regex "$CURATOR_CONTENT" "[Bb]ackend.*[Ss]election|[Ss]elect.*backend|backend.*field" "TEST-CTX-M8-042 Curator mentions backend selection"

echo ""

# ============================================================
# TEST SUITE 8: Cloud & Self-Hosted Placeholder Sections
# TEST-CTX-M8-043 through TEST-CTX-M8-046
# ============================================================
echo "--- Placeholder Sections (TEST-CTX-M8-043 to TEST-CTX-M8-046) ---"

# TEST-CTX-M8-043: CLOUD-ADAPTER section exists
assert_contains "$SYNC_CONTENT" "## CLOUD-ADAPTER" "TEST-CTX-M8-043 CLOUD-ADAPTER section exists"

# TEST-CTX-M8-044: CLOUD-ADAPTER references M9
assert_contains_regex "$SYNC_CONTENT" "M9|Milestone.*9" "TEST-CTX-M8-044 CLOUD-ADAPTER references M9"

# TEST-CTX-M8-045: SELF-HOSTED-ADAPTER section exists
assert_contains "$SYNC_CONTENT" "## SELF-HOSTED-ADAPTER" "TEST-CTX-M8-045 SELF-HOSTED-ADAPTER section exists"

# TEST-CTX-M8-046: SELF-HOSTED-ADAPTER references M11
assert_contains_regex "$SYNC_CONTENT" "M11|Milestone.*11" "TEST-CTX-M8-046 SELF-HOSTED-ADAPTER references M11"

echo ""

# ============================================================
# TEST SUITE 9: Deployment via setup.sh
# TEST-CTX-M8-047
# ============================================================
echo "--- Deployment (TEST-CTX-M8-047) ---"

# TEST-CTX-M8-047: setup.sh deploys protocols from core/protocols/ to .claude/protocols/
# (sync-adapters.md will be deployed automatically because setup.sh copies all core/protocols/*.md)
SETUP_CONTENT=""
if [ -f "$SETUP_SCRIPT" ]; then
    SETUP_CONTENT=$(cat "$SETUP_SCRIPT")
fi
assert_contains "$SETUP_CONTENT" "core/protocols" "TEST-CTX-M8-047 setup.sh deploys from core/protocols/ directory"

echo ""

# ============================================================
# TEST SUITE 10: Backend Config Values
# TEST-CTX-M8-048 through TEST-CTX-M8-050
# ============================================================
echo "--- Backend Config Values (TEST-CTX-M8-048 to TEST-CTX-M8-050) ---"

# TEST-CTX-M8-048: Documents cloudflare-d1 backend
assert_contains "$SYNC_CONTENT" "cloudflare-d1" "TEST-CTX-M8-048 Documents cloudflare-d1 backend option"

# TEST-CTX-M8-049: Documents self-hosted backend
assert_contains "$SYNC_CONTENT" "self-hosted" "TEST-CTX-M8-049 Documents self-hosted backend option"

# TEST-CTX-M8-050: Documents API token via environment variable pattern
assert_contains_regex "$SYNC_CONTENT" "api_token_env|auth_token_env|_TOKEN" "TEST-CTX-M8-050 Documents API token via env var pattern"

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
