echo "Let an HDMI monitor on the NVIDIA GPU of a hybrid appear when plugged in"

# The desktop's GPU pins used to be set for Hyprland itself, so it could not
# open EGL on the NVIDIA GPU and a monitor on its ports never appeared. Hyprland
# now sets them only for what it starts. A session started with the old pins
# keeps them until Hyprland restarts.
if [[ -n ${OMARCHY_DESKTOP_GPU_PINS:-} ]]; then
  omarchy-state set reboot-required
  echo "Reboot so a monitor plugged into the NVIDIA GPU's ports appears."
fi
