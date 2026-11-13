.pragma library
// A text field's undo steps, as Omarchy's own field (Qt's TextInput) groups
// them (QQuickTextInputPrivate::addCommand and internalUndo), for `Field`,
// whose Qt TextEdit groups them otherwise.
//
// A step is a run of one kind of edit: typing, Backspace or Delete. A move of
// the cursor or the selection, an undo, a redo, or a paste ends the run, and
// a paste is a step of its own. An edit that takes a selection, or more than
// one character with none (Ctrl+Backspace), starts a step that the next run
// of any kind joins. Undo puts back the text, the cursor and the selection
// from before the step.

// What `now` is to `old`, from the selection (`start`, `end`) and the cursor
// before it and the cursor after (`after`): "selection", a selection taken,
// maybe with text in its place; "insert", text put in at the cursor; "back"
// and "del", the character before or after the cursor taken; or "other".
function editKind(old, now, start, end, cursor, after) {
  if (end > start) return "selection"
  var grown = now.length - old.length
  if (grown > 0 && now.slice(0, cursor) === old.slice(0, cursor) && now.slice(cursor + grown) === old.slice(cursor)) return "insert"
  if (grown === -1 && after === cursor - 1 && now === old.slice(0, cursor - 1) + old.slice(cursor)) return "back"
  if (grown === -1 && after === cursor && now === old.slice(0, cursor) + old.slice(cursor + 1)) return "del"
  return "other"
}

// Whether an edit of `kind` joins the step `last` started or ran on, when
// nothing has ended it: a run of one kind, or any run after a selection
// taken. "" is a run nothing can join.
function joins(kind, last) {
  if (kind !== "insert" && kind !== "back" && kind !== "del") return false
  return last === kind || last === "open"
}

// The run an edit of `kind` leaves for the next to join.
function runAfter(kind) {
  return kind === "insert" || kind === "back" || kind === "del" ? kind : "open"
}
