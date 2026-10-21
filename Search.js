.pragma library
.import "Format.js" as Format
.import "Quote.js" as Quote

// Yahoo's symbol lookup: its URL and its answer. Knows nothing else.

var SEARCH_URL = "https://query2.finance.yahoo.com/v1/finance/search"

function searchUrl(query) {
  return SEARCH_URL + "?q=" + encodeURIComponent(query) + "&quotesCount=8&newsCount=0"
}

// Yahoo sends at most the 8 quotes `searchUrl` asks for, 7 in the saved
// answers; an answer with more than this is a bad one (`Format.fetchedList`).
var MOST_QUOTES = 40

// Yahoo's answer as search shows it: the results Stonks can follow, and a
// note naming what else the answer held, or "" when it held nothing else;
// null when its quotes are not a list within MOST_QUOTES.
// Stonks follows stocks, ETFs, indexes, and cryptocurrencies; Yahoo also
// finds mutual funds, currencies, futures, and more, and a search that
// hid them without a word read "No matches" for a fund Yahoo has.
var FOLLOWED = ["EQUITY", "ETF", "INDEX", "CRYPTOCURRENCY"]

function parseSearch(json) {
  var quotes = Format.fetchedList((json && json.quotes) || [], MOST_QUOTES)
  if (!quotes) return null
  var results = []
  var left = []
  for (var i = 0; i < quotes.length; i++) {
    var q = quotes[i]
    if (!q.symbol) continue
    if (q.quoteType && FOLLOWED.indexOf(q.quoteType) < 0) {
      left.push(q)
      continue
    }
    results.push({ symbol: q.symbol, name: searchName(q), exchange: Quote.EXCHANGE_NAMES[q.exchange] || String(q.exchange || "").toUpperCase() })
  }
  return { results: results, note: leftOutNote(left) }
}

// The kinds Yahoo's search has been seen to send that Stonks leaves out.
var KIND_NAMES = {
  MUTUALFUND: "mutual funds",
  MONEY_MARKET: "money market funds",
  CURRENCY: "currencies",
  FUTURE: "futures",
  OPTION: "options"
}

// "Stonks doesn’t show currencies or futures": each kind left out once, in
// the answer's order, a kind not in KIND_NAMES by Yahoo's own word for it.
// Said the same under results or with none, and short, so it fits the
// popup on one line: "Also found a currency and futures, which Stonks
// doesn’t show" ran past it with a mutual fund and a currency.
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

// Yahoo's short name is cut at 31 characters ("…Tesla Daily Targe"), and a
// German listing's pads a share-class letter onto the end ("…UCITS ETF    R",
// R for registered shares). The long name is the whole name, so the row's
// own ellipsis is the only cut; the short name, without that letter, is the
// fallback. The letter is read from the end, a character at a time: a regex
// for "two spaces, a capital, the end" retries from every space, and a
// fetched name of 63,000 spaces held the shell's thread for over two
// seconds. (Qt's JavaScript has no trimEnd.)
function searchName(q) {
  if (q.longname) return q.longname
  if (!q.shortname) return q.symbol
  var name = String(q.shortname)
  var spaces = 0
  while (spaces < name.length - 1 && /\s/.test(name.charAt(name.length - 2 - spaces))) spaces++
  var lettered = spaces >= 2 && /[A-Z]/.test(name.charAt(name.length - 1))
  return (lettered ? name.slice(0, -1) : name).trim()
}
