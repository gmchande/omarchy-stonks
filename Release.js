.pragma library
// `omarchy plugin update` moves to main, which moves only at a release, so
// main's manifest names the newest Stonks.

var MANIFEST_URL = "https://raw.githubusercontent.com/gmchande/omarchy-stonks/main/manifest.json"

// The id every user's install has. A copy run under another, beside it,
// wears a mark on its pill (`otherCopy`), so the two tell apart; a user
// never sees it.
var RELEASED_ID = "grvc.stonks"

// What the footer says of saving and updating, from `state`, { unreadable,
// saveFailed, editsUnsaved, updatedTo, releasedTo }: the lists file can't be
// read, a save didn't land, changes made meanwhile wait, Stonks was updated
// to `updatedTo` and wants the shell restarted, a newer `releasedTo` is out.
// A save that didn't land is said ahead of the update, since a restart would
// lose the changes. Where the fix won't fit beside the notice, it drops "or
// remove" and keeps the file's full path, `listsFile`.
function footerNotice(state, listsFile) {
  var updatedTo = state.updatedTo || ""
  var unsaved = state.unreadable ? !!state.editsUnsaved : !!state.saveFailed
  var restartable = !unsaved && !state.unreadable
  return {
    unreadable: !!state.unreadable,
    saveFailed: !!state.saveFailed,
    updatedTo: updatedTo,
    text: unsaved ? "Your changes aren't saved" : state.unreadable ? "Couldn't load your lists"
      : updatedTo !== "" ? "Updated to " + updatedTo + " · click to restart the shell" : "",
    actions: state.unreadable ? ["fix or remove " + listsFile, "fix " + listsFile] : unsaved ? ["click to try again"] : [],
    updateOffer: state.releasedTo && updatedTo === "" ? state.releasedTo : "",
    restartable: restartable,
    restartOffered: updatedTo !== "" && restartable
  }
}

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
