# Gate Examples

## Rule 2: Prevent Destructive Database Commands

Prevents accidental `mix ecto.create`, `mix ecto.drop`, and `mix ecto.reset` commands.

```yaml
name: "no-destructive-db"
hook: "PreToolUse"
matcher: "Bash"
condition: |
  jq -r '.tool_input.command' | grep -qE '\bmix +ecto\.(create|drop|reset)\b'
decision: "ask"
message: "Rule 2: Destructive DB command requires explicit confirmation"
tags: ["security", "database"]
severity: "high"
```

**Triggers when:** User tries to run `mix ecto.drop`, `mix ecto.create`, or `mix ecto.reset`  
**Decision:** Asks user for confirmation  
**Message:** Shows rule reminder

---

## Rule 4: Documentation Location

Prevents `.md` files from being created outside `/docs/` directory.

```yaml
name: "no-docs-violation"
hook: "PreToolUse"
matcher: "Write|Edit"
condition: |
  file=$(jq -r '.tool_input.file_path')
  base="${file##*/}"
  [[ "$base" == *.md ]] || exit 1
  case "$file" in
    */docs/*|docs/*) exit 1 ;;
  esac
  case "$base" in
    CLAUDE.md|README.md|claude.md) exit 1 ;;
  esac
  exit 0
decision: "deny"
message: "Rule 4: .md files must live under /docs (exceptions: CLAUDE.md, README.md, directory claude.md)"
tags: ["documentation"]
severity: "medium"
```

**Triggers when:** Creating `.md` file outside `/docs/` (except exceptions)  
**Decision:** Denies the action  
**Exceptions:** CLAUDE.md, README.md, directory-specific claude.md files

---

## Audit Log Gate

Logs all tool usage for compliance/audit trails.

```yaml
name: "audit-log"
hook: "PostToolUse"
matcher: "*"
condition: exit 0  # Always trigger
decision: "allow"
message: "Tool execution logged"
tags: ["audit"]
severity: "low"
```

**Triggers when:** Any tool executes (PostToolUse hook)  
**Decision:** Allows action and logs  
**Use case:** Compliance, security audits, debugging

---

## Custom Gate: npm Lock Prevention

Prevent `npm install` when `package-lock.json` exists (use `npm ci` instead).

```yaml
name: "lock-npm-installs"
description: "Use npm ci instead of npm install with lock files"
hook: "PreToolUse"
matcher: "Bash"
condition: |
  cmd=$(jq -r '.tool_input.command')
  [ "$cmd" = "npm install" ] && [ -f package-lock.json ]
decision: "ask"
message: "Use npm ci instead (package-lock.json exists for reproducible installs)"
tags: ["npm", "best-practice"]
severity: "low"
```

---

## Custom Gate: SQL Injection Prevention

Block direct SQL when a safe ORM alternative exists.

```yaml
name: "no-raw-sql"
description: "Prevent raw SQL in Elixir (use Ecto instead)"
hook: "PreToolUse"
matcher: "Edit"
condition: |
  file=$(jq -r '.tool_input.file_path')
  # Only check .ex files (Elixir source)
  [[ "$file" == *.ex ]] || exit 1
  # This is a simple heuristic; full implementation would parse the file
  exit 0
decision: "ask"
message: "Consider using Ecto queries instead of raw SQL for safety"
tags: ["security", "sql", "elixir"]
severity: "medium"
```

---

## Custom Gate: Env File Protection

Prevent writing `.env` or `.env.local` files.

```yaml
name: "protect-env-files"
description: "Prevent committing .env files"
hook: "PreToolUse"
matcher: "Write|Edit"
condition: |
  file=$(jq -r '.tool_input.file_path')
  base="${file##*/}"
  [[ "$base" == .env || "$base" == .env.local ]]
decision: "deny"
message: "Do not commit .env files (use .env.example or secrets manager)"
tags: ["security", "secrets"]
severity: "critical"
```
