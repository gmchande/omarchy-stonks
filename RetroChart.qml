pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Tones.js" as Tones
import "Motion.js" as Motion
import "Chart.js" as Chart
// The retro chart, one rule for the day and every range: columns of cells
// fill from the baseline row, in the up colour above it and the down colour
// below, each by its own price's side of the close, as smooth's line is. The
// day adds dimmer hours, the bell and the night's edges, and the lit last
// trade. Once tonight has traded, the baseline steps at the bell to
// the close just gone (`geometry.step`), and the columns from there stand on
// it. The grid and the columns paint when the data changes; the draw-in
// widens a clip a whole column at a time, and the ticks and the scrub are
// cells laid over them.
Item {
  id: root

  property var geometry: null
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property color baselineColor: Tones.dimmer(Commons.Color.foreground, Commons.Color.background)
  property var up: true
  // Lights the last regular trade's cap. Off for small copies, and a range
  // has none: its last bar need not be the headline trade.
  property bool glow: false
  // The cap blinks while the market trades, white, colour, white, as a sprite
  // does: four blinks, about 6 s, as a new price arrives or the surface opens,
  // as the smooth dot ripples, then it rests.
  property bool live: false
  property string newestPrice: ""
  property bool surfaceOpen: true
  // Closing: the live mark stops where it is, and blinks again as the surface
  // opens.
  property bool still: false
  property color hairlineColor: Commons.Color.foreground
  // The unlit cells, as an LCD shows every segment faintly.
  property color ghostColor: "transparent"
  // A cell and the seam after it, in window units, or in pixels of the
  // picture on a screen of any scale (`ShareCard`).
  property real pixel: 5
  property real gap: 1
  // 0..1 along the axis, or -1 when not scrubbing.
  property real scrubX: -1
  // The grid and the baseline are always there; the columns fill in from the
  // left to the newest trade's.
  property real reveal: 1
  // A replay's place, 0..1, or -1 without one: the columns fill in behind it.
  property real replayX: -1
  // The surface under the chart, which the stems are seen against.
  property color ground: Commons.Color.background
  // The ticks at the bells. A row's copy leaves them out, as its smooth line
  // does: on a few rows of cells they stand as tall as its prices.
  property bool bells: true

  readonly property var grid: Chart.retroGrid(geometry, width, height, pixel, gap)
  readonly property bool day: !!geometry && geometry.day === true
  readonly property bool directionKnown: typeof up === "boolean"
  readonly property color aboveColor: directionKnown ? upColor : baselineColor
  readonly property color belowColor: directionKnown ? downColor : baselineColor
  readonly property bool drawable: Chart.drawable(geometry)
  readonly property bool hasBaseline: Chart.hasBaseline(geometry)
  // Through the newest trade's column.
  readonly property int inkColumns: drawable
    ? Math.min(grid.columns, Math.floor(geometry.points[geometry.points.length - 1].x * grid.columns) + 1) : 0
  readonly property int scrubColumn: scrubX >= 0 ? Chart.retroColumn(grid, scrubX) : -1
  // What is laid over the ink draws in with it (`RangeMarks`).
  readonly property real inkDrawn: replayX < 0 && reveal >= 1 ? width : curtain.width
  // The stems are retro's wash: each side adds the lightness the up colour's
  // does at 35% (`Tones.washAlpha`), less under a dim cap. `solid` draws each
  // stem at its cap's ink, for a chart so small that faint stems leave the
  // caps a dotted line: the pill's, 13 columns at 1x.
  property bool solid: false
  readonly property real aboveStem: solid ? 1 : Tones.washAlpha(aboveColor, upColor, ground, 0.35, 1)
  readonly property real belowStem: solid ? 1 : Tones.washAlpha(belowColor, upColor, ground, 0.35, 1)
  readonly property real aboveStemDim: solid ? 0.45 : Tones.washAlpha(aboveColor, upColor, ground, 0.35 * 0.45, 0.45)
  readonly property real belowStemDim: solid ? 0.45 : Tones.washAlpha(belowColor, upColor, ground, 0.35 * 0.45, 0.45)

  onGridChanged: { base.requestPaint(); ink.requestPaint() }
  onBaselineColorChanged: base.requestPaint()
  onGhostColorChanged: base.requestPaint()
  onAboveColorChanged: ink.requestPaint()
  onBelowColorChanged: ink.requestPaint()
  onAboveStemChanged: ink.requestPaint()
  onBelowStemChanged: ink.requestPaint()
  onAboveStemDimChanged: ink.requestPaint()
  onBelowStemDimChanged: ink.requestPaint()

  function baseRowAt(g, c) {
    return Chart.retroBaseRow(g, c)
  }

  // How far along the columns `x` is: they end short of the chart's width
  // where it holds no whole number of them. The start's own column reads
  // the start.
  function fractionAt(x) {
    return grid.ownStart && x < grid.pitch ? 0 : x / (grid.columns * grid.pitch)
  }

  // The column a point at `fraction` stands in (`Chart.retroColumn`).
  function columnAt(fraction) {
    return Chart.retroColumn(grid, fraction)
  }

  // The centre of the column `layout` puts it in.
  function xAt(fraction) {
    return columnAt(fraction) * grid.pitch + pixel / 2
  }

  // The lit rows of the columns between `x0` and `x1`, and the baselines'.
  // What is laid over the chart keeps clear of it (`RangeMarks`).
  function inkExtentIn(x0, x1) {
    var g = grid
    var rows = (hasBaseline ? [g.baseRow] : []).concat(g.stepCol < g.columns ? [g.stepRow] : [])
    var last = Math.min(g.columns - 1, Math.floor(x1 / g.pitch))
    for (var c = Math.max(0, Math.floor(x0 / g.pitch)); c <= last; c++) {
      if (g.levels[c] !== undefined) rows.push(g.levels[c])
    }
    if (!rows.length) return { top: height, bottom: 0 }
    return { top: Math.min.apply(null, rows) * pixel, bottom: (Math.max.apply(null, rows) + 1) * pixel }
  }

  Canvas {
    id: base
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var g = root.grid
      var pixel = root.pixel
      if (root.ghostColor.a > 0) {
        ctx.fillStyle = root.ghostColor
        for (var gc = 0; gc < g.columns; gc++) {
          for (var gr = 0; gr < g.rows; gr++) ctx.fillRect(gc * g.pitch, gr * pixel, pixel, pixel - root.gap)
        }
      }
      if (!root.hasBaseline && g.stepCol >= g.columns) return
      // Every other cell, so it lives on the bars' grid, not as a hairline
      // across them.
      ctx.fillStyle = root.baselineColor
      for (var bc = 0; bc < g.columns; bc += 2)
        if (root.hasBaseline || bc >= g.stepCol) ctx.fillRect(bc * g.pitch, root.baseRowAt(g, bc) * pixel, pixel, pixel - root.gap)
    }
  }

  // A replay that has left the start reveals the column after it, where
  // every later point stands (`Chart.retroColumn`).
  Item {
    id: curtain
    width: (root.replayX >= 0 ? Math.max(Math.ceil(root.grid.columns * Math.min(1, root.replayX)), root.grid.ownStart ? Chart.retroColumn(root.grid, root.replayX) + 1 : 0)
      : root.reveal >= 1 ? root.grid.columns : Math.ceil(root.inkColumns * Math.max(0, root.reveal))) * root.grid.pitch
    height: root.height
    clip: true

    Canvas {
      id: ink
      objectName: "ink"
      width: root.width
      height: root.height
      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!root.drawable) return
        var g = root.grid
        var pixel = root.pixel
        for (var c = 0; c < g.columns; c++) {
          if (g.levels[c] === undefined) continue
          var baseRow = root.baseRowAt(g, c)
          var baseY = baseRow * pixel
          var y = g.levels[c] * pixel
          var above = g.above[c]
          // With no line under it, a column takes the baseline's ink.
          var color = !root.hasBaseline && c < g.stepCol ? root.baselineColor : above ? root.aboveColor : root.belowColor
          var dim = g.dim[c] ? 0.45 : 1
          var x = c * g.pitch
          var top = Math.min(y, baseY)
          var h = Math.abs(y - baseY)
          if (h > 0) {
            var stem = g.dim[c] ? (above ? root.aboveStemDim : root.belowStemDim) : (above ? root.aboveStem : root.belowStem)
            ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, stem)
            ctx.fillRect(x, top, pixel, h)
          }
          ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, dim)
          ctx.fillRect(x, y, pixel, pixel)
        }
      }
    }
  }

  // The ticks, cut at the chart's edges as a canvas cuts: on the pill's six
  // rows a baseline on the top or bottom row would put a cell outside it.
  // Those the columns have reached draw in with them; those ahead, in hours
  // still to come, are there with the baseline. The bell's stays on the
  // day's row.
  Repeater {
    model: root.bells && root.hasBaseline ? root.geometry.ticks.length : 0

    Rectangle {
      required property int index
      readonly property int column: Math.min(root.grid.columns - 1, Math.floor(root.geometry.ticks[index] * root.grid.columns))
      readonly property int row: column > root.grid.stepCol ? root.grid.stepRow : root.grid.baseRow
      readonly property real cellTop: Math.max(0, (row - 1) * root.pixel)
      visible: column >= root.inkColumns || column * root.grid.pitch < curtain.width
      x: column * root.grid.pitch
      y: cellTop
      width: root.pixel
      height: Math.min(root.height, (row + 2) * root.pixel) - cellTop
      color: root.baselineColor
    }
  }

  // What is laid over the ink but under the scrub's line and dot
  // (`RangeMarks`).
  readonly property Item underScrub: underScrubLayer
  Item {
    id: underScrubLayer
    anchors.fill: parent
  }

  Rectangle {
    visible: root.drawable && root.scrubColumn >= 0
    x: root.scrubColumn * root.grid.pitch
    width: root.pixel
    height: root.height
    color: Util.alpha(root.hairlineColor, 0.3)
  }

  Rectangle {
    visible: root.drawable && root.scrubColumn >= 0 && root.grid.levels[root.scrubColumn] !== undefined
    x: root.scrubColumn * root.grid.pitch
    y: visible ? root.grid.levels[root.scrubColumn] * root.pixel : 0
    width: root.pixel
    height: root.pixel
    color: root.hairlineColor
  }

  // The pixel version of the smooth chart's live dot, once the day has drawn
  // in: four blinks, white, colour, white, when the mark plays (`LiveMark`).
  Rectangle {
    id: cap
    objectName: "liveCap"
    visible: root.glow && root.day && root.grid.lastLit >= 0 && root.reveal >= 1 && root.replayX < 0
    x: root.grid.lastLit * root.grid.pitch
    y: visible ? root.grid.levels[root.grid.lastLit] * root.pixel : 0
    width: root.pixel
    height: root.pixel
    color: root.hairlineColor

    SequentialAnimation {
      id: blinks
      paused: running && root.still
      loops: 4
      onRunningChanged: if (!running) cap.opacity = 1

      PropertyAction { target: cap; property: "opacity"; value: 1 }
      PauseAnimation { duration: Motion.duration(Style, 700) }
      PropertyAction { target: cap; property: "opacity"; value: 0.5 }
      PauseAnimation { duration: Motion.duration(Style, 160) }
      PropertyAction { target: cap; property: "opacity"; value: 0 }
      PauseAnimation { duration: Motion.duration(Style, 480) }
      PropertyAction { target: cap; property: "opacity"; value: 0.5 }
      PauseAnimation { duration: Motion.duration(Style, 160) }
    }
  }

  LiveMark {
    live: root.live
    still: root.still
    shown: cap.visible
    drawing: function() { return root.reveal < 1 }
    surfaceOpen: root.surfaceOpen
    price: root.newestPrice
    burst: blinks
  }
}
