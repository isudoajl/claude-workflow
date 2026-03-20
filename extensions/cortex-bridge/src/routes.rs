// routes.rs -- API route handlers for the Cortex Bridge
//
// Implements 4 endpoints:
// - GET  /api/health  -- no auth, returns server health
// - GET  /api/status  -- bearer auth, returns category counts
// - POST /api/export  -- bearer + HMAC auth, receives entries
// - GET  /api/import  -- bearer auth, returns entries since timestamp

use axum::{
    body::Bytes,
    extract::{Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Json},
};
use serde::Deserialize;
use std::sync::Arc;
use std::time::Instant;

use crate::auth;
use crate::models::{
    ExportRequest, ExportResponse, HealthResponse, ImportResponse, SharedEntry, StatusResponse,
};
use crate::storage::Database;

/// Shared application state passed to all route handlers.
pub struct AppState {
    pub db: Database,
    pub auth_token: String,
    pub hmac_key: String,
    pub start_time: Instant,
    pub rate_limiter: RateLimiter,
}

/// Simple in-memory rate limiter using std::time::Instant.
///
/// Tracks request count per minute. Resets the counter when the
/// current window expires. This is a global counter, not per-IP,
/// which is sufficient for a single-team bridge server.
pub struct RateLimiter {
    counter: std::sync::Mutex<(u64, Instant)>,
    max_per_minute: u64,
}

impl RateLimiter {
    pub fn new(max_per_minute: u64) -> Self {
        RateLimiter {
            counter: std::sync::Mutex::new((0, Instant::now())),
            max_per_minute,
        }
    }

    /// Check if a request is allowed. Returns true if within rate limit.
    pub fn check(&self) -> bool {
        let mut state = self.counter.lock().expect("Rate limiter mutex poisoned");
        let elapsed = state.1.elapsed();

        // Reset counter if window has expired
        if elapsed.as_secs() >= 60 {
            *state = (1, Instant::now());
            return true;
        }

        if state.0 >= self.max_per_minute {
            return false;
        }

        state.0 += 1;
        true
    }
}

/// GET /api/health -- No authentication required.
///
/// Returns server health status including version and uptime.
pub async fn health(State(state): State<Arc<AppState>>) -> Json<HealthResponse> {
    let uptime = state.start_time.elapsed().as_secs();
    Json(HealthResponse {
        healthy: true,
        version: env!("CARGO_PKG_VERSION").to_string(),
        uptime_seconds: uptime,
    })
}

/// GET /api/status -- Requires Bearer token authentication.
///
/// Returns category counts and last sync timestamp.
pub async fn status(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    if !state.rate_limiter.check() {
        return (
            StatusCode::TOO_MANY_REQUESTS,
            Json(serde_json::json!({"error": "Rate limit exceeded (100 req/min)"})),
        )
            .into_response();
    }

    let counts = match state.db.get_counts() {
        Ok(c) => c,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": format!("Database error: {e}")})),
            )
                .into_response();
        }
    };

    let last_sync = state.db.get_last_sync().unwrap_or(None);

    Json(StatusResponse {
        backend: "self-hosted".to_string(),
        counts,
        last_sync,
    })
    .into_response()
}

/// Query parameters for the import endpoint.
#[derive(Debug, Deserialize)]
pub struct ImportQuery {
    pub since: Option<String>,
}

/// GET /api/import?since=TIMESTAMP -- Requires Bearer token authentication.
///
/// Returns all entries created after the given timestamp. If `since`
/// is omitted, returns all entries.
pub async fn import_entries(
    State(state): State<Arc<AppState>>,
    Query(query): Query<ImportQuery>,
) -> impl IntoResponse {
    if !state.rate_limiter.check() {
        return (
            StatusCode::TOO_MANY_REQUESTS,
            Json(serde_json::json!({"error": "Rate limit exceeded (100 req/min)"})),
        )
            .into_response();
    }

    let entries = match state.db.get_entries_since(query.since.as_deref()) {
        Ok(e) => e,
        Err(e) => {
            return (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({"error": format!("Database error: {e}")})),
            )
                .into_response();
        }
    };

    let count = entries.len();
    Json(ImportResponse { entries, count }).into_response()
}

/// POST /api/export -- Requires Bearer token + HMAC authentication.
///
/// Receives entries from an OMEGA curator and stores them. Handles
/// deduplication via content_hash comparison.
///
/// This handler accepts raw bytes to perform HMAC verification before
/// JSON deserialization. The HMAC signature is computed over
/// `<timestamp>.<body>` and verified using the shared HMAC key.
pub async fn export(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    body: Bytes,
) -> impl IntoResponse {
    if !state.rate_limiter.check() {
        return (
            StatusCode::TOO_MANY_REQUESTS,
            Json(serde_json::json!({"error": "Rate limit exceeded (100 req/min)"})),
        )
            .into_response();
    }

    // Enforce body size limit (1MB)
    if body.len() > 1_048_576 {
        return (
            StatusCode::PAYLOAD_TOO_LARGE,
            Json(serde_json::json!({"error": "Request body too large (max 1MB)"})),
        )
            .into_response();
    }

    // HMAC verification
    let signature = headers
        .get("x-cortex-signature")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    let timestamp = headers
        .get("x-cortex-timestamp")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    if signature.is_empty() || timestamp.is_empty() {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "Missing HMAC signature or timestamp headers"})),
        )
            .into_response();
    }

    if !auth::check_timestamp(timestamp) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "Request timestamp outside acceptable window (5 min)"})),
        )
            .into_response();
    }

    if !auth::verify_hmac(&body, signature, timestamp, &state.hmac_key) {
        return (
            StatusCode::UNAUTHORIZED,
            Json(serde_json::json!({"error": "Invalid HMAC signature"})),
        )
            .into_response();
    }

    // Deserialize JSON body
    let payload: ExportRequest = match serde_json::from_slice(&body) {
        Ok(p) => p,
        Err(e) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(serde_json::json!({"error": format!("Invalid JSON: {e}")})),
            )
                .into_response();
        }
    };

    // Validate entries
    let mut valid_entries: Vec<SharedEntry> = Vec::new();
    let mut errors: Vec<String> = Vec::new();

    for entry in &payload.entries {
        if entry.uuid.is_empty() {
            errors.push("Entry missing uuid".to_string());
            continue;
        }
        if entry.category.is_empty() {
            errors.push(format!("Entry {} missing category", entry.uuid));
            continue;
        }
        if entry.content_hash.is_empty() {
            errors.push(format!("Entry {} missing content_hash", entry.uuid));
            continue;
        }
        valid_entries.push(entry.clone());
    }

    match state.db.insert_entries(&valid_entries) {
        Ok((exported, reinforced, mut db_errors)) => {
            errors.append(&mut db_errors);
            Json(ExportResponse {
                exported,
                reinforced,
                errors,
            })
            .into_response()
        }
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(serde_json::json!({"error": format!("Database error: {e}")})),
        )
            .into_response(),
    }
}

