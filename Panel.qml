pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The watchlist panel: its opening, closing, keys and card. StonksBody
// does the rest; it is built as the panel first opens, and kept.
Panel {
  id: root
  moduleName: "grvc.stonks"
  ipcTarget: "grvc.stonks"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var plugin: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("grvc.stonks") : null
  readonly property var service: plugin ? plugin.service : null
  readonly property var updates: plugin ? plugin.updates : null
  readonly property var sounds: plugin ? plugin.sounds : null
  readonly property var camera: plugin ? plugin.camera : null
  readonly property var trendColors: plugin ? plugin.trendColors : null
  readonly property string range: service ? service.range : "1D"
  readonly property int panelWidth: Style.space(480)
  // Six whole rows at any font or text size.
  readonly property int maxRows: 6
  readonly property var body: bodyLoader.item
  readonly property int heightCap: body ? panel.verticalContentInset + body.chromeHeight
    + maxRows * body.rowPitch - body.rowGap : 0
  readonly property int bodyRoom: Math.min(root.heightCap, panel.availableCardHeight > 0 ? panel.availableCardHeight : root.heightCap)
    - panel.verticalContentInset
  readonly property int fittedCardHeight: body ? panel.fittedContentHeight(body.fittedHeight(root.bodyRoom), root.heightCap) : 0
  // The shell's card is an item in a full-screen surface, so easing its
  // height resizes no window.
  property real cardHeight: 0
  onFittedCardHeightChanged: if (root.opened) easeEdge()
  NumberAnimation { id: edgeEase; target: root; property: "cardHeight"; duration: 160; easing.type: Easing.OutCubic }
  function easeEdge() {
    edgeEase.stop()
    edgeEase.to = root.fittedCardHeight
    edgeEase.start()
  }

  function offerHint() {
    if (!root.opened || !root.body || !service || !service.pluginsReady || service.hinted || root.body.notice !== "") return
    root.body.showFirstRunHint()
    service.persist({ hinted: true })
  }
  readonly property bool serviceReady: !!service && service.pluginsReady === true
  onServiceReadyChanged: offerHint()

  // An open during the close's fade leaves the card where it is on screen.
  HeldAnchor {
    id: heldAnchor
    pill: root.anchorItem
  }

  // Shown first, so the body reads the service again and the reset lays out
  // the latest.
  function open() {
    var opening = !root.opened
    var fading = opening && panel.visible
    bodyLoader.active = true
    root.controller.show()
    // Before offerHint: an update notice goes ahead of the hint.
    if (updates) updates.check()
    if (opening) {
      root.body.resetInteraction()
      offerHint()
      if (fading) easeEdge()
      else {
        heldAnchor.hold()
        edgeEase.stop()
        root.cardHeight = root.fittedCardHeight
      }
    }
    if (opening) root.body.motion.revealChart()
    Qt.callLater(function() { if (root.opened) setCenterHoverRevealSuppressed(true) })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.body) root.body.freeze()
    edgeEase.stop()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  function refresh() {
    if (service) service.refresh()
  }

  function refocusKeys() { Qt.callLater(function() { if (bodyKeys) bodyKeys.forceActiveFocus() }) }

  KeyboardPanel {
    id: panel
    anchorItem: heldAnchor
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: bodyKeys
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: Math.round(root.cardHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The body takes its new height at once; the edge eases over it.
      clip: true
      blocked: !!root.body && root.body.ownsKeys
      // Omarchy's panel keys: j k and h l move, Space activates, x removes.
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.body.moveCursor(dy)
        if (dx !== 0) root.body.nudgeScrub(dx)
      }
      onActivateRequested: root.body.featureSymbol(root.body.watchlist.cursorRow)
      onDeleteRequested: root.body.removeRow(root.body.watchlist.cursorRow)
      onCloseRequested: {
        if (root.body.showingHelp) root.body.showingHelp = false
        else if (!root.body.endScrub()) root.close()
      }
      onTabRequested: function(direction) {
        root.body.showingHelp = false
        root.switchPanel(direction)
      }

      // Keys reach the body's map first; any it leaves go on to the catcher.
      Item {
        id: bodyKeys
        Keys.onPressed: function(event) {
          if (!keyCatcher.blocked && root.body.pressKey(event)) event.accepted = true
        }
      }

      Loader {
        id: bodyLoader
        active: false
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.fittedCardHeight - panel.verticalContentInset
        sourceComponent: StonksBody {
          rowsRoom: root.bodyRoom
          screenRoom: panel.availableCardHeight > 0 ? panel.availableCardHeight - panel.verticalContentInset : 0
          edge: Math.round(root.cardHeight) - panel.verticalContentInset
          service: root.service
          updates: root.updates
          sounds: root.sounds
          camera: root.camera
          surfaceOpen: root.opened
          switchesPanels: true
          chartHeight: Style.space(190)
          foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          // Opaque: the theme's popup colour may carry an alpha.
          ground: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g, Commons.Color.popups.background.b, 1)
          upColor: root.trendColors ? root.trendColors.upOn(ground) : Commons.Color.foreground
          downColor: root.trendColors ? root.trendColors.downOn(ground) : Commons.Color.urgent
          onKeysReleased: root.refocusKeys()
          onRefreshRequested: root.refresh()
        }
      }
    }
  }
}
