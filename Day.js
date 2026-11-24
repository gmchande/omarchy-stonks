.pragma library
.import "Calendar.js" as Calendar
.import "CarriedClose.js" as CarriedClose
.import "Overnight.js" as Overnight
.import "Quote.js" as Quote

// The day a US stock's or ETF's 1D chart draws: from its pre-market, 04:00,
// on an axis that runs by the clock to its 20:00, and until the next
// pre-market the day that closed with what has traded since joined at its
// end. For one Robinhood trades all day, built from Yahoo's day and
// Robinhood's trades (`Overnight.allTrades`, `dayChart`); for one it
// doesn't, from Yahoo's alone (`sessionDay`). Knows nothing of how the
// chart draws it.

// Where the trades joined to the day that closed, tonight's or the coming
// day's pre-market, start counting from its close: its bell, so its after
// hours read against that close too. So do a day abroad's first trades
// joined to the day before it, where that close is known
// (`CarriedClose.heldDay`). Null before the first trade joined, and on any
// other day.
function nightBell(day) {
  var pts = day && day.points ? day.points : []
  var last = pts.length ? pts[pts.length - 1] : null
  if (!last || !day.tonight || !day.session.regular || last.t < day.tonight) return null
  return day.session.regular.end
}

// From the pre-market to the next night's open, or with no night after it,
// to the post-market's close; `open` is its bell. Null on a day the market
// is shut, or past the calendar.
function dayWindow(cal, date) {
  var next = Calendar.nextDateString(date)
  var nextKind = Calendar.dayKind(cal, next).kind
  if (Calendar.dayKind(cal, date).kind !== "open" || nextKind === "unknown") return null
  return {
    date: date,
    start: Calendar.epochAt(cal, date, cal.pre.open),
    open: Calendar.segmentsOn(cal, date)[0].start,
    end: nextKind === "open" ? Calendar.epochAt(cal, date, cal.overnight.open) : Calendar.postClose(cal, date)
  }
}

// The day drawn: the last whose pre-market has come (`edge`), so a day takes
// the chart at 04:00, a quiet stock's too, and stays through the weekend or
// holiday after it. Null past the calendar.
function drawnWindow(cal, edge) {
  var date = Overnight.marketDayAt(cal, edge).date
  for (var i = 0; i < 10; i++, date = Calendar.previousDateString(date)) {
    var kind = Calendar.dayKind(cal, date).kind
    if (kind === "unknown") return null
    if (kind !== "open") continue
    var win = dayWindow(cal, date)
    if (!win || edge >= win.start) return win
  }
  return null
}

// One or two trades of a day just begun, scaled to the chart's height, draw
// a line from top to bottom. So until the day has its first bars
// (`CarriedClose.firstBars`), Yahoo's and Robinhood's together, the chart
// holds the day before with them joined at its end, as it did through the
// night; a day that trades too seldom to wait for turns an hour in
// (`CarriedClose.HOLD_LIMIT`), as quiet as it is.
function heldWindow(cal, trades, edge, win) {
  if (!win || edge >= win.start + CarriedClose.HOLD_LIMIT) return win
  var day = trades.filter(function(p) { return p.t < win.end })
  return CarriedClose.firstBars(day, win.start) ? drawnWindow(cal, win.start - 1) : win
}

// Once the market trades again after the day's end, tonight and then the
// coming day's pre-market join it until that day takes the chart
// (`heldWindow`), from where it trades again (`from`): the shut hours
// between, such as a weekend's, take no room (`skip`). `turns` is the coming
// day's 04:00, `opens` its bell. Null while the day runs, and while the
// market is shut after it.
function joinedHours(cal, win, edge) {
  var next = edge >= win.end ? Calendar.nextOpen(cal, win.end) : null
  var from = next ? Math.max(win.end, Overnight.marketDay(cal, next.dateString).start) : null
  if (from === null || edge < from) return null
  return { from: from, turns: Calendar.epochAt(cal, next.dateString, cal.pre.open), opens: next.t, date: next.dateString,
    skip: from > win.end ? { from: win.end, to: from } : null }
}

