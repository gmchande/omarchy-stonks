pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui
import "Tones.js" as Tones

// The list menu: All and each named list with its count, a check on the
// current one, then "New list…", which turns into a name field in place, and
// "Manage lists…".
// Value-in, signals out; the body switches and creates. One cursor, as on
// the rows: it opens on the current list, moving the pointer puts it on the
// row under it, the arrows or j k move it from there, Enter or 1–9 take one,
// and Escape backs out. It takes the rows' mark, the hover-cursor fill and
// the bar; a click takes the row clicked.
FocusScope {
  id: root

  property var choices: []
  property string current: ""
  property bool retro: false
  property color foreground: Color.foreground
  property color dim: Tones.dim(foreground, Color.background)
  property string fontFamily: Style.font.family
  property int maxHeight: 0
  // Opaque whatever the theme's popup alpha, so the rows never show through.
  property color background: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
  // Why the typed name was refused, said under the field, and brought into
  // view: while a name is typed the menu holds still.
  property string problem: ""
  onProblemChanged: if (problem !== "") Qt.callLater(showProblem)
  function showProblem() {
    var bottom = newRow.y + 2 * itemHeight
    if (bottom > scroll.contentY + scroll.height)
      scroll.contentY = Math.min(bottom - scroll.height, Math.max(0, scroll.contentHeight - scroll.height))
  }

  property int cursor: 0
  property bool naming: false
  // What is typed for a new list; "" unless naming.
  readonly property string typedName: naming ? nameField.text : ""

  readonly property int itemHeight: Style.space(26)
  readonly property int separatorHeight: Style.space(9)
  readonly property int newIndex: choices.length
  readonly property int manageIndex: choices.length + 1
  readonly property int contentHeight: choices.length * itemHeight + separatorHeight + itemHeight * 2
    + (problem !== "" ? itemHeight : 0) + Style.space(8)

  signal chosen(string name)
  signal createRequested(string name)
  signal manageRequested()
  signal dismissed()

  width: Style.space(236)
  height: maxHeight > 0 ? Math.min(contentHeight, maxHeight) : contentHeight

  // True while the menu is open on an open surface. Turned on, it starts on
  // the current list before its first frame and takes the keys a turn later
  // if it is still on; turned off, however it closes, the surface's closing
  // included, it gives the keys up, its name field's too, and keeps what it
  // shows for the close fade.
  property bool active: false
  // Off, it still shows, through the close fade, but takes no pointer or
  // key: nothing acts or takes focus from a view that is closing.
  enabled: active
  onActiveChanged: {
    if (active) {
      reset()
      pointer.rest()
      Qt.callLater(function() { if (root.active && !root.naming) root.forceActiveFocus() })
    } else {
      nameField.focus = false
      root.focus = false
      scroll.cancelFlick()
    }
  }

  // The menu's start: the cursor on the current list.
  function reset() {
    naming = false
    problem = ""
    nameField.text = ""
    nameField.focus = false
    cursor = 0
    for (var i = 0; i < choices.length; i++) if (choices[i].name === current) cursor = i
    scroll.contentY = 0
    showCursor()
  }

  function moveCursor(delta) {
    cursor = Math.max(0, Math.min(manageIndex, cursor + delta))
    showCursor()
  }

  // A key takes the list over from the wheel: its motion stops, so it
  // cannot carry the cursor on from where the key put it.
  function showCursor() {
    scroll.cancelFlick()
    var top = topOf(cursor)
    if (top < scroll.contentY) scroll.contentY = top
    else if (top + itemHeight > scroll.contentY + scroll.height)
      scroll.contentY = top + itemHeight - scroll.height
  }

  // Entry `index`'s top in the menu: the separator sits before "New list…".
  function topOf(index) {
    return index * itemHeight + (index < newIndex ? 0 : separatorHeight)
  }

  // The scrollbar or the wheel moved the menu off the cursor: it comes to
  // the nearest entry wholly in sight, or, in a menu too short for one, the
  // entry across its middle, so the next key acts on an entry that shows.
  function keepCursorInSight() {
    if (naming) return
    var top = scroll.contentY
    var bottom = top + scroll.height
    var whole = function(i) { return topOf(i) >= top - 0.5 && topOf(i) + itemHeight <= bottom + 0.5 }
    if (whole(cursor)) return
    var shown = []
    for (var i = 0; i <= manageIndex; i++) if (whole(i)) shown.push(i)
    if (shown.length > 0) cursor = topOf(cursor) < top ? shown[0] : shown[shown.length - 1]
    else for (i = 0; i <= manageIndex; i++) if (topOf(i) + itemHeight > (top + bottom) / 2) { cursor = i; break }
  }

  function take(index) {
    if (index === newIndex) startNaming()
    else if (index === manageIndex) manageRequested()
    else if (index >= 0 && index < choices.length) chosen(choices[index].name)
  }

  function startNaming() {
    cursor = newIndex
    naming = true
    problem = ""
    Qt.callLater(function() { if (root.active && root.naming) nameField.forceActiveFocus() })
  }

  // A new list's name kept from a close that could not make it, as it was
  // left: its typing, and why it was refused.
  function resumeNaming(text, reason) {
    startNaming()
    nameField.text = text
    problem = reason
  }

  // The cursor to the row the pointer moved onto, at (x, y) in the scene:
  // the separator and the note under the field are no row. While a name is
  // typed, the field keeps the cursor.
  function pointAt(x, y) {
    if (naming) return
    var seen = scroll.mapFromItem(null, x, y)
    if (seen.x < 0 || seen.x >= scroll.width || seen.y < 0 || seen.y >= scroll.height) return
    var at = column.mapFromItem(null, x, y)
    var item = column.childAt(at.x, at.y)
    if (!item) return
    if (item === newRow) cursor = newIndex
    else if (item === manageRow) cursor = manageIndex
    else if (item.objectName === "listChoice") cursor = Math.floor(at.y / itemHeight)
  }

  function stopNaming() {
    naming = false
    problem = ""
    nameField.text = ""
    // The field gives up its focus, or the scope hands the keys straight
    // back to it.
    nameField.focus = false
    if (root.active) root.forceActiveFocus()
  }

  Keys.onPressed: function(event) {
    // While naming, the field has the keys; what it lets past goes nowhere.
    if (root.naming) { event.accepted = true; return }
    if (event.key === Qt.Key_Escape) { root.dismissed(); event.accepted = true }
    else if (event.key === Qt.Key_Down || event.text === "j") { root.moveCursor(1); event.accepted = true }
    else if (event.key === Qt.Key_Up || event.text === "k") { root.moveCursor(-1); event.accepted = true }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.take(root.cursor); event.accepted = true }
    else if (event.text >= "1" && event.text <= "9") { root.take(Number(event.text) - 1); event.accepted = true }
    else if (event.text === "w") { root.dismissed(); event.accepted = true }
    // Every other key stays with the menu, so nothing behind it acts.
    else event.accepted = true
  }

  // The edge is drawn over the ground, not see-through: Qt draws a border in
  // place of the fill, so a translucent one showed the rows' cursor bar
  // under the menu's left edge.
  Rectangle {
    anchors.fill: parent
    radius: root.retro ? 0 : Style.cornerRadius
    color: root.background
    border.width: 1
    border.color: Qt.tint(root.background, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18))
  }

  RowPointer {
    id: pointer
    // A view showing through its surface's close moves no cursor.
    onMoved: function(x, y) { if (root.active) root.pointAt(x, y) }
  }

  Flickable {
    id: scroll
    objectName: "menuScroll"
    anchors.fill: parent
    anchors.margins: Style.space(4)
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    // While a name is typed the menu holds still, and its rows take no
    // click: a click anywhere but the field and ⏎ MAKE goes to the body,
    // which keeps the name as Enter does (`StonksBody`, off the menu).
    interactive: contentHeight > height && !root.naming
    // The wheel scrolling the rows under a still pointer moves the cursor
    // to the row now under it, and any scroll a hand makes, the scrollbar's
    // included, keeps it in sight; a key's scroll (showCursor) is no
    // movement.
    onContentYChanged: {
      if (!root.active || !(moving || menuBar.pressed)) return
      if (moving && pointer.hovered) root.pointAt(pointer.scenePosition.x, pointer.scenePosition.y)
      root.keepCursorInSight()
    }
    // While more of the menu sits out of sight, as in the window at its
    // smallest, the rows' scrollbar says so, at rest too, and the entries
    // stop short of its gutter.
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      id: menuBar
      // Drawn while there is more, not only while used.
      policy: scroll.interactive ? Controls.ScrollBar.AlwaysOn : Controls.ScrollBar.AlwaysOff
      visible: scroll.interactive
      // At least 24 px long, so a long view's thumb is there to see and grab.
      minimumSize: Math.min(1, Style.space(24) / Math.max(1, availableHeight))
    }

    Column {
      id: column
      width: scroll.width - (scroll.interactive ? Style.space(8) : 0)

      Repeater {
        model: root.choices

        Item {
          id: entry
          objectName: "listChoice"
          required property var modelData
          required property int index
          readonly property bool isCursor: index === root.cursor && !root.naming
          width: column.width
          height: root.itemHeight

          Rectangle {
            anchors.fill: parent
            radius: root.retro ? 0 : Style.cornerRadius
            color: entry.isCursor ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
            Behavior on color { ColorAnimation { duration: 60 } }
          }

          CursorBar {
            visible: entry.isCursor
            retro: root.retro
            foreground: root.foreground
          }

          Text {
            id: mark
            x: Style.space(8)
            width: Style.space(16)
            anchors.verticalCenter: parent.verticalCenter
            text: entry.modelData.name === root.current ? "✓" : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          Text {
            anchors.left: mark.right
            anchors.right: count.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: entry.modelData.label
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            id: count
            objectName: "listCount"
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String(entry.modelData.count)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            enabled: !root.naming
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.take(entry.index)
          }
        }
      }

      Item {
        width: column.width
        height: root.separatorHeight

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          x: Style.space(8)
          width: parent.width - Style.space(16)
          height: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        }
      }

      Item {
        id: newRow
        objectName: "newListRow"
        width: column.width
        height: root.itemHeight

        Rectangle {
          anchors.fill: parent
          visible: !root.naming
          radius: root.retro ? 0 : Style.cornerRadius
          color: root.cursor === root.newIndex ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
          Behavior on color { ColorAnimation { duration: 60 } }
        }

        CursorBar {
          visible: root.cursor === root.newIndex && !root.naming
          retro: root.retro
          foreground: root.foreground
        }

        Text {
          visible: !root.naming
          x: Style.space(24)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "New list…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          anchors.fill: parent
          visible: !root.naming
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.startNaming()
        }

        TextField {
          id: nameField
          objectName: "listNameField"
          anchors.left: parent.left
          anchors.right: makeButton.left
          anchors.rightMargin: Style.space(10)
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          visible: root.naming
          verticalPadding: 0
          foreground: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          placeholderText: "List name"
          onTextChanged: root.problem = ""
          onAccepted: root.createRequested(text)
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.stopNaming(); event.accepted = true }
          }
        }

        // Enter, as a button.
        ListAction {
          id: makeButton
          objectName: "makeList"
          view: root
          visible: root.naming
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "MAKE"
          enterTakes: true
          onActivated: root.createRequested(nameField.text)
        }
      }

      Text {
        visible: root.problem !== ""
        width: column.width
        height: root.itemHeight
        leftPadding: Style.space(24)
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        text: root.problem
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Item {
        id: manageRow
        objectName: "manageListsRow"
        width: column.width
        height: root.itemHeight
        readonly property bool isCursor: root.cursor === root.manageIndex && !root.naming

        Rectangle {
          anchors.fill: parent
          radius: root.retro ? 0 : Style.cornerRadius
          color: manageRow.isCursor ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
          Behavior on color { ColorAnimation { duration: 60 } }
        }

        CursorBar {
          visible: manageRow.isCursor
          retro: root.retro
          foreground: root.foreground
        }

        Text {
          x: Style.space(24)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Manage lists…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          anchors.fill: parent
          enabled: !root.naming
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.manageRequested()
        }
      }
    }
  }
}
