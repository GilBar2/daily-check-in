# daily-check-in

**daily-check-in** is good for keeping your Claude usage counter active without manual intervention. It installs a macOS LaunchAgent that silently pings the Claude API eight times a day (08:30, 09:30, 10:30, 12:30, 14:30, 17:00, 19:30, 21:30) using `claude -p "Hi"` — no session created, no interaction required. Useful if your plan resets based on activity and you want to avoid hitting a cold counter mid-work. Set it up once with `./install.sh` and forget it.

## Install

```bash
git clone https://github.com/GilBar2/daily-check-in.git
cd daily-check-in
chmod +x install.sh
./install.sh
```

Requires [Claude Code](https://claude.ai/code) to be installed and authenticated.

## How it works

`keep_warm.sh` runs `claude -p "Hi"` — a single non-interactive API call. No session is created. The LaunchAgent (`com.user.claudewarm.plist`) schedules it via macOS `launchd`.

## Wake reminder (optional)

If the Mac is asleep during check-in times, the LaunchAgent can't fire. `.github/workflows/wake-reminder.yml` runs in GitHub Actions (in the cloud, independent of the Mac) and nags your phone via [ntfy.sh](https://ntfy.sh) when that happens.

It fires at fixed times — 09:30, 09:50, 10:30, 10:50, 11:30, 11:50, 12:30 (Asia/Jerusalem) — and before each nag, checks whether `keep_warm.sh` already posted a "heartbeat" to ntfy today. If a check-in already succeeded, it stays silent; otherwise it pushes "Wake the laptop for daily check-in" to your phone.

Requires two repo secrets (`NTFY_ALERT_TOPIC`, `NTFY_HEARTBEAT_TOPIC`) and enables `HEARTBEAT_TOPIC` in `keep_warm.sh`. To change the timezone the reminder times are anchored to, run `./set-timezone.sh <IANA_timezone>` (e.g. `./set-timezone.sh Europe/London`) — it recalculates the UTC cron entries and pushes the update.

## Uninstall

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.claudewarm.plist
rm ~/Library/LaunchAgents/com.user.claudewarm.plist
rm ~/Library/Application\ Support/claude-skills/keep_warm.sh
```
