.pragma library
.import "Calendar.js" as Calendar
.import "CarriedClose.js" as CarriedClose
.import "Fundamentals.js" as Fundamentals
.import "History.js" as History
.import "Market.js" as Market
.import "Overnight.js" as Overnight
.import "Quote.js" as Quote

// What Stonks asks Yahoo and Robinhood for, and when. Screens and each
// host's gate still decide whether it goes now.

// ---- Quotes

// Two seconds of a minute are never more than 30 s apart one way, so a
// symbol answered at its own second (featured, added, retried) joins the
// next run and the list stays one run.
var DUE_SOON = 30

var REFRESH_AGAIN = 10

var TRIES = 3

// Reads each calendar once, not once a listing.
function calendarsAt(calendars, now) {
  var read = new Map()
  return function(quote) {
    var cal = Calendar.calendarFor(calendars, quote)
    if (!read.has(cal)) read.set(cal, Calendar.calendarNow(cal, now))
    return read.get(cal)
  }
}

function watchedSymbols(allSymbols, featured, open) {
  return allSymbols.filter(function(s) { return open || s === featured })
}

function readingOrder(featured, sights, shown, allSymbols) {
  var order = featured ? [featured] : []
  var add = function(s) { if (order.indexOf(s) < 0) order.push(s) }
  sights.forEach(function(sight) { sight.symbols.forEach(add) })
  shown.forEach(add)
  allSymbols.forEach(add)
  return order
}

// The featured stock skips the quiet wait (`quietUntil`), so a calendar wrong
// about a session can't leave the pill behind; so does a failed answer,
// which may answer next time.
function quotesDue(watched, entries, asked, quotes, charted, featured, now, interval, calNow) {
  var at = {}
  var dayOf = Calendar.tradingDays()
  watched.forEach(function(s) {
    var entry = entries[s]
    if (!entry || entry.status === "saved" || s in asked) return
    var cal = calNow(quotes[s])
    var quiet = s === featured || entry.status !== "ok" ? 0 : quietUntil(quotes[s], entry.receivedAt, now, cal.cal, dayOf)
    at[s] = entry.answeredAt > now ? now : quiet
      || entry.answeredAt + quoteCadence(quotes[s], now, interval, charted.indexOf(s) >= 0, cal)
  })
  var symbols = Object.keys(at)
  var asking = symbols.some(function(s) { return at[s] <= now })
  var due = symbols.filter(function(s) { return at[s] <= (asking ? now + DUE_SOON : now) })
  var next = 0
  symbols.forEach(function(s) { if (due.indexOf(s) < 0 && (next === 0 || at[s] < next)) next = at[s] })
  return { due: due, next: next }
}

function refreshQuotes(watched, entries, now) {
  return watched.filter(function(s) {
    var entry = entries[s]
    return !!entry && entry.status !== "saved" && now - entry.answeredAt > REFRESH_AGAIN
  })
}

function firstAnswer(entry) {
  return !entry || entry.status === "saved"
}

function keptAsks(asked, watched, entries, running) {
  var next = {}
  var dropped = false
  for (var s in asked) {
    if (firstAnswer(entries[s]) || watched.indexOf(s) >= 0 || running.indexOf(s) >= 0) next[s] = asked[s]
    else dropped = true
  }
  return dropped ? next : asked
}

function laneWaiting(symbols, asked, entries, first, held) {
  return symbols.filter(function(s) {
    return s in asked && firstAnswer(entries[s]) === first && held.indexOf(s) < 0
  })
}

function laneJudging(toJudge, asked, held) {
  return toJudge.filter(function(s) { return !(s in asked) && held.indexOf(s) < 0 })
}

// A stock's batch of one is a chart: one request either way, and a chart
// has opens; a coin's stays spark, even alone. A coin's open is its price 24
// hours ago, read from the closes, but it asks for two days
// (`twoDays`), and a batch asks two days for all when one wants two,
// so coins batch apart from stocks.
function quoteSlots(waiting, asked, symbols, featured, charted, bulk, coins) {
  var order = waiting.slice().sort(function(a, b) {
    return (b === featured) - (a === featured) || asked[a] - asked[b] || symbols.indexOf(a) - symbols.indexOf(b)
  })
  var alone = function(s) { return !bulk || charted.indexOf(s) >= 0 }
  var coin = function(s) { return !!coins && coins.indexOf(s) >= 0 }
  var slots = order.filter(alone).map(function(s) { return { symbols: [s], spark: false } })
  var batches = []
  var batched = order.filter(function(s) { return !alone(s) && !coin(s) })
  for (var i = 0; i < batched.length; i += Quote.SPARK_BATCH) {
    var batch = batched.slice(i, i + Quote.SPARK_BATCH)
    batches.push({ symbols: batch, spark: batch.length > 1 })
  }
  var coined = order.filter(function(s) { return !alone(s) && coin(s) })
  for (var j = 0; j < coined.length; j += Quote.SPARK_BATCH) batches.push({ symbols: coined.slice(j, j + Quote.SPARK_BATCH), spark: true })
  // Each batch is in the order asked, so its first symbol places it.
  batches.sort(function(x, y) { return order.indexOf(x.symbols[0]) - order.indexOf(y.symbols[0]) })
  return slots.concat(batches)
}

