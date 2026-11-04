.pragma library
.import "Format.js" as Format
.import "Market.js" as Market
.import "Quote.js" as Quote

// Robinhood's overnight prints and the 1D chart's day built from them.
// Knows nothing of how the chart or the line under the price shows them.

var ROBINHOOD_URL = "https://api.robinhood.com/marketdata/historicals/"
var INSTRUMENTS_URL = "https://api.robinhood.com/instruments/"

// Robinhood's newest bar arrives five to ten minutes after it starts.
var OVERNIGHT_LAG = 10 * 60

// A liquid name's newest bar is ten to fifteen minutes old, so a print
// dims only once it has missed one.
var OVERNIGHT_STALE = 20 * 60

var OVERNIGHT_INTERVAL = 5 * 60

var ALL_DAY_INTERVAL = 24 * 60 * 60

function overnightMarket(calendars) {
  var map = Market.calendarMap(calendars)
  for (var id in map) if (map[id] && map[id].overnight) return map[id]
  return null
}

function hasOvernight(quote, calendars) {
  if (!quote || (quote.instrumentType !== "EQUITY" && quote.instrumentType !== "ETF")) return false
  var cal = Market.calendarFor(calendars, quote)
  return !!cal && !!cal.overnight
}

// Yahoo writes BRK-B, Robinhood BRK.B.
function robinhoodSymbol(symbol) {
  return String(symbol).replace(/-/g, ".")
}

// span=day holds the last 288 five-minute slots the 24/5 market traded, its
// closed days left out: every print a 1D chart can draw. span=hour holds
// the last 12 slots by the clock, a twenty-fourth of the bytes.
function overnightUrl(symbols, span) {
  return ROBINHOOD_URL + "?symbols=" + symbols.map(function(s) { return encodeURIComponent(robinhoodSymbol(s)) }).join(",")
    + "&interval=5minute&span=" + span + "&bounds=24_5"
}

// Robinhood takes 75 symbols a request, but a day's answer is read in one
// JSON.parse that can't be sliced, and 75 listings' days came to about 4 MB.
var OVERNIGHT_BATCH = 25

// An hour of 75 listings is about 200 KB.
var HOUR_BATCH = 75

// Half of span=hour's hour: room for a newest bar ten minutes late.
var HOUR_REACH = 30 * 60

// An hour's answer joins on to the prints in hand with no slot missed
// between. A newest slot ahead of the clock is no honest answer.
function overnightSpan(entry, now) {
  return !!entry && entry.through !== null && entry.through !== undefined && entry.through <= now && now - entry.through <= HOUR_REACH ? "hour" : "day"
}

function overnightBatches(symbols, entries, now) {
  var day = symbols.filter(function(s) { return overnightSpan(entries[s], now) === "day" })
  var hour = symbols.filter(function(s) { return overnightSpan(entries[s], now) === "hour" })
  var dayRequests = Math.ceil(day.length / OVERNIGHT_BATCH)
  if (dayRequests + Math.ceil(hour.length / HOUR_BATCH) > Math.ceil(symbols.length / OVERNIGHT_BATCH)) {
    var room = dayRequests * OVERNIGHT_BATCH - day.length
    day = day.concat(hour.slice(0, room))
    hour = hour.slice(room)
  }
  var batches = []
  for (var i = 0; i < day.length; i += OVERNIGHT_BATCH) batches.push({ span: "day", symbols: day.slice(i, i + OVERNIGHT_BATCH) })
  for (var j = 0; j < hour.length; j += HOUR_BATCH) batches.push({ span: "hour", symbols: hour.slice(j, j + HOUR_BATCH) })
  return batches
}

// Past these, an answer is bad (`Format.fetchedList`). MOST_PRINTS also caps
// the prints kept (`joinHour`): a 1D chart draws at most 336 slots.
var MOST_RESULTS = 2 * HOUR_BATCH
var MOST_PRINTS = 1000

