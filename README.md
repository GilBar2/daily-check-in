# daily-check-in

**keep_warm** makes sure your Claude usage clock is already running before
you start working. Claude gives you a 5-hour usage window that begins with
your first message — so if you start cold, you burn part of your window
while you work. This tool quietly sends a tiny message in the background
whenever the old window runs out, so there's always one ticking for you.

**daily-check-in** (in `legacy-fixed-schedule/`) is the older, simpler
version: it just pinged Claude at 8 fixed times a day. Kept around in case
you prefer it — see that folder's README.

## Install

```bash
git clone https://github.com/GilBar2/daily-check-in.git
cd daily-check-in
chmod +x install.sh
./install.sh
```

Requires [Claude Code](https://claude.ai/code) to be installed and authenticated.

## How it works

A macOS LaunchAgent (`com.user.claudewarm.plist`) runs `keep_warm.sh` every 5
minutes. Each run checks whether the last window it opened has expired yet:

- **Window still open** → does nothing. Pinging again wouldn't extend it, so
  there's no point spending a message on it.
- **Window expired** → sends one minimal prompt (`claude --model haiku -p
  "Reply with a single word: OK"`) to open a fresh window, and remembers the
  time it did so.

No chat session is created either way, and the prompt is intentionally
trivial to keep token usage negligible.

### Isolated ping config

The ping runs with `CLAUDE_CONFIG_DIR` pointed at `ping-config/` (deployed to
`~/Library/Application Support/claude-skills/ping-config/`) instead of your
normal `~/.claude/`. That directory holds nothing but a minimal
`settings.json` (`{}`) — no memory index, no skills, no MCP servers, no
hooks. It also runs with `--strict-mcp-config` (no MCP tool schemas loaded)
and a one-line `--system-prompt` in place of the full default system prompt.

This exists because the ping used to inherit your entire interactive
`~/.claude/` config wholesale — memory index, skill descriptions, MCP tool
schemas, and a `SessionStart` hook that expects a human to answer an
`AskUserQuestion` prompt. In a headless ping there's nobody there to answer
it, so it burned a second wasted round-trip on top of the ~25.8k
cache-creation tokens from loading all that context. Isolating the ping's
config dir cut per-ping cost from ~27,300 tokens to well under 3,000, with no
change to your normal interactive Claude Code sessions — `~/.claude/`
(including the `SessionStart` permission-mode hook) is untouched.

**Caveat:** this only knows about windows it opened itself. If you use Claude
directly throughout the day, those messages also open/consume windows the
script has no visibility into — so its tracking can drift from the real
window boundary during active use. It's meant to cover the *gaps* between
your own usage, not replace it.

## Uninstall

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.claudewarm.plist
rm ~/Library/LaunchAgents/com.user.claudewarm.plist
rm ~/Library/Application\ Support/claude-skills/keep_warm.sh
rm ~/Library/Application\ Support/claude-skills/last_ping
```

## Optional: wake reminder

If your Mac is asleep, the LaunchAgent can't run and no window gets opened.
`.github/workflows/wake-reminder.yml` runs in GitHub Actions (independent of
your Mac) and nags your phone via [ntfy.sh](https://ntfy.sh) if it looks like
that's happened.

It checks a few fixed times each morning — 09:30, 09:50, 10:30, 10:50, 11:30,
11:50, 12:30 (Asia/Jerusalem) — for a "heartbeat" that `keep_warm.sh` posts to
ntfy on every successful ping. No heartbeat since midnight UTC → it pushes
"Wake the laptop for daily check-in" to your phone. Heartbeat found → it stays
silent.

To use it, add two repo secrets (`NTFY_ALERT_TOPIC`, `NTFY_HEARTBEAT_TOPIC`)
and set `HEARTBEAT_TOPIC` in `keep_warm.sh`. To change the timezone the
reminder times are anchored to, run `./set-timezone.sh <IANA_timezone>` (e.g.
`./set-timezone.sh Europe/London`) — it recalculates the cron entries and
pushes the update.

*Known limitation:* because pings now happen whenever a window expires rather
than at fixed times, a heartbeat might legitimately not land until later in
the morning if the previous window ran long — which could trigger a nag even
though the Mac is awake and simply waiting. Not yet resolved.
