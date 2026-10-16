#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

migration=$(grep -l 'Decode video on the integrated GPU of hybrid NVIDIA laptops' "$ROOT"/migrations/*.sh)
home="$test_tmp/home"
node="$test_tmp/by-path/pci-0000:65:00.0-render"
stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# The refresh copies the shipped default over the user's file; the rest of what
# it installs is out of scope here.
cat >"$stub_bin/omarchy-refresh-config" <<'SH'
#!/bin/bash
cp -f "$OMARCHY_PATH/config/$1" "$HOME/.config/$1"
SH
printf '#!/bin/bash\nexit 0\n' >"$stub_bin/omarchy-install-chromium-copy-url"
printf '#!/bin/bash\nexit 0\n' >"$stub_bin/omarchy-install-chromium-ytdlp"
chmod +x "$stub_bin"/*

export OMARCHY_PATH="$ROOT" OMARCHY_INSTALL="$ROOT/install"
export OMARCHY_PCI_DEVICES_PATH="$test_tmp/devices" OMARCHY_DRI_BY_PATH="$test_tmp/by-path"
export PATH="$stub_bin:$ROOT/bin:$PATH"

# address=vendor:class[:boot_vga] for each display device.
machine() {
  local spec vendor class boot_vga device_dir
  rm -rf "$test_tmp/devices" "$test_tmp/by-path"
  mkdir -p "$test_tmp/devices" "$test_tmp/by-path"
  for spec in "$@"; do
    IFS=: read -r vendor class boot_vga <<<"${spec#*=}"
    device_dir="$test_tmp/devices/${spec%%=*}"
    mkdir -p "$device_dir"
    printf '%s\n' "$vendor" >"$device_dir/vendor"
    printf '%s\n' "$class" >"$device_dir/class"
    if [[ -n $boot_vga ]]; then
      printf '%s\n' "$boot_vga" >"$device_dir/boot_vga"
    fi
    : >"$test_tmp/by-path/pci-${spec%%=*}-render"
  done
}

reset_home() {
  rm -rf "$home" "$test_tmp/targets"
  mkdir -p "$home/.config" "$test_tmp/targets"
  cp "$ROOT/config/chromium-flags.conf" "$home/.config/chromium-flags.conf"
}

run_migration() {
  HOME="$home" bash -euo pipefail "$migration" >/dev/null
}

g16=(0000:64:00.0=0x10de:0x030000:0 0000:65:00.0=0x1002:0x038000)

# Zephyrus G16: the RTX sorts first, so decode must be pinned to the Radeon iGPU.
machine "${g16[@]}"
reset_home
cp "$ROOT/config/chromium-flags.conf" "$test_tmp/targets/chrome-flags.conf"
printf '%s' '--ozone-platform=wayland' >>"$test_tmp/targets/chrome-flags.conf"
ln -s "$test_tmp/targets/chrome-flags.conf" "$home/.config/chrome-flags.conf"
run_migration
run_migration

for flags in chromium-flags.conf chrome-flags.conf; do
  count=$(grep -cFx -- "--render-node-override=$node" "$home/.config/$flags" || true)
  (( count == 1 )) || fail "the migration pins $flags to the iGPU once" "$(cat "$home/.config/$flags")"
done
grep -qx -- '--ozone-platform=wayland--render-node-override=.*' "$home/.config/chrome-flags.conf" &&
  fail "the pin starts a line of its own after a missing trailing newline"
[[ -L $home/.config/chrome-flags.conf ]] || fail "a symlinked flags file stays a symlink"
[[ ! -e $home/.config/brave-flags.conf ]] || fail "flags files the user does not have stay absent"
pass "the migration pins existing Chromium-family flags files to the iGPU, once"

[[ $(cat "$home/.config/mpv/mpv.conf") == "# Decode video on the integrated GPU that drives the display, so the NVIDIA GPU can stay asleep."$'\n'"hwdec=vaapi"$'\n'"vaapi-device=$node" ]] ||
  fail "the migration creates an mpv config that decodes through VA-API on the iGPU" "$(cat "$home/.config/mpv/mpv.conf")"
pass "the migration creates an mpv config that decodes through VA-API on the iGPU, once"

# A user's own choices win, and a [profile] section keeps its options.
reset_home
mkdir -p "$home/.config/mpv"
printf '%s\n' '--render-node-override=/dev/dri/renderD128' >>"$home/.config/chromium-flags.conf"
printf '%s\n' 'hwdec = auto-copy' 'volume=80' '' '[big]' 'vaapi-device=/dev/dri/renderD128' >"$home/.config/mpv/mpv.conf"
run_migration

grep -c -- '--render-node-override=' "$home/.config/chromium-flags.conf" | grep -qx 1 ||
  fail "a render node the user chose is kept" "$(cat "$home/.config/chromium-flags.conf")"
expected=$(printf '%s\n' "# Decode video on the integrated GPU that drives the display, so the NVIDIA GPU can stay asleep." "vaapi-device=$node" '' 'hwdec = auto-copy' 'volume=80' '' '[big]' 'vaapi-device=/dev/dri/renderD128')
[[ $(cat "$home/.config/mpv/mpv.conf") == "$expected" ]] ||
  fail "the mpv pin keeps the user's hwdec and lands ahead of their profiles" "$(cat "$home/.config/mpv/mpv.conf")"
pass "settings the user already has are kept"

# Machines where the pin does not apply are left exactly as they were.
for description in "AMD only" "NVIDIA drives the display" "No device claims boot_vga"; do
  case $description in
  "AMD only") machine 0000:65:00.0=0x1002:0x038000 ;;
  "NVIDIA drives the display") machine 0000:00:02.0=0x8086:0x030000:0 0000:01:00.0=0x10de:0x030000:1 ;;
  "No device claims boot_vga") machine 0000:05:00.0=0x1002:0x030000 0000:01:00.0=0x10de:0x030200 ;;
  esac
  reset_home
  run_migration
  cmp -s "$ROOT/config/chromium-flags.conf" "$home/.config/chromium-flags.conf" ||
    fail "$description: the Chromium flags are untouched"
  [[ ! -e $home/.config/mpv ]] || fail "$description: no mpv config is created"
  pass "$description: nothing is written"
done

# New users get the pin from the per-user hardware leaf.
machine "${g16[@]}"
reset_home
HOME="$home" bash -euo pipefail "$ROOT/install/user/hardware/hybrid-video-decode.sh" >/dev/null
grep -qFx -- "--render-node-override=$node" "$home/.config/chromium-flags.conf" ||
  fail "the per-user leaf pins Chromium"
grep -qFx -- "vaapi-device=$node" "$home/.config/mpv/mpv.conf" || fail "the per-user leaf pins mpv"
pass "the per-user hardware leaf pins mpv and Chromium"

# Refreshing Chromium's flags from the default keeps the pin.
HOME="$home" bash "$ROOT/bin/omarchy-refresh-chromium" >/dev/null
count=$(grep -cFx -- "--render-node-override=$node" "$home/.config/chromium-flags.conf" || true)
(( count == 1 )) || fail "omarchy-refresh-chromium keeps the pin" "$(cat "$home/.config/chromium-flags.conf")"
pass "omarchy-refresh-chromium keeps the pin"
