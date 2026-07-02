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
    """Test validate-gates endpoint response format."""
    import mcp_server

    request = {"id": 1}
    response = mcp_server.handle_validate_gates(request)

    assert response["jsonrpc"] == "2.0"
    assert response["id"] == 1
    assert "result" in response

    content = response["result"]["content"][0]["text"]
    result = json.loads(content)

    # Check response structure
    assert "valid_gates" in result
    assert "invalid_gates" in result
    assert "summary" in result
    assert isinstance(result["valid_gates"], list)
    assert isinstance(result["invalid_gates"], list)
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
