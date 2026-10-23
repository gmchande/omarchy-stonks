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
// (`inkExtentIn`). A mark whose words would touch that ink moves off its
// edge, into the band's gap, by as much as `lift`; one that would need
// more, as on a chart squeezed short, is left out whole. While the scrub's
// line (`scrubX`, the scrub's place along the chart, 0..1, or -1) crosses a
// mark's date, the date stands on the price's other side, or, with no room
// there, a date's width on, clear of the line, where it touches no more ink
// than at rest; the price stays where it is. Found in the overnight QA of
// 23 October: AAPL's 1Y scrub ran through "20│JAN 2026"; and then, in the
// check of that night's fixes, hiding the whole mark instead hid the
// year's high while you scrubbed toward it.
Item {
  id: root

  property var marks: null
  property var chart: null
  property real scrubX: -1
  property color foreground: Commons.Color.foreground
  property color dim: Tones.dim(foreground, Commons.Color.background)
  property string fontFamily: Style.font.family
  readonly property real lift: Style.space(4)
  // Where the scrub's line stands, in this item's pixels, -1 without one.
  readonly property real scrubAt: root.chart && root.scrubX >= 0 ? root.chart.xAt(root.scrubX) : -1

  // The marks draw in with the line: the chart's draw-in uncovers them as
  // it uncovers its ink, the room a mark lifts into included.
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
        readonly property real gap: Style.space(6)
        // The date's place at rest, after the price.
        readonly property real restDateX: priceText.implicitWidth + mark.gap
        // How far its words' ink, as drawn at rest, would reach into the
        // chart's ink under each of them, with the mark on its edge: down
        // into it for the high, up into it for the low. A price's thousands
        // commas reach below the baseline.
        readonly property real overlap: Math.max(mark.overlapOf(0, priceText, priceInk), mark.overlapOf(mark.restDateX, dateText, dateInk), 0)
        readonly property bool dateCrossed: root.scrubAt >= 0 && root.scrubAt >= mark.x + mark.restDateX - Style.space(4)
          && root.scrubAt <= mark.x + mark.restDateX + dateText.implicitWidth + Style.space(4)
        readonly property real beforeX: -mark.gap - dateText.implicitWidth
        readonly property real onX: mark.restDateX + dateText.implicitWidth + mark.gap
        readonly property real dateX: !mark.dateCrossed ? mark.restDateX
          : mark.dateFits(mark.beforeX) ? mark.beforeX : mark.dateFits(mark.onX) ? mark.onX : mark.restDateX
        objectName: index === 0 ? "highMark" : "lowMark"
        visible: mark.overlap <= root.lift
        width: mark.restDateX + dateText.implicitWidth
        height: Math.max(priceText.implicitHeight, dateText.implicitHeight)
        x: Math.max(0, Math.min(root.width - mark.width,
          mark.modelData.x < 0.5 ? mark.at - Style.space(2) : mark.at - mark.width + Style.space(2)))
        y: root.lift + (mark.index === 0 ? -Math.min(mark.overlap, root.lift)
          : root.height - mark.height + Math.min(mark.overlap, root.lift))

        // The word at `left` in the mark: how far its ink reaches into the
        // chart's.
        function overlapOf(left, word, ink) {
          var under = root.chart.inkExtentIn(mark.x + left, mark.x + left + word.implicitWidth)
          var top = word.baselineOffset + ink.tightBoundingRect.y
          return mark.index === 0 ? top + ink.tightBoundingRect.height - under.top
            : under.bottom - (root.height - mark.height + top)
        }
        // The date can stand at `left` in the mark: on the chart, and on no
        // more of its ink than at rest.
        function dateFits(left) {
          return mark.x + left >= 0 && mark.x + left + dateText.implicitWidth <= root.width
            && mark.overlapOf(left, dateText, dateInk) <= mark.overlap
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
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Text {
          id: dateText
          objectName: "markDate"
          x: mark.dateX
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
}
