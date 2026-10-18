# On a hybrid laptop whose iGPU drives the display, video players and browsers
# that let libva or Chromium choose a render node can decode on the NVIDIA GPU
# instead: render nodes are numbered in PCI order, which puts the dGPU first on
# some machines, and the numbers can change between boots. Each video then
# wakes the runtime-suspended dGPU for work the iGPU's video engine does at a
# fraction of the power. Pin mpv and Chromium-family browsers to the iGPU by
# the stable path omarchy-hw-igpu-render-node prints. Every other machine is
# left alone, and so is any setting the user already has.
#
# Each pin goes under HYBRID_VIDEO_PIN_MARKER. Only a pin right under that line
# is Omarchy's to repin or remove later; any other render node setting, an
# unmarked pin an earlier version wrote included, is the user's and stays.

HYBRID_VIDEO_CHROMIUM_FLAGS_FILES=(
  "$HOME/.config/chromium-flags.conf"
  "$HOME/.config/chrome-flags.conf"
  "$HOME/.config/microsoft-edge-stable-flags.conf"
  "$HOME/.config/brave-flags.conf"
  "$HOME/.config/brave-origin-flags.conf"
)

HYBRID_VIDEO_MPV_CONF="$HOME/.config/mpv/mpv.conf"
HYBRID_VIDEO_MPV_COMMENT="# Decode video on the integrated GPU that drives the display, so the NVIDIA GPU can stay asleep."
# Keep in step with default/hypr/nvidia.lua, which looks for it too.
HYBRID_VIDEO_PIN_MARKER="# Omarchy repins the next line if the iGPU moves. Delete this comment to keep the line as your own."

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
    printf '%s\n--render-node-override=%s\n' "$HYBRID_VIDEO_PIN_MARKER" "$node" >>"$conf"
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

# Whether the user sets any of the options given anywhere mpv reads them: any
# section of mpv.conf, and any file pulled in with include= (mpv has no conf.d
# directory; include= is how a config is split up). Omarchy's own lines do not
# count: the block under HYBRID_VIDEO_MPV_COMMENT and a line under the marker.
# An include that cannot be read counts as a setting, since what it holds is
# unknown.
hybrid_video_mpv_user_sets() {
  local options conf include dir found
  local -a queue=("$HYBRID_VIDEO_MPV_CONF") seen=()
  local -i i=0
  options=$(IFS='|'; echo "$*")
  dir=$(dirname "$HYBRID_VIDEO_MPV_CONF")

  while (( i < ${#queue[@]} && i < 32 )); do
    conf=${queue[i]}
    i+=1
    [[ " ${seen[*]} " == *" $conf "* ]] && continue
    seen+=("$conf")
    if [[ ! -r $conf ]]; then
      (( i == 1 )) && continue
      return 0
    fi
    found=0
    while IFS= read -r include; do
      if [[ $include == set ]]; then
        found=1
        break
      fi
      case $include in
      \~\~/* | \~\~home/*) include="$dir/${include#*/}" ;;
      \~/*) include="$HOME/${include#\~/}" ;;
      /*) ;;
      *) include="$dir/$include" ;;
      esac
      queue+=("$include")
    done < <(awk -v options="$options" -v main=$(( i == 1 )) \
      -v comment="$HYBRID_VIDEO_MPV_COMMENT" -v marker="$HYBRID_VIDEO_PIN_MARKER" '
      main && $0 == comment { omarchy = 1; next }
      omarchy && (/^[[:space:]]*$/ || /^[[:space:]]*\[/) { omarchy = 0 }
      main && $0 == marker { held = 1; next }
      held { held = 0; next }
      omarchy { next }
      {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        if (line ~ /^(--)?include[[:space:]]*=/) {
          sub(/^(--)?include[[:space:]]*=[[:space:]]*/, "", line)
          # A quoted path ends at its closing quote; any other ends at a #.
          if (line ~ /^"[^"]*"/) line = substr(line, 2, index(substr(line, 2), "\"") - 1)
          else if (line ~ /^\047[^\047]*\047/) line = substr(line, 2, index(substr(line, 2), "\047") - 1)
          else { sub(/#.*/, "", line); sub(/[[:space:]]*$/, "", line) }
          if (line != "") print line
          next
        }
        sub(/#.*/, "", line)
        if (line ~ "^(--)?(" options ")[[:space:]]*(=|$)") { print "set"; exit }
      }' "$conf")
    (( found )) && return 0
  done
  return 1
}

