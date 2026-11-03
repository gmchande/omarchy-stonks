.pragma library
.import "History.js" as History
.import "Quote.js" as Quote

// Settings in, settings out. Each rule takes settings as `fileSettings`
// returns them, changes none it is given, and normalises its result once:
// normalising at every step, a save of 150 symbols in 12 lists normalised
// each list four to nine times.

function nextChangeMode(mode) {
  return mode === "pct" ? "abs" : mode === "abs" ? "open" : "pct"
}

function normalizeSymbols(value) {
  var list = []
  if (typeof value === "string") list = value.split(/[\s,]+/)
  else if (value && typeof value.length === "number") list = value
  var out = []
  var seen = {}
  for (var i = 0; i < list.length; i++) {
    var s = String(list[i] || "").trim().toUpperCase()
    if (s && seen[s] !== true) {
      seen[s] = true
      out.push(s)
    }
  }
  return out
}

function canRemove(symbols) {
  return !!symbols && symbols.length > 1
}

var ORDERS = ["manual", "symbol", "name", "pct"]

var ORDER_LABELS = { manual: "MANUAL", symbol: "SYMBOL", name: "NAME", pct: "% CHANGE" }

function normalizeOrder(value) {
  if (value === "abs") return "pct"
  return ORDERS.indexOf(value) >= 0 ? value : "manual"
}

function nextOrder(order) {
  return ORDERS[(ORDERS.indexOf(normalizeOrder(order)) + 1) % ORDERS.length]
}

function normalizeReversed(order, value) {
  return normalizeOrder(order) !== "manual" && value === true
}

function sortsAscending(order, reversed) {
  order = normalizeOrder(order)
  return (order === "pct") === normalizeReversed(order, reversed)
}

function orderLabel(order, reversed) {
  order = normalizeOrder(order)
  var arrow = order === "manual" ? "↕" : sortsAscending(order, reversed) ? "↑" : "↓"
  return arrow + "  " + ORDER_LABELS[order]
}

// `newest`: each symbol's newest print since the close
// (`Overnight.newestPrint`).
function sortedSymbols(symbols, quotes, order, reversed, changeMode, newest) {
  order = normalizeOrder(order)
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

function barEntryFor(config, id) {
  if (!config || !config.bar || !config.bar.layout) return null
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var arr = config.bar.layout[sections[s]] || []
    for (var i = 0; i < arr.length; i++) {
      if (arr[i] && arr[i].id === id) return arr[i]
    }
  }
  return null
}

function normalizeRefreshInterval(value) {
  if (value === undefined || value === null || value === "") return 60
  var n = Math.floor(Number(value))
  if (n !== n) return 60
  if (n < 30) return 30
  if (n > 900) return 900
  return n
}

// `symbols`, `order` and `reversed` are All's, as version 1 wrote them; a
// named list is a subset of All.
function fileSettings(src) {
  var from = src || {}
  var lists = normalizeLists(from.lists)
  var symbols = normalizeSymbols(from.symbols && from.symbols.length ? from.symbols : ["NVDA", "AAPL", "MSFT", "SPY", "TSLA"])
  for (var i = 0; i < lists.length; i++) symbols = symbols.concat(lists[i].symbols)
  symbols = normalizeSymbols(symbols)
  return Object.assign({}, from, {
    version: 1,
    symbols: symbols,
    featured: String(from.featured || ""),
    order: normalizeOrder(from.order || "manual"),
    reversed: normalizeReversed(from.order, from.reversed),
    changeMode: from.changeMode === "abs" || from.changeMode === "open" ? from.changeMode : "pct",
    style: from.style === "smooth" ? "smooth" : "retro",
    refreshIntervalSec: normalizeRefreshInterval(from.refreshIntervalSec),
    lists: lists,
    list: listIndex(lists, from.list) >= 0 ? lists[listIndex(lists, from.list)].name : "",
    range: History.historyRanges().indexOf(from.range) >= 0 ? from.range : "1D",
    hinted: from.hinted === true,
    sounds: from.sounds === true,
    updateCheck: from.updateCheck !== false
  })
}

