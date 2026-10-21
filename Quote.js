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

// Yahoo's short exchange codes to the names people use. A listing falls back
// to Yahoo's full exchange name; a search result to Yahoo's own short code.
var EXCHANGE_NAMES = {
  NMS: "NASDAQ", NGM: "NASDAQ", NCM: "NASDAQ", NAS: "NASDAQ", NYQ: "NYSE", PCX: "NYSE ARCA",
  ASE: "NYSE AMERICAN", BTS: "CBOE", TOR: "TSX", VAN: "TSXV", NEO: "NEO", CNQ: "CSE", LSE: "LSE",
  IOB: "LSE", TYO: "TSE", JPX: "TSE", FRA: "FRA", GER: "XETRA", PAR: "PARIS", AMS: "AMSTERDAM",
  HKG: "HKEX", ASX: "ASX", NZE: "NZX", SES: "SGX", BSE: "BSE", NSI: "NSE", CCC: "CRYPTO", CCY: "FX",
  SNP: "S&P", DJI: "DOW", NIM: "NASDAQ", PNK: "OTC", OQB: "OTC", OQX: "OTC", OEM: "OTC", JNB: "JSE"
}

function chartUrl(symbol) {
  return CHART_URL + encodeURIComponent(symbol) + "?range=1d&interval=5m&includePrePost=true"
}

function sparkUrl(symbols) {
  return SPARK_URL + "?symbols=" + symbols.map(encodeURIComponent).join(",") + "&range=1d&interval=5m&includePrePost=true"
}

