.import "Format.js" as Format
.import "Market.js" as Market
.import "Overnight.js" as Overnight
.import "Quote.js" as Quote

// Which chart a view shows (the day, or a range), and how it is laid out and
// scrubbed. Knows nothing of parsing, settings, or colour.

// The chart the view asks for, `symbol` on `range`, once it can be drawn:
// the day once its quote is in; for a US stock or ETF once Robinhood has said
// whether it trades it all day too (`allDay`, answers only, a failed one not
// all-day), and, for one it does, once the overnight feed has answered
// (`nights`, answers only), when the day is the New York calendar day of its
// newest print (`Overnight.dayChart`), and for one it does not, Yahoo's own
// day (`Overnight.sessionDay`); a range once its history and the symbol's
// quote are, since the headline is never the last bar. A range takes the day
// too once it is in, for the night's print under the price, and never waits
// for it.
// `quote` is Yahoo's, as it came: the headline and the day's figures. `day`
// is what the 1D chart draws and a scrub of it reads, the quote itself
// outside the US; `latest` is the newest print of all, for the line under
// the price, or null where the quote's own last print is it; `allDay`,
// whether Robinhood has said it trades the listing all day, so its nights
// trade (`Overnight.marketAsleep`).
// `histories` holds answers only (HistoryFeed): history in hand is drawn
// while a refetch is out and after one fails. A first fetch that failed is
// an answer too: a quote's, on any range, shows the symbol with no quote and
// no chart; a range's has the day stand in (`failed`), through a retry until
// an answer lands. Null while the chart is on its way.
function viewChart(symbol, range, quotes, entries, histories, nights, allDay, calendars) {
  if (!symbol) return null
  var quote = quotes[symbol] || null
  var quoteFailed = !quote && !!entries[symbol] && entries[symbol].status === "failed"
  if (!quote && !quoteFailed) return null
  var chart = { symbol: symbol, range: range, quote: quote, day: quote, latest: null, history: null, failed: false, allDay: false }
  if (quote && Overnight.hasOvernight(quote, calendars)) {
    // A listing never asked of Robinhood (`allDay` null, a preview outside
    // All) has Yahoo's own day.
    var tradability = allDay ? allDay[symbol] : { allDay: false }
    chart.allDay = !!tradability && tradability.allDay
    var night = nights[symbol]
    if (tradability && !tradability.allDay) chart.day = Overnight.sessionDay(quote)
    else if (tradability && night) {
      var built = Overnight.dayChart(quote, night.bars, calendars)
      chart.day = built.day
      chart.latest = built.latest
    } else if (range === "1D") return null
  }
  if (range === "1D" || !quote) return chart
  var entry = histories[symbol + "|" + range]
  if (!entry) return null
  if (entry.history) chart.history = entry.history
  else chart.failed = true
  return chart
}

// Normalized [0..1] x/y for drawing. x runs along the day's axis
// (`chartSpan`): the day the response describes, from the pre-market open so
// the line arrives at the bell from where it actually came, stretching to
// hold post-market prints; or, for a US listing, its calendar day
// (`Overnight.dayChart`) or Yahoo's own day (`Overnight.sessionDay`), laid
// out by print (`printFraction`). `ticks` mark the bell, and the night's
// edges.
// Prints outside a regular session are flagged `ext`; `brk` starts the line
// again after a quiet hour across a night, and across a break in the
// exchange's day (Tokyo's lunch, from its calendar in `calendars`: Yahoo
// sends 09:00 to 15:30 as one session), so no line crosses hours nobody
// traded. The vertical range holds every drawn print and the previous close,
// with headroom, so the baseline is always in view.
function chartGeometry(quote, calendars) {
  var pts = quote.points
  var axis = chartSpan(quote)
  var reg = quote.session.regular
  var breaks = reg ? Market.sessionBreaks(Market.calendarFor(calendars, quote), reg.start) : []
  var acrossBreak = function(a, b) {
    return breaks.some(function(gap) { return a <= gap.start && b >= gap.end })
  }
  var lo = quote.prevClose, hi = quote.prevClose
  for (var j = 0; j < pts.length; j++) {
    if (pts[j].p < lo) lo = pts[j].p
    if (pts[j].p > hi) hi = pts[j].p
  }
  var pad = (hi - lo) * 0.08 || 0.5
  lo -= pad; hi += pad
  var out = []
  for (var k = 0; k < pts.length; k++) {
    var session = Quote.pointSession(quote, pts[k])
    var prev = k > 0 ? pts[k - 1] : null
    out.push({
      x: printFraction(quote, axis, k),
      y: 1 - (pts[k].p - lo) / (hi - lo),
      ext: session !== "reg",
      brk: !!prev && ((pts[k].t - prev.t > 60 * 60
        && (session === "overnight" || Quote.pointSession(quote, prev) === "overnight")) || acrossBreak(prev.t, pts[k].t))
    })
  }
  var ticks = []
  for (var n = 0; n < axis.ticks.length; n++) {
    var x = tickFraction(quote, axis, axis.ticks[n])
    if (x > 0 && x < 1) ticks.push(x)
  }
  return {
    points: out,
    baselineY: 1 - (quote.prevClose - lo) / (hi - lo),
    ticks: ticks,
    lo: lo, hi: hi, start: axis.start, end: axis.end,
    day: true
  }
}

