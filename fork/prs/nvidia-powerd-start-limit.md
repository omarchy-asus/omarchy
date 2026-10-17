Branch: `asus/nvidia-powerd-start-limit`

# Keep nvidia-powerd startable after five charger plug-ins

Branch: `rdoupe-omarchy/omarchy-asus:asus/nvidia-powerd-start-limit` (1 commit on `upstream/quattro` at 5fcdaca64). Needs the omarchy-pkgs companion `omarchy-settings-nvidia-powerd` ([draft](pkgs-omarchy-settings-nvidia-powerd.md)); open both together.

Related: #10592 (enables nvidia-powerd on every NVIDIA laptop; this keeps it startable once something starts and stops it per charger change).

---

**Problem.** On ASUS ROG laptops with an NVIDIA GPU, Dynamic Boost silently stops working after the charger has been plugged in five times since boot. From then until a reboot, the GPU runs without the extra power budget on the barrel adapter.

**Cause.** asusd starts `nvidia-powerd.service` when the charger is plugged in and stops it on unplug (`disable_nvidia_powerd_on_battery`, on by default). nvidia-utils ships the unit with `StartLimitIntervalSec=infinity` and `StartLimitBurst=5`, a crash-loop guard whose window is the whole boot, so every plug-in counts against it. The sixth start is refused:

```
asusd: External power supply state changed: true
systemd: nvidia-powerd.service: Start request repeated too quickly.
systemd: nvidia-powerd.service: Failed with result 'start-limit-hit'.
```

(Zephyrus G16 GA605KM, nvidia-utils 610.57.04, asusctl 6.4.0: five plug-ins on one evening, the next morning's plug-in refused.)

**Change.** A vendor drop-in, `default/systemd/system/nvidia-powerd.service.d/10-omarchy.conf`, shipped by `omarchy-settings` to `/usr/lib/systemd/system/nvidia-powerd.service.d/`, sets `StartLimitIntervalSec=60`. The burst stays 5 and `Restart=on-failure`/`RestartSec=10` stay as packaged, so a crash loop (five restarts in 40 s) still stops; plug-ins minutes apart no longer count. It does nothing on machines without nvidia-powerd and does not change when the service runs. `docs/file-layout.md` describes it next to the plocate drop-in.

**How tested.**
- `test/shell.d/nvidia-powerd-start-limit-test.sh`: the drop-in only sets the window, five 10 s crash restarts still fit inside it, and it parses with `systemd-analyze verify` on top of the unit as nvidia-utils ships it.
- `test/shell.d/config-test.sh` lists the drop-in as a package default; passes with the omarchy-pkgs companion, fails without it.
- On the GA605KM: the refused start above, read from the journal.

This pull request was written with Claude Code and tested on an ASUS ROG Zephyrus G16 GA605KM.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
