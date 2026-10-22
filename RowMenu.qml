pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import "KeyText.js" as KeyText

// A row's menu: the ways to remove it, each line saying which lists the
// removal reaches, such as "Remove from Growth" and "Remove from all 3
// lists". Value-in, signals out; the body says the lines and removes. It
// looks and moves as the list menu does, with one cursor: opened by a key,
// it starts on `startLine`; opened by the pointer, on no line, until the
// pointer moves onto one. The arrows or j k move it, Enter or a click takes
// a line, and Escape or Shift+X backs out.
FocusScope {
  id: root

  // Each line's words, top to bottom.
  property var lines: []
  // The line the cursor starts on as the menu opens, -1 for none.
  property int startLine: -1
  property int cursor: -1
  property bool retro: false
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property color background: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g, Commons.Color.popups.background.b, 1)
  // The most it may be across; a longer line ends in an ellipsis.
  property int maxWidth: 0

  readonly property int itemHeight: Style.space(26)
  readonly property int inset: Style.space(4)
  readonly property int padding: Style.space(16)

  signal taken(int index)
  signal dismissed()

  // Read, so a new font measures again.
  width: { var font = metrics.font; return Math.min(maxWidth, Math.ceil(lines.reduce(function(widest, line) { return Math.max(widest, metrics.advanceWidth(line)) }, Style.space(120)))
    + padding * 2 + inset * 2) }
  height: lines.length * itemHeight + inset * 2
  FontMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  // True while the menu is open on an open surface. Turned on, it starts
  // on its line and takes the keys a turn later if it is still on; turned
  // off, however it closes, the surface's closing included, it gives them
  // up and keeps what it shows for the close fade.
  property bool active: false
  // Off, it still shows, through the close fade, but takes no pointer or
  // key.
  enabled: active
  onActiveChanged: {
    if (active) {
      cursor = startLine
      pointer.rest()
      Qt.callLater(function() { if (root.active) root.forceActiveFocus() })
    } else root.focus = false
  }
  onStartLineChanged: if (active) cursor = startLine

  function moveCursor(delta) {
    cursor = cursor < 0 ? (delta > 0 ? 0 : lines.length - 1) : Math.max(0, Math.min(lines.length - 1, cursor + delta))
  }

  Keys.onPressed: function(event) {
    // A letter by its key and Shift: Caps Lock sends "J" for j.
    var t = KeyText.typed(event)
    if (event.key === Qt.Key_Escape || t === "X") root.dismissed()
    else if (event.key === Qt.Key_Down || t === "j") root.moveCursor(1)
    else if (event.key === Qt.Key_Up || t === "k") root.moveCursor(-1)
    else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.cursor >= 0) root.taken(root.cursor)
    // Every other key stays with the menu, so nothing behind it acts.
    event.accepted = true
  }

  // The edge is drawn over the ground, as the list menu's is.
  Rectangle {
    anchors.fill: parent
    radius: root.retro ? 0 : Style.cornerRadius
    color: root.background
    border.width: 1
    border.color: Qt.tint(root.background, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18))
  }

  // A view showing through its surface's close moves no cursor.
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

      Item {
        id: line
        objectName: "rowMenuLine"
        required property string modelData
        required property int index
        readonly property bool isCursor: index === root.cursor
        width: column.width
        height: root.itemHeight

        Rectangle {
          anchors.fill: parent
          radius: root.retro ? 0 : Style.cornerRadius
          color: line.isCursor ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"
          Behavior on color { ColorAnimation { duration: 60 } }
        }

        CursorBar {
          visible: line.isCursor
          retro: root.retro
          foreground: root.foreground
        }

        Text {
          x: root.padding
          width: parent.width - root.padding * 2
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: line.modelData
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.taken(line.index)
        }
      }
    }
  }
}
