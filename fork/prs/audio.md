Branch: `asus/audio`

# PR draft: asus/audio (d8a40e6d0), base omacom/omarchy `quattro`

**Title:** Set the ASUS ROG ALC285 Master to full scale under the soft mixer

**Body:**

## Problem

On ASUS ROG laptops with the Realtek ALC285, the volume slider's 100% is not full volume. On a GA605KM the hardware Master sat 12.75 dB below full scale (#11046).

## Cause

`install/user/hardware/asus/fix-audio-mixer.sh` turns on `api.alsa.soft-mixer` for every ALSA card, which moves volume and mute into software and leaves the hardware mixer where it is. It then set the ALC285 `Master` to `80% unmute`. The soft mixer never touches `Master` again, and `fix-mic.sh`'s `alsactl store` (plus `alsa-restore.service` at boot and shutdown) keeps the 80%. On a 0-87 codec at 0.75 dB per step, 80% is step 70, 12.75 dB below the top. The commit that added the line only meant to unmute.

## Change

- Install unmutes `Master` at 100% instead of 80%. 100% is 0 dB on this codec, no gain above the codec's full scale.
- Existing installs are **not changed**: raising `Master` during `omarchy update` would make the speakers jump 12.75 dB at the same slider setting. Migration `1792162887.sh` only finds installs still at the exact old install level and tells the user once how to lift the cap, in the update output and as a desktop notification (the same pattern as `1787494718.sh`, since the echo scrolls past once). The message gives the exact command, e.g. `amixer -c Generic_1 set Master 100% unmute` (the card's ALSA id, which survives card renumbering); `alsa-restore.service` stores it at shutdown. It stays silent on non-ROG machines, without an ALC285, without the soft-mixer drop-in (PipeWire drives `Master` there, so 80% is just the volume), and at any other level. It never writes the mixer.

This implements option 1 of #11046. To limit it to boards confirmed safe (the smart-amp concern from #8359), the migration and install line can be gated on `omarchy-hw-match` instead; say so and I'll narrow it.

## Tests

- `test/shell.d/asus-rog-master-volume-test.sh` (new, stubs `omarchy-hw-asus-rog`, `aplay`, `amixer`, `omarchy-notification-send`): install sets 100%; the migration never runs `amixer set` in any case; at the old 80% it sends exactly one notification and prints the exact command; it is silent at 69% and 100%, on non-ROG machines, without an ALC285, and without the soft-mixer drop-in. 5/5 pass.
- `./test/all` headless (first version of this branch; the migration change since only touches the migration and its test): 22 failing files on stock `quattro` 51bfd1dba, 24 on this branch. The two extra (`emojis-test.sh`, `hermes-remove-test.sh`) passed 3 of 3 reruns each; both suites ran at the same time, so they look load-related. None touch the changed files.
- Hardware: the 12.75 dB figure was measured on a GA605KM (BIOS 307) on 2026-09-09 with the soft mixer on (`amixer -c 2 sget Master`: step 70 of 87, -12.75 dB); 100% read 0.00 dB. Not re-measured on this branch, because that machine currently runs without the soft-mixer drop-in.

Part of #11046: new installs get Master at 100 %; existing installs are told the one command and are never made louder by an update, so the issue stays open for them until they run it.

This PR was written with Claude Code (an AI agent); I reviewed it and ran the tests.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

## Notes (not part of the PR)

- #7459 (open, not ours) edits the same `fix-audio-mixer.sh`; whichever merges second needs a rebase. Intent does not conflict ("Master is left alone; it is set once at install").
- omarchybot (2026-10-11) said the choice among the options is the maintainer's. Consider a one-line comment on #11046 pointing at this PR rather than opening cold.
- Ported from the uncommitted 2026-10-04 draft in `~/Work/omarchy/omarchy-asus-master` (left untouched), plus the soft-mixer guard and a fresh timestamp.
