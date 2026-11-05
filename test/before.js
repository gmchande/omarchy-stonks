// Before the change: a branch that changes what the product code does must
// change or add at least one test case or harness step that fails on the
// code before the change. Otherwise its tests can't tell the change from
// the code it replaces, as a fix's test that passes with the bug still in.
// The code before is the merge base with dev (origin/dev, or STONKS_BASE).
// It is checked out in a scratch tree with this checkout's test/ beside it,
// an uncommitted edit included, and the changed test files run there: the
// unit test files first, then the harnesses, until one changed case fails.
//
// A test case is a bun test(...) or it(...) in a *.test.js. A harness step
// is a check(...) in test/qml/NAME.qml with what drives it: the lines of
// its function since the check before, which drive every check that follows
// them with no code between. A changed line elsewhere, such as in a helper,
// belongs to no case. A comment or a blank line isn't a change, in the
// tests or in the product.
//
// A branch that changes no product code, or no test, has nothing to compare
// and passes. Exits 77 when no changed case failed and some had no saved
// answers to run on (test/fixtures-dir.sh).
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const root = join(import.meta.dir, "..")
const run = (args, options = {}) => {
  const r = Bun.spawnSync(args, { cwd: root, stdout: "pipe", stderr: "pipe", ...options })
  return { code: r.exitCode, out: r.stdout.toString(), err: r.stderr.toString() }
}
const git = (...args) => {
  const r = run(["git", ...args])
  if (r.code !== 0) throw new Error(`git ${args.join(" ")}: ${r.err.trim()}`)
  return r.out
}

