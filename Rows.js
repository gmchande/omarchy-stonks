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
