.pragma library
.import "Calendar.js" as Calendar
.import "Format.js" as Format
.import "Freshness.js" as Freshness
.import "Market.js" as Market
.import "Overnight.js" as Overnight
.import "Day.js" as Day
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

// An exchange with no extended session echoes its close as a pre- or
// post-market price, so one that reads as the close is left out; an
// overnight one is a trade, and stays. Since the open the move still
// counts from the close: one from the open would count the regular session
// again under an AFTER HOURS label.
function extendedStack(quote, latest, now, day, changeMode, calendars) {
  var ext = Quote.extendedTrade(quote, latest)
  var close = Quote.regularClose(quote)
  var overnight = !!ext && ext.phase === "overnight"
  var digits = quote.priceDigits
  if (!ext || !Format.isFiniteNumber(close) || (!overnight && Format.money(ext.p, digits) === Format.money(close, digits))) return null
  var unit = changeMode === "abs" ? "abs" : "pct"
  var chg = Quote.change({ prevClose: close }, ext.p, unit, digits)
  return {
    price: Format.money(ext.p, digits),
    changeText: Format.changeText(chg, unit, digits),
    tone: Format.changeTone(chg, unit, digits),
    label: overnight ? "OVERNIGHT" : ext.phase === "post" ? "AFTER HOURS" : "PRE-MARKET",
    time: overnight ? Market.tradeTime(day || quote, ext.t, calendars) : "",
    stale: overnight && now - ext.t > Overnight.OVERNIGHT_STALE
  }
}

