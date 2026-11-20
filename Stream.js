.pragma library
.import "Format.js" as Format
.import "Overnight.js" as Overnight
.import "Quote.js" as Quote

// Yahoo's price stream (stream.py, `StreamFeed`): what is streamed, how a
// line it prints is read, and how its trades join the prices Yahoo's
// answers hold.

// stream.py runs an hour at most, then another starts; its output is capped
// far above an hour's lines for 100 symbols reported every second.
var STREAM_SECONDS = 3600
var STREAM_CAP = 32 * 1024 * 1024

// Yahoo streams at most 100 symbols a connection.
var MOST_SYMBOLS = 100

// Seconds between reports: every second while a surface is open, as its
// clock ticks; with only the pill on screen, every minute, as the pill's
// clock ticks, so the pill costs no more than a minute's answer did.
var OPEN_PACE = 1
var PILL_PACE = 60

// Yahoo sends a price as a 32-bit float, whose cents are wrong from 2^17 on.
var EXACT_BELOW = 131072

// The plugin's folder as a path, from the URL QML names it by: the shell's
// "qs:///home/…/" for a plugin outside it, "qs:@/qs/…" for one inside the
// shell's own folder (`shellDir`), as a harness loads it, or "file:///…".
function localFolder(url, shellDir) {
  var s = String(url)
  if (s.indexOf("qs:@/qs/") === 0) return shellDir + "/" + decodeURIComponent(s.slice(8))
  return decodeURIComponent(s.replace(/^(qs|file):\/\//, ""))
}

// A listing streams live while it has a trade under a minute old on arrival,
// heard in the last two minutes, room for the pill's minute between
// reports: its answers are then asked once a bar.
var LIVE_AGE = 60

// A currency's streamed price is a quote, not a trade, so a currency keeps
// its answers' price; futures send nothing.
function streamable(quote) {
  return !!quote && quote.instrumentType !== "CURRENCY" && quote.instrumentType !== "FUTURE"
}

// What streams: with a surface open, the stock on show, a preview and the
// rows in sight; with only a pill, the pill's stock; with neither, nothing.
function streamSymbols(open, pill, featured, preview, inSight) {
  var wanted = open ? [featured, preview].concat(inSight) : pill ? [featured] : []
  var out = []
  for (var i = 0; i < wanted.length && out.length < MOST_SYMBOLS; i++) {
    var s = wanted[i]
    if (s && out.indexOf(s) < 0) out.push(s)
  }
  return out
}

// What Stonks writes to stream.py: the seconds between reports, then the
// symbols.
function wantedLine(pace, symbols) {
  return pace + " " + symbols.join(",")
}

// A line stream.py printed, heard at the wall second `heard`: a trade, as
// { symbol, tick }, with the same trade as a night's bar (`night`) for
// `withNightTicks`; or { end } for why it ends; or null.
function parseLine(line, heard) {
  var parts = String(line).split(" ")
  if (parts[0] === "!") return { end: parts[1] || "" }
  if (parts.length !== 4 || !/^[A-Z0-9.^=-]{1,32}$/.test(parts[0])) return null
  var t = Number(parts[1])
  var p = Number(parts[2])
  if (!Format.isFiniteNumber(t) || t <= 0 || t % 1 !== 0 || !Format.isFiniteNumber(p) || p <= 0) return null
  return { symbol: parts[0], tick: { t: t, p: p, heard: heard, night: { t: t, p: p, s: "overnight" } } }
}

// The listings streaming live at `now` (`LIVE_AGE`): those whose trades
// show, a trade in hours their quote holds (`showable`).
function liveSymbols(ticks, now, quotes) {
  var out = {}
  for (var s in ticks) {
    var tick = ticks[s]
    if (now - tick.heard <= 2 * LIVE_AGE && tick.heard - tick.t <= LIVE_AGE && showable(quotes[s], tick)) out[s] = true
  }
  return out
}

// Whether a streamed trade can be a quote's price, newer or not: under
// `EXACT_BELOW`, whose cents a 32-bit float can't hold past; a quote whose
// trades show (`streamable`), traded at least once; and in hours the quote
// holds: its day, the coming day's pre-market it holds (`Quote.tailStart`),
// or for a coin's rolling day any time after it starts. A night's trade is
// `withNightTicks`'.
function showable(quote, tick) {
  if (!streamable(quote) || !tick || !(tick.p < EXACT_BELOW) || quote.untraded) return false
  if (quote.rolling) return tick.t >= quote.session.regular.start
  return (tick.t >= Quote.dayStart(quote) && tick.t < Quote.dayEnd(quote)) || inTail(quote, tick.t)
}

function inTail(quote, t) {
  var pre = quote.next ? quote.next.pre : null
  return !!pre && t >= pre.start && t < pre.end
}

// A quote with a showable streamed trade newer than all it holds: the trade
// is its newest point, in place of the moment Yahoo's answer stamped at its
// own second, a pre-market's for the coming day it holds, and in the
// regular session its price too. A coin's day moves on with it
// (`rolledQuote`). Any other trade leaves the quote as it is.
function tickedQuote(quote, tick) {
  if (!showable(quote, tick)) return quote
  var pts = quote.points
  var last = pts.length ? pts[pts.length - 1] : null
  if ((last && tick.t <= last.t) || (Format.isFiniteNumber(quote.marketTime) && tick.t <= quote.marketTime)) return quote
  var kept = last && last.t % Quote.BAR !== 0 ? pts.slice(0, -1) : pts
  if (quote.rolling) return rolledQuote(quote, kept, tick)
  var tail = inTail(quote, tick.t)
  var reg = quote.session.regular
  var regular = !tail && !!reg && tick.t >= reg.start && tick.t < reg.end
  return Object.assign({}, quote, regular ? { price: tick.p, marketTime: tick.t } : {},
    { points: kept.concat([tail ? { t: tick.t, p: tick.p, s: "pre" } : { t: tick.t, p: tick.p }]) })
}

// A coin's day is the 24 hours to its newest trade (`Quote.coinDay`), so a
// newer trade moves it on: from the last price 24 hours before it, which
// the move counts from, to the trade, its price. Its high and low stay
// while they still fall inside, the trade's price taking either it passes.
function rolledQuote(quote, kept, tick) {
  var pts = kept.concat([{ t: tick.t, p: tick.p }])
  var first = 0
  while (first + 1 < pts.length && pts[first + 1].t <= tick.t - 86400) first++
  var day = pts.slice(first)
  var start = day[0].t
  var high = quote.dayHigh !== null && quote.dayHighAt >= start ? quote.dayHigh : null
  var low = quote.dayLow !== null && quote.dayLowAt >= start ? quote.dayLow : null
  var higher = high !== null && tick.p > high
  var lower = low !== null && tick.p < low
  return Object.assign({}, quote, {
    points: day, price: tick.p, marketTime: tick.t, prevClose: day[0].p, dayOpen: day[0].p, figuresDay: start,
    dayHigh: higher ? tick.p : high, dayHighAt: higher ? tick.t : high === null ? null : quote.dayHighAt,
    dayLow: lower ? tick.p : low, dayLowAt: lower ? tick.t : low === null ? null : quote.dayLowAt,
    session: { pre: null, regular: { start: start, end: tick.t }, post: null }
  })
}

// Yahoo's answers (`quotes`) with each listing's newest streamed trade
// (`tickedQuote`). `had` is the last call's { quotes, made }: a listing
// whose answer and trade didn't change keeps its quote, and the whole keeps
// its object while none does.
function tickedQuotes(quotes, ticks, had) {
  var made = {}
  var out = quotes
  for (var s in ticks) {
    var was = had.made[s]
    var ticked = was && was.quote === quotes[s] && was.tick === ticks[s] ? was.out : tickedQuote(quotes[s], ticks[s])
    made[s] = { quote: quotes[s], tick: ticks[s], out: ticked }
    if (ticked === quotes[s]) continue
    if (out === quotes) out = Object.assign({}, quotes)
    out[s] = ticked
  }
  return { quotes: out !== quotes && sameMap(out, had.quotes) ? had.quotes : out, made: made }
}

function sameMap(a, b) {
  if (!b) return false
  var keys = Object.keys(a)
  if (keys.length !== Object.keys(b).length) return false
  for (var i = 0; i < keys.length; i++) if (a[keys[i]] !== b[keys[i]]) return false
  return true
}

// Robinhood's quotes (`entries`, `LastTradeFeed`'s) with each streamed trade
// in an open night (`cal`'s, `Overnight.nightAt`), under `EXACT_BELOW`,
// newer than a listing's, as the night's last trade: the newer of the two
// is shown (`Overnight.joinedTrade`). Its `at` is the second it was heard.
// The same object where none is newer.
function withNightTicks(entries, ticks, cal) {
  var out = entries
  for (var s in ticks) {
    var entry = entries[s]
    var tick = ticks[s]
    var night = cal ? Overnight.nightAt(cal, tick.t) : null
    if (!night || !night.open || !(tick.p < EXACT_BELOW) || (entry && entry.trade && entry.trade.t >= tick.t)) continue
    if (out === entries) out = Object.assign({}, entries)
    out[s] = { status: entry ? entry.status : "ok", trade: tick.night, at: tick.heard }
  }
  return out
}
