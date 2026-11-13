.pragma library
// The commands Stonks runs that carry shell code, as the argument lists a
// Process takes, each beside the rule that reads what it prints. A test runs
// each one (test/commands.test.js).

// The camera's: the editor, then the file, printed once its folder can take
// it. With Omasnap, as Omarchy 4.5 hands it screenshots, its folder; without,
// Omarchy 4.0's, from at most 64 KiB of user-dirs.dirs. Cut at 8 KB, twice
// Linux's PATH_MAX, and a byte past, so an answer over the cap names no file.
function screenshotName(symbol, omasnapFolder, pictures) {
  return ["timeout", "-k", "1", "5", "sh", "-c", "{\n"
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
    + "    dir=$(head -c 65536 \"$dirs\" | sed -n 's/^XDG_PICTURES_DIR=\"\\(.*\\)\"[[:space:]]*$/\\1/p' | tail -n 1)\n"
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

// Omasnap's folder for screenshots, as its omasnap.conf (read by `FileRead`)
// holds it in [output] directory, trimmed, or "": Omasnap reads it with
// Qt's QSettings, and a value QSettings reads as no string, such as a list
// (a value with a comma), names no folder.
function omasnapFolder(text) {
  var folder = iniString(String(text), "output", "directory")
  return folder === null ? "" : folder.trim()
}

// The string a QSettings INI file holds for `key` in `section`, read as Qt
// reads it (qsettings.cpp: readIniLine, readIniFile, readIniSection,
// iniUnescapedKey, iniUnescapedStringList, stringToVariant), or null where
// Qt reads no string: no such key, a list, or another type.
function iniString(text, section, key) {
  var data = text.replace(/^\ufeff/, "")
  var found = null
  var current = ""
  for (var line = iniLine(data, 0); line; line = iniLine(data, line.next)) {
    var body = data.slice(line.start, line.start + line.length)
    if (body.charAt(0) === "[") {
      var close = body.indexOf("]")
      var name = (close < 0 ? body.slice(1) : body.slice(1, close)).trim()
      current = name.toLowerCase() === "general" ? "" : name.toLowerCase() === "%general" ? name.slice(1) : iniKey(name)
    } else if (line.equals >= 0 && current === section && iniKey(body.slice(0, line.equals - line.start).trim()) === key) {
      // The last one in the file wins.
      found = iniValue(body.slice(line.equals - line.start + 1))
    }
  }
  return found
}

// readIniLine: the line from `at`, by `start` and `length` in `data`, with
// its first = outside quotes, or null at the end. A ; starting a line makes
// it a comment, and one later outside quotes ends it.
function iniLine(data, at) {
  var space = " \t\n\r"
  var start = at
  while (start < data.length && space.indexOf(data.charAt(start)) >= 0) start++
  var i = start
  var quoted = false
  var equals = -1
  while (i < data.length) {
    var ch = data.charAt(i)
    if ("\n\r\";=\\".indexOf(ch) < 0) { i++; continue }
    i++
    if (ch === "=") {
      if (!quoted && equals < 0) equals = i - 1
    } else if (ch === "\n" || ch === "\r") {
      if (i === start + 1) start++
      else if (!quoted) { i--; break }
    } else if (ch === "\\") {
      if (i < data.length) {
        var next = data.charAt(i++)
        if (i < data.length) {
          var after = data.charAt(i)
          if ((next === "\n" && after === "\r") || (next === "\r" && after === "\n")) i++
        }
      }
    } else if (ch === "\"") {
      quoted = !quoted
    } else if (i === start + 1) {
      while (i < data.length && data.charAt(i) !== "\n" && data.charAt(i) !== "\r") i++
      while (i < data.length && space.indexOf(data.charAt(i)) >= 0) i++
      start = i
    } else if (!quoted) {
      i--
      break
    }
  }
  return i > start ? { start: start, length: i - start, equals: equals, next: i } : null
}

// iniUnescapedKey: \ is /, and %XX and %UXXXX are the characters they name.
function iniKey(key) {
  var out = ""
  for (var i = 0; i < key.length; i++) {
    var ch = key.charAt(i)
    if (ch === "\\") { out += "/"; continue }
    if (ch !== "%" || i === key.length - 1) { out += ch; continue }
    var first = key.charAt(i + 1) === "U" ? i + 2 : i + 1
    var digits = first === i + 2 ? 4 : 2
    var hex = key.slice(first, first + digits)
    if (hex.length < digits || !/^[0-9a-fA-F]+$/.test(hex)) { out += "%"; continue }
    out += String.fromCharCode(parseInt(hex, 16))
    i = first + digits - 1
  }
  return out
}

// iniUnescapedStringList, then stringToVariant: the string, or null for a
// list or a value of another type.
function iniValue(raw) {
  var codes = { a: "\x07", b: "\b", f: "\f", n: "\n", r: "\r", t: "\t", v: "\v", "\"": "\"", "?": "?", "'": "'", "\\": "\\" }
  var out = ""
  var quoted = false
  var wasQuoted = false
  var i = 0
  var chop = 0
  var skipSpaces = function() { while (i < raw.length && (raw.charAt(i) === " " || raw.charAt(i) === "\t")) i++ }
  skipSpaces()
  while (i < raw.length) {
    var ch = raw.charAt(i)
    if (ch === "\\") {
      i++
      if (i >= raw.length) break
      var code = raw.charAt(i++)
      if (codes[code] !== undefined) out += codes[code]
      else if ((code === "x" && i < raw.length && /[0-9a-fA-F]/.test(raw.charAt(i))) || /[0-7]/.test(code)) {
        var radix = code === "x" ? 16 : 8
        var digit = radix === 16 ? /[0-9a-fA-F]/ : /[0-7]/
        var value = radix === 16 ? 0 : parseInt(code, 8)
        while (i < raw.length && digit.test(raw.charAt(i))) value = (value * radix + parseInt(raw.charAt(i++), radix)) & 0xffff
        out += String.fromCharCode(value)
      } else if ((code === "\n" || code === "\r") && i < raw.length) {
        var two = raw.charAt(i)
        if ((two === "\n" || two === "\r") && two !== code) i++
      }
      chop = out.length
    } else if (ch === "\"") {
      i++
      wasQuoted = true
      quoted = !quoted
      if (!quoted) {
        skipSpaces()
        chop = out.length
      }
    } else if (ch === "," && !quoted) {
      return null
    } else {
      var j = i + 1
      while (j < raw.length && "\\\",".indexOf(raw.charAt(j)) < 0) j++
      out += raw.slice(i, j)
      i = j
    }
  }
  if (!wasQuoted) {
    var end = out.length
    while (end > chop && (out.charAt(end - 1) === " " || out.charAt(end - 1) === "\t")) end--
    out = out.slice(0, end)
  }
  if (out.charAt(0) !== "@") return out
  if (out.slice(-1) === ")" && out.indexOf("@String(") === 0) return out.slice(8, -1)
  if (out.slice(-1) === ")" && (/^@(ByteArray|Variant|DateTime|Rect|Size|Point)\(/.test(out) || out === "@Invalid()")) return null
  return out.indexOf("@@") === 0 ? out.slice(1) : out
}

// The file keeper's: mktemp makes the file 0600 and `ln` names it, never over
// a file there, so no other account reads it and no reader sees it half
// written. The text rides in the environment as STONKS_TEXT, whole as the
// command starts: a command line is world-readable, /proc/PID/environ is
// 0400.
function createPrivately(path) {
  return ["timeout", "-k", "1", "5", "sh", "-c", "umask 077 && tmp=$(mktemp -- \"$1.XXXXXX\") || exit 1\n"
    + "printf '%s' \"$STONKS_TEXT\" > \"$tmp\" && ln -- \"$tmp\" \"$1\"\n"
    + "code=$?\n"
    + "rm -f -- \"$tmp\"\n"
    + "exit $code", "sh", path]
}

// The file reader's (`FileRead`): a file Stonks keeps, or a setting it
// reads, only if it is a regular file, cut a byte past `cap`, so one over
// the cap shows itself. dd opens it without waiting, so a FIFO put there
// since the test can't hold the read, and the read has 5 s. It exits 3
// where nothing is there, and 4 where what is there is no regular file.
function readSaved(path, cap) {
  return ["timeout", "-k", "1", "5", "sh", "-c", "[ -e \"$1\" ] || exit 3\n"
    + "[ -f \"$1\" ] || exit 4\n"
    + "exec dd if=\"$1\" iflag=nonblock,count_bytes bs=65536 count=\"$2\" status=none", "sh", path, String(cap + 1)]
}

// What a read found: { text }, { missing: true } where nothing is there, or
// { refused: true } for anything else: no regular file, one over `cap`
// bytes, one that couldn't be read, or a read that didn't end.
function readSavedFile(code, bytes, text, cap) {
  if (code === 0 && bytes <= cap) return { text: String(text) }
  if (code === 3) return { missing: true }
  return { refused: true }
}

// The sounds': once a run, the md5s of what the sounds are made from, each
// look's stamp, and the files no newer than it. A newer one was written by
// an older Stonks, which kept no stamp. The answer runs under 8 KB and is
// read up to 64.
function soundSurvey(pluginFolder, cacheFolder) {
  return ["timeout", "-k", "1", "5", "sh", "-c", "{ cd -- \"$1\" && md5sum -- ChartSound.js Sounds.qml Waking.js sounds/*/*.wav && cd -- \"$2\" || exit 0\n"
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
// Each has its own time; the whole has 8 s, past both, and a stop ends both:
// --foreground keeps each in the whole's process group.
function bellCheck() {
  return ["timeout", "-k", "1", "8", "bash", "-c", "[ \"$(timeout --foreground -k 1 2 omarchy-shell notifications isDnd 2> /dev/null)\" = on ] && exit 1\n"
    + "set -o pipefail; timeout --foreground -k 1 3 pw-dump | head -c 4000001"]
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

// A paste's (`Field`): the clipboard's text, or the primary selection's, as
// a middle-click pastes it, cut a byte past `cap`, so an answer over the cap
// shows itself. An owner that never answers, or never stops, has 2 s.
function pastedText(primary, cap) {
  return ["timeout", "-k", "1", "2", "sh", "-c", "set -o pipefail; wl-paste " + (primary ? "--primary " : "")
    + "--no-newline --type text | head -c " + (cap + 1)]
}

// The text a paste puts in, or null for an answer over `cap` bytes, or one
// that failed. A field is one line, so each line break is a space.
function readPastedText(code, bytes, text, cap) {
  if (code !== 0 || bytes > cap) return null
  return String(text).replace(/\r\n|[\r\n\u2028\u2029]/g, " ")
}

// Text selected with the pointer, put in the primary selection for a
// middle-click elsewhere, as a TextField puts it (`Field`). The text comes
// on wl-copy's input; wl-copy stays to hand it out, as it does for a copy.
function primaryCopy() {
  return ["timeout", "-k", "1", "5", "wl-copy", "--primary"]
}

// The silence that holds the output awake for the chimes (`Sounds`): pw-cat
// reading zeros for `seconds`, saying "-> streaming" once it reaches the
// output. What it says is cut at 64 KB at most, by a dd that hands each
// line on as it comes: `head -c` would hold every line until the stream
// ends.
function silenceStream(seconds) {
  return ["timeout", "-k", "1", String(seconds), "sh", "-c", "pw-cat -v --playback --raw --rate 24000 --channels 1 --format s16"
    + " --media-role Notification --latency 30ms /dev/zero 2>&1 > /dev/null | dd bs=4096 iflag=count_bytes count=65536 status=none"]
}
