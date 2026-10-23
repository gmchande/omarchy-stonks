import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tones.js" as Tones

// Pinned "+ Add a symbol" bar. Surfaces own the add flow. For a moment it can
// carry a note instead, in the foreground: why a key did nothing, with what
// a click does about it (`noteAction`), said whole so a long list name is
// what gets cut. It stays while the pointer is on it (`hovered`). Until what
// it says is fixed, a notice, in the foreground too, under any note, whose
// click is the surface's (`acts`), its action said whole as a note's is
// (`noticeAction`). A hint for the visit is a quiet line of its own above
// the bar, which it never replaces, and takes no click; the surface can have
// it give way (`showsHint`). For a few seconds after a removal, an undo
// stands at the bar's right end, a button of its own (`undoLabel`), so the
// add beside it never waits: its words stay centred on the whole bar, where
// they always are. It is painted in its surface's ground, so riding a
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
  property string noticeAction: ""
  // The notice in fewer words, shown whole where the notice won't fit:
  // a notice cut mid-word reads as broken. "" when it has no shorter form.
  property string noticeShort: ""
  property string hint: ""
  // Whether the hint shows. Its room (`hintRoom`) is measured either way,
  // so the surface can judge whether it fits without reading it back.
  property bool showsHint: true
  // A click does something: the add, or the notice's own action.
  property bool acts: true
  property string label: "+  Add a symbol"
  // The add in fewer words, shown where the add won't fit, as beside an
  // undo: a list's name is never cut. "" when it has no shorter form.
  property string labelShort: ""
  property color ground: "transparent"
  // The undo on offer, "Undo NVDA", or "" for none; it fades out with
  // `undoOpacity`, and stays while the pointer is on it (`undoHovered`).
  property string undoLabel: ""
  property real undoOpacity: 1
  readonly property bool undoHovered: undoMouse.containsMouse
  // The undo's button and the gap before it, none without an offer.
  readonly property real undoRoom: undoLabel !== "" ? undoText.implicitWidth + Style.space(20) + Style.space(4) : 0

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
  signal undoClicked()

  // The hint's lines and the gap under them, above the bar, whether or not
  // they show; and what they take, none without a hint showing.
  readonly property int hintRoom: hint !== "" ? hintText.implicitHeight + Style.space(6) : 0
  readonly property int hintHeight: showsHint ? hintRoom : 0
  // The bar and the gap over it, under the hint.
  readonly property int barHeight: rowHeight + Style.space(6)

  implicitHeight: hintHeight + barHeight
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    color: root.ground
  }

  Text {
    id: hintText
    objectName: "footerHint"
    visible: root.hint !== "" && root.showsHint
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
    anchors.rightMargin: root.gutter + root.undoRoom
    radius: root.retro ? 0 : Style.cornerRadius
    color: !root.acts ? "transparent"
      : addMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
      : addMouse.containsMouse ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"

    // The words centred on the whole bar, so an undo coming or going moves
    // nothing, unless that would run them into the undo: then the box they
    // centre in narrows, to end just clear of it. Centred by anchors, so
    // they land on the pixel they always did.
    Item {
      width: Math.min(root.width - root.gutter, 2 * (root.width - root.gutter - root.undoRoom - Style.space(10)) - footerRow.width)
      height: parent.height

      Row {
        id: footerRow
        anchors.centerIn: parent

        // The words whole, measured, never shown: where they don't fit
        // beside their action and clear of the undo, their short form shows
        // (`noticeShort`, `labelShort`).
        Text {
          id: fullWords
          visible: false
          textFormat: Text.PlainText
          text: root.note !== "" ? root.note : root.notice !== "" ? root.notice : root.label
          font: footerWords.font
        }
        Text {
          id: footerWords
          objectName: "footerText"
          // Clear of the undo.
          readonly property real room: root.width - root.gutter - root.undoRoom - Style.space(20) - (noteAction.visible ? noteAction.implicitWidth : 0)
          width: Math.min(implicitWidth, room)
          elide: Text.ElideRight
          // Cut short, it ends against its action, not a gap's width away.
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: root.note === "" && shortWords !== "" && fullWords.implicitWidth > room ? shortWords : fullWords.text
          readonly property string shortWords: root.notice !== "" ? root.noticeShort : root.labelShort
          color: root.note !== "" || root.notice !== "" ? root.foreground : root.dim
          opacity: root.note !== "" ? root.noteOpacity : root.coveredOpacity
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          id: noteAction
          objectName: "footerAction"
          visible: text !== ""
          textFormat: Text.PlainText
          text: root.note !== "" ? root.noteAction : root.notice !== "" ? root.noticeAction : ""
          color: root.foreground
          opacity: root.note !== "" ? root.noteOpacity : root.coveredOpacity
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
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

  Rectangle {
    objectName: "footerUndo"
    visible: root.undoLabel !== ""
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.topMargin: root.hintHeight + Style.space(6)
    anchors.right: parent.right
    anchors.rightMargin: root.gutter
    width: root.undoRoom - Style.space(4)
    radius: root.retro ? 0 : Style.cornerRadius
    opacity: root.undoOpacity
    color: undoMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
      : undoMouse.containsMouse ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"

    Text {
      id: undoText
      objectName: "footerUndoText"
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.undoLabel
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: undoMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.undoClicked()
      // A double-click is one click: the undo, then nothing.
      onDoubleClicked: {}
    }
  }
}
