import { test, expect } from "bun:test"
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, symlinkSync, utimesSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { load } from "./load.js"

// The commands Stonks runs that carry shell code (Commands.js), run as the
// shell runs them, each in a scratch folder. A tool that would reach the
// desktop, such as pw-dump or omarchy, is a stand-in first on PATH.
const C = load("Commands.js")
const root = join(import.meta.dir, "..")

function scratch(body) {
  const dir = mkdtempSync(join(tmpdir(), "stonks-commands-"))
  try { return body(dir) } finally { rmSync(dir, { recursive: true, force: true }) }
}
function run(argv, env, input) {
  const r = Bun.spawnSync(argv, { env, stdin: input === undefined ? "ignore" : new Blob([input]), stdout: "pipe", stderr: "pipe" })
  return { code: r.exitCode, out: r.stdout.toString() }
}
// A folder of the tools named, linked from the system's, for a PATH that
// holds nothing else.
function tools(dir, names) {
  const bin = join(dir, "tools")
  mkdirSync(bin, { recursive: true })
  for (const name of names) symlinkSync(Bun.which(name), join(bin, name))
  return bin
}
function standIn(bin, name, script) {
  mkdirSync(bin, { recursive: true })
  writeFileSync(join(bin, name), "#!/bin/sh\n" + script)
  chmodSync(join(bin, name), 0o755)
}

test("a screenshot is named for its stock and the moment, in the folder and for the editor of the Omarchy installed, and never over another", () => scratch(dir => {
  const home = join(dir, "home")
  mkdirSync(join(home, ".config"), { recursive: true })
  writeFileSync(join(home, ".config/user-dirs.dirs"), 'XDG_PICTURES_DIR="$HOME/Shots"\n')
  const base = tools(dir, ["sh", "timeout", "mkdir", "sed", "tail", "head"])
  standIn(base, "date", "echo 2026-11-11_13-00-00\n")
  const named = (env, omasnapFolder = "", pictures = join(home, "Pictures")) => {
    const r = run(C.screenshotName("AAPL", omasnapFolder, pictures), { HOME: home, PATH: base, ...env })
    return C.readScreenshotName(r.out)
  }
  const name = "stonks-AAPL-2026-11-11_13-00-00.png"
  // Omarchy 4.0: Tensaku, in the pictures folder user-dirs.dirs names, or as
  // OMARCHY_SCREENSHOT_DIR and OMARCHY_SCREENSHOT_EDITOR say.
  expect(named({})).toEqual({ editor: "tensaku-edit", file: join(home, "Shots", name) })
  expect(named({ OMARCHY_SCREENSHOT_DIR: join(home, "Legacy"), OMARCHY_SCREENSHOT_EDITOR: "my-editor" }))
    .toEqual({ editor: "my-editor", file: join(home, "Legacy", name) })
  // Omarchy 4.5: Omasnap, in Screenshots in the pictures folder, or its
  // settings' folder with ~ read as home, or OMASNAP_SCREENSHOT_DIR first.
  const omasnap = join(dir, "omasnap")
  standIn(omasnap, "omasnap", "exit 1\n")
  const with45 = { PATH: omasnap + ":" + base }
  expect(named(with45)).toEqual({ editor: "omasnap", file: join(home, "Pictures/Screenshots", name) })
  expect(named(with45, "~/Captures").file).toBe(join(home, "Captures", name))
  expect(named({ ...with45, OMASNAP_SCREENSHOT_DIR: join(home, "Snaps"), OMARCHY_SCREENSHOT_DIR: join(home, "Legacy") }, "~/Captures").file)
    .toBe(join(home, "Snaps", name))
  // A name taken in the same second takes the next number.
  writeFileSync(join(home, "Shots", name), "")
  expect(named({}).file).toBe(join(home, "Shots", name.replace(/\.png$/, "-2.png")))
  // A folder it can't make names nothing.
  writeFileSync(join(dir, "blocked"), "")
  expect(named({ OMARCHY_SCREENSHOT_DIR: join(dir, "blocked/inside") })).toBeNull()
  // An answer that names no whole file names nothing.
  expect([C.readScreenshotName("tensaku-edit\nrelative.png\n"), C.readScreenshotName("/only-a-file.png\n"), C.readScreenshotName("")]).toEqual([null, null, null])
}))

