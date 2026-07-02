# Task 9: Create Example Gates

**Goal:** Create 3 example gate YAML files demonstrating the framework.

**Files to create:**
- `lib/examples/no-destructive-db.yaml` — Rule 2 gate (from spec)
- `lib/examples/no-docs-violation.yaml` — Rule 4 gate (from spec)
- `lib/examples/audit-log.yaml` — Audit trail gate (PostToolUse)

**Exact gate content from plan Task 9 / spec:**
- no-destructive-db.yaml: PreToolUse/Bash, detects mix ecto.*, decision=ask
- no-docs-violation.yaml: PreToolUse/Write|Edit, enforces /docs rule, decision=deny
- audit-log.yaml: PostToolUse/*, always triggers, decision=allow

**Steps:**
1. Create lib/examples/ directory
2. Write 3 .yaml gate files with exact content from spec
3. Validate each gate: `bash lib/gates/validate.sh <gate>`
4. All 3 should pass validation
5. Commit: "docs(examples): add Rule 2, Rule 4, and audit-log gate examples"

**Report file:** `/Users/pranav.j/Documents/claude-x/.superpowers/sdd/task-9-report.md`
