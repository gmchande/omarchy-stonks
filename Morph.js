.pragma library
// How a chart turns into another when the stock changes: smooth's line bends
// from one into the other (`frame`), retro's columns change one at a time
// from the left (`wave`).
//
// Smooth reads each chart along its own trades, 0 at its first and 1 at its
// last, and stands both on every place either has a trade, so the line
// between two of them is straight in both and its blend is exact: the first
// frame is the old chart and the last the new, every trade of each in
// place. What each chart sets apart (its faint hours, the stretch with no
// trade, the break at a lunch, the closed day) is a stretch along its
// trades; the old one's shrinks and the new one's grows, so a look changes
// where it is, never all at once. Every frame is a chart the smooth painter
// draws as it draws any (`SmoothPaint.paintInk`), against one dashed line.

// A morph needs a trade in each chart. A chart of one trade bends as a line
// of no length at it, the old line shrinking into its dot as the dot grows
// (`lone`), or growing out of it.
function span(g) {
  if (!g || !g.points || g.points.length < 1) return null
  var a = g.points[0].x
  var b = g.points[g.points.length - 1].x
  return b > a || g.points.length === 1 ? { a: a, b: b } : null
}

function along(s, x) {
  return s.b > s.a ? (x - s.a) / (s.b - s.a) : 0
}

function lerp(a, b, t) {
  return a + (b - a) * t
}

// One chart read along its trades: each trade's place `u`, and the stretches
// it sets apart there. A flag (`faint`, `dim`, `ext`) holds before `lead`,
// after `trail`, and inside each of `inner`'s open stretches, which end at
// the unflagged trades either side, so the line between a flagged trade and
// the next is flagged too, as the painter's runs draw it. `gaps` are its
// breaks, open between the trades either side, and `holds` its stretches
// with no trade, from the trade before to the one after it.
function read(g, s) {
  var lone = g.points.length === 1
  var pts = lone ? [g.points[0], g.points[0]] : g.points
  var us = lone ? [0, 1] : pts.map(function(p) { return along(s, p.x) })
  var flags = {}
  ;["faint", "dim", "ext"].forEach(function(key) { flags[key] = stretches(pts, us, key) })
  var gaps = []
  var holds = []
  for (var i = 1; i < pts.length; i++) {
    if (pts[i].brk) gaps.push([us[i - 1], us[i]])
    else if (pts[i].untraded) holds.push([us[i - 1], us[i]])
  }
  return { g: Object.assign({}, g, { points: pts }), real: g, lone: lone, s: s, us: us, flags: flags, gaps: gaps, holds: holds }
}

function stretches(pts, us, key) {
  var first = -1
  var last = -1
  for (var i = 0; i < pts.length; i++) {
    if (pts[i][key]) continue
    if (first < 0) first = i
    last = i
  }
  // Flagged throughout: past both ends.
  if (first < 0) return { lead: 2, trail: 1, inner: [] }
  var inner = []
  for (var k = first + 1; k < last; k++) {
    if (!pts[k][key]) continue
    var from = k
    while (pts[k + 1][key]) k++
    inner.push([us[from - 1], us[k + 1]])
  }
  return { lead: first > 0 ? us[first] : 0, trail: last < pts.length - 1 ? us[last] : 1, inner: inner }
}

// Where `chart`'s line is at `u`, from its trade `k`, the first past `u`:
// held across a stretch with no trade, as the painter holds it, and straight
// across a break, so a break that closes leaves a line where it was.
function yBefore(chart, k, u) {
  var pts = chart.g.points
  if (pts[k].untraded) return pts[k - 1].y
  var f = (u - chart.us[k - 1]) / (chart.us[k] - chart.us[k - 1])
  return lerp(pts[k - 1].y, pts[k].y, f)
}

// Every place either chart has a trade, with both lines' heights there.
function places(a, b) {
  var u = [], ya = [], yb = []
  var i = 0, j = 0
  var na = a.us.length, nb = b.us.length
  while (i < na || j < nb) {
    var ua = i < na ? a.us[i] : Infinity
    var ub = j < nb ? b.us[j] : Infinity
    if (ua < ub) {
      u.push(ua); ya.push(a.g.points[i].y); yb.push(yBefore(b, j, ua)); i++
    } else if (ub < ua) {
      u.push(ub); ya.push(yBefore(a, i, ub)); yb.push(b.g.points[j].y); j++
    } else {
      u.push(ua); ya.push(a.g.points[i].y); yb.push(b.g.points[j].y); i++; j++
    }
  }
  return { u: u, ya: ya, yb: yb }
}

