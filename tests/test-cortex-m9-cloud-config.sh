#!/bin/bash
# test-cortex-m9-cloud-config.sh
#
# Tests for OMEGA Cortex Milestone M9: Cloud Adapter + Config Command
# Covers: REQ-CTX-041 (D1 adapter), REQ-CTX-042 (Turso), REQ-CTX-044 (cortex-config command), REQ-CTX-049 (D1 provisioning)
#
# These tests validate:
# - CLOUD-ADAPTER section in sync-adapters.md has real D1 content (not placeholder)
# - D1 REST API endpoint, authentication, interface methods documented
# - D1 table schema documented
# - Turso adapter basics documented
# - Rate limiting and error handling documented
# - omega-cortex-config.md exists with proper structure
# - Config command documents backend selection, flags, security, health check
# - Deployment via setup.sh
#
# Usage:
#   bash tests/test-cortex-m9-cloud-config.sh
#   bash tests/test-cortex-m9-cloud-config.sh --verbose
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

# ============================================================
# RESOLVE PROJECT ROOT
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SYNC_ADAPTERS="$PROJECT_ROOT/core/protocols/sync-adapters.md"
CONFIG_CMD="$PROJECT_ROOT/core/commands/omega-cortex-config.md"
SETUP_SCRIPT="$PROJECT_ROOT/scripts/setup.sh"

echo "============================================================"
echo "OMEGA Cortex M9: Cloud Adapter + Config Command Tests"
echo "============================================================"
echo "  Project root: $PROJECT_ROOT"
echo "  Sync adapters protocol: $SYNC_ADAPTERS"
echo "  Config command: $CONFIG_CMD"
echo ""

# Read file contents
SYNC_CONTENT=""
if [ -f "$SYNC_ADAPTERS" ]; then
    SYNC_CONTENT=$(cat "$SYNC_ADAPTERS")
fi

