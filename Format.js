.pragma library
// How numbers and moments are checked and written: prices, changes and
// their signs, durations, clock times, and the names of days and months.
// Knows nothing of markets, quotes, or where the data comes from.

function isFiniteNumber(v) {
  return typeof v === "number" && isFinite(v)
}

// A list from a fetched answer: `value` when it is an array of at most
// `most` entries, else null. A loop over a fetched list reads only one this
// returned: an object posing as a list, `{"length": 1e300}`, would hold the
// shell's one thread for good.
function fetchedList(value, most) {
  return Array.isArray(value) && value.length <= most ? value : null
}

// A name or code from a fetched answer: `value` when it is a string of at
// most `most` characters, else "", as if the site had sent none. Every
// name and code a parser keeps comes through here, so nothing downstream
// measures, matches, or draws an unbounded string.
function fetchedText(value, most) {
  return typeof value === "string" && value.length <= most ? value : ""
}

// The longest name and code kept, set well above what the saved answers
// hold: names reach 74 characters (a short name of Yahoo's), codes 27 (an
// exchange's display name).
var MOST_NAME = 200
var MOST_CODE = 64

// Whether `t`, in epoch seconds, is a moment a Date can hold (±8.64e12 s)
// at any clock offset (under a day, `Quote.isOffset`), so no reading of it
// throws: a fetched 1e300 would.
function isMoment(t) {
  return isFiniteNumber(t) && Math.abs(t) <= 8.64e12 - 86400
}

var MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

function localClock(t, gmtoffset) {
  var d = new Date((t + gmtoffset) * 1000)
  return { hour: d.getUTCHours(), minute: d.getUTCMinutes(), weekday: d.getUTCDay() }
}

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

function hhmm(t, gmtoffset) {
  var c = localClock(t, gmtoffset)
  return pad2(c.hour) + ":" + pad2(c.minute)
}

// The reader's own UTC offset at `t`, in seconds east: the machine's zone,
// which is where the reader is. Not a clock: the moment is given.
function readerOffset(t) {
  return -new Date(t * 1000).getTimezoneOffset() * 60
}

// An offset as UTC writes it, for a zone with no name to hand: "UTC+5:30".
function offsetName(offset) {
  if (!offset) return "UTC"
  var abs = Math.abs(offset)
  var minutes = Math.round(abs / 60) % 60
  return "UTC" + (offset > 0 ? "+" : MINUS) + Math.floor(abs / 3600) + (minutes ? ":" + pad2(minutes) : "")
}

// An exchange's time is said with its zone's name only where that is not
// the reader's own clock at that moment: Tokyo's "09:00 JST" for a reader in
// New York, "09:00" for one in Tokyo, and Nasdaq's "09:30" in New York or
// Toronto alike.
function zoned(clock, t, offset, name) {
  return offset === readerOffset(t) ? clock : clock + " " + (name || offsetName(offset))
}

// `hhmm` in the exchange's zone, named where the reader's differs.
function zonedHhmm(t, gmtoffset, name) {
  return zoned(hhmm(t, gmtoffset), t, gmtoffset, name)
}

// A countdown to a bell, in whole minutes rounded up: its last minute reads
// 1m, never 0m.
function duration(seconds) {
  var s = Math.ceil(Math.abs(seconds) / 60) * 60
  var d = Math.floor(s / 86400)
  var h = Math.floor((s % 86400) / 3600)
  var m = Math.floor((s % 3600) / 60)
  if (d > 0) return d + "d" + (h ? " " + h + "h" : "")
  if (h === 0) return m + "m"
  return h + "h" + (m ? " " + pad2(m) + "m" : "")
}

// A true minus, the width of the plus, so signed figures line up.
var MINUS = "\u2212"

// Thousands commas in the whole part only: 0.000005410 keeps its decimals
// together.
function grouped(digits) {
  var parts = String(digits).split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return parts.join(".")
}

// The sign a figure shows once it is rounded the way it is drawn. A move
// that rounds to nothing is no move: it takes no sign and no colour.
function shownSign(value, digits) {
  if (!isFiniteNumber(value) || Number(Math.abs(value).toFixed(digits)) === 0) return 0
  return value > 0 ? 1 : -1
}

function moneyDigits(abs) {
  return abs >= 10000 ? 0 : 2
}

// The decimals a listing's prices take, decided once from its headline
// price, so a scrub or a refresh never changes their width: Yahoo's hint;
// on a market that trades in whole cents from 1 up (`inCents`: the US, by
// Reg NMS, `Market.centExchanges`), cents there, or the hint where coarser
// (its hint of 4 under $5 read "4.6500"), while a coin (XRP-USD's 1.3065)
// or a European listing (IAG's 4.9270 in Madrid) trades finer and keeps
// it; under 1 the hint at least, and four significant digits (SHIB's
// 0.000005420, where its hint of 5 reads 0.00001); none from 10,000 up,
// where cents say nothing.
// toFixed's own limit; no price comes near it.
var MAX_PRICE_DIGITS = 100