// A spark quote has no opens for the hero's line or the day's open.
function sparkCharted(charted, quotes, entries, afterLanding) {
  return charted.filter(function(s) {
    return !!quotes[s] && !!quotes[s].closesOnly && !(afterLanding && entries[s] && entries[s].status === "failed")
  })
}

// A refusal or no answer is the host's, not the symbol's: it stays asked
// for, and the gate paces it.
function answerVerdict(kind, outcome, tries, judgingOnly) {
  if (kind === "refused" || kind === "none") return "host"
  var quote = kind === "ok" && outcome && outcome !== "missing" ? outcome.quote : null
  if (quote) return "show"
  if (judgingOnly) return "unchanged"
  if (kind !== "missing" && outcome !== "missing" && tries < TRIES - 1) return "retry"
  return "fail"
}

// What a run's answers do to the quotes held. `held` is the feed's { quotes,
// entries, asked, tries, toJudge }; `requests` are the run's, by each
// answer's `index`, and `symbols` those the feed still keeps. Returns the
// next of each, `quotes` the same object when no quote changed, so nothing
// is worked out again and no line repaints; and `retry`, the symbols to ask
// again once the feed has waited, `back`, every symbol answered, and
// `warnings`, what to say in the log.
function quotesLanded(held, requests, got, symbols, calendars, now) {
  var quotes = null
  var entries = Object.assign({}, held.entries)
  var asked = Object.assign({}, held.asked)
  var tries = Object.assign({}, held.tries)
  var toJudge = held.toJudge.slice()
  var retry = [], back = [], warnings = []
  var show = function(symbol, answered) {
    var previous = held.quotes[symbol]
    var quote = CarriedClose.carryClose(previous, answered, calendars, now)
    var dropped = Quote.bucketTimes(quote.droppedTimes)
    if (dropped && dropped !== Quote.bucketTimes(previous ? previous.droppedTimes : null) && !quote.closesOnly)
      warnings.push(symbol + " dropped stray buckets " + dropped)
    if (!previous || !Quote.sameQuote(quote, previous)) {
      if (!quotes) quotes = Object.assign({}, held.quotes)
      quotes[symbol] = quote
    }
    entries[symbol] = { status: "ok", receivedAt: now, answeredAt: now }
  }
  var heard = function(answer, request, symbol) {
    // Removed while its run was out.
    if (symbols.indexOf(symbol) < 0) return
    // A judging chart keeps the spark answer's second: the symbol stays due
    // with the rest of its run.
    var judging = !request.spark && held.toJudge.indexOf(symbol) >= 0
    var outcome = answer.kind === "ok" ? answer.outcomes[symbol] : null
    var verdict = answerVerdict(answer.kind, outcome, tries[symbol] || 0, judging && !(symbol in held.asked))
    // A refusal or no answer leaves it asked, for the gate to pace.
    if (verdict === "host") return
    if (!request.spark) toJudge = toJudge.filter(function(s) { return s !== symbol })
    if (verdict === "unchanged") return
    if (verdict === "show") {
      if (outcome.unjudged && toJudge.indexOf(symbol) < 0) toJudge.push(symbol)
      show(symbol, outcome.quote)
      if (judging && held.entries[symbol]) entries[symbol].answeredAt = held.entries[symbol].answeredAt
    } else if (verdict === "retry") {
      tries[symbol] = (tries[symbol] || 0) + 1
      retry.push(symbol)
      return
    } else {
      entries[symbol] = Object.assign({}, entries[symbol] || { receivedAt: 0 }, { status: "failed", answeredAt: now })
    }
    delete asked[symbol]
    delete tries[symbol]
  }
  got.forEach(function(answer) {
    var request = requests[answer.index]
    if (!request) return
    request.symbols.forEach(function(symbol) { heard(answer, request, symbol) })
    back = back.concat(request.symbols)
  })
  return {
    quotes: quotes || held.quotes, entries: entries, asked: asked, tries: tries,
    toJudge: toJudge.filter(function(s) { return symbols.indexOf(s) >= 0 }),
    retry: retry, back: back, warnings: warnings
  }
}

// The close and late trades settle within this of a market's last trade.
var SETTLED = 15 * 60