CONFIG_CONTENT=""
if [ -f "$CONFIG_CMD" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_CMD")
fi

SETUP_CONTENT=""
if [ -f "$SETUP_SCRIPT" ]; then
    SETUP_CONTENT=$(cat "$SETUP_SCRIPT")
fi

# ============================================================
# TEST SUITE 1: Protocol CLOUD-ADAPTER Section -- D1 Content
# TEST-CTX-M9-001 through TEST-CTX-M9-010
# ============================================================
echo "--- CLOUD-ADAPTER D1 Content (TEST-CTX-M9-001 to TEST-CTX-M9-010) ---"

# TEST-CTX-M9-001: CLOUD-ADAPTER section has D1 content (not just placeholder)
# The placeholder from M8 said "This section will be expanded when M9 is implemented."
# After M9, it must have real content.
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SYNC_CONTENT" | grep -q "CLOUD-ADAPTER" && ! echo "$SYNC_CONTENT" | grep -q "will be expanded when M9"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M9-001 CLOUD-ADAPTER section has real content (placeholder removed)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M9-001 CLOUD-ADAPTER section still has placeholder text"
fi

# TEST-CTX-M9-002: Documents D1 REST API endpoint
assert_contains "$SYNC_CONTENT" "/client/v4/accounts/" "TEST-CTX-M9-002 Documents D1 REST API endpoint path"

# TEST-CTX-M9-003: Documents Bearer token authentication
assert_contains_regex "$SYNC_CONTENT" "[Bb]earer.*token|[Aa]uthentication.*[Bb]earer" "TEST-CTX-M9-003 Documents Bearer token authentication"

# TEST-CTX-M9-004: Documents OMEGA_CORTEX_CF_TOKEN env var
assert_contains "$SYNC_CONTENT" "OMEGA_CORTEX_CF_TOKEN" "TEST-CTX-M9-004 Documents OMEGA_CORTEX_CF_TOKEN env var"

# TEST-CTX-M9-005: Documents export for D1 (POST/INSERT)
assert_contains_regex "$SYNC_CONTENT" "export.*POST|POST.*INSERT|INSERT.*D1" "TEST-CTX-M9-005 Documents D1 export via POST/INSERT"

# TEST-CTX-M9-006: Documents import for D1 (SELECT with since filter)
assert_contains_regex "$SYNC_CONTENT" "import.*SELECT|SELECT.*created_at" "TEST-CTX-M9-006 Documents D1 import via SELECT"

# TEST-CTX-M9-007: Documents status for D1 (COUNT)
assert_contains_regex "$SYNC_CONTENT" "status.*COUNT|COUNT.*category" "TEST-CTX-M9-007 Documents D1 status via COUNT query"

# TEST-CTX-M9-008: Documents health for D1
assert_contains_regex "$SYNC_CONTENT" "health.*metadata|health.*200|health.*API" "TEST-CTX-M9-008 Documents D1 health check"

# TEST-CTX-M9-009: Documents rate limiting (batch INSERTs)
assert_contains_regex "$SYNC_CONTENT" "[Rr]ate.*limit|[Bb]atch.*INSERT|max.*50" "TEST-CTX-M9-009 Documents rate limiting for D1"

# TEST-CTX-M9-010: Documents error handling (HTTP 429, 5xx)
assert_contains_regex "$SYNC_CONTENT" "429|5xx|[Ee]xponential.*backoff|[Rr]etry" "TEST-CTX-M9-010 Documents D1 error handling (429/5xx/retry)"

echo ""

# ============================================================
# TEST SUITE 2: D1 Table Schema
# TEST-CTX-M9-011 through TEST-CTX-M9-014
# ============================================================
echo "--- D1 Table Schema (TEST-CTX-M9-011 to TEST-CTX-M9-014) ---"

# TEST-CTX-M9-011: Documents shared_behavioral_learnings table
assert_contains "$SYNC_CONTENT" "shared_behavioral_learnings" "TEST-CTX-M9-011 Documents shared_behavioral_learnings table"

# TEST-CTX-M9-012: Documents shared_incidents table
assert_contains "$SYNC_CONTENT" "shared_incidents" "TEST-CTX-M9-012 Documents shared_incidents table"

# TEST-CTX-M9-013: Documents shared_hotspots table
assert_contains "$SYNC_CONTENT" "shared_hotspots" "TEST-CTX-M9-013 Documents shared_hotspots table"

# TEST-CTX-M9-014: Documents D1 table schema columns (uuid, contributor, content_hash)
assert_contains_regex "$SYNC_CONTENT" "uuid.*contributor|contributor.*content_hash" "TEST-CTX-M9-014 Documents D1 table schema columns"

echo ""

# ============================================================
# TEST SUITE 3: Turso Adapter
# TEST-CTX-M9-015 through TEST-CTX-M9-017
# ============================================================
echo "--- Turso Adapter (TEST-CTX-M9-015 to TEST-CTX-M9-017) ---"

# TEST-CTX-M9-015: Documents Turso adapter
assert_contains_regex "$SYNC_CONTENT" "[Tt]urso" "TEST-CTX-M9-015 Documents Turso adapter"

# TEST-CTX-M9-016: Documents Turso URL format (libsql://)
assert_contains "$SYNC_CONTENT" "libsql://" "TEST-CTX-M9-016 Documents Turso URL format (libsql://)"

# TEST-CTX-M9-017: Documents Turso auth token env var
assert_contains "$SYNC_CONTENT" "OMEGA_CORTEX_TURSO_TOKEN" "TEST-CTX-M9-017 Documents Turso auth token env var"

echo ""

# ============================================================
# TEST SUITE 4: Config Command File Existence & Structure
# TEST-CTX-M9-018 through TEST-CTX-M9-022
# ============================================================
echo "--- Config Command Structure (TEST-CTX-M9-018 to TEST-CTX-M9-022) ---"

# TEST-CTX-M9-018: omega-cortex-config.md exists
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$CONFIG_CMD" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M9-018 omega-cortex-config.md exists"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M9-018 omega-cortex-config.md does not exist at $CONFIG_CMD"
fi

# TEST-CTX-M9-019: Has YAML frontmatter with name field
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CONFIG_CONTENT" | head -5 | grep -q "^---" && echo "$CONFIG_CONTENT" | grep -q "^name:"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M9-019 Has YAML frontmatter with name field"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M9-019 Missing YAML frontmatter or name field"
fi

# TEST-CTX-M9-020: Name field contains omega:cortex-config
assert_contains "$CONFIG_CONTENT" "omega:cortex-config" "TEST-CTX-M9-020 Name field contains omega:cortex-config"

# TEST-CTX-M9-021: Has description in frontmatter
assert_contains_regex "$CONFIG_CONTENT" "^description:" "TEST-CTX-M9-021 Has description in frontmatter"

# TEST-CTX-M9-022: Config command content is substantial (>50 lines)
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$CONFIG_CMD" ]; then
    CMD_LINES=$(wc -l < "$CONFIG_CMD" | tr -d ' ')
    if [ "$CMD_LINES" -gt 50 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M9-022 Config command is substantial ($CMD_LINES lines)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M9-022 Config command too short ($CMD_LINES lines, expected >50)"
    fi
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M9-022 Cannot count lines -- file missing"
fi

echo ""

# ============================================================
# TEST SUITE 5: Config Command -- Backend Selection Flow
# TEST-CTX-M9-023 through TEST-CTX-M9-028
# ============================================================
echo "--- Backend Selection Flow (TEST-CTX-M9-023 to TEST-CTX-M9-028) ---"

# TEST-CTX-M9-023: Documents git-jsonl backend option
assert_contains "$CONFIG_CONTENT" "git-jsonl" "TEST-CTX-M9-023 Documents git-jsonl backend option"

# TEST-CTX-M9-024: Documents cloudflare-d1 backend option
assert_contains "$CONFIG_CONTENT" "cloudflare-d1" "TEST-CTX-M9-024 Documents cloudflare-d1 backend option"

# TEST-CTX-M9-025: Documents turso backend option
assert_contains "$CONFIG_CONTENT" "turso" "TEST-CTX-M9-025 Documents turso backend option"

# TEST-CTX-M9-026: Documents self-hosted backend option
assert_contains "$CONFIG_CONTENT" "self-hosted" "TEST-CTX-M9-026 Documents self-hosted backend option"

# TEST-CTX-M9-027: Documents health check step
assert_contains_regex "$CONFIG_CONTENT" "[Hh]ealth.*check|[Vv]alidate.*connectivity|connectivity.*check" "TEST-CTX-M9-027 Documents health check step"

# TEST-CTX-M9-028: Documents cortex-config.json save location
assert_contains "$CONFIG_CONTENT" "cortex-config.json" "TEST-CTX-M9-028 Documents cortex-config.json save location"

echo ""

# ============================================================
# TEST SUITE 6: Config Command -- Flags
# TEST-CTX-M9-029 through TEST-CTX-M9-031
# ============================================================
echo "--- Config Command Flags (TEST-CTX-M9-029 to TEST-CTX-M9-031) ---"

# TEST-CTX-M9-029: Documents --show flag
assert_contains "$CONFIG_CONTENT" "--show" "TEST-CTX-M9-029 Documents --show flag"

# TEST-CTX-M9-030: Documents --reset flag
assert_contains "$CONFIG_CONTENT" "--reset" "TEST-CTX-M9-030 Documents --reset flag"

# TEST-CTX-M9-031: --show masks sensitive values
assert_contains_regex "$CONFIG_CONTENT" "[Mm]ask.*sensitive|[Mm]ask.*token|sensitive.*masked" "TEST-CTX-M9-031 --show masks sensitive values"

echo ""

# ============================================================
# TEST SUITE 7: Config Command -- Security
# TEST-CTX-M9-032 through TEST-CTX-M9-035
# ============================================================
echo "--- Config Command Security (TEST-CTX-M9-032 to TEST-CTX-M9-035) ---"

# TEST-CTX-M9-032: API tokens stored as env var names, not plaintext
assert_contains_regex "$CONFIG_CONTENT" "env.*var|environment.*variable|ENV.*VAR|_env" "TEST-CTX-M9-032 API tokens stored as env var names"

# TEST-CTX-M9-033: cortex-config.json is gitignored
assert_contains_regex "$CONFIG_CONTENT" "gitignore|gitignored" "TEST-CTX-M9-033 cortex-config.json is gitignored"

# TEST-CTX-M9-034: Documents TLS requirement
assert_contains_regex "$CONFIG_CONTENT" "TLS|HTTPS|tls|https" "TEST-CTX-M9-034 Documents TLS requirement"

# TEST-CTX-M9-035: Documents that tokens come from env vars not config
assert_contains_regex "$CONFIG_CONTENT" "[Nn][Ee][Vv][Ee][Rr].*stored.*config|[Nn][Ee][Vv][Ee][Rr].*actual.*token|[Nn]ot.*plaintext|env.*var.*name" "TEST-CTX-M9-035 Tokens come from env vars, never stored in config"

echo ""

# ============================================================
# TEST SUITE 8: Config Command -- Pipeline Tracking
# TEST-CTX-M9-036
# ============================================================
echo "--- Pipeline Tracking (TEST-CTX-M9-036) ---"

# TEST-CTX-M9-036: Creates workflow_runs entry
assert_contains "$CONFIG_CONTENT" "workflow_runs" "TEST-CTX-M9-036 Creates workflow_runs entry"

echo ""

# ============================================================
# TEST SUITE 9: D1 Schema Provisioning
# TEST-CTX-M9-037 through TEST-CTX-M9-039
# ============================================================
echo "--- D1 Schema Provisioning (TEST-CTX-M9-037 to TEST-CTX-M9-039) ---"

# TEST-CTX-M9-037: Config command documents D1 schema provisioning
assert_contains_regex "$CONFIG_CONTENT" "[Pp]rovision.*schema|[Ss]chema.*provision|CREATE TABLE" "TEST-CTX-M9-037 Documents D1 schema provisioning"

# TEST-CTX-M9-038: Provisioning is idempotent (CREATE TABLE IF NOT EXISTS)
assert_contains_regex "$CONFIG_CONTENT" "IF NOT EXISTS|[Ii]dempotent" "TEST-CTX-M9-038 D1 provisioning is idempotent"

# TEST-CTX-M9-039: Provisioning creates shared_behavioral_learnings table
assert_contains "$CONFIG_CONTENT" "shared_behavioral_learnings" "TEST-CTX-M9-039 Provisioning creates shared_behavioral_learnings table"

echo ""

# ============================================================
# TEST SUITE 10: Deployment via setup.sh
# TEST-CTX-M9-040
# ============================================================
echo "--- Deployment (TEST-CTX-M9-040) ---"

# TEST-CTX-M9-040: setup.sh deploys commands from core/commands/ to .claude/commands/
# omega-cortex-config.md is deployed automatically because setup.sh copies all core/commands/*.md
assert_contains "$SETUP_CONTENT" "core/commands" "TEST-CTX-M9-040 setup.sh deploys from core/commands/ directory"

echo ""

# ============================================================
# TEST SUITE 11: M8 Regression -- sync-adapters.md still valid
# TEST-CTX-M9-041 through TEST-CTX-M9-043
# ============================================================
echo "--- M8 Regression (TEST-CTX-M9-041 to TEST-CTX-M9-043) ---"

# TEST-CTX-M9-041: sync-adapters.md still has @INDEX block
INDEX_BLOCK=$(head -15 "$SYNC_ADAPTERS" 2>/dev/null || echo "")
assert_contains "$INDEX_BLOCK" "@INDEX" "TEST-CTX-M9-041 sync-adapters.md @INDEX block still present"

# TEST-CTX-M9-042: All required sections still present
assert_contains "$SYNC_CONTENT" "## INTERFACE" "TEST-CTX-M9-042a INTERFACE section still present"
assert_contains "$SYNC_CONTENT" "## GIT-JSONL-ADAPTER" "TEST-CTX-M9-042b GIT-JSONL-ADAPTER section still present"
assert_contains "$SYNC_CONTENT" "## CLOUD-ADAPTER" "TEST-CTX-M9-042c CLOUD-ADAPTER section still present"
assert_contains "$SYNC_CONTENT" "## SELF-HOSTED-ADAPTER" "TEST-CTX-M9-042d SELF-HOSTED-ADAPTER section still present"
assert_contains "$SYNC_CONTENT" "## CONFIGURATION" "TEST-CTX-M9-042e CONFIGURATION section still present"
assert_contains "$SYNC_CONTENT" "## ERROR-HANDLING" "TEST-CTX-M9-042f ERROR-HANDLING section still present"

# TEST-CTX-M9-043: Git JSONL adapter content not accidentally removed
assert_contains "$SYNC_CONTENT" ".omega/shared/" "TEST-CTX-M9-043 Git JSONL adapter content preserved"

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
