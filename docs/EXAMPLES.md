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

## Flagship: Stop Run Tests

Blocks ending the turn when code files were edited this session but no test
command has run yet — a definition-of-done nudge, not a permission check.

```yaml
name: "stop-run-tests"
description: "Block ending the turn when code files were edited but no test command ran"
hook: "Stop"
matcher: "*"
condition: |
  input=$(cat)
  tp=$(jq -r '.transcript_path // empty' <<< "$input")
  [ -n "$tp" ] && [ -f "$tp" ] || exit 1
  source "$GATES_LIB_DIR/transcript-helpers.sh"
  th_edited_files_matching "$tp" '\.(ex|exs|py|js|ts)"' >/dev/null || exit 1
  th_ran_command_matching "$tp" '(mix test|pytest|npm test|go test)' && exit 1
  exit 0
decision: "block"
message: "Code files were edited this session but no test command has run. Run the tests before finishing."
tags: ["orchestration", "definition-of-done"]
severity: "medium"
```

**Triggers when:** `Stop` fires, the transcript shows an edited source file this session, and no matching test command has run since  
**Decision:** Blocks the stop — Claude sees the reason and continues the turn  
**Uses:** `transcript-helpers.sh` (`th_edited_files_matching`, `th_ran_command_matching`) to read the transcript instead of tracking state itself  
**Note:** The runner's stop-loop guard auto-allows a repeat `Stop` within the same turn (default `max_blocks: 1`), so this can't nag forever

---

## Flagship: Prompt Router

Injects workflow instructions into the conversation when the user's prompt
contains a tracker URL — a generic template for the Asana/Sentry→RCA router.

```yaml
name: "prompt-router"
description: "Inject workflow instructions when the prompt contains a tracker URL (template)"
hook: "UserPromptSubmit"
matcher: "*"
condition: |
  p=$(jq -r '.prompt // .user_input // empty')
  echo "$p" | grep -qE 'app\.asana\.com/[0-9]+/|sentry\.[a-z.]+/organizations/[^/]+/issues/' || exit 1
  echo "WORKFLOW TRIGGER: tracker URL detected in this prompt. Execute the project's full RCA workflow automatically without waiting for confirmation."
decision: "inject"
message: "tracker URL detected"
tags: ["orchestration", "routing"]
severity: "low"
```

**Triggers when:** The submitted prompt contains an Asana task URL or a Sentry issue URL  
**Decision:** Injects context — the condition's stdout (the `WORKFLOW TRIGGER: ...` line), not `message`, becomes the `additionalContext`  
**Use case:** Auto-route tracker links to a debugging workflow without the user having to say "debug rca"

---

## Flagship: Boot Info

Injects project boot context on a fresh session start by reading a
project-local `.claude/BOOT.md` file, if one exists.

```yaml
name: "boot-info"
description: "Inject project boot context on fresh session start (reads .claude/BOOT.md if present)"
hook: "SessionStart"
matcher: "startup"
condition: |
  input=$(cat)
  cwd=$(jq -r '.cwd // empty' <<< "$input")
  [ -n "$cwd" ] && [ -f "$cwd/.claude/BOOT.md" ] || exit 1
  cat "$cwd/.claude/BOOT.md"
decision: "inject"
message: "boot context"
tags: ["orchestration", "context"]
severity: "low"
```

**Triggers when:** `SessionStart` fires with `source: "startup"` and the cwd has a `.claude/BOOT.md`  
**Decision:** Injects context — the file's contents (printed by the condition) become the `additionalContext`, verbatim  
**Use case:** Give every fresh session project-specific boot info without a manual "load context" step

---

## Flagship: Format Nudge

Reminds Claude to run the formatter right after it edits a source file.

```yaml
name: "format-nudge"
description: "After editing an Elixir file, remind Claude to run mix format"
hook: "PostToolUse"
matcher: "Write|Edit"
condition: |
  f=$(jq -r '.tool_input.file_path // empty')
  case "$f" in
    *.ex|*.exs) echo "Reminder: you edited $f — run 'mix format' before finishing." ;;
    *) exit 1 ;;
  esac
decision: "inject"
message: "formatting reminder"
tags: ["orchestration", "feedback"]
severity: "low"
```

**Triggers when:** A `Write` or `Edit` targets a `.ex`/`.exs` file  
**Decision:** Injects context — the printed reminder becomes `additionalContext`  
**Use case:** Lightweight per-language template for a "run the formatter" nudge (swap the extension/command for other stacks)

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