// Asking sooner brings back the same price. An index's periods stay the last
// session's until its open, and London's pre-market is Yahoo's alone, so the
// calendar and Yahoo's current period both have a say.
function quietUntil(quote, receivedAt, now, cal, dayOf) {
  if (!quote || quote.crypto || !receivedAt) return 0
  var s = quote.session
  if (!s || !s.regular || receivedAt < (s.post || s.regular).end + SETTLED) return 0
  var c = quote.current
  if (c && c.regular && receivedAt >= (c.pre || c.regular).start && receivedAt < (c.post || c.regular).end + SETTLED) return 0
  var starts = []
  if (cal) {
    var day = dayOf(cal, receivedAt)
    if (day.to && receivedAt >= day.from && receivedAt < day.to + SETTLED) return 0
    var open = receivedAt < day.from ? day.from : day.next
    if (open) starts.push(open)
  }
  if (c && c.regular && (c.pre || c.regular).start > receivedAt) starts.push((c.pre || c.regular).start)
  var next = starts.length ? Math.min.apply(null, starts) : 0
  return next > now ? next : 0
}

// Yahoo's day answer for a stock turns to the coming day with its
// pre-market, and London's and Tokyo's with their open, whose first bar
// comes about 15 minutes late. Two days keep the last session in the answer
// until the new one has a trade. An index's answer stays the last session's
// until its open.
function twoDays(quote, now, calendars) {
  if (!quote) return true
  if (quote.crypto) return true
  if (quote.instrumentType === "INDEX") return false
  var cal = Calendar.calendarFor(calendars, quote)
  var date = cal ? Calendar.dateStringOf(Calendar.localDate(now, cal)) : ""
  var segs = cal ? Calendar.segmentsOn(cal, date) : []
  var pts = quote.points
  var tradedSince = function(t) { return pts.length > 0 && pts[pts.length - 1].t >= t }
  if (cal && cal.pre) {
    var pre = Calendar.epochAt(cal, date, cal.pre.open)
    return segs.length > 0 && now >= pre && (now < segs[0].start || (now < Calendar.epochAt(cal, date, cal.post.close) && !tradedSince(pre)))
  }
  var open = segs.length ? { start: segs[0].start, end: segs[segs.length - 1].end } : !cal && quote.current ? quote.current.regular : null
  return !!open && now >= open.start && now < open.end && !tradedSince(open.start)
}

// How often, while Yahoo may still answer with the last session's quote
// (`Market.awaitingOpen`).
var OPENING_ASK = 15

// Outside the session only the day's dim tail can move, so only a charted
// stock keeps the interval.
function quoteCadence(quote, now, interval, charted, calNow) {
  if (!quote) return 15 * 60
  if (quote.crypto || Market.regularNow(quote, now, calNow)) return Market.awaitingOpen(quote, now) ? Math.min(OPENING_ASK, interval) : interval
  if (calNow.quiet || calNow.breakEnd) return 15 * 60
  var phase = Market.sessionPhase(quote, now)
  if (phase === "pre" || phase === "post") return charted ? interval : Math.max(5 * 60, interval)
  return 15 * 60
}

// ---- Robinhood

// Trades due within half an interval go with those due now, so the list
// stays one request each night's 5 minutes. With nothing open while a
// night trades, the pill's symbol is asked so its newest price stays
// current. `allDay` and `nights` are Robinhood's entries; `quoteEntries`
// Yahoo's.
function overnightAsks(s) {
  var featured = s.featured
  var cal = Overnight.overnightMarket(s.calendars)
  var tonight = cal && !s.open ? Overnight.nightAt(cal, s.now) : null
  var night = !!tonight && tonight.open && s.overnightSymbols.indexOf(featured) >= 0
  var kept = s.open || night
  var featuredEntry = s.quoteEntries[featured]
  var live = !!featuredEntry && featuredEntry.status === "ok" && s.overnightSymbols.indexOf(featured) >= 0
  if (!kept && !live) return null
  var previewing = s.open && s.previewShown && !!s.previewQuote && s.allSymbols.indexOf(s.preview) < 0
    && Overnight.hasOvernight(s.previewQuote, s.calendars)
  var waited = previewing ? s.preview : featured
  var listings = s.open ? s.overnightSymbols.concat(previewing ? [s.preview] : []) : [featured]
  var tradability = listings.filter(function(x) {
    return kept ? Overnight.allDayDue(s.allDay[x], s.now) : !s.allDay[x]
  })
  var drawn = listings.filter(function(x) { return !s.allDay[x] || s.allDay[x].allDay })
  // Listings asked together share `entry.at`, so each ask is judged once.
  var judged = {}
  // The newest stretch Yahoo left empty, once Robinhood's bars for it are in.
  var quotes = s.overnightSymbols.map(function(x) { return s.quotes[x] })
  if (previewing && s.previewQuote.session) quotes.push(s.previewQuote)
  var hole = null
  for (var i = 0; i < quotes.length; i++) {
    var last = quotes[i] ? Overnight.yahooHole(quotes[i]) : null
    if (last !== null && last + Overnight.OVERNIGHT_LAG <= s.now && (hole === null || last > hole)) hole = last
  }
  var holeDue = function(x) {
    return hole !== null && !!s.allDay[x] && s.allDay[x].allDay && Overnight.holeDue(hole, s.nights[x], s.now)
  }
  var tradesDue = function(x, at) {
    var entry = s.nights[x]
    if (!entry) return true
    // At the clock's own second, not `at`: Robinhood's bars for the stretch
    // must be in.
    if (holeDue(x)) return true
    if (!kept) return false
    var key = at + " " + entry.at + " " + entry.status
    if (!(key in judged)) judged[key] = Overnight.overnightDue(entry.at, at, s.calendars, entry.status === "failed")
    return judged[key]
  }
  var trades = drawn.filter(function(x) { return tradesDue(x, s.now) })
  if (trades.length > 0)
    trades = drawn.filter(function(x) { return tradesDue(x, s.now + Overnight.OVERNIGHT_INTERVAL / 2) })
  if (tradability.length === 0 && trades.length === 0) return null
  var alone = function(symbols, answers) {
    return symbols.length > 1 && symbols.indexOf(waited) >= 0 && !answers[waited] ? [waited] : symbols
  }
  return { tradability: alone(tradability, s.allDay), trades: alone(trades, s.nights) }
}

