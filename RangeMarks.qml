pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Tones.js" as Tones

// A range's own high and low on its chart (`History.rangeMarks`): the price
// bright and the date dim, the high on the top edge and the low on the bottom,
// in the line's headroom, each over its bar and turned toward the middle.
// `chart` is the look on show, which says where it draws a bar, how far its
// ink has drawn in, and how high its ink reaches under a mark. A mark that
// would touch the ink lifts off the edge by up to `lift`, else is left out.
// It lies in the chart's `underScrub`, so a scrub's line and dot pass over it
// and it never moves while you scrub.
Item {
  id: root

  property var marks: null
  property var chart: null
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  // The shell's text size and spacing, or the picture's own in the screenshot,
  // which no text size moves.
  property real fontSize: Style.font.caption
  property real letterSpacing: 1
  property real spacing: Style.effectiveSpacingScale
  readonly property real lift: root.space(4)

  // `n` of the panel's pixels at text size 12, as `Style.space` rounds them.
  function space(n) { return Math.max(1, Math.round(n * root.spacing)) }

  // The chart's draw-in uncovers the marks with its ink, the room a mark lifts
  // into included.
  Item {
    y: -root.lift
    width: root.chart ? Math.min(root.width, root.chart.inkDrawn) : 0
    height: root.height + root.lift * 2
    clip: true

    Repeater {
      model: root.marks && root.chart ? [root.marks.high, root.marks.low] : []

      Item {
        id: mark
        required property var modelData
        required property int index
        readonly property real at: root.chart.xAt(mark.modelData.x)
        readonly property real gap: root.space(6)
        // How far its words' ink would reach into the chart's ink under them.
        // A price's thousands commas reach below the baseline.
        readonly property real overlap: Math.max(mark.overlapOf(0, priceText, priceInk), mark.overlapOf(dateText.x, dateText, dateInk), 0)
        objectName: index === 0 ? "highMark" : "lowMark"
        visible: mark.overlap <= root.lift
        width: priceText.implicitWidth + mark.gap + dateText.implicitWidth
        height: Math.max(priceText.implicitHeight, dateText.implicitHeight)
        x: Math.max(0, Math.min(root.width - mark.width,
          mark.modelData.x < 0.5 ? mark.at - root.space(2) : mark.at - mark.width + root.space(2)))
        y: root.lift + (mark.index === 0 ? -Math.min(mark.overlap, root.lift)
          : root.height - mark.height + Math.min(mark.overlap, root.lift))

        function overlapOf(left, word, ink) {
          var under = root.chart.inkExtentIn(mark.x + left, mark.x + left + word.implicitWidth)
          var top = word.baselineOffset + ink.tightBoundingRect.y
          return mark.index === 0 ? top + ink.tightBoundingRect.height - under.top
            : under.bottom - (root.height - mark.height + top)
        }

        TextMetrics { id: priceInk; font: priceText.font; text: priceText.text }
        TextMetrics { id: dateInk; font: dateText.font; text: dateText.text }

        Text {
          id: priceText
          objectName: "markPrice"
          textFormat: Text.PlainText
          text: mark.modelData.price
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
          font.bold: true
        }
        Text {
          id: dateText
          objectName: "markDate"
          x: priceText.implicitWidth + mark.gap
          textFormat: Text.PlainText
          text: mark.modelData.date
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: root.fontSize
          font.bold: true
          font.letterSpacing: root.letterSpacing
        }
      }
    }
  }
}