function allDayUrl(symbols) {
  return INSTRUMENTS_URL + "?symbols=" + symbols.map(function(s) { return encodeURIComponent(robinhoodSymbol(s)) }).join(",")
}

// Robinhood's instruments answer 100 results a page, in their own order,
// and a symbol may answer twice: past 50, symbols on page two would read as
// not trading all day.
var ALL_DAY_BATCH = 50

// Robinhood can answer a symbol twice, in its own order. "tradable" is its
// 24 Hour Market.
function parseAllDay(json, symbols) {
  var results = Format.fetchedList(json && json.results, 2 * symbols.length)
  if (!results) return null
  var out = {}
  for (var i = 0; i < symbols.length; i++) {
    var wanted = robinhoodSymbol(symbols[i])
    out[symbols[i]] = results.some(function(r) { return r && r.symbol === wanted && r.all_day_tradability === "tradable" })
  }
  return out
}

function allDayDue(entry, now) {
  if (!entry) return true
  return now - entry.at >= (entry.status === "ok" ? ALL_DAY_INTERVAL : OVERNIGHT_INTERVAL)
}

function parseOvernight(json, symbols) {
  var results = overnightResults(json)
  if (!results) return null
  var out = {}
  for (var i = 0; i < symbols.length; i++) out[symbols[i]] = overnightAnswer(results[i], symbols[i])
  return out
}

function overnightResults(json) {
  return Format.fetchedList(json && json.results, MOST_RESULTS)
}

// bounds=24_5 fills a quiet name's gaps with flat `interpolated` bars,
// which are no trades. `from` and `through` count every slot, traded or
// not: how far the answer reaches. A print in a session Robinhood never
// sends, such as "__proto__", is left out: its name becomes the warning's.
var SESSIONS = ["pre", "reg", "post", "overnight"]

function overnightAnswer(result, symbol) {
  var out = { bars: [], from: null, through: null }
  var historicals = result && result.symbol === robinhoodSymbol(symbol) ? Format.fetchedList(result.historicals, MOST_PRINTS) : null
  if (!historicals) return out
  for (var j = 0; j < historicals.length; j++) {
    var bar = historicals[j]
    var t = Date.parse(bar.begins_at) / 1000
    var p = Number(bar.close_price)
    if (Format.isFiniteNumber(t) && (out.from === null || t < out.from)) out.from = t
    if (Format.isFiniteNumber(t) && (out.through === null || t > out.through)) out.through = t
    if (!bar.interpolated && Format.isFiniteNumber(t) && Format.isFiniteNumber(p) && p > 0 && SESSIONS.indexOf(bar.session) >= 0)
      out.bars.push({ t: t, p: p, s: bar.session })
  }
  return out
}

// A bar still forming may be among the hour's slots, so they replace what
// was kept from their first on.
function joinHour(had, hour) {
  if (hour.from === null) return { bars: had.bars, through: had.through }
  return {
    bars: had.bars.filter(function(b) { return b.t < hour.from }).concat(hour.bars).slice(-MOST_PRINTS),
    through: had.through === null || hour.through > had.through ? hour.through : had.through
  }
}

function sameBars(a, b) {
  if (a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) if (a[i].t !== b[i].t || a[i].p !== b[i].p || a[i].s !== b[i].s) return false
  return true
}

function marketDay(cal, dateString) {
  return {
    date: dateString,
    start: Market.epochAt(cal, Market.previousDateString(dateString), cal.overnight.open),
    end: Market.epochAt(cal, dateString, cal.post.close),
    open: Market.dayKind(cal, dateString).kind === "open"
  }
}

function marketDayAt(cal, t) {
  var local = Market.localDate(t, cal)
  var dateString = Market.dateStringOf(local)
  return marketDay(cal, Market.clockOf(local) >= cal.overnight.open ? Market.nextDateString(dateString) : dateString)
}

