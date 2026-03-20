# QA Report: OMEGA Cortex -- Milestone M1: Schema + Migration

## Scope Validated

- `core/db/schema.sql` -- Version 1.3.0 schema with Cortex additions
- `core/db/migrate-1.3.0.sh` -- Migration script for pre-Cortex databases
- `scripts/db-init.sh` -- DB initialization with migration integration
- Requirements: REQ-CTX-001 through REQ-CTX-006, REQ-CTX-010, REQ-CTX-011

## Summary

**PASS** -- All 153 automated tests pass. All Must requirements verified through both automated tests and manual exploratory testing. The one Should requirement (REQ-CTX-010) also passes. No blocking issues found. Two non-blocking observations documented (specs/docs drift).

## System Entrypoint

No running system required for M1. Validation performed by:
1. Running the test suite: `bash tests/test-cortex-m1-schema.sh` (153 tests, all pass)
2. Manual exploratory testing using `sqlite3` against temp databases
3. Running `bash scripts/db-init.sh [tmpdir]` to verify integration

## Traceability Matrix Status

| Requirement ID | Priority | Has Tests | Tests Pass | Acceptance Met | Notes |
|---|---|---|---|---|---|
| REQ-CTX-001 | Must | Yes | Yes | Yes | Schema version 1.3.0 verified in line 2 comment |
| REQ-CTX-002 | Must | Yes | Yes | Yes | `shared_imports` table with correct columns, UNIQUE index, NOT NULL constraints |
| REQ-CTX-003 | Must | Yes | Yes | Yes | `contributor` column on all 6 tables (behavioral_learnings, incidents, lessons, patterns, decisions, hotspots) |
| REQ-CTX-004 | Must | Yes | Yes | Yes | `shared_uuid` column on 5 tables; correctly excluded from hotspots |
| REQ-CTX-005 | Must | Yes | Yes | Yes | `is_private` column on 5 tables with DEFAULT 0; correctly excluded from hotspots |
| REQ-CTX-006 | Must | Yes | Yes | Yes | Migration is idempotent (tested 3x), handles missing DB, preserves data |
| REQ-CTX-010 | Should | Yes | Yes | Yes | `v_shared_briefing` view filters correctly: confidence >= 0.8, active, not private |
| REQ-CTX-011 | Must | Partial | Yes | Yes | Backward compat verified by Suite 9 (all original tables/views present, constraints preserved). No explicit REQ-CTX-011 tag in tests. Full backward compat (briefing.sh, agents) is M2 scope per architecture traceability. |

### Gaps Found

- **REQ-CTX-011 test tagging**: Test Suite 9 covers backward compatibility at the schema level but is tagged under REQ-CTX-001, not REQ-CTX-011. The architecture traceability matrix assigns REQ-CTX-011 to M2 (not M1), which is correct since full backward compat of hooks and agents cannot be verified until those files are modified. At the M1 schema level, backward compat is confirmed.
- **No standalone traceability matrix file**: Traceability is embedded in the architecture doc. This is acceptable but differs from some OMEGA conventions where a standalone matrix exists.

## Acceptance Criteria Results

### Must Requirements

#### REQ-CTX-001: Schema version bump to 1.3.0
- [x] `core/db/schema.sql` line 2 updated to `Version: 1.3.0 -- Added Cortex collective intelligence layer` -- PASS
- [x] No functional change beyond comment -- PASS (confirmed by TEST-CTX-M1-001, TEST-CTX-M1-002)

#### REQ-CTX-002: `shared_imports` table
- [x] `CREATE TABLE IF NOT EXISTS shared_imports` present in schema.sql -- PASS
- [x] Columns: `id INTEGER PRIMARY KEY AUTOINCREMENT`, `shared_uuid TEXT NOT NULL`, `category TEXT NOT NULL`, `source_file TEXT`, `imported_at TEXT DEFAULT (datetime('now'))` -- PASS
- [x] UNIQUE constraint on `shared_uuid` (enforced via `CREATE UNIQUE INDEX`) -- PASS
- [x] Index `idx_shared_imports_uuid` exists -- PASS
- [x] NULL `shared_uuid` rejected by NOT NULL constraint -- PASS (TEST-CTX-M1-089)
- [x] NULL `category` rejected by NOT NULL constraint -- PASS (TEST-CTX-M1-090)
- [x] Duplicate `shared_uuid` rejected -- PASS (TEST-CTX-M1-010, TEST-CTX-M1-085)

