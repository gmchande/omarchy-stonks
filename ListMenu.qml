pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import "KeyText.js" as KeyText
import "Motion.js" as Motion
import "Rows.js" as Rows

// The list menu: All and each named list, then "New list…" and "Manage
// lists…", pinned under the lists.
FocusScope {
  id: root

  property var choices: []
  property string current: ""
  property Look look
  property int maxHeight: 0
  // Opaque whatever the theme's panel alpha.
  property color background: Util.alpha(Commons.Color.popups.background, 1)
  property string problem: ""

  property int cursor: 0
  property bool naming: false
  readonly property string typedName: naming ? nameField.text : ""

  readonly property int itemHeight: Style.space(26)
  function rowSize() { return { pitch: itemHeight, height: itemHeight } }
  readonly property int separatorHeight: Style.space(9)
  readonly property int inset: Style.space(4)
  readonly property int newIndex: choices.length
  readonly property int manageIndex: choices.length + 1
  readonly property int pinnedHeight: separatorHeight + itemHeight * 2 + (problem !== "" ? itemHeight : 0)
  readonly property int contentHeight: choices.length * itemHeight + pinnedHeight + inset * 2
  readonly property int rowsShown: maxHeight > 0
    ? Math.max(1, Math.min(choices.length, Math.floor((maxHeight - pinnedHeight - inset * 2) / itemHeight)))
    : choices.length

  readonly property int leastHeight: itemHeight + pinnedHeight + inset * 2
  signal chosen(string name)
  signal createRequested(string name)
  signal manageRequested()
  signal dismissed()

  width: Style.space(236)
  height: rowsShown * itemHeight + pinnedHeight + inset * 2

  property bool active: false
  // Shown through the close fade, but inert.
  enabled: active
  // Turned on, it takes the keys a turn later only if still on; turned
  // off, however it closes, it gives them up, its name field's too.
  onActiveChanged: {
    if (active) {
      reset()
      pointer.rest()
      Qt.callLater(function() { if (root.active && !root.naming) root.forceActiveFocus() })
    } else {
      nameField.focus = false
      root.focus = false
      scroll.cancelFlick()
      settle.stop()
    }
  }

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

  // A key stops the wheel's motion, so it can't carry the cursor on from
  // where the key put it.
  function showCursor() {
    scroll.cancelFlick()
    var end = Math.max(0, scroll.contentHeight - scroll.height)
    var landed = settle.running ? settle.to : Math.min(end, Math.round(scroll.contentY / itemHeight) * itemHeight)
    settle.stop()
    scroll.contentY = landed
    if (cursor >= newIndex) return
    scroll.contentY = Rows.topShowing(cursor, rowSize(), scroll.contentY, scroll.height)
  }

  // A scroll by hand comes to rest on a row's edge, so no list shows cut.
  function settleOnRow() {
    var end = Math.max(0, scroll.contentHeight - scroll.height)
    var target = Math.min(end, Math.round(scroll.contentY / itemHeight) * itemHeight)
    if (target === scroll.contentY) return
    settle.to = target
    settle.restart()
  }

  NumberAnimation {
    id: settle
    target: scroll
    property: "contentY"
    duration: Motion.duration(Style, 160)
    easing.type: Easing.Bezier
    easing.bezierCurve: Motion.curve(Style)
    // Settled under a still pointer, the cursor takes the row now under it.
    onFinished: if (root.active && pointer.hovered) root.pointAt(pointer.scenePosition.x, pointer.scenePosition.y)
  }

  // After a scroll by hand: the nearest list wholly in sight, else the list
  // across the middle.
  function keepCursorInSight() {
    if (naming || cursor >= newIndex) return
    cursor = Rows.cursorKeptInSight(cursor, newIndex, rowSize(), scroll.contentY, scroll.height)
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

  // Back after a close that couldn't make the new list.
  function resumeNaming(text, reason) {
    startNaming()
    nameField.text = text
    problem = reason
  }

  // While a name is typed, the field keeps the cursor.
  function pointAt(x, y) {
    if (naming) return
    var pin = pinned.mapFromItem(null, x, y)
    var pinItem = pinned.childAt(pin.x, pin.y)
    if (pinItem === newRow) { cursor = newIndex; return }
    if (pinItem === manageRow) { cursor = manageIndex; return }
    var seen = scroll.mapFromItem(null, x, y)
    if (seen.x < 0 || seen.x >= scroll.width || seen.y < 0 || seen.y >= scroll.height) return
    var at = column.mapFromItem(null, x, y)
    var item = column.childAt(at.x, at.y)
    if (item && item.objectName === "listChoice") cursor = Math.floor(at.y / itemHeight)
  }

  function stopNaming() {
    naming = false
    problem = ""
    nameField.text = ""
    // The field drops its focus first, or the scope hands it straight back.
    nameField.focus = false
    if (root.active) root.forceActiveFocus()
  }

  Keys.onPressed: function(event) {
    // While naming, the field has the keys; what it lets past goes nowhere.
    if (root.naming) { event.accepted = true; return }
    // A letter by its key and Shift: Caps Lock sends "W" for w.
    var t = KeyText.typed(event)
    if (event.key === Qt.Key_Escape) { root.dismissed(); event.accepted = true }
    else if (event.key === Qt.Key_Down) { root.moveCursor(1); event.accepted = true }
    else if (event.key === Qt.Key_Up) { root.moveCursor(-1); event.accepted = true }
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.take(root.cursor); event.accepted = true }
    else if (t === "w") { root.dismissed(); event.accepted = true }
    // Nothing behind the menu acts.
    else event.accepted = true
  }

  // Qt draws a border in place of the fill, so a translucent edge would
  // show the rows' cursor bar under it.
  Rectangle {
    anchors.fill: parent
    radius: root.look.retro ? 0 : Style.cornerRadius
    color: root.background
    border.width: 1
    border.color: Qt.tint(root.background, Util.alpha(root.look.foreground, 0.18))
  }

  RowPointer {
    id: pointer
    // Through the close fade, the pointer moves no cursor.
    onMoved: function(x, y) { if (root.active) root.pointAt(x, y) }
  }

  Flickable {
    id: scroll
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: root.inset
    height: root.rowsShown * root.itemHeight
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    // A Flickable that scrolls takes presses itself. Held still while
    // naming, so a click on it reaches the body, which keeps the name.
    interactive: contentHeight > height && !root.naming
    // `moving` stays false for a key's scroll.
    onContentYChanged: {
      if (!root.active || !(moving || menuBar.pressed)) return
      if (moving && pointer.hovered) root.pointAt(pointer.scenePosition.x, pointer.scenePosition.y)
      root.keepCursorInSight()
    }
    onMovementEnded: root.settleOnRow()
    Controls.ScrollBar.vertical: ViewScrollBar {
      id: menuBar
      scrolls: scroll.interactive
      onPressedChanged: if (!pressed) root.settleOnRow()
    }

    Column {
      id: column
      width: scroll.width - (scroll.interactive ? Style.space(8) : 0)

      Repeater {
        // By count: a change to the lists rebinds the rows, not rebuilds them.
        model: root.choices.length

        // A plain Item at the root: when a list goes, the Repeater switches
        // off the bindings of a root that is the delegate's own, and no
        // others, so nothing here reads a list that has gone.
        Item {
          id: entry
          objectName: "listChoice"
          required property int index
          readonly property var choice: root.choices[index]
          width: column.width
          height: root.itemHeight

          MenuLine {
            anchors.fill: parent
            look: root.look
            isCursor: entry.index === root.cursor && !root.naming
            takes: !root.naming
            onTaken: root.take(entry.index)

            Text {
              id: mark
              x: Style.space(8)
              width: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              text: entry.choice.name === root.current ? "✓" : ""
              color: root.look.foreground
              font.family: root.look.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Text {
              anchors.left: mark.right
              anchors.right: count.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: entry.choice.label
              color: root.look.foreground
              font.family: root.look.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              id: count
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(entry.choice.count)
              color: root.look.dim
              font.family: root.look.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }
      }
    }
  }

  Column {
    id: pinned
    anchors.top: scroll.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: root.inset
    anchors.rightMargin: root.inset

    Item {
      width: pinned.width
      height: root.separatorHeight

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(8)
        width: parent.width - Style.space(16)
        height: 1
        color: Util.alpha(root.look.foreground, 0.12)
      }
    }

    Item {
      id: newRow
      width: pinned.width
      height: root.itemHeight

      // The line gives way whole to the field while a name is typed.
      MenuLine {
        anchors.fill: parent
        visible: !root.naming
        look: root.look
        isCursor: root.cursor === root.newIndex
        onTaken: root.startNaming()

        Text {
          x: Style.space(24)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "New list…"
          color: root.look.dim
          font.family: root.look.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Field {
        id: nameField
        objectName: "listNameField"
        anchors.left: parent.left
        anchors.right: makeButton.left
        anchors.rightMargin: Style.space(10)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: root.naming
        verticalPadding: 0
        // The typed name starts where "New list…" and the lists' names do.
        leftPadding: Style.space(24)
        retro: root.look.retro
        foreground: root.look.foreground
        dim: root.look.dim
        font.family: root.look.fontFamily
        font.pixelSize: Style.font.bodySmall
        placeholderText: "List name"
        onTextChanged: root.problem = ""
        onAccepted: root.createRequested(text)
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.stopNaming(); event.accepted = true }
        }
      }

      ListAction {
        id: makeButton
        look: root.look
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
      width: pinned.width
      height: root.itemHeight
      leftPadding: Style.space(24)
      verticalAlignment: Text.AlignVCenter
      textFormat: Text.PlainText
      text: root.problem
      color: root.look.foreground
      font.family: root.look.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    MenuLine {
      id: manageRow
      width: pinned.width
      height: root.itemHeight
      look: root.look
      isCursor: root.cursor === root.manageIndex && !root.naming
      takes: !root.naming
      onTaken: root.manageRequested()

      Text {
        x: Style.space(24)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Manage lists…"
        color: root.look.dim
        font.family: root.look.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
