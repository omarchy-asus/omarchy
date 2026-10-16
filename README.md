# Omarchy Zephyrus

[Omarchy](https://github.com/omacom/omarchy) for ASUS ROG Zephyrus laptops (G14 and G16), kept as a fork the way [omarchy-mac](https://codeberg.org/malik-na/omarchy-mac) is for Apple Silicon.

## Why this repo

A Zephyrus is a hybrid laptop: an AMD or Intel iGPU drives the panel, an NVIDIA RTX sits behind it for games and the HDMI port, and ASUS firmware decides fans, power limits and charging. Stock Linux and stock Omarchy run on it, but several things go wrong: the RTX wakes up and burns watts for no reason, video decodes on the wrong GPU, the firmware ignores power limits Linux thinks it set, a dropped HID report makes the Super key die silently, and so on.

Fixing each of those properly means a fix in a different place: the kernel, NVIDIA's driver, Hyprland, asusctl, Omarchy itself. Each of those projects moves at its own pace, and a one-off patch on someone's laptop helps nobody else. This repo is where the fixes are collected, proven on real hardware, and then sent to the project that should own them:

- **One place to see every fix** and where it stands upstream (the table below).
- **A complete, working Omarchy for Zephyrus laptops** in the meantime, gated on the hardware so it behaves exactly like stock Omarchy anywhere else.
- **Upstream first.** Every change here is staged as a self-contained commit that can become its own pull request or patch. When upstream takes a fix, the copy here is dropped.

Reference machine: Zephyrus G16 GA605KM (Ryzen AI 7 350, Radeon 860M, RTX 5060 Laptop, BIOS 307). Where a fix is known to apply to other models, the table says so; where it is only verified on the GA605KM, it says that too.

How the fork works and which Omarchy rules it follows: [ZEPHYRUS.md](ZEPHYRUS.md).

## Hardware fixes and where they stand

Columns:

- **Scope**: `GA605KM` = verified on that model only; `Zephyrus` = G14/G16 family firmware; `hybrid` = any iGPU + NVIDIA laptop; `ASUS` = ASUS ROG/TUF laptops on the same driver; `generic` = any laptop.
- **This repo**: `—` not here yet (it runs as a local workaround on the reference machine); `workaround` = here, but not the way upstream should do it; `proper` = here, done the Omarchy way, ready to propose.
- **Upstream**: the project that owns the real fix and the state there.
- **Omarchy**: the state in [omacom/omarchy](https://github.com/omacom/omarchy) or [omacom/omarchy-pkgs](https://github.com/omacom/omarchy-pkgs).

Status as of 2026-10-16. A branch name in **This repo** means the fix is written and pushed on that branch but not yet merged here.

### GPU and RTX power

| Fix | Effect | Scope | This repo | Upstream | Omarchy |
|---|---|---|---|---|---|
| Don't force NVIDIA VA-API on hybrid laptops | Browser and mpv video decode on the iGPU instead of the RTX (AV1 1080p60: 0.36 s CPU vs 2.61 s software); RTX can sleep. Upstream's check misses iGPUs that are a non-VGA display controller (Krackan), so the G16 is still treated as NVIDIA-driven. Scope: video decode only; GLX stays on NVIDIA so OpenGL games keep the RTX with no wrapper | hybrid | proper, branch `zephyrus/hybrid-video` (VA-API override skipped when the iGPU is found; detector left alone) | n/a | Merged on `quattro` ([#11690](https://github.com/omacom/omarchy/pull/11690)), not in a release yet; backport [#13902](https://github.com/omacom/omarchy/pull/13902) open |
| Defer NVPCF notifications while the RTX sleeps | RTX no longer wakes for 20-25 s at +6-9 W on every 1 % battery drop (13 of 13 drops stock, 0 of 3 patched) | Zephyrus (same firmware on GA605, GA403, GU605) | — | NVIDIA [#1299](https://github.com/NVIDIA/open-gpu-kernel-modules/pull/1299) open; [our test report](https://github.com/NVIDIA/open-gpu-kernel-modules/pull/1299#issuecomment-6205310711) posted | n/a: x86 machines get the driver from Arch, not omarchy-pkgs; carried as a local DKMS patch until NVIDIA merges |
| Hibernate powers off instead of hanging | NVIDIA driver no longer hangs on shutdown after the hibernate image is written | hybrid | — | NVIDIA [#1412](https://github.com/NVIDIA/open-gpu-kernel-modules/pull/1412) open (not ours) | n/a (same reason) |
| Qt Multimedia hardware decode off the RTX | The bar's codec probe held a CUDA context and kept the RTX awake all session | hybrid | not needed | n/a | Resolved: the Omarchy shell no longer uses Qt Multimedia (a test enforces it) |
| RTX held awake on the barrel for HDMI | HDMI plugged into a sleeping RTX races the monitor's EDID (falls back to 1024x768); RTX stays in D0 on the barrel, sleeps on battery and USB-C | GA605KM | proper, branch `zephyrus/hw-quirks` (fork-only until NVIDIA fixes the race) | NVIDIA (EDID race on resume): not reported; **not reproduced 2026-10-16** (3 of 3 plugs into a sleeping RTX came up at the native mode on 610.57.04 with aquamarine 0.15.1), so this fix may be dropped | not proposed |
| No NVIDIA early load in the initramfs | Smaller initramfs, amdgpu early for the LUKS prompt | hybrid | — | n/a | Same idea open, not ours: [#8263](https://github.com/omacom/omarchy/pull/8263), [#10065](https://github.com/omacom/omarchy/pull/10065) |

### CPU power, fans and adapters

| Fix | Effect | Scope | This repo | Upstream | Omarchy |
|---|---|---|---|---|---|
| asusd hands profile and EPP control to one owner | `ChangePlatformProfileOnAc/OnBattery=false`, `PlatformProfileLinkedEpp=false` so asusd stops overriding the power policy | ASUS | proper, branch `zephyrus/power` with migration (post-reboot check pending) | asusctl: not reported | not proposed |
| Power policy by adapter: barrel = full power, battery and USB-C = save | Hooks Omarchy's existing power-source event, no new daemon; USB-C told apart from the barrel through the asus-armoury `charge_mode` attribute | Zephyrus | proper, branch `zephyrus/power`; barrel checked 2026-10-16 (charge_mode 1 → performance, full power); USB-C and battery checks pending | n/a (policy). Kernel: charger-type events not exposed to userspace (idea, not written) | not proposed |
| Battery: EPP `power` with boost on | −0.86 W, lower in 4 of 4 A/B rounds, bursts unchanged | generic (amd_pstate) | — (power-profiles-daemon owns EPP and uses `balance_power`; to propose separately) | n/a | not proposed |
| Battery: fans off at idle | ASUS profile quiet with the AMD profile balanced: fans 0 rpm instead of ~2,000-3,800, median −0.79 W, clocks unchanged | GA605KM | proper, branch `zephyrus/power` (battery check pending; on the barrel it writes nothing) | n/a | not proposed |
| Undersized charger: step down, hold charge during games | On a 140 W brick the EC clamped the CPU to 735 MHz while charging; holding the charge limit at the current level removed the stutter | GA605KM | — | n/a (the EC can't see adapter wattage) | not proposed |
| CPU power limits (SPL/SPPT/FPPT) | **Finding, confirmed 2026-10-16:** the firmware applies them only while the custom CPU fan curve is on. With the curve on, 25 W and 40 W held exactly under full load; without it a 25 W write left the CPU at 48.5 W. Values written earlier apply the moment the curve turns on | Zephyrus family A | n/a (power policy only uses them once a branch enables the curve) | Kernel: `requires_fan_curve` confirmed for the GA605KM entry | n/a |

### Kernel: ASUS drivers

| Fix | Effect | Scope | This repo | Upstream | Omarchy |
|---|---|---|---|---|---|
| hid-asus: pass the Win-lock report through | Fn+Super locks the Windows key; the keyboard then sends a lock report instead of Super, and hid-asus's lighting-echo filter (written for another keyboard, widened twice) drops it, so Super dies silently | ASUS ROG N-Key keyboards | — (local DKMS module) | linux-input: [submitted 2026-09-10](https://patchwork.kernel.org/project/linux-input/patch/20260910055303.1238743-1-ryan.doupe@gmail.com/), no replies; ping drafted | Docs PR open: [#11045](https://github.com/omacom/omarchy/pull/11045) |
| asus-armoury: `nv_tgp` is an offset, table uses absolute watts | On 19 of 19 surveyed models (31 official BIOS images) the firmware adds the value to the base TGP; every comparable kernel table entry uses absolute watts, so the whole allowed range overshoots the firmware maximum | ASUS (AMD + Intel, RTX 40/50) | n/a | platform-driver-x86: report drafted, not sent | n/a |
| asus-armoury: power limits for GA605KM | Exposes Dynamic Boost, thermal target and GPU offset (0-35 W) on this model | GA605KM | n/a | Patch ready; fan-curve gate confirmed; waits on the `nv_tgp` offset report | n/a |
| asus-armoury: FA401UV missing `requires_fan_curve` | Its firmware drops CPU power-limit writes outside fan-curve mode | FA401UV | n/a | Included in the offset report | n/a |

### Display

| Fix | Effect | Scope | This repo | Upstream | Omarchy |
|---|---|---|---|---|---|
| aquamarine ≥ 0.15.1 | 0.14: OLED panel black at Hyprland start; 0.15.0: after HDMI unplug the RTX never sleeps again | Zephyrus OLED | n/a (package version) | aquamarine [#316](https://github.com/hyprwm/aquamarine/pull/316), [#410](https://github.com/hyprwm/aquamarine/pull/410) merged (not ours); 0.15.1 in Arch | Omarchy mirror still serves 0.15.0 |
| Hyprland: windows offset after HDMI replug | Resets the render offset on reconnect | generic | — (local build) | Hyprland [#16140](https://github.com/hyprwm/Hyprland/pull/16140) merged, unreleased (not ours) | not proposed |
| Refresh rate by power source | 240 Hz on AC, 60 Hz on battery | preference | not carried (a preference, not a hardware fix) | n/a | not proposed |

### Sleep and hibernate

| Fix | Effect | Scope | This repo | Upstream | Omarchy |
|---|---|---|---|---|---|
| Touchpad does not wake the laptop | The ASUF1209 touchpad's wakeups aborted a hibernate (129k touchpad wake events in one boot); keyboard, lid and power button still wake | GA605KM (likely Zephyrus) | proper, branch `zephyrus/hw-quirks` | Kernel linux-input: report withdrawn. Tested 2026-10-16: from s2idle only a click wakes it, not a touch, so the 129k wake events are touches counted as wakeup events during hibernate entry (cause unverified) | not proposed |
| `HibernateMode=shutdown` | Platform mode rolled back on a pending wake (2026-10-14: `rolling back`, then `nv_restore_user_channels` warning) and wedged the NVIDIA driver; hard reset, session lost. Shutdown mode has no rollback path | GA605KM (same fix reported on GA403UV) | proper, branch `zephyrus/sleep` (gated on GA605KM, #8017 pattern) | NVIDIA: rollback wedge not reported; post-image power-off hang is [#1412](https://github.com/NVIDIA/open-gpu-kernel-modules/pull/1412) (not ours) | Same fix reported, not ours: [#8589](https://github.com/omacom/omarchy/issues/8589), waits on the maintainer's gating choice; comments for #8589 and [#9696](https://github.com/omacom/omarchy/issues/9696) drafted |
| Hibernate 20 min after suspend on battery | systemd's 60 min default let the battery die in s2idle twice (2026-10-11, 2026-10-14: critical-battery suspend, `Image not found` on next boot) | generic | not carried (upstream-first; local drop-in until a PR lands) | n/a | Open, not ours: [#12125](https://github.com/omacom/omarchy/pull/12125) (lid policy + 20 min), [#13540](https://github.com/omacom/omarchy/pull/13540) (critical battery hibernates directly), [#13610](https://github.com/omacom/omarchy/pull/13610); our data drafted as comments on #12125 and #13540 |
| Idle timeouts by power source, suspend after idle lock on battery | Omarchy has one idle pair and no idle suspend | generic | not carried (local service `omarchy-idle-power` until upstream lands) | Quickshell idle monitor bug: [#8038](https://github.com/omacom/omarchy/issues/8038), [#14438](https://github.com/omacom/omarchy/issues/14438) (not ours) | Open, not ours: [#8595](https://github.com/omacom/omarchy/pull/8595) (per-source pairs), [#11686](https://github.com/omacom/omarchy/pull/11686) (`idle.suspend`); comments drafted |

### Video decode

| Fix | Effect | Scope | This repo | Upstream | Omarchy |
|---|---|---|---|---|---|
| mpv decode pinned to the iGPU | Render node numbers put the RTX first; pinning to the iGPU's by-path node keeps decode on VCN and the RTX asleep | hybrid | proper, branch `zephyrus/hybrid-video` | n/a | `hwdec=auto-safe` merged ([#15172](https://github.com/omacom/omarchy/pull/15172), not ours) doesn't pin the node; issue [#14285](https://github.com/omacom/omarchy/issues/14285) open |
| Chrome/Chromium VA-API on the iGPU | `--render-node-override` with the iGPU's by-path node; YouTube on battery ~9 W instead of ~12 W (with other battery fixes) | hybrid | proper, branch `zephyrus/hybrid-video` | n/a | not proposed; related open: #13081, #12704, #13189 |

### Audio

| Fix | Effect | Scope | This repo | Upstream | Omarchy |
|---|---|---|---|---|---|
| ALC285 hardware Master at 100 % under the soft mixer | Omarchy's ASUS setup leaves 12.75 dB of hidden attenuation | ASUS ROG (ALC285) | — | n/a | Issue open: [#11046](https://github.com/omacom/omarchy/issues/11046) |

### Tried and rejected

Measured on battery and dropped: Wi-Fi power save (dropout risk on the MT7925), PCI runtime PM and ASPM powersupersave tweaks, `amd_pstate` dynamic EPP, the full ASUS quiet profile (caps the CPU at 2 GHz), Windows-style per-core caps, IRQ steering, a session-wide Mesa GLX default (breaks OpenGL games).

## Related work by others

Zephyrus panels and helpers for Omarchy: [omarchy-g14-tools](https://github.com/cashcon57/omarchy-g14-tools), [omarchy-dgpu-control](https://github.com/rawritude/omarchy-dgpu-control), [omarchy-g14-controls](https://github.com/Ayumad/omarchy-g14-controls), [omarchy-armoury](https://github.com/gdeyoung/omarchy-armoury). Open Omarchy work on these laptops: [#13082](https://github.com/omacom/omarchy/pull/13082) (G16 GU605MY backlight), [#8821](https://github.com/omacom/omarchy/pull/8821) (G14 OLED MUX), [#10592](https://github.com/omacom/omarchy/pull/10592) (nvidia-powerd), [#9236](https://github.com/omacom/omarchy/issues/9236) (G14/G16 NVIDIA power spikes).

## Omarchy itself

Everything else is upstream Omarchy, merged regularly from `omacom/omarchy`. The manual lives in [`manual/`](manual/); start with [Welcome to Omarchy!](manual/01-welcome-to-omarchy.md) or read more at [omarchy.org](https://omarchy.org).
