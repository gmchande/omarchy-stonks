.pragma library
.import "Calendar.js" as Calendar
.import "Format.js" as Format
.import "History.js" as History
.import "Market.js" as Market
.import "Overnight.js" as Overnight
.import "Quote.js" as Quote

// Which chart a view shows (the day, or a range), and how it is laid out and
// scrubbed. Knows nothing of parsing, settings, or colour.

// The chart a view shows, `symbol` on `range`, or null while it is on its way.
// The day waits for its quote and, where Robinhood may trade it all day, for
// Robinhood (`dayDrawn`); a range for its history and the quote, since the
// headline is never the last bar. A range ends on the day's newest price since
// the close, and never waits for it. `histories` holds answers only, so what
// is drawn stays while a refetch is out and after one fails. A failed first
// fetch is an answer: a quote's shows the symbol alone, and a range's has the
// day stand in (`failed`). `latest` is the newest trade of all, or null where
// the quote's own last trade is it.
function viewChart(symbol, range, quotes, entries, histories, nights, allDay, calendars, slideAt) {
  if (!symbol) return null
  var quote = quotes[symbol] || null
  var quoteFailed = !quote && !!entries[symbol] && entries[symbol].status === "failed"
  if (!quote && !quoteFailed) return null
  var chart = { symbol: symbol, range: range, quote: quote, day: null, latest: null, history: null, failed: false, allDay: false }
  if (quote) {
    var drawn = dayDrawn(symbol, quote, nights, allDay, calendars, slideAt)
    if (drawn.waiting && range === "1D") return null
    chart.day = drawn.day
    chart.latest = drawn.latest
    chart.allDay = drawn.allDay
  }
  if (range === "1D" || !quote) return chart
  var entry = histories[History.historyKey(symbol, range)]
  if (!entry) return null
  if (entry.history) {
    var trade = Overnight.newestTrade(quote, chart.latest, calendars, chart.day)
    chart.history = History.withNewest(entry.history, trade, trade ? Market.tradeClock(quote, trade.t, calendars) : null)
  } else chart.failed = true
  return chart
}

// The day the chart, a row's line and the pill's draw, so all three show one.
// For a US stock or ETF Robinhood trades all day, the newest trade's trading
// day with its night (`Overnight.dayChart`), its start slid by `slideAt`, the
// shell's clock five minutes at a time; for one it doesn't, Yahoo's own
// (`Overnight.sessionDay`); `waiting` until Robinhood says which. Without
// `allDay`, as in a harness that stubs the service, Yahoo's own. Any other
// listing's is its quote's day, or the coming day once it has a trade
// (`Quote.tailDay`): London's or Tokyo's stays the last until its first bar.
function dayDrawn(symbol, quote, nights, allDay, calendars, slideAt) {
  var out = { day: Quote.tailDay(quote) || quote, latest: null, allDay: false, waiting: false }
  if (!Overnight.hasOvernight(quote, calendars)) return out
  var tradability = allDay ? allDay[symbol] : { allDay: false }
  var night = nights ? nights[symbol] : null
  out.allDay = !!tradability && tradability.allDay
  if (tradability && !tradability.allDay) out.day = Overnight.sessionDay(quote)
  else if (tradability && night) {
    var built = Overnight.dayChart(quote, night, calendars, slideAt)
    out.day = built.day
    out.latest = built.latest
  } else out.waiting = true
  return out
}

// Null while the day waits on Robinhood, as the chart does, so a line draws
// once, in the shape it keeps until a new price changes it.
function lineDay(symbol, quote, nights, allDay, calendars, slideAt) {
  var drawn = dayDrawn(symbol, quote, nights, allDay, calendars, slideAt)
  return drawn.waiting ? null : drawn.day
}

// Measured from the dashed line of the day each chart draws. While that day
// waits on Robinhood, Yahoo's own trades make it. Until 04:00 that is the
// day that closed, as the chart will draw it, with its after hours counted
// as its own, until Robinhood's answer brings tonight's trade.
function newestTrades(symbols, quotes, nights, allDay, calendars) {
  var out = {}
  for (var i = 0; i < symbols.length; i++) {
    var newest = newestTradeOf(symbols[i], quotes[symbols[i]], nights, allDay, calendars)
    if (newest) out[symbols[i]] = newest
  }
  return out
}

// One listing's: it reads the listing's quote, its night's trades and reach,
// and Robinhood's word on whether it trades all day, and nothing else.
function newestTradeOf(symbol, quote, nights, allDay, calendars) {
  if (!quote || !Overnight.hasOvernight(quote, calendars)) return null
  var drawn = dayDrawn(symbol, quote, nights, allDay, calendars)
  if (drawn.waiting) drawn = Overnight.dayChart(quote, NO_ANSWER, calendars)
  return Overnight.newestTrade(quote, drawn.latest, calendars, drawn.day)
}

// Robinhood's answer before it comes (`Overnight.overnightAnswer`'s shape).
var NO_ANSWER = { bars: [], from: null, through: null }

