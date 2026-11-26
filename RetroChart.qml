pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Tones.js" as Tones
import "Motion.js" as Motion
import "Chart.js" as Chart
import "Morph.js" as Morph
// The retro chart, one rule for the day and every range: columns of cells
// fill from the baseline row, in the up colour above it and the down colour
// below, each by its own price's side of the close, as smooth's line is. The
// day draws lighter hours, and adds the bell and the night's edges, and the
// lit last trade. Once tonight has traded, what the number beside the chart
// doesn't count (`geometry.aside`) draws fainter, its stems every other
// cell. The unlit cells paint when the size changes, the baseline and the
// columns when the data changes; the draw-in widens a clip a whole column at a
// time, and the ticks and the scrub are cells laid over them. Another chart
// takes over from the one before (`morphFrom`, `morph`) a column at a time
// from the left, each column with its own dashed row (`Morph.wave`).
Item {
  id: root

  property var geometry: null
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property color baselineColor: Tones.dimmer(Commons.Color.foreground, Commons.Color.background)
  // What the number beside the chart doesn't count (`geometry.aside`) stands
  // on the dashed line too, at a fainter share than the dim hours', and with
  // every other cell of its stems: fainter alone, it runs into tonight's dim
  // hours on a dark ground. With `greyAside`, as on a row, whose counted day
  // is already dim, it takes `greyColor`, a step stronger than the
  // baseline's ink, its caps whole: at a fainter share they'd read as the
  // baseline's.
  property bool greyAside: false
  property color greyColor: Tones.dim(Commons.Color.foreground, ground)
  readonly property real asideShare: greyAside ? 0.45 : 0.4
  readonly property real asideInk: greyAside ? 1 : asideShare
  property var up: true
  // Lights the last regular trade's cap. Off for small copies, and a range
  // has none: its last bar need not be the headline trade.
  property bool glow: false
  // The panel's and the screenshot's day keep the session full at any hour
  // and draw the hours around it lighter (`faint`); a row's lights what
  // trades now (`dim`). Once the closed day is set apart the two agree.
  property bool fullSession: false
  readonly property bool even: fullSession && day && !geometry.aside
  // The hours around the session, on a day not set apart: lighter than the
  // session, and still its green or red on a dark ground.
  readonly property real hoursInk: 0.6
  readonly property real lighterInk: even ? hoursInk : 0.45
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
  // The chart this one takes over from, and how far in time it has come, 0
  // to 1: the columns come at an even pace, so every frame takes some.
  property var morphFrom: null
  property real morph: 1
  // A replay's place, 0..1, or -1 without one: the columns fill in behind it.
  property real replayX: -1
  // The surface under the chart, which the stems are seen against.
  property color ground: Commons.Color.background
  // The ticks at the bells. A row's copy leaves them out, as its smooth line
  // does: on a few rows of cells they stand as tall as its prices.
  property bool bells: true

  readonly property var grid: Chart.retroGrid(geometry, width, height, pixel, gap)
  // The grid this one takes over from: a change that comes mid-wave goes on
  // from the columns on screen.
  property var fromGrid: null
  property var lastGrid: null
  onMorphFromChanged: fromGrid = !morphFrom ? null
    : morph < 1 && lastGrid ? lastGrid : Chart.retroGrid(morphFrom, width, height, pixel, gap)
  // The columns the new chart has taken, a whole number, so a frame that
  // takes none paints nothing.
  readonly property int front: fromGrid && morph < 1 ? Math.floor(morph * grid.columns) : grid.columns
  readonly property var shownGrid: fromGrid && front < grid.columns ? Morph.wave(fromGrid, grid, front) : grid
  readonly property bool day: !!geometry && geometry.day === true
  readonly property bool directionKnown: typeof up === "boolean"
  readonly property color aboveColor: directionKnown ? upColor : baselineColor
  readonly property color belowColor: directionKnown ? downColor : baselineColor
  readonly property bool drawable: Chart.drawable(geometry)
  readonly property bool hasBaseline: Chart.hasBaseline(geometry)
  // Through the newest trade's column.
  readonly property int inkColumns: drawable
    ? Math.min(grid.columns, Math.floor(geometry.points[geometry.points.length - 1].x * grid.columns) + 1) : 0
  // The first trade's column, where the draw-in starts.
  readonly property int firstColumn: drawable ? Chart.retroColumn(grid, geometry.points[0].x) : 0
  readonly property int scrubColumn: scrubX >= 0 ? Chart.retroColumn(grid, scrubX) : -1
  // What is laid over the ink draws in with it (`RangeMarks`).
  readonly property real inkDrawn: replayX < 0 && reveal >= 1 ? width : curtain.width
  // What is laid over the ink shows as a chart takes over, over the second
  // half (`RangeMarks`).
  readonly property real marksShown: Math.max(0, Math.min(1, morph * 2 - 1))
  // The stems are retro's wash: each side adds the lightness the up colour's
  // does at 35% (`Tones.washAlpha`), less under a lighter cap. `solid` draws each
  // stem at its cap's ink, for a chart so small that faint stems leave the
  // caps a dotted line: the pill's, 13 columns at 1x.
  property bool solid: false
  readonly property real aboveStem: solid ? 1 : Tones.washAlpha(aboveColor, upColor, ground, 0.35, 1)
  readonly property real belowStem: solid ? 1 : Tones.washAlpha(belowColor, upColor, ground, 0.35, 1)
  readonly property real aboveStemDim: solid ? lighterInk : Tones.washAlpha(aboveColor, upColor, ground, 0.35 * lighterInk, lighterInk)
  readonly property real belowStemDim: solid ? lighterInk : Tones.washAlpha(belowColor, upColor, ground, 0.35 * lighterInk, lighterInk)
  readonly property real aboveStemAside: Tones.washAlpha(greyAside ? greyColor : aboveColor, upColor, ground, 0.35 * asideShare, asideShare)
  readonly property real belowStemAside: Tones.washAlpha(greyAside ? greyColor : belowColor, upColor, ground, 0.35 * asideShare, asideShare)

  onShownGridChanged: { base.requestPaint(); ink.requestPaint() }
  onBaselineColorChanged: base.requestPaint()
  // The unlit cells change only with the chart's size, so a new price
  // repaints none of them.
  readonly property string ghostCells: ghostColor.a > 0 ? [grid.columns, grid.rows, pixel, gap].join(" ") : ""
  onGhostCellsChanged: ghost.requestPaint()
  onGhostColorChanged: ghost.requestPaint()
  onAboveColorChanged: ink.requestPaint()
  onBelowColorChanged: ink.requestPaint()
  onAboveStemChanged: ink.requestPaint()
  onBelowStemChanged: ink.requestPaint()
  onAboveStemDimChanged: ink.requestPaint()
  onBelowStemDimChanged: ink.requestPaint()
  onAboveStemAsideChanged: ink.requestPaint()
  onBelowStemAsideChanged: ink.requestPaint()
  onGreyColorChanged: ink.requestPaint()

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

  // The centre of the column `columnAt` puts it in.
  function xAt(fraction) {
    return columnAt(fraction) * grid.pitch + pixel / 2
  }

  // The lit rows of the columns between `x0` and `x1`, and the baselines'.
  // What is laid over the chart keeps clear of it (`RangeMarks`).
  function inkExtentIn(x0, x1) {
    var g = grid
    var rows = hasBaseline ? [g.baseRow] : []
    var last = Math.min(g.columns - 1, Math.floor(x1 / g.pitch))
    for (var c = Math.max(0, Math.floor(x0 / g.pitch)); c <= last; c++) {
      if (g.levels[c] !== undefined) rows.push(g.levels[c])
    }
    if (!rows.length) return { top: height, bottom: 0 }
    return { top: Math.min.apply(null, rows) * pixel, bottom: (Math.max.apply(null, rows) + 1) * pixel }
  }

  // One fill, then the seams between the cells cleared: a fill for each
  // cell is 72,000 of them on a big window.
  Canvas {
    id: ghost
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (root.ghostColor.a <= 0) return
      var g = root.grid
      var pixel = root.pixel
      var gap = root.gap
      var w = g.columns * g.pitch - gap
      var h = g.rows * pixel - gap
      ctx.fillStyle = root.ghostColor
      ctx.fillRect(0, 0, w, h)
      if (gap <= 0) return
      for (var c = 1; c < g.columns; c++) ctx.clearRect(c * g.pitch - gap, 0, gap, h)
      for (var r = 1; r < g.rows; r++) ctx.clearRect(0, r * pixel - gap, w, gap)
    }
  }

  Canvas {
    id: base
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var g = root.shownGrid
      var pixel = root.pixel
      if (!root.hasBaseline) return
      // Every other cell, so it lives on the bars' grid, not as a hairline
      // across them.
      ctx.fillStyle = root.baselineColor
      for (var bc = 0; bc < g.columns; bc += 2) ctx.fillRect(bc * g.pitch, (g.baseRows ? g.baseRows[bc] : g.baseRow) * pixel, pixel, pixel - root.gap)
    }
  }

  // A replay that has left the start reveals the column after it, where
  // every later point stands (`Chart.retroColumn`). The draw-in starts at the
  // first trade's column.
  Item {
    id: curtain
    width: (root.replayX >= 0 ? Math.max(Math.ceil(root.grid.columns * Math.min(1, root.replayX)), root.grid.ownStart ? Chart.retroColumn(root.grid, root.replayX) + 1 : 0)
      : root.reveal >= 1 ? root.grid.columns
      : root.firstColumn + Math.ceil((root.inkColumns - root.firstColumn) * Math.max(0, root.reveal))) * root.grid.pitch
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
        var g = root.shownGrid
        root.lastGrid = g
        var pixel = root.pixel
        var asideInk = root.asideInk
        for (var c = 0; c < g.columns; c++) {
          if (g.levels[c] === undefined) continue
          var baseRow = g.baseRows ? g.baseRows[c] : g.baseRow
          var baseY = baseRow * pixel
          var y = g.levels[c] * pixel
          var above = g.above[c]
          var aside = g.aside ? g.aside[c] : c >= g.asideFrom && c < g.asideTo
          // With no line under it, a column takes the baseline's ink.
          var color = aside && root.greyAside ? root.greyColor : !root.hasBaseline ? root.baselineColor : above ? root.aboveColor : root.belowColor
          var lighter = root.fullSession ? g.faint[c] : g.dim[c]
          var dim = aside ? asideInk : lighter ? root.lighterInk : 1
          var x = c * g.pitch
          // The stem fills the rows between the baseline's and the cap's, on
          // both sides alike, so equal moves stand equally long and the
          // baseline's dots show under every column. A `solid` chart has no
          // fainter stem for the aside, so its caps stand alone there.
          var top = Math.min(y, baseY) + pixel
          var h = Math.abs(y - baseY) - pixel
          if (h > 0 && !(aside && root.solid)) {
            var stem = aside ? (above ? root.aboveStemAside : root.belowStemAside)
              : lighter ? (above ? root.aboveStemDim : root.belowStemDim) : (above ? root.aboveStem : root.belowStem)
            ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, stem)
            if (aside) {
              // Every other cell from the one on the dashed line, so the
              // cells line up across columns.
              var step = y < baseY ? -1 : 1
              var far = Math.abs(g.levels[c] - baseRow)
              for (var k = 1; k < far; k += 2) ctx.fillRect(x, (baseRow + k * step) * pixel, pixel, pixel - root.gap)
            } else ctx.fillRect(x, top, pixel, h)
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
  // still to come, are there with the baseline. While a chart takes over,
  // each side of the wave has its own chart's.
  Repeater {
    model: root.bells && root.hasBaseline ? root.geometry.ticks.length : 0

    Rectangle {
      required property int index
      readonly property int column: Math.min(root.grid.columns - 1, Math.floor(root.geometry.ticks[index] * root.grid.columns))
      readonly property int row: root.grid.baseRow
      readonly property real cellTop: Math.max(0, (row - 1) * root.pixel)
      visible: column < root.front && (column >= root.inkColumns || column * root.grid.pitch < curtain.width)
      x: column * root.grid.pitch
      y: cellTop
      width: root.pixel
      height: Math.min(root.height, (row + 2) * root.pixel) - cellTop
      color: root.baselineColor
    }
  }

  Repeater {
    model: root.bells && root.fromGrid && Chart.hasBaseline(root.morphFrom) && root.front < root.grid.columns ? root.morphFrom.ticks.length : 0

    Rectangle {
      required property int index
      readonly property int column: Math.min(root.fromGrid.columns - 1, Math.floor(root.morphFrom.ticks[index] * root.fromGrid.columns))
      readonly property int row: root.fromGrid.baseRow
      readonly property real cellTop: Math.max(0, (row - 1) * root.pixel)
      visible: column >= root.front
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

  // The pixel version of the smooth chart's live dot, once the columns reach
  // it: four blinks, white, colour, white, when the mark plays (`LiveMark`).
  Rectangle {
    id: cap
    objectName: "liveCap"
    // At the open it lights halfway through the bell's beat (`bloom`).
    visible: root.glow && root.day && root.shownGrid.lastLit >= 0 && root.replayX < 0 && x < curtain.width && root.bloomed >= 0.5
    x: root.shownGrid.lastLit * root.grid.pitch
    y: visible ? root.shownGrid.levels[root.shownGrid.lastLit] * root.pixel : 0
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

  // How far the cap has come at the open's bell, 0 to 1 (`bloom`).
  property real bloomed: 1
  function bloom() {
    if (!surfaceOpen) return
    bloomAnim.restart()
  }
  NumberAnimation { id: bloomAnim; target: root; property: "bloomed"; from: 0; to: 1; duration: Motion.duration(Style, 320) }

  LiveMark {
    live: root.live
    still: root.still
    // The cap comes as the columns reach it; its blinks at the draw-in's end.
    shown: cap.visible && root.reveal >= 1
    drawing: function() { return root.reveal < 1 }
    surfaceOpen: root.surfaceOpen
    price: root.newestPrice
    burst: blinks
  }
}
