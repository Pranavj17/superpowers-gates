# Superpowers Gates Skill Design

**Date:** 2026-07-02  
**Project:** superpowers-gates  
**Scope:** Claude Code skill packaging for hook gates framework  
**Status:** Design approved, ready for implementation

---

## Overview

**Problem:** Hook gates framework is powerful but requires manual installation (`git clone` → copy files). New users have high friction discovering and setting it up.

**Solution:** Package as a Claude Code skill for **discoverability** (plugin registry) and **frictionless onboarding** (one-click install + optional auto-setup), while keeping the framework as the standalone source of truth.

**Architecture:** Unified monorepo with framework at core, skill as thin MCP wrapper.

---

## Goals

1. ✅ **Discoverability** — Users find hook gates in Claude Code without knowing it exists
2. ✅ **Frictionless setup** — First-time users install + configure with minimal friction
3. ✅ **Active tools** — Skill provides `/create-gate` prompt and `validate-gates` tool for ongoing use
4. ✅ **Single source** — Framework code lives once; skill orchestrates it, not duplicates it
5. ✅ **Dual distribution** — Works as both standalone framework (GitHub) and skill (plugin registry)

---

## Architecture

### Repository Structure

```
superpowers-gates/
├── framework/                    # Core implementation (unchanged)
│   ├── lib/gates/
│   │   ├── runner.sh            # Gate executor (93 lines)
│   │   ├── validate.sh          # YAML validator (162 lines)
│   │   ├── helpers.sh           # Helper functions (75 lines)
│   │   └── schema.json          # JSON Schema (166 lines)
│   ├── lib/examples/            # 3 example gates
│   ├── lib/tests/               # 4 test suites (24 tests)
│   ├── docs/                    # User guides
│   ├── README.md                # Framework overview
│   └── VERSION                  # Version file (e.g., "1.0.0")
├── skill/                       # Claude Code skill (NEW)
│   ├── plugin.json              # Skill manifest
│   ├── mcp_server.py            # MCP server (tools + prompts)
│   ├── init.sh                  # First-install setup script
│   └── README.md                # Skill setup guide
├── .github/
│   └── workflows/ci.yml         # Tests for both framework + skill
├── ARCHITECTURE.md              # Design decisions
├── README.md                    # Unified entry point (choose your path)
└── VERSION                      # Project version (synced across framework + skill)
```

### Version Strategy

- Single `VERSION` file at repo root (e.g., `1.0.0`)
- Framework uses: `framework/VERSION` (or symlink to root)
- Skill uses: `skill/plugin.json` version field
- Keep both in sync on releases
- CI enforces: `framework/VERSION == skill/plugin.json version`

---

## Installation Flows

### Flow A: Plugin Registry (New Users)

```
1. User searches "superpowers gates" in Claude Code plugins
2. Finds "Superpowers Gates" with description + reviews
3. Clicks "Install"
4. Skill downloads framework: git clone https://github.com/pranav/superpowers-gates ~/.claude/gates-framework
5. Init prompt appears:
   ┌──────────────────────────────────────────┐
   │ Hook Gates Framework installed!          │
   │                                          │
   │ Set up now? (Recommended)                │
   │ ❯ Yes (auto-register hook)              │
   │   No (manual setup)                      │
   │   Manual (show commands)                 │
   └──────────────────────────────────────────┘
6a. YES → Auto-update .claude/settings.json with PreToolUse hook
6b. NO → Show GETTING_STARTED.md
6c. MANUAL → Display bash commands user can copy/paste
7. Validate installation: bash ~/.claude/gates-framework/framework/lib/gates/validate.sh
8. Welcome message: "Ready to create gates! Try /create-gate or /list-gates"
```

**Idempotency:** If skill reinstalled, skip steps 4-7 (framework already present).

### Flow B: Direct Framework (Developers)

```
1. User: git clone https://github.com/pranav/superpowers-gates
2. Read framework/README.md
3. Copy examples: cp framework/lib/examples/* ~/.claude/gates/
4. Configure manually (edit .claude/settings.json)
5. Run tests: bash framework/lib/tests/*.test.sh
6. No skill needed; pure framework
```

### Flow C: Skill + Custom Gates

```
1. Install skill (Flow A)
2. Use /create-gate prompt to build new gates interactively
3. Gates saved to ~/.claude/gates/
4. Framework's runner.sh evaluates them automatically
```

---

## Skill Components

### MCP Server (`skill/mcp_server.py`)

Implements Claude Code MCP interface with:

**Tools:**

