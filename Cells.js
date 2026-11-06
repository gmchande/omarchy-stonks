.pragma library
// The cell drawings: block digits, the animals and the icons. Knows no data.

var RULE_THICKNESS = 2
var RULE_PITCH = 3
var RULE_INK = 0.12

// Row 5, below the baseline, holds only the comma's tail, so "1,096.16"
// never reads as "1.096.16".
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
  // The unknown price and the minus draw as a bar, a price on its way as
  // three dots.
  "—": ["000", "000", "111", "000", "000"],
  "\u2212": ["000", "000", "111", "000", "000"],
  "…": ["00000", "00000", "00000", "00000", "10101"]
}

function markPoints() {
  return [{ x: 0, y: 0.9 }, { x: 0.25, y: 0.45 }, { x: 0.5, y: 0.75 }, { x: 0.75, y: 0.25 }, { x: 1, y: 0.05 }]
}

function markLevels(rows) {
  return markPoints().map(function(p) { return Math.round(p.y * (rows - 1)) })
}

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

// 20 by 14, front on. The bull reads by its long horns and nostrils, the
// bear by round ears notched underneath and cheeks wider than its ears: an
// outline running straight up into the ears reads as a cat.
// test/qml/render.qml draws the other candidates beside these.
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

// A row's remove × in retro, as tall as the symbol's capitals beside it.
var REMOVE_SPRITE = [
  "#...#",
  ".#.#.",
  "..#..",
  ".#.#.",
  "#...#"
]

// The header's speaker and camera, on cells 3 px apart in a 6 by 4 grid
// (`GridIcon`). "M" "L" "A" (centre, radius, from and to degrees) "Z" build
// a path; "fill", "stroke" and "hollow" (even-odd, for the lens's hole)
// paint it, and "dot" fills a circle.
var SOUND_CONE = [["M", 0.5, 3.5], ["L", 3.5, 3.5], ["L", 7.5, 0.5], ["L", 7.5, 10.5], ["L", 3.5, 7.5], ["L", 0.5, 7.5], ["Z"], ["fill"]]
var SOUND_ON = { columns: 6, rows: 4,
  path: SOUND_CONE.concat([["A", 7, 5.5, 3.8, -50, 50], ["stroke"], ["A", 7, 5.5, 7.4, -50, 50], ["stroke"]]) }
var SOUND_OFF = { columns: 6, rows: 4,
  path: SOUND_CONE.concat([["M", 10.5, 3.5], ["L", 14.5, 7.5], ["stroke"], ["M", 14.5, 3.5], ["L", 10.5, 7.5], ["stroke"]]) }
var CAMERA_BODY = [["M", 0.5, 3], ["L", 4.8, 3], ["L", 6.3, 0.5], ["L", 10.7, 0.5], ["L", 12.2, 3], ["L", 16.5, 3], ["L", 16.5, 10.5], ["L", 0.5, 10.5], ["Z"],
  ["M", 11.3, 6.6], ["A", 8.5, 6.6, 2.8, 0, 359.9], ["Z"], ["hollow"]]
var CAMERA = { columns: 6, rows: 4, path: CAMERA_BODY }
var CAMERA_LIT = { columns: 6, rows: 4, path: CAMERA_BODY.concat([["dot", 8.5, 6.6, 1.6]]) }

var UNIT_SIGNS = {
  pct: { columns: 4, rows: 4,
    path: [["dot", 3, 3, 2.1], ["dot", 9.5, 8.5, 2.1], ["M", 10.5, 0.8], ["L", 2, 10.7], ["stroke"]] },
  abs: { columns: 4, rows: 4,
    path: [["M", 6.25, 0.8], ["L", 6.25, 7.2], ["stroke"], ["M", 2.6, 4], ["L", 9.9, 4], ["stroke"],
      ["M", 2.6, 10.4], ["L", 9.9, 10.4], ["stroke"]] },
  open: { columns: 4, rows: 4,
    path: [["A", 6.25, 4.6, 3.3, 180, 360], ["L", 9.55, 7.4], ["L", 11.4, 9.1], ["L", 1.1, 9.1], ["L", 2.95, 7.4], ["Z"], ["fill"],
      ["dot", 6.25, 10.3, 1.3], ["dot", 6.25, 1.1, 0.9]] }
}

function iconCell(fontScale) {
  return Math.max(3, Math.round(3 * fontScale))
}

// The bull's eyes shut to slits a row lower. The bear's one-cell eyes have
// no half-shut shape: at half the lid covers them; shut, each opens as a
// two-cell slit at eye level, widened outward: inward it crowds the nose,
// and a row lower it frowns.
var BULL_HALF = BULL_SPRITE.slice()
BULL_HALF[6] = "...##############..."
var BULL_SHUT = BULL_HALF.slice()
BULL_SHUT[7] = ".....#..####..#....."
var BEAR_HALF = BEAR_SPRITE.slice()
BEAR_HALF[6] = ".##################."
var BEAR_SHUT = BEAR_SPRITE.slice()
BEAR_SHUT[6] = ".####..######..####."

// At the sprite's cell size, it fits the gap before the header's words.
var SLEEP_Z = [
  "###",
  "..#",
  ".#.",
  "#..",
  "###"
]

function spritePixels(rows) {
  var out = []
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      if (rows[y].charAt(x) === "#") out.push({ x: x, y: y })
    }
  }
  return out
}

// Fidget's pricked horns and ears, a row higher than the sprite's: its top
// four rows, in place of the sprite's own.
var BULL_PRICKED = [
  "#..................#",
  "##................##",
  ".###............###.",
  "...##..........##..."
]
var BEAR_PRICKED = [
  "..###..........###..",
  ".#####........#####.",
  ".#####........#####.",
  ".##################."
]

// Fidget, the header animal's loop: how long each step holds, in ms, and
// what it does then. It sits still, pricks its horns or ears twice, then
// blinks: 2.4 s a loop, the animal drawn anew 5 times.
var FIDGET = [
  { ms: 1500 },
  { ms: 200, pricked: true },
  { ms: 150 },
  { ms: 150, pricked: true },
  { ms: 150, blink: true },
  { ms: 250 }
]

function spriteFor(up, lids, pricked) {
  var open = up ? BULL_SPRITE : BEAR_SPRITE
  var half = up ? BULL_HALF : BEAR_HALF
  var shut = up ? BULL_SHUT : BEAR_SHUT
  var rows = lids === 2 ? shut : lids === 1 ? half : open
  if (pricked) rows = (up ? BULL_PRICKED : BEAR_PRICKED).concat(rows.slice(4))
  return spritePixels(rows)
}
