#!/bin/bash

# =============================================================================
# gate-runner.test.sh — Unit tests for lib/gates/runner.sh
#
# This test suite validates the gate executor before implementation (TDD).
# Tests will fail until runner.sh is created in Task 5.
#
# Test gates are created in a temporary directory for isolation.
# Each test can define its own set of gates via test fixtures.
# =============================================================================

set -euo pipefail

# Get absolute paths for consistent behavior
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GATES_DIR="$PROJECT_ROOT/lib/gates"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
RUNNER_PATH="$GATES_DIR/runner.sh"

# Test environment
TEMP_GATES_DIR=""
TEST_HOME=""

# =============================================================================
# Test Framework: Setup, Teardown, and Assert Helpers
# =============================================================================

# Counter for test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# setup_test_environment() — Create temporary gates directory
setup_test_environment() {
    TEMP_GATES_DIR=$(mktemp -d)
    TEST_HOME=$(mktemp -d)
    export HOME="$TEST_HOME"
    mkdir -p "$TEST_HOME/.claude/gates"
    # Copy runner to temp location so it can find gates
    if [ -f "$RUNNER_PATH" ]; then
        cp "$RUNNER_PATH" "$TEMP_GATES_DIR/runner.sh"
    fi
}

# teardown_test_environment() — Clean up temporary directories
teardown_test_environment() {
    [ -n "$TEMP_GATES_DIR" ] && rm -rf "$TEMP_GATES_DIR" 2>/dev/null || true
    [ -n "$TEST_HOME" ] && rm -rf "$TEST_HOME" 2>/dev/null || true
}

# create_test_gate <name> <hook> <matcher> <condition> <decision> <message>
# Creates a temporary gate YAML file for testing
create_test_gate() {
    local name="$1"
    local hook="$2"
    local matcher="$3"
    local condition="$4"
    local decision="$5"
    local message="$6"

    cat > "$TEST_HOME/.claude/gates/$name.yaml" << EOF
name: "$name"
description: "Test gate for $name"
hook: "$hook"
matcher: "$matcher"
condition: |
  $condition
decision: "$decision"
message: "$message"
EOF
}

# assert_exit_0 <test_name> <command>
# Verify that a command exits with status 0
assert_exit_0() {
    local test_name="$1"
    local command="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if eval "$command" >/dev/null 2>&1; then
        echo "✓ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "✗ FAIL: $test_name (expected exit 0, got $?)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# assert_exit_nonzero <test_name> <command>
# Verify that a command exits with non-zero status
assert_exit_nonzero() {
    local test_name="$1"
    local command="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if ! eval "$command" >/dev/null 2>&1; then
        echo "✓ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "✗ FAIL: $test_name (expected non-zero exit, got 0)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# assert_contains <test_name> <haystack> <needle>
# Verify that haystack contains needle (substring match)
assert_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ "$haystack" == *"$needle"* ]]; then
        echo "✓ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "✗ FAIL: $test_name"
        echo "  Expected to contain: $needle"
        echo "  Got: $haystack"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# assert_not_contains <test_name> <haystack> <needle>
# Verify that haystack does NOT contain needle
assert_not_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ "$haystack" != *"$needle"* ]]; then
        echo "✓ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "✗ FAIL: $test_name"
        echo "  Expected NOT to contain: $needle"
        echo "  Got: $haystack"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# assert_empty <test_name> <value>
