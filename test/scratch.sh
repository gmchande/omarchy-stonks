# Where every run's work folders go, sourced first by each script that makes
# one: on disk, in the user's cache (STONKS_TEST_TMP names another), never
# in /tmp, which can be a tmpfs in memory that other programs fill. It sets
# TMPDIR, so every `mktemp -d` here and every tool a run starts (magick,
# bun, Quickshell) writes there too. Each script removes only the folders
# it made, by exact path; this folder itself stays, since runs side by side
# share it. The one folder kept in /tmp is a Quickshell's runtime folder
# (qml/quickshell.sh): its sockets need a path under 107 bytes, and it holds
# only links, sockets, and a log.
export TMPDIR=${STONKS_TEST_TMP:-${XDG_CACHE_HOME:-$HOME/.cache}/stonks-test}
mkdir -p -- "$TMPDIR" || { echo "can't make the work folder $TMPDIR" >&2; exit 1; }
