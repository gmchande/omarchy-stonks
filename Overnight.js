.pragma library
.import "Format.js" as Format
.import "Market.js" as Market
.import "Quote.js" as Quote

// Robinhood's overnight prints and the 1D chart's day built from them. Knows
// nothing of how the line under the price or the chart shows them.
//
// US listings trade overnight on ATSs, 20:00 to 04:00 New York time, Sunday
// to Thursday nights, never the night before a market holiday. A stock or
// an ETF on a US listing (decided from Yahoo's instrument type and the
// listing's calendar, never from what Robinhood answers: it answers BTC with
// a bitcoin ETF) is asked of Robinhood's instruments whether Robinhood
// trades it all day, the 24 Hour Market its screen badges
// (`all_day_tradability`), and of its keyless historicals for its prints,
// side by side, so neither waits for the other. Only one it trades all day
// draws its prints, on a 1D chart of one trading day (`dayChart`): the New
// York date of its newest print, from the first hour it can trade that day
// to the last, a night staying on the evening's chart until 04:00;
// Robinhood's prints for the hours outside Yahoo's day, and Yahoo's own. A
// night that trades thinly (`thinNight`) is a line through its few trades,
// each where the clock puts it. Any other has Yahoo's own day, 04:00 to
// 20:00, or the coming day's once a two-day answer holds a print of it: a
// thin name trades a few shares overnight now and then, and none of them
// is a night's price. Since the close, the newest print is the price on
// top (`newestPrint`); the day's high, low, and open stay Yahoo's.

var ROBINHOOD_URL = "https://api.robinhood.com/marketdata/historicals/"
var INSTRUMENTS_URL = "https://api.robinhood.com/instruments/"

// Robinhood's newest bar arrives five to ten minutes after it starts.
var OVERNIGHT_LAG = 10 * 60

// The overnight print dims past this: a liquid name's newest bar is ten to
// fifteen minutes old in the normal course, so it dims only once it has
// missed one.
var OVERNIGHT_STALE = 20 * 60

// How often an open surface asks again while a night trades.
var OVERNIGHT_INTERVAL = 5 * 60

// How long Robinhood's answer on all-day trading holds: a day.
var ALL_DAY_INTERVAL = 24 * 60 * 60

// The first calendar with an overnight session.
function overnightMarket(calendars) {
  var map = Market.calendarMap(calendars)
  for (var id in map) if (map[id] && map[id].overnight) return map[id]
  return null
}

// A stock or an ETF on a listing whose calendar has the overnight session:
// no index, cryptocurrency, fund, OTC, or non-US listing. Robinhood is asked
// whether it trades each one all day.
function hasOvernight(quote, calendars) {
  if (!quote || (quote.instrumentType !== "EQUITY" && quote.instrumentType !== "ETF")) return false
  var cal = Market.calendarFor(calendars, quote)
  return !!cal && !!cal.overnight
}

// Yahoo writes a share class with a hyphen, Robinhood with a dot: BRK-B, BRK.B.
function robinhoodSymbol(symbol) {
  return String(symbol).replace(/-/g, ".")
}

// span=day is the last 288 five-minute slots Robinhood's 24/5 market traded,
// its closed days left out, so one answer holds every print a 1D chart can
// draw; span=hour is the last 12 slots by the clock, a twenty-fourth of the
// bytes, which brings prints already in hand up to date (`overnightSpan`).
// At most `OVERNIGHT_BATCH` symbols to a day's request, `HOUR_BATCH` to an
// hour's.
function overnightUrl(symbols, span) {
  return ROBINHOOD_URL + "?symbols=" + symbols.map(function(s) { return encodeURIComponent(robinhoodSymbol(s)) }).join(",")
    + "&interval=5minute&span=" + span + "&bounds=24_5"
}

