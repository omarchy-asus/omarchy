# Show an OSD when Fn+Super locks or unlocks Super on the ASUS ROG N-Key keyboard.
#
# The lock lives in the keyboard firmware, and while it is on Super does nothing
# with no sign of why. The rule gives the desktop user the keyboard's hidraw
# nodes and the user unit, enabled for every user of this machine, watches them.
# The OSD needs a kernel whose hid-asus passes the Win-lock reports through
# ("HID: asus: pass through ROG N-Key Win-lock reports"); stock hid-asus drops
# them, and then the watcher sees nothing, while omarchy-hw-asus-rog-winlock
# lock, unlock and status still work.

if omarchy-hw-asus-rog-nkey; then
  sudo install -Dm644 "$OMARCHY_PATH/default/udev/asus-rog-winlock.rules" /etc/udev/rules.d/70-asus-rog-winlock.rules
  sudo install -Dm644 "$OMARCHY_PATH/default/systemd/user/omarchy-asus-rog-winlock.service" /etc/systemd/user/omarchy-asus-rog-winlock.service
  sudo systemctl --global enable omarchy-asus-rog-winlock.service
fi
