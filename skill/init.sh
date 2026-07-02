#!/bin/bash
set -euo pipefail

GATES_FRAMEWORK="$HOME/.claude/gates-framework"
REPO_URL="https://github.com/Pranavj17/superpowers-gates"

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
cp "$GATES_FRAMEWORK/framework/lib/examples"/*.yaml "$HOME/.claude/gates/"

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
if [ -t 0 ]; then
  read -p "Register hook? (y/n/m): " setup_choice
else
  setup_choice="n"
  echo "Non-interactive mode: skipping hook auto-registration."
  echo "Run: python3 \"\$GATES_FRAMEWORK/skill/update_settings.py\" --auto"
fi

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
