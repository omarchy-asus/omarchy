require("default.hypr.startup-cursor")

hl.on("hyprland.start", function()
  -- Applications inherit the user's cursor; only the compositor starts blank.
  if omarchy_startup_cursor_pending then
    hl.env("XCURSOR_PATH", omarchy_startup_cursor.path)
    hl.env("XCURSOR_THEME", omarchy_startup_cursor.xcursor)
  end

  -- The desktop's GPU pins (nvidia.lua) reach what Hyprland starts from now
  -- on, never Hyprland's own renderer: it has already loaded its EGL vendors.
  local pin_names = {}
  for _, pin in ipairs(o.desktop_gpu_pins or {}) do
    hl.env(pin[1], pin[2])
    table.insert(pin_names, pin[1])
  end
  if #pin_names > 0 then
    hl.env("OMARCHY_DESKTOP_GPU_PINS", table.concat(pin_names, " "))
  end

  -- Slow app launch fix -- set systemd and D-Bus activation vars before
  -- starting session services.
  -- The desktop's GPU pins stay out of it, so what systemd starts, a game
  -- launcher at login included, has every GPU.
  local activation = "dbus-update-activation-environment --systemd --all"
  if #pin_names > 0 then
    activation = activation .. " && systemctl --user unset-environment " .. table.concat(pin_names, " ")
  end
  hl.exec_cmd(activation)

  hl.exec_cmd("omarchy-launch-shell")
  hl.exec_cmd("omarchy-provision-first-run")
  hl.exec_cmd("omarchy-powerprofiles-init")
  hl.exec_cmd(o.launch("omarchy-hyprland-monitor-watch"))
  hl.exec_cmd(o.launch("udiskie --automount --no-notify --no-tray"))

  -- Run post-boot hooks after startup config has loaded.
  hl.exec_cmd("sleep 2 && omarchy-hook post-boot")
end)