test("a file made for Stonks is its owner's alone from the start, holds the text whole, and is never made over a file there", () => scratch(dir => {
  const path = join(dir, "grvc.stonks.json")
  const made = run(C.createPrivately(path), { PATH: process.env.PATH, STONKS_TEXT: '{"symbols":["AAPL"]}\n' })
  expect([made.code, readFileSync(path, "utf8"), statSync(path).mode & 0o777]).toEqual([0, '{"symbols":["AAPL"]}\n', 0o600])
  const again = run(C.createPrivately(path), { PATH: process.env.PATH, STONKS_TEXT: "{}" })
  expect([again.code !== 0, readFileSync(path, "utf8")]).toEqual([true, '{"symbols":["AAPL"]}\n'])
  // Nothing is left behind beside it.
  expect(Bun.spawnSync(["ls", "-A", dir]).stdout.toString().trim().split("\n")).toEqual(["grvc.stonks.json"])
}))

test("the sounds made in an earlier run are used again only while what they're made from is unchanged and they are no newer than its stamp", () => scratch(dir => {
  const cache = join(dir, "cache")
  mkdirSync(cache)
  const survey = () => C.readSoundSurvey(run(C.soundSurvey(root, cache), { PATH: process.env.PATH }).out, 5)
  // Nothing made yet: each look's sources come whole, with no stamp. They
  // name every file the sounds are made from, so a change to any of them
  // makes the sounds again.
  const first = survey()
  expect([first.sums.smooth.length, first.sums.retro.length, first.stamps, first.have]).toEqual([8, 8, {}, {}])
  expect(first.sums.smooth.map(line => line.slice(34)).filter(name => !name.startsWith("sounds/"))).toEqual(["ChartSound.js", "Sounds.qml", "Waking.js"])
  // A stamp, a file made before it, and one written after it by an older Stonks.
  writeFileSync(join(cache, "stamp-smooth"), "abc123\n")
  writeFileSync(join(cache, "chime-smooth-1.wav"), "")
  writeFileSync(join(cache, "chime-smooth-2.wav"), "")
  utimesSync(join(cache, "chime-smooth-1.wav"), 1000, 1000)
  utimesSync(join(cache, "stamp-smooth"), 2000, 2000)
  utimesSync(join(cache, "chime-smooth-2.wav"), 3000, 3000)
  const later = survey()
  expect([later.stamps, later.have]).toEqual([{ smooth: "abc123" }, { "chime-smooth-1.wav": true }])
  // A source missing from the answer leaves that look to be made again.
  expect(C.readSoundSurvey(first.sums.retro.slice(1).join("\n"), 5).sums.retro).toBeNull()
}))

test("the bell keeps quiet under Do Not Disturb and while an app records, and rings when nothing says otherwise", () => scratch(dir => {
  const bin = join(dir, "bin")
  const ask = (dnd, dump) => {
    standIn(bin, "omarchy-shell", `echo ${dnd}\n`)
    standIn(bin, "pw-dump", `cat <<'EOF'\n${dump}\nEOF\n`)
    const r = run(C.bellCheck(), { PATH: bin + ":" + process.env.PATH })
    return r.code === 0 && !C.recording(r.out)
  }
  const stream = (mediaClass, state, monitor) => ({ type: "PipeWire:Interface:Node", info: { state, props: { "media.class": mediaClass, ...(monitor ? { "stream.capture.sink": true } : {}) } } })
  const quiet = JSON.stringify([stream("Stream/Output/Audio", "running")])
  expect(ask("off", quiet)).toBe(true)
  expect(ask("on", quiet)).toBe(false)
  // A call's microphone running stops it; a paused one, or a level meter
  // reading a speaker, doesn't.
  expect(ask("off", JSON.stringify([stream("Stream/Input/Audio", "running")]))).toBe(false)
  expect(ask("off", JSON.stringify([stream("Stream/Input/Audio", "suspended"), stream("Stream/Input/Audio", "running", true)]))).toBe(true)
  // An answer that doesn't read counts as recording.
  expect(ask("off", "not json")).toBe(false)
}))

test("the chimes' player plays each chime it's sent that its names allow, and nothing else", () => scratch(dir => {
  const bin = join(dir, "bin")
  const log = join(dir, "played")
  standIn(bin, "pw-play", `for last; do :; done; echo "$last" >> "${log}"\n`)
  run(C.chimePlayer("chime-smooth-[0-9].wav|chime-smooth-10.wav", "/sounds"), { PATH: bin + ":" + process.env.PATH },
    "chime-smooth-3.wav\nchime-smooth-10.wav\n../../etc/passwd\nchime-retro-3.wav\n")
  Bun.sleepSync(300)
  expect(readFileSync(log, "utf8").trim().split("\n").sort()).toEqual(["/sounds/chime-smooth-10.wav", "/sounds/chime-smooth-3.wav"])
}))

