.pragma library
.import "Fundamentals.js" as Fundamentals
.import "History.js" as History
.import "Market.js" as Market
.import "Overnight.js" as Overnight
.import "Quote.js" as Quote

// What Stonks asks Yahoo and Robinhood for, and when: which quotes are due
// and how a run of them is made into requests, what a bad answer leads to,
// what Robinhood is asked, which chart's history goes next and which are
// fetched ahead of a click, which cap and P/E waits on its quote, and when
// the clock wakes for the next. The service and the quote feed hand in what
// they hold and run what these decide; whether a screen is on, and each
// host's gate, still decide whether it goes now.

// ---- Quotes

// A run takes with it each quote due within this many seconds, so a symbol
// answered at a second of its own (featured, added, or retried) joins the
// run at the next one, and the list stays one run: two seconds of a minute
// are never more than half a minute apart one way.
var DUE_SOON = 30

// A user's refresh asks again only for what answered more than this many
// seconds ago, so a second press adds nothing.
var REFRESH_AGAIN = 10

// Tries in all for a quote whose answers are bad before it is failed.
var TRIES = 3

// A function from a quote to its market's calendar as read at `now`
// (`Market.calendarNow`), each calendar read once, not once a listing.
function calendarsAt(calendars, now) {
  var read = new Map()
  return function(quote) {
    var cal = Market.calendarFor(calendars, quote)
    if (!read.has(cal)) read.set(cal, Market.calendarNow(cal, now))
    return read.get(cal)
  }
}

// The symbols of All whose quotes are kept fresh: the pill's alone with
// nothing open, and all of them while a surface is open (`open`), which
// asks for each as it opens.
function watchedSymbols(library, featured, open) {
  return library.filter(function(s) { return open || s === featured })
}

// The order a run asks for quotes in, ties of the second they were asked
// for broken by it (`quoteSlots`): the stock at the top, then each open
// surface's rows in sight from the top down (`sights`, { surface, symbols },
// as in `aheadRows`), then the list as shown, then the rest of All.
function readingOrder(featured, sights, shown, library) {
  var order = featured ? [featured] : []
  var add = function(s) { if (order.indexOf(s) < 0) order.push(s) }
  sights.forEach(function(sight) { sight.symbols.forEach(add) })
  shown.forEach(add)
  library.forEach(add)
  return order
}

// Of `watched`, the quotes to ask for at `now`, and the second the first of
// the rest falls due, 0 for none: { due, next }. One is due once its last
// answer, ok or failed, is as old as its market's cadence
// (`Market.quoteCadence`), or the refresh interval for one an open
// surface's hero shows (`heroes`); but a row whose market can't have moved
// since its last price waits for its market to trade again
// (`Market.quietUntil`). The pill's own (`pill`) keeps its cadence, so a
// calendar that is wrong about a session can't leave the pill behind, and
// so does a failed one, which may answer next time.
// Whatever is asked takes with it each one due within `DUE_SOON`. A symbol
// with no answer yet, one kept from an earlier session, or one already
// asked for is the feed's to ask.
function quotesDue(watched, entries, asked, quotes, heroes, pill, now, interval, calNow) {
  var at = {}
  var dayOf = Market.tradingDays()
  watched.forEach(function(s) {
    var entry = entries[s]
    if (!entry || entry.status === "saved" || s in asked) return
    var cal = calNow(quotes[s])
    var quiet = s === pill || entry.status !== "ok" ? 0 : Market.quietUntil(quotes[s], entry.receivedAt, now, cal.cal, dayOf)
    at[s] = entry.answeredAt > now ? now : quiet
      || entry.answeredAt + Market.quoteCadence(quotes[s], now, interval, heroes.indexOf(s) >= 0, cal)
  })
  var symbols = Object.keys(at)
  var asking = symbols.some(function(s) { return at[s] <= now })
  var due = symbols.filter(function(s) { return at[s] <= (asking ? now + DUE_SOON : now) })
  var next = 0
  symbols.forEach(function(s) { if (due.indexOf(s) < 0 && (next === 0 || at[s] < next)) next = at[s] })
  return { due: due, next: next }
}

// The watched quotes a user's refresh asks for: each answered, and not in
// the last `REFRESH_AGAIN` seconds.
function refreshQuotes(watched, entries, now) {
  return watched.filter(function(s) {
    var entry = entries[s]
    return !!entry && entry.status !== "saved" && now - entry.answeredAt > REFRESH_AGAIN
  })
}

