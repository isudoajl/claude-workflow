---
name: omega:bugfix
description: "Fix a bug with a reduced chain. Use when: something is broken, crash, error, defect, regression, 'X is not working', 'it fails when...', 'there\\'s a bug in...', unexpected behavior, wrong output, test failure, exception. Accepts optional --scope to limit context. Use --incident=INC-NNN to resume an existing incident."
---

# Workflow: Bugfix

Optional: `--scope="file or module"` to point directly at the suspected area.
Optional: `--incident=INC-NNN` to resume work on an existing incident ticket.

## Pipeline Tracking (Institutional Memory)
If `.claude/memory.db` exists, register this workflow run:

```bash
sqlite3 .claude/memory.db "INSERT INTO workflow_runs (type, description, scope) VALUES ('bugfix', 'USER_DESCRIPTION_HERE', 'SCOPE_OR_NULL');"
RUN_ID=$(sqlite3 .claude/memory.db "SELECT last_insert_rowid();")
```

Close at end: `UPDATE workflow_runs SET status='completed|failed', completed_at=datetime('now') WHERE id=$RUN_ID;`
Pass `$RUN_ID` to every agent.

## Incident Tracking

Every bugfix is tracked as an incident. Read the **@INDEX** (first 12 lines) of `.claude/protocols/incident-protocol.md` to find the section you need, then Read ONLY that section with offset/limit.

### If `--incident=INC-NNN` is provided (resuming):
1. Query the incident timeline to load full context of what was tried:
```bash
sqlite3 -header -column .claude/memory.db "SELECT entry_type, content, result FROM incident_entries WHERE incident_id='INC-NNN' ORDER BY id;"
```
2. Update status to `investigating`:
```bash
sqlite3 .claude/memory.db "UPDATE incidents SET status='investigating' WHERE incident_id='INC-NNN';"
```
3. Pass the incident timeline to the Analyst as context — do NOT retry approaches that already failed.

### If no `--incident` (new bug):
1. Auto-create an incident:
```bash
INC_ID=$(sqlite3 .claude/memory.db "SELECT 'INC-' || printf('%03d', COALESCE(MAX(CAST(SUBSTR(incident_id, 5) AS INTEGER)), 0) + 1) FROM incidents;")
sqlite3 .claude/memory.db "INSERT INTO incidents (incident_id, title, domain, description, symptoms, run_id) VALUES ('$INC_ID', 'SHORT_TITLE', 'SCOPE_OR_DOMAIN', 'USER_DESCRIPTION', 'SYMPTOMS_IF_ANY', $RUN_ID);"
```
2. Tell the user: "Tracking as **$INC_ID**. Resume in future sessions with `/omega:bugfix --incident=$INC_ID`"

### During the pipeline:
Log significant steps as incident entries (attempts, discoveries, clues). Each agent should INSERT entries as they work.

### On resolution (Step 8):
1. Close the incident:
```bash
sqlite3 .claude/memory.db "INSERT INTO incident_entries (incident_id, entry_type, content, result, agent, run_id) VALUES ('$INC_ID', 'resolution', 'WHAT_FIXED_IT', 'worked', 'developer', $RUN_ID);"
sqlite3 .claude/memory.db "UPDATE incidents SET status='resolved', root_cause='ROOT_CAUSE', resolution='HOW_FIXED', resolved_at=datetime('now') WHERE incident_id='$INC_ID';"
```
2. **Extract behavioral learning**: Ask — did this bug reveal a flaw in HOW Claude reasons? If yes, INSERT into `behavioral_learnings`. Example: if Claude guessed instead of analyzing, the learning is "Always verify X before claiming Y."

## Fail-Safe Controls

### Bug Verification
Before starting the chain, verify the bug is reproducible:
1. If the bug description includes reproduction steps, try them first
2. If the bug cannot be reproduced from the description alone, the Analyst should note this and proceed with code analysis to identify the probable cause
3. If no relevant code can be found from the bug description (even with Grep), STOP and ask the user for more context

