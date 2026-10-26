local paths = require("default.hypr.paths")

local nvidia = paths.omarchy_path .. "/bin/omarchy-hw-nvidia"
local nvidia_display = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-display"
local nvidia_gsp = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-gsp"
local nvidia_without_gsp = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-without-gsp"
local igpu_render_node = paths.omarchy_path .. "/bin/omarchy-hw-igpu-render-node"

-- Video decode pins (install/helpers/hybrid-video-decode.sh) name the iGPU's
-- render node by PCI path. True when one Omarchy wrote (the line right under
-- its marker comment) names a device that is gone or is not a non-NVIDIA
-- display device any more: a MUX switch, an iGPU turned off in firmware, a BIOS
-- update that moved the address. A render node the user set is theirs, even the
-- NVIDIA GPU's. Reads the config files and cached sysfs IDs only, never a
-- device node.
local hybrid_video_pin_marker =
  "# Omarchy repins the next line if the iGPU moves. Delete this comment to keep the line as your own."
local function hybrid_video_pin_stale()
  local home = os.getenv("HOME") or ""
  local devices = os.getenv("OMARCHY_PCI_DEVICES_PATH") or "/sys/bus/pci/devices"
  local function first_line(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local line = file:read("*l")
    file:close()
    return line
  end
  local files = { "/.config/mpv/mpv.conf", "/.config/chromium-flags.conf", "/.config/chrome-flags.conf",
    "/.config/microsoft-edge-stable-flags.conf", "/.config/brave-flags.conf", "/.config/brave-origin-flags.conf" }
  for _, name in ipairs(files) do
    local file = io.open(home .. name, "r")
    if file then
      local marked = false
      for line in file:lines() do
        local address = marked and (line:match("^%s*%-%-render%-node%-override=%S*/by%-path/pci%-(.-)%-render%s*$")
          or line:match("^%s*%-?%-?vaapi%-device%s*=%s*%S*/by%-path/pci%-(.-)%-render%s*$"))
        if address then
          local vendor = first_line(devices .. "/" .. address .. "/vendor")
          local class = first_line(devices .. "/" .. address .. "/class")
          if not vendor or vendor == "0x10de" or not class or not class:match("^0x03") then
            file:close()
            return true
          end
        end
        marked = line == hybrid_video_pin_marker
      end
      file:close()
    end
  end
  return false
end

-- These detectors read cached sysfs IDs rather than shelling out to lspci.
-- lspci reads PCI config space, which resumes a runtime-suspended GPU, and on a
-- hybrid laptop that wake alone outlasts Hyprland's 1.5s config reload budget.
if o.shell_succeeds(o.shell_quote(nvidia)) then
  -- On hybrid laptops the display is wired to the iGPU, so forcing NVIDIA's
  -- VA-API/GLX drivers globally breaks Chromium-based browsers (black video).
  -- Only apply those when NVIDIA actually drives the display.
  local nvidia_is_display = o.shell_succeeds(o.shell_quote(nvidia_display))
  local igpu_drives_display = o.shell_succeeds(o.shell_quote(igpu_render_node))
  if o.shell_succeeds(o.shell_quote(nvidia_gsp)) then
    hl.env("NVD_BACKEND", "direct")
    -- An iGPU that is a non-VGA display controller (AMD Krackan) has no
    -- boot_vga, so the display check still answers NVIDIA there. That iGPU
    -- drives the panel, though: forcing NVIDIA's VA-API or GLX on the session
    -- wakes the dGPU for every video and keeps it awake for any GLX app (the
    -- Steam client). Games ask for the dGPU themselves: DXVK picks it, and
    -- native OpenGL games run with PRIME render offload (prime-run).
    if nvidia_is_display and not igpu_drives_display then
      hl.env("LIBVA_DRIVER_NAME", "nvidia")
      hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    end
    -- The open driver resumes a runtime-suspended GPU for every call into it,
    -- even one that only asks which GPUs exist. With the iGPU driving the
    -- display, any app that lists Vulkan devices or opens surfaceless EGL at
    -- startup (GTK, Chromium, Electron) woke the dGPU for about 20 seconds,
    -- whichever GPU it went on to use. Keep NVIDIA's Vulkan driver and EGL
    -- vendor out of the desktop: the shell, the launcher, key bindings and the
    -- apps they start (GLVND asks every listed EGL vendor for its devices,
    -- whatever their order). Games get them back however they start: the
    -- variables stay out of the systemd user environment (autostart.lua), so
    -- a game launcher started at login has every GPU; an interactive bash
    -- drops them (default/bash/envs); the app launcher starts game entries
    -- without them (omarchy-launch-desktop-entry); and anything else can run
    -- through omarchy-launch-all-gpus. OMARCHY_DESKTOP_GPU_PINS names them.
    -- Hyprland itself keeps NVIDIA's EGL vendor: a monitor on the dGPU's ports
    -- (HDMI) needs it, plugged in at login or later. So autostart.lua sets the
    -- pins once Hyprland has started, after its renderer has loaded the EGL
    -- vendors (GLVND reads the list once per process).
    if igpu_drives_display then
      o.desktop_gpu_pins = {
        { "VK_LOADER_DRIVERS_DISABLE", "*nvidia*" },
        { "__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json" },
      }
    end
  elseif o.shell_succeeds(o.shell_quote(nvidia_without_gsp)) then
    hl.env("NVD_BACKEND", "egl")
    if nvidia_is_display then
      hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    end
  end

  if hybrid_video_pin_stale() then
    o.exec_on_start("omarchy-refresh-hybrid-video")
  end

  require("default.hypr.hybrid-cursor")
end
