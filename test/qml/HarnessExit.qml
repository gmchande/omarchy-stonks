import QtQuick
import QtTest

// The one way a harness ends Quickshell: set exitCode, then start it.
// Qt.exit tears the engine down at the next deferred delete, and QtTest's
// wait() runs those inside its own event loop, under the handler running the
// test: Qt aborts there, and the abort dumps core. So this exits only once no
// TestCase is running (TestSchedule.currentTest is null between test cases;
// were it renamed, every run would time out rather than abort). There is no
// watchdog in QML: a hang is stopped from outside, at its script's run_qs
// timeout (quickshell.sh), and TERM ends Quickshell without a core.
Timer {
  property int exitCode: 0
  interval: 1
  repeat: true
  onTriggered: {
    if (TestSchedule.currentTest !== null) return
    stop()
    Qt.exit(exitCode)
  }
}
