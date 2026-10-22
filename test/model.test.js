import { test, expect } from "bun:test"
import { existsSync, readdirSync, readFileSync } from "node:fs"
import { join } from "node:path"
import { load } from "./load.js"

// The pure rules: tests that read no saved answer, so they run on any
// clone. Those that read Yahoo's and Robinhood's saved answers are in
// saved.test.js.
const root = join(import.meta.dir, "..")
// The reader is in New York: an exchange's time is named
// with its zone only where that clock differs from the reader's.
process.env.TZ = "America/New_York"
// Every rule file's names, under one name: each is defined once.
const M = Object.assign({}, ...["Format", "Fetch", "Quote", "Market", "Overnight", "History", "Fundamentals", "Figures",
  "Chart", "Tones", "Settings", "KeySheet", "Search", "Cells", "Share"].map(name => load(name + ".js")))

const calendars = JSON.parse(readFileSync(join(root, "calendars.json"), "utf8"))
const US = calendars.calendars.US
const JPX = calendars.calendars.JPX
const DAY = 24 * 3600
const keptBars = bars => M.filterStrayCloses(bars).bars
const at = (date, clock) => M.epochAt(US, date, clock)
// A listing's cadence, by its calendar's reading, as askDue reads it.
const quoteCadence = (q, now, interval, hero) => M.quoteCadence(q, now, interval, hero, M.calendarNow(M.calendarFor(calendars, q), now))

test("a stray run is the one the series carries on past", () => {
  // The bar after opens back at the level, not from the stray close.
  const stray = [
    { t: 0, o: 100, c: 100 }, { t: 300, o: 100, c: 90 }, { t: 600, o: 100, c: 101 }
  ]
  expect(keptBars(stray).map(bar => bar.c)).toEqual([100, 101])
  // Two in a row, MSFT's shape: the second opens from the first, so no single
  // bar breaks continuity — only the bar after the pair does.
  const pair = [
    { t: 0, o: 100, c: 100 }, { t: 300, o: 100, c: 115 }, { t: 600, o: 114, c: 110 },
    { t: 900, o: 100, c: 100.1 }
  ]
  expect(keptBars(pair).map(bar => bar.c)).toEqual([100, 100.1])
  // A real move: the next bar opens from where this one closed.
  const real = [
    { t: 0, o: 100, c: 100 }, { t: 300, o: 100, c: 90 }, { t: 600, o: 90, c: 100 }
  ]
  expect(keptBars(real)).toEqual(real)
  // A real move that stays away is never a run at all.
  const stayed = [
    { t: 0, o: 100, c: 100 }, { t: 300, o: 100, c: 104 }, { t: 600, o: 104, c: 104.2 },
    { t: 900, o: 104.2, c: 103.9 }
  ]
  expect(keptBars(stayed)).toEqual(stayed)
  // Small enough that price shape alone could not tell it from trading.
  const small = [
    { t: 0, o: 100, c: 100 }, { t: 300, o: 100, c: 99.2 }, { t: 600, o: 99.2, c: 100 }
  ]
  expect(keptBars(small)).toEqual(small)
})

test("stray filtering never judges the newest bar or an uneven gap", () => {
  const newest = [{ t: 0, o: 100, c: 100 }, { t: 300, o: 100, c: 100 }, { t: 600, o: 100, c: 90 }]
  // The last hourly bar of a day: the next bar is tomorrow's open.
  const overnight = [{ t: 0, o: 100, c: 100 }, { t: 300, o: 100, c: 90 }, { t: 900, o: 100, c: 101 }]
  const noOpens = [{ t: 0, c: 100 }, { t: 300, c: 90 }, { t: 600, c: 100 }]
  // A run longer than Yahoo has ever sent is a real move, not corruption.
  const long = [
    { t: 0, o: 100, c: 100 }, { t: 300, o: 100, c: 90 }, { t: 600, o: 90, c: 91 },
    { t: 900, o: 91, c: 90 }, { t: 1200, o: 90, c: 91 }, { t: 1500, o: 100, c: 100 }
  ]
  expect(keptBars(newest)).toEqual(newest)
  expect(keptBars(overnight)).toEqual(overnight)
  expect(keptBars(noOpens)).toEqual(noOpens)
  expect(keptBars(long)).toEqual(long)
  // An hourly history across a weekend: every bar opens at 100, Friday's
  // last and Monday's first close at 98. A history has no sessions to say a
  // gap lies inside one, so none is bridged. Found in review.
  const weekend = [
    { t: 0, o: 100, c: 100 }, { t: 3600, o: 100, c: 98 }, { t: 3600 + 66 * 3600, o: 100, c: 98 },
    { t: 3600 + 67 * 3600, o: 100, c: 100 }
  ]
  expect(keptBars(weekend)).toEqual(weekend)
  expect(keptBars([])).toEqual([])
})

test("an answer is new when any bar moves, mid-day ones too, and the same when nothing does", () => {
  const quote = points => ({ symbol: "NEST", price: 101, marketTime: 900, points })
  const day = [{ t: 0, p: 99 }, { t: 300, p: 100 }, { t: 600, p: 102 }, { t: 900, p: 101 }, { t: 1200, p: 103 }]
  const moved = (i, p) => quote(day.map((pt, j) => j === i ? { t: pt.t, p: p } : pt))
  expect(M.sameQuote(quote(day), quote(day.map(pt => Object.assign({}, pt))))).toBe(true)
  // Yahoo revises a middle bar: the ends, the count, and the figures stay.
  expect(M.sameQuote(quote(day), moved(2, 102.5))).toBe(false)
  // Three middle bars shuffle: the plain and weighted sums of the prices
  // both stay.
  expect(M.sameQuote(quote(day), quote([day[0], { t: 300, p: 101 }, { t: 600, p: 100 }, { t: 900, p: 102 }, day[4]]))).toBe(false)
  expect(M.sameQuote(quote(day), Object.assign(quote(day), { price: 101.5 }))).toBe(false)
})

test("yAt interpolates a polyline and is null past the line", () => {
  const pts = [{ x: 0, y: 0 }, { x: 1, y: 1 }]
  expect(M.yAt(pts, 0.5)).toBe(0.5)
  expect(M.yAt(pts, 0)).toBe(0)
  expect(M.yAt(pts, 1)).toBe(1)
  expect(M.yAt(pts, -0.1)).toBeNull()
  expect(M.yAt(pts, 1.1)).toBeNull()
  expect(M.yAt([], 0.5)).toBeNull()
})

test("an extended-hours print extends the day range as far as it reaches", () => {
  const q = {
    prevClose: 100,
    session: { regular: { start: 0, end: 900 } },
    points: [{ t: 0, p: 100 }, { t: 300, p: 110 }, { t: 900, p: 50 }]
  }
  const geometry = M.chartGeometry(q)
  expect(geometry.lo).toBeCloseTo(45.2, 10)
  expect(geometry.hi).toBeCloseTo(114.8, 10)
  expect(geometry.points[2].ext).toBe(true)
  for (const p of geometry.points) {
    expect(p.y).toBeGreaterThan(0)
    expect(p.y).toBeLessThan(1)
  }
})

test("Tokyo's lunch break comes from the calendar; the morning session stays on Yahoo", () => {
  const morning = 1788832800
  const lunch = 1788836400
  const jpx = {
    symbol: "7203.T",
    exchange: "TSE",
    timezoneName: "Asia/Tokyo",
    gmtoffset: 32400,
    crypto: false,
    session: { pre: null, post: null, regular: { start: M.epochAt(JPX, "2026-09-08", "09:00"), end: M.epochAt(JPX, "2026-09-08", "15:30") } },
    points: []
  }
  expect(M.marketStatus(jpx, morning, 0, calendars)).toBe("Market closes in 4h 30m")
  // Tokyo's clock is named for a reader in New York.
  expect(M.marketStatus(jpx, lunch, 0, calendars)).toBe("Lunch break · reopens 12:30 JST · in 30m")
})

test("Toronto and London close early when their exchanges say, and London's 2028 holidays are named", () => {
  // A listing held from the day before, so only the calendar knows when
  // today ends: asked for at the trading interval until the early close,
  // then on the slow clock.
  const held = (symbol, exchange, cal, day, open, close) => ({
    symbol, exchange, crypto: false, gmtoffset: M.offsetForDate(cal, day),
    session: { pre: null, post: null, regular: { start: M.epochAt(cal, day, open), end: M.epochAt(cal, day, close) } },
    points: []
  })
  const TSX = calendars.calendars.TSX
  const LSE = calendars.calendars.LSE
  const shop = held("SHOP.TO", "TSX", TSX, "2026-12-23", "09:30", "16:00")
  const cadence = (quote, cal, day, clock) => quoteCadence(quote, M.epochAt(cal, day, clock), 60, false)
  expect([cadence(shop, TSX, "2026-12-24", "12:00"), cadence(shop, TSX, "2026-12-24", "14:00")]).toEqual([60, 900])
  const shel = held("SHEL.L", "LSE", LSE, "2027-12-23", "08:00", "16:30")
  expect([cadence(shel, LSE, "2027-12-24", "12:00"), cadence(shel, LSE, "2027-12-24", "13:00")]).toEqual([60, 900])
  // In the exchange's own wording, less its "(substitute)", its zone named
  // for a reader in New York.
  const status = (quote, day) => M.marketStatus(quote, M.epochAt(LSE, day, "12:00"), 0, calendars)
  const late = held("SHEL.L", "LSE", LSE, "2027-12-31", "08:00", "12:30")
  expect(status(late, "2028-01-03")).toBe("New Year's Day · opens Tue 08:00 GMT")
  const easter = held("SHEL.L", "LSE", LSE, "2028-04-13", "08:00", "16:30")
  expect(status(easter, "2028-04-14")).toBe("Good Friday · opens Tue 08:00 BST")
})

