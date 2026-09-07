# OpenCode provider — design

**Date:** 2026-09-07
**Plugin:** ptr.agents-monitor (`~/Repos/ktbx/agents-monitor`)
**Status:** approved (user picked "as designed, runner-only" cadence)

## Goal

An **OpenCode** tab appears in the Agents Monitor panel once the user runs
and uses the OpenCode CLI — same experience as the pi tab.

## Source of truth

`~/.local/share/opencode/opencode.db` (SQLite, opened `mode=ro` so a
running OpenCode is never lock-blocked). The legacy `storage/` JSON tree is
fully migrated into it (verified 2026-09-07: all 218 legacy message ids
exist as db rows; db holds 390 messages / 28 sessions). Assistant rows carry
`tokens{input,output,reasoning,cache{read,write}}`, `modelID`,
`providerID`, `time.created` (epoch ms), `session_id`.

## Counting

- Every assistant message with non-zero tokens, **no exclusions**: the stock
  Claude/Codex collectors scan `~/.claude` / `~/.codex` and never read
  OpenCode's store, so the double-count coupling that shapes the pi
  collector does not apply.
- Token mapping into the Claude-shaped contract buckets:
  `inputTokens ← tokens.input`, `outputTokens ← tokens.output +
  tokens.reasoning` (OpenCode splits reasoning; Claude's output includes
  thinking), `cacheReadInputTokens ← tokens.cache.read`,
  `cacheCreationInputTokens ← tokens.cache.write`. A message reporting only
  `tokens.total` counts as that total. The sum equals OpenCode's
  `tokens.total`.
- Day bucketing by `time.created` (local calendar day), fallback
  `time_created` column, fallback today. Sessions = distinct `session_id`
  with ≥1 counted message (pi-collector semantics).

## Wiring

- `bin/omarchy-agent-usage-opencode` — collector; writes the stock record
  contract (`id: "opencode"`, `name: "OpenCode"`, local stats only, no
  limits) atomically to `usage/opencode.json`. No db file → all-zero record
  → `providerHasData()` false → no tab until first use.
- `bin/agents-monitor-update` — the pi-specific block generalizes to a loop
  over `pi opencode`; same `--except` / id-filter / `--limits-only` rules.
- `manifest.json` — providers defaults gain `opencode` (enabled);
  description updated.
- `assets/opencode.svg` (+ black `-light` twin) from opencode.ai's favicon,
  background tile stripped, viewBox tightened.

## Refresh cadence (decision)

Runner-only, no new systemd timer: the record refreshes on shell start, the
panel's interval tick (default 900 s), and any panel open / refresh
activation. Tab appears within one of those after the first counted message.

## Verification

- Collector stdout vs a hand-computed db aggregate (prompts, sessions,
  today totals, per-model sums).
- `--except opencode` skips it; bare run writes both pi and opencode
  records.
- After `./install.sh`: panel shows the OpenCode tab with the mark and the
  expected per-day / per-model numbers.
