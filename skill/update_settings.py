#!/usr/bin/env python3
"""
Auto-register hook gates in .claude/settings.json.
Usage: python3 update_settings.py --auto
"""

import json
import shutil
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

    # Back up existing settings before overwriting, if present
    if settings_path.exists():
        backup_path = settings_path.with_suffix(settings_path.suffix + ".bak")
        shutil.copy2(settings_path, backup_path)

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