### Iteration Limits (per milestone)
- **QA ↔ Developer iterations (Steps 4-5):** Maximum **3 iterations** per milestone. If QA still finds the bug is not fully fixed after 3 rounds, STOP and report to user: "QA iteration limit reached (3/3) for milestone M[N]. Bug status: [description]. Requires human decision."
- **Reviewer ↔ Developer iterations (Steps 6-7):** Maximum **2 iterations** per milestone. If the reviewer still finds critical issues after 2 rounds, STOP and report to user: "Review iteration limit reached (2/2) for milestone M[N]. Remaining issues: [list]. Requires human decision."

### Inter-Step Output Validation
Before invoking each agent, verify the previous agent produced its expected output:
- Before Test Writer (Step 2, each milestone): verify `docs/bugfixes/*-analysis.md` exists with the milestone's modules
- Before Developer (Step 3, each milestone): verify reproduction test file exists for the milestone's modules
- Before Compilation Validation (Step 3.5, each milestone): verify source code files exist
- Before QA (Step 4, each milestone): verify compilation & lint validation passed (build + lint + tests clean)
- Before Reviewer (Step 6, each milestone): verify QA report exists in `docs/qa/`

**If any expected output is missing, STOP the chain** and report: "CHAIN HALTED at Step [N] (Milestone M[X]): Expected output from [agent] not found. [What's missing]."

### Error Recovery
If any agent fails mid-chain:
1. Save the chain state to `docs/.workflow/chain-state.md` with:
   - Which steps completed successfully (and their output files)
   - Which step failed and why
   - What remains to be done
2. Report to user with the chain state
3. The user can resume with `/omega:resume` which auto-detects the resume point, or `/omega:resume --from="[step]"` to resume from a specific step