test("a listing's overnight session is named so, a holiday's evening too, and the night before a holiday trades none", () => {
  const nest = {
    symbol: "NEST", exchange: "NASDAQ", crypto: false, gmtoffset: M.offsetForDate(US, "2026-11-25"),
    session: {
      pre: { start: at("2026-11-25", "04:00"), end: at("2026-11-25", "09:30") },
      regular: { start: at("2026-11-25", "09:30"), end: at("2026-11-25", "16:00") },
      post: { start: at("2026-11-25", "16:00"), end: at("2026-11-25", "20:00") }
    },
    points: []
  }
  const night = (date, allDay) => M.nightTrades(nest, allDay, at(date, "21:00"), calendars)
  // Thanksgiving's evening trades for Friday, for a listing Robinhood trades
  // all day; the evening before it, nothing.
  expect([night("2026-11-26", true), night("2026-11-26", false), night("2026-11-25", true)]).toEqual([true, false, false])
  const thursday = at("2026-11-26", "21:00")
  expect(M.marketStatus(nest, thursday, 0, calendars, true)).toBe("Overnight · opens Fri 09:30")
  expect(M.marketStatus(nest, thursday, 0, calendars, false)).toBe("Thanksgiving Day · opens Fri 09:30")
})

test("formatting", () => {
  expect(M.duration(4200)).toBe("1h 10m")
  expect(M.duration(300)).toBe("5m")
  expect(M.duration(39 * 3600 + 1200)).toBe("1d 15h")
  // A countdown rounds up: its last minute reads 1m, never 0m.
  expect(M.duration(59)).toBe("1m")
  expect(M.duration(1)).toBe("1m")
  expect(M.duration(3570)).toBe("1h")
  expect(M.duration(4141)).toBe("1h 10m")
  expect(M.money(1234.5)).toBe("1,234.50")
  expect(M.money(118204)).toBe("118,204")
  expect(M.money(undefined)).toBe("—")
  expect(M.pct(-1.137)).toBe("\u22121.14%")
  expect(M.pct(1267.16)).toBe("+1,267%")
  expect(M.pct(71789.6)).toBe("+71,790%")
  expect(M.pct(-999.99)).toBe("\u2212999.99%")
  // A side bar's pill stacks the move in lines of four characters at most:
  // one decimal under 10%, none from 10% up, thousands as K%; a move that
  // shows as none has no sign.
  const pctLines = v => M.stackedPct(v).lines.join(" ")
  expect([-1.56, 0.04, 9.94, 9.96, -12.34, 123.4, 999.4, 1234.5, 9960, 54321].map(pctLines))
    .toEqual(["\u22121.6 %", "0.0 %", "+9.9 %", "+10 %", "\u221212 %", "+123 %", "+999 %", "+1.2 K%", "+10 K%", "+54 K%"])
  // It rounds what the rows show, never the float behind it, so the two
  // agree whatever prices made the move: 20 to 21.99 is 9.94999…%, which
  // the rows show as +9.95% and the pill showed as +9.9% while 100 to
  // 109.95 read +10%. Found in review: around 9.95%, 0.05%, and 99.95%.
  const shown = [[20, 21.99], [20, 18.01], [100, 109.95], [100, 90.05], [20, 21.988], [20, 20.01], [20, 19.99],
    [100, 100.05], [100, 99.95], [20, 39.99], [100, 199.95], [20, 0.01], [100, 0.05]]
    .map(([prevClose, price]) => {
      const move = M.change({ prevClose }, price, "pct").pct
      return M.pct(move) + " " + M.stackedPct(move).lines[0]
    })
  expect(shown).toEqual(["+9.95% +10", "\u22129.95% \u221210", "+9.95% +10", "\u22129.95% \u221210", "+9.94% +9.9",
    "+0.05% +0.1", "\u22120.05% \u22120.1", "+0.05% +0.1", "\u22120.05% \u22120.1",
    "+99.95% +100", "+99.95% +100", "\u221299.95% \u2212100", "\u221299.95% \u2212100"])
  // In money, split at its point with its sign kept; a coin's long fraction
  // broken after four characters; from a thousand in its unit, a figure that
  // rounds to 1,000 of one being one of the next.
  const moneyLines = ([v, digits]) => M.stackedMoney(v, digits).lines.join(" ")
  expect([[-3.84, 2], [0.004, 2], [-0.67, 2], [999.994, 2], [999.996, 2], [8940, 2], [-12345, 0], [999600, 0], [-0.000000123, 9]]
    .map(moneyLines))
    .toEqual(["\u22123 .84", "0 .00", "\u22120 .67", "+999 .99", "+1.0 K", "+8.9 K", "\u221212 K", "+1.0 M", "\u22120 .000 0001 23"])
  expect([M.stackedMoney(0.004, 2).sign, M.stackedMoney(-0.67, 2).sign, M.stackedPct(0.04).sign]).toEqual([0, -1, 0])
  // A symbol: an index without its ^, a longer one split at its dot or
  // dash, and what is still longer broken after its fourth character.
  expect(["AAPL", "^GSPC", "^DJI", "SHEL.L", "BTC-USD", "SHIB-USD", "BRK-B", "GOOGL", "RELIANCE.NS", "^STOXX50E"]
    .map(s => M.stackedSymbol(s).join(" ")))
    .toEqual(["AAPL", "GSPC", "DJI", "SHEL .L", "BTC -USD", "SHIB -USD", "BRK -B", "GOOG L", "RELI ANCE .NS", "STOX X50E"])
  expect(M.changeText({ abs: 0.91, pct: 0.52 }, "abs")).toBe("+0.91")
  expect(M.changeText({ abs: -1234.5, pct: -2 }, "abs")).toBe("\u22121,234.50")
  expect(M.nextChangeMode("pct")).toBe("abs")
  expect(M.nextChangeMode("open")).toBe("pct")
  expect(M.compactNumber(52432411)).toBe("52.4M")
  expect(M.compactNumber(1234)).toBe("1K")
  expect(M.compactNumber(2.5e9)).toBe("2.5B")
  // A figure that rounds up to 1,000 of its unit is one of the next, and
  // trillions take fewer decimals as they grow, so no count draws wider
  // than 999.9M.
  expect([999499, 999500, 999.9e6, 999.96e6, 999.9e9, 999.96e9, 4.9e12, 33.82e12, 99.996e12, 400.11e12, 999.96e12, 12345.6e12]
    .map(M.compactNumber))
    .toEqual(["999K", "1.0M", "999.9M", "1.0B", "999.9B", "1T", "4.9T", "33.82T", "100T", "400.1T", "1000T", "12346T"])
})

test("arrowAngle saturates at five percent", () => {
  expect(M.arrowAngle(0)).toBe(0)
  expect(M.arrowAngle(2.5)).toBe(22.5)
  expect(M.arrowAngle(9)).toBe(45)
  expect(M.arrowAngle(-9)).toBe(-45)
})

test("each look has one sign language", () => {
  expect(M.lookSigns("+2.55%", false)).toBe("+2.55%")
  expect(M.lookSigns("\u22120.59%", false)).toBe("\u22120.59%")
  expect(M.lookSigns("+2.55%", true)).toBe("▲2.55%")
  expect(M.lookSigns("\u22120.59%", true)).toBe("▼0.59%")
  expect(M.lookSigns("—", true)).toBe("—")
})

test("a run's output splits into its answers, each said by what came back", () => {
  const trailer = (i, status, exit, retry = "") => `\n@@stonks ${i} ${status} ${exit} ${retry}\n`
  const text = '{"chart":1}' + trailer(0, 200, 0)
    + '{"e":"Not Found"}' + trailer(1, 404, 0)
    + "Too Many Requests" + trailer(2, 429, 0, "30")
    + trailer(3, "000", 6)
    + '{"x":"aaa' + trailer(4, 200, 63)
    + "<html>" + trailer(5, 502, 0)
    + '{"chart":2}' + trailer(7, 200, 0)
  const got = M.answers(text).map(a => [a.index, a.kind, a.body, a.retryAfter])
  expect(got).toEqual([
    [0, "ok", '{"chart":1}', 0],
    [1, "missing", '{"e":"Not Found"}', 0],
    [2, "refused", "Too Many Requests", 30],
    [3, "none", "", 0],
    [4, "bad", '{"x":"aaa', 0],
    [5, "bad", "<html>", 0],
    // The run never reached 6: it has no answer.
    [7, "ok", '{"chart":2}', 0]
  ])
  expect(M.answerKind(503, 0)).toBe("refused")
  expect(M.soleBody('{"a":1}' + trailer(0, 200, 0))).toBe('{"a":1}')
  expect(M.soleBody("Too Many" + trailer(0, 429, 0))).toBe("")
  // A run stopped mid-answer: the cut answer has no trailer, so none.
  expect(M.answers('{"a":1}' + trailer(0, 200, 0) + '{"b":').length).toBe(1)
})

