# asus/rtkit: PR draft for omacom/omarchy

Branch: `asus/rtkit` (f47858637), one commit on upstream `quattro` 51bfd1dba.

**Title:** Install rtkit on x86_64 too so PipeWire gets realtime scheduling

**Body:**

### Problem

On x86_64, no PipeWire thread runs with realtime scheduling. `rtkit` is listed only in `install/omarchy-aarch64.packages`, with the comment "Nothing pulls rtkit in on aarch64", which implies something does pull it in on x86_64. Nothing does any more: on an x86_64 Omarchy 4.0.4 install from the 2026-09 ISO, `rtkit` was not installed and `pactree -r rtkit` is empty (it is only an optional dependency of `pipewire` and `xdg-desktop-portal`). The ISO's recorded fresh-install manifest from 2026-05 still has `rtkit` as a dependency, so whatever pulled it in back then no longer does.

### Change

- Move `rtkit` from `omarchy-aarch64.packages` to `omarchy-base.packages`, so every platform installs it (the platform test forbids listing it twice).
- A migration installs it on existing systems (`omarchy-pkg-add rtkit`). The N1x migration that installs it on that platform stays as it is.

### Testing

- `test/shell.d/platform-packages-test.sh` passes; `./test/all` shows no new failures against `quattro` (headless).
- On an ASUS ROG Zephyrus G16 (GA605KM): after installing `rtkit`, PipeWire's data loop runs `SCHED_RR` priority 20 (`ps -eLo cls,rtprio,comm | grep data-loop`); before, every PipeWire thread was `TS`.

This pull request was written with Claude Code; I reviewed and tested it.

**Packaging.** No omarchy-pkgs change is needed: the installer and the ISO's offline mirror read `install/omarchy-base.packages` directly (the omarchy package's `depends` hold only the packages whose removal would break the desktop), and existing installs get rtkit from the migration. The list stays alphabetical, with the reason next to the entry.