function priceDigits(price, hint, inCents) {
  var digits = isFiniteNumber(hint) && hint >= 0 ? hint : 2
  if (isFiniteNumber(price)) {
    var abs = Math.abs(price)
    if (abs >= 10000) return 0
    if (abs >= 1 && inCents) digits = Math.min(digits, 2)
    else if (abs > 0 && abs < 1) digits = Math.max(digits, 3 - Math.floor(Math.log(abs) / Math.LN10))
  }
  return Math.min(MAX_PRICE_DIGITS, digits)
}

// The least a listing's price moves by: one unit of Yahoo's hint; on a
// market that trades in whole cents from 1 up (`inCents`), a cent there,
// or the hint's unit where coarser; under 1 never coarser than the price's
// second significant digit (SHIB's hint of 0.00001 is twice its price).
// Null without a price.
function priceTick(price, hint, inCents) {
  if (!isFiniteNumber(price) || price === 0) return null
  var abs = Math.abs(price)
  var digits = isFiniteNumber(hint) && hint >= 0 ? hint : 2
  if (abs >= 1 && inCents) digits = Math.min(digits, 2)
  else if (abs < 1) digits = Math.max(digits, 1 - Math.floor(Math.log(abs) / Math.LN10))
  return Math.pow(10, -digits)
}

// A move in money takes its listing's decimals, and at least cents under
// 10,000: Bitcoin's whole-number price moves by $2,105.77.
function moveDigits(abs, digits) {
  return abs >= 10000 ? 0 : Math.max(2, isFiniteNumber(digits) ? digits : 2)
}

// Decimals stop mattering once a move is four digits wide.
function pctDigits(abs) {
  return abs >= 1000 ? 0 : 2
}

function signText(sign) {
  return sign > 0 ? "+" : sign < 0 ? MINUS : ""
}

// A price, in its listing's decimals (`priceDigits`) when given.
function money(value, digits) {
  if (value === null || value === undefined || isNaN(value)) return "—"
  var abs = Math.abs(value)
  var shown = isFiniteNumber(digits) ? digits : moneyDigits(abs)
  return (shownSign(value, shown) < 0 ? MINUS : "") + grouped(abs.toFixed(shown))
}

function pct(value) {
  return isFiniteNumber(value) ? percent(value, pctDigits(Math.abs(value))) : "—"
}

// A move rounded for a side bar's stack: one decimal under 10%, none from
// there. It is the rows' figure (`pct`) rounded half up, in whole
// hundredths so no float can tip it, so the two never disagree: the rows'
// +9.95% reads +10, their +0.05% +0.1, however the quote's prices made it.
// `shown` is its size.
function narrowPctShown(value) {
  var abs = Math.abs(value)
  var hundredths = Math.round(Number(abs.toFixed(pctDigits(abs))) * 100)
  var tenths = Math.round(hundredths / 10)
  return tenths >= 100 ? { digits: 0, shown: Math.round(hundredths / 100) } : { digits: 1, shown: tenths / 10 }
}

// A bar at the side of the screen stacks the pill as Omarchy's clock stacks
// its lines, one to an icon slot, each at most STACK_WIDTH characters: as
// many as fit its 28 px at the clock's sizes.
var STACK_WIDTH = 4

// `text` broken after every STACK_WIDTH characters.
function stackChunks(text) {
  var out = []
  for (var i = 0; i < text.length; i += STACK_WIDTH) out.push(text.slice(i, i + STACK_WIDTH))
  return out
}

// A symbol's stacked lines: an index without its ^ (GSPC), a longer one
// split at its first dot or dash (SHEL .L, BTC -USD), and any part still
// longer broken after its fourth character (GOOG L).
function stackedSymbol(symbol) {
  var s = String(symbol).replace(/^\^/, "")
  if (s.length <= STACK_WIDTH) return [s]
  var at = s.search(/[.\-]/)
  var parts = at > 0 ? [s.slice(0, at), s.slice(at)] : [s]
  return parts.reduce(function(out, part) { return out.concat(stackChunks(part)) }, [])
}

// A magnitude of a thousand or more, in its unit as compactNumber names
// them: one decimal under 10, none from there, and a figure that rounds to
// 1,000 of its unit is one of the next. At most three characters, so its
// sign fits beside it.
function stackedThousands(abs) {
  var units = ["K", "M", "B", "T"]
  var v = abs
  var u = -1
  do {
    v /= 1000
    u++
  } while (Math.round(v) >= 1000 && u < units.length - 1)
  return { figure: Math.round(v * 10) < 100 ? v.toFixed(1) : String(Math.round(v)), unit: units[u] }
}

