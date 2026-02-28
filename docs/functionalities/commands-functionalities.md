# Command Definitions — Functionality Inventory

> Domain: `.claude/commands/` (14 slash command orchestrators)
> Generated: 2026-02-28

## Overview

All command definitions are Markdown files with YAML frontmatter (`name`, `description`) and a body defining the orchestration chain, fail-safe controls, iteration limits, and inter-step output validation.

## Commands

| # | Command | File | Type | Agents Used | Scope Support |
|---|---------|------|------|-------------|---------------|
| 1 | `workflow:new` | `.claude/commands/workflow-new.md` | Full Chain | discovery → analyst → architect → test-writer → developer → QA → reviewer | Yes |
| 2 | `workflow:new-feature` | `.claude/commands/workflow-new-feature.md` | Full Chain | (discovery) → feature-evaluator → analyst → architect → test-writer → developer → QA → reviewer | Yes |
| 3 | `workflow:improve-functionality` | `.claude/commands/workflow-improve-functionality.md` | Reduced Chain | analyst → test-writer → developer → QA → reviewer | Yes |
| 4 | `workflow:bugfix` | `.claude/commands/workflow-bugfix.md` | Reduced Chain | analyst → test-writer → developer → QA → reviewer | Yes |
| 5 | `workflow:audit` | `.claude/commands/workflow-audit.md` | Single Agent | reviewer | Yes |
| 6 | `workflow:docs` | `.claude/commands/workflow-docs.md` | Single Agent | architect | Yes |
| 7 | `workflow:sync` | `.claude/commands/workflow-sync.md` | Single Agent | architect | Yes |
| 8 | `workflow:functionalities` | `.claude/commands/workflow-functionalities.md` | Single Agent | functionality-analyst | Yes |
| 9 | `workflow:understand` | `.claude/commands/workflow-understand.md` | Single Agent | codebase-expert | Yes |
| 10 | `workflow:c2c` | `.claude/commands/workflow-c2c.md` | Multi-Round Loop | c2c-writer ↔ c2c-auditor (max 20 rounds) | No |
| 11 | `workflow:proto-audit` | `.claude/commands/workflow-proto-audit.md` | Single Agent | proto-auditor | Yes (dimensions) |
| 12 | `workflow:proto-improve` | `.claude/commands/workflow-proto-improve.md` | Single Agent | proto-architect | Yes (findings) |
| 13 | `workflow:create-role` | `.claude/commands/workflow-create-role.md` | Three-Phase Chain | role-creator → role-auditor → auto-remediation (max 2 cycles) | No |
| 14 | `workflow:audit-role` | `.claude/commands/workflow-audit-role.md` | Single Agent | role-auditor | Yes (dimensions) |

## Shared Fail-Safe Controls

All multi-step commands share these controls:
- **Iteration Limits**: QA ↔ Developer max 3 iterations; Reviewer ↔ Developer max 2 iterations
- **Inter-Step Output Validation**: Each step verifies the previous step produced expected output files
- **Error Recovery**: Failed chains save state to `docs/.workflow/chain-state.md`
- **Scope Parameter**: All commands accept `--scope` to limit context window usage
