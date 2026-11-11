pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons

// A row's removals, each line naming the lists it reaches ("Remove from all
// 3 lists"), and from a right-click, "Choose lists…". It looks and moves as
// the list menu does.
OverRows {
  id: root

  property var lines: []
  property int startLine: -1
  property int cursor: -1
  property Look look
  property color background: Util.alpha(Commons.Color.popups.background, 1)
  property int maxWidth: 0

  readonly property int itemHeight: Style.space(26)
  readonly property int inset: Style.space(4)
  readonly property int padding: Style.space(16)

  signal taken(int index)
  signal dismissed()

  // Reading `metrics.font` measures again at a new font.
  width: { var font = metrics.font; return Math.min(maxWidth, Math.ceil(lines.reduce(function(widest, line) { return Math.max(widest, metrics.advanceWidth(line)) }, Style.space(120)))
    + padding * 2 + inset * 2) }
  height: lines.length * itemHeight + inset * 2
  FontMetrics {
    id: metrics
    font.family: root.look.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  onOpened: {
    cursor = startLine
    pointer.rest()
  }
  onStartLineChanged: if (active) cursor = startLine

  function moveCursor(delta) {
    cursor = cursor < 0 ? (delta > 0 ? 0 : lines.length - 1) : Math.max(0, Math.min(lines.length - 1, cursor + delta))
  }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) root.dismissed()
    else if (event.key === Qt.Key_Down) root.moveCursor(1)
    else if (event.key === Qt.Key_Up) root.moveCursor(-1)
    else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.cursor >= 0) root.taken(root.cursor)
    // Every other key stays with the menu, so nothing behind it acts.
    event.accepted = true
  }

  Rectangle {
    anchors.fill: parent
    radius: root.look.retro ? 0 : Style.cornerRadius
    color: root.background
    border.width: 1
    border.color: Qt.tint(root.background, Util.alpha(root.look.foreground, 0.18))
  }

  RowPointer {
    id: pointer
    onMoved: function(x, y) {
      if (!root.active) return
      var at = column.mapFromItem(null, x, y)
      if (at.x >= 0 && at.x < column.width && at.y >= 0 && at.y < column.height) root.cursor = Math.floor(at.y / root.itemHeight)
    }
  }

  Column {
    id: column
    anchors.fill: parent
    anchors.margins: root.inset

    Repeater {
      model: root.lines

      // A plain Item at the root, as the list menu's lines have.
      Item {
        id: line
        objectName: "rowMenuLine"
        required property string modelData
        required property int index
        width: column.width
        height: root.itemHeight

        MenuLine {
          anchors.fill: parent
          look: root.look
          isCursor: line.index === root.cursor
          onTaken: root.taken(line.index)

          Text {
            x: root.padding
            width: parent.width - root.padding * 2
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: line.modelData
            color: root.look.foreground
            font.family: root.look.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
