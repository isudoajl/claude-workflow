#!/bin/bash
# test-cortex-m11-bridge.sh
#
# Tests for OMEGA Cortex Milestone M11: Self-Hosted Bridge + Adapter
# Covers: REQ-CTX-043 (self-hosted adapter), REQ-CTX-050 (bridge server)
#
# These tests validate:
# - extensions/cortex-bridge/ directory structure and files
# - Cargo.toml with correct dependencies
# - All Rust source files exist with expected patterns
# - Dockerfile and docker-compose.yml exist
# - README.md exists with deployment documentation
# - sync-adapters.md SELF-HOSTED-ADAPTER section filled in
# - cargo check passes (if Rust toolchain available)
#
# Usage:
#   bash tests/test-cortex-m11-bridge.sh
#   bash tests/test-cortex-m11-bridge.sh --verbose
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

BRIDGE_DIR="$PROJECT_ROOT/extensions/cortex-bridge"
SYNC_ADAPTERS="$PROJECT_ROOT/core/protocols/sync-adapters.md"

echo "============================================================"
echo "OMEGA Cortex M11: Self-Hosted Bridge + Adapter Tests"
echo "============================================================"
echo "  Project root: $PROJECT_ROOT"
echo "  Bridge dir: $BRIDGE_DIR"
echo ""

# ============================================================
# TEST SUITE 1: Directory Structure & File Existence
# TEST-CTX-M11-001 through TEST-CTX-M11-009
# ============================================================
echo "--- Directory Structure (TEST-CTX-M11-001 to TEST-CTX-M11-009) ---"

