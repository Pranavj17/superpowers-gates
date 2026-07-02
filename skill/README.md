# Superpowers Gates Skill

Claude Code skill for YAML-based permission gates.

## Quick Start

This skill is installed via Claude Code plugin registry. After installation:

1. Run `/create-gate` to start the interactive gate wizard
2. Use `validate-gates` tool to check all installed gates
3. Run `/list-gates` to discover and search installed gates

## Setup

The skill's init script will run on first install:
- Clones the framework to `~/.claude/gates-framework`
- Creates `~/.claude/gates` directory for custom gates
- Copies example gates (Rule 2, Rule 4, Audit)
- Optionally registers the PreToolUse hook

## For Framework Developers

See the root [README.md](../README.md) for framework documentation.
