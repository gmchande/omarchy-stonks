.pragma library
.import "Format.js" as Format

// Yahoo's chart and spark answers, and the day's prices read off them.
// Knows no calendar, no Robinhood, and nothing of how a figure is shown.

var CHART_URL = "https://query1.finance.yahoo.com/v8/finance/chart/"
// Spark sends `meta` and closes, no opens; 21 symbols a request get HTTP 400.
var SPARK_URL = "https://query1.finance.yahoo.com/v7/finance/spark"
var SPARK_BATCH = 20

// Past these, an answer is bad (`Format.fetchedList`). The largest real ones:
// ^GSPC's All, about 1,190 monthly bars, and a coin's 1M, 744 hourly bars.
var MOST_BARS = 5000
// A coin's month lists 31 days; every saved answer has one period a day.
var MOST_DAYS = 100
var MOST_PERIODS = 10
// A coin's period lasts 23:59, the longest saved; 25 hours allows a day the
// clocks go back. One spanning centuries would walk billions of five-minute
// slots on the shell's one thread (`Overnight.extendedSlots`).
var LONGEST_PERIOD = 25 * 3600
var MOST_SPARKS = 2 * SPARK_BATCH

// Yahoo's exchange codes to the names people use. A listing without one
// shows Yahoo's full exchange name; a search result, the code.
var EXCHANGE_NAMES = {
  NMS: "NASDAQ", NGM: "NASDAQ", NCM: "NASDAQ", NAS: "NASDAQ", NYQ: "NYSE", PCX: "NYSE ARCA",
  ASE: "NYSE AMERICAN", BTS: "CBOE", TOR: "TSX", VAN: "TSXV", NEO: "NEO", CNQ: "CSE", LSE: "LSE",
  IOB: "LSE", TYO: "TSE", JPX: "TSE", FRA: "FRA", GER: "XETRA", PAR: "PARIS", AMS: "AMSTERDAM",
  HKG: "HKEX", ASX: "ASX", NZE: "NZX", SES: "SGX", BSE: "BSE", NSI: "NSE", CCC: "CRYPTO", CCY: "FX",
  SNP: "S&P", DJI: "DOW", NIM: "NASDAQ", PNK: "OTC", OQB: "OTC", OQX: "OTC", OEM: "OTC", JNB: "JSE"
}

// The length of the bars Stonks asks for, in seconds.
var BAR = 5 * 60

// Two days once Yahoo's day has turned to the coming one, so the last
// session is still in the answer (`Asks.twoDays`).
function chartUrl(symbol, twoDays) {
  return CHART_URL + encodeURIComponent(symbol) + "?range=" + (twoDays ? "2d" : "1d") + "&interval=" + BAR / 60 + "m&includePrePost=true"
}

function sparkUrl(symbols, twoDays) {
  return SPARK_URL + "?symbols=" + symbols.map(encodeURIComponent).join(",") + "&range=" + (twoDays ? "2d" : "1d") + "&interval=" + BAR / 60 + "m&includePrePost=true"
}

// Yahoo leaves out a symbol it doesn't know.
function sparkResults(json) {
  var out = {}
  var sent = json && json.spark && json.spark.result
  var results = sent ? Format.fetchedList(sent, MOST_SPARKS) : []
  if (!results) return null
  for (var i = 0; i < results.length; i++) {
    var day = results[i].response && results[i].response[0]
    var symbol = Format.fetchedText(results[i].symbol, Format.MOST_CODE)
    if (day && day.meta && symbol) out[symbol] = day
  }
  return out
}

// Spark has no opens, so the stray filter can't judge it: the last chart
// answer's verdict stands in for its strays and its open. `unjudged` when
// spark shows what that verdict didn't see: a jump past its settled bars once
// a new bar is whole, a bar changed or filled in, or the session opened since.
// Only a chart answer can say whether that is a stray, or what the open was.
function sparkQuote(day, verdict, centExchanges, receivedAt) {
  var quote = parseChart({ chart: { result: [day] } }, centExchanges, receivedAt)
  if (!quote) return null
  var pts = quote.points
  var tick = answerTick(day.meta, pts.map(function(p) { return { c: p.p } }), centExchanges)
  var newBar = !verdict || (pts.length >= 2 && pts[pts.length - 2].t > verdict.newest)
  var unjudged = false
  for (var i = 1; newBar && !unjudged && i < pts.length - 1; i++)
    unjudged = pts[i].t > (verdict ? verdict.settled : 0) && !sameLevel(pts[i].p, pts[i - 1].p, tick)
  for (var j = 0, k = 0; verdict && !unjudged && j < pts.length && pts[j].t <= verdict.newest; j++) {
    while (k < verdict.times.length && verdict.times[k] < pts[j].t) k++
    unjudged = verdict.times[k] !== pts[j].t || !sameClose(pts[j].p, verdict.closes[k])
  }
  if (quote.openSession !== null) {
    if (verdict && verdict.openSession === quote.openSession) quote.dayOpen = verdict.open
    else unjudged = true
  }
  var dropped = verdict ? verdict.dropped : []
  quote.points = pts.filter(function(p) { return dropped.indexOf(p.t) < 0 })
  quote.droppedTimes = pts.filter(function(p) { return dropped.indexOf(p.t) >= 0 }).map(function(p) { return p.t })
  quote.verdict = verdict
  quote.closesOnly = true
  return { quote: quote, unjudged: unjudged }
}

