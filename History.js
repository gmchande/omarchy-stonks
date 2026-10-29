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

// A range's history in the cache, and in what the service asks of it, by
// its symbol and range.
function historyKey(symbol, range) {
  return String(symbol || "").toUpperCase() + "|" + String(range || "")
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
// them, for the stray filter's tick. Null, as there, for an answer that is
// not a chart, whose bars or periods are not lists within Quote's budgets,
// whose periods are not periods (`Quote.answerClocks`), or whose bar times
// are not moments; an offset that is not one is none. A price at or under
// zero is none, as in the day's answer (`Quote.knownPrice`): a bar without a
// close is left out of `bars`, which the chart draws, and its START is its
// first close when its previous close isn't known. Read as prices, zeros
// would put "START 0.00" on screen, and a negative first close would draw
// a cliff at the chart's left. A bar without a close that has a high, a
// low, or shares is kept in `unclosed`, for the range's high, low, and
// volume: Tokyo's daily answer leaves the day's close out after its close,
// and without it its VOL and high would lose what Yahoo sent.
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
  // A new listing's history opens with its offer price: a bar at
  // the bell of its first day (`firstTradeDate`), one price and no shares,
  // hours before its first trade. That bar is dropped: kept, a young
  // listing's 1W and 1M would plunge to its offer price at the left edge
  // and name it the range's low.
  var firstTrade = Format.isFiniteNumber(meta.firstTradeDate) ? meta.firstTradeDate : null
  bars = bars.filter(function(b) { return !(b.t === firstTrade && b.v === 0 && b.o === b.c && b.h === b.c && b.l === b.c) })
  var interval = Format.fetchedText(meta.dataGranularity, Format.MOST_CODE) || (spec && spec.interval)
  var intervalSeconds = historyIntervalSeconds(interval)
  // Only intraday buckets carry a stray close; a daily bar cannot. A move of
  // a tick or two is trading (`Quote.filterStrayCloses`).
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
    // An intraday answer's days, each with its own clock, and the live
    // moment Yahoo appends, at the price's own second (`barOffset`).
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

// A range's last close, its change, and its high and low, each a bar's
// `{ p, t }`, from its bars and those without a close (`unclosed`), whose
// high and low Yahoo did send; none with no bar drawn.
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
  // The range starts with the listing when its first bar is on its first
  // day of trading, or in the bar that holds it: a young listing's first
  // trade can come hours after its first day's bell.
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

// Normalized x/y for a range: bars evenly spaced, and a vertical range that
// holds every close and the period's starting price the change is measured
// from, with headroom. From 5Y up the scale is logarithmic, so a decade of
// growth reads as a slope instead of a flat line and a wall: every price
// is above zero (`parseHistory`).
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

// Whether the last bar is the live moment (`liveAt`) Yahoo appends to a
// week's, a month's, or a quarter's bars as a bar of its own: the bucket
// before it already holds the live moment's day, its volume included.
function liveBarAppended(history) {
  var bars = history && history.bars ? history.bars : []
  var coarse = history && (history.interval === "1wk" || history.interval === "1mo" || history.interval === "3mo")
  return !!coarse && bars.length > 1 && bars[bars.length - 1].t === history.liveAt
}

// `history` ending on the newest price since the listing's regular close
// (`print`, { t, p, phase }, `Overnight.newestPrint`), as Robinhood's ranges
// end on it: a bar of its own after the last, or in place of the live moment
// Yahoo appends to a week's, a month's, or a quarter's bars, which stands
// for the price now too. The bar is that one trade, so it counts in the
// range's low and high, where the line reaches it, and not in its volume
// (`rangeVolume`), as the day's VOL leaves out the night. The history as it
// came with no print after its last bar.
function withNewest(history, print) {
  var bars = history.bars
  if (!print || !bars.length || print.t <= bars[bars.length - 1].t) return history
  var own = liveBarAppended(history) ? bars.slice(0, -1) : bars
  return Object.assign({}, history, {
    bars: own.concat([{ t: print.t, o: print.p, h: print.p, l: print.p, c: print.p, v: null, newest: print.phase }])
  })
}

// The bar `withNewest` ended `history` on, or null.
function newestBar(history) {
  var bars = history && history.bars ? history.bars : []
  return bars.length && bars[bars.length - 1].newest ? bars[bars.length - 1] : null
}

// The index of the last bar of Yahoo's own: before an appended live moment
// (`liveBarAppended`), whose day the bucket before it holds, or the newest
// price (`newestBar`).
function ownLast(history) {
  return history.bars.length - (liveBarAppended(history) || newestBar(history) ? 2 : 1)
}

// A bar without a close (`unclosed`) after every bar drawn: Tokyo's day,
// after its close, before Yahoo's answer has its close. Null with none.
function closelessLast(history) {
  var bars = history && history.bars ? history.bars : []
  var open = history && history.unclosed ? history.unclosed : []
  var after = bars.length ? bars[bars.length - 1].t : -Infinity
  var found = null
  for (var i = 0; i < open.length; i++) if (open[i].t > after && (!found || open[i].t > found.t)) found = open[i]
  return found
}

// Whether the last bar of a range of bars a day long or longer holds the
// session that starts at `t` (`Quote.figuresDay`), by the exchange's
// calendar: a day's bar is that day's, a week's bar the seven days from its
// first, a month's its month. The last bar is one without a close after
// those drawn (`closelessLast`), else the last of Yahoo's own (`ownLast`).
// An intraday bar holds only part of a day.
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

// A range's high and low, each a bar's `{ p, t }`. When the last bar holds
// the session of the listing's `quote`, the quote's day high and low count
// as that bar's: the range is fetched each hour, the quote each minute, so
// on a day that passes the range's high, the range keeps up with the day's
// line and the 52 weeks' (`Figures.dayLine`, `Fundamentals.yearLine`).
// Null with no bars.
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

// What traded over a range: its bars' volumes added, those without a close
// too (`unclosed`), as the day's VOL reads (`Format.compactNumber`). An
// appended live moment is left out, since the bucket before it counts its
// day, and so is the newest price (`withNewest`). "" when any counted bar's
// volume isn't known, or when none is above zero, as for an index Yahoo has
// no volume for.
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

// A range line's facts, in the day line's places (`Figures.dayLine`): START,
// the price the range's change is measured from, which the scrub's dashed
// line names too, and VOL, what traded over it (`rangeVolume`). `widest` is
// the widest price of the listing's at its decimals; each value is "" when
// not known, as in the room the info table holds for them.
function rangeFacts(widest, start, volume) {
  return [
    { label: "START", value: start || "", widest: widest },
    { label: "VOL", value: volume || "", widest: Format.widest("999.9M") }
  ]
}

// The info block's first line on a range, in the day line's shape: the
// range's name, its low and high (`rangeEnds`) with the price on top's
// place between them, where its line ends: the newest price
// (`withNewest`), else the headline's, else the last bar's close. Then its
// facts (`rangeFacts`). The dates of the low and high are on the chart's
// marks (`rangeMarks`). Null with no bars.
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

// A range's high and low (`rangeEnds`), marked on its chart (`RangeMarks`):
// each where its bar sits along the chart, 0..1, as the scrub places a bar
// (`historyFraction`), its price at the listing's decimals, and its date.
// One made after the last bar drawn, on a bar without a close
// (`closelessLast`), stands at the chart's right edge, where that day is.
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

// A scrubbed bar as the header says it, its date and its price, then its
// date alone, for a header with no room for both: the hero shows the price
// large. An intraday bar's date and time read by its own day's clock, so a
// time across a change of clocks reads as the exchange's clock said then;
// the newest price (`withNewest`) is a trade, named by its day and time on
// every range.
function historyScrubForms(history, bar, digits) {
  if (!history || !bar) return [""]
  var years = historySpansYears(history)
  var date = historyDateText(history, bar.t, years, bar.newest ? "1d" : history.interval)
  if (history.interval === "1wk" && !bar.newest) date = "WEEK OF " + date
  if (bar.newest || history.interval === "15m" || history.interval === "30m" || history.interval === "1h") {
    var clock = Quote.clockAt(history, bar.t)
    date += " " + Format.zonedHhmm(bar.t, clock.offset, clock.zone)
  }
  return [date + " · " + Format.money(bar.c, digits), date]
}

// The range's price and move, as the hero shows it: a scrubbed bar's, else
// the price on top, the newest since the close where the line ends on it
// (`newestBar`), its session and time said after the range's name
// (`newest`), else the headline's. Each measured from the
// range's start (`baseline`).
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
    tone: Format.changeTone(chg, "pct"),
    dayUp: chg.pct === null ? null : chg.up,
    dayTone: Format.changeTone(chg, "pct"),
    changeText: Format.pct(chg.pct),
    changeLine: Format.pct(chg.pct),
    // What the change is measured over, said under it the way AT CLOSE is:
    // the range, or, for a listing younger than a range short of All, the
    // day it began trading. With the newest price on top, its session and
    // time follow (`Figures.newestCaptions`).
    periodLabel: stats.coverage.short && history.range !== "All"
      ? "SINCE " + historyStatsDateText(history, history.firstTradeDate, true, "1d")
      : String(history.range || "").toUpperCase(),
    newest: tail ? { t: tail.t, p: tail.c, phase: tail.newest } : null
  }
}
