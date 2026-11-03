.pragma library
.import "Format.js" as Format
.import "Quote.js" as Quote

// Exchange sessions, bells, the header's words and the refresh cadence.
// Yahoo owns today; the rest is calendars.json: no keyless holiday feed exists.

var PHASES = {
  closed: "Closed", weekend: "Weekend", pre: "Pre-market",
  opening: "Opening bell", open: "Market open", lunch: "Lunch lull", power: "Power hour",
  closing: "Closing bell", post: "After hours", always: "Open around the clock", overnight: "Overnight"
}

// A quote held without a fetch passes from its bars' session into Yahoo's
// current period, as Monday's pre-market on Friday's bars.
function clockSession(quote, t) {
  var s = quote.session
  var c = quote.current
  if (!c || !c.regular || !s.regular || t < (s.post || s.regular).end) return s
  return t >= (c.pre || c.regular).start && t < (c.post || c.regular).end ? c : s
}

// The chart endpoint carries no market state: the periods are all there is.
// The hour is by the clock of `t`'s own period, across a change of clocks too.
function sessionPhase(quote, t) {
  var s = clockSession(quote, t)
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
function secondsToBell(quote, now) {
  var reg = clockSession(quote, now).regular
  if (!reg || quote.crypto) return null
  if (now >= reg.start && now < reg.end) return { seconds: reg.end - now, bell: "close" }
  if (now < reg.start) return { seconds: reg.start - now, bell: "open" }
  return null
}

function calendarMap(calendars) {
  if (!calendars) return null
  return calendars.calendars ? calendars.calendars : calendars
}

// Yahoo files some indexes under a name that holds indexes on other hours
// too (^FTSE beside FTSE's global ones, ^RUT beside Cboe's VVIX).
function calendarFor(calendars, quote) {
  var map = calendarMap(calendars)
  if (!map || !quote || !quote.exchange) return null
  for (var id in map) {
    var cal = map[id]
    if (cal && ((cal.exchanges && cal.exchanges.indexOf(quote.exchange) >= 0) || (cal.indexes && cal.indexes.indexOf(quote.symbol) >= 0))) return cal
  }
  return null
}

// US exchanges trade in whole cents from $1 (Reg NMS); a coin or a European
// listing trades finer.
function centExchanges(calendars) {
  var map = calendarMap(calendars)
  return map && map.US && map.US.exchanges ? map.US.exchanges : []
}

function dateStringOf(local) {
  return local.y + "-" + Format.pad2(local.m) + "-" + Format.pad2(local.d)
}

function nextDateString(dateString) {
  var p = dateString.split("-")
  var d = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2] + 1))
  return d.getUTCFullYear() + "-" + Format.pad2(d.getUTCMonth() + 1) + "-" + Format.pad2(d.getUTCDate())
}

function offsetForDate(cal, dateString) {
  var ranges = cal.utcOffsets || []
  for (var i = 0; i < ranges.length; i++) {
    if (dateString >= ranges[i].from && dateString < ranges[i].to) return ranges[i].offset
  }
  return cal.standardOffset
}

function localDate(t, cal) {
  var off = cal.standardOffset
  var d = new Date((t + off) * 1000)
  var dateString = d.getUTCFullYear() + "-" + Format.pad2(d.getUTCMonth() + 1) + "-" + Format.pad2(d.getUTCDate())
  var real = offsetForDate(cal, dateString)
  if (real !== off) {
    d = new Date((t + real) * 1000)
    dateString = d.getUTCFullYear() + "-" + Format.pad2(d.getUTCMonth() + 1) + "-" + Format.pad2(d.getUTCDate())
    real = offsetForDate(cal, dateString)
    d = new Date((t + real) * 1000)
  }
  return {
    y: d.getUTCFullYear(),
    m: d.getUTCMonth() + 1,
    d: d.getUTCDate(),
    weekday: d.getUTCDay(),
    hour: d.getUTCHours(),
    minute: d.getUTCMinutes(),
    offset: real
  }
}

function zoneName(cal, offset, quote) {
  var names = cal && cal.zoneNames
  if (names && names[String(offset)]) return names[String(offset)]
  if (quote && quote.zoneName && quote.gmtoffset === offset) return quote.zoneName
  return Format.offsetName(offset)
}