test("an update that restarts the shell restarts it only when the plugin's folder moved", () => scratch(dir => {
  const home = join(dir, "home")
  const plugin = join(home, ".config/omarchy/plugins/grvc.stonks")
  mkdirSync(plugin, { recursive: true })
  const git = (...args) => Bun.spawnSync(["git", "-C", plugin, "-c", "user.name=t", "-c", "user.email=t@t", ...args])
  git("init", "-q")
  git("commit", "-q", "--allow-empty", "-m", "one")
  const bin = join(dir, "bin")
  const log = join(dir, "omarchy.log")
  const update = moves => {
    standIn(bin, "omarchy", `echo "$*" >> "${log}"
case "$1 $2" in
  "launch floating") shift 5; exec bash -c "$1" ;;
  "plugin update") ${moves ? `git -C "${plugin}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m next` : ":"} ;;
esac
`)
    writeFileSync(log, "")
    run(C.updateAndRestart("grvc.stonks"), { HOME: home, PATH: bin + ":" + process.env.PATH })
    return readFileSync(log, "utf8").trim().split("\n").slice(1)
  }
  expect(update(false)).toEqual(["plugin update grvc.stonks"])
  expect(update(true)).toEqual(["plugin update grvc.stonks", "restart shell"])
}))

// ---------------------------------------------------------------- waking the sound output

const W = load("Waking.js")

test("a chime as the output wakes keeps its whole lead-in, and as the lead-in shrinks no chime sent 45 ms after another starts before it", () => {
  const woke = { wokeAt: 0, awakeAt: -1, asleepAfter: 4000, silenceRunning: false }
  // Woken, with nothing heard yet: the whole 150 ms, with or without the
  // silence playing.
  expect([W.leadInAt(0, woke), W.leadInAt(500, woke), W.leadInAt(0, { ...woke, silenceRunning: true })]).toEqual([150, 150, 150])
  // The silence heard reaching it at 200: each chime's sound starts after
  // the last one's, in a run of chimes 45 ms apart.
  const heard = { ...woke, awakeAt: 200, silenceRunning: true }
  const starts = Array.from({ length: 20 }, (_, i) => 200 + 45 * i).map(t => t + W.leadInAt(t, heard))
  expect(starts.every((start, i) => i === 0 || start > starts[i - 1])).toBe(true)
  expect([W.leadInAt(200, heard), W.leadInAt(650, heard)]).toEqual([150, 0])
  // In 30 ms steps, each a sound made ahead (`Sounds.leadSteps`).
  const leads = new Set(Array.from({ length: 700 }, (_, t) => W.leadInAt(t, heard)))
  expect([...leads].sort((a, b) => a - b)).toEqual([0, 30, 60, 90, 120, 150])
})

test("the output counts as awake once the silence has played the lead-in to it, or a second after it woke without one, and asleep 4 s after the last sound", () => {
  const output = { wokeAt: 0, awakeAt: 200, asleepAfter: 4000, silenceRunning: true }
  expect([W.outputAwake(349, output), W.outputAwake(350, output), W.outputAwake(4000, output)]).toEqual([false, true, false])
  const quiet = { wokeAt: 0, awakeAt: -1, asleepAfter: 4000, silenceRunning: false }
  expect([W.outputAwake(999, quiet), W.outputAwake(1000, quiet), W.outputAwake(1000, { ...quiet, silenceRunning: true })]).toEqual([false, true, false])
})

test("a sound with a lead-in opens with that much silence at its own rate, and plays whole after it", () => {
  // A WAV header for 24 kHz mono 16-bit, and four samples.
  const wav = new ArrayBuffer(44 + 8)
  const d = new DataView(wav)
  d.setUint32(4, 36 + 8, true)
  d.setUint32(24, 24000, true)
  d.setUint32(40, 8, true)
  new Uint8Array(wav, 44).set([1, 2, 3, 4, 5, 6, 7, 8])
  const led = W.withLeadIn(wav, 150)
  const o = new DataView(led)
  // 150 ms at 24,000 samples a second, two bytes each.
  expect([led.byteLength, o.getUint32(4, true), o.getUint32(40, true), o.getUint32(24, true)]).toEqual([44 + 7200 + 8, 36 + 7208, 7208, 24000])
  expect([...new Uint8Array(led, 44, 7200)].every(b => b === 0)).toBe(true)
  expect([...new Uint8Array(led, 44 + 7200)]).toEqual([1, 2, 3, 4, 5, 6, 7, 8])
})
