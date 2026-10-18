Branch: `asus/hibernate-mode`

# Hibernate the ROG Zephyrus G16 GA605KM in shutdown mode

Open after the comment on #8589 (g16reverse `upstream/reports/06-omarchy-hibernate-mode-shutdown.md`): the maintainer's gating choice there decides whether this goes up per model (the #8017 pattern).

**Problem.** On the GA605KM, a hibernate in systemd's default platform mode can end in a hard reset. On 2026-10-14 the kernel wrote the image, saw a pending wakeup event and rolled back (`PM: hibernation: Wakeup event detected during hibernation, rolling back.`). The rollback powered the RTX 5060 back up mid-transition, the NVIDIA driver failed to restore its channels (`WARNING: nvidia/nv.c:4524 at nv_restore_user_channels`) and the laptop had to be reset; the session was lost.

**Cause.** Platform mode asks the firmware for ACPI S4 after the snapshot and backs out on any pending wakeup. The rollback path is what wedges the NVIDIA driver on this hybrid machine.

**Change.** `install/hardware/asus/fix-asus-ga605km-hibernate-mode.sh` writes `/etc/systemd/sleep.conf.d/omarchy-asus-ga605km-hibernate-mode.conf` with `HibernateMode=shutdown`, gated on `omarchy-hw-asus-rog && omarchy-hw-match "GA605KM"`. Migration `1792129283.sh` does the same for existing installs and keeps a file that is already there. This is the pattern of #8017 (ThinkBook X IMH). #8589 reports the same fix on the GA403UV; it is not included because this machine can't test it.

**Known limit.** With NVIDIA's driver up to 610.57.04, the power-off after the image is written can hang (NVIDIA/open-gpu-kernel-modules#1412, open). The image is on disk then, so a long power press and a normal boot resume the session. With #1412 applied it powers off by itself. Either way it is better than platform mode's hard reset with a lost session.

**How tested.**
- `test/shell.d/asus-ga605km-hibernate-mode-test.sh` (11 checks): the gate (non-ROG machines and another ROG model get nothing, from the leaf and from the migration), the drop-in content, file mode 644, idempotence (a second run makes no `sudo` call), an administrator's drop-in is kept, and the leaf and the migration write the same text.
- `./test/all` headless: see "Test results".
- On hardware (GA605KM, same setting from a local drop-in since 2026-10-14): `systemctl hibernate` and battery `suspend-then-hibernate` both wrote the image, powered off (patched driver) and resumed, 63 s and 68 s door to door.

This pull request was written with Claude Code.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## Hardware checks still to run (need a real suspend or hibernate)

1. Fresh migration on the live machine: once the branch is merged into the fork and `omarchy update` runs, `systemd-analyze cat-config systemd/sleep.conf` must show `HibernateMode=shutdown` from the new file (the old `20-g16-hibernate-delay.conf` also sets it, so remove that line first to prove the new file alone works), then one `systemctl hibernate` and resume.
2. Stock-driver behaviour: confirm once more that on the unpatched 610.57.04 driver a shutdown-mode hibernate leaves the image intact (long press, resume works). Only needed if the PR text is challenged; the hibernate session saw it on 2026-10-14.

## Not carried here (upstream-first)

- `HibernateDelaySec=20min`, `HibernateOnACPower=no`, lid suspend-then-hibernate: generic; covered by open PRs #12125 and #13540. Evidence drafted as comments in `upstream/reports/07-omarchy-sleep-policy-12125-13540.md`. Local config stays.
- Idle timeouts by power source and battery idle suspend: covered by #8595 and #11686. The local `omarchy-idle-power` service stays until they land. Comments drafted in `upstream/reports/08-omarchy-idle-by-source-8595-11686.md`.
