# Agents Monitor

An [Omarchy](https://omarchy.org) shell plugin: **Claude Code, Codex,
Fireworks, pi, OpenCode, and OpenRouter** usage, limits, and pace in one
bar panel.

Fork of the stock `omarchy.agents` widget (MIT) with built-in **pi agent**,
**OpenCode**, and **OpenRouter** collection — providers the stock panel does
not show. When installed it replaces the stock widget on the bar.

## What it adds over stock

| Provider | Limits | Local stats |
|---|---|---|
| claude | Anthropic OAuth usage endpoint | as stock |
| codex | Codex app-server RPC | as stock |
| fireworks | prepaid balance estimate | as stock |
| **pi** | — (local stats only) | `~/.pi/agent/sessions` + `~/.omp/agent/sessions` transcripts, every provider **except** `anthropic` and `openai-codex` (those are already folded into the Claude/Codex tabs by the stock collectors; counting them here would double-count) |
| **opencode** | z.ai GLM Coding Plan quota (undocumented community endpoint `api/monitor/usage/quota/limit`, keyed from OpenCode's `auth.json`): 5-hour + weekly token windows, tool-request quota, plan level; fail-soft with a cached-payload fallback | `~/.local/share/opencode/opencode.db` (SQLite, read-only) — every assistant message, all providers; the stock collectors never scan OpenCode's store, so nothing needs excluding |
| **openrouter** | pay-as-you-go credits (official `/api/v1/credits` + `/api/v1/auth/key`): one "Credits used" meter, balance line — credits do not reset | token stats via the Analytics API (`/api/v1/analytics/query`, management key required; balance-only without it) |

Everything else — the per-day and per-model charts, cross-device
sync, settings schema — is the stock widget, unchanged. The QML
divergences: (1) the provider tab strip sizes tabs to their name text
(natural width plus the control's own padding) and grows the panel to keep
the strip on one row, wrapping only on screens too narrow for it — stock
divided the strip into equal cells, which clipped names like "OpenRouter"
at six providers in a 380 px panel; (2) the urgent status box gates its
visibility on `authHelpText` (its content) instead of `usageStatusText` —
stock's pairing rendered an empty red box whenever a provider had a
healthy status line and no help text; (3) the content below the
status box splits into two cards: a SUBSCRIPTION card (balance + limit
meters — account truth) and a usage card (day/model charts) titled by
whose truth they tell — `USAGE — ACCOUNT` for account-scoped records
(`scope: "account"`: OpenRouter, Fireworks) vs `USAGE — THIS MACHINE` for
local session stats (or `— N DEVICES` when sync merges machines); a card
with nothing to show collapses out.

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

## How bundled collection works

- `bin/omarchy-agent-usage-pi` — Python collector; scans pi/omp session
  JSONL for assistant messages from providers no stock collector claims,
  writes the record contract to `~/.local/state/omarchy/agents/usage/pi.json`
- `bin/omarchy-agent-usage-opencode` — Python collector; reads OpenCode's
  SQLite store `~/.local/share/opencode/opencode.db` read-only (the legacy
  `storage/` JSON tree is fully migrated into it) and counts every
  assistant message with tokens, writing the same contract to
  `usage/opencode.json`. Token mapping: input ← `tokens.input`, output ←
  `tokens.output` + `tokens.reasoning`, cache read/write ←
  `tokens.cache.{read,write}` — the sum equals OpenCode's `tokens.total`.
  Also probes the z.ai GLM Coding Plan quota endpoint (OpenCode here runs
  on that plan) and maps the windows onto the tab's limit meters;
  fail-soft (10 s timeout, single attempt, cached payload reused while its
  windows are open), unknown row types skipped, `--quota-debug` prints the
  raw payload
- `bin/omarchy-agent-usage-openrouter` — Python collector; balance meter
  from OpenRouter's official credits/auth-key endpoints, plus token stats
  (today / by day / by model) from the Analytics API. Keys: balance needs
  `$OPENROUTER_API_KEY` or `{"apiKey": …}` in
  `~/.config/omarchy/agents/openrouter.json` (systemd/panel environments
  don't inherit shell exports); token stats additionally need a
  **management key** (openrouter.ai → Settings → Management Keys —
  read-only, cannot make model requests) in the same file as
  `{"managementKey": …}` or `$OPENROUTER_MANAGEMENT_KEY`. Without it the
  record degrades to balance-only. Stats are account-scoped (`scope:
  "account"`, the fireworks convention) so synced devices take the max, not
  the sum. Unconfigured runs never clobber a previously collected record
- `bin/agents-monitor-update` — refresh runner; the panel calls this instead
  of `omarchy-agent-usage-update` directly. Forwards to the stock updater
  (claude/codex/fireworks, honoring `--force`, `--limits-only`, `--except`,
  and agent-id filters) and runs all three bundled collectors under the
  same rules, so all enabled providers refresh together. `--limits-only`
  runs never touch the network-bound bundled probes, so opening the panel
  never hits the undocumented z.ai endpoint (the 5-minute opencode timer
  below keeps quota fresh instead).
- `Main.qml` differs from upstream in three lines: the resolved path of
  the bundled runner, the command that uses it, and the `scope`
  passthrough in `displayProvider`

### The timer (option 2)

The machine-local `omarchy-pi-usage.timer` (systemd user unit) stays enabled
alongside the plugin **on purpose**: the plugin refreshes pi with everything
else on its interval (default 900 s, which also governs the network-bound
stock collectors), while the timer re-scans pi — a purely local, cheap scan —
every 5 minutes and keeps the record fresh when the shell is not running or
the plugin is uninstalled. The overlap is idempotent (atomic writes, same
record shape).

`install.sh` also ships and enables the sibling
`omarchy-opencode-usage.timer` (same 1-min boot / 5-min active cadence,
30 s accuracy) so `opencode.json` stays equally fresh. It runs the
collector straight from the installed plugin directory — no second copy to
keep in sync — and `uninstall.sh` stops and removes it, unlike the pi
timer, which survives uninstall by design (so the pi tab keeps feeding the
stock widget).

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

Copy upstream changes in, then re-apply the `Main.qml` patch (the
runner: `updateBin` property + `updateCommand` first element; plus the
`scope` passthrough in `displayProvider`) and the
`Panel.qml` patches (the content-fitted provider tab strip: `Flow` instead
of equal-cell `Row`, buttons at natural width, `contentWidth` grown by
`naturalRowWidth`; the status box's `authHelpText` visibility gate; and
the usage group boundary with its `usageGroupTitle` header) — everything
else the fork adds lives in
files upstream does not have (the `bin/` tree), which cannot conflict. The
manifest is
regenerable from upstream with the `jq` rename (`id`, `name`, `author`,
`description`, `displayName`, `aliases`, `providers.pi`,
`omarchy.clonedFrom`).

## License

MIT — upstream Omarchy code (© David Heinemeier Hansson,
[Omarchy](https://omarchy.org)) plus original collector and runner
scripts (© Katabex).
