import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Cells.js" as Cells
import "Rows.js" as Rows
import "Motion.js" as Motion
// The list's header: its name, a menu, left of the rule, as Apple puts it
// atop a list; the order and the rows' unit on the right. Its height is the
// caption line's, never a word's: a glyph from another font is taller and
// would move the rows. Like a line of text, it rounds its ascent and descent
// up to whole pixels each.
Item {
  id: root

  property string listLabel: "All"
  property bool listMenuOpen: false
  // The day the rows measure (`Figures.rowsDayName`): "TODAY", "FRI", or
  // "MON".
  property string rowsDay: "TODAY"
  property var breadth: ({ list: "", up: 0, flat: 0, down: 0, none: 0 })
  // Search or a list view covers the rows: the header names their list and
  // says nothing of rows out of sight.
  property bool rowsCovered: false
  property string order: "manual"
  property bool reversed: false
  property string changeMode: "pct"
  property Look look
  property bool seen: true
  // Closing: what moves stops where it is.
  property bool still: false

  signal listClicked()
  signal orderClicked()
  signal orderReverseClicked()
  signal unitClicked()

  property real chevronAngle: 0
  property real rowsOpacity: 1
  property string prevMode: changeMode
  property real unitSwap: 1
  // Eased width of the sort-order label, so the breadth rule fills all room
  // at rest and its right end travels smoothly when the sort label changes
  // width.
  property real orderRoom: orderText.implicitWidth
  property string lastOrder: ""

  Component.onCompleted: settle()
  function settle() {
    breadthRule.settle()
    chevronAnim.stop()
    chevronAngle = listMenuOpen ? 180 : 0
    rowsFade.stop()
    rowsOpacity = rowsCovered ? 0 : 1
    unitSwapAnim.stop()
    prevMode = changeMode
    unitSwap = 1
    orderRoomAnim.stop()
    lastOrder = order
    orderRoom = orderText.implicitWidth
  }
  onStillChanged: {
    if (still) {
      if (chevronAnim.running) chevronAnim.pause()
      if (rowsFade.running) rowsFade.pause()
      if (unitSwapAnim.running) unitSwapAnim.pause()
      if (orderRoomAnim.running) orderRoomAnim.pause()
    } else if (orderRoomAnim.paused) {
      orderRoomAnim.stop()
      lastOrder = order
      orderRoom = orderText.implicitWidth
    }
  }
  function moveOrderRoom() {
    if (still) return
    var to = orderText.implicitWidth
    var changedOrder = lastOrder !== "" && lastOrder !== order
    lastOrder = order
    if (!changedOrder || !seen || !visible || rowsCovered || Motion.duration(Style, 160) <= 0) {
      orderRoomAnim.stop()
      orderRoom = to
      return
    }
    if (Math.abs(to - (orderRoomAnim.running ? orderRoomAnim.to : orderRoom)) < 0.5) return
    orderRoomAnim.stop()
    orderRoomAnim.to = to
    orderRoomAnim.start()
  }
  NumberAnimation {
    id: orderRoomAnim
    target: root
    property: "orderRoom"
    duration: Motion.duration(Style, 160)
    easing.type: Easing.Bezier
    easing.bezierCurve: Motion.curve(Style)
  }
  onOrderRoomChanged: if (orderRoomAnim.running && Math.abs(orderRoom - orderRoomAnim.to) < 0.5) {
    orderRoomAnim.stop()
    orderRoom = orderRoomAnim.to
  }
  onSeenChanged: if (!seen) Qt.callLater(function() { if (!root.seen && !root.still) root.settle() })
  Connections {
    target: Style
    ignoreUnknownSignals: true
    function onReduceMotionChanged() { if (Style.reduceMotion) root.settle() }
  }
  onListMenuOpenChanged: {
    if (still) return
    var to = listMenuOpen ? 180 : 0
    if (!seen || !visible || Motion.duration(Style, 140) <= 0) {
      chevronAnim.stop()
      chevronAngle = to
      return
    }
    chevronAnim.stop()
    chevronAnim.to = to
    chevronAnim.start()
  }
  NumberAnimation { id: chevronAnim; target: root; property: "chevronAngle"; duration: Motion.duration(Style, 140); easing.type: Easing.OutCubic }
  onChevronAngleChanged: if (chevronAnim.running && Math.abs(chevronAngle - chevronAnim.to) < 2) {
    chevronAnim.stop()
    chevronAngle = chevronAnim.to
  }
  onRowsCoveredChanged: {
    if (still) return
    var to = rowsCovered ? 0 : 1
    if (!seen || !visible || Motion.duration(Style, 140) <= 0) {
      rowsFade.stop()
      rowsOpacity = to
      return
    }
    rowsFade.stop()
    rowsFade.to = to
    rowsFade.start()
  }
  NumberAnimation { id: rowsFade; target: root; property: "rowsOpacity"; duration: Motion.duration(Style, 140); easing.type: Easing.OutCubic }
  onRowsOpacityChanged: if (rowsFade.running && Math.abs(rowsOpacity - rowsFade.to) < 0.01) {
    rowsFade.stop()
    rowsOpacity = rowsFade.to
  }
  onChangeModeChanged: {
    var from = prevMode
    if (still) {
      prevMode = changeMode
      return
    }
    if (!from || from === changeMode || !seen || !visible || rowsCovered || Motion.duration(Style, 140) <= 0) {
      unitSwapAnim.stop()
      prevMode = changeMode
      unitSwap = 1
      return
    }
    unitSwapAnim.stop()
    unitSwap = 0
    unitSwapAnim.start()
  }
  NumberAnimation {
    id: unitSwapAnim
    target: root
    property: "unitSwap"
    to: 1
    duration: Motion.duration(Style, 140)
    easing.type: root.look.retro ? Easing.Linear : Easing.OutCubic
    onFinished: root.prevMode = root.changeMode
  }
  onUnitSwapChanged: if (unitSwapAnim.running && !look.retro && unitSwap > 0.99) {
    unitSwapAnim.stop()
    unitSwap = 1
    prevMode = changeMode
  }

  height: Math.ceil(captionLine.ascent) + Math.ceil(captionLine.descent)

  FontMetrics {
    id: captionLine
    font: orderText.font
  }

  // Widest sort-order label in the current font, so cycling sort orders
  // never shifts a long elided list name, its chevron or TODAY.
  readonly property real widestOrderWidth: {
    var font = captionLine.font // read, so a new text size measures again
    var widest = 0
    var orders = Object.keys(Rows.ORDER_LABELS)
    for (var i = 0; i < orders.length; i++) {
      widest = Math.max(widest,
        Math.ceil(captionLine.advanceWidth(Rows.orderLabel(orders[i], false))),
        Math.ceil(captionLine.advanceWidth(Rows.orderLabel(orders[i], true))))
    }
    return widest
  }

  Rectangle {
    objectName: "listControl"
    anchors.left: listText.left
    anchors.leftMargin: -Style.space(6)
    anchors.right: listChevron.right
    anchors.rightMargin: -Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    height: parent.height + Style.space(4)
    radius: root.look.retro ? 0 : Style.cornerRadius
    color: listMouse.pressed ? Style.pressedFillFor(root.look.foreground, Commons.Color.accent)
      : root.listMenuOpen ? Style.selectedFillFor(root.look.foreground, Commons.Color.accent)
      : listMouse.containsMouse ? Style.hoverFillFor(root.look.foreground, Commons.Color.accent) : "transparent"
    Behavior on color { ColorAnimation { duration: Motion.duration(Style, 120) } }
  }

  Text {
    id: listText
    objectName: "listLabel"
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(0, Math.min(implicitWidth, parent.width - root.widestOrderWidth - todayText.implicitWidth
      - unitSign.width - orderText.anchors.rightMargin - Style.space(80)))
    textFormat: Text.PlainText
    text: root.listLabel.toUpperCase()
    color: root.look.foreground
    font.family: root.look.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
    elide: Text.ElideRight
  }

  Text {
    id: listChevron
    objectName: "listChevron"
    anchors.left: listText.right
    anchors.leftMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    rotation: root.chevronAngle
    text: "󰅀"
    color: root.look.dim
    font.family: root.look.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  MouseArea {
    id: listMouse
    anchors.left: listText.left
    anchors.right: listChevron.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.margins: -Style.space(6)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.listClicked()
  }

  // The rows and the rule are the day's on every range, and say which.
  Text {
    id: todayText
    visible: !root.rowsCovered || root.rowsOpacity > 0
    opacity: root.rowsOpacity
    anchors.left: listChevron.right
    anchors.leftMargin: root.rowsDay !== "" ? Style.space(12) : 0
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.rowsDay
    color: root.look.dim
    font.family: root.look.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
  }

  // The list's breadth. It rests while the rows are covered, fills the room
  // beside the sort label at rest, and travels smoothly as the sort label
  // changes width.
  BreadthRule {
    id: breadthRule
    objectName: "breadthRule"
    visible: !root.rowsCovered || root.rowsOpacity > 0
    opacity: root.rowsOpacity
    anchors.left: todayText.right
    anchors.leftMargin: root.rowsDay !== "" ? Style.space(10) : Style.space(12)
    anchors.right: unitBox.left
    anchors.rightMargin: root.orderRoom + orderText.anchors.rightMargin + Style.space(10)
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    breadth: root.breadth
    look: root.look
    seen: root.seen
    still: root.still || root.rowsCovered
  }

  // Hovers as a range does, so it reads as a control, not a label. In a
  // sorted order the arrow reverses and the word steps to the next order,
  // each with its own fill; manual has no direction, so both step.
  Rectangle {
    visible: !root.rowsCovered || root.rowsOpacity > 0
    opacity: root.rowsOpacity
    anchors.right: orderText.right
    anchors.rightMargin: -Style.space(6)
    anchors.verticalCenter: orderText.verticalCenter
    width: orderText.sorted ? orderText.implicitWidth - orderText.wordStart + Style.space(12)
      : orderText.implicitWidth + Style.space(12)
    height: parent.height + Style.space(4)
    radius: root.look.retro ? 0 : Style.cornerRadius
    readonly property bool hovered: !root.rowsCovered && (wordMouse.containsMouse || !orderText.sorted && arrowMouse.containsMouse)
    readonly property bool pressed: !root.rowsCovered && (wordMouse.pressed || !orderText.sorted && arrowMouse.pressed)
    color: pressed ? Style.pressedFillFor(root.look.foreground, Commons.Color.accent)
      : hovered ? Style.hoverFillFor(root.look.foreground, Commons.Color.accent) : "transparent"
    Behavior on color { ColorAnimation { duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) } }
  }

  // Padded as the word's fill pads the word, so the two read as two
  // buttons.
  Rectangle {
    visible: (!root.rowsCovered || root.rowsOpacity > 0) && orderText.sorted
    opacity: root.rowsOpacity
    x: orderText.x - Style.space(6)
    width: Math.round(arrowMetrics.advanceWidth) + Style.space(12)
    anchors.verticalCenter: orderText.verticalCenter
    height: parent.height + Style.space(4)
    radius: root.look.retro ? 0 : Style.cornerRadius
    color: !root.rowsCovered && arrowMouse.pressed ? Style.pressedFillFor(root.look.foreground, Commons.Color.accent)
      : !root.rowsCovered && arrowMouse.containsMouse ? Style.hoverFillFor(root.look.foreground, Commons.Color.accent) : "transparent"
    Behavior on color { ColorAnimation { duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) } }
  }

  // The arrow alone, and with the two spaces after it.
  TextMetrics {
    id: arrowMetrics
    font: orderText.font
    text: orderText.text.slice(0, 1)
  }
  TextMetrics {
    id: gapMetrics
    font: orderText.font
    text: orderText.text.slice(0, 3)
  }

  Text {
    id: orderText
    objectName: "orderLabel"
    visible: !root.rowsCovered || root.rowsOpacity > 0
    opacity: root.rowsOpacity
    anchors.right: unitBox.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: Rows.orderLabel(root.order, root.reversed)
    onImplicitWidthChanged: root.moveOrderRoom()
    readonly property bool sorted: root.order !== "manual"
    // The arrow's target runs to the word's first letter, and left to make
    // the shell's 22 px, but never into the breadth rule, whose hover says
    // the counts.
    readonly property real wordStart: Math.round(gapMetrics.advanceWidth)
    readonly property real arrowReach: Math.min(Style.space(10),
      Math.max(Style.space(6), Style.space(22) - wordStart))
    property real lift: !root.rowsCovered && (arrowMouse.containsMouse || wordMouse.containsMouse) ? 1 : 0
    Behavior on lift { NumberAnimation { duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) } }
    // Brighter only under the pointer: the list's name is the header's one
    // word in full ink.
    color: Qt.tint(root.look.dim, Util.alpha(root.look.foreground, lift))
    font.family: root.look.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1

    MouseArea {
      id: arrowMouse
      objectName: "orderArrow"
      enabled: !root.rowsCovered
      x: -orderText.arrowReach
      y: -Style.space(6)
      width: orderText.arrowReach + orderText.wordStart
      height: parent.height + Style.space(12)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: orderText.sorted ? root.orderReverseClicked() : root.orderClicked()
    }

    // Half the gap before the unit; the unit's target takes the other half.
    MouseArea {
      id: wordMouse
      enabled: !root.rowsCovered
      x: orderText.wordStart
      y: -Style.space(6)
      width: parent.width - orderText.wordStart + orderText.anchors.rightMargin / 2
      height: parent.height + Style.space(12)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        if (mouse.modifiers & Qt.ShiftModifier) root.orderReverseClicked()
        else root.orderClicked()
      }
    }
  }

  // The rows' unit at the figures' edge, where a table puts a column's:
  // % for a percent, ± for an amount, the market's bell for since the open.
  // The signs are one width, so a step moves nothing.
  Rectangle {
    visible: !root.rowsCovered || root.rowsOpacity > 0
    opacity: root.rowsOpacity
    anchors.horizontalCenter: unitBox.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: unitBox.width + Style.space(12)
    height: parent.height + Style.space(4)
    radius: root.look.retro ? 0 : Style.cornerRadius
    color: !root.rowsCovered && unitMouse.pressed ? Style.pressedFillFor(root.look.foreground, Commons.Color.accent)
      : !root.rowsCovered && unitMouse.containsMouse ? Style.hoverFillFor(root.look.foreground, Commons.Color.accent) : "transparent"
    Behavior on color { ColorAnimation { duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) } }
  }

  Item {
    id: unitBox
    visible: !root.rowsCovered || root.rowsOpacity > 0
    opacity: root.rowsOpacity
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: unitSign.implicitWidth
    height: unitSign.implicitHeight
    property color ink: !root.rowsCovered && unitMouse.containsMouse ? root.look.foreground : root.look.dim
    Behavior on ink { ColorAnimation { duration: Motion.duration(Style, 120) } }
    readonly property int cell: Cells.iconCell(Style.fontScale)
    readonly property bool swapping: root.unitSwap < 1
    readonly property real wipeX: Math.round(root.unitSwap * width)

    // Outgoing unit sign: crossfades out in smooth, wipes right in retro.
    Item {
      visible: unitBox.swapping
      x: root.look.retro ? unitBox.wipeX : 0
      y: -unitSign.bleed
      width: root.look.retro ? Math.max(0, unitBox.width - unitBox.wipeX) : unitBox.width
      height: unitBox.height + unitSign.bleed * 2
      clip: root.look.retro
      GridIcon {
        x: -parent.x
        y: unitSign.bleed
        opacity: root.look.retro ? 1 : 1 - root.unitSwap
        cell: unitBox.cell
        shape: Cells.UNIT_SIGNS[root.prevMode]
        color: unitBox.ink
      }
    }

    Item {
      x: 0
      y: -unitSign.bleed
      width: unitBox.swapping && root.look.retro ? unitBox.wipeX : unitBox.width
      height: unitBox.height + unitSign.bleed * 2
      clip: unitBox.swapping && root.look.retro
      GridIcon {
        id: unitSign
        y: bleed
        opacity: unitBox.swapping && !root.look.retro ? root.unitSwap : 1
        cell: unitBox.cell
        shape: Cells.UNIT_SIGNS[root.changeMode]
        color: unitBox.ink
      }
    }
  }

  MouseArea {
    id: unitMouse
    objectName: "unitTarget"
    visible: !root.rowsCovered
    anchors.left: unitBox.left
    anchors.leftMargin: -orderText.anchors.rightMargin / 2
    anchors.right: unitBox.right
    anchors.rightMargin: -Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    height: parent.height + Style.space(12)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.unitClicked()

    // A sign can't say what it counts from, so the tip does.
    PanelToolTip {
      visible: unitMouse.containsMouse
      text: ({ pct: "% change since the previous close", abs: "Change since the previous close, in each stock's currency",
        open: "% change since the open" })[root.changeMode] || ""
      fontFamily: root.look.fontFamily
      y: parent.height + 3
      x: parent.width - implicitWidth
    }
  }
}
