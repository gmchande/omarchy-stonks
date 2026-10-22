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
// draws its prints, on a 1D chart of one New York calendar day, midnight to
// midnight, the way Robinhood's screen draws it: Yahoo's day, and
// Robinhood's prints for the hours before it and after it; unless the night
// after Yahoo's day trades thinly (`thinNight`), when the chart is Yahoo's
// day and that night's few trades after it, each on its own. Any other has
// Yahoo's own day, 04:00 to 20:00: a thin name trades a few shares
// overnight now and then (two at 23:10 on 6 October, in the saved answers),
// and none of them is a night's price. The overnight print is never the
// headline, nor in the day's high, low, or change: those stay Yahoo's.

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
// its closed days left out (seen Sunday 4 October, 22:58 ET: Thursday 22:55
// onward), so one answer holds every print a 1D chart can draw. At most
// `OVERNIGHT_BATCH` symbols to a request.
function overnightUrl(symbols) {
  return ROBINHOOD_URL + "?symbols=" + symbols.map(function(s) { return encodeURIComponent(robinhoodSymbol(s)) }).join(",")
    + "&interval=5minute&span=day&bounds=24_5"
}

// The listings to a request: a third of the 75 Robinhood's historicals
// take ("Too many instruments requested. No more than 75 allowed."), so
// each answer, read in one JSON.parse that can't be sliced, is a third as
// long: 75 listings came to about 4 MB.
var OVERNIGHT_BATCH = 25

// The most entries a list in Robinhood's answers may hold, past which the
// answer is a bad one (`Format.fetchedList`): a result for each symbol
// asked, one each in the saved answers, so twice the most asked at once; a
// listing's prints, span=day's 288 five-minute slots, 288 in the saved
// answers.
var MOST_RESULTS = 2 * OVERNIGHT_BATCH
var MOST_PRINTS = 1000

