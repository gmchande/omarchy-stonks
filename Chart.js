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
  var chart = { symbol: symbol, range: range, quote: quote, day: null, latest: null, history: null, failed: false, allDay: false }
  if (quote) {
    var drawn = dayDrawn(symbol, quote, nights, allDay, calendars)
    if (drawn.waiting && range === "1D") return null
    chart.day = drawn.day
    chart.latest = drawn.latest
    chart.allDay = drawn.allDay
  }
  if (range === "1D" || !quote) return chart
  var entry = histories[History.historyKey(symbol, range)]
  if (!entry) return null
  if (entry.history) chart.history = History.withNewest(entry.history, Overnight.newestPrint(quote, chart.latest, calendars, chart.day))
  else chart.failed = true
  return chart
}

// The day the 1D chart draws for `symbol`'s `quote`, { day, latest,
// allDay, waiting }, which a row's line and the pill's draw too, so all
// three show one day (`lineDay`): for a US stock or ETF Robinhood trades
// all day (`allDay`, its answers by symbol), the newest print's trading
// day with its night (`nights`, its answers, `Overnight.dayChart`), and
// `latest`, that newest print; for one it doesn't, Yahoo's own day
// (`Overnight.sessionDay`); while Robinhood hasn't answered either, Yahoo's
// day as it came, `waiting`. A listing never asked of Robinhood (`allDay`
// not given, as in a harness that stubs the service) has Yahoo's own day,
// with no prints. Any other listing's is its quote's day, or the coming day
// a two-day answer holds once it has a print (`Quote.tailDay`).
function dayDrawn(symbol, quote, nights, allDay, calendars) {
  var out = { day: Quote.tailDay(quote) || quote, latest: null, allDay: false, waiting: false }
  if (!Overnight.hasOvernight(quote, calendars)) return out
  var tradability = allDay ? allDay[symbol] : { allDay: false }
  var night = nights ? nights[symbol] : null
  out.allDay = !!tradability && tradability.allDay
  if (tradability && !tradability.allDay) out.day = Overnight.sessionDay(quote)
  else if (tradability && night) {
    var built = Overnight.dayChart(quote, night, calendars)
    out.day = built.day
    out.latest = built.latest
  } else out.waiting = true
  return out
}

// The day a row's line and the pill's draw: the 1D chart's (`dayDrawn`),
// or null while that day waits on Robinhood's answer, as the chart does, so
// a line draws once, in the shape it keeps until a new price changes it.
function lineDay(symbol, quote, nights, allDay, calendars) {
  var drawn = dayDrawn(symbol, quote, nights, allDay, calendars)
  return drawn.waiting ? null : drawn.day
}

// The newest price since the close of each of `symbols` that has one
// (`Overnight.newestPrint`), by symbol, measured from the dashed line of
// the day its chart draws (`dayDrawn`): from Yahoo's own prints (`quotes`)
// and, for one Robinhood trades all day (`allDay`, answers), its night's
// (`nights`, answers). While that day waits on Robinhood, Yahoo's own
// newest, on the day Yahoo's prints alone make (`Overnight.dayChart` with
// no answer): until 04:00 the day that closed, as the chart will draw it,
// so the answer brings only a newer price, never another footing.
function newestPrints(symbols, quotes, nights, allDay, calendars) {
  var out = {}
  for (var i = 0; i < symbols.length; i++) {
    var q = quotes[symbols[i]]
    if (!q || !Overnight.hasOvernight(q, calendars)) continue
    var drawn = dayDrawn(symbols[i], q, nights, allDay, calendars)
    if (drawn.waiting) drawn = Overnight.dayChart(q, NO_ANSWER, calendars)
    var newest = Overnight.newestPrint(q, drawn.latest, calendars, drawn.day)
    if (newest) out[symbols[i]] = newest
  }
  return out
}

// Robinhood's answer before it comes (`Overnight.overnightAnswer`'s shape).
var NO_ANSWER = { bars: [], from: null, through: null }

// Normalized [0..1] x/y for drawing. x runs along the day's axis
// (`chartSpan`) by the clock, each print at its time: the day the response
// describes, from the pre-market open so the line arrives at the bell from
// where it actually came, stretching to hold post-market prints; or, for a
// US listing, its trading day (`Overnight.dayChart`,
// `Overnight.sessionDay`), so a quiet hour shows as one and a finished
// day ends at its last print's time. `ticks` mark the bell, and the
// night's edges. Prints outside a regular session are flagged `ext`, and
// those drawn dim `dim`: the extended hours, or, on a day lit where it
// trades now (`litFrom`, `Overnight.litFrom`), every print before it.
// `brk` starts the line again across a break in the exchange's day (Tokyo's
// lunch, from its calendar in `calendars`: Yahoo sends 09:00 to 15:30 as
// one session; the point after it is flagged `lunch` too, so a scrub there
// draws no dot), and across the hours after a day that take no room
// (`axis.skip`), so no line crosses hours the market was shut. A quiet hour
// of a US night is no break: the line runs on through it to the next
// trade. The vertical range holds every drawn print and the close the day
// is measured from (`Quote.dayBase`) where it is known, with headroom, so
// the baseline is always in view.
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
  var lit = quote.litFrom !== undefined && quote.litFrom !== null
  var out = []
  for (var k = 0; k < pts.length; k++) {
    var session = Quote.pointSession(quote, pts[k])
    var prev = k > 0 ? pts[k - 1] : null
    out.push({
      x: axisFraction(axis, pts[k].t),
      y: 1 - (pts[k].p - lo) / (hi - lo),
      ext: session !== "reg",
      dim: lit ? pts[k].t < quote.litFrom : session !== "reg",
      brk: !!prev && across(breaks, prev.t, pts[k].t),
      lunch: !!prev && across(lunches, prev.t, pts[k].t)
    })
  }
  var ticks = []
  for (var n = 0; n < axis.ticks.length; n++) {
    var x = axisFraction(axis, axis.ticks[n])
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

// The moment at `fraction` along the day.
function timeAtFraction(quote, fraction) {
  var axis = chartSpan(quote)
  return Math.round(clockAt(axis, Format.clamp(fraction, 0, 1) * clockRoom(axis, axis.end)))
}

// Where the moment `t` sits along the day; -1 off the day.
function fractionAtTime(quote, t) {
  var axis = chartSpan(quote)
  if (t < axis.start || t > axis.end) return -1
  return axisFraction(axis, t)
}

// `t` moved `steps` along the day, five minutes a step, kept on it and
// short of `last`, the last print.
function stepTime(quote, t, steps, last) {
  var axis = chartSpan(quote)
  return Format.clamp(t + steps * 300, axis.start, last || axis.end)
}

// The newest bright point of a chart geometry, where the dot sits: the
// newest print of what trades now, else the regular session's last.
function lastLitPoint(geometry) {
  if (!geometry || !geometry.points) return null
  for (var i = geometry.points.length - 1; i >= 0; i--) {
    if (!geometry.points[i].dim) return geometry.points[i]
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