// Spark rounds a price of 1 or more to three decimals (PLUG's 1.3786 as
// 1.379) and sends a smaller one as the chart does.
function sameClose(spark, chart) {
  return Math.abs(spark - chart) <= (Math.abs(chart) >= 1 ? 0.0005 : 0) + Math.abs(chart) * 1e-6
}

function apart(a, b) {
  var scale = Math.max(Math.abs(a), Math.abs(b))
  return scale > 0 ? Math.abs(a - b) / scale : 0
}

var STRAY_GAP = 0.005

// Under $2 one cent is more than STRAY_GAP, and PLUG's one-cent bounces
// are trades.
var STRAY_TICKS = 2

// The half tick absorbs Yahoo's float noise (1.9800000190734863 against
// 1.9700000286102295).
function sameLevel(a, b, tick) {
  return apart(a, b) <= STRAY_GAP || (tick > 0 && Math.abs(a - b) < (STRAY_TICKS + 0.5) * tick)
}

// Yahoo has sent at most two strays in a row.
var STRAY_RUN = 3

// Yahoo has mixed in at most four strays in one run.
var MIXED_RUN = 4

// Yahoo drops stray trades into intraday buckets, such as a bell bucket
// back at yesterday's close. A stray shows by the series carrying on as if it
// never happened, not by its size: one saved stray is 0.8%. A move within two
// ticks, or a bar with shares traded, is a trade: no saved stray traded any,
// and a thin listing's real trades often open back where they began.
function filterStrayCloses(bars, periods, tick) {
  var source = bars || []
  if (source.length < 3) return { bars: source.slice(), droppedTimes: [] }
  var kept = [bars[0]]
  var droppedTimes = []
  var level = 0
  var i = 1
  while (i < bars.length) {
    var run = strayRun(bars, level, i, tick, periods) || mixedRun(bars, level, i, periods, tick)
    if (run > 0) {
      for (var dropped = 0; dropped < run; dropped++) droppedTimes.push(bars[i + dropped].t)
      i += run
      continue
    }
    kept.push(bars[i])
    level = i
    i++
  }
  return { bars: kept, droppedTimes: droppedTimes }
}

// How many bars from `from` never happened: their closes leave the accepted
// price and the next bar opens back at it, where a real move opens from its
// own close. The newest bar is never judged, and neither is a run across a
// session break or a night, where prices really move. Yahoo can leave out a
// bucket between two strays, so a gap inside a session doesn't end the run.
function strayRun(bars, level, from, tick, periods) {
  var price = bars[level].c
  var step = bars[level + 1].t - bars[level].t
  var session = sessionAt(periods, bars[level].t)
  for (var length = 1; length <= STRAY_RUN; length++) {
    var end = from + length - 1
    var back = end + 1 < bars.length ? bars[end + 1] : null
    if (!back || !Format.isFiniteNumber(back.o) || traded(bars[end]) || sameLevel(bars[end].c, price, tick)) return 0
    var opensBack = sameLevel(back.o, price, tick) && !sameLevel(back.o, bars[end].c, tick)
    if (back.t - bars[end].t !== step) {
      if (opensBack && session && sessionAt(periods, back.t) === session) continue
      return 0
    }
    if (opensBack) return length
  }
  return 0
}

