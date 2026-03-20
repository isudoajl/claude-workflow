// integration.rs -- Integration tests for the Cortex Bridge server
//
// Tests the storage layer end-to-end since it's the core of the
// bridge. HTTP endpoint tests require a running server and are
// covered by the shell test suite (test-cortex-m11-bridge.sh).

use cortex_bridge::models::SharedEntry;
use cortex_bridge::storage::Database;

fn test_db() -> Database {
    Database::new(":memory:").expect("Failed to create test database")
}

fn make_entry(uuid: &str, category: &str, hash: &str) -> SharedEntry {
    SharedEntry {
        uuid: uuid.to_string(),
        category: category.to_string(),
        contributor: "Integration Test <test@example.com>".to_string(),
        source_project: "test-project".to_string(),
        created_at: "2026-03-20T15:00:00Z".to_string(),
        confidence: 0.9,
        occurrences: 1,
        content_hash: hash.to_string(),
        signature: Some("test-signature".to_string()),
        data: serde_json::json!({"rule": "test rule", "context": "testing"}),
    }
}

#[test]
fn test_full_export_import_cycle() {
    let db = test_db();

    // Export entries
    let entries = vec![
        make_entry("uuid-1", "behavioral_learning", "hash-1"),
        make_entry("uuid-2", "incident", "hash-2"),
        make_entry("uuid-3", "hotspot", "hash-3"),
    ];

    let (exported, reinforced, errors) = db.insert_entries(&entries).unwrap();
    assert_eq!(exported, 3);
    assert_eq!(reinforced, 0);
    assert!(errors.is_empty());

    // Import all entries
    let imported = db.get_entries_since(None).unwrap();
    assert_eq!(imported.len(), 3);

    // Import with timestamp filter
    let recent = db
        .get_entries_since(Some("2026-03-20T14:00:00Z"))
        .unwrap();
    assert_eq!(recent.len(), 3);

    let none = db
        .get_entries_since(Some("2026-03-20T16:00:00Z"))
        .unwrap();
    assert_eq!(none.len(), 0);
}

#[test]
fn test_deduplication_by_content_hash() {
    let db = test_db();

    let entry1 = make_entry("uuid-1", "behavioral_learning", "same-hash");
    db.insert_entries(&[entry1]).unwrap();

    // Second entry with same content_hash but different UUID
    let entry2 = SharedEntry {
        uuid: "uuid-2".to_string(),
        contributor: "Other Dev <other@example.com>".to_string(),
        ..make_entry("uuid-2", "behavioral_learning", "same-hash")
    };

    let (exported, reinforced, _) = db.insert_entries(&[entry2]).unwrap();
    assert_eq!(exported, 0);
    assert_eq!(reinforced, 1);

    // Only one entry in the database
    let all = db.get_entries_since(None).unwrap();
    assert_eq!(all.len(), 1);
    // Occurrences bumped
    assert_eq!(all[0].occurrences, 2);
}

#[test]
fn test_cross_contributor_reinforcement() {
    let db = test_db();

    let entry = make_entry("uuid-1", "behavioral_learning", "hash-1");
    db.insert_entries(&[entry]).unwrap();

    // Reinforce from a different contributor
    let result = db
        .reinforce_entry("uuid-1", "Other Dev <other@example.com>")
        .unwrap();
    assert!(result);

    let entries = db.get_entries_since(None).unwrap();
    assert_eq!(entries[0].occurrences, 2);
    // Confidence boosted by 0.2, capped at 1.0
    assert!(entries[0].confidence >= 1.0);
}

#[test]
fn test_category_counts() {
    let db = test_db();

    let entries = vec![
        make_entry("uuid-1", "behavioral_learning", "hash-1"),
        make_entry("uuid-2", "behavioral_learning", "hash-2"),
        make_entry("uuid-3", "incident", "hash-3"),
        make_entry("uuid-4", "hotspot", "hash-4"),
        make_entry("uuid-5", "lesson", "hash-5"),
    ];

    db.insert_entries(&entries).unwrap();

    let counts = db.get_counts().unwrap();
    assert_eq!(counts.get("behavioral_learning"), Some(&2));
    assert_eq!(counts.get("incident"), Some(&1));
    assert_eq!(counts.get("hotspot"), Some(&1));
    assert_eq!(counts.get("lesson"), Some(&1));
}

#[test]
fn test_entry_data_field_preserved() {
    let db = test_db();

    let mut entry = make_entry("uuid-1", "behavioral_learning", "hash-1");
    entry.data = serde_json::json!({
        "rule": "always write tests first",
        "context": "discovered during TDD session",
        "custom_field": 42
    });

    db.insert_entries(&[entry]).unwrap();

    let entries = db.get_entries_since(None).unwrap();
    assert_eq!(entries[0].data["rule"], "always write tests first");
    assert_eq!(entries[0].data["custom_field"], 42);
}
