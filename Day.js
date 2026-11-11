.pragma library
.import "Calendar.js" as Calendar
.import "Overnight.js" as Overnight
.import "Quote.js" as Quote

// The day a 1D chart draws for a stock that trades at night: where it
// starts and how its start slides toward midnight, the evening when tonight
// joins the day that closed, its ticks, and the hours drawn bright. Built
// from Yahoo's day and Robinhood's trades (`Overnight.allTrades`). Knows
// nothing of how the chart draws it.

// Where tonight's trades, joined to the day that closed, start counting
// from its close: its bell, so its after hours read against that close too.
// Null before tonight's first trade, and on any other day.
function nightBell(day) {
  var pts = day && day.points ? day.points : []
  var last = pts.length ? pts[pts.length - 1] : null
  if (!last || !day.tonight || !day.session.regular || last.s !== "overnight" || last.t < day.tonight) return null
  return day.session.regular.end
}

// From the night's open the evening before to the next night's open, or
// with no night after it, to the post-market's close; `midnight` is where
// its start has slid to by the afternoon (`slidWindow`). Null past the
// calendar.
function dayWindow(cal, date) {
  var next = Calendar.nextDateString(date)
  var nextKind = Calendar.dayKind(cal, next).kind
  if (Calendar.dayKind(cal, date).kind !== "open" || nextKind === "unknown") return null
  return {
    date: date,
    start: Overnight.marketDay(cal, date).start,
    midnight: Calendar.epochAt(cal, date, "00:00"),
    end: nextKind === "open" ? Calendar.epochAt(cal, date, cal.overnight.open) : postClose(cal, date)
  }
}

// Until the open the day starts with its night, at 20:00 the evening before.
// From the open its start slides toward its own midnight by the shell's clock
// (`slideAt`, five minutes at a time), as tonight slides in at night,
// reaching it as many hours after the open as the night held before
// midnight: at 13:30. A quiet stock's trades come when they come, so the
// clock, not its newest trade, moves the start.
function slidWindow(win, open, slideAt) {
  var slid = slideAt > open ? Math.floor((slideAt - open) / Overnight.SLOT) * Overnight.SLOT : 0
  return Object.assign({}, win, { start: Math.min(win.midnight, win.start + slid) })
}

// Robinhood's post-market lasts as long after a half day's 13:00 close as
// after a full day's, so it ends at 17:00.
function postClose(cal, date) {
  var segs = Calendar.segmentsOn(cal, date)
  var full = Calendar.epochAt(cal, date, cal.post.close)
  return Math.min(full, segs[segs.length - 1].end + full - Calendar.epochAt(cal, date, cal.post.open))
}

// A day stays on through the weekend or holiday after it, until the next
// trade.
function chartWindow(cal, quote, latest) {
  return dayWindow(cal, Overnight.marketDayAt(cal, latest ? latest.t : quote.session.regular.start).date)
}

// The day that closed, then tonight, the shut hours between them taking no
// room (`skip`). It keeps the width the closed day ended with, from its
// midnight to its end, so from 20:00 five minutes leave the left as five
// arrive on the right. A listing with no trade since before the closed day
// keeps its own.
function eveningWindow(cal, latestT, reach) {
  var night = Overnight.nightAt(cal, reach)
  if (!night || !night.open) return null
  var date = Overnight.marketDayAt(cal, reach).date
  var closed = null
  for (var i = 0; i < 10 && !closed; i++) {
    date = Calendar.previousDateString(date)
    closed = dayWindow(cal, date)
  }
  if (!closed || latestT < closed.start) return null
  var skip = closed.end < night.start ? { from: closed.end, to: night.start } : null
  return {
    date: closed.date,
    start: Math.max(closed.midnight, reach - (closed.end - closed.midnight) + Overnight.SLOT - (skip ? skip.to - skip.from : 0)),
    end: reach,
    skip: skip,
    night: night
  }
}

function windowSession(cal, quote, win) {
  var on = function(s) { return !!s && !!s.regular && Calendar.dateStringOf(Calendar.localDate(s.regular.start, cal)) === win.date }
  if (on(quote.session)) return quote.session
  if (on(quote.next)) return quote.next
  var segs = Calendar.segmentsOn(cal, win.date)
  var open = segs[0].start
  var close = segs[segs.length - 1].end
  return { pre: { start: Calendar.epochAt(cal, win.date, cal.pre.open), end: open }, regular: { start: open, end: close },
    post: { start: close, end: postClose(cal, win.date) } }
}

