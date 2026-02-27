---
name: workflow:create-role
description: Create a new agent role definition. The role-creator designs comprehensive, battle-tested agent definitions with sharp boundaries, detailed processes, and complete failure handling.
---

# Workflow: Create Role

Invoke ONLY the `role-creator` subagent to design a new agent role definition.
Input: a description of the desired role (can be vague or detailed — the agent adapts).

## Process

The role-creator follows this sequence:

1. **Analyze the request**
   - Read the user's description of the desired role
   - Glob `.claude/agents/*.md` to study existing agent patterns and detect potential overlap
   - Read `.claude/commands/*.md` to understand orchestration patterns
   - Read `CLAUDE.md` for workflow rules and constraints the new agent must respect

2. **Clarify (if needed)**
   - If the role description is vague, ask targeted questions about identity, boundaries, triggers, output, tools, and integration
   - If the description is detailed enough, proceed without unnecessary questions

3. **Research the domain**
   - Use WebSearch to research best practices, methodologies, and pitfalls for the role's domain
   - 2-4 targeted searches, not exhaustive research

4. **Design the role architecture**
   - Walk through the Role Anatomy Checklist (identity, boundaries, prerequisites, directory safety, source of truth, context management, process, output, rules, anti-patterns, failure handling, integration)
   - Perform overlap analysis against existing agents
   - Select minimal tools (least privilege)
   - Select appropriate model

5. **Write the agent definition**
   - Produce the complete `.claude/agents/[name].md` file
   - Follow the standard frontmatter format (name, description, tools, model)

6. **Validate**
   - Completeness check (all anatomy items addressed)
   - Consistency check (doesn't contradict CLAUDE.md or existing agents)
   - Clarity check (unambiguous to another LLM)
   - Boundary check (sharp enough to prevent scope creep)
   - Failure check (handles missing prerequisites, empty input, context exhaustion)

7. **Present and confirm**
   - Show the complete agent definition to the user
   - Explain key design decisions
   - Wait for explicit approval before saving to disk

8. **Save and create companion artifacts**
   - Save the approved agent definition to `.claude/agents/[name].md`
   - If applicable, create a companion command at `.claude/commands/workflow-[name].md`
   - Note any existing commands that should be updated to integrate the new agent

## What the Role Creator Produces
- A complete agent definition file (`.claude/agents/[name].md`)
- Optionally, a companion command file (`.claude/commands/workflow-[name].md`)
- Design rationale for key decisions (tools, model, boundaries)

## Quality Standards
Every role produced must have:
- Clear identity and purpose (first 3 lines tell you what it does)
- Sharp boundaries (what it does NOT do is explicit)
- Prerequisite gate (stops with clear error if upstream input is missing)
- Directory safety (creates directories before writing)
- Source of truth hierarchy (reads code before docs)
- Context management strategy (never reads entire codebase)
- Step-by-step process (phases with numbered steps)
- Output format template (predictable structure)
- Hard rules (non-negotiable constraints)
- Anti-patterns (explicit "don't do this" list)
- Failure handling (missing input, context limits, upstream failures)
