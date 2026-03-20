#!/bin/bash
# test-cortex-m13-bridge-security.sh
#
# Tests for OMEGA Cortex Milestone M13: Bridge + Network Security Hardening
# Covers: REQ-CTX-056 (TLS mandatory), REQ-CTX-057 (HMAC auth), REQ-CTX-058 (rate limiting + size caps)
#
# These tests validate security properties by inspecting source code patterns:
# - TLS configuration and rustls usage
# - HMAC authentication implementation
# - Rate limiting enforcement
# - Body size limits
# - No unsafe code
# - No unwrap in handlers
# - Dependency security (ring, not openssl)
# - Protocol documentation of security features
#
# Usage:
#   bash tests/test-cortex-m13-bridge-security.sh
#   bash tests/test-cortex-m13-bridge-security.sh --verbose
#
# Dependencies: bash, grep

set -u

# ============================================================
# TEST FRAMEWORK (matching existing project conventions from M11)
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

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -qF -- "$needle"; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Unwanted needle found: $needle"
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    fi
}

assert_not_contains_regex() {
    local haystack="$1"
    local pattern="$2"
    local description="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if echo "$haystack" | grep -qE "$pattern"; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: $description"
        echo "    Unwanted pattern matched: $pattern"
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: $description"
    fi
}

# ============================================================
# RESOLVE PROJECT ROOT
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BRIDGE_DIR="$PROJECT_ROOT/extensions/cortex-bridge"
CORTEX_PROTOCOL="$PROJECT_ROOT/core/protocols/cortex-protocol.md"
SYNC_ADAPTERS="$PROJECT_ROOT/core/protocols/sync-adapters.md"

echo "============================================================"
echo "OMEGA Cortex M13: Bridge + Network Security Hardening Tests"
echo "============================================================"
echo "  Project root: $PROJECT_ROOT"
echo "  Bridge dir: $BRIDGE_DIR"
echo ""

# ============================================================
# Read all source files once
# ============================================================
MAIN_CONTENT=""
CONFIG_CONTENT=""
AUTH_CONTENT=""
ROUTES_CONTENT=""
STORAGE_CONTENT=""
CARGO_CONTENT=""

[ -f "$BRIDGE_DIR/src/main.rs" ] && MAIN_CONTENT=$(cat "$BRIDGE_DIR/src/main.rs")
[ -f "$BRIDGE_DIR/src/config.rs" ] && CONFIG_CONTENT=$(cat "$BRIDGE_DIR/src/config.rs")
[ -f "$BRIDGE_DIR/src/auth.rs" ] && AUTH_CONTENT=$(cat "$BRIDGE_DIR/src/auth.rs")
[ -f "$BRIDGE_DIR/src/routes.rs" ] && ROUTES_CONTENT=$(cat "$BRIDGE_DIR/src/routes.rs")
[ -f "$BRIDGE_DIR/src/storage.rs" ] && STORAGE_CONTENT=$(cat "$BRIDGE_DIR/src/storage.rs")
[ -f "$BRIDGE_DIR/Cargo.toml" ] && CARGO_CONTENT=$(cat "$BRIDGE_DIR/Cargo.toml")

