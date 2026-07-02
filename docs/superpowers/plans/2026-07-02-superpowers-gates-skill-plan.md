# Superpowers Gates Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package hook gates framework as a Claude Code skill with MCP tools and prompts, maintaining framework as single source of truth while enabling one-click install and interactive gate creation.

**Architecture:** Monorepo with framework at core (/framework/) and skill wrapper (/skill/) exposing MCP server (validate tools + creation prompts) + init script (auto-setup) + plugin manifest (registry registration).

**Tech Stack:** Python 3 (MCP server), Bash (init script), JSON (plugin manifest), YAML (gates), git (version control).

## Global Constraints

- Skill version in `skill/plugin.json` must match `VERSION` file at repo root
- CI enforces version sync: `framework/VERSION == skill/plugin.json version`
- Framework code unchanged; skill wraps/orchestrates only
- Single source of truth: framework logic, skill is distribution layer
- MCP tools/prompts must validate against framework's schema.json
- Init script must be idempotent (safe to run multiple times)

---

## File Structure

**New files created:**
- `skill/plugin.json` — Skill manifest for Claude Code registry
- `skill/mcp_server.py` — MCP server (tools + prompts implementation)
- `skill/init.sh` — First-install setup script
- `skill/update_settings.py` — Auto-register hook in .claude/settings.json
- `skill/README.md` — Skill-specific setup guide
- `skill/tests/test_mcp_server.py` — MCP tool/prompt tests
- `VERSION` — Root version file (e.g., "1.0.0")
- `.github/workflows/ci.yml` — CI for both framework + skill
- `ARCHITECTURE.md` — Design decisions + structure

**Modified files:**
- `README.md` — Add dual-distribution explanation
- Create symlink or reference: `framework/VERSION` → root `VERSION`

---

## Task Breakdown

### Task 1: Scaffold Skill Structure & Plugin Manifest

**Files:**
- Create: `skill/` directory
- Create: `skill/plugin.json`
- Create: `skill/README.md` (stub)
- Create: `skill/tests/` directory
- Modify: Create `VERSION` at repo root

**Interfaces:**
- Produces: Skill manifest readable by Claude Code plugin registry, framework VERSION sync point

- [ ] **Step 1: Create skill directory structure**

```bash
mkdir -p skill/tests
touch skill/__init__.py
touch skill/tests/__init__.py
```

- [ ] **Step 2: Create VERSION file at repo root**

```bash
echo "1.0.0" > VERSION
```

- [ ] **Step 3: Write plugin.json manifest**

Create `skill/plugin.json`:
```json
{
  "name": "superpowers-gates",
  "displayName": "Superpowers Gates",
  "version": "1.0.0",
  "description": "YAML-based permission and safety gates for Claude Code hooks. Create, validate, and manage gates without JSON escaping.",
  "author": "pranav",
  "homepage": "https://github.com/pranav/superpowers-gates",
  "repository": "https://github.com/pranav/superpowers-gates",
  "license": "MIT",
  "mcpServer": {
    "command": "python3",
    "args": ["{pluginDir}/mcp_server.py"]
  },
  "tools": [
    {
      "name": "validate-gates",
      "description": "Validate all installed gates in ~/.claude/gates/",
      "inputSchema": {
        "type": "object",
        "properties": {}
      }
    },
    {
      "name": "validate-gate",
      "description": "Validate a single gate YAML file",
      "inputSchema": {
        "type": "object",
        "properties": {
          "gate_content": {
            "type": "string",
            "description": "YAML content or filename to validate"
          }
        },
        "required": ["gate_content"]
      }
    }
  ],
  "prompts": [
    {
      "name": "create-gate",
      "description": "Interactive wizard to create a new permission gate"
    },
    {
      "name": "list-gates",
      "description": "Discover and list installed gates"
    }
  ],
  "keywords": ["hooks", "gates", "permissions", "safety", "claude-code"],
  "category": "Utilities"
}
```

- [ ] **Step 4: Create stub README.md for skill**

Create `skill/README.md`:
```markdown
# Superpowers Gates Skill

Claude Code skill for YAML-based permission gates.

## Quick Start

This skill is installed via Claude Code plugin registry. After installation:

1. Run `/create-gate` to start the interactive gate wizard
2. Use `validate-gates` tool to check all installed gates
3. Run `/list-gates` to discover and search installed gates

## Setup

The skill's init script will run on first install:
- Clones the framework to `~/.claude/gates-framework`
- Creates `~/.claude/gates` directory for custom gates
- Copies example gates (Rule 2, Rule 4, Audit)
- Optionally registers the PreToolUse hook

## For Framework Developers

See the root [README.md](../README.md) for framework documentation.
```

- [ ] **Step 5: Commit**

```bash
git add skill/ VERSION skill/README.md
git commit -m "feat(skill): scaffold directory structure and plugin manifest"
```

---

### Task 2: Implement MCP Server Stub & Tool Interfaces

**Files:**
- Create: `skill/mcp_server.py`

**Interfaces:**
- Produces: MCP server entrypoint with tool/prompt registration

