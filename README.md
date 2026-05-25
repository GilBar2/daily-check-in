# daily-check-in

A macOS LaunchAgent that sends a daily ping to the Claude API to keep your usage counter active.

Fires at: **08:00, 12:30, 17:00, 21:30**

## Install

```bash
git clone https://github.com/giltombee/daily-check-in.git
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
