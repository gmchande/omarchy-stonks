.pragma library
.import "Format.js" as Format
.import "Market.js" as Market
.import "Overnight.js" as Overnight
.import "Quote.js" as Quote

// What a quote shows: the rows' and the hero's figures, the list's breadth,
// the day's info line, the line under the price, freshness, and the pill's
// arrow. Knows nothing of how the quote was parsed or when markets open.
//
// Presentation follows Apple's Stocks app where it has already decided:
// prices stay in the listing's currency, the currency code and exchange sit
// on one line, the headline price is the regular close with the extended
// hours print labelled separately.

function arrowAngle(pctChange) {
  if (!Format.isFiniteNumber(pctChange)) return 0
  return Format.clamp(pctChange / 5, -1, 1) * 45
}

// The listing line's exchange and currency, the code said once: left out
// where the name, shown whole (not `nameCut`), already ends with it, as
// Yahoo names a pair ("Bitcoin USD"), and where Yahoo named no currency.
function listingMeta(quote, nameCut) {
  var code = quote.currency || ""
  var name = String(quote.name || "")
  var said = !nameCut && name.slice(-code.length - 1) === " " + code
  return quote.exchange + (code === "" || said ? "" : " · " + currencyLabel(code))
}

// A currency as Stonks says it: Yahoo's code, but pence, London's "GBp",
// as PENCE: beside the capitals around it, GBp reads as GBP, and 3,648.00
// as pounds.
function currencyLabel(code) {
  return code === "GBp" ? "PENCE" : code
}

// A freshness whose warning is said once for every listing, where Yahoo
// sends nothing for any (`StonksBody.yahooDown`): a failed or overdue
// refresh reads as an aged quote, which says only when its price is from.
function quietFreshness(fresh) {
  return freshnessWarns(fresh) ? Object.assign({}, fresh, { state: "aged" }) : fresh
}

// Freshness is three separate facts, kept separate: the time the headline
// quote stands for, whether a refresh was asked for and has had no answer,
// and whether the last one failed. The policy is presentation, not a claim
// about the provider: a symbol that trades is asked for at the refresh
// interval, so a live indicator is honest for a quote under two minutes old.

var LIVE_QUOTE_MAX_AGE = 120

// Room for a run of the whole list and three tries of a bad answer before
// a refresh owed counts as overdue.
var OVERDUE_AFTER = 90

// How long, in seconds, a quote Stonks let go old, its last answer older
// than a live one (LIVE_QUOTE_MAX_AGE), says nothing of its age once its
// refresh is asked: about the time a normal answer takes, so a surface
// opening on a row nothing kept fresh (a cryptocurrency, with nothing open)
// shows no "As of" for the moment before the fresh price lands; on a slow
// network it says "As of" from then until the answer. Timed to the
// millisecond by the service (`Service.asking`): counted in whole seconds of
// the clock it would end anywhere from 1 to 2 s on.
var ASKED_GRACE = 2

// entry: the feed's last answer, { status: "ok"|"failed"|"saved",
// answeredAt }, "saved" for a quote kept from an earlier session, or null
// before any. owedSince: when a refresh began waiting on Yahoo, its request
// out unanswered or the host paused (`QuoteFeed.owed`), or 0. inGrace: its
// refresh was asked for under ASKED_GRACE ago (`Service.asking`). A symbol
// nobody asked for is never late, so no cadence enters the rule; nor is one
// Stonks' own pacing holds. A quote old by its market's clock is "aged";
// "asking" in its grace while its last answer is older than a live quote,
// so its age goes unsaid only where Stonks, not the source, let it go old:
// a source sending late (London, 15 minutes) is answered every minute and
// says "As of" throughout. A quote still the last session's in the first
// moments of a session is "asking" too, as Stonks asks again for its first
// price (`Market.awaitingOpen`). Its words name the time of the price on
// top: the newest since the close where there is one (`newest`,
// `Overnight.newestPrint`), as a Robinhood print stays on top while Yahoo
// fails, else Yahoo's.
function freshness(entry, quote, now, owedSince, inGrace, newest) {
  var head = quote ? Quote.headlineQuote(quote) : null
  var phase = quote ? Market.sessionPhase(quote, now) : "closed"
  var asOf = head ? head.t : null
  var shownAt = head && newest ? newest.t : asOf
  var overdue = owedSince > 0 && now - owedSince >= OVERDUE_AFTER
  // The quote stands for another day than the clock's: the words name the day.
  var earlier = !!shownAt && exchangeDay(quote, shownAt) !== exchangeDay(quote, now)
  var asking = (!!inGrace && !!entry && now - entry.answeredAt > LIVE_QUOTE_MAX_AGE) || Market.awaitingOpen(quote, now)
  var state = entry && entry.status === "failed" ? "failed"
    : overdue ? "overdue"
    : !quote || !head ? "unavailable"
    : entry && entry.status === "saved" ? "saved"
    : asOf !== null && Market.isTrading(phase) && now - asOf > LIVE_QUOTE_MAX_AGE ? (asking ? "asking" : "aged")
    : "fresh"
  return { state: state, asOf: shownAt, session: newest ? newest.phase : "", earlier: earlier,
    live: asOf !== null && state === "fresh" && Market.isTrading(phase), phase: phase }
}

