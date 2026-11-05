import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tones.js" as Tones

// The pinned "+ Add a symbol" bar. A note there says for a moment why a key
// did nothing; a notice says, until it is fixed, what needs fixing. Painted
// in its surface's ground, it covers the rows it passes on a growing edge.
Item {
  id: root

  property bool retro: false
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.space(30)
  // The rows' scrollbar gutter: the words and fill stop short of it, the
  // ground doesn't.
  property int gutter: 0
  property string note: ""
  property string notice: ""
  // Longest first; empty when the notice says it all.
  property var noticeActions: []
  property string hint: ""
  property bool showsHint: true
  // A click does something: the add, or the notice's own action.
  property bool acts: true
  property string label: "+  Add a symbol"
  // Shown where `label` won't fit, as beside an undo; "" when there is none.
  property string labelShort: ""
  property color ground: "transparent"
  // "Undo NVDA", or "" for none.
  property string undoLabel: ""
  property real undoOpacity: 1
  // The undo stays while the pointer is on it.
  readonly property bool undoHovered: undoMouse.containsMouse
  property string updateLabel: ""
  readonly property bool undoing: undoLabel !== ""
  readonly property string sideLabel: undoing ? undoLabel : updateLabel
  readonly property real undoRoom: sideLabel !== "" ? undoText.implicitWidth + Style.space(20) + Style.space(4) : 0

  // A note stays while the pointer is on the bar.
  readonly property bool hovered: addMouse.containsMouse
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
    duration: Style.duration(160)
    easing.type: Easing.Bezier
    easing.bezierCurve: Style.easeOut
  }

  signal clicked()
  signal undoClicked()
  signal updateClicked()

  // A button as the shell draws one (Ui/Button.qml, `bordered`): the
  // theme's border at rest, the cursor's border and fill under the pointer,
  // the pressed fill, and a little give while held. `mouse` is its own.
  component FooterButton: BorderSurface {
    property MouseArea mouse: null
    property bool acts: true
    property bool retro: false
    property color foreground: Commons.Color.foreground
    readonly property bool hot: acts && !!mouse && mouse.containsMouse
    radius: retro ? 0 : Style.cornerRadius
    color: !acts || !mouse ? "transparent"
      : mouse.pressed ? Style.pressedFillFor(foreground, Commons.Color.accent)
      : hot ? Style.hoverFillFor(foreground, Commons.Color.accent) : "transparent"
    Behavior on color { ColorAnimation { duration: Style.duration(120) } }
    borderSpec: !acts ? Border.none()
      : Border.controlSpec(hot ? "hover-cursor" : "normal", foreground, Commons.Color.accent)
    scale: acts && !!mouse && mouse.pressed ? 0.97 : 1
    Behavior on scale {
      NumberAnimation {
        duration: Style.duration(160)
        easing.type: Easing.Bezier
        easing.bezierCurve: Style.easeOut
      }
    }
  }

  // Measured even while the hint is hidden, so the surface can judge whether
  // it fits.
  readonly property int hintRoom: hint !== "" ? hintText.implicitHeight + Style.space(6) : 0
  readonly property int hintHeight: showsHint ? hintRoom : 0
  // Two actions joined by " · " that don't fit go on a line each, never one
  // word wrapped alone. Reading the font measures again at a new text size.
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
  // The action goes beside the notice only whole; a shorter form takes a
  // line of its own, so the action never cuts the notice.
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
  // A note covers a notice for a moment in the notice's room, so nothing
  // under or over the bar moves.
  readonly property int wordLines: notice !== "" ? noticeShown.lines : 1
  readonly property int barHeight: Math.max(rowHeight, footerWords.implicitHeight * wordLines + Style.space(8)) + Style.space(6)

  implicitHeight: hintHeight + barHeight
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    color: root.ground
  }

  // The hint takes no click.
  Text {
    id: hintText
    objectName: "footerHint"
    visible: root.hint !== "" && root.showsHint
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.rightMargin: root.gutter
    // At a theme's own spacing a line can be wider than the card.
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
    textFormat: Text.PlainText
    text: root.hintLines
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  FooterButton {
    objectName: "footerFill"
    anchors.fill: parent
    anchors.topMargin: root.hintHeight + Style.space(6)
    anchors.rightMargin: root.gutter + root.undoRoom
    mouse: addMouse
    acts: root.acts
    retro: root.retro
    foreground: root.foreground

    // Centred on the whole bar, so the end button coming or going moves
    // nothing, unless the words would run into it.
    Item {
      width: Math.min(root.width - root.gutter, 2 * (root.width - root.gutter - root.undoRoom - Style.space(10)) - footerRow.width)
      height: parent.height

      Grid {
        id: footerRow
        anchors.centerIn: parent
        readonly property bool twoLines: root.note === "" && root.notice !== "" && root.noticeShown.lines === 2
        columns: twoLines ? 1 : 2
        horizontalItemAlignment: Grid.AlignHCenter

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
      // Undoes the press's give, so a press near the edge still counts.
      scale: 1 / parent.scale
      hoverEnabled: true
      cursorShape: root.acts ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.clicked()
      // A double-click is one click: an undo, then not a search.
      onDoubleClicked: {}
    }
  }

  FooterButton {
    objectName: "footerUndo"
    visible: root.sideLabel !== ""
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.topMargin: root.hintHeight + Style.space(6)
    anchors.right: parent.right
    anchors.rightMargin: root.gutter
    width: root.undoRoom - Style.space(4)
    opacity: root.undoing ? root.undoOpacity : 1
    mouse: undoMouse
    retro: root.retro
    foreground: root.foreground

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
      scale: 1 / parent.scale
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.undoing ? root.undoClicked() : root.updateClicked()
      // A double-click is one click: the undo or the update, then nothing.
      onDoubleClicked: {}
    }
  }
}
