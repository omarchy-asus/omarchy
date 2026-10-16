# On a hybrid laptop whose iGPU drives the display, pin mpv and the
# Chromium-family flags files this user already has to the iGPU's render node,
# so playing video does not wake the NVIDIA GPU.
source "$OMARCHY_INSTALL/helpers/hybrid-video-decode.sh"

if render_node=$(omarchy-hw-igpu-render-node); then
  echo "Detected a hybrid GPU with the display on the iGPU. Decoding video on $render_node."
  hybrid_video_pin_mpv
  hybrid_video_pin_chromium
fi
