.pragma library
.import "Format.js" as Format
.import "Market.js" as Market
.import "Quote.js" as Quote

// How fresh a price is, and what Stonks says when it isn't: the live dot,
// "As of" with the price's own time, "Not updating", "Refresh failed", "No
// data", and the header's line while a site doesn't answer.

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
// "As of" throughout. The time is the newest price's, as a Robinhood trade
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
  // `now`: the words name the day when it isn't the clock's, as a trade does (`Market.tradeDay`).
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
  var asOf = lead + Market.tradeDay(quote, fresh.asOf, fresh.now, calendars).toUpperCase()
    + Market.tradeTime(quote, fresh.asOf, calendars)
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