function nightAt(cal, t) {
  var local = Market.localDate(t, cal)
  var clock = Market.clockOf(local)
  if (clock >= cal.overnight.close && clock < cal.overnight.open) return null
  var day = marketDayAt(cal, t)
  return { start: day.start, end: Market.epochAt(cal, day.date, cal.overnight.close), open: day.open }
}

function nightTrades(quote, allDay, t, calendars) {
  var cal = allDay ? Market.calendarFor(calendars, quote) : null
  var night = cal && cal.overnight ? nightAt(cal, t) : null
  return !!night && night.open
}

function marketAsleep(quote, allDay, t, calendars) {
  if (!quote || quote.crypto) return false
  return !nightTrades(quote, allDay, t, calendars) && !Market.inRegularSession(quote, t, calendars) && !Market.inExtendedHours(quote, t, calendars)
}

function prints(quote, bars) {
  var own = ownPrints(quote, bars)
  var filled = fillsBetween(quote, bars, own)
  for (var k = 0; k < filled.length; k++) own = own.concat(filled[k].bars)
  if (filled.length) own.sort(function(a, b) { return a.t - b.t })
  return own
}

function ownPrints(quote, bars) {
  var out = []
  for (var i = 0; i < bars.length; i++) if (beside(quote, bars[i].t)) out.push(bars[i])
  for (var j = 0; j < quote.points.length; j++) {
    var pt = quote.points[j]
    out.push({ t: pt.t, p: pt.p, s: Quote.pointSession(quote, pt) })
  }
  out.sort(function(a, b) { return a.t - b.t })
  return out
}

var HOLE_SLOTS = 6

function extendedSlots(quote, a, b) {
  var out = []
  var days = [quote.session, quote.next]
  for (var d = 0; d < days.length; d++) {
    var spans = days[d] ? [days[d].pre, days[d].post] : []
    for (var k = 0; k < spans.length; k++) {
      if (!spans[k]) continue
      var end = Math.min(b, spans[k].end)
      for (var t = Math.ceil(Math.max(a + 1, spans[k].start) / SLOT) * SLOT; t < end; t += SLOT) out.push({ t: t, s: k === 0 ? "pre" : "post" })
    }
  }
  return out
}

// Yahoo can send no bar for an hour of a pre-market. Robinhood's trades
// fill such a stretch, HOLE_SLOTS or more slots with no print, where it
// traded in at least half of them: a thin stock's sparse trading is no such
// stretch. A stretch lies between two prints, so the price on top is never
// Robinhood's from it.
function filledStretches(quote, bars) {
  return fillsBetween(quote, bars, ownPrints(quote, bars))
}

function fillsBetween(quote, bars, drawn) {
  var out = []
  for (var i = 1; i < drawn.length; i++) {
    var from = drawn[i - 1].t
    var to = drawn[i].t
    if (to - from <= HOLE_SLOTS * SLOT) continue
    var slots = extendedSlots(quote, from, to)
    if (slots.length < HOLE_SLOTS) continue
    var sessions = {}
    for (var j = 0; j < slots.length; j++) sessions[slots[j].t] = slots[j].s
    var traded = bars.filter(function(b) { return b.t > from && b.t < to && b.t in sessions })
    if (traded.length * 2 < slots.length) continue
    out.push({ from: from, to: to, bars: traded.map(function(b) { return { t: b.t, p: b.p, s: sessions[b.t] } }) })
  }
  return out
}

var STEADY_SLOTS = 12

// A thin stock's sparse pre-market leaves gaps too, so only one that
// traded in at least half its slots before the gap, STEADY_SLOTS at least,
// counts.
function yahooHole(quote) {
  var pre = quote.session.pre
  var pts = quote.points
  if (!pre) return null
  var last = null
  var steady = 0
  for (var i = 0; i + 1 < pts.length && pts[i].t < pre.end; i++) {
    if (pts[i].t < pre.start) continue
    steady++
    if (pts[i + 1].t - pts[i].t <= HOLE_SLOTS * SLOT) continue
    var slots = extendedSlots(quote, pts[i].t, Math.min(pts[i + 1].t, pre.end))
    var before = Math.floor((pts[i].t - pre.start) / SLOT) + 1
    if (slots.length >= HOLE_SLOTS && before >= STEADY_SLOTS && steady * 2 >= before) last = slots[slots.length - 1].t
  }
  return last
}

