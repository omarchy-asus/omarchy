echo "Hibernate the ASUS ROG Zephyrus G16 GA605KM in shutdown mode"

# See install/hardware/asus/fix-asus-ga605km-hibernate-mode.sh, which sets up
# new installs the same way.
conf="${OMARCHY_ASUS_HIBERNATE_MODE_CONF:-/etc/systemd/sleep.conf.d/omarchy-asus-ga605km-hibernate-mode.conf}"

if ! omarchy-hw-asus-rog || ! omarchy-hw-match "GA605KM"; then
  exit 0
fi

# systemd-sleep reads the file at each hibernate, so nothing needs a restart.
# An existing file is the administrator's or another user's run; keep it.
if [[ ! -f $conf ]]; then
  sudo install -Dm644 /dev/stdin "$conf" <<'CONF'
# ASUS ROG Zephyrus G16 GA605KM: the ACPI S4 rollback wedges the NVIDIA driver;
# see install/hardware/asus/fix-asus-ga605km-hibernate-mode.sh.
[Sleep]
HibernateMode=shutdown
CONF
fi
