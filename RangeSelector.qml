pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "Tones.js" as Tones

// The shared history range control. Each token gets an equal slice of the
// row so the full set stays on one line in the popup; the chosen one sits in
// the shell's selected fill, the way the featured row does, and alone has a
// bright label; the one under the pointer takes the hover fill and keeps its
// dim label, so a hover never reads as a second choice; and a pressed one
// takes the pressed fill from the moment the button goes down, as the
// shell's buttons do. The tokens tile the whole row, so each takes the wheel
// itself: a notch is one range, however finely the wheel reports it.
Item {
  id: root

  property var options: []
  property string value: "1D"
  property bool retro: false
  property color foreground: Color.foreground
  property color dim: Tones.dim(foreground, Color.background)
  property string fontFamily: Style.font.family
  // What is left of a notch between wheel events.
  property real wheelRemainder: 0

  signal selected(string value)

  implicitHeight: Style.space(18)

  function step(delta) {
    var index = options.indexOf(value)
    var target = Math.max(0, Math.min(options.length - 1, index + delta))
    if (target !== index) selected(String(options[target]))
  }

  // A notch up is the shorter range, the way the list scrolls up.
  function wheel(angleDelta) {
    var notches = Util.wheelSteps(wheelRemainder, angleDelta)
    wheelRemainder = notches.remainder
    if (notches.steps !== 0) step(-notches.steps)
  }

  Repeater {
    model: root.options

    Item {
      required property var modelData
      required property int index
      x: index * root.width / root.options.length
      width: root.width / root.options.length
      height: root.height

      readonly property bool chosen: String(modelData) === root.value

      Rectangle {
        objectName: "rangeToken"
        anchors.centerIn: parent
        width: token.implicitWidth + Style.space(12)
        height: parent.height
        radius: root.retro ? 0 : Style.cornerRadius
        color: tokenMouse.pressed ? Style.pressedFillFor(root.foreground, Color.accent)
          : parent.chosen ? Style.selectedFillFor(root.foreground, Color.accent)
          : (tokenMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }

      Text {
        id: token
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: String(parent.modelData).toUpperCase()
        color: parent.chosen ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1

        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }

      MouseArea {
        id: tokenMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.selected(String(parent.modelData))
        onWheel: function(event) { root.wheel(event.angleDelta.y) }
      }
    }
  }
}
