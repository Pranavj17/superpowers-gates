# Getting Started with Hook Gates Framework

## Installation

```bash
git clone https://github.com/Pranavj17/superpowers-gates ~/.claude/gates-framework
mkdir -p ~/.claude/gates
cp -r ~/.claude/gates-framework/lib/examples/* ~/.claude/gates/
bash ~/.claude/gates-framework/lib/gates/validate.sh
```

## Configuration

Add to your `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/gates-framework/lib/gates/runner.sh PreToolUse",
            "statusMessage": "Checking gates..."
          }
        ]
      }
    ]
  }
}
```

## Quick Example

Test a gate directly:

```bash
# Test Rule 2 with destructive DB command
echo '{"tool":"Bash","tool_input":{"command":"mix ecto.drop"}}' | \
  bash ~/.claude/gates-framework/lib/gates/runner.sh PreToolUse

# Output:
# {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"Rule 2: Destructive DB command requires explicit confirmation"}}
```

## Your First Custom Gate

Create a new gate file at `~/.claude/gates/my-custom-gate.yaml`:

```yaml
name: "my-custom-rule"
description: "My first custom permission gate"
hook: "PreToolUse"
matcher: "Bash"
condition: |
  jq -r '.tool_input.command' | grep -q "npm install"
decision: "ask"
message: "Consider using npm ci instead of npm install"
tags: ["npm", "best-practice"]
severity: "low"
```

Validate it:

```bash
bash ~/.claude/gates-framework/lib/gates/validate.sh ~/.claude/gates/my-custom-gate.yaml
```

## How Gates Work

1. Claude Code fires a hook (e.g., `PreToolUse`)
2. Hook runner loads all `.yaml` files from `~/.claude/gates/`
3. For each gate (alphabetically):
   - Check if hook matches
   - Check if tool matches (regex)
   - Evaluate condition (bash code)
4. First matching gate triggers:
   - Decision (ask/deny/allow) is returned to Claude Code
5. No gate matches → allow action (fail-open)

## File Structure

- `~/.claude/gates-framework/lib/gates/` — Core framework (runner.sh, validator, schema)
- `~/.claude/gates-framework/lib/examples/` — Example gates (Rule 2, Rule 4)
- `~/.claude/gates/` — Your project-specific gates (copy examples here)

## Next Steps

- Read `SCHEMA_REFERENCE.md` for detailed gate YAML format
- See `EXAMPLES.md` for more gate patterns
- Read `CONTRIBUTING.md` to add new gates to the framework
