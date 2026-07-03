#!/bin/bash

# =============================================================================
# integration.test.sh — End-to-end integration test for hook gates framework
#
# Validates that runner.sh, validate.sh, and example gates work together
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

# Test framework setup
TESTS_PASSED=0
TESTS_FAILED=0

# Helper: assert output contains string
assert_contains() {
    local output="$1"
    local expected="$2"
    if echo "$output" | grep -q "$expected"; then
        return 0
    else
        echo "FAIL: Expected '$expected' in output"
        echo "Got: $output"
        return 1
    fi
}

# Helper: assert output is empty
assert_empty() {
    local output="$1"
    if [ -z "$output" ]; then
        return 0
    else
        echo "FAIL: Expected empty output, got: $output"
        return 1
    fi
}

# Test 1: All example gates are valid
test_all_example_gates_valid() {
    echo "Test 1: All example gates are valid"

    local gates_dir="$LIB_DIR/examples"
    local pass=true

    for gate in "$gates_dir"/*.yaml; do
        if ! bash "$LIB_DIR/gates/validate.sh" "$gate" > /dev/null 2>&1; then
            echo "✗ FAIL: Gate validation failed for $(basename $gate)"
            pass=false
        fi
    done

    if [ "$pass" = true ]; then
        echo "✓ PASS: All $(ls "$gates_dir"/*.yaml | wc -l | tr -d ' ') example gates are valid YAML"
        ((TESTS_PASSED++))
        return 0
    else
        echo "✗ FAIL: One or more gates failed validation"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test 2: Rule 2 gate catches destructive DB commands
test_rule_2_blocks_destructive_db() {
    echo "Test 2: Rule 2 (no-destructive-db) blocks mix ecto.drop"

    # Set up test gates
    mkdir -p "$HOME/.claude/gates"
    cp "$LIB_DIR"/examples/*.yaml "$HOME/.claude/gates/"

    # Input: mix ecto.drop command
    local input='{"tool_name":"Bash","tool_input":{"command":"mix ecto.drop"}}'
    local output=$(echo "$input" | bash "$LIB_DIR/gates/runner.sh" PreToolUse 2>/dev/null || true)

    if assert_contains "$output" "permissionDecision.*ask"; then
        echo "✓ PASS: Rule 2 blocks destructive DB command with decision=ask"
        ((TESTS_PASSED++))
        return 0
    else
        echo "✗ FAIL: Rule 2 did not catch mix ecto.drop"
        echo "Output: $output"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test 3: Rule 4 gate catches root .md files
test_rule_4_blocks_root_md() {
    echo "Test 3: Rule 4 (no-docs-violation) blocks /OAUTH.md"

    # Input: Write to root .md file
    local input='{"tool_name":"Write","tool_input":{"file_path":"/OAUTH.md"}}'
    local output=$(echo "$input" | bash "$LIB_DIR/gates/runner.sh" PreToolUse 2>/dev/null || true)

    if assert_contains "$output" "permissionDecision.*deny"; then
        echo "✓ PASS: Rule 4 blocks root .md file with decision=deny"
        ((TESTS_PASSED++))
        return 0
    else
        echo "✗ FAIL: Rule 4 did not catch /OAUTH.md violation"
        echo "Output: $output"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test 4: Runner allows safe actions (fail-open)
test_runner_allows_safe_actions() {
    echo "Test 4: Runner allows safe actions (fail-open)"

    # Input: Safe bash command
    local input='{"tool_name":"Bash","tool_input":{"command":"ls -la /tmp"}}'
    local output=$(echo "$input" | bash "$LIB_DIR/gates/runner.sh" PreToolUse 2>/dev/null || true)

    if assert_empty "$output"; then
        echo "✓ PASS: No gates triggered, action allowed (fail-open)"
        ((TESTS_PASSED++))
        return 0
    else
        echo "✗ FAIL: Runner returned output for safe action"
        echo "Output: $output"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test 5: Flagship example gates each trigger and non-trigger correctly
test_flagship_examples() {
    echo "Test 5: Flagship example gates (stop-run-tests, prompt-router, boot-info, format-nudge)"

    local original_home="$HOME"
    local test_home
    test_home=$(mktemp -d)
    export HOME="$test_home"
    mkdir -p "$HOME/.claude/gates"
    cp "$LIB_DIR/examples/stop-run-tests.yaml" \
       "$LIB_DIR/examples/prompt-router.yaml" \
       "$LIB_DIR/examples/boot-info.yaml" \
       "$LIB_DIR/examples/format-nudge.yaml" \
       "$HOME/.claude/gates/"

    local pass=true
    local out

    # --- stop-run-tests (Stop): since-scoped — block only if a code edit
    # happened AFTER the last test command (or no test ever ran) ---
    local sid_trigger="flagship-stop-trigger"
    local sid_notrigger="flagship-stop-notrigger"
    local sid_edit_then_test="flagship-stop-edit-then-test"
    rm -f "${TMPDIR:-/tmp}/gates-stop-${sid_trigger}-stop-run-tests"
    rm -f "${TMPDIR:-/tmp}/gates-stop-${sid_notrigger}-stop-run-tests"
    rm -f "${TMPDIR:-/tmp}/gates-stop-${sid_edit_then_test}-stop-run-tests"

    # test-then-edit: mock-transcript.jsonl ends with an Edit of other.ex
    # AFTER its "npm test" line => block (edit since last test).
    local stop_trigger_input
    stop_trigger_input=$(jq -n --arg tp "$FIXTURES_DIR/mock-transcript.jsonl" --arg sid "$sid_trigger" \
        '{session_id: $sid, transcript_path: $tp, stop_hook_active: false}')
    out=$(echo "$stop_trigger_input" | bash "$LIB_DIR/gates/runner.sh" Stop 2>/dev/null || true)
    assert_contains "$out" '"decision":"block"' || pass=false

    # no transcript at all => allow (nothing to scope).
    local stop_notrigger_input
    stop_notrigger_input=$(jq -n --arg sid "$sid_notrigger" '{session_id: $sid, stop_hook_active: false}')
    out=$(echo "$stop_notrigger_input" | bash "$LIB_DIR/gates/runner.sh" Stop 2>/dev/null || true)
    assert_empty "$out" || pass=false

    # edit-then-test: mock-transcript-edit-then-test.jsonl ends with "mix
    # test" AFTER the Edit => no block (tests already covered the edit).
    local stop_edit_then_test_input
    stop_edit_then_test_input=$(jq -n --arg tp "$FIXTURES_DIR/mock-transcript-edit-then-test.jsonl" --arg sid "$sid_edit_then_test" \
        '{session_id: $sid, transcript_path: $tp, stop_hook_active: false}')
    out=$(echo "$stop_edit_then_test_input" | bash "$LIB_DIR/gates/runner.sh" Stop 2>/dev/null || true)
    assert_empty "$out" || pass=false

    # REGRESSION: write-with-pytest: Write tool contains "pytest" in content,
    # but no actual Bash test command ran. Should BLOCK (no tests ran).
    local sid_write_pytest="flagship-stop-write-pytest"
    local stop_write_pytest_input
    stop_write_pytest_input=$(jq -n --arg tp "$FIXTURES_DIR/mock-transcript-write-with-pytest.jsonl" --arg sid "$sid_write_pytest" \
        '{session_id: $sid, transcript_path: $tp, stop_hook_active: false}')
    out=$(echo "$stop_write_pytest_input" | bash "$LIB_DIR/gates/runner.sh" Stop 2>/dev/null || true)
    assert_contains "$out" '"decision":"block"' || pass=false

    # --- prompt-router (UserPromptSubmit): tracker URL => inject ---
    local router_trigger_input='{"prompt":"please handle https://app.asana.com/0/123456789/987654321 today"}'
    out=$(echo "$router_trigger_input" | bash "$LIB_DIR/gates/runner.sh" UserPromptSubmit 2>/dev/null || true)
    assert_contains "$out" "additionalContext" || pass=false
    assert_contains "$out" "WORKFLOW TRIGGER" || pass=false

    local router_notrigger_input='{"prompt":"hello, just chatting"}'
    out=$(echo "$router_notrigger_input" | bash "$LIB_DIR/gates/runner.sh" UserPromptSubmit 2>/dev/null || true)
    assert_empty "$out" || pass=false

    # --- boot-info (SessionStart): .claude/BOOT.md present in cwd => inject ---
    local proj_dir
    proj_dir=$(mktemp -d)
    mkdir -p "$proj_dir/.claude"
    echo "PROJECT BOOT CONTEXT" > "$proj_dir/.claude/BOOT.md"

    local boot_trigger_input
    boot_trigger_input=$(jq -n --arg cwd "$proj_dir" '{source: "startup", cwd: $cwd}')
    out=$(echo "$boot_trigger_input" | bash "$LIB_DIR/gates/runner.sh" SessionStart 2>/dev/null || true)
    assert_contains "$out" "additionalContext" || pass=false
    assert_contains "$out" "PROJECT BOOT CONTEXT" || pass=false

    local boot_notrigger_input='{"source":"startup"}'
    out=$(echo "$boot_notrigger_input" | bash "$LIB_DIR/gates/runner.sh" SessionStart 2>/dev/null || true)
    assert_empty "$out" || pass=false
    rm -rf "$proj_dir"

    # --- format-nudge (PostToolUse): Edit/Write of .ex/.exs => inject ---
    local nudge_trigger_input='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.ex"}}'
    out=$(echo "$nudge_trigger_input" | bash "$LIB_DIR/gates/runner.sh" PostToolUse 2>/dev/null || true)
    assert_contains "$out" "additionalContext" || pass=false
    assert_contains "$out" "mix format" || pass=false

    local nudge_notrigger_input='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt"}}'
    out=$(echo "$nudge_notrigger_input" | bash "$LIB_DIR/gates/runner.sh" PostToolUse 2>/dev/null || true)
    assert_empty "$out" || pass=false

    # Restore real HOME
    rm -rf "$test_home"
    export HOME="$original_home"

    if [ "$pass" = true ]; then
        echo "✓ PASS: All 4 flagship example gates trigger and non-trigger correctly"
        ((TESTS_PASSED++))
        return 0
    else
        echo "✗ FAIL: One or more flagship example gate assertions failed"
        ((TESTS_FAILED++))
        return 1
    fi
}

# =============================================================================
# Run all tests
# =============================================================================

echo "======================================================================="
echo "Running integration.test.sh test suite"
echo "======================================================================="
echo ""

test_all_example_gates_valid || true
test_rule_2_blocks_destructive_db || true
test_rule_4_blocks_root_md || true
test_runner_allows_safe_actions || true
test_flagship_examples || true

echo ""
echo "======================================================================="
echo "Test Results: $TESTS_PASSED/5 passed, $TESTS_FAILED failed"
echo "======================================================================="

# Exit with appropriate code
if [ $TESTS_FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
