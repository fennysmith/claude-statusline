#!/bin/sh
# Installer for claude-statusline.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/fennysmith/claude-statusline/main/install.sh | sh
#
# Environment:
#   CLAUDE_STATUSLINE_REF   git ref to install from (default: main)
#   CLAUDE_CONFIG_DIR       Claude config dir (default: $HOME/.claude)

set -e

REPO="${CLAUDE_STATUSLINE_REPO:-fennysmith/claude-statusline}"
REF="${CLAUDE_STATUSLINE_REF:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${REF}"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SCRIPT_PATH="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

echo "Downloading statusline.sh -> $SCRIPT_PATH"
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RAW/statusline.sh" -o "$SCRIPT_PATH"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$SCRIPT_PATH" "$RAW/statusline.sh"
else
    echo "error: need curl or wget" >&2
    exit 1
fi
chmod +x "$SCRIPT_PATH"

# Check optional deps
missing=""
command -v jq   >/dev/null 2>&1 || missing="$missing jq"
command -v curl >/dev/null 2>&1 || missing="$missing curl"
if [ -n "$missing" ]; then
    echo "warning: missing dependencies for full functionality:$missing"
fi

CMD="bash $SCRIPT_PATH"

if [ -f "$SETTINGS" ]; then
    if ! command -v jq >/dev/null 2>&1; then
        echo "error: jq required to merge into existing settings.json" >&2
        echo "       install jq, or manually add:" >&2
        echo "       \"statusLine\": {\"type\": \"command\", \"command\": \"$CMD\"}" >&2
        exit 1
    fi
    tmp=$(mktemp)
    jq --arg cmd "$CMD" \
       '.statusLine = {type: "command", command: $cmd}' \
       "$SETTINGS" > "$tmp"
    mv "$tmp" "$SETTINGS"
    echo "Updated $SETTINGS"
else
    cat > "$SETTINGS" <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "$CMD"
  }
}
EOF
    echo "Created $SETTINGS"
fi

echo
echo "Done. Restart Claude Code (or start a new session) to see the statusline."
echo "Set ANTHROPIC_API_KEY in your shell to enable the monthly usage segment."