test("a spark day keeps the last chart's verdict, and a jump past it waits for a chart", () => {
  const t0 = 1791386400
  // A day of bars at 100 with a stray at the sixth: it closes at 103 and
  // the next bar opens back at 100.
  const closes = [100, 100.1, 100, 100.1, 100, 103, 100.1, 100, 100.1, 100, 100.1, 100]
  const answer = (cs, withOpens) => {
    const ts = cs.map((c, i) => t0 + i * 300)
    const quote = { close: cs }
    if (withOpens) quote.open = cs.map((c, i) => i === 6 ? 100 : i > 0 ? cs[i - 1] : c)
    return { meta: { symbol: "AAA", instrumentType: "EQUITY", exchangeName: "NMS", priceHint: 2,
      regularMarketPrice: cs[cs.length - 1], regularMarketTime: ts[ts.length - 1], chartPreviousClose: 100 },
      timestamp: ts, indicators: { quote: [quote] } }
  }
  const chart = M.parseChart({ chart: { result: [answer(closes, true)] } }, [])
  expect(chart.droppedTimes).toEqual([t0 + 5 * 300])
  // The same day from spark, no opens: the chart's stray stays out, and
  // with no new bar since, nothing waits.
  const same = M.sparkQuote(answer(closes, false), chart.verdict, [])
  expect([same.unjudged, same.quote.droppedTimes, same.quote.points.length]).toEqual([false, [t0 + 5 * 300], 11])
  // Never judged: the jump waits for a chart.
  expect(M.sparkQuote(answer(closes, false), null, []).unjudged).toBe(true)
  // Five quiet bars on, the old jump is settled; a new one is not.
  const later = closes.concat([100.1, 100, 100.1, 100, 100.1])
  const settled = M.parseChart({ chart: { result: [answer(later, true)] } }, []).verdict
  expect(M.sparkQuote(answer(later.concat([100, 100.1]), false), settled, []).unjudged).toBe(false)
  expect(M.sparkQuote(answer(later.concat([104, 100.1]), false), settled, []).unjudged).toBe(true)
  // The newest bar is never judged, so a jump there waits for nothing.
  expect(M.sparkQuote(answer(later.concat([104]), false), settled, []).unjudged).toBe(false)
  // A whole bar Yahoo changes waits for a chart, new bar or not: an old bar
  // turned into a spike, the stray it dropped corrected back to the level,
  // a smaller move than a level, and a bar of the last few, not yet
  // settled.
  const revised = (at, price) => later.map((c, i) => i === at ? price : c)
  expect(M.sparkQuote(answer(revised(3, 103), false), settled, []).unjudged).toBe(true)
  expect(M.sparkQuote(answer(revised(5, 100), false), settled, []).unjudged).toBe(true)
  expect(M.sparkQuote(answer(revised(4, 100.3), false), settled, []).unjudged).toBe(true)
  expect(M.sparkQuote(answer(revised(14, 100.4), false), settled, []).unjudged).toBe(true)
  // Spark's own rounding of a close is no change.
  expect(M.sparkQuote(answer(revised(3, 100.1004), false), settled, []).unjudged).toBe(false)
  // A bar the chart had none for, filled in since, waits for a chart too.
  const gap = answer(later, true)
  gap.indicators.quote[0].close = later.map((c, i) => i === 9 ? null : c)
  const holed = M.parseChart({ chart: { result: [gap] } }, []).verdict
  expect(M.sparkQuote(answer(later, false), holed, []).unjudged).toBe(true)
  // Yahoo leaves a symbol it doesn't know out of a spark answer.
  const days = M.sparkResults({ spark: { result: [{ symbol: "AAA", response: [answer(closes, false)] }] } })
  expect(Object.keys(days)).toEqual(["AAA"])
})

test("a spark day takes its open from the chart of the same session, and waits for a chart once its session opens", () => {
  const day = (start, cs, withOpens) => {
    const ts = cs.map((c, i) => start + i * 300)
    const quote = { close: cs }
    if (withOpens) quote.open = cs.map(c => c - 1)
    return { meta: { symbol: "AAA", instrumentType: "EQUITY", exchangeName: "NMS", priceHint: 2,
      regularMarketPrice: cs[cs.length - 1], regularMarketTime: ts[ts.length - 1], chartPreviousClose: 90,
      regularMarketDayHigh: 200, regularMarketDayLow: 50,
      currentTradingPeriod: { regular: { start: start, end: start + 23400 } } },
      timestamp: ts, indicators: { quote: [quote] } }
  }
  const monday = 1791386400
  const chart = M.parseChart({ chart: { result: [day(monday, [100, 100.1, 100.2], true)] } }, [])
  // The chart's open is its first regular bar's, and the change since the
  // open is measured from it, not from that bar's close.
  expect(chart.dayOpen).toBe(99)
  expect(M.change(chart, 110, "open").abs).toBe(11)
  // Spark, no opens: the same session's day keeps the chart's open.
  const same = M.sparkQuote(day(monday, [100, 100.1, 100.2, 100.1], false), chart.verdict, [])
  expect([same.unjudged, same.quote.dayOpen]).toEqual([false, 99])
  // The next session has opened: no open is known, so none is shown, and the
  // day waits for a chart.
  const tuesday = M.sparkQuote(day(monday + 86400, [104, 105], false), chart.verdict, [])
  expect([tuesday.unjudged, tuesday.quote.dayOpen, M.change(tuesday.quote, 105, "open").pct]).toEqual([true, null, null])
})

test("a screenshot's file name carries only its symbol's letters, digits, dots, and dashes, so no symbol names another folder", () => {
  expect(M.fileSymbol("AAPL")).toBe("aapl")
  expect(M.fileSymbol("^GSPC")).toBe("gspc")
  expect(M.fileSymbol("BRK-B")).toBe("brk-b")
  expect(M.fileSymbol("7203.T")).toBe("7203.t")
  // A symbol a hostile answer could send: no slash survives, so "..", left
  // between "stonks-" and the date, is no step out of the folder.
  for (const symbol of ["../../.ssh/id_rsa", "a/../../b", "/etc/passwd", "..", "$(rm -rf ~)", "x\ny", "AAPL;ls *"]) {
    const name = "stonks-" + M.fileSymbol(symbol) + "-2026-10-21_15-11-03.png"
    expect([symbol, /^[a-z0-9.-]+$/.test(M.fileSymbol(symbol)), name.includes("/")]).toEqual([symbol, true, false])
  }
  expect(M.fileSymbol("../../.ssh/id_rsa")).toBe(".....sshidrsa")
  // Nothing left, and no symbol runs long.
  expect(M.fileSymbol("^/")).toBe("chart")
  expect(M.fileSymbol("A".repeat(500)).length).toBe(32)
})

test("blockCells lays digits on a grid with a blank column between", () => {
  const grid = text => {
    const { columns, cells } = M.blockCells(text)
    const rows = Array.from({ length: 6 }, () => Array(columns).fill(" "))
    for (const cell of cells) rows[cell.y][cell.x] = cell.lit ? "#" : "."
    return rows.map(row => row.join(""))
  }
  expect(grid("10")).toEqual([".#. ###", "##. #.#", ".#. #.#", ".#. #.#", "### ###", "       "])
  expect(grid("1.5")).toEqual([".#.   ###", "##.   #..", ".#.   ###", ".#.   ..#", "### # ###", "         "])
  // The comma hangs a cell below the baseline, which the point never does.
  expect(grid("1,0")).toEqual([".#.   ###", "##.   #.#", ".#.   #.#", ".#.   #.#", "### # ###", "    #    "])
  expect(M.blockCells("1,015.80").columns).toBe(27)
  // The price on its way draws as three dots, not as nothing at all.
  expect(M.blockCells("…").cells.filter(cell => cell.lit).length).toBe(3)
  expect(M.blockCells("…").columns).toBe(5)
  // The retro hero draws the dash rather than nothing.
  expect(M.blockCells("—").cells.filter(cell => cell.lit)).toEqual([
    { x: 0, y: 2, lit: true }, { x: 1, y: 2, lit: true }, { x: 2, y: 2, lit: true }
  ])
})

test("sprites fill the 20 by 14 grid, and the bull is not the bear", () => {
  for (const sprite of [M.BULL_SPRITE, M.BEAR_SPRITE]) {
    expect(sprite.length).toBe(14)
    for (const row of sprite) expect(row.length).toBe(20)
  }
  expect(M.spriteFor(true)).not.toEqual(M.spriteFor(false))
})

