# Pull requests

One draft per topic branch. Opened pull requests come from a squashed copy of the topic branch, `pr/<name>` on the fork; review changes go on `pr/<name>` and, as a `fixup!`, on the topic branch. Before opening one: squash its `fixup!` commits (`git rebase -i --autosquash upstream/quattro` on the branch, then `fork/sync --push`), check the branch on [upstream's PR list](https://github.com/omacom/omarchy/pulls) for anything newer that overlaps, and open it from the branch with the draft's title and body. Upstream wants one change per pull request and says so when a pull request was written by an agent; every draft does.

## Order to open them in

Ready means: `fork/test` passes with no new failures against upstream, and nothing is waiting on hardware. Point it at a pkgs checkout with the companions (`OMARCHY_PKGS_PATH=~/Work/omarchy/omarchy-asus-pkgs-wt/omarchy-asus`, the `omarchy-asus` integration branch), or `config-test.sh` reports the charger-swap unit and the nvidia-powerd drop-in as not shipped. To test one topic on its own, use its companion's worktree. On 2026-10-17 against current upstream pkgs, `passwordless-grant-lifecycle-test.sh` also fails on both (upstream pkgs dropped the `pre_remove` it calls), and `input-indicator-test.sh` fails now and then in a full run but passes alone. On 2026-10-16 it fails 1 of 458 test files on the fork and 1 of 446 on upstream `quattro`, the same one: `i18n-test.sh`, because the 8 `style.font.cjk.*` menu keys added by #15508 are untranslated in all 49 languages (upstream data, not this fork). That is by design: pull requests add only the English side, and the `Sync translations` workflow fills the other languages later (`docs/i18n.md`); CI's `i18n-check` does not require them, only the local test does, so it clears on its own when the bot runs. Run as plain `./test/all` inside a desktop session, 21 more files fail on both for session reasons that `fork/test` clears.

| # | Branch | Title | State |
|---|---|---|---|
| 1 | `asus/rtkit` | Install rtkit on x86_64 too so PipeWire gets realtime scheduling | not opened: [#12428](https://github.com/omacom/omarchy/pull/12428) (not ours) is the same fix with portal and PipeWire restarts; drop this branch when it merges |
| 2 | `asus/asusd-power-profiles` → [#15667](https://github.com/omacom/omarchy/pull/15667) | Stop asusd from switching the power profile and EPP on ROG laptops | ready; settings verified to persist across a reboot 2026-10-16 ([power-hardware-checks](power-hardware-checks.md)) |
| 3 | `asus/usbc-power` → [#15668](https://github.com/omacom/omarchy/pull/15668) | Save power on USB-C chargers on ASUS ROG laptops | open; needs the `omarchy-settings-source-monitor` pkgs companion (branch pushed, PR not opened yet); USB-C, barrel and battery checked on the GA605KM 2026-10-16, a live charger swap not yet |
| 4 | `asus/powerprofiles-external-owner` → [#15669](https://github.com/omacom/omarchy/pull/15669) | Let another power manager own the profile on plug and unplug | ready; generic |
| 5 | `asus/hybrid-video-decode` | Keep video decode on the iGPU of hybrid NVIDIA laptops | ready; refs #14285 |
| 6 | `asus/hdmi-cursor` | Use a software cursor while a monitor on the NVIDIA GPU is plugged into a hybrid laptop | run it once inside Hyprland first (only the equivalent local config has run) |
| 7 | `asus/audio` | Set the ASUS ROG ALC285 Master to full scale under the soft mixer | ready; part of #11046, see #7459 |
| 8 | `asus/touchpad-wake` | Keep the touchpad from waking the ROG Zephyrus G16 GA605KM | ready; GA605KM only |
| 9 | `asus/hibernate-mode` | Hibernate the ROG Zephyrus G16 GA605KM in shutdown mode | after the #8589 comment; one hibernate with the migration |
| 10 | `asus/ga605km-quiet-fans` | Stop the idle fans on battery on the ROG Zephyrus G16 GA605KM | after 2; may stay in the fork if upstream prefers no new sudoers grant for one model |
| 11 | `perf/webcam-guard-udev` → [#15670](https://github.com/omacom/omarchy/pull/15670) | Answer the webcam menu guard from udev instead of opening cameras | ready; generic |
| 12 | `perf/monitor-watch-logind` | Reconcile clamshell state on logind events instead of a 2s poll | watch one real lid close first |
| 13 | `perf/launcher-icon-index` | Rescan the launcher icon index at most once a minute on open | ready; generic |
| 14 | `perf/tailscale-poll` → [#15671](https://github.com/omacom/omarchy/pull/15671) | Poll only Tailscale status while its panel is closed | ready; generic |
| 15 | `asus/nvidia-powerd-start-limit` | Keep nvidia-powerd startable after five charger plug-ins | ready; needs the `omarchy-settings-nvidia-powerd` pkgs companion; open both together |
| — | `carry/initramfs-8263` | someone else's #8263, carried | do not open; comment on #8263 after a hibernate on the fork |

Merge conflicts between them are small and known: 3, 4 and 10 touch `bin/omarchy-powerprofiles-set`; 5 and 6 touch `default/hypr/nvidia.lua` and `test/shell.d/hw-nvidia-test.sh`. Whichever lands second needs a rebase.

## Packages ([omarchy-asus-pkgs](https://github.com/rdoupe-omarchy/omarchy-asus-pkgs))

| Branch | Title | State |
|---|---|---|
| `nvidia-open-x86_64` | nvidia-open-dkms: build for x86_64 too, with NVIDIA PRs #1299 and #1412 | after 615 has run on the GA605KM ([draft](pkgs-nvidia-open-x86_64.md)) |
| `omarchy-settings-source-monitor` | omarchy-settings: ship the ASUS charger-swap monitor as a user unit | companion to [#15668](https://github.com/omacom/omarchy/pull/15668); ready, open it with or after #15668 ([draft](pkgs-omarchy-settings-source-monitor.md)) |
| `omarchy-settings-nvidia-powerd` | omarchy-settings: ship the nvidia-powerd start-limit drop-in | companion to `asus/nvidia-powerd-start-limit`; open it with that PR ([draft](pkgs-omarchy-settings-nvidia-powerd.md)) |
| `omarchy-asus` | not a PR: upstream master with every companion merged in | install and test from it; rebuild after a companion changes (`git merge` each companion onto `upstream/master`) |
| `linux-omarchy-hid-asus-winlock` | Add hid-asus Win-lock pass-through to the base, BORE and MuQSS kernels | after Jiri's review of the hid-asus patch, or two weeks after the ping ([draft](pkgs-linux-omarchy-hid-asus-winlock.md)) |