// Yahoo also mixes strays into a quiet extended session: three or four bars,
// none opening where the last closed, closing both above and below the price,
// then a bar opening back at it, whatever the gaps. A thin listing's own
// trades take that shape two bars at a time, never three in the saved answers.
function mixedRun(bars, level, from, periods, tick) {
  var price = bars[level].c
  var session = extendedSession(periods, bars[level].t)
  if (!session) return 0
  var above = false
  var below = false
  for (var end = from; end < from + MIXED_RUN && end + 1 < bars.length; end++) {
    var bar = bars[end]
    var back = bars[end + 1]
    if (traded(bar) || (end > from && sameLevel(bar.o, bars[end - 1].c, tick))) return 0
    if (extendedSession(periods, back.t) !== session) return 0
    if (!sameLevel(bar.c, price, tick)) {
      if (bar.c > price) above = true
      else below = true
    }
    if (end - from >= 2 && above && below && Format.isFiniteNumber(back.o)
        && sameLevel(back.o, price, tick) && !sameLevel(back.o, bar.c, tick)) return end - from + 1
  }
  return 0
}

// Yahoo sends no volume for a stray, nor, in the saved answers, for pre-
// and post-market bars.
function traded(bar) {
  return Format.isFiniteNumber(bar.v) && bar.v > 0
}

function sessionAt(periods, t) {
  var names = ["pre", "regular", "post"]
  for (var n = 0; periods && n < names.length; n++) {
    var period = periods[names[n]]
    if (period && t >= period.start && t < period.end) return names[n]
  }
  return ""
}

function extendedSession(periods, t) {
  var session = sessionAt(periods, t)
  return session === "regular" ? "" : session
}

function exchangeOf(meta) {
  var code = Format.fetchedText(meta.exchangeName, Format.MOST_CODE)
  return EXCHANGE_NAMES[code] || (Format.fetchedText(meta.fullExchangeName, Format.MOST_NAME) || code).toUpperCase()
}

// `centExchanges`: the exchanges that trade in whole cents from $1
// (`Calendar.centExchanges`).
function inCents(meta, centExchanges) {
  return !!centExchanges && centExchanges.indexOf(exchangeOf(meta)) >= 0
}

function answerTick(meta, bars, centExchanges) {
  var price = knownPrice(meta.regularMarketPrice) !== null ? meta.regularMarketPrice
    : (bars.length ? bars[bars.length - 1].c : null)
  return Format.priceTick(price, meta.priceHint, inCents(meta, centExchanges))
}

