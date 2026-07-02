# Task 7: Implement validate.sh

**Goal:** Implement YAML gate validator with comprehensive checks.

**Files to create:**
- `lib/gates/validate.sh` — Gate validator script

**Main function: `validate_gate <gate_file>`**
- Check if YAML is parseable (yq)
- Check required fields present (name, description, hook, matcher, condition, decision, message)
- Validate hook value (enum check)
- Validate decision value (enum check)
- Validate severity (optional, enum check)
- Print: "✓ filename.yaml valid" on success
- Print: "ERROR: ..." on failure
- Return 0 on success, 1 on failure

**Usage:**
- `validate_gate file.yaml` — Validate single gate
- Called from `lib/tests/validate.test.sh` (Task 6)
- Called from Task 9 (validate examples)

**Steps:**
1. Create lib/gates/validate.sh with validation logic
2. Make executable
3. Run Task 6 tests: `bash lib/tests/validate.test.sh`
4. All 5 tests should PASS
5. Commit: "feat(validate): implement gate YAML validator with comprehensive checks"

**Report file:** `/Users/pranav.j/Documents/claude-x/.superpowers/sdd/task-7-report.md`
