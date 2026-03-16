-- ============================================================
-- DEBRIEF QUERIES — agents run these AFTER completing work
-- ============================================================
-- These are INSERT/UPDATE templates. Agents fill in the values.

-- 1. Start a workflow run (at pipeline start)
-- Returns the run_id to pass to all agents in the chain
-- sqlite3 .claude/memory.db "INSERT INTO workflow_runs (type, description, scope) VALUES ('bugfix', 'fix scheduler crash on empty queue', 'backend/src/scheduler.rs'); SELECT last_insert_rowid();"

-- 2. Log a file change
-- sqlite3 .claude/memory.db "INSERT INTO changes (run_id, file_path, change_type, description, agent) VALUES (42, 'src/scheduler.rs', 'modified', 'Added null check for empty queue before dequeue', 'developer');"

-- 3. Log a decision
-- sqlite3 .claude/memory.db "INSERT INTO decisions (run_id, domain, decision, rationale, alternatives, confidence) VALUES (42, 'scheduler', 'Use Option<T> instead of panic on empty queue', 'Panicking crashes the runtime; Option<T> lets callers decide', '[\"sentinel value - rejected: hides errors\", \"Result<T,E> - rejected: not actually an error condition\"]', 0.9);"

-- 4. Log a failed approach
-- sqlite3 .claude/memory.db "INSERT INTO failed_approaches (run_id, domain, problem, approach, failure_reason, file_paths) VALUES (42, 'scheduler', 'Empty queue crash', 'Added .is_empty() guard before .pop()', 'Race condition: queue can become empty between check and pop in concurrent context', '[\"src/scheduler.rs\"]');"

-- 5. Log a bug found and fixed
-- sqlite3 .claude/memory.db "INSERT INTO bugs (run_id, description, symptoms, root_cause, fix_description, affected_files) VALUES (42, 'Scheduler panics on empty queue', 'Thread panic: called unwrap() on None at scheduler.rs:142', 'dequeue() calls .pop().unwrap() without checking if queue is empty', 'Replaced .pop().unwrap() with .pop() returning Option<Task>', '[\"src/scheduler.rs\", \"src/worker.rs\"]');"

-- 6. Update hotspot counter (upsert)
-- sqlite3 .claude/memory.db "INSERT INTO hotspots (file_path, times_touched, description, last_incident_run) VALUES ('src/scheduler.rs', 1, 'Scheduler core - concurrent access patterns', 42) ON CONFLICT(file_path) DO UPDATE SET times_touched = times_touched + 1, last_incident_run = 42, last_updated = datetime('now');"

-- 7. Log a finding
-- sqlite3 .claude/memory.db "INSERT INTO findings (run_id, finding_id, severity, category, description, file_path, line_range) VALUES (42, 'AUDIT-P1-003', 'P1', 'bug', 'Race condition in dequeue when multiple workers consume', 'src/scheduler.rs', '140-155');"

-- 8. Mark a finding as fixed
-- sqlite3 .claude/memory.db "UPDATE findings SET status='fixed', fixed_in_run=43 WHERE finding_id='AUDIT-P1-003';"

-- 9. Log a component dependency
-- sqlite3 .claude/memory.db "INSERT OR IGNORE INTO dependencies (source_file, target_file, relationship, discovered_run) VALUES ('src/worker.rs', 'src/scheduler.rs', 'calls', 42);"

-- 10. Log a requirement
-- sqlite3 .claude/memory.db "INSERT OR IGNORE INTO requirements (run_id, req_id, domain, description, priority) VALUES (42, 'REQ-SCHED-001', 'scheduler', 'Scheduler must handle empty queue without panicking', 'Must');"

-- 11. Update requirement status
-- sqlite3 .claude/memory.db "UPDATE requirements SET status='verified', test_ids='[\"TEST-SCHED-001\", \"TEST-SCHED-002\"]' WHERE req_id='REQ-SCHED-001';"

-- 12. Log a discovered pattern
-- sqlite3 .claude/memory.db "INSERT INTO patterns (run_id, domain, name, description, example_files) VALUES (42, 'scheduler', 'Option-based queue access', 'All queue operations return Option<T> instead of panicking, letting callers handle empty state', '[\"src/scheduler.rs:dequeue\", \"src/scheduler.rs:peek\"]');"

-- 13. Complete a workflow run
-- sqlite3 .claude/memory.db "UPDATE workflow_runs SET status='completed', completed_at=datetime('now'), git_commits='[\"abc1234\", \"def5678\"]' WHERE id=42;"

-- 14. Fail a workflow run
-- sqlite3 .claude/memory.db "UPDATE workflow_runs SET status='failed', completed_at=datetime('now'), error_message='QA iteration limit reached (3/3)' WHERE id=42;"

-- 15. Log decay (for the compressor/maintenance)
-- sqlite3 .claude/memory.db "INSERT INTO decay_log (entity_type, entity_id, action, reason, run_id) VALUES ('decision', 15, 'stale_flagged', 'Referenced file no longer exists after refactor', 42);"