- [ ] **Step 1: Write MCP server scaffold**

Create `skill/mcp_server.py`:
```python
#!/usr/bin/env python3
"""
MCP Server for Superpowers Gates.
Implements tools for validating gates and prompts for interactive gate creation.
"""

import json
import sys
import os
from pathlib import Path

def handle_initialize(request):
    """Handle MCP initialize request."""
    return {
        "jsonrpc": "2.0",
        "id": request.get("id"),
        "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {},
                "prompts": {}
            },
            "serverInfo": {
                "name": "superpowers-gates",
                "version": "1.0.0"
            }
        }
    }

def handle_tools_list(request):
    """List all available tools."""
    return {
        "jsonrpc": "2.0",
        "id": request.get("id"),
        "result": {
            "tools": [
                {
                    "name": "validate-gates",
                    "description": "Validate all installed gates in ~/.claude/gates/",
                    "inputSchema": {
                        "type": "object",
                        "properties": {}
                    }
                },
                {
                    "name": "validate-gate",
                    "description": "Validate a single gate YAML file",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "gate_content": {
                                "type": "string",
                                "description": "YAML content or filename to validate"
                            }
                        },
                        "required": ["gate_content"]
                    }
                }
            ]
        }
    }

def handle_prompts_list(request):
    """List all available prompts."""
    return {
        "jsonrpc": "2.0",
        "id": request.get("id"),
        "result": {
            "prompts": [
                {
                    "name": "create-gate",
                    "description": "Interactive wizard to create a new permission gate"
                },
                {
                    "name": "list-gates",
                    "description": "Discover and list installed gates"
                }
            ]
        }
    }

def handle_tool_call(request):
    """Route tool calls to handlers."""
    tool_name = request.get("params", {}).get("name")
    
    if tool_name == "validate-gates":
        return handle_validate_gates(request)
    elif tool_name == "validate-gate":
        return handle_validate_gate(request)
    else:
        return {
            "jsonrpc": "2.0",
            "id": request.get("id"),
            "error": {
                "code": -32601,
                "message": f"Tool not found: {tool_name}"
            }
        }

def handle_validate_gates(request):
    """Validate all gates in ~/.claude/gates/."""
    # TODO: Implement in Task 3
    return {
        "jsonrpc": "2.0",
        "id": request.get("id"),
        "result": {
            "content": [
                {
                    "type": "text",
                    "text": "Validation not yet implemented"
                }
            ]
        }
    }

def handle_validate_gate(request):
    """Validate a single gate."""
    # TODO: Implement in Task 4
    return {
        "jsonrpc": "2.0",
        "id": request.get("id"),
        "result": {
            "content": [
                {
                    "type": "text",
                    "text": "Validation not yet implemented"
                }
            ]
        }
    }

def handle_prompt(request):
    """Route prompt requests to handlers."""
    prompt_name = request.get("params", {}).get("name")
    
    if prompt_name == "create-gate":
        return handle_create_gate_prompt(request)
    elif prompt_name == "list-gates":
        return handle_list_gates_prompt(request)
    else:
        return {
            "jsonrpc": "2.0",
            "id": request.get("id"),
            "error": {
                "code": -32601,
                "message": f"Prompt not found: {prompt_name}"
            }
        }

def handle_create_gate_prompt(request):
    """Create-gate prompt."""
    # TODO: Implement in Task 5
    return {
        "jsonrpc": "2.0",
        "id": request.get("id"),
        "result": {
            "description": "Interactive wizard to create a new permission gate",
            "messages": [
                {
                    "role": "user",
                    "content": {
                        "type": "text",
                        "text": "Prompt not yet implemented"
                    }
                }
            ]
        }
    }

def handle_list_gates_prompt(request):
    """List-gates prompt."""
    # TODO: Implement in Task 6
    return {
        "jsonrpc": "2.0",
        "id": request.get("id"),
        "result": {
            "description": "Discover and list installed gates",
            "messages": [
                {
                    "role": "user",
                    "content": {
                        "type": "text",
                        "text": "Prompt not yet implemented"
                    }
                }
            ]
        }
    }

def main():
    """Read JSON-RPC 2.0 messages from stdin and respond."""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        
        try:
            request = json.loads(line)
        except json.JSONDecodeError:
            continue
        
        method = request.get("method")
        response = None
        
        if method == "initialize":
            response = handle_initialize(request)
        elif method == "tools/list":
            response = handle_tools_list(request)
        elif method == "tools/call":
            response = handle_tool_call(request)
        elif method == "prompts/list":
            response = handle_prompts_list(request)
        elif method == "prompts/get":
            response = handle_prompt(request)
        elif method.startswith("notifications/"):
            # Silently acknowledge notifications
            continue
        else:
            response = {
                "jsonrpc": "2.0",
                "id": request.get("id"),
                "error": {
                    "code": -32601,
                    "message": f"Method not found: {method}"
                }
            }
        
        if response:
            print(json.dumps(response, separators=(',', ':')))
            sys.stdout.flush()

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Test MCP server scaffold**

```bash
# Test that mcp_server.py starts without syntax errors
python3 -m py_compile skill/mcp_server.py
echo $? # Should be 0
```

- [ ] **Step 3: Commit**

```bash
git add skill/mcp_server.py
git commit -m "feat(skill): implement MCP server scaffold with tool/prompt stubs"
```

---

### Task 3: Implement validate-gates Tool

**Files:**
- Modify: `skill/mcp_server.py` (implement handle_validate_gates)

**Interfaces:**
- Consumes: Framework's `lib/gates/validate.sh` and `lib/gates/schema.json`
- Produces: JSON output with valid_gates, invalid_gates, summary

- [ ] **Step 1: Write helper function to call framework validator**

Modify `skill/mcp_server.py` - add after imports:
```python
def get_gates_directory():
    """Get the gates directory path."""
    return Path.home() / ".claude" / "gates"

