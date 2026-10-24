echo "Keep the NVIDIA GPU asleep while apps start on hybrids whose iGPU drives the display"

# Hyprland now keeps NVIDIA's Vulkan driver and EGL vendor out of the session
# there, so listing GPUs at app startup no longer wakes the dGPU. The
# app launcher gives entries that prefer the discrete GPU (Steam) every GPU.
# Hyprland applies env at startup, so a running session needs a reboot.
if [[ -z ${VK_LOADER_DRIVERS_DISABLE:-} ]] && omarchy-hw-nvidia-gsp && omarchy-hw-igpu-render-node >/dev/null; then
  omarchy-state set reboot-required
  echo "Reboot to keep the NVIDIA GPU asleep while apps start. Start Steam from the app launcher,"
  echo "and other game launchers with omarchy-launch-all-gpus, so their games can use it."
fi