# Verify that a value is empty
assert_empty() {
    local test_name="$1"
    local value="$2"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [ -z "$value" ]; then
        echo "✓ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "✗ FAIL: $test_name (expected empty, got: '$value')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# run_runner <hook> <input_json>
# Execute runner.sh with given hook and JSON input, return output
run_runner() {
    local hook="$1"
    local input="$2"

    if [ ! -f "$RUNNER_PATH" ]; then
        # Runner not implemented yet (TDD)
        return 1
    fi

    # Run runner with input via stdin
    echo "$input" | bash "$RUNNER_PATH" "$hook" 2>/dev/null || return 1
}

# =============================================================================
# Test Functions
# =============================================================================

# Test 1: No gates loaded → allow action (fail-open)
test_no_gates_allows_action() {
    setup_test_environment

    local input=$(cat "$FIXTURES_DIR/mock-preToolUse-bash.json")
    local result=$(run_runner "PreToolUse" "$input" || echo "")

    # No gates directory → should return empty (allow)
    assert_empty "test_no_gates_allows_action" "$result"

    teardown_test_environment
}

# Test 2: Rule 2 catches destructive DB command (mix ecto.drop)
test_rule_2_catches_destructive_db() {
    setup_test_environment

    # Create Rule 2 gate (no-destructive-db.yaml)
    create_test_gate \
        "no-destructive-db" \
        "PreToolUse" \
        "Bash" \
        "jq -r '.tool_input.command' | grep -qE 'mix ecto\\.(create|drop|reset)'" \
        "ask" \
        "Rule 2: Destructive DB command requires explicit confirmation"

    local input=$(cat "$FIXTURES_DIR/mock-destructive-db.json")
    local result=$(run_runner "PreToolUse" "$input" || echo "")

    assert_contains "test_rule_2_catches_destructive_db: decision is ask" "$result" '"permissionDecision":"ask"'
    assert_contains "test_rule_2_catches_destructive_db: message mentions Rule 2" "$result" "Rule 2"

    teardown_test_environment
}

# Test 3: Rule 2 allows safe commands (ls, etc.)
test_rule_2_allows_safe_commands() {
    setup_test_environment

    # Create Rule 2 gate (no-destructive-db.yaml)
    create_test_gate \
        "no-destructive-db" \
        "PreToolUse" \
        "Bash" \
        "jq -r '.tool_input.command' | grep -qE 'mix ecto\\.(create|drop|reset)'" \
        "ask" \
        "Rule 2: Destructive DB command requires explicit confirmation"

    local input=$(cat "$FIXTURES_DIR/mock-preToolUse-bash.json")
    local result=$(run_runner "PreToolUse" "$input" || echo "")

    # Safe command should not trigger gate → allow (empty output)
    assert_empty "test_rule_2_allows_safe_commands" "$result"

    teardown_test_environment
}

# Test 4: Rule 4 catches root .md files (not in /docs)
test_rule_4_catches_root_md() {
    setup_test_environment

    # Create Rule 4 gate (no-docs-violation.yaml)
    create_test_gate \
        "no-docs-violation" \
        "PreToolUse" \
        "Write|Edit" \
        "file=\$(jq -r '.tool_input.file_path'); base=\"\${file##*/}\"; [[ \"\$base\" == *.md ]] || exit 1; case \"\$file\" in */docs/*|docs/*) exit 1;; esac; case \"\$base\" in CLAUDE.md|README.md|claude.md) exit 1;; esac; exit 0" \
        "deny" \
        "Rule 4: .md files must live under /docs (exceptions: CLAUDE.md, README.md, directory claude.md)"

    local input=$(cat "$FIXTURES_DIR/mock-preToolUse-write.json")
    local result=$(run_runner "PreToolUse" "$input" || echo "")

    assert_contains "test_rule_4_catches_root_md: decision is deny" "$result" '"permissionDecision":"deny"'
    assert_contains "test_rule_4_catches_root_md: message mentions Rule 4" "$result" "Rule 4"

    teardown_test_environment
}

# Test 5: Rule 4 allows /docs/.md files
test_rule_4_allows_docs_md() {
    setup_test_environment

    # Create Rule 4 gate (no-docs-violation.yaml)
    create_test_gate \
        "no-docs-violation" \
        "PreToolUse" \
        "Write|Edit" \
        "file=\$(jq -r '.tool_input.file_path'); base=\"\${file##*/}\"; [[ \"\$base\" == *.md ]] || exit 1; case \"\$file\" in */docs/*|docs/*) exit 1;; esac; case \"\$base\" in CLAUDE.md|README.md|claude.md) exit 1;; esac; exit 0" \
        "deny" \
        "Rule 4: .md files must live under /docs (exceptions: CLAUDE.md, README.md, directory claude.md)"

    # Create input for /docs/oauth.md (allowed location)
    local input='{"tool_name":"Write","tool_input":{"file_path":"docs/oauth.md"}}'
    local result=$(run_runner "PreToolUse" "$input" || echo "")

    # File in /docs → should not trigger gate → allow (empty output)
    assert_empty "test_rule_4_allows_docs_md" "$result"

    teardown_test_environment
}

# Test 6: First match wins (alphabetical order)
test_first_match_wins() {
    setup_test_environment

    # Create two gates that would both match the same input
    # First gate (alphabetically): "a-deny-all-bash"
    create_test_gate \
        "a-deny-all-bash" \
        "PreToolUse" \
        "Bash" \
        "true" \
        "deny" \
        "First gate: deny all bash commands"

    # Second gate (alphabetically): "b-allow-bash"
    create_test_gate \
        "b-allow-bash" \
        "PreToolUse" \
        "Bash" \
        "true" \
        "allow" \
        "Second gate: allow bash commands"

    local input=$(cat "$FIXTURES_DIR/mock-preToolUse-bash.json")
    local result=$(run_runner "PreToolUse" "$input" || echo "")

    # First gate should match and win (alphabetical order)
    assert_contains "test_first_match_wins: first gate wins" "$result" "First gate: deny all bash"
    assert_not_contains "test_first_match_wins: second gate loses" "$result" "Second gate"

    teardown_test_environment
}

test_star_matcher_matches_all_tools() {
    setup_test_environment

    # Schema documents matcher "*" as "all tools"; bare "*" is invalid ERE so
    # the runner must translate it
    create_test_gate \
        "star-matcher" \
        "PreToolUse" \
        "*" \
        "true" \
        "ask" \
        "Star matcher gate triggered"

    local input=$(cat "$FIXTURES_DIR/mock-preToolUse-write.json")
    local result=$(run_runner "PreToolUse" "$input" || echo "")

    assert_contains "test_star_matcher_matches_all_tools: gate triggers" "$result" "Star matcher gate triggered"

    teardown_test_environment
}

# =============================================================================
# Main: Run all tests and report results
# =============================================================================

main() {
    echo "======================================================================="
    echo "Running gate-runner.test.sh test suite"
    echo "======================================================================="
    echo

    # Verify runner exists (or will exist in Task 5)
    if [ ! -f "$RUNNER_PATH" ]; then
        echo "⚠️  WARNING: $RUNNER_PATH not found (expected for TDD, will be created in Task 5)"
        echo
    fi

    # Run all test functions
    test_no_gates_allows_action || true
    test_rule_2_catches_destructive_db || true
    test_rule_2_allows_safe_commands || true
    test_rule_4_catches_root_md || true
    test_rule_4_allows_docs_md || true
    test_first_match_wins || true
    test_star_matcher_matches_all_tools || true

    echo
    echo "======================================================================="
    echo "Test Results: $TESTS_PASSED/$TESTS_TOTAL passed, $TESTS_FAILED failed"
    echo "======================================================================="

    return "$TESTS_FAILED"
}

main "$@"
