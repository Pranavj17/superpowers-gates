# Superpowers Gates — Architecture

## Monorepo Structure

```
superpowers-gates/
├── framework/          # Core gate execution engine (unchanged)
│   ├── VERSION         # Framework version symlink
│   └── lib/
│       ├── gates/      # Runner, validator, helpers, schema
│       ├── examples/   # Production-ready gates
│       └── tests/      # 24 tests (100% coverage)
├── skill/              # Claude Code skill (MCP wrapper)
│   ├── plugin.json     # Registry manifest
│   ├── mcp_server.py   # MCP tools + prompts
│   ├── init.sh         # First-install setup
│   └── tests/          # Skill integration tests
├── docs/               # User guides
├── .github/workflows/  # CI for both framework + skill
├── VERSION             # Single source for versioning
└── README.md           # Dual-path entry point
```

## Design Principles

### Single Source of Truth
- **Framework** contains all gate logic
- **Skill** is a thin wrapper — MCP tools call framework validators
- No code duplication

### Dual Distribution
- **Framework path**: Users clone repo, install manually
- **Skill path**: Users find in Claude Code registry, one-click install

### Version Synchronization
- Single `VERSION` file at repo root
- CI enforces: `framework/VERSION` == `skill/plugin.json` version

---

See `docs/superpowers/specs/2026-07-02-superpowers-gates-skill-design.md` for design details.
