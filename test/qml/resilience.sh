#!/usr/bin/env bash
# Real saves and deadline wakes, malformed overnight recovery, and work
# queued before/while the screens are off. Everything owned by this run.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree resilience.qml
patch_copy plugin/Service.qml '/readonly property var entries: feed.entries/a\  readonly property alias testGate: yahooGate\n  readonly property alias testFeed: feed\n  readonly property alias testHistory: historyFeed\n  readonly property alias testFundamentals: fundamentalsFeed\n  readonly property alias testDataFile: dataFile'
patch_copy plugin/Service.qml 's/function wallSecond() { return Math.floor(Date.now() \/ 1000) }/property int clockOffset: 0\n  function wallSecond() { return Math.floor(Date.now() \/ 1000) + root.clockOffset }/'
patch_copy plugin/FundamentalsFeed.qml '/id: root/a\  property int clockOffset: 0\n  readonly property var testCommand: fetchProc.command'
patch_copy plugin/FundamentalsFeed.qml 's/Date.now()/(Date.now() + root.clockOffset * 1000)/g'
patch_copy plugin/App.qml '/readonly property bool ready:/a\  readonly property var testBody: root.body\n  readonly property alias testKeys: keyCatcher'
printf '%s\n' '{"version":1,"symbols":["BTC-USD"],"featured":"BTC-USD","order":"manual","style":"smooth","range":"1D"}' > "$work/data.json"
# A full disk without root: Quickshell starts in a user and mount namespace
# of its own, whose ~/.config/omarchy is a 64 KB tmpfs holding the data
# file, then as the user again in one inside it, so a folder made
# read-only refuses its writes, as it would not refuse root's. Each step
# execs, so Quickshell keeps the pid the run started, and its group and
# mark (quickshell.sh). The tmpfs goes with the namespace.
mkdir -p "$work/bin"
cat > "$work/bin/quickshell" << EOF
#!/usr/bin/env bash
exec unshare --map-root-user --mount -- bash -c '
  set -e
  mount -t tmpfs -o size=64k,mode=700 tmpfs "\$HOME/.config/omarchy"
  cp "$work/data.json" "\$HOME/.config/omarchy/grvc.stonks.json"
  exec unshare --map-user=$(id -u) --map-group=$(id -g) -- "$(command -v quickshell)" "\$@"' _ "\$@"
EOF
chmod +x "$work/bin/quickshell"
export QT_QPA_PLATFORM=offscreen
PATH="$work/bin:$PATH" run_qs 90
# The test's lost saves warn as Quickshell does for any: three refused by
# the read-only folder, two on the full disk.
for expected in "Unknown error when opening file\\.:3" "Atomic commit failed\\.:2"; do
  pattern="WARN scene: QML FileView at @plugin/Service.qml.*Write of .*grvc.stonks.json failed: ${expected%:*}"
  count=$(rg -c "$pattern" "$work/log" || true)
  if [ "${count:-0}" != "${expected##*:}" ]; then
    echo "FAIL expected ${expected##*:} warnings of a lost save matching '${expected%:*}', got ${count:-0}"
    code=1
  fi
  sed -i "\\|$pattern|d" "$work/log"
done
finish "RESILIENCE DONE"
