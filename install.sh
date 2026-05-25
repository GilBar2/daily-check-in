#!/bin/bash
set -e

mkdir -p "$HOME/Library/Application Support/claude-skills"

CLAUDE_PATH=$(which claude)
if [ -z "$CLAUDE_PATH" ]; then
  echo "Error: claude binary not found. Install Claude Code first."
  exit 1
fi

sed "s|TARGET_CLAUDE_PATH|$CLAUDE_PATH|g" keep_warm.sh > "$HOME/Library/Application Support/claude-skills/keep_warm.sh"
chmod +x "$HOME/Library/Application Support/claude-skills/keep_warm.sh"

sed "s|SKILLS_DIR|$HOME/Library/Application Support/claude-skills|g" com.user.claudewarm.plist > "$HOME/Library/LaunchAgents/com.user.claudewarm.plist"

launchctl bootout gui/$(id -u) "$HOME/Library/LaunchAgents/com.user.claudewarm.plist" 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.user.claudewarm.plist"

echo "Installed. Pings scheduled at 08:00, 12:30, 17:00, and 21:30."
