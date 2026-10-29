import { test, expect } from "bun:test"
import { existsSync, readFileSync, readdirSync } from "node:fs"
import { join } from "node:path"
import { load } from "./load.js"

// The rules read against Yahoo's and Robinhood's saved answers, which are
// private (test/fixtures; test/fixtures-dir.sh finds them). Without them it
// says why and exits 77, which test/unit.sh counts as a skip. The pure rules
// are model.test.js.
const found = Bun.spawnSync([join(import.meta.dir, "fixtures-dir.sh")])
// fixtures-dir.sh exits 1 for no saved answers; anything else is a failure.
if (found.exitCode === 1) {
  console.log(`SKIP saved.test.js: ${found.stderr.toString().trim()}`)
  process.exit(77)
}
if (!found.success) throw new Error(`fixtures-dir.sh failed (${found.exitCode}): ${found.stderr.toString().trim()}`)
const fixtures = found.stdout.toString().trim()
// The reader is in New York: an exchange's time is named
// with its zone only where that clock differs from the reader's.
process.env.TZ = "America/New_York"
// Every rule file's names, under one name: each is defined once.
const M = Object.assign({}, ...["Format", "Fetch", "Quote", "Market", "Overnight", "History", "Fundamentals", "Figures",
  "Chart", "Tones", "Settings", "KeySheet", "Search", "Cells"].map(name => load(name + ".js")))

const fixture = name => JSON.parse(readFileSync(join(fixtures, name), "utf8"))
const calendars = JSON.parse(readFileSync(join(import.meta.dir, "..", "calendars.json"), "utf8"))
const US = calendars.calendars.US
const JPX = calendars.calendars.JPX
// The exchanges that trade in whole cents from $1, as the feeds read with.
const cents = M.centExchanges(calendars)
// A listing's cadence and warmth, by its calendar's reading, as askDue
// reads them.
const calNow = (q, now) => M.calendarNow(M.calendarFor(calendars, q), now)
const staysWarm = (q, now) => M.staysWarm(q, now, calNow(q, now))
const quoteCadence = (q, now, interval, hero) => M.quoteCadence(q, now, interval, hero, calNow(q, now))
const quote = M.parseChart(fixture("aapl.json"))
const shop = M.parseChart(fixture("shop-to.json"))
const btc = M.parseChart(fixture("btc-usd-day.json"))
const search = fixture("search.json")
const reg = quote.session.regular
const DAY = 24 * 3600

// A quote with only the points inside the regular session, so it reads as
// "still trading" for tests that need a live market.
function duringSession(q) {
  return { ...q, points: M.regularPoints(q) }
}
test("parseChart keeps the fields the panel needs", () => {
  const fields = q => ({ symbol: q.symbol, currency: q.currency, exchange: q.exchange, timezoneName: q.timezoneName, instrumentType: q.instrumentType, crypto: q.crypto })
  expect(fields(quote)).toEqual({ symbol: "AAPL", currency: "USD", exchange: "NASDAQ", timezoneName: "America/New_York", instrumentType: "EQUITY", crypto: false })
  expect(fields(shop)).toEqual({ symbol: "SHOP.TO", currency: "CAD", exchange: "TSX", timezoneName: "America/Toronto", instrumentType: "EQUITY", crypto: false })
  expect(fields(btc)).toEqual({ symbol: "BTC-USD", currency: "USD", exchange: "CRYPTO", timezoneName: "UTC", instrumentType: "CRYPTOCURRENCY", crypto: true })
  // Names as the company writes them, as search takes them: Yahoo's short
  // name is in capitals for SHOP.TO and cut at 31 characters for SPY.
  expect(shop.name).toBe("Shopify Inc.")
  expect(M.parseChart(fixture("spy-2026-09-11-day-prepost.json")).name).toBe("State Street SPDR S&P 500 ETF Trust")
  expect(M.parseChart(fixture("nest-2026-09-11-day-prepost.json")).name).toBe("Nest Holdings Inc")
})

test("the listing line names a pair's currency once, and pence as pence", () => {
  // Yahoo names the pair with its currency: "BITCOIN USD · CRYPTO", not "· USD" again.
  expect(btc.name).toBe("Bitcoin USD")
  expect(M.listingMeta(btc)).toBe("CRYPTO")
  expect(M.listingMeta(quote)).toBe("NASDAQ · USD")
  expect(M.listingMeta(shop)).toBe("TSX · CAD")
  // London quotes in pence, which Yahoo calls GBp: in the hero's capitals,
  // or read fast, that is GBP, and 3,648.00 reads as pounds.
  const london = M.parseChart(fixture("shel-l-day.json"))
  expect(london.currency).toBe("GBp")
  expect(M.listingMeta(london)).toBe("LSE · PENCE")
  expect(M.currencyLabel("GBp")).toBe("PENCE")
})

test("a listing Yahoo names no currency for says its exchange alone, never USD", () => {
  const day = fixture("ftse-day.json")
  day.chart.result[0].meta.currency = null
  expect(M.listingMeta(M.parseChart(day))).toBe("FTSE INDEX")
})

test("parseChart drops a null close, even on the newest bar the stray filter never judges", () => {
  const json = fixture("aapl.json")
  const result = json.chart.result[0]
  const gone = quote.points[quote.points.length - 1].t
  result.indicators.quote[0].close[result.timestamp.indexOf(gone)] = null
  expect(M.parseChart(json).points.map(p => p.t)).toEqual(quote.points.map(p => p.t).filter(t => t !== gone))
})

test("across every saved intraday response the filter drops only those eleven bars", () => {
  const days = [
    ["aapl.json", []],
    ["aapl-2026-09-04-day-prepost.json", []],
    ["aapl-2026-09-04-day-regular.json", []],
    ["shop-to.json", []],
    // A continuous market gives the filter nothing to judge.
    ["btc-usd-day.json", []],
    ["nest-2026-09-11-day-prepost.json", [1789158000]],
    ["spy-2026-09-11-day-prepost.json", [1789156800]],
    ["msft-2026-09-11-day-prepost.json", [1789157100, 1789162200, 1789162500]],
    // BRK-B's after hours on Friday 2 October: 520.93, 489.66, 500.31, and
    // 489.66 between 502.80 and 502.65, 30, 5, 10, and 10 minutes apart.
    ["moments/listings-2026-10-03-1200/brk-b.json", [1790973900, 1790974200, 1790974800, 1790975400]],
    // JPM's after hours on Friday 16 October: 16:50 and 17:00 opened at
    // 339.83 and 339.52 and closed at 318.24, 16:55 missing, and 17:05
    // opened back at 339.50: left in, they end the sparkline in a spike.
    ["moments/power-user-2026-10-16/jpm.json", [1792183800, 1792184400]],
    // A cent or two under $2 is more than half a percent and still a trade:
    // PLUG's, AITX's at $0.0016 (a tick of 0.0001), and BOLT's 1.97 between
    // 1.98s all stay.
    ["moments/power-user-2026-10-16/plug.json", []],
    ["moments/power-user-2026-10-16/aitx.json", []],
    ["moments/listings-2026-10-07-1455/bolt.json", []],
    ["moments/listings-2026-10-08-1054/bolt.json", []]
  ]
  for (const [name, expected] of days) {
    const json = fixture(name)
    const result = json.chart.result[0]
    const parsed = M.parseChart(json, cents)
    const kept = parsed.points.map(point => point.t)
    const dropped = result.timestamp.filter((t, i) =>
      result.indicators.quote[0].close[i] !== null && kept.indexOf(t) < 0)
    expect([name, dropped]).toEqual([name, expected])
    expect([name, parsed.droppedTimes]).toEqual([name, expected])
  }
  // MSFT at 17:30 and 17:35 ET printed 515.03 then 510.62 between 495.40 and
  // 495.01. The second opens where the first closed, so no single bar breaks
  // continuity; 17:40 opening at 495.20 gives the pair away. At 16:05 the
  // same shape sits one bucket after the bell, only 0.62% wide. The
  // neighbours stay.
  const msft = M.parseChart(fixture("msft-2026-09-11-day-prepost.json"))
  expect(msft.points.filter(p => [1789157400, 1789161900, 1789162800].indexOf(p.t) >= 0).map(p => p.p))
    .toEqual([495.3218, 495.4, 495.0108])
  // REED's after hours on Thursday 1 October: 21.63 at 18:25 and 21.30 at
  // 18:40 after 21.50 at 18:20, and the bar after opens back at 21.50: a thin
  // stock's own trades, BRK-B's shape two bars long. A mixed run is three.
  const reed = M.parseChart(fixture("moments/night/reed.json"))
  expect(reed.points.filter(p => p.t === 1790893500 || p.t === 1790894400).map(p => p.p)).toEqual([21.63, 21.3])
  // A real move across a gap stays: TOY rose from 325.33 at 09:10 on Monday
  // 5 October to 327.38, 327.90, and, 09:25 missing, 328.43 at 09:30, and
  // 09:35 opened back near 325. The bar after the gap opened from 327.90,
  // where the move had got to, so the gap is not bridged.
  const toy = M.parseChart(fixture("moments/live-2026-10-05/toy.json"))
  expect(toy.points.filter(p => p.t >= 1790946900 && p.t <= 1790947800).map(p => p.t))
    .toEqual([1790946900, 1790947200, 1790947800])
})

test("a bar with shares traded in it is a trade, never stray", () => {
  // TOY's climb into Friday 2 October's close, 15:50 and 15:55 on 38,404 and
  // 121,968 shares, opened back from at 16:05 by an after-hours print: taken
  // for strays, the line would end the session 3.54 under the last trade.
  const toy = M.parseChart(fixture("moments/live-2026-10-05/toy.json"))
  const close = M.epochAt(US, "2026-10-02", "15:50")
  expect(toy.points.filter(p => p.t === close || p.t === close + 300).map(p => p.p)).toEqual([320.0400085449219, 320.8299865722656])
  // From that close, 320.77 at 16:00, Yahoo's 317.05 at 16:05 and 318.57 at
  // 16:10, no shares, the bar after each opening back at 320.77, are strays:
  // Robinhood's tape of those minutes has no trade until 319.80 at 16:25, its
  // price held at 320.77.
  expect(toy.droppedTimes).toEqual([close + 900, close + 1200])
})

test("a young listing's ranges start at its first trade and keep its thin trades, and agree on its high and low", () => {
  // WREN, first traded Friday 16 October: Yahoo's 1W and 1M open with its
  // 18.00 offer at 09:30, no shares traded, its first trade 23.00 at 11:45.
  // 1W must not say "18.00 23.00", nor drop the week's 23.875 high on
  // 257,049 shares among 11 bars as strays; nor 1M "18.00 23.88", nor 3M
  // and the 52-week line "19.75 23.88".
  const set = "moments/premarket-2026-10-23-0622/"
  const quote = M.parseChart(fixture(set + "wren.json"), cents)
  expect(M.yearLine(quote).range).toMatchObject({ lowText: "19.75", highText: "23.88" })
  for (const [file, range] of [["wren-1w", "1W"], ["wren-1m", "1M"], ["wren-3m", "3M"]]) {
    const history = M.parseHistory(fixture(set + file + ".json"), range, cents)
    const ends = M.rangeEnds(history, M.periodStats(history), quote)
    expect([range, M.rangeLine(history, ends, quote).range]).toMatchObject([range, { lowText: "19.75", highText: "23.88" }])
    expect([range, history.droppedTimes, history.bars.some(b => b.l === 18)]).toEqual([range, [], false])
    expect([range, M.historyRowModel(history, quote, 0).periodLabel]).toEqual([range, "SINCE 16 OCT 2026"])
  }
})

test("a day with no bar says nothing against the trade its quote holds", () => {
  // WREN at 09:37 on Friday 23 October: Yahoo's quote is its 09:30 trade,
  // 20.62 on 366 shares, and its day has no bar: no "No trades charted"
  // under "1D 20.62 20.62 VOL 366".
  const wren = M.parseChart(fixture("moments/bell-2026-10-23-0937/wren.json"), cents)
  expect([wren.points.length, wren.price, wren.volume]).toEqual([0, 20.62, 366])
  expect(M.dayNote(wren, M.epochAt(US, "2026-10-23", "09:37"), calendars)).toBe("")
  // CVR untraded on Friday 16 October, its quote Wednesday's, still says so.
  const cvr = M.parseChart(fixture("moments/power-user-2026-10-16/cvr.json"), cents)
  expect(M.dayNote(cvr, M.epochAt(US, "2026-10-16", "14:09"), calendars)).toBe("No trades charted")
})

test("the headline uses the regular quote or labels the last chart trade with its time", () => {
  expect(M.headlineQuote(quote)).toEqual({ price: quote.price, t: quote.marketTime, source: "quote" })
  expect(M.regularClose(quote)).toBe(quote.price)
  const regular = M.regularPoints(quote)
  const noMeta = { ...quote, price: null }
  expect(M.headlineQuote(noMeta)).toEqual({ price: regular[regular.length - 1].p, t: regular[regular.length - 1].t, source: "chart" })
  const noTime = { ...quote, marketTime: null }
  expect(M.headlineQuote(noTime)).toEqual({ price: quote.price, t: null, source: "quote" })
  const untimed = M.freshness({ status: "ok" }, noTime, quote.marketTime, 0)
  expect(untimed.asOf).toBeNull()
  expect(untimed.live).toBe(false)
  expect(M.freshnessText(untimed, noTime, calendars)).toBe("TIME NOT SENT")
  expect(M.freshnessText({ ...untimed, state: "saved" }, noTime, calendars)).toBe("SAVED · TIME NOT SENT")
  expect(M.freshnessText({ ...untimed, state: "failed" }, noTime, calendars)).toBe("REFRESH FAILED · TIME NOT SENT")
  expect(M.freshnessText({ ...untimed, state: "overdue" }, noTime, calendars)).toBe("UPDATE OVERDUE · TIME NOT SENT")
  const nothing = { ...quote, price: null, points: [] }
  expect(M.headlineQuote(nothing)).toBeNull()
  expect(M.regularClose(nothing)).toBeNull()
  // A constructed omission, not a claim that this capture lacked metadata.
  const night = M.parseChart(fixture("moments/listings-2026-10-07-0100/nest.json"))
  const now = Date.UTC(2026, 9, 7, 5) / 1000
  for (const omitted of [{ price: null }, { price: null, marketTime: null }]) {
    const fallback = { ...night, ...omitted }
    const fresh = M.freshness({ status: "ok" }, fallback, now, 0)
    expect(M.headlineQuote(fallback)).toEqual({ price: 249.77999877929688, t: 1791316500, source: "chart" })
    expect(M.freshnessText(fresh, fallback, calendars)).toBe("LAST TRADE · TUE 15:55")
    expect(M.freshnessWarns(fresh)).toBe(false)
    expect(M.freshnessText({ ...fresh, earlier: false }, fallback, calendars)).toBe("LAST TRADE · 15:55")
    expect(M.freshnessText({ ...fresh, state: "failed" }, fallback, calendars)).toBe("REFRESH FAILED · LAST TRADE · TUE 15:55")
    expect(M.freshnessText({ ...fresh, state: "overdue" }, fallback, calendars)).toBe("UPDATE OVERDUE · LAST TRADE · TUE 15:55")
  }
  expect(M.freshnessText(M.freshness({ status: "ok" }, night, now, 0), night, calendars)).toBe("")
})

const sep4 = M.parseChart(fixture("aapl-2026-09-04-day-prepost.json"))
const sep4Reg = sep4.session.regular

test("a bucket stamped at the bell is post-market, unless it holds the closing trade, and the quote a second later is the close", () => {
  const regular = M.regularPoints(sep4)
  expect(regular.length).toBe(78)
  expect(regular[regular.length - 1].t).toBe(sep4Reg.end - 300)
  const atBell = sep4.points.find(p => p.t === sep4Reg.end)
  expect(atBell).toBeDefined()
  expect(M.chartGeometry(sep4).points.find(p => p.x === M.chartGeometry(sep4).ticks[0]).ext).toBe(true)
  // The closing quote one second after the bell is still the regular quote,
  // not the bell bucket's 319.92.
  expect(M.headlineQuote(sep4)).toEqual({ price: 319.97, t: sep4Reg.end + 1, source: "quote" })
  // CVR on Monday 26 October traded twice: at 13:10 for 10.55, and its
  // close at 16:00 for 9.82, down 6.48% with a bear. The bell's bucket holds
  // that closing trade, so the dot sits on it, below the dashed line, the
  // line's bright part ends there, and a scrub there reads the close.
  const cvr = M.viewChart("CVR", "1D", { CVR: savedDay("watch-2026-10-26-1800", "cvr") }, {}, {}, {},
    { CVR: { status: "ok", allDay: false, at: 0 } }, calendars).day
  const geometry = M.chartGeometry(cvr)
  const dot = M.lastRegularPoint(geometry)
  expect([geometry.points.length, geometry.points.indexOf(dot), dot.y > geometry.baselineY]).toEqual([2, 1, true])
  const rest = M.rowModel(cvr, 0, "pct")
  expect([rest.priceText, rest.changeText, M.animalKind(rest)]).toEqual(["9.82", "\u22126.48%", "bear"])
  const scrub = M.rowModel(cvr, cvr.points[1].t, "pct")
  expect([scrub.priceText, M.animalKind(scrub)]).toEqual(["9.82", "bear"])
  expect(M.marketStatus(cvr, at("2026-10-26", "18:00"), cvr.points[1].t, calendars)).toBe("At 16:00 · Closing bell")
  // The trade at 13:10 reads its own price, not the close.
  expect(M.rowModel(cvr, cvr.points[0].t, "pct").priceText).toBe("10.55")
})

test("after the close, the session's last print reads the close at the bell, and the bucket after it reads itself", () => {
  // London on Wednesday 7 October, fetched 14:55 New York: its last regular
  // bucket is 16:25 at 3,646.50, its close 3,648.00 stamped 17:20:32 BST,
  // after its 16:30 and 16:35 buckets.
  const london = M.parseChart(fixture("moments/listings-2026-10-07-1455/shel.l.json"))
  const bell = london.session.regular.end
  expect(london.marketTime).toBeGreaterThan(bell)
  expect(M.readingAt(london, bell - 300)).toEqual({ price: 3648, t: bell, close: true })
  expect(M.marketStatus(london, at("2026-10-07", "14:55"), bell - 300, calendars)).toBe("At 16:30 BST · Closing bell")
  expect(M.readingAt(london, bell)).toEqual({ price: 3657, t: bell, close: false })
})

test("a scrub reads the print at or before it, from the day's first print through Tokyo's lunch to its last", () => {
  // Toyota on Wednesday 7 October, its whole day: 30 morning prints, the
  // last 11:30's at 2,915, then none until 12:30's at 2,917, and the day
  // closing at 2,900.50 at 15:30, after its last print, 15:20's.
  const toyota = M.parseChart(fixture("overnight/sweep-2026-10-07-1455/7203.t.json"))
  const pts = toyota.points
  const read = t => M.readingAt(toyota, t)
  const reopen = pts.findIndex((p, i) => i > 0 && p.t - pts[i - 1].t > 1800)
  expect([pts.length, reopen, pts[reopen - 1].p, pts[reopen].p]).toEqual([65, 30, 2915, 2917])
  expect(read(pts[0].t - 60)).toEqual({ price: 2930.5, t: pts[0].t - 60, close: false })
  expect(read(pts[0].t)).toEqual({ price: 2939.5, t: pts[0].t, close: false })
  expect(read(pts[3].t + 30)).toEqual({ price: 2927.5, t: pts[3].t + 30, close: false })
  expect(read(pts[reopen].t - 1800).price).toBe(2915)
  expect(read(pts[reopen].t).price).toBe(2917)
  expect(read(pts[pts.length - 1].t)).toEqual({ price: 2900.5, t: toyota.session.regular.end, close: true })
})

test("a scrub inside Tokyo's lunch draws no dot, as the line and the chimes leave it; either side of it the dot is on the line", () => {
  const toyota = M.parseChart(fixture("overnight/sweep-2026-10-07-1455/7203.t.json"))
  const pts = M.chartGeometry(toyota, calendars).points
  const reopen = pts.findIndex(p => p.brk)
  const [morning, afternoon] = [pts[reopen - 1], pts[reopen]]
  const chime = load("ChartSound.js").lineBars({ points: pts })
  const inside = [0.01, 0.5, 0.99].map(f => morning.x + (afternoon.x - morning.x) * f)
  expect(inside.map(x => [M.yAt(pts, x), chime(x)])).toEqual(inside.map(() => [null, -1]))
  expect([M.yAt(pts, morning.x), M.yAt(pts, afternoon.x)]).toEqual([morning.y, afternoon.y])
  const beforeLunch = (pts[reopen - 2].x + morning.x) / 2
  expect(M.yAt(pts, beforeLunch)).toBeCloseTo((pts[reopen - 2].y + morning.y) / 2, 9)
})

// Smooth's replay of `day`, from its first print to its last over 2 s, as a
// surface plays it (ChartMotion's `replay`), heard against the line drawn:
// where each bar's fundamental rises (its amplitude over 40 ms, every 4 ms,
// up a twelfth of the loudest's against 40 ms before), each bar's own, so
// bars struck together are each heard. `wrong` holds the strikes of a bar
// the line didn't have in the 80 ms before or the 20 ms after, as the
// strikes' 45 ms spacing and the window allow; `unstruck` the moves onto a
// bar the line then holds 45 ms or more not heard as that bar's strike;
// `inBreak` the strikes that start where the line lifts.
function smoothHeard(day) {
  const sound = load("ChartSound.js")
  const geometry = M.chartGeometry(day, calendars), pts = geometry.points
  const from = M.fractionAtTime(day, day.points[0].t), to = M.fractionAtTime(day, M.lastPrintTime(day))
  const s = sound.smooth(geometry, from, to, 2).samples, rate = sound.RATE, penta = sound.PENTATONIC
  const place = t => sound.placeAt(t, from, to, 2)
  // The line's height at `x`, null where it lifts (`brk`).
  const lineY = x => {
    if (x <= pts[0].x) return pts[0].y
    const k = pts.findIndex((p, i) => i > 0 && p.x >= x)
    if (k < 0) return pts.at(-1).y
    const [a, b] = [pts[k - 1], pts[k]]
    if (b.brk && x > a.x && x < b.x) return null
    return a.y + (b.y - a.y) * (x - a.x) / Math.max(1e-9, b.x - a.x)
  }
  const barAt = t => {
    if (t > 2) return -2
    const y = lineY(place(t))
    return y === null ? -1 : Math.round((1 - Math.max(0, Math.min(1, y))) * (penta.length - 1))
  }
  const span = 960, hop = 96, amp = penta.map(() => []), coef = penta.map(f => 2 * Math.cos(2 * Math.PI * f / rate))
  let top = 0
  for (let at = 0; at + span < s.length; at += hop) {
    penta.forEach((_, b) => {
      let q1 = 0, q2 = 0
      for (let k = 0; k < span; k++) {
        const q0 = coef[b] * q1 - q2 + s[at + k] * (0.5 - 0.5 * Math.cos(2 * Math.PI * k / span))
        q2 = q1; q1 = q0
      }
      const a = Math.sqrt(Math.max(0, q1 * q1 + q2 * q2 - coef[b] * q1 * q2))
      amp[b].push(a)
      top = Math.max(top, a)
    })
  }
  // A rise under half the window's greatest is another bar heard through
  // it, and one bar's rises within 40 ms of its strike are that strike.
  const strikes = [], lastOf = []
  for (let w = 0; w < amp[0].length; w++) {
    const rises = penta.map((_, c) => (amp[c][w] - (w >= 10 ? amp[c][w - 10] : 0)) / top)
    const most = Math.max(...rises), t = (w * hop + span / 2) / rate
    rises.forEach((rise, c) => {
      if (rise <= 0.08 || rise < most / 2 || (lastOf[c] !== undefined && t - lastOf[c] <= 0.04)) return
      lastOf[c] = t
      strikes.push({ t, bar: c })
    })
  }
  strikes.sort((a, b) => a.t - b.t)
  const around = (t, before, after) => {
    const bars = []
    for (let u = t - before; u <= t + after; u += 0.002) bars.push(barAt(u))
    return bars
  }
  const inBreak = strikes.filter(st => around(st.t, 0.025, 0.02).every(b => b === -1))
  const wrong = strikes.filter(st => !inBreak.includes(st) && !around(st.t, 0.08, 0.02).includes(st.bar))
  const runs = []
  for (let v = 0; v <= 2; v += 0.002) {
    const held = barAt(v), run = runs.at(-1)
    if (!run || run.bar !== held) runs.push({ bar: held, from: v, to: v })
    else run.to = v
  }
  // Heard from 20 ms before the move to 65 ms after: the gap's 45 ms and
  // the window's give.
  const moves = runs.filter(r => r.bar >= 0 && r.to - r.from >= 0.045)
  const unstruck = moves.filter(r => !strikes.some(st => st.bar === r.bar && st.t >= r.from - 0.02 && st.t <= r.from + 0.065))
  const breakMs = runs.filter(r => r.bar === -1).reduce((sum, r) => sum + (r.to - r.from) * 1000, 0)
  return { geometry, place, strikes, wrong, moves, unstruck, inBreak, breakMs }
}

