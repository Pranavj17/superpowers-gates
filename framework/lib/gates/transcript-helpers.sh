#!/bin/bash
# transcript-helpers.sh — jq helpers over the session transcript for gate
# conditions. Source via: source "$GATES_LIB_DIR/transcript-helpers.sh"
# All helpers fail-open: missing/garbled transcript → empty output, nonzero exit.

# th_tool_entries <transcript_path>
# Prints one line per tool call: "<tool_name>\t<compact input JSON>"
th_tool_entries() {
    jq -r 'select(.type=="assistant") | .message.content[]?
           | select(.type=="tool_use")
           | [.name, (.input|tostring)] | @tsv' "$1" 2>/dev/null
}

# th_edited_files_matching <transcript_path> <ere>
# Prints Edit/Write input lines whose JSON matches <ere>; exit 0 if any.
th_edited_files_matching() {
    th_tool_entries "$1" | awk -F'\t' '$1=="Edit"||$1=="Write"{print $2}' \
        | grep -E "$2"
}

# th_ran_command_matching <transcript_path> <ere>
# Exit 0 if any Bash command in the transcript matches <ere>.
th_ran_command_matching() {
    th_tool_entries "$1" | awk -F'\t' '$1=="Bash"{print $2}' | grep -qE "$2"
}

# th_tools_since_last <transcript_path> <marker_ere>
# Prints the th_tool_entries lines that occur AFTER the last line matching
# <marker_ere> (tool name or compact input JSON). If no line matches the
# marker, prints all entries (nothing to scope "since" — the marker never
# happened this session).
th_tools_since_last() {
    local transcript_path="$1"
    local marker="$2"
    local entries last_match
    entries=$(th_tool_entries "$transcript_path")
    last_match=$(printf '%s\n' "$entries" | grep -nE "$marker" 2>/dev/null | tail -1 | cut -d: -f1)
    if [ -z "$last_match" ]; then
        printf '%s\n' "$entries"
    else
        printf '%s\n' "$entries" | tail -n "+$((last_match + 1))"
    fi
}
