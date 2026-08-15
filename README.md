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

A macOS LaunchAgent (`com.user.claudewarm.plist`) runs `keep_warm.sh` every 15
minutes. Each run checks whether the last window it opened has expired yet:

- **Window still open** → does nothing. Pinging again wouldn't extend it, so
  there's no point spending a message on it.
- **Window expired** → sends one minimal prompt (`claude --model haiku -p
  "Reply with a single word: OK"`) to open a fresh window, and remembers the
  time it did so.

No chat session is created either way, and the prompt is intentionally
trivial to keep token usage negligible.

### Why the ping runs with so many flags

The ping is a one-word health check, but by default Claude Code assembles a
full interactive context for it: your memory index, every skill description,
all MCP tool schemas, and any `SessionStart` hook. That cost **~27,300 tokens
to say "OK"** — and if the hook expects a human (e.g. an `AskUserQuestion`
permission prompt), the headless ping also burns a wasted extra round-trip
failing to answer it.

So the ping is invoked with:

| Flag | Removes |
|---|---|
| `--settings '{"hooks":{}}'` | hooks, for this invocation only |
| `--disable-slash-commands` | all skill definitions |
| `--strict-mcp-config` | all MCP tool schemas |
| `--exclude-dynamic-system-prompt-sections` | dynamic system-prompt blocks |
| `--system-prompt "..."` | replaces the full default system prompt |

Measured 2026-08-06: **27,304 → ~1,500 tokens cold, <300 warm** (~94% less).
Your normal interactive sessions are completely unaffected — `~/.claude/`,
including any `SessionStart` hook, is never modified.

**Do not add `--bare` or `--setting-sources ''`**, and do not run the ping
under an isolated `CLAUDE_CONFIG_DIR`. All three were tested and each one
independently breaks authentication (`Not logged in · Please run /login`),
even though the credentials themselves live in the macOS Keychain.

### Why the guard uses a glob

The topic guards are written as `case "$NTFY_TOPIC" in ""|*PLACEHOLDER*)` and
**not** as `[ "$NTFY_TOPIC" != "NTFY_TOPIC_PLACEHOLDER" ]`.

`install.sh` substitutes the sentinel with `sed ... /g`, which rewrote *every*
occurrence in the file — including the one inside the comparison. On any
installed copy the guard became `[ "$topic" != "<your real topic>" ]`, which is
always false, so **the ntfy alert and the heartbeat never fired at all.** This
was silent: the failure path ran, the `curl` was simply skipped. Discovered and
fixed 2026-08-06. The glob survives the `sed` because only the full literal
sentinel is matched.

### Failure alerts are throttled

A failed ping costs zero tokens — the CLI gives up before it reaches the API —
so the script keeps retrying on every tick until it succeeds. But it only
sends an ntfy alert on the **first** failure and then roughly hourly
(`ALERT_EVERY`), tracked in a `fail_count` state file that is cleared on
success. Without this, an expired login produced one high-priority phone
alert on every single tick indefinitely.

`ALERT_EVERY` is expressed in *ticks*, not minutes, so it must be kept in step
with `StartInterval` in the plist — the two together should work out to about
an hour (currently 4 ticks x 900s).

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
