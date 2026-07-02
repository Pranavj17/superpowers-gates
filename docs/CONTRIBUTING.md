# Contributing Gates to the Framework

## Guidelines

1. **Solve a real problem** — Gates should enforce a rule that matters
2. **Clear and concise** — Simple conditions are better than complex ones
3. **Well-tested** — Include example inputs that trigger and don't trigger
4. **Documented** — Add brief description in gate YAML
5. **Reusable** — Avoid project-specific logic; make it generally useful

## Creating a New Gate

### Step 1: Write the Gate File

Create a new `.yaml` file in `framework/lib/examples/`:

```bash
cat > framework/lib/examples/my-gate.yaml << 'EOF'
name: "my-gate"
description: "Clear description of what this gate does"
hook: "PreToolUse"
matcher: "Bash"
condition: |
  # Your bash code here
  jq -r '.tool_input.command' | grep -q "pattern"
decision: "ask"
message: "User-friendly reason"
tags: ["category"]
severity: "medium"
EOF
```

### Step 2: Test the Condition Locally

```bash
# Test with sample input
echo '{"tool":"Bash","tool_input":{"command":"your command"}}' | bash framework/lib/gates/runner.sh PreToolUse
```

### Step 3: Validate the Gate

```bash
bash framework/lib/gates/validate.sh framework/lib/examples/my-gate.yaml
```

### Step 4: Add to Test Suite

In `framework/lib/tests/gate-runner.test.sh`, add tests:

```bash
test_my_gate_triggers() {
  cat > "$TEST_GATES_DIR/.claude/gates/my-gate.yaml" << 'GATE'
# Your gate YAML here
GATE
  
  local input='{"tool":"Bash","tool_input":{"command":"test input"}}'
  local result=$(bash "$RUNNER" PreToolUse < <(echo "$input"))
  assert_contains "$result" "decision.*ask" "my-gate triggers correctly"
}
```

### Step 5: Commit

```bash
git add framework/lib/examples/my-gate.yaml framework/lib/tests/gate-runner.test.sh docs/EXAMPLES.md
git commit -m "feat(gates): add my-gate example for XYZ rule"
```

## Design Patterns

### Pattern 1: Regex Match on Command

```yaml
condition: |
  jq -r '.tool_input.command' | grep -qE 'pattern'
```

### Pattern 2: File Extension Check

```yaml
condition: |
  file=$(jq -r '.tool_input.file_path')
  [[ "$file" == *.extension ]]
```

### Pattern 3: Complex Multi-Check

```yaml
condition: |
  file=$(jq -r '.tool_input.file_path')
  cmd=$(jq -r '.tool_input.command // empty')
  [[ "$file" == *.ext ]] && [[ "$cmd" =~ pattern ]]
```

### Pattern 4: File Existence Check

```yaml
condition: |
  file=$(jq -r '.tool_input.file_path')
  [ -f "$file" ] && grep -q "marker" "$file"
```

## Testing Checklist

- [ ] Gate YAML passes validation
- [ ] Condition triggers with expected input
- [ ] Condition does NOT trigger with safe input
- [ ] Message is clear and actionable
- [ ] Severity is appropriate (low/medium/high/critical)
- [ ] Tags are descriptive
- [ ] No typos in name or description

## Common Mistakes

❌ **Overly complex condition** — Keep it simple and readable  
❌ **Vague message** — Tell user exactly what rule they violated  
❌ **Missing required fields** — Validate with `bash framework/lib/gates/validate.sh`  
❌ **Condition that doesn't exit cleanly** — Always `exit 0` or `exit 1` explicitly  
❌ **Too broad matcher** — Be specific to tools that make sense  

## Reporting Issues

Found a bug in the framework? Open an issue with:
1. The gate file that triggers the issue
2. Expected behavior
3. Actual behavior
4. Steps to reproduce
