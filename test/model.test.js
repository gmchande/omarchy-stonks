import { test, expect, describe } from "bun:test"
import { readFileSync, readdirSync } from "node:fs"
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
  "Chart", "Tones", "Settings", "KeySheet", "Search", "Cells", "Share", "Asks"].map(name => load(name + ".js")))

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
  // gap lies inside one, so none is bridged.
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
  expect(geometry.lo).toBeLessThan(50)
  expect(geometry.hi).toBeGreaterThan(110)
  expect(geometry.points[2].ext).toBe(true)
  for (const p of geometry.points) {
    expect(p.y).toBeGreaterThan(0)
    expect(p.y).toBeLessThan(1)
  }
})

// A day whose post session runs an hour past its last print, five minutes old.
const openDay = (price, prevClose) => {
  const now = 1789669200
  return {
    symbol: "DAY", name: "Day", currency: "USD", exchange: "NASDAQ", timezoneName: "America/New_York",
    gmtoffset: -14400, instrumentType: "EQUITY", crypto: false, price, prevClose, marketTime: now,
    session: {
      pre: { start: now - 25200, end: now - 19800 },
      regular: { start: now - 19800, end: now + 3600 },
      post: { start: now + 3600, end: now + 18000 }
    },
    points: [{ t: now - 19800, p: prevClose ?? price }, { t: now - 300, p: price }]
  }
}

test("the day's axis runs past its last print, and key scrubbing stops at the last print", () => {
  const day = openDay(110, 100)
  const last = day.points.at(-1).t
  expect(M.chartGeometry(day).end).toBeGreaterThan(last)
  expect(M.stepTime(day, last, 50, last)).toBe(last)
})

test("a quiet trading span joins its prints; Tokyo's scheduled lunch alone breaks the line", () => {
  const us = {
    symbol: "THIN", exchange: "NYQ", crypto: false, prevClose: 100,
    session: {regular: {start: at("2026-10-21", "09:30"), end: at("2026-10-21", "16:00")}},
    axis: {start:at("2026-10-21", "00:00"),end:at("2026-10-22", "00:00"),byPrint:true,ticks:[]},
    points: ["00:05", "02:10", "06:45", "09:35"].map((t,i)=>({t:at("2026-10-21",t),p:100+i}))
  }
  const line=M.chartGeometry(us,calendars)
  expect(line.points.map(p=>p.brk)).toEqual([false,false,false,false])
  expect(us.points.map((p,i)=>M.timeAtFraction(us,line.points[i].x))).toEqual(us.points.map(p=>p.t))
  const tokyo={symbol:"7203.T",exchange:"TSE",crypto:false,gmtoffset:32400,prevClose:100,
    session:{regular:{start:M.epochAt(JPX,"2026-10-21","09:00"),end:M.epochAt(JPX,"2026-10-21","15:30")}},
    points:["09:00","11:30","12:30","15:25"].map((t,i)=>({t:M.epochAt(JPX,"2026-10-21",t),p:100+i}))}
  expect(M.chartGeometry(tokyo,calendars).points.map(p=>p.brk)).toEqual([false,false,true,false])
  const one={...us,points:[us.points[0]]}
  expect(M.chartGeometry(one,calendars).points).toHaveLength(1)
  expect(M.timeAtFraction(one,M.chartGeometry(one,calendars).points[0].x)).toBe(us.points[0].t)
})

