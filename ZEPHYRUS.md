# Omarchy Zephyrus

A public fork of [Omarchy](https://github.com/omacom/omarchy) for ASUS ROG Zephyrus laptops (G14, G16), in the style of omarchy-mac: a complete, working Omarchy for these machines, where every change is staged and proven before it is offered upstream as its own pull request. Reference machine: Zephyrus G16 GA605KM (Ryzen AI 7 350, Radeon 860M, RTX 5060 Laptop), BIOS 307.

This file is the only fork-specific file at the root. Everything else follows upstream's layout so each change can be cherry-picked into a pull request unchanged.

## How this fork tracks upstream

- `quattro` follows `omacom/omarchy` `quattro`; merge upstream with `git fetch upstream && git merge upstream/quattro`.
- Each change lives on its own branch (`zephyrus/<topic>`), one atomic commit per coherent change, then merges into `quattro` here and is opened upstream from the same branch.
- When upstream merges a change, drop the fork's copy on the next upstream merge.

## Upstream's rules this fork follows (from `AGENTS.md`, `agents/skills/`, `docs/`, `.github/`)

- Upstream first: a missing or broken piece gets fixed where it belongs (kernel, NVIDIA, asusctl) and the gap stays visible meanwhile. A workaround here is a last resort, with the reason written next to the code. Kernel and driver findings go to their maintainers directly, not through this fork.
- Hardware setup lives in `install/hardware/<vendor-or-family>/`, gated by a predicate. Family-wide behaviour uses `omarchy-hw-asus-rog` (plus a Zephyrus predicate if one is needed); a single model's quirk stays behind `omarchy-hw-match` on its DMI name.
- Commands start with `omarchy-` and use the documented prefixes (`hw-`, `toggle-`, `setup-`, ...); command metadata follows `agents/skills/command-metadata.md`; new browsable groups go in `GROUP_DESCRIPTIONS` in `bin/omarchy`.
- Install and migration work follows `agents/skills/install-scripts.md` and `agents/skills/migrations.md`; existing installs get a migration.
- Bash style: `#!/bin/bash`, two-space indent, `[[ ]]` for strings and files, `(( ))` for numbers, full `if`/`else` for two-path flow, quoted paths instead of escaped spaces.
- Use the helpers: `omarchy-pkg-add`/`omarchy-pkg-drop`, `omarchy-cmd-present`/`omarchy-cmd-missing` only for optional dependencies, `omarchy-notification-send`, `$OMARCHY_PATH` (never derived from `HOME`).
- Privilege escalation follows the "Privilege Escalation" section of `default/agents/skills/omarchy/SKILL.md`.
- Long-running code reacts to events (udev, logind, inotify, Hyprland events), never a timer poll; the idle-spawn and budget tests in `docs/testing.md` must stay green.
- Tests: focused tests under `test/shell.d/*-test.sh`, `./test/all` before a pull request; visual changes are verified per `agents/skills/visual-verification.md`; graphical acceptance runs only in a disposable VM.
- Markdown in `docs/`, `manual/`, `plans/`: full lines, no hard wrapping. End-user docs go in `manual/`, internals in `docs/`.
- Issues on `omacom/omarchy` are for verified bugs only; ideas go to Discussions (Suggestions), support to Discord.
- Pull requests (from recent merges): a short imperative title that names the user-visible outcome ("Keep ...", "Fix ... on ..."); a body that states the problem, the cause, the change and how it was tested. Agent-written pull requests are accepted; say so in the body.

## Planned changes

| # | Change | Where it goes upstream | State |
|---|---|---|---|
| 1 | Hybrid GPU: stop forcing NVIDIA VA-API/GLX when NVIDIA does not drive the display | Already open upstream as omacom/omarchy#13902; test on the G16 and comment there instead of duplicating | to test |
| 2 | Adapter-aware power profiles (barrel = full power, battery and USB-C = save), EPP/boost bundle, asusd not rewriting its config | `install/hardware/asus/` + an event-driven `omarchy-` service | to port from rog-power v2 |
| 3 | Battery fans off: ASUS profile quiet with the AMD profile balanced (fans 0 rpm, about 0.8 W saved, clocks unchanged) | part of 2 | to port |
| 4 | NVIDIA PR #1299 (no RTX wake on battery-level ACPI events) | omacom/omarchy-pkgs `nvidia-open-dkms`, which already carries an unmerged NVIDIA fix | after NVIDIA responds |
| 5 | asus-armoury `nv_tgp` offsets for all models, GA605KM entry | kernel (platform-driver-x86), report first | report to draft |

## Evidence

Measurements, firmware analysis and test logs live in the private research repo (`g16reverse`); each pull request quotes the evidence it needs.