// Null for a malformed answer. Yahoo never sends bars out of time order,
// and one would land off the chart's grid. `receivedAt` is when it came.
function parseChart(json, centExchanges, receivedAt) {
  var result = json && json.chart && json.chart.result && json.chart.result[0]
  if (!result || !result.meta) return null
  var meta = result.meta
  var timestamps = Format.fetchedList(result.timestamp || [], MOST_BARS)
  var quote = (result.indicators && result.indicators.quote && result.indicators.quote[0]) || {}
  var closes = Format.fetchedList(quote.close || [], MOST_BARS)
  var opens = Format.fetchedList(quote.open || [], MOST_BARS)
  // Spark sends no volume, high or low.
  var volumes = quote.volume ? Format.fetchedList(quote.volume, MOST_BARS) : null
  var highs = quote.high ? Format.fetchedList(quote.high, MOST_BARS) : null
  var lows = quote.low ? Format.fetchedList(quote.low, MOST_BARS) : null
  var clocks = answerClocks(meta.tradingPeriods)
  var current = meta.currentTradingPeriod || {}
  if (!timestamps || !closes || !opens || !clocks || !currentPeriods(current)) return null
  // Yahoo's current period moves to the next session before the bars do
  // (Monday's at 00:36, the bars still Friday's), so the trading periods name
  // the bars' session. A two-day answer is read as the headline's day: earlier
  // days' bars go, and the coming day's pre-market stays as its tail. A coin's
  // answer is read whole (`coinDay`).
  var quoted = Format.isFiniteNumber(meta.regularMarketTime) && meta.regularMarketTime > 0 ? meta.regularMarketTime : null
  var coin = meta.instrumentType === "CRYPTOCURRENCY"
  var days = meta.tradingPeriods ? answerDays(meta.tradingPeriods) : [current]
  var chosen = headlineDay(days, quoted, timestamps, closes)
  var periods = days[chosen]
  var next = !coin && chosen + 1 < days.length ? days[chosen + 1] : null
  var from = !coin && chosen > 0 ? periodsStart(periods) : null
  var bars = answerBars(timestamps, { o: opens, c: closes, v: volumes, h: highs, l: lows }, from)
  if (!bars) return null
  var filtered = filterStrayCloses(bars, periods, answerTick(meta, bars, centExchanges))
  var kept = filtered.bars
  var regular = periodOf(periods.regular)
  var index = meta.instrumentType === "INDEX"
  var points = dayPoints(kept, next, regular, index)
  // Before a session, Yahoo already sends the coming day's high and low, as 0
  // in London's case: the figures are then that day's, and the bars' open
  // isn't.
  var ahead = !knownPrice(meta.regularMarketDayHigh) && !knownPrice(meta.regularMarketDayLow) && !!current.regular
  var firstRegular = regular && !ahead ? firstRegularBar(kept, regular) : null
  var symbol = Format.fetchedText(meta.symbol, Format.MOST_CODE)
  var instrumentType = Format.fetchedText(meta.instrumentType, Format.MOST_CODE)
  var out = {
    symbol: symbol,
    // Yahoo's short name comes in capitals for some listings, cut at 31.
    name: Format.fetchedText(meta.longName, Format.MOST_NAME) || Format.fetchedText(meta.shortName, Format.MOST_NAME) || symbol,
    // Yahoo can name no currency, as ^STOXX50E's answer did.
    currency: Format.fetchedText(meta.currency, Format.MOST_CODE),
    exchange: exchangeOf(meta),
    timezoneName: Format.fetchedText(meta.exchangeTimezoneName, Format.MOST_CODE),
    gmtoffset: isOffset(meta.gmtoffset) ? meta.gmtoffset : 0,
    // "EDT", "JST": the zone's short name at that offset.
    zoneName: Format.fetchedText(meta.timezone, Format.MOST_CODE),
    clocks: clocks,
    instrumentType: instrumentType,
    crypto: instrumentType === "CRYPTOCURRENCY",
    price: knownPrice(meta.regularMarketPrice),
    priceDigits: Format.priceDigits(knownPrice(meta.regularMarketPrice) !== null ? meta.regularMarketPrice
      : (points.length ? points[points.length - 1].p : null), meta.priceHint, inCents(meta, centExchanges)),
    prevClose: answerPrevClose(meta, days, chosen, quoted, regular),
    marketTime: Format.isMoment(meta.regularMarketTime) && meta.regularMarketTime > 0 ? meta.regularMarketTime : null,
    dayOpen: firstRegular ? knownPrice(firstRegular.o) : null,
    // The session `dayOpen` opened.
    openSession: firstRegular ? regular.start : null,
    dayHigh: knownPrice(meta.regularMarketDayHigh),
    dayLow: knownPrice(meta.regularMarketDayLow),
    volume: meta.regularMarketVolume,
    fiftyTwoWeekHigh: knownPrice(meta.fiftyTwoWeekHigh),
    fiftyTwoWeekLow: knownPrice(meta.fiftyTwoWeekLow),
    // The session the day's open, high, low and volume belong to.
    figuresDay: figuresDayOf(ahead, current, regular, quoted),
    nextDayBegun: nextDayHasBegun(index, next, regular, current, receivedAt),
    // Its trades are all the day will have, so the chart ends at the last
    // (`Day.tradedAxis`).
    wholeDay: !!regular && Format.isFiniteNumber(receivedAt) && receivedAt >= (periods.post || periods.regular).end,
    session: {
      pre: index ? null : periodOf(periods.pre),
      regular: regular,
      post: index ? null : periodOf(periods.post)
    },
    current: {
      pre: index ? null : periodOf(current.pre),
      regular: periodOf(current.regular),
      post: index ? null : periodOf(current.post)
    },
    next: next && !index ? { pre: periodOf(next.pre), regular: periodOf(next.regular), post: periodOf(next.post) } : null,
    points: points,
    droppedTimes: filtered.droppedTimes,
    verdict: chartVerdict(bars, opens, filtered, firstRegular, regular)
  }
  var rolled = coin ? coinDay(points, kept) : null
  return rolled ? Object.assign(out, rolled) : out
}

// Which of an answer's days is the headline's: the last whose session has
// begun by the quote's time, or without one, by a bar in it.
function headlineDay(days, quoted, timestamps, closes) {
  var chosen = 0
  for (var d = 1; d < days.length; d++) {
    var regular = days[d].regular
    if (!regular) continue
    var since = quoted !== null ? quoted : barIn(timestamps, closes, regular)
    if (since !== null && regular.start <= since) chosen = d
  }
  return chosen
}

// The bars from `from` on that have a close; null if a time is malformed or
// out of order. `series` holds the answer's opens, closes, volumes, highs and
// lows by the bar's own names, the last three null in a spark answer.
function answerBars(timestamps, series, from) {
  var bars = []
  for (var i = 0; i < timestamps.length; i++) {
    if (!Format.isMoment(timestamps[i]) || (i > 0 && !(timestamps[i] > timestamps[i - 1]))) return null
    if (knownPrice(series.c[i]) === null) continue
    if (from !== null && timestamps[i] < from) continue
    bars.push({
      t: timestamps[i],
      o: series.o[i],
      c: series.c[i],
      v: series.v ? series.v[i] : null,
      h: series.h ? series.h[i] : null,
      l: series.l ? series.l[i] : null
    })
  }
  return bars
}

