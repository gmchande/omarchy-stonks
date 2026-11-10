.pragma library
// The one curl every feed runs, several URLs over one connection. Knows
// nothing of what it fetches.

var USER_AGENT = "Mozilla/5.0 (Omarchy Stonks)"

// Curl writes this line after each answer; a JSON body never holds a
// newline followed by it. Curl's status is 000 when nothing answered.
var ANSWER_MARK = "@@stonks"

// Each cap is above the largest real answer, uncompressed: a day's chart up
// to 22 KB, a spark of 20 listings 90 KB, a history of 500 bars 60 KB,
// Robinhood's trades 56.3 KB a listing a day and 2.6 KB an hour, the rest a
// few KB.
var DAY_CAP = 64000
var SPARK_CAP = 400000
var FUNDAMENTALS_CAP = 64000
var SEARCH_CAP = 64000
var HISTORY_CAP = 256000
var MANIFEST_CAP = 16000

function overnightCap(count, span) {
  return 16000 + (span === "hour" ? 8000 : 80000) * count
}

function instrumentsCap(count) {
  return 16000 + 8000 * count
}

// `--max-time` is per URL, so no URL holds a run more than 10 s.
function curlCommand(urls, maxBytes) {
  return ["curl", "-sS", "--compressed", "--max-filesize", String(maxBytes),
    "--connect-timeout", "5", "--max-time", "10", "-A", USER_AGENT,
    "-w", "\\n" + ANSWER_MARK + " %{urlnum} %{http_code} %{exitcode} %header{retry-after}\\n"].concat(urls)
}

// none: no HTTP answer, as with no network or a timeout before the status.
// refused: the host wants fewer requests. missing: asking again won't help.
function answerKind(status, exit) {
  if (status === 0) return "none"
  if (status === 429 || status === 503) return "refused"
  if (exit !== 0 || status >= 500) return "bad"
  if (status >= 400) return "missing"
  return status === 200 ? "ok" : "bad"
}

function answers(text, from) {
  var out = []
  var pattern = new RegExp("\\n" + ANSWER_MARK + " (\\d+) (\\d{3}) (\\d+) ?([^\\n]*)\\n", "g")
  from = from || 0
  pattern.lastIndex = from
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
      retryAfter: retryAfter,
      end: pattern.lastIndex
    })
    from = pattern.lastIndex
  }
  return out
}
