#!/bin/bash

# =============================================================================
# helpers.test.sh — Unit tests for lib/gates/helpers.sh
#
# This test suite validates the helper functions before implementation (TDD).
# Tests will fail until helpers.sh is created in Task 3.
# =============================================================================

set -euo pipefail

# Source the helpers library (will fail until Task 3)
source "$(dirname "$0")/../gates/helpers.sh" 2>/dev/null || {
    echo "❌ FATAL: lib/gates/helpers.sh not found (expected for TDD)"
    exit 1
}

# =============================================================================
# Test Framework: Assert Helpers
# =============================================================================

# Counter for test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

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

# assert_equals <test_name> <actual> <expected>
# Verify that two values are equal
assert_equals() {
    local test_name="$1"
    local actual="$2"
    local expected="$3"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [[ "$actual" == "$expected" ]]; then
        echo "✓ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "✗ FAIL: $test_name (expected '$expected', got '$actual')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# =============================================================================
# Test Functions for is_destructive_bash_cmd()
# =============================================================================

# Test 1: Detect "mix ecto.drop" as destructive
test_is_destructive_bash_cmd_with_ecto_drop() {
    assert_exit_0 "test_is_destructive_bash_cmd_with_ecto_drop" \
        "is_destructive_bash_cmd 'mix ecto.drop'"
}

# Test 2: Detect "mix ecto.create" as destructive
test_is_destructive_bash_cmd_with_ecto_create() {
    assert_exit_0 "test_is_destructive_bash_cmd_with_ecto_create" \
        "is_destructive_bash_cmd 'mix ecto.create'"
}

# Test 3: Allow safe commands like "ls -la"
test_is_destructive_bash_cmd_with_safe_command() {
    assert_exit_nonzero "test_is_destructive_bash_cmd_with_safe_command" \
        "is_destructive_bash_cmd 'ls -la'"
}

# =============================================================================
# Test Functions for is_docs_location_violation()
# =============================================================================

# Test 4: Detect root .md file as violation (e.g., /OAUTH.md)
test_is_docs_location_violation_with_root_md() {
    assert_exit_0 "test_is_docs_location_violation_with_root_md" \
        "is_docs_location_violation 'OAUTH.md'"
}

# Test 5: Allow /docs/ location (e.g., /docs/OAUTH.md)
test_is_docs_location_violation_with_docs_md() {
    assert_exit_nonzero "test_is_docs_location_violation_with_docs_md" \
        "is_docs_location_violation 'docs/OAUTH.md'"
}

# Test 6: Allow CLAUDE.md at root (permitted exception)
test_is_docs_location_violation_with_claude_md() {
    assert_exit_nonzero "test_is_docs_location_violation_with_claude_md" \
        "is_docs_location_violation 'CLAUDE.md'"
}

# =============================================================================
# Main: Run all tests and report results
# =============================================================================

main() {
    echo "======================================================================="
    echo "Running helpers.test.sh test suite"
    echo "======================================================================="
    echo

    # Run all test functions
    test_is_destructive_bash_cmd_with_ecto_drop || true
    test_is_destructive_bash_cmd_with_ecto_create || true
    test_is_destructive_bash_cmd_with_safe_command || true
    test_is_docs_location_violation_with_root_md || true
    test_is_docs_location_violation_with_docs_md || true
    test_is_docs_location_violation_with_claude_md || true

    echo
    echo "======================================================================="
    echo "Test Results: $TESTS_PASSED/$TESTS_TOTAL passed, $TESTS_FAILED failed"
    echo "======================================================================="

    return "$TESTS_FAILED"
}

main "$@"
