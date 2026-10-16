// Loads the plugin's rule files under bun as QML loads them: a file's
// `.import "X.js" as X` lines name the files it reads, which load first and
// are handed in under that name. Returns the file's top-level names.
import { readFileSync } from "node:fs"
import { join } from "node:path"

const root = join(import.meta.dir, "..")
const loaded = {}

export function load(file) {
  if (loaded[file]) return loaded[file]
  const source = readFileSync(join(root, file), "utf8")
  const imports = [...source.matchAll(/^\.import "(\w+\.js)" as (\w+)\s*$/gm)]
  const body = source.replace(/^\.import .*$/gm, "")
  const names = [...body.matchAll(/^(?:function|var) (\w+)/gm)].map(m => m[1])
  const qualifiers = imports.map(m => m[2])
  loaded[file] = new Function(...qualifiers, body + `\nreturn { ${names.join(", ")} }`)(...imports.map(m => load(m[1])))
  return loaded[file]
}
