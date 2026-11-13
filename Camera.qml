import QtQuick
import QtCore
import Quickshell.Io
import "Commands.js" as Commands
// The screenshot's hand-off, as Omarchy's own screenshot does it after its
// grab. With Omasnap, as on Omarchy 4.5, the folder is OMASNAP_SCREENSHOT_DIR,
// else OMARCHY_SCREENSHOT_DIR, which `omarchy-capture-screenshot` passes on as
// it, else omasnap.conf's [output] directory, else Screenshots in the pictures
// folder, read as Omasnap reads them, so from XDG_CONFIG_HOME, and never
// written; the editor is `omasnap`. Without it, as on Omarchy 4.0, the
// folder is OMARCHY_SCREENSHOT_DIR, else XDG_PICTURES_DIR from user-dirs.dirs,
// read as text and never run, else ~/Pictures; the editor is
// OMARCHY_SCREENSHOT_EDITOR, else Tensaku. The picture is saved there and
// nowhere else, copied to the clipboard, and announced in Omarchy 4.0's words,
// a click opening it in the editor. Each command has 5 s; one shot at a time.
Item {
  id: root

  // The shot under way; no `shotDone`, no shot.
  property string shotSymbol: ""
  property var shotItem: null
  property string shotOmasnapFolder: ""
  property string shotPictures: ""
  property string shotFile: ""
  property string shotEditor: ""
  property var shotTaken: null
  property var shotDone: null
  readonly property bool busy: shotDone !== null

  // omasnap.conf, at most 64 KiB: Omasnap writes a few lines.
  FileRead {
    id: omasnapConf
    onDone: function(answer) {
      if (!root.shotDone) return
      root.shotOmasnapFolder = Commands.omasnapFolder(answer.text || "")
      naming.running = true
    }
  }
  function localPath(location) {
    return decodeURIComponent(String(StandardPaths.writableLocation(location)).replace(/^file:\/\//, ""))
  }

  // `taken()` hears the picture taken, before it is saved; then `item` may go.
  // `done(code)`: 0 saved, copied and announced; 1 not saved; 2 saved but not
  // copied.
  function shoot(item, symbol, taken, done) {
    if (busy) return false
    shotSymbol = symbol
    shotItem = item
    shotOmasnapFolder = ""
    shotPictures = localPath(StandardPaths.PicturesLocation)
    shotFile = ""
    shotEditor = ""
    shotTaken = taken
    shotDone = done
    omasnapConf.read(localPath(StandardPaths.ConfigLocation) + "/omasnap/omasnap.conf", 65536)
    return true
  }

  function finish(code) {
    var done = shotDone
    shotDone = null
    shotTaken = null
    shotItem = null
    if (done) done(code)
  }

  // The editor, then the file (`Commands.screenshotName`).
  Process {
    id: naming
    command: Commands.screenshotName(root.shotSymbol, root.shotOmasnapFolder, root.shotPictures)
    stdout: StdioCollector {
      id: namingOut
      onStreamFinished: {
        var named = namingOut.data.byteLength > 8192 ? null : Commands.readScreenshotName(text)
        if (!root.shotItem || !named) return root.finish(1)
        root.shotEditor = named.editor
        root.shotFile = named.file
        var item = root.shotItem
        // No size is passed: Qt sizes the grab from the item's fractional size
        // times the screen's ratio, so at a scale such as 1.75, where 2400
        // pixels are no whole number of units, it still saves 2400. The PNG is
        // encoded on this thread.
        if (!item.grabToImage(function(result) {
          var taken = root.shotTaken
          root.shotTaken = null
          root.shotItem = null
          if (taken) taken()
          if (!result.saveToFile(root.shotFile)) return root.finish(1)
          copying.code = -1
          copying.running = true
        })) root.finish(1)
      }
    }
    // A command that fails to start ends with no stream's end.
    onRunningChanged: if (!running && root.shotDone && root.shotFile === "") root.finish(1)
  }

  // Read as `running` falls, since a command that fails to start never
  // exits.
  Process {
    id: copying
    property int code: -1
    command: ["timeout", "-k", "1", "5", "sh", "-c", "exec wl-copy --type image/png < \"$1\"", "sh", root.shotFile]
    onExited: function(code) { copying.code = code }
    onRunningChanged: {
      if (running) return
      if (copying.code === 0) announcing.running = true
      else root.finish(2)
    }
  }

  // Best effort, as Omarchy 4.0's is: the picture is saved and copied by
  // then.
  Process {
    id: announcing
    command: ["timeout", "-k", "1", "5", "omarchy-notification-send", "Screenshot saved to clipboard and file",
      "Click to edit", "--image", root.shotFile, "--exec", root.shotEditor, root.shotFile]
    onRunningChanged: if (!running) root.finish(0)
  }
}
