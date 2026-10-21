.pragma library
.import "Chart.js" as Chart
.import "Figures.js" as Figures
.import "Format.js" as Format
.import "History.js" as History
.import "Market.js" as Market
.import "Quote.js" as Quote

// What the screenshot says: the picture's line of facts, what its change is
// measured from, its axis's ends, the footer's words, and
// the file's name. Every figure is one Stonks already shows or knows, in
// its own words. The picture leaves the reader's clock behind, so its
// times always name their zone. Knows nothing of drawing or of files.

// The day as the picture draws it: the 1D chart's day, its axis ending at
// its newest print, so a picture taken at 16:03 has no empty evening.
function pictureDay(day) {
  if (!day || !day.points.length) return day
  var axis = Chart.chartSpan(day)
  var newest = day.points[day.points.length - 1].t
  return Object.assign({}, day, { axis: Object.assign({}, axis, { end: Math.max(axis.start, newest) }) })
}

// Where `t` falls in `quote`'s exchange: its date, clock, and zone's name.
function local(quote, t, calendars) {
  var cal = quote.calendar || Market.calendarFor(calendars, quote)
  if (cal) {
    var day = Market.localDate(t, cal)
    return { y: day.y, m: day.m, d: day.d, weekday: day.weekday, clock: Market.clockOf(day), zone: Market.zoneName(cal, day.offset, quote) }
  }
  var at = Quote.clockAt(quote, t)
  var d = new Date((t + at.offset) * 1000)
  return { y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate(), weekday: d.getUTCDay(),
    clock: Format.hhmm(t, at.offset), zone: at.zone || Format.offsetName(at.offset) }
}

// "16:00 EDT · TUE 20 OCT 2026".
function clockAndDate(quote, t, calendars) {
  var l = local(quote, t, calendars)
  return l.clock + " " + l.zone + " · " + Format.WEEKDAYS[l.weekday].toUpperCase() + " " + l.d + " " + Format.MONTHS[l.m - 1] + " " + l.y
}

// The headline is the regular session's close, as a scrub at the bell reads
// it (`Quote.readingAt`): never a cryptocurrency's, which has none.
function headlineIsClose(quote) {
  var head = Quote.headlineQuote(quote)
  var reg = quote.session.regular
  return !quote.crypto && !!head && head.source === "quote" && !!reg && head.t >= reg.end
}

// The moment the picture's price stands for: `t`, whether it is the close,
// and, for a range's bar, the bar: the scrubbed one, or, with no headline,
// the last, whose close the range then shows (`History.historyRowModel`).
function moment(o) {
  if (o.history && o.scrubT) {
    var bar = History.historyBarAt(o.history, History.historyFraction(o.history, o.scrubT))
    if (bar) return { t: bar.t, close: false, bar: bar }
  }
  if (!o.history && o.scrubT) {
    var read = Quote.readingAt(o.day, o.scrubT)
    return { t: read.t, close: read.close, bar: null }
  }
  var head = Quote.headlineQuote(o.quote)
  if (!head && o.history) {
    var last = History.historyBarAt(o.history, 1)
    if (last) return { t: last.t, close: false, bar: last }
  }
  var close = headlineIsClose(o.quote)
  return { t: close ? o.quote.session.regular.end : head ? head.t : 0, close: close, bar: null }
}

// A range's bar as its scrub names it (`History.historyScrubText`): its
// date, a week's "WEEK OF", and an intraday bar's time, here always with
// its zone, without the price, which the picture shows large.
function barDate(history, bar) {
  var intraday = history.interval === "15m" || history.interval === "30m" || history.interval === "1h"
  var date = History.historyDateText(history, bar.t, History.historySpansYears(history), history.interval)
  if (history.interval === "1wk") date = "WEEK OF " + date
  if (intraday) {
    var clock = Quote.clockAt(history, bar.t)
    date += " " + Format.hhmm(bar.t, clock.offset) + " " + (clock.zone || Format.offsetName(clock.offset))
  }
  return date
}

// The picture's words, from what the surface shows: `quote` (Yahoo's),
// `day` (the 1D chart's), `history` (a range's, or null on the day),
// `latest`, `scrubT` (0 at rest), `changeMode`, `range`, `now`, and
// `calendars`.
//   when: what the price is, its time and zone, and its date;
//   from: what the change is measured from, as the chart's dashed line;
//   extended: the line under the price the popup shows, with its time;
//   start, end: the axis's two ends;
//   said: the moment in the footer's words.
function words(o) {
  var quote = o.quote
  var digits = quote.priceDigits
  var at = moment(o)
  var out = { when: "", from: "", extended: "", extendedTone: "flat", start: "", end: "", said: "" }
  if (at.bar) {
    out.when = barDate(o.history, at.bar)
    out.said = "on " + out.when
  } else if (at.t) {
    out.when = (at.close ? quote.exchange + " CLOSE · " : "AT ") + clockAndDate(quote, at.t, o.calendars)
    out.said = at.close ? "at the close" : "at " + Market.printClock(quote, at.t, o.calendars)
  }
  if (o.history) {
    out.from = String(o.range).toUpperCase() + " START " + Format.money(o.history.baseline, digits)
    // Each end with its year: the picture is read later, elsewhere.
    var bars = o.history.bars
    if (bars.length) {
      out.start = History.historyDateText(o.history, bars[0].t, true, o.history.interval)
      out.end = History.historyDateText(o.history, bars[bars.length - 1].t, true, o.history.interval)
    }
  } else {
    // What the change on show is measured from: the quote's at rest, the
    // day's while scrubbed (`Figures.rowModel`), as after midnight, where
    // the day's chart starts from the close the quote's change ends on.
    var base = o.scrubT ? o.day : quote
    out.from = o.changeMode === "open" ? "OPEN " + Format.money(base.dayOpen, base.priceDigits)
      : "PREV CLOSE " + Format.money(base.prevClose, base.priceDigits)
    var pts = o.day.points
    if (pts.length) {
      var axis = Chart.chartSpan(pictureDay(o.day))
      out.start = local(o.day, axis.byPrint ? pts[0].t : axis.start, o.calendars).clock
      out.end = local(o.day, pts[pts.length - 1].t, o.calendars).clock
    }
  }
  // The popup's line under the price, as it shows it: at rest, its tone,
  // and an old overnight print dimmed (`Figures.extendedStack`).
  var ext = !o.scrubT ? Figures.extendedStack(quote, o.latest, o.now, o.day, o.changeMode) : null
  var print = ext ? Quote.extendedPrint(quote, o.latest) : null
  if (ext && print) {
    var l = local(ext.label === "OVERNIGHT" && o.day ? o.day : quote, print.t, o.calendars)
    out.extended = ext.label + " " + l.clock + " " + l.zone + " · " + ext.price + " " + ext.changeText
    out.extendedTone = ext.stale ? "old" : ext.tone
  }
  return out
}

// What the screenshot is of, as the footer names it: the symbol, the range
// off the day, and the moment ("AAPL at the close", "AAPL 1Y on 3 AUG
// 2026").
function subject(symbol, range, said) {
  return symbol + (range && range !== "1D" ? " " + range : "") + (said ? " " + said : "")
}

// The symbol as the file's name carries it: lower case, letters, digits,
// dots, and dashes only, so no symbol can name another folder or carry a
// character a shell or a file manager reads; 32 at most. "^GSPC" is
// "gspc", "BRK-B" "brk-b".
function fileSymbol(symbol) {
  return String(symbol).toLowerCase().replace(/[^a-z0-9.-]/g, "").slice(0, 32) || "chart"
}
