.pragma library

// How the smooth look paints a line on a 2D canvas, for the hero's chart
// (SmoothChart) and a row's (Sparkline). Each chart keeps what is its own:
// the hero its wash, ticks and lone trades' dots, a row its draw-in and its
// dots in one ink.

// The hero's line and its wash, in `s`, the chart's sizes and inks and its
// way to make a colour (`s.rgba`, Qt's in QML). A range, or a day set apart
// (`g.aside`), keeps a flat wash under its session, up to the last regular
// trade, and none under the stretch the number beside the chart doesn't
// count. Any other day's (`even`) fades under every trade, so no hour of it
// takes an edge. A range has no extended trades. A chart turning into
// another (`Morph.frame`) is part way between the two (`g.even`, 0 to 1).
function paintInk(ctx, g, s) {
  var pad = s.pad
  var pts = g.points
  var w = s.width - pad * 2
  var h = s.height - pad * 2
  var aside = g.aside
  var even = g.day === true && !aside
  var mixed = typeof g.even === "number"
  var fadeShare = mixed ? g.even : even ? 1 : 0
  var all = function() { return true }
  var lastRegular = -1
  for (var n = 0; n < pts.length; n++) if (!pts[n].ext) lastRegular = n
  var washes = []
  if (fadeShare > 0) washes.push({ runs: runs(pts, all), fade: true })
  if (fadeShare < 1) washes.push({ runs: runs(pts.slice(0, lastRegular + 1), all), fade: false })
  var parts = asideParts(aside, pad, w, s.width)
  var clipped = parts.length > 1
  var by = s.hasBaseline ? pad + g.baselineY * h : null

  for (var p = 0; by !== null && p < parts.length; p++) {
    if (parts[p].aside || parts[p].to <= parts[p].from) continue
    ctx.save()
    if (clipped) clipTo(ctx, parts[p], s.height)
    for (var k = 0; k < washes.length; k++) {
      ctx.fillStyle = washes[k].fade ? fade(ctx, pts, by, pad, h, s, fadeShare)
        : sides(ctx, by, s, s.aboveWash * (1 - fadeShare), s.belowWash * (1 - fadeShare))
      var filled = washes[k].runs
      for (var r = 0; r < filled.length; r++) {
        var run = filled[r]
        if (run.length < 2) continue
        ctx.beginPath()
        ctx.moveTo(pad + run[0].x * w, by)
        for (var i = 0; i < run.length; i++) {
          if (i > 0 && run[i].untraded) ctx.lineTo(pad + run[i].x * w, pad + run[i - 1].y * h)
          ctx.lineTo(pad + run[i].x * w, pad + run[i].y * h)
        }
        ctx.lineTo(pad + run[run.length - 1].x * w, by)
        ctx.closePath()
        ctx.fill()
      }
    }
    ctx.restore()
  }

  ctx.lineJoin = "round"
  ctx.lineCap = "round"
  ctx.lineWidth = 2 * s.weight
  // The whole series in the lighter ink, then the rest over it at full
  // (`faint`), so the hours around the session read as the quieter part of
  // one line. The stretch the number beside the chart doesn't count keeps
  // the sides' colours, fainter than the dim ink and half as thick, so it
  // reads apart from tonight's dim hours on a dark ground, where a fainter
  // shade alone runs into them.
  var lighter = mixed ? 0.45 + (s.hoursAlpha - 0.45) * fadeShare : even ? s.hoursAlpha : 0.45
  for (var q = 0; q < parts.length; q++) {
    if (parts[q].to <= parts[q].from) continue
    ctx.save()
    if (clipped) clipTo(ctx, parts[q], s.height)
    if (parts[q].aside) {
      ctx.lineWidth = s.weight
      ctx.strokeStyle = sides(ctx, by, s, s.asideAlpha, s.asideAlpha)
      strokeRuns(ctx, runs(pts, all), pad, w, h, s.dashUnit)
    } else {
      ctx.strokeStyle = sides(ctx, by, s, lighter, lighter)
      strokeRuns(ctx, runs(pts, all), pad, w, h, s.dashUnit)
      ctx.strokeStyle = sides(ctx, by, s, 1, 1)
      strokeRuns(ctx, runs(pts, function(pt) { return !pt.faint }), pad, w, h, s.dashUnit)
    }
    ctx.restore()
  }

  if (s.hasBaseline) strokeTicks(ctx, g, s, false)
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

// One ink for both sides: stroking each line twice, clipped to each side,
// doubles the paint. The dim ink is one share of its own colour: it reads
// against the full line beside it, not against the other side. With no
// line to stand against (`by` null), the baseline's ink.
function sides(ctx, by, s, aboveAlpha, belowAlpha) {
  var c = s.baselineColor
  if (by === null) return s.rgba(c.r, c.g, c.b, aboveAlpha)
  var a = s.aboveColor
  var b = s.belowColor
  return splitInk(ctx, s.height, by, s.rgba(a.r, a.g, a.b, aboveAlpha), s.rgba(b.r, b.g, b.b, belowAlpha))
}

// The day's wash: strongest at its far reach on each side, clear at the
// dashed line, so it shows where the move went. Two stops at one offset
// merge, so the second sits a hair below.
function fade(ctx, pts, by, pad, h, s, share) {
  var top = by - 1
  var bottom = by + 1
  for (var i = 0; i < pts.length; i++) {
    top = Math.min(top, pad + pts[i].y * h)
    bottom = Math.max(bottom, pad + pts[i].y * h)
  }
  var stop = (by - top) / (bottom - top)
  var a = s.aboveColor
  var b = s.belowColor
  var g = ctx.createLinearGradient(0, top, 0, bottom)
  g.addColorStop(0, s.rgba(a.r, a.g, a.b, s.aboveFade * share))
  g.addColorStop(stop, s.rgba(a.r, a.g, a.b, 0))
  g.addColorStop(Math.min(1, stop + 0.0001), s.rgba(b.r, b.g, b.b, 0))
  g.addColorStop(1, s.rgba(b.r, b.g, b.b, s.belowFade * share))
  return g
}

// A lone trade, a day's only one or one beside a break, is a dot three
// times the line's width, so it reads at a glance. It never breathes: that
// is the live dot's alone.
function strokeRuns(ctx, lines, pad, w, h, dashUnit) {
  for (var r = 0; r < lines.length; r++) {
    var line = lines[r]
    if (line.length > 1) {
      strokeLine(ctx, line, pad, w, h, dashUnit)
      continue
    }
    ctx.fillStyle = ctx.strokeStyle
    ctx.beginPath()
    ctx.arc(pad + line[0].x * w, pad + line[0].y * h, ctx.lineWidth * 1.5, 0, Math.PI * 2)
    ctx.fill()
  }
}

// The dashed line and the ticks in hours still to come, which stand with it
// before the line reaches them.
function paintBase(ctx, g, s) {
  var h = s.height - s.pad * 2
  strokeBaseline(ctx, s.pad, s.width - s.pad, s.pad + g.baselineY * h, s.baselineColor,
    s.weight, [3 * s.dashUnit, 4 * s.dashUnit])
  strokeTicks(ctx, g, s, true)
}

// Ticks the line has reached draw in with it; those ahead, in hours still
// to come, are there with the baseline. A chart turning into another fades
// the old one's out and the new one's in (`g.tickAlpha`).
function strokeTicks(ctx, g, s, ahead) {
  var w = s.width - s.pad * 2
  var h = s.height - s.pad * 2
  var inkLast = g.points.length ? g.points[g.points.length - 1].x : 0
  var c = s.baselineColor
  ctx.strokeStyle = c
  ctx.lineWidth = s.weight
  for (var k = 0; k < g.ticks.length; k++) {
    if ((g.ticks[k] > inkLast) !== ahead) continue
    if (g.tickAlpha) ctx.strokeStyle = s.rgba(c.r, c.g, c.b, c.a * g.tickAlpha[k])
    var cx = s.pad + g.ticks[k] * w
    var cy = s.pad + g.baselineY * h
    ctx.beginPath()
    ctx.moveTo(cx, cy - 4 * s.weight)
    ctx.lineTo(cx, cy + 4 * s.weight)
    ctx.stroke()
  }
}

// The chart cut across where what the number beside it doesn't count
// (`aside`, 0..1 along the axis) begins and ends, each part with whether
// it is that stretch. Without one, the chart whole.
function asideParts(aside, pad, w, width) {
  if (!aside) return [{ from: 0, to: width, aside: false }]
  var gx0 = aside.from <= 0 ? 0 : pad + aside.from * w
  var gx1 = aside.to >= 1 ? width : pad + aside.to * w
  return [{ from: 0, to: gx0, aside: false }, { from: gx0, to: gx1, aside: true }, { from: gx1, to: width, aside: false }]
}

// What follows draws only within `part`, until the context is restored.
function clipTo(ctx, part, height) {
  ctx.beginPath()
  ctx.rect(part.from, 0, part.to - part.from, height)
  ctx.clip()
}

// One ink for both sides of the dashed line at `by`: `above` over it and
// `below` under it. Two stops at one offset merge, so the second sits a
// hair below.
function splitInk(ctx, height, by, above, below) {
  var stop = Math.max(0, Math.min(1, by / height))
  var g = ctx.createLinearGradient(0, 0, 0, height)
  g.addColorStop(stop, above)
  g.addColorStop(Math.min(1, stop + 0.0001), below)
  return g
}

// The dashed line at the price the change counts from. Round ends on every
// paint: the context keeps the last paint's cap, so otherwise a first paint
// draws square dashes and repaints round.
function strokeBaseline(ctx, x0, x1, y, color, width, dash) {
  ctx.strokeStyle = color
  ctx.lineWidth = width
  ctx.lineCap = "round"
  ctx.setLineDash(dash)
  ctx.beginPath()
  ctx.moveTo(x0, y)
  ctx.lineTo(x1, y)
  ctx.stroke()
  ctx.setLineDash([])
}

// The line through `pts`, in the context's stroke. A break (`brk`) lifts
// the pen, and across a stretch with no trade (`untraded`) the line holds
// the trade before it, dotted, and steps to the next: dots the line's width
// across, a width apart, since the dashes count in its widths, and stretch
// by `dashUnit` in the screenshot as the baseline's do (`ShareCard`).
function strokeLine(ctx, pts, pad, w, h, dashUnit) {
  var held = []
  ctx.beginPath()
  for (var i = 0; i < pts.length; i++) {
    var x = pad + pts[i].x * w
    var y = pad + pts[i].y * h
    if (i === 0 || pts[i].brk) ctx.moveTo(x, y)
    else if (pts[i].untraded) {
      var heldY = pad + pts[i - 1].y * h
      held.push({ from: pad + pts[i - 1].x * w, to: x, y: heldY })
      ctx.moveTo(x, heldY)
      ctx.lineTo(x, y)
    } else ctx.lineTo(x, y)
  }
  ctx.stroke()
  if (!held.length) return
  ctx.setLineDash([0.01, 2 * dashUnit])
  ctx.beginPath()
  for (var d = 0; d < held.length; d++) {
    ctx.moveTo(held[d].from, held[d].y)
    ctx.lineTo(held[d].to, held[d].y)
  }
  ctx.stroke()
  ctx.setLineDash([])
}
