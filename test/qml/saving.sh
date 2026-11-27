#!/usr/bin/env bash
# A save and the next read: a change made through the real service is in
# the lists file, the file is its owner's alone, and a fresh start reads
# what was saved; a file that can't be read is never written over, the
# footer says what to do, and once fixed it is read again; a save that
# can't land is said and lands when tried again, and an update's restart
# waits for it; a save is read back, and a save asked while a read is out
# waits for it, writing nothing over a file that can't be read; a file too
# large, not UTF-8, or no regular file, is never read or written over; a
# file that appears, or is edited by hand, is read; every older release's
# file reads whole; and a sound whose file couldn't be written is written
# once it can be. HOME and curl are scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree saving.qml
scratch_home v1-data.json grvc.stonks.json
export STONKS_DATA_FILES="$(ls "$plugin"/test/data-files/*.json | tr '\n' ' ')"
export QT_QPA_PLATFORM=offscreen
run_qs 120
# The three saves the walk refuses warn as Quickshell does for any lost save.
lost='WARN scene: QML FileView at @plugin/ListsFile.qml.*Write of .*grvc.stonks.json failed: Unknown error when opening file\.'
count=$(rg -c "$lost" "$work/log" || true)
if [ "${count:-0}" != 3 ]; then
  echo "FAIL expected three warnings of a lost save, got ${count:-0}"
  code=1
fi
sed -i "\\|$lost|d" "$work/log"
# The sound the walk can't write warns once: one that didn't land isn't
# tried again until it's wanted.
chime='WARN scene: QML FileView at @plugin/OwnerOnly.qml.*Write of .*chime-smooth-0\.wav failed'
count=$(rg -c "$chime" "$work/log" || true)
if [ "${count:-0}" != 1 ]; then
  echo "FAIL expected one warning of a lost sound, got ${count:-0}"
  code=1
fi
sed -i "\\|$chime|d" "$work/log"
# Queued async writes must never drop an active FileView operation.
if rg -q 'got operation finished from dropped operation' "$work/log"; then
  echo "FAIL async writes dropped a FileView operation"
  code=1
fi
finish "SAVING DONE"
