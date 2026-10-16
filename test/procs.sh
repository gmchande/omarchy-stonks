# Process groups and run marks, shared by the tophat (tophat.sh) and the
# Quickshell runs (qml/quickshell.sh). A run marks what it starts with
# NAME=VALUE in their environment, which every child inherits, so its
# processes are found by that mark, never by name: the owner's shell and
# other runs are the same programs.

# stat_of PID: the fields of /proc/PID/stat after the command name, so
# $2 is the parent, $3 the process group, and $20 the start time.
stat_of() {
  local s
  s=$(cat "/proc/$1/stat" 2>/dev/null) || return 1
  printf '%s\n' "${s##*) }"
}
ppid_of() { stat_of "$1" | awk '{print $2}'; }
pgid_of() { stat_of "$1" | awk '{print $3}'; }
start_of() { stat_of "$1" | awk '{print $20}'; }

# leader_is LEADER START: LEADER is the process recorded (its start time)
# and still leads its group.
leader_is() {
  [ -n "$1" ] && [ "$(start_of "$1")" = "$2" ] && [ "$(pgid_of "$1")" = "$1" ]
}

# group_ours LEADER START MARK: the group LEADER made still holds the run's
# processes: its leader is the one recorded, or every member carries MARK
# (the leader may go first, and a group number is never reused while a
# member lives).
group_ours() {
  local pid members
  leader_is "$1" "$2" && return 0
  members=$(pgrep -g "$1") || return 1
  for pid in $members; do
    grep -qzx -- "$3" "/proc/$pid/environ" 2> /dev/null || return 1
  done
}

# signal_group SIGNAL LEADER START MARK: only the group the run made.
signal_group() {
  group_ours "$2" "$3" "$4" || return 1
  kill -s "$1" -- "-$2" 2> /dev/null
}

# marked MARK: "PID COMMAND" for each process that carries MARK.
marked() {
  local env pid
  { grep -lzx -- "$1" /proc/[0-9]*/environ 2> /dev/null || :; } | while read -r env; do
    pid=${env#/proc/}; pid=${pid%/environ}
    echo "$pid $(tr '\0' ' ' < "/proc/$pid/cmdline" 2> /dev/null)"
  done
}
