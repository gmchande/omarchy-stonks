.pragma library
.import "Format.js" as Format

// Yahoo's day answer for a listing, and the day's prices read off it: the
// session its bars describe, the headline, the change, and each print's
// session. If the chart or spark endpoint changes, its URL and parser move
// here. Knows no calendar, no Robinhood, and nothing of how a figure is
// shown.

var CHART_URL = "https://query1.finance.yahoo.com/v8/finance/chart/"
// Yahoo's spark: the chart's whole `meta` and its closes, for up to
// SPARK_BATCH listings a request (21 gets HTTP 400). No opens.
var SPARK_URL = "https://query1.finance.yahoo.com/v7/finance/spark"
var SPARK_BATCH = 20

// The most entries a list in a chart or spark answer may hold, past which
// the answer is a bad one (`Format.fetchedList`), each well over a real
// answer's. Bars: 501 in the saved answers (NVDA's 2Y of days); ^GSPC's All,
// a month a bar since 1927, comes to about 1,190, and a coin's 1M, an hour
// a bar, to 744.
var MOST_BARS = 5000
// Trading periods: a list of days, 23 in the saved answers (a month of
// hours), 31 for a coin's month; one period a day in every saved answer.
var MOST_DAYS = 100
var MOST_PERIODS = 10
// A spark answer's listings: one for each symbol asked, SPARK_BATCH at most.
var MOST_SPARKS = 2 * SPARK_BATCH

// Yahoo's short exchange codes to the names people use. A listing falls back
// to Yahoo's full exchange name; a search result to Yahoo's own short code.
var EXCHANGE_NAMES = {
  NMS: "NASDAQ", NGM: "NASDAQ", NCM: "NASDAQ", NAS: "NASDAQ", NYQ: "NYSE", PCX: "NYSE ARCA",
  ASE: "NYSE AMERICAN", BTS: "CBOE", TOR: "TSX", VAN: "TSXV", NEO: "NEO", CNQ: "CSE", LSE: "LSE",
  IOB: "LSE", TYO: "TSE", JPX: "TSE", FRA: "FRA", GER: "XETRA", PAR: "PARIS", AMS: "AMSTERDAM",
  HKG: "HKEX", ASX: "ASX", NZE: "NZX", SES: "SGX", BSE: "BSE", NSI: "NSE", CCC: "CRYPTO", CCY: "FX",
  SNP: "S&P", DJI: "DOW", NIM: "NASDAQ", PNK: "OTC", OQB: "OTC", OQX: "OTC", OEM: "OTC", JNB: "JSE"
}

// A day answer's URL: one day, or, with `twoDays`, the last two, so the
// last session is in it once Yahoo's day has turned to the coming one
// (`Market.twoDays`). The answer is read as the headline's session and
// what came after it (`parseChart`).
function chartUrl(symbol, twoDays) {
  return CHART_URL + encodeURIComponent(symbol) + "?range=" + (twoDays ? "2d" : "1d") + "&interval=5m&includePrePost=true"
}

function sparkUrl(symbols, twoDays) {
  return SPARK_URL + "?symbols=" + symbols.map(encodeURIComponent).join(",") + "&range=" + (twoDays ? "2d" : "1d") + "&interval=5m&includePrePost=true"
}

// A spark answer's listings, by symbol: each one's day in the chart's own
// shape, closes only. A symbol Yahoo doesn't know is left out of the answer.
// Null for an answer whose listings are not a list of at most MOST_SPARKS.
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

// One listing's spark day (`sparkResults`) as a quote. Without opens the
// stray filter can judge nothing, so the listing's last chart answer's
// verdict stands in (`verdict`, `parseChart`): the strays it dropped are
// left out, and its day's open is this day's when both are the same
// session's. `unjudged` when a jump between two closes (not `sameLevel`)
// lies past the bars that verdict settled and a whole bar has come since
// it, or when Yahoo has since changed a whole bar the verdict saw, past
// spark's own rounding (`sameClose`), or filled one in it had none for, or
// when the session has opened since the verdict's: only a chart answer,
// with opens, can say whether that is a stray, or what the open was. The
// newest bar is never judged, as in the filter.
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

