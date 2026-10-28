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
// price (`Market.awaitingOpen`).
function freshness(entry, quote, now, owedSince, inGrace) {
  var head = quote ? Quote.headlineQuote(quote) : null
  var phase = quote ? Market.sessionPhase(quote, now) : "closed"
  var asOf = head ? head.t : null
  var overdue = owedSince > 0 && now - owedSince >= OVERDUE_AFTER
  // The quote stands for another day than the clock's: the words name the day.
  var earlier = !!asOf && exchangeDay(quote, asOf) !== exchangeDay(quote, now)
  var asking = (!!inGrace && !!entry && now - entry.answeredAt > LIVE_QUOTE_MAX_AGE) || Market.awaitingOpen(quote, now)
  var state = entry && entry.status === "failed" ? "failed"
    : overdue ? "overdue"
    : !quote || !head ? "unavailable"
    : entry && entry.status === "saved" ? "saved"
    : asOf !== null && Market.isTrading(phase) && now - asOf > LIVE_QUOTE_MAX_AGE ? (asking ? "asking" : "aged")
    : "fresh"
  return { state: state, asOf: asOf, earlier: earlier, live: asOf !== null && state === "fresh" && Market.isTrading(phase), phase: phase }
}

// The words for a freshness state, or "" when nothing needs saying. A quote
// kept from an earlier session says when it is from until its first answer.
// The time is the quote's exchange's (`Market.printClock`), its zone named
// where the reader's clock differs.
function freshnessText(fresh, quote, calendars) {
  if (!fresh) return ""
  // With nothing ever answered there was nothing to refresh: "Refresh
  // failed" is for a symbol that had data and lost it.
  var head = quote ? Quote.headlineQuote(quote) : null
  if (!fresh.asOf) {
    if (head) return (fresh.state === "failed" ? "REFRESH FAILED · "
      : fresh.state === "overdue" ? "REFRESH LATE · " : fresh.state === "saved" ? "SAVED · " : "") + "TIME NOT SENT"
    return fresh.state === "failed" ? "NO DATA FOR THIS SYMBOL" : fresh.state === "unavailable" || fresh.state === "overdue" ? "NO DATA" : ""
  }
  var chartTrade = head && head.source === "chart"
  var asOf = (chartTrade ? "LAST TRADE · " : "AS OF ") + (fresh.earlier ? Format.WEEKDAYS[Format.localClock(fresh.asOf, quote.gmtoffset).weekday].toUpperCase() + " " : "")
    + Market.printClock(quote, fresh.asOf, calendars)
  if (fresh.state === "failed") return "REFRESH FAILED · " + asOf
  if (fresh.state === "overdue") return "REFRESH LATE · " + asOf
  if (chartTrade || fresh.state === "aged" || fresh.state === "saved") return asOf
  return ""
}

function freshnessWarns(fresh) {
  return !!fresh && (fresh.state === "failed" || fresh.state === "overdue")
}