// The prints in hand may stop at the night's end, short of Yahoo's empty
// stretch. Asked once Robinhood's bar for its last slot is in; a failed
// answer is asked again OVERNIGHT_INTERVAL later.
function holeDue(hole, entry, now) {
  var due = hole + OVERNIGHT_LAG
  if (now < due || (entry.through !== null && entry.through >= hole)) return false
  return entry.at < due || (entry.status === "failed" && now - entry.at >= OVERNIGHT_INTERVAL)
}

function beside(quote, t) {
  var yahooAgain = Quote.tailStart(quote)
  return (t < Quote.dayStart(quote) || t >= Quote.dayEnd(quote)) && (yahooAgain === null || t < yahooAgain)
}

// `closed`: the print came after its day's regular close, through the
// night until 04:00 and the weekend after a Friday; never in a pre-market.
// `joined`: tonight's print on the day that closed. `dayStart` names that day.
function newestPrint(quote, latest, calendars, day) {
  var print = quote && hasOvernight(quote, calendars) ? Quote.extendedPrint(quote, latest) : null
  if (!print) return null
  var own = day.session.regular.start === quote.session.regular.start
  return { t: print.t, p: print.p, phase: print.phase, base: Quote.dayBase(day), own: own, closed: own && print.t >= quote.session.regular.end,
    joined: print.phase === "overnight" && !!day.tonight && print.t >= day.tonight, dayStart: day.session.regular.start }
}

// To the next night's open, or with no night after it, to the post-market's
// close. Null past the calendar.
function dayWindow(cal, date) {
  var next = Market.nextDateString(date)
  var nextKind = Market.dayKind(cal, next).kind
  if (Market.dayKind(cal, date).kind !== "open" || nextKind === "unknown") return null
  return {
    date: date,
    start: marketDay(cal, date).start,
    end: nextKind === "open" ? Market.epochAt(cal, date, cal.overnight.open) : postClose(cal, date)
  }
}

// Robinhood's post-market lasts as long after a half day's 13:00 close as
// after a full day's, so it ends at 17:00.
function postClose(cal, date) {
  var segs = Market.segmentsOn(cal, date)
  var full = Market.epochAt(cal, date, cal.post.close)
  return Math.min(full, segs[segs.length - 1].end + full - Market.epochAt(cal, date, cal.post.open))
}

// A day stays on through the weekend or holiday after it, until the next
// print.
function chartWindow(cal, quote, latest) {
  return dayWindow(cal, marketDayAt(cal, latest ? latest.t : quote.session.regular.start).date)
}

var DAY = 24 * 60 * 60

// The day that closed, then tonight, the shut hours between them taking no
// room (`skip`). Like Robinhood's day answer it holds the 288 slots up to
// `reach`, so from 20:00 five minutes leave the left as five arrive on the
// right. A listing with no trade since before the closed day keeps its own.
function eveningWindow(cal, latestT, reach) {
  var night = nightAt(cal, reach)
  if (!night || !night.open) return null
  var date = marketDayAt(cal, reach).date
  var closed = null
  for (var i = 0; i < 10 && !closed; i++) {
    date = Market.previousDateString(date)
    closed = dayWindow(cal, date)
  }
  if (!closed || latestT < closed.start) return null
  var skip = closed.end < night.start ? { from: closed.end, to: night.start } : null
  return {
    date: closed.date,
    start: Math.max(closed.start, reach - DAY + SLOT - (skip ? skip.to - skip.from : 0)),
    end: reach,
    skip: skip,
    night: night
  }
}

