# claude-usage-tracker

Records how much of each Claude Code usage limit was consumed at the end of
every rolling **5-hour** and **7-day** window, giving a durable history that
the statusline snapshot (overwritten on every render) doesn't keep.

Note: no data source exposes absolute token counts against the limit — Claude
only reports **percentage of limit used** plus the reset time, so that is what
gets recorded. (Transcript JSONLs contain token fields, but their
`output_tokens` are known placeholders — anthropics/claude-code#25941.)

## How it works

A systemd user timer runs `bin/claude-usage-tracker` every 5 minutes. Each run:

1. Fetches current utilization — primary source is the **undocumented** OAuth
   usage endpoint; fallback is the statusline snapshot file (see below).
2. Appends the sample to `history.jsonl`.
3. Compares each window's `resets_at` against the one stored in `state.json`.
   If it advanced, the window rolled over: the *previous* sample was the last
   observation of the old cycle and is written to `cycles.csv` as that cycle's
   closing row (deduped per cycle, so a row is emitted exactly once — even if
   the machine slept through the reset and the sample is hours stale).
4. If a reset lands before the next timer fire, the run sleeps until ~60s
   before it and takes one extra sample, so closing values are normally ≤60s
   from the true cycle end. `sample_age_seconds` in the CSV reports staleness.

### Data sources

Primary — OAuth usage endpoint (**undocumented; may change without notice**):

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken from ~/.claude/.credentials.json>
anthropic-beta: oauth-2025-04-20
User-Agent: claude-code/2.1.0    # required — omitting it causes persistent 429s
```

Calls are kept ≥180s apart. The tracker **never refreshes the OAuth token**
itself (that could rotate tokens out from under the Claude Code CLI); if the
token is expired it falls back, and running Claude Code refreshes it.

Fallback — `~/.claude/abtop-rate-limits.json`, the last statusline snapshot,
accepted only if less than 6h old. If both sources fail, a `"source":"miss"`
line is logged to history and no CSV row is affected.

## Files

| Path | What |
|---|---|
| `~/.local/share/claude-usage-tracker/history.jsonl` | one line per poll |
| `~/.local/share/claude-usage-tracker/cycles.csv` | one row per completed cycle |
| `~/.local/share/claude-usage-tracker/state.json` | tracker state (last sample per window, dedupe ring) |

`cycles.csv` columns:

```
window,cycle_end_epoch,cycle_end_iso,pct_used,sampled_at_epoch,sampled_at_iso,sample_age_seconds,source
5h,1788686400,2026-09-06T10:40:00Z,42.3,1788686345,2026-09-06T10:39:05Z,55,api
```

`history.jsonl` lines:

```json
{"ts": 1788669213.4, "ts_iso": "2026-09-06T05:53:33Z", "source": "api",
 "error": null,
 "windows": {"5h": {"pct": 4.0, "resets_at": 1788686400, "resets_at_iso": "..."},
             "7d": {"pct": 0.0, "resets_at": 1788901200, "resets_at_iso": "..."}},
 "raw": { "...verbatim payload, incl. seven_day_sonnet / extra_usage..." }}
```

## Install / uninstall

```bash
./install.sh              # copies units to ~/.config/systemd/user, enables timer
./install.sh --uninstall  # disables timer, removes units, keeps data
```

Check on it:

```bash
systemctl --user list-timers claude-usage-tracker.timer
journalctl -t claude-usage-tracker -f   # (--user -u filtering doesn't match on this journald setup)
column -s, -t ~/.local/share/claude-usage-tracker/cycles.csv
```

## Testing hooks

```bash
CUT_DATA_DIR=/tmp/cut-test bin/claude-usage-tracker      # sandbox the data dir
CUT_FORCE_FALLBACK=1 bin/claude-usage-tracker            # exercise the fallback path
CUT_FAKE_RESET_IN=90 bin/claude-usage-tracker            # exercise sleep-until-reset
```