// The words for a freshness state, or "" when nothing needs saying. A quote
// kept from an earlier session says when it is from until its first answer.
// The time is the quote's exchange's (`Market.printClock`), its zone named
// where the reader's clock differs; a newest price since the close on top
// is named by its session, "OVERNIGHT 00:50", as its caption is.
function freshnessText(fresh, quote, calendars) {
  if (!fresh) return ""
  // With nothing ever answered there was nothing to refresh: "Refresh
  // failed" is for a symbol that had data and lost it.
  var head = quote ? Quote.headlineQuote(quote) : null
  if (!fresh.asOf) {
    if (head) return (fresh.state === "failed" ? "REFRESH FAILED · "
      : fresh.state === "overdue" ? "UPDATE OVERDUE · " : fresh.state === "saved" ? "SAVED · " : "") + "TIME NOT SENT"
    return fresh.state === "failed" ? "NO DATA FOR THIS SYMBOL" : fresh.state === "unavailable" || fresh.state === "overdue" ? "NO DATA" : ""
  }
  var chartTrade = head && head.source === "chart"
  var lead = fresh.session ? Market.phaseLabel(fresh.session).toUpperCase() + " " : chartTrade ? "LAST TRADE · " : "AS OF "
  var asOf = lead + (fresh.earlier ? Format.WEEKDAYS[Format.localClock(fresh.asOf, quote.gmtoffset).weekday].toUpperCase() + " " : "")
    + Market.printClock(quote, fresh.asOf, calendars)
  if (fresh.state === "failed") return "REFRESH FAILED · " + asOf
  if (fresh.state === "overdue") return "UPDATE OVERDUE · " + asOf
  if (chartTrade || fresh.state === "aged" || fresh.state === "saved") return asOf
  return ""
}

function freshnessWarns(fresh) {
  return !!fresh && (fresh.state === "failed" || fresh.state === "overdue")
}

// The extended-hours line under the price: the newest print outside the
// regular session (`latest`, the chart's newest print of all, or the
// quote's own last), with its move against the quote's regular close. Null
// during the regular session. An overnight print says its own time, by the
// calendar the chart's `day` carries when it has one, and is `stale` once
// OVERNIGHT_STALE old at `now`. A pre- or post-market print that shows as
// the close itself is left out: an exchange with no extended session echoes
// its close. An overnight print is a trade, and stays.
// The move is in the hero's unit (`changeMode`): an amount in "abs", else a
// percent. Since the open, it is still measured from the close: the open
// belongs to the regular session the hero's figure covers, and a move from
// it to this print would count that session again under an AFTER HOURS
// label.
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

