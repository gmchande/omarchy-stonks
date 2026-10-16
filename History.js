.import "Format.js" as Format
.import "Market.js" as Market
.import "Quote.js" as Quote

// Ranges: Yahoo's history answer, its stats, bars, dates, and words. Knows
// nothing of the day or overnight prints; a calendar it is handed only says
// an intraday bar's time.

// 1D stays on chartUrl / parseChart. Every other range uses this table.
var HISTORY_RANGES = {
  "1W": { range: "5d", interval: "15m" },
  "1M": { range: "1mo", interval: "1h" },
  "3M": { range: "3mo", interval: "1d" },
  "6M": { range: "6mo", interval: "1d" },
  "YTD": { range: "ytd", interval: "1d" },
  "1Y": { range: "1y", interval: "1d" },
  "2Y": { range: "2y", interval: "1d" },
  "5Y": { range: "5y", interval: "1wk", scale: "log" },
  "10Y": { range: "10y", interval: "1wk", scale: "log" },
  "All": { range: "max", interval: "1mo", scale: "log" }
}

function historyUrl(symbol, range) {
  var spec = HISTORY_RANGES[range]
  if (!spec) return null
  return Quote.CHART_URL + encodeURIComponent(symbol) + "?range=" + spec.range + "&interval=" + spec.interval + "&events=div%2Csplits&includeAdjustedClose=true"
}

function historyRanges() {
  return ["1D"].concat(Object.keys(HISTORY_RANGES))
}

function parseHistory(json, range) {
  var result = json && json.chart && json.chart.result && json.chart.result[0]
  if (!result || !result.meta) return null
  var meta = result.meta
  var spec = HISTORY_RANGES[range]
  var quote = (result.indicators && result.indicators.quote && result.indicators.quote[0]) || {}
  var timestamps = result.timestamp || []
  var opens = quote.open || []
  var highs = quote.high || []
  var lows = quote.low || []
  var closes = quote.close || []
  var bars = []
  for (var i = 0; i < timestamps.length; i++) {
    if (closes[i] === null || closes[i] === undefined) continue
    bars.push({ t: timestamps[i], o: opens[i], h: highs[i], l: lows[i], c: closes[i] })
  }
  bars.sort(function (a, b) { return a.t - b.t })
  if (bars.length >= 2 && bars[bars.length - 1].t === bars[bars.length - 2].t) bars.splice(bars.length - 2, 1)
  var interval = meta.dataGranularity || (spec && spec.interval)
  var intervalSeconds = historyIntervalSeconds(interval)
  // Only intraday buckets carry a stray close; a daily bar cannot.
  var droppedTimes = []
  if (intervalSeconds > 0 && intervalSeconds < 24 * 60 * 60) {
    var filtered = Quote.filterStrayCloses(bars)
    bars = filtered.bars
    droppedTimes = filtered.droppedTimes
  }
  var baseline = Format.isFiniteNumber(meta.chartPreviousClose) ? meta.chartPreviousClose : (bars.length ? bars[0].c : null)
  return {
    symbol: meta.symbol,
    range: range,
    interval: interval,
    gmtoffset: meta.gmtoffset || 0,
    zoneName: meta.timezone || "",
    bars: bars,
    baseline: baseline,
    firstTradeDate: Format.isFiniteNumber(meta.firstTradeDate) ? meta.firstTradeDate : null,
    droppedTimes: droppedTimes
  }
}

function historyIntervalSeconds(interval) {
  if (interval === "5m") return 5 * 60
  if (interval === "15m") return 15 * 60
  if (interval === "30m") return 30 * 60
  if (interval === "1h") return 60 * 60
  if (interval === "1d") return 24 * 60 * 60
  if (interval === "1wk") return 7 * 24 * 60 * 60
  if (interval === "1mo") return 31 * 24 * 60 * 60
  if (interval === "3mo") return 93 * 24 * 60 * 60
  return 0
}

