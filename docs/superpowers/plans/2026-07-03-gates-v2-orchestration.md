# Gates v2 — Hook Control Plane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the gates framework to six hook events with per-event decision dialects, per-repo gate loading, condition-stdout-as-payload for inject gates, and a stop-loop guard.

**Architecture:** One runner (`runner.sh`) loads project gates then global gates, picks the matcher key per event, enforces a decision-legality table, and emits the correct JSON dialect per event. Validation legality lives once in `validate.sh` (the MCP server shells out to it). Spec: `docs/superpowers/specs/2026-07-03-gates-v2-orchestration-design.md`.

**Tech Stack:** bash + yq + jq; bash test suites in `framework/lib/tests/`.

## Global Constraints

- Repo: `/Users/pranav.j/.claude/plugins/marketplaces/superpowers-gates` — run all commands from `framework/`
- Fail-open everywhere: any yq/jq/parse error or illegal combination → skip gate, exit 0
- First triggered gate wins; evaluation order = project dir (alphabetical) then global dir (alphabetical)
- Existing v1.1 gates must stay valid and behave identically (PreToolUse ask/deny/allow; PostToolUse allow = legacy no-op; side-effect exit-1 conditions untouched)
- All 4 test suites must pass after every task: `for t in lib/tests/*.test.sh; do bash "$t"; done`
- Conditions receive the hook input JSON on stdin exactly once
- Commit after each task with a conventional-commit message + `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: Runner core v2 — two-directory loading, per-event match key, dialect emitters

This is one task because the runner is a single 90-line script; splitting it would make each sub-task rewrite the same loop.

**Files:**
- Modify: `framework/lib/gates/runner.sh` (full replacement below)
- Test: `framework/lib/tests/gate-runner.test.sh` (append tests + register in `main()`)

**Interfaces:**
- Produces: runner emits per-event JSON dialects (exact shapes in code below); exports `GATES_LIB_DIR` env var to conditions (Task 6's helpers rely on it); reads optional `max_blocks` gate field (Task 4 tests it; Task 5 validates it)
- Consumes: nothing new

- [ ] **Step 1: Write failing tests** — append before the `# Main:` section of `framework/lib/tests/gate-runner.test.sh`:

```bash
# Helper: run runner with a custom project cwd embedded in input JSON
make_input_with_cwd() { # $1=tool_name $2=cwd
    printf '{"tool_name":"%s","cwd":"%s","tool_input":{"command":"ls"}}' "$1" "$2"
}

test_project_gates_load_and_win() {
    setup_test_environment
    local proj_dir
    proj_dir=$(mktemp -d)
    mkdir -p "$proj_dir/.claude/gates"
    # Global gate allows; project gate denies. Project must win.
    create_test_gate "z-global" "PreToolUse" "Bash" "true" "ask" "Global gate"
    cat > "$proj_dir/.claude/gates/a-project.yaml" <<'EOF'
name: "a-project"
description: "project gate"
hook: "PreToolUse"
matcher: "Bash"
condition: |
  true
decision: "deny"
message: "Project gate wins"
EOF
    local result
    result=$(make_input_with_cwd "Bash" "$proj_dir" | bash "$RUNNER_PATH" "PreToolUse" || echo "")
    assert_contains "test_project_gates_load_and_win" "$result" "Project gate wins"
    rm -rf "$proj_dir"
    teardown_test_environment
}

test_stop_block_dialect() {
    setup_test_environment
    create_test_gate "stop-gate" "Stop" "*" "true" "block" "Finish the tests first"
    local result
    result=$(printf '{"session_id":"s1","stop_hook_active":false}' | bash "$RUNNER_PATH" "Stop" || echo "")
    assert_contains "test_stop_block_dialect: decision block" "$result" '"decision":"block"'
    assert_contains "test_stop_block_dialect: reason" "$result" "Finish the tests first"
    teardown_test_environment
}

test_prompt_inject_uses_condition_stdout() {
    setup_test_environment
    create_test_gate "router" "UserPromptSubmit" "*" "echo INJECTED-WORKFLOW" "inject" "fallback msg"
    local result
    result=$(printf '{"prompt":"debug this"}' | bash "$RUNNER_PATH" "UserPromptSubmit" || echo "")
    assert_contains "test_prompt_inject: additionalContext" "$result" '"additionalContext":"INJECTED-WORKFLOW'
    teardown_test_environment
}

test_sessionstart_matcher_uses_source() {
    setup_test_environment
    create_test_gate "boot" "SessionStart" "startup" "echo BOOTCTX" "inject" "unused"
    local hit miss
    hit=$(printf '{"source":"startup"}' | bash "$RUNNER_PATH" "SessionStart" || echo "")
    miss=$(printf '{"source":"resume"}' | bash "$RUNNER_PATH" "SessionStart" || echo "")
    assert_contains "test_sessionstart_matcher: startup matches" "$hit" "BOOTCTX"
    assert_empty "test_sessionstart_matcher: resume skipped" "$miss"
    teardown_test_environment
}

test_illegal_decision_for_event_skipped() {
    setup_test_environment
    create_test_gate "bad-stop" "Stop" "*" "true" "deny" "should never fire"
    local result
    result=$(printf '{"session_id":"s1"}' | bash "$RUNNER_PATH" "Stop" || echo "")
    assert_empty "test_illegal_decision_for_event_skipped" "$result"
    teardown_test_environment
}
```