// Nine strikes in ten are the bar under the line, and nine of ten held
// moves are struck.
const followsLine = heard => {
  expect(heard.strikes.length).toBeGreaterThanOrEqual(5)
  expect(heard.wrong.length).toBeLessThanOrEqual(heard.strikes.length * 0.1)
  expect(heard.unstruck.length).toBeLessThanOrEqual(heard.moves.length * 0.1)
}

test("smooth's replay strikes the scrub's chimes: the bar under the line as the replay moves along it", () => {
  followsLine(smoothHeard(quote))
})

test("smooth's replay of Tokyo's day strikes no bar across lunch, where the chart draws nothing, and the bar under the line either side", () => {
  // Toyota on Monday 19 October, its line stopping for lunch below the
  // close and starting again above it.
  const heard = smoothHeard(savedDay("demo-2026-10-19-1146", "7203.t"))
  expect(heard.breakMs).toBeGreaterThan(100)
  expect(heard.inBreak).toEqual([])
  followsLine(heard)
})

test("smooth's replay of a thin night follows the line through its trades", () => {
  // TOY at 00:36 on Monday 5 October: Sunday night's five trades, a line
  // through them where the clock puts each.
  const heard = smoothHeard(dayAt("live-2026-10-05", "toy").day)
  const trades = heard.geometry.points
  expect([trades.length, trades.some(p => p.brk)]).toEqual([5, false])
  followsLine(heard)
})

test("the day is drawn whole, and its range holds the previous close", () => {
  const spy = M.parseChart(fixture("spy-2026-09-11-day-prepost.json"))
  const spyReg = spy.session.regular
  const geo = M.chartGeometry(spy)
  expect(geo.start).toBe(spy.points[0].t)
  expect(geo.start).toBeLessThan(spyReg.start)
  expect(geo.points[0].ext).toBe(true)
  expect(geo.points[0].x).toBe(0)
  expect(geo.points.filter(p => !p.ext).length).toBe(78)
  expect(geo.points.filter(p => p.ext).length).toBe(109)
  // The last regular print is the 15:55 bucket, one five-minute step before
  // the bell tick.
  expect(geo.ticks[0] - M.lastRegularPoint(geo).x).toBeCloseTo(300 / (geo.end - geo.start), 10)
  // SPY gapped up on 11 September: the session traded 763.97 to 766.31, more
  // than six points above the 757.83 previous close, and only the pre-market
  // climbs between them: the session alone would leave the line in the top
  // fifth over an empty chart.
  expect(geo.lo).toBeLessThan(757.83)
  expect(geo.hi).toBeGreaterThan(766.31)
  const lowest = Math.max(...geo.points.map(p => p.y))
  const highest = Math.min(...geo.points.map(p => p.y))
  expect(lowest - highest).toBeGreaterThan(0.5)
  expect(geo.baselineY).toBeGreaterThan(lowest)
  // While the session trades, the axis ends at the bell, and time and
  // position map onto each other; before the axis there is no cursor.
  const live = duringSession(quote)
  expect(M.chartGeometry(live)).toMatchObject({ ticks: [], end: reg.end })
  expect(M.timeAtFraction(live, 0)).toBe(reg.start)
  expect(M.timeAtFraction(live, 1)).toBe(reg.end)
  expect(M.fractionAtTime(live, reg.start + 3.25 * 3600)).toBeCloseTo(0.5, 5)
  expect(M.fractionAtTime(live, reg.start - 60)).toBe(-1)
  expect(M.lastRegularPoint(null)).toBeNull()
})

test("sessionPhase follows the bells the exchange announced", () => {
  // The periods are trusted: an empty series does not make a holiday.
  const q = { ...quote, points: [] }
  expect(M.sessionPhase(q, q.session.pre.start + 60)).toBe("pre")
  expect(M.sessionPhase(q, reg.start + 60)).toBe("opening")
  expect(M.sessionPhase(q, reg.start + 2 * 3600)).toBe("open")
  expect(M.sessionPhase(q, reg.start + 2.75 * 3600)).toBe("lunch")
  expect(M.sessionPhase(q, reg.end - 30 * 60)).toBe("power")
  expect(M.sessionPhase(q, reg.end - 60)).toBe("closing")
  expect(M.sessionPhase(q, q.session.post.start + 60)).toBe("post")
  expect(M.sessionPhase(q, q.session.post.end + 3600)).toBe("closed")
  expect(M.sessionPhase(q, reg.start + 5 * DAY)).toBe("weekend")
  // The lunch lull is a New York thing.
  expect(M.sessionPhase({ ...q, timezoneName: "Europe/London" }, reg.start + 2.75 * 3600)).toBe("open")
})

// Saudi's exchange trades Sunday to Thursday, 10:00 to 15:00 at UTC+3. No
// saved answer is from one, so Toyota's day is moved to Sunday 25 October's
// session there, priced to 11:45.
test("a session on a Sunday trades, and its evening is closed, not the weekend", () => {
  const json = fixture("7203-t-day.json")
  const r = json.chart.result[0]
  const sunday = Date.UTC(2026, 9, 25) / 1000
  const start = sunday + 7 * 3600, end = sunday + 12 * 3600, noon = sunday + 9 * 3600
  const shift = start - r.meta.currentTradingPeriod.regular.start
  r.timestamp = r.timestamp.map(t => t + shift).filter(t => t <= noon - 900)
  for (const k of Object.keys(r.indicators.quote[0])) r.indicators.quote[0][k] = r.indicators.quote[0][k].slice(0, r.timestamp.length)
  const p = { timezone: "AST", gmtoffset: 10800 }
  const periods = { pre: { ...p, start, end: start }, regular: { ...p, start, end }, post: { ...p, start: end, end } }
  Object.assign(r.meta, { symbol: "2222.SR", exchangeName: "SAU", timezone: "AST", exchangeTimezoneName: "Asia/Riyadh",
    gmtoffset: 10800, currency: "SAR", regularMarketTime: noon - 900, currentTradingPeriod: periods,
    tradingPeriods: { pre: [[periods.pre]], regular: [[periods.regular]], post: [[periods.post]] } })
  const q = M.parseChart(json, cents, noon)
  // At noon its price is 15 minutes old: asked for each minute, kept fresh
  // with nothing open, and its age said.
  expect(M.sessionPhase(q, noon)).toBe("open")
  expect(quoteCadence(q, noon, 60, false)).toBe(60)
  expect(staysWarm(q, noon)).toBe(true)
  expect(M.freshness({ status: "ok", answeredAt: noon - 5 }, q, noon, 0, false)).toMatchObject({ state: "aged" })
  // The Saturday before is the weekend; Sunday after the bell is closed.
  expect(M.sessionPhase(q, start - DAY)).toBe("weekend")
  expect(M.sessionPhase(q, end + 3600)).toBe("closed")
})

test("crypto is always open, never sees a weekend, reads its last 24 hours everywhere, and still reports quote age", () => {
  const t = btc.session.regular.start + 3600
  expect(M.sessionPhase(btc, t)).toBe("always")
  expect(M.sessionPhase(btc, t + 5 * DAY)).toBe("always")
  expect(M.marketStatus(btc, t, 0, calendars)).toBe("Open around the clock")
  const ok = { status: "ok", receivedAt: t - 5 }
  expect(M.freshness(ok, { ...btc, marketTime: t - 10 }, t, 0)).toMatchObject({ state: "fresh", live: true })
  expect(M.freshness(ok, { ...btc, marketTime: t - 500 }, t, 0)).toMatchObject({ state: "aged", live: false })
  // Bitcoin's two-day answer at 13:22 New York on 28 October: its day is the
  // last 24 hours, from the price 24 hours before the newest, not Yahoo's
  // UTC day, which restarts at 20:00 New York with one print. The move
  // beside the price, a row's and the pill's, the dashed line, the day's
  // open, low and high all read those 24 hours; the chart fills the width,
  // the dot on the newest print.
  const raw = fixture("moments/coin-2026-10-28-1322/btc-usd.json").chart.result[0]
  const q = raw.indicators.quote[0]
  const bars = raw.timestamp.map((t, i) => ({ t, p: q.close[i], h: q.high[i], l: q.low[i] })).filter(b => b.p !== null)
  const ago = bars.filter(b => b.t <= bars.at(-1).t - DAY).at(-1)
  const coin = M.parseChart({ chart: { result: [raw] } }, cents)
  // Its low and high are its bars' since then, which a close can miss.
  const since = bars.filter(b => b.t > ago.t)
  const low = Math.min(ago.p, ...since.map(b => b.l))
  const high = Math.max(ago.p, ...since.map(b => b.h))
  expect([coin.points[0].t, coin.points.at(-1).t, coin.prevClose, coin.dayOpen, coin.dayLow, coin.dayHigh])
    .toEqual([ago.t, bars.at(-1).t, ago.p, ago.p, low, high])
  expect(low < Math.min(...since.map(b => b.p)) || high > Math.max(...since.map(b => b.p))).toBe(true)
  expect(ago.t).toBeLessThan(Date.UTC(2026, 9, 28) / 1000)
  const row = M.rowModel(coin, 0, "pct")
  expect([row.changeText, row.periodLabel, M.dayTitle(coin, M.exchangeDay(coin, coin.marketTime))])
    .toEqual([M.pct((coin.price - ago.p) / ago.p * 100), "24H", "24H"])
  const line = M.chartGeometry(coin)
  expect([M.dayBase(coin), line.points[0].x, line.points.at(-1).x, M.lastRegularPoint(line)]).toEqual([ago.p, 0, 1, line.points.at(-1)])
  // An answer that doesn't reach back 24 hours, a one-day answer, has no
  // price 24 hours ago: its quote stays Yahoo's UTC day, titled as a day.
  expect([btc.rolling, btc.prevClose, M.dayTitle(btc, M.exchangeDay(btc, btc.marketTime))])
    .toEqual([undefined, fixture("btc-usd-day.json").chart.result[0].meta.chartPreviousClose, "1D"])
})

test("after the close the header names the day and the next open from the calendar", () => {
  // Saturday 5 September 2026 with Friday's response: the countdown must not
  // go to Monday 7 September, which Nasdaq closed for Labor Day.
  const saturday = 1788582233
  const short = JSON.parse(JSON.stringify(calendars))
  short.calendars.US.validThrough = "2026-09-06"
  const rows = [
    // Friday evening: the regular close is named so 16:00 is not read as the
    // end of trading, then the post-market ends.
    [sep4.session.post.start + 1800, calendars, "After hours · closed at 16:00"],
    [sep4.session.post.end + 60, calendars, "Closed · opens Tue 09:30"],
    [saturday, calendars, "Weekend · opens Tue 09:30"],
    [1788793200, calendars, "Labor Day · opens Tue 09:30"],
    // Standard time, and a closure that keeps its opens verb.
    [M.epochAt(US, "2026-11-26", "12:00"), calendars, "Thanksgiving Day · opens Fri 09:30"],
    [M.epochAt(US, "2027-06-18", "12:00"), calendars, "Juneteenth · opens Mon 09:30"],
    // Past validThrough the schedule is unknown, and the header says so.
    [saturday, short, "Weekend · schedule unavailable"]
  ]
  for (const [now, cals, expected] of rows) expect([now, M.marketStatus(sep4, now, 0, cals)]).toEqual([now, expected])
})

// The readers every exchange's clock is pinned for, and an answer as Yahoo
// sends it once the exchange's clocks have changed: its `gmtoffset` and
// zone are the new ones, and each period keeps its own day's.
const READERS = ["America/New_York", "Europe/London", "Asia/Tokyo", "Asia/Kolkata"]
const readAs = (zone, fn) => {
  process.env.TZ = zone
  try { return fn() } finally { process.env.TZ = "America/New_York" }
}
const sentAt = (json, gmtoffset, timezone) => {
  const copy = structuredClone(json)
  Object.assign(copy.chart.result[0].meta, { gmtoffset, timezone })
  return copy
}

test("the popular indexes Yahoo files under their own codes keep their exchange's hours", () => {
  // ^N225 under Osaka, ^FTSE under FTSE Index, ^RUT under Chicago Options,
  // and the TSX Composite under Toronto: through Tokyo's lunch the Nikkei
  // must not say "Market closes in 3h 30m" nor be asked every minute, and
  // after each close each says when it opens.
  const n225 = M.parseChart(fixture("first-day-2026-10-14/n225-day.json"))
  const lunch = n225.session.regular.start + 2.75 * 3600
  expect(M.marketStatus(n225, lunch, 0, calendars)).toBe("Lunch break · reopens 12:30 JST · in 45m")
  expect(quoteCadence(n225, lunch, 60, false)).toBe(15 * 60)
  const closed = q => M.marketStatus(q, q.session.regular.end + 4 * 3600, 0, calendars)
  expect(closed(n225)).toBe("Closed · opens Thu 09:00 JST")
  const ftse = M.parseChart(fixture("ftse-day.json"))
  expect(closed(ftse)).toBe("Closed · opens Wed 08:00 BST")
  expect(closed(M.parseChart(fixture("rut-day.json")))).toBe("Closed · opens Wed 09:30")
  expect(closed(M.parseChart(fixture("gsptse-day.json")))).toBe("Closed · opens Wed 09:30")
  // ^VIX keeps Chicago's hours, which no calendar has; FTSE's global
  // indexes, filed under FTSE Index too, are calculated while any of their
  // markets trade, not on London's days.
  expect(closed(M.parseChart(fixture("vix-day.json")))).toBe("Closed")
  expect(closed({ ...ftse, symbol: "GEISAC.FGI" })).toBe("Closed")
})

test("an exchange's time names its zone only where the reader's clock differs", () => {
  const tokyo = M.parseChart(fixture("7203-t-day.json"))
  const evening = tokyo.session.regular.end + 3 * 3600
  const aapl = M.parseChart(fixture("aapl.json"))
  // Saturday 31 October: New York's clocks go back that night.
  const saturday = M.epochAt(US, "2026-10-31", "12:00")
  const tokyoNext = () => M.marketStatus(tokyo, evening, 0, calendars)
  expect(readAs("America/New_York", tokyoNext)).toMatch(/^Closed · opens \w{3} 09:00 JST$/)
  expect(readAs("Asia/Tokyo", tokyoNext)).toMatch(/^Closed · opens \w{3} 09:00$/)
  // Nasdaq's Monday open, after the clocks change: nothing to name in New
  // York or Toronto; London, already on GMT, is told it is EST.
  const usNext = () => M.marketStatus(aapl, saturday, 0, calendars)
  expect(readAs("America/New_York", usNext)).toBe("Weekend · opens Mon 09:30")
  expect(readAs("America/Toronto", usNext)).toBe("Weekend · opens Mon 09:30")
  expect(readAs("Europe/London", usNext)).toBe("Weekend · opens Mon 09:30 EST")
  // A listing with no calendar names its zone as Yahoo does; "AS OF" too.
  const btc = M.parseChart(fixture("btc-usd-day.json"))
  expect(M.freshnessText({ state: "aged", asOf: btc.marketTime }, btc)).toBe("AS OF 18:32 UTC")
})

test("an exchange's time across a change of clocks reads by its own day's clock, for every reader", () => {
  // A listing with a calendar: an answer fetched after New York's clocks go
  // back (EST) holds a close from before (EDT): 09:30 reads 09:30, not
  // 08:30 EST.
  const aapl = { ...M.parseChart(fixture("aapl.json")), gmtoffset: -18000, zoneName: "EST" }
  const close = at("2026-10-30", "16:00")
  // Sydney's clocks went forward on 4 October: today's 1M answer is sent in
  // AEDT, and its periods keep each day's own, so the 10:00 AEST open of 21
  // September reads 10:00, not 11:00 AEDT.
  const bhp = M.parseHistory(fixture("history/bhp-ax-1mo.json"), "1M")
  // Ranges, a day, and closes fetched before 25 October (XETRA, Madrid) and
  // 1 November (Nasdaq, Chicago, OTC), each also as Yahoo sends it after.
  // Madrid's close is stamped 17:35:26, past its periods' end at 17:30.
  const nest = fixture("history/nest-1mo.json")
  const sap = fixture("history/sap-de-5d.json")
  const vix = fixture("vix-day.json")
  const aitx = fixture("moments/power-user-2026-10-16/aitx.json")
  const day = fixture("aapl.json")
  const iag = fixture("moments/cents-2026-10-17/iag.mc.json")
  const sides = [[nest, sentAt(nest, -18000, "EST")], [sap, sentAt(sap, 3600, "CET")],
    [vix, sentAt(vix, -21600, "CST")], [aitx, sentAt(aitx, -18000, "EST")], [day, sentAt(day, -18000, "EST")],
    [iag, sentAt(iag, 3600, "CET")]]
  for (const reader of READERS) readAs(reader, () => {
    // New York's own clock is named only to the other readers.
    const edt = reader === "America/New_York" ? "" : " EDT"
    expect(M.freshnessText({ state: "aged", asOf: close }, aapl, calendars)).toBe("AS OF 16:00" + edt)
    expect(M.historyScrubForms(bhp, bhp.bars[0])[0]).toBe("21 SEP 10:00 AEST · 60.56")
    expect(M.historyScrubForms(bhp, bhp.bars[bhp.bars.length - 2])[0]).toBe("20 OCT 16:00 AEDT · 59.50")
    for (const [n, s, v, a, d, m] of [sides.map(side => side[0]), sides.map(side => side[1])]) {
      const month = M.parseHistory(n, "1M")
      const week = M.parseHistory(s, "1W")
      const chicago = M.parseChart(v)
      const otc = M.parseChart(a)
      const nasdaq = M.parseChart(d)
      expect(M.historyScrubForms(month, month.bars[0])[0]).toBe("12 AUG 09:30" + edt + " · 233.17")
      expect(M.historyScrubForms(week, week.bars[0])[0]).toBe("14 OCT 09:00 CEST · 196.32")
      expect(M.freshnessText({ state: "aged", asOf: chicago.marketTime, earlier: true }, chicago, calendars)).toBe("AS OF TUE 09:35 CDT")
      expect(M.freshnessText({ state: "aged", asOf: otc.marketTime, earlier: true }, otc, calendars)).toBe("AS OF FRI 16:00" + edt)
      const madrid = M.parseChart(m)
      expect(M.freshnessText({ state: "aged", asOf: madrid.marketTime, earlier: true }, madrid, calendars)).toBe("AS OF FRI 17:35 CEST")
      // The day's lunch lull is New York's noon, whichever clock the
      // answer was sent by.
      const noon = nasdaq.session.regular.start + 2.5 * 3600
      expect(M.marketStatus(nasdaq, nasdaq.session.post.end, noon, calendars)).toBe("At 12:00" + edt + " · Lunch lull")
    }
  })
})

test("a weeknight after post-market leads with closed and the next open", () => {
  const q = {
    ...duringSession(quote),
    session: {
      pre: { start: M.epochAt(US, "2026-09-17", "04:00"), end: M.epochAt(US, "2026-09-17", "09:30") },
      regular: { start: M.epochAt(US, "2026-09-17", "09:30"), end: M.epochAt(US, "2026-09-17", "16:00") },
      post: { start: M.epochAt(US, "2026-09-17", "16:00"), end: M.epochAt(US, "2026-09-17", "20:00") }
    },
    points: [
      { t: M.epochAt(US, "2026-09-17", "04:00"), p: quote.prevClose },
      { t: M.epochAt(US, "2026-09-17", "15:55"), p: quote.price },
      { t: M.epochAt(US, "2026-09-17", "19:55"), p: quote.price + 1 }
    ]
  }
  const nextPre = M.epochAt(US, "2026-09-18", "04:00")
  for (const clock of ["20:01", "23:59"]) {
    const now = M.epochAt(US, "2026-09-17", clock)
    expect(M.marketStatus(q, now, 0, calendars)).toBe("Closed · opens Fri 09:30")
  }
  for (const clock of ["00:01", "03:59"]) {
    const now = M.epochAt(US, "2026-09-18", clock)
    expect(M.marketStatus(q, now, 0, calendars)).toBe("Closed · opens Fri 09:30")
  }
  expect(M.marketStatus(q, nextPre, 0, calendars)).toBe("Closed · opens Fri 09:30")
  const geometry = M.chartGeometry(q)
  expect(geometry.end).toBe(q.points[q.points.length - 1].t)
})

test("a listing's prices take the decimals they need, decided once from its headline price", () => {
  // On a market that trades in whole cents from $1 (the US), cents there,
  // or Yahoo's hint where coarser; elsewhere the hint. The hint at least
  // and four significant digits under 1; none from 10,000 up. The hints are
  // the real ones (SHIB-USD 5, DOGE-USD 5, AITX 4, LUMN 4, BRK-A 2).
  const shown = (price, hint, inCents) => M.money(price, M.priceDigits(price, hint, inCents))
  expect(shown(5.41e-6, 5)).toBe("0.000005410")
  // However small: a ten-decimal cap's 1.234e-11 is not 0.
  expect(shown(1.234e-11, 8)).toBe("0.00000000001234")
  expect(shown(0.08711, 5)).toBe("0.08711")
  expect(shown(0.5, 2)).toBe("0.5000")
  expect(shown(0.0016, 4)).toBe("0.001600")
  // Yahoo's hint of 4 under $5 read "4.6500" on the row and the hero; after
  // hours, PLUG's sub-penny 1.3891 reads in cents too.
  for (const [name, price] of [["lumn", "4.65"], ["plug", "1.38"]]) {
    const q = M.parseChart(fixture("moments/power-user-2026-10-16/" + name + ".json"), cents)
    expect([name, M.rowModel(q, 0, "pct").priceText]).toEqual([name, price])
  }
  expect(shown(1.3891, 4, true)).toBe("1.39")
  // Off the US a listing over $1 trades finer than a cent and keeps Yahoo's
  // hint, its tick too: XRP-USD at 1.3065 and IAG at 4.927 EUR in Madrid,
  // each with a hint of 4, read four decimals and move by 0.0001. In cents,
  // a coin's real moves would hide, and two cents of XRP would be 1.5% to
  // the stray filter.
  for (const [name, price] of [["xrp-usd", "1.3065"], ["iag.mc", "4.9270"]]) {
    const json = fixture("moments/cents-2026-10-17/" + name + ".json")
    const q = M.parseChart(json, cents)
    expect([name, M.rowModel(q, 0, "pct").priceText, M.answerTick(json.chart.result[0].meta, [], cents)]).toEqual([name, price, 0.0001])
  }
  expect(shown(235.62, 2)).toBe("235.62")
  expect(shown(759748.25, 2)).toBe("759,748")
  expect(shown(2900.5, undefined)).toBe("2,900.50")
  // A coin's day and every scrub of it are in the headline's decimals.
  const shib = M.parseChart(fixture("moments/listings-2026-10-08-1054/shib-usd.json"))
  expect(shib.priceDigits).toBe(9)
  expect(M.rowModel(shib, 0, "pct").priceText).toBe("0.000005410")
  expect(M.rowModel(shib, shib.points[3].t, "pct").priceText).toMatch(/^0\.00000\d{4}$/)
  // A move in money keeps cents where the price has none, and a coin's
  // decimals where it has more; its colour agrees with what is drawn.
  expect(M.signedMoney(-2105.766, 0)).toBe("\u22122,105.77")
  expect(M.changeText({ abs: -2e-8, pct: -0.37 }, "abs", 9)).toBe("\u22120.000000020")
  expect(M.changeTone({ abs: -2e-8, pct: -0.37 }, "abs", 9)).toBe("down")
  expect(M.changeTone({ abs: -2e-8, pct: -0.37 }, "abs")).toBe("flat")
})

