import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Chart.js" as Chart
import "Tones.js" as Tones
import "Motion.js" as Motion
// The smooth chart, one rule for the day and every range: a dashed baseline at
// the price the change is measured from, and the line and its wash in the up
// colour above it and the down colour below, as the retro columns fall. The day
// adds dimmer hours, ticks at the bell and the night's edges, breaks, and the
// dot on the newest bright trade. Once tonight has traded, the baseline steps
// at the bell to the close just gone (`geometry.step`), and the line past it
// takes its colours from there. Three layers, so each paints only when what
// it draws changes: the baseline, the ink under a clip the draw-in widens, and
// the scrub.
Item {
  id: root

  property var geometry: null
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property color baselineColor: Tones.dimmer(Commons.Color.foreground, Commons.Color.background)
  property color hairlineColor: Commons.Color.foreground
  property var up: true
  // 0..1 along the axis, or -1 when not scrubbing.
  property real scrubX: -1
  // The baseline is always there; the ink draws in from the left to the
  // newest trade.
  property real reveal: 1
  // A replay's place, 0..1, or -1 without one: the ink draws in behind it.
  property real replayX: -1
  // The dot ripples while the market trades, as Apple's does: three times as a
  // new price arrives or the surface opens, then it rests.
  property bool live: false
  property string newestPrice: ""
  property bool surfaceOpen: true
  // Closing: the live mark stops where it is, and ripples again as the surface
  // opens.
  property bool still: false
  // The surface under the chart, which the wash is seen against.
  property color ground: Commons.Color.background
  // A multiple of every stroke, the dot and the pad: the screenshot lays its
  // chart out at 2 (`ShareCard`).
  property real weight: 1
  // Canvas multiplies the dashes by the line's width too: the picture's 2 on a
  // screen of any scale keeps them one length (`ShareCard`).
  property real dashUnit: weight

  readonly property bool directionKnown: typeof up === "boolean"
  readonly property color aboveColor: directionKnown ? upColor : baselineColor
  readonly property color belowColor: directionKnown ? downColor : baselineColor
  readonly property real pad: 3 * weight
  readonly property var lastPoint: Chart.lastLitPoint(geometry)
  readonly property bool day: !!geometry && geometry.day === true
  // Against the dashed line under it, and in the line's own ink with none.
  readonly property color dotColor: {
    var base = lastPoint ? Chart.baseAt(geometry, lastPoint.x) : null
    return base === null ? baselineColor : lastPoint.y > base ? belowColor : aboveColor
  }
  // One trade draws: the first trade after midnight is a dot on its day.
  readonly property bool drawable: !!geometry && !!geometry.points && geometry.points.length >= 1
  // The baseline draws with no trade too, as on a day nobody traded.
  readonly property bool hasBaseline: !!geometry && typeof geometry.baselineY === "number" && isFinite(geometry.baselineY)
  readonly property bool hasStep: !!geometry && !!geometry.step
  // The draw-in sweeps to the newest trade's dot: the line's width and a half,
  // and a pixel.
  readonly property real inkLast: drawable ? geometry.points[geometry.points.length - 1].x : 0
  readonly property real inkRight: Math.min(width, pad + inkLast * (width - pad * 2) + 4)
  // What is laid over the ink draws in with it (`RangeMarks`).
  readonly property real inkDrawn: curtain.width
  // Each side's wash adds the lightness the up colour's does at 16%
  // (`Tones.washAlpha`), so a down day's reads as strongly as an up day's.
  readonly property real aboveWash: Tones.washAlpha(aboveColor, upColor, ground, 0.16, 1)
  readonly property real belowWash: Tones.washAlpha(belowColor, upColor, ground, 0.16, 1)

  onGeometryChanged: { base.requestPaint(); ink.requestPaint(); marks.requestPaint() }
  onBaselineColorChanged: { base.requestPaint(); ink.requestPaint() }
  onAboveWashChanged: ink.requestPaint()
  onBelowWashChanged: ink.requestPaint()
  onAboveColorChanged: ink.requestPaint()
  onBelowColorChanged: ink.requestPaint()
  onHairlineColorChanged: marks.requestPaint()
  onScrubXChanged: marks.requestPaint()

  function fractionAt(x) {
    return (x - pad) / (width - pad * 2)
  }

  function xAt(fraction) {
    return pad + fraction * (width - pad * 2)
  }

  // The trades between `x0` and `x1` and the nearest either side, which the
  // line joins to them, each with its half width or a lone trade's dot, and
  // the baseline. What is laid over the chart keeps clear of it (`RangeMarks`).
  function inkExtentIn(x0, x1) {
    var g = geometry
    var h = height - pad * 2
    var top = height
    var bottom = 0
    var reach = function(y, r) {
      top = Math.min(top, pad + y * h - r)
      bottom = Math.max(bottom, pad + y * h + r)
    }
    if (g && typeof g.baselineY === "number" && isFinite(g.baselineY)) reach(g.baselineY, weight)
    if (g && g.step) reach(g.step.y, weight)
    var pts = g && g.points ? g.points : []
    for (var i = 0; i < pts.length; i++) {
      var lone = (i === 0 || pts[i].brk) && (i === pts.length - 1 || pts[i + 1].brk)
      var r = lone ? 3 * weight : weight
      var before = xAt(pts[Math.max(0, i - 1)].x) - r
      var after = xAt(pts[Math.min(pts.length - 1, i + 1)].x) + r
      if (after >= x0 && before <= x1) reach(pts[i].y, r)
    }
    return { top: top, bottom: bottom }
  }

  // Ticks the line has reached draw in with it; those ahead, in hours still to
  // come, are there with the baseline. The bell's stays on the day's line;
  // with no line under them, none.
  function strokeTicks(ctx, ahead) {
    var w = width - pad * 2
    var h = height - pad * 2
    var step = geometry.step
    ctx.strokeStyle = baselineColor
    ctx.lineWidth = weight
    for (var k = 0; k < geometry.ticks.length; k++) {
      var base = step && geometry.ticks[k] > step.x ? step.y : geometry.baselineY
      if ((geometry.ticks[k] > inkLast) !== ahead || base === null) continue
      var cx = pad + geometry.ticks[k] * w
      var cy = pad + base * h
      ctx.beginPath()
      ctx.moveTo(cx, cy - 4 * weight)
      ctx.lineTo(cx, cy + 4 * weight)
      ctx.stroke()
    }
  }

  Canvas {
    id: base
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!root.hasBaseline && !root.hasStep) return
      var h = height - root.pad * 2
      var step = root.geometry.step
      var sx = step ? root.xAt(step.x) : width - root.pad
      ctx.strokeStyle = root.baselineColor
      ctx.lineWidth = root.weight
      ctx.lineCap = "round"
      ctx.setLineDash([3 * root.dashUnit, 4 * root.dashUnit])
      ctx.beginPath()
      if (root.hasBaseline) {
        ctx.moveTo(root.pad, root.pad + root.geometry.baselineY * h)
        ctx.lineTo(sx, root.pad + root.geometry.baselineY * h)
      }
      if (step) {
        ctx.moveTo(sx, root.pad + step.y * h)
        ctx.lineTo(width - root.pad, root.pad + step.y * h)
      }
      ctx.stroke()
      ctx.setLineDash([])
      root.strokeTicks(ctx, true)
    }
  }

  Item {
    id: curtain
    width: root.replayX >= 0 ? root.width * Math.min(1, root.replayX)
      : root.reveal >= 1 ? root.width : root.inkRight * Math.max(0, root.reveal)
    height: root.height
    clip: true

    Canvas {
      id: ink
      objectName: "ink"
      width: root.width
      height: root.height
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!root.drawable) return
        var geometry = root.geometry
        var pad = root.pad
        var pts = geometry.points
        var w = width - pad * 2
        var h = height - pad * 2
        var by = pad + geometry.baselineY * h
        // The fill is about the day up to its last regular trade. A range has
        // no extended trades.
        var lastRegular = -1
        for (var n = 0; n < pts.length; n++) if (!pts[n].ext) lastRegular = n
        var filled = runs(pts.slice(0, lastRegular + 1), function() { return true })

        // With no previous close known there is no wash, only the line.
        ctx.fillStyle = sides(ctx, by, root.aboveWash, root.belowWash)
        for (var r = 0; root.hasBaseline && r < filled.length; r++) {
          var run = filled[r]
          if (run.length < 2) continue
          ctx.beginPath()
          ctx.moveTo(pad + run[0].x * w, by)
          for (var i = 0; i < run.length; i++) ctx.lineTo(pad + run[i].x * w, pad + run[i].y * h)
          ctx.lineTo(pad + run[run.length - 1].x * w, by)
          ctx.closePath()
          ctx.fill()
        }

        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.lineWidth = 2 * root.weight
        // The whole series in dim ink, then the bright part over it (`dim`),
        // so the rest reads as the quieter part of one line. Each side of the
        // step takes its colours from its own baseline, or with none, the
        // line's own ink.
        var stepX = geometry.step ? pad + geometry.step.x * w : width
        var parts = [{ from: 0, to: stepX, by: root.hasBaseline ? by : null }]
        if (geometry.step) parts.push({ from: stepX, to: width, by: pad + geometry.step.y * h })
        for (var s = 0; s < parts.length; s++) {
          ctx.save()
          if (geometry.step) {
            ctx.beginPath()
            ctx.rect(parts[s].from, 0, parts[s].to - parts[s].from, height)
            ctx.clip()
          }
          ctx.strokeStyle = sides(ctx, parts[s].by, 0.45, 0.45)
          strokeRuns(ctx, runs(pts, function() { return true }), pad, w, h)
          ctx.strokeStyle = sides(ctx, parts[s].by, 1, 1)
          strokeRuns(ctx, runs(pts, function(p) { return !p.dim }), pad, w, h)
          ctx.restore()
        }

        if (root.hasBaseline || root.hasStep) root.strokeTicks(ctx, false)
      }

      // A point `keep` refuses, or a break (`brk`), ends a stretch.
      function runs(pts, keep) {
        var out = []
        var run = []
        for (var i = 0; i < pts.length; i++) {
          if (pts[i].brk || !keep(pts[i])) {
            if (run.length) out.push(run)
            run = []
          }
          if (keep(pts[i])) run.push(pts[i])
        }
        if (run.length) out.push(run)
        return out
      }

      // One gradient for both sides: stroking each line twice, clipped to each
      // side, doubles the paint. Two stops at one offset merge, so the second
      // sits a hair below. The dim ink is one share of its own colour: it reads
      // against the full line beside it, not against the other side. With no
      // line to stand against (`by` null), the baseline's ink.
      function sides(ctx, by, aboveAlpha, belowAlpha) {
        if (by === null) return Qt.rgba(root.baselineColor.r, root.baselineColor.g, root.baselineColor.b, aboveAlpha)
        var stop = Math.max(0, Math.min(1, by / height))
        var g = ctx.createLinearGradient(0, 0, 0, height)
        g.addColorStop(stop, Qt.rgba(root.aboveColor.r, root.aboveColor.g, root.aboveColor.b, aboveAlpha))
        g.addColorStop(Math.min(1, stop + 0.0001), Qt.rgba(root.belowColor.r, root.belowColor.g, root.belowColor.b, belowAlpha))
        return g
      }

      // A lone trade, a day's only one or one beside a break, is a dot three
      // times the line's width, so it reads at a glance. It never breathes:
      // that is the live dot's alone.
      function strokeRuns(ctx, lines, pad, w, h) {
        for (var r = 0; r < lines.length; r++) {
          var line = lines[r]
          if (line.length === 1) {
            ctx.fillStyle = ctx.strokeStyle
            ctx.beginPath()
            ctx.arc(pad + line[0].x * w, pad + line[0].y * h, ctx.lineWidth * 1.5, 0, Math.PI * 2)
            ctx.fill()
            continue
          }
          ctx.beginPath()
          for (var j = 0; j < line.length; j++) {
            var x = pad + line[j].x * w
            var y = pad + line[j].y * h
            if (j === 0) ctx.moveTo(x, y)
            else ctx.lineTo(x, y)
          }
          ctx.stroke()
        }
      }
    }
  }

  // What is laid over the ink but under the scrub's line and dot
  // (`RangeMarks`).
  readonly property Item underScrub: underScrubLayer
  Item {
    id: underScrubLayer
    anchors.fill: parent
  }

  Canvas {
    id: marks
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!root.drawable || root.scrubX < 0) return
      var pad = root.pad
      var w = width - pad * 2
      var h = height - pad * 2
      var sx = pad + root.scrubX * w
      ctx.strokeStyle = root.hairlineColor
      ctx.lineWidth = root.weight
      ctx.beginPath()
      ctx.moveTo(sx, 0)
      ctx.lineTo(sx, height)
      ctx.stroke()
      var sy = Chart.yAt(root.geometry.points, root.scrubX)
      if (sy !== null) {
        ctx.fillStyle = root.hairlineColor
        ctx.beginPath()
        ctx.arc(sx, pad + sy * h, 5 * root.weight, 0, Math.PI * 2)
        ctx.fill()
      }
    }
  }

  // Outside the canvas, so it ripples without repainting the line. While the
  // market is open, a new price or the dot's first showing (an open, a new
  // chart, a draw-in's end) starts three ripples, about 6 s, and a newer price
  // starts them over. A range has no dot: its last bar need not be the
  // headline trade.
  Item {
    id: dot
    visible: root.day && root.lastPoint !== null && root.reveal >= 1 && root.replayX < 0
    x: root.lastPoint ? root.pad + root.lastPoint.x * (root.width - root.pad * 2) : 0
    y: root.lastPoint ? root.pad + root.lastPoint.y * (root.height - root.pad * 2) : 0
    // Hidden mid-ripple by an open's draw-in, it owes them and ripples once it
    // shows; any other hide, as a sheet over it, stops them.
    onVisibleChanged: {
      if (visible) root.ripple()
      else {
        if (ripples.running && root.opening && root.reveal < 1) root.rippleOwed = true
        ripples.stop()
      }
    }

    Rectangle {
      id: halo
      objectName: "liveHalo"
      anchors.centerIn: parent
      width: 14 * root.weight
      height: 14 * root.weight
      radius: 7 * root.weight
      color: root.dotColor
      opacity: 0.25
    }

    Rectangle {
      anchors.centerIn: parent
      width: 6 * root.weight
      height: 6 * root.weight
      radius: 3 * root.weight
      color: root.dotColor
    }

    SequentialAnimation {
      id: ripples
      paused: running && root.still
      loops: 3
      onRunningChanged: if (!running) { halo.scale = 1; halo.opacity = 0.25; root.opening = false }

      ParallelAnimation {
        NumberAnimation { target: halo; property: "scale"; from: 1; to: 2.2; duration: Motion.duration(Style, 1400); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) }
        NumberAnimation { target: halo; property: "opacity"; from: 0.35; to: 0; duration: Motion.duration(Style, 1400); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) }
      }
      PauseAnimation { duration: Motion.duration(Style, 600) }
    }
  }

  // A scrub's end, a sheet closing, or the market turning live again with the
  // price already rippled for starts nothing. `opening` lasts from the open
  // until its ripples stop.
  property string rippledPrice: ""
  property bool rippleOwed: false
  property bool opening: false
  function ripple() {
    if (!root.live || !dot.visible || root.still) return
    // With the shell's animations off, the dot stays still, and the price
    // counts as rippled for: animations back on, it never ripples for it.
    if (Style.reduceMotion) {
      root.rippleOwed = false
      root.rippledPrice = root.newestPrice
      root.opening = false
      return
    }
    if (!root.rippleOwed && root.newestPrice === root.rippledPrice) return
    // A restart's stop of a paused burst would end `opening`; an open's
    // ripples keep it.
    var opening = root.opening
    root.rippleOwed = false
    root.rippledPrice = root.newestPrice
    ripples.restart()
    root.opening = opening
  }
  onNewestPriceChanged: ripple()
  onSurfaceOpenChanged: if (surfaceOpen) { rippleOwed = true; opening = true; ripple() }
  onLiveChanged: if (live) ripple(); else ripples.stop()
  onStillChanged: if (!still) ripple()
}