function periodStats(history) {
  var bars = history && history.bars ? history.bars : []
  var lastBar = bars.length ? bars[bars.length - 1] : null
  var last = lastBar && Format.isFiniteNumber(lastBar.c) ? lastBar.c : null
  var chg = Quote.change({ prevClose: history ? history.baseline : null, points: [] }, last, "pct")
  var high = null
  var low = null
  for (var i = 0; i < bars.length; i++) {
    var bar = bars[i]
    if (Format.isFiniteNumber(bar.h) && (!high || bar.h > high.p)) high = { p: bar.h, t: bar.t }
    if (Format.isFiniteNumber(bar.l) && (!low || bar.l < low.p)) low = { p: bar.l, t: bar.t }
  }
  var interval = historyIntervalSeconds(history ? history.interval : "")
  var first = bars.length ? bars[0] : null
  var firstTradeDate = history ? history.firstTradeDate : null
  var short = !!(first && Format.isFiniteNumber(first.t) && Format.isFiniteNumber(firstTradeDate) && interval > 0
    && first.t <= firstTradeDate + interval && first.t + interval >= firstTradeDate)
  return {
    last: last,
    change: chg,
    high: high,
    low: low,
    belowHigh: high && Format.isFiniteNumber(last) && high.p !== 0 ? (high.p - last) / high.p * 100 : null,
    coverage: {
      from: first && Format.isFiniteNumber(first.t) ? first.t : null,
      to: lastBar && Format.isFiniteNumber(lastBar.t) ? lastBar.t : null,
      bars: bars.length,
      short: short
    }
  }
}

// Normalized x/y for a range: bars evenly spaced, and a vertical range that
// holds every close and the period's starting price the change is measured
// from, with headroom. From 5Y up the scale is logarithmic, so a decade of
// growth reads as a slope instead of a flat line and a wall. A log has no
// place for zero or a negative price, so a history holding one stays linear.
function historyGeometry(history) {
  var bars = history && history.bars ? history.bars : []
  var usable = []
  for (var i = 0; i < bars.length; i++) {
    if (Format.isFiniteNumber(bars[i].t) && Format.isFiniteNumber(bars[i].c)) usable.push(bars[i])
  }
  if (!usable.length) {
    return { points: [], baselineY: null, ticks: [], lo: null, hi: null, start: null, end: null, day: false }
  }
  var spec = HISTORY_RANGES[history.range]
  var baseline = Format.isFiniteNumber(history.baseline) ? history.baseline : usable[0].c
  var log = !!spec && spec.scale === "log" && baseline > 0
    && usable.every(function(bar) { return bar.c > 0 })
  var scale = log ? Math.log : function(p) { return p }
  var lo = scale(baseline)
  var hi = lo
  for (var j = 0; j < usable.length; j++) {
    var v = scale(usable[j].c)
    if (v < lo) lo = v
    if (v > hi) hi = v
  }
  var pad = (hi - lo) * 0.08 || 0.5
  lo -= pad
  hi += pad
  var denominator = Math.max(1, usable.length - 1)
  var points = []
  for (var k = 0; k < usable.length; k++) {
    points.push({
      x: k / denominator,
      y: 1 - (scale(usable[k].c) - lo) / (hi - lo),
      t: usable[k].t,
      p: usable[k].c,
      ext: false
    })
  }
  return {
    points: points,
    baselineY: 1 - (scale(baseline) - lo) / (hi - lo),
    ticks: [],
    lo: log ? Math.exp(lo) : lo,
    hi: log ? Math.exp(hi) : hi,
    start: usable[0].t,
    end: usable[usable.length - 1].t,
    day: false
  }
}

function historyBarAt(history, fraction) {
  var bars = history && history.bars ? history.bars : []
  if (!bars.length || !Format.isFiniteNumber(fraction)) return null
  var index = Math.round(Format.clamp(fraction, 0, 1) * (bars.length - 1))
  return bars[index]
}

function historyFraction(history, t) {
  var bars = history && history.bars ? history.bars : []
  if (!bars.length || !Format.isFiniteNumber(t) || !Format.isFiniteNumber(bars[0].t) || !Format.isFiniteNumber(bars[bars.length - 1].t)) return -1
  if (t < bars[0].t || t > bars[bars.length - 1].t) return -1
  if (bars.length === 1) return 0
  var nearest = 0
  var distance = Math.abs(bars[0].t - t)
  for (var i = 1; i < bars.length; i++) {
    var nextDistance = Math.abs(bars[i].t - t)
    if (nextDistance < distance) {
      nearest = i
      distance = nextDistance
    }
  }
  return nearest / (bars.length - 1)
}

function historyDateParts(t, gmtoffset) {
  if (!Format.isFiniteNumber(t)) return null
  var d = new Date((t + (gmtoffset || 0)) * 1000)
  return { day: d.getUTCDate(), month: d.getUTCMonth(), year: d.getUTCFullYear() }
}

function historySpansYears(history) {
  var bars = history && history.bars ? history.bars : []
  if (!bars.length) return false
  var first = historyDateParts(bars[0].t, history.gmtoffset)
  var last = historyDateParts(bars[bars.length - 1].t, history.gmtoffset)
  return !!(first && last && first.year !== last.year)
}

