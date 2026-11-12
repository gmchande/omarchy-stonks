.pragma library
.import "Calendar.js" as Calendar
.import "Format.js" as Format
.import "Quote.js" as Quote

// The close a move counts from, carried across an open while Yahoo catches up.

// For minutes after an open, Yahoo's answers can still count the day from
// the close before last. Each quote carries the last close Stonks saw
// (`closeSeen`, saved with it) for the next session to count from. Such an
// answer can also still hold the last close as its price, at the new day's
// time: Yahoo restating the last session, or a trade at its close, which
// its answers can't tell apart (a spark answer has no volume). The move is
// left out until Yahoo's base moves on, and so is the day's open, the same
// restatement, until a chart answer has the day's own. A split or a
// dividend moves Yahoo's base, and Yahoo's stands. A Stonks that holds no
// close from the session before leaves the move out until Yahoo has caught
// up (`CATCH_UP`): no field of Yahoo's answers names that close at every
// open. Without a calendar, a close held from before a weekday with no
// session seen may be a holiday's eve, a missed day's, or, where the week
// starts on Sunday, Thursday's: the move is left out only while Yahoo still
// counts from the close before the one held. A stock that doesn't trade
// again can't show Yahoo catching up, so the clock ends the wait too
// (`BEHIND`). A US stock's day turns at 04:00, hours before its first
// trade: a calendar with a pre-market keeps Yahoo's, and so does a listing
// with no calendar and no close held, which may be one.
function carryClose(previous, quote, calendars, now) {
  if (!quote || quote.crypto || quote.instrumentType === "INDEX" || !quote.session.regular) return quote
  if (quote.before) quote = Object.assign({}, quote, { before: Object.assign({}, quote.before, { base: heldBase(previous, quote.before) }) })
  var cal = Calendar.calendarFor(calendars, quote)
  if (cal && cal.pre) return quote
  // The next quote reads the close from this one, so an unchanged answer
  // after the bell stays unchanged.
  var seen = previous && !sessionClose(quote) ? sessionClose(previous) || previous.closeSeen || null : null
  var reg = quote.session.regular
  var head = Quote.headlineQuote(quote)
  var traded = !!head && head.source === "quote" && head.t !== null && head.t >= reg.start
  var held = !!seen && nextSession(quote, seen.day, reg.start, cal)
  var behind = traded && !!seen && quote.prevClose === seen.before && seen.before !== seen.close
  var stale = behind && held
  var restated = stale && head.price === seen.close
  var first = traded ? firstTrade(quote, head) : null
  var unknown = traded && !held && (!!cal || behind) && head.t < first + CATCH_UP && now < first + CATCH_UP + BEHIND
  if (!seen && !unknown) return quote
  var carried = seen ? Object.assign({}, quote, { closeSeen: seen }) : quote
  // Yahoo restating the last close: no move, and no open, until it moves on.
  if (restated) {
    var verdict = quote.verdict && Object.assign({}, quote.verdict, { open: null, openSession: null })
    return Object.assign({}, carried, { prevClose: null, dayOpen: null, openSession: null, verdict: verdict })
  }
  // No close held from the session before: no move until Yahoo catches up.
  if (unknown) return Object.assign({}, carried, { prevClose: null })
  // Yahoo still counting from the close before last: the move counts from
  // the close seen.
  if (stale) return Object.assign({}, carried, { prevClose: seen.close })
  return carried
}

function sessionClose(quote) {
  var reg = quote.session && quote.session.regular
  var head = Quote.headlineQuote(quote)
  return reg && head && head.source === "quote" && head.t !== null && head.t >= reg.end && Format.isFiniteNumber(quote.prevClose)
    ? { day: reg.start, close: head.price, before: quote.prevClose } : null
}