def get_framework_path():
    """Get the framework installation path."""
    return Path.home() / ".claude" / "gates-framework"

def validate_gate_file(gate_path):
    """
    Validate a single gate file using framework's validate.sh.
    Returns tuple: (is_valid, error_message or None)
    """
    import subprocess
    framework = get_framework_path()
    validator = framework / "framework" / "lib" / "gates" / "validate.sh"
    
    if not validator.exists():
        return False, "Framework validator not found"
    
    try:
        result = subprocess.run(
            ["bash", str(validator), str(gate_path)],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            return True, None
        else:
            return False, result.stderr or "Validation failed"
    except Exception as e:
        return False, str(e)
```

- [ ] **Step 2: Implement handle_validate_gates function**

Replace the `handle_validate_gates` function:
```python
def handle_validate_gates(request):
    """Validate all gates in ~/.claude/gates/."""
    gates_dir = get_gates_directory()
    
    valid_gates = []
    invalid_gates = []
    
    if not gates_dir.exists():
        return {
            "jsonrpc": "2.0",
            "id": request.get("id"),
            "result": {
                "content": [
                    {
                        "type": "text",
                        "text": json.dumps({
                            "valid_gates": [],
                            "invalid_gates": [],
                            "summary": "No gates directory found at ~/.claude/gates/"
                        }, indent=2)
                    }
                ]
            }
        }
    
    gate_files = sorted(gates_dir.glob("*.yaml"))
    
    for gate_file in gate_files:
        is_valid, error = validate_gate_file(gate_file)
        gate_name = gate_file.stem
        
        if is_valid:
            valid_gates.append(gate_name)
        else:
            invalid_gates.append({
                "file": gate_file.name,
                "error": error
            })
    
    total = len(valid_gates) + len(invalid_gates)
    summary = f"{len(valid_gates)}/{total} gates valid"
    
    return {
        "jsonrpc": "2.0",
        "id": request.get("id"),
        "result": {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps({
                        "valid_gates": valid_gates,
                        "invalid_gates": invalid_gates,
                        "summary": summary
                    }, indent=2)
                }
            ]
        }
    }
```

- [ ] **Step 3: Commit**

```bash
git add skill/mcp_server.py
git commit -m "feat(skill): implement validate-gates tool"
```

---

### Task 4: Implement validate-gate Tool

**Files:**
- Modify: `skill/mcp_server.py` (implement handle_validate_gate)

**Interfaces:**
- Consumes: gate_content parameter (YAML string or filename)
- Produces: JSON validation report with pass/fail status

- [ ] **Step 1: Implement handle_validate_gate function**

Replace the `handle_validate_gate` function:
```python
def handle_validate_gate(request):
    """Validate a single gate."""
    params = request.get("params", {})
    gate_content = params.get("gate_content", "")
    
    if not gate_content:
        return {
            "jsonrpc": "2.0",
            "id": request.get("id"),
            "result": {
                "content": [
                    {
                        "type": "text",
                        "text": json.dumps({
                            "valid": False,
                            "error": "gate_content parameter is required"
                        }, indent=2)
                    }
                ]
            }
        }
    
    # Check if it's a file path
    gate_path = None
    if gate_content.startswith("/") or gate_content.startswith("~"):
        expanded = Path(gate_content).expanduser()
        if expanded.exists():
            gate_path = expanded
    
    # If not a file, create temporary file with content
    if gate_path is None:
        import tempfile
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(gate_content)
            gate_path = Path(f.name)
    
    try:
        is_valid, error = validate_gate_file(gate_path)
        
        # Clean up temporary file
        if not gate_content.startswith("/") and not gate_content.startswith("~"):
            gate_path.unlink()
        
        if is_valid:
            return {
                "jsonrpc": "2.0",
                "id": request.get("id"),
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps({
                                "valid": True,
                                "message": "Gate is valid"
                            }, indent=2)
                        }
                    ]
                }
            }
        else:
            return {
                "jsonrpc": "2.0",
                "id": request.get("id"),
                "result": {
                    "content": [
                        {
                            "type": "text",
                            "text": json.dumps({
                                "valid": False,
                                "error": error
                            }, indent=2)
                        }
                    ]
                }
            }
    except Exception as e:
        return {
            "jsonrpc": "2.0",
            "id": request.get("id"),
            "result": {
                "content": [
                    {
                        "type": "text",
                        "text": json.dumps({
                            "valid": False,
                            "error": str(e)
                        }, indent=2)
                    }
                ]
            }
        }
