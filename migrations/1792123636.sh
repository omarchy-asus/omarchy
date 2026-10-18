echo "Decode video on the integrated GPU of hybrid NVIDIA laptops"

source "$OMARCHY_PATH/install/helpers/hybrid-video-decode.sh"

hybrid_video_pin_mpv
hybrid_video_pin_chromium