// Whether a spark close is the chart's for the same bar: spark sends a
// price of 1 or more to three decimals (PLUG's 1.3786 as 1.379), a smaller
// one as the chart does (AITX's 0.0014, SHIB's 0.00000505).
function sameClose(spark, chart) {
  return Math.abs(spark - chart) <= (Math.abs(chart) >= 1 ? 0.0005 : 0) + Math.abs(chart) * 1e-6
}

// How far apart two prices are, as a fraction of the larger.
function apart(a, b) {
  var scale = Math.max(Math.abs(a), Math.abs(b))
  return scale > 0 ? Math.abs(a - b) / scale : 0
}

// Under this, two prices are the same level; over it, they are not.
var STRAY_GAP = 0.005

// Two prices this many ticks apart are one level however small the price:
// under $2 one cent is more than STRAY_GAP, and PLUG's one-cent bounces read
// as stray.
var STRAY_TICKS = 2

// Whether two prices are one level: within STRAY_GAP, or within two of the
// listing's ticks (`Format.priceTick`; null without one). The half tick over
// absorbs Yahoo's float noise (1.9800000190734863 against 1.9700000286102295).
function sameLevel(a, b, tick) {
  return apart(a, b) <= STRAY_GAP || (tick > 0 && Math.abs(a - b) < (STRAY_TICKS + 0.5) * tick)
}

// The longest run of stray buckets seen: Yahoo has sent two in a row.
var STRAY_RUN = 3

// The longest run of mixed stray prints seen inside one extended session:
// BRK-B's four after its close on Friday 2 October.
var MIXED_RUN = 4

// Yahoo drops stray ticks into intraday buckets: a bell bucket that falls
// back to yesterday's close, a lone after-hours print, sometimes two in a
// row. What identifies them is not how far they reach — one of the saved
// cases is 0.8% — but that the series carries on as if they never happened.
// `tick` is the listing's (`Format.priceTick`): a move of a tick or two is
// trading, never stray. So is a bar with shares traded in it (`v`): every
// stray in the saved answers came with none, and a thin listing's own
// trades often open back where the bar before closed. Otherwise a thin
// young listing's week would lose real bars, its high among them.
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

// How many bars from `from` the series says never happened: their closes have
// all left the accepted bar's price, and the bar after them opens back at that
// price instead of continuing from the last of them. A real move is the other
// way round — the next bar opens from where the move closed. Zero for a real
// move, and for a run with no bar after it, so the newest bar is never judged.
// Only a bar one step after the run, the step from the accepted bar to the
// run, judges it, so a session break is never bridged. Inside one session of
// the answer's `periods`, a bar after an uneven gap that opens back at the
// price yet strays again only carries the run on: JPM's 16:50 and 17:00 on
// 16 October opened at the price (339.83, 339.52) and closed at 318.24,
// 16:55 missing, and 17:05 opened back at 339.50. A history has no periods:
// across a night or a weekend, prices can really move.
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

// Yahoo also mixes stray prints into a quiet extended session: BRK-B on
// Friday 2 October, 16:45 to 17:10, closed at 520.93, 489.66, 500.31, and
// 489.66 between 502.80 and 502.65, 30, 5, 10, and 10 minutes apart. Inside
// one pre- or post-market session, whatever the gaps, a run of three or four
// bars is stray when none of them opens where the one before closed, their
// closes land both above and below the accepted price, and the bar after
// them opens back at that price. A thin listing's own trades take that shape
// two bars at a time (REED's 18:25 and 18:40 on 1 October), never three in
// the saved answers. Zero otherwise; `periods` are the answer's sessions.
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

// Whether shares traded in a bar: Yahoo sends none for a stray, and in the
// saved answers none for a day's pre- and post-market bars either.
function traded(bar) {
  return Format.isFiniteNumber(bar.v) && bar.v > 0
}

// "pre", "regular", or "post" when `t` falls in that session of `periods`,
// else "".
function sessionAt(periods, t) {
  var names = ["pre", "regular", "post"]
  for (var n = 0; periods && n < names.length; n++) {
    var period = periods[names[n]]
    if (period && t >= period.start && t < period.end) return names[n]
  }
  return ""
}

// "pre" or "post" when `t` falls in that session of `periods`, else "".
function extendedSession(periods, t) {
  var session = sessionAt(periods, t)
  return session === "regular" ? "" : session
}

// The exchange a listing trades on, by the name people use.
function exchangeOf(meta) {
  var code = Format.fetchedText(meta.exchangeName, Format.MOST_CODE)
  return EXCHANGE_NAMES[code] || (Format.fetchedText(meta.fullExchangeName, Format.MOST_NAME) || code).toUpperCase()
}

