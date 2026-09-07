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
`install.sh` any time to deploy repo changes).

`install.sh` disables `omarchy.agents`, puts `ptr.agents-monitor` in its bar
slot (right section, after `omarchy.tailscale`), validates the manifest, and
restarts the shell — changed QML needs it (see "Deploying changes").

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
  all enabled providers refresh together.
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

The whole live-agents view (cards, bar badge, quick probe) was removed on
2026-09-07; nothing in the plugin reads or writes
`~/.local/state/omarchy/agents-monitor/` anymore.

Upgrading from an older install? `./uninstall.sh` removes the obsolete
`omarchy-agents-monitor-live` systemd units, or disable them manually
(`systemctl --user disable --now omarchy-agents-monitor-live.timer`, then
delete `~/.config/systemd/user/omarchy-agents-monitor-live.*`). The stale
state dir `~/.local/state/omarchy/agents-monitor/` can be deleted too.

## Deploying changes

Re-run `./install.sh`. It ends with `omarchy restart shell` because the
shell's "Local plugin changed, reloading" path re-instantiates **cached**
QML components — changed QML does not take effect on hot-reload alone
(verified with a line-shift canary, 2026-09-06). Data-file changes
(`pi.json`) of course applies without any restart.

## Re-syncing with upstream

The QML is a fork of `/usr/share/omarchy/shell/plugins/agents/`. After an
Omarchy update:

```bash
diff -u /usr/share/omarchy/shell/plugins/agents/Main.qml Main.qml
diff -u /usr/share/omarchy/shell/plugins/agents/Panel.qml Panel.qml
diff -u /usr/share/omarchy/shell/plugins/agents/Agent.qml Agent.qml
```

Copy upstream changes in, then re-apply the two-line `Main.qml` patch
(`updateBin` property + `updateCommand` first element) — `Panel.qml` is
byte-identical to upstream again. Everything else the fork adds lives in
files upstream does not have (the `bin/` tree), which cannot conflict. The
manifest is
regenerable from upstream with the `jq` rename (`id`, `name`, `author`,
`description`, `displayName`, `aliases`, `providers.pi`,
`omarchy.clonedFrom`).

## License

MIT — upstream Omarchy code (© David Heinemeier Hansson,
[Omarchy](https://omarchy.org)) plus original collector and runner
scripts (© Katabex).
