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

## Uninstall

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.claudewarm.plist
rm ~/Library/LaunchAgents/com.user.claudewarm.plist
rm ~/Library/Application\ Support/claude-skills/keep_warm.sh
```