Register in `main()` after `test_star_matcher_matches_all_tools || true`:

```bash
    test_project_gates_load_and_win || true
    test_stop_block_dialect || true
    test_prompt_inject_uses_condition_stdout || true
    test_sessionstart_matcher_uses_source || true
    test_illegal_decision_for_event_skipped || true
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `cd framework && bash lib/tests/gate-runner.test.sh`
Expected: 10 old assertions PASS; the 5 new tests FAIL (runner emits `permissionDecision` shape for every event and never loads project dirs).

- [ ] **Step 3: Replace `framework/lib/gates/runner.sh` entirely with:**

```bash
#!/bin/bash

# =============================================================================
# runner.sh — Gate executor (v2: hook control plane)
#
# Loads gates from <cwd>/.claude/gates (project) then ~/.claude/gates
# (global), evaluates them against the hook event, and emits the correct
# decision dialect per event. First triggered gate wins. Fail-open: any
# error skips the gate.
#
# Usage: echo '<hook input JSON>' | runner.sh <HookEvent>
# =============================================================================

set -euo pipefail

HOOK_EVENT="$1"
INPUT_JSON=$(cat)

# Exported so gate conditions can source transcript-helpers.sh etc.
GATES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GATES_LIB_DIR

GLOBAL_GATES_DIR="${HOME}/.claude/gates"
PROJECT_CWD=$(echo "$INPUT_JSON" | jq -r '.cwd // empty' 2>/dev/null || echo "")

# Ordered gate list: project gates first, then global (alphabetical each)
gate_files=()
if [ -n "$PROJECT_CWD" ] && [ -d "$PROJECT_CWD/.claude/gates" ] \
   && [ "$PROJECT_CWD/.claude/gates" != "$GLOBAL_GATES_DIR" ]; then
    while IFS= read -r f; do gate_files+=("$f"); done \
        < <(find "$PROJECT_CWD/.claude/gates" -maxdepth 1 -name "*.yaml" -type f | sort)
fi
if [ -d "$GLOBAL_GATES_DIR" ]; then
    while IFS= read -r f; do gate_files+=("$f"); done \
        < <(find "$GLOBAL_GATES_DIR" -maxdepth 1 -name "*.yaml" -type f | sort)
fi
[ "${#gate_files[@]}" -eq 0 ] && exit 0