function calendarClock(cal, t, quote) {
  var local = localDate(t, cal)
  return Format.zoned(clockOf(local), t, local.offset, zoneName(cal, local.offset, quote))
}

function epochAt(cal, dateString, hm) {
  var p = dateString.split("-")
  var clock = hm.split(":")
  var utc = Date.UTC(+p[0], +p[1] - 1, +p[2], +clock[0], +clock[1]) / 1000
  return utc - offsetForDate(cal, dateString)
}

function dayKind(cal, dateString) {
  if (!cal || !dateString || dateString > cal.validThrough) return { kind: "unknown" }
  var weekday = localDate(epochAt(cal, dateString, "12:00"), cal).weekday
  if ((cal.weekend || [6, 0]).indexOf(weekday) >= 0) return { kind: "weekend" }
  if (cal.closures && cal.closures[dateString]) return { kind: "closure", name: cal.closures[dateString] }
  return { kind: "open" }
}

function segmentsOn(cal, dateString) {
  if (dayKind(cal, dateString).kind !== "open") return []
  var sessions = cal.sessions || []
  var early = cal.earlyCloses ? cal.earlyCloses[dateString] : null
  var out = []
  for (var i = 0; i < sessions.length; i++) {
    var close = early && i === sessions.length - 1 ? early : sessions[i].close
    out.push({ start: epochAt(cal, dateString, sessions[i].open), end: epochAt(cal, dateString, close) })
  }
  return out
}

function nextOpen(cal, t) {
  if (!cal) return null
  var dateString = dateStringOf(localDate(t, cal))
  while (dateString <= cal.validThrough) {
    var segs = segmentsOn(cal, dateString)
    for (var i = 0; i < segs.length; i++) {
      if (segs[i].start > t) return { t: segs[i].start, dateString: dateString }
    }
    dateString = nextDateString(dateString)
  }
  return null
}

function sessionBreaks(cal, t) {
  var segs = cal ? segmentsOn(cal, dateStringOf(localDate(t, cal))) : []
  var out = []
  for (var i = 0; i < segs.length - 1; i++) out.push({ start: segs[i].end, end: segs[i + 1].start })
  return out
}

function breakUntil(cal, t) {
  return calendarNow(cal, t).breakEnd
}

function formatNextOpen(cal, nxt) {
  var local = localDate(nxt.t, cal)
  return "opens " + Format.WEEKDAYS[local.weekday] + " " + calendarClock(cal, nxt.t)
}

function calendarQuiet(calendars, quote, now) {
  return !!quote && !quote.crypto && calendarNow(calendarFor(calendars, quote), now).quiet
}

// The same for every listing on a calendar, so a walk over a list reads
// each calendar once (`Service.askDue`).
function calendarNow(cal, now) {
  var date = cal ? dateStringOf(localDate(now, cal)) : ""
  var kind = cal ? dayKind(cal, date).kind : ""
  var segs = cal ? segmentsOn(cal, date) : []
  var breakEnd = null
  for (var i = 0; i < segs.length - 1; i++) if (now >= segs[i].end && now < segs[i + 1].start) breakEnd = segs[i + 1].start
  return {
    cal: cal,
    quiet: kind === "weekend" || kind === "closure",
    breakEnd: breakEnd,
    segment: segs.some(function(seg) { return now >= seg.start && now < seg.end })
  }
}

function calendarRegular(cal, now) {
  var segs = cal ? segmentsOn(cal, dateStringOf(localDate(now, cal))) : []
  if (!segs.some(function(seg) { return now >= seg.start && now < seg.end })) return null
  return { start: segs[0].start, end: segs[segs.length - 1].end }
}

function scheduleNote(quote, now, calendars) {
  var cal = calendarFor(calendars, quote)
  if (!cal) return calendarMap(calendars) ? "" : " · market hours unknown"
  var nxt = nextOpen(cal, now)
  return nxt ? " · " + formatNextOpen(cal, nxt) : " · market hours unknown"
}

function previousDateString(dateString) {
  var p = dateString.split("-")
  var d = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2] - 1))
  return d.getUTCFullYear() + "-" + Format.pad2(d.getUTCMonth() + 1) + "-" + Format.pad2(d.getUTCDate())
}

function clockOf(local) {
  return Format.pad2(local.hour) + ":" + Format.pad2(local.minute)
}