// Whether an answer's listing trades in whole cents from $1: its exchange is
// one of `centExchanges`, the caller's to know (`Market.centExchanges`).
function inCents(meta, centExchanges) {
  return !!centExchanges && centExchanges.indexOf(exchangeOf(meta)) >= 0
}

// The tick of the listing an answer is for (`Format.priceTick`), from its
// headline price, else its last bar's close.
function answerTick(meta, bars, centExchanges) {
  var price = knownPrice(meta.regularMarketPrice) !== null ? meta.regularMarketPrice
    : (bars.length ? bars[bars.length - 1].c : null)
  return Format.priceTick(price, meta.priceHint, inCents(meta, centExchanges))
}

// Yahoo's day answer as a quote. `centExchanges` are the exchanges whose
// listings trade in whole cents from $1 (`Market.centExchanges`): their
// prices and ticks take cents there; any other listing's take Yahoo's hint.
// Null for an answer that is not a chart, whose bars or periods are not
// lists within MOST_BARS, MOST_DAYS, and MOST_PERIODS, whose bar times
// are not moments (`Format.isMoment`) each after the one before, as every
// saved answer's are: the chart lays its prints out from the first to the
// last, and one out of order would land off its grid; or whose trading
// periods or current ones are not periods (`answerClocks`,
// `currentPeriods`). An offset that is not one (`isOffset`) is none.
// `receivedAt`, when given, is when the answer came (`nextDayBegun`).
function parseChart(json, centExchanges, receivedAt) {
  var result = json && json.chart && json.chart.result && json.chart.result[0]
  if (!result || !result.meta) return null
  var meta = result.meta
  var timestamps = Format.fetchedList(result.timestamp || [], MOST_BARS)
  var quote = (result.indicators && result.indicators.quote && result.indicators.quote[0]) || {}
  var closes = Format.fetchedList(quote.close || [], MOST_BARS)
  var opens = Format.fetchedList(quote.open || [], MOST_BARS)
  // Shares traded in each bar, which the stray filter reads; none read from
  // an answer without them, as spark's.
  var volumes = quote.volume ? Format.fetchedList(quote.volume, MOST_BARS) : null
  var clocks = answerClocks(meta.tradingPeriods)
  var current = meta.currentTradingPeriod || {}
  if (!timestamps || !closes || !opens || !clocks || !currentPeriods(current)) return null
  // The session the bars describe is the answer's trading periods. Yahoo's
  // current period moves on to the next session first (Monday's at 00:36 New
  // York, the bars still Friday's), so it stands in only for an answer
  // without them. A two-day answer (`chartUrl`) is read as the headline's
  // session, the last of its days whose regular session the quote is from
  // or after, else its first: the bars of the days before it are left out,
  // and the bars of the day after it (`next`), the coming day's pre-market,
  // stay as its tail, each with its session. Without the quote's time, the
  // last day with a regular-session bar, so before the open the session is
  // still the last one. A one-day answer is its day.
  var quoted = Format.isFiniteNumber(meta.regularMarketTime) && meta.regularMarketTime > 0 ? meta.regularMarketTime : null
  var days = meta.tradingPeriods ? answerDays(meta.tradingPeriods) : [current]
  var since = function(d) { return quoted !== null ? quoted : barIn(timestamps, closes, days[d].regular) }
  var chosen = 0
  for (var d = 1; d < days.length; d++) if (days[d].regular && since(d) !== null && days[d].regular.start <= since(d)) chosen = d
  var periods = days[chosen]
  var next = chosen + 1 < days.length ? days[chosen + 1] : null
  var from = chosen > 0 ? periodsStart(periods) : null
  var bars = []
  for (var i = 0; i < timestamps.length; i++) {
    if (!Format.isMoment(timestamps[i]) || (i > 0 && !(timestamps[i] > timestamps[i - 1]))) return null
    if (knownPrice(closes[i]) !== null && (from === null || timestamps[i] >= from))
      bars.push({ t: timestamps[i], o: opens[i], c: closes[i], v: volumes ? volumes[i] : null })
  }
  var filtered = filterStrayCloses(bars, periods, answerTick(meta, bars, centExchanges))
  var kept = filtered.bars
  // The whole bars, all but the live moment; and of them those whose
  // verdict no later bar can change: a stray run reaches at most MIXED_RUN
  // bars on, to the bar that opens back.
  var wholeBars = bars.slice(0, Math.max(0, bars.length - 1))
  var settledBars = bars.slice(0, Math.max(0, bars.length - MIXED_RUN))
  var regular = periodOf(periods.regular)
  // An index is worked out only while its exchange trades. Yahoo still
  // gives it pre- and post-market periods, and repeats its close through the
  // evening (^GSPC's 7818.93 from 16:00 to 17:20): it has neither session,
  // and no print outside its own.
  var index = meta.instrumentType === "INDEX"
  var tailFrom = next ? periodsStart(next) : null
  var points = []
  for (var j = 0; j < kept.length; j++) {
    var tail = tailFrom !== null && kept[j].t >= tailFrom
    if (tail && !index) points.push({ t: kept[j].t, p: kept[j].c, s: POINT_SESSIONS[sessionAt(next, kept[j].t)] || "pre" })
    else if (!tail && (!index || !regular || (kept[j].t >= regular.start && kept[j].t < regular.end)))
      points.push({ t: kept[j].t, p: kept[j].c })
  }
  // Yahoo moves the day's high, low, and volume on before the bars, too:
  // London's answer before its session sends the coming day's high and low
  // as 0, not known yet. The figures' day is then that session's, and the
  // bars' open is not its. And they stay a listing's last trading day's:
  // CVR, untraded on Friday 16 October, answered with Friday's session and
  // Wednesday's figures, its regular quote stamped Wednesday 16:00. The
  // figures' day is then the quote's.
  var ahead = !knownPrice(meta.regularMarketDayHigh) && !knownPrice(meta.regularMarketDayLow) && !!current.regular
  var figuresDay = ahead ? current.regular.start : !regular ? null
    : quoted !== null && quoted < regular.start ? quoted : regular.start
  // The day's open: the first regular-session bar's, once there is one.
  var firstRegular = null
  for (var k = 0; regular && !ahead && k < kept.length && !firstRegular; k++)
    if (kept[k].t >= regular.start && kept[k].t < regular.end) firstRegular = kept[k]
  // Whether the answer came once its next day had begun, its bars still an
  // earlier session's: a stock's two-day answer holding the coming day
  // (`next`), which Yahoo sends from its pre-market on; an index's, whose
  // bars stay the last session's until its open, once Yahoo's current
  // period is a later session than its bars' and the answer came after that
  // period's pre-market began, else its open. Its open is then not the
  // coming session's (`headlineBase`).
  var nextDay = !!regular && !!current.regular && current.regular.start > regular.start ? (current.pre || current.regular) : null
  var nextDayBegun = index ? !!nextDay && Format.isFiniteNumber(receivedAt) && receivedAt >= nextDay.start : !!next
  var symbol = Format.fetchedText(meta.symbol, Format.MOST_CODE)
  var instrumentType = Format.fetchedText(meta.instrumentType, Format.MOST_CODE)
  return {
    symbol: symbol,
    // The long name, as search takes it: the short one arrives in capitals
    // for some listings and is cut at 31 characters.
    name: Format.fetchedText(meta.longName, Format.MOST_NAME) || Format.fetchedText(meta.shortName, Format.MOST_NAME) || symbol,
    // Only the currency Yahoo names, or "": an answer can name none, as
    // ^STOXX50E's did, and a price is never called dollars Yahoo didn't say.
    currency: Format.fetchedText(meta.currency, Format.MOST_CODE),
    exchange: exchangeOf(meta),
    timezoneName: Format.fetchedText(meta.exchangeTimezoneName, Format.MOST_CODE),
    gmtoffset: isOffset(meta.gmtoffset) ? meta.gmtoffset : 0,
    // The zone's short name at that offset, as Yahoo writes it: "EDT", "JST".
    zoneName: Format.fetchedText(meta.timezone, Format.MOST_CODE),
    // Each period's own (`answerClocks`), for a print's clock on its day.
    clocks: clocks,
    instrumentType: instrumentType,
    crypto: instrumentType === "CRYPTOCURRENCY",
    // The regular-market quote as Yahoo reports it, with its own timestamp.
    // Kept apart from the chart samples: see headlineQuote. A price at or
    // under zero is none, as a close, a previous close, an open, a high, and
    // a low are (`knownPrice`): Yahoo sends zeros for prices it doesn't
    // have, and it can send negatives: shown, a negative price would read
    // "-5.00" and a zero previous close "0.00%".
    price: knownPrice(meta.regularMarketPrice),
    // The decimals every price of this listing is shown in, from its
    // headline price, Yahoo's hint, and its market (`Format.priceDigits`).
    priceDigits: Format.priceDigits(knownPrice(meta.regularMarketPrice) !== null ? meta.regularMarketPrice
      : (points.length ? points[points.length - 1].p : null), meta.priceHint, inCents(meta, centExchanges)),
    // The close before the bars' session: the range's own, before its first
    // day, unless the session is a later day's of a two-day answer, whose
    // close before it is Yahoo's previous close, the headline's.
    prevClose: knownPrice(chosen === 0 && meta.chartPreviousClose !== undefined ? meta.chartPreviousClose : meta.previousClose),
    // A time no Date holds (`Format.isMoment`) is none, as one not sent is.
    marketTime: Format.isMoment(meta.regularMarketTime) && meta.regularMarketTime > 0 ? meta.regularMarketTime : null,
    dayOpen: firstRegular ? knownPrice(firstRegular.o) : null,
    // The regular session `dayOpen` is the open of, once its first bar has
    // come; null before, and while the figures are the coming session's.
    openSession: firstRegular ? regular.start : null,
    dayHigh: knownPrice(meta.regularMarketDayHigh),
    dayLow: knownPrice(meta.regularMarketDayLow),
    volume: meta.regularMarketVolume,
    fiftyTwoWeekHigh: knownPrice(meta.fiftyTwoWeekHigh),
    fiftyTwoWeekLow: knownPrice(meta.fiftyTwoWeekLow),
    // The start of the session the day's open, high, low, and volume are.
    figuresDay: figuresDay,
    nextDayBegun: nextDayBegun,
    session: {
      pre: index ? null : periodOf(periods.pre),
      regular: regular,
      post: index ? null : periodOf(periods.post)
    },
    // Yahoo's current period: the next session once the bars' has ended.
    current: {
      pre: index ? null : periodOf(current.pre),
      regular: periodOf(current.regular),
      post: index ? null : periodOf(current.post)
    },
    // The coming day's periods, when a two-day answer holds them after the
    // session's: its pre-market bars are the day's tail (`tailStart`).
    next: next && !index ? { pre: periodOf(next.pre), regular: periodOf(next.regular), post: periodOf(next.post) } : null,
    points: points,
    droppedTimes: filtered.droppedTimes,
    // What the stray filter judged of this day, for a spark answer after it
    // (`sparkQuote`): its last whole bar (the newest is the live moment),
    // the last bar no later bar can change the verdict on, the whole bars'
    // closes as judged, the strays it dropped, and the day's open with its
    // session. Null without opens, when it could judge nothing.
    verdict: opens.length ? {
      newest: wholeBars.length ? wholeBars[wholeBars.length - 1].t : 0,
      settled: settledBars.length ? settledBars[settledBars.length - 1].t : 0,
      times: wholeBars.map(function(b) { return b.t }),
      closes: wholeBars.map(function(b) { return b.c }),
      dropped: filtered.droppedTimes,
      open: firstRegular ? knownPrice(firstRegular.o) : null,
      openSession: firstRegular ? regular.start : null
    } : null
  }
}