# json_str <string> — JSON-encode a string (includes surrounding quotes)
json_str() { jq -Rn --arg s "$1" '$s'; }

# The input field a gate matcher is tested against, per event.
# "__any__" = matchers don't apply to this event (gate always matches).
# Empty = event unsupported → allow everything.
match_key() {
    case "$HOOK_EVENT" in
        PreToolUse|PostToolUse) echo "$INPUT_JSON" | jq -r '.tool_name // .tool // empty' 2>/dev/null || echo "" ;;
        SessionStart)           echo "$INPUT_JSON" | jq -r '.source // empty' 2>/dev/null || echo "" ;;
        SubagentStop)           echo "$INPUT_JSON" | jq -r '.agent_type // empty' 2>/dev/null || echo "" ;;
        Stop|UserPromptSubmit)  echo "__any__" ;;
        *)                      echo "" ;;
    esac
}

# decision_legal <event> <decision> — the dialect table
decision_legal() {
    case "$1:$2" in
        PreToolUse:ask|PreToolUse:deny|PreToolUse:allow) return 0 ;;
        PostToolUse:block|PostToolUse:inject|PostToolUse:allow) return 0 ;;
        UserPromptSubmit:block|UserPromptSubmit:inject) return 0 ;;
        SessionStart:inject) return 0 ;;
        Stop:block|SubagentStop:block) return 0 ;;
        *) return 1 ;;
    esac
}

tool_key=$(match_key)
[ -z "$tool_key" ] && exit 0

for gate_file in "${gate_files[@]}"; do
    gate_name=$(yq eval '.name' "$gate_file" 2>/dev/null || echo "")
    gate_hook=$(yq eval '.hook' "$gate_file" 2>/dev/null || echo "")
    gate_matcher=$(yq eval '.matcher' "$gate_file" 2>/dev/null || echo "")
    gate_condition=$(yq eval '.condition' "$gate_file" 2>/dev/null || echo "")
    gate_decision=$(yq eval '.decision' "$gate_file" 2>/dev/null || echo "")
    gate_message=$(yq eval '.message' "$gate_file" 2>/dev/null || echo "")

    if [ -z "$gate_hook" ] || [ -z "$gate_matcher" ] || [ -z "$gate_condition" ] \
       || [ -z "$gate_decision" ] || [ -z "$gate_message" ]; then
        continue
    fi
    [ "$gate_hook" != "$HOOK_EVENT" ] && continue
    decision_legal "$HOOK_EVENT" "$gate_decision" || continue

    if [ "$tool_key" != "__any__" ]; then
        m="$gate_matcher"
        [ "$m" = "*" ] && m=".*"    # documented all-tools matcher; bare * is invalid ERE
        echo "$tool_key" | grep -qE "^($m)$" || continue
    fi

    # Stop-loop guard: a blocked Stop re-fires with stop_hook_active=true.
    # Default: one block per turn (max_blocks: 1). Counter resets on the
    # first (unblocked) Stop of each turn.
    count_file=""
    if [ "$HOOK_EVENT" = "Stop" ] || [ "$HOOK_EVENT" = "SubagentStop" ]; then
        stop_active=$(echo "$INPUT_JSON" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
        max_blocks=$(yq eval '.max_blocks // 1' "$gate_file" 2>/dev/null || echo "1")
        case "$max_blocks" in (*[!0-9]*|"") max_blocks=1 ;; esac
        session_id=$(echo "$INPUT_JSON" | jq -r '.session_id // "nosession"' 2>/dev/null || echo "nosession")
        count_file="${TMPDIR:-/tmp}/gates-stop-${session_id}-${gate_name}"
        if [ "$stop_active" = "true" ]; then
            count=$(cat "$count_file" 2>/dev/null || echo "0")
            case "$count" in (*[!0-9]*|"") count=0 ;; esac
            [ "$count" -ge "$max_blocks" ] && continue
        else
            echo "0" > "$count_file" 2>/dev/null || true
        fi
    fi

    # Evaluate condition. exit 0 = triggered; stdout = payload for inject.
    if cond_out=$(echo "$INPUT_JSON" | bash -c "$gate_condition" 2>/dev/null); then
        case "$HOOK_EVENT:$gate_decision" in
            PreToolUse:*)
                echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"$gate_decision\",\"permissionDecisionReason\":$(json_str "$gate_message")}}"
                ;;
            Stop:block|SubagentStop:block)
                count=$(cat "$count_file" 2>/dev/null || echo "0")
                case "$count" in (*[!0-9]*|"") count=0 ;; esac
                echo $((count + 1)) > "$count_file" 2>/dev/null || true
                echo "{\"decision\":\"block\",\"reason\":$(json_str "$gate_message")}"
                ;;
            *:block)
                echo "{\"decision\":\"block\",\"reason\":$(json_str "$gate_message")}"
                ;;
            *:inject)
                ctx="${cond_out:-$gate_message}"
                echo "{\"hookSpecificOutput\":{\"hookEventName\":\"$HOOK_EVENT\",\"additionalContext\":$(json_str "$ctx")}}"
                ;;
            PostToolUse:allow)
                : ;;   # legacy v1 no-op decision
        esac
        exit 0
    fi
