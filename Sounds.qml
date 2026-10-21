import QtQuick
import Quickshell
import Quickshell.Io
import "ReplaySound.js" as ReplaySound
// The sounds for what you just did, while they are on (`turnedOn`, the data
// file's `sounds`): adding a symbol, removing a row, undoing the removal,
// which plays the removal backwards, and a replay, which plays the chart
// (`ReplaySound`). Each in the look's voice, and one at a time: a new sound
// stops the one playing. Nothing else sounds: no refresh, price, or bell,
// and nothing you do to look around. `pw-play`, which PipeWire ships, plays
// them at the system's volume; there is no volume of Stonks' own. The
// surfaces say when; this knows only how.
Item {
  id: root

  property bool turnedOn: true
  property bool retro: false
  // The surface whose replay is playing, so that replay's end stops only
  // its own sound; null for any other sound.
  property var replayOwner: null
  readonly property string replayPath: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache")
    + "/grvc.stonks/replay.wav"

  // One of the fixed sounds: "add", "remove", or "undo".
  function play(name) {
    if (!turnedOn) return
    replayOwner = null
    start(String(Qt.resolvedUrl("sounds/" + (retro ? "retro" : "smooth") + "/" + name + ".wav")).replace(/^file:\/\//, ""))
  }

  // A replay's sound, made from the chart as it starts: `chart` holds the
  // chart's geometry, the retro chart's grid, where the replay runs from and
  // to along it, and its length in seconds. The file is written whole before
  // `pw-play` starts: the write blocks, and lands by a rename, so a player
  // still reading the last one keeps it.
  function playReplay(owner, chart) {
    if (!turnedOn) return
    var sound = retro ? ReplaySound.retro(chart.grid, chart.from, chart.to, chart.seconds)
      : ReplaySound.smooth(chart.geometry, chart.from, chart.to, chart.seconds)
    replayFile.setData(ReplaySound.wav(sound))
    replayOwner = owner
    start(replayPath)
  }

  // A replay cut short stops its sound, and no other.
  function stopReplay(owner) {
    if (!owner || owner !== replayOwner) return
    replayOwner = null
    player.running = false
  }

  // Turned off, the sound playing stops.
  onTurnedOnChanged: if (!turnedOn) {
    replayOwner = null
    player.running = false
  }

  // A sound still playing ends first: the next waits for it to go.
  function start(file) {
    player.exec(["pw-play", "--media-role", "Notification", "--latency", "20ms", file])
  }

  Process { id: player }

  FileView {
    id: replayFile
    path: root.replayPath
    preload: false
    blockWrites: true
    atomicWrites: true
  }
}
