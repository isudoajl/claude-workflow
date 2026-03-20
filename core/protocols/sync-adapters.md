<!-- @INDEX
INTERFACE                                15-81
GIT-JSONL-ADAPTER                        82-130
CLOUD-ADAPTER                            131-165
SELF-HOSTED-ADAPTER                      166-254
CONFIGURATION                            255-321
ERROR-HANDLING                           322-366
MIDDLEWARE                               370-549
@/INDEX -->

# Sync Adapter Abstraction

The Sync Adapter layer decouples OMEGA Cortex's curation and import logic from the underlying storage backend. All backends implement the same interface, making the curator and briefing hook adapter-agnostic.

---
## INTERFACE

The adapter interface defines four methods that every backend must implement. These are specified as a contract -- actual implementations live in the curator agent (export), briefing hook (import), and future adapter code (cloud/self-hosted).

### Methods

#### `export(entries: Entry[]) -> ExportResult`

Takes a list of curated entries (already evaluated, deduplicated, and signed by the curator) and writes them to the configured backend.

**Parameters:**
- `entries` -- Array of entry objects. Each entry has: `uuid`, `contributor`, `source_project`, `created_at`, `confidence`, `content_hash`, `signature`, plus category-specific fields (see `cortex-protocol.md` SHARED-STORE-FORMAT section).

**Returns:** `ExportResult`
```
ExportResult {
  exported: int       -- number of new entries written
  reinforced: int     -- number of existing entries reinforced (content_hash match)
  errors: string[]    -- list of error messages (empty on success)
}
```

#### `import(since: Timestamp?) -> Entry[]`

Reads entries from the backend. Optionally filters to only entries created or updated after the `since` timestamp.

**Parameters:**
- `since` -- Optional ISO 8601 timestamp. If provided, only return entries newer than this time. If omitted, return all entries (subject to backend-specific limits).

**Returns:** `Entry[]` -- Array of entry objects to import into the local session briefing.

#### `status() -> BackendStats`

Returns statistics about the current backend state.

**Returns:** `BackendStats`
```
BackendStats {
  backend: string                -- adapter name (e.g., "git-jsonl", "cloudflare-d1", "self-hosted")
  counts: {category: int}       -- entry counts per category (behavioral_learnings, incidents, hotspots, lessons, patterns, decisions)
  last_sync: timestamp           -- ISO 8601 timestamp of last successful sync (export or import)
}
```

#### `health() -> HealthResult`

Checks whether the backend is available and operational.

**Returns:** `HealthResult`
```
HealthResult {
  healthy: bool       -- true if backend is reachable and writable
  message: string     -- human-readable status message
  latency_ms: int     -- round-trip time in milliseconds (0 for local backends)
}
```

### Entry Lifecycle

```
memory.db -> Curator (evaluate, deduplicate, sign) -> Adapter.export() -> Backend
Backend -> Adapter.import() -> Briefing Hook -> Session context
```

The curator's curation logic (confidence thresholds, privacy checks, content validation, HMAC signing, deduplication, conflict detection) is **adapter-agnostic**. It produces a list of ready-to-export entries. The adapter handles only transport and storage.

---
## GIT-JSONL-ADAPTER

The Git JSONL adapter is the **default backend**. It wraps the existing Phase 1-3 behavior (Modules 2-7) into the adapter interface pattern. Zero configuration required.

### How It Maps to the Interface

#### `export(entries) -> ExportResult`

Writes curated entries to `.omega/shared/` as JSONL and JSON files:
- `behavioral-learnings.jsonl` -- one JSON object per line
- `incidents/INC-NNN.json` -- one file per resolved incident
- `hotspots.jsonl` -- one JSON object per line
- `lessons.jsonl` -- one JSON object per line
- `patterns.jsonl` -- one JSON object per line
- `decisions.jsonl` -- one JSON object per line

This is the existing curator behavior from Phase 1-3, unchanged. The export writes locally; developers push via normal `git push`.