// What a day's chart says in words where it has almost nothing to draw:
// no bar at all ("No trades charted": CVR on Friday 16 October, its last
// trade Wednesday's), or one ("Traded only at 14:10": CKX's one bar, its
// time where the listing trades, the zone named where the reader's
// differs). A bar is five minutes of trades, so the words speak of the
// chart, not of each trade. "" otherwise, and for an empty day before its
// session opens at `now`: an index has no print before its bell. Nor for
// one bar before its day is over at `now`, its last hour ended (its
// session's, or a 1D chart's own, its night's close where a night follows
// it: `axis.closes`): only then is it the only one. The S&P 500's first
// bar at 09:35 and Sunday night's first at 20:05 are the first of many.
// Nor for Yahoo's live moment, which it stamps at the price's own second,
// apart from the bars at their five-minute starts. Nor
// for an empty day whose quote is a trade of its session, with a price and
// a volume beside the chart: WREN's 09:30 trade with no bar at 09:37.
function dayNote(day, now, calendars) {
  if (!day) return ""
  var pts = day.points
  var over = now >= (day.axis && day.axis.closes ? day.axis.closes : Quote.dayEnd(day))
  if (pts.length === 1) return pts[0].t % (5 * 60) === 0 && over ? "Traded only at " + Market.printClock(day, pts[0].t, calendars) : ""
  if (pts.length > 1) return ""
  var regular = day.session.regular
  if (!regular) return "No trades charted"
  var head = Quote.headlineQuote(day)
  var tradedToday = !!head && head.t !== null && head.t >= regular.start
  return now < regular.start || tradedToday ? "" : "No trades charted"
}

// The day a moment falls on in the quote's exchange, as a day count: two
// moments on one count are on one day there.
function exchangeDay(quote, t) {
  return quote && Format.isFiniteNumber(t) ? Math.floor((t + (quote.gmtoffset || 0)) / 86400) : null
}

// The info block's first line on the day, titled by `dayTitle`: its regular
// low and high once known, the price's place between them, then its open
// and volume. An end the day pushes to its 52-week mark takes that
// direction's tone, as the 52-week line's does (`Fundamentals.yearLine`).
// The open keeps its slot before the session's first bar, so the line keeps
// its shape; VOL's is as wide as 999.9M. With no quote there is no line.
function dayLine(quote, today) {
  if (!quote) return null
  var q = quote
  var head = Quote.headlineQuote(q)
  var range = Format.infoRange(q.dayLow, q.dayHigh, head ? head.price : null, q.priceDigits)
  if (range.high !== null && Format.isFiniteNumber(q.fiftyTwoWeekHigh) && range.high >= q.fiftyTwoWeekHigh) range.highTone = "up"
  if (range.low !== null && Format.isFiniteNumber(q.fiftyTwoWeekLow) && range.low <= q.fiftyTwoWeekLow) range.lowTone = "down"
  return {
    title: dayTitle(q, today),
    range: range,
    facts: [
      { label: "OPEN", value: Format.isFiniteNumber(q.dayOpen) ? Format.money(q.dayOpen, q.priceDigits) : "", widest: range.widest },
      { label: "VOL", value: Format.isFiniteNumber(q.volume) ? Format.compactNumber(q.volume) : "", widest: Format.widest("999.9M") }
    ]
  }
}

// The day line's title, three letters at most, as a range's token is:
// "1D" for today's figures (`today` is `exchangeDay` of the clock), else
// their session's name (`pastDayName`); a coin's last 24 hours
// (`Quote.coinDay`), "24H".
function dayTitle(quote, today) {
  if (quote.rolling) return "24H"
  return pastDayName(quote, quote.figuresDay, today) || "1D"
}

// The name of a day before `today` that holds `t` (`dayName`); "" for
// today.
function pastDayName(quote, t, today) {
  var day = exchangeDay(quote, t)
  return day !== null && today - day > 0 ? dayName(quote, t, today) : ""
}

// The name of the day that holds `t`, up to `today`: its weekday in the
// exchange's calendar ("FRI"), which names one day of the six before
// today, since no calendar closes longer than five (Tokyo's Golden Week).
// A day a week old or more, as a halted listing's, says its month ("SEP"),
// never a weekday that would read as this week's.
function dayName(quote, t, today) {
  var d = new Date((t + (quote.gmtoffset || 0)) * 1000)
  return today - exchangeDay(quote, t) < 7 ? Format.WEEKDAYS[d.getUTCDay()].toUpperCase() : Format.MONTHS[d.getUTCMonth()]
}

// Every title `dayTitle` can give.
function dayTitles() {
  return ["1D", "24H"].concat(Format.WEEKDAYS.map(function(w) { return w.toUpperCase() }), Format.MONTHS)
}

// How the list reads on the figures its rows show: up, flat, and down, and
// the rows with no figure yet. The rows' own price and tone rules, so the
// rule under the list name never disagrees with them: at rest, each
// listing's newest price since its close where it has one (`newest`, by
// symbol, `Overnight.newestPrint`).
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

