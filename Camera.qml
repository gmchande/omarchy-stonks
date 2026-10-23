import QtQuick
import QtCore
import Quickshell.Io
// The screenshot's hand-off, as Omarchy's own screenshot does it after its
// grab, on the Omarchy installed. With Omasnap installed, as on Omarchy 4.5,
// the folder is Omasnap's: OMASNAP_SCREENSHOT_DIR, else
// OMARCHY_SCREENSHOT_DIR, which `omarchy-capture-screenshot` hands on as
// it, else the directory in omasnap.conf's [output], ~ expanded, else
// Screenshots in the pictures folder; the settings and the pictures folder
// read through Qt as Omasnap reads them (QSettings, QStandardPaths), so
// from XDG_CONFIG_HOME, and never written. The editor is `omasnap`.
// Without Omasnap, as on Omarchy 4.0, the folder is OMARCHY_SCREENSHOT_DIR,
// else XDG_PICTURES_DIR read from ~/.config/user-dirs.dirs as text, $HOME
// expanded, never run, else ~/Pictures; the editor is
// OMARCHY_SCREENSHOT_EDITOR, else Tensaku. A `sh` picks the folder and the
// editor, makes the folder if it isn't there, and names the file in it as
// stonks-<symbol>-<YYYY-MM-DD_HH-MM-SS>.png, "-2" and on after a name taken
// that second; the picture (`ShareCard`) is grabbed at its size and saved
// there, with no copy anywhere else; `wl-copy` reads it on its input onto
// the clipboard; and `omarchy-notification-send` says so in Omarchy 4.0's
// words, its thumbnail the picture and a click on it the editor on the
// file, the editor and the file as separate words. Each command has 5
// seconds. One shot at a time. The surfaces say what is shot; this knows
// only how.
Item {
  id: root

  // The shot under way: its symbol, its item, the folder omasnap.conf names
  // and the pictures folder as Omasnap reads them, the file it is saved as
  // and the editor a click opens it in, what to call once the picture is
  // taken, and what to call with how it ended (`shoot`); no callback, no
  // shot.
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

  // Saves `item` as a picture named for `symbol` (`Share.fileSymbol`), copies
  // it, and announces it. `taken()` hears the picture taken, before it is
  // saved; then `item` may go. `done(code)` hears how it ended: 0 saved,
  // copied, and announced; 1 not saved; 2 saved but not copied. False while
  // another shot is under way.
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

  // The editor on its first line, then the file's name: printed only once
  // its folder is there to take it. Read through `head` up to 8 KB, twice
  // the longest path Linux opens (PATH_MAX, 4096 bytes), a byte past it
  // too, so an answer that reaches the cap shows it and names no file.
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

  // Best effort, as Omarchy 4.0's is: the picture is saved and copied by
  // then.
  Process {
    id: announcing
    command: ["timeout", "5", "omarchy-notification-send", "Screenshot saved to clipboard and file",
      "Edit with Super + Alt + , (or click this)", "--image", root.shotFile, "--exec", root.shotEditor, root.shotFile]
    onExited: root.finish(0)
  }
}
