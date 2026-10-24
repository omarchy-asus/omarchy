#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command lua

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
export OMARCHY_PCI_DEVICES_PATH="$tmp_dir/devices" OMARCHY_DRM_PATH="$tmp_dir/drm" OMARCHY_DRI_BY_PATH="$tmp_dir/by-path" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH"
# nvidia.lua reads the video decode pins in ~/.config; keep the developer's own out of the test.
export HOME="$tmp_dir/home"
mkdir -p "$HOME"

# Exit statuses, expected NVD_BACKEND/LIBVA/GLX/Vulkan-disable/EGL-vendors values, then
# vendor:device:class[:boot_vga].
while IFS='|' read -r description nvidia gsp without_gsp display expected_env devices; do
  rm -rf "$tmp_dir/devices" "$tmp_dir/by-path"
  mkdir -p "$tmp_dir/devices" "$tmp_dir/by-path"
  slot=0
  for spec in $devices; do
    IFS=: read -r vendor device class boot_vga <<<"$spec"
    device_dir="$tmp_dir/devices/$slot"
    mkdir -p "$device_dir"
    printf '%s\n' "$vendor" >"$device_dir/vendor"
    printf '%s\n' "$device" >"$device_dir/device"
    printf '%s\n' "$class" >"$device_dir/class"
    : >"$tmp_dir/by-path/pci-$slot-render"
    if [[ -n $boot_vga ]]; then
      printf '%s\n' "$boot_vga" >"$device_dir/boot_vga"
    fi
    slot=$((slot + 1))
  done

  for check in "nvidia:$nvidia" "nvidia-gsp:$gsp" "nvidia-without-gsp:$without_gsp" "nvidia-display:$display"; do
    status=0
    "omarchy-hw-${check%:*}" || status=$?
    [[ $status == "${check#*:}" ]] || fail "$description: ${check%:*}" "expected ${check#*:}, got $status"
  done

  # Run the real Lua config and detectors; capture only Hyprland's env calls.
  actual_env=$(lua <<'LUA'
package.path = os.getenv("ROOT") .. "/?.lua;" .. package.path
require("default.hypr.helpers")
local env = {}
hl = { env = function(key, value) env[key] = value end, on = function() end, exec_cmd = function() end,
  dsp = { exec_cmd = function(command) return command end } }
require("default.hypr.desktop-gpu-pins")
require("default.hypr.nvidia")
-- Hyprland's own environment (its renderer loads the EGL vendors from it) never
-- carries the pins.
if env.VK_LOADER_DRIVERS_DISABLE or env.__EGL_VENDOR_LIBRARY_FILENAMES or env.OMARCHY_DESKTOP_GPU_PINS then
  print("pins set for Hyprland itself")
end
-- What it starts does: run a key binding's command and read its environment.
local pipe = io.popen(hl.dsp.exec_cmd(
  [[printf '%s|%s|%s' "${VK_LOADER_DRIVERS_DISABLE:--}" "${__EGL_VENDOR_LIBRARY_FILENAMES:--}" "${OMARCHY_DESKTOP_GPU_PINS:-}"]]))
local vk, egl, named = pipe:read("*a"):match("^(.-)|(.-)|(.*)$")
pipe:close()
egl = egl:gsub("/usr/share/glvnd/egl_vendor.d/", "")
print(table.concat({ env.NVD_BACKEND or "-", env.LIBVA_DRIVER_NAME or "-", env.__GLX_VENDOR_LIBRARY_NAME or "-",
  vk, egl }, " "))
-- The pins are named for bash and autostart.lua exactly when they are set.
local pinned = named == "VK_LOADER_DRIVERS_DISABLE __EGL_VENDOR_LIBRARY_FILENAMES" and o.desktop_gpu_pins ~= nil
if pinned ~= (vk ~= "-") then print("pins named wrongly") end
LUA
  )
  [[ $actual_env == "$expected_env" ]] || fail "$description: driver environment" "expected $expected_env, got $actual_env"
  pass "$description"
