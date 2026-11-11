.pragma library
// The commands Stonks runs that carry shell code, as the argument lists a
// Process takes, each beside the rule that reads what it prints. A test runs
// each one (test/commands.test.js).

// The camera's: the editor, then the file, printed once its folder can take
// it. With Omasnap, as Omarchy 4.5 hands it screenshots, its folder; without,
// Omarchy 4.0's. Cut at 8 KB, twice Linux's PATH_MAX, and a byte past, so an
// answer over the cap names no file.
function screenshotName(symbol, omasnapFolder, pictures) {
  return ["timeout", "5", "sh", "-c", "{\n"
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
    + "} | head -c 8193\n", "sh", symbol, omasnapFolder, pictures]
}

// { editor, file }, or null for an answer that names no whole file.
function readScreenshotName(text) {
  var printed = String(text).replace(/\n$/, "")
  var cut = printed.indexOf("\n")
  var file = printed.slice(cut + 1)
  if (cut < 1 || file.charAt(0) !== "/" || file.indexOf("\n") >= 0) return null
  return { editor: printed.slice(0, cut), file: file }
}

// The file keeper's: mktemp makes the file 0600 and `ln` names it, never over
// a file there, so no other account reads it and no reader sees it half
// written. The text rides in the environment as STONKS_TEXT, whole as the
// command starts: a command line is world-readable, /proc/PID/environ is
// 0400.
function createPrivately(path) {
  return ["timeout", "5", "sh", "-c", "umask 077 && tmp=$(mktemp -- \"$1.XXXXXX\") || exit 1\n"
    + "printf '%s' \"$STONKS_TEXT\" > \"$tmp\" && ln -- \"$tmp\" \"$1\"\n"
    + "code=$?\n"
    + "rm -f -- \"$tmp\"\n"
    + "exit $code", "sh", path]
}

// The sounds': once a run, the md5s of what the sounds are made from, each
// look's stamp, and the files no newer than it. A newer one was written by
// an older Stonks, which kept no stamp. The answer runs under 8 KB and is
// read up to 64.
function soundSurvey(pluginFolder, cacheFolder) {
  return ["timeout", "5", "sh", "-c", "{ cd -- \"$1\" && md5sum -- ChartSound.js Sounds.qml Waking.js sounds/*/*.wav && cd -- \"$2\" || exit 0\n"
    + "for look in smooth retro; do\n"
    + "  [ -f \"stamp-$look\" ] || continue\n"
    + "  printf 'stamp %s %s\\n' \"$look\" \"$(head -c 64 -- \"stamp-$look\")\"\n"
    + "  for f in chime-*\"$look\"-*.wav lead-\"$look\"-*.wav; do\n"
    + "    [ -f \"$f\" ] && ! [ \"$f\" -nt \"stamp-$look\" ] && printf 'have %s\\n' \"$f\"\n"
    + "  done\n"
    + "done; } | head -c 65536", "sh", pluginFolder, cacheFolder]
}

// Per look, the md5 lines its sounds are made from, null unless all of
// them came: ChartSound.js, Sounds.qml, Waking.js and each of its `fixed`
// bundled sounds; each look's stamp; and the files kept, as keys.
function readSoundSurvey(text, fixed) {
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
  ;["smooth", "retro"].forEach(function(look) { if (sums[look].length !== 3 + fixed) sums[look] = null })
  return { sums: sums, stamps: stamps, have: have }
}

// The bell's: quiet under Omarchy's Do Not Disturb, asked as Omarchy's
// toggle asks it, and otherwise PipeWire's state, cut a byte past 4 MB to
// show an answer over the cap. omarchy-shell's -q would hide its answer too.
function bellCheck() {
  return ["bash", "-c", "[ \"$(timeout -k 1 2 omarchy-shell notifications isDnd 2> /dev/null)\" = on ] && exit 1\n"
    + "set -o pipefail; timeout -k 1 3 pw-dump | head -c 4000001"]
}

// An app's capture stream running, not one reading a speaker's monitor, as
// a level meter does. An answer that doesn't read counts as recording.
function recording(dump) {
  var nodes
  try { nodes = JSON.parse(dump) } catch (e) { return true }
  return !Array.isArray(nodes) || nodes.some(function(node) {
    var props = node.info && node.info.props || {}
    return node.type === "PipeWire:Interface:Node" && props["media.class"] === "Stream/Input/Audio"
      && node.info.state === "running" && String(props["stream.capture.sink"]) !== "true"
  })
}

// The chimes': one shell while sounds are on, starting a pw-play in the
// background for each chime named on its input that `names`, its `case`
// patterns, allow, so chimes overlap and the shell's thread starts no
// process per chime. Each has 2 s, so a stalled PipeWire can't pile them
// up, and starts from a subshell that ends at once: from this shell, each
// grew it by a third of a kilobyte, 10 MB over 20,000 chimes.
function chimePlayer(names, folder) {
  return ["sh", "-c", "while read -r name; do case $name in " + names + ") "
    + "( timeout -k 1 2 pw-play --media-role Notification --latency 30ms \"$1/$name\" & ) ;; esac; done", "sh", folder]
}

// The update that restarts the shell: in a terminal Omarchy opens, which
// shows what changes and asks, and only when the plugin's folder moved. The
// launcher joins its arguments into a `bash -c` script, so the last one is
// shell code.
function updateAndRestart(pluginId) {
  return ["omarchy", "launch", "floating", "terminal", "with", "presentation",
    "p=$HOME/.config/omarchy/plugins/" + pluginId + "; was=$(git -C \"$p\" rev-parse HEAD);"
    + " omarchy plugin update " + pluginId + " && [[ $(git -C \"$p\" rev-parse HEAD) != \"$was\" ]]"
    + " && echo 'Restarting the shell…' && omarchy restart shell"]
}
