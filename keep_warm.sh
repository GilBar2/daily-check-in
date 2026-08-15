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

# Counts consecutive failures so a broken login doesn't fire an ntfy alert
# on every tick forever. Removed on success. See "alert throttle" below.
FAIL_FILE="SKILLS_DIR/fail_count"
# Keep this in step with StartInterval in com.user.claudewarm.plist:
# ALERT_EVERY * StartInterval should stay ~1 hour. At the current 900s tick,
# 4 ticks = 1 hour.
ALERT_EVERY=4

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

# The ping is a one-word health check, so it needs none of the context Claude
# Code normally assembles for an interactive session. Left unstripped it
# inherits the user's memory index, every skill description, all MCP tool
# schemas and the SessionStart hook — ~27.3k tokens to say "OK". These flags
# cut that to ~1.5k cold and <300 warm (measured 2026-08-06).
#
# --no-session-persistence stops the ping writing a session transcript per
# tick. Those are pure clutter here, and a failing ping writes one too: an
# auth outage on 2026-08-13..15 left 350 junk transcripts in
# ~/.claude/projects/-/ having never made a single API call.
#
# Do NOT add --bare or --setting-sources '': each independently breaks auth
# ("Not logged in · Please run /login"). Running under an isolated
# CLAUDE_CONFIG_DIR breaks auth the same way. See the PRD for the test matrix.
OUTPUT=$("$CLAUDE_BIN" \
  --model haiku \
  --no-session-persistence \
  --strict-mcp-config \
  --disable-slash-commands \
  --exclude-dynamic-system-prompt-sections \
  --settings '{"hooks":{}}' \
  --system-prompt "Health check. Reply with exactly one word." \
  -p "Reply with a single word: OK" 2>&1)
STATUS=$?

# Treat a non-zero exit OR an auth error in the output as a failure. The CLI
# OAuth token expires periodically and can only be renewed with an interactive
# `claude auth login`, so surfacing this is the whole point. The pattern
# includes "Not logged in" / "/login" because that — not a literal "401" — is
# what the CLI actually prints for an expired token.
if [ $STATUS -ne 0 ] || printf '%s' "$OUTPUT" | grep -qiE '401|authenticate|Not logged in|/login'; then
  FAILS=0
  if [ -f "$FAIL_FILE" ]; then
    FAILS=$(cat "$FAIL_FILE" 2>/dev/null || echo 0)
  fi
  FAILS=$((FAILS + 1))
  echo "$FAILS" > "$FAIL_FILE"

  # Alert throttle: a failed ping costs no tokens (the CLI gives up before it
  # reaches the API), so retrying on every tick is harmless — but alerting on
  # every tick is not. Notify on the first failure, then roughly hourly.
  if [ "$FAILS" -eq 1 ] || [ $((FAILS % ALERT_EVERY)) -eq 0 ]; then
    # NB: match the *glob* "*PLACEHOLDER*", never the literal sentinel.
    # install.sh seds the sentinel globally, so a literal comparison here gets
    # rewritten into "$NTFY_TOPIC" != "<your real topic>" — always false, which
    # silently disabled every alert. See README "Why the guard uses a glob".
    case "$NTFY_TOPIC" in
      ""|*PLACEHOLDER*) ;;
      *)
      curl -s \
        -H "Title: daily-check-in failed" \
        -H "Priority: high" \
        -H "Tags: warning" \
        -d "Claude ping failed ($FAILS in a row). Re-login: claude auth logout && claude auth login" \
        "https://ntfy.sh/$NTFY_TOPIC" >/dev/null
        ;;
    esac
  fi
  echo "$(date '+%Y-%m-%d %H:%M:%S') ping FAILED ($FAILS in a row): $(printf '%s' "$OUTPUT" | head -1)"
  # Don't update STATE_FILE — a failed ping never opened a window, so the
  # next check should retry rather than waiting another 5 hours.
  exit 1
fi

# Success — this ping opened a fresh window. Record it, log, and heartbeat.
echo "$NOW" > "$STATE_FILE"
rm -f "$FAIL_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') ping OK (new window opened)"
# Same glob guard as the alert above — a literal sentinel comparison would be
# rewritten by install.sh's sed and silently disable the heartbeat.
case "$HEARTBEAT_TOPIC" in
  ""|*PLACEHOLDER*) ;;
  *) curl -s -d "awake" "https://ntfy.sh/$HEARTBEAT_TOPIC" >/dev/null ;;
esac
