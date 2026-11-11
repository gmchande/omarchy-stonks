#!/usr/bin/env bash
# A save and the next read: a change made through the real service is in
# the lists file, the file is its owner's alone, and a fresh start reads
# what was saved; a file that can't be read is never written over, the
# footer says what to do, and once fixed it is read again; a save that
# can't land is said and lands when tried again. HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree saving.qml
scratch_home v1-data.json grvc.stonks.json
export QT_QPA_PLATFORM=offscreen
run_qs 60
# The one save the walk refuses warns as Quickshell does for any lost save.
lost='WARN scene: QML FileView at @plugin/ListsFile.qml.*Write of .*grvc.stonks.json failed: Unknown error when opening file\.'
count=$(rg -c "$lost" "$work/log" || true)
if [ "${count:-0}" != 1 ]; then
  echo "FAIL expected one warning of a lost save, got ${count:-0}"
  code=1
fi
sed -i "\\|$lost|d" "$work/log"
finish "SAVING DONE"
