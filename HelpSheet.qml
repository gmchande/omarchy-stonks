pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "Tones.js" as Tones

// Shortcut sheet, the same on both surfaces: the key groups in two columns,
// the mouse's lines across both under them, and its close button last.
// One column left half the window empty and pushed the last group below the
// fold. The two columns stack independently, groups in order, the first
// taking groups until it holds about half the lines, so a short group never
// sits beside a long one with a hole under it.
Flickable {
  id: root

  // KeySheet.sheet: { groups, mouse, note }.
  property var sheet: ({ groups: [], mouse: null, note: "" })
  property color foreground: Color.foreground
  property color dim: Tones.dim(foreground, Color.background)
  property string fontFamily: Style.font.family
  property bool retro: false
  // The words start at the rows' inset (`inset`), and CLOSE ends where the
  // rows' figures do, one gutter and an inset short of the right (`edge`):
  // the sheet clips at its edges, so CLOSE's fill reaching past its word
  // stays whole. What each key does may run on past that edge, as wrapped
  // words do, rather than break a line in the popup.
  property int inset: 0
  property int edge: 0

  signal closeRequested()

  readonly property var groups: sheet.groups
  // How many groups the first column takes.
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
  // The key column, as wide as the widest key or gesture, so what each
  // does keeps the room a popup's half column has.
  readonly property int keyWidth: {
    var widest = 0
    var all = groups.concat(sheet.mouse ? [sheet.mouse] : [])
    for (var g = 0; g < all.length; g++)
      for (var r = 0; r < all[g].rows.length; r++) widest = Math.max(widest, Math.ceil(keyMetrics.advanceWidth(all[g].rows[r].key)))
    return widest
  }
  FontMetrics { id: keyMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }

  contentWidth: width
  contentHeight: sheetColumn.y + sheetColumn.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  interactive: contentHeight > height

  // One group: its title, then a line per entry, the key bold and what it
  // does dim. `keyName` tells the keys from the mouse's gestures.
  component Group: Column {
    id: group
    required property var modelData
    property string keyName: "helpKey"
    spacing: Style.space(4)

    PanelSectionHeader {
      text: group.modelData.title
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Repeater {
      model: group.modelData.rows

      Row {
        id: helpRow
        required property var modelData
        width: group.width
        spacing: Style.space(10)

        Text {
          objectName: group.keyName
          width: root.keyWidth
          textFormat: Text.PlainText
          text: helpRow.modelData.key
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
        Text {
          width: parent.width - root.keyWidth - parent.spacing
          textFormat: Text.PlainText
          text: helpRow.modelData.does
          color: root.dim
          font.family: root.fontFamily
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
          required property var modelData
          width: root.columnWidth
          spacing: Style.space(16)

          Repeater {
            model: parent.modelData
            delegate: Group { width: root.columnWidth }
          }
        }
      }
    }

    Repeater {
      model: root.sheet.mouse ? [root.sheet.mouse] : []
      delegate: Group { width: sheetColumn.width; keyName: "helpGesture" }
    }

    Item {
      width: sheetColumn.width
      height: Math.max(note.implicitHeight, close.implicitHeight)

      Text {
        id: note
        objectName: "helpNote"
        anchors.left: parent.left
        anchors.right: close.left
        anchors.rightMargin: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.sheet.note
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      // Escape, as a button.
      ListAction {
        id: close
        objectName: "helpClose"
        view: root
        anchors.right: parent.right
        anchors.rightMargin: root.edge
        anchors.verticalCenter: parent.verticalCenter
        text: "CLOSE"
        onActivated: root.closeRequested()
      }
    }
  }
}
