echo "Move the G16 Control widget to the omarchy-asus plugin"

# The asus-zephyrus-g16-control package linked its bar widget into the plugins
# directory from /usr/share under the id omarchy-asus.g16. The widget is the
# omarchy-asus plugin now, and asus-rog-nkey-winlock replaces that package, so
# the link points nowhere. Swap it for the plugin. Machines that never had the
# link are left alone.
plugins=$HOME/.config/omarchy/plugins
old=$plugins/omarchy-asus.g16
url=https://github.com/omarchy-asus/omarchy-asus-plugin

if [[ -L $old && $(readlink "$old") == /usr/share/omarchy/plugins/omarchy-asus.g16 ]]; then
  rm "$old"
  if [[ ! -e $plugins/io.github.omarchy-asus.panel ]] &&
    ! omarchy-plugin-add "$url" --enable --yes; then
    echo "Could not add the omarchy-asus plugin. Add it later with:"
    echo "  omarchy-plugin-add $url --enable"
  fi
fi
