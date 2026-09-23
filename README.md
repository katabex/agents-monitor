# Agents Monitor for Omarchy

An [Omarchy](https://omarchy.org) shell plugin showing usage per subscription and agent.
When installed it replaces the stock widget on the bar.

![Agents Monitor panel](screenshots/panel.png)

## What it shows

- **SUBSCRIPTION** - one tab per subscription (Anthropic, OpenAI, Z.ai, OpenRouter, Fireworks, Copilot), ordered by how much you actually use each one.
  Each tab shows how full your allowance is and when it resets, or a prepaid balance if the service is pay-as-you-go.
  A subscription you haven't configured on this machine simply doesn't get a tab.
- **USAGE - BY AGENT** - one tab per coding tool that ran in the last 7 days (Claude Code, Codex, OpenCode, pi, Hermes), ordered by use, with a day-by-day chart of its tokens this week.
- **USAGE - BY SUBSCRIPTION AND MODEL** - a running total, independent of which tab is selected above: this week's usage summed by subscription and by model, across every tool at once.

## Providers and setup

Claude Code, Codex, Copilot, OpenCode, pi, and Hermes need no configuration beyond having used the tool at least once - their tabs appear automatically.

| Provider | Needs |
|---|---|
| Claude Code | Signed in via `claude` (same as stock) |
| Codex | Signed in via `codex login` (same as stock) |
| Z.ai | Nothing extra - reads the key OpenCode already has, or `$ZAI_API_KEY` |
| OpenRouter | `$OPENROUTER_API_KEY`, or `{"apiKey": "..."}` in `~/.config/omarchy/agents/openrouter.json`; add `"managementKey"` in the same file (from openrouter.ai → Settings → Management Keys) for token/app stats, not just the balance |
| Fireworks | `$FIREWORKS_API_KEY`, `~/.fireworks/auth.ini`, or signed in via OpenCode |
| Copilot | Just use the `copilot` CLI - token stats and premium-request consumption come from its local store (Copilot exposes no quota, so the tab shows consumption, not a level) |

## Install

```bash
./install.sh
```

Copies the plugin into `~/.config/omarchy/plugins/katabex.agents-monitor` and puts it in the bar in place of the stock `omarchy.agents` widget.
Re-run any time to pick up repo changes.

## Uninstall

```bash
./uninstall.sh
```

Restores the stock `omarchy.agents` widget and removes the plugin.

## License

MIT - upstream Omarchy code (© David Heinemeier Hansson, [Omarchy](https://omarchy.org)) plus original collector and runner scripts (© Katabex).
See `ARCHITECTURE.md` for how it's built.
