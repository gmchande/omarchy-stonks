.pragma library
.import "Calendar.js" as Calendar
.import "Overnight.js" as Overnight
.import "Quote.js" as Quote

// The day a US stock's or ETF's 1D chart draws: from its open, on an axis
// that runs by the clock to its 20:00, and until the next open the day that
// closed with what has traded since joined at its end. For one Robinhood
// trades all day, built from Yahoo's day and Robinhood's trades
// (`Overnight.allTrades`, `dayChart`); for one it doesn't, from Yahoo's
// alone (`sessionDay`). Knows nothing of how the chart draws it.

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

// From the open to the next night's open, or with no night after it, to
// the post-market's close. Null on a day the market is shut, or past the
// calendar.
function dayWindow(cal, date) {
  var next = Calendar.nextDateString(date)
  var nextKind = Calendar.dayKind(cal, next).kind
  if (Calendar.dayKind(cal, date).kind !== "open" || nextKind === "unknown") return null
  return {
    date: date,
    start: Calendar.segmentsOn(cal, date)[0].start,
    end: nextKind === "open" ? Calendar.epochAt(cal, date, cal.overnight.open) : Calendar.postClose(cal, date)
  }
}

// The day drawn: the last whose open the answers have reached (`reach`),
// Yahoo's trades or Robinhood's slots, traded or not, so a day takes the
// chart at its open, a quiet stock's too, and stays through the weekend or
// holiday after it. Null past the calendar.
function drawnWindow(cal, reach) {
  var date = Overnight.marketDayAt(cal, reach).date
  for (var i = 0; i < 10; i++, date = Calendar.previousDateString(date)) {
    var kind = Calendar.dayKind(cal, date).kind
    if (kind === "unknown") return null
    if (kind !== "open") continue
    var win = dayWindow(cal, date)
    if (!win || reach >= win.start) return win
  }
  return null
}

// Once the answers reach past the day's end, tonight and then the coming
// day's pre-market join it until that day's open, from where the market
// trades again (`from`): the shut hours between, such as a weekend's,
// take no room (`skip`). Null while the day runs.
function joinedHours(cal, win, reach) {
  var next = reach >= win.end ? Calendar.nextOpen(cal, win.end) : null
  if (!next) return null
  var from = Math.max(win.end, Overnight.marketDay(cal, next.dateString).start)
  return { from: from, opens: next.t, date: next.dateString, skip: from > win.end ? { from: win.end, to: from } : null }
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

// The day's bell, and where joined hours begin: tonight's open and the
// coming day's midnight and pre-market.
function windowTicks(cal, win, session, joined) {
  var ticks = []
  var segs = Calendar.segmentsOn(cal, win.date)
  if (segs.length && segs[0].start === session.regular.start) ticks.push(session.regular.end)
  else for (var i = 0; i < segs.length; i++) ticks.push(segs[i].end)
  if (joined) ticks.push(joined.from, Calendar.epochAt(cal, joined.date, "00:00"), Calendar.epochAt(cal, joined.date, cal.overnight.close))
  return ticks
}

var LIT_SESSIONS = ["pre", "post", "overnight"]

// Read from the trades, never the clock, so a night with no trade yet
// stays dim: on a day that closed (`tonight`), only joined trades light.
function litFrom(points, tonight, over) {
  var last = points.length ? points[points.length - 1] : null
  if (!last || over || LIT_SESSIONS.indexOf(last.s) < 0 || (tonight !== null && last.t < tonight)) return null
  var i = points.length - 1
  while (i > 0 && points[i - 1].s === last.s) i--
  return points[i].t
}

// `day` is shaped as a quote, so the chart and a scrub read it as they
// read Yahoo's; the day's figures stay the quote's.
function dayChart(quote, answer, calendars) {
  var cal = Calendar.calendarFor(calendars, quote)
  if (!cal || !cal.overnight || !quote.session.regular) return { day: quote, latest: null }
  var all = Overnight.allTrades(quote, answer.bars)
  var latest = all.length ? all[all.length - 1] : null
  var reach = latest ? Math.max(latest.t, answer.through !== null ? answer.through : latest.t) : quote.session.regular.start
  var win = drawnWindow(cal, reach)
  if (!win) return { day: quote, latest: latest }
  var joined = joinedHours(cal, win, reach)
  var session = windowSession(cal, quote, win)
  var own = session === quote.session
  var points = all.filter(function(p) { return p.t >= win.start })
  var opened = Overnight.marketDay(cal, win.date).start
  // Over once Robinhood's bars reach the day's end, or Yahoo's own day is
  // whole, and a day over ends at its last trade; joined hours never are.
  var reachedEnd = answer.through !== null && answer.through + Overnight.SLOT >= win.end
  var over = !joined && (reachedEnd || (own && !!quote.wholeDay))
  var axis = {
    start: win.start,
    end: joined ? reach : over && points.length ? points[points.length - 1].t : win.end,
    ticks: windowTicks(cal, win, session, joined),
    // When the day's last hour ends (`Figures.dayNote`).
    closes: joined ? joined.opens : win.end
  }
  if (joined && joined.skip) axis.skip = joined.skip
  var tonight = joined ? joined.from : null
  return {
    day: Object.assign({}, quote, {
      session: session,
      next: null,
      points: points,
      // Every trade of the day from its night's open, which its low and high
      // count (`Figures.figuresTrades`), though the chart starts at the open.
      trades: all.filter(function(p) { return p.t >= opened }),
      prevClose: own ? quote.prevClose : Quote.regularClose(quote),
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

// A stock Robinhood doesn't trade all day: Yahoo's day from its open, and
// once Yahoo's answer holds the coming day's pre-market (`Quote.tailDay`),
// that joined at its end, the night between taking no room, the axis
// running on to `now`, the shell's clock five minutes at a time, or without
// one to the newest trade. A thin listing Robinhood doesn't trade all day
// has a few night trades, and none is a night's price.
function sessionDay(quote, now) {
  var reg = quote.session.regular
  if (!reg) return quote
  var all = quote.points
  var points = all.filter(function(p) { return p.t >= reg.start })
  var last = points.length ? points[points.length - 1].t : null
  var tonight = Quote.tailDay(quote) ? Quote.tailStart(quote) : null
  var axis = { start: reg.start, ticks: [reg.end] }
  if (tonight !== null) {
    var ends = Quote.dayEnd(quote)
    axis.end = Math.max(last, now > 0 ? now : last)
    axis.ticks.push(tonight)
    if (ends < tonight) axis.skip = { from: ends, to: tonight }
  } else axis.end = quote.wholeDay && last !== null ? last : Math.max(Quote.dayEnd(quote), last !== null ? last : 0)
  return Object.assign({}, quote, {
    next: null,
    points: points,
    // Every trade of the day, which its low and high count
    // (`Figures.figuresTrades`), though the chart starts at the open.
    trades: all,
    axis: axis,
    tonight: tonight
  })
}
