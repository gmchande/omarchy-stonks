import QtQuick
import QtCore
import Quickshell.Io
// The screenshot's hand-off, as Omarchy's own screenshot does it after its
// grab. With Omasnap, as on Omarchy 4.5, the folder is OMASNAP_SCREENSHOT_DIR,
// else OMARCHY_SCREENSHOT_DIR, which `omarchy-capture-screenshot` passes on as
// it, else omasnap.conf's [output] directory, else Screenshots in the pictures
// folder, read through Qt as Omasnap reads them, so from XDG_CONFIG_HOME, and
// never written; the editor is `omasnap`. Without it, as on Omarchy 4.0, the
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

  Settings {
    id: omasnapSettings
    location: StandardPaths.writableLocation(StandardPaths.ConfigLocation) + "/omasnap/omasnap.conf"
  }

  // `taken()` hears the picture taken, before it is saved; then `item` may go.
  // `done(code)`: 0 saved, copied and announced; 1 not saved; 2 saved but not
  // copied.
  function shoot(item, symbol, taken, done) {
    if (busy) return false
    shotSymbol = symbol
    shotItem = item
    // As Omasnap reads it: a list (a value with a comma) is no folder.
    omasnapSettings.sync()
    var configured = omasnapSettings.value("output/directory", "")
    shotOmasnapFolder = typeof configured === "string" ? configured.trim() : ""
    shotPictures = decodeURIComponent(String(StandardPaths.writableLocation(StandardPaths.PicturesLocation)).replace(/^file:\/\//, ""))
    shotFile = ""
    shotEditor = ""
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

  // The editor, then the file, printed once its folder can take it. Read up to
  // 8 KB, twice Linux's PATH_MAX, and a byte past, so an answer over the cap
  // names no file.
  Process {
    id: naming
    command: ["timeout", "5", "sh", "-c", "{\n"
      + "if command -v omasnap > /dev/null; then\n"
      + "  editor=omasnap\n"
      + "  conf=$2\n"
      + "  case $conf in '~') conf=$HOME ;; '~/'*) conf=$HOME${conf#'~'} ;; esac\n"
      + "  dir=${OMASNAP_SCREENSHOT_DIR:-${OMARCHY_SCREENSHOT_DIR:-${conf:-$3/Screenshots}}}\n"
      + "else\n"
      + "  editor=${OMARCHY_SCREENSHOT_EDITOR:-tensaku-edit}\n"
      + "  dir=${OMARCHY_SCREENSHOT_DIR:-}\n"
      + "  dirs=$HOME/.config/user-dirs.dirs\n"
      + "  if [ -z \"$dir\" ] && [ -f \"$dirs\" ]; then\n"
      + "    dir=$(sed -n 's/^XDG_PICTURES_DIR=\"\\(.*\\)\"[[:space:]]*$/\\1/p' \"$dirs\" | tail -n 1)\n"
      + "    case $dir in\n"
      + "      '$HOME'*) dir=$HOME${dir#'$HOME'} ;;\n"
      + "      '${HOME}'*) dir=$HOME${dir#'${HOME}'} ;;\n"
      + "    esac\n"
      + "  fi\n"
      + "  dir=${dir:-$HOME/Pictures}\n"
      + "fi\n"
      + "mkdir -p \"$dir\" && [ -w \"$dir\" ] || exit 1\n"
      + "stamp=$(date +%Y-%m-%d_%H-%M-%S)\n"
      + "file=$dir/stonks-$1-$stamp.png\n"
      + "n=1\n"
      + "while [ -e \"$file\" ]; do n=$((n + 1)); file=$dir/stonks-$1-$stamp-$n.png; done\n"
      + "printf '%s\\n%s\\n' \"$editor\" \"$file\"\n"
      + "} | head -c 8193\n",
      "sh", root.shotSymbol, root.shotOmasnapFolder, root.shotPictures]
    stdout: StdioCollector {
      id: namingOut
      onStreamFinished: {
        if (namingOut.data.byteLength > 8192) return root.finish(1)
        var printed = text.replace(/\n$/, "")
        var cut = printed.indexOf("\n")
        var file = printed.slice(cut + 1)
        if (!root.shotItem || cut < 1 || file.charAt(0) !== "/" || file.indexOf("\n") >= 0) return root.finish(1)
        root.shotEditor = printed.slice(0, cut)
        root.shotFile = file
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
          if (result.saveToFile(root.shotFile)) copying.running = true
          else root.finish(1)
        })) root.finish(1)
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

  // Best effort, as Omarchy 4.0's is: the picture is saved and copied by
  // then.
  Process {
    id: announcing
    command: ["timeout", "5", "omarchy-notification-send", "Screenshot saved to clipboard and file",
      "Click to edit", "--image", root.shotFile, "--exec", root.shotEditor, root.shotFile]
    onExited: root.finish(0)
  }
}
