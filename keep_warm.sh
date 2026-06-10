#!/bin/bash
CLAUDE_BIN="TARGET_CLAUDE_PATH"

# Optional: ntfy.sh topic to alert your phone when a ping fails (e.g. expired
# login). Leave as the placeholder or empty to disable alerts.
NTFY_TOPIC="NTFY_TOPIC_PLACEHOLDER"

# Optional: separate ntfy topic used as a heartbeat so the cloud wake-reminder
# workflow knows the Mac is awake. Leave as placeholder to disable.
HEARTBEAT_TOPIC="HEARTBEAT_TOPIC_PLACEHOLDER"

OUTPUT=$("$CLAUDE_BIN" -p "Hi" 2>&1)
STATUS=$?

# Treat a non-zero exit OR an auth error in the output as a failure. The CLI
# OAuth token expires periodically and can only be renewed with an interactive
# `claude auth login`, so surfacing this immediately is the whole point.
if [ $STATUS -ne 0 ] || printf '%s' "$OUTPUT" | grep -qiE '401|authenticate'; then
  if [ -n "$NTFY_TOPIC" ] && [ "$NTFY_TOPIC" != "NTFY_TOPIC_PLACEHOLDER" ]; then
    curl -s \
      -H "Title: daily-check-in failed" \
      -H "Priority: high" \
      -H "Tags: warning" \
      -d "Claude ping failed. Re-login: claude auth logout && claude auth login" \
      "https://ntfy.sh/$NTFY_TOPIC" >/dev/null
  fi
  exit 1
fi

# Success — log timestamp and post heartbeat so cloud reminder knows Mac is awake
echo "$(date '+%Y-%m-%d %H:%M:%S') ping OK"
if [ -n "$HEARTBEAT_TOPIC" ] && [ "$HEARTBEAT_TOPIC" != "HEARTBEAT_TOPIC_PLACEHOLDER" ]; then
  curl -s -d "awake" "https://ntfy.sh/$HEARTBEAT_TOPIC" >/dev/null
fi
