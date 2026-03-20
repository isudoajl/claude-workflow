# Cortex Bridge -- Self-Hosted OMEGA Sync Server

A lightweight Rust HTTP server for real-time OMEGA Cortex knowledge sync. Teams deploy this on a VPS for instant knowledge sharing without the git push/pull cycle.

## Quick Start

### Docker (recommended)

```bash
# Set required environment variables
export CORTEX_BRIDGE_TOKEN="your-secret-bearer-token"
export CORTEX_BRIDGE_HMAC_KEY="$(openssl rand -hex 32)"

# Start the server
docker compose up -d

# Verify it's running
curl http://localhost:8443/api/health
```

### Bare Metal

```bash
# Prerequisites: Rust 1.85+
cargo build --release

# Set required environment variables
export CORTEX_BRIDGE_TOKEN="your-secret-bearer-token"
export CORTEX_BRIDGE_HMAC_KEY="$(openssl rand -hex 32)"

# Run
./target/release/cortex-bridge
```

### systemd Service

```ini
[Unit]
Description=Cortex Bridge Server
After=network.target

[Service]
Type=simple
User=cortex-bridge
Environment=CORTEX_BRIDGE_TOKEN=your-secret-bearer-token
Environment=CORTEX_BRIDGE_HMAC_KEY=your-hex-key
Environment=CORTEX_BRIDGE_DB_PATH=/var/lib/cortex-bridge/cortex-bridge.db
ExecStart=/usr/local/bin/cortex-bridge
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

## Configuration

All configuration is via environment variables:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CORTEX_BRIDGE_TOKEN` | Yes | -- | Bearer authentication token |
| `CORTEX_BRIDGE_HMAC_KEY` | Yes | -- | HMAC-SHA256 signing key (hex string) |
| `CORTEX_BRIDGE_HOST` | No | `0.0.0.0` | Bind address |
| `CORTEX_BRIDGE_PORT` | No | `8443` | Bind port |
| `CORTEX_BRIDGE_DB_PATH` | No | `./cortex-bridge.db` | SQLite database path |
| `CORTEX_BRIDGE_TLS_CERT` | No | -- | TLS certificate PEM file |
| `CORTEX_BRIDGE_TLS_KEY` | No | -- | TLS private key PEM file |

## API Endpoints

### `GET /api/health` -- No auth

Returns server health status.

```json
{"healthy": true, "version": "0.1.0", "uptime_seconds": 3600}
```

### `GET /api/status` -- Bearer token

Returns entry counts and last sync time.

```json
{
  "backend": "self-hosted",
  "counts": {"behavioral_learnings": 42, "incidents": 5},
  "last_sync": "2026-03-20T15:00:00Z"
}
```

### `POST /api/export` -- Bearer + HMAC

Receives entries from OMEGA curator.

**Headers:**
- `Authorization: Bearer <token>`
- `X-Cortex-Signature: hmac-sha256=<hex_digest>`
- `X-Cortex-Timestamp: <unix_epoch_seconds>`

**Body:**
```json
{"entries": [{"category": "behavioral_learning", "uuid": "...", ...}]}
```

**Response:**
```json
{"exported": 3, "reinforced": 1, "errors": []}
```

### `GET /api/import?since=2026-03-20T15:00:00Z` -- Bearer token

Returns entries created after the given timestamp.

```json
{"entries": [...], "count": 15}
```

## Authentication

The bridge uses dual authentication:

1. **Bearer token** -- constant-time comparison of `Authorization` header
2. **HMAC-SHA256** (export only) -- signature over `<timestamp>.<body>` using shared key

Requests with timestamps older than 5 minutes are rejected (replay protection).

## TLS

For production, enable TLS by setting `CORTEX_BRIDGE_TLS_CERT` and `CORTEX_BRIDGE_TLS_KEY`. Uses rustls (pure Rust, no OpenSSL dependency).

With Let's Encrypt:
```bash
export CORTEX_BRIDGE_TLS_CERT=/etc/letsencrypt/live/your-domain/fullchain.pem
export CORTEX_BRIDGE_TLS_KEY=/etc/letsencrypt/live/your-domain/privkey.pem
```

## OMEGA Client Configuration

In your project's `.omega/cortex-config.json`:

```json
{
  "backend": "self-hosted",
  "self-hosted": {
    "endpoint_url": "https://cortex-bridge.your-domain.com:8443",
    "auth_token_env": "OMEGA_CORTEX_BRIDGE_TOKEN"
  }
}
```

## Rate Limiting

The server enforces 100 requests per minute globally. Exceeding this limit returns HTTP 429.
