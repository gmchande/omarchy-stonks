# The queue and the lock both runners share, sourced by test/all.sh (what
# Stonks does) and test/review.sh (how it looks and moves). A runner sources
# this, queues its harnesses (start), fills the slots (fill), runs its quick
# checks (run), and ends on verdict. The harnesses run side by side, a few
# at a time, each with its own HOME, QML cache, and fake curl state
# (qml/lib.sh), while the quick checks run; each one's output prints in
# order, with its time. A check that exits 77 had no saved answers to run on
# (test/fixtures-dir.sh): it says why, and the last line counts the skips,
# ALL PASS only when nothing skipped.
#
#   test/all.sh [--again] [NAME...]     test/review.sh [--again] [--fresh]
#
# A tree that already passed, since the last system update and the saved
# answers' last change, isn't run again: its record covers it. --again runs
# it anyway, as when chasing a flaky test.
#
# A runner that takes names sets $some to them before sourcing this: then
# only the named checks run (start, picked, known_names), the run is never
# recorded nor refused, and its last line names them instead of ALL PASS,
# which only a full run may print.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source "$PWD/test/scratch.sh"
runner=test/${0##*/}
some=${some-}
again=""
for arg; do
  case $arg in
    --again) again=1 ;;
    *) echo "$runner: unknown option $arg"; exit 2 ;;
  esac
done

# The run's record (test/ran.sh): the tree it ran on, so the next one to
# merge it checks the record instead of running it again. Only a run that
# begins and ends on a clean tree (no edit, no untracked file) is recorded:
# any other ran on something no commit holds. It goes in the git folder
# every worktree shares, which no one edits by hand.
clean_tree() { [ -z "$(git status --porcelain 2> /dev/null)" ] && git rev-parse -q --verify 'HEAD^{tree}' 2> /dev/null; }
records="$(git rev-parse --path-format=absolute --git-common-dir)/stonks-runs"
# checkout: what the run runs on: its clean tree, if it is clean, and HEAD.
checkout() {
  tree=$(clean_tree)
  commit=$(git rev-parse -q --verify HEAD 2> /dev/null)
  if [ -n "$some" ]; then tree=""
  elif [ -z "$tree" ]; then echo "$runner: this run won't be recorded: the tree has uncommitted edits or untracked files (git status)"; fi
}
# refuse_passed: ends the run when this tree already passed this runner in a
# run that began after the last package change and the saved answers' last
# change (test/ran.sh --passed), unless --again.
refuse_passed() {
  [ -n "$tree" ] && [ -z "$again" ] || return 0
  test/ran.sh --passed "$runner" 2> /dev/null || return 0
  echo "$runner already passed on this tree, and neither a package nor a saved"
  echo "answer has changed since; its record covers it (test/ran.sh shows it)."
  echo "To run it again on purpose, as when chasing a flaky test: $runner --again"
  exit 0
}
checkout
refuse_passed

# One run at a time on this machine, of either runner, from any checkout:
# overlapping runs fill its memory. A second run says what it waits
# for, then waits. The kernel lets go of the lock once this run and each
# check it started have ended, however they end: a run killed outright still
# holds it until its checks end, each within its own time limit. The
# commands themselves, and so Quickshell and anything else they start, never
# hold it (9>&- below), so no stray process holds up the next run. The lock
# is in the session's runtime folder, found as quickshell.sh finds it, so
# every run on a desktop names the same one; only where there is none, as in
# a container, in /tmp.
for folder in "${XDG_RUNTIME_DIR:-}" "/run/user/$UID" /tmp; do [ -d "$folder" ] && break; done
lock=$folder/stonks-suite.lock
# A run that can't take the lock stops rather than run beside another.
exec 9>> "$lock" || exit 1
if ! flock -n 9; then
  echo "$runner: waiting for the run already going ($(cat "$lock"))"
  flock 9 || exit 1
  # The checkout may have moved meanwhile, and that run may have passed it.
  checkout
  refuse_passed
fi
echo "$runner, pid $$ in $PWD" > "$lock"

# centiseconds: time since boot, which a clock change does not move.
centiseconds() {
  local up
  read -r up _ < /proc/uptime
  echo "${up/./}"
}
# The run's own time, from the lock taken to its verdict.
began=$(centiseconds)

# Before anything runs: every harness script sources lib.sh, ends on finish
# and its finish line, and is started by one of the runners. A script that
# misses one can pass without its checks having run. quickshell.sh is
# lib.sh's runner, crash-check.sh proves it without the saved answers, and
# data-files.sh and readme.sh are release tools no runner starts.
for script in test/qml/*.sh; do
  name=${script##*/}
  case "$name" in lib.sh|quickshell.sh|crash-check.sh|render.sh|data-files.sh|readme.sh) continue ;; esac
  grep -q '^source .*/lib\.sh"$' "$script" || echo "FAILED $script does not source lib.sh"
  tail -n 1 "$script" | grep -qE '^finish "[^"]+"$' || echo "FAILED $script does not end with finish \"...\""
  grep -qE "^start .* bash test/qml/${name//./\\.}( .*)?$" test/all.sh test/review.sh \
    || echo "FAILED $script is started by neither test/all.sh nor test/review.sh"
done | grep . && { echo "SOME FAILED"; exit 1; }

