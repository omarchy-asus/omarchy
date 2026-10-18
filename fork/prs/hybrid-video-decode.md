Branch: `asus/hybrid-video-decode`

# Keep video decode on the iGPU of hybrid NVIDIA laptops

Branch: `rdoupe-omarchy/omarchy-asus:asus/hybrid-video-decode` (3 commits on `upstream/quattro` at 51bfd1dba; restructured 2026-10-16 to scope the change to video decode)

---

Refs #14285. Related: #13081, #12704, #11690.

On a hybrid laptop whose iGPU drives the panel, playing a video in mpv or Chromium can still decode on the NVIDIA GPU and pull it out of runtime suspend. #11690 stopped forcing NVIDIA's VA-API/GLX drivers on those machines, but that is not enough on its own, and on some machines it does not apply at all. This PR only moves video decode; which GPU OpenGL uses is left as it is.

## Cause

Two things, both measured on an ASUS Zephyrus G16 GA605KM (Ryzen AI 7 350 / Radeon 860M + RTX 5060 Laptop):

1. **Render nodes follow PCI order, not the display.** The RTX is `0000:64:00.0` and the iGPU `0000:65:00.0`, so the RTX gets `renderD128` on most boots, and the numbers can swap between boots. libva, mpv and Chromium open `renderD128` or let the driver pick when nothing names a node, so with `LIBVA_DRIVER_NAME` unset mpv still decodes on NVDEC. mpv's `hwdec=auto-safe` (#15172) can also settle on NVDEC, which loads CUDA. Either way the dGPU wakes for work the iGPU's VCN does at a fraction of the power.
2. **`omarchy-hw-nvidia-display` cannot see this iGPU.** AMD Krackan presents its iGPU as a non-VGA display controller (class `0x038000`), which has no `boot_vga` attribute. The RTX reports `boot_vga=0`, nothing reports `1`, so the detector falls back to "NVIDIA drives the display" and `nvidia.lua` keeps exporting `LIBVA_DRIVER_NAME=nvidia` (and `__GLX_VENDOR_LIBRARY_NAME=nvidia`) on the iGPU session.

