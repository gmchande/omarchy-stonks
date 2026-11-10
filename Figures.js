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

// `timed`: the caller says the newest price's time itself, as a row does
// after its name, so a note that would only repeat it is left out.
function freshnessText(fresh, quote, calendars, timed) {
  if (!fresh) return ""
  var head = quote ? Quote.headlineQuote(quote) : null
  if (!fresh.asOf) {
    if (head) return (fresh.state === "failed" ? "REFRESH FAILED · "
      : fresh.state === "overdue" ? "NOT UPDATING · " : "") + "TIME UNKNOWN"
    return fresh.state === "failed" ? "NO DATA FOR THIS SYMBOL" : fresh.state === "unavailable" || fresh.state === "overdue" ? "NO DATA" : ""
  }
  // Where Yahoo sent no price, what's on top is a trade, not the close, so
  // it says when.
  var chartTrade = head && head.source === "chart"
  var lead = fresh.session ? Market.phaseLabel(fresh.session).toUpperCase() + " " : chartTrade ? "LAST TRADE · " : "AS OF "
  var asOf = lead + Market.printDay(quote, fresh.asOf, fresh.now, calendars).toUpperCase()
    + Market.printClock(quote, fresh.asOf, calendars)
  if (fresh.state === "failed") return "REFRESH FAILED · " + asOf
  if (fresh.state === "overdue") return "NOT UPDATING · " + asOf
  if ((chartTrade && !(fresh.session && timed)) || fresh.state === "aged" || fresh.state === "saved") return asOf
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
  var chg = Quote.change({ prevClose: close }, ext.p, unit)
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
      // Yahoo sends an index or a currency pair no volume, as a 0.
      { label: "VOL", value: Format.isFiniteNumber(q.volume) && q.volume > 0 ? Format.compactNumber(q.volume) : "", widest: Format.widest("999.9M") }
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

// Three letters at most, as a range's token is, so a day a week old or more,
// whose name is its date, is 1D: the line under the price names it.
function dayTitle(quote, today) {
  if (quote.rolling) return "24H"
  var day = exchangeDay(quote, quote.figuresDay)
  return day !== null && today - day > 0 && today - day < 7 ? dayName(quote, quote.figuresDay, today) : "1D"
}

function pastDayName(quote, t, today) {
  var day = exchangeDay(quote, t)
  return day !== null && today - day > 0 ? dayName(quote, t, today) : ""
}

// No calendar closes longer than five days (Tokyo's Golden Week), so a
// weekday names one of the six days before today. A week old or more says
// its date, 4 SEP: a weekday would read as this week's, a month alone as
// the month.
function dayName(quote, t, today) {
  var d = new Date((t + (quote.gmtoffset || 0)) * 1000)
  return today - exchangeDay(quote, t) < 7 ? Format.WEEKDAYS[d.getUTCDay()].toUpperCase() : d.getUTCDate() + " " + Format.MONTHS[d.getUTCMonth()]
}

function dayTitles() {
  return ["1D", "24H"].concat(Format.WEEKDAYS.map(function(w) { return w.toUpperCase() }))
}

// Only US stocks and ETFs, which trade at night, share one day here;
// listings abroad and coins name their own on their rows. A row with no
// time names no day: its freshness says so. A row whose move is the
// night's says so itself (`rowTime`), so the header keeps the day.
function rowsDay(symbols, quotes, newest, now, calendars) {
  var shared = null
  var mixed = false
  for (var i = 0; i < symbols.length; i++) {
    var q = quotes[symbols[i]]
    if (!q || !Overnight.hasOvernight(q, calendars)) continue
    var head = Quote.headlineQuote(q)
    var t = newest[symbols[i]] ? newest[symbols[i]].dayStart : head ? head.t : null
    if (t === null) continue
    var day = { quote: q, t: t, day: exchangeDay(q, t) }
    mixed = mixed || (!!shared && shared.day !== day.day)
    shared = day
  }
  var today = shared ? exchangeDay(shared.quote, now) : null
  return !shared || mixed || shared.day >= today ? "TODAY" : dayName(shared.quote, shared.t, today)
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
  return { price: read.price, t: read.t, base: scrubbedBase(quote, scrubT, newest) }
}

// Every price on screen comes from here. It carries no drawing and reads no
// clock, so a row isn't derived again every second; `scrubT` comes snapped.
// `dayUp` counts from the close whatever the mode, so the chart's fill
// doesn't flip with it.
function rowModel(quote, scrubT, mode, newest) {
  var since = !scrubT && newest ? newest : null
  var read = reading(quote, scrubT, newest || null)
  var chg = Quote.change(read.base, read.price, mode)
  var direction = Quote.change(read.base, read.price, "pct")
  return {
    symbol: quote.symbol,
    name: quote.name,
    price: read.price,
    priceText: Format.money(read.price, quote.priceDigits),
    asOf: read.t,
    // The close the day's change counts from, the dashed line's for a scrub.
    close: read.base.prevClose,
    pct: chg.pct,
    abs: chg.abs,
    tone: Format.changeTone(chg, mode, quote.priceDigits),
    dayUp: direction.pct === null ? null : direction.up,
    dayTone: Format.changeTone(direction, "pct", quote.priceDigits),
    changeText: Format.changeText(chg, mode, quote.priceDigits),
    // The unit `changeText` says the move in.
    unit: mode === "abs" ? "abs" : "pct",
    changeLine: Format.changeText(chg, mode, quote.priceDigits) + (mode === "open" && chg.pct !== null ? " open" : ""),
    periodLabel: since && mode !== "open" ? "" : quote.rolling && mode !== "open" ? "24H" : Format.changeCaption(mode),
    newest: since
  }
}

// A moment of the coming day that a two-day answer holds, once that day has
// a print, counts from the quote's own close with no open yet, as the 1D
// chart draws it (`Quote.tailDay`), so a row scrubbed into the pre-market
// reads what the hero does. Once tonight has traded, a moment past the bell
// counts from the close just gone, where the dashed line steps: the day
// drawn says so (`Overnight.nightBell`), and a row's quote by its newest
// price (`newest.joined`).
function scrubbedBase(quote, t, newest) {
  var reg = quote.session.regular
  var bell = Overnight.nightBell(quote)
  if (bell === null && newest && newest.joined && reg) bell = reg.end
  if (bell !== null && t >= bell) return { prevClose: Quote.regularClose(quote), dayOpen: null }
  var tail = Quote.tailStart(quote)
  if (tail !== null && t >= tail && Quote.lastPrintTime(quote) >= tail) return { prevClose: Quote.regularClose(quote), dayOpen: null }
  return { prevClose: Quote.dayBase(quote), dayOpen: quote.dayOpen }
}

// The chart's dashed line in words: the close before the day on the chart,
// named by its day (`closeName`). A coin never closes: its day starts at its
// price 24 hours ago.
function dayBaselineText(day, today, calendars) {
  var base = Format.money(Quote.dayBase(day), day.priceDigits)
  if (day.rolling) return "24H AGO " + base
  var reg = day.session.regular
  return (reg ? closeName(day, reg.start, today, calendars) : "PREV CLOSE") + " " + base
}

// The dashed line under a scrubbed moment `t`, in words: past the bell of a
// day tonight has traded on, the close just gone, where the line steps
// (`Overnight.nightBell`).
function scrubBaselineText(day, t, today, calendars) {
  var bell = Overnight.nightBell(day)
  if (bell === null || t < bell) return dayBaselineText(day, today, calendars)
  var named = closeLabel(day, today, calendars)
  return named.label + (named.time ? " " + named.time : "") + " " + Format.money(Quote.regularClose(day), day.priceDigits)
}

// The headline's close, named by its day once that day is past. Where Yahoo
// sent no price, the headline is the chart's last bar, which isn't the
// close: LAST TRADE and its time.
function closeLabel(quote, today, calendars) {
  var head = Quote.headlineQuote(quote)
  var day = head && head.t !== null ? pastDayName(quote, head.t, today) : ""
  if (head && head.source === "chart") return { label: "LAST TRADE", time: (day ? day + " " : "") + Market.printClock(quote, head.t, calendars) }
  return { label: (day ? day + " " : "") + "CLOSE", time: "" }
}

// The close before the price on top, which the price on top no longer is,
// and its day's move: CLOSE 171.99 −5.68%, or MON CLOSE once that day is
// past. Where the price on top is that close, counted from the same close
// (`shown`), it would only repeat it: no price, no move.
function closeLine(quote, today, changeMode, shown, calendars) {
  var row = rowModel(quote, 0, changeMode === "abs" ? "abs" : "pct")
  var same = row.priceText === shown.priceText && row.close === shown.close
  var named = closeLabel(quote, today, calendars)
  return { label: named.label, time: named.time, price: same ? "" : row.priceText, changeText: same ? "" : row.changeText,
    tone: same ? "flat" : row.tone, stale: false }
}

// The part of a day's move since its close, while the price on top is a
// trade after its bell: AFTER HOURS +1.35%. None where it rounds to nothing.
function sinceClose(quote, newest, changeMode) {
  var unit = changeMode === "abs" ? "abs" : "pct"
  var since = Quote.change({ prevClose: Quote.regularClose(quote) }, newest.p, unit)
  var tone = Format.changeTone(since, unit, quote.priceDigits)
  return tone === "flat" ? null
    : { label: Market.phaseLabel(newest.phase).toUpperCase(), changeText: Format.changeText(since, unit, quote.priceDigits), tone: tone }
}

// TODAY, or the day's name once it is past.
function moveDay(quote, t, today) {
  return exchangeDay(quote, t) >= today ? "TODAY" : dayName(quote, t, today)
}

// What the move on top covers. A day's whole move, after hours in it, is
// its day's; the night's and the pre-market's, counted from the close just
// gone, are their session's. Where Yahoo's quote is older than the day the
// night joined (`joined` without `closed`), the move covers that day too,
// and goes unnamed.
function moveName(quote, newest, from, today) {
  if (newest) {
    if (newest.joined) return newest.closed ? "OVERNIGHT" : ""
    return newest.closed ? moveDay(quote, quote.session.regular.start, today) : Market.phaseLabel(newest.phase).toUpperCase()
  }
  return !from ? "" : quote.rolling ? "24H" : moveDay(quote, from.dayT, today)
}

// The trading day before the one that starts at `dayStart`, by the listing's
// calendar, as a date string: none without a calendar, or past its reach.
function closeBeforeDate(cal, dayStart) {
  if (!cal) return null
  var date = Market.dateStringOf(Market.localDate(dayStart, cal))
  for (var i = 0; i < 10; i++) {
    date = Market.previousDateString(date)
    var kind = Market.dayKind(cal, date).kind
    if (kind === "open") return date
    if (kind === "unknown") return null
  }
  return null
}

// A close named by its day, the trading day before the one `t` falls in:
// FRI CLOSE within the week, 4 SEP CLOSE beyond, and PREV CLOSE where no
// calendar can say which day that was. The panel's lines, the scrub's
// legend and the screenshot all name a close this one way.
function closeName(quote, t, today, calendars) {
  var cal = Market.calendarFor(calendars, quote)
  var date = closeBeforeDate(cal, t)
  return date === null ? "PREV CLOSE" : dayName(quote, Market.epochAt(cal, date, "12:00"), today) + " CLOSE"
}

// The close the move on top counts from (`view.close`), named by its day,
// and the day the price on top is of (`view.asOf`): the session's, or the
// last one's while Yahoo's quote is still its close, before the new day's
// first trade. None where that close isn't known, as at Tokyo's open before
// its first bar.
function closeCountedFrom(quote, view, today, calendars) {
  var reg = quote.session.regular
  if (!reg || !Format.isFiniteNumber(view.close)) return null
  var dayT = Format.isFiniteNumber(view.asOf) && view.asOf < reg.start ? view.asOf : reg.start
  return { label: quote.rolling ? "24H AGO" : closeName(quote, dayT, today, calendars),
    price: Format.money(view.close, quote.priceDigits), dayT: dayT }
}

// The two lines under the price and the move, one rule at every hour.
// Under the price, the close before the price on top, named by its day,
// with its day's move until the next session opens (`closeLine`), and while
// the move on top is the whole day's with trades after the bell in it, the
// part since the close (`since`), which gives way first. Where the price on
// top is a trade of the session or the close itself, the close it counts
// from (`closeCountedFrom`); where it is the close and Yahoo holds a pre-
// or after-hours print beside it, that print (`extendedStack`). Under the
// move, its name and the same move in the other unit (`view.unit`): TODAY
// +4.57, OVERNIGHT −1.83, PRE-MARKET −5.74, FRI −0.43, 24H −795.72,
// 1M −90.97, SINCE OPEN +9.34. A scrubbed moment keeps its amount and a
// range's name, and the dashed line's legend takes the first line's place.
// Where the move isn't known, the first is the close it would count from,
// if known, and the second a mode's or a range's name alone.
function heroLines(quote, view, latest, now, day, calendars, changeMode, scrubbing) {
  var none = { label: "", changeText: "", tone: "flat" }
  if (!quote || !view) return { close: null, caption: none }
  var today = exchangeDay(quote, now)
  var newest = view.newest || null
  var period = view.periodLabel || ""
  var from = closeCountedFrom(quote, view, today, calendars)
  var close = scrubbing ? null : newest ? closeLine(quote, today, changeMode, view, calendars)
    : extendedStack(quote, latest, now, day, changeMode) || closeOnly(from)
  var whole = !!close && !!newest && newest.closed && !newest.joined
  if (whole && close.price === "") close = closeOnly(from) || close
  else if (whole && period === "") close.since = sinceClose(quote, newest, changeMode)
  var other = view.unit === "abs" ? "pct" : "abs"
  if (view.pct === null) return { close: close, caption: { label: period === "24H" ? "" : period, changeText: "", tone: "flat" } }
  var label = scrubbing ? (period === "24H" ? "" : period) : period || moveName(quote, newest, from, today)
  return { close: close, caption: { label: label, changeText: Format.changeText(view, other, quote.priceDigits), tone: Format.changeTone(view, other, quote.priceDigits) } }
}

function closeOnly(from) {
  return from ? { label: from.label, time: "", price: from.price, changeText: "", tone: "flat", stale: false } : null
}

// The pill's hover: the newest price's session and time.
function newestNote(quote, newest, now, calendars) {
  return Market.phaseLabel(newest.phase) + " " + newestTime(quote, newest, now, calendars)
}

// A row says it after the name.
function newestTime(quote, newest, now, calendars) {
  return Market.printDay(quote, newest.t, now, calendars) + Market.printClock(quote, newest.t, calendars)
}

// A row's time after its name; where its move is the night's, counted from
// the close just gone, it says so: Overnight 01:25.
function rowTime(quote, newest, now, calendars) {
  return (newest.joined ? Market.phaseLabel("overnight") + " " : "") + newestTime(quote, newest, now, calendars)
}

function newestStale(newest, now) {
  return !!newest && newest.phase === "overnight" && now - newest.t > Overnight.OVERNIGHT_STALE
}

// The header and the pill read this one rule, so they never disagree.
function animalKind(row) {
  return !row || row.dayTone === "flat" ? "" : row.dayTone === "up" ? "bull" : "bear"
}
