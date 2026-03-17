# QA Report: Setup Script Idempotency Improvement

## Scope Validated
- `scripts/setup.sh` -- full idempotency improvement (copy_if_changed, counters, change detection, verbose flag, summary)
- `scripts/db-init.sh` -- verified REQ-SETUP-010 is intentionally deferred
- `docs/setup-guide.md` -- checked for documentation drift
- `README.md` -- checked for documentation drift
- `CLAUDE.md` -- verified correct counts

## Summary
**PASS** -- All Must and Should requirements met. All 123 automated tests pass (0 skipped). All 7 manual end-to-end scenarios pass. The setup.sh script is now fully idempotent with accurate output and no regressions. Two non-blocking documentation drift issues found (setup-guide.md and README.md not updated to reflect new --verbose flag and current agent/command/hook counts). One dead code variable found (HOOKS_CHANGED).

## System Entrypoint
```bash
# From any target project directory:
bash /path/to/claude-workflow/scripts/setup.sh [--no-db] [--ext=name] [--verbose]
```

No application server to start. The system under test is a deployment shell script. Validation was performed by running setup.sh against temporary project directories and inspecting the output and filesystem results.

## Traceability Matrix Status

| Requirement ID | Priority | Has Tests | Tests Pass | Acceptance Met | Notes |
|---|---|---|---|---|---|
| REQ-SETUP-001 | Must | Yes | Yes | Yes | `copy_if_changed` uses `cmp -s`, returns new/updated/unchanged correctly |
| REQ-SETUP-002 | Must | Yes | Yes | Yes | TOTAL_NEW/UPDATED/UNCHANGED tracked and used in summary |
| REQ-SETUP-003 | Must | Yes | Yes | Yes | Core agents section uses copy_if_changed with +/~/= symbols |
| REQ-SETUP-004 | Must | Yes | Yes | Yes | Core commands section uses copy_if_changed with +/~/= symbols |
| REQ-SETUP-005 | Must | Yes | Yes | Yes | Extensions section uses copy_if_changed with +/~/= symbols |
| REQ-SETUP-006 | Must | Yes | Yes | Yes | Hooks section uses copy_if_changed; chmod +x always applied |
| REQ-SETUP-007 | Should | Yes | Yes | Yes | settings.json compares hooks JSON before writing; shows =/~/+ |
| REQ-SETUP-008 | Should | Yes | Yes | Yes | CLAUDE.md compares rules text before rewriting; shows =/~ |
| REQ-SETUP-009 | Must | Yes | Yes | Yes | Summary shows "N new, N updated, N unchanged" or "Nothing changed" |
| REQ-SETUP-010 | Could | No | N/A | N/A | Deliberately deferred (db-init.sh query files) |
| REQ-SETUP-011 | Could | Yes | Yes | Yes | --verbose flag implemented; shows = lines for each unchanged file |
| REQ-SETUP-012 | Won't | No | N/A | N/A | --dry-run deliberately deferred |

