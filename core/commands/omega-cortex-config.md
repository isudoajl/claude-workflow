---
name: omega:cortex-config
description: "Configure the OMEGA Cortex sync backend. Interactively select between git-jsonl (default), cloudflare-d1, turso, or self-hosted backends. Validates connectivity via health check before saving. Supports --show to display current config and --reset to revert to default."
---

# Workflow: Cortex Config

Configure the OMEGA Cortex sync backend for this project. Manages `.omega/cortex-config.json` which controls how shared knowledge is stored and synced across team members.

## Pipeline Tracking

Register a `workflow_runs` entry at the start:

```sql
INSERT INTO workflow_runs (type, description, scope, status)
VALUES ('cortex-config', 'Configure Cortex sync backend', 'project', 'running');
```

At completion, UPDATE the workflow_runs entry:

```sql
UPDATE workflow_runs
SET status = 'completed', completed_at = datetime('now')
WHERE id = $RUN_ID;
```

## Flags

- `--show` -- Display current configuration. Mask sensitive values: show env var names but not actual token values. If no config exists, display "No configuration -- using git-jsonl default."
- `--reset` -- Remove `.omega/cortex-config.json` and revert to the git-jsonl default backend. Confirm before deleting.

## Interactive Flow

### Step 1: Show Current Configuration

Display the current backend configuration (or "No configuration -- using git-jsonl default" if no `.omega/cortex-config.json` exists).

### Step 2: Present Backend Options

| Option | Backend | Description |
|--------|---------|-------------|
| 1 | `git-jsonl` | Default, zero infrastructure. Git handles sync via normal push/pull. |
| 2 | `cloudflare-d1` | Real-time sync, managed by Cloudflare. Requires Cloudflare account. |
| 3 | `turso` | Real-time sync, edge-distributed. Requires Turso account. |
| 4 | `self-hosted` | Real-time sync, self-sovereign. Requires VPS with bridge server. |

### Step 3: Collect Backend-Specific Configuration

**git-jsonl**: No configuration needed. Uses `.omega/shared/` directory with git-native sync.

**cloudflare-d1**:
- `account_id` -- Cloudflare account ID
- `database_id` -- D1 database ID
- `api_token_env` -- Environment variable name holding the API token (default: `OMEGA_CORTEX_CF_TOKEN`). The env var name is stored in config, never the actual token. Tokens are not plaintext in config.

**turso**:
- `url` -- Turso database URL (format: `libsql://your-db.turso.io`)
- `auth_token_env` -- Environment variable name holding the auth token (default: `OMEGA_CORTEX_TURSO_TOKEN`). The env var name is stored in config, never the actual token.

**self-hosted**:
- `endpoint_url` -- Bridge server URL (must use `https://`)
- `auth_token_env` -- Environment variable name holding the auth token (default: `OMEGA_CORTEX_BRIDGE_TOKEN`). The env var name is stored in config, never the actual token.

### Step 4: Run Health Check

Validate connectivity before saving configuration:

- **git-jsonl**: Check `.omega/shared/` exists and is writable
- **cloudflare-d1**: POST a test query to D1 API, verify 200 OK. Validate TLS certificate.
- **turso**: POST a test query to Turso HTTP API, verify response. Validate TLS certificate.
- **self-hosted**: GET `{endpoint_url}/api/v1/health`, verify 200 OK. Validate TLS certificate.

If the health check fails, display the error and ask whether to save anyway or retry.

### Step 5: D1 Schema Provisioning (cloudflare-d1 only)

For the cloudflare-d1 backend, after a successful health check, offer to provision the D1 database schema:

"Provision database schema? This creates the required D1 tables if they don't exist."

The provisioning runs idempotent SQL via the D1 API (`CREATE TABLE IF NOT EXISTS`):

- `shared_behavioral_learnings` -- uuid, contributor, source_project, created_at, confidence, occurrences, content_hash, signature, rule, context, status
- `shared_incidents` -- incident_id, title, domain, status, contributor, created_at, resolved_at, root_cause, resolution, entries_json, signature
- `shared_hotspots` -- uuid, file_path, risk_level, times_touched, contributors_json, contributor_count, description
- `shared_lessons` -- uuid, contributor, source_project, created_at, confidence, occurrences, content_hash, signature, lesson, context, domain
- `shared_patterns` -- uuid, contributor, source_project, created_at, confidence, occurrences, content_hash, signature, pattern, context, domain
- `shared_decisions` -- uuid, contributor, source_project, created_at, confidence, occurrences, content_hash, signature, decision, rationale, context

### Step 6: Save Configuration

Write `.omega/cortex-config.json`:

```json
{
  "backend": "cloudflare-d1",
  "cloudflare-d1": {
    "account_id": "your-account-id",
    "database_id": "your-database-id",
    "api_token_env": "OMEGA_CORTEX_CF_TOKEN"
  }
}
```

### Step 7: Confirm

Display: "Backend configured. Run /omega:share to test."

## Security

- **API tokens are stored as env var names in config, never actual tokens.** The config file records `"api_token_env": "OMEGA_CORTEX_CF_TOKEN"` -- at runtime, the adapter reads `$OMEGA_CORTEX_CF_TOKEN` from the environment.
- **cortex-config.json is gitignored.** Added by `setup.sh` to `.gitignore` (may contain credential references like account IDs).
- **TLS required.** All cloud/self-hosted backends must use HTTPS. The health check validates TLS certificate chain. No `--insecure` or self-signed certs in production.
- **Token env vars should be set in shell profile** (`.bashrc`, `.zshrc`, etc.) or CI/CD secrets -- never committed to version control.

## --show Flag Behavior

When `--show` is passed:
1. Read `.omega/cortex-config.json`
2. If missing: display "No configuration -- using git-jsonl default"
3. If present: display the config with sensitive values masked:
   - Show backend type
   - Show env var names (e.g., `api_token_env: OMEGA_CORTEX_CF_TOKEN`)
   - Mask account_id/database_id partially (e.g., `abc...xyz`)
   - Show endpoint URLs

## --reset Flag Behavior

When `--reset` is passed:
1. Check if `.omega/cortex-config.json` exists
2. If missing: display "No configuration to reset -- already using git-jsonl default"
3. If present: confirm deletion, remove the file, display "Configuration reset. Using git-jsonl default."

## Institutional Memory Protocol

- **Briefing**: Query memory.db for previous cortex-config runs and known backend issues.
- **Incremental logging**: Log backend selection and health check results to memory.db.
- **Close-out**: Record final configuration state and any errors encountered.

## Error Handling

- If `.omega/` directory does not exist, create it before saving config
- If health check fails: display error, offer to save anyway or retry
- If D1 provisioning fails: log warning, save config without provisioning (user can re-run later)
- If config file is malformed: warn and offer to overwrite with fresh config
