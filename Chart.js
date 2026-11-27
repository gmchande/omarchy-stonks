.pragma library
.import "Calendar.js" as Calendar
.import "CarriedClose.js" as CarriedClose
.import "Format.js" as Format
.import "History.js" as History
.import "Market.js" as Market
.import "Overnight.js" as Overnight
.import "Day.js" as Day
.import "Quote.js" as Quote

// Which chart a view shows (the day, or a range), and how it is laid out and
// scrubbed. Knows nothing of parsing, settings, or colour.

// The chart a view shows, `symbol` on `range`, or null while it is on its way.
// The day waits for its quote and, for a US stock or ETF, for Robinhood's
// trades (`dayDrawn`); a range for its history and the quote, since the
// headline is never the last bar. A range starts at the close before it, at
// its time by the listing's calendar (`History.withStart`), and ends on the
// day's newest price since the close, and never waits for it. `histories`
// holds answers only, so what is drawn stays while a refetch is out and after
// one fails. A failed first fetch is an answer: a quote's shows the symbol
// alone, and a range's has the day stand in (`failed`). `latest` is the
// newest trade of all, or null where the quote's own last trade is it.
function viewChart(symbol, range, quotes, entries, histories, nights, calendars, dayClock, lastTrades) {
  if (!symbol) return null
  var quote = quotes[symbol] || null
  var quoteFailed = !quote && !!entries[symbol] && entries[symbol].status === "failed"
  if (!quote && !quoteFailed) return null
  var chart = { symbol: symbol, range: range, quote: quote, day: null, latest: null, history: null, failed: false, tradesAtNight: false }
  if (quote) {
    var drawn = dayDrawn(symbol, quote, nights, calendars, dayClock)
    if (drawn.waiting && range === "1D") return null
    if (drawn.waiting && lastTrades) {
      var quoted = Overnight.quotedNight(lastTrades[symbol], Overnight.overnightMarket(calendars))
      if (quoted) {
        var built = Day.dayChart(CarriedClose.heldDay(quote, null, true) || quote, quoted, calendars, dayClock)
        drawn = { day: built.day, latest: built.latest, tradesAtNight: true, waiting: false }
      }
    }
    chart.day = drawn.day
    chart.latest = drawn.latest
    chart.tradesAtNight = drawn.tradesAtNight
  }
  if (range === "1D" || !quote) return chart
  var entry = histories[History.historyKey(symbol, range)]
  if (!entry) return null
  if (entry.history) {
    var trade = Overnight.newestTrade(quote, chart.latest, calendars, chart.day)
    // On a listing's first day, Yahoo counts every range from its offer price.
    var offered = Quote.listingDay(quote) && Quote.sameClose(entry.history.baseline, quote.prevClose)
    var history = offered ? Object.assign({}, entry.history, { offered: true }) : entry.history
    var first = history.bars[0]
    var closeAt = first ? Calendar.closeBefore(Calendar.calendarFor(calendars, quote), first.t) : null
    chart.history = History.withStart(History.withNewest(history, trade, trade ? Market.tradeClock(quote, trade.t, calendars) : null),
      closeAt, closeAt !== null ? Market.tradeClock(quote, closeAt, calendars) : null)
  } else chart.failed = true
  return chart
}

// The day the chart, a row's line and the pill's draw, so all three show one.
// For a US stock or ETF, the trading day whose open has come by `dayClock`,
// the shell's clock five minutes at a time, from 04:00, with what has
// traded since its end joined, running on to that clock, until the next
// open: from Yahoo's day and Robinhood's trades where those show it trading
// at night (`Overnight.tradesAtNight`, `Day.dayChart`); for one with no
// night trades, Yahoo's own and its coming pre-market (`Day.sessionDay`);
// `waiting` until Robinhood's trades come. Without `nights`, as in a
// harness that stubs the service, Yahoo's own. Any other listing's is its
// quote's day, or the coming day once it has a trade (`Quote.tailDay`). Any
// listing's, London's, Tokyo's or a US stock's, stays the last until its
// first bar, then holds it through the new day's first minutes
// (`CarriedClose.heldDay`).
function dayDrawn(symbol, quote, nights, calendars, dayClock) {
  var us = Overnight.hasOvernight(quote, calendars)
  var night = us && nights ? nights[symbol] : null
  var atNight = !!night && Overnight.tradesAtNight(night, Calendar.calendarFor(calendars, quote))
  var held = CarriedClose.heldDay(quote, atNight ? night.bars : null, us)
  var out = { day: Quote.tailDay(quote) || held || quote, latest: null, tradesAtNight: atNight, waiting: false }
  if (!us) return out
  if (atNight) {
    var built = Day.dayChart(held || quote, night, calendars, dayClock)
    out.day = built.day
    out.latest = built.latest
  } else if (night || !nights) out.day = Day.sessionDay(held || quote, dayClock)
  else out.waiting = true
  return out
}

// Null while the day waits on Robinhood, as the chart does, so a line draws
// once, in the shape it keeps until a new price changes it.
function lineDay(symbol, quote, nights, calendars, dayClock) {
  var drawn = dayDrawn(symbol, quote, nights, calendars, dayClock)
  return drawn.waiting ? null : drawn.day
}