### Gaps Found
- No test gaps -- all implemented requirements have test coverage
- REQ-SETUP-010 (Could) deliberately not implemented per spec -- acceptable
- REQ-SETUP-012 (Won't) deliberately deferred per spec -- acceptable

## Acceptance Criteria Results

### Must Requirements

#### REQ-SETUP-001: copy_if_changed helper
- [x] Given destination does not exist, copies file and returns "new" -- PASS
- [x] Given destination exists but differs, copies file and returns "updated" -- PASS
- [x] Given destination exists and is identical, does NOT copy and returns "unchanged" -- PASS
- [x] Uses `cmp -s` (POSIX standard) -- PASS (verified in code, line 86)

#### REQ-SETUP-002: Per-run counters
- [x] Fresh project: NEW = total files, UPDATED/UNCHANGED = 0 -- PASS (manual: 33 new, 0 updated, 0 unchanged)
- [x] Up-to-date project: UNCHANGED = total files, NEW/UPDATED = 0 -- PASS (manual: "Nothing changed")
- [x] Partial update: correct split across all three counters -- PASS (manual: 1 updated, 32 unchanged)

#### REQ-SETUP-003: Core agents with accurate symbols
- [x] `+` symbol for new files -- PASS
- [x] `~` symbol for updated files -- PASS
- [x] Unchanged files suppressed by default, shown with `(N unchanged)` -- PASS
- [x] No `cp` executed for unchanged files (mtime preserved) -- PASS

#### REQ-SETUP-004: Core commands with accurate symbols
- [x] Same verification as REQ-SETUP-003 -- PASS

#### REQ-SETUP-005: Extensions with accurate symbols
- [x] Extension agents show +/~/= correctly -- PASS
- [x] Extension commands show +/~/= correctly -- PASS
- [x] Per-extension unchanged counts shown -- PASS

#### REQ-SETUP-006: Hooks with accurate symbols
- [x] Hooks show +/~/= correctly -- PASS
- [x] `chmod +x` always applied regardless of copy status -- PASS (verified in code, line 308)

#### REQ-SETUP-009: Summary with counts
- [x] Fresh install shows all-new count -- PASS ("33 new")
- [x] Nothing changed shows "Nothing changed -- already up to date" -- PASS
- [x] Partial update shows breakdown -- PASS ("1 updated, 32 unchanged")

### Should Requirements

#### REQ-SETUP-007: settings.json change detection
- [x] Shows `= hooks already configured` when unchanged -- PASS
- [x] Shows `~ hooks updated in settings.json` when changed -- PASS
- [x] Shows `+ settings.json created with hooks` when new -- PASS
- [x] Preserves non-hook settings (model, permissions) -- PASS
- [x] Handles malformed JSON gracefully (overwrites instead of crashing) -- PASS

#### REQ-SETUP-008: CLAUDE.md change detection
- [x] Shows `= Workflow rules already current` when identical -- PASS
- [x] Shows `~ Workflow rules updated` when different -- PASS
- [x] Skips rewrite entirely when identical (preserves mtime) -- PASS
- [x] Does not duplicate workflow section after multiple runs -- PASS (verified: exactly 1 marker after 3 runs)
- [x] Preserves project-specific content above separator -- PASS

### Could Requirements

#### REQ-SETUP-011: --verbose flag (IMPLEMENTED)
- [x] Default: suppress `=` lines, show `(N unchanged)` per section -- PASS
- [x] With `--verbose`: show all `=` lines -- PASS
- [x] Listed in `--help` output -- PASS

## End-to-End Flow Results

| Flow | Steps | Result | Notes |
|---|---|---|---|
| Fresh install (core only) | Run setup.sh on empty git project | PASS | All files deployed with `+`, summary shows "33 new" |
| Immediate re-run | Run setup.sh again with no changes | PASS | "Nothing changed -- already up to date", no `+` or `~` |
| Partial update (1 agent changed) | Modify source agent, re-run | PASS | Only changed agent shows `~`, rest "(13 unchanged)" |
| Re-run with --verbose | Run with --verbose flag | PASS | All unchanged files shown individually with `=` |
| Extension deployment | Run with --ext=blockchain | PASS | 6 new extension files, core unchanged |
| Full extension re-run | Run --ext=all twice | PASS | Second run shows "Nothing changed" for all extensions |
| CLAUDE.md preservation | Project with custom CLAUDE.md | PASS | Custom content preserved, no duplication after 3 runs |
| settings.json custom keys | Add model/permissions, re-run | PASS | Custom keys preserved, hooks unchanged |
| Malformed JSON recovery | Write invalid JSON to settings.json, re-run | PASS | Overwrites with valid config, no crash |
| Path with spaces | Project at "/tmp/qa setup test spaces" | PASS | All operations work, settings.json paths correct |
| Empty extension | Extension dir with no agents/commands | PASS | Handled gracefully, no crash |
| DB initialization | Run with DB enabled | PASS | memory.db created, schema migrated on re-run |

## Exploratory Testing Findings

| # | What Was Tried | Expected | Actual | Severity |
|---|---|---|---|---|
| 1 | Empty extension directory (no agents/commands subdirs) | Graceful handling, no crash | Shows extension name, continues to next section | low |
| 2 | Project path with spaces ("/tmp/qa setup test spaces") | All operations work correctly | All files deployed, settings.json paths correct, re-run idempotent | low |
| 3 | Malformed settings.json (invalid JSON) | Recovery without crashing (past bug) | Correctly falls through to overwrite, no set -e crash | low |
| 4 | Unchanged file mtime preservation | No cp executed, mtime unchanged | mtime preserved (verified with stat -f "%m" before/after with 2s sleep) | low |

## Failure Mode Validation

| Failure Scenario | Triggered | Detected | Recovered | Degraded OK | Notes |
|---|---|---|---|---|---|
| Malformed settings.json | Yes | Yes | Yes | Yes | try/except in python3 comparison catches JSONDecodeError, falls through to overwrite |
| Missing extension | Yes | Yes | N/A | Yes | WARNING message, continues with other extensions |
| Empty extension (no subdirs) | Yes | N/A | N/A | Yes | Silently handled, if-guards on subdirectory existence |
| python3 merge failure under set -e | Not Triggered | N/A | N/A | N/A | Theoretically possible but extremely unlikely -- merge path only reached after successful comparison |

## Security Validation

Not applicable -- setup.sh is a local deployment script that runs with the user's own permissions on local files. No network operations, no authentication, no user-supplied input beyond CLI flags.

## Specs/Docs Drift

| File | Documented Behavior | Actual Behavior | Severity |
|------|-------------------|-----------------|----------|
| docs/setup-guide.md | No mention of --verbose flag, change detection output, or idempotency summary | setup.sh has --verbose flag, shows +/~/= symbols, and provides change count summary | medium |
| docs/setup-guide.md | "13 agents, 13 commands, 4 hooks" | Actual: 14 agents, 14 commands, 5 hooks | medium |
| README.md | "13 agents, 13 commands" in setup section | Actual: 14 agents, 14 commands | medium |
| README.md | No mention of --verbose flag | setup.sh supports --verbose | low |

## Blocking Issues (must fix before merge)

None. All Must and Should requirements are met.

## Non-Blocking Observations

- **[OBS-001]**: `scripts/setup.sh` lines 409, 426 -- `HOOKS_CHANGED` variable is set but never read. Dead code that should be cleaned up. (P3)
- **[OBS-002]**: `scripts/setup.sh` lines 434-446 -- The merge python3 command runs as a standalone statement under `set -e` without a `|| fallback`. If python3 fails with an uncaught exception (e.g., FileNotFoundError), the script will exit before reaching the `if [ $? -eq 0 ]` check. Extremely unlikely since the comparison step already validated the file, but the pattern should be guarded with `||` for consistency with the comparison step. (P3)
- **[OBS-003]**: `docs/setup-guide.md` -- Does not document the --verbose flag, change detection output format, or the idempotency summary behavior. The improvement spec scope explicitly lists this file as needing update. (P2)
- **[OBS-004]**: `README.md` -- Does not mention --verbose flag in the Setup section. Minor since it references setup-guide.md for complete reference. (P3)
- **[OBS-005]**: `docs/setup-guide.md` and `README.md` -- Agent/command/hook counts are stale (say 13/13/4, actual is 14/14/5). This predates this improvement but should be corrected. (P2)

## Modules Not Validated

- `scripts/db-init.sh` query file idempotency (REQ-SETUP-010) -- "Could" priority, deliberately not implemented per spec. The current behavior (always copy) is acceptable for small reference files.

## Test Suite Results

```
Total:   123
Passed:  123
Failed:  0
Skipped: 0
```

All 123 tests pass, including the POST-IMPROVEMENT tests that were previously skipped. The test suite covers:
- First run deployment (agents, commands, hooks, structure, settings.json, CLAUDE.md)
- Second run safety (file identity, hook permissions, no CLAUDE.md duplication)
- Partial updates (modified source files)
- Extensions (deployment, re-run, missing extension, --ext=all)
- CLAUDE.md handling (existing content, creation, marker detection)
- settings.json merge (preserve custom settings, add hooks)
- --no-db and --help flags
- Output symbols (+/~/=), summary counts, --verbose flag
- settings.json and CLAUDE.md change detection
- Edge cases (empty extension, malformed JSON)
- DB initialization (schema, query files, re-run safety)

## Final Verdict

**PASS** -- All Must and Should requirements met. No blocking issues. The setup.sh idempotency improvement is fully functional with accurate change detection, correct output symbols, proper summary counts, and no regressions from the original behavior. The 5 non-blocking observations (2 at P2, 3 at P3) should be addressed in a follow-up but do not block this change.
