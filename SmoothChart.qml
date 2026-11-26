import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Chart.js" as Chart
import "Morph.js" as Morph
import "SmoothPaint.js" as SmoothPaint
import "Tones.js" as Tones
import "Motion.js" as Motion
// The smooth chart, one rule for the day and every range: a dashed baseline at
// the price the change is measured from, and the line and its wash in the up
// colour above it and the down colour below, as the retro columns fall. The
// day draws the hours around its session lighter, and adds ticks at the bell
// and the night's edges, breaks, and the dot on the newest trade of what
// trades now. Its wash fades from the day's far reach to clear at the dashed
// line, under every trade. Once tonight has traded, what the number beside
// the chart doesn't count draws fainter and thinner, with no wash
// (`geometry.aside`), and the rest keeps a flat wash under the session.
// Three layers, so each paints only when what it draws changes: the
// baseline, the ink under a clip the draw-in widens, and the scrub. Another
// chart bends out of the one before (`morphFrom`, `morph`), every frame a
// chart drawn as any is.
Item {
  id: root

  property var geometry: null
  property color upColor: Commons.Color.foreground
  property color downColor: Commons.Color.urgent
  property color baselineColor: Tones.dimmer(Commons.Color.foreground, Commons.Color.background)
  // How strongly what the number beside the chart doesn't count
  // (`geometry.aside`) draws: fainter than tonight's dim hours' 45%.
  readonly property real asideAlpha: 0.4
  // The hours around the session, on a day not set apart (`faint`): lighter
  // than the session, and still its green or red on a dark ground.
  readonly property real hoursAlpha: 0.6
  property color hairlineColor: Commons.Color.foreground
  property var up: true
  // 0..1 along the axis, or -1 when not scrubbing.
  property real scrubX: -1
  // The baseline is always there; the ink draws in from the first trade to
  // the newest.
  property real reveal: 1
  // The chart this one bends out of, and how far it has come, 0 to 1.
  property var morphFrom: null
  property real morph: 1
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
  // Worked out once a change, then a frame of it at each step. A change that
  // comes mid-bend bends on from the frame on screen.
  property var bendFrom: null
  property var lastShown: null
  onMorphFromChanged: bendFrom = morphFrom && morph < 1 && lastShown ? lastShown : morphFrom
  readonly property var plan: bendFrom && geometry ? Morph.plan(bendFrom, geometry) : null
  readonly property var shown: plan && morph < 1 ? Morph.frame(plan, morph) : geometry
  readonly property var lastPoint: Chart.lastLitPoint(shown)
  readonly property bool day: !!geometry && geometry.day === true
  // Against the dashed line under it, and in the line's own ink with none.
  readonly property color dotColor: !lastPoint || !hasBaseline ? baselineColor
    : lastPoint.y > shown.baselineY ? belowColor : aboveColor
  readonly property bool drawable: Chart.drawable(shown)
  readonly property bool hasBaseline: Chart.hasBaseline(shown)
  // The dot rides a line that had one, and comes with the line's end to one
  // that hadn't.
  readonly property bool dotRides: !!plan && bendFrom.day === true && Chart.lastLitPoint(bendFrom) !== null
  // The draw-in sweeps from before the first trade's dot to past the
  // newest's: the line's width and a half, and a pixel.
  readonly property real inkFirst: drawable ? shown.points[0].x : 0
  readonly property real inkLast: drawable ? shown.points[shown.points.length - 1].x : 0
  readonly property real inkLeft: Math.max(0, pad + inkFirst * (width - pad * 2) - 3 * weight)
  readonly property real inkRight: Math.min(width, pad + inkLast * (width - pad * 2) + 4)
  // What is laid over the ink shows once the ink has drawn past it, and as a
  // chart bends into this one, over the second half (`RangeMarks`).
  readonly property real inkDrawn: curtain.width
  readonly property real marksShown: Math.max(0, Math.min(1, morph * 2 - 1))
  // Each side's wash adds the lightness the up colour's does at 16%
  // (`Tones.washAlpha`), so a down day's reads as strongly as an up day's.
  readonly property real aboveWash: Tones.washAlpha(aboveColor, upColor, ground, 0.16, 1)
  readonly property real belowWash: Tones.washAlpha(belowColor, upColor, ground, 0.16, 1)
  // The day's fade, at the day's far reach, by the same rule.
  readonly property real aboveFade: Tones.washAlpha(aboveColor, upColor, ground, 0.34, 1)
  readonly property real belowFade: Tones.washAlpha(belowColor, upColor, ground, 0.34, 1)

  onShownChanged: { base.requestPaint(); ink.requestPaint() }
  onGeometryChanged: marks.requestPaint()
  onBaselineColorChanged: { base.requestPaint(); ink.requestPaint() }
  onAboveWashChanged: ink.requestPaint()
  onBelowWashChanged: ink.requestPaint()
  onAboveFadeChanged: ink.requestPaint()
  onBelowFadeChanged: ink.requestPaint()
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

  // The sizes and inks the painter reads.
  function paintStyle(canvas) {
    return {
      width: canvas.width, height: canvas.height, pad: pad, weight: weight, dashUnit: dashUnit,
      hasBaseline: hasBaseline, baselineColor: baselineColor, aboveColor: aboveColor, belowColor: belowColor,
      aboveWash: aboveWash, belowWash: belowWash, aboveFade: aboveFade, belowFade: belowFade,
      hoursAlpha: hoursAlpha, asideAlpha: asideAlpha, rgba: function(r, g, b, a) { return Qt.rgba(r, g, b, a) }
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
      SmoothPaint.paintBase(ctx, root.shown, root.paintStyle(base))
    }
  }

  Item {
    id: curtain
    width: root.replayX >= 0 ? root.width * Math.min(1, root.replayX)
      : root.reveal >= 1 ? root.width : root.inkLeft + (root.inkRight - root.inkLeft) * Math.max(0, root.reveal)
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
        SmoothPaint.paintInk(ctx, root.shown, root.paintStyle(ink))
        root.lastShown = root.shown
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

  // How far the dot has bloomed at the open's bell, 0 to 1 (`bloom`).
  property real bloomed: 1
  function bloom() {
    if (!surfaceOpen) return
    bloomAnim.restart()
  }
  NumberAnimation { id: bloomAnim; target: root; property: "bloomed"; from: 0; to: 1; duration: Motion.duration(Style, 320); easing.type: Easing.OutCubic }
  // It ends once the halo's edge is within half a pixel of its place.
  onBloomedChanged: if (bloomAnim.running && (1 - bloomed) * 0.6 * 7 * weight < 0.5) {
    bloomAnim.stop()
    bloomed = 1
  }

  // Outside the canvas, so it ripples without repainting the line: three
  // ripples, about 6 s, when the mark plays (`LiveMark`). A range has no dot:
  // its last bar need not be the headline trade. It shows as the ink reaches
  // it, and while a chart bends into this one, only if the old one had one.
  // At the open it blooms on the bell's beat (`bloom`).
  Item {
    id: dot
    visible: root.day && root.lastPoint !== null && root.replayX < 0 && root.inkDrawn >= x
      && (root.morph >= 1 || root.dotRides)
    scale: 0.4 + 0.6 * root.bloomed
    opacity: 0.4 + 0.6 * root.bloomed
    x: root.lastPoint ? root.pad + root.lastPoint.x * (root.width - root.pad * 2) : 0
    y: root.lastPoint ? root.pad + root.lastPoint.y * (root.height - root.pad * 2) : 0

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
      onRunningChanged: if (!running) { halo.scale = 1; halo.opacity = 0.25 }

      ParallelAnimation {
        NumberAnimation { target: halo; property: "scale"; from: 1; to: 2.2; duration: Motion.duration(Style, 1400); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) }
        NumberAnimation { target: halo; property: "opacity"; from: 0.35; to: 0; duration: Motion.duration(Style, 1400); easing.type: Easing.Bezier; easing.bezierCurve: Motion.curve(Style) }
      }
      PauseAnimation { duration: Motion.duration(Style, 600) }
    }
  }

  LiveMark {
    live: root.live
    still: root.still
    // The dot comes as the ink reaches it, and rides a bend; its burst comes
    // as the draw-in or the bend ends, where the new chart's trade is.
    shown: dot.visible && root.reveal >= 1 && root.morph >= 1
    drawing: function() { return root.reveal < 1 || root.morph < 1 }
    surfaceOpen: root.surfaceOpen
    price: root.newestPrice
    burst: ripples
  }
}
