.pragma library
.import "Format.js" as Format
.import "History.js" as History
.import "Market.js" as Market
.import "Overnight.js" as Overnight
.import "Quote.js" as Quote

// Which chart a view shows (the day, or a range), and how it is laid out and
// scrubbed. Knows nothing of parsing, settings, or colour.

// The chart the view asks for, `symbol` on `range`, once it can be drawn:
// the day once its quote is in; for a US stock or ETF once Robinhood has said
// whether it trades it all day too (`allDay`, answers only, a failed one not
// all-day), and, for one it does, once the overnight feed has answered
// (`nights`, answers only), when the day is one trading day, the newest
// print's (`Overnight.dayChart`), and for one it does not, Yahoo's own day
// (`Overnight.sessionDay`); any other listing's is its quote's day, or the
// coming day a two-day answer holds once it has a print (`Quote.tailDay`):
// London's or Tokyo's stays the last until its first bar lands. A range
// once its history and the symbol's quote are, since the headline is never
// the last bar. A range takes the day too once it is in, for the newest
// price since the close, which its history ends on, as the price on top
// does (`History.withNewest`), and never waits for it.
// `quote` is Yahoo's, as it came: the headline and the day's figures. `day`
// is what the 1D chart draws and a scrub of it reads; `latest` is the
// newest print of all, for the line under the price, or null where the
// quote's own last print is it; `allDay`, whether Robinhood has said it
// trades the listing all day, so its nights trade (`Overnight.marketAsleep`).
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
  var chart = { symbol: symbol, range: range, quote: quote, day: quote && (Quote.tailDay(quote) || quote), latest: null,
    history: null, failed: false, allDay: false }
  if (quote && Overnight.hasOvernight(quote, calendars)) {
    // A listing never asked of Robinhood (`allDay` not given, as in a
    // harness that stubs the service) has Yahoo's own day.
    var tradability = allDay ? allDay[symbol] : { allDay: false }
    chart.allDay = !!tradability && tradability.allDay
    var night = nights[symbol]
    if (tradability && !tradability.allDay) chart.day = Overnight.sessionDay(quote)
    else if (tradability && night) {
      var built = Overnight.dayChart(quote, night, calendars)
      chart.day = built.day
      chart.latest = built.latest
    } else if (range === "1D") return null
  }
  if (range === "1D" || !quote) return chart
  var entry = histories[History.historyKey(symbol, range)]
  if (!entry) return null
  if (entry.history) chart.history = History.withNewest(entry.history, Overnight.newestPrint(quote, chart.latest, calendars))
  else chart.failed = true
  return chart
}

// Normalized [0..1] x/y for drawing. x runs along the day's axis
// (`chartSpan`): the day the response describes, from the pre-market open so
// the line arrives at the bell from where it actually came, stretching to
// hold post-market prints; or, for a US listing, its trading day
// (`Overnight.dayChart`, `Overnight.sessionDay`), laid out by print
// (`printFraction`). `ticks` mark the bell, and the night's edges.
// Prints outside a regular session are flagged `ext`; `brk` starts the line
// again across a break in the exchange's day (Tokyo's lunch, from its
// calendar in `calendars`: Yahoo sends 09:00 to 15:30 as one session; the
// point after it is flagged `lunch` too, so a scrub there draws no dot), and
// across the hours after a day that take no room (`axis.skip`), so no line
// crosses hours the market was shut. A quiet hour of a US night is no
// break: that day is laid out by print, where a quiet hour takes no room, so
// a gap there would read as missing prices. A thin night's trades
// (`axis.night`) are laid out by the clock, one line through them, so the
// hours between them are there to see. The vertical range
// holds every drawn print and the close the day is measured from
// (`Quote.dayBase`) where it is known, with headroom, so the baseline is
// always in view.
function chartGeometry(quote, calendars) {
  var pts = quote.points
  var axis = chartSpan(quote)
  var reg = quote.session.regular
  var lunches = reg ? Market.sessionBreaks(Market.calendarFor(calendars, quote), reg.start) : []
  var breaks = axis.skip && axis.skip.to > axis.skip.from ? lunches.concat([{ start: axis.skip.from, end: axis.skip.to }]) : lunches
  var across = function(gaps, a, b) {
    return gaps.some(function(gap) { return a <= gap.start && b >= gap.end })
  }
  // An unknown close (`Quote.knownPrice`) has no place on the scale and no
  // dashed line: the prints alone set it. Otherwise a null close draws a
  // baseline at zero, the day flattened on top of it.
  var base = Quote.dayBase(quote)
  var known = Format.isFiniteNumber(base)
  var lo = known ? base : (pts.length ? pts[0].p : 0)
  var hi = lo
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
      brk: !!prev && across(breaks, prev.t, pts[k].t),
      lunch: !!prev && across(lunches, prev.t, pts[k].t)
    })
  }
  var ticks = []
  for (var n = 0; n < axis.ticks.length; n++) {
    var x = tickFraction(quote, axis, axis.ticks[n])
    if (x > 0 && x < 1) ticks.push(x)
  }
  return {
    points: out,
    baselineY: known ? 1 - (base - lo) / (hi - lo) : null,
    ticks: ticks,
    lo: lo, hi: hi, start: axis.start, end: axis.end,
    day: true
  }
}