// Whether a quote says nothing new over the last one for the same symbol:
// the points compared one by one, a bar Yahoo revises mid-day too, then
// every other figure as a value (`sameRecord`), never written out as text,
// which for a long list's landing would take longer than the rest of it.
function sameQuote(a, b) {
  var pa = a.points || []
  var pb = b.points || []
  if (pa.length !== pb.length) return false
  for (var i = 0; i < pa.length; i++) if (pa[i].t !== pb[i].t || pa[i].p !== pb[i].p) return false
  return sameRecord(a, b, "points")
}

// Whether two figures hold the same: a number, text, or flag; or a list
// or record of them, item by item.
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

// Two records' figures, all but `skip`'s. One left unset is the same as one
// a record lacks, as a saved quote, written out and read back, lacks it.
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

// The answer's sessions in a regular session's day: its pre-market, its
// regular session, and its after hours.
var POINT_SESSIONS = { pre: "pre", regular: "reg", post: "post" }

// Where a day's periods (`answerDays`) begin: its pre-market, else its
// regular session; null with neither.
function periodsStart(periods) {
  return periods.pre ? periods.pre.start : periods.regular ? periods.regular.start : null
}

// The time of an answer's first bar with a close inside `period`, or null.
function barIn(timestamps, closes, period) {
  for (var i = 0; period && i < timestamps.length; i++)
    if (timestamps[i] >= period.start && timestamps[i] < period.end && knownPrice(closes[i]) !== null) return timestamps[i]
  return null
}

