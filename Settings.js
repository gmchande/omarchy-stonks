.pragma library
.import "History.js" as History
.import "Quote.js" as Quote

// The data file's settings and lists, and every rule that changes them:
// settings in, settings out. Knows nothing of quotes, except to rank them.
// Each rule takes settings as `fileSettings` returns them, changes none it
// is given, and normalises what it returns once: normalising at each step,
// a save at 150 symbols in 12 lists normalises every list four to nine times.

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

// All always keeps one symbol: the pill, the hero, and the window all need
// one to show. A named list may be empty. The service refuses All's last
// removal and the body says why, from this one rule.
function canRemove(symbols) {
  return !!symbols && symbols.length > 1
}

// A list's order; each list has its own. Manual is the symbols array as
// saved; the rest are views over it, so sorting never rewrites what you
// arranged by hand. The order and the change mode are separate settings:
// sorting by % change ranks the rows by the percent they show, from the
// open when they show since the open. There is no order by the amount:
// Stonks converts no currency, so yen, dollars, and index points would rank
// as one number; showing amounts, the rows stay in percent order.
var ORDERS = ["manual", "symbol", "name", "pct"]

var ORDER_LABELS = { manual: "MANUAL", symbol: "SYMBOL", name: "NAME", pct: "% CHANGE" }

// An order saved by an older build as "abs", the amount, reads as % change,
// which runs the same way.
function normalizeOrder(value) {
  if (value === "abs") return "pct"
  return ORDERS.indexOf(value) >= 0 ? value : "manual"
}

function nextOrder(order) {
  return ORDERS[(ORDERS.indexOf(normalizeOrder(order)) + 1) % ORDERS.length]
}

// A sorted order runs its own way, A to Z or biggest gain first, or,
// reversed, the other. Manual has no direction, so it is never reversed.
function normalizeReversed(order, value) {
  return normalizeOrder(order) !== "manual" && value === true
}

// True when a sorted order puts the smallest value first: text unreversed,
// a change reversed.
function sortsAscending(order, reversed) {
  order = normalizeOrder(order)
  return (order === "pct") === normalizeReversed(order, reversed)
}

// The order control's word, its arrow the way the values run down the list:
// ↑ ascending, ↓ descending, ↕ manual.
function orderLabel(order, reversed) {
  order = normalizeOrder(order)
  var arrow = order === "manual" ? "↕" : sortsAscending(order, reversed) ? "↑" : "↓"
  return arrow + "  " + ORDER_LABELS[order]
}

// Symbols in display order. Sorted views keep quotes that have not
// arrived at the bottom, in their manual order, and the sort is stable so
// ties keep their manual order too, whichever way it runs. `changeMode` is
// the rows' unit, which % change ranks by, the move each row shows: from
// its newest price since the close where it has one (`newest`, by symbol,
// `Overnight.newestPrint`).
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

// The data file. `symbols` is All, the library, in its manual order, and
// `order` is All's order: the version-1 keys keep their meaning, so an older
// build reads the same All. `reversed` is All's direction, a key of its own
// for the same reason. Named lists are subsets of All with their own
// order and direction; `list` is the current one, "" for All. A symbol a hand-edited file
// puts only in a named list joins All rather than being dropped. `range` is
// the chart range the panel and the window show. A key this version doesn't
// know, at the top or in a list, stays as it is: a later version's, after a
// downgrade or from another machine sharing the file.
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
    // A new install opens in retro, the look every picture of Stonks shows;
    // smooth is a key or a click away.
    style: from.style === "smooth" ? "smooth" : "retro",
    refreshIntervalSec: normalizeRefreshInterval(from.refreshIntervalSec),
    lists: lists,
    list: listIndex(lists, from.list) >= 0 ? lists[listIndex(lists, from.list)].name : "",
    range: History.historyRanges().indexOf(from.range) >= 0 ? from.range : "1D",
    // The panel's first-run hint has shown, and never shows again.
    hinted: from.hinted === true,
    // The sounds, off until the file says true: a new install and a file
    // from before them start silent.
    sounds: from.sounds === true,
    // The daily look on GitHub for a newer Stonks, on unless the file says
    // false: off, Stonks asks GitHub nothing.
    updateCheck: from.updateCheck !== false
  })
}

// Named lists: a name, the symbols in their manual order, and the list's own
// order and direction. Names are trimmed and unique ignoring case; "All" is
// the library's.
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

// Why a new list cannot have this name, or "" when it can.
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

// The rows' symbols in their manual order, and the order they show in.
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

// All first, then the named lists: what the menu offers.
// Each carries its symbols, so a symbol's checklist can read its ticks.
function listChoices(settings) {
  var out = [{ name: "", label: "All", count: settings.symbols.length, symbols: settings.symbols }]
  for (var i = 0; i < settings.lists.length; i++) {
    var list = settings.lists[i]
    out.push({ name: list.name, label: list.name, count: list.symbols.length, symbols: list.symbols })
  }
  return out
}

