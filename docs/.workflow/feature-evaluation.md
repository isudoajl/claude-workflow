# Feature Evaluation: OMEGA Cortex -- Collective Intelligence Layer

## Feature Description
Transform OMEGA from a solo-developer tool into a collective intelligence system where resolved incidents, behavioral learnings, and hotspot maps automatically propagate across all team members through a hybrid local-SQLite + git-tracked shared knowledge architecture (`.omega/shared/` with JSONL files), mediated by an intelligent Knowledge Curator agent. The system adds a new agent, two new commands, a new protocol file, schema additions, briefing hook modifications, and touches 10+ existing files.

## Evaluation Summary

| Dimension | Score (1-5) | Assessment |
|-----------|-------------|------------|
| D1: Necessity | 4 | Real problem: every developer's memory.db is an isolated island. Teams using OMEGA genuinely lose value from duplicated debugging and learning. |
| D2: Impact | 4 | Multiplier effect: unlocks team-scale institutional memory, OMEGA's core differentiator. Moves the product from "solo power tool" to "team intelligence layer." |
| D3: Complexity Cost | 2 | Cross-cutting: modifies schema, briefing hook, setup script, diagnostician agent, memory protocol, plus 4 new files. The Curator agent introduces a novel intelligence layer with relevance filtering, conflict detection, and reinforcement merging -- all new patterns for OMEGA. |
| D4: Alternatives | 4 | No viable alternative delivers the same value. Manual export scripts, shared markdown files, or third-party tools all lack the curation intelligence and OMEGA-native integration. |
| D5: Alignment | 5 | This IS what OMEGA is about. The architecture doc literally says "persistent institutional memory across sessions." Cortex is the natural multi-developer extension of that core mission. |
| D6: Risk | 3 | Moderate risk. Git merge conflicts on JSONL files, curator accuracy (over-sharing or under-sharing), briefing token budget inflation, and schema migration across deployed projects. Backward compatibility design is solid but the blast radius of briefing.sh changes is high. |
| D7: Timing | 3 | Prerequisites are mostly met (confidence scoring, incident timelines, schema migration patterns exist). However, OMEGA is still maturing its solo-developer memory pipeline -- 8 open questions in the brief suggest significant design uncertainty remains. |

**Feature Viability Score: 3.8 / 5.0**

Calculation: `((4 + 4 + 5) x 2 + (2 + 4 + 3 + 3)) / 10 = (26 + 12) / 10 = 3.8`

## Verdict: CONDITIONAL

This is a high-value feature that aligns perfectly with OMEGA's mission, but the scope is too large and the design uncertainty too high for a single feature implementation. The "MVP" described in the Idea Brief is actually 9 sub-features, several of which introduce novel architectural patterns (curator intelligence, cross-developer reinforcement merging, conflict detection). Building all 9 at once creates a high risk of a bloated, under-tested first version.

## Detailed Analysis

### What Problem Does This Solve?

The problem is real and clearly articulated. When OMEGA is used by a team, each developer's `memory.db` is an isolated brain -- `.claude/memory.db` is gitignored (correctly, since SQLite on shared filesystems is unsafe). Developer A resolves INC-042 after 2 hours of diagnosis; Developer B starts from zero when they hit the same pattern. Behavioral corrections are learned independently by each developer. Hotspot data reflects one person's experience, not the team's collective experience.

This is genuinely the "institutional amnesia" the brief describes. The value scales linearly with team size and non-linearly with incident frequency (the more incidents a team encounters, the more value each shared resolution provides to future encounters).

Evidence that the problem is current: the schema already has `source_project` on `behavioral_learnings` (schema.sql line 216), the incident tracking system has full timeline support (`incident_entries` table with hypothesis/attempt/discovery/resolution types at schema.sql lines 260-272), and confidence scoring is already implemented (schema.sql lines 196, 217). These are clear signals that the architecture was designed with sharing in mind but the sharing mechanism was never built.

### What Already Exists?