// A bar is five minutes of trades, so the words speak of the chart. One bar
// is the only one once its day is over (`axis.closes` where a night follows);
// before that it may be the first of many. They count every trade of the
// day (`day.trades`), as its low and high do, though the chart starts at
// the open, and name the day of one that isn't today's. An empty
// day says nothing before its bell, as an index has no trade before it, nor
// beside a quote that is a trade of its session. Yahoo stamps its live
// moment at the price's own second, apart from the bars at their five-minute
// starts.
function dayNote(day, now, calendars) {
  if (!day) return ""
  var pts = day.trades || day.points
  var over = now >= (day.axis && day.axis.closes ? day.axis.closes : Quote.dayEnd(day))
  if (pts.length === 1) return pts[0].t % (5 * 60) === 0 && over
    ? "Traded only at " + Market.tradeDay(day, pts[0].t, now, calendars) + Market.tradeTime(day, pts[0].t, calendars) : ""
  if (pts.length > 1) return ""
  var regular = day.session.regular
  if (!regular) return "No trades today"
  if (day.untraded) return "Not traded yet"
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
// under Tuesday's chart, while Yahoo's are still Monday's, say MON. Its low
// and high are Yahoo's for the session, widened by the day's trades around
// it from its night's open, drawn or before the chart's start (`figuresTrades`).
// An end at the 52-week mark takes that direction's tone, as
// `Fundamentals.yearLine`'s. The open keeps its slot before the first bar,
// so the line keeps its shape.
function dayLine(quote, today, day, newest) {
  if (!quote) return null
  // While the chart holds the day just closed, its figures are that day's.
  var q = day && day.held ? day : quote
  var drawn = day && day.session && day.session.regular ? exchangeDay(q, day.session.regular.start) : null
  var figures = exchangeDay(q, q.figuresDay)
  var head = Quote.headlineQuote(q)
  var low = q.dayLow
  var high = q.dayHigh
  var trades = figuresTrades(q, day)
  for (var i = 0; i < trades.length; i++) {
    if (low === null || trades[i].p < low) low = trades[i].p
    if (high === null || trades[i].p > high) high = trades[i].p
  }
  var sameDayNewest = !!newest && Format.isFiniteNumber(newest.p)
    && (!newest.stepped || (drawn !== null && figures !== null && drawn < figures))
  if (sameDayNewest) {
    if (low === null || newest.p < low) low = newest.p
    if (high === null || newest.p > high) high = newest.p
  }
  var range = Format.infoRange(low, high, sameDayNewest ? newest.p : (head ? head.price : null), q.priceDigits)
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
// joined after it, nor the coming day's; or where the figures are of the
// day those joined trades belong to, as while the chart holds the day
// before (`CarriedClose.heldDay`), those. None when the chart is another
// day's. Inside the session Yahoo's figures are the trades', and a bar
// there can be Yahoo echoing its quote, as Tokyo's at the bell.
function figuresTrades(quote, day) {
  if (!day || !day.session || !day.session.regular) return []
  var drawn = exchangeDay(quote, day.session.regular.start)
  var figures = exchangeDay(quote, quote.figuresDay)
  var until = day.tonight || Quote.tailStart(day) || Infinity
  var outside = function(p) { return Quote.pointSession(day, p) !== "reg" }
  var pts = day.trades || day.points
  if (drawn === figures) return pts.filter(function(p) { return p.t < until && outside(p) })
  return day.tonight && drawn < figures ? pts.filter(function(p) { return p.t >= day.tonight && outside(p) }) : []
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

// The day the rows measure, "TODAY", "FRI", "8 SEP", "24H" for coins alone,
// or "OVERNIGHT" while any row on show counts tonight's move, worked out in
// two steps, so the clock reads only the second: the day the rows share,
// which changes only with their prices, and its name, which changes only at
// the exchange's midnight. Any list holding US stocks keeps the US rows' rule
// (their shared day, or "TODAY" where they disagree or none has a time). A
// list with no US stock takes the day its own rows share, "24H" for rolling
// coins alone, and blank where they disagree or none names one.
function rowsSharedDay(symbols, quotes, newest, calendars) {
  var usShared = null
  var usMixed = false
  var hasUs = false
  var otherShared = null
  var otherMixed = false
  var rolling = false
  for (var i = 0; i < symbols.length; i++) {
    var q = quotes[symbols[i]]
    if (!q) continue
    var nt = newest ? newest[symbols[i]] : null
    if (nt && nt.joined && nt.closed) return { overnight: true }
    if (Overnight.hasOvernight(q, calendars)) {
      hasUs = true
      var usHead = Quote.headlineQuote(q)
      var usT = nt ? nt.dayStart : usHead ? usHead.t : null
      if (usT === null) continue
      var usDay = { quote: q, t: usT, day: exchangeDay(q, usT) }
      if (usShared && usShared.day !== usDay.day) usMixed = true
      else usShared = usDay
      continue
    }
    if (hasUs) continue
    if (q.rolling) {
      rolling = true
      if (otherShared) otherMixed = true
      continue
    }
    if (rolling) otherMixed = true
    var head = Quote.headlineQuote(q)
    var t = head ? head.t : null
    if (t === null) continue
    var day = exchangeDay(q, t)
    var offset = q.gmtoffset || 0
    if (!otherShared) otherShared = { quote: q, t: t, day: day, minOffset: offset, maxOffset: offset }
    else if (otherShared.day !== day) otherMixed = true
    else {
      if (offset < otherShared.minOffset) otherShared.minOffset = offset
      if (offset > otherShared.maxOffset) otherShared.maxOffset = offset
    }
  }
  if (hasUs) return usMixed || !usShared ? { today: true } : usShared
  if (otherMixed) return null
  if (otherShared) return otherShared
  return rolling ? { rolling: true } : null
}

function rowsDayName(shared, now) {
  if (!shared) return ""
  if (shared.overnight) return "OVERNIGHT"
  if (shared.today) return "TODAY"
  if (shared.rolling) return "24H"
  var off = shared.quote.gmtoffset || 0
  var minToday = Math.floor((now + (shared.minOffset !== undefined ? shared.minOffset : off)) / 86400)
  var maxToday = Math.floor((now + (shared.maxOffset !== undefined ? shared.maxOffset : off)) / 86400)
  if (shared.day >= maxToday) return "TODAY"
  if (shared.day < minToday) {
    var near = maxToday - shared.day < 7
    var far = minToday - shared.day >= 7
    return near || far ? dayName(shared.quote, shared.t, minToday) : ""
  }
  return ""
}

// What the header says, by what wins: trouble, then a chart loading, a
// refresh asked for, a range that failed, a scrub of a range, and the
// market's words. `forms` are its words, each shorter than the last;
// `trouble`, whether they are trouble; `offersRetry`, whether they offer to
// try the range again. `s`:
// - `hasService`, else `whenMissing` says so.
// - `scrubbed`: a scrub or replay shows a moment. `refreshing`: a refresh
//   the reader asked for is out. `rangeFailed`: the range on show failed,
//   and `chartRange` is it.
// - `pause`: Yahoo's (`Freshness.hostPause`), said where a stock warns
//   (`warnings`), and short in the panel (`compact`). `yahooDown`: every
//   stock warns. `quoted`: the stock on show has a quote, whose refresh
//   failed (`featuredFailed`); `symbol` is it.
// - `loading`: a chart is on its way, said as `loadingText` where one is on
//   show (`hasChart`), and nothing before any.
// - `scrubForms`: a range's scrub, null without. `marketForms`: the
//   market's.
// A refetch the service makes itself says nothing, out or failed.
function headerLine(s) {
  var said = function(forms) { return { forms: forms, trouble: false, offersRetry: false } }
  if (!s.hasService) return said([s.whenMissing])
  if (!s.scrubbed && !s.refreshing && !s.rangeFailed) {
    var trouble = s.pause && s.warnings > 0 ? (s.compact ? s.pause.forms.slice(1) : s.pause.forms)
      : s.yahooDown ? ["Can't get prices · Stonks keeps trying", "Can't get prices"]
      : s.quoted && s.featuredFailed ? ["Refresh failed for " + s.symbol + " · Retrying", "Refresh failed · Retrying", "Refresh failed"]
      : null
    if (trouble) return { forms: trouble, trouble: true, offersRetry: false }
  }
  if (s.loading) return said([s.hasChart ? s.loadingText : ""])
  if (s.refreshing && !s.scrubbed) return said(["Refreshing"])
  if (s.rangeFailed) return { forms: [s.chartRange.toUpperCase() + " unavailable"], trouble: false, offersRetry: true }
  if (s.scrubForms) return said(s.scrubForms)
  if (s.quoted) return said(s.marketForms)
  return said([s.whenMissing])
}

// The rows' own price and tone rules, so the breadth never disagrees with
// them (`listRow`). `lines` holds each row's line while the rows are
// scrubbed at `scrubT`.
function listBreadth(symbols, quotes, lines, scrubT, mode, newest) {
  var out = { up: 0, flat: 0, down: 0, none: 0 }
  for (var i = 0; i < symbols.length; i++) {
    var quote = quotes[symbols[i]]
    var line = lines ? scrubbedLine(lines[symbols[i]] || null, scrubT) : null
    var trade = newest ? newest[symbols[i]] || null : null
    var read = !quote ? null : line ? reading(line, scrubT, trade) : reading(quote, 0, trade)
    var chg = read ? Quote.change(read.base, read.price, mode, quote.priceDigits) : null
    if (!chg || chg.pct === null) out.none++
    else out[Format.changeTone(chg, mode, quote.priceDigits)]++
  }
  return out
}

// A row, matching what the panel shows on 1D: at rest its newest trade,
// overnight included; scrubbed at `scrubT`, its own line (`Chart.lineDay`),
// once it has a trade at or before `scrubT` (`scrubbedLine`).
function listRow(quote, mode, newest, line, scrubT) {
  var scrubbed = scrubbedLine(line, scrubT)
  return scrubbed ? rowModel(scrubbed, scrubT, mode, newest) : rowModel(quote, 0, mode, newest)
}

// A row's note after its name: while the list's header says OVERNIGHT
// (`overnightList`), rows trading tonight say only their name and a row still
// on its day names that day ("Today", "Mon", "8 Sep", or "24h" for a coin).
// Nothing at other hours.
function rowNote(quote, view, overnightList, now) {
  if (!overnightList || !quote || !view) return ""
  if (view.newest && view.newest.joined) return ""
  if (quote.untraded) return ""
  if (quote.rolling) return "24h"
  var t = view.newest ? view.newest.dayStart : view.asOf
  if (!Format.isFiniteNumber(t) || !Format.isFiniteNumber(now) || now <= 0) return ""
  var today = exchangeDay(quote, now)
  return today === null ? "" : Format.sentenceCase(moveDay(quote, t, today))
}

// The line a row reads a scrub at `t` from: its own, once it has a trade at
// or before `t`, the one its dot sits on (`Chart.tradeFraction`). Before
// its first trade, or with no line drawn yet, the row has no dot, and rests.
function scrubbedLine(line, t) {
  return t && line && line.points.length && line.points[0].t <= t ? line : null
}

function reading(quote, scrubT, newest) {
  if (!scrubT) return Quote.restingRead(quote, newest)
  var read = Quote.readingAt(quote, scrubT)
  return { price: read.price, t: read.t, base: scrubbedBase(quote, scrubT, newest) }
}

// Every price on screen comes from here. It carries no drawing and reads no
// clock, so a row isn't derived again every second; `scrubT` comes snapped.
// `dayUp` counts from the close whatever the mode, so the chart's fill
// doesn't flip with it. A listing yet to trade shows its IPO price, named
// as such (`heroLines`), with no move: `price` stays null, as no trade is.
function rowModel(quote, scrubT, mode, newest) {
  var since = !scrubT && newest ? newest : null
  var read = reading(quote, scrubT, newest || null)
  var chg = Quote.change(read.base, read.price, mode, quote.priceDigits)
  var direction = Quote.change(read.base, read.price, "pct")
  return {
    symbol: quote.symbol,
    name: quote.name,
    price: read.price,
    priceText: Format.money(quote.untraded ? quote.prevClose : read.price, quote.priceDigits),
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
// a trade, counts from the quote's own close with no open yet, as the 1D
// chart draws it (`Quote.tailDay`), so a row scrubbed into the pre-market
// reads what the hero does. Once a trade has joined the day that closed,
// tonight's or the pre-market's, a moment past the bell counts from the
// close just gone, the panel's dashed line: the day drawn says so
// (`Day.nightBell`), and a row's quote by its newest price
// (`newest.stepped`). A day abroad just opened, joined to the day before
// it, has its own open already (`CarriedClose.heldDay`). A moment of a US
// day's pre-market comes before its open, so it counts only from the close.
function scrubbedBase(quote, t, newest) {
  var reg = quote.session.regular
  var bell = Day.nightBell(quote)
  var nextOpenAt = Format.isFiniteNumber(quote.nextOpenAt) ? quote.nextOpenAt
    : quote.next && quote.next.regular ? quote.next.regular.start : null
  var nextOpen = Format.isFiniteNumber(quote.nextOpen) && (nextOpenAt === null || t >= nextOpenAt) ? quote.nextOpen : null
  if (bell === null && newest && newest.stepped && reg) bell = reg.end
  if (bell !== null && t >= bell) return { prevClose: Quote.regularClose(quote), dayOpen: nextOpen }
  var tail = Quote.tailStart(quote)
  if (tail !== null && t >= tail && Quote.lastTradeTime(quote) >= tail) return { prevClose: Quote.regularClose(quote), dayOpen: nextOpen }
  return { prevClose: Quote.dayBase(quote), dayOpen: reg && t < reg.start ? null : quote.dayOpen }
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

// What a scrubbed moment `t` counts from, in words: past the bell of a day
// tonight has traded on, the close just gone, the panel's dashed line
// (`Day.nightBell`).
function scrubBaselineText(day, t, today, calendars) {
  var bell = Day.nightBell(day)
  if (bell === null || t < bell) return dayBaselineText(day, today, calendars)
  var named = closeLabel(day, today, calendars)
  return named.label + (named.time ? " " + named.time : "") + " " + Format.money(Quote.regularClose(day), day.priceDigits)
}

// What a scrubbed moment's move counts from, said under the price by the
// panel and the screenshot alike: since the open, the day's open, which no
// line on the chart marks; else the dashed line under the pointer.
function scrubLegend(day, t, today, calendars, changeMode, newest) {
  var base = changeMode === "open" ? scrubbedBase(day, t, newest) : null
  return base && Format.isFiniteNumber(base.dayOpen) ? "OPEN " + Format.money(base.dayOpen, day.priceDigits)
    : "┄ " + scrubBaselineText(day, t, today, calendars)
}

// The headline's close, named by its day once that day is past. Where Yahoo
// sent no price, the headline is the chart's last bar, which isn't the
// close: LAST TRADE and its time.
function closeLabel(quote, today, calendars) {
  var head = Quote.headlineQuote(quote)
  var day = head && head.t !== null ? pastDayName(quote, head.t, today) : ""
  if (head && head.source === "chart") return { label: "LAST TRADE", time: (day ? day + " " : "") + Market.tradeTime(quote, head.t, calendars) }
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
  var since = Quote.change({ prevClose: Quote.regularClose(quote) }, newest.p, unit, quote.priceDigits)
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

// A close named by its day, the trading day before the one `t` falls in:
// FRI CLOSE within the week, 4 SEP CLOSE beyond, and PREV CLOSE where no
// calendar can say which day that was. On a listing's first day it is the
// offer price (`Quote.listingDay`). The panel's lines, the scrub's legend and
// the screenshot all name a close this one way.
function closeName(quote, t, today, calendars) {
  if (Quote.listingDay(quote)) return "IPO PRICE"
  var cal = Calendar.calendarFor(calendars, quote)
  var date = Calendar.closeBeforeDate(cal, t)
  return date === null ? "PREV CLOSE" : dayName(quote, Calendar.epochAt(cal, date, "12:00"), today) + " CLOSE"
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

// The two lines under the price and the move, one rule at every hour, and
// the move itself (`move`). Under the price, the close before the price on
// top, named by its day, with its day's move until the next session opens
// (`closeLine`), and while the move on top is the whole day's with trades
// after the bell in it, the part since the close (`since`), which gives way
// first. Where the price on top is a trade of the session or the close
// itself, the close it counts from (`closeCountedFrom`); where it is the
// close and Yahoo holds a pre- or after-hours trade beside it, that trade
// (`extendedStack`). Under the move, its name and the same move in the
// other unit (`view.unit`): TODAY +4.57 USD, OVERNIGHT −1.83 USD,
// PRE-MARKET −5.74 USD, FRI −0.43 USD, 24H −795.72 USD, 1M −90.97 USD,
// SINCE OPEN +9.34 USD. A scrubbed moment keeps its amount and a range's
// name, and the legend of what it counts from takes the first line's place.
// Where the move isn't known, the first is the close it would count from, if
// known, and the second a mode's or a range's name alone, or at an open
// while the day's move waits on its close, FIRST TRADES · MOVE SOON.
function heroLines(quote, view, latest, now, day, calendars, changeMode, scrubbing) {
  var none = { label: "", changeText: "", tone: "flat" }
  if (!quote || !view) return { close: null, caption: none, move: "" }
  var today = exchangeDay(quote, now)
  var newest = view.newest || null
  var period = view.periodLabel || ""
  var from = closeCountedFrom(quote, view, today, calendars)
  var close = null
  if (!scrubbing && newest) close = closeLine(quote, today, changeMode, view, calendars)
  else if (!scrubbing) close = extendedStack(quote, latest, now, day, changeMode, calendars) || closeOnly(from, quote.untraded)
  var whole = !!close && !!newest && newest.closed && !newest.joined
  if (whole && close.price === "") close = closeOnly(from) || close
  else if (whole && period === "") close.since = sinceClose(quote, newest, changeMode)
  var rangeName = period === "24H" ? "" : period
  if (view.pct === null) return { close: close, caption: { label: !scrubbing && period === "" && moveAwaited(quote, view) ? "FIRST TRADES · MOVE SOON" : rangeName, changeText: "", tone: "flat" }, move: view.changeText }
  var label = scrubbing ? rangeName : period || moveName(quote, newest, from, today)
  var other = view.unit === "abs" ? "pct" : "abs"
  var caption = { label: label, changeText: inMoney(quote, Format.changeText(view, other, quote.priceDigits), other), tone: Format.changeTone(view, other, quote.priceDigits) }
  return { close: close, caption: caption, move: inMoney(quote, view.changeText, view.unit) }
}

// A move in money beside a percent names its currency, as the listing's
// line does (`listingMeta`), so +4.75 USD never reads as a percent. An
// index moves in points, so its move names none, as the screenshot's
// (`Share.js`).
function inMoney(quote, text, unit) {
  return unit === "abs" && quote.currency && quote.instrumentType !== "INDEX" ? text + " " + currencyLabel(quote.currency) : text
}

// The close the move counts from, or only its name where the price on top
// is it (`shown`), as a listing's IPO price before its first trade.
function closeOnly(from, shown) {
  return from ? { label: from.label, time: "", price: shown ? "" : from.price, changeText: "", tone: "flat", stale: false } : null
}

// A price of the session with no close to count from: for minutes after an
// open, until Yahoo's answers count from the close just gone
// (`CarriedClose.carryClose`).
function moveAwaited(quote, view) {
  var reg = quote.session.regular
  return !!reg && !Format.isFiniteNumber(view.close) && Format.isFiniteNumber(view.asOf) && view.asOf >= reg.start
}

// The pill's hover on a listing's first day: before its first trade, that
// there is none yet, with the IPO price the pill shows; after it, the IPO
// price, while the pill's move (`row`) counts from it: not since the open,
// nor from the close just gone once tonight or the next day's pre-market
// trades.
function listingNote(quote, row, mode) {
  if (!Quote.listingDay(quote) || !Format.isFiniteNumber(quote.prevClose)) return ""
  var price = Format.money(quote.prevClose, quote.priceDigits)
  if (quote.untraded) return "Not traded yet · IPO price " + price
  return mode !== "open" && !!row && row.close === quote.prevClose ? "From its IPO price, " + price : ""
}

// The pill's hover past its symbol and move: only what the pill can't
// show. At night, "overnight" (with "as of 23:12" once late) and how the
// closed day ended, "today −3.45%" or "Fri −1.42%". Else the session of a
// price from outside the regular one, "after hours", with "as of 23:12"
// once late, by the rules the rows and the panel go by: a row's "As of"
// (`Freshness.freshnessText`) and the panel's dimmed night price
// (`newestStale`). Nothing while a warning names both itself. `fresh` is
// the pill's own (`Freshness.freshness`).
function pillNote(quote, newest, fresh, mode, calendars, retro) {
  if (Freshness.freshnessWarns(fresh)) return ""
  var now = fresh.now
  var late = fresh.state === "aged" || fresh.state === "saved" || newestStale(newest, now)
  var session = [newest ? Market.phaseLabel(newest.phase).toLowerCase() : "", late ? asOfNote(quote, fresh.asOf, now, calendars) : ""]
    .filter(function(part) { return part !== "" }).join(" ")
  if (!newest || !newest.joined) return session
  var closed = rowModel(quote, 0, mode === "abs" ? "abs" : "pct")
  if (closed.pct === null) return session
  var today = exchangeDay(quote, now)
  var head = Quote.headlineQuote(quote)
  var dayT = head && head.t !== null ? head.t : quote.session && quote.session.regular ? quote.session.regular.start : null
  var named = dayT !== null ? moveDay(quote, dayT, today) : ""
  var day = named === "TODAY" ? "today" : Format.sentenceCase(named)
  var ended = (day ? day + " " : "") + Format.lookSigns(closed.changeText, retro)
  return [session, ended].filter(function(part) { return part !== "" }).join(" · ")
}

function asOfNote(quote, t, now, calendars) {
  return "as of " + Market.tradeDay(quote, t, now, calendars) + Market.tradeTime(quote, t, calendars)
}

function newestStale(newest, now) {
  return !!newest && newest.phase === "overnight" && now - newest.t > Overnight.OVERNIGHT_STALE
}

function staleNightNote(quote, newest, now, calendars) {
  return quote && newestStale(newest, now) ? asOfNote(quote, newest.t, now, calendars).toUpperCase() : ""
}

// The bull or bear for a stock's day move, shared by the header and the pill.
function animalKind(row) {
  return !row || row.dayTone === "flat" ? "" : row.dayTone === "up" ? "bull" : "bear"
}

// The header's animal: the day's bull or bear, and while no move is known,
// as at an open abroad or before any price comes, the plain bull, Stonks'
// own mark, in neither the up nor the down colour. The pill draws its flat
// rule then, as the row draws its dash.
function headerAnimal(row) {
  return !row || row.dayUp === null ? "plain" : animalKind(row)
}