// A symbol whose answer is a first answer: none yet this session, or only
// a quote kept from an earlier one.
function firstAnswer(entry) {
  return !entry || entry.status === "saved"
}

// The asks a quote feed keeps once what is watched changes: a refresh for a
// symbol no longer watched is dropped unless its run is still out
// (`running`); first answers always stay. `asked` itself when none goes.
function keptAsks(asked, watched, entries, running) {
  var next = {}
  var dropped = false
  for (var s in asked) {
    if (firstAnswer(entries[s]) || watched.indexOf(s) >= 0 || running.indexOf(s) >= 0) next[s] = asked[s]
    else dropped = true
  }
  return dropped ? next : asked
}

// The symbols a lane's next run is for, in `symbols`' order: each asked for
// whose answer is the lane's, a first answer (`first`) or a refresh, and
// not `held`: cooling after a bad answer, or out on either lane's run.
function laneWaiting(symbols, asked, entries, first, held) {
  return symbols.filter(function(s) {
    return s in asked && firstAnswer(entries[s]) === first && held.indexOf(s) < 0
  })
}

// The spark days waiting to be judged on the chart (`toJudge`) that a
// refresh run may carry: none asked for anyway, whose own answer judges it,
// and none `held`.
function laneJudging(toJudge, asked, held) {
  return toJudge.filter(function(s) { return !(s in asked) && held.indexOf(s) < 0 })
}

// A run's requests for `waiting`, in order, each { symbols, spark }: a
// chart for each hero (`heroes`), the pill's (`lead`) leading, then spark
// batches of up to `Quote.SPARK_BATCH`, each in the order asked, so one the
// budget held goes before those asked since, and those asked together in
// `symbols`' order (`readingOrder`). A batch of one is a chart: one
// request either way, and the chart's has opens, so its day needs no
// judging. The coins (`coins`) go in spark batches of their own, one alone
// too: a coin is asked for two days (`Market.twoDays`), and a batch asks
// two for all when one of them wants two, so beside the stocks it would
// double their answer; its open is its price 24 hours ago, read from the
// closes. Their batches take their place among the stocks' by the order
// asked. A feed that isn't `bulk`, the preview's, asks only charts.
function quoteSlots(waiting, asked, symbols, lead, heroes, bulk, coins) {
  var order = waiting.slice().sort(function(a, b) {
    return (b === lead) - (a === lead) || asked[a] - asked[b] || symbols.indexOf(a) - symbols.indexOf(b)
  })
  var charted = function(s) { return !bulk || heroes.indexOf(s) >= 0 }
  var coin = function(s) { return !!coins && coins.indexOf(s) >= 0 }
  var slots = order.filter(charted).map(function(s) { return { symbols: [s], spark: false } })
  var batches = []
  var batched = order.filter(function(s) { return !charted(s) && !coin(s) })
  for (var i = 0; i < batched.length; i += Quote.SPARK_BATCH) {
    var batch = batched.slice(i, i + Quote.SPARK_BATCH)
    batches.push({ symbols: batch, spark: batch.length > 1 })
  }
  var coined = order.filter(function(s) { return !charted(s) && coin(s) })
  for (var j = 0; j < coined.length; j += Quote.SPARK_BATCH) batches.push({ symbols: coined.slice(j, j + Quote.SPARK_BATCH), spark: true })
  // Each batch is in the order asked, so its first symbol places it.
  batches.sort(function(x, y) { return order.indexOf(x.symbols[0]) - order.indexOf(y.symbols[0]) })
  return slots.concat(batches)
}

// The heroes whose quotes came from spark, with no opens for the hero's line
// or the day's open, whose chart is asked for. After a run lands
// (`afterLanding`), not one whose answer just failed: its next refresh goes
// on the chart, so a failing chart is not asked again at once.
function sparkHeroes(heroes, quotes, entries, afterLanding) {
  return heroes.filter(function(s) {
    return !!quotes[s] && !!quotes[s].closesOnly && !(afterLanding && entries[s] && entries[s].status === "failed")
  })
}

