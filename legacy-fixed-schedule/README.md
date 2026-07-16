# Legacy: fixed 8x/day schedule

This is the original `daily-check-in` approach, preserved here in case the
window-based redesign (now the repo's default — see the top-level README)
doesn't work out and you want to roll back.

**What it does:** pings `claude -p "Hi"` at eight fixed times a day (08:30,
09:30, 10:30, 12:30, 14:30, 17:00, 19:30, 21:30), regardless of whether a
5-hour usage window is already open. Simpler, but wastes pings that land
inside an already-open window and can leave gaps of up to ~1.5h between a
window expiring and the next scheduled ping.

## Rolling back

```bash
cd legacy-fixed-schedule
NTFY_TOPIC=<your-topic> HEARTBEAT_TOPIC=<your-heartbeat-topic> ./install.sh
```

This reinstalls the LaunchAgent using this folder's `keep_warm.sh` and
`com.user.claudewarm.plist`, overwriting the currently-installed (window-based)
version at `~/Library/Application Support/claude-skills/keep_warm.sh` and
`~/Library/LaunchAgents/com.user.claudewarm.plist`.

To go back to the redesigned version afterward, run `./install.sh` from the
repo root instead.
