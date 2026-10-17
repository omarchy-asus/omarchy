# PR draft: omacom/omarchy-pkgs, from rdoupe-omarchy/omarchy-asus-pkgs `omarchy-settings-source-monitor` (f54cd3d6, on upstream master 29c89f78)

NOT opened. Companion to omacom/omarchy#15668 (`asus/usbc-power`); Ryan opens it with or after #15668. Recipe-only, two files, no `pkgrel` bump (same as #922: the 4.0.4 release has no such unit, so its package is unchanged).

## Title

omarchy-settings: ship the ASUS charger-swap monitor as a user unit

## Body

omacom/omarchy#15668 adds `default/systemd/user/omarchy-powerprofiles-source-monitor.service`, which re-applies the power profile when an ASUS ROG laptop swaps between its barrel adapter and a USB-C charger. First run and a migration enable it. Left only in `/usr/share/omarchy/default/systemd/user`, systemd cannot find it, and Omarchy's `test/shell.d/config-test.sh` reports it as not shipped.

This installs it in `/usr/lib/systemd/user` in `omarchy-settings` and `omarchy-settings-dev`, guarded by `[[ -f ... ]]` the same way #922 ships the USB and Thunderbolt watchers, so sources without the unit build unchanged. The unit's `ConditionPathExists` on the ASUS `charge_mode` attribute keeps it inert on every other machine.

Tested:
- Omarchy's `test/shell.d/config-test.sh` with #15668 applied passes against this branch and fails against master.
- `tests/package-metadata.sh` and `tests/pinned-sources.sh` pass.

This PR was prepared with an AI agent (Claude Code); I reviewed it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
