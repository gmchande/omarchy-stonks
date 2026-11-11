.pragma library
.import "Format.js" as Format
.import "Quote.js" as Quote

// Yahoo's symbol search: its URL and its answer.

var SEARCH_URL = "https://query2.finance.yahoo.com/v1/finance/search"

// Yahoo's answers asked for, and the most of the list's own shown above them.
var SHOWN_RESULTS = 8

function searchUrl(query) {
  return SEARCH_URL + "?q=" + encodeURIComponent(query) + "&quotesCount=" + SHOWN_RESULTS + "&newsCount=0"
}

// Why a lookup failed, from its answer (`Fetch.answers`), or none: "none"
// when nothing answered, "refused" when Yahoo wants fewer requests, and
// "missing" for the 400 Yahoo gives a question it can't search, such as an
// emoji, which asking again won't change. Any other refusal, such as a 403,
// may pass, so it is "other" and can be asked again.
function failure(answer) {
  if (!answer || answer.kind === "none" || answer.kind === "refused") return answer ? answer.kind : "none"
  return answer.status === 400 ? "missing" : "other"
}

// The answers read since search opened, kept by the words they answer, so
// words typed again answer at once and nothing is asked. A Map, since words
// a person types may be any words, "constructor" among them. Each rule
// returns a new one.
function keptAnswer(kept, words) {
  return kept.has(words) ? kept.get(words) : null
}

// Only an answer read is kept: words whose lookup failed are asked again.
function withAnswer(kept, words, found) {
  if (!found) return kept
  var next = new Map(kept)
  next.set(words, found)
  return next
}

function withoutAnswer(kept, words) {
  if (!kept.has(words)) return kept
  var next = new Map(kept)
  next.delete(words)
  return next
}

// Yahoo sends at most the 8 asked for; past this, an answer is bad.
var MOST_QUOTES = 40

var FOLLOWED = ["EQUITY", "ETF", "INDEX", "CRYPTOCURRENCY"]

function parseSearch(json) {
  var quotes = Format.fetchedList((json && json.quotes) || [], MOST_QUOTES)
  if (!quotes) return null
  var results = []
  var left = []
  var topLeftOut = false
  for (var i = 0; i < quotes.length; i++) {
    var q = {
      symbol: Format.fetchedText(quotes[i].symbol, Format.MOST_CODE),
      quoteType: Format.fetchedText(quotes[i].quoteType, Format.MOST_CODE),
      typeDisp: Format.fetchedText(quotes[i].typeDisp, Format.MOST_NAME),
      exchange: Format.fetchedText(quotes[i].exchange, Format.MOST_CODE),
      longname: Format.fetchedText(quotes[i].longname, Format.MOST_NAME),
      shortname: Format.fetchedText(quotes[i].shortname, Format.MOST_NAME)
    }
    if (!q.symbol || /[\ud800-\udfff]/.test(q.symbol)) continue
    if (q.quoteType && FOLLOWED.indexOf(q.quoteType) < 0) {
      if (results.length === 0 && left.length === 0) topLeftOut = true
      left.push(q)
      continue
    }
    results.push({ symbol: q.symbol, name: searchName(q), exchange: Quote.EXCHANGE_NAMES[q.exchange] || q.exchange.toUpperCase(),
      instrumentType: q.quoteType })
  }
  return { results: results, note: leftOutNote(left), topLeftOut: topLeftOut }
}

// Kinds seen in Yahoo's search answers.
var KIND_NAMES = {
  MUTUALFUND: "mutual funds",
  MONEY_MARKET: "money market funds",
  CURRENCY: "currencies",
  FUTURE: "futures",
  OPTION: "options"
}

function leftOutNote(left) {
  var names = []
  for (var i = 0; i < left.length; i++) {
    var word = String(left[i].typeDisp || left[i].quoteType).toLowerCase()
    var name = KIND_NAMES[left[i].quoteType] || (/s$/.test(word) ? word : word + "s")
    if (names.indexOf(name) < 0) names.push(name)
  }
  if (names.length === 0) return ""
  var listed = names.length < 3 ? names.join(" or ")
    : names.slice(0, -1).join(", ") + ", or " + names[names.length - 1]
  return "Stonks doesn't show " + listed
}

// Read from the end, a character at a time: a regex for "two spaces, a
// capital, the end" retries from every space. (Qt's JavaScript has no
// trimEnd.)
function searchName(q) {
  if (q.longname) return q.longname
  if (!q.shortname) return q.symbol
  var name = q.shortname
  var spaces = 0
  while (spaces < name.length - 1 && /\s/.test(name.charAt(name.length - 2 - spaces))) spaces++
  var lettered = spaces >= 2 && /[A-Z]/.test(name.charAt(name.length - 1))
  return (lettered ? name.slice(0, -1) : name).trim()
}

// The list's own stocks a query names, at most as many as Yahoo is asked
// for: a symbol it spells first, then symbols that start with it, then
// names with a word that does, each group in the list's order. It reads
// nothing but the list, so it answers as each letter lands.
function ownMatches(query, symbols, quotes) {
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return []
  var exact = []
  var bySymbol = []
  var byName = []
  for (var i = 0; i < symbols.length; i++) {
    var symbol = symbols[i]
    var lower = symbol.toLowerCase()
    var quote = quotes[symbol]
    if (lower === q) exact.push(symbol)
    else if (lower.indexOf(q) === 0) bySymbol.push(symbol)
    else if (quote && (" " + String(quote.name || "").toLowerCase()).indexOf(" " + q) >= 0) byName.push(symbol)
  }
  return exact.concat(bySymbol, byName).slice(0, SHOWN_RESULTS)
}
