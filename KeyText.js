.pragma library

// What a key press says as a command. A letter's is its key and Shift, never
// its text's case: Caps Lock sends "J" for j, and "j" for Shift+J, and J
// moves a row where j moves the selection. A letter held with Ctrl, Alt, or
// Meta says nothing. Any other key's is its text.

// Qt's codes for the letter keys are their capitals' character codes, and
// its Shift and keypad modifiers these bits.
var KEY_A = "A".charCodeAt(0)
var KEY_Z = "Z".charCodeAt(0)
var SHIFT = 0x02000000
var KEYPAD = 0x20000000

function typed(event) {
  if (event.key < KEY_A || event.key > KEY_Z) return event.text
  if (event.modifiers & ~(SHIFT | KEYPAD)) return ""
  var letter = String.fromCharCode(event.key)
  return event.modifiers & SHIFT ? letter : letter.toLowerCase()
}
