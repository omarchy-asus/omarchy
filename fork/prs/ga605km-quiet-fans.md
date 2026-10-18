Branch: `asus/ga605km-quiet-fans`

# Stop the idle fans on battery on the ROG Zephyrus G16 GA605KM


**Problem.** On battery in `balanced`, the G16 GA605KM's three fans run at about 2200/1800/3800 rpm even when it is idle at 28 °C. That costs battery and makes noise.

**Cause.** The machine has two platform-profile handlers. The fan floor comes from the ASUS one (`asus-wmi`) and the CPU limits from the AMD one (`amd-pmf`). Setting both to quiet (`power-saver`) stops the fans but caps the CPU at 2.0 GHz.

**Change.** On battery with the `balanced` profile, `omarchy-powerprofiles-set` sets only the asus-wmi handler to quiet and leaves amd-pmf on balanced. On any other source or profile it undoes that mixed state, and only that state. The write needs root, so it goes through a small helper, `omarchy-powerprofiles-asus-quiet-fans on|off`, with a sudoers grant that names both whole commands (`%wheel ... NOPASSWD: /usr/bin/omarchy-powerprofiles-asus-quiet-fans on, ... off`). This follows `omarchy-theme-set-browser-policy` and `omarchy-dns`: the shell has no terminal for a password. The helper pins PATH as root, calls no other `omarchy-` command, checks the DMI product name itself, finds the handlers by name, writes `on` only on battery (Mains offline), and writes nothing when the state is already right. Each platform-profile write makes the firmware wake the RTX for about 20 s, so it writes once per plug or unplug at most. Without the grant and without a terminal it does nothing, rather than raise a password dialog on every unplug. power-profiles-daemon reads the mixed state as `custom` and keeps its own profile, balanced, so it does not fight it (`ppd-driver-platform-profile.c`). Going from battery to the barrel, power-profiles-daemon's write of `performance` resets both handlers. Going from battery to USB-C (balanced, so power-profiles-daemon writes nothing), the `off` call restores asus-wmi to balanced. It is gated with `omarchy-hw-match "GA605KM"` (DMI product name `ROG Zephyrus G16 GA605KM_GA605KM`, board `GA605KM`), the only model it was measured on. It works best with `asus/asusd-power-profiles`: with linked EPP on, asusd would set its quiet EPP on the switch.

**How tested.** `test/shell.d/asus-quiet-fans-test.sh` checks that the sudoers file carries exactly the on/off rule and passes `visudo -c`, and that the helper elevates the packaged path and pins PATH under root. Against a mocked sysfs tree it checks: on battery and balanced the fans go quiet once (a second call writes nothing, which the test proves by making the profile files read-only); nothing is written on AC, outside balanced, in the full quiet profile, on another model or without the ASUS handler; `off` undoes only the mixed state; and any argument other than `on` or `off` is refused. It also checks that `omarchy-powerprofiles-set` calls `on` only for balanced on battery and never calls the helper on other machines. A mutation check (removing the state guard) makes the test fail.

**Evidence.** Battery A/B on the GA605KM (2026-10-15, `delta/WINDOWS.md` §7, `abtest-1015-1051`, samples with the RTX suspended only), asus-wmi quiet + amd-pmf balanced against plain balanced, EPP held equal: −1.57 / −0.79 / −0.79 / −2.43 W per cycle, median −0.79 W, lower in 3 of 4 cycles. Fans at 7 rpm against about 2100/1800/3700. Single-thread 5043 MHz / 12.2 W and all-core 5041 MHz peak, the same as balanced (full quiet: 2011 MHz). Live on that machine since 2026-10-15 13:41 through rog-power v2, verified on battery: asus-wmi quiet, amd-pmf balanced, fans 0 rpm, RTX back to suspended.

Packaging companion: `omarchy-settings` already installs everything under `etc/sudoers.d/` at mode 0440.

This pull request was written with Claude Code.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

**Without the package.** The helper runs from `/usr/bin` with a sudoers grant, both installed by the omarchy packages. A checkout linked with `omarchy dev link` has neither until the packages are built from it (`omarchy dev pkg-test`); the helper then leaves the fans alone and says why once per boot in the journal (`journalctl -t omarchy-powerprofiles-asus-quiet-fans`).

**With `powerprofiles-autoswitch-off`** (`asus/powerprofiles-external-owner`), source changes return before this code runs, so a quiet-fans state set earlier on battery is not undone on plug-in by Omarchy. The tool that then owns the profile clears it with its next profile write: any write through `/sys/firmware/acpi/platform_profile` sets both handlers.
