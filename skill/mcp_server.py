#!/usr/bin/env python3
"""
MCP Server for Superpowers Gates.
Implements tools for validating gates and prompts for interactive gate creation.
"""

import json
import sys
import os
import subprocess
import tempfile
from pathlib import Path


def get_gates_directory():
    """Get the gates directory path."""
    return Path.home() / ".claude" / "gates"


def get_framework_path():
    """Get the framework installation path."""
    return Path.home() / ".claude" / "gates-framework"


def validate_gate_file(gate_path):
    """Validate a single gate file using framework's validate.sh."""
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


def get_server_version():
    """Read the framework version from the repo VERSION file, defaulting to 1.0.0."""
    version_file = Path(__file__).parent.parent / "VERSION"
    try:
        return version_file.read_text().strip() or "1.0.0"
    except Exception:
        return "1.0.0"


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
                "version": get_server_version()
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
    is_temp = False

    if gate_content.startswith("/") or gate_content.startswith("~"):
        expanded = Path(gate_content).expanduser()
        if expanded.exists():
            gate_path = expanded

    # If not a file, create temporary file with content
    if gate_path is None:
        with tempfile.NamedTemporaryFile(mode='w', suffix='.yaml', delete=False) as f:
            f.write(gate_content)
            gate_path = Path(f.name)
            is_temp = True

    try:
        is_valid, error = validate_gate_file(gate_path)

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
    finally:
        # Always clean up temp file
        if is_temp and gate_path:
            try:
                gate_path.unlink()
            except Exception:
                pass  # Ignore cleanup errors


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


def main():
    """Read JSON-RPC 2.0 messages from stdin and respond."""
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            request = json.loads(line)
        except json.JSONDecodeError:
            # Can't recover an id from unparseable input; respond per JSON-RPC spec.
            print(json.dumps({
                "jsonrpc": "2.0",
                "id": None,
                "error": {
                    "code": -32700,
                    "message": "Parse error"
                }
            }, separators=(',', ':')))
            sys.stdout.flush()
            continue

        if not isinstance(request, dict):
            print(json.dumps({
                "jsonrpc": "2.0",
                "id": None,
                "error": {
                    "code": -32600,
                    "message": "Invalid Request"
                }
            }, separators=(',', ':')))
            sys.stdout.flush()
            continue

        try:
            method = request.get("method") or ""
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
        except Exception as e:
            # One bad message must not kill the server loop.
            print(json.dumps({
                "jsonrpc": "2.0",
                "id": request.get("id") if isinstance(request, dict) else None,
                "error": {
                    "code": -32603,
                    "message": f"Internal error: {e}"
                }
            }, separators=(',', ':')))
            sys.stdout.flush()


if __name__ == "__main__":
    main()