test("rowModel shows the regular close at rest and the print under the finger", () => {
  const view = (t, mode, q = quote) => {
    const v = M.rowModel(q, t, mode)
    return { price: v.price, priceText: v.priceText, changeText: v.changeText, tone: v.tone, dayUp: v.dayUp }
  }
  // aapl.json ends on an after-hours print (324.72); at rest the row shows
  // the close, and the change mode moves only the change.
  const close = { price: 325.13, priceText: "325.13", tone: "up", dayUp: true }
  expect(view(0, "pct")).toEqual({ ...close, changeText: "+2.61%" })
  expect(view(0, "abs")).toEqual({ ...close, changeText: "+8.28" })
  // Since the open: from the OPEN the info line shows, 316.98.
  expect(view(0, "open")).toEqual({ ...close, changeText: "+2.57%" })
  // The rows carry the mode's word inline; the hero's SINCE OPEN caption is
  // pointer.qml's. Percent and amount carry none.
  expect(M.rowModel(quote, 0, "open")).toMatchObject({ changeLine: "+2.57% open", periodLabel: "SINCE OPEN" })
  expect(M.rowModel(quote, 0, "abs")).toMatchObject({ changeLine: "+8.28", periodLabel: "" })
  // Scrubbing reads the print at that moment and holds it until the next;
  // the direction is the moment's too, so the bull and bear follow a scrub.
  const mid = quote.points[40]
  const scrubbed = { price: 316.23, priceText: "316.23", changeText: "\u22120.20%", tone: "down", dayUp: false }
  expect(view(mid.t, "pct")).toEqual(scrubbed)
  expect(view(mid.t + 30, "pct")).toEqual(scrubbed)
  // Before the first print the row reads the previous close.
  expect(view(quote.points[0].t - 60, "pct")).toEqual({ price: 316.85, priceText: "316.85", changeText: "0.00%", tone: "flat", dayUp: true })
  // Open mode can turn the change down while the day is still up.
  const flip = {
    ...quote, prevClose: 100, price: 105, marketTime: reg.end - 30, dayOpen: 110,
    points: [{ t: reg.start + 60, p: 110 }, { t: reg.end - 60, p: 105 }]
  }
  expect(view(0, "open", flip)).toMatchObject({ price: 105, tone: "down", dayUp: true })
  // The pill's animal reads the day against its close in every mode.
  expect([M.animalKind(M.rowModel(flip, 0, "open")), M.animalKind(M.rowModel(flip, 0, "pct"))]).toEqual(["bull", "bull"])
  // With no data nothing is invented: no price, no change, no direction.
  const nothing = { ...quote, price: null, marketTime: null, points: [] }
  expect(view(0, "pct", nothing)).toMatchObject({ priceText: "—", changeText: "—", dayUp: null })
  expect(M.rowModel(nothing, 0, "open").changeLine).toBe("—")
  // The scrub has no last print to stop at, rather than failing.
  expect(M.lastPrintTime(nothing)).toBeNull()
  expect(M.rowModel(nothing, 0, "pct")).toMatchObject({ pct: null, asOf: null })
  const emptyHistory = { symbol: "AAPL", range: "1Y", interval: "1d", baseline: null, bars: [] }
  expect(M.historyRowModel(emptyHistory, nothing, 0).dayUp).toBeNull()
})

test("marketStatus says whether the market is open, and where the finger is while scrubbing", () => {
  const q = duringSession(quote)
  expect(M.marketStatus(q, reg.start + 2 * 3600, 0, calendars)).toBe("Market closes in 4h 30m")
  expect(M.marketStatus(q, reg.start - 600, 0, calendars)).toBe("Pre-market · opens in 10m")
  expect(M.marketStatus(q, q.session.pre.start - 600, 0, calendars)).toBe("Market opens in 5h 40m")
  expect(M.marketStatus(quote, quote.session.post.start + 60, 0, calendars)).toBe("After hours · closed at 16:00")
  expect(M.marketStatus(q, reg.start + 2 * 3600, reg.start + 3600)).toBe("At 10:30 · Market open")
  expect(M.marketStatus(q, reg.start + 2 * 3600, reg.start + 2.75 * 3600)).toBe("At 12:15 · Lunch lull")
  // At rest the day's named moments lead too, as they do while scrubbing.
  expect(M.marketStatus(q, reg.start + 600, 0, calendars)).toBe("Opening bell · closes in 6h 20m")
  expect(M.marketStatus(q, reg.start + 2.75 * 3600, 0, calendars)).toBe("Lunch lull · closes in 3h 45m")
  expect(M.marketStatus(q, reg.end - 40 * 60, 0, calendars)).toBe("Power hour · closes in 40m")
  expect(M.marketStatus(q, reg.end - 3 * 60, 0, calendars)).toBe("Closing bell · closes in 3m")
  // With less room, each says its time alone: the session is named on the
  // line under the price, and a scrub's moment goes before its time.
  expect(M.statusForms(quote, quote.session.post.start + 60, 0, calendars)).toEqual(["After hours · closed at 16:00", "Closed at 16:00"])
  expect(M.statusForms(q, reg.start - 600, 0, calendars)).toEqual(["Pre-market · opens in 10m", "Opens in 10m"])
  expect(M.statusForms(q, reg.start + 2 * 3600, reg.start + 3600)).toEqual(["At 10:30 · Market open", "At 10:30"])
})

test("extendedStack labels the print after the bell against the close", () => {
  expect(M.extendedStack(quote)).toEqual({ price: "324.72", changeText: "\u22120.13%", tone: "down", label: "AFTER HOURS", time: "", stale: false })
  expect(M.extendedStack(duringSession(quote))).toBeNull()
  // With the change as an amount, this line takes the hero's unit, not a
  // percent beside the hero's "+1.99"; since the open it stays a percent
  // from the close.
  expect(M.extendedStack(quote, null, 0, null, "abs")).toMatchObject({ price: "324.72", changeText: "\u22120.41", tone: "down" })
  expect(M.extendedStack(quote, null, 0, null, "open")).toEqual(M.extendedStack(quote))
  const close = M.regularClose(quote)
  const last = quote.points[quote.points.length - 1]
  const echo = { ...quote, points: [...quote.points.slice(0, -1), { t: last.t, p: close + 0.001 }] }
  expect(M.extendedStack(echo)).toBeNull()
})

test("a change that rounds to nothing has no sign and no direction", () => {
  expect(M.pct(0)).toBe("0.00%")
  expect(M.pct(0.004)).toBe("0.00%")
  expect(M.pct(-0.004)).toBe("0.00%")
  expect(M.pct(0.005)).toBe("+0.01%")
  expect(M.signedMoney(0)).toBe("0.00")
  expect(M.signedMoney(-0.001)).toBe("0.00")
  expect(M.money(-0.001)).toBe("0.00")
  expect(M.lookSigns(M.pct(0), true)).toBe("0.00%")
  expect(M.changeTone({ abs: 0, pct: 0 }, "pct")).toBe("flat")
  // Each mode judges its own figure as drawn: a big stock's +1.20 can be
  // 0.00%, flat in percent and up in amount.
  expect(M.changeTone({ abs: 0.004, pct: 0.00004 }, "abs")).toBe("flat")
  expect(M.changeTone({ abs: 1.2, pct: 0.004 }, "pct")).toBe("flat")
  expect(M.changeTone({ abs: 1.2, pct: 0.004 }, "abs")).toBe("up")
  expect(M.changeTone({ abs: -3, pct: -2 }, "open")).toBe("down")
  expect(M.changeTone({ abs: null, pct: null }, "pct")).toBe("flat")
  const still = { ...quote, prevClose: M.regularClose(quote) }
  const view = M.rowModel(still, 0, "pct")
  expect(view.changeText).toBe("0.00%")
  expect(view.tone).toBe("flat")
  // The chart's direction still has one: the day did not fall.
  expect(view.dayUp).toBe(true)
})

// An info line as one string to read: its title, its range (an end's tone
// after it, "+" up and "-" down; an unknown end as "?"; "@" the price the
// tick marks), and its facts, an empty slot as "_".
const said = line => line && [
  line.title,
  (line.range.lowText || "?") + (line.range.lowTone === "down" ? "-" : "") + "–"
    + (line.range.highText || "?") + (line.range.highTone === "up" ? "+" : "")
    + (line.range.price === null ? "" : " @" + M.money(line.range.price)),
  ...line.facts.map(f => [f.label, f.value || "_", f.after].filter(Boolean).join(" "))
].join(" · ")
// The day line as it reads at `t`: its `today` is the day `t` falls on in
// the listing's exchange, counted in whole days at the quote's UTC offset.
const dayLineAt = (q, t) => M.dayLine(q, Math.floor((t + (q.gmtoffset || 0)) / 86400))

// Yahoo sends some day answers with their trading periods in a range's
// shape, one list of days, in place of pre, regular, and post: every non-US
// listing's, and an index's at night. Those periods are the regular
// session's: SHEL.L is open through its session, not "Closed · opens Mon",
// and ^GSPC's day line over Thursday's figures says THU, not 1D.
test("a day answer whose trading periods are one list of days has them as its regular session", () => {
  const shel = M.parseChart(fixture("shel-l-2026-10-23-trading.json"))
  const london = calendars.calendars.LSE
  expect(shel.session).toEqual({ pre: null, regular: { start: M.epochAt(london, "2026-10-23", "08:00"), end: M.epochAt(london, "2026-10-23", "16:30") }, post: null })
  const opening = M.epochAt(london, "2026-10-23", "08:10")
  expect(M.marketStatus(shel, opening, 0, calendars)).toBe("Opening bell · closes in 8h 20m")
  const toyota = M.parseChart(fixture("7203-t-2026-10-23-day.json"))
  expect(toyota.session.regular).toEqual({ start: M.epochAt(JPX, "2026-10-23", "09:00"), end: M.epochAt(JPX, "2026-10-23", "15:30") })
  expect(M.marketStatus(toyota, M.epochAt(JPX, "2026-10-23", "11:00"), 0, calendars)).toBe("Lunch break in 30m")
  const gspc = M.parseChart(fixture("gspc-2026-10-23-night.json"))
  expect(gspc.session.regular).toEqual({ start: M.epochAt(US, "2026-10-22", "09:30"), end: M.epochAt(US, "2026-10-22", "16:00") })
  expect(dayLineAt(gspc, at("2026-10-23", "03:03")).title).toBe("THU")
})

test("the day line is 1D, or its figures' weekday when they are not today's: its low and high, its open and volume", () => {
  // On its own day a session's line is 1D: SHOP.TO's saved day is
  // Wednesday 2 September in Toronto, AAPL's Tuesday 1 September, read
  // after its close. The open is the first regular bar's.
  expect(said(dayLineAt(shop, at("2026-09-02", "15:00")))).toBe("1D · 192.88–196.46 @194.60 · OPEN 194.74 · VOL 353K")
  expect(said(dayLineAt(quote, at("2026-09-01", "17:30")))).toBe("1D · 314.74–327.30 @325.13 · OPEN 316.98 · VOL 52.4M")
  // On a Saturday, Friday's figures are FRI: NEST's 11 September.
  const nest = M.parseChart(fixture("nest-2026-09-11-day-prepost.json"))
  expect(said(dayLineAt(nest, at("2026-09-12", "12:00")))).toBe("FRI · 223.64–234.80 @224.55 · OPEN 234.80 · VOL 11.2M")
  // On Labor Day, Monday 7 September, AAPL's Friday 4 September.
  expect(dayLineAt(M.parseChart(fixture("aapl-2026-09-04-day-prepost.json")), at("2026-09-07", "12:00")).title).toBe("FRI")
  // Six days on, the weekday still names one day of the week before; a
  // week on it would read as today's, so the month stands in.
  expect([dayLineAt(nest, at("2026-09-17", "12:00")).title, dayLineAt(nest, at("2026-09-18", "12:00")).title]).toEqual(["FRI", "SEP"])
  // A listing untraded on its answer's day keeps its last trading day's
  // figures, and says that day: CVR at 23:09 on Friday 16 October answered
  // with Friday's session and Wednesday's figures, its quote stamped
  // Wednesday 16:00: WED, not 1D.
  const cvr = M.parseChart(fixture("moments/power-user-2026-10-16/cvr.json"))
  expect(said(dayLineAt(cvr, at("2026-10-16", "23:09")))).toBe("WED · 11.28–11.87 @11.28 · OPEN _ · VOL 68")
  expect(M.dayLine(null)).toBeNull()
  // Before the session's first bar there is no open to give: its slot is
  // kept, empty, so the line keeps its shape.
  const early = fixture("aapl.json")
  const result = early.chart.result[0]
  const pre = result.timestamp.filter(t => t < result.meta.currentTradingPeriod.regular.start).length
  result.timestamp = result.timestamp.slice(0, pre)
  for (const key of Object.keys(result.indicators.quote[0])) result.indicators.quote[0][key] = result.indicators.quote[0][key].slice(0, pre)
  expect(said(dayLineAt(M.parseChart(early), at("2026-09-01", "09:00")))).toBe("1D · 314.74–327.30 @325.13 · OPEN _ · VOL 52.4M")
  // A day that reaches a 52-week mark says so by that end's tone, and an
  // ordinary day does not.
  const reaching = (field, from) => {
    const json = fixture("aapl.json")
    const meta = json.chart.result[0].meta
    meta[field] = meta[from]
    return M.parseChart(json)
  }
  expect(said(dayLineAt(reaching("fiftyTwoWeekHigh", "regularMarketDayHigh"), at("2026-09-01", "17:30"))))
    .toBe("1D · 314.74–327.30+ @325.13 · OPEN 316.98 · VOL 52.4M")
  expect(said(dayLineAt(reaching("fiftyTwoWeekLow", "regularMarketDayLow"), at("2026-09-01", "17:30"))))
    .toBe("1D · 314.74-–327.30 @325.13 · OPEN 316.98 · VOL 52.4M")

})

test("the day line's title is 1D through its figures' last second, their weekday from the next midnight, over a weekend and a holiday, their month a week on", () => {
  // AAPL's figures are Tuesday 1 September's.
  const title = t => dayLineAt(quote, t).title
  expect([title(at("2026-09-01", "23:59") + 59), title(at("2026-09-02", "00:00")), title(at("2026-09-05", "12:00")),
    title(at("2026-09-07", "12:00")), title(at("2026-09-08", "12:00"))]).toEqual(["1D", "TUE", "TUE", "TUE", "SEP"])
  // CKX traded on Friday 16 October, so at 23:09 that Friday its figures
  // are the day's; CVR's are Wednesday's.
  const ckx = M.parseChart(fixture("moments/power-user-2026-10-16/ckx.json"))
  const cvr = M.parseChart(fixture("moments/power-user-2026-10-16/cvr.json"))
  expect([dayLineAt(ckx, at("2026-10-16", "23:09")).title, dayLineAt(cvr, at("2026-10-16", "23:09")).title]).toEqual(["1D", "WED"])
})

// Saved answers from Sunday 25 October 2026, prices Friday's: the series,
// the daily bars around the cap's date, the day, and Yahoo's rates.
// NEST's, SPY's, and BTC-USD's are from 1 October.
const fundamentals = name => M.parseFundamentals(fixture(`fundamentals/${name}.json`))
const figures = name => {
  const read = fundamentals(name)
  return read.cap ? M.withCapClose(read, fixture(`fundamentals/${name}-closes.json`)) : read
}
const rate = pair => M.parseRate(fixture(`fundamentals/fx-${pair.toLowerCase()}.json`), pair)
// Yahoo's saved rates as the feed keeps them, by pair.
const rates = Object.fromEntries(["USDCAD", "USDGBP", "USDAUD"].map(pair => [pair, { value: rate(pair), checkedAt: 0 }]))
// A listing's figures as the feed keeps them, the pair its P/E needs, and
// its Friday day.
const listing = name => {
  const q = M.parseChart(fixture(`fundamentals/${name}-2026-10-25-day.json`))
  const f = figures(`${name}-2026-10-25`)
  return { q, f, pair: M.ratePair(f, q.currency) }
}

test("Yahoo's cap is the newer of its own snapshot and the quarter's end, with that date's close, beside the latest EPS", () => {
  const cap = (value, date, currency, close) => ({ value, date, currency, close })
  const eps = (value, currency) => ({ value, date: "2026-06-30", currency })
  const own = name => M.latestSnapshot(fixture(`fundamentals/${name}-2026-10-25.json`).timeseries.result, "trailingMarketCap").date
  // AAPL's own snapshot, 17 September, is newer than the quarter's end.
  expect(figures("aapl-2026-10-25")).toEqual({ cap: cap(4918238660000, "2026-09-17", "USD", 337), eps: eps(8.72, "USD") })
  // PIER's own is a year old: the quarter's end, 30 June, takes its place.
  expect(own("pier")).toBe("2025-10-02")
  expect(figures("pier-2026-10-25")).toEqual({ cap: cap(896414500, "2026-06-30", "USD", 38.88999938964844), eps: eps(2.94, "USD") })
  // The cap in the listing's currency, the EPS in the one it reports in:
  // Shopify and Shell report in dollars, Shell's cap in pounds while its
  // prices are in pence.
  expect(own("shop-to")).toBe("2025-10-03")
  expect(figures("shop-to-2026-10-25")).toEqual({ cap: cap(209197184573, "2026-06-30", "CAD", 162.25999450683594), eps: eps(1.48, "USD") })
  expect(figures("shel-l-2026-10-25")).toEqual({ cap: cap(162552239092, "2026-06-30", "GBP", 2933), eps: eps(4.52, "USD") })
  expect(figures("7203-t-2026-10-25")).toEqual({ cap: cap(36316507956160, "2026-07-31", "JPY", 3067), eps: eps(351.38, "JPY") })
  // ORE.AX reports half-yearly: no quarter's end, its own snapshot alone.
  expect(figures("ore-ax-2026-10-25")).toEqual({ cap: cap(306416424997, "2026-07-31", "AUD", 60.310001373291016), eps: eps(1.932, "USD") })
  // NEST's latest trailing diluted EPS is a loss, so it has none.
  expect(figures("nest").eps).toBeNull()
  // An ETF and a cryptocurrency: every series empty, so no close to ask for.
  for (const name of ["spy", "btc-usd"]) {
    expect(fundamentals(name)).toEqual({ cap: null, eps: null })
    expect(M.capCloseUrl(name.toUpperCase(), fundamentals(name))).toBeNull()
  }
  // An answer that is not a timeseries, closes that are not a chart, or a
  // chart without the cap's close is no answer: the feed keeps the figures
  // it had.
  expect(M.parseFundamentals({ finance: { error: "Too Many Requests" } })).toBeNull()
  expect(M.withCapClose(fundamentals("aapl-2026-10-25"), null)).toBeNull()
  expect(M.withCapClose(fundamentals("aapl-2026-10-25"), { chart: { result: [{ meta: { gmtoffset: -14400 } }] } })).toBeNull()
  // Only an equity is asked.
  expect([quote, shop, btc].map(M.hasFundamentals)).toEqual([true, true, false])
  expect(M.hasFundamentals(M.parseChart(fixture("spy-2026-09-11-day-prepost.json")))).toBe(false)
  expect(M.hasFundamentals({ ...quote, symbol: "^GSPC", instrumentType: "INDEX" })).toBe(false)
})

// Against Yahoo's own live figures for these, each cap is within 3% and
// each P/E within 4%.
test("the 52-week line moves the cap with the price, and divides the price by the EPS in the price's currency", () => {
  const year = (q, f, held = rates) => said(M.yearLine(q, f, null, held))
  const facts = (q, f, held) => year(q, f, held).split(" · ").slice(2).join(" · ")
  const read = name => facts(listing(name).q, listing(name).f)
  expect(read("aapl")).toBe("MKT CAP USD 5.07T · P/E 39.9")
  expect(read("pier")).toBe("MKT CAP USD 1.1B · P/E 15.5")
  expect(read("7203-t")).toBe("MKT CAP JPY 36.77T · P/E 8.8")
  // Earnings in dollars, at Yahoo's rate: 236.24 / (1.48 × 1.4004) is 114.0,
  // and from 100 a P/E has no decimals.
  expect(listing("shop-to").pair).toBe("USDCAD")
  expect(read("shop-to")).toBe("MKT CAP CAD 304.6B · P/E 114")
  // London's price in pence over earnings in pounds: 40.33 / (4.52 × 0.7477).
  expect(listing("shel-l").pair).toBe("USDGBP")
  expect(read("shel-l")).toBe("MKT CAP GBP 223.5B · P/E 11.9")
  expect(listing("ore-ax").pair).toBe("USDAUD")
  expect(read("ore-ax")).toBe("MKT CAP AUD 279.7B · P/E 20.1")
  // Without its pair's rate, or after the rate failed, a P/E is left out,
  // never shown in the wrong currency; the cap still shows. A rate answer
  // for another pair is no rate.
  const shopTo = listing("shop-to")
  expect(facts(shopTo.q, shopTo.f, {})).toBe("MKT CAP CAD 304.6B · P/E _")
  expect(facts(shopTo.q, shopTo.f, { USDCAD: { value: null, checkedAt: 0 } })).toBe("MKT CAP CAD 304.6B · P/E _")
  expect([rate("USDCAD"), M.parseRate(fixture("fundamentals/fx-usdgbp.json"), "USDCAD")]).toEqual([1.4004, null])
  // Yahoo answers a pair from USD under its short name about half the time,
  // GBP=X for USDGBP=X, at the same rate: Shell keeps its P/E. The short
  // name stands only for a pair from USD: GBP=X is no answer for EURGBP.
  const short = pair => M.parseRate(fixture(`fundamentals/fx-${pair.toLowerCase()}-short.json`), pair)
  expect([short("USDGBP"), short("USDCAD")]).toEqual([0.7477, 1.4004])
  const shell = listing("shel-l")
  expect(facts(shell.q, shell.f, { USDGBP: { value: short("USDGBP"), checkedAt: 0 } })).toBe("MKT CAP GBP 223.5B · P/E 11.9")
  expect(M.parseRate(fixture("fundamentals/fx-usdgbp-short.json"), "EURGBP")).toBeNull()
  // A price in a small unit other than pence, cents of rand against
  // earnings in rand, asks no rate and has no P/E.
  const rand = { ...figures("shop-to-2026-10-25"), eps: { value: 1.48, date: "2026-06-30", currency: "ZAR" } }
  expect(M.ratePair(rand, "ZAc")).toBe("")
  expect(facts({ ...shopTo.q, currency: "ZAc" }, rand)).toBe("MKT CAP CAD 304.6B · P/E _")
  // A quote at `price`, stamped `days` after `date`'s 20:00 UTC: the cap
  // and the P/E follow the price.
  const at = (q, price, date, days = 0) => ({ ...q, price, marketTime: M.dateEpoch(date) + days * DAY + 20 * 3600 })
  const pier = listing("pier")
  expect(facts(at(pier.q, 38.89, "2026-06-30"), pier.f)).toBe("MKT CAP USD 896.4M · P/E 13.2")
  expect(facts(at(pier.q, 91.26, "2026-10-23"), pier.f)).toBe("MKT CAP USD 2.1B · P/E 31.0")
  // A cap 200 days old still moves with the price; at 201 it is left out.
  expect(facts(at(pier.q, 38.89, "2026-06-30", 200), pier.f)).toBe("MKT CAP USD 896.4M · P/E 13.2")
  expect(facts(at(pier.q, 38.89, "2026-06-30", 201), pier.f)).toBe("MKT CAP _ · P/E 13.2")
  // After a loss there is no P/E.
  const nest = M.parseChart(fixture("nest-2026-09-11-day-prepost.json"))
  expect(year(at(nest, 226.61, "2026-09-23"), figures("nest"))).toBe("52W · 73.52–299.86 @226.61 · MKT CAP USD 61.6B · P/E _")
  // An ETF and a cryptocurrency have their 52-week range only, and no slot
  // for a cap or a P/E they never have.
  expect(year(M.parseChart(fixture("spy-2026-09-11-day-prepost.json")), null)).toBe("52W · 629.28–779.37 @764.29")
  expect(year(btc, null)).toBe("52W · 57,748–126,198 @77,152")
  expect(M.yearLine(null, pier.f)).toBeNull()
})

// Yahoo's 52-week marks can trail the day: a day past one shows the same
// high (or low) on both lines, in that direction's tone.
test("a day past its 52-week mark widens the 52-week range to it", () => {
  const past = { ...quote, fiftyTwoWeekHigh: quote.dayHigh - 1 }
  expect(said(M.dayLine(past)).split(" · ")[1]).toBe("314.74–327.30+ @325.13")
  expect(said(M.yearLine(past, null)).split(" · ")[1]).toBe("225.95–327.30+ @325.13")
  const under = { ...quote, fiftyTwoWeekLow: quote.dayLow + 1 }
  expect(said(M.dayLine(under)).split(" · ")[1]).toBe("314.74-–327.30 @325.13")
  expect(said(M.yearLine(under, null)).split(" · ")[1]).toBe("314.74-–344.57 @325.13")
})

