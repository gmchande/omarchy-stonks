.pragma library
.import "Format.js" as Format

// What calendars.json says of an exchange: its days, sessions, holidays,
// early closes and clocks. No keyless holiday feed exists, so Stonks carries
// them.

function calendarMap(calendars) {
  if (!calendars) return null
  return calendars.calendars
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

// A calendar knows the days from its `validFrom` to its `validThrough`: no
// holiday and no change of clocks outside them.
function covers(cal, dateString) {
  return dateString >= cal.validFrom && dateString <= cal.validThrough
}

function dayKind(cal, dateString) {
  if (!cal || !dateString || !covers(cal, dateString)) return { kind: "unknown" }
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

function previousDateString(dateString) {
  var p = dateString.split("-")
  var d = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2] - 1))
  return d.getUTCFullYear() + "-" + Format.pad2(d.getUTCMonth() + 1) + "-" + Format.pad2(d.getUTCDate())
}

// The trading day before the one that starts at `dayStart`, by the listing's
// calendar, as a date string: none without a calendar, or past its reach.
function closeBeforeDate(cal, dayStart) {
  if (!cal) return null
  var date = dateStringOf(localDate(dayStart, cal))
  for (var i = 0; i < 10; i++) {
    date = previousDateString(date)
    var kind = dayKind(cal, date).kind
    if (kind === "open") return date
    if (kind === "unknown") return null
  }
  return null
}

// That day's regular close, an early one included, as a moment.
function closeBefore(cal, dayStart) {
  var date = closeBeforeDate(cal, dayStart)
  if (date === null) return null
  var segs = segmentsOn(cal, date)
  return segs[segs.length - 1].end
}

// The after-hours last as long after a half day's 13:00 close as after a
// full day's, so they end at 17:00. For a day the market trades.
function postClose(cal, date) {
  var segs = segmentsOn(cal, date)
  var full = epochAt(cal, date, cal.post.close)
  return Math.min(full, segs[segs.length - 1].end + full - epochAt(cal, date, cal.post.open))
}

function clockOf(local) {
  return Format.pad2(local.hour) + ":" + Format.pad2(local.minute)
}

function tradingDay(cal, date) {
  var segs = segmentsOn(cal, date)
  var opens = function(day, first) { return cal.pre ? epochAt(cal, day, cal.pre.open) : first }
  var open = nextOpen(cal, epochAt(cal, nextDateString(date), "00:00"))
  return {
    from: segs.length ? opens(date, segs[0].start) : 0,
    to: segs.length ? (cal.post ? postClose(cal, date) : segs[segs.length - 1].end) : 0,
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
