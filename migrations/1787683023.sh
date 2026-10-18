echo "Stop early-loading the NVIDIA driver on hybrid GPU systems so hibernation can resume"

# install/hardware/nvidia.sh used to write nvidia.conf on every NVIDIA machine.
# On a hybrid laptop the iGPU provides early KMS, and having nvidia already
# loaded inside the initramfs makes resume from hibernation fail with
# "nv_pmops_freeze returns -5" / "PM: hibernation: resume failed (-5)".
# Drop the drop-in on those machines and rebuild the initramfs once. A marker
# records completion so another user's run does not repeat the rebuild.

nvidia_conf="${OMARCHY_MKINITCPIO_NVIDIA_CONF:-/etc/mkinitcpio.conf.d/nvidia.conf}"
rebuild_marker="${OMARCHY_NVIDIA_REBUILD_MARKER:-/var/lib/omarchy/migrations/1787683023}"

omarchy-cmd-present limine-mkinitcpio || exit 0
[[ -f $nvidia_conf ]] || exit 0
[[ ! -e $rebuild_marker ]] || exit 0
omarchy-hw-nvidia-only-display && exit 0

# Only the drop-in exactly as the installer wrote it is Omarchy's to remove. A
# file with any other content was edited, or written by hand, and may load or
# configure more than this; removing it and rebuilding could break the boot.
if [[ $(cat "$nvidia_conf"; echo x) != $'MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)\nx' ]]; then
  echo "Leaving $nvidia_conf in place: it is not the file Omarchy wrote. Remove it and run 'sudo limine-mkinitcpio' to stop early-loading nvidia."
  exit 0
fi

echo "This is a hybrid GPU machine; removing nvidia from the initramfs and rebuilding it"

# The drop-in has to be gone before the rebuild, but the rebuild is what makes
# the change real. If it fails, put the drop-in back so the next run finds it
# and retries instead of exiting at the check above with a stale image.
backup=$(mktemp)
cp "$nvidia_conf" "$backup"
sudo rm -f "$nvidia_conf"
if ! sudo limine-mkinitcpio; then
  sudo install -m644 "$backup" "$nvidia_conf"
  rm -f "$backup"
  echo "Rebuilding the initramfs failed; restored $nvidia_conf so the migration retries" >&2
  exit 1
fi
rm -f "$backup"
sudo install -Dm644 /dev/null "$rebuild_marker"
