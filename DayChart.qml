import QtQuick
import qs.Commons as Commons
import "Chart.js" as Chart
import "Tones.js" as Tones
// The hero chart, one rule for the day and every range: a dashed baseline at
// the price the change is measured from, and the line and the area between
// it and the baseline in the up colour above and the down colour below, the
// way the retro columns fall. The day adds its own furniture: the dimmer
// extended hours, the ticks at the bell and the night's edges, a line that
// starts again after a break in the exchange's day, and the dot on the last
// regular print.
// Three layers, so each paints only when what it draws changes: the
// baseline, the data's ink under a clip the draw-in widens, and the scrub.
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
  // How much of the ink has been drawn, 0..1. The baseline is always there;
  // the line draws in from the left edge to the newest drawn print, and at
  // 1 the whole chart shows.
  property real reveal: 1
  // A replay's place along the plot, 0..1, or -1 without one: the line draws
  // in behind it, in the plot's own terms.
  property real replayX: -1
  // The dot ripples while the market trades, the way Apple's does: three
  // times as a new price arrives (`newestPrice`, the newest print's) or the
  // surface opens, then it rests.
  property bool live: false
  property string newestPrice: ""
  property bool surfaceOpen: true
  // A closing surface: the live mark stops where it is, as the rest of the
  // surface does; it ripples again as the surface opens.
  property bool still: false
  // The surface under the chart, which the wash is seen against.
  property color ground: Commons.Color.background
  // The size of every stroke, the dot, and the pad, as a multiple of the
  // screen's: the screenshot lays its chart out at the picture's pixels,
  // 2 to its unit (`ShareCard`).
  property real weight: 1
  // The baseline's dashes, which Canvas also multiplies by the line's
  // width: the weight, or the picture's 2 on a screen of any scale, so the
  // screenshot's dashes are the same length on each (`ShareCard`).
  property real dashUnit: weight

  readonly property bool directionKnown: typeof up === "boolean"
  readonly property color aboveColor: directionKnown ? upColor : baselineColor
  readonly property color belowColor: directionKnown ? downColor : baselineColor
  readonly property int pad: Math.round(3 * weight)
  readonly property var lastPoint: Chart.lastRegularPoint(geometry)
  readonly property bool day: !!geometry && geometry.day === true
  readonly property color dotColor: lastPoint && lastPoint.y > geometry.baselineY ? belowColor : aboveColor
  // One print draws: the first print after midnight is a dot on its day.
  readonly property bool drawable: !!geometry && !!geometry.points && geometry.points.length >= 1
  // The baseline draws with no print too, as on a day nobody traded.
  readonly property bool hasBaseline: !!geometry && typeof geometry.baselineY === "number" && isFinite(geometry.baselineY)
  // Where the ink ends, in pixels: the newest drawn print and its dot (the
  // line's width and a half, and a pixel). The draw-in sweeps to here.
  readonly property real inkLast: drawable ? geometry.points[geometry.points.length - 1].x : 0
  readonly property real inkRight: Math.min(width, pad + inkLast * (width - pad * 2) + 4)
  // How far the ink has drawn in, in pixels: what is laid over the ink
  // draws in with it (`RangeMarks`).
  readonly property real inkDrawn: curtain.width
  // The wash: the up colour's at 16%, and each side at the alpha that adds
  // the same lightness over the ground (`Tones.washAlpha`), so a down day's
  // reads as strongly as an up day's; never more than half the line's ink.
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

  // Where along the axis `x` is, inside the pad the line is drawn within.
  function fractionAt(x) {
    return (x - pad) / (width - pad * 2)
  }

  // Where a point `fraction` along the axis is drawn: `fractionAt`'s
  // inverse.
  function xAt(fraction) {
    return pad + fraction * (width - pad * 2)
  }

  // How high and low the ink reaches between `x0` and `x1`, in pixels: the
  // prints there and the nearest either side, which the line joins to
  // them, the baseline, which runs the whole width, and the line's half
  // width. What is laid over the chart keeps clear of it (`RangeMarks`).
  function inkExtentIn(x0, x1) {
    var g = geometry
    var ys = g && typeof g.baselineY === "number" && isFinite(g.baselineY) ? [g.baselineY] : []
    var pts = g && g.points ? g.points : []
    for (var i = 0; i < pts.length; i++) {
      var before = xAt(pts[Math.max(0, i - 1)].x)
      var after = xAt(pts[Math.min(pts.length - 1, i + 1)].x)
      if (after >= x0 && before <= x1) ys.push(pts[i].y)
    }
    if (!ys.length) return { top: height, bottom: 0 }
    var h = height - pad * 2
    return { top: pad + Math.min.apply(null, ys) * h - weight, bottom: pad + Math.max.apply(null, ys) * h + weight }
  }

  // The ticks: a mark on the baseline at the bell, and at the night's
  // edges. Those the line has reached draw in with it; those ahead of the
  // newest print, in the hours still to come, are there with the baseline.
  function strokeTicks(ctx, by, ahead) {
    var w = width - pad * 2
    ctx.strokeStyle = baselineColor
    ctx.lineWidth = weight
    for (var k = 0; k < geometry.ticks.length; k++) {
      if ((geometry.ticks[k] > inkLast) !== ahead) continue
      var cx = pad + geometry.ticks[k] * w
      ctx.beginPath()
      ctx.moveTo(cx, by - 4 * weight)
      ctx.lineTo(cx, by + 4 * weight)
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
      if (!root.hasBaseline) return
      var by = root.pad + root.geometry.baselineY * (height - root.pad * 2)
      ctx.strokeStyle = root.baselineColor
      ctx.lineWidth = root.weight
      ctx.lineCap = "round"
      ctx.setLineDash([3 * root.dashUnit, 4 * root.dashUnit])
      ctx.beginPath()
      ctx.moveTo(root.pad, by)
      ctx.lineTo(width - root.pad, by)
      ctx.stroke()
      ctx.setLineDash([])
      root.strokeTicks(ctx, by, true)
    }
  }

  // The draw-in widens this clip over ink that is already painted.
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
        // Everything up to the last regular print, the hours before it
        // included: that is the day the fill is about. A range has no
        // extended prints, so it is all of it.
        var lastRegular = -1
        for (var n = 0; n < pts.length; n++) if (!pts[n].ext) lastRegular = n
        var filled = runs(pts.slice(0, lastRegular + 1), function() { return true })

        ctx.fillStyle = sides(ctx, by, root.aboveWash, root.belowWash)
        for (var r = 0; r < filled.length; r++) {
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
        // The whole series in dim ink, then each regular session over it in
        // full ink, so the extended hours on either side read as the quieter
        // part of one continuous line.
        ctx.strokeStyle = sides(ctx, by, 0.45, 0.45)
        strokeRuns(ctx, runs(pts, function() { return true }), pad, w, h)
        ctx.strokeStyle = sides(ctx, by, 1, 1)
        strokeRuns(ctx, runs(pts, function(p) { return !p.ext }), pad, w, h)

        // The ticks the line has reached draw in with it.
        root.strokeTicks(ctx, by, false)
      }

      // The stretches the line joins: a point that `keep` refuses, or one
      // that starts again after a break (`brk`, Tokyo's lunch), ends a stretch.
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

      // The above colour over the baseline and the below colour under it, in
      // one pass: stroking each line twice, clipped to each side, doubled the
      // paint. Two stops at one offset merge, so the second sits a hair below.
      // The line's dim ink is one share of its own colour on both sides: it
      // reads against the full line beside it, not against the other side.
      function sides(ctx, by, aboveAlpha, belowAlpha) {
        var stop = Math.max(0, Math.min(1, by / height))
        var g = ctx.createLinearGradient(0, 0, 0, height)
        g.addColorStop(stop, Qt.rgba(root.aboveColor.r, root.aboveColor.g, root.aboveColor.b, aboveAlpha))
        g.addColorStop(Math.min(1, stop + 0.0001), Qt.rgba(root.belowColor.r, root.belowColor.g, root.belowColor.b, belowAlpha))
        return g
      }

      // A stretch of one print, a day's only one or one alone beside a
      // break, is a dot three times the line's width, in its session's tone,
      // so it reads at a glance. It never breathes: that is the live dot's
      // alone.
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

  Canvas {
    id: marks
    objectName: "scrubMarks"
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

  // The dot on the last regular print lives outside the canvas so it can
  // ripple without repainting the line: a core, and a halo that grows out
  // and fades. While the market is open a new price, or the dot's first
  // showing (an open, a new chart, the end of a draw-in), starts three
  // ripples, about 6 s, and a newer price during them starts the three
  // over; then the halo rests as it does with the market closed. A range
  // has no dot: its last bar need not be the headline print.
  Item {
    id: dot
    visible: root.day && root.lastPoint !== null && root.reveal >= 1 && root.replayX < 0
    x: root.lastPoint ? root.pad + root.lastPoint.x * (root.width - root.pad * 2) : 0
    y: root.lastPoint ? root.pad + root.lastPoint.y * (root.height - root.pad * 2) : 0
    // Hidden mid-ripple by an open's draw-in, it owes them still, and
    // ripples once it shows; any other hide, a sheet over it, stops them
    // for good.
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
        NumberAnimation { target: halo; property: "scale"; from: 1; to: 2.2; duration: 1400; easing.type: Easing.OutCubic }
        NumberAnimation { target: halo; property: "opacity"; from: 0.35; to: 0; duration: 1400; easing.type: Easing.OutCubic }
      }
      PauseAnimation { duration: 600 }
    }
  }

  // The price the last ripples were for, and an open's ripples owed until
  // the dot can show them (`opening`, from the open until its ripples
  // stop): a scrub's end, a sheet closing, or the market turning live again
  // with the price the dot already rippled for starts nothing.
  property string rippledPrice: ""
  property bool rippleOwed: false
  property bool opening: false
  function ripple() {
    if (!root.live || !dot.visible || root.still) return
    if (!root.rippleOwed && root.newestPrice === root.rippledPrice) return
    // The restart's stop of a paused burst would end `opening`: an open's
    // ripples keep it, whichever of the open's changes starts them.
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