// The listings to a day's request: a third of the 75 Robinhood's
// historicals take ("Too many instruments requested. No more than 75
// allowed."), so each answer, read in one JSON.parse that can't be sliced,
// is a third as long: 75 listings came to about 4 MB.
var OVERNIGHT_BATCH = 25

// The listings to an hour's request: all 75 Robinhood takes, whose answer is
// about 200 KB.
var HOUR_BATCH = 75

// How old the newest slot of the prints in hand may be for an hour's answer
// to reach back past it: half the hour, room for a newest bar that comes
// ten minutes late (`OVERNIGHT_LAG`).
var HOUR_REACH = 30 * 60

// What to ask Robinhood for a listing's prints at `now`, by its entry
// (`OvernightFeed.entries`): "hour" while its newest slot in hand is within
// HOUR_REACH, so the answer joins on to it with no slot missed between;
// "day" for one never answered, or answered longer ago, or whose newest
// slot is ahead of the clock, which no honest answer holds.
function overnightSpan(entry, now) {
  return !!entry && entry.through !== null && entry.through !== undefined && entry.through <= now && now - entry.through <= HOUR_REACH ? "hour" : "day"
}

// The requests for the prints of `symbols` at `now`, by their entries
// (`overnightSpan`), each { span, symbols }: the days first, then the
// hours. Never more requests than a day for all would take: where the hours
// would add one, they fill the last day's spare places instead, so a small
// list whose pill's stock is already in hand still opens in one request.
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

// The most entries a list in Robinhood's answers may hold, past which the
// answer is a bad one (`Format.fetchedList`): a result for each symbol
// asked, one each in the saved answers, so twice the most asked at once; a
// listing's prints, span=day's 288 five-minute slots, 288 in the saved
// answers. MOST_PRINTS is also the most prints kept for a listing
// (`joinHour`): a 1D chart draws from a midnight to 04:00 the day after, at
// most 336 of a 24/5 market's slots.
var MOST_RESULTS = 2 * HOUR_BATCH
var MOST_PRINTS = 1000

// Robinhood's instruments for `symbols`: whether it trades each all day. At
// most `ALL_DAY_BATCH` symbols to a request.
function allDayUrl(symbols) {
  return INSTRUMENTS_URL + "?symbols=" + symbols.map(function(s) { return encodeURIComponent(robinhoodSymbol(s)) }).join(",")
}

// The listings to a request: Robinhood's instruments answer 100 results a
// page and leave the rest to a `next` page, in their own order, and a
// symbol may answer twice (`parseAllDay`), so half of that fits one page.
// Otherwise the symbols on page two read as not trading all day.
var ALL_DAY_BATCH = 50

// Robinhood's instruments answer, by the Yahoo symbols asked for: true for a
// listing it trades all day (`all_day_tradability` "tradable"), false for any
// other, and for one it does not know. Results come in its own order. Null
// for a response that is not Robinhood's, or whose results are not a list
// of at most two for each symbol asked.
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

// Whether a listing's answer on all-day trading (`entry`, { status, allDay,
// at }) is due: never asked; a day after an answer; and a few minutes after
// a failure, which counts as not all-day meanwhile.
function allDayDue(entry, now) {
  if (!entry) return true
  return now - entry.at >= (entry.status === "ok" ? ALL_DAY_INTERVAL : OVERNIGHT_INTERVAL)
}

// Robinhood's answer, by the Yahoo symbols asked for: each one's
// (`overnightAnswer`). Null for a response that is not Robinhood's.
function parseOvernight(json, symbols) {
  var results = overnightResults(json)
  if (!results) return null
  var out = {}
  for (var i = 0; i < symbols.length; i++) out[symbols[i]] = overnightAnswer(results[i], symbols[i])
  return out
}

// Robinhood's results, in the order asked, or null for a response that is
// not Robinhood's, or whose results are not a list within MOST_RESULTS.
function overnightResults(json) {
  return Format.fetchedList(json && json.results, MOST_RESULTS)
}