// The closed day set apart (`aside`) along a chart's trades. A chart without
// one has it shut where the other's touches the chart's edge.
function asideAlong(chart, aside, other) {
  var x = aside || (other.from <= 0 ? { from: other.from, to: other.from } : { from: other.to, to: other.to })
  var s = chart.s
  return { from: along(s, x.from), to: along(s, x.to), edge: x.to >= 1 }
}

// Null when either chart can't bend; `from` and `to` are geometries the
// smooth painter draws.
function plan(from, to) {
  var sa = span(from)
  var sb = span(to)
  if (!sa || !sb) return null
  var a = read(from, sa)
  var b = read(to, sb)
  var at = places(a, b)
  var aside = from.aside || to.aside
    ? { a: asideAlong(a, from.aside, to.aside), b: asideAlong(b, to.aside, from.aside) } : null
  return { a: a, b: b, u: at.u, ya: at.ya, yb: at.yb, aside: aside }
}

// The open stretches of `list` at `share` of their width, about their
// middles, as [from, to].
function shrunk(list, share) {
  var out = []
  if (share <= 0) return out
  for (var i = 0; i < list.length; i++) {
    var mid = (list[i][0] + list[i][1]) / 2
    var half = (list[i][1] - list[i][0]) / 2 * share
    out.push([mid - half, mid + half])
  }
  return out
}

// A hold ends at the trade the line steps to, so it shrinks toward it.
function toEnd(list, share) {
  var out = []
  if (share <= 0) return out
  for (var i = 0; i < list.length; i++) out.push([list[i][1] - (list[i][1] - list[i][0]) * share, list[i][1]])
  return out
}

function joined(list) {
  list.sort(function(p, q) { return p[0] - q[0] })
  var out = []
  for (var i = 0; i < list.length; i++) {
    var last = out[out.length - 1]
    if (last && list[i][0] <= last[1]) last[1] = Math.max(last[1], list[i][1])
    else out.push(list[i].slice())
  }
  return out
}

function inside(list, u) {
  for (var i = 0; i < list.length; i++) if (u > list[i][0] && u < list[i][1]) return true
  return false
}

// A hold covers the trade it ends at, where the line steps.
function held(list, u) {
  for (var i = 0; i < list.length; i++) if (u > list[i][0] && u <= list[i][1]) return true
  return false
}

// A flag's stretches `t` of the way: the old chart's leading and trailing
// ones move to the new one's, and those between shrink and grow.
function stretchesAt(fa, fb, t) {
  return { lead: lerp(fa.lead, fb.lead, t), trail: lerp(fa.trail, fb.trail, t), inner: shrunk(fa.inner, 1 - t).concat(shrunk(fb.inner, t)) }
}

function flagged(f, u) {
  return u < f.lead || u > f.trail || inside(f.inner, u)
}

function evenness(g) {
  if (typeof g.even === "number") return g.even
  return g.day && !g.aside ? 1 : 0
}

