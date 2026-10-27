// Inspect the required font's own cmap through fontconfig, with no fallback
// rendering. Discover characters from literals so a new label joins the check.
import {readdirSync,readFileSync} from 'node:fs'
import {join} from 'node:path'
const root = join(import.meta.dir,'..')
const run = args => {
  const r = Bun.spawnSync(args,{stdout:'pipe',stderr:'pipe'})
  if (r.exitCode) throw new Error(args[0]+': '+r.stderr)
  return r.stdout.toString().trim()
}
const file = run(['fc-match','--format','%{file}','JetBrainsMono Nerd Font'])
const family = run(['fc-query','--format','%{family}',file])
if (!family.split(',').includes('JetBrainsMono Nerd Font')) throw new Error('required JetBrainsMono Nerd Font is absent')
const ranges = run(['fc-query','--format','%{charset}',file]).split(/\s+/).map(r => r.split('-').map(n=>parseInt(n,16)))
const chars = new Map()
// QML and the rule files use single/double quoted literals. Skip comments
// before reading literals; decode escapes, so an escaped glyph is checked too.
for (const name of readdirSync(root).filter(n=>/\.(qml|js)$/.test(n))) {
  const source = readFileSync(join(root,name),'utf8')
  const tokens = source.match(/\/\/[^\n]*|\/\*[\s\S]*?\*\/|"(?:\\[\s\S]|[^"\\])*"|'(?:\\[\s\S]|[^'\\])*'/g) || []
  for (const token of tokens.filter(t=>t[0] !== '/')) {
    const literal = token.slice(1,-1).replace(/\\u\{([\da-f]+)\}|\\u([\da-f]{4})|\\x([\da-f]{2})|\\([\s\S])/gi,
      (_,long,short,hex,escaped) => long || short || hex ? String.fromCodePoint(parseInt(long||short||hex,16)) : ({n:'\n',t:'\t',r:'\r'}[escaped]||escaped))
    for (const c of literal) if (c.codePointAt(0)>=32) chars.set(c,name)
  }
}
const missing = [...chars].filter(([c])=>!ranges.some(([a,b=a])=>c.codePointAt(0)>=a && c.codePointAt(0)<=b))
if (missing.length) {
  for (const [c,name] of missing) console.error(`FAIL required font lacks ${c} U+${c.codePointAt(0).toString(16).toUpperCase()} in ${name}`)
  process.exit(1)
}
console.log(`PASS required font covers ${chars.size} characters in product literals`)