// One result of Robinhood's answer, for the Yahoo symbol asked for in its
// place: { bars, from, through }. `bars` are its prints, { t, p, s } with s
// its session ("pre", "reg", "post", "overnight"), only the bars that
// traded: bounds=24_5 still fills a quiet name's gaps with flat
// `interpolated` bars. `from` and `through` are the starts of the oldest and
// the newest five-minute slots the answer holds, traded or not, null with
// none: what the answer covers (`joinHour`), and how far Robinhood's day
// reaches, so a night's quiet slots can be counted (`thinNight`). An unknown
// symbol comes back empty, and one that names another symbol, or whose
// prints are not a list within MOST_PRINTS, is no answer for it.
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
    if (!bar.interpolated && Format.isFiniteNumber(t) && Format.isFiniteNumber(p) && p > 0) out.bars.push({ t: t, p: p, s: bar.session })
  }
  return out
}

// The prints in hand (`had`, { bars, through }) brought up to date by an
// hour's answer (`hour`, `overnightAnswer`'s): the hour's slots replace
// what was kept from its first slot on, a bar still forming among them, and
// the older ones stay, the newest MOST_PRINTS of them all, so a surface
// left open keeps no more than a chart can draw. An hour with nothing in
// it changes nothing.
function joinHour(had, hour) {
  if (hour.from === null) return { bars: had.bars, through: had.through }
  return {
    bars: had.bars.filter(function(b) { return b.t < hour.from }).concat(hour.bars).slice(-MOST_PRINTS),
    through: had.through === null || hour.through > had.through ? hour.through : had.through
  }
}

// Whether two answers' prints for a listing are the same, bar by bar.
function sameBars(a, b) {
  if (a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) if (a[i].t !== b[i].t || a[i].p !== b[i].p || a[i].s !== b[i].s) return false
  return true
}

// The 24-hour market's day `dateString`: from the overnight open the evening
// before to the post-market close. It trades when the exchange does.
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

// The night `t` falls in, from the overnight open to the pre-market open,
// open only before a trading day; null outside one.
function nightAt(cal, t) {
  var local = Market.localDate(t, cal)
  var clock = Market.clockOf(local)
  if (clock >= cal.overnight.close && clock < cal.overnight.open) return null
  var day = marketDayAt(cal, t)
  return { start: day.start, end: Market.epochAt(cal, day.date, cal.overnight.close), open: day.open }
}

// Whether a listing's overnight session is on at `t`: a night that trades,
// Sunday evening's and a holiday's included, for one Robinhood trades all
// day (`allDay`).
function nightTrades(quote, allDay, t, calendars) {
  var cal = allDay ? Market.calendarFor(calendars, quote) : null
  var night = cal && cal.overnight ? nightAt(cal, t) : null
  return !!night && night.open
}

// Whether a listing's market is resting at `t`, by its phase and its
// calendar alone, never by how old its data is: awake through its regular
// session (`Market.inRegularSession`), its pre-market and after hours
// (`Market.inExtendedHours`), each by Yahoo's periods or, for a quote held
// from an earlier day, the calendar's, and its overnight session
// (`nightTrades`); asleep through Tokyo's lunch, a weekend, a published
// closure, and the rest of the night. A cryptocurrency never rests.
function marketAsleep(quote, allDay, t, calendars) {
  if (!quote || quote.crypto) return false
  return !nightTrades(quote, allDay, t, calendars) && !Market.inRegularSession(quote, t, calendars) && !Market.inExtendedHours(quote, t, calendars)
}

// Robinhood's prints and Yahoo's own, in time order, each with its session:
// Yahoo's day and what a two-day answer holds after it, the coming day's
// pre-market (`Quote.tailStart`); Robinhood's beside them (`beside`).
function prints(quote, bars) {
  var out = []
  for (var i = 0; i < bars.length; i++) if (beside(quote, bars[i].t)) out.push(bars[i])
  for (var j = 0; j < quote.points.length; j++) {
    var pt = quote.points[j]
    out.push({ t: pt.t, p: pt.p, s: Quote.pointSession(quote, pt) })
  }
  out.sort(function(a, b) { return a.t - b.t })
  return out
}

