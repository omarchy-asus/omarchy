# Hibernate the ASUS ROG Zephyrus G16 GA605KM in shutdown mode.
#
# In the default platform mode the kernel asks the firmware for ACPI S4 after
# writing the image and backs out if any wakeup event is pending ("Wakeup event
# detected during hibernation, rolling back"). On this model the rollback
# powers the RTX back up in the middle of the transition, the NVIDIA driver
# fails to restore its channels (WARNING in nv_restore_user_channels) and the
# laptop needs a hard reset. Shutdown mode writes the image and powers off with
# no rollback path; resume is the normal boot-time image restore.
#
# The NVIDIA driver up to 610.57.04 can still hang the final power-off after
# the image is written (NVIDIA/open-gpu-kernel-modules PR #1412). The image is
# already on disk then, so a long power press and a normal boot resume it.

if omarchy-hw-asus-rog && omarchy-hw-match "GA605KM"; then
  conf="${OMARCHY_ASUS_HIBERNATE_MODE_CONF:-/etc/systemd/sleep.conf.d/omarchy-asus-ga605km-hibernate-mode.conf}"

  mkdir -p "$(dirname "$conf")"
  cat >"$conf" <<'CONF'
# ASUS ROG Zephyrus G16 GA605KM: the ACPI S4 rollback wedges the NVIDIA driver;
# see install/hardware/asus/fix-asus-ga605km-hibernate-mode.sh.
[Sleep]
HibernateMode=shutdown
CONF
fi
