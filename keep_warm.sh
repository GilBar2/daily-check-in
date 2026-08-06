#!/bin/bash
CLAUDE_BIN="TARGET_CLAUDE_PATH"

# Optional: ntfy.sh topic to alert your phone when a ping fails (e.g. expired
# login). Leave as the placeholder or empty to disable alerts.
NTFY_TOPIC="NTFY_TOPIC_PLACEHOLDER"

# Optional: separate ntfy topic used as a heartbeat so the cloud wake-reminder
# workflow knows the Mac is awake. Leave as placeholder to disable.
HEARTBEAT_TOPIC="HEARTBEAT_TOPIC_PLACEHOLDER"

# Tracks the epoch timestamp of the last successful ping (i.e. the last time
# we know a fresh 5-hour usage window was opened). Claude's usage window is
# fixed from the first prompt in it — later prompts inside an active window
# don't extend or reset it — so there's no point pinging more than once per
# window. This script runs frequently (see plist) and only actually calls
# Claude once the previous window should have expired.
STATE_FILE="SKILLS_DIR/last_ping"
WINDOW_SECONDS=18000  # 5 hours

# Isolated, minimal Claude config dir for the ping only. Keeps the ping from
# inheriting the interactive ~/.claude config (memory index, skills, MCP
# server schemas, hooks) — that inheritance was costing ~25.8k cache-creation
# tokens per ping for zero benefit. See ping-config/settings.json in the repo.
PING_CONFIG_DIR="SKILLS_DIR/ping-config"

NOW=$(date +%s)
LAST=0
if [ -f "$STATE_FILE" ]; then
  LAST=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
fi

ELAPSED=$((NOW - LAST))
if [ "$ELAPSED" -lt "$WINDOW_SECONDS" ]; then
  # Previous window is still active — pinging now would be wasted quota.
  exit 0
fi

OUTPUT=$(CLAUDE_CONFIG_DIR="$PING_CONFIG_DIR" "$CLAUDE_BIN" \
  --model haiku \
  --strict-mcp-config \
  --no-session-persistence \
  --system-prompt "You are a health check. Reply with exactly one word." \
  -p "Reply with a single word: OK" 2>&1)
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
  # Don't update STATE_FILE — a failed ping never opened a window, so the
  # next check should retry rather than waiting another 5 hours.
  exit 1
fi

# Success — this ping opened a fresh window. Record it, log, and heartbeat.
echo "$NOW" > "$STATE_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') ping OK (new window opened)"
if [ -n "$HEARTBEAT_TOPIC" ] && [ "$HEARTBEAT_TOPIC" != "HEARTBEAT_TOPIC_PLACEHOLDER" ]; then
  curl -s -d "awake" "https://ntfy.sh/$HEARTBEAT_TOPIC" >/dev/null
fi