// What a quote reads at `scrubT`, { price, t, base }, `base` shaped as
// `Quote.change` reads it: a scrubbed moment of its day (`Quote.readingAt`)
// from the close it is measured from (`scrubbedBase`); at rest, its price
// on top (`Quote.restingRead`), the newest since the close (`newest`) where
// there is one.
function reading(quote, scrubT, newest) {
  if (!scrubT) return Quote.restingRead(quote, newest)
  var read = Quote.readingAt(quote, scrubT)
  return { price: read.price, t: read.t, base: scrubbedBase(quote, scrubT) }
}

// The one projection every price on screen comes from. At rest it is the
// price on top: the regular-market quote, its change from Yahoo's previous
// close or the day's open (`Quote.headlineBase`), or, once the listing has
// traded since its regular close, its newest price (`newest`,
// `Overnight.newestPrint`), its change from that close, its session and
// time said beside it (`newestCaptions`). A non-zero scrubT reads that
// moment of the day (`Quote.readingAt`), its change from the close the
// dashed line is at (`Quote.dayBase`), or, past the session's close, from
// that close, as the price on top is (`scrubbedBase`).
// dayUp is always versus that close, so the chart fill does not flip when
// the change mode does, and it is the direction at the moment shown, as a
// range's is. dayTone is that change's tone, flat when it rounds to nothing,
// so the bull and bear follow a scrub and a replay, and a flat day has
// neither.
// It carries no drawing: a line is drawn from its quote, so it redraws when
// the quote does, not with the clock or the change mode. Nor does it read
// the clock, so a row is not derived again every second. Pass the
// already-snapped scrub time.
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
    // Null stays null: an unavailable change must not read as unchanged.
    pct: chg.pct,
    abs: chg.abs,
    tone: Format.changeTone(chg, mode, quote.priceDigits),
    dayUp: direction.pct === null ? null : direction.up,
    dayTone: Format.changeTone(direction, "pct", quote.priceDigits),
    changeText: Format.changeText(chg, mode, quote.priceDigits),
    changeLine: Format.changeText(chg, mode, quote.priceDigits) + (mode === "open" && chg.pct !== null && !since ? " open" : ""),
    periodLabel: since ? "" : quote.rolling && mode !== "open" ? "24H" : Format.changeCaption(mode),
    // The newest price since the close on top, { t, p, phase }, or null.
    newest: since
  }
}

// What a scrubbed moment `t` of a quote's day is measured from, shaped as
// `Quote.change` reads it: the close the day is measured from, and its
// open. A print after the session's close is read from that close
// (`readsClose`), as the price on top is once the listing trades after
// it. A moment of the coming day a two-day answer holds after it, once
// that day has a print, is that day's, as the 1D chart draws it
// (`Quote.tailDay`): from the quote's own close, so a row following a
// scrub into the pre-market reads what the hero does. With no session
// opened since that close, both read "since the open" from it too, as the
// price on top does (`Quote.restingRead`).
function scrubbedBase(quote, t) {
  var tail = Quote.tailStart(quote)
  if ((tail !== null && t >= tail && Quote.lastPrintTime(quote) >= tail) || readsClose(quote, t)) {
    var close = Quote.regularClose(quote)
    return { prevClose: close, dayOpen: close }
  }
  return { prevClose: Quote.dayBase(quote), dayOpen: quote.dayOpen }
}

// Whether a scrub at `t` reads a print after its day's regular session
// closed, of a listing with extended hours whose quote is that close: the
// after hours and the night after them. The close itself, read at the
// bell (`Quote.readingAt`), is the session's.
function readsClose(quote, t) {
  var reg = quote.session.regular
  var head = Quote.headlineQuote(quote)
  if (!reg || !quote.session.post || quote.crypto || t < reg.end || !head || head.t === null || head.t < reg.end) return false
  return !Quote.readingAt(quote, t).close
}

