.pragma library
.import "Format.js" as Format
.import "Quote.js" as Quote

// Yahoo's range answers: their bars, stats, dates and words. No calendars:
// a bar's clock is its own day's, from the answer.

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

// A range answered within this is fresh: only a reader's refresh asks for
// it again sooner.
var HISTORY_FRESH = 15 * 60

function historyUrl(symbol, range) {
  var spec = HISTORY_RANGES[range]
  if (!spec) return null
  return Quote.CHART_URL + encodeURIComponent(symbol) + "?range=" + spec.range + "&interval=" + spec.interval + "&events=div%2Csplits&includeAdjustedClose=true"
}

function historyRanges() {
  return ["1D"].concat(Object.keys(HISTORY_RANGES))
}

function historyKey(symbol, range) {
  return String(symbol || "").toUpperCase() + "|" + String(range || "")
}

function historyFresh(entry, now) {
  return !!entry && entry.status === "ok" && !!entry.receivedAt && now - entry.receivedAt < HISTORY_FRESH
}

// The charts held once `values` land, by key: at most `keep`, the oldest
// going first, but never one in use (on show, or a row's fetched ahead):
// pushed out, it would be asked for again at once, and push out the next.
function historiesKept(entries, values, inUse, keep) {
  var keys = Object.keys(values)
  var next = {}
  var others = Object.keys(entries).filter(function(k) { return keys.indexOf(k) < 0 })
  var over = others.length - (keep - keys.length)
  others.forEach(function(k) {
    if (over > 0 && inUse.indexOf(k) < 0) over--
    else next[k] = entries[k]
  })
  keys.forEach(function(k) { next[k] = Object.assign({ history: null, receivedAt: 0 }, entries[k], values[k]) })
  return next
}

// A history holds regular hours only. No wait is shorter than the feed
// keeps an answer fresh (`HISTORY_FRESH`).
function historyDue(range, entry, quote, now, trading) {
  var spec = HISTORY_RANGES[range]
  if (!spec || !entry || !quote) return false
  var intraday = historyIntervalSeconds(spec.interval) < 24 * 60 * 60
  if (now - entry.answeredAt < (intraday ? HISTORY_FRESH : 60 * 60)) return false
  if (trading) return true
  var regular = quote.session && quote.session.regular
  return !!regular && regular.end <= now && entry.receivedAt < regular.end
}