done
exit 0
```

- [ ] **Step 4: Run all runner tests**

Run: `cd framework && bash lib/tests/gate-runner.test.sh`
Expected: all assertions PASS (old 10 + new). If `test_rule_*` fail, the PreToolUse emitter shape regressed — it must stay byte-compatible with v1.1 (`"permissionDecision":"ask"` etc.).

- [ ] **Step 5: Run the other three suites**

Run: `cd framework && for t in lib/tests/helpers.test.sh lib/tests/validate.test.sh lib/tests/integration.test.sh; do bash "$t" || echo "FAIL $t"; done`
Expected: no FAIL lines.

- [ ] **Step 6: Commit**

```bash
git add framework/lib/gates/runner.sh framework/lib/tests/gate-runner.test.sh
git commit -m "feat(runner): v2 control plane — project gates, per-event matchers and dialects

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Stop-loop guard behavior tests

The guard code shipped in Task 1's runner; this task pins its behavior with tests (it's the most dangerous failure mode — an infinite Stop loop).

**Files:**
- Test: `framework/lib/tests/gate-runner.test.sh` (append + register)

**Interfaces:**
- Consumes: runner's `stop_hook_active` / `max_blocks` / counter-file logic from Task 1 (counter file `${TMPDIR:-/tmp}/gates-stop-<session_id>-<gate_name>`)

- [ ] **Step 1: Write the tests**

```bash
test_stop_guard_allows_second_attempt() {
    setup_test_environment
    create_test_gate "stop-dod" "Stop" "*" "true" "block" "keep going"
    rm -f "${TMPDIR:-/tmp}/gates-stop-guardtest-stop-dod"
    local first second
    first=$(printf '{"session_id":"guardtest","stop_hook_active":false}' | bash "$RUNNER_PATH" "Stop" || echo "")
    second=$(printf '{"session_id":"guardtest","stop_hook_active":true}' | bash "$RUNNER_PATH" "Stop" || echo "")
    assert_contains "test_stop_guard: first attempt blocked" "$first" '"decision":"block"'
    assert_empty "test_stop_guard: second attempt allowed" "$second"
    teardown_test_environment
}

test_stop_guard_max_blocks_two() {
    setup_test_environment
    cat > "$HOME/.claude/gates/stop-nag.yaml" <<'EOF'
name: "stop-nag"
description: "blocks twice"
hook: "Stop"
matcher: "*"
condition: |
  true
decision: "block"
message: "not done yet"
max_blocks: 2
EOF
    rm -f "${TMPDIR:-/tmp}/gates-stop-nagtest-stop-nag"
    local a b c
    a=$(printf '{"session_id":"nagtest","stop_hook_active":false}' | bash "$RUNNER_PATH" "Stop" || echo "")
    b=$(printf '{"session_id":"nagtest","stop_hook_active":true}' | bash "$RUNNER_PATH" "Stop" || echo "")
    c=$(printf '{"session_id":"nagtest","stop_hook_active":true}' | bash "$RUNNER_PATH" "Stop" || echo "")
    assert_contains "test_stop_guard_max2: 1st blocked" "$a" '"decision":"block"'
    assert_contains "test_stop_guard_max2: 2nd blocked" "$b" '"decision":"block"'
    assert_empty "test_stop_guard_max2: 3rd allowed" "$c"
    teardown_test_environment
}
```

