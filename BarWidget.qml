pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Cells.js" as Cells
import "Chart.js" as Chart
import "Figures.js" as Figures
import "Format.js" as Format
import "Tones.js" as Tones
// The bar pill: one featured symbol with its day line and change, whatever
// range the panel or the window shows. Left click opens the panel, scroll
// walks the watchlist, middle click cycles the pill style, right click opens
// the window. The data service owns the data; the pill reads it.
BarWidget {
  id: root
  moduleName: "grvc.stonks"

  readonly property var plugin: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("grvc.stonks") : null
  readonly property var service: plugin ? plugin.service : null
  readonly property var panel: panelLoader.item
  readonly property string featuredSymbol: service ? service.featuredSymbol : ""
  readonly property var featuredQuote: service && featuredSymbol ? (service.quotes[featuredSymbol] || null) : null
  // The day, as its row shows it. The line comes from the quote it draws,
  // so the clock never redraws it.
  readonly property var featured: featuredQuote
    ? Figures.rowModel(featuredQuote, 0, service.changeMode) : null
  // A day with no print draws nothing, as its row does.
  readonly property var lineGeometry: featuredQuote && featuredQuote.points.length ? Chart.chartGeometry(featuredQuote, service.calendars) : null
  // In the bar's right section, among its bare icons, the pill has a form of
  // its own, `barStyleRight`: the icon until a middle-click there picks
  // another. The centre and left share `barStyle`. On a side bar it has
  // `barStyleVertical`: the icon, as Omarchy's text widgets fall back to
  // theirs there, until a middle-click picks the symbol over its change
  // ("stacked"). Each rides the entry, as the clock keeps verticalFormat
  // beside format, so a move between sections or between the top and a side
  // brings back each one's own.
  readonly property bool onRight: {
    var layout = bar && bar.layoutConfig ? bar.layoutConfig : null
    var right = layout && Array.isArray(layout.right) ? layout.right : []
    return right.some(function(entry) {
      return (typeof entry === "string" ? entry : entry && entry.id) === root.moduleName
    })
  }
  readonly property string styleKey: vertical ? "barStyleVertical" : onRight ? "barStyleRight" : "barStyle"
  readonly property string barStyle: setting(styleKey, vertical || onRight ? "icon" : "sparkline")
  // Just the day's animal, a quiet icon among the bar's own.
  readonly property bool iconOnly: barStyle === "icon"
  readonly property bool retro: service ? service.retro : setting("style", "retro") === "retro"
  // Freshness is judged with or without a quote: a first fetch that failed
  // is what "! No data" is for.
  readonly property var freshness: service && featuredSymbol
    ? Figures.freshness(service.entries[featuredSymbol] || null, featuredQuote, service.now, service.owed[featuredSymbol] || 0) : null
  readonly property bool warns: Figures.freshnessWarns(freshness)
  // What the "!" means, in the panel's words, for the hover on every form,
  // then why and when Stonks tries again, where it knows: Yahoo's pause
  // (`Figures.hostPause`), or that a price on show couldn't be updated. The
  // pill itself has no room for them.
  readonly property var hostPause: service && service.yahooGate
    ? Figures.hostPause(service.yahooGate.pause, service.yahooGate.pausedUntil, service.now) : null
  readonly property string warningText: !warns ? ""
    : Figures.freshnessText(freshness, featuredQuote, service.calendars)
      + (hostPause ? "\n" + hostPause.why + "\n" + hostPause.when
        : freshness.state === "failed" && featured ? "\nRetrying" : "")
  // The shell copies a hover's words only as the pointer enters. While it
  // stays, a warning that starts, ends, or changes its words goes to the bar
  // again, once every binding has the new words: no bubble names a warning
  // that has ended, and the text form's empties out. So does another symbol
  // on the pill, a wheel step's, so the bubble never names the company the
  // pill has left; a symbol and its warning changing together show it once
  // (Qt.callLater runs one function once). A new figure alone never
  // re-shows it, so a resting pointer sees no blink.
  function reshowTooltip() {
    if (button.tooltipHovered && button.bar) button.bar.showTooltip(button, button.tooltipText)
  }
  onWarningTextChanged: Qt.callLater(reshowTooltip)
  onFeaturedSymbolChanged: Qt.callLater(reshowTooltip)
  onOpenedChanged: Qt.callLater(reshowTooltip)
  // Up and down for the bar's own ground (`TrendColors`).
  readonly property color upColor: plugin && plugin.trendColors ? plugin.trendColors.upOn(barGround) : button.foreground
  readonly property color downColor: plugin && plugin.trendColors ? plugin.trendColors.downOn(barGround) : Commons.Color.urgent
  readonly property color trendColor: toneColor(featured ? featured.tone : "")
  // A day's colour by its tone: up, down, or the dim of a flat one.
  function toneColor(tone) { return tone === "up" ? upColor : tone === "down" ? downColor : dimColor }
  // The day and animal the icon form shows (`Figures.animalKind`, the
  // header's rule). A new price that turns the same symbol's day between
  // the bull and the bear steps the animal (`BarAnimal.turnTo`); another
  // symbol or another day shows at once, and no change mode moves it: the
  // turn says a price crossed, never that the reading changed.
  // Read in the handler, never a binding, so it can't lag `featured`.
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
  // Quieter than the bar's ink by the same rule as the panel's secondary
  // text, against the bar's own ground.
  readonly property color barGround: Qt.rgba(Commons.Color.bar.background.r, Commons.Color.bar.background.g, Commons.Color.bar.background.b, 1)
  readonly property color dimColor: Tones.dim(button.foreground, barGround)
  // A failed or overdue refresh marks the pill too: the bar is the surface
  // most likely to be trusted at a glance. With no price, an answer the
  // source sent without one says "No data", and a wait it never answered
  // (overdue) says so in the header's words, naming no source: not every
  // reader knows Yahoo.
  readonly property string changeText: featured ? (warns ? "! " : "") + Format.lookSigns(featured.changeLine, retro)
    : !warns ? "…" : freshness.state === "overdue" ? "! Can't get prices" : "! No data"
  // A side bar's stacked form: the symbol's lines over the move's, each at
  // most four characters (`Format.stackedSymbol`), the move in the rows'
  // unit, money in money and else a percent (`Format.stackedMoney`,
  // `stackedPct`), coloured by its sign as drawn. A warning's "!" goes on a
  // short line of its own before the move, as the text form puts it before
  // the change, kept whether the "!" shows or not, as the icon form keeps
  // its room: the pill never changes height for a warning. With no quote at
  // all the "!" is the move, in the place of the waiting "…".
  readonly property var stackedMove: !featured ? { lines: warns ? [] : ["…"], sign: 0 }
    : service.changeMode === "abs" ? Format.stackedMoney(featured.abs, featuredQuote.priceDigits) : Format.stackedPct(featured.pct)
  readonly property var stackedLines: Format.stackedSymbol(featuredSymbol || "ST")
    .map(function(t) { return { text: t, move: false, warning: false } })
    .concat(featured ? [{ text: warns ? "!" : "", move: false, warning: true }]
      : warns ? [{ text: "!", move: false, warning: false }] : [])
    .concat(stackedMove.lines.map(function(t) { return { text: t, move: true, warning: false } }))
  // The warning's line: the "!"'s ink and a gap each side, as the icon form
  // keeps under its animal.
  readonly property int stackedWarningHeight: Math.ceil(stackedWarningMetrics.tightBoundingRect("!").height) + 2 * 2
  readonly property int stackedHeight: stackedLines.reduce(function(sum, line) {
    return sum + (line.warning ? stackedWarningHeight : Style.bar.iconSlot)
  }, 0)
  FontMetrics {
    id: stackedWarningMetrics
    font.family: button.fontFamily
    font.pixelSize: Math.max(1, Math.round(button.fontSize))
  }

  // What is left of a notch between wheel events: a high-resolution wheel
  // sends a notch as several small ticks, and a notch is one symbol.
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
    NumberAnimation { target: root; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
  }

  function persistBarStyle(next) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[root.styleKey] = next
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // A side bar has two forms, the icon and the symbol over its change, so a
  // middle-click there steps between them.
  function cycleBarStyle() {
    var ring = ["sparkline", "arrow", "text", "icon"]
    root.persistBarStyle(root.vertical ? (root.iconOnly ? "stacked" : "icon")
      : ring[(ring.indexOf(barStyle) + 1) % ring.length])
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root).
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
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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
    fixedWidth: root.vertical ? -1 : (root.iconOnly ? Style.bar.iconSlot : content.implicitWidth + Style.space(17))
    // A side bar's icon slot holds the animal and the room under it for a
    // warning's "!", with a pixel to spare each end: an icon slot, or more
    // where the text is small enough that the two outgrow it.
    fixedHeight: root.vertical ? (root.iconOnly ? Math.max(Style.bar.iconSlot, Math.ceil(iconForm.implicitHeight) + 2)
      : root.stackedHeight) : -1
    // A hover only for what the pill can't say: the icon names nothing, so
    // its hover says what the other forms show, the symbol and its change;
    // on every form, what a warning's "!" means. The line, the arrow, and
    // the text show their symbol and change already, so say nothing else.
    // None while its panel is open: the bubble lands on the card's header.
    tooltipText: root.opened ? ""
      : (root.iconOnly ? (root.featuredSymbol || "STONKS") + " " + root.changeText : "")
        + (root.iconOnly && root.warningText !== "" ? " · " : "") + root.warningText

    onPressed: function(b) {
      if (b === Qt.RightButton) { if (root.plugin) root.plugin.windowHost.toggle() }
      else if (b === Qt.MiddleButton) root.cycleBarStyle()
      else root.togglePanel()
    }
    onWheelMoved: function(delta) { root.walk(delta) }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(6)
      visible: !root.vertical || root.iconOnly

      Sparkline {
        objectName: "pillLine"
        visible: root.barStyle === "sparkline" && !root.retro
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(40)
        height: Style.space(12)
        geometry: root.lineGeometry
        lineColor: root.trendColor
        baselineColor: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.25)
        lineWidth: 1.5
      }

      // The rows' pixel histogram at pill size, so the pill, a row, and the
      // hero are one drawing at three sizes; its stems solid, as faint ones
      // read as a dotted line here.
      PixelChart {
        visible: root.barStyle === "sparkline" && root.retro
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(40)
        height: Style.space(12)
        geometry: root.lineGeometry
        upColor: root.trendColor
        downColor: root.trendColor
        baselineColor: Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.25)
        pixel: 2
        gap: 1
        solid: true
      }

      // The 23-degrees idea: an arrow whose tilt is the size of today's move,
      // flat at zero and pinned at 45 degrees past a five percent day.
      Text {
        objectName: "pillArrow"
        visible: root.barStyle === "arrow"
        anchors.verticalCenter: parent.verticalCenter
        text: "➜"
        color: root.trendColor
        font.family: button.fontFamily
        font.pixelSize: Style.font.icon
        rotation: root.featured ? -Figures.arrowAngle(root.featured.pct) : 0
        Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }

      // The icon form, on either bar: the day's animal, the same in both
      // looks, the header's bull or bear (`BarAnimal`) one cell a pixel, as
      // tall as the bar's icons allow. A day that crosses its close turns it
      // column by column (`shownKind`). With no animal it says what the
      // other forms say: a flat day lies level in the dim of a flat change,
      // as the line form's flat day does, and before the first quote the
      // dim "…" of the text form.
      Item {
        id: iconForm
        objectName: "pillIcon"
        visible: root.iconOnly
        anchors.verticalCenter: parent.verticalCenter
        // A side bar is barely wider than the animal, so a warning's "!" goes
        // under it there, in room the slot keeps whether the "!" shows or
        // not: the animal never moves for a warning.
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

        // A warning's "!", in the bar's ink as the hero's line says one. On a
        // top or bottom bar it hangs in the slot's margin right of the
        // animal; on a side bar it sits under it, its ink centred across the
        // bar. A badge on its corner, as the shell's Tailscale icon wears
        // one, blurs into the cells at this size. With nothing shown, a first
        // fetch that failed, it stands alone where the animal would be.
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

      // The text form says the price too, as a ticker does: the bar is
      // where a glance asks what it is now.
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
        // With no price, a warning's words ("! Can't get prices") are in the
        // bar's ink, as the header says trouble; the waiting "…" stays dim.
        color: root.featured ? root.trendColor : root.warns ? button.foreground : root.dimColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }
    }

    // As Omarchy's clock draws a vertical bar: one line to an icon slot, at
    // the bar's size, 90% at four characters, never smaller; the warning's
    // line is shorter (`stackedWarningHeight`).
    Column {
      objectName: "pillStack"
      visible: root.vertical && !root.iconOnly
      anchors.centerIn: parent

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
