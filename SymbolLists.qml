pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui
import "Rows.js" as Rows

// A symbol's lists, in the rows' place: a tick box for each list, All first.
OverRows {
  id: root

  property var choices: []
  property string symbol: ""
  property string symbolName: ""
  property Look look
  // Said in the title's place for a moment: why a tick did nothing.
  property string note: ""

  property int cursor: 0

  readonly property int itemHeight: Style.space(30)
  function rowSize() { return { pitch: itemHeight, height: itemHeight } }
  // The rows' scrollbar gutter and text inset, so these words line up with
  // the rows underneath.
  property int gutter: 0
  readonly property int inset: Style.space(10)
  readonly property int contentHeight: itemHeight + choices.length * itemHeight

  signal toggled(string name, bool member)
  signal dismissed()

  function member(index) {
    return !!choices[index] && choices[index].symbols.indexOf(symbol) >= 0
  }

  onOpened: {
    reset()
    pointer.rest()
    opening.restart()
  }
  onClosed: scroll.cancelFlick()

  function reset() {
    cursor = choices.length > 1 ? 1 : -1
    scroll.contentY = 0
  }

  function pointAt(x, y) {
    var at = scroll.mapFromItem(null, x, y)
    if (at.x < 0 || at.x >= scroll.width || at.y < 0 || at.y >= scroll.height) return
    var index = Math.floor((at.y + scroll.contentY) / itemHeight)
    if (index < choices.length) cursor = index
  }

  // The view opens under the pointer that Ctrl-clicked to open it.
  Timer {
    id: opening
    interval: Application.styleHints.mouseDoubleClickInterval
  }

  function toggle(index) {
    if (index < 0 || index >= choices.length) return
    cursor = index
    showCursor()
    toggled(choices[index].name, !member(index))
  }

  function moveCursor(delta) {
    cursor = Math.max(0, Math.min(choices.length - 1, cursor + delta))
    showCursor()
  }

  function showCursor() {
    scroll.cancelFlick()
    scroll.contentY = Rows.topShowing(cursor, rowSize(), scroll.contentY, scroll.height)
  }

  // After a scroll by hand: the nearest list wholly in sight, or in a view
  // too short for one, the list across its middle.
  function keepCursorInSight() {
    if (cursor < 0) return
    cursor = Rows.cursorKeptInSight(cursor, choices.length, rowSize(), scroll.contentY, scroll.height)
  }

  Keys.onPressed: function(event) {
    event.accepted = true
    if (event.key === Qt.Key_Escape) root.dismissed()
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.toggle(root.cursor)
    else if (event.key === Qt.Key_Down) root.moveCursor(1)
    else if (event.key === Qt.Key_Up) root.moveCursor(-1)
  }

  RowPointer {
    id: pointer
    // Through the close fade, the pointer moves no cursor.
    onMoved: function(x, y) { if (root.active) root.pointAt(x, y) }
  }

  Item {
    id: title
    width: parent.width
    height: root.itemHeight

    Text {
      id: lead
      visible: root.note === ""
      x: root.inset
      anchors.baseline: symbolText.baseline
      textFormat: Text.PlainText
      text: "LISTS WITH"
      color: root.look.dim
      font.family: root.look.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
    }

    Text {
      id: symbolText
      visible: root.note === ""
      anchors.left: lead.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.symbol
      color: root.look.foreground
      font.family: root.look.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Text {
      visible: root.note === ""
      anchors.left: symbolText.right
      anchors.leftMargin: Style.space(8)
      anchors.right: done.left
      anchors.rightMargin: Style.space(16)
      anchors.baseline: symbolText.baseline
      textFormat: Text.PlainText
      text: root.symbolName.toUpperCase()
      color: root.look.dim
      font.family: root.look.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
      elide: Text.ElideRight
    }

    Text {
      visible: root.note !== ""
      x: root.inset
      anchors.right: done.left
      anchors.rightMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.note
      color: root.look.foreground
      font.family: root.look.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Button {
      id: done
      anchors.right: parent.right
      anchors.rightMargin: root.gutter + root.inset
      anchors.verticalCenter: parent.verticalCenter
      bordered: true
      radius: root.look.retro ? 0 : Style.cornerRadius
      foreground: root.look.foreground
      fontFamily: root.look.fontFamily
      fontSize: Style.font.bodySmall
      text: "Done"
      onClicked: root.dismissed()
    }
  }

  Flickable {
    id: scroll
    anchors.top: title.bottom
    anchors.bottom: parent.bottom
    width: parent.width
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    // `moving` stays false for a key's scroll.
    onContentYChanged: {
      if (!root.active || !(moving || listsBar.pressed)) return
      if (moving && pointer.hovered) root.pointAt(pointer.scenePosition.x, pointer.scenePosition.y)
      root.keepCursorInSight()
    }
    Controls.ScrollBar.vertical: ViewScrollBar { id: listsBar; scrolls: scroll.interactive }

    Column {
      id: column
      width: scroll.width - root.gutter

      Repeater {
        // By count: a change to the lists rebinds the rows, not rebuilds them.
        model: root.choices.length

        Item {
          id: entry
          objectName: "symbolListRow"
          required property int index
          readonly property var choice: root.choices[index]
          readonly property bool ticked: choice.symbols.indexOf(root.symbol) >= 0
          width: column.width
          height: root.itemHeight

          CursorSurface {
            anchors.fill: parent
            hasCursor: entry.index === root.cursor
            foreground: root.look.foreground
            radius: root.look.retro ? 0 : Style.cornerRadius
          }

          Rectangle {
            id: box
            x: root.inset
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(12)
            height: width
            radius: root.look.retro ? 0 : Style.space(3)
            color: "transparent"
            border.width: 1
            border.color: entry.ticked ? root.look.foreground : root.look.dim

            Text {
              anchors.centerIn: parent
              visible: entry.ticked
              text: "✓"
              color: root.look.foreground
              font.family: root.look.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Text {
            anchors.left: box.right
            anchors.leftMargin: Style.space(10)
            anchors.right: (entry.choice.name === "" ? hint : count).left
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: entry.choice.label
            color: root.look.foreground
            font.family: root.look.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            id: hint
            visible: entry.choice.name === ""
            anchors.right: count.left
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "UNCHECK TO REMOVE IT EVERYWHERE"
            color: root.look.dim
            font.family: root.look.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
          }

          Text {
            id: count
            anchors.right: parent.right
            anchors.rightMargin: root.inset
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String(entry.choice.count)
            color: root.look.dim
            font.family: root.look.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle(entry.index)
          }
        }
      }
    }
  }

  // Takes the click after the Ctrl-click; with no hoverEnabled, hover passes.
  MouseArea {
    objectName: "openingShield"
    anchors.fill: parent
    visible: opening.running
    acceptedButtons: Qt.AllButtons
  }
}
