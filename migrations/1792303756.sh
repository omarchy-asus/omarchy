echo "Show an OSD when Fn+Super locks or unlocks Super on ASUS ROG N-Key keyboards"

if omarchy-hw-asus-rog-nkey; then
  source "$OMARCHY_PATH/install/hardware/asus/rog-winlock.sh"

  # Re-run the rules for the keyboard so its hidraw nodes get the seat user's
  # ACL now rather than at the next boot.
  sudo udevadm control --reload
  sudo udevadm trigger --action=change --subsystem-match=hidraw
  sudo udevadm settle

  # Nothing to start into over SSH or from a TTY; the next graphical login
  # starts the globally enabled unit. A failed start only delays the OSD.
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  if systemctl --user is-active --quiet graphical-session.target; then
    systemctl --user start omarchy-asus-rog-winlock.service >/dev/null 2>&1 || true
  fi
fi
