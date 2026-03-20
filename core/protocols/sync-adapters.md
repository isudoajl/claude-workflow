<!-- @INDEX
INTERFACE                                15-81
GIT-JSONL-ADAPTER                        82-130
CLOUD-ADAPTER                            131-165
SELF-HOSTED-ADAPTER                      166-185
CONFIGURATION                            186-252
ERROR-HANDLING                           253-297
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

**Status: Planned for Phase 4, Milestone M11 (REQ-CTX-043, REQ-CTX-050)**

The Self-Hosted Adapter will connect to a Rust-based HTTP bridge server (`extensions/cortex-bridge/`) for teams wanting full data sovereignty.

### Planned Interface Mapping

- `export()` -- HTTP POST entries to bridge server `/api/v1/entries`
- `import()` -- HTTP GET entries from bridge server `/api/v1/entries?since=...`
- `status()` -- GET `/api/v1/status` for backend statistics
- `health()` -- GET `/api/v1/health` for availability check

### Configuration

See CONFIGURATION section below for `self-hosted` config fields.

This section will be expanded when M11 is implemented.

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
