# Agents Monitor

An [Omarchy](https://omarchy.org) shell plugin: **Claude Code, Codex,
Fireworks, and pi** usage, limits, and pace in one bar panel.

Fork of the stock `omarchy.agents` widget (MIT) with built-in **pi agent**
collection — the provider the stock panel does not show. When installed it
replaces the stock widget on the bar.

## What it adds over stock

| Provider | Limits | Local stats |
|---|---|---|
| claude | Anthropic OAuth usage endpoint | as stock |
| codex | Codex app-server RPC | as stock |
| fireworks | prepaid balance estimate | as stock |
| **pi** | — (local stats only) | `~/.pi/agent/sessions` transcripts, every provider **except** `anthropic` and `openai-codex` (those are already folded into the Claude/Codex tabs by the stock collectors; counting them here would double-count) |

Everything else — the panel UI, per-day and per-model charts, cross-device
sync, settings schema — is the stock widget, unchanged.

## Install

```bash
./install.sh
```

Copies the plugin into `~/.config/omarchy/plugins/ptr.agents-monitor`
(`omarchy-plugin-validate` rejects symlinked plugin folders, so the repo in
`~/Repos/ktbx/agents-monitor` stays the source of truth — re-run
`install.sh` any time to deploy repo changes; the shell hot-reloads files
that change under its plugins dir).

`install.sh` disables `omarchy.agents`, puts `ptr.agents-monitor` in its bar
slot (right section, after `omarchy.tailscale`), and validates the manifest.
No restart needed.

## Uninstall

```bash
./uninstall.sh
```

Restores the stock `omarchy.agents` widget and removes the plugin from the
config directory.

## How pi collection works

- `bin/omarchy-agent-usage-pi` — Python collector; scans pi session JSONL for
  assistant messages from providers no stock collector claims, writes the
  record contract to `~/.local/state/omarchy/agents/usage/pi.json`
- `bin/agents-monitor-update` — refresh runner; the panel calls this instead
  of `omarchy-agent-usage-update` directly. Forwards to the stock updater
  (claude/codex/fireworks, honoring `--force`, `--limits-only`, `--except`,
  and agent-id filters) and runs the pi collector under the same rules, so
  all enabled providers refresh together. Also runs the live scanner
  (`--full`) — provider-independent, skipped only by `--limits-only`
- `bin/agents-monitor-live` — live session scanner (pi, Claude Code,
  Codex). `--quick` (15 s, driven by the bar widget's QML probe) writes
  `~/.local/state/omarchy/agents-monitor/live.json`; `--full` (5-minute
  systemd timer + every panel refresh) also writes `projects.json` with
  per-project token totals for today. Design:
  `docs/superpowers/specs/2026-09-06-live-agents-design.md`
- `LiveAgents.qml` — the LIVE · ALL AGENTS and BY PROJECT cards above the
  provider tabs, the bar count badge, and the quick probe. All new UI
  lives here; `Panel.qml` only carries two marked insertion blocks
- `Main.qml` differs from upstream in exactly two lines: the resolved path of
  the bundled runner, and the command that uses it

### The timer (option 2)

The machine-local `omarchy-pi-usage.timer` (systemd user unit) stays enabled
alongside the plugin **on purpose**: the plugin refreshes pi with everything
else on its interval (default 900 s, which also governs the network-bound
stock collectors), while the timer re-scans pi — a purely local, cheap scan —
every 5 minutes and keeps the record fresh when the shell is not running or
the plugin is uninstalled. The overlap is idempotent (atomic writes, same
record shape).

`install.sh` also installs and enables the sibling
`omarchy-agents-monitor-live.timer` (same 5-minute cadence) so
`live.json`/`projects.json` stay fresh between panel refreshes and while
the shell is down; `uninstall.sh` stops and removes it. Uninstalling leaves
`~/.local/state/omarchy/agents-monitor/` behind — harmless leftovers,
delete manually if you want it gone. The 15-second quick probe only runs
while the shell is up (the bar widget drives it); its atomic writes make
the timer overlap safe.

## Deploying changes

Re-run `./install.sh`. It ends with `omarchy restart shell` because the
shell's "Local plugin changed, reloading" path re-instantiates **cached**
QML components — changed QML does not take effect on hot-reload alone
(verified with a line-shift canary, 2026-09-06). Data-file changes
(`pi.json`, `live.json`) of course apply without any restart.

## Re-syncing with upstream

The QML is a fork of `/usr/share/omarchy/shell/plugins/agents/`. After an
Omarchy update:

```bash
diff -u /usr/share/omarchy/shell/plugins/agents/Main.qml Main.qml
diff -u /usr/share/omarchy/shell/plugins/agents/Panel.qml Panel.qml
diff -u /usr/share/omarchy/shell/plugins/agents/Agent.qml Agent.qml
```

Copy upstream changes in, then re-apply the two-line `Main.qml` patch
(`updateBin` property + `updateCommand` first element) **and** the two
`// agents-monitor:live-agents begin/end` marked blocks in `Panel.qml`
(the cards at the top of the panel Column, the badge after the
`BarIconButton`), **and** the one-line height-cap change in `Panel.qml`
(`fittedContentHeight(column.implicitHeight)` without the `Style.space(640)`
cap — panel sizes to content instead of scrolling). Everything else the
fork adds lives in files upstream does not have (`LiveAgents.qml`, the
bin/ and systemd/ trees), which cannot conflict. The manifest is
regenerable from upstream with the `jq` rename (`id`, `name`, `author`,
`description`, `displayName`, `aliases`, `providers.pi`,
`omarchy.clonedFrom`).

## License

MIT — upstream Omarchy code (© David Heinemeier Hansson,
[Omarchy](https://omarchy.org)) plus original collector and runner
scripts (© Katabex).