// Whether Robinhood's bar at `t` is drawn beside `quote`'s own prints:
// before Yahoo's day or after it, up to where Yahoo's own begin again.
function beside(quote, t) {
  var yahooAgain = Quote.tailStart(quote)
  return (t < Quote.dayStart(quote) || t >= Quote.dayEnd(quote)) && (yahooAgain === null || t < yahooAgain)
}

// The newest price a US stock or ETF has traded at since its last regular
// close, { t, p, phase, base, own, closed, dayStart }: the newest print of all (`latest`,
// the chart's, else the quote's own last) where it is an after-hours,
// overnight, or pre-market one (`Quote.extendedPrint`). It is the price on
// top wherever the listing's price shows (`Figures.rowModel`), its move
// from the 1D chart's dashed line (`base`, `Quote.dayBase` of `day`, the
// day the chart draws, `Chart.dayDrawn`), so the number, the line, the
// animal, the rows and the pill agree. `own` says whether that day is the
// quote's own, and `closed` whether its regular session has closed before
// the print: its after hours, and the weekend after a Friday; not its
// pre-market, nor a night or pre-market a new day has begun with. `dayStart`
// is that day's regular open, which names it. Null in the
// regular session, with no trade since the close, and for a listing with
// no extended hours, an index, a coin, or one abroad.
function newestPrint(quote, latest, calendars, day) {
  var print = quote && hasOvernight(quote, calendars) ? Quote.extendedPrint(quote, latest) : null
  if (!print) return null
  var own = day.session.regular.start === quote.session.regular.start
  return { t: print.t, p: print.p, phase: print.phase, base: Quote.dayBase(day), own: own, closed: own && print.t >= quote.session.regular.end,
    dayStart: day.session.regular.start }
}

// The hours trading day `date` draws on its 1D chart, 24 of them: from its
// night's open the evening before, the calendar's (`cal.overnight.open`),
// to the next night's open where a night follows it, else to its
// post-market's close (`postClose`): a Friday's and a holiday eve's 20:00,
// a half day's 17:00. Null for a date that doesn't trade (a weekend, a
// holiday), or past the calendar.
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

// When a trading day's post-market closes: as long after its last close as
// the calendar's post-market lasts, to its close at most, so a half day's
// 13:00 close ends at 17:00, as Robinhood's hours for 27 November say.
function postClose(cal, date) {
  var segs = Market.segmentsOn(cal, date)
  var full = Market.epochAt(cal, date, cal.post.close)
  return Math.min(full, segs[segs.length - 1].end + full - Market.epochAt(cal, date, cal.post.open))
}

// The window (`dayWindow`) the chart shows, by its newest print (`latest`):
// the trading day it belongs to (`marketDayAt`), so the chart turns to the
// next day with the first trade of its night, and a day stays on through
// the weekend or a holiday after it until then. Without a print, the
// quote's own day's. Null past the calendar.
function chartWindow(cal, quote, latest) {
  return dayWindow(cal, marketDayAt(cal, latest ? latest.t : quote.session.regular.start).date)
}

// The periods of the trading day a window's hours belong to: the quote's
// own where they are that day's, else the coming day's a two-day answer
// holds (`Quote.tailDay`), else the calendar's, from its pre-market's open
// to its post-market's close.
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

// The times worth a tick on a window's axis: midnight, the night's end at
// 04:00, and the close. The close is when Yahoo says it is on a day its
// periods describe (`session`), else the calendar's.
function windowTicks(cal, win, session) {
  var ticks = [Market.epochAt(cal, win.date, "00:00"), Market.epochAt(cal, win.date, cal.overnight.close)]
  var segs = Market.segmentsOn(cal, win.date)
  if (segs.length && segs[0].start === session.regular.start) ticks.push(session.regular.end)
  else for (var i = 0; i < segs.length; i++) ticks.push(segs[i].end)
  return ticks
}

