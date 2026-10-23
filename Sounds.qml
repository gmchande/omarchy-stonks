import QtQuick
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
  // The surfaces whose chart is being scrubbed, by the pointer on it or by
  // keys, where a screen shows it (`scrubbing`).
  property var scrubbed: []
  // The output is kept awake while sounds are on and a chart is scrubbed,
  // and for 1 s after, so a chime struck after a pause plays at once: an
  // output asleep wakes as a sound starts, and cuts or delays its start.
  // Only then: headphones go to whichever computer plays, and an open popup
  // alone mustn't take them.
  readonly property bool keepingAwake: turnedOn && (scrubbed.length > 0 || afterScrub.running)
  // The surface whose replay is playing, so that replay's end stops only
  // its own sound; null for any other sound.
  property var replayOwner: null
  // Stonks' files (`Service.files`, `OwnerOnly`): the replay's and the
  // chimes' are written in its cache folder, through it.
  property var files: null
  readonly property string folder: files ? files.folder : ""
  readonly property string replayPath: folder + "/replay.wav"
  readonly property string voice: retro ? "retro" : "smooth"
  // The files in the cache's folder written this run, by name: each look's
  // chimes and lead-ins, written ahead as sounds turn on or the look
  // changes, and again on the next run.
  property var madeThisRun: ({})
  readonly property var fixedSounds: ["add", "remove", "undo", "shutter", "bell"]
  // At most one chime every 45 ms, 22 a second: a bar struck sooner waits
  // out the gap, and the latest waiting wins (`waiting`, or -1), so a sweep
  // ends on the bar under the pointer.
  readonly property int chimeGap: 45
  property real lastChime: 0
  property int waiting: -1

  // A sound that may start on an output asleep opens with 150 ms of silence,
  // its lead-in (`led`), so the output's waking eats the silence and never
  // the sound: it comes later, whole. PipeWire puts an output to sleep after
  // 5 s with nothing playing; Stonks hears only its own sounds, so it counts
  // the output asleep 4 s after its last start or its silence's end
  // (`asleepAfter`). A sound starting within 1 s of the one that woke the
  // output opens with the lead-in too, as the output may still be waking:
  // this laptop's speakers took 135 to 182 ms, and Bluetooth can take
  // longer.
  readonly property int leadIn: 150
  property real asleepAfter: 0
  property real wokeAt: 0

  // A sound starts now: true when it opens with the lead-in.
  function starting() {
    var now = Date.now()
    if (now >= asleepAfter) wokeAt = now
    asleepAfter = Math.max(asleepAfter, now + 4000)
    return now - wokeAt < 1000
  }

  // `bytes`, a WAV with the plain 44-byte header the chimes' and the
  // bundled sounds have, its lead-in of silence before the sound.
  function led(bytes) {
    var zeros = Math.round(new DataView(bytes).getUint32(24, true) * leadIn / 1000) * 2
    var out = new ArrayBuffer(bytes.byteLength + zeros)
    new Uint8Array(out).set(new Uint8Array(bytes, 0, 44))
    new Uint8Array(out, 44 + zeros).set(new Uint8Array(bytes, 44))
    var d = new DataView(out)
    d.setUint32(4, out.byteLength - 8, true)
    d.setUint32(40, out.byteLength - 44, true)
    return out
  }

  // A surface says whether its chart is being scrubbed. As the last scrub
  // ends, the 1 s hold starts before the list empties, so `keepingAwake`
  // never dips in between.
  function scrubbing(surface, on) {
    var others = scrubbed.filter(function(s) { return s !== surface })
    if (on) others.push(surface)
    if (others.length === scrubbed.length) return
    if (others.length === 0) afterScrub.restart()
    scrubbed = others
  }

  function bundled(look, name) {
    return String(Qt.resolvedUrl("sounds/" + look + "/" + name + ".wav")).replace(/^file:\/\//, "")
  }

  // One of the fixed sounds: "add", "remove", "undo", "shutter", or "bell";
  // with its lead-in from the cache's folder once that is private, and
  // without where it can't be (`OwnerOnly.made`).
  function play(name) {
    if (!turnedOn) return
    replayOwner = null
    var lead = starting()
    start(lead && files.made ? written(voice, name, true) : bundled(voice, name))
  }

  // A replay's sound, made from the chart as it starts: `chart` holds the
  // chart's geometry, the retro chart's grid, where the replay runs from and
  // to along it, and its length in seconds. The file, `replay.wav` or with
  // its lead-in `lead-replay.wav`, is written whole before `pw-play` starts:
  // the write blocks, and lands by a rename, so a player still reading the
  // last one keeps it. A replay of what that file last held, the same look,
  // chart, and run, plays it again: making it held a retro start about
  // 10 ms more than a smooth one. None plays while its file can't be
  // written yet (`OwnerOnly.write`).
  property var replayHeld: ({})
  function playReplay(owner, chart) {
    if (!turnedOn) return
    var lead = starting()
    var path = lead ? folder + "/lead-replay.wav" : replayPath
    var made = { retro: retro, chart: retro ? chart.grid : chart.geometry, from: chart.from, to: chart.to, seconds: chart.seconds }
    var last = replayHeld[path]
    if (!last || last.retro !== made.retro || last.chart !== made.chart || last.from !== made.from
        || last.to !== made.to || last.seconds !== made.seconds) {
      var sound = retro ? ChartSound.retro(chart.grid, chart.from, chart.to, chart.seconds)
        : ChartSound.smooth(chart.geometry, chart.from, chart.to, chart.seconds)
      var bytes = ChartSound.wav(sound)
      if (!files.write(path, lead ? led(bytes) : bytes)) return
      replayHeld[path] = made
    }
    replayOwner = owner
    start(path)
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
    var path = written(voice, bar, starting())
    chimer.write(path.slice(folder.length + 1) + "\n")
  }

  // A file's name in the cache's folder: a chime, `what` its bar,
  // "chime-retro-3.wav", or "chime-lead-retro-3.wav" with its lead-in; or a
  // fixed sound with its lead-in, `what` its name, "lead-smooth-add.wav".
  function fileOf(look, what, lead) {
    return (typeof what === "number" ? "chime-" : "") + (lead ? "lead-" : "") + look + "-" + what + ".wav"
  }

  // A file's path in the cache's folder (`fileOf`), written unless this run
  // has: now, or once the folder is private (`OwnerOnly.write`), until then
  // playing the file an earlier run left, if any.
  function written(look, what, lead) {
    var file = fileOf(look, what, lead)
    if (!madeThisRun[file]) {
      var bytes = typeof what === "number" ? ChartSound.wav(ChartSound.chime(look === "retro", what)) : bundledBytes(look, what)
      files.write(folder + "/" + file, lead ? led(bytes) : bytes)
      madeThisRun[file] = true
    }
    return folder + "/" + file
  }

  // A bundled sound's bytes: a new path loads in the background, even
  // with blockLoading, so the read waits for that load, or it would hand
  // back the last file's.
  function bundledBytes(look, name) {
    bundledFile.path = bundled(look, name)
    bundledFile.waitForJob()
    return bundledFile.data()
  }
  // The bundled sounds, read to write their lead-ins.
  FileView { id: bundledFile; blockLoading: true }

  // What a look writes ahead: its eleven chimes, each with its lead-in too,
  // and its fixed sounds' lead-ins.
  function aheadOf(look) {
    var list = []
    for (var bar = 0; bar < 11; bar++) list.push([bar, false], [bar, true])
    fixedSounds.forEach(function(name) { list.push([name, true]) })
    return list
  }

  // Turned off, the sound playing stops, and a chime waiting with it. The
  // look's files are written ahead, one every 100 ms, so the first pass
  // over the chart writes nothing: written back to back, smooth's eleven
  // chimes held the shell's thread for about 80 ms.
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
  Component.onCompleted: ahead.restart()
  Timer {
    id: ahead
    interval: 100
    repeat: true
    onTriggered: {
      if (!root.turnedOn) return stop()
      var look = root.voice
      var due = root.aheadOf(look).filter(function(f) { return !root.madeThisRun[root.fileOf(look, f[0], f[1])] })
      if (due.length === 0) return stop()
      root.written(look, due[0][0], due[0][1])
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
  // once it has gone. Each has 4 s, twice the longest, a replay's 2 s, so a
  // PipeWire that stalls can't hold one.
  function start(file) {
    player.exec(["timeout", "-k", "1", "4", "pw-play", "--media-role", "Notification", "--latency", "20ms", file])
  }

  Process { id: player }

  // The output kept awake (`keepingAwake`): a stream of silence, PipeWire's
  // pw-cat reading zeros, which holds the speakers or headphones open as a
  // sound playing does, and nothing while sounds are off or no chart has
  // been scrubbed for 1 s. Its start may wake the output, as a sound's does.
  // A pw-cat that ends while it's wanted, as when PipeWire restarts, starts
  // again 2 s later.
  Timer { id: afterScrub; interval: 1000 }
  onKeepingAwakeChanged: {
    if (keepingAwake) {
      starting()
      asleepAfter = Infinity
    } else {
      asleepAfter = Date.now() + 4000
    }
    silence.running = keepingAwake
  }
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
  // chime's file name a line, and starting a pw-play for each in the
  // background, so the chimes overlap and the shell's own thread starts no
  // process per chime. It plays nothing but a chime's file: any other line
  // it skips. Each pw-play has 2 s, four times a chime's length, so a
  // PipeWire that stalls can't pile them up. Each starts from a subshell
  // that ends at once, so this shell keeps no record of it: started from
  // the shell itself, each chime grew it by about a third of a kilobyte,
  // 10 MB over 20,000 chimes. When Stonks goes its input closes and it
  // ends; a chime ringing then rings out, half a second at most.
  Process {
    id: chimer
    running: root.turnedOn
    stdinEnabled: true
    command: ["sh", "-c", "while read -r name; do case $name in "
      + "chime-smooth-[0-9].wav|chime-smooth-10.wav|chime-retro-[0-9].wav|chime-retro-10.wav"
      + "|chime-lead-smooth-[0-9].wav|chime-lead-smooth-10.wav|chime-lead-retro-[0-9].wav|chime-lead-retro-10.wav) "
      + "( timeout -k 1 2 pw-play --media-role Notification --latency 20ms \"$1/$name\" & ) ;; esac; done", "sh", root.folder]
  }
}
