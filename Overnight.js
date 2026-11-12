.pragma library
.import "Calendar.js" as Calendar
.import "Format.js" as Format
.import "Market.js" as Market
.import "Quote.js" as Quote

// Robinhood's trades: what is asked of it and when, its answers, the
// night's hours, and a listing's trades with Yahoo's (`allTrades`). The day
// a 1D chart draws from them is `Day.js`'s.

var ROBINHOOD_URL = "https://api.robinhood.com/marketdata/historicals/"
var INSTRUMENTS_URL = "https://api.robinhood.com/instruments/"

// Robinhood's newest bar arrives five to ten minutes after it starts.
var OVERNIGHT_LAG = 10 * 60

// A liquid name's newest bar is ten to fifteen minutes old, so a trade
// dims only once it has missed one.
var OVERNIGHT_STALE = 20 * 60

// Robinhood's bars are five minutes each.
var SLOT = 5 * 60

var OVERNIGHT_INTERVAL = 5 * 60

var ALL_DAY_INTERVAL = 24 * 60 * 60

function overnightMarket(calendars) {
  var map = Calendar.calendarMap(calendars)
  for (var id in map) if (map[id] && map[id].overnight) return map[id]
  return null
}

function hasOvernight(quote, calendars) {
  if (!quote || (quote.instrumentType !== "EQUITY" && quote.instrumentType !== "ETF")) return false
  var cal = Calendar.calendarFor(calendars, quote)
  return !!cal && !!cal.overnight
}

// Yahoo writes BRK-B, Robinhood BRK.B.
function robinhoodSymbol(symbol) {
  return String(symbol).replace(/-/g, ".")
}

// span=day holds the last 288 five-minute slots the 24/5 market traded, its
// closed days left out: every trade a 1D chart can draw. span=hour holds
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

// An hour's answer joins on to the trades in hand with no slot missed
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

// Past these, an answer is bad (`Format.fetchedList`). MOST_TRADES also caps
// the trades kept (`joinHour`): a 1D chart draws at most 336 slots.
var MOST_RESULTS = 2 * HOUR_BATCH
var MOST_TRADES = 1000

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

// Robinhood's word on whether `symbol` trades all day, from a check's
// answer (`parsed`, null when the check failed). A failed check keeps the
// last answer, or none: `allDay` null, never said either way.
function allDayEntry(parsed, symbol, had, at) {
  return parsed ? { status: "ok", allDay: parsed[symbol], at: at } : { status: "failed", allDay: had ? had.allDay : null, at: at }
}

function allDayDue(entry, now) {
  if (!entry) return true
  return now - entry.at >= (entry.status === "ok" ? ALL_DAY_INTERVAL : OVERNIGHT_INTERVAL)
}

function overnightResults(json) {
  return Format.fetchedList(json && json.results, MOST_RESULTS)
}

// bounds=24_5 fills a quiet name's gaps with flat `interpolated` bars,
// which are no trades. `from` and `through` count every slot, traded or
// not: how far the answer reaches. A trade in a session Robinhood never
// sends, such as "__proto__", is left out: its name becomes the warning's.
var SESSIONS = ["pre", "reg", "post", "overnight"]

function overnightAnswer(result, symbol) {
  var out = { bars: [], from: null, through: null }
  var historicals = result && result.symbol === robinhoodSymbol(symbol) ? Format.fetchedList(result.historicals, MOST_TRADES) : null
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
    bars: had.bars.filter(function(b) { return b.t < hour.from }).concat(hour.bars).slice(-MOST_TRADES),
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
    start: Calendar.epochAt(cal, Calendar.previousDateString(dateString), cal.overnight.open),
    open: Calendar.dayKind(cal, dateString).kind === "open"
  }
}

function marketDayAt(cal, t) {
  var local = Calendar.localDate(t, cal)
  var dateString = Calendar.dateStringOf(local)
  return marketDay(cal, Calendar.clockOf(local) >= cal.overnight.open ? Calendar.nextDateString(dateString) : dateString)
}

