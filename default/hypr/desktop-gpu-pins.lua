local paths = require("default.hypr.paths")

-- The open NVIDIA driver resumes a runtime-suspended GPU for every call into
-- it, even one that only asks which GPUs exist. On a hybrid whose iGPU drives
-- the display (Turing and newer), any app that lists Vulkan devices or opens
-- surfaceless EGL at startup (GTK, Chromium, Electron) woke the dGPU for about
-- 20 seconds, whichever GPU it went on to use. Keep NVIDIA's Vulkan driver and
-- EGL vendor out of the desktop: the shell, the launcher, key bindings and the
-- apps they start (GLVND asks every listed EGL vendor for its devices, whatever
-- their order).
--
-- Only what Hyprland starts gets the pins, never Hyprland itself: aquamarine
-- opens EGL on the dGPU for a monitor on its ports (HDMI), plugged in at login
-- or later. So instead of hl.env, every command Hyprland runs (hl.exec_cmd,
-- hl.dsp.exec_cmd, hl.dsp.exec_raw and a workspace rule's on_created_empty, so
-- key bindings, autostart and hyprctl dispatch too) exports them in its own
-- shell first. This runs before any binding or rule is made.
--
-- Games get them back however they start: autostart.lua keeps them out of the
-- systemd user environment, so a game launcher started at login has every GPU;
-- an interactive bash drops them (default/bash/envs); the app launcher starts
-- game entries without them (omarchy-launch-desktop-entry); and anything else
-- can run through omarchy-launch-all-gpus. OMARCHY_DESKTOP_GPU_PINS names them.
local function hybrid_igpu_display()
  return o.shell_succeeds(o.shell_quote(paths.omarchy_path .. "/bin/omarchy-hw-nvidia-gsp"))
    and o.shell_succeeds(o.shell_quote(paths.omarchy_path .. "/bin/omarchy-hw-igpu-render-node"))
end

if not hybrid_igpu_display() then return end

local pins = {
  { "VK_LOADER_DRIVERS_DISABLE", "*nvidia*" },
  { "__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json" },
}
o.desktop_gpu_pins = {}
local exports = {}
for _, pin in ipairs(pins) do
  table.insert(o.desktop_gpu_pins, pin[1])
  table.insert(exports, pin[1] .. "=" .. o.shell_quote(pin[2]))
end
table.insert(exports, "OMARCHY_DESKTOP_GPU_PINS=" .. o.shell_quote(table.concat(o.desktop_gpu_pins, " ")))
local prefix = "export " .. table.concat(exports, " ") .. "; "

-- Exec rules ("[workspace 2] app") stay at the front, where Hyprland reads them.
function o.with_desktop_gpu_pins(command)
  local rules, rest = command:match("^%s*(%[[^%]]*%])(.*)$")
  if rules then return rules .. " " .. prefix .. rest end
  return prefix .. command
end

-- A config reload may keep hl as it was: wrap it once.
if hl.omarchy_desktop_gpu_pins then return end
local function wrap(functions, name)
  local run = functions and functions[name]
  if run then
    functions[name] = function(command, ...) return run(o.with_desktop_gpu_pins(command), ...) end
  end
end
wrap(hl, "exec_cmd")
wrap(hl.dsp, "exec_cmd")
wrap(hl.dsp, "exec_raw")
-- A workspace rule's on_created_empty command is run by Hyprland too.
local workspace_rule = hl.workspace_rule
if workspace_rule then
  hl.workspace_rule = function(rule, ...)
    if type(rule) == "table" and type(rule.on_created_empty) == "string" and rule.on_created_empty ~= "" then
      local pinned = {}
      for key, value in pairs(rule) do pinned[key] = value end
      pinned.on_created_empty = o.with_desktop_gpu_pins(rule.on_created_empty)
      rule = pinned
    end
    return workspace_rule(rule, ...)
  end
end
hl.omarchy_desktop_gpu_pins = true