**Note**: schema.sql uses `CREATE UNIQUE INDEX` rather than inline `UNIQUE(shared_uuid)` constraint. The architecture spec (Module 1) shows inline `UNIQUE(shared_uuid)`. Both enforce uniqueness identically in SQLite. The actual implementation has a separate UNIQUE INDEX, which is equally correct and provides the fast-lookup benefit the spec calls for.

#### REQ-CTX-003: `contributor` column on shareable tables
- [x] `contributor TEXT` added to `behavioral_learnings` -- PASS
- [x] `contributor TEXT` added to `incidents` -- PASS
- [x] `contributor TEXT` added to `lessons` -- PASS
- [x] `contributor TEXT` added to `patterns` -- PASS
- [x] `contributor TEXT` added to `decisions` -- PASS
- [x] `contributor TEXT` added to `hotspots` -- PASS
- [x] Existing rows get NULL for contributor (no backfill) -- PASS (TEST-CTX-M1-080 to 082)
- [x] Migration uses `PRAGMA table_info()` existence check before ALTER -- PASS
- [x] Special characters in contributor (angle brackets, hyphens) accepted -- PASS (TEST-CTX-M1-117)
- [x] Unicode in contributor accepted -- PASS (TEST-CTX-M1-118)

#### REQ-CTX-004: `shared_uuid` column on shareable tables
- [x] `shared_uuid TEXT` added to `behavioral_learnings` -- PASS
- [x] `shared_uuid TEXT` added to `incidents` -- PASS
- [x] `shared_uuid TEXT` added to `lessons` -- PASS
- [x] `shared_uuid TEXT` added to `patterns` -- PASS
- [x] `shared_uuid TEXT` added to `decisions` -- PASS
- [x] NOT added to `hotspots` (uses `file_path` as natural key) -- PASS (TEST-CTX-M1-024, TEST-CTX-M1-048)
- [x] NULL for locally-created entries -- PASS (TEST-CTX-M1-057)

#### REQ-CTX-005: `is_private` column on shareable tables
- [x] `is_private INTEGER DEFAULT 0` added to `behavioral_learnings` -- PASS
- [x] `is_private INTEGER DEFAULT 0` added to `incidents` -- PASS
- [x] `is_private INTEGER DEFAULT 0` added to `lessons` -- PASS
- [x] `is_private INTEGER DEFAULT 0` added to `patterns` -- PASS
- [x] `is_private INTEGER DEFAULT 0` added to `decisions` -- PASS
- [x] NOT added to `hotspots` -- PASS
- [x] DEFAULT 0 verified (new rows get is_private=0) -- PASS (TEST-CTX-M1-030 to 032, TEST-CTX-M1-055)
- [x] Value 1 accepted for private entries -- PASS (TEST-CTX-M1-119)

#### REQ-CTX-006: Migration script for existing DBs
- [x] Migration script exists at `core/db/migrate-1.3.0.sh` -- PASS
- [x] Uses `PRAGMA table_info()` existence check pattern -- PASS
- [x] Idempotent: first run succeeds -- PASS (TEST-CTX-M1-061)
- [x] Idempotent: second run succeeds without errors -- PASS (TEST-CTX-M1-062)
- [x] Idempotent: third run succeeds -- PASS (TEST-CTX-M1-068)
- [x] Row count preserved after repeated migrations -- PASS (TEST-CTX-M1-063)
- [x] Data content preserved after migration -- PASS (TEST-CTX-M1-064, 076-079)
- [x] `db-init.sh` calls migration after running schema.sql -- PASS (verified in source, line 35-39)
- [x] Handles missing DB gracefully (exits 0, prints message) -- PASS
- [x] Handles missing sqlite3 gracefully (exits 0, prints message) -- PASS (verified in source)
- [x] Works on fresh DB (columns already exist, no-op) -- PASS (TEST-CTX-M1-113)
- [x] Works on pre-Cortex DB (columns added) -- PASS (TEST-CTX-M1-036 to 053)
- [x] Works on already-migrated DB (no-op) -- PASS (TEST-CTX-M1-061 to 068)
- [x] Creates `shared_imports` table via `CREATE TABLE IF NOT EXISTS` -- PASS
- [x] Creates `v_shared_briefing` view via `CREATE VIEW IF NOT EXISTS` -- PASS

