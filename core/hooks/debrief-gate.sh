#!/bin/bash
# ============================================================
# DEBRIEF GATE — PreToolUse hook (matcher: Bash)
# Blocks git commits unless the AI has logged at least one
# outcome (self-score) in THIS SESSION. Uses the briefing
# flag's session_id to scope the check per-session.
# ============================================================

# Read hook input from stdin
INPUT=$(cat)

# Extract the command from the JSON input
COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")

# Only gate git commits — let everything else through immediately
case "$COMMAND" in
    *"git commit"*)
        ;;
    *)
        exit 0
        ;;
esac

# --- This is a git commit. Check if debrief was done THIS SESSION. ---

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DB_PATH="$PROJECT_DIR/.claude/memory.db"
BRIEFING_FLAG="$PROJECT_DIR/.claude/hooks/.briefing_done"

# If no DB, allow the commit (project may not use institutional memory)
if [ ! -f "$DB_PATH" ]; then
    exit 0
fi

# Get current session_id from the hook input
CURRENT_SESSION=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || echo "")

# Get the session_id that was briefed (stored by briefing.sh)
BRIEFED_SESSION=""
if [ -f "$BRIEFING_FLAG" ]; then
    BRIEFED_SESSION=$(cat "$BRIEFING_FLAG" 2>/dev/null || echo "")
fi

# If this session wasn't briefed (briefing hook didn't fire), use time-based fallback
if [ -z "$BRIEFED_SESSION" ] || [ "$CURRENT_SESSION" != "$BRIEFED_SESSION" ]; then
    # No briefing for this session — check if ANY outcomes logged in last 30 minutes
    OUTCOME_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM outcomes WHERE created_at >= datetime('now', '-30 minutes');" 2>/dev/null || echo "0")
else
    # Session was briefed — get briefing timestamp and check outcomes after it
    # The briefing flag stores session_id, so use workflow_runs to find session start
    # Check outcomes logged after the most recent workflow_run started
    LATEST_RUN_START=$(sqlite3 "$DB_PATH" "SELECT started_at FROM workflow_runs ORDER BY id DESC LIMIT 1;" 2>/dev/null || echo "")

    if [ -n "$LATEST_RUN_START" ]; then
        OUTCOME_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM outcomes WHERE created_at >= '$LATEST_RUN_START';" 2>/dev/null || echo "0")
    else
        # No workflow_runs at all — check today
        TODAY=$(date -u +"%Y-%m-%d")
        OUTCOME_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM outcomes WHERE created_at >= '$TODAY';" 2>/dev/null || echo "0")
    fi
fi

if [ "$OUTCOME_COUNT" -gt 0 ]; then
    # Debrief happened this session — allow the commit
    exit 0
fi

# --- BLOCKED ---

# Check if a workflow_run was at least created this session
LATEST_RUN_STATUS=$(sqlite3 "$DB_PATH" "SELECT status FROM workflow_runs ORDER BY id DESC LIMIT 1;" 2>/dev/null || echo "")

if [ "$LATEST_RUN_STATUS" = "running" ]; then
    # workflow_run exists but no outcomes — partial debrief
    echo "COMMIT BLOCKED — SELF-SCORING REQUIRED"
    echo ""
    echo "You registered a workflow_run but logged zero outcomes (self-scores) this session."
    echo "Before committing, score at least your most significant actions:"
    echo ""
    echo "  sqlite3 .claude/memory.db \"INSERT INTO outcomes (run_id, agent, score, domain, action, lesson) VALUES (\\\$RUN_ID, 'developer', 1, 'domain', 'what you did', 'what you learned');\""
    echo ""
    echo "Score: +1 (worked well), 0 (unremarkable), -1 (failed/excessive iteration)"
    echo "Then retry the commit."
    exit 2
fi

# No workflow_run AND no outcomes — full debrief missing
echo "COMMIT BLOCKED — DEBRIEF REQUIRED"
echo ""
echo "You have not logged any debrief for this session. Before committing, you MUST:"
echo ""
echo "  1. Register this session:"
echo "     sqlite3 .claude/memory.db \"INSERT INTO workflow_runs (type, description) VALUES ('manual', 'description');\""
echo "     RUN_ID=\$(sqlite3 .claude/memory.db \"SELECT last_insert_rowid();\")"
echo ""
echo "  2. Self-score your significant actions:"
echo "     sqlite3 .claude/memory.db \"INSERT INTO outcomes (run_id, agent, score, domain, action, lesson) VALUES (\\\$RUN_ID, 'developer', 1, 'domain', 'what you did', 'what you learned');\""
echo ""
echo "  3. Log changes, decisions, and failed approaches"
echo ""
echo "  4. Then retry the commit."
exit 2