// The settings with one named list changed, or All when name is "".
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

// Adding on a named list puts the symbol in it and in All; on All, in All
// only. The surface features it once its first answer is in.
function withSymbolAdded(settings, symbol) {
  var s = String(symbol || "").trim().toUpperCase()
  if (!s) return settings
  return withList(settings, settings.list, function(list) {
    return Object.assign({}, list, { symbols: list.symbols.concat([s]) })
  })
}

// One symbol's membership of one list, "" for All. Adding to a named list
// puts the symbol in All too. Taking it out of a named list takes that
// membership only; out of All, out of every list, and All keeps one symbol.
// A featured symbol that leaves All hands the hero to its neighbour in `shown`.
function withMembership(settings, symbol, name, member, shown) {
  var without = function(list) { return list.filter(function(s) { return s !== symbol }) }
  if (listIndex(settings.lists, name) >= 0) {
    return withList(settings, name, function(list) {
      return Object.assign({}, list, { symbols: member ? list.symbols.concat([symbol]) : without(list.symbols) })
    })
  }
  // A symbol in the checklist is always in All; there is nothing to tick.
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

// A removal taken back: the symbol returns to the place it had in All and in
// every list that held it, as `before` recorded them, and to the hero only if
// the removal moved it off and the hero is still the one it `left`. Anything
// else changed since stays as it is now.
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

// Another order starts in its own direction.
function withListOrder(settings, order) {
  return withList(settings, settings.list, function(list) {
    return Object.assign({}, list, { order: normalizeOrder(order), reversed: false })
  })
}

// The current list's sorted order the other way; manual has no direction.
function withListReversed(settings) {
  return withList(settings, settings.list, function(list) {
    return Object.assign({}, list, { reversed: normalizeReversed(list.order, !list.reversed) })
  })
}

// A hand-arranged order for the current list; it must hold the same symbols.
function withManualOrder(settings, symbols) {
  return withList(settings, settings.list, function(list) {
    var moved = normalizeSymbols(symbols)
    var same = moved.length === list.symbols.length
      && moved.every(function(s) { return list.symbols.indexOf(s) >= 0 })
    return same ? Object.assign({}, list, { symbols: moved, order: "manual", reversed: false }) : list
  })
}

// A new, empty list, made current. Unchanged when the name is refused.
function withListCreated(settings, name) {
  if (listNameProblem(name, settings.lists) !== "") return settings
  var list = { name: listName(name), symbols: [], order: "manual", reversed: false }
  return fileSettings(Object.assign({}, settings, { lists: settings.lists.concat([list]), list: list.name }))
}

// Why a list cannot take a new name, or "" when it can: the new-list rules
// against every other list, so changing only the case is fine.
function renameProblem(settings, name, newName) {
  return listNameProblem(newName, settings.lists.filter(function(list) { return list.name !== name }))
}

// The current list follows its new name. Unchanged when the name is refused.
function withListRenamed(settings, name, newName) {
  var i = listIndex(settings.lists, name)
  if (i < 0 || renameProblem(settings, settings.lists[i].name, newName) !== "") return settings
  var lists = settings.lists.slice()
  lists[i] = Object.assign({}, lists[i], { name: listName(newName) })
  var current = settings.list === settings.lists[i].name ? lists[i].name : settings.list
  return fileSettings(Object.assign({}, settings, { lists: lists, list: current }))
}

// A named list one place up or down among the named lists; All stays first.
function withListMoved(settings, name, delta) {
  var from = listIndex(settings.lists, name)
  if (from < 0) return settings
  return fileSettings(Object.assign({}, settings, { lists: movedSymbols(settings.lists, from, from + delta) }))
}

// Deleting a list leaves All and every other list as they were; deleting the
// current one goes back to All.
function withListDeleted(settings, name) {
  var i = listIndex(settings.lists, name)
  if (i < 0) return settings
  var lists = settings.lists.slice()
  lists.splice(i, 1)
  return fileSettings(Object.assign({}, settings, { lists: lists }))
}

// Whether two settings, as `fileSettings` returns them, say the same.
function settingsEqual(left, right) {
  return left === right || JSON.stringify(left) === JSON.stringify(right)
}

// What the lists hold, as one value two settings hold equally or not: All's
// symbols and each named list's name and symbols, in their saved order. A
// list's sort order and direction are views over it.
function listsHeld(settings) {
  return JSON.stringify([settings.symbols, settings.lists.map(function(list) { return [list.name, list.symbols] })])
}

// First-run copy of data settings off the bar entry, which held them before
// the data file: its data-file keys only, never the pill's own. Null when
// that entry has no symbols, so the service can fall back to defaults
// without writing.
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
