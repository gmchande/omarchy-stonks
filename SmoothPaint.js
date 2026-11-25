.pragma library

// How the smooth look paints a line on a 2D canvas, for the hero's chart
// (SmoothChart) and a row's (Sparkline). Each chart keeps what is its own:
// the hero its wash, ticks and lone trades' dots, a row its draw-in and its
// dots in one ink.

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
