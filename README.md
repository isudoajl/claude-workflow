# Claude Code Quality Workflow

A multi-agent orchestration system for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that produces high-quality code through structured validation layers. Instead of asking an AI to "build X" and hoping for the best, this workflow forces every piece of code through questioning, architecture design, test-driven development, implementation, QA validation, and review — each handled by a specialized agent with its own context window.

## The Problem

When you ask an AI to write code directly, it:
- **Assumes things** instead of asking — leading to silent bugs
- **Writes tests after code** — biasing tests toward what was built, not what should be built
- **Skips architecture** — jumping straight to implementation without thinking through design
- **Ignores context** — not reading existing code conventions, patterns, or documentation
- **Lets documentation rot** — specs and docs drift out of sync with the actual codebase
- **Has no traceability** — requirements, tests, and code aren't linked, so gaps go unnoticed

This workflow solves all of that.

## How It Works

Eleven specialized agents execute in chain or standalone, each with a single responsibility:

```
Your Idea
  ↓
💡 Discovery     → Explores and challenges your idea through conversation
  ↓
🔍 Analyst       → Questions your idea, defines requirements with acceptance criteria
  ↓
🏗️ Architect     → Designs architecture with failure modes, security, performance budgets
  ↓
🧪 Test Writer   → Writes tests BEFORE code exists (TDD, priority-driven)
  ↓
💻 Developer     → Implements module by module until all tests pass
  ↓
🔨 Compiler      → Automatic validation
  ↓
✅ QA            → Validates end-to-end functionality and acceptance criteria
  ↓
👁️ Reviewer      → Audits for bugs, security, performance, and documentation drift
  ↓
📦 Git           → Conventional commits and versioning
```

Each agent runs as a Claude Code subagent with its own isolated context window. The analyst's heavy reading doesn't eat into the developer's context. Work is scoped, incremental, and saved to disk at every step. Every agent validates its prerequisites before starting, and every multi-step command enforces iteration limits and inter-step output validation to prevent silent failures.

## Traceability Chain

Every requirement flows through the entire pipeline via unique IDs:

```
Discovery validates the idea
  → Analyst assigns REQ-XXX-001
    → Architect maps to module
      → Test Writer writes TEST-XXX-001
        → Developer implements
          → QA verifies acceptance criteria
            → Reviewer audits completeness
```

