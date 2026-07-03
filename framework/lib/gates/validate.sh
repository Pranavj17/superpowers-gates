#!/bin/bash

# =============================================================================
# validate.sh — Gate YAML validator
#
# This script validates gate YAML files for the Hook Gates Framework.
# Checks YAML syntax, required fields, and enum values.
# =============================================================================

set -euo pipefail

# Valid enum values
readonly VALID_HOOKS=("PreToolUse" "PostToolUse" "UserPromptSubmit" "SessionStart" "Stop" "SubagentStop")
readonly VALID_DECISIONS=("allow" "deny" "ask" "block" "inject" "transform")
readonly VALID_SEVERITIES=("low" "medium" "high" "critical")

# Required fields (7 total)
readonly REQUIRED_FIELDS=("name" "description" "hook" "matcher" "condition" "decision" "message")

# =============================================================================
# Helper Functions
# =============================================================================

# is_in_array <value> <array_name>
#
# Check if a value exists in an array
#
# Arguments:
#   $1 - The value to search for
#   $2 - The variable name of the array
#
# Returns:
#   0 if found, 1 if not found
#
is_in_array() {
    local value="$1"
    local array_name="$2"

    # Use eval to safely access the array
    case "$array_name" in
        "VALID_HOOKS")
            [[ "${VALID_HOOKS[*]}" =~ $value ]] && return 0
            ;;
        "VALID_DECISIONS")
            [[ "${VALID_DECISIONS[*]}" =~ $value ]] && return 0
            ;;
        "VALID_SEVERITIES")
            [[ "${VALID_SEVERITIES[*]}" =~ $value ]] && return 0
            ;;
    esac
    return 1
}

# validate_gate <gate_file>
#
# Validate a gate YAML file.
#
# Arguments:
#   $1 - Path to the gate YAML file
#
# Returns:
#   0 if valid, 1 if invalid
#
validate_gate() {
    local gate_file="$1"
    local filename
    filename=$(basename "$gate_file")

    # Step 1: Check if file exists
    if [[ ! -f "$gate_file" ]]; then
        echo "ERROR: File not found: $gate_file"
        return 1
    fi

    # Step 2: Check if YAML is parseable with yq
    if ! yq '.' "$gate_file" >/dev/null 2>&1; then
        echo "ERROR: Invalid YAML syntax in $filename"
        return 1
    fi

    # Step 3: Check for all required fields
    for field in "${REQUIRED_FIELDS[@]}"; do
        local value
        value=$(yq -r ".$field" "$gate_file" 2>/dev/null) || value=""

        # yq returns "null" for missing fields, so check for both empty and null
        if [[ -z "$value" ]] || [[ "$value" == "null" ]]; then
            echo "ERROR: Missing required field '$field' in $filename"
            return 1
        fi
    done

    # Step 4: Validate hook enum
    local hook
    hook=$(yq -r '.hook' "$gate_file" 2>/dev/null) || hook=""
    if ! is_in_array "$hook" "VALID_HOOKS"; then
        echo "ERROR: Invalid hook value '$hook' in $filename. Valid values: ${VALID_HOOKS[*]}"
        return 1
    fi

    # Step 5: Validate decision enum
    local decision
    decision=$(yq -r '.decision' "$gate_file" 2>/dev/null) || decision=""
    if ! is_in_array "$decision" "VALID_DECISIONS"; then
        echo "ERROR: Invalid decision value '$decision' in $filename. Valid values: ${VALID_DECISIONS[*]}"
        return 1
    fi

    # Step 5b: decision must be legal for this hook (dialect table — keep in
    # sync with runner.sh decision_legal)
    case "$hook:$decision" in
        PreToolUse:ask|PreToolUse:deny|PreToolUse:allow) ;;
        PostToolUse:block|PostToolUse:inject|PostToolUse:allow) ;;
        UserPromptSubmit:block|UserPromptSubmit:inject) ;;
        SessionStart:inject) ;;
        Stop:block|SubagentStop:block) ;;
        *)
            echo "ERROR: Decision '$decision' is not valid for hook '$hook' in $filename"
            return 1 ;;
    esac

    # Step 5c: optional max_blocks must be a positive integer (applies to any hook)
    local max_blocks
    max_blocks=$(yq -r '.max_blocks // ""' "$gate_file" 2>/dev/null) || max_blocks=""
    if [[ -n "$max_blocks" ]] && [[ "$max_blocks" != "null" ]]; then
        if ! [[ "$max_blocks" =~ ^[1-9][0-9]*$ ]]; then
            echo "ERROR: max_blocks must be a positive integer in $filename"
            return 1
        fi
    fi

    # Step 6: Validate severity (optional field)
    local severity
    severity=$(yq -r '.severity' "$gate_file" 2>/dev/null) || severity=""
    # Only validate if severity is present and not null
    if [[ -n "$severity" ]] && [[ "$severity" != "null" ]] && ! is_in_array "$severity" "VALID_SEVERITIES"; then
        echo "ERROR: Invalid severity value '$severity' in $filename. Valid values: ${VALID_SEVERITIES[*]}"
        return 1
    fi

    # Step 7: Validate condition is executable (valid bash)
    # First check if condition is a string (not an object or array)
    local condition_type
    condition_type=$(yq '.condition | type' "$gate_file" 2>/dev/null) || condition_type=""

    # If condition is not a string, it's invalid
    if [[ -n "$condition_type" ]] && [[ "$condition_type" != "!!str" ]]; then
        echo "ERROR: Non-executable condition in $filename (condition must be a string, not $condition_type)"
        return 1
    fi

    local condition
    condition=$(yq -r '.condition' "$gate_file" 2>/dev/null) || condition=""

    # Try to parse and validate the condition as bash
    # Create a temporary file to test the condition
    local temp_condition_file
    temp_condition_file=$(mktemp)
    trap "rm -f '$temp_condition_file'" EXIT

    # Wrap the condition in a bash script for validation
    cat > "$temp_condition_file" << CONDITION_EOF
#!/bin/bash
set -euo pipefail
$condition
CONDITION_EOF

    # Try to syntax-check the condition
    # Use bash -n for syntax checking
    if ! bash -n "$temp_condition_file" 2>/dev/null; then
        echo "ERROR: Non-executable condition in $filename (invalid bash syntax)"
        rm -f "$temp_condition_file"
        return 1
    fi

    rm -f "$temp_condition_file"

    # All validations passed
    echo "✓ $filename valid"
    return 0
}

# Export the function so it can be sourced
export -f validate_gate is_in_array

# =============================================================================
# CLI entry point
#
# Allows direct execution: validate specific file args, or all gates in
# ~/.claude/gates if no args are given. validate_gate already prints its own
# ERROR/success messages, so this guard only tracks the aggregate exit code.
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    exit_code=0
    if [[ $# -gt 0 ]]; then
        targets=("$@")
    else
        shopt -s nullglob
        targets=("$HOME/.claude/gates"/*.yaml)
        shopt -u nullglob
    fi
    for gate_file in "${targets[@]}"; do
        if ! validate_gate "$gate_file"; then
            exit_code=1
        fi
    done
    exit $exit_code
fi