Register both in `main()`.

- [ ] **Step 2: Run** — `cd framework && bash lib/tests/gate-runner.test.sh` — Expected: all PASS (guard already implemented; any FAIL is a real guard bug — fix runner, not tests).

- [ ] **Step 3: Verify the real field name.** Run a live check against Claude Code docs/output: `grep -r "stop_hook_active" ~/.claude/projects/*/  2>/dev/null | head -3` (transcripts record hook inputs). If the field differs, update the runner jq path and this test.

- [ ] **Step 4: Commit**

```bash
git add framework/lib/tests/gate-runner.test.sh
git commit -m "test(runner): stop-loop guard — default single block, max_blocks opt-in

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Validator dialect legality (validate.sh)

**Files:**
- Modify: `framework/lib/gates/validate.sh:12-14` (enums) and `:101-107` (decision check)
- Test: `framework/lib/tests/validate.test.sh` (append)

**Interfaces:**
- Produces: `validate_gate` accepts the six v2 hooks, rejects illegal hook×decision combos with `ERROR: Decision '<d>' is not valid for hook '<h>' …`, accepts optional integer `max_blocks`
- Consumes: dialect table identical to runner's `decision_legal` (Task 1)

- [ ] **Step 1: Write failing tests** — append to `framework/lib/tests/validate.test.sh` (follow its existing helper/assert conventions; check the file's helpers before writing):

```bash
test_stop_block_gate_valid() {
    local f=$(mktemp -t gate-XXXX.yaml)
    cat > "$f" <<'EOF'
name: "stop-ok"
description: "stop gate"
hook: "Stop"
matcher: "*"
condition: |
  true
decision: "block"
message: "keep going"
max_blocks: 2
EOF
    assert_exit_0 "test_stop_block_gate_valid" "validate_gate '$f'"
    rm -f "$f"
}

test_deny_on_stop_invalid() {
    local f=$(mktemp -t gate-XXXX.yaml)
    cat > "$f" <<'EOF'
name: "stop-bad"
description: "illegal decision"
hook: "Stop"
matcher: "*"
condition: |
  true
decision: "deny"
message: "nope"
EOF
    assert_exit_nonzero "test_deny_on_stop_invalid" "validate_gate '$f'"
    rm -f "$f"
}

