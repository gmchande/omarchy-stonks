.pragma library
// `omarchy plugin update` moves to main, which moves only at a release, so
// main's manifest names the newest Stonks.

var MANIFEST_URL = "https://raw.githubusercontent.com/gmchande/omarchy-stonks/main/manifest.json"

// The id every user's install has. A copy run under another, beside it,
// wears a mark on its pill and its header (`otherCopy`), so the two tell
// apart; a user never sees it.
var RELEASED_ID = "grvc.stonks"

function otherCopy(id) {
  return !!id && id !== RELEASED_ID
}

var VERSION = /^\d+(\.\d+)*$/

function manifestVersion(text) {
  var version
  try { version = JSON.parse(text).version } catch (e) { return "" }
  return typeof version === "string" && VERSION.test(version) ? version : ""
}

function isNewer(version, than) {
  if (!VERSION.test(version) || !VERSION.test(than)) return false
  var a = version.split(".").map(Number)
  var b = than.split(".").map(Number)
  for (var i = 0; i < Math.max(a.length, b.length); i++) {
    var x = a[i] || 0
    var y = b[i] || 0
    if (x !== y) return x > y
  }
  return false
}
