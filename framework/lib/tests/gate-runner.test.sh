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

# Helper: run runner with a custom project cwd embedded in input JSON
make_input_with_cwd() { # $1=tool_name $2=cwd
    printf '{"tool_name":"%s","cwd":"%s","tool_input":{"command":"ls"}}' "$1" "$2"
}

# write_project_gate <proj_dir> — drops a "Project gate wins" deny gate
write_project_gate() {
    local proj_dir="$1"
    mkdir -p "$proj_dir/.claude/gates"
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
}

test_project_gates_load_and_win() {
    setup_test_environment
    local proj_dir
    proj_dir=$(mktemp -d)
    write_project_gate "$proj_dir"
    # Global gate allows; project gate denies. Project must win — but only
    # once the project is trusted (FIX 1): write its cwd into the sandboxed
    # HOME's trust file.
    create_test_gate "z-global" "PreToolUse" "Bash" "true" "ask" "Global gate"
    mkdir -p "$TEST_HOME/.claude"
    printf '%s\n' "$proj_dir" > "$TEST_HOME/.claude/gates-trusted"
    local result
    result=$(make_input_with_cwd "Bash" "$proj_dir" | bash "$RUNNER_PATH" "PreToolUse" || echo "")
    assert_contains "test_project_gates_load_and_win" "$result" "Project gate wins"
    rm -rf "$proj_dir"
    teardown_test_environment
}

test_project_gates_ignored_when_untrusted() {
    setup_test_environment
    local proj_dir
    proj_dir=$(mktemp -d)
    write_project_gate "$proj_dir"
    # Global gate allows; project gate (untrusted) must be skipped entirely,
    # so the global "ask" gate should win instead.
    create_test_gate "z-global" "PreToolUse" "Bash" "true" "ask" "Global gate"
    local result
    result=$(make_input_with_cwd "Bash" "$proj_dir" | bash "$RUNNER_PATH" "PreToolUse" || echo "")
    assert_not_contains "test_project_gates_ignored_when_untrusted: project gate skipped" "$result" "Project gate wins"
    assert_contains "test_project_gates_ignored_when_untrusted: global gate still wins" "$result" "Global gate"
    rm -rf "$proj_dir"
    teardown_test_environment
}