## Step 1: Analyst
Analyze the reported bug. **The Analyst MUST comprehend the architecture of the affected area before proposing any fix** (see Analyst's "Architecture Comprehension" mandate). A bugfix that doesn't understand the architecture is a blind patch.

1. If `--scope` provided, read only that file/module and its spec
2. If no `--scope`, use Grep to locate the relevant code from the bug description
3. Read only the affected code and related spec files
4. **Comprehend the architecture**: map module boundaries, data flows, dependency direction, and blast radius of the affected area. Document in "Architecture Context" section
5. Identify the probable cause — informed by architectural understanding, not just symptom analysis
6. Perform impact analysis — what else might be affected by the fix. This MUST be based on the architecture context, not grep-level guessing
7. Flag if the bug reveals a specs/docs drift
8. **Assess fix complexity** and define milestones if the fix requires changes across 4+ modules or the blast radius is large enough that a single agent context would be insufficient:
   - Group related modules into milestones (max 3 modules per milestone)
   - Define dependency order between milestones (fix foundational modules first)
   - Each milestone must be independently testable
   - Include a **Milestones** section in the output document with: ID, Name, Scope (Modules), Scope (Requirements), Dependencies
9. Generate requirements with IDs, priorities, and acceptance criteria for the fix

Save output to `docs/bugfixes/[name]-analysis.md`.

## Step 1.5: Milestone Plan Extraction
After the Analyst completes, parse the analysis document for milestones:

1. Read `docs/bugfixes/*-analysis.md` and look for a **Milestones** section
2. **If milestones are defined** (M1, M2, M3...): extract them into an ordered list respecting dependency order. A milestone cannot start until all its dependencies are complete.
3. **If no milestones are defined** (typical for scoped bugs): treat the entire fix as a single milestone — wrap all modules into one pass through Steps 2-8.5.
4. Save the milestone plan to `docs/.workflow/milestone-progress.md` with all milestones listed as `PENDING`.

## Steps 2-8: Milestone Loop
**For EACH milestone in dependency order**, execute the following steps. After completing all steps for a milestone, **auto-continue to the next milestone without user intervention**.

> **60% Context Budget:** Each agent invocation for a milestone must complete within 60% of its context window. The Analyst sized milestones to respect this budget (max 3 modules each). If an agent stops due to budget exhaustion, save chain state to `docs/.workflow/chain-state.md` and use `/omega:resume` to continue.

### Step 2: Test Writer (scoped to current milestone)
Write tests that REPRODUCE the bug for this milestone's modules (they must fail). Invoke the `test-writer` subagent, **scoped to the current milestone's modules only**.
1. Reference the requirement ID from the analyst's document
2. Read only the affected module's existing tests to match conventions
3. Add related edge case tests
4. Consider: does this bug pattern exist elsewhere? If so, note it.
5. All previous milestone tests must continue passing (regression)

### Step 3: Developer (scoped to current milestone)
Invoke the `developer` subagent, **scoped to the current milestone's modules only**.
Fix the bug in this milestone's modules.
The reproduction tests must pass.
Run all existing tests to check for regression.

### Step 3.5: Compilation & Lint Validation
**Mandatory gate before QA.** The developer MUST run a full compilation and lint validation pass after implementing all fixes for the current milestone:

**Rust projects** (detected via `Cargo.toml`):
1. `cargo build` — fix any compilation errors
2. `cargo clippy -- -D warnings` — fix all lint warnings
3. `cargo test` — run full test suite, ensure ALL tests pass (including previous milestones)

**Elixir projects** (detected via `mix.exs`):
1. `mix compile --warnings-as-errors` — fix compilation warnings
2. `mix dialyzer` (if configured) — fix type issues
3. `mix test` — run full test suite

**Node.js/TypeScript projects** (detected via `package.json` + `tsconfig.json`):
1. `npx tsc --noEmit` (TypeScript) or build step — fix type/compilation errors
2. `npx eslint .` (if configured) — fix lint issues
3. `npm test` or `npx jest` — run the full test suite

**General pattern** (adapt to detected language):
1. Build/compile step
2. Lint/static analysis step
3. Full test suite

If any step fails, fix and re-run. This is subject to the developer's **max 5 retry limit**. If all 3 steps pass clean, proceed to QA. If retries are exhausted, STOP and escalate.

### Step 4: QA (scoped to current milestone)
Invoke the `qa` subagent, **scoped to the current milestone**.
1. Verify the bug is actually fixed — reproduce the original scenario for this milestone's modules
2. Verify acceptance criteria from the analyst's document for this milestone
3. Test related flows — ensure the fix didn't break adjacent functionality
4. Verify the fix addresses the root cause, not just the symptom
5. Generate QA report at `docs/qa/[name]-M[N]-qa-report.md`

### Step 5: QA Iteration
If QA finds the bug is not fully fixed or the fix broke something else:
- Developer fixes → QA re-validates (scoped to fix only)
- Repeat until QA approves (max 3 iterations — see Fail-Safe Controls above)

### Step 6: Reviewer (scoped to current milestone)
Invoke the `reviewer` subagent, **scoped to the current milestone**.
Review only the changed files for this milestone.
Verify it's not a superficial patch but a root cause fix.
Verify that relevant specs/docs are updated if the bug revealed incorrect documentation.
Save output to `docs/reviews/[name]-M[N]-bugfix-review.md`.

### Step 7: Review Iteration
If the reviewer finds critical issues:
- Return to the developer with the findings
- The developer fixes them (scoped to the affected area only)
- The reviewer reviews again (scoped to the fix only)
- Repeat until approved (max 2 iterations — see Fail-Safe Controls above)

### Step 8.5: Milestone Commit & Push
After the reviewer approves the current milestone:
1. `git add` all files relevant to this milestone (source code, tests, specs, docs, QA reports, review reports)
2. `git commit` with conventional message: `fix: complete [milestone name] (M[N])`
3. `git push` to the remote
4. Update `docs/.workflow/milestone-progress.md` — mark this milestone as `COMPLETE` with timestamp

**Then AUTO-CONTINUE to the next milestone.** No user intervention needed between milestones.

### Milestone Loop Termination
The loop ends when ALL milestones are marked `COMPLETE` in the progress file. If any milestone fails (agent error, retry limit exceeded), save the chain state and report which milestones completed and which remain.

## Step 9: Final Versioning
Once ALL milestones are complete:
1. Run the full test suite one final time to verify cross-milestone integration
2. Create the final commit with `fix:` prefix (if single milestone, this is the only commit)
3. Final `git push`
4. Clean up `docs/.workflow/` temporary files (but keep `milestone-progress.md` as a record)
