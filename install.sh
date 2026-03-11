#!/bin/bash

# Install status-line.sh for Claude Code

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$HOME/.claude/scripts"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$TARGET_DIR"
cp "$SCRIPT_DIR/status-line.sh" "$TARGET_DIR/status-line.sh"
chmod +x "$TARGET_DIR/status-line.sh"

# Add statusLine to settings.json if not present
if [ -f "$SETTINGS" ]; then
    if ! grep -q 'statusLine' "$SETTINGS"; then
        python3 -c "
import json
with open('$SETTINGS') as f:
    s = json.load(f)
s['statusLine'] = {'type': 'command', 'command': '~/.claude/scripts/status-line.sh'}
with open('$SETTINGS', 'w') as f:
    json.dump(s, f, indent=2)
print('Added statusLine to settings.json')
"
    else
        echo "statusLine already configured in settings.json"
    fi
else
    echo '{"statusLine":{"type":"command","command":"~/.claude/scripts/status-line.sh"}}' | python3 -m json.tool > "$SETTINGS"
    echo "Created settings.json with statusLine"
fi

echo "Installed! Restart Claude Code to see the status line."
