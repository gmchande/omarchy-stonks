import QtQuick
import "Quote.js" as Quote
// The saved prices, quotes.json in the cache folder: read as the service
// starts, handed to the quote feed once the lists file is in, and written
// back as the feed's prices change. It is read outside the shell's thread
// (`FileRead`) and written through `OwnerOnly`, which makes it its owner's
// alone. The service says when to look at saving (`flush`).
Item {
  id: root

  // The keeper of Stonks' files (`OwnerOnly`), whose folder holds the file.
  property var files: null
  // The quote feed whose prices are saved, and which the saved ones start.
  property var quoteFeed: null
  // The service, whose `now` times the saves.
  property var clock: null
  // The lists file is in, so the feed holds its symbols.
  property bool listsReady: false
  // A surface opening, whose prices a save would stall.
  property bool opening: false
  // Whether the asks a save waits for can be answered: Yahoo isn't pausing
  // Stonks and a screen is on.
  property bool answering: true

  readonly property string path: files && files.folder ? files.folder + "/quotes.json" : ""
  // 16 MiB: a stock's saved price is 8 KB, 12 KB at the most seen, so 150
  // stocks' are about 1.2 MB.
  readonly property int cap: 16777216
  property var savedAnswer: null
  // The feed holds the saved prices.
  property bool seeded: false

  FileRead {
    id: reader
    onDone: function(answer) {
      root.savedAnswer = answer
      root.seed()
    }
  }
  Component.onCompleted: if (root.path !== "") reader.read(root.path, root.cap)
  onPathChanged: if (root.path !== "" && !root.seeded) reader.read(root.path, root.cap)

  // Once both the file and the lists are in.
  function seed() {
    if (!root.listsReady || root.savedAnswer === null || root.seeded) return
    var text = root.savedAnswer.text || ""
    root.savedAnswer = null
    root.quoteFeed.seed(root.parseSaved(text))
    // What the seed put in is what the file holds.
    root.unsaved = false
    root.seeded = true
  }

  // { symbol: { quote, receivedAt } }
  function parseSaved(text) {
    try {
      var parsed = JSON.parse(text)
      return parsed && parsed.version === 1 && parsed.quotes ? Quote.keptQuotes(parsed.quotes) : {}
    } catch (e) {
      return {}
    }
  }

  // At most every 10 minutes, and only once an answer has come, so quotes
  // from an earlier session are never written back as they are. It waits
  // while a surface opens or a chart draws in, and for the runs out and asks
  // due when it fell due (`waitsFor`): a long list's file is a megabyte,
  // written on the shell's thread, which would stall an open's prices.
  property bool unsaved: false
  property int savedAt: 0
  property var waitsFor: null
  // What came is saved, though every price may have failed since.
  property bool answeredOnce: false
  Connections {
    target: root.quoteFeed
    function onQuotesChanged() { root.unsaved = true }
    function onEntriesChanged() {
      if (!root.answeredOnce) root.answeredOnce = Object.keys(root.quoteFeed.entries).some(function(s) { return root.quoteFeed.entries[s].status === "ok" })
    }
  }
  onOpeningChanged: if (root.opening) root.waitsFor = null

  function flush() {
    var feed = root.quoteFeed
    var now = root.clock.now
    if (!root.unsaved || (root.savedAt && now - root.savedAt < 10 * 60)) return
    if (!root.answeredOnce || root.opening || feed.holding) return
    if (!root.waitsFor) root.waitsFor = { runs: feed.landing.slice(), asked: Object.assign({}, feed.asked) }
    var waits = root.waitsFor
    if (waits.runs.some(function(run) { return feed.landing.indexOf(run) >= 0 })
      || (root.answering && Object.keys(waits.asked).some(function(s) { return feed.asked[s] === waits.asked[s] }))) return
    root.waitsFor = null
    root.unsaved = false
    root.savedAt = now
    root.write()
  }

  // Each of All's quotes as the file's text, made by a save for a quote
  // changed since the last, a few milliseconds a turn: the whole file in
  // one JSON.stringify took 40 ms of the shell's thread for 150 stocks.
  // `quoteTexts` doesn't notify.
  readonly property var quoteTexts: ({ by: {} })
  Timer {
    id: textStep
    interval: 0
    onTriggered: root.write()
  }

  // Written in a turn of its own once every text is made: the text
  // JSON.stringify makes of { version: 1, quotes: { symbol: { quote,
  // receivedAt } } }, in All's order, as the quotes stand then.
  function write() {
    var until = Date.now() + 4
    var by = root.quoteTexts.by
    var quotes = root.quoteFeed.quotes
    var held = root.quoteFeed.symbols.filter(function(s) { return !!quotes[s] })
    var stale = held.filter(function(s) { return !by[s] || by[s].quote !== quotes[s] })
    if (stale.length > 0) {
      for (var i = 0; i < stale.length && Date.now() < until; i++)
        by[stale[i]] = { quote: quotes[stale[i]], text: JSON.stringify(quotes[stale[i]]) }
      textStep.start()
      return
    }
    var entries = root.quoteFeed.entries
    var kept = {}
    var saved = held.map(function(s) {
      kept[s] = by[s]
      return JSON.stringify(s) + ':{"quote":' + by[s].text + ',"receivedAt":' + JSON.stringify((entries[s] || {}).receivedAt || 0) + "}"
    })
    root.quoteTexts.by = kept
    root.files.write(root.path, '{"version":1,"quotes":{' + saved.join(",") + "}}\n")
  }
}