function scrubPhase(quote, t) {
  if (!quote.axis || (t >= Quote.dayStart(quote) && t < Quote.dayEnd(quote))) return sessionPhase(quote, t)
  var pts = quote.points
  var session = ""
  for (var i = 0; i < pts.length && pts[i].t <= t; i++) session = Quote.pointSession(quote, pts[i])
  return session === "reg" ? "open" : session || "closed"
}

// Past `validThrough` a change of clocks the calendar doesn't list would
// read as standard time, an hour out.
function clockCalendar(quote, t, calendars) {
  var cal = quote.calendar || calendarFor(calendars, quote)
  return cal && dateStringOf(localDate(t, cal)) <= cal.validThrough ? cal : null
}

function printClock(quote, t, calendars) {
  var cal = clockCalendar(quote, t, calendars)
  if (cal) return calendarClock(cal, t, quote)
  var clock = Quote.clockAt(quote, t)
  return Format.zonedHhmm(t, clock.offset, clock.zone)
}

// The calendars keep their source's names, since they are renewed from it.
function holidayName(name) {
  return name.replace(/ (observed|\(substitute\))$/, "")
}

function marketStatus(quote, now, scrubT, calendars, overnight) {
  return statusForms(quote, now, scrubT, calendars, overnight)[0]
}

// The status, then shorter forms for a narrower header; each keeps the
// time, its day and its zone.
function statusForms(quote, now, scrubT, calendars, overnight) {
  if (scrubT) {
    var read = Quote.readingAt(quote, scrubT)
    var at = "At " + printDay(quote, read.t, now, calendars) + printClock(quote, read.t, calendars)
    return [at + " · " + phaseLabel(read.close ? "closing" : scrubPhase(quote, scrubT)), at]
  }
  var cal = calendarFor(calendars, quote)
  var brk = cal ? breakUntil(cal, now) : null
  if (brk) {
    var reopens = "reopens " + calendarClock(cal, brk, quote)
    return ["Lunch break · " + reopens + " · in " + Format.duration(brk - now), "Lunch break · " + reopens, sentence(reopens)]
  }
  // The calendar's clock today, not the held answer's, which may be from
  // before a change of clocks.
  var held = !overnight && !isTrading(sessionPhase(quote, now)) ? calendarRegular(cal, now) : null
  var q = held ? Object.assign({}, quote, { session: { pre: null, regular: held, post: null }, current: null,
    clocks: [], gmtoffset: localDate(now, cal).offset }) : quote
  var phase = overnight ? "overnight" : sessionPhase(q, now)
  var bell = secondsToBell(q, now) || indexBell(quote, cal, now)
  var kind = cal ? dayKind(cal, dateStringOf(localDate(now, cal))) : null
  // On a holiday Yahoo may still send a session nobody trades.
  var closure = !overnight && kind && kind.kind === "closure"
  if (!closure && bell && bell.bell === "close") {
    var named = phase === "opening" || phase === "lunch" || phase === "power" || phase === "closing"
    var pause = sessionBreaks(cal, now).filter(function(b) { return now < b.start })[0]
    var closes = pause ? "lunch break in " + Format.duration(pause.start - now) : "closes in " + Format.duration(bell.seconds)
    return [named ? phaseLabel(phase) + " · " + closes : pause ? sentence(closes) : "Market " + closes, sentence(closes)]
  }
  if (!closure && bell) {
    var opens = "opens in " + Format.duration(bell.seconds)
    var before = quote.instrumentType === "INDEX" ? phaseLabel("closed") + " · "
      : phase === "pre" || phase === "overnight" ? phaseLabel(phase) + " · " : "Market "
    return [before + opens, sentence(opens)]
  }
  var reg = clockSession(q, now).regular
  if (!closure && phase === "post" && reg && now >= reg.end) {
    var closedAt = "closed at " + printClock(quote, reg.end, calendars)
    return [phaseLabel(phase) + " · " + closedAt, sentence(closedAt)]
  }
  var note = phase === "post" ? "" : scheduleNote(quote, now, calendars)
  var names = closure ? [holidayName(kind.name), phaseLabel("closed")] : [phaseLabel(phase)]
  return names.map(function(name) { return name + note }).concat(note ? [sentence(note.slice(" · ".length))] : [])
}

