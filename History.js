.pragma library
.import "Format.js" as Format
.import "Quote.js" as Quote

// Ranges: Yahoo's history answer, its stats, bars, dates, and words. Knows
// nothing of the day or overnight prints, nor of calendars: a bar's clock
// is its own day's, from the answer.

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

// Whether the range on show, its last answer `entry` (HistoryFeed's), is
// asked again at `now`: while its listing's market trades (`trading`, the
// caller's word, by the listing's calendar; a history holds regular hours
// only), every 15 minutes for a range of bars within the day (1W, 1M),
// whose line moves with the hour, and every hour for one of daily bars or
// longer, whose last bar moves through the session; and once after the
// session in its quote (`quote`) has closed, if its last good history came
// in before that, for its last bars. Each wait counts from the last answer,
// a failed one too, so a failed refresh is tried again at the same pace;
// never sooner than the cache's 15 minutes.
function historyDue(range, entry, quote, now, trading) {
  var spec = HISTORY_RANGES[range]
  if (!spec || !entry || !quote) return false
  var intraday = historyIntervalSeconds(spec.interval) < 24 * 60 * 60
  if (now - entry.answeredAt < (intraday ? 15 : 60) * 60) return false
  if (trading) return true
  var regular = quote.session && quote.session.regular
  return !!regular && regular.end <= now && entry.receivedAt < regular.end
}

// Yahoo's answer for a range. `centExchanges` as `Quote.parseChart` takes
// them, for the stray filter's tick.
function parseHistory(json, range, centExchanges) {
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
  // Only intraday buckets carry a stray close; a daily bar cannot. A move of
  // a tick or two is trading (`Quote.filterStrayCloses`).
  var droppedTimes = []
  if (intervalSeconds > 0 && intervalSeconds < 24 * 60 * 60) {
    var filtered = Quote.filterStrayCloses(bars, null, Quote.answerTick(meta, bars, centExchanges))
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
    // An intraday answer's days, each with its own clock, and the live
    // moment Yahoo appends, at the price's own second (`barOffset`).
    clocks: Quote.answerClocks(meta.tradingPeriods),
    liveAt: Format.isFiniteNumber(meta.regularMarketTime) ? meta.regularMarketTime : null,
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

// The UTC offset a bar of `history` at `t` is dated by: its own day's. An
// intraday bar's day is in Yahoo's periods (`Quote.clockAt`). A longer
// bar's answer lists none, and Yahoo stamps a week or a month at its first
// day's midnight by that day's offset, which is an hour either side of the
// answer's across a change of clocks: London's summer weeks at 23:00 UTC
// the Sunday before, its winter ones at 00:00. Any other stamp, a day's bar
// at its open or the live moment, keeps to its day by the answer's; the
// live moment even at a whole hour, as a coin's at 23:00 UTC.
function barOffset(history, t) {
  if (history.clocks && history.clocks.length) return Quote.clockAt(history, t).offset
  var offset = history.gmtoffset || 0
  if (t === history.liveAt) return offset
  var shifts = [0, -3600, 3600]
  for (var i = 0; i < shifts.length; i++) {
    if ((t + offset + shifts[i]) % 86400 === 0) return offset + shifts[i]
  }
  return offset
}

function historyDateParts(history, t) {
  if (!Format.isFiniteNumber(t)) return null
  var d = new Date((t + barOffset(history, t)) * 1000)
  return { day: d.getUTCDate(), month: d.getUTCMonth(), year: d.getUTCFullYear() }
}

function historySpansYears(history) {
  var bars = history && history.bars ? history.bars : []
  if (!bars.length) return false
  var first = historyDateParts(history, bars[0].t)
  var last = historyDateParts(history, bars[bars.length - 1].t)
  return !!(first && last && first.year !== last.year)
}

function historyDateText(history, t, withYear, interval) {
  var date = historyDateParts(history, t)
  if (!date) return "—"
  var text = interval === "1mo" || interval === "3mo" ? Format.MONTHS[date.month] : date.day + " " + Format.MONTHS[date.month]
  return text + (withYear ? " " + date.year : "")
}

// A bar coarser than a day has no day number to place it, so it always
// carries its year: a five-year high inside one calendar year would
// otherwise read "JUL". Day-level bars take the year only when the period
// crosses one. The year is written whole, as the scrub writes it: "JAN 23"
// read as the 23rd of January.
function historyStatsDateText(history, t, withYear, interval) {
  var coarse = interval === "1wk" || interval === "1mo" || interval === "3mo"
  return historyDateText(history, t, coarse || withYear, coarse ? "1mo" : "1d")
}

// The widest date historyStatsDateText writes for these bars: a two-digit
// day, and always the year, which a period takes once it crosses one.
function historyStatsDateWidest(interval) {
  var coarse = interval === "1wk" || interval === "1mo" || interval === "3mo"
  return coarse ? "MMM 8888" : "88 MMM 8888"
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
  var dated = function(point) { return point ? historyStatsDateText(history, point.t, years, history.interval) : "" }
  var widest = historyStatsDateWidest(history.interval)
  var facts = []
  if (coverage.short)
    facts.push({ label: "SINCE", value: historyStatsDateText(history, history.firstTradeDate, true, "1d"), widest: historyStatsDateWidest("1d") })
  facts.push({ label: "LOW", value: dated(stats.low), widest: widest })
  facts.push({ label: "HIGH", value: dated(stats.high), widest: widest })
  if (coverage.short)
    facts.push({ label: "", value: coverage.bars && coverage.bars < 8 ? String(coverage.bars) : "", after: "BARS", widest: "8" })
  return { title: String(history.range || "").toUpperCase(), range: range, facts: facts }
}

// An intraday bar's date and time read by its own day's clock, so a time
// across a change of clocks reads as the exchange's clock said then.
function historyScrubText(history, bar, digits) {
  if (!history || !bar) return ""
  var years = historySpansYears(history)
  var date = historyDateText(history, bar.t, years, history.interval)
  if (history.interval === "1wk") date = "WEEK OF " + date
  if (history.interval === "15m" || history.interval === "30m" || history.interval === "1h") {
    var clock = Quote.clockAt(history, bar.t)
    date += " " + Format.zonedHhmm(bar.t, clock.offset, clock.zone)
  }
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
