.pragma library
.import "Format.js" as Format
.import "Quote.js" as Quote

// Exchange calendars and sessions: the schedules in calendars.json, the
// phase a quote's periods put the clock in, the bells, the header's words,
// a print's clock in its own exchange's time, and the refresh cadence the
// phases ask for. Knows nothing of Robinhood, history, or settings.
//
// The calendars are a file the plugin carries, because no keyless holiday
// feed exists. Yahoo still owns today; the calendars speak after the close,
// before a day's window exists, between Tokyo's segments, and for the next
// honest open.

var PHASES = {
  closed: "Closed", weekend: "Weekend", pre: "Pre-market",
  opening: "Opening bell", open: "Market open", lunch: "Lunch lull", power: "Power hour",
  closing: "Closing bell", post: "After hours", always: "Open around the clock", overnight: "Overnight"
}

// The session the clock is in at `t`: the bars' own, until the clock has
// left it and entered Yahoo's current period, which a quote held without a
// fetch reaches (Monday's pre-market on Friday's bars, London's open on
// Thursday's). The chart, the open, and the info line keep the bars'.
function clockSession(quote, t) {
  var s = quote.session
  var c = quote.current
  if (!c || !c.regular || !s.regular || t < (s.post || s.regular).end) return s
  return t >= (c.pre || c.regular).start && t < (c.post || c.regular).end ? c : s
}

// The phase at time `t`, from the exchange's own periods and nothing else.
// The chart endpoint carries no market state, and a missing series is not
// evidence of a holiday, so a session the periods describe is trusted. Its
// day and hour are by the clock of `t`'s own period (`Quote.clockAt`): a
// scrub of Friday's lunch on the Sunday the clocks went back is at noon.
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
  // A weekend is a Saturday or Sunday the session isn't on: Saudi's exchange
  // trades on Sunday, so its Sunday is open, then closed after its bell.
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

// Seconds to a bell the exchange has actually announced: the close while
// the session runs, the open while it is still ahead. Yahoo describes one
// session per response, so once it has ended there is nothing to count to.
// Guessed by adding days, the next open would land on holidays like Labor Day.
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

// The listing's calendar: the one naming its exchange, or naming the index
// itself, where Yahoo files it under a name that holds indexes on other
// hours too (^FTSE beside FTSE's global ones, ^RUT beside Cboe's VVIX).
function calendarFor(calendars, quote) {
  var map = calendarMap(calendars)
  if (!map || !quote || !quote.exchange) return null
  for (var id in map) {
    var cal = map[id]
    if (cal && ((cal.exchanges && cal.exchanges.indexOf(quote.exchange) >= 0) || (cal.indexes && cal.indexes.indexOf(quote.symbol) >= 0))) return cal
  }
  return null
}

// The exchanges whose listings trade in whole cents from $1: the US
// calendar's, by Reg NMS. A coin or a European listing trades finer
// (`Format.priceDigits`). None without calendars.
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

// A calendar's zone by its name at `offset` ("EDT" or "EST"), else the
// quote's own where its offset is that one, else the offset itself.
function zoneName(cal, offset, quote) {
  var names = cal && cal.zoneNames
  if (names && names[String(offset)]) return names[String(offset)]
  if (quote && quote.zoneName && quote.gmtoffset === offset) return quote.zoneName
  return Format.offsetName(offset)
}

// A calendar's clock at `t`, its zone named where the reader's differs.
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

// The breaks between a trading day's segments, Tokyo's lunch: each from one
// segment's close to the next one's open, on the calendar day of `t`.
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

// What a market's calendar says at `now`, the same for every listing on
// it, so a walk over a list reads each calendar once (`Service.askDue`):
// whether its day is a weekend or a published closure (`quiet`), the end of
// the break between segments it is in (`breakEnd`, Tokyo's lunch), and
// whether one of its segments trades (`segment`). A listing with no
// calendar (`cal` null) has none of these.
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

// The calendar's regular session on the day of `now`, from its first
// segment's open to its last's close, while one of them trades at `now`;
// else null, as on a weekend, a closure, or with no calendar.
function calendarRegular(cal, now) {
  var segs = cal ? segmentsOn(cal, dateStringOf(localDate(now, cal))) : []
  if (!segs.some(function(seg) { return now >= seg.start && now < seg.end })) return null
  return { start: segs[0].start, end: segs[segs.length - 1].end }
}

