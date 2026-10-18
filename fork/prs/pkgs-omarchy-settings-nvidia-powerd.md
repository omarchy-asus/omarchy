# PR draft: omacom/omarchy-pkgs, from rdoupe-omarchy/omarchy-asus-pkgs `omarchy-settings-nvidia-powerd` (25c4f5a4, on upstream master 6350bf7e)

NOT opened. Companion to `asus/nvidia-powerd-start-limit` ([draft](nvidia-powerd-start-limit.md)); open both together. Recipe-only, two files, no `pkgrel` bump.

## Title

omarchy-settings: ship the nvidia-powerd start-limit drop-in

## Body

omacom/omarchy#<PR> adds `default/systemd/system/nvidia-powerd.service.d/10-omarchy.conf`, which gives nvidia-powerd's five-start limit a one-minute window instead of the whole boot, so asusd's start on every charger plug-in keeps working after the fifth.

This installs it in `/usr/lib/systemd/system/nvidia-powerd.service.d/` in `omarchy-settings` and `omarchy-settings-dev`, next to the plocate drop-in, guarded by `[[ -f ... ]]` so release pins without the file build unchanged.

Tested:
- Omarchy's `test/shell.d/config-test.sh` with omacom/omarchy#<PR> applied passes against this branch and fails against master.
- `tests/package-metadata.sh` and `tests/pinned-sources.sh` pass.

This PR was prepared with an AI agent (Claude Code); I reviewed it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
