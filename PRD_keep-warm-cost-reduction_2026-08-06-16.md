# PRD — keep_warm.sh cost reduction

**Date:** 2026-08-06 16:45
**Repo:** `github.com/GilBar2/daily-check-in` (local: `~/daily-check-in`, on `main` @ `a06c900`)
**Status:** Ready for implementation

---

## 1. Problem

`keep_warm.sh` fires a one-word Haiku prompt (`"Reply with a single word: OK"`) once per expired 5-hour usage window. That trivial prompt currently costs **~27,300 tokens** per successful ping.

Measured from the 2026-08-06 13:00:43 ping (session `3d5e32ba-53cf-4cf1-ab1b-0b397ee5d6d8`):

| Request | Model | cache_creation | output |
|---|---|---|---|
| `req_011CdmJNpUB94SN8CAZgfLiN` | haiku-4-5 | 25,820 | 518 |
| `req_011CdmJPKFYVbFxDNiRNd82q` | haiku-4-5 | 504 | 462 |
| **Total** | | **26,324** | **980** |

> Note: each `requestId` appears twice in the `.jsonl`; that is duplicate logging of one API call, not two calls. Do not double-count.

### 1.1 Root causes

1. **Full user context is loaded into every ping.** The ping inherits `~/.claude/` wholesale: `MEMORY.md` (30+ entries), all skill descriptions, MCP server tool schemas, and hook definitions. That is the ~25.8k cache-creation write.
2. **A `SessionStart` hook hijacks the ping.** `~/.claude/settings.json` defines a `SessionStart` hook injecting: *"Before doing anything else this session, ask the user via AskUserQuestion which permission mode they want…"*. In a headless `-p` run there is nobody to answer, so the ping burns a second round-trip (the 504/462 request) on an `AskUserQuestion` call that errors with `"Answer questions?"` before it can answer `OK`.

### 1.2 Explicitly out of scope

The 17 pings that failed today (10:54–12:55) returned `401 OAuth access token has expired`. Those are `<synthetic>` client-side errors with `requestId: None` and **cost 0 tokens** — they never reached the API. Token cost is *not* the issue there. The retry-storm behaviour and OAuth expiry are a separate concern; see §7.

---

## 2. Goal

Reduce the per-ping cost from ~27,300 tokens to **under 3,000 tokens** (target: <1,500) without changing:

- the ping's function (verify auth is alive + open a fresh 5-hour window),
- the ntfy alert/heartbeat behaviour,
- anything about the user's normal interactive Claude Code sessions.

**Non-goal:** do not delete or weaken the `SessionStart` permission-mode hook for interactive use. The user wants it.

---

## 3. Constraints & verified environment facts

1. `CLAUDE_CONFIG_DIR` is a supported env var (string present in the CLI binary, v2.1.158).
2. ~~**Auth lives in the macOS Keychain** under service `Claude Code-credentials`, *not* in `~/.claude`. An isolated config dir therefore inherits working auth — no re-login needed.~~ **DISPROVEN 2026-08-06 by testing — see §4.0.** The Keychain entry exists, but a Keychain secret alone is not sufficient; an isolated `CLAUDE_CONFIG_DIR` reports `Not logged in · Please run /login`.
3. Available cost-relevant CLI flags (v2.1.158): `--settings`, `--system-prompt`, `--append-system-prompt`, `--strict-mcp-config`, `--mcp-config`, `--no-session-persistence`, `--disallowedTools`, `--model`.
4. Binary path is pinned in the script: `/Users/giltombee/.nvm/versions/node/v24.14.1/bin/claude`.
5. The script exists in **three** places that must stay in sync:
   - `~/daily-check-in/keep_warm.sh` (repo, current version)
   - `~/daily-check-in/legacy-fixed-schedule/keep_warm.sh` (rollback copy — **do not modify**, per prior explicit user request)
   - `~/Library/Application Support/claude-skills/keep_warm.sh` (live, run by launchd)
