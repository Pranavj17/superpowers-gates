# Task 1: Create Test Fixtures & Assert Helpers

**Goal:** Create mock hook inputs and test gates for use by later test suites.

**Files to create:**
- `lib/tests/fixtures/valid-gate.yaml` — Syntactically valid test gate
- `lib/tests/fixtures/invalid-gate.yaml` — Missing `decision` field (invalid)
- `lib/tests/fixtures/mock-preToolUse-bash.json` — Mock Bash tool input
- `lib/tests/fixtures/mock-preToolUse-write.json` — Mock Write tool input
- `lib/tests/fixtures/mock-destructive-db.json` — Mock destructive DB command input

**Project directory:** `/Users/pranav.j/Documents/claude-x`

**Global Constraints:**
- All file paths are absolute (`/Users/pranav.j/Documents/claude-x/...`)
- Gate YAML has required fields: name, description, hook, matcher, condition, decision, message
- Valid hook values: PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, SessionEnd
- Valid decision values: allow, deny, ask, transform
- Mock JSON inputs match Claude Code hook format: `{tool: "...", tool_input: {...}}`

**Exact values to use:**
- valid-gate.yaml: hook=PreToolUse, matcher=Bash, decision=ask, condition checks for "test" command
- invalid-gate.yaml: same as valid but missing `decision` field
- mock-preToolUse-bash.json: command="ls -la /tmp"
- mock-preToolUse-write.json: file_path="/OAUTH.md"
- mock-destructive-db.json: command="mix ecto.drop"

**Steps:**
1. Create lib/tests/fixtures/ directory
2. Write each .yaml and .json file with exact contents (shown in plan, Task 1)
3. Verify files exist with ls -la
4. Commit with message: "test(fixtures): add mock inputs and test gates"

**Report file:** `/Users/pranav.j/Documents/claude-x/.superpowers/sdd/task-1-report.md`

