import QtQuick
import Quickshell
import Quickshell.Io

// Grabs `source`'s rendered frames into $STONKS_FRAMES as PPM, and has
// frames.js judge them. A grab alone keeps the source's transparency, and
// not always in the same format, so while grabbing the source has its
// window's colour laid under it: what is on screen stays the same, and
// every frame is the picture as it shows. Offscreen, Qt draws with its
// software render loop, which renders on its own cadence (each grab asks
// for the next render) while animations advance on QtCore's 16 ms timer,
// and `afterAnimating` fires on every render, whether the clock ticked or
// not. So a render with no tick since the last frame repeats that frame's
// moment and is not kept, and a frame is timed by the latest moment its
// picture can show: the clock's last tick, or the mark when it came after
// that tick (a change made at the mark shows at once). Timed by the render
// instead, a late clock shows each moment later than it was, and a
// 160 ms ease on a busy machine read as 240. Times are ms since `start`,
// which a harness sets as its motion starts (`markStart`). A harness copies
// this beside its shell.qml (`frame_tools`, lib.sh).
Item {
  id: grabber

  property Item source: null
  property string name: ""
  property real start: 0
  property var frames: []
  property int waiting: 0
  property var verdict: null
  // When the animation clock last ticked, and the moment of the last frame.
  property real tick: 0
  property real shown: 0
  property Item ground: null

  // Starts a run of frames named `runName`, timed from now until marked.
  function begin(runName) {
    if (ground) ground.destroy()
    ground = Qt.createQmlObject('import QtQuick; Rectangle { anchors.fill: parent; z: -1000 }', source)
    ground.color = source.Window.window.color
    name = runName
    frames = []
    tick = 0
    shown = 0
    verdict = null
    start = Date.now()
    ticker.running = true
  }

  function markStart() { start = Date.now() }

  function end() { ticker.running = false }
  function resume() { ticker.running = true }

  // One frame: this render's picture, timed by its moment.
  function shot(at) {
    var path = Quickshell.env("STONKS_FRAMES") + "/" + name + "-" + String(frames.length).padStart(3, "0") + ".ppm"
    frames.push({ path: path, at: at })
    shown = at
    waiting++
    source.grabToImage(function(result) {
      result.saveToFile(path)
      grabber.waiting--
    })
  }

  // The frames rendered before the start was marked.
  function framesBefore() {
    return frames.filter(function(frame) { return frame.at < grabber.start })
  }

  // Asks frames.js for its verdict on `judged` (every frame by default), in
  // `mode` (drawin, same, edge, edgeheld, turn, or press) with the mode's
  // own `args` (edge's band, press's fill and box, a draw-in's `plot=`).
  // The run is over: the ground goes. A verdict always comes within 9 s, a
  // failing one if frames.js gave none, so a harness waiting 10 s for it
  // never reads null.
  function judge(mode, judged, args) {
    verdict = null
    if (ground) ground.destroy()
    ground = null
    judgeProc.command = ["bun", Quickshell.env("STONKS_FRAME_CHECK"), mode].concat(args || []).concat((judged || frames).map(function(frame) {
      return frame.path + "@" + Math.round(frame.at - grabber.start)
    }))
    judgeProc.running = true
    noVerdict.restart()
  }

  Timer {
    id: noVerdict
    interval: 9000
    onTriggered: if (grabber.verdict === null) grabber.verdict = { ok: false, detail: "no verdict from frames.js in 9 s" }
  }

  // Keeps the window rendering on every tick while grabbing, still pictures
  // too, and notes when the clock ticked.
  FrameAnimation {
    id: ticker
    running: false
    onTriggered: {
      grabber.tick = Date.now()
      grabber.source.Window.window.update()
    }
  }

  Connections {
    target: ticker.running ? grabber.source.Window.window : null
    function onAfterAnimating() {
      var at = grabber.start > grabber.tick && Date.now() >= grabber.start ? grabber.start : grabber.tick
      if (at > grabber.shown) grabber.shot(at)
    }
  }

  Process {
    id: judgeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { grabber.verdict = JSON.parse(String(text || "").trim()) }
        catch (e) { grabber.verdict = { ok: false, detail: "no verdict: " + text } }
      }
    }
  }
}
