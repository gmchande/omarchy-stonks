.pragma library
// The cell drawings: block digits, the bull and the bear, and the mark's
// levels. Knows no data.

// The thin rules: the breadth rule under the list's name and the info
// lines' ranges. 2 px is the thinnest at which a colour reads; the plain
// rule is the foreground at RULE_INK; retro draws a rule as cells on the
// pixel chart's grain, RULE_PITCH apart.
var RULE_THICKNESS = 2
var RULE_PITCH = 3
var RULE_INK = 0.12

// 3x5 bitmap digits, drawn in square cells the way Omarchy draws its own
// logo in blocks. Rows 0–4 stand on the baseline; row 5 is below it, where
// only the comma's tail goes, so "1,096.16" never reads as "1.096.16".
var BLOCK_GLYPHS = {
  "0": ["111", "101", "101", "101", "111"],
  "1": ["010", "110", "010", "010", "111"],
  "2": ["111", "001", "111", "100", "111"],
  "3": ["111", "001", "111", "001", "111"],
  "4": ["101", "101", "111", "001", "001"],
  "5": ["111", "100", "111", "001", "111"],
  "6": ["111", "100", "111", "101", "111"],
  "7": ["111", "001", "001", "001", "001"],
  "8": ["111", "101", "111", "101", "111"],
  "9": ["111", "101", "111", "001", "111"],
  ".": ["0", "0", "0", "0", "1"],
  ",": ["0", "0", "0", "0", "1", "1"],
  // The unavailable price, money(null), and the minus both draw as a bar,
  // and the price on its way draws as three dots rather than nothing.
  "—": ["000", "000", "111", "000", "000"],
  "\u2212": ["000", "000", "111", "000", "000"],
  "…": ["00000", "00000", "00000", "00000", "10101"]
}

// Stonks' mark: a small chart that climbs, as points left to right, 0 at the
// top. The look icon draws it as a curve and in cells.
function markPoints() {
  return [{ x: 0, y: 0.9 }, { x: 0.25, y: 0.45 }, { x: 0.5, y: 0.75 }, { x: 0.75, y: 0.25 }, { x: 1, y: 0.05 }]
}

// The mark in cells, the way the retro chart draws: each column's cap row,
// of `rows`, 0 at the top, its stem running down to the floor.
function markLevels(rows) {
  return markPoints().map(function(p) { return Math.round(p.y * (rows - 1)) })
}

// The price as cells on a five-row grid: every digit's full 3x5 slot, the
// way an LCD shows its unlit segments faintly, with the glyph's cells lit.
// Punctuation has no slot. One blank column between characters.
function blockCells(text) {
  var cells = []
  var x = 0
  var chars = String(text || "").split("")
  for (var c = 0; c < chars.length; c++) {
    var glyph = BLOCK_GLYPHS[chars[c]]
    if (!glyph) continue
    var slot = glyph[0].length === 3
    for (var r = 0; r < glyph.length; r++) {
      for (var b = 0; b < glyph[r].length; b++) {
        var lit = glyph[r].charAt(b) === "1"
        if (lit || slot) cells.push({ x: x + b, y: r, lit: lit })
      }
    }
    x += glyph[0].length + 1
  }
  return { columns: Math.max(0, x - 1), cells: cells }
}

// The bull for an up day, the bear for a down day: the header's animal in
// both looks, and the pill's icon form. 20 wide, 14 tall; "#" is a lit
// pixel. Two faces, front on. The bull reads by its long horns and its
// nostrils. The bear reads by round ears that stand out from its head,
// with a notch under each, and cheeks wider than its ears: earlier faces
// whose outline ran straight up into the ears read as cats.
// test/qml/render.qml draws the other candidates beside these, and marks
// whichever pair is here as the default.
var BULL_SPRITE = [
  "....................",
  "#..................#",
  "##................##",
  ".###............###.",
  "...######..######...",
  ".....##########.....",
  "...###.######.###...",
  ".....#.######.#.....",
  ".....##########.....",
  ".....##########.....",
  "....############....",
  "....##.######.##....",
  "....############....",
  ".....##########....."
]

var BEAR_SPRITE = [
  "....................",
  "..###..........###..",
  ".#####........#####.",
  ".##################.",
  ".##################.",
  "..################..",
  ".#####.######.#####.",
  "####################",
  ".#######....#######.",
  ".########..########.",
  ".########..########.",
  "..################..",
  "...##############...",
  ".....##########....."
]

