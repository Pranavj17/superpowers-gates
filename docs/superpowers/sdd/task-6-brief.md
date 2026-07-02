# Task 6: Write Tests for validate.sh

**Goal:** Write tests for YAML gate validator before implementing it.

**Files to create:**
- `lib/tests/validate.test.sh` — Test suite for validate.sh

**5 test functions:**
1. `test_valid_gate_passes` — Valid gate from Task 1 fixtures passes
2. `test_invalid_gate_fails` — Invalid gate (missing field) fails
3. `test_invalid_hook_fails` — Invalid hook value rejected
4. `test_invalid_decision_fails` — Invalid decision value rejected
5. `test_non_executable_condition_caught` — Non-executable condition caught

**Validator checks (from spec):**
- Required fields: name, description, hook, matcher, condition, decision, message
- Valid hook: PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, SessionEnd
- Valid decision: allow, deny, ask, transform
- YAML parseable (yq)
- Condition executable (optional: best-effort)

**Steps:**
1. Create lib/tests/validate.test.sh with 5 test functions
2. Make executable
3. Run tests (will fail—validate.sh not created yet)
4. Commit: "test(validate): add unit tests for gate validator"

**Report file:** `/Users/pranav.j/Documents/claude-x/.superpowers/sdd/task-6-report.md`