done <<'CASES'
AMD only|1|1|1|1|- - - - -|0x1002:0x15e7:0x030000:1
NVIDIA audio only|1|1|1|0|- - - - -|0x10de:0x228e:0x040300
No PCI devices|1|1|1|0|- - - - -|
Turing (first GSP)|0|0|1|0|direct nvidia nvidia - -|0x10de:0x1f91:0x030000
Volta (last without GSP)|0|1|0|0|egl - nvidia - -|0x10de:0x1d81:0x030000
Maxwell (first 580xx)|0|1|0|0|egl - nvidia - -|0x10de:0x1340:0x030000
Kepler (unsupported)|0|1|1|0|- - - - -|0x10de:0x1004:0x030000
AMD display with Ampere offload|0|0|1|1|direct - - *nvidia* 50_mesa.json|0x1002:0x15bf:0x030000:1 0x10de:0x25ac:0x030200:0
Intel display with Maxwell offload|0|1|0|1|egl - - - -|0x8086:0x46a6:0x030000:1 0x10de:0x1340:0x030000:0
NVIDIA display with inactive iGPU|0|0|1|0|direct nvidia nvidia - -|0x1002:0x15bf:0x030000:0 0x10de:0x2c02:0x030000:1
Hybrid without boot_vga|0|0|1|0|direct nvidia nvidia - -|0x1002:0x15e7:0x030000 0x10de:0x2560:0x030200
Non-VGA AMD display with Blackwell VGA offload|0|0|1|0|direct - - *nvidia* 50_mesa.json|0x1002:0x1114:0x038000 0x10de:0x2d59:0x030000:0
Non-VGA AMD display with Ampere 3D offload|0|0|1|0|direct nvidia nvidia - -|0x1002:0x1114:0x038000 0x10de:0x25ac:0x030200
CASES

# A session started before this change still carries LIBVA_DRIVER_NAME=nvidia
# on a hybrid whose iGPU has no boot_vga; only a reboot clears Hyprland's env.
rm -rf "$tmp_dir/devices" "$tmp_dir/by-path"
mkdir -p "$tmp_dir/devices/0000:64:00.0" "$tmp_dir/devices/0000:65:00.0" "$tmp_dir/by-path"
printf '0x10de\n' >"$tmp_dir/devices/0000:64:00.0/vendor"
printf '0x030000\n' >"$tmp_dir/devices/0000:64:00.0/class"
printf '0\n' >"$tmp_dir/devices/0000:64:00.0/boot_vga"
printf '0x1002\n' >"$tmp_dir/devices/0000:65:00.0/vendor"
printf '0x038000\n' >"$tmp_dir/devices/0000:65:00.0/class"
: >"$tmp_dir/by-path/pci-0000:65:00.0-render"