**Deduplication**: Uses `content_hash` comparison against existing JSONL entries. Matching entries are reinforced (occurrences bumped, confidence updated). New entries are appended. See `cortex-protocol.md` CURATION-RULES section.

#### `import(since?) -> Entry[]`

Reads entries from `.omega/shared/` JSONL/JSON files. The `since` parameter filters entries by `created_at` timestamp. Already-imported entries (tracked in `shared_imports` table) are skipped.

This is the existing briefing.sh import behavior from Phase 3, unchanged. Developers pull new entries via normal `git pull`.

#### `status() -> BackendStats`

- Counts entries per JSONL file by counting non-empty lines
- Lists incident JSON files in `.omega/shared/incidents/`
- Reports `last_sync` from the most recent file modification timestamp in `.omega/shared/`

#### `health() -> HealthResult`

- Checks `.omega/shared/` directory exists
- Checks directory is writable (`test -w`)
- Always returns `latency_ms: 0` (local filesystem)
- Returns `healthy: true` if directory exists and is writable

### Sync Mechanism

The Git JSONL adapter uses **git-native sync**:
- Export: curator writes to `.omega/shared/` files locally
- Sync to team: developer runs `git add .omega/shared/ && git commit && git push`
- Import: briefing.sh reads from `.omega/shared/` files after `git pull`

No additional sync mechanism is needed. Git handles distribution.

---
## CLOUD-ADAPTER

Implemented in M9 (REQ-CTX-041, REQ-CTX-042). The Cloud Adapter connects to Cloudflare D1 (primary) or Turso/libSQL (alternative) via REST API for real-time sync without git dependencies. Authentication uses Bearer token from env var `OMEGA_CORTEX_CF_TOKEN` (D1) or `OMEGA_CORTEX_TURSO_TOKEN` (Turso). All API calls require HTTPS.

### Cloudflare D1 -- Interface Mapping

**API endpoint**: `https://api.cloudflare.com/client/v4/accounts/{account_id}/d1/database/{database_id}/query`

- `export(entries)` -- POST SQL INSERT statements to D1 via REST API. Batch INSERTs (max 50 per API call) to respect Cloudflare rate limits.
- `import(since?)` -- POST SQL SELECT queries to D1. Filter with `WHERE created_at > ?` for incremental import.
- `status()` -- POST `SELECT COUNT(*) ... GROUP BY category` to D1 to retrieve entry counts per category.
- `health()` -- GET database metadata endpoint to verify 200 OK response and measure latency.

**Error handling**: HTTP 429 (rate limited) triggers exponential backoff. HTTP 5xx triggers retry (max 3 attempts), then fail gracefully to pending-exports cache. See ERROR-HANDLING section.

### D1 Table Schema

Tables mirror the JSONL shared store structure. All tables use `CREATE TABLE IF NOT EXISTS` for idempotent provisioning (REQ-CTX-049).

- `shared_behavioral_learnings(uuid, contributor, source_project, created_at, confidence, occurrences, content_hash, signature, rule, context, status)`
- `shared_incidents(incident_id, title, domain, status, contributor, created_at, resolved_at, root_cause, resolution, entries_json, signature)`
- `shared_hotspots(uuid, file_path, risk_level, times_touched, contributors_json, contributor_count, description)`
- `shared_lessons(uuid, contributor, source_project, created_at, confidence, occurrences, content_hash, signature, lesson, context, domain)`
- `shared_patterns(uuid, contributor, source_project, created_at, confidence, occurrences, content_hash, signature, pattern, context, domain)`
- `shared_decisions(uuid, contributor, source_project, created_at, confidence, occurrences, content_hash, signature, decision, rationale, context)`

### Turso Adapter

Same SQL interface as D1 but via Turso HTTP API. URL format: `libsql://{database}.turso.io`. Auth: Bearer token from `OMEGA_CORTEX_TURSO_TOKEN`. Same table schema as D1. Turso-specific: embedded replicas for offline-first usage (future enhancement).

