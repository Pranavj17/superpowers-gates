# Task 12: Integration Test

**Goal:** Write end-to-end test proving runner + validator + examples work together.

**Files to create:**
- `lib/tests/integration.test.sh` — Integration test suite

**Tests:**
1. All example gates valid (via validate.sh)
2. Rule 2 blocks mix ecto.drop (via runner.sh)
3. Rule 4 blocks /OAUTH.md (via runner.sh)
4. Runner allows safe actions (fail-open)

**Steps:**
1. Create lib/tests/integration.test.sh
2. Load example gates (from Task 9)
3. Run each test (4 total)
4. All should PASS
5. Make executable, commit: "test(integration): add end-to-end framework integration test"

**Report file:** `/Users/pranav.j/Documents/claude-x/.superpowers/sdd/task-12-report.md`