# TEST-CTX-M11-001: extensions/cortex-bridge/ directory exists
TESTS_RUN=$((TESTS_RUN + 1))
if [ -d "$BRIDGE_DIR" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M11-001 extensions/cortex-bridge/ directory exists"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M11-001 extensions/cortex-bridge/ directory does not exist"
fi

# TEST-CTX-M11-002: Cargo.toml exists
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$BRIDGE_DIR/Cargo.toml" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M11-002 Cargo.toml exists"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M11-002 Cargo.toml does not exist"
fi

# TEST-CTX-M11-003: All source files exist
for srcfile in main.rs config.rs auth.rs routes.rs storage.rs models.rs lib.rs; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$BRIDGE_DIR/src/$srcfile" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M11-003 src/$srcfile exists"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M11-003 src/$srcfile does not exist"
    fi
done

# TEST-CTX-M11-004: Dockerfile exists
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$BRIDGE_DIR/Dockerfile" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M11-004 Dockerfile exists"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M11-004 Dockerfile does not exist"
fi

# TEST-CTX-M11-005: docker-compose.yml exists
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$BRIDGE_DIR/docker-compose.yml" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M11-005 docker-compose.yml exists"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M11-005 docker-compose.yml does not exist"
fi

# TEST-CTX-M11-006: README.md exists
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$BRIDGE_DIR/README.md" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M11-006 README.md exists"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M11-006 README.md does not exist"
fi

# TEST-CTX-M11-007: Integration test file exists
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$BRIDGE_DIR/tests/integration.rs" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M11-007 tests/integration.rs exists"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M11-007 tests/integration.rs does not exist"
fi

echo ""

# ============================================================
# TEST SUITE 2: Cargo.toml Dependencies
# TEST-CTX-M11-010 through TEST-CTX-M11-018
# ============================================================
echo "--- Cargo.toml Dependencies (TEST-CTX-M11-010 to TEST-CTX-M11-018) ---"

CARGO_CONTENT=""
if [ -f "$BRIDGE_DIR/Cargo.toml" ]; then
    CARGO_CONTENT=$(cat "$BRIDGE_DIR/Cargo.toml")
fi

# TEST-CTX-M11-010: Package name is cortex-bridge
assert_contains "$CARGO_CONTENT" 'name = "cortex-bridge"' "TEST-CTX-M11-010 package name is cortex-bridge"

# TEST-CTX-M11-011: axum dependency
assert_contains "$CARGO_CONTENT" 'axum =' "TEST-CTX-M11-011 axum dependency present"

# TEST-CTX-M11-012: tokio dependency
assert_contains "$CARGO_CONTENT" 'tokio =' "TEST-CTX-M11-012 tokio dependency present"

# TEST-CTX-M11-013: rusqlite dependency with bundled feature
assert_contains "$CARGO_CONTENT" 'rusqlite' "TEST-CTX-M11-013 rusqlite dependency present"
assert_contains "$CARGO_CONTENT" 'bundled' "TEST-CTX-M11-013b rusqlite has bundled feature"

# TEST-CTX-M11-014: serde dependency
assert_contains "$CARGO_CONTENT" 'serde =' "TEST-CTX-M11-014 serde dependency present"

# TEST-CTX-M11-015: serde_json dependency
assert_contains "$CARGO_CONTENT" 'serde_json' "TEST-CTX-M11-015 serde_json dependency present"

# TEST-CTX-M11-016: ring dependency (HMAC, no OpenSSL)
assert_contains "$CARGO_CONTENT" 'ring =' "TEST-CTX-M11-016 ring dependency present (no OpenSSL)"

# TEST-CTX-M11-017: uuid dependency
assert_contains "$CARGO_CONTENT" 'uuid =' "TEST-CTX-M11-017 uuid dependency present"

# TEST-CTX-M11-018: axum-server with TLS (rustls)
assert_contains "$CARGO_CONTENT" 'axum-server' "TEST-CTX-M11-018 axum-server dependency present"
assert_contains "$CARGO_CONTENT" 'tls-rustls' "TEST-CTX-M11-018b axum-server has tls-rustls feature"

echo ""

# ============================================================
# TEST SUITE 3: Source File Content Patterns
# TEST-CTX-M11-020 through TEST-CTX-M11-035
# ============================================================
echo "--- Source File Patterns (TEST-CTX-M11-020 to TEST-CTX-M11-035) ---"

# Read source files
MAIN_CONTENT=""
CONFIG_CONTENT=""
AUTH_CONTENT=""
ROUTES_CONTENT=""
STORAGE_CONTENT=""
MODELS_CONTENT=""

[ -f "$BRIDGE_DIR/src/main.rs" ] && MAIN_CONTENT=$(cat "$BRIDGE_DIR/src/main.rs")
[ -f "$BRIDGE_DIR/src/config.rs" ] && CONFIG_CONTENT=$(cat "$BRIDGE_DIR/src/config.rs")
[ -f "$BRIDGE_DIR/src/auth.rs" ] && AUTH_CONTENT=$(cat "$BRIDGE_DIR/src/auth.rs")
[ -f "$BRIDGE_DIR/src/routes.rs" ] && ROUTES_CONTENT=$(cat "$BRIDGE_DIR/src/routes.rs")
[ -f "$BRIDGE_DIR/src/storage.rs" ] && STORAGE_CONTENT=$(cat "$BRIDGE_DIR/src/storage.rs")
[ -f "$BRIDGE_DIR/src/models.rs" ] && MODELS_CONTENT=$(cat "$BRIDGE_DIR/src/models.rs")

# TEST-CTX-M11-020: main.rs has tokio::main and axum Router
assert_contains "$MAIN_CONTENT" "tokio::main" "TEST-CTX-M11-020 main.rs has tokio::main"
assert_contains "$MAIN_CONTENT" "Router" "TEST-CTX-M11-020b main.rs has Router"

# TEST-CTX-M11-021: main.rs has all 4 API routes
assert_contains "$MAIN_CONTENT" "/api/health" "TEST-CTX-M11-021a main.rs has /api/health route"
assert_contains "$MAIN_CONTENT" "/api/status" "TEST-CTX-M11-021b main.rs has /api/status route"
assert_contains "$MAIN_CONTENT" "/api/export" "TEST-CTX-M11-021c main.rs has /api/export route"
assert_contains "$MAIN_CONTENT" "/api/import" "TEST-CTX-M11-021d main.rs has /api/import route"

# TEST-CTX-M11-022: main.rs has TLS support
assert_contains "$MAIN_CONTENT" "tls_rustls" "TEST-CTX-M11-022 main.rs has TLS support via rustls"

# TEST-CTX-M11-023: config.rs reads from env vars
assert_contains "$CONFIG_CONTENT" "CORTEX_BRIDGE_HOST" "TEST-CTX-M11-023a config has CORTEX_BRIDGE_HOST"
assert_contains "$CONFIG_CONTENT" "CORTEX_BRIDGE_PORT" "TEST-CTX-M11-023b config has CORTEX_BRIDGE_PORT"
assert_contains "$CONFIG_CONTENT" "CORTEX_BRIDGE_TOKEN" "TEST-CTX-M11-023c config has CORTEX_BRIDGE_TOKEN"
assert_contains "$CONFIG_CONTENT" "CORTEX_BRIDGE_HMAC_KEY" "TEST-CTX-M11-023d config has CORTEX_BRIDGE_HMAC_KEY"
assert_contains "$CONFIG_CONTENT" "CORTEX_BRIDGE_DB_PATH" "TEST-CTX-M11-023e config has CORTEX_BRIDGE_DB_PATH"
assert_contains "$CONFIG_CONTENT" "CORTEX_BRIDGE_TLS_CERT" "TEST-CTX-M11-023f config has CORTEX_BRIDGE_TLS_CERT"
assert_contains "$CONFIG_CONTENT" "CORTEX_BRIDGE_TLS_KEY" "TEST-CTX-M11-023g config has CORTEX_BRIDGE_TLS_KEY"

# TEST-CTX-M11-024: auth.rs has HMAC verification
assert_contains "$AUTH_CONTENT" "verify_hmac" "TEST-CTX-M11-024a auth.rs has verify_hmac function"
assert_contains "$AUTH_CONTENT" "HMAC_SHA256" "TEST-CTX-M11-024b auth.rs uses HMAC_SHA256"

# TEST-CTX-M11-025: auth.rs has bearer token verification
assert_contains "$AUTH_CONTENT" "verify_bearer_token" "TEST-CTX-M11-025 auth.rs has verify_bearer_token"

# TEST-CTX-M11-026: auth.rs has timestamp/replay protection
assert_contains "$AUTH_CONTENT" "check_timestamp" "TEST-CTX-M11-026a auth.rs has check_timestamp"
assert_contains "$AUTH_CONTENT" "300" "TEST-CTX-M11-026b auth.rs has 5-minute (300s) window"

# TEST-CTX-M11-027: auth.rs has constant-time comparison
assert_contains_regex "$AUTH_CONTENT" "constant.time|hmac.*verify|timing" "TEST-CTX-M11-027 auth.rs mentions constant-time comparison"

# TEST-CTX-M11-028: routes.rs has health endpoint
assert_contains "$ROUTES_CONTENT" "pub async fn health" "TEST-CTX-M11-028 routes.rs has health handler"

# TEST-CTX-M11-029: routes.rs has status endpoint
assert_contains "$ROUTES_CONTENT" "pub async fn status" "TEST-CTX-M11-029 routes.rs has status handler"

# TEST-CTX-M11-030: routes.rs has export endpoint with HMAC verification
assert_contains "$ROUTES_CONTENT" "pub async fn export" "TEST-CTX-M11-030a routes.rs has export handler"
assert_contains "$ROUTES_CONTENT" "x-cortex-signature" "TEST-CTX-M11-030b export checks X-Cortex-Signature"
assert_contains "$ROUTES_CONTENT" "x-cortex-timestamp" "TEST-CTX-M11-030c export checks X-Cortex-Timestamp"

# TEST-CTX-M11-031: routes.rs has import endpoint
assert_contains "$ROUTES_CONTENT" "pub async fn import_entries" "TEST-CTX-M11-031 routes.rs has import handler"

# TEST-CTX-M11-032: routes.rs has rate limiting
assert_contains "$ROUTES_CONTENT" "RateLimiter" "TEST-CTX-M11-032a routes.rs has RateLimiter"
assert_contains "$ROUTES_CONTENT" "100" "TEST-CTX-M11-032b routes.rs has 100 req/min limit"

# TEST-CTX-M11-033: storage.rs has SQLite operations
assert_contains "$STORAGE_CONTENT" "rusqlite" "TEST-CTX-M11-033a storage.rs uses rusqlite"
assert_contains "$STORAGE_CONTENT" "CREATE TABLE" "TEST-CTX-M11-033b storage.rs creates tables"
assert_contains "$STORAGE_CONTENT" "insert_entries" "TEST-CTX-M11-033c storage.rs has insert_entries"
assert_contains "$STORAGE_CONTENT" "get_entries_since" "TEST-CTX-M11-033d storage.rs has get_entries_since"
assert_contains "$STORAGE_CONTENT" "get_counts" "TEST-CTX-M11-033e storage.rs has get_counts"

# TEST-CTX-M11-034: storage.rs has content_hash deduplication
assert_contains "$STORAGE_CONTENT" "content_hash" "TEST-CTX-M11-034 storage.rs has content_hash dedup"

# TEST-CTX-M11-035: models.rs has SharedEntry struct
assert_contains "$MODELS_CONTENT" "SharedEntry" "TEST-CTX-M11-035a models.rs has SharedEntry"
assert_contains "$MODELS_CONTENT" "ExportRequest" "TEST-CTX-M11-035b models.rs has ExportRequest"
assert_contains "$MODELS_CONTENT" "ExportResponse" "TEST-CTX-M11-035c models.rs has ExportResponse"
assert_contains "$MODELS_CONTENT" "ImportResponse" "TEST-CTX-M11-035d models.rs has ImportResponse"
assert_contains "$MODELS_CONTENT" "HealthResponse" "TEST-CTX-M11-035e models.rs has HealthResponse"
assert_contains "$MODELS_CONTENT" "StatusResponse" "TEST-CTX-M11-035f models.rs has StatusResponse"

echo ""

# ============================================================
# TEST SUITE 4: Dockerfile & docker-compose.yml
# TEST-CTX-M11-040 through TEST-CTX-M11-045
# ============================================================
echo "--- Docker Files (TEST-CTX-M11-040 to TEST-CTX-M11-045) ---"

DOCKERFILE_CONTENT=""
COMPOSE_CONTENT=""

[ -f "$BRIDGE_DIR/Dockerfile" ] && DOCKERFILE_CONTENT=$(cat "$BRIDGE_DIR/Dockerfile")
[ -f "$BRIDGE_DIR/docker-compose.yml" ] && COMPOSE_CONTENT=$(cat "$BRIDGE_DIR/docker-compose.yml")

# TEST-CTX-M11-040: Dockerfile has multi-stage build
assert_contains "$DOCKERFILE_CONTENT" "AS builder" "TEST-CTX-M11-040 Dockerfile has multi-stage build"

# TEST-CTX-M11-041: Dockerfile uses rust base image
assert_contains_regex "$DOCKERFILE_CONTENT" "FROM rust:" "TEST-CTX-M11-041 Dockerfile uses rust base image"

# TEST-CTX-M11-042: Dockerfile builds release binary
assert_contains "$DOCKERFILE_CONTENT" "cargo build --release" "TEST-CTX-M11-042 Dockerfile builds release"

# TEST-CTX-M11-043: Dockerfile exposes port
assert_contains "$DOCKERFILE_CONTENT" "EXPOSE 8443" "TEST-CTX-M11-043 Dockerfile exposes port 8443"

# TEST-CTX-M11-044: docker-compose.yml has cortex-bridge service
assert_contains "$COMPOSE_CONTENT" "cortex-bridge" "TEST-CTX-M11-044 docker-compose has cortex-bridge service"

# TEST-CTX-M11-045: docker-compose.yml has required env vars
assert_contains "$COMPOSE_CONTENT" "CORTEX_BRIDGE_TOKEN" "TEST-CTX-M11-045a docker-compose has TOKEN env"
assert_contains "$COMPOSE_CONTENT" "CORTEX_BRIDGE_HMAC_KEY" "TEST-CTX-M11-045b docker-compose has HMAC_KEY env"

echo ""

# ============================================================
# TEST SUITE 5: README.md Content
# TEST-CTX-M11-050 through TEST-CTX-M11-054
# ============================================================
echo "--- README.md Content (TEST-CTX-M11-050 to TEST-CTX-M11-054) ---"

README_CONTENT=""
[ -f "$BRIDGE_DIR/README.md" ] && README_CONTENT=$(cat "$BRIDGE_DIR/README.md")

# TEST-CTX-M11-050: README has Docker deployment
assert_contains "$README_CONTENT" "Docker" "TEST-CTX-M11-050 README mentions Docker deployment"

# TEST-CTX-M11-051: README has bare metal deployment
assert_contains_regex "$README_CONTENT" "[Bb]are [Mm]etal" "TEST-CTX-M11-051 README mentions bare metal deployment"

# TEST-CTX-M11-052: README has systemd
assert_contains "$README_CONTENT" "systemd" "TEST-CTX-M11-052 README mentions systemd"

# TEST-CTX-M11-053: README has TLS documentation
assert_contains "$README_CONTENT" "TLS" "TEST-CTX-M11-053 README documents TLS"

# TEST-CTX-M11-054: README has API endpoint documentation
assert_contains "$README_CONTENT" "/api/health" "TEST-CTX-M11-054a README documents /api/health"
assert_contains "$README_CONTENT" "/api/status" "TEST-CTX-M11-054b README documents /api/status"
assert_contains "$README_CONTENT" "/api/export" "TEST-CTX-M11-054c README documents /api/export"
assert_contains "$README_CONTENT" "/api/import" "TEST-CTX-M11-054d README documents /api/import"

echo ""

# ============================================================
# TEST SUITE 6: sync-adapters.md SELF-HOSTED-ADAPTER Section
# TEST-CTX-M11-060 through TEST-CTX-M11-067
# ============================================================
echo "--- sync-adapters.md SELF-HOSTED Section (TEST-CTX-M11-060 to TEST-CTX-M11-067) ---"

SYNC_CONTENT=""
[ -f "$SYNC_ADAPTERS" ] && SYNC_CONTENT=$(cat "$SYNC_ADAPTERS")

# TEST-CTX-M11-060: SELF-HOSTED-ADAPTER section exists
assert_contains "$SYNC_CONTENT" "## SELF-HOSTED-ADAPTER" "TEST-CTX-M11-060 SELF-HOSTED-ADAPTER section exists"

# TEST-CTX-M11-061: Section is no longer a placeholder
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$SYNC_CONTENT" | grep -q "This section will be expanded"; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M11-061 SELF-HOSTED-ADAPTER still has placeholder text"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M11-061 SELF-HOSTED-ADAPTER placeholder removed"
fi

# TEST-CTX-M11-062: Section documents all 4 API endpoints
assert_contains "$SYNC_CONTENT" "POST /api/export" "TEST-CTX-M11-062a documents POST /api/export"
assert_contains "$SYNC_CONTENT" "GET /api/import" "TEST-CTX-M11-062b documents GET /api/import"
assert_contains "$SYNC_CONTENT" "GET /api/status" "TEST-CTX-M11-062c documents GET /api/status"
assert_contains "$SYNC_CONTENT" "GET /api/health" "TEST-CTX-M11-062d documents GET /api/health"

# TEST-CTX-M11-063: Section documents Bearer auth
assert_contains "$SYNC_CONTENT" "Bearer" "TEST-CTX-M11-063 documents Bearer authentication"

# TEST-CTX-M11-064: Section documents HMAC auth
assert_contains "$SYNC_CONTENT" "HMAC-SHA256" "TEST-CTX-M11-064 documents HMAC-SHA256 authentication"

# TEST-CTX-M11-065: Section documents replay protection
assert_contains_regex "$SYNC_CONTENT" "[Rr]eplay" "TEST-CTX-M11-065 documents replay protection"

# TEST-CTX-M11-066: Section documents deployment options
assert_contains_regex "$SYNC_CONTENT" "[Dd]eploy" "TEST-CTX-M11-066 documents deployment options"

# TEST-CTX-M11-067: @INDEX updated with correct line range
INDEX_BLOCK=$(head -10 "$SYNC_ADAPTERS" 2>/dev/null || echo "")
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$INDEX_BLOCK" | grep -qE "SELF-HOSTED-ADAPTER.*[0-9]+-[0-9]+"; then
    # Verify it's NOT still the old small range (166-185)
    if echo "$INDEX_BLOCK" | grep -q "SELF-HOSTED-ADAPTER.*166-185"; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M11-067 @INDEX still has old range 166-185"
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M11-067 @INDEX updated with new SELF-HOSTED-ADAPTER range"
    fi
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M11-067 @INDEX missing SELF-HOSTED-ADAPTER range"
fi

echo ""

# ============================================================
# TEST SUITE 7: Rust Compilation (optional)
# TEST-CTX-M11-070 through TEST-CTX-M11-072
# ============================================================
echo "--- Rust Compilation (TEST-CTX-M11-070 to TEST-CTX-M11-072) ---"

if command -v cargo >/dev/null 2>&1; then
    # TEST-CTX-M11-070: cargo check passes
    TESTS_RUN=$((TESTS_RUN + 1))
    if (cd "$BRIDGE_DIR" && cargo check 2>&1 | tail -1 | grep -q "Finished"); then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M11-070 cargo check passes"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M11-070 cargo check failed"
        if [ "$VERBOSE" = true ]; then
            (cd "$BRIDGE_DIR" && cargo check 2>&1 | tail -20)
        fi
    fi

    # TEST-CTX-M11-071: cargo clippy passes (lib only, no dead_code from binary)
    TESTS_RUN=$((TESTS_RUN + 1))
    CLIPPY_OUTPUT=$(cd "$BRIDGE_DIR" && cargo clippy --lib -- -D warnings 2>&1)
    if echo "$CLIPPY_OUTPUT" | grep -q "error"; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M11-071 cargo clippy --lib has errors"
        if [ "$VERBOSE" = true ]; then
            echo "$CLIPPY_OUTPUT" | tail -20
        fi
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M11-071 cargo clippy --lib passes clean"
    fi

    # TEST-CTX-M11-072: cargo test passes
    TESTS_RUN=$((TESTS_RUN + 1))
    TEST_OUTPUT=$(cd "$BRIDGE_DIR" && cargo test 2>&1)
    FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep -c "FAILED" || true)
    if [ "$FAIL_COUNT" = "0" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M11-072 cargo test passes (all tests green)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M11-072 cargo test has failures"
        if [ "$VERBOSE" = true ]; then
            echo "$TEST_OUTPUT" | grep -A5 "FAILED"
        fi
    fi
else
    echo "  SKIP: TEST-CTX-M11-070 cargo not found (Rust toolchain not installed)"
    echo "  SKIP: TEST-CTX-M11-071 cargo not found"
    echo "  SKIP: TEST-CTX-M11-072 cargo not found"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 3))
