# Idea Brief: OMEGA Cortex -- Collective Intelligence Layer

## One-Line Summary
Transform OMEGA from a solo-developer tool into a collective intelligence system where resolved incidents, behavioral learnings, and hotspot maps automatically propagate across all team members through a hybrid local-SQLite + git-tracked shared knowledge architecture, mediated by an intelligent Knowledge Curator agent.

## Problem Statement
Every developer's OMEGA instance is an isolated brain. Learnings, incidents, hotspots, behavioral corrections, patterns, and failed approaches stay locked in individual `.claude/memory.db` files. When Developer A spends two hours diagnosing a race condition, Developer B has zero access to that knowledge trail. When Developer C corrects Claude's behavior ("never mock the database in integration tests"), Developers A and B will each have to discover that same lesson independently. The team does not get collectively smarter -- each developer starts from scratch in areas where their teammates have already paid the learning cost. This is the antithesis of institutional memory: it is institutional amnesia.

## Current State
- **memory.db is local-only**: Gitignored (correctly -- SQLite on shared/network filesystems is unsafe). Each project gets one DB per developer machine.
- **No sharing mechanism**: No export, import, sync, or merge capability exists for memory.db contents.
- **Behavioral learnings already have `source_project`**: The schema tracks which project a learning came from, but has no `contributor` or `shared` flag.
- **Incidents have full timelines**: The `incidents` + `incident_entries` tables already capture the complete diagnostic trail (hypotheses, attempts, discoveries, root cause, resolution). This data is extremely valuable to share but currently dies with the developer who resolved it.
- **Hotspots are per-developer**: File risk levels are based on one developer's experience. A file that burns three different developers still shows as "low" for the fourth developer who has not touched it yet.
- **Briefing hook fires once per session**: `briefing.sh` already injects behavioral learnings and open incidents into context at session start. This is the natural import point for shared knowledge.
- **Confidence scoring exists**: `behavioral_learnings.confidence` and `lessons.confidence` already use 0.0-1.0 scoring with reinforcement tracking. This pattern extends naturally to shared knowledge.
- **Schema uses `CREATE TABLE IF NOT EXISTS`**: Migration path for additive changes already works across deployed projects.

## Proposed Solution
Build a **hybrid sync architecture** with three components:

### Component 1: Local Memory (unchanged)
`memory.db` remains the fast, local, real-time store. All 15 agents read/write locally exactly as today. Zero latency, zero network dependencies, zero risk of SQLite corruption from concurrent access. This is the performance layer.

### Component 2: Shared Knowledge Store (new)
A `.omega/shared/` directory in the project repository (git-tracked). Contains curated, high-value knowledge exported from individual developers' memory.db instances. Organized by category:
- `behavioral-learnings.jsonl` -- team-wide behavioral corrections
- `incidents/` -- one file per resolved incident (full timeline)
- `hotspots.jsonl` -- aggregated file risk data
- `lessons.jsonl` -- distilled domain-specific patterns
- `patterns.jsonl` -- successful patterns discovered
- `decisions.jsonl` -- architectural decisions with rationale

Format designed for minimal git merge conflicts (JSONL = one entry per line, append-only by default, each entry has a UUID for deduplication).