migration=$(grep -l 'Stop forcing NVIDIA VA-API on hybrids whose iGPU' "$ROOT"/migrations/*.sh)
for libva in nvidia ""; do
  rm -rf "$tmp_dir/home"
  mkdir -p "$tmp_dir/home"
  HOME="$tmp_dir/home" LIBVA_DRIVER_NAME=$libva bash -euo pipefail "$migration" >/dev/null
  if [[ $libva == "nvidia" ]]; then
    [[ -f $tmp_dir/home/.local/state/omarchy/reboot-required ]] ||
      fail "the migration asks for a reboot while the session still forces NVIDIA VA-API"
  else
    [[ ! -e $tmp_dir/home/.local/state/omarchy/reboot-required ]] ||
      fail "the migration leaves a session without the NVIDIA override alone"
  fi
done
pass "the migration asks for a reboot only while the old NVIDIA override is live"

# The same for __GLX_VENDOR_LIBRARY_NAME=nvidia, which Hyprland stopped setting
# there later.
migration=$(grep -l 'Stop forcing NVIDIA GLX on hybrids whose iGPU' "$ROOT"/migrations/*.sh)
for glx in nvidia ""; do
  rm -rf "$tmp_dir/home"
  mkdir -p "$tmp_dir/home"
  HOME="$tmp_dir/home" __GLX_VENDOR_LIBRARY_NAME=$glx bash -euo pipefail "$migration" >/dev/null
  if [[ $glx == "nvidia" ]]; then
    [[ -f $tmp_dir/home/.local/state/omarchy/reboot-required ]] ||
      fail "the migration asks for a reboot while the session still forces NVIDIA GLX"
  else
    [[ ! -e $tmp_dir/home/.local/state/omarchy/reboot-required ]] ||
      fail "the migration leaves a session without the NVIDIA GLX override alone"
  fi
done
pass "the migration asks for a reboot only while the old NVIDIA GLX override is live"

# A session started before the GPU pins doesn't carry them yet.
migration=$(grep -l 'Keep the NVIDIA GPU asleep while apps start' "$ROOT"/migrations/*.sh)
printf '0x2d59\n' >"$tmp_dir/devices/0000:64:00.0/device"
mkdir -p "$tmp_dir/state-bin"
cat >"$tmp_dir/state-bin/omarchy-state" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_STATE_LOG"
SH
chmod +x "$tmp_dir/state-bin/omarchy-state"
for pinned in "" "VK_LOADER_DRIVERS_DISABLE __EGL_VENDOR_LIBRARY_FILENAMES"; do
  : >"$tmp_dir/state.log"
  PATH="$tmp_dir/state-bin:$PATH" OMARCHY_TEST_STATE_LOG="$tmp_dir/state.log" OMARCHY_DESKTOP_GPU_PINS=$pinned \
    bash -euo pipefail "$migration" >/dev/null
  if [[ -z $pinned ]]; then
    grep -Fxq "set reboot-required" "$tmp_dir/state.log" ||
      fail "the GPU pin migration asks for a reboot while the session lacks the pins"
  elif [[ -s $tmp_dir/state.log ]]; then
    fail "the GPU pin migration leaves a pinned session alone"
  fi
done
pass "the GPU pin migration asks for a reboot only while the session lacks the pins"

# A session started with the pins set for Hyprland itself needs a reboot before
# a monitor on the NVIDIA GPU's ports can appear.
migration=$(grep -l 'Let an HDMI monitor on the NVIDIA GPU of a hybrid appear' "$ROOT"/migrations/*.sh)
for pinned in "" "VK_LOADER_DRIVERS_DISABLE __EGL_VENDOR_LIBRARY_FILENAMES"; do
  : >"$tmp_dir/state.log"
  PATH="$tmp_dir/state-bin:$PATH" OMARCHY_TEST_STATE_LOG="$tmp_dir/state.log" OMARCHY_DESKTOP_GPU_PINS=$pinned \
    bash -euo pipefail "$migration" >/dev/null
  if [[ -n $pinned ]]; then
    grep -Fxq "set reboot-required" "$tmp_dir/state.log" ||
      fail "the HDMI migration asks for a reboot while Hyprland carries the old pins"
  elif [[ -s $tmp_dir/state.log ]]; then
    fail "the HDMI migration leaves a session without the pins alone"
  fi
done
pass "the HDMI migration asks for a reboot only while Hyprland carries the old pins"

# What systemd starts (a game launcher at login) gets every GPU: autostart
# takes the desktop's pins back out of the activation environment.
activation=$(lua <<'LUA'
package.path = os.getenv("ROOT") .. "/?.lua;" .. package.path
require("default.hypr.helpers")
local handlers, cmds = {}, {}
hl = { env = function() end, on = function(event, fn) handlers[event] = fn end,
  exec_cmd = function(cmd) table.insert(cmds, cmd) end, dsp = { exec_cmd = function(cmd) return cmd end } }
require("default.hypr.desktop-gpu-pins")
require("default.hypr.nvidia")
require("default.hypr.autostart")
handlers["hyprland.start"]()
for _, cmd in ipairs(cmds) do
  local activation = cmd:match("dbus%-update%-activation%-environment.*")
  if activation then print(activation) end
end
LUA
)
[[ $activation == "dbus-update-activation-environment --systemd --all && systemctl --user unset-environment VK_LOADER_DRIVERS_DISABLE __EGL_VENDOR_LIBRARY_FILENAMES" ]] ||
  fail "autostart keeps the desktop's GPU pins out of the systemd user environment" "$activation"
pass "autostart keeps the desktop's GPU pins out of the systemd user environment"

# Exec rules stay at the front of the command, where Hyprland reads them, and
# every way Hyprland runs a command gets the pins.
wrapped=$(lua <<'LUA'
package.path = os.getenv("ROOT") .. "/?.lua;" .. package.path
require("default.hypr.helpers")
local ran, rules = {}, {}
hl = { env = function() end, exec_cmd = function(cmd) table.insert(ran, cmd) end,
  workspace_rule = function(rule) table.insert(rules, rule) end,
  dsp = { exec_cmd = function(cmd) return cmd end, exec_raw = function(cmd) return cmd end } }
require("default.hypr.desktop-gpu-pins")
require("default.hypr.desktop-gpu-pins")
hl.exec_cmd("app")
local rule = { workspace = "special:scratchpad", on_created_empty = "app" }
hl.workspace_rule(rule)
hl.workspace_rule({ workspace = "3", gaps_in = 0 })
print(hl.dsp.exec_cmd("[workspace 2 silent] app --flag"))
print(hl.dsp.exec_raw("app"))
print(ran[1])
print(rules[1].on_created_empty)
print(rule.on_created_empty, rules[2].on_created_empty, rules[2].gaps_in)
LUA
)
expected_prefix="export VK_LOADER_DRIVERS_DISABLE='*nvidia*' __EGL_VENDOR_LIBRARY_FILENAMES='/usr/share/glvnd/egl_vendor.d/50_mesa.json' OMARCHY_DESKTOP_GPU_PINS='VK_LOADER_DRIVERS_DISABLE __EGL_VENDOR_LIBRARY_FILENAMES'; "
expected_wrapped="[workspace 2 silent] ${expected_prefix} app --flag
${expected_prefix}app
${expected_prefix}app
${expected_prefix}app
app	nil	0"
[[ $wrapped == "$expected_wrapped" ]] ||
  fail "every command Hyprland runs gets the pins, exec rules first, wrapped once" "$wrapped"
pass "every command Hyprland runs gets the pins, exec rules first, wrapped once"
