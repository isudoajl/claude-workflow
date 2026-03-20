// models.rs -- Data models for the Cortex Bridge server
//
// These structs define the shared entry format that flows between
// OMEGA clients and the bridge server. They mirror the JSONL format
// defined in cortex-protocol.md SHARED-STORE-FORMAT section.

use serde::{Deserialize, Serialize};

/// A shared knowledge entry from an OMEGA contributor.
///
/// Category-specific fields are stored in the `data` field as
/// arbitrary JSON, keeping the model flexible across all entry types
/// (behavioral_learning, incident, hotspot, lesson, pattern, decision).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedEntry {
    pub uuid: String,
    pub category: String,
    pub contributor: String,
    pub source_project: String,
    pub created_at: String,
    pub confidence: f64,
    pub occurrences: i32,
    pub content_hash: String,
    pub signature: Option<String>,
    /// Category-specific fields (rule, context, lesson, etc.)
    #[serde(default)]
    pub data: serde_json::Value,
}

/// Request body for POST /api/export
#[derive(Debug, Deserialize)]
pub struct ExportRequest {
    pub entries: Vec<SharedEntry>,
}

/// Response body for POST /api/export
#[derive(Debug, Serialize)]
pub struct ExportResponse {
    pub exported: usize,
    pub reinforced: usize,
    pub errors: Vec<String>,
}

/// Response body for GET /api/import
#[derive(Debug, Serialize)]
pub struct ImportResponse {
    pub entries: Vec<SharedEntry>,
    pub count: usize,
}

/// Response body for GET /api/health
#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub healthy: bool,
    pub version: String,
    pub uptime_seconds: u64,
}

/// Response body for GET /api/status
#[derive(Debug, Serialize)]
pub struct StatusResponse {
    pub backend: String,
    pub counts: std::collections::HashMap<String, i64>,
    pub last_sync: Option<String>,
}