function historyBody(overrides) {
  const meta = { symbol: "AAPL", currency: "USD", gmtoffset: -14400, chartPreviousClose: 200, firstTradeDate: 345459600, ...(overrides.meta || {}) }
  const quote = {
    open: [1, 2, 3],
    high: [1.1, 2.1, 3.1],
    low: [0.9, 1.9, 2.9],
    close: [1, 2, 3],
    volume: [10, 20, 30],
    ...(overrides.quote || {})
  }
  return {
    chart: {
      result: [{
        meta,
        timestamp: overrides.timestamp || [100, 200, 300],
        indicators: { quote: [quote] }
      }]
    }
  }
}

test("parseHistory filters intraday prints but leaves daily reversals untouched", () => {
  const common = {
    timestamp: [100, 200, 300],
    quote: { open: [100, 100, 100], close: [100, 96, 100], high: [101, 97, 101], low: [95, 95, 99], volume: [10, 10, 10] }
  }
  const intraday = M.parseHistory(historyBody({ ...common, meta: { dataGranularity: "15m" } }), "1W")
  const daily = M.parseHistory(historyBody({ ...common, meta: { dataGranularity: "1d" } }), "1M")
  expect(intraday.bars.map(bar => bar.c)).toEqual([100, 100])
  expect(daily.bars.map(bar => bar.c)).toEqual([100, 96, 100])
})

test("parseHistory drops null closes, and without a previous close the first close is the baseline", () => {
  const hist = M.parseHistory(historyBody({
    meta: { chartPreviousClose: "nope" },
    quote: { close: [1, null, 3] }
  }), "1Y")
  expect(hist.bars.map(b => b.t)).toEqual([100, 300])
  expect(hist.bars.map(b => b.c)).toEqual([1, 3])
  expect(hist.baseline).toBe(1)
})

test("parseHistory drops a duplicate of the last bar", () => {
  const hist = M.parseHistory(historyBody({
    timestamp: [100, 200, 200],
    quote: {
      open: [1, 2, 2],
      high: [1.1, 2.1, 2.2],
      low: [0.9, 1.9, 1.8],
      close: [1, 2, 2.05],
      volume: [10, 20, 21]
    }
  }), "1Y")
  expect(hist.bars).toEqual([
    { t: 100, o: 1, h: 1.1, l: 0.9, c: 1 },
    { t: 200, o: 2, h: 2.2, l: 1.8, c: 2.05 }
  ])
})

test("coverage is short only when the response begins within one interval of listing", () => {
  const base = { interval: "1d", baseline: 10, firstTradeDate: 100, bars: [{ t: 100, h: 11, l: 9, c: 10 }] }
  expect(M.periodStats(base).coverage.short).toBe(true)
  expect(M.periodStats({ ...base, bars: [{ ...base.bars[0], t: 100 + DAY }] }).coverage.short).toBe(true)
  expect(M.periodStats({ ...base, bars: [{ ...base.bars[0], t: 101 + DAY }] }).coverage.short).toBe(false)
  expect(M.periodStats({ ...base, interval: "1wk", bars: [{ ...base.bars[0], t: 100 - 3 * DAY }] }).coverage.short).toBe(true)
  expect(M.periodStats({ ...base, interval: "1wk", bars: [{ ...base.bars[0], t: 100 - 8 * DAY }] }).coverage.short).toBe(false)
  expect(M.periodStats({ ...base, firstTradeDate: null }).coverage.short).toBe(false)
})

test("a response with no bars draws nothing and claims nothing", () => {
  const empty = M.parseHistory({ chart: { result: [{ meta: { symbol: "NEW", chartPreviousClose: 10 }, indicators: { quote: [{}] } }] } }, "1Y")
  expect(M.periodStats(empty)).toEqual({
    last: null,
    change: { abs: null, pct: null, up: true },
    high: null,
    low: null,
    belowHigh: null,
    coverage: { from: null, to: null, bars: 0, short: false }
  })
  expect(M.historyGeometry(empty)).toEqual({
    points: [], baselineY: null, ticks: [], lo: null, hi: null, start: null, end: null, day: false
  })
  expect(M.historyBarAt(empty, 0.5)).toBeNull()
  expect(M.historyFraction(empty, 1)).toBe(-1)
  expect(M.historyBarAt({ bars: [{ t: 1, c: 2 }] }, NaN)).toBeNull()
  expect(M.historyFraction({ bars: [{ t: 1, c: 2 }] }, 1)).toBe(0)
})

test("the view's chart can be drawn once its data is in, or its first fetch has failed", () => {
  const quote = { symbol: "A" }
  const history = { bars: [] }
  const ok = { A: { status: "ok" } }
  // The day: its quote, or its first fetch failed; nothing while it is out.
  expect(M.viewChart("A", "1D", { A: quote }, {}, {})).toEqual({ symbol: "A", range: "1D", quote, day: quote, latest: null, history: null, failed: false, allDay: false })
  expect(M.viewChart("A", "1D", {}, { A: { status: "loading" } }, {})).toBeNull()
  expect(M.viewChart("A", "1D", {}, { A: { status: "failed" } }, {})).toMatchObject({ quote: null, failed: false })
  // A failed first quote is the answer on a range too: no headline from the
  // history's last bar.
  expect(M.viewChart("A", "1M", {}, { A: { status: "failed" } }, { "A|1M": { status: "ok", history } }))
    .toMatchObject({ quote: null, history: null, failed: false })
  // A range needs its history and the symbol's quote: the headline is never
  // the last bar. Nothing while the history's first answer is out.
  expect(M.viewChart("A", "1M", {}, ok, { "A|1M": { status: "ok", history } })).toBeNull()
  expect(M.viewChart("A", "1M", { A: quote }, ok, {})).toBeNull()
  expect(M.viewChart("A", "1M", { A: quote }, ok, { "A|1M": { status: "ok", history } })).toMatchObject({ history, failed: false })
  // History in hand stays drawn after a refetch fails.
  expect(M.viewChart("A", "1M", { A: quote }, ok, { "A|1M": { status: "failed", history } })).toMatchObject({ history, failed: false })
  // A first fetch that failed has the day stand in (through its retry: the
  // answer stays until another lands).
  expect(M.viewChart("A", "1M", { A: quote }, ok, { "A|1M": { status: "failed", history: null } })).toMatchObject({ history: null, failed: true })
})

// Named lists (Phase 4). All is the library, stored as the version-1
// `symbols`; named lists are subsets with their own order.
const library = (extra = {}) => M.fileSettings({
  symbols: ["NEST", "BO", "IRIS", "SPY"], featured: "NEST", order: "pct",
  lists: [
    { name: "My Watchlist", symbols: ["NEST", "BO"], order: "manual" },
    { name: "Growth", symbols: ["BO", "IRIS"], order: "name" }
  ],
  ...extra
})

test("the data file reads as written and repairs hand edits", () => {
  const v1 = { version: 1, symbols: ["NEST", "SILK"], featured: "SILK", order: "pct", changeMode: "pct", style: "retro", refreshIntervalSec: 60 }
  const read = M.fileSettings(v1)
  // A file from before sounds has them on, their default, and the version
  // check too; only a saved false turns either off.
  expect(read).toEqual({ ...v1, reversed: false, lists: [], list: "", range: "1D", hinted: false, sounds: true, updateCheck: true })
  expect([false, "no", 0].map(v => M.fileSettings({ sounds: v }).sounds)).toEqual([false, true, true])
  expect([false, "no", 0].map(v => M.fileSettings({ updateCheck: v }).updateCheck)).toEqual([false, true, true])
  expect(M.listSymbols(read)).toEqual(["NEST", "SILK"])
  expect(M.listOrder(read)).toBe("pct")
  // The version-1 keys keep their meaning, so an older build reads the same All.
  const withLists = library({ list: "Growth" })
  expect(withLists.symbols).toEqual(["NEST", "BO", "IRIS", "SPY"])
  expect(withLists.order).toBe("pct")
  // No file: the default library and cadence.
  expect(M.fileSettings(null).symbols).toEqual(["NVDA", "AAPL", "MSFT", "SPY", "TSLA"])
  expect(M.fileSettings(null).refreshIntervalSec).toBe(60)
  // Symbols are upper-cased, trimmed, and kept once, from a string or a list.
  expect(M.fileSettings({ symbols: "nvda, aapl AAPL" }).symbols).toEqual(["NVDA", "AAPL"])
  expect(M.fileSettings({ symbols: ["spy", " tsla ", "SPY"] }).symbols).toEqual(["SPY", "TSLA"])
  // The cadence stays between 30 seconds and 15 minutes.
  for (const [given, kept] of [[15, 30], [1000, 900], [120, 120], ["nope", 60]])
    expect([given, M.fileSettings({ refreshIntervalSec: given }).refreshIntervalSec]).toEqual([given, kept])
  // A symbol only a named list holds joins All; an unknown current list is
  // All, and a change of case is not unknown.
  const orphan = M.fileSettings({ symbols: ["NEST"], lists: [{ name: "Growth", symbols: ["BO"] }], list: "Gone" })
  expect(orphan.symbols).toEqual(["NEST", "BO"])
  expect(orphan.list).toBe("")
  expect(M.fileSettings({ symbols: ["NEST"], lists: [{ name: "Growth" }], list: "growth" }).list).toBe("Growth")
  // A hand edit's unknown order is manual, manual is never reversed, and
  // list names are trimmed, kept once ignoring case, and never All or empty.
  const edited = M.fileSettings({ symbols: ["BO"], order: "bogus", reversed: true, lists: [
    { name: "  Growth  ", symbols: ["bo", "BO"], reversed: true }, { name: "growth", symbols: ["X"] },
    { name: "All", symbols: [] }, { name: "", symbols: [] }, { name: "Wins", order: "bogus" },
    { name: "Losers", order: "pct", reversed: true }
  ] })
  expect([edited.order, edited.reversed]).toEqual(["manual", false])
  expect(edited.lists).toEqual([
    { name: "Growth", symbols: ["BO"], order: "manual", reversed: false },
    { name: "Wins", symbols: [], order: "manual", reversed: false },
    { name: "Losers", symbols: [], order: "pct", reversed: true }
  ])
})

