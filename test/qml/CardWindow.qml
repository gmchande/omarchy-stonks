import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The popup's card in a plain window, for the offscreen platform, where the
// shell's KeyboardPanel, a layer-shell PanelWindow, does not load. Only the
// window is stood in: the card is the shell's BorderSurface, with the
// shell's border spec, padding, and radius. What lives on KeyboardPanel
// itself is copied from /usr/share/omarchy/shell/Ui/KeyboardPanel.qml: the
// properties Panel.qml sets (lines 40-63), the window's visibility (81) and
// the focus on open (226-235) without the fade, the content inset and the
// fitted sizes (159-174) with no screen to cap them, and the card with its
// content holder (379-417) without the fade. No placement and no twins on
// other screens: the card sits at the window's top left, on a ground no
// card has.
FloatingWindow {
  id: root

  property Item anchorItem: null
  property QtObject bar: null
  property var owner: null
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  property bool open: false
  property Item focusTarget: null
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

  visible: open
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
      height: root.contentHeight
      color: Color.popups.background
      borderSpec: root.borderSpec
      padding: root.padding
      radius: Style.cornerRadius

      Item {
        id: contentHolder
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
      }
    }
  }
}