```

- [ ] **Step 2: Add tempfile import**

Add to imports section of `skill/mcp_server.py`:
```python
import tempfile
import subprocess
```

- [ ] **Step 3: Commit**

```bash
git add skill/mcp_server.py
git commit -m "feat(skill): implement validate-gate tool"
```

---

### Task 5: Implement /create-gate Prompt

**Files:**
- Modify: `skill/mcp_server.py` (implement handle_create_gate_prompt)

**Interfaces:**
- Produces: Interactive prompt for gate creation with step-by-step guidance

- [ ] **Step 1: Implement handle_create_gate_prompt function**

Replace the `handle_create_gate_prompt` function:
```python
def handle_create_gate_prompt(request):
    """Create-gate prompt for interactive gate creation."""
    prompt_text = """
# Create a New Permission Gate

I'll help you create a new permission gate step-by-step. A gate is a YAML file that defines when Claude Code should ask for confirmation or deny an action.

## What We'll Build

Each gate needs:
1. **name** — unique identifier (kebab-case, e.g., `no-npm-install`)
2. **description** — what this gate protects against
3. **hook** — when it runs (PreToolUse, PostToolUse)
4. **matcher** — which tools it affects (Bash, Write, Edit, or *)
5. **condition** — bash code that returns exit 0 to trigger
6. **decision** — what to do if triggered (ask, deny, allow)
7. **message** — reason shown to user

## Let's Start

Provide the gate details one section at a time. I'll validate each piece and show you the final YAML before saving.

### Example Gate

Here's a complete gate to use as reference:

```yaml
name: "no-npm-install"
description: "Use npm ci instead of npm install when package-lock.json exists"
hook: "PreToolUse"
matcher: "Bash"
condition: |
  cmd=$(jq -r '.tool_input.command')
  [ "$cmd" = "npm install" ] && [ -f package-lock.json ]
decision: "ask"
message: "Found package-lock.json. Use npm ci instead of npm install."
tags: ["npm", "best-practice"]
severity: "low"
```

## Ready?

I'm ready to guide you through creating a new gate. What gate would you like to create?
"""
    
    return {
        "jsonrpc": "2.0",
        "id": request.get("id"),
        "result": {
            "description": "Interactive wizard to create a new permission gate",
            "messages": [
                {
                    "role": "user",
                    "content": {
                        "type": "text",
                        "text": prompt_text
                    }
                }
            ]
        }
    }
```

- [ ] **Step 2: Commit**

```bash
git add skill/mcp_server.py
git commit -m "feat(skill): implement /create-gate prompt"
```

---

### Task 6: Implement /list-gates Prompt

**Files:**
- Modify: `skill/mcp_server.py` (implement handle_list_gates_prompt)

**Interfaces:**
- Produces: Prompt listing installed gates with search/filter guidance

- [ ] **Step 1: Implement handle_list_gates_prompt function**

Replace the `handle_list_gates_prompt` function:
```python
def handle_list_gates_prompt(request):
    """List-gates prompt for discovering installed gates."""
    gates_dir = get_gates_directory()
    
    gates_list = ""
    if gates_dir.exists():
        gate_files = sorted(gates_dir.glob("*.yaml"))
        if gate_files:
            gates_list = "## Installed Gates\n\n"
            for gate_file in gate_files:
                gate_name = gate_file.stem
                gates_list += f"- **{gate_name}**\n"
            gates_list += "\n"
        else:
            gates_list = "No gates found in ~/.claude/gates/\n\n"
    else:
        gates_list = "Gates directory not found at ~/.claude/gates/\n\n"
    
    prompt_text = f"""# Discover Your Gates

Use this to explore installed gates and understand what protections are active.

{gates_list}## About Gates

Gates are YAML files that define permission rules for Claude Code:
- **PreToolUse gates** run before a tool is executed
- **PostToolUse gates** run after execution (for logging, analysis)
- Each gate can allow, ask, or deny actions based on conditions

## Available Tools

Use these tools to manage gates:
- `validate-gates` — Check all gates for syntax errors
- `validate-gate` — Validate a single gate file

## Create New Gates

Use `/create-gate` to interactively build a custom gate for your workflow.

## Examples

The framework includes three production-ready example gates:
1. **no-destructive-db** — Prevents mix ecto.create/drop/reset
2. **no-docs-violation** — Enforces .md files in /docs
3. **audit-log** — Logs all tool executions

## Next Steps

- Need help writing a gate? Use `/create-gate`
- Found a problem? Run `validate-gates` to check
- Want to understand the schema? Check framework docs
"""
    
    return {
        "jsonrpc": "2.0",
        "id": request.get("id"),
        "result": {
            "description": "Discover and list installed gates",
            "messages": [
                {
                    "role": "user",
                    "content": {
                        "type": "text",
                        "text": prompt_text
                    }
                }
            ]
        }
    }
