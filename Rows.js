.pragma library
.import "Quote.js" as Quote
.import "Settings.js" as Settings

// A list's rows: the order they are shown in, what the header says of that
// order, and where each sits while one is dragged. The order itself is the
// list's, kept by `Settings.js`.

var ORDER_LABELS = { manual: "MANUAL", symbol: "SYMBOL", name: "NAME", pct: "% CHANGE" }

function sortsAscending(order, reversed) {
  order = Settings.normalizeOrder(order)
  return (order === "pct") === Settings.normalizeReversed(order, reversed)
}

function orderLabel(order, reversed) {
  order = Settings.normalizeOrder(order)
  var arrow = order === "manual" ? "↕" : sortsAscending(order, reversed) ? "↑" : "↓"
  return arrow + "  " + ORDER_LABELS[order]
}

// `newest`: each symbol's newest trade since the close
// (`Overnight.newestTrade`).
function sortedSymbols(symbols, quotes, order, reversed, changeMode, newest) {
  order = Settings.normalizeOrder(order)
  if (order === "manual") return symbols.slice()
  var keyed = []
  for (var i = 0; i < symbols.length; i++) {
    var q = quotes[symbols[i]]
    keyed.push({ symbol: symbols[i], index: i, key: q ? sortKey(q, order, changeMode, newest ? newest[symbols[i]] : null) : null })
  }
  var first = sortsAscending(order, reversed) ? -1 : 1
  keyed.sort(function(a, b) {
    if (a.key === null && b.key === null) return a.index - b.index
    if (a.key === null) return 1
    if (b.key === null) return -1
    if (a.key < b.key) return first
    if (a.key > b.key) return -first
    return a.index - b.index
  })
  var out = []
  for (var k = 0; k < keyed.length; k++) out.push(keyed[k].symbol)
  return out
}

function shownOrder(held, sorted) {
  if (!held || held.length !== sorted.length) return sorted
  for (var i = 0; i < sorted.length; i++) if (held.indexOf(sorted[i]) < 0) return sorted
  return held
}

function sortKey(quote, order, changeMode, newest) {
  if (order === "symbol") return quote.symbol.toUpperCase()
  if (order === "name") return String(quote.name || quote.symbol).toUpperCase()
  var read = Quote.restingRead(quote, newest)
  return Quote.change(read.base, read.price, changeMode === "open" ? "open" : "pct").pct
}

// The slot a dragged row takes when its top is `rows` rows down the list,
// a fraction, among `count`: it keeps `held` until it is 0.6 of a row past
// it, so a pointer resting near another row's edge never swaps the two back
// and forth.
function dragSlot(rows, held, count) {
  var next = held < 0 || Math.abs(rows - held) >= 0.6 ? Math.round(rows) : held
  return Math.max(0, Math.min(count - 1, next))
}

// Where a row sits while `dragged` is held over `slot`: the rows it has
// passed each give up a place toward the one it left, and the rest stay.
function slotOf(symbols, symbol, dragged, slot) {
  var i = symbols.indexOf(symbol)
  if (dragged === "") return i
  var from = symbols.indexOf(dragged)
  if (from < slot && i > from && i <= slot) return i - 1
  if (slot < from && i >= slot && i < from) return i + 1
  return i
}

// ---- Sight
//
// A list's rows by `row`, { pitch, height }: row i runs from i * pitch, for
// `height`, and the gap to the next is the rest of its pitch. `top` is how
// far the list is scrolled and `sight` how much of it shows. Half a pixel
// either way still counts, so a row a fraction off reads whole.

function rowWhole(index, row, top, sight) {
  var y = index * row.pitch
  return y >= top - 0.5 && y + row.height <= top + sight + 0.5
}

// Any part: the pointer may rest on a row the list's foot cuts.
function rowSeen(index, row, top, sight) {
  var y = index * row.pitch
  return y + row.height > top + 0.5 && y < top + sight - 0.5
}

// The first and last rows any part of which shows.
function rowsSeen(row, top, sight) {
  return { first: Math.max(0, Math.floor((top + 0.5 - row.height) / row.pitch) + 1), last: Math.ceil((top + sight - 0.5) / row.pitch) - 1 }
}

// The least scroll that shows a row whole: a row already whole leaves the
// list where it is.
function topShowing(index, row, top, sight) {
  var y = index * row.pitch
  if (y < top) return y
  if (y + row.height > top + sight) return y + row.height - sight
  return top
}

// The same, resting on a row's edge and never past the list's end, which
// is `length` down.
function restingTop(index, row, top, sight, length) {
  var to = topShowing(index, row, top, sight)
  return to === top ? top : Math.min(Math.max(0, length - sight), Math.ceil(to / row.pitch) * row.pitch)
}

// The row you chose still counts while any of it shows, or while you hold
// it up (`lifted`).
function chosenSeen(symbols, own, lifted, row, top, sight) {
  var at = symbols.indexOf(own)
  return own !== "" && (lifted || (at >= 0 && rowSeen(at, row, top, sight)))
}

// The row keys act on, where the list is headed: the one you chose while it
// counts (`chosenSeen`); else the featured row, while it shows whole; else
// the first row whole in sight, so a key never acts on a row unseen.
function cursorRow(symbols, own, lifted, featured, row, top, sight) {
  if (chosenSeen(symbols, own, lifted, row, top, sight)) return own
  var featuredAt = symbols.indexOf(featured)
  if (featuredAt >= 0 && rowWhole(featuredAt, row, top, sight)) return featured
  var first = Math.max(0, Math.ceil((top - 0.5) / row.pitch))
  return symbols[Math.min(first, symbols.length - 1)] || ""
}

// After a scroll by hand, the cursor among `count` rows: where it is while
// whole in sight; else the nearest row whole in sight; or, in a view too
// short for one, the row across its middle.
function cursorKeptInSight(cursor, count, row, top, sight) {
  if (rowWhole(cursor, row, top, sight)) return cursor
  var shown = []
  for (var i = 0; i < count; i++) if (rowWhole(i, row, top, sight)) shown.push(i)
  if (shown.length > 0) return cursor * row.pitch < top ? shown[0] : shown[shown.length - 1]
  return Math.max(0, Math.min(count - 1, Math.floor((top + sight / 2) / row.pitch)))
}
