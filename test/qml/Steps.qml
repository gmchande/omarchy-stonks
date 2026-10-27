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
}
