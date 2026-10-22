pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Tones.js" as Tones

// A range's own high and low, marked on its chart (`History.rangeMarks`):
// the price bright and the date dim, the high on the chart's top edge and
// the low on its bottom, in the line's headroom. Each stands over its bar
// and is turned toward the chart's middle, so it stays on the chart.
// `chart` is the look on show: where it draws a bar (`xAt`, retro's on its
// bar's column), how far its ink has drawn in (`inkDrawn`), so a mark draws
// in with the line, and where the ink reaches (`inkExtent`). A mark whose
// words would touch the ink, on a chart squeezed short, is left out whole.
Item {
  id: root

  property var marks: null
  property var chart: null
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family

  FontMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  Repeater {
    model: root.marks && root.chart ? [root.marks.high, root.marks.low] : []

    Row {
      id: mark
      required property var modelData
      required property int index
      readonly property real at: root.chart.xAt(mark.modelData.x)
      // Its words' ink, from the capitals' top to the baseline: digits and
      // capitals have nothing below it.
      readonly property bool clear: mark.index === 0
        ? mark.y + priceText.baselineOffset <= root.chart.inkExtent.top
        : mark.y + priceText.baselineOffset - metrics.capitalHeight >= root.chart.inkExtent.bottom
      objectName: index === 0 ? "highMark" : "lowMark"
      visible: mark.clear && mark.at <= root.chart.inkDrawn
      spacing: Style.space(6)
      x: Math.max(0, Math.min(root.width - mark.width,
        mark.modelData.x < 0.5 ? mark.at - Style.space(2) : mark.at - mark.width + Style.space(2)))
      y: mark.index === 0 ? 0 : root.height - mark.height

      Text {
        id: priceText
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