### Component 3: Knowledge Curator Agent (new)
An intelligent middleware agent that bridges local to shared. This is the KEY design element -- not a dumb export script, but an agent that evaluates what is worth sharing:
- **Relevance filter**: Is this team-relevant or personal? (A user's communication preference is personal; "never use `unwrap()` in production paths" is team-relevant.)
- **Confidence threshold**: Only promote entries above a confidence threshold (e.g., 0.7). Low-confidence learnings need more local reinforcement first.
- **Redundancy check**: Is this already in the shared store? If yes, reinforce (bump confidence/occurrences) rather than duplicate.
- **Conflict detection**: If a new learning contradicts an existing shared one, flag for human resolution rather than silently overwriting.
- **Reinforcement merging**: When the same learning arrives from 2+ developers independently, boost confidence significantly -- this is strong signal.

## Target Users
- **Primary**: Development teams (2+) using OMEGA on shared repositories -- they need collective learning to avoid redundant debugging, propagate best practices, and build a shared understanding of fragile areas.
- **Secondary**: Solo developers working across multiple machines or contexts -- the shared store acts as a persistent backup and cross-machine sync mechanism via git, and the curator still provides curation value (filtering noise from signal).
- **Design principle**: Works identically for 1 developer or N. No artificial team-size limits. The architecture scales naturally because git handles distribution and the curator handles curation regardless of team size.

## Success Criteria
- Developer A resolves INC-042 (race condition in auth). Developer B starts a session the next day after pulling. During briefing, OMEGA surfaces the shared incident. When Developer B encounters similar symptoms, the diagnostician says: "This resembles INC-042 -- race condition pattern in auth module. See resolution."
- Developer A corrects Claude: "never mock the database in integration tests." After git sync, Developer B's test-writer agent already knows this rule without Developer B ever being corrected.
- Three developers each log an incident in the payments module within a week. The shared hotspot map flags "payments module -- 3 incidents in 7 days across 3 developers, systemic instability suspected." Every developer sees this in their next briefing.
- A solo developer uses OMEGA Cortex and sees no degradation vs. current behavior. The curator runs, the shared store exists, but the experience is seamless.
- Existing OMEGA projects that do NOT opt into Cortex continue working exactly as before. Full backward compatibility.

## MVP Scope
All capabilities below are v1. Ordered by implementation dependency:

### 1. Shared Knowledge Store (foundation)
- `.omega/shared/` directory structure, initialized by setup.sh
- JSONL file format with UUID-based entries, contributor attribution, timestamps
- Categories: behavioral_learnings, incidents (with timelines), hotspots, lessons, patterns, decisions
- `.gitignore` updated: `memory.db` stays ignored, `.omega/shared/` is tracked
- Each entry includes: `uuid`, `contributor` (git user), `source_project`, `created_at`, `confidence`, `occurrences`, category-specific fields

### 2. Knowledge Curator Agent (intelligence layer)
- New agent: `core/agents/curator.md`
- Evaluates memory.db entries for team relevance, confidence, and redundancy
- Promotes qualifying entries to `.omega/shared/` files
- Handles deduplication (UUID + content-hash matching)
- Handles reinforcement (same learning from multiple developers = confidence boost)
- Flags contradictions for human resolution (writes to `conflicts.jsonl` or logs a warning)
- Triggerable automatically (via hook after significant memory writes) and manually (via command)

### 3. Import at Briefing (consumption)
- `briefing.sh` enhanced: at session start, reads `.omega/shared/` files
- Imports new entries (not already in local memory.db) into local tables
- Uses a `shared_imports` tracking table to avoid re-importing
- Shared behavioral learnings injected alongside local ones
- Shared incidents available for diagnostician queries
- Shared hotspot data merged with local hotspot data

### 4. Schema Additions (plumbing)
- New columns on shareable tables: `contributor TEXT`, `shared_uuid TEXT`, `is_shared INTEGER DEFAULT 0`
- New table: `shared_imports` -- tracks which shared UUIDs have been imported (prevents re-import)
- `ALTER TABLE ADD COLUMN` with `CREATE TABLE IF NOT EXISTS`-style checks for backward-compatible migration

### 5. Export/Import Commands (user interface)
- `/omega:share` -- manually trigger the curator to evaluate and export. Also usable for force-sharing specific entries.
- `/omega:team-status` -- dashboard showing: shared knowledge stats (counts by category), recent contributions (who shared what, when), active shared incidents, team hotspot map, any unresolved conflicts.

### 6. Shared Incident Registry (high-value knowledge)
- Curator exports resolved incidents with full timeline: title, domain, symptoms, root cause, resolution, all entries (hypotheses, attempts, discoveries), prevention rules
- Exported as one JSON file per incident in `.omega/shared/incidents/INC-NNN.json`
- Diagnostician agent enhanced: queries shared incidents for pattern matching during diagnosis
- Incident correlation: curator detects related incidents from multiple contributors and notes the relationship

### 7. Shared Behavioral Learnings (team evolution)
- Curator exports high-confidence behavioral learnings to `.omega/shared/behavioral-learnings.jsonl`
- Confidence boosted when reinforced by multiple contributors independently
- Decay: learnings not reinforced over N sessions/time-period lose confidence (existing decay_log mechanism extends)
- Briefing imports these and makes them available to all agents

### 8. Shared Hotspot Map (collective risk awareness)
- Curator aggregates hotspot data from memory.db into `.omega/shared/hotspots.jsonl`
- Weighted by: number of contributors who flagged the area, recency of incidents, incident severity
- Cross-contributor correlation: "3 developers hit issues in payments/ this week"
- Briefing surfaces shared hotspots alongside local ones, with attribution

### 9. Contributor Attribution (context, not blame)
- Every shared entry tracks who contributed it and in what context
- `/omega:team-status` shows contributor activity
- Surfaced during briefing for context: "Learned from Developer A during the payments refactor (INC-042)"

## Explicitly Out of Scope
- **Real-time sync**: No WebSocket, no server, no push notifications. Git pull/push is the sync mechanism.
- **Central server/service**: No hosted component. Everything is files in the repo and local SQLite. Zero infrastructure requirements.
- **Access control/permissions**: No fine-grained sharing permissions. If you have git access, you participate in shared knowledge.
- **Cross-project knowledge sharing**: Cortex shares within a single repository. Cross-repo sharing is a future capability.
- **Automatic conflict resolution**: Curator flags contradictions; humans resolve them.
- **UI/dashboard**: No web interface. `/omega:team-status` is CLI output.
- **Shared user profiles**: The Persona system remains per-developer. Communication preferences are personal.

## Key Decisions Made
- **Hybrid architecture (local SQLite + git-tracked files)**: SQLite on network/shared filesystems is unsafe (locking issues, corruption risk). Git-tracked files solve distribution, versioning, and conflict visibility. Local SQLite solves real-time performance. The user chose "Option C -- Hybrid" explicitly.
- **JSONL format for shared files**: One JSON object per line. Append-friendly, git-mergeable (line-level conflicts), grep-friendly. Each entry self-contained with UUID for dedup.
- **Automatic curation with agent intelligence**: The user explicitly chose "automatic but with an agent middleware to filter the noise." The curator evaluates relevance, confidence, and redundancy.
- **All three knowledge types in v1**: The user explicitly stated incidents, behavioral learnings, AND hotspot maps are all critical for v1.
- **Scales from 1 to N developers**: No artificial limits. Same architecture, same code paths.
- **One file per incident, JSONL for everything else**: Incidents have rich timeline data that benefits from standalone files. Other categories use append-only JSONL.
- **Briefing hook is the import point**: Existing `briefing.sh` already fires once per session. Adding shared knowledge import here is architecturally clean.
- **Git handles distribution**: No custom sync protocol. `git pull` gets the team's knowledge. `git push` shares yours.

## Directions Explored and Rejected
- **Pure SQLite replication (shared memory.db)**: Rejected -- SQLite does not support concurrent writes from different machines safely. WAL mode helps locally but not over network.
- **Central sync server**: Rejected -- adds infrastructure and availability dependencies. OMEGA's philosophy is zero-infrastructure.
- **Manual-only sharing**: Rejected per user preference -- automatic curation is primary. Manual remains as supplement.
- **Phased v1 (incidents only)**: Rejected -- user stated all three knowledge types are critical. The architecture supports all three with the same plumbing.
- **Shared SQLite DB committed to git**: Rejected -- binary files do not merge, diffs are meaningless, file grows monotonically.

## Open Questions
- **Shared directory naming**: `.omega/shared/` vs `omega-shared/` vs `.claude/shared/`?
- **Conflict resolution UX**: `conflicts.jsonl` file? `/omega:resolve-conflicts` command? Interactive prompt?
- **Import performance at scale**: Incremental import (track last-import timestamp) as mitigation?
- **Stale knowledge decay in shared store**: Should shared learnings that are never reinforced eventually decay?
- **Curator trigger mechanism**: Hook-based (PostToolUse after sqlite3 writes)? Session close-out? Pre-commit hook?
- **Shared knowledge versioning**: Generation counter for quick "nothing new" detection?
- **Privacy marking**: `private` flag on memory.db tables to prevent curator from sharing?
- **Contributor identity**: git `user.name`? `user.email`? `user_profile.user_name`?

## Constraints
- **Technology**: Pure SQLite (local) + JSONL/JSON files (shared) + bash hooks + markdown agent definitions. No external services.
- **Scale**: Must work for 1 through N developers. Git is the scaling mechanism.
- **Integration**: Must integrate with existing briefing.sh, memory.db schema (additive changes only), setup.sh, and all 15 existing agents.
- **Backward compatibility**: Projects NOT using Cortex must work identically to today.
- **Context budget**: Shared knowledge import must respect the 60% context budget. Import must be selective.

## Risks
- **Git merge conflicts on JSONL**: Mitigated by line-level granularity (one entry per line).
- **Curator accuracy**: Could over-share or under-share. Mitigated by confidence thresholds and manual override.
- **Briefing token budget**: Shared knowledge adds tokens. Mitigated by selective import (high-confidence, scope-relevant only).
- **Trust and quality**: Bad learnings could propagate. Mitigated by confidence scoring, contributor attribution, ability to archive.
- **Schema migration**: Mitigated by `ALTER TABLE ADD COLUMN` with existence checks.
- **#1 Kill Risk**: The curator adds complexity without delivering visible value quickly enough. Mitigation: start with conservative curation.

## User Experience Scenarios

### Scenario 1: Bug Resolution Knowledge Transfer
Developer A resolves INC-042 (race condition in auth). Curator exports full incident to `.omega/shared/incidents/INC-042.json`. Developer A pushes. Developer B pulls next day. During briefing, OMEGA imports the incident. When Developer B hits similar symptoms, the diagnostician says: "This resembles INC-042 -- race condition pattern in auth module. See resolution."

### Scenario 2: Behavioral Learning Propagation
Developer A corrects Claude: "never mock the database in integration tests." Curator evaluates: team-relevant, confidence 0.8, not redundant. Promotes to shared learnings. After git sync, Developer B's test-writer already knows the rule.

### Scenario 3: Hotspot Early Warning
Three developers each log incidents in the payments module within a week. Shared hotspot map flags: "payments module -- 3 incidents in 7 days across 3 developers, systemic instability suspected."

## Files That Will Need Changes

### New Files
| File | Purpose |
|------|---------|
| `core/agents/curator.md` | Knowledge Curator agent definition |
| `core/commands/omega-share.md` | Manual share trigger command |
| `core/commands/omega-team-status.md` | Team knowledge dashboard command |
| `core/protocols/cortex-protocol.md` | Full Cortex protocol reference |

### Modified Files
| File | What Changes |
|------|-------------|
| `core/db/schema.sql` | Add shared knowledge columns and tables |
| `core/hooks/briefing.sh` | Add shared knowledge import step |
| `scripts/setup.sh` | Initialize `.omega/shared/` directory |
| `CLAUDE.md` | Add Cortex protocol pointer |
| `README.md` | Document Cortex feature |
| `docs/architecture.md` | Add Cortex architecture section |
| `docs/agent-inventory.md` | Add curator agent entry |
| `docs/institutional-memory.md` | Document shared knowledge layer |
| `core/agents/diagnostician.md` | Query shared incidents during diagnosis |
| `core/protocols/memory-protocol.md` | Add shared knowledge rules |
