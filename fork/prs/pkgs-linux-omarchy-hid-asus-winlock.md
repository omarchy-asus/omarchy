# PR draft: omacom/omarchy-pkgs: hid-asus Win-lock pass-through (NOT opened)

Branch: `rdoupe-omarchy/omarchy-asus-pkgs` `linux-omarchy-hid-asus-winlock`, commit 1f5ed441 on upstream master 4dc48ee4.
Status: hold until Jiri Kosina answers the upstream patch (linux-input patchwork 14804337, sent 2026-09-10, state "new", no replies; the whole hid-asus queue has been quiet since 2026-09-11), or about two weeks after the ping with no answer (see `~/Work/g16reverse/upstream/OMARCHY-KERNEL-ROUTE.md`). If upstream asks for changes, update 0567 to match before opening.

Do not put the upstream patchwork URL in the body: it embeds the sender's email address. Use the API link or the patch name, as the commit message does.

---

**Title:** Add hid-asus Win-lock pass-through to the base, BORE and MuQSS kernels

**Body:**

Adds `0567-hid-asus-pass-through-rog-nkey-win-lock-reports.patch` to `linux-omarchy-bore`, `linux-omarchy-eevdf` and `linux-omarchy-muqss`, right after 0566 (the other hid-asus patch).

Why: on ROG N-Key keyboards (USB `0b05:19b6`, e.g. the ROG Zephyrus G16 2025) Fn+Super locks the Windows key in the EC. While it is locked, pressing Super makes the keyboard send a lock report (`5d bf 01 01`) instead of the key. hid-asus drops every report with ID 0x5d or 0x5e as an AURA lighting echo, so the report never reaches hidraw. The key press disappears silently and nothing in userspace can tell the user why Super does nothing. The patch lets only `5d bf 01 xx` through, on the ROG N-Key Keyboard2 only. All other 0x5d and 0x5e reports stay filtered.

The filter dates from b92b80246e06 (2020, written for the first N-Key keyboard's lighting echo) and was widened in 4bfb2c72b2bf and 59d2f5b7392e to every device hid-asus drives. In USB captures on this keyboard, idle and with lighting changes, the echo was always opcode 0x0a; 0xbf appeared only as the Win-lock notify.

Upstream: "HID: asus: pass through ROG N-Key Win-lock reports", linux-input patchwork 14804337 (https://patchwork.kernel.org/api/patches/14804337/), sent 2026-09-10. [Update with the review state before opening.] The patch here is that change rebased onto 7.2.8 with 0566 applied, with the same logic. The user-facing side is Omarchy docs PR omacom/omarchy#11045 (troubleshooting entry for Fn+Super).

## What I checked

Packaging (7.2.8, all three recipes at the current `pkgrel=5`):
- All patches apply in recipe order with `--fuzz=0` on a clean `linux-7.2.8.tar.xz` (sha256 matches the recipe): 151 for BORE, 150 each for base (eevdf) and MuQSS, 0567 included. 0566 is the only other patch touching `hid-asus.c` in any of the three, and it is byte-identical across them.
- `source`, `b2sums` and `sha256sums` stay the same length in each recipe (303, 301, 301), and the new entries sit at the new patch's index. Every local patch's b2 and sha256 match its array entry.
- `tests/pinned-sources.sh` and `tests/package-metadata.sh` pass.
- `hid-asus.c` from the patched 7.2.8 tree builds as a module with `W=1` and no warnings, out of tree against the installed `7.2.5-3-omarchy` headers.
- Not done: an in-tree `make drivers/hid/hid-asus.o` (the build host lacks `bc` for `modules_prepare`), a full `makepkg`, and booting a kernel built from this PR.

Hardware (ROG Zephyrus G16 GA605KM, keyboard `0b05:19b6`, same logic built as a DKMS module on 7.2.5-3-omarchy and used daily since 2026-09): with the lock on, hidraw receives `5d bf 01 01` on Fn+Super and on each suppressed Super press, and `5d bf 01 00` on unlock. Lighting changes still produce no 0x5d traffic on hidraw.

## Notes for review
- **No `.sig`:** every other patch has a maintainer signature I can't produce, so 0567 is listed without `{,.sig}` and the recipe still builds. Please sign it and switch the entry to `0567-…patch{,.sig}`, adding the `SKIP` entries to both sums arrays.
- **No pkgrel bump:** following how patch-adding commits are done here (e.g. d06bf466), the release bump is left to the next kernel release commit.
- When the patch lands in hid `for-7.x/asus` or mainline, drop 0567 (or replace it with the merged version if it changes in review).

Written with an AI coding agent (Claude Code); I reviewed the change and ran the checks above.