test("Tokyo's lunch break comes from the calendar; the morning session stays on Yahoo, counting to the break", () => {
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
  // 11:00: the morning ends at the 11:30 break, not at the 15:30 close.
  expect(M.statusForms(jpx, morning, 0, calendars)).toEqual(["Lunch break in 30m", "Lunch break in 30m"])
  expect(M.marketStatus(jpx, M.epochAt(JPX, "2026-09-08", "11:26"), 0, calendars)).toBe("Lunch break in 4m")
  // Tokyo's clock is named for a reader in New York.
  expect(M.marketStatus(jpx, lunch, 0, calendars)).toBe("Lunch break · reopens 12:30 JST · in 30m")
  // Asked every minute through the morning, on the slow clock at lunch.
  expect(quoteCadence(jpx, morning, 60, true)).toBe(60)
  expect(quoteCadence(jpx, lunch, 60, true)).toBe(900)
  expect(M.inRegularSession(jpx, lunch, calendars)).toBe(false)
  // A lunch break without its countdown, then when it reopens.
  expect(M.statusForms(jpx, lunch, 0, calendars))
    .toEqual(["Lunch break · reopens 12:30 JST · in 30m", "Lunch break · reopens 12:30 JST", "Reopens 12:30 JST"])
  // The bell rings at 09:00 and 15:30, not around lunch.
  const tokyo = hm => M.epochAt(JPX, "2026-09-08", hm)
  expect(["09:00", "11:30", "12:30", "15:30"].map(hm => M.bellBetween(jpx, tokyo(hm) - 60, tokyo(hm) + 1, calendars)))
    .toEqual(["open", "", "", "close"])
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

test("a Toronto time in 2027 and 2028 reads by Toronto's clock, and past any calendar's last day by the clock Yahoo sends", () => {
  const TSX = calendars.calendars.TSX
  // SHOP.TO as Yahoo sends it in summer: EDT, the reader's own clock, so
  // no zone is named.
  const shop = { symbol: "SHOP.TO", exchange: "TSX", crypto: false, gmtoffset: -14400, zoneName: "EDT",
    clocks: [], session: { pre: null, post: null, regular: null }, points: [] }
  const july2027 = Date.UTC(2027, 6, 14, 20) / 1000
  const july2028 = Date.UTC(2028, 6, 14, 20) / 1000
  expect([M.printClock(shop, july2027, calendars), M.printClock(shop, july2028, calendars)]).toEqual(["16:00", "16:00"])
  // A calendar that has run out, as Toronto's did on 31 December 2026:
  // its times come from Yahoo's offset, never its standard time.
  const ran = JSON.parse(JSON.stringify(calendars))
  ran.calendars.TSX.validThrough = "2026-12-31"
  ran.calendars.TSX.utcOffsets = ran.calendars.TSX.utcOffsets.slice(0, 1)
  expect([M.printClock(shop, july2027, ran), M.clockOf(shop, july2027, ran), M.dateOf(shop, july2027, ran)])
    .toEqual(["16:00", "16:00 EDT", "WED 14 JUL 2027"])
  // Inside the calendar, its clock still decides, whatever offset the quote
  // holds: December's close is 16:00 EST, not 17:00 EDT.
  expect(M.printClock(shop, M.epochAt(TSX, "2026-12-30", "16:00"), ran)).toBe("16:00")
  // The years' holidays and Christmas Eve's early close, by TSX's rules.
  const kinds = ["2027-05-24", "2027-12-24", "2027-12-27", "2027-12-28", "2028-01-03", "2028-07-03", "2028-12-26", "2028-12-29"]
    .map(day => M.dayKind(TSX, day).kind)
  expect(kinds).toEqual(["closure", "open", "closure", "closure", "closure", "closure", "closure", "open"])
  expect(M.segmentsOn(TSX, "2027-12-24").map(seg => seg.end)).toEqual([M.epochAt(TSX, "2027-12-24", "13:00")])
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
  // the rows show as +9.95% and the pill must not show as +9.9% while 100
  // to 109.95 reads +10%: around 9.95%, 0.05%, and 99.95%.
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

test("the change arrow points with the day's move and stays flat at zero", () => {
  expect(M.arrowAngle(2.5)).toBeGreaterThan(0)
  expect(M.arrowAngle(-2.5)).toBeLessThan(0)
  expect(M.arrowAngle(0)).toBe(0)
})

test("each look has one sign language", () => {
  expect(M.lookSigns("+2.55%", false)).toBe("+2.55%")
  expect(M.lookSigns("\u22120.59%", false)).toBe("\u22120.59%")
  expect(M.lookSigns("+2.55%", true)).toBe("▲2.55%")
  expect(M.lookSigns("\u22120.59%", true)).toBe("▼0.59%")
  expect(M.lookSigns("—", true)).toBe("—")
})

test("an unknown chart direction stays unset, and a flat day draws no animal", () => {
  const unknown = M.rowModel(openDay(100, null), 0, "pct")
  expect(unknown.dayUp).toBeNull()
  expect(M.animalKind(unknown)).toBe("")
  const flat = M.rowModel(openDay(100.001, 100), 0, "pct")
  expect(flat.tone).toBe("flat")
  expect(M.animalKind(flat)).toBe("")
  expect(M.animalKind(M.rowModel(openDay(110, 100), 0, "pct"))).toBe("bull")
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
    quote: { open: [100, 100, 100], close: [100, 96, 100], high: [101, 97, 101], low: [95, 95, 99], volume: [10, 0, 10] }
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
    { t: 100, o: 1, h: 1.1, l: 0.9, c: 1, v: 10 },
    { t: 200, o: 2, h: 2.2, l: 1.8, c: 2.05, v: 21 }
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
  expect(M.periodStats(empty)).toMatchObject({ last: null, high: null, low: null, coverage: { short: false } })
  expect(M.historyGeometry(empty).points).toEqual([])
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

// Named lists. All is the library, stored as the version-1
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
  // Older files keep sounds and the version check on; only a saved false
  // turns either off. Newer settings may add other defaults.
  expect(read).toMatchObject({ ...v1, reversed: false, lists: [], list: "", range: "1D", hinted: false, sounds: true, updateCheck: true })
  expect([false, "no", 0].map(v => M.fileSettings({ sounds: v }).sounds)).toEqual([false, true, true])
  expect([false, "no", 0].map(v => M.fileSettings({ updateCheck: v }).updateCheck)).toEqual([false, true, true])
  expect(M.listSymbols(read)).toEqual(["NEST", "SILK"])
  expect(M.listOrder(read)).toBe("pct")
  // The version-1 keys keep their meaning, so an older build reads the same All.
  const withLists = library({ list: "Growth" })
  expect(withLists.symbols).toEqual(["NEST", "BO", "IRIS", "SPY"])
  expect(withLists.order).toBe("pct")
  // No file: the default library and cadence, in retro, the look every
  // picture of Stonks shows; a file that chose smooth keeps it.
  expect(M.fileSettings(null).symbols).toEqual(["NVDA", "AAPL", "MSFT", "SPY", "TSLA"])
  expect(M.fileSettings(null).refreshIntervalSec).toBe(60)
  expect([M.fileSettings(null).style, M.fileSettings({ style: "smooth" }).style]).toEqual(["retro", "smooth"])
  // A saved range comes back; one Stonks doesn't draw is the day.
  expect([M.fileSettings({ range: "1M" }).range, M.fileSettings({ range: "2D" }).range]).toEqual(["1M", "1D"])
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
  // An order an older build saved by the amount reads as % change, on All
  // and on a list, each keeping its direction and members.
  const byAmount = M.fileSettings({ symbols: ["AAPL", "MSFT"], order: "abs", reversed: true,
    lists: [{ name: "Yen", symbols: ["MSFT"], order: "abs" }] })
  expect([byAmount.order, byAmount.reversed]).toEqual(["pct", true])
  expect(byAmount.lists).toEqual([{ name: "Yen", symbols: ["MSFT"], order: "pct", reversed: false }])
})

// Each data file a release wrote (test/data-files/VERSION.json; data-files.sh
// write makes the next), read as the Service reads it. What the user made is
// written out here, not read from the file, so a reader that loses something
// can't lose it from what the check expects too: All in an order made by
// hand, a list in manual order arranged by hand, one sorted, one sorted the
// other way, and one empty; the current list a named one, a featured symbol
// off the top, and every view setting off its default. 1.0.0 knew no sounds,
// so its file reads them on, their default; from 1.0.4 the file has them
// off, and the daily version check off too.
const dataFiles = join(import.meta.dir, "data-files")
for (const file of readdirSync(dataFiles).filter(name => name.endsWith(".json"))) describe(file.replace(/\.json$/, ""), () => {
  const old = file === "1.0.0.json"
  const made = {
    lists: [
      { name: "", symbols: ["SPY", "AAPL", "7203.T", "BTC-USD", "^GSPC", "SHEL.L", "JNJ"], order: "manual", reversed: false },
      { name: "US", symbols: ["SPY", "JNJ", "AAPL", "^GSPC"], order: "manual", reversed: false },
      { name: "World", symbols: ["SHEL.L", "7203.T", "AAPL"], order: "name", reversed: false },
      { name: "Movers", symbols: ["BTC-USD", "JNJ", "7203.T"], order: "pct", reversed: true },
      { name: "Later", symbols: [], order: "manual", reversed: false }
    ],
    list: "World", featured: "7203.T", range: "1Y", style: "retro", changeMode: "abs", refreshIntervalSec: 300, hinted: true,
    sounds: old, updateCheck: old
  }
  const text = readFileSync(join(dataFiles, file), "utf8")
  // As Service.parseDataText reads it: one JSON object, through fileSettings.
  const parsed = (() => { try { return JSON.parse(text.trim()) } catch (e) { return null } })()
  const read = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? M.fileSettings(parsed) : null
  const label = list => (list.name || "All") + ": " + (list.symbols.join(", ") || "empty") + ", " + list.order + (list.reversed ? " reversed" : "")
  const shown = s => ({ name: s.list, symbols: M.listSymbols(s), order: M.listOrder(s), reversed: M.listReversed(s) })
  // A switch to a list, as the Service persists it.
  const switched = (s, name) => M.fileSettings(Object.assign({}, s, { list: name }))
  const names = lists => lists.map(list => list.name)
  const current = made.lists.find(list => list.name === made.list)
  test("the file reads", () => expect(read).not.toBeNull())
  test("All, then " + names(made.lists.slice(1)).join(", ") + ", in that order", () => expect(names(M.listChoices(read))).toEqual(names(made.lists)))
  test("the current list is " + label(current), () => expect(label(shown(read))).toBe(label(current)))
  test("featured " + made.featured, () => expect([read.featured, read.symbols.includes(read.featured)]).toEqual([made.featured, true]))
  test("on " + made.range, () => expect(read.range).toBe(made.range))
  test("in " + made.style, () => expect(read.style).toBe(made.style))
  test("the change as " + made.changeMode, () => expect(read.changeMode).toBe(made.changeMode))
  test("refreshed every " + made.refreshIntervalSec + " s", () => expect(read.refreshIntervalSec).toBe(made.refreshIntervalSec))
  test("the first-run hint not shown again", () => expect(read.hinted).toBe(made.hinted))
  test("sounds " + (made.sounds ? "on" : "off"), () => expect(read.sounds).toBe(made.sounds))
  test("the version check " + (made.updateCheck ? "on" : "off"), () => expect(read.updateCheck).toBe(made.updateCheck))
  for (const list of made.lists) test(label(list), () => expect(label(shown(switched(read, list.name)))).toBe(label(list)))
  // After a downgrade, or on a machine sharing the file: the other machine's
  // file is on US; this one switches back to World and sorts it, and writes.
  test("a later version's keys stay through a write: one at the top, one in a list", () => {
    const later = JSON.parse(text)
    later.alerts = [{ symbol: "AAPL", above: 400 }]
    later.lists[1].pinned = true
    later.list = "US"
    const written = JSON.parse(JSON.stringify(M.withListOrder(switched(M.fileSettings(later), made.list), "symbol")))
    expect([written.list, written.lists[1].name, written.lists[1].order]).toEqual([made.list, "World", "symbol"])
    expect([written.alerts, written.lists[1].pinned]).toEqual([later.alerts, true])
  })
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

test("o runs manual, symbol, name, % change and back, and the order word's arrow says which way the values run", () => {
  expect(["manual", "symbol", "name", "pct"].map(M.nextOrder)).toEqual(["symbol", "name", "pct", "manual"])
  expect(["manual", "symbol", "name", "pct"].map(order => M.orderLabel(order, false)))
    .toEqual(["↕  MANUAL", "↑  SYMBOL", "↑  NAME", "↓  % CHANGE"])
  expect(["manual", "symbol", "pct"].map(order => M.orderLabel(order, true))).toEqual(["↕  MANUAL", "↓  SYMBOL", "↑  % CHANGE"])
})

test("a list's name is refused empty, as All, or taken in any case or padding; a new list is made current and empty, its name trimmed", () => {
  const s = library()
  expect([M.listNameProblem("  ", s.lists), M.listNameProblem(" growth ", s.lists), M.listNameProblem("all", s.lists)])
    .toEqual(["Name the list", "growth already exists", "All already exists"])
  const made = M.withListCreated(s, "  Wins ")
  expect([made.list, M.listSymbols(made), made.lists.map(list => list.name)]).toEqual(["Wins", [], ["My Watchlist", "Growth", "Wins"]])
  expect(M.withListCreated(s, "GROWTH")).toBe(s)
  // A rename meets the same rules against the other lists, so a change of
  // case alone renames, and the current list follows its new name.
  expect([M.renameProblem(s, "Growth", "my watchlist"), M.renameProblem(s, "Growth", "GROWTH")]).toEqual(["my watchlist already exists", ""])
  const renamed = M.withListRenamed(library({ list: "Growth" }), "Growth", "GROWTH")
  expect([renamed.list, renamed.lists.map(list => list.name)]).toEqual(["GROWTH", ["My Watchlist", "GROWTH"]])
})

test("All can't be renamed, moved, or deleted, a list moves only between the named lists, and deleting one leaves the rest as they were", () => {
  const s = library({ list: "Growth" })
  for (const same of [M.withListRenamed(s, "", "Mine"), M.withListMoved(s, "", 1), M.withListDeleted(s, ""),
    M.withListMoved(s, "My Watchlist", -1), M.withListMoved(s, "Growth", 1)]) expect(same).toEqual(s)
  expect(M.withListMoved(s, "Growth", -1).lists.map(list => list.name)).toEqual(["Growth", "My Watchlist"])
  const other = M.withListDeleted(s, "My Watchlist")
  expect([other.list, other.symbols, other.lists]).toEqual(["Growth", s.symbols, [s.lists[1]]])
  const current = M.withListDeleted(s, "Growth")
  expect([current.list, current.symbols, current.lists]).toEqual(["", s.symbols, [s.lists[0]]])
})

test("undo puts a removed stock back at its place in All and in each list that held it, and the hero only if the removal moved it", () => {
  const before = library()
  const shown = ["NEST", "BO", "IRIS", "SPY"]
  const out = M.withMembership(before, "BO", "", false, shown)
  const back = M.withRemovalUndone(out, before, "BO", out.featured)
  expect([back.symbols, back.lists.map(list => list.symbols), back.featured])
    .toEqual([before.symbols, before.lists.map(list => list.symbols), "NEST"])
  // The hero removed hands on to the next row, and comes back with its
  // row, unless another hero was chosen since.
  const heroOut = M.withMembership(before, "NEST", "", false, shown)
  expect(heroOut.featured).toBe("BO")
  expect(M.withRemovalUndone(heroOut, before, "NEST", heroOut.featured).featured).toBe("NEST")
  expect(M.withRemovalUndone(M.fileSettings({ ...heroOut, featured: "SPY" }), before, "NEST", heroOut.featured).featured).toBe("SPY")
  // Out of one list only, it goes back into that list at its place.
  const offGrowth = M.withMembership(library({ list: "Growth" }), "BO", "Growth", false, ["BO", "IRIS"])
  expect(M.withRemovalUndone(offGrowth, library({ list: "Growth" }), "BO", offGrowth.featured).lists[1].symbols).toEqual(["BO", "IRIS"])
})

test("the rule under the list name counts up, flat, and down as the rows' tones read them, and a row with no quote as none", () => {
  const q = (symbol, prevClose, dayOpen, price) => ({ symbol, name: symbol, prevClose, dayOpen, price, priceDigits: 2, marketTime: 1, points: [], session: { regular: null } })
  // FLAT closed where it started the day, and is up since its open.
  const quotes = { UP: q("UP", 100, 101, 110), FLAT: q("FLAT", 100, 99, 100), DOWN: q("DOWN", 100, 99, 90) }
  const symbols = ["UP", "FLAT", "DOWN", "GONE"]
  for (const mode of ["pct", "open"]) {
    const rows = { up: 0, flat: 0, down: 0, none: 1 }
    for (const symbol of symbols.slice(0, 3)) rows[M.rowModel(quotes[symbol], 0, mode).tone]++
    expect([mode, M.listBreadth(symbols, quotes, 0, mode)]).toEqual([mode, rows])
  }
  expect(M.listBreadth(symbols, quotes, 0, "pct")).toEqual({ up: 1, flat: 1, down: 1, none: 1 })
  expect(M.listBreadth(symbols, quotes, 0, "open")).toEqual({ up: 2, flat: 0, down: 1, none: 1 })
})

// What ends the undo on offer: a data file, hand-edited or another
// build's, that changes what the lists hold, and none that changes only the
// view.
test("only a change to what the lists hold ends the undo", () => {
  const s = library()
  expect(M.listsHeld(Object.assign({}, s, { range: "1Y", featured: "SPY", order: "symbol", list: "Growth" }))).toBe(M.listsHeld(s))
  expect(M.listsHeld(Object.assign({}, s, { lists: s.lists.concat([{ name: "Made elsewhere", symbols: [] }]) }))).not.toBe(M.listsHeld(s))
})

test("sorting ranks the rows as a view over the manual list", () => {
  const q = (symbol, name, prevClose, price) => ({ symbol, name, prevClose, price, marketTime: 1, points: [], session: { regular: null } })
  // Names that sort unlike the symbols, so each order is its own.
  const quotes = { UP: q("UP", "Alpha Inc", 100, 110), DN: q("DN", "Mid Co", 100, 95), FL: q("FL", "Zeta Corp", 100, 100) }
  const manual = ["FL", "DN", "UP", "NEW"]
  expect(M.sortedSymbols(manual, quotes, "manual")).toEqual(manual)
  expect(M.sortedSymbols(manual, quotes, "symbol")).toEqual(["DN", "FL", "UP", "NEW"])
  expect(M.sortedSymbols(manual, quotes, "name")).toEqual(["UP", "DN", "FL", "NEW"])
  expect(M.sortedSymbols(manual, quotes, "pct")).toEqual(["UP", "FL", "DN", "NEW"])
  // Reversed, each sorted order runs the other way; a symbol with no quote
  // stays at the bottom, and manual has no direction.
  expect(M.sortedSymbols(manual, quotes, "symbol", true)).toEqual(["UP", "FL", "DN", "NEW"])
  expect(M.sortedSymbols(manual, quotes, "pct", true)).toEqual(["DN", "FL", "UP", "NEW"])
  expect(M.sortedSymbols(manual, quotes, "manual", true)).toEqual(manual)
  // A tie keeps the manual order, whichever way the sort runs.
  const tie = { FL2: { ...quotes.FL, symbol: "FL2" }, FL: quotes.FL }
  expect(M.sortedSymbols(["FL2", "FL"], tie, "pct")).toEqual(["FL2", "FL"])
  expect(M.sortedSymbols(["FL2", "FL"], tie, "pct", true)).toEqual(["FL2", "FL"])
  // Lumen is up 10%, NVIDIA 2%: by percent Lumen leads, though NVIDIA's
  // amount is larger, and it still leads with amounts showing: they can't
  // be ranked across currencies.
  const pair = { LUMA: q("LUMA", "Lumen", 10, 11), NVDA: q("NVDA", "NVIDIA", 180, 183.6) }
  expect(M.sortedSymbols(["LUMA", "NVDA"], pair, "pct")).toEqual(["LUMA", "NVDA"])
  expect(M.sortedSymbols(["LUMA", "NVDA"], pair, "pct", false, "abs")).toEqual(["LUMA", "NVDA"])
  // Showing since the open, the rows rank by the move from the open they
  // show: UP is up 10% on the close but 0.9% on the open, DN down 5% on the
  // close but up 5.6% on the open.
  const opened = { UP: { ...quotes.UP, dayOpen: 109 }, DN: { ...quotes.DN, dayOpen: 90 } }
  expect(M.sortedSymbols(["UP", "DN"], opened, "pct", false, "pct")).toEqual(["UP", "DN"])
  expect(M.sortedSymbols(["UP", "DN"], opened, "pct", false, "open")).toEqual(["DN", "UP"])
})

// The keys a sheet or README label names, in one spelling: a capital as
// Shift and it, ⇧ as Shift, and the sheet's "Del ⌫" as Delete and Backspace.
const keyTokens = label => label.replace(/`/g, "").split(/\s+/)
  .filter(t => t !== "" && t !== "or")
  .map(t => ({ "Del": "Delete", "⌫": "Backspace" })[t] || t.replace(/^⇧/, "Shift+"))
  .map(t => /^[A-Z]$/.test(t) ? "Shift+" + t : t)
const sortedKeys = labels => labels.flatMap(keyTokens).sort()

test("the key sheet lists exactly the README's keys for each surface, the row's move only in manual order", () => {
  const lines = readFileSync(join(root, "README.md"), "utf8").split("\n")
  const start = lines.indexOf("| Key | Does |")
  expect(start).toBeGreaterThan(0)
  const table = []
  for (let i = start + 2; lines[i] && lines[i][0] === "|"; i++) table.push(lines[i].split("|").map(c => c.trim()))
  // A row ending "(popup)" or "(window)" is that surface's alone.
  const readme = surface => sortedKeys(table.filter(c => {
    const only = /\((popup|window)\)$/.exec(c[2])
    return !only || only[1] === surface
  }).map(c => c[1]))
  const drawn = (order, switchesPanels) =>
    sortedKeys(M.sheet(order, switchesPanels).groups.flatMap(g => g.rows.map(r => r.key)))
  const moves = ["Shift+↑", "Shift+↓"]
  expect(drawn("manual", true)).toEqual(readme("popup"))
  expect(drawn("manual", false)).toEqual(readme("window"))
  expect(drawn("pct", true)).toEqual(readme("popup").filter(k => !moves.includes(k)))
  expect(drawn("symbol", false)).toEqual(readme("window").filter(k => !moves.includes(k)))
})

test("a letter says its key and Shift, never its text's case, and nothing held with Ctrl or Alt", () => {
  const { typed } = load("KeyText.js")
  const SHIFT = 0x02000000, CTRL = 0x04000000, ALT = 0x08000000, KEYPAD = 0x20000000
  // Caps Lock sends "O" with no Shift, and "o" with it.
  expect(["o", "l", "m"].map(l => typed({ key: l.toUpperCase().charCodeAt(0), modifiers: 0, text: l.toUpperCase() })))
    .toEqual(["o", "l", "m"])
  expect(typed({ key: 79, modifiers: SHIFT, text: "o" })).toBe("O")
  expect(typed({ key: 79, modifiers: SHIFT | KEYPAD, text: "o" })).toBe("O")
  expect(typed({ key: 80, modifiers: 0, text: "p" })).toBe("p")
  expect(typed({ key: 80, modifiers: CTRL, text: "\u0010" })).toBe("")
  expect(typed({ key: 80, modifiers: ALT, text: "p" })).toBe("")
  expect(typed({ key: 63, modifiers: SHIFT, text: "?" })).toBe("?")
})

test("a stock's day is asked for two days from its pre-market until the bell, when Yahoo's day no longer holds the last session", () => {
  const stock = { symbol: "X", exchange: "NASDAQ", instrumentType: "EQUITY", crypto: false }
  const two = (q, date, clock) => M.twoDays(q, at(date, clock), calendars)
  // Friday 23 October: one day through the night, which still holds
  // Thursday; two from the pre-market's open; one again at the bell.
  expect(["03:59", "04:00", "06:22", "09:29", "09:30", "20:00"].map(c => two(stock, "2026-10-23", c)))
    .toEqual([false, true, true, true, false, false])
  // No session to wait for: a Saturday, Thanksgiving.
  expect([two(stock, "2026-10-24", "06:00"), two(stock, "2026-11-26", "06:00")]).toEqual([false, false])
  // An index's answer stays the last session's until its open, a coin's
  // day never waits, and London has no pre-market to turn at.
  expect(two({ ...stock, symbol: "^GSPC", exchange: "S&P", instrumentType: "INDEX" }, "2026-10-23", "06:00")).toBe(false)
  expect(two({ ...stock, symbol: "BTC-USD", exchange: "CRYPTO", instrumentType: "CRYPTOCURRENCY", crypto: true }, "2026-10-23", "06:00")).toBe(false)
  expect(two({ ...stock, symbol: "SHEL.L", exchange: "LSE" }, "2026-10-23", "06:00")).toBe(false)
  // A listing not yet answered: its market and hour aren't known.
  expect(two(null, "2026-10-23", "12:00")).toBe(true)
})

test("a range left on show is asked again every 15 minutes of its session, every hour for daily bars, a failed refresh at the same pace, and once after the close for its last bars", () => {
  const close = at("2026-10-07", "16:00")
  const day = { session: { regular: { start: at("2026-10-07", "09:30"), end: close } } }
  const due = (range, entry, now, trading) => M.historyDue(range, entry, day, now, trading)
  const answered = t => ({ answeredAt: t, receivedAt: t })
  const three = at("2026-10-07", "15:00")
  // While New York trades: a week's 15-minute bars every 15 minutes, a
  // year's daily bars every hour.
  expect([due("1W", answered(three), three + 15 * 60 - 1, true), due("1W", answered(three), three + 15 * 60, true)]).toEqual([false, true])
  expect([due("1Y", answered(three), three + 60 * 60 - 1, true), due("1Y", answered(three), three + 60 * 60, true)]).toEqual([false, true])
  // A failed refresh counts from when it failed, not from the last good
  // answer, so it is tried again at the same pace.
  const failed = { answeredAt: three, receivedAt: three - 60 * 60 }
  expect([due("1W", failed, three + 15 * 60 - 1, true), due("1W", failed, three + 15 * 60, true)]).toEqual([false, true])
  // After the close: once while its last good answer came before the close,
  // a failed one included; then not again.
  const tenTo = at("2026-10-07", "15:50")
  expect(due("1W", answered(tenTo), at("2026-10-07", "16:05"), false)).toBe(true)
  expect(due("1W", { answeredAt: at("2026-10-07", "16:05"), receivedAt: tenTo }, at("2026-10-07", "16:20"), false)).toBe(true)
  expect(due("1W", answered(at("2026-10-07", "16:05")), at("2026-10-07", "19:00"), false)).toBe(false)
  // Before the session, nothing new: closed and not yet past its end.
  expect(due("1W", answered(at("2026-10-07", "08:00")), at("2026-10-07", "09:00"), false)).toBe(false)
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
  // A failed answer is asked again five minutes on, whatever the hour.
  const asked = at("2026-10-02", "04:11")
  expect(M.overnightDue(asked, at("2026-10-02", "04:15"), calendars, true)).toBe(false)
  expect(M.overnightDue(asked, at("2026-10-02", "04:16"), calendars, true)).toBe(true)
  expect(M.overnightDue(asked, at("2026-10-02", "08:00"), calendars, false)).toBe(false)
})

test("a run of Robinhood's prints never takes more requests than a day for all would", () => {
  const now = 1791000000
  const warm = { through: now - 10 * 60 }
  const names = n => Array.from({ length: n }, (_, i) => "S" + i)
  const spans = batches => batches.map(b => b.span + " " + b.symbols.length).join(", ")
  // A small list's first open at night, the pill's stock already in hand:
  // one day for all three, not a day and an hour.
  expect(M.overnightBatches(["AAPL", "MSFT", "SPY"], { AAPL: warm }, now))
    .toEqual([{ span: "day", symbols: ["MSFT", "SPY", "AAPL"] }])
  // A long list's first open: the pill's stock fills the last day's room.
  const long = names(115)
  expect(spans(M.overnightBatches(long, { S0: warm }, now))).toBe("day 25, day 25, day 25, day 25, day 15")
  // Its refreshes through the night: the last hour, two requests, not five.
  const inHand = Object.fromEntries(long.map(s => [s, warm]))
  expect(spans(M.overnightBatches(long, inHand, now))).toBe("hour 75, hour 40")
  // Three added to it meanwhile: their days, and the rest's hour.
  expect(spans(M.overnightBatches(long.concat(["N1", "N2", "N3"]), inHand, now))).toBe("day 3, hour 75, hour 40")
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
  const sundayPrint = { t: at("2026-11-01", "21:00"), p: 100.5, s: "overnight" }
  const sunday = M.dayChart(quote, { bars: [sundayPrint], through: sundayPrint.t }, calendars)
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
  const thursdayPrint = { t: at("2026-11-26", "22:00"), p: 100.2, s: "overnight" }
  const friday = M.dayChart(early, { bars: [thursdayPrint], through: thursdayPrint.t }, calendars).day
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
          expect([reader, gmtoffset, history.bars.map(bar => M.historyScrubForms(history, bar)[1])])
            .toEqual([reader, gmtoffset, dates])
        }
      }
    } finally { process.env.TZ = "America/New_York" }
  }
  // The live moment Yahoo appends keeps today's date, even at a whole hour
  // of a coin's day, where no clock changes: Saturday 31 October's 23:00
  // UTC is not the week of 1 November.
  const live = stamp("2026-10-31T23:00:00Z")
  const coin = { range: "5Y", interval: "1wk", gmtoffset: 0, liveAt: live,
    bars: [{ t: stamp("2026-10-26T00:00:00Z"), c: 100 }, { t: live, c: 101 }] }
  expect(coin.bars.map(bar => M.historyScrubForms(coin, bar)[1])).toEqual(["WEEK OF 26 OCT", "WEEK OF 31 OCT"])
})

test("a session's one bar says nothing until its five minutes are past", () => {
  // An index's opening bar with its close already in, three minutes into
  // the session, must not read "Traded only at 09:30".
  const bell = at("2026-10-20", "09:30")
  const day = { symbol: "^GSPC", exchange: "S&P", instrumentType: "INDEX", gmtoffset: -14400,
    session: { pre: null, regular: { start: bell, end: at("2026-10-20", "16:00") }, post: null },
    points: [{ t: bell, p: 100 }] }
  expect(M.dayNote(day, bell + 180, calendars)).toBe("")
  expect(M.dayNote(day, bell + 300, calendars)).toBe("Traded only at 09:30")
})

test("Robinhood's word on all-day trading is asked once, again a day on, or five minutes after a failure", () => {
  const t = at("2026-10-07", "01:00")
  expect(M.allDayDue(null, t)).toBe(true)
  expect(M.allDayDue({ status: "ok", allDay: true, at: t }, t + 24 * 3600 - 1)).toBe(false)
  expect(M.allDayDue({ status: "ok", allDay: false, at: t }, t + 24 * 3600)).toBe(true)
  expect(M.allDayDue({ status: "failed", allDay: false, at: t }, t + 5 * 60 - 1)).toBe(false)
  expect(M.allDayDue({ status: "failed", allDay: false, at: t }, t + 5 * 60)).toBe(true)
})

// What the service and the quote feed ask for, and when (Asks.js), on
// Wednesday 21 October: a US stock, whose pre-market, session and after
// hours are Yahoo's; London's, which closes at 11:30 in New York; a coin.
const WED = "2026-10-21"
const usStock = symbol => ({
  symbol, exchange: "NASDAQ", instrumentType: "EQUITY", crypto: false, points: [],
  session: {
    pre: { start: at(WED, "04:00"), end: at(WED, "09:30") },
    regular: { start: at(WED, "09:30"), end: at(WED, "16:00") },
    post: { start: at(WED, "16:00"), end: at(WED, "20:00") }
  }
})
const shel = {
  symbol: "SHEL.L", exchange: "LSE", instrumentType: "EQUITY", crypto: false, points: [],
  session: { pre: null, post: null, regular: { start: M.epochAt(calendars.calendars.LSE, WED, "08:00"), end: M.epochAt(calendars.calendars.LSE, WED, "16:30") } }
}
const coin = symbol => ({ symbol, exchange: "CCC", instrumentType: "CRYPTOCURRENCY", crypto: true, points: [] })
const answered = t => ({ status: "ok", receivedAt: t, answeredAt: t })

test("with nothing open, the pill's quote and each listing in its regular session are kept fresh, and all of All while a surface is open", () => {
  const quotes = { AAPL: usStock("AAPL"), "SHEL.L": shel, "BTC-USD": coin("BTC-USD") }
  const all = Object.keys(quotes)
  const watched = (clock, featured, open) => {
    const now = at(WED, clock)
    return M.watchedSymbols(all, featured, open, quotes, now, M.calendarsAt(calendars, now))
  }
  // 10:00 in New York: both markets trade; a coin never rests, so only the
  // pill keeps it fresh.
  expect(watched("10:00", "", false)).toEqual(["AAPL", "SHEL.L"])
  expect(watched("12:00", "", false)).toEqual(["AAPL"])
  expect(watched("12:00", "BTC-USD", false)).toEqual(["AAPL", "BTC-USD"])
  // After hours: the pill's alone, unless a surface is open.
  expect(watched("17:00", "AAPL", false)).toEqual(["AAPL"])
  expect(watched("17:00", "", true)).toEqual(all)
})

test("a quote run takes every quote due within half a minute of one due, and names the second the next falls due", () => {
  const now = at(WED, "12:00")
  const calNow = M.calendarsAt(calendars, now)
  const quotes = { A: coin("A"), B: coin("B"), C: coin("C"), D: coin("D") }
  const due = (entries, asked = {}) => M.quotesDue(Object.keys(quotes), entries, asked, quotes, [], now, 60, calNow)
  // A is a minute old: B, due in 20 s, goes with it; C, due in 40 s, waits
  // and wakes the clock.
  expect(due({ A: answered(now - 60), B: answered(now - 40), C: answered(now - 20) })).toEqual({ due: ["A", "B"], next: now + 40 })
  // With none due, nothing goes early.
  expect(due({ A: answered(now - 50), B: answered(now - 40) })).toEqual({ due: [], next: now + 10 })
  // A failed answer is due on the same clock; one stamped ahead of the
  // clock, set back since, is due at once.
  expect(due({ A: { status: "failed", receivedAt: 0, answeredAt: now - 60 }, B: answered(now + 300) }).due).toEqual(["A", "B"])
  // A first answer, a quote kept from an earlier session, and one already
  // asked for are the feed's to ask.
  expect(due({ B: { status: "saved", receivedAt: now - 3600, answeredAt: 0 }, C: answered(now - 60) }, { C: now - 5 }))
    .toEqual({ due: [], next: 0 })
  // After hours an open surface's hero is asked on the interval, the rest
  // every 5 minutes.
  const late = at(WED, "17:00")
  const stocks = { AAPL: usStock("AAPL"), MSFT: usStock("MSFT") }
  expect(M.quotesDue(["AAPL", "MSFT"], { AAPL: answered(late - 60), MSFT: answered(late - 60) }, {}, stocks, ["AAPL"], late, 60,
    M.calendarsAt(calendars, late))).toEqual({ due: ["AAPL"], next: late + 240 })
})

test("a refresh asks again only for quotes answered more than 10 s ago, and for Robinhood's prints only on charts it trades all day", () => {
  const now = at(WED, "12:00")
  const entries = { OLD: answered(now - 11), NEW: answered(now - 10), KEPT: { status: "saved", receivedAt: 1, answeredAt: 0 } }
  expect(M.refreshQuotes(["OLD", "NEW", "KEPT", "NONE"], entries, now)).toEqual(["OLD"])
  expect(M.refreshPrints(["AAPL", "SHEL.L"], ["AAPL"], now - 11, now)).toEqual(["AAPL"])
  expect(M.refreshPrints(["AAPL"], ["AAPL"], now - 10, now)).toEqual([])
})

test("a quote run charts the pill's quote first and the other heroes next, then the rest in spark batches of 20 in the order asked", () => {
  const symbols = Array.from({ length: 23 }, (_, i) => "S" + i)
  // S22 was asked a second before the rest: the budget held it back.
  const asked = Object.fromEntries(symbols.map(s => [s, s === "S22" ? 99 : 100]))
  const slots = M.quoteSlots(symbols, asked, symbols, "S5", ["S9", "S5"], true)
  const batch = ["S22", "S0", "S1", "S2", "S3", "S4", "S6", "S7", "S8"].concat(symbols.slice(10, 21))
  // The one left over is one request either way, and a chart's has opens.
  expect(slots).toEqual([
    { symbols: ["S5"], spark: false }, { symbols: ["S9"], spark: false },
    { symbols: batch, spark: true }, { symbols: ["S21"], spark: false }
  ])
  // The preview's feed asks only charts.
  expect(M.quoteSlots(["P", "Q"], { P: 1, Q: 1 }, ["P", "Q"], "", [], false))
    .toEqual([{ symbols: ["P"], spark: false }, { symbols: ["Q"], spark: false }])
  // Each lane runs its own kind, a first answer (none yet, or a quote kept
  // from an earlier session) or a refresh, never one cooling after a bad
  // answer or out on a run; a day waiting to be judged goes only when its
  // own refresh isn't asked anyway.
  const entries = { R: answered(1), C: answered(1), K: { status: "saved", receivedAt: 1, answeredAt: 0 } }
  const waiting = { N: 1, K: 1, R: 1, C: 1 }
  expect(M.laneWaiting(["N", "K", "R", "C", "X"], waiting, entries, true, [])).toEqual(["N", "K"])
  expect(M.laneWaiting(["N", "K", "R", "C", "X"], waiting, entries, false, ["C"])).toEqual(["R"])
  expect(M.laneJudging(["R", "J", "H"], waiting, ["H"])).toEqual(["J"])
  // A hero whose quote came from spark, with no opens, is asked for its
  // chart, but not again at once after its chart failed.
  const sparked = { H: { closesOnly: true }, C: {} }
  expect(M.sparkHeroes(["H", "C"], sparked, {}, false)).toEqual(["H"])
  expect(M.sparkHeroes(["H"], sparked, { H: { status: "failed" } }, true)).toEqual([])
  expect(M.sparkHeroes(["H"], sparked, { H: { status: "failed" } }, false)).toEqual(["H"])
})

test("a refresh for a quote no longer watched leaves the queue unless its run is out, and a first answer always stays", () => {
  const entries = { GONE: answered(1), OUT: answered(1), KEPT: answered(1) }
  expect(M.keptAsks({ NEW: 5, GONE: 5, OUT: 5, KEPT: 5 }, ["KEPT"], entries, ["OUT"])).toEqual({ NEW: 5, OUT: 5, KEPT: 5 })
})

test("a bad quote answer is tried three times in all, a missing symbol fails at once, and a refusal waits for its host", () => {
  const read = { quote: { symbol: "A" }, unjudged: false }
  expect(M.answerVerdict("ok", read, 2, false)).toBe("show")
  expect([0, 1, 2].map(tries => M.answerVerdict("bad", null, tries, false))).toEqual(["retry", "retry", "fail"])
  // A whole answer that doesn't read is a bad one; a spark answer without
  // the symbol, a missing one.
  expect(M.answerVerdict("ok", null, 0, false)).toBe("retry")
  expect([M.answerVerdict("missing", null, 0, false), M.answerVerdict("ok", "missing", 0, false)]).toEqual(["fail", "fail"])
  expect([M.answerVerdict("refused", null, 2, false), M.answerVerdict("none", null, 2, false)]).toEqual(["host", "host"])
  // A chart asked only to judge a day already shown changes nothing when
  // it brings no quote.
  expect([M.answerVerdict("bad", null, 0, true), M.answerVerdict("ok", read, 0, true)]).toEqual(["unchanged", "show"])
})

test("Robinhood is asked once a session for the pill's stock with nothing open, and for every US listing while a surface is, the chart waited on alone first", () => {
  const now = at(WED, "21:00")
  const base = {
    open: false, pill: "AAPL", pillAsked: false, quoteEntries: { AAPL: answered(now) }, overnightSymbols: ["AAPL", "MSFT"],
    library: ["AAPL", "MSFT", "SHEL.L"], preview: "", previewShown: false, previewQuote: null, allDay: {}, nights: {}, now, calendars
  }
  const asks = changes => M.overnightAsks({ ...base, ...changes })
  // Nothing open: the pill's stock alone, once Yahoo has answered it live,
  // and once a session; what Robinhood has answered for it is enough.
  expect(asks({})).toEqual({ tradability: ["AAPL"], prints: ["AAPL"] })
  expect(asks({ quoteEntries: { AAPL: { status: "saved", receivedAt: 1, answeredAt: 0 } } })).toBe(null)
  expect(asks({ pillAsked: true })).toBe(null)
  expect(asks({ allDay: { AAPL: { status: "ok", allDay: true, at: now - DAY - 60 } }, nights: { AAPL: { status: "ok", at: now - 3600 } } })).toBe(null)
  // A surface open: every US listing, the pill's alone while it has no
  // answer.
  expect(asks({ open: true })).toEqual({ tradability: ["AAPL"], prints: ["AAPL"] })
  const pillAnswered = ago => ({ open: true, allDay: { AAPL: { status: "ok", allDay: true, at: now - 60 } }, nights: { AAPL: { status: "ok", at: now - ago } } })
  expect(asks(pillAnswered(60))).toEqual({ tradability: ["MSFT"], prints: ["MSFT"] })
  // Prints asked 3 minutes ago go with those due, within half of a night's
  // 5 minutes.
  expect(asks(pillAnswered(180)).prints).toEqual(["AAPL", "MSFT"])
  // One Robinhood trades only by day never has its prints asked.
  const byDay = { ...pillAnswered(60), allDay: { AAPL: { status: "ok", allDay: true, at: now - 60 }, MSFT: { status: "ok", allDay: false, at: now - 60 } } }
  expect(asks(byDay)).toBe(null)
  // A preview outside All on view, a US stock by search's result before its
  // quote, is asked with them, alone first while it has no answer; off
  // view, it waits.
  const nvda = { preview: "NVDA", previewShown: true, previewQuote: { symbol: "NVDA", exchange: "NASDAQ", instrumentType: "EQUITY" } }
  expect(asks({ ...pillAnswered(60), ...nvda })).toEqual({ tradability: ["NVDA"], prints: ["NVDA"] })
  expect(asks({ ...pillAnswered(60), ...nvda, previewShown: false })).toEqual({ tradability: ["MSFT"], prints: ["MSFT"] })
})

test("a refresh's chart is owed until a new answer replaces the one it had, then a chart with no answer is asked, and the day asks none", () => {
  // The window previews NVDA while the popup shows AAPL; the window alone
  // charts only its preview, once it rests.
  const charts = M.chartsOnShow(["popup", "window"], "AAPL", "NVDA", "window", true)
  expect(charts).toEqual(["AAPL", "NVDA"])
  expect(M.chartsOnShow(["window"], "AAPL", "NVDA", "window", true)).toEqual(["NVDA"])
  expect(M.chartsOnShow(["window"], "AAPL", "NVDA", "window", false)).toEqual([])
  expect(M.chartsOnShow([], "AAPL", "", null, false)).toEqual([])
  expect(M.historyCharts(charts, "1D")).toEqual([])
  const both = { "AAPL|1W": { status: "ok", history: {} }, "NVDA|1W": { status: "ok", history: {} } }
  expect(M.nextHistory(charts, "1W", both, {})).toBe(null)
  expect(M.nextHistory(charts, "1W", { "AAPL|1W": both["AAPL|1W"] }, {})).toEqual({ symbol: "NVDA", force: false })
  // A refresh owes both, fetched fresh in turn; a failed answer settles one
  // as a good one does.
  const owing = M.historyOwing(charts, "1W", both)
  expect(M.nextHistory(charts, "1W", both, owing)).toEqual({ symbol: "AAPL", force: true })
  expect(M.nextHistory(charts, "1W", { ...both, "AAPL|1W": { status: "failed" } }, owing)).toEqual({ symbol: "NVDA", force: true })
  // Left on show, the first hero whose range has grown old is asked again,
  // by the preview's quote where only it has one.
  const noon = at(WED, "12:00")
  const aged = { "NVDA|1W": { history: {}, answeredAt: noon - 60 }, "AAPL|1W": { history: {}, answeredAt: noon - 15 * 60 } }
  expect(M.staleHistory(["NVDA", "AAPL"], "1W", aged, {}, { AAPL: usStock("AAPL"), NVDA: usStock("NVDA") }, noon, calendars)).toBe("AAPL")
  expect(M.staleHistory(["NVDA"], "1W", aged, {}, { NVDA: usStock("NVDA") }, noon, calendars)).toBe("")
})

test("the rows in sight have their charts fetched ahead, the heroes' aside, as many as the cache keeps beside them, and none on the day", () => {
  const sights = [{ surface: "popup", symbols: ["A", "B", "HERO"] }, { surface: "window", symbols: ["B", "C", "D"] }]
  expect(M.aheadRows(true, "1W", ["HERO"], sights, 40)).toEqual(["A", "B", "C", "D"])
  expect(M.aheadRows(true, "1W", ["HERO"], sights, 4)).toEqual(["A", "B", "C"])
  expect(M.aheadRows(true, "1D", [], sights, 40)).toEqual([])
  expect(M.aheadRows(false, "1W", [], sights, 40)).toEqual([])
  // One answered or missed ahead on this range is not asked again on it.
  expect(M.aheadCharts(["A", "B", "C"], "1W", { "A|1W": {} }, { "B|1W": true })).toEqual(["C"])
  expect(M.aheadCharts(["A"], "1M", { "A|1W": {} }, {})).toEqual(["A"])
})

test("a cap and P/E asked for before its quote waits in its asker's place, and only an equity's is fetched", () => {
  const none = { stock: "", preview: "" }
  const early = M.fundamentalsAsk(none, "stock", "MSFT", null)
  expect(early).toEqual({ pending: { stock: "MSFT", preview: "" }, fetch: false })
  // The preview's ask leaves the stock's waiting.
  const both = M.fundamentalsAsk(early.pending, "preview", "SHOP.TO", null).pending
  expect(both).toEqual({ stock: "MSFT", preview: "SHOP.TO" })
  expect(M.fundamentalsAsk(both, "stock", "MSFT", usStock("MSFT"))).toEqual({ pending: { stock: "", preview: "SHOP.TO" }, fetch: true })
  expect(M.fundamentalsAsk(none, "stock", "BTC-USD", coin("BTC-USD")).fetch).toBe(false)
})

test("the clock steps just past each second while a surface is open and each minute while none is, sooner for a quote due or a pause ending", () => {
  const now = at(WED, "12:00")
  const ms = now * 1000 + 250
  expect(M.clockWait(true, ms, now, [])).toBe(755)
  expect(M.clockWait(false, ms, now, [])).toBe(59755)
  // Only a deadline after the service's second and before the next step
  // counts; one the wall clock has passed already is at once.
  expect(M.clockWait(false, ms, now, [now + 20, now - 5, now + 600, 0])).toBe(19755)
  expect(M.clockWait(false, ms, now - 3, [now - 1])).toBe(5)
})

test("community themes that one hue, a faint colour, or a tinted light ground would trip", () => {
  // Palettes from Omarchy's community themes, as the shell resolves them:
  // the green, the red (the shell's urgent), and the surface's ground.
  const colour = c => typeof c === "string" ? M.hexColor(c) : c
  // Independent meaning, not the production pair supplying its own expected
  // value. A valid tune of these greens/reds need not preserve exact hexes.
  const greenAndRed = pair => {
    const [up, down] = [colour(pair.up), colour(pair.down)]
    expect([up.g >= 1.25 * Math.max(up.r, up.b), down.r >= 1.25 * Math.max(down.g, down.b)]).toEqual([true, true])
  }
  const cases = [
    { name: "Clear light", green: "#008000", red: "#b00000", ground: "#ffffff", want: "theme" },
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
    if (c.want === "theme") expect([c.name, got]).toEqual([c.name, { up: c.green, down: red }])
    else greenAndRed(got)
    // Stonks' own reads at 4.5:1 on a light ground and 6:1 on a dark one,
    // where a colour at 4.5:1 is dark enough to look muddy.
    const floor = { theme: 3, light: 4.5, dark: 6 }[c.want]
    expect([c.name, M.paired(M.hexOf(colour(got.up)), colour(got.down))]).toEqual([c.name, true])
    expect([c.name, M.contrast(colour(got.up), ground) >= floor, M.contrast(colour(got.down), ground) >= floor]).toEqual([c.name, true, true])
  }
  // The floor is each surface's own: Ferrari F1's red bar takes Stonks'
  // pair, where the theme's red is at 1.66:1, while its dark popup keeps the
  // theme's (https://github.com/hueilost/omarchy-theme-ferrari-f1).
  const red = M.hexColor("#ff2800")
  greenAndRed(M.trend("#3ddc84", red, M.hexColor("#c40000")))
  expect(M.trend("#3ddc84", red, M.hexColor("#0d0d0f"))).toEqual({ up: "#3ddc84", down: red })
  // A light bar under a dark popup takes the other pair: White's on black.
  greenAndRed(M.trend("#3a3a3a", M.hexColor("#2a2a2a"), M.hexColor("#000000")))
  // On a mid-grey ground no green reads at 4.5:1, and the darkest tried
  // rounded to black, which reads but says nothing: there, up is a green at
  // the 3:1 floor.
  const mid = M.hexColor("#808080"), greyPair = M.trend("#777777", M.hexColor("#555555"), mid)
  greenAndRed(greyPair)
  const chroma = c => Math.hypot(M.oklab(c).a, M.oklab(c).b)
  expect([greyPair.up, chroma(colour(greyPair.up)) >= 0.07, M.contrast(colour(greyPair.up), mid) >= 3]).toEqual([greyPair.up, true, true])
  // On a #bb0022 bar a light green reads at 6:1 only within 0.003 of
  // lightness, which a search in steps passed over for the 3:1 floor.
  const bar = M.hexColor("#bb0022"), barPair = M.trend("#777777", M.hexColor("#555555"), bar)
  expect([M.contrast(colour(barPair.up), bar) >= 6, chroma(colour(barPair.up)) >= 0.063]).toEqual([true, true])
  // On a dark grey, a light red reads at 6:1 only in a narrow band of
  // lightness, which a coarse search passed over for the 3:1 floor.
  for (const grey of ["#454545", "#484848"]) {
    const ground = M.hexColor(grey), pair = M.trend("#777777", M.hexColor("#555555"), ground)
    greenAndRed(pair)
    expect([grey, M.contrast(colour(pair.up), ground) >= 6, M.contrast(colour(pair.down), ground) >= 6]).toEqual([grey, true, true])
  }
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
    // A spark day that throws as it is read leaves its feed asking nothing
    // more until Stonks restarts.
    { name: "a day's period null", call: read, answer: chartAnswer(r => { r.meta.tradingPeriods.pre = [[null]] }) },
    { name: "a spark day with a period null", call: "M.sparkQuote(json, null, [])",
      answer: chartAnswer(r => { r.meta.tradingPeriods.pre = [[null]] }).chart.result[0] },
    // A day's one period ending at an object throws where a bar is compared
    // with it; one no bar is compared with stays in the quote, where every
    // look for what is due throws.
    { name: "a spark day whose period ends at an object", call: "M.sparkQuote(json, null, [])",
      answer: chartAnswer(null, [[period(T0, { toString: null })]]).chart.result[0] },
    { name: "a current period ending at an object", call: read,
      answer: chartAnswer(r => { r.meta.currentTradingPeriod = { regular: period(T0, { toString: null }) } }) },
    { name: "a period's start as text", call: read, answer: chartAnswer(r => { r.meta.tradingPeriods.regular[0][0].start = String(T0) }) },
    { name: "a period's offset an object", call: read, answer: chartAnswer(r => { r.meta.tradingPeriods.post[0][0].gmtoffset = { toString: null } }) },
    { name: "bar times over budget", call: read, answer: chartAnswer(r => { r.timestamp = times(M.MOST_BARS + 1) }) },
    { name: "closes over budget", call: read, answer: chartAnswer(r => { bars(r).close = times(M.MOST_BARS + 1).map(() => 10) }) },
    { name: "a session's days over budget", call: read,
      answer: chartAnswer(r => { r.meta.tradingPeriods.pre = times(M.MOST_DAYS + 1).map(() => [period(T0 - 3600, T0)]) }) },
    // A 322-byte answer whose retro chart would fill 222 billion columns from
    // its middle print back to its last.
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
  const series = (type, value, date = "2026-09-30") => ({ meta: { type: [type] }, [type]: [{ asOfDate: date, currencyCode: "USD", reportedValue: { raw: value } }] })
  const timeseries = edit => {
    const answer = { timeseries: { result: [series("trailingMarketCap", 4e12), series("quarterlyMarketCap", 3e12, "2026-06-30"), series("trailingDilutedEPS", 7)] } }
    if (edit) edit(answer.timeseries.result)
    return answer
  }
  const read = "M.parseFundamentals(json)"
  const figures = { cap: { value: 4e12, date: "2026-09-30", currency: "USD" }, eps: { value: 7, date: "2026-09-30", currency: "USD" } }
  const quarter = { value: 3e12, date: "2026-06-30", currency: "USD" }
  const closes = `M.withCapClose(${JSON.stringify(figures)}, json)`
  const closed = { ...figures, cap: { ...figures.cap, close: 250 } }
  const rate = "M.parseRate(json, 'USDCAD')"
  const rateAnswer = edit => chartAnswer(r => { r.meta.symbol = "USDCAD=X"; r.meta.currency = "CAD"; r.meta.regularMarketPrice = 1.4; if (edit) edit(r) })
  const day = Date.UTC(2026, 8, 30) / 1000 + 14 * 3600
  const cases = [
    { name: "an answer, as sent", call: read, answer: timeseries(), want: figures },
    { name: "the cap's series posing", call: read, answer: timeseries(r => { r[0].trailingMarketCap = POSING }), want: { cap: quarter, eps: figures.eps } },
    { name: "both caps' series posing", call: read,
      answer: timeseries(r => { r[0].trailingMarketCap = POSING; r[1].quarterlyMarketCap = POSING }), want: { cap: null, eps: figures.eps } },
    { name: "the EPS series posing", call: read, answer: timeseries(r => { r[2].trailingDilutedEPS = POSING }), want: { cap: figures.cap, eps: null } },
    { name: "the series posing", call: "M.latestSnapshot(json, 'trailingMarketCap')", answer: POSING },
    { name: "the series over budget", call: read, answer: timeseries(r => r.push(...times(M.MOST_SERIES - 2).map(() => series("trailingDilutedEPS", 7)))) },
    { name: "the cap's snapshots over budget", call: read,
      answer: timeseries(r => { r[0].trailingMarketCap = times(M.MOST_SNAPSHOTS + 1).map(() => r[0].trailingMarketCap[0]) }), want: { cap: quarter, eps: figures.eps } },
    { name: "the closes, as sent", call: closes, answer: chartAnswer(r => { r.timestamp = [day]; bars(r).close = [250] }), want: closed },
    { name: "the closes' times posing", call: closes, answer: chartAnswer(r => { r.timestamp = POSING }) },
    { name: "the closes posing", call: closes, answer: chartAnswer(r => { r.timestamp = [day]; bars(r).close = POSING }) },
    { name: "the closes over budget", call: closes,
      answer: chartAnswer(r => { r.timestamp = times(M.MOST_BARS + 1).map(t => t - T0 - 300 * M.MOST_BARS + day); bars(r).close = r.timestamp.map(() => 250) }) },
    { name: "the closes' times no Date holds", call: closes, answer: chartAnswer(r => { r.timestamp = [1e300]; bars(r).close = [250] }) },
    { name: "a rate, as sent", call: rate, answer: rateAnswer(), want: 1.4 },
    { name: "a rate posing", call: rate, answer: rateAnswer(r => { r.meta.regularMarketPrice = POSING }) },
    { name: "a rate for another pair", call: rate, answer: rateAnswer(r => { r.meta.symbol = "USDGBP=X" }) },
    { name: "a rate in another currency", call: rate, answer: rateAnswer(r => { r.meta.currency = "GBP" }) }
  ]
  expect(await hostile(cases)).toEqual(cases.map(c => [c.name, c.want === undefined ? null : c.want]))
}, 60000)

test("a hostile search or Robinhood answer reads as no answer, at once", async () => {
  const quote = { symbol: "SHOP", quoteType: "EQUITY", exchange: "NMS", longname: "Shopify Inc." }
  const result = historicals => ({ symbol: "NEST", historicals })
  const print = { begins_at: "2026-10-07T00:00:00Z", close_price: "10.00", session: "overnight", interpolated: false }
  const nest = "M.overnightAnswer(json.results[0], 'NEST').bars.length"
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

// Half a UTF-16 pair can't go in a URL: the quote feed would take its
// first-answer slot, encodeURIComponent would throw before any request
// started, and no new symbol's quote would come until the shell restarts.
test("search leaves out a symbol no request can carry", () => {
  const found = M.parseSearch(JSON.parse('{"quotes":[{"symbol":"\\ud800","quoteType":"EQUITY"},{"symbol":"AAPL","quoteType":"EQUITY"}]}'))
  expect(found.results.map(r => M.chartUrl(r.symbol))).toEqual([M.chartUrl("AAPL")])
})

test("search names are whole, so the row's own ellipsis is the only cut", () => {
  const rows = M.parseSearch({ quotes: [
    // Yahoo's short name stops at 31 characters; the long name is whole.
    { symbol: "TSLT", shortname: "T-REX 2X Long Tesla Daily Targe", longname: "T-REX 2X Long Tesla Daily Target ETF", exchange: "BTS", quoteType: "ETF" },
    // A German listing pads its share class onto the short name.
    { symbol: "VUAA.DE", shortname: "Vanguard S&P 500 UCITS ETF    R", longname: null, exchange: "GER", quoteType: "ETF" },
    { symbol: "MTX.F", shortname: "MTU Aero Engines AG           N", exchange: "FRA", quoteType: "EQUITY" },
    // Neither an option nor a row without a symbol is something to add.
    { symbol: "TSLA260918C00400000", shortname: "TSLA Sep 2026 400 call", exchange: "OPR", quoteType: "OPTION" },
    { shortname: "No symbol", exchange: "NMS", quoteType: "EQUITY" },
    { symbol: "BARE", exchange: "NMS", quoteType: "EQUITY" }
  ] }).results
  expect(rows.map(r => r.name)).toEqual([
    "T-REX 2X Long Tesla Daily Target ETF", "Vanguard S&P 500 UCITS ETF", "MTU Aero Engines AG", "BARE"
  ])
})

// An object in a close cell throws where its price is drawn or written, and
// an overflowing number reads Infinity. Each is a gap in the chart, as a
// missing close is.
test("a close that isn't a finite number is a missing bar, in the day and in a range", () => {
  for (const bad of [{ toString: null }, JSON.parse("1e309"), "10"]) for (const at of [1, 2]) {
    const sent = close => r => { bars(r).close[at] = close }
    expect(M.parseChart(chartAnswer(sent(bad)), [])).toEqual(M.parseChart(chartAnswer(sent(null)), []))
    expect(M.parseHistory(rangeAnswer(sent(bad)), "1M", [])).toEqual(M.parseHistory(rangeAnswer(sent(null)), "1M", []))
  }
})

// An answer's offset is the clock a print outside its periods is read by:
// an object there throws wherever a time is worked out, every look for
// what is due among them. One that isn't an offset is none.
test("an answer's offset that isn't one is none, in the day and in a range", () => {
  for (const bad of [{ toString: null }, "-14400", 1e13]) {
    const sent = offset => r => { r.meta.gmtoffset = offset }
    expect(M.parseChart(chartAnswer(sent(bad)), []).gmtoffset).toBe(0)
    expect(M.parseHistory(rangeAnswer(sent(bad)), "1M", []).gmtoffset).toBe(0)
  }
})

// A Robinhood whose hour answers each run five minutes on would have the
// shell keep 150 more prints at every one, 15,000 after a hundred, and with
// their times ahead of the clock, ask for an hour again for ever.
test("a hostile Robinhood's hours keep at most a day's request's prints, and times ahead of the clock ask for a day", () => {
  const hour = k => M.overnightAnswer({ symbol: "X", historicals: Array.from({ length: 150 }, (_, j) =>
    ({ begins_at: new Date((T0 + k * 300 + j) * 1000).toISOString(), close_price: "10", session: "overnight", interpolated: false })) }, "X")
  let kept = hour(0)
  for (let k = 1; k <= 100; k++) kept = M.joinHour(kept, hour(k))
  expect(kept.bars.length).toBe(M.MOST_PRINTS)
  expect(kept.bars.slice(-150)).toEqual(hour(100).bars)
  expect(M.overnightSpan(kept, T0)).toBe("day")
  expect(M.overnightSpan({ through: T0 + 60 }, T0)).toBe("day")
})

// A time of 1e300 kept as the quote's throws in the words that say how
// fresh it is, and the screenshot's. One a Date holds only at UTC's clock
// throws at Tokyo's.
test("a quote's time no Date holds is none: its price and chart stay, and its time reads as not sent", () => {
  const sent = time => M.parseChart(chartAnswer(r => { r.meta.regularMarketTime = time; r.meta.gmtoffset = 32400 }), [])
  const none = sent(undefined)
  const said = q => [M.freshnessText(M.freshness({ status: "ok", answeredAt: T0 }, q, T0 + 600, 0, false), q, null),
    M.words({ quote: q, day: q, history: null, latest: null, scrubT: 0, changeMode: "pct", range: "1D", now: T0 + 600, calendars: null })]
  for (const bad of [1e300, 8.64e12]) {
    expect(sent(bad)).toEqual(none)
    expect(said(sent(bad))).toEqual(said(none))
  }
  expect(none.price).toBe(10)
  expect(none.points.length).toBe(3)
  expect(said(none)[0]).toBe("TIME NOT SENT")
})

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
  expect(found).toEqual({ results: [{ symbol: "SHOP", name: "Shopify", exchange: "", instrumentType: "EQUITY" }], note: "Stonks doesn’t show mutual funds or warrants", topLeftOut: false })
  const cap = { meta: { type: ["trailingMarketCap"] }, trailingMarketCap: [{ asOfDate: "2026-09-30", currencyCode: long(1e5), reportedValue: { raw: 4e12 } }] }
  expect(M.parseFundamentals({ timeseries: { result: [cap] } }).cap.currency).toBe("")
  // A spark listing under a symbol past its length is one Yahoo didn't send.
  const spark = symbol => M.sparkResults({ spark: { result: [{ symbol, response: [chartAnswer().chart.result[0]] }] } })
  expect([Object.keys(spark("X")), Object.keys(spark(long(1e5)))]).toEqual([["X"], []])
})

// The update check offers main's version only when it comes after the
// running one, number by number.
test("a version is newer number by number, and a manifest names one only whole", () => {
  const R = load("Release.js")
  expect(R.isNewer("1.0.10", "1.0.9")).toBe(true)
  expect([["1.0.8", "1.0.9"], ["1.0.9", "1.0.9"], ["x", "1.0.9"]].map(([a, b]) => R.isNewer(a, b))).toEqual([false, false, false])
  expect(R.manifestVersion('{ "version": "9.9.9" }')).toBe("9.9.9")
  expect([R.manifestVersion('{\n  "id": "grvc.st'), R.manifestVersion('{ "id": "grvc.stonks" }')]).toEqual(["", ""])
})
