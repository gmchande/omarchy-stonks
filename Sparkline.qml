import QtQuick
import qs.Commons as Commons
import "Chart.js" as Chart
import "Tones.js" as Tones
// A row's day line. With a known direction it takes the hero's rule, the up
// colour above the dashed baseline and the down colour below, the baseline
// stepping at the bell once tonight has traded (`geometry.step`); without
// one, as on a row still loading, one colour. The draw-in clips the line,
// not the baseline, in the one canvas, so a row costs no layer more; the
// scrub's dot has its own layer, so a scrub never repaints the line.
Item {
  id: root

  property var geometry: null
  property color lineColor: Tones.dim(Commons.Color.foreground, Commons.Color.background)
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
  onSplitChanged: { ink.requestPaint(); marks.requestPaint() }
  onUpColorChanged: { ink.requestPaint(); marks.requestPaint() }
  onDownColorChanged: { ink.requestPaint(); marks.requestPaint() }
  onBaselineColorChanged: ink.requestPaint()
  onLineWidthChanged: ink.requestPaint()
  onRevealChanged: ink.requestPaint()
  onCursorXChanged: marks.requestPaint()

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

      // With no line under a part, it takes the line's own ink (`by` null).
      var by = root.hasBaseline ? pad + root.geometry.baselineY * h : null
      var step = root.geometry.step
      var stepX = step ? pad + step.x * w : width
      var parts = [{ from: 0, to: stepX, by: by }]
      if (step) parts.push({ from: stepX, to: width, by: pad + step.y * h })
      if (root.hasBaseline || step) {
        ctx.strokeStyle = root.baselineColor
        ctx.lineWidth = 1
        // Round ends on every paint: the context keeps the last paint's cap,
        // so otherwise a first paint draws square dashes and repaints round.
        ctx.lineCap = "round"
        ctx.setLineDash([2, 3])
        ctx.beginPath()
        if (root.hasBaseline) {
          ctx.moveTo(pad, by)
          ctx.lineTo(Math.min(stepX, pad + w), by)
        }
        if (step) {
          ctx.moveTo(stepX, parts[1].by)
          ctx.lineTo(pad + w, parts[1].by)
        }
        ctx.stroke()
        ctx.setLineDash([])
      }

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
      for (var s = 0; s < (root.split ? parts.length : 1); s++) {
        ctx.save()
        if (root.split && step) {
          ctx.beginPath()
          ctx.rect(parts[s].from, 0, parts[s].to - parts[s].from, height)
          ctx.clip()
        }
        // Two stops at one offset merge, so the second sits a hair below.
        if (root.split && parts[s].by !== null) {
          var stop = Math.max(0, Math.min(1, parts[s].by / height))
          var g = ctx.createLinearGradient(0, 0, 0, height)
          g.addColorStop(stop, root.upColor)
          g.addColorStop(Math.min(1, stop + 0.0001), root.downColor)
          ctx.strokeStyle = g
        } else ctx.strokeStyle = root.lineColor
        // A break (`brk`) lifts the pen, as the hero's line does.
        ctx.beginPath()
        for (var i = 0; i < pts.length; i++) {
          var x = pad + pts[i].x * w
          var y = pad + pts[i].y * h
          if (i === 0 || pts[i].brk) ctx.moveTo(x, y)
          else ctx.lineTo(x, y)
        }
        ctx.stroke()
        ctx.restore()
      }
      // A lone trade is a dot three line widths across.
      for (var k = 0; k < pts.length; k++) {
        if (!(k === 0 || pts[k].brk) || !(k === pts.length - 1 || pts[k + 1].brk)) continue
        var dy = pad + pts[k].y * h
        var under = Chart.baseAt(root.geometry, pts[k].x)
        ctx.fillStyle = !root.split || under === null ? root.lineColor : dy <= pad + under * h ? root.upColor : root.downColor
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
      var under = Chart.baseAt(root.geometry, root.cursorX)
      var cy = Chart.yAt(pts, root.cursorX)
      if (cy !== null) {
        ctx.fillStyle = !root.split || under === null ? root.lineColor : cy <= under ? root.upColor : root.downColor
        ctx.beginPath()
        ctx.arc(pad + root.cursorX * w, pad + cy * h, 2.5, 0, Math.PI * 2)
        ctx.fill()
      }
    }
  }
}