### Configuration

See CONFIGURATION section below for `cloudflare-d1` and `turso` config fields.

---
## SELF-HOSTED-ADAPTER

**Status: Implemented -- Phase 4, Milestone M11 (REQ-CTX-043, REQ-CTX-050)**

The Self-Hosted Adapter connects to a Rust-based HTTP bridge server (`extensions/cortex-bridge/`) for teams wanting full data sovereignty. The bridge is built with axum + tokio + rusqlite, using ring for HMAC and rustls for TLS. No OpenSSL dependency.

### Interface Mapping

#### `export(entries) -> ExportResult`

HTTP POST to the bridge server's `/api/export` endpoint.

```
POST /api/export
Authorization: Bearer <token>
X-Cortex-Signature: hmac-sha256=<hex_digest>
X-Cortex-Timestamp: <unix_epoch_seconds>
Content-Type: application/json

{"entries": [<SharedEntry>, ...]}
```

The HMAC signature is computed as `HMAC-SHA256(key, "<timestamp>.<body>")`. The bridge server verifies the signature, checks the timestamp is within 5 minutes (replay protection), then inserts entries with content_hash-based deduplication. Duplicate entries are reinforced (occurrences bumped, confidence boosted).

**Response:** `{"exported": 3, "reinforced": 1, "errors": []}`

#### `import(since?) -> Entry[]`

HTTP GET from the bridge server's `/api/import` endpoint.

```
GET /api/import?since=2026-03-20T15:00:00Z
Authorization: Bearer <token>
```

Returns entries created after the `since` timestamp. If `since` is omitted, returns all entries. Results are ordered by `created_at` ASC for deterministic import.

**Response:** `{"entries": [...], "count": 15}`

#### `status() -> BackendStats`

HTTP GET from the bridge server's `/api/status` endpoint.

```
GET /api/status
Authorization: Bearer <token>
```

Returns entry counts grouped by category and the last sync timestamp.

**Response:** `{"backend": "self-hosted", "counts": {"behavioral_learnings": 42}, "last_sync": "2026-03-20T15:00:00Z"}`

#### `health() -> HealthResult`

HTTP GET from the bridge server's `/api/health` endpoint. No authentication required.

```
GET /api/health
```

**Response:** `{"healthy": true, "version": "0.1.0", "uptime_seconds": 3600}`

### Authentication

Dual authentication is required for write operations:

1. **Bearer token** -- `Authorization: Bearer <token>` header, constant-time comparison via HMAC-based equality check (prevents timing side-channels)
2. **HMAC-SHA256** (export only) -- `X-Cortex-Signature: hmac-sha256=<hex>` + `X-Cortex-Timestamp: <unix_seconds>`, computed over `<timestamp>.<body>`, verified using shared HMAC key
3. **Replay protection** -- requests with timestamps older than 5 minutes are rejected
4. **Rate limiting** -- 100 requests per minute globally, returns HTTP 429 when exceeded
5. **Body size limit** -- 1MB maximum request body

Read-only endpoints (`/api/health`, `/api/status`, `/api/import`) require only Bearer token authentication. `/api/health` requires no authentication.

### Deployment

The bridge server is packaged in `extensions/cortex-bridge/` with three deployment options:

1. **Docker** (recommended) -- `docker compose up -d` with env vars in `.env`
2. **Bare metal** -- `cargo build --release` + systemd service unit
3. **TLS** -- set `CORTEX_BRIDGE_TLS_CERT` and `CORTEX_BRIDGE_TLS_KEY` for rustls

See `extensions/cortex-bridge/README.md` for full deployment guide.

### Configuration

See CONFIGURATION section below for `self-hosted` config fields.

---
## CONFIGURATION

Backend selection is configured via `.omega/cortex-config.json` in the project root.