test_project_gates_honored_via_env_flag() {
    setup_test_environment
    local proj_dir
    proj_dir=$(mktemp -d)
    write_project_gate "$proj_dir"
    create_test_gate "z-global" "PreToolUse" "Bash" "true" "ask" "Global gate"
    local result
    result=$(make_input_with_cwd "Bash" "$proj_dir" | GATES_TRUST_PROJECT=1 bash "$RUNNER_PATH" "PreToolUse" || echo "")
    assert_contains "test_project_gates_honored_via_env_flag" "$result" "Project gate wins"
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

# Test: PostToolUse block dialect
test_posttooluse_block_dialect() {
    setup_test_environment
    create_test_gate "block-gate" "PostToolUse" "Bash" "true" "block" "Fix the output first"
    local input='{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_output":"x"}'
    local result
    result=$(printf '%s' "$input" | bash "$RUNNER_PATH" "PostToolUse" || echo "")
    assert_contains "test_posttooluse_block_dialect: decision is block" "$result" '"decision":"block"'
    assert_contains "test_posttooluse_block_dialect: message" "$result" "Fix the output first"
    teardown_test_environment
}

# Test: PostToolUse inject uses condition stdout
test_posttooluse_inject_uses_condition_stdout() {
    setup_test_environment
    create_test_gate "inject-gate" "PostToolUse" "Bash" "echo NUDGE-CONTEXT" "inject" "unused message"
    local input='{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_output":"x"}'
    local result
    result=$(printf '%s' "$input" | bash "$RUNNER_PATH" "PostToolUse" || echo "")
    assert_contains "test_posttooluse_inject: additionalContext" "$result" '"additionalContext":"NUDGE-CONTEXT'
    assert_contains "test_posttooluse_inject: hookEventName" "$result" '"hookEventName":"PostToolUse"'
    teardown_test_environment
}

# Test: PostToolUse allow is silent no-op
test_posttooluse_allow_is_silent_noop() {
    setup_test_environment
    create_test_gate "allow-gate" "PostToolUse" "Bash" "true" "allow" "unused"
    local input='{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_output":"x"}'
    local result
    result=$(printf '%s' "$input" | bash "$RUNNER_PATH" "PostToolUse" || echo "")
    assert_empty "test_posttooluse_allow_is_silent_noop: output empty" "$result"
    teardown_test_environment
}

# Test: Stop guard allows second attempt (default single block)
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

# Test: Stop guard respects max_blocks option
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

# Test: Stop guard fails OPEN (does not block) when the counter file exists
# but cannot be read — guard state is unknown, so the runner must never
# re-block on unknown state (FIX 2a).
test_stop_guard_fails_open_when_counter_unreadable() {
    setup_test_environment
    create_test_gate "stop-unreadable" "Stop" "*" "true" "block" "should not re-block on error"
    local sid="unreadable-test"
    local count_file="${TMPDIR:-/tmp}/gates-stop-${sid}-stop-unreadable"
    rm -f "$count_file"
    # First (unblocked) Stop creates+initializes the counter file.
    printf '{"session_id":"%s","stop_hook_active":false}' "$sid" \
        | bash "$RUNNER_PATH" "Stop" >/dev/null 2>&1 || true
    # Simulate an unreadable counter (e.g. disk error, permission change).
    chmod 000 "$count_file" 2>/dev/null || true
    local result
    result=$(printf '{"session_id":"%s","stop_hook_active":true}' "$sid" \
        | bash "$RUNNER_PATH" "Stop" || echo "")
    chmod 644 "$count_file" 2>/dev/null || true
    if [ "$(id -u)" = "0" ]; then
        echo "SKIP: test_stop_guard_fails_open_when_counter_unreadable (running as root, chmod 000 has no effect)"
    else
        assert_empty "test_stop_guard_fails_open_when_counter_unreadable" "$result"
    fi
    rm -f "$count_file"
    teardown_test_environment
}

# Test: gate `name` containing "/" is sanitized before building the counter
# path, so the stop-loop guard still counts correctly across repeat Stops
# instead of the path silently escaping TMPDIR (FIX 2b).
test_stop_guard_sanitizes_gate_name_with_slash() {
    setup_test_environment
    cat > "$HOME/.claude/gates/nested-slash-gate.yaml" <<'EOF'
name: "nested/gate"
description: "gate name contains a slash"
hook: "Stop"
matcher: "*"
condition: |
  true
decision: "block"
message: "keep going"
max_blocks: 2
EOF
    local sid="slashtest"
    local a b c
    a=$(printf '{"session_id":"%s","stop_hook_active":false}' "$sid" | bash "$RUNNER_PATH" "Stop" || echo "")
    b=$(printf '{"session_id":"%s","stop_hook_active":true}' "$sid" | bash "$RUNNER_PATH" "Stop" || echo "")
    c=$(printf '{"session_id":"%s","stop_hook_active":true}' "$sid" | bash "$RUNNER_PATH" "Stop" || echo "")
    assert_contains "test_stop_guard_sanitizes_gate_name_with_slash: 1st blocked" "$a" '"decision":"block"'
    assert_contains "test_stop_guard_sanitizes_gate_name_with_slash: 2nd blocked" "$b" '"decision":"block"'
    assert_empty "test_stop_guard_sanitizes_gate_name_with_slash: 3rd allowed" "$c"
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
    test_project_gates_load_and_win || true
    test_project_gates_ignored_when_untrusted || true
    test_project_gates_honored_via_env_flag || true
    test_stop_block_dialect || true
    test_prompt_inject_uses_condition_stdout || true
    test_sessionstart_matcher_uses_source || true
    test_illegal_decision_for_event_skipped || true
    test_posttooluse_block_dialect || true
    test_posttooluse_inject_uses_condition_stdout || true
    test_posttooluse_allow_is_silent_noop || true
    test_stop_guard_allows_second_attempt || true
    test_stop_guard_max_blocks_two || true
    test_stop_guard_fails_open_when_counter_unreadable || true
    test_stop_guard_sanitizes_gate_name_with_slash || true

    echo
    echo "======================================================================="
    echo "Test Results: $TESTS_PASSED/$TESTS_TOTAL passed, $TESTS_FAILED failed"
    echo "======================================================================="

    return "$TESTS_FAILED"
}

main "$@"
