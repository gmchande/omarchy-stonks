.pragma library
.import "Calendar.js" as Calendar
.import "Format.js" as Format
.import "Quote.js" as Quote

// The moment in an exchange's day: its sessions and bells, and the header's
// words for them. Yahoo owns today; the rest is the calendar's.

var PHASES = {
  closed: "Closed", weekend: "Weekend", pre: "Pre-market",
  opening: "Opening bell", open: "Market open", lunch: "Lunch lull", power: "Power hour",
  closing: "Closing bell", post: "After hours", always: "Open around the clock", overnight: "Overnight"
}

function calendarOf(calendars, quote) {
  return calendars && calendars.sessions ? calendars : Calendar.calendarFor(calendars, quote)
}

// On a calendar half day where Yahoo still sends a full-day regular end,
// clamp the regular close (and its after-hours span) to the early close so
// the header, freshness, cadence and sleep agree with the exchange.
function clampedSession(s, cal) {
  if (!cal || !s || !s.regular) return s
  var date = Calendar.dateStringOf(Calendar.localDate(s.regular.start, cal))
  if (!cal.earlyCloses || !cal.earlyCloses[date]) return s
  var segs = Calendar.segmentsOn(cal, date)
  if (!segs.length) return s
  var close = segs[segs.length - 1].end
  if (s.regular.end <= close) return s
  var post = s.post ? { start: close, end: cal.post ? Calendar.postClose(cal, date) : Math.min(s.post.end, close + (s.post.end - s.post.start)) } : null
  return { pre: s.pre, regular: { start: s.regular.start, end: close }, post: post }
}

// Calendar session for a held quote on today's trading day: its regular span,
// plus calendar-defined extended hours where the listing trades them.
function heldDaySession(quote, cal, now) {
  if (!cal || quote.crypto) return null
  var date = Calendar.dateStringOf(Calendar.localDate(now, cal))
  var segs = Calendar.segmentsOn(cal, date)
  if (!segs.length) return null
  var open = segs[0].start
  var close = segs[segs.length - 1].end
  var pre = cal.pre && quote.session.pre ? { start: Calendar.epochAt(cal, date, cal.pre.open), end: open } : null
  var post = cal.post && quote.session.post ? { start: close, end: Calendar.postClose(cal, date) } : null
  var start = pre ? pre.start : open
  var end = post ? post.end : close
  if (now < start || now >= end) return null
  return { pre: pre, regular: { start: open, end: close }, post: post }
}

// A quote held without a fetch passes from its bars' session into Yahoo's
// current period, as Monday's pre-market on Friday's bars.
function clockSession(quote, t, cal) {
  var s = clampedSession(quote.session, cal)
  var c = clampedSession(quote.current, cal)
  if (!c || !c.regular || !s.regular || t < (s.post || s.regular).end) return s
  return t >= (c.pre || c.regular).start && t < (c.post || c.regular).end ? c : s
}

// The chart endpoint carries no market state: the periods are all there is.
// The hour is by the clock of `t`'s own period, across a change of clocks too.
function sessionPhase(quote, t, cal) {
  var s = clockSession(quote, t, cal)
  if (quote.crypto) return "always"
  if (!s.regular) return "closed"
  var local = Format.localClock(t, Quote.clockAt(quote, t).offset)
  if (s.pre && t >= s.pre.start && t < s.regular.start) return "pre"
  if (t >= s.regular.start && t < s.regular.end) {
    if (t < s.regular.start + 30 * 60) return "opening"
    if (t >= s.regular.end - 5 * 60) return "closing"
    if (t >= s.regular.end - 60 * 60) return "power"
    if (local.hour === 12 && quote.timezoneName === "America/New_York") return "lunch"
    return "open"
  }
  if (s.post && t >= s.post.start && t < s.post.end) return "post"
  // Saudi's exchange trades on Sunday.
  var day = function(at) { return Math.floor((at + Quote.clockAt(quote, at).offset) / 86400) }
  var weekend = (local.weekday === 0 || local.weekday === 6) && day(t) !== day(s.regular.start)
  return weekend ? "weekend" : "closed"
}

function phaseLabel(phase) {
  return PHASES[phase] || PHASES.closed
}

function isTrading(phase) {
  return phase === "opening" || phase === "open" || phase === "lunch" || phase === "power" || phase === "closing" || phase === "always"
}

// Yahoo describes one session an answer, so after it there is nothing to
// count to: adding days would land the next open on a holiday.
function secondsToBell(quote, now, cal) {
  var reg = clockSession(quote, now, cal).regular
  if (!reg || quote.crypto) return null
  if (now >= reg.start && now < reg.end) return { seconds: reg.end - now, bell: "close" }
  if (now < reg.start) return { seconds: reg.start - now, bell: "open" }
  return null
}

function formatNextOpen(cal, nxt) {
  var local = Calendar.localDate(nxt.t, cal)
  return "opens " + Format.WEEKDAYS[local.weekday] + " " + Calendar.calendarClock(cal, nxt.t)
}

