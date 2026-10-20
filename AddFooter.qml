import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tones.js" as Tones

// Pinned "+ Add a symbol" bar. Surfaces own the add flow. For a moment it can
// carry a note instead, in the foreground: why a key did nothing, or what a
// removal took, with what a click does about it (`noteAction`), said whole
// so a long list name is what gets cut. It stays while the pointer is on
// it (`hovered`). Until what it says is fixed, a notice, in the foreground
// too, under any note, whose click is the surface's (`acts`). A hint for the
// visit is a quiet line of its own above the bar, which it never replaces,
// and takes no click. It is painted in its surface's ground, so riding a
// growing edge it covers the rows it passes.
Item {
  id: root

  property bool retro: false
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.space(30)
  // The scrollbar's gutter at the right, which the rows stop short of: the
  // footer's words and fill line up with theirs. Its ground still spans it.
  property int gutter: 0
  property string note: ""
  property string noteAction: ""
  property string notice: ""
  property string hint: ""
  // A click does something: the add, an undo, or the notice's own action.
  property bool acts: true
  property string label: "+  Add a symbol"
  property color ground: "transparent"

  readonly property bool hovered: addMouse.containsMouse
  // The note as its moment ends, 1 to 0; what it covered fades in after it
  // (fadeIn), in the house 160 ms.
  property real noteOpacity: 1
  property real coveredOpacity: 1
  function fadeIn() { coveredIn.restart() }
  // Closing stops the fade where it is; an open shows it whole.
  function freeze() { coveredIn.stop() }
  function settle() {
    coveredIn.stop()
    coveredOpacity = 1
  }
  NumberAnimation {
    id: coveredIn
    target: root
    property: "coveredOpacity"
    from: 0
    to: 1
    duration: 160
    easing.type: Easing.OutCubic
  }

  signal clicked()

  // The hint's lines and the gap under them, above the bar; none without one.
  readonly property int hintHeight: hint !== "" ? hintText.implicitHeight + Style.space(6) : 0

  implicitHeight: hintHeight + rowHeight + Style.space(6)
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    color: root.ground
  }

  Text {
    id: hintText
    objectName: "footerHint"
    visible: root.hint !== ""
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.rightMargin: root.gutter
    // A line wider than the card, at a theme's own spacing, wraps; the hint
    // takes the height it needs.
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
    text: root.hint
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  PanelSeparator {
    y: root.hintHeight
    width: root.width - root.gutter
    foreground: root.foreground
    strength: 0.08
  }

  Rectangle {
    objectName: "footerFill"
    anchors.fill: parent
    anchors.topMargin: root.hintHeight + Style.space(6)
    anchors.rightMargin: root.gutter
    radius: root.retro ? 0 : Style.cornerRadius
    color: !root.acts ? "transparent"
      : addMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
      : addMouse.containsMouse ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"

    Row {
      anchors.centerIn: parent

      Text {
        objectName: "footerText"
        width: Math.min(implicitWidth, root.width - root.gutter - Style.space(20) - (noteAction.visible ? noteAction.implicitWidth : 0))
        elide: Text.ElideRight
        // Cut short, it ends against its action, not a gap's width away.
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: root.note !== "" ? root.note : root.notice !== "" ? root.notice : root.label
        color: root.note !== "" || root.notice !== "" ? root.foreground : root.dim
        opacity: root.note !== "" ? root.noteOpacity : root.coveredOpacity
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        id: noteAction
        objectName: "footerAction"
        visible: root.note !== "" && root.noteAction !== ""
        textFormat: Text.PlainText
        text: root.noteAction
        color: root.foreground
        opacity: root.noteOpacity
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      id: addMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: root.acts ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.clicked()
      // A double-click is one click: an undo, then not a search.
      onDoubleClicked: {}
    }
  }
}
