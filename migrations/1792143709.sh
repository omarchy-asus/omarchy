echo "Stop forcing NVIDIA VA-API on hybrids whose iGPU is not VGA class"

# On a hybrid whose iGPU is a non-VGA display controller (AMD Krackan), Hyprland
# no longer sets LIBVA_DRIVER_NAME=nvidia; NVIDIA's GLX stays for OpenGL games.
# Hyprland applies env at startup, so a session that still carries the old
# override needs a reboot to drop it.
if [[ ${LIBVA_DRIVER_NAME:-} == "nvidia" ]] && omarchy-hw-igpu-render-node >/dev/null; then
  omarchy-state set reboot-required
  echo "Reboot to decode video on the integrated GPU instead of NVIDIA."
fi
