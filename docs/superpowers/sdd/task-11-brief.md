# Task 11: Update Project Configuration

**Goal:** Register hook runner in project settings and update project docs.

**Files to modify:**
- `.claude/settings.json` — Add PreToolUse hook with runner.sh
- `CLAUDE.md` — Update project status

**Settings update:**
- Add to `hooks.PreToolUse` array
- Command: `bash ~/.claude/gates/lib/gates/runner.sh PreToolUse`
- Status message: "Checking gates..."

**CLAUDE.md update:**
- Add section: "Hook Gates Framework Status"
- Note framework complete + ready to use
- Mention how to use (copy gates, update settings, create custom gates)

**Steps:**
1. Read current .claude/settings.json
2. Add PreToolUse hook (if not present)
3. Verify JSON is valid (jq)
4. Append status section to CLAUDE.md
5. Commit: "config: register hook gates framework in settings.json"

**Report file:** `/Users/pranav.j/Documents/claude-x/.superpowers/sdd/task-11-report.md`
