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
      var next = restart.createObject(started)
      var began = within(5000, function() { return next.ready })
      var read = [next.listName, next.symbols.join(","), next.order, next.featuredSymbol, next.range].join(" ")
      next.destroy()
      harness.check("a change is in the file, the file is its owner's alone, and a fresh start reads what was saved",
        wrote && mode === "600" && began && read === "Tech MSFT,NVDA symbol NVDA 1Y", [wrote, mode, began, read].join(" | "))

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
      // Mended as an editor saves: a new file moved over the old.
      sh('printf %s "$3" > "$1.new" && mv "$1.new" "$1"', good)
      var readAgain = within(3000, function() { return !service.listsUnreadable && service.range === "1Y" })
      service.setRange("3M")
      harness.check("a file that can't be read is never written over, the footer says so and names the file, and once mended it is read and saved to again",
        noticed && kept && told.indexOf("aren't saved") >= 0 && told.indexOf("grvc.stonks.json") >= 0 && readAgain && landed(),
        [noticed, kept, told, readAgain, service.range].join(" | "))

      // A folder nothing can be written into.
      sh('chmod 500 "$2"')
      service.setRange("6M")
      var failed = within(4000, function() { return service.saveFailed })
      var asked = footer()
      var unsaved = JSON.parse(harness.readFile(harness.file)).range === "3M"
      sh('chmod 700 "$2"')
      // The footer's words are the way to try again.
      var notice = harness.find(body, "footerText")
      mouseClick(notice, notice.width / 2, notice.height / 2)
      harness.check("a save that can't land is said in the footer with a way to try again, and trying again once it can saves it",
        failed && unsaved && asked.indexOf("aren't saved") >= 0 && asked.indexOf("try again") >= 0 && landed()
          && within(3000, function() { return footer().indexOf("aren't saved") < 0 }),
        [failed, unsaved, asked, footer()].join(" | "))

      app.close()
      harness.finish()
    }
  }
}
