# Live Agents — Design

**Date:** 2026-09-06
**Plugin:** ptr.agents-monitor (`~/Repos/ktbx/agents-monitor`)

## Summary

Add a cross-provider live agent view to the Agents Monitor panel and bar widget:
a merged list of currently-running and recently-idle agent sessions across
**pi, Claude Code, and Codex** (Fireworks excluded — billing API only, no local
sessions), a per-project token breakdown for today, a session stat line, and a
count badge on the bar glyph.

## Decisions

| Decision | Pick |
|---|---|
| Scope | Merged live section — all agents with local session logs (pi, claude, codex) |
| Panel arrangement | Split cards: "LIVE · ALL AGENTS" + "BY PROJECT" |
| Placement | Once, above the provider tab bar (not per-tab) |
| Bar badge | Green count pill on the glyph, hidden at 0, counts all local agents |
| Visibility rule | Active = last activity ≤ 5 min · Idle = quiet longer but active today · otherwise hidden |
| Plumbing | Hybrid: quick probe (15 s, QML-driven) + full parse (5 min timer + panel refresh) |

## Architecture

One new vendored script `bin/agents-monitor-live` (python3), two modes:

| Mode | Cadence | Trigger | Writes |
|---|---|---|---|
| `--quick` | every 15 s, plus once at shell start | QML timer in the bar widget via `Quickshell.Io Process` | `live.json` |
| `--full` | every 5 min + every panel refresh | new systemd user timer `omarchy-agents-monitor-live.{service,timer}` and the plugin runner `bin/agents-monitor-update` (after the stock update, same pattern as the pi collector) | `live.json` + `projects.json` |

`--full` runs regardless of the runner's `--except` flags — it is provider-independent.

State files (atomic write: temp + rename):

- `~/.local/state/omarchy/agents-monitor/live.json` — session rows; built from
  directory listings + file stats + first/last-line peeks, no whole-file reads.
- `~/.local/state/omarchy/agents-monitor/projects.json` — per-project token
  totals for today; whole-file parse.

Sibling to the shell-watched `agents/usage/` dir so no "Live" provider tab
appears. `projects.json` has a single writer (`--full`); `live.json` is
written by both modes — atomic temp+rename makes concurrent writes safe
(last valid write wins, identical schema).

QML: one new component `LiveAgents.qml` — `FileView` on both files with
`watchChanges: true`; all new UI (cards, stat line, badge count) binds to it.
The 15 s probe resolves the script via `Qt.resolvedUrl` (same trick as the
existing Main.qml patch).

Freshness contract: the producer never stamps session *state*. QML derives
active/idle/hidden from `lastActivity` against its clock, so stale data
degrades instead of lying.

## Data shapes

`live.json`:

```json
{
  "schemaVersion": 1,
  "computedAt": "2026-09-06T15:40:00Z",
  "parseErrors": 0,
  "sessions": [
    {
      "provider": "pi",
      "project": "plugins/dev",
      "startedAt": "2026-09-06T12:14:52Z",
      "lastActivity": "2026-09-06T15:38:41Z",
      "model": "glm-5.3",
      "approxContextTokens": 92000
    }
  ]
}
```

- `provider`: `"pi" | "claude" | "codex"`.
- `project`: decoded from the session dir / cwd field.
- Emitted for every session whose `lastActivity` falls on the current
  **local** calendar day (covers started-yesterday-still-running). Capped at
  200 files per provider per scan.
- `model` null → rendered "—". `approxContextTokens` null → no ctx bar.

`projects.json`: `projects[]` of `{project, providers: {<id>: tokens}, total}`
for today, sorted by total. QML renders top 5 plus the stat line
(`N sessions today · avg Xm · longest Yh`; durations from live.json).
pi/claude sessions can span midnight, so tokens are summed per message
filtered to the current local calendar day; codex rollout files are
 date-partitioned and cumulative, so their last counter stands in.

## Per-provider parsing

| | Discovery | startedAt | lastActivity | model | context tokens |
|---|---|---|---|---|---|
| pi | `~/.pi/agent/sessions/<cwd-dir>/*.jsonl` | first line (`session` event) | file mtime | first `model_change` | tail-parse last ~64 KB for final usage block |
| claude | `~/.claude/projects/<dir>/*.jsonl` | first event timestamp | mtime | first assistant `model` field | tail-parse last usage block |
| codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` — today's + yesterday's date dirs only | `session_meta.payload.timestamp` | mtime | `session_meta.payload.model` | last `token_count` event if present |

Missing dir → provider skipped silently. Per-file parse failure → row skipped,
counted in `parseErrors`. `--root <dir>` flag overrides HOME-derived paths for
tests.

Context %: the script ships a small `CONTEXT_WINDOWS` table (glm-5.x, claude
families, codex families); QML shows `ctx 92k/200k` when the model is known,
plain `ctx 92k` when not. Unknown models never guess.

## UI

- Panel.qml gains **one clearly-marked insertion block** above the tab bar.
  All rendering lives in `LiveAgents.qml`; Panel.qml conflict surface stays
  ~10 lines.
- LIVE card: header "LIVE · ALL AGENTS" + `N active · M idle`; rows sorted by
  last activity (active first): status dot (green glowing = active, dim =
  idle), project, provider badge, age — elapsed since `startedAt` for active
  rows ("1h 53m"), "idle 2h" since `lastActivity` for idle rows; the
  top/active row carries the ctx bar.
- BY PROJECT card: header "BY PROJECT · TODAY"; top 5 rows with mini bars and
  totals; stat line at the bottom.
- Bar badge: overlay child on the bar glyph — green pill with the active
  count, hidden at 0. Existing click behaviors untouched.
- The whole live section collapses to zero height when live data is
  unavailable, restoring stock appearance.

## Degradation

| Situation | Result |
|---|---|
| Normal | Full experience; badge ≤ 15 s fresh, dot-state ≤ 30 s |
| Script missing (old install) | Cards hidden, badge hidden, no errors |
| live.json corrupt | QML keeps last good parse; none ever → hidden |
| Agent finishes mid-interval | Reclassified active→idle within ~30 s |
| File parse failure | Row skipped, `parseErrors` counted, rest unaffected |

## Sync semantics

live.json / projects.json are device-local and never written to `syncDir`;
the live view shows this machine's agents only. Synced provider records are
untouched.

## Testing

1. Script against `--root` fixture trees: empty / normal / corrupt files /
   codex date-nesting → assert shapes, caps, `parseErrors`.
2. Deployment: new timer active; `agents-monitor-update` triggers `--full`;
   existing pi collector + timer unaffected.
3. QML via shell hot-reload: cards render above tabs; badge hides at 0;
   touching a session file flips it active within 15 s; panel still fits
   without scrolling.
4. Installed copy identical to repo (`diff -rq`).

## Install / uninstall

- `install.sh`: copy plugin (now including `bin/agents-monitor-live` and
  `LiveAgents.qml`), register + enable the new systemd timer, existing steps
  unchanged.
- `uninstall.sh`: stop + remove the new timer, then existing steps. State
  files under `~/.local/state/omarchy/agents-monitor/` are left in place
  (harmless; document removal in README).

## Upstream re-sync impact

README procedure becomes: re-apply the 2-line Main.qml patch **and** the one
marked insertion block in Panel.qml. No other stock files diverge.

## Out of scope (future candidates)

Per-provider session cards, hour-of-day profile, week-over-week trend,
estimated cost, all-time totals/streak rows, multi-day project window — from
the 2026-09-06 brainstorm parameter menu; revisit after this ships.
