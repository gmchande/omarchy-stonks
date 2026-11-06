.pragma library
.import "Format.js" as Format
.import "Market.js" as Market
.import "Overnight.js" as Overnight
.import "Quote.js" as Quote

// What a quote shows on screen, in rows, the hero, the info lines and the
// pill. Knows nothing of how the quote was parsed or when markets open.

function arrowAngle(pctChange) {
  if (!Format.isFiniteNumber(pctChange)) return 0
  return Format.clamp(pctChange / 5, -1, 1) * 45
}

// Yahoo names a pair with its currency ("Bitcoin USD"), so a name shown
// whole that ends with the code already says it.
function listingMeta(quote, nameCut) {
  var code = quote.currency || ""
  var name = String(quote.name || "")
  var said = !nameCut && name.slice(-code.length - 1) === " " + code
  return quote.exchange + (code === "" || said ? "" : " · " + currencyLabel(code))
}

function currencyLabel(code) {
  return code === "GBp" ? "PENCE" : code
}

// For `StonksBody.yahooDown`, which says the warning once for the list.
function quietFreshness(fresh) {
  return freshnessWarns(fresh) ? Object.assign({}, fresh, { state: "aged" }) : fresh
}

// A trading symbol is asked for at every refresh, so a quote under two
// minutes old is live.
var LIVE_QUOTE_MAX_AGE = 120

// Room for a run of the whole list and three tries of a bad answer before
// a refresh owed counts as overdue.
var OVERDUE_AFTER = 90

// So the clock wakes for the "!" only while something is owed.
function overdueAt(owed, now) {
  var at = 0
  for (var symbol in owed) {
    var due = owed[symbol] + OVERDUE_AFTER
    if (due > now && (!at || due < at)) at = due
  }
  return at
}

// A normal answer's time, so a surface opening on a quote nothing kept fresh
// says no "As of" before its price lands. `Service.asking` times it to the
// millisecond; in the clock's whole seconds it ends 1 to 2 s on.
var ASKED_GRACE = 2

// `owedSince` is `QuoteFeed.owed`'s, `inGrace` `Service.asking`'s. Only a
// quote Stonks let go old keeps its age unsaid while asked: a source that
// sends late, as London's 15 minutes, is answered every minute and says
// "As of" throughout. The time is the newest price's, as a Robinhood print
// stays on top while Yahoo fails.
function freshness(entry, quote, now, owedSince, inGrace, newest) {
  var head = quote ? Quote.headlineQuote(quote) : null
  var phase = quote ? Market.sessionPhase(quote, now) : "closed"
  var asOf = head ? head.t : null
  var shownAt = head && newest ? newest.t : asOf
  var overdue = owedSince > 0 && now - owedSince >= OVERDUE_AFTER
  var asking = (!!inGrace && !!entry && now - entry.answeredAt > LIVE_QUOTE_MAX_AGE) || Market.awaitingOpen(quote, now)
  var state = entry && entry.status === "failed" ? "failed"
    : overdue ? "overdue"
    : !quote || !head ? "unavailable"
    : entry && entry.status === "saved" ? "saved"
    : asOf !== null && Market.isTrading(phase) && now - asOf > LIVE_QUOTE_MAX_AGE ? (asking ? "asking" : "aged")
    : "fresh"
  // `now`: the words name the day when it isn't the clock's, as a print does (`Market.printDay`).
  return { state: state, asOf: shownAt, session: newest ? newest.phase : "", now: now,
    live: asOf !== null && state === "fresh" && Market.isTrading(phase), phase: phase }
}