function normalizeLists(value) {
  var out = []
  if (!value || typeof value.length !== "number") return out
  for (var i = 0; i < value.length; i++) {
    var list = value[i] || {}
    var name = listName(list.name)
    if (listNameProblem(name, out) !== "") continue
    out.push(Object.assign({}, list, { name: name, symbols: normalizeSymbols(list.symbols), order: normalizeOrder(list.order || "manual"),
      reversed: normalizeReversed(list.order, list.reversed) }))
  }
  return out
}

function listName(value) {
  return String(value || "").replace(/\s+/g, " ").trim()
}

function listIndex(lists, name) {
  var key = listName(name).toUpperCase()
  if (!key) return -1
  for (var i = 0; i < lists.length; i++) if (lists[i].name.toUpperCase() === key) return i
  return -1
}

function listNameProblem(name, lists) {
  var n = listName(name)
  if (!n) return "Name the list"
  if (n.toUpperCase() === "ALL") return "All already exists"
  if (listIndex(lists, n) >= 0) return n + " already exists"
  return ""
}

function currentList(settings) {
  var i = listIndex(settings.lists, settings.list)
  return i >= 0 ? settings.lists[i] : null
}

function listSymbols(settings) {
  var list = currentList(settings)
  return list ? list.symbols : settings.symbols
}

function listOrder(settings) {
  var list = currentList(settings)
  return list ? list.order : settings.order
}

function listReversed(settings) {
  var list = currentList(settings)
  return list ? list.reversed : settings.reversed
}

function listChoices(settings) {
  var out = [{ name: "", label: "All", count: settings.symbols.length, symbols: settings.symbols }]
  for (var i = 0; i < settings.lists.length; i++) {
    var list = settings.lists[i]
    out.push({ name: list.name, label: list.name, count: list.symbols.length, symbols: list.symbols })
  }
  return out
}

function withList(settings, name, change) {
  var i = listIndex(settings.lists, name)
  if (i < 0) {
    var all = change({ symbols: settings.symbols, order: settings.order, reversed: settings.reversed })
    return fileSettings(Object.assign({}, settings, { symbols: all.symbols, order: all.order, reversed: all.reversed }))
  }
  var lists = settings.lists.slice()
  lists[i] = change(lists[i])
  return fileSettings(Object.assign({}, settings, { lists: lists }))
}

function withSymbolAdded(settings, symbol) {
  var s = String(symbol || "").trim().toUpperCase()
  if (!s) return settings
  return withList(settings, settings.list, function(list) {
    return Object.assign({}, list, { symbols: list.symbols.concat([s]) })
  })
}

function withMembership(settings, symbol, name, member, shown) {
  var without = function(list) { return list.filter(function(s) { return s !== symbol }) }
  if (listIndex(settings.lists, name) >= 0) {
    return withList(settings, name, function(list) {
      return Object.assign({}, list, { symbols: member ? list.symbols.concat([symbol]) : without(list.symbols) })
    })
  }
  // Every symbol is in All already.
  if (member || !canRemove(settings.symbols) || settings.symbols.indexOf(symbol) < 0) return settings
  var symbols = without(settings.symbols)
  var featured = settings.featured
  if (String(featured).toUpperCase() === symbol) {
    var at = (shown || []).indexOf(symbol)
    featured = at < 0 ? symbols[0] : shown[at === shown.length - 1 ? at - 1 : at + 1]
  }
  return fileSettings(Object.assign({}, settings, { symbols: symbols, featured: featured,
    lists: settings.lists.map(function(list) { return Object.assign({}, list, { symbols: without(list.symbols) }) }) }))
}