// Why prices stopped and when Stonks tries again, from the gate of the host
// quotes come from (`Gate.qml`): its `pause`, "none" when nothing answered
// or "refused", and `pausedUntil`, the second its next request may go, which
// the service's clock wakes for. Null while the host answers: then Stonks
// doesn't know why. A pause for no answer lasts 72 s at most, so it is said
// in minutes, rounded up; a refusal's can last half an hour, so it names the
// time on the reader's clock. `why` and `when` in full, for the pill's
// hover; `forms`, the header's, each shorter than the one before, the last
// one fitting the popup at text size 20, where a refusal's is "Refused".
// Each form says what Stonks knows, that nothing answered or that it was
// asked to wait, and guesses no cause.
// No source is named: not every reader knows Yahoo (the owner, 26 October).
function hostPause(pause, pausedUntil, now) {
  var left = pausedUntil - now
  if (pause === "none") {
    var minutes = Format.duration(Math.max(1, left))
    var noAnswer = { why: "No answer, check your connection",
      when: "Trying again within " + (left > 60 ? Math.ceil(left / 60) + " minutes" : "a minute") }
    noAnswer.forms = [noAnswer.why + " · " + noAnswer.when, "No answer · Next try in " + minutes, "No answer · Next try " + minutes]
    return noAnswer
  }
  if (pause === "refused") {
    var at = left > 0 ? Format.hhmm(pausedUntil, Format.readerOffset(pausedUntil)) : ""
    var refused = { why: "The site Stonks gets prices from asked it to wait", when: at ? "Trying again at " + at : "Trying again now" }
    refused.forms = [refused.why + " · " + refused.when, "Asked to wait · Next try " + (at ? "at " + at : "now"),
      "Refused · Next try " + (at || "now")]
    return refused
  }
  return null
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
// session opens at `now`: an index has no print before its bell. Nor while
// the one point may still be the session's first bar, forming: Yahoo's
// live moment, which it stamps at the price's own second, apart from the
// bars at their five-minute starts, stands alone while the first bar has
// no close yet (^GSPC at 09:30:25; London's at 08:02, seen 15 minutes
// late), and a bar is whole only once `now` is past its five minutes. Nor
// for an empty day whose quote is a trade of its session, with a price and
// a volume beside the chart: WREN's 09:30 trade with no bar at 09:37.
function dayNote(day, now, calendars) {
  if (!day) return ""
  var pts = day.points
  var bar = 5 * 60
  if (pts.length === 1) return pts[0].t % bar === 0 && now >= pts[0].t + bar ? "Traded only at " + Market.printClock(day, pts[0].t, calendars) : ""
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
// their session's name (`pastDayName`).
function dayTitle(quote, today) {
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
  return ["1D"].concat(Format.WEEKDAYS.map(function(w) { return w.toUpperCase() }), Format.MONTHS)
}

// How the list reads on the figures its rows show: up, flat, and down, and
// the rows with no figure yet. The rows' own price and tone rules, so the
// rule under the list name never disagrees with them.
function listBreadth(symbols, quotes, scrubT, mode) {
  var out = { up: 0, flat: 0, down: 0, none: 0 }
  for (var i = 0; i < symbols.length; i++) {
    var quote = quotes[symbols[i]]
    var read = quote ? (scrubT ? Quote.readingAt(quote, scrubT) : Quote.headlineQuote(quote)) : null
    var price = read ? read.price : null
    var chg = quote ? Quote.change(measuredAt(quote, scrubT), price, mode) : null
    if (!chg || chg.pct === null) out.none++
    else out[Format.changeTone(chg, mode, quote.priceDigits)]++
  }
  return out
}

// What a moment of a quote's day is measured from (`rowModel`), shaped as
// `Quote.change` reads it: at rest the headline's (`Quote.headlineBase`),
// and a scrubbed moment the dashed line's (`scrubbedBase`).
function measuredAt(quote, scrubT) {
  return scrubT ? scrubbedBase(quote) : Quote.headlineBase(quote)
}

// The one projection every price on screen comes from. The headline is
// the regular-market quote, its change from Yahoo's previous close or the
// day's open (`Quote.headlineBase`); a
// non-zero scrubT reads that moment of the day (`Quote.readingAt`), its
// change from the close the dashed line is at (`Quote.dayBase`): before the
// open, the last session's close. Every print the chart draws reads from
// that one close, the night's and the coming day's pre-market's after the
// day too, so wherever the pointer is the change and the animal say where
// that price stands against the dashed line; at rest the line under the
// price still measures the night from the day's own close (`extendedStack`).
// dayUp is always versus that close, so the chart fill does not flip when
// the change mode does, and it is the direction at the moment shown, as a
// range's is. dayTone is that change's tone, flat when it rounds to nothing,
// so the bull and bear follow a scrub and a replay, and a flat day has
// neither.
// It carries no drawing: a line is drawn from its quote, so it redraws when
// the quote does, not with the clock or the change mode. Nor does it read
// the clock, so a row is not derived again every second. Pass the
// already-snapped scrub time.
function rowModel(quote, scrubT, mode) {
  var read = scrubT ? Quote.readingAt(quote, scrubT) : Quote.headlineQuote(quote)
  var price = read ? read.price : null
  var measured = measuredAt(quote, scrubT)
  var chg = Quote.change(measured, price, mode)
  var direction = Quote.change(measured, price, "pct")
  return {
    symbol: quote.symbol,
    name: quote.name,
    price: price,
    priceText: Format.money(price, quote.priceDigits),
    asOf: read ? read.t : null,
    // Null stays null: an unavailable change must not read as unchanged.
    pct: chg.pct,
    abs: chg.abs,
    tone: Format.changeTone(chg, mode, quote.priceDigits),
    dayUp: direction.pct === null ? null : direction.up,
    dayTone: Format.changeTone(direction, "pct", quote.priceDigits),
    changeText: Format.changeText(chg, mode, quote.priceDigits),
    changeLine: Format.changeText(chg, mode, quote.priceDigits) + (mode === "open" && chg.pct !== null ? " open" : ""),
    periodLabel: Format.changeCaption(mode)
  }
}

// What a scrubbed moment of a quote's day is measured from, shaped as
// `Quote.change` reads it: the close the day is measured from, and its open.
function scrubbedBase(quote) {
  return { prevClose: Quote.dayBase(quote), dayOpen: quote.dayOpen }
}

// What a scrub of the 1D `day` reads its moves from, said beside its dashed
// line: the line's own close, the one before the day's session
// (`Quote.dayBase`), which every print of the chart reads from. Within the
// session, on its own day, that is the previous close. Once the session
// has closed, the last close is its own: so a scrub past its close
// (`scrubT`, 0 at rest), and any reading once the day is past (`today`),
// as overnight or on a weekend, names the session the line's close comes
// before: "CLOSE BEFORE TUE", or, a week old or more, its date, "CLOSE
// BEFORE 12 SEP", since "BEFORE SEP" would read as before September.
function dayBaselineText(day, today, scrubT) {
  var reg = day.session.regular
  var closed = !!reg && (pastDayName(day, reg.start, today) !== "" || (scrubT > 0 && scrubT >= reg.end))
  return (closed ? "CLOSE BEFORE " + sessionName(day, reg.start, today) : "PREV CLOSE") + " " + Format.money(Quote.dayBase(day), day.priceDigits)
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
