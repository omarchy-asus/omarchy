#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

sleep_monitor="$ROOT/bin/omarchy-system-sleep-monitor"
tmpdir=$(mktemp -d)
monitor_pid=""
events_writer=""

cleanup() {
  [[ -n $monitor_pid ]] && kill -9 "$monitor_pid" 2>/dev/null
  [[ -n $events_writer ]] && exec {events_writer}>&-
  pkill -9 -f "$tmpdir" 2>/dev/null
  rm -rf "$tmpdir"
}
trap cleanup EXIT

mock_bin="$tmpdir/bin"
mock_omarchy="$tmpdir/omarchy"
producer_pid_file="$tmpdir/producer-pid"
inhibit_log="$tmpdir/inhibit-log"
inhibit_reject="$tmpdir/inhibit-reject"
lock_log="$tmpdir/lock-log"
events_fifo="$tmpdir/events"
mkdir -p "$mock_bin" "$mock_omarchy/bin"

# Each inhibitor taken logs the pid of the child it runs: logind holds the
# inhibitor exactly as long as that pid lives.
cat >"$mock_bin/systemd-inhibit" <<'SH'
#!/bin/bash

while [[ $1 == --* ]]; do
  shift
done

if [[ -e $INHIBIT_REJECT ]]; then
  echo "Failed to inhibit: $(<"$INHIBIT_REJECT")" >&2
  exit 1
fi

echo "$$" >>"$INHIBIT_LOG"
exec "$@"
SH

cat >"$mock_bin/dbus-monitor" <<'SH'
#!/bin/bash

echo "$$" >"$PRODUCER_PID_FILE"
printf 'signal time=0 sender=org.freedesktop.DBus -> destination=:1.1 member=NameAcquired\n'
exec cat "$EVENTS_FIFO"
SH

cat >"$mock_omarchy/bin/omarchy-system-sleep-lock" <<'SH'
#!/bin/bash

holder=$(tail -n 1 "$INHIBIT_LOG" 2>/dev/null)
if [[ -n $holder ]] && kill -0 "$holder" 2>/dev/null; then
  echo "locked held" >>"$LOCK_LOG"
else
  echo "locked unheld" >>"$LOCK_LOG"
fi
SH

chmod +x \
  "$mock_bin/systemd-inhibit" \
  "$mock_bin/dbus-monitor" \
  "$mock_omarchy/bin/omarchy-system-sleep-lock"
ln -s "$sleep_monitor" "$mock_omarchy/bin/omarchy-system-sleep-monitor"

wait_for() {
  local _
  for _ in {1..300}; do
    "$@" && return 0
    sleep 0.01
  done
  return 1
}

inhibitors() {
  [[ -s $inhibit_log ]] && wc -l <"$inhibit_log" || echo 0
}

current_holder() {
  tail -n 1 "$inhibit_log"
}

holding() {
  [[ -s $inhibit_log ]] && kill -0 "$(current_holder)" 2>/dev/null
}

not_holding() {
  ! holding
}

inhibitor_count_is() {
  [[ $(inhibitors) == "$1" ]]
}

lock_count_is() {
  [[ -s $lock_log && $(wc -l <"$lock_log") == "$1" ]]
}

running() {
  kill -0 "$1" 2>/dev/null
}

stopped() {
  ! kill -0 "$1" 2>/dev/null
}

start_monitor() {
  rm -f "$events_fifo" "$inhibit_log" "$lock_log" "$producer_pid_file"
  mkfifo "$events_fifo"
  exec {events_writer}<>"$events_fifo"

  OMARCHY_PATH="$mock_omarchy" \
    PATH="$mock_bin:$PATH" \
    PRODUCER_PID_FILE="$producer_pid_file" \
    INHIBIT_LOG="$inhibit_log" \
    INHIBIT_REJECT="$inhibit_reject" \
    LOCK_LOG="$lock_log" \
    EVENTS_FIFO="$events_fifo" \
    "$sleep_monitor" 2>"$tmpdir/monitor-stderr" &
  monitor_pid=$!

  wait_for test -s "$producer_pid_file" || fail "sleep monitor starts its event producer"
}

send_event() {
  printf '   boolean %s\n' "$1" >&"$events_writer"
}

stop_monitor() {
  kill "$monitor_pid" 2>/dev/null || true
  wait "$monitor_pid" 2>/dev/null || true
  monitor_pid=""
  exec {events_writer}>&-
  events_writer=""
}

# A full suspend and resume, twice, within one monitor process.
rm -f "$inhibit_reject"
start_monitor

