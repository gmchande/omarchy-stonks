pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import "Motion.js" as Motion
import "Rows.js" as Rows

// A symbol's lists, in the rows' place: a tick box for each list, All
// first, and New list…, which makes a list holding the symbol.
OverRows {
  id: root

  property var choices: []
  property string symbol: ""
  property string symbolName: ""
  property Look look
  // Said in the title's place for a moment: why a tick did nothing.
  property string note: ""

  property int cursor: 0
  property bool naming: false
  // Why the typed name can't be made, said under it.
  property string problem: ""
  readonly property int newIndex: choices.length

  readonly property int itemHeight: Style.space(30)
  function rowSize() { return { pitch: itemHeight, height: itemHeight } }
  // The rows' scrollbar gutter and text inset, so these words line up with
  // the rows underneath.
  property int gutter: 0
  readonly property int inset: Style.space(10)
  readonly property int contentHeight: itemHeight + (choices.length + 1 + (problem !== "" ? 1 : 0)) * itemHeight

  signal toggled(string name, bool member)
  signal createRequested(string name)
  signal dismissed()

  // While a name is typed, the field keeps the keys.
  keysTo: naming ? null : root

  function member(index) {
    return !!choices[index] && choices[index].symbols.indexOf(symbol) >= 0
  }

  onOpened: {
    reset()
    pointer.rest()
    opening.restart()
  }
  onClosed: {
    newRow.release()
    scroll.cancelFlick()
  }

  function reset() {
    stopNaming()
    cursor = choices.length > 1 ? 1 : newIndex
    scroll.contentY = 0
  }

  function pointAt(x, y) {
    if (naming) return
    var at = scroll.mapFromItem(null, x, y)
    // The scrollbar's gutter beside the rows is no row's.
    if (at.x < 0 || at.x >= column.width || at.y < 0 || at.y >= scroll.height) return
    var index = Math.floor((at.y + scroll.contentY) / itemHeight)
    if (index <= newIndex) cursor = index
  }

  // The view opens under the pointer that Ctrl-clicked to open it.
  Timer {
    id: opening
    interval: Application.styleHints.mouseDoubleClickInterval
  }

  function toggle(index) {
    if (index === newIndex) return startNaming()
    if (index < 0 || index >= choices.length) return
    cursor = index
    showCursor()
    toggled(choices[index].name, !member(index))
  }

  function startNaming() {
    cursor = newIndex
    showCursor()
    naming = true
    problem = ""
    newRow.edit(false)
  }

  // Back to the line, the field emptied. After a make, the cursor stays on
  // the place the new list takes, ticked.
  function stopNaming() {
    naming = false
    problem = ""
    newRow.text = ""
    newRow.release()
  }

  function moveCursor(delta) {
    cursor = Math.max(0, Math.min(newIndex, cursor + delta))
    showCursor()
  }

  function showCursor() {
    scroll.cancelFlick()
    scroll.contentY = Rows.topShowing(cursor, rowSize(), scroll.contentY, scroll.height)
  }

  // After a scroll by hand: the nearest list wholly in sight, or in a view
  // too short for one, the list across its middle.
  function keepCursorInSight() {
    cursor = Rows.cursorKeptInSight(cursor, newIndex + 1, rowSize(), scroll.contentY, scroll.height)
  }

  Keys.onPressed: function(event) {
    event.accepted = true
    // While naming, the field has the keys; what it lets past goes nowhere.
    if (root.naming) return
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

    ListAction {
      id: done
      look: root.look
      anchors.right: parent.right
      anchors.rightMargin: root.gutter + root.inset
      anchors.verticalCenter: parent.verticalCenter
      text: "DONE"
      onActivated: root.dismissed()
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

          Rectangle {
            anchors.fill: parent
            radius: root.look.retro ? 0 : Style.cornerRadius
            color: rowMouse.pressed ? Style.pressedFillFor(root.look.foreground, Commons.Color.accent)
              : entry.index === root.cursor ? Style.hoverFillFor(root.look.foreground, Commons.Color.accent) : "transparent"
            border.width: entry.index === root.cursor ? Style.hoverBorderWidth : 0
            border.color: Style.hoverBorderFor(root.look.foreground, Commons.Color.accent)
            Behavior on color { ColorAnimation { duration: Motion.duration(Style, 60) } }
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

      InlineNameRow {
        id: newRow
        width: column.width
        host: root
        look: root.look
        editing: root.naming
        problem: root.problem
        prompt: "New list…"
        isCursor: root.cursor === root.newIndex
        placeholder: "List name"
        lineHeight: root.itemHeight
        // The typed name starts where the lists' names do.
        textX: root.inset + Style.space(22)
        actionsRight: root.inset
        lineName: "symbolNewList"
        fieldName: "symbolListNameField"
        actionName: "symbolListMake"
        onTextChanged: root.problem = ""
        onTaken: root.startNaming()
        onSubmitted: function(name) { root.createRequested(name) }
        onCancelled: root.stopNaming()
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