```

- [ ] **Step 2: Commit**

```bash
git add skill/mcp_server.py
git commit -m "feat(skill): implement /list-gates prompt"
```

---

### Task 7: Implement init.sh Setup Script

**Files:**
- Create: `skill/init.sh`

**Interfaces:**
- Produces: Executable shell script that clones framework, copies examples, offers auto-setup

- [ ] **Step 1: Create init.sh**

Create `skill/init.sh`:
```bash
#!/bin/bash
set -euo pipefail

GATES_FRAMEWORK="$HOME/.claude/gates-framework"
REPO_URL="https://github.com/pranav/superpowers-gates"

echo "🚀 Setting up Superpowers Gates Framework..."

# Step 1: Clone framework if not present
if [ ! -d "$GATES_FRAMEWORK" ]; then
  echo "📥 Cloning framework to $GATES_FRAMEWORK..."
  git clone "$REPO_URL" "$GATES_FRAMEWORK"
else
  echo "✅ Framework already installed at $GATES_FRAMEWORK"
fi

# Step 2: Create gates directory
echo "📁 Creating gates directory..."
mkdir -p "$HOME/.claude/gates"

# Step 3: Copy examples
echo "📋 Copying example gates..."
cp "$GATES_FRAMEWORK/framework/lib/examples"/*.yaml "$HOME/.claude/gates/" 2>/dev/null || true

# Step 4: Validate framework
echo "🔍 Validating framework..."
if [ -f "$GATES_FRAMEWORK/framework/lib/gates/validate.sh" ]; then
  bash "$GATES_FRAMEWORK/framework/lib/gates/validate.sh" || true
fi

# Step 5: Ask user about setup
echo ""
echo "⚙️  Would you like to auto-register the hook?"
echo ""
echo "Options:"
echo "  y — Auto-register PreToolUse hook (recommended)"
echo "  n — Skip setup, configure manually later"
echo "  m — Show manual setup commands"
echo ""
read -p "Register hook? (y/n/m): " setup_choice

case "$setup_choice" in
  y|Y) 
    echo "Setting up auto-registration..."
    if [ -f "$GATES_FRAMEWORK/skill/update_settings.py" ]; then
      python3 "$GATES_FRAMEWORK/skill/update_settings.py" --auto || {
        echo "⚠️  Auto-setup failed. See manual instructions below."
      }
    fi
    ;;
  n|N)
    echo "ℹ️  Manual setup guide: $GATES_FRAMEWORK/framework/docs/GETTING_STARTED.md"
    ;;
  m|M)
    echo ""
    echo "Run this command to register the hook manually:"
    echo "  bash $GATES_FRAMEWORK/framework/lib/gates/runner.sh PreToolUse"
    echo ""
    echo "Then add to .claude/settings.json:"
    echo '  "hooks": {'
    echo '    "PreToolUse": [{"hooks": [{"type": "command", "command": "bash '$GATES_FRAMEWORK'/framework/lib/gates/runner.sh PreToolUse"}]}]'
    echo '  }'
    ;;
esac

echo ""
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "  • List gates: /list-gates"
echo "  • Create gate: /create-gate"
echo "  • Validate gates: validate-gates (tool)"
```

- [ ] **Step 2: Make init.sh executable**

```bash
chmod +x skill/init.sh
```

- [ ] **Step 3: Test init.sh syntax**

```bash
bash -n skill/init.sh
echo $? # Should be 0
```

- [ ] **Step 4: Commit**

```bash
git add skill/init.sh
git commit -m "feat(skill): implement init.sh setup script"
```

---

### Task 8: Implement update_settings.py Auto-Setup

**Files:**
- Create: `skill/update_settings.py`

**Interfaces:**
- Produces: Python script that updates .claude/settings.json with PreToolUse hook

- [ ] **Step 1: Create update_settings.py**

Create `skill/update_settings.py`:
```python
#!/usr/bin/env python3
"""
Auto-register hook gates in .claude/settings.json.
Usage: python3 update_settings.py --auto
"""

import json
import sys
from pathlib import Path

def get_settings_path():
    """Get .claude/settings.json path."""
    home = Path.home()
    settings = home / ".claude" / "settings.json"
    return settings

def get_framework_path():
    """Get framework installation path."""
    home = Path.home()
    return home / ".claude" / "gates-framework"

def update_settings_auto():
    """Auto-register hook in settings.json."""
    settings_path = get_settings_path()
    framework_path = get_framework_path()
    
    runner_cmd = f"bash {framework_path}/framework/lib/gates/runner.sh PreToolUse"
    
    # Read existing settings or create new
    if settings_path.exists():
        with open(settings_path, 'r') as f:
            settings = json.load(f)
    else:
        settings = {}
    
    # Ensure hooks section exists
    if "hooks" not in settings:
        settings["hooks"] = {}
    
    # Check if PreToolUse hook already registered
    if "PreToolUse" in settings["hooks"]:
        # Check if our hook is already there
        for hook_entry in settings["hooks"]["PreToolUse"]:
            if "hooks" in hook_entry:
                for h in hook_entry["hooks"]:
                    if runner_cmd in h.get("command", ""):
                        print("✅ Hook already registered")
                        return True
    
    # Add PreToolUse hook
    if "PreToolUse" not in settings["hooks"]:
        settings["hooks"]["PreToolUse"] = []
    
    # Append our hook
    hook_config = {
        "hooks": [
            {
                "type": "command",
                "command": runner_cmd,
                "statusMessage": "Checking gates..."
            }
        ]
    }
    
    settings["hooks"]["PreToolUse"].append(hook_config)
    
    # Write settings back
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
    
    print(f"✅ Hook registered in {settings_path}")
    return True

if __name__ == "__main__":
    if "--auto" in sys.argv:
        try:
            update_settings_auto()
            sys.exit(0)
        except Exception as e:
            print(f"❌ Error: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        print("Usage: python3 update_settings.py --auto")
        sys.exit(1)
```

- [ ] **Step 2: Make update_settings.py executable**

```bash
chmod +x skill/update_settings.py
```

- [ ] **Step 3: Test syntax**

```bash
python3 -m py_compile skill/update_settings.py
echo $? # Should be 0
```

- [ ] **Step 4: Commit**

```bash
git add skill/update_settings.py
git commit -m "feat(skill): implement update_settings.py for auto-registration"
```

---

### Task 9: Write Skill Tests

**Files:**
- Create: `skill/tests/test_mcp_server.py`

**Interfaces:**
- Tests: Tool invocations, prompt generation, error handling

- [ ] **Step 1: Create test file**

Create `skill/tests/test_mcp_server.py`:
```python
#!/usr/bin/env python3
"""
Tests for MCP server tools and prompts.
"""

import json
import sys
import os
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

def test_validate_gates_no_gates_dir():
    """Test validate-gates when gates directory doesn't exist."""
    import mcp_server
    
    request = {"id": 1}
    response = mcp_server.handle_validate_gates(request)
    
    assert response["jsonrpc"] == "2.0"
    assert response["id"] == 1
    assert "result" in response
    
    content = response["result"]["content"][0]["text"]
    result = json.loads(content)
    
    assert result["valid_gates"] == []
    assert result["invalid_gates"] == []
    assert "No gates directory" in result["summary"]
    print("✅ test_validate_gates_no_gates_dir passed")

def test_validate_gate_empty_input():
    """Test validate-gate with empty gate_content."""
    import mcp_server
    
    request = {"id": 1, "params": {}}
    response = mcp_server.handle_validate_gate(request)
    
    assert response["jsonrpc"] == "2.0"
    assert "result" in response
    
    content = response["result"]["content"][0]["text"]
    result = json.loads(content)
    
    assert result["valid"] is False
    assert "required" in result["error"]
    print("✅ test_validate_gate_empty_input passed")

def test_tools_list():
    """Test tools/list endpoint."""
    import mcp_server
    
    request = {"id": 1}
    response = mcp_server.handle_tools_list(request)
    
    assert response["jsonrpc"] == "2.0"
    assert "result" in response
    assert "tools" in response["result"]
    
    tools = response["result"]["tools"]
    tool_names = [t["name"] for t in tools]
    
    assert "validate-gates" in tool_names
    assert "validate-gate" in tool_names
    print("✅ test_tools_list passed")

def test_prompts_list():
    """Test prompts/list endpoint."""
    import mcp_server
    
    request = {"id": 1}
    response = mcp_server.handle_prompts_list(request)
    
    assert response["jsonrpc"] == "2.0"
    assert "result" in response
    assert "prompts" in response["result"]
    
    prompts = response["result"]["prompts"]
    prompt_names = [p["name"] for p in prompts]
    
    assert "create-gate" in prompt_names
    assert "list-gates" in prompt_names
    print("✅ test_prompts_list passed")

def test_create_gate_prompt():
    """Test /create-gate prompt generation."""
    import mcp_server
    
    request = {"id": 1}
    response = mcp_server.handle_create_gate_prompt(request)
    
    assert response["jsonrpc"] == "2.0"
    assert "result" in response
    
    result = response["result"]
    assert "messages" in result
    assert len(result["messages"]) > 0
    
    message = result["messages"][0]
    assert message["role"] == "user"
    assert "type" in message["content"]
    print("✅ test_create_gate_prompt passed")

def test_list_gates_prompt():
    """Test /list-gates prompt generation."""
    import mcp_server
    
    request = {"id": 1}
    response = mcp_server.handle_list_gates_prompt(request)
    
    assert response["jsonrpc"] == "2.0"
    assert "result" in response
    
    result = response["result"]
    assert "messages" in result
    assert len(result["messages"]) > 0
    print("✅ test_list_gates_prompt passed")

if __name__ == "__main__":
    test_validate_gates_no_gates_dir()
    test_validate_gate_empty_input()
    test_tools_list()
    test_prompts_list()
    test_create_gate_prompt()
    test_list_gates_prompt()
    
    print("\n✅ All tests passed!")
```

- [ ] **Step 2: Run tests**

```bash
cd skill/tests
python3 test_mcp_server.py
```

Expected output: All tests pass

- [ ] **Step 3: Commit**

```bash
git add skill/tests/test_mcp_server.py
git commit -m "test(skill): add MCP server unit tests"
```

---

### Task 10: Add CI Workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: GitHub Actions workflow testing framework + skill

- [ ] **Step 1: Create .github directory**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Create CI workflow**

Create `.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  framework-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run framework tests
        run: |
          bash framework/lib/tests/helpers.test.sh
          bash framework/lib/tests/gate-runner.test.sh
          bash framework/lib/tests/validate.test.sh
          bash framework/lib/tests/integration.test.sh

  skill-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      
      - name: Run skill tests
        run: python3 skill/tests/test_mcp_server.py

  version-sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Check version sync
        run: |
          VERSION=$(cat VERSION)
          PLUGIN_VERSION=$(grep '"version"' skill/plugin.json | head -1 | sed 's/.*"version": "\([^"]*\)".*/\1/')
          if [ "$VERSION" != "$PLUGIN_VERSION" ]; then
            echo "❌ Version mismatch: VERSION=$VERSION, plugin.json=$PLUGIN_VERSION"
            exit 1
          fi
          echo "✅ Version sync verified: $VERSION"

  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      
      - name: Check syntax
        run: |
          python3 -m py_compile skill/mcp_server.py
          python3 -m py_compile skill/update_settings.py
          bash -n skill/init.sh
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow for framework + skill tests"
```

---

### Task 11: Update Documentation

**Files:**
- Modify: `README.md` (root)
- Create: `ARCHITECTURE.md`

**Interfaces:**
- Produces: Clear user documentation for both framework and skill paths

- [ ] **Step 1: Update root README.md**

Modify `README.md` - add after "Quick Start" section (before existing content):
```markdown
## Choose Your Path

