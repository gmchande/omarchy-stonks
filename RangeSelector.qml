pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Tones.js" as Tones

// The shared history range control. The words share the row with equal
// space between them, the first starting at its left and the last ending at
// its right, so they line up with the blocks above and below; each token's
// target reaches halfway to its neighbours', so the targets tile the row.
// The chosen one sits in the shell's selected fill, reaching past its word
// as the featured row's does, and alone has a bright label; the hovered one
// takes the hover fill and keeps its dim label, so a hover never reads as a
// second choice; a pressed one takes the pressed fill from the moment the
// button goes down, as the shell's buttons do. A wheel notch is one range,
// however finely the wheel reports it.
Item {
  id: root

  property var options: []
  property string value: "1D"
  property bool retro: false
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  // What is left of a notch between wheel events.
  property real wheelRemainder: 0

  signal selected(string value)

  // The words in the tokens' font, each as wide as it is drawn, and the
  // space between two of them. The row is the caption's line, as the info
  // lines and the list's header are, so the band's gaps are the gaps seen;
  // a token's fill reaches 2 px past it above and below, as the list's
  // name's does, and its target further, to the shell's 22 px.
  readonly property font wordFont: Qt.font({ family: fontFamily, pixelSize: Style.font.caption, bold: true, letterSpacing: 1 })
  FontMetrics { id: metrics; font: root.wordFont }
  implicitHeight: Math.ceil(metrics.ascent) + Math.ceil(metrics.descent)
  // The metrics' font carries the letter spacing, so its advance is the word
  // as drawn. Reading the font measures again on a new text size, or a popup
  // built before `omarchy display text size` overshoots both edges.
  readonly property var wordWidths: {
    var font = metrics.font
    return options.map(function(o) {
      return Math.ceil(metrics.advanceWidth(String(o).toUpperCase()))
    })
  }
  readonly property real wordSpace: options.length > 1
    ? (width - wordWidths.reduce(function(a, b) { return a + b }, 0)) / (options.length - 1) : 0
  function wordX(index) {
    var x = index * wordSpace
    for (var i = 0; i < index; i++) x += wordWidths[i]
    return x
  }

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
      objectName: "rangeOption"
      required property var modelData
      required property int index
      // From halfway to the word before to halfway to the word after.
      x: root.wordX(index) - root.wordSpace / 2
      width: (root.wordWidths[index] || 0) + root.wordSpace
      height: root.height

      readonly property bool chosen: String(modelData) === root.value

      Rectangle {
        objectName: "rangeToken"
        anchors.centerIn: parent
        width: token.implicitWidth + Style.space(12)
        height: parent.height + Style.space(4)
        radius: root.retro ? 0 : Style.cornerRadius
        color: tokenMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
          : parent.chosen ? Style.selectedFillFor(root.foreground, Commons.Color.accent)
          : (tokenMouse.containsMouse ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent")
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }

      Text {
        id: token
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: String(parent.modelData).toUpperCase()
        color: parent.chosen ? root.foreground : root.dim
        font: root.wordFont
        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }

      MouseArea {
        id: tokenMouse
        // 4 px into the gap over the row, short of the chart's own target
        // above, and 8 into the one under it.
        anchors.fill: parent
        anchors.topMargin: -Style.space(4)
        anchors.bottomMargin: -Style.space(8)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.selected(String(parent.modelData))
        onWheel: function(event) { root.wheel(event.angleDelta.y) }
      }
    }
  }
}
