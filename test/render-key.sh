#!/usr/bin/env bash
# The name of the set of pictures test/qml/render.sh draws from the checkout
# at DIR (this one by default): a hash of everything that draws them, so two
# trees with one name draw the same pixels (test/review.sh keeps each set it
# draws under its name, and reuses it). A name that leaves out an input would
# let a kept set stand in for pictures that input changed, so when in doubt
# an input goes in: a needless one costs only a fresh drawing.
#
# - Stonks' own files: every file outside test/ and .github/, since the
#   picture's tree copies from the plugin's root (lib.sh, plugin_tree).
# - The drawing tools under test/: every file render.sh reads or sources.
#   A change that makes it read another must name it here.
# - The saved answers: their commit, and any edit not yet committed.
# - The installed packages (pacman -Q): Omarchy's shell and themes, Qt,
#   Quickshell, and the fonts.
# - What the fonts read beyond the packages: the system's and the user's
#   fontconfig and the user's fonts, which the scratch HOME doesn't hide,
#   since XDG_CONFIG_HOME and XDG_DATA_HOME point past it.
# - What the shell's own components read as they start: the corner rounding
#   and outer gap from the running Hyprland (Commons/Style.qml), and
#   Omarchy's settings from the environment, with the locale and Qt's.
#
# DIR is a git checkout, whose tracked and untracked files count, an edit
# included, or a tree git archive wrote (test/review.sh's base). The same
# commit gets the same name either way. Fails without the saved answers.
#
#   test/render-key.sh [DIR]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fixtures=$(test/fixtures-dir.sh)
dir=$(cd "${1:-.}" && pwd)
tools="test/qml/render.sh test/qml/render.qml test/qml/popup-anchor.qml test/qml/FrameGrab.qml test/qml/frames.js test/qml/lib.sh test/qml/quickshell.sh test/qml/HarnessExit.qml test/qml/Harness.qml test/qml/Steps.qml test/procs.sh test/fixtures-dir.sh"

# files: DIR's files, as paths under it.
files() {
  if [ -e "$dir/.git" ]; then git -C "$dir" ls-files -co --exclude-standard
  else (cd "$dir" && find . -type f -printf '%P\n'); fi
}
# hashes FOLDER: each file under FOLDER, links followed, with its hash.
hashes() { [ ! -d "$1" ] || (cd "$1" && find -L . -type f -print0 | sort -z | xargs -0r sha256sum); }

{
  { files | grep -Ev '^(test|\.github)/' || true; tr ' ' '\n' <<< "$tools"; } \
    | sort -u | (cd "$dir" && while IFS= read -r file; do [ ! -f "$file" ] || sha256sum "$file"; done)
  echo "saved answers $(git -C "$fixtures" rev-parse HEAD)"
  git -C "$fixtures" diff HEAD --binary
  (cd "$fixtures" && git ls-files -o --exclude-standard -z | xargs -0r sha256sum)
  pacman -Q
  hashes /etc/fonts
  hashes "${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig"
  hashes "${XDG_DATA_HOME:-$HOME/.local/share}/fonts"
  hyprctl -j getoption decoration:rounding 2> /dev/null || true
  hyprctl -j getoption general:gaps_out 2> /dev/null || true
  env | grep -E '^(LANG|LANGUAGE|LC_[A-Z]+|QT_[A-Z_]+|QML[A-Z0-9_]*|QSG_[A-Z_]+|FONTCONFIG_[A-Z_]+|OMARCHY_[A-Z0-9_]+)=' | sort || true
} | sha256sum | cut -c1-16
