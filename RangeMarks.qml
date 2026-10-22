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
// in with the line, and how high and low its ink reaches under a mark
// (`inkExtentIn`). A mark whose words would touch that ink, as on a chart
// squeezed short, is left out whole.
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
      // Each word's ink as drawn keeps clear of the chart's ink under it:
      // above it for the high, below it for the low. A price's thousands
      // commas reach below the baseline.
      readonly property bool clear: mark.clears(priceText, priceInk) && mark.clears(dateText, dateInk)
      objectName: index === 0 ? "highMark" : "lowMark"
      visible: mark.clear && mark.at <= root.chart.inkDrawn
      spacing: Style.space(6)
      x: Math.max(0, Math.min(root.width - mark.width,
        mark.modelData.x < 0.5 ? mark.at - Style.space(2) : mark.at - mark.width + Style.space(2)))
      y: mark.index === 0 ? 0 : root.height - mark.height

      function clears(word, ink) {
        var under = root.chart.inkExtentIn(mark.x + word.x, mark.x + word.x + word.width)
        var top = mark.y + word.baselineOffset + ink.tightBoundingRect.y
        return mark.index === 0 ? top + ink.tightBoundingRect.height <= under.top : top >= under.bottom
      }

      TextMetrics { id: priceInk; font: priceText.font; text: priceText.text }
      TextMetrics { id: dateInk; font: dateText.font; text: dateText.text }

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
        id: dateText
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