// Hours before the first trade drawn and after the last take no room, so a
// finished day runs edge to edge. Where the chart's start has slid past some
// of the day's trades (`slid`), the axis starts there instead, five minutes
// at a time, so a quiet hour leaves the left as the start passes it, never
// in one step.
function tradedAxis(session, points, end, over, ticks, slid) {
  var open = session.regular.start
  return {
    start: slid !== undefined ? slid : points.length ? Math.min(points[0].t, open) : open,
    end: over && points.length ? points[points.length - 1].t : end,
    ticks: ticks
  }
}

function windowTicks(cal, win, session) {
  var ticks = [Calendar.epochAt(cal, win.date, "00:00"), Calendar.epochAt(cal, win.date, cal.overnight.close)]
  var segs = Calendar.segmentsOn(cal, win.date)
  if (segs.length && segs[0].start === session.regular.start) ticks.push(session.regular.end)
  else for (var i = 0; i < segs.length; i++) ticks.push(segs[i].end)
  if (win.night) ticks.push(win.night.start, Calendar.epochAt(cal, Calendar.dateStringOf(Calendar.localDate(win.night.end, cal)), "00:00"))
  return ticks
}

var LIT_SESSIONS = ["pre", "post", "overnight"]

// Read from the trades, never the clock, so a night with no trade yet
// stays dim.
function litFrom(points, evening, over) {
  var last = points.length ? points[points.length - 1] : null
  if (!last || over || LIT_SESSIONS.indexOf(last.s) < 0) return null
  if (evening ? last.s !== "overnight" || last.t < evening.night.start : last.s === "overnight") return null
  var i = points.length - 1
  while (i > 0 && points[i - 1].s === last.s) i--
  return points[i].t
}

// `day` is shaped as a quote, so the chart and a scrub read it as they
// read Yahoo's; the day's figures stay the quote's. `slideAt` slides the
// day's start (`slidWindow`); without it, as where only the newest price is
// wanted (`Chart.newestTrades`) or a harness gives no clock, the newest trade
// stands in for it.
function dayChart(quote, answer, calendars, slideAt) {
  var cal = Calendar.calendarFor(calendars, quote)
  if (!cal || !cal.overnight || !quote.session.regular) return { day: quote, latest: null }
  var all = Overnight.allTrades(quote, answer.bars)
  var latest = all.length ? all[all.length - 1] : null
  var reach = latest ? Math.max(latest.t, answer.through !== null ? answer.through : latest.t) : answer.through
  var evening = reach !== null && latest ? eveningWindow(cal, latest.t, reach) : null
  var win = evening || chartWindow(cal, quote, latest)
  if (!win) return { day: quote, latest: latest }
  var session = windowSession(cal, quote, win)
  if (!evening) win = slidWindow(win, session.regular.start, slideAt > 0 ? slideAt : reach)
  var own = session === quote.session
  var points = all.filter(function(p) { return p.t >= win.start })
  var opened = Overnight.marketDay(cal, win.date).start
  var trades = all.filter(function(p) { return p.t >= opened })
  // Over once Robinhood's bars reach the window's end, or Yahoo's own day
  // is whole; an evening never is.
  var reachedEnd = answer.through !== null && answer.through + Overnight.SLOT >= win.end
  var over = !evening && (reachedEnd || (own && !!quote.wholeDay))
  // Once the window has slid past the day's first trades, the axis starts
  // where the window does.
  var slid = trades.length && trades[0].t < win.start ? win.start : undefined
  var axis = tradedAxis(session, points, win.end, over, windowTicks(cal, win, session), slid)
  // `closes`: when the day's last hour ends (`Figures.dayNote`).
  axis.closes = evening ? evening.night.end : win.end
  if (win.skip) axis.skip = win.skip
  return {
    day: Object.assign({}, quote, {
      session: session,
      next: null,
      points: points,
      // Every trade of the day from its night's open, which its low and high
      // count (`Figures.figuresTrades`) wherever the chart's start has slid.
      trades: trades,
      prevClose: own ? quote.prevClose : Quote.regularClose(quote),
      dayOpen: own ? quote.dayOpen : null,
      openSession: own ? quote.openSession : null,
      axis: axis,
      litFrom: litFrom(points, evening, over),
      tonight: evening ? evening.night.start : null,
      calendar: cal
    }),
    latest: latest
  }
}

// A thin listing Robinhood doesn't trade all day has a few night
// trades, and none is a night's price.
function sessionDay(quote) {
  if (!quote.session.regular) return quote
  var day = Quote.tailDay(quote) || quote
  var pts = day.points
  return Object.assign({}, day, {
    axis: tradedAxis(day.session, pts, Math.max(Quote.dayEnd(day), pts.length ? pts[pts.length - 1].t : 0), !!day.wholeDay,
      [day.session.regular.end])
  })
}
