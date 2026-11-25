#!/usr/bin/env bash
# A save and the next read: a change made through the real service is in
# the lists file, the file is its owner's alone, and a fresh start reads
# what was saved; a file that can't be read is never written over, the
# footer says what to do, and once fixed it is read again; a save that
# can't land is said and lands when tried again; a save is read back, and a
# read out as it lands goes unheard; a file too large, or no regular file,
# is never read or written over; a file that appears, or is edited by hand,
# is read; and every older release's file reads whole. HOME and curl are
# scratch.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
plugin_tree saving.qml
scratch_home v1-data.json grvc.stonks.json
export STONKS_DATA_FILES="$(ls "$plugin"/test/data-files/*.json | tr '\n' ' ')"
export QT_QPA_PLATFORM=offscreen
run_qs 120
# The two saves the walk refuses warn as Quickshell does for any lost save.
lost='WARN scene: QML FileView at @plugin/ListsFile.qml.*Write of .*grvc.stonks.json failed: Unknown error when opening file\.'
count=$(rg -c "$lost" "$work/log" || true)
if [ "${count:-0}" != 2 ]; then
  echo "FAIL expected two warnings of a lost save, got ${count:-0}"
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
finish "SAVING DONE"
