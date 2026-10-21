import QtQuick
import Quickshell
import Quickshell.Io
// The screenshot's hand-off, as Omarchy's own screenshot does it after its
// grab (`omarchy-capture-screenshot`): the picture (`ShareCard`), grabbed
// at its size and saved as a working copy in Stonks' cache folder, goes
// into the folder Omarchy's screenshots use (OMARCHY_SCREENSHOT_DIR, else
// XDG_PICTURES_DIR read from ~/.config/user-dirs.dirs as text, $HOME
// expanded, never run, else ~/Pictures) as
// stonks-<symbol>-<YYYY-MM-DD_HH-MM-SS>.png, onto the clipboard with
// `wl-copy`, and to Omarchy's notification with `omarchy-notification-send`,
// its thumbnail the picture and a click on it the reader's screenshot editor
// (OMARCHY_SCREENSHOT_EDITOR, else Tensaku) on the file. One shot at a
// time. The surfaces say what is shot and what to say; this knows only how.
Item {
  id: root

  readonly property string folder: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/grvc.stonks"
  readonly property string workingCopy: folder + "/screenshot.png"
  readonly property bool busy: grabbing || handOff.running || folderMaker.running
  property bool grabbing: false
  // The shot under way: the file's symbol, the toast's words, the grab, and
  // what to call with how it ended (`shoot`).
  property string shotSymbol: ""
  property string shotBody: ""
  property var shotGrab: null
  property var shotDone: null

  // Grabs `item` at its size and hands the picture on, as `symbol` in the
  // file's name (`Share.fileSymbol`) and `body` under the toast's headline;
  // `done(code)` hears how it ended: 0 saved, copied, and announced; 1 not
  // saved; 2 saved but not copied.
  function shoot(item, symbol, body, done) {
    if (busy) return false
    shotSymbol = symbol
    shotBody = body
    shotDone = done
    grabbing = true
    var asked = item.grabToImage(function(result) {
      root.grabbing = false
      root.shotGrab = result
      // Stonks' cache folder may not be there yet: made, the grab saves.
      if (result.saveToFile(root.workingCopy)) root.handOn()
      else folderMaker.running = true
    }, Qt.size(item.width, item.height))
    if (!asked) {
      grabbing = false
      finish(1)
    }
    return asked
  }

  function handOn() {
    shotGrab = null
    handOff.running = true
  }

  function finish(code) {
    var done = shotDone
    shotDone = null
    shotGrab = null
    if (done) done(code)
  }

  Process {
    id: folderMaker
    command: ["mkdir", "-p", root.folder]
    onExited: {
      if (root.shotGrab && root.shotGrab.saveToFile(root.workingCopy)) root.handOn()
      else root.finish(1)
    }
  }

  // Exits 1 when the picture can't be saved, 2 when it can't be copied; the
  // notification is best effort, as Omarchy's is: the picture is saved and
  // copied by then. A second shot in the same second takes the name with
  // "-2" after it, and so on, rather than writing over the first.
  Process {
    id: handOff
    command: ["sh", "-c", "dir=${OMARCHY_SCREENSHOT_DIR:-}\n"
      + "dirs=$HOME/.config/user-dirs.dirs\n"
      + "if [ -z \"$dir\" ] && [ -f \"$dirs\" ]; then\n"
      + "  dir=$(sed -n 's/^XDG_PICTURES_DIR=\"\\(.*\\)\"[[:space:]]*$/\\1/p' \"$dirs\" | tail -n 1)\n"
      + "  case $dir in\n"
      + "    '$HOME'*) dir=$HOME${dir#'$HOME'} ;;\n"
      + "    '${HOME}'*) dir=$HOME${dir#'${HOME}'} ;;\n"
      + "  esac\n"
      + "fi\n"
      + "dir=${dir:-$HOME/Pictures}\n"
      + "stamp=$(date +%Y-%m-%d_%H-%M-%S)\n"
      + "file=$dir/stonks-$1-$stamp.png\n"
      + "n=1\n"
      + "while [ -e \"$file\" ]; do n=$((n + 1)); file=$dir/stonks-$1-$stamp-$n.png; done\n"
      + "mkdir -p \"$dir\" && cp \"$2\" \"$file\" || exit 1\n"
      + "wl-copy --type image/png < \"$file\" || exit 2\n"
      + "omarchy-notification-send \"Screenshot saved to clipboard and file\" \"$3\" --image \"$file\" "
      + "--exec \"${OMARCHY_SCREENSHOT_EDITOR:-tensaku-edit}\" \"$file\" || true\n",
      "sh", root.shotSymbol, root.workingCopy, root.shotBody]
    onExited: function(code) { root.finish(code) }
  }
}
