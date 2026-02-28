# C2C Protocol Specifications — Functionality Inventory

> Domain: `c2c-protocol/`
> Generated: 2026-02-28

## Overview

Formal protocol specifications for Claude-to-Claude communication. Defines the rules, formats, and enforcement mechanisms for structured multi-agent conversations.

## Artifacts

| # | Name | File | Description |
|---|------|------|-------------|
| 1 | C2C Protocol v3.0 | `c2c-protocol/protocol-spec-v2.md` | Full protocol specification: definitions, format, confidence modes, source types, rules R01-R12+, meta-rules M1-M6, quorum, partitions, trust scoring, escalation |
| 2 | C2C Enforcement Layer v1 | `c2c-protocol/enforcement-layer-v2.md` | Adversarial auditor boot sequence (Agent C): CONF_CHECK, SRC_CHECK, R04_CHECK, LOGIC_CHECK; blocking rules, trust scoring |
| 3 | Audit Report v3.1 | `c2c-protocol/audits/audit-c2c-proto-v3.1-deployment-model-2026-02-26.md` | Proto-Auditor's D1-D12 audit of the C2C protocol |
| 4 | Patch Report v3.1 | `c2c-protocol/patches/patches-c2c-proto-v3.1-2026-02-26.md` | Proto-Architect's improvement patches for audit findings |

## Dependencies

- Protocol spec is the foundation — referenced by enforcement layer, POC agents, and protocol commands
- Audit reports are produced by the Proto-Auditor agent
- Patch reports are produced by the Proto-Architect agent consuming audit reports
