.pragma library
.import "Calendar.js" as Calendar
.import "Format.js" as Format
.import "Market.js" as Market
.import "Quote.js" as Quote

// Robinhood's trades: what is asked of it and when, its answers, the
// night's hours, and a listing's trades with Yahoo's (`allTrades`). The day
// a 1D chart draws from them is `Day.js`'s.

var ROBINHOOD_URL = "https://api.robinhood.com/marketdata/historicals/"
var QUOTES_URL = "https://api.robinhood.com/marketdata/quotes/"
var INSTRUMENTS_URL = "https://api.robinhood.com/instruments/"

// Robinhood's newest bar arrives five to ten minutes after it starts.
var OVERNIGHT_LAG = 10 * 60

// A night's price says "As of" past two minutes, as a day's does
// (`Freshness.LIVE_QUOTE_MAX_AGE`): Robinhood's quote is asked every minute.
var OVERNIGHT_STALE = 2 * 60

// Robinhood's bars are five minutes each.
var SLOT = 5 * 60

var OVERNIGHT_INTERVAL = 5 * 60

var LIST_DATE_INTERVAL = 24 * 60 * 60
var LIST_DATE_SETTLED = 30 * 24 * 60 * 60

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

// For `Quote.parseChart` to set aside a bar Yahoo stamps in a US stock's or
// ETF's night, by the clock, from 20:00 to 04:00 every day: whether `t` is
// in it. Null for a listing with no night. Asked of every bar, so each day's
// hours are worked out once.
function yahooNight(listing, calendars) {
  var cal = hasOvernight(listing, calendars) ? Calendar.calendarFor(calendars, listing) : null
  if (!cal) return null
  var day = { from: 0, to: 0 }
  return function(t) {
    if (t >= day.from && t < day.to) return false
    var date = Calendar.dateStringOf(Calendar.localDate(t, cal))
    day = { from: Calendar.epochAt(cal, date, cal.overnight.close), to: Calendar.epochAt(cal, date, cal.overnight.open) }
    return t < day.from || t >= day.to
  }
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

// Robinhood answered with no slot at all: a symbol it doesn't carry, such
// as a preferred share (BAC.PL), whose place in its answer is a
// placeholder. Each symbol it carries answers every slot, traded or not.
function uncarried(entry) {
  return !!entry && entry.status === "ok" && entry.through === null
}

// One Robinhood doesn't carry goes in a day's request that goes anyway, or
// one of its own, so it never draws the others into a day's.
function overnightBatches(symbols, entries, now) {
  var none = symbols.filter(function(s) { return uncarried(entries[s]) })
  var carried = symbols.filter(function(s) { return !uncarried(entries[s]) })
  var day = carried.filter(function(s) { return overnightSpan(entries[s], now) === "day" })
  var hour = carried.filter(function(s) { return overnightSpan(entries[s], now) === "hour" })
  var dayRequests = Math.ceil(day.length / OVERNIGHT_BATCH)
  if (dayRequests + Math.ceil(hour.length / HOUR_BATCH) > Math.ceil(carried.length / OVERNIGHT_BATCH)) {
    var room = dayRequests * OVERNIGHT_BATCH - day.length
    day = day.concat(hour.slice(0, room))
    hour = hour.slice(room)
  }
  day = day.concat(none)
  var batches = []
  for (var i = 0; i < day.length; i += OVERNIGHT_BATCH) batches.push({ span: "day", symbols: day.slice(i, i + OVERNIGHT_BATCH) })
  for (var j = 0; j < hour.length; j += HOUR_BATCH) batches.push({ span: "hour", symbols: hour.slice(j, j + HOUR_BATCH) })
  return batches
}

// Past these, an answer is bad (`Format.fetchedList`). MOST_TRADES also caps
// the trades kept (`joinTrades`): a 1D chart draws at most 336 slots.
var MOST_RESULTS = 2 * HOUR_BATCH
var MOST_TRADES = 1000

function listDateUrl(symbols) {
  return INSTRUMENTS_URL + "?symbols=" + symbols.map(function(s) { return encodeURIComponent(robinhoodSymbol(s)) }).join(",")
}

// Robinhood's instruments answer 100 results a page, in their own order,
// and a symbol may answer twice: past 50, symbols on page two would read as
// never listed.
var LIST_DATE_BATCH = 50

// The day Robinhood says each listed, as "2026-11-19", where it says one;
// null for an answer that can't be read. Robinhood can answer a symbol
// twice, in its own order.
function listDates(json, symbols) {
  var results = Format.fetchedList(json && json.results, 2 * symbols.length)
  if (!results) return null
  var bySymbol = Object.create(null)
  for (var j = 0; j < results.length; j++) {
    var r = results[j]
    if (r && typeof r.symbol === "string" && !(r.symbol in bySymbol)
        && typeof r.list_date === "string" && /^\d{4}-\d\d-\d\d$/.test(r.list_date))
      bySymbol[r.symbol] = r.list_date
  }
  var out = {}
  for (var i = 0; i < symbols.length; i++) {
    var date = bySymbol[robinhoodSymbol(symbols[i])]
    if (date) out[symbols[i]] = date
  }
  return out
}

// The day `symbol` listed, from a check's answer (`dates`, null when the
// check failed). A failed check keeps the last answer's date, or none.
function listDateEntry(dates, symbol, had, at) {
  return dates ? { status: "ok", listDate: dates[symbol] || null, at: at }
    : { status: "failed", listDate: had && had.listDate || null, at: at }
}

// Robinhood's listing date on each quote it gave one for, so a listing's
// first day names its IPO price (`Quote.listingDay`). A quote stays on its
// day until the next session, a Friday listing's through the weekend and a
// holiday after it, so only a date of the last week, by `now`, can be a
// quote's listing day, and only those quotes are read. The same object
// where none changes.
function withListDates(quotes, listDates, now) {
  var since = new Date((now - 7 * 86400) * 1000).toISOString().slice(0, 10)
  var out = quotes
  for (var symbol in listDates) {
    var date = listDates[symbol] && listDates[symbol].listDate || null
    if (!date || date < since) continue
    var quote = quotes[symbol]
    if (!quote || quote.listDate === date) continue
    if (out === quotes) out = Object.assign({}, quotes)
    out[symbol] = Object.assign({}, quote, { listDate: date })
  }
  return out
}

// A listing whose IPO date is over a month past can never become a first
// trading day again, so it needs no daily re-check.
function listDateSettled(entry, now) {
  if (!entry || entry.status !== "ok" || !entry.listDate) return false
  var cutoff = new Date((now - LIST_DATE_SETTLED) * 1000).toISOString().slice(0, 10)
  return entry.listDate < cutoff
}

function listDateDue(entry, now) {
  if (!entry) return true
  if (listDateSettled(entry, now)) return false
  return now - entry.at >= (entry.status === "ok" ? LIST_DATE_INTERVAL : OVERNIGHT_INTERVAL)
}

function overnightResults(json) {
  return Format.fetchedList(json && json.results, MOST_RESULTS)
}

// bounds=24_5 fills a quiet name's gaps with flat `interpolated` bars,
// which are no trades. `from` and `through` count every slot, traded or
// not: how far the answer reaches. A trade in a session Robinhood never
// sends, such as "__proto__", is left out: its name becomes the warning's.
var SESSIONS = ["pre", "reg", "post", "overnight"]

// The answer for `asked[at]`, from the results of the request that asked
// for `asked`: the result naming it, wherever it is, else, where Robinhood
// doesn't carry it, the placeholder in its place, which names no symbol and
// has no slot. A place counts only in an answer with a result for every
// listing asked: in one that left a listing out, a placeholder may have
// moved into another's place. Null where the answer left the listing out,
// so it is asked again soon, never taken as not carried.
function overnightAnswer(results, asked, at) {
  var out = { bars: [], from: null, through: null }
  var name = robinhoodSymbol(asked[at])
  var result = results[at] && results[at].symbol === name ? results[at] : null
  for (var i = 0; !result && i < results.length; i++) if (results[i] && results[i].symbol === name) result = results[i]
  if (!result) return results.length === asked.length && results[at] && results[at].symbol === "" ? out : null
  var historicals = Format.fetchedList(result.historicals, MOST_TRADES)
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

// A bar still forming may be among an answer's slots, so they replace what
// was kept from their first on.
function joinTrades(had, answer) {
  if (answer.from === null) return { bars: had.bars, through: had.through }
  return {
    bars: had.bars.filter(function(b) { return b.t < answer.from }).concat(answer.bars).slice(-MOST_TRADES),
    through: had.through === null || answer.through > had.through ? answer.through : had.through
  }
}

// What a listing keeps of an answer: joined on to the trades in hand, so a
// day asked again keeps the night before that it no longer reaches, and the
// listing keeps trading at night (`tradesAtNight`). An hour can't stand for
// a day: one with none in hand, whose trades went meanwhile
// (`Service.forgetLeft`), is left unanswered.
function keptTrades(had, answer, span) {
  if (!answer) return null
  if (had) return joinTrades(had, answer)
  return span === "hour" ? null : { bars: answer.bars, through: answer.through }
}

function sameBars(a, b) {
  if (a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) if (a[i].t !== b[i].t || a[i].p !== b[i].p || a[i].s !== b[i].s) return false
  return true
}

// ---- Robinhood's quote: the night's last trade

// Robinhood took 150 symbols a quote request when we measured, at about
// 840 bytes each; its historicals take 75, and so does this.
var LAST_TRADE_BATCH = 75

function lastTradeUrl(symbols) {
  return QUOTES_URL + "?symbols=" + symbols.map(function(s) { return encodeURIComponent(robinhoodSymbol(s)) }).join(",") + "&bounds=24_5"
}

function lastTradeCap(count) {
  return 16000 + 4000 * count
}

// Each listing's last trade outside the regular session, at its venue's
// time, whole seconds, from a quote's answer; null for one Robinhood sent
// none for, and null for the whole answer when it can't be read. The bid
// and ask are never read: a price between them is no trade. Robinhood
// answers an unknown symbol null, in the order asked.
function lastTrades(json, symbols) {
  var results = Format.fetchedList(json && json.results, symbols.length)
  if (!results) return null
  var bySymbol = Object.create(null)
  for (var j = 0; j < results.length; j++) {
    var x = results[j]
    if (x && typeof x.symbol === "string" && !(x.symbol in bySymbol)) bySymbol[x.symbol] = x
  }
  var out = {}
  for (var i = 0; i < symbols.length; i++) {
    var r = bySymbol[robinhoodSymbol(symbols[i])]
    // Its venue's clock to the nanosecond, which Date.parse can't read.
    var stamp = r && typeof r.venue_last_non_reg_trade_time === "string" ? r.venue_last_non_reg_trade_time.replace(/(\.\d{3})\d+/, "$1") : ""
    var t = Math.floor(Date.parse(stamp) / 1000)
    var p = r ? Number(r.last_non_reg_trade_price) : NaN
    out[symbols[i]] = Format.isFiniteNumber(t) && Format.isFiniteNumber(p) && p > 0 ? { t: t, p: p, s: "overnight" } : null
  }
  return out
}

// The quote's trade, where it is tonight's and newer than every bar the
// chart has: one in an open night, from 20:00 to 04:00, since from 04:00
// Yahoo has the pre-market. A bar's close is its slot's last trade as
// Robinhood answered, so a trade inside the newest bar's slot is newer only
// where the quote was asked no earlier than the bars. `entry` is the quote
// feed's, `night` the trades', `cal` the night's calendar.
function joinedTrade(night, entry, cal) {
  var trade = entry ? entry.trade : null
  var hours = trade && cal ? nightAt(cal, trade.t) : null
  if (!night || !hours || !hours.open) return null
  var last = night.bars.length ? night.bars[night.bars.length - 1] : null
  if (last && (trade.t <= last.t || (trade.t < last.t + SLOT && entry.at < night.at))) return null
  return trade
}

// A lone night trade from Robinhood's quote, shaped as an answer for
// `Day.dayChart` while a listing out of sight has no trades of its own yet:
// only a trade in an open night, so an after-hours or pre-market trade stays
// Yahoo's alone.
function quotedNight(entry, cal) {
  var trade = entry ? entry.trade : null
  var hours = trade && cal ? nightAt(cal, trade.t) : null
  return hours && hours.open ? { bars: [trade], from: trade.t, through: trade.t } : null
}

// Robinhood's trades, each listing's with its quote's trade at their end
// where `joinedTrade` takes it: what the chart, the rows' lines and the
// price on top read. `had` is the last call's { nights, joins }: a listing
// whose trades and quote didn't change keeps its object, and so do the
// nights while none does.
function joinedNights(nights, lastTrades, cal, had) {
  var joins = {}
  var out = {}
  var same = Object.keys(nights).length === Object.keys(had.nights).length
  for (var symbol in nights) {
    var night = nights[symbol]
    var trade = joinedTrade(night, lastTrades[symbol], cal)
    var join = had.joins[symbol]
    if (trade) joins[symbol] = join && join.night === night && join.trade === trade ? join
      : { night: night, trade: trade, joined: Object.assign({}, night, {
        bars: join && join.night.bars === night.bars && join.trade === trade ? join.joined.bars : night.bars.concat([trade]) }) }
    out[symbol] = trade ? joins[symbol].joined : night
    same = same && had.nights[symbol] === out[symbol]
  }
  return { nights: same ? had.nights : out, joins: joins }
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

// The last night the market traded that began by `t`; null past the
// calendar.
function lastNight(cal, t) {
  for (var day = marketDayAt(cal, t), i = 0; i < 14; i++, day = marketDay(cal, Calendar.previousDateString(day.date)))
    if (day.open && day.start <= t) return day
  return null
}

// Whether Robinhood's trades (`night`, its entry) show a US listing
// trading at night: a night trade in the night its answer reaches, while it
// reaches one, or in the night before; by day, in the night just gone. So a
// thin stock that skips a night stays awake through it, one that starts
// trading in the night wakes at its first trade, and one with no night
// trades shows the day alone, as Yahoo has it.
function tradesAtNight(night, cal) {
  if (!night || night.through === null || !cal || !cal.overnight) return false
  var last = lastNight(cal, night.through)
  if (!last) return false
  var before = night.through < Calendar.epochAt(cal, last.date, cal.overnight.close) ? lastNight(cal, last.start - 1) : null
  var from = before ? before.start : last.start
  for (var i = night.bars.length - 1; i >= 0 && night.bars[i].t >= from; i--) if (night.bars[i].s === "overnight") return true
  return false
}

// Whether the night trades `quote`'s listing now: one that trades at night
// (`atNight`, `tradesAtNight`), in an open night.
function nightTrades(quote, atNight, t, calendars) {
  var cal = atNight ? Calendar.calendarFor(calendars, quote) : null
  var night = cal && cal.overnight ? nightAt(cal, t) : null
  return !!night && night.open
}

// The listings whose newest price may be a trade Robinhood failed to send,
// while the night trades (`open`): those whose trades failed, so Stonks
// can't tell whether they traded, and those that trade at night whose
// quote failed. A quote is asked only of those (`Asks.lastTradeListings`),
// so one left from a night a listing traded counts no more once it
// doesn't. `nights` and `lastTrades` are Robinhood's entries, `cal` the
// night's calendar.
function nightFailures(nights, lastTrades, open, cal, since) {
  var out = {}
  if (!open) return out
  var floor = since || 0
  for (var symbol in nights) if (nights[symbol].status === "failed" && nights[symbol].at >= floor) out[symbol] = true
  for (var quoted in lastTrades)
    if (lastTrades[quoted].status === "failed" && lastTrades[quoted].at >= floor && tradesAtNight(nights[quoted], cal)) out[quoted] = true
  return out
}

function marketAsleep(quote, atNight, t, calendars) {
  if (!quote || quote.crypto) return false
  return !nightTrades(quote, atNight, t, calendars) && !Market.inRegularSession(quote, t, calendars) && !Market.inExtendedHours(quote, t, calendars)
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
// counts. Before the open, the pre-market is the coming day's, Yahoo's
// answer still the day that closed (`quote.next`).
function yahooHole(quote) {
  if (!quote) return null
  if (quote._yahooHole !== undefined) return quote._yahooHole
  var last = null
  var pres = [quote.session.pre, quote.next ? quote.next.pre : null]
  for (var d = 0; d < pres.length; d++) {
    var hole = pres[d] ? preHole(quote, pres[d]) : null
    if (hole !== null) last = hole
  }
  try { Object.defineProperty(quote, "_yahooHole", { value: last, enumerable: false }) } catch (e) {}
  return last
}

function preHole(quote, pre) {
  var pts = quote.points
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
// `stepped`: the trade joined the day that closed, tonight's or then the
// pre-market's (`Day.dayChart`). Such trades belong to the day ahead, so
// they count from the close just gone, with no open yet, and so does a
// scrub past that day's bell (`Figures.scrubbedBase`). `joined`: tonight's.
// `own`: the day drawn is Yahoo's quote's, whose open the move may count
// from. `dayStart` names the day the move is of: the day drawn, or the
// pre-market's own.
function newestTrade(quote, latest, calendars, day) {
  var trade = quote && hasOvernight(quote, calendars) ? Quote.extendedTrade(quote, latest) : null
  if (!trade) return null
  var own = day.session.regular.start === quote.session.regular.start
  var stepped = !!day.tonight && trade.t >= day.tonight
  var joined = stepped && trade.phase === "overnight"
  return { t: trade.t, p: trade.p, phase: trade.phase, base: stepped ? Quote.regularClose(day) : Quote.dayBase(day), own: own && !stepped,
    closed: own && trade.phase !== "pre" && trade.t >= quote.session.regular.end, joined: joined, stepped: stepped,
    dayStart: stepped && !joined ? trade.t : day.session.regular.start }
}

function overnightDue(askedAt, now, calendars, failed) {
  var cal = overnightMarket(calendars)
  if (!cal) return false
  if (!askedAt) return true
  var night = nightAt(cal, now)
  if (failed) return (!!night && night.open && askedAt < night.start) || now - askedAt >= OVERNIGHT_INTERVAL
  if (night && night.open) return now - askedAt >= OVERNIGHT_INTERVAL
  for (var day = marketDayAt(cal, now), i = 0; i < 14; i++, day = marketDay(cal, Calendar.previousDateString(day.date))) {
    var ended = Calendar.epochAt(cal, day.date, cal.overnight.close) + OVERNIGHT_LAG
    if (day.open && ended <= now) return askedAt < ended
  }
  return false
}
