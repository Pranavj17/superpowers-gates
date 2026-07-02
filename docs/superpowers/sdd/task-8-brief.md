# Task 8: Create JSON Schema

**Goal:** Create JSON Schema document for gate YAML validation.

**Files to create:**
- `lib/gates/schema.json` — JSON Schema defining valid gate structure

**Schema defines (from spec):**
- Required fields: name, description, hook, matcher, condition, decision, message
- name: string, kebab-case pattern
- description: string
- hook: enum (PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, SessionEnd)
- matcher: string (regex)
- condition: string (bash code)
- decision: enum (allow, deny, ask, transform)
- message: string
- Optional: tags (array), severity (enum), version (string), author (string)

**Steps:**
1. Create valid JSON Schema document
2. Verify it's valid JSON (jq .)
3. Test against valid gate YAML from Task 1 (convert to JSON, validate)
4. Commit: "test(schema): add JSON Schema for gate validation"

**Report file:** `/Users/pranav.j/Documents/claude-x/.superpowers/sdd/task-8-report.md`