// An answer's trading periods, a day at a time, each day's pre, regular, and
// post sessions from its first period's start to its last's end; none from
// a list past MOST_DAYS or MOST_PERIODS, an answer `parseChart` has already
// refused (`answerClocks`). A day answer lists one day, a two-day answer
// two (`chartUrl`). A day answer may also come in a range's shape, one list
// of days, as every non-US listing's and an index's at night do: its
// periods are the regular session's, with no pre or post. Not read so, a
// listing such as SHEL.L would say "Closed · opens Mon" through its session,
// its chart a straight line. Always one day at least, its sessions null when
// none is listed.
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

// The clocks an answer's days kept: each trading period with its own UTC
// offset and zone name, from its start to its day's midnight, so a close
// stamped past the period's end reads its day's too (IAG.MC's at 17:35:26,
// its periods ended at 17:30). `meta.gmtoffset` is the clock the answer was
// sent by, so the week after a change of clocks a period before it still
// says its own (Sydney's 10:00 AEST open of 21 September, in an answer sent
// in AEDT). Both shapes Yahoo sends: pre, regular, and post, each a list of
// days, and one list of days, a range's and some day answers' (`answerDays`).
// Null when a list of days or of a day's periods is not a list within
// MOST_DAYS or MOST_PERIODS, or a period is not one (`isPeriod`) with an
// offset (`isOffset`): a spark day with a null period would throw here and
// stop its feed until Stonks restarts.
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
    }
  }
  return out
}

