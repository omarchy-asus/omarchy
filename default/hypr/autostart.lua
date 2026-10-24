require("default.hypr.startup-cursor")

hl.on("hyprland.start", function()
  -- Applications inherit the user's cursor; only the compositor starts blank.
  if omarchy_startup_cursor_pending then
    hl.env("XCURSOR_PATH", omarchy_startup_cursor.path)
    hl.env("XCURSOR_THEME", omarchy_startup_cursor.xcursor)
  end

  -- Slow app launch fix -- set systemd and D-Bus activation vars before
  -- starting session services.
  -- The desktop's GPU pins (desktop-gpu-pins.lua), which this command gets
  -- like any other, stay out of it, so what systemd starts, a game launcher
  -- at login included, has every GPU.
  local activation = "dbus-update-activation-environment --systemd --all"
  if o.desktop_gpu_pins then
    activation = activation .. " && systemctl --user unset-environment " .. table.concat(o.desktop_gpu_pins, " ")
  end
  hl.exec_cmd(activation)

  hl.exec_cmd("omarchy-launch-shell")
  hl.exec_cmd("omarchy-provision-first-run")
  hl.exec_cmd("omarchy-powerprofiles-init")
  hl.exec_cmd(o.launch("omarchy-hyprland-monitor-watch"))
  hl.exec_cmd(o.launch("udiskie --automount --no-notify --no-tray"))

  -- Start the herdr server inside the graphical session so its panes inherit
  -- WAYLAND_DISPLAY. Otherwise the first SSH login from a remote herdr starts
  -- it with a tty environment, and agents in its panes can't read the clipboard.
  hl.exec_cmd(o.launch("herdr server"))

  -- Run post-boot hooks after startup config has loaded.
  hl.exec_cmd("sleep 2 && omarchy-hook post-boot")
end)