Requirements use MoSCoW priorities (Must/Should/Could/Won't). Tests are written in priority order — Must requirements get exhaustive coverage first.

## Source of Truth

```
Codebase  →  specs/  →  docs/
(ultimate)   (technical)  (user-facing)
```

The codebase always wins. When specs or docs are outdated, agents flag the discrepancy and fix it. Every agent reads the actual code before trusting any documentation.

## Agents

> For a complete inventory of every functionality, input, output, and fail-safe control for each agent, see [docs/agent-functionalities.md](docs/agent-functionalities.md).

### 💡 Discovery (`discovery.md`)
**Model:** Opus | **Tools:** Read, Grep, Glob, WebFetch, WebSearch

The idea validator. The only agent that engages in extended back-and-forth with the user. Takes a raw idea, explores the vision, challenges assumptions, identifies risks, and produces a clear Idea Brief for the Analyst. Uses web search to research patterns and inform challenges. Adapts its approach based on context — full exploration for new projects, anchored exploration for features on existing codebases. Requires explicit user approval before saving the Idea Brief to ensure the pipeline builds from a validated concept. Ensures `docs/.workflow/` exists before writing. Saves partial progress if the user abandons mid-discovery.

**Output:** `docs/.workflow/idea-brief.md` (full or lightweight template based on discovery depth)

### 🔍 Analyst (`analyst.md`)
**Model:** Opus | **Tools:** Read, Grep, Glob, WebFetch, WebSearch

The business analyst. Validates prerequisites (idea brief must exist when invoked after discovery). Reads `specs/SPECS.md` to understand the project, scopes to the relevant area, reads the actual code, then questions everything that isn't clear. Never assumes — always asks. Assigns requirement IDs with MoSCoW priorities and explicit acceptance criteria. Performs impact analysis on existing code. Flags and fixes drift between code and specs — updates stale specs to match the codebase before writing new requirements. Ensures output directories exist before writing.

**Output:** `specs/[domain]-requirements.md` with requirement IDs, acceptance criteria, traceability matrix

### 🏗️ Architect (`architect.md`)
**Model:** Opus | **Tools:** Read, Write, Edit, Grep, Glob

The designer. Validates prerequisites (analyst requirements must exist). Takes the analyst's requirements and designs the system architecture before any code is written. Defines modules, interfaces, dependencies, and implementation order. Plans failure modes and recovery strategies. Identifies security considerations and trust boundaries. Sets performance budgets. Creates and updates spec files in `specs/` and documentation in `docs/`. Ensures output directories exist before writing.

Also handles `/workflow:docs` and `/workflow:sync` — reading the codebase and bringing specs/docs back in sync. Handles missing specs/docs gracefully by creating them from scratch.

**Output:** `specs/[domain]-architecture.md`, updated specs and docs

### 🧪 Test Writer (`test-writer.md`)
**Model:** Opus | **Tools:** Read, Write, Edit, Bash, Glob, Grep

The contract writer. Validates prerequisites (architect design and analyst requirements must exist). Detects project language and adapts test structure accordingly — supports Rust, TypeScript, Python, Go, and any language with standard conventions. Writes all tests BEFORE any implementation exists, driven by requirement priorities — Must requirements first (exhaustive coverage), then Should, then Could. References requirement IDs for full traceability. Covers acceptance criteria, failure modes, security scenarios, and edge cases. Flags specs inconsistencies when tests reveal undocumented behavior. Works one module at a time, saving to disk after each.

**Output:** Test files that must fail initially (red phase of TDD)

### 💻 Developer (`developer.md`)
**Model:** Opus | **Tools:** Read, Write, Edit, Bash, Glob, Grep

The builder. Validates prerequisites (tests, architect design, and analyst requirements must exist). Reads the analyst's requirements directly for traceability. Implements the minimum code needed to pass all tests, one module at a time in the order defined by the architect. Matches existing code conventions by grepping the codebase. Never advances to the next module until the current one's tests all pass. Updates the traceability matrix's "Implementation Module" column after each module. Updates relevant specs/ and docs/ when implementation changes documented behavior. Has a max retry limit of 5 attempts per test-fix cycle — escalates after that. Handles new project scaffolding. Commits after each module.

**Cycle:** Red → Green → Refactor → Update Traceability → Sync Specs/Docs → Commit → Next

### ✅ QA (`qa.md`)
**Model:** Opus | **Tools:** Read, Write, Edit, Bash, Glob, Grep

The validator. Validates prerequisites (source code and tests must exist). Bridges the gap between "tests pass" and "it works as the user expects." Validates acceptance criteria for each requirement. Runs end-to-end flows, not just unit tests. Performs exploratory testing to find issues that scripted tests miss. Verifies failure modes and security scenarios actually behave correctly. Checks traceability matrix completeness. Verifies specs/docs accuracy against actual system behavior and flags drift. Has a "system won't start" fallback — if the system can't run, documents the error and validates what it can. Ensures `docs/qa/` exists before writing reports.

**Output:** QA validation report with acceptance criteria results, exploratory findings, and specs/docs drift

### 👁️ Reviewer (`reviewer.md`)
**Model:** Opus | **Tools:** Read, Grep, Glob (read-only)

The auditor. Validates prerequisites (source code must exist). Reviews all implemented code looking for bugs, security vulnerabilities, performance issues, technical debt, and specs/docs drift. Uses language-adaptive Grep patterns for cross-cutting scans (supports Rust, Python, TypeScript, Go, and others). Works module by module, saving findings incrementally. Brutally honest — doesn't approve out of courtesy. Can escalate architectural issues distinctly from code issues. Ensures output directories exist before writing reports.

**Output:** Review report with critical/minor findings, specs drift, and final verdict

### 📊 Functionality Analyst (`functionality-analyst.md`)
**Model:** Opus | **Tools:** Read, Grep, Glob (read-only)

The cartographer. Reads the codebase (ignoring docs — code is the single source of truth) and produces a structured inventory of everything the system does: endpoints, services, models, CLI commands, handlers, integrations, workers, migrations. Identifies dead code and unused exports. Notes cross-module dependencies.

**Output:** `docs/functionalities/[domain]-functionalities.md` and master index

### 🧠 Codebase Expert (`codebase-expert.md`)
**Model:** Opus | **Tools:** Read, Grep, Glob (read-only)

The comprehension engine. Goes beyond cataloging to build a deep understanding of any codebase — regardless of size. Works in 6 progressive layers: project shape → architecture & boundaries → domain & business logic → data flow & state → patterns & conventions → complexity & risk map. Produces a holistic understanding document that reads like a senior engineer's onboarding guide. Handles large codebases through progressive summarization with checkpoints.

**Output:** `docs/understanding/PROJECT-UNDERSTANDING.md` (or `[scope]-understanding.md`)

### 🔬 Proto-Auditor (`proto-auditor.md`)
**Model:** Opus | **Tools:** Read, Grep, Glob (read-only)

The protocol auditor. Audits protocol specifications across 12 dimensions (self-reference integrity, trust model soundness, confidence claim validity, escalation & deadlock, quorum & partition, adversarial resistance, specification completeness, enforcement realism, temporal integrity, composability, information leakage, self-audit) at 3 levels (L1: protocol, L2: enforcement, L3: self). Operates with an adversarial stance — assumes broken until proven safe. Produces structured `audit()` blocks per dimension and a `final_report()` with severity stacking and back-propagation checks.

**Output:** `c2c-protocol/audits/audit-[protocol]-[date].md`

### 🔧 Proto-Architect (`proto-architect.md`)
**Model:** Opus | **Tools:** Read, Write, Edit, Grep, Glob

The protocol improver. Consumes audit reports from Proto-Auditor and generates structured patches to close findings. Runs a 6-step pipeline: triage, root cause isolation, patch generation, self-audit, version increment, and regression check. Patches are classified into quality tiers (Tier 1: closes root cause with no new surface, down to Tier 4: rejected). Never adds complexity without closing a finding. Never patches symptoms when root causes are reachable.

**Output:** `c2c-protocol/patches/patches-[protocol]-[date].md`

## Commands

| Command | Description | Agents Used |
|---------|-------------|-------------|
| `/workflow:new "idea"` | Build something from scratch | discovery → analyst → architect → test-writer → developer → QA → reviewer |
| `/workflow:new-feature "feature"` | Add to existing project | (discovery) → analyst → architect → test-writer → developer → QA → reviewer |
| `/workflow:improve-functionality "improvement"` | Refactor, optimize, or enhance | analyst → test-writer → developer → QA → reviewer |
| `/workflow:bugfix "bug"` | Fix a bug | analyst → test-writer → developer → QA → reviewer |
| `/workflow:audit` | Full code + specs audit | Reviewer only |
| `/workflow:docs` | Generate/update specs & docs | Architect only |
| `/workflow:sync` | Fix drift between code and specs/docs | Architect only |
| `/workflow:functionalities` | Map all codebase functionalities | Functionality Analyst only |
| `/workflow:understand` | Deep codebase comprehension | Codebase Expert only |
| `/workflow:c2c` | Multi-round C2C protocol (writer ↔ auditor) | Writer + Auditor (up to 5 rounds) |
| `/workflow:proto-audit` | Audit a protocol specification (12 dimensions, 3 levels) | Proto-Auditor only |
| `/workflow:proto-improve` | Improve protocol based on audit findings | Proto-Architect only |

### Scope Parameter

All commands accept `--scope` to limit context usage on large codebases:

```bash
/workflow:new-feature "add retry logic" --scope="omega-providers"
/workflow:audit --scope="omega-core"
/workflow:sync --scope="omega-memory"
/workflow:bugfix "scheduler crash" --scope="backend/src/gateway/scheduler.rs"
```

When no scope is provided, the analyst determines the minimal scope needed.

## Fail-Safe Controls

The workflow is reinforced with guardrails at every level to prevent silent failures, infinite loops, and cascading garbage.

### Prerequisite Gates
Every agent validates its upstream input before starting. If required input is missing, the agent **stops immediately** with a clear error message identifying what's missing and which upstream agent failed.

### Iteration Limits
Multi-step commands enforce maximum iteration counts:
- **QA ↔ Developer:** max 3 iterations
- **Reviewer ↔ Developer:** max 2 iterations

If limits are reached, the workflow stops and reports remaining issues to the user.

### Inter-Step Output Validation
Before invoking each agent, the command verifies the previous agent produced its expected output file. Missing output halts the chain with a clear report.

### Error Recovery
If any agent fails mid-chain, the workflow saves chain state to `docs/.workflow/chain-state.md` — what completed, what failed, what remains. The user can resume from the failed step.

### Directory Safety
Agents create target directories before writing (e.g., `docs/qa/`, `docs/reviews/`, `specs/`). No silent file-write failures.

### Language-Agnostic
Test-writer and reviewer adapt to the project's language (Rust, Python, TypeScript, Go, etc.) by detecting config files and existing source. No language is assumed.

## Context Window Management

This workflow is designed for real-world codebases that exceed a single context window. Every agent follows these rules:

- **Read indexes first** — `specs/SPECS.md` gives the project layout without reading every file
- **Grep before Read** — search for symbols and patterns before loading whole files
- **Work one module at a time** — never load everything into context simultaneously
- **Save to disk incrementally** — tests, code, and findings are written to files after each module
- **Checkpoint on large operations** — audit, docs, and sync process one milestone at a time with progress saved to `docs/.workflow/`
- **Never silently degrade** — if an agent can't finish, it states exactly what was skipped and recommends a scoped follow-up
- **Clean up** — temporary `docs/.workflow/` files are removed after workflow completion

## Installation

### Quick Install (existing project)

```bash
# Clone the workflow repo
git clone <repo-url> claude-workflow

# Copy agents and commands into your project
mkdir -p .claude/agents .claude/commands
cp claude-workflow/.claude/agents/*.md .claude/agents/
cp claude-workflow/.claude/commands/*.md .claude/commands/
```

> **Note:** Do not copy CLAUDE.md — each project should have its own. Merge the workflow rules from `claude-workflow/CLAUDE.md` into your project's CLAUDE.md manually (see [Integrate With Existing CLAUDE.md](#integrate-with-existing-claudemd)).

### Setup Script (new project)

```bash
git clone <repo-url> claude-workflow
cd my-project
bash ../claude-workflow/scripts/setup.sh
```

The setup script copies agents and commands, creates `specs/SPECS.md` and `docs/DOCS.md` if they don't exist, and never overwrites existing files (except agents and commands which are always kept in sync).

## Project Structure

The workflow expects (and creates if missing) this structure:

```
your-project/
├── CLAUDE.md                  ← Workflow rules (read by Claude Code on startup)
├── backend/                   ← Backend source code
│   ├── src/
│   └── tests/
├── frontend/                  ← Frontend source code (if applicable)
│   ├── src/
│   └── tests/
├── specs/
│   ├── SPECS.md               ← Master index of all technical specs
│   ├── domain-a.md            ← Per-domain spec files
│   └── domain-b.md
├── docs/
│   ├── DOCS.md                ← Master index of all documentation
│   ├── quickstart.md          ← Topic-oriented guides
│   ├── architecture.md
│   ├── .workflow/             ← Temporary agent checkpoints (auto-cleaned)
│   ├── reviews/               ← Code review reports
│   ├── audits/                ← Audit reports
│   ├── sync/                  ← Sync/drift reports
│   ├── functionalities/       ← Codebase functionality inventories
│   └── understanding/        ← Deep codebase comprehension documents
├── .claude/
│   ├── agents/                ← Subagent definitions
│   │   ├── discovery.md
│   │   ├── analyst.md
│   │   ├── architect.md
│   │   ├── test-writer.md
│   │   ├── developer.md
│   │   ├── qa.md
│   │   ├── reviewer.md
│   │   ├── functionality-analyst.md
│   │   ├── codebase-expert.md
│   │   ├── proto-auditor.md
│   │   └── proto-architect.md
│   └── commands/              ← Slash commands
│       ├── workflow-new.md
│       ├── workflow-new-feature.md
│       ├── workflow-improve-functionality.md
│       ├── workflow-bugfix.md
│       ├── workflow-audit.md
│       ├── workflow-docs.md
│       ├── workflow-sync.md
│       ├── workflow-functionalities.md
│       ├── workflow-understand.md
│       ├── workflow-proto-audit.md
│       └── workflow-proto-improve.md
└── .gitignore
```

Code lives in `backend/` (and optionally `frontend/`). Specs and docs remain at the project root. Agents are aware of this structure when scoping reads and writes.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed (`npm install -g @anthropic-ai/claude-code`)
- Claude Pro or Max subscription
- Git
- Rust toolchain (recommended) or your preferred language

## Customization

### Change Language
Edit `CLAUDE.md` and change:
```
- Preferred language: Rust
```
To your preferred language. All agents adapt automatically — the test-writer will match your language's test conventions, the developer will follow your language's patterns.

### Add Custom Agents
Create a `.md` file in `.claude/agents/` with the frontmatter format:
```yaml
---
name: your-agent
description: When to invoke this agent
tools: Read, Write, Edit, Bash, Glob, Grep
model: sonnet
---

Your agent instructions here...
```

### Modify Workflows
Edit commands in `.claude/commands/` to change agent chain order, add steps, or create new workflow modes.

### Integrate With Existing CLAUDE.md
If your project already has a `CLAUDE.md`, merge the workflow rules from this project's `CLAUDE.md` into yours — specifically the Source of Truth Hierarchy, Global Rules, Traceability Chain, and Context Window Management sections.

## Workflow Details

### `/workflow:new` — Full Pipeline

```
Step 1: Discovery  → explores and challenges the idea with the user, produces Idea Brief
Step 2: Analyst    → questions user, generates requirements with IDs, priorities, acceptance criteria
Step 3: Architect  → designs architecture with failure modes, security, performance budgets
Step 4: Test Writer→ writes failing tests by priority (Must first), references requirement IDs
Step 5: Developer  → implements module by module until green, commits each
Step 6: QA         → validates acceptance criteria, runs end-to-end and exploratory tests
Step 7: Reviewer   → audits code + specs drift, approves or sends back
Step 8: Iteration  → developer fixes → reviewer re-reviews (scoped to fix only)
Step 9: Versioning → final commit, version tag, cleanup temp files
```

### `/workflow:new-feature` — Same as New, Context-Aware

Same pipeline but every agent reads existing code first. Discovery is invoked when the feature description is vague; skipped for specific, well-scoped features. The analyst checks for specs drift and performs impact analysis. The test-writer matches existing test conventions. All previous tests must continue passing (regression).

### `/workflow:improve-functionality` — Refactor and Optimize

```
Step 1: Analyst    → reads current code, identifies what to improve (no new requirements)
Step 2: Test Writer→ writes regression tests to lock in existing behavior
Step 3: Developer  → refactors/optimizes, all tests must still pass
Step 4: QA         → validates behavior hasn't changed despite improvements
Step 5: Reviewer   → verifies improvement is real, no behavior changes slipped in
```

Skips the architect since the architecture already exists. The analyst focuses on code quality, performance, and patterns rather than questioning new requirements. Behavior stays the same — only the implementation gets better.

### `/workflow:bugfix` — Reduced Chain

```
Step 1: Analyst    → locates bug in code (Grep), performs impact analysis
Step 2: Test Writer→ writes a test that reproduces the bug (must fail)
Step 3: Developer  → fixes bug, reproduction test passes, no regression
Step 4: QA         → reproduces original scenario, validates root cause fix
Step 5: Reviewer   → verifies root cause fix (not a patch), checks specs
```

### `/workflow:audit` — Read-Only Analysis

Reviewer scans the codebase looking for security issues, performance problems, technical debt, dead code, missing tests, and documentation drift. On large codebases, works one milestone at a time with checkpoints. Produces a comprehensive report at `docs/audits/`.

### `/workflow:docs` — Documentation Generation

Architect reads the codebase (source of truth) and creates or updates specs and docs to match reality. Works one milestone at a time on large projects.

### `/workflow:sync` — Drift Detection and Fix

Architect compares every spec and doc file against the actual code. Produces a drift report showing stale specs, missing specs, orphaned docs, and index gaps. Then fixes everything found. Report saved to `docs/sync/`.

### `/workflow:functionalities` — Codebase Inventory

Functionality Analyst reads the source code (ignoring documentation) and maps everything the system does: endpoints, services, models, CLI commands, handlers, integrations, workers, and migrations. Identifies dead code and cross-module dependencies. Produces structured inventories at `docs/functionalities/`.

### `/workflow:understand` — Deep Codebase Comprehension

Codebase Expert progressively builds a holistic understanding of any project, regardless of size. Works through 6 layers:

```
Layer 1: Project Shape      → languages, frameworks, directory organization, build system
Layer 2: Architecture       → modules, boundaries, dependency direction, bootstrap flow
Layer 3: Domain Logic       → core entities, relationships, business workflows
Layer 4: Data Flow          → entry → processing → storage → exit, config flow
Layer 5: Patterns           → conventions, architectural patterns, the "template" for new features
Layer 6: Complexity & Risk  → high-complexity areas, security-sensitive paths, technical debt
```

Handles large codebases through progressive summarization — saves checkpoints to `docs/.workflow/` after each layer pair. If it can't finish, it tells you exactly what was covered and what remains. Produces a comprehensive understanding document at `docs/understanding/` that reads like an onboarding guide for a senior engineer.

### `/workflow:proto-audit` — Protocol Specification Audit

Proto-Auditor runs a full adversarial audit on a protocol specification across 12 dimensions at 3 levels:

```
D1:  Self-Reference Integrity       D7:  Specification Completeness
D2:  Trust Model Soundness          D8:  Enforcement Realism
D3:  Confidence Claim Validity      D9:  Temporal & Ordering Integrity
D4:  Escalation & Deadlock          D10: Composability & Cross-Layer
D5:  Quorum & Partition             D11: Information Leakage & Side Channels
D6:  Adversarial Agent Resistance   D12: Self-Audit (Auditor Integrity)
```

Levels: L1 (protocol spec), L2 (enforcement layer), L3 (self-audit). Outputs structured `audit()` blocks per dimension and a `final_report()` with severity stacking, back-propagation, and deployment conditions. Findings are classified as CRITICAL, MAJOR, or MINOR. The overall verdict scale is: broken → degraded → hardened → production-ready.

**Output:** `c2c-protocol/audits/audit-[protocol]-[date].md`

### `/workflow:proto-improve` — Protocol Improvement from Audit

Proto-Architect consumes an audit report and generates structured patches through a 6-step pipeline:

```
P1: Triage         → classify findings, group by root cause, order dependencies
P2: Root Cause     → isolate layer (axiom/rule/meta/implicit), determine scope
P3: Patch Gen      → generate patches (amend/extend/add/deprecate/axiom/define)
P4: Self-Audit     → reject patches that add complexity without closing findings
P5: Version        → classify version bump (major/minor)
P6: Regression     → verify patches don't break interacting rules
```

Patches are quality-tiered: Tier 1 (closes root cause, no new surface) through Tier 4 (rejected). Structural changes require operator approval. CRITICAL findings cannot be closed with symptom-only patches without sign-off. Patch batches are atomic — all pass or none apply.

**Output:** `c2c-protocol/patches/patches-[protocol]-[date].md`

### `/workflow:c2c` — Multi-Round C2C Protocol

A proof-of-concept for multi-round agent-to-agent conversations using the C2C protocol. Two agents iterate in a loop:

```
Round 1: Writer produces code → Auditor audits and finds issues
Round 2: Writer fixes/defends/concedes → Auditor re-audits changes
Round 3: ...continues until certification or max 5 rounds
```

**Agent A (Writer):** Produces production code with persuasive documentation. Self-assesses honestly using confidence tags. Responds to audit findings with `FIX`, `DEFENSE`, or `CONCESSION` messages.

**Agent B (Auditor):** Audits code line-by-line, fact-checks confidence claims, verifies R04 compliance (accuracy > persuasion). Issues `CERTIFICATION` when code meets production standards (`accepted`, `conditional`, or `rejected`).

Both agents communicate exclusively through structured `msg()` blocks with mandatory `conf()` and `src()` tags on every claim. The orchestrator manages turn numbering, conversation history, and context compression across rounds.

**Output:** Per-round transcripts in `poc/c2c-protocol/rounds/` and a `RESULTS.md` summarizing bugs found/fixed, defenses, concessions, and certification status.

## Philosophy

> "The best code is the one that went through multiple layers of questioning before it existed."

This workflow exists because:
- Without constraints, AI assumes things and generates silent bugs
- Tests written after code are biased toward what was built, not what should be built
- Requirements without acceptance criteria and priorities lead to vague implementations
- Traceability from requirement to test to code catches gaps that informal processes miss
- A strict compiler (Rust) compensates for AI weaknesses in ways a dynamic language can't
- QA validation catches issues that unit tests alone miss — "tests pass" doesn't mean "it works"
- Code review by a separate instance catches what the original missed
- Documenting before coding forces clarity of thought
- Specs and docs drift silently — automated sync catches it before it becomes a liability
- Context limits are real — scoping and chunking prevent quality degradation on large codebases

## License

MIT