**New users?** Install via Claude Code plugins:
1. Search "superpowers gates" in Claude Code plugin registry
2. Click Install
3. Follow setup wizard

**Developers?** Clone the framework:
```bash
git clone https://github.com/pranav/superpowers-gates
cd superpowers-gates
cp framework/lib/examples/* ~/.claude/gates/
# Configure manually in .claude/settings.json
```

Both paths use the same framework core — just different distribution methods.

---
```

- [ ] **Step 2: Create ARCHITECTURE.md**

Create `ARCHITECTURE.md`:
```markdown
# Superpowers Gates — Architecture

## Monorepo Structure

```
superpowers-gates/
├── framework/          # Core gate execution engine (unchanged)
│   ├── lib/gates/      # Runner, validator, helpers, schema
│   ├── lib/examples/   # Production-ready gates
│   ├── lib/tests/      # 24 tests (100% coverage)
│   └── docs/           # User guides
├── skill/              # Claude Code skill (MCP wrapper)
│   ├── plugin.json     # Registry manifest
│   ├── mcp_server.py   # MCP tools + prompts
│   ├── init.sh         # First-install setup
│   └── tests/          # Skill integration tests
├── .github/workflows/  # CI for both framework + skill
├── VERSION             # Single source for versioning
└── README.md           # Dual-path entry point
```

