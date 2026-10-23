echo "Stop forcing NVIDIA GLX on hybrids whose iGPU is not VGA class"

# On a hybrid whose iGPU is a non-VGA display controller (AMD Krackan), Hyprland
# no longer sets __GLX_VENDOR_LIBRARY_NAME=nvidia, so plain GLX apps stay on the
# iGPU; native OpenGL games run on NVIDIA with PRIME render offload. Hyprland
# applies env at startup, so a session that still carries the old override needs
# a reboot to drop it.
if [[ ${__GLX_VENDOR_LIBRARY_NAME:-} == "nvidia" ]] && omarchy-hw-igpu-render-node >/dev/null; then
  omarchy-state set reboot-required
  echo "Reboot to keep apps off NVIDIA. Native OpenGL games now need"
  echo "__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia %command% in their launch options."
fi
