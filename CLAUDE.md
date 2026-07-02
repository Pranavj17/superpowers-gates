# claude-x: Hook Framework Playground

Experimental project for designing and testing a **conditional routing + state threading hook framework** for Claude Code.

## Purpose

Build a reusable, testable hook pattern that:
- Routes prompts conditionally based on UserPromptSubmit analysis
- Threads state through execution (prompt → SessionEnd)
- Persists audit trails and decisions
- Works across projects

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

## Current Status

- [ ] Brainstorm hook framework design
- [ ] Propose 2-3 implementation approaches
- [ ] Design conditional routing + state threading patterns
- [ ] Prototype core hook library
- [ ] Write tests
- [ ] Document patterns

## How to Use

Start a new Claude Code session from this project:

```bash
claude-x  # zsh alias: cd to claude-x and start claude
```

All work happens in this fresh session to keep context clean.