# Concatenate all source for cross-file checks
ALL_SRC=""
for f in "$BRIDGE_DIR"/src/*.rs; do
    [ -f "$f" ] && ALL_SRC="$ALL_SRC$(cat "$f")"
done

# ============================================================
# TEST SUITE 1: TLS Configuration (REQ-CTX-056)
# TEST-CTX-M13-101 through TEST-CTX-M13-106
# ============================================================
echo "--- TLS Configuration [REQ-CTX-056] (TEST-CTX-M13-101 to TEST-CTX-M13-106) ---"

# TEST-CTX-M13-101: main.rs references rustls or TLS
assert_contains_regex "$MAIN_CONTENT" "tls_rustls|rustls|RustlsConfig" \
    "TEST-CTX-M13-101 main.rs references rustls/TLS"

# TEST-CTX-M13-102: config.rs has TLS_CERT env var
assert_contains "$CONFIG_CONTENT" "CORTEX_BRIDGE_TLS_CERT" \
    "TEST-CTX-M13-102 config.rs has CORTEX_BRIDGE_TLS_CERT env var"

# TEST-CTX-M13-103: config.rs has TLS_KEY env var
assert_contains "$CONFIG_CONTENT" "CORTEX_BRIDGE_TLS_KEY" \
    "TEST-CTX-M13-103 config.rs has CORTEX_BRIDGE_TLS_KEY env var"

# TEST-CTX-M13-104: Cargo.toml has tls-rustls feature
assert_contains "$CARGO_CONTENT" "tls-rustls" \
    "TEST-CTX-M13-104 Cargo.toml has tls-rustls feature"

# TEST-CTX-M13-105: No openssl dependency in Cargo.toml
assert_not_contains "$CARGO_CONTENT" "openssl" \
    "TEST-CTX-M13-105 No openssl dependency in Cargo.toml"

# TEST-CTX-M13-106: axum-server dependency for TLS binding
assert_contains "$CARGO_CONTENT" "axum-server" \
    "TEST-CTX-M13-106 axum-server dependency for TLS binding"

echo ""

# ============================================================
# TEST SUITE 2: HMAC Authentication (REQ-CTX-057)
# TEST-CTX-M13-201 through TEST-CTX-M13-208
# ============================================================
echo "--- HMAC Authentication [REQ-CTX-057] (TEST-CTX-M13-201 to TEST-CTX-M13-208) ---"

# TEST-CTX-M13-201: auth.rs uses ring::hmac
assert_contains "$AUTH_CONTENT" "ring::hmac" \
    "TEST-CTX-M13-201 auth.rs uses ring::hmac"

# TEST-CTX-M13-202: auth.rs implements constant-time comparison
assert_contains_regex "$AUTH_CONTENT" "constant.time|hmac::verify" \
    "TEST-CTX-M13-202 auth.rs uses constant-time comparison (hmac::verify)"

# TEST-CTX-M13-203: routes.rs calls verify_hmac on export endpoint
assert_contains "$ROUTES_CONTENT" "verify_hmac" \
    "TEST-CTX-M13-203 routes.rs calls verify_hmac on export"

# TEST-CTX-M13-204: X-Cortex-Signature header referenced
assert_contains "$ALL_SRC" "x-cortex-signature" \
    "TEST-CTX-M13-204 X-Cortex-Signature header referenced"

# TEST-CTX-M13-205: X-Cortex-Timestamp header referenced
assert_contains "$ALL_SRC" "x-cortex-timestamp" \
    "TEST-CTX-M13-205 X-Cortex-Timestamp header referenced"

# TEST-CTX-M13-206: auth.rs has verify_bearer_token function
assert_contains "$AUTH_CONTENT" "pub fn verify_bearer_token" \
    "TEST-CTX-M13-206 auth.rs has verify_bearer_token function"

# TEST-CTX-M13-207: auth.rs has check_timestamp function
assert_contains "$AUTH_CONTENT" "pub fn check_timestamp" \
    "TEST-CTX-M13-207 auth.rs has check_timestamp function"

# TEST-CTX-M13-208: 5-minute replay window (300 seconds)
assert_contains "$AUTH_CONTENT" "300" \
    "TEST-CTX-M13-208 auth.rs has 5-minute (300s) replay window"

echo ""

# ============================================================
# TEST SUITE 3: Rate Limiting (REQ-CTX-058)
# TEST-CTX-M13-301 through TEST-CTX-M13-304
# ============================================================
echo "--- Rate Limiting [REQ-CTX-058] (TEST-CTX-M13-301 to TEST-CTX-M13-304) ---"

# TEST-CTX-M13-301: routes.rs implements rate limiting
assert_contains "$ROUTES_CONTENT" "RateLimiter" \
    "TEST-CTX-M13-301 routes.rs implements RateLimiter"

# TEST-CTX-M13-302: 100 req/min limit documented or coded
assert_contains_regex "$ALL_SRC" "100.*req|100 req|RateLimiter::new(100)|new\(100\)" \
    "TEST-CTX-M13-302 100 req/min limit present"

# TEST-CTX-M13-303: HTTP 429 status code referenced
assert_contains "$ROUTES_CONTENT" "TOO_MANY_REQUESTS" \
    "TEST-CTX-M13-303 HTTP 429 TOO_MANY_REQUESTS status referenced"

# TEST-CTX-M13-304: Rate limiter checks applied to export/import/status handlers
TESTS_RUN=$((TESTS_RUN + 1))
RATE_CHECK_COUNT=$(echo "$ROUTES_CONTENT" | grep -c "rate_limiter.check()" || true)
if [ "$RATE_CHECK_COUNT" -ge 3 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M13-304 Rate limiter check in $RATE_CHECK_COUNT handlers (expect >= 3)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M13-304 Rate limiter check in only $RATE_CHECK_COUNT handlers (expect >= 3)"
fi

echo ""

# ============================================================
# TEST SUITE 4: Body Size Limits (REQ-CTX-058)
# TEST-CTX-M13-401 through TEST-CTX-M13-402
# ============================================================
echo "--- Body Size Limits [REQ-CTX-058] (TEST-CTX-M13-401 to TEST-CTX-M13-402) ---"

# TEST-CTX-M13-401: 1MB limit (1_048_576 or 1048576) referenced in routes.rs
assert_contains_regex "$ROUTES_CONTENT" "1_048_576|1048576" \
    "TEST-CTX-M13-401 1MB (1_048_576) body size limit in routes.rs"

# TEST-CTX-M13-402: PAYLOAD_TOO_LARGE status code referenced
assert_contains "$ROUTES_CONTENT" "PAYLOAD_TOO_LARGE" \
    "TEST-CTX-M13-402 PAYLOAD_TOO_LARGE status referenced"

echo ""

# ============================================================
# TEST SUITE 5: No unsafe Code
# TEST-CTX-M13-501 through TEST-CTX-M13-502
# ============================================================
echo "--- Code Safety (TEST-CTX-M13-501 to TEST-CTX-M13-502) ---"

# TEST-CTX-M13-501: No unsafe blocks in source files
TESTS_RUN=$((TESTS_RUN + 1))
UNSAFE_COUNT=0
for f in "$BRIDGE_DIR"/src/*.rs; do
    if [ -f "$f" ]; then
        # Match "unsafe {" or "unsafe fn" but not inside comments
        FILE_UNSAFE=$(grep -c "^[^/]*unsafe " "$f" 2>/dev/null || true)
        UNSAFE_COUNT=$((UNSAFE_COUNT + FILE_UNSAFE))
    fi
done
if [ "$UNSAFE_COUNT" -eq 0 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M13-501 No unsafe blocks in bridge source files"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M13-501 Found $UNSAFE_COUNT unsafe blocks in source files"
fi

# TEST-CTX-M13-502: No unwrap() in routes.rs (graceful error handling)
TESTS_RUN=$((TESTS_RUN + 1))
UNWRAP_COUNT=$(echo "$ROUTES_CONTENT" | grep -c "\.unwrap()" || true)
if [ "$UNWRAP_COUNT" -eq 0 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M13-502 No unwrap() in routes.rs handlers"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M13-502 Found $UNWRAP_COUNT unwrap() in routes.rs"
fi

echo ""

# ============================================================
# TEST SUITE 6: Dependency Security
# TEST-CTX-M13-601 through TEST-CTX-M13-604
# ============================================================
echo "--- Dependency Security (TEST-CTX-M13-601 to TEST-CTX-M13-604) ---"

# TEST-CTX-M13-601: ring used for crypto (not home-rolled)
assert_contains "$CARGO_CONTENT" 'ring =' \
    "TEST-CTX-M13-601 ring crate used for cryptography"

# TEST-CTX-M13-602: No openssl in Cargo.toml (pure Rust crypto stack)
assert_not_contains "$CARGO_CONTENT" "openssl" \
    "TEST-CTX-M13-602 No openssl dependency (pure Rust crypto)"

# TEST-CTX-M13-603: rusqlite used for SQL (parameterized queries)
assert_contains "$CARGO_CONTENT" "rusqlite" \
    "TEST-CTX-M13-603 rusqlite crate for parameterized SQL queries"

# TEST-CTX-M13-604: storage.rs uses parameterized queries (no string-format SQL)
TESTS_RUN=$((TESTS_RUN + 1))
# Check that params![] is used and no format!("...INSERT...{...}...") patterns exist
PARAMS_COUNT=$(echo "$STORAGE_CONTENT" | grep -c "params!\[" || true)
FORMAT_SQL_COUNT=$(echo "$STORAGE_CONTENT" | grep -c 'format!.*INSERT\|format!.*SELECT\|format!.*UPDATE\|format!.*DELETE' || true)
if [ "$PARAMS_COUNT" -gt 0 ] && [ "$FORMAT_SQL_COUNT" -eq 0 ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M13-604 storage.rs uses parameterized queries ($PARAMS_COUNT params![] calls, 0 format SQL)"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M13-604 storage.rs params![]=$PARAMS_COUNT, format SQL=$FORMAT_SQL_COUNT"
fi

echo ""

# ============================================================
# TEST SUITE 7: Protocol Documentation
# TEST-CTX-M13-701 through TEST-CTX-M13-706
# ============================================================
echo "--- Protocol Documentation (TEST-CTX-M13-701 to TEST-CTX-M13-706) ---"

CORTEX_CONTENT=""
SYNC_CONTENT=""
[ -f "$CORTEX_PROTOCOL" ] && CORTEX_CONTENT=$(cat "$CORTEX_PROTOCOL")
[ -f "$SYNC_ADAPTERS" ] && SYNC_CONTENT=$(cat "$SYNC_ADAPTERS")

# TEST-CTX-M13-701: cortex-protocol.md SECURITY section documents bridge auth
assert_contains "$CORTEX_CONTENT" "## SECURITY" \
    "TEST-CTX-M13-701 cortex-protocol.md has SECURITY section"

# TEST-CTX-M13-702: SECURITY section documents HMAC-SHA256
assert_contains "$CORTEX_CONTENT" "HMAC-SHA256" \
    "TEST-CTX-M13-702 SECURITY section documents HMAC-SHA256"

# TEST-CTX-M13-703: SECURITY section documents Bearer token
assert_contains "$CORTEX_CONTENT" "Bearer token" \
    "TEST-CTX-M13-703 SECURITY section documents Bearer token"

# TEST-CTX-M13-704: SECURITY section documents bridge authentication subsection
assert_contains "$CORTEX_CONTENT" "Bridge Authentication" \
    "TEST-CTX-M13-704 SECURITY section has Bridge Authentication subsection"

# TEST-CTX-M13-705: sync-adapters.md SELF-HOSTED-ADAPTER documents dual auth
assert_contains "$SYNC_CONTENT" "SELF-HOSTED-ADAPTER" \
    "TEST-CTX-M13-705 sync-adapters.md has SELF-HOSTED-ADAPTER section"

# TEST-CTX-M13-706: SELF-HOSTED-ADAPTER documents HMAC-SHA256
assert_contains "$SYNC_CONTENT" "HMAC-SHA256" \
    "TEST-CTX-M13-706 SELF-HOSTED-ADAPTER documents HMAC-SHA256"

echo ""

# ============================================================
# TEST SUITE 8: Security Test File Existence
# TEST-CTX-M13-801 through TEST-CTX-M13-802
# ============================================================
echo "--- Security Test Files (TEST-CTX-M13-801 to TEST-CTX-M13-802) ---"

# TEST-CTX-M13-801: Rust security integration test file exists
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$BRIDGE_DIR/tests/security.rs" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: TEST-CTX-M13-801 tests/security.rs exists"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: TEST-CTX-M13-801 tests/security.rs does not exist"
fi

# TEST-CTX-M13-802: Security test file covers M13 test IDs
SECURITY_TEST_CONTENT=""
[ -f "$BRIDGE_DIR/tests/security.rs" ] && SECURITY_TEST_CONTENT=$(cat "$BRIDGE_DIR/tests/security.rs")

assert_contains "$SECURITY_TEST_CONTENT" "TEST-CTX-M13" \
    "TEST-CTX-M13-802 security.rs references TEST-CTX-M13 test IDs"

echo ""

# ============================================================
# TEST SUITE 9: Cargo test (optional -- requires Rust toolchain)
# TEST-CTX-M13-901 through TEST-CTX-M13-902
# ============================================================
echo "--- Cargo Test Validation (TEST-CTX-M13-901 to TEST-CTX-M13-902) ---"

if command -v cargo >/dev/null 2>&1; then
    # TEST-CTX-M13-901: cargo test --test security passes
    TESTS_RUN=$((TESTS_RUN + 1))
    TEST_OUTPUT=$(cd "$BRIDGE_DIR" && cargo test --test security 2>&1)
    FAIL_COUNT=$(echo "$TEST_OUTPUT" | grep -c "FAILED" || true)
    if [ "$FAIL_COUNT" = "0" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M13-901 cargo test --test security passes (all security tests green)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M13-901 cargo test --test security has failures"
        if [ "$VERBOSE" = true ]; then
            echo "$TEST_OUTPUT" | grep -A5 "FAILED"
        fi
    fi

    # TEST-CTX-M13-902: Full cargo test passes (existing + security)
    TESTS_RUN=$((TESTS_RUN + 1))
    FULL_TEST_OUTPUT=$(cd "$BRIDGE_DIR" && cargo test 2>&1)
    FULL_FAIL_COUNT=$(echo "$FULL_TEST_OUTPUT" | grep -c "FAILED" || true)
    if [ "$FULL_FAIL_COUNT" = "0" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  PASS: TEST-CTX-M13-902 cargo test passes (all tests including security)"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL: TEST-CTX-M13-902 cargo test has failures"
        if [ "$VERBOSE" = true ]; then
            echo "$FULL_TEST_OUTPUT" | grep -A5 "FAILED"
        fi
    fi
else
    echo "  SKIP: TEST-CTX-M13-901 cargo not found (Rust toolchain not installed)"
    echo "  SKIP: TEST-CTX-M13-902 cargo not found"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 2))
fi

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