#### REQ-CTX-011: Backward compatibility
- [x] All 18 original tables present in fresh schema -- PASS (TEST-CTX-M1-124-*)
- [x] All 11 original views present in fresh schema -- PASS (TEST-CTX-M1-125-*)
- [x] Existing UNIQUE(rule) constraint on behavioral_learnings preserved -- PASS (TEST-CTX-M1-126)
- [x] Original v_behavioral_briefing view works alongside v_shared_briefing -- PASS (TEST-CTX-M1-127)
- [x] No existing CREATE TABLE/VIEW definitions modified (additive only) -- PASS (verified by reading schema.sql: new columns are inline additions, not modifications)

### Should Requirements

#### REQ-CTX-010: `v_shared_briefing` view
- [x] View created with `CREATE VIEW IF NOT EXISTS v_shared_briefing` -- PASS
- [x] Selects from `behavioral_learnings` where confidence >= 0.8 -- PASS (TEST-CTX-M1-095, 096, 097)
- [x] Filters: status = 'active' -- PASS (TEST-CTX-M1-099, 100)
- [x] Filters: is_private = 0 (via `COALESCE(is_private, 0) = 0`) -- PASS (TEST-CTX-M1-098)
- [x] COALESCE handles NULL is_private (pre-migration row appears) -- PASS (exploratory test 14)
- [x] Orders by confidence DESC, occurrences DESC -- PASS (TEST-CTX-M1-101, 102; exploratory test 21)
- [x] Returns columns: id, rule, confidence, occurrences, context, source_project, contributor, created_at, last_reinforced -- PASS (TEST-CTX-M1-103 to 105)
- [x] Returns empty set when no qualifying entries -- PASS (TEST-CTX-M1-106)
- [x] Boundary: confidence exactly 0.80 included -- PASS (TEST-CTX-M1-095)
- [x] Boundary: confidence 0.79 excluded -- PASS (TEST-CTX-M1-097)

## End-to-End Flow Results

| Flow | Steps | Result | Notes |
|---|---|---|---|
| Fresh DB creation via schema.sql | 1 | PASS | All 20 tables, 12 views created. All Cortex columns present. |
| Fresh DB creation via db-init.sh | 3 (mkdir, schema.sql, migration) | PASS | DB created with all Cortex features. Migration is no-op on fresh DB. |
| Pre-Cortex DB migration | 2 (migration script, verify) | PASS | All columns added, data preserved, shared_imports created. |
| Pre-Cortex DB via db-init.sh | 3 (detect existing, re-run schema, run migration) | PASS | Schema re-applied safely, migration adds columns. |
| Triple migration (idempotency) | 3 runs | PASS | No errors, no data loss, no duplicate columns. |
| Insert -> Migrate -> Query | 3 | PASS | Pre-existing data intact, new columns have NULL/default values. |

## Exploratory Testing Findings

| # | What Was Tried | Expected | Actual | Severity |
|---|---|---|---|---|
| 1 | Insert data with `Name <email>` contributor format | Accepted without issues | Accepted, stored correctly with angle brackets | N/A (PASS) |
| 2 | Insert with Unicode contributor name | Accepted | Accepted and queryable | N/A (PASS) |
| 3 | NULL is_private entry queried via v_shared_briefing | COALESCE treats as 0 (not private) | Correct -- entry appears in view | N/A (PASS) |
| 4 | Insert duplicate shared_uuid into shared_imports | Rejected by UNIQUE constraint | Error code 19 (UNIQUE constraint failed) | N/A (PASS) |
| 5 | Migration on nonexistent DB file | Graceful skip, exit 0 | `DB not found ... skipping migration`, exit 0 | N/A (PASS) |
| 6 | v_shared_briefing ordering with same confidence | Ordered by occurrences DESC as tiebreaker | Correct ordering (C=0.95, B=0.90/10occ, A=0.90/5occ) | N/A (PASS) |
| 7 | Run schema.sql on already-migrated DB (simulate db-init.sh re-run) | No errors, data preserved | Correct -- CREATE IF NOT EXISTS prevents collisions | N/A (PASS) |
| 8 | Architecture spec references `migrate-1.3.0.sql` but file is `.sh` | Consistent naming | Spec drift detected (see below) | low |