function freshnessText(fresh, quote, calendars) {
  if (!fresh) return ""
  var head = quote ? Quote.headlineQuote(quote) : null
  if (!fresh.asOf) {
    if (head) return (fresh.state === "failed" ? "REFRESH FAILED · "
      : fresh.state === "overdue" ? "NOT UPDATING · " : "") + "TIME UNKNOWN"
    return fresh.state === "failed" ? "NO DATA FOR THIS SYMBOL" : fresh.state === "unavailable" || fresh.state === "overdue" ? "NO DATA" : ""
  }
  var chartTrade = head && head.source === "chart"
  var lead = fresh.session ? Market.phaseLabel(fresh.session).toUpperCase() + " " : chartTrade ? "LAST TRADE · " : "AS OF "
  var asOf = lead + Market.printDay(quote, fresh.asOf, fresh.now, calendars).toUpperCase()
    + Market.printClock(quote, fresh.asOf, calendars)
  if (fresh.state === "failed") return "REFRESH FAILED · " + asOf
  if (fresh.state === "overdue") return "NOT UPDATING · " + asOf
  if (chartTrade || fresh.state === "aged" || fresh.state === "saved") return asOf
  return ""
}

function freshnessWarns(fresh) {
  return !!fresh && (fresh.state === "failed" || fresh.state === "overdue")
}

// From the quote host's gate (`Gate.qml`); null while the host answers. A
// pause for no answer lasts 72 s at most, so it says minutes, rounded up; a
// refusal's can last half an hour, so it says the time. `why` and `when` are
// the pill's hover, a sentence each. `forms` is the header, each shorter than
// the last: the window starts at the first, the panel at the second, and the
// last fits at text size 20.
function hostPause(pause, pausedUntil, now) {
  var left = pausedUntil - now
  if (pause === "none") {
    var minutes = Format.duration(Math.max(1, left))
    var inWords = left > 60 ? Math.ceil(left / 60) + " minutes" : "1 minute"
    return { why: "Can't connect. Check your internet.", when: "Retrying in " + inWords + ".",
      forms: ["Can't connect · Check your internet · Retrying in " + inWords, "Can't connect · Retrying in " + minutes, "Can't connect · " + minutes] }
  }
  if (pause === "refused") {
    var at = left > 0 ? Format.hhmm(pausedUntil, Format.readerOffset(pausedUntil)) : ""
    var retrying = at ? "Retrying at " + at : "Retrying now"
    return { why: "The price server is busy.", when: retrying + ".",
      forms: ["The price server is busy · " + retrying, "Server busy · " + retrying, at ? "Server busy · " + at : "Server busy · Retrying"] }
  }
  return null
}

// An exchange with no extended session echoes its close as a pre- or
// post-market print, so one that reads as the close is left out; an
// overnight print is a trade, and stays. Since the open the move still
// counts from the close: one from the open would count the regular session
// again under an AFTER HOURS label.
function extendedStack(quote, latest, now, day, changeMode) {
  var ext = Quote.extendedPrint(quote, latest)
  var close = Quote.regularClose(quote)
  var overnight = !!ext && ext.phase === "overnight"
  var digits = quote.priceDigits
  if (!ext || !Format.isFiniteNumber(close) || (!overnight && Format.money(ext.p, digits) === Format.money(close, digits))) return null
  var unit = changeMode === "abs" ? "abs" : "pct"
  var chg = Quote.change({ prevClose: close, points: [] }, ext.p, unit)
  return {
    price: Format.money(ext.p, digits),
    changeText: Format.changeText(chg, unit, digits),
    tone: Format.changeTone(chg, unit, digits),
    label: overnight ? "OVERNIGHT" : ext.phase === "post" ? "AFTER HOURS" : "PRE-MARKET",
    time: overnight ? Market.printClock(day || quote, ext.t) : "",
    stale: overnight && now - ext.t > Overnight.OVERNIGHT_STALE
  }
}

// A bar is five minutes of trades, so the words speak of the chart. One bar
// is the only one once its day is over (`axis.closes` where a night follows);
// before that it may be the first of many. They count every trade of the
// day (`day.trades`), as its low and high do, though the chart's start may
// have slid past some, and name the day of one that isn't today's. An empty
// day says nothing before its bell, as an index has no print before it, nor
// beside a quote that is a trade of its session. Yahoo stamps its live
// moment at the price's own second, apart from the bars at their five-minute
// starts.
function dayNote(day, now, calendars) {
  if (!day) return ""
  var pts = day.trades || day.points
  var over = now >= (day.axis && day.axis.closes ? day.axis.closes : Quote.dayEnd(day))
  if (pts.length === 1) return pts[0].t % (5 * 60) === 0 && over
    ? "Traded only at " + Market.printDay(day, pts[0].t, now, calendars) + Market.printClock(day, pts[0].t, calendars) : ""
  if (pts.length > 1) return ""
  var regular = day.session.regular
  if (!regular) return "No trades today"
  var head = Quote.headlineQuote(day)
  var tradedToday = !!head && head.t !== null && head.t >= regular.start
  if (now < regular.start || tradedToday) return ""
  return exchangeDay(day, regular.start) === exchangeDay(day, now) ? "No trades today"
    : "No trades on " + Format.WEEKDAYS[Format.localClock(regular.start, day.gmtoffset).weekday]
}