function scheduleNote(quote, now, calendars) {
  var cal = calendarFor(calendars, quote)
  if (!cal) return calendarMap(calendars) ? "" : " · schedule unavailable"
  var nxt = nextOpen(cal, now)
  return nxt ? " · " + formatNextOpen(cal, nxt) : " · schedule unavailable"
}

function previousDateString(dateString) {
  var p = dateString.split("-")
  var d = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2] - 1))
  return d.getUTCFullYear() + "-" + Format.pad2(d.getUTCMonth() + 1) + "-" + Format.pad2(d.getUTCDate())
}

function clockOf(local) {
  return Format.pad2(local.hour) + ":" + Format.pad2(local.minute)
}

// Where a scrub sits: the session of the print it reads, outside Yahoo's
// day; the exchange's own phase inside it.
function scrubPhase(quote, t) {
  if (!quote.axis || (t >= Quote.dayStart(quote) && t < Quote.dayEnd(quote))) return sessionPhase(quote, t)
  var pts = quote.points
  var session = ""
  for (var i = 0; i < pts.length && pts[i].t <= t; i++) session = Quote.pointSession(quote, pts[i])
  return session === "reg" ? "open" : session || "closed"
}

// The calendar that knows the clock of `quote`'s exchange at `t`: the
// series' own or the listing's in `calendars`, while `t` falls on a day up
// to its last (`validThrough`). Null past it, where a change of clocks it
// doesn't list would read as standard time, an hour out: Toronto's July
// 2027 close would read "15:00 EST".
function clockCalendar(quote, t, calendars) {
  var cal = quote.calendar || calendarFor(calendars, quote)
  return cal && dateStringOf(localDate(t, cal)) <= cal.validThrough ? cal : null
}

// A time where `quote` trades: by its calendar's offset for that moment's
// date (`clockCalendar`), so a time across a change of clocks reads true;
// else by the clock Yahoo's periods say its day kept (`Quote.clockAt`), or
// Yahoo's own offset. Its zone is named where the reader's clock differs.
function printClock(quote, t, calendars) {
  var cal = clockCalendar(quote, t, calendars)
  if (cal) return calendarClock(cal, t, quote)
  var clock = Quote.clockAt(quote, t)
  return Format.zonedHhmm(t, clock.offset, clock.zone)
}

// A closure as the header names it: the holiday, without the calendar's
// "observed" or "(substitute)". The reader learns the market is shut,
// why, and when it opens without it, and the popup has no room for Tokyo's
// "Constitution Memorial Day observed" beside its next open. The calendars
// keep their source's names, since they are renewed from it.
function holidayName(name) {
  return name.replace(/ (observed|\(substitute\))$/, "")
}

// The one time that matters: how long until the market opens or closes,
// when the exchange has said. "Closes in" already says it is open. After
// the bell the phase stands on its own, with the regular close named so
// 16:00 is never mistaken for the end of after-hours trading. A quote held
// from an earlier session, before the new day's answer lands, has the
// calendar's session stand in while one of its segments trades
// (`calendarRegular`), so the open says "Opening bell", not the next day's
// open; an index counts to the open through its calendar's pre-market
// (`indexBell`). A listing whose overnight session is on (`overnight`,
// `Overnight.nightTrades`) is in it, as the line under the price says, a
// weekend's or a holiday's evening included. While scrubbing, where in the
// day the finger is: at the close's own time, the closing bell, when it
// reads the close (`Quote.readingAt`).
function marketStatus(quote, now, scrubT, calendars, overnight) {
  return statusForms(quote, now, scrubT, calendars, overnight)[0]
}