function scheduleNote(quote, now, calendars) {
  var cal = Calendar.calendarFor(calendars, quote)
  if (!cal) return Calendar.calendarMap(calendars) ? "" : " · market hours unknown"
  var nxt = Calendar.nextOpen(cal, now)
  return nxt ? " · " + formatNextOpen(cal, nxt) : " · market hours unknown"
}

function scrubPhase(quote, t) {
  if (!quote.axis || (t >= Quote.dayStart(quote) && t < Quote.dayEnd(quote))) return sessionPhase(quote, t)
  var pts = quote.points
  var session = ""
  for (var i = 0; i < pts.length && pts[i].t <= t; i++) session = Quote.pointSession(quote, pts[i])
  return session === "reg" ? "open" : session || "closed"
}

// On a day the calendar doesn't cover, a change of clocks it doesn't list
// would read as standard time, an hour out.
function clockCalendar(quote, t, calendars) {
  var cal = quote.calendar || Calendar.calendarFor(calendars, quote)
  return cal && Calendar.covers(cal, Calendar.dateStringOf(Calendar.localDate(t, cal))) ? cal : null
}

// The exchange's own clock at `t`, `{ offset, zone }`.
function tradeClock(quote, t, calendars) {
  var cal = clockCalendar(quote, t, calendars)
  if (!cal) return Quote.clockAt(quote, t)
  var offset = Calendar.localDate(t, cal).offset
  return { offset: offset, zone: Calendar.zoneName(cal, offset, quote) }
}

function tradeTime(quote, t, calendars) {
  var clock = tradeClock(quote, t, calendars)
  return Format.zonedHhmm(t, clock.offset, clock.zone)
}

// The calendars keep their source's names, since they are renewed from it:
// Toronto's "In Lieu of Boxing Day" reads as London's "Boxing Day" does.
function holidayName(name) {
  return name.replace(/^In Lieu of /, "").replace(/ (observed|\(substitute\))$/, "")
}

// The status, then shorter forms for a narrower header; each keeps the
// time, its day and its zone. A scrub into a calendar's lunch break says
// so, as the header at rest does.
function statusForms(quote, now, scrubT, calendars, overnight) {
  if (scrubT) {
    var read = Quote.readingAt(quote, scrubT)
    var at = "At " + tradeDay(quote, read.t, now, calendars) + tradeTime(quote, read.t, calendars)
    var lunch = !read.close && Calendar.breakUntil(Calendar.calendarFor(calendars, quote), scrubT)
    return [at + " · " + (lunch ? "Lunch break" : phaseLabel(read.close ? "closing" : scrubPhase(quote, scrubT))), at]
  }
  var cal = Calendar.calendarFor(calendars, quote)
  var brk = cal ? Calendar.breakUntil(cal, now) : null
  if (brk) {
    var reopens = "reopens " + Calendar.calendarClock(cal, brk, quote)
    return ["Lunch break · " + reopens + " · in " + Format.duration(brk - now), "Lunch break · " + reopens, sentence(reopens)]
  }
  // The calendar's clock today, not the held answer's, which may be from
  // before a change of clocks.
  var basePhase = sessionPhase(quote, now, cal)
  var held = !overnight && !isTrading(basePhase) && basePhase !== "pre" && basePhase !== "post" ? heldDaySession(quote, cal, now) : null
  var q = held ? Object.assign({}, quote, { session: held, current: null,
    clocks: [], gmtoffset: Calendar.localDate(now, cal).offset }) : quote
  var phase = overnight ? "overnight" : sessionPhase(q, now, cal)
  var bell = secondsToBell(q, now, cal) || indexBell(quote, cal, now)
  var kind = cal ? Calendar.dayKind(cal, Calendar.dateStringOf(Calendar.localDate(now, cal))) : null
  // On a holiday Yahoo may still send a session nobody trades.
  var closure = !overnight && kind && kind.kind === "closure"
  if (!closure && bell && bell.bell === "close") {
    var named = phase === "opening" || phase === "lunch" || phase === "power" || phase === "closing"
    var pause = Calendar.sessionBreaks(cal, now).filter(function(b) { return now < b.start })[0]
    var closes = pause ? "lunch break in " + Format.duration(pause.start - now) : "closes in " + Format.duration(bell.seconds)
    return [named ? phaseLabel(phase) + " · " + closes : pause ? sentence(closes) : "Market " + closes, sentence(closes)]
  }
  if (!closure && bell) {
    var opens = "opens in " + Format.duration(bell.seconds)
    var before = quote.instrumentType === "INDEX" ? phaseLabel("closed") + " · "
      : phase === "pre" || phase === "overnight" ? phaseLabel(phase) + " · " : "Market "
    return [before + opens, sentence(opens)]
  }
  var reg = clockSession(q, now, cal).regular
  if (!closure && phase === "post" && reg && now >= reg.end) {
    var closedAt = "closed at " + tradeTime(quote, reg.end, calendars)
    return [phaseLabel(phase) + " · " + closedAt, sentence(closedAt)]
  }
  var note = phase === "post" ? "" : scheduleNote(quote, now, calendars)
  var names = closure ? [holidayName(kind.name), phaseLabel("closed")] : [phaseLabel(phase)]
  return names.map(function(name) { return name + note }).concat(note ? [sentence(note.slice(" · ".length))] : [])
}