// Yahoo's 52 weeks leave out the 1Y range's first day, so on 1Y the line is
// the range's own low and high and always agrees with the chart's marks:
// RGTI's 1Y line must not say 58.15 over a 52-week high of 57.97. Saved 14
// October 2026, when that first day held a stock's high (RGTI) and low
// (GOOG), a cryptocurrency's high, an index's low, a Toronto listing's low,
// and an ETF's neither.
test("on 1Y the 52-week line is the range's low and high", () => {
  const saved = name => {
    const q = M.parseChart(fixture(`first-day-2026-10-14/${name}-day.json`))
    const h = M.parseHistory(fixture(`first-day-2026-10-14/${name}-1y.json`), "1Y")
    return { q, h, ends: M.rangeEnds(h, null, q) }
  }
  const ends = line => said(line).split(" · ")[1].replace(/ @.*/, "")
  const lines = ({ q, h, ends: e }) => [ends(M.rangeLine(h, e, q)), ends(M.yearLine(q, null, e)), ends(M.yearLine(q, null, null))]
  expect(lines(saved("rgti"))).toEqual(["11.77–58.15", "11.77-–58.15", "11.77-–57.97"])
  expect(lines(saved("goog"))).toEqual(["241.18–404.47", "241.18–404.47", "244.67–404.47"])
  expect(lines(saved("eth-usd"))).toEqual(["1,506.51–4,265.11", "1,506.51–4,265.11", "1,506.51–4,250.67"])
  expect(lines(saved("n225"))).toEqual(["46,544–72,832", "46,544–72,832", "46,911–72,832"])
  expect(lines(saved("td-to"))).toEqual(["109.56–175.33", "109.56–175.33", "110.17–175.33"])
  expect(lines(saved("spy"))).toEqual(["629.28–781.62", "629.28–781.62", "629.28–781.62"])
  // A 52-week figure of Yahoo's wider than the chart's ends gives way to
  // them: no 600.00–800.00 under a chart marked 629.28 and 781.62.
  const spy = saved("spy")
  expect(ends(M.yearLine({ ...spy.q, fiftyTwoWeekLow: 600, fiftyTwoWeekHigh: 800 }, null, spy.ends))).toBe("629.28–781.62")
  // A day at Yahoo's high under a higher first day is not at the line's
  // high, so takes no tone.
  const rgti = saved("rgti")
  expect(ends(M.yearLine({ ...rgti.q, fiftyTwoWeekHigh: rgti.q.dayHigh }, null, rgti.ends))).toBe("11.77-–58.15")
  // A day at its 52-week high keeps its tone on 1Y, though its own bar's
  // high carries float noise past the day's.
  const goog = saved("goog")
  const capped = goog.h.bars.map(b => ({ ...b, h: Math.min(b.h, goog.q.dayHigh) }))
  capped[capped.length - 1].h = goog.q.dayHigh + 1e-9
  const googQ = { ...goog.q, fiftyTwoWeekHigh: goog.q.dayHigh }
  expect(ends(M.yearLine(googQ, null, M.rangeEnds({ ...goog.h, bars: capped }, null, googQ)))).toBe("241.18–355.25+")
})

test("each symbol is asked for on its own market's clock", () => {
  const q = duringSession(quote)
  const s = q.session
  const cadence = (quote, now, hero = false, interval = 60) => quoteCadence(quote, now, interval, hero)
  // Its regular session: the refresh interval, whatever the setting says.
  expect(cadence(q, reg.start + 3600)).toBe(60)
  expect(cadence(q, reg.start + 3600, false, 45)).toBe(45)
  // Pre-market and after hours: the close can't move, only the dim tail, so
  // every 5 minutes unless it is an open surface's hero; never faster than
  // the interval.
  expect(cadence(q, s.pre.start + 60)).toBe(300)
  expect(cadence(q, s.post.start + 60)).toBe(300)
  expect(cadence(q, s.post.start + 60, true)).toBe(60)
  expect(cadence(q, s.post.start + 60, false, 600)).toBe(600)
  // Closed: the night and the weekend.
  expect(cadence(q, s.post.end + 3600)).toBe(900)
  expect(cadence(q, reg.start + 5 * DAY, true)).toBe(900)
  // A cryptocurrency trades through every night and weekend, and keeps only
  // itself on the minute.
  expect(cadence(btc, btc.session.regular.start + 5 * DAY)).toBe(60)
  // No quote yet, or a first fetch that failed: the slow clock.
  expect(cadence(null, reg.start + 3600)).toBe(900)
})

// A held quote describes its own session until the new day's answer lands,
// so at the open it would say closed; while the calendar has a segment
// trading, that session stands in. SHEL.L's Friday answer held to Monday
// must not say "Closed · opens Tue 08:00 GMT" at 08:00:10; Toyota's lunch
// is still a break.
test("a quote held from an earlier session says the calendar's session while it trades", () => {
  const shel = M.parseChart(fixture("shel-l-2026-10-23-trading.json"))
  const london = calendars.calendars.LSE
  const monday = hm => M.marketStatus(shel, M.epochAt(london, "2026-10-26", hm), 0, calendars)
  expect(monday("07:59")).toBe("Closed · opens Mon 08:00 GMT")
  expect(monday("08:00")).toBe("Opening bell · closes in 8h 30m")
  expect(monday("12:00")).toBe("Market closes in 4h 30m")
  expect(monday("16:40")).toBe("Closed · opens Tue 08:00 GMT")
  expect(M.marketStatus(shel, M.epochAt(london, "2026-10-24", "10:00"), 0, calendars)).toBe("Weekend · opens Mon 08:00 GMT")
  const toyota = M.parseChart(fixture("7203-t-2026-10-23-day.json"))
  const tokyo = hm => M.marketStatus(toyota, M.epochAt(JPX, "2026-10-26", hm), 0, calendars)
  expect([tokyo("09:00"), tokyo("11:45"), tokyo("13:00")])
    .toEqual(["Opening bell · lunch break in 2h 30m", "Lunch break · reopens 12:30 JST · in 45m", "Market closes in 2h 30m"])
  // The hour is the calendar's on the day, not the held answer's: AAPL's
  // answer of Tuesday 1 September, in EDT, held to Monday 2 November, in
  // EST: no "Lunch lull" at 11:00.
  const aapl = hm => M.marketStatus(quote, M.epochAt(US, "2026-11-02", hm), 0, calendars)
  expect([aapl("11:00"), aapl("12:10")]).toEqual(["Market closes in 5h", "Lunch lull · closes in 3h 50m"])
})

test("a published closure is closed, whatever Yahoo's periods say", () => {
  const labor = 1788793200
  const fakeOpen = {
    ...sep4,
    session: { pre: null, post: null, regular: { start: labor - 3600, end: labor + 3600 } }
  }
  expect(M.quoteCadence(fakeOpen, labor, 60, false, M.calendarNow(null, labor))).toBe(60)
  expect(quoteCadence(fakeOpen, labor, 60, false)).toBe(900)
  expect(M.inRegularSession(fakeOpen, labor, calendars)).toBe(false)
  // The header agrees: the published closure outranks a response that still
  // describes a session.
  expect(M.marketStatus(fakeOpen, labor, 0, calendars)).toBe("Labor Day · opens Tue 09:30")
  expect(M.marketStatus(fakeOpen, labor, 0, null)).toBe("Power hour · closes in 1h")
  // Where the header has no room for the holiday's name, it says the
  // closure as a weekend is said, and with less room still, when it opens:
  // every form keeps the time.
  expect(M.statusForms(fakeOpen, labor, 0, calendars)).toEqual(["Labor Day · opens Tue 09:30", "Closed · opens Tue 09:30", "Opens Tue 09:30"])
  expect(M.statusForms(fakeOpen, labor, 0, null)).toEqual(["Power hour · closes in 1h", "Closes in 1h"])
})

test("the bell rings once at a market's open and once at its close, never late, on a holiday, or for a coin", () => {
  const q = duringSession(quote)
  const bell = (quote, before, now) => M.bellBetween(quote, before, now, calendars)
  // The minute's tick over the open and the close, and a step just over.
  expect([bell(q, reg.start - 60, reg.start), bell(q, reg.start - 1, reg.start + 5), bell(q, reg.end - 30, reg.end + 30)])
    .toEqual(["open", "open", "close"])
  // Nothing between them, and nothing late: Stonks started, or the machine
  // woke, after the bell.
  expect([bell(q, reg.start + 60, reg.start + 120), bell(q, reg.start - 3600, reg.start + 60), bell(q, reg.end - 60, reg.end + 600)])
    .toEqual(["", "", ""])
  // Labor Day, whatever Yahoo's periods say, and a coin's day, ring nothing.
  const labor = 1788793200
  const fakeOpen = { ...sep4, session: { pre: null, post: null, regular: { start: labor - 3600, end: labor + 3600 } } }
  expect([bell(fakeOpen, labor - 3630, labor - 3570), bell(fakeOpen, labor + 3570, labor + 3630)]).toEqual(["", ""])
  const day = btc.session.regular
  expect([bell(btc, day.start - 30, day.start + 30), bell(btc, day.end - 30, day.end + 30)]).toEqual(["", ""])
})

test("freshness keeps quote age, an unanswered ask, and the refresh outcome apart", () => {
  const q = duringSession(quote)
  const trading = reg.start + 3600
  const ok = { status: "ok", receivedAt: trading - 10 }
  const live = { ...q, price: 100, marketTime: trading - 30 }
  expect(M.freshness(ok, live, trading, 0)).toMatchObject({ state: "fresh", live: true, asOf: trading - 30 })
  // The same old quote fetched again is still an old quote.
  const aged = { ...q, price: 100, marketTime: trading - 121 }
  expect(M.freshness(ok, aged, trading, 0)).toMatchObject({ state: "aged", live: false, asOf: trading - 121 })
  expect(M.freshnessText(M.freshness(ok, aged, trading, 0), q)).toBe("AS OF 10:27")
  // An old quote in its refresh's grace (`Service.asking`) says nothing of
  // its age, and claims no live price, where its last answer is old too (a
  // coin nothing kept fresh, as a surface opens); one answered a minute ago
  // is late at its source, and says "As of" through each refresh.
  const unrefreshed = { status: "ok", answeredAt: trading - 3600 }
  expect(M.freshness(unrefreshed, aged, trading, 0, true)).toMatchObject({ state: "asking", live: false })
  expect(M.freshnessText(M.freshness(unrefreshed, aged, trading, 0, true), q)).toBe("")
  expect(M.freshness(unrefreshed, aged, trading, 0, false).state).toBe("aged")
  expect(M.freshness({ status: "ok", answeredAt: trading - 60 }, aged, trading, 0, true).state).toBe("aged")
  // A refresh asked for and unanswered for 90 s is overdue, however old the
  // last answer; one nobody asked for never is.
  expect(M.freshness(ok, live, trading, trading - 89).state).toBe("fresh")
  expect(M.freshness(ok, live, trading, trading - 90)).toMatchObject({ state: "overdue", live: false })
  expect(M.freshnessText(M.freshness(ok, live, trading, trading - 90), q)).toBe("UPDATE OVERDUE · AS OF 10:29")
  expect(M.freshnessWarns(M.freshness(ok, live, trading, trading - 90))).toBe(true)
  expect(M.freshness({ status: "ok", receivedAt: trading - 86400 }, live, trading, 0).state).toBe("fresh")
  // A failed refresh is a failure whatever the quote's age, and keeps its as-of.
  const failed = { status: "failed", receivedAt: trading - 10 }
  expect(M.freshness(failed, live, trading, 0)).toMatchObject({ state: "failed", live: false, asOf: trading - 30 })
  expect(M.freshnessText(M.freshness(failed, live, trading, 0), q)).toBe("REFRESH FAILED · AS OF 10:29")
  expect(M.freshnessWarns(M.freshness(failed, live, trading, 0))).toBe(true)
  // No quote at all: unavailable, failed when the first fetch failed, and a
  // warning once its ask has gone 90 s unanswered.
  expect(M.freshness(null, null, trading, 0)).toMatchObject({ state: "unavailable", live: false })
  expect(M.freshnessText(M.freshness({ status: "failed", receivedAt: 0 }, null, trading, 0), null)).toBe("NO DATA FOR THIS SYMBOL")
  const nothing = M.freshness(null, null, trading, trading - 90)
  expect([nothing.state, M.freshnessText(nothing, null), M.freshnessWarns(nothing)]).toEqual(["overdue", "NO DATA", true])
})

test("a quote kept from an earlier session says when it is from, and warns only once asked for and unanswered", () => {
  const q = duringSession(quote)
  const close = { ...q, price: 100, marketTime: reg.end - 1 }
  const saved = { status: "saved", receivedAt: reg.end }
  // The same day: its time. Another day: the day too, so yesterday's close
  // is never read as now; in its exchange's time, with no live mark.
  const sameDay = M.freshness(saved, close, q.session.post.start + 60, 0)
  expect([sameDay.state, sameDay.live, M.freshnessText(sameDay, q)]).toEqual(["saved", false, "AS OF 15:59"])
  const nextDay = M.freshness(saved, close, reg.start + DAY + 60, 0)
  expect([nextDay.state, nextDay.live, M.freshnessWarns(nextDay), M.freshnessText(nextDay, q)])
    .toEqual(["saved", false, false, "AS OF TUE 15:59"])
  const late = M.freshness(saved, close, reg.start + DAY + 90, reg.start + DAY)
  expect([late.state, M.freshnessText(late, q)]).toEqual(["overdue", "UPDATE OVERDUE · AS OF TUE 15:59"])
})

test("outside trading an old close is normal, but a failed refresh still shows", () => {
  const q = duringSession(quote)
  const night = q.session.post.end + 3600
  const closeQuote = { ...q, price: 100, marketTime: reg.end + 1 }
  const ok = { status: "ok", receivedAt: night - 60 }
  expect(M.freshness(ok, closeQuote, night, 0)).toMatchObject({ state: "fresh", live: false })
  expect(M.freshnessText(M.freshness(ok, closeQuote, night, 0), q)).toBe("")
  const failed = { status: "failed", receivedAt: night - 60 }
  expect(M.freshness(failed, closeQuote, night, 0).state).toBe("failed")
})

test("parseSearch keeps tradable results with names and readable exchanges", () => {
  const { results: rows, note } = M.parseSearch(search)
  expect(rows[0].symbol).toBe("SHOP")
  expect(rows[0].exchange).toBe("NASDAQ")
  expect(rows.find(r => r.symbol === "SHOP.TO").exchange).toBe("TSX")
  for (const r of rows) expect(r.name.length).toBeGreaterThan(0)
  expect(note).toBe("")
})

// "vfiax", a Vanguard fund Yahoo has, must not read "No matches", and
// "eurusd" must not show two Zurich indexes with the currency itself hidden
// without a word.
test("search names the kinds it leaves out, beside what it shows or alone", () => {
  const vfiax = fixture("search-vfiax.json")
  const eurusd = fixture("search-eurusd.json")
  expect(M.parseSearch(vfiax)).toEqual({ results: [], note: "Stonks doesn’t show mutual funds", topLeftOut: true })
  const pair = M.parseSearch(eurusd)
  expect(pair.results.map(r => r.symbol)).toEqual(["18QQ.Z", "Q0SF.Z"])
  expect(pair.note).toBe("Stonks doesn’t show currencies or futures")
  // Yahoo's top answer is the currency, so search takes neither index for
  // it (window-search.qml).
  expect([pair.topLeftOut, M.parseSearch(search).topLeftOut]).toEqual([true, false])
  // Three kinds, in the answer's order; a kind with no name of Stonks' own
  // goes by Yahoo's word for it.
  expect(M.parseSearch({ quotes: vfiax.quotes.concat(eurusd.quotes) }).note)
    .toBe("Stonks doesn’t show mutual funds, currencies, or futures")
  expect(M.parseSearch({ quotes: [{ symbol: "W", quoteType: "WARRANT", typeDisp: "Warrant" }] }).note)
    .toBe("Stonks doesn’t show warrants")
})