// A move in percent stacked, its sign and figure over its %: −1.5 over %,
// −12 over % from 10% (`narrowPctShown`), and from 1,000% in thousands,
// 1.2 over K%. `sign` is the figure's as drawn.
function stackedPct(value) {
  if (!isFiniteNumber(value)) return { lines: ["—"], sign: 0 }
  var narrow = narrowPctShown(value)
  var sign = narrow.shown === 0 ? 0 : value > 0 ? 1 : -1
  if (narrow.shown >= 1000) {
    var big = stackedThousands(narrow.shown)
    return { lines: [signText(sign) + big.figure, big.unit + "%"], sign: sign }
  }
  return { lines: [signText(sign) + narrow.shown.toFixed(narrow.digits), "%"], sign: sign }
}

// A move in money stacked, as `signedMoney` writes it, split at its point
// with its sign kept: −3 over .84, and a fraction too long for a line
// broken after its fourth character, as a coin under a cent's is. From a
// thousand, in its unit: 8.9 over K.
function stackedMoney(value, digits) {
  if (!isFiniteNumber(value)) return { lines: ["—"], sign: 0 }
  var shown = moveDigits(Math.abs(value), digits)
  var sign = shownSign(value, shown)
  var fixed = Math.abs(value).toFixed(shown)
  if (Number(fixed) >= 1000) {
    var big = stackedThousands(Number(fixed))
    return { lines: [signText(sign) + big.figure, big.unit], sign: sign }
  }
  var parts = fixed.split(".")
  return { lines: [signText(sign) + parts[0]].concat(parts.length > 1 ? stackChunks("." + parts[1]) : []), sign: sign }
}

function percent(value, digits) {
  return signText(shownSign(value, digits)) + grouped(Math.abs(value).toFixed(digits)) + "%"
}

// A move in money, signed, in its listing's decimals (`moveDigits`).
function signedMoney(value, digits) {
  var shown = moveDigits(Math.abs(value), digits)
  return signText(shownSign(value, shown)) + money(Math.abs(value), shown)
}

// One sign language per look: smooth says + and −, retro says ▲ and ▼. An
// unmoved figure has no sign in either.
function lookSigns(text, retro) {
  return retro ? String(text).replace("+", "▲").replace(MINUS, "▼") : text
}

// The change figure alone. What it is measured from, when that is not the
// previous close, is said beside it: under the hero's figure as its caption
// (changeCaption), inline on the rows and the pill (changeLine).
// `digits` is the listing's price decimals, for a move in money.
function changeText(chg, mode, digits) {
  if (chg.pct === null) return "—"
  if (mode === "abs") return signedMoney(chg.abs, digits)
  return pct(chg.pct)
}

function changeCaption(mode) {
  return mode === "open" ? "SINCE OPEN" : ""
}

// Which way a change figure reads, from the figure as drawn, so its colour
// can never disagree with its sign: "up", "down", or "flat" when it rounds to
// nothing or there is no figure at all.
function changeTone(chg, mode, digits) {
  if (!chg || chg.pct === null) return "flat"
  var sign = mode === "abs" ? shownSign(chg.abs, moveDigits(Math.abs(chg.abs), digits))
    : shownSign(chg.pct, pctDigits(Math.abs(chg.pct)))
  return sign > 0 ? "up" : sign < 0 ? "down" : "flat"
}

// A count in its unit: 52.4M, 1.6B, 4.75T. A figure that rounds up to 1,000
// of its unit is one of the next (999.96M is 1.0B, never 1000.0M), and
// trillions, the last unit, take fewer decimals as they grow (33.82T,
// 400.1T, 1234T, a cap in won or rupiah), so no count draws wider than
// 999.9M.
function compactNumber(n) {
  if (n === null || n === undefined || isNaN(n)) return "—"
  if (n >= 999.95e9) {
    var t = n / 1e12
    return String(Number(t.toFixed(t >= 999.95 ? 0 : t >= 99.995 ? 1 : 2))) + "T"
  }
  if (n >= 999.95e6) return (n / 1e9).toFixed(1) + "B"
  if (n >= 999.5e3) return (n / 1e6).toFixed(1) + "M"
  if (n >= 1e3) return (n / 1e3).toFixed(0) + "K"
  return String(n)
}

// The widest a figure of this shape draws: every digit an 8. A column sized
// by it holds any value with the same digits, so a refresh that changes the
// value never moves what stands beside it.
function widest(text) {
  return String(text).replace(/\d/g, "8")
}

// An info line's range: its low and high, each null and "" when not known,
// the price whose place it marks, and the widest a price of the listing's
// takes at its decimals, from the largest price the line knows.
function infoRange(low, high, price, digits) {
  var known = function(v) { return isFiniteNumber(v) ? v : null }
  low = known(low)
  high = known(high)
  price = known(price)
  var largest = [low, high, price].reduce(function(m, v) { return v === null ? m : Math.max(m, Math.abs(v)) }, -1)
  return {
    low: low,
    high: high,
    price: price,
    lowText: low === null ? "" : money(low, digits),
    highText: high === null ? "" : money(high, digits),
    lowTone: "",
    highTone: "",
    widest: largest < 0 ? "" : widest(money(largest, digits))
  }
}

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v))
}
