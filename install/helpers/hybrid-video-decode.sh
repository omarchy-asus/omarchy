# On a hybrid laptop whose iGPU drives the display, video players and browsers
# that let libva or Chromium choose a render node can decode on the NVIDIA GPU
# instead: render nodes are numbered in PCI order, which puts the dGPU first on
# some machines, and the numbers can change between boots. Each video then
# wakes the runtime-suspended dGPU for work the iGPU's video engine does at a
# fraction of the power. Pin mpv and Chromium-family browsers to the iGPU by
# the stable path omarchy-hw-igpu-render-node prints. Every other machine is
# left alone, and so is any setting the user already has.

HYBRID_VIDEO_CHROMIUM_FLAGS_FILES=(
  "$HOME/.config/chromium-flags.conf"
  "$HOME/.config/chrome-flags.conf"
  "$HOME/.config/microsoft-edge-stable-flags.conf"
  "$HOME/.config/brave-flags.conf"
  "$HOME/.config/brave-origin-flags.conf"
)

HYBRID_VIDEO_MPV_CONF="$HOME/.config/mpv/mpv.conf"

# Appends --render-node-override to the flags files given, or to every
# Chromium-family flags file Omarchy seeds. Only files the user already has.
hybrid_video_pin_chromium() {
  local node conf
  local -a confs=("$@")

  (( ${#confs[@]} )) || confs=("${HYBRID_VIDEO_CHROMIUM_FLAGS_FILES[@]}")

  node=$(omarchy-hw-igpu-render-node) || return 0

  for conf in "${confs[@]}"; do
    [[ -f $conf ]] || continue
    grep -q -- '^[[:space:]]*--render-node-override=' "$conf" && continue
    [[ -s $conf && -n $(tail -c1 "$conf") ]] && echo >>"$conf"
    echo "--render-node-override=$node" >>"$conf"
  done
}

# Whether mpv.conf sets an option outside any [profile] section.
hybrid_video_mpv_sets() {
  [[ -f $HYBRID_VIDEO_MPV_CONF ]] &&
    awk -v option="$1" '
      /^[[:space:]]*\[/ { exit }
      $0 ~ "^[[:space:]]*(--)?" option "[[:space:]]*=" { found = 1; exit }
      END { exit !found }
    ' "$HYBRID_VIDEO_MPV_CONF"
}

# Decodes through VA-API on the iGPU. hwdec=auto-safe from /etc/mpv/mpv.conf
# can settle on NVDEC, which loads CUDA and wakes the dGPU. The options go at
# the top of ~/.config/mpv/mpv.conf, ahead of any [profile] section, and only
# those the user has not set.
hybrid_video_pin_mpv() {
  local node existing=""
  local -a options=()

  node=$(omarchy-hw-igpu-render-node) || return 0

  hybrid_video_mpv_sets hwdec || options+=("hwdec=vaapi")
  hybrid_video_mpv_sets vaapi-device || options+=("vaapi-device=$node")
  (( ${#options[@]} )) || return 0

  mkdir -p "$(dirname "$HYBRID_VIDEO_MPV_CONF")"
  if [[ -f $HYBRID_VIDEO_MPV_CONF ]]; then
    existing=$(<"$HYBRID_VIDEO_MPV_CONF")
  fi

  # Rewrite in place, which keeps a symlinked config pointing where it did.
  {
    echo "# Decode video on the integrated GPU that drives the display, so the NVIDIA GPU can stay asleep."
    printf '%s\n' "${options[@]}"
    if [[ -n $existing ]]; then
      printf '\n%s\n' "$existing"
    fi
  } >"$HYBRID_VIDEO_MPV_CONF"
}
