.pragma library
// Which colours are up and down, how much quieter secondary text is, and how
// strongly a chart's wash lies over the ground. Every colour comes from the
// theme, but Stonks' own pair for a theme without a usable one (`ownPair`).
// Colours are { r, g, b } in 0..1, as a QML color is; one made here is a
// "#rrggbb" string.

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
// two blues, two greys, or a grey beside a red. Hue alone (OKLab's ΔH), since a
// darker shade of a hue is also less saturated: a bright and a dark green are
// 0.111 apart in a and b but 0.001 in hue.
var PAIR_APART = 0.06

// `green` is colors.toml's "#rrggbb", or ""; `red` the shell's urgent.
function paired(green, red) {
  var g = hexColor(green)
  if (!g) return false
  var p = oklab(g), q = oklab(red)
  var da = p.a - q.a, db = p.b - q.b
  var dc = Math.sqrt(p.a * p.a + p.b * p.b) - Math.sqrt(q.a * q.a + q.b * q.b)
  return Math.sqrt(Math.max(0, da * da + db * db - dc * dc)) >= PAIR_APART
}

// A theme's own green or red fainter than this on a surface's ground is not
// clear enough to read there.
var OWN_FLOOR = 3

// Stonks' own up and down: a green and a red by hue, as near the ground as
// reads at OWN_TARGET, at OWN_CHROMA where sRGB allows, else down to
// HUE_CHROMA, the least that still says its hue. A fixed pair, such as
// GitHub's, looks foreign in the themes that need one: a deep crimson bear on
// Catppuccin Latte's pastels.
var OWN_HUES = { up: 145, down: 25 }
var OWN_CHROMA = 0.16
var HUE_CHROMA = 0.07
var OWN_TARGET = { light: 4.5, dark: 6 }

// White reads more strongly on it than black.
function darkGround(ground) {
  return contrast({ r: 1, g: 1, b: 1 }, ground) > contrast({ r: 0, g: 0, b: 0 }, ground)
}

// Null outside sRGB's gamut, unless `clipped`.
function fromOklch(L, C, hue, clipped) {
  var a = C * Math.cos(hue * Math.PI / 180), b = C * Math.sin(hue * Math.PI / 180)
  var l = Math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
  var m = Math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
  var s = Math.pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
  var lin = [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
  for (var i = 0; i < 3; i++) if (!clipped && (lin[i] < -1e-4 || lin[i] > 1 + 1e-4)) return null
  var encode = function(v) {
    v = Math.max(0, Math.min(1, v))
    return v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055
  }
  return { r: encode(lin[0]), g: encode(lin[1]), b: encode(lin[2]) }
}

// On the side of the ground with more room. Where `chroma` leaves sRGB at that
// lightness, it is lowered as little as it must, down to `least`.
function readingColor(hue, chroma, least, target, ground) {
  var lighter = darkGround(ground)
  var from = oklabLightness(ground), to = lighter ? 1 : 0
  // Judged as written, "#rrggbb", which rounds each channel.
  var at = function(c) {
    var written = function(L) { return hexOf(fromOklch(L, c, hue, true)) }
    var reads = function(L) { return contrast(hexColor(written(L)), ground) >= target }
    // In sRGB, and keeping its chroma once rounded: near black a green rounds
    // to #000000, which reads but says no hue.
    var fits = function(L) {
      if (fromOklch(L, c, hue) === null) return false
      var o = oklab(hexColor(written(L)))
      return Math.sqrt(o.a * o.a + o.b * o.b) >= c * 0.9
    }
    // Contrast crosses the target once away from the ground, so halving finds
    // the nearest lightness that reads, where a walk in steps can pass over it.
    if (!reads(to)) return null
    var lo = from, hi = to
    for (var i = 0; i < 30; i++) {
      var mid = (lo + hi) / 2
      if (reads(mid)) hi = mid
      else lo = mid
    }
    if (fits(hi)) return written(hi)
    // Out of sRGB there, as a deep colour can be: the first lightness on that
    // fits.
    for (var step = 1; step <= 100; step++) {
      var L = hi + (to - hi) * step / 100
      if (fits(L)) return written(L)
    }
    return null
  }
  // Less chroma only widens what fits sRGB, so halving finds the most that
  // reads, where stepping down can pass over it.
  var best = at(chroma)
  if (best !== null) return best
  best = at(least)
  if (best === null) return null
  var lo = least, hi = chroma
  for (var n = 0; n < 6; n++) {
    var mid = (lo + hi) / 2
    var found = at(mid)
    if (found !== null) {
      best = found
      lo = mid
    } else hi = mid
  }
  return best
}

// It keeps its hue down to OWN_FLOOR before it greys: a red on a red bar must,
// to stay red.
function ownColor(hue, ground) {
  var dark = darkGround(ground)
  var target = dark ? OWN_TARGET.dark : OWN_TARGET.light
  return readingColor(hue, OWN_CHROMA, HUE_CHROMA, target, ground)
    || readingColor(hue, OWN_CHROMA, HUE_CHROMA, OWN_FLOOR, ground)
    || readingColor(hue, OWN_CHROMA, 0, target, ground)
    || hexOf(dark ? { r: 1, g: 1, b: 1 } : { r: 0, g: 0, b: 0 })
}

// Made once: the search can take several milliseconds, and every surface asks
// for up and down apart, on every theme switch.
var ownPairs = {}
function ownPair(ground) {
  var key = hexOf(ground)
  if (!ownPairs[key]) ownPairs[key] = { up: ownColor(OWN_HUES.up, ground), down: ownColor(OWN_HUES.down, ground) }
  return ownPairs[key]
}

// Up is the theme's green, as Omarchy colours success in every app it themes,
// and down its red. Each surface picks for its own ground.
function trend(green, red, ground) {
  var faintest = function(up, down) { return Math.min(contrast(up, ground), contrast(down, ground)) }
  if (paired(green, red) && faintest(hexColor(green), red) >= OWN_FLOOR) return { up: green, down: red }
  return ownPair(ground)
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

// Mixed toward the ground, so it is quieter on a light theme as on a dark one,
// but never under `floor` contrast: dim keeps body text's 4.5:1, dimmer 3:1.
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

// At one alpha a dark red adds far less light than a light blue, so a down
// day's wash would look half as present as an up day's. Each side's alpha is
// the one at which its colour adds the lightness (OKLab's L) the up colour
// adds at the chart's alpha.

// Either way, mixed channel by channel in sRGB, as a canvas composites.
function addedLightness(color, ground, alpha) {
  return Math.abs(oklabLightness(mixed(ground, color, alpha)) - oklabLightness(ground))
}

// Never more than half `ink`, the alpha of the line or cap above it, so those
// stay the most important thing: a pale up colour over Kanagawa's dark red
// would take the red's stems to solid ink.
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
