pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tones.js" as Tones
import "KeyText.js" as KeyText

// Manage lists, in the rows' place: rename, reorder, and delete the named
// lists. All is listed first and cannot be changed. Value-in, signals out;
// the body persists. Like the list menu it owns its keys while open: the
// arrows or j k move the cursor, Enter renames, J K move the list, x asks to
// delete and Enter confirms, Escape backs out one step. The buttons say only
// what they do; the one Enter takes is marked (`ListAction.enterTakes`).
// One cursor, as on the rows: moving the pointer puts it, with the rows'
// mark, on the row under it, which shows that row's buttons; a click on one
// takes it.
FocusScope {
  id: root

  property var choices: []
  property bool retro: false
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  // Why the typed name was refused, said under the field, and brought into
  // view: while a name is typed the list holds still. Its line gone, as you
  // type again or leave the field, the list rests within its rows at once.
  property string problem: ""
  onProblemChanged: if (problem !== "") Qt.callLater(showProblem); else settle()
  // The rows' height counts the problem's line at once; the column's lays
  // out a turn later.
  function showProblem() {
    var bottom = (cursor + 2) * itemHeight
    if (bottom > scroll.contentY + scroll.height)
      scroll.contentY = Math.min(bottom - scroll.height, Math.max(0, rowsHeight - scroll.height))
  }
  // Called as the problem's line goes: the rows without it, counted here,
  // since `rowsHeight` may not have heard yet.
  function settle() {
    scroll.contentY = Math.min(scroll.contentY, Math.max(0, choices.length * itemHeight - scroll.height))
  }

  property int cursor: 1
  property bool renaming: false
  property bool confirming: false
  // The list a rename or the delete question is about, by name, not by row:
  // the order can change on another surface meanwhile, and the cursor, the
  // field, and the question follow the list, into view. Gone from the
  // lists (deleted or renamed elsewhere), there is nothing left to act on.
  property string pendingName: ""
  onChoicesChanged: {
    if (!renaming && !confirming) return
    var at = choices.map(function(c) { return c.name }).indexOf(pendingName)
    if (at < 0) { stopEditing(); return }
    cursor = at
    showCursor()
    if (problem !== "") Qt.callLater(showProblem)
  }
  // What is typed for the rename; "" unless renaming.
  readonly property string typedName: renaming ? nameField.text : ""

  readonly property int itemHeight: Style.space(30)
  // The scrollbar's gutter at the right, as the list's rows keep it, and the
  // rows' words' inset from their fills, so this view's words line up with
  // the rows it covers.
  property int gutter: 0
  readonly property int inset: Style.space(10)
  readonly property int rowsHeight: choices.length * itemHeight + (problem !== "" ? itemHeight : 0)
  readonly property int contentHeight: itemHeight + rowsHeight
  readonly property var cursorChoice: choices[cursor] || null

  signal renameRequested(string name, string newName)
  signal moveRequested(string name, int delta)
  signal deleteRequested(string name)
  signal dismissed()

  // True while the view is open on an open surface. Turned on, it starts on
  // the first named list, or All when there is none, before its first frame
  // and takes the keys a turn later if it is still on; turned off, however
  // it closes, the surface's closing included, it gives the keys up, its
  // rename field's too, and keeps what it shows for the close fade.
  property bool active: false
  // Off, it still shows, through the close fade, but takes no pointer or
  // key: nothing acts or takes focus from a view that is closing.
  enabled: active
  onActiveChanged: {
    if (active) {
      reset()
      pointer.rest()
      Qt.callLater(function() { if (root.active && !root.renaming) root.forceActiveFocus() })
    } else {
      nameField.focus = false
      root.focus = false
      scroll.cancelFlick()
    }
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

  // The cursor to the row the pointer moved onto, at (x, y) in the scene;
  // the title is no row. A row renaming or asking keeps
  // it, so the question stays on its own list.
  function pointAt(x, y) {
    if (renaming || confirming) return
    var at = scroll.mapFromItem(null, x, y)
    if (at.x < 0 || at.x >= scroll.width || at.y < 0 || at.y >= scroll.height) return
    var index = Math.floor((at.y + scroll.contentY) / itemHeight)
    if (index < choices.length) cursor = index
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
  // list across its middle, so the next key acts on a list that shows. A
  // rename or a delete's question keeps its row.
  function keepCursorInSight() {
    if (renaming || confirming) return
    var top = scroll.contentY
    var bottom = top + scroll.height
    var whole = function(i) { return i * itemHeight >= top - 0.5 && (i + 1) * itemHeight <= bottom + 0.5 }
    if (whole(cursor)) return
    var shown = []
    for (var i = 0; i < choices.length; i++) if (whole(i)) shown.push(i)
    if (shown.length > 0) cursor = cursor * itemHeight < top ? shown[0] : shown[shown.length - 1]
    else cursor = Math.max(0, Math.min(choices.length - 1, Math.floor((top + bottom) / 2 / itemHeight)))
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

  // A rename kept from a close that could not save it, as it was left:
  // its list, its typing, and why it was refused.
  function resumeRename(name, text, reason) {
    var at = choices.map(function(c) { return c.name }).indexOf(name)
    if (at < 1) return
    startRenaming(at)
    nameField.text = text
    problem = reason
  }

  // The field gives up its focus, or the scope hands the keys straight back.
  function stopEditing() {
    renaming = false
    confirming = false
    problem = ""
    nameField.focus = false
    if (root.active) root.forceActiveFocus()
  }

  // Enter in the field, or its button: the list it was started on.
  function saveName() {
    renameRequested(pendingName, nameField.text)
  }

  // A click away from the field, or DONE, keeps what was typed, as Enter
  // does; an emptied field keeps the old name.
  // Escape alone throws the typing away. A name refused stays in the
  // field, saying why.
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

  // A double-click is one click: the question's DELETE comes up under the
  // DELETE clicked to ask, so within the double-click interval (`justAsked`)
  // it takes no press at all. Qt counts a double-click from its presses, so
  // a second press held past the interval is still that double-click's, and
  // its release must answer nothing. Enter always answers.
  Timer {
    id: justAsked
    interval: Application.styleHints.mouseDoubleClickInterval
  }

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
    // A letter by its key and Shift: Caps Lock sends "J" for j.
    var t = KeyText.typed(event)
    if (event.key === Qt.Key_Escape) { if (root.confirming) root.confirming = false; else root.dismissed() }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (root.confirming) root.confirmDelete()
      else root.startRenaming(root.cursor)
    }
    else if (event.key === Qt.Key_Down || t === "j") root.moveCursor(1)
    else if (event.key === Qt.Key_Up || t === "k") root.moveCursor(-1)
    else if (t === "J") root.move(root.cursor, 1)
    else if (t === "K") root.move(root.cursor, -1)
    else if (t === "x" || event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) root.askDelete(root.cursor)
    else if (t === "W") root.dismissed()
  }

  // Under everything else in the view: while a name is typed, a click that
  // lands on none of the view's buttons, or its field, keeps the name.
  MouseArea {
    objectName: "renameAway"
    anchors.fill: parent
    visible: root.renaming
    onClicked: root.keepName()
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
      x: root.inset
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "MANAGE LISTS"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1
    }

    // Over a rename DONE keeps the typed name first, and stays on a
    // refusal.
    ListAction {
      view: root
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
    objectName: "manageScroll"
    anchors.top: title.bottom
    anchors.bottom: parent.bottom
    width: parent.width
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    // A list that scrolls takes a press itself; while a name is typed it
    // holds still, so a click on it reaches the view's own (`renameAway`).
    interactive: contentHeight > height && !root.renaming
    // The wheel scrolling the rows under a still pointer moves the cursor
    // to the row now under it, and any scroll a hand makes, the scrollbar's
    // included, keeps it in sight; a key's scroll (showCursor) is no
    // movement.
    onContentYChanged: {
      if (!root.active || !(moving || manageBar.pressed)) return
      if (moving && pointer.hovered) root.pointAt(pointer.scenePosition.x, pointer.scenePosition.y)
      root.keepCursorInSight()
    }
    // While more lists sit out of sight, as in the window at its smallest,
    // the rows' scrollbar says so, at rest too, in the gutter the lists stop
    // short of.
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      id: manageBar
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
          objectName: "manageRow"
          required property var modelData
          required property int index
          readonly property bool named: modelData.name !== ""
          readonly property bool isCursor: index === root.cursor
          readonly property bool editing: isCursor && root.renaming
          readonly property bool asking: isCursor && root.confirming
          readonly property bool showsActions: named && !editing && !asking && isCursor
          width: column.width
          height: root.itemHeight * (editing && root.problem !== "" ? 2 : 1)

          Rectangle {
            width: parent.width
            height: root.itemHeight
            radius: root.retro ? 0 : Style.cornerRadius
            color: entry.isCursor ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"
            Behavior on color { ColorAnimation { duration: 60 } }
          }

          CursorBar {
            visible: entry.isCursor
            rowHeight: root.itemHeight
            retro: root.retro
            foreground: root.foreground
          }

          Text {
            visible: !entry.editing && !entry.asking
            x: root.inset
            width: (entry.showsActions ? actions.x : count.x) - x - Style.space(12)
            height: root.itemHeight
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: entry.modelData.label
            color: entry.named ? root.foreground : root.dim
            font.family: root.fontFamily
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
            text: "THE LIBRARY"
            color: root.dim
            font.family: root.fontFamily
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

            ListAction {
              view: root
              objectName: "moveUp"
              anchors.verticalCenter: parent.verticalCenter
              text: "↑"
              opacity: entry.index > 1 ? 1 : 0.4
              onActivated: root.move(entry.index, -1)
            }
            ListAction {
              view: root
              objectName: "moveDown"
              anchors.verticalCenter: parent.verticalCenter
              text: "↓"
              opacity: entry.index < root.choices.length - 1 ? 1 : 0.4
              onActivated: root.move(entry.index, 1)
            }
            ListAction {
              view: root
              objectName: "renameAction"
              anchors.verticalCenter: parent.verticalCenter
              text: "RENAME"
              enterTakes: true
              onActivated: root.startRenaming(entry.index)
            }
            ListAction {
              view: root
              objectName: "deleteAction"
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
            objectName: "listCount"
            visible: !entry.editing && !entry.asking
            anchors.right: parent.right
            anchors.rightMargin: root.inset
            height: root.itemHeight
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: String(entry.modelData.count)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          // Delete asks here, in the row: the viewer has no dialogs.
          Text {
            visible: entry.asking
            x: root.inset
            width: confirm.x - x - Style.space(12)
            height: root.itemHeight
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: "Delete " + entry.modelData.label + "? "
              + (entry.modelData.count === 0 ? "It is empty."
                : entry.modelData.count === 1 ? "Its symbol stays in All."
                : "Its " + entry.modelData.count + " symbols stay in All.")
            color: root.foreground
            font.family: root.fontFamily
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
              view: root
              objectName: "confirmDelete"
              anchors.verticalCenter: parent.verticalCenter
              text: "DELETE"
              enterTakes: true
              enabled: !justAsked.running
              onActivated: root.confirmDelete()
            }
            ListAction {
              view: root
              objectName: "cancelDelete"
              anchors.verticalCenter: parent.verticalCenter
              // The way out is always Cancel, as search's and the rename's
              // are; DELETE, which you asked for, keeps Enter.
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
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }

    // One field, laid over whichever row is being renamed, up to its choices:
    // clear of the cursor's bar, its words where the name's were.
    TextField {
      id: nameField
      objectName: "renameField"
      visible: root.renaming
      x: Style.space(6)
      y: root.cursor * root.itemHeight
      width: renameChoices.x - x - Style.space(12)
      leftPadding: root.inset - x
      height: root.itemHeight
      verticalPadding: 0
      foreground: root.foreground
      font.family: root.fontFamily
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

    // The rename's choices, at the renamed row's end.
    Row {
      id: renameChoices
      visible: root.renaming
      anchors.right: parent.right
      anchors.rightMargin: root.gutter + root.inset
      y: root.cursor * root.itemHeight
      height: root.itemHeight
      spacing: Style.space(14)

      ListAction {
        view: root
        objectName: "saveName"
        anchors.verticalCenter: parent.verticalCenter
        text: "SAVE"
        enterTakes: true
        onActivated: root.saveName()
      }
      ListAction {
        view: root
        objectName: "cancelRename"
        anchors.verticalCenter: parent.verticalCenter
        text: "CANCEL"
        onActivated: root.stopEditing()
      }
    }
  }
}