function exchangeDay(quote, t) {
  return quote && Format.isFiniteNumber(t) ? Math.floor((t + (quote.gmtoffset || 0)) / 86400) : null
}

// Titled against the later of today and the day drawn, so Monday's figures
// under Tuesday's chart, from its first night trade, say MON. Its low and
// high are Yahoo's for the session, widened by the day's trades around it
// from its night's open, drawn or slid off the chart's left (`figuresTrades`).
// An end at the 52-week mark takes that direction's tone, as
// `Fundamentals.yearLine`'s. The open keeps its slot before the first bar,
// so the line keeps its shape.
function dayLine(quote, today, day) {
  if (!quote) return null
  var q = quote
  var drawn = day && day.session && day.session.regular ? exchangeDay(q, day.session.regular.start) : null
  var head = Quote.headlineQuote(q)
  var low = q.dayLow
  var high = q.dayHigh
  var trades = figuresTrades(q, day)
  for (var i = 0; i < trades.length; i++) {
    if (low === null || trades[i].p < low) low = trades[i].p
    if (high === null || trades[i].p > high) high = trades[i].p
  }
  var range = Format.infoRange(low, high, head ? head.price : null, q.priceDigits)
  if (range.high !== null && Format.isFiniteNumber(q.fiftyTwoWeekHigh) && range.high >= q.fiftyTwoWeekHigh) range.highTone = "up"
  if (range.low !== null && Format.isFiniteNumber(q.fiftyTwoWeekLow) && range.low <= q.fiftyTwoWeekLow) range.lowTone = "down"
  return {
    title: dayTitle(q, drawn !== null && drawn > today ? drawn : today),
    range: range,
    facts: [
      { label: "OPEN", value: Format.isFiniteNumber(q.dayOpen) ? Format.money(q.dayOpen, q.priceDigits) : "", widest: range.widest },
      { label: "VOL", value: Format.isFiniteNumber(q.volume) ? Format.compactNumber(q.volume) : "", widest: Format.widest("999.9M") }
    ]
  }
}

// The trades the chart draws outside the session, for the day the quote's
// figures are of: its night, pre-market and after hours, but not tonight's,
// joined after it, nor the coming day's. None when the chart is another
// day's. Inside the session Yahoo's figures are the trades', and a bar there
// can be Yahoo echoing its quote, as Tokyo's at the bell.
function figuresTrades(quote, day) {
  if (!day || !day.session || !day.session.regular || exchangeDay(quote, day.session.regular.start) !== exchangeDay(quote, quote.figuresDay)) return []
  var until = day.tonight || Quote.tailStart(day) || Infinity
  return (day.trades || day.points).filter(function(p) { return p.t < until && Quote.pointSession(day, p) !== "reg" })
}

// Three letters at most, as a range's token is.
function dayTitle(quote, today) {
  if (quote.rolling) return "24H"
  return pastDayName(quote, quote.figuresDay, today) || "1D"
}

function pastDayName(quote, t, today) {
  var day = exchangeDay(quote, t)
  return day !== null && today - day > 0 ? dayName(quote, t, today) : ""
}

// No calendar closes longer than five days (Tokyo's Golden Week), so a
// weekday names one of the six days before today.
function dayName(quote, t, today) {
  var d = new Date((t + (quote.gmtoffset || 0)) * 1000)
  return today - exchangeDay(quote, t) < 7 ? Format.WEEKDAYS[d.getUTCDay()].toUpperCase() : Format.MONTHS[d.getUTCMonth()]
}

