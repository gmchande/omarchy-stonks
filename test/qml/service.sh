#!/usr/bin/env bash
# The real Service through migration, persist, and external edits, with the
# fake curl and a scratch HOME holding the bar entry; which symbols ask for a
# cap and P/E, once a day, keeping the last good on a failure; a data file
# that can't be read, never written over; a save from elsewhere during a read
# of the file; and the version watch on the tree's copy of the manifest.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
feed_tree service.qml Service.qml Gate.qml Updates.qml QuoteFeed.qml HistoryFeed.qml FundamentalsFeed.qml AllDayFeed.qml OvernightFeed.qml Fetch.js Quote.js Format.js Market.js Overnight.js History.js Fundamentals.js Chart.js Settings.js calendars.json manifest.json
# The harness ages a fundamentals entry by a day, and counts the data file's
# reads, so a check waits on its read-back.
patch_copy Service.qml '/readonly property var fundamentals:/a\  readonly property alias testFundamentalsFeed: fundamentalsFeed\n  readonly property alias testDataFile: dataFile'
# A second Service whose data file is a stand-in the harness steps through
# (DataFileStandIn.qml): Quickshell's own read can't be held part-way.
cp "$here/DataFileStandIn.qml" "$root/"
cp "$root/Service.qml" "$root/SteppedService.qml"
patch_copy SteppedService.qml '/^  FileView {$/{N;s/^  FileView {\n    id: dataFile$/  DataFileStandIn {\n    id: dataFile/}'
scratch_home shell-bar-only.json shell.json
run_qs 70
finish "ALL PASS"
