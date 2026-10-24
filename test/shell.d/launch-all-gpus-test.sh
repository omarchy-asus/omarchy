#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/home/.local/share/applications" "$test_tmp/share/applications"

# gtk-launch reports what it was asked to run and the GPU pins it inherited.
cat >"$mock_bin/gtk-launch" <<'SH'
#!/bin/bash
printf '%s vk=%s egl=%s\n' "$*" "${VK_LOADER_DRIVERS_DISABLE-unset}" "${__EGL_VENDOR_LIBRARY_FILENAMES-unset}"
SH
chmod +x "$mock_bin/gtk-launch"

cat >"$test_tmp/share/applications/steam.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Steam
Exec=/usr/bin/steam %U
PrefersNonDefaultGPU=true
DESKTOP

cat >"$test_tmp/share/applications/org.example.Editor.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Editor
Exec=editor

[Desktop Action discrete]
Name=On the discrete GPU
PrefersNonDefaultGPU=true
DESKTOP

# A user's copy shadows the system entry, as it does for gtk-launch.
cat >"$test_tmp/share/applications/org.example.Game.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Game
PrefersNonDefaultGPU=true
DESKTOP
cat >"$test_tmp/home/.local/share/applications/org.example.Game.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Game
PrefersNonDefaultGPU=false
DESKTOP

# An entry in a subdirectory has the path's slashes as dashes in its ID.
mkdir -p "$test_tmp/share/applications/games"
cat >"$test_tmp/share/applications/games/example.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Nested game
PrefersNonDefaultGPU=true
DESKTOP

launch() {
  HOME="$test_tmp/home" XDG_DATA_HOME="" XDG_DATA_DIRS="$test_tmp/share" PATH="$ROOT/bin:$mock_bin:$PATH" \
    VK_LOADER_DRIVERS_DISABLE='*nvidia*' __EGL_VENDOR_LIBRARY_FILENAMES=mesa:nvidia \
    "$ROOT/bin/omarchy-launch-desktop-entry" "$1"
}

expect() {
  local description="$1" expected="$2" actual="$3"
  [[ $actual == "$expected" ]] || fail "$description" "expected '$expected', got '$actual'"
  pass "$description"
}

expect "an entry that prefers the discrete GPU starts without the GPU pins" \
  "steam.desktop vk=unset egl=unset" "$(launch steam.desktop)"
expect "a desktop id given without its suffix is found too" \
  "steam vk=unset egl=unset" "$(launch steam)"
expect "an entry in a subdirectory is found by its desktop ID" \
  "games-example.desktop vk=unset egl=unset" "$(launch games-example.desktop)"
expect "an action's PrefersNonDefaultGPU is not the entry's" \
  "org.example.Editor.desktop vk=*nvidia* egl=mesa:nvidia" "$(launch org.example.Editor.desktop)"
expect "the user's copy of an entry decides" \
  "org.example.Game.desktop vk=*nvidia* egl=mesa:nvidia" "$(launch org.example.Game.desktop)"
expect "an entry that cannot be found keeps the pins" \
  "missing.desktop vk=*nvidia* egl=mesa:nvidia" "$(launch missing.desktop)"

if "$ROOT/bin/omarchy-launch-all-gpus" 2>/dev/null; then
  fail "omarchy-launch-all-gpus refuses to run without a command"
fi
pass "omarchy-launch-all-gpus refuses to run without a command"
