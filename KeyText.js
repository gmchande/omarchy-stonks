.pragma library

// Qt's letter key codes are their capitals' character codes.
var KEY_A = "A".charCodeAt(0)
var KEY_Z = "Z".charCodeAt(0)
var SHIFT = 0x02000000
var CTRL = 0x04000000
var ALT = 0x08000000
var META = 0x10000000
var KEYPAD = 0x20000000

// A letter says nothing held with anything but Shift. Any other key says
// nothing held with Ctrl, Alt or Super: Qt gives Alt+/ the text "/", which
// would act as / alone. AltGr, which some layouts type [ and ] with, may
// come as Qt's group switch, so it types as itself.
function typed(event) {
  if (event.key < KEY_A || event.key > KEY_Z) return event.modifiers & (CTRL | ALT | META) ? "" : event.text
  if (event.modifiers & ~(SHIFT | KEYPAD)) return ""
  var letter = String.fromCharCode(event.key)
  return event.modifiers & SHIFT ? letter : letter.toLowerCase()
}
