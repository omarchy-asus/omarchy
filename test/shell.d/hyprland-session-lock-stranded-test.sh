#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

fake_bin=$(mktemp -d)
proc=$(mktemp -d)
trap 'rm -rf "$fake_bin" "$proc"' EXIT

cat >"$fake_bin/omarchy-hyprland-session-locked" <<'SH'
#!/bin/bash

exit "$OMARCHY_TEST_LOCKED"
SH

# The lockers running are given, so the live desktop's own shell stays out of it.
cat >"$fake_bin/pgrep" <<'SH'
#!/bin/bash

[[ $* == "-u $UID -x quickshell|qs|hyprlock" ]] || exit 3
[[ -n $OMARCHY_TEST_LOCKERS ]] || exit 1
printf '%s\n' $OMARCHY_TEST_LOCKERS
SH
chmod +x "$fake_bin"/*

locker() {
  local pid="$1"
  shift

  mkdir -p "$proc/$pid"
  printf '%s\0' "$@" >"$proc/$pid/cmdline"
}

# The Hyprland a locker was started under, as its environment names it.
under() {
  local pid="$1" signature="$2"

  printf '%s\0' "PATH=/usr/bin" "HYPRLAND_INSTANCE_SIGNATURE=$signature" "WAYLAND_DISPLAY=wayland-1" >"$proc/$pid/environ"
}

locker 100 quickshell -n -p /usr/share/omarchy/shell
locker 200 quickshell -n -p /tmp/tmp.abc/omarchy/shell
locker 201 quickshell -n -p "/data/voxtype/quickshell backup/omarchy/shell"
locker 202 qs -p /usr/share/voxtype/quickshell-locker
locker 300 qs -p /usr/share/voxtype/quickshell
locker 301 qs -d -p /data/.local/share/voxtype/quickshell
locker 302 /usr/bin/qs -p "/data/User Data/voxtype/quickshell/"
locker 400 hyprlock
locker 401 hyprlock -c /usr/share/voxtype/quickshell/lock.conf
locker 600 quickshell -n -p /usr/share/omarchy/shell
locker 601 quickshell -n -p /usr/share/omarchy/shell
locker 602 hyprlock
locker 603 quickshell -n -p /usr/share/omarchy/shell
locker 604 quickshell -n -p /usr/share/omarchy/shell

under 600 other-hyprland
under 601 this-hyprland
under 602 other-hyprland
printf '%s\0' "PATH=/usr/bin" "HYPRLAND_INSTANCE_SIGNATURE=" >"$proc/603/environ"
printf '%s\0' "PATH=/usr/bin" >"$proc/604/environ"

# The Hyprland the asking shell runs under.
signature=this-hyprland

assert_status() {
  local expected="$1" locked="$2" lockers="$3" description="$4" actual=0

  PATH="$fake_bin:$PATH" HYPRLAND_INSTANCE_SIGNATURE="$signature" OMARCHY_PROC_ROOT="$proc" OMARCHY_TEST_LOCKED="$locked" OMARCHY_TEST_LOCKERS="$lockers" \
    "$ROOT/bin/omarchy-hyprland-session-lock-stranded" 100 || actual=$?

  (( actual == expected )) || fail "$description" "expected exit $expected, got $actual"
  pass "$description"
}

assert_status 0 0 "" "a lock with no locker alive is stranded"
assert_status 0 0 "100" "the asking shell does not count as another locker"
assert_status 1 1 "" "an unlocked session is not stranded"
assert_status 2 2 "" "a compositor that cannot say leaves it undetermined"
assert_status 2 0 "100 200" "a lock another shell may hold is left undetermined, so it is never taken"
assert_status 2 0 "100 400" "a lock hyprlock may hold is left undetermined"
assert_status 0 0 "100 300" "voxtype's dictation OSD does not count as a locker"
assert_status 2 0 "300 200" "voxtype's OSD does not hide another shell"
assert_status 0 0 "100 301" "voxtype's OSD from the user's data directory does not count either"
assert_status 0 0 "100 302" "nor from a data directory with a space in it"
assert_status 2 0 "100 202" "a shell beside voxtype's config is still a locker"
assert_status 2 0 "100 201" "a shell whose path only contains voxtype's config, after a space, is still a locker"
assert_status 2 0 "100 401" "hyprlock is a locker whatever its arguments name"
assert_status 2 0 "100 500" "a locker gone before its arguments are read is still counted"
assert_status 0 0 "100 600" "a shell under another Hyprland cannot hold this one's lock"
assert_status 2 0 "100 601" "a shell under this Hyprland is still a locker"
assert_status 0 0 "100 602" "nor can hyprlock under another Hyprland"
assert_status 2 0 "100 603" "a shell with an empty signature is still a locker"
assert_status 2 0 "100 604" "a shell with no signature is still a locker"
assert_status 2 0 "600 601" "a shell under another Hyprland does not hide one under this"
signature=
assert_status 2 0 "100 600" "with no signature of its own, the asking shell counts every locker"
signature=this-hyprland
