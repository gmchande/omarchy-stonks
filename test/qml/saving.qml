import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as Stonks
import "plugin/Settings.js" as Settings

// A save and the next read, through the real service and the real window.
// Each step is judged by what the lists file holds, what a fresh start
// reads from it, and what the footer says. HOME and curl are scratch
// fixtures; the file is broken and mended by hand, as a person would.
Harness {
  id: harness
  marker: "SAVING DONE"

  readonly property string folder: Quickshell.env("HOME") + "/.config/omarchy"
  readonly property string file: folder + "/grvc.stonks.json"

  Stonks.Service { id: service; pluginId: "grvc.stonks" }
  Stonks.Updates { id: updates; pluginId: "grvc.stonks" }
  Stonks.Camera { id: camera }
  Stonks.App { id: app; service: service; updates: updates; camera: camera }
  // A fresh start on the same file.
  Component { id: restart; Stonks.Service { pluginId: "grvc.stonks" } }
  Item { id: started }
  // Each read-back of a save, as the service says it: landed or lost.
  property var checks: []
  Connections {
    target: service
    function onSaveChecked(saved) { harness.checks = harness.checks.concat([saved]) }
  }

  // One command, run to its end.
  Process {
    id: command
    property bool done: false
    stdout: StdioCollector { id: said; waitForEnd: true }
    onExited: done = true
  }

  Steps {
    name: "Saving"
    when: service.ready

    readonly property var body: app.body

    // $1 is the lists file, $2 its folder, $3 what the step hands in.
    function sh(script, text) {
      command.done = false
      command.command = ["bash", "-c", script, "bash", harness.file, harness.folder, text || ""]
      command.running = true
      tryVerify(function() { return command.done }, 5000)
      return String(said.text).trim()
    }
    // The file holds what the service holds.
    function landed() {
      return within(5000, function() {
        try { return Settings.settingsEqual(JSON.parse(harness.readFile(harness.file)), service.fileSettings) } catch (e) { return false }
      })
    }
    // The words the footer shows.
    // The footer's words, clicked as a person clicks them.
    function clickFooter() {
      var words = harness.find(body, "footerText")
      mouseClick(words, words.width / 2, words.height / 2)
    }
    function footer() {
      var out = []
      var walk = function(node) {
        if (!node || node.visible === false) return
        if (node.text !== undefined && String(node.text) !== "") out.push(String(node.text))
        for (var i = 0; i < node.children.length; i++) walk(node.children[i])
      }
      walk(harness.find(body, "footer"))
      return out.join(" | ")
    }

    function test_saving() {
      app.open("{}")
      tryVerify(function() { return !!body && body.surfaceOpen }, 3000)

      service.createList("Tech")
      service.setMembership("MSFT", "Tech", true)
      service.setMembership("NVDA", "Tech", true)
      service.switchList("Tech")
      service.setOrder("symbol")
      service.feature("NVDA")
      service.setRange("1Y")
      var wrote = landed()
      // The file is made its owner's a moment after each write.
      var mode = ""
      within(3000, function() { mode = sh('stat -c %a "$1"'); return mode === "600" })
      // The prices are saved once the first answers are in.
      var cached = within(5000, function() { return harness.readFile(service.quotesPath) !== "" })
      var priced = Object.keys(service.quotes)
      var next = restart.createObject(started)
      var began = within(5000, function() { return next.ready })
      var read = [next.listName, next.symbols.join(","), next.order, next.featuredSymbol, next.range].join(" ")
      var unpriced = priced.filter(function(s) { return !next.quotes[s] })
      next.destroy()
      harness.check("a change is in the file, the file is its owner's alone, and a fresh start reads what was saved, the prices too",
        wrote && mode === "600" && began && read === "Tech MSFT,NVDA symbol NVDA 1Y" && cached && priced.length > 0 && unpriced.length === 0,
        [wrote, mode, began, read, cached, priced.length + " priced, a fresh start without " + unpriced.join(",")].join(" | "))

      // Half a JSON object, as a hand edit leaves one.
      var good = harness.readFile(harness.file)
      var broken = "{\n  \"symbols\": [\"AAPL\",\n"
      sh('printf %s "$3" > "$1"', broken)
      var noticed = within(3000, function() { return service.listsUnreadable })
      service.setRange("1W")
      // Time for a write that must not come to land.
      wait(700)
      var kept = harness.readFile(harness.file) === broken
      var told = footer()
      // Its words don't act: nothing can be added to lists that can't be read.
      clickFooter()
      var still = !body.adding
      // Mended as an editor saves: a new file moved over the old.
      sh('printf %s "$3" > "$1.new" && mv "$1.new" "$1"', good)
      var readAgain = within(3000, function() { return !service.listsUnreadable && service.range === "1Y" })
      service.setRange("3M")
      harness.check("a file that can't be read is never written over, the footer says so, names the file and doesn't act, and once mended it is read and saved to again",
        noticed && kept && told.indexOf("aren't saved") >= 0 && told.indexOf("grvc.stonks.json") >= 0 && still && readAgain && landed(),
        [noticed, kept, told, still, readAgain, service.range].join(" | "))

      // A folder nothing can be written into.
      sh('chmod 500 "$2"')
      service.setRange("6M")
      var failed = within(4000, function() { return service.saveFailed })
      var asked = footer()
      var unsaved = JSON.parse(harness.readFile(harness.file)).range === "3M"
      sh('chmod 700 "$2"')
      // The footer's words are the way to try again.
      clickFooter()
      harness.check("a save that can't land is said in the footer with a way to try again, and trying again once it can saves it",
        failed && unsaved && asked.indexOf("aren't saved") >= 0 && asked.indexOf("try again") >= 0 && landed()
          && within(3000, function() { return footer().indexOf("aren't saved") < 0 }),
        [failed, unsaved, asked, footer()].join(" | "))

      // Lists a hand edit named oddly: a case twin, All, and none, the last
      // holding a symbol no other list or All holds, beside a key Stonks
      // doesn't know.
      var odd = JSON.stringify({ version: 1, symbols: ["AAPL", "MSFT", "NVDA"], range: "3M", lists: [
        { name: "Tech", symbols: ["MSFT", "NVDA"], order: "manual", reversed: false },
        { name: "tech", symbols: ["AAPL"], order: "manual", reversed: false, note: "mine" },
        { name: "All", symbols: ["NVDA"], order: "manual", reversed: false },
        { name: " ", symbols: ["JNJ"], order: "manual", reversed: false }
      ] }, null, 2)
      sh('printf %s "$3" > "$1.new" && mv "$1.new" "$1"', odd)
      var readOdd = within(3000, function() { return service.lists.length === 5 })
      service.setRange("1Y")
      var savedOdd = landed()
      var file = JSON.parse(harness.readFile(harness.file))
      var held = file.lists.map(function(list) { return list.name + ":" + list.symbols.join(",") }).join(" ")
      harness.check("a list a hand edit named oddly keeps what it holds and its keys under a free name, through a read and the next save",
        readOdd && savedOdd && held === "Tech:MSFT,NVDA tech 2:AAPL All 2:NVDA List:JNJ" && file.lists[1].note === "mine"
          && file.symbols.indexOf("JNJ") >= 0,
        [readOdd, savedOdd, held, JSON.stringify(file.lists[1]), file.symbols.join(",")].join(" | "))

      // A save is read back, and found as it was written.
      good = harness.readFile(harness.file)
      harness.checks = []
      service.setRange("6M")
      var backed = landed() && within(3000, function() { return harness.checks.indexOf(true) >= 0 })
      harness.check("a save is read back and found as it was written",
        backed && harness.checks.indexOf(false) < 0 && !service.saveFailed, [backed, JSON.stringify(harness.checks), service.saveFailed].join(" | "))

      // A read still out as a save lands holds the text from before the
      // save; it goes unheard, and the save is read back as it landed.
      good = harness.readFile(harness.file)
      // The stand-in dd says when it has read the file (bin/dd).
      sh('rm -f "$STONKS_FAKE_STATE/dd.read" && touch "$STONKS_FAKE_STATE/dd.hold" && cp "$1" "$1.new" && mv "$1.new" "$1"')
      var held = within(3000, function() { return sh('[ -e "$STONKS_FAKE_STATE/dd.read" ] && echo read') === "read" })
      harness.checks = []
      service.setRange("1M")
      sh('rm -f "$STONKS_FAKE_STATE/dd.hold"')
      var through = held && landed() && within(3000, function() { return harness.checks.indexOf(true) >= 0 })
      // The held read comes in after the save's own: it must say nothing.
      through = through && !within(500, function() { return harness.checks.indexOf(false) >= 0 })
      harness.check("a read still out as a save lands goes unheard, and the save is read back as it landed",
        through && harness.checks.indexOf(false) < 0 && !service.saveFailed && footer().indexOf("aren't saved") < 0 && service.range === "1M"
          && JSON.parse(harness.readFile(harness.file)).range === "1M",
        [through, service.saveFailed, footer(), service.range, JSON.stringify(harness.checks)].join(" | "))

      // A file larger than 128 KiB, and where the file was a folder, a FIFO
      // or a link to a device: each can't be read, the footer says so, and
      // none is written over. The FIFO holds nothing up.
      good = harness.readFile(harness.file)
      // Each kind: how it's made, and how it's seen, the same after a save
      // asked of it. The large one is the file with a 128 KiB note added,
      // made in the shell: a command takes no argument that long.
      var refused = function(kind) {
        sh(kind[1])
        var made = sh(kind[2])
        var noticed = within(3000, function() { return service.listsUnreadable && footer().indexOf("Couldn't load your lists") >= 0 })
        var was = service.range
        service.setRange(was === "1Y" ? "3M" : "1Y")
        var kept = !within(700, function() { return sh(kind[2]) !== made })
        sh('rm -rf "$1" && printf %s "$3" > "$1.new" && mv "$1.new" "$1"', good)
        var back = kind[3] || within(3000, function() { return !service.listsUnreadable })
        return noticed && kept && back ? "" : kind[0] + ": " + [noticed, kept, back, made].join(" ")
      }
      var refusals = [
        ["over 128 KiB", 'sed "\\$d" "$1" > "$1.new" && { printf \',"note": "\'; head -c 131072 /dev/zero | tr "\\0" x; printf \'"\\n}\\n\'; } >> "$1.new" && mv "$1.new" "$1"', 'md5sum < "$1"'],
        ["a folder", 'rm -f "$1" && mkdir "$1"', 'stat -c %F "$1" && ls -A "$1" | wc -l'],
        ["a FIFO", 'rm -f "$1" && mkfifo "$1"', 'stat -c %F "$1"']
      ].map(refused).filter(function(s) { return s !== "" })

      // A save that didn't land still awaits its read-back when a file
      // Stonks can't read takes the file's place: the footer says it can't
      // load the lists, and neither its words nor the next change write
      // over the file.
      var big = 'sed "\\$d" "$1" > "$1.new" && { printf \',"note": "\'; head -c 131072 /dev/zero | tr "\\0" x; printf \'"\\n}\\n\'; } >> "$1.new" && mv "$1.new" "$1"'
      sh('chmod 500 "$2"')
      service.setRange(service.range === "6M" ? "3M" : "6M")
      var pending = within(4000, function() { return service.saveFailed })
      sh('chmod 700 "$2" && ' + big)
      var made = sh('md5sum < "$1"')
      var noticed = within(3000, function() { return service.listsUnreadable && footer().indexOf("Couldn't load your lists") >= 0 })
      clickFooter()
      service.setRange(service.range === "1Y" ? "3M" : "1Y")
      var kept = !within(700, function() { return sh('md5sum < "$1"') !== made })
      sh('printf %s "$3" > "$1.new" && mv "$1.new" "$1"', good)
      var back = within(3000, function() { return !service.listsUnreadable && !service.saveFailed })
      harness.check("a file Stonks can't read, put in the file's place while a lost save awaits its read-back, is never written over",
        pending && noticed && kept && back, [pending, noticed, kept, back, footer()].join(" | "))

      // A change that would make the file larger than Stonks reads is never
      // written: the file keeps what it held, the footer says the changes
      // aren't saved, and once they fit again that goes.
      good = harness.readFile(harness.file)
      var huge = new Array(131073).join("x")
      var made = service.createList(huge) === ""
      var unsaved = within(2000, function() { return footer().indexOf("aren't saved") >= 0 })
      var untouched = !within(700, function() { return harness.readFile(harness.file) !== good })
      service.deleteList(huge)
      var fits = within(3000, function() { return footer().indexOf("aren't saved") < 0 }) && harness.readFile(harness.file) === good
      harness.check("a change that would make the lists file larger than Stonks reads leaves the file as it was, and the footer says the changes aren't saved until they fit",
        made && unsaved && untouched && fits, [made, unsaved, untouched, fits, footer()].join(" | "))

      // The file gone, then back: what comes back is read.
      sh('rm -f "$1"')
      var gone = within(3000, function() { return !service.listsUnreadable && service.lists.length === 1 })
      var back = JSON.parse(good)
      back.range = "5Y"
      sh('printf %s "$3" > "$1.new" && mv "$1.new" "$1"', JSON.stringify(back, null, 2) + "\n")
      var appeared = within(3000, function() { return service.range === "5Y" && service.lists.length > 1 })
      // A hand edit in place.
      back.range = "1W"
      sh('printf %s "$3" > "$1"', JSON.stringify(back, null, 2) + "\n")
      var edited = within(3000, function() { return service.range === "1W" })
      harness.check("a file that appears where none was is read, and so is an edit made in place by hand",
        gone && appeared && edited, [gone, appeared, edited, service.range].join(" | "))

      // Every older release's file reads to the lists and settings it holds.
      var wrong = Quickshell.env("STONKS_DATA_FILES").split(" ").filter(function(path) { return path !== "" }).filter(function(path) {
        var text = harness.readFile(path)
        sh('printf %s "$3" > "$1.new" && mv "$1.new" "$1"', text)
        return !within(3000, function() { return Settings.settingsEqual(service.fileSettings, Settings.readListsFile(text)) })
      })
      harness.check("every older release's lists file reads to the lists and settings it holds",
        Quickshell.env("STONKS_DATA_FILES") !== "" && wrong.length === 0, wrong.join(" "))

      // A first start with no lists file takes the symbols an older Stonks
      // kept in its bar entry in shell.json, and writes them to a new file.
      sh('rm -f "$1" && printf %s "$3" > "$2/shell.json"',
        JSON.stringify({ bar: { layout: { right: [{ id: "grvc.stonks", symbols: ["NVDA", "SPY"], order: "name" }] } } }))
      var first = restart.createObject(started)
      var fromBar = within(5000, function() { return first.ready && first.allSymbols.join(",") === "NVDA,SPY" })
      var written = within(5000, function() {
        try { return JSON.parse(harness.readFile(harness.file)).symbols.join(",") === "NVDA,SPY" } catch (e) { return false }
      })
      first.destroy()
      sh('rm -f "$2/shell.json" && printf %s "$3" > "$1.new" && mv "$1.new" "$1"', good)
      harness.check("a first start with no lists file takes the bar's symbols an older Stonks kept in shell.json, and writes them to a new file",
        fromBar && written, [fromBar, written].join(" | "))

      // Last, a link to a device: Quickshell's watch follows a link to what
      // it names, so it says no more of the file's place, mended or not.
      var link = refused(["a link to a device", 'rm -f "$1" && ln -s /dev/zero "$1"', 'readlink "$1"', true])
      if (link !== "") refusals.push(link)
      harness.check("a file over 128 KiB, a folder, a FIFO or a link to a device in the file's place can't be read, the footer says so, and none is written over",
        refusals.length === 0, refusals.join(" | "))

      app.close()
      harness.finish()
    }
  }
}