test_inject_on_userpromptsubmit_valid() {
    local f=$(mktemp -t gate-XXXX.yaml)
    cat > "$f" <<'EOF'
name: "router-ok"
description: "prompt router"
hook: "UserPromptSubmit"
matcher: "*"
condition: |
  echo ctx
decision: "inject"
message: "fallback"
EOF
    assert_exit_0 "test_inject_on_userpromptsubmit_valid" "validate_gate '$f'"
    rm -f "$f"
}
```

- [ ] **Step 2: Run to verify failure** — `cd framework && bash lib/tests/validate.test.sh` — Expected: new tests FAIL (`block`/`inject` not in `VALID_DECISIONS`).

- [ ] **Step 3: Implement.** In `validate.sh` replace lines 12-14 with:

```bash
readonly VALID_HOOKS=("PreToolUse" "PostToolUse" "UserPromptSubmit" "SessionStart" "Stop" "SubagentStop" "SessionEnd")
readonly VALID_DECISIONS=("allow" "deny" "ask" "block" "inject" "transform")
readonly VALID_SEVERITIES=("low" "medium" "high" "critical")
```

After the existing decision-enum check (line ~107), add the legality check and `max_blocks` check:

```bash
    # Step 5b: decision must be legal for this hook (dialect table — keep in
    # sync with runner.sh decision_legal)
    case "$hook:$decision" in
        PreToolUse:ask|PreToolUse:deny|PreToolUse:allow) ;;
        PostToolUse:block|PostToolUse:inject|PostToolUse:allow) ;;
        UserPromptSubmit:block|UserPromptSubmit:inject) ;;
        SessionStart:inject) ;;
        Stop:block|SubagentStop:block) ;;
        SessionEnd:*)
            echo "ERROR: SessionEnd gates are side-effect only; no decision applies in $filename"
            return 1 ;;
        *)
            echo "ERROR: Decision '$decision' is not valid for hook '$hook' in $filename"
            return 1 ;;
    esac

    # Step 5c: optional max_blocks must be a positive integer (Stop/SubagentStop only)
    local max_blocks
    max_blocks=$(yq -r '.max_blocks // ""' "$gate_file" 2>/dev/null) || max_blocks=""
    if [[ -n "$max_blocks" ]] && [[ "$max_blocks" != "null" ]]; then
        if ! [[ "$max_blocks" =~ ^[1-9][0-9]*$ ]]; then
            echo "ERROR: max_blocks must be a positive integer in $filename"
            return 1
        fi
    fi
```

Note: existing example `audit-log.yaml` is `PostToolUse` + `allow`? No — it is `decision: "allow"` with hook `PostToolUse`: legal per table. `no-destructive-db` (PreToolUse:ask) and `no-docs-violation` (PreToolUse:deny) unchanged.

- [ ] **Step 4: Run validate + integration suites** — `cd framework && bash lib/tests/validate.test.sh && bash lib/tests/integration.test.sh` — Expected: PASS. Also run `bash lib/gates/validate.sh lib/examples/*.yaml` — every example prints `✓ … valid`.

- [ ] **Step 5: Commit**

```bash
git add framework/lib/gates/validate.sh framework/lib/tests/validate.test.sh
git commit -m "feat(validate): v2 hooks + per-event decision legality + max_blocks

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: transcript-helpers.sh

**Files:**
- Create: `framework/lib/gates/transcript-helpers.sh`
- Create: `framework/lib/tests/fixtures/mock-transcript.jsonl`
- Test: `framework/lib/tests/helpers.test.sh` (append)

**Interfaces:**
- Produces: `th_tool_entries <transcript_path>` (prints `tool_name<TAB>compact-input-json` per tool call), `th_edited_files_matching <transcript_path> <ere>` (prints matches, exit 0 if any), `th_ran_command_matching <transcript_path> <ere>` (exit 0 if a Bash command matched). Sourced by conditions via `$GATES_LIB_DIR/transcript-helpers.sh` (exported by runner, Task 1).
- Consumes: `GATES_LIB_DIR` from Task 1.

- [ ] **Step 1: Inspect a real transcript to pin jq paths.** Run: `ls -t ~/.claude/projects/*/*.jsonl 2>/dev/null | head -1 | xargs -I{} sh -c 'jq -c "select(.type==\"assistant\") | .message.content[]? | select(.type==\"tool_use\") | {name, input}" {} 2>/dev/null | head -3'`. If output shows tool calls, the paths below are right; otherwise adapt BOTH the helper jq and the fixture to the real shape and note the change in the commit message.

- [ ] **Step 2: Create the fixture** `framework/lib/tests/fixtures/mock-transcript.jsonl` (one JSON per line, real-shape):

```json
{"type":"user","message":{"content":"please fix the bug"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/repo/lib/memory/storage.ex","old_string":"a","new_string":"b"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"mix compile"}}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/repo/notes.txt","content":"x"}}]}}
```

- [ ] **Step 3: Write failing tests** — append to `helpers.test.sh` (using its assert helpers):

```bash
test_th_tool_entries_lists_tools() {
    source "$GATES_DIR/transcript-helpers.sh"
    local out
    out=$(th_tool_entries "$FIXTURES_DIR/mock-transcript.jsonl")
    assert_contains "th_tool_entries: Edit listed" "$out" "Edit"
    assert_contains "th_tool_entries: Bash listed" "$out" "mix compile"
}

