pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import "Tones.js" as Tones
// The retro chart, one rule for the day and every range: pixel columns fill
// from the baseline row, the previous close or the period's starting price,
// in the up colour above it and the down colour below. The day adds the
// dimmer extended hours, the bell and the night's edges, the lit last
// print, and a thin night's trades, each a lone cell with no column under it.
// The grid and the lit columns are painted when the data changes; the
// draw-in widens a clip over the columns a whole column at a time, and the
// bell and the scrub are cells laid over them.
Item {
  id: root

  property var geometry: null
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property color baselineColor: Tones.dimmer(Commons.Color.foreground, Commons.Color.background)
  property var up: true
  // Light the last regular print's cap white. Off for small copies, and a
  // range has none: its last bar need not be the headline print.
  property bool glow: false
  // Twinkle that cap while the market trades: white, colour, white, in
  // steps, the way a sprite blinks; four blinks, about 6 s, as a new price
  // arrives (`newestPrice`, the newest print's) or the surface opens, as the
  // smooth dot ripples, then it rests, shown and still.
  property bool live: false
  property string newestPrice: ""
  property bool surfaceOpen: true
  // A closing surface: the live mark stops where it is, as the rest of the
  // surface does; it blinks again as the surface opens.
  property bool still: false
  property color hairlineColor: Commons.Color.foreground
  // The unlit cells of the display, the way an LCD shows every segment
  // faintly. Transparent draws none.
  property color ghostColor: "transparent"
  // A cell and the seam after it, in window units: whole pixels of the
  // screen, or of the picture on a screen of any scale (`ShareCard`).
  property real pixel: 5
  property real gap: 1
  // 0..1 along the axis, or -1 when not scrubbing.
  property real scrubX: -1
  // How much of the ink has been drawn, 0..1. The grid and baseline are
  // always there; the lit columns fill in from the left edge to the newest
  // drawn print's, and at 1 the whole chart shows.
  property real reveal: 1
  // A replay's place along the plot, 0..1, or -1 without one: the columns
  // fill in behind it, whole columns of the plot.
  property real replayX: -1
  // The surface under the chart, which the stems are seen against.
  property color ground: Commons.Color.background

  // The grid the day is drawn on, shared by the paint and the cap overlay.
  readonly property var grid: layout()
  readonly property bool day: !!geometry && geometry.day === true
  readonly property bool directionKnown: typeof up === "boolean"
  readonly property color aboveColor: directionKnown ? upColor : baselineColor
  readonly property color belowColor: directionKnown ? downColor : baselineColor
  // One print draws: the first print after midnight is a cell on its day.
  readonly property bool drawable: !!geometry && !!geometry.points && geometry.points.length >= 1
  // The baseline draws with no print too, as on a day nobody traded.
  readonly property bool hasBaseline: !!geometry && typeof geometry.baselineY === "number" && isFinite(geometry.baselineY)
  // The columns the ink reaches, through the newest drawn print's. The
  // draw-in sweeps across these, a whole column at a time.
  readonly property int inkColumns: drawable
    ? Math.min(grid.columns, Math.floor(geometry.points[geometry.points.length - 1].x * grid.columns) + 1) : 0
  readonly property int scrubColumn: scrubX >= 0 ? Math.min(grid.columns - 1, Math.floor(scrubX * grid.columns)) : -1
  // How far the lit columns have drawn in, in pixels, and the whole width
  // once they have: what is laid over the ink draws in with it
  // (`RangeMarks`).
  readonly property real inkDrawn: replayX < 0 && reveal >= 1 ? width : curtain.width
  // The stems are retro's wash: the up colour's at 35%, dimmer for the
  // extended hours, and each side at the alpha that adds the same lightness
  // over the ground (`Tones.washAlpha`), never more than half the ink of the
  // cap above it (full, or the extended hours' 45%). A cap is the line, one
  // share of its own colour on both sides.
  // `solid` draws each stem at its cap's ink instead, for a chart so small
  // that faint stems leave only the caps, a dotted line: the pill's, 13
  // columns at 1x.
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

  // Bucket the points by column; the last point in a bucket wins, which is
  // the price at the end of that stretch of the axis. A column no print
  // falls in, between two prints the line joins, holds the last print
  // before it: the price then. Only a break (`brk`) leaves columns dark, as
  // it lifts the smooth look's pen.
  function layout() {
    var pitch = pixel + gap
    var g = {
      pitch: pitch,
      columns: Math.max(1, Math.floor(width / pitch)),
      rows: Math.max(1, Math.floor(height / pixel)),
      baseRow: 0,
      levels: [],
      ext: [],
      dot: [],
      lastRegular: -1
    }
    if (!geometry || !geometry.points) return g
    // With no previous close known, the columns stand on the chart's floor.
    g.baseRow = hasBaseline ? Math.round(geometry.baselineY * (g.rows - 1)) : g.rows - 1
    var pts = geometry.points
    // The cap sits on the last column whose own last print is regular,
    // never on one held after it. A column stays on the grid at both ends,
    // so the fill between two prints never runs past it.
    var last = -1
    for (var i = 0; i < pts.length; i++) {
      var col = Math.max(0, Math.min(g.columns - 1, Math.floor(pts[i].x * g.columns)))
      if (col !== last && last >= 0 && !g.ext[last]) g.lastRegular = last
      for (var held = last + 1; i > 0 && !pts[i].brk && held < col; held++) {
        g.levels[held] = g.levels[last]
        g.ext[held] = g.ext[last]
      }
      g.levels[col] = Math.round(pts[i].y * (g.rows - 1))
      g.ext[col] = pts[i].ext
      g.dot[col] = !!pts[i].dot
      last = col
    }
    if (last >= 0 && !g.ext[last]) g.lastRegular = last
    return g
  }

  // Where a point `fraction` along the axis is drawn: the centre of its
  // column, as `layout` buckets it.
  function xAt(fraction) {
    var col = Math.max(0, Math.min(grid.columns - 1, Math.floor(fraction * grid.columns)))
    return col * grid.pitch + pixel / 2
  }

  // How high and low the ink reaches between `x0` and `x1`, in pixels: the
  // lit rows of the columns there, and the baseline's, which runs the whole
  // width. What is laid over the chart keeps clear of it (`RangeMarks`).
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

  // The unlit grid and the dashed baseline row: always all there.
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
      if (!root.hasBaseline) return
      // The baseline: a dashed row of cells, every other column, so it lives
      // on the same grid as the bars instead of a hairline drawn across them.
      ctx.fillStyle = root.baselineColor
      for (var bc = 0; bc < g.columns; bc += 2) ctx.fillRect(bc * g.pitch, g.baseRow * pixel, pixel, pixel - root.gap)
    }
  }

  // The lit columns, revealed a whole column at a time.
  Item {
    id: curtain
    objectName: "curtain"
    width: (root.replayX >= 0 ? Math.ceil(root.grid.columns * Math.min(1, root.replayX))
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
        var baseRow = g.baseRow
        var baseY = baseRow * pixel
        for (var c = 0; c < g.columns; c++) {
          if (g.levels[c] === undefined) continue
          var y = g.levels[c] * pixel
          var above = g.levels[c] <= baseRow
          var color = above ? root.aboveColor : root.belowColor
          var dim = g.ext[c] ? 0.45 : 1
          var x = c * g.pitch
          var top = Math.min(y, baseY)
          var h = Math.abs(y - baseY)
          // The stem from each cap down to the baseline; a thin night's
          // trade stands alone, as smooth's dot does.
          if (h > 0 && !g.dot[c]) {
            var stem = g.ext[c] ? (above ? root.aboveStemDim : root.belowStemDim) : (above ? root.aboveStem : root.belowStem)
            ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, stem)
            ctx.fillRect(x, top, pixel, h)
          }
          ctx.fillStyle = Qt.rgba(color.r, color.g, color.b, dim)
          ctx.fillRect(x, y, pixel, pixel)
        }
      }
    }
  }

  // The ticks, the bell and the night's edges: each a short column of cells,
  // cut at the chart's edges, as a canvas cuts it. On the pill's six rows a
  // baseline on the top or bottom row would put a cell outside the chart.
  // Those the columns have reached draw in with them, as the smooth look's
  // ticks draw in with its line; those ahead of the newest print, in the
  // hours still to come, are there with the baseline.
  Repeater {
    model: root.hasBaseline ? root.geometry.ticks.length : 0

    Rectangle {
      required property int index
      readonly property real cellTop: Math.max(0, (root.grid.baseRow - 1) * root.pixel)
      readonly property int column: Math.min(root.grid.columns - 1, Math.floor(root.geometry.ticks[index] * root.grid.columns))
      objectName: "retroBell"
      visible: column >= root.inkColumns || column * root.grid.pitch < curtain.width
      x: column * root.grid.pitch
      y: cellTop
      width: root.pixel
      height: Math.min(root.height, (root.grid.baseRow + 2) * root.pixel) - cellTop
      color: root.baselineColor
    }
  }

  // The scrub: a faint column of cells with the cap lit.
  Rectangle {
    visible: root.drawable && root.scrubColumn >= 0
    x: root.scrubColumn * root.grid.pitch
    width: root.pixel
    height: root.height
    color: Qt.rgba(root.hairlineColor.r, root.hairlineColor.g, root.hairlineColor.b, 0.3)
  }

  Rectangle {
    visible: root.drawable && root.scrubColumn >= 0 && root.grid.levels[root.scrubColumn] !== undefined
    x: root.scrubColumn * root.grid.pitch
    y: visible ? root.grid.levels[root.scrubColumn] * root.pixel : 0
    width: root.pixel
    height: root.pixel
    color: root.hairlineColor
  }

  // The last regular print: one white cell over the cap, the pixel version
  // of the smooth chart's dot. Only once the day has drawn in.
  Rectangle {
    id: cap
    objectName: "liveCap"
    visible: root.glow && root.day && root.grid.lastRegular >= 0 && root.reveal >= 1 && root.replayX < 0
    x: root.grid.lastRegular * root.grid.pitch
    y: visible ? root.grid.levels[root.grid.lastRegular] * root.pixel : 0
    width: root.pixel
    height: root.pixel
    color: root.hairlineColor
    // Hidden mid-blink by an open's draw-in, it owes them still, and blinks
    // once it shows; any other hide, a sheet over it, stops them for good.
    onVisibleChanged: {
      if (visible) root.blink()
      else {
        if (blinks.running && root.opening && root.reveal < 1) root.blinkOwed = true
        blinks.stop()
      }
    }

    SequentialAnimation {
      id: blinks
      paused: running && root.still
      loops: 4
      onRunningChanged: if (!running) { cap.opacity = 1; root.opening = false }

      PropertyAction { target: cap; property: "opacity"; value: 1 }
      PauseAnimation { duration: 700 }
      PropertyAction { target: cap; property: "opacity"; value: 0.5 }
      PauseAnimation { duration: 160 }
      PropertyAction { target: cap; property: "opacity"; value: 0 }
      PauseAnimation { duration: 480 }
      PropertyAction { target: cap; property: "opacity"; value: 0.5 }
      PauseAnimation { duration: 160 }
    }
  }

  // The price the last blinks were for, and an open's blinks owed until the
  // cap can show them (`opening`, from the open until its blinks stop): a
  // scrub's end, a sheet closing, or the market turning live again with the
  // price the cap already blinked for starts nothing.
  property string blinkedPrice: ""
  property bool blinkOwed: false
  property bool opening: false
  function blink() {
    if (!root.live || !cap.visible || root.still) return
    if (!root.blinkOwed && root.newestPrice === root.blinkedPrice) return
    // The restart's stop of a paused burst would end `opening`: an open's
    // blinks keep it, whichever of the open's changes starts them.
    var opening = root.opening
    root.blinkOwed = false
    root.blinkedPrice = root.newestPrice
    blinks.restart()
    root.opening = opening
  }
  onNewestPriceChanged: blink()
  onSurfaceOpenChanged: if (surfaceOpen) { blinkOwed = true; opening = true; blink() }
  onLiveChanged: if (live) blink(); else blinks.stop()
  onStillChanged: if (!still) blink()
}