wait_for holding || fail "sleep monitor holds an inhibitor once it is listening"
pass "sleep monitor holds an inhibitor once it is listening"

for cycle in 1 2; do
  holder=$(current_holder)
  send_event true
  wait_for lock_count_is "$cycle" ||
    fail "sleep monitor locks for a sleep event (cycle $cycle)"
  [[ $(tail -n 1 "$lock_log") == "locked held" ]] ||
    fail "sleep monitor locks while the inhibitor still holds the suspend (cycle $cycle)"
  wait_for stopped "$holder" ||
    fail "sleep monitor releases the inhibitor after locking (cycle $cycle)"
  running "$monitor_pid" ||
    fail "sleep monitor keeps running after a suspend (cycle $cycle)"

  send_event false
  wait_for inhibitor_count_is $((cycle + 1)) ||
    fail "sleep monitor takes a new inhibitor on resume (cycle $cycle)"
  wait_for holding ||
    fail "sleep monitor holds the new inhibitor (cycle $cycle)"
done
pass "sleep monitor locks while holding the inhibitor, then releases it"
pass "sleep monitor stays up across suspends and takes a new inhibitor on resume"

# Stopping the unit reaps the inhibitor and the event producer.
holder=$(current_holder)
producer_pid=$(<"$producer_pid_file")
stop_monitor
wait_for stopped "$holder" || fail "sleep monitor releases its inhibitor when terminated"
wait_for stopped "$producer_pid" ||
  fail "sleep monitor cleans up its producer when terminated" "producer still running: $producer_pid"
pass "sleep monitor cleans up its inhibitor and producer when terminated"

# Started while logind is still in a sleep transition: logind rejects the
# inhibitor as already running. That is not a failure: the resume's
# PrepareForSleep(false) takes it.
echo "The operation inhibition has been requested for is already running" >"$inhibit_reject"
start_monitor
sleep 2.5
running "$monitor_pid" ||
  fail "sleep monitor keeps running when logind is mid-transition" "$(<"$tmpdir/monitor-stderr")"
inhibitor_count_is 0 || fail "sleep monitor holds no inhibitor logind rejected"
rm -f "$inhibit_reject"
send_event false
wait_for holding || fail "sleep monitor takes the inhibitor once the transition ends"
pass "sleep monitor waits out a sleep transition instead of exiting"
stop_monitor

# Any other rejection is a real failure, left to the unit's Restart=.
echo "Access denied" >"$inhibit_reject"
start_monitor
producer_pid=$(<"$producer_pid_file")
wait_for stopped "$monitor_pid" || fail "sleep monitor exits when logind refuses the inhibitor"
wait "$monitor_pid" && fail "sleep monitor reports a refused inhibitor as a failure"
[[ $(<"$tmpdir/monitor-stderr") == *"Access denied"* ]] ||
  fail "sleep monitor logs why the inhibitor was refused" "$(<"$tmpdir/monitor-stderr")"
wait_for stopped "$producer_pid" || fail "sleep monitor reaps its producer when it fails"
monitor_pid=""
exec {events_writer}>&-
events_writer=""
rm -f "$inhibit_reject"
pass "sleep monitor fails on any other inhibitor rejection"

# The event stream ending (the system bus went away) is a failure too, and
# the inhibitor goes with it.
start_monitor
wait_for holding || fail "sleep monitor holds an inhibitor once it is listening"
holder=$(current_holder)
kill "$(<"$producer_pid_file")"
wait_for stopped "$monitor_pid" || fail "sleep monitor exits when its event stream ends"
wait "$monitor_pid" && fail "sleep monitor reports a lost event stream as a failure"
wait_for stopped "$holder" || fail "sleep monitor releases the inhibitor when its event stream ends"
monitor_pid=""
exec {events_writer}>&-
events_writer=""
pass "sleep monitor fails and releases the inhibitor when its event stream ends"

# A monitor killed outright cannot clean up; its inhibitor must not outlive it
# and hold up every later suspend.
start_monitor
wait_for holding || fail "sleep monitor holds an inhibitor once it is listening"
holder=$(current_holder)
kill -9 "$monitor_pid"
wait "$monitor_pid" 2>/dev/null || true
monitor_pid=""
wait_for stopped "$holder" || sleep 2
stopped "$holder" || fail "sleep monitor's inhibitor ends with a killed monitor"
exec {events_writer}>&-
events_writer=""
pass "sleep monitor's inhibitor ends with a killed monitor"
