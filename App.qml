pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons
import "History.js" as History
// Tiled app window. Owns window lifecycle, keys, and look; the body reads
// the service and owns the list, search, scrub, and help.
Item {
  id: root

  property var service: null
  property var updates: null
  // The theme's up and down (`TrendColors`).
  property var trendColors: null
  property bool closingFromHost: false
  property string requestedSymbol: ""
  property string requestedRange: ""

  readonly property bool ready: !!(service && service.pluginsReady)
  readonly property bool opened: window.visible
  readonly property string featuredSymbol: ready ? service.featuredSymbol : ""
  readonly property string range: ready ? service.range : "1D"
  // Built as the window first opens, and kept: null until then.
  readonly property var body: bodyLoader.item

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    requestedSymbol = String(payload.symbol || "").toUpperCase()
    requestedRange = History.historyRanges().indexOf(payload.range) >= 0 ? payload.range : ""
    closingFromHost = false
    // At rest before the first frame; closing left the window as it was.
    // Shown first, so the body reads the service again and the reset lays
    // out the latest.
    var opening = !window.visible
    bodyLoader.active = true
    window.visible = true
    if (opening) root.body.resetInteraction()
    applyRequest()
    if (opening) root.body.motion.revealChart()
    if (updates) updates.check()
    requestFundamentals()
    refocusKeys()
  }

  function close() {
    closingFromHost = true
    root.body.freeze()
    window.visible = false
    closingFromHost = false
  }

  // The summon payload's symbol and range, once the service can act on them,
  // in one change. Both are shared with the popup, and the symbol with the
  // bar, so a request belongs to the visit that made it: one waiting on a
  // service that was not ready yet is dropped if the window has been closed
  // by the time it is.
  function applyRequest() {
    if (!ready || !window.visible) return
    var symbol = requestedSymbol
    var range = requestedRange
    requestedSymbol = ""
    requestedRange = ""
    service.summon(symbol, range)
  }

  // The cap and P/E for the symbol on show while the window is open; the
  // service asks for the chart's history itself.
  function requestFundamentals() {
    if (window.visible && ready && featuredSymbol) service.fetchFundamentals(featuredSymbol)
  }

  function refresh() {
    if (ready) service.refresh()
    requestFundamentals()
  }

  function refocusKeys() { Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() }) }

  // A window summoned while its service starts draws its chart in once
  // there is a symbol to draw.
  onReadyChanged: if (ready) Qt.callLater(function() {
    root.applyRequest()
    root.requestFundamentals()
    if (window.visible) root.body.motion.revealChart()
  })
  onFeaturedSymbolChanged: requestFundamentals()

  FloatingWindow {
    id: window
    title: "Stonks"
    color: Color.background
    implicitWidth: 720
    implicitHeight: 760
    // The fixed content at its whole chart plus one row: below this the
    // list would have no room at all. The chart gives way first, so here
    // three rows show (StonksBody.minChartHeight).
    minimumSize: Qt.size(560, root.body ? root.body.smallestHeight : 0)
    visible: false

    // A close by the compositor freezes the body as one of ours does.
    onVisibleChanged: if (!visible && !root.closingFromHost) root.close()

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        var body = root.body
        if (body.ownsKeys) return
        if (event.key === Qt.Key_Escape) {
          if (body.showingHelp) body.showingHelp = false
          else if (!body.endScrub()) root.close()
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Up) { body.moveCursor(-1); event.accepted = true }
        else if (event.key === Qt.Key_Down) { body.moveCursor(1); event.accepted = true }
        else if (event.key === Qt.Key_Left) { body.nudgeScrub(-1); event.accepted = true }
        else if (event.key === Qt.Key_Right) { body.nudgeScrub(1); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          body.featureSymbol(body.watchlist.cursorRow)
          event.accepted = true
        } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
          body.removeRow(body.watchlist.cursorRow)
          event.accepted = true
        } else if (event.text === "?") { body.toggleHelp(); event.accepted = true }
        else if (event.text === "a" || event.text === "+") { body.startAdding(); event.accepted = true }
        else if (event.text === "x") { body.removeRow(body.watchlist.cursorRow); event.accepted = true }
        else if (event.text === "c") { body.cycleChangeMode(); event.accepted = true }
        else if (event.text === "r") { root.refresh(); event.accepted = true }
        else if (event.text === "[") { body.stepRange(-1); event.accepted = true }
        else if (event.text === "]") { body.stepRange(1); event.accepted = true }
        else if (event.key === Qt.Key_P && event.modifiers === Qt.NoModifier) { body.replay(); event.accepted = true }
        else if (event.text === "s") { body.toggleStyle(); event.accepted = true }
        else if (event.text === "o") { body.cycleOrder(); event.accepted = true }
        else if (event.text === "O") { body.reverseOrder(); event.accepted = true }
        else if (event.text === "w") { body.openListMenu(); event.accepted = true }
        else if (event.text === "W") { body.openManageLists(); event.accepted = true }
        else if (event.text === "m") { body.openSymbolLists(body.watchlist.cursorRow); event.accepted = true }
        else if (event.text === "u") { body.undoRemoval(); event.accepted = true }
        else if (event.text === ",") { body.stepList(-1); event.accepted = true }
        else if (event.text === ".") { body.stepList(1); event.accepted = true }
        else if (event.modifiers === Qt.ShiftModifier && event.key === Qt.Key_J) { body.moveSelected(1); event.accepted = true }
        else if (event.modifiers === Qt.ShiftModifier && event.key === Qt.Key_K) { body.moveSelected(-1); event.accepted = true }
        else if (event.text >= "1" && event.text <= "9") { body.featureAt(Number(event.text) - 1); event.accepted = true }
      }

      // A tiled window can be very wide; past the width the layout is drawn
      // for, the body keeps that width and centres, so a row never splits
      // into two islands. Narrower, it fills.
      Loader {
        id: bodyLoader
        active: false
        width: Math.min(parent.width, Style.space(720))
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter
        sourceComponent: StonksBody {
          service: root.ready ? root.service : null
          updates: root.updates
          surfaceOpen: window.visible
          // Before the service is ready the empty hero's label says Loading.
          headerWhenMissing: root.ready ? "No data" : ""
          margins: Style.space(16)
          chartHeight: Style.space(220)
          minChartHeight: Style.space(136)
          upColor: root.trendColors ? root.trendColors.upOn(ground) : Color.foreground
          downColor: root.trendColors ? root.trendColors.downOn(ground) : Color.urgent
          onKeysReleased: root.refocusKeys()
          onRefreshRequested: root.refresh()
        }
      }
    }
  }
}
