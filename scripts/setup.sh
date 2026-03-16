#!/bin/bash
# Setup script to initialize the workflow in any project
#
# Usage:
#   bash setup.sh                           # core only
#   bash setup.sh --ext=blockchain          # core + blockchain extension
#   bash setup.sh --ext=blockchain,omega    # core + multiple extensions
#   bash setup.sh --ext=all                 # core + all extensions
#   bash setup.sh --no-db                   # skip SQLite initialization
#   bash setup.sh --list-ext                # list available extensions
#
# Run from the TARGET project directory, or pass the path:
#   bash /path/to/claude-workflow/scripts/setup.sh

set -e

# Detect script directory (the claude-workflow repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Parse arguments
EXTENSIONS=""
SKIP_DB=false
LIST_EXT=false

for arg in "$@"; do
    case $arg in
        --ext=*)
            EXTENSIONS="${arg#*=}"
            ;;
        --no-db)
            SKIP_DB=true
            ;;
        --list-ext)
            LIST_EXT=true
            ;;
        --help|-h)
            echo "Usage: bash setup.sh [--ext=name1,name2] [--no-db] [--list-ext]"
            echo ""
            echo "Options:"
            echo "  --ext=EXT     Install extensions (comma-separated, or 'all')"
            echo "  --no-db       Skip SQLite institutional memory initialization"
            echo "  --list-ext    List available extensions and exit"
            echo "  --help        Show this help"
            exit 0
            ;;
    esac
done

# List extensions
if [ "$LIST_EXT" = true ]; then
    echo "Available extensions:"
    echo ""
    for ext_dir in "$SCRIPT_DIR/extensions"/*/; do
        ext_name=$(basename "$ext_dir")
        agent_count=$(ls "$ext_dir/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
        cmd_count=$(ls "$ext_dir/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
        echo "  $ext_name ($agent_count agents, $cmd_count commands)"
        # List agents
        for agent in "$ext_dir/agents/"*.md; do
            [ -f "$agent" ] && echo "    - $(basename "$agent" .md)"
        done
    done
    exit 0
fi

echo "Setting up Claude Code Quality Workflow..."
echo ""

# Check Claude Code
if ! command -v claude &> /dev/null; then
    echo "  Claude Code not detected in PATH."
    echo "   Install it with: npm install -g @anthropic-ai/claude-code"
    echo "   Continuing file setup..."
    echo ""
fi

# Check git
if ! git rev-parse --is-inside-work-tree &> /dev/null 2>&1; then
    echo "  Initializing git repository..."
    git init
    echo ""
fi

# ============================================================
# CORE AGENTS
# ============================================================
echo "  Copying core agents..."
mkdir -p .claude/agents
for agent in "$SCRIPT_DIR/core/agents/"*.md; do
    name=$(basename "$agent")
    cp "$agent" ".claude/agents/$name"
    echo "   + $name"
done

# ============================================================
# CORE COMMANDS
# ============================================================
echo ""
echo "  Copying core commands..."
mkdir -p .claude/commands
for cmd in "$SCRIPT_DIR/core/commands/"*.md; do
    name=$(basename "$cmd")
    cp "$cmd" ".claude/commands/$name"
    echo "   + ${name%.md}"
done

# ============================================================
# EXTENSIONS
# ============================================================
if [ -n "$EXTENSIONS" ]; then
    echo ""
    echo "  Installing extensions..."

    # Expand "all" to list of all available extensions
    if [ "$EXTENSIONS" = "all" ]; then
        EXTENSIONS=""
        for ext_dir in "$SCRIPT_DIR/extensions"/*/; do
            ext_name=$(basename "$ext_dir")
            if [ -n "$EXTENSIONS" ]; then
                EXTENSIONS="$EXTENSIONS,$ext_name"
            else
                EXTENSIONS="$ext_name"
            fi
        done
    fi

    # Install each extension
    IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS"
    for ext in "${EXT_ARRAY[@]}"; do
        ext=$(echo "$ext" | tr -d ' ')  # trim whitespace
        ext_path="$SCRIPT_DIR/extensions/$ext"

        if [ ! -d "$ext_path" ]; then
            echo "   WARNING: Extension '$ext' not found at $ext_path — skipping"
            continue
        fi

        echo ""
        echo "   Extension: $ext"

        # Copy extension agents
        if [ -d "$ext_path/agents" ]; then
            for agent in "$ext_path/agents/"*.md; do
                [ -f "$agent" ] || continue
                name=$(basename "$agent")
                cp "$agent" ".claude/agents/$name"
                echo "    + agent: $name"
            done
        fi

        # Copy extension commands
        if [ -d "$ext_path/commands" ]; then
            for cmd in "$ext_path/commands/"*.md; do
                [ -f "$cmd" ] || continue
                name=$(basename "$cmd")
                cp "$cmd" ".claude/commands/$name"
                echo "    + command: ${name%.md}"
            done
        fi
    done