What `nvidia.lua` sets on `quattro` (#11690), per path:

| Path | `NVD_BACKEND` | `LIBVA_DRIVER_NAME` | `__GLX_VENDOR_LIBRARY_NAME` |
|---|---|---|---|
| GSP NVIDIA (Turing+), NVIDIA drives the display (includes the G16 today) | `direct` | `nvidia` | `nvidia` |
| GSP NVIDIA, iGPU claims `boot_vga` | `direct` | unset | unset |
| Pre-GSP NVIDIA (Maxwell to Volta), NVIDIA drives the display | `egl` | unset | `nvidia` |
| Pre-GSP NVIDIA, iGPU claims `boot_vga` | `egl` | unset | unset |
| No NVIDIA, or unsupported (Kepler) | unset | unset | unset |

## Why not fix the detector

Making `omarchy-hw-nvidia-display` answer "iGPU" on Krackan would also drop `__GLX_VENDOR_LIBRARY_NAME=nvidia`, so OpenGL games (Steam's GL titles, GL-only native ports) would run on the 860M unless every user added an offload wrapper. That would be a behaviour change for gaming that this PR does not mean to make. So the detector is unchanged, and only the VA-API override and the decode pins move. If maintainers would rather have Krackan follow #11690's hybrid path completely (no GLX override, offload per game), that is a one-line follow-up in `omarchy-hw-nvidia-display`.

## Change

- `omarchy-hw-igpu-render-node` (new) prints the stable `/dev/dri/by-path/pci-<BDF>-render` of the iGPU that drives the panel next to an NVIDIA GPU: the one that claims `boot_vga`, or, when the NVIDIA GPU reports `boot_vga=0`, the single non-NVIDIA display device that has no `boot_vga` (Krackan). It exits 1 everywhere else (no NVIDIA, NVIDIA claims `boot_vga`, nothing to tell from, no render node). Like the other detectors it reads cached sysfs only, never `lspci`.
- `nvidia.lua`: on the GSP path, `LIBVA_DRIVER_NAME=nvidia` is skipped when that helper finds the iGPU. `NVD_BACKEND` and `__GLX_VENDOR_LIBRARY_NAME` are untouched, so on the G16 the only env change is that VA-API is no longer forced to NVIDIA. On #11690's hybrids the helper changes nothing (the override was already off). A migration asks for a reboot only when the running session still carries `LIBVA_DRIVER_NAME=nvidia` and the helper finds an iGPU, since Hyprland's env is fixed at startup.
- `install/helpers/hybrid-video-decode.sh` pins on those machines only:
  - mpv: adds `hwdec=vaapi` and `vaapi-device=<node>` to the top of `~/.config/mpv/mpv.conf` (ahead of any `[profile]`), only for options the user has not set at top level. `/etc/mpv/mpv.conf` stays `hwdec=auto-safe` for everyone else.
  - Chromium, Chrome, Edge, Brave, Brave Origin: appends `--render-node-override=<node>` to flags files the user already has, unless one is there.
- Applied by a per-user hardware leaf (new users), `omarchy-install-browser` and `omarchy-refresh-chromium` (both copy the default flags over the user's file), and a migration for existing installs. Same shape as the Google account flags in `omarchy-refresh-chromium`.
- `omarchy-cmd-browser-handoff` accepts `--render-node-override` as a process flag the running browser already has, so the pin does not turn off the fast handoff.

Machines without an NVIDIA GPU, NVIDIA-only machines and hybrids where NVIDIA drives the display get no change. No machine gets a different GLX vendor than it has today.

Overlap: #15293 (not ours, open) fixes the display-GPU check for class 0x0380 iGPUs, the reason the comment in `nvidia.lua` gives for NVIDIA's VA-API being chosen on Krackan. With it, the G16 undocked no longer gets the NVIDIA env at all; docked over HDMI (port wired to the dGPU) both GPUs claim and it still does, so the `omarchy-hw-igpu-render-node` guard here still matters. If #15293 lands first, reword that comment to the docked case. `test/shell.d/hw-nvidia-test.sh` conflicts textually with it (both add rows); whichever lands second rebases. Draft G16 review comment for #15293: `~/Work/g16reverse/upstream/reports/12-omarchy-15293-display-gpu.md`.

Not covered: #14285 also reports mpv's Vulkan device enumeration (`vo=gpu-next`) resuming the dGPU on an Intel + RTX 5070 machine. This PR fixes the decode path; if enumeration still wakes the card there, `VK_LOADER_DRIVERS_DISABLE` scoped to mpv is the follow-up that issue suggests.

## Evidence (G16 GA605KM, nvidia-open 610.57.04, mesa 26.2.2, mpv 0.41.0)

- mpv with `hwdec=vaapi` and `vaapi-device` on the iGPU by-path node decodes H.264/HEVC/VP9/AV1 on VCN at 4 to 9x less CPU than software decode, and the RTX stays `suspended`. Without the node, mpv holds `renderD128`, `nvidia0`, `nvidiactl` and `nvidia-uvm` whether `LIBVA_DRIVER_NAME` is `nvidia` or unset.
- Chrome with `--render-node-override=/dev/dri/by-path/pci-0000:65:00.0-render` keeps its GPU process and VA-API decode on the iGPU (amdgpu fdinfo shows decode engine time, no NVIDIA fds). YouTube on battery draws about 9 W against about 12 W without the pin.

## Tests

- `test/shell.d/hw-nvidia-test.sh`: two new topologies through the real `nvidia.lua` (non-VGA AMD iGPU next to a VGA RTX with `boot_vga=0` gives `direct - nvidia`: VA-API unforced, GLX kept; next to a 3D-controller NVIDIA without `boot_vga` keeps `direct nvidia nvidia`), every case now with render nodes present, plus the reboot migration.
- `test/shell.d/hw-igpu-render-node-test.sh`: G16, Intel and AMD `boot_vga` hybrids, NVIDIA as display, no `boot_vga` anywhere, non-VGA iGPU next to an NVIDIA without `boot_vga`, single-GPU machines, missing render node, and an `lspci` stub that fails if run.
- `test/shell.d/hybrid-video-decode-test.sh`: the migration on mocked PCI trees (run twice, symlinked and newline-less flags files, user-chosen `hwdec`, `vaapi-device` in a profile and an existing `--render-node-override` kept, nothing written on three non-applicable machines), the per-user leaf, and `omarchy-refresh-chromium` keeping the pin.
- `brave-widevine-test.sh` stubs the new helper; `browser-handoff-test.sh` hands off with the pin in the flags file.
- `./test/all` headless (no `WAYLAND_DISPLAY`, `DISPLAY` or `HYPRLAND_INSTANCE_SIGNATURE`): `./test/cli` passes; `./test/shell` has the same 22 failing files on this branch (448 files) as on stock `quattro` (446 files), both run from a clean checkout outside the home directory, all from the sandbox (no `lspci`, `hyprctl`, `sudo` or browsers on `PATH`, no session bus), none in the touched areas. `default-apps-test.sh` and `platform-app-hooks-test.sh` now run the browser installer against an empty or stubbed GPU tree so the result does not depend on the machine.

Written with Claude Code (Claude Opus 5.5); the measurements are from my own G16.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## Verify on the G16 without waking the RTX (not part of the PR body)

Only cached sysfs and `/proc` are read. Do not run `nvidia-smi`, `lspci`, or read `/proc/driver/nvidia`.

```bash
# 0. Install the branch (omarchy dev link or package), run migrations, reboot.
omarchy-migrate

# 1. Detection: iGPU is the display GPU, and its stable render node.
omarchy-hw-nvidia-display; echo "nvidia-display=$? (want 0: unchanged, GLX stays on NVIDIA)"
omarchy-hw-igpu-render-node            # want /dev/dri/by-path/pci-0000:65:00.0-render
printenv LIBVA_DRIVER_NAME             # want empty after reboot (the local hyprland.lua radeonsi override can go)
printenv __GLX_VENDOR_LIBRARY_NAME     # want nvidia (OpenGL games on the RTX, unchanged)

# 2. Pins written.
head -3 ~/.config/mpv/mpv.conf
grep -H -- --render-node-override ~/.config/{chromium,chrome}-flags.conf

# 3. Watch the RTX while playing video in mpv, then in Chrome (YouTube).
rtx=/sys/bus/pci/devices/0000:64:00.0/power/runtime_status
while sleep 1; do printf '%s %s\n' "$(date +%T)" "$(<$rtx)"; done   # want "suspended" throughout

# 4. Decode engine usage on the iGPU (amdgpu fdinfo), sampled twice 5 s apart.
#    VCN 4 decodes on the unified queue, so the time can show under drm-engine-enc rather than drm-engine-dec.
engines() { for f in /proc/$1/fdinfo/*; do grep -q 'drm-driver:.*amdgpu' "$f" 2>/dev/null && grep -hE 'drm-pdev|drm-engine-(dec|enc|gfx)' "$f"; done | sort | uniq; }
pid=$(pgrep -nx mpv); engines $pid; sleep 5; engines $pid
gpu=$(pgrep -nf 'chrome.*type=gpu-process'); engines $gpu; sleep 5; engines $gpu

# 5. No NVIDIA device files held by the players (want no output).
ls -l /proc/$pid/fd /proc/$gpu/fd 2>/dev/null | grep -E 'nvidia|pci-0000:64'
for f in /proc/$pid/fd/* /proc/$gpu/fd/*; do t=$(readlink "$f"); [[ $t == /dev/dri/renderD* ]] && echo "$t -> $(readlink -f /dev/dri/by-path/pci-0000:64:00.0-render)"; done
```

## Open questions

- Background, not changed here: `__GLX_VENDOR_LIBRARY_NAME=nvidia` makes every GLX client (X11/XWayland OpenGL apps, e.g. Steam's client UI if it uses GLX, GL games, `glxinfo`) load NVIDIA's libGLX, which opens `/dev/nvidia*` and resumes the RTX for as long as that client runs. Wayland-native EGL and Vulkan clients are not affected by it (glvnd picks the EGL/Vulkan vendor by device). So on the G16 any running XWayland GL app keeps the RTX awake; that is today's behaviour and the price of games just working. Inferred from how glvnd dispatches, not measured on this branch.

- MUX "Ultimate"/dGPU-only mode on the G16: does the firmware then set `boot_vga=1` on the RTX (so the pin correctly turns off)? Needs a check on the machine after switching modes.
- Fresh installs: the per-user leaf only pins when `/dev/dri/by-path/pci-<iGPU>-render` exists while it runs; the migration and `omarchy-refresh-chromium` catch up later otherwise.
- A pin goes stale if the iGPU's PCI address changes (BIOS update, eGPU). mpv then falls back to software decode; what Chromium does with a missing override node is untested.

## Pins that go stale

The pins name the iGPU's render node by PCI path. A MUX switch to the dGPU, an iGPU turned off in firmware or a BIOS update that moves the PCI address leaves a pin pointing at nothing, and decode would fall back to software. `nvidia.lua` checks the pins at config load (the config files and cached sysfs IDs only, no device opened) and, only when one is stale, runs `omarchy-refresh-hybrid-video` at Hyprland start: it drops by-path pins that no longer name a non-NVIDIA display device and pins again to the iGPU that is there now. Pins the user set by device number are left alone. `test/shell.d/hybrid-video-decode-test.sh` covers a moved iGPU and a machine with no iGPU.

## Known limits

Only mpv and the Chromium-family browsers are pinned. With `LIBVA_DRIVER_NAME` no longer forced, any other VA-API client that opens the first render node (GStreamer, ffmpeg's and `vainfo`'s defaults, some Electron apps) opens renderD128, which on the G16 is the RTX: it loads NVIDIA's VA-API driver and wakes the GPU, as it did before this change. This is not a regression, but decode does not move to the iGPU for those programs.
