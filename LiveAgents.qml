import QtQuick
import Quickshell
import Quickshell.Io

// Live agent sessions, merged across every CLI with local session logs
// (pi, Claude Code, Codex). Data only, no UI: this instance owns the
// 15-second quick probe and watches the live.json file that
// bin/agents-monitor-live writes; the bar count badge in Panel.qml binds
// to it (ready, activeCount, activeColor). The LIVE / BY PROJECT cards it
// used to render were removed 2026-09-07
// (docs/superpowers/specs/2026-09-07-remove-live-cards-design.md; data
// contract: docs/superpowers/specs/2026-09-06-live-agents-design.md).
//
// The producer never stamps state — active/idle is derived here against
// nowMs, so a stale file degrades (the badge empties) instead of lying.

Item {
  id: live

  // ---------------------------------------------------------------- inputs

  property color activeColor: "#69d58c"

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") || "") + "/.local/state") + "/omarchy/agents-monitor"
  readonly property string script: Qt.resolvedUrl("bin/agents-monitor-live")
    .toString().replace(/^file:\/\//, "")

  // ---------------------------------------------------------------- clock
  // The panel's own 30 s ticker only runs while opened; the badge needs a
  // heartbeat too, so this one always runs and re-derives session states.
  property double nowMs: Date.now()

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: live.nowMs = Date.now()
  }

  // ---------------------------------------------------------------- probe

  Process {
    id: probe
    running: false
    command: [live.script, "--quick"]
    stdout: StdioCollector { }
    stderr: StdioCollector { }
  }

  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: if (!probe.running) probe.running = true
  }

  Component.onCompleted: probe.running = true

  // ---------------------------------------------------------------- data

  property var liveData: null

  FileView {
    path: live.stateDir + "/live.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(String(text()))
        if (parsed && parsed.schemaVersion === 1)
          live.liveData = parsed
      } catch (e) { /* keep last good */ }
    }
    onLoadFailed: {} // keep last good; the probe rewrites within 15 s
  }

  // Fresh data only: a file older than 10 min means the probe is not
  // running (shell just started, or an older install without the script) —
  // a stale count would pass dead sessions off as live.
  readonly property bool ready: !!liveData
    && nowMs - Date.parse(liveData.computedAt) < 10 * 60 * 1000

  readonly property real activeWindowMs: 5 * 60 * 1000
  readonly property var sessions: ready && liveData ? (liveData.sessions || []) : []

  function isActive(session) {
    return nowMs - Date.parse(session.lastActivity) <= activeWindowMs
  }

  readonly property int activeCount: {
    var n = 0
    for (var i = 0; i < sessions.length; i++)
      if (isActive(sessions[i])) n++
    return n
  }
}