// `before`: the settings before the removal; `left`: the hero it left.
function withRemovalUndone(settings, before, symbol, left) {
  var restore = function(now, was) {
    var at = was.indexOf(symbol)
    if (at < 0 || now.indexOf(symbol) >= 0) return now
    var out = now.slice()
    out.splice(Math.min(at, out.length), 0, symbol)
    return out
  }
  var lists = settings.lists.map(function(list) {
    var j = listIndex(before.lists, list.name)
    return j < 0 ? list : Object.assign({}, list, { symbols: restore(list.symbols, before.lists[j].symbols) })
  })
  var hero = function(value) { return String(value || "").toUpperCase() }
  var back = hero(before.featured) === symbol && hero(left) !== symbol && hero(settings.featured) === hero(left)
  return fileSettings(Object.assign({}, settings, { symbols: restore(settings.symbols, before.symbols), lists: lists,
    featured: back ? symbol : settings.featured }))
}

function withListOrder(settings, order) {
  return withList(settings, settings.list, function(list) {
    return Object.assign({}, list, { order: normalizeOrder(order), reversed: false })
  })
}

function withListReversed(settings) {
  return withList(settings, settings.list, function(list) {
    return Object.assign({}, list, { reversed: normalizeReversed(list.order, !list.reversed) })
  })
}

function withManualOrder(settings, symbols) {
  return withList(settings, settings.list, function(list) {
    var moved = normalizeSymbols(symbols)
    var same = moved.length === list.symbols.length
      && moved.every(function(s) { return list.symbols.indexOf(s) >= 0 })
    return same ? Object.assign({}, list, { symbols: moved, order: "manual", reversed: false }) : list
  })
}

function withListCreated(settings, name) {
  if (listNameProblem(name, settings.lists) !== "") return settings
  var list = { name: listName(name), symbols: [], order: "manual", reversed: false }
  return fileSettings(Object.assign({}, settings, { lists: settings.lists.concat([list]), list: list.name }))
}

function renameProblem(settings, name, newName) {
  return listNameProblem(newName, settings.lists.filter(function(list) { return list.name !== name }))
}

function withListRenamed(settings, name, newName) {
  var i = listIndex(settings.lists, name)
  if (i < 0 || renameProblem(settings, settings.lists[i].name, newName) !== "") return settings
  var lists = settings.lists.slice()
  lists[i] = Object.assign({}, lists[i], { name: listName(newName) })
  var current = settings.list === settings.lists[i].name ? lists[i].name : settings.list
  return fileSettings(Object.assign({}, settings, { lists: lists, list: current }))
}

function withListMoved(settings, name, delta) {
  var from = listIndex(settings.lists, name)
  if (from < 0) return settings
  return fileSettings(Object.assign({}, settings, { lists: movedSymbols(settings.lists, from, from + delta) }))
}

function withListDeleted(settings, name) {
  var i = listIndex(settings.lists, name)
  if (i < 0) return settings
  var lists = settings.lists.slice()
  lists.splice(i, 1)
  return fileSettings(Object.assign({}, settings, { lists: lists }))
}

// Both as `fileSettings` returns them, so their keys come in one order.
function settingsEqual(left, right) {
  return left === right || JSON.stringify(left) === JSON.stringify(right)
}

function listsHeld(settings) {
  return JSON.stringify([settings.symbols, settings.lists.map(function(list) { return [list.name, list.symbols] })])
}

// The settings rode the bar entry before the data file.
function settingsFromBar(config) {
  var bar = barEntryFor(config, "grvc.stonks")
  if (!bar || !bar.symbols || !bar.symbols.length) return null
  var from = {}
  for (var key in fileSettings(null)) if (key in bar) from[key] = bar[key]
  return fileSettings(from)
}

function movedSymbols(symbols, from, to) {
  var list = symbols.slice()
  if (from < 0 || from >= list.length || to < 0 || to >= list.length) return list
  var item = list.splice(from, 1)[0]
  list.splice(to, 0, item)
  return list
}
