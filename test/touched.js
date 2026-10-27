// Which checks a diff can reach, for test/touched.sh, which runs them. A
// check is a file a step of test/all.sh or test/review.sh names, or a
// journey in test/tophat/journeys/. A check is left out only when nothing it
// runs names a changed file; when in doubt it runs.
//
// - A harness (test/qml/NAME.sh) reaches what it names, then what those
//   name, and so on: its own .qml, lib.sh, the plugin's types and rule
//   files. QML and the rule files load one another only by name: a type's
//   name, a rule file's name in an import, a file's name in a Loader. A
//   file read through its folder (sounds/, data-files/, bin/) is reached
//   by the folder's name. Whole-line comments name nothing.
// - A journey reaches what it names and what the shell loads of the
//   plugin: manifest.json and what that names, on.
// - Every other check (unit tests, boundaries, lint, the glyphs, and such)
//   reads files it doesn't name, so it runs on every diff. They take
//   seconds.
// - A change to the runners themselves (queue.sh and what it sources,
//   all.sh, review.sh, or this pair) reaches everything.
//
// A check that comes to read a file by a name it builds must name the file
// or its folder somewhere, or this misses it.
//
//   bun test/touched.js BASE     the picks for this checkout's diff from its
//                                merge-base with BASE, edits and untracked
//                                files included: one line per check,
//                                "pick|leave TAB FILE TAB RUNNER TAB WHY"
//   bun test/touched.js self-check   the rules on a made-up checkout
import {existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync} from 'node:fs'
import {basename, dirname, join} from 'node:path'
import {tmpdir} from 'node:os'

const git = (root, ...args) => {
  const r = Bun.spawnSync(['git', '-C', root, ...args], {stdout: 'pipe', stderr: 'pipe'})
  if (r.exitCode) throw new Error(`git ${args.join(' ')}: ${r.stderr}`)
  return r.stdout.toString()
}
const lines = text => text.split('\n').filter(Boolean)

const runners = {'test/all.sh': 'all', 'test/review.sh': 'review'}
const everything = ['test/queue.sh', 'test/scratch.sh', 'test/all.sh', 'test/review.sh', 'test/touched.sh', 'test/touched.js']
const code = /\.(qml|js|mjs|sh|py|lua)$/

// names FILE: the words that reach FILE when a check names them. A QML
// type is named by its file's name, which starts with a capital; any other
// file by its whole name, and data through its folder too, every folder
// but test/ itself.
function names(file) {
  const base = basename(file)
  if (/^[A-Z].*\.qml$/.test(base)) return [base.slice(0, -4)]
  if (code.test(file) || /\.(qml|md)$/.test(file)) return [base]
  return [base, ...dirname(file).split('/').filter(d => d !== '.' && d !== 'test')]
}

// words FILE: what FILE names, its whole-line comments left out. Only code
// loads what it names: a script, a QML page or a rule file, or a script with
// no extension (the fake curl). Data names nothing, the manifest included:
// only the shell loads its entry points, and only a journey runs the shell.
function words(root, file) {
  if (!(code.test(file) || !basename(file).includes('.')) || !existsSync(join(root, file))) return new Set()
  const buffer = readFileSync(join(root, file))
  if (buffer.subarray(0, 8000).includes(0)) return new Set()
  const comment = /\.(qml|js|mjs)$/.test(file) ? /^\s*(\/\/|\/\*)/ : /\.lua$/.test(file) ? /^\s*--/ : /^\s*#/
  const found = new Set()
  for (const line of buffer.toString().split('\n')) {
    if (comment.test(line)) continue
    for (const word of line.match(/[\w.-]+/g) || []) {
      found.add(word)
      found.add(word.replace(/\.+$/, ''))
      for (const part of word.split('.')) found.add(part)
    }
  }
  return found
}

