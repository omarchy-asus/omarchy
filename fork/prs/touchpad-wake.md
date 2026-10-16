Branch: `asus/touchpad-wake`

# Keep the touchpad from waking the ROG Zephyrus G16 GA605KM

### Problem

On the ROG Zephyrus G16 GA605KM the touchpad is armed as a wake source, and every report it sends while armed counts as a wakeup event: it logged 129k wakeup events in one boot, and touching the pad while the laptop was going down aborted a hibernate. From s2idle itself only a click wakes it (tested 2026-10-16: a resting or sliding finger did not wake it, a click did, twice), so the harm is touches being counted during suspend and hibernate entry, not touches waking a sleeping laptop.

### Cause

The firmware declares the ASUF1209 touchpad (FocalTech, on i2c-hid) as a wake source, and Linux arms it, and while it is armed i2c-hid reports every input report as a wakeup event (`pm_wakeup_event()`, since "HID: i2c-hid: Report wakeup events", 2021). Most likely a touch during the freeze of a suspend or hibernate then aborts it; that is inferred from the 129k events and the aborted hibernate, not reproduced with a finger on the pad during entry. On Windows, ASUS's touchpad filter driver (AsusPTPFilter) limits the touchpad's wakeups to clicks. Its wake-mode flag is set to "button only". Linux has no equivalent, so the choice is between that and no touchpad wake at all.

### Change

- `install/hardware/asus/fix-asus-ga605km-touchpad-wake.sh`, gated on `omarchy-hw-asus-rog && omarchy-hw-match "GA605KM"`, writes a udev rule that sets `power/wakeup=disabled` on `i2c-ASUF1209:*`. The keyboard, lid and power button still wake the laptop; a touchpad click no longer does.
- The rule matches `bind` as well as `add`. The i2c core arms the wakeup when the driver probes, which can happen after udev has already handled the add event.
- A migration installs the same rule on existing GA605KM installs and disarms the touchpad for the current boot. It leaves any existing rule file alone and does nothing on other machines.
- The rule is scoped to the touchpad's ACPI ID and is only written on this model. The ID is probably shared with other Zephyrus models, but that has only been verified on the GA605KM.

### Testing

- `test/shell.d/asus-ga605km-touchpad-wake-test.sh` runs the hardware leaf and the migration against a mocked sysfs and `/etc`. It checks the gate (non-ROG machines and other ROG models are left alone), the rule text, the file mode, that only the touchpad is disarmed, idempotence, that an administrator's copy is kept, and that new installs and the migration write the same rule. It also runs `udevadm verify` on the rule.
- `./test/all` (run headless) shows no new failures compared with stock `quattro` on the same machine. The 22 files that fail on the branch also fail on stock: agent-usage, i18n, sleep-lock and the other environment-dependent tests.
- Running on the GA605KM: the same rule (matching `add` only) has been in place since 2026-10-14, and `/sys/bus/i2c/devices/i2c-ASUF1209:00/power/wakeup` reads `disabled`.

This pull request was written with Claude Code.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
