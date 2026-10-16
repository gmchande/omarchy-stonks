// The one curl every feed runs: one or several URLs in one run, over one
// connection, compressed, each answer capped and followed by a line that
// says what came back. Knows nothing of what it fetches.

var USER_AGENT = "Mozilla/5.0 (Omarchy Stonks)"

// The line curl writes after each answer: the URL's place in the run, the
// HTTP status (000 when nothing answered), curl's exit code for it, and any
// Retry-After. A JSON body never holds a newline followed by this.
var ANSWER_MARK = "@@stonks"

// Caps, each above the largest real answer even uncompressed: a day's chart
// is about 13 KB raw (BTC-USD's 22), cap and P/E and a search a few KB, a
// history of 500 bars about 60 KB, Robinhood's prints 56.3 KB a listing and
// its instruments a few KB.
var DAY_CAP = 64000
var FUNDAMENTALS_CAP = 64000
var SEARCH_CAP = 64000
var HISTORY_CAP = 256000

function overnightCap(count) {
  return 16000 + 80000 * count
}

function instrumentsCap(count) {
  return 16000 + 8000 * count
}

// `urls` are fetched in turn; an answer over `maxBytes` is a bad answer.
// `--max-time` is per URL, so a run's own limit is its feed's.
function curlCommand(urls, maxBytes) {
  return ["curl", "-sS", "--compressed", "--max-filesize", String(maxBytes),
    "--connect-timeout", "5", "--max-time", "10", "-A", USER_AGENT,
    "-w", "\\n" + ANSWER_MARK + " %{urlnum} %{http_code} %{exitcode} %header{retry-after}\\n"].concat(urls)
}

// What one answer means for whoever sent it:
//   ok       a whole 200 answer, for the feed to parse;
//   none     no HTTP answer at all: no network, no connection, no TLS, or a
//            timeout before the status;
//   refused  429 or 503: the host wants fewer requests;
//   bad      another 5xx, an answer cut short, or one over its cap;
//   missing  another 4xx: the question is wrong, asking again won't help.
function answerKind(status, exit) {
  if (status === 0) return "none"
  if (status === 429 || status === 503) return "refused"
  if (exit !== 0 || status >= 500) return "bad"
  if (status >= 400) return "missing"
  return status === 200 ? "ok" : "bad"
}

// A run's output as its answers, by the URL's place in the run: { index,
// status, kind, body, retryAfter } (seconds, 0 when none was sent). A URL the
// run never reached, stopped first, has none.
function answers(text) {
  var out = []
  var pattern = new RegExp("\\n" + ANSWER_MARK + " (\\d+) (\\d{3}) (\\d+) ?([^\\n]*)\\n", "g")
  var from = 0
  var match
  while ((match = pattern.exec(text)) !== null) {
    var status = Number(match[2])
    var exit = Number(match[3])
    var retryAfter = /^\s*\d+\s*$/.test(match[4]) ? Number(match[4]) : 0
    out.push({
      index: Number(match[1]),
      status: status,
      kind: answerKind(status, exit),
      body: text.slice(from, match.index),
      retryAfter: retryAfter
    })
    from = pattern.lastIndex
  }
  return out
}

// The run's one answer as a body to parse, "" for anything but a whole 200.
function soleBody(text) {
  var all = answers(text)
  return all.length && all[0].kind === "ok" ? all[0].body : ""
}
