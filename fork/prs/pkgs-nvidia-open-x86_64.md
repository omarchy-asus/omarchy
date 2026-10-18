# PR draft: omacom/omarchy-pkgs, from rdoupe-omarchy/omarchy-asus-pkgs `nvidia-open-x86_64` (9c7c0a1b)

NOT opened. Ryan reviews it and opens it from his account, or asks for it to be opened. One package, recipe-only (`pkgbuilds/nvidia-open-dkms/`), so it qualifies for the self-merge path once builds are approved (`build-approved` label; we are not in VOUCHED.td).

## Title

nvidia-open-dkms: build for x86_64 too, with NVIDIA PRs #1299 and #1412

## Body

Builds the existing `nvidia-open-dkms` recipe for x86_64 as well, so Omarchy's NVIDIA laptops get two driver fixes that are still pending upstream. On x86_64 the package replaces Arch's `nvidia-open-dkms` of the same version (615.78.08); `nvidia-utils` still comes from Arch.

- **[NVIDIA PR #1299](https://github.com/NVIDIA/open-gpu-kernel-modules/pull/1299)** (Lars Nieradzik, `0010`/`0011`, both commits with authorship): on hybrid laptops the firmware sends an NVPCF notification on every battery percent, and each one woke a runtime-suspended GPU from D3cold for 20-25 s at +6-9 W. They are now coalesced while the GPU sleeps and replayed after resume. ASUS ROG Zephyrus G16 GA605KM (RTX 5060 Laptop) on battery: the stock driver woke for 13 of 13 battery steps, patched 0 of 3. Who benefits, from the ACPI of 69 ASUS BIOS images (GPU variants of a board share it): the per-percent wakes are in the 2024-2025 Zephyrus G14 and G16 (AMD and Intel), ProArt P16, and the 2024-2025 TUF A16 and TUF A18; the AMD Strix/Scar, the 2025 Intel Strix/Scar and TUF A14 get at most one NVPCF notify per charger plug or unplug; the 2022-2024 Intel Strix/Scar, TUF A15/F15/F16 and older Zephyrus have no battery path. Other vendors were not checked. On desktops and laptops without NVPCF the patched code never runs.
- **[NVIDIA PR #1412](https://github.com/NVIDIA/open-gpu-kernel-modules/pull/1412)** (Hans van Essen, `0012`): after the hibernation image is written, `nv_pci_shutdown()` tore down a GPU that was still suspended and power-off hung. Same G16: stock never powered off after writing the image; patched, 4 of 4 hibernations powered off and resumed with no driver errors.
- `0008` (#1368, the nvkms callback leak) already in the recipe is arch-independent and now applies on x86_64 too.

The N1x patches (`0003`-`0007`, `0009`) move to `source_aarch64` and apply on aarch64 only, in the same order as before. `pkgrel` goes 3 → 4. Since the recipe's version doesn't move, the aarch64 package is rebuilt as well and now also carries `0010`-`0012`.

Tested:
- All three upstream commits `git am` cleanly onto the 615.78.08 source, and their changed lines are identical to the PRs. Both arches' patch series apply with `patch --fuzz=0` (x86_64: 0008, 0010-0012; aarch64: 0003-0012).
- `makepkg` on x86_64: only the shared patches are applied, and the package has no `.orig`/`.rej` files. Its dependencies, provides, conflicts and replaces match Arch's x86_64 `nvidia-open-dkms` 615.78.08-1.
- The packaged DKMS tree builds all five modules against `linux-omarchy` 7.2.5-3 headers. 610.57.04 with the same two patches has run on the G16 since 2026-10-14/15, which is where the numbers above come from.
- Not done: running 615 with these patches on hardware, and building or booting the aarch64 package. The aarch64 build is left to CI; it was only checked for patch application.
- `tests/pinned-sources.sh` and `tests/package-metadata.sh` pass.

This PR was prepared with an AI agent (Claude Code) working from my measurements; I reviewed it.

## Risks and how this fits the release process (for the maintainers; also summarise in the PR)

1. **Who gets it.** On x86_64, `[omarchy]` comes before `[extra]`, so every Omarchy machine that has `nvidia-open-dkms` installed switches to this build. That's everyone who went through `install/hardware/nvidia.sh` with a Turing-or-newer GPU. Machines on Arch's prebuilt `nvidia-open` aren't affected: it conflicts with this package, and nothing pulls this one in on those machines.
   - Mitigation: the metadata already limits the package to `edge`. It reaches `rc`/`stable` only with a release train, after edge users have run it.
   - Neither patch changes behaviour on a desktop GPU without runtime D3. #1299 only acts on NVPCF ACPI notifications while runtime-suspended, and #1412 only when `NV_FLAG_SUSPENDED` is set at shutdown.
2. **Version pin.** The package depends on `nvidia-utils=615.78.08`, and on x86_64 that comes from Arch. When a channel's Arch snapshot moves to a newer `nvidia-utils`, `pacman -Syu` fails on the broken dependency until this recipe is bumped. That's the same coupling the aarch64 overlay already has with Arch Linux ARM, but on x86_64 the snapshot moves on its own schedule.
   - Mitigations, pick one:
     - (a) Bump this recipe in the same change that advances a channel's mirror snapshot past a driver change. The README says so.
     - (b) Add a `json` watch on Arch's package API (`https://archlinux.org/packages/extra/x86_64/nvidia-utils/json/`, path `pkgver`), with `"sync": true` on the reviewed lane. Bumps then arrive as PRs; if a patch stops applying, the PR goes red instead of shipping. The watch has to check that the patches still apply, which a build does.
     - (c) Ship x86_64 to `edge` only for now (the current `channels`) and decide later.
   - We'd do the 615.x bumps ourselves (rebased patches as a follow-up PR) if that helps.
3. **aarch64 changes too.** The N1x driver gains `0010`-`0012`. They're generic Linux PM paths and are inert there unless the firmware sends NVPCF notifications or the machine hibernates, but they do change a validated driver.
   - If that's unwanted, a one-line change moves `0010`-`0012` to `source_x86_64`, and we can change the PR that way.
4. **Removal.** Drop each patch once NVIDIA ships it in a release. Neither is in 615.78.08: thaw is still a no-op and `rm_acpi_nvpcf_notify()` is unchanged. NVIDIA said on #1286 that there will be no more 610 releases. #1412 is waiting on its author's NVIDIA CLA.
5. **Prebuilt modules.** This is DKMS only, like Arch's `nvidia-open-dkms`, so every kernel update rebuilds it locally, as it does today. No prebuilt `nvidia-open` for `linux-omarchy` is proposed.

## Before opening

- Re-check that #1299/#1412 are still open and unchanged (`gh pr diff`). If NVIDIA has shipped either, drop it.
- Optionally run the 615 package on the G16 first (`~/Work/omarchy-g16/builds/nvidia-open-dkms-615/INSTALL.md`) and replace "Not done: running 615" with the result.
