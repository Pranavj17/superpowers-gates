# Gate YAML Schema Reference

## Required Fields

Every gate must have these fields:

### `name` (string, kebab-case)
Unique identifier for the gate.
```yaml
name: "no-destructive-db"
```

### `description` (string)
Human-readable description of what the gate does.
```yaml
description: "Prevent mix ecto.create/drop/reset without explicit approval"
```

### `hook` (string, enum)
When the gate is evaluated. Valid values:
- `PreToolUse` — Before a tool executes
- `PostToolUse` — After a tool executes
- `UserPromptSubmit` — When user submits a prompt
- `SessionStart` — When session begins
- `SessionEnd` — When session ends

```yaml
hook: "PreToolUse"
```

### `matcher` (string, regex)
Which tools to match. Examples:
- `"Bash"` — Only Bash tool
- `"Write|Edit"` — Write or Edit tools
- `"*"` — All tools

```yaml
matcher: "Bash"
```

### `condition` (string, bash code)
Bash code that returns 0 (trigger gate) or non-zero (don't trigger).
Input is available to `jq` via stdin.

```yaml
condition: |
  jq -r '.tool_input.command' | grep -qE '\bmix +ecto\.(create|drop|reset)\b'
```

**Gotchas:**

1. **Stdin is consumed once.** The hook JSON arrives on stdin a single time. If
   your condition needs more than one `jq` call, capture stdin first or the
   second call silently reads an empty stream:

   ```yaml
   condition: |
     input=$(cat)
     file=$(jq -r '.tool_input.file_path // ""' <<< "$input")
     added=$(jq -r '.tool_input.content // .tool_input.new_string // ""' <<< "$input")
     ...
   ```

2. **Gates run globally.** The runner is registered as a user-level hook, so
   every gate fires in every project. A gate enforcing a project-specific rule
   must path-scope its condition, e.g.:

   ```yaml
   condition: |
     file=$(jq -r '.tool_input.file_path')
     case "$file" in
       /Users/you/projects/my-repo/*) ;;  # this repo only
       *) exit 1 ;;
     esac
     ...
   ```

3. **Side-effect gates.** A gate can perform an action (e.g. append to a log)
   and then `exit 1` so it never emits a decision — useful for PostToolUse
   audit trails where per-call decision output would be noise. See
   `examples/audit-log.yaml`.

### `decision` (string, enum)
What Claude Code should do when gate triggers. Valid values:
- `"allow"` — Permit the action
- `"deny"` — Block the action
- `"ask"` — Ask user for permission
- `"transform"` — Modify input (future, requires handler)

```yaml
decision: "ask"
```

### `message` (string)
User-facing reason shown when gate triggers.

```yaml
message: "Rule 2: Destructive DB command requires explicit confirmation"
```

## Optional Fields

### `tags` (string array)
Searchable categories. Default: `[]`

```yaml
tags: ["security", "database", "rule-2"]
```

### `severity` (string, enum)
Risk level for sorting. Valid values: `low`, `medium`, `high`, `critical`. Default: `"medium"`

```yaml
severity: "high"
```

### `version` (string)
Gate version for compatibility. Default: `"1.0"`

```yaml
version: "1.0"
```

### `author` (string)
Who wrote this gate.

```yaml
author: "pranav.j@scripbox.com"
```

## Condition Evaluation

The `condition` field is bash code with special context:

- Input is piped via stdin as a jq object (Claude Code hook input)
- You can use jq to extract fields
- You can pipe to grep, awk, etc.
- Return 0 (exit 0) to trigger, non-zero to skip

### Examples

**Extract and check command:**
```yaml
condition: |
  jq -r '.tool_input.command' | grep -qE '\bmix +ecto\.(create|drop|reset)\b'
```

**Check file extension:**
```yaml
condition: |
  file=$(jq -r '.tool_input.file_path')
  [[ "$file" == *.md ]]
```

**Multiple conditions:**
```yaml
condition: |
  file=$(jq -r '.tool_input.file_path')
  [[ "$file" == *.md ]] && [[ ! "$file" =~ /docs/ ]]
```

## Complete Example

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
version: "1.0"
author: "pranav.j@scripbox.com"
```