### Config File Location

`.omega/cortex-config.json`

This file is **gitignored** (it may contain credential references). Each developer configures their own backend locally.

### Config Format

```json
{
  "backend": "git-jsonl",
  "git-jsonl": {},
  "cloudflare-d1": {
    "account_id": "your-cloudflare-account-id",
    "database_id": "your-d1-database-id",
    "api_token_env": "OMEGA_CORTEX_CF_TOKEN"
  },
  "turso": {
    "url": "libsql://your-db.turso.io",
    "auth_token_env": "OMEGA_CORTEX_TURSO_TOKEN"
  },
  "self-hosted": {
    "endpoint_url": "https://cortex-bridge.your-domain.com",
    "auth_token_env": "OMEGA_CORTEX_BRIDGE_TOKEN"
  }
}
```

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `backend` | string | Yes | Active backend: `"git-jsonl"`, `"cloudflare-d1"`, `"turso"`, `"self-hosted"` |
| `git-jsonl` | object | No | Git JSONL adapter options (currently empty -- no config needed) |
| `cloudflare-d1.account_id` | string | For D1 | Cloudflare account ID |
| `cloudflare-d1.database_id` | string | For D1 | D1 database ID |
| `cloudflare-d1.api_token_env` | string | For D1 | Environment variable name holding the API token |
| `turso.url` | string | For Turso | Turso database URL |
| `turso.auth_token_env` | string | For Turso | Environment variable name holding the auth token |
| `self-hosted.endpoint_url` | string | For bridge | Bridge server URL |
| `self-hosted.auth_token_env` | string | For bridge | Environment variable name holding the auth token |

### Default Behavior (Zero Config)

If `.omega/cortex-config.json` does **not exist**, the system defaults to `git-jsonl`. This ensures:
- Backward compatibility with Phase 1-3 deployments
- Zero configuration required for the default workflow
- Existing projects continue working without any changes

The `git-jsonl` backend requires no configuration fields -- the empty `{}` object is optional.

### Backend Selection Logic

```
1. Read .omega/cortex-config.json
2. If file missing or parse error: use "git-jsonl" (default)
3. Read "backend" field
4. If "backend" field missing: use "git-jsonl" (default)
5. Route to the matching adapter
6. If unknown backend value: log warning, fall back to "git-jsonl"
```

---
## ERROR-HANDLING

All adapters must be error-tolerant. A backend failure must never crash OMEGA or block local work.

### Principles

1. **Never crash** -- adapter errors are logged, not thrown
2. **Degrade gracefully** -- if the configured backend fails, fall back to local-only operation
3. **Cache pending work** -- failed exports are saved for retry
4. **Inform the user** -- log warnings so developers know sync is degraded

### Failed Export

When `export()` fails (network error, permission denied, API error):
1. Cache the failed entries in `.omega/.pending-exports.jsonl` (gitignored)
2. Each cached line: `{"category": "...", "entry": {...}, "backend": "...", "queued_at": "...", "error": "..."}`
3. On next `/omega:share` run, attempt to flush pending exports first
4. Maximum 500 pending entries -- oldest are dropped if exceeded

### Failed Import

When `import()` fails:
1. Use local data only (memory.db behavioral learnings, no shared knowledge)
2. Skip the shared import section in briefing output
3. Log a warning: `"[CORTEX] Import failed: {error}. Using local data only."`
4. Do NOT retry during the same session -- wait for next session

### Unhealthy Backend

When `health()` returns `healthy: false`:
1. Log a warning with the health message
2. If the configured backend is NOT `git-jsonl` and `git-jsonl` is available as fallback:
   - Log: `"[CORTEX] Backend '{name}' unhealthy. Falling back to git-jsonl."`
   - Use `git-jsonl` for this session only (do not change cortex-config.json)
3. If `git-jsonl` is also unhealthy (`.omega/shared/` missing or not writable):
   - Operate in local-only mode
   - Log: `"[CORTEX] No backend available. Operating in local-only mode."`