// A listing's newest trade, measured from the dashed line of the day its
// chart draws. While a listing out of sight waits on Robinhood's fuller
// trades, its quote's night trade (`lastTrades`) stands in if tonight
// traded, else Yahoo's own trades. It reads the listing's quote, its
// night's trades and reach, and its last trade, and nothing else.
function newestTradeOf(symbol, quote, nights, calendars, lastTrades) {
  if (!quote || !Overnight.hasOvernight(quote, calendars)) return null
  var drawn = dayDrawn(symbol, quote, nights, calendars)
  if (drawn.waiting) {
    var quoted = lastTrades ? Overnight.quotedNight(lastTrades[symbol], Overnight.overnightMarket(calendars)) : null
    drawn = Day.dayChart(quote, quoted || NO_ANSWER, calendars)
  }
  return Overnight.newestTrade(quote, drawn.latest, calendars, drawn.day)
}

// Robinhood's answer before it comes (`Overnight.overnightAnswer`'s shape).
var NO_ANSWER = { bars: [], from: null, through: null }

// x runs by the clock along the day's axis (`chartSpan`): from the first trade
// or the open, whichever is earlier, so the line reaches the bell from where it
// came, to hold every trade; or, for a US stock or ETF, from 04:00 to its
// 20:00 (`Day.js`), so a quiet hour shows as one, the hours to come stay
// empty, and a finished day ends at its last trade. `ext` marks trades
// outside the regular session. `dim` marks those that don't trade now: the
// extended hours, or on a day lit where it trades now (`Day.litFrom`),
// every trade before that, and a row's columns light what it leaves. The
// dot sits on the newest trade, lit or not, the one the price on top shows.
// `faint` marks what the panel's chart draws lighter: the extended hours,
// so the session stays full at any hour, or once the closed day is set
// apart (`aside`), as `dim`.
// `brk` lifts the line across hours of the exchange's day that take room,
// such as Tokyo's lunch, which Yahoo sends inside one 09:00 to 15:30
// session. Hours that take no room (`axis.skip`), such as a weekend, are no
// break: the line runs across them. Neither is a stretch with no trade, as a
// thin night or pre-market leaves: more than half an hour of room between two
// trades, which `Overnight.fillsBetween` calls a stretch too. The line holds
// the trade before it there and steps to the one after (`untraded`), where a
// slope would draw trading that never happened. The scale holds every trade
// and the close, so the baseline stays in view.
//
// Once tonight has traded (`Day.nightBell`), the day holds two closes, and
// the one dashed line is the close just gone, which the number beside the
// chart counts from, so the day before the bell is set aside (`aside`).
// The scale holds both closes, so nothing moves when one look turns into
// the other.
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
  var dayBase = Quote.dayBase(quote)
  var bell = Day.nightBell(quote)
  // Known apart from the day's: Yahoo can send the close without the one before.
  var gone = bell !== null ? Quote.regularClose(quote) : null
  var stepped = Format.isFiniteNumber(gone)
  var base = stepped ? gone : dayBase
  var known = Format.isFiniteNumber(base)
  var lo = known ? base : (pts.length ? pts[0].p : 0)
  var hi = lo
  if (stepped) { lo = Math.min(lo, gone); hi = Math.max(hi, gone) }
  if (Format.isFiniteNumber(dayBase)) { lo = Math.min(lo, dayBase); hi = Math.max(hi, dayBase) }
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
    var dim = lit ? pts[k].t < quote.litFrom : session !== "reg"
    var prev = k > 0 ? pts[k - 1] : null
    var brk = !!prev && across(prev.t, pts[k].t)
    out.push({
      x: axisFraction(axis, pts[k].t),
      y: 1 - (pts[k].p - lo) / (hi - lo),
      ext: session !== "reg",
      dim: dim,
      faint: stepped ? dim : session !== "reg",
      brk: brk,
      untraded: !!prev && !brk && clockRoom(axis, pts[k].t) - clockRoom(axis, prev.t) > Overnight.HOLE_SLOTS * Overnight.SLOT
    })
  }
  var ticks = []
  for (var n = 0; n < axis.ticks.length; n++) {
    var x = axisFraction(axis, axis.ticks[n])
    if (x > 0 && x < 1) ticks.push(x)
  }
  var bellX = stepped ? axisFraction(axis, bell) : 0
  return {
    points: out,
    baselineY: known ? 1 - (base - lo) / (hi - lo) : null,
    aside: stepped ? { from: 0, to: bellX } : null,
    ticks: ticks,
    lo: lo, hi: hi, start: axis.start, end: axis.end,
    day: true
  }
}

// One trade draws: the first after midnight is a dot on its day, or a cell.
function drawable(geometry) {
  return !!geometry && !!geometry.points && geometry.points.length >= 1
}

// The dashed baseline draws with no trade too, as on a day nobody traded.
// It is unknown for a quote without a previous close, and for a range on a
// log scale whose close before it is below zero, as oil's was in 2020.
function hasBaseline(geometry) {
  return !!geometry && typeof geometry.baselineY === "number" && isFinite(geometry.baselineY)
}

