import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var providers: usage.enabledProviders

  // The panel reads the same records along two independent axes: what you
  // pay for (services — balance and limit windows) and what ran (agents —
  // session stats). A provider earns a tab in a card by having that kind
  // of data: claude/codex sit in both strips, zai service-only (it has no
  // local stats), pi and opencode agent-only, and the two cards switch
  // independently. A limits-only record with a dead probe and no rows yet
  // still earns the service tab via the urgent status+help pairing — that
  // pairing exists to be shown, not to be gated out. A subscription that
  // is not configured on this machine (configured === false — credentials
  // absent, per the collectors and the runner's config-check) earns no
  // tab at all (user decision 2026-09-17): it has no level or reset to
  // show, and its setup remedy is noise for a service never set up here.
  readonly property var serviceProviders: {
    var rev = providers
    var result = []
    for (var i = 0; i < providers.length; i++) {
      var p = providers[i]
      if (p.configured === false) continue
      if ((p.limits && p.limits.length > 0) || p.balance
          || (String(p.usageStatusText || "") !== "" && String(p.authHelpText || "") !== ""))
        result.push(p)
    }
    return result
  }
  readonly property var agentProviders: {
    var rev = providers
    var result = []
    for (var i = 0; i < providers.length; i++) {
      var p = providers[i]
      if (String(p.scope || "") === "account")
        continue  // OpenRouter/Fireworks: account analytics, not agents
      var days = p.recentDays || []
      var has = false
      for (var d = 0; d < days.length; d++)
        if (Number(days[d].messageCount) > 0) { has = true; break }
      if (!has) {
        var usageModels = p.modelUsage || {}
        for (var k in usageModels) { has = true; break }
      }
      // A tab is earned by renderable token data (day chart or model
      // rows), not by bare activity: activity-only records — discovery
      // MVPs, copilot's token-less store — stay in the usage dir but out
      // of the strip until they carry numbers worth charting.
      if (has) result.push(p)
    }
    return result
  }

  // Selections follow the provider, not the slot it happens to sit in: a
  // provider whose first scan lands while the panel is open would otherwise
  // shift the list underneath you and swap out what you were reading.
  property string selectedServiceId: ""
  property string selectedAgentId: ""
  readonly property int serviceIndex: {
    for (var i = 0; i < serviceProviders.length; i++)
      if (serviceProviders[i].providerId === selectedServiceId) return i
    return 0
  }
  readonly property int agentIndex: {
    for (var i = 0; i < agentProviders.length; i++)
      if (agentProviders[i].providerId === selectedAgentId) return i
    return 0
  }
  readonly property var service: serviceProviders.length > 0 ? serviceProviders[serviceIndex] : null
  readonly property var agent: agentProviders.length > 0 ? agentProviders[agentIndex] : null

  // The discovery record earns no tab of its own (see providerHasData's
  // installedUnused clause) — it sits in root.providers directly, found
  // by id, so its installedUnused list can back the AGENT card's footer
  // line regardless of which agent tab happens to be selected.
  readonly property var discoveryProvider: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === "discovery") return providers[i]
    return null
  }

  // Legacy alias: bar-icon alarming and the IPC cursor follow the service
  // card — its windows are what stop the next prompt.
  readonly property var provider: service

  property bool cursorActive: false
  // Which card the arrow keys drive; mouse clicks set it themselves.
  property bool serviceFocus: true

  // Countdowns and "updated" read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  readonly property var limits: limitWindows(service)
  readonly property var models: modelRows(agent)
  readonly property var balance: service ? (service.balance || null) : null
  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  readonly property bool balanceAlarming: !!balance && balance.funded > 0
    && balance.remaining / balance.funded <= 0.1
  readonly property bool alarming: serviceAlarming(service)

  // One status vocabulary for the whole panel: a subscription is urgent
  // when its fullest limit window is nearly spent, its prepaid balance is
  // nearly drained, or its probe failed outright (headline AND remedy both
  // set — the status-box contract; stock collectors leave stale help text
  // on healthy records, so help alone must never count). The service tab
  // names wear this as their text color, so the strip doubles as a status
  // row, and the bar icon speaks the same word for the selected service.
  function serviceAlarming(p) {
    if (!p) return false
    if (String(p.usageStatusText || "") !== "" && String(p.authHelpText || "") !== "")
      return true
    var windows = limitWindows(p)
    for (var i = 0; i < windows.length; i++)
      if (Number(windows[i].percent) >= 0.9) return true
    var b = p.balance
    return !!b && Number(b.funded) > 0 && Number(b.remaining) / Number(b.funded) <= 0.1
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // The service card names the company you pay; the agent card names the
  // tool that ran. Same record, two honest labels.
  function serviceName(p) {
    if (!p) return ""
    var map = { claude: "Anthropic", codex: "OpenAI" }
    return map[String(p.providerId)] || p.providerName
  }
  function agentName(p) {
    if (!p) return ""
    var map = { claude: "Claude Code" }
    return map[String(p.providerId)] || p.providerName
  }

  function selectService(index) {
    if (serviceProviders.length === 0) return
    var wrapped = ((index % serviceProviders.length) + serviceProviders.length) % serviceProviders.length
    selectedServiceId = serviceProviders[wrapped].providerId
  }
  function selectAgent(index) {
    if (agentProviders.length === 0) return
    var wrapped = ((index % agentProviders.length) + agentProviders.length) % agentProviders.length
    selectedAgentId = agentProviders[wrapped].providerId
  }
  function selectProvider(index) { selectService(index) }

  function refreshNow() {
    usage.refreshAll(true)
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters and the hero speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title) {
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || "")
    }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  // ---------------------------------------------------------------- content

  // The usage charts tell different truths per provider: account-wide
  // analytics (openrouter, fireworks — scope "account") vs machine-local
  // session stats (everything else). The group title says which one the
  // numbers are; a synced setup merges device stats into one total.
  function usageGroupTitle(p) {
    if (!p) return ""
    if (String(p.scope || "") === "account")
      return "USAGE — ACCOUNT"
    if (p.syncEnabled && Number(p.syncDeviceCount || 0) > 1)
      return "USAGE — " + Number(p.syncDeviceCount) + " DEVICES"
    return "USAGE — THIS MACHINE"
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    return dayName(date)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    // Prompt and session counts only exist for today, so they ride along here
    // instead of taking a section of their own. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (today && provider && provider.hasPromptStats !== false)
      text += " · " + Number(provider.todayPrompts || 0) + " prompts · "
        + Number(provider.todaySessions || 0) + " sessions"
    return text
  }

  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  // Which subscriptions this agent's tokens burned, heaviest first.
  // Collectors map provider ids to service-tab ids; unmapped ids show
  // as-is. Buckets carry modelUsage's shape so rows and tooltips render
  // identically.
  function subscriptionRows(p) {
    var usageBySub = p ? (p.subscriptionUsage || {}) : {}
    var rows = []
    for (var id in usageBySub) {
      var bucket = usageBySub[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      var total = input + output + cacheRead + cacheWrite
      if (total > 0)
        rows.push({
          name: subscriptionDisplayName(id),
          total: total,
          input: input,
          output: output,
          cacheRead: cacheRead,
          cacheWrite: cacheWrite
        })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows
  }

  function subscriptionDisplayName(id) {
    var map = {
      claude: "Anthropic",
      codex: "OpenAI",
      opencode: "OpenCode",
      zai: "Z.ai",
      openrouter: "OpenRouter",
      fireworks: "Fireworks",
      "opencode-zen": "OpenCode Zen"
    }
    return map[String(id)] || String(id)
  }

  function modelRows(p) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      rows.push({
        name: usage.friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function modelTooltip(row) {
    if (!row) return ""
    return "In " + usage.formatTokenCount(row.input)
      + " · out " + usage.formatTokenCount(row.output)
      + " · cache read " + usage.formatTokenCount(row.cacheRead)
      + " · cache write " + usage.formatTokenCount(row.cacheWrite)
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    if (provider && provider.syncEnabled && provider.syncDeviceCount > 0)
      return "Merged from " + provider.syncDeviceCount + " device" + (provider.syncDeviceCount === 1 ? "" : "s")
    return ""
  }

  // AGENT card footer: catalog agents installed on this machine but never
  // used, and owned by no collector — visible without earning a tab.
  // Empty (the common case) renders no line at all.
  function installedUnusedText() {
    var p = discoveryProvider
    var list = p && Array.isArray(p.installedUnused) ? p.installedUnused : []
    if (list.length === 0) return ""
    return "Installed, never used here: " + list.join(" · ")
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function markCandidates(id, surfaceColor) {
    var candidates = []
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + id + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + id + ".svg"))
    // Last resort for providers without a shipped mark (discovery-found
    // agents): the terminal-prompt chevron says "an agent ran here".
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/agent-fallback-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/agent-fallback.svg"))
    return candidates
  }

  function iconCandidatesForProvider(p, surfaceColor) {
    return p ? markCandidates(String(p.providerId), surfaceColor) : []
  }

  // Marks resolve by provider id directly now that Z.ai has its own
  // record (assets/zai.svg); the opencode AGENT mark stays
  // assets/opencode.svg (see markCandidates).
  function serviceMarkId(p) {
    return String(p ? p.providerId : "")
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run either CLI.
  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onServiceIndexChanged: if (panelFlick) panelFlick.contentY = 0
  onAgentIndexChanged: if (panelFlick) panelFlick.contentY = 0
  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.selectService(root.serviceIndex + 1); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
    active: root.alarming
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchAgent()
      else if (buttonCode === Qt.MiddleButton) root.selectService(root.serviceIndex + 1)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Math.max(Style.space(380),
      Math.max(serviceStrip.naturalRowWidth, agentStrip.naturalRowWidth) + Style.space(8)))
    // Taller than the control panels on purpose: this one is a dashboard,
    // and the whole point is reading limits and history without scrolling —
    // so the card adopts to the content's full height and only the screen
    // itself (fittedContentHeight's availableCardHeight cap) can force the
    // Flickable fallback.
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          root.cursorActive = true
          if (root.serviceFocus) root.selectService(root.serviceIndex + dx)
          else root.selectAgent(root.agentIndex + dx)
        }
        if (dy !== 0) {
          // Vertical keys scroll first; at the scroll edges they hand the
          // tab focus to the other card.
          if (dy < 0 && !root.serviceFocus) {
            root.serviceFocus = true
          } else if (dy > 0 && root.serviceFocus && panelFlick.atYEnd) {
            root.serviceFocus = false
          } else {
            panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                             Math.max(0, panelFlick.contentHeight - panelFlick.height))
          }
        }
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshNow() }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Text {
            visible: root.providers.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Service card ----------
          // One tab per thing you pay for; the strip names the company
          // (Anthropic, not Claude Code). The card answers two questions
          // and only those (user decision 2026-09-17): how full the
          // allowance is, and when it resets. Everything else the record
          // carries - tier label, token history, app burn - stays in the
          // record, off the card. Tab names carry their subscription's
          // status color (see serviceAlarming), so the strip reads as a
          // status row even before you select. Selecting a tab here never
          // disturbs the agent card below.
          BorderSurface {
            visible: root.serviceProviders.length > 0
            width: parent.width
            implicitHeight: serviceColumn.implicitHeight + serviceColumn.y * 2
            height: implicitHeight
            color: root.alpha(root.foreground, 0.04)
            borderSpec: Border.flat(root.alpha(root.foreground, 0.15), 1)
            radius: Style.cornerRadius

            Column {
              id: serviceColumn
              x: Style.space(12)
              y: Style.space(12)
              width: parent.width - Style.space(24)
              spacing: Style.space(12)

              Row {
                width: parent.width
                spacing: Style.space(8)

                // The selected service's mark.
                ProviderMark {
                  markId: root.serviceMarkId(root.service)
                }

                Text {
                  textFormat: Text.PlainText
                  text: "SUBSCRIPTION"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Flow {
                id: serviceStrip
                width: parent.width
                spacing: Style.spacing.md

              property real naturalRowWidth: 0
              function syncNaturalWidth() {
                var total = 0
                var count = 0
                for (var i = 0; i < children.length; i++) {
                  total += children[i].implicitWidth || 0
                  count++
                }
                var candidate = count > 1 ? total + spacing * (count - 1) : total
                if (candidate > naturalRowWidth)
                  naturalRowWidth = candidate
              }

                Repeater {
                  model: root.serviceProviders

                  onItemAdded: function(index, item) { Qt.callLater(serviceStrip.syncNaturalWidth) }
                  onItemRemoved: function(index, item) { serviceStrip.syncNaturalWidth() }

                  StatusTabButton {
                    required property var modelData
                    required property int index

                    onImplicitWidthChanged: serviceStrip.syncNaturalWidth()

                    text: root.serviceName(modelData)
                    selected: index === root.serviceIndex
                    hasCursor: root.cursorActive && root.serviceFocus && index === root.serviceIndex
                    // The name IS the status lamp: urgent when the record is
                    // alarming, theme foreground when healthy.
                    statusColor: root.serviceAlarming(modelData) ? root.urgent : root.foreground
                    onClicked: {
                      root.cursorActive = true
                      root.serviceFocus = true
                      root.selectService(index)
                    }
                    onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
                  }
                }
              }

              BorderSurface {
                // Show only when the record says why AND what to do:
                // stock collectors initialize authHelpText and never clear
                // it on success, so help alone nags on every healthy
                // provider (their "Run claude auth login" shows while
                // limits are perfectly live). usageStatusText is the
                // headline, authHelpText the remedy; both set = real.
                visible: !!root.service
                  && String(root.service.usageStatusText || "") !== ""
                  && String(root.service.authHelpText || "") !== ""
                width: parent.width
                implicitHeight: serviceStatusText.implicitHeight + Style.spacing.xl * 2
                height: implicitHeight
                color: root.alpha(root.urgent, 0.10)
                borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
                radius: Style.cornerRadius

                Text {
                  id: serviceStatusText
                  textFormat: Text.PlainText
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  text: root.service ? String(root.service.authHelpText || "") : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              // ---------- Usage level ----------
              // The card's entire content: one row per limit window - how
              // full it is, and when it resets. A prepaid balance is the
              // same answer in money (how much is left; it never resets,
              // so it gets no reset line). No section headers: with only
              // one grammar left, the rows speak for themselves.
              Column {
                id: levelSection
                visible: !!root.balance || root.limits.length > 0
                width: parent.width
                spacing: Style.space(12)

                Column {
                  id: balanceRow
                  visible: !!root.balance
                  width: parent.width
                  spacing: Style.space(6)

                  // The meter shows what is left, not what is used: a prepaid
                  // account drains toward empty rather than filling toward a cap.
                  readonly property real ratio: root.balance && root.balance.funded > 0
                    ? root.clamp(root.balance.remaining / root.balance.funded, 0, 1)
                    : -1

                  Item {
                    width: parent.width
                    implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)

                    Text {
                      id: balanceLabel
                      text: "Prepaid credits"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                      id: balanceValue
                      textFormat: Text.PlainText
                      text: root.balance ? root.formatMoney(root.balance.remaining, root.balance.currency) : ""
                      color: root.balanceAlarming ? root.urgent : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                    }
                  }

                  Meter {
                    visible: balanceRow.ratio >= 0
                    width: parent.width
                    value: balanceRow.ratio
                    alarming: root.balanceAlarming
                  }
                }

                Repeater {
                  model: root.limits

                  LimitRow {
                    required property var modelData
                    width: levelSection.width
                    window: modelData
                  }
                }
              }

            }
          }

          // ---------- Agent card ----------
          // One tab per thing that runs; the title names whose truth the
          // charts tell (machine-local sessions, account-wide analytics,
          // or a cross-device merge). Selecting a tab here never disturbs
          // the service card above.
          BorderSurface {
            visible: root.agentProviders.length > 0
            width: parent.width
            implicitHeight: usageColumn.implicitHeight + usageColumn.y * 2
            height: implicitHeight
            color: root.alpha(root.foreground, 0.04)
            borderSpec: Border.flat(root.alpha(root.foreground, 0.15), 1)
            radius: Style.cornerRadius

            Column {
              id: usageColumn
              x: Style.space(12)
              y: Style.space(12)
              width: parent.width - Style.space(24)
              spacing: Style.space(12)

              // The selected agent's mark leads the usage title: the card
              // speaks for one tool, and the mark says which before the
              // scope text does.
              Row {
                width: parent.width
                spacing: Style.space(8)

                ProviderMark {
                  markId: root.agent ? String(root.agent.providerId) : ""
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.usageGroupTitle(root.agent)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              Flow {
                id: agentStrip
                width: parent.width
                spacing: Style.spacing.md

              property real naturalRowWidth: 0
              function syncNaturalWidth() {
                var total = 0
                var count = 0
                for (var i = 0; i < children.length; i++) {
                  total += children[i].implicitWidth || 0
                  count++
                }
                var candidate = count > 1 ? total + spacing * (count - 1) : total
                if (candidate > naturalRowWidth)
                  naturalRowWidth = candidate
              }

                Repeater {
                  model: root.agentProviders

                  onItemAdded: function(index, item) { Qt.callLater(agentStrip.syncNaturalWidth) }
                  onItemRemoved: function(index, item) { agentStrip.syncNaturalWidth() }

                  // Same component as the service strip so both cards keep
                  // one tab look; agents just never carry a status color.
                  StatusTabButton {
                    required property var modelData
                    required property int index

                    onImplicitWidthChanged: agentStrip.syncNaturalWidth()

                    text: root.agentName(modelData)
                    selected: index === root.agentIndex
                    hasCursor: root.cursorActive && !root.serviceFocus && index === root.agentIndex
                    onClicked: {
                      root.cursorActive = true
                      root.serviceFocus = false
                      root.selectAgent(index)
                    }
                    onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
                  }
                }
              }

              UsageCharts {
                p: root.agent
              }



              // ---------- Per subscription ----------
              // The attribution mirror of the service card: which
              // subscription's credits this agent's tokens burned.
              Column {
                id: subscriptionSection
                visible: rows.length > 0
                width: parent.width
                spacing: Style.spacing.md

                readonly property var rows: root.subscriptionRows(root.agent)

                PanelSectionHeader {
                  width: parent.width
                  text: "PER SUBSCRIPTION"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Repeater {
                  model: subscriptionSection.rows

                  ModelRow {
                    required property var modelData
                    width: subscriptionSection.width
                    row: modelData
                    share: modelData.total / Math.max(1, subscriptionSection.rows[0].total)
                  }
                }
              }

              // ---------- Installed, never used ----------
              // Machine state, not this agent's — the discovery record,
              // not root.agent, so the line never changes with the
              // selected tab. Unobtrusive on purpose: a caption, not a row.
              Text {
                textFormat: Text.PlainText
                visible: text !== ""
                width: parent.width
                text: root.installedUnusedText()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // A provider's mark, resolving assets/<id>.svg (light twin first on light
  // surfaces) with a fallback walk. Candidates restart the walk only when
  // the URLs change: provider objects are rebuilt on every refresh, and
  // re-pointing source at a URL whose load already failed emits no
  // statusChanged. Extracted from the service header when the agent card's
  // usage title grew a mark of its own; the evaluate-once trap forbids
  // parents from binding over child ids, so the walk lives on this item.
  component ProviderMark: Item {
    id: mark
    property string markId: ""
    property real markSize: Style.space(18)

    property var candidates: root.markCandidates(markId, root.surface)
    property string candidatesKey: candidates.join("\n")
    property int candidateIndex: 0
    onCandidatesKeyChanged: candidateIndex = 0

    width: markSize
    height: markSize

    Image {
      anchors.fill: parent
      source: mark.candidateIndex < mark.candidates.length ? mark.candidates[mark.candidateIndex] : ""
      sourceSize.width: mark.markSize * 2
      sourceSize.height: mark.markSize * 2
      fillMode: Image.PreserveAspectFit
      // Advancing source from inside its own status change trips the
      // binding-loop detector; defer one tick.
      onStatusChanged: if (status === Image.Error && mark.candidateIndex < mark.candidates.length)
        Qt.callLater(function() { mark.candidateIndex++ })
    }
  }

  // The stock Button minus what a tab strip never uses, plus the one thing
  // stock cannot do: a text color that survives selection. The kit derives
  // the selected text color from the fixed `selected-color` theme token
  // (a literal hex in generated themes), so the sanctioned per-instance
  // `foreground` override — the way to tint a button — washes out the
  // instant the tab is selected, exactly when you are looking at it
  // (observed live: OpenAI at 95% lost its urgent name on selection).
  // Here the status color wins in every state; selection speaks through
  // bold text and the chrome fills, and every fill/border still comes from
  // the same Style tokens, so themes keep full control. Geometry mirrors
  // stock (border reservation included) so strip sizing is unchanged;
  // focus-ring states are dropped because tab strips are never Tab-focusable.
  component StatusTabButton: BorderSurface {
    id: tab

    property string text: ""
    property bool selected: false
    property bool hasCursor: false
    property color statusColor: root.foreground
    property string fontFamily: root.fontFamily
    property real fontSize: Style.font.bodySmall
    property real verticalPadding: Style.spacing.controlPaddingY

    signal clicked()
    signal hovered(bool isHovered)

    leftPadding: Style.spacing.controlPaddingX
    rightPadding: Style.spacing.controlPaddingX
    topPadding: verticalPadding
    bottomPadding: verticalPadding

    readonly property bool hot: mouseArea.containsMouse || hasCursor
    readonly property var _hoverBorderSpec: Border.controlSpec("hover-cursor", root.foreground, root.accent)
    readonly property var _selectedBorderSpec: Border.controlSpec("selected", root.foreground, root.accent)
    readonly property var _normalBorderSpec: Border.controlSpec("normal", root.foreground, root.accent)
    // Tabs are always bordered (stock delegates pass bordered: true), and a
    // selected tab keeps the normal border unless the theme opts into a
    // dedicated selected border — same precedence as stock.
    readonly property var _borderSpec: hot ? _hoverBorderSpec
      : selected ? (Border.controlHasWidth("selected") ? _selectedBorderSpec : _normalBorderSpec)
      : _normalBorderSpec

    // Reserve the largest border any state can paint, as stock does, so the
    // control doesn't grow a pixel per side on hover and relayout the strip.
    readonly property real _reservedBorderTop: Math.max(Border.top(_hoverBorderSpec), Border.top(_selectedBorderSpec), Border.top(_normalBorderSpec))
    readonly property real _reservedBorderRight: Math.max(Border.right(_hoverBorderSpec), Border.right(_selectedBorderSpec), Border.right(_normalBorderSpec))
    readonly property real _reservedBorderBottom: Math.max(Border.bottom(_hoverBorderSpec), Border.bottom(_selectedBorderSpec), Border.bottom(_normalBorderSpec))
    readonly property real _reservedBorderLeft: Math.max(Border.left(_hoverBorderSpec), Border.left(_selectedBorderSpec), Border.left(_normalBorderSpec))

    implicitWidth: label.implicitWidth + leftPadding + rightPadding + _reservedBorderLeft + _reservedBorderRight
    implicitHeight: label.implicitHeight + topPadding + bottomPadding + _reservedBorderTop + _reservedBorderBottom
    radius: Style.cornerRadius

    color: mouseArea.pressed ? Style.pressedFillFor(root.foreground, root.accent)
      : hot ? Style.hoverFillFor(root.foreground, root.accent)
      : selected ? Style.selectedFillFor(root.foreground, root.accent)
      : "transparent"
    borderSpec: _borderSpec

    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      id: label
      textFormat: Text.PlainText
      text: tab.text
      // Status beats selection: the color is the information, so it holds
      // in every state; selection says its piece through bold + chrome.
      color: tab.statusColor
      font.family: tab.fontFamily
      font.pixelSize: tab.fontSize
      font.bold: tab.selected
      anchors.centerIn: parent
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tab.clicked()
    }

    HoverHandler {
      onHoveredChanged: tab.hovered(hovered)
    }
  }

  // A limit window: label and percentage, meter, and reset countdown.
  component LimitRow: Column {
    id: limitRow
    property var window: null

    readonly property bool alarming: window && window.percent >= 0.9

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        textFormat: Text.PlainText
        // A model-scoped window is titled after its model, and those names run
        // long enough to reach the percentage, so the title gives way first.
        text: limitRow.window ? limitRow.window.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: limitValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: limitValue
        textFormat: Text.PlainText
        text: limitRow.window && limitRow.window.percent >= 0
          ? Math.round(limitRow.window.percent * 100) + "%"
          : "—"
        color: limitRow.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: limitRow.window ? limitRow.window.percent : -1
      alarming: limitRow.alarming
    }

    Text {
      id: resetText
      textFormat: Text.PlainText
      width: parent.width
      text: {
        var remainingMs = root.resetMsFor(limitRow.window)
        return remainingMs > 0 ? "Resets in " + root.formatDuration(remainingMs) : ""
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Rounded track showing the percentage of the allowance used.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

  }

  // One row per day: label, bar, tokens. Today is picked out in full
  // foreground so the week reads as a run-up to right now.
  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      textFormat: Text.PlainText
      text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: dayValue
      textFormat: Text.PlainText
      text: usage.formatTokenCount(dayRow.day ? Number(dayRow.day.messageCount || 0) : 0)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day, dayRow.today)
      fontFamily: root.fontFamily
    }
  }

  // Model rows read as a table: the share bar fills the row behind the label
  // instead of stacking under it, which keeps the whole dashboard on one screen.
  // Day/model charts for whichever provider they are bound to. Agents
  // show theirs in the agent card; account-scoped services (OpenRouter,
  // Fireworks) show theirs inside the service card — their tokens are
  // credit burn, subscription data, not agent activity.
  component UsageCharts: Column {
    id: charts
    property var p: null
    property string sectionTitle: ""
    readonly property var modelList: root.modelRows(p)
    width: parent.width
    spacing: Style.spacing.md

    Text {
      width: parent.width
      visible: charts.sectionTitle !== ""
      textFormat: Text.PlainText
      text: charts.sectionTitle
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

        Column {
          id: usageSection
          visible: !!charts.p && charts.p.recentDays && charts.p.recentDays.length > 0
          width: parent.width
          spacing: Style.spacing.md

          readonly property var days: charts.p ? (charts.p.recentDays || []) : []
          readonly property real peak: Math.max(1, root.weekPeak(charts.p))

          PanelSectionHeader {
            width: parent.width
            text: "TOKENS BY DAY"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: usageSection.days

            DayRow {
              required property var modelData
              required property int index

              width: usageSection.width
              day: modelData
              ratio: Number(modelData.messageCount || 0) / usageSection.peak
              // By date, not by position: the Claude stats-cache fallback can
              // hand us a window that stops short of today.
              today: String(modelData.date || "") === root.todayDate()
            }
          }
        }
        Column {
          id: modelSection
          visible: charts.modelList.length > 0
          width: parent.width
          spacing: Style.spacing.md

          PanelSectionHeader {
            width: parent.width
            text: "TOKENS BY MODEL"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: charts.modelList

            ModelRow {
              required property var modelData
              width: modelSection.width
              row: modelData
              // Scaled to the heaviest model, so the top row is always full —
              // the same scale-to-peak the weekly chart uses for its busiest day.
              share: modelData.total / Math.max(1, charts.modelList[0].total)
            }
          }
        }
  }

  component ModelRow: Item {
    id: modelRow
    property var row: null
    property real share: 0

    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: modelName
      textFormat: Text.PlainText
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: modelTokens
      textFormat: Text.PlainText
      text: modelRow.row ? usage.formatTokenCount(modelRow.row.total) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse
      text: root.modelTooltip(modelRow.row)
      fontFamily: root.fontFamily
    }
  }
}