// The day's axis, where chartGeometry's x runs from and to, without the
// drawing: a scrub step asks it of every row. `ticks` are the times it marks.
function chartSpan(quote) {
  if (quote.axis) return quote.axis
  var reg = Quote.regularOrPrints(quote)
  var pts = quote.points
  return {
    start: Math.min(pts.length ? pts[0].t : reg.start, reg.start),
    end: Math.max(reg.end, pts.length ? pts[pts.length - 1].t : reg.end),
    ticks: [reg.end]
  }
}

function axisFraction(axis, t) {
  return (t - axis.start) / Math.max(1, axis.end - axis.start)
}

// A US listing's 1D is laid out by print (`axis.byPrint`), the way
// Robinhood's screen draws it: the prints so far stand evenly from the left
// edge to where the clock puts the newest, so hours nobody traded take no
// room and a thin name's morning is never an empty stretch; the hours to
// come run by the clock. Any other day runs by the clock throughout.

// Where the clock puts the newest print, 0..1: the end of the prints' room.
function newestFraction(quote, axis) {
  var pts = quote.points
  return pts.length ? Format.clamp(axisFraction(axis, pts[pts.length - 1].t), 0, 1) : 0
}

// Where print `k` sits.
function printFraction(quote, axis, k) {
  if (!axis.byPrint) return axisFraction(axis, quote.points[k].t)
  var last = quote.points.length - 1
  return last > 0 ? newestFraction(quote, axis) * k / last : newestFraction(quote, axis)
}

// The last print at or before `t`, -1 before the first.
function printIndexAt(quote, t) {
  var pts = quote.points
  var i = -1
  while (i + 1 < pts.length && pts[i + 1].t <= t) i++
  return i
}

// Where a tick at `t` sits: by print, halfway between the prints either side
// of it, and by the clock past the newest print; -1 before the first.
function tickFraction(quote, axis, t) {
  var pts = quote.points
  if (!axis.byPrint || !pts.length || t > pts[pts.length - 1].t) return axisFraction(axis, t)
  var k = printIndexAt(quote, t - 1) + 1
  if (k === 0) return -1
  return newestFraction(quote, axis) * (k - 0.5) / Math.max(1, pts.length - 1)
}

// The moment at `fraction` along the day: by print, the nearest print, up to
// the newest; by the clock past it.
function timeAtFraction(quote, fraction) {
  var axis = chartSpan(quote)
  var pts = quote.points
  var f = Format.clamp(fraction, 0, 1)
  if (axis.byPrint && pts.length) {
    var newest = newestFraction(quote, axis)
    if (f <= newest) return pts[Math.round((newest > 0 ? f / newest : 1) * (pts.length - 1))].t
  }
  return Math.round(axis.start + f * (axis.end - axis.start))
}

// Where the moment `t` sits along the day: by print, at the print it reads,
// the last at or before it; -1 off the day.
function fractionAtTime(quote, t) {
  var axis = chartSpan(quote)
  if (t < axis.start || t > axis.end) return -1
  var pts = quote.points
  if (axis.byPrint && pts.length && t <= pts[pts.length - 1].t) return printFraction(quote, axis, Math.max(0, printIndexAt(quote, t)))
  return axisFraction(axis, t)
}

// `t` moved `steps` along the day, kept on it and short of `last`, the last
// print: by print, from one print to the next; by the clock, five minutes a
// step.
function stepTime(quote, t, steps, last) {
  var axis = chartSpan(quote)
  var pts = quote.points
  if (axis.byPrint && pts.length) {
    var limit = Math.max(0, printIndexAt(quote, last || axis.end))
    return pts[Format.clamp(Math.max(0, printIndexAt(quote, t)) + steps, 0, limit)].t
  }
  return Format.clamp(t + steps * 300, axis.start, last || axis.end)
}

// The last regular-session point of a chart geometry, where the dot sits.
function lastRegularPoint(geometry) {
  if (!geometry || !geometry.points) return null
  for (var i = geometry.points.length - 1; i >= 0; i--) {
    if (!geometry.points[i].ext) return geometry.points[i]
  }
  return null
}

// Interpolated normalized y for a normalized x, or null past the line.
function yAt(points, x) {
  if (!points || !points.length) return null
  if (x < points[0].x || x > points[points.length - 1].x) return null
  if (points.length === 1) return points[0].y
  for (var i = 1; i < points.length; i++) {
    if (points[i].x >= x) {
      var a = points[i - 1], b = points[i]
      var f = b.x === a.x ? 0 : (x - a.x) / (b.x - a.x)
      return a.y + (b.y - a.y) * f
    }
  }
  return null
}
