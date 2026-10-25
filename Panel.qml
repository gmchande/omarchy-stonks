pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "KeyText.js" as KeyText

// The watchlist popup. Owns popup lifecycle, keys, and look; the body reads
// the service and owns the list, search, scrub, help, and the motion when
// the chart changes. The body is built as the popup first opens, and kept.
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
  readonly property string featuredSymbol: service ? service.featuredSymbol : ""
  readonly property string range: service ? service.range : "1D"
  readonly property int panelWidth: Style.space(480)
  // The popup shows up to six whole rows under its fixed content. Stated in
  // rows, so a different font or text size still gets six.
  readonly property int maxRows: 6
  // Built as the popup first opens, and kept: null until then.
  readonly property var body: bodyLoader.item
  readonly property int heightCap: body ? panel.verticalContentInset + body.chromeHeight
    + maxRows * body.rowPitch - body.rowGap : 0
  // The card's height for what the body shows: whole rows up to the cap, so
  // the footer ends the popup with no gap, or a view's own height. The
  // body's room is the most the card gives it.
  readonly property int bodyRoom: Math.min(root.heightCap, panel.availableCardHeight > 0 ? panel.availableCardHeight : root.heightCap)
    - panel.verticalContentInset
  readonly property int fittedCardHeight: body ? panel.fittedContentHeight(body.fittedHeight(root.bodyRoom), root.heightCap) : 0
  // While the popup is open its edge eases to that height, so a view that
  // changes it moves the edge instead of jumping it; the body lays out at
  // the new height at once and the card's edge reveals or covers it, the
  // footer riding it. The shell's card is an item
  // inside a full-screen surface, so no window resizes. Closing stops the
  // edge where it is for the fade. An open from closed settles it before
  // the first frame; one during the close's fade eases from where it is.
  property real cardHeight: 0
  onFittedCardHeightChanged: if (root.opened) easeEdge()
  NumberAnimation { id: edgeEase; target: root; property: "cardHeight"; duration: 160; easing.type: Easing.OutCubic }
  function easeEdge() {
    edgeEase.stop()
    edgeEase.to = root.fittedCardHeight
    edgeEase.start()
  }

  // The first visit there ever was says how Stonks is moved and changed,
  // once: the service saves that it has. A popup opened while the service
  // still reads its file says it as soon as the service is ready. A visit
  // whose footer has a notice ahead of the hint (the data file can't be
  // read, a save didn't land, an update waits) neither shows nor records
  // it: a later one does.
  function offerHint() {
    if (!root.opened || !root.body || !service || !service.pluginsReady || service.hinted || root.body.notice !== "") return
    root.body.showFirstRunHint()
    service.persist({ hinted: true })
  }
  readonly property bool serviceReady: !!service && service.pluginsReady === true
  onServiceReadyChanged: offerHint()

  // The card's place along the bar, held from an open from closed until the
  // next; an open during the close fade keeps it, since the card is still on
  // screen.
  HeldAnchor {
    id: heldAnchor
    pill: root.anchorItem
  }

  // The views reset as the popup opens, before its first frame, not as it
  // closes: the card fades out showing what you were looking at. Shown
  // first, so the body reads the service again (its held inputs) and the
  // reset lays out the latest. An open while open changes nothing on screen.
  function open() {
    var opening = !root.opened
    var fading = opening && panel.visible
    bodyLoader.active = true
    root.controller.show()
    // Before the hint is offered: the footer's notices go ahead of it.
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
    requestFundamentals()
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

  // The cap and P/E for the symbol on show while the popup is open; the
  // service asks for the chart's history itself.
  function requestFundamentals() {
    if (root.opened && service && featuredSymbol) service.fetchFundamentals(featuredSymbol)
  }

  function refresh() {
    if (service) service.refresh()
    requestFundamentals()
  }

  function refocusKeys() { Qt.callLater(function() { if (letterKeys) letterKeys.forceActiveFocus() }) }

  onFeaturedSymbolChanged: requestFundamentals()

  KeyboardPanel {
    id: panel
    anchorItem: heldAnchor
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: letterKeys
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: Math.round(root.cardHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The body is laid out at the card's new height while the edge eases.
      clip: true
      blocked: !!root.body && root.body.ownsKeys
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.body.moveCursor(dy)
        if (dx !== 0) root.body.nudgeScrub(dx)
      }
      onActivateRequested: root.body.featureSymbol(root.body.watchlist.cursorRow)
      onCloseRequested: {
        if (root.body.showingHelp) root.body.showingHelp = false
        else if (!root.body.endScrub()) root.close()
      }
      onDeleteRequested: root.body.removeRow(root.body.watchlist.cursorRow)
      onTabRequested: function(direction) {
        root.body.showingHelp = false
        root.switchPanel(direction)
      }
      onTextKey: function(t) { root.body.pressKey(t) }

      // The popup's keys land here first. The catcher reads a key's text,
      // and Caps Lock sends "J" for j, which would move a row: a letter
      // goes on as the text its key and Shift mean (`KeyText.typed`).
      // Delete and Backspace, which the catcher doesn't read, remove the
      // row, as in the window. Every other key goes on to the catcher.
      Item {
        id: letterKeys
        Keys.onPressed: function(event) {
          if (keyCatcher.blocked) return
          if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            root.body.removeRow(root.body.watchlist.cursorRow)
            event.accepted = true
            return
          }
          if (event.key < Qt.Key_A || event.key > Qt.Key_Z) return
          var t = KeyText.typed(event)
          if (t === "") return
          keyCatcher.textKey(t)
          event.accepted = true
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
          // The rows' room, so the list judges its sight by the rows' view
          // while the card has shrunk to the key sheet or a view.
          rowsRoom: root.bodyRoom
          // The screen's room, so the first-run hint gives way to the rows.
          screenRoom: panel.availableCardHeight > 0 ? panel.availableCardHeight - panel.verticalContentInset : 0
          // The card's edge as it eases: the footer and the field ride it.
          edge: Math.round(root.cardHeight) - panel.verticalContentInset
          service: root.service
          updates: root.updates
          sounds: root.sounds
          camera: root.camera
          surfaceOpen: root.opened
          chartHeight: Style.space(190)
          foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          // The card's colour, opaque whatever the theme's popup alpha.
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