fi

echo ""

# ============================================================
# TEST SUITE 8: Security Patterns
# TEST-CTX-M11-080 through TEST-CTX-M11-085
# ============================================================
echo "--- Security Patterns (TEST-CTX-M11-080 to TEST-CTX-M11-085) ---"

# TEST-CTX-M11-080: No OpenSSL dependency in Cargo.toml
TESTS_RUN=$((TESTS_RUN + 1))
if echo "$CARGO_CONTENT" | grep -qi "openssl"; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M11-080 Cargo.toml contains OpenSSL dependency (should use ring/rustls)"
else
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M11-080 No OpenSSL dependency (uses ring + rustls)"
fi

# TEST-CTX-M11-081: Body size limit enforced
ALL_SRC=""
for f in "$BRIDGE_DIR"/src/*.rs; do
    [ -f "$f" ] && ALL_SRC="$ALL_SRC$(cat "$f")"
done
assert_contains "$ALL_SRC" "1_048_576" "TEST-CTX-M11-081 1MB body size limit enforced"

# TEST-CTX-M11-082: Rate limiting present
assert_contains "$ALL_SRC" "rate_limiter" "TEST-CTX-M11-082 Rate limiting implemented"

# TEST-CTX-M11-083: WAL mode for SQLite
assert_contains "$STORAGE_CONTENT" "WAL" "TEST-CTX-M11-083 SQLite WAL mode enabled"

# TEST-CTX-M11-084: Graceful error handling (no unwrap in routes)
TESTS_RUN=$((TESTS_RUN + 1))
UNWRAP_COUNT=$(echo "$ROUTES_CONTENT" | grep -c "\.unwrap()" || true)
if [ "$UNWRAP_COUNT" -eq 0 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M11-084 No unwrap() in routes.rs (graceful error handling)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M11-084 Found $UNWRAP_COUNT unwrap() calls in routes.rs"
fi

# TEST-CTX-M11-085: X-Cortex-Signature and X-Cortex-Timestamp headers used
assert_contains "$ALL_SRC" "x-cortex-signature" "TEST-CTX-M11-085a X-Cortex-Signature header used"
assert_contains "$ALL_SRC" "x-cortex-timestamp" "TEST-CTX-M11-085b X-Cortex-Timestamp header used"

echo ""

# ============================================================
# SUMMARY
# ============================================================
echo "============================================================"
echo "RESULTS: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
echo "============================================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi

exit 0
