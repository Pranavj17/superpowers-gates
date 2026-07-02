# Task 4: Write Tests for runner.sh

**Goal:** Write comprehensive unit tests for the gate executor before implementing it.

**Files to create:**
- `lib/tests/gate-runner.test.sh` — Test suite for runner.sh

**Global Constraints:**
- Tests use fixtures from Task 1 (mock-*.json files)
- Tests use example gates (to be created later, but test framework should support them)
- Runner evaluates gates in alphabetical order (first match wins)
- No gates loaded → allow (fail-open)
- Tests expect runner at: `lib/gates/runner.sh`

**6 test functions to implement:**
1. `test_no_gates_allows_action` — No gates → allow input
2. `test_rule_2_catches_destructive_db` — Rule 2 gate blocks destructive command
3. `test_rule_2_allows_safe_commands` — Rule 2 allows safe commands
4. `test_rule_4_catches_root_md` — Rule 4 gate blocks root .md files
5. `test_rule_4_allows_docs_md` — Rule 4 allows /docs/.md files
6. `test_first_match_wins` — First matching gate wins (alphabetical order)

**Steps:**
1. Create lib/tests/gate-runner.test.sh with test framework
2. Implement 6 test functions (use fixtures from Task 1)
3. Run tests (will fail—runner.sh not yet created)
4. Commit: "test(runner): add unit tests for gate executor"

**Report file:** `/Users/pranav.j/Documents/claude-x/.superpowers/sdd/task-4-report.md`