function windowSession(cal, quote, win) {
  var on = function(s) { return !!s && !!s.regular && Calendar.dateStringOf(Calendar.localDate(s.regular.start, cal)) === win.date }
  if (on(quote.session)) return quote.session
  if (on(quote.next)) return quote.next
  var segs = Calendar.segmentsOn(cal, win.date)
  var open = segs[0].start
  var close = segs[segs.length - 1].end
  return { pre: { start: Calendar.epochAt(cal, win.date, cal.pre.open), end: open }, regular: { start: open, end: close },
    post: { start: close, end: Calendar.postClose(cal, win.date) } }
}

// The day's open and bell, and where joined hours begin: tonight's open,
// and the coming day's midnight, pre-market and open.
function windowTicks(cal, win, session, joined) {
  var ticks = [win.open]
  var segs = Calendar.segmentsOn(cal, win.date)
  if (segs.length && segs[0].start === session.regular.start) ticks.push(session.regular.end)
  else for (var i = 0; i < segs.length; i++) ticks.push(segs[i].end)
  if (joined) ticks.push(joined.from, Calendar.epochAt(cal, joined.date, "00:00"), joined.turns, joined.opens)
  return ticks
}

var LIT_SESSIONS = ["pre", "post", "overnight"]

// Read from the trades, never the clock, so a night with no trade yet
// stays dim: on a day that closed (`tonight`), only joined trades light,
// the coming day's too while the chart holds the day (`heldWindow`).
function litFrom(points, tonight, over) {
  var last = points.length ? points[points.length - 1] : null
  if (!last || over || (tonight !== null ? last.t < tonight : LIT_SESSIONS.indexOf(last.s) < 0)) return null
  var i = points.length - 1
  while (i > 0 && points[i - 1].s === last.s) i--
  return points[i].t
}

// How far the day reaches: `now`, the shell's clock, while it is no later
// than the end of the trading day after the newest answer's (`reach`), so
// joined hours run on to now; past that the answers are stale, and their
// own day stays, as it does without a clock.
function dayEdge(cal, reach, now) {
  var win = now > reach ? drawnWindow(cal, reach) : null
  var next = win ? Calendar.nextOpen(cal, win.open) : null
  var after = next ? dayWindow(cal, next.dateString) : null
  return after && now < after.end ? now : reach
}

// `day` is shaped as a quote, so the chart and a scrub read it as they
// read Yahoo's; the day's figures stay the quote's. `now`, the shell's
// clock five minutes at a time, carries joined hours on to now and turns
// the day at 04:00 (`dayEdge`); without it, as where only the newest
// price is wanted (`Chart.newestTradeOf`) or a harness gives no clock, the
// newest answer stands in for it. A day just begun waits for its first
// bars, joined to the day before meanwhile (`heldWindow`).
function dayChart(quote, answer, calendars, now) {
  var cal = Calendar.calendarFor(calendars, quote)
  if (!cal || !cal.overnight || !quote.session.regular) return { day: quote, latest: null }
  var all = Overnight.allTrades(quote, answer.bars)
  var latest = all.length ? all[all.length - 1] : null
  var reach = latest ? Math.max(latest.t, answer.through !== null ? answer.through : latest.t) : quote.session.regular.start
  var edge = dayEdge(cal, reach, now)
  var win = heldWindow(cal, all, edge, drawnWindow(cal, edge))
  if (!win) return { day: quote, latest: latest }
  var joined = joinedHours(cal, win, edge)
  var session = windowSession(cal, quote, win)
  var own = session === quote.session
  // Yahoo's quote, still the day's close after Yahoo's day has turned, says
  // the close before that day too.
  var head = Quote.headlineQuote(quote)
  var closedOn = !!head && head.t !== null && head.t >= win.start && head.t < (joined ? joined.turns : win.end)
  var points = all.filter(function(p) { return p.t >= win.start })
  var opened = Overnight.marketDay(cal, win.date).start
  // Over once Robinhood's bars reach the day's end, or Yahoo's own day is
  // whole, and a day over ends at its last trade; joined hours never are.
  var reachedEnd = answer.through !== null && answer.through + Overnight.SLOT >= win.end
  var over = !joined && (reachedEnd || (own && !!quote.wholeDay))
  var axis = {
    start: win.start,
    end: joined ? edge : over && points.length ? points[points.length - 1].t : win.end,
    ticks: windowTicks(cal, win, session, joined),
    // When the day's last hour ends (`Figures.dayNote`).
    closes: joined ? joined.turns : win.end
  }
  if (joined && joined.skip) axis.skip = joined.skip
  var tonight = joined ? joined.from : null
  return {
    day: Object.assign({}, quote, {
      session: session,
      next: null,
      points: points,
      // Every trade of the day from its night's open, which its low and high
      // count (`Figures.figuresTrades`), though the chart starts at 04:00.
      trades: all.filter(function(p) { return p.t >= opened }),
      figuresTrades: figuresTrades(cal, quote, all, win),
      prevClose: own || closedOn ? quote.prevClose : Quote.regularClose(quote),
      dayOpen: own ? quote.dayOpen : null,
      openSession: own ? quote.openSession : null,
      axis: axis,
      litFrom: litFrom(points, tonight, over),
      tonight: tonight,
      calendar: cal
    }),
    latest: latest
  }
}