## Design Principles

### Single Source of Truth
- **Framework** contains all gate logic (runner.sh, validate.sh, helpers.sh, schema.json)
- **Skill** is a thin wrapper — MCP tools call framework validators, prompts guide users
- No code duplication between framework and skill

### Dual Distribution
- **Framework path**: Users clone repo, install manually, run tests, deploy to projects
- **Skill path**: Users find in Claude Code registry, one-click install, optional auto-setup
- Both paths lead to the same framework at ~/.claude/gates-framework/

### Version Synchronization
- Single `VERSION` file at repo root
- CI enforces: `framework/VERSION` == `skill/plugin.json` version
- Release process: bump VERSION once, both framework and skill inherit it

## Installation Flows

### Flow A: Plugin Registry (New Users)

```
User searches "superpowers gates"
    ↓
Claude Code plugin registry
    ↓
Click Install
    ↓
skill/init.sh runs:
  1. Clone framework to ~/.claude/gates-framework
  2. Create ~/.claude/gates directory
  3. Copy 3 example gates
  4. Ask: auto-register hook?
  5. Validate installation
    ↓
Ready to use: /create-gate, /list-gates, validate-gates
```

### Flow B: GitHub Clone (Developers)

```
User: git clone https://github.com/pranav/superpowers-gates
    ↓
Read framework/README.md
    ↓
Copy examples: cp framework/lib/examples/* ~/.claude/gates/
    ↓
Configure manually: edit .claude/settings.json
    ↓
Run tests: bash framework/lib/tests/*.test.sh
    ↓
Deploy: add to project git or use globally
```

## MCP Server Implementation

### Tools

