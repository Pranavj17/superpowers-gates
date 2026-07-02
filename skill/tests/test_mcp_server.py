#!/usr/bin/env python3
"""
Tests for MCP server tools and prompts.

Hermetic tests that exercise the real framework/lib/gates/validate.sh against
a copy of the repo's actual framework code, by monkeypatching
get_gates_directory / get_framework_path to point into a tmp_path sandbox.
"""

import glob
import json
import shutil
import sys
import tempfile
from pathlib import Path

import pytest

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

import mcp_server  # noqa: E402

REPO_ROOT = Path(__file__).parent.parent.parent

VALID_GATE_YAML = """\
name: "test-gate"
description: "A valid test gate"
hook: "PreToolUse"
matcher: "Bash"
condition: |
  [[ "$TOOL" == "Bash" ]]
decision: "ask"
message: "Test message"
"""

# Missing the required 'decision' field.
INVALID_GATE_YAML = """\
name: "test-gate"
description: "An invalid test gate missing decision"
hook: "PreToolUse"
matcher: "Bash"
condition: |
  [[ "$TOOL" == "Bash" ]]
message: "Test message"
"""


@pytest.fixture
def framework_env(tmp_path, monkeypatch):
    """Point mcp_server at a tmp_path sandbox containing a real framework/ copy."""
    framework_install = tmp_path / "framework-install"
    shutil.copytree(REPO_ROOT / "framework", framework_install / "framework")

    gates_dir = tmp_path / "gates"
    gates_dir.mkdir()

    monkeypatch.setattr(mcp_server, "get_framework_path", lambda: framework_install)
    monkeypatch.setattr(mcp_server, "get_gates_directory", lambda: gates_dir)

    return {"framework_install": framework_install, "gates_dir": gates_dir}


def test_validate_gates_empty_gates_dir_reports_zero(framework_env):
    """validate-gates against an empty (but existing) gates dir reports 0 gates."""
    request = {"id": 1}
    response = mcp_server.handle_validate_gates(request)

    assert response["jsonrpc"] == "2.0"
    assert response["id"] == 1
    assert "result" in response

    content = response["result"]["content"][0]["text"]
    result = json.loads(content)

    assert result["valid_gates"] == []
    assert result["invalid_gates"] == []
    assert result["summary"] == "0/0 gates valid"
    print("✅ test_validate_gates_empty_gates_dir_reports_zero passed")


def test_validate_gate_valid_yaml_returns_valid_true(framework_env):
    """A valid gate YAML string, validated via the real validate.sh, is reported valid."""
    request = {"id": 1, "params": {"name": "validate-gate", "arguments": {"gate_content": VALID_GATE_YAML}}}
    response = mcp_server.handle_validate_gate(request)

    content = response["result"]["content"][0]["text"]
    result = json.loads(content)

    assert result["valid"] is True, result
    print("✅ test_validate_gate_valid_yaml_returns_valid_true passed")


def test_validate_gate_invalid_yaml_returns_valid_false(framework_env):
    """A gate missing the required 'decision' field is reported invalid."""
    request = {"id": 1, "params": {"name": "validate-gate", "arguments": {"gate_content": INVALID_GATE_YAML}}}
    response = mcp_server.handle_validate_gate(request)

    content = response["result"]["content"][0]["text"]
    result = json.loads(content)

    assert result["valid"] is False
    assert "error" in result
    print("✅ test_validate_gate_invalid_yaml_returns_valid_false passed")


def test_validate_gate_cleans_up_temp_file(framework_env):
    """Validating YAML-string content leaves no temp file behind afterward."""
    pattern = str(Path(tempfile.gettempdir()) / "*.yaml")
    before = set(glob.glob(pattern))

    request = {"id": 1, "params": {"name": "validate-gate", "arguments": {"gate_content": VALID_GATE_YAML}}}
    mcp_server.handle_validate_gate(request)

    after = set(glob.glob(pattern))
    assert after == before, f"temp file leaked: {after - before}"
    print("✅ test_validate_gate_cleans_up_temp_file passed")


def test_validate_gate_empty_input():
    """Test validate-gate with empty gate_content."""
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
    request = {"id": 1}
    response = mcp_server.handle_list_gates_prompt(request)

    assert response["jsonrpc"] == "2.0"
    assert "result" in response

    result = response["result"]
    assert "messages" in result
    assert len(result["messages"]) > 0
    print("✅ test_list_gates_prompt passed")


if __name__ == "__main__":
    # Plain-script fallback: run the fixture-free tests directly. The
    # fixture-based tests above (framework_env-dependent) require pytest;
    # run via `python3 -m pytest skill/tests/ -v` for the full suite.
    test_validate_gate_empty_input()
    test_tools_list()
    test_prompts_list()
    test_create_gate_prompt()
    test_list_gates_prompt()

    print("\n✅ All plain-script tests passed! Run `python3 -m pytest skill/tests/ -v` for the full suite.")
