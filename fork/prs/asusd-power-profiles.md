Branch: `asus/asusd-power-profiles`

# Stop asusd from switching the power profile and EPP on ROG laptops


**Problem.** On ASUS ROG laptops two daemons pick the power profile when the charger is plugged in or out. Omarchy's shell runs `omarchy-powerprofiles-set ac|battery`, which restores the profile remembered for that source through power-profiles-daemon. asusd does the same from its own config (`platform_profile_on_ac: Performance`, `platform_profile_on_battery: Quiet` by default). Which one wins depends on timing. asusd also watches the platform profile, and after every change (its own, power-profiles-daemon's, Fn+F5) it rewrites the CPU energy performance preference (EPP) from its own table, replacing the EPP power-profiles-daemon chose for that profile. On a G16 GA605KM this left EPP at `performance` in quiet phases of a battery test and cost about 1.8 W.

**Cause.** asusd defaults `change_platform_profile_on_ac`, `change_platform_profile_on_battery` and `platform_profile_linked_epp` to true (asusctl 6.4.0, `asusd/src/config.rs`).

**Change.** A systemd drop-in for `asusd.service` sets those three D-Bus properties to false after asusd starts (`ExecStartPost=-/usr/bin/busctl ... b false`). asusd saves them in `/etc/asusd/asusd.ron`. The `-` prefix means a model without platform profiles, or an older asusd, still starts normally. Seeding `asusd.ron` directly is not safe: asusd's config struct has no serde defaults, so a partial file is renamed to `-old` and replaced with defaults. The drop-in ships in `omarchy-settings` like the other `etc/` drop-ins. It does nothing on machines without asusd, and Omarchy installs asusctl only on ROG hardware (`install/hardware/asus-rog.sh`). Everything else asusd does (keyboard lighting, charge limit, fan curves, Fn keys) is unchanged. Fn+F5 still cycles the profile, and power-profiles-daemon then sets the EPP for that profile.

**How tested.** `test/shell.d/asusd-power-profiles-test.sh` checks the migration (below) and that the drop-in sets exactly these three properties, that every line ignores failure, and that the drop-in parses with `systemd-analyze verify` (no unknown keys). `./test/all` gives the same result as stock `upstream/quattro` on this machine (see "Test results" below). The same three settings have been live on a GA605KM since 2026-10-15, set over D-Bus as a normal user.

**Evidence.** asusctl 6.4.0 source: `ctrl_platform.rs` (`check_and_set_epp` on every platform-profile inotify event, profile switch on power change), `config.rs` defaults, `daemon.rs` (D-Bus name requested after interfaces are registered, so `ExecStartPost` reaches them). Battery A/B on the GA605KM (`abtest-1015-1039`): asusd's `profile_custom_epp: Performance` overrode EPP and added about 1.8 W SoC power.

**Migration.** `migrations/1792122579.sh` (commit `a8317d178`) applies the same three settings to a running asusd, so existing installs do not wait for a reboot. It runs only on ROG hardware (`omarchy-hw-asus-rog`) with `asusd.service` active, writes a property only while it still reads `b true` (a rerun writes nothing), skips properties an older asusd lacks, and if asusd refuses a write it says so and goes on: the drop-in turns it off at the next start. asusd's D-Bus policy lets wheel and users members set these without root. `test/shell.d/asusd-power-profiles-test.sh` covers it with `busctl`, `systemctl` and the ROG check stubbed: all three turned off, idempotent rerun, nothing on non-ROG or without asusd, a refused write reported while the rest still apply, a missing property skipped.

Packaging companion (omacom/omarchy-pkgs, `omarchy-settings`): add `etc/systemd/system/asusd.service.d/10-omarchy-power-profiles.conf` to `backup=()`, next to the other systemd drop-ins.

This pull request was written with Claude Code.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
