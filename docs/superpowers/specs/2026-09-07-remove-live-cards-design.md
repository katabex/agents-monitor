# Remove live-agents panel cards — design

**Date:** 2026-09-07
**Plugin:** ptr.agents-monitor (`~/Repos/ktbx/agents-monitor`)
**Status:** approved (user picked "cards + dead plumbing" scope)

## Context

The live-agents view added 2026-09-06 rendered two cards above the provider
tabs — **LIVE · ALL AGENTS** and **BY PROJECT · TODAY** — plus a green count
pill on the bar icon. The cards made the panel tall (the stock 640 px height
cap had to be lifted) and the user wants them gone.

## Decision

Remove the two panel cards and every piece of plumbing that existed only for
them. **Keep the bar count pill** — it was not part of the complaint and
still answers "is anything running right now" without opening anything.

## Changes

- `LiveAgents.qml` becomes data-only: keeps the 15 s quick probe, the
  live.json FileView, and the derived `ready` / `activeCount` /
  `activeColor` the badge binds to. All card rendering, the projects.json
  watcher, and the card-only text helpers are deleted.
- `Panel.qml`: the card block at the top of the column is gone; the
  `LiveAgents` instance moves next to `Main { id: usage }` as a non-visual
  data source. The badge block after `BarIconButton` is unchanged. The
  stock `fittedContentHeight(column.implicitHeight, Style.space(640))` cap
  is restored (the fork had lifted it only for the cards).
- `bin/agents-monitor-live`: `--full`, `scan_projects`,
  `full_session_tokens`, and `local_day_of` deleted; quick scan and
  live.json remain.
- `bin/agents-monitor-update`: no longer runs the live scanner — the QML
  probe alone refreshes the badge.
- `systemd/omarchy-agents-monitor-live.{service,timer}` deleted;
  `install.sh` no longer installs them, `uninstall.sh` keeps removal as
  legacy cleanup for ≤ v0.1.0 installs.

## Non-goals

- No change to the badge's looks or the 5-minute/15-second cadence split of
  the *pi usage* timer (`omarchy-pi-usage.timer` stays as is).
- live.json data contract unchanged
  (see `2026-09-06-live-agents-design.md`).

## Migration

Existing installs: disable and delete
`omarchy-agents-monitor-live.{service,timer}` and remove stale
`~/.local/state/omarchy/agents-monitor/projects.json` (uninstall.sh /
README cover this).

## Verification

- `bin/agents-monitor-live` run against a scratch `XDG_STATE_HOME` writes
  live.json only (no projects.json).
- After `./install.sh`: panel opens with no LIVE / BY PROJECT cards and the
  stock height cap back; bar badge still shows the live count while an
  agent is running; `systemctl --user list-timers` no longer lists the
  live timer.

## Addendum (same day, later session)

The bar count badge was removed as well, at the user's request. With no
consumer left, the whole live pipeline went: `LiveAgents.qml` (probe +
live.json + activeCount), `bin/agents-monitor-live`, the badge block, and
the badge-source block in `Panel.qml`. `Panel.qml` is now byte-identical to
upstream (verified by diff against
`/usr/share/omarchy/shell/plugins/agents/`); the only QML fork left is the
two-line `Main.qml` runner patch. `~/.local/state/omarchy/agents-monitor/`
is no longer read or written and can be deleted.