// The chart `t` of the way from `plan`'s old one to its new one, a frame of
// the eased motion.
function frame(p, t) {
  if (t <= 0) return p.a.real
  if (t >= 1) return p.b.real
  var a = p.a, b = p.b
  var gaps = joined(shrunk(a.gaps, 1 - t).concat(shrunk(b.gaps, t)))
  var holds = toEnd(a.holds, 1 - t).concat(toEnd(b.holds, t))
  var faint = stretchesAt(a.flags.faint, b.flags.faint, t)
  var dim = stretchesAt(a.flags.dim, b.flags.dim, t)
  var ext = stretchesAt(a.flags.ext, b.flags.ext, t)
  var xAt = function(u) { return lerp(a.s.a + u * (a.s.b - a.s.a), b.s.a + u * (b.s.b - b.s.a), t) }
  var yAt = function(k, u) {
    // Between places `k - 1` and `k`.
    var f = (u - p.u[k - 1]) / (p.u[k] - p.u[k - 1])
    return lerp(lerp(p.ya[k - 1], p.ya[k], f), lerp(p.yb[k - 1], p.yb[k], f), t)
  }
  // The line's places this frame: every place either chart has a trade, and
  // each edge of a stretch, so an edge glides between trades rather than
  // stepping from one to the next.
  var cuts = []
  ;[faint, dim, ext].forEach(function(f) {
    cuts.push(f.lead, f.trail)
    f.inner.forEach(function(s) { cuts.push(s[0], s[1]) })
  })
  holds.forEach(function(h) { cuts.push(h[0]) })
  gaps.forEach(function(s) { cuts.push(s[0], s[1]) })
  cuts = cuts.filter(function(c) { return c > 0 && c < 1 }).sort(function(x, y) { return x - y })
  var us = []
  var ys = []
  var c = 0
  for (var k = 0; k < p.u.length; k++) {
    for (; c < cuts.length && cuts[c] <= p.u[k]; c++) {
      if (cuts[c] < p.u[k] && cuts[c] > us[us.length - 1]) {
        us.push(cuts[c])
        ys.push(yAt(k, cuts[c]))
      }
    }
    us.push(p.u[k])
    ys.push(lerp(p.ya[k], p.yb[k], t))
  }
  // Places inside a break are left out, and the one at its far edge starts
  // the line again.
  var points = []
  var g = 0
  for (var i = 0; i < us.length; i++) {
    var u = us[i]
    while (g < gaps.length && gaps[g][1] < u) g++
    var gap = gaps[g]
    if (gap && u > gap[0] && u < gap[1]) continue
    var brk = !!gap && u === gap[1]
    points.push({
      x: xAt(u),
      y: ys[i],
      brk: brk,
      untraded: !brk && held(holds, u),
      faint: flagged(faint, u),
      dim: flagged(dim, u),
      ext: flagged(ext, u)
    })
  }
  var ticks = a.g.ticks.concat(b.g.ticks)
  var tickAlpha = a.g.ticks.map(function(x, i) { return (a.g.tickAlpha ? a.g.tickAlpha[i] : 1) * (1 - t) })
    .concat(b.g.ticks.map(function() { return t }))
  var aside = null
  if (p.aside) {
    var from = xAt(lerp(p.aside.a.from, p.aside.b.from, t))
    var to = p.aside.a.edge && p.aside.b.edge ? 1 : xAt(lerp(p.aside.a.to, p.aside.b.to, t))
    aside = { from: from, to: to }
  }
  // A close line only while both charts have one: a chart with none stays
  // in the line's own ink until the other is on screen whole.
  var baselined = isFinite(a.g.baselineY) && a.g.baselineY !== null && isFinite(b.g.baselineY) && b.g.baselineY !== null
  // A one-trade chart's dot, the size it has come to (`share`).
  var lone = []
  if (a.lone) lone.push({ point: points[0], share: 1 - t })
  if (b.lone) lone.push({ point: points[points.length - 1], share: t })
  return {
    points: points,
    baselineY: baselined ? lerp(a.g.baselineY, b.g.baselineY, t) : null,
    aside: aside,
    even: lerp(evenness(a.g), evenness(b.g), t),
    ticks: ticks,
    tickAlpha: tickAlpha,
    lone: lone,
    lo: b.g.lo, hi: b.g.hi, start: b.g.start, end: b.g.end,
    day: b.g.day
  }
}

// Retro's grid `front` columns into the wave: the new chart's columns left
// of it and the old one's from it on, each with its own dashed row, or none
// where its chart has no close (`based`), so every cell stands on the line
// drawn under it. The old one may be a wave itself, cut short by this one.
function wave(from, to, front) {
  if (front <= 0) return from
  if (front >= to.columns) return to
  var g = Object.assign({}, to, { levels: [], above: [], dim: [], faint: [], aside: [], baseRows: [], baseds: [] })
  for (var c = 0; c < to.columns; c++) {
    var src = c < front ? to : from
    g.levels[c] = src.levels[c]
    g.above[c] = src.above[c]
    g.dim[c] = src.dim[c]
    g.faint[c] = src.faint[c]
    g.aside[c] = src.aside ? src.aside[c] : c >= src.asideFrom && c < src.asideTo
    g.baseRows[c] = src.baseRows ? src.baseRows[c] : src.baseRow
    g.baseds[c] = src.baseds ? src.baseds[c] : src.based
  }
  // The lit cap waits for the wave to pass it.
  g.lastLit = to.lastLit < front ? to.lastLit : -1
  return g
}
