#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mpv_comment="# Decode video on the integrated GPU that drives the display, so the NVIDIA GPU can stay asleep."
marker="# Omarchy repins the next line if the iGPU moves. Delete this comment to keep the line as your own."
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
  grep -A1 -xF -- "$marker" "$home/.config/$flags" | tail -n1 | grep -qFx -- "--render-node-override=$node" ||
    fail "the Chromium pin in $flags sits under Omarchy's marker" "$(cat "$home/.config/$flags")"
done
grep -qx -- '--ozone-platform=wayland--render-node-override=.*' "$home/.config/chrome-flags.conf" &&
  fail "the pin starts a line of its own after a missing trailing newline"
[[ -L $home/.config/chrome-flags.conf ]] || fail "a symlinked flags file stays a symlink"
[[ ! -e $home/.config/brave-flags.conf ]] || fail "flags files the user does not have stay absent"
pass "the migration pins existing Chromium-family flags files to the iGPU, once"

[[ $(cat "$home/.config/mpv/mpv.conf") == "$mpv_comment"$'\n'"hwdec=vaapi"$'\n'"$marker"$'\n'"vaapi-device=$node" ]] ||
  fail "the migration creates an mpv config that decodes through VA-API on the iGPU" "$(cat "$home/.config/mpv/mpv.conf")"
pass "the migration creates an mpv config that decodes through VA-API on the iGPU, once"

# A user's own choices win. A machine where decode was already set up by hand
# keeps mpv exactly as it is when hwdec or vaapi-device is set anywhere mpv
# reads: any [profile] of mpv.conf, or a file it pulls in with include=.
# Chromium keeps a flags file that already names a render node.
reset_home
mkdir -p "$home/.config/mpv"
printf '%s\n' '--render-node-override=/dev/dri/renderD128' >>"$home/.config/chromium-flags.conf"
cp "$ROOT/config/chromium-flags.conf" "$home/.config/brave-flags.conf"
printf '%s\n' '--render-node-override=/dev/dri/renderD129' >>"$home/.config/brave-flags.conf"
cp "$home/.config/brave-flags.conf" "$test_tmp/brave-flags.user"
printf '%s' '--enable-features=VaapiVideoDecoder' >"$home/.config/chrome-flags.conf"
run_migration

grep -c -- '--render-node-override=' "$home/.config/chromium-flags.conf" | grep -qx 1 ||
  fail "a render node the user chose is kept" "$(cat "$home/.config/chromium-flags.conf")"
cmp -s "$test_tmp/brave-flags.user" "$home/.config/brave-flags.conf" ||
  fail "every flags file with a render node keeps it" "$(cat "$home/.config/brave-flags.conf")"
grep -qFx -- "--render-node-override=$node" "$home/.config/chrome-flags.conf" ||
  fail "a flags file without a render node is still pinned" "$(cat "$home/.config/chrome-flags.conf")"
pass "Chromium flags files that name a render node are kept, the others pinned"

mpv_kept() { # description, then the lines of mpv.conf
  local description=$1
  shift
  mkdir -p "$home/.config/mpv"
  printf '%s\n' "$@" >"$home/.config/mpv/mpv.conf"
  cp "$home/.config/mpv/mpv.conf" "$test_tmp/mpv.user"
  run_migration
  cmp -s "$test_tmp/mpv.user" "$home/.config/mpv/mpv.conf" ||
    fail "$description: mpv.conf is untouched" "$(cat "$home/.config/mpv/mpv.conf")"
  pass "$description: mpv.conf is untouched"
}
mpv_kept "hwdec at the top, vaapi-device in a profile" 'hwdec = auto-copy' 'volume=80' '' '[big]' 'vaapi-device=/dev/dri/renderD128'
mpv_kept "vaapi-device only in a profile" 'volume=80' '' '[igpu]' 'vaapi-device=/dev/dri/renderD129'
mpv_kept "hwdec only in a profile, with no value" 'volume=80' '[hw]' '--hwdec'
printf '%s\n' '[default]' 'hwdec=vaapi' >"$home/.config/mpv/decode.conf"
mpv_kept "hwdec in a file included from the config directory" 'volume=80' 'include="~~/decode.conf"'
printf '%s\n' 'vaapi-device=/dev/dri/renderD129' >"$test_tmp/igpu.conf"
printf '%s\n' "include=$test_tmp/igpu.conf" >"$test_tmp/decode.conf"
mpv_kept "vaapi-device in a nested include" 'volume=80' "--include=$test_tmp/decode.conf"
mpv_kept "an include that cannot be read" 'volume=80' "include=$test_tmp/missing.conf"

# An include without either option, and the options in comments, do not count.
rm -rf "$home/.config/mpv"
mkdir -p "$home/.config/mpv"
printf '%s\n' 'volume=80' >"$home/.config/mpv/extra.conf"
printf '%s\n' '# hwdec=nvdec' 'include=~~/extra.conf # volume' "include='$home/.config/mpv/extra.conf' # again" '[big]' 'fullscreen # vaapi-device=x' >"$home/.config/mpv/mpv.conf"
run_migration
expected=$(printf '%s\n' "$mpv_comment" "hwdec=vaapi" "$marker" "vaapi-device=$node" '' '# hwdec=nvdec' 'include=~~/extra.conf # volume' "include='$home/.config/mpv/extra.conf' # again" '[big]' 'fullscreen # vaapi-device=x')
[[ $(cat "$home/.config/mpv/mpv.conf") == "$expected" ]] ||
  fail "an mpv.conf without decode settings is pinned ahead of its profiles" "$(cat "$home/.config/mpv/mpv.conf")"
