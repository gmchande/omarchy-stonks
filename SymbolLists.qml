pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import "Tones.js" as Tones

// A symbol's lists, in the rows' place: a tick box for each list, All first.
FocusScope {
  id: root

  property var choices: []
  property string symbol: ""
  property string symbolName: ""
  property bool retro: false
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  // Said in the title's place for a moment: why a tick did nothing.
  property string note: ""

  property int cursor: 0

  readonly property int itemHeight: Style.space(30)
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

  property bool active: false
  // Shown through the close fade, but takes no pointer or key.
  enabled: active
  // Turned on, it takes the keys a turn later only if still on; turned
  // off, however it closes, it gives them up.
  onActiveChanged: {
    if (active) {
      reset()
      pointer.rest()
      opening.restart()
      Qt.callLater(function() { if (root.active) root.forceActiveFocus() })
    } else {
      root.focus = false
      scroll.cancelFlick()
    }
  }

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
    var top = cursor * itemHeight
    if (top < scroll.contentY) scroll.contentY = top
    else if (top + itemHeight > scroll.contentY + scroll.height)
      scroll.contentY = top + itemHeight - scroll.height
  }

  // After a scroll by hand: the nearest list wholly in sight, or in a view
  // too short for one, the list across its middle.
  function keepCursorInSight() {
    if (cursor < 0) return
    var top = scroll.contentY
    var bottom = top + scroll.height
    var whole = function(i) { return i * itemHeight >= top - 0.5 && (i + 1) * itemHeight <= bottom + 0.5 }
    if (whole(cursor)) return
    var shown = []
    for (var i = 0; i < choices.length; i++) if (whole(i)) shown.push(i)
    if (shown.length > 0) cursor = cursor * itemHeight < top ? shown[0] : shown[shown.length - 1]
    else cursor = Math.max(0, Math.min(choices.length - 1, Math.floor((top + bottom) / 2 / itemHeight)))
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
      color: root.dim
      font.family: root.fontFamily
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
      color: root.foreground
      font.family: root.fontFamily
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
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
      elide: Text.ElideRight
    }

    Text {
      objectName: "symbolListsNote"
      visible: root.note !== ""
      x: root.inset
      anchors.right: done.left
      anchors.rightMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.note
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    ListAction {
      id: done
      objectName: "symbolListsDone"
      view: root
      anchors.right: parent.right
      anchors.rightMargin: root.gutter + root.inset
      anchors.verticalCenter: parent.verticalCenter
      text: "DONE"
      onActivated: root.dismissed()
    }
  }

  Flickable {
    id: scroll
    objectName: "symbolListsScroll"
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
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      id: listsBar
      policy: scroll.interactive ? Controls.ScrollBar.AlwaysOn : Controls.ScrollBar.AlwaysOff
      visible: scroll.interactive
      // At least 24 px long, so a long view's thumb is there to see and grab.
      minimumSize: Math.min(1, Style.space(24) / Math.max(1, availableHeight))
    }

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

          Rectangle {
            objectName: "rowFill"
            anchors.fill: parent
            radius: root.retro ? 0 : Style.cornerRadius
            color: rowMouse.pressed ? Style.pressedFillFor(root.foreground, Commons.Color.accent)
              : entry.index === root.cursor ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"
            Behavior on color { ColorAnimation { duration: 60 } }
          }

          CursorBar {
            visible: entry.index === root.cursor
            retro: root.retro
            foreground: root.foreground
          }

          Rectangle {
            id: box
            objectName: "tickBox"
            x: root.inset
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(12)
            height: width
            radius: root.retro ? 0 : Style.space(3)
            color: "transparent"
            border.width: 1
            border.color: entry.ticked ? root.foreground : root.dim

            Text {
              anchors.centerIn: parent
              visible: entry.ticked
              text: "✓"
              color: root.foreground
              font.family: root.fontFamily
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
            color: root.foreground
            font.family: root.fontFamily
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
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
          }

          Text {
            id: count
            objectName: "listCount"
            anchors.right: parent.right
            anchors.rightMargin: root.inset
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String(entry.choice.count)
            color: root.dim
            font.family: root.fontFamily
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