// What one symbol's answer settles: "show" its quote; "retry" after a short
// pause, a bad answer before its `TRIES`th; "fail"; "host", a refusal or no
// answer at all, the host's and not the symbol's, which leaves it asked for
// its gate to pace; or "unchanged", a chart fetched only to judge a day
// already shown (`judgingOnly`) that brought no quote. `kind` is
// `Fetch.answerKind`'s; `outcome` the reading of an ok answer, { quote },
// null for a bad one, or "missing"; `tries` the bad answers so far.
function answerVerdict(kind, outcome, tries, judgingOnly) {
  if (kind === "refused" || kind === "none") return "host"
  var quote = kind === "ok" && outcome && outcome !== "missing" ? outcome.quote : null
  if (quote) return "show"
  if (judgingOnly) return "unchanged"
  if (kind !== "missing" && outcome !== "missing" && tries < TRIES - 1) return "retry"
  return "fail"
}

// ---- Robinhood

// What Robinhood is asked now, { tradability, prints }, or null for
// nothing. While a surface is open (`open`), for every US stock and ETF
// (`overnightSymbols`): whether it trades all day, once a day each
// (`Overnight.allDayDue`); and the prints of each not known to trade only
// by day, each by its own last ask (`Overnight.overnightDue`), taking with
// it each one due within half a night's interval, so the list stays one
// request a night's 5 minutes. A resting preview on view outside All
// (`previewShown`, `preview`), a US stock or ETF by `previewQuote`, is
// asked with them. With nothing open while a night trades, the pill's
// symbol alone, the same way, so the newest price on top of the pill
// (`Overnight.newestPrint`) stays current. Otherwise, with nothing open,
// for the pill's symbol alone, what Robinhood has not answered for it,
// failed or not, as soon as Yahoo has answered it live: at most once for
// each stock the pill shows. The chart waited on, the preview's or else the
// pill's, goes alone ahead of the rest while it has no answer. `allDay`
// and `nights` are the two feeds' entries; `quoteEntries` Yahoo's.
function overnightAsks(s) {
  var pill = s.pill
  var cal = Overnight.overnightMarket(s.calendars)
  var tonight = cal && !s.open ? Overnight.nightAt(cal, s.now) : null
  var night = !!tonight && tonight.open && s.overnightSymbols.indexOf(pill) >= 0
  // Asked again as each answer falls due, not once a session.
  var kept = s.open || night
  var pillEntry = s.quoteEntries[pill]
  var live = !!pillEntry && pillEntry.status === "ok" && s.overnightSymbols.indexOf(pill) >= 0
  if (!kept && !live) return null
  var previewing = s.open && s.previewShown && !!s.previewQuote && s.library.indexOf(s.preview) < 0
    && Overnight.hasOvernight(s.previewQuote, s.calendars)
  var waited = previewing ? s.preview : pill
  var listings = s.open ? s.overnightSymbols.concat(previewing ? [s.preview] : []) : [pill]
  var tradability = listings.filter(function(x) {
    return kept ? Overnight.allDayDue(s.allDay[x], s.now) : !s.allDay[x]
  })
  var drawn = listings.filter(function(x) { return !s.allDay[x] || s.allDay[x].allDay })
  // The listings of one ask share its second (`entry.at`), so each ask is
  // judged once, not once a listing.
  var judged = {}
  var printsDue = function(x, at) {
    var entry = s.nights[x]
    if (!entry) return true
    if (!kept) return false
    var key = at + " " + entry.at + " " + entry.status
    if (!(key in judged)) judged[key] = Overnight.overnightDue(entry.at, at, s.calendars, entry.status === "failed")
    return judged[key]
  }
  var prints = drawn.filter(function(x) { return printsDue(x, s.now) })
  if (prints.length > 0)
    prints = drawn.filter(function(x) { return printsDue(x, s.now + Overnight.OVERNIGHT_INTERVAL / 2) })
  if (tradability.length === 0 && prints.length === 0) return null
  var alone = function(symbols, answers) {
    return symbols.length > 1 && symbols.indexOf(waited) >= 0 && !answers[waited] ? [waited] : symbols
  }
  return { tradability: alone(tradability, s.allDay), prints: alone(prints, s.nights) }
}

// The prints a user's refresh asks for: those of the charts on show that
// Robinhood trades all day (`allDaySymbols`), unless asked in the last
// `REFRESH_AGAIN` seconds. Rows never draw them, only a chart does.
function refreshPrints(charts, allDaySymbols, askedAt, now) {
  if (now - askedAt <= REFRESH_AGAIN) return []
  return charts.filter(function(s) { return allDaySymbols.indexOf(s) >= 0 })
}