// lists.qml drives adding, removing, stepping, naming, and ordering through
// the real Service and keys, on a library where no symbol is in two named
// lists and every add is already in All. These are the cases it cannot reach.
test("membership across several lists", () => {
  // A new symbol added on a named list joins All; one added on All joins no list.
  const onGrowth = M.withSymbolAdded(library({ list: "Growth" }), "fslr")
  expect(onGrowth.symbols).toEqual(["NEST", "BO", "IRIS", "SPY", "FSLR"])
  expect(M.listSymbols(onGrowth)).toEqual(["BO", "IRIS", "FSLR"])
  expect(onGrowth.featured).toBe("NEST")
  const onAll = M.withSymbolAdded(library(), "FSLR")
  expect(onAll.symbols).toContain("FSLR")
  expect(onAll.lists.every(list => list.symbols.indexOf("FSLR") < 0)).toBe(true)
  // BO is in both named lists: leaving Growth keeps it in My Watchlist and All;
  // leaving All takes it out of both.
  const offGrowth = M.withMembership(library({ list: "Growth" }), "BO", "Growth", false, ["BO", "IRIS"])
  expect([offGrowth.symbols, offGrowth.lists.map(list => list.symbols)])
    .toEqual([["NEST", "BO", "IRIS", "SPY"], [["NEST", "BO"], ["IRIS"]]])
  const offAll = M.withMembership(library(), "BO", "", false, ["BO", "NEST", "IRIS", "SPY"])
  expect([offAll.symbols, offAll.lists.map(list => list.symbols)])
    .toEqual([["NEST", "IRIS", "SPY"], [["NEST"], ["IRIS"]]])
  // The featured symbol leaving All from the last row shown hands the hero
  // to the row above it; All keeps its last symbol.
  expect(M.withMembership(library(), "NEST", "", false, ["BO", "IRIS", "SPY", "NEST"]).featured).toBe("SPY")
  const one = M.fileSettings({ symbols: ["NEST"] })
  expect(M.withMembership(one, "NEST", "", false, ["NEST"]).symbols).toEqual(["NEST"])
  // Each list keeps its own order and manual arrangement, apart from All's.
  const growth = M.withListOrder(library({ list: "Growth" }), "symbol")
  expect([M.listOrder(growth), growth.order, growth.lists[0].order]).toEqual(["symbol", "pct", "manual"])
  const all = M.withListOrder(library(), "symbol")
  expect([all.order, all.lists[1].order]).toEqual(["symbol", "name"])
  const moved = M.withManualOrder(library({ list: "Growth" }), ["IRIS", "BO"])
  expect([M.listSymbols(moved), M.listOrder(moved), moved.symbols])
    .toEqual([["IRIS", "BO"], "manual", ["NEST", "BO", "IRIS", "SPY"]])
  // A reorder that does not hold the list's symbols is refused.
  expect(M.listSymbols(M.withManualOrder(library({ list: "Growth" }), ["IRIS"]))).toEqual(["BO", "IRIS"])
  // A list's direction is its own, survives a change of its members, and
  // goes with a new order or a hand arrangement.
  const losers = M.withListReversed(library({ list: "Growth" }))
  expect([M.listReversed(losers), losers.reversed, losers.lists[0].reversed]).toEqual([true, false, false])
  expect(M.listReversed(M.withSymbolAdded(losers, "FSLR"))).toBe(true)
  expect(M.listReversed(M.withMembership(losers, "BO", "Growth", false, ["IRIS", "BO"]))).toBe(true)
  expect(M.listReversed(M.withListOrder(losers, "pct"))).toBe(false)
  expect(M.listReversed(M.withManualOrder(losers, ["IRIS", "BO"]))).toBe(false)
  expect(M.listReversed(M.withListReversed(library({ list: "My Watchlist" })))).toBe(false)
})

test("which day the 1D chart shows: the newest print's, or on a closed date the last trading day", () => {
  const date = newest => M.chartDate(US, newest)
  // A weekday's first print after midnight begins its day.
  expect(date(at("2026-10-07", "00:00"))).toBe("2026-10-07")
  // Until then the chart stays on the day before, so it never stands
  // empty: Wednesday 00:05, its newest print Tuesday 23:55.
  expect(date(at("2026-10-06", "23:55"))).toBe("2026-10-06")
  // A weekend or a holiday shows the last trading day, all day, Sunday
  // night's session included (provisional): Saturday on Friday's last
  // print, Sunday 22:25, Thanksgiving's evening, and the night before the
  // half day after it.
  expect(date(at("2026-10-09", "19:55"))).toBe("2026-10-09")
  expect(date(at("2026-10-11", "22:25"))).toBe("2026-10-09")
  expect(date(at("2026-11-26", "20:30"))).toBe("2026-11-25")
  expect(date(at("2026-11-26", "23:55"))).toBe("2026-11-25")
  // Monday's first print after midnight begins Monday.
  expect(date(at("2026-10-12", "00:05"))).toBe("2026-10-12")
})

test("an open surface asks Robinhood again every five minutes of a night, and once after it", () => {
  const due = (asked, now) => M.overnightDue(asked, now, calendars)
  expect(due(0, at("2026-10-02", "13:00"))).toBe(true)
  expect(due(at("2026-10-01", "22:56"), at("2026-10-01", "23:00"))).toBe(false)
  expect(due(at("2026-10-01", "22:55"), at("2026-10-01", "23:00"))).toBe(true)
  // The night's last bars are in ten minutes after 04:00.
  expect(due(at("2026-10-02", "03:58"), at("2026-10-02", "04:05"))).toBe(false)
  expect(due(at("2026-10-02", "03:58"), at("2026-10-02", "04:11"))).toBe(true)
  // Nothing new comes between then and the next night, nor at the weekend.
  expect(due(at("2026-10-02", "04:11"), at("2026-10-02", "19:59"))).toBe(false)
  expect(due(at("2026-10-02", "13:00"), at("2026-10-03", "12:00"))).toBe(false)
  expect(due(at("2026-10-03", "12:00"), at("2026-10-04", "20:05"))).toBe(true)
})

test("each print says its own time across a change of clocks, and the day marks an early close", () => {
  // Summer time ends Sunday 1 November 2026. On Sunday night Yahoo's response
  // is still Friday's, in summer time; the night's print is not.
  const quote = {
    symbol: "X", instrumentType: "EQUITY", exchange: "NASDAQ", gmtoffset: -14400, prevClose: 100, price: 100,
    marketTime: at("2026-10-30", "16:00"),
    session: {
      pre: { start: at("2026-10-30", "04:00"), end: at("2026-10-30", "09:30") },
      regular: { start: at("2026-10-30", "09:30"), end: at("2026-10-30", "16:00") },
      post: { start: at("2026-10-30", "16:00"), end: at("2026-10-30", "20:00") }
    },
    points: [{ t: at("2026-10-30", "19:55"), p: 100 }]
  }
  const sunday = M.dayChart(quote, [{ t: at("2026-11-01", "21:00"), p: 100.5, s: "overnight" }], calendars)
  expect(M.extendedStack(quote, sunday.latest, at("2026-11-01", "21:05"), sunday.day)).toMatchObject({ label: "OVERNIGHT", time: "21:00" })
  // The day after Thanksgiving closes at 13:00, and its tick says so: laid
  // out by print, it stands between the 12:55 print and the 15:00 one, and
  // none stands at 16:00, past the newest print, where the clock runs.
  const early = {
    ...quote, gmtoffset: -18000, marketTime: at("2026-11-27", "13:00"),
    session: {
      pre: { start: at("2026-11-27", "04:00"), end: at("2026-11-27", "09:30") },
      regular: { start: at("2026-11-27", "09:30"), end: at("2026-11-27", "13:00") },
      post: { start: at("2026-11-27", "13:00"), end: at("2026-11-27", "17:00") }
    },
    points: [{ t: at("2026-11-27", "12:55"), p: 101 }, { t: at("2026-11-27", "15:00"), p: 101.5 }]
  }
  const friday = M.dayChart(early, [{ t: at("2026-11-26", "22:00"), p: 100.2, s: "overnight" }], calendars).day
  const geometry = M.chartGeometry(friday)
  const [noon, afternoon] = geometry.points.map(p => p.x)
  expect(geometry.ticks.filter(x => x > noon && x < afternoon)).toHaveLength(1)
  expect(geometry.ticks.filter(x => x > afternoon).map(x => M.timeAtFraction(friday, x))).not.toContain(at("2026-11-27", "16:00"))
})

