# Task 6 Report: Write Tests for Gate Validator (validate.sh)

**Date:** 2026-07-02  
**Status:** COMPLETE ✓  
**Commit:** `aca2b3f` — test(validate): add unit tests for gate validator

## Summary

Successfully created a comprehensive test suite for the gate YAML validator before implementation, following TDD principles. All 5 test functions are in place and configured to test the `validate_gate()` function once Task 7 implements it.

## Deliverables

### Test Suite File
- **File:** `lib/tests/validate.test.sh` (executable)
- **Lines:** 155
- **Pattern:** Follows existing test framework (assert helpers from `helpers.test.sh`)

### Test Fixtures Created
Four fixture files to support the 5 test cases:
1. **valid-gate.yaml** (pre-existing from Task 1)
   - Complete, valid gate with all required fields
   - Hook: `PreToolUse`
   - Decision: `ask`

2. **invalid-gate.yaml** (pre-existing from Task 1)
   - Missing `decision` field
   - Tests field validation

3. **invalid-hook.yaml** (NEW)
   - Hook value: `InvalidHook` (not in enum)
   - Tests hook validation (enum: PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, SessionEnd)

4. **invalid-decision.yaml** (NEW)
   - Decision value: `invalid_decision` (not in enum)
   - Tests decision validation (enum: allow, deny, ask, transform)

5. **non-executable-condition.yaml** (NEW)
   - Condition contains invalid bash syntax: `[ missing closing bracket`
   - Tests condition executability detection

## Test Functions (5 Total)

### 1. test_valid_gate_passes
**Purpose:** Valid gate from Task 1 fixtures passes  
**Input:** `valid-gate.yaml` (all fields present, valid enums)  
**Expected:** Exit 0 (success)  
**Coverage:** Happy path validation

### 2. test_invalid_gate_fails
**Purpose:** Invalid gate (missing field) fails  
**Input:** `invalid-gate.yaml` (missing `decision` field)  
**Expected:** Exit 1 (failure)  
**Coverage:** Required field validation

### 3. test_invalid_hook_fails
**Purpose:** Invalid hook value rejected  
**Input:** `invalid-hook.yaml` (hook: `InvalidHook`)  
**Expected:** Exit 1 (failure)  
**Coverage:** Enum validation for hook

### 4. test_invalid_decision_fails
**Purpose:** Invalid decision value rejected  
**Input:** `invalid-decision.yaml` (decision: `invalid_decision`)  
**Expected:** Exit 1 (failure)  
**Coverage:** Enum validation for decision

### 5. test_non_executable_condition_caught
**Purpose:** Non-executable condition caught  
**Input:** `non-executable-condition.yaml` (condition with invalid bash syntax)  
**Expected:** Exit 1 (failure)  
**Coverage:** Condition executability detection (best-effort per spec)

## Test Framework

### Assert Helpers
Reused from `helpers.test.sh`:
- `assert_exit_0 <test_name> <command>` — Verifies exit status 0
- `assert_exit_nonzero <test_name> <command>` — Verifies non-zero exit

### Result Tracking
- Counter variables: `TESTS_PASSED`, `TESTS_FAILED`, `TESTS_TOTAL`
- Main function runs all 5 tests with `|| true` for resilience
- Final report: "Test Results: X/Y passed, Z failed"
- Exit code matches number of failures

## Validation Checklist

✓ All 5 required test functions created  
✓ Fixture files created (3 new, 2 pre-existing)  
✓ Test file executable (`chmod +x`)  
✓ Tests fail appropriately (validate.sh not yet created)  
✓ Follows project testing patterns  
✓ Uses `FIXTURES_DIR` for portability  
✓ Proper error handling with `set -euo pipefail`  
✓ Committed with message: "test(validate): add unit tests for gate validator"  

## Validator Implementation Requirements (Task 7)

The `validate_gate <gate_file>` function must:

1. **Check YAML parseable** — Use `yq` to parse file
2. **Check required fields:** name, description, hook, matcher, condition, decision, message
3. **Validate hook enum:** PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, SessionEnd
4. **Validate decision enum:** allow, deny, ask, transform
5. **Validate severity** (optional, enum if present)
6. **Return:** 0 on success, 1 on failure
7. **Output:** "✓ filename.yaml valid" on success, "ERROR: ..." on failure

## Next Steps

- Task 7: Implement `lib/gates/validate.sh` with validation logic
- Run tests: `bash lib/tests/validate.test.sh` (all 5 should PASS)
- Task 8: Validate example gates
- Task 9: Add CI/linting validation

## Test Execution

Current state (expected):
```
$ bash lib/tests/validate.test.sh
❌ FATAL: lib/gates/validate.sh not found (expected for TDD)
```

After Task 7 (expected):
```
$ bash lib/tests/validate.test.sh
✓ PASS: test_valid_gate_passes
✓ PASS: test_invalid_gate_fails
✓ PASS: test_invalid_hook_fails
✓ PASS: test_invalid_decision_fails
✓ PASS: test_non_executable_condition_caught

Test Results: 5/5 passed, 0 failed
```

## Files Modified/Created

```
lib/tests/validate.test.sh ..................... NEW (155 lines)
lib/tests/fixtures/invalid-hook.yaml ........... NEW (9 lines)
lib/tests/fixtures/invalid-decision.yaml ....... NEW (9 lines)
lib/tests/fixtures/non-executable-condition.yaml NEW (9 lines)
```

**Total additions:** 185 lines  
**Total files:** 4