1. **`validate-gates`**
   - Input: (none; auto-scans `~/.claude/gates/*.yaml`)
   - Output: JSON
     ```json
     {
       "valid_gates": ["no-destructive-db", "audit-log"],
       "invalid_gates": [{"file": "bad-gate.yaml", "error": "missing required field: decision"}],
       "summary": "2/3 gates valid"
     }
     ```

2. **`validate-gate`**
   - Input: `gate_content` (YAML string or filename)
   - Output: Validation report (pass/fail + details)
   - Used by `/create-gate` prompt for live validation

**Prompts:**

1. **`/create-gate`**
   - Interactive wizard for creating new gates
   - Steps: name → description → hook → matcher → condition → decision → message
   - Live validation after each field
   - Saves to `~/.claude/gates/{name}.yaml`
   - Shows: "✅ Gate saved! Test it with: validate-gates"

2. **`/list-gates`**
   - Display installed gates
   - Format: name | description | hook | decision | status
   - Searchable by: name, tag, hook type
   - Show count: "5 gates installed (3 examples, 2 custom)"

### Init Script (`skill/init.sh`)

Runs once on first install:

```bash
#!/bin/bash
set -euo pipefail

GATES_FRAMEWORK="$HOME/.claude/gates-framework"

# Step 1: Clone framework if not present
if [ ! -d "$GATES_FRAMEWORK" ]; then
  git clone https://github.com/pranav/superpowers-gates "$GATES_FRAMEWORK"
fi

# Step 2: Create gates directory
mkdir -p "$HOME/.claude/gates"

# Step 3: Copy examples
cp "$GATES_FRAMEWORK/framework/lib/examples"/*.yaml "$HOME/.claude/gates/"

# Step 4: Ask user about setup
read -p "Register hook in .claude/settings.json? (y/n/manual) " setup_choice
case "$setup_choice" in
  y|Y) 
    # Auto-update settings.json
    python3 "$GATES_FRAMEWORK/skill/update_settings.py" --auto
    echo "✅ Hook registered!"
    ;;
  n|N)
    echo "ℹ️ See: $GATES_FRAMEWORK/framework/docs/GETTING_STARTED.md"
    ;;
  m|M)
    echo "Run: bash $GATES_FRAMEWORK/framework/lib/gates/runner.sh PreToolUse"
    ;;
esac

# Step 5: Validate
bash "$GATES_FRAMEWORK/framework/lib/gates/validate.sh"
echo "✅ Installation complete!"
```

### Plugin Manifest (`skill/plugin.json`)

```json
{
  "name": "superpowers-gates",
  "displayName": "Superpowers Gates",
  "version": "1.0.0",
  "description": "YAML-based permission and safety gates for Claude Code hooks. Create, validate, and manage gates without JSON escaping.",
  "author": "pranav",
  "homepage": "https://github.com/pranav/superpowers-gates",
  "repository": "https://github.com/pranav/superpowers-gates",
  "license": "MIT",
  "mcpServer": {
    "command": "python3",
    "args": ["{pluginDir}/mcp_server.py"]
  },
  "tools": [
    {
      "name": "validate-gates",
      "description": "Validate all installed gates in ~/.claude/gates/",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "validate-gate",
      "description": "Validate a single gate YAML file",
      "inputSchema": {
        "type": "object",
        "properties": {
          "gate_content": {
            "type": "string",
            "description": "YAML content or filename to validate"
          }
        },
        "required": ["gate_content"]
      }
    }
  ],
  "prompts": [
    {
      "name": "create-gate",
      "description": "Interactive wizard to create a new permission gate"
    },
    {
      "name": "list-gates",
      "description": "Discover and list installed gates"
    }
  ],
  "keywords": ["hooks", "gates", "permissions", "safety", "claude-code"],
  "category": "Utilities"
}
```

---

## Distribution

### Framework Distribution

- **Repository:** `https://github.com/pranav/superpowers-gates`
- **Installation:** `git clone` or download ZIP
- **Updates:** User runs `git pull` in `~/.claude/gates-framework/`
- **Releases:** GitHub releases with tags (v1.0.0, v1.1.0, etc.)
- **Audience:** Developers, teams, advanced users

### Skill Distribution

- **Registry:** Claude Code plugin registry
- **Installation:** One-click from Claude Code UI
- **Updates:** Claude Code handles automatically
- **Audience:** End users, anyone discovering via plugin search

### Version Sync

- Root `VERSION` file: `1.0.0`
- Framework reads from: `framework/VERSION`
- Skill declares in: `skill/plugin.json` version field
- CI check: Both must match on every commit
- Release process: Bump root VERSION, both pick it up automatically

---

## User Workflows