// Whether `p` is a period every reading of it can take: an object whose
// start and end are moments (`Format.isMoment`). Otherwise a period's end
// of {"toString": null} would throw where a bar is compared with it, and,
// kept in the quote, on every look for what is due, so no row would be
// asked for again until Stonks restarts.
function isPeriod(p) {
  return !!p && typeof p === "object" && Format.isMoment(p.start) && Format.isMoment(p.end)
}

// Whether each current period Yahoo sends, pre, regular, and post, is a
// period (`isPeriod`). Their offsets are never read.
function currentPeriods(current) {
  var names = ["pre", "regular", "post"]
  for (var i = 0; i < names.length; i++) if (current[names[i]] && !isPeriod(current[names[i]])) return false
  return true
}

// Whether `v` is a UTC offset in seconds a clock can keep: a number under a
// day either way.
function isOffset(v) {
  return Format.isFiniteNumber(v) && Math.abs(v) < 86400
}

// The clock `answer`, a quote or a history, kept at `t`: that of its
// period's day holding `t`; outside them, the answer's own.
function clockAt(answer, t) {
  var clocks = answer.clocks || []
  for (var i = 0; i < clocks.length; i++) {
    if (t >= clocks[i].start && t < clocks[i].until) return clocks[i]
  }
  return { offset: answer.gmtoffset || 0, zone: answer.zoneName || "" }
}

// A price Yahoo sends as 0 is one it does not know yet: London's day high,
// day low, and 52-week low before its session opens. Null, like a missing one.
function knownPrice(v) {
  return Format.isFiniteNumber(v) && v > 0 ? v : null
}

// Chart samples inside the regular session. Buckets are stamped by their
// start, and Yahoo's regular-only series ends with the 15:55 bucket, so a
// bucket stamped at the bell belongs to the post-market.
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

// The headline: the regular-market quote Yahoo reports, with its own
// timestamp, the way Apple's Stocks shows the price. It is the latest
// regular print while trading and the close otherwise, and it may be
// stamped a second after the bell or belong to the previous session; that
// is still the regular quote. A missing time never discards a known price.
// Only when the price is missing does the last regular chart sample stand
// in, labelled with its bar's time. Null when neither
// exists: an unavailable price is shown as unavailable, never invented.
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

