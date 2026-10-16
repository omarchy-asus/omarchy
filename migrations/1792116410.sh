echo "Keep the touchpad from waking the ASUS ROG Zephyrus G16 GA605KM"

# See install/hardware/asus/fix-asus-ga605km-touchpad-wake.sh, which sets up new
# installs the same way.
rules="${OMARCHY_ASUS_TOUCHPAD_WAKE_RULES:-/etc/udev/rules.d/99-omarchy-asus-ga605km-touchpad-wake.rules}"
i2c_devices="${OMARCHY_I2C_DEVICES_PATH:-/sys/bus/i2c/devices}"

if ! omarchy-hw-asus-rog || ! omarchy-hw-match "GA605KM"; then
  exit 0
fi

if [[ ! -f $rules ]]; then
  sudo install -Dm644 /dev/stdin "$rules" <<'RULES'
# ASUS ROG Zephyrus G16 GA605KM: any touch on the ASUF1209 touchpad wakes the
# laptop, so disarm it; see install/hardware/asus/fix-asus-ga605km-touchpad-wake.sh.
ACTION=="add|bind", SUBSYSTEM=="i2c", KERNEL=="i2c-ASUF1209:*", ATTR{power/wakeup}="disabled"
RULES
fi

# udev applies the rule from the next boot. Disarm the touchpad for this one
# too; once it reads disabled, another user's run is a no-op.
for wakeup in "$i2c_devices"/i2c-ASUF1209:*/power/wakeup; do
  [[ -f $wakeup && $(<"$wakeup") != "disabled" ]] || continue
  echo disabled | sudo tee "$wakeup" >/dev/null
done