// A row's remove button in retro: an × in the rows' 2 px cells, one cell
// thick and the height of the symbol's capitals beside it.
var REMOVE_SPRITE = [
  "#...#",
  ".#.#.",
  "..#..",
  ".#.#.",
  "#...#"
]

// The header's speaker and camera, solid, on the look icon's grid: 4 rows,
// 6 columns. Each has its cells for retro, "#" lit and "+" faint, as the
// mark's stems are, and its path for smooth, drawn on cells 3 px apart and
// scaled with them (`GridIcon`): "M" "L" "A" (centre, radius, from and to
// degrees) "Z" build it, "fill", "stroke", and "hollow" (even-odd, so the
// lens is a hole) paint it, and "dot" fills a circle. The speaker is on
// with its waves, off with a cross, its waves faint in retro; the camera
// is at rest with its lens a hole, lit with the shot's dot in it, faint
// cells in retro.
var SOUND_CONE = [["M", 0.5, 3.5], ["L", 3.5, 3.5], ["L", 7.5, 0.5], ["L", 7.5, 10.5], ["L", 3.5, 7.5], ["L", 0.5, 7.5], ["Z"], ["fill"]]
var SOUND_ON = { columns: 6, rows: 4,
  cells: ["..#.#.", "###..#", "###..#", "..#.#."],
  path: SOUND_CONE.concat([["A", 7, 5.5, 3.8, -50, 50], ["stroke"], ["A", 7, 5.5, 7.4, -50, 50], ["stroke"]]) }
var SOUND_OFF = { columns: 6, rows: 4,
  cells: ["..#.+.", "###..+", "###..+", "..#.+."],
  path: SOUND_CONE.concat([["M", 10.5, 3.5], ["L", 14.5, 7.5], ["stroke"], ["M", 14.5, 3.5], ["L", 10.5, 7.5], ["stroke"]]) }
var CAMERA_BODY = [["M", 0.5, 3], ["L", 4.8, 3], ["L", 6.3, 0.5], ["L", 10.7, 0.5], ["L", 12.2, 3], ["L", 16.5, 3], ["L", 16.5, 10.5], ["L", 0.5, 10.5], ["Z"],
  ["M", 11.3, 6.6], ["A", 8.5, 6.6, 2.8, 0, 359.9], ["Z"], ["hollow"]]
var CAMERA = { columns: 6, rows: 4,
  cells: ["..##..", "######", "##..##", "######"],
  path: CAMERA_BODY }
var CAMERA_LIT = { columns: 6, rows: 4,
  cells: ["..##..", "######", "##++##", "######"],
  path: CAMERA_BODY.concat([["dot", 8.5, 6.6, 1.6]]) }

// The header's icons' cell, their grid's pitch, from the shell's text
// scale: 3 px to text size 13, 4 px from 14 to 17, 5 px from 18, so the
// icons keep their weight beside the words.
function iconCell(fontScale) {
  return Math.max(3, Math.round(3 * fontScale))
}

// Each animal's eyes closing, as the header steps them: the lid half down,
// then shut (`HeaderStatus`). The bull's two-cell eyes shut to slits
// lowered a row. The bear's one-cell eyes have no half: the lid covers
// them, then each opens as a two-cell slit at eye level, widened outward:
// widened inward they crowd the nose, and lowered a row they meet it in a
// frown.
var BULL_HALF = BULL_SPRITE.slice()
BULL_HALF[6] = "...##############..."
var BULL_SHUT = BULL_HALF.slice()
BULL_SHUT[7] = ".....#..####..#....."
var BEAR_HALF = BEAR_SPRITE.slice()
BEAR_HALF[6] = ".##################."
var BEAR_SHUT = BEAR_SPRITE.slice()
BEAR_SHUT[6] = ".####..######..####."

// The sleeper's "z" in cells, 3 wide and 5 tall like the block digits, at
// the sprite's cell size: it fits the gap before the header's words.
var SLEEP_Z = [
  "###",
  "..#",
  ".#.",
  "#..",
  "###"
]

// Flattened lit pixels for a Repeater: [{x, y}, ...].
function spritePixels(rows) {
  var out = []
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      if (rows[y].charAt(x) === "#") out.push({ x: x, y: y })
    }
  }
  return out
}

// The animal for an up day or a down one, its eyes open (0), half shut
// (1), or shut (2).
function spriteFor(up, lids) {
  var open = up ? BULL_SPRITE : BEAR_SPRITE
  var half = up ? BULL_HALF : BEAR_HALF
  var shut = up ? BULL_SHUT : BEAR_SHUT
  return spritePixels(lids === 2 ? shut : lids === 1 ? half : open)
}
