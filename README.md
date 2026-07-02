# Hook Gates Framework

A **YAML-based declarative permission & safety gates system** for Claude Code hooks that replaces complex inline bash/jq with readable, testable YAML files.

## Problem

Claude Code hooks are powerful but verbose. Complex permission rules require nested JSON escaping and embedded bash/jq, making them:
- ❌ Hard to read (500+ characters for simple rules)
- ❌ Impossible to test independently
- ❌ Not reusable across projects
- ❌ Difficult to audit

Example: Preventing destructive database commands required this in `.claude/settings.json`:
```json
"command": "COMMAND=$(jq -r '.tool_input.command'); if echo \"$COMMAND\" | grep -qE '\\bmix +ecto\\.(create|drop|reset)\\b'; then echo '{...}'; fi"
```

## Solution

**Hook Gates:** Declare permission rules as simple YAML files.

```yaml
name: "no-destructive-db"
description: "Prevent mix ecto.create/drop/reset without explicit approval"
hook: "PreToolUse"
matcher: "Bash"
condition: |
  jq -r '.tool_input.command' | grep -qE '\bmix +ecto\.(create|drop|reset)\b'
decision: "ask"
message: "Rule 2: Destructive DB command requires explicit confirmation"
tags: ["security", "database"]
severity: "high"
```

Same logic, **10× more readable**, and **independently testable**.

## Features

✅ **Declarative YAML gates** — Define permission rules without inline JSON escaping  
✅ **First-match-wins evaluation** — Gates load alphabetically, first trigger returns decision  
✅ **Fail-open by default** — No matching gate = allow (safe default)  
✅ **Comprehensive validation** — `validate.sh` checks YAML syntax, required fields, valid enums  
✅ **Reusable helpers** — Bash/jq functions for common patterns (destructive commands, file paths)  
✅ **Full test suite** — 30+ unit tests across helpers, runner, validator, and integration  
✅ **Production examples** — Rule 2, Rule 4, and audit logging gates ready to use  
✅ **Documentation** — GETTING_STARTED, SCHEMA_REFERENCE, EXAMPLES, CONTRIBUTING guides  

## Architecture

```
Hook Event (e.g., PreToolUse)
    ↓
Runner loads gates from ~/.claude/gates/*.yaml
    ↓
For each gate (alphabetically):
  - Check hook matches
  - Check tool matcher (regex)
  - Evaluate condition (bash code)
    ↓
First match → Return decision (ask/deny/allow)
No match → Allow (fail-open)
```

## Choose Your Path

**New users?** Install as a Claude Code plugin (this repo is its own marketplace):
```
/plugin marketplace add Pranavj17/superpowers-gates
/plugin install superpowers-gates@superpowers-gates
```
The plugin ships `hooks/hooks.json`, so the gate runner registers itself for
PreToolUse and PostToolUse automatically — **no settings.json edits needed**.
Just add gate files to `~/.claude/gates/` (copy the examples to start):
```bash
mkdir -p ~/.claude/gates
cp "$(ls -d ~/.claude/plugins/cache/superpowers-gates/superpowers-gates/*/ | tail -1)framework/lib/examples/"*.yaml ~/.claude/gates/
```
If you previously registered the runner manually in settings.json, remove that
entry after upgrading — otherwise every gate fires twice.

**Developers?** Clone the framework:
```bash
git clone https://github.com/Pranavj17/superpowers-gates
cd superpowers-gates
cp framework/lib/examples/* ~/.claude/gates/
# Configure manually in .claude/settings.json (see Quick Start step 3)
```

Both paths use the same framework core — just different distribution methods.

---

## Quick Start

### 1. Install Framework

```bash
# Clone framework to local installation
git clone https://github.com/Pranavj17/superpowers-gates ~/.claude/gates-framework

# Create gates directory
mkdir -p ~/.claude/gates

# Copy example gates
cp -r ~/.claude/gates-framework/framework/lib/examples/* ~/.claude/gates/

# Validate gates
bash ~/.claude/gates-framework/framework/lib/gates/validate.sh
```

### 2. Copy Example Gates

Three production-ready gates are included:

| Gate | Purpose | Hook | Decision |
|------|---------|------|----------|
| `no-destructive-db.yaml` | Prevent `mix ecto.{create,drop,reset}` | PreToolUse | ask |
| `no-docs-violation.yaml` | Enforce `.md` files in `/docs` | PreToolUse | deny |
| `audit-log.yaml` | Log all tool executions | PostToolUse | allow |

### 3. Register in Claude Code

**Plugin installs skip this step** — `hooks/hooks.json` registers the runner
automatically. For manual/clone installs, add to `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [{
      "hooks": [{
        "type": "command",
        "command": "bash ~/.claude/gates-framework/framework/lib/gates/runner.sh PreToolUse",
        "statusMessage": "Checking gates..."
      }]
    }]
  }
}
```

### 4. Create Custom Gates

Add new gate files to `~/.claude/gates/` (alphabetically sorted):

```bash
cat > ~/.claude/gates/no-npm-install.yaml << 'EOF'
name: "no-npm-install"
description: "Use npm ci instead of npm install when package-lock.json exists"
hook: "PreToolUse"
matcher: "Bash"
condition: |
  cmd=$(jq -r '.tool_input.command')
  [ "$cmd" = "npm install" ] && [ -f package-lock.json ]
decision: "ask"
message: "Found package-lock.json. Use npm ci instead of npm install."
tags: ["npm", "best-practice"]
severity: "low"
EOF

# Validate it
bash ~/.claude/gates-framework/framework/lib/gates/validate.sh ~/.claude/gates/no-npm-install.yaml
```