test_th_edited_files_matching() {
    source "$GATES_DIR/transcript-helpers.sh"
    assert_exit_0 "th_edited_files_matching: .ex edited" \
        "th_edited_files_matching '$FIXTURES_DIR/mock-transcript.jsonl' '\\.ex\"' >/dev/null"
    assert_exit_nonzero "th_edited_files_matching: no .py edited" \
        "th_edited_files_matching '$FIXTURES_DIR/mock-transcript.jsonl' '\\.py\"' >/dev/null"
}

test_th_ran_command_matching() {
    source "$GATES_DIR/transcript-helpers.sh"
    assert_exit_0 "th_ran_command_matching: mix compile ran" \
        "th_ran_command_matching '$FIXTURES_DIR/mock-transcript.jsonl' 'mix compile'"
    assert_exit_nonzero "th_ran_command_matching: mix test did not run" \
        "th_ran_command_matching '$FIXTURES_DIR/mock-transcript.jsonl' 'mix test'"
}
```

- [ ] **Step 4: Run to verify failure** — `bash lib/tests/helpers.test.sh` — Expected: FAIL (file doesn't exist).

- [ ] **Step 5: Create `framework/lib/gates/transcript-helpers.sh`:**

```bash
#!/bin/bash
# transcript-helpers.sh — jq helpers over the session transcript for gate
# conditions. Source via: source "$GATES_LIB_DIR/transcript-helpers.sh"
# All helpers fail-open: missing/garbled transcript → empty output, exit 1.

# th_tool_entries <transcript_path>
# Prints one line per tool call: "<tool_name>\t<compact input JSON>"
th_tool_entries() {
    jq -r 'select(.type=="assistant") | .message.content[]?
           | select(.type=="tool_use")
           | [.name, (.input|tostring)] | @tsv' "$1" 2>/dev/null
}

# th_edited_files_matching <transcript_path> <ere>
# Prints Edit/Write input lines whose JSON matches <ere>; exit 0 if any.
th_edited_files_matching() {
    th_tool_entries "$1" | awk -F'\t' '$1=="Edit"||$1=="Write"{print $2}' \
        | grep -E "$2"
}

# th_ran_command_matching <transcript_path> <ere>
# Exit 0 if any Bash command in the transcript matches <ere>.
th_ran_command_matching() {
    th_tool_entries "$1" | awk -F'\t' '$1=="Bash"{print $2}' | grep -qE "$2"
}
```

- [ ] **Step 6: Run** — `bash lib/tests/helpers.test.sh` — Expected: PASS. (If `GATES_DIR`/`FIXTURES_DIR` variable names differ in this suite, use the suite's actual path variables.)

- [ ] **Step 7: Commit**

```bash
git add framework/lib/gates/transcript-helpers.sh framework/lib/tests/fixtures/mock-transcript.jsonl framework/lib/tests/helpers.test.sh
git commit -m "feat(helpers): transcript jq helpers for stateful gate conditions

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Flagship example gates

**Files:**
- Create: `framework/lib/examples/stop-run-tests.yaml`
- Create: `framework/lib/examples/prompt-router.yaml`
- Create: `framework/lib/examples/boot-info.yaml`
- Create: `framework/lib/examples/format-nudge.yaml`
- Test: `framework/lib/tests/integration.test.sh` (ensure it validates all examples; if it already globs `lib/examples/*.yaml`, no change needed — verify)