// Yahoo's figures stay the last session's until its day turns, after the
// open: while the chart draws a later day, the trades of theirs from its
// night's open, which its low and high count (`Figures.figuresTrades`).
// Null while the chart draws that day.
function figuresTrades(cal, quote, trades, win) {
  var date = Calendar.dateStringOf(Calendar.localDate(quote.figuresDay, cal))
  var figures = date < win.date ? dayWindow(cal, date) : null
  if (!figures) return null
  var from = Overnight.marketDay(cal, date).start
  return trades.filter(function(p) { return p.t >= from && p.t < figures.end })
}

// A stock Robinhood doesn't trade all day: Yahoo's day from its pre-market,
// and from 04:00 the coming day Yahoo's two-day answer holds
// (`Quote.comingDay`), once it has its first bars or an hour has passed,
// as `dayChart` turns. Until then that day's first trades are joined at
// its end (`Quote.tailDay`), the night between taking no room. The axis
// runs on to `now`, the shell's clock five minutes at a time, through the
// coming day's end, or without one, or with an answer staler than that, to
// the newest trade, which stands in for the clock without one.
function sessionDay(quote, now) {
  if (!quote.session.regular) return quote
  var coming = Quote.tailStart(quote)
  var clock = now || Quote.lastTradeTime(quote)
  var turned = coming !== null && clock >= coming
    && (clock >= coming + CarriedClose.HOLD_LIMIT || !CarriedClose.firstBars(quote.points, coming))
  var day = turned ? Quote.comingDay(quote) : quote
  var tail = turned ? null : Quote.tailDay(quote)
  var reg = day.session.regular
  var start = Quote.periodsStart(day.session)
  var all = day.points
  var points = all.filter(function(p) { return p.t >= start })
  var last = points.length ? points[points.length - 1].t : null
  var tonight = tail ? coming : null
  var axis = { start: start, ticks: [reg.start, reg.end] }
  if (tonight !== null) {
    var ends = Quote.dayEnd(day)
    axis.end = now > last && now < Quote.dayEnd(tail) ? now : last
    axis.ticks.push(tonight)
    if (ends < tonight) axis.skip = { from: ends, to: tonight }
  } else axis.end = day.wholeDay && last !== null ? last : Math.max(Quote.dayEnd(day), last !== null ? last : 0)
  return Object.assign({}, day, {
    next: null,
    points: points,
    // Every trade of the day, which its low and high count
    // (`Figures.figuresTrades`), though the chart starts at 04:00, and once
    // it has turned, those of the day Yahoo's figures are still of.
    trades: all,
    figuresTrades: turned ? quote.points.filter(function(p) { return p.t < coming }) : null,
    axis: axis,
    tonight: tonight
  })
}