### Workflow: Discoverability → Setup → Use

```
┌─────────────────────────────────────────┐
│ 1. Discover (Claude Code plugin search) │
│    "superpowers gates"                  │
│    ↓                                    │
│ 2. Install (one-click)                  │
│    ↓                                    │
│ 3. Setup (auto or manual)               │
│    ↓                                    │
│ 4. Use (tools + prompts)                │
│    /create-gate                         │
│    validate-gates                       │
│    /list-gates                          │
│    ↓                                    │
│ 5. Framework (in background)            │
│    runner.sh evaluates gates on hooks   │
└─────────────────────────────────────────┘
```

### Workflow: Developer (No Skill)

```
┌─────────────────────────────────────────┐
│ 1. Clone: git clone ...superpowers-gates│
│    ↓                                    │
│ 2. Read: framework/README.md            │
│    ↓                                    │
│ 3. Install: Copy examples, configure    │
│    ↓                                    │
│ 4. Customize: Write custom gates        │
│    ↓                                    │
│ 5. Test: Run framework test suites      │
│    ↓                                    │
│ 6. Deploy: Add to project git           │
└─────────────────────────────────────────┘
```

---

## Implementation Strategy

### Phase 1: Scaffold Skill Structure
- Create `skill/` directory structure
- Write `plugin.json` manifest
- Stub `mcp_server.py` with tool/prompt definitions

### Phase 2: Implement MCP Server
- `validate-gates` tool (scan + validate)
- `validate-gate` tool (single gate validation)
- `/create-gate` prompt (interactive wizard)
- `/list-gates` prompt (discovery)

### Phase 3: Implement Init Script
- `skill/init.sh` (framework download, config)
- `skill/update_settings.py` (auto-register hook)
- Error handling + idempotency

### Phase 4: CI + Testing
- Add `.github/workflows/ci.yml` to test both framework + skill
- Version sync check
- Framework tests (existing 24 tests)
- Skill tests (MCP tool integration tests)

### Phase 5: Documentation
- `skill/README.md` (skill-specific setup)
- Update root `README.md` (choose your path: skill vs framework)
- Add `ARCHITECTURE.md` (this design)

### Phase 6: Distribution
- Publish skill to Claude Code plugin registry
- Create GitHub release (v1.0.0)
- Rename repo to `superpowers-gates`

---

## Testing Strategy

### Framework Tests (Existing)
- helpers.test.sh (6 tests)
- gate-runner.test.sh (9 tests)
- validate.test.sh (5 tests)
- integration.test.sh (4 tests)
- **Total: 24 tests** ✅ (no changes needed)

### Skill Tests (New)
- MCP tool invocation tests
- Init script validation (idempotency, error handling)
- Settings.json update tests
- Integration: skill install + gate creation end-to-end

### CI Workflow
```yaml
# .github/workflows/ci.yml
on: push
jobs:
  framework-tests:
    - Run: lib/tests/*.test.sh
  skill-tests:
    - Run: skill/tests/*.test.py
  version-sync:
    - Check: framework/VERSION == skill/plugin.json
  build:
    - Build skill MCP server
```

---

## Success Criteria

✅ **Discoverability** — Skill appears in Claude Code plugin registry  
✅ **Install friction** — User can install + configure in <2 minutes  
✅ **Dual distribution** — Works as both skill (registry) and framework (GitHub)  
✅ **Single source** — Framework code exists once; skill wraps it  
✅ **Tools ready** — `/create-gate`, `validate-gates`, `/list-gates` all functional  
✅ **Tests pass** — All 24 framework tests + new skill tests green  
✅ **Documentation** — Clear path: "Choose skill for one-click, or clone for full control"  

---

## Deferred (Out of Scope)

- Skill marketplace ratings/reviews (Claude Code handles)
- Auto-update for gates (users manage in `~/.claude/gates/`)
- Cloud sync of gates (user responsibility)
- IDE integrations beyond Claude Code (future skill variants)

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Unified monorepo** | Single source of truth; easier version management |
| **Skill wraps framework** | Framework is the core; skill adds distribution/UX layer |
| **Optional auto-setup** | Reduces friction but respects advanced users' preferences |
| **Interactive prompts** | Lowers barrier for gate creation vs reading docs |
| **Tool + Prompt combo** | Tools for validation, prompts for interaction |

---

## References

- **Framework Design:** `docs/superpowers/specs/2026-07-02-hook-gates-framework-design.md`
- **Framework Plan:** `docs/superpowers/plans/2026-07-02-hook-gates-framework-plan.md`
- **Claude Code MCP:** https://claude.ai/code — MCP specification
