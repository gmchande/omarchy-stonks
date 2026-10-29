import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tones.js" as Tones

// Pinned "+ Add a symbol" bar; surfaces own the add flow. For a moment it
// can carry a note instead, in the foreground: why a key did nothing. It
// stays while the pointer is on it (`hovered`). Until what it says is fixed,
// a notice, also in the foreground, sits under any note; its click is the
// surface's (`acts`). It stays whole, with what to do beside it or on a
// line of its own (`noticeActions`). A hint for the visit is a quiet line
// above the bar, never replacing it and taking no click; the surface can
// have it give way (`showsHint`). For a few seconds after a removal, an undo
// stands at the bar's right end as its own button (`undoLabel`), so the add
// never waits and its words stay centred on the whole bar. While a newer
// Stonks is out, that place holds its update (`updateLabel`), which gives
// way to an undo. The bar is painted in its surface's ground, so riding a
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
  property string notice: ""
  // What to do about the notice, longest first, said whole: beside the
  // notice where both fit, else on a line of its own, never cutting the
  // notice (`noticeShown`). Empty for a notice that says it all.
  property var noticeActions: []
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
  // The update on offer, "Update to 1.1.0", or "" for none.
  property string updateLabel: ""
  // What the bar's right end holds: the undo while one is on offer, else
  // the update.
  readonly property bool undoing: undoLabel !== ""
  readonly property string sideLabel: undoing ? undoLabel : updateLabel
  // That button and the gap before it, none without one.
  readonly property real undoRoom: sideLabel !== "" ? undoText.implicitWidth + Style.space(20) + Style.space(4) : 0

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
  signal updateClicked()

  // The hint's lines and the gap under them, above the bar, whether or not
  // they show; and what they take, none without a hint showing.
  readonly property int hintRoom: hint !== "" ? hintText.implicitHeight + Style.space(6) : 0
  readonly property int hintHeight: showsHint ? hintRoom : 0
  // The hint as drawn: a line of two actions joined by " · " that won't fit
  // gives each action its own line, never one word wrapped alone (the
  // owner, 28 October). The font is read so a new text size measures again.
  readonly property string hintLines: {
    var room = width - gutter
    var font = hintMetrics.font
    return hint.split("\n").map(function(line) {
      if (line.indexOf(" · ") < 0 || hintMetrics.advanceWidth(line) <= room) return line
      return line.split(" · ").map(function(part) { return part.charAt(0).toUpperCase() + part.slice(1) }).join("\n")
    }).join("\n")
  }
  FontMetrics {
    id: hintMetrics
    font: hintText.font
  }
  // The notice's action as shown, and on how many lines: the whole action
  // beside the notice where both fit clear of the bar's end button, else on
  // a line of its own, capitalised, in the longest form that fits there
  // (the owner, 28 October: clear beats compact for what needs fixing).
  readonly property var noticeShown: {
    if (notice === "" || noticeActions.length === 0) return { action: "", lines: 1 }
    var room = width - gutter - undoRoom - Style.space(20)
    var font = footerMetrics.font
    if (footerMetrics.advanceWidth(notice + " · " + noticeActions[0]) <= room) return { action: " · " + noticeActions[0], lines: 1 }
    var own = noticeActions.map(function(a) { return a.charAt(0).toUpperCase() + a.slice(1) })
    for (var j = 0; j < own.length - 1; j++)
      if (footerMetrics.advanceWidth(own[j]) <= room) return { action: own[j], lines: 2 }
    return { action: own[own.length - 1], lines: 2 }
  }
  FontMetrics {
    id: footerMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
  // The bar and the gap over it, under the hint: a row's height, or a
  // notice's two lines and their padding where it takes two.
  readonly property int barHeight: Math.max(rowHeight, footerRow.implicitHeight + Style.space(8)) + Style.space(6)

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
    text: root.hintLines
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

    // The words centred on the whole bar, so the button at its end coming
    // or going moves nothing, unless that would run them into it: then the
    // box they centre in narrows, to end just clear of it. Centred by
    // anchors, so they land on the pixel they always did.
    Item {
      width: Math.min(root.width - root.gutter, 2 * (root.width - root.gutter - root.undoRoom - Style.space(10)) - footerRow.width)
      height: parent.height

      // One line, or a notice over its action where both don't fit
      // (`noticeShown`), each line centred.
      Grid {
        id: footerRow
        anchors.centerIn: parent
        readonly property bool twoLines: root.note === "" && root.notice !== "" && root.noticeShown.lines === 2
        columns: twoLines ? 1 : 2
        horizontalItemAlignment: Grid.AlignHCenter

        // The words whole, measured, never shown: where they don't fit
        // clear of the undo, their short form shows (`labelShort`), so a
        // long list name is what gets cut. A notice stays whole.
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
          // Clear of the button at the bar's end, and of the action beside it.
          readonly property real room: root.width - root.gutter - root.undoRoom - Style.space(20)
            - (noteAction.visible && !footerRow.twoLines ? noteAction.implicitWidth : 0)
          width: Math.min(implicitWidth, room)
          elide: Text.ElideRight
          // Cut short, it ends against its action, not a gap's width away.
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: root.note === "" && root.notice === "" && root.labelShort !== "" && fullWords.implicitWidth > room ? root.labelShort : fullWords.text
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
          text: root.note === "" && root.notice !== "" ? root.noticeShown.action : ""
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
    visible: root.sideLabel !== ""
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.topMargin: root.hintHeight + Style.space(6)
    anchors.right: parent.right
    anchors.rightMargin: root.gutter
    width: root.undoRoom - Style.space(4)
    radius: root.retro ? 0 : Style.cornerRadius
    opacity: root.undoing ? root.undoOpacity : 1
    color: undoMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
      : undoMouse.containsMouse ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"

    Text {
      id: undoText
      objectName: "footerUndoText"
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.sideLabel
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: undoMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.undoing ? root.undoClicked() : root.updateClicked()
      // A double-click is one click: the undo or the update, then nothing.
      onDoubleClicked: {}
    }
  }
}
