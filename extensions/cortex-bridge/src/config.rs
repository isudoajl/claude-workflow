// config.rs -- Configuration loading from environment variables
//
// All configuration is read from environment variables at startup.
// Required variables must be set or the server will exit with a
// clear error message. Optional variables have sensible defaults.

use std::env;
use std::process;

/// Server configuration loaded from environment variables.
#[derive(Debug, Clone)]
pub struct Config {
    /// Bind address (default: "0.0.0.0")
    pub host: String,
    /// Bind port (default: "8443")
    pub port: String,
    /// Bearer authentication token (required)
    pub auth_token: String,
    /// HMAC-SHA256 signing key as hex string (required)
    pub hmac_key: String,
    /// SQLite database file path (default: "./cortex-bridge.db")
    pub db_path: String,
    /// Optional TLS certificate file path
    pub tls_cert: Option<String>,
    /// Optional TLS private key file path
    pub tls_key: Option<String>,
}

impl Config {
    /// Load configuration from environment variables.
    ///
    /// Required:
    /// - `CORTEX_BRIDGE_TOKEN` -- Bearer auth token
    /// - `CORTEX_BRIDGE_HMAC_KEY` -- HMAC signing key (hex)
    ///
    /// Optional:
    /// - `CORTEX_BRIDGE_HOST` (default: "0.0.0.0")
    /// - `CORTEX_BRIDGE_PORT` (default: "8443")
    /// - `CORTEX_BRIDGE_DB_PATH` (default: "./cortex-bridge.db")
    /// - `CORTEX_BRIDGE_TLS_CERT` -- TLS certificate path
    /// - `CORTEX_BRIDGE_TLS_KEY` -- TLS private key path
    pub fn from_env() -> Self {
        let host = env::var("CORTEX_BRIDGE_HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
        let port = env::var("CORTEX_BRIDGE_PORT").unwrap_or_else(|_| "8443".to_string());
        let db_path =
            env::var("CORTEX_BRIDGE_DB_PATH").unwrap_or_else(|_| "./cortex-bridge.db".to_string());

        let auth_token = env::var("CORTEX_BRIDGE_TOKEN").unwrap_or_else(|_| {
            eprintln!("ERROR: CORTEX_BRIDGE_TOKEN environment variable is required");
            process::exit(1);
        });

        let hmac_key = env::var("CORTEX_BRIDGE_HMAC_KEY").unwrap_or_else(|_| {
            eprintln!("ERROR: CORTEX_BRIDGE_HMAC_KEY environment variable is required");
            process::exit(1);
        });

        // Validate HMAC key is valid hex
        if hex_decode(&hmac_key).is_none() {
            eprintln!("ERROR: CORTEX_BRIDGE_HMAC_KEY must be a valid hex string");
            process::exit(1);
        }

        let tls_cert = env::var("CORTEX_BRIDGE_TLS_CERT").ok();
        let tls_key = env::var("CORTEX_BRIDGE_TLS_KEY").ok();

        // Warn if only one TLS parameter is set
        if tls_cert.is_some() != tls_key.is_some() {
            eprintln!("WARNING: Both CORTEX_BRIDGE_TLS_CERT and CORTEX_BRIDGE_TLS_KEY must be set for TLS");
        }

        Config {
            host,
            port,
            auth_token,
            hmac_key,
            db_path,
            tls_cert,
            tls_key,
        }
    }
}

/// Decode a hex string to bytes. Returns None if invalid.
pub fn hex_decode(hex: &str) -> Option<Vec<u8>> {
    if hex.len() % 2 != 0 {
        return None;
    }
    (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).ok())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hex_decode_valid() {
        assert_eq!(hex_decode("deadbeef"), Some(vec![0xde, 0xad, 0xbe, 0xef]));
        assert_eq!(hex_decode("00ff"), Some(vec![0x00, 0xff]));
        assert_eq!(hex_decode(""), Some(vec![]));
    }

    #[test]
    fn test_hex_decode_invalid() {
        assert_eq!(hex_decode("xyz"), None);
        assert_eq!(hex_decode("0"), None); // odd length
        assert_eq!(hex_decode("gg"), None);
    }
}
