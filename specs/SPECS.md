# SPECS.md -- Technical Specifications

> Master index of technical specifications for OMEGA.

## Architecture

- [OMEGA CLI Architecture](omega-cli-architecture.md) -- Rust binary rewrite of the toolkit: crate layout, asset embedding, CLI design, cross-platform builds, install script, SQLite strategy, version management, extension discovery, milestones

## Features

- [OMEGA Persona Requirements](persona-requirements.md) -- Reduced-scope identity layer: user_profile table, onboarding_state table, workflow_usage view, briefing.sh identity block, experience auto-upgrade, OMEGA Identity protocol in CLAUDE.md, /omega:onboard command
- [OMEGA Persona Architecture](persona-architecture.md) -- Module breakdown, schema SQL, briefing hook design, CLAUDE.md identity protocol, onboarding command structure, failure modes, milestone plan
- [OMEGA Cortex Requirements](cortex-requirements.md) -- Collective intelligence layer: hybrid local-SQLite + git-tracked shared knowledge, Knowledge Curator agent, sync adapters (git/cloud/self-hosted), 4 phases (Foundation, Curation, Consumption, Sync Adapters), 50 requirements
- [OMEGA Cortex Architecture](cortex-architecture.md) -- Cortex module breakdown (15 modules across 11 milestones): schema + migration, setup + shared store, cortex protocol, curator agent, share command, session-close trigger, briefing import, diagnostician enhancement, team status, documentation, sync adapter abstraction, config command, middleware pipeline, D1 adapter, self-hosted bridge. JSONL format specification, failure modes, security model, performance budgets
