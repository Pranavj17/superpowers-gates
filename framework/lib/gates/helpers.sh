#!/bin/bash

# =============================================================================
# helpers.sh — Helper functions for gate conditions
#
# This library provides helper functions for evaluating gate conditions
# in the SDD (Subagent-Driven Development) framework.
# =============================================================================

# is_destructive_bash_cmd <command>
#
# Detect if a command is destructive (e.g., mix ecto.create/drop/reset).
#
# Arguments:
#   $1 - The command string to evaluate
#
# Returns:
#   0 (true) if the command matches destructive patterns
#   1 (false) otherwise
#
# Examples:
#   is_destructive_bash_cmd "mix ecto.drop"    # exit 0 (destructive)
#   is_destructive_bash_cmd "mix ecto.create"  # exit 0 (destructive)
#   is_destructive_bash_cmd "mix ecto.reset"   # exit 0 (destructive)
#   is_destructive_bash_cmd "ls -la"           # exit 1 (safe)
#
is_destructive_bash_cmd() {
    local command="$1"

    # Match: mix ecto.create, mix ecto.drop, mix ecto.reset
    if [[ "$command" =~ mix\ ecto\.(create|drop|reset) ]]; then
        return 0  # Destructive
    fi

    return 1  # Not destructive
}

# is_docs_location_violation <file_path>
#
# Check if a markdown file violates Rule 4 (documentation location rule).
#
# Rule 4 states that all .md files must live in /docs/ with these exceptions:
#   - CLAUDE.md (at project root)
#   - README.md (at project root)
#   - claude.md (directory-specific, can be anywhere)
#
# Arguments:
#   $1 - The file path to check
#
# Returns:
#   0 (true) if the file is a violation of Rule 4
#   1 (false) if the file is not a violation (or not an .md file)
#
# Examples:
#   is_docs_location_violation "OAUTH.md"         # exit 0 (violation)
#   is_docs_location_violation "docs/OAUTH.md"    # exit 1 (not violation)
#   is_docs_location_violation "CLAUDE.md"        # exit 1 (exception)
#   is_docs_location_violation "README.md"        # exit 1 (exception)
#   is_docs_location_violation "lib/claude.md"    # exit 1 (exception)
#   is_docs_location_violation "app.js"           # exit 1 (not .md)
#
is_docs_location_violation() {
    local file_path="$1"

    # Only check .md files
    if [[ ! "$file_path" =~ \.md$ ]]; then
        return 1  # Not a violation (not an .md file)
    fi

    # Extract just the filename
    local filename
    filename=$(basename "$file_path")

    # Exceptions: CLAUDE.md, README.md, claude.md (anywhere)
    if [[ "$filename" == "CLAUDE.md" ]] || \
       [[ "$filename" == "README.md" ]] || \
       [[ "$filename" == "claude.md" ]]; then
        return 1  # Not a violation (exception)
    fi

    # Check if file is in allowed locations: /docs/ or docs/
    if [[ "$file_path" =~ ^/?docs/ ]]; then
        return 1  # Not a violation (in /docs/)
    fi

    # All other .md files are violations
    return 0  # Violation
}
