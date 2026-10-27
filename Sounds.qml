import QtQuick
import Quickshell.Io
import "ChartSound.js" as ChartSound
// The sounds, while they are on (`turnedOn`, the data file's `sounds`, off
// until it says true; while off, nothing here runs):
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

  property bool turnedOn: false
  property bool retro: false
  // The output is kept awake while sounds are on and a scrub moves, and
  // for 1 s after it last moved or ended (`scrubHeld`), so a chime struck
  // after a pause plays at once: an output asleep wakes as a sound starts,
  // and cuts or delays its start. Only then, and while a replay waits for
  // the output to wake (`whenAwake`): headphones go to whichever computer
  // plays, so neither an open popup nor a scrub left standing takes them.
  readonly property bool keepingAwake: turnedOn && (scrubHeld || replaysWaiting.length > 0)
  // A scrub moved, started, or ended in the last second (`afterScrub`): a
  // flag of its own, since the timer's restart turns `running` off and on.
  property bool scrubHeld: false
  // The surface whose replay is playing, so that replay's end stops only
  // its own sound; null for any other sound.
  property var replayOwner: null
  // Stonks' files (`Service.files`, `OwnerOnly`): the replay's and the
  // chimes' are written in its cache folder, through it.
  property var files: null
  readonly property string folder: files ? files.folder : ""
  readonly property string replayPath: folder + "/replay.wav"
  readonly property string voice: retro ? "retro" : "smooth"
  // The files in the cache's folder that hold the current sound, by name:
  // each look's chimes and lead-ins, written ahead as sounds turn on or the
  // look changes, or left current by an earlier run (`takeSurvey`).
  property var madeThisRun: ({})
  // What each look's files are made from now: the md5 of this file,
  // ChartSound.js, and the look's bundled sounds, as `takeSurvey` read
  // them, which the look's `stamp-<look>` in the folder holds once all its
  // files do; and the looks this run wrote a file of, "landed" while every
  // write did, else "failed", whose stamp is written again only once all
  // landed: a stamp over a failed write would keep the old sound for good.
  property var sources: ({})
  property var rewrote: ({})
  property bool surveyed: false
  readonly property var fixedSounds: ["add", "remove", "undo", "shutter", "bell"]
  // A chime's lead-ins, in ms (`leadAt`).
  readonly property var leadSteps: [30, 60, 90, 120, 150]
  // The names the chimes' player plays, as its `case` patterns.
  readonly property string chimeNames: {
    var names = []
    ;["smooth", "retro"].forEach(function(look) {
      [""].concat(leadSteps.map(function(ms) { return "lead" + ms + "-" })).forEach(function(lead) {
        names.push("chime-" + lead + look + "-[0-9].wav", "chime-" + lead + look + "-10.wav")
      })
    })
    return names.join("|")
  }
  // At most one chime every 45 ms, 22 a second: a bar struck sooner waits
  // out the gap, and the latest waiting wins (`waiting`, or -1), so a sweep
  // ends on the bar under the pointer.
  readonly property int chimeGap: 45
  property real lastChime: 0
  property int waiting: -1

  // A sound that may start on an output asleep opens with up to 150 ms of
  // silence, its lead-in (`led`), so the output's waking eats the silence
  // and never the sound: it comes later, whole. PipeWire puts an output to
  // sleep after 5 s with nothing playing; Stonks hears only its own sounds,
  // so it counts the output asleep 4 s after its last start or its
  // silence's end (`asleepAfter`). A sound that wakes it opens with the
  // whole lead-in, and so does every one after while it wakes: until the
  // stream of silence says it reached the output (`awakeAt`, pw-cat's
  // "streaming"), or without that stream, for 550 ms. Measured laptop
  // speakers wake in 135 to 182 ms; Bluetooth can take longer. Then the
  // lead-in shrinks a third as fast as time passes, in 30 ms steps, to none
  // 450 ms on: chimes come at least 45 ms apart (`chimeGap`), so one never
  // sounds before a chime struck ahead of it.
  readonly property int leadIn: 150
  property real asleepAfter: 0
  property real wokeAt: 0
  // When the output last woke and was reached, 0 before any, or -1 while
  // it wakes and nothing has said so yet.
  property real awakeAt: 0

  // A sound starts now: the lead-in it opens with, in ms, or 0.
  function starting() {
    var now = Date.now()
    if (now >= asleepAfter) {
      wokeAt = now
      awakeAt = -1
    }
    asleepAfter = Math.max(asleepAfter, now + 4000)
    return leadAt(now)
  }

  function leadAt(now) {
    var from = awakeAt >= 0 ? awakeAt : silence.running ? now : wokeAt + 550
    return Math.min(leadIn, Math.max(0, Math.ceil((leadIn - (now - from) / 3) / 30) * 30))
  }

  // Whether the output is awake and past its waking: reached 150 ms ago, so
  // the silence playing since has covered it.
  function awake(now) {
    if (now >= asleepAfter) return false
    return awakeAt >= 0 ? now >= awakeAt + leadIn : !silence.running && now - wokeAt >= 1000
  }

  // `bytes`, a WAV with the plain 44-byte header the chimes' and the
  // bundled sounds have, with `ms` of silence before the sound.
  function led(bytes, ms) {
    var zeros = Math.round(new DataView(bytes).getUint32(24, true) * ms / 1000) * 2
    var out = new ArrayBuffer(bytes.byteLength + zeros)
    new Uint8Array(out).set(new Uint8Array(bytes, 0, 44))
    new Uint8Array(out, 44 + zeros).set(new Uint8Array(bytes, 44))
    var d = new DataView(out)
    d.setUint32(4, out.byteLength - 8, true)
    d.setUint32(40, out.byteLength - 44, true)
    return out
  }

  // A chart's scrub moved, started, or ended where a screen shows it: the
  // output is held 1 s more.
  function scrubMoved() {
    scrubHeld = true
    afterScrub.restart()
  }

  function bundled(look, name) {
    return String(Qt.resolvedUrl("sounds/" + look + "/" + name + ".wav")).replace(/^file:\/\//, "")
  }

  // One of the fixed sounds: "add", "remove", "undo", "shutter", or "bell";
  // with the whole lead-in from the cache's folder when it needs any, once
  // that is private, and without where it can't be (`OwnerOnly.made`).
  function play(name) {
    if (!turnedOn) return
    replayOwner = null
    var lead = starting() > 0
    start(lead && files.made ? written(voice, name, leadIn) : bundled(voice, name))
  }

  // A replay's sound follows its sweep bar by bar, so it never opens with a
  // lead-in: a replay asked for while the output may sleep waits for it
  // instead, holding the silence until the output is awake (`awake`), or
  // 1.5 s at most, and then starts, picture and sound together. `go`
  // starts it; a surface asks again, or `stopReplay`, to drop its wait.
  property var replaysWaiting: []
  function whenAwake(owner, go) {
    replaysWaiting = replaysWaiting.filter(function(w) { return w.owner !== owner })
    if (!turnedOn || awake(Date.now())) return go()
    replaysWaiting = replaysWaiting.concat([{ owner: owner, go: go, since: Date.now() }])
    replayWait.start()
  }
  Timer {
    id: replayWait
    interval: 50
    repeat: true
    onTriggered: {
      if (root.replaysWaiting.length === 0) return stop()
      var now = Date.now()
      var ready = !root.turnedOn || root.awake(now)
      var due = root.replaysWaiting.filter(function(w) { return ready || now - w.since >= 1500 })
      if (due.length === 0) return
      due.forEach(function(w) { w.go() })
      root.replaysWaiting = root.replaysWaiting.filter(function(w) { return due.indexOf(w) < 0 })
      if (root.replaysWaiting.length === 0) stop()
    }
  }

  // A replay's sound, made from the chart as it starts: `chart` holds the
  // chart's geometry, the retro chart's grid, where the replay runs from and
  // to along it, and its length in seconds. The file is written whole before
  // `pw-play` starts: the write blocks, and lands by a rename, so a player
  // still reading the last one keeps it. A replay of what the last one
  // played, the same look, chart, and run, plays its file again: making it
  // holds a retro start about 10 ms longer than a smooth one. None plays while
  // its file can't be written yet (`OwnerOnly.write`).
  property var replayMade: null
  function playReplay(owner, chart) {
    if (!turnedOn) return
    starting()
    var made = { retro: retro, chart: retro ? chart.grid : chart.geometry, from: chart.from, to: chart.to, seconds: chart.seconds }
    var last = replayMade
    if (!last || last.retro !== made.retro || last.chart !== made.chart || last.from !== made.from
        || last.to !== made.to || last.seconds !== made.seconds) {
      var sound = retro ? ChartSound.retro(chart.grid, chart.from, chart.to, chart.seconds)
        : ChartSound.smooth(chart.geometry, chart.from, chart.to, chart.seconds)
      if (!files.write(replayPath, ChartSound.wav(sound))) return
      replayMade = made
    }
    replayOwner = owner
    start(replayPath)
  }

  // A replay cut short stops its sound, and no other; one still waiting
  // for the output stays unstarted.
  function stopReplay(owner) {
    if (!owner) return
    replaysWaiting = replaysWaiting.filter(function(w) { return w.owner !== owner })
    if (owner !== replayOwner) return
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
  // "chime-retro-3.wav", or "chime-lead90-retro-3.wav" with a 90 ms
  // lead-in; or a fixed sound with the whole lead-in, `what` its name,
  // "lead-smooth-add.wav".
  function fileOf(look, what, lead) {
    if (typeof what !== "number") return "lead-" + look + "-" + what + ".wav"
    return "chime-" + (lead ? "lead" + lead + "-" : "") + look + "-" + what + ".wav"
  }

  // A file's path in the cache's folder (`fileOf`), `lead` ms of silence
  // before its sound, written unless this run has: now, or once the folder
  // is private (`OwnerOnly.write`), until then playing the file an earlier
  // run left, if any.
  function written(look, what, lead) {
    var file = fileOf(look, what, lead)
    if (!madeThisRun[file]) {
      var bytes = typeof what === "number" ? ChartSound.wav(ChartSound.chime(look === "retro", what)) : bundledBytes(look, what)
      var landed = files.write(folder + "/" + file, lead ? led(bytes, lead) : bytes)
      madeThisRun[file] = true
      if (rewrote[look] !== "failed") rewrote[look] = landed ? "landed" : "failed"
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

  // What a look writes ahead: its eleven chimes, each with every lead-in
  // too, and its fixed sounds' lead-ins.
  function aheadOf(look) {
    var list = []
    for (var bar = 0; bar < 11; bar++) {
      list.push([bar, 0])
      leadSteps.forEach(function(ms) { list.push([bar, ms]) })
    }
    fixedSounds.forEach(function(name) { list.push([name, leadIn]) })
    return list
  }

  // Turned off, the sound playing stops, and a chime waiting with it. The
  // look's files are written ahead, one every 100 ms, so the first pass
  // over the chart writes nothing: written back to back, smooth's eleven
  // chimes hold the shell's thread for about 80 ms. Only the files that
  // don't hold the current sound are written (`takeSurvey`): writing all 71
  // of a look's on every start holds the thread 3 to 66 ms each, for 7 s.
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
      if (!root.surveyed) {
        if (root.folder !== "" && !survey.running) survey.running = true
        return
      }
      var look = root.voice
      var due = root.aheadOf(look).filter(function(f) { return !root.madeThisRun[root.fileOf(look, f[0], f[1])] })
      if (due.length > 0) return root.written(look, due[0][0], due[0][1])
      stop()
      // After the look's files, so none is newer than the stamp that
      // vouches for it.
      if (root.rewrote[look] === "landed" && root.sources[look]) root.files.write(root.folder + "/stamp-" + look, root.sources[look] + "\n")
      delete root.rewrote[look]
    }
  }

  // What the sounds are made from, by `md5sum`, and each look's stamp and
  // the files no newer than it, once a run, before anything is written
  // ahead. A file newer than its look's stamp was written by a Stonks that
  // keeps no stamp, an older one, so it may hold another sound. The answer
  // runs under 8 KB; it is read up to 64. Heard as it ends, or as it fails
  // to start, which says no exit.
  Process {
    id: survey
    command: ["timeout", "5", "sh", "-c", "{ cd -- \"$1\" && md5sum -- ChartSound.js Sounds.qml sounds/*/*.wav && cd -- \"$2\" || exit 0\n"
      + "for look in smooth retro; do\n"
      + "  [ -f \"stamp-$look\" ] || continue\n"
      + "  printf 'stamp %s %s\\n' \"$look\" \"$(head -c 64 -- \"stamp-$look\")\"\n"
      + "  for f in chime-*\"$look\"-*.wav lead-\"$look\"-*.wav; do\n"
      + "    [ -f \"$f\" ] && ! [ \"$f\" -nt \"stamp-$look\" ] && printf 'have %s\\n' \"$f\"\n"
      + "  done\n"
      + "done; } | head -c 65536", "sh", String(Qt.resolvedUrl(".")).replace(/^file:\/\//, ""), root.folder]
    stdout: StdioCollector { id: surveyAnswer }
    onRunningChanged: if (!running) root.takeSurvey(surveyAnswer.text)
  }

  // A look's files that hold the current sound count as made this run: its
  // stamp says what they are made from now, and the folder has them. Any
  // other, a missing one too, is written ahead; without an answer, all are.
  function takeSurvey(text) {
    var sums = { smooth: [], retro: [] }
    var stamps = {}
    var have = {}
    String(text).split("\n").forEach(function(line) {
      var sum = line.match(/^[0-9a-f]{32}  (.+)$/)
      var own = sum ? sum[1].match(/^sounds\/(smooth|retro)\//) : null
      var word = line.split(" ")
      if (own) sums[own[1]].push(line)
      else if (sum) ["smooth", "retro"].forEach(function(look) { sums[look].push(line) })
      else if (word[0] === "stamp" && word.length === 3) stamps[word[1]] = word[2]
      else if (word[0] === "have" && word.length === 2) have[word[1]] = true
    })
    ;["smooth", "retro"].forEach(function(look) {
      // ChartSound.js, this file, and every bundled sound.
      if (sums[look].length !== 2 + root.fixedSounds.length) return
      root.sources[look] = Qt.md5(sums[look].join("\n"))
      if (stamps[look] !== root.sources[look]) return
      root.aheadOf(look).forEach(function(f) {
        var file = root.fileOf(look, f[0], f[1])
        if (have[file]) root.madeThisRun[file] = true
      })
    })
    root.surveyed = true
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
  // PipeWire that stalls can't hold one. Every stream Stonks starts asks
  // for 30 ms, which PipeWire rounds down to the default quantum, 1024
  // frames at 48 and 44.1 kHz, so none moves it: each move back up puts a
  // Bluetooth output about 11 ms further behind, and AirPods go silent once
  // a few seconds of chimes add up to a couple of hundred.
  function start(file) {
    player.exec(["timeout", "-k", "1", "4", "pw-play", "--media-role", "Notification", "--latency", "30ms", file])
  }

  Process { id: player }

  // The output kept awake (`keepingAwake`): a stream of silence, PipeWire's
  // pw-cat reading zeros, which holds the speakers or headphones open as a
  // sound playing does, and nothing while sounds are off, no scrub has
  // moved for 1 s, and no replay waits. Its start may wake the output, as a
  // sound's does; it says, verbosely, when its stream reaches the output
  // ("-> streaming"), which ends the waking (`awakeAt`). The output counts
  // as awake only while it runs: stopped, for 4 s more; ended on its own
  // while it's wanted, as when PipeWire restarts, not at all, since the
  // output may have gone with it. Then it starts again 2 s later. Each
  // stream ends at `streamSeconds` under `timeout`, so none outlives a shell
  // that dies without stopping it; one that reaches it while it's wanted
  // starts again at once, the output still awake under it.
  property int streamSeconds: 60
  Timer { id: afterScrub; interval: 1000; onTriggered: root.scrubHeld = false }
  onKeepingAwakeChanged: silence.running = keepingAwake
  Process {
    id: silence
    command: ["timeout", "-k", "1", String(root.streamSeconds), "pw-cat", "-v", "--playback", "--raw", "--rate", "24000",
      "--channels", "1", "--format", "s16", "--media-role", "Notification", "--latency", "30ms", "/dev/zero"]
    stderr: SplitParser {
      onRead: function(line) { if (root.awakeAt < 0 && line.indexOf("-> streaming") >= 0) root.awakeAt = Date.now() }
    }
    onRunningChanged: {
      if (!running) return
      root.starting()
      root.asleepAfter = Infinity
    }
    onExited: function(exitCode) {
      var renewed = exitCode === 124 && root.keepingAwake
      root.asleepAfter = Date.now() + (root.keepingAwake && !renewed ? 0 : 4000)
      if (renewed) Qt.callLater(function() { silence.running = root.keepingAwake })
      else if (root.keepingAwake) silenceAgain.restart()
    }
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
  // the shell itself, each chime grows it by about a third of a kilobyte,
  // 10 MB over 20,000 chimes. When Stonks goes its input closes and it
  // ends; a chime ringing then rings out, half a second at most.
  Process {
    id: chimer
    running: root.turnedOn
    stdinEnabled: true
    command: ["sh", "-c", "while read -r name; do case $name in " + root.chimeNames + ") "
      + "( timeout -k 1 2 pw-play --media-role Notification --latency 30ms \"$1/$name\" & ) ;; esac; done", "sh", root.folder]
  }
}