// The headline day's trades, and the coming day's pre-market as its tail,
// each tail trade named by its session. Yahoo gives an index pre- and
// post-market periods and repeats its close through the evening, but an
// index is worked out only while its exchange trades.
function dayPoints(kept, next, regular, index) {
  var tailFrom = next ? periodsStart(next) : null
  var points = []
  for (var j = 0; j < kept.length; j++) {
    var bar = kept[j]
    if (tailFrom !== null && bar.t >= tailFrom) {
      if (!index) points.push({ t: bar.t, p: bar.c, s: POINT_SESSIONS[sessionAt(next, bar.t)] || "pre" })
    } else if (!index || !regular || (bar.t >= regular.start && bar.t < regular.end)) {
      points.push({ t: bar.t, p: bar.c })
    }
  }
  return points
}

// Yahoo's bars sit on the five-minute grid from the bell. Off it, at the
// quote's time, is Yahoo's echo of its price: one price, no shares. Its open
// is that price, not the day's: at Tokyo's open on 4 November, 09:00:03's
// held Monday's close, 3,051, with the day already traded 3,030 to 3,040.
// So the day's open waits for Yahoo's first bar of the day.
function firstRegularBar(kept, regular) {
  for (var k = 0; k < kept.length; k++) {
    var t = kept[k].t
    if (t >= regular.start && t < regular.end && (t - regular.start) % BAR === 0) return kept[k]
  }
  return null
}

// Yahoo's previous close is the close before the day it counts as current,
// its chart previous close the one before the answer's first day. Tokyo's
// two-day answer before Monday's first bar holds Friday alone, with Friday's
// own close as its previous close. A one-day answer's quote can be an older
// day's, for a listing that hasn't traded.
function answerPrevClose(meta, days, chosen, quoted, regular) {
  var oneDay = days.length === 1 && meta.range !== "2d"
  var beforeHeadline = chosen === 0 && (quoted === null || !regular || quoted < regular.start)
  if (meta.chartPreviousClose !== undefined && (oneDay || beforeHeadline)) return knownPrice(meta.chartPreviousClose)
  return knownPrice(meta.previousClose)
}

// The session the day's figures belong to: the coming day's once Yahoo sends
// its high and low (`ahead`). An untraded listing's figures and quote stay
// its last trading day's.
function figuresDayOf(ahead, current, regular, quoted) {
  if (ahead) return current.regular.start
  if (!regular) return null
  if (quoted !== null && quoted < regular.start) return quoted
  return regular.start
}

// A stock's next day has begun once Yahoo sends it, from its pre-market on.
// An index's bars stay the last session's until its open, so its next day
// begins with the pre-market, else the open, of Yahoo's later current period.
function nextDayHasBegun(index, next, regular, current, receivedAt) {
  if (!index) return !!next
  if (!regular || !current.regular || current.regular.start <= regular.start) return false
  var nextDay = current.pre || current.regular
  return Format.isFiniteNumber(receivedAt) && receivedAt >= nextDay.start
}

// For a later spark answer (`sparkQuote`). Null without opens, when the
// filter judged nothing. A stray run reaches at most MIXED_RUN bars on, so no
// later bar can change the verdict before that. The newest bar is the live
// moment.
function chartVerdict(bars, opens, filtered, firstRegular, regular) {
  if (!opens.length) return null
  var whole = bars.slice(0, Math.max(0, bars.length - 1))
  var settled = bars.slice(0, Math.max(0, bars.length - MIXED_RUN))
  return {
    newest: whole.length ? whole[whole.length - 1].t : 0,
    settled: settled.length ? settled[settled.length - 1].t : 0,
    times: whole.map(function(b) { return b.t }),
    closes: whole.map(function(b) { return b.c }),
    dropped: filtered.droppedTimes,
    open: firstRegular ? knownPrice(firstRegular.o) : null,
    openSession: firstRegular ? regular.start : null
  }
}

