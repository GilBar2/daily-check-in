#!/bin/bash
set -e

mkdir -p "$HOME/Library/Application Support/claude-skills"

CLAUDE_PATH=$(which claude)
if [ -z "$CLAUDE_PATH" ]; then
  echo "Error: claude binary not found. Install Claude Code first."
  exit 1
fi

# Optional failure alerts: set NTFY_TOPIC in your environment before running.
# Set HEARTBEAT_TOPIC for the cloud wake-reminder to detect Mac wake-up.
# Leave either unset to disable that feature.
sed -e "s|TARGET_CLAUDE_PATH|$CLAUDE_PATH|g" \
    -e "s|NTFY_TOPIC_PLACEHOLDER|${NTFY_TOPIC:-NTFY_TOPIC_PLACEHOLDER}|g" \
    -e "s|HEARTBEAT_TOPIC_PLACEHOLDER|${HEARTBEAT_TOPIC:-HEARTBEAT_TOPIC_PLACEHOLDER}|g" \
    keep_warm.sh > "$HOME/Library/Application Support/claude-skills/keep_warm.sh"
chmod +x "$HOME/Library/Application Support/claude-skills/keep_warm.sh"

mkdir -p "$HOME/Library/Logs"
sed -e "s|SKILLS_DIR|$HOME/Library/Application Support/claude-skills|g" \
    -e "s|LOG_DIR|$HOME/Library/Logs|g" \
    com.user.claudewarm.plist > "$HOME/Library/LaunchAgents/com.user.claudewarm.plist"

launchctl bootout gui/$(id -u) "$HOME/Library/LaunchAgents/com.user.claudewarm.plist" 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$HOME/Library/LaunchAgents/com.user.claudewarm.plist"

echo "Installed. Checks every 5 minutes; pings Claude only once the previous 5-hour usage window has expired."
