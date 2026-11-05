.pragma library
// How Stonks moves on the shell it runs in. Omarchy 4.5's shell times every
// animation through `Style.duration`, which is 0 while its animations are
// off, and eases on `Style.easeOut`; Omarchy 4.0's has neither, and there
// Stonks moves as 1.1.0 did, on its own durations and OutCubic.

// OutCubic as a cubic Bézier: exact, since its control points are a third
// and two thirds along at full height.
var OUT_CUBIC = [1 / 3, 1, 2 / 3, 1, 1, 1]

// `style` is the shell's Style, read in the caller's binding, so a binding
// follows the shell's switch.
function duration(style, ms) {
  return typeof style.duration === "function" ? style.duration(ms) : ms
}

function curve(style) {
  return style.easeOut || OUT_CUBIC
}