**Interfaces:**
- Consumes: dialects (Task 1), validator legality (Task 3), transcript helpers (Task 4)

- [ ] **Step 1: `stop-run-tests.yaml`**

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

- [ ] **Step 2: `prompt-router.yaml`**

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

- [ ] **Step 3: `boot-info.yaml`**

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

- [ ] **Step 4: `format-nudge.yaml`**

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

- [ ] **Step 5: Validate all examples + end-to-end smoke each one through the runner:**

```bash
cd framework
bash lib/gates/validate.sh lib/examples/*.yaml
# Stop gate: no transcript → must NOT trigger
printf '{"session_id":"x"}' | bash lib/gates/runner.sh Stop   # expect empty output
# Router: (copy prompt-router.yaml into a temp HOME gates dir, echo an asana URL prompt, expect additionalContext)
```

Write these smokes as a new test `test_flagship_examples` in `integration.test.sh` following its conventions: copy each example into the suite's temp gates dir, feed a triggering and a non-triggering input, assert on output.

- [ ] **Step 6: Run** — `bash lib/tests/integration.test.sh` — Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add framework/lib/examples/ framework/lib/tests/integration.test.sh
git commit -m "feat(examples): flagship orchestration gates — stop-run-tests, prompt-router, boot-info, format-nudge

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Registration, docs, version 1.2.0

**Files:**
- Modify: `hooks/hooks.json` (6 events)
- Modify: `docs/SCHEMA_REFERENCE.md` (dialect table), `README.md` (control-plane overview + scoping), `docs/EXAMPLES.md` (4 new examples)
- Modify: `skill/mcp_server.py` create-gate prompt (dialect table + inject/stdout contract)
- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (`1.2.0`)

**Interfaces:**
- Consumes: everything above. No new interfaces.

- [ ] **Step 1: Replace `hooks/hooks.json` hooks object** so each of the six events runs `bash "${CLAUDE_PLUGIN_ROOT}/framework/lib/gates/runner.sh" <Event>` (same shape as the existing two entries; statusMessage "Checking gates..."). Events: PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, Stop, SubagentStop.

- [ ] **Step 2: SCHEMA_REFERENCE.md** — replace the `hook`/`decision` sections with the dialect table from the spec (copy the table verbatim from `docs/superpowers/specs/2026-07-03-gates-v2-orchestration-design.md` §Decision dialects), document `max_blocks`, the inject/stdout contract, and gate loading order (project `.claude/gates/` then `~/.claude/gates/`).

- [ ] **Step 3: create-gate prompt in `skill/mcp_server.py`** — in the "What We'll Build" list update items 3 (hook: six events) and 6 (decision: per-event, with the table condensed to one line per event); add a fourth gotcha: "`inject` gates: whatever the condition prints on exit 0 becomes the injected context."

- [ ] **Step 4: Bump versions** — `"version": "1.2.0"` in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.

- [ ] **Step 5: Full verification**

```bash
cd framework && for t in lib/tests/*.test.sh; do bash "$t" || echo "SUITE FAIL: $t"; done
jq -e '.hooks | keys | length == 6' ../hooks/hooks.json
bash lib/gates/validate.sh lib/examples/*.yaml
```

Expected: no `SUITE FAIL`, `true`, all `✓ valid`.

- [ ] **Step 6: Commit**

```bash
git add hooks/hooks.json docs/ README.md skill/mcp_server.py .claude-plugin/
git commit -m "feat(plugin): register 6-event control plane, docs, v1.2.0

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Post-plan (not tasks): push to origin, `claude plugin marketplace update superpowers-gates`, restart session, migrate `enforce-storage-get` + `no-docs-violation` into the memory repo's `.claude/gates/` and drop their path guards.