function windowSession(cal, quote, win) {
  var on = function(s) { return !!s && !!s.regular && Market.dateStringOf(Market.localDate(s.regular.start, cal)) === win.date }
  if (on(quote.session)) return quote.session
  if (on(quote.next)) return quote.next
  var segs = Market.segmentsOn(cal, win.date)
  var open = segs[0].start
  var close = segs[segs.length - 1].end
  return { pre: { start: Market.epochAt(cal, win.date, cal.pre.open), end: open }, regular: { start: open, end: close },
    post: { start: close, end: postClose(cal, win.date) } }
}

// Robinhood's bars are five minutes each.
var SLOT = 5 * 60

// Hours before the first trade and after the last take no room, so a
// finished day runs edge to edge.
function tradedAxis(session, points, end, over, ticks) {
  var open = session.regular.start
  return {
    start: points.length ? Math.min(points[0].t, open) : open,
    end: over && points.length ? points[points.length - 1].t : end,
    ticks: ticks
  }
}

function windowTicks(cal, win, session) {
  var ticks = [Market.epochAt(cal, win.date, "00:00"), Market.epochAt(cal, win.date, cal.overnight.close)]
  var segs = Market.segmentsOn(cal, win.date)
  if (segs.length && segs[0].start === session.regular.start) ticks.push(session.regular.end)
  else for (var i = 0; i < segs.length; i++) ticks.push(segs[i].end)
  if (win.night) ticks.push(win.night.start, Market.epochAt(cal, Market.dateStringOf(Market.localDate(win.night.end, cal)), "00:00"))
  return ticks
}

var LIT_SESSIONS = ["pre", "post", "overnight"]

// Read from the prints, never the clock, so a night with no trade yet
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
// read Yahoo's; the day's figures stay the quote's.
function dayChart(quote, answer, calendars) {
  var cal = Market.calendarFor(calendars, quote)
  if (!cal || !cal.overnight || !quote.session.regular) return { day: quote, latest: null }
  var all = prints(quote, answer.bars)
  var latest = all.length ? all[all.length - 1] : null
  var reach = latest ? Math.max(latest.t, answer.through !== null ? answer.through : latest.t) : answer.through
  var evening = reach !== null && latest ? eveningWindow(cal, latest.t, reach) : null
  var win = evening || chartWindow(cal, quote, latest)
  if (!win) return { day: quote, latest: latest }
  var session = windowSession(cal, quote, win)
  var own = session === quote.session
  var points = all.filter(function(p) { return p.t >= win.start })
  var over = !evening && ((answer.through !== null && answer.through + SLOT >= win.end) || (own && !!quote.wholeDay))
  return {
    day: Object.assign({}, quote, {
      session: session,
      next: null,
      points: points,
      prevClose: own ? quote.prevClose : Quote.regularClose(quote),
      dayOpen: own ? quote.dayOpen : null,
      openSession: own ? quote.openSession : null,
      // `closes`: when the day's last hour ends (`Figures.dayNote`).
      axis: Object.assign(tradedAxis(session, points, win.end, over, windowTicks(cal, win, session)),
        { closes: evening ? evening.night.end : win.end }, win.skip ? { skip: win.skip } : {}),
      litFrom: litFrom(points, evening, over),
      tonight: evening ? evening.night.start : null,
      calendar: cal
    }),
    latest: latest
  }
}

// A thin listing Robinhood doesn't trade all day prints a few night
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

function overnightDue(askedAt, now, calendars, failed) {
  var cal = overnightMarket(calendars)
  if (!cal) return false
  if (!askedAt) return true
  if (failed) return now - askedAt >= OVERNIGHT_INTERVAL
  var night = nightAt(cal, now)
  if (night && night.open) return now - askedAt >= OVERNIGHT_INTERVAL
  for (var day = marketDayAt(cal, now), i = 0; i < 14; i++, day = marketDay(cal, Market.previousDateString(day.date))) {
    var ended = Market.epochAt(cal, day.date, cal.overnight.close) + OVERNIGHT_LAG
    if (day.open && ended <= now) return askedAt < ended
  }
  return false
}
