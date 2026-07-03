#!/bin/bash

# =============================================================================
# runner.sh — Gate executor (v2: hook control plane)
#
# Loads gates from <cwd>/.claude/gates (project) then ~/.claude/gates
# (global), evaluates them against the hook event, and emits the correct
# decision dialect per event. First triggered gate wins. Fail-open: any
# error skips the gate.
#
# Usage: echo '<hook input JSON>' | runner.sh <HookEvent>
# =============================================================================

set -euo pipefail

HOOK_EVENT="$1"
INPUT_JSON=$(cat)

# Exported so gate conditions can source transcript-helpers.sh etc.
GATES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GATES_LIB_DIR

GLOBAL_GATES_DIR="${HOME}/.claude/gates"
PROJECT_CWD=$(echo "$INPUT_JSON" | jq -r '.cwd // empty' 2>/dev/null || echo "")

# Ordered gate list: project gates first, then global (alphabetical each)
gate_files=()
if [ -n "$PROJECT_CWD" ] && [ -d "$PROJECT_CWD/.claude/gates" ] \
   && [ "$PROJECT_CWD/.claude/gates" != "$GLOBAL_GATES_DIR" ]; then
    while IFS= read -r f; do gate_files+=("$f"); done \
        < <(find "$PROJECT_CWD/.claude/gates" -maxdepth 1 -name "*.yaml" -type f | sort)
fi
if [ -d "$GLOBAL_GATES_DIR" ]; then
    while IFS= read -r f; do gate_files+=("$f"); done \
        < <(find "$GLOBAL_GATES_DIR" -maxdepth 1 -name "*.yaml" -type f | sort)
fi
[ "${#gate_files[@]}" -eq 0 ] && exit 0

# json_str <string> — JSON-encode a string (includes surrounding quotes)
json_str() { jq -Rn --arg s "$1" '$s'; }

# The input field a gate matcher is tested against, per event.
# "__any__" = matchers don't apply to this event (gate always matches).
# Empty = event unsupported → allow everything.
match_key() {
    case "$HOOK_EVENT" in
        PreToolUse|PostToolUse) echo "$INPUT_JSON" | jq -r '.tool_name // .tool // empty' 2>/dev/null || echo "" ;;
        SessionStart)           echo "$INPUT_JSON" | jq -r '.source // empty' 2>/dev/null || echo "" ;;
        SubagentStop)           echo "$INPUT_JSON" | jq -r '.agent_type // empty' 2>/dev/null || echo "" ;;
        Stop|UserPromptSubmit)  echo "__any__" ;;
        *)                      echo "" ;;
    esac
}

# decision_legal <event> <decision> — the dialect table
decision_legal() {
    case "$1:$2" in
        PreToolUse:ask|PreToolUse:deny|PreToolUse:allow) return 0 ;;
        PostToolUse:block|PostToolUse:inject|PostToolUse:allow) return 0 ;;
        UserPromptSubmit:block|UserPromptSubmit:inject) return 0 ;;
        SessionStart:inject) return 0 ;;
        Stop:block|SubagentStop:block) return 0 ;;
        *) return 1 ;;
    esac
}

tool_key=$(match_key)
[ -z "$tool_key" ] && exit 0

for gate_file in "${gate_files[@]}"; do
    gate_name=$(yq eval '.name' "$gate_file" 2>/dev/null || echo "")
    gate_hook=$(yq eval '.hook' "$gate_file" 2>/dev/null || echo "")
    gate_matcher=$(yq eval '.matcher' "$gate_file" 2>/dev/null || echo "")
    gate_condition=$(yq eval '.condition' "$gate_file" 2>/dev/null || echo "")
    gate_decision=$(yq eval '.decision' "$gate_file" 2>/dev/null || echo "")
    gate_message=$(yq eval '.message' "$gate_file" 2>/dev/null || echo "")

    if [ -z "$gate_hook" ] || [ -z "$gate_matcher" ] || [ -z "$gate_condition" ] \
       || [ -z "$gate_decision" ] || [ -z "$gate_message" ]; then
        continue
    fi
    [ "$gate_hook" != "$HOOK_EVENT" ] && continue
    decision_legal "$HOOK_EVENT" "$gate_decision" || continue

    if [ "$tool_key" != "__any__" ]; then
        m="$gate_matcher"
        [ "$m" = "*" ] && m=".*"    # documented all-tools matcher; bare * is invalid ERE
        echo "$tool_key" | grep -qE "^($m)$" || continue
    fi

    # Stop-loop guard: a blocked Stop re-fires with stop_hook_active=true.
    # Default: one block per turn (max_blocks: 1). Counter resets on the
    # first (unblocked) Stop of each turn.
    count_file=""
    if [ "$HOOK_EVENT" = "Stop" ] || [ "$HOOK_EVENT" = "SubagentStop" ]; then
        stop_active=$(echo "$INPUT_JSON" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
        max_blocks=$(yq eval '.max_blocks // 1' "$gate_file" 2>/dev/null || echo "1")
        case "$max_blocks" in (*[!0-9]*|"") max_blocks=1 ;; esac
        session_id=$(echo "$INPUT_JSON" | jq -r '.session_id // "nosession"' 2>/dev/null || echo "nosession")
        count_file="${TMPDIR:-/tmp}/gates-stop-${session_id}-${gate_name}"
        if [ "$stop_active" = "true" ]; then
            count=$(cat "$count_file" 2>/dev/null || echo "0")
            case "$count" in (*[!0-9]*|"") count=0 ;; esac
            [ "$count" -ge "$max_blocks" ] && continue
        else
            echo "0" > "$count_file" 2>/dev/null || true
        fi
    fi

    # Evaluate condition. exit 0 = triggered; stdout = payload for inject.
    if cond_out=$(echo "$INPUT_JSON" | bash -c "$gate_condition" 2>/dev/null); then
        case "$HOOK_EVENT:$gate_decision" in
            PreToolUse:*)
                echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"$gate_decision\",\"permissionDecisionReason\":$(json_str "$gate_message")}}"
                ;;
            Stop:block|SubagentStop:block)
                count=$(cat "$count_file" 2>/dev/null || echo "0")
                case "$count" in (*[!0-9]*|"") count=0 ;; esac
                echo $((count + 1)) > "$count_file" 2>/dev/null || true
                echo "{\"decision\":\"block\",\"reason\":$(json_str "$gate_message")}"
                ;;
            *:block)
                echo "{\"decision\":\"block\",\"reason\":$(json_str "$gate_message")}"
                ;;
            *:inject)
                ctx="${cond_out:-$gate_message}"
                echo "{\"hookSpecificOutput\":{\"hookEventName\":\"$HOOK_EVENT\",\"additionalContext\":$(json_str "$ctx")}}"
                ;;
            PostToolUse:allow)
                : ;;   # legacy v1 no-op decision
        esac
        exit 0
    fi
done
exit 0