function dayTitles() {
  return ["1D", "24H"].concat(Format.WEEKDAYS.map(function(w) { return w.toUpperCase() }), Format.MONTHS)
}

// Only US stocks and ETFs, which trade at night, share one day here;
// listings abroad and coins name their own on their rows. A row with no
// time names no day: its freshness says so.
function rowsDay(symbols, quotes, newest, now, calendars) {
  var shared = null
  var night = false
  for (var i = 0; i < symbols.length; i++) {
    var q = quotes[symbols[i]]
    if (!q || !Overnight.hasOvernight(q, calendars)) continue
    var head = Quote.headlineQuote(q)
    var t = newest[symbols[i]] ? newest[symbols[i]].dayStart : head ? head.t : null
    if (t === null) continue
    var day = { quote: q, t: t, day: exchangeDay(q, t) }
    if (shared && shared.day !== day.day) return "TODAY"
    shared = day
    night = night || nightJoined(newest[symbols[i]])
  }
  var today = shared ? exchangeDay(shared.quote, now) : null
  return !shared || shared.day >= today ? "TODAY" : dayName(shared.quote, shared.t, today) + (night ? " + NIGHT" : "")
}

// The rows' own price and tone rules, so the breadth never disagrees with
// them.
function listBreadth(symbols, quotes, scrubT, mode, newest) {
  var out = { up: 0, flat: 0, down: 0, none: 0 }
  for (var i = 0; i < symbols.length; i++) {
    var quote = quotes[symbols[i]]
    var read = quote ? reading(quote, scrubT, newest ? newest[symbols[i]] : null) : null
    var chg = read ? Quote.change(read.base, read.price, mode) : null
    if (!chg || chg.pct === null) out.none++
    else out[Format.changeTone(chg, mode, quote.priceDigits)]++
  }
  return out
}

function reading(quote, scrubT, newest) {
  if (!scrubT) return Quote.restingRead(quote, newest)
  var read = Quote.readingAt(quote, scrubT)
  return { price: read.price, t: read.t, base: scrubbedBase(quote, scrubT) }
}

// Every price on screen comes from here. It carries no drawing and reads no
// clock, so a row isn't derived again every second; `scrubT` comes snapped.
// `dayUp` counts from the close whatever the mode, so the chart's fill
// doesn't flip with it.
function rowModel(quote, scrubT, mode, newest) {
  var since = !scrubT && newest ? newest : null
  var read = reading(quote, scrubT, since)
  var chg = Quote.change(read.base, read.price, mode)
  var direction = Quote.change(read.base, read.price, "pct")
  return {
    symbol: quote.symbol,
    name: quote.name,
    price: read.price,
    priceText: Format.money(read.price, quote.priceDigits),
    asOf: read.t,
    pct: chg.pct,
    abs: chg.abs,
    tone: Format.changeTone(chg, mode, quote.priceDigits),
    dayUp: direction.pct === null ? null : direction.up,
    dayTone: Format.changeTone(direction, "pct", quote.priceDigits),
    changeText: Format.changeText(chg, mode, quote.priceDigits),
    changeLine: Format.changeText(chg, mode, quote.priceDigits) + (mode === "open" && chg.pct !== null ? " open" : ""),
    periodLabel: since && mode !== "open" ? "" : quote.rolling && mode !== "open" ? "24H" : Format.changeCaption(mode),
    newest: since
  }
}

// A moment of the coming day that a two-day answer holds, once that day has
// a print, counts from the quote's own close with no open yet, as the 1D
// chart draws it (`Quote.tailDay`), so a row scrubbed into the pre-market
// reads what the hero does.
function scrubbedBase(quote, t) {
  var tail = Quote.tailStart(quote)
  if (tail !== null && t >= tail && Quote.lastPrintTime(quote) >= tail) return { prevClose: Quote.regularClose(quote), dayOpen: null }
  return { prevClose: Quote.dayBase(quote), dayOpen: quote.dayOpen }
}

