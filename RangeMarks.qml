pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Tones.js" as Tones

// A range's own high and low, marked on its chart (`History.rangeMarks`):
// the price bright and the date dim, the high on the chart's top edge and
// the low on its bottom, where the line's headroom keeps them clear of the
// ink. Each stands over its bar and is turned toward the chart's middle, so
// it stays on the chart. `chart` is the look on show: where it draws a bar
// (`xAt`, retro's on its bar's column), and how far its ink has drawn in
// (`inkDrawn`), so a mark draws in with the line.
Item {
  id: root

  property var marks: null
  property var chart: null
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family

  Repeater {
    model: root.marks && root.chart ? [root.marks.high, root.marks.low] : []

    Row {
      id: mark
      required property var modelData
      required property int index
      readonly property real at: root.chart.xAt(mark.modelData.x)
      objectName: index === 0 ? "highMark" : "lowMark"
      visible: mark.at <= root.chart.inkDrawn
      spacing: Style.space(6)
      x: Math.max(0, Math.min(root.width - mark.width,
        mark.modelData.x < 0.5 ? mark.at - Style.space(2) : mark.at - mark.width + Style.space(2)))
      y: mark.index === 0 ? 0 : root.height - mark.height

      Text {
        textFormat: Text.PlainText
        text: mark.modelData.price
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        textFormat: Text.PlainText
        text: mark.modelData.date
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1
      }
    }
  }
}
