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
When the gate is evaluated. Valid values: `PreToolUse`, `PostToolUse`,
`UserPromptSubmit`, `SessionStart`, `Stop`, `SubagentStop`. See
[Decision dialects](#decision-dialects) below for which `decision` values are
legal on each.

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

2. **Gates are scoped by placement, not by field.** The runner loads gates
   from `<cwd>/.claude/gates/*.yaml` (project) first, then
   `~/.claude/gates/*.yaml` (global) — see [Gate loading
   order](#gate-loading-order). A project gate applies only in that repo; a
   global gate fires everywhere. There is no `scope:`/`paths:` YAML field —
   drop a gate in the repo's `.claude/gates/` to scope it there instead of
   path-guarding the condition:

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
What Claude Code should do when the gate triggers. `decision` is
**event-aware** — the legal values (and what the runner emits) depend on
`hook`. The validator rejects a `decision` that isn't legal for its `hook`.

#### Decision dialects

| `hook` | legal `decision` | on trigger, runner emits |
|---|---|---|
| PreToolUse | `ask` / `deny` / `allow` | `hookSpecificOutput.permissionDecision` + reason (unchanged) |
| PostToolUse | `block` / `inject` | `{"decision":"block","reason":message}` or `hookSpecificOutput.additionalContext` |
| UserPromptSubmit | `block` / `inject` | `{"decision":"block","reason":message}` (prompt erased) or `additionalContext` |
| SessionStart | `inject` | `hookSpecificOutput.additionalContext` |
| Stop | `block` | `{"decision":"block","reason":message}` — turn continues, Claude sees reason |
| SubagentStop | `block` | same as Stop |

```yaml
decision: "ask"
```

**The inject/stdout contract.** Condition stdout is the payload for `inject`
gates: when an `inject` gate's condition exits 0, the runner captures
whatever it printed to stdout and emits that as `additionalContext`. The
condition is both predicate and generator — e.g. a `SessionStart` gate whose
condition prints boot info becomes the injected context verbatim. For
`block`/`ask`/`deny`/`allow` gates the static `message:` field is the reason,
as always; stdout is ignored for those.

### `message` (string)
User-facing reason shown when gate triggers (ignored for `inject` gates,
where stdout is the payload — see above).

```yaml
message: "Rule 2: Destructive DB command requires explicit confirmation"
```

## Gate loading order

The runner loads gates from two directories, in order:

1. `<cwd>/.claude/gates/*.yaml` — project gates (`cwd` comes from the hook
   input JSON) — **only for trusted projects**, see below
2. `~/.claude/gates/*.yaml` — global gates

Within each directory, gates load alphabetically. Across the merged list,
**first triggered gate wins** — so a project gate can pre-empt a global gate
of the same shape simply by existing.

> **Security note:** Project gates run arbitrary bash from the repository on
> hook events including SessionStart. They are loaded ONLY for trusted
> projects: add the repo's absolute path to `~/.claude/gates-trusted`, or set
> `GATES_TRUST_PROJECT=1`. Treat this like Claude Code project hooks. An
> untrusted project's `.claude/gates/*.yaml` files are skipped entirely —
> only global gates from `~/.claude/gates/` apply.

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

### `max_blocks` (integer, `Stop`/`SubagentStop` only)
Default: `1`. A blocked `Stop` makes Claude continue and eventually try to
stop again; the runner auto-allows the gate on a repeat stop within the same
turn to prevent infinite nagging. Set `max_blocks: N` to opt into more
re-blocks before the guard kicks in.

```yaml
max_blocks: 2
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
