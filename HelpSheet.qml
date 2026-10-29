pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Tones.js" as Tones

// Shortcut sheet, the same on both surfaces: the key groups in two columns,
// a dim credit line (the version and where prices come from) closing the
// second, then the mouse's lines across both under them, and its close
// button.
// One column would leave half the window empty and push the last group
// below the fold. The two stack independently, groups in order, the first
// taking groups until it holds about half the lines, so a short group never
// sits beside a long one with a hole under it.
Flickable {
  id: root

  // KeySheet.sheet: { groups, mouse }.
  property var sheet: ({ groups: [], mouse: null })
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  property bool retro: false
  // The words start at the rows' inset (`inset`), and CLOSE ends where the
  // rows' figures do, one gutter and an inset short of the right (`edge`):
  // the sheet clips at its edges, so CLOSE's fill reaching past its word
  // stays whole. What each key does may run on past that edge, as wrapped
  // words do, rather than break a line in the panel.
  property int inset: 0
  property int edge: 0
  // Stonks' version, as the version watch read it from the manifest; ""
  // leaves it off the credit rather than show a blank.
  property string version: ""
  // One part a line, so a half column never breaks one mid-phrase.
  readonly property string credit: (version !== "" ? ["Stonks " + version] : [])
    .concat(["Prices from Yahoo", "Overnight from Robinhood"]).join("\n")

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
  // does keeps the room a panel's half column has. The binding reads
  // keyMetrics.font so a new font measures again: a text size changed while
  // the shell runs would otherwise run a key into its words.
  readonly property int keyWidth: {
    var font = keyMetrics.font
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
  // While more of the sheet sits out of sight, as in a short window, the
  // scrollbar says so, at rest too, in the gutter CLOSE ends short of.
  Controls.ScrollBar.vertical: Controls.ScrollBar {
    objectName: "helpScrollBar"
    policy: root.interactive ? Controls.ScrollBar.AlwaysOn : Controls.ScrollBar.AlwaysOff
    visible: root.interactive
    // At least 24 px long, so a long sheet's thumb is there to see and grab.
    minimumSize: Math.min(1, Style.space(24) / Math.max(1, availableHeight))
  }

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
          id: sheetSide
          required property var modelData
          required property int index
          width: root.columnWidth
          spacing: Style.space(16)

          Repeater {
            model: sheetSide.modelData
            delegate: Group { width: root.columnWidth }
          }

          // The credit closes the second column, in the room the first's
          // longer groups leave beside it, so a window of ordinary height
          // shows it without a scroll.
          Text {
            objectName: "helpCredit"
            visible: sheetSide.index === 1
            width: root.columnWidth - root.edge
            textFormat: Text.PlainText
            text: root.credit
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }

    Repeater {
      model: root.sheet.mouse ? [root.sheet.mouse] : []
      delegate: Group { width: sheetColumn.width; keyName: "helpGesture" }
    }

    // Escape, as a button.
    ListAction {
      id: close
      objectName: "helpClose"
      view: root
      anchors.right: parent.right
      anchors.rightMargin: root.edge
      text: "CLOSE"
      onActivated: root.closeRequested()
    }
  }
}
