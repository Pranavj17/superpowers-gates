# Task 5: Implement runner.sh

**Goal:** Implement the gate executor that loads .yaml files and evaluates conditions.

**Files to create:**
- `lib/gates/runner.sh` — Gate executor script

**Behavior (from spec):**
1. Takes `PreToolUse` as first argument (hook event name)
2. Reads hook input from stdin (jq object)
3. Loads all *.yaml files from `~/.claude/gates/` in alphabetical order
4. For each gate:
   - Extract: hook, matcher, condition, decision, message (via yq)
   - Check if gate's hook matches argument
   - Check if matcher matches tool name (jq `.tool`)
   - Evaluate condition (bash code with stdin available)
   - If true: output JSON decision and exit 0
5. No gates match → exit 0 (no output, allow)

**Input format (from stdin):**
```json
{"tool":"Bash","tool_input":{"command":"..."}}
```

**Output format (if gate triggers):**
```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"..."}}
```

**Steps:**
1. Create lib/gates/runner.sh with gate loading + evaluation loop
2. Make executable
3. Run Task 4 tests: `bash lib/tests/gate-runner.test.sh`
4. All 6 tests should PASS
5. Commit: "feat(runner): implement gate executor with first-match-wins semantics"

**Report file:** `/Users/pranav.j/Documents/claude-x/.superpowers/sdd/task-5-report.md`
