import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Motion.js" as Motion

// The panel's card in a plain window, for the offscreen platform, where the
// shell's KeyboardPanel, a layer-shell PanelWindow, does not load. Only the
// window is stood in: the card is the shell's BorderSurface, with the
// shell's border spec, padding, and radius. What lives on KeyboardPanel
// itself is copied from /usr/share/omarchy/shell/Ui/KeyboardPanel.qml: the
// properties Panel.qml sets, the card's drawn height and its ease, the
// window's visibility and the focus on open, the card's fade in and out
// where a harness sets `fades`, the content inset and the fitted sizes with
// no screen to cap them, and the card with its content holder without the
// morph from another panel. No
// placement and no twins on other screens: the card sits at the window's
// top left, on a ground no card has.
FloatingWindow {
  id: root

  property Item anchorItem: null
  property QtObject bar: null
  property var owner: null
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property var borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
  property bool open: false
  property Item focusTarget: null

  // From Omarchy 4.5's card, which lib.sh's card_window drops for a shell
  // whose card has none: the card's height on screen, which snaps just after
  // an open, then eases.
  property real drawnHeight: contentHeight
  property bool heightLive: false
  Behavior on drawnHeight {
    enabled: root.heightLive
    NumberAnimation {
      duration: Style.duration(200)
      easing.type: Easing.Bezier
      easing.bezierCurve: Style.easeOut
    }
  }
  Timer {
    id: heightSettle
    interval: 60
    onTriggered: root.heightLive = root.open
  }
  Connections {
    target: root
    function onOpenChanged() {
      root.heightLive = false
      if (root.open) heightSettle.restart()
    }
  }
  // The end of 4.5's card height.
  default property alias contentItem: contentHolder.children
  readonly property alias card: card
  // The window's picture, for FrameGrab: the window's own content item has
  // no QML engine to grab with.
  readonly property alias surface: surface

  readonly property real availableCardWidth: 0
  readonly property real availableCardHeight: 0
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  // With `fades`, the card fades in and out, and the window stays up
  // through the fade: a reopen can come during it.
  property bool fades: false
  property real shown: open ? 1 : 0
  Behavior on shown {
    id: showing
    enabled: root.fades
    NumberAnimation {
      duration: Motion.duration(Style, showing.targetValue > 0 ? 180 : 120)
      easing.type: Easing.Bezier
      easing.bezierCurve: Motion.curve(Style)
    }
  }
  visible: open || shown > 0
  color: "#ff00ff"
  implicitWidth: contentWidth + 40
  implicitHeight: 900

  onOpenChanged: if (open && focusTarget) Qt.callLater(function() { root.focusTarget.forceActiveFocus() })

  Item {
    id: surface
    anchors.fill: parent

    BorderSurface {
      id: card
      width: root.contentWidth
      height: root.drawnHeight
      opacity: root.shown
      // While it grows, the content keeps its own size and the card crops it.
      clip: root.drawnHeight < root.contentHeight - 0.5
      color: Commons.Color.popups.background
      borderSpec: root.borderSpec
      padding: root.padding
      radius: Style.cornerRadius

      Item {
        id: contentHolder
        anchors.top: parent.top
        anchors.left: parent.left
        width: root.contentWidth - card.contentLeftInset - card.contentRightInset
        height: root.contentHeight - card.contentTopInset - card.contentBottomInset
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
      }
    }
  }
}
