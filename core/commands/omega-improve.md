---
name: omega:improve
description: "Improve existing code — refactor, optimize, or enhance without adding new features. Use when: refactoring, performance optimization, code cleanup, simplification, 'make this faster', 'clean up...', 'refactor...', 'optimize...', reduce complexity, improve readability, technical debt. Accepts optional --scope to limit context."
---

# Workflow: Improve Existing Code

The user wants to improve code that already works — refactoring, performance optimization, code quality enhancement, or simplification.
This is NOT for adding new features or fixing bugs. The behavior should stay the same; the implementation gets better.
Optional: `--scope="area"` to limit which part of the codebase is analyzed.

**CRITICAL: Every modification requires architectural understanding first.** Even "just a refactor" can break invariants, violate contracts, or cascade through dependent modules. The Analyst MUST comprehend the architecture of the affected area before proposing any improvement (see Analyst's "Architecture Comprehension" mandate). The Developer MUST read this architecture context before writing a single line of code.

## Pipeline Tracking (Institutional Memory)
If `.claude/memory.db` exists, register this workflow run:

```bash
sqlite3 .claude/memory.db "INSERT INTO workflow_runs (type, description, scope) VALUES ('improve', 'USER_DESCRIPTION_HERE', 'SCOPE_OR_NULL');"
RUN_ID=$(sqlite3 .claude/memory.db "SELECT last_insert_rowid();")
```

Close at end: `UPDATE workflow_runs SET status='completed|failed', completed_at=datetime('now') WHERE id=$RUN_ID;`
Pass `$RUN_ID` to every agent.

## Existing Code Validation
Before starting, verify there is code to improve:
1. Check for source code files in the project. If none exist, this workflow is inapplicable — inform the user.
2. If `specs/SPECS.md` does not exist, proceed but note: "No specs found. Improvement analysis will be based solely on codebase reading."

## Fail-Safe Controls

### Iteration Limits (per milestone)
- **QA ↔ Developer iterations (Steps 4-5):** Maximum **3 iterations** per milestone. If QA still finds behavioral changes or broken flows after 3 rounds, STOP and report to user: "QA iteration limit reached (3/3) for milestone M[N]. Remaining issues: [list]. Requires human decision."
- **Reviewer ↔ Developer iterations (Steps 6-7):** Maximum **2 iterations** per milestone. If the reviewer still finds issues after 2 rounds, STOP and report to user: "Review iteration limit reached (2/2) for milestone M[N]. Remaining issues: [list]. Requires human decision."

### Inter-Step Output Validation
Before invoking each agent, verify the previous agent produced its expected output:
- Before Test Writer (Step 2, each milestone): verify `docs/improvements/*-improvement.md` exists with the milestone's modules
- Before Developer (Step 3, each milestone): verify test files exist (new regression tests or confirmation that existing tests suffice)
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

## Step 1: Analyst (improvement-focused)
Invoke the `analyst` subagent. It MUST:
1. Read `specs/SPECS.md` index (not all files)
2. If `--scope` provided, read only that area's specs and code
3. If no `--scope`, determine minimal scope from the improvement description
4. **Comprehend the architecture** of the affected area (mandatory — see Analyst's "Architecture Comprehension" mandate):
   - Map module boundaries, data flows, and dependency direction
   - Identify what depends on the code being improved — both directly and indirectly
   - Document architectural constraints and invariants that the improvement must preserve
   - Save as "Architecture Context" section in the output document
5. Read the **actual code** in the scoped area — focus on:
   - Code smells (duplication, long functions, deep nesting, unclear naming)
   - Performance issues (unnecessary allocations, O(n^2) where O(n) is possible, blocking calls)
   - Complexity (can this be simplified without losing functionality?)
   - Pattern violations (code that doesn't match the project's established conventions)
6. Perform impact analysis — informed by architecture context, not just grep-level code reading
7. Ask clarifying questions about the desired improvement direction
8. **Assess scope size** and define milestones if the improvement touches 4+ modules or requires changes that would exceed a single agent's 60% context budget:
   - Group related modules into milestones (max 3 modules per milestone)
   - Define dependency order between milestones
   - Each milestone must be independently testable
   - Include a **Milestones** section in the output document with: ID, Name, Scope (Modules), Scope (Requirements), Dependencies
9. Generate a requirements document with IDs, priorities, and acceptance criteria that specifies:
   - What the current code does (behavior to preserve)
   - What specifically will be improved
   - What will NOT change (explicit boundaries)
   - What architectural invariants must be preserved

Save output to `docs/improvements/[domain]-improvement.md`.

## Step 1.5: Milestone Plan Extraction
After the Analyst completes, parse the improvement document for milestones:

1. Read `docs/improvements/*-improvement.md` and look for a **Milestones** section
2. **If milestones are defined** (M1, M2, M3...): extract them into an ordered list respecting dependency order. A milestone cannot start until all its dependencies are complete.
3. **If no milestones are defined** (typical for small improvements): treat the entire improvement as a single milestone — wrap all modules into one pass through Steps 2-8.5.
4. Save the milestone plan to `docs/.workflow/milestone-progress.md` with all milestones listed as `PENDING`.

## Steps 2-8: Milestone Loop
**For EACH milestone in dependency order**, execute the following steps. After completing all steps for a milestone, **auto-continue to the next milestone without user intervention**.

> **60% Context Budget:** Each agent invocation for a milestone must complete within 60% of its context window. The Analyst sized milestones to respect this budget (max 3 modules each). If an agent stops due to budget exhaustion, save chain state to `docs/.workflow/chain-state.md` and use `/omega:resume` to continue.

### Step 2: Test Writer (regression-focused, scoped to current milestone)
Invoke the `test-writer` subagent, **scoped to the current milestone's modules only**. It MUST:
1. Read the analyst's improvement document (IDs, priorities, acceptance criteria) for this milestone
2. Read existing tests for the affected modules in this milestone
3. Write **regression tests** that lock in current behavior BEFORE any changes
4. Reference requirement IDs for traceability
5. Cover edge cases that the improvement might accidentally break
6. If existing tests already cover the behavior well, state that and add only missing edge cases
7. All previous milestone tests must continue passing (regression)

The goal is a safety net: after the improvement, all tests must still pass.

### Step 3: Developer (refactor-focused, scoped to current milestone)
Invoke the `developer` subagent, **scoped to the current milestone's modules only**. It MUST:
1. Read the analyst's improvement document and the test suite for this milestone
2. Read the scoped codebase to understand current conventions
3. Implement the improvement one module at a time
4. After each change, run ALL tests (new regression tests + existing tests)
5. Never change behavior — only implementation
6. Commit after each module with `refactor:` or `perf:` prefix

### Step 3.5: Compilation & Lint Validation
**Mandatory gate before QA.** The developer MUST run a full compilation and lint validation pass after implementing all modules for the current milestone:

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

### Step 4: QA (regression-focused, scoped to current milestone)
Invoke the `qa` subagent, **scoped to the current milestone**. It MUST:
1. Verify that behavior has NOT changed — run end-to-end flows before and after comparison
2. Verify acceptance criteria (the improvement targets were met) for this milestone
3. Check that no functionality was accidentally removed or altered
4. Validate that performance improvements are measurable (if applicable)
5. Generate QA report at `docs/qa/[name]-M[N]-qa-report.md`

### Step 5: QA Iteration
If QA finds behavioral changes or broken flows:
- Developer fixes → QA re-validates (scoped to fix only)
- Repeat until QA confirms behavior is preserved

### Step 6: Reviewer (improvement-focused, scoped to current milestone)
Invoke the `reviewer` subagent, **scoped to the current milestone**. It MUST:
1. Verify the improvement actually improves things (not just reshuffling)
2. Confirm no behavior changes slipped in
3. Check that all tests pass (regression + existing)
4. Verify specs/docs are still accurate after the changes
5. Look for opportunities missed or improvements that went too far

Save output to `docs/reviews/[name]-M[N]-improvement-review.md`.

### Step 7: Review Iteration
If the reviewer finds issues:
- Return to the developer with findings (scoped to affected module only)
- Developer fixes → reviewer re-reviews (scoped to fix only)
- Repeat until approved

### Step 8.5: Milestone Commit & Push
After the reviewer approves the current milestone:
1. `git add` all files relevant to this milestone (source code, tests, specs, docs, QA reports, review reports)
2. `git commit` with conventional message: `refactor: complete [milestone name] (M[N])` or `perf: complete [milestone name] (M[N])`
3. `git push` to the remote
4. Update `docs/.workflow/milestone-progress.md` — mark this milestone as `COMPLETE` with timestamp

**Then AUTO-CONTINUE to the next milestone.** No user intervention needed between milestones.

### Milestone Loop Termination
The loop ends when ALL milestones are marked `COMPLETE` in the progress file. If any milestone fails (agent error, retry limit exceeded), save the chain state and report which milestones completed and which remain.

## Step 9: Final Versioning
Once ALL milestones are complete:
1. Run the full test suite one final time to verify cross-milestone integration
2. Create the final version tag
3. Final `git push --tags`
4. Clean up `docs/.workflow/` temporary files (but keep `milestone-progress.md` as a record)