// Whether `x` is in the stretch the number beside the chart doesn't count
// (`chartGeometry`'s `aside`).
function asideAt(geometry, x) {
  var aside = geometry.aside
  return !!aside && x >= aside.from && (x < aside.to || aside.to >= 1)
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

// Where a row's dot sits while scrubbed at `t`: on the line where the price
// its figures read sits (`Quote.readingAt`), its trade or the close's bell,
// never between two trades, where the line's slope is no price anyone
// paid. -1 before the first trade (`Figures.scrubbedLine`).
function tradeFraction(quote, t) {
  var at = Quote.readingAt(quote, t).at
  return at === null ? -1 : fractionAtTime(quote, at)
}

// Five minutes of room a step, so one crosses the hours that take none, kept
// on the day and no later than `last`, the last trade.
function stepTime(quote, t, steps, last) {
  var axis = chartSpan(quote)
  return Format.clamp(clockAt(axis, clockRoom(axis, t) + steps * 300), axis.start, last || axis.end)
}

// Retro's cells for a chart `width` by `height`, of `pixel` cells `gap`
// apart: each column's level, whether it is dim, which side of the close
// it is on (`above`), the newest trade's column (`newest`), the baseline's
// row, and the columns from `asideFrom` to before `asideTo`, which draw
// aside (`chartGeometry`'s `aside`). The last trade in a column wins: the
// price at the end of that stretch. A range's start (`rangeStart`) keeps
// the first column to itself, so the column the line starts from is always
// there (`ownStart`, `retroColumn`). A column between two trades the line
// joins holds the one before it; a break (`brk`) and a stretch with no trade
// (`untraded`) leave columns dark. With no previous close known (`based`
// false), the columns stand on the floor. A column's side is its own
// price's against the close, unrounded, as smooth's line is: a price a hair
// under the close, on the close's row, is below; one at the close is above,
// as smooth's line there is up.
function retroGrid(geometry, width, height, pixel, gap) {
  var pitch = pixel + gap
  var columns = Math.max(1, Math.floor(width / pitch))
  var g = { pitch: pitch, columns: columns, rows: Math.max(1, Math.floor(height / pixel)), baseRow: 0, asideFrom: columns, asideTo: columns, levels: [], above: [], dim: [], faint: [], newest: -1, ownStart: false, based: false }
  if (!geometry || !geometry.points) return g
  g.based = hasBaseline(geometry)
  g.baseRow = g.based ? Math.round(geometry.baselineY * (g.rows - 1)) : g.rows - 1
  var aside = geometry.aside
  if (aside) {
    g.asideFrom = Math.floor(aside.from * columns)
    g.asideTo = aside.to >= 1 ? columns : Math.floor(aside.to * columns)
  }
  var pts = geometry.points
  g.ownStart = pts.length > 1 && columns > 1 && !!pts[0].rangeStart
  // Halfway to the next point, where a scrub, which reads the nearest
  // point, leaves the start.
  g.startReach = g.ownStart ? pts[1].x / 2 : 0
  var last = -1
  for (var i = 0; i < pts.length; i++) {
    var col = retroColumn(g, pts[i].x)
    for (var held = last + 1; i > 0 && !pts[i].brk && !pts[i].untraded && held < col; held++) {
      g.levels[held] = g.levels[last]
      g.above[held] = g.above[last]
      g.dim[held] = g.dim[last]
      g.faint[held] = g.faint[last]
    }
    g.levels[col] = Math.round(pts[i].y * (g.rows - 1))
    g.above[col] = pts[i].y <= (hasBaseline(geometry) ? geometry.baselineY : 1)
    g.dim[col] = pts[i].dim
    g.faint[col] = pts[i].faint
    last = col
  }
  g.newest = last
  return g
}

// The column a place `x` along the chart stands in: a point's, a scrub's or
// a replay's. With the start in the first column alone, every place a scrub
// reads as the start stands there, and every later one from the second on.
function retroColumn(g, x) {
  var col = Math.max(0, Math.min(g.columns - 1, Math.floor(x * g.columns)))
  if (!g.ownStart) return col
  return x < g.startReach ? 0 : Math.max(1, col)
}

// Where the dot sits: the newest trade, the one the price on top shows,
// whether it trades now or not.
function newestPoint(geometry) {
  if (!geometry || !geometry.points || !geometry.points.length) return null
  return geometry.points[geometry.points.length - 1]
}

// Null past the line and across a break, where the line lifts. Across a
// stretch with no trade, the trade before it, as the line holds it.
function yAt(points, x) {
  if (!points || !points.length) return null
  if (x < points[0].x || x > points[points.length - 1].x) return null
  if (points.length === 1) return points[0].y
  for (var i = 1; i < points.length; i++) {
    if (points[i].x >= x) {
      var a = points[i - 1], b = points[i]
      if (b.brk && x > a.x && x < b.x) return null
      if (b.untraded && x < b.x) return a.y
      var f = b.x === a.x ? 0 : (x - a.x) / (b.x - a.x)
      return a.y + (b.y - a.y) * f
    }
  }
  return null
}