test("weeks and months either side of 25 October and 1 November keep their dates, from either side's answer, for every reader", () => {
  // Yahoo stamps each at its first day's midnight by that day's offset (a
  // London week in summer time at 23:00 UTC the Sunday before, one in GMT
  // at 00:00), and sends the answer's offset as the day it is sent's.
  const stamp = iso => Date.parse(iso) / 1000
  const cases = [
    ["1wk", [3600, 0], ["2026-10-18T23:00:00Z", "2026-10-26T00:00:00Z"], ["WEEK OF 19 OCT", "WEEK OF 26 OCT"]],
    ["1wk", [-14400, -18000], ["2026-10-26T04:00:00Z", "2026-11-02T05:00:00Z"], ["WEEK OF 26 OCT", "WEEK OF 2 NOV"]],
    ["1mo", [3600, 0], ["2026-09-30T23:00:00Z", "2026-11-01T00:00:00Z"], ["OCT", "NOV"]],
    // Midnight of 1 November is still summer time in New York.
    ["1mo", [-14400, -18000], ["2026-10-01T04:00:00Z", "2026-11-01T04:00:00Z", "2026-12-01T05:00:00Z"], ["OCT", "NOV", "DEC"]]
  ]
  for (const reader of ["America/New_York", "Europe/London", "Asia/Tokyo", "Asia/Kolkata"]) {
    process.env.TZ = reader
    try {
      for (const [interval, offsets, stamps, dates] of cases) {
        for (const gmtoffset of offsets) {
          const history = { range: "5Y", interval, gmtoffset, bars: stamps.map(iso => ({ t: stamp(iso), c: 100 })) }
          expect([reader, gmtoffset, history.bars.map(bar => M.historyScrubText(history, bar).split(" · ")[0])])
            .toEqual([reader, gmtoffset, dates])
        }
      }
    } finally { process.env.TZ = "America/New_York" }
  }
  // The live moment Yahoo appends keeps today's date, even at a whole hour
  // of a coin's day, where no clock changes. Found in review: Saturday 31
  // October's 23:00 UTC read as the week of 1 November.
  const live = stamp("2026-10-31T23:00:00Z")
  const coin = { range: "5Y", interval: "1wk", gmtoffset: 0, liveAt: live,
    bars: [{ t: stamp("2026-10-26T00:00:00Z"), c: 100 }, { t: live, c: 101 }] }
  expect(coin.bars.map(bar => M.historyScrubText(coin, bar).split(" · ")[0])).toEqual(["WEEK OF 26 OCT", "WEEK OF 31 OCT"])
})

test("a session's one bar says nothing until its five minutes are past", () => {
  // An index's opening bar with its close already in, three minutes into
  // the session: it read "Traded only at 09:30" (found in review).
  const bell = at("2026-10-20", "09:30")
  const day = { symbol: "^GSPC", exchange: "S&P", instrumentType: "INDEX", gmtoffset: -14400,
    session: { pre: null, regular: { start: bell, end: at("2026-10-20", "16:00") }, post: null },
    points: [{ t: bell, p: 100 }] }
  expect(M.dayNote(day, bell + 180, calendars)).toBe("")
  expect(M.dayNote(day, bell + 300, calendars)).toBe("Traded only at 09:30")
})

test("a failed answer is asked again five minutes on, whatever the hour", () => {
  const asked = at("2026-10-02", "04:11")
  expect(M.overnightDue(asked, at("2026-10-02", "04:15"), calendars, true)).toBe(false)
  expect(M.overnightDue(asked, at("2026-10-02", "04:16"), calendars, true)).toBe(true)
  expect(M.overnightDue(asked, at("2026-10-02", "08:00"), calendars, false)).toBe(false)
})

test("each side's wash adds the lightness the up colour's does, worked out from the theme", () => {
  const hex = h => ({ r: parseInt(h.slice(1, 3), 16) / 255, g: parseInt(h.slice(3, 5), 16) / 255, b: parseInt(h.slice(5, 7), 16) / 255 })
  // The renders' colours, Kanagawa's (a pale accent, a dark red), and
  // Catppuccin Latte's, a light theme whose wash takes light away.
  const themes = {
    render: { ground: "#101315", up: "#7aa2f7", down: "#a55555", downWash: 0.257 },
    kanagawa: { ground: "#1f1f28", up: "#dcd7ba", down: "#c34043", downWash: 0.377 },
    latte: { ground: "#eff1f5", up: "#1e66f5", down: "#d20f39", downWash: 0.134 }
  }
  for (const [name, t] of Object.entries(themes)) {
    const [ground, up, down] = [hex(t.ground), hex(t.up), hex(t.down)]
    // Up keeps the alpha it is given.
    expect(M.washAlpha(up, up, ground, 0.16, 1)).toBeCloseTo(0.16, 6)
    // Down takes the alpha that adds the same lightness: more for a darker
    // red on a dark ground, less on a light one.
    const a = M.washAlpha(down, up, ground, 0.16, 1)
    expect([name, Math.round(a * 1000) / 1000]).toEqual([name, t.downWash])
    expect(M.addedLightness(down, ground, a)).toBeCloseTo(M.addedLightness(up, ground, 0.16), 6)
  }
  // Never more than half the ink it sits under, so the line and the caps
  // stay the most important thing: Kanagawa's red stems would match the
  // pale accent's at 77% of a cap's full ink, and the extended hours' at 37%
  // of their 45%. Both stop at half.
  const [ground, up, down] = [hex("#1f1f28"), hex("#dcd7ba"), hex("#c34043")]
  expect(M.washAlpha(down, up, ground, 0.35, 1)).toBe(0.5)
  expect(M.washAlpha(down, up, ground, 0.35 * 0.45, 0.45)).toBe(0.225)
  // Below the cap the rule holds: Gruvbox's red stems match at 40%.
  const [gGround, gUp, gDown] = [hex("#282828"), hex("#7daea3"), hex("#ea6962")]
  const stem = M.washAlpha(gDown, gUp, gGround, 0.35, 1)
  expect(Math.round(stem * 1000) / 1000).toBe(0.4)
  expect(M.addedLightness(gDown, gGround, stem)).toBeCloseTo(M.addedLightness(gUp, gGround, 0.35), 6)
  // A colour too close to the ground to add as much is at the cap.
  expect(M.washAlpha(hex("#16181a"), hex("#7aa2f7"), hex("#101315"), 0.16, 1)).toBe(0.5)
})

test("up never reads as down, and each side reads on its ground, in every installed theme", () => {
  // Up and down are the theme's green and red where they are a real pair
  // and the fainter reaches 3:1, else Stonks' own pair for the surface's
  // ground. Read from the themes Omarchy installs, as the shell reads them:
  // `red` (else `color1`) is its urgent, and the bar, the popup's card, and
  // the window all lie on its background.
  const dir = "/usr/share/omarchy/themes"
  const themes = readdirSync(dir).filter(name => existsSync(join(dir, name, "colors.toml")))
  expect(themes.length).toBeGreaterThanOrEqual(22)
  const colour = c => typeof c === "string" ? M.hexColor(c) : c
  const own = []
  for (const name of themes) {
    const toml = readFileSync(join(dir, name, "colors.toml"), "utf8")
    const key = keys => M.hexColor(M.themeColor(toml, keys))
    const [ground, red] = [key(["background", "color0"]), key(["red", "color1"])]
    const { up, down } = M.trend(M.themeColor(toml, ["green", "color2"]), red, ground)
    expect([name, M.paired(M.hexOf(colour(up)), colour(down))]).toEqual([name, true])
    const floor = down === red ? 3 : 4.5
    if (down !== red) own.push(name)
    expect([name, M.contrast(colour(up), ground) >= floor, M.contrast(colour(down), ground) >= floor]).toEqual([name, true, true])
  }
  expect(own.sort()).toEqual(["catppuccin-latte", "hackerman", "lumon", "miasma", "solitude", "vantablack", "white"])
})