const baseRef = process.env.STONKS_BASE || "origin/dev"
const baseName = baseRef.replace(/^origin\//, "")
if (run(["git", "rev-parse", "--verify", "--quiet", `${baseRef}^{commit}`]).code !== 0) {
  console.log(`FAILED before the change: there is no ${baseRef} to compare with. Fetch it, or name the branch this one starts from in STONKS_BASE.`)
  process.exit(1)
}
const base = git("merge-base", "HEAD", baseRef).trim()
const short = base.slice(0, 7)

// What changed since the base, in this checkout as it is: tracked files
// against the base, deleted ones too, and new files git doesn't ignore.
const touched = [
  ...git("diff", "--name-only", "-z", base).split("\0"),
  ...git("ls-files", "--others", "--exclude-standard", "-z").split("\0"),
].filter(path => path)
const changed = touched.filter(path => existsSync(join(root, path)))
// The product's files, outside test/ and the docs and pictures; its code
// changed when one differs from the base's with comments and blank lines
// set aside.
const product = touched.filter(path => !/^(test|\.github|media)\/|\.(md|png)$/.test(path))
const show = path => run(["git", "show", `${base}:${path}`]).out
const now = path => existsSync(join(root, path)) ? readFileSync(join(root, path), "utf8") : ""
// canon SOURCE: SOURCE's code alone: comments set aside and each run of
// space outside a string or a regular expression made one space, so
// comments, blank lines and indenting change nothing and a string's every
// character still counts.
function canon(source) {
  const { comments, literals } = scan(source)
  const marks = [...comments.map(([s, e]) => [s, e, false]), ...literals.map(([s, e]) => [s, e, true])]
    .sort((a, b) => a[0] - b[0])
  let out = "", pending = "", from = 0
  for (const [start, end, literal] of marks) {
    if (start < from) continue
    pending += source.slice(from, start)
    if (literal) { out += pending.replace(/\s+/g, " ") + source.slice(start, end); pending = "" }
    else pending += " "
    from = end
  }
  return (out + (pending + source.slice(from)).replace(/\s+/g, " ")).trim()
}
const code = (path, source) => /\.(qml|js)$/.test(path) ? canon(source) : source
const codeChanged = product.filter(path => code(path, show(path)) !== code(path, now(path)))
if (codeChanged.length === 0) {
  console.log(`no product code changed since ${baseName} (${short}), only tests, docs or comments: nothing to compare`)
  process.exit(0)
}

// What the branch adds to the product: the files the base hasn't, and the
// names in its code that no product file at the base has. A case that
// can't run on the code before counts as failing there only when the error
// names one of them.
const words = text => new Set(text.match(/[A-Za-z_$][\w$]{2,}/g) || [])
const isProduct = path => !/^(test|\.github|media)\/|\.(md|png)$/.test(path)
const baseNames = new Set()
for (const path of git("ls-tree", "-r", "--name-only", base).split("\n")) {
  if (isProduct(path) && /\.(qml|js)$/.test(path)) for (const w of words(canon(show(path)))) baseNames.add(w)
}
const addedFiles = product.filter(path => existsSync(join(root, path)) && run(["git", "cat-file", "-e", `${base}:${path}`]).code !== 0)
const addedNames = new Set(addedFiles.flatMap(path => {
  const file = path.split("/").pop()
  return [file, file.replace(/\.\w+$/, "")]
}))
for (const path of codeChanged) {
  if (/\.(qml|js)$/.test(path)) for (const w of words(canon(now(path)))) if (!baseNames.has(w)) addedNames.add(w)
}
const namesAdded = line => [...words(line)].some(w => addedNames.has(w)) || addedFiles.some(path => line.includes(path.split("/").pop()))

// The harnesses a runner starts, by name, each with every command a runner
// starts it with, since a harness such as layout.sh runs some of its steps
// under one command and the rest under another.
const starts = new Map()
for (const runner of ["test/all.sh", "test/review.sh"]) {
  for (const line of readFileSync(join(root, runner), "utf8").split("\n")) {
    const m = line.match(/^start "[^"]*" (.*\bbash test\/qml\/([\w-]+)\.sh\b.*)$/)
    if (m) starts.set(m[2], [...(starts.get(m[2]) || []), m[1]])
  }
}
const harnessOf = path => {
  const m = path.match(/^test\/qml\/([\w-]+)\.qml$/)
  return m && starts.has(m[1]) ? m[1] : null
}
const tests = changed.filter(path => /\.test\.js$/.test(path) || harnessOf(path))

// changedLines PATH: the lines of PATH that differ from the base's, by
// their number here. A hunk whose code is the same, as one that changes
// only comments or blank lines, changes nothing. A deletion with nothing
// added in its place marks the line now there.
// masked SOURCE: SOURCE's lines with every comment blanked out, read in
// the whole file, so a line inside a block comment is blank too.
function masked(source) {
  let out = "", from = 0
  for (const [start, end] of scan(source).comments) {
    out += source.slice(from, start) + source.slice(start, end).replace(/[^\n]/g, " ")
    from = end
  }
  return (out + source.slice(from)).split("\n")
}
const quiet = line => line.trim() === ""
function changedLines(path) {
  const lines = new Set()
  const text = readFileSync(join(root, path), "utf8")
  if (run(["git", "cat-file", "-e", `${base}:${path}`]).code !== 0) {
    text.split("\n").forEach((_, i) => lines.add(i + 1))
    return lines
  }
  const now = masked(text), before = masked(show(path))
  const hunks = git("diff", "-U0", "--no-color", "--no-ext-diff", base, "--", path).split(/^(?=@@ )/m).slice(1)
  for (const hunk of hunks) {
    const [, oldFrom, oldCount, from, count] = hunk.match(/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/).map(Number)
    const removed = before.slice(oldFrom - 1, oldFrom - 1 + (Number.isNaN(oldCount) ? 1 : oldCount))
    const added = now.slice(from - 1, from - 1 + (Number.isNaN(count) ? 1 : count))
    if (canon(added.join("\n")) === canon(removed.join("\n"))) continue
    added.forEach((l, i) => { if (!quiet(l)) lines.add(from + i) })
    if (removed.some(l => !quiet(l)) && added.every(quiet)) lines.add(added.length ? from : from + 1)
  }
  return lines
}

// scan SOURCE: each call's opening parenthesis with the name before it, and
// each function body, as line ranges. Strings, template literals, comments
// and regular expressions are skipped, so their brackets don't count.
function scan(source) {
  const lineAt = []
  let line = 1
  for (let i = 0; i <= source.length; i++) {
    lineAt.push(line)
    if (source[i] === "\n") line++
  }
  const calls = [], functions = [], comments = [], literals = [], stack = [], close = new Map(), opened = new Map()
  // last: the word or character before, which tells a regular expression
  // from a division; lastAt: where it ends.
  let last = "", lastAt = -1, i = 0
  const regexAfter = /^([(,=:[!&|?{};+\-*%<>~^]|return|typeof|case|in|of|delete|void|throw|new)?$/
  const wordAt = /[\w$]+/y, spaceParen = /\s*\(/y
  while (i < source.length) {
    const c = source[i], next = source[i + 1]
    if (c === "/" && (next === "/" || next === "*")) {
      const end = next === "/" ? source.indexOf("\n", i) : source.indexOf("*/", i + 2) + 2
      comments.push([i, end < 2 ? source.length : end])
      if (end < 2) break
      i = end
      continue
    }
    if (/\s/.test(c)) { i++; continue }
    if (c === "\"" || c === "'") {
      const start = i
      for (i++; i < source.length && source[i] !== c; i++) if (source[i] === "\\") i++
      last = "x"; lastAt = i++; literals.push([start, i]); continue
    }
    if (c === "/" && regexAfter.test(last)) {
      const start = i
      let inClass = false
      for (i++; i < source.length && (inClass || source[i] !== "/"); i++) {
        if (source[i] === "\\") i++
        else if (source[i] === "[") inClass = true
        else if (source[i] === "]") inClass = false
      }
      last = "x"; lastAt = i++; literals.push([start, i]); continue
    }
    if (c === "`" || (c === "}" && stack.at(-1)?.template)) {
      const start = i
      if (c === "}") close.set(stack.pop().at, i)
      for (i++; i < source.length && source[i] !== "`" && !(source[i] === "$" && source[i + 1] === "{"); i++) {
        if (source[i] === "\\") i++
      }
      if (source[i] === "$") { stack.push({ at: i + 1, template: true }); i += 2; last = "{" }
      else { last = "x"; lastAt = i++ }
      literals.push([start, i])
      continue
    }
    wordAt.lastIndex = i
    const word = wordAt.exec(source)
    if (word) { last = word[0]; i += last.length; lastAt = i - 1; continue }
    if (c === "(" || c === "[" || c === "{") {
      // What comes just before: enough for a name or a `function (...)`.
      const before = source.slice(Math.max(0, i - 200), i).trimEnd()
      const entry = { at: i, kind: c }
      if (c === "(") {
        const name = before.match(/(?:^|[^.\w$])((?:[\w$]+\.)*[\w$]+)$/)?.[1] || ""
        entry.name = /\bfunction\s+[\w$]+$/.test(before) ? "" : name
      }
      if (c === "{") {
        const paren = last === ")" ? opened.get(lastAt) : undefined
        // A function's body: after `function NAME(...)`, `(...) =>`, `x =>`,
        // or a QML signal handler's `onName:`.
        entry.fn = before.endsWith("=>") || /\bon[A-Z][\w$]*\s*:$/.test(before)
          || (paren !== undefined && /\bfunction(\s+[\w$]+)?\s*$/.test(source.slice(Math.max(0, paren - 200), paren)))
      }
      stack.push(entry)
    } else if ((c === ")" || c === "]" || c === "}") && stack.length) {
      const open = stack.pop()
      close.set(open.at, i)
      opened.set(i, open.at)
      if (open.kind === "(") calls.push({ name: open.name, open: open.at, end: i })
      if (open.fn) functions.push({ start: lineAt[open.at], end: lineAt[i] })
    }
    last = c
    lastAt = i++
  }
  // A call's extent runs on through calls chained onto it, as in
  // test.each(table)(name, fn).
  for (const call of calls) {
    let end = call.end
    for (;;) {
      spaceParen.lastIndex = end + 1
      const m = spaceParen.exec(source)
      if (!m || !close.has(end + m[0].length)) break
      end = close.get(end + m[0].length)
    }
    call.start = lineAt[call.open]
    call.endLine = lineAt[end]
  }
  return { calls, functions, comments, literals }
}

// cases PATH: the test cases, or the harness's steps, that changed lines
// of PATH belong to. Each is the checks it's judged by, as { start, end }
// lines: a test or a check alone when the line is inside it; a changed line
// between checks belongs to the checks that come next in its function, up
// to the next line of code after them.
function cases(path, harness) {
  const source = readFileSync(join(root, path), "utf8")
  const text = masked(source)
  const { calls, functions } = scan(source)
  const own = calls.filter(c => harness
    ? /^((harness|root)\.)?check$/.test(c.name)
    : /^(test|it)(\.\w+)?$/.test(c.name))
    .map(c => ({ start: c.start, end: c.endLine }))
    .sort((a, b) => a.start - b.start)
  const found = new Map()
  const add = checks => found.set(checks.map(c => c.start).join(","), checks)
  const within = (r, l) => r.start <= l && l <= r.end
  const narrowest = list => list.sort((a, b) => (a.end - a.start) - (b.end - b.start))[0]
  for (const l of changedLines(path)) {
    const inside = narrowest(own.filter(c => within(c, l)))
    if (inside) { add([inside]); continue }
    if (!harness) continue
    const fn = narrowest(functions.filter(f => within(f, l)))
    let k = fn ? own.findIndex(c => c.start > l && c.end <= fn.end) : -1
    if (k < 0) continue
    const group = [own[k]]
    for (k++; k < own.length && own[k].end <= fn.end && text.slice(own[k - 1].end, own[k].start - 1).every(quiet); k++) {
      group.push(own[k])
    }
    add(group)
  }
  return [...found.values()]
}

const due = tests.map(path => ({ path, harness: harnessOf(path) }))
  .map(t => ({ ...t, cases: cases(t.path, t.harness) }))
  .filter(t => t.cases.length)
  // The unit test files first: they take seconds, a harness a minute.
  .sort((a, b) => !!a.harness - !!b.harness)
const total = due.reduce((n, t) => n + t.cases.length, 0)
if (total === 0) {
  console.log(`no test case or harness step changed since ${baseName} (${short}): nothing to compare`)
  process.exit(0)
}

// The scratch tree: the base's files with this checkout's test/, the saved
// answers linked in where there are some. A harness's check there also
// says where it was called from, by the harness's line. The tree goes as
// the run ends; an interrupt first stops what runs in it, and waits for it
// to end.
const tree = mkdtempSync(join(process.env.TMPDIR || tmpdir(), "before."))
const running = new Set()
process.on("exit", () => rmSync(tree, { recursive: true, force: true }))
for (const [signal, code] of [["SIGINT", 130], ["SIGTERM", 143]]) {
  process.on(signal, async () => {
    for (const child of running) child.kill("SIGTERM")
    await Promise.all([...running].map(child => child.exited))
    process.exit(code)
  })
}
const fromBase = run(["bash", "-c", 'git archive "$1" | tar -x -C "$2"', "_", base, tree])
if (fromBase.code !== 0) {
  console.log(`FAILED before the change: could not check out ${short}: ${fromBase.err.trim()}`)
  process.exit(1)
}
rmSync(join(tree, "test"), { recursive: true, force: true })
for (const path of git("ls-files", "-z", "--cached", "--others", "--exclude-standard", "test").split("\0")) {
  if (path && existsSync(join(root, path))) cpSync(join(root, path), join(tree, path), { recursive: true })
}
const fixtures = run([join(root, "test/fixtures-dir.sh")])
if (fixtures.code === 0) symlinkSync(fixtures.out.trim(), join(tree, "test/fixtures"))
const harnessFile = join(tree, "test/qml/Harness.qml")
const harnessSource = readFileSync(harnessFile, "utf8")
const opening = "  function check(label, ok, detail) {\n"
if (!harnessSource.includes(opening)) {
  console.log("FAILED before the change: Harness.qml's check is no longer `function check(label, ok, detail)`; change test/before.js with it")
  process.exit(1)
}
writeFileSync(harnessFile, harnessSource.replace(opening, opening
  + "    var at = String(new Error().stack).split(\"\\n\").filter(function(f) { return /\\/shell\\.qml:\\d+$/.test(f) })[0]\n"
  + "    if (at) console.log(\"STEP \" + at.replace(/^.*:/, \"\") + \" \" + (ok ? \"PASS\" : \"FAIL\") + \" \" + label)\n"))

// failing T RESULTS CODE ERRORS: the first of T's cases to fail on the code
// before, as { start, name } or { start, error }: a check of it failed
// there, or its file's run failed before it ran with an error that names a
// file or a name the branch adds, as a file needing the change does. An
// error that names none of them is kept in `breaks`, never taken as proof:
// something else broken at the base. A skipped case fails on nothing.
const inCase = (checks, r) => checks.some(c => c.start <= r.line && r.line <= c.end)
const breaks = []
function failing(t, results, code, errors = []) {
  for (const checks of t.cases) {
    const own = results.filter(r => inCase(checks, r))
    const failed = own.find(r => !r.pass && !r.skip)
    if (failed) return { start: checks[0].start, name: failed.name }
    if (own.length || code === undefined || code === 0 || code === 77) continue
    const error = errors.find(namesAdded)
    if (error) return { start: checks[0].start, error }
    if (!breaks.some(b => b.t === t)) breaks.push({ t, errors })
  }
  return null
}

// runOne T: runs T's file in the tree, a harness by its runner's command, a
// test file in bun with a JUnit report, and returns its exit code and its
// checks' results, each with its line, whether it passed, and its name. A
// harness is read from its log as it runs, and stopped once one of its
// cases fails, or once another file's has.
const xml = s => s.replace(/&#10;/g, " ").replace(/&quot;/g, "\"").replace(/&apos;/g, "'")
  .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
const steps = text => [...text.matchAll(/STEP (\d+) (PASS|FAIL) (.*)/g)]
  .map(m => ({ line: Number(m[1]), pass: m[2] === "PASS", name: m[3] }))
let found = null
async function runOne(t, index, command) {
  const report = join(tree, `junit-${index}.xml`)
  // A harness's work folder, and so its Quickshell's log, under the tree
  // (test/scratch.sh).
  const work = join(tree, `work-${index}`)
  mkdirSync(work)
  const args = t.harness ? ["bash", "-c", command]
    : ["bun", "test", `./${t.path}`, "--reporter=junit", `--reporter-outfile=${report}`]
  const child = Bun.spawn(args, { cwd: tree, stdout: "pipe", stderr: "pipe", env: { ...process.env, STONKS_TEST_TMP: work } })
  running.add(child)
  let stopped = false, seen = []
  const watch = t.harness && setInterval(() => {
    for (const name of readdirSync(work)) {
      const log = join(work, name, "log")
      if (existsSync(log)) seen = steps(readFileSync(log, "utf8"))
    }
    if (!stopped && (found || failing(t, seen))) { stopped = true; child.kill("SIGTERM") }
  }, 500)
  const [out, err] = await Promise.all([new Response(child.stdout).text(), new Response(child.stderr).text()])
  const code = await child.exited
  running.delete(child)
  clearInterval(watch)
  // The lines that say why a run failed, a check's own result aside.
  const errors = [...new Set((out + "\n" + err).split("\n")
    .filter(l => /\bfail|error/i.test(l) || /not found|missed/.test(l))
    .filter(l => !/STEP \d+ /.test(l))
    .map(l => l.replace(/^\s*(DEBUG|INFO|WARN|ERROR|FATAL)?:?\s*(qml:\s*)?/, "").trim()))]
  if (t.harness) return stopped ? { results: seen } : { code, results: steps(out), errors }
  const results = []
  const text = existsSync(report) ? readFileSync(report, "utf8") : ""
  for (const m of text.matchAll(/<testcase name="([^"]*)"[^>]*? line="(\d+)"[^>]*?(\/>|>([\s\S]*?)<\/testcase>)/g)) {
    const body = m[4] || ""
    results.push({ line: Number(m[2]), pass: !/<(failure|error)\b/.test(body), skip: /<skipped\b/.test(body), name: xml(m[1]) })
  }
  return { code, results, errors }
}

// The unit test files, then the harnesses, one at a time and each of a
// harness's commands in turn, until a changed case fails on the code
// before. One at a time, so test/all.sh, whose queue gives this check one
// of its slots, never runs more harnesses at once than test/queue.sh allows.
let skipped = 0
for (const [index, t] of due.entries()) {
  for (const [part, command] of (t.harness ? starts.get(t.harness) : [null]).entries()) {
    if (found) break
    const { code, results, errors } = await runOne(t, `${index}-${part}`, command)
    if (code === 77) {
      console.log(`skipped ${t.path}: no saved answers to run its ${t.cases.length} changed cases on`)
      skipped += t.cases.length
      break
    }
    const f = failing(t, results, code, errors)
    if (f) found = { t, ...f }
  }
}

if (found) {
  const where = found.name ? `"${found.name}" (${found.t.path}:${found.start}) fails`
    : `the case at ${found.t.path}:${found.start} can't run, as "${found.error}" says,`
  console.log(`${where} on ${baseName}'s code (${short}), so the branch's tests tell its change from the code before it`)
  process.exit(0)
}
// A run that broke at the base for a reason the branch doesn't name proves
// nothing: say what broke, and fail.
for (const { t, errors } of breaks) {
  console.log(`FAILED before the change: ${t.path} broke on ${baseName}'s code (${short}) before reaching its changed cases, `
    + "and the error names nothing this branch adds, so it can't show the change is needed. Fix what broke there, or check it "
    + `fails for the change. It said:\n${(errors.length ? errors.slice(0, 5) : ["nothing"]).map(l => "  " + l).join("\n")}`)
}
if (breaks.length) process.exit(1)
if (skipped) {
  console.log(`no changed case that ran fails on ${baseName}'s code (${short}); the ${skipped} with no saved answers may`)
  process.exit(77)
}
console.log(`FAILED before the change: this branch changes the code in ${codeChanged.slice(0, 3).join(", ")}${codeChanged.length > 3 ? " and more" : ""}, `
  + `but ${total - skipped === 1 ? "the one test case or harness step" : `each of the ${total - skipped} test cases and harness steps`} it adds or changes passes on ${baseName}'s code too (${short}), `
  + "so none can tell the change from the code it replaces. Add or change a case that checks what the reader sees, "
  + `not a request or a value the code computed, and see it fail on ${baseName}'s code.`)
process.exit(1)
