.pragma library
.import "Format.js" as Format
.import "Quote.js" as Quote

// Cap and P/E: Yahoo's dated cap snapshots and its close, trailing
// earnings, the rate between two currencies a P/E may need, and the
// 52-week line. Knows nothing of sessions or charts.

var FUNDAMENTALS_URL = "https://query1.finance.yahoo.com/ws/fundamentals-timeseries/v1/finance/timeseries/"

// Yahoo keeps a listing's cap as dated snapshots: its own, weeks or months
// apart (once ten months), and one at each quarter's end; 400 days reaches
// the latest of each.
var FUNDAMENTALS_DAYS = 400

// A cap snapshot older than this, against the price, is too stale to move:
// a quarter's end is in the answer about 45 days after it, and a half-yearly
// reporter's own snapshot can be six months old.
var CAP_MAX_AGE_DAYS = 200

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
  return FUNDAMENTALS_URL + encodeURIComponent(symbol) + "?type=trailingMarketCap,quarterlyMarketCap,trailingDilutedEPS"
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

// Yahoo's latest cap and trailing diluted EPS, each with its own date and
// currency; null when the answer is not a timeseries, or its series are not
// a list within MOST_SERIES. The cap is the newer of Yahoo's own snapshot
// and the last quarter's end. The EPS stands only while it is above zero:
// after a loss there is no P/E.
function parseFundamentals(json) {
  var results = Format.fetchedList(json && json.timeseries && json.timeseries.result, MOST_SERIES)
  if (!results) return null
  var own = latestSnapshot(results, "trailingMarketCap")
  var quarter = latestSnapshot(results, "quarterlyMarketCap")
  var cap = !quarter || (own && own.date >= quarter.date) ? own : quarter
  var eps = latestSnapshot(results, "trailingDilutedEPS")
  return {
    cap: cap && cap.value > 0 ? cap : null,
    eps: eps && eps.value > 0 ? eps : null
  }
}

// "2026-09-23" as the epoch of its midnight, UTC.
function dateEpoch(date) {
  var parts = String(date || "").split("-")
  return Date.UTC(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])) / 1000
}

// The cap was taken at its date's close, so that close is what moves it
// with the price since. The daily bars around the cap's date, with a week
// before for holidays; null when there is no cap.
function capCloseUrl(symbol, figures) {
  if (!figures.cap) return null
  return Quote.CHART_URL + encodeURIComponent(symbol) + "?interval=1d&period1=" + (dateEpoch(figures.cap.date) - 7 * 24 * 60 * 60)
    + "&period2=" + (dateEpoch(figures.cap.date) + 2 * 24 * 60 * 60)
}

// The figures with the cap's close: the last session's on or before its
// date, in the exchange's calendar. Null when the answer is not a chart,
// its bars are not lists within `Quote.MOST_BARS` stamped at moments
// (`Format.isMoment`), or it lacks the cap's close: no answer, so the feed
// keeps what it had.
function withCapClose(figures, json) {
  var result = json && json.chart && json.chart.result && json.chart.result[0]
  if (!result || !result.meta) return null
  var times = Format.fetchedList(result.timestamp || [], Quote.MOST_BARS)
  var bars = result.indicators && result.indicators.quote && result.indicators.quote[0]
  var closes = Format.fetchedList(bars && bars.close ? bars.close : [], Quote.MOST_BARS)
  if (!times || !closes) return null
  var offset = result.meta.gmtoffset || 0
  var close = null
  for (var i = 0; i < times.length; i++) {
    if (!Format.isMoment(times[i] + offset)) return null
    var day = new Date((times[i] + offset) * 1000).toISOString().slice(0, 10)
    if (day <= figures.cap.date && Quote.knownPrice(closes[i]) !== null) close = closes[i]
  }
  return close === null ? null : Object.assign({}, figures, { cap: Object.assign({}, figures.cap, { close: close }) })
}

// A price's currency in whole units: London quotes pence, "GBp", against
// earnings in pounds.
function wholeUnits(currency) {
  return currency === "GBp" ? { currency: "GBP", per: 100 } : { currency: String(currency || ""), per: 1 }
}

// The pair whose rate turns the EPS into the price's currency, as Yahoo
// names it ("USDCAD", from USD into CAD); "" when the two are the same or
// either is not a plain three-letter code, as a price in another small
// unit (ZAc) is not: then there is no P/E rather than one off by a hundred.
function ratePair(figures, currency) {
  var eps = figures && figures.eps
  var into = wholeUnits(currency).currency
  if (!eps || eps.currency === into) return ""
  return /^[A-Z]{3}$/.test(eps.currency) && /^[A-Z]{3}$/.test(into) ? eps.currency + into : ""
}