status=0
logs=$(mktemp -d)
labels=()
pids=()
# Each harness runs in a process group of its own, which holds everything it
# starts, so an interrupt stops exactly those groups: never a process by
# name, since the owner's shell and other runs are Quickshells too. It waits
# for them to empty, as each harness stops its own Quickshell's group, so
# nothing the run started outlives it.
stop_all() {
  local pid i
  for pid in "${pids[@]}"; do kill -- "-$pid" 2> /dev/null; done
  for pid in "${pids[@]}"; do
    for i in $(seq 50); do pgrep -g "$pid" > /dev/null || break; sleep 0.2; done
  done
  exit 130
}
trap stop_all INT TERM
trap 'rm -rf "$logs"' EXIT

# At most this many checks started below run at once: all nineteen at once
# peak at 1.9 GB, four at 0.8 GB. The harnesses wait on their own steps, not
# the machine (test/all.sh at four uses 1.5 of 16 cores), so six at once end
# a run sooner.
slots=6
queue=()

# start LABEL COMMAND...: queues COMMAND to run in the background, in order,
# once fewer than $slots of them run (fill); a harness only when picked.
start() {
  local command arg
  for arg in "${@:2}"; do
    [[ $arg == test/qml/*.sh ]] && { arg=${arg#test/qml/}; picked "${arg%.sh}" || return 0; break; }
  done
  labels+=("$1")
  printf -v command '%q ' "${@:2}"
  queue+=("$command")
}

# picked NAME: whether this run runs the check NAME: every check, or only
# the named ones ($some). start picks a harness by its test/qml/NAME.sh,
# noting the name for known_names.
known=""
picked() {
  [[ " $known " == *" $1 "* ]] || known+=" $1"
  [ -z "$some" ] || [[ " $some " == *" $1 "* ]]
}

# known_names NAME...: once every harness is queued, ends the run, before
# anything starts, when a name in $some is neither a harness's nor one of
# NAMES.
known_names() {
  local - name
  set -f
  known+=" $*"
  for name in $some; do
    [[ " $known " == *" $name "* ]] && continue
    echo "$runner: no check is named $name; the names are:$known"
    exit 2
  done
}

# fill: runs queued commands while fewer than $slots run, each in a process
# group of its own (job control, set -m), into its own log, noting its time
# in centiseconds beside it.
fill() {
  local pid running=0 log command
  for pid in "${pids[@]}"; do kill -0 "$pid" 2> /dev/null && running=$((running + 1)); done
  while [ "${#queue[@]}" -gt 0 ] && [ "$running" -lt "$slots" ]; do
    log="$logs/${#pids[@]}" command=${queue[0]}
    queue=("${queue[@]:1}")
    set -m
    # The job holds the lock while its command, which doesn't, runs.
    (
      begin=$(centiseconds)
      eval "$command" > "$log" 2>&1 9>&-
      code=$?
      echo $(( $(centiseconds) - begin )) > "$log.cs"
      echo "$code" > "$log.code"
      exit "$code"
    ) &
    set +m
    pids+=($!)
    running=$((running + 1))
  done
}

# report CODE [CS]: a check's verdict, and its time when it has one.
skipped=0
report() {
  local took=${2:+ ($(printf '%d.%ds' $(($2 / 100)) $(($2 % 100 / 10))))}
  if [ "$1" -eq 0 ]; then echo "   ok$took"
  elif [ "$1" -eq 77 ]; then echo "   skipped$took"; skipped=$((skipped + 1))
  else echo "   FAILED$took"; status=1; fi
}
# run LABEL COMMAND...: a quick check, in the foreground, with its verdict;
# then the queue fills any slot that came free meanwhile.
run() {
  echo "== $1"
  shift
  "$@" 9>&-
  report $?
  fill
}

# drain: once every queued check has ended, filling slots meanwhile, for a
# check that reads what they made (test/review.sh's render diff). Their
# output still prints at the verdict.
drain() {
  local pid
  while [ "${#queue[@]}" -gt 0 ]; do sleep 0.2; fill; done
  for pid in "${pids[@]}"; do
    while kill -0 "$pid" 2> /dev/null; do sleep 0.2; done
  done
}

# passed NUMBER...: whether each queued check with NUMBER passed, after
# drain. A check's number is how many were queued before it, so a runner
# notes ${#labels[@]} just before its start.
passed() {
  local i
  for i; do [ "$(cat "$logs/$i.code" 2> /dev/null)" = 0 ] || return 1; done
}

# verdict: once the queue has run dry, each queued check's output and
# verdict in order, the run's own time, and the last line, which a run on a
# clean tree also records against it. Exits non-zero on any failure.
verdict() {
  local i code took last
  while [ "${#queue[@]}" -gt 0 ]; do sleep 0.2; fill; done
  for i in "${!pids[@]}"; do
    wait "${pids[$i]}"
    code=$?
    echo "== ${labels[$i]}"
    cat "$logs/$i"
    report "$code" "$(cat "$logs/$i.cs" 2> /dev/null)"
  done
  took=$(( ($(centiseconds) - began + 50) / 100 ))
  echo "$runner took $((took / 60)) min $((took % 60)) s"
  if [ "$status" -ne 0 ]; then last="SOME FAILED"
  elif [ -n "$some" ]; then
    last="PASSED ONLY $some"
    [ "$skipped" -gt 0 ] && last+=", $skipped SKIPPED (no saved answers)"
  elif [ "$skipped" -gt 0 ]; then last="PASSED, $skipped SKIPPED (no saved answers)"
  else last="ALL PASS"; fi
  if [ -n "$tree" ] && [ "$(clean_tree)" = "$tree" ]; then
    echo "$tree $commit $runner $(date -Iseconds) ${took}s $last" >> "$records"
  fi
  echo "$last"
  exit "$status"
}
