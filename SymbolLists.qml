pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import "Tones.js" as Tones

// A symbol's lists, in the rows' place: one tick box per list, All first.
// Value-in, signals out; the body applies the membership rules. It owns its
// keys while open: the arrows or j k move the cursor, Enter or Space ticks
// the cursor's list, 1–9 tick that list, Escape or m closes. One cursor, as
// on the rows: moving the pointer puts it on the row under it, with the
// rows' mark, and a click ticks the row clicked.
FocusScope {
  id: root

  property var choices: []
  property string symbol: ""
  property string symbolName: ""
  property bool retro: false
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  // A short word in the title's place, for a moment: why a tick did nothing.
  property string note: ""

  property int cursor: 0

  readonly property int itemHeight: Style.space(30)
  // The scrollbar's gutter at the right, as the list's rows keep it, and the
  // rows' words' inset from their fills, so this view's words line up with
  // the rows it covers.
  property int gutter: 0
  readonly property int inset: Style.space(10)
  readonly property int contentHeight: itemHeight + choices.length * itemHeight

  signal toggled(string name, bool member)
  signal dismissed()

  function member(index) {
    return !!choices[index] && choices[index].symbols.indexOf(symbol) >= 0
  }

  // True while the checklist is open on an open surface. Turned on, it
  // starts before its first frame and takes the keys a turn later if it is
  // still on; turned off, however it closes, the surface's closing included,
  // it gives the keys up and keeps what it shows for the close fade.
  property bool active: false
  // Off, it still shows, through the close fade, but takes no pointer or
  // key: nothing acts or takes focus from a view that is closing.
  enabled: active
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

  // Opens on the first named list, and with none there is no cursor until an
  // arrow, a number, or the pointer picks a row: a stray Enter never unticks
  // All.
  function reset() {
    cursor = choices.length > 1 ? 1 : -1
    scroll.contentY = 0
  }

  // The cursor to the row the pointer moved onto, at (x, y) in the scene;
  // the title is no row.
  function pointAt(x, y) {
    var at = scroll.mapFromItem(null, x, y)
    if (at.x < 0 || at.x >= scroll.width || at.y < 0 || at.y >= scroll.height) return
    var index = Math.floor((at.y + scroll.contentY) / itemHeight)
    if (index < choices.length) cursor = index
  }

  // A double-click is one click (WatchlistRow): the view opens in the rows'
  // place, under the pointer, so the click that follows the Ctrl-click that
  // opened it, within the double-click interval, lands nowhere, and never
  // unticks the list under it.
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

  // A key takes the list over from the wheel: its motion stops, so it
  // cannot carry the cursor on from where the key put it.
  function showCursor() {
    scroll.cancelFlick()
    var top = cursor * itemHeight
    if (top < scroll.contentY) scroll.contentY = top
    else if (top + itemHeight > scroll.contentY + scroll.height)
      scroll.contentY = top + itemHeight - scroll.height
  }

  // The scrollbar or the wheel moved the lists off the cursor: it comes to
  // the nearest list wholly in sight, or, in a view too short for one, the
  // list across its middle, so the next key ticks a list that shows.
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
    if (event.key === Qt.Key_Escape || event.text === "m") root.dismissed()
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.toggle(root.cursor)
    else if (event.key === Qt.Key_Down || event.text === "j") root.moveCursor(1)
    else if (event.key === Qt.Key_Up || event.text === "k") root.moveCursor(-1)
    else if (event.text >= "1" && event.text <= "9") root.toggle(Number(event.text) - 1)
  }

  RowPointer {
    id: pointer
    // A view showing through its surface's close moves no cursor.
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
    // The wheel scrolling the rows under a still pointer moves the cursor
    // to the row now under it, and any scroll a hand makes, the scrollbar's
    // included, keeps it in sight; a key's scroll (showCursor) is no
    // movement.
    onContentYChanged: {
      if (!root.active || !(moving || listsBar.pressed)) return
      if (moving && pointer.hovered) root.pointAt(pointer.scenePosition.x, pointer.scenePosition.y)
      root.keepCursorInSight()
    }
    // While more lists sit out of sight, as in the window at its smallest,
    // the rows' scrollbar says so, at rest too, in the gutter the lists stop
    // short of.
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      id: listsBar
      // Drawn while there is more, not only while used.
      policy: scroll.interactive ? Controls.ScrollBar.AlwaysOn : Controls.ScrollBar.AlwaysOff
      visible: scroll.interactive
      // At least 24 px long, so a long view's thumb is there to see and grab.
      minimumSize: Math.min(1, Style.space(24) / Math.max(1, availableHeight))
    }

    Column {
      id: column
      width: scroll.width - root.gutter

      Repeater {
        model: root.choices

        Item {
          id: entry
          objectName: "symbolListRow"
          required property var modelData
          required property int index
          readonly property bool ticked: modelData.symbols.indexOf(root.symbol) >= 0
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
            anchors.right: (entry.modelData.name === "" ? hint : count).left
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: entry.modelData.label
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            id: hint
            visible: entry.modelData.name === ""
            anchors.right: count.left
            anchors.rightMargin: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "UNTICK TO REMOVE EVERYWHERE"
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
            text: String(entry.modelData.count)
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

  // Over the view while the opening click's double-click interval runs: it
  // takes that click, and the pointer's hover passes.
  MouseArea {
    objectName: "openingShield"
    anchors.fill: parent
    visible: opening.running
    acceptedButtons: Qt.AllButtons
  }
}
