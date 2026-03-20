// auth.rs -- Authentication and authorization for the Cortex Bridge
//
// Implements dual authentication as specified in cortex-protocol.md SECURITY section:
// 1. Bearer token verification (constant-time comparison)
// 2. HMAC-SHA256 signature verification using `ring`
// 3. Timestamp-based replay protection (5-minute window)

use axum::{
    extract::{Request, State},
    http::{HeaderMap, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
};
use ring::hmac;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::config::hex_decode;
use crate::routes::AppState;

/// Verify a bearer token using constant-time comparison.
///
/// Returns true if the provided token matches the expected token.
/// Uses HMAC-based comparison to prevent timing side-channel attacks:
/// HMAC(key, provided) == HMAC(key, expected) is constant-time via ring.
pub fn verify_bearer_token(provided: &str, expected: &str) -> bool {
    // Use HMAC as a constant-time equality check: if HMAC(k, a) == HMAC(k, b) then a == b
    let key = hmac::Key::new(hmac::HMAC_SHA256, b"bearer-token-comparison");
    let tag = hmac::sign(&key, expected.as_bytes());
    hmac::verify(&key, provided.as_bytes(), tag.as_ref()).is_ok()
}

/// Verify an HMAC-SHA256 signature over a request body.
///
/// The signature is computed as: HMAC-SHA256(key, "<timestamp>.<body>")
/// The expected header format is: `hmac-sha256=<hex_digest>`
///
/// Returns true if the signature is valid.
pub fn verify_hmac(body: &[u8], signature_header: &str, timestamp: &str, key_hex: &str) -> bool {
    // Parse the signature header: "hmac-sha256=<hex>"
    let hex_sig = match signature_header.strip_prefix("hmac-sha256=") {
        Some(h) => h,
        None => return false,
    };

    // Decode the provided signature from hex
    let provided_sig = match hex_decode(hex_sig) {
        Some(s) => s,
        None => return false,
    };

    // Decode the HMAC key from hex
    let key_bytes = match hex_decode(key_hex) {
        Some(k) => k,
        None => return false,
    };

    // Compute expected HMAC: HMAC-SHA256(key, "<timestamp>.<body>")
    let signing_key = hmac::Key::new(hmac::HMAC_SHA256, &key_bytes);
    let mut message = Vec::with_capacity(timestamp.len() + 1 + body.len());
    message.extend_from_slice(timestamp.as_bytes());
    message.push(b'.');
    message.extend_from_slice(body);

    // Constant-time verification
    hmac::verify(&signing_key, &message, &provided_sig).is_ok()
}

/// Check if a timestamp is within the acceptable replay window (5 minutes).
///
/// Returns true if the timestamp is within 300 seconds of the current time.
pub fn check_timestamp(timestamp_str: &str) -> bool {
    let provided: u64 = match timestamp_str.parse() {
        Ok(t) => t,
        Err(_) => return false,
    };

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    // Allow 5 minutes (300 seconds) of clock skew in either direction
    let diff = now.abs_diff(provided);

    diff <= 300
}

/// Axum middleware for Bearer token authentication.
///
/// Checks the `Authorization: Bearer <token>` header against the
/// configured auth token. Returns 401 Unauthorized if missing or invalid.
pub async fn bearer_auth_middleware(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    request: Request,
    next: Next,
) -> Response {
    let auth_header = headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    let token = auth_header.strip_prefix("Bearer ").unwrap_or("");

    if token.is_empty() || !verify_bearer_token(token, &state.auth_token) {
        return (
            StatusCode::UNAUTHORIZED,
            serde_json::json!({"error": "Invalid or missing Bearer token"}).to_string(),
        )
            .into_response();
    }

    next.run(request).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_verify_bearer_token_valid() {
        assert!(verify_bearer_token("my-secret-token", "my-secret-token"));
    }

    #[test]
    fn test_verify_bearer_token_invalid() {
        assert!(!verify_bearer_token("wrong-token", "my-secret-token"));
        assert!(!verify_bearer_token("", "my-secret-token"));
    }

    #[test]
    fn test_verify_hmac_valid() {
        // Generate a test HMAC
        let key_hex = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
        let body = b"test body";
        let timestamp = "1234567890";

        // Compute expected signature
        let key_bytes = hex_decode(key_hex).unwrap();
        let signing_key = hmac::Key::new(hmac::HMAC_SHA256, &key_bytes);
        let mut message = Vec::new();
        message.extend_from_slice(timestamp.as_bytes());
        message.push(b'.');
        message.extend_from_slice(body);
        let tag = hmac::sign(&signing_key, &message);
        let sig_hex: String = tag.as_ref().iter().map(|b| format!("{b:02x}")).collect();

        let header = format!("hmac-sha256={sig_hex}");
        assert!(verify_hmac(body, &header, timestamp, key_hex));
    }

    #[test]
    fn test_verify_hmac_invalid() {
        let key_hex = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
        assert!(!verify_hmac(
            b"body",
            "hmac-sha256=0000000000000000000000000000000000000000000000000000000000000000",
            "1234567890",
            key_hex
        ));
    }

    #[test]
    fn test_verify_hmac_bad_prefix() {
        assert!(!verify_hmac(b"body", "sha256=abcd", "12345", "aabb"));
    }

    #[test]
    fn test_check_timestamp_valid() {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        assert!(check_timestamp(&now.to_string()));
        assert!(check_timestamp(&(now - 60).to_string())); // 1 min ago
        assert!(check_timestamp(&(now + 60).to_string())); // 1 min future
    }

    #[test]
    fn test_check_timestamp_expired() {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        assert!(!check_timestamp(&(now - 600).to_string())); // 10 min ago
    }

    #[test]
    fn test_check_timestamp_invalid() {
        assert!(!check_timestamp("not-a-number"));
        assert!(!check_timestamp(""));
    }
}
