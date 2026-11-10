.pragma library
.import "Chart.js" as Chart
.import "Figures.js" as Figures
.import "Format.js" as Format
.import "History.js" as History
.import "Market.js" as Market
.import "Quote.js" as Quote

// What the screenshot says, in Stonks' own words: every figure is one Stonks
// already shows or knows. The picture outlives the reader's clock, so its
// times always name their zone. Knows nothing of drawing or of files.

// Its axis ends at the newest print, so a picture taken at 16:03 has no empty
// evening.
function pictureDay(day) {
  if (!day || !day.points.length) return day
  var axis = Chart.chartSpan(day)
  var newest = day.points[day.points.length - 1].t
  return Object.assign({}, day, { axis: Object.assign({}, axis, { end: Math.max(axis.start, newest) }) })
}

// By the calendar that knows that day's clock (`Market.tradeClock`), else
// by Yahoo's.
function local(quote, t, calendars) {
  var at = Market.tradeClock(quote, t, calendars)
  var d = new Date((t + at.offset) * 1000)
  return { y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate(), weekday: d.getUTCDay(),
    clock: Format.hhmm(t, at.offset), zone: at.zone || Format.offsetName(at.offset) }
}

// "16:00 EDT".
function clockOf(quote, t, calendars) {
  var l = local(quote, t, calendars)
  return l.clock + " " + l.zone
}

// "TUE 20 OCT 2026".
function dateOf(quote, t, calendars) {
  var l = local(quote, t, calendars)
  return Format.WEEKDAYS[l.weekday].toUpperCase() + " " + l.d + " " + Format.MONTHS[l.m - 1] + " " + l.y
}

// As a scrub at the bell reads it (`Quote.readingAt`); a cryptocurrency has no
// close.
function headlineIsClose(quote) {
  var head = Quote.headlineQuote(quote)
  var reg = quote.session.regular
  return !quote.crypto && !!head && head.source === "quote" && !!reg && head.t >= reg.end
}

// For a range's bar, the bar: the scrubbed one, or with no headline the last,
// whose close the range then shows.
function moment(o) {
  if (o.history && o.scrubT) {
    var bar = History.historyBarAt(o.history, History.historyFraction(o.history, o.scrubT))
    if (bar) return { t: bar.t, close: false, bar: bar }
  }
  if (!o.history && o.scrubT) {
    var read = Quote.readingAt(o.day, o.scrubT)
    return { t: read.t, close: read.close, bar: null }
  }
  // At rest, the newest price since the close where it is on top, on the day
  // and on a range, whose line ends on it.
  if (o.newest) return { t: o.newest.t, close: false, bar: null }
  var head = Quote.headlineQuote(o.quote)
  if (!head && o.history) {
    var last = History.historyBarAt(o.history, 1)
    if (last) return { t: last.t, close: false, bar: last }
  }
  var close = headlineIsClose(o.quote)
  return { t: close ? o.quote.session.regular.end : head ? head.t : 0, close: close, bar: null }
}

// As its scrub names it (`History.historyScrubForms`), a time always with its
// zone, and without the price, which the picture shows large.
function barDate(history, bar) {
  var day = History.barDay(history, bar)
  var clock = day.clock
  return clock ? day.date + " " + Format.hhmm(bar.t, clock.offset) + " " + (clock.zone || Format.offsetName(clock.offset)) : day.date
}

// The picture's words beyond the panel's two lines (`Figures.heroLines`),
// which it draws as the panel does, from what the surface shows (`newest`
// is the price on top at rest; `scrubT` is 0 at rest):
//   foot: when the price on top is from, with its date, since the picture
//   outlives the reader's clock: WED 7 OCT 2026 · 00:50 EDT, a close as
//   CLOSE 16:00 EDT, and a range's bar by its own date;
//   open: since the open on the day, the open the move counts from, which
//   the panel says under its ranges and the picture has no room for, in
//   place of the line under the price: OPEN 153.97. Null where the move
//   doesn't count from an open, or the open isn't known;
//   currency: none beside an index's level, which isn't money;
//   start, end: the day's axis's ends;
//   said: the moment in the notification's words.
function words(o) {
  var quote = o.quote
  var at = moment(o)
  var out = { foot: "", open: null, start: "", end: "", said: "",
    currency: quote.instrumentType === "INDEX" ? "" : Figures.currencyLabel(String(quote.currency || "")) }
  if (o.changeMode === "open" && !o.history) {
    var base = o.scrubT ? Figures.scrubbedBase(o.day, o.scrubT, o.newest || null) : Quote.restingRead(quote, o.newest || null).base
    if (Format.isFiniteNumber(base.dayOpen)) out.open = { label: "OPEN", price: Format.money(base.dayOpen, quote.priceDigits) }
  }
  if (at.bar) {
    out.foot = barDate(o.history, at.bar)
    out.said = "on " + out.foot
  } else if (at.t) {
    out.foot = dateOf(quote, at.t, o.calendars) + " · " + (at.close ? "CLOSE " : "") + clockOf(quote, at.t, o.calendars)
    out.said = at.close ? "at the close" : "at " + Market.printClock(quote, at.t, o.calendars)
  }
  var pts = o.history ? [] : o.day.points
  if (pts.length) {
    var axis = Chart.chartSpan(pictureDay(o.day))
    var first = local(o.day, axis.start, o.calendars)
    var last = local(o.day, pts[pts.length - 1].t, o.calendars)
    out.start = first.clock
    // A chart that runs into the next morning names the weekday it ends on.
    out.end = (last.d !== first.d ? Format.WEEKDAYS[last.weekday].toUpperCase() + " " : "") + last.clock
  }
  return out
}

// "AAPL at the close", "AAPL 1Y on 3 AUG 2026".
function subject(symbol, range, said) {
  return symbol + (range && range !== "1D" ? " " + range : "") + (said ? " " + said : "")
}

// So no symbol can name another folder or carry a character a shell or a file
// manager reads.
function fileSymbol(symbol) {
  return String(symbol).toLowerCase().replace(/[^a-z0-9.-]/g, "").slice(0, 32) || "chart"
}