fi

# ============================================================
# PROJECT STRUCTURE
# ============================================================
echo ""
echo "  Ensuring project structure..."
if [ ! -d "./specs" ]; then
    mkdir -p specs
    echo "   + specs/ created"
else
    echo "   = specs/ already exists"
fi

if [ ! -d "./docs" ]; then
    mkdir -p docs
    echo "   + docs/ created"
else
    echo "   = docs/ already exists"
fi

mkdir -p docs/.workflow

if [ ! -f "./specs/SPECS.md" ]; then
    cat > ./specs/SPECS.md << 'EOF'
# SPECS.md — Technical Specifications

> Master index of all technical specification documents.

## Specification Files

_(No specs yet. The workflow agents will populate this as you build.)_
EOF
    echo "   + specs/SPECS.md created"
else
    echo "   = specs/SPECS.md already exists"
fi

if [ ! -f "./docs/DOCS.md" ]; then
    cat > ./docs/DOCS.md << 'EOF'
# DOCS.md — Documentation

> Master index of all user-facing and developer documentation.

## Documentation Files

_(No docs yet. The workflow agents will populate this as you build.)_
EOF
    echo "   + docs/DOCS.md created"
else
    echo "   = docs/DOCS.md already exists"
fi

# ============================================================
# INSTITUTIONAL MEMORY (SQLite)
# ============================================================
if [ "$SKIP_DB" = false ]; then
    echo ""
    echo "  Initializing institutional memory..."
    bash "$SCRIPT_DIR/scripts/db-init.sh" "."
fi

# ============================================================
# SUMMARY
# ============================================================
echo ""
echo "======================================================="
echo "  Workflow configured successfully"
echo "======================================================="
echo ""

# Count what was installed
AGENT_COUNT=$(ls .claude/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
CMD_COUNT=$(ls .claude/commands/*.md 2>/dev/null | wc -l | tr -d ' ')

echo "  Installed: $AGENT_COUNT agents, $CMD_COUNT commands"
if [ "$SKIP_DB" = false ]; then
    echo "  Memory DB: .claude/memory.db"
fi
echo ""
echo "  Core commands:"
echo "    /workflow:new \"idea\"                  Start from scratch"
echo "    /workflow:new-feature \"feat\"          Add a feature"
echo "    /workflow:improve \"desc\"              Refactor/optimize"
echo "    /workflow:bugfix \"bug\"                Fix a bug"
echo "    /workflow:audit [--fix]               Audit code"
echo "    /workflow:docs                        Generate specs & docs"
echo "    /workflow:sync                        Sync specs/docs"
echo "    /workflow:functionalities             Map codebase"
echo "    /workflow:understand                  Deep comprehension"
echo "    /workflow:create-role \"desc\"          Design agent role"
echo "    /workflow:audit-role \"path\"           Audit agent role"
echo "    /workflow:wizard-ux \"desc\"            Design wizard UX"
echo "    /workflow:resume                      Resume stopped workflow"

if [ -n "$EXTENSIONS" ]; then
    echo ""
    echo "  Extension commands:"
    IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS"
    for ext in "${EXT_ARRAY[@]}"; do
        ext=$(echo "$ext" | tr -d ' ')
        case $ext in
            blockchain)
                echo "    /workflow:blockchain-network \"desc\"   Node/P2P infrastructure"
                echo "    /workflow:blockchain-debug \"desc\"     Debug connectivity"
                echo "    /workflow:stress-test \"desc\"          Stress test CLI/RPC"
                ;;
            omega)
                echo "    /workflow:omega-setup \"desc\"          Configure OMEGA"
                ;;
            c2c-protocol)
                echo "    /workflow:c2c                         C2C protocol POC"
                echo "    /workflow:proto-audit                 Audit protocol spec"
                echo "    /workflow:proto-improve               Improve protocol"
                ;;
        esac
    done
fi

echo ""
echo "  Source of truth: codebase > specs/ > docs/"
echo ""
echo "  Start with: claude"
echo ""
