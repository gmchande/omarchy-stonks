import QtQuick
import qs.Commons as Commons
import "Chart.js" as Chart
import "SmoothPaint.js" as SmoothPaint
import "Tones.js" as Tones
// A row's day line. With a known direction it takes the hero's rule, the up
// colour above the dashed baseline and the down colour below; without one,
// as on a row still loading, one colour. Once tonight has traded, what the
// number beside it doesn't count (`geometry.aside`) keeps that rule in a
// thinner, fainter line, or with one colour, takes `greyColor`. The
// draw-in clips the line, not the baseline, in the one canvas, so a row
// costs no layer more; the scrub's dot has its own layer, so a scrub never
// repaints the line.
Item {
  id: root

  property var geometry: null
  property color lineColor: Tones.dim(Commons.Color.foreground, Commons.Color.background)
  // What the number beside the line doesn't count, in a line of one colour.
  property color greyColor: lineColor
  // And in a split line: thinner and fainter, so it reads as context beside
  // the day the number counts.
  readonly property real asideAlpha: 0.5
  readonly property real asideWidth: 0.75
  property var up: null
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  readonly property bool split: typeof up === "boolean"
  property color baselineColor: Tones.dimmer(Commons.Color.foreground, Commons.Color.background)
  property real lineWidth: 1.25
  // 0..1 along the session, or -1 for none.
  property real cursorX: -1
  readonly property real pad: 1.5
  // The baseline, where there is one, shows whole; the line shows to the
  // newest trade's dot.
  property real reveal: 1
  readonly property bool drawable: Chart.drawable(geometry)
  // Without it, no direction to split by.
  readonly property bool hasBaseline: Chart.hasBaseline(geometry)

  onGeometryChanged: { ink.requestPaint(); marks.requestPaint() }
  onLineColorChanged: { ink.requestPaint(); marks.requestPaint() }
  onGreyColorChanged: { ink.requestPaint(); marks.requestPaint() }
  onSplitChanged: { ink.requestPaint(); marks.requestPaint() }
  onUpColorChanged: { ink.requestPaint(); marks.requestPaint() }
  onDownColorChanged: { ink.requestPaint(); marks.requestPaint() }
  onBaselineColorChanged: ink.requestPaint()
  onLineWidthChanged: ink.requestPaint()
  onRevealChanged: ink.requestPaint()
  onCursorXChanged: marks.requestPaint()

  // A dot's ink at `x`, `y` pixels down: the line's there.
  function inkAt(x, y) {
    var aside = Chart.asideAt(geometry, x)
    if (!split || !hasBaseline) return aside ? greyColor : lineColor
    var c = y <= pad + geometry.baselineY * (height - pad * 2) ? upColor : downColor
    return aside ? Qt.rgba(c.r, c.g, c.b, asideAlpha) : c
  }

  Canvas {
    id: ink
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!root.drawable) return

      var pts = root.geometry.points
      var pad = root.pad
      var w = width - pad * 2
      var h = height - pad * 2

      // With no line under it, the line takes its own ink (`by` null).
      var by = root.hasBaseline ? pad + root.geometry.baselineY * h : null
      var parts = SmoothPaint.asideParts(root.geometry.aside, pad, w, width)
      if (root.hasBaseline) SmoothPaint.strokeBaseline(ctx, pad, pad + w, by, root.baselineColor, 1, [2, 3])

      ctx.lineWidth = root.lineWidth
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      // The sweep runs to the newest trade's dot.
      ctx.save()
      if (root.reveal < 1) {
        var inkRight = pad + pts[pts.length - 1].x * w + root.lineWidth * 1.5 + 1
        ctx.beginPath()
        ctx.rect(0, 0, inkRight * Math.max(0, root.reveal), height)
        ctx.clip()
      }
      for (var s = 0; s < parts.length; s++) {
        if (parts[s].to <= parts[s].from) continue
        ctx.save()
        if (parts.length > 1) SmoothPaint.clipTo(ctx, parts[s], height)
        var tinted = root.split && by !== null
        var alpha = parts[s].aside ? root.asideAlpha : 1
        if (parts[s].aside && !tinted) ctx.strokeStyle = root.greyColor
        else if (tinted) ctx.strokeStyle = SmoothPaint.splitInk(ctx, height, by,
          Qt.rgba(root.upColor.r, root.upColor.g, root.upColor.b, alpha), Qt.rgba(root.downColor.r, root.downColor.g, root.downColor.b, alpha))
        else ctx.strokeStyle = root.lineColor
        if (parts[s].aside && tinted) ctx.lineWidth = root.asideWidth
        SmoothPaint.strokeLine(ctx, pts, pad, w, h, 1)
        ctx.restore()
      }
      // A lone trade is a dot three line widths across.
      for (var k = 0; k < pts.length; k++) {
        if (!(k === 0 || pts[k].brk) || !(k === pts.length - 1 || pts[k + 1].brk)) continue
        var dy = pad + pts[k].y * h
        ctx.fillStyle = root.inkAt(pts[k].x, dy)
        ctx.beginPath()
        ctx.arc(pad + pts[k].x * w, dy, root.lineWidth * 1.5, 0, Math.PI * 2)
        ctx.fill()
      }
      ctx.restore()
    }
  }

  Canvas {
    id: marks
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (!root.drawable || root.cursorX < 0) return
      var pts = root.geometry.points
      var pad = root.pad
      var w = width - pad * 2
      var h = height - pad * 2
      var cy = Chart.yAt(pts, root.cursorX)
      if (cy !== null) {
        ctx.fillStyle = root.inkAt(root.cursorX, pad + cy * h)
        ctx.beginPath()
        ctx.arc(pad + root.cursorX * w, pad + cy * h, 2.5, 0, Math.PI * 2)
        ctx.fill()
      }
    }
  }
}