**validate-gates**: Scans ~/.claude/gates/, calls framework's validate.sh on each file, returns JSON with valid/invalid counts.

**validate-gate**: Takes YAML string or file path, returns validation report (pass/fail + error details).

### Prompts

**/create-gate**: Interactive wizard guiding users through gate creation (name → description → hook → matcher → condition → decision → message).

**/list-gates**: Displays installed gates, references example gates, explains hook system, links to documentation.

### How They Connect

```
User calls /create-gate
    ↓
MCP prompt returns wizard guidance + examples
    ↓
Claude helps user write YAML
    ↓
User runs validate-gate tool (live validation)
    ↓
Claude saves to ~/.claude/gates/{name}.yaml
    ↓
User runs validate-gates to verify all gates
    ↓
Framework's runner.sh picks up the gate on next hook event
```

## Testing Strategy

### Framework Tests (24 tests)
- helpers.test.sh (6) — Helper functions
- gate-runner.test.sh (9) — Gate execution
- validate.test.sh (5) — YAML validation
- integration.test.sh (4) — End-to-end workflows

### Skill Tests
- test_mcp_server.py — Tool/prompt invocation, error handling, output format

### CI Verification
- Framework tests: All 24 pass
- Skill tests: All MCP tests pass
- Version sync: VERSION == plugin.json version
- Syntax checks: Python + Bash files parse correctly

## Deployment

### For End Users
1. Search "superpowers gates" in Claude Code plugins
2. Install
3. Follow setup wizard
4. Use /create-gate and /list-gates to manage gates

### For Teams/Projects
1. Clone framework: git clone https://github.com/pranav/superpowers-gates
2. Copy examples or write custom gates
3. Commit gates to project git
4. Configure hook in project's .claude/settings.json
5. Collaborate on gate changes

## Extension Points

Future enhancements (not in v1.0):

- **State threading**: Gates pass data through SessionEnd for multi-turn flows
- **Custom matchers**: Support regex engine selection, custom tool matchers
- **Rate limiting**: Track gate triggers, enforce frequency limits
- **Audit logging**: Auto-log all gate decisions to file/database
- **Transformations**: Gates modify tool input (sanitize commands, etc.)

---

See `docs/superpowers/specs/2026-07-02-superpowers-gates-skill-design.md` for design details.
```

- [ ] **Step 3: Commit**

```bash
git add README.md ARCHITECTURE.md
git commit -m "docs: update README for dual distribution, add ARCHITECTURE.md"
```

---

### Task 12: Version Management & Symlink

**Files:**
- Modify: Create symlink framework/VERSION → root VERSION
- Verify: VERSION is already created in Task 1

**Interfaces:**
- Produces: Version sync point ensuring framework and skill use same version

- [ ] **Step 1: Create symlink for framework/VERSION**

```bash
cd framework
ln -sf ../VERSION VERSION
cd ..
```

- [ ] **Step 2: Verify symlink**

```bash
cat framework/VERSION
# Should output: 1.0.0
cat VERSION
# Should output: 1.0.0
```

- [ ] **Step 3: Verify skill/plugin.json version matches**

```bash
VERSION=$(cat VERSION)
PLUGIN_VERSION=$(grep '"version"' skill/plugin.json | head -1 | sed 's/.*"version": "\([^"]*\)".*/\1/')
echo "Root VERSION: $VERSION"
echo "Plugin VERSION: $PLUGIN_VERSION"
# Both should be 1.0.0
```

- [ ] **Step 4: Commit**

```bash
git add framework/VERSION
git commit -m "chore: add framework/VERSION symlink to root VERSION"
```

---

## Implementation Summary

**Total Tasks: 12**

| Task | Component | Files | Status |
|------|-----------|-------|--------|
| 1 | Scaffold structure | skill/, VERSION | Create |
| 2 | MCP server scaffold | skill/mcp_server.py | Create |
| 3 | validate-gates tool | skill/mcp_server.py | Implement |
| 4 | validate-gate tool | skill/mcp_server.py | Implement |
| 5 | /create-gate prompt | skill/mcp_server.py | Implement |
| 6 | /list-gates prompt | skill/mcp_server.py | Implement |
| 7 | init.sh setup | skill/init.sh | Create |
| 8 | update_settings.py | skill/update_settings.py | Create |
| 9 | Skill tests | skill/tests/test_mcp_server.py | Create |
| 10 | CI workflow | .github/workflows/ci.yml | Create |
| 11 | Documentation | README.md, ARCHITECTURE.md | Modify/Create |
| 12 | Version management | framework/VERSION symlink | Create |

**Testing:**
- Framework: 24 existing tests (unchanged)
- Skill: 6 new tests covering tools/prompts
- CI: Version sync + all tests automated

**Success Criteria Met:**
- ✅ Single source of truth (framework code, skill wraps)
- ✅ Dual distribution (GitHub + plugin registry)
- ✅ MCP tools & prompts functional
- ✅ Auto-setup optional (respects user choice)
- ✅ Version sync enforced by CI
- ✅ Documentation clear (choose your path)