// Yahoo's latest rate for a pair, on the chart endpoint quotes use.
function rateUrl(pair) {
  return Quote.CHART_URL + encodeURIComponent(pair + "=X") + "?range=1d&interval=1d"
}

// The rate in a pair's answer: units of the second currency to one of the
// first. Null unless the answer names that pair and that currency, and the
// rate is a number above zero.
function parseRate(json, pair) {
  var meta = json && json.chart && json.chart.result && json.chart.result[0] && json.chart.result[0].meta
  if (!meta || meta.symbol !== pair + "=X" || meta.currency !== pair.slice(3)) return null
  var rate = meta.regularMarketPrice
  return Format.isFiniteNumber(rate) && rate > 0 ? rate : null
}

// The headline price over the EPS in the price's currency, or null. The EPS
// in another currency counts only at its pair's rate, from `rates`: by pair,
// { value, checkedAt }, value null after a failed fetch.
function peRatio(figures, price, currency, rates) {
  var eps = figures ? figures.eps : null
  if (!eps) return null
  var units = wholeUnits(currency)
  var held = rates ? rates[ratePair(figures, currency)] : null
  var rate = eps.currency && eps.currency === units.currency ? 1 : held ? held.value : null
  return rate ? price / units.per / (eps.value * rate) : null
}

function peText(value) {
  return value < 100 ? value.toFixed(1) : Format.grouped(String(Math.round(value)))
}

// The info block's second line, on every range: the 52-week range with the
// price's place in it, then the cap and the P/E, each only when known. A
// day past Yahoo's 52-week mark widens the range to it, so the day's high
// and the year's read the same, both in the up tone (the low in the down
// tone). On 1Y the range's own low and high (`yearEnds`, the 1Y range's
// `History.rangeEnds`, else null) widen it too, so the two lines never
// disagree: Yahoo's 52 weeks leave out the 1Y range's first day. A longer
// range never does, its ends can be older than a year. They are compared
// at the listing's decimals, so a bar's float noise never passes a mark it
// reads as. A day only takes the tone while its end is the one shown. The
// cap moves with the headline price from its own date's close; a cap more
// than CAP_MAX_AGE_DAYS whole days older than the price is left out. The
// P/E is the headline price over the latest EPS, at its pair's rate in
// `rates` where it needs one (`peRatio`). The cap names its currency
// wherever Yahoo does, so one in yen never reads as one in dollars beside
// it, whatever the reader's own; a London cap is in GBP while its prices
// are in GBp.
// Only an equity has cap and P/E slots, kept whether known or not, so the
// line keeps its shape: the cap's as wide as its currency and 999.9B before
// the cap comes; the P/E's as wide as 99.9.
function yearLine(quote, figures, yearEnds, rates) {
  if (!quote) return null
  var q = quote
  var head = Quote.headlineQuote(q)
  var both = Format.isFiniteNumber(q.fiftyTwoWeekLow) && Format.isFiniteNumber(q.fiftyTwoWeekHigh)
  var atHigh = both && Format.isFiniteNumber(q.dayHigh) && q.dayHigh >= q.fiftyTwoWeekHigh
  var atLow = both && Format.isFiniteNumber(q.dayLow) && q.dayLow <= q.fiftyTwoWeekLow
  var low = both ? (atLow ? q.dayLow : q.fiftyTwoWeekLow) : null
  var high = both ? (atHigh ? q.dayHigh : q.fiftyTwoWeekHigh) : null
  var reads = function(v) { return Number(v.toFixed(Format.isFiniteNumber(q.priceDigits) ? q.priceDigits : Format.moneyDigits(Math.abs(v)))) }
  if (both && yearEnds && reads(yearEnds.low.p) < reads(low)) {
    low = yearEnds.low.p
    atLow = false
  }
  if (both && yearEnds && reads(yearEnds.high.p) > reads(high)) {
    high = yearEnds.high.p
    atHigh = false
  }
  var line = Format.infoRange(low, high, head ? head.price : null, q.priceDigits)
  if (atHigh) line.highTone = "up"
  if (atLow) line.lowTone = "down"
  var facts = []
  if (hasFundamentals(q)) {
    var cap = figures ? figures.cap : null
    var pe = head ? peRatio(figures, head.price, q.currency, rates) : null
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
    facts.push({ label: "P/E", value: pe !== null ? peText(pe) : "", widest: Format.widest("99.9") })
  }
  return { title: "52W", range: line, facts: facts }
}
