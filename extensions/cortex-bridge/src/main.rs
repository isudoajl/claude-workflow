// Cortex Bridge -- Self-hosted OMEGA Cortex sync server
//
// A lightweight HTTP server that receives shared knowledge from OMEGA
// curator agents and serves it to OMEGA briefing hooks. Replaces the
// git push/pull cycle with real-time HTTP API calls.
//
// Architecture: axum + tokio + rusqlite (SQLite)
// Authentication: Bearer token + HMAC-SHA256 signature
// Security: TLS via rustls, replay protection, rate limiting
//
// See: core/protocols/sync-adapters.md SELF-HOSTED-ADAPTER section

use axum::middleware;
use axum::routing::{get, post};
use axum::Router;
use std::sync::Arc;
use std::time::Instant;
use tokio::net::TcpListener;

mod auth;
mod config;
mod models;
mod routes;
mod storage;

#[tokio::main]
async fn main() {
    let config = config::Config::from_env();
    let db = storage::Database::new(&config.db_path).expect("Failed to initialize database");

    let state = Arc::new(routes::AppState {
        db,
        auth_token: config.auth_token.clone(),
        hmac_key: config.hmac_key.clone(),
        start_time: Instant::now(),
        rate_limiter: routes::RateLimiter::new(100),
    });

    // Health endpoint -- no auth required
    let health_routes = Router::new().route("/api/health", get(routes::health));

    // Authenticated routes -- Bearer token required
    let auth_routes = Router::new()
        .route("/api/status", get(routes::status))
        .route("/api/import", get(routes::import_entries))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            auth::bearer_auth_middleware,
        ));

    // Export route -- Bearer token + HMAC required
    // Note: HMAC verification is done inside the handler since it
    // needs to consume the body for signature verification, then
    // pass it to the JSON extractor.
    let export_routes = Router::new()
        .route("/api/export", post(routes::export))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            auth::bearer_auth_middleware,
        ));

    let app = Router::new()
        .merge(health_routes)
        .merge(auth_routes)
        .merge(export_routes)
        .with_state(state);

    let addr = format!("{}:{}", config.host, config.port);
    println!("Cortex Bridge v{} listening on {addr}", env!("CARGO_PKG_VERSION"));
    println!("  Database: {}", config.db_path);
    println!("  TLS: {}", if config.tls_cert.is_some() { "enabled" } else { "disabled" });

    // TLS support via axum-server + rustls
    if let (Some(cert_path), Some(key_path)) = (&config.tls_cert, &config.tls_key) {
        let tls_config = axum_server::tls_rustls::RustlsConfig::from_pem_file(cert_path, key_path)
            .await
            .expect("Failed to load TLS certificate/key");

        let addr = addr.parse().expect("Invalid bind address");
        axum_server::bind_rustls(addr, tls_config)
            .serve(app.into_make_service())
            .await
            .expect("TLS server failed");
    } else {
        let listener = TcpListener::bind(&addr)
            .await
            .expect("Failed to bind to address");
        axum::serve(listener, app)
            .await
            .expect("Server failed");
    }
}
