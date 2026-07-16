#!/bin/bash
# Usage: ./set-timezone.sh Europe/London
# Recalculates the wake-reminder cron schedule for the given timezone
# and updates + pushes the GitHub Actions workflow.
set -e

TZ_ARG="${1:-Asia/Jerusalem}"

# Validate timezone and compute UTC cron entries via Python (handles DST correctly)
CRON_LINES=$(python3 - "$TZ_ARG" <<'PYEOF'
import sys
from datetime import date, datetime, time
from zoneinfo import ZoneInfo

tz_name = sys.argv[1]
try:
    tz = ZoneInfo(tz_name)
except Exception:
    print(f"Error: unknown timezone '{tz_name}'", file=sys.stderr)
    sys.exit(1)

targets = [
    (9, 30), (9, 50), (10, 30), (10, 50),
    (11, 30), (11, 50), (12, 30),
]

for h, m in targets:
    local_dt = datetime.combine(date.today(), time(h, m), tzinfo=tz)
    utc_dt = local_dt.utctimetuple()
    print(f"    - cron: '{utc_dt.tm_min:02d} {utc_dt.tm_hour:02d} * * *'   # {h:02d}:{m:02d} {tz_name}")
PYEOF
)

if [ $? -ne 0 ]; then
  exit 1
fi

# Rewrite the workflow file
WORKFLOW=".github/workflows/wake-reminder.yml"

cat > "$WORKFLOW" <<YAML
name: Wake Reminder

# Fires at these local times: 09:30, 09:50, 10:30, 10:50, 11:30, 11:50, 12:30
# Timezone: ${TZ_ARG}
# To change timezone: ./set-timezone.sh <IANA_timezone>  e.g. ./set-timezone.sh Europe/London
on:
  schedule:
${CRON_LINES}
jobs:
  remind:
    runs-on: ubuntu-latest
    steps:
      - name: Check heartbeat and send reminder if needed
        env:
          NTFY_ALERT_TOPIC: \${{ secrets.NTFY_ALERT_TOPIC }}
          NTFY_HEARTBEAT_TOPIC: \${{ secrets.NTFY_HEARTBEAT_TOPIC }}
        run: |
          # Check for today's heartbeat (since midnight UTC)
          SINCE=\$(date -d "today 00:00" +%s)
          MESSAGES=\$(curl -s "https://ntfy.sh/\${NTFY_HEARTBEAT_TOPIC}/json?poll=1&since=\${SINCE}" 2>/dev/null)

          if echo "\$MESSAGES" | grep -q '"event":"message"'; then
            echo "Heartbeat found — Mac is awake. No reminder needed."
          else
            echo "No heartbeat today — sending wake reminder."
            curl -s \\
              -H "Title: Wake the laptop" \\
              -H "Priority: high" \\
              -H "Tags: alarm_clock" \\
              -d "Wake the laptop for daily check-in ☀️" \\
              "https://ntfy.sh/\${NTFY_ALERT_TOPIC}"
          fi
YAML

echo "Updated $WORKFLOW for $TZ_ARG"
echo "Schedule (UTC cron):"
echo "$CRON_LINES"

git add "$WORKFLOW"
git commit -m "Update wake-reminder schedule for $TZ_ARG"
git push

echo ""
echo "Done. Reminders fire at local 09:30–12:30 in $TZ_ARG."
