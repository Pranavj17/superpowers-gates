# Gates v2 — Hook Control Plane (Design)

**Date:** 2026-07-03 · **Target version:** 1.2.0 · **Status:** Approved

## Goal

Extend superpowers-gates from a PreToolUse/PostToolUse permission-gate system
into a declarative control plane over the Claude Code agent loop: gate any
supported lifecycle event, load gates per-repo as well as globally, and emit
the correct decision dialect per event — all still as small YAML files.

## Scope (v1.2)

Six events:

- `PreToolUse`, `PostToolUse` — existing, unchanged semantics
- `UserPromptSubmit`, `SessionStart`, `Stop`, `SubagentStop` — new

**Non-goals (deferred):** `updatedInput` tool rewriting; `updatedToolOutput`;
the other ~24 hook events (PermissionRequest, TaskCreated, FileChanged, …) —
the runner's per-event emitter table makes each a small follow-up; a session
state machine (Stop gates read the turn's `tool_calls` and `transcript_path`
instead — stateless).

## Architecture

### Gate loading & scoping (by placement, not by field)

The runner loads, in order:

1. `<cwd>/.claude/gates/*.yaml` — project gates (cwd from hook input JSON)
2. `~/.claude/gates/*.yaml` — global gates

Alphabetical within each directory; **first triggered gate wins** (existing
semantics, now spanning both directories with project first). There is no
`scope:`/`paths:` YAML field — placing a gate inside a repo scopes it to that
repo. Repo-specific global gates (today's hand-written path guards) migrate to
the repo's `.claude/gates/`.

### Decision dialects

`decision:` becomes event-aware. The validator enforces legality per event.

| `hook` | legal `decision` | on trigger, runner emits |
|---|---|---|
| PreToolUse | `ask` / `deny` / `allow` | `hookSpecificOutput.permissionDecision` + reason (unchanged) |
| PostToolUse | `block` / `inject` | `{"decision":"block","reason":message}` or `hookSpecificOutput.additionalContext` |
| UserPromptSubmit | `block` / `inject` | `{"decision":"block","reason":message}` (prompt erased) or `additionalContext` |
| SessionStart | `inject` | `hookSpecificOutput.additionalContext` |
| Stop | `block` | `{"decision":"block","reason":message}` — turn continues, Claude sees reason |
| SubagentStop | `block` | same as Stop |

**Condition stdout is the payload for `inject` gates.** When an `inject`
gate's condition exits 0, the runner captures its stdout and emits it as
`additionalContext`. The condition is both predicate and generator (e.g. a
SessionStart gate whose condition prints boot info). For `block`/`ask`/`deny`
gates, the static `message:` field is the reason, as today; stdout is ignored.

### Matchers per event

The runner selects the match key by event: `tool_name` (PreToolUse,
PostToolUse), `source` — startup|resume|clear|compact (SessionStart),
`agent_type` (SubagentStop), none (Stop, UserPromptSubmit — matcher ignored,
treated as match-all). `*` or absent matcher = match all (translated to `.*`,
already shipped in v1.1).

### Stop-loop guard

A blocked Stop makes Claude continue and eventually try to stop again. To
prevent infinite nagging, the runner auto-allows Stop/SubagentStop gates when
the input indicates the stop was already blocked this turn (`stop_hook_active`
input field — exact name verified against live input during implementation; if
absent, fall back to a per-session-id counter file in `${TMPDIR}`). A gate may
opt into more re-blocks with `max_blocks: N` (default 1).

### Fail-open (unchanged)

Malformed YAML, missing fields, yq/jq errors, illegal decision-for-event,
unknown event → gate skipped, action allowed. Side-effect gates (condition
does work then exits 1, e.g. audit-log) keep working on every event.

### Input field compatibility

UserPromptSubmit prompt text is read as `.prompt // .user_input` (docs and
shipped versions disagree on the field name; support both).

## Components & file changes

| File | Change |
|---|---|
| `framework/lib/gates/runner.sh` | project-dir loading; per-event emitter functions; stdout capture for inject; stop-loop guard; per-event match key |
| `framework/lib/gates/validate.sh` + `skill/mcp_server.py` | dialect legality table (hook × decision); new optional field `max_blocks` |
| `framework/lib/gates/transcript-helpers.sh` (new) | jq helpers over `transcript_path` / `tool_calls`: `edited_code_files`, `ran_command_matching <regex>`, `tools_since_last <regex>` |
| `hooks/hooks.json` | register runner for all six events |
| `framework/lib/examples/` | 4 new flagship gates (below) |
| `framework/lib/tests/` | per-event emitter tests, precedence tests, dialect-legality tests, fixtures per event |
| `docs/SCHEMA_REFERENCE.md`, `docs/EXAMPLES.md`, `README.md`, create-gate prompt | dialect table + inject/stdout contract + scoping docs |
| `.claude-plugin/plugin.json`, `marketplace.json` | 1.2.0 |

## Flagship example gates

1. **`stop-run-tests.yaml`** — Stop / block. Condition (via transcript
   helpers): code files edited this turn AND no test command ran since →
   block with "run the tests before finishing".
2. **`prompt-router.yaml`** — UserPromptSubmit / inject. Greps prompt for a
   URL pattern, prints workflow instructions (generic template of the
   Asana/Sentry→RCA router).
3. **`boot-info.yaml`** — SessionStart / inject, matcher `startup`. Runs a
   project script, prints its output as boot context.
4. **`format-nudge.yaml`** — PostToolUse / inject on `Write|Edit`. Source file
   edited → inject "run the formatter before finishing".

## Testing

Extend the bash test suites (currently 10/10 runner + 3 suites green):

- Emitter shape per event (Stop block JSON, UserPromptSubmit block + inject,
  SessionStart inject-from-stdout, PostToolUse inject)
- Project gates beat global gates; alphabetical within dir; first-match-wins
  across the merged list
- Dialect legality: `deny` on a Stop gate → validator error, runner skip
- Stop-loop guard: second Stop with `stop_hook_active` → no block emitted
- All example gates pass `validate.sh`

## Migration & compatibility

Existing v1.1 gates are valid v1.2 gates (Pre/PostToolUse dialect unchanged;
`allow` on PostToolUse legacy-maps to `inject`-with-message=none, i.e. still a
no-op emit). After release: move `enforce-storage-get` + `no-docs-violation`
from `~/.claude/gates/` into the memory repo's `.claude/gates/` and delete
their hand-written path guards.
