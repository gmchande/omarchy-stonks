pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui
import "Rows.js" as Rows

// Manage lists, in the rows' place: rename, reorder, and delete the named
// lists. All comes first and can't change.
OverRows {
  id: root

  property var choices: []
  property Look look
  // Why a typed name was refused, said under the field and brought into
  // view; as its line goes, the list rests within its rows at once.
  property string problem: ""
  onProblemChanged: if (problem !== "") Qt.callLater(showProblem); else settle()
  // The column lays out a turn after the problem's line appears.
  function showProblem() {
    var bottom = (cursor + 2) * itemHeight
    if (bottom > scroll.contentY + scroll.height)
      scroll.contentY = Math.min(bottom - scroll.height, Math.max(0, rowsHeight - scroll.height))
  }
  // `rowsHeight` may not have updated yet.
  function settle() {
    scroll.contentY = Math.min(scroll.contentY, Math.max(0, choices.length * itemHeight - scroll.height))
  }

  property int cursor: 1
  property bool renaming: false
  property bool confirming: false
  // By name: the other surface can reorder, rename or delete it meanwhile.
  property string pendingName: ""
  onChoicesChanged: {
    if (!renaming && !confirming) return
    var at = choices.map(function(c) { return c.name }).indexOf(pendingName)
    if (at < 0) { stopEditing(); return }
    cursor = at
    showCursor()
    if (problem !== "") Qt.callLater(showProblem)
  }
  readonly property string typedName: renaming ? nameField.text : ""

  readonly property int itemHeight: Style.space(30)
  function rowSize() { return { pitch: itemHeight, height: itemHeight } }
  // The rows' scrollbar gutter and text inset, so these words line up with
  // the rows underneath.
  property int gutter: 0
  readonly property int inset: Style.space(10)
  readonly property int rowsHeight: choices.length * itemHeight + (problem !== "" ? itemHeight : 0)
  readonly property int contentHeight: itemHeight + rowsHeight

  signal renameRequested(string name, string newName)
  signal moveRequested(string name, int delta)
  signal deleteRequested(string name)
  signal dismissed()

  keysTo: renaming ? null : root
  onOpened: {
    reset()
    pointer.rest()
  }
  // Closed, it gives up its rename field's keys too.
  onClosed: {
    nameField.focus = false
    scroll.cancelFlick()
  }

  function reset() {
    renaming = false
    confirming = false
    problem = ""
    nameField.focus = false
    cursor = choices.length > 1 ? 1 : 0
    scroll.contentY = 0
  }

  function moveCursor(delta) {
    confirming = false
    cursor = Math.max(0, Math.min(choices.length - 1, cursor + delta))
    showCursor()
  }

  function pointAt(x, y) {
    if (renaming || confirming) return
    var at = scroll.mapFromItem(null, x, y)
    if (at.x < 0 || at.x >= scroll.width || at.y < 0 || at.y >= scroll.height) return
    var index = Math.floor((at.y + scroll.contentY) / itemHeight)
    if (index < choices.length) cursor = index
  }

  function showCursor() {
    scroll.cancelFlick()
    scroll.contentY = Rows.topShowing(cursor, rowSize(), scroll.contentY, scroll.height)
  }

  // After a scroll by hand: the nearest list wholly in sight, or in a view
  // too short for one, the list across its middle. A rename or a delete's
  // question keeps its row.
  function keepCursorInSight() {
    if (renaming || confirming) return
    cursor = Rows.cursorKeptInSight(cursor, choices.length, rowSize(), scroll.contentY, scroll.height)
  }

  function startRenaming(index) {
    if (!choices[index] || choices[index].name === "") return
    cursor = index
    pendingName = choices[index].name
    confirming = false
    problem = ""
    nameField.text = choices[index].name
    renaming = true
    Qt.callLater(function() {
      if (!root.active || !root.renaming) return
      nameField.forceActiveFocus()
      nameField.selectAll()
    })
  }

  // Back after a close that couldn't save the rename.
  function resumeRename(name, text, reason) {
    var at = choices.map(function(c) { return c.name }).indexOf(name)
    if (at < 1) return
    startRenaming(at)
    nameField.text = text
    problem = reason
  }

  // The field drops its focus first, or the scope hands it straight back.
  function stopEditing() {
    renaming = false
    confirming = false
    problem = ""
    nameField.focus = false
    if (root.active) root.forceActiveFocus()
  }

  function saveName() {
    renameRequested(pendingName, nameField.text)
  }

  // An emptied field keeps the old name.
  function keepName() {
    if (nameField.text.trim() === "") stopEditing()
    else saveName()
  }

  function move(index, delta) {
    var choice = choices[index]
    var to = index + delta
    if (!choice || choice.name === "" || to < 1 || to >= choices.length) return
    confirming = false
    cursor = to
    moveRequested(choice.name, delta)
    showCursor()
  }

  function askDelete(index) {
    if (!choices[index] || choices[index].name === "") return
    cursor = index
    pendingName = choices[index].name
    confirming = true
  }

  // The question's DELETE opens under the DELETE clicked to ask.
  Timer {
    id: justAsked
    interval: Application.styleHints.mouseDoubleClickInterval
  }

  // Enter always answers, inside the double-click interval too.
  function confirmDelete() {
    if (!confirming) return
    var name = pendingName
    confirming = false
    deleteRequested(name)
    cursor = Math.min(cursor, choices.length - 1)
  }

  Keys.onPressed: function(event) {
    // While renaming, the field has the keys; what it lets past goes nowhere.
    event.accepted = true
    if (root.renaming) return
    var moving = (event.modifiers & ~Qt.KeypadModifier) === Qt.ControlModifier
    if (event.key === Qt.Key_Escape) { if (root.confirming) root.confirming = false; else root.dismissed() }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.confirming) root.confirmDelete()
      else root.startRenaming(root.cursor)
    }
    else if (moving && event.key === Qt.Key_Down) root.move(root.cursor, 1)
    else if (moving && event.key === Qt.Key_Up) root.move(root.cursor, -1)
    else if (event.key === Qt.Key_Down) root.moveCursor(1)
    else if (event.key === Qt.Key_Up) root.moveCursor(-1)
    else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) root.askDelete(root.cursor)
  }

  MouseArea {
    anchors.fill: parent
    visible: root.renaming
    onClicked: root.keepName()
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
      x: root.inset
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "MANAGE LISTS"
      color: root.look.dim
      font.family: root.look.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
    }

    ListAction {
      look: root.look
      objectName: "manageDone"
      anchors.right: parent.right
      anchors.rightMargin: root.gutter + root.inset
      anchors.verticalCenter: parent.verticalCenter
      text: "DONE"
      onActivated: {
        if (root.renaming) root.keepName()
        if (!root.renaming) root.dismissed()
      }
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
    // A Flickable that scrolls takes presses itself. Held still while
    // renaming, so a click on it reaches `renameAway`.
    interactive: contentHeight > height && !root.renaming
    // `moving` stays false for a key's scroll.
    onContentYChanged: {
      if (!root.active || !(moving || manageBar.pressed)) return
      if (moving && pointer.hovered) root.pointAt(pointer.scenePosition.x, pointer.scenePosition.y)
      root.keepCursorInSight()
    }
    Controls.ScrollBar.vertical: ViewScrollBar { id: manageBar; scrolls: scroll.interactive }

    Column {
      id: column
      width: scroll.width - root.gutter

      Repeater {
        // By count: a change to the lists rebinds the rows, not rebuilds them.
        model: root.choices.length

        Item {
          id: entry
          objectName: "manageRow"
          required property int index
          readonly property var choice: root.choices[index]
          readonly property bool named: choice.name !== ""
          readonly property bool isCursor: index === root.cursor
          readonly property bool editing: isCursor && root.renaming
          readonly property bool asking: isCursor && root.confirming
          readonly property bool showsActions: named && !editing && !asking && isCursor
          width: column.width
          height: root.itemHeight * (editing && root.problem !== "" ? 2 : 1)

          CursorSurface {
            width: parent.width
            height: root.itemHeight
            hasCursor: entry.isCursor
            foreground: root.look.foreground
            radius: root.look.retro ? 0 : Style.cornerRadius
          }

          Text {
            visible: !entry.editing && !entry.asking
            x: root.inset
            width: (entry.showsActions ? actions.x : count.x) - x - Style.space(12)
            height: root.itemHeight
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: entry.choice.label
            color: entry.named ? root.look.foreground : root.look.dim
            font.family: root.look.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            visible: !entry.named && entry.isCursor
            anchors.right: count.left
            anchors.rightMargin: Style.space(16)
            height: root.itemHeight
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: "EVERY SYMBOL"
            color: root.look.dim
            font.family: root.look.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
          }

          Row {
            id: actions
            visible: entry.showsActions
            anchors.right: count.left
            anchors.rightMargin: Style.space(16)
            height: root.itemHeight
            spacing: Style.space(14)

            // An arrow with nowhere to move its list can't act, and is faded.
            ListAction {
              look: root.look
              objectName: "moveUp"
              anchors.verticalCenter: parent.verticalCenter
              text: "↑"
              enabled: entry.index > 1
              opacity: entry.index > 1 ? 1 : 0.4
              onActivated: root.move(entry.index, -1)
            }
            ListAction {
              look: root.look
              objectName: "moveDown"
              anchors.verticalCenter: parent.verticalCenter
              text: "↓"
              enabled: entry.index < root.choices.length - 1
              opacity: entry.index < root.choices.length - 1 ? 1 : 0.4
              onActivated: root.move(entry.index, 1)
            }
            ListAction {
              look: root.look
              anchors.verticalCenter: parent.verticalCenter
              text: "RENAME"
              enterTakes: true
              onActivated: root.startRenaming(entry.index)
            }
            ListAction {
              look: root.look
              anchors.verticalCenter: parent.verticalCenter
              text: "DELETE"
              onActivated: {
                root.askDelete(entry.index)
                justAsked.restart()
              }
            }
          }

          Text {
            id: count
            visible: !entry.editing && !entry.asking
            anchors.right: parent.right
            anchors.rightMargin: root.inset
            height: root.itemHeight
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: String(entry.choice.count)
            color: root.look.dim
            font.family: root.look.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          // Delete asks in the row: Stonks has no dialogs.
          Text {
            visible: entry.asking
            x: root.inset
            width: confirm.x - x - Style.space(12)
            height: root.itemHeight
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: "Delete " + entry.choice.label + "? "
              + (entry.choice.count === 0 ? "It's empty."
                : entry.choice.count === 1 ? "Its symbol stays in All."
                : "Its " + entry.choice.count + " symbols stay in All.")
            color: root.look.foreground
            font.family: root.look.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Row {
            id: confirm
            visible: entry.asking
            anchors.right: parent.right
            anchors.rightMargin: root.inset
            height: root.itemHeight
            spacing: Style.space(14)

            ListAction {
              look: root.look
              anchors.verticalCenter: parent.verticalCenter
              text: "DELETE"
              enterTakes: true
              enabled: !justAsked.running
              onActivated: root.confirmDelete()
            }
            ListAction {
              look: root.look
              anchors.verticalCenter: parent.verticalCenter
              text: "CANCEL"
              onActivated: root.confirming = false
            }
          }

          Text {
            visible: entry.editing && root.problem !== ""
            y: root.itemHeight
            x: root.inset
            width: parent.width - x
            height: root.itemHeight
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: root.problem
            color: root.look.foreground
            font.family: root.look.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }

    // Clear of the cursor's bar, its words where the name's were.
    Field {
      id: nameField
      objectName: "renameField"
      visible: root.renaming
      x: Style.space(6)
      y: root.cursor * root.itemHeight
      width: renameChoices.x - x - Style.space(12)
      leftPadding: root.inset - x
      height: root.itemHeight
      verticalPadding: 0
      retro: root.look.retro
      foreground: root.look.foreground
      dim: root.look.dim
      font.family: root.look.fontFamily
      font.pixelSize: Style.font.bodySmall
      onTextChanged: root.problem = ""
      // Enter is taken here, not on accepted: the press would go on to the
      // view, which by then has the keys back and would rename again.
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.stopEditing(); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          event.accepted = true
          root.saveName()
        }
      }
    }

    Row {
      id: renameChoices
      visible: root.renaming
      anchors.right: parent.right
      anchors.rightMargin: root.gutter + root.inset
      y: root.cursor * root.itemHeight
      height: root.itemHeight
      spacing: Style.space(14)

      ListAction {
        look: root.look
        anchors.verticalCenter: parent.verticalCenter
        text: "SAVE"
        enterTakes: true
        onActivated: root.saveName()
      }
      ListAction {
        look: root.look
        anchors.verticalCenter: parent.verticalCenter
        text: "CANCEL"
        onActivated: root.stopEditing()
      }
    }
  }
}
