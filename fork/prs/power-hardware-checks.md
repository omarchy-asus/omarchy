# Power branches: hardware checks and results

Applies to `asus/asusd-power-profiles`, `asus/usbc-power`, `asus/ga605km-quiet-fans`.

2026-10-16 results: on USB-C `charge_mode` reads 18 (0x12; bit 1 set, bit 0 clear), on the barrel 1, on battery 0; `omarchy-hw-asus-rog-usbc-power` answered correctly in all three (g16reverse `captures/hwtest-1016-0149.log`). Post-reboot asusd check: after the 2026-10-16 07:53 boot, `ChangePlatformProfileOnAc`, `ChangePlatformProfileOnBattery` and `PlatformProfileLinkedEpp` all read `b false`, persisted in `/etc/asusd/asusd.ron` (these were set live over D-Bus, the same three properties the drop-in and migration set; one boot with the drop-in itself installed is still worth doing). Still open: the quiet-fans run with the branch installed.

## Validate on real hardware before upstreaming

**Barrel check, 2026-10-16 (read-only, branch not installed).** On the barrel adapter: `charge_mode` = 1, ACAD online = 1, both UCSI USB-C supplies online = 0, `platform_profile` performance (asus-wmi and amd-pmf both performance), EPP `performance`, boost 1. `omarchy-hw-asus-rog` true, `omarchy-hw-asus-rog-usbc-power` false. `omarchy-powerprofiles-set ac`, run against a copy of the live sysfs values with `powerprofilesctl` stubbed, kept `ac` (not `usb-c`), set `performance`, and called the quiet-fans helper with `off`, which wrote nothing. So the barrel gets full power. Still pending: steps 1 and 3 on USB-C and on battery (needs an unplug), and the post-reboot asusd check.

Do this on the GA605KM, with the branch installed through a dev link, only when the user agrees to that live change and its timing. Every command below only reads.

1. **charge_mode on USB-C (PR 2).** Read it on battery, on the barrel and on USB-C. It should read 0 on battery, 1 on the barrel, and on USB-C a value with bit 1 set and bit 0 clear (18 on a 60 W PD charger, measured 2026-10-16):
   `cat /sys/class/firmware-attributes/asus-armoury/attributes/charge_mode/current_value`
   Check the settle time: run `udevadm monitor --udev --subsystem-match=power_supply` in one terminal, plug in USB-C, and in another run `for i in $(seq 20); do cat .../charge_mode/current_value; sleep 0.25; done`. The 2 s wait must cover the gap between ACAD online and the bit.
2. **asusd (PR 1).** After a reboot, each of these should print `b false`:
   `busctl --system get-property xyz.ljones.Asusd /xyz/ljones xyz.ljones.Platform ChangePlatformProfileOnAc` (and `...OnBattery`, `PlatformProfileLinkedEpp`).
   Then unplug and replug, and check that `powerprofilesctl get`, `cat /sys/firmware/acpi/platform_profile` and `cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference` follow power-profiles-daemon (barrel: performance/performance; battery: balanced/balance_power).
3. **Sources (PR 2).** On USB-C: `powerprofilesctl get` → balanced, EPP `balance_performance`, `cat /sys/devices/system/cpu/cpufreq/boost` → 1. On the barrel: performance. `ls ~/.local/state/omarchy/powerprofiles/` shows `usb-c` once a profile is picked on USB-C.
4. **Quiet fans (PR 3).** First `sudo -l -l /usr/bin/omarchy-powerprofiles-asus-quiet-fans on` should show `!authenticate`. Then unplug and wait 10 s:
   `grep . /sys/class/platform-profile/*/{name,profile}` → asus-wmi quiet, amd-pmf balanced; `grep . /sys/class/hwmon/hwmon*/fan*_input` → about 0 rpm;
   `cat /sys/bus/pci/devices/0000:64:00.0/power/runtime_status` should go back to `suspended` within about 30 s. Never use nvidia-smi or /proc/driver/nvidia for this. Plug USB-C: asus-wmi balanced. Plug the barrel: both performance. Check `journalctl -t sudo` for one call per change.
5. **Not covered by events.** Check what happens after Fn+F5 on battery (the fans stay normal until the next source change) and after suspend/resume (whether the firmware resets the handler).

## Test results (2026-10-16)

`./test/all` on `a8317d178`, headless: all four power tests pass (`asusd-power-profiles`, `asus-rog-usbc-power`, `asus-quiet-fans`, `powerprofiles-set`). 33 of 449 shell test files fail on this machine for environment reasons unrelated to the branch (mise errors in the agent-usage tests, `omarchy-i18n` not on PATH, and similar); `migrate-notify-test.sh` fails the same way with the new migration removed.

## Fork-only, not ported, or open

- **Battery EPP.** rog-power used EPP `power` with boost on, against `balance_power`: −0.86 W, 4 of 4 rounds (F15). power-profiles-daemon owns EPP, and in 0.30 balanced on battery is `balance_power` (`battery_aware`), while power-saver is `power` with boost off. Overriding it would race power-profiles-daemon on every event, so it is not ported. The upstream route is a power-profiles-daemon option; until then it could be fork-only.
- **Not ported, by design or because there is no evidence:** CPU PPT writes (they do not take effect on BIOS 307 without the custom CPU fan curve, `review/ppt-manual-mode.md`); nv_tgp (an offset; belongs in the asus-armoury kernel table); the SlimQ flap step-down, game-first charge hold, RTX holder scan and gamemode hooks (rog-power-specific, not general Omarchy behaviour); the USB-C power-saver/quiet envelope (this branch uses balanced on USB-C, per the policy "not barrel = save, boost on").
- **Fork-only files:** `ZEPHYRUS.md` (planned changes 2 and 3 should point at this branch once it is reviewed). Everything on this branch is written to be upstreamable as is. PR 3 is the most model-specific, and may still be better kept in the fork if upstream prefers no new sudoers grant for one model.