test("community themes that one hue, a faint colour, or a tinted light ground would trip", () => {
  // Palettes from Omarchy's community themes, as the shell resolves them:
  // the green, the red (the shell's urgent), and the surface's ground.
  const own = { dark: M.OWN_PAIRS[0], light: M.OWN_PAIRS[1] }
  const cases = [
    // One hue, or a grey, that a gap in a and b took for a pair.
    { name: "CpUnk", link: "https://github.com/stannorbvb-cmd/cpunk", green: "#D1D2D1", red: "#f82a2a", ground: "#040303", want: "dark" },
    { name: "Mars", link: "https://github.com/steve-lohmeyer/omarchy-mars-theme", green: "#7b534e", red: "#e07b5f", ground: "#000000", want: "dark" },
    { name: "Sakura", link: "https://github.com/bjarneo/omarchy-sakura-theme", green: "#f29b9a", red: "#e85f6f", ground: "#0d0509", want: "dark" },
    // Two vivid neighbours, orange and red, are a pair by hue and keep it.
    { name: "Waveform Dark", link: "https://github.com/hipsterusername/omarchy-waveform-dark-theme", green: "#ff6600", red: "#ff3333", ground: "#0a0a0a", want: "theme" },
    // A pair whose fainter colour is under 3:1: a dark red on a dark ground,
    // a mid green on a light one.
    { name: "Naysayer", link: "https://github.com/brianblakely/omarchy-naysayer-theme", green: "#90ee90", red: "#800000", ground: "#072626", want: "dark" },
    { name: "Solarized Light", link: "https://github.com/dfrico/omarchy-solarized-light-theme", green: "#859900", red: "#dc322f", ground: "#fdf6e3", want: "light" },
    // Tinted light grounds, where GitHub's light text colours fell under
    // 4.5:1 (4.04:1 and 3.48:1).
    { name: "Gruvbox Light", link: "https://github.com/Kushal0924/omarchy-gruvbox-light-theme", green: "#98971a", red: "#cc241d", ground: "#f2e5bc", want: "light" },
    { name: "Map Quest", link: "https://github.com/ItsABigIgloo/omarchy-mapquest-theme", green: "#3a443d", red: "#4f351e", ground: "#ecd3a1", want: "light" }
  ]
  for (const c of cases) {
    const [red, ground] = [M.hexColor(c.red), M.hexColor(c.ground)]
    const got = M.trend(c.green, red, ground)
    const want = c.want === "theme" ? { up: c.green, down: red } : own[c.want]
    expect([c.name, got]).toEqual([c.name, want])
    if (c.want !== "theme")
      expect([c.name, M.contrast(M.hexColor(got.up), ground) >= 4.5, M.contrast(M.hexColor(got.down), ground) >= 4.5]).toEqual([c.name, true, true])
  }
  // The floor is each surface's own: Ferrari F1's red bar takes Stonks'
  // pair, where the theme's red is at 1.66:1, while its dark popup keeps the
  // theme's (https://github.com/hueilost/omarchy-theme-ferrari-f1).
  const red = M.hexColor("#ff2800")
  expect(M.trend("#3ddc84", red, M.hexColor("#c40000"))).toEqual(own.dark)
  expect(M.trend("#3ddc84", red, M.hexColor("#0d0d0f"))).toEqual({ up: "#3ddc84", down: red })
  // A light bar under a dark popup takes the other pair: White's on black.
  expect(M.trend("#3a3a3a", M.hexColor("#2a2a2a"), M.hexColor("#000000"))).toEqual(own.dark)
})

// Each parser fed hostile answers, in a child process with a time limit: a
// loop without end in a parser holds the shell's one thread, and with it
// the bar, the launcher, and every other plugin, and the test's own timeout
// can't stop a synchronous one. At each place a parser reads a list, an
// object posing as one with a length of 1e300, and a list one past its
// budget; and bar times no Date can hold. Each must come back at once with
// nothing read from it. An answer goes as text, read with JSON.parse, as
// curl's is. `call` is run on it as `json`; its value comes back as JSON,
// "threw" and the error's name, or "no answer in 10 s".
async function hostile(cases) {
  const rules = ["Format", "Quote", "History", "Fundamentals", "Search", "Overnight"]
  return Promise.all(cases.map(async c => {
    const child = Bun.spawn([process.execPath, "-e", `
      import { load } from ${JSON.stringify(join(import.meta.dir, "load.js"))}
      const M = Object.assign({}, ...${JSON.stringify(rules)}.map(name => load(name + ".js")))
      const json = JSON.parse(await Bun.stdin.text())
      let out
      try { out = ${c.call} } catch (e) { out = "threw " + e.name }
      console.log(JSON.stringify(out))`],
      { stdin: new Blob([JSON.stringify(c.answer)]), stdout: "pipe", stderr: "pipe", timeout: 10000 })
    const [text, error, code] = await Promise.all([new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited])
    return [c.name, child.signalCode ? "no answer in 10 s" : code === 0 ? JSON.parse(text) : "exited " + code + ": " + error.trim()]
  }))
}
const POSING = { length: 1e300 }
// `n` bar times five minutes apart, or `n` of anything else.
const T0 = 1791386400
const times = n => Array.from({ length: n }, (_, i) => T0 + 300 * i)
const period = (start, end) => ({ start, end, gmtoffset: -14400, timezone: "EDT" })
// A day answer whose three bars read, and a range's, its periods one list
// of days; `edit` changes the result, or the answer, before it is sent.
const chartAnswer = (edit, periods) => {
  const answer = { chart: { result: [{
    meta: { symbol: "X", regularMarketPrice: 10, regularMarketTime: T0 + 600, gmtoffset: -14400, tradingPeriods: periods ||
      { pre: [[period(T0 - 3600, T0)]], regular: [[period(T0, T0 + 3600)]], post: [[period(T0 + 3600, T0 + 7200)]] } },
    timestamp: times(3),
    indicators: { quote: [{ open: [10, 10, 10], high: [10, 10, 10], low: [10, 10, 10], close: [10, 10, 10] }] }
  }] } }
  if (edit) edit(answer.chart.result[0], answer)
  return answer
}
const rangeAnswer = edit => chartAnswer(edit, [[period(T0, T0 + 3600)]])
const bars = r => r.indicators.quote[0]

test("a hostile chart or spark answer reads as no answer, at once", async () => {
  const read = "M.parseChart(json, []) && 'read'"
  const spark = "M.sparkResults(json) && 'read'"
  const cases = [
    { name: "a day answer, as sent", call: read, answer: chartAnswer(), want: "read" },
    { name: "bar times posing", call: read, answer: chartAnswer(r => { r.timestamp = POSING }) },
    { name: "closes posing", call: read, answer: chartAnswer(r => { bars(r).close = POSING }) },
    { name: "opens posing", call: read, answer: chartAnswer(r => { bars(r).open = POSING }) },
    { name: "a session's days posing", call: read, answer: chartAnswer(r => { r.meta.tradingPeriods.regular = POSING }) },
    { name: "a day's periods posing", call: read, answer: chartAnswer(r => { r.meta.tradingPeriods.regular = [POSING] }) },
    // A spark day with this threw as it was read, and its feed asked nothing
    // more until Stonks restarted.
    { name: "a day's period null", call: read, answer: chartAnswer(r => { r.meta.tradingPeriods.pre = [[null]] }) },
    { name: "a spark day with a period null", call: "M.sparkQuote(json, null, [])",
      answer: chartAnswer(r => { r.meta.tradingPeriods.pre = [[null]] }).chart.result[0] },
    { name: "bar times over budget", call: read, answer: chartAnswer(r => { r.timestamp = times(M.MOST_BARS + 1) }) },
    { name: "closes over budget", call: read, answer: chartAnswer(r => { bars(r).close = times(M.MOST_BARS + 1).map(() => 10) }) },
    { name: "a session's days over budget", call: read,
      answer: chartAnswer(r => { r.meta.tradingPeriods.pre = times(M.MOST_DAYS + 1).map(() => [period(T0 - 3600, T0)]) }) },
    // A 322-byte answer the review of this fix found: the retro chart filled
    // 222 billion columns from its middle print back to its last.
    { name: "bar times out of order", call: read, answer: chartAnswer(r => { r.timestamp = [T0, -8e12, T0 + 600] }) },
    { name: "a day's periods over budget", call: read,
      answer: chartAnswer(r => { r.meta.tradingPeriods.pre = [times(M.MOST_PERIODS + 1).map(() => period(T0 - 3600, T0))] }) },
    { name: "bar times no Date holds", call: read, answer: chartAnswer(r => { r.timestamp = [0, 1e300, 2e300] }) },
    { name: "a spark day with its bar times posing", call: "M.sparkQuote(json, null, [])",
      answer: chartAnswer(r => { r.timestamp = POSING }).chart.result[0] },
    { name: "a spark answer, as sent", call: spark, answer: { spark: { result: [{ symbol: "X", response: [chartAnswer().chart.result[0]] }] } }, want: "read" },
    { name: "spark listings posing", call: spark, answer: { spark: { result: POSING } } },
    { name: "spark listings over budget", call: spark,
      answer: { spark: { result: times(M.MOST_SPARKS + 1).map(t => ({ symbol: "S" + t, response: [chartAnswer().chart.result[0]] })) } } }
  ]
  expect(await hostile(cases)).toEqual(cases.map(c => [c.name, c.want === undefined ? null : c.want]))
}, 60000)

