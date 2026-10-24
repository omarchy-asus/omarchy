echo "Keep the NVIDIA GPU asleep while apps start on hybrids whose iGPU drives the display"

# Hyprland now keeps NVIDIA's Vulkan driver and EGL vendor out of the desktop
# there, so listing GPUs at app startup no longer wakes the dGPU. Games still
# get them: from a shell, at login, from the app launcher as a game, or through
# omarchy-launch-all-gpus. Hyprland applies env at startup, so a running session
# needs a reboot.
if [[ -z ${OMARCHY_DESKTOP_GPU_PINS:-} ]] && omarchy-hw-nvidia-gsp && omarchy-hw-igpu-render-node >/dev/null; then
  omarchy-state set reboot-required
  echo "Reboot to keep the NVIDIA GPU asleep while apps start; games still use it."
fi