// A coin never closes, so its day is its last 24 hours, from the trade 24
// hours before the newest: the move, the chart and the figures all read them.
// Its low and high come from its bars, which a close can miss, with the bar
// each came from (`dayHighAt`, `dayLowAt`): the 24 hours cross midnight.
// Yahoo's `regularMarketVolume` already covers 24 hours for a coin. Null for
// an answer that doesn't reach back that far, whose quote stays Yahoo's UTC
// day.
function coinDay(points, bars) {
  var newest = points.length ? points[points.length - 1] : null
  var first = 0
  while (newest && first + 1 < points.length && points[first + 1].t <= newest.t - 86400) first++
  if (!newest || points[first].t > newest.t - 86400) return null
  var day = points.slice(first)
  var since = bars.filter(function(b) { return b.t > day[0].t })
  var ranged = since.length > 0 && since.every(function(b) { return knownPrice(b.h) !== null && knownPrice(b.l) !== null })
  var reach = since.concat([{ t: day[0].t, h: day[0].p, l: day[0].p }])
  var high = ranged ? reach.reduce(function(a, b) { return b.h > a.h ? b : a }) : null
  var low = ranged ? reach.reduce(function(a, b) { return b.l < a.l ? b : a }) : null
  return {
    rolling: true,
    points: day,
    prevClose: day[0].p,
    dayOpen: day[0].p,
    openSession: null,
    dayHigh: high ? high.h : null,
    dayLow: low ? low.l : null,
    dayHighAt: high ? high.t : null,
    dayLowAt: low ? low.t : null,
    figuresDay: day[0].t,
    nextDayBegun: false,
    session: { pre: null, regular: { start: day[0].t, end: newest.t }, post: null }
  }
}

// Compared as values, never written out as text, which for a long list's
// landing would take longer than the rest of it. Yahoo revises mid-day bars.
function sameQuote(a, b) {
  var pa = a.points || []
  var pb = b.points || []
  if (pa.length !== pb.length) return false
  for (var i = 0; i < pa.length; i++) if (pa[i].t !== pb[i].t || pa[i].p !== pb[i].p) return false
  return sameRecord(a, b, "points")
}

function sameValue(a, b) {
  if (a === b) return true
  if (!a || !b || typeof a !== "object" || typeof b !== "object") return false
  var list = Array.isArray(a)
  if (list !== Array.isArray(b)) return false
  if (!list) return sameRecord(a, b, "")
  if (a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) if (a[i] !== b[i] && !sameValue(a[i], b[i])) return false
  return true
}

// A key left unset matches a missing one, as in a saved quote read back.
function sameRecord(a, b, skip) {
  var keys = Object.keys(a)
  for (var i = 0; i < keys.length; i++) if (keys[i] !== skip && !sameValue(a[keys[i]], b[keys[i]])) return false
  keys = Object.keys(b)
  for (var j = 0; j < keys.length; j++) if (keys[j] !== skip && b[keys[j]] !== undefined && !(keys[j] in a)) return false
  return true
}

function periodOf(period) {
  return period ? { start: period.start, end: period.end } : null
}

var POINT_SESSIONS = { pre: "pre", regular: "reg", post: "post" }

function periodsStart(periods) {
  return periods.pre ? periods.pre.start : periods.regular ? periods.regular.start : null
}

function barIn(timestamps, closes, period) {
  for (var i = 0; period && i < timestamps.length; i++)
    if (timestamps[i] >= period.start && timestamps[i] < period.end && knownPrice(closes[i]) !== null) return timestamps[i]
  return null
}

// Yahoo sends a non-US listing's day, and an index's at night, in a range's
// shape: one list of days, each a regular session.
function answerDays(periods) {
  var names = ["pre", "regular", "post"]
  var lists = {}
  var count = 1
  for (var i = 0; i < names.length; i++) {
    var list = Array.isArray(periods) ? (names[i] === "regular" ? periods : []) : periods[names[i]]
    lists[names[i]] = Format.fetchedList(list || [], MOST_DAYS) || []
    count = Math.max(count, lists[names[i]].length)
  }
  var out = []
  for (var d = 0; d < count; d++) {
    var day = {}
    for (var n = 0; n < names.length; n++) {
      var days = lists[names[n]]
      var listed = Format.fetchedList(days[days.length - count + d] || [], MOST_PERIODS) || []
      day[names[n]] = listed.length ? { start: listed[0].start, end: listed[listed.length - 1].end } : null
    }
    out.push(day)
  }
  return out
}

