import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Live agent sessions, merged across every CLI with local session logs
// (pi, Claude Code, Codex). One instance only: it owns the 15-second quick
// probe, watches the two state files bin/agents-monitor-live writes, and
// renders the LIVE + BY PROJECT cards that sit above the provider tabs.
// The bar badge binds to the same instance (activeCount).
//
// Data contract: docs/superpowers/specs/2026-09-06-live-agents-design.md.
// The producer never stamps state — active/idle is derived here against
// nowMs, so a stale file degrades (rows go dim) instead of lying.

Item {
  id: live

  // ---------------------------------------------------------------- inputs
  property color foreground: "#ffffff"
  property string fontFamily: ""
  property var formatTokens: function(n) { return String(n) }
  property color activeColor: "#69d58c"

  readonly property color dim: Qt.darker(foreground, 1.55)
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") || "") + "/.local/state") + "/omarchy/agents-monitor"
  readonly property string script: Qt.resolvedUrl("bin/agents-monitor-live")
    .toString().replace(/^file:\/\//, "")

  // ---------------------------------------------------------------- clock
  // The panel's own 30 s ticker only runs while opened; the badge needs a
  // heartbeat too, so this one always runs and re-derives dot states.
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
  property var projectsData: null

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

  FileView {
    path: live.stateDir + "/projects.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(String(text()))
        if (parsed && parsed.schemaVersion === 1)
          live.projectsData = parsed
      } catch (e) { /* keep last good */ }
    }
    onLoadFailed: {}
  }

  // Fresh data only: a file older than 10 min means the probe is not
  // running (shell just started, or an older install without the script) —
  // showing it would pass yesterday's sessions off as live.
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
  readonly property int idleCount: sessions.length - activeCount

  // Active rows lead (newest first — that is the scan order), idle follow.
  readonly property var visibleSessions: {
    var active = [], idle = []
    for (var i = 0; i < sessions.length; i++)
      (isActive(sessions[i]) ? active : idle).push(sessions[i])
    return active.concat(idle)
  }

  readonly property var projectRows: projectsData
    ? (projectsData.projects || []).slice(0, 5) : []
  readonly property real projectPeak: {
    var peak = 1
    for (var i = 0; i < projectRows.length; i++)
      peak = Math.max(peak, Number(projectRows[i].total || 0))
    return peak
  }

  // ---------------------------------------------------------------- text
  function spanMs(session) {
    var start = Date.parse(session.startedAt)
    if (!isFinite(start)) return 0
    return Math.max(0, (isActive(session) ? nowMs : Date.parse(session.lastActivity)) - start)
  }

  function formatSpan(ms) {
    var minutes = Math.floor(ms / 60000)
    if (minutes < 1) return "now"
    if (minutes < 60) return minutes + "m"
    var hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h " + (minutes % 60) + "m"
    return Math.floor(hours / 24) + "d " + (hours % 24) + "h"
  }

  function formatAge(ms) {
    if (ms < 60000) return "just now"
    return formatSpan(ms)
  }

  function ageText(session) {
    return isActive(session)
      ? formatSpan(nowMs - Date.parse(session.startedAt))
      : "idle " + formatAge(nowMs - Date.parse(session.lastActivity))
  }

  function ctxText(session) {
    var tokens = Number(session.approxContextTokens || 0)
    if (tokens <= 0) return ""
    var window = Number(session.contextWindow || 0)
    return window > 0
      ? "ctx " + live.formatTokens(tokens) + "/" + live.formatTokens(window)
      : "ctx " + live.formatTokens(tokens)
  }

  readonly property string statLine: {
    if (sessions.length === 0) return ""
    var total = 0, longest = 0
    for (var i = 0; i < sessions.length; i++) {
      var span = spanMs(sessions[i])
      total += span
      longest = Math.max(longest, span)
    }
    return sessions.length + " session" + (sessions.length === 1 ? "" : "s")
      + " today · avg " + formatSpan(total / sessions.length)
      + " · longest " + formatSpan(longest)
  }

  // ---------------------------------------------------------------- cards
  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(12)
    visible: live.sessions.length > 0

    // ---------- LIVE ----------
    Column {
      width: parent.width
      spacing: Style.space(6)

      Item {
        width: parent.width
        implicitHeight: Math.max(liveHeader.implicitHeight, liveCount.implicitHeight)

        PanelSectionHeader {
          id: liveHeader
          text: "LIVE · ALL AGENTS"
          foreground: live.foreground
          fontFamily: live.fontFamily
          anchors.left: parent.left
        }

        Text {
          id: liveCount
          textFormat: Text.PlainText
          text: live.activeCount + " active · " + live.idleCount + " idle"
          color: live.dim
          font.family: live.fontFamily
          font.pixelSize: Style.font.caption
          anchors.right: parent.right
          anchors.baseline: liveHeader.baseline
        }
      }

      Repeater {
        model: live.visibleSessions

        Column {
          id: sessionRow
          required property var modelData
          width: parent.width
          spacing: Style.space(3)

          readonly property bool active: live.isActive(modelData)
          readonly property string ctx: live.ctxText(modelData)
          readonly property bool showCtx: active && ctx !== ""
            && modelData === live.visibleSessions[0]

          Item {
            width: parent.width
            implicitHeight: Math.max(projectName.implicitHeight, badge.implicitHeight)

            Rectangle {
              id: dot
              width: Style.space(7)
              height: width
              radius: width / 2
              color: sessionRow.active ? live.activeColor : live.alpha(live.foreground, 0.35)
              anchors.left: parent.left
              anchors.leftMargin: Style.space(3)
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: projectName
              textFormat: Text.PlainText
              text: sessionRow.modelData.project || "—"
              color: sessionRow.active ? live.foreground : live.dim
              font.family: live.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              anchors.left: dot.right
              anchors.leftMargin: Style.space(8)
              anchors.right: badge.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
            }

            Rectangle {
              id: badge
              width: badgeText.implicitWidth + Style.space(8)
              height: badgeText.implicitHeight + Style.space(4)
              radius: Style.space(3)
              color: live.alpha(live.foreground, 0.10)
              anchors.right: age.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: badgeText
                textFormat: Text.PlainText
                text: sessionRow.modelData.provider || ""
                color: live.dim
                font.family: live.fontFamily
                font.pixelSize: Style.font.caption
                anchors.centerIn: parent
              }
            }

            Text {
              id: age
              textFormat: Text.PlainText
              text: live.ageText(sessionRow.modelData)
              color: sessionRow.active ? live.activeColor : live.dim
              font.family: live.fontFamily
              font.pixelSize: Style.font.caption
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // Context bar rides under the newest active row only.
          Item {
            visible: sessionRow.showCtx
            width: parent.width
            implicitHeight: Math.max(6, ctxTrack.height)

            Rectangle {
              id: ctxTrack
              visible: sessionRow.showCtx
              width: parent.width
              height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
              radius: height / 2
              color: live.alpha(live.foreground, 0.12)
              anchors.left: parent.left
              anchors.right: ctxLabel.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter

              Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.min(1, Number(sessionRow.modelData.approxContextTokens || 0)
                  / Math.max(1, Number(sessionRow.modelData.contextWindow || 0)))
                color: live.foreground
                visible: Number(sessionRow.modelData.contextWindow || 0) > 0

                Behavior on width {
                  NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
              }
            }

            Text {
              id: ctxLabel
              visible: sessionRow.showCtx
              textFormat: Text.PlainText
              text: sessionRow.ctx
              color: live.dim
              font.family: live.fontFamily
              font.pixelSize: Style.font.caption
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }
    }

    // ---------- BY PROJECT ----------
    Column {
      width: parent.width
      spacing: Style.space(6)
      visible: live.projectRows.length > 0

      PanelSectionHeader {
        width: parent.width
        text: "BY PROJECT · TODAY"
        foreground: live.foreground
        fontFamily: live.fontFamily
      }

      Repeater {
        model: live.projectRows

        Item {
          id: projectRow
          required property var modelData
          width: parent.width
          implicitHeight: Math.max(projectName.implicitHeight, projectTotal.implicitHeight) + Style.space(2)

          Text {
            id: projectName
            textFormat: Text.PlainText
            text: projectRow.modelData.project || "—"
            color: live.foreground
            font.family: live.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width * 0.42
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Rectangle {
            id: projectTrack
            height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
            radius: height / 2
            color: live.alpha(live.foreground, 0.12)
            anchors.left: projectName.right
            anchors.right: projectTotal.left
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height
              radius: parent.radius
              width: parent.width * Math.min(1, Number(projectRow.modelData.total || 0) / live.projectPeak)
              color: live.alpha(live.foreground, 0.55)

              Behavior on width {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
              }
            }
          }

          Text {
            id: projectTotal
            textFormat: Text.PlainText
            text: live.formatTokens(Number(projectRow.modelData.total || 0))
            color: live.dim
            font.family: live.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        width: parent.width
        text: live.statLine
        color: live.dim
        font.family: live.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
