pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import "Motion.js" as Motion
import "Rows.js" as Rows

// Manage lists, in the rows' place: rename, reorder, and delete the named
// lists. All comes first and can't change.
OverRows {
  id: root
  fades: true

  property var choices: []
  property Look look
  // Why a typed name was refused, said under the field and brought into
  // view; as its line goes, the list rests within its rows at once.
  property string problem: ""
  onProblemChanged: if (problem !== "") Qt.callLater(showProblem); else clampScroll()
  // The column lays out a turn after the problem's line appears.
  function showProblem() {
    var bottom = (cursor + 2) * itemHeight
    var base = scrollGlide.running ? scrollGlide.to : scroll.contentY
    if (bottom > base + scroll.height)
      glideScroll(Math.min(bottom - scroll.height, Math.max(0, rowsHeight - scroll.height)))
  }
  // `rowsHeight` may not have updated yet.
  function clampScroll() {
    scrollGlide.stop()
    scroll.contentY = Math.min(scroll.contentY, Math.max(0, choices.length * itemHeight - scroll.height))
  }

  function glideScroll(to) {
    scroll.cancelFlick()
    if (!active || !seen || still || Motion.duration(Style, 160) <= 0 || Math.abs(to - scroll.contentY) < 0.5) {
      scrollGlide.stop()
      scroll.contentY = to
      return
    }
    scrollGlide.to = to
    scrollGlide.restart()
  }
  NumberAnimation { id: scrollGlide; target: scroll; property: "contentY"; duration: Motion.duration(Style, 160); easing.type: Easing.OutCubic }

  property int cursor: 1
  property bool renaming: false
  property bool confirming: false
  // By name: the other surface can reorder, rename or delete it meanwhile.
  property string pendingName: ""
  // Deleted lists kept in `rowsModel` for 120 ms while their row folds shut.
  property var lastChoices: ({})
  property var foldChoices: ({})
  property var foldingNames: []
  signal foldsCleared()
  function recordChoices() {
    var map = {}
    for (var i = 0; i < choices.length; i++) map[choices[i].name] = choices[i]
    lastChoices = map
  }
  function finishFold(name) {
    if (foldingNames.indexOf(name) < 0) return
    var nextFold = Object.assign({}, foldChoices)
    delete nextFold[name]
    foldChoices = nextFold
    foldingNames = foldingNames.filter(function(n) { return n !== name })
    Rows.syncModel(rowsModel, "name", names.concat(foldingNames))
  }
  function endFolds() {
    if (foldingNames.length === 0) return
    foldingNames = []
    foldChoices = ({})
    foldsCleared()
    Rows.syncModel(rowsModel, "name", names)
  }
  onChoicesChanged: {
    var listed = choices.map(function(c) { return c.name })
    var nextFolding = foldingNames.filter(function(n) { return listed.indexOf(n) < 0 })
    var nextFoldChoices = {}
    for (var f = 0; f < nextFolding.length; f++) nextFoldChoices[nextFolding[f]] = foldChoices[nextFolding[f]]
    if (active && seen && !still && Motion.duration(Style, 120) > 0) {
      var prevNames = Object.keys(lastChoices)
      for (var p = 0; p < prevNames.length; p++) {
        var gone = prevNames[p]
        if (gone === "" || gone === reorder.lifted || listed.indexOf(gone) >= 0 || nextFolding.indexOf(gone) >= 0) continue
        nextFolding.push(gone)
        nextFoldChoices[gone] = lastChoices[gone]
      }
    }
    foldChoices = nextFoldChoices
    foldingNames = nextFolding
    Rows.syncModel(rowsModel, "name", listed.concat(foldingNames))
    recordChoices()
    if (!renaming && !confirming) return
    var at = listed.indexOf(pendingName)
    if (at < 0) { stopEditing(); return }
    cursor = at
    showCursor()
    if (problem !== "") Qt.callLater(showProblem)
  }
  readonly property string typedName: renaming ? newName.text : ""

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
  // Closed, it gives up its rename field's keys too, and a lifted list
  // drops where it was.
  onClosed: {
    newName.release()
    scrollGlide.stop()
    scroll.cancelFlick()
    reorder.cancel()
    endFolds()
  }
  onSettled: {
    scrollGlide.stop()
    endFolds()
    clampScroll()
  }
  onStillChanged: if (still && scrollGlide.running) scrollGlide.pause()
  onSeenChanged: if (!seen) Qt.callLater(function() { if (!root.seen && !root.still) { scrollGlide.stop(); root.endFolds() } })
  Connections {
    target: Style
    ignoreUnknownSignals: true
    function onReduceMotionChanged() { if (Style.reduceMotion) { scrollGlide.stop(); root.endFolds() } }
  }

  function reset() {
    renaming = false
    confirming = false
    problem = ""
    cursor = choices.length > 1 ? 1 : 0
    scrollGlide.stop()
    endFolds()
    scroll.contentY = 0
  }

  function moveCursor(delta) {
    confirming = false
    cursor = Math.max(0, Math.min(choices.length - 1, cursor + delta))
    showCursor()
  }

  // A page key's step: the lists wholly in sight, less one, so the list it
  // leaves stays in sight.
  function pageRows() {
    return Math.max(1, Math.floor(scroll.height / itemHeight) - 1)
  }

  function pointAt(x, y) {
    if (renaming || confirming || reorder.lifted !== "") return
    var at = scroll.mapFromItem(null, x, y)
    // The scrollbar's gutter beside the rows is no row's.
    if (at.x < 0 || at.x >= column.width || at.y < 0 || at.y >= scroll.height) return
    var index = Math.floor((at.y + scroll.contentY) / itemHeight)
    if (index < choices.length) cursor = index
  }

  function showCursor() {
    scroll.cancelFlick()
    var base = scrollGlide.running ? scrollGlide.to : scroll.contentY
    glideScroll(Rows.topShowing(cursor, rowSize(), base, scroll.height))
  }

  // After a scroll by hand: the nearest list wholly in sight, or in a view
  // too short for one, the list across its middle. A rename or a delete's
  // question keeps its row, and a lifted list the cursor.
  function keepCursorInSight() {
    if (renaming || confirming || reorder.lifted !== "") return
    cursor = Rows.cursorKeptInSight(cursor, choices.length, rowSize(), scroll.contentY, scroll.height)
  }

  function startRenaming(index) {
    if (!choices[index] || choices[index].name === "") return
    cursor = index
    pendingName = choices[index].name
    confirming = false
    problem = ""
    newName.text = choices[index].name
    renaming = true
    newName.edit(true)
  }

  // Back after a close that couldn't save the rename.
  function resumeRename(name, text, reason) {
    var at = choices.map(function(c) { return c.name }).indexOf(name)
    if (at < 1) return
    startRenaming(at)
    newName.text = text
    problem = reason
  }

  function stopEditing() {
    renaming = false
    confirming = false
    problem = ""
    newName.release()
  }

  function saveName() {
    renameRequested(pendingName, newName.text)
  }

  // An emptied field keeps the old name.
  function keepName() {
    if (newName.text.trim() === "") stopEditing()
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

  // The lists' names, in order, and a row for each by name, kept as lists
  // come and go, never moved: a row finds its place by its name.
  readonly property var names: choices.map(function(c) { return c.name })
  ListModel { id: rowsModel }
  Component.onCompleted: {
    recordChoices()
    Rows.syncModel(rowsModel, "name", names)
  }

  // A list dragged by its row, as a stock's row is in your own order
  // (Watchlist): lifted under the pointer, the others making room, and
  // dropped in the place it is over. All stays first.
  readonly property ReorderDrag reorder: ReorderDrag {
    keys: root.names
    pitch: root.itemHeight
    contentY: scroll.contentY
    sight: scroll.height
    reach: Math.max(0, scroll.contentHeight - scroll.height)
    onScrollTo: function(y) { scrollGlide.stop(); scroll.contentY = y }
    first: 1
    onDropped: function(from, to) {
      if (from !== to) root.moveRequested(root.reorder.lifted, to - from)
      root.cursor = to
    }
    onLanded: root.showCursor()
  }

  function beginDrag(name, y) {
    if (!reorder.begin(name, y)) return
    confirming = false
    cursor = reorder.slot
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
    else if (event.key === Qt.Key_PageDown) root.moveCursor(root.pageRows())
    else if (event.key === Qt.Key_PageUp) root.moveCursor(-root.pageRows())
    else if (event.key === Qt.Key_End) root.moveCursor(root.choices.length)
    else if (event.key === Qt.Key_Home) root.moveCursor(-root.choices.length)
    else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) root.askDelete(root.cursor)
  }

  // Opaque ground while fading out over the rows underneath.
  Rectangle {
    z: -1
    anchors.fill: parent
    color: root.look.ground
    visible: !root.open
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
    // renaming, so a click on it reaches the click-away that keeps the name.
    interactive: contentHeight > height && !root.renaming
    // `moving` stays false for a key's scroll.
    onMovementStarted: scrollGlide.stop()
    onContentYChanged: {
      if (scrollGlide.running && Math.abs(contentY - scrollGlide.to) < 0.5) {
        scrollGlide.stop()
        contentY = scrollGlide.to
        return
      }
      if (!root.active || !(moving || manageBar.pressed)) return
      if (moving && pointer.hovered) root.pointAt(pointer.scenePosition.x, pointer.scenePosition.y)
      root.keepCursorInSight()
    }
    Controls.ScrollBar.vertical: ViewScrollBar {
      id: manageBar
      scrolls: scroll.interactive
      onPressedChanged: if (pressed) scrollGlide.stop()
    }

    // The rows, one per list by name, so a list that moves slides to its
    // place as a stock's row does.
    Item {
      id: column
      width: scroll.width - root.gutter
      implicitHeight: root.rowsHeight

      Repeater {
        model: rowsModel

        Item {
          id: entry
          objectName: "manageRow"
          required property string name
          readonly property int index: root.names.indexOf(name)
          readonly property var choice: root.choices[index] || root.foldChoices[name] || ({ name: name, label: "", count: 0 })
          readonly property bool named: name !== ""
          readonly property bool isCursor: !folding && index === root.cursor
          readonly property bool editing: isCursor && root.renaming
          readonly property bool asking: isCursor && root.confirming
          readonly property bool showsActions: named && !editing && !asking && isCursor && !lifted && !folding
          readonly property bool lifted: named && name === root.reorder.lifted
          width: column.width
          height: root.itemHeight
          visible: index >= 0 || folding

          // Where the list sits while another is dragged (`Rows.slotOf`), and
          // below a rename's problem, a row lower. It slides from one place
          // to the next, as a stock's row does (WatchlistRow).
          readonly property int place: root.reorder.slotOf(name)
          readonly property real errorTarget: root.renaming && root.problem !== "" && place > root.cursor ? root.itemHeight : 0
          property real errorOffset: 0
          onErrorTargetChanged: {
            if (!root.active || !root.seen || root.still || Motion.duration(Style, 160) <= 0 || Math.abs(errorTarget - errorOffset) < 0.5) {
              errorSlide.stop()
              errorOffset = errorTarget
              return
            }
            errorSlide.to = errorTarget
            errorSlide.restart()
          }
          NumberAnimation { id: errorSlide; target: entry; property: "errorOffset"; duration: Motion.duration(Style, 160); easing.type: Easing.OutCubic }
          onErrorOffsetChanged: if (errorSlide.running && Math.abs(errorOffset - errorTarget) < 0.5) {
            errorSlide.stop()
            errorOffset = errorTarget
          }
          y: lifted ? root.reorder.liftedY : folding ? foldY : place * root.itemHeight + shift + errorOffset
          property int lastPlace: -1
          property real shift: 0
          onPlaceChanged: {
            var from = lastPlace
            lastPlace = place
            if (folding && place < 0) return
            if (lifted || from < 0 || place < 0) { slide.stop(); shift = 0; return }
            shift += (from - place) * root.itemHeight
            if (Math.abs(shift) < 0.5 || Motion.duration(Style, 160) <= 0) { slide.stop(); shift = 0; return }
            slide.restart()
          }
          Component.onCompleted: { lastPlace = place; errorOffset = errorTarget }
          NumberAnimation { id: slide; target: entry; property: "shift"; to: 0; duration: Motion.duration(Style, 160); easing.type: Easing.OutCubic }
          onShiftChanged: if (slide.running && Math.abs(shift) < 0.5) {
            slide.stop()
            shift = 0
          }

          // Folding: shut from the bottom up and faded over 120 ms, matching WatchlistRow.
          readonly property bool shouldFold: root.foldingNames.indexOf(name) >= 0
          property bool folding: false
          property real foldY: 0
          property real folded: 1
          transform: Scale { yScale: entry.folded }
          onShouldFoldChanged: {
            if (shouldFold) fold()
            else if (folding) endFold()
          }
          function fold() {
            if (folding || lifted) return
            foldY = y
            slide.stop()
            errorSlide.stop()
            folding = true
            foldAnim.restart()
          }
          function endFold() {
            if (!folding) return
            foldAnim.stop()
            folding = false
            folded = 1
            opacity = 1
          }
          ParallelAnimation {
            id: foldAnim
            NumberAnimation { target: entry; property: "folded"; to: 0; duration: Motion.duration(Style, 120); easing.type: Easing.OutCubic }
            NumberAnimation { target: entry; property: "opacity"; to: 0; duration: Motion.duration(Style, 120); easing.type: Easing.OutCubic }
            onFinished: {
              entry.endFold()
              root.finishFold(entry.name)
            }
          }
          Connections {
            target: root
            function onFoldsCleared() { entry.endFold() }
          }
          z: lifted ? root.choices.length + 2 : folding ? -1 : slide.running ? 1 : 0

          // Lifted or sliding, the row lays the card's ground under its fill,
          // so the rows it passes never show through.
          Rectangle {
            width: parent.width
            height: root.itemHeight
            radius: root.look.retro ? 0 : Style.cornerRadius
            visible: entry.lifted || slide.running
            color: root.look.ground
          }

          // Lifted, the row wears the resting control border, as a stock's
          // row does; under the cursor, the shell's cursor outline.
          Rectangle {
            width: parent.width
            height: root.itemHeight
            radius: root.look.retro ? 0 : Style.cornerRadius
            color: entry.lifted ? Style.pressedFillFor(root.look.foreground, Commons.Color.accent)
              : entry.isCursor ? Style.hoverFillFor(root.look.foreground, Commons.Color.accent) : "transparent"
            border.width: entry.lifted ? 1 : entry.isCursor ? Style.hoverBorderWidth : 0
            border.color: entry.lifted ? Style.normalBorderFor(root.look.foreground, Commons.Color.accent)
              : Style.hoverBorderFor(root.look.foreground, Commons.Color.accent)
            Behavior on color { ColorAnimation { duration: Motion.duration(Style, 60) } }
          }

          // A drag lifts a named list and carries it among the others, as a
          // stock's row in your own order; All stays first.
          MouseArea {
            width: parent.width
            height: root.itemHeight
            enabled: entry.named && !entry.folding && !root.renaming && !root.confirming
            preventStealing: true
            cursorShape: entry.lifted ? Qt.ClosedHandCursor : Qt.ArrowCursor
            property real pressY: -1
            property bool dragged: false
            onPressed: function(event) {
              pressY = event.y
              dragged = false
            }
            onPositionChanged: function(event) {
              if (!pressed || pressY < 0) return
              if (!dragged) {
                if (Math.abs(event.y - pressY) < 6) return
                dragged = true
                root.beginDrag(entry.name, entry.mapToItem(column, event.x, pressY).y)
              }
              root.reorder.moveTo(entry.mapToItem(column, event.x, event.y).y)
            }
            onReleased: if (dragged) root.reorder.end()
            onCanceled: if (dragged) root.reorder.cancel()
          }

          Text {
            visible: !entry.editing && !entry.asking
            x: root.inset
            width: (actions.visible ? actions.x : count.x) - x - Style.space(12)
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
            visible: (!entry.named && entry.isCursor) || opacity > 0
            opacity: !entry.named && entry.isCursor ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.duration(Style, 100); easing.type: Easing.OutCubic } }
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
            visible: (entry.showsActions || opacity > 0) && !entry.editing && !entry.asking
            opacity: entry.showsActions ? 1 : 0
            enabled: entry.showsActions
            Behavior on opacity { NumberAnimation { duration: Motion.duration(Style, 100); easing.type: Easing.OutCubic } }
            anchors.right: count.left
            anchors.rightMargin: Style.space(16)
            height: root.itemHeight
            spacing: Style.space(14)

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

          // Delete asks in the row: Stonks has no dialogs. Fades in over 100 ms
          // and clears immediately on cancel so it never overlaps the list name.
          property real askingOpacity: 0
          onAskingChanged: {
            if (asking) {
              if (root.active && root.seen && !root.still && Motion.duration(Style, 100) > 0) {
                askingOpacity = 0
                askingFade.restart()
              } else {
                askingFade.stop()
                askingOpacity = 1
              }
            } else {
              askingFade.stop()
              askingOpacity = 0
            }
          }
          NumberAnimation { id: askingFade; target: entry; property: "askingOpacity"; to: 1; duration: Motion.duration(Style, 100); easing.type: Easing.OutCubic }

          Text {
            visible: entry.asking
            opacity: entry.askingOpacity
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
            opacity: entry.askingOpacity
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
        }
      }
    }

    // Over the cursor's row, clear of its bar, its words where the name's
    // were; under it, why the name was refused, the rows below a row lower.
    InlineNameRow {
      id: newName
      y: root.cursor * root.itemHeight
      width: column.width
      host: root
      look: root.look
      editing: root.renaming
      problem: root.problem
      action: "SAVE"
      lineHeight: root.itemHeight
      textX: root.inset
      fieldX: Style.space(6)
      fieldGap: Style.space(12)
      actionsRight: root.inset
      fieldName: "renameField"
      onTextChanged: root.problem = ""
      onSubmitted: root.saveName()
      onCancelled: root.stopEditing()
    }
  }
}
