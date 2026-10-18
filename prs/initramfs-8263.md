# carry/initramfs-8263: carried upstream PR (not ours; do not open a PR)

Branch: `carry/initramfs-8263`, edbron's two commits from omacom/omarchy#8263 cherry-picked onto upstream `quattro` 51bfd1dba with authorship kept (a1a42cb07, 83772736a). No conflicts.

Why this one and not #10065:
- #8263 is narrow (hybrid machines only; NVIDIA-only machines unchanged), merges cleanly, has two independent confirmations (ThinkPad T480 with 580xx, an AMD iGPU + NVIDIA report) and two omarchybot reviews with no defect found.
- #10065 changes every hibernation setup (strips `kms`, simpledrm Plymouth, initramfs blacklist), conflicts with `quattro`, and was not tested through a real hibernate cycle.

On the GA605KM: `bin/omarchy-hw-nvidia-only-display` returns false (the Krackan iGPU is a 0x0380 display controller, which its `0x03*` match counts), so `nvidia.conf` is not written and the migration removes an existing one. The local machine already runs this way (`/etc/mkinitcpio.conf.d/nvidia.conf.disabled`).

Upstream action for us: a short comment on #8263 confirming it on an AMD Krackan + RTX 5060 laptop once the fork build has run a real hibernate with it (resume worked here 4 of 4 with the NVIDIA early load already removed). Drop this branch when #8263 merges.
