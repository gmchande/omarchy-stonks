// How the theme's colours are put to work: which colours are up and down,
// how much quieter secondary text is, and how strongly a chart's wash lies
// over the ground. Every colour comes in from the theme, except Stonks' own
// up and down for a theme with no green and red of its own (`OWN_PAIRS`).
// Colours are { r, g, b } in 0..1, as a QML color is; a colour made here is
// a "#rrggbb" string, which a QML color property takes.

// A theme's colour by its first key present, read the way the shell reads
// colors.toml (`Color.loadColors`): `green`, else the terminal's `color2`.
function themeColor(toml, keys) {
  for (var k = 0; k < keys.length; k++) {
    var pattern = new RegExp("^\\s*" + keys[k] + "\\s*=\\s*[\"']?(#[0-9A-Fa-f]{6})", "m")
    var match = pattern.exec(String(toml || ""))
    if (match) return match[1]
  }
  return ""
}

function hexColor(text) {
  var m = /^#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})$/.exec(String(text || ""))
  return m ? { r: parseInt(m[1], 16) / 255, g: parseInt(m[2], 16) / 255, b: parseInt(m[3], 16) / 255 } : null
}

function hexOf(c) {
  var two = function(v) {
    var n = Math.round(Math.max(0, Math.min(1, v)) * 255)
    return (n < 16 ? "0" : "") + n.toString(16)
  }
  return "#" + two(c.r) + two(c.g) + two(c.b)
}

function linear(v) {
  return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
}

function oklab(c) {
  var r = linear(c.r), g = linear(c.g), b = linear(c.b)
  var l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
  var m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
  var s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
  return {
    L: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
    a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
    b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
  }
}

function oklabLightness(c) {
  return oklab(c).L
}

// Closer than this in hue, a theme's green and red are no pair: two greens,
// two blues, two greys, or a grey beside a red. Lightness and chroma are
// both left out (OKLab's ΔH), as a darker shade of one hue is also less
// saturated: a bright and a dark green are 0.111 apart in a and b but
// 0.001 in hue. Of the installed themes, the nearest without a pair is
// Hackerman's two greens at 0.025 and the nearest with one Miasma's green
// and brown at 0.064; the cut sits between them. Lumon, Solitude,
// Vantablack, and White are at 0.002 or less, and every other installed
// theme at 0.106 or more.
var PAIR_APART = 0.06

// Whether the theme's green (a "#rrggbb" from colors.toml, or "") and red
// (the shell's urgent) are a real pair.
function paired(green, red) {
  var g = hexColor(green)
  if (!g) return false
  var p = oklab(g), q = oklab(red)
  var da = p.a - q.a, db = p.b - q.b
  var dc = Math.sqrt(p.a * p.a + p.b * p.b) - Math.sqrt(q.a * q.a + q.b * q.b)
  return Math.sqrt(Math.max(0, da * da + db * db - dc * dc)) >= PAIR_APART
}

// Fainter than this against a surface's ground, a theme's own green or red
// is not clear enough to read there: Miasma's brown at 2.30:1 and Catppuccin
// Latte's green at 2.96:1 on their own backgrounds.
var OWN_FLOOR = 3

// Stonks' own up and down, for a theme without a pair or with one too faint
// to read: one pair for a dark ground and one for a light one. The dark is
// GitHub's dark-mode success and danger text colours; the light is Primer's
// green 6 and red 6, a step darker than GitHub's light text colours, which
// fall under 4.5:1 on tinted light grounds (Catppuccin Latte's at 4.49:1).
// Each reads at 4.5:1 or more on the ground it is picked for in every
// installed theme.
var OWN_PAIRS = [
  { up: "#3fb950", down: "#f85149" },
  { up: "#116329", down: "#a40e26" }
]

// Up and down on `ground`. Up is the theme's green, as Omarchy colours
// success in every app it themes, and down its red; never the accent, which
// means selected. Where the theme has no real pair, or the fainter of its
// two is under the floor on this ground, Stonks' own takes over: the pair
// whose fainter colour stands out more from this ground, so each surface
// picks for its own.
function trend(green, red, ground) {
  var faintest = function(up, down) { return Math.min(contrast(up, ground), contrast(down, ground)) }
  if (paired(green, red) && faintest(hexColor(green), red) >= OWN_FLOOR) return { up: green, down: red }
  var dark = OWN_PAIRS[0], light = OWN_PAIRS[1]
  return faintest(hexColor(dark.up), hexColor(dark.down)) >= faintest(hexColor(light.up), hexColor(light.down)) ? dark : light
}

// WCAG 2's contrast between two opaque colours.
function contrast(x, y) {
  var lum = function(c) { return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b) }
  var a = lum(x), b = lum(y)
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
}

function mixed(from, to, share) {
  return {
    r: from.r + (to.r - from.r) * share,
    g: from.g + (to.g - from.g) * share,
    b: from.b + (to.b - from.b) * share
  }
}

// Secondary text: the foreground mixed `share` of the way toward the ground
// it sits on, so it is quieter on a light theme as on a dark one, but never
// under `floor` contrast against that ground. Dim takes a third and keeps
// body text's 4.5:1; dimmer takes half and keeps 3:1.
var DIM = { share: 0.32, floor: 4.5 }
var DIMMER = { share: 0.5, floor: 3 }

function secondary(foreground, ground, level) {
  if (contrast(foreground, ground) <= level.floor) return hexOf(foreground)
  if (contrast(mixed(foreground, ground, level.share), ground) >= level.floor)
    return hexOf(mixed(foreground, ground, level.share))
  var lo = 0, hi = level.share
  for (var i = 0; i < 30; i++) {
    var mid = (lo + hi) / 2
    if (contrast(mixed(foreground, ground, mid), ground) >= level.floor) lo = mid
    else hi = mid
  }
  return hexOf(mixed(foreground, ground, lo))
}

function dim(foreground, ground) {
  return secondary(foreground, ground, DIM)
}

function dimmer(foreground, ground) {
  return secondary(foreground, ground, DIMMER)
}

// A wash is a colour at some alpha over the surface's ground. At one alpha a
// dark red adds far less light than a light blue, so a down day's wash would
// look half as present as an up day's. Each side's alpha is worked out from
// the theme instead: the alpha at which its colour adds the same lightness,
// OKLab's L, over the ground as the up colour does at the alpha the chart
// sets.

// The lightness `color` at `alpha` adds over `ground`, either way, mixed
// channel by channel in sRGB, as a canvas composites it.
function addedLightness(color, ground, alpha) {
  return Math.abs(oklabLightness(mixed(ground, color, alpha)) - oklabLightness(ground))
}

// The alpha at which `color` over `ground` adds the lightness `reference`
// adds at `alpha`: `alpha` itself for the reference. Never more than half
// `ink`, the alpha of the line or cap it sits under, so the line and the
// caps stay the most important thing: a pale up colour over a dark red
// (Kanagawa) would otherwise take the red's stems to solid ink.
function washAlpha(color, reference, ground, alpha, ink) {
  var cap = ink / 2
  var target = addedLightness(reference, ground, alpha)
  if (addedLightness(color, ground, cap) <= target) return cap
  var lo = 0
  var hi = cap
  for (var i = 0; i < 30; i++) {
    var mid = (lo + hi) / 2
    if (addedLightness(color, ground, mid) < target) lo = mid
    else hi = mid
  }
  return (lo + hi) / 2
}