// By the clock `tradeTime` reads.
function tradeDay(quote, t, now, calendars) {
  var day = function(at) {
    return Math.floor((at + tradeClock(quote, at, calendars).offset) / 86400)
  }
  var days = day(now) - day(t)
  if (days === 0) return ""
  var d = new Date((day(t) * 86400) * 1000)
  return (days > 0 && days < 7 ? Format.WEEKDAYS[d.getUTCDay()] : d.getUTCDate() + " " + sentence(Format.MONTHS[d.getUTCMonth()].toLowerCase())) + " "
}

function sentence(words) {
  return words.charAt(0).toUpperCase() + words.slice(1)
}

// Yahoo's periods for an index stay the last session's until it opens, so
// through its calendar's pre-market it counts to the calendar's open.
function indexBell(quote, cal, now) {
  if (quote.instrumentType !== "INDEX" || !cal || !cal.pre) return null
  var date = Calendar.dateStringOf(Calendar.localDate(now, cal))
  var segs = Calendar.segmentsOn(cal, date)
  if (!segs.length || now < Calendar.epochAt(cal, date, cal.pre.open) || now >= segs[0].start) return null
  return { seconds: segs[0].start - now, bell: "open" }
}

function inRegularSession(quote, now, calendars) {
  return regularNow(quote, now, Calendar.calendarNow(Calendar.calendarFor(calendars, quote), now))
}

function regularNow(quote, now, calNow) {
  if (!quote || quote.crypto || calNow.quiet || calNow.breakEnd) return false
  if (calNow.earlyEnd && now >= calNow.earlyEnd) return false
  return isTrading(sessionPhase(quote, now, calNow.cal)) || calNow.segment
}

// Whether a listing's market is actively trading its headline price now:
// always for coins, otherwise in its regular session by both Yahoo and its
// calendar (never during a holiday, lunch break, or past a half-day close).
function tradingNow(quote, now, calendars) {
  if (!quote) return false
  if (quote.crypto) return true
  return inRegularSession(quote, now, calendars)
}

// A step over 90 s is Stonks starting or the machine waking: a bell is
// never late.
function bellBetween(quote, before, now, calendars) {
  if (!quote || now <= before || now - before > 90) return ""
  var cal = Calendar.calendarFor(calendars, quote)
  var then = Calendar.calendarNow(cal, before)
  var at = Calendar.calendarNow(cal, now)
  if (then.breakEnd || at.breakEnd) return ""
  var was = regularNow(quote, before, then)
  var is = regularNow(quote, now, at)
  return was === is ? "" : is ? "open" : "close"
}

// A quote whose periods don't describe today takes their extended hours'
// lengths around today's segments.
function inExtendedHours(quote, now, calendars) {
  if (!quote || quote.crypto || Calendar.calendarQuiet(calendars, quote, now)) return false
  var cal = Calendar.calendarFor(calendars, quote)
  var phase = sessionPhase(quote, now, cal)
  if (phase === "pre" || phase === "post") return true
  var date = cal ? Calendar.dateStringOf(Calendar.localDate(now, cal)) : ""
  var described = cal && [quote.session, quote.current].some(function(p) {
    return !!p && !!p.regular && Calendar.dateStringOf(Calendar.localDate(p.regular.start, cal)) === date
  })
  var segs = cal && !described ? Calendar.segmentsOn(cal, date) : []
  var s = quote.session
  if (!segs.length || !s.regular) return false
  var open = segs[0].start
  var close = segs[segs.length - 1].end
  var pre = !!s.pre && now >= open - (s.regular.start - s.pre.start) && now < open
  var postEnd = cal.post ? Calendar.postClose(cal, date) : close + (s.post ? s.post.end - s.regular.end : 0)
  var post = !!s.post && now >= close && now < postEnd
  return pre || post
}

// Yahoo can answer with the last session's quote for seconds after the open.
var OPENING_WAIT = 60

function awaitingOpen(quote, now, calendars) {
  if (!quote || quote.crypto) return false
  var cal = calendarOf(calendars, quote)
  var reg = clockSession(quote, now, cal).regular
  if (!reg || now < reg.start || now >= reg.end) reg = Calendar.calendarRegular(cal, now)
  var head = Quote.headlineQuote(quote)
  return !!reg && !!head && head.t !== null && head.t < reg.start && now >= reg.start && now < reg.start + OPENING_WAIT
}