// By the clock `printClock` reads.
function printDay(quote, t, now, calendars) {
  var day = function(at) {
    var cal = clockCalendar(quote, at, calendars)
    var offset = cal ? localDate(at, cal).offset : Quote.clockAt(quote, at).offset
    return Math.floor((at + offset) / 86400)
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
  var date = dateStringOf(localDate(now, cal))
  var segs = segmentsOn(cal, date)
  if (!segs.length || now < epochAt(cal, date, cal.pre.open) || now >= segs[0].start) return null
  return { seconds: segs[0].start - now, bell: "open" }
}

function inRegularSession(quote, now, calendars) {
  return regularNow(quote, now, calendarNow(calendarFor(calendars, quote), now))
}

function regularNow(quote, now, calNow) {
  if (!quote || quote.crypto || calNow.quiet || calNow.breakEnd) return false
  return isTrading(sessionPhase(quote, now)) || calNow.segment
}

// A step over 90 s is Stonks starting or the machine waking: a bell is
// never late.
function bellBetween(quote, before, now, calendars) {
  if (!quote || now <= before || now - before > 90) return ""
  var cal = calendarFor(calendars, quote)
  var then = calendarNow(cal, before)
  var at = calendarNow(cal, now)
  if (then.breakEnd || at.breakEnd) return ""
  var was = regularNow(quote, before, then)
  var is = regularNow(quote, now, at)
  return was === is ? "" : is ? "open" : "close"
}

// A quote whose periods don't describe today takes their extended hours'
// lengths around today's segments.
function inExtendedHours(quote, now, calendars) {
  if (!quote || quote.crypto || calendarQuiet(calendars, quote, now)) return false
  var phase = sessionPhase(quote, now)
  if (phase === "pre" || phase === "post") return true
  var cal = calendarFor(calendars, quote)
  var date = cal ? dateStringOf(localDate(now, cal)) : ""
  var described = cal && [quote.session, quote.current].some(function(p) {
    return !!p && !!p.regular && dateStringOf(localDate(p.regular.start, cal)) === date
  })
  var segs = cal && !described ? segmentsOn(cal, date) : []
  var s = quote.session
  if (!segs.length || !s.regular) return false
  var open = segs[0].start
  var close = segs[segs.length - 1].end
  var pre = !!s.pre && now >= open - (s.regular.start - s.pre.start) && now < open
  var post = !!s.post && now >= close && now < close + (s.post.end - s.regular.end)
  return pre || post
}

// The close and late prints settle within this of a market's last trade.
var SETTLED = 15 * 60

function tradingDay(cal, date) {
  var segs = segmentsOn(cal, date)
  var opens = function(day, first) { return cal.pre ? epochAt(cal, day, cal.pre.open) : first }
  var open = nextOpen(cal, epochAt(cal, nextDateString(date), "00:00"))
  return {
    from: segs.length ? opens(date, segs[0].start) : 0,
    to: segs.length ? (cal.post ? epochAt(cal, date, cal.post.close) : segs[segs.length - 1].end) : 0,
    next: open ? opens(open.dateString, open.t) : 0
  }
}

// Each calendar's day is read once, not once a listing.
function tradingDays() {
  var read = new Map()
  return function(cal, t) {
    var date = dateStringOf(localDate(t, cal))
    if (!read.has(cal)) read.set(cal, {})
    var days = read.get(cal)
    if (!(date in days)) days[date] = tradingDay(cal, date)
    return days[date]
  }
}

// Asking sooner brings back the same price. An index's periods stay the last
// session's until its open, and London's pre-market is Yahoo's alone, so the
// calendar and Yahoo's current period both have a say.
function quietUntil(quote, receivedAt, now, cal, dayOf) {
  if (!quote || quote.crypto || !receivedAt) return 0
  var s = quote.session
  if (!s || !s.regular || receivedAt < (s.post || s.regular).end + SETTLED) return 0
  var c = quote.current
  if (c && c.regular && receivedAt >= (c.pre || c.regular).start && receivedAt < (c.post || c.regular).end + SETTLED) return 0
  var starts = []
  if (cal) {
    var day = dayOf(cal, receivedAt)
    if (day.to && receivedAt >= day.from && receivedAt < day.to + SETTLED) return 0
    var open = receivedAt < day.from ? day.from : day.next
    if (open) starts.push(open)
  }
  if (c && c.regular && (c.pre || c.regular).start > receivedAt) starts.push((c.pre || c.regular).start)
  var next = starts.length ? Math.min.apply(null, starts) : 0
  return next > now ? next : 0
}

// Yahoo's day answer for a stock turns to the coming day with its
// pre-market, and London's and Tokyo's with their open, whose first bar
// comes about 15 minutes late. Two days keep the last session in the answer
// until the new one has a print. An index's answer stays the last session's
// until its open.
function twoDays(quote, now, calendars) {
  if (!quote) return true
  if (quote.crypto) return true
  if (quote.instrumentType === "INDEX") return false
  var cal = calendarFor(calendars, quote)
  var date = cal ? dateStringOf(localDate(now, cal)) : ""
  var segs = cal ? segmentsOn(cal, date) : []
  var pts = quote.points
  var printedSince = function(t) { return pts.length > 0 && pts[pts.length - 1].t >= t }
  if (cal && cal.pre) {
    var pre = epochAt(cal, date, cal.pre.open)
    return segs.length > 0 && now >= pre && (now < segs[0].start || (now < epochAt(cal, date, cal.post.close) && !printedSince(pre)))
  }
  var open = segs.length ? { start: segs[0].start, end: segs[segs.length - 1].end } : !cal && quote.current ? quote.current.regular : null
  return !!open && now >= open.start && now < open.end && !printedSince(open.start)
}

// For minutes after an open, Yahoo's answers, all but a two-day chart, can
// still count the day from the close before last. Each quote carries the
// last close Stonks saw (`closeSeen`, saved with it) for the next weekday's
// session to count from. A split, a dividend or a holiday moves Yahoo's
// base, and Yahoo's stands. A US stock's day turns at 04:00, hours before its
// first trade: a calendar with a pre-market keeps Yahoo's.
function carryClose(previous, quote, calendars) {
  if (!quote || quote.crypto || quote.instrumentType === "INDEX" || !quote.session.regular) return quote
  var cal = calendarFor(calendars, quote)
  if (cal && cal.pre) return quote
  // The next quote reads the close from this one, so an unchanged answer
  // after the bell stays unchanged.
  var seen = previous && !sessionClose(quote) ? sessionClose(previous) || previous.closeSeen || null : null
  if (!seen) return quote
  var reg = quote.session.regular
  var head = Quote.headlineQuote(quote)
  var traded = !!head && head.source === "quote" && head.t !== null && head.t >= reg.start
  var stale = traded && nextWeekday(quote, seen.day, reg.start) && quote.prevClose === seen.before && seen.before !== seen.close
  return Object.assign({}, quote, stale ? { closeSeen: seen, prevClose: seen.close } : { closeSeen: seen })
}

function sessionClose(quote) {
  var reg = quote.session && quote.session.regular
  var head = Quote.headlineQuote(quote)
  return reg && head && head.source === "quote" && head.t !== null && head.t >= reg.end && Format.isFiniteNumber(quote.prevClose)
    ? { day: reg.start, close: head.price, before: quote.prevClose } : null
}

function nextWeekday(quote, from, to) {
  var day = function(t) { return Math.floor((t + (quote.gmtoffset || 0)) / 86400) }
  var weekday = new Date(day(from) * 86400000).getUTCDay()
  return day(to) - day(from) === (weekday === 5 ? 3 : weekday === 6 ? 2 : 1)
}

// Yahoo can answer with the last session's quote for seconds after the open.
var OPENING_WAIT = 60
var OPENING_ASK = 15

function awaitingOpen(quote, now) {
  if (!quote || quote.crypto) return false
  var reg = clockSession(quote, now).regular
  var head = Quote.headlineQuote(quote)
  return !!reg && !!head && head.t !== null && head.t < reg.start && now >= reg.start && now < reg.start + OPENING_WAIT
}

// Outside the session only the day's dim tail can move, so only a hero
// keeps the interval.
function quoteCadence(quote, now, interval, hero, calNow) {
  if (!quote) return 15 * 60
  if (quote.crypto || regularNow(quote, now, calNow)) return awaitingOpen(quote, now) ? Math.min(OPENING_ASK, interval) : interval
  if (calNow.quiet || calNow.breakEnd) return 15 * 60
  var phase = sessionPhase(quote, now)
  if (phase === "pre" || phase === "post") return hero ? interval : Math.max(5 * 60, interval)
  return 15 * 60
}
