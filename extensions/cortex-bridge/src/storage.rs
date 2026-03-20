// storage.rs -- SQLite storage backend for the Cortex Bridge
//
// Manages all database operations: schema creation, entry insertion
// with deduplication (content_hash), incremental retrieval, category
// counts, and cross-contributor reinforcement.
//
// Uses rusqlite with WAL mode for concurrent read/write access.

use rusqlite::{params, Connection, Result as SqliteResult};
use std::collections::HashMap;
use std::sync::Mutex;

use crate::models::SharedEntry;

/// Thread-safe SQLite database wrapper.
///
/// Uses a Mutex around the Connection because rusqlite's Connection
/// is not Sync. For a bridge server with moderate load, this is
/// acceptable. High-throughput deployments should consider connection
/// pooling.
pub struct Database {
    conn: Mutex<Connection>,
}

impl Database {
    /// Create or open a SQLite database at the given path.
    ///
    /// Runs schema migrations on first creation. Sets WAL journal
    /// mode for better concurrent access.
    pub fn new(path: &str) -> SqliteResult<Self> {
        let conn = Connection::open(path)?;

        // Enable WAL mode for concurrent readers
        conn.execute_batch("PRAGMA journal_mode=WAL;")?;
        // Foreign keys
        conn.execute_batch("PRAGMA foreign_keys=ON;")?;

        // Run schema creation
        Self::create_tables(&conn)?;

        Ok(Database {
            conn: Mutex::new(conn),
        })
    }