### Error Logging

All adapter errors are logged to memory.db `outcomes` table:
```sql
INSERT INTO outcomes (action, result, context, agent, score)
VALUES ('cortex_sync', 'error', '{error_details}', 'curator', -1);
```

---
## MIDDLEWARE

The middleware pipeline sits between the curator's output and the adapter's transport layer. It handles format transformation, batching, retry logic, conflict pre-checking, and offline caching. The middleware is adapter-agnostic -- the same pipeline runs for all backends.

### Pipeline Flow

```
Curator Output -> Format Transform -> Batch -> Conflict Pre-check -> Adapter.export()
                                                                          |
                                                                    If fails: Cache
                                                                          |
                                                                          v
                                                              .omega/.pending-exports.jsonl
```

### Format Transformation

Converts memory.db rows into adapter entry format. Each entry is a JSON object with:

- **Common fields**: `uuid`, `contributor`, `source_project`, `created_at`, `confidence`, `content_hash`, `signature`
- **Category-specific fields**: Varies by entry type (e.g., `rule` + `context` for behavioral learnings, `lesson` + `domain` for lessons, `pattern` + `context` for patterns, `decision` + `rationale` for decisions)

The Format Transform step normalizes memory.db column names to the shared entry schema, ensures all required fields are present, and generates `content_hash` if not already set. Output is a list of JSON objects ready for batching.

### Batching

Groups entries for efficient API calls:

- **Cloud backends** (cloudflare-d1, turso): max 50 per batch to respect rate limits
- **Self-hosted backends**: max 50 per batch for consistency
- **Git JSONL**: unlimited (local filesystem, no API rate limits)

Entries are grouped by category first, then split into batches of the configured size. Each batch is a single API call (cloud/self-hosted) or a single file append (git-jsonl).

### Retry on Failure

When an adapter's `export()` call fails, the middleware retries with exponential backoff:

- **Max 3 retries** per batch
- **Backoff schedule**: 1s, 2s, 4s (exponential)
- **Retryable errors**: network timeout, HTTP 429 (rate limited), HTTP 5xx (server error)
- **Non-retryable errors**: HTTP 400 (bad request), HTTP 401/403 (auth failure) -- fail immediately

If all 3 retries are exhausted, the failed batch is cached locally (see Offline Cache below).

### Conflict Pre-check

Before exporting, the middleware verifies no `content_hash` collision exists in the target backend:

1. For each entry, check if an entry with the same `content_hash` already exists in the backend
2. If a match is found: reinforce the existing entry (bump occurrences, update confidence) instead of creating a duplicate
3. If no match: proceed with export as a new entry

This prevents duplicate entries across team members who independently discover the same knowledge. The pre-check uses the adapter's `import()` method with a narrow scope or a dedicated hash-check query.

### Offline Cache

If the backend is unavailable after all retries are exhausted, entries are cached locally:

- **Cache file**: `.omega/.pending-exports.jsonl` (gitignored -- local-only, transient)
- **Format**: One JSON object per line: `{"category": "...", "entry": {...}, "backend": "...", "queued_at": "...", "error": "..."}`
- **Max entries**: 500 pending entries. Oldest are dropped if exceeded.

### Pending Flush

On the next successful connection to the backend, pending exports are flushed before any new exports:

1. Read `.omega/.pending-exports.jsonl`
2. Attempt to export each pending entry through the full middleware pipeline (format, batch, conflict check)
3. On success: remove the entry from the pending file
4. On failure: leave the entry in the pending file for the next attempt
5. After flushing (or if no pending entries), proceed with new exports

This ensures entries are never lost and are delivered in order of original creation.

---

### Real-Time Import

For cloud and self-hosted backends, the briefing hook performs a real-time HTTP pull instead of reading `.omega/shared/` files.

#### Backend Detection