## Project Structure

```
claude-x/
├── framework/
│   ├── VERSION
│   └── lib/
│       ├── gates/
│       │   ├── runner.sh              # Gate executor (hook interface)
│       │   ├── validate.sh            # YAML validator
│       │   ├── helpers.sh             # Reusable bash/jq functions
│       │   └── schema.json            # JSON Schema for validation
│       ├── examples/
│       │   ├── no-destructive-db.yaml # Rule 2: DB safety
│       │   ├── no-docs-violation.yaml # Rule 4: Docs location
│       │   └── audit-log.yaml         # PostToolUse audit example
│       └── tests/
│           ├── helpers.test.sh        # Helper function tests (6 tests)
│           ├── gate-runner.test.sh    # Runner tests (9 tests)
│           ├── validate.test.sh       # Validator tests (5 tests)
│           ├── integration.test.sh    # End-to-end tests (4 tests)
│           └── fixtures/              # Mock inputs for testing
├── skill/
│   ├── mcp_server.py               # Python MCP server
│   ├── init.sh                     # Setup script
│   ├── update_settings.py          # Hook auto-registration
│   └── tests/                      # Skill tests
├── docs/
│   ├── superpowers/
│   │   ├── specs/2026-07-02-hook-gates-framework-design.md
│   │   └── plans/2026-07-02-hook-gates-framework-plan.md
│   ├── GETTING_STARTED.md         # Installation & usage
│   ├── SCHEMA_REFERENCE.md        # Complete field documentation
│   ├── EXAMPLES.md                # Real-world gate examples
│   └── CONTRIBUTING.md            # Contributing guidelines
├── .claude/
│   ├── settings.json              # Project configuration
│   └── hooks/                     # Hook scripts
├── CLAUDE.md                       # Project guidance for Claude Code
└── README.md                       # This file
```

## Test Results

All test suites passing:

```
helpers.test.sh:       6/6 passed ✅
gate-runner.test.sh:   9/9 passed ✅
validate.test.sh:      5/5 passed ✅
integration.test.sh:   4/4 passed ✅
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total:                24/24 passed ✅
```

**Run all tests:**
```bash
bash framework/lib/tests/helpers.test.sh
bash framework/lib/tests/gate-runner.test.sh
bash framework/lib/tests/validate.test.sh
bash framework/lib/tests/integration.test.sh
```

## Documentation

- **[GETTING_STARTED.md](docs/GETTING_STARTED.md)** — Installation, configuration, and quick examples
- **[SCHEMA_REFERENCE.md](docs/SCHEMA_REFERENCE.md)** — Complete gate YAML field reference
- **[EXAMPLES.md](docs/EXAMPLES.md)** — Real-world gate patterns and use cases
- **[CONTRIBUTING.md](docs/CONTRIBUTING.md)** — Contribution guidelines and design patterns

## Technical Details

### Gate YAML Schema

**Required fields:** `name`, `description`, `hook`, `matcher`, `condition`, `decision`, `message`

**Optional fields:** `tags`, `severity`, `version`, `author`

```yaml
name: "unique-identifier"                 # kebab-case
description: "Human-readable description"
hook: "PreToolUse|PostToolUse|..."        # When to evaluate
matcher: "Bash|Write|Edit|*"              # Which tools to match
condition: |                              # Bash code, exit 0 to trigger
  jq -r '.tool_input...' | grep -q "..."
decision: "ask|deny|allow|transform"      # Permission decision
message: "User-facing reason"             # Why gate triggered
tags: ["category", "tags"]                # Search metadata (optional)
severity: "low|medium|high|critical"      # Risk level (optional)
```

### Evaluation Logic

1. **Load gates** — Read all `*.yaml` files from `~/.claude/gates/` in alphabetical order
2. **Filter by hook** — Only evaluate gates matching the event hook (PreToolUse, PostToolUse, etc.)
3. **Filter by tool** — Check if gate's matcher regex matches the tool name
4. **Evaluate condition** — Run bash code with JSON input via stdin
5. **Return decision** — First match wins; output JSON decision to Claude Code
6. **Fail-open** — No match = allow (safe default)

### JSON Output Format

When a gate triggers:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Rule 2: Destructive DB command requires explicit confirmation"
  }
}
```

No output = action allowed.

## Future Extensions

Potential enhancements (out of scope for v1):

- **State threading** — Gates pass data through SessionEnd for multi-turn flows
- **Conditional routing** — Route prompts to different handlers based on gate decision
- **Transformations** — Gates modify tool input (sanitize commands, etc.)
- **Rate limiting** — Track gate triggers, enforce frequency limits
- **Async decisions** — Call external APIs for approval (requires changes to hook interface)
- **Audit logging** — Automatic logging of all gate decisions to file/database

## Contributing

See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines on:
- Creating new gates
- Writing gate patterns
- Testing and validation
- Issue reporting

## License

This framework is part of the claude-x playground project.

## References

- **Design Specification:** `docs/superpowers/specs/2026-07-02-hook-gates-framework-design.md`
- **Implementation Plan:** `docs/superpowers/plans/2026-07-02-hook-gates-framework-plan.md`
- **Claude Code Hooks:** https://claude.ai/code — Documentation on hook system
