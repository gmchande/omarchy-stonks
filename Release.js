.pragma library
// Which Stonks is newest: the version in the manifest on main, the branch
// `omarchy plugin update` moves to, which moves only at a release. Knows
// nothing of when it is asked.

var MANIFEST_URL = "https://raw.githubusercontent.com/gmchande/omarchy-stonks/main/manifest.json"

// A version as Stonks numbers them: whole numbers between dots, "1.0.1".
var VERSION = /^\d+(\.\d+)*$/

// The version a manifest's text names, "" for one that names none.
function manifestVersion(text) {
  var version
  try { version = JSON.parse(text).version } catch (e) { return "" }
  return typeof version === "string" && VERSION.test(version) ? version : ""
}

// Whether `version` comes after `than`, number by number: 1.0.10 after
// 1.0.9. Never when either is not a version.
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
