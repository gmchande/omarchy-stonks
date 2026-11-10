.pragma library
// Checks and writes numbers and moments. Knows nothing of markets, quotes,
// or where the data comes from.

function isFiniteNumber(v) {
  return typeof v === "number" && isFinite(v)
}

// A loop over a fetched list reads only one this returned: an object posing
// as a list, `{"length": 1e300}`, would hold the shell's one thread for good.
function fetchedList(value, most) {
  return Array.isArray(value) && value.length <= most ? value : null
}

// Every name and code a parser keeps comes through here.
function fetchedText(value, most) {
  return typeof value === "string" && value.length <= most ? value : ""
}

// Well over the saved answers' longest: a name of 74 characters, a code of 27.
var MOST_NAME = 200
var MOST_CODE = 64

// A Date holds ±8.64e12 s; a day less leaves room for any clock offset.
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

// The machine's zone is the reader's.
function readerOffset(t) {
  return -new Date(t * 1000).getTimezoneOffset() * 60
}

function offsetName(offset) {
  if (!offset) return "UTC"
  var abs = Math.abs(offset)
  var minutes = Math.round(abs / 60) % 60
  return "UTC" + (offset > 0 ? "+" : MINUS) + Math.floor(abs / 3600) + (minutes ? ":" + pad2(minutes) : "")
}

function zoned(clock, t, offset, name) {
  return offset === readerOffset(t) ? clock : clock + " " + (name || offsetName(offset))
}

function zonedHhmm(t, gmtoffset, name) {
  return zoned(hhmm(t, gmtoffset), t, gmtoffset, name)
}

// Sentence case for words the header writes in capitals, keeping a day's
// and a month's name and a zone: "As of Thu 16:39 BST", "As of 2 Sep 13:17".
var NAMED = new RegExp("\\b(" + WEEKDAYS.concat(MONTHS).join("|").toLowerCase() + ")\\b", "g")
function sentenceCase(text) {
  var sentence = text.charAt(0) + text.slice(1).toLowerCase()
  return sentence.replace(NAMED, function(name) { return name.charAt(0).toUpperCase() + name.slice(1) })
    .replace(/(\d\d:\d\d) (\S+)/, function(all, clock, zone) { return clock + " " + zone.toUpperCase() })
}

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

function grouped(digits) {
  var parts = String(digits).split(".")
  parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  return parts.join(".")
}

// A double can't hold a half-cent: Yahoo's 83.705 is 83.70499…, which toFixed
// rounds down. Nudged away from zero by far less than any price's last digit,
// a half rounds away from zero, as other apps round it.
function fixed(value, digits) {
  return (value * (1 + 1e-12)).toFixed(digits)
}

function shownSign(value, digits) {
  if (!isFiniteNumber(value) || Number(fixed(Math.abs(value), digits)) === 0) return 0
  return value > 0 ? 1 : -1
}

// The digits a figure shows below `limit`, from which it shows none. One
// that rounds up to the limit shows none either: 999.996% reads +1,000%,
// as 1,000% does, not +1,000.00%.
function digitsBelow(abs, limit, digits) {
  return Number(fixed(abs, digits)) >= limit ? 0 : digits
}

function moneyDigits(abs) {
  return digitsBelow(abs, 10000, 2)
}

// toFixed's own limit; no price comes near it.
var MAX_PRICE_DIGITS = 100

// US markets trade in whole cents from $1, by Reg NMS
// (`Market.centExchanges`).
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

function priceTick(price, hint, inCents) {
  if (!isFiniteNumber(price) || price === 0) return null
  var abs = Math.abs(price)
  var digits = isFiniteNumber(hint) && hint >= 0 ? hint : 2
  if (abs >= 1 && inCents) digits = Math.min(digits, 2)
  else if (abs < 1) digits = Math.max(digits, 1 - Math.floor(Math.log(abs) / Math.LN10))
  return Math.pow(10, -digits)
}

function moveDigits(abs, digits) {
  return digitsBelow(abs, 10000, Math.max(2, isFiniteNumber(digits) ? digits : 2))
}

function pctDigits(abs) {
  return digitsBelow(abs, 1000, 2)
}

function signText(sign) {
  return sign > 0 ? "+" : sign < 0 ? MINUS : ""
}

function money(value, digits) {
  if (value === null || value === undefined || isNaN(value)) return "—"
  var abs = Math.abs(value)
  var shown = isFiniteNumber(digits) ? digits : moneyDigits(abs)
  return (shownSign(value, shown) < 0 ? MINUS : "") + grouped(fixed(abs, shown))
}

function pct(value) {
  return isFiniteNumber(value) ? percent(value, pctDigits(Math.abs(value))) : "—"
}

function narrowPctShown(value) {
  var abs = Math.abs(value)
  var hundredths = Math.round(Number(fixed(abs, pctDigits(abs))) * 100)
  var tenths = Math.round(hundredths / 10)
  return tenths >= 100 ? { digits: 0, shown: Math.round(hundredths / 100) } : { digits: 1, shown: tenths / 10 }
}

// On a side bar Omarchy's clock stacks its lines one to an icon slot; four
// characters fit its 28 px at the clock's sizes.
var STACK_WIDTH = 4

function stackChunks(text) {
  var out = []
  for (var i = 0; i < text.length; i += STACK_WIDTH) out.push(text.slice(i, i + STACK_WIDTH))
  return out
}

function stackedSymbol(symbol) {
  var s = String(symbol).replace(/^\^/, "")
  if (s.length <= STACK_WIDTH) return [s]
  var at = s.search(/[.\-]/)
  var parts = at > 0 ? [s.slice(0, at), s.slice(at)] : [s]
  return parts.reduce(function(out, part) { return out.concat(stackChunks(part)) }, [])
}

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

function stackedMoney(value, digits) {
  if (!isFiniteNumber(value)) return { lines: ["—"], sign: 0 }
  var shown = moveDigits(Math.abs(value), digits)
  var sign = shownSign(value, shown)
  var fixedText = fixed(Math.abs(value), shown)
  if (Number(fixedText) >= 1000) {
    var big = stackedThousands(Number(fixedText))
    return { lines: [signText(sign) + big.figure, big.unit], sign: sign }
  }
  var parts = fixedText.split(".")
  return { lines: [signText(sign) + parts[0]].concat(parts.length > 1 ? stackChunks("." + parts[1]) : []), sign: sign }
}

function percent(value, digits) {
  return signText(shownSign(value, digits)) + grouped(fixed(Math.abs(value), digits)) + "%"
}

function signedMoney(value, digits) {
  var shown = moveDigits(Math.abs(value), digits)
  return signText(shownSign(value, shown)) + money(Math.abs(value), shown)
}

function lookSigns(text, retro) {
  return retro ? String(text).replace("+", "▲").replace(MINUS, "▼") : text
}

function changeText(chg, mode, digits) {
  if (chg.pct === null) return "—"
  if (mode === "abs") return signedMoney(chg.abs, digits)
  return pct(chg.pct)
}

function changeCaption(mode) {
  return mode === "open" ? "SINCE OPEN" : ""
}

function changeTone(chg, mode, digits) {
  if (!chg || chg.pct === null) return "flat"
  var sign = mode === "abs" ? shownSign(chg.abs, moveDigits(Math.abs(chg.abs), digits))
    : shownSign(chg.pct, pctDigits(Math.abs(chg.pct)))
  return sign > 0 ? "up" : sign < 0 ? "down" : "flat"
}

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

// A column sized to this holds any value of the same shape, so a refresh
// moves nothing beside it.
function widest(text) {
  return String(text).replace(/\d/g, "8")
}

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
