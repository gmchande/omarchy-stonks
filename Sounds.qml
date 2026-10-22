import QtQuick
import Quickshell
import Quickshell.Io
import "ChartSound.js" as ChartSound
// The sounds, while they are on (`turnedOn`, the data file's `sounds`):
// for what you just did, adding a symbol, removing a row, undoing the
// removal, which plays the removal backwards, taking a screenshot, the
// shutter, a replay, which plays the chart, and the chimes, the chart's
// bars as the scrub crosses them (`ChartSound`); and the market's bell
// (`Bell`). Each in the look's voice.
// The fixed sounds, the bell, and the replay play one at a time: a new one
// stops the one playing. The chimes overlap and ring out. Nothing else
// sounds: no refresh or price. `pw-play`, which PipeWire ships, plays them
// at the system's volume; there is no volume of Stonks' own. The surfaces
// and the bell say when; this knows only how.
Item {
  id: root

  property bool turnedOn: true
  property bool retro: false
  // A popup or window is open where a screen shows it.
  property bool surfacesOpen: false
  // The output is kept awake while sounds are on and a surface is open, and
  // for 10 s after the last closes, so the first sound plays at once: an
  // output asleep wakes as a sound starts, and cuts or delays its start.
  readonly property bool keepingAwake: turnedOn && (surfacesOpen || afterClose.running)
  // The surface whose replay is playing, so that replay's end stops only
  // its own sound; null for any other sound.
  property var replayOwner: null
  readonly property string folder: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/grvc.stonks"
  readonly property string replayPath: folder + "/replay.wav"
  readonly property string voice: retro ? "retro" : "smooth"
  // The chimes' files written this run, by name ("retro-3"): each look's
  // eleven, written ahead as sounds turn on or the look changes, and again
  // on the next run.
  property var chimesWritten: ({})
  // At most one chime every 45 ms, 22 a second: a bar struck sooner waits
  // out the gap, and the latest waiting wins (`waiting`, or -1), so a sweep
  // ends on the bar under the pointer.
  readonly property int chimeGap: 45
  property real lastChime: 0
  property int waiting: -1

  // One of the fixed sounds: "add", "remove", "undo", or "shutter".
  function play(name) {
    if (!turnedOn) return
    replayOwner = null
    start(String(Qt.resolvedUrl("sounds/" + voice + "/" + name + ".wav")).replace(/^file:\/\//, ""))
  }

  // A replay's sound, made from the chart as it starts: `chart` holds the
  // chart's geometry, the retro chart's grid, where the replay runs from and
  // to along it, and its length in seconds. The file is written whole before
  // `pw-play` starts: the write blocks, and lands by a rename, so a player
  // still reading the last one keeps it.
  function playReplay(owner, chart) {
    if (!turnedOn) return
    var sound = retro ? ChartSound.retro(chart.grid, chart.from, chart.to, chart.seconds)
      : ChartSound.smooth(chart.geometry, chart.from, chart.to, chart.seconds)
    soundFile.path = replayPath
    soundFile.setData(ChartSound.wav(sound))
    replayOwner = owner
    start(replayPath)
  }

  // A replay cut short stops its sound, and no other.
  function stopReplay(owner) {
    if (!owner || owner !== replayOwner) return
    replayOwner = null
    player.running = false
  }

  // A chime: bar `bar` (0..10, `ChartSound.barAt`) struck in the look's
  // voice; -1, a place with no bar, strikes nothing, and drops a bar
  // waiting, so nothing starts where the line lifts.
  function chime(bar) {
    if (!turnedOn) return
    if (bar < 0) {
      chimeWait.stop()
      waiting = -1
      return
    }
    var wait = lastChime + chimeGap - Date.now()
    if (wait <= 0) return strike(bar)
    waiting = bar
    if (!chimeWait.running) {
      chimeWait.interval = Math.ceil(wait)
      chimeWait.start()
    }
  }

  // A bar struck now: one waiting is behind it, and never plays after it.
  function strike(bar) {
    chimeWait.stop()
    waiting = -1
    lastChime = Date.now()
    chimer.write(written(voice, bar) + "\n")
  }

  // A chime's name ("retro-3"), its file written unless this run has.
  function written(look, bar) {
    var name = look + "-" + bar
    if (!chimesWritten[name]) {
      soundFile.path = folder + "/chime-" + name + ".wav"
      soundFile.setData(ChartSound.wav(ChartSound.chime(look === "retro", bar)))
      chimesWritten[name] = true
    }
    return name
  }

  // Turned off, the sound playing stops, and a chime waiting with it. The
  // look's chimes are written ahead, one every 100 ms, so the first pass
  // over the chart writes nothing: written back to back, smooth's eleven
  // held the shell's thread for about 80 ms.
  onTurnedOnChanged: {
    if (!turnedOn) {
      replayOwner = null
      player.running = false
      chimeWait.stop()
      waiting = -1
    }
    ahead.restart()
  }
  onVoiceChanged: ahead.restart()
  Component.onCompleted: {
    ahead.restart()
    silence.running = keepingAwake
  }
  Timer {
    id: ahead
    interval: 100
    repeat: true
    onTriggered: {
      if (!root.turnedOn) return stop()
      for (var bar = 0; bar < 11; bar++) {
        if (!root.chimesWritten[root.voice + "-" + bar]) return root.written(root.voice, bar)
      }
      stop()
    }
  }

  Timer {
    id: chimeWait
    onTriggered: {
      var bar = root.waiting
      root.waiting = -1
      if (bar >= 0) root.strike(bar)
    }
  }

  // One at a time: exec stops a sound still playing, and starts this one
  // once it has gone.
  function start(file) {
    player.exec(["pw-play", "--media-role", "Notification", "--latency", "20ms", file])
  }

  Process { id: player }

  // The output kept awake (`keepingAwake`): a stream of silence, PipeWire's
  // pw-cat reading zeros, which holds the speakers or headphones open as a
  // sound playing does, and nothing while sounds are off or every surface
  // has been closed 10 s. A pw-cat that ends while it's wanted, as when
  // PipeWire restarts, starts again 2 s later.
  onSurfacesOpenChanged: if (!surfacesOpen) afterClose.restart()
  Timer { id: afterClose; interval: 10000 }
  onKeepingAwakeChanged: silence.running = keepingAwake
  Process {
    id: silence
    command: ["pw-cat", "--playback", "--raw", "--rate", "24000", "--channels", "1", "--format", "s16",
      "--media-role", "Notification", "/dev/zero"]
    onExited: if (root.keepingAwake) silenceAgain.restart()
  }
  Timer {
    id: silenceAgain
    interval: 2000
    onTriggered: if (root.keepingAwake && !silence.running) silence.running = true
  }

  // The market's bell, unless an app is recording from a microphone, as a
  // call does: `pw-dump` lists PipeWire's nodes once, as the bell is due,
  // for at most 3 s and 4 MB (the list runs to about half a megabyte), so
  // no answer can hold the bell or fill the shell. An answer that ran out
  // of time, failed, or reached the cap counts as recording, by the
  // pipeline's own exit and the bytes it gave, never by the clock: the bell
  // stays quiet. One still out is stopped within 4 s, before the next bell.
  function ring() {
    if (turnedOn && !listening.running) listening.running = true
  }

  // Whether PipeWire's nodes (`pw-dump`'s answer) hold a microphone being
  // recorded: an app's capture stream running, not one reading a speaker's
  // monitor, as a level meter does. An answer that can't be read keeps the
  // bell quiet too.
  function recording(dump) {
    var nodes
    try { nodes = JSON.parse(dump) } catch (e) { return true }
    return !Array.isArray(nodes) || nodes.some(function(node) {
      var props = node.info && node.info.props || {}
      return node.type === "PipeWire:Interface:Node" && props["media.class"] === "Stream/Input/Audio"
        && node.info.state === "running" && String(props["stream.capture.sink"]) !== "true"
    })
  }

  // A byte past 4 MB is read, so an answer that reaches the cap shows it.
  Process {
    id: listening
    command: ["bash", "-c", "set -o pipefail; timeout -k 1 3 pw-dump | head -c 4000001"]
    stdout: StdioCollector { id: answer }
    onExited: function(code) {
      if (root.turnedOn && code === 0 && answer.data.byteLength <= 4000000 && !root.recording(answer.text)) root.play("bell")
    }
  }

  // The chimes' player: one shell for as long as sounds are on, reading a
  // chime's name a line, and starting a pw-play for each in the background,
  // so the chimes overlap and the shell's own thread starts no process per
  // chime. It plays nothing but a chime's file: any other line it skips.
  // Each pw-play has 2 s, four times a chime's length, so a PipeWire that
  // stalls can't pile them up. Each starts from a subshell that ends at
  // once, so this shell keeps no record of it: started from the shell
  // itself, each chime grew it by about a third of a kilobyte, 10 MB over
  // 20,000 chimes. When Stonks goes its input closes and it ends; a chime
  // ringing then rings out, half a second at most.
  Process {
    id: chimer
    running: root.turnedOn
    stdinEnabled: true
    command: ["sh", "-c", "while read -r name; do case $name in smooth-[0-9]|smooth-10|retro-[0-9]|retro-10) "
      + "( timeout -k 1 2 pw-play --media-role Notification --latency 20ms \"$1/chime-$name.wav\" & ) ;; esac; done", "sh", root.folder]
  }

  FileView {
    id: soundFile
    preload: false
    blockWrites: true
    atomicWrites: true
  }
}
