Branch: `asus/usbc-power`

# Save power on USB-C chargers on ASUS ROG Zephyrus laptops


**Problem.** A Zephyrus on a 100 W USB-C charger gets the AC profile, `performance`, the same as on its 200 W+ barrel adapter. It can then draw more than the charger supplies, so the battery drains while plugged in and the charger can cut out.

**Cause.** The ACPI adapter (`ACAD`, type Mains) reads online for the barrel and for USB-C alike, and so does UPower's `OnBattery`. Nothing in the profile path could tell the two apart.

**Change.** The firmware reports which input it charges from (WMI DSTS `0x0012006C`: bit 0 barrel, bit 1 USB-C PD, 3 both with the barrel in use). The kernel exposes this read-only, without root, as the asus-armoury firmware attribute `charge_mode` (or `asus-nb-wmi/charge_mode` on older kernels). A new predicate, `omarchy-hw-asus-rog-usbc-power`, is true when a ROG Zephyrus is charging from USB-C only. It checks the charge_mode file first, so machines without it start no extra process. When the machine has just been plugged in and charge_mode still reads 0, it re-reads for up to 2 s, because the firmware sets the bits shortly after the adapter comes online. On battery it answers at once. `omarchy-powerprofiles-set` turns `ac` into a third source, `usb-c`: it defaults to `balanced` (power-profiles-daemon on AC then sets EPP `balance_performance` with boost on), and a profile picked there from the menu or the power panel is remembered under `usb-c`, apart from the barrel's `ac`. The barrel adapter keeps `performance` and full power. The shell, menu and panel need no change: they already call `omarchy-powerprofiles-set ac|battery|autodetect` on every source change. No daemon or poll is added.

**How tested.** `test/shell.d/asus-rog-usbc-power-test.sh` uses a mocked sysfs tree (`OMARCHY_SYS_ROOT`, `OMARCHY_POWER_SUPPLY_PATH`). It covers charge_mode 1, 2 and 3; the legacy attribute; a missing attribute; non-ROG and non-Zephyrus machines; a charger the firmware reports 0.5 s late; and battery answered without waiting. It also checks that USB-C defaults to balanced while the barrel keeps performance, that each source remembers its own pick, and that battery and other machines behave as before. `powerprofiles-set-test.sh` now points `OMARCHY_SYS_ROOT` at an empty tree, so it gives the same result on a Zephyrus running on USB-C.

**Evidence.** GA605KM, BIOS 307. DSTS `0x0012006C` read 0x10000 on battery, 0x10001 on the 220 W barrel and 0x10002 on a 100 W USB-C PD charger (2026-10-14). The 140 W SlimQ barrel reads the same as the 220 W one, so barrels cannot be told apart. `charge_mode/current_value` read 1 on the barrel, 0 on battery and 18 (0x12: bit 1 set, bit 0 clear) on a 60 W USB-C PD charger (checked live 2026-10-16; the extra bit 4 is not used). The predicate tests only bits 0 and 1, so it answered correctly in all three cases. G-Helper uses the same DSTS bits for its USB-C profile, and Armoury Crate switches to its `*_PD` power schemes on them.

This pull request was written with Claude Code.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

**Naming a source.** Only the current source resolves to `usb-c`: `autodetect`, or a power-source change that names `ac` with no profile. `ac <profile>` names the barrel and `usb-c <profile>` names USB-C, so each can be set from anywhere, the way the manual already describes `battery <profile>`. The power panel names the current plugged-in source with `autodetect` instead of `ac`, so a pick made there on USB-C stays with USB-C. The test covers both, and charge_mode 18 (a 60 W PD charger, measured on the GA605KM) and 17.
