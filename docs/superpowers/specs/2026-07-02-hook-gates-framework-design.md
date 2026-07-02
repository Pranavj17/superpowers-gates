# Hook Gates Framework Design

**Date:** 2026-07-02  
**Project:** claude-x  
**Scope:** Claude Code plugin/extension for permission & safety gates  
**Status:** Design approved, ready for implementation plan

---

## Overview

**Problem:** Claude Code hooks are powerful but verbose. Complex conditions (like Rule 2 and Rule 4 in the Memory project) require embedded jq/grep in JSON, making them hard to read, test, and reuse.

**Solution:** A **declarative YAML-based gate framework** that abstracts hook logic into composable, testable permission gates. Gates define conditions (bash/jq filters) and decisions (allow/deny/ask) in plain YAML, eliminating shell script complexity from `.claude/settings.json`.

**Target Users:**
- Claude Code projects needing permission/safety rules
- Teams building reusable hook libraries
- Anyone who wants to audit what their hooks do

**Scope:** Permission/safety gates only (PreToolUse, PostToolUse). State threading and conditional routing are future extensions.

---

## Architecture

### Core Concept: Gates as YAML Files

A **gate** is a single YAML file (`~/.claude/gates/*.yaml`) that defines:
- **Condition:** When does this gate trigger? (bash/jq filter)
- **Decision:** What should Claude Code do? (allow/deny/ask)
- **Message:** Why? (shown to user)
- **Metadata:** Hook, matcher, severity, tags

```yaml
# Example: no-destructive-db.yaml
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

### Execution Flow

```
Claude Code fires hook (e.g., PreToolUse)
        ↓
