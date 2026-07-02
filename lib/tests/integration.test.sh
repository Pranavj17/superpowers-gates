#!/bin/bash

# =============================================================================
# integration.test.sh — End-to-end integration test for hook gates framework
#
# Validates that runner.sh, validate.sh, and example gates work together
# =============================================================================

set -euo pipefail

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

    local gates_dir="lib/examples"
    local pass=true

    for gate in "$gates_dir"/*.yaml; do
        if ! bash lib/gates/validate.sh "$gate" > /dev/null 2>&1; then
            echo "✗ FAIL: Gate validation failed for $(basename $gate)"
            pass=false
        fi
    done

    if [ "$pass" = true ]; then
        echo "✓ PASS: All 3 example gates are valid YAML"
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
    cp lib/examples/*.yaml "$HOME/.claude/gates/"

    # Input: mix ecto.drop command
    local input='{"tool":"Bash","tool_input":{"command":"mix ecto.drop"}}'
    local output=$(echo "$input" | bash lib/gates/runner.sh PreToolUse 2>/dev/null || true)

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
    local input='{"tool":"Write","tool_input":{"file_path":"/OAUTH.md"}}'
    local output=$(echo "$input" | bash lib/gates/runner.sh PreToolUse 2>/dev/null || true)

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
    local input='{"tool":"Bash","tool_input":{"command":"ls -la /tmp"}}'
    local output=$(echo "$input" | bash lib/gates/runner.sh PreToolUse 2>/dev/null || true)

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

echo ""
echo "======================================================================="
echo "Test Results: $TESTS_PASSED/4 passed, $TESTS_FAILED failed"
echo "======================================================================="

# Exit with appropriate code
if [ $TESTS_FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