// ---- Charts

// The symbols the open surfaces' heroes chart: the featured symbol on every
// open surface but the one previewing, and a resting preview on view
// (`previewShown`). None with nothing open.
function chartsOnShow(openSurfaces, featured, preview, previewSurface, previewShown) {
  if (openSurfaces.length === 0) return []
  var charts = []
  if (preview === "" || openSurfaces.some(function(s) { return s !== previewSurface }))
    charts.push(featured)
  if (preview !== "" && previewShown && charts.indexOf(preview) < 0)
    charts.push(preview)
  return charts.filter(function(s) { return s !== "" })
}

// Those whose history they show on `range`: none on the day, which needs
// none.
function historyCharts(charts, range) {
  return range === "1D" ? [] : charts
}

// What a user's refresh owes of `charts`' histories: each one's answer at
// the time, null for none, by key. One is owed until a new answer, ok or
// failed, replaces that.
function historyOwing(charts, range, entries) {
  var owing = {}
  charts.forEach(function(s) {
    var key = History.historyKey(s, range)
    owing[key] = entries[key] || null
  })
  return owing
}

// The chart whose history is asked for next, { symbol, force }, or null: one
// a refresh still owes (`owing`), fetched fresh, then one with no answer
// yet, ok or failed.
function nextHistory(charts, range, entries, owing) {
  var key = function(s) { return History.historyKey(s, range) }
  var owed = charts.filter(function(s) { return key(s) in owing && entries[key(s)] === owing[key(s)] })
  if (owed.length > 0) return { symbol: owed[0], force: true }
  var unanswered = charts.filter(function(s) { return !entries[key(s)] })
  return unanswered.length > 0 ? { symbol: unanswered[0], force: false } : null
}

// The first of `charts` whose history in hand has grown old as its market
// moved (`History.historyDue`), a failed refresh too, "" for none. Its quote
// is from `quotes` or else `previewQuotes`.
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

// The rows in sight whose charts are fetched ahead of a click on `range`:
// each open surface's (`sights`, { surface, symbols }, in the order they
// opened), top first, but the heroes' (`heroes`), only as many as the
// cache keeps (`keep`) beside the heroes' charts. None with nothing open or
// on the day.
function aheadRows(open, range, heroes, sights, keep) {
  if (!open || range === "1D") return []
  var rows = []
  sights.forEach(function(sight) {
    sight.symbols.forEach(function(s) { if (rows.indexOf(s) < 0 && heroes.indexOf(s) < 0) rows.push(s) })
  })
  return rows.slice(0, keep - heroes.length)
}

// Of `rows`, those whose chart on `range` has no answer yet, nor has missed
// one ahead (`missed`, by key).
function aheadCharts(rows, range, entries, missed) {
  return rows.filter(function(s) {
    var key = History.historyKey(s, range)
    return !entries[key] && !missed[key]
  })
}

// ---- Cap and P/E

// The caps and P/Es the heroes on show need (`heroes`,
// `Service.heroesOnShow`), in their order, each { symbol, currency }: an
// equity's (`Fundamentals.hasFundamentals`), once its quote is in, from
// `quotes` or else `previewQuotes`. One without its quote yet joins when it
// lands.
function figuresWanted(heroes, quotes, previewQuotes) {
  var wanted = []
  heroes.forEach(function(s) {
    var quote = quotes[s] || previewQuotes[s]
    if (!quote || !Fundamentals.hasFundamentals(quote)) return
    if (wanted.some(function(w) { return w.symbol === s })) return
    wanted.push({ symbol: s, currency: String(quote.currency || "") })
  })
  return wanted
}

// ---- The clock

// The milliseconds from `nowMs`, the wall clock, to just past the start of
// the clock's next step: the next second while a surface is open (`open`),
// the next minute while none is, or an earlier one of `deadlines` still
// ahead of `now`, the service's second: the next quote due, a host's pause
// ending. One the wall clock has passed already is at once.
function clockWait(open, nowMs, now, deadlines) {
  var wall = Math.floor(nowMs / 1000)
  var next = open ? wall + 1 : (Math.floor(wall / 60) + 1) * 60
  deadlines.forEach(function(at) { if (at > now && at < next) next = at })
  return Math.max(0, (next - wall - 1) * 1000 + 1000 - nowMs % 1000) + 5
}