## Failure Mode Validation

| Failure Scenario | Triggered | Detected | Recovered | Degraded OK | Notes |
|---|---|---|---|---|---|
| Migration on missing DB | Yes | Yes | N/A | Yes | Script prints message, exits 0. No crash. |
| Migration on fresh DB (columns exist) | Yes | Yes (checks existence) | N/A | Yes | No-op, no errors. |
| Migration re-run (idempotent) | Yes | Yes | N/A | Yes | 3x runs, no errors, data preserved. |
| shared_imports duplicate UUID | Yes | Yes (UNIQUE constraint) | N/A | Yes | Error returned to caller. |
| shared_imports NULL required fields | Yes | Yes (NOT NULL constraint) | N/A | Yes | Insert rejected. |
| v_shared_briefing on pre-migration DB | Not Triggered | N/A | N/A | N/A | Would fail if is_private column missing. COALESCE handles NULL values but column must exist. View is created in schema.sql which includes the column, so this scenario only arises if view is created before migration on a legacy DB -- unlikely in practice since db-init.sh runs schema.sql first. |

## Security Validation

| Attack Surface | Test Performed | Result | Notes |
|---|---|---|---|
| Local SQLite file | N/A | Out of Scope | Schema is local-only. No network surface. OS file permissions control access. |
| is_private column | Verified default 0, value 1 accepted | PASS | Privacy marking infrastructure correct. Enforcement is in curator (Phase 2). |

## Specs/Docs Drift

| File | Documented Behavior | Actual Behavior | Severity |
|------|-------------------|-----------------|----------|
| `specs/cortex-architecture.md` (line 82, 112) | Migration file named `core/db/migrate-1.3.0.sql` | Actual file is `core/db/migrate-1.3.0.sh` (bash script, not SQL). Lines 219, 1083, 1138-1141 of the same file correctly reference `.sh`. | low |
| `specs/cortex-architecture.md` (Module 1, line 90-97) | `shared_imports` table has inline `UNIQUE(shared_uuid)` constraint | Implementation uses `CREATE UNIQUE INDEX idx_shared_imports_uuid` instead. Functionally identical -- both enforce uniqueness. | low |
| `specs/cortex-requirements.md` (REQ-CTX-006) | File named `core/db/migrate-1.3.0.sql (or inline in db-init.sh)` | File is `core/db/migrate-1.3.0.sh`. The parenthetical "or inline" makes this acceptable as it acknowledges alternatives. | low |

## Blocking Issues (must fix before merge)

None.

## Non-Blocking Observations

- **[OBS-001]**: `specs/cortex-architecture.md` lines 82 and 112 reference `core/db/migrate-1.3.0.sql` but the actual file is `core/db/migrate-1.3.0.sh`. Later in the same document (lines 219, 1083, 1138-1141), the correct `.sh` extension is used. The early references should be updated for consistency.
- **[OBS-002]**: The architecture spec shows `shared_imports` with inline `UNIQUE(shared_uuid)` constraint, but the implementation uses a separate `CREATE UNIQUE INDEX`. Both enforce uniqueness identically in SQLite. This is a cosmetic difference, not a functional one.
- **[OBS-003]**: Test Suite 9 (backward compatibility) is tagged under REQ-CTX-001 in the test file, but functionally covers REQ-CTX-011. Adding an explicit REQ-CTX-011 reference in the test suite header would improve traceability.

## Modules Not Validated (if context limited)

None -- full M1 scope validated.

## Final Verdict

**PASS** -- All Must requirements (REQ-CTX-001 through REQ-CTX-006, REQ-CTX-011) met. The Should requirement (REQ-CTX-010) met. All 153 automated tests pass. All exploratory tests pass. Migration is idempotent, data-preserving, and handles edge cases gracefully. Schema changes are purely additive with no modification to existing definitions. No blocking issues. Three low-severity specs/docs drift items documented as non-blocking observations. Approved for review.