function refreshTrades(charts, allDaySymbols, askedAt, now) {
  if (now - askedAt <= REFRESH_AGAIN) return []
  return charts.filter(function(s) { return allDaySymbols.indexOf(s) >= 0 })
}

// ---- Charts

function chartsOnShow(openSurfaces, featured, preview, previewSurface, previewShown) {
  if (openSurfaces.length === 0) return []
  var charts = []
  if (preview === "" || openSurfaces.some(function(s) { return s !== previewSurface }))
    charts.push(featured)
  if (preview !== "" && previewShown && charts.indexOf(preview) < 0)
    charts.push(preview)
  return charts.filter(function(s) { return s !== "" })
}

function historyCharts(charts, range) {
  return range === "1D" ? [] : charts
}

function historyOwing(charts, range, entries) {
  var owing = {}
  charts.forEach(function(s) {
    var key = History.historyKey(s, range)
    owing[key] = entries[key] || null
  })
  return owing
}

function nextHistory(charts, range, entries, owing) {
  var key = function(s) { return History.historyKey(s, range) }
  var owed = charts.filter(function(s) { return key(s) in owing && entries[key(s)] === owing[key(s)] })
  if (owed.length > 0) return { symbol: owed[0], force: true }
  var unanswered = charts.filter(function(s) { return !entries[key(s)] })
  return unanswered.length > 0 ? { symbol: unanswered[0], force: false } : null
}

function staleHistory(charts, range, entries, quotes, previewQuotes, now, calendars) {
  for (var i = 0; i < charts.length; i++) {
    var s = charts[i]
    var entry = entries[History.historyKey(s, range)]
    var quote = quotes[s] || previewQuotes[s]
    var trading = !!quote && (quote.crypto || Market.inRegularSession(quote, now, calendars))
    if (!!entry && !!entry.history && History.historyDue(range, entry, quote, now, trading)) return s
  }
  return ""
}

function aheadRows(open, range, charted, sights, keep) {
  if (!open || range === "1D") return []
  var rows = []
  sights.forEach(function(sight) {
    sight.symbols.forEach(function(s) { if (rows.indexOf(s) < 0 && charted.indexOf(s) < 0) rows.push(s) })
  })
  return rows.slice(0, keep - charted.length)
}

function aheadCharts(rows, range, entries, missed) {
  return rows.filter(function(s) {
    var key = History.historyKey(s, range)
    return !entries[key] && !missed[key]
  })
}

// ---- Cap and P/E

function fundamentalsWanted(charted, quotes, previewQuotes) {
  var wanted = []
  charted.forEach(function(s) {
    var quote = quotes[s] || previewQuotes[s]
    if (!quote || !Fundamentals.hasFundamentals(quote)) return
    if (wanted.some(function(w) { return w.symbol === s })) return
    wanted.push({ symbol: s, currency: String(quote.currency || "") })
  })
  return wanted
}

// ---- The clock

// `nowMs` is the wall clock, `now` the service's second. Wakes 5 ms past
// the step, so its second has begun.
function clockWait(open, nowMs, now, deadlines) {
  var wall = Math.floor(nowMs / 1000)
  var next = open ? wall + 1 : (Math.floor(wall / 60) + 1) * 60
  deadlines.forEach(function(at) { if (at > now && at < next) next = at })
  return Math.max(0, (next - wall - 1) * 1000 + 1000 - nowMs % 1000) + 5
}
