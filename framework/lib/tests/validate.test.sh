#!/bin/bash

# =============================================================================
# validate.test.sh — Unit tests for lib/gates/validate.sh
#
# This test suite validates the gate YAML validator before implementation (TDD).
# Tests will fail until validate.sh is created in Task 7.
# =============================================================================

set -euo pipefail

# Source the validate library (will fail until Task 7)
source "$(dirname "$0")/../gates/validate.sh" 2>/dev/null || {
    echo "❌ FATAL: lib/gates/validate.sh not found (expected for TDD)"
    exit 1
}

# Get the fixtures directory path
FIXTURES_DIR="$(dirname "$0")/fixtures"

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

# =============================================================================
# Test Functions for validate_gate()
# =============================================================================

# Test 1: Valid gate from Task 1 fixtures passes
test_valid_gate_passes() {
    assert_exit_0 "test_valid_gate_passes" \
        "validate_gate '$FIXTURES_DIR/valid-gate.yaml'"
}

# Test 2: Invalid gate (missing field) fails
test_invalid_gate_fails() {
    assert_exit_nonzero "test_invalid_gate_fails" \
        "validate_gate '$FIXTURES_DIR/invalid-gate.yaml'"
}

# Test 3: Invalid hook value rejected
test_invalid_hook_fails() {
    assert_exit_nonzero "test_invalid_hook_fails" \
        "validate_gate '$FIXTURES_DIR/invalid-hook.yaml'"
}

# Test 4: Invalid decision value rejected
test_invalid_decision_fails() {
    assert_exit_nonzero "test_invalid_decision_fails" \
        "validate_gate '$FIXTURES_DIR/invalid-decision.yaml'"
}

# Test 5: Non-executable condition caught
test_non_executable_condition_caught() {
    assert_exit_nonzero "test_non_executable_condition_caught" \
        "validate_gate '$FIXTURES_DIR/non-executable-condition.yaml'"
}

# Test 6: Stop + block + max_blocks is legal (v2 dialect table)
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

# Test 7: deny is not legal for Stop (v2 dialect table)
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

# Test 8: inject is legal for UserPromptSubmit (v2 dialect table)
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

# =============================================================================
# Main: Run all tests and report results
# =============================================================================

main() {
    echo "======================================================================="
    echo "Running validate.test.sh test suite"
    echo "======================================================================="
    echo

    # Run all test functions
    test_valid_gate_passes || true
    test_invalid_gate_fails || true
    test_invalid_hook_fails || true
    test_invalid_decision_fails || true
    test_non_executable_condition_caught || true
    test_stop_block_gate_valid || true
    test_deny_on_stop_invalid || true
    test_inject_on_userpromptsubmit_valid || true

    echo
    echo "======================================================================="
    echo "Test Results: $TESTS_PASSED/$TESTS_TOTAL passed, $TESTS_FAILED failed"
    echo "======================================================================="

    return "$TESTS_FAILED"
}

main "$@"
