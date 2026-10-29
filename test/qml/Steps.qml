import QtQuick
import QtTest

// The TestCase a flow harness walks its steps in.
TestCase {
  // Waits up to ms for fn to hold and returns whether it does, so the check
  // that reads it is the one that fails.
  function within(ms, fn) {
    for (var t = 0; t < ms && !fn(); t += 20) wait(20)
    return fn()
  }

  // QtTest's own report of a failed verify or a step that throws never
  // reaches these runs' log, which then ended only short of its marker:
  // each failure is said here too, with where, for lib.sh's finish. It
  // wraps QtTest's `qtest_results`, so a Qt that renames it fails every run
  // as it loads, not quietly.
  Component.onCompleted: {
    var results = qtest_results
    var say = function(message, file, line) {
      console.log("FAIL! " + (message || "a check failed") + (file ? " (" + String(file).replace(/^.*\//, "") + ":" + line + ")" : ""))
    }
    qtest_results = new Proxy(results, {
      get: function(target, key) {
        if (key === "fail") return function(message, file, line) {
          say(message, file, line)
          return target.fail(message, file, line)
        }
        if (key === "verify") return function(ok, message, file, line) {
          if (!ok) say(message, file, line)
          return target.verify(ok, message, file, line)
        }
        if (key === "compare") return function(ok, message, actual, expected, file, line) {
          if (!ok) say((message ? message + ": " : "") + actual + " is not " + expected, file, line)
          return target.compare(ok, message, actual, expected, file, line)
        }
        var value = target[key]
        return typeof value === "function" ? value.bind(target) : value
      }
    })
  }
}