// Whether the session `to` starts is the next after the one `from` starts:
// by the listing's calendar where it covers the day, so Tuesday's follows
// Friday's over a Monday holiday, else by weekdays.
function nextSession(quote, from, to, cal) {
  var date = function(t) { return Calendar.dateStringOf(Calendar.localDate(t, cal)) }
  if (cal && Calendar.covers(cal, date(from)) && Calendar.covers(cal, date(to))) {
    var open = Calendar.nextOpen(cal, Calendar.epochAt(cal, Calendar.nextDateString(date(from)), "00:00"))
    return !!open && open.dateString === date(to)
  }
  var day = function(t) { return Math.floor((t + (quote.gmtoffset || 0)) / 86400) }
  var weekday = new Date(day(from) * 86400000).getUTCDay()
  return day(to) - day(from) === (weekday === 5 ? 3 : weekday === 6 ? 2 : 1)
}

// Toyota's answers at Tokyo's open on Monday 2 November counted from
// Thursday's close until its trades reached 09:05, five minutes after the
// first; Shell's at London's on Tuesday 3 November were right by 08:05.
// Twice that, from the first trade Yahoo sent: its bar, else the quote.
var CATCH_UP = 10 * 60

// Yahoo's answers from Tokyo and London ran 15 minutes behind the clock,
// Toronto's not at all, so by then Yahoo's trades have caught up, whether
// or not the stock traded again.
var BEHIND = 15 * 60

function firstTrade(quote, head) {
  var pts = Quote.regularPoints(quote)
  return pts.length ? pts[0].t : head.t
}

// One or two trades of a day just begun, scaled to the chart's height, draw
// a line from top to bottom, or a crash from the close. So until the day has
// `FIRST_BARS`, the 1D chart holds the day just closed, asked for in two
// days meanwhile (`Asks.twoDays`), as it was drawn before the open, with the
// new day's trades joined after it as a pre-market joins a day
// (`Quote.tailDay`). Its dashed line is the one Stonks drew before the open
// (`heldBase`); the new day's trades count from its close, the one the move
// counts from, where the dashed line steps at the bell, as it does for
// tonight's trades (`Day.nightBell`). Each is left out where unknown
// (`held`).
function heldDay(quote) {
  if (!quote.before || !firstMinutes(quote)) return null
  var close = quote.prevClose
  var known = Format.isFiniteNumber(close)
  return Object.assign({}, quote, {
    session: quote.before.session,
    next: quote.session,
    before: null,
    held: true,
    tonight: known ? Quote.periodsStart(quote.session) : null,
    points: quote.before.points.concat(quote.points.map(function(p) { return { t: p.t, p: p.p, s: Quote.pointSession(quote, p) } })),
    prevClose: Format.isFiniteNumber(quote.before.base) ? quote.before.base : null,
    price: close,
    marketTime: known ? quote.before.session.regular.end : null,
    dayOpen: null,
    openSession: null
  })
}

// Three of Yahoo's five-minute bars, ten minutes of the day, by when its move
// shows (`CATCH_UP`). Yahoo's echo of its quote, off the grid, is no bar.
var FIRST_BARS = 3

function firstMinutes(quote) {
  var reg = quote.session.regular
  var bars = Quote.regularPoints(quote).filter(function(p) { return (p.t - reg.start) % Quote.BAR === 0 })
  return bars.length < FIRST_BARS
}

// Yahoo's first bars came up to half an hour after the open in the saved
// answers, Sydney's three only after it. A listing with fewer an hour after
// its open trades too seldom to wait for, and is drawn as it trades.
var HOLD_LIMIT = 60 * 60

// The dashed line of the day before `quote`'s, as the quote Stonks held drew
// it: no field of Yahoo's answers names it at every open, as Tokyo's two-day
// answer gave that day's own close as the close before it.
function heldBase(previous, before) {
  var day = before.session.regular.start
  if (!previous || !previous.session.regular) return null
  if (previous.session.regular.start === day) return Quote.dayBase(previous)
  return previous.before && previous.before.session.regular.start === day ? previous.before.base : null
}
