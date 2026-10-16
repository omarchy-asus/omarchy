#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
watch_pid=""
events_fd=""
logind_fd=""

# The watcher forks delayed clamshell retries and the recovery loop; kill the
# whole tree so nothing outlives the test tree it runs against.
stop_watcher() {
  local child descendants

  if [[ -n $watch_pid ]]; then
    descendants=$(pgrep -P "$watch_pid" 2>/dev/null || true)
    for child in $descendants; do
      descendants+=" $(pgrep -P "$child" 2>/dev/null || true)"
    done

    kill -KILL "$watch_pid" 2>/dev/null || true
    wait "$watch_pid" 2>/dev/null || true
    for child in $descendants; do
      kill -KILL "$child" 2>/dev/null || true
    done
    watch_pid=""
  fi

  if [[ -n $events_fd ]]; then
    exec {events_fd}>&-
    events_fd=""
  fi

  if [[ -n $logind_fd ]]; then
    exec {logind_fd}>&-
    logind_fd=""
  fi

  return 0
}

cleanup() {
  stop_watcher
  rm -rf "$test_tmp"
}
trap cleanup EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

events="$test_tmp/events"
logind="$test_tmp/logind"
sync_log="$test_tmp/sync.log"
gdbus_args="$test_tmp/gdbus-args"

cat >"$fake_bin/socat" <<'SH'
#!/bin/bash

exec cat "$OMARCHY_TEST_EVENTS"
SH

# Stands in for `gdbus monitor` on logind, printing what the test feeds it.
cat >"$fake_bin/gdbus" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >"$OMARCHY_TEST_GDBUS_ARGS"
exec cat "$OMARCHY_TEST_LOGIND"
SH

cat >"$fake_bin/omarchy-hyprland-monitor-clamshell" <<'SH'
#!/bin/bash

printf 'sync\n' >>"$OMARCHY_TEST_SYNC_LOG"
SH

for command in omarchy-system-lid-inhibit omarchy-hyprland-monitor-external-active omarchy-hw-laptop; do
  cat >"$fake_bin/$command" <<'SH'
#!/bin/bash

exit 0
SH
done

# Every monitor reports a mode, so the recovery loop stays quiet.
cat >"$fake_bin/omarchy-hyprland-monitor-modeless" <<'SH'
#!/bin/bash

exit 1
SH

chmod +x "$fake_bin"/*

syncs() {
  [[ -f $sync_log ]] || { echo 0; return; }
  wc -l <"$sync_log"
}

await_syncs() {
  local waited

  for (( waited = 0; waited < 40; waited++ )); do
    (( $(syncs) >= $1 )) && return 0
    sleep 0.05
  done

  return 1
}

rm -f "$events" "$logind" "$sync_log"
mkfifo "$events" "$logind"

PATH="$fake_bin:$PATH" \
XDG_RUNTIME_DIR="$test_tmp" \
HYPRLAND_INSTANCE_SIGNATURE=test \
OMARCHY_TEST_EVENTS="$events" \
OMARCHY_TEST_LOGIND="$logind" \
OMARCHY_TEST_GDBUS_ARGS="$gdbus_args" \
OMARCHY_TEST_SYNC_LOG="$sync_log" \
  "$ROOT/bin/omarchy-hyprland-monitor-watch" >/dev/null 2>&1 &
watch_pid=$!

exec {events_fd}>"$events"
exec {logind_fd}>"$logind"

await_syncs 1 || fail "the watcher reconciles the clamshell state at startup"
pass "the watcher reconciles the clamshell state at startup"

grep -F -- '--system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1' "$gdbus_args" >/dev/null ||
  fail "the watcher listens to logind on the system bus" "$(cat "$gdbus_args" 2>/dev/null)"
pass "the watcher listens to logind on the system bus"

# The startup retries run at 1, 3 and 7 seconds. The old docked poll added a
# sync every 2 seconds on top; nothing should land between the first two retries.
sleep 2.6
(( $(syncs) == 2 )) || fail "the watcher does not poll the clamshell state" "syncs after 2.6s: $(syncs)"
pass "the watcher does not poll the clamshell state"

before=$(syncs)
printf '%s\n' "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)" >&"$logind_fd"
printf '%s\n' "/org/freedesktop/login1: org.freedesktop.login1.Manager.SessionNew ('3', objectpath '/org/freedesktop/login1/session/_33')" >&"$logind_fd"
sleep 0.3
(( $(syncs) == before )) || fail "going to sleep and unrelated logind signals do not reconcile" "$before -> $(syncs)"
pass "going to sleep and unrelated logind signals do not reconcile"

printf '%s\n' "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)" >&"$logind_fd"
await_syncs $(( before + 1 )) || fail "a resume reconciles the clamshell state"
pass "a resume reconciles the clamshell state"

# Let the resume's own retry settle so the lid's sync is not swallowed by its lock.
sleep 1.3
before=$(syncs)
printf '%s\n' "/org/freedesktop/login1: org.freedesktop.DBus.Properties.PropertiesChanged ('org.freedesktop.login1.Manager', {'LidClosed': <true>}, @as [])" >&"$logind_fd"
await_syncs $(( before + 1 )) || fail "a lid change reported by logind reconciles the clamshell state"
pass "a lid change reported by logind reconciles the clamshell state"

before=$(syncs)
printf 'monitorremovedv2>>1,HDMI-A-1,Display\n' >&"$events_fd"
await_syncs $(( before + 1 )) || fail "a monitor removal still reconciles the clamshell state"
pass "a monitor removal still reconciles the clamshell state"

# The compositor going away ends the watcher, and logind's listener with it.
exec {events_fd}>&-
events_fd=""
for (( waited = 0; waited < 40; waited++ )); do
  kill -0 "$watch_pid" 2>/dev/null || break
  sleep 0.05
done
! kill -0 "$watch_pid" 2>/dev/null || fail "the watcher exits when the compositor's event socket closes"
wait "$watch_pid" 2>/dev/null || true
watch_pid=""
pass "the watcher exits when the compositor's event socket closes"
