pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "History.js" as History
// The Stonks window. StonksBody does the rest; it is built as the window
// first opens, and kept.
Item {
  id: root

  property var service: null
  property var updates: null
  property var sounds: null
  property var camera: null
  property var trendColors: null
  property bool closingFromHost: false
  property string requestedSymbol: ""
  property string requestedRange: ""
  property bool onScreen: true

  readonly property bool ready: !!(service && service.pluginsReady)
  readonly property bool opened: window.visible
  readonly property string featuredSymbol: ready ? service.featuredSymbol : ""
  readonly property string range: ready ? service.range : "1D"
  readonly property var body: bodyLoader.item

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    requestedSymbol = String(payload.symbol || "").toUpperCase()
    requestedRange = History.historyRanges().indexOf(payload.range) >= 0 ? payload.range : ""
    closingFromHost = false
    // Shown first, so the body reads the service again and the reset lays
    // out the latest.
    var opening = !window.visible
    bodyLoader.active = true
    window.visible = true
    if (opening) root.body.resetInteraction()
    applyRequest()
    if (opening) root.body.motion.revealChart()
    if (updates) updates.check()
    refocusKeys()
  }

  function close() {
    closingFromHost = true
    root.body.freeze()
    window.visible = false
    closingFromHost = false
  }

  function applyRequest() {
    if (!ready || !window.visible) return
    var symbol = requestedSymbol
    var range = requestedRange
    requestedSymbol = ""
    requestedRange = ""
    service.summon(symbol, range)
  }

  function refresh() {
    if (ready) service.refresh()
  }

  function refocusKeys() { Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() }) }

  onReadyChanged: if (ready) Qt.callLater(function() {
    root.applyRequest()
    if (window.visible) root.body.motion.revealChart()
  })

  FloatingWindow {
    id: window
    title: "Stonks"
    color: Commons.Color.background
    implicitWidth: 720
    implicitHeight: 760
    // The width scales with the text size: at a fixed 560, size 16 cuts
    // Tokyo's holiday header and leaves VOL and P/E off the info lines.
    minimumSize: Qt.size(Style.space(560), root.body ? root.body.smallestHeight : 0)
    visible: false

    // The compositor's close freezes the body as ours does.
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
        } else if (body.pressKey(event)) event.accepted = true
      }

      MouseArea {
        objectName: "marginCatcher"
        anchors.fill: parent
        visible: !!root.body && root.body.rowMenu !== null
        acceptedButtons: Qt.AllButtons
        onClicked: root.body.rowMenu = null
        onWheel: function(wheel) { wheel.accepted = true }
      }

      // Past the width the layout is drawn for, the body centres, so a wide
      // tiled window never splits a row into two islands.
      Loader {
        id: bodyLoader
        active: false
        width: Math.min(parent.width, Style.space(720))
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter
        sourceComponent: StonksBody {
          service: root.ready ? root.service : null
          updates: root.updates
          sounds: root.sounds
          camera: root.camera
          surfaceOpen: window.visible
          onScreen: root.onScreen
          headerWhenMissing: root.ready ? "No data" : ""
          margins: Style.space(16)
          chartHeight: Style.space(220)
          minChartHeight: Style.space(136)
          upColor: root.trendColors ? root.trendColors.upOn(ground) : Commons.Color.foreground
          downColor: root.trendColors ? root.trendColors.downOn(ground) : Commons.Color.urgent
          onKeysReleased: root.refocusKeys()
          onRefreshRequested: root.refresh()
        }
      }
    }
  }
}
