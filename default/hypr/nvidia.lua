local paths = require("default.hypr.paths")

local nvidia = paths.omarchy_path .. "/bin/omarchy-hw-nvidia"
local nvidia_display = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-display"
local nvidia_gsp = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-gsp"
local nvidia_without_gsp = paths.omarchy_path .. "/bin/omarchy-hw-nvidia-without-gsp"
local igpu_render_node = paths.omarchy_path .. "/bin/omarchy-hw-igpu-render-node"

-- Video decode pins (install/helpers/hybrid-video-decode.sh) name the iGPU's
-- render node by PCI path. True when one names a device that is gone or is not
-- a non-NVIDIA display device any more: a MUX switch, an iGPU turned off in
-- firmware, a BIOS update that moved the address. Reads the config files and
-- cached sysfs IDs only, never a device node.
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
      for line in file:lines() do
        local address = line:match("^%s*%-%-render%-node%-override=%S*/by%-path/pci%-(.-)%-render%s*$")
          or line:match("^%s*%-?%-?vaapi%-device%s*=%s*%S*/by%-path/pci%-(.-)%-render%s*$")
        if address then
          local vendor = first_line(devices .. "/" .. address .. "/vendor")
          local class = first_line(devices .. "/" .. address .. "/class")
          if not vendor or vendor == "0x10de" or not class or not class:match("^0x03") then
            file:close()
            return true
          end
        end
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
  if o.shell_succeeds(o.shell_quote(nvidia_gsp)) then
    hl.env("NVD_BACKEND", "direct")
    if nvidia_is_display then
      -- An iGPU that is a non-VGA display controller (AMD Krackan) has no
      -- boot_vga, so the display check still answers NVIDIA and GLX stays on
      -- it for OpenGL games. Video decode belongs on that iGPU, though: forcing
      -- NVIDIA's VA-API there wakes the dGPU for every video.
      if not o.shell_succeeds(o.shell_quote(igpu_render_node)) then
        hl.env("LIBVA_DRIVER_NAME", "nvidia")
      end
      hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
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
end
