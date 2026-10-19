#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

fake_bin=$(mktemp -d)
trap 'rm -rf "$fake_bin"' EXIT

cat >"$fake_bin/omarchy-hyprland-session-locked" <<'SH'
#!/bin/bash

exit "$OMARCHY_TEST_LOCKED"
SH

# The lockers running are given, so the live desktop's own shell stays out of it.
cat >"$fake_bin/pgrep" <<'SH'
#!/bin/bash

[[ $* == "-u $UID -a -x quickshell|qs|hyprlock" ]] || exit 3
[[ -n $OMARCHY_TEST_LOCKERS ]] || exit 1
printf '%s\n' "$OMARCHY_TEST_LOCKERS"
SH
chmod +x "$fake_bin"/*

assert_status() {
  local expected="$1" locked="$2" lockers="$3" description="$4" actual=0

  PATH="$fake_bin:$PATH" OMARCHY_TEST_LOCKED="$locked" OMARCHY_TEST_LOCKERS="$lockers" \
    "$ROOT/bin/omarchy-hyprland-session-lock-stranded" 100 || actual=$?

  (( actual == expected )) || fail "$description" "expected exit $expected, got $actual"
  pass "$description"
}

shell="100 quickshell -n -p /usr/share/omarchy/shell"
other_shell="200 quickshell -n -p /tmp/tmp.abc/omarchy/shell"
voxtype="300 qs -d -p /usr/share/voxtype/quickshell"
voxtype_user="301 qs -d -p /data/.local/share/voxtype/quickshell/"
not_voxtype="302 quickshell -p /usr/share/voxtype/quickshell-lock"
hyprlock="400 hyprlock"

assert_status 0 0 "" "a lock with no locker alive is stranded"
assert_status 0 0 "$shell" "the asking shell does not count as another locker"
assert_status 1 1 "" "an unlocked session is not stranded"
assert_status 2 2 "" "a compositor that cannot say leaves it undetermined"
assert_status 2 0 "$shell"$'\n'"$other_shell" "a lock another shell may hold is left undetermined, so it is never taken"
assert_status 2 0 "$shell"$'\n'"$hyprlock" "a lock hyprlock may hold is left undetermined"
assert_status 0 0 "$shell"$'\n'"$voxtype" "voxtype's dictation OSD does not count as a locker"
assert_status 2 0 "$voxtype"$'\n'"$other_shell" "voxtype's OSD does not hide another shell"
assert_status 0 0 "$shell"$'\n'"$voxtype_user" "voxtype's per-user OSD copy does not count as a locker"
assert_status 2 0 "$shell"$'\n'"$not_voxtype" "only voxtype's own config is skipped, not a path that starts like it"