    /// Create tables if they don't exist.
    ///
    /// Schema mirrors the D1 cloud schema from M9, adapted for
    /// rusqlite. Tables are created idempotently with IF NOT EXISTS.
    fn create_tables(conn: &Connection) -> SqliteResult<()> {
        conn.execute_batch(
            "
            CREATE TABLE IF NOT EXISTS shared_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                uuid TEXT NOT NULL UNIQUE,
                category TEXT NOT NULL,
                contributor TEXT NOT NULL,
                source_project TEXT NOT NULL,
                created_at TEXT NOT NULL,
                confidence REAL NOT NULL DEFAULT 0.0,
                occurrences INTEGER NOT NULL DEFAULT 1,
                content_hash TEXT NOT NULL,
                signature TEXT,
                data TEXT NOT NULL DEFAULT '{}',
                imported_at TEXT NOT NULL DEFAULT (datetime('now')),
                reinforced_by TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_shared_entries_category
                ON shared_entries(category);
            CREATE INDEX IF NOT EXISTS idx_shared_entries_content_hash
                ON shared_entries(content_hash);
            CREATE INDEX IF NOT EXISTS idx_shared_entries_created_at
                ON shared_entries(created_at);
            CREATE UNIQUE INDEX IF NOT EXISTS idx_shared_entries_uuid
                ON shared_entries(uuid);

            CREATE TABLE IF NOT EXISTS sync_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                action TEXT NOT NULL,
                entry_count INTEGER NOT NULL DEFAULT 0,
                timestamp TEXT NOT NULL DEFAULT (datetime('now')),
                client_ip TEXT,
                details TEXT
            );
            ",
        )?;
        Ok(())
    }

    /// Insert entries with deduplication based on content_hash.
    ///
    /// For each entry:
    /// - If content_hash already exists: reinforce (bump occurrences, update confidence)
    /// - If content_hash is new: insert as new entry
    ///
    /// Returns (exported_count, reinforced_count, errors).
    pub fn insert_entries(
        &self,
        entries: &[SharedEntry],
    ) -> SqliteResult<(usize, usize, Vec<String>)> {
        let conn = self.conn.lock().expect("Database mutex poisoned");
        let mut exported = 0;
        let mut reinforced = 0;
        let mut errors = Vec::new();

        for entry in entries {
            // Check if content_hash already exists
            let existing: Option<(i64, i32, Option<String>)> = conn
                .query_row(
                    "SELECT id, occurrences, reinforced_by FROM shared_entries WHERE content_hash = ?1",
                    params![entry.content_hash],
                    |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
                )
                .ok();

            if let Some((id, current_occurrences, current_reinforced)) = existing {
                // Reinforce existing entry
                let new_occurrences = current_occurrences + 1;
                // Cross-contributor reinforcement: +0.2 boost (capped at 1.0)
                let new_confidence = (entry.confidence + 0.2).min(1.0);

                // Track who reinforced
                let reinforced_by = {
                    let mut contributors: Vec<String> = current_reinforced
                        .as_deref()
                        .unwrap_or("")
                        .split(',')
                        .filter(|s| !s.is_empty())
                        .map(String::from)
                        .collect();
                    if !contributors.contains(&entry.contributor) {
                        contributors.push(entry.contributor.clone());
                    }
                    contributors.join(",")
                };

                match conn.execute(
                    "UPDATE shared_entries SET occurrences = ?1, confidence = ?2, reinforced_by = ?3 WHERE id = ?4",
                    params![new_occurrences, new_confidence, reinforced_by, id],
                ) {
                    Ok(_) => reinforced += 1,
                    Err(e) => errors.push(format!("Reinforce error for {}: {}", entry.uuid, e)),
                }
            } else {
                // Insert new entry
                let data_str = entry.data.to_string();
                match conn.execute(
                    "INSERT INTO shared_entries (uuid, category, contributor, source_project, created_at, confidence, occurrences, content_hash, signature, data)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
                    params![
                        entry.uuid,
                        entry.category,
                        entry.contributor,
                        entry.source_project,
                        entry.created_at,
                        entry.confidence,
                        entry.occurrences,
                        entry.content_hash,
                        entry.signature,
                        data_str,
                    ],
                ) {
                    Ok(_) => exported += 1,
                    Err(e) => errors.push(format!("Insert error for {}: {}", entry.uuid, e)),
                }
            }
        }

        // Log the sync action
        let _ = conn.execute(
            "INSERT INTO sync_log (action, entry_count, details) VALUES ('export', ?1, ?2)",
            params![
                exported + reinforced,
                format!("exported={exported}, reinforced={reinforced}")
            ],
        );

        Ok((exported, reinforced, errors))
    }

    /// Get entries created or updated after the given timestamp.
    ///
    /// If timestamp is None, returns all entries.
    /// Results are ordered by created_at ASC for deterministic import.
    pub fn get_entries_since(&self, since: Option<&str>) -> SqliteResult<Vec<SharedEntry>> {
        let conn = self.conn.lock().expect("Database mutex poisoned");
        let mut entries = Vec::new();

        let (sql, param): (&str, Option<&str>) = match since {
            Some(ts) => (
                "SELECT uuid, category, contributor, source_project, created_at, confidence, occurrences, content_hash, signature, data FROM shared_entries WHERE created_at > ?1 ORDER BY created_at ASC",
                Some(ts),
            ),
            None => (
                "SELECT uuid, category, contributor, source_project, created_at, confidence, occurrences, content_hash, signature, data FROM shared_entries ORDER BY created_at ASC",
                None,
            ),
        };

        let mut stmt = conn.prepare(sql)?;

        let rows = if let Some(ts) = param {
            stmt.query_map(params![ts], Self::row_to_entry)?
        } else {
            stmt.query_map([], Self::row_to_entry)?
        };

        for row in rows {
            match row {
                Ok(entry) => entries.push(entry),
                Err(e) => eprintln!("Warning: failed to read entry: {e}"),
            }
        }

        // Log the sync action
        let _ = conn.execute(
            "INSERT INTO sync_log (action, entry_count, details) VALUES ('import', ?1, ?2)",
            params![
                entries.len(),
                format!("since={}", since.unwrap_or("all"))
            ],
        );

        Ok(entries)
    }

    /// Map a database row to a SharedEntry.
    fn row_to_entry(row: &rusqlite::Row) -> rusqlite::Result<SharedEntry> {
        let data_str: String = row.get(9)?;
        let data: serde_json::Value =
            serde_json::from_str(&data_str).unwrap_or(serde_json::Value::Object(Default::default()));

        Ok(SharedEntry {
            uuid: row.get(0)?,
            category: row.get(1)?,
            contributor: row.get(2)?,
            source_project: row.get(3)?,
            created_at: row.get(4)?,
            confidence: row.get(5)?,
            occurrences: row.get(6)?,
            content_hash: row.get(7)?,
            signature: row.get(8)?,
            data,
        })
    }

    /// Get entry counts grouped by category.
    pub fn get_counts(&self) -> SqliteResult<HashMap<String, i64>> {
        let conn = self.conn.lock().expect("Database mutex poisoned");
        let mut counts = HashMap::new();

        let mut stmt = conn.prepare(
            "SELECT category, COUNT(*) FROM shared_entries GROUP BY category",
        )?;

        let rows = stmt.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
        })?;

        for (category, count) in rows.flatten() {
            counts.insert(category, count);
        }

        Ok(counts)
    }

    /// Get the timestamp of the most recent sync action.
    pub fn get_last_sync(&self) -> SqliteResult<Option<String>> {
        let conn = self.conn.lock().expect("Database mutex poisoned");
        conn.query_row(
            "SELECT timestamp FROM sync_log ORDER BY id DESC LIMIT 1",
            [],
            |row| row.get(0),
        )
        .ok()
        .map_or(Ok(None), |v| Ok(Some(v)))
    }

    /// Reinforce an existing entry by UUID with a new contributor.
    ///
    /// Bumps occurrences by 1 and applies cross-contributor confidence
    /// boost (+0.2, capped at 1.0) as per REQ-CTX-022.
    ///
    /// Used by integration tests and as public library API for custom
    /// reinforcement workflows. Not called by the HTTP handler directly
    /// (dedup-based reinforcement happens in insert_entries).
    #[allow(dead_code)]
    pub fn reinforce_entry(&self, uuid: &str, contributor: &str) -> SqliteResult<bool> {
        let conn = self.conn.lock().expect("Database mutex poisoned");

        // Get current state
        let current: Option<(i32, f64, Option<String>)> = conn
            .query_row(
                "SELECT occurrences, confidence, reinforced_by FROM shared_entries WHERE uuid = ?1",
                params![uuid],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .ok();

        match current {
            Some((occurrences, confidence, reinforced_by)) => {
                let new_occurrences = occurrences + 1;
                let new_confidence = (confidence + 0.2).min(1.0);

                let reinforced_str = {
                    let mut contributors: Vec<String> = reinforced_by
                        .as_deref()
                        .unwrap_or("")
                        .split(',')
                        .filter(|s| !s.is_empty())
                        .map(String::from)
                        .collect();
                    if !contributors.contains(&contributor.to_string()) {
                        contributors.push(contributor.to_string());
                    }
                    contributors.join(",")
                };

                conn.execute(
                    "UPDATE shared_entries SET occurrences = ?1, confidence = ?2, reinforced_by = ?3 WHERE uuid = ?4",
                    params![new_occurrences, new_confidence, reinforced_str, uuid],
                )?;

                Ok(true)
            }
            None => Ok(false),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_db() -> Database {
        Database::new(":memory:").expect("Failed to create test database")
    }

    fn sample_entry(uuid: &str, hash: &str) -> SharedEntry {
        SharedEntry {
            uuid: uuid.to_string(),
            category: "behavioral_learning".to_string(),
            contributor: "Test User <test@example.com>".to_string(),
            source_project: "test-project".to_string(),
            created_at: "2026-03-20T15:00:00Z".to_string(),
            confidence: 0.9,
            occurrences: 1,
            content_hash: hash.to_string(),
            signature: None,
            data: serde_json::json!({"rule": "always test first"}),
        }
    }

    #[test]
    fn test_insert_new_entry() {
        let db = test_db();
        let entries = vec![sample_entry("uuid-1", "hash-1")];
        let (exported, reinforced, errors) = db.insert_entries(&entries).unwrap();
        assert_eq!(exported, 1);
        assert_eq!(reinforced, 0);
        assert!(errors.is_empty());
    }

    #[test]
    fn test_insert_duplicate_reinforces() {
        let db = test_db();
        let entry1 = sample_entry("uuid-1", "hash-1");
        let mut entry2 = sample_entry("uuid-2", "hash-1"); // same hash
        entry2.contributor = "Other User <other@example.com>".to_string();

        db.insert_entries(&[entry1]).unwrap();
        let (exported, reinforced, errors) = db.insert_entries(&[entry2]).unwrap();
        assert_eq!(exported, 0);
        assert_eq!(reinforced, 1);
        assert!(errors.is_empty());
    }

    #[test]
    fn test_get_entries_since() {
        let db = test_db();
        let e1 = SharedEntry {
            created_at: "2026-03-19T10:00:00Z".to_string(),
            ..sample_entry("uuid-1", "hash-1")
        };
        let e2 = SharedEntry {
            created_at: "2026-03-20T10:00:00Z".to_string(),
            ..sample_entry("uuid-2", "hash-2")
        };
        db.insert_entries(&[e1, e2]).unwrap();

        let all = db.get_entries_since(None).unwrap();
        assert_eq!(all.len(), 2);

        let recent = db
            .get_entries_since(Some("2026-03-19T12:00:00Z"))
            .unwrap();
        assert_eq!(recent.len(), 1);
        assert_eq!(recent[0].uuid, "uuid-2");
    }

    #[test]
    fn test_get_counts() {
        let db = test_db();
        let e1 = sample_entry("uuid-1", "hash-1");
        let mut e2 = sample_entry("uuid-2", "hash-2");
        e2.category = "incident".to_string();

        db.insert_entries(&[e1, e2]).unwrap();

        let counts = db.get_counts().unwrap();
        assert_eq!(counts.get("behavioral_learning"), Some(&1));
        assert_eq!(counts.get("incident"), Some(&1));
    }

    #[test]
    fn test_reinforce_entry() {
        let db = test_db();
        let entry = sample_entry("uuid-1", "hash-1");
        db.insert_entries(&[entry]).unwrap();

        let reinforced = db.reinforce_entry("uuid-1", "Other <other@test.com>").unwrap();
        assert!(reinforced);

        let entries = db.get_entries_since(None).unwrap();
        assert_eq!(entries[0].occurrences, 2);
        // Confidence boosted by 0.2, capped at 1.0
        assert!((entries[0].confidence - 1.0).abs() < f64::EPSILON);
    }

    #[test]
    fn test_reinforce_nonexistent() {
        let db = test_db();
        let reinforced = db.reinforce_entry("nonexistent", "User").unwrap();
        assert!(!reinforced);
    }
}