// Each period keeps its own offset until its day's midnight, so a close
// stamped after the period's end, as IAG.MC's at 17:35:26 is, reads its day.
// `meta.gmtoffset` is the clock when Yahoo sent the answer, so after a change
// of clocks an older period still says its own.
function answerClocks(periods) {
  var lists = !periods ? [] : Array.isArray(periods) ? [periods] : [periods.pre, periods.regular, periods.post]
  var out = []
  for (var i = 0; i < lists.length; i++) {
    var days = Format.fetchedList(lists[i] || [], MOST_DAYS)
    if (!days) return null
    for (var j = 0; j < days.length; j++) {
      var day = Format.fetchedList(days[j] || [], MOST_PERIODS)
      if (!day) return null
      for (var k = 0; k < day.length; k++) {
        var p = day[k]
        if (!isPeriod(p) || !isOffset(p.gmtoffset)) return null
        var midnight = (Math.floor((p.start + p.gmtoffset) / 86400) + 1) * 86400 - p.gmtoffset
        out.push({ start: p.start, until: midnight, offset: p.gmtoffset, zone: Format.fetchedText(p.timezone, Format.MOST_CODE) })
      }
      // `answerDays` reads a day from its first period's start to its last's end.
      if (day.length && !isPeriod({ start: day[0].start, end: day[day.length - 1].end })) return null
    }
  }
  return out
}

// A period whose end is {"toString": null} would throw on every comparison,
// and no row would be asked for again until Stonks restarts.
function isPeriod(p) {
  return !!p && typeof p === "object" && Format.isMoment(p.start) && Format.isMoment(p.end) && p.end - p.start <= LONGEST_PERIOD
}

// Their offsets are never read, so only the periods are checked.
function currentPeriods(current) {
  var names = ["pre", "regular", "post"]
  for (var i = 0; i < names.length; i++) if (current[names[i]] && !isPeriod(current[names[i]])) return false
  return true
}

// The cache's quotes, { symbol: { quote, receivedAt } }, as this or an
// earlier Stonks saved them. Before 1.1.1 a period could span centuries, and
// `Overnight.extendedSlots` walks the pre- and post-markets slot by slot.
function keptQuotes(saved) {
  var out = {}
  for (var symbol in saved) {
    var quote = saved[symbol] && saved[symbol].quote
    var days = quote && quote.session ? [quote.session, quote.next] : []
    if (days.length && days.every(function(day) { return !day || ((!day.pre || isPeriod(day.pre)) && (!day.post || isPeriod(day.post))) }))
      out[symbol] = saved[symbol]
  }
  return out
}

function isOffset(v) {
  return Format.isFiniteNumber(v) && Math.abs(v) < 86400
}

// `answer` is a quote or a history.
function clockAt(answer, t) {
  var clocks = answer.clocks || []
  for (var i = 0; i < clocks.length; i++) {
    if (t >= clocks[i].start && t < clocks[i].until) return clocks[i]
  }
  return { offset: answer.gmtoffset || 0, zone: answer.zoneName || "" }
}

// Yahoo sends 0 for a price it doesn't know yet, such as London's day high
// before its open, and can send a negative.
function knownPrice(v) {
  return Format.isFiniteNumber(v) && v > 0 ? v : null
}

// Buckets are stamped by their start, so the one at the bell is post-market.
function regularPoints(quote) {
  var reg = quote.session.regular
  if (!reg) return quote.points
  var out = []
  for (var i = 0; i < quote.points.length; i++) {
    var pt = quote.points[i]
    if (pt.t >= reg.start && pt.t < reg.end) out.push(pt)
  }
  return out
}

// Yahoo's regular-market quote, the latest regular trade or the close, can
// be stamped after the bell or belong to the previous session.
function headlineQuote(quote) {
  if (Format.isFiniteNumber(quote.price)) {
    return { price: quote.price, t: Format.isFiniteNumber(quote.marketTime) ? quote.marketTime : null, source: "quote" }
  }
  var pts = regularPoints(quote)
  if (pts.length) return { price: pts[pts.length - 1].p, t: pts[pts.length - 1].t, source: "chart" }
  return null
}

function regularClose(quote) {
  var head = headlineQuote(quote)
  return head ? head.price : null
}

// Before the session opens, Yahoo's quote is still the last close and its
// previous close the one before, so the day is measured from the quote: else
// the pre-market's change would disagree with the line under the price.
function dayBase(quote) {
  var reg = quote.session.regular
  var head = headlineQuote(quote)
  return reg && head && head.source === "quote" && head.t !== null && head.t < reg.start ? head.price : quote.prevClose
}

function headlineBase(quote) {
  return { prevClose: quote.prevClose, dayOpen: quote.nextDayBegun ? null : quote.dayOpen }
}

// Every place a price shows at rest reads this, so none disagree: the newest
// trade since the close (`Overnight.newestTrade`), else the headline.
function restingRead(quote, newest) {
  if (newest)
    return { price: newest.p, t: newest.t, base: { prevClose: newest.base, dayOpen: newest.own ? headlineBase(quote).dayOpen : null } }
  var head = headlineQuote(quote)
  return { price: head ? head.price : null, t: head ? head.t : null, base: headlineBase(quote) }
}

