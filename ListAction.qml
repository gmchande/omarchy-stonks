import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Motion.js" as Motion

// A word that acts as a button, on the shell's resting fill (Style's
// normal fill) so it reads as one before the pointer finds it. A disabled
// MouseArea keeps the hover it had, so `hovered` checks `enabled` too.
Text {
  id: root

  property Look look
  // Marked as the shell marks its default button (its Button's `selected`,
  // ConfirmDialog's chosen one).
  property bool enterTakes: false
  property bool still: false
  readonly property bool hovered: enabled && mouse.containsMouse

  signal activated()

  textFormat: Text.PlainText
  color: enterTakes ? Style.selectedStateColor(look.foreground, Commons.Color.accent)
    : hovered ? look.foreground : look.dim
  Behavior on color { enabled: !root.still; ColorAnimation { duration: Motion.duration(Style, 120) } }
  scale: enabled && mouse.pressed ? 0.97 : 1
  Behavior on scale {
    enabled: !root.still
    NumberAnimation {
      duration: Motion.duration(Style, 160)
      easing.type: Easing.Bezier
      easing.bezierCurve: Motion.curve(Style)
    }
  }
  font.family: look.fontFamily
  font.pixelSize: Style.font.caption
  font.bold: true
  font.letterSpacing: 1

  Rectangle {
    z: -1
    // Inside today's room: the gap between two buttons in a row stays
    // open, and the box centres on the letters, not their last spacing.
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: -root.font.letterSpacing / 2
    width: parent.implicitWidth - root.font.letterSpacing + Style.space(10)
    height: parent.implicitHeight + Style.space(6)
    radius: root.look.retro ? 0 : Style.cornerRadius
    // The pressed fill while the button is down.
    color: mouse.pressed ? Style.pressedFillFor(root.look.foreground, Commons.Color.accent)
      : root.hovered ? Style.hoverFillFor(root.look.foreground, Commons.Color.accent)
      : root.enterTakes ? Style.selectedFillFor(root.look.foreground, Commons.Color.accent)
      : Style.normalFillFor(root.look.foreground, Commons.Color.accent)
    Behavior on color { enabled: !root.still; ColorAnimation { duration: Motion.duration(Style, 120) } }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    anchors.margins: -Style.space(6)
    scale: 1 / parent.scale
    hoverEnabled: true
    // One that can't act shows no hand, so it never invites a click.
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.activated()
  }
}
