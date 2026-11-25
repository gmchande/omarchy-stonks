.pragma library

// Qt's letter key codes are their capitals' character codes.
var KEY_A = "A".charCodeAt(0)
var KEY_Z = "Z".charCodeAt(0)
var SHIFT = 0x02000000
var KEYPAD = 0x20000000

// Nothing held with Ctrl, Alt or Super: Qt gives Alt+/ the text "/", which
// would act as / alone. AltGr, which some layouts type [ and ] with, isn't
// Qt's Alt.
function typed(event) {
  if (event.modifiers & ~(SHIFT | KEYPAD)) return ""
  if (event.key < KEY_A || event.key > KEY_Z) return event.text
  var letter = String.fromCharCode(event.key)
  return event.modifiers & SHIFT ? letter : letter.toLowerCase()
}
