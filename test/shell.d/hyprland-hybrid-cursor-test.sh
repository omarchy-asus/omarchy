#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command lua

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
export OMARCHY_DRM_PATH="$tmp_dir/drm"

# card <index> <vendor> [connector...]
card() {
  local index=$1 vendor=$2 connector
  shift 2
  mkdir -p "$OMARCHY_DRM_PATH/card$index/device"
  printf '%s\n' "$vendor" >"$OMARCHY_DRM_PATH/card$index/device/vendor"
  for connector in "$@"; do
    mkdir -p "$OMARCHY_DRM_PATH/card$index-$connector"
    printf 'connected\n' >"$OMARCHY_DRM_PATH/card$index-$connector/status"
  done
}

# Loads the module under a stub hl, then runs the given steps. Each step is
# "start", "reload", "add:<name>", "remove:<name>", "user:<value>" (a value from
# the user's config) or "timers" (run pending one-shot timers). Prints the
# cursor value after every step, or "events=0" when nothing was registered.
run() {
  lua - "$@" <<'LUA'
package.path = os.getenv("ROOT") .. "/?.lua;" .. package.path
local monitors, handlers, timers, value = {}, {}, {}, 2
hl = {
  get_monitors = function()
    local list = {}
    for _, name in ipairs(monitors) do list[#list + 1] = { name = name } end
    return list
  end,
  get_config = function(key) assert(key == "cursor.no_hardware_cursors"); return value end,
  config = function(c) value = c.cursor.no_hardware_cursors end,
  on = function(event, fn) handlers[event] = handlers[event] or {}; table.insert(handlers[event], fn) end,
  timer = function(fn) table.insert(timers, fn) end,
}
local function fire(event) for _, fn in ipairs(handlers[event] or {}) do fn() end end
require("default.hypr.hybrid-cursor")
if next(handlers) == nil then print("events=0") return end
local out = {}
for _, step in ipairs(arg) do
  local verb, name = step:match("^(%a+):?(.*)$")
  if verb == "start" then fire("hyprland.start")
  elseif verb == "reload" then value = 2; fire("config.reloaded")
  elseif verb == "user" then value = tonumber(name); fire("config.reloaded")
  elseif verb == "add" then table.insert(monitors, name); fire("monitor.added")
  elseif verb == "remove" then
    for i, m in ipairs(monitors) do if m == name then table.remove(monitors, i) break end end
    fire("monitor.removed")
  elseif verb == "timers" then local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end
  end
  out[#out + 1] = tostring(value)
end
print(table.concat(out, " "))
LUA
}

expect() {
  local description=$1 expected=$2 actual
  shift 2
  actual=$(run "$@")
  [[ $actual == "$expected" ]] || fail "$description" "expected '$expected', got '$actual'"
  pass "$description"
}

card 0 0x1002 eDP-1
card 1 0x10de HDMI-A-1 DP-1
expect "hybrid: panel only keeps the hardware cursor" "2 2" start add:eDP-1
expect "hybrid: monitor on the NVIDIA card switches to a software cursor" "2 1 1" add:eDP-1 add:HDMI-A-1 timers
expect "hybrid: any NVIDIA connector counts, not just HDMI" "1" add:DP-1
expect "hybrid: unplugging it goes back to auto" "1 2 2" add:HDMI-A-1 remove:HDMI-A-1 timers
expect "hybrid: a reload with the monitor plugged in re-applies" "1 1" add:HDMI-A-1 reload
expect "hybrid: a value the user set is left alone" "0 0 0" user:0 add:HDMI-A-1 remove:HDMI-A-1

rm -rf "$OMARCHY_DRM_PATH"
card 0 0x10de HDMI-A-1 eDP-1
expect "NVIDIA only: nothing registered" "events=0"

rm -rf "$OMARCHY_DRM_PATH"
card 0 0x1002 eDP-1 HDMI-A-1
expect "no NVIDIA card: nothing registered" "events=0"

rm -rf "$OMARCHY_DRM_PATH"
expect "no DRM cards: nothing registered" "events=0"