**In the codebase:**
- `memory.db` is the sole knowledge store, local-only, gitignored (`core/db/schema.sql`)
- No export, import, sync, or merge capability for memory.db contents exists -- confirmed by grepping for `shared|export|import|sync|team|collective` across the core directory
- `briefing.sh` fires once per session, injecting behavioral learnings and open incidents (`core/hooks/briefing.sh` lines 109-134) -- this is the natural import point
- Confidence scoring on `behavioral_learnings.confidence` and `lessons.confidence` already exists (schema.sql lines 217, 196)
- `CREATE TABLE IF NOT EXISTS` pattern used throughout -- migration path is established
- `source_project` exists on `behavioral_learnings` (schema.sql line 216) but no `contributor` or `shared` flag
- 15 core agents exist today, none of which handle cross-developer knowledge transfer

**External alternatives (via web search):**
- Research exists on collaborative memory architectures for LLM agents with private/shared tiers -- the two-tier approach proposed here matches current academic thinking
- MCP-based approaches exist for agent memory sharing but require server infrastructure, violating OMEGA's zero-infrastructure philosophy
- No existing tool provides OMEGA-native knowledge sharing -- this must be built custom

### Complexity Assessment

**New files (4):** `core/agents/curator.md`, `core/commands/omega-share.md`, `core/commands/omega-team-status.md`, `core/protocols/cortex-protocol.md`

**Modified files (10):** `core/db/schema.sql`, `core/hooks/briefing.sh`, `scripts/setup.sh`, `CLAUDE.md`, `README.md`, `docs/architecture.md`, `docs/agent-inventory.md`, `docs/institutional-memory.md`, `core/agents/diagnostician.md`, `core/protocols/memory-protocol.md`

**Novel patterns introduced:**
1. The Knowledge Curator is a *new category* of agent -- not a pipeline agent, not a utility agent, not a dispatch agent, not a meta agent. It is the first "maintenance agent" that operates on memory.db data itself rather than on source code. This requires establishing new patterns for how agents interact with the knowledge layer.
2. Cross-developer reinforcement merging (same learning from 2+ developers boosts confidence) has no precedent in the codebase. The current confidence system only tracks single-developer reinforcement.
3. Conflict detection (contradictory learnings from different developers) is mentioned but the UX is listed as an open question.

**Ongoing maintenance cost:**
- The shared knowledge store (`.omega/shared/`) becomes a permanent artifact in every team repository
- The curator agent definition will need iteration as teams discover edge cases in relevance filtering
- Schema migration must be maintained across all deployed projects (backward compatibility requires ALTER TABLE ADD COLUMN patterns that get complex over time)
- The briefing hook's token budget grows with shared knowledge -- this requires ongoing tuning
- Two new commands (`omega:share`, `omega:team-status`) and one new protocol file add to the surface area

**Estimated effort:** Large. 9 sub-components, 14 files affected, novel architectural patterns. This is not a "feature" -- it is an architectural layer.

### Risk Assessment

1. **Briefing token inflation** (medium risk): The briefing hook currently injects behavioral learnings and open incidents. Adding shared incidents, shared behavioral learnings, and shared hotspots could easily exceed the 60% context budget. The brief mentions "selective import" as mitigation, but the selection algorithm is an open question.

2. **Curator accuracy** (medium risk): The curator must distinguish "team-relevant" from "personal" knowledge. This is a judgment call that depends heavily on the quality of the agent definition. Over-sharing creates noise; under-sharing defeats the purpose. There is no ground truth to validate against.

3. **Schema migration blast radius** (low risk): Adding columns with `ALTER TABLE ADD COLUMN` and a new `shared_imports` table is safe with existence checks. The existing pattern handles this well.

4. **Git merge conflicts** (low risk): JSONL is append-only and line-level, so conflicts should be rare and easily resolvable. This was a good design choice.

5. **8 unresolved design questions** (medium risk): The Idea Brief lists 8 open questions including directory naming, conflict resolution UX, import performance, stale knowledge decay, curator trigger mechanism, versioning, privacy marking, and contributor identity. These are not minor details -- several affect the core architecture.

## Conditions

For CONDITIONAL verdict: the following conditions must be met before proceeding:

