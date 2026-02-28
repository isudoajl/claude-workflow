# POC C2C Protocol — Functionality Inventory

> Domain: `poc/c2c-protocol/`
> Generated: 2026-02-28

## Overview

Proof-of-concept implementation of multi-round C2C agent communication. Two agents (writer + auditor) iterate under the C2C protocol until certification or max rounds.

## Artifacts

| # | Name | File | Description |
|---|------|------|-------------|
| 1 | C2C Writer Prompt | `poc/c2c-protocol/c2c-writer.md` | Agent A: code writer + doc author operating under C2C protocol with conf/src tags |
| 2 | C2C Auditor Prompt | `poc/c2c-protocol/c2c-auditor.md` | Agent B: code auditor + fact-checker, issues certification when production-ready |
| 3 | Protocol Condensed | `poc/c2c-protocol/PROTOCOL-CONDENSED.md` | Embedded C2C v2.1 protocol spec for agent prompts: format, tags, handshake, multi-round message types |
| 4 | Results | `poc/c2c-protocol/RESULTS.md` | Multi-round POC results: 2 rounds, 4 invocations, certification accepted, 13 findings tracked |

### v1 Single-Round POC

| # | Name | File | Description |
|---|------|------|-------------|
| 5 | Rate Limiter | `poc/c2c-protocol/v1-single-round/rate_limiter.py` | Token bucket rate limiter: per-client tracking, configurable rate/burst, thread-safe |
| 6 | Agent A Output | `poc/c2c-protocol/v1-single-round/agent-a-output.md` | Writer's round 1 output from single-round POC |
| 7 | Agent B Output | `poc/c2c-protocol/v1-single-round/agent-b-output.md` | Auditor's round 1 output from single-round POC |

### Multi-Round Transcripts

| # | Name | File | Description |
|---|------|------|-------------|
| 8 | Round 1 Writer | `poc/c2c-protocol/rounds/round-1-writer.md` | Writer's round 1 output |
| 9 | Round 1 Auditor | `poc/c2c-protocol/rounds/round-1-auditor.md` | Auditor's round 1 audit findings |
| 10 | Round 2 Writer | `poc/c2c-protocol/rounds/round-2-writer.md` | Writer's fixes/defenses/concessions |
| 11 | Round 2 Auditor | `poc/c2c-protocol/rounds/round-2-auditor.md` | Auditor's certification decision |
