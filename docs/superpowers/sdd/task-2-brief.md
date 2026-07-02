# Task 2: Write Tests for helpers.sh

**Goal:** Write unit tests for helper functions before implementing the helpers.sh library.

**Files to create:**
- `lib/tests/helpers.test.sh` — Test suite with assert helpers and 6 test functions

**Project directory:** `/Users/pranav.j/Documents/claude-x`

**Global Constraints:**
- Test file must be executable (chmod +x)
- Tests call functions from `lib/gates/helpers.sh` (will be created in Task 3)
- Two helper functions to test:
  1. `is_destructive_bash_cmd(cmd)` — Returns 0 if cmd matches `mix ecto.(create|drop|reset)`
  2. `is_docs_location_violation(file_path)` — Returns 0 if file violates Rule 4 (md file outside /docs)

**Exact test names and behavior:**
1. `test_is_destructive_bash_cmd_with_ecto_drop` — Should PASS when impl exists (detects "mix ecto.drop")
2. `test_is_destructive_bash_cmd_with_ecto_create` — Should PASS when impl exists (detects "mix ecto.create")
3. `test_is_destructive_bash_cmd_with_safe_command` — Should PASS when impl exists (allows "ls -la")
4. `test_is_docs_location_violation_with_root_md` — Should PASS when impl exists (detects "/OAUTH.md" violation)
5. `test_is_docs_location_violation_with_docs_md` — Should PASS when impl exists (allows "/docs/OAUTH.md")
6. `test_is_docs_location_violation_with_claude_md` — Should PASS when impl exists (allows "/CLAUDE.md")

**Assert helpers to include:**
- `assert_exit_0 <test_name> <command>` — Test command returns 0
- `assert_exit_nonzero <test_name> <command>` — Test command returns non-zero
- `assert_equals <test_name> <actual> <expected>` — Test value equality

**Steps (TDD order):**
1. Create lib/tests/helpers.test.sh with test framework + 6 test functions
2. Source lib/gates/helpers.sh (will fail at this point—helpers.sh not yet created)
3. Call each test function in main block
4. Make file executable
5. Try to run tests (expected: FAIL with "helpers.sh not found")
6. Commit with message: "test(helpers): add unit tests for helper functions"

**Report file:** `/Users/pranav.j/Documents/claude-x/.superpowers/sdd/task-2-report.md`

