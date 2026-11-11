pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

// The `?` sheet on both surfaces: key groups in two columns, the credit
// closing the second, then Close.
Flickable {
  id: root

  // KeySheet.sheet: { groups }.
  property var sheet: ({ groups: [] })
  property Look look
  // `edge` is the room right of the rows' figures. Close ends there, so its
  // fill stays inside the clip; what a key does may run past it.
  property int inset: 0
  property int edge: 0
  property string version: ""
  // One part a line, so a half column never breaks one mid-phrase. With no
  // version known the credit leaves it off rather than show a blank.
  readonly property string credit: ["Every key is in the README"]
    .concat(version !== "" ? ["Stonks " + version] : [])
    .concat(["Prices from Yahoo", "Overnight from Robinhood"]).join("\n")

  signal closeRequested()

  readonly property var groups: sheet.groups
  // Two columns, the first taking groups until it holds about half the
  // lines: one column would leave half the window empty.
  readonly property int split: {
    var lines = function(group) { return group.rows.length + 1 }
    var total = 0
    for (var i = 0; i < groups.length; i++) total += lines(groups[i])
    var taken = 0
    for (var j = 0; j < groups.length; j++) {
      if (taken + lines(groups[j]) / 2 > total / 2) return Math.max(1, j)
      taken += lines(groups[j])
    }
    return groups.length
  }
  readonly property int columnWidth: (width - inset - columns.spacing) / 2
  // Reads keyMetrics.font so a new font or text size measures again.
  readonly property int keyWidth: {
    var font = keyMetrics.font
    var widest = 0
    for (var g = 0; g < groups.length; g++)
      for (var r = 0; r < groups[g].rows.length; r++) widest = Math.max(widest, Math.ceil(keyMetrics.advanceWidth(groups[g].rows[r].key)))
    return widest
  }
  FontMetrics { id: keyMetrics; font.family: root.look.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }

  contentWidth: width
  contentHeight: sheetColumn.y + sheetColumn.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  interactive: contentHeight > height
  // While more of the sheet is out of sight the scrollbar says so, at rest too.
  Controls.ScrollBar.vertical: ViewScrollBar { scrolls: root.interactive }

  component Group: Column {
    id: group
    required property var modelData
    spacing: Style.space(4)

    PanelSectionHeader {
      text: group.modelData.title
      foreground: root.look.foreground
      fontFamily: root.look.fontFamily
    }

    Repeater {
      model: group.modelData.rows

      Row {
        id: helpRow
        required property var modelData
        width: group.width
        spacing: Style.space(10)

        Text {
          width: root.keyWidth
          textFormat: Text.PlainText
          text: helpRow.modelData.key
          color: root.look.foreground
          font.family: root.look.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
        Text {
          width: parent.width - root.keyWidth - parent.spacing
          textFormat: Text.PlainText
          text: helpRow.modelData.does
          color: root.look.dim
          font.family: root.look.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  Column {
    id: sheetColumn
    x: root.inset
    y: Style.space(4)
    width: root.width - root.inset
    spacing: Style.space(16)

    Row {
      id: columns
      spacing: Style.space(24)

      Repeater {
        model: [root.groups.slice(0, root.split), root.groups.slice(root.split)]

        Column {
          id: sheetSide
          required property var modelData
          required property int index
          width: root.columnWidth
          spacing: Style.space(16)

          Repeater {
            model: sheetSide.modelData
            delegate: Group { width: root.columnWidth }
          }

          Text {
            objectName: "helpCredit"
            // The credit closes the second column, so a window of ordinary
            // height shows it without a scroll.
            visible: sheetSide.index === 1
            width: root.columnWidth - root.edge
            textFormat: Text.PlainText
            text: root.credit
            color: root.look.dim
            font.family: root.look.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }

    Button {
      anchors.right: parent.right
      anchors.rightMargin: root.edge
      bordered: true
      radius: root.look.retro ? 0 : Style.cornerRadius
      foreground: root.look.foreground
      fontFamily: root.look.fontFamily
      fontSize: Style.font.bodySmall
      text: "Close"
      onClicked: root.closeRequested()
    }
  }
}
