#!/bin/bash

# =============================================================================
# runner.sh — Gate executor for SDD (Subagent-Driven Development)
#
# Loads gate configurations from ~/.claude/gates/*.yaml and evaluates them
# against hook events and tool inputs, returning permission decisions.
#
# Usage:
#   echo '{"tool_name":"Bash","tool_input":{"command":"..."}}' | runner.sh <hook>
#
# Arguments:
#   $1 - Hook event name (e.g., "PreToolUse")
#
# Input (stdin):
#   JSON object with structure: {"tool_name":"...", "tool_input":{...}}
#
# Output (if gate triggers):
#   JSON decision: {"hookSpecificOutput":{"hookEventName":"...","permissionDecision":"...","permissionDecisionReason":"..."}}
#
# Exit codes:
#   0 - Always (allow action if no gate triggers)
# =============================================================================

set -euo pipefail

# Get the hook event name from first argument
HOOK_EVENT="$1"

# Read the input JSON from stdin
INPUT_JSON=$(cat)

# Get the gates directory from HOME
GATES_DIR="${HOME}/.claude/gates"

# If gates directory doesn't exist, exit silently (allow action)
if [ ! -d "$GATES_DIR" ]; then
    exit 0
fi

# Load all *.yaml files from gates directory in alphabetical order
# For each gate: check hook match, matcher match, evaluate condition
# First match wins and outputs decision, then exit 0
for gate_file in $(find "$GATES_DIR" -maxdepth 1 -name "*.yaml" -type f | sort); do
    # Use yq to extract fields from the YAML file
    # We need: hook, matcher, condition, decision, message

    # Extract fields with yq
    gate_hook=$(yq eval '.hook' "$gate_file" 2>/dev/null || echo "")
    gate_matcher=$(yq eval '.matcher' "$gate_file" 2>/dev/null || echo "")
    gate_condition=$(yq eval '.condition' "$gate_file" 2>/dev/null || echo "")
    gate_decision=$(yq eval '.decision' "$gate_file" 2>/dev/null || echo "")
    gate_message=$(yq eval '.message' "$gate_file" 2>/dev/null || echo "")

    # Skip if any field is empty (invalid gate)
    if [ -z "$gate_hook" ] || [ -z "$gate_matcher" ] || [ -z "$gate_condition" ] || [ -z "$gate_decision" ] || [ -z "$gate_message" ]; then
        continue
    fi

    # Check if gate's hook matches the event hook
    if [ "$gate_hook" != "$HOOK_EVENT" ]; then
        continue
    fi

    # Extract the tool name from the input JSON
    tool_name=$(echo "$INPUT_JSON" | jq -r '.tool_name // .tool' 2>/dev/null || echo "")

    # Skip if we couldn't extract tool name
    if [ -z "$tool_name" ]; then
        continue
    fi

    # Check if gate's matcher matches the tool name using regex
    # matcher can be a single tool name, a pipe-separated list like "Write|Edit",
    # or "*" for all tools (translated: bare "*" is not a valid ERE)
    if [ "$gate_matcher" = "*" ]; then
        gate_matcher=".*"
    fi
    if ! echo "$tool_name" | grep -qE "^($gate_matcher)$"; then
        continue
    fi

    # Evaluate the condition (bash code that gets input JSON via stdin)
    # The condition should exit 0 (true) or 1 (false)
    if echo "$INPUT_JSON" | bash -c "$gate_condition" 2>/dev/null; then
        # Gate triggered! Output the decision and exit
        output=$(cat <<EOF
{"hookSpecificOutput":{"hookEventName":"$HOOK_EVENT","permissionDecision":"$gate_decision","permissionDecisionReason":"$gate_message"}}
EOF
)
        echo "$output"
        exit 0
    fi
done

# No gates matched → allow action
exit 0
