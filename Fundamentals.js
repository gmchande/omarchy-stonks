.pragma library
.import "Format.js" as Format
.import "Quote.js" as Quote

// Cap and P/E: Yahoo's dated snapshots, their closes, and the 52-week
// line. Knows nothing of sessions or charts.

var FUNDAMENTALS_URL = "https://query1.finance.yahoo.com/ws/fundamentals-timeseries/v1/finance/timeseries/"

// Yahoo keeps a listing's cap and P/E as dated snapshots, weeks or months
// apart (once ten months); 400 days reaches the latest.
var FUNDAMENTALS_DAYS = 400

// A cap snapshot older than this, against the price, is too stale to move.
var CAP_MAX_AGE_DAYS = 120

// The most entries a list in a cap and P/E answer may hold
// (`Format.fetchedList`): a series for each of the three types asked, three
// in the saved answers; and a series' snapshots, four in the saved answers,
// at most one a day over the FUNDAMENTALS_DAYS asked, both ends counted.
var MOST_SERIES = 12
var MOST_SNAPSHOTS = FUNDAMENTALS_DAYS + 1

// Only an equity has a cap or a P/E: Yahoo sends an ETF, an index, or a
// cryptocurrency none.
function hasFundamentals(quote) {
  return !!quote && quote.instrumentType === "EQUITY"
}

function fundamentalsUrl(symbol, now) {
  return FUNDAMENTALS_URL + encodeURIComponent(symbol) + "?type=trailingMarketCap,trailingPeRatio,trailingDilutedEPS"
    + "&period1=" + (now - FUNDAMENTALS_DAYS * 24 * 60 * 60) + "&period2=" + now
}

// The latest dated value of one series: { value, date, currency }, or null,
// also when `results`, or the series, is not a list within its budget.
function latestSnapshot(results, type) {
  var latest = null
  var all = Format.fetchedList(results, MOST_SERIES) || []
  for (var i = 0; i < all.length; i++) {
    var meta = all[i] && all[i].meta
    if (!meta || !meta.type || meta.type[0] !== type) continue
    var series = Format.fetchedList(all[i][type] || [], MOST_SNAPSHOTS) || []
    for (var j = 0; j < series.length; j++) {
      var point = series[j]
      var value = point && point.reportedValue ? point.reportedValue.raw : null
      var date = point ? Format.fetchedText(point.asOfDate, Format.MOST_CODE) : ""
      if (!Format.isFiniteNumber(value) || !date) continue
      if (!latest || date > latest.date)
        latest = { value: value, date: date, currency: Format.fetchedText(point.currencyCode, Format.MOST_CODE) }
    }
  }
  return latest
}

// Yahoo's latest cap and P/E, each with its own date; null when the answer
// is not a timeseries, or its series are not a list within MOST_SERIES. The
// P/E stands only while the latest trailing diluted EPS is above zero: after
// a loss Yahoo publishes no new P/E, and its last one describes earnings
// that are gone.
function parseFundamentals(json) {
  var results = Format.fetchedList(json && json.timeseries && json.timeseries.result, MOST_SERIES)
  if (!results) return null
  var cap = latestSnapshot(results, "trailingMarketCap")
  var pe = latestSnapshot(results, "trailingPeRatio")
  var eps = latestSnapshot(results, "trailingDilutedEPS")
  return {
    cap: cap && cap.value > 0 ? cap : null,
    pe: pe && pe.value > 0 && eps && eps.value > 0 ? { value: pe.value, date: pe.date } : null
  }
}

// "2026-09-23" as the epoch of its midnight, UTC.
function dateEpoch(date) {
  var parts = String(date || "").split("-")
  return Date.UTC(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])) / 1000
}

function snapshotDates(figures) {
  return [figures.cap, figures.pe].filter(function(s) { return !!s }).map(function(s) { return s.date }).sort()
}

// Each snapshot was taken at its date's close, so that close is what moves
// it with the price since. The daily bars around the snapshots' dates, with
// a week before for holidays; null when there is no snapshot.
function snapshotClosesUrl(symbol, figures) {
  var dates = snapshotDates(figures)
  if (!dates.length) return null
  return Quote.CHART_URL + encodeURIComponent(symbol) + "?interval=1d&period1=" + (dateEpoch(dates[0]) - 7 * 24 * 60 * 60)
    + "&period2=" + (dateEpoch(dates[dates.length - 1]) + 2 * 24 * 60 * 60)
}