// x runs by the clock along the day's axis (`chartSpan`): from the first trade
// or the open, whichever is earlier, so the line reaches the bell from where it
// came, to hold every trade; or, for a US listing, its trading day, so a quiet
// hour shows as one and a finished day ends at its last trade. `ext` marks
// trades outside the regular session, and `dim` those drawn dim: the extended
// hours, or on a day lit where it trades now (`Overnight.litFrom`), every trade
// before that. `brk` lifts the line across hours of the exchange's day that
// take room, such as Tokyo's lunch, which Yahoo sends inside one 09:00 to 15:30
// session. Hours that take no room (`axis.skip`), such as a weekend, are no
// break: the line runs across them, as through a quiet hour of a US night. The
// scale holds every trade and the close, so the baseline stays in view. Once
// tonight has traded, the dashed line steps at the bell to the close just
// gone (`Overnight.nightBell`), which the scale holds too: `step`.
function chartGeometry(quote, calendars) {
  var pts = quote.points
  var axis = chartSpan(quote)
  var reg = quote.session.regular
  var breaks = reg ? Calendar.sessionBreaks(Calendar.calendarFor(calendars, quote), reg.start) : []
  var across = function(a, b) {
    return breaks.some(function(gap) { return a <= gap.start && b >= gap.end })
  }
  // An unknown close has no place on the scale: as zero it would flatten the
  // day against a baseline.
  var base = Quote.dayBase(quote)
  var known = Format.isFiniteNumber(base)
  var bell = Overnight.nightBell(quote)
  var stepBase = bell !== null ? Quote.regularClose(quote) : null
  var lo = known ? base : (pts.length ? pts[0].p : 0)
  var hi = lo
  if (Format.isFiniteNumber(stepBase)) { lo = Math.min(lo, stepBase); hi = Math.max(hi, stepBase) }
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
      brk: !!prev && across(prev.t, pts[k].t)
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
    // Known apart from the day's: Yahoo can send the close without the one before.
    step: Format.isFiniteNumber(stepBase) ? { x: axisFraction(axis, bell), y: 1 - (stepBase - lo) / (hi - lo) } : null,
    ticks: ticks,
    lo: lo, hi: hi, start: axis.start, end: axis.end,
    day: true
  }
}

// The dashed line's height at `x`: the step's height once `x` is past the
// bell, the day's before it, and null where there is no line.
function baseAt(geometry, x) {
  return geometry.step && x >= geometry.step.x ? geometry.step.y : geometry.baselineY
}

// Without the drawing: a scrub step asks it of every row. A quote with the
// coming day's pre-market after its day runs on to its newest trade, the hours
// between taking no room (`skip`).
function chartSpan(quote) {
  if (quote.axis) return quote.axis
  var reg = Quote.regularOrTrades(quote)
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

// The hours `axis.skip` covers take no room.
function clockRoom(axis, t) {
  var skipped = axis.skip ? Math.max(0, Format.clamp(t, axis.skip.from, axis.skip.to) - axis.skip.from) : 0
  return t - axis.start - skipped
}

// `clockRoom`'s inverse: the moment `room` along the axis. Where the skipped
// hours join, the later side's, where trading resumes.
function clockAt(axis, room) {
  var t = axis.start + room
  return axis.skip && t >= axis.skip.from ? t + Math.max(0, axis.skip.to - axis.skip.from) : t
}

function timeAtFraction(quote, fraction) {
  var axis = chartSpan(quote)
  return Math.round(clockAt(axis, Format.clamp(fraction, 0, 1) * clockRoom(axis, axis.end)))
}

// -1 off the day.
function fractionAtTime(quote, t) {
  var axis = chartSpan(quote)
  if (t < axis.start || t > axis.end) return -1
  return axisFraction(axis, t)
}

// Five minutes of room a step, so one crosses the hours that take none, kept
// on the day and no later than `last`, the last trade.
function stepTime(quote, t, steps, last) {
  var axis = chartSpan(quote)
  return Format.clamp(clockAt(axis, clockRoom(axis, t) + steps * 300), axis.start, last || axis.end)
}

// Where the dot sits: the newest trade of what trades now, else the regular
// session's last.
function lastLitPoint(geometry) {
  if (!geometry || !geometry.points) return null
  for (var i = geometry.points.length - 1; i >= 0; i--) {
    if (!geometry.points[i].dim) return geometry.points[i]
  }
  return null
}

// Null past the line and across a break, where the line lifts.
function yAt(points, x) {
  if (!points || !points.length) return null
  if (x < points[0].x || x > points[points.length - 1].x) return null
  if (points.length === 1) return points[0].y
  for (var i = 1; i < points.length; i++) {
    if (points[i].x >= x) {
      var a = points[i - 1], b = points[i]
      if (b.brk && x > a.x && x < b.x) return null
      var f = b.x === a.x ? 0 : (x - a.x) / (b.x - a.x)
      return a.y + (b.y - a.y) * f
    }
  }
  return null
}