// Robinhood's instruments for `symbols`, one request for all: whether it
// trades each all day.
function allDayUrl(symbols) {
  return INSTRUMENTS_URL + "?symbols=" + symbols.map(function(s) { return encodeURIComponent(robinhoodSymbol(s)) }).join(",")
}

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
// place: { bars, through }. `bars` are its prints, { t, p, s } with s its
// session ("pre", "reg", "post", "overnight"), only the bars that traded:
// bounds=24_5 still fills a quiet name's gaps with flat `interpolated`
// bars. `through` is the start of the newest five-minute slot the answer
// holds, traded or not, null with none: how far Robinhood's day reaches, so
// a night's quiet slots can be counted (`thinNight`). An unknown symbol
// comes back empty, and one that names another symbol, or whose prints are
// not a list within MOST_PRINTS, is no answer for it.
function overnightAnswer(result, symbol) {
  var out = { bars: [], through: null }
  var historicals = result && result.symbol === robinhoodSymbol(symbol) ? Format.fetchedList(result.historicals, MOST_PRINTS) : null
  if (!historicals) return out
  for (var j = 0; j < historicals.length; j++) {
    var bar = historicals[j]
    var t = Date.parse(bar.begins_at) / 1000
    var p = Number(bar.close_price)
    if (Format.isFiniteNumber(t) && (out.through === null || t > out.through)) out.through = t
    if (!bar.interpolated && Format.isFiniteNumber(t) && Format.isFiniteNumber(p) && p > 0) out.bars.push({ t: t, p: p, s: bar.session })
  }
  return out
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

function tradingDayBefore(cal, date) {
  var day = Market.previousDateString(date)
  for (var i = 0; i < 14 && Market.dayKind(cal, day).kind !== "open"; i++) day = Market.previousDateString(day)
  return day
}

// The day a closed date's 1D chart shows: the last trading day before it,
// all day.
// PROVISIONAL from 20:00 on a closed date a session follows (Sunday, the
// evening after a holiday): that night trades for the next day, and
// Robinhood's screen may draw it on another chart. Sunday 11 October's
// captures settle it.
function closedDateChart(cal, date) {
  return tradingDayBefore(cal, date)
}

// The trading day the 1D chart shows: the New York date of the newest print
// (`newest`, its time), so a new day begins with its first print and the
// chart never stands empty between midnight and then; on a closed date,
// `closedDateChart`.
function chartDate(cal, newest) {
  var date = Market.dateStringOf(Market.localDate(newest, cal))
  return Market.dayKind(cal, date).kind === "open" ? date : closedDateChart(cal, date)
}

// The close the chart of `date` is measured from, the one before its regular
// session: Yahoo's previous close once its bars are that day's, and its
// regular close while they are still the day before, from midnight to the
// pre-market.
// PROVISIONAL from 20:00 to midnight: the night after the close stays on the
// day's previous close, while the line under the price measures it from the
// day's own close. The 7 October 20:10 and 23:00 captures settle which close
// Robinhood's chart measures it from.
function dayBaseline(quote, cal, date) {
  var bars = Market.dateStringOf(Market.localDate(quote.session.regular.start, cal))
  return bars < date ? Quote.regularClose(quote) : quote.prevClose
}

// Robinhood's prints outside Yahoo's day and Yahoo's own, in time order, each
// with its session.
function prints(quote, bars) {
  var from = Quote.dayStart(quote)
  var to = Quote.dayEnd(quote)
  var out = []
  for (var i = 0; i < bars.length; i++) {
    if (bars[i].t < from || bars[i].t >= to) out.push(bars[i])
  }
  for (var j = 0; j < quote.points.length; j++) {
    var pt = quote.points[j]
    out.push({ t: pt.t, p: pt.p, s: Quote.pointSession(quote, pt) })
  }
  out.sort(function(a, b) { return a.t - b.t })
  return out
}

// The times worth a tick on `date`'s axis: the night's end, the close, and
// the next night's start when one follows.
function dayTicks(cal, date, regular) {
  var ticks = [Market.epochAt(cal, date, cal.overnight.close)]
  var segs = Market.segmentsOn(cal, date)
  // The response's own day closes when Yahoo says it does.
  if (segs.length && segs[0].start === regular.start) ticks.push(regular.end)
  else for (var i = 0; i < segs.length; i++) ticks.push(segs[i].end)
  var evening = Market.epochAt(cal, date, cal.overnight.open)
  if (nightAt(cal, evening).open) ticks.push(evening)
  return ticks
}

// The night after `quote`'s day: the overnight session before the next day
// the market trades, Sunday evening's after a Friday, from its open to its
// close.
function nightAfter(cal, quote) {
  var date = Market.dateStringOf(Market.localDate(quote.session.regular.start, cal))
  var day = marketDay(cal, Market.nextDateString(date))
  for (var i = 0; i < 14 && !day.open; i++) day = marketDay(cal, Market.nextDateString(day.date))
  return { start: day.start, end: Market.epochAt(cal, day.date, cal.overnight.close) }
}

// Robinhood's bars are five minutes each.
var SLOT = 5 * 60

// The share of a night's five-minute slots so far a stock trades in for its
// night to be traded through. In the saved answers, the listings that trade
// the night through traded in every slot, and the rest in 70% at most.
var TRADED_THROUGH = 0.9

// Whether `night` trades thinly in Robinhood's answer for a listing
// (`answer`, { bars, through }): it has begun there, and fewer than
// TRADED_THROUGH of its five-minute slots so far traded. A night not begun
// is neither.
function thinNight(night, answer) {
  if (answer.through === null || answer.through < night.start) return false
  var slots = Math.floor((Math.min(answer.through, night.end - SLOT) - night.start) / SLOT) + 1
  var traded = answer.bars.filter(function(b) { return b.t >= night.start && b.t < night.end }).length
  return traded < TRADED_THROUGH * slots
}

// The 1D chart of a listing Robinhood trades all day, apart from its quote,
// from its answer (`answer`, { bars, through }, `overnightAnswer`'s):
// `day`, shaped as a quote so the chart's measures read it as they read
// Yahoo's; and `latest`, the newest print of all, which the line under the
// price names wherever it falls. Each print keeps its session, and its
// clock time comes from the calendar. Only the chart and a scrub of it read
// the day: the headline and the day's figures stay the quote's.
// The day is the New York calendar day `chartDate` names, midnight to
// midnight, laid out by print (`Chart.chartGeometry`), with the hours to
// come empty: the prints inside it, its axis, and its baseline
// (`dayBaseline`) as its `prevClose`. Through a night after Yahoo's day that
// trades thinly (`thinNight`), it is `dayAndNight`.
function dayChart(quote, answer, calendars) {
  var cal = Market.calendarFor(calendars, quote)
  if (!cal || !cal.overnight || !quote.session.regular) return { day: quote, latest: null }
  var all = prints(quote, answer.bars)
  var latest = all.length ? all[all.length - 1] : null
  var night = nightAfter(cal, quote)
  if (thinNight(night, answer)) return { day: dayAndNight(quote, answer.bars, night, cal), latest: latest }
  var date = chartDate(cal, latest ? latest.t : quote.session.regular.start)
  var start = Market.epochAt(cal, date, "00:00")
  var end = Market.epochAt(cal, Market.nextDateString(date), "00:00")
  return {
    day: Object.assign({}, quote, {
      points: all.filter(function(p) { return p.t >= start && p.t < end }),
      prevClose: dayBaseline(quote, cal, date),
      axis: { start: start, end: end, ticks: dayTicks(cal, date, quote.session.regular), byPrint: true },
      calendar: cal
    }),
    latest: latest
  }
}

// A thin night's 1D: Yahoo's day as `sessionDay` lays it out, measured from
// its previous close, then the night after it (`axis.night`) to its close,
// its trades by the clock, each on its own (`Chart.chartGeometry`). The
// hours between the day's end and the night's start, a weekend's, take no
// room (`axis.dayEnd`). Ticks at the close and the night's start.
function dayAndNight(quote, bars, night, cal) {
  return Object.assign({}, quote, {
    points: quote.points.concat(bars.filter(function(b) { return b.t >= night.start && b.t < night.end })),
    axis: { start: Quote.dayStart(quote), end: night.end, ticks: [quote.session.regular.end, night.start], byPrint: true,
      dayEnd: Quote.dayEnd(quote), night: night },
    calendar: cal
  })
}

// The 1D chart of a US listing Robinhood does not trade all day: Yahoo's own
// day, its pre-market open to its post-market close (04:00 to 20:00), laid
// out by print, with a tick at the close; no prints of Robinhood's, and no
// day apart from the quote's.
function sessionDay(quote) {
  if (!quote.session.regular) return quote
  return Object.assign({}, quote, {
    axis: { start: Quote.dayStart(quote), end: Quote.dayEnd(quote), ticks: [quote.session.regular.end], byPrint: true }
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
