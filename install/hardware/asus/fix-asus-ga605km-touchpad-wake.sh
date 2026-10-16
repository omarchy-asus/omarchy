# Keep the touchpad from waking the ASUS ROG Zephyrus G16 GA605KM (ASUF1209
# touchpad on i2c-hid).
#
# Its firmware marks the touchpad as a wake source, and Linux arms it for any
# touch: a brush against the pad wakes the laptop from suspend in a bag, and
# one aborted a hibernate in progress (129k wakeup events in one boot). ASUS's
# Windows filter driver limits its wakeups to clicks, which Linux cannot do
# yet. Disarm it; the keyboard, lid and power button still wake the laptop.
#
# The rule also runs on bind: the i2c core arms the wakeup when the driver
# probes, which can come after udev has handled the add event.

if omarchy-hw-asus-rog && omarchy-hw-match "GA605KM"; then
  rules="${OMARCHY_ASUS_TOUCHPAD_WAKE_RULES:-/etc/udev/rules.d/99-omarchy-asus-ga605km-touchpad-wake.rules}"

  mkdir -p "$(dirname "$rules")"
  cat >"$rules" <<'RULES'
# ASUS ROG Zephyrus G16 GA605KM: any touch on the ASUF1209 touchpad wakes the
# laptop, so disarm it; see install/hardware/asus/fix-asus-ga605km-touchpad-wake.sh.
ACTION=="add|bind", SUBSYSTEM=="i2c", KERNEL=="i2c-ASUF1209:*", ATTR{power/wakeup}="disabled"
RULES
fi