test("a hostile range answer reads as no answer, at once", async () => {
  const read = "M.parseHistory(json, '1M', []) && 'read'"
  const cases = [
    { name: "a range answer, as sent", call: read, answer: rangeAnswer(), want: "read" },
    { name: "bar times posing", call: read, answer: rangeAnswer(r => { r.timestamp = POSING }) },
    ...["open", "high", "low", "close"].map(list =>
      ({ name: list + "s posing", call: read, answer: rangeAnswer(r => { bars(r)[list] = POSING }) })),
    { name: "a day's periods posing", call: read, answer: rangeAnswer(r => { r.meta.tradingPeriods = [POSING] }) },
    { name: "bar times over budget", call: read, answer: rangeAnswer(r => { r.timestamp = times(M.MOST_BARS + 1) }) },
    { name: "days over budget", call: read,
      answer: rangeAnswer(r => { r.meta.tradingPeriods = times(M.MOST_DAYS + 1).map(() => [period(T0, T0 + 3600)]) }) },
    { name: "bar times no Date holds", call: read, answer: rangeAnswer(r => { r.timestamp = [0, 1e300, 2e300] }) }
  ]
  expect(await hostile(cases)).toEqual(cases.map(c => [c.name, c.want === undefined ? null : c.want]))
}, 60000)

test("a hostile cap and P/E answer leaves the figures it would have fed unknown, at once", async () => {
  const series = (type, value) => ({ meta: { type: [type] }, [type]: [{ asOfDate: "2026-09-30", currencyCode: "USD", reportedValue: { raw: value } }] })
  const timeseries = edit => {
    const answer = { timeseries: { result: [series("trailingMarketCap", 4e12), series("trailingPeRatio", 30), series("trailingDilutedEPS", 7)] } }
    if (edit) edit(answer.timeseries.result)
    return answer
  }
  const read = "M.parseFundamentals(json)"
  const figures = { cap: { value: 4e12, date: "2026-09-30", currency: "USD" }, pe: { value: 30, date: "2026-09-30" } }
  const closes = `M.withSnapshotCloses(${JSON.stringify(figures)}, json)`
  const both = { cap: { ...figures.cap, close: 250 }, pe: { ...figures.pe, close: 250 } }
  const day = Date.UTC(2026, 8, 30) / 1000 + 14 * 3600
  const cases = [
    { name: "an answer, as sent", call: read, answer: timeseries(), want: figures },
    // The marketplace's review of 1.0.2 found this one.
    { name: "the cap's series posing", call: read, answer: timeseries(r => { r[0].trailingMarketCap = POSING }), want: { cap: null, pe: figures.pe } },
    { name: "the EPS series posing", call: read, answer: timeseries(r => { r[2].trailingDilutedEPS = POSING }), want: { cap: figures.cap, pe: null } },
    { name: "the series posing", call: "M.latestSnapshot(json, 'trailingMarketCap')", answer: POSING },
    { name: "the series over budget", call: read, answer: timeseries(r => r.push(...times(M.MOST_SERIES - 2).map(() => series("trailingPeRatio", 30)))) },
    { name: "the cap's snapshots over budget", call: read,
      answer: timeseries(r => { r[0].trailingMarketCap = times(M.MOST_SNAPSHOTS + 1).map(() => r[0].trailingMarketCap[0]) }), want: { cap: null, pe: figures.pe } },
    { name: "the closes, as sent", call: closes, answer: chartAnswer(r => { r.timestamp = [day]; bars(r).close = [250] }), want: both },
    { name: "the closes' times posing", call: closes, answer: chartAnswer(r => { r.timestamp = POSING }) },
    { name: "the closes posing", call: closes, answer: chartAnswer(r => { r.timestamp = [day]; bars(r).close = POSING }) },
    { name: "the closes over budget", call: closes,
      answer: chartAnswer(r => { r.timestamp = times(M.MOST_BARS + 1).map(t => t - T0 - 300 * M.MOST_BARS + day); bars(r).close = r.timestamp.map(() => 250) }) },
    { name: "the closes' times no Date holds", call: closes, answer: chartAnswer(r => { r.timestamp = [1e300]; bars(r).close = [250] }) }
  ]
  expect(await hostile(cases)).toEqual(cases.map(c => [c.name, c.want === undefined ? null : c.want]))
}, 60000)

test("a hostile search or Robinhood answer reads as no answer, at once", async () => {
  const quote = { symbol: "SHOP", quoteType: "EQUITY", exchange: "NMS", longname: "Shopify Inc." }
  const result = historicals => ({ symbol: "NEST", historicals })
  const print = { begins_at: "2026-10-07T00:00:00Z", close_price: "10.00", session: "overnight", interpolated: false }
  const nest = "M.overnightBars(json.results[0], 'NEST').length"
  const cases = [
    { name: "a search, as sent", call: "M.parseSearch(json).results.length", answer: { quotes: [quote] }, want: 1 },
    { name: "search quotes posing", call: "M.parseSearch(json)", answer: { quotes: POSING } },
    { name: "search quotes over budget", call: "M.parseSearch(json) && 'read'", answer: { quotes: times(M.MOST_QUOTES + 1).map(() => quote) } },
    { name: "prints, as sent", call: nest, answer: { results: [result([print])] }, want: 1 },
    { name: "Robinhood's results posing", call: "M.parseOvernight(json, ['NEST'])", answer: { results: POSING } },
    { name: "Robinhood's results over budget", call: "M.overnightResults(json) && 'read'", answer: { results: times(M.MOST_RESULTS + 1).map(() => result([])) } },
    { name: "a listing's prints posing", call: nest, answer: { results: [result(POSING)] }, want: 0 },
    { name: "a listing's prints over budget", call: nest, answer: { results: [result(times(M.MOST_PRINTS + 1).map(() => print))] }, want: 0 },
    { name: "instruments, as sent", call: "M.parseAllDay(json, ['NEST'])", answer: { results: [{ symbol: "NEST", all_day_tradability: "tradable" }] }, want: { NEST: true } },
    { name: "instruments posing", call: "M.parseAllDay(json, ['NEST'])", answer: { results: POSING } },
    { name: "instruments over budget", call: "M.parseAllDay(json, ['NEST'])", answer: { results: times(3).map(() => ({ symbol: "NEST", all_day_tradability: "tradable" })) } }
  ]
  expect(await hostile(cases)).toEqual(cases.map(c => [c.name, c.want === undefined ? null : c.want]))
}, 60000)

test("a fetched name or code past its length reads as not sent", () => {
  const long = n => "N".repeat(n)
  const day = edit => M.parseChart(chartAnswer(r => edit(r.meta)), [])
  // A name past MOST_NAME gives way to the next one Yahoo sent, then the
  // symbol; one at the limit is kept whole.
  expect(day(m => { m.longName = long(M.MOST_NAME + 1); m.shortName = "Short" }).name).toBe("Short")
  expect(day(m => { m.longName = long(M.MOST_NAME) }).name).toBe(long(M.MOST_NAME))
  expect(day(m => { m.longName = long(1e6); m.shortName = long(1e6) }).name).toBe("X")
  // A code past MOST_CODE is no code, and the exchange's full name past
  // MOST_NAME no name: no currency named, no zone, no exchange.
  const codes = day(m => {
    m.currency = m.exchangeTimezoneName = m.timezone = m.exchangeName = m.instrumentType = long(M.MOST_CODE + 1)
    m.fullExchangeName = long(M.MOST_NAME + 1)
  })
  expect([codes.currency, codes.timezoneName, codes.zoneName, codes.exchange, codes.instrumentType]).toEqual(["", "", "", "", ""])
  expect(day(m => { m.symbol = long(1e5) }).symbol).toBe("")
  const range = M.parseHistory(rangeAnswer(r => { r.meta.symbol = r.meta.timezone = long(1e5) }), "1M", [])
  expect([range.symbol, range.zoneName]).toEqual(["", ""])
  // Search leaves out a result with no symbol it can keep, and names a kind
  // it leaves out by its own code when Yahoo's word for it runs on.
  const found = M.parseSearch({ quotes: [
    { symbol: long(1e5), quoteType: "EQUITY", longname: "Lost" },
    { symbol: "SHOP", quoteType: "EQUITY", exchange: long(1e5), longname: long(1e5), shortname: "Shopify" },
    { symbol: "VFIAX", quoteType: "MUTUALFUND", typeDisp: long(1e5) },
    { symbol: "OTHER", quoteType: "WARRANT", typeDisp: long(1e5) }
  ] })
  expect(found).toEqual({ results: [{ symbol: "SHOP", name: "Shopify", exchange: "" }], note: "Stonks doesn’t show mutual funds or warrants" })
  const cap = { meta: { type: ["trailingMarketCap"] }, trailingMarketCap: [{ asOfDate: "2026-09-30", currencyCode: long(1e5), reportedValue: { raw: 4e12 } }] }
  expect(M.parseFundamentals({ timeseries: { result: [cap] } }).cap.currency).toBe("")
})