// pick ROOT BASE: each check's verdict for the diff of ROOT from its
// merge-base with BASE.
function pick(root, base) {
  const since = git(root, 'merge-base', base, 'HEAD').trim()
  const changed = [...new Set([
    ...lines(git(root, 'diff', '--name-only', '--no-renames', since)),
    ...lines(git(root, 'ls-files', '--others', '--exclude-standard')),
  ])]
  const files = [...new Set([...lines(git(root, 'ls-files', '--cached', '--others', '--exclude-standard')), ...changed])]
  const byName = new Map()
  for (const file of files) for (const name of names(file)) byName.set(name, [...(byName.get(name) || []), file])
  const scanned = new Map()
  const reach = (seeds, stop = new Set()) => {
    const seen = new Set(seeds), queue = [...seeds]
    while (queue.length) {
      const file = queue.pop()
      // The runners name every check, and a change to them reaches
      // everything anyway: what they name reaches no check through them.
      if (!scanned.has(file)) scanned.set(file, everything.includes(file) ? new Set() : words(root, file))
      if (stop.has(file)) continue
      for (const word of scanned.get(file)) for (const next of byName.get(word) || []) {
        if (!seen.has(next)) { seen.add(next); queue.push(next) }
      }
    }
    return seen
  }

  // The checks: every file a runner's step names, by the runner that runs it.
  const checks = new Map()
  for (const [runner, kind] of Object.entries(runners)) {
    if (!existsSync(join(root, runner))) continue
    for (const line of readFileSync(join(root, runner), 'utf8').split('\n')) {
      if (!/^\s*(start|run)\s/.test(line)) continue
      for (const word of line.match(/[^\s"']+/g)) {
        const file = files.find(f => word === f || word.endsWith('/' + f))
        if (file && file.includes('/') && !checks.has(file)) checks.set(file, kind)
      }
    }
  }
  for (const file of files) {
    if (/^test\/tophat\/journeys\/[^/]+\.sh$/.test(file) && !file.endsWith('/lib.sh') && !checks.has(file)) checks.set(file, 'journey')
  }

  // What the shell loads of the plugin, which only a journey runs: the
  // manifest's entry points, or every file when the manifest can't be read.
  let shell
  try {
    shell = ['manifest.json', ...Object.values(JSON.parse(readFileSync(join(root, 'manifest.json'), 'utf8')).entryPoints)]
  } catch {
    shell = files
  }

  // What a runner runs itself, beside its checks: the scripts its own steps
  // call (test/review.sh's render diff), and what those name. A change
  // there reaches every check of that runner.
  const helped = new Map()
  for (const runner of Object.keys(runners)) {
    const named = [...words(root, runner)].flatMap(word => byName.get(word) || [])
    const helpers = named.filter(f => !checks.has(f) && !everything.includes(f))
    const reached = reach(helpers, new Set([...checks.keys(), ...everything]))
    helped.set(runners[runner], changed.filter(f => reached.has(f) && !checks.has(f)))
  }

  const runnerChanged = changed.filter(f => everything.includes(f))
  const picks = []
  for (const [check, runner] of checks) {
    const journey = check.startsWith('test/tophat/journeys/')
    const helper = helped.get(runner) || []
    let verdict = 'pick', why
    if (runnerChanged.length) why = `the runners changed (${runnerChanged.join(', ')})`
    else if (helper.length) why = `its runner's own steps reach ${helper.slice(0, 3).join(', ')}${helper.length > 3 ? ` and ${helper.length - 3} more` : ''}`
    else if (!journey && !/^test\/qml\/[^/]+\.sh$/.test(check)) why = 'reads files it does not name, so it runs on every diff'
    else {
      const reached = reach(journey ? [check, ...shell] : [check])
      const hit = changed.filter(f => reached.has(f))
      if (hit.length) why = `reaches ${hit.slice(0, 3).join(', ')}${hit.length > 3 ? ` and ${hit.length - 3} more` : ''}`
      else { verdict = 'leave'; why = `reaches none of the ${changed.length} changed files` }
    }
    picks.push([verdict, check, runner, why])
  }
  return {since, changed, picks}
}

function selfCheck() {
  const root = mkdtempSync(join(tmpdir(), 'touched-'))
  let failures = 0
  try {
    const put = (file, text) => { mkdirSync(dirname(join(root, file)), {recursive: true}); writeFileSync(join(root, file), text) }
    put('manifest.json', '{"entryPoints": {"service": "Main.qml"}}\n')
    put('Main.qml', 'Item {\n  Child {}\n}\n')
    put('Child.qml', 'import "Rules.js" as Rules\nItem {\n  property string bell: "sounds/" + "bell.wav"\n}\n')
    put('Rules.js', '.pragma library\nfunction f() { return 1 }\n')
    put('Lone.qml', 'Item {}\n')
    put('NOTES.md', 'Child, Lone and Rules.js, in words.\n')
    put('sounds/bell.wav', Buffer.from([82, 73, 70, 70, 0, 0, 0, 0]))
    put('test/all.sh', 'source "$(dirname "${BASH_SOURCE[0]}")/queue.sh"\nstart "x harness" bash test/qml/x.sh\nstart "y harness" bash test/qml/y.sh\nrun "quick check" bash test/quick.sh\nverdict\n')
    put('test/review.sh', 'source "$(dirname "${BASH_SOURCE[0]}")/queue.sh"\nrender_diff() { bash test/diff.sh; }\nstart "renders" bash test/qml/r.sh\nrun --with test/qml/r.sh "render diff" render_diff\nverdict\n')
    put('test/diff.sh', 'echo diff\n')
    put('test/queue.sh', 'verdict() { :; }\n')
    put('test/quick.sh', 'echo ok\n')
    put('test/qml/lib.sh', 'PATH="$here/bin:$PATH"\ncp "$plugin"/*.qml "$plugin/manifest.json" "$root/plugin/"\nusage() { echo "every harness: test/all.sh"; }\n')
    put('test/qml/bin/curl', '#!/bin/sh\necho answer\n')
    put('test/qml/x.sh', 'source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"\nplugin_tree x.qml\n')
    put('test/qml/x.qml', 'Stonks.Main {\n  id: y\n}\n')
    put('test/qml/y.sh', 'source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"\nplugin_tree y.qml\nfor file in "$here"/../data/*.json; do load "$file"; done\n')
    put('test/qml/y.qml', '// Child is not loaded here, only named in a comment.\nStonks.Lone {}\n')
    put('test/qml/r.sh', 'source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"\nplugin_tree r.qml\n')
    put('test/qml/r.qml', 'Stonks.Child {}\n')
    put('test/data/1.json', '{}\n')
    put('test/tophat/journeys/lib.sh', 'start_session\n')
    put('test/tophat/journeys/j.sh', 'source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"\n')
    git(root, 'init', '-q')
    git(root, 'add', '-A')
    git(root, '-c', 'user.name=check', '-c', 'user.email=check@example.com', 'commit', '-qm', 'base')
    const cases = [
      ['a rule file the plugin imports', 'Rules.js', ['test/qml/x.sh', 'test/qml/r.sh', 'test/tophat/journeys/j.sh', 'test/quick.sh'], ['test/qml/y.sh']],
      ['a type only one harness loads', 'Lone.qml', ['test/qml/y.sh', 'test/quick.sh'], ['test/qml/x.sh', 'test/qml/r.sh', 'test/tophat/journeys/j.sh']],
      ['a type a harness names only in a comment', 'Child.qml', ['test/qml/x.sh', 'test/qml/r.sh', 'test/tophat/journeys/j.sh'], ['test/qml/y.sh']],
      ['a sound read through its folder', 'sounds/bell.wav', ['test/qml/x.sh', 'test/qml/r.sh', 'test/tophat/journeys/j.sh'], ['test/qml/y.sh']],
      ['a data file read through its folder', 'test/data/1.json', ['test/qml/y.sh'], ['test/qml/x.sh', 'test/qml/r.sh', 'test/tophat/journeys/j.sh']],
      ['the fake curl in bin/', 'test/qml/bin/curl', ['test/qml/x.sh', 'test/qml/y.sh', 'test/qml/r.sh'], []],
      ['a harness\'s own page', 'test/qml/y.qml', ['test/qml/y.sh'], ['test/qml/x.sh', 'test/qml/r.sh', 'test/tophat/journeys/j.sh']],
      ['a note nothing reads', 'NOTES.md', ['test/quick.sh'], ['test/qml/x.sh', 'test/qml/y.sh', 'test/qml/r.sh', 'test/tophat/journeys/j.sh']],
      ['a new data file, not yet added to git', 'test/data/2.json', ['test/qml/y.sh'], ['test/qml/x.sh', 'test/qml/r.sh']],
      ['the runners\' queue', 'test/queue.sh', ['test/qml/x.sh', 'test/qml/y.sh', 'test/qml/r.sh', 'test/tophat/journeys/j.sh', 'test/quick.sh'], []],
      ['a script a runner runs itself', 'test/diff.sh', ['test/qml/r.sh'], ['test/qml/x.sh', 'test/qml/y.sh']],
      ['a deleted type', '-Lone.qml', ['test/qml/y.sh'], ['test/qml/x.sh']],
    ]
    for (const [label, change, want, notWant] of cases) {
      if (change.startsWith('-')) rmSync(join(root, change.slice(1)))
      else if (existsSync(join(root, change))) writeFileSync(join(root, change), readFileSync(join(root, change), 'utf8') + '\n// changed\n')
      else put(change, 'Item {}\n')
      const picked = pick(root, 'HEAD').picks.filter(p => p[0] === 'pick').map(p => p[1])
      const missed = want.filter(c => !picked.includes(c)), extra = notWant.filter(c => picked.includes(c))
      const ok = !missed.length && !extra.length
      if (!ok) failures++
      console.log(`${ok ? 'PASS' : 'FAIL'} ${label} (${change.replace(/^-/, 'deleted ')})${missed.length ? `: left out ${missed.join(', ')}` : ''}${extra.length ? `: ran ${extra.join(', ')}` : ''}`)
      git(root, 'checkout', '-q', '--', '.')
      git(root, 'clean', '-qfd')
    }
  } finally {
    rmSync(root, {recursive: true, force: true})
  }
  process.exit(failures ? 1 : 0)
}

const [arg] = process.argv.slice(2)
if (!arg) { console.error('usage: bun test/touched.js BASE | self-check'); process.exit(2) }
if (arg === 'self-check') selfCheck()
const root = git(process.cwd(), 'rev-parse', '--show-toplevel').trim()
const {since, changed, picks} = pick(root, arg)
console.log(['since', since, changed.length].join('\t'))
for (const p of picks) console.log(p.join('\t'))
