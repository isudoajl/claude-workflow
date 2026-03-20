# Sync Report — 2026-03-20

## Scope
Cortex (collective intelligence layer) — Phases 1-3

## Specs Drift
| Spec File | Status | Issue |
|-----------|--------|-------|
| specs/cortex-requirements.md | OK | 50 requirements, traceability matrix complete |
| specs/cortex-architecture.md | OK | 15 modules, 11 milestones documented |
| specs/SPECS.md | OK | Cortex entries present |

## Docs Drift (Found & Fixed)
| Doc File | Status | Issue | Fix |
|----------|--------|-------|-----|
| README.md | Fixed | Agent count "15" -> 16, command count "17/18" -> 19, hook count "6" -> 7, missing curator agent | Updated all counts, added curator row |
| docs/architecture.md | Fixed | Agent count "15" -> 16, command count "16" -> 19, table count "17" -> 20, view count "10" -> 12 | Updated counts |
| docs/setup-guide.md | Fixed | Agent count "15" -> 16, command count "17" -> 19, protocol count "5" -> 7, DB stats outdated, missing hooks docs, no .omega/shared/ mention | Updated all counts, added learning-detector + learning-gate docs, added shared store row, updated session-close.sh with Cortex |
| docs/institutional-memory.md | Fixed | No Cortex coverage at all — missing shared_imports table, is_private/shared_uuid/contributor columns, v_shared_briefing view | Added full "Cortex: Collective Intelligence Layer" section with schema additions, commands, how-it-works flow |
| docs/DOCS.md | OK | cortex-protocol.md reference present |
| CLAUDE.md | OK | Cortex pointer present |

## Index Drift
| Index | Issue |
|-------|-------|
| SPECS.md | OK — Cortex entries present |
| DOCS.md | OK — cortex-protocol.md referenced |

## Actions Taken
- README.md: 9 edits (agent count, command count, hook count, curator agent row, section headers)
- docs/architecture.md: 2 edits (agent/command/table/view counts)
- docs/setup-guide.md: 4 edits (deployment table counts, hook count text, missing hooks docs, shared store row)
- docs/institutional-memory.md: 1 edit (added entire Cortex section + updated limitations)

## Remaining Issues
- architecture.md references Phase 4 files (omega-cortex-config.md, extensions/cortex-bridge/) that don't exist yet — left as-is since they're clearly labeled as Phase 4 planned components
- setup-guide.md deployment directory tree doesn't show .omega/shared/ — minor, covered in deployment table
