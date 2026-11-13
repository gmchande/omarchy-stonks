import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Commands.js" as Commands
// The shell's text field (Ui/TextField), drawn and worked as it is, with
// Stonks' dim placeholder: the shell's Qt.darker(foreground) is as dark as
// typed text on a light theme.
//
// The shell's field is Qt's TextInput, which reads all the clipboard holds,
// on the shell's thread, each time the clipboard changes while it can be
// typed in, and each time it becomes so: a clipboard that never stops
// sending would hold the shell. So the text here is Qt's TextEdit, as a
// TextArea, which asks only what kinds of data the clipboard holds, held to
// one line. A paste, by keys, the middle button or the right-click menu,
// reads the clipboard here instead, outside the shell's thread
// (`Commands.pastedText`): at most `pasteCap` bytes, in 2 s, or nothing.
FocusScope {
  id: root

  property bool retro: false
  property color dim: foreground

  // Ui/TextField's own.
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color selectionTint: Style.selectionFillFor(foreground, accent)
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY
  property bool hasCursor: false
  readonly property var borderSpec: Border.controlSpec(activeFocus ? "focus" : (area.hovered || hasCursor ? "hover-cursor" : "normal"), foreground, accent)

  // A TextField's.
  property real leftPadding: horizontalPadding + Border.left(borderSpec)
  property real rightPadding: horizontalPadding + Border.right(borderSpec)
  property real topPadding: verticalPadding + Border.top(borderSpec)
  property real bottomPadding: verticalPadding + Border.bottom(borderSpec)
  // A text set here puts the cursor at its end, as a TextField's does; a
  // TextEdit's would stay at the start.
  property string text: ""
  onTextChanged: {
    if (area.text === text) return
    area.text = text
    area.cursorPosition = area.length
  }
  property alias placeholderText: area.placeholderText
  property alias font: area.font
  property alias cursorPosition: area.cursorPosition
  readonly property alias selectionStart: area.selectionStart
  readonly property alias selectionEnd: area.selectionEnd
  readonly property alias hovered: area.hovered
  function selectAll() { area.selectAll() }
  // Enter.
  signal accepted()

  implicitWidth: area.implicitWidth + leftPadding + rightPadding
  implicitHeight: area.implicitHeight + topPadding + bottomPadding

  BorderSurface {
    anchors.fill: parent
    color: Style.controlFill(root.activeFocus, area.hovered || root.hasCursor, root.foreground, root.accent)
    borderSpec: root.borderSpec
    // In retro its corners are square, as every fill there is.
    radius: root.retro ? 0 : Style.cornerRadius
  }

  // The text, in a TextField's place, clipped where a TextField clips it:
  // its paddings in, with a pixel more at the end for the cursor.
  TextArea {
    id: area
    x: root.leftPadding
    y: root.topPadding
    width: Math.max(0, root.width - root.leftPadding - root.rightPadding) + 1
    height: Math.max(0, root.height - root.topPadding - root.bottomPadding)
    clip: true
    focus: true
    // The pointer anywhere in the field, its paddings too, is in the text,
    // as in a TextField: Qt looks past a clipped item's edges only as far as
    // its pointer handlers' margin, and the mask then takes the field's
    // whole rectangle.
    HoverHandler { margin: Math.max(root.leftPadding, root.rightPadding, root.topPadding, root.bottomPadding) }
    containmentMask: QtObject {
      function contains(point: point): bool {
        return point.x >= -area.x && point.y >= -area.y && point.x < root.width - area.x && point.y < root.height - area.y
      }
    }
    background: null
    padding: 0
    leftPadding: -root.scrolled
    rightPadding: 1
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    color: root.foreground
    selectionColor: root.selectionTint
    selectedTextColor: root.foreground
    placeholderTextColor: root.dim
    textFormat: TextEdit.PlainText
    wrapMode: TextEdit.NoWrap
    verticalAlignment: TextEdit.AlignVCenter

    // The right-click menu, Qt's own for a TextArea in Fusion
    // (TextEditingContextMenu), but for its Paste: Qt's calls the text's own
    // paste, which reads the clipboard on the shell's thread. This one
    // pastes once it has closed and handed the keys back to the field.
    ContextMenu.menu: Menu {
      id: menu
      property bool pasteOwed: false
      // As Qt's on Wayland, where the shell runs, and in the walks too.
      popupType: Popup.Item
      onAboutToShow: pasteOwed = false
      // Not if the field went from sight or lost the keys meanwhile.
      onClosed: {
        if (pasteOwed && root.visible && root.activeFocus) root.pasteFrom(false)
        pasteOwed = false
      }
      Action {
        text: qsTr("Undo")
        icon.name: "edit-undo"
        icon.width: 24
        icon.height: 24
        shortcut: StandardKey.Undo
        enabled: area.canUndo
        onTriggered: area.undo()
      }
      Action {
        text: qsTr("Redo")
        icon.name: "edit-redo"
        icon.width: 24
        icon.height: 24
        shortcut: StandardKey.Redo
        enabled: area.canRedo
        onTriggered: area.redo()
      }
      MenuSeparator {}
      Action {
        text: qsTr("Cut")
        icon.name: "edit-cut"
        icon.width: 24
        icon.height: 24
        shortcut: StandardKey.Cut
        enabled: area.selectedText.length > 0
        onTriggered: area.cut()
      }
      Action {
        text: qsTr("Copy")
        icon.name: "edit-copy"
        icon.width: 24
        icon.height: 24
        shortcut: StandardKey.Copy
        enabled: area.selectedText.length > 0
        onTriggered: area.copy()
      }
      Action {
        text: qsTr("Paste")
        icon.name: "edit-paste"
        icon.width: 24
        icon.height: 24
        shortcut: StandardKey.Paste
        onTriggered: menu.pasteOwed = true
      }
      Action {
        text: qsTr("Delete")
        icon.name: "edit-delete"
        icon.width: 24
        icon.height: 24
        shortcut: StandardKey.Delete
        enabled: area.selectedText.length > 0
        onTriggered: area.remove(area.selectionStart, area.selectionEnd)
      }
      MenuSeparator {}
      Action {
        text: qsTr("Select All")
        icon.name: "edit-select-all"
        icon.width: 24
        icon.height: 24
        shortcut: StandardKey.SelectAll
        onTriggered: area.selectAll()
      }
    }

    // Callers' keys come first, as on a TextField; a key that passes both
    // them and the field comes back to them as it goes on.
    Keys.forwardTo: [root]
    Keys.onPressed: function(event) { root.key(event) }

    // The selection's top row and the cursor, drawn as a TextInput draws
    // them: out to whole pixels on every side (QRectF::toAlignedRect). A
    // TextEdit draws a line centred on a half pixel, as a list's name is,
    // from the pixel below.
    Rectangle {
      readonly property rect from: area.positionToRectangle(area.selectionStart)
      readonly property rect to: area.positionToRectangle(area.selectionEnd)
      readonly property var box: root.aligned(from.x, from.y, to.x, from.y + from.height)
      z: -0.5
      visible: area.selectionStart !== area.selectionEnd
      x: box.x
      y: box.y
      width: box.width
      height: Math.round(from.y) - box.y
      color: root.selectionTint
    }
    cursorDelegate: Item {
      id: cursor
      // The text it is the cursor of.
      readonly property var edit: parent
      // Over the text, as a TextInput's, and under the placeholder.
      z: edit && edit.length === 0 ? -0.25 : 0
      // A TextInput's blink, begun again at each move.
      property bool lit: true
      Connections {
        target: cursor.edit
        function onCursorPositionChanged() { cursor.lit = true; blink.restart() }
        function onTextChanged() { cursor.lit = true; blink.restart() }
      }
      Timer {
        id: blink
        interval: Application.styleHints.cursorFlashTime / 2
        running: !!cursor.edit && cursor.edit.cursorVisible && interval > 0
        repeat: true
        onTriggered: cursor.lit = !cursor.lit
        onRunningChanged: cursor.lit = true
      }
      Rectangle {
        // Out to whole pixels, as `aligned` draws the selection.
        x: Math.floor(cursor.x) - cursor.x
        y: Math.floor(cursor.y) - cursor.y
        width: Math.ceil(cursor.x + 1) - Math.floor(cursor.x)
        height: Math.ceil(cursor.y + cursor.height) - Math.floor(cursor.y)
        visible: !!cursor.edit && cursor.edit.cursorVisible && cursor.lit
        color: cursor.edit ? cursor.edit.color : "transparent"
      }
    }

    onCursorRectangleChanged: root.scroll()
    onContentWidthChanged: root.scroll()
    onWidthChanged: root.scroll()
    onTextChanged: {
      root.text = area.text
      root.edited()
    }
    onCursorPositionChanged: root.edited()
    onSelectionStartChanged: root.edited()
    onSelectionEndChanged: root.edited()
    onPreeditTextChanged: root.edited()
  }

  function aligned(left, top, right, bottom) {
    return { x: Math.floor(left), y: Math.floor(top), width: Math.ceil(right) - Math.floor(left), height: Math.ceil(bottom) - Math.floor(top) }
  }

  // A TextInput's scroll: the text moves only as far as keeps the cursor in
  // sight (QQuickTextInputPrivate::ensureVisible).
  property real scrolled: 0
  function scroll() {
    var room = area.width - 1
    var x = area.cursorRectangle.x + scrolled
    var used = area.contentWidth > x ? area.contentWidth : x
    var to = scrolled
    if (used <= room) to = 0
    else if (x - to >= room) to = x - room
    else if (x - to < 0 && to < used) to = x
    else if (used - to < room) to = used - room
    scrolled = to
  }

  // Each key as a TextField takes it.
  function key(event) {
    if (event.matches(StandardKey.Paste)) {
      event.accepted = true
      pasteFrom(false)
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      // A TextField says so and lets the key on; here it would be a line.
      event.accepted = true
      accepted()
    } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
      // A TextField takes no tab: the key moves the focus on, if anything
      // else in the window takes it.
      event.accepted = true
      var next = area.nextItemInFocusChain(event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))
      if (next && next !== area) next.forceActiveFocus(Qt.TabFocusReason)
    } else if (event.matches(StandardKey.Cut) && area.selectedText === "") {
      // A TextField's cut with nothing selected deletes the next character.
      event.accepted = true
      area.remove(area.cursorPosition, Math.min(area.length, area.cursorPosition + 1))
    } else if (event.matches(StandardKey.DeleteCompleteLine)) {
      event.accepted = true
      area.selectAll()
      area.copy()
      area.remove(0, area.length)
    } else if ([StandardKey.MoveToNextLine, StandardKey.MoveToPreviousLine, StandardKey.SelectNextLine, StandardKey.SelectPreviousLine,
        StandardKey.MoveToStartOfDocument, StandardKey.MoveToEndOfDocument, StandardKey.SelectStartOfDocument, StandardKey.SelectEndOfDocument,
        StandardKey.MoveToNextPage, StandardKey.MoveToPreviousPage, StandardKey.SelectNextPage, StandardKey.SelectPreviousPage]
        .some(function(key) { return event.matches(key) })) {
      // Keys of a text of many lines, which a TextField passes over.
      event.accepted = true
    }
  }

  // The left and middle buttons, as a TextField takes them. A TextField's
  // one line takes the pointer by where it is along the line, anywhere in
  // the field; a TextEdit's text above or below its line is its start or
  // its end, so the field takes the pointer here
  // (QQuickTextInput::mousePressEvent and the rest). A press puts the
  // cursor there, or with Shift selects to there; a drag selects; a double
  // click takes the word, a third click all. The middle button pastes the
  // primary selection where it lands. The right button is the text's own,
  // for its menu.
  MouseArea {
    id: pointer
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: Qt.IBeamCursor
    property bool selecting: false
    property point doubled
    function at(mouse) {
      var x = mapToItem(area, mouse.x, 0).x
      return area.positionAt(x, area.cursorRectangle.y + area.cursorRectangle.height / 2)
    }
    Timer { id: tripleWait; interval: Application.styleHints.mouseDoubleClickInterval }
    onPressed: function(mouse) {
      area.forceActiveFocus(Qt.MouseFocusReason)
      selecting = false
      if (mouse.button === Qt.MiddleButton) {
        area.cursorPosition = at(mouse)
        return
      }
      var near = Math.abs(mouse.x - doubled.x) + Math.abs(mouse.y - doubled.y) < Application.styleHints.startDragDistance
      if (tripleWait.running && near) {
        tripleWait.stop()
        area.selectAll()
        return
      }
      selecting = true
      if (mouse.modifiers & Qt.ShiftModifier) area.moveCursorSelection(at(mouse), TextEdit.SelectCharacters)
      else area.cursorPosition = at(mouse)
    }
    onDoubleClicked: function(mouse) {
      if (mouse.button !== Qt.LeftButton) return
      area.cursorPosition = at(mouse)
      area.selectWord()
      doubled = Qt.point(mouse.x, mouse.y)
      tripleWait.restart()
    }
    onPositionChanged: function(mouse) {
      if (selecting && pressedButtons & Qt.LeftButton) area.moveCursorSelection(at(mouse), TextEdit.SelectCharacters)
    }
    onReleased: function(mouse) {
      selecting = false
      if (mouse.button === Qt.LeftButton) {
        if (area.selectedText !== "") root.copyPrimary(area.selectedText)
        return
      }
      area.deselect()
      root.pasteFrom(true)
    }
  }

  // A paste lands only on the field as it was asked: typing, moving the
  // cursor or the selection, losing the keys or going from sight drops it.
  readonly property int pasteCap: 4096
  property bool pastePrimary: false
  property int pasteAsked: 0
  property int pasteCode: -1
  function pasteFrom(primary) {
    if (pasting.running || !root.visible) return
    pastePrimary = primary
    pasteAsked = edits
    pasteCode = -1
    pasting.running = true
  }
  property int edits: 0
  function edited() {
    edits++
    pasting.running = false
  }
  onActiveFocusChanged: if (!activeFocus) edited()
  onVisibleChanged: edited()

  Process {
    id: pasting
    command: Commands.pastedText(root.pastePrimary, root.pasteCap)
    stdout: StdioCollector { id: pasted }
    onExited: function(code) { root.pasteCode = code }
    // A command that fails to start ends with no exit.
    onRunningChanged: {
      if (running || root.pasteAsked !== root.edits) return
      var text = Commands.readPastedText(root.pasteCode, pasted.data.byteLength, pasted.text, root.pasteCap)
      if (text === null) return
      area.remove(area.selectionStart, area.selectionEnd)
      area.insert(area.cursorPosition, text)
    }
  }

  // Text selected with the pointer goes to the primary selection, as a
  // TextField puts it there on the button's release (`Commands.primaryCopy`).
  function copyPrimary(text) {
    if (primaryCopy.running) primaryCopy.running = false
    primaryCopy.text = text
    primaryCopy.stdinEnabled = true
    primaryCopy.running = true
  }
  Process {
    id: primaryCopy
    property string text: ""
    command: Commands.primaryCopy()
    onStarted: {
      write(text)
      stdinEnabled = false
    }
  }
}
