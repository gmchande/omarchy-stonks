pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Motion.js" as Motion

// The watchlist panel: its opening, closing, keys and card. StonksBody
// does the rest; it is built as the panel first opens, and kept.
Panel {
  id: root
  // `moduleName` is the pill's, the plugin's id, which it hands over.

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var plugin: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var service: plugin ? plugin.service : null
  readonly property var updates: plugin ? plugin.updates : null
  readonly property var sounds: plugin ? plugin.sounds : null
  readonly property var camera: plugin ? plugin.camera : null
  readonly property var trendColors: plugin ? plugin.trendColors : null
  readonly property int panelWidth: Style.space(480)
  // Up to six whole rows, at any font or text size.
  readonly property int maxRows: 6
  readonly property var body: bodyLoader.item
  readonly property int heightCap: body ? panel.verticalContentInset + body.chromeHeight
    + maxRows * body.rowPitch - body.rowGap : 0
  readonly property int bodyRoom: Math.min(root.heightCap, panel.availableCardHeight > 0 ? panel.availableCardHeight : root.heightCap)
    - panel.verticalContentInset
  readonly property int fittedCardHeight: body ? panel.fittedContentHeight(body.fittedHeight(root.bodyRoom), root.heightCap) : 0
  // Omarchy 4.5's card eases its own height, as `drawnHeight`. Omarchy
  // 4.0's takes the height it's given at once, so there Stonks eases it, as
  // 1.1.0 did: the card is an item in a full-screen surface, so easing its
  // height resizes no window.
  readonly property bool shellEases: panel.drawnHeight !== undefined
  property real cardHeight: 0
  onFittedCardHeightChanged: if (!root.shellEases && root.opened) easeEdge()
  NumberAnimation { id: edgeEase; target: root; property: "cardHeight"; duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) }
  function easeEdge() {
    edgeEase.stop()
    edgeEase.to = root.fittedCardHeight
    edgeEase.start()
  }
  // The card's edge as drawn, which the footer rides and the rows end at.
  readonly property real shownHeight: shellEases ? panel.drawnHeight : cardHeight
  // On 4.5, an open during the close's fade holds the card at the height on
  // screen until the shell eases its height again, just after the open, so
  // the reset's change (the key sheet giving way to the rows) eases from there.
  property int heldHeight: -1
  Connections {
    target: panel
    ignoreUnknownSignals: true
    function onHeightLiveChanged() { if (panel.heightLive) root.heldHeight = -1 }
  }

  function offerHint() {
    if (!root.opened || !root.body || !service || !service.ready || service.hinted || root.body.notice !== "") return
    root.body.showFirstRunHint()
    service.persist({ hinted: true })
  }
  readonly property bool serviceReady: !!service && service.ready === true
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
    if (opening) root.heldHeight = fading && root.shellEases ? Math.round(panel.drawnHeight) : -1
    bodyLoader.active = true
    root.controller.show()
    // Before offerHint: an update notice goes ahead of the hint.
    if (updates) updates.check()
    if (opening) {
      root.body.resetInteraction()
      offerHint()
      if (!fading) heldAnchor.hold()
      // On 4.0, an open during the close's fade eases the edge from where
      // it is.
      if (!root.shellEases) {
        if (fading) easeEdge()
        else {
          edgeEase.stop()
          root.cardHeight = root.fittedCardHeight
        }
      }
    }
    if (opening) root.body.motion.revealChart()
    Qt.callLater(function() { if (root.opened) setCenterHoverRevealSuppressed(true) })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.body) root.body.freeze()
    // Closing stops Stonks' own ease where it is for the fade.
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
    contentHeight: !root.shellEases ? Math.round(root.cardHeight)
      : root.heldHeight >= 0 ? root.heldHeight : root.fittedCardHeight

    PanelKeyCatcher {
      id: keyCatcher
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      // The body takes its new height at once; the edge eases over it, and
      // rows end at the edge's inner side, never in its padding.
      height: Math.round(root.shownHeight) - panel.verticalContentInset
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
          // The rows' view is judged by the rows' room while the card has
          // shrunk to the key sheet or a view.
          rowsRoom: root.bodyRoom
          // The screen's room, so the first-run hint gives way to the rows.
          screenRoom: panel.availableCardHeight > 0 ? panel.availableCardHeight - panel.verticalContentInset : 0
          edge: Math.round(root.shownHeight) - panel.verticalContentInset
          service: root.service
          updates: root.updates
          sounds: root.sounds
          camera: root.camera
          surfaceOpen: root.opened
          screenOn: !root.service || !root.service.screens || root.service.screens.screenOn(panel.screen)
          switchesPanels: true
          chartHeight: Style.space(190)
          foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          // Opaque: the theme's popup colour may carry an alpha.
          ground: Util.alpha(Commons.Color.popups.background, 1)
          upColor: root.trendColors ? root.trendColors.upOn(ground) : Commons.Color.foreground
          downColor: root.trendColors ? root.trendColors.downOn(ground) : Commons.Color.urgent
          onKeysReleased: root.refocusKeys()
          onRefreshRequested: root.refresh()
        }
      }
    }
  }
}