function extendedTrade(quote, latest) {
  var pts = quote.points
  var last = latest || pts[pts.length - 1]
  if (!quote.session.regular || !last) return null
  var phase = pointSession(quote, last)
  return phase === "reg" ? null : { t: last.t, p: last.p, phase: phase }
}

// Once Yahoo's quote is the close, the session's last trade reads it at the
// bell: the S&P 500's last bar is 15:55's, not its close. Not at the quote's
// own stamp, which can come later: London's 16:30 close has come stamped
// 17:20, after its after-hours buckets.
function readingAt(quote, t) {
  var pts = quote.points
  if (!pts.length || t < pts[0].t) return { price: dayBase(quote), t: t, close: false }
  // Search by halves: walking from the first trade would cost every row a
  // step per trade on each scrub step.
  var k = 0
  var top = pts.length - 1
  while (k < top) {
    var mid = (k + top + 1) >> 1
    if (pts[mid].t <= t) k = mid
    else top = mid - 1
  }
  var head = headlineQuote(quote)
  var reg = quote.session.regular
  if (!quote.crypto && head && head.source === "quote" && reg && head.t >= reg.end
      && pointSession(quote, pts[k]) === "reg" && (k + 1 === pts.length || pointSession(quote, pts[k + 1]) !== "reg"))
    return { price: head.price, t: reg.end, close: true }
  return { price: pts[k].p, t: t, close: false }
}

// `digits`, the price's, makes the move the price shown less the close or
// open shown, so the two add up to the price on top. Each rounding its own
// half-cent away from zero, 348.22 and −0.50 sat under 347.73 (Yahoo's
// 347.725). A price shown with fewer digits than the move, whole from
// 10,000, can't add up, so its move is the difference itself. The percent
// is always the difference's.
function change(quote, priceNow, mode, digits) {
  var base = mode === "open" ? quote.dayOpen : quote.prevClose
  if (!Format.isFiniteNumber(priceNow) || !Format.isFiniteNumber(base)) return { abs: null, pct: null, up: true }
  var abs = priceNow - base
  var shown = Format.isFiniteNumber(digits) && digits >= 2 ? Number(Format.fixed(priceNow, digits)) - Number(Format.fixed(base, digits)) : abs
  return { abs: shown, pct: base ? (abs / base) * 100 : 0, up: abs >= 0 }
}

// The bell's bucket is the session's when it holds the closing trade, and so
// is a trade at the close's price seconds later: Yahoo restating the close.
function pointSession(quote, pt) {
  if (pt.s) return pt.s
  if (quote.crypto) return "reg"
  var reg = regularOrTrades(quote)
  if (pt.t === reg.end && closingTrade(quote, pt)) return "reg"
  if (pt.t > reg.end && pt.t < reg.end + 60 && !!quote.session.regular && closingTrade(quote, { t: reg.end, p: pt.p })) return "reg"
  return pt.t >= reg.end ? "post" : pt.t < reg.start ? "pre" : "reg"
}

// Yahoo stamps its regular price inside the bell's bucket when that bucket
// holds the close. London stamps its close an hour on (`readingAt`).
function closingTrade(quote, pt) {
  var t = quote.marketTime
  return !!quote.session.regular && Format.isFiniteNumber(quote.price) && t !== null && t >= pt.t && t < pt.t + 300
    && sameClose(pt.p, quote.price)
}

// Yahoo can send no regular session.
function regularOrTrades(quote) {
  var pts = quote.points
  return quote.session.regular || { start: pts[0] ? pts[0].t : 0, end: pts.length ? pts[pts.length - 1].t : 1 }
}

function lastTradeTime(quote) {
  var pts = quote.points
  return pts.length ? pts[pts.length - 1].t : null
}

function dayStart(quote) {
  var s = quote.session
  return s.pre ? s.pre.start : s.regular ? s.regular.start : 0
}

function dayEnd(quote) {
  var s = quote.session
  return s.post ? s.post.end : s.regular ? s.regular.end : 0
}

function tailStart(quote) {
  return quote.next ? periodsStart(quote.next) : null
}

function tailDay(quote) {
  var from = tailStart(quote)
  var pts = quote.points
  if (from === null || !pts.length || pts[pts.length - 1].t < from) return null
  return Object.assign({}, quote, {
    session: quote.next,
    next: null,
    points: pts.filter(function(p) { return p.t >= from }),
    prevClose: regularClose(quote),
    dayOpen: null,
    openSession: null,
    wholeDay: false
  })
}

function bucketTimes(times) {
  var out = []
  for (var i = 0; times && i < times.length; i++) out.push(new Date(times[i] * 1000).toISOString())
  return out.join(", ")
}