// The status, then the same said in less, each form shorter than the one
// before, for a header with no room for the one before. First a closure's
// notice without the holiday's name, worded as a weekend's is ("Closed ·
// opens Tue 09:30"), and a lunch break without its countdown ("Lunch break
// · reopens 12:30 JST"). Then the time alone, with what it is: without the
// session's name, which the line under the price says whenever an
// extended price shows, and the day's ("Opens Tue 09:30", "Closed at
// 16:00"), and a scrub without its moment's name ("At 02:25"); a schedule
// that has run out says only that. Every form keeps the time, its day, and
// its zone. A scrubbed print from another day than `now`'s where the
// listing trades names that day ("At Sun 21:10 · Overnight": Sunday
// night's chart is still on screen at Monday 01:00).
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
  // The stand-in reads the hour by the calendar's clock today, not the
  // held answer's, which may be from before a change of clocks: otherwise
  // a New York quote held from EDT into EST would say "Lunch lull" at 11:00.
  var held = !overnight && !isTrading(sessionPhase(quote, now)) ? calendarRegular(cal, now) : null
  var q = held ? Object.assign({}, quote, { session: { pre: null, regular: held, post: null }, current: null,
    clocks: [], gmtoffset: localDate(now, cal).offset }) : quote
  var phase = overnight ? "overnight" : sessionPhase(q, now)
  var bell = secondsToBell(q, now) || indexBell(quote, cal, now)
  var kind = cal ? dayKind(cal, dateStringOf(localDate(now, cal))) : null
  // A published closure outranks a cached response that still describes a
  // session: on a holiday Yahoo may hand back a window nobody is trading.
  var closure = !overnight && kind && kind.kind === "closure"
  // The day's named moments lead while they last, as they do in a scrub. A
  // morning with a break ahead counts to the break, not the day's close:
  // Tokyo stops at 11:30, so at 11:26 "Market closes in 4h 4m" would be
  // four hours wrong.
  if (!closure && bell && bell.bell === "close") {
    var named = phase === "opening" || phase === "lunch" || phase === "power" || phase === "closing"
    var pause = sessionBreaks(cal, now).filter(function(b) { return now < b.start })[0]
    var closes = pause ? "lunch break in " + Format.duration(pause.start - now) : "closes in " + Format.duration(bell.seconds)
    return [named ? phaseLabel(phase) + " · " + closes : pause ? sentence(closes) : "Market " + closes, sentence(closes)]
  }
  // An index has no pre-market of its own, so before its open it is closed,
  // said in the shape its stocks' "Pre-market · opens in 3h 10m" is,
  // whatever periods Yahoo sent it.
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

// The day `t` falls on where `quote` trades, said before its clock when it
// isn't the day of `now` there: its weekday within the week ("Sun "), else
// its date ("6 Oct "), never a weekday that would read as this week's.
// The day by the clock `printClock` reads.
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

// An index has no pre-market of its own, and Yahoo's periods for it stay
// the last session's until it opens (the S&P 500's until 09:30:12 on Friday
// 23 October), so its own bell has nothing to count to: through its
// calendar's pre-market on a trading day it counts to the open, as the
// stocks beside it do.
function indexBell(quote, cal, now) {
  if (quote.instrumentType !== "INDEX" || !cal || !cal.pre) return null
  var date = dateStringOf(localDate(now, cal))
  var segs = segmentsOn(cal, date)
  if (!segs.length || now < epochAt(cal, date, cal.pre.open) || now >= segs[0].start) return null
  return { seconds: segs[0].start - now, bell: "open" }
}

// Whether a quote's own market is in its regular session now: Yahoo's
// periods, or, for a quote held from an earlier day, the calendar's, which
// the periods cannot know; less a published closure and a break between
// segments (Tokyo's lunch). Never a cryptocurrency, which has none.
function inRegularSession(quote, now, calendars) {
  return regularNow(quote, now, calendarNow(calendarFor(calendars, quote), now))
}

// `inRegularSession` by its calendar's reading at `now` (`calendarNow`).
function regularNow(quote, now, calNow) {
  if (!quote || quote.crypto || calNow.quiet || calNow.breakEnd) return false
  return isTrading(sessionPhase(quote, now)) || calNow.segment
}

// The bell a quote's market rings as the clock moves on from `before` to
// `now`: "open" where its regular session begins between them, "close"
// where it ends, else "". A break between segments (Tokyo's lunch) rings
// neither, so each rings once a day; a closure, a weekend, and a
// cryptocurrency never enter a session, so ring nothing. A step of the
// clock longer than 90 seconds, Stonks starting after the bell or the
// machine waking from sleep, rings nothing: a bell is never late.
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

// Whether a quote's own market is in its pre-market or after hours now:
// Yahoo's periods; or, for a quote held from an earlier day, whose periods,
// its bars' and its current ones, don't describe today, the listing's own
// extended hours, as long as its periods have them before and after its
// regular session (an index's have none), around today's segments in its
// calendar, so an early close's after hours ends as early; less a
// published closure.
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