// The close the answer's own day is measured from: the one before its
// regular session. That is Yahoo's previous close once the quote is that
// session's; until the session opens the quote is still the last session's
// close, and Yahoo's previous close the one before it: measured from that,
// the pre-market's change would disagree with the line under the price. The
// headline's change stays the quote's own (`headlineBase`).
function dayBase(quote) {
  var reg = quote.session.regular
  var head = headlineQuote(quote)
  return reg && head && head.source === "quote" && head.t !== null && head.t < reg.start ? head.price : quote.prevClose
}

// What the headline's change is measured from, shaped as `change` reads
// it: Yahoo's previous close, and the day's open, but none once the
// listing's next day has begun (`nextDayBegun`), for a stock and an index
// alike, so before the open no index says the last session's "% open"
// while the stocks beside it say "—". A scrub of the last session still
// reads from its open.
function headlineBase(quote) {
  return { prevClose: quote.prevClose, dayOpen: quote.nextDayBegun ? null : quote.dayOpen }
}

// The latest print outside a regular session, the newest print of all
// (`latest` when given, else the quote's own last): pre-market, post-market,
// or overnight. Null while the regular session's print is the newest.
function extendedPrint(quote, latest) {
  var pts = quote.points
  var last = latest || pts[pts.length - 1]
  if (!quote.session.regular || !last) return null
  var phase = pointSession(quote, last)
  return phase === "reg" ? null : { t: last.t, p: last.p, phase: phase }
}

// What a moment `t` of the day reads, shaped as the headline is: the price
// at or just before it, at `t`; before the first print, the close the day
// is measured from (`dayBase`).
// Once Yahoo's quote is the regular session's close, the session's last
// print reads that close at the bell (`close`): the S&P 500's last bar is
// 15:55's, never its close, and Tokyo's 15:20's. Not at the quote's own
// stamp, which can come later: London's close on 7 October, 16:30, was
// stamped 17:20, after its 16:30 and 16:35 after-hours buckets.
function readingAt(quote, t) {
  var pts = quote.points
  if (!pts.length || t < pts[0].t) return { price: dayBase(quote), t: t, close: false }
  // The last print at or before `t`, halving the prints, which run in time
  // order: a walk from the first would cost every row a step for each print
  // of the day on every scrub step.
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

// The move from the previous close, or "since the open" from the day's open
// as the info line shows it (`dayOpen`): none while that isn't known, as
// before the session's first bar.
function change(quote, priceNow, mode) {
  var base = mode === "open" ? quote.dayOpen : quote.prevClose
  if (!Format.isFiniteNumber(priceNow) || !Format.isFiniteNumber(base)) return { abs: null, pct: null, up: true }
  var abs = priceNow - base
  return { abs: abs, pct: base ? (abs / base) * 100 : 0, up: abs >= 0 }
}

// A print's session: its own tag where the series carries one, else where it
// falls against the response's regular session. Buckets are stamped by their
// start, so the one stamped at the bell is post-market.
function pointSession(quote, pt) {
  if (pt.s) return pt.s
  var reg = regularOrPrints(quote)
  return pt.t >= reg.end ? "post" : pt.t < reg.start ? "pre" : "reg"
}

// The regular session, or the prints' own span when Yahoo sent none.
function regularOrPrints(quote) {
  var pts = quote.points
  return quote.session.regular || { start: pts[0] ? pts[0].t : 0, end: pts.length ? pts[pts.length - 1].t : 1 }
}

// The last print the chart actually drew. The axis runs on past it, to the
// bell or to midnight, but there is nothing to read past this, so the scrub
// stops here.
function lastPrintTime(quote) {
  var pts = quote.points
  return pts.length ? pts[pts.length - 1].t : null
}

// Where the response's own day starts and ends: its pre- and post-market,
// or its regular session.
function dayStart(quote) {
  var s = quote.session
  return s.pre ? s.pre.start : s.regular ? s.regular.start : 0
}

function dayEnd(quote) {
  var s = quote.session
  return s.post ? s.post.end : s.regular ? s.regular.end : 0
}

// Where the coming day's pre-market a two-day answer holds after a quote's
// day begins (`next`): its prints from here are the day's tail. Null for a
// quote with nothing after its day.
function tailStart(quote) {
  return quote.next ? periodsStart(quote.next) : null
}

function bucketTimes(times) {
  var out = []
  for (var i = 0; times && i < times.length; i++) out.push(new Date(times[i] * 1000).toISOString())
  return out.join(", ")
}