// Tokyo's daily answer leaves the day's close out after its close; that
// bar's high, low and shares still count, in `unclosed`.
function parseHistory(json, range, centExchanges) {
  var result = json && json.chart && json.chart.result && json.chart.result[0]
  if (!result || !result.meta) return null
  var meta = result.meta
  var spec = HISTORY_RANGES[range]
  var quote = (result.indicators && result.indicators.quote && result.indicators.quote[0]) || {}
  var list = function(value) { return Format.fetchedList(value || [], Quote.MOST_BARS) }
  var timestamps = list(result.timestamp)
  var opens = list(quote.open)
  var highs = list(quote.high)
  var lows = list(quote.low)
  var closes = list(quote.close)
  var volumes = quote.volume ? list(quote.volume) : null
  var clocks = Quote.answerClocks(meta.tradingPeriods)
  if (!timestamps || !opens || !highs || !lows || !closes || !clocks) return null
  var bars = []
  var unclosed = []
  for (var i = 0; i < timestamps.length; i++) {
    if (!Format.isMoment(timestamps[i])) return null
    var bar = { t: timestamps[i], o: Quote.knownPrice(opens[i]), h: Quote.knownPrice(highs[i]), l: Quote.knownPrice(lows[i]),
      c: closes[i], v: volumes ? volumes[i] : null }
    if (Quote.knownPrice(closes[i]) !== null) bars.push(bar)
    else if (bar.h !== null || bar.l !== null || (Format.isFiniteNumber(bar.v) && bar.v > 0)) unclosed.push(Object.assign(bar, { c: null }))
  }
  bars.sort(function (a, b) { return a.t - b.t })
  if (bars.length >= 2 && bars[bars.length - 1].t === bars[bars.length - 2].t) bars.splice(bars.length - 2, 1)
  // Yahoo opens a new listing's history with its offer price: one price, no
  // shares, at its first day's bell, hours before its first trade.
  var firstTrade = Format.isFiniteNumber(meta.firstTradeDate) ? meta.firstTradeDate : null
  bars = bars.filter(function(b) { return !(b.t === firstTrade && b.v === 0 && b.o === b.c && b.h === b.c && b.l === b.c) })
  var interval = Format.fetchedText(meta.dataGranularity, Format.MOST_CODE) || (spec && spec.interval)
  var intervalSeconds = historyIntervalSeconds(interval)
  // A daily bar never carries a stray close.
  var droppedTimes = []
  if (intervalSeconds > 0 && intervalSeconds < 24 * 60 * 60) {
    var filtered = Quote.filterStrayCloses(bars, null, Quote.answerTick(meta, bars, centExchanges))
    bars = filtered.bars
    droppedTimes = filtered.droppedTimes
  }
  var baseline = Quote.knownPrice(meta.chartPreviousClose) || (bars.length ? bars[0].c : null)
  return {
    symbol: Format.fetchedText(meta.symbol, Format.MOST_CODE),
    range: range,
    interval: interval,
    gmtoffset: Quote.isOffset(meta.gmtoffset) ? meta.gmtoffset : 0,
    zoneName: Format.fetchedText(meta.timezone, Format.MOST_CODE),
    // Each intraday day's clock, and the live moment Yahoo appends at the
    // price's own second.
    clocks: clocks,
    liveAt: Format.isFiniteNumber(meta.regularMarketTime) ? meta.regularMarketTime : null,
    bars: bars,
    unclosed: unclosed,
    baseline: baseline,
    firstTradeDate: firstTrade,
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
  var counted = bars.length ? bars.concat(history.unclosed || []) : []
  for (var i = 0; i < counted.length; i++) {
    var bar = counted[i]
    if (Format.isFiniteNumber(bar.h) && (!high || bar.h > high.p)) high = { p: bar.h, t: bar.t }
    if (Format.isFiniteNumber(bar.l) && (!low || bar.l < low.p)) low = { p: bar.l, t: bar.t }
  }
  var interval = historyIntervalSeconds(history ? history.interval : "")
  var first = bars.length ? bars[0] : null
  var firstTradeDate = history ? history.firstTradeDate : null
  // A young listing's first trade can come hours after its first day's bell.
  var short = !!(first && Format.isFiniteNumber(first.t) && Format.isFiniteNumber(firstTradeDate) && interval > 0
    && first.t <= firstTradeDate + Math.max(interval, 24 * 60 * 60) && first.t + interval >= firstTradeDate)
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

// The line starts at the range's start, where `withStart` adds it, so the
// move reads from its left end to its right. The log scale (5Y up) shows a
// decade's growth as a slope, not a flat line and a wall; every price is
// above zero.
function historyGeometry(history) {
  var bars = drawnBars(history)
  var usable = []
  for (var i = 0; i < bars.length; i++) {
    if (Format.isFiniteNumber(bars[i].t) && Format.isFiniteNumber(bars[i].c)) usable.push(bars[i])
  }
  if (!usable.length) {
    return { points: [], baselineY: null, ticks: [], lo: null, hi: null, start: null, end: null, day: false }
  }
  var spec = HISTORY_RANGES[history.range]
  var baseline = Format.isFiniteNumber(history.baseline) ? history.baseline : usable[0].c
  var log = !!spec && spec.scale === "log"
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
  var bars = drawnBars(history)
  if (!bars.length || !Format.isFiniteNumber(fraction)) return null
  var index = Math.round(Format.clamp(fraction, 0, 1) * (bars.length - 1))
  return bars[index]
}

function historyFraction(history, t) {
  var bars = drawnBars(history)
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

// Intraday bars take Yahoo's periods. Longer bars have none: Yahoo stamps a
// week or month at its first day's midnight by that day's offset, an hour
// off the answer's across a change of clocks. Any other stamp, the live
// moment too (a coin's at 23:00 UTC), keeps the answer's offset. The newest
// price is a trade, not a period, so it keeps the clock it traded by.
function barOffset(history, t) {
  var newest = newestBar(history)
  if (newest && newest.t === t) return newest.clock.offset
  if (history.start && history.start.clock && history.start.t === t) return history.start.clock.offset
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
  var bars = drawnBars(history)
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

function historyStatsDateText(history, t, withYear, interval) {
  var coarse = interval === "1wk" || interval === "1mo" || interval === "3mo"
  return historyDateText(history, t, coarse || withYear, coarse ? "1mo" : "1d")
}

// Yahoo appends the live moment to weekly, monthly and quarterly bars as a
// bar of its own; the bar before it already holds that day, volume included.
function liveBarAppended(history) {
  var bars = history && history.bars ? history.bars : []
  var coarse = history && (history.interval === "1wk" || history.interval === "1mo" || history.interval === "3mo")
  return !!coarse && bars.length > 1 && bars[bars.length - 1].t === history.liveAt
}

// Robinhood's ranges end on the newest price too. It replaces the live
// moment, which also stands for the price now. `clock` is the exchange's at
// that trade (`Market.tradeClock`): the history's may be from before a change
// of clocks.
function withNewest(history, trade, clock) {
  var bars = history.bars
  if (!trade || !bars.length || trade.t <= bars[bars.length - 1].t) return history
  var own = liveBarAppended(history) ? bars.slice(0, -1) : bars
  return Object.assign({}, history, {
    bars: own.concat([{ t: trade.t, o: trade.p, h: trade.p, l: trade.p, c: trade.p, v: null, newest: trade.phase, closed: !!trade.closed, clock: clock }])
  })
}

// The range's line starts at its start, the price its move counts from
// (`baseline`), where Yahoo's first bar doesn't already close on it. That is
// the close before the range, at `closeAt` with the exchange's `clock` where
// its calendar names that day, as 1D names its close; or, for a listing that
// began inside the range, Yahoo's first price for it. Yahoo sends the start
// rounded and the bar's close as a float, so they match to a millionth.
function withStart(history, closeAt, clock) {
  var first = history.bars[0]
  if (!first || !Format.isFiniteNumber(history.baseline) || Math.abs(history.baseline - first.c) <= first.c * 1e-6) return history
  var listed = periodStats(history).coverage.short
  var named = !listed && closeAt !== null
  return Object.assign({}, history, {
    start: { t: named ? closeAt : first.t - 1, c: history.baseline, clock: named ? clock : null, listed: listed }
  })
}

// The bars the line draws: the start, then Yahoo's.
function drawnBars(history) {
  var bars = history && history.bars ? history.bars : []
  return history && history.start ? [history.start].concat(bars) : bars
}

function barClock(history, bar) {
  return bar.newest ? bar.clock : Quote.clockAt(history, bar.t)
}

function newestBar(history) {
  var bars = history && history.bars ? history.bars : []
  return bars.length && bars[bars.length - 1].newest ? bars[bars.length - 1] : null
}

function ownLast(history) {
  return history.bars.length - (liveBarAppended(history) || newestBar(history) ? 2 : 1)
}

function closelessLast(history) {
  var bars = history && history.bars ? history.bars : []
  var open = history && history.unclosed ? history.unclosed : []
  var after = bars.length ? bars[bars.length - 1].t : -Infinity
  var found = null
  for (var i = 0; i < open.length; i++) if (open[i].t > after && (!found || open[i].t > found.t)) found = open[i]
  return found
}

function lastBarHolds(history, t) {
  var bars = history && history.bars ? history.bars : []
  var spans = { "1d": "day", "1wk": "week", "1mo": "month", "3mo": "quarter" }
  var span = spans[history ? history.interval : ""]
  if (!bars.length || !span || !Format.isFiniteNumber(t)) return false
  var closeless = closelessLast(history)
  var start = closeless ? closeless.t : bars[ownLast(history)].t
  var day = historyDateParts(history, t)
  var first = historyDateParts(history, start)
  var days = (Date.UTC(day.year, day.month, day.day) - Date.UTC(first.year, first.month, first.day)) / 86400000
  var months = (day.year - first.year) * 12 + day.month - first.month
  if (span === "day") return days === 0
  if (span === "week") return days >= 0 && days < 7
  return months >= 0 && months < (span === "month" ? 1 : 3)
}

// The range is fetched hourly and the quote each minute, so the quote's day
// high and low stand in for the last bar's while it holds that day.
function rangeEnds(history, stats, quote) {
  stats = stats || periodStats(history)
  if (!stats.high || !stats.low) return null
  var high = stats.high
  var low = stats.low
  if (quote && lastBarHolds(history, quote.figuresDay)) {
    var closeless = closelessLast(history)
    var today = closeless ? closeless.t : history.bars[ownLast(history)].t
    if (Format.isFiniteNumber(quote.dayHigh) && quote.dayHigh > high.p) high = { p: quote.dayHigh, t: today }
    if (Format.isFiniteNumber(quote.dayLow) && quote.dayLow < low.p) low = { p: quote.dayLow, t: today }
  }
  return { high: high, low: low }
}

function rangeVolume(history) {
  var bars = history && history.bars ? history.bars : []
  var end = bars.length ? ownLast(history) + 1 : 0
  var counted = bars.slice(0, end).concat(end > 0 && history.unclosed ? history.unclosed : [])
  var sum = 0
  for (var i = 0; i < counted.length; i++) {
    if (!Format.isFiniteNumber(counted[i].v)) return ""
    sum += counted[i].v
  }
  return sum > 0 ? Format.compactNumber(sum) : ""
}

function rangeFacts(widest, start, volume) {
  return [
    { label: "START", value: start || "", widest: widest },
    { label: "VOL", value: volume || "", widest: Format.widest("999.9M") }
  ]
}

function rangeLine(history, ends, quote) {
  if (!ends) return null
  var digits = quote ? quote.priceDigits : undefined
  var head = quote ? Quote.headlineQuote(quote) : null
  var last = history.bars[history.bars.length - 1]
  var range = Format.infoRange(ends.low.p, ends.high.p, !newestBar(history) && head ? head.price : last.c, digits)
  var start = Format.isFiniteNumber(history.baseline) ? Format.money(history.baseline, digits) : ""
  return {
    title: String(history.range || "").toUpperCase(),
    range: range,
    facts: rangeFacts(range.widest, start, rangeVolume(history))
  }
}

// The line each range held for a symbol would show under its chart, so the
// info table keeps room for all of them and a change of range moves nothing.
function heldLines(histories, symbol, quote) {
  var lines = []
  Object.keys(HISTORY_RANGES).forEach(function(range) {
    var entry = histories[historyKey(symbol, range)]
    var line = entry && entry.history ? rangeLine(entry.history, rangeEnds(entry.history, null, quote), quote) : null
    if (line) lines.push(line)
  })
  return lines
}

function rangeMarks(history, ends, quote) {
  if (!ends) return null
  var digits = quote ? quote.priceDigits : undefined
  var years = historySpansYears(history)
  var drawnTo = history.bars[history.bars.length - 1].t
  var mark = function(point) {
    return {
      x: point.t > drawnTo ? 1 : historyFraction(history, point.t),
      price: Format.money(point.p, digits),
      date: historyStatsDateText(history, point.t, years, history.interval)
    }
  }
  return { high: mark(ends.high), low: mark(ends.low) }
}

// A range bar's day as its scrub and its screenshot name it, with the clock
// of a bar that has a time: `{ date, clock }`, `clock` null for a day's bar.
// The start is the close before the range, by its own day where the
// calendar names it, or as the close before the first bar; or a listing's
// first day.
function barDay(history, bar) {
  var years = historySpansYears(history)
  var timed = !!bar.newest || history.interval === "15m" || history.interval === "30m" || history.interval === "1h"
  if (bar === history.start) {
    if (bar.clock) return { date: historyDateText(history, bar.t, years, "1d"), clock: timed ? bar.clock : null }
    if (bar.listed) return { date: historyDateText(history, history.firstTradeDate, years, "1d"), clock: null }
    return { date: "CLOSE BEFORE " + historyDateText(history, history.bars[0].t, years, "1d"), clock: null }
  }
  var date = historyDateText(history, bar.t, years, bar.newest ? "1d" : history.interval)
  if (history.interval === "1wk" && !bar.newest) date = "WEEK OF " + date
  return { date: date, clock: timed ? barClock(history, bar) : null }
}

// The date alone is for a header with no room: the hero shows the price.
function historyScrubForms(history, bar, digits) {
  if (!history || !bar) return [""]
  var day = barDay(history, bar)
  var date = day.clock ? day.date + " " + Format.zonedHhmm(bar.t, day.clock.offset, day.clock.zone) : day.date
  return [date + " · " + Format.money(bar.c, digits), date]
}

function historyRowModel(history, quote, scrubT) {
  if (!history) return null
  var stats = periodStats(history)
  var bar = scrubT ? historyBarAt(history, historyFraction(history, scrubT)) : null
  var tail = bar ? null : newestBar(history)
  var head = !bar && !tail && quote ? Quote.headlineQuote(quote) : null
  var price = bar && Format.isFiniteNumber(bar.c) ? bar.c
    : tail ? tail.c : (head ? head.price : stats.last)
  var chg = Quote.change({ prevClose: history.baseline, points: [] }, price, "pct")
  return {
    symbol: history.symbol || (quote ? quote.symbol : ""),
    name: quote ? quote.name : (history.symbol || ""),
    price: price,
    priceText: Format.money(price, quote ? quote.priceDigits : undefined),
    asOf: bar ? bar.t : tail ? tail.t : (head ? head.t : stats.coverage.to),
    pct: chg.pct,
    abs: chg.abs,
    unit: "pct",
    tone: Format.changeTone(chg, "pct"),
    dayUp: chg.pct === null ? null : chg.up,
    dayTone: Format.changeTone(chg, "pct"),
    changeText: Format.pct(chg.pct),
    changeLine: Format.pct(chg.pct),
    // Said under the change, as the day's move names its day
    // (`Figures.heroLines`).
    periodLabel: stats.coverage.short && history.range !== "All"
      ? "SINCE " + historyStatsDateText(history, history.firstTradeDate, true, "1d")
      : String(history.range || "").toUpperCase(),
    newest: tail ? { t: tail.t, p: tail.c, phase: tail.newest, closed: tail.closed } : null
  }
}
