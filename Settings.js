.import "History.js" as History
.import "Quote.js" as Quote

// The data file's settings and lists, and every rule that changes them:
// settings in, settings out. Knows nothing of quotes, except to rank them.

function nextChangeMode(mode) {
  return mode === "pct" ? "abs" : mode === "abs" ? "open" : "pct"
}

function normalizeSymbols(value) {
  var list = []
  if (typeof value === "string") list = value.split(/[\s,]+/)
  else if (value && typeof value.length === "number") list = value
  var out = []
  for (var i = 0; i < list.length; i++) {
    var s = String(list[i] || "").trim().toUpperCase()
    if (s && out.indexOf(s) < 0) out.push(s)
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
// sorting by % change ranks the rows without changing what their change
// figures say. There is no order by the amount: Stonks converts no
// currency, so yen, dollars, and index points would rank as one number.
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
// ties keep their manual order too, whichever way it runs. Text sorts run
// A to Z and change sorts biggest gain first; reversed, the other way.
function sortedSymbols(symbols, quotes, order, reversed) {
  order = normalizeOrder(order)
  if (order === "manual") return symbols.slice()
  var keyed = []
  for (var i = 0; i < symbols.length; i++) {
    var q = quotes[symbols[i]]
    keyed.push({ symbol: symbols[i], index: i, key: q ? sortKey(q, order) : null })
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

function sortKey(quote, order) {
  if (order === "symbol") return quote.symbol.toUpperCase()
  if (order === "name") return String(quote.name || quote.symbol).toUpperCase()
  return Quote.change(quote, Quote.regularClose(quote), "pct").pct
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
// the chart range the popup and the window show.
function fileSettings(src) {
  var from = src || {}
  var lists = normalizeLists(from.lists)
  var symbols = normalizeSymbols(from.symbols && from.symbols.length ? from.symbols : ["NVDA", "AAPL", "MSFT", "SPY", "TSLA"])
  for (var i = 0; i < lists.length; i++) symbols = normalizeSymbols(symbols.concat(lists[i].symbols))
  return {
    version: 1,
    symbols: symbols,
    featured: String(from.featured || ""),
    order: normalizeOrder(from.order || "manual"),
    reversed: normalizeReversed(from.order, from.reversed),
    changeMode: from.changeMode === "abs" || from.changeMode === "open" ? from.changeMode : "pct",
    style: from.style === "retro" ? "retro" : "smooth",
    refreshIntervalSec: normalizeRefreshInterval(from.refreshIntervalSec),
    lists: lists,
    list: listIndex(lists, from.list) >= 0 ? lists[listIndex(lists, from.list)].name : "",
    range: History.historyRanges().indexOf(from.range) >= 0 ? from.range : "1D",
    // The popup's first-run hint has shown, and never shows again.
    hinted: from.hinted === true
  }
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
    out.push({ name: name, symbols: normalizeSymbols(list.symbols), order: normalizeOrder(list.order || "manual"),
      reversed: normalizeReversed(list.order, list.reversed) })
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
  if (n.toUpperCase() === "ALL") return "All is the whole library"
  if (listIndex(lists, n) >= 0) return n + " already exists"
  return ""
}

// The current list, or null on All.
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

// All first, then the named lists: what the menu offers and , . step through.
// Each carries its symbols, so a symbol's checklist can read its ticks.
function listChoices(settings) {
  var out = [{ name: "", label: "All", count: settings.symbols.length, symbols: settings.symbols }]
  for (var i = 0; i < settings.lists.length; i++) {
    var list = settings.lists[i]
    out.push({ name: list.name, label: list.name, count: list.symbols.length, symbols: list.symbols })
  }
  return out
}

function steppedList(settings, delta) {
  var choices = listChoices(settings)
  var at = 0
  for (var i = 0; i < choices.length; i++) if (choices[i].name === settings.list) at = i
  return choices[(at + delta + choices.length) % choices.length].name
}

// The settings with one named list changed, or All when name is "".
function withList(settings, name, change) {
  var next = fileSettings(settings)
  var i = listIndex(next.lists, name)
  if (i < 0) {
    var all = change({ symbols: next.symbols, order: next.order, reversed: next.reversed })
    next.symbols = all.symbols
    next.order = all.order
    next.reversed = all.reversed
  } else {
    next.lists[i] = change(next.lists[i])
  }
  return fileSettings(next)
}

// Adding on a named list puts the symbol in it and in All; on All, in All
// only. The surface features it once its first answer is in.
function withSymbolAdded(settings, symbol) {
  var s = String(symbol || "").trim().toUpperCase()
  if (!s) return fileSettings(settings)
  var next = fileSettings(settings)
  next.symbols = normalizeSymbols(next.symbols.concat([s]))
  next = withList(next, next.list, function(list) {
    return Object.assign({}, list, { symbols: normalizeSymbols(list.symbols.concat([s])) })
  })
  return next
}

// One symbol's membership of one list, "" for All. Adding to a named list
// puts the symbol in All too. Taking it out of a named list takes that
// membership only; out of All, out of every list, and All keeps one symbol.
// A featured symbol that leaves All hands the hero to its neighbour in `shown`.
function withMembership(settings, symbol, name, member, shown) {
  var next = fileSettings(settings)
  var without = function(list) { return list.filter(function(s) { return s !== symbol }) }
  if (listIndex(next.lists, name) >= 0) {
    return withList(next, name, function(list) {
      var symbols = member ? normalizeSymbols(list.symbols.concat([symbol])) : without(list.symbols)
      return Object.assign({}, list, { symbols: symbols })
    })
  }
  // A symbol in the checklist is always in All; there is nothing to tick.
  if (member) return next
  if (!canRemove(next.symbols) || next.symbols.indexOf(symbol) < 0) return next
  next.symbols = without(next.symbols)
  for (var i = 0; i < next.lists.length; i++) next.lists[i].symbols = without(next.lists[i].symbols)
  if (String(next.featured).toUpperCase() === symbol) {
    var at = (shown || []).indexOf(symbol)
    next.featured = at < 0 ? next.symbols[0] : shown[at === shown.length - 1 ? at - 1 : at + 1]
  }
  return fileSettings(next)
}

// A removal taken back: the symbol returns to the place it had in All and in
// every list that held it, as `before` recorded them, and to the hero only if
// the removal moved it off and the hero is still the one it `left`. Anything
// else changed since stays as it is now.
function withRemovalUndone(settings, before, symbol, left) {
  var next = fileSettings(settings)
  var then = fileSettings(before)
  var restore = function(now, was) {
    var at = was.indexOf(symbol)
    if (at < 0 || now.indexOf(symbol) >= 0) return now
    var out = now.slice()
    out.splice(Math.min(at, out.length), 0, symbol)
    return out
  }
  next.symbols = restore(next.symbols, then.symbols)
  for (var i = 0; i < next.lists.length; i++) {
    var j = listIndex(then.lists, next.lists[i].name)
    if (j >= 0) next.lists[i].symbols = restore(next.lists[i].symbols, then.lists[j].symbols)
  }
  var hero = function(value) { return String(value || "").toUpperCase() }
  if (hero(then.featured) === symbol && hero(left) !== symbol && hero(next.featured) === hero(left))
    next.featured = symbol
  return fileSettings(next)
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
  var next = fileSettings(settings)
  if (listNameProblem(name, next.lists) !== "") return next
  next.lists.push({ name: listName(name), symbols: [], order: "manual", reversed: false })
  next.list = listName(name)
  return fileSettings(next)
}

// Why a list cannot take a new name, or "" when it can: the new-list rules
// against every other list, so changing only the case is fine.
function renameProblem(settings, name, newName) {
  return listNameProblem(newName, settings.lists.filter(function(list) { return list.name !== name }))
}

// The current list follows its new name. Unchanged when the name is refused.
function withListRenamed(settings, name, newName) {
  var next = fileSettings(settings)
  var i = listIndex(next.lists, name)
  if (i < 0 || renameProblem(next, next.lists[i].name, newName) !== "") return next
  if (next.list === next.lists[i].name) next.list = listName(newName)
  next.lists[i].name = listName(newName)
  return fileSettings(next)
}

// A named list one place up or down among the named lists; All stays first.
function withListMoved(settings, name, delta) {
  var next = fileSettings(settings)
  var from = listIndex(next.lists, name)
  if (from >= 0) next.lists = movedSymbols(next.lists, from, from + delta)
  return next
}

// Deleting a list leaves All and every other list as they were; deleting the
// current one goes back to All.
function withListDeleted(settings, name) {
  var next = fileSettings(settings)
  var i = listIndex(next.lists, name)
  if (i >= 0) next.lists.splice(i, 1)
  return fileSettings(next)
}

function settingsEqual(left, right) {
  return JSON.stringify(fileSettings(left)) === JSON.stringify(fileSettings(right))
}

// What the lists hold, as one value two settings hold equally or not: All's
// symbols and each named list's name and symbols, in their saved order. A
// list's sort order and direction are views over it.
function listsHeld(settings) {
  var from = fileSettings(settings)
  return JSON.stringify([from.symbols, from.lists.map(function(list) { return [list.name, list.symbols] })])
}

// First-run copy of data settings off the bar entry. Null when that entry
// has no symbols, so the service can fall back to defaults without writing.
function settingsFromBar(config) {
  var bar = barEntryFor(config, "grvc.stonks")
  if (!bar || !bar.symbols || !bar.symbols.length) return null
  return fileSettings(bar)
}

// A manual list with one symbol moved to a new slot.
function movedSymbols(symbols, from, to) {
  var list = symbols.slice()
  if (from < 0 || from >= list.length || to < 0 || to >= list.length) return list
  var item = list.splice(from, 1)[0]
  list.splice(to, 0, item)
  return list
}