function historyDateText(t, gmtoffset, withYear, interval) {
  var date = historyDateParts(t, gmtoffset)
  if (!date) return "—"
  var text = interval === "1mo" || interval === "3mo" ? Format.MONTHS[date.month] : date.day + " " + Format.MONTHS[date.month]
  return text + (withYear ? " " + date.year : "")
}

// A bar coarser than a day has no day number to place it, so it always
// carries its year: a five-year high inside one calendar year would
// otherwise read "JUL". Day-level bars take the year only when the period
// crosses one.
function historyStatsDateText(t, gmtoffset, withYear, interval) {
  var date = historyDateParts(t, gmtoffset)
  if (!date) return "—"
  var coarse = interval === "1wk" || interval === "1mo" || interval === "3mo"
  var text = coarse ? Format.MONTHS[date.month] : date.day + " " + Format.MONTHS[date.month]
  return text + (coarse || withYear ? " " + String(date.year).slice(-2) : "")
}

// The widest date historyStatsDateText writes for these bars: a two-digit
// day, and always the year, which a period takes once it crosses one.
function historyStatsDateWidest(interval) {
  var coarse = interval === "1wk" || interval === "1mo" || interval === "3mo"
  return coarse ? "MMM 88" : "88 MMM 88"
}

// The info block's first line on a range, in the day line's shape
// (`Figures.dayLine`): the range, its low and high with the price's place
// between them, then what only it says: when a listing younger than its
// range began, the dates of its low and high, and how few bars a young
// listing's sparse answer has. The bars' slot is kept while the listing is
// younger than its range, so the eighth bar empties it and moves nothing.
// `digits` is the listing's price decimals (`Quote.priceDigits`); `price`
// the headline, else the last bar's close.
function rangeLine(history, stats, digits, price) {
  stats = stats || periodStats(history)
  if (!history || !stats || !stats.coverage) return null
  var coverage = stats.coverage
  var years = historySpansYears(history)
  var range = Format.infoRange(stats.low ? stats.low.p : null, stats.high ? stats.high.p : null,
    Format.isFiniteNumber(price) ? price : stats.last, digits)
  var dated = function(point) { return point ? historyStatsDateText(point.t, history.gmtoffset, years, history.interval) : "" }
  var widest = historyStatsDateWidest(history.interval)
  var facts = []
  if (coverage.short)
    facts.push({ label: "SINCE", value: historyStatsDateText(history.firstTradeDate, history.gmtoffset, true, "1d"), widest: historyStatsDateWidest("1d") })
  facts.push({ label: "LOW", value: dated(stats.low), widest: widest })
  facts.push({ label: "HIGH", value: dated(stats.high), widest: widest })
  if (coverage.short)
    facts.push({ label: "", value: coverage.bars && coverage.bars < 8 ? String(coverage.bars) : "", after: "BARS", widest: "8" })
  return { title: String(history.range || "").toUpperCase(), range: range, facts: facts }
}

// `calendar` is the listing's, so an intraday bar's time across a change of
// clocks reads by its own date's offset.
function historyScrubText(history, bar, digits, calendar) {
  if (!history || !bar) return ""
  var years = historySpansYears(history)
  var date = historyDateText(bar.t, history.gmtoffset, years, history.interval)
  if (history.interval === "1wk") date = "WEEK OF " + date
  if (history.interval === "15m" || history.interval === "30m" || history.interval === "1h")
    date += " " + (calendar ? Market.calendarClock(calendar, bar.t, history) : Format.zonedHhmm(bar.t, history.gmtoffset, history.zoneName))
  return date + " · " + Format.money(bar.c, digits)
}

function historyRowModel(history, quote, scrubT) {
  if (!history) return null
  var stats = periodStats(history)
  var bar = scrubT ? historyBarAt(history, historyFraction(history, scrubT)) : null
  var head = !bar && quote ? Quote.headlineQuote(quote) : null
  var price = bar && Format.isFiniteNumber(bar.c) ? bar.c
    : (head ? head.price : stats.last)
  var chg = Quote.change({ prevClose: history.baseline, points: [] }, price, "pct")
  return {
    symbol: history.symbol || (quote ? quote.symbol : ""),
    name: quote ? quote.name : (history.symbol || ""),
    price: price,
    priceText: Format.money(price, quote ? quote.priceDigits : undefined),
    asOf: bar ? bar.t : (head ? head.t : stats.coverage.to),
    pct: chg.pct,
    tone: Format.changeTone(chg, "pct"),
    dayUp: chg.pct === null ? null : chg.up,
    dayTone: Format.changeTone(chg, "pct"),
    changeText: Format.pct(chg.pct),
    changeLine: Format.pct(chg.pct),
    // What the change is measured over, said under it the way AT CLOSE is.
    periodLabel: String(history.range || "").toUpperCase()
  }
}
