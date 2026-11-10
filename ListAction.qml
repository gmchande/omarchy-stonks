import QtQuick
import qs.Commons
import qs.Commons as Commons

// A word that acts as a button. A disabled MouseArea keeps the hover it
// had, so `hovered` checks `enabled` too.
Text {
  id: root

  property Look look
  // Square corners. The key sheet's CLOSE keeps round ones in retro too.
  property bool retro: look.retro
  // Marked as the shell marks its default button (its Button's `selected`,
  // ConfirmDialog's chosen one).
  property bool enterTakes: false
  readonly property bool hovered: enabled && mouse.containsMouse

  signal activated()

  textFormat: Text.PlainText
  color: enterTakes ? Style.selectedStateColor(look.foreground, Commons.Color.accent)
    : hovered ? look.foreground : look.dim
  font.family: look.fontFamily
  font.pixelSize: Style.font.caption
  font.bold: true
  font.letterSpacing: 1

  Rectangle {
    objectName: "actionFill"
    z: -1
    anchors.centerIn: parent
    width: parent.implicitWidth + Style.space(12)
    height: parent.implicitHeight + Style.space(4)
    radius: root.retro ? 0 : Style.cornerRadius
    // The pressed fill while the button is down.
    color: mouse.pressed ? Style.pressedFillFor(root.look.foreground, Commons.Color.accent)
      : root.hovered ? Style.hoverFillFor(root.look.foreground, Commons.Color.accent)
      : root.enterTakes ? Style.selectedFillFor(root.look.foreground, Commons.Color.accent) : "transparent"
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    anchors.margins: -Style.space(6)
    hoverEnabled: true
    // One that can't act shows no hand, so it never invites a click.
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.activated()
  }
}