test("request URLs are the exact strings Yahoo is sent, and history never takes the 1D path", () => {
  expect(M.searchUrl("a b")).toContain("q=a%20b")
  expect(M.historyUrl("AAPL", "1D")).toBeNull()
  // The saved fundamentals answers are the feed's own requests.
  const saved = name => readFileSync(join(fixtures, "fundamentals", name + ".url"), "utf8").replace(/^# /, "").trim()
  const asked = Number(saved("aapl-2026-10-25").match(/period2=(\d+)/)[1])
  expect(M.fundamentalsUrl("AAPL", asked)).toBe(saved("aapl-2026-10-25"))
  expect(asked - Number(saved("aapl-2026-10-25").match(/period1=(\d+)/)[1])).toBe(400 * DAY)
  for (const [name, symbol] of [["aapl", "AAPL"], ["pier", "PIER"], ["shop-to", "SHOP.TO"], ["7203-t", "7203.T"], ["shel-l", "SHEL.L"], ["ore-ax", "ORE.AX"]])
    expect(M.capCloseUrl(symbol, fundamentals(name + "-2026-10-25"))).toBe(saved(name + "-2026-10-25-closes"))
  for (const pair of ["USDCAD", "USDGBP", "USDAUD"])
    expect(M.rateUrl(pair)).toBe(saved("fx-" + pair.toLowerCase()))
})

test("the saved NVDA split response uses split-adjusted close columns on both sides", () => {
  const json = fixture("history/nvda-split.json")
  const split = json.chart.result[0].events.splits["1718026200"]
  const history = M.parseHistory(json, "2Y")
  expect(split.splitRatio).toBe("10:1")
  expect(history.bars[4]).toMatchObject({ t: 1717767000, c: 120.88800048828125 })
  expect(history.bars[5]).toMatchObject({ t: 1718026200, c: 121.79000091552734 })
  expect(history.bars[5].c / history.bars[4].c).toBeCloseTo(1.0074614554265338, 10)
  expect(history.bars[0].c).toBe(115)
  expect(json.chart.result[0].indicators.adjclose[0].adjclose[0]).toBe(114.67301177978516)
})

test("historyGeometry uses uniform bar spacing and retains bar facts", () => {
  const history = M.parseHistory(fixture("history/aapl-1y.json"), "1Y")
  const geometry = M.historyGeometry(history)
  const step = 1 / (history.bars.length - 1)
  expect(geometry.points.length).toBe(history.bars.length)
  expect(geometry.points[0]).toMatchObject({ x: 0, t: 1757683800, p: 234.07000732421875, ext: false })
  expect(geometry.points[geometry.points.length - 1]).toMatchObject({ x: 1, t: 1789133400, p: 332.2699890136719, ext: false })
  for (let i = 1; i < geometry.points.length; i++)
    expect(geometry.points[i].x - geometry.points[i - 1].x).toBeCloseTo(step, 12)
  const closes = history.bars.map(bar => bar.c).concat([history.baseline])
  expect(geometry.day).toBe(false)
  // Headroom: every close and the baseline sit strictly inside the range.
  expect(geometry.lo).toBeLessThan(Math.min(...closes))
  expect(geometry.hi).toBeGreaterThan(Math.max(...closes))
  expect(geometry.baselineY).toBeGreaterThan(0)
  expect(geometry.baselineY).toBeLessThan(1)
  expect(geometry.start).toBe(1757683800)
  expect(geometry.end).toBe(1789133400)
})

test("5Y and longer draw on a log scale; shorter ranges stay linear", () => {
  const weekly = M.parseHistory(fixture("history/aapl-5y.json"), "5Y")
  const geometry = M.historyGeometry(weekly)
  const logY = p => 1 - (Math.log(p) - Math.log(geometry.lo)) / (Math.log(geometry.hi) - Math.log(geometry.lo))
  for (const point of geometry.points) expect(point.y).toBeCloseTo(logY(point.p), 12)
  expect(geometry.baselineY).toBeCloseTo(logY(weekly.baseline), 12)
  const highest = geometry.points.reduce((a, b) => (b.p > a.p ? b : a))
  const lowest = geometry.points.reduce((a, b) => (b.p < a.p ? b : a))
  expect(Math.min(...geometry.points.map(point => point.y))).toBe(highest.y)
  expect(Math.max(...geometry.points.map(point => point.y))).toBe(lowest.y)
  // The scrub walks bars by position, so the scale cannot move it.
  const bar = weekly.bars[100]
  expect(M.historyBarAt(weekly, geometry.points[100].x)).toBe(bar)
  expect(M.historyFraction(weekly, bar.t)).toBe(geometry.points[100].x)
  for (const range of ["10Y", "All"]) {
    const long = M.historyGeometry({ ...weekly, range })
    const longY = p => 1 - (Math.log(p) - Math.log(long.lo)) / (Math.log(long.hi) - Math.log(long.lo))
    for (const point of long.points) expect(point.y).toBeCloseTo(longY(point.p), 12)
  }
  const linear = M.historyGeometry({ ...weekly, range: "2Y" })
  const linearY = p => 1 - (p - linear.lo) / (linear.hi - linear.lo)
  for (const point of linear.points) expect(point.y).toBeCloseTo(linearY(point.p), 12)
})

// A price at or under zero is none, as a zero high or low is: a day's
// negative price, zero previous close, and negative first close; a range's
// zero previous close and negative first close, its START then its first
// good close, its long range still on a log scale. No "-5.00" on every
// coin, no "0.00%", no "START 0.00", no cliff at the chart's left.
test("a price at or under zero in an answer is left out", () => {
  const day = fixture("aapl.json")
  const meta = day.chart.result[0].meta
  const closes = day.chart.result[0].indicators.quote[0].close
  const firstTime = day.chart.result[0].timestamp[0]
  meta.regularMarketPrice = -5
  meta.chartPreviousClose = 0
  closes[0] = -1
  const q = M.parseChart(day)
  expect([q.price, q.prevClose]).toEqual([null, null])
  expect(q.points.some(p => p.t === firstTime || p.p <= 0)).toBe(false)
  // With no previous close the day's prints set its scale alone, and it
  // draws no dashed line: a null close would draw one at zero, the day
  // squeezed flat against the top.
  const day1 = M.chartGeometry(q, calendars)
  const ys = day1.points.map(p => p.y)
  expect(day1.baselineY).toBeNull()
  expect(Math.max(...ys) - Math.min(...ys)).toBeGreaterThan(0.8)
  const year = fixture("history/aapl-5y.json")
  year.chart.result[0].meta.chartPreviousClose = 0
  year.chart.result[0].indicators.quote[0].close[0] = -1
  year.chart.result[0].indicators.quote[0].low[1] = 0
  const h = M.parseHistory(year, "5Y")
  const secondClose = year.chart.result[0].indicators.quote[0].close[1]
  expect(h.bars[0].t).toBe(year.chart.result[0].timestamp[1])
  expect([h.baseline, h.bars[0].l]).toEqual([secondClose, null])
  const geometry = M.historyGeometry(h)
  const logY = p => 1 - (Math.log(p) - Math.log(geometry.lo)) / (Math.log(geometry.hi) - Math.log(geometry.lo))
  for (const point of geometry.points) expect(point.y).toBeCloseTo(logY(point.p), 12)
})

test("history scrub lookup snaps to a bar and maps its timestamp back", () => {
  const history = M.parseHistory(fixture("history/aapl-1y.json"), "1Y")
  const middle = history.bars[125]
  expect(M.historyBarAt(history, 0.5)).toBe(middle)
  expect(M.historyFraction(history, middle.t)).toBe(0.5)
  expect(M.historyBarAt(history, -1)).toBe(history.bars[0])
  expect(M.historyBarAt(history, 2)).toBe(history.bars[history.bars.length - 1])
  expect(M.historyFraction(history, history.bars[0].t - 1)).toBe(-1)
  expect(M.historyFraction(history, history.bars[history.bars.length - 1].t + 1)).toBe(-1)
})

// A range's high and low, each with its bar's place and its date, as its
// chart's marks show them (`rangeEnds`, `rangeMarks`).
const marksOf = (h, q) => M.rangeMarks(h, M.rangeEnds(h, null, q), q)

test("a range marks its high and low on its chart, over their bars, with their dates", () => {
  const aapl = M.parseHistory(fixture("history/aapl-1y.json"), "1Y")
  const week = M.parseHistory(fixture("history/nest-5d.json"), "1W")
  const month = M.parseHistory(fixture("history/nest-1mo.json"), "1M")
  const fab = M.parseHistory(fixture("history/fab-max.json"), "All")
  const weekly = M.parseHistory(fixture("history/aapl-5y.json"), "5Y")
  const marks = h => {
    const m = marksOf(h)
    return `HIGH ${m.high.price} ${m.high.date} · LOW ${m.low.price} ${m.low.date}`
  }
  expect(marks(aapl)).toBe("HIGH 344.57 29 JUL 2026 · LOW 229.02 12 SEP 2025")
  expect(marks(week)).toBe("HIGH 254.74 8 SEP · LOW 209.40 4 SEP")
  expect(marks(month)).toBe("HIGH 280.83 17 AUG · LOW 194.80 1 SEP")
  expect(marks(fab)).toBe("HIGH 142.92 1 AUG 2025 · LOW 16.60 30 APR 2026")
  // The year whole, as the scrub writes it: "JAN 23" would read as 23
  // January.
  expect(marks(weekly)).toBe("HIGH 344.57 JUL 2026 · LOW 124.17 JAN 2023")
  // Each stands where the chart draws the bar that made it.
  for (const h of [aapl, week, month, fab, weekly]) {
    const m = marksOf(h)
    const highs = h.bars.map(b => b.h).filter(Number.isFinite)
    const lows = h.bars.map(b => b.l).filter(Number.isFinite)
    expect(M.historyBarAt(h, m.high.x).h).toBe(Math.max(...highs))
    expect(M.historyBarAt(h, m.low.x).l).toBe(Math.min(...lows))
  }
  // No bars, no marks.
  expect(marksOf({ ...week, bars: [] })).toBeNull()
  // A weekly bar names no day, so it carries its year even when the whole
  // period sits inside one.
  const oneYear = {
    ...weekly, interval: "1wk",
    bars: weekly.bars.filter(bar => bar.t >= 1767225600 && bar.t < 1798761600)
  }
  expect(M.historySpansYears(oneYear)).toBe(false)
  expect(marks(oneYear)).toMatch(/^HIGH [\d.]+ [A-Z]{3} 2026 · LOW [\d.]+ [A-Z]{3} 2026$/)
  expect(M.historyScrubForms(aapl, aapl.bars[0])[0]).toBe("12 SEP 2025 · 234.07")
  expect(M.historyScrubForms(week, week.bars[0])[0]).toBe("4 SEP 09:30 · 213.58")
  expect(M.historyScrubForms({ ...week, interval: "30m" }, week.bars[0])[0]).toBe("4 SEP 09:30 · 213.58")
  expect(M.historyScrubForms(month, month.bars[0])[0]).toBe("12 AUG 09:30 · 233.17")
  expect(M.historyScrubForms({ ...week, interval: "1wk" }, week.bars[0])[0]).toBe("WEEK OF 4 SEP · 213.58")
  expect(M.historyScrubForms({ ...aapl, interval: "1mo" }, aapl.bars[0])[0]).toBe("SEP 2025 · 234.07")
  expect(M.historyScrubForms({ ...aapl, interval: "3mo" }, aapl.bars[0])[0]).toBe("SEP 2025 · 234.07")
})

// A range is fetched each hour and the quote each minute, so a range's last
// bar can trail the day: while that bar holds the quote's session, the
// quote's day high and low count as its own. RGTI made its 52-week low of
// 11.77 on 14 October 2026; its 1Y answer from before had the day at 12.05.
test("a range's line and marks take in the quote's day while its last bar is that day's", () => {
  const saved = name => ({
    q: M.parseChart(fixture(`first-day-2026-10-14/${name}-day.json`)),
    h: M.parseHistory(fixture(`first-day-2026-10-14/${name}-1y.json`), "1Y")
  })
  const rgti = saved("rgti")
  const earlier = { ...rgti.h, bars: rgti.h.bars.map((b, i, all) => (i === all.length - 1 ? { ...b, l: 12.05 } : b)) }
  const low = marksOf(earlier, rgti.q).low
  expect(`${low.price} ${low.date}`).toBe("11.77 14 OCT 2026")
  expect(M.historyBarAt(earlier, low.x)).toBe(earlier.bars[earlier.bars.length - 1])
  expect(M.rangeLine(earlier, M.rangeEnds(earlier, null, rgti.q), rgti.q).range.lowText).toBe("11.77")
  // A week's bar holds each day of its week. Yahoo's weekly answer ends
  // with the week of Monday 7 September and the live moment, Friday the
  // 11th, as a bar of its own: Thursday is that week's, and the Monday after
  // the live moment is not.
  const weekly = M.parseHistory(fixture("history/aapl-5y.json"), "5Y")
  const weekOf = weekly.bars[weekly.bars.length - 2]
  expect(weekly.bars[weekly.bars.length - 1].t).toBe(weekly.liveAt)
  const thursday = { figuresDay: weekOf.t + 3 * DAY, dayHigh: 400, dayLow: 300, priceDigits: 2 }
  expect(marksOf(weekly, thursday).high.price).toBe("400.00")
  expect(marksOf(weekly, { ...thursday, figuresDay: weekOf.t + 7 * DAY }).high.price).toBe("344.57")
  // A chart with no bar for the quote's day yet leaves it out: the Nikkei's
  // 1Y answer, its 14 October bar taken away, ends on 13 October.
  const n225 = saved("n225")
  expect(marksOf({ ...n225.h, unclosed: [] }, { ...n225.q, dayHigh: 80000 }).high.price).toBe("72,832")
  // With that bar, sent without its close, the day is the quote's.
  expect(marksOf(n225.h, { ...n225.q, dayHigh: 80000 }).high).toEqual({ x: 1, price: "80,000", date: "14 OCT 2026" })
  // An intraday bar holds only part of a day, so a day's high is not its.
  const week = M.parseHistory(fixture("history/nest-5d.json"), "1W")
  const lastBar = week.bars[week.bars.length - 1]
  expect(marksOf(week, { figuresDay: lastBar.t, dayHigh: 999, dayLow: 1, priceDigits: 2 }).high.price).toBe("254.74")
})

// Yahoo's daily answer for Tokyo leaves the day's close out after the
// close, with the day's high, low, and shares: Toyota's 1Y on 16 October.
// They count in the range's high, low, and VOL; the chart draws closes, so
// it leaves the bar out, and no close is made up: the last three days must
// not read VOL 51.4M and a high of 3,046.
test("a bar without a close counts its high, low, and volume in the range, and is not drawn", () => {
  const json = fixture("history/7203-t-1y.json")
  const year = M.parseHistory(json, "1Y")
  expect(year.unclosed).toEqual([{ t: Date.UTC(2026, 9, 16) / 1000, o: 3051, h: 3096, l: 3047, c: null, v: 25007500 }])
  expect(year.bars.length).toBe(242)
  expect(year.bars.every(bar => bar.c > 0)).toBe(true)
  // The answer's last three days, as Yahoo sent them.
  const three = structuredClone(json)
  const result = three.chart.result[0]
  result.timestamp = result.timestamp.slice(-3)
  for (const key of Object.keys(result.indicators.quote[0])) result.indicators.quote[0][key] = result.indicators.quote[0][key].slice(-3)
  const days = M.parseHistory(three, "1Y")
  expect(days.bars.length).toBe(2)
  const line = said(M.rangeLine(days, M.rangeEnds(days, null, null), null))
  expect(line.split(" · ").filter(part => part.startsWith("VOL"))).toEqual(["VOL 76.4M"])
  expect(M.periodStats(days).high).toEqual({ p: 3096, t: Date.UTC(2026, 9, 16) / 1000 })
  // Its mark stands at the chart's right edge, dated the day it was made.
  const high = marksOf(days, null).high
  expect([high.x, high.price, high.date]).toEqual([1, "3,096.00", "16 OCT"])
  // Without its volume, the day's high still counts, and VOL is left out
  // rather than undercount the range.
  const noVolume = { ...days, unclosed: days.unclosed.map(bar => ({ ...bar, v: null })) }
  expect([M.rangeVolume(noVolume), M.periodStats(noVolume).high.p]).toEqual(["", 3096])
})

// On a range, the first info line is the range's: its low and high (as its
// marks) with the price between them, then START, the price its change is
// measured from, and VOL over the range, where the day's OPEN and VOL sit.
test("a range's line gives its low and high, START, and the volume traded over it", () => {
  const nest = M.parseChart(fixture("nest-2026-09-11-day-prepost.json"))
  const rangeLine = (h, q) => said(M.rangeLine(h, M.rangeEnds(h, null, q), q))
  const week = M.parseHistory(fixture("history/nest-5d.json"), "1W")
  expect(rangeLine(week, nest)).toBe("1W · 209.40–254.74 @224.55 · START 210.63 · VOL 69.5M")
  // Yahoo's weekly answer ends with the live moment as a bar of its own,
  // whose volume the week's bar before it already counts: 80.5B with it.
  expect(rangeLine(M.parseHistory(fixture("history/aapl-5y.json"), "5Y"), quote))
    .toBe("5Y · 124.17–344.57 @325.13 · START 148.97 · VOL 80.4B")
  // An index has its volume; with no quote the tick is the last close.
  expect(rangeLine(M.parseHistory(fixture("history/gspc-1y.json"), "1Y"), null))
    .toBe("1Y · 6,316.91–7,844.52 @7,735.81 · START 6,629.07 · VOL 1.34T")
  // A bar whose volume isn't known leaves VOL out rather than undercount
  // it, and so does an answer with no volume above zero.
  expect(rangeLine({ ...week, bars: week.bars.map((b, i) => (i === 3 ? { ...b, v: null } : b)) }, nest).endsWith("VOL _")).toBe(true)
  expect(rangeLine({ ...week, bars: week.bars.map(b => ({ ...b, v: 0 })) }, nest).endsWith("VOL _")).toBe(true)
})

// A listing younger than its range says so under its change, with the day
// it began, in place of the range's name. All starts where the listing
// does, so it never says SINCE; nor does a listing whose start Yahoo
// doesn't give.
test("a listing younger than its range says SINCE its first day under the change", () => {
  const fig = fixture("history/fig-max.json")
  const label = (range, h) => M.historyRowModel(h || M.parseHistory(fig, range), quote, 0).periodLabel
  expect(label("2Y")).toBe("SINCE 31 JUL 2025")
  expect(label("All")).toBe("ALL")
  expect(label("2Y", { ...M.parseHistory(fig, "2Y"), firstTradeDate: null })).toBe("2Y")
  expect(label("1Y", M.parseHistory(fixture("history/aapl-1y.json"), "1Y"))).toBe("1Y")
})

test("historyRowModel uses the quote until a historical bar is scrubbed", () => {
  const history = M.parseHistory(fixture("history/aapl-1y.json"), "1Y")
  const resting = M.historyRowModel(history, quote, 0)
  expect(resting).toMatchObject({ price: 325.13, asOf: 1788292801, changeText: "+41.34%", periodLabel: "1Y", dayUp: true })
  const bar = history.bars[20]
  expect(M.historyRowModel(history, quote, bar.t)).toMatchObject({ price: 245.27000427246094, asOf: bar.t, changeText: "+6.63%" })
  // The direction follows the change shown: up at rest, down on a bar under
  // the baseline.
  const below = {
    symbol: "TEST", range: "1Y", interval: "1d", baseline: 300,
    bars: [{ t: 1, h: 251, l: 249, c: 250 }, { t: 2, h: 281, l: 279, c: 280 }]
  }
  expect(M.historyRowModel(below, { ...quote, price: 325 }, 0).dayUp).toBe(true)
  expect(M.historyRowModel(below, quote, 1)).toMatchObject({ price: 250, tone: "down", dayUp: false })
  const fallback = M.historyRowModel(history, null, 0)
  expect(fallback).toMatchObject({
    symbol: "AAPL", name: "AAPL", price: 332.2699890136719,
    asOf: history.bars[history.bars.length - 1].t
  })
  expect(M.historyRowModel(null, quote, 0)).toBeNull()
})

// ---------------------------------------------------------------- overnight

// Robinhood's saved span=day answer for a moment, by symbol: the bars that
// traded, and how far it reached.
const traded = (set, symbols) => M.parseOvernight(fixture(`moments/${set}/robinhood-day.json`), symbols)
const savedDay = (set, name) => M.parseChart(fixture(`moments/${set}/${name}.json`))
const at = (date, clock) => M.epochAt(US, date, clock)

test("Robinhood's answer keeps only the bars that traded, by the symbols asked for", () => {
  // Saved Friday 2 October at 13:40 New York. bounds=24_5 still fills SILK's
  // quiet five-minute slots with flat interpolated bars; GRIT.TO, a Toronto
  // listing Robinhood does not trade, comes back empty in its place.
  const raw = fixture("moments/day/robinhood-day.json").results
  const bars = traded("day", ["NEST", "SILK", "REED", "GRIT.TO"])
  expect(raw[1].historicals.length).toBe(288)
  expect(bars.SILK.bars.length).toBe(288 - raw[1].historicals.filter(b => b.interpolated).length)
  expect(bars.NEST.bars.filter(b => b.s === "overnight").length).toBe(96)
  expect(bars.REED.bars.filter(b => b.s === "overnight")).toEqual([])
  expect(bars["GRIT.TO"]).toEqual({ bars: [], from: null, through: null })
  // It reaches its newest slot, traded or not: REED traded in none of
  // them, and still reaches as far as SILK and NEST.
  expect(bars.REED.through).toBe(Date.parse(raw[2].historicals.at(-1).begins_at) / 1000)
  expect([bars.NEST.through, bars.SILK.through]).toEqual([bars.REED.through, bars.REED.through])
  // Asked out of the order it answers in, an answer names another symbol
  // and is no answer for the one asked.
  expect(M.parseOvernight(fixture("moments/day/robinhood-day.json"), ["SILK", "NEST"]))
    .toEqual({ SILK: { bars: [], from: null, through: null }, NEST: { bars: [], from: null, through: null } })
  expect(M.parseOvernight({ chart: {} }, ["NEST"])).toBeNull()
})

test("a refresh within half an hour asks Robinhood for the last hour, which brings the day in hand up to what a day asked then holds", () => {
  // Saved Wednesday 7 October at 00:05 and 01:00 New York, 55 minutes
  // apart, as a night's refreshes come with the popup closed between.
  const earlier = traded("2026-10-07-0005", ["NEST"]).NEST
  const later = fixture("moments/2026-10-07-0100/robinhood-day.json")
  const hour = { results: later.results.map(r => ({ ...r, span: "hour", historicals: r.historicals.slice(-12) })) }
  const joined = M.joinHour(earlier, M.parseOvernight(hour, ["NEST"]).NEST)
  const day = M.parseOvernight(later, ["NEST"]).NEST
  expect(joined.through).toBe(day.through)
  expect(joined.bars.filter(b => b.t >= day.from)).toEqual(day.bars)
  // The older prints stay: a chart of the day before still has them.
  expect(joined.bars[0]).toEqual(earlier.bars[0])
  // An hour that answers nothing keeps the prints in hand.
  expect(M.joinHour(earlier, { bars: [], from: null, through: null })).toEqual({ bars: earlier.bars, through: earlier.through })
  // Ten minutes after the newest slot in hand, the hour reaches back past
  // it; an hour after, it would leave slots out, so the day is asked again,
  // as it is for a listing never answered.
  expect(M.overnightSpan({ through: earlier.through }, earlier.through + 10 * 60)).toBe("hour")
  expect(M.overnightSpan({ through: earlier.through }, earlier.through + 60 * 60)).toBe("day")
  expect(M.overnightSpan(undefined, earlier.through)).toBe("day")
  expect(M.overnightSpan({ through: null }, earlier.through)).toBe("day")
})

test("the prints Stonks keeps for a listing hold every one its 1D chart draws, however long a surface stays open", () => {
  // Every saved Robinhood answer, oldest first, each joined on to what is in
  // hand as an hour's answer is: weeks of prints, far past MOST_PRINTS,
  // where a real surface is asked for a day again after half an hour. At
  // each moment, each listing's chart is the one every print sent so far
  // would draw.
  const sets = readdirSync(join(fixtures, "moments")).filter(set => existsSync(join(fixtures, "moments", set, "robinhood-day.json")))
    .map(set => {
      const answer = fixture(`moments/${set}/robinhood-day.json`)
      const parsed = M.parseOvernight(answer, answer.results.map(r => r.symbol))
      return { set, parsed, through: Math.max(...Object.values(parsed).map(a => a.through ?? 0)) }
    })
    .sort((a, b) => a.through - b.through)
  const kept = {}
  const sent = {}
  let drawn = 0
  for (const { set, parsed } of sets) {
    for (const [symbol, answer] of Object.entries(parsed)) {
      kept[symbol] = kept[symbol] ? M.joinHour(kept[symbol], answer) : answer
      sent[symbol] = sent[symbol] || new Map()
      for (const bar of answer.bars) sent[symbol].set(bar.t, bar)
    }
    for (const file of readdirSync(join(fixtures, "moments", set))) {
      if (!file.endsWith(".json") || file.startsWith("robinhood")) continue
      const quote = M.parseChart(fixture(`moments/${set}/${file}`))
      const symbol = quote && M.robinhoodSymbol(quote.symbol)
      if (!quote || !quote.session.regular || !kept[symbol]?.bars.length) continue
      const all = { bars: [...sent[symbol].values()].sort((a, b) => a.t - b.t), through: kept[symbol].through }
      const chart = M.dayChart(quote, all, calendars)
      if (!chart.latest) continue
      expect([set, file, M.dayChart(quote, kept[symbol], calendars)]).toEqual([set, file, chart])
      drawn++
    }
  }
  expect(Math.max(...Object.values(kept).map(k => k.bars.length))).toBe(M.MOST_PRINTS)
  expect(drawn).toBeGreaterThan(100)
})

test("Robinhood's instruments say which listings it trades all day, by the symbols asked for", () => {
  // Saved Wednesday 7 October: NEST and SPY trade on its 24 Hour Market,
  // KILN and BOLT do not. Results come in Robinhood's own order; one it does
  // not list is not all-day, and a share class is asked with a dot.
  const answer = fixture("moments/listings-2026-10-07-1455/robinhood-instruments.json")
  expect(M.parseAllDay(answer, ["KILN", "NEST", "BOLT", "SPY", "ZZZZQ"]))
    .toEqual({ KILN: false, NEST: true, BOLT: false, SPY: true, ZZZZQ: false })
  expect(M.parseAllDay({ results: [{ symbol: "BRK.B", all_day_tradability: "tradable" }] }, ["BRK-B"])).toEqual({ "BRK-B": true })
  expect(M.allDayUrl(["BRK-B", "NEST"])).toContain("?symbols=BRK.B,NEST")
  expect(M.parseAllDay({ chart: {} }, ["NEST"])).toBeNull()
})

test("which listings have an overnight market comes from Yahoo, never from Robinhood's answer", () => {
  // Asked for SPX, ^GSPC, BTC, and BTC-USD, Robinhood answers the index and
  // the cryptocurrency with nothing, and BTC with the bars of a bitcoin ETF.
  const answer = M.parseOvernight(fixture("moments/robinhood-index-crypto.json"), ["SPX", "^GSPC", "BTC", "BTC-USD"])
  expect([answer.SPX.bars.length, answer["^GSPC"].bars.length, answer["BTC-USD"].bars.length]).toEqual([0, 0, 0])
  expect(answer.BTC.bars.length).toBeGreaterThan(0)
  // So the quote decides: a stock or an ETF on a US exchange.
  expect(M.hasOvernight(savedDay("day", "nest"), calendars)).toBe(true)
  expect(M.hasOvernight(M.parseChart(fixture("spy-2026-09-11-day-prepost.json")), calendars)).toBe(true)
  expect(M.hasOvernight(savedDay("day", "gspc"), calendars)).toBe(false)
  expect(M.hasOvernight(btc, calendars)).toBe(false)
  expect(M.hasOvernight(shop, calendars)).toBe(false)
  expect(M.hasOvernight(M.parseChart(fixture("7203-t-day.json")), calendars)).toBe(false)
  expect(M.hasOvernight(M.parseChart(fixture("shel-l-day.json")), calendars)).toBe(false)
  // One request for the list, a share class in Robinhood's spelling.
  expect(M.overnightUrl(["NEST", "BRK-B"], "day"))
    .toBe("https://api.robinhood.com/marketdata/historicals/?symbols=NEST,BRK.B&interval=5minute&span=day&bounds=24_5")
  expect(M.overnightUrl(["NEST"], "hour")).toContain("&span=hour&")
})

// The 1D chart of a saved moment, with the quote it was built from.
// Robinhood's answer is read for the symbols it holds, in its order.
const dayAt = (set, name) => {
  const asked = fixture(`moments/${set}/robinhood-day.json`).results.map(r => r.symbol)
  const quote = savedDay(set, name)
  return { ...M.dayChart(quote, traded(set, asked)[name.toUpperCase()], calendars), quote }
}
// The line under the price at `now`, as the hero reads it.
const stripAt = (built, now) => M.extendedStack(built.quote, built.latest, now, built.day)

test("the 1D chart is the New York calendar day, midnight to midnight, the hours to come empty", () => {
  // Wednesday 7 October, 11:53: Robinhood's screen draws the day from
  // midnight, the night and the pre-market before the open, and nothing past now.
  const quote = savedDay("2026-10-07-1153", "nest")
  const { day } = dayAt("2026-10-07-1153", "nest")
  expect(M.chartSpan(day)).toMatchObject({ start: at("2026-10-07", "00:00"), end: at("2026-10-08", "00:00") })
  expect(day.points[0].t).toBeGreaterThanOrEqual(at("2026-10-07", "00:00"))
  const sessions = day.points.map(p => p.s).filter((s, i, all) => s !== all[i - 1])
  expect(sessions).toEqual(["overnight", "pre", "reg"])
  expect(M.chartGeometry(day).points.at(-1).x).toBeCloseTo((11 * 60 + 50) / 1440, 2)
  // Ticks at the night's end, the close, and tonight's start.
  expect(M.chartGeometry(day).ticks.map(x => M.timeAtFraction(day, x)))
    .toEqual([at("2026-10-07", "04:00"), at("2026-10-07", "16:00"), at("2026-10-07", "20:00")])
  // Measured from Tuesday's close, the quote's previous close.
  expect(day.prevClose).toBe(quote.prevClose)
})

test("before the day's first print the chart stays on yesterday, and the line under the price names the night", () => {
  // Wednesday 00:05: Robinhood's newest bar is Tuesday 23:55.
  const { day, latest } = dayAt("2026-10-07-0005", "nest")
  expect(M.chartSpan(day).start).toBe(at("2026-10-06", "00:00"))
  expect(M.lastPrintTime(day)).toBe(at("2026-10-06", "23:55"))
  expect(stripAt(dayAt("2026-10-07-0005", "nest"), at("2026-10-07", "00:05"))).toMatchObject({ label: "OVERNIGHT", time: "23:55" })
})

// Wherever the pointer is on a 1D chart, its change and its animal say
// where that price stands against the close it reads from: the dashed
// line's, or, past the session's close, that close (`readsClose`).
const againstDashedLine = (day, where) => {
  for (const p of day.points) {
    const base = M.readsClose(day, p.t) ? M.regularClose(day) : M.dayBase(day)
    const row = M.rowModel(day, p.t, "pct")
    const flat = row.dayTone === "flat"
    const side = flat ? "" : row.price > base ? "bull" : "bear"
    if (M.animalKind(row) !== side || (!flat && row.dayUp !== row.price > base)) return `${where} ${p.t} ${row.priceText} ${row.changeText} ${M.animalKind(row)} vs ${M.money(base)}`
  }
  return `${where} all against ${M.money(M.dayBase(day))}`
}

test("once a listing trades after its close, its newest price is on top, measured from that close, and a scrub of the night reads the same", () => {
  // Wednesday 01:00: NEST closed Tuesday at 249.87, +7.44%, and traded at
  // 248.04 at 00:50. The price on top is 248.04, −0.73% from Tuesday's
  // close, with a bear, its session and time said beside it; Tuesday's
  // close and move go on the line beneath. A scrub of that print reads the
  // same −0.73%, never +6.65% from Monday's close, the dashed line's, which
  // Tuesday's own prints still read from. Before, the close was on top and
  // the scrub read +6.65%.
  const quote = savedDay("2026-10-07-0100", "nest")
  const built = dayAt("2026-10-07-0100", "nest")
  const { day, latest } = built
  const one = at("2026-10-07", "01:00")
  const newest = M.newestPrint(quote, latest, calendars)
  expect(newest).toEqual({ t: latest.t, p: 248.04, phase: "overnight" })
  const top = M.rowModel(quote, 0, "pct", newest)
  expect([top.priceText, top.changeText, M.animalKind(top)]).toEqual(["248.04", "\u22120.73%", "bear"])
  expect(M.newestCaptions(quote, newest, one, calendars)[0]).toBe("OVERNIGHT 00:50")
  expect(M.closeLine(quote, M.exchangeDay(quote, one), "pct")).toMatchObject({ label: "TUE CLOSE", price: "249.87", changeText: "+7.44%", tone: "up" })
  expect(M.rowModel(day, latest.t, "pct")).toMatchObject({ changeText: "\u22120.73%", dayUp: false })
  // Since the open too: no session has opened since Tuesday's close.
  expect(M.rowModel(day, latest.t, "open").changeText).toBe(M.rowModel(quote, 0, "open", newest).changeText)
  expect(M.rowModel(quote, 0, "open", newest).changeText).toBe("\u22120.73%")
  expect(M.dayBaselineText(day, M.exchangeDay(day, one), latest.t)).toBe("TUE CLOSE 249.87")
  expect(againstDashedLine(day, "01:00")).toBe(`01:00 all against ${M.money(quote.prevClose)}`)
  expect(M.dayBase(day)).toBe(quote.prevClose)
  const noon = quote.points.find(p => p.t >= at("2026-10-06", "12:00")).t
  expect(M.rowModel(day, noon, "pct").changeText).toBe(M.rowModel(quote, noon, "pct").changeText)
  expect(M.dayBaselineText(day, M.exchangeDay(day, one), noon)).toBe("CLOSE BEFORE TUE 232.57")
  // Yahoo failing while Robinhood answers: the warning names the time of
  // the price on top, the night's, not Tuesday's close.
  const failed = M.freshness({ status: "failed", answeredAt: one - 60 }, quote, one, 0, false, newest)
  expect(M.freshnessText(failed, quote, calendars)).toBe("REFRESH FAILED · OVERNIGHT 00:50")
  // Read with no newest price, the close is on top.
  expect(M.rowModel(quote, 0, "pct").changeText).toBe("+7.44%")
})

// A watch moment's listings as the service holds them, answered at the
// moment: their quotes, Robinhood's prints and word on all-day trading, and
// each one's newest price since its close (`newestPrints`).
const topsAt = set => {
  const now = answeredAt(set)
  const asked = fixture(`moments/${set}/robinhood-day.json`).results.map(r => r.symbol)
  const prints = traded(set, asked)
  const ins = M.parseAllDay(fixture(`moments/${set}/robinhood-instruments.json`), asked)
  const quotes = {}, nights = {}, allDay = {}
  for (const file of readdirSync(join(fixtures, "moments", set))) {
    if (!file.endsWith(".json") || file.startsWith("robinhood")) continue
    const q = M.parseChart(fixture(`moments/${set}/${file}`), cents, now)
    quotes[q.symbol] = q
    const rs = M.robinhoodSymbol(q.symbol)
    if (rs in ins) {
      allDay[q.symbol] = { status: "ok", allDay: ins[rs], at: 0 }
      nights[q.symbol] = { status: "ok", ...prints[rs] }
    }
  }
  const symbols = Object.keys(quotes)
  const newest = M.newestPrints(symbols, quotes, nights, allDay, calendars)
  // What a listing shows on top, as its row, the pill, and the panel read it.
  const top = s => {
    const row = M.rowModel(quotes[s], 0, "pct", newest[s] || null)
    return [row.priceText, row.changeText, newest[s] ? M.newestCaptions(quotes[s], newest[s], now, calendars)[0] : "",
      newest[s] ? M.closeLine(quotes[s], M.exchangeDay(quotes[s], now), "pct").label : ""].join(" ")
  }
  return { now, quotes, nights, allDay, symbols, newest, top }
}

test("in every phase, a stock that has traded since its close shows that newest price on top, the same on the pill, the rows and the panel", () => {
  // The weekend watch's moments, 25 and 26 October. NBIS and JNJ trade at
  // night on Robinhood; PSIX doesn't; BRK-A and CVR hadn't traded since
  // their close; an index, a coin, and London, Tokyo and Toronto have no
  // newest price, ever.
  const phases = {
    "watch-2026-10-25-1000": ["NBIS 158.74 0.00% AFTER HOURS FRI 19:59 FRI CLOSE", "JNJ 263.16 −0.25% AFTER HOURS FRI 18:46 FRI CLOSE",
      "PSIX 45.69 +0.13% AFTER HOURS FRI 19:00 FRI CLOSE"],
    "watch-2026-10-25-2335": ["NBIS 152.51 −3.92% OVERNIGHT 23:30 FRI CLOSE", "JNJ 264.11 +0.11% OVERNIGHT 23:25 FRI CLOSE",
      "PSIX 45.69 +0.13% AFTER HOURS FRI 19:00 FRI CLOSE"],
    "watch-2026-10-26-0100": ["NBIS 153.07 −3.57% OVERNIGHT 00:55 FRI CLOSE", "JNJ 264.05 +0.09% OVERNIGHT 00:35 FRI CLOSE"],
    "watch-2026-10-26-0420": ["NBIS 151.28 −4.70% PRE-MARKET 04:19 FRI CLOSE", "JNJ 264.55 +0.28% PRE-MARKET 04:06 FRI CLOSE"],
    "watch-2026-10-26-1200": ["NBIS 163.31 +2.88%  ", "JNJ 265.78 +0.75%  "],
    "watch-2026-10-26-1800": ["NBIS 155.34 +1.35% AFTER HOURS 17:58 CLOSE", "JNJ 266.42 +0.05% AFTER HOURS 17:30 CLOSE",
      "PSIX 47.15 0.00% AFTER HOURS 16:56 CLOSE", "CVR 9.82 −6.48%  "],
    "watch-2026-10-26-2005": ["NBIS 156.80 +2.30% OVERNIGHT 20:00 CLOSE", "JNJ 266.30 0.00% AFTER HOURS 19:57 CLOSE"]
  }
  for (const [set, expected] of Object.entries(phases)) {
    const at = topsAt(set)
    expect([set, ...expected.map(e => e.split(" ")[0] + " " + at.top(e.split(" ")[0]))]).toEqual([set, ...expected])
    for (const s of ["BRK-A", "^GSPC", "BTC-USD", "SHEL.L", "7203.T", "SHOP.TO"]) expect([set, s, at.newest[s]]).toEqual([set, s, undefined])
    // The panel reads the newest price from its chart's newest print, the
    // rows and the pill from the list's: the same one. A row's line and the
    // pill's draw the day the 1D chart does.
    for (const s of at.symbols) {
      const view = M.viewChart(s, "1D", at.quotes, {}, {}, at.nights, at.allDay, calendars)
      expect([set, s, M.newestPrint(at.quotes[s], view.latest, calendars)]).toEqual([set, s, at.newest[s] || null])
      expect([set, s, M.dayDrawn(at.quotes[s], at.nights[s], at.allDay[s], calendars).day]).toEqual([set, s, view.day])
    }
  }
  // Sunday 23:35: JNJ's row and pill draw tonight's trades, ending on its
  // newest price above Friday's close, beside its +0.11%, not Friday's day,
  // which fell 1.42%.
  {
    const at = topsAt("watch-2026-10-25-2335")
    const day = M.dayDrawn(at.quotes.JNJ, at.nights.JNJ, at.allDay.JNJ, calendars).day
    const line = M.chartGeometry(day, calendars)
    expect([day.points.at(-1).p, line.points.at(-1).y < line.baselineY]).toEqual([264.11, true])
  }
  // Sunday 23:35, the list sorted by change and its up and down count read
  // the price on top: NBIS, −3.92% tonight, is the list's worst, though
  // Friday's close was down only 0.27%.
  const sunday = topsAt("watch-2026-10-25-2335")
  const sorted = M.sortedSymbols(sunday.symbols, sunday.quotes, "pct", false, "pct", sunday.newest)
  expect(sorted.at(-1)).toBe("NBIS")
  const breadth = M.listBreadth(sunday.symbols, sunday.quotes, 0, "pct", sunday.newest)
  const tones = sunday.symbols.map(s => M.rowModel(sunday.quotes[s], 0, "pct", sunday.newest[s] || null).tone)
  expect([breadth.up, breadth.down]).toEqual([tones.filter(t => t === "up").length, tones.filter(t => t === "down").length])
  expect(M.sortedSymbols(sunday.symbols, sunday.quotes, "pct", false, "pct", null).at(-1)).not.toBe("NBIS")
  // A night's price dims once Robinhood has missed a bar.
  const nbis = sunday.newest.NBIS
  expect([M.newestStale(nbis, nbis.t + 20 * 60), M.newestStale(nbis, nbis.t + 20 * 60 + 1)]).toEqual([false, true])
  // A row's name line and the pill's hover say its session and time.
  expect(M.newestNote(sunday.quotes.NBIS, nbis, sunday.now, calendars)).toBe("Overnight 23:30")
  expect(M.newestNote(sunday.quotes.PSIX, sunday.newest.PSIX, sunday.now, calendars)).toBe("After hours Fri 19:00")
  // On 1W, 1M and 1Y too, NBIS's line ends on its newest price, the price
  // on top, as Robinhood's ranges did at 20:00 on 28 October: the move from
  // the range's start to it, said under it by the range's name and then the
  // price's session and time, so the week's move never reads as the
  // night's beside the row's; a scrub at the line's end reading it, and the
  // range's low taking it. The range's volume stays Yahoo's bars'.
  for (const [set, moment, when] of [["watch-2026-10-25-2335", "2026-10-25-2335", "OVERNIGHT 23:30"], ["watch-2026-10-26-2005", "2026-10-26-2005", "OVERNIGHT 20:00"]]) {
    const at = topsAt(set)
    const top = M.rowModel(at.quotes.NBIS, 0, "pct", at.newest.NBIS)
    for (const [range, span] of [["1W", "5d"], ["1M", "1mo"], ["1Y", "1y"]]) {
      const where = `${set} ${range}`
      const raw = M.parseHistory(fixture(`history/nbis-${moment}-${span}.json`), range)
      const chart = M.viewChart("NBIS", range, at.quotes, {}, { ["NBIS|" + range]: { status: "ok", history: raw } }, at.nights, at.allDay, calendars)
      const history = chart.history
      const model = M.historyRowModel(history, at.quotes.NBIS, 0)
      const line = M.historyGeometry(history).points
      expect([where, model.priceText, model.newest, line.at(-1).p]).toEqual([where, top.priceText, at.newest.NBIS, at.newest.NBIS.p])
      expect([where, M.newestCaptions(at.quotes.NBIS, model.newest, at.now, calendars, model.periodLabel)[0]]).toEqual([where, `${range} · ${when}`])
      expect([where, model.changeText]).toEqual([where, M.pct((at.newest.NBIS.p - raw.baseline) / raw.baseline * 100)])
      expect([where, M.historyRowModel(history, at.quotes.NBIS, at.newest.NBIS.t).priceText]).toEqual([where, top.priceText])
      expect([where, M.rangeVolume(history)]).toEqual([where, M.rangeVolume(raw)])
    }
  }
  const week = M.viewChart("NBIS", "1W", sunday.quotes, {},
    { "NBIS|1W": { status: "ok", history: M.parseHistory(fixture("history/nbis-2026-10-25-2335-5d.json"), "1W") } }, sunday.nights, sunday.allDay, calendars).history
  expect(M.rangeEnds(week).low).toEqual({ p: 152.51, t: sunday.newest.NBIS.t })
})

test("before the open the day is measured from the last session's close, though Yahoo's previous close is the one before", () => {
  // Friday 23 October, 06:22: Yahoo's day is Friday's, its pre-market from
  // 04:00, while its quote is Thursday's close and its previous close
  // Wednesday's. The chart and its scrub must not measure AAPL's pre-market
  // from Wednesday's 343.99, green above it, while the line under the price
  // says it is down from Thursday's.
  const quote = savedDay("premarket-2026-10-23-0622", "aapl")
  expect([quote.price, quote.prevClose]).toEqual([348.22, 343.99])
  const fourFortyFive = at("2026-10-23", "04:45")
  const days = [M.dayChart(quote, { bars: [], through: null }, calendars).day, M.sessionDay(quote)]
  for (const day of [quote, ...days]) {
    const line = M.chartGeometry(day)
    expect(line.points.at(-1).y).toBeGreaterThan(line.baselineY)
    expect(M.rowModel(day, fourFortyFive, "pct")).toMatchObject({ priceText: "345.92", changeText: "\u22120.66%", dayUp: false })
  }
  for (const day of days) expect(M.dayBaselineText(day, M.exchangeDay(day, fourFortyFive))).toBe("PREV CLOSE 348.22")
  // The headline is still Thursday's close and Thursday's move.
  expect(M.rowModel(quote, 0, "pct").changeText).toBe("+1.23%")
  // NVDA the other way round: down on Thursday, up since.
  const nvda = savedDay("premarket-2026-10-23-0622", "nvda")
  expect(M.rowModel(nvda, fourFortyFive, "pct").changeText).toBe("+1.19%")
  expect(M.rowModel(nvda, 0, "pct").changeText).toBe("\u22124.40%")
})

test("in a session's first minute a quote still the last session's says nothing of its age, and is asked again within 15 s", () => {
  // Friday 23 October: Yahoo's answers held Thursday's quote until 09:30:09
  // (^GSPC) and 09:30:12 (AAPL): from 09:30:02 no US row may say "As of Thu
  // 16:00" until 09:30:46, when the rows asked at 09:29:46 next fall due.
  const bell = at("2026-10-23", "09:30")
  for (const name of ["aapl", "gspc"]) {
    const thursday = savedDay("bell-2026-10-23-0929", name)
    const opening = M.freshness({ status: "ok", answeredAt: bell }, thursday, bell + 2, 0, false)
    expect([name, opening.state, opening.live, M.freshnessText(opening, thursday, calendars)]).toEqual([name, "asking", false, ""])
    expect([name, quoteCadence(thursday, bell + 2, 60, false)]).toEqual([name, 15])
    // A minute on, a quote still Thursday's is old, and says so.
    const later = M.freshness({ status: "ok", answeredAt: bell + 60 }, thursday, bell + 61, 0, false)
    expect([name, M.freshnessText(later, thursday, calendars)]).toEqual([name, name === "aapl" ? "AS OF THU 16:00" : "AS OF THU 16:31"])
    expect([name, quoteCadence(thursday, bell + 61, 60, false)]).toEqual([name, 60])
    // The first answer with the session's price is live, asked each minute.
    const friday = savedDay("bell-2026-10-23-0930", name)
    expect([name, M.freshness({ status: "ok", answeredAt: bell + 12 }, friday, bell + 12, 0, false)])
      .toMatchObject([name, { state: "fresh", live: true }])
    expect([name, quoteCadence(friday, bell + 12, 60, false)]).toEqual([name, 60])
  }
})

test("before the open an index counts to the bell, closed, and its open goes when the stocks' does", () => {
  // Friday 23 October, 06:22: the S&P 500's periods are still Thursday's,
  // its current period Friday's; AAPL's day is Friday's already. The index
  // must not say "Closed · opens Fri 09:30" and "−0.41% open" while every
  // stock says "Pre-market · opens in 3h 11m" and "—": it says it in the
  // stocks' shape.
  const now = at("2026-10-23", "06:20")
  const read = (set, name, received) => M.parseChart(fixture(`moments/${set}/${name}.json`), cents, received)
  const gspc = read("premarket-2026-10-23-0622", "gspc", at("2026-10-23", "06:22"))
  const aapl = read("premarket-2026-10-23-0622", "aapl", at("2026-10-23", "06:22"))
  expect(M.statusForms(gspc, now, 0, calendars)).toEqual(["Closed · opens in 3h 10m", "Opens in 3h 10m"])
  expect(M.marketStatus(aapl, now, 0, calendars)).toBe("Pre-market · opens in 3h 10m")
  for (const q of [gspc, aapl]) expect([q.symbol, M.rowModel(q, 0, "open").changeLine]).toEqual([q.symbol, "—"])
  // At 01:00 the stocks' answers are still Tuesday's, and so is the
  // index's open, though Yahoo's current period is Wednesday's: the index
  // must not say "—" from midnight while its stocks show Tuesday's moves
  // since the open.
  const one = at("2026-10-07", "01:00")
  const night = ["gspc", "nest", "spy", "kiln"].map(name => read("listings-2026-10-07-0100", name, one))
  expect(night.map(q => M.rowModel(q, 0, "open").changeLine)).toEqual(["+0.17% open", "+5.33% open", "+0.12% open", "+4.65% open"])
  // A scrub of the index's Thursday still reads from Thursday's open.
  expect(M.rowModel(gspc, at("2026-10-22", "10:30"), "open").changeLine).toBe("\u22120.58% open")
  // Its headline is still Thursday's close and move, as theirs are.
  expect(M.rowModel(gspc, 0, "pct").changeText).toBe("\u22121.21%")
  // Before the pre-market it names the open's day, as a stock does.
  expect(M.marketStatus(gspc, at("2026-10-23", "03:59"), 0, calendars)).toBe("Closed · opens Fri 09:30")
})

test("the evening's night is on the day's chart, a scrub of it read from the day's own close, as the price on top is", () => {
  // Tuesday 23:00: the night since 20:00 at the right end of Tuesday. Its
  // newest price is on top, measured from Tuesday's close, and a scrub of
  // the night reads from that close too, so the two never disagree; a scrub
  // of the session still reads from the dashed line, Monday's close.
  const quote = savedDay("2026-10-06-2300", "nest")
  const built = dayAt("2026-10-06-2300", "nest")
  const day = built.day
  expect(M.chartSpan(day)).toMatchObject({ start: at("2026-10-06", "00:00"), end: at("2026-10-07", "00:00") })
  expect(day.points.at(-1)).toMatchObject({ s: "overnight" })
  expect(day.points.at(-1).t).toBeGreaterThanOrEqual(at("2026-10-06", "20:00"))
  expect(M.dayBase(day)).toBe(quote.prevClose)
  const top = M.rowModel(quote, 0, "pct", M.newestPrint(quote, built.latest, calendars))
  expect(M.rowModel(day, built.latest.t, "pct").changeText).toBe(top.changeText)
  const night = day.points.filter(p => p.t >= at("2026-10-06", "20:00"))
  expect(night.length).toBe(35)
  expect(night.every(p => M.readsClose(day, p.t))).toBe(true)
  expect(againstDashedLine(day, "23:00")).toBe(`23:00 all against ${M.money(quote.prevClose)}`)
  // Beside the scrub, what it reads from is named for what it is: on the
  // session, the previous close; past the bell, in the after hours (the
  // 16:00 bucket is its first) or the night, Tuesday's close.
  const today = M.exchangeDay(day, at("2026-10-06", "23:00"))
  const labelAt = clock => M.dayBaselineText(day, today, at("2026-10-06", clock))
  const close = M.money(M.regularClose(quote))
  expect(["12:00", "15:55", "16:00", "17:00", "22:50"].map(labelAt)).toEqual([
    `PREV CLOSE ${M.money(quote.prevClose)}`, `PREV CLOSE ${M.money(quote.prevClose)}`,
    `CLOSE ${close}`, `CLOSE ${close}`, `CLOSE ${close}`])
  expect(M.dayBaselineText(day, today, 0)).toBe(`PREV CLOSE ${M.money(quote.prevClose)}`)
  // Read six days on, the session is named by its weekday; a week on or
  // more, as a halted listing's last day, by its date, never its month
  // alone, which would read as before October.
  expect([6, 7, 30].map(days => M.dayBaselineText(day, today + days, 0))).toEqual([
    `CLOSE BEFORE TUE ${M.money(quote.prevClose)}`, `CLOSE BEFORE 6 OCT ${M.money(quote.prevClose)}`,
    `CLOSE BEFORE 6 OCT ${M.money(quote.prevClose)}`])
})

// When a watch moment's answers came, by its times.txt: how long after
// its day a quote was answered decides whether that day is over.
const answeredAt = set => Date.parse(readFileSync(join(fixtures, "moments", set, "times.txt"), "utf8").match(/answers to (\S+)/)[1]) / 1000
// Two of Yahoo's day answers for a listing joined into the two-day answer
// one request would have brought at the later's time: the earlier's bars
// and periods, then the later's, and the later's quote. A later answer with
// no periods yet has its current period's.
const joined = (earlier, later) => {
  const a = earlier.chart.result[0]
  const b = later.chart.result[0]
  const periods = (p, q) => Array.isArray(p) ? [...p, ...(q || [[b.meta.currentTradingPeriod.regular]])]
    : Object.fromEntries(Object.keys(p).map(k => [k, [...p[k], ...q[k]]]))
  const bars = r => r.indicators.quote[0]
  return { chart: { result: [{
    meta: { ...b.meta, range: "2d", tradingPeriods: periods(a.meta.tradingPeriods, b.meta.tradingPeriods) },
    timestamp: [...a.timestamp, ...(b.timestamp || [])],
    indicators: { quote: [Object.fromEntries(["open", "high", "low", "close", "volume"].map(f => [f, [...bars(a)[f], ...((b.timestamp && bars(b)[f]) || [])]]))] }
  }] } }
}

test("a weekend shows Friday from midnight to 20:00, filling the width, then Sunday's night alone from its first print, on past midnight to 04:00", () => {
  // Saturday noon: Friday's day is over, Robinhood's answer reaching its
  // 19:55 slot, so its prints fill the width; ticks at 04:00 and the
  // close, none at 20:00, its edge.
  const saturday = dayAt("2026-10-03-1200", "nest").day
  expect(M.chartSpan(saturday)).toMatchObject({ start: at("2026-10-02", "00:00"), end: at("2026-10-02", "20:00"), over: true })
  expect(M.lastPrintTime(saturday)).toBe(at("2026-10-02", "19:55"))
  expect(M.chartGeometry(saturday).points.at(-1).x).toBe(1)
  expect(M.chartGeometry(saturday).ticks.map(x => M.timeAtFraction(saturday, x)))
    .toEqual([at("2026-10-02", "04:00"), at("2026-10-02", "16:00")])
  // A thin feed: SHOP's Friday 23 October, its after hours ending with a
  // 19:05 bar, as Robinhood's answer stood at 20:30 that evening (cut from
  // its week, fetched Monday 00:12). Over, it fills the width like every
  // other listing's: the 19:05 bar on the right edge, where a scrub says
  // its own time, and nothing drawn at 20:00, where no trade was.
  const shopRaw = fixture("moments/shop-2026-10-26-0013/robinhood-week.json")
  const week = M.parseOvernight(shopRaw, ["SHOP"]).SHOP
  const fridayNight = { bars: week.bars.filter(b => b.t < at("2026-10-23", "20:00")), through: at("2026-10-23", "19:55") }
  const shopQuote = M.parseChart(fixture("moments/shop-2026-10-26-0013/shop.json"), cents, at("2026-10-23", "20:30"))
  const thinFeed = M.dayChart(shopQuote, fridayNight, calendars).day
  expect(M.chartSpan(thinFeed)).toMatchObject({ start: at("2026-10-23", "00:00"), end: at("2026-10-23", "20:00"), over: true })
  const shopLast = M.lastPrintTime(thinFeed) - at("2026-10-23", "19:05")
  expect([shopLast >= 0 && shopLast < 60, M.chartGeometry(thinFeed).points.at(-1).x]).toEqual([true, 1])
  expect(M.marketStatus(thinFeed, at("2026-10-23", "20:30"), M.timeAtFraction(thinFeed, 1), calendars)).toBe("At 19:05 · After hours")
  expect(M.marketStatus(thinFeed, at("2026-10-26", "00:13"), M.timeAtFraction(thinFeed, 1), calendars)).toBe("At Fri 19:05 · After hours")
  // Sunday 10:00, NBIS: the same, Thursday's close dashed, the dot on
  // Friday's last regular print. Before 26 October the line stopped five
  // sixths of the way, the axis running to Saturday's midnight.
  const sunday = dayAt("watch-2026-10-25-1000", "nbis")
  const friday = M.chartGeometry(sunday.day)
  expect(M.chartSpan(sunday.day)).toMatchObject({ start: at("2026-10-23", "00:00"), end: at("2026-10-23", "20:00") })
  expect([friday.points.at(-1).x, M.dayBase(sunday.day)]).toEqual([1, sunday.quote.prevClose])
  expect(sunday.day.points[friday.points.indexOf(M.lastRegularPoint(friday))].t).toBe(at("2026-10-23", "15:55"))
  // Sunday 19:50, no print of the night yet: still Friday. By 20:05
  // Robinhood has sent the night's 20:00 bar, and the chart is Sunday's,
  // 20:00 to midnight.
  expect(M.chartSpan(dayAt("watch-2026-10-25-1950", "nbis").day).start).toBe(at("2026-10-23", "00:00"))
  expect(M.chartSpan(dayAt("watch-2026-10-25-2005", "nbis").day)).toMatchObject({ start: at("2026-10-25", "20:00"), end: at("2026-10-26", "00:00") })
  // Its one print is the night's first, not its only one: no "Traded only
  // at 20:00" while the night runs, to its close at 04:00.
  const lone = dayAt("watch-2026-10-25-2005", "nbis").day
  expect([lone.points.length, M.dayNote(lone, at("2026-10-25", "20:06"), calendars), M.dayNote(lone, at("2026-10-26", "03:59"), calendars)])
    .toEqual([1, "", ""])
  expect(M.dayNote(lone, at("2026-10-26", "04:00"), calendars)).toBe("Traded only at 20:00")
  // Sunday 23:35: the night alone, dashed at Friday's close, the one the
  // move under the price is measured from, so a scrub of the newest print
  // and the line under the price say the same. No regular print, no dot.
  // Its prints stand evenly to where the clock puts the newest, 23:30.
  const night = dayAt("watch-2026-10-25-2335", "nbis")
  const close = M.regularClose(night.quote)
  const geometry = M.chartGeometry(night.day)
  expect(M.dayBase(night.day)).toBe(close)
  expect(night.day.points.every(p => p.s === "overnight")).toBe(true)
  expect(M.lastRegularPoint(geometry)).toBeNull()
  expect(geometry.points.at(-1).x).toBe(3.5 / 4)
  expect(againstDashedLine(night.day, "23:35")).toBe(`23:35 all against ${M.money(close)}`)
  expect(M.rowModel(night.day, night.latest.t, "pct").changeText).toBe(stripAt(night, at("2026-10-25", "23:35")).changeText)
  // A scrub names the day of a print that isn't from today.
  const ten = night.day.points.find(p => p.t === at("2026-10-25", "21:10")).t
  expect(M.marketStatus(night.day, at("2026-10-25", "23:35"), ten, calendars)).toBe("At 21:10 · Overnight")
  expect(M.marketStatus(night.day, at("2026-10-26", "01:00"), ten, calendars)).toBe("At Sun 21:10 · Overnight")
  // Monday 01:00: where Robinhood starts an empty day, the night runs on
  // past midnight to the right edge, by print, a tick at midnight.
  const late = dayAt("watch-2026-10-26-0100", "nbis")
  const run = M.chartGeometry(late.day)
  expect(M.chartSpan(late.day)).toMatchObject({ start: at("2026-10-25", "20:00"), end: late.latest.t })
  expect(late.latest.t).toBeGreaterThan(at("2026-10-26", "00:30"))
  const midnight = late.day.points.findIndex(p => p.t >= at("2026-10-26", "00:00"))
  expect(run.ticks.length).toBe(1)
  expect(run.ticks[0]).toBeCloseTo((run.points[midnight - 1].x + run.points[midnight].x) / 2, 9)
  expect(run.points.at(-1).x).toBe(1)
  // Monday 04:20: once Monday has a print of its own at 04:00 or later,
  // its day from midnight, its night since then and the pre-market, the
  // rest of the day empty and no dot; still Friday's close dashed. JNJ's
  // 04:00 bar hadn't come at 04:05: Sunday's night stayed on till then.
  const monday = dayAt("watch-2026-10-26-0420", "nbis")
  expect(M.chartSpan(monday.day)).toMatchObject({ start: at("2026-10-26", "00:00"), end: at("2026-10-27", "00:00") })
  expect([...new Set(monday.day.points.map(p => p.s))]).toEqual(["overnight", "pre"])
  expect([M.lastRegularPoint(M.chartGeometry(monday.day)), M.dayBase(monday.day)]).toEqual([null, close])
  expect(M.chartSpan(dayAt("watch-2026-10-26-0405", "jnj").day).start).toBe(at("2026-10-25", "20:00"))
  // 09:35: nothing turns at the open; the dot comes with the first regular print.
  const open = dayAt("watch-2026-10-26-0935", "nbis")
  expect(M.chartSpan(open.day).start).toBe(at("2026-10-26", "00:00"))
  const first = M.chartGeometry(open.day)
  expect(open.day.points[first.points.indexOf(M.lastRegularPoint(first))].t).toBeGreaterThanOrEqual(at("2026-10-26", "09:30"))
})

test("a night that trades thinly shows Yahoo's day, then a line through the night's few trades by the clock", () => {
  // Every saved moment of a trading night, and three daytime ones: NEST and
  // SPY trade in every five-minute slot of the night and keep the calendar
  // day; SILK (13 of 35 slots by Thursday 23:00, 16 of 29 by Sunday 22:30),
  // REED (none on Thursday), EZ (1 of 55 by Monday 00:36) and TOY (5 of 55)
  // trade thinly. REED has no print on Sunday night, so its chart is still
  // Friday's, which has no night. In the daytime no night after Yahoo's day
  // has begun.
  const moments = {
    night: ["nest", "silk", "reed"], sunday: ["nest", "silk", "reed"], "live-2026-10-05": ["nest", "ez", "toy"],
    "2026-10-04-2230": ["nest"], "2026-10-06-2300": ["nest"], "2026-10-07-0005": ["nest"], "2026-10-07-0100": ["nest"],
    "listings-2026-10-07-0100": ["nest", "spy"], day: ["nest", "silk", "reed"], monday: ["nest", "silk", "reed"],
    "2026-10-07-1153": ["nest"]
  }
  const thin = Object.entries(moments).flatMap(([set, names]) => names.filter(name => !!dayAt(set, name).day.axis.night).map(name => `${set} ${name}`))
  expect(thin).toEqual(["night silk", "night reed", "sunday silk", "live-2026-10-05 ez", "live-2026-10-05 toy"])
  expect(M.chartSpan(dayAt("sunday", "reed").day)).toMatchObject({ start: at("2026-09-25", "00:00"), end: at("2026-09-25", "20:00") })

  // Thursday 23:00: SILK's Thursday from 04:00, then its night to 04:00, a
  // line through its 13 trades, each where the clock puts it, with no
  // break: a few trades in a quiet night drawn as dots read as noise. Ticks
  // at the close and the night's start.
  const quote = savedDay("night", "silk")
  const built = dayAt("night", "silk")
  const day = built.day
  expect(M.chartSpan(day)).toMatchObject({ start: at("2026-10-01", "04:00"), end: at("2026-10-02", "04:00") })
  expect(day.prevClose).toBe(quote.prevClose)
  const geometry = M.chartGeometry(day)
  const trades = day.points.map((p, k) => [p, geometry.points[k]]).filter(([p]) => p.t >= at("2026-10-01", "20:00"))
  expect(trades.map(([p]) => p.s)).toEqual(Array(13).fill("overnight"))
  expect(day.points.length).toBe(quote.points.length + 13)
  for (const [p, g] of trades) {
    expect(g.brk).toBe(false)
    expect(g.x).toBeCloseTo((p.t - at("2026-10-01", "04:00")) / 86400, 9)
    // A scrub where a trade is drawn reads it.
    expect(M.timeAtFraction(day, g.x)).toBe(p.t)
  }
  // The day before them stands a print a step, as Yahoo's own day does.
  const dayPoints = geometry.points.slice(0, geometry.points.length - 13)
  expect(dayPoints.every((g, k) => Math.abs(g.x - dayPoints.at(-1).x * k / (dayPoints.length - 1)) < 1e-9)).toBe(true)
  expect(geometry.ticks.map(x => M.timeAtFraction(day, x))).toContain(at("2026-10-01", "20:00"))
  expect(built.latest).toEqual(day.points.at(-1))
  // A scrubbed trade of the night reads its move from Thursday's close, as
  // the price on top does.
  const top = M.rowModel(quote, 0, "pct", M.newestPrint(quote, built.latest, calendars))
  expect(M.rowModel(day, built.latest.t, "pct").changeLine).toBe(top.changeLine)
  expect(top.changeLine).toBe("+0.04%")
  expect(againstDashedLine(day, "SILK")).toBe(`SILK all against ${M.money(quote.prevClose)}`)
  const noon = quote.points.find(p => p.t >= at("2026-10-01", "12:00")).t
  expect(M.rowModel(day, noon, "pct").changeText).toBe(M.rowModel(quote, noon, "pct").changeText)
  expect(M.dayBaselineText(day, M.exchangeDay(day, at("2026-10-01", "23:00")))).toBe(`PREV CLOSE ${M.money(quote.prevClose)}`)

  // Sunday 22:30: Sunday's night alone, 20:00 to midnight, a line through
  // its trades where the clock puts them. JNJ at 23:35 on 25 October: 19
  // trades in 43 slots, the same.
  for (const [set, name, date] of [["sunday", "silk", "2026-09-27"], ["watch-2026-10-25-2335", "jnj", "2026-10-25"]]) {
    const sunday = dayAt(set, name).day
    const eight = at(date, "20:00")
    expect(M.chartSpan(sunday)).toMatchObject({ start: eight, end: eight + 4 * 3600 })
    const line = M.chartGeometry(sunday).points
    expect(line.some(g => g.brk)).toBe(false)
    expect(line.map(g => g.x)).toEqual(sunday.points.map(p => (p.t - eight) / (4 * 3600)))
  }
  expect(dayAt("watch-2026-10-25-2335", "jnj").day.points.length).toBe(19)
})

// The 1D charts of a saved moment as the view builds them (`Chart.viewChart`),
// each listing routed by Robinhood's word on it: by the symbols `names`
// (file names) stand for.
const SYMBOLS = { nvda: "NVDA", aapl: "AAPL", jnj: "JNJ", wren: "WREN", gspc: "^GSPC" }
const chartsAt = (set, names) => {
  const asked = fixture(`moments/${set}/robinhood-day.json`).results.map(r => r.symbol)
  const nights = {}
  const prints = traded(set, asked)
  for (const s of asked) nights[s] = { status: "ok", ...prints[s] }
  const ins = M.parseAllDay(fixture(`moments/${set}/robinhood-instruments.json`), asked)
  const allDay = {}
  for (const s of asked) allDay[s] = { status: "ok", allDay: ins[s], at: 0 }
  const quotes = {}
  for (const n of names) quotes[SYMBOLS[n]] = M.parseChart(fixture(`moments/${set}/${n}.json`), cents)
  return names.map(n => ({ quote: quotes[SYMBOLS[n]], ...M.viewChart(SYMBOLS[n], "1D", quotes, {}, {}, nights, allDay, calendars) }))
}
// The New York date of a day's regular session.
const sessionDate = q => M.dateStringOf(M.localDate(q.session.regular.start, US))

test("until 04:00 every listing's 1D chart is its last session and the night after it; from the new day's first print at 04:00, the new day", () => {
  // Friday 23 October at 01:00 and 02:30: every headline is Thursday's
  // close and move. At 02:30 NVDA's chart must not show the night alone
  // under Thursday's −4.40%, with a scrub of it turning the bear into a
  // bull, while a quiet stock beside it shows Thursday. A busy stock (NVDA,
  // AAPL), one with a thin night (JNJ), one Robinhood doesn't trade all day
  // (WREN), and an index all draw Thursday, and the night after it.
  for (const set of ["night-2026-10-23-0100", "night-2026-10-23-0230"]) {
    const charts = chartsAt(set, ["nvda", "aapl", "jnj", "wren", "gspc"])
    for (const { quote, day, latest, symbol } of charts) {
      const where = `${set} ${symbol}`
      expect([where, sessionDate(day), sessionDate(quote)]).toEqual([where, "2026-10-22", "2026-10-22"])
      const thursday = day.points.filter(p => M.pointSession(day, p) === "reg")
      expect([where, thursday.length > 0, thursday.every(p => p.t <= at("2026-10-22", "16:00"))]).toEqual([where, true, true])
      // The box holds Thursday's own range: what came after never fills it.
      const geometry = M.chartGeometry(day, calendars)
      const prices = thursday.map(p => p.p)
      expect([where, geometry.hi - geometry.lo >= Math.max(...prices) - Math.min(...prices)]).toEqual([where, true])
      // A scrub anywhere on it says where the price stands against the close
      // it reads from: Thursday's prints against the dashed line,
      // Wednesday's close, as the headline's move does; the night's against
      // Thursday's close, as the price on top does.
      const noon = thursday.find(p => p.t >= at("2026-10-22", "12:00"))
      expect([where, M.rowModel(day, noon.t, "pct").changeText]).toEqual([where, M.rowModel(quote, noon.t, "pct").changeText])
      expect(againstDashedLine(day, where)).toBe(`${where} all against ${M.money(quote.prevClose)}`)
    }
    const [nvda, aapl, jnj] = charts
    expect(M.rowModel(nvda.quote, 0, "pct").changeText).toBe("\u22124.40%")
    // The night after Thursday, running on past midnight.
    for (const { day, symbol } of [nvda, aapl, jnj]) {
      const after = day.points.filter(p => p.t >= at("2026-10-22", "20:00")).map(p => p.s)
      expect([set, symbol, after[0], after.at(-1)]).toEqual([set, symbol, "overnight", "overnight"])
    }
    if (set.endsWith("0230")) {
      // Pointing at 02:25, the newest print: each reads what is on top at
      // rest, from Thursday's close. NVDA's bear of Thursday's −4.40% is a
      // bull since its close.
      const read = c => { const r = M.rowModel(c.day, at("2026-10-23", "02:25"), "pct"); return [r.priceText, r.changeText, M.animalKind(r)] }
      const top = c => { const r = M.rowModel(c.quote, 0, "pct", M.newestPrint(c.quote, c.latest, calendars)); return [r.priceText, r.changeText, M.animalKind(r)] }
      expect([nvda, aapl, jnj].map(read)).toEqual([nvda, aapl, jnj].map(top))
      expect(read(nvda)).toEqual(["214.37", "+1.02%", "bull"])
    }
  }
  // 06:00, a two-day answer holding Thursday and Friday's pre-market: the
  // chart is Friday from midnight for a listing Robinhood trades all day,
  // its night, then the pre-market, the rest of the day empty and no dot.
  // Dashed at Thursday's close, the one the line under the price measures
  // from, so a scrub of the newest print reads what that line does. WREN,
  // which Robinhood doesn't trade all day, has no print since 04:00: still
  // Thursday. The headline is still Thursday's close and move, and the
  // index's chart still Thursday's.
  const [nvda, aapl, jnj, wren, gspc] = chartsAt("night-2026-10-23-0600", ["nvda", "aapl", "jnj", "wren", "gspc"])
  for (const { quote, day, symbol } of [nvda, aapl, jnj]) {
    const close = M.regularClose(quote)
    expect([symbol, sessionDate(day), sessionDate(quote), M.dayBase(day)]).toEqual([symbol, "2026-10-23", "2026-10-22", close])
    expect([symbol, M.lastRegularPoint(M.chartGeometry(day))]).toEqual([symbol, null])
    expect(againstDashedLine(day, symbol)).toBe(`${symbol} all against ${M.money(close)}`)
    expect([symbol, M.chartSpan(day).start, day.points[0].s, day.points.at(-1).s]).toEqual([symbol, at("2026-10-23", "00:00"), "overnight", "pre"])
  }
  expect([sessionDate(wren.day), wren.quote.points.at(-1).t < at("2026-10-23", "04:00")]).toEqual(["2026-10-22", true])
  expect(M.rowModel(aapl.day, aapl.latest.t, "pct").changeText)
    .toBe(M.extendedStack(aapl.quote, aapl.latest, at("2026-10-23", "06:00"), aapl.day).changeText)
  // A row following a scrub into the pre-market its quote holds reads the
  // hero's move, from Thursday's close, not Wednesday's.
  const fiveAm = nvda.quote.points.find(p => p.t >= at("2026-10-23", "05:00")).t
  expect(M.rowModel(nvda.quote, fiveAm, "pct").changeText).toBe(M.rowModel(nvda.day, fiveAm, "pct").changeText)
  // WREN, with no pre-market print, is still on Thursday: a row of it at
  // that moment reads its last print against its own chart's dashed line.
  expect(M.rowModel(wren.quote, fiveAm, "pct").changeText).toBe(M.rowModel(wren.day, wren.day.points.at(-1).t, "pct").changeText)
  expect(M.rowModel(nvda.quote, 0, "pct").changeText).toBe("\u22124.40%")
  expect(sessionDate(gspc.day)).toBe("2026-10-22")
})

test("at the open the chart moves to the new session, and a listing abroad shows its last session until its new one has a bar", () => {
  // Friday 09:31: AAPL's chart is Friday from midnight, the S&P 500's Friday's
  // session.
  for (const { day, symbol } of chartsAt("night-2026-10-23-0931", ["aapl", "gspc"]))
    expect([symbol, sessionDate(day)]).toEqual([symbol, "2026-10-23"])
  // London before its session opens, its answer still the last session's:
  // the chart, the headline and its day are that session's.
  const london = M.parseChart(fixture("shel-l-day.json"), cents)
  const view = M.viewChart("SHEL.L", "1D", { "SHEL.L": london }, {}, {}, {}, {}, calendars)
  const LSE = calendars.calendars.LSE
  expect(M.dateStringOf(M.localDate(view.day.session.regular.start, LSE))).toBe(M.dateStringOf(M.localDate(london.marketTime, LSE)))
  expect(view.day.points.every(p => p.t < view.day.session.regular.end + 600)).toBe(true)
  // Tokyo at Sunday 20:05 New York, Monday 09:05 there: Yahoo's day answer
  // has turned to Monday and holds no bar yet, so a chart of it alone is
  // empty. Asked for two days until Monday has a bar (`twoDays`), the
  // answer holds Friday's day and Monday's periods, and the chart stays
  // Friday's. By 20:20 Monday's first bars are in: Monday's day, from them.
  const tokyo = set => fixture(`moments/${set}/7203.t.json`)
  const sunday = at("2026-10-25", "20:05")
  const turned = M.parseChart(tokyo("watch-2026-10-25-2005"), cents)
  expect([turned.points.length, M.twoDays(turned, sunday, calendars)]).toEqual([0, true])
  const both = later => M.parseChart(joined(tokyo("watch-2026-10-25-1950"), tokyo(later)), cents)
  const tokyoDate = q => M.dateStringOf(M.localDate(q.session.regular.start, JPX))
  const tokyoDay = q => M.viewChart("7203.T", "1D", { "7203.T": q }, {}, {}, {}, {}, calendars).day
  const friday = tokyoDay(both("watch-2026-10-25-2005"))
  expect([tokyoDate(friday), friday.points.length]).toEqual(["2026-10-23", 66])
  const monday = tokyoDay(both("watch-2026-10-25-2020"))
  expect([tokyoDate(monday), monday.points.length]).toEqual(["2026-10-26", 2])
})

test("a two-day answer is read as the headline's session, with the coming day's pre-market after it", () => {
  // Friday 06:00: Thursday's day and Friday's pre-market to 05:55. The
  // quote is Thursday's, measured from Wednesday's close, and the line
  // under the price is the pre-market's, from Thursday's close.
  const aapl = savedDay("night-2026-10-23-0600", "aapl")
  expect([sessionDate(aapl), aapl.prevClose, M.rowModel(aapl, 0, "pct").changeText]).toEqual(["2026-10-22", 343.99, "+1.23%"])
  const tail = aapl.points.filter(p => p.t >= at("2026-10-23", "04:00"))
  expect([tail.length, tail.every(p => p.s === "pre")]).toEqual([23, true])
  expect(M.extendedStack(aapl, null, at("2026-10-23", "06:00"), null)).toMatchObject({ label: "PRE-MARKET", changeText: "\u22120.49%" })
  // The row's line: Thursday, then the pre-market, the night between taking
  // no room and the line starting again after it.
  const row = M.chartGeometry(aapl, calendars)
  const first = aapl.points.indexOf(tail[0])
  expect([row.points[first].brk, row.points[first].x - row.points[first - 1].x < 0.02]).toEqual([true, true])
  // Since the open at rest is "—", as the S&P 500's is: the coming session
  // has no open yet. A scrub of Thursday still reads from Thursday's open.
  // The two-day answer must not bring back Thursday's open.
  expect(M.rowModel(aapl, 0, "open").changeLine).toBe("—")
  expect(M.rowModel(aapl, at("2026-10-22", "12:00"), "open").changeLine).toMatch(/^[+\u2212]\d+\.\d\d% open$/)
  // Without the quote's time, the session is still Thursday's, the last
  // with regular bars, not Friday's unopened one: the chart is not the night
  // alone, its scrub not from Wednesday's close.
  const untimed = fixture("moments/night-2026-10-23-0600/aapl.json")
  delete untimed.chart.result[0].meta.regularMarketTime
  const timeless = M.parseChart(untimed, cents)
  expect([sessionDate(timeless), timeless.points.length, timeless.prevClose]).toEqual(["2026-10-22", aapl.points.length, 343.99])
  // Mid-session, a listing's first answer is asked for two days too: the
  // day is Friday's, from Thursday's close, and Thursday is left out.
  const noon = savedDay("twodays-2026-10-23-1208", "aapl")
  expect([sessionDate(noon), noon.prevClose, noon.next, noon.points[0].t]).toEqual(["2026-10-23", 348.22, null, at("2026-10-23", "04:00")])
})

test("an overnight print is its own line under the price, measured from the close, with its time", () => {
  const now = at("2026-10-01", "23:00")
  const strip = name => stripAt(dayAt("night", name), now)
  const nest = savedDay("night", "nest")
  const nestDay = dayAt("night", "nest").day
  // NEST traded to 22:50, ten minutes ago: Robinhood's newest bar.
  expect(strip("nest")).toEqual({ price: "234.27", changeText: "+0.86%", tone: "up", label: "OVERNIGHT", time: "22:50", stale: false })
  expect(M.money(M.regularClose(nest))).toBe("232.28")
  // Never the headline, nor in the day's high: the day holds a night print
  // above Thursday's high, and the hero and the day's line are Thursday's.
  expect(Math.max(...nestDay.points.map(p => p.p))).toBeGreaterThan(nest.dayHigh)
  expect(M.rowModel(nest, 0, "pct").priceText).toBe("232.28")
  // SILK last traded at 22:20: forty minutes old, it dims.
  expect(strip("silk")).toMatchObject({ label: "OVERNIGHT", time: "22:20", stale: true })
  // REED has not traded tonight: no overnight line, its after-hours stays.
  expect(strip("reed")).toMatchObject({ label: "AFTER HOURS", time: "" })
  // While a scrub reads the night, the header names it.
  expect(M.marketStatus(nestDay, now, at("2026-10-01", "21:30"), calendars)).toBe("At 21:30 · Overnight")
  expect(M.marketStatus(nestDay, now, at("2026-10-01", "00:20"), calendars)).toBe("At 00:20 · Overnight")
})

test("no session on Friday or Saturday night, or the night before a holiday", () => {
  const weekend = dayAt("weekend", "nest")
  // Saturday noon: Friday's after-hours is the newest print.
  expect(stripAt(weekend, at("2026-09-26", "12:00"))).toMatchObject({ label: "AFTER HOURS" })
  expect(M.lastPrintTime(weekend.day)).toBe(at("2026-09-25", "19:55"))
  const night = t => M.nightAt(US, t)
  expect(night(at("2026-09-27", "22:00")).open).toBe(true)
  expect(night(at("2026-09-29", "02:00")).open).toBe(true)
  expect(night(at("2026-09-25", "22:00")).open).toBe(false)
  expect(night(at("2026-09-26", "22:00")).open).toBe(false)
  // Thanksgiving is Thursday 26 November: no session Wednesday night, and
  // Thursday night trades into Friday.
  expect(night(at("2026-11-25", "22:00")).open).toBe(false)
  expect(night(at("2026-11-26", "22:00")).open).toBe(true)
  expect(night(at("2026-10-02", "12:00"))).toBeNull()
})

test("the line under the price: Friday night's is the after-hours, a quiet night keeps its last print, c makes it an amount, and an index or a coin has none", () => {
  expect(stripAt(dayAt("weekend", "nest"), at("2026-09-25", "22:00")).label).toBe("AFTER HOURS")
  // Twenty minutes on from Thursday 23:00 with nothing newer.
  expect(stripAt(dayAt("night", "nest"), at("2026-10-01", "23:11"))).toMatchObject({ label: "OVERNIGHT", time: "22:50", price: "234.27" })
  // Wednesday 01:00: as an amount, the same sign; since the open, the
  // percent from the close.
  const built = dayAt("2026-10-07-0100", "nest")
  const now = at("2026-10-07", "01:00")
  const line = mode => M.extendedStack(built.quote, built.latest, now, built.day, mode)
  expect(line("abs").changeText).toMatch(/^[+\u2212]\d+\.\d\d$/)
  expect(line("abs").changeText.charAt(0)).toBe(line("pct").changeText.charAt(0))
  expect(line("open").changeText).toBe(line("pct").changeText)
  // With no regular price the night still has its line.
  expect(M.extendedStack({ ...built.quote, price: null, marketTime: null }, built.latest, now, built.day))
    .toMatchObject({ label: "OVERNIGHT", time: "00:50", price: "248.04" })
  // An index and a coin: no overnight line, and an index's day is its session.
  const gspc = savedDay("night", "gspc")
  expect(M.extendedStack(gspc, null, at("2026-10-01", "23:00"))).toBeNull()
  const index = M.chartSpan(M.viewChart("^GSPC", "1D", { "^GSPC": gspc }, {}, {}, {}, {}, calendars).day)
  expect(index.end - index.start).toBeLessThan(8 * 3600)
  const coin = M.extendedStack(savedDay("listings-2026-10-07-0100", "btc-usd"), null, now)
  expect(coin && coin.label).not.toBe("OVERNIGHT")
})

test("a listing Robinhood doesn't trade all day draws Yahoo's day, filling the width once it is over, the coming day from its first print, and its stray night trade makes no overnight line", () => {
  const notAllDay = (set, file, symbol, received) => {
    const q = M.parseChart(fixture(`moments/${set}/${file}.json`), cents, received)
    return { quote: q, ...M.viewChart(symbol, "1D", { [symbol]: q }, {}, {}, {}, { [symbol]: { status: "ok", allDay: false, at: 0 } }, calendars) }
  }
  // Sunday 10:00: BRK-A's Friday, 04:00 to 20:00, answered after it ended,
  // its 61 bars filling the width to the last, 16:00's. Answered before
  // 20:00, the last stood where the clock put it, the hours to come empty.
  const brk = notAllDay("watch-2026-10-25-1000", "brk-a", "BRK-A", answeredAt("watch-2026-10-25-1000"))
  const friday = M.chartGeometry(brk.day)
  expect(M.chartSpan(brk.day)).toMatchObject({ start: at("2026-10-23", "04:00"), end: at("2026-10-23", "20:00"), over: true })
  expect([brk.day.points.length, brk.day.points.at(-1).t, friday.points.at(-1).x]).toEqual([61, at("2026-10-23", "16:00"), 1])
  expect(M.timeAtFraction(brk.day, 1)).toBe(at("2026-10-23", "16:00"))
  const early = notAllDay("watch-2026-10-25-1000", "brk-a", "BRK-A", at("2026-10-23", "19:00")).day
  expect(M.chartGeometry(early).points.at(-1).x).toBe(0.75)
  // CVR's Friday, its last trade 15:35: over, that trade sits on the right
  // edge, and the 16:00 close after it has no tick left of it.
  const cvrFriday = notAllDay("watch-2026-10-25-1000", "cvr", "CVR", answeredAt("watch-2026-10-25-1000")).day
  expect([cvrFriday.points.at(-1).t, M.chartGeometry(cvrFriday).ticks]).toEqual([at("2026-10-23", "15:35"), []])
  // Friday 06:00, AAPL read as a listing Robinhood doesn't trade all day:
  // its two-day answer holds Friday's pre-market, so the chart is Friday's
  // day from its first print, dashed at Thursday's close, with no dot.
  // WREN, with no print since 04:00, keeps Thursday (above).
  const aapl = notAllDay("night-2026-10-23-0600", "aapl", "AAPL")
  expect(M.chartSpan(aapl.day)).toMatchObject({ start: at("2026-10-23", "04:00"), end: at("2026-10-23", "20:00") })
  expect([...new Set(aapl.day.points.map(p => p.s))]).toEqual(["pre"])
  expect([M.dayBase(aapl.day), M.lastRegularPoint(M.chartGeometry(aapl.day))]).toEqual([M.regularClose(aapl.quote), null])
  // CVR at 09:35 on Monday 26 October hadn't traded since Friday, and
  // Yahoo's day answer held Monday's periods and no bar: alone, an empty
  // chart. It is still asked for two days past the bell (`twoDays`), and
  // the chart stays on Friday until Monday's first trade, 13:10's.
  const cvrAt = (set, received) => M.parseChart(joined(fixture("moments/watch-2026-10-25-1000/cvr.json"), fixture(`moments/${set}/cvr.json`)), cents, received)
  const opened = cvrAt("watch-2026-10-26-0935", at("2026-10-26", "09:35"))
  expect(M.twoDays(opened, at("2026-10-26", "09:35"), calendars)).toBe(true)
  const cvrDay = q => M.viewChart("CVR", "1D", { CVR: q }, {}, {}, {}, { CVR: { status: "ok", allDay: false, at: 0 } }, calendars).day
  expect([sessionDate(cvrDay(opened)), cvrDay(opened).points.length]).toEqual(["2026-10-23", 2])
  const traded = cvrAt("watch-2026-10-26-1500", at("2026-10-26", "15:00"))
  expect([sessionDate(cvrDay(traded)), cvrDay(traded).points[0].t, M.twoDays(traded, at("2026-10-26", "15:00"), calendars)])
    .toEqual(["2026-10-26", at("2026-10-26", "13:10"), false])
  for (const [file, symbol] of [["kiln", "KILN"], ["bolt", "BOLT"]]) {
    const chart = notAllDay("listings-2026-10-07-0100", file, symbol)
    expect(M.chartSpan(chart.day)).toMatchObject({ start: at("2026-10-06", "04:00"), end: at("2026-10-06", "20:00") })
    const line = M.extendedStack(chart.quote, chart.latest, at("2026-10-07", "01:00"), chart.day)
    expect(line && line.label).not.toBe("OVERNIGHT")
  }
  // 14:55: KILN keeps Yahoo's day from 04:00, every print of it.
  const kiln = notAllDay("listings-2026-10-07-1455", "kiln", "KILN")
  expect(M.chartSpan(kiln.day).start).toBe(at("2026-10-07", "04:00"))
  expect(kiln.day.points.length).toBe(kiln.quote.points.length)
  // The keys step print to print: three steps from BOLT's first print land
  // on its fourth, 05:40.
  const bolt = notAllDay("listings-2026-10-07-1455", "bolt", "BOLT").day
  expect(M.stepTime(bolt, bolt.points[0].t, 3)).toBe(bolt.points[3].t)
  expect(bolt.points[3].t).toBe(at("2026-10-07", "05:40"))
})

test("a thin US day's quiet spans each take one step to the next print", () => {
  const set = "gaps-2026-10-21-1006"
  const q = savedDay(set, "vane")
  const allDay = M.parseAllDay(fixture(`moments/${set}/robinhood-instruments.json`), ["VANE"])
  const nights = { VANE: { status: "ok", ...traded(set, ["VANE"]).VANE } }
  const day = M.viewChart("VANE", "1D", { VANE: q }, {}, {}, nights, { VANE: { status: "ok", allDay: allDay.VANE, at: 0 } }, calendars).day
  const times = day.points.map(p => p.t)
  for (const [from, to] of [[1792555800, 1792561200], [1792565400, 1792569600], [1792571400, 1792580700]]) {
    expect(times.indexOf(to)).toBe(times.indexOf(from) + 1)
    expect(M.stepTime(day, from, 1)).toBe(to)
  }
})

test("a night's chart on each saved moment: its span, its trades, and what a scrub of it reads", () => {
  // Sunday 22:30: a scrub at the left edge reads the night's first print,
  // never the previous close.
  const sunday = dayAt("sunday", "nest")
  const edge = M.timeAtFraction(sunday.day, 0.03)
  expect(M.marketStatus(sunday.day, at("2026-09-27", "22:30"), edge, calendars)).toMatch(/^At 20:\d\d · Overnight$/)
  expect(M.rowModel(sunday.day, edge, "pct").priceText).not.toBe("243.48")
  // Monday 08:00: Monday from midnight, a scrub at a tenth in reading the
  // night against Friday's close.
  const monday = dayAt("monday", "nest")
  expect(M.chartSpan(monday.day)).toMatchObject({ start: at("2026-09-28", "00:00"), end: at("2026-09-29", "00:00") })
  const dawn = M.timeAtFraction(monday.day, 0.1)
  expect(M.marketStatus(monday.day, at("2026-09-28", "08:00"), dawn, calendars)).toMatch(/^At 02:\d\d · Overnight$/)
  expect(M.rowModel(monday.day, dawn, "pct").priceText).not.toBe("237.33")
  // Thursday 23:00: NEST's night traded through, midnight to midnight;
  // REED's, not traded, Thursday's day from 04:00, nothing after it.
  expect(M.chartSpan(dayAt("night", "nest").day)).toMatchObject({ start: at("2026-10-01", "00:00"), end: at("2026-10-02", "00:00") })
  const reed = dayAt("night", "reed").day
  expect(M.chartSpan(reed)).toMatchObject({ start: at("2026-10-01", "04:00"), end: at("2026-10-02", "04:00") })
  expect(reed.points.every(p => p.t < at("2026-10-01", "20:00"))).toBe(true)
  // Monday 5 October 00:36: EZ traded once since Sunday 20:00, TOY five
  // times: Sunday's night, 20:00 to midnight, a lone trade and a line.
  const ez = dayAt("live-2026-10-05", "ez")
  expect(M.chartSpan(ez.day)).toMatchObject({ start: at("2026-10-04", "20:00"), end: at("2026-10-05", "00:00") })
  expect(M.chartGeometry(ez.day).points.length).toBe(1)
  expect(stripAt(ez, at("2026-10-05", "00:36"))).toMatchObject({ label: "OVERNIGHT", time: "22:40", price: "19.71", changeText: "\u22123.71%" })
  expect(M.chartGeometry(dayAt("live-2026-10-05", "toy").day).points.length).toBe(5)
  // Wednesday 06:00: Wednesday from midnight, still from Tuesday's close.
  const six = dayAt("2026-10-07-0600", "nest").day
  expect(M.chartSpan(six).start).toBe(at("2026-10-07", "00:00"))
  expect(M.dayBaselineText(six, M.exchangeDay(six, at("2026-10-07", "06:00")))).toBe("PREV CLOSE 249.87")
})

test("on 1M at night the line ends on the night's price, the one on top", () => {
  const set = "live-2026-10-05"
  const asked = fixture(`moments/${set}/robinhood-day.json`).results.map(r => r.symbol)
  const prints = traded(set, asked)
  const quotes = { NEST: savedDay(set, "nest") }
  const history = M.parseHistory(fixture(`moments/${set}/nest-1m.json`), "1M", cents)
  const chart = M.viewChart("NEST", "1M", quotes, {}, { "NEST|1M": { status: "ok", history } },
    { NEST: { status: "ok", ...prints.NEST } }, { NEST: { status: "ok", allDay: true, at: 0 } }, calendars)
  expect(chart.history.bars.slice(0, -1)).toEqual(history.bars)
  expect(chart.history.bars.at(-1)).toMatchObject({ c: 245.47, newest: "overnight" })
  expect(M.historyRowModel(chart.history, chart.quote, 0)).toMatchObject({ priceText: "245.47", periodLabel: "1M" })
})

test("after the close a scrub to the bell reads the close at 16:00, an index's and a stock's, and the after-hours its own print", () => {
  const now = at("2026-10-01", "23:00")
  const gspc = savedDay("night", "gspc")
  const end = M.timeAtFraction(gspc, 1)
  expect(M.marketStatus(gspc, now, end, calendars)).toBe("At 16:00 · Closing bell")
  expect(M.rowModel(gspc, end, "pct").priceText).toBe(M.rowModel(gspc, 0, "pct").priceText)
  const silk = dayAt("night", "silk").day
  const rest = M.rowModel(silk, 0, "pct").priceText
  // The session's last print is its closing trade's, stamped at the bell.
  const bell = silk.points.findLastIndex(p => M.pointSession(silk, p) === "reg")
  expect(silk.points[bell].t).toBe(silk.session.regular.end)
  expect(M.marketStatus(silk, now, silk.points[bell].t, calendars)).toBe("At 16:00 · Closing bell")
  expect(M.rowModel(silk, silk.points[bell].t, "pct").priceText).toBe(rest)
  let off = bell + 1
  while (M.money(silk.points[off].p, silk.priceDigits) === rest) off++
  expect(M.marketStatus(silk, now, silk.points[off].t, calendars)).toMatch(/^At \d\d:\d\d · After hours$/)
  expect(M.rowModel(silk, silk.points[off].t, "pct").priceText).toBe(M.money(silk.points[off].p, silk.priceDigits))
  // An index at 01:00 has no flat tail of its close after the bell.
  const night = savedDay("listings-2026-10-07-0100", "gspc")
  expect(night.points.at(-1).t).toBeLessThan(night.session.regular.end)
})

test("since the open the change is the move from the OPEN the day line shows", () => {
  const q = savedDay("listings-2026-10-07-0100", "nest")
  const open = dayLineAt(q, at("2026-10-07", "01:00")).facts[0]
  expect(open.label).toBe("OPEN")
  const price = Number(M.rowModel(q, 0, "open").priceText.replace(/,/g, ""))
  const from = Number(open.value.replace(/,/g, ""))
  expect(M.rowModel(q, 0, "open").changeText).toBe(M.pct((price - from) / from * 100))
})

test("a scrub in Nasdaq's day after Tokyo's close leaves Tokyo's row on its close", () => {
  const tokyo = savedDay("listings-2026-10-07-1455", "7203.t")
  expect(M.rowModel(tokyo, at("2026-10-07", "12:00"), "pct").priceText).toBe(M.rowModel(tokyo, 0, "pct").priceText)
})

test("after midnight the answer is still Friday's: its date, its open, its prints, and its rows' day lines", () => {
  // Saved Monday 5 October at 00:36 New York. Yahoo's current period is
  // already Monday's; the bars, the high, low, and volume, and the trading
  // periods are Friday's.
  const now = at("2026-10-05", "00:36")
  const live = name => M.parseChart(fixture(`moments/live-2026-10-05/${name}.json`))
  const nest = live("nest")
  expect(said(dayLineAt(nest, now))).toBe("FRI · 235.34–248.34 @242.81 · OPEN 235.81 · VOL 12.3M")
  for (const name of ["nest", "ez", "toy"]) {
    const quote = live(name)
    // Friday's 19:59 print is after hours, never Monday's pre-market.
    expect(M.extendedStack(quote, null, now).label).toBe("AFTER HOURS")
    // A row's day line runs the full width: Friday's pre-market to its last print.
    const points = M.chartGeometry(quote).points
    expect([points[0].x, points[points.length - 1].x]).toEqual([0, 1])
    // The next open comes from the calendar.
    expect(M.marketStatus(quote, now, 0, calendars)).toBe("Closed · opens Mon 09:30")
  }
  // A daytime answer reads as it did: Friday 2 October at 13:40.
  const day = savedDay("day", "nest")
  expect(said(dayLineAt(day, at("2026-10-02", "13:40")))).toBe("1D · 235.34–248.34 @241.72 · OPEN 235.81 · VOL 9.5M")
  expect(M.marketStatus(day, at("2026-10-02", "13:40"), 0, calendars)).toBe("Market closes in 2h 20m")
})

test("a quote held past its bars' session takes the phase and the bell from Yahoo's current period", () => {
  // The saved Monday 00:36 NEST answer, still held at 04:30: its current
  // period's pre-market has begun, so the header turns, and so does the
  // cadence, at the boundary itself, not at the next fetch.
  const nest = M.parseChart(fixture("moments/live-2026-10-05/nest.json"))
  const dawn = at("2026-10-05", "04:30")
  expect(M.marketStatus(nest, dawn, 0, calendars)).toBe("Pre-market · opens in 5h")
  expect([quoteCadence(nest, dawn, 60, true), quoteCadence(nest, dawn, 60, false)]).toEqual([60, 300])
  // The chart, the open, and the info line stay the bars' Friday.
  expect(said(dayLineAt(nest, dawn))).toBe("FRI · 235.34–248.34 @242.81 · OPEN 235.81 · VOL 12.3M")
  expect(M.extendedStack(nest, null, dawn).label).toBe("AFTER HOURS")
  // London's answer, saved before Friday's session with Thursday's bars,
  // still held at 08:30 London: Friday's session is open.
  const london = M.parseChart(fixture("shel-l-day.json"))
  const morning = M.epochAt(calendars.calendars.LSE, "2026-10-02", "08:30")
  expect(M.marketStatus(london, morning, 0, calendars)).toBe("Market closes in 8h")
  expect([M.inRegularSession(london, morning, calendars), quoteCadence(london, morning, 60, false)]).toEqual([true, 60])
})

test("a quote held from an earlier day stays warm by its calendar; one with no calendar, on the slow clock once its periods are past", () => {
  // NEST's answer of Wednesday 7 October at 14:55, held into Thursday.
  const nest = M.parseChart(fixture("moments/listings-2026-10-07-1455/nest.json"))
  const thursday = at("2026-10-08", "11:00")
  expect(M.sessionPhase(nest, thursday)).toBe("closed")
  expect([M.inRegularSession(nest, thursday, calendars), staysWarm(nest, thursday), quoteCadence(nest, thursday, 60, false)])
    .toEqual([true, true, 60])
  // Before Thursday's open, and on Saturday: closed.
  expect(staysWarm(nest, at("2026-10-08", "08:00"))).toBe(false)
  expect(staysWarm(nest, at("2026-10-10", "12:00"))).toBe(false)
  // The S&P 500 is on the US calendar (S&P is one of its exchanges): kept
  // fresh through Thursday's session like any US listing, at the refresh
  // interval, and not before Wednesday's open.
  const gspc = M.parseChart(fixture("moments/listings-2026-10-07-1455/gspc.json"))
  expect([staysWarm(gspc, at("2026-10-07", "11:00")), staysWarm(gspc, at("2026-10-07", "06:00"))]).toEqual([true, false])
  expect([staysWarm(gspc, thursday), quoteCadence(gspc, thursday, 60, false)]).toEqual([true, 60])
  expect(staysWarm(gspc, at("2026-10-10", "12:00"))).toBe(false)
  // An index whose exchange has no calendar (Russell's, Yahoo's WCB): in its
  // periods it is warm; once they are past, it is asked on the slow clock to
  // learn of the next.
  const russell = { ...gspc, exchange: "WCB" }
  expect([staysWarm(russell, at("2026-10-07", "11:00")), staysWarm(russell, at("2026-10-07", "06:00"))]).toEqual([true, false])
  expect([staysWarm(russell, thursday), quoteCadence(russell, thursday, 60, false)]).toEqual([true, 900])
  // A cryptocurrency never stays warm with nothing open.
  expect(staysWarm(btc, btc.session.regular.start + 3600)).toBe(false)
})

test("the header's animal sleeps while its market does: by phase and calendar, never by the data's age", () => {
  // The sweep's listings at each saved moment, each from its own answer at
  // that moment, and whether Robinhood trades it all day from its own.
  const sweep = ["nest", "kiln", "spy", "bolt", "gspc", "btc-usd", "shel.l", "7203.t"]
  const tradable = M.parseAllDay(fixture("moments/listings-2026-10-07-0100/robinhood-instruments.json"), ["NEST", "KILN", "SPY", "BOLT"])
  const asleep = (quote, t) => M.marketAsleep(quote, !!tradable[quote.symbol], t, calendars)
  const row = (set, t) => sweep.filter(name => asleep(savedDay(set, name), t)).join(" ")
  // Wednesday 01:00: NEST's and SPY's night trades; KILN's and BOLT's
  // doesn't, nor an index's or London's; Tokyo is in its afternoon.
  expect(row("listings-2026-10-07-0100", at("2026-10-07", "01:00"))).toBe("kiln bolt gspc shel.l")
  // 06:00, pre-market: every US stock and ETF is awake, the thin ones
  // too; an index has no pre-market; London trades; Tokyo has closed.
  expect(row("listings-2026-10-07-0600", at("2026-10-07", "06:00"))).toBe("gspc 7203.t")
  // 14:55, the session; London and Tokyo have closed.
  expect(row("listings-2026-10-07-1455", at("2026-10-07", "14:55"))).toBe("shel.l 7203.t")
  // Thursday 10:54, the session, London's too.
  expect(row("listings-2026-10-08-1054", M.epochAt(US, "2026-10-08", "10:54") + 24)).toBe("7203.t")
  // Saturday noon: all but the cryptocurrency, which never sleeps.
  expect(row("listings-2026-10-03-1200", at("2026-10-03", "12:00"))).toBe("nest kiln spy bolt gspc shel.l 7203.t")
  // After hours, the 14:55 answers held to 17:00: a thin stock is awake
  // with nothing trading; an index has closed.
  expect(row("listings-2026-10-07-1455", at("2026-10-07", "17:00"))).toBe("gspc shel.l 7203.t")
  // Sunday 22:30: Monday's night trades for NEST; the index sleeps.
  const sunday = at("2026-09-27", "22:30")
  expect([asleep(savedDay("sunday", "nest"), sunday), asleep(savedDay("sunday", "gspc"), sunday)]).toEqual([false, true])
  // Tokyo's lunch, 11:45 JST, sleeps; its morning, 10:00, is awake.
  const tokyo = M.parseChart(fixture("7203-t-day.json"))
  expect([asleep(tokyo, Date.UTC(2026, 9, 2, 2, 45) / 1000), asleep(tokyo, Date.UTC(2026, 9, 2, 1, 0) / 1000)]).toEqual([true, false])
  // A holiday sleeps, whatever Yahoo's periods still say: Labor Day, with
  // a response that describes a session; and Thanksgiving, NEST's held
  // answer, with no night before it.
  const labor = 1788793200
  const fakeOpen = { ...sep4, session: { pre: null, post: null, regular: { start: labor - 3600, end: labor + 3600 } } }
  expect(asleep(fakeOpen, labor)).toBe(true)
  const nest = savedDay("listings-2026-10-07-1455", "nest")
  expect([asleep(nest, at("2026-11-26", "12:00")), asleep(nest, at("2026-11-25", "22:00"))]).toEqual([true, true])
  // The data's age never sends it to sleep: Wednesday's answers held into
  // Thursday are awake by the calendar through its pre-market, session, and
  // after hours, KILN asleep in the nights around them and NEST, whose
  // nights trade, awake; the index has no pre-market.
  const thursday = ["03:00", "06:00", "11:00", "17:00", "21:00"].map(clock => at("2026-10-08", clock))
  const kiln = savedDay("listings-2026-10-07-1455", "kiln")
  expect([nest, kiln].map(q => thursday.map(t => asleep(q, t))))
    .toEqual([[false, false, false, false, false], [true, false, false, false, true]])
  const gspc = savedDay("listings-2026-10-07-1455", "gspc")
  expect([asleep(gspc, at("2026-10-08", "06:00")), asleep(gspc, at("2026-10-08", "11:00"))]).toEqual([true, false])
  // An early close's own periods rule its day: the day after Thanksgiving,
  // KILN's after hours ends at 17:00, so it sleeps at 18:00, not at 20:00,
  // whether they are its bars' periods, only Yahoo's current ones over
  // Wednesday's bars, or none of that day's at all, Wednesday's answer held
  // there: its after hours runs as long after the early close as after a
  // normal one.
  const early = clock => at("2026-11-27", clock)
  const periods = {
    pre: { start: early("04:00"), end: early("09:30") },
    regular: { start: early("09:30"), end: early("13:00") },
    post: { start: early("13:00"), end: early("17:00") } }
  for (const friday of [{ ...kiln, session: periods }, { ...kiln, current: periods }, kiln])
    expect(["16:00", "18:00"].map(clock => asleep(friday, early(clock)))).toEqual([false, true])
  // A listing's own extended hours, whatever day its periods describe:
  // London's Wednesday answer held into Thursday is awake in its pre-market
  // (07:15 to 08:00) and after hours (16:30 to 17:15), as Thursday's own
  // answer is; Toronto's, from 2 September, the next day in its pre-market
  // (08:00 to 09:30) and after hours (16:00 to 17:00); each asleep outside.
  const london = clock => M.epochAt(calendars.calendars.LSE, "2026-10-08", clock)
  const toronto = clock => M.epochAt(calendars.calendars.TSX, "2026-09-03", clock)
  const awakeAt = (quote, times) => times.map(t => !asleep(quote, t))
  for (const set of ["listings-2026-10-07-1455", "listings-2026-10-08-1054"])
    expect(awakeAt(savedDay(set, "shel.l"), ["07:00", "07:20", "16:40", "17:30"].map(london))).toEqual([false, true, true, false])
  expect(awakeAt(shop, ["07:30", "08:30", "16:10", "17:30"].map(toronto))).toEqual([false, true, true, false])
})

// Bitcoin's picture says its day, in UTC, the time it has no calendar for;
// its file and the footer keep the dash. A scrub outside the regular session
// names it, as the picture at rest does: a big price read as the session's
// would mislead. A range says its dates once, at the foot, with no axis
// dates for a mark to repeat. An index's level isn't money: no currency.
test("a screenshot says when its price is, its session, its range's dates once, and an index's level without a currency", () => {
  const Share = load("Share.js")
  const words = Share.words({ quote: btc, day: M.dayChart(btc, null, calendars).day, history: null, latest: null,
    scrubT: 0, changeMode: "pct", range: "1D", now: btc.marketTime + 60, calendars })
  expect([words.span, words.when]).toEqual(["SAT 12 SEP 2026", "AT 18:32 UTC"])
  expect([Share.subject("BTC-USD", "1D", words.said), Share.fileSymbol("BTC-USD")]).toEqual(["BTC-USD at 18:32 UTC", "btc-usd"])
  const scrubbed = (day, quote, t) => Share.words({ quote, day, history: null, latest: null, scrubT: t,
    changeMode: "pct", range: "1D", now: t, calendars }).when
  const spy = M.parseChart(fixture("spy-2026-09-11-day-prepost.json"))
  expect(["07:30", "12:00", "18:10"].map(clock => scrubbed(spy, spy, at("2026-09-11", clock))))
    .toEqual(["PRE-MARKET 07:30 EDT", "AT 12:00 EDT", "AFTER HOURS 18:10 EDT"])
  const night = dayAt("night", "nest")
  expect(scrubbed(night.day, night.quote, at("2026-10-01", "21:30"))).toBe("OVERNIGHT 21:30 EDT")
  const year = Share.words({ quote, day: quote, history: M.parseHistory(fixture("history/aapl-1y.json"), "1Y"),
    latest: null, scrubT: 0, changeMode: "pct", range: "1Y", now: quote.marketTime + 60, calendars })
  expect([year.span, year.start, year.end]).toEqual(["1 YEAR · 12 SEP 2025 – 11 SEP 2026", "", ""])
  const gspc = savedDay("listings-2026-10-07-1455", "gspc")
  expect([gspc, spy, savedDay("listings-2026-10-07-1455", "shel.l")].map(q => Share.words({ quote: q, day: q,
    history: null, latest: null, scrubT: 0, changeMode: "pct", range: "1D", now: q.marketTime + 60, calendars }).currency))
    .toEqual(["", "USD", "PENCE"])
})