6. launchd job: `com.user.claudewarm`, `StartInterval` 300s, plist at `~/Library/LaunchAgents/com.user.claudewarm.plist`.
7. State file `~/Library/Application Support/claude-skills/last_ping` holds the epoch of the last window opened; `WINDOW_SECONDS=18000`.

---

## 4. Solution

### 4.0 REVISION 2026-08-06 17:00 — §4.1/§4.2 below are SUPERSEDED

The original plan (isolate via `CLAUDE_CONFIG_DIR`) **does not work**. Implementation was attempted on branch `cheap-ping-dev` (`0061ae2`) and blocked at PRD §6.1. Verified by direct testing:

| Test | Config | Result |
|---|---|---|
| A | empty isolated `CLAUDE_CONFIG_DIR` | `Not logged in · Please run /login` |
| B | isolated + `oauthAccount`/`userID`/`hasCompletedOnboarding` copied in | `Not logged in` |
| C | isolated + **entire** real `.claude.json` copied in | `Not logged in` |

So `.claude.json` is not the gate either — auth is bound to the default config dir more deeply than account-linkage state. **Abandon the isolated-config-dir approach.**

Two further flags were found to independently break auth the same way: `--bare` and `--setting-sources ''`. Do not use either.

### 4.0.1 REPLACEMENT — verified working

Keep the default config dir (so auth works) and strip context via flags:

```bash
OUTPUT=$("$CLAUDE_BIN" --model haiku \
  --strict-mcp-config \
  --disable-slash-commands \
  --exclude-dynamic-system-prompt-sections \
  --settings '{"hooks":{}}' \
  --system-prompt "Health check. Reply with exactly one word." \
  -p "Reply with a single word: OK" 2>&1)
STATUS=$?
```

| Flag | Removes |
|---|---|
| `--settings '{"hooks":{}}'` | the `SessionStart` permission-mode hook, for this invocation only |
| `--disable-slash-commands` | all skill definitions |
| `--strict-mcp-config` | all MCP tool schemas |
| `--exclude-dynamic-system-prompt-sections` | dynamic system-prompt blocks |
| `--system-prompt` | replaces the full Claude Code system prompt |

**Measured results** (deduped by `requestId`, output confirmed `OK` every run):

| Run | Tokens |
|---|---|
| Baseline (current script) | 27,304 |
| Cold cache | **1,497** |
| Warm cache | 251, then 77 |

**94.5% reduction cold; ~99% warm.** Meets §2 target (<3,000) and the stretch goal (<1,500).

### 4.0.2 Required hardening

Testing showed the failure-detection grep `401|authenticate` **does not match** the actual string `Not logged in · Please run /login`. Detection currently survives only because `STATUS -ne 0` catches it. Widen the pattern:

```bash
grep -qiE '401|authenticate|Not logged in|/login'
```

### 4.1 Create a dedicated, minimal config dir — SUPERSEDED, DO NOT IMPLEMENT

Path: `~/Library/Application Support/claude-skills/ping-config/`

Contents: a `settings.json` containing **no hooks, no MCP servers, no skills, no memory**. Minimal valid file:

```json
{}
```

This directory must **not** contain `MEMORY.md`, a `projects/` tree, `skills/`, or `plugins/`.

### 4.2 Rewrite the invocation

Replace:

```bash
OUTPUT=$("$CLAUDE_BIN" --model haiku -p "Reply with a single word: OK" 2>&1)
```

with:

```bash
OUTPUT=$(CLAUDE_CONFIG_DIR="$PING_CONFIG_DIR" "$CLAUDE_BIN" \
  --model haiku \
  --strict-mcp-config \
  --no-session-persistence \
  --system-prompt "You are a health check. Reply with exactly one word." \
  -p "Reply with a single word: OK" 2>&1)
STATUS=$?
```

Rationale per flag:

| Flag | Saves |
|---|---|
| `CLAUDE_CONFIG_DIR=…` | memory index, skill descriptions, hooks — the bulk of the 25.8k |
| `--strict-mcp-config` (with no `--mcp-config`) | all MCP tool schemas |
| `--system-prompt` | replaces the full default Claude Code system prompt with one line |
| `--no-session-persistence` | stops writing a `.jsonl` per ping (18 junk files were created today) |