// What a scrub of the 1D `day` reads its moves from, said where the line
// under the price was: the dashed line's close, the one before the day's
// session (`Quote.dayBase`). Within the session, on its own day, that is
// the previous close. Once the session has closed, the last close is its
// own: so a scrub past its close (`scrubT`, 0 at rest), and any reading
// once the day is past (`today`), as overnight or on a weekend, names the
// session the line's close comes before: "CLOSE BEFORE TUE", or, a week
// old or more, its date, "CLOSE BEFORE 12 SEP", since "BEFORE SEP" would
// read as before September. A scrub of a print after the session's close
// reads from the session's own close (`readsClose`), named as the line
// under the price names it at rest, "TUE CLOSE 249.87": not the dashed
// line's, so the panel draws no dashed mark beside it.
function dayBaselineText(day, today, scrubT) {
  var reg = day.session.regular
  if (scrubT > 0 && readsClose(day, scrubT))
    return closeLabel(day, today) + " " + Format.money(Quote.regularClose(day), day.priceDigits)
  var closed = !!reg && (pastDayName(day, reg.start, today) !== "" || (scrubT > 0 && scrubT >= reg.end))
  return (closed ? "CLOSE BEFORE " + sessionName(day, reg.start, today) : "PREV CLOSE") + " " + Format.money(Quote.dayBase(day), day.priceDigits)
}

// The regular close's name, for the line under the price: "CLOSE" on its
// own day (`today`), else with its day's name, "FRI CLOSE".
function closeLabel(quote, today) {
  var head = Quote.headlineQuote(quote)
  var day = head && head.t !== null ? pastDayName(quote, head.t, today) : ""
  return (day ? day + " " : "") + "CLOSE"
}

// The line under the price while the newest price since the close is on
// top (`rowModel`'s `newest`): the regular close and its own day's move, in
// the hero's unit, a percent since the open, as `extendedStack`'s are.
function closeLine(quote, today, changeMode) {
  var unit = changeMode === "abs" ? "abs" : "pct"
  var row = rowModel(quote, 0, unit)
  return { label: closeLabel(quote, today), time: "", price: row.priceText, changeText: row.changeText, tone: row.tone, stale: false }
}

// The newest price's session and time (`newest`, { t, phase }), with its
// day where the listing trades when it isn't `now`'s: "OVERNIGHT 23:25",
// "AFTER HOURS FRI 19:55"; on a longer range after what its move is
// measured over (`period`, "1W"), "1W · OVERNIGHT 23:25", so the range's
// move never reads as the night's. Each form shorter than the one before,
// for a caption with no room for the one before: then without the day.
// Upper case for the hero's caption; the rows and the pill's hover say it
// in sentence case (`newestNote`).
function newestCaptions(quote, newest, now, calendars, period) {
  var label = (period ? period + " · " : "") + (newest.phase === "overnight" ? "OVERNIGHT" : newest.phase === "post" ? "AFTER HOURS" : "PRE-MARKET")
  var clock = Market.printClock(quote, newest.t, calendars)
  var day = Market.printDay(quote, newest.t, now, calendars).toUpperCase()
  return [label + " " + day + clock, label + " " + clock]
}

// The newest price's session and time as a row's name line and the pill's
// hover say it: "Overnight 23:25", "After hours Fri 19:55".
function newestNote(quote, newest, now, calendars) {
  var label = newest.phase === "overnight" ? "Overnight" : newest.phase === "post" ? "After hours" : "Pre-market"
  return label + " " + Market.printDay(quote, newest.t, now, calendars) + Market.printClock(quote, newest.t, calendars)
}

// Whether the newest price on top is old: a night's print missed by more
// than one of Robinhood's bars (`Overnight.OVERNIGHT_STALE`), as the line
// under the price dims it.
function newestStale(newest, now) {
  return !!newest && newest.phase === "overnight" && now - newest.t > Overnight.OVERNIGHT_STALE
}

// The session that starts at `start`, named for the line beside the dashed
// line: its weekday within the week (`dayName`), else its date.
function sessionName(day, start, today) {
  if (today - exchangeDay(day, start) < 7) return dayName(day, start, today)
  var d = new Date((start + (day.gmtoffset || 0)) * 1000)
  return d.getUTCDate() + " " + Format.MONTHS[d.getUTCMonth()]
}

// The day's animal for a row (`rowModel`): "bull" up, "bear" down, by
// `dayTone`, and "" on a flat day or with no row. The header's and the
// pill's read this one rule, so the two never disagree on the same moment.
function animalKind(row) {
  return !row || row.dayTone === "flat" ? "" : row.dayTone === "up" ? "bull" : "bear"
}
