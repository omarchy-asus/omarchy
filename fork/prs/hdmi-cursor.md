# PR draft: asus/hdmi-cursor (not opened)

Branch: `asus/hdmi-cursor` on rdoupe-omarchy/omarchy-asus, one commit on `upstream/quattro` 51bfd1dba.

**Title:** Use a software cursor while a monitor on the NVIDIA GPU is plugged into a hybrid laptop

## Body

On hybrid laptops the iGPU renders the desktop, but some ports, usually HDMI, are wired to the NVIDIA GPU. Hyprland then has to copy the hardware cursor image across GPUs on every update. With the NVIDIA driver that copy fails every time:

```
EGL (blit): glCheckFramebufferStatus failed: 1282
drm: Backend requires blit, but cursor blit failed
```

On an ASUS ROG Zephyrus G16 (GA605KM: Radeon 860M + RTX 5060, HDMI on the RTX) that was about 74,000 failures in 20 hours, roughly 230 a minute while the mouse moves. aquamarine 0.15.1 also leaks the EGLImage, renderbuffer and framebuffer it creates for each failed attempt (the early return in `Renderer.cpp` `blit()` skips the cleanup), and Hyprland's memory grew to about 900 MB alongside.

Hyprland's default (`cursor:no_hardware_cursors = 2`, auto) only picks a software cursor when the NVIDIA GPU is the renderer, which it is not on a hybrid.

This change adds `default/hypr/hybrid-cursor.lua`, loaded from `nvidia.lua` when an NVIDIA GPU is present:

- It only does anything when an NVIDIA DRM card sits next to a display card from another vendor (cached sysfs `device/vendor`, so the RTX is never woken).
- On `monitor.added`/`monitor.removed` it checks whether any connected monitor's connector belongs to the NVIDIA card (`/sys/class/drm/cardN-<connector>`), not by connector name. If so it sets a software cursor; once the last such monitor is gone it goes back to auto, so the laptop panel keeps its hardware cursor. It checks again a second later because a removed monitor can still be listed while its event runs.
- A value the user sets in their own config is left alone; after a config reload it re-applies.
- No polling: monitor events, `hyprland.start` and `config.reloaded` only.

This is a mitigation. The root causes are the failing cross-GPU cursor blit and aquamarine's leak on that path; an aquamarine report with the leak fix is drafted but not sent yet. Once those are fixed this can be dropped.

### Testing

- New `test/shell.d/hyprland-hybrid-cursor-test.sh` runs the module under a stub `hl` against a fake `/sys/class/drm` (`OMARCHY_DRM_PATH`, as `omarchy-hw-external-monitors` already uses): panel only, a monitor on the NVIDIA card (HDMI and DP), unplug, reload, a user's own value, NVIDIA-only, no NVIDIA, no cards.
- `test/shell.d/hw-nvidia-test.sh` now points `OMARCHY_DRM_PATH` at an empty directory so it doesn't read the test machine's cards.
- `./test/all`, headless: same failures as the base commit (see the commit's test note).
- On the hardware: the same policy (keyed on the HDMI name) has run as a local Hyprland config on the GA605KM since 2026-10-16; the cursor errors stopped while the HDMI monitor was connected and the panel kept its hardware cursor. This exact module has not run inside Hyprland yet.

Written with Claude Code (agent-assisted); tested as described above.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