`--model haiku` stays. Keeping `2>&1` and `$?` capture is required — the existing 401/`authenticate` detection depends on both.

### 4.3 Preserve existing failure semantics

The current logic must survive verbatim:

- non-zero exit **or** output matching `401|authenticate` ⇒ ntfy alert to `$NTFY_TOPIC`, **do not** update `last_ping`, `exit 1`.
- success ⇒ write epoch to `last_ping`, append `"<ts> ping OK (new window opened)"` to the log, POST `awake` to `$HEARTBEAT_TOPIC`.

Both ntfy topic values must be carried over unchanged.

---

## 5. Implementation steps

1. Branch the repo. Per the user's ref-naming rule: branch names take a `-dev` suffix; bare `vX.Y` is reserved for release tags. Use `cheap-ping-dev`.
2. Create `ping-config/settings.json` as a **template in the repo** (e.g. `ping-config/settings.json`) so the repo stays the source of truth, mirroring how `keep_warm.sh` is templated.
3. Edit `~/daily-check-in/keep_warm.sh` per §4.2, adding a `PING_CONFIG_DIR` variable near the other path constants at the top.
4. Do **not** touch `legacy-fixed-schedule/`.
5. Update the README to document the isolated config dir and why it exists.
6. Deploy: copy the updated script to `~/Library/Application Support/claude-skills/keep_warm.sh`, and create the live `ping-config/` dir with its `settings.json`.
7. Do **not** reload launchd yet — verify first (§6).

---

## 6. Verification (required before declaring done)

Run each step and record actual output. Do not infer results.

1. **Auth check (the main risk).** Run the new invocation manually with the isolated config dir. Confirm it returns `OK` and *not* a 401. If it 401s, the isolated dir does not inherit Keychain auth — **stop and report**, do not proceed.
2. **Cost measurement.** Because `--no-session-persistence` suppresses the log, measure in two passes:
   - Pass A: run the new invocation **with** persistence and with `CLAUDE_CONFIG_DIR` pointed at the isolated dir; read the resulting `.jsonl` under that dir and sum `cache_creation_input_tokens` + `output_tokens`, **deduplicating by `requestId`**.
   - Pass B: confirm the final form (with `--no-session-persistence`) still returns `OK`.
3. **Report the before/after number.** Baseline is 27,304 tokens. State the measured new figure. If it is not under 3,000, say so plainly rather than declaring success.
4. **No-op path.** Run the script directly while `last_ping` is recent; confirm it exits 0 immediately without calling the API.
5. **Failure path.** Confirm by inspection (not by breaking auth) that the 401 branch still reaches the ntfy `curl` and skips the `last_ping` write.
6. **Interactive sessions untouched.** Confirm `~/.claude/settings.json` is byte-identical to before — the `SessionStart` hook must remain intact.

---

## 7. Follow-up, not in this change

1. **OAuth expiry.** 17 consecutive pings failed on an expired token before one succeeded at 13:00. Worth understanding why the token lapsed and whether the ntfy alert actually fired.
2. **Retry storm.** On failure the script deliberately does not update `last_ping`, so it retries every 5 minutes indefinitely. Free in tokens, but noisy. Consider a backoff or a max-consecutive-failures cap.
3. **`wake-reminder.yml`** still assumes fixed ping times (known open item from the 2026-07-16 redesign).

---

## 8. Acceptance criteria

- [ ] Per-ping cost measured at **< 3,000 tokens** (from 27,304), with the measurement shown.
- [ ] Ping still returns `OK` and still detects auth failure.
- [ ] `~/.claude/settings.json` unmodified; interactive `SessionStart` hook still fires.
- [ ] `legacy-fixed-schedule/` unmodified.
- [ ] Repo and live copies in sync; changes committed on `cheap-ping-dev`.
- [ ] launchd **not** reloaded — left for the user to approve.
