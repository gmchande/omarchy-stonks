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

// The lists file, from the home folder: Omarchy's config folder holds one
// for a plugin, named by its id.
function listsFile(pluginId) {
  return ".config/omarchy/" + pluginId + ".json"
}

function normalizeRefreshInterval(value) {
  if (value === undefined || value === null || value === "") return 60
  var n = Math.floor(Number(value))
  if (n !== n) return 60
  if (n < 30) return 30
  if (n > 900) return 900
  return n
}

// The lists file's text: one JSON object, read through `fileSettings`, or
// null for anything else, which is never written over.
function readListsFile(text) {
  try {
    var parsed = JSON.parse(String(text || "").trim())
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
    return fileSettings(parsed)
  } catch (e) {
    return null
  }
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

// A hand edit can leave a list with no name, the name All, or another
// list's name in another case. It keeps all it holds under the first free
// name like its own (`freeListName`); lists named well keep theirs, so they
// are named first.
function normalizeLists(value) {
  if (!value || typeof value.length !== "number") return []
  var lists = []
  for (var i = 0; i < value.length; i++) if (value[i] && typeof value[i] === "object") lists.push(value[i])
  var named = []
  var names = lists.map(function(list) {
    var name = listName(list.name)
    if (listNameProblem(name, named) !== "") return null
    named.push({ name: name })
    return name
  })
  return lists.map(function(list, i) {
    var name = names[i]
    if (name === null) {
      name = freeListName(listName(list.name), named)
      named.push({ name: name })
    }
    return Object.assign({}, list, { name: name, symbols: normalizeSymbols(list.symbols), order: normalizeOrder(list.order || "manual"),
      reversed: normalizeReversed(list.order, list.reversed) })
  })
}

// "List" for no name, then "All 2", "growth 2", "List 3": the first not taken.
function freeListName(name, lists) {
  var base = name || "List"
  for (var n = 1; ; n++) {
    var tried = n === 1 ? base : base + " " + n
    if (listNameProblem(tried, lists) === "") return tried
  }
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

// `before`: the settings before the removal; `left`: the stock it left featured.
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
  var upper = function(value) { return String(value || "").toUpperCase() }
  var back = upper(before.featured) === symbol && upper(left) !== symbol && upper(settings.featured) === upper(left)
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

// The settings rode the plugin ID's bar entry before the lists file.
function settingsFromBar(config, id) {
  var bar = barEntryFor(config, id)
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
