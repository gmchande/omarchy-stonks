.pragma library
.import "Format.js" as Format
.import "Quote.js" as Quote

// Yahoo's symbol search: its URL and its answer.

var SEARCH_URL = "https://query2.finance.yahoo.com/v1/finance/search"

function searchUrl(query) {
  return SEARCH_URL + "?q=" + encodeURIComponent(query) + "&quotesCount=8&newsCount=0"
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
  return "Stonks doesn’t show " + listed
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
