# claude-x: Hook Gates Framework

A **YAML-based declarative permission & safety gates framework** for Claude Code that makes hooks readable, testable, and reusable. Gates replace complex inline jq/bash in settings.json with plain YAML files.

## Purpose

Provide a composable gate pattern that:
- Defines permission rules as declarative YAML files (`~/.claude/gates/*.yaml`)
- Evaluates conditions (bash/jq filters) for hook events
- Returns permission decisions (allow/deny/ask) without inline JSON escaping
- Is testable, versionable, and reusable across projects

## Project Structure

```
claude-x/
├── .claude/
│   ├── hooks/          # Hook implementations
│   ├── agents/         # Custom agent definitions
│   └── settings.json   # Project configuration
├── lib/                # Hook framework library
├── tests/              # Hook pattern tests
├── docs/               # Design specs & documentation
└── examples/           # Example hook configurations
```

## Framework Status: COMPLETE ✅

The hook gates framework is fully implemented, tested, and documented:

- ✅ **Design & Specification** — `docs/superpowers/specs/2026-07-02-hook-gates-framework-design.md`
- ✅ **Core Implementation** — Gate executor (`lib/gates/runner.sh`), validator (`lib/gates/validate.sh`), JSON schema (`lib/gates/schema.json`)
- ✅ **Helper Functions** — Reusable bash/jq filters (`lib/gates/helpers.sh`)
- ✅ **Test Suite** — 30 unit tests across 6 test files (100% passing)
- ✅ **Example Gates** — 3 production-ready gates (Rule 2, Rule 4, Audit Log)
- ✅ **Documentation** — GETTING_STARTED, SCHEMA_REFERENCE, EXAMPLES, CONTRIBUTING guides

### How to Use

1. **Install Framework**
   ```bash
   git clone https://github.com/pranav/claude-gates-framework ~/.claude/gates-framework
   mkdir -p ~/.claude/gates
   cp -r ~/.claude/gates-framework/lib/examples/* ~/.claude/gates/
   ```

2. **Create Custom Gates** — Add `.yaml` files to `~/.claude/gates/`:
   ```yaml
   name: "my-rule"
   description: "My permission gate"
   hook: "PreToolUse"
   matcher: "Bash"
   condition: |
     jq -r '.tool_input.command' | grep -q "dangerous-command"
   decision: "ask"
   message: "This requires confirmation"
   tags: ["security"]
   severity: "high"
   ```

3. **Register in Claude Code** — Add to `.claude/settings.json`:
   ```json
   {
     "hooks": {
       "PreToolUse": [{
         "hooks": [{
           "type": "command",
           "command": "bash ~/.claude/gates-framework/lib/gates/runner.sh PreToolUse",
           "statusMessage": "Checking gates..."
         }]
       }]
     }
   }
   ```

For detailed documentation, see `docs/GETTING_STARTED.md`.