function nightAt(cal, t) {
  var local = Calendar.localDate(t, cal)
  var clock = Calendar.clockOf(local)
  if (clock >= cal.overnight.close && clock < cal.overnight.open) return null
  var day = marketDayAt(cal, t)
  return { start: day.start, end: Calendar.epochAt(cal, day.date, cal.overnight.close), open: day.open }
}

function nightTrades(quote, allDay, t, calendars) {
  var cal = allDay ? Calendar.calendarFor(calendars, quote) : null
  var night = cal && cal.overnight ? nightAt(cal, t) : null
  return !!night && night.open
}

// The listings whose newest price may be a trade Robinhood failed to send,
// while the night trades (`open`): those it has never said trade all day or
// not, its last check failed, and those it trades all day whose trades
// failed. `allDay` and `nights` are Robinhood's entries.
function nightFailures(allDay, nights, open) {
  var out = {}
  if (!open) return out
  for (var symbol in allDay) {
    var tradability = allDay[symbol]
    var night = nights[symbol]
    if (tradability.allDay === null ? tradability.status === "failed" : tradability.allDay && !!night && night.status === "failed") out[symbol] = true
  }
  return out
}

function marketAsleep(quote, allDay, t, calendars) {
  if (!quote || quote.crypto) return false
  return !nightTrades(quote, allDay, t, calendars) && !Market.inRegularSession(quote, t, calendars) && !Market.inExtendedHours(quote, t, calendars)
}

function allTrades(quote, bars) {
  var own = ownTrades(quote, bars)
  var filled = fillsBetween(quote, bars, own)
  for (var k = 0; k < filled.length; k++) own = own.concat(filled[k].bars)
  if (filled.length) own.sort(function(a, b) { return a.t - b.t })
  return own
}

function ownTrades(quote, bars) {
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
// fill such a stretch, HOLE_SLOTS or more slots with no trade, where it
// traded in at least half of them: a thin stock's sparse trading is no such
// stretch. A stretch lies between two trades, so the price on top is never
// Robinhood's from it.
function filledStretches(quote, bars) {
  return fillsBetween(quote, bars, ownTrades(quote, bars))
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

// The trades in hand may stop at the night's end, short of Yahoo's empty
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

// `closed`: the trade came after its day's regular close, through the
// night until 04:00 and the weekend after a Friday; never in a pre-market.
// `joined`: tonight's trade on the day that closed. Tonight's trades belong
// to the day ahead, so a joined trade counts from the close just gone, with
// no open yet, as the pre-market's does after 04:00 (`Quote.tailDay`).
// `own`: the day drawn is Yahoo's quote's, whose open the move may count
// from. `dayStart` names the day drawn.
function newestTrade(quote, latest, calendars, day) {
  var trade = quote && hasOvernight(quote, calendars) ? Quote.extendedTrade(quote, latest) : null
  if (!trade) return null
  var own = day.session.regular.start === quote.session.regular.start
  var joined = trade.phase === "overnight" && !!day.tonight && trade.t >= day.tonight
  return { t: trade.t, p: trade.p, phase: trade.phase, base: joined ? Quote.regularClose(quote) : Quote.dayBase(day), own: own && !joined,
    closed: own && trade.t >= quote.session.regular.end, joined: joined, dayStart: day.session.regular.start }
}

// The newest trade as the rows and the pill read it at rest: none once
// tonight has traded, so they keep the day's close and move until the new
// day's first prices arrive, soon after 04:00, as the 1D chart keeps its
// day. The panel's price on top is tonight's.
function restingNewest(newest) {
  return newest && newest.joined ? null : newest
}

function overnightDue(askedAt, now, calendars, failed) {
  var cal = overnightMarket(calendars)
  if (!cal) return false
  if (!askedAt) return true
  if (failed) return now - askedAt >= OVERNIGHT_INTERVAL
  var night = nightAt(cal, now)
  if (night && night.open) return now - askedAt >= OVERNIGHT_INTERVAL
  for (var day = marketDayAt(cal, now), i = 0; i < 14; i++, day = marketDay(cal, Calendar.previousDateString(day.date))) {
    var ended = Calendar.epochAt(cal, day.date, cal.overnight.close) + OVERNIGHT_LAG
    if (day.open && ended <= now) return askedAt < ended
  }
  return false
}
