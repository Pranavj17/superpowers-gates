# Task 3: Implement helpers.sh

**Goal:** Implement the two helper functions defined by Task 2 tests.

**Files to create:**
- `lib/gates/helpers.sh` — Bash library with 2 helper functions

**Functions to implement (from tests, Task 2):**

1. `is_destructive_bash_cmd <command>` (lines 35-40 of plan):
   - Returns 0 (true) if command matches: `mix ecto.(create|drop|reset)`
   - Returns non-zero (false) otherwise
   - Example: `is_destructive_bash_cmd "mix ecto.drop"` → exit 0

2. `is_docs_location_violation <file_path>` (lines 42-60 of plan):
   - Returns 0 (true) if file violates Rule 4
   - Rule 4: .md files must live in /docs (exceptions: CLAUDE.md, README.md, directory claude.md)
   - Only check .md files (return 1 if not .md)
   - Allowed locations: /docs/*, docs/*
   - Allowed filenames: CLAUDE.md, README.md, claude.md (anywhere)
   - Everything else: violation (return 0)
   - Example: `is_docs_location_violation "/OAUTH.md"` → exit 0

**Steps:**
1. Create lib/gates/helpers.sh with shebang + 2 functions
2. Make file executable (chmod +x)
3. Run Task 2 tests: `bash lib/tests/helpers.test.sh`
4. All 6 tests should PASS
5. Commit with message: "feat(helpers): implement helper functions for gate conditions"

**Report file:** `/Users/pranav.j/Documents/claude-x/.superpowers/sdd/task-3-report.md`

