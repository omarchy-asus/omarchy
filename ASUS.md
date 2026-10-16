# Omarchy ASUS

A public fork of [Omarchy](https://github.com/omacom/omarchy) for ASUS laptops (ROG Zephyrus, Strix and Flow, TUF, ProArt), in the style of omarchy-mac: a complete, working Omarchy for these machines, where every change is staged and proven before it is offered upstream as its own pull request. Reference machine: Zephyrus G16 GA605KM (Ryzen AI 7 350, Radeon 860M, RTX 5060 Laptop), BIOS 307.

The fork's own files are this one, `README.md` and `fork/`. Everything else follows upstream's layout, so each fix is a pull request as it stands.

## Using it

Omarchy 4 runs from the `omarchy` package; a git checkout replaces it with `omarchy dev link`:

```bash
git clone https://github.com/rdoupe-omarchy/omarchy-asus.git ~/omarchy-asus
omarchy dev link ~/omarchy-asus     # reboot when it asks
```

`quattro` only moves forward, so `omarchy update` keeps pulling it (`omarchy-update-dev` pulls `--ff-only`). Hardware setup and migrations run as they do upstream; every fix is gated on the hardware it is for, so on other machines the fork behaves like stock Omarchy. `omarchy dev unlink` goes back to the package.

The link covers only what Omarchy runs out of its checkout. Files at fixed system paths come from the packages: `omarchy-settings` copies `etc/` (the asusd drop-in, the quiet-fans sudoers grant) and `omarchy` installs `bin/` into `/usr/bin` (the quiet-fans helper sudo runs). Build both from the checkout with the pkgs fork's recipes:

```bash
git clone https://github.com/rdoupe-omarchy/omarchy-asus-pkgs.git ~/omarchy-asus-pkgs
OMARCHY_PKGBUILDS_DIR=~/omarchy-asus-pkgs/pkgbuilds omarchy dev pkg-test omarchy-settings ~/omarchy-asus
OMARCHY_PKGBUILDS_DIR=~/omarchy-asus-pkgs/pkgbuilds omarchy dev pkg-test omarchy ~/omarchy-asus
```

Without them the asusd drop-in and quiet fans stay off; the quiet-fans helper logs that once per boot (`journalctl -t omarchy-powerprofiles-asus-quiet-fans`), and the asusd migration's one-off D-Bus write still applies until asusd's config is reset.

## How the fork is built

- `quattro` (default branch, the one to install): upstream `quattro` merged in, then one `--no-ff` merge per fix. `git log --first-parent quattro` lists the fixes.
- Topic branches, one per pull request, always rebased on upstream `quattro`: `asus/*` for ASUS hardware, `perf/*` for generic fixes found while profiling, `carry/*` for other people's open upstream pull requests the fork carries until they merge. `fork/branches` lists them in order, with each one's pull request draft in `fork/prs/`.
- `asus/stack`: upstream `quattro`, one commit with the fork's own files, then every topic branch's commits in order. The whole fork as one linear series, for reading or bisecting; it is rebuilt from scratch, so do not install from it.
- `fork/sync` does all of it: fetch upstream, rebase the topic branches, merge into `quattro`, rebuild `asus/stack`, and report branches upstream has merged so they can be dropped. `fork/sync --push` publishes.
- A new fix: branch from `upstream/quattro`, one atomic commit per coherent change, add it to `fork/branches` with its draft in `fork/prs/`, update the README table, run `fork/sync`.
- A change to a fix that is already merged into `quattro` goes on its topic branch as a new `fixup! <subject>` commit, never an amend, so `quattro` keeps fast-forwarding. The fixups are squashed when the pull request is opened (see `fork/prs/README.md` for the order to open them in).
- When upstream merges a fix, `fork/sync` reports it and the line comes out of `fork/branches`.

Kernel and package changes go to the packages fork, [rdoupe-omarchy/omarchy-asus-pkgs](https://github.com/rdoupe-omarchy/omarchy-asus-pkgs), one branch per change, the same way.

## Upstream's rules this fork follows (from `AGENTS.md`, `agents/skills/`, `docs/`, `.github/`)

- Upstream first: a missing or broken piece gets fixed where it belongs (kernel, NVIDIA, asusctl) and the gap stays visible meanwhile. A workaround here is a last resort, with the reason written next to the code. Kernel and driver findings go to their maintainers directly, not through this fork.
- Hardware setup lives in `install/hardware/<vendor-or-family>/`, gated by a predicate. Family-wide behaviour uses `omarchy-hw-asus-rog` (plus a Zephyrus predicate if one is needed); a single model's quirk stays behind `omarchy-hw-match` on its DMI name.
- Commands start with `omarchy-` and use the documented prefixes (`hw-`, `toggle-`, `setup-`, ...); command metadata follows `agents/skills/command-metadata.md`; new browsable groups go in `GROUP_DESCRIPTIONS` in `bin/omarchy`.
- Install and migration work follows `agents/skills/install-scripts.md` and `agents/skills/migrations.md`; existing installs get a migration.
- Bash style: `#!/bin/bash`, two-space indent, `[[ ]]` for strings and files, `(( ))` for numbers, full `if`/`else` for two-path flow, quoted paths instead of escaped spaces.
- Use the helpers: `omarchy-pkg-add`/`omarchy-pkg-drop`, `omarchy-cmd-present`/`omarchy-cmd-missing` only for optional dependencies, `omarchy-notification-send`, `$OMARCHY_PATH` (never derived from `HOME`).
- Privilege escalation follows the "Privilege Escalation" section of `default/agents/skills/omarchy/SKILL.md`.
- Long-running code reacts to events (udev, logind, inotify, Hyprland events), never a timer poll; the idle-spawn and budget tests in `docs/testing.md` must stay green.
- Tests: focused tests under `test/shell.d/*-test.sh`, `./test/all` before a pull request (in this fork run it as `fork/test`, which isolates the tests from the desktop session; see the script); visual changes are verified per `agents/skills/visual-verification.md`; graphical acceptance runs only in a disposable VM.
- Markdown in `docs/`, `manual/`, `plans/`: full lines, no hard wrapping. End-user docs go in `manual/`, internals in `docs/`.
- Issues on `omacom/omarchy` are for verified bugs only; ideas go to Discussions (Suggestions), support to Discord.
- Pull requests (from recent merges): a short imperative title that names the user-visible outcome ("Keep ...", "Fix ... on ..."); a body that states the problem, the cause, the change and how it was tested. Agent-written pull requests are accepted; say so in the body.

## Status of each fix

The table in [README.md](README.md) is the single list of fixes and where each one stands in this repo, upstream and in Omarchy. Update it in the same commit as any change to a fix.

## Evidence

Measurements, firmware analysis and test logs live in the private research repo (`g16reverse`); each pull request quotes the evidence it needs.