// A coin never closes: its day starts at its price 24 hours ago.
function dayBaselineText(day, today, scrubT) {
  var base = Format.money(Quote.dayBase(day), day.priceDigits)
  if (day.rolling) return "24H AGO " + base
  var reg = day.session.regular
  var closed = !!reg && (pastDayName(day, reg.start, today) !== "" || (scrubT > 0 && scrubT >= reg.end))
  return (closed ? "CLOSE BEFORE " + sessionName(day, reg.start, today) : "PREV CLOSE") + " " + base
}

function closeLabel(quote, today) {
  var head = Quote.headlineQuote(quote)
  var day = head && head.t !== null ? pastDayName(quote, head.t, today) : ""
  return (day ? day + " " : "") + "CLOSE"
}

// After the close on its own day (`newest.closed`), the move since that
// close is said too, unless it rounds to nothing. From the next day on, the
// move on top is that one, so it isn't said twice.
function closeLine(quote, today, changeMode, newest) {
  var unit = changeMode === "abs" ? "abs" : "pct"
  var row = rowModel(quote, 0, unit)
  var since = newest.closed ? Quote.change({ prevClose: Quote.regularClose(quote), points: [] }, newest.p, unit) : null
  var sinceTone = since ? Format.changeTone(since, unit, quote.priceDigits) : "flat"
  return { label: closeLabel(quote, today), time: "", price: row.priceText, changeText: row.changeText, tone: row.tone, stale: false,
    since: since && sinceTone !== "flat" ? Format.changeText(since, unit, quote.priceDigits) : "", sinceTone: sinceTone }
}

// Each form is shorter than the last, for a caption with no room for it. A
// period comes first, so a range's move never reads as the night's. A night
// joined to the day that closed names that close, as its move covers the
// day too.
function newestCaptions(quote, newest, now, calendars, period) {
  var day = Market.printDay(quote, newest.t, now, calendars).toUpperCase()
  var clock = Market.printClock(quote, newest.t, calendars)
  if (!period && nightJoined(newest)) {
    var named = "SINCE " + closeBefore(quote, newest, calendars).toUpperCase() + " CLOSE"
    return [named + " · " + day + clock, named + " · " + clock, named]
  }
  var label = (period ? period + " · " : "") + (newest.phase === "overnight" ? "OVERNIGHT" : newest.phase === "post" ? "AFTER HOURS" : "PRE-MARKET")
  var forms = [label + " " + day + clock, label + " " + clock]
  return period ? forms.concat([period]) : forms
}

function nightJoined(newest) {
  return !!newest && !!newest.joined
}

function closeBefore(quote, newest, calendars) {
  var cal = Market.calendarFor(calendars, quote)
  var date = Market.dateStringOf(Market.localDate(newest.dayStart, cal))
  for (var i = 0; i < 10; i++) {
    date = Market.previousDateString(date)
    if (Market.dayKind(cal, date).kind === "open") break
  }
  return Format.WEEKDAYS[new Date(date + "T12:00:00Z").getUTCDay()]
}

function newestNote(quote, newest, now, calendars) {
  var time = newestTime(quote, newest, now, calendars)
  if (nightJoined(newest)) return "Since " + closeBefore(quote, newest, calendars) + " close · " + time
  return (newest.phase === "overnight" ? "Overnight" : newest.phase === "post" ? "After hours" : "Pre-market") + " " + time
}

// A row says it after the name.
function newestTime(quote, newest, now, calendars) {
  return Market.printDay(quote, newest.t, now, calendars) + Market.printClock(quote, newest.t, calendars)
}

function newestStale(newest, now) {
  return !!newest && newest.phase === "overnight" && now - newest.t > Overnight.OVERNIGHT_STALE
}

// A week old or more says its date: "BEFORE SEP" would read as before
// September.
function sessionName(day, start, today) {
  if (today - exchangeDay(day, start) < 7) return dayName(day, start, today)
  var d = new Date((start + (day.gmtoffset || 0)) * 1000)
  return d.getUTCDate() + " " + Format.MONTHS[d.getUTCMonth()]
}

// The header and the pill read this one rule, so they never disagree.
function animalKind(row) {
  return !row || row.dayTone === "flat" ? "" : row.dayTone === "up" ? "bull" : "bear"
}
