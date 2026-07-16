# daily-check-in

**daily-check-in** is good for keeping your Claude usage window open without manual intervention. Claude's usage limit runs on a fixed 5-hour window that starts at your *first* prompt — later prompts inside an active window don't extend or reset it, so pinging on a fixed schedule wastes quota re-pinging windows that are already open. Instead, this installs a macOS LaunchAgent that checks every 5 minutes whether the previous window has expired, and only then sends a single trivial prompt (`claude --model haiku -p "Reply with a single word: OK"`) to open a fresh one — no session created, minimal tokens spent. Useful if your plan resets based on activity and you want a window open whenever you're likely to start working. Set it up once with `./install.sh` and forget it.

## Install

```bash
git clone https://github.com/GilBar2/daily-check-in.git
cd daily-check-in
chmod +x install.sh
./install.sh
```

Requires [Claude Code](https://claude.ai/code) to be installed and authenticated.

## How it works

The LaunchAgent (`com.user.claudewarm.plist`) runs `keep_warm.sh` every 5 minutes via macOS `launchd` (`StartInterval`). Each run compares the current time against a state file (`last_ping`, next to the script) holding the epoch timestamp of the last window it opened:

- If less than 5 hours have passed, it exits immediately — the previous window is still active and pinging would just burn quota for no timing benefit.
- Once 5 hours have passed, it sends one minimal prompt (`claude --model haiku -p "Reply with a single word: OK"`) to open a fresh window and records the new timestamp.

No session is created either way. A failed ping (e.g. expired login) does **not** update the state file, so the next 5-minute check retries rather than waiting a full window.

**Caveat:** this only tracks windows opened by this script. Any Claude usage you do yourself also opens/consumes windows the script doesn't know about, so the state file can under- or over-estimate the real window boundary if you're actively using Claude outside of this automation.

## Wake reminder (optional)

If the Mac is asleep when a window needs to be reopened, the LaunchAgent can't fire. `.github/workflows/wake-reminder.yml` runs in GitHub Actions (in the cloud, independent of the Mac) and nags your phone via [ntfy.sh](https://ntfy.sh) when that happens.

It fires at fixed times — 09:30, 09:50, 10:30, 10:50, 11:30, 11:50, 12:30 (Asia/Jerusalem) — and before each nag, checks whether `keep_warm.sh` already posted a "heartbeat" to ntfy since midnight UTC. If a check-in already succeeded, it stays silent; otherwise it pushes "Wake the laptop for daily check-in" to your phone.

**Note:** since pings are no longer scheduled at fixed times, a heartbeat might legitimately not land until later in the morning if the previous day's window ran late — the reminder could nag even though the Mac is awake and simply waiting out an active window. Not yet resolved; flagging for a future pass if it turns out to be noisy in practice.

Requires two repo secrets (`NTFY_ALERT_TOPIC`, `NTFY_HEARTBEAT_TOPIC`) and enables `HEARTBEAT_TOPIC` in `keep_warm.sh`. To change the timezone the reminder times are anchored to, run `./set-timezone.sh <IANA_timezone>` (e.g. `./set-timezone.sh Europe/London`) — it recalculates the UTC cron entries and pushes the update.

## Rollback to the original fixed schedule

The previous approach — ping at 8 fixed times a day, no window-expiry check —
is preserved under [`legacy-fixed-schedule/`](legacy-fixed-schedule/) in case
the window-based redesign above doesn't work out for you. See that folder's
README for how to reinstall it.

## Uninstall

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.claudewarm.plist
rm ~/Library/LaunchAgents/com.user.claudewarm.plist
rm ~/Library/Application\ Support/claude-skills/keep_warm.sh
rm ~/Library/Application\ Support/claude-skills/last_ping
```
