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

// Where `t` falls in `quote`'s exchange: its date, clock, and zone's name,
// by the calendar that knows that day's clock (`Market.clockCalendar`),
// else by Yahoo's.
function local(quote, t, calendars) {
  var cal = Market.clockCalendar(quote, t, calendars)
  if (cal) {
    var day = Market.localDate(t, cal)
    return { y: day.y, m: day.m, d: day.d, weekday: day.weekday, clock: Market.clockOf(day), zone: Market.zoneName(cal, day.offset, quote) }
  }
  var at = Quote.clockAt(quote, t)
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

// A range's length in words, for the picture's foot.
var SPANS = { "1W": "1 WEEK", "1M": "1 MONTH", "3M": "3 MONTHS", "6M": "6 MONTHS", "YTD": "YEAR TO DATE",
  "1Y": "1 YEAR", "2Y": "2 YEARS", "5Y": "5 YEARS", "10Y": "10 YEARS", "All": "ALL" }

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
  // At rest, the newest price since the close (`newest`) where it is the
  // one on top, on the day and on a range, whose line ends on it.
  if (o.newest) return { t: o.newest.t, close: false, bar: null, phase: o.newest.phase }
  var head = Quote.headlineQuote(o.quote)
  if (!head && o.history) {
    var last = History.historyBarAt(o.history, 1)
    if (last) return { t: last.t, close: false, bar: last }
  }
  var close = headlineIsClose(o.quote)
  return { t: close ? o.quote.session.regular.end : head ? head.t : 0, close: close, bar: null }
}

// A range's bar as its scrub names it (`History.historyScrubForms`): its
// date, a week's "WEEK OF", and an intraday bar's time, or the newest
// price's (`History.withNewest`), here always with its zone, without the
// price, which the picture shows large.
function barDate(history, bar) {
  var timed = !!bar.newest || history.interval === "15m" || history.interval === "30m" || history.interval === "1h"
  var date = History.historyDateText(history, bar.t, History.historySpansYears(history), bar.newest ? "1d" : history.interval)
  if (history.interval === "1wk" && !bar.newest) date = "WEEK OF " + date
  if (timed) {
    var clock = Quote.clockAt(history, bar.t)
    date += " " + Format.hhmm(bar.t, clock.offset) + " " + (clock.zone || Format.offsetName(clock.offset))
  }
  return date
}

// The picture's words, from what the surface shows: `quote` (Yahoo's),
// `day` (the 1D chart's), `history` (a range's, or null on the day),
// `latest`, `newest` (the newest price since the close, on top at rest:
// `Figures.rowModel`'s), `scrubT` (0 at rest), `changeMode`, `range`,
// `now`, and `calendars`.
//   when: what the price is, and its time and zone; a scrub outside the
//   regular session named by its session, as the line under the price is;
//   on a range, its date too, which on the day the foot says;
//   from: what the change is measured from, as the chart's dashed line;
//   extended: the line under the price the panel shows, with its time;
//   currency: beside the price; none beside an index's level, which isn't
//   money;
//   start, end: the day's axis's two ends; a range has none;
//   span: when, at the foot: on the day, the date of the price on show,
//   the day its move belongs to (after midnight, the close before the
//   chart's day); on a range, the range's length and its first and last
//   dates, said once here;
//   said: the moment in the footer's words.
function words(o) {
  var quote = o.quote
  var digits = quote.priceDigits
  var at = moment(o)
  var out = { when: "", from: "", extended: "", extendedTone: "flat", start: "", end: "", span: "", said: "",
    currency: quote.instrumentType === "INDEX" ? "" : Figures.currencyLabel(String(quote.currency || "")) }
  if (at.bar) {
    out.when = barDate(o.history, at.bar)
    out.said = "on " + out.when
  } else if (at.t) {
    var phase = at.phase || (o.scrubT && !at.close ? Market.scrubPhase(o.day, o.scrubT) : "")
    var outside = phase === "pre" || phase === "post" || phase === "overnight"
    out.when = (at.close ? quote.exchange + " CLOSE · " : outside ? Market.phaseLabel(phase).toUpperCase() + " " : "AT ")
      + clockOf(quote, at.t, o.calendars)
      + (o.history ? " · " + dateOf(quote, at.t, o.calendars) : "")
    if (!o.history) out.span = dateOf(quote, at.t, o.calendars)
    out.said = at.close ? "at the close" : "at " + Market.printClock(quote, at.t, o.calendars)
  }
  if (o.history) {
    out.from = String(o.range).toUpperCase() + " START " + Format.money(o.history.baseline, digits)
    out.span = SPANS[o.range] || String(o.range).toUpperCase()
    // Each end with its year: the picture is read later, elsewhere.
    var bars = o.history.bars
    if (bars.length) {
      out.span += " · " + History.historyDateText(o.history, bars[0].t, true, o.history.interval)
        + " – " + History.historyDateText(o.history, bars[bars.length - 1].t, true, o.history.interval)
    }
  } else {
    // What the change on show is measured from: the quote's at rest
    // (`Quote.restingRead`); with a newest price on top, or while scrubbed,
    // the chart's dashed line, named as the panel names it
    // (`Figures.dayBaselineText`).
    var today = Figures.exchangeDay(o.day, o.now)
    var base = o.scrubT ? Figures.scrubbedBase(o.day, o.scrubT) : Quote.restingRead(quote, o.newest || null).base
    out.from = o.changeMode === "open" ? "OPEN " + Format.money(base.dayOpen, digits)
      : o.scrubT || o.newest ? Figures.dayBaselineText(o.day, today, o.scrubT)
      : "PREV CLOSE " + Format.money(base.prevClose, digits)
    var pts = o.day.points
    if (pts.length) {
      var axis = Chart.chartSpan(pictureDay(o.day))
      var first = local(o.day, axis.start, o.calendars)
      var last = local(o.day, pts[pts.length - 1].t, o.calendars)
      out.start = first.clock
      // A chart that runs past its day, into the night and the next
      // morning, names the weekday it ends on.
      out.end = (last.d !== first.d ? Format.WEEKDAYS[last.weekday].toUpperCase() + " " : "") + last.clock
    }
  }
  // The panel's line under the price, as it shows it: at rest, the close
  // under a newest price on top, and the move since it (`Figures.closeLine`),
  // else the extended-hours print, its tone, and an old overnight print
  // dimmed (`Figures.extendedStack`).
  if (!o.scrubT && o.newest) {
    var below = Figures.closeLine(quote, Figures.exchangeDay(quote, o.now), o.changeMode, o.newest)
    out.extended = below.label + " · " + below.price + " " + below.changeText + (below.since ? " · " + below.since + " SINCE" : "")
    out.extendedTone = below.tone
    return out
  }
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
