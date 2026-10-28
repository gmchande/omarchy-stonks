import QtQuick
// One host's gate, which every request to that host asks first, from every
// feed: a budget, and a pause when the host stops answering or says no. On
// the service's clock.
//
// The budget holds `capacity` requests and refills at `perMinute`; normal
// use never reaches its edge, and the first time it holds a request back it
// says so. Runs of quotes (`bulk`) leave `reserve` of it for single requests,
// a history, a search, cap and P/E, so a long list never starves them. A
// pause comes from what came back (`report`): no answer at all waits 2 s,
// doubling to 60, since nothing reached the server; a refusal (429, 503)
// waits for Retry-After, else 1 minute, doubling, either for 30 minutes at
// most, so a huge or hostile Retry-After can't silence Stonks for days.
// Each wait varies by ±20%, so installs don't all come back at the same
// second. Once a pause has run out, one request goes alone, and only its
// answer reopens the host: each request carries the `ticket` it was let
// through on, and an answer to one let through before the latest pause
// began says nothing of the host now. A reader asking again (`hurry`) ends
// a pause for no answer at once, never a refusal's.
Item {
  id: root

  property string host: ""
  // Whatever keeps the clock, the service: its wall clock (`wallSecond`),
  // read at each call, never its `now`, which trails the wall between ticks
  // while nothing is open, nor a binding's copy.
  property var clock: null
  property int capacity: 80
  property real perMinute: 40
  property int reserve: 10

  property real tokens: capacity
  property int filledAt: 0
  // Why the host is paused: "" while it answers, "none" or "refused".
  property string pause: ""
  property int pausedUntil: 0
  // Pauses of this kind in a row, which set the next one's length.
  property int strikes: 0
  // The one request sent alone after a pause is out.
  property bool probing: false
  property bool warned: false
  // Moves on as each pause begins: what a request is let through on.
  property int ticket: 0

  readonly property bool paused: pause !== ""

  // The host answered again after a pause.
  signal reopened()

  function now() {
    return clock ? clock.wallSecond() : 0
  }

  function refill() {
    if (filledAt > 0) root.tokens = Math.min(capacity, tokens + Math.max(0, now() - filledAt) * perMinute / 60)
    root.filledAt = now()
  }

  // How many of `count` requests may go now: up to the budget while the host
  // answers, less the reserve for a `bulk` run; one alone once a pause has
  // run out; none while it lasts. Each goes on the gate's `ticket` as it is.
  function take(count, bulk) {
    if (count <= 0) return 0
    refill()
    if (paused) {
      if (probing || now() < pausedUntil) return 0
      root.probing = true
      root.tokens = Math.max(0, tokens - 1)
      return 1
    }
    var granted = Math.max(0, Math.min(count, Math.floor(tokens - (bulk ? reserve : 0))))
    if (granted < count && !warned) {
      root.warned = true
      console.warn("stonks: " + host + "'s budget held back " + (count - granted) + " requests")
    }
    root.tokens = tokens - granted
    return granted
  }

  // Whether a request that can wait (a chart fetched ahead of a click) may
  // go: only while the host answers and at least half the budget is left,
  // so quotes and the charts on show always find it. It takes nothing.
  function spare() {
    refill()
    return !paused && tokens >= capacity / 2
  }

  // What the answers to requests let through on `ticket` said, by kind
  // (`Fetch.answerKind`): a refusal pauses the host, any other answer
  // reopens it, and no answer at all pauses it briefly. Answers on an older
  // ticket can only refuse.
  function report(kinds, retryAfter, ticket) {
    var current = ticket === root.ticket
    if (current) root.probing = false
    if (kinds.indexOf("refused") >= 0) {
      // The rest of the run that began this pause adds no strike.
      if (!current && pause === "refused") return
      root.strikes = pause === "refused" ? strikes + 1 : 1
      begin("refused", Math.min(retryAfter > 0 ? retryAfter : 60 * Math.pow(2, strikes - 1), 30 * 60))
    } else if (!current) {
      return
    } else if (kinds.some(function(k) { return k !== "none" })) {
      var was = paused
      root.pause = ""
      root.strikes = 0
      if (was) root.reopened()
    } else if (kinds.length > 0) {
      root.strikes = pause === "none" ? strikes + 1 : 1
      begin("none", Math.min(2 * Math.pow(2, strikes - 1), 60))
    }
  }

  // A reader asked again, by r or RETRY: the network may be back, so a pause
  // for no answer at all ends now, and its lone request goes with what was
  // asked, rather than up to a minute after the network is back. A
  // refusal's pause holds: the host asked for fewer requests.
  function hurry() {
    if (pause === "none" && !probing && pausedUntil > now()) root.pausedUntil = now()
  }

  // A pause of `kind` for about `seconds`, on a new ticket: whatever was let
  // through before it, a probe still out included, no longer speaks for the
  // host, and the next probe may go once it ends.
  function begin(kind, seconds) {
    root.pause = kind
    root.ticket = root.ticket + 1
    root.probing = false
    root.pausedUntil = now() + Math.max(1, Math.round(seconds * (0.8 + 0.4 * Math.random())))
  }
}