pass "an mpv.conf without decode settings is pinned ahead of its profiles"

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

# A pin to an iGPU that is gone (a MUX switch, a BIOS update that moved its PCI
# address) is dropped and pinned again to the iGPU that is there now; with no
# iGPU at all the pins go. A user's own non-by-path setting stays.
stale_check() { # prints yes when nvidia.lua would schedule a refresh at start
  HOME="$home" lua <<'LUA'
package.path = os.getenv("ROOT") .. "/?.lua;" .. package.path
require("default.hypr.helpers")
local started = {}
hl = { env = function() end, on = function(event, fn) if event == "hyprland.start" then started[#started + 1] = fn end end,
  exec_cmd = function(command) io.write(command, "\n") end }
require("default.hypr.nvidia")
-- Other modules register start handlers too; only the commands matter here.
for _, fn in ipairs(started) do pcall(fn) end
LUA
}
machine "${g16[@]}"
reset_home
HOME="$home" bash -euo pipefail "$ROOT/install/user/hardware/hybrid-video-decode.sh" >/dev/null
[[ -z $(stale_check) ]] || fail "valid pins schedule no refresh at start"
machine 0000:64:00.0=0x10de:0x030000:0 0000:66:00.0=0x1002:0x038000
moved="$test_tmp/by-path/pci-0000:66:00.0-render"
[[ $(stale_check) == *omarchy-refresh-hybrid-video* ]] || fail "a pin to a gone iGPU schedules a refresh at start"
HOME="$home" bash "$ROOT/bin/omarchy-refresh-hybrid-video"
! grep -qF "pci-0000:65:00.0" "$home/.config/chromium-flags.conf" "$home/.config/mpv/mpv.conf" ||
  fail "the stale pins are dropped"
grep -qFx -- "--render-node-override=$moved" "$home/.config/chromium-flags.conf" || fail "Chromium is pinned to the iGPU's new address"
grep -qFx -- "vaapi-device=$moved" "$home/.config/mpv/mpv.conf" || fail "mpv is pinned to the iGPU's new address"
[[ $(cat "$home/.config/mpv/mpv.conf") == "$mpv_comment"$'\n'"$marker"$'\n'"vaapi-device=$moved"$'\n'"hwdec=vaapi" ]] ||
  fail "the mpv pin goes back under Omarchy's comment, once" "$(cat "$home/.config/mpv/mpv.conf")"
[[ -z $(stale_check) ]] || fail "refreshed pins schedule no refresh at start"
machine 0000:64:00.0=0x10de:0x030000:1
printf 'vaapi-device=/dev/dri/renderD129\n' >>"$home/.config/mpv/mpv.conf"
HOME="$home" bash "$ROOT/bin/omarchy-refresh-hybrid-video"
! grep -qF -e "by-path" -e "$marker" "$home/.config/chromium-flags.conf" "$home/.config/mpv/mpv.conf" ||
  fail "with no iGPU the pins go, with their markers"
grep -qFx 'vaapi-device=/dev/dri/renderD129' "$home/.config/mpv/mpv.conf" || fail "a pin the user set by device number stays"
pass "stale render node pins are dropped and re-pinned, at Hyprland start only when needed"

# A render node the user picked themselves is theirs, even one on the NVIDIA
# GPU by its PCI path: it schedules no refresh at start and a refresh leaves it.
machine "${g16[@]}"
reset_home
mkdir -p "$home/.config/mpv"
dgpu="$test_tmp/by-path/pci-0000:64:00.0-render"
printf '%s\n' "--render-node-override=$dgpu" >>"$home/.config/chromium-flags.conf"
printf '%s\n' 'hwdec=vaapi' "vaapi-device=$dgpu" >"$home/.config/mpv/mpv.conf"
cp "$home/.config/chromium-flags.conf" "$test_tmp/chromium-flags.user"
cp "$home/.config/mpv/mpv.conf" "$test_tmp/mpv.user"
run_migration
[[ -z $(stale_check) ]] || fail "a render node the user chose schedules no refresh at start"
HOME="$home" bash "$ROOT/bin/omarchy-refresh-hybrid-video"
cmp -s "$test_tmp/chromium-flags.user" "$home/.config/chromium-flags.conf" ||
  fail "a refresh keeps the user's NVIDIA render node for Chromium" "$(cat "$home/.config/chromium-flags.conf")"
cmp -s "$test_tmp/mpv.user" "$home/.config/mpv/mpv.conf" ||
  fail "a refresh keeps the user's NVIDIA render node for mpv" "$(cat "$home/.config/mpv/mpv.conf")"
pass "a render node the user chose, even the NVIDIA GPU's, is never replaced"
