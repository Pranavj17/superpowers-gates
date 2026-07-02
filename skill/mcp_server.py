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