// The 1D chart of a listing Robinhood trades all day, apart from its quote,
// from its answer (`answer`, { bars, through }, `overnightAnswer`'s):
// `day`, shaped as a quote so the chart's measures read it as they read
// Yahoo's; and `latest`, the newest print of all, which the price on top
// is. Each print keeps its session, and its clock time comes from the
// calendar. The chart and a scrub of it read the day, and so do the price
// on top and its move (`newestPrint`); the day's figures stay the quote's.
// The day is one trading day (`chartWindow`), on a 24-hour scale from its
// night's open to the next: Friday from Thursday's 20:00 all weekend;
// Monday from Sunday's first night trade; each next day from the first
// trade of its night. Each print stands at its time (`Chart.chartGeometry`),
// so a quiet hour shows as one and a finished day ends at its last
// print's time. Measured from the last regular close before it
// (`Quote.dayBase`): the quote's previous close on its own day, else its
// close, as a scrub of it is (`Figures.scrubbedBase`).
function dayChart(quote, answer, calendars) {
  var cal = Market.calendarFor(calendars, quote)
  if (!cal || !cal.overnight || !quote.session.regular) return { day: quote, latest: null }
  var all = prints(quote, answer.bars)
  var latest = all.length ? all[all.length - 1] : null
  var win = chartWindow(cal, quote, latest)
  if (!win) return { day: quote, latest: latest }
  var session = windowSession(cal, quote, win)
  var own = session === quote.session
  return {
    day: Object.assign({}, quote, {
      session: session,
      next: null,
      points: all.filter(function(p) { return p.t >= win.start }),
      prevClose: own ? quote.prevClose : Quote.regularClose(quote),
      dayOpen: own ? quote.dayOpen : null,
      openSession: own ? quote.openSession : null,
      // `closes`: when the day's last hour ends (`Figures.dayNote`).
      axis: { start: win.start, end: win.end, ticks: windowTicks(cal, win, session), closes: win.end },
      calendar: cal
    }),
    latest: latest
  }
}

// The 1D chart of a US listing Robinhood does not trade all day: Yahoo's own
// day, its pre-market open to its post-market close (04:00 to 20:00), each
// print at its time, with a tick at the close; from the coming day's first
// print a two-day answer holds, that day (`Quote.tailDay`). No prints of
// Robinhood's.
function sessionDay(quote) {
  if (!quote.session.regular) return quote
  var day = Quote.tailDay(quote) || quote
  var pts = day.points
  return Object.assign({}, day, {
    axis: { start: Quote.dayStart(day), end: Math.max(Quote.dayEnd(day), pts.length ? pts[pts.length - 1].t : 0),
      ticks: [day.session.regular.end] }
  })
}

// Whether an open surface should ask Robinhood again for a listing's
// prints, last asked at `askedAt`: never asked; every few minutes while a
// night trades; and once after a night ends, for its last bars. Between a
// night's last bars and the next night, nothing new can come.
function overnightDue(askedAt, now, calendars, failed) {
  var cal = overnightMarket(calendars)
  if (!cal) return false
  if (!askedAt) return true
  // A failed answer is asked again a few minutes on, whatever the hour.
  if (failed) return now - askedAt >= OVERNIGHT_INTERVAL
  var night = nightAt(cal, now)
  if (night && night.open) return now - askedAt >= OVERNIGHT_INTERVAL
  for (var day = marketDayAt(cal, now), i = 0; i < 14; i++, day = marketDay(cal, Market.previousDateString(day.date))) {
    var ended = Market.epochAt(cal, day.date, cal.overnight.close) + OVERNIGHT_LAG
    if (day.open && ended <= now) return askedAt < ended
  }
  return false
}
