// Loads the plugin's rule files under bun as QML loads them: a file's
// `.import "X.js" as X` lines name the files it reads, which load first and
// are handed in under that name; each loads once, as `.pragma library` has
// QML load it. Returns the file's top-level names.
import { readFileSync } from "node:fs"
import { join } from "node:path"

const root = join(import.meta.dir, "..")
const loaded = {}

export function load(file) {
  if (loaded[file]) return loaded[file]
  const source = readFileSync(join(root, file), "utf8")
  const imports = [...source.matchAll(/^\.import "(\w+\.js)" as (\w+)\s*$/gm)]
  const body = source.replace(/^\.(import|pragma) .*$/gm, "")
  const names = [...body.matchAll(/^(?:function|var) (\w+)/gm)].map(m => m[1])
  const qualifiers = imports.map(m => m[2])
  loaded[file] = new Function(...qualifiers, body + `\nreturn { ${names.join(", ")} }`)(...imports.map(m => load(m[1])))
  return loaded[file]
}

// Several rule files' names under one object, as the tests read them. A
// name two of them define belongs to neither here: reading it throws, so a
// test asks the file it means, as `load("Share.js").clockOf`.
export function rules(files) {
  const all = {}, from = {}
  for (const file of files) {
    for (const [name, value] of Object.entries(load(file + ".js"))) {
      if (name in from) {
        const first = from[name]
        Object.defineProperty(all, name, { configurable: true, get() {
          throw new Error(`${name} is in ${first}.js and ${file}.js: read it from the one you mean, as load("${file}.js").${name}`)
        } })
      } else {
        all[name] = value
        from[name] = file
      }
    }
  }
  return all
}
