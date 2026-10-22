import QtQuick
import Quickshell
import Quickshell.Io
// The screenshot's hand-off, as Omarchy's own screenshot does it after its
// grab (`omarchy-capture-screenshot`). A `sh` names the file in the folder
// Omarchy's screenshots use (OMARCHY_SCREENSHOT_DIR, else XDG_PICTURES_DIR
// read from ~/.config/user-dirs.dirs as text, $HOME expanded, never run,
// else ~/Pictures), made if it isn't there, as
// stonks-<symbol>-<YYYY-MM-DD_HH-MM-SS>.png, "-2" and on after a name taken
// that second; the picture (`ShareCard`) is grabbed at its size and saved
// there, with no copy anywhere else; `wl-copy` reads it on its input onto
// the clipboard; and `omarchy-notification-send` says so in Omarchy's own
// words, its thumbnail the picture and a click on it the reader's screenshot
// editor (OMARCHY_SCREENSHOT_EDITOR, else Tensaku) on the file, the editor
// and the file as separate words. Each command has 5 seconds. One shot at a
// time. The surfaces say what is shot; this knows only how.
Item {
  id: root

  readonly property string editor: Quickshell.env("OMARCHY_SCREENSHOT_EDITOR") || "tensaku-edit"
  // The shot under way: its symbol, its item, the file it is saved as, what
  // to call once the picture is taken, and what to call with how it ended
  // (`shoot`); no callback, no shot.
  property string shotSymbol: ""
  property var shotItem: null
  property string shotFile: ""
  property var shotTaken: null
  property var shotDone: null
  readonly property bool busy: shotDone !== null

  // Saves `item` as a picture named for `symbol` (`Share.fileSymbol`), copies
  // it, and announces it. `taken()` hears the picture taken, before it is
  // saved; then `item` may go. `done(code)` hears how it ended: 0 saved,
  // copied, and announced; 1 not saved; 2 saved but not copied. False while
  // another shot is under way.
  function shoot(item, symbol, taken, done) {
    if (busy) return false
    shotSymbol = symbol
    shotItem = item
    shotFile = ""
    shotTaken = taken
    shotDone = done
    naming.running = true
    return true
  }

  function finish(code) {
    var done = shotDone
    shotDone = null
    shotTaken = null
    shotItem = null
    if (done) done(code)
  }

  // The file's name: printed only once its folder is there to take it.
  Process {
    id: naming
    command: ["timeout", "5", "sh", "-c", "dir=${OMARCHY_SCREENSHOT_DIR:-}\n"
      + "dirs=$HOME/.config/user-dirs.dirs\n"
      + "if [ -z \"$dir\" ] && [ -f \"$dirs\" ]; then\n"
      + "  dir=$(sed -n 's/^XDG_PICTURES_DIR=\"\\(.*\\)\"[[:space:]]*$/\\1/p' \"$dirs\" | tail -n 1)\n"
      + "  case $dir in\n"
      + "    '$HOME'*) dir=$HOME${dir#'$HOME'} ;;\n"
      + "    '${HOME}'*) dir=$HOME${dir#'${HOME}'} ;;\n"
      + "  esac\n"
      + "fi\n"
      + "dir=${dir:-$HOME/Pictures}\n"
      + "mkdir -p \"$dir\" && [ -w \"$dir\" ] || exit 1\n"
      + "stamp=$(date +%Y-%m-%d_%H-%M-%S)\n"
      + "file=$dir/stonks-$1-$stamp.png\n"
      + "n=1\n"
      + "while [ -e \"$file\" ]; do n=$((n + 1)); file=$dir/stonks-$1-$stamp-$n.png; done\n"
      + "printf '%s\\n' \"$file\"\n",
      "sh", root.shotSymbol]
    stdout: StdioCollector {
      onStreamFinished: {
        var file = text.replace(/\n$/, "")
        if (!root.shotItem || file.charAt(0) !== "/" || file.indexOf("\n") >= 0) return root.finish(1)
        root.shotFile = file
        var item = root.shotItem
        // Grabbed at the item's size, which on the window's screen is the
        // picture's in pixels (`ShareCard`), to the nearest whole unit: on
        // a scale such as 1.75, where 2400 pixels are no whole number of
        // units, a pixel off. The PNG is encoded here, on this thread, once
        // the picture is taken.
        if (!item.grabToImage(function(result) {
          var taken = root.shotTaken
          root.shotTaken = null
          root.shotItem = null
          if (taken) taken()
          if (result.saveToFile(root.shotFile)) copying.running = true
          else root.finish(1)
        }, Qt.size(Math.round(item.width), Math.round(item.height)))) root.finish(1)
      }
    }
  }

  Process {
    id: copying
    command: ["timeout", "5", "sh", "-c", "exec wl-copy --type image/png < \"$1\"", "sh", root.shotFile]
    onExited: function(code) {
      if (code === 0) announcing.running = true
      else root.finish(2)
    }
  }

  // Best effort, as Omarchy's is: the picture is saved and copied by then.
  Process {
    id: announcing
    command: ["timeout", "5", "omarchy-notification-send", "Screenshot saved to clipboard and file",
      "Edit with Super + Alt + , (or click this)", "--image", root.shotFile, "--exec", root.editor, root.shotFile]
    onExited: root.finish(0)
  }
}
