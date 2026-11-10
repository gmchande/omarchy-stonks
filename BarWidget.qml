pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Cells.js" as Cells
import "Chart.js" as Chart
import "Figures.js" as Figures
import "Format.js" as Format
import "Release.js" as Release
import "Tones.js" as Tones
import "Motion.js" as Motion
// The pill: the stock you last looked at, with its day's line and change
// whatever range the panel or the window shows.
BarWidget {
  id: root
  // `moduleName` is the bar entry's id, which the bar sets: the plugin's
  // id, the manifest's. The shell hands a plugin only its own service.

  readonly property var plugin: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var service: plugin ? plugin.service : null
  // Under an id other than a user's, a second copy beside it: a dim flask
  // at the pill's end, or under it on a side bar, so the two tell apart.
  readonly property bool marked: Release.otherCopy(moduleName)
  // Its room, the same whatever the pill shows, so nothing moves for it.
  readonly property int markRoom: marked ? (vertical ? Math.ceil(sideMark.implicitHeight) : content.spacing + Math.ceil(rowMark.implicitWidth)) : 0
  readonly property var panel: panelLoader.item
  readonly property string featuredSymbol: service ? service.featuredSymbol : ""
  readonly property var featuredQuote: service && featuredSymbol ? (service.quotes[featuredSymbol] || null) : null
  // As its row shows it, with its newest price since the close.
  readonly property var featured: featuredQuote
    ? Figures.rowModel(featuredQuote, 0, service.changeMode, service.newestPrints[featuredSymbol] || null) : null
  // The pill has no room for the newest price's session and time; the hover
  // says them.
  readonly property string newestNote: featured && featured.newest
    ? Figures.newestNote(featuredQuote, featured.newest, service.now, service.calendars) : ""
  // The day the 1D chart draws, once Robinhood has said which. Only the
  // five-minute clock that slides its start redraws it, never the second.
  // Built only for the form that draws it, and handed only to the look on
  // show.
  readonly property var lineDay: featuredQuote && barStyle === "sparkline"
    ? Chart.lineDay(featuredSymbol, featuredQuote, service.nights, service.allDay, service.calendars, service.slideAt) : null
  readonly property var lineGeometry: lineDay && lineDay.points.length ? Chart.chartGeometry(lineDay, service.calendars) : null
  // The right section, among the bar's bare icons, and a side bar each keep
  // a form of their own, the icon until a middle-click picks another, as the
  // clock keeps verticalFormat beside format: a move brings each one's back.
  readonly property bool onRight: {
    var layout = bar && bar.layoutConfig ? bar.layoutConfig : null
    var right = layout && Array.isArray(layout.right) ? layout.right : []
    return right.some(function(entry) {
      return (typeof entry === "string" ? entry : entry && entry.id) === root.moduleName
    })
  }
  readonly property string styleKey: vertical ? "barStyleVertical" : onRight ? "barStyleRight" : "barStyle"
  readonly property string barStyle: setting(styleKey, vertical || onRight ? "icon" : "sparkline")
  readonly property bool iconOnly: barStyle === "icon"
  readonly property bool retro: service ? service.retro : setting("style", "retro") === "retro"
  // Judged without a quote too: a first fetch that failed is "! No data".
  readonly property var freshness: service && featuredSymbol
    ? Figures.freshness(service.entries[featuredSymbol] || null, featuredQuote, service.now, service.owed[featuredSymbol] || 0, false,
      service.newestPrints[featuredSymbol] || null) : null
  readonly property bool warns: Figures.freshnessWarns(freshness)
  // The hover's words for the "!", in sentence case as a row says them, then
  // why and when Stonks tries again.
  readonly property var hostPause: service && service.yahooGate
    ? Figures.hostPause(service.yahooGate.pause, service.yahooGate.pausedUntil, service.now) : null
  readonly property string warningText: !warns ? ""
    : Format.sentenceCase(Figures.freshnessText(freshness, featuredQuote, service.calendars))
      + (hostPause ? "\n" + hostPause.why + "\n" + hostPause.when
        : freshness.state === "failed" && featured ? "\nRetrying" : "")
  // The shell copies a hover's words only as the pointer enters, so they go
  // to the bar again while it stays: a warning's, a new symbol's, a newest
  // price's session and time. Qt.callLater runs a function once, so changes
  // together show once. A new figure alone never does, so a resting pointer
  // sees no blink but for a newer trade's time.
  function reshowTooltip() {
    if (button.tooltipHovered && button.bar) button.bar.showTooltip(button, button.tooltipText)
  }
  onWarningTextChanged: Qt.callLater(reshowTooltip)
  onFeaturedSymbolChanged: Qt.callLater(reshowTooltip)
  onNewestNoteChanged: Qt.callLater(reshowTooltip)
  onOpenedChanged: Qt.callLater(reshowTooltip)
  // Up and down for the bar's own ground (`TrendColors`).
  readonly property color upColor: plugin && plugin.trendColors ? plugin.trendColors.upOn(barGround) : button.foreground
  readonly property color downColor: plugin && plugin.trendColors ? plugin.trendColors.downOn(barGround) : Commons.Color.urgent
  readonly property color trendColor: toneColor(featured ? featured.tone : "")
  function toneColor(tone) { return tone === "up" ? upColor : tone === "down" ? downColor : dimColor }
  // The animal turns only for a price crossing on the same symbol's day
  // (`BarAnimal.turnTo`), never for another symbol, day or change mode. Read
  // in the handler, never a binding, so it can't lag `featured`.
  function animalDay() {
    return !featuredQuote ? "" : [featuredSymbol,
      featuredQuote.session && featuredQuote.session.regular ? featuredQuote.session.regular.start : 0].join("|")
  }
  property string shownDay: ""
  property string shownKind: ""
  onFeaturedChanged: {
    var kind = Figures.animalKind(featured)
    var day = animalDay()
    if (day !== "" && day === shownDay) animal.turnTo(kind, shownKind)
    else animal.settle()
    shownDay = day
    shownKind = kind
  }
  Component.onCompleted: {
    shownDay = animalDay()
    shownKind = Figures.animalKind(featured)
  }
  readonly property color barGround: Qt.rgba(Commons.Color.bar.background.r, Commons.Color.bar.background.g, Commons.Color.bar.background.b, 1)
  readonly property color dimColor: Tones.dim(button.foreground, barGround)
  // The bar is the surface most trusted at a glance, so a failed or overdue
  // refresh marks the pill too. Overdue names no source: not every reader
  // knows Yahoo.
  readonly property string changeText: featured ? (warns ? "! " : "") + Format.lookSigns(featured.changeLine, retro)
    : !warns ? "…" : freshness.state === "overdue" ? "! Can't get prices" : "! No data"
  // A side bar's stacked form: the symbol over the move, four characters a
  // line at most, in the rows' unit. The "!" takes a short line of its own
  // before the move, kept empty without one, so the pill never changes height.
  readonly property var stackedMove: !featured ? { lines: warns ? [] : ["…"], sign: 0 }
    : service.changeMode === "abs" ? Format.stackedMoney(featured.abs, featuredQuote.priceDigits) : Format.stackedPct(featured.pct)
  readonly property var stackedLines: Format.stackedSymbol(featuredSymbol || "ST")
    .map(function(t) { return { text: t, move: false, warning: false } })
    .concat(featured ? [{ text: warns ? "!" : "", move: false, warning: true }]
      : warns ? [{ text: "!", move: false, warning: false }] : [])
    .concat(stackedMove.lines.map(function(t) { return { text: t, move: true, warning: false } }))
  // The "!"'s ink and 2 px each side.
  readonly property int stackedWarningHeight: Math.ceil(stackedWarningMetrics.tightBoundingRect("!").height) + 2 * 2
  readonly property int stackedHeight: stackedLines.reduce(function(sum, line) {
    return sum + (line.warning ? stackedWarningHeight : Style.bar.iconSlot)
  }, 0)
  FontMetrics {
    id: stackedWarningMetrics
    font.family: button.fontFamily
    font.pixelSize: Math.max(1, Math.round(button.fontSize))
  }

  // A high-resolution wheel sends a notch as several small ticks; a notch is
  // one symbol.
  property real wheelRemainder: 0

  function walk(angleDelta) {
    var notches = Util.wheelSteps(wheelRemainder, angleDelta)
    wheelRemainder = notches.remainder
    if (notches.steps !== 0 && service) service.featureStep(-notches.steps)
  }

  function acknowledgeRefresh() {
    refreshAcknowledgement.restart()
  }

  // A refresh asked for over IPC: every pill on every screen acknowledges it.
  Connections {
    target: root.plugin && root.plugin.ipc ? root.plugin.ipc : null
    function onRefreshed() { root.acknowledgeRefresh() }
  }

  SequentialAnimation {
    id: refreshAcknowledgement
    PropertyAction { target: root; property: "opacity"; value: 0.55 }
    NumberAnimation { target: root; property: "opacity"; to: 1; duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) }
  }

  function persistBarStyle(next) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[root.styleKey] = next
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function cycleBarStyle() {
    var ring = ["sparkline", "arrow", "text", "icon"]
    root.persistBarStyle(root.vertical ? (root.iconOnly ? "stacked" : "icon")
      : ring[(ring.indexOf(barStyle) + 1) % ring.length])
  }

  // Bar.findPanelWidget routes summon, hide and toggle to a widget with open,
  // close and opened.
  readonly property bool opened: panel ? panel.opened === true : false

  function open() { if (panel) panel.open() }
  function close() { if (panel) panel.close() }
  function togglePanel() { if (panel) panel.toggle() }

  readonly property real openPanelIndicatorWidth: content.implicitWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property bool popoutSwitchClosing: panel ? panel.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panel) panel.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("moduleName" in target) target.moduleName = root.moduleName
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onModuleNameChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : (root.iconOnly ? Style.bar.iconSlot + root.markRoom : content.implicitWidth + Style.space(17))
    // The animal and the room under it for a "!", a pixel to spare each end,
    // and at least an icon slot; and the mark's room under it all.
    fixedHeight: root.vertical ? (root.iconOnly ? Math.max(Style.bar.iconSlot, Math.ceil(iconForm.implicitHeight) + 2)
      : root.stackedHeight) + root.markRoom : -1
    // Only what the pill can't say: the icon form's symbol and change, a
    // newest price's session and time ("Overnight 23:25"), and what a "!"
    // means. None while the panel is open: the bubble would land on its header.
    tooltipText: root.opened ? ""
      : [root.iconOnly ? (root.featuredSymbol || "STONKS") + " " + root.changeText : "", root.newestNote, root.warningText]
        .filter(function(part) { return part !== "" }).join(" · ")

    onPressed: function(b) {
      if (b === Qt.RightButton) { if (root.plugin) root.plugin.windowHost.toggle() }
      else if (b === Qt.MiddleButton) root.cycleBarStyle()
      else root.togglePanel()
    }
    onWheelMoved: function(delta) { root.walk(delta) }

    // What the pill draws takes the button's press, as the shell's own bar
    // icons do (BarIconButton): held down, it gives a little, while the hit
    // area and the bar's layout hold still. Omarchy 4.0's bar icons don't
    // give, and its button has no `pressScale`.
    Row {
      id: content
      scale: button.pressScale || 1
      anchors.centerIn: parent
      anchors.verticalCenterOffset: root.vertical ? -root.markRoom / 2 : 0
      spacing: Style.space(6)
      visible: !root.vertical || root.iconOnly

      Sparkline {
        objectName: "pillLine"
        visible: root.barStyle === "sparkline" && !root.retro
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(40)
        height: Style.space(12)
        geometry: root.retro ? null : root.lineGeometry
        lineColor: root.trendColor
        baselineColor: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.25)
        lineWidth: 1.5
      }

      // The rows' histogram at pill size, its stems solid: faint ones read as
      // a dotted line here.
      PixelChart {
        visible: root.barStyle === "sparkline" && root.retro
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(40)
        height: Style.space(12)
        geometry: root.retro ? root.lineGeometry : null
        upColor: root.trendColor
        downColor: root.trendColor
        baselineColor: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.25)
        pixel: 2
        gap: 1
        solid: true
      }

      // Its tilt is the size of today's move: flat at zero, 45° past 5%.
      Text {
        objectName: "pillArrow"
        visible: root.barStyle === "arrow"
        anchors.verticalCenter: parent.verticalCenter
        text: "➜"
        color: root.trendColor
        font.family: button.fontFamily
        font.pixelSize: Style.font.icon
        rotation: root.featured ? -Figures.arrowAngle(root.featured.pct) : 0
        Behavior on rotation { NumberAnimation { duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) } }
      }

      // The day's animal, the same in both looks, one cell a pixel. Without
      // one, a flat day lies level in the dim of a flat change, and before the
      // first quote the text form's dim "…" waits.
      Item {
        id: iconForm
        objectName: "pillIcon"
        visible: root.iconOnly
        anchors.verticalCenter: parent.verticalCenter
        // A side bar is barely wider than the animal, so a "!" goes under it,
        // in room kept whether it shows or not.
        readonly property int warningGap: 2
        readonly property rect warningInk: warningMetrics.tightBoundingRect("!")
        implicitWidth: animal.implicitWidth
        implicitHeight: animal.implicitHeight + (root.vertical ? warningGap + warningInk.height : 0)

        BarAnimal {
          id: animal
          objectName: "pillAnimal"
          kind: Figures.animalKind(root.featured)
          upColor: root.upColor
          downColor: root.downColor
          cell: Math.max(1, Math.floor(Style.bar.iconCanvas / rows))
        }

        Rectangle {
          objectName: "pillLevel"
          visible: !!root.featured && animal.kind === ""
          y: Math.round((animal.height - height) / 2)
          width: animal.width
          height: Cells.RULE_THICKNESS
          color: root.dimColor
        }

        Text {
          objectName: "pillWaiting"
          visible: !root.featured && !root.warns
          anchors.centerIn: animal
          textFormat: Text.PlainText
          text: "…"
          color: root.dimColor
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
        }

        // Right of the animal on a top or bottom bar, under it on a side bar.
        // A badge on its corner, as Tailscale's icon wears, blurs into the
        // cells at this size.
        Text {
          id: warning
          objectName: "pillWarning"
          readonly property bool under: root.vertical && !!root.featured
          visible: root.warns
          x: Math.round(under ? (animal.width - iconForm.warningInk.width) / 2 - iconForm.warningInk.x
            : root.featured ? animal.width + 1 : (animal.width - width) / 2)
          y: Math.round(under ? animal.height + iconForm.warningGap - baselineOffset - iconForm.warningInk.y
            : (animal.height - height) / 2)
          textFormat: Text.PlainText
          text: "!"
          color: button.foreground
          font.family: button.fontFamily
          font.pixelSize: button.fontSize
          font.bold: true
        }
        FontMetrics { id: warningMetrics; font: warning.font }
      }

      Text {
        objectName: "pillSymbol"
        visible: !root.iconOnly
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.featuredSymbol || "STONKS"
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        font.bold: true
      }

      // The text form says the price too, as a ticker does.
      Text {
        objectName: "pillPrice"
        visible: root.barStyle === "text" && !!root.featured
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.featured ? root.featured.priceText : ""
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }

      Text {
        objectName: "pillChange"
        visible: !root.iconOnly
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.changeText
        // With no price, trouble is in the bar's ink, as the header says it.
        color: root.featured ? root.trendColor : root.warns ? button.foreground : root.dimColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }

      Text {
        id: rowMark
        objectName: "pillCopyMark"
        visible: root.marked && !root.vertical
        anchors.verticalCenter: parent.verticalCenter
        // The icon form's "!" hangs past the animal: kept clear, shown or not.
        leftPadding: root.iconOnly ? 1 + Math.ceil(warning.implicitWidth) : 0
        textFormat: Text.PlainText
        text: "\uDB80\uDC96"
        color: root.dimColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }
    }

    // On a side bar, too narrow for it beside the pill, the mark goes under.
    Text {
      id: sideMark
      objectName: "pillCopyMarkUnder"
      scale: button.pressScale || 1
      visible: root.marked && root.vertical
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      textFormat: Text.PlainText
      text: "\uDB80\uDC96"
      color: root.dimColor
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
    }

    // As Omarchy's clock draws a vertical bar: a line to an icon slot, 90% at
    // four characters.
    Column {
      objectName: "pillStack"
      scale: button.pressScale || 1
      visible: root.vertical && !root.iconOnly
      anchors.centerIn: parent
      anchors.verticalCenterOffset: -root.markRoom / 2

      Repeater {
        model: root.stackedLines

        OpticalGlyph {
          required property var modelData
          objectName: "pillStackLine"
          width: button.width
          height: modelData.warning ? root.stackedWarningHeight : Style.bar.iconSlot
          text: modelData.move ? Format.lookSigns(modelData.text, root.retro) : modelData.text
          fontFamily: button.fontFamily
          fontSize: modelData.text.length > 3 ? button.fontSize * 0.9 : button.fontSize
          color: !modelData.move ? button.foreground : root.stackedMove.sign > 0 ? root.upColor
            : root.stackedMove.sign < 0 ? root.downColor : root.dimColor
        }
      }
    }
  }
}
