import QtQuick
import qs.Commons
import qs.Ui
import "Chart.js" as Chart
import "Figures.js" as Figures
import "Format.js" as Format
import "Tones.js" as Tones
// The bar pill: one featured symbol with its day line and change, whatever
// range the popup or the window shows. Left click opens the popup, scroll
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
  // another. The centre and left share `barStyle`. Both ride the entry when
  // it moves, so each section brings back its own.
  readonly property bool onRight: {
    var layout = bar && bar.layoutConfig ? bar.layoutConfig : null
    var right = layout && Array.isArray(layout.right) ? layout.right : []
    return right.some(function(entry) {
      return (typeof entry === "string" ? entry : entry && entry.id) === root.moduleName
    })
  }
  readonly property string styleKey: onRight ? "barStyleRight" : "barStyle"
  readonly property string barStyle: setting(styleKey, onRight ? "icon" : "sparkline")
  // Just Stonks' mark, a quiet icon among the bar's own.
  readonly property bool iconOnly: barStyle === "icon"
  readonly property bool retro: service ? service.retro : setting("style", "smooth") === "retro"
  // Freshness is judged with or without a quote: a first fetch that failed
  // is what "! no data" is for.
  readonly property var freshness: service && featuredSymbol
    ? Figures.freshness(service.entries[featuredSymbol] || null, featuredQuote, service.now, service.asked[featuredSymbol] || 0) : null
  readonly property bool warns: Figures.freshnessWarns(freshness)
  // What the "!" means, in the popup's words, for the hover on every form.
  readonly property string warningText: warns ? Figures.freshnessText(freshness, featuredQuote, service.calendars) : ""
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
  readonly property color downColor: plugin && plugin.trendColors ? plugin.trendColors.downOn(barGround) : Color.urgent
  readonly property color trendColor: featured && featured.tone === "up" ? upColor
    : featured && featured.tone === "down" ? downColor : dimColor
  // Quieter than the bar's ink by the same rule as the popup's secondary
  // text, against the bar's own ground.
  readonly property color barGround: Qt.rgba(Color.bar.background.r, Color.bar.background.g, Color.bar.background.b, 1)
  readonly property color dimColor: Tones.dim(button.foreground, barGround)
  // A failed or overdue refresh marks the pill too: the bar is the surface
  // most likely to be trusted at a glance.
  readonly property string changeText: featured ? (warns ? "! " : "") + Format.lookSigns(featured.changeLine, retro)
    : (warns ? "! no data" : "…")

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

  // A vertical bar draws the line, the arrow, and the text alike, the symbol
  // over its change, so a middle-click there steps between that and the
  // icon; a saved arrow or text stays saved, for a horizontal bar, until it
  // does.
  function cycleBarStyle() {
    var ring = ["sparkline", "arrow", "text", "icon"]
    root.persistBarStyle(root.vertical ? (root.iconOnly ? "sparkline" : "icon")
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
    fixedHeight: root.vertical ? (root.iconOnly ? Style.bar.iconSlot : Style.bar.iconSlot * 2) : -1
    // A hover only for what the pill can't say: the icon names nothing, so
    // its hover says what the other forms show, the symbol and its change;
    // on every form, what a warning's "!" means. The line, the arrow, and
    // the text show their symbol and change already, so say nothing else.
    // None while its popup is open: the bubble lands on the card's header.
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
      // hero are one drawing at three sizes.
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

      // The icon form, on either bar: Stonks' mark, the same in both looks,
      // climbing or falling with the day, in its colour, at the size of the
      // bar's icons, its columns solid so it reads beside their glyphs.
      StonksMark {
        objectName: "pillMark"
        visible: root.iconOnly
        anchors.verticalCenter: parent.verticalCenter
        falling: !!root.featured && root.featured.tone === "down"
        color: root.trendColor
        solid: true
        pixel: Math.max(2, Math.round(Style.bar.iconCanvas / 8))
        gap: 1
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
        color: root.featured ? root.trendColor : root.dimColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }
    }

    Column {
      visible: root.vertical && !root.iconOnly
      anchors.centerIn: parent

      OpticalGlyph {
        objectName: "pillDaySymbol"
        width: button.width
        height: Style.bar.iconSlot
        text: root.featured ? root.featured.symbol : "ST"
        fontFamily: button.fontFamily
        fontSize: button.fontSize * 0.85
        color: button.foreground
      }
      // Coloured by the figure it shows, a percentage whatever change the
      // rows say: by its sign, and no colour once it shows 0.0%.
      OpticalGlyph {
        objectName: "pillDayChange"
        width: button.width
        height: Style.bar.iconSlot
        text: root.featured ? Format.lookSigns(Format.narrowPct(root.featured.pct), root.retro) : "…"
        fontFamily: button.fontFamily
        fontSize: button.fontSize * 0.85
        color: !root.featured || Format.narrowPctShown(root.featured.pct).shown === 0 ? root.dimColor
          : root.featured.pct > 0 ? root.upColor : root.downColor
      }
    }
  }
}
