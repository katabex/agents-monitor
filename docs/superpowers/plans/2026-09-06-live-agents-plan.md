# Live Agents — Implementation Plan

**Spec:** `docs/superpowers/specs/2026-09-06-live-agents-design.md`
**Repo:** `~/Repos/ktbx/agents-monitor`

Steps are ordered; each has a verification command. Do not deploy (step 9)
until steps 1–8 pass.

## 1. Script skeleton + session discovery — `bin/agents-monitor-live`

- [x] python3, executable, argparse: `--quick` (default when no mode given),
      `--full`, `--root <dir>` (defaults to `$HOME`; tests override)
- [x] `discover_sessions(root)` → list of (provider, path) per spec:
      - pi: `<root>/.pi/agent/sessions/*/*.jsonl`
      - claude: `<root>/.claude/projects/*/*.jsonl`
      - codex: `<root>/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` for
        today's and yesterday's **local** dates only
- [x] Filter to files with mtime on the current local calendar day; cap 200
      per provider (most recent mtime first)
- [x] Missing dirs skipped silently

Verify: against real `$HOME`, `./bin/agents-monitor-live --quick` prints a
debug line per provider with counts > 0 for pi (this session counts).

## 2. Field extraction (quick mode) → `live.json`

- [x] Per file extract: `project` (decode dir name `--home-ptr-X--` → path;
      display name = last two path components, `~` for home itself; codex uses
      `session_meta.payload.cwd`), `startedAt`, `lastActivity` (mtime),
      `model` (pi: first `model_change`; claude: first `"model":` line;
      codex: `session_meta.payload.model`), `approxContextTokens`
      (tail 64 KB; pi/claude: last usage block, sum
      input + cacheRead + cacheWrite + output; codex: last `token_count`
      event totals; null on any miss)
- [x] Any per-file exception → skip row, increment `parseErrors`
- [x] Write `~/.local/state/omarchy/agents-monitor/live.json` atomically
      (`--root` redirects state dir too), shape exactly per spec §Data shapes

Verify: `jq . ~/.local/state/omarchy/agents-monitor/live.json` shows this
session as pi / active-today / glm-5.3 with non-null context tokens.

## 3. Full mode → `projects.json`

- [x] Same discovery, but parse each file whole; sum usage tokens per session
      (pi/claude: all usage blocks; codex: all `token_count` events, last
      cumulative value per file)
- [x] Aggregate by project × provider → `projects[]` sorted by `total`
      desc, shape per spec
- [x] `--full` also rewrites `live.json`

Verify: `jq . ~/.local/state/omarchy/agents-monitor/projects.json` —
today's real numbers, pi dominant. The pi column (all projects summed)
must equal `pi.json` `todayTotalTokens` exactly when both are computed at
the same moment (verified 2026-09-06: 12,721,452 == 12,721,452).

## 4. Context window table

- [x] `CONTEXT_WINDOWS` dict in the script: prefix-match families
      (`glm-5`, `claude-sonnet`, `claude-opus`, `gpt-5`, …) → window tokens
- [x] Exposed as `contextWindow` field on each session row (null unknown)
      — QML never needs the table

Verify: `jq '.sessions[0].contextWindow'` non-null for glm-5.3.

## 5. Runner + systemd units

- [x] `bin/agents-monitor-update`: append invocation of
      `agents-monitor-live --full` (same error handling as pi collector call)
- [x] New `systemd/omarchy-agents-monitor-live.service` (oneshot, runs
      `<installed plugin bin>/agents-monitor-live --full`) and `.timer`
      (OnBootSec=2min, OnUnitActiveSec=5min)

Verify: `bin/agents-monitor-update --help`-style dry run or direct execution
writes both files; unit files pass `systemd-analyze verify`.

## 6. `LiveAgents.qml`

- [x] Owns: 15 s `Timer` + `Quickshell.Io Process` running the script
      `--quick` via `Qt.resolvedUrl("bin/agents-monitor-live")`; two
      `FileView`s (live.json, projects.json, `watchChanges: true`)
- [x] Exposes: `sessionsReady`, `activeCount`, `idleCount`, `visibleSessions`
      (active first, then lastActivity desc; each row re-derives state vs
      `nowMs` — 30 s tick), `ctxText(session)`, `ageText(session)`,
      `projectRows` (top 5), `statLine`
- [x] Parse guard: try/catch, keep last good; never-good → `ready: false`
- [x] Renders: LIVE card + BY PROJECT card per spec §UI (zero height when
      not ready)

Verify: `qmllint`-style check if available; else shell hot-reload in step 10.

## 7. Panel.qml wiring (marked blocks only)

- [x] Root-level single `LiveAgents { id: liveAgents }` instantiation
      (one probe, not two)
- [x] Insertion block above the tab bar hosting the two cards — wrapped in
      `// agents-monitor:live-agents begin/end` markers
- [x] Badge: overlay child on the bar `BarIconButton` (green pill, count
      `liveAgents.activeCount`, `visible: count > 0`) — same marker comments
- [x] No other Panel.qml lines touched

Verify: `git diff Panel.qml` shows only the two marked blocks; QML loads
without console errors after `omarchy restart shell`.

## 8. Install / uninstall / README

- [x] `install.sh`: existing copy step (now ships script + LiveAgents.qml),
      then install units → `systemctl --user daemon-reload`, `enable --now`
      the new timer
- [x] `uninstall.sh`: `disable --now` + remove units + daemon-reload;
      existing steps unchanged; README notes leftover state dir removal
- [x] README: update re-sync section — 2-line Main.qml patch **plus** the
      marked Panel.qml blocks; document state dir + timer

Verify: read-through; `bash -n` on both scripts.

## 9. Deploy + end-to-end

- [x] `./install.sh`; confirm plugin re-validated + enabled

Verify: `diff -rq` repo vs installed copy (identical);
`systemctl --user is-active omarchy-agents-monitor-live.timer` = active;
panel: cards above tabs, badge pill while this session runs; `touch` a real
session file → flips active ≤ 15 s; badge 0-state after 5 min idle window
(or temporarily lower threshold to test); stock provider tabs unchanged.

## 10. Commit + session log

- [x] Commit sequence: script (1–4), runner+units (5), QML (6–7),
      install/docs (8), deploy notes (9) — or one commit per natural unit
- [x] Update `~/Repos/ktbx/dev/2026-09-06-session.md` §open items