# Decodes through VA-API on the iGPU. hwdec=auto-safe from /etc/mpv/mpv.conf
# can settle on NVDEC, which loads CUDA and wakes the dGPU. The options go at
# the top of ~/.config/mpv/mpv.conf, ahead of any [profile] section. A user who
# sets either one anywhere (see hybrid_video_mpv_user_sets) has set decode up
# their own way, and mpv is left alone. When the comment Omarchy writes above them is
# still there (a stale pin was dropped), they go back under it.
hybrid_video_pin_mpv() {
  local node existing="" out
  local -a options=()

  node=$(omarchy-hw-igpu-render-node) || return 0
  hybrid_video_mpv_user_sets hwdec vaapi-device && return 0

  hybrid_video_mpv_sets hwdec || options+=("hwdec=vaapi")
  hybrid_video_mpv_sets vaapi-device || options+=("$HYBRID_VIDEO_PIN_MARKER" "vaapi-device=$node")
  (( ${#options[@]} )) || return 0

  mkdir -p "$(dirname "$HYBRID_VIDEO_MPV_CONF")"
  if [[ -f $HYBRID_VIDEO_MPV_CONF ]]; then
    existing=$(<"$HYBRID_VIDEO_MPV_CONF")
  fi

  # Rewrite in place, which keeps a symlinked config pointing where it did.
  if [[ -n $existing ]] && awk -v m="$HYBRID_VIDEO_MPV_COMMENT" '
    /^[[:space:]]*\[/ { exit }
    $0 == m { found = 1; exit }
    END { exit !found }' "$HYBRID_VIDEO_MPV_CONF"; then
    out=$(printf '%s\n' "${options[@]}" | awk -v m="$HYBRID_VIDEO_MPV_COMMENT" '
      FNR == NR { options = options $0 "\n"; next }
      { print }
      !done && $0 == m { printf "%s", options; done = 1 }' - "$HYBRID_VIDEO_MPV_CONF"; echo x)
    printf '%s' "${out%x}" >"$HYBRID_VIDEO_MPV_CONF"
    return 0
  fi
  {
    echo "$HYBRID_VIDEO_MPV_COMMENT"
    printf '%s\n' "${options[@]}"
    if [[ -n $existing ]]; then
      printf '\n%s\n' "$existing"
    fi
  } >"$HYBRID_VIDEO_MPV_CONF"
}

# Whether a pinned /dev/dri/by-path/pci-<address>-render node still belongs to
# a display device that is not the NVIDIA GPU. A MUX switch to the dGPU, an
# iGPU turned off in firmware or a BIOS update that moves the PCI address
# leaves a pin pointing at nothing, and decode silently falls back to software.
# Reads only cached sysfs IDs, never the device.
hybrid_video_node_valid() {
  local name=${1##*/} vendor="" class="" dev
  [[ $name == pci-*-render ]] || return 0
  name=${name#pci-}
  dev="${OMARCHY_PCI_DEVICES_PATH:-/sys/bus/pci/devices}/${name%-render}"
  read -r vendor 2>/dev/null <"$dev/vendor" || return 1
  read -r class 2>/dev/null <"$dev/class" || return 1
  [[ $vendor != "0x10de" && $class == 0x03* ]]
}

# Drops the render node pins Omarchy wrote (the by-path line right under
# HYBRID_VIDEO_PIN_MARKER) that no longer name the iGPU, with their marker, from
# the Chromium-family flags files and mpv.conf. A render node setting without
# the marker is the user's, whatever it names, and is left alone.
hybrid_video_unpin_stale() {
  local conf line held changed out pin='^[[:space:]]*(--render-node-override=|(--)?vaapi-device[[:space:]]*=[[:space:]]*)([^[:space:]]*/by-path/pci-[^[:space:]]+-render)[[:space:]]*$'
  for conf in "${HYBRID_VIDEO_CHROMIUM_FLAGS_FILES[@]}" "$HYBRID_VIDEO_MPV_CONF"; do
    [[ -f $conf ]] || continue
    changed=0 out="" held=0
    while IFS= read -r line || [[ -n $line ]]; do
      if (( held )); then
        held=0
        if [[ $line =~ $pin ]] && ! hybrid_video_node_valid "${BASH_REMATCH[3]}"; then
          changed=1
          continue
        fi
        out+="$HYBRID_VIDEO_PIN_MARKER"$'\n'
      fi
      if [[ $line == "$HYBRID_VIDEO_PIN_MARKER" ]]; then
        held=1
        continue
      fi
      out+="$line"$'\n'
    done <"$conf"
    (( held )) && out+="$HYBRID_VIDEO_PIN_MARKER"$'\n'
    # Rewrite in place, which keeps a symlinked config pointing where it did.
    (( changed )) && printf '%s' "$out" >"$conf"
  done
  return 0
}

# Drops stale pins, then pins again where an iGPU is found.
hybrid_video_refresh() {
  hybrid_video_unpin_stale
  hybrid_video_pin_mpv
  hybrid_video_pin_chromium
}
