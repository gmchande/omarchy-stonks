import QtQuick
import qs.Commons
import qs.Commons as Commons
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
  // The day the rows measure (`Figures.rowsDay`): "TODAY", "FRI", or
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
  // Closing: what moves stops where it is.
  property bool still: false

  signal listClicked()
  signal orderClicked()
  signal orderReverseClicked()
  signal unitClicked()

  function settle() { breadthRule.settle() }

  height: Math.ceil(captionLine.ascent) + Math.ceil(captionLine.descent)

  FontMetrics {
    id: captionLine
    font: orderText.font
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
    Behavior on color { ColorAnimation { duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) } }
  }

  Text {
    id: listText
    objectName: "listLabel"
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, parent.width - orderText.implicitWidth - todayText.implicitWidth
      - unitSign.width - orderText.anchors.rightMargin - Style.space(80))
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
    anchors.left: listText.right
    anchors.leftMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
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
    visible: !root.rowsCovered
    anchors.left: listChevron.right
    anchors.leftMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.rowsDay
    color: root.look.dim
    font.family: root.look.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
  }

  // The list's breadth. It rests while the rows are covered.
  BreadthRule {
    id: breadthRule
    objectName: "breadthRule"
    visible: !root.rowsCovered
    anchors.left: todayText.right
    anchors.leftMargin: Style.space(10)
    anchors.right: orderText.left
    anchors.rightMargin: Style.space(10)
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    breadth: root.breadth
    look: root.look
    still: root.still || root.rowsCovered
  }

  // Hovers as a range does, so it reads as a control, not a label. In a
  // sorted order the arrow reverses and the word steps to the next order,
  // each with its own fill; manual has no direction, so both step.
  Rectangle {
    visible: !root.rowsCovered
    anchors.right: orderText.right
    anchors.rightMargin: -Style.space(6)
    anchors.verticalCenter: orderText.verticalCenter
    width: orderText.sorted ? orderText.implicitWidth - orderText.wordStart + Style.space(12)
      : orderText.implicitWidth + Style.space(12)
    height: parent.height + Style.space(4)
    radius: root.look.retro ? 0 : Style.cornerRadius
    readonly property bool hovered: wordMouse.containsMouse || !orderText.sorted && arrowMouse.containsMouse
    readonly property bool pressed: wordMouse.pressed || !orderText.sorted && arrowMouse.pressed
    color: pressed ? Style.pressedFillFor(root.look.foreground, Commons.Color.accent)
      : hovered ? Style.hoverFillFor(root.look.foreground, Commons.Color.accent) : "transparent"
    Behavior on color { ColorAnimation { duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) } }
  }

  // Padded as the word's fill pads the word, so the two read as two
  // buttons.
  Rectangle {
    visible: !root.rowsCovered && orderText.sorted
    x: orderText.x - Style.space(6)
    width: Math.round(arrowMetrics.advanceWidth) + Style.space(12)
    anchors.verticalCenter: orderText.verticalCenter
    height: parent.height + Style.space(4)
    radius: root.look.retro ? 0 : Style.cornerRadius
    color: arrowMouse.pressed ? Style.pressedFillFor(root.look.foreground, Commons.Color.accent)
      : arrowMouse.containsMouse ? Style.hoverFillFor(root.look.foreground, Commons.Color.accent) : "transparent"
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
    visible: !root.rowsCovered
    anchors.right: unitSign.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: Rows.orderLabel(root.order, root.reversed)
    readonly property bool sorted: root.order !== "manual"
    // The arrow's target runs to the word's first letter, and left to make
    // the shell's 22 px, but never into the breadth rule, whose hover says
    // the counts.
    readonly property real wordStart: Math.round(gapMetrics.advanceWidth)
    readonly property real arrowReach: Math.min(breadthRule.anchors.rightMargin,
      Math.max(Style.space(6), Style.space(22) - wordStart))
    property real lift: arrowMouse.containsMouse || wordMouse.containsMouse ? 1 : 0
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
    visible: !root.rowsCovered
    anchors.horizontalCenter: unitSign.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: unitSign.width + Style.space(12)
    height: parent.height + Style.space(4)
    radius: root.look.retro ? 0 : Style.cornerRadius
    color: unitMouse.pressed ? Style.pressedFillFor(root.look.foreground, Commons.Color.accent)
      : unitMouse.containsMouse ? Style.hoverFillFor(root.look.foreground, Commons.Color.accent) : "transparent"
    Behavior on color { ColorAnimation { duration: Motion.duration(Style, 160); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) } }
  }

  GridIcon {
    id: unitSign
    visible: !root.rowsCovered
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    cell: Cells.iconCell(Style.fontScale)
    shape: Cells.UNIT_SIGNS[root.changeMode]
    color: unitMouse.containsMouse ? root.look.foreground : root.look.dim
  }

  MouseArea {
    id: unitMouse
    objectName: "unitTarget"
    visible: !root.rowsCovered
    anchors.left: unitSign.left
    anchors.leftMargin: -orderText.anchors.rightMargin / 2
    anchors.right: unitSign.right
    anchors.rightMargin: -Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    height: parent.height + Style.space(12)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.unitClicked()
  }
}