// Whether a stock, ETF, or index is kept fresh with nothing open: through
// its regular session; and a listing with no calendar to say when that is
// (an index's), on the slow clock once every period its quote knows is
// past, so it learns of its next session. By its calendar's reading at
// `now` (`calendarNow`).
function staysWarm(quote, now, calNow) {
  if (!quote || quote.crypto) return false
  if (regularNow(quote, now, calNow)) return true
  if (calNow.cal) return false
  var latest = quote.current && quote.current.regular ? quote.current : quote.session
  var last = latest.post || latest.regular
  return !!last && now >= last.end
}

// Whether a listing's day answer is asked for two days (`Quote.chartUrl`):
// one with no quote yet, whose market and hour aren't known; a
// cryptocurrency's always, for its last 24 hours (`Quote.coinDay`); on a
// trading day of a calendar with a pre-market, from the pre-market's open
// until the session opens; and on any other, from the session's open, by
// its calendar or else Yahoo's current period (Sydney's), until the quote
// holds a print of it. Yahoo's day answer for a stock turns
// to the coming day with its pre-market (AAPL's at 06:22 on Friday 23
// October held Friday from 04:00 and nothing of Thursday), and London's
// and Tokyo's at their open, its first bar a quarter of an hour behind
// (SHEL.L's at 04:05 New York on Monday 26 October held nothing), while
// the 1D chart shows the last day until the new one has a print
// (`Quote.tailDay`). Never an index's, whose answer stays the last
// session's until its open.
function twoDays(quote, now, calendars) {
  if (!quote) return true
  if (quote.crypto) return true
  if (quote.instrumentType === "INDEX") return false
  var cal = calendarFor(calendars, quote)
  var date = cal ? dateStringOf(localDate(now, cal)) : ""
  var segs = cal ? segmentsOn(cal, date) : []
  if (cal && cal.pre) return segs.length > 0 && now >= epochAt(cal, date, cal.pre.open) && now < segs[0].start
  var open = segs.length ? { start: segs[0].start, end: segs[segs.length - 1].end } : !cal && quote.current ? quote.current.regular : null
  var pts = quote.points
  return !!open && now >= open.start && now < open.end && !(pts.length && pts[pts.length - 1].t >= open.start)
}

// How long after a session opens its first price may still be on its way,
// and how often a quote still waiting on it is asked for meanwhile: Yahoo
// answered with the last session's quote until 09:30:09 for the S&P 500
// and 09:30:12 for AAPL on Friday 23 October.
var OPENING_WAIT = 60
var OPENING_ASK = 15

// Whether `quote`'s regular session opened under OPENING_WAIT ago at `now`
// and its headline is still from before it: the session's first price is
// on its way. Answers asked at 09:30:00 can still bring back the last
// session's; without this, every US row would say "As of Thu 16:00" until
// the next ask, a minute on.
function awaitingOpen(quote, now) {
  if (!quote || quote.crypto) return false
  var reg = clockSession(quote, now).regular
  var head = Quote.headlineQuote(quote)
  return !!reg && !!head && head.t !== null && head.t < reg.start && now >= reg.start && now < reg.start + OPENING_WAIT
}

// How often a symbol's quote is asked for, in seconds, by its own market
// now and never by the rest of the list: the refresh interval while it
// trades (always, for a cryptocurrency), and every OPENING_ASK seconds at
// most while its session's first price is on its way (`awaitingOpen`); in
// pre-market and after hours, when only the dim tail of its day can move,
// every 5 minutes unless it is the hero of an open surface; and every 15
// minutes while its market is closed, for a night, a weekend, a holiday, or
// a break. A symbol with no quote is asked again on the slow clock too. By
// its calendar's reading at `now` (`calendarNow`).
function quoteCadence(quote, now, interval, hero, calNow) {
  if (!quote) return 15 * 60
  if (quote.crypto || regularNow(quote, now, calNow)) return awaitingOpen(quote, now) ? Math.min(OPENING_ASK, interval) : interval
  if (calNow.quiet || calNow.breakEnd) return 15 * 60
  var phase = sessionPhase(quote, now)
  if (phase === "pre" || phase === "post") return hero ? interval : Math.max(5 * 60, interval)
  return 15 * 60
}
