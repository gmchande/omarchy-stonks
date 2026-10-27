#!/usr/bin/env bash
# The real Service, with the fake curl and a scratch HOME holding the bar
# entry: migration, a data file only its owner can read from the first
# write, persist, external edits; which symbols ask for a cap and P/E, once
# a day, keeping the last good on failure; an unreadable data file never
# written over; a save from elsewhere mid-read; and the version watch on the
# tree's manifest.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
feed_tree service.qml Service.qml OwnerOnly.qml Gate.qml Updates.qml QuoteFeed.qml HistoryFeed.qml FundamentalsFeed.qml AllDayFeed.qml OvernightFeed.qml ReleaseFeed.qml Fetch.js Quote.js Format.js Market.js Overnight.js History.js Fundamentals.js Figures.js Chart.js Settings.js Release.js calendars.json manifest.json
# The harness ages a fundamentals entry by a day, and counts the data file's
# reads, so a check waits on its read-back.
patch_copy Service.qml '/readonly property var fundamentals:/a\  readonly property alias testFundamentalsFeed: fundamentalsFeed\n  readonly property alias testDataFile: dataFile'
# A second Service whose data file is a stand-in the harness steps through
# (DataFileStandIn.qml): Quickshell's own read can't be held part-way.
cp "$here/DataFileStandIn.qml" "$root/"
cp "$root/Service.qml" "$root/SteppedService.qml"
patch_copy SteppedService.qml '/^  FileView {$/{N;s/^  FileView {\n    id: dataFile$/  DataFileStandIn {\n    id: dataFile/}'
scratch_home shell-bar-only.json shell.json
# Under the umask most machines have, every chmod waits until the harness
# has read the data file's first mode (bin/chmod).
umask 022
touch "$STONKS_FAKE_STATE/chmod.hold"
run_qs 70
finish "SERVICE DONE"