// A spark answer's listings, by symbol: each one's day in the chart's own
// shape, closes only. A symbol Yahoo doesn't know is left out of the answer.
function sparkResults(json) {
  var out = {}
  var results = json && json.spark && json.spark.result
  for (var i = 0; results && i < results.length; i++) {
    var day = results[i].response && results[i].response[0]
    if (day && day.meta) out[results[i].symbol] = day
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
function sparkQuote(day, verdict, centExchanges) {
  var quote = parseChart({ chart: { result: [day] } }, centExchanges)
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
// trading, never stray.
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
    if (!back || !Format.isFiniteNumber(back.o) || sameLevel(bars[end].c, price, tick)) return 0
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
    if (end > from && sameLevel(bar.o, bars[end - 1].c, tick)) return 0
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
  return EXCHANGE_NAMES[meta.exchangeName] || String(meta.fullExchangeName || meta.exchangeName || "").toUpperCase()
}

// Whether an answer's listing trades in whole cents from $1: its exchange is
// one of `centExchanges`, the caller's to know (`Market.centExchanges`).
function inCents(meta, centExchanges) {
  return !!centExchanges && centExchanges.indexOf(exchangeOf(meta)) >= 0
}

// The tick of the listing an answer is for (`Format.priceTick`), from its
// headline price, else its last bar's close.
function answerTick(meta, bars, centExchanges) {
  var price = Format.isFiniteNumber(meta.regularMarketPrice) ? meta.regularMarketPrice
    : (bars.length ? bars[bars.length - 1].c : null)
  return Format.priceTick(price, meta.priceHint, inCents(meta, centExchanges))
}

// Yahoo's day answer as a quote. `centExchanges` are the exchanges whose
// listings trade in whole cents from $1 (`Market.centExchanges`): their
// prices and ticks take cents there; any other listing's take Yahoo's hint.
function parseChart(json, centExchanges) {
  var result = json && json.chart && json.chart.result && json.chart.result[0]
  if (!result || !result.meta) return null
  var meta = result.meta
  var timestamps = result.timestamp || []
  var quote = (result.indicators && result.indicators.quote && result.indicators.quote[0]) || {}
  var closes = quote.close || []
  var opens = quote.open || []
  // The session the bars describe is the answer's trading periods. Yahoo's
  // current period moves on to the next session first (Monday's at 00:36 New
  // York, the bars still Friday's), so it stands in only for an answer
  // without them.
  var periods = meta.tradingPeriods ? answerPeriods(meta.tradingPeriods) : meta.currentTradingPeriod || {}
  var current = meta.currentTradingPeriod || {}
  var bars = []
  for (var i = 0; i < timestamps.length; i++) {
    if (closes[i] !== null && closes[i] !== undefined)
      bars.push({ t: timestamps[i], o: opens[i], c: closes[i] })
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
  var points = []
  for (var j = 0; j < kept.length; j++) {
    if (!index || !regular || (kept[j].t >= regular.start && kept[j].t < regular.end))
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
  var quoted = Format.isFiniteNumber(meta.regularMarketTime) && meta.regularMarketTime > 0 ? meta.regularMarketTime : null
  var figuresDay = ahead ? current.regular.start : !regular ? null
    : quoted !== null && quoted < regular.start ? quoted : regular.start
  // The day's open: the first regular-session bar's, once there is one.
  var firstRegular = null
  for (var k = 0; regular && !ahead && k < kept.length && !firstRegular; k++)
    if (kept[k].t >= regular.start && kept[k].t < regular.end) firstRegular = kept[k]
  return {
    symbol: meta.symbol,
    // The long name, as search takes it: the short one arrives in capitals
    // for some listings and is cut at 31 characters.
    name: meta.longName || meta.shortName || meta.symbol,
    // Only the currency Yahoo names, or "": an answer can name none, as
    // ^STOXX50E's did, and a price is never called dollars Yahoo didn't say.
    currency: meta.currency || "",
    exchange: exchangeOf(meta),
    timezoneName: meta.exchangeTimezoneName || "",
    gmtoffset: meta.gmtoffset || 0,
    // The zone's short name at that offset, as Yahoo writes it: "EDT", "JST".
    zoneName: meta.timezone || "",
    // Each period's own (`answerClocks`), for a print's clock on its day.
    clocks: answerClocks(meta.tradingPeriods),
    instrumentType: meta.instrumentType || "",
    crypto: meta.instrumentType === "CRYPTOCURRENCY",
    // The regular-market quote as Yahoo reports it, with its own timestamp.
    // Kept apart from the chart samples: see headlineQuote.
    price: Format.isFiniteNumber(meta.regularMarketPrice) ? meta.regularMarketPrice : null,
    // The decimals every price of this listing is shown in, from its
    // headline price, Yahoo's hint, and its market (`Format.priceDigits`).
    priceDigits: Format.priceDigits(Format.isFiniteNumber(meta.regularMarketPrice) ? meta.regularMarketPrice
      : (points.length ? points[points.length - 1].p : null), meta.priceHint, inCents(meta, centExchanges)),
    prevClose: meta.chartPreviousClose !== undefined ? meta.chartPreviousClose : meta.previousClose,
    marketTime: Format.isFiniteNumber(meta.regularMarketTime) && meta.regularMarketTime > 0 ? meta.regularMarketTime : null,
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

// Whether a quote says nothing new over the last one for the same symbol,
// without writing out every point: every figure but the points as text,
// then the points compared one by one, a bar Yahoo revises mid-day too.
function sameQuote(a, b) {
  var pa = a.points || []
  var pb = b.points || []
  if (pa.length !== pb.length) return false
  for (var i = 0; i < pa.length; i++) if (pa[i].t !== pb[i].t || pa[i].p !== pb[i].p) return false
  return JSON.stringify(figuresOf(a)) === JSON.stringify(figuresOf(b))
}

function figuresOf(quote) {
  var figures = {}
  for (var key in quote) if (key !== "points") figures[key] = quote[key]
  return figures
}

function periodOf(period) {
  return period ? { start: period.start, end: period.end } : null
}

// An answer's trading periods as its pre, regular, and post sessions: each
// the last day it lists, from its first period's start to its last's end.
function answerPeriods(periods) {
  var out = {}
  var names = ["pre", "regular", "post"]
  for (var i = 0; i < names.length; i++) {
    var days = periods[names[i]] || []
    var day = days[days.length - 1] || []
    out[names[i]] = day.length ? { start: day[0].start, end: day[day.length - 1].end } : null
  }
  return out
}

// The clocks an answer's days kept: each trading period with its own UTC
// offset and zone name, from its start to its day's midnight, so a close
// stamped past the period's end reads its day's too (IAG.MC's at 17:35:26,
// its periods ended at 17:30). `meta.gmtoffset` is the clock the answer was
// sent by, so the week after a change of clocks a period before it still
// says its own (Sydney's 10:00 AEST open of 21 September, in an answer sent
// in AEDT). Both shapes Yahoo sends: a day answer's pre, regular, and post,
// each a list of days, and a range's one list of days.
function answerClocks(periods) {
  var lists = !periods ? [] : Array.isArray(periods) ? [periods] : [periods.pre, periods.regular, periods.post]
  var out = []
  lists.forEach(function(days) {
    (days || []).forEach(function(day) {
      (day || []).forEach(function(p) {
        var midnight = (Math.floor((p.start + p.gmtoffset) / 86400) + 1) * 86400 - p.gmtoffset
        out.push({ start: p.start, until: midnight, offset: p.gmtoffset, zone: p.timezone || "" })
      })
    })
  })
  return out
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
// is still the regular quote. Only when the metadata is unusable does the
// last regular chart sample stand in, with its own time. Null when neither
// exists: an unavailable price is shown as unavailable, never invented.
function headlineQuote(quote) {
  if (Format.isFiniteNumber(quote.price) && Format.isFiniteNumber(quote.marketTime)) {
    return { price: quote.price, t: quote.marketTime, source: "quote" }
  }
  var pts = regularPoints(quote)
  if (pts.length) return { price: pts[pts.length - 1].p, t: pts[pts.length - 1].t, source: "chart" }
  return null
}

function regularClose(quote) {
  var head = headlineQuote(quote)
  return head ? head.price : null
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
// at or just before it, at `t`; before the first print, the previous close.
// Once Yahoo's quote is the regular session's close, the session's last
// print reads that close at the bell (`close`): the S&P 500's last bar is
// 15:55's, never its close, and Tokyo's 15:20's. Not at the quote's own
// stamp, which can come later: London's close on 7 October, 16:30, was
// stamped 17:20, after its 16:30 and 16:35 after-hours buckets.
function readingAt(quote, t) {
  var pts = quote.points
  if (!pts.length || t < pts[0].t) return { price: quote.prevClose, t: t, close: false }
  var k = 0
  while (k + 1 < pts.length && pts[k + 1].t <= t) k++
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

function bucketTimes(times) {
  var out = []
  for (var i = 0; times && i < times.length; i++) out.push(new Date(times[i] * 1000).toISOString())
  return out.join(", ")
}