// The day's axis, where chartGeometry's x runs from and to, without the
// drawing: a scrub step asks it of every row. `ticks` are the times it marks.
// A quote with the coming day's pre-market after its day (`Quote.tailStart`)
// runs on to its newest print, the hours between its day and that
// pre-market, which nothing trades in, taking no room (`skip`).
function chartSpan(quote) {
  if (quote.axis) return quote.axis
  var reg = Quote.regularOrPrints(quote)
  var pts = quote.points
  var start = Math.min(pts.length ? pts[0].t : reg.start, reg.start)
  var end = Math.max(reg.end, pts.length ? pts[pts.length - 1].t : reg.end)
  var tail = Quote.tailStart(quote)
  if (tail === null) return { start: start, end: end, ticks: [reg.end] }
  return { start: start, end: end, ticks: [reg.end, tail], skip: end >= tail ? { from: Quote.dayEnd(quote), to: tail } : null }
}

function axisFraction(axis, t) {
  return clockRoom(axis, t) / Math.max(1, clockRoom(axis, axis.end))
}

// How much of the axis the clock has run from its start to `t`: all of
// it, but for the hours between a day's end and what trades after it
// (`axis.skip`), a weekend's, which take no room.
function clockRoom(axis, t) {
  var skipped = axis.skip ? Math.max(0, Format.clamp(t, axis.skip.from, axis.skip.to) - axis.skip.from) : 0
  return t - axis.start - skipped
}

// `clockRoom`'s inverse: the moment `room` along the axis.
function clockAt(axis, room) {
  var t = axis.start + room
  return axis.skip && t > axis.skip.from ? t + Math.max(0, axis.skip.to - axis.skip.from) : t
}

// A US listing's 1D is laid out by print (`axis.byPrint`), the way
// Robinhood's screen draws it: the day's prints so far stand evenly from the
// left edge to where the clock puts the newest, so hours nobody traded take
// no room and a thin name's morning is never an empty stretch; the hours to
// come run by the clock, and so does a thin night after the day
// (`axis.night`), where each trade stands at its own time. Any other day runs
// by the clock throughout.

// How many prints the day holds before a night after it: all of them
// without one. The night's come after them.
function dayPrints(quote, axis) {
  var pts = quote.points
  if (!axis.night) return pts.length
  var lo = 0, hi = pts.length
  while (lo < hi) {
    var mid = (lo + hi) >> 1
    if (pts[mid].t < axis.night.start) lo = mid + 1
    else hi = mid
  }
  return lo
}

// Where the clock puts the day's newest print, 0..1: the end of the prints'
// room. A day that is over (`axis.over`) fills the width, its newest print
// on the right edge, whatever its time: SHOP's last bar of Friday 23
// October was 19:05's.
function newestFraction(quote, axis) {
  var n = dayPrints(quote, axis)
  if (!n) return 0
  return axis.over ? 1 : Format.clamp(axisFraction(axis, quote.points[n - 1].t), 0, 1)
}

function printFraction(quote, axis, k) {
  var n = dayPrints(quote, axis)
  if (!axis.byPrint || k >= n) return axisFraction(axis, quote.points[k].t)
  return n > 1 ? newestFraction(quote, axis) * k / (n - 1) : newestFraction(quote, axis)
}

// The last print at or before `t`, -1 before the first.
function printIndexAt(quote, t) {
  var pts = quote.points
  var i = -1
  while (i + 1 < pts.length && pts[i + 1].t <= t) i++
  return i
}

// Where a tick at `t` sits: by print, halfway between the day's prints
// either side of it, and by the clock past the newest; -1 before the first.
// A day that is over has nothing past its newest print, on the right edge
// (`newestFraction`): a tick there sits on the edge, where none is drawn.
function tickFraction(quote, axis, t) {
  var pts = quote.points
  var n = dayPrints(quote, axis)
  if (axis.byPrint && axis.over && n && t > pts[n - 1].t) return 1
  if (!axis.byPrint || !n || t > pts[n - 1].t) return axisFraction(axis, t)
  var k = printIndexAt(quote, t - 1) + 1
  if (k === 0) return -1
  return newestFraction(quote, axis) * (k - 0.5) / Math.max(1, n - 1)
}

// The moment at `fraction` along the day: by print, the nearest of the
// day's prints up to its newest, and the nearest print up to the newest of
// a night after it; by the clock past them.
function timeAtFraction(quote, fraction) {
  var axis = chartSpan(quote)
  var pts = quote.points
  var f = Format.clamp(fraction, 0, 1)
  if (axis.byPrint && pts.length) {
    var n = dayPrints(quote, axis)
    var newest = newestFraction(quote, axis)
    if (n && f <= newest) return pts[Math.round((newest > 0 ? f / newest : 1) * (n - 1))].t
    if (f <= printFraction(quote, axis, pts.length - 1)) {
      var near = Math.max(0, n - 1)
      for (var k = near + 1; k < pts.length; k++) {
        if (Math.abs(printFraction(quote, axis, k) - f) < Math.abs(printFraction(quote, axis, near) - f)) near = k
      }
      return pts[near].t
    }
  }
  return Math.round(clockAt(axis, f * clockRoom(axis, axis.end)))
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
// print: by print, from one print to the next, a thin night's trades
// included; by the clock, five minutes a step.
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

// Interpolated normalized y for a normalized x, or null past the line and
// inside Tokyo's lunch (`lunch`), where the line lifts, so the scrub's dot
// leaves the gap as the line and the chime do.
function yAt(points, x) {
  if (!points || !points.length) return null
  if (x < points[0].x || x > points[points.length - 1].x) return null
  if (points.length === 1) return points[0].y
  for (var i = 1; i < points.length; i++) {
    if (points[i].x >= x) {
      var a = points[i - 1], b = points[i]
      if (b.lunch && x > a.x && x < b.x) return null
      var f = b.x === a.x ? 0 : (x - a.x) / (b.x - a.x)
      return a.y + (b.y - a.y) * f
    }
  }
  return null
}
