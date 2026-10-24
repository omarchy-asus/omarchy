echo "Move the G16 Control widget to the omarchy-asus plugin"

# The asus-zephyrus-g16-control package linked its bar widget into the plugins
# directory from /usr/share under the id omarchy-asus.g16. The widget is the
# omarchy-asus plugin now, and asus-rog-nkey-winlock replaces that package, so
# the link points nowhere. Swap it for the plugin. Machines that never had the
# link are left alone.
plugins=$HOME/.config/omarchy/plugins
old=$plugins/omarchy-asus.g16
id=io.github.omarchy-asus.panel
url=https://github.com/omarchy-asus/omarchy-asus-plugin

# The link goes only once the plugin is on the bar. Until then this fails, so
# omarchy-migrate keeps it pending and the next update or login runs it again;
# the dead link marks what is left to do.
stay_pending() {
  echo "The omarchy-asus plugin is not on the bar yet: $1." >&2
  echo "This migration runs again with the next omarchy-update, or run omarchy-migrate." >&2
  exit 1
}

if [[ -L $old && $(readlink "$old") == /usr/share/omarchy/plugins/omarchy-asus.g16 ]]; then
  if [[ ! -e $plugins/$id && ! -L $plugins/$id ]]; then
    omarchy-plugin-add "$url" --enable --yes || stay_pending "adding $url failed"
  elif git -C "$plugins/$id" remote get-url origin 2>/dev/null | grep -q 'omarchy-asus/omarchy-asus-plugin'; then
    # An earlier run cloned it but could not enable it (no shell to ask).
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
    [[ $(omarchy-bar put "$id") == *"is on the bar"* ]] || stay_pending "the shell did not put $id on the bar"
  fi
  rm "$old"
fi