// The figures with each snapshot's close: the last session's on or before
// its date, in the exchange's calendar. Null when the answer is not a chart,
// its bars are not lists within `Quote.MOST_BARS` stamped at moments
// (`Format.isMoment`), or it lacks a snapshot's close: no answer, so the
// feed keeps what it had.
function withSnapshotCloses(figures, json) {
  var result = json && json.chart && json.chart.result && json.chart.result[0]
  if (!result || !result.meta) return null
  var times = Format.fetchedList(result.timestamp || [], Quote.MOST_BARS)
  var bars = result.indicators && result.indicators.quote && result.indicators.quote[0]
  var closes = Format.fetchedList(bars && bars.close ? bars.close : [], Quote.MOST_BARS)
  if (!times || !closes) return null
  var offset = result.meta.gmtoffset || 0
  var withClose = function(snapshot) {
    if (!snapshot) return null
    var close = null
    for (var i = 0; i < times.length; i++) {
      if (!Format.isMoment(times[i] + offset)) return null
      var day = new Date((times[i] + offset) * 1000).toISOString().slice(0, 10)
      if (day <= snapshot.date && Quote.knownPrice(closes[i]) !== null) close = closes[i]
    }
    return close === null ? null : Object.assign({}, snapshot, { close: close })
  }
  var cap = withClose(figures.cap)
  var pe = withClose(figures.pe)
  if ((figures.cap && !cap) || (figures.pe && !pe)) return null
  return { cap: cap, pe: pe }
}

function peText(value) {
  return value < 100 ? value.toFixed(1) : Format.grouped(String(Math.round(value)))
}

// The info block's second line, the same on every range: the 52-week range
// with the price's place in it, then the cap and the P/E, each only when
// known. A day past Yahoo's 52-week mark widens the range to it, so the
// day's high and the year's read the same, both in the up tone (the low in
// the down tone). A range's own low and high are its chart's marks
// (`History.rangeMarks`), never this line's, though Yahoo's 52 weeks leave
// out the 1Y range's first day. The cap and the P/E move with the headline
// price from their own date's close; a cap more than CAP_MAX_AGE_DAYS whole
// days older than the price is left out. The cap names its currency
// wherever Yahoo does, so one in yen never reads as one in dollars beside
// it, whatever the reader's own; a London cap is in GBP while its prices
// are in GBp.
// Only an equity has cap and P/E slots, kept whether known or not, so the
// line keeps its shape: the cap's as wide as its currency and 999.9B before
// the cap comes; the P/E's as wide as 99.9.
function yearLine(quote, figures) {
  if (!quote) return null
  var q = quote
  var head = Quote.headlineQuote(q)
  var both = Format.isFiniteNumber(q.fiftyTwoWeekLow) && Format.isFiniteNumber(q.fiftyTwoWeekHigh)
  var atHigh = both && Format.isFiniteNumber(q.dayHigh) && q.dayHigh >= q.fiftyTwoWeekHigh
  var atLow = both && Format.isFiniteNumber(q.dayLow) && q.dayLow <= q.fiftyTwoWeekLow
  var low = both ? (atLow ? q.dayLow : q.fiftyTwoWeekLow) : null
  var high = both ? (atHigh ? q.dayHigh : q.fiftyTwoWeekHigh) : null
  var line = Format.infoRange(low, high, head ? head.price : null, q.priceDigits)
  if (atHigh) line.highTone = "up"
  if (atLow) line.lowTone = "down"
  var facts = []
  if (hasFundamentals(q)) {
    var cap = figures ? figures.cap : null
    var pe = figures ? figures.pe : null
    // A currency code is three letters, the listing's in capitals until the
    // cap's own is known; with none named, the cap says none.
    var named = cap ? cap.currency : String(q.currency || "").toUpperCase()
    var code = named ? named + " " : ""
    facts.push({
      label: "MKT CAP",
      value: head && cap && Math.floor((head.t - dateEpoch(cap.date)) / (24 * 60 * 60)) <= CAP_MAX_AGE_DAYS
        ? code + Format.compactNumber(cap.value * head.price / cap.close) : "",
      widest: code + Format.widest("999.9B")
    })
    facts.push({ label: "P/E", value: head && pe ? peText(pe.value * head.price / pe.close) : "", widest: Format.widest("99.9") })
  }
  return { title: "52W", range: line, facts: facts }
}
