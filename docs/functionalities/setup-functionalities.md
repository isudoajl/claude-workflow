# Setup Script — Functionality Inventory

> Domain: `scripts/setup.sh`
> Generated: 2026-02-28

## Overview

Deployment tool that copies OMEGA's agents and commands into a target project. Creates scaffolding for `specs/` and `docs/` if missing.

## Functionalities

| # | Functionality | Location | Description |
|---|---------------|----------|-------------|
| 1 | Claude Code detection | `scripts/setup.sh`:10-15 | Checks if `claude` CLI is in PATH; warns if missing but continues |
| 2 | Git initialization | `scripts/setup.sh`:18-22 | Initializes git repo if not already inside one |
| 3 | Script directory detection | `scripts/setup.sh`:25 | Resolves the toolkit's root directory from script location |
| 4 | Agent copying | `scripts/setup.sh`:28-44 | Creates `.claude/agents/` and copies all `*.md` agent files. Always overwrites |
| 5 | Command copying | `scripts/setup.sh`:47-64 | Creates `.claude/commands/` and copies all `*.md` command files. Always overwrites |
| 6 | specs/ scaffolding | `scripts/setup.sh`:67-90 | Creates `specs/` directory and `specs/SPECS.md` master index if they do not exist. Never overwrites |
| 7 | docs/ scaffolding | `scripts/setup.sh`:92-105 | Creates `docs/` directory and `docs/DOCS.md` master index if they do not exist. Never overwrites |
| 8 | Usage summary output | `scripts/setup.sh`:107-133 | Prints available workflow commands and source of truth hierarchy |

## Key Behaviors

- **Always overwrites**: agents and commands (kept in sync with toolkit)
- **Never overwrites**: `specs/SPECS.md`, `docs/DOCS.md` (project-specific content preserved)
- **Never copies**: `CLAUDE.md` (each project maintains its own)