`briefing.sh` reads `cortex-config.json` to determine the active backend:

- If `git-jsonl` (or no config): use existing file-based import from `.omega/shared/` (unchanged)
- If `cloudflare-d1`, `turso`, or `self-hosted`: use HTTP pull via `curl`

#### HTTP Pull

For cloud/self-hosted backends, import uses HTTP:

```
curl -s --max-time 5 \
  -H "Authorization: Bearer $TOKEN" \
  "$ENDPOINT/import?since=$LAST_SYNC_TIMESTAMP"
```

- **Incremental**: Uses `last_sync_timestamp` from `cortex_sync_state` table to fetch only new entries
- **Timeout**: 5 seconds max for HTTP calls (briefing must not block)
- **Response**: JSON array of entries matching the shared entry schema

#### Sync State Tracking

The `cortex_sync_state` table in memory.db tracks sync progress:

- `backend`: active backend name
- `last_sync_at`: timestamp of last successful import
- `last_export_at`: timestamp of last successful export
- `pending_count`: number of entries in `.omega/.pending-exports.jsonl`

Updated after every successful import or export operation.

#### Fallback Chain

If the primary import method fails, the system falls back gracefully:

1. **HTTP pull** (cloud/self-hosted) -- primary for non-git backends
2. **`.omega/shared/` files** -- fallback if HTTP fails and files exist
3. **Skip import** -- if both fail, proceed with local data only
4. **Local only** -- memory.db is always available regardless

The fallback chain ensures briefing never blocks or errors. Log: `"Cortex backend unavailable -- using local knowledge only"`

---

### Offline-First Resilience

Core invariant: local memory.db is always functional regardless of backend status. OMEGA never degrades local functionality due to backend availability.

#### Per-Backend Offline Behavior

- **Git JSONL**: inherently offline-first. Files are local; sync happens via git push/pull. No network dependency for local operations.
- **Cloud backends** (cloudflare-d1, turso): exports queued in `.omega/.pending-exports.jsonl` when offline. On next session with connectivity, pending exports are flushed to the backend.
- **Self-hosted bridge**: same as cloud -- queue exports locally, flush when connectivity returns.

#### Offline Guarantees

The cardinal rules: never error, never block, never degrade local OMEGA functionality.

1. **Never error** -- adapter errors are caught and logged, never propagated
2. **Never block** -- HTTP timeouts are capped at 5 seconds; all operations have bounded execution time
3. **Never degrade local OMEGA** -- all local features (memory.db queries, behavioral learnings, incident tracking, lessons, patterns) work identically whether online or offline
4. **Queue, don't drop** -- failed exports are cached for retry, not discarded

#### Import Offline Behavior

When the backend is unreachable during import:
- Use last-known local data from memory.db
- Skip shared import section in briefing output
- Log info: `"Cortex backend unavailable -- using local knowledge only"`
- Do NOT retry during the same session -- wait for next session

---

### Backend Migration

The `/omega:cortex-migrate` command enables migration between backend types.

#### Usage

```
/omega:cortex-migrate --from=git --to=cloudflare-d1
/omega:cortex-migrate --from=cloudflare-d1 --to=turso
/omega:cortex-migrate --from=turso --to=self-hosted
```

#### Migration Flow

1. Read all entries from the source backend via `import(since=epoch)` (i.e., `since=1970-01-01T00:00:00Z`)
2. Write all entries to the target backend via `export(entries)` through the full middleware pipeline
3. Validate completeness: count comparison between source and target entry counts
4. Report results: entries migrated, entries skipped (already in target), errors

#### Guarantees

- **Non-destructive**: source data is always preserved after migration
- **Deduplication-aware**: uses content_hash to skip entries already present in the target
- **Resumable**: if migration fails partway, re-running picks up where it left off (dedup prevents duplicates)
- **Any-to-any**: supports migration between any two backends (git-jsonl, cloudflare-d1, turso, self-hosted)