- [ ] **Reduce scope to 3 phases**: Phase 1 = Schema additions + shared knowledge store structure + setup.sh initialization (pure plumbing, zero behavioral change). Phase 2 = Curator agent + `/omega:share` command (the novel intelligence layer). Phase 3 = Briefing import + diagnostician enhancement + `/omega:team-status` (where end-user value is delivered). Each phase is independently deployable and testable.
- [ ] **Resolve the 4 blocking open questions before Phase 2**: (1) Shared directory naming (`.omega/shared/` vs alternatives), (2) Curator trigger mechanism (hook-based vs session close-out vs pre-commit), (3) Contributor identity source (`git user.name` vs `user.email` vs `user_profile.user_name`), (4) Privacy marking mechanism (whether a `private` flag on memory.db tables is needed to prevent curator from sharing certain entries).
- [ ] **Define the briefing token budget cap**: Before Phase 3, specify the maximum number of shared items injected at session start (e.g., top 5 shared behavioral learnings, top 3 shared incidents by relevance). Without a hard cap, the briefing will grow unbounded and violate the 60% context budget.
- [ ] **Accept that the Curator will start conservative**: First version should promote only entries with confidence >= 0.8 (not 0.7 as proposed in the brief). It is better to under-share than over-share in v1. Loosening the threshold later is easy; tightening after bad knowledge has propagated is hard.

## Alternatives Considered

- **Manual export/import scripts (no curator)**: A simple `omega:export-learnings` and `omega:import-learnings` pair that dumps high-confidence behavioral learnings to a shared file and imports from it. Pros: 10x simpler, no new agent, no intelligence layer. Cons: no relevance filtering, no deduplication, no reinforcement merging. Delivers ~40% of the value at ~15% of the cost. This could be a useful stepping stone before the full Cortex.
- **Shared markdown files with manual curation**: Developers write shared learnings to a team wiki or markdown file. Pros: zero infrastructure. Cons: no automation, no confidence scoring, no integration with briefing. Delivers ~10% of the value.
- **External knowledge base (Notion, Confluence, etc.)**: Pros: existing tools with search and collaboration. Cons: not OMEGA-native, not injected at briefing, breaks zero-infrastructure philosophy. Not viable for this use case.
- **Do nothing**: Teams continue with isolated memory.db instances. Cost of inaction: every developer independently rediscovers lessons, incidents, and hotspots. For a team of 4, this roughly 4x the debugging time for repeated patterns. Significant but not blocking -- OMEGA works fine for solo developers today.

## Recommendation

**Proceed, but restructure the scope.** The feature is well-conceived, well-aligned, and addresses a genuine gap in OMEGA's architecture. The hybrid local-SQLite + git-tracked-JSONL architecture is the right approach (validated by academic research and constrained by OMEGA's zero-infrastructure philosophy). However, the "MVP" as described is too large for a single implementation pass.

Decompose into 3 independently deployable phases, each going through the full OMEGA pipeline:

1. **Phase 1 (Foundation)**: Schema additions, `.omega/shared/` directory structure, setup.sh changes. Pure plumbing with zero behavioral change. Ship it, verify backward compatibility across all deployed target projects.

2. **Phase 2 (Curation)**: Curator agent + `/omega:share` command. This is the novel intelligence layer. Ship it, iterate on curation quality with real team usage before building the import/consumption side.

3. **Phase 3 (Consumption)**: Briefing import, diagnostician enhancement, `/omega:team-status`. This is where the value is delivered to end users. Ship it only after Phase 2 has been validated with real usage data.

Do not attempt all 9 sub-features in one pass through the pipeline.

## User Decision
**USER OVERRIDE: PROCEED**

The user overrides the CONDITIONAL verdict. Rationale (in their words):
> "It's a problem I'm facing right now. I'm working with my cousin on the same project. He doesn't have Omega; I created it, but if I tell him to install Omega, I'll lose all the interaction, learning, project corrections, and super valuable information! And it costs money."

**Immediate pain point**: User has accumulated hundreds of learnings, incident resolutions, behavioral corrections in their memory.db. If their cousin runs `setup.sh`, they start from ZERO. Every re-learned lesson = wasted API tokens. Every re-debugged bug = hours lost.

**User mandate**: Make this 5/5. "Omega is going to revolutionize the world of agents, now in a collaborative way."

**Accepted conditions**:
- [x] Phased approach (3 phases, independently deployable)
- [x] Resolve blocking open questions during architecture
- [x] Define briefing token budget cap
- [x] Curator starts conservative (confidence >= 0.8)

**Proceeding to Analyst (Step 1).**