Hook runner loads all gates from ~/.claude/gates/*.yaml
        ↓
For each gate (in alphabetical order):
  - Does hook match? (PreToolUse, PostToolUse, etc.)
  - Does matcher match? (Bash, Write|Edit, *)
  - Does condition evaluate to true? (run bash condition)
        ↓
First matching gate triggers:
  - Return {decision, message} to Claude Code
  - Claude Code processes decision (ask, deny, allow, transform)
        ↓
No gate matches:
  - Allow the action (fail-open)
```

### File Structure

```
claude-x/
├── lib/
│   ├── gates/
│   │   ├── runner.sh              # Gate executor
│   │   ├── validate.sh            # YAML validator
│   │   ├── helpers.sh             # Reusable jq/grep/bash functions
│   │   └── schema.json            # JSON Schema for gates
│   ├── examples/
│   │   ├── no-destructive-db.yaml
│   │   ├── no-docs-violation.yaml
│   │   └── audit-log.yaml
│   └── tests/
│       ├── gate-runner.test.sh
│       ├── validate.test.sh
│       └── fixtures/
│           ├── mock-preToolUse-bash.json
│           ├── mock-preToolUse-write.json
│           └── ...
├── docs/
│   ├── GETTING_STARTED.md
│   ├── SCHEMA_REFERENCE.md
│   ├── EXAMPLES.md
│   └── CONTRIBUTING.md
└── .claude/
    ├── settings.json              # Registers runner
    └── gates/                     # Project-specific gates (user copies here)
```

---

## Gate File Format (YAML Schema)

### Required Fields

| Field | Type | Description | Example |
|:---|:---|:---|:---|
| `name` | string | Unique identifier (kebab-case) | `"no-destructive-db"` |
| `description` | string | Human-readable purpose | `"Prevent mix ecto.create/drop/reset without explicit approval"` |
| `hook` | enum | When to trigger | `"PreToolUse"` |
| `matcher` | string | Which tools to match | `"Bash"` or `"Write\|Edit"` or `"*"` |
| `condition` | string | Bash code that triggers gate if exit 0 | `jq ... \| grep ...` |
| `decision` | enum | What Claude Code should do | `"allow"`, `"deny"`, `"ask"`, or `"transform"` |
| `message` | string | User-facing reason | `"Rule 2: ..."` |

### Optional Fields

| Field | Type | Default | Description |
|:---|:---|:---|:---|
| `tags` | string[] | `[]` | Searchable categories | `["security", "database"]` |
| `severity` | enum | `"medium"` | Risk level for sorting | `"low"`, `"medium"`, `"high"` |
| `version` | string | `"1.0"` | Gate version for compatibility | `"1.0"` |
| `author` | string | none | Who wrote this gate | `"pranav.j@scripbox.com"` |

### Valid Values

**hook:** `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SessionStart`, `SessionEnd`

**decision:** 
- `"allow"` — permit the action
- `"deny"` — block the action
- `"ask"` — ask user for permission
- `"transform"` — modify input (future, requires handler)

**severity:** `"low"`, `"medium"`, `"high"`, `"critical"`

---

## Hook Integration

### Registering the Runner

Add to `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/gates/runner.sh PreToolUse",
            "statusMessage": "Checking gates..."
          }
        ]
      }
    ]
  }
}
```

### Runner Implementation (`runner.sh`)

```bash
#!/bin/bash
# Gate executor: evaluate all matching gates, return first decision

HOOK_EVENT="${1:-PreToolUse}"
GATES_DIR="${HOME}/.claude/gates"

[ -d "$GATES_DIR" ] || exit 0  # No gates, allow

for gate_file in "$GATES_DIR"/*.yaml; do
  [ -f "$gate_file" ] || continue
  
  # Extract gate metadata
  hook=$(yq '.hook' "$gate_file")
  matcher=$(yq '.matcher' "$gate_file")
  
  # Check if gate applies to this hook event
  [ "$hook" = "$HOOK_EVENT" ] || continue
  
  # Check if matcher applies (from Claude Code stdin)
  tool=$(jq -r '.tool // empty')
  if [ -n "$matcher" ] && [ "$matcher" != "*" ]; then
    [[ "$tool" =~ $matcher ]] || continue
  fi
  
  # Evaluate condition
  condition=$(yq '.condition' "$gate_file")
  if eval "$condition"; then
    # Gate triggered: output decision
    name=$(yq '.name' "$gate_file")
    decision=$(yq '.decision' "$gate_file")
    message=$(yq '.message' "$gate_file")
    
    echo "{
      \"hookSpecificOutput\": {
        \"hookEventName\": \"$HOOK_EVENT\",
        \"permissionDecision\": \"$decision\",
        \"permissionDecisionReason\": \"$message\"
      }
    }" | jq -c .
    exit 0
  fi
done

exit 0  # No gates matched, allow
```

### Key Design Decisions

1. **First-match wins** — Gates evaluated in alphabetical order, first trigger stops evaluation
2. **Fail-open** — No matching gate = allow (gates are restrictions, not allowlists)
3. **Conditions are bash** — Full bash/jq flexibility; testable in isolation
4. **Stateless execution** — No side effects, pure decision-making
5. **Input from stdin** — Gate receives Claude Code hook input as jq object

---

## Refactoring Existing Rules

### Rule 2 → YAML Gate

**Before** (in `.claude/settings.json`):
```json
{
  "matcher": "Bash",
  "hooks": [{
    "type": "command",
    "command": "COMMAND=$(jq -r '.tool_input.command'); if echo \"$COMMAND\" | grep -qE '\\bmix +ecto\\.(create|drop|reset)\\b'; then echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"Rule 2 (no-destructive-db): mix ecto.create/drop/reset requires explicit user confirmation\"}}'; fi"
  }]
}
```

**After** (in `~/.claude/gates/no-destructive-db.yaml`):
```yaml
name: "no-destructive-db"
description: "Prevent mix ecto.create/drop/reset without explicit approval (Rule 2)"
hook: "PreToolUse"
matcher: "Bash"
condition: |
  jq -r '.tool_input.command' | grep -qE '\bmix +ecto\.(create|drop|reset)\b'
decision: "ask"
message: "Rule 2: Destructive DB command requires explicit confirmation"
tags: ["security", "database", "rule-2"]
severity: "high"
```

**Benefits:**
- ✅ 10× more readable
- ✅ Can be tested independently
- ✅ Reusable across projects
- ✅ Versionable in git
- ✅ Discoverable via `ls`

### Rule 4 → YAML Gate

**Before** (in `.claude/settings.json`, 5 lines of nested escaping):
```json
{
  "matcher": "Write|Edit",
  "hooks": [{
    "type": "command",
    "command": "FILE=$(jq -r '.tool_input.file_path'); BASE=\"${FILE##*/}\"; case \"$BASE\" in *.md) case \"$FILE\" in */docs/*|docs/*) exit 0;; esac; case \"$BASE\" in CLAUDE.md|README.md|claude.md) exit 0;; esac; echo \"{\\\"hookSpecificOutput\\\":{\\\"hookEventName\\\":\\\"PreToolUse\\\",\\\"permissionDecision\\\":\\\"deny\\\",\\\"permissionDecisionReason\\\":\\\"Rule 4 (docs-location): new .md files must live under /docs...\\\"}}\" ;; esac"
  }]
}
```

**After** (in `~/.claude/gates/no-docs-violation.yaml`):
```yaml
name: "no-docs-violation"
description: "Enforce Rule 4: .md files must live under /docs"
hook: "PreToolUse"
matcher: "Write|Edit"
condition: |
  file=$(jq -r '.tool_input.file_path')
  base="${file##*/}"
  
  # Only apply to .md files
  [[ "$base" == *.md ]] || exit 1
  
  # Allowed locations
  case "$file" in
    */docs/*|docs/*) exit 1 ;;  # Allowed
  esac
  
  # Allowed filenames
  case "$base" in
    CLAUDE.md|README.md|claude.md) exit 1 ;;  # Allowed
  esac
  
  # Everything else denied
  exit 0
decision: "deny"
message: "Rule 4: .md files must live under /docs (exceptions: CLAUDE.md, README.md, directory claude.md)"
tags: ["documentation", "rule-4"]
severity: "medium"
```

---

## Testing Strategy

### Validation (`validate.sh`)

Ensures all gates are well-formed:
- Required fields present
- Hook/decision values valid
- YAML parseable
- Conditions are executable bash

```bash
bash ~/.claude/gates/validate.sh
# Output:
# ✓ no-destructive-db.yaml valid
# ✓ no-docs-violation.yaml valid
```

### Unit Tests (`gate-runner.test.sh`)

Test fixtures mock Claude Code hook input:

```bash
# Test Rule 2 catches destructive command
test_rule_2_destructive_db() {
  local input='{"tool":"Bash","tool_input":{"command":"mix ecto.drop"}}'
  local result=$(bash runner.sh PreToolUse <<< "$input")
  
  assert_contains "$result" '"permissionDecision":"ask"'
  assert_contains "$result" "Rule 2"
}

# Test Rule 2 allows safe command
test_rule_2_safe_command() {
  local input='{"tool":"Bash","tool_input":{"command":"ls -la"}}'
  local result=$(bash runner.sh PreToolUse <<< "$input")
  
  # No gate matched, empty output
  [ -z "$result" ]
}

# Test Rule 4 catches root .md files
test_rule_4_root_md() {
  local input='{"tool":"Write","tool_input":{"file_path":"/OAUTH.md"}}'
  local result=$(bash runner.sh PreToolUse <<< "$input")
  
  assert_contains "$result" '"permissionDecision":"deny"'
  assert_contains "$result" "Rule 4"
}

# Test Rule 4 allows docs/.md files
test_rule_4_docs_md() {
  local input='{"tool":"Write","tool_input":{"file_path":"/docs/OAUTH.md"}}'
  local result=$(bash runner.sh PreToolUse <<< "$input")
  
  [ -z "$result" ]  # No gate matched
}
```

---

## Distribution & Usage

### For Users

**Install:**
```bash
git clone https://github.com/pranav/claude-gates-framework ~/.claude/gates-framework
cp -r ~/.claude/gates-framework/lib/examples/* ~/.claude/gates/
bash ~/.claude/gates/validate.sh
```

**Configure:**
Update `.claude/settings.json` to call the runner (see Hook Integration section).

**Use:**
```bash
# Check if gates are working
echo '{"tool":"Bash","tool_input":{"command":"mix ecto.drop"}}' | \
  bash ~/.claude/gates/runner.sh PreToolUse
# Output: decision: ask, reason: Rule 2
```

### As a Package

**Future:** Distribute via npm:
```bash
npm install @claude-code/gates
# Unpacks to ~/.claude/gates with symlink
```

---

## Extensibility

### Adding New Gates

Users create new `.yaml` files in `~/.claude/gates/`:

```bash
# New gate: prevent npm install in projects with lockfiles
cat > ~/.claude/gates/lock-npm-installs.yaml << 'EOF'
name: "lock-npm-installs"
description: "Prevent npm install if package-lock.json exists (use npm ci instead)"
hook: "PreToolUse"
matcher: "Bash"
condition: |
  cmd=$(jq -r '.tool_input.command')
  [ "$cmd" = "npm install" ] && [ -f package-lock.json ]
decision: "ask"
message: "Use npm ci instead of npm install (package-lock.json exists)"
tags: ["npm", "best-practice"]
severity: "low"
EOF

# Validate
bash ~/.claude/gates/validate.sh
```

### Custom Helpers

Users can source `helpers.sh` in their condition:

```yaml
condition: |
  source ~/.claude/gates/helpers.sh
  is_destructive_sql "$(jq -r '.tool_input.command')" && exit 0
  exit 1
```

---

## Future Extensions (Out of Scope)

1. **State threading** — Gates can pass state to SessionEnd
2. **Conditional routing** — Route prompts to different handlers based on gate decision
3. **Transformations** — Gates can modify tool input before execution
4. **Async decisions** — Gates can call external services for approval
5. **Rate limiting** — Track gate triggers, limit frequency
6. **Audit logging** — Automatic logging of all gate decisions to a file

---

## Success Criteria

✅ **Readability** — Rule 2 + Rule 4 in YAML are 5× clearer than nested JSON  
✅ **Testability** — Each gate has unit tests; 100% test coverage of conditions  
✅ **Reusability** — Gates can be copied to other Claude Code projects  
✅ **Discoverability** — `ls ~/.claude/gates/` shows all active rules  
✅ **Correctness** — Validator catches invalid gates; runner is bug-free  
✅ **Performance** — Gate evaluation < 100ms (bash startup dominated)  

---

## Implementation Plan

See: `2026-07-02-hook-gates-framework-plan.md` (generated by writing-plans skill)

**TDD approach:**
1. Write tests for runner.sh
2. Implement runner.sh
3. Write tests for validate.sh
4. Implement validate.sh
5. Refactor Rule 2 + Rule 4 as gates
6. Integration test in Memory project
7. Documentation + examples

**Estimated scope:** 8-10 TDD tasks
