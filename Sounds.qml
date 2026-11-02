import QtQuick
import Quickshell.Io
import "ChartSound.js" as ChartSound
// The sounds, each in the look's voice: what you just did, a replay, the
// chimes as a scrub crosses the chart's bars (`ChartSound`), and the market's
// bell (`Bell`). One sound plays at a time, a new one stopping the last; the
// chimes overlap. `pw-play` plays them at the system's volume. The surfaces
// and the bell say when; this knows only how.
Item {
  id: root

  property bool turnedOn: false
  property bool retro: false
  // An output asleep wakes as a sound starts, and cuts or delays it, so it is
  // kept awake while a scrub moves, for 1 s after, and while a replay waits
  // for it. Never longer: headphones go to whichever computer plays.
  readonly property bool keepingAwake: turnedOn && (scrubHeld || replaysWaiting.length > 0)
  // Its own flag, since the timer's restart turns `running` off and on.
  property bool scrubHeld: false
  // So a replay's end stops only its own sound.
  property var replayOwner: null
  // `OwnerOnly`, which writes the replay's and the chimes' files.
  property var files: null
  readonly property string folder: files ? files.folder : ""
  readonly property string replayPath: folder + "/replay.wav"
  readonly property string voice: retro ? "retro" : "smooth"
  // The cache's files that hold the current sound: written this run, or left
  // current by an earlier one (`takeSurvey`).
  property var madeThisRun: ({})
  // Each look's md5 of what its files are made from (`takeSurvey`), which its
  // `stamp-<look>` holds once all its files do; and whether this run's writes
  // all "landed" or one "failed". A stamp over a failed write would keep the
  // old sound for good.
  property var sources: ({})
  property var rewrote: ({})
  property bool surveyed: false
  readonly property var fixedSounds: ["add", "remove", "undo", "shutter", "bell"]
  // In ms (`leadAt`).
  readonly property var leadSteps: [30, 60, 90, 120, 150]
  // The chimes' player's `case` patterns.
  readonly property string chimeNames: {
    var names = []
    ;["smooth", "retro"].forEach(function(look) {
      [""].concat(leadSteps.map(function(ms) { return "lead" + ms + "-" })).forEach(function(lead) {
        names.push("chime-" + lead + look + "-[0-9].wav", "chime-" + lead + look + "-10.wav")
      })
    })
    return names.join("|")
  }
  // A bar struck sooner waits, and the latest waiting wins.
  readonly property int chimeGap: 45
  property real lastChime: 0
  property int waiting: -1

  // A sound that may wake an output asleep opens with up to 150 ms of silence,
  // which the waking eats instead of the sound. PipeWire puts an output to
  // sleep after 5 s with nothing playing; Stonks hears only its own sounds, so
  // it counts the output asleep 4 s after its last. The whole lead-in holds
  // until the silence's stream reaches the output, or for 550 ms without one:
  // laptop speakers wake in 135 to 182 ms, Bluetooth slower. Then it shrinks a
  // third as fast as time passes, in 30 ms steps, so with chimes 45 ms apart
  // none sounds before the one struck ahead of it.
  readonly property int leadIn: 150
  property real asleepAfter: 0
  property real wokeAt: 0
  // 0 before the output first woke, -1 while it wakes and nothing has said so.
  property real awakeAt: 0

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

  // Reached 150 ms ago, so the silence playing since has covered its waking.
  function awake(now) {
    if (now >= asleepAfter) return false
    return awakeAt >= 0 ? now >= awakeAt + leadIn : !silence.running && now - wokeAt >= 1000
  }

  // A WAV with the plain 44-byte header the chimes and the bundled sounds have.
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

  function scrubMoved() {
    scrubHeld = true
    afterScrub.restart()
  }

  function bundled(look, name) {
    return String(Qt.resolvedUrl("sounds/" + look + "/" + name + ".wav")).replace(/^file:\/\//, "")
  }

  // With the whole lead-in when it needs one, from the cache's folder once
  // that is private (`OwnerOnly.made`).
  function play(name) {
    if (!turnedOn) return
    replayOwner = null
    var lead = starting() > 0
    start(lead && files.made ? written(voice, name, leadIn) : bundled(voice, name))
  }

  // A replay's sound keeps step with its sweep, so instead of a lead-in it
  // waits for the output to be awake, 1.5 s at most. `go` starts it.
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

  // The file is written whole before `pw-play` starts, and lands by a rename,
  // so a player still reading the last one keeps it. The same replay again
  // plays its file again: making it holds a retro start about 10 ms longer.
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

  // One still waiting for the output never starts.
  function stopReplay(owner) {
    if (!owner) return
    replaysWaiting = replaysWaiting.filter(function(w) { return w.owner !== owner })
    if (owner !== replayOwner) return
    replayOwner = null
    player.running = false
  }

  // `bar` is 0 to 10 (`ChartSound.barAt`), or -1 where the line lifts.
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

  function strike(bar) {
    chimeWait.stop()
    waiting = -1
    lastChime = Date.now()
    var path = written(voice, bar, starting())
    chimer.write(path.slice(folder.length + 1) + "\n")
  }

  function fileOf(look, what, lead) {
    if (typeof what !== "number") return "lead-" + look + "-" + what + ".wav"
    return "chime-" + (lead ? "lead" + lead + "-" : "") + look + "-" + what + ".wav"
  }

  // Until the folder is private (`OwnerOnly.write`), the file an earlier run
  // left plays, if any.
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

  // A new path loads in the background even with blockLoading, so the read
  // waits for it, or it would hand back the last file's.
  function bundledBytes(look, name) {
    bundledFile.path = bundled(look, name)
    bundledFile.waitForJob()
    return bundledFile.data()
  }
  FileView { id: bundledFile; blockLoading: true }

  function aheadOf(look) {
    var list = []
    for (var bar = 0; bar < 11; bar++) {
      list.push([bar, 0])
      leadSteps.forEach(function(ms) { list.push([bar, ms]) })
    }
    fixedSounds.forEach(function(name) { list.push([name, leadIn]) })
    return list
  }

  // A look's files are written ahead one every 100 ms, so a first scrub writes
  // none: back to back, smooth's eleven chimes hold the shell's thread 80 ms.
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
      // Last, so no file is newer than the stamp that vouches for it.
      if (root.rewrote[look] === "landed" && root.sources[look]) root.files.write(root.folder + "/stamp-" + look, root.sources[look] + "\n")
      delete root.rewrote[look]
    }
  }

  // Once a run: the md5s of what the sounds are made from, each look's stamp,
  // and the files no newer than it. A newer one was written by an older Stonks,
  // which kept no stamp. The answer runs under 8 KB and is read up to 64. Read
  // as `running` falls, since a command that fails to start never exits.
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

  // Without an answer, every file is written ahead.
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

  // exec stops a sound still playing. 4 s is twice the longest, a replay's, so
  // a stalled PipeWire can't hold one. Every stream asks for 30 ms, which
  // PipeWire rounds down to its quantum, 1024 frames, so none moves it: each
  // move puts a Bluetooth output about 11 ms further behind, and AirPods go
  // silent once a few seconds of chimes add up.
  function start(file) {
    player.exec(["timeout", "-k", "1", "4", "pw-play", "--media-role", "Notification", "--latency", "30ms", file])
  }

  Process { id: player }

  // The silence that keeps the output awake: pw-cat reading zeros holds it
  // open as a sound does, and says "-> streaming" once it reaches it. The
  // output counts as awake only while it runs and 4 s after it stops. One that
  // ends on its own while wanted, as when PipeWire restarts, may have taken the
  // output with it, so it counts as asleep and starts again 2 s later. Each
  // stream ends after `streamSeconds`, so none outlives a shell that dies, and
  // starts again at once if still wanted.
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

  // Quiet while Omarchy's Do Not Disturb is on, as Omarchy's own toggle asks
  // it, or an app records from a microphone, as a call does. A shell that
  // doesn't answer, as with another app showing notifications, leaves the bell
  // to ring. `pw-dump` runs to about half a megabyte; an answer that times out,
  // fails or passes 4 MB counts as recording. Both are stopped within 7 s,
  // before the next bell.
  function ring() {
    if (turnedOn && !listening.running) listening.running = true
  }

  // An app's capture stream running, not one reading a speaker's monitor, as a
  // level meter does.
  function recording(dump) {
    var nodes
    try { nodes = JSON.parse(dump) } catch (e) { return true }
    return !Array.isArray(nodes) || nodes.some(function(node) {
      var props = node.info && node.info.props || {}
      return node.type === "PipeWire:Interface:Node" && props["media.class"] === "Stream/Input/Audio"
        && node.info.state === "running" && String(props["stream.capture.sink"]) !== "true"
    })
  }

  // A byte past 4 MB shows an answer over the cap. omarchy-shell's -q would
  // hide its answer too.
  Process {
    id: listening
    command: ["bash", "-c", "[ \"$(timeout -k 1 2 omarchy-shell notifications dndState 2> /dev/null)\" = on ] && exit 1\n"
      + "set -o pipefail; timeout -k 1 3 pw-dump | head -c 4000001"]
    stdout: StdioCollector { id: answer }
    onExited: function(code) {
      if (root.turnedOn && code === 0 && answer.data.byteLength <= 4000000 && !root.recording(answer.text)) root.play("bell")
    }
  }

  // One shell while sounds are on, starting a pw-play in the background for
  // each chime named on its input, so chimes overlap and the shell's thread
  // starts no process per chime. Each has 2 s, four times a chime, so a
  // stalled PipeWire can't pile them up, and starts from a subshell that ends
  // at once: started from this shell, each grew it by a third of a kilobyte,
  // 10 MB over 20,000 chimes. As Stonks goes, its input closes and it ends.
  Process {
    id: chimer
    running: root.turnedOn
    stdinEnabled: true
    command: ["sh", "-c", "while read -r name; do case $name in " + root.chimeNames + ") "
      + "( timeout -k 1 2 pw-play --media-role Notification --latency 30ms \"$1/$name\" & ) ;; esac; done", "sh", root.folder]
  }
}
